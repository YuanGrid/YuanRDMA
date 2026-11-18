// SPDX-License-Identifier: GPL-2.0
/*-
 * Copyright(c) 2020-21 Intel Corporation. All rights reserved.
 */

#include <linux/version.h>
#include "ifc_mcdma_net.h"
#include "ifc_mcdma_ethtool.h"
#include "ifc_mcdma_bas.h"

struct kernel_ethtool_ringparam;

#define IFC_ETHTOOL_OP_TYPE(member) typeof(((struct ethtool_ops *)0)->member)
#define IFC_GET_RINGPARAM_EXTACK_TYPE \
	void (*)(struct net_device *, struct ethtool_ringparam *, \
		 struct kernel_ethtool_ringparam *, struct netlink_ext_ack *)
#define IFC_SET_RINGPARAM_EXTACK_TYPE \
	int (*)(struct net_device *, struct ethtool_ringparam *, \
		struct kernel_ethtool_ringparam *, struct netlink_ext_ack *)
#define IFC_SELECT_ETHTOOL_OP(member, extack_type, extack_fn, legacy_fn) \
	((IFC_ETHTOOL_OP_TYPE(member))__builtin_choose_expr( \
		__builtin_types_compatible_p(IFC_ETHTOOL_OP_TYPE(member), \
					     extack_type), \
		extack_fn, legacy_fn))

#ifdef __BIG_ENDIAN
#define __BYTE_ORDER __BIG_ENDIAN
#else
#define __BYTE_ORDER __LITTLE_ENDIAN
#endif
#include "ynic_net_base.h"

static int ifc_mcdma_reconfigure_queues(struct net_device *netdev, u32 new_cnt)
{
	struct ifc_mcdma_dev_ctx *dev_ctx = netdev_priv(netdev);
	u32 old_cnt = dev_ctx->chnl_cnt;
	u32 old_rx_cnt = dev_ctx->rx_chnl_cnt;
	u32 old_tx_cnt = dev_ctx->tx_chnl_cnt;
	u32 i;
	int ret;

	if (!netif_running(netdev)) {
		dev_ctx->rx_chnl_cnt = new_cnt;
		dev_ctx->tx_chnl_cnt = new_cnt;
		dev_ctx->chnl_cnt = new_cnt;
		for (i = 0; i < IFC_MCDMA_RSS_INDIR_SIZE; i++)
			dev_ctx->rss_indir_table[i] = i % new_cnt;

		ret = netif_set_real_num_tx_queues(netdev, new_cnt);
		if (ret)
			goto restore_counts;

		ret = netif_set_real_num_rx_queues(netdev, new_cnt);
		if (ret) {
			netif_set_real_num_tx_queues(netdev, old_cnt);
			goto restore_counts;
		}
		return 0;
	}

	pr_info("%s: Stopping all queues\n", netdev->name);
	netif_tx_stop_all_queues(netdev);
	pr_info("%s: Freeing all queue contexts\n", netdev->name);
	ifc_mcdma_chnl_free_all(dev_ctx);

	dev_ctx->rx_chnl_cnt = new_cnt;
	dev_ctx->tx_chnl_cnt = new_cnt;
	dev_ctx->chnl_cnt = new_cnt;
	for (i = 0; i < IFC_MCDMA_RSS_INDIR_SIZE; i++)
		dev_ctx->rss_indir_table[i] = i % new_cnt;

	ret = netif_set_real_num_tx_queues(netdev, new_cnt);
	if (ret)
		goto restore_counts;
	ret = netif_set_real_num_rx_queues(netdev, new_cnt);
	if (ret)
		goto restore_tx_queues;

	ret = ifc_core_rebuild_all(dev_ctx);
	if (ret)
		goto restore_real_queues;

	ret = ifc_mcdma_chnl_init_all(dev_ctx);
	if (ret < 0)
		goto restore_core_map;

	ifc_mcdma_hw_write_reta(dev_ctx);
	ifc_mcdma_hw_write_rss_key(dev_ctx);
	return 0;

restore_core_map:
	ifc_core_free_all(dev_ctx);
restore_real_queues:
	netif_set_real_num_rx_queues(netdev, old_cnt);
restore_tx_queues:
	netif_set_real_num_tx_queues(netdev, old_cnt);
restore_counts:
	dev_ctx->rx_chnl_cnt = old_rx_cnt;
	dev_ctx->tx_chnl_cnt = old_tx_cnt;
	dev_ctx->chnl_cnt = old_cnt;
	for (i = 0; i < IFC_MCDMA_RSS_INDIR_SIZE; i++)
		dev_ctx->rss_indir_table[i] = i % old_cnt;

	if (netif_running(netdev)) {
		ifc_core_rebuild_all(dev_ctx);
		if (ifc_mcdma_chnl_init_all(dev_ctx) < 0) {
			pr_err("%s: failed to restore old queues after reconfigure error\n",
			       netdev->name);
		} else {
			ifc_mcdma_hw_write_reta(dev_ctx);
			ifc_mcdma_hw_write_rss_key(dev_ctx);
		}
	}

	return ret ? ret : -EFAULT;
}

u32 ifc_mcdma_get_msglevel(struct net_device *netdev)
{
	struct ifc_mcdma_dev_ctx *dev_ctx = netdev_priv(netdev);
	return dev_ctx->msg_enable;
}

void ifc_mcdma_set_msglevel(struct net_device *netdev, u32 data)
{
	struct ifc_mcdma_dev_ctx *dev_ctx = netdev_priv(netdev);
	dev_ctx->msg_enable = data;
}

void ifc_mcdma_get_drvinfo(struct net_device *dev,
					      struct ethtool_drvinfo *info)
{

	struct ifc_mcdma_dev_ctx *dev_ctx = netdev_priv(dev);
	struct pci_dev *pdev;

	pdev = dev_ctx->pctx.pdev;
	#if LINUX_VERSION_CODE >= KERNEL_VERSION(6,8,0)
		strscpy(info->driver, DRV_SUMMARY, sizeof(info->driver));
		strscpy(info->version, DRV_VERSION, sizeof(info->version));
		snprintf(info->bus_info, sizeof(info->bus_info) - 1, "%s", pci_name(pdev));
	#else
		strlcpy(info->driver, DRV_SUMMARY, sizeof(info->driver));
		strlcpy(info->version, DRV_VERSION, sizeof(info->version));
		snprintf(info->bus_info, sizeof(info->bus_info) - 1, "%s", pci_name(pdev));
	#endif
}

static void ifc_mcdma_get_ringparam_common(struct net_device *netdev,
					   struct ethtool_ringparam *ring)
{
        struct ifc_mcdma_dev_ctx *dev_ctx = netdev_priv(netdev);

	if (dev_ctx == NULL) {
		netdev_err(netdev, "Invalid device context\n");
		return;
	}

        ring->rx_max_pending = IFC_MCDMA_MAX_DESC;
        ring->tx_max_pending = IFC_MCDMA_MAX_DESC;
        ring->rx_pending = dev_ctx->num_of_pages * 128;
        ring->tx_pending = dev_ctx->num_of_pages * 128;;

        ring->rx_mini_max_pending = 0;
        ring->rx_jumbo_max_pending = 0;
        ring->rx_mini_pending = 0;
        ring->rx_jumbo_pending = 0;
}

static void ifc_mcdma_get_ringparam_legacy(struct net_device *netdev,
					   struct ethtool_ringparam *ring)
{
	ifc_mcdma_get_ringparam_common(netdev, ring);
}

static void ifc_mcdma_get_ringparam_extack(struct net_device *netdev,
					   struct ethtool_ringparam *ring,
					   struct kernel_ethtool_ringparam *kernel_ring,
					   struct netlink_ext_ack *extack)
{
	(void)kernel_ring;
	(void)extack;
	ifc_mcdma_get_ringparam_common(netdev, ring);
}

static int ifc_mcdma_set_ringparam_common(struct net_device *netdev,
					  struct ethtool_ringparam *ring)
{
	struct ifc_mcdma_dev_ctx *dev_ctx;
	u32 old_pages;
	int ret;

        if (ring->tx_pending > IFC_MCDMA_MAX_DESC ||
            ring->tx_pending < IFC_MCDMA_MIN_DESC ||
            ring->rx_pending > IFC_MCDMA_MAX_DESC ||
            ring->rx_pending < IFC_MCDMA_MIN_DESC) {
                netdev_err(netdev, "Descriptors requested (Tx: %d / Rx: %d) out of range: Range [%d-%d]\n",
                           ring->tx_pending, ring->rx_pending,
                           IFC_MCDMA_MIN_DESC, IFC_MCDMA_MAX_DESC);
                return -EINVAL;
        }

	dev_ctx = netdev_priv(netdev);
	if (dev_ctx == NULL) {
                pr_err("%s: dev_ctx NULL\n", netdev->name);
                return  -EFAULT;
        }

	if (ring->tx_pending % 128)
                return  -EFAULT;

	old_pages = dev_ctx->num_of_pages;
	dev_ctx->num_of_pages = ring->tx_pending / 128;

	if (!netif_running(netdev)) {
                pr_info("%s: Ring parameters updated pages:%u\n", netdev->name,
			dev_ctx->num_of_pages);
		return 0;
	}

	ret = ifc_mcdma_reconfigure_queues(netdev, dev_ctx->chnl_cnt);
	if (ret < 0) {
		dev_ctx->num_of_pages = old_pages;
                pr_err("%s: Channel re-initialization failed for new ring size\n",
		       netdev->name);
		return ret;
	}

        pr_info("%s: Ring parameters updated pages:%u\n", netdev->name,
		dev_ctx->num_of_pages);
	return 0;
}

static int ifc_mcdma_set_ringparam_legacy(struct net_device *netdev,
					  struct ethtool_ringparam *ring)
{
	return ifc_mcdma_set_ringparam_common(netdev, ring);
}

static int ifc_mcdma_set_ringparam_extack(struct net_device *netdev,
					  struct ethtool_ringparam *ring,
					  struct kernel_ethtool_ringparam *kernel_ring,
					  struct netlink_ext_ack *extack)
{
	(void)kernel_ring;
	(void)extack;
	return ifc_mcdma_set_ringparam_common(netdev, ring);
}

static void
ifc_mcdma_get_channels(struct net_device *dev, struct ethtool_channels *ch)
{
	struct ifc_mcdma_dev_ctx *dev_ctx = netdev_priv(dev);

	ch->max_combined = dev_ctx->tot_chnl_avl;
	ch->combined_count = dev_ctx->chnl_cnt;
}

static int
ifc_mcdma_set_channels(struct net_device *dev, struct ethtool_channels *ch)
{
	struct ifc_mcdma_dev_ctx *dev_ctx = netdev_priv(dev);
	u32 new_cnt;
	int ret;

	/*
	 * ethtool first reads current channels via get_channels, then modifies
	 * only the specified fields and sends the full struct back.
	 *
	 * -L combined N  -> combined_count=N, rx_count=0, tx_count=0
	 * -L rx N tx N   -> combined_count=<old>, rx_count=N, tx_count=N
	 *
	 * Prefer rx/tx when both are explicitly set (non-zero and equal),
	 * fall back to combined_count otherwise.
	 */
	if (ch->rx_count && ch->tx_count && ch->rx_count == ch->tx_count)
		new_cnt = ch->rx_count;
	else if (ch->combined_count)
		new_cnt = ch->combined_count;
	else
		return -EINVAL;

	if (new_cnt == 0 || new_cnt > dev_ctx->tot_chnl_avl) {
		pr_err("%s: invalid channel count %u (max %u)\n",
		       dev->name, new_cnt, dev_ctx->tot_chnl_avl);
		return -EINVAL;
	}

	if (new_cnt == dev_ctx->chnl_cnt)
		return 0;

	ret = ifc_mcdma_reconfigure_queues(dev, new_cnt);
	if (ret < 0)
		pr_err("%s: channel re-init failed after set_channels\n", dev->name);

	return ret;
}


static u32 ifc_mcdma_get_link(struct net_device *netdev)
{
	u32 val = 0;
	u16 link = 0;
	int func_id = 0;
	struct ifc_mcdma_dev_ctx *dev_ctx = netdev_priv(netdev);
	struct pci_dev *pdev;

	pdev = dev_ctx->pctx.pdev;
	func_id = PCI_FUNC(pdev->devfn);
	val = ifc_mcdma_pio_read32_mode(dev_ctx, IFC_MCDMA_BAS_ETH_STATUS);
	link = val & 0x1;

	//netdev_info(netdev, "ethtool: ifc_get_link port: %d   link: %u\r\n", func_id, link);
	return link;
}


static int ifc_mcdma_get_link_ksettings(struct net_device *netdev,
                struct ethtool_link_ksettings *cmd)
{
	struct ifc_mcdma_dev_ctx *dev_ctx = netdev_priv(netdev);
	struct pci_dev *pdev;
	uint32_t model = 0,speed = 0;
	uint8_t type = 0;
	//uint32_t asta = 0;
	//uint8_t autoneg = 0;
	int func_id = 0;

	pdev = dev_ctx->pctx.pdev;
	memset(&cmd->link_modes, 0, sizeof(cmd->link_modes));

	ethtool_link_ksettings_zero_link_mode(cmd, supported);
	ethtool_link_ksettings_zero_link_mode(cmd, advertising);


	ethtool_link_ksettings_add_link_mode(cmd, supported, FIBRE);
	ethtool_link_ksettings_add_link_mode(cmd, advertising, FIBRE);
	cmd->base.port = PORT_FIBRE;

	model = ifc_mcdma_pio_read32_mode(dev_ctx,
		IFC_BASE_OFFSET + IFC_MODEL_REG);
	speed = ifc_mcdma_pio_read32_mode(dev_ctx,
		IFC_BASE_OFFSET + IFC_PORT_SPEED_REG);
	type = (model >> 12) & 0xf;
	if(type == CARD_10G) {
		ethtool_link_ksettings_add_link_mode(cmd, supported, 10000baseT_Full);
		ethtool_link_ksettings_add_link_mode(cmd, advertising, 10000baseT_Full);
	} else if(type == CARD_25G) {
		ethtool_link_ksettings_add_link_mode(cmd, supported, 25000baseCR_Full);
		ethtool_link_ksettings_add_link_mode(cmd, advertising, 25000baseCR_Full);
		ethtool_link_ksettings_add_link_mode(cmd, supported, 10000baseT_Full);
		ethtool_link_ksettings_add_link_mode(cmd, advertising, 10000baseT_Full);
	} else if(type == CARD_100G) {
		ethtool_link_ksettings_add_link_mode(cmd, supported, 100000baseCR_Full);
		ethtool_link_ksettings_add_link_mode(cmd, advertising, 100000baseCR_Full);
		ethtool_link_ksettings_add_link_mode(cmd, supported, 50000baseCR_Full);
		ethtool_link_ksettings_add_link_mode(cmd, advertising, 50000baseCR_Full);
		//ethtool_link_ksettings_add_link_mode(cmd, supported, 40000baseCR_Full);
		//ethtool_link_ksettings_add_link_mode(cmd, supported, 40000baseCR_Full);
		ethtool_link_ksettings_add_link_mode(cmd, supported, 10000baseT_Full);
		ethtool_link_ksettings_add_link_mode(cmd, advertising, 10000baseT_Full);
	} else if(type == CARD_400G) {
		ethtool_link_ksettings_add_link_mode(cmd, supported, 400000baseCR4_Full);
		ethtool_link_ksettings_add_link_mode(cmd, advertising, 400000baseCR4_Full);
		ethtool_link_ksettings_add_link_mode(cmd, supported, 200000baseCR4_Full);
		ethtool_link_ksettings_add_link_mode(cmd, advertising, 200000baseCR4_Full);
		ethtool_link_ksettings_add_link_mode(cmd, supported, 100000baseCR_Full);
		ethtool_link_ksettings_add_link_mode(cmd, advertising, 100000baseCR_Full);
		ethtool_link_ksettings_add_link_mode(cmd, supported, 50000baseCR_Full);
		ethtool_link_ksettings_add_link_mode(cmd, advertising, 50000baseCR_Full);
	} else {
		ethtool_link_ksettings_add_link_mode(cmd, supported, 10000baseT_Full);
		ethtool_link_ksettings_add_link_mode(cmd, advertising, 10000baseT_Full);
	}


	//ethtool_link_ksettings_add_link_mode(cmd, supported, Pause);
	//ethtool_link_ksettings_add_link_mode(cmd, advertising, Pause);


	/* Set supported and advertised autoneg */
	//ethtool_link_ksettings_add_link_mode(cmd, supported, Autoneg);
	//ethtool_link_ksettings_add_link_mode(cmd, advertising, Autoneg);
	//Auto-negotiation
	func_id = PCI_FUNC(pdev->devfn);
#if 0
		asta = ifc_mcdma_pio_read(dev_ctx, IFC_AUNE_REG);
	autoneg = asta & 0x1;
	if(autoneg)
		cmd->base.autoneg = AUTONEG_ENABLE;
	else
		cmd->base.autoneg = AUTONEG_DISABLE;
#else
	cmd->base.autoneg = AUTONEG_DISABLE;
#endif

	ethtool_link_ksettings_del_link_mode(cmd, supported, Pause);
	ethtool_link_ksettings_del_link_mode(cmd, supported, Asym_Pause);

	/* Set supported FEC modes based on PHY capability */
    ethtool_link_ksettings_add_link_mode(cmd, supported, FEC_RS);
    ethtool_link_ksettings_add_link_mode(cmd, advertising, FEC_RS);

	// 设置其他参数，例如速度、双工模式等
	if(speed == MD_LINK_SPEED_10G) {
		cmd->base.speed = SPEED_10000;
	} else if(speed == MD_LINK_SPEED_25G) {
		cmd->base.speed = SPEED_25000;
	} else if(speed == MD_LINK_SPEED_40G) {
		cmd->base.speed = SPEED_40000;
	} else if(speed == MD_LINK_SPEED_50G) {
		cmd->base.speed = SPEED_50000;
	} else if(speed == MD_LINK_SPEED_100G) {
		cmd->base.speed = SPEED_100000;
	} else if(speed == MD_LINK_SPEED_200G) {
		cmd->base.speed = SPEED_200000;
	} else if(speed == MD_LINK_SPEED_400G) {
		cmd->base.speed = SPEED_400000;
	} else if(speed == MD_LINK_SPEED_1G) {
		cmd->base.speed = SPEED_1000;
	} else {
		cmd->base.speed = SPEED_UNKNOWN;
	}
	cmd->base.duplex = DUPLEX_FULL; // 假设为全双工

	//cmd->base.phy_address = 0;         // PHYAD: 0
	//cmd->base.transceiver = XCVR_INTERNAL;

	return 0;
}

static int ifc_mcdma_get_fecparam(struct net_device *netdev,
                                  struct ethtool_fecparam *fec)
{
	struct ifc_mcdma_dev_ctx *dev_ctx = netdev_priv(netdev);
	struct pci_dev *pdev;
	//u32 val = 0;
	u32 speed = 0;

	pdev = dev_ctx->pctx.pdev;

	speed = ifc_mcdma_pio_read32_mode(dev_ctx,
		IFC_BASE_OFFSET + IFC_PORT_SPEED_REG);
	if((speed != MD_LINK_SPEED_100G) && (speed != MD_LINK_SPEED_200G) && \
		(speed != MD_LINK_SPEED_400G)) {
		//dev_err(&(pdev->dev), "Network Card mode not support fec.");
		return -1;
	}

	/* FEC is always enabled (RS-FEC) */
	fec->fec = ETHTOOL_FEC_RS;
	fec->active_fec = ETHTOOL_FEC_RS;

	return 0;
}

static int ifc_mcdma_set_fecparam(struct net_device *netdev,
                        struct ethtool_fecparam *fecparam)
{
	struct ifc_mcdma_dev_ctx *dev_ctx = netdev_priv(netdev);
	struct pci_dev *pdev;

	pdev = dev_ctx->pctx.pdev;

	/* FEC is forced on and cannot be modified */
	//dev_info(&(pdev->dev), "FEC is forced enabled (RS-FEC) and cannot be changed");
	return -EOPNOTSUPP;
}

static int ifc_mcdma_get_rxnfc(struct net_device *netdev,
			       struct ethtool_rxnfc *info, u32 *rules)
{
	struct ifc_mcdma_dev_ctx *dev_ctx = netdev_priv(netdev);

	switch (info->cmd) {
	case ETHTOOL_GRXRINGS:
		info->data = dev_ctx->chnl_cnt;
		return 0;
	default:
		return -EOPNOTSUPP;
	}
}

static u32 ifc_mcdma_get_rxfh_indir_size(struct net_device *netdev)
{
	return IFC_MCDMA_RSS_INDIR_SIZE;
}

static u32 ifc_mcdma_get_rxfh_key_size(struct net_device *netdev)
{
	return IFC_MCDMA_RSS_KEY_SIZE;
}

#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 8, 0)
static int ifc_mcdma_get_rxfh(struct net_device *netdev,
			       struct ethtool_rxfh_param *rxfh)
{
	struct ifc_mcdma_dev_ctx *dev_ctx = netdev_priv(netdev);

	rxfh->hfunc = ETH_RSS_HASH_TOP;
	if (rxfh->indir)
		memcpy(rxfh->indir, dev_ctx->rss_indir_table,
		       IFC_MCDMA_RSS_INDIR_SIZE * sizeof(u32));
	if (rxfh->key)
		memcpy(rxfh->key, dev_ctx->rss_key, IFC_MCDMA_RSS_KEY_SIZE);
	return 0;
}

static int ifc_mcdma_set_rxfh(struct net_device *netdev,
			       struct ethtool_rxfh_param *rxfh,
			       struct netlink_ext_ack *extack)
{
	struct ifc_mcdma_dev_ctx *dev_ctx = netdev_priv(netdev);
	u32 i;

	if (rxfh->hfunc != ETH_RSS_HASH_NO_CHANGE &&
	    rxfh->hfunc != ETH_RSS_HASH_TOP)
		return -EOPNOTSUPP;

	if (rxfh->indir) {
		for (i = 0; i < IFC_MCDMA_RSS_INDIR_SIZE; i++) {
			if (rxfh->indir[i] >= dev_ctx->chnl_cnt)
				return -EINVAL;
		}
		memcpy(dev_ctx->rss_indir_table, rxfh->indir,
		       IFC_MCDMA_RSS_INDIR_SIZE * sizeof(u32));
		ifc_mcdma_hw_write_reta(dev_ctx);
	}

	if (rxfh->key) {
		memcpy(dev_ctx->rss_key, rxfh->key, IFC_MCDMA_RSS_KEY_SIZE);
		ifc_mcdma_hw_write_rss_key(dev_ctx);
	}
	return 0;
}
#else
static int ifc_mcdma_get_rxfh(struct net_device *netdev, u32 *indir,
			       u8 *key, u8 *hfunc)
{
	struct ifc_mcdma_dev_ctx *dev_ctx = netdev_priv(netdev);

	if (hfunc)
		*hfunc = ETH_RSS_HASH_TOP;
	if (indir)
		memcpy(indir, dev_ctx->rss_indir_table,
		       IFC_MCDMA_RSS_INDIR_SIZE * sizeof(u32));
	if (key)
		memcpy(key, dev_ctx->rss_key, IFC_MCDMA_RSS_KEY_SIZE);
	return 0;
}

static int ifc_mcdma_set_rxfh(struct net_device *netdev, const u32 *indir,
			       const u8 *key, const u8 hfunc)
{
	struct ifc_mcdma_dev_ctx *dev_ctx = netdev_priv(netdev);
	u32 i;

	if (hfunc != ETH_RSS_HASH_NO_CHANGE &&
	    hfunc != ETH_RSS_HASH_TOP)
		return -EOPNOTSUPP;

	if (indir) {
		for (i = 0; i < IFC_MCDMA_RSS_INDIR_SIZE; i++) {
			if (indir[i] >= dev_ctx->chnl_cnt)
				return -EINVAL;
		}
		memcpy(dev_ctx->rss_indir_table, indir,
		       IFC_MCDMA_RSS_INDIR_SIZE * sizeof(u32));
		ifc_mcdma_hw_write_reta(dev_ctx);
	}

	if (key) {
		memcpy(dev_ctx->rss_key, key, IFC_MCDMA_RSS_KEY_SIZE);
		ifc_mcdma_hw_write_rss_key(dev_ctx);
	}
	return 0;
}
#endif

const struct ethtool_ops ifc_mcdma_ethtool_ops = {
	.get_msglevel		= ifc_mcdma_get_msglevel,
	.set_msglevel		= ifc_mcdma_set_msglevel,
	.get_drvinfo        = ifc_mcdma_get_drvinfo,
	.get_ts_info		= ethtool_op_get_ts_info,
	.get_link		    = ifc_mcdma_get_link,
	.get_channels       = ifc_mcdma_get_channels,
	.set_channels       = ifc_mcdma_set_channels,
	.get_ringparam      = IFC_SELECT_ETHTOOL_OP(get_ringparam,
						    IFC_GET_RINGPARAM_EXTACK_TYPE,
						    ifc_mcdma_get_ringparam_extack,
						    ifc_mcdma_get_ringparam_legacy),
	.set_ringparam      = IFC_SELECT_ETHTOOL_OP(set_ringparam,
						    IFC_SET_RINGPARAM_EXTACK_TYPE,
						    ifc_mcdma_set_ringparam_extack,
						    ifc_mcdma_set_ringparam_legacy),
    .get_link_ksettings = ifc_mcdma_get_link_ksettings,
    .get_fecparam       = ifc_mcdma_get_fecparam,
    .set_fecparam       = ifc_mcdma_set_fecparam,
	.get_rxnfc           = ifc_mcdma_get_rxnfc,
	.get_rxfh_indir_size = ifc_mcdma_get_rxfh_indir_size,
	.get_rxfh_key_size   = ifc_mcdma_get_rxfh_key_size,
	.get_rxfh            = ifc_mcdma_get_rxfh,
	.set_rxfh            = ifc_mcdma_set_rxfh,
};

void ifc_mcdma_set_ethtool_ops(struct net_device *netdev)
{
	netdev->ethtool_ops = &ifc_mcdma_ethtool_ops;
}
