// roce_engine.sv
// Phase 1 per-lane 引擎（core_clk 域，TX 输出在 mac_clk）：一个 RoCEv2 RC 引擎实例。
// roce_top 例化 LANES 个本模块，外加共享的 roce_pcie_hub / roce_rx_qpn_split / roce_cq。
//
// 分工：
//   per-lane（本模块）：roce_tbl、roce_dma_arb、roce_dma（虚拟 BAS）、roce_dma_test、
//                       roce_rx_disp、roce_resp、roce_req、roce_tx、roce_tx_out。
//   共享（roce_top）：  AVMM/CSR、软复位、roce_rx_front、roce_rx_parse、QPN 分流、
//                       roce_cq（CQ 环只能有一个 producer index）、roce_pcie_hub、
//                       roce_bas_mon（监视真实 BAS）、roce_debug、TX 汇合、计数器合并。
//
// QP → lane 绑定：qp_index[LANE_W-1:0] == LANE_ID（奇偶交错）。
//   - 表写广播到所有 lane（每 lane 一份完整的 16 QP / MPT / MTT / CQC），写入时序完全
//     一致，所以 table_ack 取 lane 0 即可；QPC 回读由 roce_top 按 index 选 lane
//     （硬件置错只发生在属主 lane）。
//   - SQ/RQ doorbell 只放给属主 lane。否则非属主 lane 的 req 也会看到 producer 前进，
//     把同一个 WQE 再发一遍。非属主 QP 在本 lane 里 producer == consumer，永远空闲。
//   - RX 只会收到属主 QP 的包（roce_rx_qpn_split 保证）。
//
// CQ：本 lane 的 resp/req 产生 CQE，送到共享 roce_cq；roce_cq 写回时经本 lane 的
//   DMA 写客户端 2（cq_dma_*）发出，CQE 与它前面的 payload 同一 AXI ID，保序不丢。
`default_nettype none
`timescale 1ns/1ps
`include "roce_bas_if.vh"
module roce_engine
    import roce_pkg::*;
#(
    parameter int DATA_W         = 1024,
    parameter int USERF_W        = 7,
    parameter int CORE_CLOCK_MHZ = 250,
    parameter int LANES          = 2,
    parameter int LANE_ID        = 0
)(
    input  wire                   core_clk,
    input  wire                   dp_rst,
    input  wire                   pcie_clk,
    input  wire                   dp_pcie_rst,
    input  wire                   mac_clk,
    input  wire                   dp_mac_rst,
    // 配置
    input  wire [47:0]            local_mac,
    input  wire [31:0]            local_ip,
    // 表（广播写）
    input  wire                   table_request,
    input  wire                   table_write_enable,
    input  wire [3:0]             table_select,
    input  wire [23:0]            table_index,
    input  wire [511:0]           table_write_data,
    output wire                   table_ack,
    output wire                   table_error,
    output wire [511:0]           table_read_data,
    output wire [QP_NUM*512-1:0]  qpc_o,                 // 调试与共享 CQ 用（只取 lane 0）
    output wire [CQ_NUM*$bits(cqc_t)-1:0] cqc_flat,
    output wire [CQ_NUM-1:0]      cq_reset,
    // doorbell（未过滤，本模块按 QP 归属过滤）
    input  wire                   doorbell_sq_valid,
    input  wire                   doorbell_rq_valid,
    input  wire [31:0]            doorbell_data,
    // DMA 自测（只有 lane 0 接 start，其余 lane 恒 0）
    input  wire [63:0]            dma_test_source,
    input  wire [63:0]            dma_test_destination,
    input  wire [12:0]            dma_test_length,
    input  wire [31:0]            dma_test_repeat,
    input  wire                   dma_test_start,
    output wire                   dma_test_busy,
    output wire                   dma_test_done,
    output wire                   dma_test_error,
    output wire [31:0]            dma_test_cycles,
    // 虚拟 BAS（pcie_clk 域，接 roce_pcie_hub）
    output wire [`BAS_M2S_W-1:0]  virt_bas_m2s,
    input  wire [`BAS_S2M_W-1:0]  virt_bas_s2m,
    // PFC 收方向（2026-11-09 起由 roce_pfc 统一判定，已含 honor 掩码 / 看门狗 / ANY_ALL）：
    //   rx_pfc         core 域生效 pause，[8]=802.3x，[7:0]=每优先级 —— roce_req 派发、roce_resp 回包准入
    //   pfc_gate_enable = ~REG_CTRL[2]（PFC_GATE_DIS），与 roce_pfc 的 CTRL.RX_EN 相与后才挡
    //   resp_gate      CTRL.RESP_GATE：ACK/READ RESP 是否也受 pause 约束
    //   pause_mac      mac 域生效 pause，给本 lane TX 出口挡帧（roce_pfc_egress）
    //   egress_gate    CTRL.EGRESS_GATE（mac 域）
    input  wire  [8:0]            rx_pfc,
    input  wire                   pfc_gate_enable,
    input  wire                   resp_gate,
    input  wire  [8:0]            pause_mac,
    input  wire                   egress_gate,
    output wire                   egress_hold,
    // ECN / CNP（阶段 2）：本 lane 收到 CE 包 → cnp_request 挂起；roce_cnp 限频后给 grant，
    // 本 lane 用该 QP 的 QPC 组一个 CNP 从本 lane 的 roce_tx 发出（dnp 必须是属主 lane）。
    input  wire                   cnp_grant,
    input  wire                   cnp_en,
    input  wire                   cnp_np_en,            // B6434：NP_EN，挂起位与已锁存 grant 都受它约束
    input  wire  [7:0]            cnp_tos,
    input  wire                   cnp_becn,             // B6434：CNP 的 BTH BECN（0xA14[0]）
    input  wire                   cnp_fecn,             // B6434：CNP 的 BTH FECN（0xA14[1]）
    output wire                   cnp_request,
    output wire                   event_ecn_marked,
    output wire                   event_cnp_sent,
    output wire                   event_cnp_handled,     // 收到并接受的 CNP（本 QP 处于 RTS）
    output wire                   event_cnp_ignored,     // 收到但丢弃的 CNP（QP 非法 / 非 RTS）
    // DCQCN（阶段 3）：每 QP 的 CNP / 准入事件，全部送给 roce_top 的全局上下文表。
    // 用 one-hot 而不是「索引 + valid」：roce_top 要把 4 个 lane 的同名事件或起来，
    // one-hot 直接或即可，不用对 4 个索引做比较。
    output wire  [QP_NUM-1:0]     event_rx_cnp_qp,     // 收到 CNP 的 QP（one-hot）
    output wire  [QP_NUM-1:0]     event_tx_admit_qp,   // 被准入发包的 QP（one-hot）
    output wire  [12:0]           event_tx_admit_length,
    // 全局速率准入（roce_dcqcn 输出，broadcast 到所有 lane；每位对应全局 QP 索引）
    input  wire  [QP_NUM-1:0]     tx_rate_ready,
    // RX（头/payload 数据广播，valid 由 roce_rx_qpn_split 只对本 lane 拉高）
    input  wire                   rx_header_valid,
    output wire                   rx_header_ready,
    input  rx_hdr_t               rx_header,
    input  wire                   rx_payload_valid,
    output wire                   rx_payload_ready,
    input  wire [1023:0]          rx_payload_data,
    input  wire                   rx_payload_last,
    // CQE 出口（到共享 roce_cq）
    output wire                   resp_cqe_valid,
    input  wire                   resp_cqe_ready,
    output wire [3:0]             resp_cqe_cq,
    output wire [127:0]           resp_cqe_data,
    output wire                   req_cqe_valid,
    input  wire                   req_cqe_ready,
    output wire [3:0]             req_cqe_cq,
    output wire [127:0]           req_cqe_data,
    // 共享 roce_cq 的写回经本 lane DMA 写客户端 2
    input  wire                   cq_dma_write_request_valid,
    output wire                   cq_dma_write_request_ready,
    input  wire [63:0]            cq_dma_write_request_address,
    input  wire [63:0]            cq_dma_write_request_page1,
    input  wire [12:0]            cq_dma_write_request_length,
    input  wire                   cq_dma_write_valid,
    output wire                   cq_dma_write_ready,
    input  wire [1023:0]          cq_dma_write_data,
    // TX（mac_clk 域，接 TX 汇合）
    output wire                   tx_valid,
    input  wire                   tx_ready,
    output wire [DATA_W-1:0]      tx_data,
    output wire [USERF_W-1:0]     tx_last_bytes,
    output wire                   tx_last,
    // 计数事件（core_clk，单拍）
    output wire                   event_tx_packet,
    output wire                   event_rx_packet,
    output wire                   event_duplicate,
    output wire                   event_sequence_error,
    output wire                   event_tx_ack,
    output wire                   event_tx_nak,
    output wire                   event_rx_ack,
    output wire                   event_rx_nak,
    output wire                   event_rx_rnr,
    output wire                   event_rnr_nak,
    output wire                   event_retransmit_timeout,
    output wire                   event_retransmit_nak,
    output wire                   event_access_error,
    output wire                   event_bad,
    output wire  [8*32-1:0]       dbg_access_snapshot,
    input  wire                   dbg_access_snapshot_clr,
    output wire                   event_page_hit,
    output wire                   event_page_miss,
    // 调试
    output wire [127:0]           req_debug_state,
    output wire [6:0]             resp_debug_state,
    output wire [9:0]             tx_debug_state,
    output wire [13:0]            dma_debug_state,
    output wire [1:0]             debug_disp_busy_owner
);
    localparam int LANE_W = (LANES <= 2) ? 1 : (LANES <= 4) ? 2 : 3;
    localparam int CQC_W  = $bits(cqc_t);

    // ------------------------------------------------------------ core 域复位第 3 级（B6417）
    // roce_top 已把 dp_rst 寄存两级（全局一根 → 每 lane 一根），这里按子模块再复制一份，
    // 每份只扇出到一个子模块，fitter 能把它放在该子模块旁边。dont_merge 防止综合把这些
    // 逻辑相同的寄存器并回一根（并回去就又是 B6416 那根 1.7 + 1.6 ns 的长网）。
    // 所有子模块同拍断言/释放，与 roce_top 里共享模块的第 3 级对齐。
    (* dont_merge *) reg rst_tbl, rst_arb, rst_dma, rst_test, rst_disp, rst_resp, rst_req, rst_tx, rst_tx_out, rst_glue;
    always @(posedge core_clk) begin
        rst_tbl    <= dp_rst;
        rst_arb    <= dp_rst;
        rst_dma    <= dp_rst;
        rst_test   <= dp_rst;
        rst_disp   <= dp_rst;
        rst_resp   <= dp_rst;
        rst_req    <= dp_rst;
        rst_tx     <= dp_rst;
        rst_tx_out <= dp_rst;
        rst_glue   <= dp_rst;     // 本模块内的 skid / 头寄存
    end

    // doorbell 按 QP 归属过滤（doorbell_data[3:0] = QP index）
    wire owns_doorbell_qp   = (doorbell_data[LANE_W-1:0] == LANE_W'(LANE_ID));
    wire lane_doorbell_sq   = doorbell_sq_valid && owns_doorbell_qp;
    wire lane_doorbell_rq   = doorbell_rq_valid && owns_doorbell_qp;

    // ------------------------------------------------------------ 资源表
    wire [QP_NUM*512-1:0] qpc;
    wire [QP_NUM*3-1:0]   qp_state_flat;
    wire [QP_NUM-1:0]     qp_state_change, qp_set_error, qp_set_error_requester, qp_set_error_responder;
    cqc_t                 cqc [CQ_NUM];
    wire [2:0]            translate_valid, translate_ready, translate_response;
    wire [95:0]           translate_key;
    wire [191:0]          translate_virtual_address;
    wire [38:0]           translate_length;
    wire [11:0]           translate_access;
    wire [47:0]           translate_protection_domain;
    wire [63:0]           translate_physical_address0, translate_physical_page1;
    wire                  translate_error;
    assign qp_set_error = qp_set_error_requester | qp_set_error_responder;
    assign qpc_o        = qpc;
    genvar ci;
    generate
        for (ci = 0; ci < CQ_NUM; ci = ci + 1) begin : gen_cqc
            assign cqc_flat[ci*CQC_W +: CQC_W] = cqc[ci];
        end
    endgenerate

    roce_tbl #(.CLIENTS(3)) u_tbl (
        .clk(core_clk), .rst(rst_tbl),
        .table_request(table_request), .table_write_enable(table_write_enable),
        .table_select(table_select), .table_index(table_index),
        .table_write_data(table_write_data), .table_ack(table_ack),
        .table_error(table_error), .table_read_data(table_read_data),
        .qpc(qpc), .qp_state_o(qp_state_flat), .qp_state_change(qp_state_change),
        .qp_set_error(qp_set_error), .cqc(cqc), .cq_reset(cq_reset),
        .translate_valid(translate_valid), .translate_ready(translate_ready),
        .translate_key(translate_key), .translate_virtual_address(translate_virtual_address),
        .translate_length(translate_length), .translate_access(translate_access),
        .translate_protection_domain(translate_protection_domain),
        .translate_response(translate_response),
        .translate_physical_address0(translate_physical_address0),
        .translate_physical_page1(translate_physical_page1),
        .translate_error(translate_error)
    );

    // ------------------------------------------------------------ DMA
    //   读：0 req WQE / 1 resp RQ WQE / 2 tx payload / 3 自测
    //   写：0 resp 落地 / 1 req READ 数据 / 2 CQE（共享 roce_cq 经此口）/ 3 自测
    wire [3:0]    client_read_request_valid, client_read_request_ready;
    wire [3:0]    client_read_valid, client_read_ready;
    wire [255:0]  client_read_request_address, client_read_request_page1;
    wire [51:0]   client_read_request_length;
    wire [1023:0] client_read_data;
    wire [127:0]  client_read_keep;
    wire          client_read_last, client_read_error;
    wire [3:0]    client_write_request_valid, client_write_request_ready;
    wire [3:0]    client_write_valid, client_write_ready, client_write_complete;
    wire [255:0]  client_write_request_address, client_write_request_page1;
    wire [51:0]   client_write_request_length;
    wire [4095:0] client_write_data;
    wire          client_write_complete_error;

    assign client_write_request_valid[2]            = cq_dma_write_request_valid;
    assign cq_dma_write_request_ready               = client_write_request_ready[2];
    assign client_write_request_address[2*64 +: 64] = cq_dma_write_request_address;
    assign client_write_request_page1[2*64 +: 64]   = cq_dma_write_request_page1;
    assign client_write_request_length[2*13 +: 13]  = cq_dma_write_request_length;
    assign client_write_valid[2]                    = cq_dma_write_valid;
    assign cq_dma_write_ready                       = client_write_ready[2];
    assign client_write_data[2*1024 +: 1024]        = cq_dma_write_data;

    wire          dn_read_request_valid, dn_read_request_ready, dn_read_valid, dn_read_ready;
    wire          dn_read_last, dn_read_error;
    wire [63:0]   dn_read_request_address, dn_read_request_page1;
    wire [127:0]  dn_read_keep;
    wire [12:0]   dn_read_request_length, dn_write_request_length;
    wire [3:0]    dn_read_request_tag, dn_read_tag;
    wire [1023:0] dn_read_data, dn_write_data;
    wire          dn_write_request_valid, dn_write_request_ready;
    wire          dn_write_valid, dn_write_ready, dn_write_complete, dn_write_complete_error;
    wire [63:0]   dn_write_request_address, dn_write_request_page1;
    // u_arb 一侧（经 skid 再到 u_dma 的 dn_*）
    wire          arb_read_request_valid, arb_read_request_ready, arb_read_valid, arb_read_ready;
    wire          arb_read_last, arb_read_error;
    wire [63:0]   arb_read_request_address, arb_read_request_page1;
    wire [127:0]  arb_read_keep;
    wire [12:0]   arb_read_request_length, arb_write_request_length;
    wire [3:0]    arb_read_request_tag, arb_read_tag;
    wire [1023:0] arb_read_data, arb_write_data;
    wire          arb_write_request_valid, arb_write_request_ready, arb_write_valid, arb_write_ready;
    wire [63:0]   arb_write_request_address, arb_write_request_page1;

    roce_dma_arb #(.READ_CLIENTS(4), .WRITE_CLIENTS(4)) u_arb (
        .clk(core_clk), .rst(rst_arb),
        .dma_read_request_valid(client_read_request_valid),
        .dma_read_request_ready(client_read_request_ready),
        .dma_read_request_address(client_read_request_address),
        .dma_read_request_page1(client_read_request_page1),
        .dma_read_request_length(client_read_request_length),
        .dma_read_valid(client_read_valid), .dma_read_ready(client_read_ready),
        .dma_read_data(client_read_data), .dma_read_keep(client_read_keep),
        .dma_read_last(client_read_last), .dma_read_error(client_read_error),
        .dma_write_request_valid(client_write_request_valid),
        .dma_write_request_ready(client_write_request_ready),
        .dma_write_request_address(client_write_request_address),
        .dma_write_request_page1(client_write_request_page1),
        .dma_write_request_length(client_write_request_length),
        .dma_write_valid(client_write_valid), .dma_write_ready(client_write_ready),
        .dma_write_data(client_write_data), .dma_write_complete(client_write_complete),
        .dma_write_complete_error(client_write_complete_error),
        .downstream_read_request_valid(arb_read_request_valid),
        .downstream_read_request_ready(arb_read_request_ready),
        .downstream_read_request_address(arb_read_request_address),
        .downstream_read_request_page1(arb_read_request_page1),
        .downstream_read_request_length(arb_read_request_length),
        .downstream_read_request_tag(arb_read_request_tag),
        .downstream_read_valid(arb_read_valid), .downstream_read_ready(arb_read_ready),
        .downstream_read_data(arb_read_data), .downstream_read_keep(arb_read_keep),
        .downstream_read_last(arb_read_last), .downstream_read_tag(arb_read_tag),
        .downstream_read_error(arb_read_error),
        .downstream_write_request_valid(arb_write_request_valid),
        .downstream_write_request_ready(arb_write_request_ready),
        .downstream_write_request_address(arb_write_request_address),
        .downstream_write_request_page1(arb_write_request_page1),
        .downstream_write_request_length(arb_write_request_length),
        .downstream_write_valid(arb_write_valid), .downstream_write_ready(arb_write_ready),
        .downstream_write_data(arb_write_data),
        .downstream_write_complete(dn_write_complete),
        .downstream_write_complete_error(dn_write_complete_error)
    );

    // ------------------------------------------------------------ u_arb ↔ u_dma 之间的四个 skid（B6417，250 MHz）
    //
    // B6416 最大的一族违例（REQ_DMA 7292 + ANY_RFIFO 4343 + CQ_ANY 4626 + REQ_OTHER 大部分，有重叠）
    // 是同一个跨模块握手环：任一客户端的状态寄存器 → 它的 dma_write_valid → u_arb 写 owner 选路
    // → u_wr_align（take_input 依赖 write_data_in_valid）→ write_ready → dma_test 的
    // dma_read_ready = dma_write_ready（读写交叉耦合）→ u_arb 按 tag 选 read_ready
    // → u_rd_align.can_advance → u_r_fifo M20K 读使能（末段走线 1.43 ns）。
    // 写请求方向另有一条：客户端 request_valid → u_arb 选路 → u_dma 算是否跨页 → request_ready
    // → u_arb → 客户端（CQ_CQ 那组）。
    //
    // 在 u_arb 与 u_dma 之间四个方向各放一级全寄存器 skid，u_dma 的所有握手输入都只看寄存器：
    //   读请求  u_arb → u_dma     {tag, length, page1, address}              145 位
    //   写请求  u_arb → u_dma     {length, page1, address}                   141 位
    //   读数据  u_dma → u_arb     {error, tag, last, keep, data}            1158 位
    //   写数据  u_arb → u_dma     data                                      1024 位
    // 代价：每个方向多 1 拍固定延迟，吞吐不变（skid 两级，m_ready 恒 1 时每拍一个）。
    //
    // 顺序与死锁：读数据按序返回、skid 是 FIFO，tag 跟着走；写方向 u_arb 在一个请求的
    // 全部数据拍送完之前不放下一个请求（write_locked），而 u_dma 收请求只看 aw/bresp FIFO 与
    // wr_align 空闲，不看数据，所以「请求在 skid 里等、数据在另一个 skid 里等」不会互锁。
    // dma_write_complete 不经 skid（u_arb 按授权顺序记账，与请求 skid 同序）。
    roce_skid #(.WIDTH(4 + 13 + 64 + 64)) u_read_request_skid (
        .clk(core_clk), .rst(rst_glue),
        .s_valid(arb_read_request_valid), .s_ready(arb_read_request_ready),
        .s_data({arb_read_request_tag, arb_read_request_length, arb_read_request_page1, arb_read_request_address}),
        .m_valid(dn_read_request_valid), .m_ready(dn_read_request_ready),
        .m_data({dn_read_request_tag, dn_read_request_length, dn_read_request_page1, dn_read_request_address})
    );
    roce_skid #(.WIDTH(13 + 64 + 64)) u_write_request_skid (
        .clk(core_clk), .rst(rst_glue),
        .s_valid(arb_write_request_valid), .s_ready(arb_write_request_ready),
        .s_data({arb_write_request_length, arb_write_request_page1, arb_write_request_address}),
        .m_valid(dn_write_request_valid), .m_ready(dn_write_request_ready),
        .m_data({dn_write_request_length, dn_write_request_page1, dn_write_request_address})
    );
    roce_skid #(.WIDTH(1 + 4 + 1 + 128 + 1024)) u_read_data_skid (
        .clk(core_clk), .rst(rst_glue),
        .s_valid(dn_read_valid), .s_ready(dn_read_ready),
        .s_data({dn_read_error, dn_read_tag, dn_read_last, dn_read_keep, dn_read_data}),
        .m_valid(arb_read_valid), .m_ready(arb_read_ready),
        .m_data({arb_read_error, arb_read_tag, arb_read_last, arb_read_keep, arb_read_data})
    );
    wire          mid_write_valid, mid_write_ready;
    wire [1023:0] mid_write_data;
    roce_skid #(.WIDTH(1024)) u_write_data_skid (
        .clk(core_clk), .rst(rst_glue),
        .s_valid(arb_write_valid), .s_ready(arb_write_ready),
        .s_data(arb_write_data),
        .m_valid(mid_write_valid), .m_ready(mid_write_ready),
        .m_data(mid_write_data)
    );
    // 写数据第二级 skid（B6433）。B6432 STA：u_dma|u_w_fifo（满判断）→ u_wr_align 的组合 ready →
    // u_write_data_skid|skid_valid 走线占 87%、−0.204 ns（lane 0/2）。这个握手位一旦锁存错，写数据会
    // 多拍/漏拍，u_resp 的 SEND 游标随之错位——SEND 续包每包都按游标做完整翻译，越界报 access error；
    // WRITE 续包走页缓存，同样的错位只会静默写错数据。B6432 上 server send_bw ~50% 轮次 remote access
    // error（§56.7）。第二级放在 u_dma 一侧：组合 ready 只走短线，两级之间是寄存器到寄存器的长线。
    // 代价：写数据多 1 拍固定延迟，吞吐不变；u_dma 收请求不看数据（见上），不引入互锁。
    roce_skid #(.WIDTH(1024)) u_write_data_skid2 (
        .clk(core_clk), .rst(rst_glue),
        .s_valid(mid_write_valid), .s_ready(mid_write_ready),
        .s_data(mid_write_data),
        .m_valid(dn_write_valid), .m_ready(dn_write_ready),
        .m_data(dn_write_data)
    );

    roce_dma #(.TAG_W(4)) u_dma (
        .clk(core_clk), .rst(rst_dma), .pcie_clk(pcie_clk), .pcie_rst(dp_pcie_rst),
        .bas_m2s(virt_bas_m2s), .bas_s2m(virt_bas_s2m),
        .dma_read_request_valid(dn_read_request_valid),
        .dma_read_request_ready(dn_read_request_ready),
        .dma_read_request_address(dn_read_request_address),
        .dma_read_request_page1(dn_read_request_page1),
        .dma_read_request_length(dn_read_request_length),
        .dma_read_request_tag(dn_read_request_tag),
        .dma_read_valid(dn_read_valid), .dma_read_ready(dn_read_ready),
        .dma_read_data(dn_read_data), .dma_read_keep(dn_read_keep),
        .dma_read_last(dn_read_last), .dma_read_tag(dn_read_tag),
        .dma_read_error(dn_read_error),
        .dma_write_request_valid(dn_write_request_valid),
        .dma_write_request_ready(dn_write_request_ready),
        .dma_write_request_address(dn_write_request_address),
        .dma_write_request_page1(dn_write_request_page1),
        .dma_write_request_length(dn_write_request_length),
        .dma_write_valid(dn_write_valid), .dma_write_ready(dn_write_ready),
        .dma_write_data(dn_write_data), .dma_write_complete(dn_write_complete),
        .dma_write_complete_error(dn_write_complete_error),
        .debug_state(dma_debug_state)
    );

    // ------------------------------------------------------------ DMA 自测（客户端 3）
    // 250 MHz（B6411）：自测请求经一级 skid 再进仲裁器。
    // B6410 真实 250 MHz fit 里 u_dma_test 的 total_count/reads_issued（32 位计数器）
    // 直连仲裁器的优先级扫描、ready 再回送过来，形成跨模块组合环，占 17.5% 违例
    // （3,503 条，连同 fetch_req_qp 一共）。
    // 自测是上板诊断用的旁路，多一拍延迟没有功能影响；切断这条环后它不再参与关键路径。
    //
    // skid 语义：dma_test 的 request_valid 是「还有事要做」的电平（不是单拍脉冲），
    // 保持到 ready 握手为止，所以只要寄存后按握手推进即可，不需要深 FIFO。
    wire              sel_read_valid_pre, sel_read_ready_pre;
    wire [63:0]       sel_read_address_pre, sel_read_page1_pre;
    wire [12:0]       sel_read_length_pre;
    wire              sel_write_valid_pre, sel_write_ready_pre;
    wire [63:0]       sel_write_address_pre, sel_write_page1_pre;
    wire [12:0]       sel_write_length_pre;

    roce_dma_test u_dma_test (
        .clk(core_clk), .rst(rst_test),
        .source_address(dma_test_source), .destination_address(dma_test_destination),
        .transfer_length(dma_test_length), .repeat_count(dma_test_repeat),
        .start(dma_test_start), .busy(dma_test_busy), .done(dma_test_done),
        .error(dma_test_error), .cycle_count(dma_test_cycles),
        .dma_read_request_valid(sel_read_valid_pre),
        .dma_read_request_ready(sel_read_ready_pre),
        .dma_read_request_address(sel_read_address_pre),
        .dma_read_request_page1(sel_read_page1_pre),
        .dma_read_request_length(sel_read_length_pre),
        .dma_read_valid(client_read_valid[3]), .dma_read_ready(client_read_ready[3]),
        .dma_read_data(client_read_data), .dma_read_error(client_read_error),
        .dma_write_request_valid(sel_write_valid_pre),
        .dma_write_request_ready(sel_write_ready_pre),
        .dma_write_request_address(sel_write_address_pre),
        .dma_write_request_page1(sel_write_page1_pre),
        .dma_write_request_length(sel_write_length_pre),
        .dma_write_valid(client_write_valid[3]), .dma_write_ready(client_write_ready[3]),
        .dma_write_data(client_write_data[3*1024 +: 1024]),
        .dma_write_complete(client_write_complete[3]),
        .dma_write_complete_error(client_write_complete_error)
    );

    // 读/写各一个 1 深度 skid：valid/地址/长度都寄存，ready 只依赖寄存器
    reg               sel_rd_v, sel_wr_v;
    reg  [63:0]       sel_rd_addr, sel_rd_page1, sel_wr_addr, sel_wr_page1;
    reg  [12:0]       sel_rd_len, sel_wr_len;
    always @(posedge core_clk) begin
        if (rst_glue) begin
            sel_rd_v <= 1'b0;
            sel_wr_v <= 1'b0;
        end else begin
            // 装：pre 有请求且（skid 空或本拍被取走）
            if (sel_read_valid_pre && (!sel_rd_v || sel_read_ready_pre)) begin
                sel_rd_v     <= 1'b1;
                sel_rd_addr  <= sel_read_address_pre;
                sel_rd_page1 <= sel_read_page1_pre;
                sel_rd_len   <= sel_read_length_pre;
            end else if (sel_read_ready_pre) begin
                sel_rd_v <= 1'b0;
            end
            if (sel_write_valid_pre && (!sel_wr_v || sel_write_ready_pre)) begin
                sel_wr_v     <= 1'b1;
                sel_wr_addr  <= sel_write_address_pre;
                sel_wr_page1 <= sel_write_page1_pre;
                sel_wr_len   <= sel_write_length_pre;
            end else if (sel_write_ready_pre) begin
                sel_wr_v <= 1'b0;
            end
        end
    end
    // dma_test 的 ready 来自 skid 的装载条件（只依赖寄存器），不再组合回计数器比较
    assign sel_read_ready_pre  = !sel_rd_v || client_read_request_ready[3];
    assign sel_write_ready_pre = !sel_wr_v || client_write_request_ready[3];

    assign client_read_request_valid[3]            = sel_rd_v;
    assign client_read_request_address[3*64 +: 64] = sel_rd_addr;
    assign client_read_request_page1[3*64 +: 64]   = sel_rd_page1;
    assign client_read_request_length[3*13 +: 13]  = sel_rd_len;
    assign client_write_request_valid[3]            = sel_wr_v;
    assign client_write_request_address[3*64 +: 64] = sel_wr_addr;
    assign client_write_request_page1[3*64 +: 64]   = sel_wr_page1;
    assign client_write_request_length[3*13 +: 13]  = sel_wr_len;

    // ------------------------------------------------------------ RX：disp → resp | req
    wire [1:0] route_header_valid, route_header_ready, route_payload_valid, route_payload_ready, route_done;

    roce_rx_disp u_disp (
        .clk(core_clk), .rst(rst_disp),
        .rx_header_valid(rx_header_valid), .rx_header_ready(rx_header_ready),
        .rx_header(rx_header),
        .rx_payload_valid(rx_payload_valid), .rx_payload_ready(rx_payload_ready),
        .route_header_valid(route_header_valid), .route_header_ready(route_header_ready),
        .route_payload_valid(route_payload_valid), .route_payload_ready(route_payload_ready),
        .route_done(route_done), .event_rx_packet(event_rx_packet),
        .debug_busy_owner(debug_disp_busy_owner)
    );

    // ------------------------------------------------------------ 响应方
    wire     responder_job_valid, responder_job_ready;
    tx_job_t responder_job;

    roce_resp u_resp (
        .clk(core_clk), .rst(rst_resp), .qpc(qpc), .qp_state_i(qp_state_flat),
        .qp_state_change(qp_state_change), .qp_set_error(qp_set_error_responder),
        .doorbell_rq_valid(lane_doorbell_rq), .doorbell_data(doorbell_data),
        .table_request(table_request), .table_write_enable(table_write_enable),
        .table_select(table_select),
        .rx_header_valid(route_header_valid[0]), .rx_header_ready(route_header_ready[0]),
        .rx_header(rx_header),
        .rx_payload_valid(route_payload_valid[0]), .rx_payload_ready(route_payload_ready[0]),
        .rx_payload_data(rx_payload_data), .rx_payload_last(rx_payload_last),
        .done(route_done[0]),
        .translate_valid(translate_valid[2:1]), .translate_ready(translate_ready[2:1]),
        .translate_key(translate_key[95:32]),
        .translate_virtual_address(translate_virtual_address[191:64]),
        .translate_length(translate_length[38:13]),
        .translate_access(translate_access[11:4]),
        .translate_protection_domain(translate_protection_domain[47:16]),
        .translate_response(translate_response[2:1]),
        .translate_physical_address0(translate_physical_address0),
        .translate_physical_page1(translate_physical_page1),
        .translate_error(translate_error),
        .dma_read_request_valid(client_read_request_valid[1]),
        .dma_read_request_ready(client_read_request_ready[1]),
        .dma_read_request_address(client_read_request_address[1*64 +: 64]),
        .dma_read_request_page1(client_read_request_page1[1*64 +: 64]),
        .dma_read_request_length(client_read_request_length[1*13 +: 13]),
        .dma_read_valid(client_read_valid[1]), .dma_read_ready(client_read_ready[1]),
        .dma_read_data(client_read_data),
        .dma_write_request_valid(client_write_request_valid[0]),
        .dma_write_request_ready(client_write_request_ready[0]),
        .dma_write_request_address(client_write_request_address[0*64 +: 64]),
        .dma_write_request_page1(client_write_request_page1[0*64 +: 64]),
        .dma_write_request_length(client_write_request_length[0*13 +: 13]),
        .dma_write_valid(client_write_valid[0]), .dma_write_ready(client_write_ready[0]),
        .dma_write_data(client_write_data[0*1024 +: 1024]),
        .cqe_valid(resp_cqe_valid), .cqe_ready(resp_cqe_ready),
        .cqe_cq_index(resp_cqe_cq), .cqe_data(resp_cqe_data),
        .tx_job_valid(responder_job_valid), .tx_job_ready(responder_job_ready),
        .tx_job(responder_job),
        .event_duplicate(event_duplicate), .event_sequence_error(event_sequence_error),
        .event_tx_ack(event_tx_ack), .event_tx_nak(event_tx_nak),
        .event_rnr_nak(event_rnr_nak), .event_access_error(event_access_error),
        .dbg_access_snapshot(dbg_access_snapshot), .dbg_access_snapshot_clr(dbg_access_snapshot_clr),
        .event_drop(event_bad),
        .event_page_hit(event_page_hit), .event_page_miss(event_page_miss),
        .debug_state(resp_debug_state)
    );

    // ------------------------------------------------------------ 请求方
    wire        requester_job_valid, requester_job_ready;
    tx_job_t    requester_job;
    wire [31:0] requester_translate_key;
    wire [63:0] requester_translate_address;
    wire [12:0] requester_translate_length;
    wire [3:0]  requester_translate_access;
    assign translate_key[31:0]             = requester_translate_key;
    assign translate_virtual_address[63:0] = requester_translate_address;
    assign translate_length[12:0]          = requester_translate_length;
    assign translate_access[3:0]           = requester_translate_access;

    // ------------------------------------------------------------ RX header 到 u_req 的一级 skid（250 MHz）
    //
    // B6410 真实 250 MHz fit 里 62.4% 的违例是同一个环：u_req 的 state 寄存器
    //   → u_req.rx_header_ready → u_rx_disp.rx_header_ready
    //   → u_rx_parse.in_ready → demux 每 lane FIFO 的 m_axis_tready
    // 三级模块之间没有寄存器，4 ns 内要走完 M20K 输出 + 译码 + 4 选 1 + 状态判断。
    //
    // 这里放一级**透传（fall-through）** skid：空的时候当拍就把头送到 u_req
    // （valid / data 直接旁路），u_req 忙的时候才寄存进 req_header_r。
    // 透传是必须的——如果一律寄存，header 通道就变成两拍一个头，RX 每包白丢一拍。
    //
    // 断开的点：
    //   * 环上原来的 disp 4 选 1 与 parse 的 header_ok 从 ready 往回链上消失，
    //     route_header_ready[1] 只剩「skid 空 || 被取走」两级；
    //   * valid/数据方向 u_req 的译码不再串在 demux FIFO 的读地址上，
    //     装进 req_header_r 之后 FIFO 读地址只受「寄存器 + u_req ready」驱动。
    // 代价：u_req 忙时多 1 拍延迟；payload 通道不动（disp 的 owner 机制保证 payload
    // 首拍在 header 被取走之后才放行）。
    wire          req_header_valid, req_header_ready;
    rx_hdr_t      req_header;
    reg           req_header_v;
    rx_hdr_t      req_header_r;
    wire          req_header_bypass = !req_header_v;                 // skid 空：当拍直通
    assign req_header_valid = req_header_v || route_header_valid[1];
    assign req_header       = req_header_v ? req_header_r : rx_header;
    // 上游 ready：skid 空 → 本拍的头被 u_req 取走即算取走（不透传就丢头）；
    //            skid 满 → 本拍的头先存不进去，要等 u_req 取走寄存的那个（skid 变空）。
    assign route_header_ready[1] = req_header_v ? req_header_ready : 1'b1;

    always @(posedge core_clk) begin
        if (rst_glue) begin
            req_header_v <= 1'b0;
        end else if (req_header_valid && req_header_ready) begin
            // 本拍有一个头被 u_req 取走。空 skid 透传的情况本拍不存新头（上游看到的
            // ready 已经是 1，它的下一个头在下一拍才来）；满 skid 的情况上游 ready 也是 1，
            // 本拍的头正等着被发现，所以要接住。
            req_header_v <= req_header_bypass ? 1'b0 : route_header_valid[1];
            if (!req_header_bypass && route_header_valid[1]) req_header_r <= rx_header;
        end else if (route_header_valid[1] && !req_header_v) begin
            // u_req 没取走、上游有头：存起来
            req_header_v <= 1'b1;
            req_header_r <= rx_header;
        end
    end

    roce_req #(.CORE_CLOCK_MHZ(CORE_CLOCK_MHZ)) u_req (
        .clk(core_clk), .rst(rst_req), .qpc(qpc), .qp_state_i(qp_state_flat),
        .qp_state_change(qp_state_change), .qp_set_error(qp_set_error_requester),
        .doorbell_sq_valid(lane_doorbell_sq), .doorbell_data(doorbell_data),
        .rx_pfc(rx_pfc), .pfc_gate_enable(pfc_gate_enable),
        .tx_rate_ready(tx_rate_ready),
        .rx_header_valid(req_header_valid), .rx_header_ready(req_header_ready),
        .rx_header(req_header),
        .rx_payload_valid(route_payload_valid[1]), .rx_payload_ready(route_payload_ready[1]),
        .rx_payload_data(rx_payload_data), .rx_payload_last(rx_payload_last),
        .done(route_done[1]),
        .translate_valid(translate_valid[0]), .translate_ready(translate_ready[0]),
        .translate_key(requester_translate_key),
        .translate_virtual_address(requester_translate_address),
        .translate_length(requester_translate_length),
        .translate_access(requester_translate_access),
        .translate_protection_domain(translate_protection_domain[15:0]),
        .translate_response(translate_response[0]),
        .translate_physical_address0(translate_physical_address0),
        .translate_physical_page1(translate_physical_page1),
        .translate_error(translate_error),
        .dma_read_request_valid(client_read_request_valid[0]),
        .dma_read_request_ready(client_read_request_ready[0]),
        .dma_read_request_address(client_read_request_address[0*64 +: 64]),
        .dma_read_request_page1(client_read_request_page1[0*64 +: 64]),
        .dma_read_request_length(client_read_request_length[0*13 +: 13]),
        .dma_read_valid(client_read_valid[0]), .dma_read_ready(client_read_ready[0]),
        .dma_read_data(client_read_data),
        .dma_write_request_valid(client_write_request_valid[1]),
        .dma_write_request_ready(client_write_request_ready[1]),
        .dma_write_request_address(client_write_request_address[1*64 +: 64]),
        .dma_write_request_page1(client_write_request_page1[1*64 +: 64]),
        .dma_write_request_length(client_write_request_length[1*13 +: 13]),
        .dma_write_valid(client_write_valid[1]), .dma_write_ready(client_write_ready[1]),
        .dma_write_data(client_write_data[1*1024 +: 1024]),
        .cqe_valid(req_cqe_valid), .cqe_ready(req_cqe_ready),
        .cqe_cq_index(req_cqe_cq), .cqe_data(req_cqe_data),
        .tx_job_valid(requester_job_valid), .tx_job_ready(requester_job_ready),
        .tx_job(requester_job),
        .event_rx_ack(event_rx_ack), .event_rx_nak(event_rx_nak),
        .event_rx_rnr(event_rx_rnr),
        .event_retransmit_timeout(event_retransmit_timeout),
        .event_retransmit_nak(event_retransmit_nak),
        .event_rx_cnp(event_cnp_handled_lane),
        .event_rx_cnp_qp(event_rx_cnp_qp_lane),
        .debug_state(req_debug_state)
    );

    wire event_cnp_handled_lane;
    wire [QP_NUM-1:0] event_rx_cnp_qp_lane;
    assign event_cnp_handled  = event_cnp_handled_lane;
    assign event_rx_cnp_qp    = event_rx_cnp_qp_lane;
    assign event_cnp_ignored = 1'b0;      // roce_req 目前把「QP 非法 / 非 RTS」的 CNP 直接 DRAIN，
                                          // 与其它坏包一样不计；要分开统计需要在 u_req 里再加一个脉冲。

    // ------------------------------------------------------------ ECN / CNP 生成（NP 侧）
    // 触发：头部在 disp 输入处握手成功、opcode 是请求类（WRITE*/SEND*/READ_REQ）、
    //       header.ecn_congestion（IPv4 TOS[1:0]==2'b11，由 roce_rx_parse 解出）、QP 合法。
    //   ACK / READ RESP 不触发：它们不是网络拥塞的对象，给它们回 CNP 会打环。
    //   header.bad 的包也不触发（长度/opcode 不合法，不值得为它花一个 CNP 配额）。
    // 挂起语义：只记「有一个 CE 包要回」，不排队——同一窗口内来 100 个 CE 包也只发一个 CNP，
    //   这正是 NP 限频想要的行为（np_ecn_marked 里能看到真实的 CE 包数）。
    // 发出去的那一刻：cnp_grant（roce_cnp 的端口级限频 + 轮询仲裁）到、且没有响应方任务在
    //   roce_tx 槽 0 里没走完（这里让 CNP 优先，见下面的槽 0 覆盖）。
    wire rx_header_take = rx_header_valid && rx_header_ready;
    wire cnp_qualified  = rx_header_take && !rx_header.bad && rx_header.qp_valid &&
                          (rx_header.opcode <= OP_READ_REQ) && rx_header.ecn_congestion;
    reg        cnp_pending;
    reg  [3:0] cnp_qp;
    // 发出（被 roce_tx 取走）的那一拍清挂起位。cnp_grant 是 roce_cnp 的寄存器输出，
    // 与它同拍的 cnp_job_valid 一定能被 roce_tx 看到（槽 0 的 issue_take 只看在途 FIFO
    // 有没有空位），所以不需要额外的 skid。ready 就是 roce_tx 槽 0 的 ready。
    // grant 是 roce_cnp 的单拍脉冲；若这一拍 roce_tx 的轮询正好选了槽 1（请求方），
    // CNP 就发不出去。锁存一个 pending_grant，直到真的被槽 0 取走为止——
    // 否则每次撞车都要白等一个 min_time_between_cnps 窗口。
    reg  cnp_grant_q;
    wire cnp_job_valid = cnp_pending && (cnp_grant || cnp_grant_q);
    // roce_tx 槽 0 的 ready（槽 0 由 CNP 与响应方共用）。B6432 曾把它原样回给 u_resp：CNP 占槽那一拍
    // 若响应方也有待发任务（ACK / NAK / READ RESP），u_resp 看到 ready=1 以为被取走 → 任务被静默丢掉。
    // 现在 u_resp 只在槽 0 真的装的是它的任务时才看到 ready（见下方 responder_job_ready）。
    wire slot0_ready;
    wire cnp_sent      = cnp_job_valid && slot0_ready;
    always @(posedge core_clk) begin
        // B6434：NP_EN 关掉时把「已锁存的 grant」和「挂起位」一起清。只清 grant 不够——
        // 挂起位会立刻被下一个 CE 包重新拉起，然后发现 grant_q 干净、等新的 grant；
        // 只清挂起位也不够——cnp_grant_q 会一直留着，下一包直接发出去。
        if (rst_glue || !cnp_en || !cnp_np_en || cnp_sent) cnp_grant_q <= 1'b0;
        else if (cnp_grant)                                cnp_grant_q <= 1'b1;
    end
    always @(posedge core_clk) begin
        if (rst_glue || !cnp_en || !cnp_np_en) begin
            cnp_pending <= 1'b0;
        end else if (cnp_sent) begin
            cnp_pending <= 1'b0;
        end else if (cnp_qualified) begin
            cnp_pending <= 1'b1;
            cnp_qp      <= rx_header.qp_index;
        end
    end
    assign event_cnp_sent = cnp_sent;

    assign cnp_request      = cnp_pending;
    assign event_ecn_marked = cnp_qualified;          // 每个 CE 数据包一次（含被限频压掉的）

    // CNP 任务：与响应方共用 roce_tx 的槽 0（CNP 优先，最多占掉 ACK 一个包的时间）
    tx_job_t cnp_job;
    assign cnp_job = '{
        qp_index: cnp_qp,
        opcode: OP_CNP,
        psn: 24'd0,
        ack_request: 1'b0,
        solicited: 1'b0,
        reth_virtual_address: 64'd0,
        reth_rkey: 32'd0,
        reth_length: 32'd0,
        aeth_syndrome: 8'd0,
        aeth_msn: 24'd0,
        immediate: 32'd0,
        payload_length: 13'd0,
        physical_address0: 64'd0,
        physical_page1: 64'd0,
        tos: cnp_tos,
        tos_valid: 1'b1
    };

    // ------------------------------------------------------------ TX
    tx_job_t tx_jobs [2];
    // 槽 0 给 CNP 让路：CNP 只在 grant 那一拍出现，响应方任务本来也只在 ready 时才会走。
    wire     slot0_cnp   = cnp_job_valid;
    wire     slot0_resp  = responder_job_valid_gated && !slot0_cnp;
    assign   responder_job_ready = slot0_ready && !slot0_cnp;
    assign tx_jobs[0] = slot0_cnp ? cnp_job : responder_job;
    assign tx_jobs[1] = requester_job;

    // PFC 响应方准入（2026-11-09）：ACK / NAK / READ RESP 与请求包同一个 QP、同一个 TOS，
    // 对端暂停该优先级时也不能发（mlx5 同样按 QP 的 traffic class 发 ACK）。
    // roce_resp 的 tx_job 是寄存器，valid 期间字段保持不变，所以在这里挡 valid 即可；
    // roce_tx 的 tx_job_ready 只在看到 valid 时才拉高，ready 不用另外处理。
    // 每 QP 的 blocked 位先寄存（与 roce_req.tx_pfc_blocked_q 同口径），选路只剩 16:1 选 1 位。
    // 代价：同一 lane 的 response FIFO 被挡住时，排在后面的其他 QP 的回包也要等（HOL）；
    // response FIFO 满后 roce_resp 主状态机停收 RX，staging 涨到 XOFF 阈值时本端会向对端发 PFC
    // —— 这正是 PFC 逐跳反压的语义。
    reg  [QP_NUM-1:0] resp_pfc_blocked_q;
    always @(posedge core_clk) begin
        if (rst_glue) resp_pfc_blocked_q <= '0;
        else
            for (int qp = 0; qp < QP_NUM; qp++)
                resp_pfc_blocked_q[qp] <= pfc_gate_enable && resp_gate &&
                                          (rx_pfc[8] || rx_pfc[qpc[qp*512 + 7*32+16+5 +: 3]]);
    end
    wire responder_job_blocked     = resp_pfc_blocked_q[responder_job.qp_index];
    wire responder_job_valid_gated = responder_job_valid && !responder_job_blocked;

    wire          tx_frame_valid, tx_frame_ready, tx_frame_last;
    wire [1023:0] tx_frame_data;
    wire [127:0]  tx_frame_keep;
    wire [6:0]    tx_frame_last_bytes, tx_frame_last_beat_bytes;

    roce_tx u_tx (
        .clk(core_clk), .rst(rst_tx), .local_mac(local_mac), .local_ip(local_ip), .qpc(qpc),
        .tx_job_valid({requester_job_valid, slot0_resp | slot0_cnp}),
        .tx_job_ready({requester_job_ready, slot0_ready}),
        .tx_job(tx_jobs),
        .dma_read_request_valid(client_read_request_valid[2]),
        .dma_read_request_ready(client_read_request_ready[2]),
        .dma_read_request_address(client_read_request_address[2*64 +: 64]),
        .dma_read_request_page1(client_read_request_page1[2*64 +: 64]),
        .dma_read_request_length(client_read_request_length[2*13 +: 13]),
        .dma_read_valid(client_read_valid[2]), .dma_read_ready(client_read_ready[2]),
        .dma_read_data(client_read_data), .dma_read_keep(client_read_keep),
        .dma_read_last(client_read_last),
        .frame_valid(tx_frame_valid), .frame_ready(tx_frame_ready),
        .frame_data(tx_frame_data), .frame_keep(tx_frame_keep), .frame_last(tx_frame_last),
        .frame_last_bytes(tx_frame_last_bytes),
        .frame_last_beat_bytes(tx_frame_last_beat_bytes),
        .cnp_bth_flags({cnp_fecn, cnp_becn}),
        .event_tx_packet(event_tx_packet),
        .event_tx_admit(lane_tx_admit),
        .event_tx_admit_qp(lane_tx_admit_qp_idx),
        .event_tx_admit_length(lane_tx_admit_len),
        .debug_state(tx_debug_state)
    );

    // 准入事件：roce_tx 给的是「索引 + 长度」，这里转成 one-hot 送给 roce_top
    wire                lane_tx_admit;
    wire [3:0]          lane_tx_admit_qp_idx;
    // (lane_tx_admit_qp_idx 只给 one-hot 转换用)
    wire [12:0]         lane_tx_admit_len;
    wire [QP_NUM-1:0]   lane_tx_admit_qp_vec = lane_tx_admit ? (QP_NUM'(1) << lane_tx_admit_qp_idx) : '0;
    assign event_tx_admit_qp     = lane_tx_admit_qp_vec;
    assign event_tx_admit_length = lane_tx_admit_len;

    wire          egress_valid, egress_ready, egress_last;
    wire [DATA_W-1:0]  egress_data;
    wire [USERF_W-1:0] egress_last_bytes;
    roce_tx_out u_tx_out (
        .clk(core_clk), .rst(rst_tx_out), .mac_clk(mac_clk), .mac_rst(dp_mac_rst),
        .frame_valid(tx_frame_valid), .frame_ready(tx_frame_ready),
        .frame_data(tx_frame_data), .frame_keep(tx_frame_keep), .frame_last(tx_frame_last),
        .frame_last_bytes(tx_frame_last_bytes),
        .frame_last_beat_bytes(tx_frame_last_beat_bytes),
        .mac_valid(egress_valid), .mac_ready(egress_ready),
        .mac_data(egress_data), .mac_last_bytes(egress_last_bytes), .mac_last(egress_last)
    );

    // PFC 出口门控（mac 域）：pause 生效后本 lane 至多再发完当前帧，见 roce_pfc_egress.sv。
    // pfc_gate_enable 是 core 域准静态位，跨到 mac 域只用作使能，两级寄存足够。
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    reg [1:0] gate_dis_mac_sync;
    always @(posedge mac_clk) gate_dis_mac_sync <= {gate_dis_mac_sync[0], pfc_gate_enable};
    roce_pfc_egress #(.DATA_W(DATA_W), .USERF_W(USERF_W)) u_pfc_egress (
        .clk(mac_clk), .rst(dp_mac_rst),
        .gate_enable(egress_gate && gate_dis_mac_sync[1]),
        .pause(pause_mac),
        .s_valid(egress_valid), .s_ready(egress_ready), .s_data(egress_data),
        .s_last_bytes(egress_last_bytes), .s_last(egress_last),
        .m_valid(tx_valid), .m_ready(tx_ready), .m_data(tx_data),
        .m_last_bytes(tx_last_bytes), .m_last(tx_last),
        .hold(egress_hold)
    );
endmodule
`default_nettype wire
