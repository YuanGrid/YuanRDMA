#include <stdint.h>
#include <unistd.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/fcntl.h>
#include <rte_memzone.h>
#include <rte_string_fns.h>
//#include <ethdev_pci.h>
#ifndef DPDK_21_11_RC2
#include <rte_ethdev_pci.h>
#else
#include <ethdev_pci.h>
#endif
#include <rte_malloc.h>
#include <rte_dev.h>
#include <rte_pci.h>
#include <rte_ether.h>
#include <rte_ethdev.h>
#include <net/ethernet.h>
#include <rte_alarm.h>
#include <rte_cycles.h>
#include <rte_atomic.h>
#include <rte_mbuf.h>
#include <rte_mempool.h>
#include <rte_common.h>
#include <rte_hexdump.h>
#include <rte_spinlock.h>
//#include <rte_log.h>
//#include <rte_pmd.h>

//#include <rte_vfio.h>
//#include <sys/ioctl.h>
//#include <sys/eventfd.h>
#include <mcdma_ip_params.h>
#include <pio_reg_registers.h>

#include "mcdma_regs.h"
#include "rte_pmd_mcdma.h"
#include "mcdma_dca.h"

#include "mcdma_platform.h"
#include "mcdma_rss.h"

static inline uint64_t
mcdma_rss_reg_offset(const struct ifc_mcdma_device *dma_priv, uint64_t offset)
{
	return dma_priv->pcie_mode ? (offset << 1) : offset;
}

static inline uint32_t
mcdma_rss_read32(const struct ifc_mcdma_device *dma_priv, uint64_t offset)
{
	return ifc_readl((void *)((uint64_t)dma_priv->bar_addr[IFC_MCDMA_PIO_BAR] +
		mcdma_rss_reg_offset(dma_priv, offset)));
}

static inline void
mcdma_rss_write32(const struct ifc_mcdma_device *dma_priv, uint64_t offset,
		uint32_t value)
{
	ifc_writel((void *)((uint64_t)dma_priv->bar_addr[IFC_MCDMA_PIO_BAR] +
		mcdma_rss_reg_offset(dma_priv, offset)), value);
}


/**
 * DPDK callback to update the RETA indirection table.
 * Code like mlx5_dev_rss_reta_update
 *
 * @param dev
 *   Pointer to Ethernet device structure.
 * @param reta_conf
 *   Pointer to RETA configuration structure array.
 * @param reta_size
 *   Size of the RETA table.
 *
 * @return
 *   0 on success, a negative errno value otherwise and rte_errno is set.
 */
int
mcdma_dev_rss_reta_update(struct rte_eth_dev *dev,
	struct rte_eth_rss_reta_entry64 *reta_conf, uint16_t reta_size)
{
	uint32_t i, idx, pos, val, func_id;
	struct rte_pci_device *pci_dev;
	struct ifc_mcdma_device *dma_priv;

	pci_dev = RTE_ETH_DEV_TO_PCI(dev);
	if (pci_dev == NULL)
		return -EINVAL;

	dma_priv = (struct ifc_mcdma_device *)dev->data->dev_private;

	if (!reta_size) {
		rte_errno = EINVAL;
		return -rte_errno;
	}

	/*
	 * 0x1400	0x0400		RW		RSS indirection table
	 * 0x15FF	0x05FF				31:16 - reserved; 15:0 - queue ID at index
	 * qdma_pci_read_reg/qdma_pci_write_reg
	 */
	func_id = pci_dev->addr.function;

	for (i = 0; i < reta_size; i++) {

		idx = i / RTE_ETH_RETA_GROUP_SIZE;
		pos = i % RTE_ETH_RETA_GROUP_SIZE;

		val = mcdma_rss_read32(dma_priv, MCDMA_SUBSYSTEM_RSSTABLE(func_id) + i * 4);

		val &= 0xFFFF0000;
		val |= reta_conf[idx].reta[pos];

		mcdma_rss_write32(dma_priv, MCDMA_SUBSYSTEM_RSSTABLE(func_id) + i * 4, val);
	}
	PMD_DRV_LOG(INFO, "func_id %d, reta_size %d,addr=%p\n",  func_id, reta_size,dma_priv->bar_addr[IFC_MCDMA_PIO_BAR]);

	return 0;
}

/**
 * DPDK callback to get the RETA indirection table.
 *
 * @param dev
 *   Pointer to Ethernet device structure.
 * @param reta_conf
 *   Pointer to RETA configuration structure array.
 * @param reta_size
 *   Size of the RETA table.
 *
 * @return
 *   0 on success, a negative errno value otherwise and rte_errno is set.
 */
int
mcdma_dev_rss_reta_query(struct rte_eth_dev *dev,
	struct rte_eth_rss_reta_entry64 *reta_conf, uint16_t reta_size)
{
	uint32_t i, idx, pos, val, func_id;
	struct rte_pci_device *pci_dev;
	struct ifc_mcdma_device *dma_priv;

	pci_dev = RTE_ETH_DEV_TO_PCI(dev);
	if (pci_dev == NULL)
		return -EINVAL;

	dma_priv = (struct ifc_mcdma_device *)dev->data->dev_private;

	if (!reta_size || reta_size > MCDMA_RSS_RETA_SIZE) {
		rte_errno = EINVAL;
		return -rte_errno;
	}

	func_id = pci_dev->addr.function;

	/* Fill each entry of the table even if its bit is not set. */
	for (idx = 0, i = 0; (i != reta_size); ++i) {

		idx = i / RTE_ETH_RETA_GROUP_SIZE;
		pos = i % RTE_ETH_RETA_GROUP_SIZE;

		val = mcdma_rss_read32(dma_priv, MCDMA_SUBSYSTEM_RSSTABLE(func_id) + i * 4);

		reta_conf[idx].reta[pos] = (uint16_t)val;
	}

	PMD_DRV_LOG(INFO, "func_id %d, reta size %d, MCDMA_RSS_RETA_SIZE %d\n",
		func_id, reta_size, MCDMA_RSS_RETA_SIZE);

	return 0;
}

/**
 * DPDK callback to update the RSS hash configuration.
 * Code like qdma_rss_hash_update
 *
 * @param dev
 *   Pointer to Ethernet device structure.
 * @param[in] rss_conf
 *   RSS configuration data.
 *
 * @return
 *   0 on success, a negative errno value otherwise and rte_errno is set.
 */
int
mcdma_dev_rss_hash_update(struct rte_eth_dev *dev, struct rte_eth_rss_conf *rss_conf)
{
	/*
	 * 0x1600	0x0600		RW		RSS hash key
	 * 0x1627	0x0627
	 * qdma_pci_read_reg/qdma_pci_write_reg
	 */
	uint32_t i, val, func_id;
	struct rte_pci_device *pci_dev;
	struct ifc_mcdma_device *dma_priv;

	pci_dev = RTE_ETH_DEV_TO_PCI(dev);
	if (pci_dev == NULL)
		return -EINVAL;

	dma_priv = (struct ifc_mcdma_device *)dev->data->dev_private;
	func_id = pci_dev->addr.function;

	if (rss_conf->rss_key && rss_conf->rss_key_len) {
		for(i = 0; i < rss_conf->rss_key_len; i+=4) {
			val = rss_conf->rss_key[i];
			val |= ((uint32_t)rss_conf->rss_key[i+1]) << 8;
			val |= ((uint32_t)rss_conf->rss_key[i+2]) << 16;
			val |= ((uint32_t)rss_conf->rss_key[i+3]) << 24;
			mcdma_rss_write32(dma_priv, MCDMA_SUBSYSTEM_RSSHASHKEY(func_id) + i, val);
		}
	}

	PMD_DRV_LOG(INFO, "func_id %d, rss_key_len %d\n",
		 func_id, rss_conf->rss_key_len);

	return 0;
}

/**
 * DPDK callback to get the RSS hash configuration.
 *
 * @param dev
 *   Pointer to Ethernet device structure.
 * @param[in, out] rss_conf
 *   RSS configuration data.
 *
 * @return
 *   0 on success, a negative errno value otherwise and rte_errno is set.
 */
int
mcdma_dev_rss_hash_conf_get(struct rte_eth_dev *dev, struct rte_eth_rss_conf *rss_conf)
{
	uint32_t i, val;
	uint16_t func_id;
	struct rte_pci_device *pci_dev;
	struct ifc_mcdma_device *dma_priv;

	pci_dev = RTE_ETH_DEV_TO_PCI(dev);
	if (pci_dev == NULL)
		return -EINVAL;

	dma_priv = (struct ifc_mcdma_device *)dev->data->dev_private;

	if (!rss_conf) {
		rte_errno = EINVAL;
		return -rte_errno;
	}

	if (rss_conf->rss_key && (rss_conf->rss_key_len >= MCDMA_RSS_KEY_SIZE)) {

		func_id = pci_dev->addr.function;

		rss_conf->rss_key_len = MCDMA_RSS_KEY_SIZE;
		rss_conf->rss_hf = RTE_ETH_RSS_IP | RTE_ETH_RSS_TCP | RTE_ETH_RSS_UDP;

		for (i = 0; i < MCDMA_RSS_KEY_SIZE; i+=4) {
			val = mcdma_rss_read32(dma_priv, MCDMA_SUBSYSTEM_RSSHASHKEY(func_id) + i);
			rss_conf->rss_key[i] = (uint8_t)(val & 0xff);
			rss_conf->rss_key[i+1] = (uint8_t)((val >> 8) & 0xff);
			rss_conf->rss_key[i+2] = (uint8_t)((val >> 16) & 0xff);
			rss_conf->rss_key[i+3] = (uint8_t)((val >> 24) & 0xff);
		}

	} else {
		rss_conf->rss_hf = 0;
		rss_conf->rss_key_len = 0;
	}

	PMD_DRV_LOG(INFO, "func_id %d, rss_hf 0x%lX, rss_key_len %d\n",
		 pci_dev->addr.function, rss_conf->rss_hf, rss_conf->rss_key_len);

	return 0;
}
