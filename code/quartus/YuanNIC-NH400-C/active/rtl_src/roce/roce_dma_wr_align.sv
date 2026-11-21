// roce_dma_wr_align.sv
// BAS 写数据整形：把从第 0 字节开始的 1024 bit 流（tlast 结束），按 addr[6:0] 移位，
// 拼成 128 B 对齐的 1024 bit 写拍并生成 wstrb。请求跨页时由 roce_dma 拆成两个 burst，
// request_first_burst_beats 为第一个 burst 的拍数（0 表示不跨页），在该拍也输出 write_last。
//
// 1024 bit 版本（B6386）：输入一拍 128 B、输出一拍 128 B，输入输出同宽，一拍一段。
// 旧版输入 512 bit，要把两个 64 B 半拍锁存进 low_half_data 才凑得出一条 1024 bit 写拍，
// take_input 每两拍才拉高一次，是 RX 写回 PCIe 的限速点（2 拍/128 B）。
//
// 记 start_offset = addr[6:0] = 128*f + s。第 i 个输出拍对应输入字节 [128(i-f)-s, +128)，
// 即 {第 j 拍, 第 j-1 拍} 右移 (128-s) 字节（j = i-f，第 -1 拍视为 0）。s==0 时
// 右移 128 字节就是第 j 拍本身——但右移 128 在 1024 位输出上恒为 0，所以 s==0 单独旁路。
// 最后一个输出拍可能不够 128 字节，用 wstrb 截断。
`default_nettype none
`timescale 1ns/1ps
module roce_dma_wr_align (
    input  wire               clk,
    input  wire               rst,
    // 请求
    input  wire               request_valid,
    output wire               request_ready,
    input  wire  [6:0]        request_address_low,
    input  wire  [12:0]       request_length,        // 1..4096
    input  wire  [5:0]        request_first_burst_beats,
    // 输入数据（每请求 ceil(transfer_length/128) 拍）
    input  wire               write_data_in_valid,
    output wire               write_data_in_ready,
    input  wire  [1023:0]     write_data_in,
    // 输出写拍
    output reg                write_valid,
    input  wire               write_ready,
    output reg   [1023:0]     write_data,
    output reg   [127:0]      write_strobe,
    output reg                write_last
);
    localparam int BEAT_BYTES = 128;
    localparam int SHIFT_W    = 7;
    localparam int BYTE_W     = 8;
    // 右移量 1..128；128 表示"输出全 0"（s==0 时不会用到，见上面的旁路）
    localparam int RSHIFT_W   = 8;

    reg           request_active;
    reg  [6:0]    beat_index, beat_count;
    reg  [RSHIFT_W-1:0] right_shift_bytes;
    reg  [13:0]   start_offset, end_offset;       // 有效字节区间 [start_offset, end_offset)
    reg  [6:0]    beats_needed;         // 还需读入的输入拍数
    reg  [5:0]    first_burst_beats;
    reg  [1023:0] previous_beat;

    wire          can_advance = !write_valid || write_ready;
    wire [13:0]   beat_byte_offset     = {beat_index, 7'd0};
    wire          beat_is_useful = (beat_byte_offset + 14'd128 > start_offset) && (beat_byte_offset < end_offset);
    wire          wants_input   = beat_is_useful && (beats_needed != 7'd0);
    wire          input_stall   = wants_input && !write_data_in_valid;
    wire          produce_beat  = request_active && can_advance && (beat_index < beat_count) && !input_stall;
    wire          take_input    = produce_beat && wants_input;

    wire [1023:0] current_beat = wants_input ? write_data_in : 1024'd0;
    // s==0 时右移 128 字节不合法（2048 位右移 1024 位正好把上一拍清零，结果就是 current_beat），
    // 直接旁路掉，避免综合出一个 2^8 项的桶形移位器。
    wire [1023:0] shifted_beat = (right_shift_bytes == RSHIFT_W'(128))
                               ? current_beat
                               : 1024'({current_beat, previous_beat} >> {right_shift_bytes[6:0], 3'b000});
    wire [1023:0] beat_data = beat_is_useful ? shifted_beat : 1024'd0;

    function automatic [127:0] low_bits_mask(input [13:0] count);
        low_bits_mask = (count >= 14'd128) ? {128{1'b1}}
                                           : ((128'd1 << count) - 128'd1);
    endfunction
    wire [13:0]   strobe_low  = (start_offset > beat_byte_offset) ? (start_offset - beat_byte_offset) : 14'd0;
    wire [13:0]   strobe_high = (end_offset > beat_byte_offset) ? (end_offset - beat_byte_offset) : 14'd0;
    wire [127:0]  beat_strobe = low_bits_mask(strobe_high) & ~low_bits_mask(strobe_low);

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
                if (request_valid) begin
                    request_active    <= 1'b1;
                    beat_index        <= 7'd0;
                    // B6393：零长度时 end_offset 可为 0，ceil 结果为 0 会让 produce_beat
                    // （beat_index < beat_count）恒假 → request_active 永不清 → request_ready
                    // 恒 0，把这条写客户端与同引擎的读客户端一起堵死。钳到 1 拍：退化成
                    // 一拍全 0 strobe 的合法 AXI 写，对长度 ≥1 是等价变换。
                    beat_count        <= (((request_end_offset + 14'd127) >> 7) == 14'd0) ? 7'd1
                                                                          : 7'((request_end_offset + 14'd127) >> 7);
                    right_shift_bytes <= RSHIFT_W'(128) - {1'b0, request_address_low};
                    start_offset      <= {7'd0, request_address_low};
                    end_offset        <= request_end_offset;
                    beats_needed      <= 7'((request_length + 13'd127) >> 7);
                    first_burst_beats <= request_first_burst_beats;
                    previous_beat     <= 1024'd0;
                end
            end else if (produce_beat) begin
                beat_index <= beat_index + 7'd1;
                if (take_input) begin
                    previous_beat <= write_data_in;
                    beats_needed  <= beats_needed - 7'd1;
                end
                write_valid  <= 1'b1;
                write_data   <= beat_data;
                write_strobe <= beat_strobe;
                // 跨页时第一个 burst 的最后一拍也要打 write_last：
                // first_burst_beats 现在直接就是 128 B 拍数，不用再像旧版那样 *2。
                write_last   <= (beat_index + 7'd1 == beat_count) ||
                                ((first_burst_beats != 6'd0) && (beat_index + 7'd1 == {1'b0, first_burst_beats}));
                if (beat_index + 7'd1 == beat_count)
                    request_active <= 1'b0;
            end
        end
    end
endmodule
`default_nettype wire
