`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/07/10 17:17:57
// Design Name: 
// Module Name: match_adapter
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module match_comparer(

input       [ 15:0]     data            ,
output  reg             result          ,

input                   en              ,
input       [ 15:0]     condition       ,

input                   clk             ,   //
input                   resetn              //valid: low
);

always @(posedge clk)
begin
    if (!resetn)
        begin
            result <= 1'b0;
        end
    else if (!en)
        begin
            result <= 1'b1;
        end
    else
        begin
            result <= (data == condition) ? 1'b1 : 1'b0;
        end
end


endmodule
