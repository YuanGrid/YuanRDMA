// roce_gray_cnt.sv
// 快时钟域事件计数（每拍最多 +1），格雷码跨到慢时钟域读出。用于 MAC 域的统计计数器。
`default_nettype none
`timescale 1ns/1ps
module roce_gray_cnt #(
    parameter int W = 32
)(
    input  wire          source_clk,
    input  wire          source_rst,
    input  wire          source_increment,
    input  wire          dest_clk,
    output reg  [W-1:0]  dest_count
);
    reg [W-1:0] binary_count, gray_count;
    always @(posedge source_clk) begin
        if (source_rst) begin
            binary_count  <= '0;
            gray_count <= '0;
        end else begin
            if (source_increment) binary_count <= binary_count + 1'b1;
            gray_count <= binary_count ^ (binary_count >> 1);
        end
    end

    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    reg [W-1:0] gray_sync1, gray_sync2;
    always @(posedge dest_clk) begin
        gray_sync1 <= gray_count;
        gray_sync2 <= gray_sync1;
    end

    integer bit_index;
    always @(posedge dest_clk) begin
        dest_count[W-1] <= gray_sync2[W-1];
        for (bit_index = W-2; bit_index >= 0; bit_index = bit_index - 1)
            dest_count[bit_index] <= gray_to_binary_bit(bit_index);
    end
    function automatic logic gray_to_binary_bit(input integer position);
        logic parity;
        parity = 1'b0;
        for (int higher = W-1; higher >= position; higher--) parity ^= gray_sync2[higher];
        return parity;
    endfunction
endmodule
`default_nettype wire
