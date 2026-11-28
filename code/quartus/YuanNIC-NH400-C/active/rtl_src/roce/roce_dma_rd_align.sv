// roce_dma_rd_align.sv
// BAS 读数据整形：把 128 B 对齐的 1024 bit 读回拍，按请求的 addr[6:0]/transfer_length 转成
// 从第 0 字节开始的 1024 bit 流（tkeep 只在最后一拍不满），每个请求以 tlast 结束。
//
// 1024 bit 版本（B6386）：输入一拍 128 B、输出一拍 128 B，输入输出同宽，一拍一段。
// 旧版输出 512 bit，需要 half_index[0] 把每个 128 B 读回拍拆成两个 64 B 半拍，in_ready
// 每两拍才拉高一次，成了 TX 取 payload 的限速点（2 拍/128 B）。
// 因为 start offset s < 128 = BEAT_BYTES，首拍一定有用，不需要 first_useful_beat；
// 跨拍拼接用 {in_data, previous_beat} 的 2048 位桶形移位完成，与 roce_skip_align 同构。
//
// DW 参数化：DW=2048 时输入是 pcie 域拼好的「256 B 对齐双拍」，
// 起点偏移 s = addr[7:0]（0..255，8 位移位，LUT6 下与 7 位同为 4 级），输出一拍 256 B。
// 拍数公式与 DW=1024 同构：beat_count = ceil((s + length) / BEAT_BYTES)。
// DW=1024（默认）与参数化之前逐位等价。
//
// 请求间零空泡（B6415）：
// B6414 及以前每个请求固定多 3 拍——c0 装 meta（meta_ready = !request_active，必须等上一请求
// 完全结束）、c1 首拍只存不出（拼接要上一拍）、末尾单独一拍 finish 清 request_active。
// 1 KB 对齐请求 11 拍只出 8 拍（占空 0.727），是 server read_bw 单 lane 的墙
// （125 MHz 下理论 93.1 Gb/s，实测 89.81）。现在：
//   1. 预取寄存器 next_*：meta_ready = !next_valid（纯寄存器，不吃 out_ready 那条长组合链），
//      当前请求结束的同一拍（request_done）就把下一请求装进来，下一拍直接取它的首拍；
//      空闲时 meta 直接旁路进当前请求，不多一拍延迟。
//   2. byte_shift == 0 时不需要拼接：每取一拍就出一拍（out_data = in_data），没有首拍只存、
//      也没有末尾 flush。1 KB 对齐 = 8 拍/请求。
//   3. byte_shift != 0 仍按原拼接：读回 N = ceil((s+L)/128) 拍，首拍只存；
//      N == ceil(L/128) 时末尾还要一拍 flush。1 KB 非对齐 = 9 拍/请求。
//   4. out_tag / out_error 与当前请求的 cur_tag / error_seen 分开：请求切换与末拍输出同拍发生，
//      末拍还在输出寄存器里等 out_ready 时，cur_tag 已经是下一请求的了。
`default_nettype none
`timescale 1ns/1ps
module roce_dma_rd_align #(
    parameter int TAG_W = 4,
    parameter int DW    = 1024,
    parameter int AW    = $clog2(DW/8)          // meta_address_low 位宽 = 拍内字节偏移
)(
    input  wire               clk,
    input  wire               rst,
    // 请求元数据（与 AR 同序）
    input  wire               meta_valid,
    output wire               meta_ready,
    input  wire  [AW-1:0]     meta_address_low,
    input  wire  [12:0]       meta_length,        // 1..4096
    input  wire  [TAG_W-1:0]  meta_tag,
    // BAS 读回拍（已过 CDC）
    input  wire               in_valid,
    output wire               in_ready,
    input  wire  [DW-1:0]     in_data,
    input  wire               in_error,
    // 输出
    output reg                out_valid,
    input  wire               out_ready,
    output reg   [DW-1:0]     out_data,
    output reg   [DW/8-1:0]   out_keep,
    output reg                out_last,
    output reg   [TAG_W-1:0]  out_tag,
    output reg                out_error
);
    localparam int BEAT_BYTES = DW / 8;             // 128 / 256
    localparam int SHIFT_W    = AW;                 // 7 / 8
    localparam int BYTE_W     = AW + 1;             // 可表示 0..BEAT_BYTES
    localparam [12:0] BEAT_BYTES_V = 13'(BEAT_BYTES);

    // ---------------------------------------------------------------- 当前请求
    reg                request_active;
    reg  [6:0]         beats_left;                  // 还要从上游取几拍（1..33）
    reg  [SHIFT_W-1:0] byte_shift;
    reg                shift_zero;                  // byte_shift == 0：直出，不拼接
    reg  [12:0]        bytes_remaining;             // 还要输出几个字节
    reg  [TAG_W-1:0]   cur_tag;
    reg                error_seen;
    reg                have_previous_beat;
    reg  [DW-1:0]      previous_beat;

    // ---------------------------------------------------------------- 预取的下一请求
    reg                next_valid;
    reg  [6:0]         next_beats;
    reg  [SHIFT_W-1:0] next_shift;
    reg                next_shift_zero;
    reg  [12:0]        next_length;
    reg  [TAG_W-1:0]   next_tag;

    // 一拍装下整个 skip 范围（s < 128），所以 beat_count = ceil((s + length) / 128)
    wire [13:0]  meta_end_offset = 14'(meta_address_low) + {1'b0, meta_length};
    wire [13:0]  meta_beat_count = (meta_end_offset + 14'(BEAT_BYTES - 1)) >> SHIFT_W;

    wire          can_advance  = !out_valid || out_ready;
    wire          need_beat    = (beats_left != 7'd0);
    wire          last_beat    = (beats_left == 7'd1);
    wire [12:0]   output_bytes = (bytes_remaining > BEAT_BYTES_V) ? BEAT_BYTES_V : bytes_remaining;
    wire          last_output  = (bytes_remaining <= BEAT_BYTES_V);

    // 取一拍；取到的这一拍能不能马上出一拍：对齐时总能，非对齐时要有上一拍可拼。
    wire          consume_beat = request_active && can_advance && need_beat && in_valid;
    wire          emit_on_consume = consume_beat && (shift_zero || have_previous_beat) &&
                                    (bytes_remaining != 13'd0);
    // 请求结束的三种方式（都要求 can_advance，与原来的 finish_request 同条件）：
    //   a) 取最后一拍的同时出最后一拍（对齐；或非对齐且读回拍数 = 输出拍数 + 1）
    //   b) 上游已取完，还剩 previous_beat 里的尾巴 → flush 出最后一拍
    //   c) 长度为 0 的退化请求：不出拍，直接结束（保持原行为）
    wire          done_on_consume = emit_on_consume && last_beat && last_output;
    wire          flush_previous  = request_active && can_advance && !need_beat && (bytes_remaining != 13'd0);
    wire          finish_empty    = request_active && can_advance && !need_beat && (bytes_remaining == 13'd0);
    wire          request_done    = done_on_consume || flush_previous || finish_empty;
    wire          current_free    = !request_active || request_done;

    assign in_ready   = request_active && can_advance && need_beat;
    assign meta_ready = !next_valid;
    wire          meta_take = meta_valid && !next_valid;

    function automatic [BEAT_BYTES-1:0] low_bits_mask(input [BYTE_W-1:0] count);
        low_bits_mask = (count >= BYTE_W'(BEAT_BYTES)) ? {BEAT_BYTES{1'b1}}
                                                       : (({{(BEAT_BYTES-1){1'b0}}, 1'b1} << count) - 1);
    endfunction

    function automatic [DW-1:0] shift_right_bytes(input [2*DW-1:0] value, input [SHIFT_W-1:0] shift);
        shift_right_bytes = DW'(value >> {shift, 3'b000});
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            request_active <= 1'b0;
            next_valid     <= 1'b0;
            out_valid      <= 1'b0;
        end else begin
            if (out_valid && out_ready)
                out_valid <= 1'b0;

            // ---------------------------------------------------- 当前请求推进
            if (consume_beat) begin
                beats_left         <= beats_left - 7'd1;
                error_seen         <= error_seen | in_error;
                previous_beat      <= in_data;
                have_previous_beat <= 1'b1;
                if (emit_on_consume) begin
                    out_valid <= 1'b1;
                    out_data  <= shift_zero ? in_data
                                            : shift_right_bytes({in_data, previous_beat}, byte_shift);
                    out_keep  <= low_bits_mask(output_bytes[BYTE_W-1:0]);
                    out_last  <= last_output;
                    out_tag   <= cur_tag;
                    out_error <= error_seen | in_error;
                    bytes_remaining <= bytes_remaining - output_bytes;
                end
            end else if (flush_previous) begin
                // 输入已取完但还有字节没输出：最后一拍靠 previous_beat 右移补齐（只有非对齐会走到）
                out_valid <= 1'b1;
                out_data  <= shift_right_bytes({{DW{1'b0}}, previous_beat}, byte_shift);
                out_keep  <= low_bits_mask(output_bytes[BYTE_W-1:0]);
                out_last  <= 1'b1;
                out_tag   <= cur_tag;
                out_error <= error_seen;
                bytes_remaining <= 13'd0;
            end

            // ---------------------------------------------------- 请求切换（写在后面，覆盖上面的推进）
            // 当前请求本拍结束（或本来就空）时，优先装预取的那个；预取为空就把输入口的 meta 直接装进来。
            if (current_free) begin
                if (next_valid) begin
                    request_active     <= 1'b1;
                    beats_left         <= next_beats;
                    byte_shift         <= next_shift;
                    shift_zero         <= next_shift_zero;
                    bytes_remaining    <= next_length;
                    cur_tag            <= next_tag;
                    error_seen         <= 1'b0;
                    have_previous_beat <= 1'b0;
                    next_valid         <= 1'b0;
                end else if (meta_valid) begin
                    request_active     <= 1'b1;
                    beats_left         <= meta_beat_count[6:0];
                    byte_shift         <= meta_address_low[SHIFT_W-1:0];
                    shift_zero         <= (meta_address_low == '0);
                    bytes_remaining    <= meta_length;
                    cur_tag            <= meta_tag;
                    error_seen         <= 1'b0;
                    have_previous_beat <= 1'b0;
                end else begin
                    request_active     <= 1'b0;
                end
            end

            // 当前请求还在跑：meta 先停在预取寄存器（beat 数提前算好，切换时只搬寄存器）
            if (meta_take && !current_free) begin
                next_valid      <= 1'b1;
                next_beats      <= meta_beat_count[6:0];
                next_shift      <= meta_address_low[SHIFT_W-1:0];
                next_shift_zero <= (meta_address_low == '0);
                next_length     <= meta_length;
                next_tag        <= meta_tag;
            end
        end
    end
endmodule
`default_nettype wire
