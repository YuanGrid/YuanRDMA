//-----------------------------------------------------------------------------
// Title         : pkt_tg
// Project       : 
//-----------------------------------------------------------------------------
// File          : pkt_tg.v
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

module pkt_tg (/*AUTOARG*/
   // Outputs
   tx_mac_data, tx_mac_valid, tx_mac_inframe, tx_mac_eop_empty,
   tx_mac_error, tx_mac_skip_crc,
   // Inputs
   rst, clk, tx_mac_ready, rx_mac_data, rx_mac_valid, rx_mac_inframe,
   rx_mac_eop_empty, rx_mac_error, rx_mac_fcs_error, rx_mac_status
   ) ;
   input  wire             rst;
   input  wire 			   clk;

   output reg [1023:0] 	   tx_mac_data        ;
   output reg 			   tx_mac_valid       ;
   output reg [15:0] 	   tx_mac_inframe     ;
   output reg [47:0] 	   tx_mac_eop_empty   ;
   input  wire 			   tx_mac_ready       ;
   output reg [15:0] 	   tx_mac_error       ;
   output reg [15:0] 	   tx_mac_skip_crc    ;
   
   input wire [1023:0] 	   rx_mac_data        ;
   input wire 			   rx_mac_valid       ;
   input wire [15:0] 	   rx_mac_inframe     ;
   input wire [47:0] 	   rx_mac_eop_empty   ;
   input wire [31:0] 	   rx_mac_error       ;
   input wire [15:0] 	   rx_mac_fcs_error   ;
   input wire [47:0] 	   rx_mac_status      ;

   always @ ( posedge clk ) begin
	  tx_mac_data <= rx_mac_data;
	  tx_mac_valid <= rx_mac_valid & tx_mac_ready;
	  tx_mac_inframe <= rx_mac_inframe;
	  tx_mac_eop_empty <= rx_mac_eop_empty;
	  tx_mac_error     <= 'd0;
	  tx_mac_skip_crc <= 'd0;
   end
   
endmodule // pkt_tg
