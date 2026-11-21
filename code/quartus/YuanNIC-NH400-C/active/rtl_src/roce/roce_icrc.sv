// roce_icrc.sv
// RoCEv2 ICRC 计算（IPv4、无 VLAN），输入为以太网帧（从目的 MAC 开始，第 0 字节在 [7:0]）。
// - 首拍：前 14 字节（以太网头）置 0，按 RoCEv2 规则把 TOS/TTL/IP 校验和/UDP 校验和/
//   BTH resv8a 置 0xFF。INIT 取 0x7535D075（规范 0xAE0BACAE 的位反转），使 14 个 0 字节
//   之后的 CRC 状态正好等于 "8 字节 0xFF" 之后的状态 0xDEBB20E3。
// - 末拍 keep 必须从第 0 字节连续；中间拍必须全满。
// - TX：输入不含 ICRC，icrc = 要追加的 4 字节（[7:0] 先发）。
// - RX：输入含 ICRC，ok = 1 表示校验通过（CRC 残值 0xDEBB20E3）。
// 结果在 last 拍之后固定 LATENCY 拍给出（out_valid 单拍）。
`default_nettype none
`timescale 1ns/1ps
module roce_icrc #(
    parameter int DW     = 512,
    parameter int N_PIPE = 3
)(
    input  wire              clk,
    input  wire              rst,
    input  wire              in_valid,
    input  wire  [DW-1:0]    in_data,
    input  wire  [DW/8-1:0]  in_keep,
    input  wire              in_first,
    input  wire              in_last,
    output wire              out_valid,
    output wire  [31:0]      out_icrc,
    output wire              out_icrc_ok
);
    localparam int KEEP_WIDTH = DW/8;

    // RoCEv2 掩码（字节偏移，IPv4 无 VLAN）
    function automatic [DW-1:0] mask_first_beat(input [DW-1:0] frame_data);
        reg [DW-1:0] masked;
        begin
            masked = frame_data;
            masked[0 +: 14*8]   = '0;          // 以太网头不参与
            masked[15*8 +: 8]   = 8'hFF;       // IPv4 TOS
            masked[22*8 +: 8]   = 8'hFF;       // TTL
            masked[24*8 +: 16]  = 16'hFFFF;    // IP header checksum
            masked[40*8 +: 16]  = 16'hFFFF;    // UDP checksum
            masked[46*8 +: 8]   = 8'hFF;       // BTH resv8a（FECN/BECN）
            mask_first_beat = masked;
        end
    endfunction

    wire [DW-1:0] masked_data = in_first ? mask_first_beat(in_data) : in_data;

    // crc_gen_byteEn 的约定：第 0 字节在最高位，byteEn[KEEP_WIDTH-1] 对应第 0 字节
    wire [DW-1:0] data_reversed;
    wire [KEEP_WIDTH-1:0] byte_enable_reversed;
    genvar byte_index;
    generate
        for (byte_index = 0; byte_index < KEEP_WIDTH; byte_index = byte_index + 1) begin : gen_reverse
            assign data_reversed[(KEEP_WIDTH-1-byte_index)*8 +: 8] = masked_data[byte_index*8 +: 8];
            assign byte_enable_reversed[KEEP_WIDTH-1-byte_index]          = in_keep[byte_index];
        end
    endgenerate

    wire [31:0] crc_value;
    crc_gen_byteEn #(
        .DWIDTH   (DW           ),
        .CRC_WIDTH(32           ),
        .PIPE_LVL (N_PIPE       ),
        .CRC_POLY (32'h04C11DB7 ),
        .INIT     (32'h7535D075 ),
        .XOR_OUT  (32'h00000000 ),
        .REFIN    (1'b1         ),
        .REFOUT   (1'b1         )
    ) u_crc (
        .clk        (clk        ),
        .rst        (rst        ),
        .din        (data_reversed    ),
        .byteEn     (byte_enable_reversed    ),
        .dlast      (in_valid & in_last),
        .flitEn     (in_valid    ),
        .crc_out    (crc_value    ),
        .crc_out_vld(out_valid    )
    );

    assign out_icrc = ~crc_value;
    assign out_icrc_ok   = (crc_value == 32'hDEBB20E3);
endmodule
`default_nettype wire
