// SPDX-License-Identifier: GPL-2.0 OR BSD-2-Clause
/* yuanrdma provider：控制面走 uverbs 命令；数据面直接写主机内存中的环并敲 doorbell。 */
#include <endian.h>
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
	uint32_t want_inline;
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
	want_inline = attributes->cap.max_inline_data;
	if (want_inline > YUANRDMA_MAX_INLINE) {
		errno = EINVAL;
		return NULL;
	}
	qp = calloc(1, sizeof(*qp));
	if (!qp)
		return NULL;
	/* inline 由 provider 用跳板缓冲实现，内核不知道也不需要知道（它对 max_inline_data > 0 一律拒绝） */
	attributes->cap.max_inline_data = 0;
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
	if (qp->is_ud) {
		qp->rq_addr = calloc(1u << qp->rq_log2_depth, sizeof(uint64_t));
		if (!qp->rq_addr)
			goto free_shadow;
	}
	if (want_inline) {
		size_t size;

		qp->inline_stride = (want_inline + 63) & ~63u;
		size = (size_t)qp->inline_stride << qp->sq_log2_depth;
		if (posix_memalign((void **)&qp->inline_buf, 4096, size)) {
			qp->inline_buf = NULL;
			goto free_shadow;
		}
		qp->inline_mr = ibv_reg_mr(pd, qp->inline_buf, size, IBV_ACCESS_LOCAL_WRITE);
		if (!qp->inline_mr)
			goto free_shadow;
		qp->max_inline = want_inline;
	}
	pthread_spin_init(&qp->send_lock, PTHREAD_PROCESS_PRIVATE);
	pthread_spin_init(&qp->recv_lock, PTHREAD_PROCESS_PRIVATE);
	pthread_mutex_lock(&context->qp_table_lock);
	context->qp_table[qp->qp_index] = qp;
	pthread_mutex_unlock(&context->qp_table_lock);
	attributes->cap.max_send_wr = (1u << qp->sq_log2_depth) - 1;
	attributes->cap.max_recv_wr = (1u << qp->rq_log2_depth) - 1;
	attributes->cap.max_inline_data = qp->max_inline;
	return &qp->ibv_qp;

free_shadow:
	if (qp->inline_mr)
		ibv_dereg_mr(qp->inline_mr);
	free(qp->inline_buf);
	free(qp->sq_wr_id);
	free(qp->rq_wr_id);
	free(qp->rq_addr);
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

	/* 进 ERR：未完成的 WQE 要以 FLUSH_ERR 完成（rdma_disconnect 走的就是这条）。硬件不写冲刷 CQE，
	 * 由 poll_cq 末尾的 flush_queue 按 qp->error 合成。**必须在下发命令之前置位**：内核处理
	 * 这条命令时会叫醒已 arm 的 CQ，被叫醒的线程紧接着 poll，那时就要能看到冲刷项。 */
	bool to_error = (mask & IBV_QP_STATE) && attributes->qp_state == IBV_QPS_ERR;
	bool was_error = qp->error;

	if (to_error)
		qp->error = true;
	ret = ibv_cmd_modify_qp(ibv_qp, attributes, mask, &command, sizeof(command));
	if (ret && to_error)
		qp->error = was_error;
	if (!ret && (mask & IBV_QP_STATE) && attributes->qp_state == IBV_QPS_RESET) {
		pthread_spin_lock(&qp->send_lock);
		qp->sq_producer = qp->sq_consumer = 0;
		qp->error = false;
		pthread_spin_unlock(&qp->send_lock);
		pthread_spin_lock(&qp->recv_lock);
		qp->rq_producer = qp->rq_consumer = qp->rq_db_producer = 0;
		pthread_spin_unlock(&qp->recv_lock);
	}
	/* 用户态只缓存，改动已经由 uverbs 写进 QPC（RTL 从 QPC 取 dst_mac/dst_ip）。
	 * 缓存的两项都只服务 post_send（UD 的 path_mtu 上限、QPC 当前目的地址），不影响控制面。 */
	if (!ret && (mask & IBV_QP_PATH_MTU) &&
	    attributes->path_mtu >= IBV_MTU_256 && attributes->path_mtu <= IBV_MTU_4096)
		qp->path_mtu = attributes->path_mtu;
	if (!ret && (mask & IBV_QP_AV)) {
		pthread_spin_lock(&qp->send_lock);
		qp->av = attributes->ah_attr.grh;
		qp->av_valid = true;
		pthread_spin_unlock(&qp->send_lock);
	}
	return ret;
}

int yuanrdma_query_qp(struct ibv_qp *ibv_qp, struct ibv_qp_attr *attributes, int mask,
		      struct ibv_qp_init_attr *init_attributes)
{
	struct ibv_query_qp command = {};
	int ret = ibv_cmd_query_qp(ibv_qp, attributes, mask, init_attributes, &command, sizeof(command));

	/* inline 是 provider 实现的，内核报 0，这里换成真实上限 */
	if (!ret) {
		attributes->cap.max_inline_data = to_yuanrdma_qp(ibv_qp)->max_inline;
		init_attributes->cap.max_inline_data = to_yuanrdma_qp(ibv_qp)->max_inline;
	}
	return ret;
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
	if (qp->inline_mr)
		ibv_dereg_mr(qp->inline_mr);
	free(qp->inline_buf);
	free(qp->sq_wr_id);
	free(qp->rq_wr_id);
	free(qp->rq_addr);
	free(qp);
	return 0;
}

/* ---------------------------------------------------------------- AH
 *
 * UD 发送需要三样东西：目的 QPN、Q_Key、目的地址（dmac/dip/TTL/TOS）。前两个是 per-WR 的，
 * 落在 SQ WQE 的 dw9/dw10（见 yuanrdma_hw.h 的 sq_wqe_layout）；目的地址是 per-AH 的，
 * 但 RTL 的 UD 组包**不从 WQE 取目的 MAC/IP**：roce_req 的 tx_job.dmac/dip 来自 QPC。
 * 所以 AH 在用户态的职责是：
 *
 *   1) 把 ibv_ah_attr 解析成规范形式，参数错误在 create_ah 就报（perftest 会说
 *      "Couldn't create AH"），而不是拖到 post_send 才失败；
 *   2) post_send 时与 QP 当前写进 QPC 的目的地址比对，不同就先改写 QPC
 *      （ud_set_destination：modify_qp(IBV_QP_AV)，内核解析 dmac 后整项写 QPC）。
 *
 * 限制（与内核 yuanrdma_modify_qp 的 IB_QP_AV 分支一致）：
 * 只接受 RoCEv2 + IPv4（dgid 是 v4-mapped），IPv6 GID / IB 链路层都返回 EOPNOTSUPP。
 * 本端 IP/MAC 来自 CSR（YNRDMA_REG_IPV4/YNRDMA_REG_MAC_*），与 sgid_index 无关；
 * sgid_index 只交给内核选 GID 类型（必须是 RoCEv2）与做 ARP。
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
	ah->attr = *attr;
	if (!ah->attr.port_num)
		ah->attr.port_num = 1;
	/* 源 GID 只做记录；GID 表由内核 yuanrdma_add_gid 维护，查不到也不拒绝。 */
	if (attr->grh.sgid_index < 16)
		ibv_query_gid(pd->context, ah->attr.port_num, attr->grh.sgid_index, &ah->sgid);
	return &ah->ibv_ah;
}

int yuanrdma_destroy_ah(struct ibv_ah *ibv_ah)
{
	if (!ibv_ah)
		return 0;
	free(container_of(ibv_ah, struct yuanrdma_ah, ibv_ah));
	return 0;
}

/* req_notify_cq：硬件 CQ 不产生 MSI，完成事件由内核软件提供——arm 时内核记下下一个 CQE 将落的格，
 * hrtimer 监视该格 owner 位，翻转即把事件投进本 CQ 绑定的 comp channel（内核 yuanrdma_cq_event.c）。
 * 所以这里只需把 arm 请求交给内核；solicited_only 在内核按 NEXT_COMP 处理（可能多唤醒，不会丢事件）。 */
int yuanrdma_req_notify_cq(struct ibv_cq *ibv_cq, int solicited_only)
{
	return ibv_cmd_req_notify_cq(ibv_cq, solicited_only);
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

/*
 * UD：保证 QPC 的目的地址就是 wr->wr.ud.ah。调用方持有 send_lock。
 *
 * RTL 组 UD 帧的 Eth/IP 头（dmac、dip、TTL、TOS、UDP sport）取自 QPC，WQE 里只带 remote_qpn
 * 与 qkey。标准 UD 用法（rdma_cm 的 udaddy、ud_pingpong、perftest）只在 WR 上给 AH、从不
 * modify_qp(IBV_QP_AV)，不补这一步时 QPC 的目的地址是 create_qp 时的 0：帧发往
 * 0.0.0.0 / 00:00:00:00:00:00、TTL 0（直连 ConnectX 时对端照收，但它从接收到的 IPv4 头
 * 里取不到可用的目的地址，ibv_create_ah_from_wc 失败；过交换机则根本到不了）。
 *
 * 做法：AH 与 QPC 当前目的地址不同就发一次 modify_qp(IBV_QP_AV)（内核解析 dmac 并整项写
 * QPC），之后同一个 AH 的 WR 直接走快路径。
 *
 * **语义限制**：QPC 只有一份目的地址，RTL 在取 WQE 时读它。所以换目的地址时 SQ 里不能有
 * 还没退休的 WQE（包括本次 post_send 链里排在前面、尚未敲 doorbell 的那些），否则它们会被
 * 发到新地址。判据是 provider 自己的 sq_consumer == sq_producer，sq_consumer 只在 poll 到
 * 发送 CQE 时前进——换地址前，之前的 WQE 必须都以 signaled CQE 退休（最后一个 signaled
 * 即可，前面未 signaled 的随它一起退休）。不满足返回 EBUSY，不静默错发。
 * 一个 QP 只对一个目的地址（udaddy 每个连接一个 QP、ud_pingpong、perftest 每 QP 一个 AH）
 * 只在第一条 WR 上付一次 modify_qp 的代价（含一次 ARP 查询，邻居表已有时是微秒级）。
 */
static bool ud_same_route(const struct ibv_global_route *a, const struct ibv_global_route *b)
{
	return !memcmp(a->dgid.raw, b->dgid.raw, sizeof(a->dgid.raw)) && a->sgid_index == b->sgid_index &&
	       a->flow_label == b->flow_label && a->hop_limit == b->hop_limit &&
	       a->traffic_class == b->traffic_class;
}

static int ud_set_destination(struct yuanrdma_qp *qp, const struct ibv_ah *ibv_ah)
{
	const struct yuanrdma_ah *ah = container_of(ibv_ah, struct yuanrdma_ah, ibv_ah);
	struct ibv_modify_qp command = {};
	struct ibv_qp_attr attr = {};
	int ret;

	if (qp->av_valid && ud_same_route(&qp->av, &ah->attr.grh))
		return 0;
	if (qp->sq_producer != qp->sq_consumer)
		return EBUSY;
	attr.ah_attr = ah->attr;
	ret = ibv_cmd_modify_qp(&qp->ibv_qp, &attr, IBV_QP_AV, &command, sizeof(command));
	if (ret)
		return ret;
	qp->av = ah->attr.grh;
	qp->av_valid = true;
	return 0;
}

/* inline 载荷总长：RC 拼接全部 SGE；UD 只取 SGE[0]（SGE[1] 是接收侧 GRH 影子缓冲的约定，发送不带） */
static uint32_t inline_length(const struct ibv_send_wr *wr, bool is_ud)
{
	uint32_t total = 0;
	int i, n = is_ud ? (wr->num_sge ? 1 : 0) : wr->num_sge;

	for (i = 0; i < n; i++)
		total += wr->sg_list[i].length;
	return total;
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
		 * INLINE：WQE 里没有 inline 载荷区，由 provider 拷进本槽的跳板缓冲后按普通 SGE 下发
		 * （create_qp 没要 inline、超过 max_inline、或 RDMA READ 带 INLINE 都按 EINVAL 拒绝）。
		 * RC 的 inline 允许多 SGE：拷贝时已拼成一段。 */
		bool is_inline = wr->send_flags & IBV_SEND_INLINE;

		if (qp->sq_producer - qp->sq_consumer >= depth - 1) {
			ret = ENOMEM;
		} else if (opcode < 0) {
			ret = EINVAL;
		} else if (is_inline && (!qp->max_inline || wr->opcode == IBV_WR_RDMA_READ ||
					 inline_length(wr, is_ud) > qp->max_inline)) {
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
				ret = ud_set_destination(qp, wr->wr.ud.ah);
		} else if (wr->num_sge > 1 && !is_inline) {
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
		if (is_inline) {
			/* 拷进本槽跳板：槽在 sq_consumer 越过它之前不会被复用，硬件取数时内容稳定 */
			uint8_t *dst = qp->inline_buf + (size_t)slot * qp->inline_stride;
			uint32_t total = 0;
			int i, n = is_ud ? (wr->num_sge ? 1 : 0) : wr->num_sge;

			for (i = 0; i < n; i++) {
				memcpy(dst + total, (void *)(uintptr_t)wr->sg_list[i].addr, wr->sg_list[i].length);
				total += wr->sg_list[i].length;
			}
			wqe.length = total;
			wqe.lkey = qp->inline_mr->lkey;
			wqe.laddr = (uintptr_t)dst;
		} else if (wr->num_sge) {
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

/*
 * UD 接收缓冲的前 40 B 留给 GRH（IB 语义：不论报文带不带 GRH，UD 接收都从第一个 SGE 的
 * 第 40 字节起放载荷，wc.byte_len 含这 40 B；ud_pingpong / udaddy / perftest 都按
 * size + 40 申请缓冲）。RTL 把载荷写到 RQ WQE 的 addr 起，所以 UD 的 RQ WQE 下发
 * 「用户起址 + 40、长度 - 40」，GRH 区由 poll_cq 按 CQE 的 IPv4 信息合成（见 ud_write_grh）。
 */
#define YUANRDMA_UD_GRH_BYTES 40u

/*
 * RQ 门铃合并。门铃是 UC 写；逐个 post_recv 都敲时，下一次 post_recv 加锁（原子指令即全屏障）
 * 要等上一个门铃写走到设备才能往下走，补 RQ 的速度被钉在「每个 WQE 一次 MMIO 往返」上。
 * 一包一补的 UD 接收端（每个完成后立即 post_recv 一个）因此补不上线速，硬件收包时 RQ 已空。
 *
 * 规则（recv_lock 内判定）：
 *   - 未敲门铃的 WQE 攒到 YUANRDMA_RQ_DB_BATCH 个就敲；
 *   - 硬件手里的 WQE（rq_db_producer − rq_consumer，即已敲门铃减去已轮询到的接收完成）少于
 *     YUANRDMA_RQ_DB_LOW 时立即敲：浅 RQ、低速应用与逐个敲完全相同；
 *   - poll_cq 每次都把本 CQ 上各 QP 攒着的门铃补敲（rq_doorbell_flush）。
 * 这个差值只会高估硬件手里的 WQE（还没轮询到的完成仍算在硬件手里）：CQ 已轮询空时它就是实数，
 * 硬件至少还有 LOW 个 WQE；CQ 里还有完成时，应用要取完成就得 poll，攒着的门铃随之敲出。
 * 所以攒着的至多 BATCH − 1 个 WQE 不会被一直扣住，应用停止补 RQ 后最后几个也照样可用。
 */
#define YUANRDMA_RQ_DB_BATCH 16u
#define YUANRDMA_RQ_DB_LOW   64

/* 调用方持有 recv_lock */
static void rq_ring_doorbell(struct yuanrdma_context *context, struct yuanrdma_qp *qp)
{
	udma_to_device_barrier();		/* WQE 先于 doorbell 可见 */
	mmio_write32((uint32_t *)((char *)context->doorbell_page + YNRDMA_DB_RQ),
		     ((qp->rq_producer & 0xffff) << 16) | qp->qp_index);
	qp->rq_db_producer = qp->rq_producer;
}

/* poll_cq 调用：补敲 qp 攒着的 RQ 门铃。post_recv 正持锁时跳过，它自己按规则敲，剩下的留给下一次 poll */
static void rq_doorbell_flush(struct yuanrdma_context *context, struct yuanrdma_qp *qp)
{
	if (qp->rq_db_producer == qp->rq_producer)	/* 不持锁先看一眼：绝大多数时候没有攒着的 */
		return;
	if (pthread_spin_trylock(&qp->recv_lock))
		return;
	if (qp->rq_db_producer != qp->rq_producer)
		rq_ring_doorbell(context, qp);
	pthread_spin_unlock(&qp->recv_lock);
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
		if (qp->is_ud && wr->num_sge && wr->sg_list[0].length < YUANRDMA_UD_GRH_BYTES) {
			ret = EINVAL;		/* 放不下 GRH 区：IB 语义下这个缓冲收不了任何 UD 报文 */
			*bad_wr = wr;
			break;
		}
		if (wr->num_sge) {
			wqe.length = wr->sg_list[0].length;
			wqe.lkey = wr->sg_list[0].lkey;
			wqe.addr = wr->sg_list[0].addr;
		}
		if (qp->is_ud) {
			qp->rq_addr[slot] = wqe.addr;
			if (wr->num_sge) {
				wqe.addr += YUANRDMA_UD_GRH_BYTES;
				wqe.length -= YUANRDMA_UD_GRH_BYTES;
			}
		}
		memcpy(&qp->rq_ring[slot], &wqe, sizeof(wqe));
		qp->rq_wr_id[slot] = wr->wr_id;
		qp->rq_producer++;
		posted = true;
	}
	/* 门铃合并规则见 rq_ring_doorbell 上方。rq_consumer 由 poll_cq 在 cq->lock 下推进，这里读到的
	 * 可能偏旧（偏小），差值按有符号算：QP 出错后 flush_queue 会把 rq_consumer 推过 rq_db_producer。 */
	if (posted && (qp->rq_producer - qp->rq_db_producer >= YUANRDMA_RQ_DB_BATCH ||
		       (int32_t)(qp->rq_db_producer - qp->rq_consumer) < YUANRDMA_RQ_DB_LOW))
		rq_ring_doorbell(context, qp);
	pthread_spin_unlock(&qp->recv_lock);
	return ret;
}

/*
 * UD 接收的 GRH 合成。RoCEv2 线上没有 GRH，IB 语义却要求带 IBV_WC_GRH 的 UD 完成在接收缓冲
 * 前 40 B 放 GRH：ibv_create_ah_from_wc 从这里取对端地址造回包 AH（udaddy 的 create_reply_ah）。
 * 格式与 ConnectX 一致（2026-11-27 对端 gdb 实取）：前 20 B 为 0，后 20 B 是收到的 IPv4 头；
 * libibverbs 的 get_grh_header_version 见首字 version != 6 且 [20] 是 0x45 即按 IPv4 解析，
 * 用 daddr 查本端 GID 序号、saddr 作 dgid、ttl 作 hop_limit、tos 作 traffic_class。
 *
 * IPv4 信息来自 CQE dw5..dw7（RTL 在 UD 接收时填，并置 dw0[19]）。CQE 没带（老镜像）时
 * 不写 GRH、不置 IBV_WC_GRH——那样 create_ah_from_wc 会得到 is_global=0 的 AH，create_ah 拒绝，
 * 比编一个错的源地址强。
 */
static void ud_write_grh(uint8_t *grh, const struct ynrdma_cqe *cqe, uint32_t payload_length, bool has_imm)
{
	uint8_t *ip = grh + 20;
	uint32_t dw7 = le32toh(cqe->dw7);
	uint32_t total = 20 + 8 + 12 + 8 + (has_imm ? 4 : 0) + payload_length + ((0u - payload_length) & 3) + 4;
	uint32_t sum = 0;
	int i;

	memset(grh, 0, 20);
	ip[0] = 0x45;
	ip[1] = (dw7 >> 8) & 0xff;		/* TOS */
	ip[2] = total >> 8;
	ip[3] = total & 0xff;
	ip[4] = ip[5] = 0;
	ip[6] = 0x40;				/* DF */
	ip[7] = 0;
	ip[8] = dw7 & 0xff;			/* TTL */
	ip[9] = 17;				/* UDP */
	ip[10] = ip[11] = 0;
	memcpy(ip + 12, &cqe->src_ip, 4);	/* dw5/dw6 的内存字节序就是网络序 */
	memcpy(ip + 16, &cqe->dst_ip, 4);
	for (i = 0; i < 20; i += 2)
		sum += (ip[i] << 8) | ip[i + 1];
	while (sum >> 16)
		sum = (sum & 0xffff) + (sum >> 16);
	sum = ~sum & 0xffff;
	ip[10] = sum >> 8;
	ip[11] = sum & 0xff;
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
	struct yuanrdma_qp *rq_qp = NULL;	/* 本批最近一个出接收完成的 QP（补敲 RQ 门铃用） */
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
		if ((dw0 >> 17) & 1) {			/* 接收完成：RQ 按序 */
			slot = wqe_index & ((1u << qp->rq_log2_depth) - 1);
			wc[count].wr_id = qp->rq_wr_id[slot];
			/* UD：载荷落在用户缓冲 +40 处（post_recv 移过），byte_len 按 IB 语义含 40 B GRH 区；
			 * CQE 带了 IPv4 信息（dw0[19]）就合成 GRH。dw0[18] 是旧契约的「硬件已写 GRH」，
			 * 从没有镜像置过，现已废弃不读。 */
			if (qp->is_ud && wc[count].status == IBV_WC_SUCCESS) {
				wc[count].byte_len += YUANRDMA_UD_GRH_BYTES;
				if ((dw0 & YNRDMA_CQE_F_IPV4) && qp->rq_addr[slot]) {
					ud_write_grh((uint8_t *)(uintptr_t)qp->rq_addr[slot], cqe,
						     le32toh(cqe->byte_len), (dw0 >> 16) & 1);
					wc[count].wc_flags |= IBV_WC_GRH;
				}
			}
			qp->rq_consumer++;
			if (rq_qp != qp) {		/* 换了 QP：上一个 QP 攒着的 RQ 门铃先补敲 */
				if (rq_qp)
					rq_doorbell_flush(context, rq_qp);
				rq_qp = qp;
			}
		} else {				/* 发送完成：之前未 signaled 的 WQE 一并退休 */
			slot = wqe_index & ((1u << qp->sq_log2_depth) - 1);
			wc[count].wr_id = qp->sq_wr_id[slot];
			qp->sq_consumer += ((slot - qp->sq_consumer) & ((1u << qp->sq_log2_depth) - 1)) + 1;
		}
		if (wc[count].status != IBV_WC_SUCCESS)
			qp->error = true;
		count++;
	}
	if (rq_qp)
		rq_doorbell_flush(context, rq_qp);
	/* 没取满说明 CQ 已经轮询空：出错的 QP 其余 WQE 冲刷；以本 CQ 为 recv_cq 的 QP 攒着的 RQ 门铃
	 * 全部补敲（取满时只补了本批出现过的 QP，其余的等 CQ 轮询空这一次）。 */
	if (count < entries) {
		for (qp_index = 0; qp_index < YNRDMA_MAX_QP; qp_index++) {
			struct yuanrdma_qp *qp = context->qp_table[qp_index];

			if (!qp)
				continue;
			if (qp->error && count < entries)
				count += flush_queue(qp, qp->ibv_qp.send_cq == ibv_cq, qp->ibv_qp.recv_cq == ibv_cq,
						     entries - count, &wc[count]);
			if (qp->ibv_qp.recv_cq == ibv_cq)
				rq_doorbell_flush(context, qp);
		}
	}
	if (count)
		mmio_write32((uint32_t *)((char *)context->doorbell_page + YNRDMA_DB_CQ),
			     ((cq->consumer & 0xffff) << 16) | cq->cq_index);
	pthread_spin_unlock(&cq->lock);
	return count;
}
