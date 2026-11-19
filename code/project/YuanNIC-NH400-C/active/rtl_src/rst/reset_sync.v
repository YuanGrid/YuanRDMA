`include "../top/global_define.vh"

module      rst (
                    clk             ,
                    ex_reset_n      ,
                    mmcm_lock       ,
                    
                    soft_rst_val    ,
                    soft_rst_clr    ,

                    hard_rst        ,
                    sys_rst
                );

input   wire            clk             ;
input   wire            ex_reset_n      ;
input   wire            mmcm_lock       ;

input   wire    [7:0]   soft_rst_val    ;
output  reg             soft_rst_clr    ;

output   reg 		    hard_rst        ;
output  wire            sys_rst         ;

/**********************************************/
reg     [7:0]   soft_rst_cnt    ;
reg             soft_rst        ;
reg             soft_rst_dly    ;
wire            mmcm_lock_dly1  ;
wire            mmcm_lock_dly2  ;

   reg [31:0] 	mmcm_lock_d;

   always @ ( posedge clk ) begin
	  mmcm_lock_d <= {mmcm_lock_d[30:0],mmcm_lock};
   end

   assign mmcm_lock_dly2 = mmcm_lock_d[31];

/********************************************************************\
*                                                                    *
*               Hard reset generator                                 *
*                                                                    *
\********************************************************************/
wire            hard_rst_pre    ;
reg     [3:0]   hard_rst_cnt   = 4'd0 ;

assign hard_rst_pre = (~ex_reset_n) | (~mmcm_lock_dly2);

always @(posedge clk or posedge hard_rst_pre)
begin
    if(hard_rst_pre == 1'b1)
        hard_rst_cnt <= 4'h0;
    else
        if (hard_rst_cnt == 4'hf)
            hard_rst_cnt <= #`UDLY hard_rst_cnt;
        else
            hard_rst_cnt <= #`UDLY hard_rst_cnt + 4'h1;
end

always @(posedge clk or posedge hard_rst_pre)
begin
    if(hard_rst_pre == 1'b1)
        hard_rst <= 1'b1;
    else
        if (hard_rst_cnt == 4'hf)
            hard_rst <= #`UDLY 1'b0;
        else
          hard_rst <= #`UDLY 1'b1;
end

/********************************************************************\
*                                                                    *
*               Global reset generator                               *
*                                                                    *
\********************************************************************/

always @(posedge clk or posedge hard_rst)
begin
    if(hard_rst == 1'b1)
      soft_rst_cnt <= 8'h00;
    else
      if (soft_rst_val == 8'h5a)
        soft_rst_cnt <= #`UDLY soft_rst_cnt + 8'h01;
      else
        soft_rst_cnt <= #`UDLY 8'h00;
end

   always @(posedge clk or posedge hard_rst)
	 begin
		if(hard_rst == 1'b1)
          soft_rst <= 1'b0;
		else
          if (soft_rst_cnt[7] == 1'b1)
            soft_rst <= #`UDLY 1'b1;
          else
            soft_rst <= #`UDLY 1'b0;
	 end
   
   always @(posedge clk or posedge hard_rst)
	 begin
		if(hard_rst == 1'b1)
          soft_rst_clr <= 1'b0;
		else
          if (soft_rst_cnt[7:2] == 6'h3f) //(3f<<2-1f=dd)
            soft_rst_clr <= #`UDLY 1'b1;
          else
            soft_rst_clr <= #`UDLY 1'b0;
	 end
   
   always @(posedge clk or posedge hard_rst)
	 begin
		if(hard_rst == 1'b1)
        soft_rst_dly <= 1'b1;
    else
      soft_rst_dly <= #`UDLY soft_rst ;
	 end
   
reg sys_rst_reg;
   
   always @(posedge clk or posedge hard_rst)
	 begin
		if(hard_rst == 1'b1)
          sys_rst_reg <= 1'b1;
		else
          sys_rst_reg <= #`UDLY soft_rst_dly ;
	 end
   
   assign sys_rst = sys_rst_reg;

endmodule