/* SPDX-License-Identifier: GPL-2.0
 * Copyright(c) 2020-21 Intel Corporation. All rights reserved.
 */
#ifndef _IFC_MCDMA_NET_H_
#define _IFC_MCDMA_NET_H_

#include <linux/netdevice.h>
#include <linux/etherdevice.h>
#include <linux/irqreturn.h>
#include <linux/interrupt.h>
#include <linux/pci.h>
#include <linux/skbuff.h>
#include <linux/jhash.h>
#include <regs/qdma_regs_2_registers.h>
#include <linux/moduleparam.h>

#ifdef ENABLE_DEBUGFS
#include "ifc_mcdma_debugfs.h"
#endif

#define VENDOR_ID		0x1172
#define DEVICE_ID		0x0000
#define DEVICE_ID_W		0x000C
#define DRV_VERSION		"0.0.0.1"
#define DRV_SUMMARY		"ifc_mcdma_netdev Intel(R) PCIe end point drv"
#define NETDEV_NAME		"ifc_mcdma%d"
#define IFC_MCDMA_DRIVER_NAME	"ifc_mcdma_netdev"
#define IFC_PCIE5_BAR2_MAGIC	0x4e540000U

/* Number of channels per PF
 * Based on BS, need to configure value
 */
#define IFC_MCDMA_CHAN_PER_PF	512

/* Number of Channels */
#define IFC_MCDMA_CHANNEL_MAX	512

/* Max number of Desc per queue */
#define IFC_MCDMA_MAX_DESC	2048

/* Min number of Desc per queue */
#define IFC_MCDMA_MIN_DESC	128

/* Page size */
#define IFC_MCDMA_PAGE_SIZE	128

/* Hash table size
 */
#define IFC_MCDMA_H2D_MAP_TABLE_SIZE	IFC_MCDMA_CHANNEL_MAX

/* RSS indirection table size (must be power of 2) */
#define IFC_MCDMA_RSS_INDIR_SIZE	128

/* RSS hardware register layout in BAR2 (matches DPDK mcdma PMD):
 *   BAR2 + 0x1500000 + 0x1000 * func_id + 0x400  -> RETA table (128 x 32-bit)
 *   BAR2 + 0x1500000 + 0x1000 * func_id + 0x600  -> Hash key  (40 bytes)
 * Each RETA entry: bits[15:0] = queue_id, bits[31:16] = reserved (RMW).
 * Hash key packing: little-endian (key[i] -> bits[7:0]).
 */
#define IFC_MCDMA_RSS_SUBSYS_OFFSET	0x1500000UL
#define IFC_MCDMA_RSS_FUNC_STRIDE	0x1000UL
#define IFC_MCDMA_RSS_RETA_OFFSET	0x400UL
#define IFC_MCDMA_RSS_KEY_OFFSET	0x600UL
#define IFC_MCDMA_RSS_KEY_SIZE		40

/* Queue Batch Delay */
#define IFC_MCDMA_Q_BATCH_DELAY	1

 /* Payload Limit */
#define IFC_MCDMA_BUF_LIMIT	(1UL << 20)

/* 每个描述符槽的 DMA 缓冲：4 KB、4 KB 对齐（dma_alloc_coherent 分配，按页对齐）。
 *
 * PCIe5 MCDMA 的 DMA 不能跨 4 KB 页：D2H 写跨页会发 Malformed TLP，BIOS 可能升级成
 * fatal MCE。所以任何交给硬件的缓冲都是「一个描述符 = 一块对齐的 4 KB」，长度 <= 4096，
 * 天然落在一页之内。比 4096 长的帧拆成多个描述符：
 *   RX（D2H）：硬件把一帧顺序写进多个描述符缓冲，首段写回 SOF、末段写回 EOF 和末段
 *             实际字节数 rx_pyld_cnt，驱动按 SOF/EOF 拼回一个 skb；
 *   TX（H2D）：驱动把 skb 拷进槽内 bounce 缓冲，每 4096 字节一个描述符，首个置 SOF、
 *             最后一个置 EOF。
 * 4096 也是 128 B（PCIe5 1024 bit 数据宽度）的整数倍，非末段描述符长度满足对齐要求。 */
#define IFC_MCDMA_BUF_SIZE	4096

/* TX 单帧上限（字节）。MCDMA H2D 出来后要过 qdma_top.sv 的 u2_tx_fifo_inst：
 * DCFIFO、PACKET_FIFO（整包写完才放行）、FIFO_DEPTH = 64 拍 × 128 B，写到约 60 拍就满。
 * 比这长的帧永远凑不齐 tlast，H2D 通路会永久卡死（三块板的 release 工程都一样）。
 * 保守取 58 拍 = 7424 B，xmit 直接丢掉更长的帧，不交给硬件。 */
#define IFC_MCDMA_TX_FRAME_MAX	(58 * 128)
#define IFC_MCDMA_TX_MAX_SEGS	DIV_ROUND_UP(IFC_MCDMA_TX_FRAME_MAX, IFC_MCDMA_BUF_SIZE)

/* L2 MTU 上限。alloc_etherdev_mq() 默认给 1500，内核会在 ndo_change_mtu 之前就拒绝
 * 更大的值，所以 ifc_mcdma_netdev_setup() 里要显式放开 max_mtu。
 *
 * RoCE 的 active_mtu = iboe_get_mtu(netdev->mtu)，5.15 的 iboe_get_mtu() 扣
 * GRH 40 + UDP 8 + BTH 12 + XRC 4 + AtomicETH 28 + ICRC 4 = 96 字节：
 *   l2 MTU >= 4192 → IB MTU 4096（推荐两端都设 4200）
 *   l2 MTU >= 2144 → IB MTU 2048
 * 2026-11-08 起 RX/TX 都是多描述符（见 IFC_MCDMA_BUF_SIZE），帧长不再受 4 KB 限制；
 * 上限只受 TX 侧 IFC_MCDMA_TX_FRAME_MAX 约束：7168 + 14 以太头 + 4 VLAN = 7186 <= 7424。
 * 不放到 9000：9014 B 的帧会把 u2_tx_fifo_inst 卡死。 */
#define IFC_MCDMA_L2_MTU_MAX	7168

/* Number of pages of descriptors per queue */
#define IFC_MCDMA_DESC_PAGES	1 //todo

/**
 *Number of descriptors per page
 */
#define IFC_MCDMA_CONFIG_NUM_DESC_PER_PAGE             127

/* Descriptors submission limit */
#if IFC_MCDMA_DESC_PAGES > 1
#define IFC_MCDMA_QDEPTH   ((IFC_MCDMA_DESC_PAGES/2) * IFC_MCDMA_CONFIG_NUM_DESC_PER_PAGE) //16:1016
#else
#define IFC_MCDMA_QDEPTH  ((IFC_MCDMA_CONFIG_NUM_DESC_PER_PAGE/2) + 1) //65
#endif

/* DMA direction: From Device to Host(D2H) & From Host to Device (H2D) */
enum mcdma_dir {
	IFC_MCDMA_DIR_RX,
	IFC_MCDMA_DIR_TX
};

/* Descriptor Index Limit */
#define IFC_NUM_DESC_INDEXES	65536

#define IFC_MCDMA_DEF_PAYLOAD	2048

/* externs */
extern struct ifc_mcdma_loopback_config ifc_mcdma_lb_config;

/* BAR Context */
struct ifc_mcdma_bar_info {
	const char *name;
	unsigned long size;
	void __iomem *iaddr;
};

/* PCIe Device Context */
struct ifc_pci_dev {
	struct pci_dev *pdev;
	struct ifc_mcdma_bar_info *info;
};

/* HW Descriptor Structure*/
struct ifc_mcdma_desc {
	/* word 1,2 */
	uint64_t src;
	/* word 3,4 */
	uint64_t dest;
	/* word 5 */
	uint32_t len:20;
	uint32_t rsvd:12;
	/* word 6 */
	uint32_t didx:16; //desc index
	uint32_t msix_en:1;
	uint32_t wb_en:1;
	uint32_t rsvd2:14;
	/* word 7
	 * D2H：rx_pyld_cnt/sof/eof 由硬件写回（Intel MCDMA UG 的 RX_PYLD_CNT/SOF/EOF 字段；
	 * 参考 Quartus 安装目录 ip/altera/intel_pcie/mcdma/software/user/libmqdma/ifc_mcdma.c
	 * 的 ifc_qdma_complete_requests()）：一帧跨多个描述符时，首个描述符写回 SOF，
	 * 最后一个写回 EOF 和**该描述符内**的实际字节数，中间描述符视为写满 len 字节。
	 * H2D：sof/eof 由驱动填，一帧可跨多个描述符（首个 SOF、最后一个 EOF）。 */
	uint32_t rx_pyld_cnt:20;
	uint32_t rsvd3:10;
#ifdef IFC_QDMA_INTF_ST
	uint32_t sof:1;
	uint32_t eof:1;
#else
	uint32_t rsvd4:2;
#endif
	/* word 8 */
	uint32_t rsvd5:28;
	uint32_t pad_len:2;
	uint32_t desc_invalid:1;
	uint32_t link:1;
};

/* 每个描述符槽的软件上下文（link 描述符的槽不用）。
 * buf/buf_dma 在队列初始化时分配、队列释放时回收，中途不换：
 *   RX：硬件写入的收包缓冲，完成后拷进新 skb，缓冲原地重新挂回环上；
 *   TX：bounce 缓冲，xmit 时把 skb 拷进来，skb 随即释放。 */
struct ifc_mcdma_desc_sw {
	void *buf;		/* IFC_MCDMA_BUF_SIZE 字节，4 KB 对齐 */
	dma_addr_t buf_dma;	/* 交给硬件的地址，低 12 位必为 0 */
	uint32_t tx_len;	/* TX：EOF 槽记整帧长度，完成时计入统计；其它槽为 0 */
};

#ifdef ENABLE_DEBUGFS
/* Queue Stats */
struct ifc_qdma_queue_stats {
	uint64_t tid_update;
	uint64_t processed;
	uint64_t processed_total;
	uint64_t processed_skip;
	uint32_t submitted_didx;
	uint32_t last_intr_cons_head;
	uint32_t last_intr_reg;
	uint32_t tid_skip;
};
#endif

struct ifc_queue_alloc {
	u32 queue_id;
	u32 hash;
	struct rb_node node;
	struct list_head list;
};

struct ifc_core_info {
	bool queues_mapped[IFC_MCDMA_CHANNEL_MAX];
	bool queues_allocated[IFC_MCDMA_CHANNEL_MAX];
	struct ifc_queue_alloc *rb_qcache;
	struct rb_root root;
	struct list_head lru_list;
};

/* Queue Context */
struct ifc_mcdma_queue {
	void *qcsr; //bar0 + offset
	enum mcdma_dir dir;

	void *ring_virt_addr;		/* Ring Virtual Address */
	dma_addr_t ring_dma_addr;	/* Ring DMA mapped Address */
	uint64_t ring_hw_addr;		/* Ring Address passed to HW */

	uint32_t qlen;			/* Descriptor ring length */

	int consumed_head;		/* WB live copy */
	int cur_con_head;		/* WB offline copy */
	int head;			/* Ring Head */
	int tail;			/* Ring Tail */
	int processed_tail;

	int head_didx;
	int tail_didx;

	uint16_t didx;			/* descriptor index */
	uint16_t ite_count;		/* descriptor index */
	uint16_t num_desc_bits;		/* bits required for didx */
	uint32_t wbe:1;			/* write back */
	uint32_t ire:1;			/* interrupt enable */
	uint32_t sof_rcvd:1;
	uint32_t num_desc_pages:11; //descriptors page size
	uint32_t rsvd:18;

	int irq_index;			/* index to interrupt context */
	struct ifc_mcdma_desc_sw *ctx;
	struct ifc_mcdma_channel *chnl;
	struct napi_struct napi;

	/* RX 多描述符帧的拼装状态（只在本队列的 NAPI 里访问）。
	 * 一帧可能跨两次 NAPI poll，所以放在队列上而不是局部变量。 */
	struct sk_buff *rx_skb;		/* 已收到 SOF、还没等到 EOF 的帧 */
	uint32_t rx_limit;		/* rx_skb 允许的最大帧长 */
	bool rx_discard;		/* 正在丢弃一帧的剩余段，直到 EOF */
#ifdef ENABLE_DEBUGFS
	struct ifc_qdma_queue_stats stats;
#endif
};

/* Channel Context */
struct ifc_mcdma_channel {
	uint32_t channel_id;
	struct ifc_mcdma_queue rx;
	struct ifc_mcdma_queue tx;
	struct ifc_mcdma_dev_ctx *dev_ctx;
};

/* PCIe MSIX Context */
struct ifc_msix_info {
	u32 nvectors;
	struct msix_entry *table;
};

/* Device Context */
struct ifc_mcdma_dev_ctx {
	u32 msg_enable			____cacheline_aligned;
	struct ifc_pci_dev pctx;
	u8 pcie_mode;
	u16 data_align_bytes; /* PCIe4: 64, PCIe5: 128 */
	struct ifc_msix_info msix_info;
	struct net_device *netdev;
	void *qcsr; //bar0 address
	void *gcsr;
	struct dentry *rootdir;
	char bdf[32];

	struct mutex chnl_lock;
	struct ifc_mcdma_channel *channel_context[IFC_MCDMA_CHANNEL_MAX];
	int queue_core_mapping[IFC_MCDMA_CHANNEL_MAX];
	bool channel_bitmap[IFC_MCDMA_CHANNEL_MAX];
	unsigned long num_cores;
	struct ifc_core_info *cores;

	u32 h2d_mapping[IFC_MCDMA_H2D_MAP_TABLE_SIZE];
	int channel_core_mapping[IFC_MCDMA_CHANNEL_MAX];
	struct list_head list;
	u32 num_of_pages;

	/* RSS indirection table: maps hash bucket -> channel id */
	u32 rss_indir_table[IFC_MCDMA_RSS_INDIR_SIZE];
	/* RSS Toeplitz hash key (40 bytes) */
	u8  rss_key[IFC_MCDMA_RSS_KEY_SIZE];

	/* Debugfs inputs */
	u32 start_chnl;
	u32 end_chnl;
	u32 core;
	u32 max_rx_cnt;
	u32 max_tx_cnt;
	u32 rx_chnl_cnt;
	u32 tx_chnl_cnt;
	u32 chnl_cnt; //channel number
    u32 tot_chnl_avl;
	bool is_pf;
};

struct ifc_mcdma_chnl_map {
	bool valid;
	uint32_t chnl;
};

struct ifc_mcdma_loopback_config {
	struct dentry *d;
	struct ifc_mcdma_dev_ctx *dev_ctx;
	uint32_t src_chnl;
	uint32_t dst_chnl;
	struct ifc_mcdma_chnl_map mapping[2048];
};

int ifc_mcdma_netdev_setup(struct net_device *dev,u32 tot_chn_aval);
int ifc_mcdma_ip_reset(void *dev_qcsr);
void ifc_mcdma_hw_write_reta(struct ifc_mcdma_dev_ctx *dev_ctx);
void ifc_mcdma_hw_write_rss_key(struct ifc_mcdma_dev_ctx *dev_ctx);
void ifc_mcdma_update_lb_config(struct ifc_mcdma_loopback_config *lbconfig);
int ifc_core_rebuild_all(struct ifc_mcdma_dev_ctx *dev_ctx);
void ifc_core_free_all(struct ifc_mcdma_dev_ctx *dev_ctx);
int ifc_refresh_core_info(struct ifc_mcdma_dev_ctx *dev_ctx, int q, int c);
int ifc_mcdma_chnl_init_all(struct ifc_mcdma_dev_ctx *dev_ctx);
void ifc_mcdma_chnl_free_all(struct ifc_mcdma_dev_ctx *dev_ctx);

#ifdef ENABLE_DEBUGFS
int ifc_mcdma_debugfs_setup(struct net_device *dev);
void ifc_mcdma_debugfs_remove(struct net_device *dev);
#endif
int ifc_set_mac_addr(struct net_device *dev, void *addr);

#endif	/* _IFC_MCDMA_NET_H_ */
