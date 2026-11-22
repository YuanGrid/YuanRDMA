// roce_top.sv
// RoCEv2 RDMA 引擎顶层。YuanRDMA 只例化本模块：
// - AVMM：插在 cdc2cfg 与 avm_config 之间，slot 0x017 归 RoCE CSR，其余透传；
// - BAS：经 pcie5x16_axis_dma 的打包总线读写主机内存；
// - TX：在 qdma_to_select_* 与 u2_gen0_qdma_select 口 0 之间做 2:1 包仲裁；
// - RX：旁路监听 rx_to_rcv_*[0/1]（不影响原 u7 通路）。
// 内部：roce_csr / roce_tbl（QPC MPT MTT CQC + 翻译）/ roce_dma_arb + roce_dma /
//       RX（front -> parse -> disp -> resp | req）/ roce_cq / TX（tx -> tx_out -> tx_mux）。
// Phase 1（B6394 起）：引擎拆成 LANES=2 个 roce_engine（QP 按 qp_index 奇偶绑定 lane），
//       共享 roce_pcie_hub（AXI ID = lane）/ roce_rx_qpn_split / roce_cq / TX 两级 2:1 汇合。
`default_nettype none
`timescale 1ns/1ps
`include "roce_bas_if.vh"
module roce_top
    import roce_pkg::*;
#(
    parameter int DATA_W         = 1024,
    parameter int USERF_W        = 7,
    parameter int CORE_CLOCK_MHZ = 250,
    // eth_mac_clk（F-tile o_clk_pll）频率，只用于 roce_pfc 的 µs tick（看门狗 / 最短保持）。
    // A 卡 B6420 STA：tx_clkout|ch23 = 415.04 MHz。仿真台 mac_clk 2.4 ns ≈ 417 MHz，同取 415。
    parameter int MAC_CLOCK_MHZ  = 415,
    // 软复位展宽拍数。0（默认）= CORE_CLOCK_MHZ * 5243（5.243 ms，上板值）；
    // 只给仿真用：台子 core 100 MHz 下默认要 52 万拍，cocotb 跑不动，tb_roce_sys 传 1000。
    parameter int SOFT_RST_HOLD_CYCLES = 0
)(
    // AVMM 时钟（clk250m，与 avm_config 同域）
    input  wire                   clk,
    input  wire                   rst_n,
    // 引擎 core 时钟（v1 用 clk100m：250 MHz 下时序不收敛）
    input  wire                   core_clk,
    // AVMM 上游（clk 域）
    input  wire  [27:0]           s_avm_addr,
    input  wire                   s_avm_read,
    input  wire                   s_avm_write,
    input  wire  [31:0]           s_avm_wdat,
    output wire                   s_avm_wait,
    output wire  [31:0]           s_avm_rdat,
    output wire                   s_avm_rvld,
    output wire  [1:0]            s_avm_rspo,
    output wire                   s_avm_wrsp,
    // AVMM 透传给 avm_config
    output wire  [27:0]           l_avm_addr,
    output wire                   l_avm_read,
    output wire                   l_avm_write,
    output wire  [31:0]           l_avm_wdat,
    input  wire                   l_avm_wait,
    input  wire  [31:0]           l_avm_rdat,
    input  wire                   l_avm_rvld,
    input  wire  [1:0]            l_avm_rspo,
    input  wire                   l_avm_wrsp,
    // PCIe（pcie_app_clk）
    input  wire                   pcie_clk,
    input  wire                   pcie_rst_n,
    output wire [`BAS_M2S_W-1:0]  bas_m2s,
    input  wire [`BAS_S2M_W-1:0]  bas_s2m,
    // MAC（eth_mac_clk）
    input  wire                   mac_clk,
    input  wire                   mac_rst_n,
    input  wire                   link_up,
    // PFC：eth400g 输出的 rx_pfc[8:0]（F-tile o_rx_pause / o_rx_pfc，eth_mac_clk 域电平，[8]=802.3x）。
    // 2026-11-09 起由 roce_pfc 统一处理（收方向准入 + 发方向 XOFF 生成），见 roce_pfc.sv 文件头。
    input  wire  [8:0]            rx_pfc,
    // 本引擎自动生成的 XOFF（eth_mac_clk 域）：{i_tx_pause, i_tx_pfc[7:0]}。
    // YuanRDMA 里与 system_config 的软件位 tx_pfc（REG 0x054，强制 XOFF 调试用）相或后进 MAC。
    output wire  [8:0]            tx_pfc,
    // TX：原 QDMA 流进，仲裁后出
    input  wire                   qdma_tvalid,
    input  wire  [DATA_W-1:0]     qdma_tdata,
    input  wire  [USERF_W-1:0]    qdma_tusef,
    input  wire                   qdma_tlast,
    output wire                   qdma_tready,
    output wire                   tx_tvalid,
    output wire  [DATA_W-1:0]     tx_tdata,
    output wire  [USERF_W-1:0]    tx_tusef,
    output wire                   tx_tlast,
    input  wire                   tx_tready,
    // RX：两路 rx_path_avst 输出（只监听）
    input  wire  [1:0]            rx_tvalid,
    input  wire  [2*DATA_W-1:0]   rx_tdata,
    input  wire  [13:0]           rx_tempty,
    input  wire  [5:0]            rx_tuerr,
    input  wire  [1:0]            rx_tlast,
    // 调试观测（eth_mac_clk 域，顶层采集；位段见 roce_debug.sv 的 mac_debug 端口）
    //   [7:0]   tx_valid   {gap_to_mac, reg_to_h2l, segm_to_reg, select_to_segm,
    //                       qdma_to_select, qdma_to_regslice, qdma_h2d, 1'b0}
    //   [15:8]  tx_ready   [23:16] tx_last（同序）
    //   [28:24] axis_select.debug_state   [38:29] axis_to_segm.debug_state
    //   [41:39] rx_valid   [44:42] rx_ready
    //   [76:45] lane0 fifo [108:77] lane1 fifo [122:109] rx_mux_nto1 标志
    input  wire  [136:0]          mac_debug,
    // BAS 打包总线观测（pcie_clk 域，顶层从 pcie5_bas_m2s/s2m 直采）
    //   [63:0]  ARADDR  [71:64] ARLEN  [75:72] {ARREADY,ARVALID,RREADY,RVALID}
    //   [107:76] AWADDR[31:0]
    input  wire  [107:0]          pcie_debug
);
    // core 域复位：rst_n 同步到 core_clk
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    reg  [2:0] core_reset_sync;
    always @(posedge core_clk or negedge rst_n)
        if (!rst_n) core_reset_sync <= 3'b000;
        else        core_reset_sync <= {core_reset_sync[1:0], 1'b1};
    wire core_rst_n = core_reset_sync[2];
    wire rst  = !core_rst_n;
    wire pcie_rst = !pcie_rst_n;
    wire mac_rst = !mac_rst_n;

    // ------------------------------------------------------------ 软复位展宽与分发
    // CSR 在 core_clk（A 型板 125 MHz，B6409 起）产生单拍 soft_rst；mac_clk（~195 MHz）和 pcie_clk
    // （500 MHz）都比它快，单拍脉冲跨过去同样能被采到，但为了让下游状态机看到足够宽
    // 的复位，这里统一展宽成 SOFT_RST_HOLD 个 core 周期。
    //
    // 2026-10-25：原先是 256 拍 = 2.56 us，yuancli 的轮询间隔是 2 ms，差了近 800 倍，
    // 上板只能读到 bit0=0，看起来像"复位没生效"。改成一拍级计数器、约 5.24 ms，
    // 保证软件观察窗口远大于一次 MMIO 往返；同时 roce_csr 里加了读清零的粘滞位，
    // 即使轮询错过窗口也能读到"复位发生过"。
    // 复位加宽不改变功能：所有下游都是同步复位，电平多持续几毫秒只是让它们多停在复位态。
    localparam int SOFT_RST_HOLD = (SOFT_RST_HOLD_CYCLES > 0) ? SOFT_RST_HOLD_CYCLES
                                                              : CORE_CLOCK_MHZ * 5243;   // 5.243 ms @ CORE_CLOCK_MHZ
    wire soft_rst;                      // 来自 roce_csr，单拍
    reg  [21:0] soft_rst_hold;
    wire       soft_rst_req = soft_rst | (soft_rst_hold != 22'd0);
    always @(posedge core_clk) begin
        if (rst)                    soft_rst_hold <= 22'd0;
        else if (soft_rst)          soft_rst_hold <= 22'(SOFT_RST_HOLD);
        else if (soft_rst_hold != 22'd0) soft_rst_hold <= soft_rst_hold - 22'd1;
    end

    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    reg [1:0] soft_rst_mac_sync;
    always @(posedge mac_clk) soft_rst_mac_sync <= {soft_rst_mac_sync[0], soft_rst_req};
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    reg [1:0] soft_rst_pcie_sync;
    always @(posedge pcie_clk) soft_rst_pcie_sync <= {soft_rst_pcie_sync[0], soft_rst_req};

    // 数据通路复位：硬复位 或 软复位。CSR 自身仍用 rst（软复位时保持 MAC/IP/CTRL）。
    //
    // B6417（250 MHz）：core 域 dp_rst 改成「寄存 + 按消费者复制」三级。
    // B6416 里 dp_rst = rst | soft_rst_req 是组合的：soft_rst_hold 22 位比较 → 或门 → 直接扇出到
    // 4 个 lane 全部同步清零端，走线 1.70 + 1.62 ns，11 702 个违例端点（第二大组，最差 −0.548）。
    // 现在：
    //   第 1 级 dp_rst_s1      ：一根寄存器，吃掉比较与或门；
    //   第 2 级 每消费者一份   ：每 lane / 每个共享模块一根（dont_merge），把长走线拆成「一根到一片」；
    //   第 3 级 消费者内部一份 ：roce_engine 里按子模块再复制一次（见 roce_engine.sv），
    //                           共享模块在这里同样补一级，保证**所有 core 域消费者同拍断言、同拍释放**
    //                           （否则 parse 比 engine 早一拍释放时，一帧头可能被复位中的 engine 吃掉）。
    // 复位晚 3 拍断言/释放对同步复位无功能影响：硬复位来自 rst_n 同步链，软复位本身展宽 5 ms，
    // 主机在释放后几微秒内都不会有表写/门铃到达。soft_rst_active 读回仍用未延迟的 soft_rst_req。
    reg dp_rst_s1;
    always @(posedge core_clk) dp_rst_s1 <= rst | soft_rst_req;
    wire dp_mac_rst  = mac_rst  | soft_rst_mac_sync[1];
    // B6419：MAC 域数据通路复位也做「寄存 + 按消费者复制」（同 core 域 dp_rst）。
    // B6418 tx_clkout：soft_rst_mac_sync[1] → lane0 u_tx_out.u_cdc 读指针（−0.060，走线 1.83 ns），
    // mac_rstn → u_rx_demux 各 lane FIFO 24 个端点（−0.022）。所有副本同出自 dp_mac_rst_s1、同一级，
    // 断言/释放同拍，只比原来晚 2 拍。u_rx_front 仍用未寄存的 dp_mac_rst：它的帧序号复位 mac_seq_rst
    // 必须与 rx_path_avst 同相位，数据通路复位与之的相对时序不动；rx_front 复位释放后 16 拍不收新帧，
    // 下游 demux 晚 2 拍释放不会丢帧。
    reg dp_mac_rst_s1;
    always @(posedge mac_clk) dp_mac_rst_s1 <= dp_mac_rst;
    (* dont_merge *) reg [LANES-1:0] dp_mac_rst_lane;
    (* dont_merge *) reg dp_mac_rst_demux, dp_mac_rst_mux01, dp_mac_rst_mux23, dp_mac_rst_lmux, dp_mac_rst_mux, dp_mac_rst_dbg;
    always @(posedge mac_clk) begin
        dp_mac_rst_lane  <= {LANES{dp_mac_rst_s1}};
        dp_mac_rst_demux <= dp_mac_rst_s1;
        dp_mac_rst_mux01 <= dp_mac_rst_s1;
        dp_mac_rst_mux23 <= dp_mac_rst_s1;
        dp_mac_rst_lmux  <= dp_mac_rst_s1;
        dp_mac_rst_mux   <= dp_mac_rst_s1;
        dp_mac_rst_dbg   <= dp_mac_rst_s1;
    end
    wire dp_pcie_rst_raw = pcie_rst | soft_rst_pcie_sync[1];

    // pcie 域复位本地再同步：原先把 dp_pcie_rst 一根长网直接驱动本模块全部 pcie_clk 寄存器
    // （hub + 每 lane 的 roce_dma 及其 FIFO）。4 lane 后端点翻倍，实测 pld_clkout 有 8 条
    // setup 违例的起点就是这根网，走线占 82%、WNS 几乎不动而 TNS 涨 34 倍——典型的
    // 「同类路径数量变多」而不是「某条路径变长」。
    //
    // 不用「异步置位、同步释放」：外部复位网接到异步清零端会让 STA 去查 recovery，
    // 长网照样过不去（试过，换来 recovery −0.067）。这里也不需要异步端——pcie_rst_n 来自
    // 顶层 generic_reset，已经同步到 pcie_app_clk（= 本模块 pcie_clk，STA 的 launch/latch
    // 都是 pld_clkout），soft_rst_pcie_sync 也已同步。纯同步打两拍即可，复位晚 2 拍断言
    // 对数据通路无影响。
    (* dont_merge *) reg [1:0] dp_pcie_rst_sync;
    always @(posedge pcie_clk)
        dp_pcie_rst_sync <= {dp_pcie_rst_sync[0], dp_pcie_rst_raw};
    wire dp_pcie_rst = dp_pcie_rst_sync[1];

    // ------------------------------------------------------------ AVMM 分流 + CSR
    wire [27:0] roce_address;
    wire        roce_read, roce_write, roce_wait, roce_read_valid, roce_write_response;
    wire [31:0] roce_write_data, roce_read_data;
    wire [1:0]  roce_response;

    roce_avm_split u_split (
        .upstream_address(s_avm_addr), .upstream_read(s_avm_read), .upstream_write(s_avm_write), .upstream_write_data(s_avm_wdat),
        .upstream_wait(s_avm_wait), .upstream_read_data(s_avm_rdat), .upstream_read_valid(s_avm_rvld), .upstream_response(s_avm_rspo),
        .upstream_write_response(s_avm_wrsp),
        .legacy_address(l_avm_addr), .legacy_read(l_avm_read), .legacy_write(l_avm_write), .legacy_write_data(l_avm_wdat),
        .legacy_wait(l_avm_wait), .legacy_read_data(l_avm_rdat), .legacy_read_valid(l_avm_rvld), .legacy_response(l_avm_rspo),
        .legacy_write_response(l_avm_wrsp),
        .roce_address(roce_address), .roce_read(roce_read), .roce_write(roce_write), .roce_write_data(roce_write_data),
        .roce_wait(roce_wait), .roce_read_data(roce_read_data), .roce_read_valid(roce_read_valid), .roce_response(roce_response), .roce_write_response(roce_write_response)
    );

    reg  [1:0]   link_up_sync;
    always @(posedge core_clk) link_up_sync <= {link_up_sync[0], link_up};

    // PFC 原始电平的 core 域副本（只给调试观测；准入用 roce_pfc 输出的 pfc_pause_core）。
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    reg  [8:0]   rx_pfc_sync1, rx_pfc_sync2, rx_pfc_core;

    always @(posedge core_clk) begin
        rx_pfc_sync1 <= rx_pfc;
        rx_pfc_sync2 <= rx_pfc_sync1;
        rx_pfc_core  <= rx_pfc_sync2;
    end

    wire         ctrl_enable;
    wire         pfc_gate_enable;   // 来自 roce_csr，= ~REG_CTRL[2]（PFC_GATE_DIS），复位后为 1
    wire [47:0]  local_mac;
    wire [31:0]  local_ip;
    wire         table_request, table_write_enable, table_ack, table_error;
    wire [3:0]   table_select;
    wire [23:0]  table_index;
    wire [511:0] table_write_data, table_read_data;
    wire         doorbell_sq_valid, doorbell_rq_valid, doorbell_cq_valid;
    wire [31:0]  doorbell_data;
    wire [63:0]  dma_test_source, dma_test_destination;
    wire [12:0]  dma_test_length;
    wire [31:0]  dma_test_repeat, dma_test_cycles;
    wire         dma_test_start, dma_test_busy, dma_test_done, dma_test_error;
    wire [31:0]  counter_rx_icrc_error, counter_rx_drop;
    wire [5*32-1:0] counter_bas_raw;   // u_bas_mon 原始输出（内部 ar_outstanding 仍用它）
    reg  [5*32-1:0] counter_bas_q;     // 出口打一拍，切断到 u_csr / u_debug 的长走线
    wire [5*32-1:0] counter_bas = counter_bas_q;
    wire [10:0]  debug_bas_sticky;
    wire [7:0]   debug_bas_live;
    wire         debug_bas_sticky_clear;
    wire         debug_resp_clear_pulse;   // roce_debug 写 0x0580 时出的一拍
    // 0x0400 的写 1 清与 0x0580 的写任意值清都要能清掉 roce_bas_mon 的 resp_sticky 源锁存；
    // debug_bas_sticky_clear 是 roce_csr 的 reg 输出，不能直接当 assign 左值，用这条 wire 或。
    wire         bas_sticky_clear_all = debug_bas_sticky_clear | debug_resp_clear_pulse;
    wire [3:0]   debug_resp_state;
    wire [2:0]   mux_debug_state;
    wire [1:0]   debug_disp_busy_owner;
    wire [9:0]   debug_staging_occupancy;
    wire [63:0]  counter_lane_frames;
    wire [63:0]  counter_lane_icrc_error;
    wire [63:0]  counter_lane_drop;
    wire [19:0]  debug_lane_staging;
    wire [19:0]  debug_lane_staging_peak;
    wire         lane_peak_clear;
    wire [31:0]  counter_merge_force;     // B6418：RX 合并顺序超时强制放行次数（正常恒 0）
    wire [31:0]  counter_merge_rebase;    // B6418：RX 合并空闲重新对齐序号次数（正常恒 0）
    wire [CNT_NUM-1:0] counter_increment;
    wire [7:0]    debug_ar_outstanding;
    wire [13:0]   dma_debug_state;
    wire [3:0]    debug_resp_sticky;
    wire [127:0]  req_debug_state;
    wire [9:0]    tx_debug_state;
    wire [6:0]    resp_debug_state;
    assign debug_resp_state = resp_debug_state[3:0];   // ROCE_DBG_RX_STATE 用的旧字段
    wire [2:0]    rx_parse_debug_state;
    wire [31:0]   debug_read_value;
    wire          debug_read_hit;
    wire [31:0]   csr_ext_read_value;      // debug 窗口与拥塞控制窗口的读数据二选一后给 roce_csr
    wire          csr_ext_read_hit;
    wire [8:0]    pfc_pause_core;          // roce_pfc 收方向生效 pause（core 域），给引擎做发送准入
    wire          debug_write_enable;
    wire [19:0]   debug_write_offset;
    wire [31:0]   debug_write_value;

    wire [27:0] csr_address;
    wire        csr_read, csr_write, csr_wait, csr_read_valid, csr_write_response;
    wire [31:0] csr_write_data, csr_read_data;
    roce_avm_cdc u_avm_cdc (
        .upstream_clk(clk), .upstream_rst_n(rst_n),
        .upstream_address(roce_address), .upstream_read(roce_read), .upstream_write(roce_write),
        .upstream_write_data(roce_write_data), .upstream_wait(roce_wait), .upstream_read_data(roce_read_data),
        .upstream_read_valid(roce_read_valid), .upstream_response(roce_response),
        .upstream_write_response(roce_write_response),
        .downstream_clk(core_clk), .downstream_rst_n(core_rst_n),
        .downstream_address(csr_address), .downstream_read(csr_read), .downstream_write(csr_write),
        .downstream_write_data(csr_write_data), .downstream_wait(csr_wait), .downstream_read_data(csr_read_data),
        .downstream_read_valid(csr_read_valid), .downstream_write_response(csr_write_response)
    );

    roce_csr #(.CORE_CLOCK_MHZ(CORE_CLOCK_MHZ)) u_csr (
        .clk(core_clk), .rst_n(core_rst_n),
        .upstream_address(csr_address), .upstream_read(csr_read), .upstream_write(csr_write), .upstream_write_data(csr_write_data),
        .upstream_wait(csr_wait), .upstream_read_data(csr_read_data), .upstream_read_valid(csr_read_valid), .upstream_response(),
        .upstream_write_response(csr_write_response),
        .ctrl_enable(ctrl_enable), .pfc_gate_enable(pfc_gate_enable), .soft_rst(soft_rst), .local_mac(local_mac), .local_ip(local_ip),
        .link_up(link_up_sync[1]),
        .table_request(table_request), .table_write_enable(table_write_enable), .table_select(table_select), .table_index(table_index),
        .table_write_data(table_write_data), .table_ack(table_ack), .table_error(table_error), .table_read_data(table_read_data),
        .doorbell_sq_valid(doorbell_sq_valid), .doorbell_rq_valid(doorbell_rq_valid), .doorbell_cq_valid(doorbell_cq_valid), .doorbell_data(doorbell_data),
        .counter_increment(counter_increment),
        .counter_rx_icrc_error(counter_rx_icrc_error), .counter_rx_drop(counter_rx_drop),
        .counter_bas(counter_bas), .debug_bas_sticky(debug_bas_sticky), .debug_bas_live(debug_bas_live),
        .debug_bas_sticky_clear(debug_bas_sticky_clear),
        .debug_rx_state({6'd0, debug_staging_occupancy, 6'd0, debug_disp_busy_owner, 4'd0, debug_resp_state}),
                                             // 6+10+6+2+4+4=32：staging 占 [25:16]（10 位），disp [9:8]，resp [3:0]
        .soft_rst_active(soft_rst_req),
        .debug_read_value(csr_ext_read_value), .debug_read_hit(csr_ext_read_hit),
        .debug_write_enable(debug_write_enable), .debug_write_offset(debug_write_offset),
        .debug_write_value(debug_write_value),
        .dma_test_source(dma_test_source), .dma_test_destination(dma_test_destination), .dma_test_length(dma_test_length), .dma_test_repeat(dma_test_repeat),
        .dma_test_start(dma_test_start), .dma_test_busy(dma_test_busy), .dma_test_done(dma_test_done), .dma_test_error(dma_test_error),
        .dma_test_cycles(dma_test_cycles)
    );

    // ------------------------------------------------------------ Phase 1：LANES 个引擎
    // 结构见 roce_engine.sv 文件头。
    // QP 按 qp_index 低位绑定 lane（qp_index[LANE_W-1:0] == LANE_ID）；
    // 表/doorbell 广播（engine 内按归属过滤）；CQ、BAS、RX 前端、TX 汇合、调试、计数在这里共享。
    //
    // B6405（分支 rdma_4lane_100mhz_2）：LANES 2 → 4，只做实例化，不带任何时序补救。
    // TX 汇合仍用未改动的 roce_tx_mux（固定 2:1），在顶层搭成树：
    //   lane0,lane1 → u_tx_mux_01    lane2,lane3 → u_tx_mux_23
    //   u_tx_mux_01,u_tx_mux_23 → u_lane_tx_mux → 再与 QDMA 经 u_tx_mux
    // 不做单级 5:1：mac_clk 下 1024 bit 的五选一过不了时序，而 2:1 + 输出寄存器片
    // 是 B6395/B6396 已经收敛过的路径。
    localparam int LANES  = 4;
    localparam int LANE_W = 2;
    localparam int CQC_W  = $bits(cqc_t);

    // ---- core 域复位第 2/3 级（第 1 级 dp_rst_s1 见上）
    // lane：第 2 级在这里，第 3 级在 roce_engine 内按子模块复制。
    // 共享模块（front/demux、每 lane 的 parse、cq、bas_mon/debug/计数合并）：2、3 级都在这里。
    (* dont_merge *) reg [LANES-1:0] dp_rst_lane;
    (* dont_merge *) reg [LANES-1:0] dp_rst_parse_s2, dp_rst_parse;
    (* dont_merge *) reg             dp_rst_front_s2, dp_rst_front;
    (* dont_merge *) reg             dp_rst_cq_s2,    dp_rst_cq;
    (* dont_merge *) reg             dp_rst_misc_s2,  dp_rst_misc;
    always @(posedge core_clk) begin
        dp_rst_lane     <= {LANES{dp_rst_s1}};
        dp_rst_parse_s2 <= {LANES{dp_rst_s1}};
        dp_rst_parse    <= dp_rst_parse_s2;
        dp_rst_front_s2 <= dp_rst_s1;
        dp_rst_front    <= dp_rst_front_s2;
        dp_rst_cq_s2    <= dp_rst_s1;
        dp_rst_cq       <= dp_rst_cq_s2;
        dp_rst_misc_s2  <= dp_rst_s1;
        dp_rst_misc     <= dp_rst_misc_s2;
    end

    // ---- 表：ack/error 取 lane 0（各 lane 表写时序逐拍一致）；QPC 回读选属主 lane
    wire [LANES-1:0]              lane_table_ack, lane_table_error;
    wire [LANES*512-1:0]          lane_table_read_data;
    reg  [LANE_W-1:0]             table_read_lane;
    always @(posedge core_clk)
        if (table_request) table_read_lane <= (table_select == TBL_QPC) ? table_index[LANE_W-1:0] : '0;
    assign table_ack       = lane_table_ack[0];
    assign table_error     = lane_table_error[0];
    assign table_read_data = lane_table_read_data[table_read_lane*512 +: 512];

    wire [LANES*32-1:0]           lane_qp_context_low;   // S3：每 lane 当前 QP 的 QPC dw0
    wire [LANES*CQ_NUM*CQC_W-1:0] lane_cqc_flat;
    wire [LANES*CQ_NUM-1:0]       lane_cq_reset;
    wire [CQ_NUM-1:0]             cq_reset = lane_cq_reset[0 +: CQ_NUM];
    cqc_t                         cqc [CQ_NUM];                             // CQC 只由主机写，各 lane 一致
    genvar ci;
    generate
        for (ci = 0; ci < CQ_NUM; ci = ci + 1) begin : gen_cqc
            assign cqc[ci] = lane_cqc_flat[ci*CQC_W +: CQC_W];
        end
    endgenerate

    // ---- BAS：每 lane 一个虚拟 BAS，hub 合并（AXI ID 低位 = lane）
    wire [LANES*`BAS_M2S_W-1:0]   lane_bas_m2s;
    wire [LANES*`BAS_S2M_W-1:0]   lane_bas_s2m;
    roce_pcie_hub #(.LANES(LANES)) u_pcie_hub (
        .pcie_clk(pcie_clk), .pcie_rst(dp_pcie_rst),
        .lane_m2s_flat(lane_bas_m2s), .lane_s2m_flat(lane_bas_s2m),
        .bas_m2s(bas_m2s), .bas_s2m(bas_s2m)
    );

    roce_bas_mon u_bas_mon (
        .pcie_clk(pcie_clk), .pcie_rst(dp_pcie_rst), .clk(core_clk), .rst(dp_rst_misc),
        .bas_m2s(bas_m2s), .bas_s2m(bas_s2m), .sticky_clear(bas_sticky_clear_all),
        .count_aw(counter_bas_raw[0*32 +: 32]), .count_w_last(counter_bas_raw[1*32 +: 32]), .count_b(counter_bas_raw[2*32 +: 32]),
        .count_ar(counter_bas_raw[3*32 +: 32]), .count_r_last(counter_bas_raw[4*32 +: 32]),
        .sticky(debug_bas_sticky), .live(debug_bas_live),
        .debug_ar_outstanding(debug_ar_outstanding),
        .debug_resp_sticky(debug_resp_sticky)
    );
    // ---- BAS 计数的边界寄存（时序 G0.4 第 2 处，单独拆出来合入）
    //
    // 违例来源：u_bas_mon → u_csr / u_debug，数据延迟 4.381 ns 里 2.934 是 IC，
    // 其中一跳从 X143 走到 X293（150 列、2.398 ns）。原因是 §65 的 LL_BAS_MON 把
    // u_bas_mon 钉在保留区右缘 (132,196)-(143,215)，而 u_debug / u_csr 在 X293..305
    // ——区域约束本身没错（它治的是 BAS 总线那一侧），错的是让计数器**组合**穿过这段距离。
    //
    // 这里在 u_bas_mon 出口打一拍：计数器是纯观测量（CSR 的 CNT_BAS_* 读回、0x0574 的
    // debug_wr_outstanding），晚一拍对读回没有任何影响（software 侧本来就是轮询）。
    // u_bas_mon 内部的 ar_outstanding 用的是它自己的 count_ar/count_r_last，仍走原始值，
    // 不受这一拍影响。
    always @(posedge core_clk) counter_bas_q <= counter_bas_raw;

    // ---- RX：front（mac_clk）-> demux（按 dest_qpn 分流，每 lane 各自过 CDC）
    //      -> 每 lane 一份 parse -> 对应 lane 的引擎
    //
    // B6407 方案 A：原来「单份 parse + roce_rx_qpn_split」有两个天花板——
    //   (1) HOL 阻塞：一个包进了忙 lane，整条共享流被堵住（§33.4 的 -q 4 不涨）；
    //   (2) 单条 CDC 102.4 Gb/s，`-q 4` 读需要的 116 Gb/s 永远到不了。
    // 现在分流放在 CDC 之前（mac_clk 域，首拍即可解出 dest_qpn），每 lane 独立过域、独立解析。
    localparam int HDR_W = $bits(rx_hdr_t);
    wire          rx_frame_valid, rx_frame_ready, rx_frame_last;
    wire [1023:0] rx_frame_data;
    wire [127:0]  rx_frame_keep;
    wire [LANES-1:0]       lane_frame_valid, lane_frame_ready, lane_frame_last;
    wire [LANES*1024-1:0]  lane_frame_data;
    wire [LANES*128-1:0]   lane_frame_keep;
    wire [3:0]             rx_demux_debug;
    // demux 每 lane 统计（B6408）：已在 core_clk 域（demux 内部格雷码跨过来），直接进 roce_debug
    wire [LANES*32-1:0]    rx_demux_lane_frames;
    wire [LANES*32-1:0]    rx_demux_lane_stall;
    wire [LANES*32-1:0]    rx_demux_lane_sop_stall;

    // demux 状态在 mac_clk 域，roce_debug 在 core_clk 域。只是观测值（sel 会随帧切换），
    // 两级寄存即可，与项目中其它调试同步口的处理一致。
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    reg [3:0] rx_demux_debug_sync1, rx_demux_debug_state;
    always @(posedge core_clk) begin
        rx_demux_debug_sync1  <= rx_demux_debug;
        rx_demux_debug_state  <= rx_demux_debug_sync1;
    end

    // rx_front 的 PFC 水位（mac 域，每 lane 每优先级）：直接进 roce_pfc
    wire [2*8*10-1:0]      rx_lane_occupancy;
    wire [2*8-1:0]         rx_lane_drop;

    roce_rx_front u_rx_front (
        .clk(core_clk), .rst(dp_rst_front), .mac_clk(mac_clk), .mac_rst(dp_mac_rst),
        // 帧序号只跟 MAC 硬复位走（与 rx_path_avst 同一个 mac_rst_n），不并软复位，见 roce_rx_front 文件头
        .mac_seq_rst(mac_rst),
        .config_enable(ctrl_enable), .config_ip(local_ip), .config_mac(local_mac),
        .rx_valid(rx_tvalid), .rx_data(rx_tdata), .rx_last_bytes(rx_tempty), .rx_error(rx_tuerr),
        .rx_last(rx_tlast),
        .out_valid(rx_frame_valid), .out_ready(rx_frame_ready), .out_data(rx_frame_data), .out_keep(rx_frame_keep), .out_last(rx_frame_last),
        .counter_icrc_error(counter_rx_icrc_error), .counter_drop(counter_rx_drop),
        .debug_staging_occupancy(debug_staging_occupancy),
        .counter_lane_frames(counter_lane_frames),
        .counter_lane_icrc_error(counter_lane_icrc_error),
        .counter_lane_drop(counter_lane_drop),
        .debug_lane_staging(debug_lane_staging),
        .debug_lane_staging_peak(debug_lane_staging_peak),
        .lane_peak_clear(lane_peak_clear),
        .counter_merge_force(counter_merge_force),
        .counter_merge_rebase(counter_merge_rebase),
        .lane_occupancy(rx_lane_occupancy),
        .lane_drop(rx_lane_drop)
    );

    // B6421 的 rx_front → rx_demux skid 已回退（B6423 基线取 B6420）：只多 1 拍延迟、0 违例但 core 余量没改善，
    // 未上板验证，按「以 B6420 为基线」的决定丢掉。
    roce_rx_demux #(.LANES(LANES), .DEPTH(64)) u_rx_demux (
        .mac_clk(mac_clk), .mac_rst(dp_mac_rst_demux),
        .in_valid(rx_frame_valid), .in_ready(rx_frame_ready),
        .in_data(rx_frame_data), .in_keep(rx_frame_keep), .in_last(rx_frame_last),
        .clk(core_clk), .rst(dp_rst_front),
        .lane_valid(lane_frame_valid), .lane_ready(lane_frame_ready),
        .lane_data(lane_frame_data), .lane_keep(lane_frame_keep), .lane_last(lane_frame_last),
        .debug_state(rx_demux_debug),
        .lane_frames(rx_demux_lane_frames),
        .lane_stall(rx_demux_lane_stall),
        .lane_sop_stall(rx_demux_lane_sop_stall)
    );

    // 每 lane 一份 parse：head/payload 各自的 valid/ready 直接对接该 lane 的引擎，
    // roce_rx_qpn_split 不再需要（分流已经在 demux 里完成）。
    wire [LANES-1:0]      lane_rx_header_valid, lane_rx_header_ready, lane_rx_payload_valid, lane_rx_payload_ready;
    wire [LANES*HDR_W-1:0] lane_rx_header;
    wire [LANES*1024-1:0] lane_rx_payload_data;
    wire [LANES-1:0]      lane_rx_payload_last;
    wire [LANES*3-1:0]    lane_rx_parse_debug;

    // B6422 的 parse → 引擎 payload skid 同样已回退（B6423 基线取 B6420）。
    genvar rx_lane;
    generate
        for (rx_lane = 0; rx_lane < LANES; rx_lane = rx_lane + 1) begin : gen_rx_parse
            roce_rx_parse u_rx_parse (
                .clk(core_clk), .rst(dp_rst_parse[rx_lane]),
                .in_valid(lane_frame_valid[rx_lane]), .in_ready(lane_frame_ready[rx_lane]),
                .in_data(lane_frame_data[rx_lane*1024 +: 1024]),
                .in_keep(lane_frame_keep[rx_lane*128 +: 128]),
                .in_last(lane_frame_last[rx_lane]),
                .rx_header_valid(lane_rx_header_valid[rx_lane]), .rx_header_ready(lane_rx_header_ready[rx_lane]),
                .rx_header(lane_rx_header[rx_lane*HDR_W +: HDR_W]),
                .out_valid(lane_rx_payload_valid[rx_lane]), .out_ready(lane_rx_payload_ready[rx_lane]),
                .out_data(lane_rx_payload_data[rx_lane*1024 +: 1024]), .out_keep(), .out_last(lane_rx_payload_last[rx_lane]),
                .debug_state(lane_rx_parse_debug[rx_lane*3 +: 3])
            );
        end
    endgenerate

    // 调试沿用单引擎时代的位段：固定看 lane 0 的 parse 状态
    assign rx_parse_debug_state = lane_rx_parse_debug[0 +: 3];

    // ---- 共享 CQ：客户端 = lane*2 + {0 resp, 1 req}；写回走产生该 CQE 的 lane 的 DMA
    localparam int CQ_CLIENTS = 2 * LANES;
    wire [CQ_CLIENTS-1:0]     cq_cqe_valid, cq_cqe_ready;
    // S6：每个客户端的 CQ 编号 CQ_W 位（与 roce_engine 的 resp/req_cqe_cq 宽度一致）。
    wire [CQ_CLIENTS*CQ_W-1:0] cq_cqe_cq;
    wire [CQ_CLIENTS*160-1:0] cq_cqe_data;
    wire                      cq_dma_request_valid, cq_dma_write_valid;
    wire [63:0]               cq_dma_address, cq_dma_page1;
    wire [12:0]               cq_dma_length;
    wire [1023:0]             cq_dma_data;
    wire [$clog2(CQ_CLIENTS)-1:0] cq_dma_client;
    wire [LANE_W-1:0]         cq_dma_lane = LANE_W'(cq_dma_client >> 1);
    wire [LANES-1:0]          lane_cq_dma_request_ready, lane_cq_dma_write_ready;
    wire                      event_cqe, event_cq_overflow;

    roce_cq #(.CLIENTS(CQ_CLIENTS)) u_cq (
        .clk(core_clk), .rst(dp_rst_cq), .cqc(cqc), .cq_reset(cq_reset),
        .doorbell_cq_valid(doorbell_cq_valid), .doorbell_data(doorbell_data),
        .cqe_valid(cq_cqe_valid), .cqe_ready(cq_cqe_ready), .cqe_cq_index(cq_cqe_cq), .cqe_data(cq_cqe_data),
        .dma_write_request_valid(cq_dma_request_valid), .dma_write_request_ready(lane_cq_dma_request_ready[cq_dma_lane]),
        .dma_write_request_address(cq_dma_address), .dma_write_request_page1(cq_dma_page1),
        .dma_write_request_length(cq_dma_length),
        .dma_write_valid(cq_dma_write_valid), .dma_write_ready(lane_cq_dma_write_ready[cq_dma_lane]),
        .dma_write_data(cq_dma_data), .dma_write_client(cq_dma_client),
        .event_cqe(event_cqe), .event_overflow(event_cq_overflow)
    );

    // ---- 每 lane 事件（[事件][lane]），后面合并进计数器
    localparam int EV_TX_PACKET = 0,  EV_RX_PACKET = 1,  EV_DUPLICATE = 2,  EV_SEQ_ERR   = 3;
    localparam int EV_TX_ACK    = 4,  EV_TX_NAK    = 5,  EV_RX_ACK    = 6,  EV_RX_NAK    = 7;
    localparam int EV_RX_RNR    = 8,  EV_RNR_NAK   = 9,  EV_RETX_TO   = 10, EV_RETX_NAK  = 11;
    localparam int EV_ACCESS    = 12, EV_BAD       = 13, EV_PAGE_HIT  = 14, EV_PAGE_MISS = 15;
    // ECN / CNP（阶段 2）：CE 标记计数与 CNP 发送数进 roce_cnp 的 0xA00 窗口，不进 0x0200 计数器。
    // 16..19 是拥塞控制事件：不进 0x0200 计数器窗口（它们有自己的 0xA00/0xB00 计数），
    // 但仍然走 lane_event 这一张表，所以 NEV 要覆盖到它们；gen_event_merge 只对前 16 个
    // 有意义的索引生成合并器（见下面的 EVENT_MERGE_NUM），其余直接读原始位。
    localparam int EV_ECN_MARK  = 16, EV_CNP_SENT  = 17, EV_CNP_HANDLED = 18, EV_CNP_IGNORED = 19;
    localparam int NEV          = 20;
    localparam int EVENT_MERGE_NUM = 16;
    wire [NEV-1:0][LANES-1:0] lane_event;
    wire [LANES*QP_NUM-1:0]   lane_rx_cnp_qp;       // 每个 lane 收到 CNP 的 QP（one-hot）
    wire [LANES*QP_NUM-1:0]   lane_tx_admit_qp;     // 每个 lane 准入发包的 QP（one-hot）
    wire [LANES*13-1:0]       lane_tx_admit_len;    // 准入事件的 payload 字节
    // DCQCN 的每 QP 速率闸门：由下面的 u_dcqcn 驱动，broadcast 给每个 lane 的 roce_req。
    // 声明放在 generate 之前，避免依赖「模块内声明可后置」这一点。
    wire [QP_NUM-1:0]         tx_rate_ready;

    wire [LANES-1:0]          lane_tx_valid, lane_tx_ready, lane_tx_last;
    wire [LANES*DATA_W-1:0]   lane_tx_data;
    wire [LANES*USERF_W-1:0]  lane_tx_last_bytes;
    wire [LANES*128-1:0]      lane_req_debug_state;
    wire [LANES*7-1:0]        lane_resp_debug_state;
    wire [LANES*10-1:0]       lane_tx_debug_state;
    wire [LANES*14-1:0]       lane_dma_debug_state;
    wire [LANES*2-1:0]        lane_disp_busy_owner;
    wire [LANES-1:0]          lane_dma_test_busy, lane_dma_test_done, lane_dma_test_error;
    wire [LANES*32-1:0]       lane_dma_test_cycles;

    genvar lane;
    generate
        for (lane = 0; lane < LANES; lane = lane + 1) begin : gen_lane
            roce_engine #(
                .DATA_W(DATA_W), .USERF_W(USERF_W), .CORE_CLOCK_MHZ(CORE_CLOCK_MHZ),
                .LANES(LANES), .LANE_ID(lane)
            ) u_engine (
                .core_clk(core_clk), .dp_rst(dp_rst_lane[lane]), .pcie_clk(pcie_clk), .dp_pcie_rst(dp_pcie_rst),
                .mac_clk(mac_clk), .dp_mac_rst(dp_mac_rst_lane[lane]),
                .rx_pfc(pfc_pause_core), .pfc_gate_enable(pfc_gate_enable),
                .resp_gate(pfc_resp_gate), .pause_mac(pfc_pause_mac), .egress_gate(pfc_egress_gate_mac),
                .egress_hold(lane_egress_hold[lane]),
                .cnp_grant(cnp_grant[lane]), .cnp_en(cnp_en), .cnp_np_en(cnp_np_en), .cnp_tos(cnp_tos),
                .cnp_becn(cnp_becn), .cnp_fecn(cnp_fecn),
                .cnp_request(cnp_request[lane]),
                .event_ecn_marked(lane_event[EV_ECN_MARK][lane]),
                .event_cnp_sent(lane_event[EV_CNP_SENT][lane]),
                .event_cnp_handled(lane_event[EV_CNP_HANDLED][lane]),
                .event_cnp_ignored(lane_event[EV_CNP_IGNORED][lane]),
                .event_rx_cnp_qp(lane_rx_cnp_qp[lane*QP_NUM +: QP_NUM]),
                .event_tx_admit_qp(lane_tx_admit_qp[lane*QP_NUM +: QP_NUM]),
                .event_tx_admit_length(lane_tx_admit_len[lane*13 +: 13]),
                .tx_rate_ready(tx_rate_ready),
                .local_mac(local_mac), .local_ip(local_ip),
                .table_request(table_request), .table_write_enable(table_write_enable),
                .table_select(table_select), .table_index(table_index), .table_write_data(table_write_data),
                .table_ack(lane_table_ack[lane]), .table_error(lane_table_error[lane]),
                .table_read_data(lane_table_read_data[lane*512 +: 512]),
                .debug_qp_context_low(lane_qp_context_low[lane*32 +: 32]),
                .cqc_flat(lane_cqc_flat[lane*CQ_NUM*CQC_W +: CQ_NUM*CQC_W]),
                .cq_reset(lane_cq_reset[lane*CQ_NUM +: CQ_NUM]),
                .doorbell_sq_valid(doorbell_sq_valid), .doorbell_rq_valid(doorbell_rq_valid), .doorbell_data(doorbell_data),
                .dma_test_source(dma_test_source), .dma_test_destination(dma_test_destination),
                .dma_test_length(dma_test_length), .dma_test_repeat(dma_test_repeat),
                .dma_test_start((lane == 0) ? dma_test_start : 1'b0),
                .dma_test_busy(lane_dma_test_busy[lane]), .dma_test_done(lane_dma_test_done[lane]),
                .dma_test_error(lane_dma_test_error[lane]), .dma_test_cycles(lane_dma_test_cycles[lane*32 +: 32]),
                .virt_bas_m2s(lane_bas_m2s[lane*`BAS_M2S_W +: `BAS_M2S_W]),
                .virt_bas_s2m(lane_bas_s2m[lane*`BAS_S2M_W +: `BAS_S2M_W]),
                .rx_header_valid(lane_rx_header_valid[lane]), .rx_header_ready(lane_rx_header_ready[lane]),
                .rx_header(lane_rx_header[lane*HDR_W +: HDR_W]),
                .rx_payload_valid(lane_rx_payload_valid[lane]), .rx_payload_ready(lane_rx_payload_ready[lane]),
                .rx_payload_data(lane_rx_payload_data[lane*1024 +: 1024]), .rx_payload_last(lane_rx_payload_last[lane]),
                .resp_cqe_valid(cq_cqe_valid[lane*2]),   .resp_cqe_ready(cq_cqe_ready[lane*2]),
                .resp_cqe_cq(cq_cqe_cq[(lane*2)*CQ_W +: CQ_W]), .resp_cqe_data(cq_cqe_data[(lane*2)*160 +: 160]),
                .req_cqe_valid(cq_cqe_valid[lane*2+1]),  .req_cqe_ready(cq_cqe_ready[lane*2+1]),
                .req_cqe_cq(cq_cqe_cq[(lane*2+1)*CQ_W +: CQ_W]), .req_cqe_data(cq_cqe_data[(lane*2+1)*160 +: 160]),
                .cq_dma_write_request_valid(cq_dma_request_valid && (cq_dma_lane == LANE_W'(lane))),
                .cq_dma_write_request_ready(lane_cq_dma_request_ready[lane]),
                .cq_dma_write_request_address(cq_dma_address), .cq_dma_write_request_page1(cq_dma_page1),
                .cq_dma_write_request_length(cq_dma_length),
                .cq_dma_write_valid(cq_dma_write_valid && (cq_dma_lane == LANE_W'(lane))),
                .cq_dma_write_ready(lane_cq_dma_write_ready[lane]), .cq_dma_write_data(cq_dma_data),
                .tx_valid(lane_tx_valid[lane]), .tx_ready(lane_tx_ready[lane]),
                .tx_data(lane_tx_data[lane*DATA_W +: DATA_W]), .tx_last_bytes(lane_tx_last_bytes[lane*USERF_W +: USERF_W]),
                .tx_last(lane_tx_last[lane]),
                .event_tx_packet(lane_event[EV_TX_PACKET][lane]), .event_rx_packet(lane_event[EV_RX_PACKET][lane]),
                .event_duplicate(lane_event[EV_DUPLICATE][lane]), .event_sequence_error(lane_event[EV_SEQ_ERR][lane]),
                .event_tx_ack(lane_event[EV_TX_ACK][lane]), .event_tx_nak(lane_event[EV_TX_NAK][lane]),
                .event_rx_ack(lane_event[EV_RX_ACK][lane]), .event_rx_nak(lane_event[EV_RX_NAK][lane]),
                .event_rx_rnr(lane_event[EV_RX_RNR][lane]), .event_rnr_nak(lane_event[EV_RNR_NAK][lane]),
                .event_retransmit_timeout(lane_event[EV_RETX_TO][lane]), .event_retransmit_nak(lane_event[EV_RETX_NAK][lane]),
                .event_access_error(lane_event[EV_ACCESS][lane]), .event_bad(lane_event[EV_BAD][lane]),
                .event_page_hit(lane_event[EV_PAGE_HIT][lane]), .event_page_miss(lane_event[EV_PAGE_MISS][lane]),
                .dbg_access_snapshot(acc_snapshot[lane*8*32 +: 8*32]),
                .dbg_access_snapshot_clr(acc_snapshot_clr),
                .req_debug_state(lane_req_debug_state[lane*128 +: 128]),
                .resp_debug_state(lane_resp_debug_state[lane*7 +: 7]),
                .tx_debug_state(lane_tx_debug_state[lane*10 +: 10]),
                .dma_debug_state(lane_dma_debug_state[lane*14 +: 14]),
                .debug_disp_busy_owner(lane_disp_busy_owner[lane*2 +: 2])
            );
        end
    endgenerate

    assign dma_test_busy   = lane_dma_test_busy[0];
    assign dma_test_done   = lane_dma_test_done[0];
    assign dma_test_error  = lane_dma_test_error[0];
    assign dma_test_cycles = lane_dma_test_cycles[0 +: 32];

    // 调试寄存器沿用单引擎时代的位段，观测对象固定为 lane 0
    assign req_debug_state       = lane_req_debug_state[0 +: 128];
    assign resp_debug_state      = lane_resp_debug_state[0 +: 7];
    assign tx_debug_state        = lane_tx_debug_state[0 +: 10];
    assign dma_debug_state       = lane_dma_debug_state[0 +: 14];
    assign debug_disp_busy_owner = lane_disp_busy_owner[0 +: 2];

    // ---- TX 汇合：先两两 2:1（u_tx_mux_01 / u_tx_mux_23），两棵子树再 2:1（u_lane_tx_mux），
    //      最后与 QDMA 2:1（u_tx_mux）。每一级都是 mac_clk 包级轮询，包内不切换，
    //      所以级联不改变公平性。反压逐级回填，任一级没接回去整条 TX 都会挂死。
    wire               pair01_tx_valid, pair01_tx_ready, pair01_tx_last;
    wire [DATA_W-1:0]  pair01_tx_data;
    wire [USERF_W-1:0] pair01_tx_last_bytes;
    wire               pair23_tx_valid, pair23_tx_ready, pair23_tx_last;
    wire [DATA_W-1:0]  pair23_tx_data;
    wire [USERF_W-1:0] pair23_tx_last_bytes;
    wire [2:0]         pair01_mux_debug, pair23_mux_debug;
    wire [15:0]        pair01_mux_aborts, pair23_mux_aborts;

    // 第一级左：lane0 / lane1
    roce_tx_mux #(.DATA_W(DATA_W), .USERF_W(USERF_W)) u_tx_mux_01 (
        .clk(mac_clk), .rst_n(~dp_mac_rst_mux01),
        .in_valid(lane_tx_valid[1:0]), .in_data(lane_tx_data[2*DATA_W-1:0]),
        .in_last_bytes(lane_tx_last_bytes[2*USERF_W-1:0]),
        .in_last(lane_tx_last[1:0]), .in_ready(lane_tx_ready[1:0]),
        .out_valid(pair01_tx_valid), .out_data(pair01_tx_data), .out_last_bytes(pair01_tx_last_bytes),
        .out_last(pair01_tx_last), .out_ready(pair01_tx_ready),
        .debug_state(pair01_mux_debug),
        .aborted_packets(pair01_mux_aborts)
    );

    // 第一级右：lane2 / lane3
    roce_tx_mux #(.DATA_W(DATA_W), .USERF_W(USERF_W)) u_tx_mux_23 (
        .clk(mac_clk), .rst_n(~dp_mac_rst_mux23),
        .in_valid(lane_tx_valid[3:2]), .in_data(lane_tx_data[4*DATA_W-1:2*DATA_W]),
        .in_last_bytes(lane_tx_last_bytes[4*USERF_W-1:2*USERF_W]),
        .in_last(lane_tx_last[3:2]), .in_ready(lane_tx_ready[3:2]),
        .out_valid(pair23_tx_valid), .out_data(pair23_tx_data), .out_last_bytes(pair23_tx_last_bytes),
        .out_last(pair23_tx_last), .out_ready(pair23_tx_ready),
        .debug_state(pair23_mux_debug),
        .aborted_packets(pair23_mux_aborts)
    );

    // 第二级：两棵子树 2:1 → lanes 流
    wire               lanes_tx_valid, lanes_tx_ready, lanes_tx_last;
    wire [DATA_W-1:0]  lanes_tx_data;
    wire [USERF_W-1:0] lanes_tx_last_bytes;
    wire [2:0]         lane_mux_debug_state;
    roce_tx_mux #(.DATA_W(DATA_W), .USERF_W(USERF_W)) u_lane_tx_mux (
        .clk(mac_clk), .rst_n(~dp_mac_rst_lmux),
        .in_valid({pair23_tx_valid, pair01_tx_valid}),
        .in_data({pair23_tx_data, pair01_tx_data}),
        .in_last_bytes({pair23_tx_last_bytes, pair01_tx_last_bytes}),
        .in_last({pair23_tx_last, pair01_tx_last}),
        .in_ready({pair23_tx_ready, pair01_tx_ready}),
        .out_valid(lanes_tx_valid), .out_data(lanes_tx_data), .out_last_bytes(lanes_tx_last_bytes),
        .out_last(lanes_tx_last), .out_ready(lanes_tx_ready),
        .debug_state(lane_mux_debug_state),
        .aborted_packets(lane_mux_aborts)
    );

    roce_tx_mux #(.DATA_W(DATA_W), .USERF_W(USERF_W)) u_tx_mux (
        .clk(mac_clk), .rst_n(~dp_mac_rst_mux),
        .in_valid({lanes_tx_valid, qdma_tvalid}),
        .in_data({lanes_tx_data, qdma_tdata}),
        .in_last_bytes({lanes_tx_last_bytes, qdma_tusef}),
        .in_last({lanes_tx_last, qdma_tlast}),
        .in_ready({lanes_tx_ready, qdma_tready}),
        .out_valid(tx_tvalid), .out_data(tx_tdata), .out_last_bytes(tx_tusef), .out_last(tx_tlast),
        .out_ready(tx_tready),
        .debug_state(qdma_merge_debug),
        .aborted_packets(qdma_merge_aborts)
    );

    // ------------------------------------------------------------ 调试寄存器（0x0500..0x0580）
    // 地址表与位段见 roce_debug.sv 文件头。mac 域观测由顶层经 mac_debug 总线送进来；
    // pcie 域的 AR/AW 快照由顶层直采打包总线（roce_top 内部拿不到「当前在 AXI 上的
    // ARADDR」——ar_fifo 的输出端在 roce_dma 里，握手当拍就被消耗了）。
    // 0x0574 DMA_STATE 由 roce_dma 直接给出 read_credit 等关键量（见 roce_dma.sv）；
    // [23:14] 补上 BAS 的写请求未完成数（AW_HS - B，长期不降就是写路径卡住）。
    wire [31:0] debug_wr_delta = (counter_bas[0] > counter_bas[2]) ?
                                 (counter_bas[0] - counter_bas[2]) : 32'd0;
    wire [4:0]  debug_wr_outstanding = (debug_wr_delta > 32'd31) ? 5'd31 : debug_wr_delta[4:0];
    wire [23:0] debug_dma_state = {5'd0, debug_wr_outstanding, dma_debug_state};

    // ---- 调试观测：按 lane 打平后再送 roce_debug（分组寄存器见 roce_debug.sv 地址表）
    wire [LANES*20-1:0]      lane_req_state_flat;
    wire [LANES*11-1:0]      lane_tx_state_flat;
    wire [LANES*QP_W-1:0]    lane_qp_index_flat;
    wire [LANES*3-1:0]       lane_qp_state_flat;
    wire [LANES*24-1:0]      lane_qp_psn_flat;
    wire [LANES*32-1:0]      lane_qp_context_low_flat;
    wire [LANES*24-1:0]      lane_next_psn_flat;
    wire [LANES*24-1:0]      lane_unacked_psn_flat;
    wire [LANES*6-1:0]       lane_ack_counter_flat;
    wire [LANES*5-1:0]       lane_reads_outstanding_flat;
    wire [LANES*32-1:0]      lane_tx_offset_flat;
    wire [2:0]               qdma_merge_debug;
    wire [15:0]              qdma_merge_aborts;
    wire [15:0]              lane_mux_aborts;

    // 三级 mux（u_tx_mux_01 / u_tx_mux_23 / u_lane_tx_mux）的残包放弃数逐级相加，
    // 饱和到 0xFFFF。任何一级非零都意味着某条 lane 的 TX 出现了半包；只看最后一级会
    // 漏掉前两级。用 17 位中间量判溢出，避免三项相加回绕。
    wire [17:0] lane_aborts_wide = {2'd0, pair01_mux_aborts} + {2'd0, pair23_mux_aborts}
                                 + {2'd0, lane_mux_aborts};
    wire [15:0] lane_merge_aborts = lane_aborts_wide[17] ? 16'hFFFF : lane_aborts_wide[15:0];
    genvar dl;
    generate
        for (dl = 0; dl < LANES; dl = dl + 1) begin : gen_debug_lane
            wire [127:0] req = lane_req_debug_state[dl*128 +: 128];
            // S4：lane_qp_index_flat 是 LANES*QP_W = 4*7 位，但 roce_req 的 debug_state 只打包了
            // 4 位 qp_index（其 debug_state 里的 4'(qp_index) 字段，注释写着「[23:20] 只 4 位」），
            // 所以这里零扩到 QP_W 位——高位恒 0。
            // 只影响调试读回：A_CORE_ACTIVE_QP 读 QP_W 位，只有低 4 位是真实值；
            // 旧地址 A_QP_ACTIVE 本来就只取 [3:0]，行为不变。roce_req 若把该字段扩到 QP_W 位，
            // 这里要同步改成 req[QP_W+19:20]。
            // 显式零扩到 QP_W 位：隐式扩位 -Wall 会报 WIDTHEXPAND，Quartus 也要告警。
            // QP_W >= 4 由引擎 QP_NUM >= 16 保证（QP_NUM = 8 时 QP_W=3，这里按 QP_W 的位宽复制会变成负次数，编译即暴露）。
            wire [QP_W-1:0] qpi = {{(QP_W-4){1'b0}}, req[23:20]};
            assign lane_req_state_flat      [dl*20 +: 20] = req[19:0];
            // B6413：inflight 由 4 位扩到 5 位（深度 8 → 16），占用原先恒 0 的第 10 位。
            // 平铺宽度仍是 11，原来的 2 位占位缩成 1 位：
            //   [10:6] inflight[4:0]  [5:3] skip_align[2:0]  [2] 占位(0)  [1:0] build_state
            // 下游 roce_debug 只读 [1:0]（卡死检测）与整字透传到 0x056C，位宽不变即可。
            assign lane_tx_state_flat       [dl*11 +: 11] = {lane_tx_debug_state[dl*10 + 9 -: 5],
                                                             lane_tx_debug_state[dl*10 + 4 -: 3],
                                                             1'b0,
                                                             // 源字 roce_tx.sv 的 debug_state 低两位才是 build_state：
                                                             //   [9:5] inflight  [4:2] skip_align  [1:0] build_state
                                                             // 曾写成 [+2 -: 2]，取到 {skip_align[0], build_state[1]}，
                                                             // 结果 0x056C[1:0] 恒读 0 或 2、永远读不到 PAYLOAD（§37.5）。
                                                             lane_tx_debug_state[dl*10 + 1 -: 2]};
            assign lane_qp_index_flat       [dl*QP_W +: QP_W] = qpi;
            // S3：直接用 u_req 的 qp_context 快照（就是 qpi 这个 QP 的 QPC），不再按 qpi 选路
            assign lane_qp_state_flat       [dl*3  +: 3]  = lane_qp_context_low[dl*32 +: 3];
            assign lane_qp_psn_flat         [dl*24 +: 24] = req[47:24];
            assign lane_qp_context_low_flat [dl*32 +: 32] = lane_qp_context_low[dl*32 +: 32];
            assign lane_next_psn_flat       [dl*24 +: 24] = req[47:24];
            assign lane_unacked_psn_flat    [dl*24 +: 24] = req[71:48];
            assign lane_ack_counter_flat    [dl*6  +: 6]  = req[77:72];
            assign lane_reads_outstanding_flat[dl*5 +: 5] = req[17:13];
            assign lane_tx_offset_flat      [dl*32 +: 32] = req[127:96];
        end
    endgenerate

    // B6417（250 MHz）：进 roce_debug 的每 lane 观测量先打一拍。
    // B6416 全局最差路径（−0.567）就是这里：u_req.qp_index → lane_qpc 按 qpi 的 16:1×512 位选路
    // （lane_qp_state / lane_qp_context_low）→ roce_debug 多级读回 mux → roce_csr.register_read_value，
    // 两段 1.0~1.1 ns 的跨区走线。观测量晚 1 拍对读回、卡死检测、快照都没有功能影响。
    reg  [LANES*20-1:0]      lane_req_state_q;
    reg  [LANES*11-1:0]      lane_tx_state_q;
    reg  [LANES*QP_W-1:0]    lane_qp_index_q;
    reg  [LANES*3-1:0]       lane_qp_state_q;
    reg  [LANES*24-1:0]      lane_qp_psn_q;
    reg  [LANES*32-1:0]      lane_qp_context_low_q;
    reg  [LANES*24-1:0]      lane_next_psn_q;
    reg  [LANES*24-1:0]      lane_unacked_psn_q;
    reg  [LANES*6-1:0]       lane_ack_counter_q;
    reg  [LANES*5-1:0]       lane_reads_outstanding_q;
    reg  [LANES*32-1:0]      lane_tx_offset_q;
    always @(posedge core_clk) begin
        lane_req_state_q         <= lane_req_state_flat;
        lane_tx_state_q          <= lane_tx_state_flat;
        lane_qp_index_q          <= lane_qp_index_flat;
        lane_qp_state_q          <= lane_qp_state_flat;
        lane_qp_psn_q            <= lane_qp_psn_flat;
        lane_qp_context_low_q    <= lane_qp_context_low_flat;
        lane_next_psn_q          <= lane_next_psn_flat;
        lane_unacked_psn_q       <= lane_unacked_psn_flat;
        lane_ack_counter_q       <= lane_ack_counter_flat;
        lane_reads_outstanding_q <= lane_reads_outstanding_flat;
        lane_tx_offset_q         <= lane_tx_offset_flat;
    end

    roce_debug #(.SNAP_WORDS(16), .LANES(LANES)) u_debug (
        .clk(core_clk), .rst(dp_rst_misc),
        .reg_read_enable(csr_read), .reg_read_offset(csr_address[19:0]),
        .reg_read_value(debug_read_value),
        .resp_sticky_clear_pulse(debug_resp_clear_pulse),
        .reg_write_enable(debug_write_enable), .reg_write_offset(debug_write_offset),
        .reg_write_value(debug_write_value),
        .mac_clk(mac_clk), .mac_rst(dp_mac_rst_dbg),
        .mac_tx_valid(mac_debug[7:0]),        .mac_tx_ready(mac_debug[15:8]),
        .mac_tx_last(mac_debug[23:16]),
        .mac_axis_select(mac_debug[28:24]),   .mac_segm_state(mac_debug[38:29]),
        .mac_rx_valid(mac_debug[41:39]),      .mac_rx_ready(mac_debug[44:42]),
        .mac_rx_fifo0(mac_debug[76:45]),      .mac_rx_fifo1(mac_debug[108:77]),
        .mac_rx_mux_fifo(mac_debug[122:109]),
        // 每 lane（Phase 1 起 2 个引擎）
        .lane_req_state(lane_req_state_q),
        .lane_resp_state(lane_resp_debug_state),
        .lane_tx_state(lane_tx_state_q),
        .lane_dma_state(lane_dma_debug_state),
        .lane_disp_busy_owner(lane_disp_busy_owner),
        .lane_qp_index(lane_qp_index_q),
        .lane_qp_state(lane_qp_state_q),
        .lane_qp_psn(lane_qp_psn_q),
        .lane_qp_context_low(lane_qp_context_low_q),
        .lane_next_psn(lane_next_psn_q),
        .lane_unacked_psn(lane_unacked_psn_q),
        .lane_ack_counter(lane_ack_counter_q),
        .lane_reads_outstanding(lane_reads_outstanding_q),
        .lane_tx_offset(lane_tx_offset_q),
        // 共享：RX 前端/解析、QPN 分流、TX 汇合
        .core_rx_state({debug_staging_occupancy, 1'd0, lane_disp_busy_owner[0 +: 2], rx_parse_debug_state}),
        // demux 在 mac_clk 域，roce_debug 在 core_clk 域：两级寄存（渐变状态，仅供观察）
        .core_rx_split_state(rx_demux_debug_state),
        .core_bas_live(debug_bas_live),
        .core_bas_outstanding(debug_ar_outstanding),
        .tx_merge_qdma_state(qdma_merge_debug),
        .tx_merge_qdma_aborts(qdma_merge_aborts),
        .tx_merge_lane_state(lane_mux_debug_state),
        .tx_merge_lane_aborts(lane_merge_aborts),
        .pcie_clk(pcie_clk), .pcie_rst(dp_pcie_rst),
        .pcie_ar_address(pcie_debug[63:0]),
        .pcie_ar_len(pcie_debug[71:64]),
        .pcie_ar_hs(pcie_debug[75:72]),
        .pcie_aw_address_low(pcie_debug[107:76]),
        .pcie_resp_sticky(debug_resp_sticky),
        .lane_frames(counter_lane_frames),        .lane_icrc_error(counter_lane_icrc_error),
        .lane_drop(counter_lane_drop),
        .lane_staging(debug_lane_staging),
        .lane_staging_peak(debug_lane_staging_peak),
        .demux_lane_frames(rx_demux_lane_frames),
        .demux_lane_stall(rx_demux_lane_stall),
        .demux_lane_sop_stall(rx_demux_lane_sop_stall),
        .rx_merge_events({counter_merge_rebase, counter_merge_force}),
        .lane_peak_clear_pulse(lane_peak_clear)
    );
    assign debug_read_hit = (csr_address[19:0] >= REG_DBG_BASE) && (csr_address[19:0] <= REG_DBG_END);

    // ------------------------------------------------------------ 拥塞控制（PFC / ECN-CNP / DCQCN）
    // 寄存器窗口 0x0800..0x0BFC（roce_pkg 的 REG_CC_*）。读口与调试窗口一样走 roce_csr 的「外部读」
    // 二选一：这里先在 debug 与 CC 之间选，再交给 roce_csr。写口复用 debug_write_*（roce_csr 对任何
    // 偏移都会给出单拍写脉冲），各模块自己按地址译码。
    // access error 快照（0x0C00，B6433）：每个 lane 8 个字，地址 = 0x0C00 + lane*0x20 + word*4。
    // 写窗口基址（0x0C00..0x0C03）清「已锁存」与计数；读第 7 个字（+0x1C）是复位后的总事件数。
    wire  [LANES*8*32-1:0] acc_snapshot;
    reg                    acc_snapshot_clr;
    wire        cc_acc_hit = (csr_address[19:0] >= REG_ACC_BASE) && (csr_address[19:0] <= REG_ACC_END);
    wire [31:0] acc_read_value = acc_snapshot[csr_address[6:5]*8*32 + csr_address[4:2]*32 +: 32];
    always @(posedge core_clk) begin
        acc_snapshot_clr <= debug_write_enable &&
                            (debug_write_offset >= REG_ACC_BASE) && (debug_write_offset < REG_ACC_BASE + 20'd4);
    end

    wire        cc_pfc_hit = (csr_address[19:0] >= REG_PFC_BASE) && (csr_address[19:0] <= REG_PFC_END);
    wire [31:0] pfc_read_value;
    assign csr_ext_read_hit   = debug_read_hit | cc_pfc_hit | cc_cnp_hit | cc_dcqcn_hit | cc_acc_hit;
    assign csr_ext_read_value = cc_pfc_hit ? pfc_read_value :
                                cc_cnp_hit ? cnp_read_value :
                                cc_dcqcn_hit ? dcqcn_read_value :
                                cc_acc_hit ? acc_read_value : debug_read_value;

    wire [8:0]  pfc_pause_mac;
    wire        pfc_egress_gate_mac;
    wire        pfc_resp_gate;
    wire [LANES-1:0] lane_egress_hold;

    // ------------------------------------------------------------ ECN / CNP（0x0A00 窗口）
    // roce_cnp 只做端口级的「该不该发、多久发一个、发给哪个 lane」；CNP 报文的组包在各 lane 的
    // roce_engine 里（它才拿得到该 QP 的 QPC：dmac/dip/dqpn/sport 都要取自 QPC）。
    wire        cnp_en;
    wire        cnp_np_en;              // B6434：NP_EN 也要到 lane 侧（清挂起位/已锁存 grant）
    wire [7:0]  cnp_tos;
    wire        cnp_becn, cnp_fecn;      // B6434：CNP 的 BTH BECN/FECN（0xA14）
    wire [LANES-1:0] cnp_request;
    wire [LANES-1:0] cnp_grant;
    wire [LANES-1:0] cnp_ecn_marked_lane, cnp_sent_lane, cnp_handled_lane, cnp_ignored_lane;
    wire [31:0] cnp_read_value;
    wire        cc_cnp_hit = (csr_address[19:0] >= REG_CNP_BASE) && (csr_address[19:0] <= REG_CNP_END);
    genvar cl;
    generate
        for (cl = 0; cl < LANES; cl = cl + 1) begin : gen_cnp_event
            assign cnp_ecn_marked_lane[cl] = lane_event[EV_ECN_MARK][cl];
            assign cnp_sent_lane[cl]       = lane_event[EV_CNP_SENT][cl];
            assign cnp_handled_lane[cl]    = lane_event[EV_CNP_HANDLED][cl];
            assign cnp_ignored_lane[cl]    = lane_event[EV_CNP_IGNORED][cl];
        end
    endgenerate
    roce_cnp #(.CORE_CLOCK_MHZ(CORE_CLOCK_MHZ), .LANES(LANES)) u_cnp (
        .clk(core_clk), .rst(dp_rst_misc),
        .reg_offset(csr_address[19:0]), .reg_write_offset(debug_write_offset), .reg_write(debug_write_enable),
        .reg_write_data(debug_write_value), .reg_read_data(cnp_read_value),
        .cfg_cnp_en(cnp_en), .cfg_cnp_np_en(cnp_np_en), .cfg_cnp_tos(cnp_tos),
        .cfg_cnp_becn(cnp_becn), .cfg_cnp_fecn(cnp_fecn),
        .cnp_request(cnp_request), .cnp_grant(cnp_grant),
        .event_ecn_marked(cnp_ecn_marked_lane), .event_cnp_sent(cnp_sent_lane),
        .event_cnp_handled(cnp_handled_lane), .event_cnp_ignored(cnp_ignored_lane)
    );
    roce_pfc #(.CORE_CLOCK_MHZ(CORE_CLOCK_MHZ), .MAC_CLOCK_MHZ(MAC_CLOCK_MHZ), .RX_LANES(2), .TX_LANES(LANES)) u_pfc (
        .clk(core_clk), .rst(dp_rst_misc),
        .reg_offset(csr_address[19:0]), .reg_write_offset(debug_write_offset), .reg_write(debug_write_enable),
        .reg_write_data(debug_write_value), .reg_read_data(pfc_read_value),
        .pause_core(pfc_pause_core), .resp_gate_core(pfc_resp_gate),
        .mac_clk(mac_clk), .mac_rst(dp_mac_rst_dbg),
        .lane_occupancy(rx_lane_occupancy), .lane_drop(rx_lane_drop),
        .rx_pfc(rx_pfc), .tx_pfc(tx_pfc),
        .pause_mac(pfc_pause_mac), .egress_gate_mac(pfc_egress_gate_mac),
        .egress_hold(lane_egress_hold)
    );

    // ------------------------------------------------------------ DCQCN（0x0B00 窗口，RP 侧）
    // 每 QP 一个速率上下文（RC/RT/α/阶段计数/信用），放在这里而不是每 lane 一份：
    // QP → lane 的绑定是 qp_index[LANE_W-1:0]，但全局上下文表按完整 qp_index 索引，
    // 一份就够了，也避免 4 份计数器互相不同步。
    // 事件汇聚：各 lane 给 one-hot 的「收到 CNP」与「准入发包」，直接或起来。
    //
    // S5（2026-11-14）：DCQCN 跟着引擎 QP_NUM 一起扩到 128。u_dcqcn 内部的扫描、
    // 上下文阵列、one-hot 优先级链都按 DCQCN_QP_NUM 展开；128 时扫描周期 128 拍
    // （512 ns @ 250 MHz），仍小于 ALPHA_US 的 1 µs 预算。S4 时代 DCQCN 只覆盖
    // QP0..15、QP16..127 恒放行的取舍不再需要——现在全部 128 个 QP 都受限速。
    // 要回退到只覆盖前 16 个，把本常量改成 16 即可（tx_rate_ready 的高位补 1
    // 逻辑见下面，QP_NUM > DCQCN_QP_NUM 时自动补恒 1）。
    localparam int DCQCN_QP_NUM = QP_NUM;
    // S5：DCQCN_QP_NUM = QP_NUM = 128，所以 DCQCN_QP_W = 7，与引擎的 QP_W 相同。
    // 下面的 cnp_qp_q / admit_qp_q 仍用 DCQCN_QP_W（而不是直接写 QP_W），以便将来
    // DCQCN_QP_NUM 再次小于 QP_NUM 时端口宽度还是正确的（位宽不一致时 Quartus 会截断高位）。
    localparam int DCQCN_QP_W   = (DCQCN_QP_NUM > 1) ? $clog2(DCQCN_QP_NUM) : 1;
    wire [DCQCN_QP_NUM-1:0] lane_rx_cnp_or;   // QP0..15 的 CNP 合并 one-hot（只扫前 DCQCN_QP_NUM 项）
    wire              lane_tx_admit_len_or;
    wire [12:0]       tx_admit_length_sum;
    wire [31:0]       dcqcn_read_value;
    wire [DCQCN_QP_NUM-1:0] dcqcn_rate_ready; // u_dcqcn 的 QP_NUM 位输出，再补 1 到 tx_rate_ready
    wire        cc_dcqcn_hit = (csr_address[19:0] >= REG_DCQCN_BASE) && (csr_address[19:0] <= REG_DCQCN_END);
    genvar dq;
    generate
        for (dq = 0; dq < DCQCN_QP_NUM; dq = dq + 1) begin : gen_dcqcn_or
            // lane_rx_cnp_qp 是 LANES*QP_NUM 位（引擎输出，不能改），但每个 lane 的 one-hot 都是
            // **全局** QP 索引，所以把各 lane 的同一全局索引 q 或起来就够。
            // S5：DCQCN_QP_NUM = QP_NUM = 128，所以这里覆盖全部 128 个 QP。
            reg [LANES-1:0] cnp_bits;
            always @* begin
                for (int l = 0; l < LANES; l = l + 1)
                    cnp_bits[l] = lane_rx_cnp_qp[l*QP_NUM + dq];
            end
            assign lane_rx_cnp_or[dq] = |cnp_bits;
        end
    endgenerate
    // 准入长度与 QP：同一拍最多一个 lane 有准入事件（每个 lane 的 roce_tx 每拍最多出一个包），
    // 多 lane 同拍撞上时按 lane 0 优先——只影响升速的字节计数，量级可忽略。
    // S5：DCQCN_QP_NUM = QP_NUM = 128，全部 QP 的准入事件都送进 DCQCN 计字节升速。
    reg  [DCQCN_QP_W-1:0] cnp_qp_q;  // 本拍收到 CNP 的 QP 索引（与 lane_rx_cnp_or 同拍）
    always @* begin
        cnp_qp_q = {DCQCN_QP_W{1'b0}};
        for (int l = LANES - 1; l >= 0; l = l - 1)
            for (int q = 0; q < DCQCN_QP_NUM; q = q + 1)
                if (lane_rx_cnp_qp[l*QP_NUM + q]) cnp_qp_q = DCQCN_QP_W'(q);
    end

    reg  [12:0] admit_len_q;
    reg  [DCQCN_QP_W-1:0] admit_qp_q;
    reg         admit_any;
    always @* begin
        admit_len_q = 13'd0;
        admit_qp_q  = {DCQCN_QP_W{1'b0}};
        admit_any   = 1'b0;
        for (int l = LANES - 1; l >= 0; l = l - 1)
            for (int q = 0; q < DCQCN_QP_NUM; q = q + 1)
                if (lane_tx_admit_qp[l*QP_NUM + q]) begin
                    admit_any   = 1'b1;
                    admit_qp_q  = DCQCN_QP_W'(q);
                    admit_len_q = lane_tx_admit_len[l*13 +: 13];
                end
    end
    assign tx_admit_length_sum  = admit_len_q;
    assign lane_tx_admit_len_or = admit_any;

    // tx_rate_ready 是 QP_NUM 位（广播给每个 lane 的 roce_req，按全局 qp_index 索引）：
    // 低 DCQCN_QP_NUM 位接 u_dcqcn 的输出，高位恒 1'b1 = 恒放行。
    // S5：DCQCN_QP_NUM = QP_NUM = 128，高位补 0 次（退化成直连，无额外逻辑）。
    // 若将来 DCQCN_QP_NUM < QP_NUM，高位的 QP 恒放行不受限速。
    assign tx_rate_ready = {{(QP_NUM-DCQCN_QP_NUM){1'b1}}, dcqcn_rate_ready};

    roce_dcqcn #(.CORE_CLOCK_MHZ(CORE_CLOCK_MHZ), .QP_NUM(DCQCN_QP_NUM)) u_dcqcn (
        .clk(core_clk), .rst(dp_rst_misc),
        .reg_offset(csr_address[19:0]), .reg_write_offset(debug_write_offset), .reg_write(debug_write_enable),
        .reg_write_data(debug_write_value), .reg_read_data(dcqcn_read_value),
        .event_cnp(lane_rx_cnp_or), .cnp_qp_index(cnp_qp_q),
        .event_tx_valid(lane_tx_admit_len_or), .event_tx_qp(admit_qp_q),
        .event_tx_length(tx_admit_length_sum),
        .tx_rate_ready(dcqcn_rate_ready)
    );

    // ------------------------------------------------------------ 计数器
    // 多个 lane 可能同一拍各报一次同一事件，直接 OR 会少计。每个事件一个待计数，
    // 各 lane 相加、每拍放出一个脉冲。包级事件每 lane 至少隔数拍才一次（4 lane 合计平均 < 1/拍），
    // 5 位待计数足够吸收同拍突发。
    //
    // B6417：原来只加了 lane 0/1（Phase 1 两 lane 时代留下的写法），B6405 起 LANES=4 后
    // lane 2/3 的事件全部丢失——`-q 4` 时 TX_PKTS/RX_PKTS/ACK/NAK/RETX_* 等只计了一半。
    wire [EVENT_MERGE_NUM-1:0] merged_event;
    genvar ev;
    generate
        for (ev = 0; ev < EVENT_MERGE_NUM; ev = ev + 1) begin : gen_event_merge
            reg  [4:0] pending;
            reg  [2:0] arrive;
            always @* begin
                arrive = 3'd0;
                for (int l = 0; l < LANES; l++) arrive = arrive + {2'd0, lane_event[ev][l]};
            end
            assign merged_event[ev] = (pending != 5'd0);
            always @(posedge core_clk)
                if (dp_rst_misc) pending <= 5'd0;
                else             pending <= pending + {2'd0, arrive} - {4'd0, (pending != 5'd0)};
        end
    endgenerate

    assign counter_increment[CNT_TX_PKTS]       = merged_event[EV_TX_PACKET];
    assign counter_increment[CNT_RX_PKTS]       = merged_event[EV_RX_PACKET];
    assign counter_increment[CNT_RX_ICRC_ERR]   = 1'b0;          // 来自 counter_rx_icrc_error
    assign counter_increment[CNT_RX_DROP]       = 1'b0;          // 来自 counter_rx_drop
    assign counter_increment[CNT_RX_BAD_QP]     = merged_event[EV_BAD];
    assign counter_increment[CNT_RX_DUP]        = merged_event[EV_DUPLICATE];
    assign counter_increment[CNT_RX_SEQ_ERR]    = merged_event[EV_SEQ_ERR];
    assign counter_increment[CNT_TX_ACK]        = merged_event[EV_TX_ACK];
    assign counter_increment[CNT_TX_NAK]        = merged_event[EV_TX_NAK];
    assign counter_increment[CNT_RX_ACK]        = merged_event[EV_RX_ACK];
    assign counter_increment[CNT_RX_NAK]        = merged_event[EV_RX_NAK];
    assign counter_increment[CNT_RETX_TIMEOUT]  = merged_event[EV_RETX_TO];
    assign counter_increment[CNT_RETX_NAK]      = merged_event[EV_RETX_NAK];
    assign counter_increment[CNT_TX_RNR_NAK]    = merged_event[EV_RNR_NAK];
    assign counter_increment[CNT_RX_RNR_NAK]    = merged_event[EV_RX_RNR];
    assign counter_increment[CNT_CQE]           = event_cqe;
    assign counter_increment[CNT_CQ_OVERFLOW]   = event_cq_overflow;
    assign counter_increment[CNT_RX_ACCESS_ERR] = merged_event[EV_ACCESS];
    assign counter_increment[CNT_BAS_R_LAST:CNT_BAS_AW_HS] = '0;   // 来自 roce_bas_mon（counter_bas）
    // RESP_CYCLES 是逐拍计数，多 lane 同时忙每拍要加多次，待计数会溢出。
    // 口径为「任一 lane 的 resp 非 IDLE」的拍数；单 QP 流量下与单引擎时代口径相同。
    // B6417：原来只看 lane 0/1，扩到全部 lane。
    wire [LANES-1:0] lane_resp_busy;
    genvar rb;
    generate
        for (rb = 0; rb < LANES; rb = rb + 1) begin : gen_resp_busy
            assign lane_resp_busy[rb] = (lane_resp_debug_state[rb*7 +: 4] != 4'd0);
        end
    endgenerate
    assign counter_increment[CNT_RESP_CYCLES] = |lane_resp_busy;
    assign counter_increment[CNT_PAGE_HIT]    = merged_event[EV_PAGE_HIT];
    assign counter_increment[CNT_PAGE_MISS]   = merged_event[EV_PAGE_MISS];
endmodule
`default_nettype wire
