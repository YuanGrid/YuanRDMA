`resetall
`default_nettype none
`timescale 1ns / 1ps
module reset_cdc #(parameter N=2)
    (
        input wire s_clk,
        input wire rst_n,
        input wire d_clk,
        output wire m_rst_n
    );

    reg reg_rst_n = 1'b0;
    always@(posedge s_clk )
        begin
            reg_rst_n <= rst_n;
        end

    reg [N-1:0] r_cdc = {N{1'b0}};
    always@(posedge d_clk or negedge reg_rst_n)
        begin
            if(~reg_rst_n)
                r_cdc <= {N{1'b0}};
            else
                r_cdc <= {r_cdc[N-2:0],1'b1};
        end
    assign m_rst_n = r_cdc[N-1];

endmodule
`resetall
