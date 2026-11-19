// SPDX-License-Identifier: GPL-2.0
/*-
 * Copyright(c) 2020-21 Intel Corporation. All rights reserved.
 */

#include "ifc_mcdma_net.h"
#include "ifc_mcdma_ioctl.h"
#include "ifc_mcdma_bas.h"

enum ifc_mcdma_pcie_mode {
	IFC_MCDMA_PCIE4_MODE = 0,
	IFC_MCDMA_PCIE5_MODE,
};

static inline bool ifc_mcdma_is_pcie5_mode(u8 pcie_mode)
{
	return pcie_mode == IFC_MCDMA_PCIE5_MODE;
}

static inline u64 ifc_mcdma_adjust_reg_offset(u8 pcie_mode, u64 offset)
{
	return ifc_mcdma_is_pcie5_mode(pcie_mode) ? offset << 1 : offset;
}

u8 ifc_mcdma_detect_pcie_mode(struct ifc_mcdma_dev_ctx *dev)
{
	u8 __iomem *base;

	if (!dev || !dev->pctx.info || !dev->pctx.info[2].iaddr ||
	    dev->pctx.info[2].size < sizeof(u32))
		return IFC_MCDMA_PCIE4_MODE;

	base = (u8 __iomem *)dev->pctx.info[2].iaddr;
	return readl(base) == IFC_PCIE5_BAR2_MAGIC ?
		IFC_MCDMA_PCIE5_MODE : IFC_MCDMA_PCIE4_MODE;
}

u32 ifc_mcdma_pio_read32_mode(struct ifc_mcdma_dev_ctx *dev,
			      uint64_t offset)
{
	u8 __iomem *base;
	u64 adjusted_offset;

	if (!dev || !dev->pctx.info || !dev->pctx.info[2].iaddr) {
		pr_err("Invalid device context or BAR2 mapping\n");
		return 0;
	}

	adjusted_offset = ifc_mcdma_adjust_reg_offset(dev->pcie_mode, offset);
	if (adjusted_offset > dev->pctx.info[2].size ||
	    dev->pctx.info[2].size - adjusted_offset < sizeof(u32)) {
		pr_err("PIO read offset 0x%llx (adjusted 0x%llx) out of range\n",
		       offset, adjusted_offset);
		return 0;
	}

	base = (u8 __iomem *)dev->pctx.info[2].iaddr;
	return readl(base + adjusted_offset);
}

static void ifc_mcdma_pio_write128(struct ifc_mcdma_dev_ctx *dev,
			 uint64_t offset, __uint128_t value)
{
	volatile __uint128_t *data;
	if (dev == NULL) {
		pr_err("Dev context is NULL\n");
		return;
	}

	/* PIO BAR base Addr*/
	data = (__uint128_t *)((char *)dev->pctx.info[2].iaddr + offset);

	*data = value;
	return;
}

static __uint128_t ifc_mcdma_pio_read128(struct ifc_mcdma_dev_ctx *qdev, uint64_t addr)
{
	volatile __uint128_t *data;
        __uint128_t temp;

        if (qdev == NULL) {
		pr_err("Dev context is NULL\n");
                return -1;
	}

        data = (__uint128_t *)((char *)(qdev->pctx.info[2].iaddr) + addr);
	temp = *data;

        return temp;
}

#if 0
static void ifc_mcdma_pio_write256(struct ifc_mcdma_dev_ctx *dev,
			 uint64_t offset, __iomem value)
{
#ifdef __AVX__
    asm volatile("vmovdqa %0,%%ymm2": :"m"(*data));

    asm volatile("vmovdqa %%ymm2,%0"
                 :"=m"(*(volatile uint8_t * __force) addr)
                 : :"memory");
#else /* !__AVX__ */
    ifc_mcdma_pio_write128(dev, offset, value);
    ifc_mcdma_pio_write128(dev, offset + 16, value + 16);
#endif /* !__AVX__ */
}
#endif


void ifc_mcdma_pio_write(struct ifc_mcdma_dev_ctx *dev,
			 uint64_t offset, uint64_t data)
{
	u8 __iomem *base = NULL;
	u32 lo = lower_32_bits(data);
	u32 hi = upper_32_bits(data);

	if (dev == NULL) {
		pr_err("Dev context is NULL\n");
		return;
	}

	/* PIO BAR base Addr*/
	base = (u8 __iomem *)dev->pctx.info[2].iaddr;
	if (offset + sizeof(u32) > dev->pctx.info[2].size) {
		pr_err("PIO write offset 0x%llx out of range\n", offset);
		return;
	}

	/*
	 * Match ifc_mcdma_pio_read(): write BAR2 registers as 32-bit MMIO
	 * words so x86 and arm64 both avoid problematic 64-bit device accesses.
	 */
	writel(lo, base + offset);
	if (offset + 2 * sizeof(u32) <= dev->pctx.info[2].size)
		writel(hi, base + offset + sizeof(u32));
}

uint64_t ifc_mcdma_pio_read(struct ifc_mcdma_dev_ctx *dev,
			    uint64_t offset)
{
	u8 __iomem *base = NULL;
	u64 lo;
	u64 hi = 0;

	if (dev == NULL) {
		pr_err("Dev context is NULL\n");
		return 0;
	}

	/* PIO BAR base Addr*/
	base = (u8 __iomem *)dev->pctx.info[2].iaddr;
	if (offset + sizeof(u32) > dev->pctx.info[2].size) {
		pr_err("PIO read offset 0x%llx out of range\n", offset);
		return 0;
	}

	/*
	 * BAR2 registers are consumed as 32-bit MMIO words in probe and ioctl
	 * paths. Using readq() on offset + 4 works on x86 but faults on arm64
	 * due to an unaligned 64-bit device access. Build a 64-bit return value
	 * from 32-bit reads instead.
	 */
	lo = readl(base + offset);
	if (offset + 2 * sizeof(u32) <= dev->pctx.info[2].size)
		hi = (u64)readl(base + offset + sizeof(u32)) << 32;

	return lo | hi;
}
static int ifc_mcdma_netdev_ioctl_common(struct net_device *netdev,
					 struct ifreq *ifr, int cmd)
{
	struct ifc_mcdma_dev_ctx *dev = NULL;
	struct ifc_mcdma_netdev_priv_data __user *u_priv = ifr->ifr_data;
	struct ifc_mcdma_netdev_priv_data k_priv;
	
	dev = netdev_priv(netdev);
	if (dev == NULL) {
		pr_err("%s: Dev context is NULL\n", netdev->name);
		return	-EFAULT;
	}

	/* Copy User space data to Kernel */
	if (copy_from_user(&k_priv, u_priv, sizeof(k_priv)))
		return -EFAULT;
	switch (cmd) {
		case IFC_MCDMA_SET_VALUE_AT:
			if (k_priv.offset > dev->pctx.info[2].size) {
				pr_err("%s: Offset out of range\n", netdev->name);
				return -EFAULT;
			}
			ifc_mcdma_pio_write(dev, k_priv.offset, k_priv.data);
		break;
		case IFC_MCDMA_SET_VALUE128_AT:
			if (k_priv.offset > dev->pctx.info[2].size) {
				pr_err("%s: Offset out of range\n", netdev->name);
				return -EFAULT;
			}
			ifc_mcdma_pio_write128(dev, k_priv.offset, k_priv.data128);
		break;
#if 0
		case IFC_MCDMA_SET_VALUE256_AT:
			ifc_mcdma_pio_write256(dev, k_priv.offset, k_priv.data256);
		break;
#endif
		case IFC_MCDMA_GET_VALUE_AT:
			if (k_priv.offset > dev->pctx.info[2].size) {
				pr_err("%s: Offset out of range\n", netdev->name);
				return -EFAULT;
			}
		 	k_priv.data = ifc_mcdma_pio_read(dev, k_priv.offset);

			/* Copy Kernel space data to User space */
			if (copy_to_user(u_priv, &k_priv, sizeof(u_priv))) {
				pr_err("%s: Failed to copy data to user space\n",
					netdev->name);
				return -EFAULT;
			}
		break;
		case IFC_MCDMA_GET_VALUE128_AT:
			if (k_priv.offset > dev->pctx.info[2].size) {
				pr_err("%s: Offset out of range\n", netdev->name);
				return -EFAULT;
			}
			k_priv.data128 = ifc_mcdma_pio_read128(dev, k_priv.offset);

			/* Copy Kernel space data to User space */
			if (copy_to_user(u_priv, &k_priv, sizeof(struct ifc_mcdma_netdev_priv_data))) {
				pr_err("%s: Failed to copy data to user space\n",
					netdev->name);
				return -EFAULT;
			}
		break;
		case IFC_MCDMA_BAS_TX:
			ifc_bas_transfer_handler(IFC_MCDMA_DIR_TX, dev, &k_priv);
		break;
		case IFC_MCDMA_BAS_RX:
			ifc_bas_transfer_handler(IFC_MCDMA_DIR_RX, dev, &k_priv);
		break;
		default:
			pr_err("%s: Invalid IOCTL command\n", netdev->name);
			return -EFAULT;
		break;
	}

	return 0;
}

int ifc_mcdma_netdev_ioctl(struct net_device *netdev, struct ifreq *ifr,
			   int cmd)
{
	return ifc_mcdma_netdev_ioctl_common(netdev, ifr, cmd);
}

#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 15, 0)
int ifc_mcdma_netdev_siocdevprivate(struct net_device *netdev,
				    struct ifreq *ifr, void __user *data,
				    int cmd)
{
	(void)data;
	return ifc_mcdma_netdev_ioctl_common(netdev, ifr, cmd);
}
#endif
