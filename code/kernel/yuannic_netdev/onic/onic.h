/*
 * Copyright (c) 2020 Xilinx, Inc.
 * All rights reserved.
 *
 * This source code is free software; you can redistribute it and/or modify it
 * under the terms and conditions of the GNU General Public License,
 * version 2, as published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
 * more details.
 *
 * The full GNU General Public License is included in this distribution in
 * the file called "COPYING".
 */
#ifndef __ONIC_H__
#define __ONIC_H__

#include <linux/netdevice.h>
#include <linux/cpumask.h>
#include <linux/pci.h>
#include <linux/timecounter.h>
#include <linux/net_tstamp.h>
#include <linux/ptp_clock_kernel.h>

#include "onic_hardware.h"
#include "onic_register.h"

#define ONIC_MAX_QUEUES			128

#define ONIC_MAX_ADAPTER		8
#define ONIC_MAC_SIZE			16
#define ONIC_MAC_OFFSET			0xB000
#define ONIC_MODEL_REG			0x002C
#define ONIC_PORT_SPEED_REG		0x0050
#define ONIC_LINK_REG			0x01BC
#define ONIC_AUNE_REG			0x003C


/* state bits */
#define ONIC_ERROR_INTR			0
#define ONIC_USER_INTR			1

/* flag bits */
#define ONIC_FLAG_MASTER_PF		0

#define ONIC_PTP_TX_HWTSTAMP_ENABLED	BIT(0)
#define ONIC_PTP_RX_HWTSTAMP_ENABLED	BIT(0)
#define ONIC_PTP_RX_HWTSTAMP_TYPE		BIT(4)
#define ONIC_PTP_TX_HWTSTAMP_VALID		BIT(4)
#define ONIC_PTP_RX_HWTSTAMP_VALID		BIT(8)

enum {
	CARD_10G = 0,
	CARD_25G,
	CARD_1G,
	CARD_100G,
	reserved,
};

struct onic_tx_buffer {
	struct sk_buff *skb;
	dma_addr_t dma_addr;
	u32 len;
	u64 time_stamp;
};

struct onic_rx_buffer {
	struct page *pg;
	unsigned int offset;
	u64 time_stamp;
};

/**
 * struct onic_ring - generic ring structure
 **/
struct onic_ring {
	u16 count;		/* number of descriptors */
	u8 *desc;		/* base address for descriptors */
	u8 *wb;			/* descriptor writeback */
	dma_addr_t dma_addr;	/* DMA address for descriptors */

	u16 next_to_use;
	u16 next_to_clean;
	u8 color;
};

struct onic_tx_queue {
	struct net_device *netdev;
	u16 qid;
	DECLARE_BITMAP(state, 32);

	struct onic_tx_buffer *buffer;
	struct onic_ring ring;
	struct onic_q_vector *vector;
};

struct onic_rx_queue {
	struct net_device *netdev;
	u16 qid;

	struct onic_rx_buffer *buffer;
	struct onic_ring desc_ring;
	struct onic_ring cmpl_ring;
	struct onic_q_vector *vector;

	struct napi_struct napi;
};

struct onic_q_vector {
	u16 vid;
	struct onic_private *priv;
	struct cpumask affinity_mask;
	int numa_node;
};

/**
 * struct onic_private - OpenNIC driver private data
 **/
struct onic_private {
	struct list_head dev_list;

	struct pci_dev *pdev;
	DECLARE_BITMAP(state, 32);
	DECLARE_BITMAP(flags, 32);

        int RS_FEC;

	u16 num_q_vectors;
	u16 num_tx_queues;
	u16 num_rx_queues;

	struct net_device *netdev;
	struct rtnl_link_stats64 netdev_stats;
	spinlock_t tx_lock;
	spinlock_t rx_lock;

	struct onic_q_vector *q_vector[ONIC_MAX_QUEUES];
	struct onic_tx_queue *tx_queue[ONIC_MAX_QUEUES];
	struct onic_rx_queue *rx_queue[ONIC_MAX_QUEUES];

	struct onic_hardware hw;
	unsigned int	devfn;
	unsigned short	vendor;
	unsigned short	device;
	u16		bridge_mode;	/* BRIDGE_MODE_VEB or BRIDGE_MODE_VEPA */
    
	//ptp
	u32 hw_flag; //u32 flags

	struct ptp_clock *ptp_clock;
	struct ptp_clock_info ptp_caps;
	struct work_struct ptp_tx_work;
	struct sk_buff *ptp_tx_skb;
	struct hwtstamp_config tstamp_config;
	unsigned long ptp_tx_start;
	unsigned long last_overflow_check;
	unsigned long last_rx_ptp_check;
	unsigned long last_rx_timestamp;
	spinlock_t tmreg_lock;
	struct cyclecounter hw_cc;
	struct timecounter hw_tc;
	u32 base_incval;
	u32 tx_hwtstamp_timeouts;
	u32 tx_hwtstamp_skipped;
	u32 rx_hwtstamp_cleared;


	void (*ptp_setup_sdp)(struct onic_private *);
};


void onic_ptp_init(struct onic_private *adapter);
void onic_ptp_stop(struct onic_private *adapter);
void onic_ptp_rx_rgtstamp(struct onic_private *adapter, struct sk_buff *skb);
static inline void onic_ptp_rx_hwtstamp(struct onic_private *adapter,
					 struct sk_buff *skb)
{
	onic_ptp_rx_rgtstamp(adapter, skb);

}
int onic_ptp_set_ts_config(struct onic_private *adapter, struct ifreq *ifr);
int onic_ptp_get_ts_config(struct onic_private *adapter, struct ifreq *ifr);
#endif
