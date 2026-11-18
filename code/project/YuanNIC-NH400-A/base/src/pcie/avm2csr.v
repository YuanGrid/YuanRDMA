//-----------------------------------------------------------------------------
// Title         : avm2csr.v
// Project       : NSA.A3
// Description :
// 
//-----------------------------------------------------------------------------
// Copyright (c) 2024 by www.smptian.com This model is the confidential and
// proprietary property of www.smptian.com and the possession or use of this
// file requires a written license from www.smptian.com.
//------------------------------------------------------------------------------
// Modification history :
// 14.06.2024 : created
//-----------------------------------------------------------------------------

`include "../top/define.vh"

module avm2csr (/*AUTOARG*/
   // Outputs
   avm_wait, avm_rdat, avm_rvld, avm_rspo, avm_wrsp, sir_sel,
   sir_read, sir_addr, sir_wdat,
   // Inputs
   rst, clk, avm_clk, avm_addr, avm_byte, avm_read, avm_write,
   avm_wdat, avm_bcnt, sir_rdat, sir_dack
   ) ;
   input  wire              rst;

   input  wire 				clk; //system clk
   
   input  wire 				avm_clk; //pcie usr clk 500M 

   input  wire [27:0] 		avm_addr;
   input  wire [7:0] 		avm_byte;
   input  wire 				avm_read;
   input  wire 				avm_write;
   input  wire [63:0] 		avm_wdat;
   input  wire [3:0] 		avm_bcnt; //支持burst_cnt为1
   output  reg 				avm_wait = 'b0;

   output  reg [63:0] 		avm_rdat;
   output  reg 				avm_rvld;
   output wire [1:0] 		avm_rspo;
   output  reg 				avm_wrsp; //write response valid

   output  reg 				sir_sel;
   output  reg 				sir_read;
   output  reg [31:0] 		sir_addr;//8 byte address
   output  reg [31:0] 		sir_wdat;
   input  wire [31:0] 		sir_rdat;
   input  wire 				sir_dack;

   assign avm_rspo = 2'b00;
   
   reg	[3:0]	offest;
   always @(*)
   begin
		case(avm_byte) 
			8'b00001111 : offest <= 4'h0; 
			8'b00011110 : offest <= 4'h1; 
			8'b00111100 : offest <= 4'h2; 
			8'b01111000 : offest <= 4'h3; 
			8'b11110000 : offest <= 4'h4; 
			8'b11100000 : offest <= 4'h5; 
			8'b11000000 : offest <= 4'h6; 
			8'b10000000 : offest <= 4'h7; 
		default			: offest <= 4'h0;
		endcase
   end
   
   parameter IDLE  = 5'b00001;
   parameter WRITE = 5'b00010;
   parameter READ  = 5'b00100;
   parameter DELAY = 5'b01000;
   parameter WAIT  = 5'b10000;

   reg [4:0] 				cur_stat;
   reg [4:0] 				nxt_stat;
   reg [9:0] 				wait_cnt;
   
   //跨时钟域 sir_dack sysclk to pcie_usr_clk 
   reg 						sir_dack_d1 = 'd0;
   reg 						sir_dack_d2 = 'd0;
   reg 						sir_dack_d3 = 'd0;
   
   reg [31:0] 				sir_rdat_d1 = 'd0;
   reg [31:0] 				sir_rdat_d2 = 'd0;

   reg 						time_out;

   always @ ( posedge avm_clk, posedge rst ) begin
	  if(rst == 1'b1)
		cur_stat <= IDLE;
	  else
		cur_stat <= nxt_stat;
   end

   always @ ( * ) begin
	  case (cur_stat)
		IDLE:
		  if(avm_write == 1'b1)
			nxt_stat <= WRITE;
		  else if(avm_read == 1'b1)
			nxt_stat <= READ;
		  else
			nxt_stat <= IDLE;

		WRITE:
		  if((time_out == 1'b1) || (sir_dack_d3 == 1'b1))
			nxt_stat <= DELAY;
		  else
			nxt_stat <= WRITE;
		

		READ:
		  if((time_out == 1'b1) || (sir_dack_d3 == 1'b1))
			nxt_stat <= DELAY;
		  else
			nxt_stat <= READ;
			
		DELAY: nxt_stat <= WAIT;	

		WAIT: //wait sir_bus to idle
		  if(sir_dack_d2 == 1'b0)
			nxt_stat <= IDLE;
		  else
			nxt_stat <= WAIT;
		
		default: nxt_stat <= IDLE;
		
	  endcase // case (cur_stat)
   end // always @ ( posedge clk )
   
   reg                      avm_wrsp_p = 'd0;
   
   always @ ( posedge avm_clk) begin
	  if(cur_stat == IDLE && nxt_stat != IDLE)
		avm_wait <= 1'b1;
	  else if(cur_stat == WAIT && nxt_stat == IDLE)
		avm_wait <= 1'b0;

	  if(cur_stat == READ && nxt_stat == DELAY)
		avm_rvld <= 1'b1;
	  else
		avm_rvld <= 1'b0;

	  if(cur_stat == READ && nxt_stat == DELAY)
		if(time_out == 1'b1)
		  avm_rdat <= {32'h0,32'hfffe_feff};
		else
		  avm_rdat <= {32'h0,sir_rdat_d2};

	  if(cur_stat == WRITE && nxt_stat == DELAY)
		avm_wrsp_p <= 1'b1;
	  else
		avm_wrsp_p <= 1'b0;

	  avm_wrsp <= avm_wrsp_p;
   end

   reg                         sir_sel_t  = 'd0;
   reg [31:0] 				   sir_wdat_t = 'd0;
   reg [31:0] 				   sir_addr_t = 'd0;
   reg 						   sir_read_t = 'd0;

   always @ ( posedge avm_clk ) begin
	  if(cur_stat == IDLE) begin
		 sir_wdat_t <= (avm_byte == 8'h0f) ? avm_wdat[31:0] : avm_wdat[63:32];
		 sir_addr_t <= {4'b0,avm_addr[27:0] + offest}; 
		 sir_read_t <= avm_read;
	  end
   end
   
   always @ ( posedge avm_clk ) begin
	  if(cur_stat == IDLE && nxt_stat != IDLE)
		sir_sel_t <= 1'b1;
	  else if(cur_stat != IDLE && nxt_stat == DELAY)
		sir_sel_t <= 1'b0;
   end

   always @ ( posedge avm_clk ) begin
	  if(cur_stat == IDLE)
		wait_cnt <= 10'd511;
	  else if(wait_cnt != 10'd0)
		wait_cnt <= wait_cnt - 1'b1;

	  time_out <= (wait_cnt == 10'd0);
   end

   always @ ( posedge avm_clk ) begin
	  sir_dack_d1 <= sir_dack;
	  sir_dack_d2 <= sir_dack_d1;
	  sir_dack_d3 <= sir_dack_d2;

	  sir_rdat_d1 <= sir_rdat;
	  sir_rdat_d2 <= sir_rdat_d1;
   end

   // sir bus cross pcie_usr_clk to sys_clk
   reg                       sir_sel_p  = 'd0;
   reg [31:0] 				 sir_wdat_p = 'd0;
   reg [31:0] 				 sir_addr_p = 'd0;
   reg 						 sir_read_p = 'd0;

   //sir_sel more delay
   reg 						 sir_sel_p2 = 'd0;
   
   always @ ( posedge clk ) begin
	  sir_sel_p  <= sir_sel_t;
	  sir_wdat_p <= sir_wdat_t;
	  sir_addr_p <= sir_addr_t;
	  sir_read_p <= sir_read_t;

	  sir_wdat   <= sir_wdat_p;
	  sir_addr   <= sir_addr_p;
	  sir_read   <= sir_read_p;

	  sir_sel_p2 <= sir_sel_p;
	  sir_sel    <= sir_sel_p2;
   end

endmodule // avm2csr
