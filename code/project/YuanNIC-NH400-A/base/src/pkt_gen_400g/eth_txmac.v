//-----------------------------------------------------------------------------
// Title         : eth_txmac.v
// Project       : NSA.A3
// Description :
// 
// Modification history :
// 17.06.2024 : created
//-----------------------------------------------------------------------------

`include "../top/define.v"

module eth_txmac (/*AUTOARG*/
   // Outputs
   tx_busy, tx_mac_valid, tx_mac_inframe, tx_mac_eop_empty,
   tx_mac_data, tx_mac_error, tx_mac_skip_crc,
   // Inputs
   rst, clk, tx_crc_err, tx_wenb, tx_wdat, tx_weop, tx_winf,
   tx_mac_ready
   ) ;
   input  wire                rst;
   input  wire 				  clk;

   input  wire 				  tx_crc_err;

   input  wire 				  tx_wenb;
   input  wire [1023:0] 	  tx_wdat;
   input  wire [47:0] 		  tx_weop;
   input  wire [15:0] 		  tx_winf;
   output reg 				  tx_busy;

   input  wire 				  tx_mac_ready;
   output  reg 				  tx_mac_valid;
   output  reg [15:0] 		  tx_mac_inframe;
   output  reg [48-1:0] 	  tx_mac_eop_empty;
   output  reg [16*64-1:0] 	  tx_mac_data;
   output wire [16-1:0] 	  tx_mac_error;
   output  reg [16-1:0] 	  tx_mac_skip_crc; //MAC������CRC����

   assign tx_mac_error = 16'd0;

   always @(posedge clk) begin
	  if(tx_crc_err == 1'b1) 
		tx_mac_skip_crc <= 16'hFFFF;
	  else
		tx_mac_skip_crc <= 16'h0000;
   end
   
   wire [1151:0] 			  pkt_wdat;
   wire [8:0] 				  pkt_wcnt;
   wire						  pkt_rden;
   wire [1151:0] 			  pkt_rdat;
   wire 					  pkt_empty;

   assign pkt_wdat = {64'd0,tx_winf[15:0],tx_weop[47:0],tx_wdat[1023:0]};


   always @ (posedge clk) tx_busy <= (pkt_wcnt >= 9'd384);

   
`ifdef XILINX_SIM
   fifo_sync_w1152d512_fwft
	 U_pktbuf(
			  .rst             (rst                ),
			  .clk             (clk                ),
			  .din             (pkt_wdat           ),
			  .wr_en           (tx_wenb            ),
			  .full            (                   ),
			  .almost_full     (                   ),
                                                   
			  .rd_en           (pkt_rden           ),
			  .dout            (pkt_rdat           ),
			  .empty           (pkt_empty          ),
			  .almost_empty    (                   ),
                                                   
			  .data_count      (pkt_wcnt           )
              );
   
`else
   fifo_sync_w1152d512_fwft
	 U_pktbuf(
			  .aclr            (rst                ),         
			  .clock           (clk                ),
                               
			  .data            (pkt_wdat[1151:0]   ),
			  .wrreq           (tx_wenb            ),
			  .full            (                   ),
			  .almost_full     (                   ),
                               
			  .usedw           (pkt_wcnt[8:0]      ),
                               
			  .rdreq           (pkt_rden           ),
			  .q               (pkt_rdat[1151:0]   ),           
			  .empty           (pkt_empty          ),      
			  .almost_empty    (                   )
			  );
`endif
   
  reg                          pkt_rden_t;

   always @ ( posedge clk, posedge rst ) begin
	  if(rst == 1'b1)
		pkt_rden_t <= 1'b0;
	  else
		pkt_rden_t <= tx_mac_ready;
   end
   
   assign pkt_rden = pkt_rden_t & (~pkt_empty);

   always @ ( posedge clk ) begin
	  tx_mac_data      <= pkt_rdat[1023:0];
	  tx_mac_eop_empty <= pkt_rdat[1071:1024];
	  if(pkt_rden == 1'b1)
		tx_mac_inframe <= pkt_rdat[1087:1072];
	  else
		tx_mac_inframe <= 16'd0;
   end

   always @ ( posedge clk, posedge rst ) begin
	  if(rst == 1'b1)
		tx_mac_valid <= 1'd0;
	  else
		tx_mac_valid <= pkt_rden;
   end
   
endmodule // eth_txmac
