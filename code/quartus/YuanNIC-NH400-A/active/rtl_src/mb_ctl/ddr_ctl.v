
`include "../top/global_define.vh"

module ddr_ctl (
			   input  wire             rst              ,
			   input  wire 			   clk              ,
			   
			   input  wire 			   ddr_ctl_req      ,
			   input  wire 			   ddr_ctl_rwn      ,
			   input  wire [31:0] 	   ddr_ctl_addr     ,
			   input  wire [127:0] 	   ddr_ctl_wdat     ,
			   input  wire [15:0]	   ddr_ctl_byte		,
			   output  reg [127:0] 	   ddr_ctl_rdat     ,
			   output  reg             ddr_ctl_ack      ,
			   
			   input   wire			   app_amm_ready	,
   			   output  reg 			   app_amm_write    ,
			   output  reg 			   app_amm_read     ,
			   output  reg [31:0] 	   app_amm_addr     ,
			   output  reg [127:0] 	   app_amm_wdat     ,
			   input  wire [127:0] 	   app_amm_rdat     ,
			   input  wire 			   app_amm_rvld     ,
   			   output  reg [15:0]	   app_amm_byte		,
			   output  reg [6:0]	   app_amm_bcnt

			   );

   reg	ddr_ctl_req_d1;
   reg	ddr_ctl_req_d2;
   wire ddr_ctl_req_pd;
   
   always @(posedge clk)
   begin
		ddr_ctl_req_d1 <= ddr_ctl_req;
		ddr_ctl_req_d2 <= ddr_ctl_req_d1;
   end	
		
   assign ddr_ctl_req_pd = ddr_ctl_req_d1 && (~ddr_ctl_req_d2);
	
   parameter IDLE = 2'b01;
   parameter WORK = 2'b10;
   parameter RACK = 2'b11;
   
   reg [3:0] 			   cur_stat;
   reg [3:0] 			   nxt_stat;

   always @ ( posedge clk, posedge rst ) begin
	  if(rst == 1'b1)
		cur_stat <= IDLE;
	  else
		cur_stat <= nxt_stat;
   end

   always @ ( * ) begin
	  case (cur_stat)
		IDLE:
		  if(ddr_ctl_req_pd == 1'b1)
			nxt_stat <= WORK;
		  else
			nxt_stat <= IDLE;

		WORK:
		  if(app_amm_ready == 1'b1)
			if(app_amm_read == 1'b1)  //read wait for rvld
			  nxt_stat <= RACK;
			else if(app_amm_write == 1'b1)  //write
			  nxt_stat <= IDLE;
			else
			  nxt_stat <= WORK;
		  else
			nxt_stat <= WORK;
		RACK:
		  if(app_amm_rvld == 1'b1)
			nxt_stat <= IDLE;
		  else
			nxt_stat <= RACK;
		
		default:nxt_stat <= IDLE;
	  endcase // case ()
   end // always @ ( * )

   always @ ( posedge clk ) begin
	  if(cur_stat == IDLE) begin
		app_amm_addr <= ddr_ctl_addr;
		app_amm_wdat <= ddr_ctl_wdat;
	  end
		
	  if((cur_stat == IDLE) && (nxt_stat == WORK)) begin
		 app_amm_read  <= ddr_ctl_rwn;
		 app_amm_write <= (~ddr_ctl_rwn);
	  end
	  else if((cur_stat == WORK)&&(nxt_stat == IDLE))
		 app_amm_write <= 1'b0;
	  else if((cur_stat == WORK)&&(nxt_stat == RACK))
	     app_amm_read <= 1'b0;

	  if((cur_stat == RACK) && (app_amm_rvld == 1'b1))
		ddr_ctl_rdat <= app_amm_rdat;

	  if((cur_stat == WORK && nxt_stat == IDLE)
	   ||(cur_stat == RACK && nxt_stat == IDLE))
		ddr_ctl_ack <= 1'b1;
	  else if(cur_stat == IDLE && nxt_stat == WORK)
		ddr_ctl_ack <= 1'b0;
	  else;

	  app_amm_byte <= 16'hffff;
	  app_amm_bcnt <= 7'h1;
   end
   
   
   
   
   

endmodule // ddr_ctl
