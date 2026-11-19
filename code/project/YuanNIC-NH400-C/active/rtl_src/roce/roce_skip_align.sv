// roce_skip_align.sv
// 从帧中取出 [skip, skip+transfer_length) 字节，输出从第 0 字节开始的 DW bit 流（末拍 tlast、keep 连续）。
// 输入帧多余的尾部（pad、ICRC）丢弃。每帧先给一个元数据（transfer_length 必须 >= 1），再给整帧数据。
//
// DW 可选 512（每拍 64 B）或 1024（每拍 128 B）。skip 的合法范围是 0..127，
// 对应最长头 74 B。DW=1024 时一拍就能装下整个 skip 范围，first_useful_beat 恒为 0，
// 移位只在单拍内进行；DW=512 时 skip>=64 要跨到第二拍。
//
// 元数据与数据首拍可以同拍（meta_valid && in_valid）：此时本拍既装载元数据又把 in_data
// 当第 0 拍消费掉，in_ready 在 !frame_active 时照样为 1。TX 靠这个省掉一拍的组包开销；
// 只给元数据、下一拍再给数据的老用法（RX）行为不变。
`default_nettype none
`timescale 1ns/1ps
module roce_skip_align #(
    parameter int DW = 512                  // 数据位宽：512 或 1024
)(
    input  wire              clk,
    input  wire              rst,
    input  wire              meta_valid,
    output wire              meta_ready,
    input  wire  [6:0]       meta_skip,      // 0..127
    input  wire  [12:0]      meta_length,       // 1..4096
    input  wire              in_valid,
    output wire              in_ready,
    input  wire  [DW-1:0]    in_data,
    input  wire              in_last,
    output reg               out_valid,
    input  wire              out_ready,
    output reg   [DW-1:0]    out_data,
    output reg   [DW/8-1:0]  out_keep,
    output reg               out_last,
    // 调试：{out_valid, input_done, frame_active}，见 roce_debug.sv 0x056C[7:4]
    output wire  [2:0]       debug_state
);
    localparam int BEAT_BYTES = DW / 8;             // 64 或 128
    localparam int SHIFT_W    = $clog2(BEAT_BYTES); // 6 或 7
    localparam int BYTE_W     = $clog2(BEAT_BYTES + 1);  // 7 或 8，可表示 0..BEAT_BYTES
    localparam [12:0] BEAT_BYTES_V = 13'(BEAT_BYTES);

    reg          frame_active;
    reg  [6:0]   beat_index;          // 当前输入拍序号（饱和）
    reg          first_useful_beat;         // 首个有用拍 = skip/BEAT_BYTES，DW=1024 时恒 0
    reg  [SHIFT_W-1:0] byte_shift;
    reg  [12:0]  bytes_remaining;
    reg          have_previous_beat;
    reg  [DW-1:0] previous_beat;
    reg          input_done;      // 输入已到帧尾，只剩冲刷

    wire         can_advance = !out_valid || out_ready;
    wire [12:0]  output_bytes   = (bytes_remaining > BEAT_BYTES_V) ? BEAT_BYTES_V : bytes_remaining;
    wire         consume_beat = frame_active && !input_done && can_advance && in_valid;
    wire         beat_is_useful  = (beat_index >= {6'd0, first_useful_beat}) && (bytes_remaining != 13'd0);

    // 老帧已输入完、只剩收尾：本拍要么在冲刷最后一拍（frame_flush），要么上一拍已把
    // 最后一段输出完（frame_close）。这两拍里老帧的输出内容全部由旧寄存器决定，
    // 所以可以同拍装载下一帧的元数据与首拍，帧与帧之间不再空转。
    wire         frame_flush = frame_active && input_done && can_advance && (bytes_remaining != 13'd0);
    wire         frame_close = frame_active && input_done && can_advance && (bytes_remaining == 13'd0);
    // 元数据可以被接收的时刻：老帧空闲、正在冲刷最后一拍、或正在关闭。
    // 必须同时 can_advance：否则会出现"元数据收了、首拍收不了"的半个握手——上游按 meta_ready
    // 认为帧已开铺，却因为 in_ready 为 0 不肯弹任务，下一拍再把同一个首拍当第二拍送进来。
    wire         meta_slot   = (!frame_active || frame_flush || frame_close) && can_advance;
    wire         meta_load   = meta_valid && meta_slot;
    // 元数据与本帧首拍同拍：首拍按第 0 拍处理（用当拍的 meta_skip/meta_length）
    wire         meta_load_first = meta_load && in_valid;
    wire         first_is_useful = ((meta_skip >> SHIFT_W) != 7'd0) ? 1'b0 : (meta_length != 13'd0);

    // meta_slot 为 1 的那些拍 in_ready 恒为 1，两者绑在一起，不会有半拍握手。
    // 反过来：老帧正在收尾但本拍没有元数据时，in_ready 必须是 0——那些拍数据是收不下的
    // （consume_beat 要求 !input_done），拉高会让上游以为首拍已被接受而把它丢掉。
    assign in_ready = meta_slot ? meta_valid : (frame_active && !input_done && can_advance);
    assign meta_ready = meta_slot;

    function automatic [BEAT_BYTES-1:0] low_bits_mask(input [BYTE_W-1:0] count);
        // 注意：常数 1 必须显式扩到 BEAT_BYTES 位，否则 +1 之后被截成 32 位，
        // count 接近 BEAT_BYTES 时移位结果会丢高位。
        low_bits_mask = (count >= BYTE_W'(BEAT_BYTES)) ? {BEAT_BYTES{1'b1}}
                                                       : (({{(BEAT_BYTES-1){1'b0}}, 1'b1} << count) - 1);
    endfunction
    function automatic [DW-1:0] shift_right_bytes(input [2*DW-1:0] value, input [SHIFT_W-1:0] shift);
        shift_right_bytes = DW'(value >> {shift, 3'b000});
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            frame_active  <= 1'b0;
            out_valid <= 1'b0;
        end else begin
            // out_valid 只在这一个地方清零：有输出拍（consume_beat 里出数 / flush）时
            // 下面的赋值会把它重新置 1，避免同一寄存器被多个分支驱动。
            if (out_valid && out_ready)
                out_valid <= 1'b0;

            // ---------------- 老帧：输出最后一拍 / 收尾
            // 这一段的输出内容全部由旧寄存器决定，与下面的新帧装载互不干扰。
            if (frame_flush) begin
                out_data  <= shift_right_bytes({{DW{1'b0}}, previous_beat}, byte_shift);
                out_keep  <= low_bits_mask(output_bytes[BYTE_W-1:0]);
                out_last  <= 1'b1;
                bytes_remaining     <= 13'd0;
            end else if (consume_beat) begin
                if (beat_index != 7'h7f) beat_index <= beat_index + 7'd1;
                if (beat_is_useful) begin
                    previous_beat      <= in_data;
                    have_previous_beat <= 1'b1;
                    if (have_previous_beat) begin
                        out_data  <= shift_right_bytes({in_data, previous_beat}, byte_shift);
                        out_keep  <= low_bits_mask(output_bytes[BYTE_W-1:0]);
                        if (bytes_remaining <= BEAT_BYTES_V) out_last <= 1'b1;
                        else                                 out_last <= 1'b0;
                        bytes_remaining     <= bytes_remaining - output_bytes;
                    end
                end
                if (in_last) begin
                    input_done <= 1'b1;
                    // 本拍已经补完最后一段，或刚把 previous_beat 装上：都在 input_done 里收尾
                end
            end else if (frame_close) begin
                frame_active <= 1'b0;
            end

            // ---------------- 新帧装载（放在最后，覆盖上面的帧内状态）
            // 可与老帧的 frame_flush/frame_close 同拍：老帧的输出已在本拍按旧寄存器定好，
            // 本拍直接把帧内状态切到新帧，帧与帧之间不再空转。
            // 与 consume_beat 互斥（consume_beat 要求 !input_done，而 flush/close 要求 input_done）。
            if (meta_load) begin
                frame_active    <= 1'b1;
                beat_index         <= 7'd0;
                // skip / BEAT_BYTES：DW=1024 时 skip<128=BEAT_BYTES，结果恒 0
                first_useful_beat  <= (meta_skip >> SHIFT_W) != 7'd0;
                byte_shift         <= meta_skip[SHIFT_W-1:0];
                bytes_remaining       <= meta_length;
                have_previous_beat <= 1'b0;
                input_done     <= 1'b0;
                // 元数据与首拍同拍：首拍在这里按第 0 拍处理。
                // 首个有用拍一定不是输出拍（没有 previous_beat 可拼），所以只需存下来、不必出数。
                if (meta_load_first) begin
                    beat_index <= 7'd1;
                    if (first_is_useful) begin
                        previous_beat      <= in_data;
                        have_previous_beat <= 1'b1;
                    end
                    if (in_last) input_done <= 1'b1;
                end
            end

            // ---------------- 输出有效位的统一置位（位于清零之后，同拍输出优先）
            if (frame_flush) begin
                out_valid <= 1'b1;
            end else if (consume_beat && beat_is_useful && have_previous_beat) begin
                out_valid <= 1'b1;
            end
        end
    end
    assign debug_state = {out_valid, input_done, frame_active};
endmodule
`default_nettype wire
