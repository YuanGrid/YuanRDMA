// roce_pkg.sv
// RoCEv2 引擎公共参数。寄存器和表项格式的权威定义在 code/rdmasw/include/yuanrdma_hw.h，
// 这里的常量必须与之一致。
`timescale 1ns/1ps
package roce_pkg;

    // 资源规格
    localparam int QP_NUM      = 16;
    localparam int CQ_NUM      = 16;
    localparam int MR_NUM      = 64;
    localparam int MTT_NUM     = 8192;
    localparam int QPN_BASE    = 16;

    localparam logic [31:0] ID_MAGIC   = 32'h524f_4345;
    localparam logic [31:0] HW_VERSION = 32'h0001_0000;

    // CSR 偏移（AVMM slot 内 20 bit 字节地址）
    localparam logic [19:0] REG_ID         = 20'h00000;
    localparam logic [19:0] REG_VERSION    = 20'h00004;
    localparam logic [19:0] REG_CAPS       = 20'h00008;
    localparam logic [19:0] REG_CTRL       = 20'h0000C;
    localparam logic [19:0] REG_STATUS     = 20'h00010;
    localparam logic [19:0] REG_MAC_LO     = 20'h00014;
    localparam logic [19:0] REG_MAC_HI     = 20'h00018;
    localparam logic [19:0] REG_IPV4       = 20'h0001C;
    localparam logic [19:0] REG_CORE_CLOCK = 20'h00020; // RO 引擎 core 时钟 MHz
    localparam logic [19:0] REG_CMD_DATA   = 20'h00100; // 16 x 32 bit
    localparam logic [19:0] REG_CMD        = 20'h00140;
    localparam logic [19:0] REG_CMD_STATUS = 20'h00144;
    localparam logic [19:0] REG_CNT        = 20'h00200; // CNT_NUM x 32 bit
    localparam logic [19:0] REG_DT_SRC_LO  = 20'h00300;
    localparam logic [19:0] REG_DT_SRC_HI  = 20'h00304;
    localparam logic [19:0] REG_DT_DST_LO  = 20'h00308;
    localparam logic [19:0] REG_DT_DST_HI  = 20'h0030C;
    localparam logic [19:0] REG_DT_LEN     = 20'h00310;
    localparam logic [19:0] REG_DT_REPEAT  = 20'h00314;
    localparam logic [19:0] REG_DT_CTRL    = 20'h00318;
    localparam logic [19:0] REG_DT_STATUS  = 20'h0031C;
    localparam logic [19:0] REG_DT_CYCLES  = 20'h00320;
    // 调试（2026-10-24 加，BAS/RX 卡死定位用）
    localparam logic [19:0] REG_DBG_BAS_STICKY = 20'h00400; // RO/W1C 见 roce_bas_mon.sv
    localparam logic [19:0] REG_DBG_BAS_LIVE   = 20'h00404; // RO 当前 valid/ready 电平
    localparam logic [19:0] REG_DBG_RX_STATE   = 20'h00410; // RO [3:0]resp main_state [8]disp busy [9]disp owner [23:16]staging 占用
    localparam logic [19:0] REG_SOFT_RST       = 20'h00414; // W 触发数据通路软复位；RO [0]=复位进行中
    // 扩展调试寄存器（2026-10-25 加，卡死现场定位用，地址表见 roce_debug.sv 文件头）
    // B6396 起分三组：0x0500..（共享/旧地址别名）、0x0600..（RX lane）、0x0680..（RDMA core lane）、
    // 0x0740..（TX 汇合与 RX 分流）。END 必须覆盖到最后一条，否则 CSR 侧不会把读请求
    // 转给 roce_debug，那些地址读成 0xdeadbeef，看起来像"镜像没更新"。
    localparam logic [19:0] REG_DBG_BASE       = 20'h00500;
    // B6405 起的上界：组 A 到 0x640、组 B 到 0x780（0x680 + 0x40*LANES，LANES=4）、
    // 组 C 挪到 0x7C0..0x7E0。判据是 `<=`，END 取组 C 窗口的最后一个字地址 0x7DC。
    localparam logic [19:0] REG_DBG_END        = 20'h007DC;
    // 拥塞控制寄存器窗口（2026-11-09）。地址表与 code/rdmasw/include/yuanrdma_hw.h 的 FROCE_* 一致。
    //   0x0800..0x09FC  PFC 控制器（roce_pfc.sv）
    //   0x0A00..0x0AFC  ECN / CNP（NP 侧）
    //   0x0B00..0x0BFC  DCQCN（RP 侧）
    // 选 0x0800 起：避开调试窗口（<= 0x7DC）与门铃（0x1000 起）。
    localparam logic [19:0] REG_CC_BASE        = 20'h00800;
    localparam logic [19:0] REG_PFC_BASE       = 20'h00800;
    localparam logic [19:0] REG_PFC_END        = 20'h009FC;
    localparam logic [19:0] REG_CNP_BASE       = 20'h00A00;
    localparam logic [19:0] REG_CNP_END        = 20'h00AFC;
    localparam logic [19:0] REG_DCQCN_BASE     = 20'h00B00;
    localparam logic [19:0] REG_DCQCN_END      = 20'h00BFC;
    localparam logic [19:0] REG_ACC_BASE       = 20'h00C00;   // 每 lane 8 字的 access error 快照（B6433）
    localparam logic [19:0] REG_ACC_END        = 20'h00C7C;
    localparam logic [19:0] REG_CC_END         = 20'h00BFC;
    localparam logic [19:0] DB_SQ          = 20'h01000;
    localparam logic [19:0] DB_RQ          = 20'h01004;
    localparam logic [19:0] DB_CQ          = 20'h01008;

    // 表编号（REG_CMD[27:24]）
    localparam logic [3:0] TBL_QPC = 4'd1;
    localparam logic [3:0] TBL_MPT = 4'd2;
    localparam logic [3:0] TBL_MTT = 4'd3;
    localparam logic [3:0] TBL_CQC = 4'd4;

    // 计数器编号（与 enum ynrdma_cnt 一致）
    localparam int CNT_TX_PKTS       = 0;
    localparam int CNT_RX_PKTS       = 1;
    localparam int CNT_RX_ICRC_ERR   = 2;
    localparam int CNT_RX_DROP       = 3;
    localparam int CNT_RX_BAD_QP     = 4;
    localparam int CNT_RX_DUP        = 5;
    localparam int CNT_RX_SEQ_ERR    = 6;
    localparam int CNT_TX_ACK        = 7;
    localparam int CNT_TX_NAK        = 8;
    localparam int CNT_RX_ACK        = 9;
    localparam int CNT_RX_NAK        = 10;
    localparam int CNT_RETX_TIMEOUT  = 11;
    localparam int CNT_RETX_NAK      = 12;
    localparam int CNT_TX_RNR_NAK    = 13;
    localparam int CNT_RX_RNR_NAK    = 14;
    localparam int CNT_CQE           = 15;
    localparam int CNT_CQ_OVERFLOW   = 16;
    localparam int CNT_RX_ACCESS_ERR = 17;
    localparam int CNT_BAS_AW_HS     = 18;  // 以下 5 个来自 roce_bas_mon（pcie_clk 域，格雷码跨域）
    localparam int CNT_BAS_W_LAST_HS = 19;
    localparam int CNT_BAS_B         = 20;
    localparam int CNT_BAS_AR_HS     = 21;
    localparam int CNT_BAS_R_LAST    = 22;
    // RX 固定开销分解：每 core_clk 累计（用来测量每包拍数分布，见 skill/rx-goback-n-analysis.md §2.5）
    // 读法：cnt/RX_PKTS 即均值。**必须取前后快照做差**：32 位 × 100 MHz = 43 s 回绕，
    // 直接拿绝对值除 RX_PKTS 会得到荒谬的小数（B6389 实测踩到 0.76 拍/包）。
    localparam int CNT_RESP_CYCLES      = 23; // roce_resp main_state != IDLE 的拍数
    // B6390：24 号从 CNT_DISP_BUSY_CYCLES 换成 CNT_PAGE_HIT。原 DISP_BUSY 已被 B6389 实测证否
    // （roce-log §25.3）：纯 WRITE 流量下它与 RESP_CYCLES 逐拍相等，因为 disp busy 窗口正好等于
    // resp 非 IDLE 窗口，差值恒 0，测不到任何东西。换成命中计数后可直接验收"首包也走页缓存"。
    localparam int CNT_PAGE_HIT         = 24; // roce_resp 页缓存命中次数（WRITE 路径）
    localparam int CNT_PAGE_MISS        = 25; // roce_resp 页缓存未命中（走真翻译）次数，只计 WRITE
    localparam int CNT_NUM              = 26;

    // QP 状态
    localparam logic [2:0] QPS_RESET = 3'd0;
    localparam logic [2:0] QPS_INIT  = 3'd1;
    localparam logic [2:0] QPS_RTR   = 3'd2;
    localparam logic [2:0] QPS_RTS   = 3'd3;
    localparam logic [2:0] QPS_ERR   = 3'd6;

    // SQ WQE opcode
    localparam logic [3:0] WQE_WRITE     = 4'd0;
    localparam logic [3:0] WQE_WRITE_IMM = 4'd1;
    localparam logic [3:0] WQE_SEND      = 4'd2;
    localparam logic [3:0] WQE_SEND_IMM  = 4'd3;
    localparam logic [3:0] WQE_READ      = 4'd4;

    // BTH opcode（RC）
    localparam logic [7:0] OP_SEND_FIRST      = 8'h00;
    localparam logic [7:0] OP_SEND_MIDDLE     = 8'h01;
    localparam logic [7:0] OP_SEND_LAST       = 8'h02;
    localparam logic [7:0] OP_SEND_LAST_IMM   = 8'h03;
    localparam logic [7:0] OP_SEND_ONLY       = 8'h04;
    localparam logic [7:0] OP_SEND_ONLY_IMM   = 8'h05;
    localparam logic [7:0] OP_WRITE_FIRST     = 8'h06;
    localparam logic [7:0] OP_WRITE_MIDDLE    = 8'h07;
    localparam logic [7:0] OP_WRITE_LAST      = 8'h08;
    localparam logic [7:0] OP_WRITE_LAST_IMM  = 8'h09;
    localparam logic [7:0] OP_WRITE_ONLY      = 8'h0A;
    localparam logic [7:0] OP_WRITE_ONLY_IMM  = 8'h0B;
    localparam logic [7:0] OP_READ_REQ        = 8'h0C;
    localparam logic [7:0] OP_READ_RESP_FIRST = 8'h0D;
    localparam logic [7:0] OP_READ_RESP_MID   = 8'h0E;
    localparam logic [7:0] OP_READ_RESP_LAST  = 8'h0F;
    localparam logic [7:0] OP_READ_RESP_ONLY  = 8'h10;
    localparam logic [7:0] OP_ACK             = 8'h11;
    // BTH opcode：CNP（IBTA Annex A17，RoCEv2 Congestion Notification Packet）。
    // 0x80 是 RC 的 CNP opcode（bit7=1 表示 congestion notification，bit6..0=0 表 RC）。
    localparam logic [7:0] OP_CNP             = 8'h81;   // 与 CX 实测一致（0x81 = F+BECN 置位形式）

    // AETH syndrome
    localparam logic [7:0] AETH_ACK        = 8'h1F; // 无效信用
    localparam logic [7:0] AETH_RNR_NAK    = 8'h20; // | timer
    localparam logic [7:0] AETH_NAK_SEQ    = 8'h60;
    localparam logic [7:0] AETH_NAK_INV    = 8'h61;
    localparam logic [7:0] AETH_NAK_ACCESS = 8'h62;
    localparam logic [7:0] AETH_NAK_OPERR  = 8'h63;

    // ibv_wc_opcode / ibv_wc_status（CQE dw0）
    localparam logic [7:0] WC_SEND           = 8'd0;
    localparam logic [7:0] WC_RDMA_WRITE     = 8'd1;
    localparam logic [7:0] WC_RDMA_READ      = 8'd2;
    localparam logic [7:0] WC_RECV           = 8'd128;
    localparam logic [7:0] WC_RECV_RDMA_IMM  = 8'd129;
    localparam logic [7:0] WCS_SUCCESS       = 8'd0;
    localparam logic [7:0] WCS_LOC_LEN_ERR   = 8'd1;
    localparam logic [7:0] WCS_LOC_PROT_ERR  = 8'd4;
    localparam logic [7:0] WCS_REM_INV_REQ   = 8'd9;
    localparam logic [7:0] WCS_REM_ACCESS    = 8'd10;
    localparam logic [7:0] WCS_REM_OP_ERR    = 8'd11;
    localparam logic [7:0] WCS_RETRY_EXC     = 8'd12;
    localparam logic [7:0] WCS_RNR_RETRY_EXC = 8'd13;

    localparam logic [15:0] ROCE_UDP_PORT = 16'd4791;

    // RX 解析结果（每帧一个）。数值字段已转成主机序；imm 保持线上字节序
    // （[7:0] 为线上第 0 字节，可原样写入 CQE）。RC 回包地址取自 QPC，不用报文源地址。
    typedef struct packed {
        logic [7:0]  opcode;
        logic        solicited;
        logic        ack_request;
        logic        becn;
        logic        ecn_congestion;           // IPv4 ECN == CE
        logic [23:0] dest_qpn;
        logic [3:0]  qp_index;
        logic        qp_valid;        // dqpn 落在本端 QP 范围内
        logic [23:0] psn;
        logic        has_reth;
        logic [63:0] reth_virtual_address;
        logic [31:0] reth_rkey;
        logic [31:0] reth_length;
        logic        has_aeth;
        logic [7:0]  aeth_syndrome;
        logic [23:0] aeth_msn;
        logic        has_immediate;
        logic [31:0] immediate;          // 线上字节序
        logic [12:0] payload_length;      // 0..4096
        logic        bad;          // 头部不合法（长度、opcode）
    } rx_hdr_t;


    // QPC 字段（512 bit，dw i 在 [i*32 +: 32]），布局见 yuanrdma_hw.h struct ynrdma_qpc
    function automatic logic [31:0] qpc_dw(input logic [511:0] qp_context, input int dword);
        return qp_context[dword*32 +: 32];
    endfunction
    function automatic logic [2:0]  qpc_state  (input logic [511:0] qp_context); return qp_context[2:0];        endfunction
    function automatic logic [2:0]  qpc_pmtu   (input logic [511:0] qp_context); return qp_context[5:3];        endfunction
    function automatic logic [3:0]  qpc_scq    (input logic [511:0] qp_context); return qp_context[11:8];       endfunction
    function automatic logic [3:0]  qpc_rcq    (input logic [511:0] qp_context); return qp_context[15:12];      endfunction
    function automatic logic        qpc_rwrite (input logic [511:0] qp_context); return qp_context[16];         endfunction
    function automatic logic        qpc_rread  (input logic [511:0] qp_context); return qp_context[17];         endfunction
    function automatic logic [23:0] qpc_dqpn   (input logic [511:0] qp_context); return qp_context[1*32 +: 24]; endfunction
    function automatic logic [31:0] qpc_dip    (input logic [511:0] qp_context); return qp_context[2*32 +: 32]; endfunction
    function automatic logic [47:0] qpc_dmac   (input logic [511:0] qp_context); return {qp_context[4*32 +: 16], qp_context[3*32 +: 32]}; endfunction
    function automatic logic [15:0] qpc_sport  (input logic [511:0] qp_context); return qp_context[4*32+16 +: 16]; endfunction
    function automatic logic [23:0] qpc_sq_psn (input logic [511:0] qp_context); return qp_context[5*32 +: 24]; endfunction
    function automatic logic [23:0] qpc_rq_psn (input logic [511:0] qp_context); return qp_context[6*32 +: 24]; endfunction
    function automatic logic [4:0]  qpc_timeout(input logic [511:0] qp_context); return qp_context[7*32 +: 5];  endfunction
    function automatic logic [2:0]  qpc_retry  (input logic [511:0] qp_context); return qp_context[7*32+5 +: 3]; endfunction
    function automatic logic [2:0]  qpc_rnr_rty(input logic [511:0] qp_context); return qp_context[7*32+8 +: 3]; endfunction
    function automatic logic [4:0]  qpc_min_rnr(input logic [511:0] qp_context); return qp_context[7*32+11 +: 5]; endfunction
    function automatic logic [7:0]  qpc_tos    (input logic [511:0] qp_context); return qp_context[7*32+16 +: 8]; endfunction
    function automatic logic [7:0]  qpc_ttl    (input logic [511:0] qp_context); return qp_context[7*32+24 +: 8]; endfunction
    function automatic logic [63:0] qpc_sq_base(input logic [511:0] qp_context); return {qp_context[9*32 +: 32], qp_context[8*32 +: 32]};  endfunction
    function automatic logic [63:0] qpc_rq_base(input logic [511:0] qp_context); return {qp_context[11*32 +: 32], qp_context[10*32 +: 32]}; endfunction
    function automatic logic [3:0]  qpc_sq_lg  (input logic [511:0] qp_context); return qp_context[12*32 +: 4];   endfunction
    function automatic logic [3:0]  qpc_rq_lg  (input logic [511:0] qp_context); return qp_context[12*32+4 +: 4]; endfunction
    function automatic logic [3:0]  qpc_max_rd (input logic [511:0] qp_context); return qp_context[12*32+8 +: 4]; endfunction
    function automatic logic [3:0]  qpc_max_drd(input logic [511:0] qp_context); return qp_context[12*32+12 +: 4]; endfunction
    function automatic logic [15:0] qpc_pd     (input logic [511:0] qp_context); return qp_context[12*32+16 +: 16]; endfunction
    // ibv_mtu 1..5 -> 256..4096 字节
    function automatic logic [12:0] pmtu_bytes (input logic [2:0] mtu_code); return 13'd128 << mtu_code; endfunction

    // 访问权限（MPT dw0[4:1]）
    localparam logic [3:0] ACC_LOCAL_WRITE  = 4'b0001;
    localparam logic [3:0] ACC_REMOTE_WRITE = 4'b0010;
    localparam logic [3:0] ACC_REMOTE_READ  = 4'b0100;

    // CQC
    typedef struct packed {
        logic        valid;
        logic [3:0]  log2_depth;
        logic [63:0] base;
    } cqc_t;


    // TX 包任务（每个任务一个包）。dqpn/dmac/dip/sport/tos/ttl 由 roce_tx 按 qp 查 QPC。
    typedef struct packed {
        logic [3:0]  qp_index;
        logic [7:0]  opcode;
        logic [23:0] psn;
        logic        ack_request;
        logic        solicited;
        logic [63:0] reth_virtual_address;       // 仅 RETH 类 opcode
        logic [31:0] reth_rkey;
        logic [31:0] reth_length;
        logic [7:0]  aeth_syndrome;      // 仅 AETH 类 opcode
        logic [23:0] aeth_msn;
        logic [31:0] immediate;           // 线上字节序
        logic [12:0] payload_length;           // payload 字节数，0..4096
        logic [63:0] physical_address0;           // payload 首字节物理地址
        logic [63:0] physical_page1;           // 跨页时下一页物理页地址
        // ECN/CNP（阶段 2）：CNP 的 DSCP 与数据包不同（NVIDIA 默认 cnp_dscp = 48），
        // 所以任务自带一个 TOS 覆盖。tos_valid = 0 时仍取 QPC 的 TOS（所有数据包都是这样）。
        logic [7:0]  tos;
        logic        tos_valid;
    } tx_job_t;

    function automatic logic op_has_reth(input logic [7:0] opcode);
        return (opcode == OP_WRITE_FIRST) || (opcode == OP_WRITE_ONLY) || (opcode == OP_WRITE_ONLY_IMM) ||
               (opcode == OP_READ_REQ);
    endfunction
    function automatic logic op_has_aeth(input logic [7:0] opcode);
        return (opcode == OP_READ_RESP_FIRST) || (opcode == OP_READ_RESP_LAST) ||
               (opcode == OP_READ_RESP_ONLY) || (opcode == OP_ACK);
    endfunction
    function automatic logic op_has_imm(input logic [7:0] opcode);
        return (opcode == OP_SEND_LAST_IMM) || (opcode == OP_SEND_ONLY_IMM) ||
               (opcode == OP_WRITE_LAST_IMM) || (opcode == OP_WRITE_ONLY_IMM);
    endfunction
    // CNP 的 BTH 后面跟 16 B 保留字段（不是 RETH/AETH），长度与 READ RESP 的 AETH 不同。
    function automatic logic op_is_cnp(input logic [7:0] opcode);
        return opcode == OP_CNP;
    endfunction

endpackage
