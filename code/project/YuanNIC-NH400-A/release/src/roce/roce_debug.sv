// roce_debug.sv
// RoCE 引擎调试观测：流水级握手电平、FIFO 水位、各 FSM 状态、BAS/DMA 在途请求，
// 以及「卡死快照」——某级 valid 长期为 1 而 ready 为 0 时锁存当拍上下文。
//
// 为什么单独一个模块
//   2026-10-25 的卡死现象（RoCE 引擎全部计数冻结、netdev ping 仍通）在 system_config
//   的 0x0F8 那 60 位里看不出来，而那些位本来就读不到（见 skill/debug-playbook.md
//   2026-10-25 条目）。可读的地址只有 RoCE 窗口 0x0170_0000，所以调试寄存器放在这里。
//
// ---------------------------------------------------------------------------
// 地址分配（AVMM 偏移，相对 slot 0x017，即 0x0170_0000 + 本表偏移）
// ---------------------------------------------------------------------------
//   0x0500  ID          RO  0x5244_4247（"RDBG"）
//   0x0504  VERSION     RO  {8'd1, 8'd0, 16'(SNAP_WORDS)}；改动本文件时递增 [23:16]
//   0x0508  THRESHOLD   RW  卡死判定拍数（core_clk 100 MHz，1000 拍 = 10 us），写 0 关闭判死
//   0x050C  COUNT       RO  触发过多少次卡死快照（饱和 0xFFFF）
//   0x0510  CONTROL     WO  写任意非 2 值 = 立即取一次快照；写 0x0000_0002 = 清快照与计数
//   0x0514  STATUS      RO  [0] 快照有效；[9:8] 触发域（0=mac 1=core 2=pcie）；
//                           [23:16] 触发通道号；[31:24] 保留
//
//   MAC 域（eth_mac_clk）TX 流水主干。位序高位在前，与下面「通道号」一致：
//     位号 7 6 5 4 3 2 1 0
//     级   gap_to_mac / reg_to_h2l / segm_to_reg / select_to_segm /
//          qdma_to_select / qdma_to_regslice / qdma_h2d / 保留
//   0x0520  TX_STAGE_VALID   RO  [7:0]
//   0x0524  TX_STAGE_READY   RO  [7:0]
//   0x0528  TX_STAGE_LAST    RO  [7:0]
//   0x052C  AXIS_SELECT      RO  [4:0] axis_select.debug_state = {illegal, select[0],
//                                axis_last_reg[1], axis_last_reg[0], select[1]}：
//                                [0] select[1]；[1] axis_last_reg[0]；
//                                [2] axis_last_reg[1]；[3] select[0]；
//                                [4] select==2'b10（非法态，卡死标志）
//                                注：原注释把 [1] 和 [3] 写反、[2] 写成 axis_last_reg[0]，
//                                按错位序解码会把健康态 select=2'b01 读成 2'b10。已按
//                                axis_select.sv 的 assign 逐位改正。
//   0x0530  SEGM_STATE       RO  [9:0] axis_to_segm.debug_state：
//                                [0] send_select；[1] send_select==1（危险态）；
//                                [2] s_axis_tready[0]；[3] m_segm_ready；
//                                [4] 通道 0 本拍有帧数；[9:5] start_num
//   0x0534  SEGM_COUNT       RO  [15:0] m_segm_valid 握手累计（低 16 位）；
//                                [31:16] m_segm_ready 握手累计（低 16 位）——两值同步看是否都在涨
//   0x0538  AXIS_STALL       RO/WO  axis_select 卡在非法态 2'b10 的观测（pkt_gen 删除后
//                                第 1 路恒空，落进 2'b10 就出不来，TX 会整条停）：
//                                [4:0]  当前连续驻留 /256 拍（低 5 位；100 MHz 下 1 单位 ≈ 2.56 µs）
//                                [5]    s_axis_select[4] 原样（当前在 2'b10）
//                                [6]    曾经进过 2'b10（粘滞，**读清零**）
//                                [7]    当前在 2'b10（实时，与 [5] 同源，便于整字节判读）
//                                [23:16] 历史最长一次驻留 /256 拍（饱和 0xFF ≈ 653 ms）
//                                [29:24] select 当前值 {4'd0, select[1], select[0]}
//                                WO：写 bit0=1 清粘滞位与驻留计数
//                                判读：只要 [6] 曾经为 1，说明这条退出路径真的被走过，
//                                TX 停住时优先查这里；[23:16] 给出停了多久。
//
//   MAC 域 RX 侧
//   0x0540  RX_STAGE_VALID   RO  {5'd0, rcv_to_qdma, rx_to_rcv[1], rx_to_rcv[0]}
//   0x0544  RX_STAGE_READY   RO  同上顺序。注意：顶层 rx_to_rcv_tready / rcv_to_qdma_tready
//                                实际上在 rx_path_avst 内被恒接 1'b1（RX 通路无背压），
//                                所以这三位恒为 111；RX 吞吐不靠 tready 判断，看计数。
//   0x0548  RX_FIFO0         RO  lane0 {data_afull[15:0], data_empty[15:0]}
//   0x054C  RX_FIFO1         RO  lane1 同上
//   0x0550  RX_MUX_FIFO      RO  [0] info_afull; [1] m_info_empty; [3:2] axis_ram_full;
//                                [5:4] axis_ram_empty; [7:6] axis_eop_empty;
//                                [9:8] s_drop_afull; [11:10] s_drop_empty
//
//   CORE 域（clk100m）
//   0x0560  REQ_STATE    RO  [4:0] roce_req state；[7:5] dispatch_reason；[12:8] retry_left；
//                            [17:13] reads_outstanding；[18] recovering；[19] local_error
//   0x0564  RESP_STATE   RO  [3:0] roce_resp main_state；[6:4] out_state
//   0x0568  RX_PARSE     RO  [2:0] roce_rx_parse state；[4:3] disp {owner,busy}；[5] 恒 0；
//                            [15:6] rx_front staging 占用（10 位，0..511）
//                            注（B6386 起）：parse 只剩两个状态，0=IDLE、2=STREAM，**不会出现 1**。
//                            读到 1 说明镜像不是 1024 位版本（老版 1=PUSH，多拍帧的 beat1）。
//   0x056C  TX_BUILD     RO  [1:0] build_state；[3:2] tx_mux {in_packet, port}；
//                            [6:4] skip_align；[10:7] inflight（4 位）
//                            注（B6413 起）：在途 FIFO 深度 8 → 16，inflight 需要 5 位。
//                            第 5 位占用原先恒 0 的 bit[10]，因此实际布局是：
//                              [10:6] inflight[4:0]  [5:3] skip_align[2:0]
//                              [2] 占位(0)           [1:0] build_state
//                            读法：inflight = (word >> 6) & 0x1F（16 深时 0..16）。
//                            注（B6386 起）：build_state 只有 0=PREP、1=PAYLOAD，
//                            **不会出现 2**（老版 1=头部第 1 拍，2=payload）。
//                            注：原注释写 [7:4] skip_align、[15:8] tx 在途 FIFO，与
//                            roce_top 的 {tx_debug_state[8:5], tx_debug_state[4:2],
//                            mux_debug_state[1:0], tx_debug_state[1:0]} 拼法不符。skip_align
//                            只有 3 位、inflight_used 4 位，已按拼接逐位改正。
//   0x0570  QP_ACTIVE    RO  [3:0] 当前 QP 号；[6:4] 该 QP 状态；[31:8] 该 QP next_psn
//   0x0574  DMA_STATE    RO  [9:0]  read_credit（关键：减到不足以覆盖一个新请求就会永久停发 AR）；
//                            [10] read_second_phase；[11] ar_fifo 非空；[12] read_meta 非空；
//                            [13] read_beat_valid；[18:14] 写请求未完成数（AW_HS - B，饱和 31）
//   0x0578  BAS_OUTSTAND RO  [7:0] BAS 各通道当前 valid/ready 电平（与 0x0404 同源）；
//                            [15:8] 未完成 AR 数 = AR_HS - R_LAST，饱和 255
//   0x057C  RESP_STICKY  RO  [0] 见过 R last；[1] 见过 AR 握手；
//                            [2] 见过 RRESP!=OKAY；[3] 见过 BRESP!=OKAY
//                            共 4 位，没有 bit4。依据 roce_bas_mon 的拼接
//                            {bvalid&&bresp!=0, rvalid&&rresp!=0, arvalid&&arready,
//                             rvalid&&rready&&rlast}（MSB 在前），与读口的
//                            {28'd0, resp_sticky_sync2} 一一对应。原注释把 bresp/rresp
//                            写反、且凭空多写了 bit4「写路径卡死标志」，实际不存在。
//   0x0580  RESP_CLEAR   WO  写任意值清 0x057C 的 sticky（同时清 roce_bas_mon 的源锁存，
//                            真能清掉了；不影响计数器）
//
//   0x0590..0x05CC  SNAP[0..15] 卡死快照
//     SNAP[0]  [7:0]=0x5A 标记；[9:8]=触发域；[17:10]=触发通道号；[31:24]=0xA5
//     SNAP[1]  触发时该通道已持续的拍数（饱和 0x00FF_FFFF）
//     SNAP[2]  mac TX：{tx_last, tx_ready, tx_valid}
//     SNAP[3]  mac TX：[4:0]=axis_select（5 位）；[14:5]=segm_state（10 位）
//     SNAP[4]  mac RX：{13'd0, rx_ready[2:0], 13'd0, rx_valid[2:0]}
//     SNAP[5]  mac：RX FIFO 水位 [7:0]=fifo0 empty；[15:8]=fifo0 afull；
//              [23:16]=fifo1 empty；[31:24]=fifo1 afull（不含 rx_mux_fifo，mux 只在 0x0550）
//     SNAP[6]  core：[14:0]=req_state（截 15 位）；[21:15]=resp_state（7 位）；
//              [22] 恒 0（RTL 里是 {1'b0, core_resp_state} 补成 8 位切片）
//     SNAP[7]  core：[10:0]=tx_state（11 位，与 0x056C 同布局）；[27:12]=rx_state（16 位）
//     SNAP[8]  core：qpc[qp_index] 低 32 位（含 state / MTU / next_psn 高位）
//     SNAP[9]  core：{8'd0, next_psn[23:0]}
//     SNAP[10] core：tx_offset[31:0]（当前 WQE 内偏移）
//     SNAP[11] core：[4:0]=reads_outstanding；[10:5]=ack_counter
//     SNAP[12] pcie：ARADDR[63:32]
//     SNAP[13] pcie：ARADDR[31:0]（页内偏移在这里，判别力最强）
//     SNAP[14] pcie：[7:0]=ar_len；[11:8]=ar_hs
//     SNAP[15] pcie：AWADDR[31:0]
//
// 快照语义：13 个通道（0..7 = TX 流水 8 级，8 = req FSM，9 = tx build FSM，
// 10 = resp FSM，11 = rx_parse FSM，12 = BAS 未完成 AR 过多）里，某通道连续
// THRESHOLD 拍满足「卡住」条件时，锁存该通道所在域的全部观测值。快照一旦锁住就
// 不再更新，直到写 CONTROL=2 清除——事后慢慢读不会变。THRESHOLD 单位是 core_clk
// 拍（100 MHz 下 1000 拍 = 10 us），判「真的死住」而不是正常反压。
// ---------------------------------------------------------------------------
`default_nettype none
`timescale 1ns/1ps
module roce_debug
    import roce_pkg::*;
#(
    parameter int SNAP_WORDS = 16,
    parameter int LANES      = 2      // RDMA core lane 数，与 roce_top 的 LANES 一致
)(
    input  wire         clk,                 // core 域（与 CSR 同域）
    input  wire         rst,
    // 寄存器读口：与 roce_csr 的 avm_register 一致，读使能当拍给地址、组合取数
    input  wire         reg_read_enable,
    input  wire  [19:0] reg_read_offset,
    output reg   [31:0] reg_read_value,
    // 写 0x0580 时出一拍，顶层拿它去清 roce_bas_mon 里的源锁存（resp_sticky_pcie）。
    // 只清本模块的 resp_sticky_sync1 没用：源没清，下一拍又被 OR 回来。
    output reg          resp_sticky_clear_pulse,
    // 寄存器写口（单拍）
    input  wire         reg_write_enable,
    input  wire  [19:0] reg_write_offset,
    input  wire  [31:0] reg_write_value,

    // ---------------- MAC 域实时观测（eth_mac_clk，来自顶层 roce_mac_debug）
    input  wire         mac_clk,
    input  wire         mac_rst,
    input  wire  [7:0]  mac_tx_valid,        // [7:0]   同下
    input  wire  [7:0]  mac_tx_ready,        // [15:8]
    input  wire  [7:0]  mac_tx_last,         // [23:16]
    input  wire  [4:0]  mac_axis_select,     // [28:24] axis_select.debug_state
    input  wire  [9:0]  mac_segm_state,      // [38:29] axis_to_segm.debug_state
    input  wire  [2:0]  mac_rx_valid,        // [41:39] {rcv_to_qdma, rx_to_rcv1, rx_to_rcv0}
    input  wire  [2:0]  mac_rx_ready,        // [44:42]
    input  wire  [31:0] mac_rx_fifo0,        // [76:45] {data_afull[15:0], data_empty[15:0]}
    input  wire  [31:0] mac_rx_fifo1,        // [108:77]
    input  wire  [13:0] mac_rx_mux_fifo,     // [122:109]

    // ---------------- CORE 域实时观测（按 lane 打平，lane i 占 [i*W +: W]）
    // Phase 1 起 RDMA core 是 LANES 份，每份有自己的 req/resp/disp/tx/dma/BAS。
    // 顶层把 gen_lane[i].u_engine 的 debug 端口按 lane 拼成下面这些向量。
    input  wire  [LANES*20-1:0]  lane_req_state,      // {local_error, recovering, reads_outstanding,
                                                      //  retry_left, dispatch_reason, state[4:0]}
    input  wire  [LANES*7-1:0]   lane_resp_state,     // {out_state, main_state}
    input  wire  [LANES*11-1:0]  lane_tx_state,       // {inflight[3:0], skip_align[2:0], mux[1:0], build_state[1:0]}
    input  wire  [LANES*14-1:0]  lane_dma_state,      // 见 RDMA_CORE_x_DMA_STATE
    input  wire  [LANES*2-1:0]   lane_disp_busy_owner,// {busy, owner}
    // 每 lane 的活动 QP 观测（顶层从 lane 的 req debug 状态与 QPC 表里取，按 lane 打平）
    input  wire  [LANES*QP_W-1:0] lane_qp_index,
    input  wire  [LANES*3-1:0]   lane_qp_state,
    input  wire  [LANES*24-1:0]  lane_qp_psn,
    input  wire  [LANES*32-1:0]  lane_qp_context_low,
    input  wire  [LANES*24-1:0]  lane_next_psn,
    input  wire  [LANES*24-1:0]  lane_unacked_psn,
    input  wire  [LANES*6-1:0]   lane_ack_counter,
    input  wire  [LANES*5-1:0]   lane_reads_outstanding,
    input  wire  [LANES*32-1:0]  lane_tx_offset,
    // 共享部分（RX 前端/解析、RX 分流、共享 CQ）
    input  wire  [15:0] core_rx_state,       // {staging_occupancy, busy_owner, parse_state}（parse 是共享的）
    input  wire  [3:0]  core_rx_split_state, // {payload_busy, payload_owner, 2'd0}
    input  wire  [7:0]  core_bas_live,
    input  wire  [7:0]  core_bas_outstanding,// AR 未完成数（饱和 255，全卡合计）
    // 两级 TX 汇合的实时状态与残包放弃计数
    input  wire  [2:0]  tx_merge_qdma_state,     // {in_packet, port, priority}：QDMA 与 RoCE 汇合
    input  wire  [15:0] tx_merge_qdma_aborts,
    input  wire  [2:0]  tx_merge_lane_state,     // 同上：lane0 与 lane1 汇合
    input  wire  [15:0] tx_merge_lane_aborts,

    // ---------------- PCIE 域（BAS 打包总线）观测
    input  wire         pcie_clk,
    input  wire         pcie_rst,
    input  wire  [63:0] pcie_ar_address,     // 当前 ARADDR
    input  wire  [7:0]  pcie_ar_len,
    input  wire  [3:0]  pcie_ar_hs,          // {arready, arvalid, rready, rvalid}
    input  wire  [31:0] pcie_aw_address_low,
    input  wire  [3:0]  pcie_resp_sticky,    // {bresp!=0, rresp!=0, 见过AR, 见过R last}
    // ---------------- 每 lane RX 统计（clk 域，来自 roce_rx_front）
    input  wire  [63:0] lane_frames,         // [31:0]=lane0 [63:32]=lane1，完成帧数
    input  wire  [63:0] lane_icrc_error,     // 同上
    input  wire  [63:0] lane_drop,           // 同上
    input  wire  [19:0] lane_staging,        // {lane1_occ[9:0], lane0_occ[9:0]}
    input  wire  [19:0] lane_staging_peak,   // 同上，峰值
    // ---------------- demux 每 lane 统计（clk 域，来自 roce_rx_demux，B6408 加）
    // 见 roce_rx_demux.sv 端口注释：观测的是反压强度，不是 FIFO 丢弃数
    input  wire  [LANES*32-1:0] demux_lane_frames,
    input  wire  [LANES*32-1:0] demux_lane_stall,
    input  wire  [LANES*32-1:0] demux_lane_sop_stall,
    // ---------------- RX 两路合并事件（clk 域，来自 roce_rx_front，B6418 加）
    // [31:0] = 顺序超时强制放行次数，[63:32] = 空闲重新对齐序号次数；正常运行恒为 0
    input  wire  [63:0] rx_merge_events,
    output reg          lane_peak_clear_pulse
);
    // ------------------------------------------------------------ 地址常量
    localparam logic [19:0] A_ID          = 20'h00500;
    localparam logic [19:0] A_VERSION     = 20'h00504;
    localparam logic [19:0] A_THRESHOLD   = 20'h00508;
    localparam logic [19:0] A_COUNT       = 20'h0050C;
    localparam logic [19:0] A_CONTROL     = 20'h00510;
    localparam logic [19:0] A_STATUS      = 20'h00514;
    localparam logic [19:0] A_TX_VALID    = 20'h00520;
    localparam logic [19:0] A_TX_READY    = 20'h00524;
    localparam logic [19:0] A_TX_LAST     = 20'h00528;
    localparam logic [19:0] A_AXIS_SEL    = 20'h0052C;
    localparam logic [19:0] A_AXIS_STALL  = 20'h00538;   // axis_select 卡死观测
    localparam logic [19:0] A_SEGM_STATE  = 20'h00530;
    localparam logic [19:0] A_SEGM_COUNT  = 20'h00534;
    localparam logic [19:0] A_RX_VALID    = 20'h00540;
    localparam logic [19:0] A_RX_READY    = 20'h00544;
    localparam logic [19:0] A_RX_FIFO0    = 20'h00548;
    localparam logic [19:0] A_RX_FIFO1    = 20'h0054C;
    localparam logic [19:0] A_RX_MUX      = 20'h00550;
    localparam logic [19:0] A_REQ_STATE   = 20'h00560;
    localparam logic [19:0] A_RESP_STATE  = 20'h00564;
    localparam logic [19:0] A_RX_PARSE    = 20'h00568;
    localparam logic [19:0] A_TX_BUILD    = 20'h0056C;
    localparam logic [19:0] A_QP_ACTIVE   = 20'h00570;
    localparam logic [19:0] A_DMA_STATE   = 20'h00574;
    localparam logic [19:0] A_BAS_OUTSTAND= 20'h00578;
    localparam logic [19:0] A_RESP_STICKY = 20'h0057C;
    localparam logic [19:0] A_RESP_CLEAR  = 20'h00580;
    localparam logic [19:0] A_SNAP        = 20'h00590;
    // ---- 每 lane RX 统计（0x05D0..0x05F0，紧接 SNAP 之后，占用原来未用的尾部）
    localparam logic [19:0] A_LANE0_FRAMES = 20'h005D0;
    localparam logic [19:0] A_LANE1_FRAMES = 20'h005D4;
    localparam logic [19:0] A_LANE0_ICRC   = 20'h005D8;
    localparam logic [19:0] A_LANE1_ICRC   = 20'h005DC;
    localparam logic [19:0] A_LANE0_DROP   = 20'h005E0;
    localparam logic [19:0] A_LANE1_DROP   = 20'h005E4;
    localparam logic [19:0] A_LANE_STAGING= 20'h005E8;
    localparam logic [19:0] A_LANE_PEAK    = 20'h005EC;
    localparam logic [19:0] A_LANE_CLR     = 20'h005F0;

    // ======================================================================
    // 分组寄存器（B6396 起）：按「RX lane」「RDMA core lane」「TX 汇合」分开，
    // 每个概念一块、lane 之间等距，偏移可读、加 lane 不用改基址。
    // 上面 0x0500..0x05F0 的旧地址全部保留（= 组 0 的别名），老脚本照常工作。
    // ======================================================================
    // ---- 组 A：RX lane（**MAC 输入**的每条 lane 一套，固定 2 条）
    //   每 lane 0x20 字节，lane i 的基址 = 0x0600 + 0x20*i
    //
    // 窗口宽度必须用 RX_LANES 而不是 LANES。LANES 是 **RDMA core lane 数**（B6405 起为 4），
    // 而这里的统计量来自 roce_rx_front 的两路 MAC 输入（物理上只有 2 路，lane_frames 等
    // 输入都只有 64 位）。若按 LANES 展开，LANES=4 时窗口会吃到 0x680，与组 B 的起点重叠，
    // 且 rx_lane_index 会取到 2/3，读到的是 64 位输入的越界位（综合裁成 0）。
    localparam int          RX_LANES         = 2;
    localparam logic [19:0] A_RX_LANE        = 20'h00600;
    localparam int          RX_LANE_STRIDE   = 32'h020;
    localparam logic [19:0] A_RX_LANE_FRAMES         = 20'h000;  // 帧数
    localparam logic [19:0] A_RX_LANE_ICRC_ERRORS    = 20'h004;  // ICRC 校验失败帧
    localparam logic [19:0] A_RX_LANE_DROPPED_FRAMES = 20'h008;  // staging 满整帧丢弃
    localparam logic [19:0] A_RX_LANE_STAGING_LEVEL  = 20'h00C;  // 当前暂存占用（拍）
    localparam logic [19:0] A_RX_LANE_STAGING_PEAK   = 20'h010;  // 峰值（拍），理论上限 504
    localparam logic [19:0] A_RX_LANE_MAC_FIFO       = 20'h014;  // {afull, empty}
    localparam logic [19:0] A_RX_LANE_PEAK_CLEAR     = 20'h018;  // WO 写任意值清该 lane 峰值
    // B6418：合并级事件（不分 lane，借两个 lane 窗口的 0x1C 各放一个）：
    //   0x061C = 顺序超时强制放行次数，0x063C = 空闲重新对齐序号次数。正常恒 0。
    localparam logic [19:0] A_RX_LANE_MERGE_EVENT    = 20'h01C;

    // ---- 组 D：RX demux（**RDMA core lane** 侧重分流统计，B6408 加）
    //   每 lane 0x10 字节，lane i 的基址 = 0x0640 + 0x10*i，共 LANES 条，占用 0x640..0x67F。
    //   这段刚好卡在组 A（0x600 + 0x20*2 = 0x640）与组 B（0x680）之间的空隙里。
    //   与组 A 的区别：组 A 是两路 MAC 物理输入的统计（谁在链路上收包），
    //   组 D 是分流之后 RDMA core lane 的统计（QPN 分到哪条引擎、那条引擎吃不吃得下）。
    localparam logic [19:0] A_RX_DEMUX          = 20'h00640;
    localparam int          RX_DEMUX_STRIDE     = 32'h010;
    localparam logic [19:0] A_DEMUX_LANE_FRAMES    = 20'h000;  // 分流到该 lane 的帧数
    localparam logic [19:0] A_DEMUX_LANE_STALL     = 20'h004;  // 该 lane FIFO 满、反压拍数
    localparam logic [19:0] A_DEMUX_LANE_SOP_STALL = 20'h008;  // 其中卡在帧首拍的次数

    // ---- 组 B：RDMA core lane（每个引擎实例一套，2 个）
    //   每 lane 0x40 字节，lane i 的基址 = 0x0680 + 0x40*i
    localparam logic [19:0] A_RDMA_CORE       = 20'h00680;
    localparam int          CORE_LANE_STRIDE  = 32'h040;
    localparam logic [19:0] A_CORE_REQUESTER_STATE   = 20'h000;  // req FSM + 重传计数
    localparam logic [19:0] A_CORE_RESPONDER_STATE   = 20'h004;  // resp FSM（main + out）
    localparam logic [19:0] A_CORE_RX_DISPATCH       = 20'h008;  // 本 lane 的 disp {busy, owner}
    localparam logic [19:0] A_CORE_TX_BUILD          = 20'h00C;  // tx build FSM + 组包状态
    localparam logic [19:0] A_CORE_ACTIVE_QP         = 20'h010;  // req 正在服务的 QP
    localparam logic [19:0] A_CORE_DMA_STATE         = 20'h014;  // read_credit / 在途
    localparam logic [19:0] A_CORE_BAS_OUTSTANDING   = 20'h018;  // 本 lane 的 BAS 未完成
    localparam logic [19:0] A_CORE_RESP_STICKY       = 20'h01C;  // 本 lane 的 sticky
    localparam logic [19:0] A_CORE_QP_CONTEXT_LOW    = 20'h020;  // 活动 QP 的 QPC 低 32 位
    localparam logic [19:0] A_CORE_PSN               = 20'h024;  // {unacked[23:0], next[7:0]} 见读口
    localparam logic [19:0] A_CORE_ACK_COUNTER       = 20'h028;  // ack_counter / reads_outstanding
    localparam logic [19:0] A_CORE_TX_OFFSET         = 20'h02C;  // 当前 WQE 内偏移

    // ---- 组 C：TX 汇合（三级 2:1 都是共享的，不属于任何 lane）
    // **B6405 地址后移 0x740 → 0x7C0**：组 B 的窗口是 0x680 + 0x40*LANES，
    // LANES=4 时占到 0x780，原来的 0x740 落在组 B 里、被 core_lane 的译码抢占，
    // 表现为读 TX 汇合状态时返回 lane3 的寄存器（工具侧看到的是"数值莫名其妙"）。
    // 移到 0x7C0 后组 A/B/C 三段互不重叠。rdmacli 的 DBG_TX_MERGE_BASE 必须同步。
    localparam logic [19:0] A_TX_MERGE                 = 20'h007C0;
    localparam logic [19:0] A_TX_MERGE_QDMA_STATE      = 20'h000;  // QDMA 与 RoCE 汇合
    localparam logic [19:0] A_TX_MERGE_QDMA_ABORTS     = 20'h004;  // 残包放弃计数
    localparam logic [19:0] A_TX_MERGE_LANE_STATE      = 20'h008;  // 两棵子树再 2:1（第三级）
    localparam logic [19:0] A_TX_MERGE_LANE_ABORTS     = 20'h00C;
    localparam logic [19:0] A_RX_SPLIT_STATE           = 20'h010;  // QPN 分流器 {payload_busy, owner}


    localparam logic [31:0] DEBUG_ID        = 32'h5244_4247;   // "RDBG"
    localparam logic [31:0] DEBUG_VERSION   = {8'd2, 8'd0, 16'(SNAP_WORDS)};
    localparam logic [7:0]  SNAP_TAG        = 8'h5A;

    // 通道号
    localparam int CH_TX0        = 0;    // qdma_h2d
    localparam int CH_TX1        = 1;    // qdma_to_regslice
    localparam int CH_TX2        = 2;    // qdma_to_select
    localparam int CH_TX3        = 3;    // select_to_segm
    localparam int CH_TX4        = 4;    // segm_to_reg
    localparam int CH_TX5        = 5;    // reg_to_h2l
    localparam int CH_TX6        = 6;    // gap_to_mac
    localparam int CH_REQ        = 8;
    localparam int CH_TXBUILD    = 9;
    localparam int CH_RESP       = 10;
    localparam int CH_RXPARSE    = 11;
    localparam int CH_BAS        = 12;
    localparam int CH_REQ1       = 13;   // lane1 的 roce_req（Phase 1 起才有）
    localparam int CH_RESP1      = 14;   // lane1 的 roce_resp
    localparam int STALL_CHANNEL_NUM = 15;

    // ------------------------------------------------------------ 跨域采样握手
    // core 域每 SAMPLE_PERIOD 拍翻转一次 sample_req；mac / pcie 域看到翻转就锁存一组
    // 影子寄存器并回一个 ack 翻转位，core 域把影子同步回来读。只搬电平不搬计数，
    // 丢一两拍无所谓；目的是让一批信号在 CSR 侧读到的是同一时刻的值。
    localparam int SAMPLE_PERIOD = 16;

    reg  [3:0]  sample_div;
    reg         sample_req;
    reg         mac_sample_ack, pcie_sample_ack;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    reg  [1:0]  mac_ack_sync, pcie_ack_sync;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    reg  [1:0]  sample_req_mac_sync, sample_req_pcie_sync;

    always @(posedge clk) begin
        if (rst) begin
            sample_div    <= 4'd0;
            sample_req    <= 1'b0;
            mac_ack_sync  <= 2'b00;
            pcie_ack_sync <= 2'b00;
        end else begin
            sample_div    <= sample_div + 4'd1;
            mac_ack_sync  <= {mac_ack_sync[0],  mac_sample_ack};
            pcie_ack_sync <= {pcie_ack_sync[0], pcie_sample_ack};
            if (sample_div == 4'd0)
                sample_req <= ~sample_req;
        end
    end

    // ---------------- MAC 域影子寄存器
    reg  [7:0]  m_tx_valid, m_tx_ready, m_tx_last;
    reg  [4:0]  m_axis_select;
    reg  [9:0]  m_segm_state;
    reg  [2:0]  m_rx_valid, m_rx_ready;
    reg  [31:0] m_rx_fifo0, m_rx_fifo1;
    reg  [13:0] m_rx_mux_fifo;
    reg  [31:0] m_segm_valid_cnt, m_segm_ready_cnt;
    reg         seg_valid_q, seg_ready_q;
    always @(posedge mac_clk) begin
        seg_valid_q <= mac_tx_valid[4];
        seg_ready_q <= mac_tx_ready[4];
    end
    reg         mac_req_seen;

    always @(posedge mac_clk) begin
        sample_req_mac_sync <= {sample_req_mac_sync[0], sample_req};
        if (mac_rst) begin
            mac_req_seen     <= 1'b0;
            mac_sample_ack   <= 1'b0;
            m_segm_valid_cnt <= 32'd0;
            m_segm_ready_cnt <= 32'd0;
        end else begin
            if (sample_req_mac_sync[1] != mac_req_seen) begin
                mac_req_seen   <= sample_req_mac_sync[1];
                mac_sample_ack <= sample_req_mac_sync[1];
                m_tx_valid     <= mac_tx_valid;
                m_tx_ready     <= mac_tx_ready;
                m_tx_last      <= mac_tx_last;
                m_axis_select  <= mac_axis_select;
                m_segm_state   <= mac_segm_state;
                m_rx_valid     <= mac_rx_valid;
                m_rx_ready     <= mac_rx_ready;
                m_rx_fifo0     <= mac_rx_fifo0;
                m_rx_fifo1     <= mac_rx_fifo1;
                m_rx_mux_fifo  <= mac_rx_mux_fifo;
            end
            // 组包吞吐计数：segm_to_reg 的 valid / ready 握手各自累计，
            // 两者同步涨就说明组包在推进；valid 涨而 ready 不涨就是下游反压。
            // B6419：先寄存一拍再计数（seg_valid_q / seg_ready_q）。B6418 tx_clkout：YuanRDMA u03_segm_to_h2l_slice
            // 的 filled → 本计数器 16 位使能，14 个端点 −0.028（走线 1.88 ns）。计数晚 1 拍，读数含义不变。
            if (seg_valid_q && seg_ready_q)  m_segm_valid_cnt <= m_segm_valid_cnt + 32'd1;
            if (seg_ready_q && !seg_valid_q) m_segm_ready_cnt <= m_segm_ready_cnt + 32'd1;
        end
    end

    // ---------------- PCIE 域影子寄存器
    reg  [63:0] p_ar_address;
    reg  [7:0]  p_ar_len;
    reg  [3:0]  p_ar_hs;
    reg  [31:0] p_aw_address_low;
    reg         pcie_req_seen;

    always @(posedge pcie_clk) begin
        sample_req_pcie_sync <= {sample_req_pcie_sync[0], sample_req};
        if (pcie_rst) begin
            pcie_req_seen   <= 1'b0;
            pcie_sample_ack <= 1'b0;
            p_ar_address    <= 64'd0;
            p_ar_len        <= 8'd0;
            p_ar_hs         <= 4'd0;
            p_aw_address_low<= 32'd0;
        end else begin
            if (sample_req_pcie_sync[1] != pcie_req_seen) begin
                pcie_req_seen    <= sample_req_pcie_sync[1];
                pcie_sample_ack  <= sample_req_pcie_sync[1];
                p_ar_address     <= pcie_ar_address;
                p_ar_len         <= pcie_ar_len;
                p_ar_hs          <= pcie_ar_hs;
                p_aw_address_low <= pcie_aw_address_low;
            end
        end
    end

    // mac / pcie 影子同步回 core
    reg  [7:0]  s_tx_valid, s_tx_ready, s_tx_last;
    reg  [4:0]  s_axis_select;
    reg  [9:0]  s_segm_state;
    reg  [2:0]  s_rx_valid, s_rx_ready;
    reg  [31:0] s_rx_fifo0, s_rx_fifo1;
    reg  [13:0] s_rx_mux_fifo;
    reg  [15:0] s_segm_valid_cnt, s_segm_ready_cnt;
    reg  [63:0] s_ar_address;
    reg  [7:0]  s_ar_len;
    reg  [3:0]  s_ar_hs;
    reg  [31:0] s_aw_address_low;

    always @(posedge clk) begin
        s_tx_valid       <= m_tx_valid;
        s_tx_ready       <= m_tx_ready;
        s_tx_last        <= m_tx_last;
        s_axis_select    <= m_axis_select;
        s_segm_state     <= m_segm_state;
        s_rx_valid       <= m_rx_valid;
        s_rx_ready       <= m_rx_ready;
        s_rx_fifo0       <= m_rx_fifo0;
        s_rx_fifo1       <= m_rx_fifo1;
        s_rx_mux_fifo    <= m_rx_mux_fifo;
        s_segm_valid_cnt <= m_segm_valid_cnt[15:0];
        s_segm_ready_cnt <= m_segm_ready_cnt[15:0];
        s_ar_address     <= p_ar_address;
        s_ar_len         <= p_ar_len;
        s_ar_hs          <= p_ar_hs;
        s_aw_address_low <= p_aw_address_low;
    end

    // ------------------------------------------------------------ 响应码 sticky
    reg        resp_sticky_clear;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    reg  [3:0] resp_sticky_sync1, resp_sticky_sync2;
    /* 清脉冲必须撑过源端的同步延迟。roce_bas_mon 里的 resp_sticky_pcie 在 pcie_clk 域清，
     * 回传要经它内部两级 core 域同步（resp_sticky_sync1/2）才落到本模块的输入上：
     *   写 0x0580 那一拍（记作 N）源端清零，本模块看到的 pcie_resp_sticky 要到 N+2 才变 0。
     * 所以只在 N 拍清 resp_sticky_sync1，N+2 拍又会把 residual 0x3 OR 回来，0x057C 读回复原。
     * 让内部清零窗口保持 4 拍，覆盖这段延迟；对外的 resp_sticky_clear_pulse 仍是单拍。 */
    reg  [2:0] resp_sticky_clear_ext;
    wire       resp_sticky_clear_win = resp_sticky_clear | (resp_sticky_clear_ext != 3'd0);
    always @(posedge clk) begin
        if (rst)                    resp_sticky_sync1 <= 4'd0;
        else if (resp_sticky_clear_win) resp_sticky_sync1 <= 4'd0;
        else                        resp_sticky_sync1 <= resp_sticky_sync1 | pcie_resp_sticky;
        resp_sticky_sync2 <= resp_sticky_sync1;
    end

    // ------------------------------------------------------------ 卡死检测
    localparam logic [23:0] STALL_COUNT_MAX = 24'hFF_FFF0;

    wire [7:0]  tx_stall_now   = s_tx_valid & ~s_tx_ready;

    /* FSM 类通道不能只看「非 IDLE」——满速运行时 FSM 一直非 IDLE，那样会天天误触发。
     * 判据改成：同一个非空闲状态连续保持（状态值不变）超过门限。真实卡死必然满足，
     * 正常流转每几拍就换状态，计数会被清零。 */
    /* 四个 FSM 的 hold 只保留各自的 state 字段，不跟着同一总线上的其它字段一起变：
     * req 的总线里还带 dispatch_reason / retry_left / reads_outstanding 等，它们随时会动，
     * 若整体比较，FSM 真停住时计数也会被这些无关字段反复清零，永远到不了门限。 */
    reg  [4:0]  req_state_hold;
    reg  [23:0] req_hold_count;
    reg  [6:0]  resp_state_hold;
    reg  [23:0] resp_hold_count;
    reg  [1:0]  txb_state_hold;
    reg  [23:0] txb_hold_count;
    reg  [2:0]  rxps_state_hold;
    reg  [23:0] rxps_hold_count;
    reg  [4:0]  req1_state_hold;       // lane1 roce_req
    reg  [23:0] req1_hold_count;
    reg  [6:0]  resp1_state_hold;      // lane1 roce_resp
    reg  [23:0] resp1_hold_count;
    reg         fsm_hold_rst;          // 软复位/清快照时清计数

    // 卡死检测与快照沿用「通道」模型，lane 0 仍然占用原来的 req/resp/txb 通道；
    // lane 1 的 req/resp 单独占两个新通道（13/14），这样任一 lane 卡住都能触发快照。
    // 快照内容仍以 lane 0 为主（SNAP 只有 16 个字），lane 1 的现场用分组寄存器读。
    wire [4:0]  req_state_now  = lane_req_state[4:0];
    wire [6:0]  resp_state_now = lane_resp_state[6:0];
    wire [1:0]  txb_state_now  = lane_tx_state[1:0];
    wire [2:0]  rxps_state_now = core_rx_state[2:0];
    // lane 1（LANES=2 时存在；LANES=1 时常量 0，不触发）
    localparam int LANE1 = (LANES > 1) ? 1 : 0;
    wire [4:0]  req1_state_now  = (LANES > 1) ? lane_req_state[LANE1*20 +: 5] : 5'd0;
    wire [6:0]  resp1_state_now = (LANES > 1) ? lane_resp_state[LANE1*7 +: 7] : 7'd0;

    wire req_stall_now  = (req_hold_count  >= stall_threshold[23:0]);
    wire resp_stall_now = (resp_hold_count >= stall_threshold[23:0]);
    wire req1_stall_now  = (req1_hold_count  >= stall_threshold[23:0]);
    wire resp1_stall_now = (resp1_hold_count >= stall_threshold[23:0]);
    wire txb_stall_now  = (txb_hold_count  >= stall_threshold[23:0]);
    wire rxps_stall_now = (rxps_hold_count >= stall_threshold[23:0]);
    // 未完成 AR >= 12：只有 480 beat 信用、单请求最多 33 beat，12 个以上在途且长期不降
    // 就是 R 通道不回来了。取 12 是因为 480/33 = 14，接近满信用即已无法再发新请求。
    wire bas_stall_now  = (core_bas_outstanding >= 8'd12);

    /* axis_select 卡死观测。pkt_gen 删除后顶层把第 1 路 s_axis_tvalid[1] 恒接 0，
     * 而 axis_select 的 select 状态机里 2'b10 -> 2'b01 的原始退路全都依赖 axis_last[1]，
     * 永远等不到；一旦落进 2'b10，s_axis_tready[0] 永久为 0，TX 从 axis_select 出口
     * 整条卡死（表现与 B6369 的 select_to_segm_tready 悬空完全一样）。
     *
     * 0x052C[4] 只能报"读的这一刻在不在非法态"，是瞬时值；TX 停了再读很可能已经错过。
     * 这里补粘滞位与驻留时长，任何一次落进 2'b10 都会留下痕迹。位布局见 0x0538。
     */
    reg         select_stuck_live;      // 当前就在 2'b10
    reg         select_stuck_seen;      // 曾经进过 2'b10（粘滞，读清零）
    reg  [7:0]  select_hold_cur_sat;    // 当前连续驻留 /256 拍，饱和 255
    reg  [7:0]  select_hold_max_sat;    // 历史最长驻留 /256 拍，饱和 255
    reg  [7:0]  select_hold_cur_div;    // 分频计数：满 255 让 _sat 加 1

    wire        select_illegal_now = s_axis_select[4];
    // 写 0x0538 bit0=1 清粘滞位与驻留计数，便于"清干净后再跑一轮"
    wire        select_stuck_clear = reg_write_enable &&
                                     (reg_write_offset == A_AXIS_STALL) &&
                                     reg_write_value[0];
    // 读 0x0538 时读清零。与 roce_csr 的 soft_rst_seen 同一套路：读回是组合块，
    // 清动作必须放在时钟块里，用读命中的单拍使能触发。
    wire        select_stuck_read  = reg_read_enable &&
                                     (reg_read_offset == A_AXIS_STALL);

    always @(posedge clk) begin
        if (rst || select_stuck_clear) begin
            select_stuck_live   <= 1'b0;
            select_stuck_seen   <= 1'b0;
            select_hold_cur_sat <= 8'd0;
            select_hold_max_sat <= 8'd0;
            select_hold_cur_div <= 8'd0;
        end else begin
            select_stuck_live <= select_illegal_now;

            /* 粘滞位：置位优先于读清零。否则"读取的同一拍刚好又落进非法态"时，
             * 清动作会把这次事件吞掉，等于漏报。 */
            if (select_illegal_now)
                select_stuck_seen <= 1'b1;
            else if (select_stuck_read)
                select_stuck_seen <= 1'b0;

            // 驻留计时：每 256 拍让 /256 计数器加一，饱和后停住——够判"停了多久"，不占逻辑
            if (select_illegal_now) begin
                if (select_hold_cur_div == 8'hFF) begin
                    select_hold_cur_div <= 8'd0;
                    if (select_hold_cur_sat != 8'hFF)
                        select_hold_cur_sat <= select_hold_cur_sat + 8'd1;
                end else begin
                    select_hold_cur_div <= select_hold_cur_div + 8'd1;
                end
                if (select_hold_cur_sat > select_hold_max_sat)
                    select_hold_max_sat <= select_hold_cur_sat;
            end else begin
                select_hold_cur_sat <= 8'd0;
                select_hold_cur_div <= 8'd0;
            end
        end
    end

    wire [STALL_CHANNEL_NUM-1:0] stall_now = {resp1_stall_now,     // 14 lane1 resp
                                              req1_stall_now,      // 13 lane1 req
                                              bas_stall_now,       // 12
                                              rxps_stall_now,      // 11
                                              resp_stall_now,      // 10
                                              txb_stall_now,       // 9
                                              req_stall_now,       // 8
                                              1'b0,                // 7 号通道不用
                                              tx_stall_now[6:0]};  // 6..0

    reg  [31:0] stall_threshold;
    reg  [23:0] stall_count [0:STALL_CHANNEL_NUM-1];
    reg         snap_valid;
    reg  [7:0]  snap_channel;
    reg  [1:0]  snap_domain;
    reg  [15:0] snap_count;
    reg  [31:0] snap_word [0:SNAP_WORDS-1];
    reg         force_snapshot;
    reg  [1:0]  snap_domain_next;

    // 优先编码：编号最小的超阈值通道
    reg  [3:0]  stall_first;
    reg         stall_any_first;
    integer     ch;
    always @* begin
        stall_first     = 4'd0;
        stall_any_first = 1'b0;
        for (ch = STALL_CHANNEL_NUM - 1; ch >= 0; ch = ch - 1) begin
            if (stall_count[ch] >= stall_threshold[23:0]) begin
                stall_first     = 4'(ch);
                stall_any_first = 1'b1;
            end
        end
    end
    wire stall_trigger = !snap_valid && (force_snapshot ||
                         (stall_threshold != 32'd0 && stall_any_first));

    always @(posedge clk) begin
        if (rst) begin
            stall_threshold <= 32'd1000;
            snap_valid      <= 1'b0;
            snap_channel    <= 8'd0;
            snap_domain     <= 2'd0;
            snap_domain_next<= 2'd0;
            snap_count      <= 16'd0;
            force_snapshot  <= 1'b0;
            fsm_hold_rst    <= 1'b0;
            resp_sticky_clear_ext <= 3'd0;
            req_state_hold  <= 5'h1F;   // 非 0 且不会误判为 REQ_IDLE，首拍一定"变化"
            resp_state_hold <= 7'd0;
            txb_state_hold  <= 2'd0;
            rxps_state_hold <= 3'd0;
            req_hold_count  <= 24'd0;
            resp_hold_count <= 24'd0;
            txb_hold_count  <= 24'd0;
            rxps_hold_count <= 24'd0;
            for (ch = 0; ch < STALL_CHANNEL_NUM; ch = ch + 1)
                stall_count[ch] <= 24'd0;
        end else begin
            force_snapshot    <= 1'b0;
            resp_sticky_clear <= 1'b0;
            resp_sticky_clear_pulse <= 1'b0;
            lane_peak_clear_pulse   <= 1'b0;
            // 清零窗口：写 0x0580 那拍装入 3，之后每拍减一，共撑 4 拍（含写那一拍），
            // 覆盖 roce_bas_mon 两级同步的回传延迟。见上方 resp_sticky_clear_win 的说明。
            if (resp_sticky_clear)      resp_sticky_clear_ext <= 3'd3;
            else if (resp_sticky_clear_ext != 3'd0)
                                        resp_sticky_clear_ext <= resp_sticky_clear_ext - 3'd1;
            fsm_hold_rst      <= 1'b0;

            /* FSM 停顿计数：状态没变化就一直加，一旦换状态立刻回零。
             * 但必须排除「停在空闲态」——四个 FSM 的空闲态都是数值 0（REQ_IDLE=5'd0、
             * roce_resp 的 MAIN_IDLE/OUT_IDLE=0、BUILD_PREP=2'd0、CAPTURE0=3'd0）。
             * 空载时状态恒为 0、永远不变，原来的写法会让计数一路加到门限，10 µs 就误触发
             * 一次快照；而且 snap_valid 一旦置位会挡住真正的卡死采样。所以进入空闲态就
             * 把计数清 0，只有「非空闲且不变」才算停住。 */
            if (fsm_hold_rst) begin
                req_hold_count  <= 24'd0;
                resp_hold_count <= 24'd0;
                txb_hold_count  <= 24'd0;
                rxps_hold_count <= 24'd0;
                req1_hold_count <= 24'd0;
                resp1_hold_count <= 24'd0;
            end else begin
                if ((req_state_now != req_state_hold) || (req_state_now == 5'd0)) begin
                    req_state_hold <= req_state_now;  req_hold_count <= 24'd0;
                end else if (req_hold_count < STALL_COUNT_MAX) begin
                    req_hold_count <= req_hold_count + 24'd1;
                end
                if ((resp_state_now != resp_state_hold) || (resp_state_now == 7'd0)) begin
                    resp_state_hold <= resp_state_now; resp_hold_count <= 24'd0;
                end else if (resp_hold_count < STALL_COUNT_MAX) begin
                    resp_hold_count <= resp_hold_count + 24'd1;
                end
                if ((txb_state_now != txb_state_hold) || (txb_state_now == 2'd0)) begin
                    txb_state_hold <= txb_state_now;  txb_hold_count <= 24'd0;
                end else if (txb_hold_count < STALL_COUNT_MAX) begin
                    txb_hold_count <= txb_hold_count + 24'd1;
                end
                if ((rxps_state_now != rxps_state_hold) || (rxps_state_now == 3'd0)) begin
                    rxps_state_hold <= rxps_state_now; rxps_hold_count <= 24'd0;
                end else if (rxps_hold_count < STALL_COUNT_MAX) begin
                    rxps_hold_count <= rxps_hold_count + 24'd1;
                end
                // lane1：判据与 lane0 完全一致（非空闲且状态不变）
                if ((req1_state_now != req1_state_hold) || (req1_state_now == 5'd0)) begin
                    req1_state_hold <= req1_state_now;  req1_hold_count <= 24'd0;
                end else if (req1_hold_count < STALL_COUNT_MAX) begin
                    req1_hold_count <= req1_hold_count + 24'd1;
                end
                if ((resp1_state_now != resp1_state_hold) || (resp1_state_now == 7'd0)) begin
                    resp1_state_hold <= resp1_state_now; resp1_hold_count <= 24'd0;
                end else if (resp1_hold_count < STALL_COUNT_MAX) begin
                    resp1_hold_count <= resp1_hold_count + 24'd1;
                end
            end

            if (reg_write_enable) begin
                case (reg_write_offset)
                    A_THRESHOLD: stall_threshold <= reg_write_value;
                    A_CONTROL: begin
                        if (reg_write_value == 32'h0000_0002) begin
                            // 清快照 + 清各通道计数，准备下一次观测
                            snap_valid   <= 1'b0;
                            snap_count   <= 16'd0;
                            fsm_hold_rst <= 1'b1;
                            for (ch = 0; ch < STALL_CHANNEL_NUM; ch = ch + 1)
                                stall_count[ch] <= 24'd0;
                        end else begin
                            force_snapshot <= 1'b1;
                        end
                    end
                    A_RESP_CLEAR: begin
                        resp_sticky_clear       <= 1'b1;
                        resp_sticky_clear_pulse <= 1'b1;
                    end
                    A_LANE_CLR: begin
                        // 写任意值清两路暂存峰值（计数是累计量，不清）
                        lane_peak_clear_pulse <= 1'b1;
                    end
                    default: ;
                endcase
            end

            // 各通道计数
            for (ch = 0; ch < STALL_CHANNEL_NUM; ch = ch + 1) begin
                if (stall_now[ch]) begin
                    if (stall_count[ch] < STALL_COUNT_MAX)
                        stall_count[ch] <= stall_count[ch] + 24'd1;
                end else if (!snap_valid) begin
                    stall_count[ch] <= 24'd0;   // 快照锁住后保留现场，不再清零
                end
            end

            // 锁存快照
            if (stall_trigger) begin
                snap_valid   <= 1'b1;
                snap_channel <= force_snapshot ? 8'hFF : {4'd0, stall_first};
                // 通道 0..6 是 TX 流水（mac 域），12 是 BAS（pcie 域），其余是 core 域
                snap_domain      <= snap_domain_next;
                snap_domain_next <= force_snapshot ? 2'd1 :
                                    (stall_first <= 4'(CH_TX6)) ? 2'd0 :
                                    (stall_first == 4'(CH_BAS)) ? 2'd2 : 2'd1;
                snap_count   <= (snap_count == 16'hFFFF) ? snap_count : snap_count + 16'd1;

                /* 快照字按字段赋值（不用一个大拼接，避免位宽算错）。
                 * SNAP[0] [7:0]=0x5A 标记 [9:8]=域 [17:10]=通道 [31:24]=0xA5 */
                for (ch = 0; ch < SNAP_WORDS; ch = ch + 1)
                    snap_word[ch] <= 32'd0;
                snap_word[0][7:0]   <= SNAP_TAG;
                snap_word[0][9:8]   <= force_snapshot ? 2'd1 : snap_domain_next;
                snap_word[0][17:10] <= force_snapshot ? 8'hFF : {4'd0, stall_first};
                snap_word[0][31:24] <= 8'hA5;
                snap_word[1]        <= force_snapshot ? 32'd0 : {8'd0, stall_count[stall_first]};
                // SNAP[2..4]：MAC 域 TX/RX 各级
                snap_word[2][7:0]   <= s_tx_valid;
                snap_word[2][15:8]  <= s_tx_ready;
                snap_word[2][23:16] <= s_tx_last;
                snap_word[3][4:0]   <= s_axis_select;
                snap_word[3][14:5]  <= s_segm_state;
                snap_word[4][2:0]   <= s_rx_valid;
                snap_word[4][18:16] <= s_rx_ready;
                // SNAP[5]：RX FIFO 水位（每 lane 取低 8 位 afull + 低 8 位 empty）
                snap_word[5][7:0]   <= s_rx_fifo0[7:0];
                snap_word[5][15:8]  <= s_rx_fifo0[23:16];
                snap_word[5][23:16] <= s_rx_fifo1[7:0];
                snap_word[5][31:24] <= s_rx_fifo1[23:16];
                // SNAP[6]：CORE 两个 FSM（req 截 15 位，最高位 local_error 见 0x0560）
                snap_word[6][14:0]  <= lane_req_state[0 +: 15];
                snap_word[6][22:15] <= {1'b0, lane_resp_state[0 +: 7]};
                // SNAP[7]：组包 / 解析 FSM
                snap_word[7][10:0]  <= lane_tx_state[0 +: 11];
                snap_word[7][27:12] <= core_rx_state;
                // SNAP[8..11]：QP 上下文
                snap_word[8]        <= lane_qp_context_low[0 +: 32];
                snap_word[9][23:0]  <= lane_next_psn[0 +: 24];
                snap_word[10]       <= lane_tx_offset[0 +: 32];
                snap_word[11][4:0]  <= lane_reads_outstanding[0 +: 5];
                snap_word[11][10:5] <= lane_ack_counter[0 +: 6];
                // SNAP[12..15]：BAS 当前在 AXI 上的那笔请求
                snap_word[12]       <= s_ar_address[63:32];
                snap_word[13]       <= s_ar_address[31:0];
                snap_word[14][7:0]  <= s_ar_len;
                snap_word[14][11:8] <= s_ar_hs;
                snap_word[15]       <= s_aw_address_low;
            end
        end
    end

    // ------------------------------------------------------------ 读（组合）
    wire [19:0] snap_offset = reg_read_offset - A_SNAP;
    wire [3:0]  snap_index  = snap_offset[5:2];

    // ------------------------------------------------------------ 分组地址译码
    // 组 A / B 的偏移是「lane 基址 + 组内字偏移」，所以先算出 lane 序号和组内偏移。
    // 用减法 + 位切分而不是 case 列表，加 lane 只要改 LANES 参数。
    wire        in_rx_lane    = (reg_read_offset >= A_RX_LANE) &&
                                (reg_read_offset <  A_RX_LANE  + 20'(RX_LANE_STRIDE  * RX_LANES));
    wire [19:0] rx_lane_rel   = reg_read_offset - A_RX_LANE;
    wire [3:0]  rx_lane_index = 4'(rx_lane_rel / 20'(RX_LANE_STRIDE));
    wire [19:0] rx_lane_word  = 20'(rx_lane_rel % 20'(RX_LANE_STRIDE));

    wire        in_core_lane    = (reg_read_offset >= A_RDMA_CORE) &&
                                  (reg_read_offset <  A_RDMA_CORE + 20'(CORE_LANE_STRIDE * LANES));
    wire [19:0] core_lane_rel   = reg_read_offset - A_RDMA_CORE;
    wire [3:0]  core_lane_index = 4'(core_lane_rel / 20'(CORE_LANE_STRIDE));
    wire [19:0] core_lane_word  = 20'(core_lane_rel % 20'(CORE_LANE_STRIDE));

    wire        in_tx_merge    = (reg_read_offset >= A_TX_MERGE) &&
                                 (reg_read_offset <  A_TX_MERGE + 20'h20);
    wire [4:0]  tx_merge_word  = (reg_read_offset - A_TX_MERGE);

    // 组 D：RX demux（0x640 + 0x10*i），按 RDMA core lane 展开
    wire        in_rx_demux     = (reg_read_offset >= A_RX_DEMUX) &&
                                  (reg_read_offset <  A_RX_DEMUX + 20'(RX_DEMUX_STRIDE * LANES));
    wire [19:0] rx_demux_rel    = reg_read_offset - A_RX_DEMUX;
    wire [3:0]  rx_demux_index  = 4'(rx_demux_rel / 20'(RX_DEMUX_STRIDE));
    wire [19:0] rx_demux_word   = 20'(rx_demux_rel % 20'(RX_DEMUX_STRIDE));

    always @* begin
        reg_read_value = 32'hdeadbeef;
        if (reg_read_offset >= A_SNAP && reg_read_offset < A_SNAP + 20'(4*SNAP_WORDS))
            reg_read_value = snap_word[snap_index];
        else case (reg_read_offset)
            A_ID:           reg_read_value = DEBUG_ID;
            A_VERSION:      reg_read_value = DEBUG_VERSION;
            A_THRESHOLD:    reg_read_value = stall_threshold;
            A_COUNT:        reg_read_value = {16'd0, snap_count};
            /* [0]=有效 [9:8]=域 [23:16]=通道 */
            A_STATUS:       reg_read_value = {8'd0, snap_channel, 6'd0, snap_domain, 7'd0, snap_valid};
            A_TX_VALID:     reg_read_value = {24'd0, s_tx_valid};
            A_TX_READY:     reg_read_value = {24'd0, s_tx_ready};
            A_TX_LAST:      reg_read_value = {24'd0, s_tx_last};
            A_AXIS_SEL:     reg_read_value = {27'd0, s_axis_select};
            A_SEGM_STATE:   reg_read_value = {22'd0, s_segm_state};
            A_SEGM_COUNT:   reg_read_value = {s_segm_ready_cnt, s_segm_valid_cnt};
            A_AXIS_STALL: begin
                /* 位布局见地址表 0x0538。
                 * 读清零在时钟块里做（见 select_stuck_read），这里只组合读，
                 * 不能在 @* 块里写状态位。
                 * 此前最后一个字段写成 {3'd0, select_hold_cur_sat[4:0]}（8 位），整条拼接
                 * 共 2+6+8+8+1+1+1+8 = 35 位，赋给 32 位被静默截掉最高 3 位，导致
                 * select / max_sat / seen / live 全部错位。去掉那 3 位补零后正好 32 位。 */
                reg_read_value = {2'b00,                      // [31:30] 留空
                                  {4'd0, s_axis_select[1:0]}, // [29:24] select 当前值
                                  select_hold_max_sat,        // [23:16] 历史最长驻留 /256 拍
                                  8'd0,                       // [15:8]  留空
                                  select_stuck_live,          // [7] 当前在 2'b10
                                  select_stuck_seen,          // [6] 曾经进过（读清零）
                                  select_illegal_now,         // [5] s_axis_select[4] 原样
                                  select_hold_cur_sat[4:0]};  // [4:0] 当前驻留 /256（低 5 位）
            end
            A_RX_VALID:     reg_read_value = {29'd0, s_rx_valid};
            A_RX_READY:     reg_read_value = {29'd0, s_rx_ready};
            A_RX_FIFO0:     reg_read_value = s_rx_fifo0;
            A_RX_FIFO1:     reg_read_value = s_rx_fifo1;
            A_RX_MUX:       reg_read_value = {18'd0, s_rx_mux_fifo};
            // ---- 旧地址：= 组 0 的别名，老脚本与老文档继续可用 ----
            A_REQ_STATE:    reg_read_value = {12'd0, lane_req_state[0 +: 20]};
            A_RESP_STATE:   reg_read_value = {25'd0, lane_resp_state[0 +: 7]};
            A_RX_PARSE:     reg_read_value = {16'd0, core_rx_state};
            A_TX_BUILD:     reg_read_value = {21'd0, lane_tx_state[0 +: 11]};
            // 旧地址别名：字段布局不变，QP 索引取 lane 0（与改名之前的行为一致）；
            // QP 扩到 32 以上时用 A_CORE_ACTIVE_QP 读完整索引
            A_QP_ACTIVE:    reg_read_value = {lane_qp_psn[23:0], 1'b0, lane_qp_state[2:0],
                                              lane_qp_index[3:0]};
            A_DMA_STATE:    reg_read_value = {8'd0, lane_dma_state[0 +: 14]};
            A_BAS_OUTSTAND: reg_read_value = {16'd0, core_bas_outstanding, core_bas_live};
            A_RESP_STICKY:  reg_read_value = {28'd0, resp_sticky_sync2};
            A_LANE0_FRAMES: reg_read_value = lane_frames[31:0];
            A_LANE1_FRAMES: reg_read_value = lane_frames[63:32];
            A_LANE0_ICRC:   reg_read_value = lane_icrc_error[31:0];
            A_LANE1_ICRC:   reg_read_value = lane_icrc_error[63:32];
            A_LANE0_DROP:   reg_read_value = lane_drop[31:0];
            A_LANE1_DROP:   reg_read_value = lane_drop[63:32];
            A_LANE_STAGING: reg_read_value = {12'd0, lane_staging};
            A_LANE_PEAK:    reg_read_value = {12'd0, lane_staging_peak};
            default: begin
                /* ---- 组 A：RX lane（0x0600 + 0x20*i）----
                 * 每条 MAC 输入一路，字段等距，加 lane 只改 LANES 参数与基址不冲突。 */
                if (in_rx_lane)
                    case (rx_lane_word)
                        A_RX_LANE_FRAMES:         reg_read_value = lane_frames      [rx_lane_index*32 +: 32];
                        A_RX_LANE_ICRC_ERRORS:    reg_read_value = lane_icrc_error  [rx_lane_index*32 +: 32];
                        A_RX_LANE_DROPPED_FRAMES: reg_read_value = lane_drop        [rx_lane_index*32 +: 32];
                        A_RX_LANE_STAGING_LEVEL:  reg_read_value = {22'd0, lane_staging     [rx_lane_index*10 +: 10]};
                        A_RX_LANE_STAGING_PEAK:   reg_read_value = {22'd0, lane_staging_peak[rx_lane_index*10 +: 10]};
                        A_RX_LANE_MAC_FIFO:       reg_read_value = (rx_lane_index == 0) ? s_rx_fifo0 : s_rx_fifo1;
                        A_RX_LANE_MERGE_EVENT:    reg_read_value = rx_merge_events  [rx_lane_index*32 +: 32];
                        default:                  reg_read_value = 32'hdeadbeef;
                    endcase
                /* ---- 组 B：RDMA core lane（0x0680 + 0x40*i）---- */
                else if (in_core_lane)
                    case (core_lane_word)
                        A_CORE_REQUESTER_STATE:  reg_read_value = {12'd0, lane_req_state[core_lane_index*20 +: 20]};
                        A_CORE_RESPONDER_STATE:  reg_read_value = {25'd0, lane_resp_state[core_lane_index*7 +: 7]};
                        A_CORE_RX_DISPATCH:      reg_read_value = {30'd0, lane_disp_busy_owner[core_lane_index*2 +: 2]};
                        A_CORE_TX_BUILD:         reg_read_value = {21'd0, lane_tx_state[core_lane_index*11 +: 11]};
                        A_CORE_ACTIVE_QP:        reg_read_value = {lane_qp_psn  [core_lane_index*24 +: 24],
                                                                   lane_qp_state[core_lane_index*3 +: 3],
                                                                   lane_qp_index[core_lane_index*QP_W +: QP_W]};
                        A_CORE_DMA_STATE:        reg_read_value = {18'd0, lane_dma_state[core_lane_index*14 +: 14]};
                        A_CORE_BAS_OUTSTANDING:  reg_read_value = {16'd0, core_bas_outstanding, core_bas_live};
                        A_CORE_RESP_STICKY:      reg_read_value = {28'd0, resp_sticky_sync2};
                        A_CORE_QP_CONTEXT_LOW:   reg_read_value = lane_qp_context_low[core_lane_index*32 +: 32];
                        A_CORE_PSN:              reg_read_value = lane_next_psn      [core_lane_index*24 +: 24];
                        A_CORE_ACK_COUNTER:      reg_read_value = {21'd0, lane_ack_counter[core_lane_index*6 +: 6],
                                                                   5'd0};
                        A_CORE_TX_OFFSET:        reg_read_value = lane_tx_offset     [core_lane_index*32 +: 32];
                        default:                 reg_read_value = 32'hdeadbeef;
                    endcase
                /* ---- 组 C：TX 汇合与 RX 分流（共享，无 lane）---- */
                else if (in_tx_merge)
                    case (tx_merge_word)
                        A_TX_MERGE_QDMA_STATE:  reg_read_value = {29'd0, tx_merge_qdma_state};
                        A_TX_MERGE_QDMA_ABORTS: reg_read_value = {16'd0, tx_merge_qdma_aborts};
                        A_TX_MERGE_LANE_STATE:  reg_read_value = {29'd0, tx_merge_lane_state};
                        A_TX_MERGE_LANE_ABORTS: reg_read_value = {16'd0, tx_merge_lane_aborts};
                        A_RX_SPLIT_STATE:       reg_read_value = {28'd0, core_rx_split_state};
                        default:                reg_read_value = 32'hdeadbeef;
                    endcase
                /* ---- 组 D：RX demux（0x640 + 0x10*i，按 RDMA core lane）---- */
                else if (in_rx_demux)
                    case (rx_demux_word)
                        A_DEMUX_LANE_FRAMES:    reg_read_value = demux_lane_frames    [rx_demux_index*32 +: 32];
                        A_DEMUX_LANE_STALL:     reg_read_value = demux_lane_stall     [rx_demux_index*32 +: 32];
                        A_DEMUX_LANE_SOP_STALL: reg_read_value = demux_lane_sop_stall [rx_demux_index*32 +: 32];
                        default:                reg_read_value = 32'hdeadbeef;
                    endcase
                else
                    reg_read_value = 32'hdeadbeef;
            end
        endcase
    end
    wire unused_read_enable = reg_read_enable;
endmodule
`default_nettype wire
