// SPDX-License-Identifier: GPL-2.0 OR BSD-2-Clause
/* yuanrdma provider：控制面走 uverbs 命令；数据面直接写主机内存中的环并敲 doorbell。 */
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <util/mmio.h>
#include <util/udma_barrier.h>
#include <util/util.h>

#include "provider_driver.h"
#include "yuanrdma_abi.h"

/* ---------------------------------------------------------------- 查询 / PD / MR */
int yuanrdma_query_device(struct ibv_context *context, const struct ibv_query_device_ex_input *input,
			  struct ibv_device_attr_ex *attributes, size_t attributes_size)
{
	struct ib_uverbs_ex_query_device_resp response;
	size_t response_size = sizeof(response);
	int ret;

	ret = ibv_cmd_query_device_any(context, input, attributes, attributes_size, &response, &response_size);
	if (ret)
		return ret;
	snprintf(attributes->orig_attr.fw_ver, sizeof(attributes->orig_attr.fw_ver), "%u.%u",
		 (unsigned int)(response.base.fw_ver >> 16) & 0xffff, (unsigned int)response.base.fw_ver & 0xffff);
	return 0;
}

int yuanrdma_query_port(struct ibv_context *context, uint8_t port, struct ibv_port_attr *attributes)
{
	struct ibv_query_port command = {};

	return ibv_cmd_query_port(context, port, attributes, &command, sizeof(command));
}

struct ibv_pd *yuanrdma_alloc_pd(struct ibv_context *context)
{
	struct ib_uverbs_alloc_pd_resp response;
	struct ibv_alloc_pd command = {};
	struct ibv_pd *pd = calloc(1, sizeof(*pd));

	if (!pd)
		return NULL;
	if (ibv_cmd_alloc_pd(context, pd, &command, sizeof(command), &response, sizeof(response))) {
		free(pd);
		return NULL;
	}
	return pd;
}

int yuanrdma_dealloc_pd(struct ibv_pd *pd)
{
	int ret = ibv_cmd_dealloc_pd(pd);

	if (!ret)
		free(pd);
	return ret;
}

struct ibv_mr *yuanrdma_reg_mr(struct ibv_pd *pd, void *address, size_t length, uint64_t hca_va, int access)
{
	struct ib_uverbs_reg_mr_resp response;
	struct ibv_reg_mr command;
	struct verbs_mr *mr = calloc(1, sizeof(*mr));

	if (!mr)
		return NULL;
	if (ibv_cmd_reg_mr(pd, address, length, hca_va, access, mr, &command, sizeof(command),
			   &response, sizeof(response))) {
		free(mr);
		return NULL;
	}
	return &mr->ibv_mr;
}

/* dmabuf MR：只做转发，真正的 pin / MTT 写由内核的 reg_user_mr_dmabuf 完成。
 * uverbs 慢路径（REG_DMABUF_MR 命令）只有 rdma-core >= 36 与内核 >= 5.15 才有；
 * 本栈用 code/github/rdma-core v66 自带的新接口，所以不需要 fallback。
 * 注意 mxm 类 ULP 会在失败后回退到 ibv_reg_mr，这里出错必须把 errno 带对。 */
struct ibv_mr *yuanrdma_reg_dmabuf_mr(struct ibv_pd *pd, uint64_t offset, size_t length, uint64_t iova,
				      int fd, int access)
{
	struct verbs_mr *mr = calloc(1, sizeof(*mr));
	int ret;

	if (!mr)
		return NULL;
	ret = ibv_cmd_reg_dmabuf_mr(pd, offset, length, iova, fd, access, mr, NULL);
	if (ret) {
		free(mr);
		errno = ret;
		return NULL;
	}
	return &mr->ibv_mr;
}

int yuanrdma_dereg_mr(struct verbs_mr *mr)
{
	int ret = ibv_cmd_dereg_mr(mr);

	if (!ret)
		free(mr);
	return ret;
}

/* ---------------------------------------------------------------- CQ */
struct ibv_cq *yuanrdma_create_cq(struct ibv_context *ibv_context, int cqe, struct ibv_comp_channel *channel,
				  int comp_vector)
{
	struct yuanrdma_create_cq_cmd_resp response = {};
	struct ibv_create_cq command = {};
	struct yuanrdma_cq *cq = calloc(1, sizeof(*cq));
	void *ring;

	if (!cq)
		return NULL;
	if (ibv_cmd_create_cq(ibv_context, cqe, channel, comp_vector, &cq->ibv_cq, &command, sizeof(command),
			      &response.ibv_resp, sizeof(response))) {
		free(cq);
		return NULL;
	}
	cq->cq_index = response.cq_index;
	/* S6：CQ 编号来自 QPC dw0 的 6 位位段（上限 YNRDMA_MAX_CQ = 64）。内核按
	 * yuanrdma_alloc_index(..., YNRDMA_MAX_CQ) 分配，正常不会越界；这一层防的是
	 * 内核 .ko 与 provider .so 版本错配。越界拒绝而不是继续——截断后的 cq_index
	 * 会把 doorbell 敲到别的 CQ 上（CQ40 → CQ8，40 & 15 == 8），且完全不报错。 */
	if (cq->cq_index >= YNRDMA_MAX_CQ) {
		ibv_cmd_destroy_cq(&cq->ibv_cq);
		free(cq);
		return NULL;
	}
	cq->log2_depth = response.log2_depth;
	cq->ring_size = sizeof(struct ynrdma_cqe) << cq->log2_depth;
	ring = mmap(NULL, cq->ring_size, PROT_READ | PROT_WRITE, MAP_SHARED, ibv_context->cmd_fd,
		    response.ring_mmap_key);
	if (ring == MAP_FAILED) {
		ibv_cmd_destroy_cq(&cq->ibv_cq);
		free(cq);
		return NULL;
	}
	cq->ring = ring;
	pthread_spin_init(&cq->lock, PTHREAD_PROCESS_PRIVATE);
	return &cq->ibv_cq;
}

int yuanrdma_destroy_cq(struct ibv_cq *ibv_cq)
{
	struct yuanrdma_cq *cq = to_yuanrdma_cq(ibv_cq);
	int ret = ibv_cmd_destroy_cq(ibv_cq);

	if (ret)
		return ret;
	munmap(cq->ring, cq->ring_size);
	pthread_spin_destroy(&cq->lock);
	free(cq);
	return 0;
}
/* ---------------------------------------------------------------- QP */
struct ibv_qp *yuanrdma_create_qp(struct ibv_pd *pd, struct ibv_qp_init_attr *attributes)
{
	struct yuanrdma_context *context = to_yuanrdma_context(pd->context);
	struct yuanrdma_create_qp_cmd_resp response = {};
	struct ibv_create_qp command = {};
	struct yuanrdma_qp *qp;
	void *ring;

	/* UD（G2.1 Step 2）：provider 侧放行 IBV_QPT_UD。内核 create_qp
	 * （code/kernel/yuanrdma/yuanrdma_verbs.c:521）目前仍只放 IB_QPT_RC，
	 * 所以这一层放行不会让谁「建得起来但发不对」——真正的门在上游 ioctl。
	 * 内核放行 UD 的前提是 roce_req 的 WQE_UD_SEND 与 roce_tx 的 DETH 段都已落地
	 * （见 UD 传输方案文档 §2.2/§4）。
	 * 注意：provider 不再单独判断 UD 的 max_sge，post_send 里按 wr->opcode 分派，
	 * RC 路径一个字节都不受影响。 */
	if ((attributes->qp_type != IBV_QPT_RC && attributes->qp_type != IBV_QPT_UD) || attributes->srq) {
		errno = EOPNOTSUPP;
		return NULL;
	}
	qp = calloc(1, sizeof(*qp));
	if (!qp)
		return NULL;
	if (ibv_cmd_create_qp(pd, &qp->ibv_qp, attributes, &command, sizeof(command),
			      &response.ibv_resp, sizeof(response)))
		goto free_qp;
	qp->qp_index = response.qp_index;
	qp->signal_all = attributes->sq_sig_all;
	qp->is_ud = attributes->qp_type == IBV_QPT_UD;
	qp->path_mtu = 0;		/* 未知：modify_qp(IBV_QP_PATH_MTU) 才填 */
	qp->sq_log2_depth = response.sq_log2_depth;
	qp->rq_log2_depth = response.rq_log2_depth;
	qp->sq_ring_size = sizeof(struct ynrdma_sq_wqe) << qp->sq_log2_depth;
	qp->rq_ring_size = sizeof(struct ynrdma_rq_wqe) << qp->rq_log2_depth;
	ring = mmap(NULL, qp->sq_ring_size, PROT_READ | PROT_WRITE, MAP_SHARED, pd->context->cmd_fd,
		    response.sq_mmap_key);
	if (ring == MAP_FAILED)
		goto destroy;
	qp->sq_ring = ring;
	ring = mmap(NULL, qp->rq_ring_size, PROT_READ | PROT_WRITE, MAP_SHARED, pd->context->cmd_fd,
		    response.rq_mmap_key);
	if (ring == MAP_FAILED)
		goto unmap_sq;
	qp->rq_ring = ring;
	qp->sq_wr_id = calloc(1u << qp->sq_log2_depth, sizeof(uint64_t));
	qp->rq_wr_id = calloc(1u << qp->rq_log2_depth, sizeof(uint64_t));
	if (!qp->sq_wr_id || !qp->rq_wr_id)
		goto free_shadow;
	pthread_spin_init(&qp->send_lock, PTHREAD_PROCESS_PRIVATE);
	pthread_spin_init(&qp->recv_lock, PTHREAD_PROCESS_PRIVATE);
	pthread_mutex_lock(&context->qp_table_lock);
	context->qp_table[qp->qp_index] = qp;
	pthread_mutex_unlock(&context->qp_table_lock);
	attributes->cap.max_send_wr = (1u << qp->sq_log2_depth) - 1;
	attributes->cap.max_recv_wr = (1u << qp->rq_log2_depth) - 1;
	attributes->cap.max_inline_data = response.max_inline_data;
	return &qp->ibv_qp;

free_shadow:
	free(qp->sq_wr_id);
	free(qp->rq_wr_id);
	munmap(qp->rq_ring, qp->rq_ring_size);
unmap_sq:
	munmap(qp->sq_ring, qp->sq_ring_size);
destroy:
	ibv_cmd_destroy_qp(&qp->ibv_qp);
free_qp:
	free(qp);
	return NULL;
}

int yuanrdma_modify_qp(struct ibv_qp *ibv_qp, struct ibv_qp_attr *attributes, int mask)
{
	struct yuanrdma_qp *qp = to_yuanrdma_qp(ibv_qp);
	struct ibv_modify_qp command = {};
	int ret;

	ret = ibv_cmd_modify_qp(ibv_qp, attributes, mask, &command, sizeof(command));
	if (!ret && (mask & IBV_QP_STATE) && attributes->qp_state == IBV_QPS_RESET) {
		pthread_spin_lock(&qp->send_lock);
		qp->sq_producer = qp->sq_consumer = 0;
		qp->error = false;
		pthread_spin_unlock(&qp->send_lock);
		pthread_spin_lock(&qp->recv_lock);
		qp->rq_producer = qp->rq_consumer = 0;
		pthread_spin_unlock(&qp->recv_lock);
	}
	/* 用户态只缓存，改动已经由 uverbs 写进 QPC（RTL 从 QPC 取 dst_mac/dst_ip）。
	 * 缓存的两项都只服务 post_send 的前置检查（UD 的 path_mtu 上限与 AH 一致性），
	 * 不影响控制面。 */
	if (!ret && (mask & IBV_QP_PATH_MTU) &&
	    attributes->path_mtu >= IBV_MTU_256 && attributes->path_mtu <= IBV_MTU_4096)
		qp->path_mtu = attributes->path_mtu;
	if (!ret && (mask & IBV_QP_AV)) {
		qp->av_dgid = attributes->ah_attr.grh.dgid;
		qp->av_sgid_index = attributes->ah_attr.grh.sgid_index;
		qp->av_valid = true;
	}
	return ret;
}

int yuanrdma_query_qp(struct ibv_qp *ibv_qp, struct ibv_qp_attr *attributes, int mask,
		      struct ibv_qp_init_attr *init_attributes)
{
	struct ibv_query_qp command = {};

	return ibv_cmd_query_qp(ibv_qp, attributes, mask, init_attributes, &command, sizeof(command));
}

int yuanrdma_destroy_qp(struct ibv_qp *ibv_qp)
{
	struct yuanrdma_context *context = to_yuanrdma_context(ibv_qp->context);
	struct yuanrdma_qp *qp = to_yuanrdma_qp(ibv_qp);
	int ret = ibv_cmd_destroy_qp(ibv_qp);

	if (ret)
		return ret;
	pthread_mutex_lock(&context->qp_table_lock);
	context->qp_table[qp->qp_index] = NULL;
	pthread_mutex_unlock(&context->qp_table_lock);
	munmap(qp->sq_ring, qp->sq_ring_size);
	munmap(qp->rq_ring, qp->rq_ring_size);
	free(qp->sq_wr_id);
	free(qp->rq_wr_id);
	free(qp);
	return 0;
}

/* ---------------------------------------------------------------- AH（G2.1 Step 2）
 *
 * UD 发送需要三样东西：目的 QPN、Q_Key、目的地址（dmac/dip）。前两个是 per-WR 的，
 * 落在 SQ WQE 的 dw9/dw10（见 yuanrdma_hw.h 的 sq_wqe_layout）；dmac/dip 是 per-AH 的，
 * 但 RTL 的 UD 组包**不从 WQE 取目的 MAC/IP**：roce_tx.sv:169/180 用 build_job.dmac /
 * build_job.dip，二者来自 QPC（modify_qp 的 IBV_QP_AV 已写进去，见
 * code/kernel/yuanrdma/yuanrdma_verbs.c:636-660）。所以 AH 在用户态的职责只有两条：
 *
 *   1) 把 ibv_ah_attr 解析成规范形式，参数错误在 create_ah 就报（perftest 会说
 *      "Couldn't create AH"），而不是拖到 post_send 才失败；
 *   2) post_send 时校验 wr->wr.ud.ah 与 QP 当前 AV 一致。这一步很关键：RTL 只用 QPC
 *      的目的地址，如果调用方给 QP 配了 A 的 AV、却在 post_send 里传 B 的 AH，
 *      硬件会「成功地」把包发到 A，IB 语义却要求发到 B——必须在这里挡住。
 *
 * 限制（与内核 yuanrdma_create_ah、yuanrdma_modify_qp 的 IB_QP_AV 分支一致）：
 * 只接受 RoCEv2 + IPv4（dgid 是 v4-mapped），IPv6 GID / IB 链路层都返回 EOPNOTSUPP。
 * sgid_index 只记下来，不解析成本端 IP：RTL 的本端 IP/MAC 来自 CSR
 * （YNRDMA_REG_IPV4/YNRDMA_REG_MAC_*），与 GID 表无关。
 */
static bool gid_is_v4mapped(const union ibv_gid *gid)
{
	const uint8_t *raw = gid->raw;
	int i;

	for (i = 0; i < 10; i++)
		if (raw[i])
			return false;
	return raw[10] == 0xff && raw[11] == 0xff;
}

struct ibv_ah *yuanrdma_create_ah(struct ibv_pd *pd, struct ibv_ah_attr *attr)
{
	struct yuanrdma_ah *ah;

	if (!attr) {
		errno = EINVAL;
		return NULL;
	}
	/* is_global=0 表示 IB 链路层的 LID 路由，本引擎是纯 RoCEv2，没有 LID。 */
	if (!attr->is_global || attr->grh.hop_limit == 0 || !gid_is_v4mapped(&attr->grh.dgid)) {
		errno = EOPNOTSUPP;
		return NULL;
	}
	ah = calloc(1, sizeof(*ah));
	if (!ah)
		return NULL;
	ah->ibv_ah.context = pd->context;
	ah->ibv_ah.pd = pd;
	ah->dgid = attr->grh.dgid;
	ah->sgid_index = attr->grh.sgid_index;
	ah->traffic_class = attr->grh.traffic_class;
	ah->hop_limit = attr->grh.hop_limit;
	ah->port_num = attr->port_num ? attr->port_num : 1;
	/* 源 GID 只做记录：RTL 的本端地址来自 CSR，不按 sgid_index 选。GID 表由内核
	 * yuanrdma_add_gid 维护（yuanrdma_verbs.c:131），libibverbs 的 uverbs 路径能读到，
	 * 所以这里查得到；查不到也不拒绝（perftest 常用 sgid_index=0 做 v2 IPv4 GID）。 */
	if (attr->grh.sgid_index < 16)
		ibv_query_gid(pd->context, ah->port_num, attr->grh.sgid_index, &ah->sgid);
	return &ah->ibv_ah;
}

int yuanrdma_destroy_ah(struct ibv_ah *ibv_ah)
{
	if (!ibv_ah)
		return 0;
	free(container_of(ibv_ah, struct yuanrdma_ah, ibv_ah));
	return 0;
}

/* req_notify_cq：CQ 没有中断通路（create_cq 的 channel 参数没人接，硬件侧也不产生 MSI），
 * 所以正确做法是明确报不支持，而不是挂一个「返回 0 但永远不触发事件」的假实现——
 * 后者会让事件驱动的 ULP（包括 rdma_cm 的部分路径）永远阻塞在 comp_channel 上。
 *
 * 现状：make 层面不注册这一项，ibv_req_notify_cq 会落到 libibverbs 的 ENOSYS 桩。
 * 这里保留函数体是为了让「为什么没有」留在代码里，接上中断后再挂进 ops 表。
 * 注意 device_cap_flags 里的 N_NOTIFY_CQ / RC_RNR_NAK_GEN 因此也不能置位。 */
int yuanrdma_req_notify_cq(struct ibv_cq *ibv_cq, int solicited_only)
{
	(void)ibv_cq;
	(void)solicited_only;
	return EOPNOTSUPP;
}

/* ---------------------------------------------------------------- 数据面 */
/* WQE 编码 ↔ roce_pkg.sv 的 WQE_* localparam（见 yuanrdma_hw.h 的 enum ynrdma_wqe_op）。
 * **opcode 的含义随 QP 类型变**：同一个 IBV_WR_SEND 在 RC QP 上是 WQE_SEND(2)，
 * 在 UD QP 上是 WQE_UD_SEND(5)——RTL 的 tx_opcode_of() 再翻译成线上 BTH opcode
 * （0x04 vs 0x64）。所以这里必须带 qp_type，不能只看 wr->opcode。 */
static int wqe_opcode(enum ibv_wr_opcode opcode, enum ibv_qp_type qp_type)
{
	if (qp_type == IBV_QPT_UD) {
		switch (opcode) {
		case IBV_WR_SEND:          return YNRDMA_WQE_UD_SEND;
		case IBV_WR_SEND_WITH_IMM: return YNRDMA_WQE_UD_SEND_IMM;
		/* UD 不支持 RDMA_WRITE/READ（IB 语义），也不做 FIRST/MIDDLE/LAST 分片——
		 * SEND_ONLY_UD 是单包，见 ud-transport-plan.md §2.2 第 10 条。 */
		default:                   return -1;
		}
	}
	switch (opcode) {
	case IBV_WR_RDMA_WRITE:          return YNRDMA_WQE_RDMA_WRITE;
	case IBV_WR_RDMA_WRITE_WITH_IMM: return YNRDMA_WQE_RDMA_WRITE_IMM;
	case IBV_WR_SEND:                return YNRDMA_WQE_SEND;
	case IBV_WR_SEND_WITH_IMM:       return YNRDMA_WQE_SEND_IMM;
	case IBV_WR_RDMA_READ:           return YNRDMA_WQE_RDMA_READ;
	/* 落进 default 返回 -1：post_send 把它写成 *bad_wr，调用方能拿到准确的错误点，
	 * 而不是一个「成功返回但数据丢了」的 WQE。 */
	default:                         return -1;
	}
}

/* path MTU 的 IB 枚举 → 字节数（roce_pkg.sv 的 qpc_pmtu 口径：128 << code） */
static uint32_t mtu_bytes(enum ibv_mtu mtu)
{
	return mtu ? 128u << mtu : 0;
}

/* wr->wr.ud.ah 与 QP 当前 AV 是否一致。**只对 UD 且 QP 配过 AV 时生效**：
 * RTL 用 QPC 的 dst_mac/dst_ip 组头，用 WQE 的 qpn 做 BTH/DETH，两者来自不同地方。
 *
 * 为什么不是强制：标准 UD 流程（rdma-core libibverbs/examples/ud_pingpong.c:90-117、
 * perftest 的 ud_pingpong 同理）**从不给 QP 配 IBV_QP_AV**，目的地址只在 per-WR 的 AH 里。
 * 强制要求 AV 会把标准流程挡在 post_send，比它要防的问题更糟。
 *
 * 但这留了一个真实缺口，必须说清楚：AH 只到 provider 为止，RTL 拿不到它的 dgid。
 * UD QP 若没配 AV，QPC 的 dst_mac/dst_ip 是 create_qp 时的 0，硬件会组出目的地址为 0 的
 * 帧（对端收不到，且看起来是「发出去了」）。所以走 UD 的 ULP 必须额外做一次
 * ibv_modify_qp(IBV_QP_AV) 把目的地址先写进 QPC——这是本硬件的使用约束，已写进
 * open_issues 与 skill 文档待同步。配了 AV 之后，这里的比对才真正起作用。 */
static int ud_av_matches(const struct yuanrdma_qp *qp, const struct ibv_ah *ibv_ah)
{
	const struct yuanrdma_ah *ah = container_of(ibv_ah, struct yuanrdma_ah, ibv_ah);

	if (!qp->av_valid)
		return 0;
	if (memcmp(ah->dgid.raw, qp->av_dgid.raw, sizeof(ah->dgid.raw)) ||
	    ah->sgid_index != qp->av_sgid_index)
		return EINVAL;
	return 0;
}

int yuanrdma_post_send(struct ibv_qp *ibv_qp, struct ibv_send_wr *wr, struct ibv_send_wr **bad_wr)
{
	struct yuanrdma_context *context = to_yuanrdma_context(ibv_qp->context);
	struct yuanrdma_qp *qp = to_yuanrdma_qp(ibv_qp);
	bool is_ud = qp->is_ud;
	uint32_t depth = 1u << qp->sq_log2_depth;
	uint32_t mtu = mtu_bytes(qp->path_mtu);
	bool posted = false;
	int ret = 0;

	pthread_spin_lock(&qp->send_lock);
	for (; wr; wr = wr->next) {
		int opcode = wqe_opcode(wr->opcode, ibv_qp->qp_type);
		uint32_t slot = qp->sq_producer & (depth - 1);
		struct ynrdma_sq_wqe wqe = {};

		/* SGE 条数的判定按 QP 类型分：
		 *  - RC：单 SGE（硬件与既有实现都是单段）。
		 *  - UD：IB 语义下 SGE[0] 是 payload；接收侧带 GRH 时 SGE[1] 是 40 B 的 GRH
		 *    缓冲（wire 上不发送，由 RTL 合成）。发送侧 perftest/rdma-core 只挂 1 个
		 *    SGE，所以这里接受 1 或 2，第 2 个必须是 40 B 的 GRH 影子缓冲——不是的话
		 *    报 EINVAL，绝不静默当成 payload 丢掉一段。
		 * INLINE 不发：WQE 里没有 inline 载荷区，硬件会去 laddr 取数，必须拒绝。 */
		if (qp->sq_producer - qp->sq_consumer >= depth - 1) {
			ret = ENOMEM;
		} else if (opcode < 0 || (wr->send_flags & IBV_SEND_INLINE)) {
			ret = EINVAL;
		} else if (is_ud) {
			if (wr->num_sge < 1 || wr->num_sge > 2)
				ret = EINVAL;
			else if (wr->num_sge == 2 && wr->sg_list[1].length != 40)
				ret = EINVAL;
			else if (!wr->wr.ud.ah)
				ret = EINVAL;
			else if (wr->wr.ud.remote_qpn & ~0xffffffu)
				ret = EINVAL;		/* dw9 只有 24 bit */
			else if (mtu && wr->sg_list[0].length > mtu)
				ret = EINVAL;		/* SEND_ONLY_UD 是单包：超 MTU 必须由
							 * 用户态拒绝，不是切分。下发后 RTL 会按
							 * frame_length 组一个超长帧，对端丢包。 */
			else
				ret = ud_av_matches(qp, wr->wr.ud.ah);
		} else if (wr->num_sge > 1) {
			ret = EINVAL;
		}
		if (ret) {
			*bad_wr = wr;
			break;
		}
		wqe.dw0 = opcode;
		if ((wr->send_flags & IBV_SEND_SIGNALED) || qp->signal_all)
			wqe.dw0 |= YNRDMA_WQE_F_SIGNALED;
		if (wr->send_flags & IBV_SEND_SOLICITED)
			wqe.dw0 |= YNRDMA_WQE_F_SOLICITED;
		/* num_sge == 0 是合法的零长消息（IB 允许），此时 sg_list 可以是 NULL，
		 * 不能无条件读 sg_list[0]。UD 分支在上面已经挡掉 num_sge < 1。 */
		if (wr->num_sge) {
			wqe.length = wr->sg_list[0].length;
			wqe.lkey = wr->sg_list[0].lkey;
			wqe.laddr = wr->sg_list[0].addr;
		}
		if (wr->opcode == IBV_WR_RDMA_WRITE_WITH_IMM || wr->opcode == IBV_WR_SEND_WITH_IMM)
			wqe.imm = wr->imm_data;		/* __be32：按网络序原样（RC 与 UD_IMM 共用 dw3） */
		if (!is_ud && (wr->opcode == IBV_WR_RDMA_WRITE ||
			       wr->opcode == IBV_WR_RDMA_WRITE_WITH_IMM || wr->opcode == IBV_WR_RDMA_READ)) {
			wqe.raddr = wr->wr.rdma.remote_addr;
			wqe.rkey = wr->wr.rdma.rkey;
		}
		if (is_ud) {
			/* UD 落位（yuanrdma_hw.h 的 sq_wqe_layout）：dw9[23:0] = remote_qpn，
			 * dw10[31:0] = remote_qkey。raddr/rkey 保持 0（上面 !is_ud 分支跳过），
			 * dw9[31:24] 与 dw11..dw15 由结构体零初始化保持 0。 */
			wqe.rsvd[0] = wr->wr.ud.remote_qpn & 0xffffff;
			wqe.rsvd[1] = wr->wr.ud.remote_qkey;
		}
		memcpy(&qp->sq_ring[slot], &wqe, sizeof(wqe));
		qp->sq_wr_id[slot] = wr->wr_id;
		qp->sq_producer++;
		posted = true;
	}
	if (posted) {
		udma_to_device_barrier();		/* WQE 先于 doorbell 可见 */
		mmio_write32((uint32_t *)((char *)context->doorbell_page + YNRDMA_DB_SQ),
			     ((qp->sq_producer & 0xffff) << 16) | qp->qp_index);
	}
	pthread_spin_unlock(&qp->send_lock);
	return ret;
}

int yuanrdma_post_recv(struct ibv_qp *ibv_qp, struct ibv_recv_wr *wr, struct ibv_recv_wr **bad_wr)
{
	struct yuanrdma_context *context = to_yuanrdma_context(ibv_qp->context);
	struct yuanrdma_qp *qp = to_yuanrdma_qp(ibv_qp);
	uint32_t depth = 1u << qp->rq_log2_depth;
	bool posted = false;
	int ret = 0;

	pthread_spin_lock(&qp->recv_lock);
	for (; wr; wr = wr->next) {
		uint32_t slot = qp->rq_producer & (depth - 1);
		struct ynrdma_rq_wqe wqe = {};

		if (qp->rq_producer - qp->rq_consumer >= depth - 1 || wr->num_sge > 1) {
			ret = wr->num_sge > 1 ? EINVAL : ENOMEM;
			*bad_wr = wr;
			break;
		}
		if (wr->num_sge) {
			wqe.length = wr->sg_list[0].length;
			wqe.lkey = wr->sg_list[0].lkey;
			wqe.addr = wr->sg_list[0].addr;
		}
		memcpy(&qp->rq_ring[slot], &wqe, sizeof(wqe));
		qp->rq_wr_id[slot] = wr->wr_id;
		qp->rq_producer++;
		posted = true;
	}
	if (posted) {
		udma_to_device_barrier();
		mmio_write32((uint32_t *)((char *)context->doorbell_page + YNRDMA_DB_RQ),
			     ((qp->rq_producer & 0xffff) << 16) | qp->qp_index);
	}
	pthread_spin_unlock(&qp->recv_lock);
	return ret;
}

/* 硬件出错后只给出错的那个 WQE 写 CQE，其后的 WQE 由这里冲刷成 FLUSH_ERR */
static int flush_queue(struct yuanrdma_qp *qp, bool flush_send, bool flush_recv, int entries, struct ibv_wc *wc)
{
	int count = 0;

	while (flush_send && count < entries && qp->sq_consumer != qp->sq_producer) {
		uint32_t slot = qp->sq_consumer & ((1u << qp->sq_log2_depth) - 1);

		memset(&wc[count], 0, sizeof(wc[count]));
		wc[count].wr_id = qp->sq_wr_id[slot];
		wc[count].status = IBV_WC_WR_FLUSH_ERR;
		wc[count].qp_num = qp->ibv_qp.qp_num;
		qp->sq_consumer++;
		count++;
	}
	while (flush_recv && count < entries && qp->rq_consumer != qp->rq_producer) {
		uint32_t slot = qp->rq_consumer & ((1u << qp->rq_log2_depth) - 1);

		memset(&wc[count], 0, sizeof(wc[count]));
		wc[count].wr_id = qp->rq_wr_id[slot];
		wc[count].status = IBV_WC_WR_FLUSH_ERR;
		wc[count].opcode = IBV_WC_RECV;
		wc[count].qp_num = qp->ibv_qp.qp_num;
		qp->rq_consumer++;
		count++;
	}
	return count;
}

int yuanrdma_poll_cq(struct ibv_cq *ibv_cq, int entries, struct ibv_wc *wc)
{
	struct yuanrdma_context *context = to_yuanrdma_context(ibv_cq->context);
	struct yuanrdma_cq *cq = to_yuanrdma_cq(ibv_cq);
	uint32_t depth = 1u << cq->log2_depth;
	int count = 0, qp_index;

	pthread_spin_lock(&cq->lock);
	while (count < entries) {
		struct ynrdma_cqe *cqe = &cq->ring[cq->consumer & (depth - 1)];
		uint32_t dw0 = le32toh(*(volatile uint32_t *)&cqe->dw0);
		uint32_t expected_owner = ((cq->consumer >> cq->log2_depth) & 1) ^ 1;
		struct yuanrdma_qp *qp;
		uint32_t wqe_index, slot;

		if ((dw0 >> 31) != expected_owner)
			break;
		udma_from_device_barrier();		/* 先看到 owner 再读其余字段 */
		wqe_index = le32toh(cqe->dw1) & 0xffff;
		qp_index = (le32toh(cqe->dw1) >> 16) & 0xff;
		cq->consumer++;
		qp = qp_index < YNRDMA_MAX_QP ? context->qp_table[qp_index] : NULL;
		if (!qp)
			continue;
		memset(&wc[count], 0, sizeof(wc[count]));
		wc[count].status = (dw0 >> 8) & 0xff;
		wc[count].opcode = dw0 & 0xff;
		wc[count].byte_len = le32toh(cqe->byte_len);
		wc[count].qp_num = qp->ibv_qp.qp_num;
		/* src_qp：只有 dw4[24]（src_qp_valid）为 1 才有意义（UD 接收；RC 恒 0）。
		 * 不能无条件读——S6 之前 dw4 是 rsvd，老环残留会让 RC 完成报出随机 src_qp。
		 * 全 1（0xffffff，组播/未定义）原样透传，IB 语义如此。 */
		{
			uint32_t dw4 = le32toh(cqe->dw4);

			wc[count].src_qp = (dw4 & (1u << 24)) ? (dw4 & 0xffffffu) : 0;
		}
		if ((dw0 >> 16) & 1) {
			wc[count].wc_flags |= IBV_WC_WITH_IMM;
			wc[count].imm_data = cqe->imm;
		}
		/* has_grh（dw0[18]）：UD 收包时接收缓冲**前 40 B 是 GRH**，byte_len 不含这 40 B。
		 * 只有 UD 会置这一位，RC 恒 0。 */
		if ((dw0 >> 18) & 1)
			wc[count].wc_flags |= IBV_WC_GRH;
		if ((dw0 >> 17) & 1) {			/* 接收完成：RQ 按序 */
			slot = wqe_index & ((1u << qp->rq_log2_depth) - 1);
			wc[count].wr_id = qp->rq_wr_id[slot];
			qp->rq_consumer++;
		} else {				/* 发送完成：之前未 signaled 的 WQE 一并退休 */
			slot = wqe_index & ((1u << qp->sq_log2_depth) - 1);
			wc[count].wr_id = qp->sq_wr_id[slot];
			qp->sq_consumer += ((slot - qp->sq_consumer) & ((1u << qp->sq_log2_depth) - 1)) + 1;
		}
		if (wc[count].status != IBV_WC_SUCCESS)
			qp->error = true;
		count++;
	}
	/* 出错的 QP：其余 WQE 冲刷 */
	for (qp_index = 0; qp_index < YNRDMA_MAX_QP && count < entries; qp_index++) {
		struct yuanrdma_qp *qp = context->qp_table[qp_index];

		if (qp && qp->error)
			count += flush_queue(qp, qp->ibv_qp.send_cq == ibv_cq, qp->ibv_qp.recv_cq == ibv_cq,
					     entries - count, &wc[count]);
	}
	if (count)
		mmio_write32((uint32_t *)((char *)context->doorbell_page + YNRDMA_DB_CQ),
			     ((cq->consumer & 0xffff) << 16) | cq->cq_index);
	pthread_spin_unlock(&cq->lock);
	return count;
}
