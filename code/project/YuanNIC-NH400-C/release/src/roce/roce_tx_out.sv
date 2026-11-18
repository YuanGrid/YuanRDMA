// roce_tx_out.sv
// TX 尾端：对 roce_tx 输出的帧计算 ICRC 并追加到帧尾（末拍放不下时多出一拍），
// 帧 FIFO 跨到 MAC 时钟（整帧到齐才输出，保证包内无气泡），输出 1024 bit，
// 输出格式同 qdma_to_select_*（usef = 末拍有效字节数，0 表示 128）。
//
// 1024 bit（B6386）：与 roce_top/MAC 侧同宽，删掉了原来的 512→1024 axis_adapter
// （u_upsize）。ICRC 从 DW=512/N_PIPE=3 改成 DW=1024/N_PIPE=4——这个组合 roce_rx_front
// 里已经有一份在 tx_clkout 域跑通，逻辑面积严格线性，分级 XOR 树扇入还从 8 降到 6。
`default_nettype none
`timescale 1ns/1ps
module roce_tx_out (
    input  wire              clk,
    input  wire              rst,
    input  wire              mac_clk,
    input  wire              mac_rst,
    input  wire              frame_valid,
    output wire              frame_ready,
    input  wire  [1023:0]    frame_data,
    input  wire  [127:0]     frame_keep,
    input  wire              frame_last,
    input  wire  [6:0]       frame_last_bytes,
    input  wire  [6:0]       frame_last_beat_bytes,
    output wire              mac_valid,
    input  wire              mac_ready,
    output wire  [1023:0]    mac_data,
    output wire  [6:0]       mac_last_bytes,
    output wire              mac_last
);
    localparam int BEAT_BYTES = 128;

    // ------------------------------------------------------------ ICRC
    wire frame_push = frame_valid && frame_ready;
    reg  frame_first;
    always @(posedge clk) begin
        if (rst)       frame_first <= 1'b1;
        else if (frame_push) frame_first <= frame_last;
    end
    wire        icrc_valid;
    wire [31:0] icrc_value;
    roce_icrc #(.DW(BEAT_BYTES*8), .N_PIPE(4)) u_icrc (
        .clk(clk), .rst(rst),
        .in_valid(frame_push), .in_data(frame_data), .in_keep(frame_keep), .in_first(frame_first), .in_last(frame_last),
        .out_valid(icrc_valid), .out_icrc(icrc_value), .out_icrc_ok()
    );

    wire          staging_valid, staging_last, in_ready;
    wire [1023:0] staging_data;
    wire [127:0]  staging_keep;
    wire [6:0]    staging_last_bytes;
    wire [6:0]    staging_last_beat_bytes;
    axis_async_fifo #(
        .DEPTH(64), .DATA_WIDTH(1024), .KEEP_ENABLE(0), .LAST_ENABLE(1),
        .USER_ENABLE(1), .USER_WIDTH(142)
    ) u_staging_fifo (
        .s_clk(clk), .s_rst(rst),
        .s_axis_tdata(frame_data), .s_axis_tkeep('0), .s_axis_tvalid(frame_valid), .s_axis_tready(frame_ready),
        .s_axis_tlast(frame_last), .s_axis_tid(8'd0), .s_axis_tdest(8'd0),
        .s_axis_tuser({frame_last_bytes, frame_last_beat_bytes, frame_keep}),
        .m_clk(clk), .m_rst(rst),
        .m_axis_tdata(staging_data), .m_axis_tkeep(), .m_axis_tvalid(staging_valid), .m_axis_tready(in_ready),
        .m_axis_tlast(staging_last), .m_axis_tid(), .m_axis_tdest(), .m_axis_tuser({staging_last_bytes, staging_last_beat_bytes, staging_keep}),
        .s_pause_req(1'b0), .s_pause_ack(), .m_pause_req(1'b0), .m_pause_ack(),
        .s_status_depth(), .s_status_depth_commit(), .s_status_overflow(),
        .s_status_bad_frame(), .s_status_good_frame(),
        .m_status_depth(), .m_status_depth_commit(), .m_status_overflow(),
        .m_status_bad_frame(), .m_status_good_frame()
    );

    wire        result_valid, result_ready;
    wire [31:0] result_icrc;
    axis_async_fifo #(
        .DEPTH(128), .DATA_WIDTH(32), .KEEP_ENABLE(0), .LAST_ENABLE(0), .USER_ENABLE(0)
    ) u_result_fifo (
        .s_clk(clk), .s_rst(rst),
        .s_axis_tdata(icrc_value), .s_axis_tkeep('0), .s_axis_tvalid(icrc_valid), .s_axis_tready(),
        .s_axis_tlast(1'b1), .s_axis_tid(8'd0), .s_axis_tdest(8'd0), .s_axis_tuser(1'b0),
        .m_clk(clk), .m_rst(rst),
        .m_axis_tdata(result_icrc), .m_axis_tkeep(), .m_axis_tvalid(result_valid), .m_axis_tready(result_ready),
        .m_axis_tlast(), .m_axis_tid(), .m_axis_tdest(), .m_axis_tuser(),
        .s_pause_req(1'b0), .s_pause_ack(), .m_pause_req(1'b0), .m_pause_ack(),
        .s_status_depth(), .s_status_depth_commit(), .s_status_overflow(),
        .s_status_bad_frame(), .s_status_good_frame(),
        .m_status_depth(), .m_status_depth_commit(), .m_status_overflow(),
        .m_status_bad_frame(), .m_status_good_frame()
    );
    // ------------------------------------------------------------ 追加 ICRC
    // 末拍有效 last_beat_bytes 字节（1..128），ICRC 放在 last_beat_bytes..n+3；
    // last_beat_bytes > 124 时多出一拍放剩余字节。
    wire [6:0]  last_beat_bytes  = (staging_last_beat_bytes == 7'd0) ? 7'd0 : staging_last_beat_bytes;
    wire        needs_extra_beat = (last_beat_bytes > 7'd124);
    reg         extra_beat;
    reg  [31:0] extra_icrc;
    reg  [6:0]  extra_last_bytes;
    reg  [6:0]  extra_frame_last_bytes;

    function automatic [1151:0] insert_icrc(input [1023:0] beat_data, input [127:0] beat_keep, input [31:0] icrc,
                                   input integer byte_offset);
        integer byte_lane, icrc_byte;
        reg [1023:0] out_data_bytes;
        reg [127:0]  out_keep_bits;
        begin
            out_data_bytes = beat_data; out_keep_bits = beat_keep;
            for (byte_lane = 0; byte_lane < BEAT_BYTES; byte_lane = byte_lane + 1) begin
                icrc_byte = byte_lane + byte_offset;
                if (icrc_byte >= 0 && icrc_byte < 4) begin
                    out_data_bytes[byte_lane*8 +: 8] = icrc[icrc_byte*8 +: 8];
                    out_keep_bits[byte_lane]        = 1'b1;
                end
            end
            insert_icrc = {out_keep_bits, out_data_bytes};
        end
    endfunction

    wire [1151:0] inserted_last  = insert_icrc(staging_data, staging_keep, result_icrc, -int'(last_beat_bytes));
    wire [1151:0] inserted_extra = insert_icrc(1024'd0, 128'd0, extra_icrc, BEAT_BYTES - int'(extra_last_bytes));

    wire [1023:0] out_data  = extra_beat ? inserted_extra[1023:0]    : staging_last ? inserted_last[1023:0]    : staging_data;
    wire [127:0]  out_keep  = extra_beat ? inserted_extra[1151:1024] : staging_last ? inserted_last[1151:1024] : staging_keep;
    wire          out_valid = extra_beat ? 1'b1 : (staging_valid && (!staging_last || result_valid));
    wire          out_last  = extra_beat ? 1'b1 : (staging_last && !needs_extra_beat);
    wire [6:0]    out_user  = extra_beat ? extra_frame_last_bytes[6:0] : staging_last_bytes[6:0];
    // usef 约定 0 表示 128：payload 帧末拍若正好 128 字节，last_bytes[6:0] 是 0，符合约定
    assign in_ready = !extra_beat && out_ready_internal && (!staging_last || result_valid);
    assign result_ready = !extra_beat && out_ready_internal && staging_valid && staging_last;

    // ------------------------------------------------------------ 帧 FIFO，跨到 MAC 时钟
    wire out_ready_internal;
    axis_async_fifo #(
        .DEPTH(128), .DATA_WIDTH(1024), .KEEP_ENABLE(0), .LAST_ENABLE(1),
        .USER_ENABLE(1), .USER_WIDTH(7), .FRAME_FIFO(1), .DROP_BAD_FRAME(0)
    ) u_cdc (
        .s_clk(clk), .s_rst(rst),
        .s_axis_tdata(out_data), .s_axis_tkeep('0), .s_axis_tvalid(out_valid), .s_axis_tready(out_ready_internal),
        .s_axis_tlast(out_last), .s_axis_tid(8'd0), .s_axis_tdest(8'd0), .s_axis_tuser(out_user),
        .m_clk(mac_clk), .m_rst(mac_rst),
        .m_axis_tdata(mac_data), .m_axis_tkeep(), .m_axis_tvalid(mac_valid), .m_axis_tready(mac_ready),
        .m_axis_tlast(mac_last), .m_axis_tid(), .m_axis_tdest(), .m_axis_tuser(mac_last_bytes),
        .s_pause_req(1'b0), .s_pause_ack(), .m_pause_req(1'b0), .m_pause_ack(),
        .s_status_depth(), .s_status_depth_commit(), .s_status_overflow(),
        .s_status_bad_frame(), .s_status_good_frame(),
        .m_status_depth(), .m_status_depth_commit(), .m_status_overflow(),
        .m_status_bad_frame(), .m_status_good_frame()
    );

    always @(posedge clk) begin
        if (rst) begin
            extra_beat <= 1'b0;
        end else if (extra_beat) begin
            if (out_ready_internal) extra_beat <= 1'b0;
        end else if (staging_valid && staging_last && result_valid && out_ready_internal && needs_extra_beat) begin
            extra_beat           <= 1'b1;
            extra_icrc           <= result_icrc;
            extra_last_bytes     <= last_beat_bytes;
            extra_frame_last_bytes <= staging_last_bytes;
        end
    end
endmodule
`default_nettype wire
