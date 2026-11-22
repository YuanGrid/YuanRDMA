


 //`define SIMULATION 

module beat_time#(
        parameter   BEAT_100US_CNT                  = 16'd4999 ,// 50mhz下，延迟100us计数器参数  15'd4999,15'b10
        parameter   BEAT_1US_CNT                    = 16'd49   // 50mhz下，延迟1us计数器参数 15'd49   15'b1 
)(
    input   clk,        // 系统时钟输入
    input   locked,         // PLL被锁定会输出一个locked高电平信号

    output  reg beat_1us,
    output  reg beat_100us,
    output  reg beat_1ms,
    output  reg beat_1s
);


    reg         [15:0]      beat_1us_gen_cnt    = 16'b0 ;
    reg         [15:0]      beat_100us_gen_cnt  = 16'b0	;
    reg         [3:0]       beat_1ms_gen_cnt    = 4'b0	;
    reg         [9:0]       beat_1s_gen_cnt     = 10'b0	;
    
/*
 *cpld内部使用的各种时间计数器，包括1us,1ms,100us,1s
 */
always @( posedge clk ) 
begin 
    if ( locked == 1'b0 ) 
    begin
        beat_1us_gen_cnt <= 1'd0;
        beat_1us <= 1'b0 ;
        beat_100us_gen_cnt <= 1'd0;
        beat_100us <= 1'b0 ;
        beat_1ms_gen_cnt <= 1'd0;
        beat_1ms <= 1'b0 ;
        beat_1s_gen_cnt <= 1'd0;
        beat_1s <= 1'b0 ;
    end 
    else 
    begin
        if( beat_1us_gen_cnt ==  BEAT_1US_CNT )   // 产生一微秒脉冲
        begin
            beat_1us_gen_cnt <= 'd0;
            beat_1us <= 1'b1 ;		    
		end 
        else 
        begin
            beat_1us_gen_cnt <= beat_1us_gen_cnt + 1'd1;
            beat_1us <= 1'b0 ;				
		end

        if ( beat_100us_gen_cnt ==  BEAT_100US_CNT ) // 产生一百微秒脉冲
        begin
            beat_100us_gen_cnt <= 'd0;
            beat_100us <= 1'b1 ;
        end 
        else 
        begin
            beat_100us_gen_cnt <= beat_100us_gen_cnt + 1'd1;
            beat_100us <= 1'b0 ;
        end

        if (( beat_1ms_gen_cnt == 4'd9 )&&( beat_100us == 1'b1 ))   // 产生一毫秒脉冲
        begin
            beat_1ms_gen_cnt <= 'd0;
            beat_1ms <= 1'b1 ;
        end 
        else 
        begin
            beat_1ms_gen_cnt <= beat_1ms_gen_cnt + beat_100us;
            beat_1ms <= 1'b0 ;
        end

		
        if( ( beat_1s_gen_cnt == 10'd999) &&( beat_1ms == 1'b1 ))   // 产生一秒脉冲
        begin
            beat_1s_gen_cnt <= 'd0;
            beat_1s <= 1'b1 ;		    
		end 
        else 
        begin
            beat_1s_gen_cnt <= beat_1s_gen_cnt + beat_1ms;
            beat_1s <= 1'b0 ;				
		end
    end 
end

endmodule

