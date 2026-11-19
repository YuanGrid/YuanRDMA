/* SPDX-License-Identifier: GPL-2.0 OR BSD-2-Clause */
/*
 * yuanrdma_gsi_pkt.h - 软件 GSI（QP1）用的 RoCEv2 UD 报文组装 / 解析 / ICRC。
 *
 * QP1 不经过 RoCE 引擎：发方向由驱动组好整帧经 yuanmcdma 的 netdev 发出，收方向在
 * netdev 的 UDP 4791 上截获（引擎同时也会看到这些帧，见 yuanrdma_gsi.c 文件头）。
 * 这里只放纯函数、只操作字节缓冲，内核与用户态单测（test/sw/gsi_pkt）共用同一份，
 * 单测拿它和 test/sim/common/roce_pkt.py（已与 scapy 交叉验证）逐字节比对。
 *
 * 帧格式（IPv4、无 VLAN、无 IP 选项）：
 *   Eth 14 | IPv4 20 | UDP 8 (dport 4791, csum 0) | BTH 12 | DETH 8 | [ImmDt 4] |
 *   payload | pad 0..3 | ICRC 4
 * ICRC 按 IBTA A17.8：8 字节 0xff（LRH 占位）+ 屏蔽后的 IP/UDP/BTH + 其余字节做 CRC32，
 * 屏蔽 TOS、TTL、IP 校验和、UDP 校验和、BTH resv8a；线上按小端放 ~crc。
 */
#ifndef YUANRDMA_GSI_PKT_H
#define YUANRDMA_GSI_PKT_H

#ifdef __KERNEL__
#include <linux/types.h>
#include <linux/string.h>
#include <linux/crc32.h>
#define fgsi_crc32_le(crc, p, len) crc32_le(crc, p, len)
/* 内核里这两个函数各自带一块 52 B 的栈缓冲，内联进调用者再加 ~1.4 KB 局部变量会超过
 * 内核默认 1 KB 栈帧告警线（发方向在 workqueue、收方向在 softirq，见 yuanrdma_gsi.c）。
 * 让它们各自成函数，帧就被拆开；用户态单测不需要，保持内联。
 * 写法是 inline 的位置而不是返回值前面，内核自己的 noinline（compiler_attributes.h）同义。 */
#ifndef noinline
#define noinline __attribute__((noinline))
#endif
#define fgsi_noinline inline
#else
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#define fgsi_noinline
typedef uint8_t u8;
typedef uint16_t u16;
typedef uint32_t u32;
/* 与内核 crc32_le 同语义：反射多项式 0xedb88320，不做前后取反 */
static inline u32 fgsi_crc32_le(u32 crc, const u8 *p, size_t len)
{
	int bit;

	while (len--) {
		crc ^= *p++;
		for (bit = 0; bit < 8; bit++)
			crc = (crc >> 1) ^ (0xedb88320u & (0u - (crc & 1u)));
	}
	return crc;
}
#endif

#define FGSI_ETH_LEN		14
#define FGSI_IP_LEN		20
#define FGSI_UDP_LEN		8
#define FGSI_BTH_LEN		12
#define FGSI_DETH_LEN		8
#define FGSI_IMM_LEN		4
#define FGSI_ICRC_LEN		4
#define FGSI_L3_HDR_LEN		(FGSI_IP_LEN + FGSI_UDP_LEN + FGSI_BTH_LEN)	/* ICRC 屏蔽区 */
#define FGSI_ROCE_UDP_PORT	4791
#define FGSI_ETHERTYPE_IPV4	0x0800

#define FGSI_OP_UD_SEND_ONLY		0x64
#define FGSI_OP_UD_SEND_ONLY_IMM	0x65
#define FGSI_GSI_QKEY			0x80010000u

/* 解析错误码（负值），驱动按它分别计数 */
#define FGSI_ERR_SHORT		(-1)	/* 长度不够 / IP 总长与缓冲不符 */
#define FGSI_ERR_NOT_ROCE	(-2)	/* 不是 IPv4 无选项 + UDP 4791 */
#define FGSI_ERR_OPCODE		(-3)	/* 不是 UD SEND_ONLY[_IMM] */
#define FGSI_ERR_ICRC		(-4)	/* ICRC 不对 */

struct fgsi_tx {
	u8 dmac[6];
	u8 smac[6];
	u8 sip[4];		/* 网络序 */
	u8 dip[4];
	u8 tos;
	u8 ttl;
	u16 ip_id;
	u16 sport;		/* UDP 源端口（RoCEv2 用作 ECMP 熵） */
	u8 opcode;		/* FGSI_OP_UD_SEND_ONLY / _IMM */
	u8 solicited;
	u16 pkey;
	u32 dqpn;
	u32 psn;
	u32 qkey;
	u32 sqpn;
	u8 imm[4];		/* ImmDt 原样（ib_send_wr.ex.imm_data 已是网络序） */
};

struct fgsi_rx {
	u8 sip[4];
	u8 dip[4];
	u8 tos;
	u8 ttl;
	u16 sport;
	u8 opcode;
	u8 solicited;
	u16 pkey;
	u32 dqpn;
	u32 psn;
	u32 qkey;
	u32 sqpn;
	u8 imm[4];
	u32 payload_offset;	/* 相对 IP 头 */
	u32 payload_length;	/* 不含 pad 与 ICRC */
};

static inline void fgsi_put16(u8 *p, u32 v)
{
	p[0] = (u8)(v >> 8);
	p[1] = (u8)v;
}

static inline void fgsi_put24(u8 *p, u32 v)
{
	p[0] = (u8)(v >> 16);
	p[1] = (u8)(v >> 8);
	p[2] = (u8)v;
}

static inline void fgsi_put32(u8 *p, u32 v)
{
	p[0] = (u8)(v >> 24);
	p[1] = (u8)(v >> 16);
	p[2] = (u8)(v >> 8);
	p[3] = (u8)v;
}

static inline u32 fgsi_get16(const u8 *p)
{
	return ((u32)p[0] << 8) | p[1];
}

static inline u32 fgsi_get24(const u8 *p)
{
	return ((u32)p[0] << 16) | ((u32)p[1] << 8) | p[2];
}

static inline u32 fgsi_get32(const u8 *p)
{
	return ((u32)p[0] << 24) | ((u32)p[1] << 16) | ((u32)p[2] << 8) | p[3];
}

static inline int fgsi_has_imm(u8 opcode)
{
	return opcode == FGSI_OP_UD_SEND_ONLY_IMM;
}

static inline u32 fgsi_pad(size_t payload_length)
{
	return (u32)((4 - (payload_length & 3)) & 3);
}

/* Eth 头到 payload 起点的字节数 */
static inline size_t fgsi_header_length(u8 opcode)
{
	return FGSI_ETH_LEN + FGSI_L3_HDR_LEN + FGSI_DETH_LEN + (fgsi_has_imm(opcode) ? FGSI_IMM_LEN : 0);
}

static inline size_t fgsi_frame_length(u8 opcode, size_t payload_length)
{
	return fgsi_header_length(opcode) + payload_length + fgsi_pad(payload_length) + FGSI_ICRC_LEN;
}

static inline u16 fgsi_ip_checksum(const u8 *header)
{
	u32 sum = 0;
	int i;

	for (i = 0; i < FGSI_IP_LEN; i += 2)
		sum += fgsi_get16(header + i);
	while (sum >> 16)
		sum = (sum & 0xffff) + (sum >> 16);
	return (u16)~sum;
}

/*
 * ICRC：l3 指向 IP 头，length 是 IP 头到 pad 末尾（不含 ICRC）的字节数。
 * 返回值按小端放到线上（byte0 = 低 8 位）。
 */
static inline fgsi_noinline u32 fgsi_icrc(const u8 *l3, size_t length)
{
	static const u8 lrh_placeholder[8] = { 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff };
	u8 masked[FGSI_L3_HDR_LEN];
	u32 crc;

	memcpy(masked, l3, FGSI_L3_HDR_LEN);
	masked[1] = 0xff;				/* TOS */
	masked[8] = 0xff;				/* TTL */
	masked[10] = masked[11] = 0xff;			/* IP checksum */
	masked[26] = masked[27] = 0xff;			/* UDP checksum */
	masked[FGSI_IP_LEN + FGSI_UDP_LEN + 4] = 0xff;	/* BTH resv8a（FECN/BECN 所在字节） */
	crc = fgsi_crc32_le(0xffffffffu, lrh_placeholder, sizeof(lrh_placeholder));
	crc = fgsi_crc32_le(crc, masked, sizeof(masked));
	crc = fgsi_crc32_le(crc, l3 + FGSI_L3_HDR_LEN, length - FGSI_L3_HDR_LEN);
	return ~crc;
}

/*
 * 写 Eth/IP/UDP/BTH/DETH[/ImmDt] 头，并把 pad 和 ICRC 区清零。
 * 调用者随后把 payload 拷到 frame + fgsi_header_length(opcode)，再调 fgsi_seal()。
 * 返回整帧长度（含 ICRC）。
 */
static inline fgsi_noinline size_t fgsi_build_headers(u8 *frame, const struct fgsi_tx *t, size_t payload_length)
{
	size_t header_length = fgsi_header_length(t->opcode);
	u32 pad = fgsi_pad(payload_length);
	size_t frame_length = header_length + payload_length + pad + FGSI_ICRC_LEN;
	u32 udp_length = (u32)(frame_length - FGSI_ETH_LEN - FGSI_IP_LEN);
	u8 *ip = frame + FGSI_ETH_LEN;
	u8 *udp = ip + FGSI_IP_LEN;
	u8 *bth = udp + FGSI_UDP_LEN;
	u8 *deth = bth + FGSI_BTH_LEN;

	memcpy(frame, t->dmac, 6);
	memcpy(frame + 6, t->smac, 6);
	fgsi_put16(frame + 12, FGSI_ETHERTYPE_IPV4);

	ip[0] = 0x45;
	ip[1] = t->tos;
	fgsi_put16(ip + 2, FGSI_IP_LEN + udp_length);
	fgsi_put16(ip + 4, t->ip_id);
	fgsi_put16(ip + 6, 0x4000);			/* DF */
	ip[8] = t->ttl;
	ip[9] = 17;					/* UDP */
	ip[10] = ip[11] = 0;
	memcpy(ip + 12, t->sip, 4);
	memcpy(ip + 16, t->dip, 4);
	fgsi_put16(ip + 10, fgsi_ip_checksum(ip));

	fgsi_put16(udp, t->sport);
	fgsi_put16(udp + 2, FGSI_ROCE_UDP_PORT);
	fgsi_put16(udp + 4, udp_length);
	fgsi_put16(udp + 6, 0);				/* RoCEv2 UDP 校验和为 0 */

	bth[0] = t->opcode;
	bth[1] = (u8)(((t->solicited & 1) << 7) | (1 << 6) | (pad << 4));	/* SE | MigReq | PadCnt | TVer 0 */
	fgsi_put16(bth + 2, t->pkey);
	bth[4] = 0;
	fgsi_put24(bth + 5, t->dqpn);
	bth[8] = 0;					/* AckReq 0 */
	fgsi_put24(bth + 9, t->psn);

	fgsi_put32(deth, t->qkey);
	deth[4] = 0;
	fgsi_put24(deth + 5, t->sqpn);
	if (fgsi_has_imm(t->opcode))
		memcpy(deth + FGSI_DETH_LEN, t->imm, 4);

	memset(frame + header_length + payload_length, 0, pad + FGSI_ICRC_LEN);
	return frame_length;
}

/* payload 拷完之后算 ICRC 填到帧尾 */
static inline void fgsi_seal(u8 *frame, size_t frame_length)
{
	u32 icrc = fgsi_icrc(frame + FGSI_ETH_LEN, frame_length - FGSI_ETH_LEN - FGSI_ICRC_LEN);
	u8 *tail = frame + frame_length - FGSI_ICRC_LEN;

	tail[0] = (u8)icrc;
	tail[1] = (u8)(icrc >> 8);
	tail[2] = (u8)(icrc >> 16);
	tail[3] = (u8)(icrc >> 24);
}

/*
 * 解析一帧 UD SEND。l3 指向 IP 头，length 是缓冲里从 IP 头起的可用字节数
 * （可能含以太网最小帧补齐，以 IP 总长为准）。成功返回 0，失败返回 FGSI_ERR_*。
 * 不检查目的 QPN / P_Key / Q_Key：那是 QP 层的事。
 */
static inline int fgsi_parse(const u8 *l3, size_t length, struct fgsi_rx *r)
{
	const u8 *udp = l3 + FGSI_IP_LEN;
	const u8 *bth = udp + FGSI_UDP_LEN;
	const u8 *deth = bth + FGSI_BTH_LEN;
	size_t total, minimum;
	u32 udp_length, pad, offset;
	const u8 *tail;
	u32 icrc;

	/* 先只要求 IP/UDP/BTH 完整，判出「不是 UD」再看 DETH 长度：
	 * RC 数据帧也会进 UDP 4791，要按 OPCODE 归类快速丢掉，而不是算成 SHORT。 */
	if (length < FGSI_L3_HDR_LEN)
		return FGSI_ERR_SHORT;
	if (l3[0] != 0x45 || l3[9] != 17 || fgsi_get16(udp + 2) != FGSI_ROCE_UDP_PORT)
		return FGSI_ERR_NOT_ROCE;
	if (bth[0] != FGSI_OP_UD_SEND_ONLY && bth[0] != FGSI_OP_UD_SEND_ONLY_IMM)
		return FGSI_ERR_OPCODE;
	total = fgsi_get16(l3 + 2);
	udp_length = fgsi_get16(udp + 4);
	if (total > length || udp_length + FGSI_IP_LEN != total ||
	    total < FGSI_L3_HDR_LEN + FGSI_DETH_LEN + FGSI_ICRC_LEN)
		return FGSI_ERR_SHORT;
	offset = FGSI_L3_HDR_LEN + FGSI_DETH_LEN + (fgsi_has_imm(bth[0]) ? FGSI_IMM_LEN : 0);
	pad = (bth[1] >> 4) & 3;
	minimum = (size_t)offset + pad + FGSI_ICRC_LEN;
	if (total < minimum)
		return FGSI_ERR_SHORT;

	tail = l3 + total - FGSI_ICRC_LEN;
	icrc = (u32)tail[0] | ((u32)tail[1] << 8) | ((u32)tail[2] << 16) | ((u32)tail[3] << 24);
	if (icrc != fgsi_icrc(l3, total - FGSI_ICRC_LEN))
		return FGSI_ERR_ICRC;

	memcpy(r->sip, l3 + 12, 4);
	memcpy(r->dip, l3 + 16, 4);
	r->tos = l3[1];
	r->ttl = l3[8];
	r->sport = (u16)fgsi_get16(udp);
	r->opcode = bth[0];
	r->solicited = bth[1] >> 7;
	r->pkey = (u16)fgsi_get16(bth + 2);
	r->dqpn = fgsi_get24(bth + 5);
	r->psn = fgsi_get24(bth + 9);
	r->qkey = fgsi_get32(deth);
	r->sqpn = fgsi_get24(deth + 5);
	if (fgsi_has_imm(bth[0]))
		memcpy(r->imm, deth + FGSI_DETH_LEN, 4);
	else
		memset(r->imm, 0, 4);
	r->payload_offset = offset;
	r->payload_length = (u32)(total - minimum);
	return 0;
}

#endif /* YUANRDMA_GSI_PKT_H */
