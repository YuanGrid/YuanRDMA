// roce_rx_qpn_split.sv
// Phase 1 RX 分流（core_clk 域）：roce_rx_parse 的一条头/payload 流 → LANES 个 roce_engine。
//
// 归属：lane = qp_index[LANE_W-1:0]（QP 号按奇偶交错绑定 lane，见 roce-400g-scaling-plan §5）。
//       qp_valid=0 的包（QPN 不在本端范围）一律交给 lane 0，由它的 resp 计 RX_BAD_QP。
// 头：  广播数据、只对目标 lane 拉 valid；目标 lane 的 disp 忙时自然反压（其 header_ready=0）。
// payload：有 payload 的包（判据与 roce_rx_parse 完全一致：!bad && payload_length != 0）
//       接受头后锁定 owner，payload 只放给 owner，直到 last 握手才放下一个头。
//       于是 payload 总线上永远只有一个包在流，次序与头一致，不需要 owner FIFO。
// 并行度从哪里来：放下一个头的条件是「上一包 payload 收完」，而不是「上一包 done」。
//       lane X 做包尾（FINISH/ACK/写回）的同时，lane Y 已经可以收头、分类、翻译。
//       同一 lane 的下一包仍要等它的 disp 空闲（由 lane 自己的 header_ready 保证）。
`default_nettype none
`timescale 1ns/1ps
module roce_rx_qpn_split
    import roce_pkg::*;
#(
    parameter int LANES = 2
)(
    input  wire                 clk,
    input  wire                 rst,
    // 来自 roce_rx_parse
    input  wire                 in_header_valid,
    output wire                 in_header_ready,
    input  rx_hdr_t             in_header,
    input  wire                 in_payload_valid,
    output wire                 in_payload_ready,
    input  wire                 in_payload_last,
    // 到各 lane（头数据、payload 数据在 roce_top 里直接广播）
    output wire [LANES-1:0]     lane_header_valid,
    input  wire [LANES-1:0]     lane_header_ready,
    output wire [LANES-1:0]     lane_payload_valid,
    input  wire [LANES-1:0]     lane_payload_ready,
    // 调试：{payload_busy, payload_owner}，见 roce_debug 的 RX_SPLIT_STATE
    output wire [LANE_W:0]      debug_state
);
    localparam int LANE_W = (LANES <= 2) ? 1 : (LANES <= 4) ? 2 : 3;

    wire [LANE_W-1:0] dest        = in_header.qp_valid ? in_header.qp_index[LANE_W-1:0] : '0;
    wire              has_payload = !in_header.bad && (in_header.payload_length != 13'd0);

    reg               payload_busy;
    reg  [LANE_W-1:0] payload_owner;

    assign lane_header_valid = (!payload_busy && in_header_valid) ? (LANES'(1) << dest) : '0;
    assign in_header_ready   = !payload_busy && lane_header_ready[dest];
    wire   header_take       = in_header_valid && in_header_ready;

    assign lane_payload_valid = (payload_busy && in_payload_valid) ? (LANES'(1) << payload_owner) : '0;
    assign in_payload_ready   = payload_busy && lane_payload_ready[payload_owner];
    wire   payload_last_take  = in_payload_valid && in_payload_ready && in_payload_last;

    always @(posedge clk) begin
        if (rst) begin
            payload_busy  <= 1'b0;
            payload_owner <= '0;
        end else if (!payload_busy) begin
            if (header_take && has_payload) begin
                payload_busy  <= 1'b1;
                payload_owner <= dest;
            end
        end else if (payload_last_take) begin
            payload_busy <= 1'b0;
        end
    end

    assign debug_state = {payload_busy, payload_owner};
endmodule
`default_nettype wire
