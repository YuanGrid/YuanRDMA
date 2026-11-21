// SPDX-License-Identifier: GPL-2.0 OR BSD-2-Clause
/*
 * yuanrdma_gsi.c - 软件 GSI（QP1）与内核态 CQ/AH/哑 MR。
 *
 * 为什么在驱动里做
 *   内核 MAD 层（ib_core 的 mad.c）在设备注册时创建 QP1，rdma_cm 通过它收发 CM MAD。
 *   本 RTL 只有 RC 数据通路、没有 UD，所以 QP1 完全用软件实现：
 *     发：post_send 组好整帧 Eth/IP/UDP/BTH/DETH + ICRC，经 yuanmcdma 的 eth0 发出；
 *     收：eth0 的 rx_handler 里截获 UDP 4791、UD SEND、dest QP=1 的帧，校验 ICRC 后写进
 *         MAD 层的接收 WR 和软件 CQ。
 *   报文组装/解析/ICRC 在 yuanrdma_gsi_pkt.h，与 test/sw/gsi_pkt 的单测共用同一份。
 *
 * 为什么要先把 kverbs_provider 变成 true
 *   ib_core 的 add_client_context 对 !kverbs_provider 的设备直接跳过（device.c:698-703），
 *   而 kverbs_provider 要求 post_send/post_recv/poll_cq/req_notify_cq/get_dma_mr 五个
 *   强制 op 齐全（device.c:273-297）。缺任何一个，mad/cm/cma 客户端都不会挂上来，
 *   QP1 从不创建，rdma_cm 也就永远建不了连接。
 *
 * 上下文约束（踩坑重点）
 *   - post_send / post_recv 由 MAD 层在关中断、持锁的上下文里调用：只能 GFP_ATOMIC
 *     组包入队，dev_queue_xmit 推进有序 workqueue 里做。
 *   - SGE 里是 DMA 地址而不是内核虚拟地址（MAD 用 ib_dma_map_single 映射，本驱动以
 *     pdev 注册、不走 CONFIG_INFINIBAND_VIRT_DMA）。必须自己做 DMA→物理→虚拟转换：
 *     无 IOMMU 时 dma 地址即物理地址；有 IOMMU 时经 iommu_iova_to_phys。
 *   - 收包在 eth0 的 netdev 收包路径（可能 softirq）里，同样不能睡眠。
 */
#include <linux/module.h>
#include <linux/debugfs.h>
#include <linux/seq_file.h>
#include <linux/etherdevice.h>
#include <linux/if_ether.h>
#include <linux/inetdevice.h>
#include <linux/interrupt.h>
#include <linux/iommu.h>
#include <linux/ip.h>
#include <linux/netdevice.h>
#include <linux/skbuff.h>
#include <linux/udp.h>
#include <linux/workqueue.h>
#include <net/addrconf.h>
#include <rdma/ib_addr.h>
#include <rdma/ib_verbs.h>

#include "yuanrdma_driver.h"
#include "yuanrdma_gsi_packet.h"
#include "yuanrdma_cm_packet.h"

/* 非 QP1 的 RoCE 帧（RC 数据流）在 eth0 上是否直接丢弃。默认放进协议栈（与改造前一致；
 * 4791 上没有监听者，只是走一遍 IP 栈并回限速 ICMP）。开成 1 可省掉这部分开销。 */
static bool drop_rc_on_netdev;
module_param(drop_rc_on_netdev, bool, 0644);
MODULE_PARM_DESC(drop_rc_on_netdev, "Drop non-QP1 RoCE frames on the netdev rx path (default 0 = pass)");

#define GSI_WR_SIGNALED	BIT(0)
#define GSI_WR_HAS_IMM	BIT(1)

/* IP ID：ICRC 覆盖它，收发两侧看到的必须是同一个值，所以不能恒 0 让路径设备随意改；
 * 随机起点 + 逐帧自增（RFC 6864 允许按流递增）。 */
static atomic_t yuanrdma_gsi_ip_id = ATOMIC_INIT(0);

struct yuanrdma_gsi_wr {
	u64 wr_id;
	struct ib_cqe *wr_cqe;
	struct ib_ah *ah;		/* 内核态 AH（create_ah 已解析成 ip/mac） */
	u32 opcode;
	u16 flags;
	__be32 imm;
	u32 qkey;
	u32 dqpn;
	u8 num_sge;
	struct {
		u64 addr;
		u32 length;
	} sge[YUANRDMA_GSI_MAX_SGE];
};

struct yuanrdma_gsi_ring {
	struct yuanrdma_gsi_wr *entries;
	u32 size;
	u32 prod;
	u32 cons;
};

static void yuanrdma_gsi_tx_work(struct work_struct *work);

struct yuanrdma_gsi_qp {
	struct yuanrdma_dev *dev;
	struct ib_qp *ibqp;
	spinlock_t lock;			/* 保护下面全部字段（收包路径也用） */
	enum ib_qp_state state;
	u32 qkey;
	u32 sq_psn;
	bool dead;
	struct yuanrdma_gsi_ring sq;
	struct yuanrdma_gsi_ring rq;
	bool work_queued;
	struct work_struct tx_work;
};

/* ---------------------------------------------------------------- DMA→内核虚拟地址 */

/*
 * SGE 里是 DMA 地址。没有 IOMMU 时（本机 intel_iommu 默认关，iommu_groups 为空）
 * dma 地址 = 物理地址，直接 phys_to_virt；有 IOMMU 时经 iommu_iova_to_phys 还原。
 * 要求整个缓冲区落在一页内：MAD 的缓冲都是 kmalloc 的 256/512 B 对象，满足；不满足
 * 就报错，不做跨页拼接（错在明处比悄悄拷错数据好）。
 */
static void *yuanrdma_dma_to_virt(struct yuanrdma_dev *dev, u64 addr, size_t length)
{
	phys_addr_t phys = (phys_addr_t)addr;
#ifdef CONFIG_IOMMU_API
	struct iommu_domain *domain = iommu_get_domain_for_dev(&dev->pdev->dev);

	if (domain) {
		phys = iommu_iova_to_phys(domain, addr);
		if (!phys)
			return NULL;
	}
#endif
	if (offset_in_page(phys) + length > PAGE_SIZE)
		return NULL;
	if (!pfn_valid(PFN_DOWN(phys)))
		return NULL;
	return phys_to_virt(phys);
}

/* ---------------------------------------------------------------- 软件 CQ */

static void yuanrdma_gsi_cq_push(struct ib_cq *ibcq, const struct ib_wc *wc)
{
	struct yuanrdma_cq *cq = to_yuanrdma_cq(ibcq);
	bool fire = false;

	spin_lock_bh(&cq->lock);
	if (cq->count < cq->depth) {
		cq->entries[(cq->head + cq->count) % cq->depth] = *wc;
		cq->count++;
	} else {
		cq->overflow++;		/* MAD 层 CQ 是 128 + 512 深，正常不会溢出 */
	}
	if (cq->notify) {
		cq->notify = 0;
		fire = true;
	}
	spin_unlock_bh(&cq->lock);

	/* MAD 层用 IB_POLL_UNBOUND_WORKQUEUE，comp_handler 里只是 queue_work，softirq 里调用安全 */
	if (fire && ibcq->comp_handler)
		ibcq->comp_handler(ibcq, ibcq->cq_context);
}

int yuanrdma_kernel_create_cq(struct yuanrdma_cq *cq, const struct ib_cq_init_attr *attr)
{
	u32 depth;

	if (attr->flags)
		return -EINVAL;
	depth = roundup_pow_of_two(max_t(u32, attr->cqe + 1, 64));
	cq->entries = kcalloc(depth, sizeof(struct ib_wc), GFP_KERNEL);
	if (!cq->entries)
		return -ENOMEM;
	spin_lock_init(&cq->lock);
	cq->software = true;
	cq->depth = depth;
	cq->cq_index = YNRDMA_MAX_CQ;	/* 不占硬件 CQ 槽 */
	return 0;
}

void yuanrdma_kernel_destroy_cq(struct yuanrdma_cq *cq)
{
	kfree(cq->entries);
	cq->entries = NULL;
}

int yuanrdma_poll_cq(struct ib_cq *ibcq, int num_entries, struct ib_wc *wc)
{
	struct yuanrdma_cq *cq = to_yuanrdma_cq(ibcq);
	int n = 0;

	spin_lock_bh(&cq->lock);
	while (n < num_entries && cq->count) {
		wc[n++] = cq->entries[cq->head];
		cq->head = (cq->head + 1) % cq->depth;
		cq->count--;
	}
	spin_unlock_bh(&cq->lock);
	return n;
}

int yuanrdma_req_notify_cq(struct ib_cq *ibcq, enum ib_cq_notify_flags flags)
{
	struct yuanrdma_cq *cq = to_yuanrdma_cq(ibcq);
	int ret = 0;

	spin_lock_bh(&cq->lock);
	if (cq->count)
		ret = 1;		/* 有遗留完成：poll 方靠这个返回值决定是否重新排队 */
	cq->notify = flags & IB_CQ_SOLICITED_MASK;
	spin_unlock_bh(&cq->lock);
	return ret;
}

/* ---------------------------------------------------------------- AH */

/*
 * kernel 侧 AH（create_ah 的 udata == NULL）与用户态 UD 的 AH 共用这个解析：
 *   - 内核 MAD/CM：MAD 层用 ib_create_ah 建 AH，发 QP1 时把 dmac/sip/dip 交给软件 GSI 组帧；
 *   - 用户态 UD：provider 走 ibv_cmd_create_ah → uverbs 调到这里（udata 非空），
 *     解析出的 dmac/dip 在 provider 组 WQE 之前先写进 QPC 的 AV 字段（Eth/IP 头由 RTL 从
 *     QPC 取，见 roce_tx 的 header_computed），remote_qpn/qkey 随 WQE 走。
 * 两边的合法性要求完全一样：RoCEv2（IB_GID_TYPE_ROCE_UDP_ENCAP）+ IPv4（v4-mapped GID）。
 * 解析不出来的组合一律明确报错，不发一个「地址看起来是 0.0.0.0」的帧出去。
 */
static int yuanrdma_ah_from_attr(struct yuanrdma_ah *ah, const struct rdma_ah_attr *attr)
{
	const struct ib_global_route *grh;

	if (!attr || attr->type != RDMA_AH_ATTR_TYPE_ROCE)
		return -EINVAL;
	grh = rdma_ah_read_grh(attr);
	/* 5.15 的 ib_global_route 只有 dgid，源 GID 在 sgid_attr->gid 里（mlx5 ah.c 同样取法） */
	if (!grh->sgid_attr)
		return -EINVAL;
	if (grh->sgid_attr->gid_type != IB_GID_TYPE_ROCE_UDP_ENCAP)
		return -EOPNOTSUPP;
	if (!ipv6_addr_v4mapped((const struct in6_addr *)grh->sgid_attr->gid.raw) ||
	    !ipv6_addr_v4mapped((const struct in6_addr *)grh->dgid.raw))
		return -EOPNOTSUPP;	/* 只支持 RoCEv2 + IPv4 */

	memcpy(ah->dmac, attr->roce.dmac, ETH_ALEN);
	memcpy(&ah->sip, &grh->sgid_attr->gid.raw[12], 4);
	memcpy(&ah->dip, &grh->dgid.raw[12], 4);
	ah->tos = grh->traffic_class;
	ah->ttl = grh->hop_limit ? grh->hop_limit : 64;
	ah->sport = rdma_flow_label_to_udp_sport(grh->flow_label);
	return 0;
}

int yuanrdma_create_ah(struct ib_ah *ibah, struct rdma_ah_init_attr *init, struct ib_udata *udata)
{
	struct yuanrdma_ah *ah = to_yuanrdma_ah(ibah);
	int ret;

	/*
	 * udata 非空 = 用户态 UD 的 ibv_create_ah。这里不再拒绝：UD 的 AH 内容（dmac/dip/
	 * sport）正是 QPC 的 AV 需要的，provider 建 AH 时就让内核解析并校验一遍，
	 * 用户态拿到的是「地址已经验证过」的句柄；真正的组装在 provider 与 RTL。
	 *
	 * 2026-11-21 起 UD 与 RC 同时支持，不再有 enable_ud 开关；AH 与 UD QP 都在
	 * 同一批镜像上可用，不会出现「AH 建成了、QP 建不起来」的半截状态。
	 * 内核 CM 的 AH（udata == NULL）走同一段解析。
	 *
	 * 注意：yuanrdma_ah 只存解析结果，没有 per-AH 的引用计数或硬件资源；
	 * destroy_ah 是空实现（RoCE AH 本来就无硬件状态）。
	 */
	if (!init || !init->ah_attr)
		return -EINVAL;
	ret = yuanrdma_ah_from_attr(ah, init->ah_attr);
	if (ret)
		return ret;
	ibah->type = init->ah_attr->type;
	return 0;
}

int yuanrdma_destroy_ah(struct ib_ah *ibah, u32 flags)
{
	return 0;
}

/* ---------------------------------------------------------------- 哑 DMA MR */

/*
 * get_dma_mr 是 kverbs_provider 的强制项：返回一个「本地 DMA lkey」的 MR 给内核 ULP。
 * 硬件没有这个 lkey，这里只给一个不占 MPT/MTT 的哑 MR，dereg_mr 认出来直接释放。
 */
struct ib_mr *yuanrdma_get_dma_mr(struct ib_pd *ibpd, int access_flags)
{
	struct yuanrdma_mr *mr;

	mr = kzalloc(sizeof(*mr), GFP_KERNEL);
	if (!mr)
		return ERR_PTR(-ENOMEM);
	mr->dma_mr = true;
	mr->ibmr.lkey = mr->ibmr.rkey = 0;	/* 不会出现在线路上 */
	mr->ibmr.device = ibpd->device;
	mr->ibmr.pd = ibpd;
	return &mr->ibmr;
}

/* ---------------------------------------------------------------- QP1 生命周期 */

int yuanrdma_gsi_create_qp(struct yuanrdma_qp *qp, struct ib_qp_init_attr *init)
{
	struct yuanrdma_dev *dev = to_yuanrdma_dev(qp->ibqp.device);
	struct yuanrdma_gsi_qp *gsi;
	int ret;

	if (init->srq || init->create_flags)
		return -EOPNOTSUPP;
	if (!to_yuanrdma_cq(init->send_cq)->software || !to_yuanrdma_cq(init->recv_cq)->software)
		return -EOPNOTSUPP;
	if (init->cap.max_send_sge > YUANRDMA_GSI_MAX_SGE ||
	    init->cap.max_recv_sge > YUANRDMA_GSI_MAX_SGE ||
	    init->cap.max_send_wr > YUANRDMA_GSI_SQ_DEPTH ||
	    init->cap.max_recv_wr > YUANRDMA_GSI_RQ_DEPTH)
		return -EINVAL;

	gsi = kzalloc(sizeof(*gsi), GFP_KERNEL);
	if (!gsi)
		return -ENOMEM;
	gsi->sq.entries = kcalloc(YUANRDMA_GSI_SQ_DEPTH, sizeof(*gsi->sq.entries), GFP_KERNEL);
	gsi->rq.entries = kcalloc(YUANRDMA_GSI_RQ_DEPTH, sizeof(*gsi->rq.entries), GFP_KERNEL);
	if (!gsi->sq.entries || !gsi->rq.entries) {
		ret = -ENOMEM;
		goto free_entries;
	}
	gsi->sq.size = YUANRDMA_GSI_SQ_DEPTH;
	gsi->rq.size = YUANRDMA_GSI_RQ_DEPTH;
	gsi->dev = dev;
	gsi->ibqp = &qp->ibqp;
	gsi->state = IB_QPS_RESET;
	gsi->qkey = FGSI_GSI_QKEY;
	gsi->sq_psn = 0;
	spin_lock_init(&gsi->lock);
	INIT_WORK(&gsi->tx_work, yuanrdma_gsi_tx_work);

	qp->gsi = gsi;
	qp->state = IB_QPS_RESET;
	qp->ibqp.qp_num = YUANRDMA_GSI_QPN;
	/* 收包通路只认 dev->gsi：yuanrdma_gsi_rx 在 rcu_dereference(dev->gsi) 为 NULL 时
	 * 直接 rx_no_qp++ 并吞掉整帧。只挂 qp->gsi 时发送方向是通的（post_send 走 qp->gsi），
	 * 但**接收方向全断**，表现为「REQ 发出去了、REP 永远不回」。
	 * destroy_qp 里有配套的 rcu_assign_pointer(NULL) + synchronize_rcu()。 */
	rcu_assign_pointer(dev->gsi, gsi);

	init->cap.max_send_sge = YUANRDMA_GSI_MAX_SGE;
	init->cap.max_recv_sge = YUANRDMA_GSI_MAX_SGE;
	init->cap.max_send_wr = YUANRDMA_GSI_SQ_DEPTH;
	init->cap.max_recv_wr = YUANRDMA_GSI_RQ_DEPTH;
	init->cap.max_inline_data = 0;
	return 0;

free_entries:
	kfree(gsi->sq.entries);
	kfree(gsi->rq.entries);
	kfree(gsi);
	return ret;
}

int yuanrdma_gsi_modify_qp(struct yuanrdma_qp *qp, struct ib_qp_attr *attr, int mask)
{
	struct yuanrdma_gsi_qp *gsi = qp->gsi;
	enum ib_qp_state new_state = (mask & IB_QP_STATE) ? attr->qp_state : qp->state;

	/* MAD 层只走 RESET → INIT → RTR → RTS（mad.c 的 create_mad_qp） */
	if (new_state != qp->state && new_state != IB_QPS_INIT && new_state != IB_QPS_RTR &&
	    new_state != IB_QPS_RTS && new_state != IB_QPS_ERR)
		return -EINVAL;
	spin_lock_bh(&gsi->lock);
	if (mask & IB_QP_QKEY)
		gsi->qkey = attr->qkey;
	if (mask & IB_QP_SQ_PSN)
		gsi->sq_psn = attr->sq_psn & 0xffffff;
	gsi->state = new_state;
	spin_unlock_bh(&gsi->lock);
	qp->state = new_state;
	return 0;
}

int yuanrdma_gsi_query_qp(struct yuanrdma_qp *qp, struct ib_qp_attr *attr, int mask,
			  struct ib_qp_init_attr *init)
{
	struct yuanrdma_gsi_qp *gsi = qp->gsi;

	memset(attr, 0, sizeof(*attr));
	memset(init, 0, sizeof(*init));
	spin_lock_bh(&gsi->lock);
	attr->qp_state = attr->cur_qp_state = gsi->state;
	attr->qkey = gsi->qkey;
	attr->sq_psn = gsi->sq_psn;
	spin_unlock_bh(&gsi->lock);
	attr->cap.max_send_wr = YUANRDMA_GSI_SQ_DEPTH;
	attr->cap.max_recv_wr = YUANRDMA_GSI_RQ_DEPTH;
	attr->cap.max_send_sge = YUANRDMA_GSI_MAX_SGE;
	attr->cap.max_recv_sge = YUANRDMA_GSI_MAX_SGE;
	init->qp_type = IB_QPT_GSI;
	init->send_cq = qp->ibqp.send_cq;
	init->recv_cq = qp->ibqp.recv_cq;
	init->cap = attr->cap;
	init->sq_sig_type = IB_SIGNAL_REQ_WR;
	return 0;
}

/* ---------------------------------------------------------------- QP1 发送 */

static void yuanrdma_gsi_complete(struct ib_qp *ibqp, const struct yuanrdma_gsi_wr *wr,
				  enum ib_wc_status status)
{
	struct ib_wc wc = {};

	if (!(wr->flags & GSI_WR_SIGNALED))
		return;
	wc.wr_cqe = wr->wr_cqe;
	wc.wr_id = wr->wr_id;
	wc.status = status;
	wc.opcode = IB_WC_SEND;
	wc.qp = ibqp;
	wc.port_num = 1;
	yuanrdma_gsi_cq_push(ibqp->send_cq, &wc);
}

static struct sk_buff *yuanrdma_gsi_build(struct yuanrdma_dev *dev, struct yuanrdma_gsi_qp *gsi,
					  const struct yuanrdma_gsi_wr *wr,
					  const struct yuanrdma_ah *ah)
{
	struct fgsi_tx t = {};
	struct sk_buff *skb;
	size_t total, payload_length = 0;
	u8 *frame;
	int i;

	for (i = 0; i < wr->num_sge; i++)
		payload_length += wr->sge[i].length;

	memcpy(t.dmac, ah->dmac, ETH_ALEN);
	memcpy(t.smac, dev->netdev->dev_addr, ETH_ALEN);
	memcpy(t.sip, &ah->sip, 4);
	memcpy(t.dip, &ah->dip, 4);
	t.tos = ah->tos;
	t.ttl = ah->ttl;
	t.ip_id = (u16)atomic_inc_return(&yuanrdma_gsi_ip_id);
	t.sport = ah->sport;
	t.opcode = (wr->flags & GSI_WR_HAS_IMM) ? FGSI_OP_UD_SEND_ONLY_IMM : FGSI_OP_UD_SEND_ONLY;
	t.pkey = 0xffff;
	t.dqpn = wr->dqpn;
	t.psn = gsi->sq_psn;
	t.qkey = wr->qkey;
	t.sqpn = YUANRDMA_GSI_QPN;
	if (wr->flags & GSI_WR_HAS_IMM)
		memcpy(t.imm, &wr->imm, 4);

	total = fgsi_frame_length(t.opcode, payload_length);
	/* 前面留 32 B：yuanmcdma 的 H2D 会把帧拷进对齐的 bounce 缓冲，这里只保证 IP 头对齐 */
	skb = alloc_skb(total + NET_IP_ALIGN + 32, GFP_ATOMIC);
	if (!skb)
		return NULL;
	skb_reserve(skb, NET_IP_ALIGN + 32);
	skb_reset_mac_header(skb);
	frame = skb_put(skb, total);
	fgsi_build_headers(frame, &t, payload_length);

	frame += fgsi_header_length(t.opcode);
	for (i = 0; i < wr->num_sge; i++) {
		void *src = yuanrdma_dma_to_virt(dev, wr->sge[i].addr, wr->sge[i].length);

		if (!src) {
			dev_warn_ratelimited(&dev->pdev->dev,
					     "gsi tx: sge %d 地址翻译失败（dma %llx len %u）\n",
					     i, (unsigned long long)wr->sge[i].addr, wr->sge[i].length);
			kfree_skb(skb);
			return NULL;
		}
		memcpy(frame, src, wr->sge[i].length);
		frame += wr->sge[i].length;
	}
	fgsi_seal(skb->data, total);

	skb->dev = dev->netdev;
	skb->protocol = htons(ETH_P_IP);
	skb->ip_summed = CHECKSUM_NONE;
	skb->priority = 0;
	return skb;
}

static void yuanrdma_gsi_tx_work(struct work_struct *work)
{
	struct yuanrdma_gsi_qp *gsi = container_of(work, struct yuanrdma_gsi_qp, tx_work);
	struct yuanrdma_dev *dev = gsi->dev;
	struct yuanrdma_gsi_wr wr;
	struct sk_buff *skb;

	/* 一次取一个 WR：有序 workqueue 保证顺序；整批拷到局部数组会超内核 1 KB 栈帧线 */
	for (;;) {
		spin_lock_bh(&gsi->lock);
		if (gsi->dead || gsi->sq.cons == gsi->sq.prod) {
			gsi->work_queued = false;
			spin_unlock_bh(&gsi->lock);
			return;
		}
		wr = gsi->sq.entries[gsi->sq.cons % gsi->sq.size];
		gsi->sq.cons++;
		gsi->sq_psn = (gsi->sq_psn + 1) & 0xffffff;
		spin_unlock_bh(&gsi->lock);

		if (!wr.ah) {
			dev->gsi_stats.tx_bad_wr++;
			yuanrdma_gsi_complete(gsi->ibqp, &wr, IB_WC_LOC_QP_OP_ERR);
			continue;
		}
		skb = yuanrdma_gsi_build(dev, gsi, &wr, to_yuanrdma_ah(wr.ah));
		if (!skb) {
			dev->gsi_stats.tx_bad_wr++;
			yuanrdma_gsi_complete(gsi->ibqp, &wr, IB_WC_LOC_PROT_ERR);
			continue;
		}
		dev_queue_xmit(skb);
		dev->gsi_stats.tx_packets++;
		yuanrdma_gsi_complete(gsi->ibqp, &wr, IB_WC_SUCCESS);
	}
}

int yuanrdma_post_send(struct ib_qp *ibqp, const struct ib_send_wr *wr, const struct ib_send_wr **bad_wr)
{
	struct yuanrdma_qp *qp = to_yuanrdma_qp(ibqp);
	struct yuanrdma_gsi_qp *gsi = qp->gsi;
	int ret = 0;

	if (!gsi)
		return -EOPNOTSUPP;		/* 用户态 RC 的数据面在 provider 里，内核不经这里 */
	spin_lock_bh(&gsi->lock);
	for (; wr; wr = wr->next) {
		struct yuanrdma_gsi_wr *e;
		int i;

		if (gsi->dead || gsi->state != IB_QPS_RTS) {
			ret = -EINVAL;
			break;
		}
		if (wr->opcode != IB_WR_SEND || wr->num_sge > YUANRDMA_GSI_MAX_SGE ||
		    (wr->num_sge && !wr->sg_list)) {
			ret = -EINVAL;
			break;
		}
		if (gsi->sq.prod - gsi->sq.cons >= gsi->sq.size) {
			ret = -ENOMEM;
			break;
		}
		if (wr->send_flags & IB_SEND_INLINE) {
			ret = -EOPNOTSUPP;
			break;
		}
		e = &gsi->sq.entries[gsi->sq.prod % gsi->sq.size];
		memset(e, 0, sizeof(*e));
		e->wr_id = wr->wr_id;
		e->wr_cqe = wr->wr_cqe;
		e->ah = ud_wr(wr)->ah;
		e->opcode = wr->opcode;
		if (wr->send_flags & IB_SEND_SIGNALED)
			e->flags |= GSI_WR_SIGNALED;
		if (wr->ex.imm_data) {
			e->flags |= GSI_WR_HAS_IMM;
			e->imm = wr->ex.imm_data;
		}
		e->num_sge = wr->num_sge;
		for (i = 0; i < wr->num_sge; i++) {
			e->sge[i].addr = wr->sg_list[i].addr;
			e->sge[i].length = wr->sg_list[i].length;
		}
		/* UD 约定：remote_qkey 最高位为 1 表示「用 QP 自己的 Q_Key」（内核 MAD 发的就是这种） */
		e->qkey = (ud_wr(wr)->remote_qkey & 0x80000000) ? gsi->qkey : ud_wr(wr)->remote_qkey;
		e->dqpn = ud_wr(wr)->remote_qpn;
		gsi->sq.prod++;
	}
	if (ret) {
		if (bad_wr)
			*bad_wr = wr;
	} else if (gsi->sq.cons != gsi->sq.prod && !gsi->work_queued) {
		gsi->work_queued = true;
		queue_work(gsi->dev->gsi_wq, &gsi->tx_work);
	}
	spin_unlock_bh(&gsi->lock);
	return ret;
}

int yuanrdma_post_recv(struct ib_qp *ibqp, const struct ib_recv_wr *wr, const struct ib_recv_wr **bad_wr)
{
	struct yuanrdma_qp *qp = to_yuanrdma_qp(ibqp);
	struct yuanrdma_gsi_qp *gsi = qp->gsi;
	int ret = 0;

	if (!gsi)
		return -EOPNOTSUPP;
	spin_lock_bh(&gsi->lock);
	for (; wr; wr = wr->next) {
		struct yuanrdma_gsi_wr *e;
		int i;

		if (gsi->dead || wr->num_sge > YUANRDMA_GSI_MAX_SGE ||
		    (wr->num_sge && !wr->sg_list)) {
			ret = -EINVAL;
			break;
		}
		if (gsi->rq.prod - gsi->rq.cons >= gsi->rq.size) {
			ret = -ENOMEM;
			break;
		}
		e = &gsi->rq.entries[gsi->rq.prod % gsi->rq.size];
		memset(e, 0, sizeof(*e));
		e->wr_id = wr->wr_id;
		e->wr_cqe = wr->wr_cqe;
		e->num_sge = wr->num_sge;
		for (i = 0; i < wr->num_sge; i++) {
			e->sge[i].addr = wr->sg_list[i].addr;
			e->sge[i].length = wr->sg_list[i].length;
		}
		gsi->rq.prod++;
	}
	if (ret && bad_wr)
		*bad_wr = wr;
	spin_unlock_bh(&gsi->lock);
	return ret;
}

void yuanrdma_gsi_destroy_qp(struct yuanrdma_qp *qp)
{
	struct yuanrdma_gsi_qp *gsi = qp->gsi;
	struct yuanrdma_gsi_wr *wr;
	struct ib_wc wc = {};
	struct yuanrdma_dev *dev;

	if (!gsi)
		return;
	dev = gsi->dev;
	spin_lock_bh(&gsi->lock);
	gsi->dead = true;
	spin_unlock_bh(&gsi->lock);
	cancel_work_sync(&gsi->tx_work);

	/* 让收包路径（RCU）看不到这个 QP，再等一轮 */
	rcu_assign_pointer(dev->gsi, NULL);
	synchronize_rcu();

	/* 未发的 SEND、未收的 RECV 全部按 flush 完成，MAD 层靠它释放缓冲 */
	spin_lock_bh(&gsi->lock);
	while (gsi->sq.cons != gsi->sq.prod) {
		wr = &gsi->sq.entries[gsi->sq.cons % gsi->sq.size];
		gsi->sq.cons++;
		yuanrdma_gsi_complete(&qp->ibqp, wr, IB_WC_WR_FLUSH_ERR);
	}
	while (gsi->rq.cons != gsi->rq.prod) {
		wr = &gsi->rq.entries[gsi->rq.cons % gsi->rq.size];
		gsi->rq.cons++;
		memset(&wc, 0, sizeof(wc));
		wc.wr_cqe = wr->wr_cqe;
		wc.wr_id = wr->wr_id;
		wc.status = IB_WC_WR_FLUSH_ERR;
		wc.opcode = IB_WC_RECV;
		wc.qp = &qp->ibqp;
		wc.port_num = 1;
		yuanrdma_gsi_cq_push(qp->ibqp.recv_cq, &wc);
	}
	spin_unlock_bh(&gsi->lock);

	kfree(gsi->sq.entries);
	kfree(gsi->rq.entries);
	kfree(gsi);
	qp->gsi = NULL;
}

/* ---------------------------------------------------------------- QP1 接收 */

/*
 * 把一个 QP1 UD SEND 交付给 MAD 层：
 *   接收缓冲前 40 B 是 GRH，IPv4 时前 20 B 清零、后 20 B 放原 IPv4 头
 *   （union rdma_network_hdr 的约定，ib_init_ah_attr_from_wc 会从这里取地址）。
 */
static void yuanrdma_gsi_deliver(struct yuanrdma_dev *dev, struct yuanrdma_gsi_qp *gsi,
				 struct sk_buff *skb, const struct fgsi_rx *r, const u8 *l3)
{
	struct yuanrdma_gsi_wr wr;
	struct ib_wc wc = {};
	struct yuanrdma_gsi_ring *ring;
	u8 *p;
	u32 n;

	/* 注意：struct ib_wc wc = {} 的 status 是 **0 = IB_WC_SUCCESS**。
	 * 所以每条失败路径都必须先把 status 改成错误码再 goto out，否则 out 处会向
	 * recv_cq 投递一个 wr_cqe=NULL 的「成功」完成，MAD 层 poll 到它执行
	 * wc.wr_cqe->done() 就是空指针解引用。 */
	spin_lock_bh(&gsi->lock);
	if (gsi->dead || (gsi->state != IB_QPS_RTR && gsi->state != IB_QPS_RTS)) {
		dev->gsi_stats.rx_no_qp++;
		wc.status = IB_WC_WR_FLUSH_ERR;
		goto out;
	}
	if (r->qkey != gsi->qkey || r->pkey != 0xffff) {
		dev->gsi_stats.rx_bad_header++;
		wc.status = IB_WC_LOC_QP_OP_ERR;
		goto out;
	}
	if (gsi->rq.cons == gsi->rq.prod) {
		dev->gsi_stats.rx_no_recv++;	/* UD 语义：没有接收 WR 就静默丢弃 */
		wc.status = IB_WC_LOC_QP_OP_ERR;
		goto out;
	}
	ring = &gsi->rq;
	wr = ring->entries[ring->cons % ring->size];

	if (wr.num_sge != 1 || wr.sge[0].length < YUANRDMA_GSI_GRH_LEN + r->payload_length) {
		/* MAD 每次只挂一个 512 B 的 SGE，长度不够说明对端发的不是 MAD */
		dev->gsi_stats.rx_bad_header++;
		wc.status = IB_WC_LOC_LEN_ERR;
		goto out;
	}
	p = yuanrdma_dma_to_virt(dev, wr.sge[0].addr, wr.sge[0].length);
	if (!p) {
		dev->gsi_stats.rx_bad_header++;
		wc.status = IB_WC_LOC_PROT_ERR;
		goto out;
	}
	ring->cons++;
	n = YUANRDMA_GSI_GRH_LEN + r->payload_length;
	memset(p, 0, YUANRDMA_GSI_GRH_LEN);
	memcpy(p + YUANRDMA_GSI_GRH_LEN - FGSI_IP_LEN, l3, FGSI_IP_LEN);
	memcpy(p + YUANRDMA_GSI_GRH_LEN, l3 + r->payload_offset, r->payload_length);
	dev->gsi_stats.rx_packets++;

	/*
	 * CM MAD 分类计数。驱动不解析 CM 语义（那是 ib_cm 的活），但上板时最常问的是
	 * 「REQ 到底有没有进驱动」——按 attr_id 计数能直接回答，不必抓包。
	 * 只统计，不改变交付行为：分类失败也照样交给 MAD 层，让 ib_cm 自己判。
	 * 先用 mgmt_class 字节筛一道：UDP 4791 上 A 类 MAD 只有 CM（0x07），其它管理类
	 * （0x03 SubnAdm 等）走的是别的东西，不该记进 cm_rx_bad。
	 */
	if (r->payload_length >= FGCM_MAD_LEN &&
	    *(l3 + r->payload_offset + 1) == FGCM_MGMT_CLASS_CM) {
		int attr = fgcm_classify(l3 + r->payload_offset, r->payload_length);

		if (attr >= FGCM_ATTR_REQ && attr <= FGCM_ATTR_APR)
			dev->gsi_stats.cm_rx[attr - FGCM_ATTR_REQ]++;
		else if (attr < 0)
			dev->gsi_stats.cm_rx_bad++;	/* 头不合法或 attr_id 不认识 */
	}

	memset(&wc, 0, sizeof(wc));
	wc.wr_cqe = wr.wr_cqe;
	wc.wr_id = wr.wr_id;
	wc.status = IB_WC_SUCCESS;
	wc.opcode = IB_WC_RECV;
	wc.byte_len = n;
	wc.qp = gsi->ibqp;
	wc.src_qp = r->sqpn;
	wc.pkey_index = 0;
	wc.port_num = 1;
	wc.wc_flags = IB_WC_GRH | IB_WC_WITH_NETWORK_HDR_TYPE;
	wc.network_hdr_type = RDMA_NETWORK_IPV4;
	/* eth_type_trans 已经把 ETH_HLEN pull 掉了（本函数开头的 l3 就是 IPv4 头），
	 * skb->data + 6 读到的是 IP 头的 flags/frag，不是源 MAC。改从 mac header 取。 */
	memcpy(wc.smac, skb_mac_header(skb) + ETH_ALEN, ETH_ALEN);
out:
	spin_unlock_bh(&gsi->lock);
	if (wc.status == IB_WC_SUCCESS)
		yuanrdma_gsi_cq_push(gsi->ibqp->recv_cq, &wc);
}

/*
 * eth0 的收包挂钩。yuanmcdma 走 netif_receive_skb，rx_handler 在协议栈之前、tcpdump 之后
 * 被调用，所以抓包仍然看得到这些帧。
 *   - 不是 IPv4 无选项 / 不是 UDP / 分片 / 目的 IP 不是我们的 RoCEv2 地址 / 端口不是 4791
 *     → 原样放行；
 *   - UDP 4791 但不是 UD SEND 或 dest QP != 1（RC 数据流）→ drop_rc_on_netdev 时丢弃；
 *   - QP1 → 校验并交付，帧被消费。
 * 注意 rx_handler 是独占的：eth0 上不能同时挂 bridge/bond/macvlan。
 */
static rx_handler_result_t yuanrdma_gsi_rx(struct sk_buff **pskb)
{
	struct sk_buff *skb = *pskb;
	struct yuanrdma_dev *dev = rcu_dereference(skb->dev->rx_handler_data);
	const u8 *l3, *udp, *bth;
	struct sk_buff *copy;
	unsigned int l3_len;
	struct yuanrdma_gsi_qp *gsi;
	struct fgsi_rx r;
	u8 buf[FGSI_L3_HDR_LEN + FGSI_DETH_LEN + FGSI_IMM_LEN];
	int rc;

	if (!dev)
		return RX_HANDLER_PASS;
	if (skb->protocol != htons(ETH_P_IP))
		return RX_HANDLER_PASS;
	/* 只在包头完整时预判；不够长就放行交给协议栈 */
	l3 = skb_header_pointer(skb, 0, sizeof(buf), buf);
	if (!l3)
		return RX_HANDLER_PASS;
	if (l3[0] != 0x45 || l3[9] != 17)
		return RX_HANDLER_PASS;
	if (fgsi_get16(l3 + 6) & 0x1fff)
		return RX_HANDLER_PASS;		/* 分片帧不拆，交给协议栈 */
	udp = l3 + FGSI_IP_LEN;
	if (fgsi_get16(udp + 2) != FGSI_ROCE_UDP_PORT)
		return RX_HANDLER_PASS;
	/*
	 * 本端 IPv4 过滤：**必须用 fgsi_get32 比大端值，不能用 memcmp 比内存字节**。
	 *
	 * dev->ipv4 在 yuanrdma_add_gid() 里用 get_unaligned_be32(&raw[12]) 赋值，
	 * 是「按大端读出来的主机序 u32」。而 l3+16 是线上字节（网络序）。
	 * 在 x86 这种小端机器上 &dev->ipv4 的内存字节是反的（192.168.50.1 →
	 * 内存 01 32 A8 C0，线上 C0 A8 32 01），memcmp 恒不相等 ⇒ **每一帧 QP1
	 * 都在这里被静默 PASS 掉**，表现为 gsi_stats 全部为 0、CM 永远连不上
	 * （2026-11-18 B6502 实测：对端 REP 已回到网口、tcpdump 抓得到，
	 * 但 rx_packets/rx_rc_dropped 都不动）。上面几处 fgsi_get16/24 已经是
	 * 大端解析，这里保持同一口径即可。
	 */
	if (dev->ipv4 && fgsi_get32(l3 + 16) != dev->ipv4)
		return RX_HANDLER_PASS;
	bth = udp + FGSI_UDP_LEN;
	if (bth[0] != FGSI_OP_UD_SEND_ONLY && bth[0] != FGSI_OP_UD_SEND_ONLY_IMM) {
		dev->gsi_stats.rx_rc_dropped++;
		return drop_rc_on_netdev ? RX_HANDLER_CONSUMED : RX_HANDLER_PASS;
	}
	if (fgsi_get24(bth + 5) != YUANRDMA_GSI_QPN)
		return RX_HANDLER_PASS;
	rcu_read_lock();
	gsi = rcu_dereference(dev->gsi);
	if (!gsi) {
		dev->gsi_stats.rx_no_qp++;
		rcu_read_unlock();
		return RX_HANDLER_CONSUMED;
	}

	/* QP1 帧很少，直接拷贝一份私有副本处理，不动共享 skb。
	 * 整个处理（含 yuanrdma_gsi_deliver）必须在 rcu_read_lock() 保护区内完成：
	 * destroy_qp 是 rcu_assign_pointer(NULL) + synchronize_rcu() 后 kfree(gsi)，
	 * 一旦这里提前解锁，synchronize_rcu() 就可以返回并释放 gsi，而 deliver 还在用它
	 * （读 gsi->lock / rq / dead），是典型的 UAF 窗口。软拷贝与 linearize 都不睡眠。 */
	/* 原始 skb 由网络栈负责释放：rx_handler 返回 CONSUMED 时 __netif_receive_skb
	 * **不会** free 它（约定是 handler 已消费），所以这里必须自己 consume_skb()，
	 * 否则每来一个 QP1 帧泄漏一个 skb。后面 free 标签只释放这份私有副本，所以副本
	 * 用独立变量名，别再覆盖 skb。 */
	copy = skb_copy(skb, GFP_ATOMIC);
	consume_skb(skb);
	if (!copy) {
		rcu_read_unlock();
		return RX_HANDLER_CONSUMED;
	}
	skb = copy;
	if (skb_linearize(skb))
		goto free;
	l3 = skb->data;
	l3_len = skb->len;
	rc = fgsi_parse(l3, l3_len, &r);
	if (rc == FGSI_ERR_ICRC)
		dev->gsi_stats.rx_icrc_error++;
	else if (rc)
		dev->gsi_stats.rx_bad_header++;
	else
		yuanrdma_gsi_deliver(dev, gsi, skb, &r, l3);
free:
	kfree_skb(skb);
	rcu_read_unlock();
	return RX_HANDLER_CONSUMED;
}

/* ---------------------------------------------------------------- init / cleanup */

static int yuanrdma_gsi_stats_show(struct seq_file *s, void *unused)
{
	struct yuanrdma_dev *dev = s->private;
	const struct yuanrdma_gsi_stats *g = &dev->gsi_stats;

	seq_printf(s, "tx_packets     %llu\n", g->tx_packets);
	seq_printf(s, "tx_bad_wr      %llu\n", g->tx_bad_wr);
	seq_printf(s, "rx_packets     %llu\n", g->rx_packets);
	seq_printf(s, "rx_icrc_error  %llu\n", g->rx_icrc_error);
	seq_printf(s, "rx_bad_header  %llu\n", g->rx_bad_header);
	seq_printf(s, "rx_no_qp       %llu\n", g->rx_no_qp);
	seq_printf(s, "rx_no_recv     %llu\n", g->rx_no_recv);
	seq_printf(s, "rx_rc_dropped  %llu\n", g->rx_rc_dropped);
	seq_printf(s, "cm_rx_req      %llu\n", g->cm_rx[FGCM_ATTR_REQ - FGCM_ATTR_REQ]);
	seq_printf(s, "cm_rx_mra      %llu\n", g->cm_rx[FGCM_ATTR_MRA - FGCM_ATTR_REQ]);
	seq_printf(s, "cm_rx_rej      %llu\n", g->cm_rx[FGCM_ATTR_REJ - FGCM_ATTR_REQ]);
	seq_printf(s, "cm_rx_rep      %llu\n", g->cm_rx[FGCM_ATTR_REP - FGCM_ATTR_REQ]);
	seq_printf(s, "cm_rx_rtu      %llu\n", g->cm_rx[FGCM_ATTR_RTU - FGCM_ATTR_REQ]);
	seq_printf(s, "cm_rx_dreq     %llu\n", g->cm_rx[FGCM_ATTR_DREQ - FGCM_ATTR_REQ]);
	seq_printf(s, "cm_rx_drep     %llu\n", g->cm_rx[FGCM_ATTR_DREP - FGCM_ATTR_REQ]);
	seq_printf(s, "cm_rx_sidr_req %llu\n", g->cm_rx[FGCM_ATTR_SIDR_REQ - FGCM_ATTR_REQ]);
	seq_printf(s, "cm_rx_sidr_rep %llu\n", g->cm_rx[FGCM_ATTR_SIDR_REP - FGCM_ATTR_REQ]);
	seq_printf(s, "cm_rx_lap      %llu\n", g->cm_rx[FGCM_ATTR_LAP - FGCM_ATTR_REQ]);
	seq_printf(s, "cm_rx_apr      %llu\n", g->cm_rx[FGCM_ATTR_APR - FGCM_ATTR_REQ]);
	seq_printf(s, "cm_rx_bad      %llu\n", g->cm_rx_bad);
	return 0;
}

static int yuanrdma_gsi_stats_open(struct inode *inode, struct file *file)
{
	return single_open(file, yuanrdma_gsi_stats_show, inode->i_private);
}

static const struct file_operations yuanrdma_gsi_stats_fops = {
	.owner = THIS_MODULE,
	.open = yuanrdma_gsi_stats_open,
	.read = seq_read,
	.llseek = seq_lseek,
	.release = single_release,
};

int yuanrdma_gsi_init(struct yuanrdma_dev *dev)
{
	int ret;

	dev->gsi_wq = alloc_ordered_workqueue("yuanrdma_gsi", WQ_MEM_RECLAIM);
	if (!dev->gsi_wq)
		return -ENOMEM;
	ret = netdev_rx_handler_register(dev->netdev, yuanrdma_gsi_rx, dev);
	if (ret) {
		dev_err(&dev->pdev->dev, "gsi: eth0 上挂 rx_handler 失败 %d（已被 bridge/bond 占用？）\n", ret);
		goto destroy_wq;
	}
	dev->gsi_rx_registered = true;
	dev->debugfs = debugfs_create_file("gsi_stats", 0444, NULL, dev, &yuanrdma_gsi_stats_fops);
	if (IS_ERR_OR_NULL(dev->debugfs))
		dev->debugfs = NULL;
	return 0;

destroy_wq:
	destroy_workqueue(dev->gsi_wq);
	dev->gsi_wq = NULL;
	return ret;
}

void yuanrdma_gsi_cleanup(struct yuanrdma_dev *dev)
{
	if (dev->debugfs)
		debugfs_remove(dev->debugfs);
	dev->debugfs = NULL;
	if (dev->gsi_rx_registered) {
		netdev_rx_handler_unregister(dev->netdev);
		dev->gsi_rx_registered = false;
	}
	if (dev->gsi_wq) {
		flush_workqueue(dev->gsi_wq);
		destroy_workqueue(dev->gsi_wq);
		dev->gsi_wq = NULL;
	}
}
