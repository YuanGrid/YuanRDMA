//-----------------------------------------------------------------------------
// Title         : avmm_master_tg
// Project       : 
//-----------------------------------------------------------------------------
// File          : avmm_master_tg.v
// Author        :   <Administrator@DESKTOP-SKNAR7C>
// Created       : 12.06.2024
// Last modified : 12.06.2024
//-----------------------------------------------------------------------------
// Description :
// 
//-----------------------------------------------------------------------------
// Copyright (c) 2024 by  This model is the confidential and
// proprietary property of  and the possession or use of this
// file requires a written license from .
//------------------------------------------------------------------------------
// Modification history :
// 12.06.2024 : created
//-----------------------------------------------------------------------------

module avmm_master_tg (/*AUTOARG*/
   // Outputs
   avmm_cfg_addr, avmm_cfg_read, avmm_cfg_write, avmm_cfg_wdat,
   avmm_cfg_byte,
   // Inputs
   rst, clk, avmm_cfg_rdat, avmm_cfg_rvld, avmm_cfg_wait_req
   ) ;
   input  wire                     rst;
   input  wire 					   clk;

   output reg [23:0] 			   avmm_cfg_addr;
   output reg 					   avmm_cfg_read;
   output reg 					   avmm_cfg_write;
   output reg [31:0] 			   avmm_cfg_wdat;
   output reg [3:0] 			   avmm_cfg_byte;
   input  wire [31:0] 			   avmm_cfg_rdat;
   input  wire 					   avmm_cfg_rvld;
   input  wire 					   avmm_cfg_wait_req;

   reg [31:0] 					   cnt = 32'habcd_1234;
   reg 							   syn = 'd0;
   
   always @ ( posedge clk ) begin
	  syn <= ~syn;
	  
	  if(avmm_cfg_rvld == 1'b1)
		cnt <= {cnt[30:0],cnt[31]} ^ avmm_cfg_rdat;

	  avmm_cfg_wdat <= cnt ;
	  avmm_cfg_addr <= cnt[23:0] ^ avmm_cfg_rdat[31:8];

	  avmm_cfg_write <= syn & ~avmm_cfg_wait_req;
	  avmm_cfg_read <= ~syn & ~avmm_cfg_wait_req;

	  avmm_cfg_byte <= ~cnt[3:0];
   end
   
   
   
endmodule // avmm_master_tg
