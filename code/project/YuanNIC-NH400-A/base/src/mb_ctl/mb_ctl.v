//-----------------------------------------------------------------------------
// Title         : mb_ctl.v
// Project       : MA_A3
// Description :
// 
// Modification history :
// 12.06.2024 : created
//-----------------------------------------------------------------------------

`include "../top/define.vh"

module mb_ctl (
			   input  wire             rst              ,
			   input  wire 			   clk              ,
			   
			   input  wire 			   mb_ctl_req       ,
			   input  wire 			   mb_ctl_rwn       ,
			   input  wire [31:0] 	   mb_ctl_addr      ,
			   input  wire [31:0] 	   mb_ctl_wdat      ,
			   input  wire [3:0]	   mb_ctl_byte		,
			   output  reg [31:0] 	   mb_ctl_rdat      ,
			   output  reg             mb_ctl_ack       ,
			   
			   output  reg 			   mb_ctl_irq       ,
			   
			   output  reg [31:0] 	   sdm_mb_addr      ,
			   output  reg [31:0] 	   sdm_mb_wdat      ,
			   output  reg 			   sdm_mb_write     ,
			   output  reg 			   sdm_mb_read      ,
			   output  reg [3:0]	   sdm_mb_byte		,
			   input  wire [31:0] 	   sdm_mb_rdat      ,
			   input  wire 			   sdm_mb_rvld      ,
			   input  wire 			   sdm_mb_wait_req  ,
			   input  wire 			   sdm_mb_irq       
			   );

   reg	mb_ctl_req_d1;
   reg	mb_ctl_req_d2;
   wire mb_ctl_req_pd;
   
   always @(posedge clk)
   begin
		mb_ctl_req_d1 <= mb_ctl_req;
		mb_ctl_req_d2 <= mb_ctl_req_d1;
   end	
		
   assign mb_ctl_req_pd = mb_ctl_req_d1 && (~mb_ctl_req_d2);
	
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
		  if(mb_ctl_req_pd == 1'b1)
			nxt_stat <= WORK;
		  else
			nxt_stat <= IDLE;

		WORK:
		  if(sdm_mb_wait_req == 1'b0)
			if(sdm_mb_read == 1'b1)  //read wait for rvld
			  nxt_stat <= RACK;
			else if(sdm_mb_write == 1'b1)  //write
			  nxt_stat <= IDLE;
			else
			  nxt_stat <= WORK;
		  else
			nxt_stat <= WORK;
		RACK:
		  if(sdm_mb_rvld == 1'b1)
			nxt_stat <= IDLE;
		  else
			nxt_stat <= RACK;
		
		default:nxt_stat <= IDLE;
	  endcase // case ()
   end // always @ ( * )

   always @ ( posedge clk ) begin
	  if(cur_stat == IDLE) begin
		sdm_mb_addr <= mb_ctl_addr;
		sdm_mb_wdat <= mb_ctl_wdat;
	  end
		
	  if((cur_stat == IDLE) && (nxt_stat == WORK)) begin
		 sdm_mb_read  <= mb_ctl_rwn;
		 sdm_mb_write <= (~mb_ctl_rwn);
	  end
	  else if((cur_stat == WORK)&&(nxt_stat == IDLE))
		 sdm_mb_write <= 1'b0;
	  else if((cur_stat == WORK)&&(nxt_stat == RACK))
	     sdm_mb_read <= 1'b0;

	  if((cur_stat == RACK) && (sdm_mb_rvld == 1'b1))
		mb_ctl_rdat <= sdm_mb_rdat;

	  if((cur_stat == WORK && nxt_stat == IDLE)
	   ||(cur_stat == RACK && nxt_stat == IDLE))
		mb_ctl_ack <= 1'b1;
	  else if(cur_stat == IDLE && nxt_stat == WORK)
		mb_ctl_ack <= 1'b0;
	  else;

	  mb_ctl_irq <= sdm_mb_irq;
	  sdm_mb_byte <= 4'hf;
   end
   
   
   
   
   

endmodule // mb_ctl
