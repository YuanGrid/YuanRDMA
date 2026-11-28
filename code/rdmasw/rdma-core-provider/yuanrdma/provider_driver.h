/* SPDX-License-Identifier: GPL-2.0 OR BSD-2-Clause */
/*
 * yuanrdma provider：YuanNIC-NH400-C RoCEv2 引擎的 rdma-core 用户态驱动（数据面）。
 * 硬件格式见 code/rdmasw/include/yuanrdma_hw.h，内核接口见 code/kernel/yuanrdma/yuanrdma_abi_defs.h。
 */
#ifndef YUANRDMA_PROVIDER_H
#define YUANRDMA_PROVIDER_H

#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <infiniband/driver.h>

#include "yuanrdma_hw.h"

struct yuanrdma_device {
	struct verbs_device ibv_device;
};

struct yuanrdma_qp;

struct yuanrdma_context {
	struct verbs_context ibv_context;
	uint32_t *doorbell_page;		/* 4 KB，DB_SQ/DB_RQ/DB_CQ 在页内 0x00/0x08/0x10（PCIe5 <<1，见 yuanrdma_hw.h） */
	pthread_mutex_t qp_table_lock;
	/* 编译期定长，随 YNRDMA_MAX_QP 自动变大（S4 起 128）。qp_index 由内核 create_qp 分配
	 * （< max_qp），provider 按它直接下标，别引入任何固定 16 的下标/掩码。 */
	struct yuanrdma_qp *qp_table[YNRDMA_MAX_QP];
};

struct yuanrdma_cq {
	struct ibv_cq ibv_cq;
	pthread_spinlock_t lock;
	struct ynrdma_cqe *ring;
	size_t ring_size;
	uint32_t cq_index;
	uint32_t log2_depth;
	uint32_t consumer;			/* 软件 CI（自由增长） */
};

/*
 * provider 侧的 AH（UD 用）。RTL 组 UD 帧的 Eth/IP 头取自 QPC，SQ WQE 里只有 remote_qpn 与
 * qkey，所以 AH 本身到不了硬件：post_send 发现 wr->wr.ud.ah 与 QP 当前写进 QPC 的目的地址
 * 不同时，用 attr 发一次 modify_qp(IBV_QP_AV)（内核解析 dmac 并写 QPC），见 ud_set_destination。
 */
struct yuanrdma_ah {
	struct ibv_ah ibv_ah;
	struct ibv_ah_attr attr;		/* create_ah 时的原样拷贝（已校验 RoCEv2 + v4-mapped dgid） */
	union ibv_gid sgid;
};

struct yuanrdma_qp {
	struct ibv_qp ibv_qp;
	pthread_spinlock_t send_lock;
	pthread_spinlock_t recv_lock;
	uint32_t qp_index;
	struct ynrdma_sq_wqe *sq_ring;
	struct ynrdma_rq_wqe *rq_ring;
	size_t sq_ring_size, rq_ring_size;
	uint32_t sq_log2_depth, rq_log2_depth;
	uint32_t sq_producer, sq_consumer;	/* 软件计数（自由增长），槽号 = 计数 & (depth-1) */
	uint32_t rq_producer, rq_consumer;
	uint32_t rq_db_producer;		/* 最近一次写进 RQ 门铃的 rq_producer（recv_lock 保护），见 rq_ring_doorbell */
	uint64_t *sq_wr_id;
	uint64_t *rq_wr_id;
	bool error;				/* 收到过错误 CQE：其余 WQE 由 provider 冲刷 */
	bool signal_all;			/* ibv_qp_init_attr.sq_sig_all */
	bool is_ud;				/* 由 ibv_qp.qp_type 派生，post_send 用它选 UD 分支 */
	/* modify_qp(IBV_QP_PATH_MTU) 记下的路径 MTU。0 = 用户没设：此时不做
	 * SEND_ONLY_UD 的长度检查（perftest 一定会设，但别让没设的人全被 EINVAL 挡掉）。 */
	enum ibv_mtu path_mtu;
	/* UD：QPC 里当前的目的地址（最近一次成功的 modify_qp(IBV_QP_AV)，用户显式下发或
	 * post_send 按 AH 自动下发）。post_send 拿 wr->wr.ud.ah 和它比，不同就要改写 QPC。 */
	struct ibv_global_route av;
	bool av_valid;
	/* UD 接收：每个 RQ 槽的用户缓冲起址。RQ WQE 下发的是「起址 + 40」（IB 语义：UD 接收缓冲
	 * 前 40 B 留给 GRH），poll_cq 在 CQE 带了 IPv4 信息时把合成的 GRH 写回这里。RC 不分配。 */
	uint64_t *rq_addr;
	/* IBV_SEND_INLINE 的软件实现：WQE 里没有 inline 载荷区，所以每个 SQ 槽配一格跳板缓冲
	 * （整块注册成一个 MR），post_send 把载荷拷进对应槽、按普通单 SGE 下发。
	 * 只在 create_qp 要了 max_inline_data 时才分配（占 1 个 MR），不要 inline 的 QP 零开销。 */
	uint8_t *inline_buf;
	struct ibv_mr *inline_mr;
	uint32_t inline_stride;			/* 每槽字节数，64 B 对齐；0 = 未启用 */
	uint32_t max_inline;			/* 对外报的 cap.max_inline_data */
};

/* 单 QP 允许的最大 inline 载荷。跳板缓冲 = 槽数 × 对齐后长度，SQ 深 1024 时 512 B 对应 512 KB。 */
#define YUANRDMA_MAX_INLINE 512

static inline struct yuanrdma_context *to_yuanrdma_context(struct ibv_context *context)
{
	return container_of(context, struct yuanrdma_context, ibv_context.context);
}

static inline struct yuanrdma_cq *to_yuanrdma_cq(struct ibv_cq *cq)
{
	return container_of(cq, struct yuanrdma_cq, ibv_cq);
}

static inline struct yuanrdma_qp *to_yuanrdma_qp(struct ibv_qp *qp)
{
	return container_of(qp, struct yuanrdma_qp, ibv_qp);
}

int yuanrdma_query_device(struct ibv_context *context, const struct ibv_query_device_ex_input *input,
			  struct ibv_device_attr_ex *attributes, size_t attributes_size);
int yuanrdma_query_port(struct ibv_context *context, uint8_t port, struct ibv_port_attr *attributes);
struct ibv_pd *yuanrdma_alloc_pd(struct ibv_context *context);
int yuanrdma_dealloc_pd(struct ibv_pd *pd);
struct ibv_mr *yuanrdma_reg_mr(struct ibv_pd *pd, void *address, size_t length, uint64_t hca_va, int access);
/* dmabuf MR：转发到内核的 reg_user_mr_dmabuf（uverbs 的 REG_DMABUF_MR）。与 reg_mr 共用
 * 同一个 verbs_mr，dereg_mr 也共用——内核按 handle 释放，不看 mr_type。 */
struct ibv_mr *yuanrdma_reg_dmabuf_mr(struct ibv_pd *pd, uint64_t offset, size_t length, uint64_t iova,
				      int fd, int access);
int yuanrdma_dereg_mr(struct verbs_mr *mr);
struct ibv_cq *yuanrdma_create_cq(struct ibv_context *context, int cqe, struct ibv_comp_channel *channel,
				  int comp_vector);
int yuanrdma_destroy_cq(struct ibv_cq *cq);
int yuanrdma_poll_cq(struct ibv_cq *cq, int entries, struct ibv_wc *wc);
/* UD（G2.1 Step 2）：create_ah 只接受 RoCEv2 v4-mapped dgid，存 dgid/sgid_index 供
 * post_send 校验；remote_qpn/remote_qkey 来自 wr->wr.ud，不进 AH（见 sq_wqe_layout）。 */
struct ibv_ah *yuanrdma_create_ah(struct ibv_pd *pd, struct ibv_ah_attr *attr);
int yuanrdma_destroy_ah(struct ibv_ah *ah);
int yuanrdma_req_notify_cq(struct ibv_cq *cq, int solicited_only);
struct ibv_qp *yuanrdma_create_qp(struct ibv_pd *pd, struct ibv_qp_init_attr *attributes);
int yuanrdma_modify_qp(struct ibv_qp *qp, struct ibv_qp_attr *attributes, int mask);
int yuanrdma_query_qp(struct ibv_qp *qp, struct ibv_qp_attr *attributes, int mask,
		      struct ibv_qp_init_attr *init_attributes);
int yuanrdma_destroy_qp(struct ibv_qp *qp);
int yuanrdma_post_send(struct ibv_qp *qp, struct ibv_send_wr *wr, struct ibv_send_wr **bad_wr);
int yuanrdma_post_recv(struct ibv_qp *qp, struct ibv_recv_wr *wr, struct ibv_recv_wr **bad_wr);

#endif
