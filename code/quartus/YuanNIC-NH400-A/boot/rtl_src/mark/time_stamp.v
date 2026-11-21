`timescale 1ns / 1ps
module time_stamp #(parameter FREQ=100000000)(
    input clk_r,
    input clk1,
    input clk2,
    input clk3,
    input clk4,
    input clk5,
    input rst_n,
    input gtime_set,
    input  [63:0]   gtime_value,
    output [63:0]   time_stamp_clk1,
    output [63:0]   time_stamp_clk2,
    output [63:0]   time_stamp_clk3,
    output [63:0]   time_stamp_clk4,
    output [63:0]   time_stamp_clk5);

    reg [63:0] count = 0;
    
    always @(posedge clk_r) begin
        //if(!rst_n) begin
        //    count <= 64'd0;
        //end else 
	if(gtime_set) begin
            count <= gtime_value;
        end else begin
            count <= count + 4; // 8ns for 125M
        end
    end

    sync_gray #(
        .N(64)
    ) sync_gray_0 (
        .clk_a(clk_r),
        .count_a(count),
        .clk_b(clk1),
        .count_b(time_stamp_clk1)
    );
    sync_gray #(
        .N(64)
    ) sync_gray_1 (
        .clk_a(clk_r),
        .count_a(count),
        .clk_b(clk2),
        .count_b(time_stamp_clk2)
    );
    
    sync_gray #(
        .N(64)
    ) sync_gray_2 (
        .clk_a(clk_r),
        .count_a(count),
        .clk_b(clk3),
        .count_b(time_stamp_clk3)
    );
    
    sync_gray #(
        .N(64)
    ) sync_gray_3 (
        .clk_a(clk_r),
        .count_a(count),
        .clk_b(clk4),
        .count_b(time_stamp_clk4)
    );
    
    sync_gray #(
        .N(64)
    ) sync_gray_4 (
        .clk_a(clk_r),
        .count_a(count),
        .clk_b(clk5),
        .count_b(time_stamp_clk5)
    );
endmodule

module sync_gray #(parameter N=8) (
    input  wire clk_a,
    input  wire [N-1:0] count_a,  
    input  wire clk_b,
    output reg [N-1:0] count_b );

    function [N-1:0] bin2gray;
        input [N-1:0] bin;
        begin
            bin2gray = bin ^ (bin >> 1);
        end
    endfunction

    function [N-1:0] gray2bin;
        input [N-1:0] gray;
        reg [N-1:0] bin;
        integer i;
        begin
            bin[N-1] = gray[N-1];
            for (i = N-2; i >= 0; i = i-1)
                bin[i] = bin[i+1] ^ gray[i];
            gray2bin = bin;
        end
    endfunction
    
    reg [N-1:0] gray_a, sync_b1, sync_b2;
    always @(posedge clk_a) begin
        gray_a <= bin2gray(count_a);
    end
    always @(posedge clk_b) begin
        sync_b1 <= gray_a;
        sync_b2 <= sync_b1;
    end
    always @(posedge clk_b) begin
        count_b <= gray2bin(sync_b2);
    end
     
endmodule
