// roce_skip_align.sv
// 从帧中取出 [skip, skip+transfer_length) 字节，输出从第 0 字节开始的 DW bit 流（末拍 tlast、keep 连续）。
// 输入帧多余的尾部（pad、ICRC）丢弃。每帧先给一个元数据（transfer_length 必须 >= 1），再给整帧数据。
//
// DW 可选 512（每拍 64 B）、1024（每拍 128 B）或 2048（每拍 256 B）。skip 的位宽
// SKIP_W = log2(一拍字节数)：DW=512/1024 时 7 位（0..127），DW=2048 时 8 位（0..255）。
// DW>=1024 时一拍就能装下整个 skip 范围，first_useful_beat 恒为 0，移位只在单拍内进行；
// DW=512 时 skip>=64 要跨到第二拍。
// TX 在 DW=2048 下把头右对齐到 256 B，skip = 256 − header_length ∈ 182..202。
//
// 元数据与数据首拍可以同拍（meta_valid && in_valid）：此时本拍既装载元数据又把 in_data
// 当第 0 拍消费掉，in_ready 在 !frame_active 时照样为 1。TX 靠这个省掉一拍的组包开销；
// 只给元数据、下一拍再给数据的老用法（RX）行为不变。
//
// ---- 移位窗口（B6502，G0.4 残余时序）---------------------------------------------
// 桶形移位的逻辑深度 = 移位量的位宽，而移位量位宽只取决于 **skip 的实际取值跨度**，
// 不取决于 0..127 这个名义范围。所以把「窗口」做成参数：
//
//   SKIP_BASE  : skip 的最小值       SKIP_RANGE : skip 的取值个数（跨度 + 1）
//
// 于是 skip = SKIP_BASE + rel，rel ∈ [0, SKIP_RANGE)，移位拆成两段：
//
//   1) 常数 SKIP_BASE 字节的移位 —— **纯连线**（只是换一个位切片），零逻辑、零走线增量；
//   2) rel 字节的桶形移位 —— 位宽 ceil(log2(SKIP_RANGE))，在切片后的 SLICE_W 位上做。
//
// TX 实例：skip = 128 − header_length，而 header_length 只有 54/58/62/66/70/74 六种
// （BTH 4 + Eth 14 + IPv4 12 + UDP 8 = 54，扩展头 4/8/12/16/20），所以 skip ∈ 54..74，
// 跨度 21 而不是 128 → 移位量 5 位而不是 7 位、切片 1192 位而不是 2048 位。
// 常数量 54 B 那一级从「一级 2:1 选择」变成「改一根线」。
//
// RX 实例用默认值（SKIP_BASE=0、SKIP_RANGE=BEAT_BYTES），行为与参数化之前**逐位等价**：
// 切片就是整个 2*DW，移位量仍是 SHIFT_W 位。窗口外的 skip（< SKIP_BASE 或 >= SKIP_BASE+RANGE）
// 是**上游违约**，这里不做硬件夹位（会引入比较器与选择，且掩盖 bug）——TX 侧的取值域由
// roce_tx 的 header_aligned case 穷举保证，RX 侧用默认全窗口。
`default_nettype none
`timescale 1ns/1ps
module roce_skip_align #(
    parameter int DW = 512,                 // 数据位宽：512、1024 或 2048
    parameter int SKIP_BASE  = 0,           // skip 的最小值（常数移位量，纯连线）
    parameter int SKIP_RANGE = DW / 8,      // skip 的取值个数；默认 = 一拍字节数（全窗口）
    parameter int SKIP_W     = (DW >= 2048) ? $clog2(DW / 8) : 7   // meta_skip 位宽
)(
    input  wire              clk,
    input  wire              rst,
    input  wire              meta_valid,
    output wire              meta_ready,
    input  wire  [SKIP_W-1:0] meta_skip,     // 0..2^SKIP_W-1
    input  wire  [12:0]      meta_length,       // 1..4096
    input  wire              in_valid,
    output wire              in_ready,
    output wire              data_ready,    // 本拍没有元数据时的 in_ready（见下方 assign）
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
    localparam int SHIFT_W    = $clog2(BEAT_BYTES); // 6 或 7（名义取值范围）
    localparam int BYTE_W     = $clog2(BEAT_BYTES + 1);  // 7 或 8，可表示 0..BEAT_BYTES
    localparam [12:0] BEAT_BYTES_V = 13'(BEAT_BYTES);
    // ---- 移位窗口（见文件头）：常数段 SKIP_BASE 字节 + 相对段 rel ∈ [0, SKIP_RANGE)
    localparam int REL_W   = (SKIP_RANGE <= 1) ? 1 : $clog2(SKIP_RANGE);   // 移位量位宽
    // 切片位宽：输出 DW 位 + 最大相对移位。多留一个字节，保证 rel 取满时
    // 末字节的 8 位仍落在切片内（严格值 DW+8*(SKIP_RANGE-1) 也可，但逐位等价要
    // 依赖「顶层那几位永远读不到」这个推理；这里直接留富余，代价是 1 字节连线）。
    localparam int SLICE_W = DW + 8 * SKIP_RANGE;
    localparam int BASE_BIT = SKIP_BASE * 8;             // 常数段对应的位偏移

    // ---- 窗口参数自检（elaboration 期）：窗口外没有语义，越界的 skip 会静默错帧
    // 两种失效形态：
    //   skip < SKIP_BASE      → meta_rel_shift 回绕成很大的值，rel 截断后得到一个**无关的**移位量；
    //   skip >= SKIP_BASE+RANGE → rel 超范围，切片高位不够，末尾字节取到 0。
    // 两者都不报错、只把帧内容整体错位。因此实例参数的取值域必须覆盖调用方能产生的全部 skip。
    // TX 实例（SKIP_BASE=54, SKIP_RANGE=21）覆盖 header_length {54,58,62,66,70,74} →
    // skip {74,70,66,62,58,54}，恰好顶满窗口两端（零余量）。**roce_tx 的 header_length case
    // 若新增更大的扩展头，必须同时放大 SKIP_RANGE，否则这里会在编译期报错——这是故意的。**
    // 综合目标下 initial 不综合、Quartus 只在分析期求值，与 roce_tbl 的 $fatal 用法一致。
    initial begin
        if (SKIP_BASE < 0 || SKIP_RANGE < 1 || (SKIP_BASE + SKIP_RANGE) > BEAT_BYTES)
            $fatal(1, "roce_skip_align: 窗口 [%0d, %0d) 超出拍字节数 %0d",
                   SKIP_BASE, SKIP_BASE + SKIP_RANGE, BEAT_BYTES);
        if (BASE_BIT + SLICE_W > 2 * DW)
            $fatal(1, "roce_skip_align: 切片 BASE_BIT=%0d + SLICE_W=%0d 超出 2*DW=%0d",
                   BASE_BIT, SLICE_W, 2 * DW);
    end

    reg          frame_active;
    reg  [6:0]   beat_index;          // 当前输入拍序号（饱和）
    reg          first_useful_beat;         // 首个有用拍 = skip/BEAT_BYTES，DW=1024 时恒 0
    reg  [REL_W-1:0]   rel_shift;       // 相对移位 = skip - SKIP_BASE（桶形移位的实际控制量）
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
    // meta_skip / SHIFT_W：DW=1024 时恒 0（skip 恒 < 128），保留原判据以便 DW=512 复用。
    wire         first_is_useful = ((meta_skip >> SHIFT_W) != '0) ? 1'b0 : (meta_length != 13'd0);
    // 相对移位量 = skip − SKIP_BASE。窗口外的 skip 会在这里回绕（上游违约，见文件头）；
    // 它是**常数 SKIP_BASE 的减法**，在 meta_load 那拍算好寄存，不在数据通路上。
    wire [SKIP_W-1:0] meta_rel_shift = meta_skip - SKIP_W'(SKIP_BASE);

    // meta_slot 为 1 的那些拍 in_ready 恒为 1，两者绑在一起，不会有半拍握手。
    // 反过来：老帧正在收尾但本拍没有元数据时，in_ready 必须是 0——那些拍数据是收不下的
    // （consume_beat 要求 !input_done），拉高会让上游以为首拍已被接受而把它丢掉。
    assign in_ready = meta_slot ? meta_valid : (frame_active && !input_done && can_advance);
    assign meta_ready = meta_slot;
    // meta_valid = 0 时的 in_ready。上游在只送数据、不可能同时送元数据的阶段（TX 的 payload 拍）
    // 用它代替 in_ready，逐拍取值相同，但组合锥里不再有 meta_valid 及其上游逻辑。
    assign data_ready = !meta_slot && frame_active && !input_done && can_advance;

    function automatic [BEAT_BYTES-1:0] low_bits_mask(input [BYTE_W-1:0] count);
        // 注意：常数 1 必须显式扩到 BEAT_BYTES 位，否则 +1 之后被截成 32 位，
        // count 接近 BEAT_BYTES 时移位结果会丢高位。
        low_bits_mask = (count >= BYTE_W'(BEAT_BYTES)) ? {BEAT_BYTES{1'b1}}
                                                       : (({{(BEAT_BYTES-1){1'b0}}, 1'b1} << count) - 1);
    endfunction

    // ---- 移位两级：拼接 → 常数段切片（纯连线）→ rel 桶形移位
    // 语义等价于原来的 (concat >> (SKIP_BASE+rel)*8)：
    //   concat[SKIP_BASE*8 + i + rel*8]  ===  (concat >> SKIP_BASE*8)[i + rel*8]
    // 切片起点 = SKIP_BASE*8，宽度 = DW + 8*SKIP_RANGE。
    //
    // 为什么**不**手写 radix-4 级：B6501 的实测路径（sta.rpt Path #1）显示 7 位移位
    // 已被 Quartus 打成 4 级（LUT6 每级做 4 选 1），与手写的 ceil(7/2)=4 级相同，
    // 没有手工空间；真正的收益来自**缩小移位量位宽**（7 → 5 位）与**缩小操作数**
    // （2048 → 1192 位，扇出与走线一起降）。手写级联只是把同一张网表换个写法，
    // 却多出 3 份 DW 宽的中间副本（面积↑）。所以这里保留 `>>`，只换窗口。
    //
    // 默认参数（SKIP_BASE=0、SKIP_RANGE=BEAT_BYTES）下 SLICE_W = DW + DW = 2*DW，
    // 切片就是整个拼接向量、rel 就是 skip 本身 —— 与参数化之前**同一张网表**。
    // TX 实例 BASE_BIT=432、SLICE_W=1192。
    function automatic [DW-1:0] shift_window(input [2*DW-1:0] value, input [REL_W-1:0] rel);
        reg [SLICE_W-1:0] slice;
        begin
            slice = value[BASE_BIT +: SLICE_W];       // 常数段：纯位选，零逻辑
            shift_window = DW'(slice >> {rel, 3'b000});  // 相对段：REL_W 位桶形移位
        end
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
                out_data  <= shift_window({{DW{1'b0}}, previous_beat}, rel_shift);
                out_keep  <= low_bits_mask(output_bytes[BYTE_W-1:0]);
                out_last  <= 1'b1;
                bytes_remaining     <= 13'd0;
            end else if (consume_beat) begin
                if (beat_index != 7'h7f) beat_index <= beat_index + 7'd1;
                if (beat_is_useful) begin
                    previous_beat      <= in_data;
                    have_previous_beat <= 1'b1;
                    if (have_previous_beat) begin
                        out_data  <= shift_window({in_data, previous_beat}, rel_shift);
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
                first_useful_beat  <= (meta_skip >> SHIFT_W) != '0;
                // 桶形移位的控制量：只要 rel 位（SKIP_BASE 那一段已经是切片，不再参与运算）。
                rel_shift          <= meta_rel_shift[REL_W-1:0];
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
