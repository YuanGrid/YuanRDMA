// roce_pkg.sv
// RoCEv2 引擎公共参数。寄存器和表项格式的权威定义在 code/rdmasw/include/yuanrdma_hw.h，
// 这里的常量必须与之一致。
`timescale 1ns/1ps
package roce_pkg;

    // 资源规格
    // S4：16 → 128。QPN_BASE 必须是 QP_NUM 的整数倍——roce_rx_parse 用 dest_qpn[QP_W-1:0]
    // 当 qp_index，128 时 128 % 128 == 0 成立，QPN 128..255 映到 index 0..127。
    localparam int QP_NUM      = 128;
    // QP 索引位宽（S1：参数化，QP_NUM=16 时 QP_W=4，与原来逐位相同）。扩 QP 时只改 QP_NUM。
    localparam int QP_W        = (QP_NUM > 1) ? $clog2(QP_NUM) : 1;
    // 引擎 lane 数 = 2^PKG_LANE_W（roce_top 的 LANES=4）。
    // **不能叫 LANE_W**：roce_top / roce_engine / roce_rx_demux / roce_rx_qpn_split / roce_pcie_hub 都
    // `import roce_pkg::*` 且各自声明 localparam LANE_W；只要模块在本地声明之前（例如端口表里）用到过
    // LANE_W，就等于先引用了包里的同名常量，Quartus 报 Error (13396) "already declared"（Verilator 不报）。
    localparam int PKG_LANE_W = 2;
    // S4：每 lane 只存 1/4 的 QP 项。lane 交错持有（qp_index[LANE_BITS-1:0] == lane），
    // 所以「qp 的 lane 局部索引」= qp 去掉低 LANE_BITS 位。凡按 lane 缩容的阵列/RAM 一律用
    // QP_LW 位局部索引；**QPC 读口的 rd_addr/rd_addr_q 例外，必须保持全局 QP_W 位**（消费方
    // 比的是全局 qp_index，改成局部索引会静默读到别的 QP 的 QPC）。
    localparam int LANE_BITS   = PKG_LANE_W;
    localparam int QP_LW       = (QP_W > LANE_BITS) ? QP_W - LANE_BITS : 1;
    localparam int LANE_QPS    = QP_NUM >> LANE_BITS;
    // QP 按 lane 分配：qp_index[PKG_LANE_W-1:0] == lane 编号。roce_tbl 的 QPC/SQ/RQ 状态只由
    // 属主 lane 持有（S2），非属主 lane 的这些项恒为 0，扫描/取指天然看不到它们。
    function automatic logic qp_owned(input logic [QP_W-1:0] qp, input logic [PKG_LANE_W-1:0] lane_id);
        qp_owned = (qp[PKG_LANE_W-1:0] == lane_id);
    endfunction
    // lane 局部索引（S4）：qp 去掉低 LANE_BITS 位。
    function automatic logic [QP_LW-1:0] qp_local(input logic [QP_W-1:0] qp);
        qp_local = qp[QP_W-1:LANE_BITS];
    endfunction
    // S6：CQ 16 → 64。CQ_W 随 CQ_NUM 走（16 时 4、64 时 6）。**不要在任何地方再写死 4**：
    // CQ 编号 N 与 N&15 撞号是最可能的事故模式（与 S4 的 QP68/QP4 同型：高位静默截断，
    // 编译与仿真都不报错，只是 CQE 写进了别的 CQ 的环）。定向台子 roce_cq64 钉住这一点。
    localparam int CQ_NUM      = 64;
    localparam int CQ_W        = (CQ_NUM > 1) ? $clog2(CQ_NUM) : 1;
    // QPC dw0 里 scq/rcq 各占 6 bit（见下方 qpc_scq/qpc_rcq）。CQ_NUM 再改（≥128）必须先改位段
    // 与 yuanrdma_hw.h 的 struct ynrdma_qpc，否则高位被静默截断。
    // package 里不能写 initial，所以做成函数，由 roce_tbl 在其 initial 里调用。
    localparam int CQ_FIELD_W  = 6;
    function automatic bit cq_field_fits();
        return CQ_W <= CQ_FIELD_W;
    endfunction
    localparam int MR_NUM      = 64;
    // S7：MTT 8192 → 131072（16×）。每页 4 KB，单 MR 上限从 32 MiB 变 512 MiB。
    // **必须与 code/rdmasw/include/yuanrdma_hw.h 的 YNRDMA_MAX_MTT 同步**。
    // MTT_IDX_W / MTT_ADDR_W 在 roce_tbl 内部按本值派生（见该文件「MTT 池位宽」一节）：
    //   8192 → 13 / 12（与 S7 之前写死的值逐位相同），131072 → 17 / 16。
    // 池必须是 2 的幂，roce_tbl 的 initial 里有 $fatal 兜底。
    localparam int MTT_NUM     = 131072;
    localparam int QPN_BASE    = 128;   // S4：必须是 QP_NUM 的整数倍（见 8-9 行）

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
    // 组 C 挪到 0x7C0..0x7DC。判据是 `<=`，END 取组 C 窗口的最后一个字地址 0x7DC。
    // （B6444 曾在 0x7E0..0x7EC 加过写路径探针的控制字、END 扩到 0x7EC；该探针
    //   2026-11-17 按用户要求整体删除，END 收回 0x7DC。）
    localparam logic [19:0] REG_DBG_END        = 20'h007DC;
    // 拥塞控制寄存器窗口（2026-11-09）。地址表与 code/rdmasw/include/yuanrdma_hw.h 的 YNRDMA_* 一致。
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
    // RX 固定开销分解：每 core_clk 累计（用来测量每包拍数分布，见 RX 重传分析文档 §2.5）
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

    // SQ WQE opcode（主机写在 ynrdma_sq_wqe.dw0[3:0]，见 yuanrdma_hw.h enum ynrdma_wqe_op）
    localparam logic [3:0] WQE_WRITE     = 4'd0;
    localparam logic [3:0] WQE_WRITE_IMM = 4'd1;
    localparam logic [3:0] WQE_SEND      = 4'd2;
    localparam logic [3:0] WQE_SEND_IMM  = 4'd3;
    localparam logic [3:0] WQE_READ      = 4'd4;
    // UD 发送（G2.1 Step 2）。**这是 WQE 编码，不是线上 opcode**——UD 真正发到线上的
    // BTH opcode 是 OP_SEND_ONLY_UD(0x64) / OP_SEND_ONLY_UD_IMM(0x65)，由 roce_req 的
    // tx_opcode_of() 从这两个 WQE opcode 翻译出来。与 RC 的 WQE_SEND/WQE_SEND_IMM(2/3)
    // 是两套独立编码，不要因为「都是 SEND」就复用。
    // 取值必须与 yuanrdma_hw.h 的 YNRDMA_WQE_UD_SEND/YNRDMA_WQE_UD_SEND_IMM 一致。
    localparam logic [3:0] WQE_UD_SEND     = 4'd5;
    localparam logic [3:0] WQE_UD_SEND_IMM = 4'd6;

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

    // BTH opcode：UD（Unreliable Datagram，IBTA §9.8.5）。opcode 的高 3 位是传输类型
    // 编码，UD = 011，所以 SEND_ONLY = 0b011_00100 = 0x64、SEND_ONLY_IMM = 0b011_00101 = 0x65。
    // UD 的 BTH 后面跟 **DETH 8 B**（Q_Key 4 B + 源 QPN 3 B + 1 B 保留）而不是 RETH。
    // 注意这与 RC 的 OP_SEND_ONLY(0x04)/OP_SEND_ONLY_IMM(0x05) 是**两套不同的 opcode**，
    // 0x64 的 bit2=1 让两者不会混淆（见 op_is_ud 的判据）。
    localparam logic [7:0] OP_SEND_ONLY_UD     = 8'h64;
    localparam logic [7:0] OP_SEND_ONLY_UD_IMM = 8'h65;

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
    localparam logic [7:0] WCS_LOC_OP_ERR    = 8'd3;   /* IBV_WC_LOC_OP_ERR（本地操作错误） */
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
        logic [QP_W-1:0] qp_index;
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
        // UD（0x64/0x65）的 DETH。RC 包这些位恒 0。RoCEv2 的 DETH 紧跟在 BTH 后（字节 54），
        // 带 Imm 时 ImmDt 在 62。RoCEv2 线上**没有 40 B GRH**（那是 RoCEv1 / InfiniBand 的格式），
        // 所以这里不需要 has_grh 或 GRH 字段本身——见 roce_resp.sv 里 UD CQE 的说明。
        logic        has_deth;
        logic [31:0] deth_qkey;           // 主机序
        logic [23:0] deth_src_qp;
        // UD 合成 GRH 用的源 IPv4（主机序，取 IPv4 头字节 26..29）。只有 UD 有意义，RC 恒 0。
        // 为什么需要它：IB 语义下 UD 收到的 CQE 若带 IBV_WC_GRH，接收缓冲**前 40 B 必须是 GRH**，
        // 而那 40 B 是由接收侧从 IPv4/UDP 头合成出来的（RoCEv2 线上没有 GRH）。GRH 里的
        // Source GID 低 32 位就是 IPv4 源地址（GRH 的 GID = ::ffff:<IPv4>），所以必须把源 IP
        // 从解析级带上来；rx_hdr_t 以前只有目的侧信息，合成不出来。
        logic [31:0] src_ip;
        logic [12:0] payload_length;      // 0..4096
        logic        bad;          // 头部不合法（长度、opcode）
    } rx_hdr_t;


    // QPC 字段（512 bit，dw i 在 [i*32 +: 32]），布局见 yuanrdma_hw.h struct ynrdma_qpc
    //
    // S6 改了 dw0 的位域布局（CQ 4 bit → 6 bit）。新旧对照（dw0 内）：
    //     位      旧（S4 及以前）        新（S6）
    //     [2:0]   state                  state               不变
    //     [5:3]   pmtu                   pmtu                不变（roce_resp 的 {qpc_rd_data, 3'd0} 仍成立）
    //     [11:8]  send_cq (4 bit)        ——                  旧位段作废
    //     [11:6]  ——                     send_cq (6 bit)
    //     [15:12] recv_cq (4 bit)        ——                  旧位段作废
    //     [17:12] ——                     recv_cq (6 bit)
    //     [16]    remote_write           ——                  旧位段作废
    //     [17]    remote_read            ——                  旧位段作废
    //     [18]    ——                     remote_write
    //     [19]    ——                     remote_read
    //     [20]    ——                     remote_atomic（原先无对应位，MPT 权限才是权威）
    //     [21]    ——                     qp_type（0 = RC，1 = UD；G2.1 加）
    //     [31:22] 保留                   ——                  保留
    // 跨 RTL / 内核 / provider / 台子的契约。改这里必须同步改：
    //   code/rdmasw/include/yuanrdma_hw.h（struct ynrdma_qpc 的 dw0 注释）
    //   code/kernel/yuanrdma/yuanrdma_verbs.c（create_qp 拼 dw0、modify_qp 掩码）
    //   仿真共享库 roce_hw.py（pack_qpc）
    // 内核与 provider 都不看 remote_write/remote_read 的这位（权限走 MPT），
    // RTL 也没有消费方（qpc_rwrite/qpc_rread 无引用）——它们只是记录，跟着上面两项一起挪即可。
    function automatic logic [31:0] qpc_dw(input logic [511:0] qp_context, input int dword);
        return qp_context[dword*32 +: 32];
    endfunction
    function automatic logic [2:0]  qpc_state  (input logic [511:0] qp_context); return qp_context[2:0];        endfunction
    function automatic logic [2:0]  qpc_pmtu   (input logic [511:0] qp_context); return qp_context[5:3];        endfunction
    // CQ 位段用**固定**切片，不写成 `[11 -: CQ_W]`：后者会让改 CQ_NUM 静默挪动 QPC 布局，
    // 而 QPC 布局是跨 RTL/内核/provider 的契约，必须只有一处（这里）决定它。
    // 下面的 elaboration 检查把「CQ_NUM 与位段宽度」钉在一起，改一忘一在编译期就报错。
    function automatic logic [5:0]  qpc_scq    (input logic [511:0] qp_context); return qp_context[11:6];       endfunction
    function automatic logic [5:0]  qpc_rcq    (input logic [511:0] qp_context); return qp_context[17:12];      endfunction
    function automatic logic        qpc_rwrite (input logic [511:0] qp_context); return qp_context[18];         endfunction
    function automatic logic        qpc_rread  (input logic [511:0] qp_context); return qp_context[19];         endfunction
    /* QP 类型（G2.1）：1 = UD、0 = RC。RTL 用它把「WQE opcode 是 UD」与「QP 本身是 UD」
     * 分开校验 —— 只看 WQE opcode 的话，RC QP 里混一条 UD WQE 就直接发出 0x64，而
     * 驱动侧没有 UD/RC 开关，运行期完全靠这一位；反过来 UD QP 发 RC WQE 也一样。
     * 取值只有 1 bit，不枚举 IBV_QPT_*：RTL 只需要区分「这个 QP 能不能发 UD」。
     * 跨层契约：yuanrdma_hw.h 的 ynrdma_qpc.dw0 注释、内核 create_qp 拼 dw0、
     * 仿真共享库 roce_hw.py 的 pack_qpc 三处必须同步。 */
    function automatic logic        qpc_is_ud  (input logic [511:0] qp_context); return qp_context[21];         endfunction
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


    // TX 包任务（每个任务一个包）。
    // S3（QP 128 改造）：组头所需的 QPC 字段（dmac/dip/sport/dqpn/ttl/tos）与 IP 校验和静态部分
    // 由**生成任务的一方**（roce_req / roce_resp / CNP）从自己已装载的上下文填进任务，roce_tx 不再
    // 按 qp_index 查 QPC——原来那里是 512 位 × QP_NUM 选 1 的组合选路，128 QP 时必挂。
    typedef struct packed {
        logic [QP_W-1:0] qp_index;
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
        // 组头字段（S3）：数据包/ACK 取 QPC 的 TOS；CNP 取 cnp_tos（NVIDIA 默认 cnp_dscp = 48，ECN=00）。
        logic [7:0]  tos;
        // S3 起 tos 恒有效（CNP 的覆盖由引擎在生成任务时直接填 cnp_tos），原 tos_valid 二选一已删。
        logic [7:0]  ttl;
        logic [47:0] dmac;
        logic [31:0] dip;
        logic [15:0] sport;
        logic [23:0] dqpn;
        // IPv4 头校验和中与包无关的部分：0x4000(DF) + {ttl,0x11} + 本端 IP + 目的 IP（20 位未折叠和）。
        // roce_tx 的 PREP 只再加 {0x45,tos} 与总长两项（与 B6433 的三操作数口径相同）。
        logic [19:0] csum_base;
        // 派生长度（B6439）：全部是 (opcode, payload_length) 的纯函数，由产生方算好随任务流过
        // 在途 FIFO，PREP 拍直接读寄存器，不再在 FIFO 出口做 4 项译码求和 + 两级加法 + 反相。
        // 见调试记录 §68：B6438 最差 core 路径 (u_inflight → add_4/5/87/86/88 →
        // u_skip_align|out_data) 就是这条链，−0.301 ns。
        logic [6:0]  header_length;         // 54 + extension_length
        logic [6:0]  header_skip;           // 128 - header_length，直接喂 skip_align.meta_skip
        logic [15:0] ip_total_length;       // 44 + extension_length + payload_length + pad_count
        logic [12:0] frame_length;          // 54 + extension_length + payload_length + pad_count
        // UD 的 DETH 载荷（G2.1 Step 2）。**仅 op_is_ud(opcode) 为真时有效，其它 opcode 恒 0。**
        // 目的 QPN 不在这里：复用上面的 dqpn（BTH Dest QP 本来就是 UD 的目的 QPN），
        // DETH 里只有 Q_Key 和源 QPN 需要另带（IBTA §9.8.5：DETH = Q_Key 4 B + src QP 3 B + 保留 1 B）。
        // roce_tx 在组头时把 deth_qkey 写 [432 +: 32]、deth_src_qp 写 [464 +: 24]、字节 61 保留 0。
        //
        // 【同步义务，调试记录 §76.5 的教训】加字段必须同时改这三处，漏一处必静默错位：
        //   1) roce_engine.sv 的 CNP 全字段赋值（cnp_job 的 '{...} 是 assignment pattern，
        //      少一个字段直接编译报错；但要显式补 deth_qkey: 32'd0, deth_src_qp: 24'd0 才算写清）；
        //   2) 仿真共享库 roce_hw.py 的 TX_JOB_FIELDS（顺序 + 位宽，新字段追加在**末尾**）；
        //   3) pack_tx_job() 的默认值（缺字段会被 pack_fields 当 0 填，但顺序错就是整条任务错位）。
        logic [31:0] deth_qkey;             // 主机序（组头时 swap32 成网络序）
        logic [23:0] deth_src_qp;           // 源 QPN，组头时 swap24
    } tx_job_t;

    function automatic logic [19:0] ip_csum_base(input logic [31:0] dip, input logic [7:0] ttl,
                                                 input logic [31:0] local_ip);
        return 20'h04000 + {4'd0, ttl, 8'h11} +
               {4'd0, local_ip[7:0], local_ip[15:8]} + {4'd0, local_ip[23:16], local_ip[31:24]} +
               {4'd0, dip[7:0], dip[15:8]} + {4'd0, dip[23:16], dip[31:24]};
    endfunction

    // tx_job 的派生长度（产生方调用；与 roce_tx 内部逐位等价）
    function automatic logic [6:0] tx_ext_length(input logic [7:0] opcode);
        tx_ext_length = (op_has_reth(opcode) ? 7'd16 : 7'd0) + (op_has_aeth(opcode) ? 7'd4 : 7'd0) +
                        (op_has_imm(opcode) ? 7'd4 : 7'd0) + (op_is_cnp(opcode) ? 7'd16 : 7'd0) +
                        (op_has_deth(opcode) ? 7'd8 : 7'd0);
    endfunction
    function automatic logic [1:0] tx_pad_count(input logic [12:0] payload_length);
        tx_pad_count = 2'(-payload_length);
    endfunction
    function automatic logic [6:0] tx_header_length(input logic [7:0] opcode);
        tx_header_length = 7'd54 + tx_ext_length(opcode);
    endfunction
    function automatic logic [15:0] tx_ip_total_length(input logic [7:0] opcode, input logic [12:0] payload_length);
        tx_ip_total_length = 16'd44 + {9'd0, tx_ext_length(opcode)} + {3'd0, payload_length} +
                             {14'd0, tx_pad_count(payload_length)};
    endfunction
    function automatic logic [12:0] tx_frame_length(input logic [7:0] opcode, input logic [12:0] payload_length);
        tx_frame_length = 13'd54 + {6'd0, tx_ext_length(opcode)} + payload_length +
                          {11'd0, tx_pad_count(payload_length)};
    endfunction

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
               (opcode == OP_WRITE_LAST_IMM) || (opcode == OP_WRITE_ONLY_IMM) ||
               (opcode == OP_SEND_ONLY_UD_IMM);
    endfunction
    // UD：BTH 后跟 DETH 8 B（不是 RETH）。判据只认这两个 opcode，**不要**写成
    // `opcode[7:5] == 3'b011`：0x60..0x67 里还有 RDMA WRITE_ONLY 等 UD 变体，本引擎 Step 1
    // 只支持 SEND_ONLY / SEND_ONLY_IMM，其余必须落到 bad 帧而不是被当 SEND 收下。
    function automatic logic op_is_ud(input logic [7:0] opcode);
        return (opcode == OP_SEND_ONLY_UD) || (opcode == OP_SEND_ONLY_UD_IMM);
    endfunction
    function automatic logic op_has_deth(input logic [7:0] opcode);
        return op_is_ud(opcode);
    endfunction
    // CNP 的 BTH 后面跟 16 B 保留字段（不是 RETH/AETH），长度与 READ RESP 的 AETH 不同。
    function automatic logic op_is_cnp(input logic [7:0] opcode);
        return opcode == OP_CNP;
    endfunction

endpackage
