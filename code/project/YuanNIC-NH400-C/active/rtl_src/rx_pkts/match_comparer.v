`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/03/15 18:18:18
// Design Name: 
// Module Name: match_comparer
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

module match_comparer#(
    parameter DATA_WIDTH = 16
)
(
    input                           clk             ,
    input                           resetn          ,
    input                           field_valid     ,
    input       [DATA_WIDTH-1:0]    field_data      ,
    input                           field_relation  , //0:and, 1:or
    input                           match_en        ,
    input                           match_mode      , //0:equal, 1:not equal
    input       [DATA_WIDTH-1:0]    match_mask      ,
    input       [DATA_WIDTH-1:0]    match_value     ,
    output  reg                     match_result      //0:not match, 1:match
);

always @(posedge clk) begin
    if (!resetn) begin
        match_result <= 1'b0;
    end
    else if (!match_en) begin        
        if (field_relation) begin
            match_result <= 1'b0;
        end
        else begin
            match_result <= 1'b1;
        end
    end
    else begin
        if (match_mode) begin
            match_result <= (field_valid && ((field_data & match_mask) != (match_value & match_mask))) ? 1'b1 : 1'b0;
        end
        else begin
            match_result <= (field_valid && ((field_data & match_mask) == (match_value & match_mask))) ? 1'b1 : 1'b0;
        end
    end
end


endmodule
