`timescale 1ns / 1ps
// clk = 250MHz

module clkena_gen(
    input clk,
    input rst_n,
    output reg us_ena,
    output reg ms_ena,
    output reg s_ena);
    
    reg [1:0] resetn;
    always@(posedge clk or negedge rst_n)
    begin
        if(!rst_n)
            resetn <= 2'b00;
        else 
            resetn <= {resetn[0],1'b1};
    end
  
    reg [7:0] time1us_cnt;
    reg [9:0] time1ms_cnt;
    reg [9:0] time1s_cnt;
        
    wire us_ena_c = time1us_cnt==8'd249;
    wire ms_ena_c = time1ms_cnt==10'd999 && us_ena_c;
    wire s_ena_c  = time1s_cnt ==10'd999 && ms_ena_c;
    always@(posedge clk)
    begin
        us_ena <= us_ena_c;
        ms_ena <= ms_ena_c;
        s_ena  <= s_ena_c;
    end
        
    always@(posedge clk)
    begin
        if(~resetn[1])
            time1us_cnt <= 8'd0;
        else if(time1us_cnt >= 8'd249)
            time1us_cnt <= 8'd0;
        else
            time1us_cnt <= time1us_cnt + 1'b1;
    end
    
    always@(posedge clk)
    begin
        if(~resetn[1])
            time1ms_cnt <= 10'd0;
        else if( (time1ms_cnt >= 10'd999) && us_ena_c)
            time1ms_cnt <= 10'd0;
        else if(us_ena_c)
            time1ms_cnt <= time1ms_cnt + 1'b1;
    end
    
    always@(posedge clk)
    begin
        if(~resetn[1])
            time1s_cnt <= 10'd0;
        else if( (time1s_cnt >= 10'd999) && ms_ena_c)
            time1s_cnt <= 10'd0;
        else if(ms_ena_c)
            time1s_cnt <= time1s_cnt + 1'b1;
    end
    
endmodule