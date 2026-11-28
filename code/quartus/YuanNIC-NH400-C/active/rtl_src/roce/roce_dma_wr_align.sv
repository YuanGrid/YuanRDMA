// roce_dma_wr_align.sv
// BAS 写数据整形：把从第 0 字节开始的 DW 位输入流，按 addr[6:0] 移位，
// 拼成以 128 B 对齐半拍为单位的写数据并生成 wstrb。请求跨页时由 roce_dma 拆成两个 burst，
// request_first_burst_beats 为第一个 burst 的 128 B 拍数（0 表示不跨页），在该拍也输出 write_last。
//
// 1024 bit 版本（B6386）：输入一拍 128 B、输出一拍 128 B，输入输出同宽，一拍一段。
// 旧版输入 512 bit，要把两个 64 B 半拍锁存进 low_half_data 才凑得出一条 1024 bit 写拍，
// take_input 每两拍才拉高一次，是 RX 写回 PCIe 的限速点（2 拍/128 B）。
//
// DW=2048：输入一拍 256 B、输出一拍 256 B（每个 core 拍吃 1 个输入拍）。输出拍由两个 128 B 半拍组成，
// 半拍 h 对应 BAS 的第 (2*beat_index + h) 个 W 拍；AW 仍按 128 B 拍生成（roce_dma 不变），
// 所以 burst 边界（头拍拆分、跨页）可能落在一个输出拍的中间：每个半拍各给一位 write_last，
// 请求总拍数为奇数时最后一个输出拍的高半拍不发（write_half_valid[1]=0）。pcie 域再拆回 1024 位。
//
// 记 s = addr[6:0]（AW 按 128 B 对齐，所以偏移粒度恒为 128 B，与 DW 无关）。第 k 个输出拍对应
// 输入字节 [BB*k - s, +BB)（BB = DW/8），即 {第 k 拍, 第 k-1 拍的高 128 B} 右移 (128-s) 字节
// （第 -1 拍视为 0；s < 128，所以上一拍只用得到高 128 B）。s==0 时右移 128 字节就是第 k 拍本身——
// 但右移量只取低 7 位时 128 变成 0，所以 s==0 单独旁路。DW=1024 时「上一拍的高 128 B」就是整拍，
// 与原来的写法逐位相同。最后一个输出拍可能不够 BB 字节，用 wstrb 截断。
`default_nettype none
`timescale 1ns/1ps
module roce_dma_wr_align #(
    parameter int DW = 1024                      // 输入/输出拍位宽：1024 或 2048
)(
    input  wire               clk,
    input  wire               rst,
    // 请求
    input  wire               request_valid,
    output wire               request_ready,
    input  wire  [6:0]        request_address_low,
    input  wire  [12:0]       request_length,        // 1..4096
    input  wire  [5:0]        request_first_burst_beats,
    input  wire               request_head_split,    // 首拍单独成 burst（见 roce_dma 的头拍拆分），该拍也打 write_last
    // 输入数据（每请求 ceil(transfer_length/(DW/8)) 拍）
    input  wire               write_data_in_valid,
    output wire               write_data_in_ready,
    input  wire  [DW-1:0]     write_data_in,
    // 输出写拍（每个 128 B 半拍一位 last / valid；DW=1024 时 write_half_valid 恒 1）
    output reg                write_valid,
    input  wire               write_ready,
    output reg   [DW-1:0]     write_data,
    output reg   [DW/8-1:0]   write_strobe,
    output reg   [DW/1024-1:0] write_last,
    output reg   [DW/1024-1:0] write_half_valid
);
    localparam int H          = DW / 1024;       // 每个输出拍的 128 B 半拍数：1 / 2
    localparam int BB         = DW / 8;          // 每拍字节数：128 / 256
    localparam int LB         = $clog2(BB);      // 7 / 8
    // 右移量 1..128；128 表示"输出就是当前拍"（s==0，走旁路）
    localparam int RSHIFT_W   = 8;

    reg           request_active;
    reg  [6:0]    beat_index, beat_count;        // 输出拍（DW 位）序号 / 本请求输出拍数
    reg  [6:0]    half_count;                    // 128 B 半拍总数（= 本请求各 AW 的拍数之和），只在 H=2 时用
    reg  [RSHIFT_W-1:0] right_shift_bytes;
    reg  [13:0]   start_offset, end_offset;       // 有效字节区间 [start_offset, end_offset)
    reg  [6:0]    beats_needed;         // 还需读入的输入拍数
    reg  [5:0]    first_burst_beats;
    reg           head_split;
    reg  [1023:0] previous_beat;        // 上一输入拍的高 128 B（DW=1024 时即整拍）

    wire          can_advance = !write_valid || write_ready;
    wire [13:0]   beat_byte_offset     = 14'(beat_index) << LB;
    wire          beat_is_useful = (beat_byte_offset + 14'(BB) > start_offset) && (beat_byte_offset < end_offset);
    wire          wants_input   = beat_is_useful && (beats_needed != 7'd0);
    wire          input_stall   = wants_input && !write_data_in_valid;
    wire          produce_beat  = request_active && can_advance && (beat_index < beat_count) && !input_stall;
    wire          take_input    = produce_beat && wants_input;

    wire [DW-1:0] current_beat = wants_input ? write_data_in : {DW{1'b0}};
    // s==0 时右移 128 字节不合法（右移量低 7 位为 0），而 {当前拍, 上一拍高 128 B} 右移 1024 位的结果正好
    // 就是 current_beat，直接旁路掉，避免综合出一个 2^8 项的桶形移位器。
    wire [DW-1:0] shifted_beat = (right_shift_bytes == RSHIFT_W'(128))
                               ? current_beat
                               : DW'({current_beat, previous_beat} >> {right_shift_bytes[6:0], 3'b000});
    wire [DW-1:0] beat_data = beat_is_useful ? shifted_beat : {DW{1'b0}};

    // 低 count 位为 1 的掩码（count ≥ BB 时全 1）。写成温度计码：第 i 位 = (count > i)，每位只是 count 与常数比较，
    // 位与位之间没有依赖。原来的 (1 << count) - 1 在 BB=256 时综合成 256 位借位链，B0122 core_clk 余量 0 的路径
    // （u_bresp_count_fifo → u_wr_align → write_strobe → u_w_fifo）就经过它。两种写法对 count = 0..16383 逐位相同
    // （test/sim/wr_align_equiv 穷举）。
    function automatic [BB-1:0] low_bits_mask(input [13:0] count);
        for (int i = 0; i < BB; i++)
            low_bits_mask[i] = (count > 14'(i));
    endfunction
    wire [13:0]   strobe_low  = (start_offset > beat_byte_offset) ? (start_offset - beat_byte_offset) : 14'd0;
    wire [13:0]   strobe_high = (end_offset > beat_byte_offset) ? (end_offset - beat_byte_offset) : 14'd0;
    wire [BB-1:0] beat_strobe = low_bits_mask(strobe_high) & ~low_bits_mask(strobe_low);

    // 每个半拍的 write_last / 是否要发。半拍全局序号 = beat_index*H + h，与 AW 的 128 B 拍一一对应。
    // 跨页时第一个 burst 的最后一拍也要打 write_last（first_burst_beats 是 128 B 拍数）；
    // 头拍拆分时第 0 拍单独成 burst。H=1 时 total_halves 就是 beat_count，与原来逐位相同。
    wire [6:0]    total_halves = (H == 1) ? beat_count : half_count;
    reg  [H-1:0]  beat_last, beat_half_valid;
    integer       half;
    always @* begin
        for (half = 0; half < H; half = half + 1) begin
            beat_last[half] = (7'(beat_index * H + half) + 7'd1 == total_halves) ||
                              ((first_burst_beats != 6'd0) && (7'(beat_index * H + half) + 7'd1 == {1'b0, first_burst_beats})) ||
                              (head_split && (7'(beat_index * H + half) == 7'd0));
            beat_half_valid[half] = 7'(beat_index * H + half) < total_halves;
        end
    end

    assign request_ready = !request_active;
    assign write_data_in_ready = take_input;

    wire [13:0] request_end_offset = {7'd0, request_address_low} + {1'b0, request_length};

    always @(posedge clk) begin
        if (rst) begin
            request_active <= 1'b0;
            write_valid    <= 1'b0;
        end else begin
            if (write_valid && write_ready)
                write_valid <= 1'b0;

            if (!request_active) begin
                // 空闲时请求字段每拍都跟着输入装载，装载使能只看本地的 request_active；request_valid
                // （roce_dma 的 write_request_start）只进 request_active 这一位（B0123 时序）。原来是
                // 「!request_active && request_valid」整体装载：write_request_start 由 roce_dma 的握手组合出来，
                // 要走长线去驱动一千多位寄存器的使能（扇出 45，B0122 core_clk 余量 0 的那簇路径）。
                // 空闲时这些字段没有任何读者（produce_beat 要求 request_active），request_valid 那拍装进来的
                // 正是被受理的请求，所以端口行为逐拍不变；每请求仍是「装载 1 拍 + 出拍」，不多空拍。
                request_active    <= request_valid;
                beat_index        <= 7'd0;
                // B6393：零长度时 end_offset 可为 0，ceil 结果为 0 会让 produce_beat
                // （beat_index < beat_count）恒假 → request_active 永不清 → request_ready
                // 恒 0，把这条写客户端与同引擎的读客户端一起堵死。钳到 1 拍：退化成
                // 一拍全 0 strobe 的合法 AXI 写，对长度 ≥1 是等价变换。
                beat_count        <= (((request_end_offset + 14'(BB - 1)) >> LB) == 14'd0) ? 7'd1
                                                                          : 7'((request_end_offset + 14'(BB - 1)) >> LB);
                half_count        <= (((request_end_offset + 14'd127) >> 7) == 14'd0) ? 7'd1
                                                                          : 7'((request_end_offset + 14'd127) >> 7);
                right_shift_bytes <= RSHIFT_W'(128) - {1'b0, request_address_low};
                start_offset      <= {7'd0, request_address_low};
                end_offset        <= request_end_offset;
                beats_needed      <= 7'((request_length + 13'(BB - 1)) >> LB);
                first_burst_beats <= request_first_burst_beats;
                head_split        <= request_head_split;
                previous_beat     <= 1024'd0;
            end else if (produce_beat) begin
                beat_index <= beat_index + 7'd1;
                if (take_input) begin
                    previous_beat <= write_data_in[DW-1 -: 1024];
                    beats_needed  <= beats_needed - 7'd1;
                end
                write_valid      <= 1'b1;
                write_data       <= beat_data;
                write_strobe     <= beat_strobe;
                write_last       <= beat_last;
                write_half_valid <= beat_half_valid;
                if (beat_index + 7'd1 == beat_count)
                    request_active <= 1'b0;
            end
        end
    end
endmodule
`default_nettype wire
