/* SPDX-License-Identifier: GPL-2.0 OR BSD-2-Clause */
/*
 * yuanrdma_hw.h - YuanNIC-NH400-B RoCEv2 引擎的硬件接口（CSR、WQE、CQE、表项格式）
 *
 * 内核驱动、rdma-core provider 共用；RTL 侧对应 code/release/src/roce/roce_pkg.sv，
 * 两边改动必须同步。所有多字节字段为小端（host 序），除非注明 "网络序"。
 *
 * 【改动必须同步的清单】——每一项都是跨 RTL / 内核 / provider / 台子的契约，
 * 只改一边不会报错，只会静默错位或错数据：
 *   1) SQ WQE opcode（enum ynrdma_wqe_op）↔ roce_pkg.sv 的 WQE_* localparam
 *      ↔ roce_req.sv 的 tx_opcode_of()/wc_opcode_of() ↔ provider wqe_opcode()。
 *      本轮新增 YNRDMA_WQE_UD_SEND=5 / YNRDMA_WQE_UD_SEND_IMM=6（WQE 编码，非线上 opcode）。
 *   2) SQ WQE 的 UD 字段（dw9[23:0] remote_qpn / dw10[31:0] remote_qkey，见 struct ynrdma_sq_wqe 下方）
 *      ↔ roce_req.sv 新增切片 `wqe_read_data[9*32 +: 24]` / `[10*32 +: 32]`
 *      ↔ provider post_send 的 UD 分支。RC 字段偏移不变（dw8 仍是 rkey）。
 *   3) CQE 的 src_qp / has_grh（dw4[23:0] / dw4[24] / dw0[18]，见 struct ynrdma_cqe 下方）
 *      ↔ roce_resp.sv 的 cqe_data **160 bit** 拼接（:839-842，dw4 在 [159:128]）
 *      ↔ roce_req.sv 的 cqe_data（同为 160 bit）↔ roce_engine.sv 的 resp/req_cqe_data 端口
 *      ↔ roce_cq.sv 的 160 bit/client 搬运与 DMA 写拍
 *      ↔ provider yuanrdma_poll_cq 的 wc.src_qp / IBV_WC_GRH。
 *      任何一段退回 128 bit 都会静默丢掉 dw4（-Wno-WIDTH 掩盖），UD 的 src_qp 恒 0。
 *   4) QPC 布局（struct ynrdma_qpc 各 dw 的位段）↔ roce_pkg.sv 的 qpc_* 访问函数。
 *   5) CQE dw0 的 owner/has_imm/is_recv 位 ↔ roce_cq.sv 的 owner_bit 注入 ↔ provider poll_cq。
 *   6) 任何 yuanrdma_hw.h 里的结构体都必须保持下方注释标明的字节大小（编译期断言在文件末尾）。
 *   7) test/sim/common/roce_hw.py 的 TX_JOB_FIELDS / pack_qpc / 结构体打包必须与上述逐字段对齐。
 *   8) roce_pkg.sv 的 rx_hdr_t 加字段（如本轮 src_ip[31:0]）会让 roce_top 的 HDR_W 跟着变，
 *      接收头 FIFO 位宽随之变化——不改逻辑，但要重跑综合看 M20K 占用。
 *
 * 地址：CSR 块位于 PF0 BAR2 偏移 YNRDMA_BAR2_BASE（AVMM slot 0x017），1 MB AVMM 窗口，
 * 只支持 32 bit 访问（BAM -> AXI-Lite 桥只用 wstrb[3:0]）。
 *
 * PCIe5 地址换算：axil_to_avmm_bridge.sv 把 AXI-Lite 地址右移一位再送 AVMM
 * （`avm_address <= reg_awaddr >> 1`），因为 PCIe5 下 BAR2 以 64 bit 粒度呈现
 * （MCDMA 用 64 位访问绕开 32 位访问限制）。因此：
 *     BAR2 字节偏移 = AVMM 字节地址 << 1
 * 本文件里的 YNRDMA_BAR2_BASE 与 YNRDMA_DB_PAGE 直接给出 BAR2 字节偏移；
 * 窗口内寄存器偏移（YNRDMA_REG_*）是 AVMM 字节偏移，访问时由驱动左移一位。
 * 对照点：yuanmcdma 的 IFC_MAC_OFFSET(0x0160_0000) 实际访问 BAR2 0x02C0_0000。
 */
#ifndef YUANRDMA_HW_H
#define YUANRDMA_HW_H

#include <linux/types.h>     /* 内核与用户态（linux uapi 头）都提供 __u8..__u64 */

#define YNRDMA_PCI_VENDOR_ID     0x1172  /* 以 lspci 实测为准 */
#define YNRDMA_BAR2_BASE         0x02E00000u /* AVMM 0x0170_0000 << 1 */
#define YNRDMA_WINDOW_SIZE       0x00200000u /* 1 MB AVMM 窗口，PCIe5 下占 2 MB */
#define YNRDMA_ADDR_SHIFT        1u          /* BAR2 偏移 = AVMM 地址 << YNRDMA_ADDR_SHIFT */
#define YNRDMA_ID_MAGIC          0x524f4345u /* "ROCE" */
#define YNRDMA_HW_VERSION        0x00010000u

/* 资源规格（v1） */
/* S4：QP 16 → 128（roce_pkg.sv QP_NUM=128 / QP_W=7 / 每 lane 32 项）。
 * QPN 落在 YNRDMA_QPN_BASE..+YNRDMA_MAX_QP-1 这一连续窗口，且 YNRDMA_QPN_BASE 必须是
 * YNRDMA_MAX_QP 的整数倍——roce_rx_parse 直接拿 dest_qpn[QP_W-1:0] 当 qp_index，只有基址
 * 对齐时「低 7 位」才等于「QPN - 基址」。改这里必须同步改 RTL 的 QP_NUM/QPN_BASE。 */
#define YNRDMA_MAX_QP            128
/* S6：CQ 16 → 64。QPC dw0 的 send_cq/recv_cq 各扩到 6 bit（见下方 struct ynrdma_qpc 的 dw0），
 * 硬件上限即 64 个 CQ。**改这个宏必须同时改 RTL 的 CQ_NUM**（roce_pkg.sv 的 CQ_W 随之从 4 变 6），
 * 否则 CQ 编号高位被静默截断：CQ 40 会落到 CQ 8（40 & 15 == 8），CQE 写进别人的环且不报错。 */
#define YNRDMA_MAX_CQ            64
#define YNRDMA_MAX_MR            64
/* S7：MTT 8192 → 131072（16×），单 MR 上限 = 131072 × 4 KB = 512 MiB（原 32 MiB）。
 * 必须与 roce_pkg.sv 的 MTT_NUM 同步；RTL 侧索引位宽由 MTT_NUM 派生（MTT_W=17）。
 * TBL_MTT 一次仍写 8 项（YUANRDMA_MTT_GROUP），一个 512 MiB MR 要 16384 条表命令。 */
#define YNRDMA_MAX_MTT           131072
#define YNRDMA_QPN_BASE          128     /* QPN = YNRDMA_QPN_BASE + qp_idx；避开 QP0/QP1（QP1 = CM/GSI 保留） */
#define YNRDMA_PAGE_SHIFT        12      /* MTT 页 4 KB */

/* ---------------- 全局寄存器（相对 YNRDMA_BAR2_BASE） ---------------- */
#define YNRDMA_REG_ID            0x0000  /* RO YNRDMA_ID_MAGIC */
#define YNRDMA_REG_VERSION       0x0004  /* RO */
#define YNRDMA_REG_CAPS          0x0008  /* RO [7:0]log2 QP [15:8]log2 CQ [23:16]log2 MR [31:24]log2 MTT */
#define YNRDMA_REG_CTRL          0x000C  /* RW */
#define   YNRDMA_CTRL_ENABLE       (1u << 0) /* 引擎收发使能；0 时 RoCE 报文不进引擎 */
#define   YNRDMA_CTRL_SOFT_RST     (1u << 1) /* 写 1 复位引擎内部状态（自清） */
#define   YNRDMA_CTRL_PFC_GATE_DIS (1u << 2) /* 写 1 关 RoCE 发送侧 PFC/PAUSE 准入（复位 0 = 门控开）；B6420 及以前读回恒 0、写无效 */
#define YNRDMA_REG_STATUS        0x0010  /* RO [0] MAC link up */
#define YNRDMA_REG_MAC_LO        0x0014  /* RW 本端 MAC，网络序字节 0..3 放在 [7:0]..[31:24] */
#define YNRDMA_REG_MAC_HI        0x0018  /* RW 字节 4..5 放在 [7:0]..[15:8] */
#define YNRDMA_REG_IPV4          0x001C  /* RW 本端 IPv4，网络序字节 0..3 放在 [7:0]..[31:24] */
#define YNRDMA_REG_CORE_CLOCK    0x0020  /* RO 引擎 core 时钟（MHz），DT_CYCLES 等按它换算 */

/* 表写口：先写 CMD_DATA[0..15]，再写 CMD；读回时 CMD_DATA 返回表项 */
#define YNRDMA_REG_CMD_DATA(i)   (0x0100 + 4 * (i))  /* i = 0..15，共 64 B */
#define YNRDMA_REG_CMD           0x0140
#define   YNRDMA_CMD_OP_WRITE      (1u << 31)          /* 1 写表项，0 读表项 */
#define   YNRDMA_CMD_TBL_SHIFT     24                  /* [27:24] */
#define   YNRDMA_CMD_TBL_QPC       1                   /* 64 B */
#define   YNRDMA_CMD_TBL_MPT       2                   /* 32 B */
#define   YNRDMA_CMD_TBL_MTT       3                   /* 一次 8 项 x 8 B，index 为首项 */
#define   YNRDMA_CMD_TBL_CQC       4                   /* 16 B */
#define   YNRDMA_CMD_IDX_MASK      0x00ffffffu         /* [23:0] */
#define YNRDMA_REG_CMD_STATUS    0x0144  /* RO [0] busy [1] error（非法表/越界） */

/* 统计计数器（RO，32 bit 回绕） */
#define YNRDMA_REG_CNT(i)        (0x0200 + 4 * (i))
enum ynrdma_cnt {
	YNRDMA_CNT_TX_PKTS = 0, YNRDMA_CNT_RX_PKTS, YNRDMA_CNT_RX_ICRC_ERR, YNRDMA_CNT_RX_DROP,
	YNRDMA_CNT_RX_BAD_QP, YNRDMA_CNT_RX_DUP, YNRDMA_CNT_RX_SEQ_ERR, YNRDMA_CNT_TX_ACK,
	YNRDMA_CNT_TX_NAK, YNRDMA_CNT_RX_ACK, YNRDMA_CNT_RX_NAK, YNRDMA_CNT_RETX_TIMEOUT,
	YNRDMA_CNT_RETX_NAK, YNRDMA_CNT_TX_RNR_NAK, YNRDMA_CNT_RX_RNR_NAK, YNRDMA_CNT_CQE,
	YNRDMA_CNT_CQ_OVERFLOW, YNRDMA_CNT_RX_ACCESS_ERR,
	/* BAS 通路握手计数（roce_bas_mon，pcie_clk 域）。DMA 自测一次后应满足：
	 * BAS_AW_HS == BAS_W_LAST_HS == BAS_B，BAS_AR_HS == BAS_R_LAST，且都 >= 1。
	 * 有 valid 无握手 = MCDMA 不接收；有握手无响应 = 主机侧/completion 丢失。 */
	YNRDMA_CNT_BAS_AW_HS, YNRDMA_CNT_BAS_W_LAST_HS, YNRDMA_CNT_BAS_B,
	YNRDMA_CNT_BAS_AR_HS, YNRDMA_CNT_BAS_R_LAST,
	YNRDMA_CNT_NUM
};

/* DMA 自测（BAS 读 src -> 写 dst），单次 <= 4 KB 且不跨 4 KB 页 */
#define YNRDMA_REG_DT_SRC_LO     0x0300
#define YNRDMA_REG_DT_SRC_HI     0x0304
#define YNRDMA_REG_DT_DST_LO     0x0308
#define YNRDMA_REG_DT_DST_HI     0x030C
#define YNRDMA_REG_DT_LEN        0x0310  /* 字节，1..4096 */
#define YNRDMA_REG_DT_REPEAT     0x0314  /* 重复次数（测带宽），0 视为 1 */
#define YNRDMA_REG_DT_CTRL       0x0318  /* W [0] start */
#define YNRDMA_REG_DT_STATUS     0x031C  /* RO [0] busy [1] done [2] error(bresp/rresp) */
#define YNRDMA_REG_DT_CYCLES     0x0320  /* RO 最近一次运行的 core 时钟周期数（频率见 YNRDMA_REG_CORE_CLOCK） */

/* ---------------- Doorbell 页（4 KB，可单独 mmap 给用户态） ----------------
 * AVMM 侧三个门铃在 0x1000 / 0x1004 / 0x1008，PCIe5 下各自左移一位变成
 * 0x2000 / 0x2008 / 0x2010，相对页首 0x2000 的偏移为 0x00 / 0x08 / 0x10。
 * 用户态 mmap 的页首就是 0x2000，所以按字节偏移 0x00 / 0x08 / 0x10 写。
 */
#define YNRDMA_DB_PAGE           0x1000
#define YNRDMA_DB_SQ             0x00    /* [31:16] sq_pi  [7:0] qp_idx（8 bit，够 128 QP） */
#define YNRDMA_DB_RQ             0x08    /* [31:16] rq_pi  [7:0] qp_idx */
#define YNRDMA_DB_CQ             0x10    /* [31:16] cq_ci  [7:0] cq_idx */

/* ---------------- 表项格式 ---------------- */
enum ynrdma_qp_state {
	YNRDMA_QPS_RESET = 0, YNRDMA_QPS_INIT = 1, YNRDMA_QPS_RTR = 2, YNRDMA_QPS_RTS = 3,
	YNRDMA_QPS_ERR = 6,
};

/* QPC（64 B）。写 state 时硬件按转换装载动态状态：
 * ->RESET/INIT 清零 sq_ci/rq_ci/在途表；->RTR 装载 epsn=rq_psn、msn=0；
 * ->RTS 装载 next_psn=una_psn=sq_psn。硬件出错时自己把 state 置 ERR（读回可见）。 */
struct ynrdma_qpc {
	__u32 dw0;          /* [2:0]state [5:3]pmtu(ibv_mtu 1..5) [11:6]send_cq [17:12]recv_cq
			     * [18]remote_write [19]remote_read [20]remote_atomic
			     * [21]qp_type（1 = UD、0 = RC；G2.1）—— roce_req 用它校验
			     *     「WQE opcode 是 UD」与「QP 本身是 UD」必须一致，不一致报
			     *     WCS_LOC_OP_ERR。驱动侧 UD/RC 不再有开关（2026-11-21），
			     *     运行期靠这一位区分。
			     * S6 改了布局：send_cq/recv_cq 从 4 bit 扩到 6 bit（CQ 16 → 64），
			     * remote_write/read 从 [16]/[17] 挪到 [18]/[19]（让位给 recv_cq）。
			     * 这是跨 RTL / 内核 / provider / 台子的契约，改这里必须同步改
			     * roce_pkg.sv 的 qpc_scq/qpc_rcq 与 sim 的 pack_qpc()。
			     * 注意 remote_write/read 这两位 RTL 没有消费方（权限走 MPT 的
			     * YNRDMA_ACC_*），只是记录。 */
	__u32 dest_qpn;     /* [23:0] */
	__u32 dst_ip;       /* 网络序字节 0..3 放在 [7:0]..[31:24] */
	__u32 dst_mac_lo;   /* 同 YNRDMA_REG_MAC_LO */
	__u32 dw4;          /* [15:0]dst_mac 字节4..5 [31:16]udp_sport（host 序） */
	__u32 sq_psn;       /* [23:0] */
	__u32 rq_psn;       /* [23:0] */
	__u32 dw7;          /* [4:0]timeout [7:5]retry_cnt [10:8]rnr_retry [15:11]min_rnr_timer
			     * [23:16]tos(DSCP<<2|ECN) [31:24]ttl */
	__u32 sq_base_lo, sq_base_hi; /* SQ 环 DMA 地址，物理连续 */
	__u32 rq_base_lo, rq_base_hi; /* RQ 环 DMA 地址，物理连续 */
	__u32 dw12;         /* [3:0]log2 sq_depth [7:4]log2 rq_depth [11:8]max_rd_atomic(对端)
			     * [15:12]max_dest_rd_atomic(本端) [31:16]pd */
	__u32 rsvd[3];
};

#define YNRDMA_ACC_LOCAL_WRITE   (1u << 0)
#define YNRDMA_ACC_REMOTE_WRITE  (1u << 1)
#define YNRDMA_ACC_REMOTE_READ   (1u << 2)
#define YNRDMA_ACC_REMOTE_ATOMIC (1u << 3)

/* MPT（32 B）。lkey == rkey == (tag << 8) | mr_idx */
struct ynrdma_mpt {
	__u32 dw0;          /* [0]valid [4:1]YNRDMA_ACC_* [31:16]pd */
	__u32 key;
	__u64 va;
	__u64 len;
	__u32 mtt_base;     /* 首个 MTT 项索引；项 i 对应 (va & ~0xfff) + i*4K 所在页 */
	__u32 rsvd;
};

/* MTT 项：4 KB 页的 DMA 地址，低 12 位必须为 0 */
typedef __u64 ynrdma_mtt;

/* CQC（16 B）。写入时硬件 PI 清零 */
struct ynrdma_cqc {
	__u32 base_lo, base_hi; /* CQ 环 DMA 地址，物理连续 */
	__u32 dw2;          /* [0]valid [4:1]log2 depth */
	__u32 rsvd;
};

/* ---------------- SQ WQE（64 B，主机内存 SQ 环） ----------------
 * WQE opcode → RTL roce_pkg.sv 的 WQE_* localparam，数值必须逐位一致。
 * 注意 YNRDMA_WQE_UD_SEND* 是 **WQE 编码**，不是线上 BTH opcode：RTL 的 roce_req
 * tx_opcode_of() 会把它翻译成 OP_SEND_ONLY_UD(0x64) / OP_SEND_ONLY_UD_IMM(0x65)，
 * 与 RC 的 0x04/0x05 是两套编码。 */
enum ynrdma_wqe_op {
	YNRDMA_WQE_RDMA_WRITE = 0, YNRDMA_WQE_RDMA_WRITE_IMM = 1,
	YNRDMA_WQE_SEND = 2, YNRDMA_WQE_SEND_IMM = 3, YNRDMA_WQE_RDMA_READ = 4,
	YNRDMA_WQE_UD_SEND = 5, YNRDMA_WQE_UD_SEND_IMM = 6,	/* 必须与 roce_pkg WQE_UD_SEND=4'd5 / WQE_UD_SEND_IMM=4'd6 一致 */
};
#define YNRDMA_WQE_F_SIGNALED    (1u << 8)
#define YNRDMA_WQE_F_SOLICITED   (1u << 9)

struct ynrdma_sq_wqe {
	__u32 dw0;          /* dw0 [3:0]op [8]signaled [9]solicited */
	__u32 length;       /* dw1 0..2^31 */
	__u32 lkey;         /* dw2 */
	__u32 imm;          /* dw3 ImmDt，网络序原样（RC 与 UD_IMM 共用，来自 wr.imm_data） */
	__u64 laddr;        /* dw4..dw5 */
	__u64 raddr;        /* dw6..dw7，仅 RC 的 READ/WRITE 用；UD WQE 必须写 0 */
	__u32 rkey;         /* dw8 仅 RC；UD WQE 必须写 0 */
	__u32 rsvd[7];      /* dw9..dw15（共 28 B）。UD 的 remote_qpn / qkey 落在这里 */
};

/* ---- UD 在 SQ WQE 里的落位（占 rsvd 区，结构体仍是 64 B，**不动任何 RC 字段的偏移**） ----
 *
 *   dword  位宽    字段              谁写 / 谁读
 *   dw9    [23:0]  remote_qpn        provider 写（ah->remote_qpn）；RTL 读 → BTH Dest QP
 *                                    与 DETH 目的 QP（同一值，复用 tx_job.dqpn 字段）
 *   dw9    [31:24] 保留              provider 必须写 0
 *   dw10   [31:0]  remote_qkey       provider 写（ah->remote_qkey，主机序）；
 *                                    RTL 读 → tx_job.deth_qkey，组头时 swap32 成网络序
 *   dw11..dw15     保留              provider 必须写 0
 *
 * 语义与约束（provider post_send 与 roce_req 必须严格照此实现）：
 *  - **仅 YNRDMA_WQE_UD_SEND / YNRDMA_WQE_UD_SEND_IMM 有效**；RC WQE 的 dw9..dw15 恒 0。
 *  - RTL 切片：`wqe_read_data[9*32 +: 24]` = remote_qpn、`wqe_read_data[10*32 +: 32]` = qkey。
 *    dw9..dw15 现在是 rsvd、没有任何消费方，加这两个切片是**纯新增**，RC 路径一个字节不用动
 *    （`wqe_rkey` 仍是 `wqe_read_data[287:256]`，即 dw8，见 roce_req.sv:570）。
 *  - ImmDt 复用 RC 的 dw3：UD_IMM 的 ImmDt 同样来自 wr.imm_data，走 `tx_job.immediate`，
 *    与 RC 的 SEND_WITH_IMM 完全同一条路径，不需要为 UD 新增字段。
 *  - UD WQE 的 `raddr`/`rkey`/`lkey` 语义：raddr、rkey 写 0（RTL 的 UD 分支不看，
 *    留着非零值会让重发/调试误判）；lkey 仍用于本端 payload 的 MTT 翻译，必须有效。
 *  - 为什么 remote_qpn 不塞 QPC 的 dest_qpn：同一个 UD QP 允许发往不同目的 QPN /
 *    Q_Key（AH 是 per-WR 的），塞进 QPC 不符合 IB 语义。
 *  - dw9/dw10 的落位与 UD 传输设计一致（remote_qpn/qkey 放 rsvd[0]/rsvd[1]）
 *    一致：rsvd 从 dw9 起算，所以 rsvd[0] = dw9 = QPN、rsvd[1] = dw10 = QKey。
 */

/* RQ WQE（32 B，单 SGE） */
struct ynrdma_rq_wqe {
	__u32 length;
	__u32 lkey;
	__u64 addr;
	__u32 rsvd[4];
};

/* ---------------- CQE（32 B，主机内存 CQ 环） ----------------
 * owner：硬件写第 n 个 CQE（从 0 计）时 owner = (n >> log2_depth) & 1 的反，
 * 即第一圈写 1、第二圈写 0。provider 在 ci 处检查 owner == !((ci >> log2_depth) & 1)。 */
struct ynrdma_cqe {
	__u32 dw0;          /* [7:0]ibv_wc_opcode [15:8]ibv_wc_status [16]has_imm [17]is_recv
			     * [18]has_grh（UD 收到的报文是否已合成 GRH，provider 据此置 IBV_WC_GRH）
			     * [19..30]保留（写 0）[31]owner */
	__u32 dw1;          /* [15:0]wqe_idx [23:16]qp_idx（8 bit，128 个 QP 够用；255 才溢出） */
	__u32 byte_len;
	__u32 imm;          /* 网络序原样 */
	__u32 dw4;          /* UD：DETH 的源 QPN
			     * [23:0]src_qp（IB 语义下 UD 的 wc.src_qp 是 24 bit，全 1 = 未定义/组播）
			     * [24]src_qp_valid（0 = 该 CQE 的 src_qp 无意义，例如 RC 完成）
			     * [31:25]保留（写 0） */
	__u32 rsvd[3];      /* dw5..dw7 */
};

/* ---- UD 在 CQE 里的落位（放原 rsvd[4] 区，结构体仍是 32 B） ----
 *
 * provider poll_cq 读哪一位填什么（rdma-core：yuanrdma_verbs.c 的 yuanrdma_poll_cq）：
 *   1) 始终先判 owner = dw0[31]（现有逻辑不变）。
 *   2) `wc.src_qp`：先判 dw4[24]（src_qp_valid），为 1 时
 *        wc.src_qp = le32toh(cqe->dw4) & 0xffffff;
 *      为 0 时保持 0。**不要无条件读 dw4[23:0]**——S6 之前 dw4 一直是 rsvd，
 *      老环里的残留数据会让 RC 完成报出随机 src_qp。
 *   3) `wc.wc_flags |= IBV_WC_GRH`：判 dw0[18]（has_grh）为 1 时置位。
 *      置位时接收缓冲**前 40 B 是 GRH**，byte_len 不含这 40 B（IB 语义，见 roce_pkg.rx_hdr_t
 *      的 src_ip 注释）。只有 UD + has_grh 的组合会置这一位，RC 恒 0。
 *   4) has_imm（dw0[16]）/ is_recv（dw0[17]）的现有判读顺序不要动。
 *
 * RTL 侧写入点：roce_resp.sv 的 `cqe_data <= {...}` 那一条拼接（约 :835-837）。
 * 该处是手工拼 128 bit，加字段必须同步改，否则位错位（无编译错误）。
 */

/* ---------------- 扩展调试寄存器（AVMM 0x0500..0x075C，需 B6396 及以后镜像） ----------------
 * 分三组，一个概念一块、lane 之间等距：
 *   共享/旧地址  0x0500..0x05F0（其中 0x0560.. 的 core 观测 = 组 B 的 lane0 别名）
 *   组 A RX lane 0x0600 + 0x20*i   i = 0..LANES-1
 *   组 B RDMA core lane 0x0680 + 0x40*i
 *   组 C 汇合/分流 0x0740
 * 读回 0xdeadbeef 表示该地址在镜像里不存在（镜像太老或译码未覆盖）。
 * 用户态工具 deploy/yuancli 的 `register rx_pkts / rdmacore / tx_merge` 与本表一一对应。 */
#define YNRDMA_DBG_BASE              0x0500u
#define YNRDMA_DBG_END               0x075Cu
#define YNRDMA_DBG_ID                0x0500u  /* RO "RDBG" = 0x52444247 */
#define YNRDMA_DBG_VERSION           0x0504u  /* RO {major[23:16], minor[15:8], snap_words[15:0]} */
#define YNRDMA_DBG_STALL_THRESHOLD   0x0508u  /* RW 判死拍数（core_clk），写 0 关闭 */
#define YNRDMA_DBG_STALL_COUNT       0x050Cu  /* RO 触发过多少次快照 */
#define YNRDMA_DBG_STALL_CONTROL     0x0510u  /* WO 写 2 = 清快照与计数，其它 = 立即采样 */
#define YNRDMA_DBG_STALL_STATUS      0x0514u  /* RO [0]有效 [9:8]域 [17:10]通道 */
#define YNRDMA_DBG_SNAP(i)           (0x0590u + 4u * (i))  /* 16 个字 */

/* 组 A：RX lane（每条 MAC 输入一路） */
#define YNRDMA_DBG_RX_LANE(i, reg)   (YNRDMA_DBG_BASE + 0x100u + 0x20u * (i) + (reg))
#define   YNRDMA_DBG_RX_FRAMES        0x00u  /* 累计完成帧数 */
#define   YNRDMA_DBG_RX_ICRC_ERRORS   0x04u  /* ICRC 校验失败帧 */
#define   YNRDMA_DBG_RX_DROPPED       0x08u  /* staging 满整帧丢弃 */
#define   YNRDMA_DBG_RX_STAGING       0x0Cu  /* [9:0] 当前暂存占用（拍） */
#define   YNRDMA_DBG_RX_STAGING_PEAK  0x10u  /* [9:0] 峰值，理论上限 504 */
#define   YNRDMA_DBG_RX_MAC_FIFO      0x14u  /* [15:0] empty [31:16] afull */
#define   YNRDMA_DBG_RX_PEAK_CLEAR    0x18u  /* WO 写任意值清该 lane 峰值 */

/* 组 B：RDMA core lane（每个引擎实例一套） */
#define YNRDMA_DBG_CORE_LANE(i, reg) (YNRDMA_DBG_BASE + 0x180u + 0x40u * (i) + (reg))
#define   YNRDMA_DBG_CORE_REQUESTER   0x00u  /* [4:0]Fsm [7:5]dispatch_reason [12:8]retry_left
                                             * [17:13]reads_outstanding [18]recovering [19]local_error */
#define   YNRDMA_DBG_CORE_RESPONDER   0x04u  /* [3:0]main_state [6:4]out_state */
#define   YNRDMA_DBG_CORE_DISPATCH    0x08u  /* [0]busy [1]owner */
#define   YNRDMA_DBG_CORE_TX_BUILD    0x0Cu  /* [1:0]build [3:2]mux [6:4]skip_align [10:7]inflight */
#define   YNRDMA_DBG_CORE_ACTIVE_QP   0x10u  /* [QP_W-1:0]qpn（S4 起 7 bit）[QP_W+2:QP_W]state [31:QP_W+3]next_psn
                                             * S4 起布局改变：旧版是 [3:0]qpn [6:4]state [31:8]next_psn。
                                             * 0x0560 的旧别名 A_QP_ACTIVE 仍按 [3:0] 截断，只用于兼容老脚本。 */
#define   YNRDMA_DBG_CORE_DMA         0x14u  /* [9:0]read_credit [10]2nd_phase [13:11]fifo 状态 */
#define   YNRDMA_DBG_CORE_BAS         0x18u  /* [7:0]BAS live [15:8]未完成 AR（全卡共享） */
#define   YNRDMA_DBG_CORE_STICKY      0x1Cu  /* [3:0] {bresp,rresp,AR,R-last}（共享源） */
#define   YNRDMA_DBG_CORE_QPC_LOW     0x20u  /* 活动 QP 的 QPC 低 32 位 */
#define   YNRDMA_DBG_CORE_PSN         0x24u  /* 活动 QP 的 next_psn */
#define   YNRDMA_DBG_CORE_ACK         0x28u  /* [5:0]ack_counter [10:6]reads_outstanding */
#define   YNRDMA_DBG_CORE_TX_OFFSET   0x2Cu  /* 当前 WQE 内偏移 */

/* ---------------- 拥塞控制寄存器（AVMM 0x0800..0x0BFC，需 full_pfc_func 镜像） ----------------
 * 三个窗口，各由一个模块独占（见 code/quartus/YuanNIC-NH400-A/active/rtl_src/roce/ 下对应 RTL）：
 *   0x0800..0x09FC  PFC 控制器     roce_pfc.sv
 *   0x0A00..0x0AFC  ECN / CNP（NP） roce_cnp.sv
 *   0x0B00..0x0BFC  DCQCN（RP）     roce_dcqcn.sv
 * 读回 0xdeadbeef = 该镜像没有这个窗口（full_pfc_func 之前的版本）。
 * 用户态工具 deploy/yuancli 的 `pfc ...`、`ecn ...`、`dcqcn ...` 与本表一一对应。 */

#define YNRDMA_CC_BASE               0x0800u
#define YNRDMA_CC_END                0x0BFCu

/* ---- PFC（0x0800） ---- */
#define YNRDMA_PFC_BASE              0x0800u
#define YNRDMA_PFC_END               0x09FCu
#define YNRDMA_PFC_ID                0x0800u  /* RO 0x50464301 = "PFC" v1 */
#define YNRDMA_PFC_CTRL              0x0804u  /* RW，复位 0x0F */
#define   YNRDMA_PFC_CTRL_TX_EN        (1u << 0) /* 1 = 按 RX 水位自动发 XOFF（0 = 只统计） */
#define   YNRDMA_PFC_CTRL_RX_EN        (1u << 1) /* 1 = 按收到的 pause 停发 */
#define   YNRDMA_PFC_CTRL_RESP_GATE    (1u << 2) /* 1 = ACK / READ RESP 也受 pause 约束 */
#define   YNRDMA_PFC_CTRL_EGRESS_GATE  (1u << 3) /* 1 = 每 lane 出口按帧头 TOS 在帧边界挡 */
#define YNRDMA_PFC_TX_MASK           0x0808u  /* RW，复位 0xFF：[p] 允许单独暂停优先级 p */
#define YNRDMA_PFC_RX_HONOR          0x080Cu  /* RW，复位 0x1FF：[p] 理会该优先级 pause [8] 理会 802.3x */
#define YNRDMA_PFC_CTRL2             0x0810u  /* RW，复位 0 */
#define   YNRDMA_PFC_CTRL2_GLOBAL      (1u << 0) /* 任何拥塞都直接整体暂停 */
#define   YNRDMA_PFC_CTRL2_MODE8       (1u << 1) /* 升级后的形式：1 = 802.3x（停全部） */
#define   YNRDMA_PFC_CTRL2_ESC8        (1u << 2) /* 升级时另外再叠一路 802.3x */
#define   YNRDMA_PFC_CTRL2_ANY_ALL     (1u << 3) /* 任一优先级被暂停 ⇒ 8 个优先级全停 */
#define   YNRDMA_PFC_CTRL2_RX_WD_EN    (1u << 4) /* 打开接收侧看门狗（需 WD_RX_US != 0） */
#define YNRDMA_PFC_ALL_THR           0x0814u  /* RW，复位 448：每 lane 总占用（拍）≥ 此值升级为整体暂停 */
#define YNRDMA_PFC_HOLD_US           0x0818u  /* RW，复位 10（B6433 起；之前 100）：XOFF 最短保持 µs */
#define YNRDMA_PFC_WD_TX_US          0x081Cu  /* RW，复位 100000：XOFF 连续保持超此值强制放开（0 = 关） */
#define YNRDMA_PFC_WD_RX_US          0x0820u  /* RW，复位 0：对端连续暂停超此值不再理会（0 = 关） */
#define YNRDMA_PFC_WD_WARN_US        0x082Cu  /* RW，复位 0（B6434）：XOFF 持续超此值只置告警位、不放开 XOFF */
#define YNRDMA_PFC_STATUS            0x0824u  /* RO [8:0]生效 pause [24:16]我方 tx_pfc [25]升级中 [26]出口挡帧中 */
#define YNRDMA_PFC_STATUS2           0x0828u  /* RO [7:0]RX 看门狗命中 [15:8]TX 看门狗强制放开 */
#define YNRDMA_PFC_XOFF_THR(p)       (0x0840u + 4u * (p))  /* RW，复位 256 拍（128 B/拍） */
#define YNRDMA_PFC_XON_THR(p)        (0x0860u + 4u * (p))  /* RW，复位 128 拍 */
#define YNRDMA_PFC_OCC(lane, p)      (0x0880u + 4u * ((lane) * 8u + (p)))  /* RO 当前占用（拍） */
#define YNRDMA_PFC_CNT(k)            (0x0900u + 4u * (k))  /* RO 48 个计数器 */
enum ynrdma_pfc_cnt {
	/* [0..8]   RX_EVT：被暂停段数（[8] = 802.3x）
	 * [9..17]  RX_TICK：被暂停持续拍数
	 * [18..26] TX_EVT：我方发 XOFF 的段数
	 * [27..35] TX_TICK：我方发 XOFF 的持续拍数
	 * [36..43] DROP：staging 满整帧丢弃（按优先级）
	 * 44 RX_WD_TRIP / 45 TX_WD_TRIP / 46 EGRESS_HOLD_TICK / 47 ESCALATE_EVT
	 * 48 TX_WD_WARN：WD_WARN_US 告警的上升沿数（B6434，只告警不放开 XOFF）
	 * RTL 里 cnt[0..48] 共 49 个 */
	YNRDMA_PFC_CNT_RX_EVT    = 0,
	YNRDMA_PFC_CNT_RX_TICK   = 9,
	YNRDMA_PFC_CNT_TX_EVT    = 18,
	YNRDMA_PFC_CNT_TX_TICK   = 27,
	YNRDMA_PFC_CNT_DROP      = 36,
	YNRDMA_PFC_CNT_RX_WD_TRIP = 44,
	YNRDMA_PFC_CNT_TX_WD_TRIP = 45,
	YNRDMA_PFC_CNT_EGRESS_HOLD_TICK = 46,
	YNRDMA_PFC_CNT_ESCALATE_EVT = 47,
	YNRDMA_PFC_CNT_TX_WD_WARN = 48,
};
#define YNRDMA_PFC_CLEAR             0x09FCu  /* WO 写任意值清全部计数 */

/* ---- ECN / CNP（0x0A00，NP 侧；roce_cnp.sv） ----
 * NP = 收包网卡：收到 ECN==CE 的 RoCE 数据包后，向发送方回一个 CNP（BTH opcode 0x81）。
 * 限频是**端口级**的（学 NVIDIA min_time_between_cnps 默认 4 µs），轮询仲裁分给有请求的 lane。
 * CNP 的 DSCP / ECN 来自 CNP_TOS（默认 48<<2 = 0xC0，ECN 必须为 00，否则 CNP 自己又被标 CE）。 */
#define YNRDMA_CNP_BASE              0x0A00u
#define YNRDMA_CNP_END               0x0AFCu
#define YNRDMA_CNP_ID                0x0A00u  /* RO 0x434E5001 = "CNP" v1 */
#define YNRDMA_CNP_CTRL              0x0A04u  /* RW，复位 0x3 */
#define   YNRDMA_CNP_CTRL_EN           (1u << 0) /* 总开关；0 = 不发 CNP、也不计 CE 包 */
#define   YNRDMA_CNP_CTRL_NP_EN        (1u << 1) /* 1 = 收到 CE 包才发 CNP（A/B 对照用 0） */
#define YNRDMA_CNP_TOS               0x0A08u  /* RW，复位 0xC0（DSCP 48 << 2，ECN 00） */
#define YNRDMA_CNP_MIN_US            0x0A0Cu  /* RW，复位 4（µs）：端口级 CNP 最小间隔，0 = 不限频 */
#define YNRDMA_CNP_STATUS            0x0A10u  /* RO [0] 有 lane 在等 grant  [1] 限频窗口开着 */
#define YNRDMA_CNP_BTH               0x0A14u  /* RW，复位 0x1（B6434）：[0]BECN [1]FECN（BTH byte4 高两位） */
#define   YNRDMA_CNP_BTH_BECN          (1u << 0) /* CNP 带 BECN（默认 1，TCP 语义） */
#define   YNRDMA_CNP_BTH_FECN          (1u << 1) /* CNP 带 FECN（默认 0） */
#define YNRDMA_CNP_CNT(k)            (0x0A40u + 4u * (k))  /* RO 8 个（用 5 个） */
enum ynrdma_cnp_cnt {
	YNRDMA_CNP_CNT_ECN_MARKED = 0,   /* np_ecn_marked_roce_packets：收到的 CE 数据包数 */
	YNRDMA_CNP_CNT_CNP_SENT   = 1,   /* np_cnp_sent：实际发出的 CNP 数 */
	YNRDMA_CNP_CNT_RP_HANDLED = 2,   /* rp_cnp_handled：收到并接受的 CNP 数 */
	YNRDMA_CNP_CNT_RP_IGNORED = 3,   /* rp_cnp_ignored：收到但丢弃的 CNP 数（QP 非法/非 RTS） */
	YNRDMA_CNP_CNT_THROTTLED  = 4,   /* 因限频窗口关闭而推迟的 CNP 次数 */
};
#define YNRDMA_CNP_CLEAR             0x0AFCu  /* WO 写任意值清全部计数 */

/* ---- DCQCN（0x0B00，RP 侧；roce_dcqcn.sv） ----
 * RP = 发送网卡：收到 CNP 降速，超时/按字节升速。每 QP 一份上下文。
 * S5（2026-11-14）：DCQCN 扩到全部 128 个 QP（roce_top 的 DCQCN_QP_NUM = QP_NUM = 128）。
 * STATUS 仍是 32 位（内部 STATUS_W = min(QP_NUM,32) 封顶 32）；A_QP 选择范围改为 0..127。
 * 参数默认值照 NVIDIA DOCA（names in comments）。CTRL.EN 默认 **0**：不开就完全不限制，
 * 行为与没有本模块时逐位一致（上板 A/B 对照用）。
 *
 * 定点约定：
 *   RC / RT / AI / HAI / LINE / MIN_RATE 单位 Mb/s（20 bit）
 *   信用 credit 单位 1/2048 字节，每拍 += RC，每发一个包 -= (payload + 100 B) × 2048 */
#define YNRDMA_DCQCN_BASE            0x0B00u
#define YNRDMA_DCQCN_END             0x0BFCu
#define YNRDMA_DCQCN_ID              0x0B00u  /* RO 0x44435101 = "DCQ" v1 */
#define YNRDMA_DCQCN_CTRL            0x0B04u  /* RW，复位 0 */
#define   YNRDMA_DCQCN_CTRL_EN         (1u << 0) /* 1 = 启用速率限制（默认 0 = 不限） */
#define   YNRDMA_DCQCN_CTRL_HAI_EN     (1u << 1) /* 1 = 允许超加性升速（rpg_threshold 生效） */
#define   YNRDMA_DCQCN_CTRL_CLAMP_RT   (1u << 2) /* 1 = 每次降速都同步 RT（NVIDIA clamp_tgt_rate） */
#define   YNRDMA_DCQCN_CTRL_CRED_CLR   (1u << 3) /* 调试：1 = 强制每 QP 信用为 0（完全停发） */
#define YNRDMA_DCQCN_AI              0x0B08u  /* RW rpg_ai_rate  Mb/s（默认 5） */
#define YNRDMA_DCQCN_HAI             0x0B0Cu  /* RW rpg_hai_rate Mb/s（默认 50） */
#define YNRDMA_DCQCN_THRESH          0x0B10u  /* RW rpg_threshold / F（默认 1） */
#define YNRDMA_DCQCN_ALPHA_US        0x0B14u  /* RW dce_tcp_rtt µs（默认 1） */
#define YNRDMA_DCQCN_RED_US          0x0B18u  /* RW rate_reduce_monitor_period µs（默认 4） */
#define YNRDMA_DCQCN_INC_US          0x0B1Cu  /* RW rpg_time_reset µs（默认 300） */
#define YNRDMA_DCQCN_INC_BYTES       0x0B20u  /* RW rpg_byte_reset 字节（默认 2097152 = 32767×64 B） */
#define YNRDMA_DCQCN_MIN_RATE        0x0B24u  /* RW rpg_min_rate Mb/s（默认 1） */
#define YNRDMA_DCQCN_LINE            0x0B28u  /* RW 线速 Mb/s（默认 400000） */
#define YNRDMA_DCQCN_STATUS          0x0B2Cu  /* RO [min(QP_NUM,32)-1:0] 当前被限速（credit=0）的 QP；S5 起 QP_NUM=128，STATUS_W=32 */
#define YNRDMA_DCQCN_QP              0x0B30u  /* RW 选择要读的 QP（0..127，S5 起扩到 128）*/
#define YNRDMA_DCQCN_QP_RC           0x0B34u  /* RO 选中 QP 的 RC（Mb/s） */
#define YNRDMA_DCQCN_QP_RT           0x0B38u  /* RO 选中 QP 的 RT（Mb/s） */
#define YNRDMA_DCQCN_QP_ALPHA        0x0B3Cu  /* RO 选中 QP 的 α（10 bit 小数，1023 = 1.0） */
#define YNRDMA_DCQCN_QP_CREDIT       0x0B40u  /* RO 选中 QP 的信用（1/2048 字节；0 = 等待） */
#define YNRDMA_DCQCN_QP_STATE        0x0B44u  /* RO [4:0]iT [5]cnp_seen [13:8]iB */
#define YNRDMA_DCQCN_QP_CNP          0x0B48u  /* RO 选中 QP 收到 CNP 的累计次数 */
#define YNRDMA_DCQCN_INIT_ALPHA      0x0B4Cu  /* RW α 初值（B6434，复位 1023）；写入即重载全部 QP（S5 起 128 个） */
#define YNRDMA_DCQCN_G               0x0B50u  /* RW g ×1024（B6434，复位 5，即 g = 5/1024） */
#define YNRDMA_DCQCN_MAX_HAI_F       0x0B54u  /* RW HAI 步长倍数上限（B6434，复位 1） */
#define YNRDMA_DCQCN_CNT(k)          (0x0B80u + 4u * (k))  /* RO 8 个 */
enum ynrdma_dcqcn_cnt {
	YNRDMA_DCQCN_CNT_RP_CNP     = 0,   /* 收到的 CNP 总数 */
	YNRDMA_DCQCN_CNT_RATE_DEC   = 1,   /* 执行降速的次数 */
	YNRDMA_DCQCN_CNT_RATE_INC   = 2,   /* 执行升速的次数 */
	YNRDMA_DCQCN_CNT_HAI        = 3,   /* 其中 HAI 的次数 */
	YNRDMA_DCQCN_CNT_FR         = 4,   /* 其中快速恢复（FR）的次数 */
	YNRDMA_DCQCN_CNT_STALL_TICK = 5,   /* 有 QP 因信用为 0 不能发的拍数 */
};
#define YNRDMA_DCQCN_CLEAR           0x0BFCu  /* WO 写任意值清全部计数 */

/* 组 C：TX 汇合与 RX 分流（共享，无 lane） */
#define YNRDMA_DBG_MERGE_BASE        0x0740u
#define   YNRDMA_DBG_MERGE_QDMA_STATE   0x00u /* [0]in_packet [1]port [2]priority */
#define   YNRDMA_DBG_MERGE_QDMA_ABORTS  0x04u /* 残包放弃累计（正常应为 0） */
#define   YNRDMA_DBG_MERGE_LANE_STATE   0x08u
#define   YNRDMA_DBG_MERGE_LANE_ABORTS  0x0Cu
#define   YNRDMA_DBG_RX_SPLIT_STATE     0x10u /* [0]payload_busy [1]owner */

/* ---------------- 编译期布局断言 ----------------
 * 这些结构体是主机内存里与 RTL 直接对接的格式，多一个字段就整条错位（不报错、只错数据）。
 * 内核（GNU C）与用户态（rdma-core 用 gcc/clang）两条编译路径都要能过，所以用
 * 标准 C11 的 _Static_assert，并给出 #error 兜底（避免老编译器把断言静默忽略）。 */
#if defined(__STDC_VERSION__) && (__STDC_VERSION__ >= 201112L)
#define YNRDMA_STATIC_ASSERT(cond, msg) _Static_assert(cond, msg)
#else
#define YNRDMA_STATIC_ASSERT(cond, msg) \
	typedef char ynrdma_static_assert_##__LINE__[(cond) ? 1 : -1]
#endif

YNRDMA_STATIC_ASSERT(sizeof(struct ynrdma_sq_wqe) == 64,  "ynrdma_sq_wqe 必须是 64 B");
YNRDMA_STATIC_ASSERT(sizeof(struct ynrdma_rq_wqe) == 32,  "ynrdma_rq_wqe 必须是 32 B");
YNRDMA_STATIC_ASSERT(sizeof(struct ynrdma_cqe)    == 32,  "ynrdma_cqe 必须是 32 B");
YNRDMA_STATIC_ASSERT(sizeof(struct ynrdma_qpc)    == 64,  "ynrdma_qpc 必须是 64 B");
YNRDMA_STATIC_ASSERT(sizeof(struct ynrdma_mpt)    == 32,  "ynrdma_mpt 必须是 32 B");
YNRDMA_STATIC_ASSERT(sizeof(struct ynrdma_cqc)    == 16,  "ynrdma_cqc 必须是 16 B");
YNRDMA_STATIC_ASSERT(sizeof(ynrdma_mtt)           == 8,   "ynrdma_mtt 必须是 8 B");

#endif /* YUANRDMA_HW_H */
