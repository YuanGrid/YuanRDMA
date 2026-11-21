// roce_pfc_egress.sv
// 每条 RoCE lane 的 TX 出口 PFC 门控（mac_clk 域），位于 roce_tx_out（帧 FIFO 输出）与 TX 汇合之间。
//
// 为什么要在出口挡（只在派发处挡不够）
//   802.3bs 规定 400G 收到 PFC/PAUSE 后必须在 905 pause_quanta（≈ 1.16 µs，线上 ≈ 58 KB）内停发。
//   roce_req 的派发门控只挡新 WQE；已经进流水的包——每 lane roce_tx 在途 16 个 job、roce_tx_out
//   的 staging/帧 FIFO——4 lane 合计可能有 200 KB 以上，全放出去会撑爆交换机 headroom、造成丢包。
//   这里在**帧边界**按帧头 TOS[7:5] 挡：pause 生效后本 lane 至多再发完正在发的那一帧。
//
// 语义
//   - 只在 SOP 判定，包内不打断（下游 roce_tx_mux 要求包内无气泡）。
//   - blocked = gate && (pause[8] || pause[TOS[7:5]])；帧头不是 IPv4（不会发生，引擎只发 RoCEv2）时按 prio 0 处理。
//   - 被挡时 s_ready=0（帧留在 FIFO 里），m_valid 不拉高；pause 释放后原样发出，不丢不改。
//   - 代价：同一 lane 里排在被挡帧后面的其他优先级帧也要等（HOL）。派发门控已把新包挡在源头，
//     被困住的只有 pause 前已在流水里的那部分；要彻底消除需要每 lane 按优先级分队列（v2）。
//
// 时序（415 MHz）：输出走 roce_skid，m_valid/m_data 是寄存器；s_ready 是 skid 的寄存器输出与
//   hold 的与。hold = SOP && valid && blocked，其中 blocked 只依赖 s_data 的 3 位与寄存后的 pause，
//   一级 8:1 选择 + 与门。
`default_nettype none
`timescale 1ns/1ps
module roce_pfc_egress #(
    parameter int DATA_W  = 1024,
    parameter int USERF_W = 7
)(
    input  wire                 clk,          // mac_clk
    input  wire                 rst,
    input  wire                 gate_enable,  // CTRL.EGRESS_GATE（已在 mac 域）
    input  wire  [8:0]          pause,        // 收方向生效 pause（mac 域）：[8]=802.3x
    input  wire                 s_valid,
    output wire                 s_ready,
    input  wire  [DATA_W-1:0]   s_data,
    input  wire  [USERF_W-1:0]  s_last_bytes,
    input  wire                 s_last,
    output wire                 m_valid,
    input  wire                 m_ready,
    output wire  [DATA_W-1:0]   m_data,
    output wire  [USERF_W-1:0]  m_last_bytes,
    output wire                 m_last,
    output wire                 hold          // 观测：本拍有帧被挡在出口
);
    reg  [8:0] pause_q;
    reg        gate_q;
    always @(posedge clk) begin
        pause_q <= pause;
        gate_q  <= gate_enable;
    end

    reg  in_packet;                                     // 已放行当前帧的首拍
    wire [2:0] head_prio = s_data[15*8 + 5 +: 3];       // IPv4 TOS[7:5]（以太网头 14 B 后第 2 字节）
    // CNP 旁路（B6435）：CNP 是拥塞的**解除**信号，被出口门控挡住就成死锁——
    // 对端在 CNP 自己的优先级（默认 DSCP 48 → prio6）上按住 PFC 或 802.3x 时，
    // 本端 CNP 永远出不去，对端收不到降速信号、PFC 也不会撤，正反馈锁死。
    // 判据：IPv4（EtherType 0x0800）+ UDP（proto 17）+ BTH opcode 0x81，三段都在首拍内。
    wire is_ipv4   = (s_data[12*8 +: 16] == 16'h0008);
    wire is_udp    = (s_data[23*8 +: 8]  == 8'h11);
    wire is_cnp    = (s_data[42*8 +: 8]  == 8'h81);   // BTH opcode CNP（roce_pkg::OP_CNP）
    wire cnp_bypass = is_ipv4 && is_udp && is_cnp;
    wire blocked  = gate_q && !cnp_bypass && (pause_q[8] || pause_q[head_prio]);
    assign hold   = s_valid && !in_packet && blocked;

    wire skid_ready;
    assign s_ready = skid_ready && !hold;
    wire take = s_valid && s_ready;
    always @(posedge clk) begin
        if (rst)       in_packet <= 1'b0;
        else if (take) in_packet <= !s_last;
    end

    roce_skid #(.WIDTH(DATA_W + USERF_W + 1)) u_skid (
        .clk(clk), .rst(rst),
        .s_valid(s_valid && !hold), .s_ready(skid_ready),
        .s_data({s_last, s_last_bytes, s_data}),
        .m_valid(m_valid), .m_ready(m_ready),
        .m_data({m_last, m_last_bytes, m_data})
    );
endmodule
`default_nettype wire
