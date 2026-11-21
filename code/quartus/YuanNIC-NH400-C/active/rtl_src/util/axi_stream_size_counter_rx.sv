`timescale 1ns/1ps
module axi_stream_size_counter_rx #(
    parameter  int TDATA_W = 512,
    localparam int C_MTY_W = $clog2(TDATA_W / 8)
) (
    input                               p_axis_tvalid,
    input           [C_MTY_W-1:0]       p_axis_tkeep,
    input                               p_axis_tlast,
    input                               p_axis_tready,
    output  reg                         size_valid,
    output  reg     [15:0]              size,
    input                               aclk,
    input                               aresetn
);

    localparam C_SIZE = 1 << C_MTY_W;

    reg     [15:0]      acc;
    always @(posedge aclk) begin
        if (~aresetn)
            acc <= 0;
        else if (p_axis_tvalid && p_axis_tready & p_axis_tlast)
            acc <= 0 ;
        else if (p_axis_tvalid && p_axis_tready)
            acc <= acc + C_SIZE;
    end

    always @(posedge aclk) begin
        if (p_axis_tvalid && p_axis_tlast && p_axis_tready)
            size_valid <= 1'b1;
        else
            size_valid <= 1'b0;
    end

    always @(posedge aclk) begin
        if (p_axis_tkeep == 0) 
            size <= acc + C_SIZE;
        else 
            size <= acc + p_axis_tkeep;
    end

endmodule: axi_stream_size_counter_rx
