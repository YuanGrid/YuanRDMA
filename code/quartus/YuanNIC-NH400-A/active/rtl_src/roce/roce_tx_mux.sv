// roce_tx_mux.sv
// MAC 时钟域 2:1 包仲裁：原 QDMA 发包流（口 0）与 RDMA 引擎发包流（口 1），
// 按包轮询，包内不切换。两路输入都必须包内无气泡（QDMA 侧经 u91 寄存器片、
// RDMA 侧经 frame FIFO 保证）。输出经 axi_stream_register_slice 打一拍。
// 数据格式沿用 qdma_to_select_*：1024 bit，usef = 最后一拍有效字节数（0 表示 128）。
`default_nettype none
`timescale 1ns/1ps
module roce_tx_mux #(
    parameter int DATA_W  = 1024,
    parameter int USERF_W = 7,
    // 包内空洞超时（clk 拍）。B6395 上板实测：对端掉链时 QDMA 那一路的半包被截断，
    // tlast 永远不来，in_packet 卡在 1，另一路被永久挡住 —— 整条 TX 停摆（ping 都不通）。
    // 超时后主动放弃这个残包：in_packet 清零、切换优先口、abort 计数 +1。
    // 残包已经发到线上，对端会按 FCS/ICRC 扔掉，代价只是丢一个包，换回通路可用。
    parameter int IDLE_TIMEOUT = 4096
)(
    input  wire                clk,
    input  wire                rst_n,
    input  wire  [1:0]         in_valid,
    input  wire  [2*DATA_W-1:0] in_data,
    input  wire  [2*USERF_W-1:0] in_last_bytes,
    input  wire  [1:0]         in_last,
    output wire  [1:0]         in_ready,
    output wire                out_valid,
    output wire  [DATA_W-1:0]  out_data,
    output wire  [USERF_W-1:0] out_last_bytes,
    output wire                out_last,
    input  wire                out_ready,
    // 调试：{in_packet, selected_port, priority_port}，见 roce_debug.sv 的 TX_MERGE_STATE
    output wire  [2:0]         debug_state,
    // 因包内空洞超时被放弃的残包个数（饱和 0xFFFF），正常应恒为 0
    output wire  [15:0]        aborted_packets
);
    reg        in_packet;      // 正在转发一个包
    reg        selected_port;       // 当前/上次选中的口
    reg        priority_port;      // 下一次优先的口
    reg [15:0] abort_count;
    reg [15:0] idle_count;

    wire       chosen_port = in_packet ? selected_port : (in_valid[priority_port] ? priority_port : ~priority_port);
    wire       chosen_valid    = in_valid[chosen_port];
    wire       slice_ready;

    assign in_ready = {chosen_port & slice_ready, ~chosen_port & slice_ready};

    // 包内空洞判定：在包里、本拍没有数据可发
    wire       in_gap   = in_packet && !chosen_valid;
    wire       gap_hit  = in_gap && (idle_count >= 16'(IDLE_TIMEOUT - 1));

    always @(posedge clk) begin
        if (!rst_n) begin
            in_packet     <= 1'b0;
            selected_port <= 1'b0;
            priority_port <= 1'b0;
            abort_count   <= 16'd0;
            idle_count    <= 16'd0;
        end else if (gap_hit) begin
            // 放弃残包，切到另一路
            in_packet     <= 1'b0;
            priority_port <= ~selected_port;
            idle_count    <= 16'd0;
            if (abort_count != 16'hFFFF)
                abort_count <= abort_count + 16'd1;
        end else if (chosen_valid && slice_ready) begin
            selected_port  <= chosen_port;
            in_packet <= !in_last[chosen_port];
            idle_count <= 16'd0;
            if (in_last[chosen_port])
                priority_port <= ~chosen_port;
        end else begin
            idle_count <= in_gap ? (idle_count + 16'd1) : 16'd0;
        end
    end

    axi_stream_register_slice #(
        .TDATA_W (DATA_W ),
        .TID_W   (1      ),
        .TDEST_W (1      ),
        .TUSER_W (USERF_W),
        .MODE    ("full" )
    ) u_out_slice (
        .s_axis_tvalid (chosen_valid                                  ),
        .s_axis_tdata  (in_data[chosen_port*DATA_W +: DATA_W]      ),
        .s_axis_tkeep  ('0                                 ),
        .s_axis_tlast  (in_last[chosen_port]                       ),
        .s_axis_tid    (1'b0                               ),
        .s_axis_tdest  (1'b0                               ),
        .s_axis_tuser  (in_last_bytes[chosen_port*USERF_W +: USERF_W]    ),
        .s_axis_tready (slice_ready                                  ),
        .m_axis_tvalid (out_valid                            ),
        .m_axis_tdata  (out_data                             ),
        .m_axis_tkeep  (                                   ),
        .m_axis_tlast  (out_last                             ),
        .m_axis_tid    (                                   ),
        .m_axis_tdest  (                                   ),
        .m_axis_tuser  (out_last_bytes                             ),
        .m_axis_tready (out_ready                            ),
        .aclk          (clk                                ),
        .aresetn       (rst_n                              )
    );
    assign debug_state = {in_packet, selected_port, priority_port};
    assign aborted_packets = abort_count;
endmodule
`default_nettype wire
