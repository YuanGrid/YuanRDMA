// SPDX-License-Identifier: GPL-2.0
/*-
 * Copyright(c) 2020-21 Intel Corporation. All rights reserved.
 */

#include "ifc_mcdma_net.h"
#include "ifc_mcdma_ethtool.h"
#include <net/sock.h>
#include <linux/rbtree.h>
#include <linux/cpumask.h>
#include <linux/netdevice.h>
#include <linux/version.h>
#include <linux/if_ether.h>
#include <linux/if_vlan.h>
#include <linux/list.h>
#include "ifc_mcdma_ioctl.h"
#include <linux/byteorder/little_endian.h>
#include "ifc_mcdma_bas.h"

/* Default symmetric Toeplitz RSS hash key (40 bytes).
 * Identical to the key used by Intel NICs; produces good distribution
 * for TCP/UDP over IPv4 and IPv6.
 */
static const u8 ifc_mcdma_rss_key_default[IFC_MCDMA_RSS_KEY_SIZE] = {
	0x6d, 0x5a, 0x56, 0xda, 0x25, 0x5b, 0x0e, 0xc2,
	0x41, 0x67, 0x25, 0x3d, 0x43, 0xa3, 0x8f, 0xb0,
	0xd0, 0xca, 0x2b, 0xcb, 0xae, 0x7b, 0x30, 0xb4,
	0x77, 0xcb, 0x2d, 0xa3, 0x80, 0x30, 0xf2, 0x0c,
	0x6a, 0x42, 0xb7, 0x3b, 0xbe, 0xac, 0x01, 0xfa,
};

#define DEFAULT_MSG_ENABLE (NETIF_MSG_DRV | NETIF_MSG_PROBE | NETIF_MSG_IFUP | \
		NETIF_MSG_TX_DONE | NETIF_MSG_TX_ERR | NETIF_MSG_RX_ERR)

#define IFC_CNT_HEAD_MOVE	100000

static int debug = 3;
module_param(debug, int, 0);
MODULE_PARM_DESC(debug, "Debug level (0=none,...,16=all)");

struct ifc_mcdma_loopback_config ifc_mcdma_lb_config;

#ifdef IFC_QDMA_INTF_ST
static int ifc_check_payload(struct ifc_mcdma_dev_ctx *dev_ctx, int payload)
{
	int new_payload = 0;

/*This refers to data width of AVST interface between HIP and QDMA IP.
 * For 1024 data width(PCIe5) required 128 bytes payload alignment.
 */
        int remainder = payload % dev_ctx->data_align_bytes;

	if (remainder == 0)
		return payload;
	/* Rounding up to the nearest multiple of data_align_bytes */
	new_payload = payload + dev_ctx->data_align_bytes - remainder;
	return new_payload;
}
#endif

#ifdef IFC_MCDMA_LB_CFG
static void ifc_mcdma_write64(void __iomem *addr, u64 value)
{
	u8 __iomem *base = addr;

	writel(lower_32_bits(value), base);
	writel(upper_32_bits(value), base + sizeof(u32));
}

void ifc_mcdma_update_lb_config(struct ifc_mcdma_loopback_config *lbconfig)
{
	/* set loopback config */
	struct ifc_mcdma_dev_ctx *mcdma_ctx = lbconfig->dev_ctx;
	u8 __iomem *base = (u8 __iomem *)mcdma_ctx->pctx.info[2].iaddr;

	ifc_mcdma_write64(base + 0x10000 + (lbconfig->src_chnl * 8),
			 lbconfig->dst_chnl);
}

#ifdef IFC_MCDMA_LB_DFLT_CFG
static void ifc_mcdma_set_lb_config(struct ifc_mcdma_dev_ctx *dev_ctx, int pf_num)
{
	uint32_t src, dst;
	struct ifc_mcdma_loopback_config *lbconfig = &ifc_mcdma_lb_config;
	struct ifc_mcdma_dev_ctx *mcdma_ctx = lbconfig->dev_ctx;
	u8 __iomem *base = (u8 __iomem *)mcdma_ctx->pctx.info[2].iaddr;
	int i;

	if (pf_num % 2 == 0)
		return;

	/* set loopback config */
	pr_debug("Setting default config");
	for (i = 0; i < dev_ctx->chnl_cnt; i++) {
		src = (pf_num * dev_ctx->chnl_cnt) + i;
		dst = src - dev_ctx->chnl_cnt;

		lbconfig->mapping[src].valid  = 1;
		lbconfig->mapping[src].chnl  = dst;
		ifc_mcdma_write64(base + 0x10000 + (src * 8), dst);

		lbconfig->mapping[dst].valid  = 1;
		lbconfig->mapping[dst].chnl  = src;
		ifc_mcdma_write64(base + 0x10000 + (dst * 8), src);
	}
}
#endif
#endif

#ifdef IFC_MCDMA_DEBUG
/**
 *  * ifc_mcdma_print_qstats - display queue statistics
 *   */
static void ifc_mcdma_print_qstats(struct ifc_mcdma_queue *q)
{
	struct pci_dev *pdev;

	if (unlikely(q == NULL)) {
		pr_err("Invalid channel context\n");
		return;
	}

	if (unlikely(q->chnl->channel_id >= q->chnl->dev_ctx->chnl_cnt)) {
		pr_err("Invalid channel context\n");
		return;
	}
	pdev = q->chnl->dev_ctx->pctx.pdev;

	dev_info(&pdev->dev, "SW Stats: chnl:%u dir:%s, ", q->chnl->channel_id,
		 q->dir == IFC_MCDMA_DIR_RX ? "Rx" : "Tx");
	dev_info(&pdev->dev, "processed head:%u, ", q->cur_con_head);
	dev_info(&pdev->dev, "WB head :%u\n", (volatile uint32_t)
		 q->consumed_head);
	dev_info(&pdev->dev, "SW head :%u, ", q->head);
	dev_info(&pdev->dev, "SW tail :%u, ", q->tail);
	dev_info(&pdev->dev, "DIDX:%u, ", q->didx);
	dev_info(&pdev->dev, "HW head:%u, ",
		 readl(q->qcsr + QDMA_REGS_2_Q_HEAD_POINTER));
	dev_info(&pdev->dev, "WB reg:%u\n",
		 readl(q->qcsr + QDMA_REGS_2_Q_COMPLETED_POINTER));
}
#endif

static void ifc_mcdma_set_avoid_hol(void *dev_qcsr)
{
	/* avoid hol */
#ifdef IFC_MCDMA_HOL
	writel(0xff, dev_qcsr + QDMA_REGS_2_RSVD_9);
#else
	writel(0x0, dev_qcsr + QDMA_REGS_2_RSVD_9);
#endif
}

/* RX 允许的最大帧长：MTU + 以太头 + 一层 VLAN + FCS（MAC 若透传 FCS 也不误丢）。
 * 单描述符能装下的帧（<= 4096）一律接收，与改多描述符之前的行为一致。 */
static inline unsigned int ifc_mcdma_rx_frame_max(struct ifc_mcdma_queue *q)
{
	unsigned int max = READ_ONCE(q->chnl->dev_ctx->netdev->mtu) +
			   ETH_HLEN + VLAN_HLEN + ETH_FCS_LEN;

	return max_t(unsigned int, max, IFC_MCDMA_BUF_SIZE);
}

/* 释放队列每个槽的 DMA 缓冲。调用前硬件必须已停（队列已 reset/disable）。 */
static void ifc_mcdma_bufs_free(struct ifc_mcdma_queue *q)
{
	struct device *dev = &q->chnl->dev_ctx->pctx.pdev->dev;
	int i;

	if (q->ctx == NULL)
		return;
	for (i = 0; i < q->qlen; i++) {
		if (q->ctx[i].buf == NULL)
			continue;
		dma_free_coherent(dev, IFC_MCDMA_BUF_SIZE, q->ctx[i].buf,
				  q->ctx[i].buf_dma);
		q->ctx[i].buf = NULL;
	}
}

/* 给环上每个数据描述符槽（跳过 link）分配一块 4 KB 的 DMA 缓冲。
 *
 * dma_alloc_coherent() 按页分配，返回的 DMA 地址至少按 PAGE_SIZE（>= 4 KB）对齐，
 * 缓冲长度又正好 4096，所以硬件对这块缓冲的任何读写都不会跨 4 KB 页。
 * 这里仍逐块检查低 12 位，万一 DMA 后端（swiotlb 等）给出未对齐地址就拒绝起队列，
 * 宁可 ifup 失败也不让硬件发跨页 TLP。 */
static int ifc_mcdma_bufs_alloc(struct ifc_mcdma_queue *q)
{
	struct device *dev = &q->chnl->dev_ctx->pctx.pdev->dev;
	struct ifc_mcdma_desc *ring = q->ring_virt_addr;
	int i;

	for (i = 0; i < q->qlen; i++) {
		if (ring[i].link)
			continue;
		q->ctx[i].buf = dma_alloc_coherent(dev, IFC_MCDMA_BUF_SIZE,
						   &q->ctx[i].buf_dma,
						   GFP_KERNEL);
		if (q->ctx[i].buf == NULL)
			goto fail;
		if (q->ctx[i].buf_dma & (IFC_MCDMA_BUF_SIZE - 1)) {
			dev_err(dev, "chnl %u %s slot %d: DMA addr %pad not 4KB aligned\n",
				q->chnl->channel_id,
				q->dir == IFC_MCDMA_DIR_RX ? "rx" : "tx", i,
				&q->ctx[i].buf_dma);
			goto fail;
		}
	}
	return 0;
fail:
	ifc_mcdma_bufs_free(q);
	return -ENOMEM;
}

/* Return the RSS register base for this function (BAR2 per-function area). */
static void __iomem *ifc_mcdma_rss_base(struct ifc_mcdma_dev_ctx *dev_ctx)
{
	int func_id = PCI_FUNC(dev_ctx->pctx.pdev->devfn);

	return (char *)dev_ctx->pctx.info[2].iaddr
		+ IFC_MCDMA_RSS_SUBSYS_OFFSET
		+ IFC_MCDMA_RSS_FUNC_STRIDE * func_id;
}

/* Write the RSS RETA (indirection) table to hardware.
 * Each 32-bit register: bits[15:0] = queue_id, bits[31:16] reserved (RMW).
 * Matches DPDK mcdma_dev_rss_reta_update().
 */
void ifc_mcdma_hw_write_reta(struct ifc_mcdma_dev_ctx *dev_ctx)
{
	void __iomem *base = ifc_mcdma_rss_base(dev_ctx);
	u32 i, val;

	for (i = 0; i < IFC_MCDMA_RSS_INDIR_SIZE; i++) {
		val = readl(base + IFC_MCDMA_RSS_RETA_OFFSET + i * 4);
		val &= 0xFFFF0000;
		val |= dev_ctx->rss_indir_table[i] & 0xFFFF;
		writel(val, base + IFC_MCDMA_RSS_RETA_OFFSET + i * 4);
	}
}

/* Write the RSS Toeplitz hash key to hardware.
 * Little-endian packing: key[i*4+0] -> bits[7:0], key[i*4+3] -> bits[31:24].
 * Matches DPDK mcdma_dev_rss_hash_update().
 */
void ifc_mcdma_hw_write_rss_key(struct ifc_mcdma_dev_ctx *dev_ctx)
{
	void __iomem *base = ifc_mcdma_rss_base(dev_ctx);
	u32 i, val;

	for (i = 0; i < IFC_MCDMA_RSS_KEY_SIZE; i += 4) {
		val = (u32)dev_ctx->rss_key[i]
		    | ((u32)dev_ctx->rss_key[i + 1] << 8)
		    | ((u32)dev_ctx->rss_key[i + 2] << 16)
		    | ((u32)dev_ctx->rss_key[i + 3] << 24);
		writel(val, base + IFC_MCDMA_RSS_KEY_OFFSET + i);
	}
}

int ifc_mcdma_ip_reset(void *dev_qcsr)
{
	void *base;

	if (unlikely(dev_qcsr == NULL))
		return -EFAULT;

	base = dev_qcsr;
	mdelay(500UL);

	/* IP reset */
	writel(0x01, base + QDMA_REGS_2_SOFT_RESET);

	/* giving time for the FPGA reset to complete */
	mdelay(500UL);

	pr_debug("Successfully reset IP\n");
	return 0;
}

static int ifc_descq_empty_slots(struct ifc_mcdma_queue *q)
{
	int head = q->head; //software consumer
	int tail = q->tail;
	int desc_per_page;
	int free_slots;
	int links;

	if (unlikely(q == NULL)) {
		pr_err("Chnl:%d:%d: Invalid Queue Context",
			q->chnl->channel_id, q->dir);
		return -EFAULT;
	}
	/* Completely empty? */
	if (q->head_didx == q->tail_didx) //head_didx(hw consumer)
		return q->num_desc_pages * 127;

	/* Full? */
	if ((q->head_didx != q->tail_didx) && (q->head == q->tail))
		return 0;

	desc_per_page = PAGE_SIZE / sizeof(struct ifc_mcdma_desc);

	/* #empty slots */
	if (head <= tail)
		free_slots = q->qlen - tail + head;
	else
		free_slots = head - tail;

	/* Remove links */
	links = (tail / desc_per_page - head / desc_per_page);

	if (head >= tail)
		free_slots += links;
	else
		free_slots = free_slots - (q->num_desc_pages - links);

	return free_slots;
}

/* 取 tail 处的下一个数据描述符槽（遇到 link 描述符就跳过），清零后返回，
 * *slot 为它在环里的下标。调用方填 src/dest/len/sof/eof 后必须调 ifc_mcdma_desc_put()。
 * 调用前要确认 ifc_descq_empty_slots() 有空位。 */
static struct ifc_mcdma_desc *
ifc_mcdma_desc_get(struct ifc_mcdma_queue *q, uint32_t *slot)
{
	struct ifc_mcdma_desc *d;
	uint32_t tail = q->tail;

	d = (struct ifc_mcdma_desc *)q->ring_virt_addr + tail;
	if (d->link) {	/* skip the link */
		tail = (tail + 1) % q->qlen;
		q->didx = ((q->didx + 1) % IFC_NUM_DESC_INDEXES);
		d = (struct ifc_mcdma_desc *)q->ring_virt_addr + tail;
	}
	memset(d, 0, sizeof(struct ifc_mcdma_desc));
	*slot = tail;
	return d;
}

/* 描述符填好之后推进 tail/didx（软件 desc index 赋给硬件），打开写回与中断。
 * 与原 ifc_mcdma_desc_prep() 的收尾逻辑相同；tail 指针由 ifc_mcdma_desc_submit() 写给硬件。 */
static void ifc_mcdma_desc_put(struct ifc_mcdma_queue *q,
			       struct ifc_mcdma_desc *d, uint32_t slot)
{
	q->tail = (slot + 1) % q->qlen;
	q->didx = ((q->didx + 1) % IFC_NUM_DESC_INDEXES);
	d->didx = q->didx;
	d->pad_len = 0;
	q->tail_didx = q->didx;

	/* Setting to address small packets
	 *  for batch size transfer, need to disable
	 */
	d->wb_en = 1;
	d->msix_en = 1;
}

/* RX：把槽内固定的 4 KB 缓冲挂回环上。
 * sof/eof 仍按原驱动预置为 1、rx_pyld_cnt 由 memset 清 0：硬件对它写回的描述符会覆盖
 * 这三个字段；没被写回的（多描述符帧的中间段）保持 rx_pyld_cnt == 0，
 * ifc_mcdma_rx_desc_done() 据此识别为「写满的非末段」。单描述符帧的写回结果与改动前完全一样。 */
static void ifc_mcdma_rx_desc_prep(struct ifc_mcdma_queue *q)
{
	struct ifc_mcdma_desc *d;
	uint32_t slot;

	d = ifc_mcdma_desc_get(q, &slot);
	d->src = 0ULL;
	d->dest = q->ctx[slot].buf_dma;
	d->len = IFC_MCDMA_BUF_SIZE;
	d->sof = 1;
	d->eof = 1;
	ifc_mcdma_desc_put(q, d, slot);
}

static int ifc_mcdma_desc_submit(struct ifc_mcdma_queue *q)
{
	struct ifc_mcdma_desc *d;
	int index;
	int count = 0;
	uint32_t qhead;
#ifdef ENABLE_DEBUGFS
#ifdef IFC_MCDMA_DEBUG
	uint32_t cnt;
#endif
#endif

	if (unlikely(q == NULL)) {
		pr_err("Chnl:%d:Invalid Queue Context\n", q->chnl->channel_id);
		return -EFAULT;
	}

	index = q->tail - 1;                    //todo:只处理队列的最后一个
	d = (struct ifc_mcdma_desc *)
	    ((uint64_t)q->ring_virt_addr + sizeof(*d) * index);

	/* update completion mechanism */
	d->msix_en = q->ire;
	if (q->wbe || q->ire)
		d->wb_en = 1;

	/* this code handles the scenario,when same tid update may happen
         due to the device taking more time to process data with higher payloads */
	if (q->tail == q->processed_tail) {
		writel(q->qlen, q->qcsr + QDMA_REGS_2_Q_TAIL_POINTER);
		while (count < IFC_CNT_HEAD_MOVE) {
			qhead = readl(q->qcsr + QDMA_REGS_2_Q_HEAD_POINTER);
			if ((qhead % 128) == 0)
				break;
			count++;
		}
	}

#ifdef ENABLE_DEBUGFS
#ifdef IFC_MCDMA_DEBUG
	cnt = (q->tail <= q->processed_tail) ?
		(q->qlen - 1 - q->processed_tail + q->tail) :
		(q->tail - q->processed_tail);
	q->stats.tid_update += cnt;
	q->stats.submitted_didx = q->didx;
#endif
#endif

	/* update tail pointer */
	writel(q->tail, q->qcsr + QDMA_REGS_2_Q_TAIL_POINTER);

	/* update last update tail */
	q->processed_tail = q->tail;

	return 0;
}

//获取从上次调用到当前调用期间，DMA队列中新处理完成的描述符数量。
static int ifc_descq_processed_count(struct ifc_mcdma_queue *q)
{
	int head;
	int prev_head;

	if (q->wbe || q->ire)
		head = q->consumed_head;
	else
		head = readl(q->qcsr + QDMA_REGS_2_Q_COMPLETED_POINTER);

	prev_head = q->cur_con_head;

	return (head >= prev_head) ?
		(head - prev_head) : (IFC_NUM_DESC_INDEXES - prev_head + head);
}

static int ifc_mcdma_queue_poll(struct ifc_mcdma_queue *q, int budget)
{
	int nr;
	int pending;

	if (unlikely(q == NULL)) {
		pr_err("Chnl:%d:%d: Invalid Queue Context",
			q->chnl->channel_id, q->dir);
		return -EFAULT;
	}

	pending = ifc_descq_processed_count(q);
	nr = min(pending, budget);
	q->cur_con_head = (q->cur_con_head + nr) % IFC_NUM_DESC_INDEXES;
	q->head_didx = q->cur_con_head;

	return nr;
}

/*
 * 接收使用：把所有空槽的 4 KB 缓冲重新挂回 RX 环。
 * 缓冲在队列初始化时就分配好了，这里不会因分配失败而少挂。
 * return : 挂上的描述符个数；没有空槽返回 -ENOMEM
 */
static int ifc_mcdma_queue_ring_fill(struct ifc_mcdma_queue *q)
{
	int nr_segs;
	int i;

	if (unlikely(q == NULL)) {
		pr_err("Invalid Queue Context\n");
		return -EINVAL;
	}

	/* check if descq have enough empty slots */
	nr_segs = ifc_descq_empty_slots(q);
	if (nr_segs <= 0) {
		pr_debug("cid:%u dir:%u No empty slots for submission\n"
			 , q->chnl->channel_id, q->dir);
		return -ENOMEM;
	}

	for (i = 0; i < nr_segs; i++)
		ifc_mcdma_rx_desc_prep(q);

	/* Submit the newly created descriptors */
	ifc_mcdma_desc_submit(q);

	return nr_segs;
}

/* 丢掉正在拼的帧；last == false 时继续丢弃本帧后续段，直到 EOF。 */
static void ifc_mcdma_rx_abort(struct ifc_mcdma_queue *q, bool last)
{
	if (q->rx_skb != NULL) {
		dev_kfree_skb_any(q->rx_skb);
		q->rx_skb = NULL;
	}
	q->rx_discard = !last;
}

/* 处理一个已完成的 RX 数据描述符，按 SOF/EOF 拼帧，拼完交给协议栈。
 *
 * 判段规则（参见 struct ifc_mcdma_desc 的 word 7 注释）：
 *   rx_pyld_cnt == 0：硬件没写回长度 —— 多描述符帧中写满的非末段，长度按 4096；
 *                     当前没有在拼的帧时视为一帧的开头。
 *                     （本驱动缓冲只有 4 KB，"0 表示 1 MB" 的编码不会出现在末段。）
 *   rx_pyld_cnt != 0：按写回的 sof/eof：eof 段长度 = rx_pyld_cnt；非 eof 段必须正好 4096。
 *                     末段 rx_pyld_cnt > 4096 且能与已收长度对上时，按「整帧长度」解释（兜底）。
 * 不符合以上约定的描述符整帧丢弃并打 ratelimited 告警（"bad rx desc"），计入 rx_errors。
 * 段数据从槽缓冲拷进 skb，槽缓冲随后原地挂回环上（ifc_mcdma_queue_ring_fill）。 */
static void ifc_mcdma_rx_desc_done(struct ifc_mcdma_queue *q,
				   const struct ifc_mcdma_desc *desc,
				   const struct ifc_mcdma_desc_sw *sw,
				   struct net_device *netdev)
{
	uint32_t cnt = desc->rx_pyld_cnt;
	struct sk_buff *skb;
	unsigned int alloc;
	uint32_t len;
	bool first;
	bool last;

	if (cnt == 0) {
		first = (q->rx_skb == NULL && !q->rx_discard);
		last = false;
		len = IFC_MCDMA_BUF_SIZE;
	} else {
		first = desc->sof;
		last = desc->eof;
		len = last ? cnt : IFC_MCDMA_BUF_SIZE;
		if (last && !first && cnt > IFC_MCDMA_BUF_SIZE &&
		    q->rx_skb != NULL && cnt > q->rx_skb->len &&
		    cnt - q->rx_skb->len <= IFC_MCDMA_BUF_SIZE) {
			/* 兜底：若硬件在末段写回的是整帧长度而不是本段长度
			 * （UG/libmqdma 是本段长度，这里不依赖它）。多段帧总长必 > 4096，
			 * 与「本段长度 <= 4096」不会混淆。 */
			pr_info_once("%s: MCDMA D2H EOF rx_pyld_cnt carries total frame length\n",
				     netdev->name);
			len = cnt - q->rx_skb->len;
		} else if (cnt > IFC_MCDMA_BUF_SIZE ||
			   (!last && cnt != IFC_MCDMA_BUF_SIZE)) {
			/* 与「非末段写满、末段报本段字节数」的约定不符，整帧丢弃 */
			net_warn_ratelimited("%s: chnl %u bad rx desc: sof %u eof %u cnt %u len %u\n",
					     netdev->name, q->chnl->channel_id,
					     desc->sof, desc->eof, cnt, desc->len);
			netdev->stats.rx_errors++;
			ifc_mcdma_rx_abort(q, last);
			return;
		}
	}

	if (first) {
		if (q->rx_skb != NULL || q->rx_discard) {
			/* 上一帧没等到 EOF 就来了新的 SOF */
			netdev->stats.rx_errors++;
			netdev->stats.rx_length_errors++;
			ifc_mcdma_rx_abort(q, true);
		}
		/* 单段帧按实际长度分配；多段帧一次分到本 MTU 下的最大帧长，后续段直接追加 */
		alloc = last ? len : ifc_mcdma_rx_frame_max(q);
		skb = napi_alloc_skb(&q->napi, alloc);
		if (skb == NULL) {
			netdev->stats.rx_dropped++;
			ifc_mcdma_rx_abort(q, last);
			return;
		}
		q->rx_skb = skb;
		q->rx_limit = alloc;
	} else if (q->rx_skb == NULL) {
		/* 没有 SOF 的段：正在丢弃的帧的后续段，或孤立段 */
		if (!q->rx_discard) {
			netdev->stats.rx_errors++;
			net_dbg_ratelimited("%s: chnl %u rx segment without SOF: eof %u cnt %u\n",
					    netdev->name, q->chnl->channel_id,
					    desc->eof, cnt);
		}
		ifc_mcdma_rx_abort(q, last);
		return;
	}

	skb = q->rx_skb;
	if (skb->len + len > q->rx_limit) {
		/* 比 MTU 允许的最大帧还长 */
		netdev->stats.rx_errors++;
		netdev->stats.rx_length_errors++;
		ifc_mcdma_rx_abort(q, last);
		return;
	}
	skb_put_data(skb, sw->buf, len);
	if (!last)
		return;

	/* EOF：整帧交给协议栈 */
	q->rx_skb = NULL;
	q->rx_discard = false;
	if (unlikely(skb->len < ETH_HLEN)) {
		netdev->stats.rx_errors++;
		netdev->stats.rx_length_errors++;
		dev_kfree_skb_any(skb);
		return;
	}
#ifdef SKB_HEX_DUMP
	print_hex_dump(KERN_DEBUG, "rx ", DUMP_PREFIX_OFFSET, 16, 1,
		       skb->data, skb->len, true);
#endif
	len = skb->len;
	skb_record_rx_queue(skb, q->chnl->channel_id);
	skb->protocol = eth_type_trans(skb, netdev);
	if (netif_receive_skb(skb) != NET_RX_SUCCESS) {
		netdev->stats.rx_dropped++;
	} else {
		netdev->stats.rx_packets++;
		netdev->stats.rx_bytes += len;
	}
}

/* TX 描述符完成：bounce 缓冲可复用；EOF 槽记一帧统计。skb 在 xmit 拷完就已释放。 */
static void ifc_mcdma_tx_desc_done(struct ifc_mcdma_desc_sw *sw,
				   struct net_device *netdev)
{
	if (sw->tx_len == 0)
		return;
	netdev->stats.tx_packets++;
	netdev->stats.tx_bytes += sw->tx_len;
	sw->tx_len = 0;
}

//DMA完成处理函数,用于在中断或轮询上下文中处理已完成的描述符.
//nr 是硬件写回 head 推进的描述符个数，包含 link 描述符。
static int ifc_mcdma_process_comp_pckts(struct ifc_mcdma_queue *q, int nr)
{
	struct ifc_mcdma_desc *desc;
	struct net_device *netdev;
	int t;

	if (unlikely(q == NULL)) {
		pr_err("Invalid Queue Context\n");
		return -EFAULT;
	}

	netdev = q->chnl->dev_ctx->netdev;
	if (unlikely(netdev == NULL)) {
		pr_err("Invalid netdev context\n");
		return -EFAULT;
	}

	if (q->dir != IFC_MCDMA_DIR_TX && q->dir != IFC_MCDMA_DIR_RX) {
		pr_err("Invalid queue direction.");
		return -EFAULT;
	}

	/* 先看到硬件写回的 consumed_head，再读描述符写回字段和数据缓冲 */
	dma_rmb();

	for (t = q->head; nr > 0; t = (t + 1) % q->qlen, nr--) {
		desc = (struct ifc_mcdma_desc *)q->ring_virt_addr + t;
		if (desc->link) //link描述符，不对应数据
			continue;
		if (q->dir == IFC_MCDMA_DIR_RX)
			ifc_mcdma_rx_desc_done(q, desc, &q->ctx[t], netdev);
		else
			ifc_mcdma_tx_desc_done(&q->ctx[t], netdev);
	}
	/* Update queue head to descriptor which is processed by SW */
	q->head = t;

	if (q->dir == IFC_MCDMA_DIR_TX &&
	    ifc_descq_empty_slots(q) >= IFC_MCDMA_TX_MAX_SEGS)
		netif_wake_subqueue(netdev, q->chnl->channel_id);

	return 0;
}

static irqreturn_t ifc_irq_handler(int irq, void *arg)
{
	struct ifc_mcdma_queue *q;

	if (unlikely(arg == NULL)) {
		pr_err("Invalid Interrupt context\n");
		return IRQ_NONE;
	}
	q = (struct ifc_mcdma_queue *)arg;

	napi_schedule_irqoff(&q->napi);

	return IRQ_HANDLED;
}

static int ifc_mcdma_process_completions(struct ifc_mcdma_queue *q, int budget)
{
	int ret;
	int nr = 0;

	if (unlikely(q == NULL)) {
		pr_err("Chnl:%d:%d: Invalid Queue Context",
			q->chnl->channel_id, q->dir);
		return -EFAULT;
	}

	nr = ifc_mcdma_queue_poll(q, budget);
	ifc_mcdma_process_comp_pckts(q, nr);

	if (q->dir == IFC_MCDMA_DIR_RX) {
		ret = ifc_mcdma_queue_ring_fill(q);
		if (ret < 0)
			return 0;
	}

	return nr;
}

static int ifc_irq_handler_alloc(struct ifc_msix_info *msix_info,
				 struct ifc_mcdma_queue *q)
{
	unsigned long irq_flags = (IRQF_NO_THREAD | IRQF_NOBALANCING |
				   IRQF_ONESHOT | IRQF_IRQPOLL);
	int irq_index;
	int ret;

	if (unlikely(q == NULL || msix_info == NULL)) {
		pr_err("Invalid Queue Context or msix info\n");
		return -EFAULT;
	}

	irq_index = (q->chnl->channel_id * 4) + ((1 - q->dir) * 2);

	/* Register irq handler */
	ret = request_irq(msix_info->table[irq_index].vector, ifc_irq_handler,
			  irq_flags, IFC_MCDMA_DRIVER_NAME, q);
	if (ret < 0) {
		pr_err("Failed to register irq handler: %d\n", ret);
		return -1;
	}

	q->irq_index = irq_index;
	pr_debug("Registered IRQ handler: nvectors: %d, irq_index: %d\n",
		 msix_info->nvectors, irq_index);
	return 0;
}

static void ifc_irq_handler_free(struct ifc_msix_info *msix_info,
				 struct ifc_mcdma_queue *q)
{
	int irq_index;

	if (unlikely(q == NULL || msix_info == NULL)) {
		pr_err("Invalid Queue Context or msix info\n");
		return;
	}

	irq_index = q->irq_index;
	free_irq(msix_info->table[irq_index].vector, q);
	pr_debug("Unregistered IRQ handler: nvectors: %d, irq_index: %d\n",
		 msix_info->nvectors, q->irq_index);
}

/*
 * 计算一个32位无符号整数最高有效位（MSB）的位置，
 * 其核心功能是将一个2的幂次方数值转换为对应的幂指数。
 */
static int q_size_bits(uint32_t val)
{
	int i;

	for (i = 8 * sizeof(uint32_t) - 1; i >= 0; i--) {
		if (val >> i)
			return i;
	}
	return -1;
}

static int ifc_mcdma_napi_poll(struct napi_struct *napi, int budget)
{
	struct ifc_mcdma_queue *que;
	int nr;

	que = container_of(napi, struct ifc_mcdma_queue, napi);
	if (que == NULL) {
		pr_err("Invalid Queue Context \n");
		return 0;
	}

	nr = ifc_mcdma_process_completions(que, budget);
	if (nr < budget)
		napi_complete_done(napi, nr);

	return nr;
}

static int ifc_descq_init(struct ifc_mcdma_queue *q)
{
	QDMA_REGS_2_Q_CTRL_t q_ctrl = { { 0 } };
	struct ifc_pci_dev *pci_ctx;
	struct ifc_mcdma_desc *desc;
	struct ifc_mcdma_desc *temp_desc;
	struct ifc_mcdma_desc_sw *sw;
	int desc_per_page;
	uint64_t cons_head;
	uint32_t log_len;
	int ret;
	int i;
#ifdef IFC_QDMA_INTF_ST
	int payload;
#endif

	if (unlikely(q == NULL)) {
		pr_err("Chnl:%d:%d: Invalid Queue Context",
			q->chnl->channel_id, q->dir);
		return -EFAULT;
	}

	desc_per_page = PAGE_SIZE / sizeof(struct ifc_mcdma_desc); //PAGE_SIZE=4k/32=128
	q->qlen = q->num_desc_pages * desc_per_page; //128 = 1*128;

	/* Allocate the ring buffer */
	pci_ctx = &q->chnl->dev_ctx->pctx;
	q->ring_virt_addr = dma_alloc_coherent(&pci_ctx->pdev->dev,
			q->num_desc_pages * PAGE_SIZE,
			&q->ring_dma_addr, GFP_KERNEL);
	if (q->ring_virt_addr == NULL)
		return -ENOMEM;

	log_len = q_size_bits(q->qlen);
	q->num_desc_bits = log_len;
#ifdef IFC_MCDMA_IOMMU_SUPPORT
	q->ring_hw_addr = (uint64_t)q->ring_dma_addr;
#else
	q->ring_hw_addr = virt_to_phys(q->ring_virt_addr);
#endif
	temp_desc = (struct ifc_mcdma_desc*)q->ring_hw_addr;

	pr_debug("Chnl:%d:%d:Desc per page:%d, Qlen:%d, Log len:%d\n",
		 q->chnl->channel_id, q->dir, desc_per_page, q->qlen, log_len);

	/* Allocate memory to hold onto the
	 * requests passed from the application
	 */
	q->ctx = (struct ifc_mcdma_desc_sw *)
		kcalloc(q->qlen, sizeof(*sw), GFP_KERNEL);
	if (q->ctx == NULL)
		goto fail_free_ring;
	q->rx_skb = NULL;
	q->rx_discard = false;

	/* Link the descriptor pages */
	desc = (struct ifc_mcdma_desc *)q->ring_virt_addr;
	for (i = 0; i < q->qlen; i++)
		desc[i].link = 0;

	desc[i - 1].src = q->ring_hw_addr; //最后一个desc设置为dma起始地址,即队列开头形成环形结构
	desc[i - 1].link = 1;

	for (i = desc_per_page; i < q->qlen; i += desc_per_page) {
		desc[i - 1].link = 1;  //每一页的最后一个为link连接符
		desc[i - 1].src = (uint64_t)&temp_desc[i]; //每一页最后一个指下一页第一个，最后一页除外
	}

	/* 每个数据描述符槽一块 4 KB 对齐的 DMA 缓冲（RX 收包 / TX bounce），见 IFC_MCDMA_BUF_SIZE */
	if (ifc_mcdma_bufs_alloc(q) < 0) {
		pr_err("Chnl:%d:%d: DMA buffer allocation failed\n",
		       q->chnl->channel_id, q->dir);
		goto fail_free_ctx;
	}

	/* Program regs */
	writel((uint32_t)q->ring_hw_addr,
	       q->qcsr + QDMA_REGS_2_Q_START_ADDR_L);
	writel(q->ring_hw_addr >> 32, q->qcsr + QDMA_REGS_2_Q_START_ADDR_H);
	writel(log_len, q->qcsr + QDMA_REGS_2_Q_SIZE);
	writel(0U, q->qcsr + QDMA_REGS_2_Q_TAIL_POINTER); //todo:???写入0不合法

	/* Configure address for write backs from HW */
	cons_head = (uint64_t)dma_map_single(&(pci_ctx->pdev->dev),
				&q->consumed_head, sizeof(int),
				DMA_FROM_DEVICE); // 映射写回地址到DMA空间,硬件完成描述符处理后通过此地址通知软件
        if (dma_mapping_error(&(pci_ctx->pdev->dev), cons_head)) {
		pr_err("IOMMU mapping failed\n");
		goto fail_free_ctx;
	}

	writel((uint32_t)cons_head,
	       q->qcsr + QDMA_REGS_2_Q_CONSUMED_HEAD_ADDR_L); //消耗指针，硬件回写通知软件
	writel(cons_head >> 32, q->qcsr + QDMA_REGS_2_Q_CONSUMED_HEAD_ADDR_H);

	/* Configure batch delay */
	writel(IFC_MCDMA_Q_BATCH_DELAY, q->qcsr + QDMA_REGS_2_Q_BATCH_DELAY);

#ifdef IFC_QDMA_INTF_ST
	/* Configure paylaod：与每个描述符的 len 一致，固定 4096（不再随 MTU 变） */
	payload = ifc_check_payload(q->chnl->dev_ctx, IFC_MCDMA_BUF_SIZE);
	writel(payload, q->qcsr + QDMA_REGS_2_Q_DEBUG_STATUS_4);
#endif
	/* Configure the control register */
	q_ctrl.field.q_en = 1;
	q_ctrl.field.q_intr_en = 1;
	q_ctrl.field.q_wb_en = 1;
	q->ire = 1;
	q->wbe = 0;

	/* Initialize NAPI before registering the IRQ handler to prevent a race
	 * condition: if a hardware interrupt fires after request_irq() but before
	 * netif_napi_add() sets napi->poll, ifc_irq_handler() would call
	 * napi_schedule() on an uninitialized napi_struct (poll == NULL), causing
	 * __napi_poll() to dereference NULL and trigger a kernel panic.
	 */
#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 1, 0)
	netif_napi_add(q->chnl->dev_ctx->netdev, &q->napi, ifc_mcdma_napi_poll);
#else
	netif_napi_add(q->chnl->dev_ctx->netdev, &q->napi, ifc_mcdma_napi_poll,
		       NAPI_POLL_WEIGHT);
#endif
	napi_enable(&q->napi);

	/* Register irq handler */
	ret = ifc_irq_handler_alloc(&q->chnl->dev_ctx->msix_info, q);
	if (ret < 0)
		goto fail_cleanup;

	/* Write in QCSR register */
	writel(q_ctrl.val, q->qcsr + QDMA_REGS_2_Q_CTRL);
	return 0;
fail_cleanup:
	napi_disable(&q->napi);
	netif_napi_del(&q->napi);
fail_free_ctx:
	/* 走到这里时 Q_CTRL 还没使能，硬件不会访问这些缓冲 */
	ifc_mcdma_bufs_free(q);
	kfree(q->ctx);
	q->ctx = NULL;
fail_free_ring:
	dma_free_coherent(&pci_ctx->pdev->dev, q->num_desc_pages * PAGE_SIZE,
			  q->ring_virt_addr, q->ring_dma_addr);
	return -1;
}

static int ifc_queue_reset(struct ifc_mcdma_queue *q)
{
	ktime_t start, now;
	int val;

	if (unlikely(q == NULL)) {
		pr_err("Chnl:%d:%d: Invalid Queue Context",
			q->chnl->channel_id, q->dir);
		return -EFAULT;
	}

	/* Assert reset */
	writel(1, q->qcsr + QDMA_REGS_2_Q_RESET);
	start = ktime_get();

	/* Wait for reset to deassert */
	while (1) {
		val = readl(q->qcsr + QDMA_REGS_2_Q_RESET);
		if (!val)
			return 0;
		now = ktime_get();
		if (ktime_to_ms(ktime_sub(now, start)) > 5)
			break;
	}
	return -1;
}

static int
ifc_queue_init(struct ifc_mcdma_queue *q, int dir, void *qcsr)
{
	int ret;

	if (unlikely(q == NULL)) {
		pr_err("Chnl:%d:%d: Invalid Queue Context",
			q->chnl->channel_id, q->dir);
		return -EFAULT;
	}

	q->qcsr = qcsr;
	q->num_desc_pages = q->chnl->dev_ctx->num_of_pages; //ring描述符大小设置
	q->dir = dir;

	/* Reset the queue */
	ret = ifc_queue_reset(q);
	if (ret < 0) {
		pr_err("cid:%u dir:%u Queue Reset failed\n",
		       q->chnl->channel_id, q->dir);
		return ret;
	}

	/* Init descriptor ring buffer */
	ret = ifc_descq_init(q);
	if (ret < 0) {
		pr_err("cid:%u dir:%u Descriptor init failed\n",
		       q->chnl->channel_id, q->dir);
		return ret;
	}

	/* Prepare Descriptors to receive data on Rx*/
	if (q->dir == IFC_MCDMA_DIR_RX) {
		ret = ifc_mcdma_queue_ring_fill(q);
		if (ret < 0) {
			pr_err("cid:%u dir:%u Ring prefilling failed\n",
			       q->chnl->channel_id, q->dir);
			return ret;
		}
	}
	return 0;
}

static void ifc_queue_free(struct ifc_mcdma_queue *q)
{
	struct ifc_pci_dev *pci_ctx;
        int ret = 0;

	if (unlikely(q == NULL)) {
		pr_err("Chnl:%d:%d: Invalid Queue Context",
			q->chnl->channel_id, q->dir);
		return;
	}

        /* Reset the queue */
        ret = ifc_queue_reset(q);
        if (ret < 0) {
              pr_err("%s cid:%u dir:%u Queue Reset failed\n",
              q->chnl->dev_ctx->netdev->name,q->chnl->channel_id, q->dir);
      }

	/* Disable descriptor fetching */
	writel(0U, q->qcsr + QDMA_REGS_2_Q_CTRL);

	/* Disable and remove NAPI before freeing the IRQ to ensure no in-flight
	 * NAPI poll is running and no new napi_schedule() calls can be processed
	 * after free_irq() returns.
	 */
	napi_disable(&q->napi);
	netif_napi_del(&q->napi);

	/* Free IRQ handler */
	if (q->ire)
		ifc_irq_handler_free(&q->chnl->dev_ctx->msix_info, q);

	/* Deallocate the ring buffer */
	pci_ctx = &q->chnl->dev_ctx->pctx;
	dma_free_coherent(&pci_ctx->pdev->dev, q->num_desc_pages * PAGE_SIZE,
			  q->ring_virt_addr, q->ring_dma_addr);

	/* 队列已 reset + disable，NAPI 已停：释放槽缓冲和拼了一半的 RX 帧 */
	ifc_mcdma_bufs_free(q);
	kfree(q->ctx);
	q->ctx = NULL;
	if (q->rx_skb != NULL) {
		dev_kfree_skb_any(q->rx_skb);
		q->rx_skb = NULL;
	}
	q->rx_discard = false;

	pr_debug("Chnl%d: %s Queue successfully freed\n", q->chnl->channel_id,
		 q->dir == IFC_MCDMA_DIR_TX ? "Tx" : "Rx");
}

/* TODO: Remove channel_bitmap */
static void ifc_mcdma_chnl_put(struct ifc_mcdma_dev_ctx *dctx, int chnl_id)
{
	dctx->channel_bitmap[chnl_id] = false;
	dctx->channel_context[chnl_id] = NULL;
}

static int ifc_chnl_init(struct ifc_mcdma_channel *chnl_ctx, void *dev_qcsr)
{
	int ret;

	if (unlikely(chnl_ctx == NULL || dev_qcsr == NULL)) {
		pr_err("Invalid Channel Context\n");
		return -EFAULT;
	}

    //一个通道(队列)包含一个发送一个队列
	chnl_ctx->tx.chnl = chnl_ctx;
	chnl_ctx->rx.chnl = chnl_ctx;

	/* Init the queue contexts */
    // 硬件支持2048个H2D队列和2048个D2H队列
	ret = ifc_queue_init(&chnl_ctx->rx, IFC_MCDMA_DIR_RX,
				   dev_qcsr + chnl_ctx->channel_id * 256); //todo: bar0 addr+ offset(每个队列分配256空间)
	if (ret < 0) {
		pr_err("Chnl%d: Failed to initialize Rx context\n",
		       chnl_ctx->channel_id);
		return ret;
	}
	ret = ifc_queue_init(&chnl_ctx->tx, IFC_MCDMA_DIR_TX,
			     dev_qcsr + (1UL << 19) +
			     chnl_ctx->channel_id * 256);
	if (ret < 0) {
		pr_err("Chnl%d: Failed to initialize Tx context\n",
		       chnl_ctx->channel_id);
		return ret;
	}
	/* Setting HOL for test purpose*/
	ifc_mcdma_set_avoid_hol(dev_qcsr);

	pr_debug("Chnl%d: Queue Initialization successful\n",
		chnl_ctx->channel_id);

	return 0;
}

static void ifc_chnl_free(struct ifc_mcdma_channel *chnl_ctx)
{
	struct ifc_pci_dev *pci_ctx;

	pci_ctx = &chnl_ctx->dev_ctx->pctx;
	if (unlikely(pci_ctx == NULL)) {
		pr_err("Invalid PCI Context\n");
		return;
	}

#ifdef IFC_MCDMA_DEBUG
	/* print qstats */
	ifc_mcdma_print_qstats(&chnl_ctx->rx);
	ifc_mcdma_print_qstats(&chnl_ctx->tx);
#endif

	/* Free the queue contexts */
	ifc_queue_free(&chnl_ctx->rx);
	ifc_queue_free(&chnl_ctx->tx);

	ifc_mcdma_chnl_put(chnl_ctx->dev_ctx, chnl_ctx->channel_id);
	kfree(chnl_ctx);
}

int ifc_mcdma_chnl_init_all(struct ifc_mcdma_dev_ctx *dev_ctx)
{
	struct ifc_mcdma_channel **chnl_ctx_list;
	struct ifc_mcdma_channel *chnl_ctx;
	int chnl_id;
	int ret;
	int i;

	if (unlikely(dev_ctx == NULL)) {
		pr_err("Invalid Dev Context\n");
		return -1;
	}

	chnl_ctx_list = dev_ctx->channel_context;
	mutex_init(&dev_ctx->chnl_lock);

	pr_debug("%s: Starting Initialization of all channnels\n",
		  dev_ctx->netdev->name);

	for (i = 0; i < dev_ctx->chnl_cnt; i++) {
		chnl_id = i;
		/* Allocate memory for the channel context */
		chnl_ctx = kzalloc(sizeof(struct ifc_mcdma_channel), GFP_KERNEL);
		if (chnl_ctx == NULL) {
			pr_err("%s: Mem alloc failed\n", dev_ctx->netdev->name);
			goto err_chnl_malloc_fail;
		}

		chnl_ctx->channel_id = chnl_id;
		chnl_ctx->dev_ctx = dev_ctx;
		chnl_ctx_list[i] = chnl_ctx;

		/* Init Channel Context */
		ret = ifc_chnl_init(chnl_ctx, dev_ctx->qcsr);
		if (ret < 0) {
			pr_err("%s: Chnl:%d: Failed to initialize channel\n",
				dev_ctx->netdev->name, chnl_id);
			goto err_out_chnl_free;
		}
		//pr_info("%s: Chnl:%d: Initialization Successful\n",
		//		dev_ctx->netdev->name, chnl_id);
	}
	pr_debug("%s: All Channnels Initialized\n", dev_ctx->netdev->name);
#ifdef IFC_MCDMA_LB_CFG
#ifdef IFC_MCDMA_LB_DFLT_CFG
	ifc_mcdma_set_lb_config(dev_ctx, PCI_FUNC(dev_ctx->pctx.pdev->devfn));
#endif
#endif
	pr_debug("%s: Starting all queues\n", dev_ctx->netdev->name);
	netif_tx_start_all_queues(dev_ctx->netdev);
	return 0;

err_chnl_malloc_fail:
	i--;
err_out_chnl_free:
	while (i) {
		ifc_chnl_free(chnl_ctx_list[i]);
		chnl_ctx_list[i--] = NULL;
	}
	return -1;
}

static void ifc_core_free(struct ifc_core_info *core)
{
	struct ifc_queue_alloc *q, *n;

	list_for_each_entry_safe(q, n, &core->lru_list, list) {
		list_del(&q->list);
		if (q->hash)
			rb_erase(&q->node, &core->root);
		kfree(q);
	}

	core->root = RB_ROOT;
	core->rb_qcache = NULL;
	memset(core->queues_mapped, 0, sizeof(bool) * IFC_MCDMA_CHANNEL_MAX);
	memset(core->queues_allocated, 0, sizeof(bool) * IFC_MCDMA_CHANNEL_MAX);
}

int ifc_core_rebuild_all(struct ifc_mcdma_dev_ctx *dev_ctx)
{
	struct ifc_core_info *core;
	struct ifc_queue_alloc *q;
	int cpu_id;
	int i;

	ifc_core_free_all(dev_ctx);

	for (i = 0; i < dev_ctx->chnl_cnt; i++) {
		cpu_id = i % dev_ctx->num_cores;
		core = &dev_ctx->cores[cpu_id];
		core->queues_mapped[i] = true;
		dev_ctx->queue_core_mapping[i] = cpu_id;

		q = kzalloc(sizeof(*q), GFP_KERNEL);
		if (q == NULL) {
			ifc_core_free_all(dev_ctx);
			return -ENOMEM;
		}

		q->queue_id = i;
		list_add_tail(&q->list, &core->lru_list);
	}

	return 0;
}

void ifc_core_free_all(struct ifc_mcdma_dev_ctx *dev_ctx)
{
	struct ifc_core_info *core;
	int i;

	for (i = 0; i < dev_ctx->num_cores; i++) {
		core = &dev_ctx->cores[i];
		ifc_core_free(core);
	}

	/* Clear out queue_core_mapping */
	memset(dev_ctx->queue_core_mapping, 0, sizeof(int) * IFC_MCDMA_CHANNEL_MAX);
}

void ifc_mcdma_chnl_free_all(struct ifc_mcdma_dev_ctx *dev_ctx)
{
	struct ifc_mcdma_channel **chnl_ctx_list;
	int i;

	if (dev_ctx == NULL) {
		pr_err("Invalid dev_ctx\n");
		return;
	}

	chnl_ctx_list = dev_ctx->channel_context;
	for (i = 0; i < dev_ctx->chnl_cnt; i++) {
		if (chnl_ctx_list[i])
			ifc_chnl_free(chnl_ctx_list[i]);
		chnl_ctx_list[i] = NULL;
	}
	ifc_core_free_all(dev_ctx);
}

static int ifc_mcdma_netdev_open(struct net_device *netdev)
{
	struct ifc_mcdma_dev_ctx *dev_ctx;
	int ret;
	u64 val = 0;

	dev_ctx = netdev_priv(netdev);
	if (dev_ctx == NULL) {
		pr_err("%s: dev_ctx NULL\n", netdev->name);
		return -EFAULT;
	}

	ret = ifc_core_rebuild_all(dev_ctx);
	if (ret < 0)
		return ret;

	dev_ctx->gcsr = (void *)((uint64_t)dev_ctx->pctx.info[0].iaddr + 0x200000); //todo: gcsr
	dev_ctx->is_pf = true;
	ret = ifc_mcdma_chnl_init_all(dev_ctx);
	if (ret < 0) {
		pr_err("%s: Channel Initialization failed\n", netdev->name);
		ifc_core_free_all(dev_ctx);
		return -EFAULT;
	}
	pr_debug("%s: All Channel Initialization Successful\n", netdev->name);

	/* Program RSS RETA and hash key into hardware */
	ifc_mcdma_hw_write_reta(dev_ctx);
	ifc_mcdma_hw_write_rss_key(dev_ctx);
	pr_debug("%s: RSS RETA and key programmed\n", netdev->name);

#ifdef ENABLE_DEBUGFS
	ret = ifc_mcdma_debugfs_setup(netdev);
	if (ret < 0) {
		pr_err("Failed to setup debugfs\n");
		ifc_mcdma_chnl_free_all(dev_ctx);
		return -EFAULT;
	}
#endif

	/* NAPI is now initialized per-queue inside ifc_descq_init(), before
	 * request_irq(), so no external NAPI registration is needed here.
	 */

	/*close low power*/
	val = ifc_mcdma_pio_read(dev_ctx, IFC_MCDMA_BAS_ETH_CTRL);
	val &= ~(1 << 1);
	ifc_mcdma_pio_write(dev_ctx, IFC_MCDMA_BAS_ETH_CTRL, val);

	return 0;
}

static int ifc_mcdma_netdev_close(struct net_device *netdev)
{
	struct ifc_mcdma_dev_ctx *dev_ctx;
	//u64 val = 0;

	pr_debug("%s: Stopping all queues\n", netdev->name);
	netif_tx_stop_all_queues(netdev);

	dev_ctx = netdev_priv(netdev);
	if (dev_ctx == NULL) {
		pr_err("%s: dev_ctx NULL\n", netdev->name);
		return	-EFAULT;
	}
#ifdef ENABLE_DEBUGFS
	/* Remove DebugFS entries */
	ifc_mcdma_debugfs_remove(netdev);
#endif
	/* NAPI is now disabled and removed per-queue inside ifc_queue_free(),
	 * before free_irq(), so ifc_mcdma_napi_disable_all() / ifc_mcdma_del_napi()
	 * are no longer called here.
	 */

	/* Free Channel Context */
	pr_debug("%s: Freeing all queue contexts\n", netdev->name);
	ifc_mcdma_chnl_free_all(dev_ctx);

	/*open low power*/
	//val = ifc_mcdma_pio_read(dev_ctx, IFC_MCDMA_BAS_ETH_CTRL);
	//val |= (1 << 1);
	//ifc_mcdma_pio_write(dev_ctx, IFC_MCDMA_BAS_ETH_CTRL, val);

	return 0;
}

/* TX：把 skb 拷进环上槽位的 4 KB bounce 缓冲再交给 H2D。
 *
 * 为什么不再直接 DMA skb->data：skb 线性区/frag 的物理地址任意，长帧必然跨 4 KB 页，
 * 而 PCIe5 MCDMA 不能对跨页缓冲发请求（D2H 跨页实测 Malformed TLP，H2D 没有证据
 * 说明 IP 会自己按 4 KB 拆读请求）。槽缓冲 4 KB 对齐、每段 <= 4096，读请求永远不跨页；
 * 起始地址也天然满足原 MCDMA_ALIGN_ADDRESS 要求的 128 B 对齐，所以不再需要
 * tx_skb_align_workaround()。skb_copy_bits() 同时处理线性区、frags 和 frag_list，
 * 以前带 frag_list 的 skb（NETIF_F_FRAGLIST 会让核心不线性化）只发线性区的问题一并消失。
 *
 * 一帧 > 4096 时每 4096 字节一个描述符：首个 SOF、最后一个 EOF，非末段长度 4096
 * 是 128 B 的整数倍（MCDMA 未开 byte aligned transfer，非 EOF 描述符长度需按数据宽度对齐）。
 * 超过 IFC_MCDMA_TX_FRAME_MAX 的帧直接丢弃，否则会卡死 qdma_top 的 u2_tx_fifo_inst。 */
static netdev_tx_t ifc_mcdma_netdev_xmit(struct sk_buff *skb,
					 struct net_device *netdev)
{
	struct ifc_mcdma_dev_ctx *dev_ctx;
	struct ifc_mcdma_channel *chnl_ctx;
	struct ifc_mcdma_desc_sw *sw;
	struct ifc_mcdma_desc *d;
	struct ifc_mcdma_queue *q;
	uint32_t len, off, seg, slot;
	int nsegs;
	int chnl_id;
	int i;

	chnl_id = skb_get_queue_mapping(skb);

	dev_ctx = netdev_priv(netdev);
	if (dev_ctx == NULL)
		return NETDEV_TX_BUSY;

	chnl_ctx = dev_ctx->channel_context[chnl_id];
	if (chnl_ctx == NULL)
		return NETDEV_TX_BUSY;

	q = &chnl_ctx->tx;

	len = skb->len;
	if (unlikely(len == 0 || len > IFC_MCDMA_TX_FRAME_MAX)) {
		net_warn_ratelimited("%s: drop tx frame of %u bytes (max %u)\n",
				     netdev->name, len, IFC_MCDMA_TX_FRAME_MAX);
		netdev->stats.tx_dropped++;
		dev_kfree_skb_any(skb);
		return NETDEV_TX_OK;
	}
	nsegs = DIV_ROUND_UP(len, IFC_MCDMA_BUF_SIZE);

	/* check if descq has room for the whole frame */
	if (ifc_descq_empty_slots(q) < nsegs) {
		netif_stop_subqueue(netdev, chnl_id);
		/* 完成处理可能刚好在 stop 前释放了槽位，再看一次 */
		if (ifc_descq_empty_slots(q) < nsegs)
			return NETDEV_TX_BUSY;
		netif_wake_subqueue(netdev, chnl_id);
	}

	for (i = 0, off = 0; i < nsegs; i++, off += seg) {
		seg = min_t(uint32_t, len - off, IFC_MCDMA_BUF_SIZE);
		d = ifc_mcdma_desc_get(q, &slot);
		sw = &q->ctx[slot];
		/* 范围在 [0, skb->len) 内，不会失败 */
		skb_copy_bits(skb, off, sw->buf, seg);
		d->src = sw->buf_dma;
		d->dest = 0ULL;
		d->len = seg;
		d->sof = (i == 0);
		d->eof = (i == nsegs - 1);
		sw->tx_len = d->eof ? len : 0;
		ifc_mcdma_desc_put(q, d, slot);
	}

#ifdef SKB_HEX_DUMP
	print_hex_dump(KERN_DEBUG, "tx ", DUMP_PREFIX_OFFSET, 16, 1,
		       skb->data, skb_headlen(skb), true);
#endif
	/* 整帧的描述符都写好后才更新 tail，硬件不会看到半帧 */
	ifc_mcdma_desc_submit(q);

	skb_tx_timestamp(skb);
	dev_consume_skb_any(skb);
	return NETDEV_TX_OK;
}

static struct net_device_stats
	*ifc_mcdma_netdev_get_stats(struct net_device *netdev)
{
	return &netdev->stats;
}


#if 0
static void show_core_info(struct ifc_mcdma_dev_ctx *dev_ctx)
{
	struct ifc_queue_alloc *q;
	struct ifc_core_info *core;
	int i;

	pr_info("%s: Core-Channel map after updation", dev_ctx->netdev->name);
	for (i = 0; i < dev_ctx->num_cores; i++) {
		core = &dev_ctx->cores[i];
		list_for_each_entry(q, &core->lru_list, list) {
			pr_info("%s:core:%d --> chnl:%d",
				dev_ctx->netdev->name, i, q->queue_id);
		}
	}
}
#endif

static int
update_core_mapping(struct ifc_core_info *prev_core,
			struct ifc_core_info *new_core, int qid)
{
	struct ifc_queue_alloc *q, *n;

	list_for_each_entry_safe(q, n, &prev_core->lru_list, list) {
		if (q->queue_id != qid)
			continue;
		list_del(&q->list);
		if (q->hash) {
			rb_erase(&q->node, &prev_core->root);
			if (prev_core->rb_qcache && q->hash == prev_core->rb_qcache->hash)
				prev_core->rb_qcache = NULL;
			q->hash = 0U;
		}
		break;
	}
	list_add_tail(&q->list, &new_core->lru_list);
	return 0;

}

/* Please ensure calling this function before updating queue_core_mapping */
int
ifc_refresh_core_info(struct ifc_mcdma_dev_ctx *dev_ctx, int qid, int ncoreid)
{
	struct ifc_core_info *prev_core, *new_core;
	int pcoreid;

	pcoreid = dev_ctx->queue_core_mapping[qid];
	prev_core = &dev_ctx->cores[pcoreid];
	new_core = &dev_ctx->cores[ncoreid];

	mutex_lock(&dev_ctx->chnl_lock);

	netif_stop_subqueue(dev_ctx->netdev, qid);
	prev_core->queues_mapped[qid] = false;
	new_core->queues_mapped[qid] = true;
	update_core_mapping(prev_core, new_core, qid);
        dev_ctx->queue_core_mapping[qid] = ncoreid;
	netif_wake_subqueue(dev_ctx->netdev, qid);

	mutex_unlock(&dev_ctx->chnl_lock);
	return 0;
}

/* Select TX queue based on flow hash and the RSS indirection table.
 * Different iperf parallel streams have different 5-tuple hashes, so
 * they map to different queues for true multi-queue throughput.
 */
#if LINUX_VERSION_CODE < KERNEL_VERSION(4, 19, 0)
static u16 ifc_mcdma_select_queue(struct net_device *dev, struct sk_buff *skb,
                         void *accel_priv, select_queue_fallback_t fallback)
#elif LINUX_VERSION_CODE < KERNEL_VERSION(5, 2, 0)
static u16 ifc_mcdma_select_queue(struct net_device *dev, struct sk_buff *skb,
			struct net_device *sb_dev, select_queue_fallback_t fallback)
#else
static u16 ifc_mcdma_select_queue(struct net_device *dev, struct sk_buff *skb,
			struct net_device *sb_dev)
#endif
{
	struct ifc_mcdma_dev_ctx *dev_ctx = netdev_priv(dev);
	u32 hash;

	hash = skb_get_hash(skb);
	if (!hash)
		hash = get_random_u32();

	return (u16)(dev_ctx->rss_indir_table[hash & (IFC_MCDMA_RSS_INDIR_SIZE - 1)]
		     % dev_ctx->chnl_cnt);
}

static int ifc_mcdma_change_mtu(struct net_device *dev, int new_mtu)
{
	/* MTU change not possible if device is in use */
	if (dev->flags & IFF_UP)
		return -EBUSY;

	/* Validate the new MTU */
	if (new_mtu <= 0 || new_mtu > IFC_MCDMA_BUF_LIMIT)
		return -EINVAL;

	WRITE_ONCE(dev->mtu, new_mtu);
	pr_debug("%s: Changed MTU to %d successfully", dev->name, new_mtu);
	return 0;
}

int ifc_set_mac_addr(struct net_device *dev, void *addr)
{
	struct sockaddr *saddr = addr;
	u8 *dev_addr = saddr->sa_data;
	if (!is_valid_ether_addr(saddr->sa_data))
		return -EADDRNOTAVAIL;

	netdev_info(dev, "Set MAC address to %02x:%02x:%02x:%02x:%02x:%02x",
			dev_addr[0], dev_addr[1], dev_addr[2],
			dev_addr[3], dev_addr[4], dev_addr[5]);
	eth_hw_addr_set(dev, dev_addr);
	return 0;
}

static const struct net_device_ops ifc_mcdma_netdev_ops = {
	.ndo_open		= ifc_mcdma_netdev_open,
	.ndo_stop		= ifc_mcdma_netdev_close,
	.ndo_start_xmit		= ifc_mcdma_netdev_xmit,
	.ndo_select_queue       = ifc_mcdma_select_queue,
#ifdef RHEL_RELEASE_CODE
	.ndo_change_mtu_rh74	= ifc_mcdma_change_mtu,
#else
	.ndo_change_mtu		= ifc_mcdma_change_mtu,
#endif
	.ndo_validate_addr	= eth_validate_addr,
	.ndo_set_mac_address	= ifc_set_mac_addr,
	.ndo_get_stats		= ifc_mcdma_netdev_get_stats,
	.ndo_do_ioctl		= ifc_mcdma_netdev_ioctl,
#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 15, 0)
	/*
	 * Some vendor 5.10 kernels, including openEuler, do not expose
	 * ndo_siocdevprivate. Keep ndo_do_ioctl as the baseline entry and
	 * only register the private ioctl hook where the member exists.
	 */
	.ndo_siocdevprivate	= ifc_mcdma_netdev_siocdevprivate,
#endif

};

int ifc_mcdma_netdev_setup(struct net_device *dev,u32 tot_chn_aval)
{
	struct ifc_mcdma_dev_ctx *dev_ctx = netdev_priv(dev);
	struct ifc_core_info *core;
	int err = 0;
	int i;

	//strncpy(dev->name, NETDEV_NAME, sizeof(dev->name) - 1);

	/* Initialize the device structure. */
	dev->netdev_ops = &ifc_mcdma_netdev_ops;
	ifc_mcdma_set_ethtool_ops(dev);

	/* Fill in device structure with ethernet-generic values. */
	dev->features	|= NETIF_F_FRAGLIST;
	dev->features	|= NETIF_F_GSO_SOFTWARE;
	dev->features	|= NETIF_F_RXHASH;
	dev->hw_features |= dev->features;
	dev->hw_enc_features |= dev->features;
	dev_ctx->msg_enable = netif_msg_init(debug, DEFAULT_MSG_ENABLE);
	eth_hw_addr_random(dev);

	/* alloc_etherdev_mq() 把 max_mtu 固定成 1500，内核会在 ndo_change_mtu 之前
	 * 就直接拒绝更大的 `ip link set mtu`。这里必须显式放开，否则 RoCE 只能用
	 * IB MTU 1024（iboe_get_mtu(1500) = 1500 - 96 = 1404 → 1024）。
	 * IB MTU 4096 要 l2 MTU >= 4192（推荐 4200）；上限 7168 的来历见 IFC_MCDMA_L2_MTU_MAX。 */
	dev->max_mtu = IFC_MCDMA_L2_MTU_MAX;
	dev->min_mtu = ETH_MIN_MTU;

	/* Update the number of pages */
	dev_ctx->num_of_pages = IFC_MCDMA_DESC_PAGES; //todo:设置ring描述符个数

	/* Allocate memory for core info */
	dev_ctx->num_cores = num_online_cpus();
	dev_ctx->cores = kcalloc(dev_ctx->num_cores, sizeof(struct ifc_core_info), GFP_KERNEL);
	if (dev_ctx->cores == NULL) {
		pr_err("%s: Memory allocation fail\n", dev->name);
		return -ENOMEM;
	}

         /* Set max channels */
         dev_ctx->max_rx_cnt = tot_chn_aval;
         dev_ctx->max_tx_cnt = tot_chn_aval;
         dev_ctx->rx_chnl_cnt = tot_chn_aval;
         dev_ctx->tx_chnl_cnt = tot_chn_aval;
         dev_ctx->chnl_cnt = tot_chn_aval;

        //printk("max channel=%d conf=%d\n",IFC_MCDMA_CHANNEL_MAX,dev_ctx->chnl_cnt);
	/* Core info initialization */
	for (i = 0; i < dev_ctx->num_cores; i++) {
		core = &dev_ctx->cores[i];
		core->root = RB_ROOT;
		INIT_LIST_HEAD(&core->lru_list);
	}

	/* Initialize RSS indirection table with default even distribution across channels */
	for (i = 0; i < IFC_MCDMA_RSS_INDIR_SIZE; i++)
		dev_ctx->rss_indir_table[i] = i % dev_ctx->chnl_cnt;

	/* Initialize RSS hash key with default Toeplitz key */
	memcpy(dev_ctx->rss_key, ifc_mcdma_rss_key_default,
	       IFC_MCDMA_RSS_KEY_SIZE);

    #if 0
	/* Default: All Chnls mapped to core0 */
	core = &dev_ctx->cores[0];
	for (i = 0; i < dev_ctx->chnl_cnt; i++) {
		core->queues_mapped[i] = true;

		/* Allocate new queue rb node */
		q = kzalloc(sizeof(struct ifc_queue_alloc), GFP_KERNEL);
		if (q == NULL)
			goto err_out;

		/* Populate node */
		q->queue_id = i;

		/* Insert it into LRU list */
		list_add_tail(&q->list, &core->lru_list);
	}
	#endif



	return err;

}
