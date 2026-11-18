//-----------------------------------------------------------------------------
// Title         : mb_ctl_tg
// Project       : 
//-----------------------------------------------------------------------------
// File          : mb_ctl_tg.v
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

`include "../top/define.vh"

module mb_ctl_tg (/*AUTOARG*/
   // Outputs
   mb_ctl_req, mb_ctl_rwn, mb_ctl_addr, mb_ctl_wdat,
   // Inputs
   rst, clk, mb_ctl_rdat, mb_ctl_clr, mb_ctl_irq
   ) ;
   input  wire                rst;
   input  wire 				  clk;

   output  reg 				  mb_ctl_req;
   output  reg 				  mb_ctl_rwn;
   output  reg [3:0] 		  mb_ctl_addr;
   output  reg [31:0] 		  mb_ctl_wdat;
   
   input  wire [31:0] 		  mb_ctl_rdat;
   input  wire 			      mb_ctl_clr;
   input  wire 			      mb_ctl_irq;

   reg [31:0] 				  cnt = 32'h1234_5678;

   always @ ( posedge clk ) begin
	  mb_ctl_wdat <= {cnt[30:0],cnt[31]} ^ mb_ctl_rdat;
	  mb_ctl_req  <= (mb_ctl_rdat == cnt);
	  mb_ctl_addr <= cnt[3:0];
	  mb_ctl_rwn  <= (cnt[11:8] == 4'h3) & mb_ctl_irq | mb_ctl_clr;
   end
   
endmodule // mb_ctl_tg

