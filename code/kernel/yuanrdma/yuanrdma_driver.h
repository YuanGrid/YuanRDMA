/* SPDX-License-Identifier: GPL-2.0 OR BSD-2-Clause */
/*
 * yuanrdma_driver.h - YuanNIC-NH400-B RoCEv2 引擎的 ib_core 驱动（内部定义）。
 *
 * 本驱动不占用 PCI 设备：PCI 和 netdev 由 yuanmcdma.ko（code/kernel/mcdma）负责，
 * 本驱动找到同一个 pci_dev 和它的 netdev，映射 BAR2 中的 RoCE 窗口，注册 ib_device。
 * 加载顺序：先 yuanmcdma.ko，后 yuanrdma.ko；卸载相反。
 */
#ifndef YUANRDMA_H
#define YUANRDMA_H

#include <linux/mutex.h>
#include <linux/pci.h>
#include <linux/netdevice.h>
#include <rdma/ib_verbs.h>
#include <rdma/ib_umem.h>

#include "yuanrdma_hw.h"

#define YUANRDMA_BAR		2
#define YUANRDMA_MAX_SQ_DEPTH	4096
#define YUANRDMA_MAX_RQ_DEPTH	4096
/*
 * CQ 深度上限：RTL 的 cqc_t.log2_depth 是 **4 bit**（roce_tbl.sv:326 取 [68:65]，
 * roce_pkg.sv:334 声明 [3:0]），最大只能表达 2^15；2^16 写进去高位被截成 0，
 * roce_cq 会按 index_mask=0（1 项环）+ owner 错位工作，**不报错且永远 poll 不到完成**。
 * 因此这里钉在 32768，与硬件可表达的位宽一致。
 * 要放开到 65536 必须先扩 RTL 的 log2_depth 到 5 bit 并同步 ynrdma_cqc.dw2 注释。
 */
#define YUANRDMA_MAX_CQ_DEPTH	32768
#define YUANRDMA_MTT_GROUP	8		/* MTT 一次写 8 项，按 8 对齐分配 */

/*
 * UD 与 RC 同时支持，没有开关（2026-11-21 起）。
 *
 * 原来有 module 参数 yuanrdma.enable_ud（默认 0）来放行用户态 UD QP，现在删掉了：
 * B6458/B6459 起比特流的 UD TX（roce_req 的 WQE_UD_SEND=5/6、roce_tx 的 DETH 组包）
 * 已实测可用，而驱动无法从 YNRDMA_REG_CAPS 判别 UD 是否就绪（没有对应位），
 * 留一个默认关的开关只会让部署者多一步、且容易忘记。
 *
 * **代价要知道**：比 B6458 更老的比特流（WQE 编码 5/6 没有 case）上，UD QP 现在
 * 建得起来、发得出去，但 roce_req 的 tx_opcode_of() 会落到 default 组一个 RC 形态的包，
 * 对端按 RC 解析、不回任何东西——「发送成功、接收端永远收不到」，且没有错误上报。
 * 用老镜像时不要建 UD QP。
 *
 * UD 与 RC 的区分不靠驱动：QPC dw0[21] 记 qp_type，roce_req 用它校验「WQE opcode
 * 是 UD」与「QP 本身是 UD」必须一致，不一致报 WCS_LOC_OP_ERR。
 */

/*
 * IB_PORT_CM_SUP 的声明开关（module 参数 enable_cm_sup，默认 0）。
 *
 * 为什么默认不声明：这一位是「端口支持 RDMA CM」对外汇报的能力，只有在 rping /
 * ucmatose 真的跑通之后才不算假声明（roce-cm-plan.md §6.2）。
 *
 * 为什么又要有这个开关：不声明它，rdma_create_ep() 在 cma_alloc_port 之前就返回
 * EOPNOTSUPP，**根本走不到发 REQ 那一步**，CM 就永远无法验证。验证时按
 *   insmod yuanrdma.ko enable_cm_sup=1
 * 打开，跑通后按 §6.2 的判据决定默认值。
 */
extern bool yuanrdma_enable_cm_sup;

/*
 * 软件 GSI（QP1）：内核 MAD/CM 用，收发都在驱动里完成，不占硬件 QP/CQ（见 yuanrdma_gsi.c）。
 * 容量按 MAD 层实际要的量给：mad.c 的 QP1 CQ 深度 128 + 512，RQ 512 个接收槽。
 */
#define YUANRDMA_GSI_QPN	1
#define YUANRDMA_GSI_SQ_DEPTH	256
#define YUANRDMA_GSI_RQ_DEPTH	1024
#define YUANRDMA_GSI_MAX_SGE	2		/* MAD 用头 + 载荷两个 SGE */
#define YUANRDMA_GSI_GRH_LEN	40

/* 软件 GSI 的计数，debugfs 只读导出（/sys/kernel/debug/yuanrdma/gsi_*） */
struct yuanrdma_gsi_stats {
	u64 tx_packets;
	u64 tx_bad_wr;		/* 地址翻译失败 / 长度超限 / AH 非 RoCEv2-IPv4 */
	u64 rx_packets;
	u64 rx_icrc_error;
	u64 rx_bad_header;	/* 截短、qkey/pkey 不符、非 UD SEND */
	u64 rx_no_qp;		/* QP1 不存在或不在 RTR/RTS */
	u64 rx_no_recv;		/* RQ 空，按 UD 语义静默丢弃 */
	u64 rx_rc_dropped;	/* 非 QP1 的 RoCE 帧（drop_rc_on_netdev=1 时才在这里丢） */
	/* CM MAD 分类计数（yuanrdma_cm_pkt.h 的 fgcm_classify）：上板时用来确认
	 * 「REQ 到底有没有到驱动」。attr_id 0x0010..0x001a 映射到下标 0..10。 */
	u64 cm_rx[11];
	u64 cm_rx_bad;		/* CM 帧头不符（class/version/method）或 attr_id 不认识 */
};

struct yuanrdma_gsi_qp;

struct yuanrdma_dev {
	struct ib_device ibdev;
	struct pci_dev *pdev;
	struct net_device *netdev;
	void __iomem *csr;			/* BAR2 + YNRDMA_BAR2_BASE，1 MB */
	phys_addr_t doorbell_phys;		/* doorbell 页物理地址 */
	struct mutex table_lock;		/* CMD_DATA/CMD 寄存器组 */
	DECLARE_BITMAP(qp_used, YNRDMA_MAX_QP);
	DECLARE_BITMAP(cq_used, YNRDMA_MAX_CQ);
	DECLARE_BITMAP(mr_used, YNRDMA_MAX_MR);
	DECLARE_BITMAP(mtt_used, YNRDMA_MAX_MTT / YUANRDMA_MTT_GROUP);
	DECLARE_BITMAP(pd_used, 65536);
	spinlock_t alloc_lock;

	/* 软件 GSI（yuanrdma_gsi.c） */
	struct yuanrdma_gsi_qp __rcu *gsi;	/* 当前的 QP1，收包路径 RCU 读 */
	struct workqueue_struct *gsi_wq;	/* 发包：post_send 在关中断上下文，dev_queue_xmit 推到这里 */
	bool gsi_rx_registered;			/* eth0 上的 rx_handler 是我们挂的 */
	__be32 ipv4;				/* add_gid 记下的本机 RoCEv2 IPv4，收包按它过滤 */
	struct dentry *debugfs;
	struct yuanrdma_gsi_stats gsi_stats;
};

/* 物理连续的环，由 ucontext 持有，ucontext 释放时才 free（避免用户态映射还在时释放） */
struct yuanrdma_ring {
	struct list_head node;
	struct rdma_user_mmap_entry *mmap_entry;
	void *cpu_address;
	dma_addr_t dma_address;
	size_t size;
};

struct yuanrdma_mmap_entry {
	struct rdma_user_mmap_entry rdma_entry;
	bool is_doorbell;
	struct yuanrdma_ring *ring;
};

struct yuanrdma_ucontext {
	struct ib_ucontext ibucontext;
	struct rdma_user_mmap_entry *doorbell_entry;
	struct mutex ring_lock;
	struct list_head rings;
};

struct yuanrdma_pd {
	struct ib_pd ibpd;
	u32 pd_number;
};

struct yuanrdma_cq {
	struct ib_cq ibcq;
	u32 cq_index;
	u32 log2_depth;
	struct yuanrdma_ring *ring;

	/* 内核态 CQ（无 udata，目前只有 MAD 层的 QP1 用）：纯软件环，不占硬件 CQ */
	bool software;
	spinlock_t lock;
	struct ib_wc *entries;
	u32 depth;
	u32 head;
	u32 count;
	u32 notify;			/* IB_CQ_SOLICITED / IB_CQ_NEXT_COMP，触发一次后清零 */
	u64 overflow;
};

struct yuanrdma_qp {
	struct ib_qp ibqp;
	u32 qp_index;
	struct ynrdma_qpc context;		/* 驱动侧影子 QPC，modify_qp 时整项写入 */
	struct yuanrdma_ring *sq_ring;
	struct yuanrdma_ring *rq_ring;
	u32 sq_log2_depth;
	u32 rq_log2_depth;
	enum ib_qp_state state;
	struct ib_qp_attr attributes;		/* query_qp 用 */
	enum ib_qp_type qp_type;		/* G2.1：query_qp 回真实类型，不再硬写 IB_QPT_RC */
	struct yuanrdma_gsi_qp *gsi;		/* 非空 = 软件 QP1，上面的硬件字段都不用 */
};

struct yuanrdma_mr {
	struct ib_mr ibmr;
	struct ib_umem *umem;
	/* dma-buf MR（GPUDirect）要记住原始的 ib_umem_dmabuf：释放必须走
	 * ib_umem_dmabuf_release()（它做 dma_buf unpin + unmap），用 ib_umem_release()
	 * 只会放掉 ib_umem 外壳，dma_buf 的引用与 pin 计数留在这里 —— 每次注册/注销
	 * 漏一份 GPU 显存引用。非 dmabuf MR 该指针恒 NULL。 */
	struct ib_umem_dmabuf *umem_dmabuf;
	u32 mr_index;
	u32 mtt_base;
	u32 mtt_count;
	bool dma_mr;				/* get_dma_mr 给内核用的哑 MR，不占硬件 MPT/MTT */
};

/* 内核态 AH（MAD/CM 回包用）：只存解析好的二层/三层字段 */
struct yuanrdma_ah {
	struct ib_ah ibah;
	u8 dmac[ETH_ALEN];
	__be32 sip;
	__be32 dip;
	u8 tos;
	u8 ttl;
	u16 sport;
};

static inline struct yuanrdma_dev *to_yuanrdma_dev(struct ib_device *ibdev)
{
	return container_of(ibdev, struct yuanrdma_dev, ibdev);
}
#define YUANRDMA_CAST(type, ibtype, field)					\
	static inline struct yuanrdma_##type *to_yuanrdma_##type(struct ibtype *object) \
	{ return container_of(object, struct yuanrdma_##type, field); }
YUANRDMA_CAST(ucontext, ib_ucontext, ibucontext)
YUANRDMA_CAST(pd, ib_pd, ibpd)
YUANRDMA_CAST(cq, ib_cq, ibcq)
YUANRDMA_CAST(qp, ib_qp, ibqp)
YUANRDMA_CAST(mr, ib_mr, ibmr)
YUANRDMA_CAST(ah, ib_ah, ibah)

/* yuanrdma_main.c */
u32 yuanrdma_read(struct yuanrdma_dev *dev, u32 offset);
void yuanrdma_write(struct yuanrdma_dev *dev, u32 offset, u32 value);
int yuanrdma_write_table(struct yuanrdma_dev *dev, u32 table, u32 index, const void *entry, size_t size);
int yuanrdma_read_table(struct yuanrdma_dev *dev, u32 table, u32 index, void *entry, size_t size);

/* yuanrdma_verbs.c */
extern const struct ib_device_ops yuanrdma_device_ops;

/* yuanrdma_gsi.c：软件 QP1 与内核态 CQ/AH/哑 MR */
int yuanrdma_gsi_init(struct yuanrdma_dev *dev);
void yuanrdma_gsi_cleanup(struct yuanrdma_dev *dev);
int yuanrdma_kernel_create_cq(struct yuanrdma_cq *cq, const struct ib_cq_init_attr *attr);
void yuanrdma_kernel_destroy_cq(struct yuanrdma_cq *cq);
int yuanrdma_poll_cq(struct ib_cq *ibcq, int num_entries, struct ib_wc *wc);
int yuanrdma_req_notify_cq(struct ib_cq *ibcq, enum ib_cq_notify_flags flags);
int yuanrdma_gsi_create_qp(struct yuanrdma_qp *qp, struct ib_qp_init_attr *init);
int yuanrdma_gsi_modify_qp(struct yuanrdma_qp *qp, struct ib_qp_attr *attr, int mask);
int yuanrdma_gsi_query_qp(struct yuanrdma_qp *qp, struct ib_qp_attr *attr, int mask,
			  struct ib_qp_init_attr *init);
void yuanrdma_gsi_destroy_qp(struct yuanrdma_qp *qp);
int yuanrdma_post_send(struct ib_qp *ibqp, const struct ib_send_wr *wr, const struct ib_send_wr **bad_wr);
int yuanrdma_post_recv(struct ib_qp *ibqp, const struct ib_recv_wr *wr, const struct ib_recv_wr **bad_wr);
int yuanrdma_create_ah(struct ib_ah *ibah, struct rdma_ah_init_attr *init, struct ib_udata *udata);
int yuanrdma_destroy_ah(struct ib_ah *ibah, u32 flags);
struct ib_mr *yuanrdma_get_dma_mr(struct ib_pd *ibpd, int access_flags);

#endif /* YUANRDMA_H */
