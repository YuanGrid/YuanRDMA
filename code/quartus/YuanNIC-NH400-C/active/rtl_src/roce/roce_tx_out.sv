// roce_tx_out.sv
// TX 尾端：对 roce_tx 输出的帧计算 ICRC 并追加到帧尾（末拍放不下时多出一拍），
// 帧 FIFO 跨到 MAC 时钟（整帧到齐才输出，保证包内无气泡），输出 1024 bit，
// 输出格式同 qdma_to_select_*（usef = 末拍有效字节数，0 表示 128）。
//
// 1024 bit（B6386）：与 roce_top/MAC 侧同宽，删掉了原来的 512→1024 axis_adapter
// （u_upsize）。ICRC 从 DW=512/N_PIPE=3 改成 DW=1024/N_PIPE=4——这个组合 roce_rx_front
// 里已经有一份在 tx_clkout 域跑通，逻辑面积严格线性，分级 XOR 树扇入还从 8 降到 6。
//
// 2048 bit：core 侧（roce_tx → ICRC → staging → CDC 写口）参数化为 DW，默认 2048；
// CDC 读口仍是 DW 位，在 mac 域拆成 1024 位拍再送出（mac_data / mac_last_bytes 口径不变，
// tx_mux / pfc_egress / MAC 一概不动）。带宽：core 2048×250 MHz = 512 Gbps ≥ mac 1024×390.625 MHz。
// 拆拍后加一级 roce_skid（mac 域）：pfc_egress 是组合直通，不加的话 2:1 选择会串到 tx_mux 里。
`default_nettype none
`timescale 1ns/1ps
module roce_tx_out #(
    parameter int DW = 2048
)(
    input  wire              clk,
    input  wire              rst,
    input  wire              mac_clk,
    input  wire              mac_rst,
    input  wire              frame_valid,
    output wire              frame_ready,
    input  wire  [DW-1:0]    frame_data,
    input  wire  [DW/8-1:0]  frame_keep,
    input  wire              frame_last,
    input  wire  [$clog2(DW/8)-1:0] frame_last_bytes,
    input  wire  [$clog2(DW/8)-1:0] frame_last_beat_bytes,
    output wire              mac_valid,
    input  wire              mac_ready,
    output wire  [1023:0]    mac_data,
    output wire  [6:0]       mac_last_bytes,
    output wire              mac_last
);
    localparam int BEAT_BYTES = DW / 8;
    localparam int LBW        = $clog2(BEAT_BYTES);
    localparam int PAIR       = DW / 1024;
    // ICRC 流水级数：DW=2048 时 XOR 树输入翻倍，多一级（结果走 result FIFO，延迟不影响吞吐）。
    localparam int ICRC_PIPE  = (DW >= 2048) ? 5 : 4;

    // ------------------------------------------------------------ ICRC
    wire frame_push = frame_valid && frame_ready;
    reg  frame_first;
    always @(posedge clk) begin
        if (rst)       frame_first <= 1'b1;
        else if (frame_push) frame_first <= frame_last;
    end
    wire        icrc_valid;
    wire [31:0] icrc_value;
    roce_icrc #(.DW(DW), .N_PIPE(ICRC_PIPE)) u_icrc (
        .clk(clk), .rst(rst),
        .in_valid(frame_push), .in_data(frame_data), .in_keep(frame_keep), .in_first(frame_first), .in_last(frame_last),
        .out_valid(icrc_valid), .out_icrc(icrc_value), .out_icrc_ok()
    );

    wire          staging_valid, staging_last, in_ready;
    wire [DW-1:0] staging_data;
    wire [BEAT_BYTES-1:0] staging_keep;
    wire [LBW-1:0] staging_last_bytes;
    wire [LBW-1:0] staging_last_beat_bytes;
    axis_async_fifo #(
        .DEPTH(64 / PAIR), .DATA_WIDTH(DW), .KEEP_ENABLE(0), .LAST_ENABLE(1),
        .USER_ENABLE(1), .USER_WIDTH(2*LBW + BEAT_BYTES)
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
    // 末拍有效 last_beat_bytes 字节（1..BEAT_BYTES），ICRC 放在 last_beat_bytes..n+3；
    // last_beat_bytes > BEAT_BYTES-4 时多出一拍放剩余字节。
    // （帧长恒 ≡ 2 mod 4：头 54..74 均 ≡ 2，payload+pad ≡ 0，所以 last_beat_bytes 不会是 0。）
    wire [LBW-1:0] last_beat_bytes  = staging_last_beat_bytes;
    wire        needs_extra_beat = (last_beat_bytes > LBW'(BEAT_BYTES - 4));
    reg         extra_beat;
    reg  [31:0] extra_icrc;
    reg  [LBW-1:0] extra_last_bytes;
    reg  [LBW-1:0] extra_frame_last_bytes;

    function automatic [DW+BEAT_BYTES-1:0] insert_icrc(input [DW-1:0] beat_data, input [BEAT_BYTES-1:0] beat_keep, input [31:0] icrc,
                                   input integer byte_offset);
        integer byte_lane, icrc_byte;
        reg [DW-1:0] out_data_bytes;
        reg [BEAT_BYTES-1:0] out_keep_bits;
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

    wire [DW+BEAT_BYTES-1:0] inserted_last  = insert_icrc(staging_data, staging_keep, result_icrc, -int'(last_beat_bytes));
    wire [DW+BEAT_BYTES-1:0] inserted_extra = insert_icrc({DW{1'b0}}, {BEAT_BYTES{1'b0}}, extra_icrc, BEAT_BYTES - int'(extra_last_bytes));

    wire [DW-1:0] out_data  = extra_beat ? inserted_extra[DW-1:0] : staging_last ? inserted_last[DW-1:0] : staging_data;
    wire          out_valid = extra_beat ? 1'b1 : (staging_valid && (!staging_last || result_valid));
    wire          out_last  = extra_beat ? 1'b1 : (staging_last && !needs_extra_beat);
    wire [LBW-1:0] out_user = extra_beat ? extra_frame_last_bytes : staging_last_bytes;
    // usef 约定 0 表示一整拍（帧长 ≡ 2 mod 4，实际不会出现）
    assign in_ready = !extra_beat && out_ready_internal && (!staging_last || result_valid);
    assign result_ready = !extra_beat && out_ready_internal && staging_valid && staging_last;

    // ------------------------------------------------------------ 帧 FIFO，跨到 MAC 时钟
    // 深度按字节保持 16 KB（DW=2048 时 64 拍），整帧到齐才放行（FRAME_FIFO）。
    wire out_ready_internal;
    wire          cdc_valid, cdc_ready, cdc_last;
    wire [DW-1:0] cdc_data;
    wire [LBW-1:0] cdc_last_bytes;
    axis_async_fifo #(
        .DEPTH(128 / PAIR), .DATA_WIDTH(DW), .KEEP_ENABLE(0), .LAST_ENABLE(1),
        .USER_ENABLE(1), .USER_WIDTH(LBW), .FRAME_FIFO(1), .DROP_BAD_FRAME(0)
    ) u_cdc (
        .s_clk(clk), .s_rst(rst),
        .s_axis_tdata(out_data), .s_axis_tkeep('0), .s_axis_tvalid(out_valid), .s_axis_tready(out_ready_internal),
        .s_axis_tlast(out_last), .s_axis_tid(8'd0), .s_axis_tdest(8'd0), .s_axis_tuser(out_user),
        .m_clk(mac_clk), .m_rst(mac_rst),
        .m_axis_tdata(cdc_data), .m_axis_tkeep(), .m_axis_tvalid(cdc_valid), .m_axis_tready(cdc_ready),
        .m_axis_tlast(cdc_last), .m_axis_tid(), .m_axis_tdest(), .m_axis_tuser(cdc_last_bytes),
        .s_pause_req(1'b0), .s_pause_ack(), .m_pause_req(1'b0), .m_pause_ack(),
        .s_status_depth(), .s_status_depth_commit(), .s_status_overflow(),
        .s_status_bad_frame(), .s_status_good_frame(),
        .m_status_depth(), .m_status_depth_commit(), .m_status_overflow(),
        .m_status_bad_frame(), .m_status_good_frame()
    );

    // ------------------------------------------------------------ mac 域拆拍：DW → 1024
    generate
        if (PAIR == 2) begin : gen_split
            // 一个 2048 位条目 = 低半拍 + 高半拍；末条目若只用到低半（末拍字节 1..128）就只出低半。
            // 末拍字节数 lb 是 mod 256 的值：低半为末拍时 lb∈1..128 → 7 位口径 lb[6:0]（128→0 表示整拍）；
            // 高半为末拍时 lb∈129..255 → lb−128 = lb[6:0]。两种情况都直接取低 7 位。
            reg  split_phase;                      // 1 = 正在送高半
            wire lo_is_last = cdc_last && (cdc_last_bytes != 8'd0) && (cdc_last_bytes <= 8'd128);
            wire          sp_valid = cdc_valid;
            wire          sp_ready;
            wire [1023:0] sp_data  = split_phase ? cdc_data[2047:1024] : cdc_data[1023:0];
            wire          sp_last  = split_phase ? cdc_last : lo_is_last;
            wire [6:0]    sp_lb    = cdc_last_bytes[6:0];
            assign cdc_ready = sp_ready && (split_phase || lo_is_last);
            always @(posedge mac_clk) begin
                if (mac_rst)                    split_phase <= 1'b0;
                else if (sp_valid && sp_ready)  split_phase <= split_phase ? 1'b0 : !lo_is_last;
            end
            roce_skid #(.WIDTH(1 + 7 + 1024)) u_split_skid (
                .clk(mac_clk), .rst(mac_rst),
                .s_valid(sp_valid), .s_ready(sp_ready), .s_data({sp_last, sp_lb, sp_data}),
                .m_valid(mac_valid), .m_ready(mac_ready), .m_data({mac_last, mac_last_bytes, mac_data})
            );
        end else begin : gen_nosplit
            assign mac_valid      = cdc_valid;
            assign cdc_ready      = mac_ready;
            assign mac_data       = cdc_data[1023:0];
            assign mac_last       = cdc_last;
            assign mac_last_bytes = cdc_last_bytes[6:0];
        end
    endgenerate

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
