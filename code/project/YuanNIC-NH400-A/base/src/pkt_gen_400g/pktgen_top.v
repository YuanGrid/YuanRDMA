//-----------------------------------------------------------------------------
// Title         : pktgen_top.v
// Project       : NSA.A3
// Description :
// 
// Modification history :
// 17.06.2024 : created
//-----------------------------------------------------------------------------

`include "../top/define.v"

module pktgen_top (/*AUTOARG*/
   // Outputs
   tx_ack, tx_mac_valid, tx_mac_inframe, tx_mac_eop_empty,
   tx_mac_data, tx_mac_error, tx_mac_skip_crc,
   // Inputs
   rst, clk, tx_mod, tx_num, tx_req, tx_stop, tx_mac_ready,
   tx_crc_err	
   ) ;
   input  wire                 rst;
   input  wire 				   clk;

   input  wire [3:0] 		   tx_mod;//len_mod
   input  wire [31:0] 		   tx_num;
   input  wire 				   tx_req;
   input  wire 				   tx_stop;
   output wire 				   tx_ack;
   input  wire                 tx_crc_err;
   
   input  wire 				   tx_mac_ready;
   output wire 				   tx_mac_valid;
   output wire [15:0] 		   tx_mac_inframe;
   output wire [48-1:0] 	   tx_mac_eop_empty;
   output wire [16*64-1:0] 	   tx_mac_data;
   output wire [16-1:0] 	   tx_mac_error;
   output wire [16-1:0] 	   tx_mac_skip_crc; //MAC不计算CRC控制

   //周期为2.56ns,所以以2.56ns为时间戳单位
   reg [31:0] 				   cur_time = 'd0;

   always @ (posedge clk) cur_time <= cur_time + 1'b1;
   
   wire                        tx_wenb; 
   wire [1023:0]               tx_wdat; 
   wire [47:0]                 tx_weop; 
   wire [15:0]                 tx_winf; 
   wire                        tx_busy;

   //寄存器异步路径处理
   reg [3:0] 				   tx_mod_d;
   reg [3:0] 				   tx_mod_d2;
   reg [31:0] 				   tx_num_d;
   reg [31:0] 				   tx_num_d2;
   reg 						   tx_req_d;
   reg 						   tx_req_d2;
   reg 						   tx_stop_d;
   reg 						   tx_stop_d2;

   always @ (posedge clk) tx_mod_d  <= tx_mod;
   always @ (posedge clk) tx_mod_d2 <= tx_mod_d;
   always @ (posedge clk) tx_num_d  <= tx_num;
   always @ (posedge clk) tx_num_d2 <= tx_num_d;
   always @ (posedge clk) tx_req_d  <= tx_req;
   always @ (posedge clk) tx_req_d2 <= tx_req_d;
   always @ (posedge clk) tx_stop_d <= tx_stop;
   always @ (posedge clk) tx_stop_d2<= tx_stop_d;
   
   pktgen_400g
	 U_pktgen(
			  .rst             (rst                 ),
			  .clk             (clk                 ),

			  .cur_time        (cur_time[31:0]      ),
			  .tx_mod          (tx_mod_d2[3:0]      ),
			  .tx_num          (tx_num_d2[31:0]     ),
			  .tx_req          (tx_req_d2           ),
			  .tx_stop         (tx_stop_d2          ),
			  .tx_ack          (tx_ack              ),

			  .tx_wenb         (tx_wenb             ),
			  .tx_wdat         (tx_wdat             ),
			  .tx_weop         (tx_weop             ),
			  .tx_winf         (tx_winf             ),
			  .tx_busy         (tx_busy             )
			  );

   reg 						   tx_crc_err_d;
   reg 						   tx_crc_err_d2;

   always @ (posedge clk) tx_crc_err_d  <= tx_crc_err;
   always @ (posedge clk) tx_crc_err_d2 <= tx_crc_err_d;

   eth_txmac
	 U_txmac (
			  .rst             (rst                 ),
			  .clk             (clk                 ),
			  
			  .tx_crc_err      (tx_crc_err_d2       ),
			  
			  .tx_wenb         (tx_wenb             ),
			  .tx_wdat         (tx_wdat             ),
			  .tx_weop         (tx_weop             ),
			  .tx_winf         (tx_winf             ),
			  .tx_busy         (tx_busy             ),

			  .tx_mac_ready    (tx_mac_ready        ), 
			  .tx_mac_valid    (tx_mac_valid        ),
			  .tx_mac_inframe  (tx_mac_inframe      ),
			  .tx_mac_eop_empty(tx_mac_eop_empty    ),
			  .tx_mac_data     (tx_mac_data         ),
              .tx_mac_error    (tx_mac_error        ),
              .tx_mac_skip_crc (tx_mac_skip_crc     )
              );
   
   
endmodule // pktgen_top
