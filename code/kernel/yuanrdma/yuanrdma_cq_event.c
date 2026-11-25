// SPDX-License-Identifier: GPL-2.0 OR BSD-2-Clause
/*
 * yuanrdma_cq_event.c - 用户态（硬件）CQ 的完成事件：软件监视 owner 位实现 req_notify_cq。
 *
 * 为什么要软件做
 *   硬件把 CQE 直接写进主机内存里的 CQ 环，不产生 MSI，也不提供可读的 producer 计数，
 *   所以内核原来无法实现 req_notify_cq，ibv_create_comp_channel / ibv_get_cq_event
 *   这条事件链用不了。librdmacm 的 ucma_create_cqs() 无条件建 comp channel，
 *   rping / ucmatose / rdma_server / rdma_client 都卡在这里。
 *
 * 原理
 *   CQE dw0[31] 是 owner 位：硬件写第 n 个 CQE（从 0 计）时写 !((n >> log2_depth) & 1)，
 *   即第一圈写 1、第二圈写 0；环由内核 dma_alloc_coherent 分配（初值全 0），provider 只读不写。
 *   因此任意时刻环上的 owner 序列都是一个阶跃：[v × p, !v × (depth - p)]，跳变点 p 就是
 *   下一个 CQE 要落的格（没有跳变时 p = 0）。
 *
 *   req_notify_cq 时用二分找到 p，记下 owner[p] 的当前值，把 CQ 挂进 armed 链表；
 *   一个软中断上下文的 hrtimer 每 cq_event_poll_us 微秒看一次各 armed CQ 的那一格，
 *   owner 变了就说明 arm 之后到过新 CQE：摘链、调 comp_handler，ib_uverbs 把事件投进
 *   该 CQ 绑定的 comp channel。
 *
 * 语义
 *   - 与 IB_CQ_NEXT_COMP 一致：arm 之后的第一个完成触发一次事件，之后需要重新 arm。
 *   - IB_CQ_SOLICITED 按 NEXT_COMP 处理：可能多唤醒一次，不会丢事件。
 *   - arm 之前已到达、尚未 poll 的 CQE 不触发事件，与真实硬件 CQ 相同；ULP 的标准写法
 *     （arm 之后再 poll 一次，例如 librdmacm 的 rdma_get_send_comp）覆盖这个窗口。
 *   - 事件延迟上限约为一个轮询周期（默认 20 µs），只影响事件驱动的控制面 ULP。
 *
 * 开销
 *   hrtimer 只在至少有一个 armed CQ 时运行；perftest、NCCL 这类忙轮询的 ULP 从不 arm，零开销。
 */
#include <linux/hrtimer.h>
#include <linux/ktime.h>
#include <linux/module.h>
#include "yuanrdma_driver.h"

static unsigned int cq_event_poll_us = 20;
module_param(cq_event_poll_us, uint, 0644);
MODULE_PARM_DESC(cq_event_poll_us, "armed CQ 的 owner 位轮询周期（微秒，默认 20，0 按 1 处理）");

static u32 cqe_owner(const struct yuanrdma_cq *cq, u32 slot)
{
	const struct ynrdma_cqe *cqe = (const struct ynrdma_cqe *)cq->ring->cpu_address + slot;

	return le32_to_cpu((__force __le32)READ_ONCE(cqe->dw0)) >> 31;
}

/* 下一个 CQE 落在哪一格：owner 序列是阶跃 [v × p, !v × (depth - p)]，二分找第一个 != owner[0] 的格。
 * 扫描期间硬件可能又写了 CQE，求出的 p 偏小；那一格的 owner 已经变了，下一次轮询立刻触发事件——
 * 多一次事件无害（ULP poll 到什么算什么），不会漏。 */
static u32 cq_producer_slot(const struct yuanrdma_cq *cq)
{
	u32 depth = 1u << cq->log2_depth;
	u32 first = cqe_owner(cq, 0);
	u32 lo = 1, hi = depth;		/* 答案在 [lo, hi)；hi == depth 表示整环同值 */

	while (lo < hi) {
		u32 mid = lo + (hi - lo) / 2;

		if (cqe_owner(cq, mid) != first)
			hi = mid;
		else
			lo = mid + 1;
	}
	return lo == depth ? 0 : lo;
}

static ktime_t cq_event_period(void)
{
	unsigned int us = READ_ONCE(cq_event_poll_us);

	return ns_to_ktime((u64)(us ? us : 1) * NSEC_PER_USEC);
}

static enum hrtimer_restart yuanrdma_cq_event_poll(struct hrtimer *timer)
{
	struct yuanrdma_dev *dev = container_of(timer, struct yuanrdma_dev, cq_arm_timer);
	struct yuanrdma_cq *cq, *next;
	enum hrtimer_restart ret = HRTIMER_NORESTART;
	unsigned long flags;

	spin_lock_irqsave(&dev->cq_arm_lock, flags);
	list_for_each_entry_safe(cq, next, &dev->armed_cqs, arm_node) {
		if (cqe_owner(cq, cq->watch_slot) == cq->watch_owner)
			continue;
		list_del_init(&cq->arm_node);
		dev->cq_event_stats.events++;
		/* ib_uverbs_comp_handler 只在自己的 ev_queue 锁下入队并唤醒，不回调本驱动，可在持锁时调用 */
		if (cq->ibcq.comp_handler)
			cq->ibcq.comp_handler(&cq->ibcq, cq->ibcq.cq_context);
	}
	if (list_empty(&dev->armed_cqs)) {
		dev->cq_arm_timer_on = false;
	} else {
		hrtimer_forward_now(timer, cq_event_period());
		ret = HRTIMER_RESTART;
	}
	spin_unlock_irqrestore(&dev->cq_arm_lock, flags);
	return ret;
}

int yuanrdma_hw_cq_arm(struct yuanrdma_cq *cq)
{
	struct yuanrdma_dev *dev = to_yuanrdma_dev(cq->ibcq.device);
	unsigned long flags;

	spin_lock_irqsave(&dev->cq_arm_lock, flags);
	cq->watch_slot = cq_producer_slot(cq);
	cq->watch_owner = cqe_owner(cq, cq->watch_slot);
	if (list_empty(&cq->arm_node))
		list_add_tail(&cq->arm_node, &dev->armed_cqs);
	dev->cq_event_stats.arms++;
	/* cq_arm_timer_on 由同一把锁保护：回调判定「链表空、不再重启」与这里「链表非空、需要启动」
	 * 互斥。回调已放锁但尚未返回时再 hrtimer_start 是允许的（核心会以新的到期时间入队）。 */
	if (!dev->cq_arm_timer_on) {
		dev->cq_arm_timer_on = true;
		hrtimer_start(&dev->cq_arm_timer, cq_event_period(), HRTIMER_MODE_REL_SOFT);
	}
	spin_unlock_irqrestore(&dev->cq_arm_lock, flags);
	return 0;
}

/* destroy_cq 在释放 CQ 之前调用：摘链后回调不会再碰这个 CQ（回调全程持同一把锁） */
void yuanrdma_hw_cq_disarm(struct yuanrdma_cq *cq)
{
	struct yuanrdma_dev *dev = to_yuanrdma_dev(cq->ibcq.device);
	unsigned long flags;

	spin_lock_irqsave(&dev->cq_arm_lock, flags);
	list_del_init(&cq->arm_node);
	spin_unlock_irqrestore(&dev->cq_arm_lock, flags);
}

/* QP 进 ERR 时调用：CQ 若已 arm，立即投递一次事件（不等 owner 位翻转）。
 * 冲刷完成由 provider 在 poll_cq 里合成，硬件环上不会出现新 CQE，不叫醒就永远等不到。 */
void yuanrdma_hw_cq_kick(struct yuanrdma_cq *cq)
{
	struct yuanrdma_dev *dev;
	unsigned long flags;

	if (!cq || cq->software)
		return;
	dev = to_yuanrdma_dev(cq->ibcq.device);
	spin_lock_irqsave(&dev->cq_arm_lock, flags);
	if (!list_empty(&cq->arm_node)) {
		list_del_init(&cq->arm_node);
		dev->cq_event_stats.events++;
		if (cq->ibcq.comp_handler)
			cq->ibcq.comp_handler(&cq->ibcq, cq->ibcq.cq_context);
	}
	spin_unlock_irqrestore(&dev->cq_arm_lock, flags);
}

void yuanrdma_cq_event_init(struct yuanrdma_dev *dev)
{
	spin_lock_init(&dev->cq_arm_lock);
	INIT_LIST_HEAD(&dev->armed_cqs);
	dev->cq_arm_timer_on = false;
	hrtimer_init(&dev->cq_arm_timer, CLOCK_MONOTONIC, HRTIMER_MODE_REL_SOFT);
	dev->cq_arm_timer.function = yuanrdma_cq_event_poll;
}

/* ib_unregister_device 之后调用：此时所有 CQ 已销毁、链表为空，只需确保定时器不再运行 */
void yuanrdma_cq_event_cleanup(struct yuanrdma_dev *dev)
{
	hrtimer_cancel(&dev->cq_arm_timer);
}
