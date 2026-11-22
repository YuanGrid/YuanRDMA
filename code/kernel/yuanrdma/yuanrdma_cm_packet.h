/* SPDX-License-Identifier: GPL-2.0 OR BSD-2-Clause */
/*
 * yuanrdma_cm_pkt.h - RoCE CM（rdma_cm 用的 IB_MGMT_CLASS_CM MAD）报文编解码。
 *
 * 为什么驱动里要有一份 CM MAD 编解码
 *   CM 的语义（listen / REQ→REP→RTU / DREQ→DREP）由内核 ib_cm（drivers/infiniband/core/cm.c）
 *   与 rdma_cm（cma.c）负责，**驱动不参与**：ib_cm 在 QP1 上注册 MAD agent，收到 MAD 后按
 *   attr_id 分发（cm.c:4031-4058），驱动只搬 256 B 不透明载荷（cm.c 全程不调 ib_create_qp）。
 *   驱动侧需要这份编解码的地方只有两处：
 *     1) 收包侧做最小校验与分类（class / class_version / method / attr_id / tid），把坏 MAD
 *        挡在 MAD 层之前，并按 attr_id 计数 —— 上板时一眼看出「REQ 到底有没有到」；
 *     2) 单测（test/sw/gsi_pkt/test_cm_mad.py）在没有板子、没有内核 CM 栈的情况下逐字节验证
 *        我们送上 QP1 的 256 B 与 IBTA 表 106/110/111/112 一致。
 *   所以这里只做**报文层**：不持状态、不发包、不认识连接。
 *
 * 偏移从哪来
 *   不是手抄 IB 规范，而是用 ibta_vol1_c12.h 的 CM_FIELD*_LOC 宏机械展开得到
 *   （test/sw/gsi_pkt/cm_layout.py 把同一套展开再实现一遍，单测拿它对拍）。
 *   展开规则：BASE = byte_offset + 24（MAD 头长度）；16/32 位字段先按自然对齐回退到
 *   &0xFFFC/&0xFFFE，再按 (byte_offset % 4) 定位到 MSB，shift = 尾部零的个数。
 *   注意 24 位字段（qpn/eecn/psn）落在 32 位字的**高 24 位**，所以 shift = 8 而不是 0。
 *
 * MAD 头（24 B，ib_mad_hdr，全部大端）：
 *   [0] base_version=1 | [1] mgmt_class=0x07(CM) | [2] class_version=2 | [3] method=0x03(SEND)
 *   [4..5] status | [6..7] class_specific | [8..15] tid | [16..17] attr_id
 *   [18..19] resv | [20..23] attr_mod（REQ/REP 的 ECE 码放这里）
 *
 * 各消息的数据区（MAD 字节偏移，本文全部按 MAD 起点算）：
 *
 *   REQ（attr 0x0010，表 106）
 *     28 vendor_id u24 | 32 service_id u64 | 40 local_ca_guid u64 | 52 local_q_key u32
 *     56 local_qpn u24(shift8) | 59 responder_resources | 60 local_eecn u24(shift8)
 *     63 initiator_depth | 64 remote_eecn u24(shift8)
 *     67 remote_cm_response_timeout u5[7:3] | transport_service_type u2[2:1] | e2e_fc u1[0]
 *     68 starting_psn u24(shift8)
 *     71 local_cm_response_timeout u5[7:3] | retry_count u3[2:0]
 *     72 pkey u16
 *     74 path_mtu u4[7:4] | rdc_exists u1[3] | rnr_retry_count u3[2:0]
 *     75 max_cm_retries u4[7:4] | srq u1[3] | extended_transport_type u3[2:0]
 *     76 primary_local_lid u16 | 78 primary_remote_lid u16
 *     80 primary_local_gid 16 B | 96 primary_remote_gid 16 B
 *     112 primary_flow_label u20 (32 位字的高 20 位，shift 12)
 *     115 primary_packet_rate u6 | 116 traffic_class | 117 hop_limit
 *     118 primary_sl u4[7:4] | subnet_local u1[3] | 119 local_ack_timeout u5[7:3]
 *     156..163 alternate path（本驱动不填） | 163 sap_supported u1[2]
 *     164 private_data 92 B
 *
 *   REP（attr 0x0013，表 110）
 *     32 local_q_key u32 | 36 local_qpn u24(shift8, 占 37..39)
 *     39 vendor_id_h | 40 local_eecn u24(shift8, 占 41..43) | 43 vendor_id_m
 *     44 starting_psn u24(shift8, 占 45..47) | 47 vendor_id_l
 *     48 responder_resources | 49 initiator_depth
 *     50 target_ack_delay u5[7:3] | failover_accepted u2[2:1] | e2e_fc u1[0]
 *     51 rnr_retry_count u3[7:5] | srq u1[4]
 *     52 local_ca_guid u64 | 60 private_data 196 B
 *
 *   RTU（attr 0x0014，表 111）：32 private_data 224 B
 *   DREQ（attr 0x0015，表 112）：32 remote_qpn_eecn u24(shift8, 占 33..35) | 36 private_data 220 B
 *
 * 全部四种消息的 private_data 都恰好填到 MAD 末尾（164+92 = 60+196 = 32+224 = 36+220 = 256）。
 *
 * 驱动实际用到 REQ/REP/RTU/DREQ 四种；MRA/REJ/DREP 只做 attr_id 识别与计数（ib_cm 自己发）。
 */
#ifndef YUANRDMA_CM_PKT_H
#define YUANRDMA_CM_PKT_H

#ifdef __KERNEL__
#include <linux/types.h>
#include <linux/string.h>
#else
#include <stdint.h>
#include <stddef.h>
#include <string.h>
typedef uint8_t u8;
typedef uint16_t u16;
typedef uint32_t u32;
typedef uint64_t u64;
#endif

#include "yuanrdma_gsi_packet.h"	/* 复用 fgsi_put16/put24/put32 与 get 系列 */

#define FGCM_MAD_HDR_LEN	24
#define FGCM_MAD_DATA_LEN	232
#define FGCM_MAD_LEN		(FGCM_MAD_HDR_LEN + FGCM_MAD_DATA_LEN)	/* 256 */

/* MAD 头常量（与 ib_mad.h 一致；不复用内核头是为了用户态单测能编） */
#define FGCM_BASE_VERSION	1
#define FGCM_MGMT_CLASS_CM	0x07
#define FGCM_CLASS_VERSION	2		/* IB_CM_CLASS_VERSION */
#define FGCM_METHOD_SEND	0x03		/* IB_MGMT_METHOD_SEND */

/* CM attr_id（ib_cm.h:261-271） */
#define FGCM_ATTR_REQ		0x0010
#define FGCM_ATTR_MRA		0x0011
#define FGCM_ATTR_REJ		0x0012
#define FGCM_ATTR_REP		0x0013
#define FGCM_ATTR_RTU		0x0014
#define FGCM_ATTR_DREQ		0x0015
#define FGCM_ATTR_DREP		0x0016
#define FGCM_ATTR_SIDR_REQ	0x0017
#define FGCM_ATTR_SIDR_REP	0x0018
#define FGCM_ATTR_LAP		0x0019
#define FGCM_ATTR_APR		0x001a

/* private_data 起点与长度（相对 MAD 起点） */
#define FGCM_REQ_PRIVATE_OFFSET		164
#define FGCM_REQ_PRIVATE_LEN		92
#define FGCM_REP_PRIVATE_OFFSET		60
#define FGCM_REP_PRIVATE_LEN		196
#define FGCM_RTU_PRIVATE_OFFSET		32
#define FGCM_RTU_PRIVATE_LEN		224
#define FGCM_DREQ_PRIVATE_OFFSET	36
#define FGCM_DREQ_PRIVATE_LEN		220

/* 解析错误码（负值），与 FGSI_ERR_* 错开但不共享类型 */
#define FGCM_ERR_SHORT		(-11)	/* 不足 256 B */
#define FGCM_ERR_NOT_CM		(-12)	/* mgmt_class 不是 0x07 或 method 不是 SEND */
#define FGCM_ERR_CLASS_VERSION	(-13)	/* class_version 不是 2 */
#define FGCM_ERR_ATTR		(-14)	/* attr_id 与调用的 decode 不符 */

/* CM 公共头视图 */
struct fgcm_hdr {
	u16 attr_id;
	u64 tid;
	u32 attr_mod;
};

/*
 * 语义字段。多字节网络序量（comm_id/tid/service_id/guid/gid）按字节数组存，
 * 免得在主机序上来回转；标量字段存主机序。
 */
struct fgcm_req {
	u32 local_comm_id;
	u8 service_id[8];
	u8 local_ca_guid[8];
	u32 local_q_key;
	u32 local_qpn;
	u8 responder_resources;
	u32 local_eecn;
	u8 initiator_depth;
	u32 remote_eecn;
	u8 remote_cm_response_timeout;
	u8 transport_service_type;		/* 0=RC 1=UC 3=XRC */
	u8 end_to_end_flow_control;
	u32 starting_psn;
	u8 local_cm_response_timeout;
	u8 retry_count;
	u16 pkey;
	u8 path_mtu;				/* IB_MTU_* 枚举 */
	u8 rdc_exists;
	u8 rnr_retry_count;
	u8 max_cm_retries;
	u8 srq;
	u8 extended_transport_type;
	u16 primary_local_lid;
	u16 primary_remote_lid;
	u8 primary_local_gid[16];
	u8 primary_remote_gid[16];
	u32 primary_flow_label;			/* 20 bit */
	u8 primary_packet_rate;
	u8 primary_traffic_class;
	u8 primary_hop_limit;
	u8 primary_sl;
	u8 primary_subnet_local;
	u8 local_ack_timeout;
	u8 sap_supported;
	u8 private_data[FGCM_REQ_PRIVATE_LEN];
};

struct fgcm_rep {
	u32 local_comm_id;
	u32 remote_comm_id;
	u32 local_q_key;
	u32 local_qpn;
	u32 local_eecn;
	u32 starting_psn;
	u8 responder_resources;
	u8 initiator_depth;
	u8 target_ack_delay;
	u8 failover_accepted;
	u8 end_to_end_flow_control;
	u8 rnr_retry_count;
	u8 srq;
	u8 local_ca_guid[8];
	u8 private_data[FGCM_REP_PRIVATE_LEN];
};

struct fgcm_rtu {
	u32 local_comm_id;
	u32 remote_comm_id;
	u8 private_data[FGCM_RTU_PRIVATE_LEN];
};

struct fgcm_dreq {
	u32 local_comm_id;
	u32 remote_comm_id;
	u32 remote_qpn_eecn;
	u8 private_data[FGCM_DREQ_PRIVATE_LEN];
};

/* ---------------------------------------------------------------- 头 */
static inline void fgcm_put_bytes(u8 *dst, const u8 *src, size_t n)
{
	memcpy(dst, src, n);
}

/* 写 24 B MAD 头；status/class_specific/resv 清零，attr_mod 由 _ece 版本填 */
static inline void fgcm_put_hdr(u8 *mad, u16 attr_id, u64 tid, u32 attr_mod)
{
	memset(mad, 0, FGCM_MAD_HDR_LEN);
	mad[0] = FGCM_BASE_VERSION;
	mad[1] = FGCM_MGMT_CLASS_CM;
	mad[2] = FGCM_CLASS_VERSION;
	mad[3] = FGCM_METHOD_SEND;
	fgsi_put32(mad + 8, (u32)(tid >> 32));
	fgsi_put32(mad + 12, (u32)tid);
	fgsi_put16(mad + 16, attr_id);
	fgsi_put32(mad + 20, attr_mod);
}

/* 校验 MAD 头并取出 attr_id/tid/attr_mod。成功返回 0。 */
static inline int fgcm_get_hdr(const u8 *mad, size_t length, struct fgcm_hdr *h)
{
	if (length < FGCM_MAD_LEN)
		return FGCM_ERR_SHORT;
	if (mad[1] != FGCM_MGMT_CLASS_CM || mad[3] != FGCM_METHOD_SEND)
		return FGCM_ERR_NOT_CM;
	if (mad[2] != FGCM_CLASS_VERSION)
		return FGCM_ERR_CLASS_VERSION;
	memset(h, 0, sizeof(*h));
	h->attr_id = (u16)fgsi_get16(mad + 16);
	h->tid = ((u64)fgsi_get32(mad + 8) << 32) | fgsi_get32(mad + 12);
	h->attr_mod = fgsi_get32(mad + 20);
	return 0;
}

/*
 * 分类：返回 attr_id（>= 0x10），或负的 FGCM_ERR_*，或 -1（CM 类但不是我们列出的 attr）。
 * 收包路径用它按 attr_id 计数，不解析字段。
 */
static inline int fgcm_classify(const u8 *mad, size_t length)
{
	struct fgcm_hdr h;
	int rc;

	rc = fgcm_get_hdr(mad, length, &h);
	if (rc)
		return rc;
	switch (h.attr_id) {
	case FGCM_ATTR_REQ:
	case FGCM_ATTR_MRA:
	case FGCM_ATTR_REJ:
	case FGCM_ATTR_REP:
	case FGCM_ATTR_RTU:
	case FGCM_ATTR_DREQ:
	case FGCM_ATTR_DREP:
	case FGCM_ATTR_SIDR_REQ:
	case FGCM_ATTR_SIDR_REP:
	case FGCM_ATTR_LAP:
	case FGCM_ATTR_APR:
		return h.attr_id;
	default:
		return -1;
	}
}

/* 32 位字里「高 width 位」的读写：掩码与 shift 与 ibta_vol1_c12.h 展开一致 */
#define FGCM_WORD(p)		fgsi_get32(p)
#define FGCM_PUT_WORD(p, v)	fgsi_put32((p), (v))

/* ---------------------------------------------------------------- REQ */
static inline size_t fgcm_req_encode(u8 *mad, const struct fgcm_hdr *h, const struct fgcm_req *r)
{
	/* **必须先清零整张 MAD**：下面的字段只覆盖了 REQ 的一部分字节，
	 * 其余（alternate path 的 mad[120..162]、vendor_id 的高字节等）如果不清零，
	 * 发出去的就是内核栈残留（信息泄露），对端 ib_cm 还会读到垃圾 alternate LID/GID。
	 * 单测用的缓冲恰好是全 0 的 create_string_buffer，所以以前一直没暴露。 */
	memset(mad, 0, FGCM_MAD_LEN);
	fgcm_put_hdr(mad, FGCM_ATTR_REQ, h->tid, h->attr_mod);

	fgsi_put32(mad + 24, r->local_comm_id);
	/* vendor_id 是 u24 放在**大端字的高 24 位**：内核展开 CM_REQ_VENDOR_ID 是
	 * CM_FIELD32_LOC(5, 24) → base=(5+24)&0xFFFC=28、mask=0x00FFFFFF、shift=0，
	 * 即占 mad[29..31]。原来写 mad+28 会落到 [28..30]，mad[31] 漏写。 */
	fgsi_put24(mad + 29, 0);
	fgcm_put_bytes(mad + 32, r->service_id, 8);
	fgcm_put_bytes(mad + 40, r->local_ca_guid, 8);
	fgsi_put32(mad + 52, r->local_q_key);
	fgsi_put32(mad + 56, (r->local_qpn & 0xffffff) << 8);	/* u24 在字的高 24 位 */
	mad[59] = r->responder_resources;
	fgsi_put32(mad + 60, (r->local_eecn & 0xffffff) << 8);
	mad[63] = r->initiator_depth;
	fgsi_put32(mad + 64, (r->remote_eecn & 0xffffff) << 8);
	mad[67] = (u8)(((r->remote_cm_response_timeout & 0x1f) << 3) |
		       ((r->transport_service_type & 0x3) << 1) |
		       (r->end_to_end_flow_control & 1));
	fgsi_put32(mad + 68, (r->starting_psn & 0xffffff) << 8);
	mad[71] = (u8)(((r->local_cm_response_timeout & 0x1f) << 3) |
		       (r->retry_count & 0x7));
	fgsi_put16(mad + 72, r->pkey);
	mad[74] = (u8)(((r->path_mtu & 0xf) << 4) |
		       ((r->rdc_exists & 1) << 3) |
		       (r->rnr_retry_count & 0x7));
	mad[75] = (u8)(((r->max_cm_retries & 0xf) << 4) |
		       ((r->srq & 1) << 3) |
		       (r->extended_transport_type & 0x7));
	fgsi_put16(mad + 76, r->primary_local_lid);
	fgsi_put16(mad + 78, r->primary_remote_lid);
	fgcm_put_bytes(mad + 80, r->primary_local_gid, 16);
	fgcm_put_bytes(mad + 96, r->primary_remote_gid, 16);
	fgsi_put32(mad + 112, (r->primary_flow_label & 0xfffff) << 12);
	mad[115] = (u8)(r->primary_packet_rate & 0x3f);
	mad[116] = r->primary_traffic_class;
	mad[117] = r->primary_hop_limit;
	mad[118] = (u8)(((r->primary_sl & 0xf) << 4) |
			((r->primary_subnet_local & 1) << 3));
	mad[119] = (u8)((r->local_ack_timeout & 0x1f) << 3);
	/* alternate path（mad[120..162]）保持 0：上面的 memset 已经清零，本驱动不做 failover。
	 * 注意范围是 [120,162] 而不是这里以前写的「156..162」——alternate 段从 120 开始。 */
	mad[163] = (u8)((r->sap_supported & 1) << 2);
	fgcm_put_bytes(mad + FGCM_REQ_PRIVATE_OFFSET, r->private_data, FGCM_REQ_PRIVATE_LEN);
	return FGCM_MAD_LEN;
}

static inline int fgcm_req_decode(const u8 *mad, size_t length, struct fgcm_req *r)
{
	struct fgcm_hdr h;
	int rc;

	rc = fgcm_get_hdr(mad, length, &h);
	if (rc)
		return rc;
	if (h.attr_id != FGCM_ATTR_REQ)
		return FGCM_ERR_ATTR;
	memset(r, 0, sizeof(*r));
	r->local_comm_id = fgsi_get32(mad + 24);
	fgcm_put_bytes(r->service_id, mad + 32, 8);
	fgcm_put_bytes(r->local_ca_guid, mad + 40, 8);
	r->local_q_key = fgsi_get32(mad + 52);
	r->local_qpn = (fgsi_get32(mad + 56) >> 8) & 0xffffff;
	r->responder_resources = mad[59];
	r->local_eecn = (fgsi_get32(mad + 60) >> 8) & 0xffffff;
	r->initiator_depth = mad[63];
	r->remote_eecn = (fgsi_get32(mad + 64) >> 8) & 0xffffff;
	r->remote_cm_response_timeout = (u8)((mad[67] >> 3) & 0x1f);
	r->transport_service_type = (u8)((mad[67] >> 1) & 0x3);
	r->end_to_end_flow_control = (u8)(mad[67] & 1);
	r->starting_psn = (fgsi_get32(mad + 68) >> 8) & 0xffffff;
	r->local_cm_response_timeout = (u8)((mad[71] >> 3) & 0x1f);
	r->retry_count = (u8)(mad[71] & 0x7);
	r->pkey = (u16)fgsi_get16(mad + 72);
	r->path_mtu = (u8)((mad[74] >> 4) & 0xf);
	r->rdc_exists = (u8)((mad[74] >> 3) & 1);
	r->rnr_retry_count = (u8)(mad[74] & 0x7);
	r->max_cm_retries = (u8)((mad[75] >> 4) & 0xf);
	r->srq = (u8)((mad[75] >> 3) & 1);
	r->extended_transport_type = (u8)(mad[75] & 0x7);
	r->primary_local_lid = (u16)fgsi_get16(mad + 76);
	r->primary_remote_lid = (u16)fgsi_get16(mad + 78);
	fgcm_put_bytes(r->primary_local_gid, mad + 80, 16);
	fgcm_put_bytes(r->primary_remote_gid, mad + 96, 16);
	r->primary_flow_label = (fgsi_get32(mad + 112) >> 12) & 0xfffff;
	r->primary_packet_rate = (u8)(mad[115] & 0x3f);
	r->primary_traffic_class = mad[116];
	r->primary_hop_limit = mad[117];
	r->primary_sl = (u8)((mad[118] >> 4) & 0xf);
	r->primary_subnet_local = (u8)((mad[118] >> 3) & 1);
	r->local_ack_timeout = (u8)((mad[119] >> 3) & 0x1f);
	r->sap_supported = (u8)((mad[163] >> 2) & 1);
	fgcm_put_bytes(r->private_data, mad + FGCM_REQ_PRIVATE_OFFSET, FGCM_REQ_PRIVATE_LEN);
	return 0;
}

/* ---------------------------------------------------------------- REP */
static inline size_t fgcm_rep_encode(u8 *mad, const struct fgcm_hdr *h, const struct fgcm_rep *r)
{
	memset(mad, 0, FGCM_MAD_LEN);	/* 同 REQ：未写到的字节必须是 0，不能是内核栈残留 */
	fgcm_put_hdr(mad, FGCM_ATTR_REP, h->tid, h->attr_mod);

	fgsi_put32(mad + 24, r->local_comm_id);
	fgsi_put32(mad + 28, r->remote_comm_id);
	fgsi_put32(mad + 32, r->local_q_key);
	fgsi_put32(mad + 36, (r->local_qpn & 0xffffff) << 8);
	mad[39] = 0;					/* vendor_id_h */
	fgsi_put32(mad + 40, (r->local_eecn & 0xffffff) << 8);
	mad[43] = 0;					/* vendor_id_m */
	fgsi_put32(mad + 44, (r->starting_psn & 0xffffff) << 8);
	mad[47] = 0;					/* vendor_id_l */
	mad[48] = r->responder_resources;
	mad[49] = r->initiator_depth;
	mad[50] = (u8)(((r->target_ack_delay & 0x1f) << 3) |
		       ((r->failover_accepted & 0x3) << 1) |
		       (r->end_to_end_flow_control & 1));
	mad[51] = (u8)(((r->rnr_retry_count & 0x7) << 5) | ((r->srq & 1) << 4));
	fgcm_put_bytes(mad + 52, r->local_ca_guid, 8);
	fgcm_put_bytes(mad + FGCM_REP_PRIVATE_OFFSET, r->private_data, FGCM_REP_PRIVATE_LEN);
	return FGCM_MAD_LEN;
}

static inline int fgcm_rep_decode(const u8 *mad, size_t length, struct fgcm_rep *r)
{
	struct fgcm_hdr h;
	int rc;

	rc = fgcm_get_hdr(mad, length, &h);
	if (rc)
		return rc;
	if (h.attr_id != FGCM_ATTR_REP)
		return FGCM_ERR_ATTR;
	memset(r, 0, sizeof(*r));
	r->local_comm_id = fgsi_get32(mad + 24);
	r->remote_comm_id = fgsi_get32(mad + 28);
	r->local_q_key = fgsi_get32(mad + 32);
	r->local_qpn = (fgsi_get32(mad + 36) >> 8) & 0xffffff;
	r->local_eecn = (fgsi_get32(mad + 40) >> 8) & 0xffffff;
	r->starting_psn = (fgsi_get32(mad + 44) >> 8) & 0xffffff;
	r->responder_resources = mad[48];
	r->initiator_depth = mad[49];
	r->target_ack_delay = (u8)((mad[50] >> 3) & 0x1f);
	r->failover_accepted = (u8)((mad[50] >> 1) & 0x3);
	r->end_to_end_flow_control = (u8)(mad[50] & 1);
	r->rnr_retry_count = (u8)((mad[51] >> 5) & 0x7);
	r->srq = (u8)((mad[51] >> 4) & 1);
	fgcm_put_bytes(r->local_ca_guid, mad + 52, 8);
	fgcm_put_bytes(r->private_data, mad + FGCM_REP_PRIVATE_OFFSET, FGCM_REP_PRIVATE_LEN);
	return 0;
}

/* ---------------------------------------------------------------- RTU */
static inline size_t fgcm_rtu_encode(u8 *mad, const struct fgcm_hdr *h, const struct fgcm_rtu *r)
{
	memset(mad, 0, FGCM_MAD_LEN);	/* 同 REQ：未写到的字节必须是 0，不能是内核栈残留 */
	fgcm_put_hdr(mad, FGCM_ATTR_RTU, h->tid, h->attr_mod);
	fgsi_put32(mad + 24, r->local_comm_id);
	fgsi_put32(mad + 28, r->remote_comm_id);
	fgcm_put_bytes(mad + FGCM_RTU_PRIVATE_OFFSET, r->private_data, FGCM_RTU_PRIVATE_LEN);
	return FGCM_MAD_LEN;
}

static inline int fgcm_rtu_decode(const u8 *mad, size_t length, struct fgcm_rtu *r)
{
	struct fgcm_hdr h;
	int rc;

	rc = fgcm_get_hdr(mad, length, &h);
	if (rc)
		return rc;
	if (h.attr_id != FGCM_ATTR_RTU)
		return FGCM_ERR_ATTR;
	memset(r, 0, sizeof(*r));
	r->local_comm_id = fgsi_get32(mad + 24);
	r->remote_comm_id = fgsi_get32(mad + 28);
	fgcm_put_bytes(r->private_data, mad + FGCM_RTU_PRIVATE_OFFSET, FGCM_RTU_PRIVATE_LEN);
	return 0;
}

/* ---------------------------------------------------------------- DREQ */
static inline size_t fgcm_dreq_encode(u8 *mad, const struct fgcm_hdr *h, const struct fgcm_dreq *r)
{
	memset(mad, 0, FGCM_MAD_LEN);	/* 同 REQ：未写到的字节必须是 0，不能是内核栈残留 */
	fgcm_put_hdr(mad, FGCM_ATTR_DREQ, h->tid, h->attr_mod);
	fgsi_put32(mad + 24, r->local_comm_id);
	fgsi_put32(mad + 28, r->remote_comm_id);
	fgsi_put32(mad + 32, (r->remote_qpn_eecn & 0xffffff) << 8);
	fgcm_put_bytes(mad + FGCM_DREQ_PRIVATE_OFFSET, r->private_data, FGCM_DREQ_PRIVATE_LEN);
	return FGCM_MAD_LEN;
}

static inline int fgcm_dreq_decode(const u8 *mad, size_t length, struct fgcm_dreq *r)
{
	struct fgcm_hdr h;
	int rc;

	rc = fgcm_get_hdr(mad, length, &h);
	if (rc)
		return rc;
	if (h.attr_id != FGCM_ATTR_DREQ)
		return FGCM_ERR_ATTR;
	memset(r, 0, sizeof(*r));
	r->local_comm_id = fgsi_get32(mad + 24);
	r->remote_comm_id = fgsi_get32(mad + 28);
	r->remote_qpn_eecn = (fgsi_get32(mad + 32) >> 8) & 0xffffff;
	fgcm_put_bytes(r->private_data, mad + FGCM_DREQ_PRIVATE_OFFSET, FGCM_DREQ_PRIVATE_LEN);
	return 0;
}

/*
 * 把 256 B MAD 装进 QP1 的 GSI 帧（Eth/IP/UDP/BTH/DETH + MAD + ICRC）。
 * ib_cm 用「24 B 头 + 232 B 数据」两个 SGE 交下来，线上是一段连续 256 B；
 * 256 是 4 的倍数所以 pad 恒为 0，整帧 14+20+8+12+8+256+4 = 322 B。
 * 返回整帧长度（>0），容量不够返回 0。
 */
static inline size_t fgcm_to_gsi_frame(u8 *frame, size_t capacity, const struct fgsi_tx *t,
				       const u8 *mad)
{
	size_t total = fgsi_frame_length(t->opcode, FGCM_MAD_LEN);

	if (total > capacity)
		return 0;
	fgsi_build_headers(frame, t, FGCM_MAD_LEN);
	memcpy(frame + fgsi_header_length(t->opcode), mad, FGCM_MAD_LEN);
	fgsi_seal(frame, total);
	return total;
}

#endif /* YUANRDMA_CM_PKT_H */
