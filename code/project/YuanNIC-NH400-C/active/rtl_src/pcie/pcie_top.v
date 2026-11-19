
`include "../top/global_define.vh"

module pcie_top (
   input  wire [15:0] 		 PCIE0_GT_0_grx_n        ,
   input  wire [15:0] 		 PCIE0_GT_0_grx_p        ,
   output wire [15:0] 		 PCIE0_GT_0_gtx_n        ,
   output wire [15:0] 		 PCIE0_GT_0_gtx_p        ,
                                                    
   input  wire 				 PCIE0_GT_0_clk_p        ,
   input  wire 				 PCIE0_GT_1_clk_p        ,
                                                    
   input 					 pcie_reset_n            ,
                                                  
   output wire 				 pcie_app_rst            ,
   output wire               pcie_app_clk            ,
                                                 
   //pio bus                                              
   input  wire 				 avmm_wait_req           ,
   output wire [27:0] 		 avmm_addr               ,
   output wire [7:0] 		 avmm_byte               ,
   output wire 				 avmm_read               ,
   input  wire [63:0] 		 avmm_rdat               ,
   input  wire 				 avmm_rvld               ,
                                                  
   output wire 				 avmm_write              ,
   output wire [63:0] 		 avmm_wdat               ,
   output wire [3:0] 		 avmm_bcnt               ,
   input  wire [1:0] 		 avmm_rspo               ,
   input  wire 				 avmm_write_rsp          ,
                                              
   //dma bus  
   input   wire         d2h_st_sof_0_i,               //            p0_d2h_st_0.startofpacket,           Check User Guide for details
   input   wire         d2h_st_eof_0_i,               //                       .endofpacket,             Check User Guide for details
   input   wire [5:0]   d2h_st_empty_0_i,             //                       .empty,                   Check User Guide for details
   input   wire [10:0]  d2h_st_channel_0_i,           //                       .channel,                 Check User Guide for details
   input   wire         d2h_st_valid_0_i,             //                       .valid,                   Check User Guide for details
   input   wire [511:0] d2h_st_data_0_i,              //                       .data,                    Check User Guide for details
   output  wire         d2h_st_ready_0_o,             //                       .ready,                   Check User Guide for details
   output  wire         h2d_st_sof_0_o,               //            p0_h2d_st_0.startofpacket,           Check User Guide for details
   output  wire         h2d_st_eof_0_o,               //                       .endofpacket,             Check User Guide for details
   output  wire [5:0]   h2d_st_empty_0_o,             //                       .empty,                   Check User Guide for details
   output  wire         h2d_st_valid_0_o,             //                       .valid,                   Check User Guide for details
   output  wire [511:0] h2d_st_data_0_o,              //                       .data,                    Check User Guide for details
   output  wire [10:0]  h2d_st_channel_0_o,           //                       .channel,                 Check User Guide for details   
   input   wire         h2d_st_ready_0_i,             //                       .ready,                   Check User Guide for details
     
   //status
   output wire 				 app_reset_status        ,
   output wire 				 pcie_link_up            ,
   output wire 				 data_link_up            
				 );
   
   wire 					 pcie_app_rst_n;

   assign pcie_app_rst = !pcie_app_rst_n;

   wire 					 resetip_ninit_done_reset;
   
   pcie_ed_resetIP 
	 resetip (
			  .ninit_done (resetip_ninit_done_reset)  //  output,  width = 1, ninit_done.reset
			  );
   
   pcie4x16 
	 U_pcie4x16_mcdma (
					   .app_clk                      (pcie_app_clk            ),                      //  output,    width = 1,                app_clk.clk
					   .app_rst_n                    (pcie_app_rst_n          ),                    //  output,    width = 1,      app_nreset_status.reset_n
                                                                              
					   //csr interface                                              
					   .rx_pio_waitrequest_i         (avmm_wait_req           ),         //   input,    width = 1,       p0_rx_pio_master.waitrequest
					   .rx_pio_address_o             (avmm_addr               ),             //  output,   width = 28,                       .address
					   .rx_pio_byteenable_o          (avmm_byte               ),          //  output,    width = 8,                       .byteenable
					   .rx_pio_read_o                (avmm_read               ),                //  output,    width = 1,                       .read
					   .rx_pio_readdata_i            (avmm_rdat               ),            //   input,   width = 64,                       .readdata
					   .rx_pio_readdatavalid_i       (avmm_rvld               ),       //   input,    width = 1,                       .readdatavalid
					   .rx_pio_write_o               (avmm_write              ),               //  output,    width = 1,                       .write
					   .rx_pio_writedata_o           (avmm_wdat               ),           //  output,   width = 64,                       .writedata
					   .rx_pio_burstcount_o          (avmm_bcnt               ),          //  output,    width = 4,                       .burstcount
					   .rx_pio_response_i            (avmm_rspo               ),            //   input,    width = 2,                       .response
					   .rx_pio_writeresponsevalid_i  (avmm_write_rsp          ),  //   input,    width = 1,                       .writeresponsevalid
                                                                              
					   //dma interface
                       	.d2h_st_sof_0_i              (d2h_st_sof_0_i   ),               //   input,    width = 1,            p0_d2h_st_0.startofpacket
                        .d2h_st_eof_0_i              (d2h_st_eof_0_i   ),               //   input,    width = 1,                       .endofpacket
                        .d2h_st_empty_0_i            (d2h_st_empty_0_i ),             //   input,    width = 6,                       .empty
                        .d2h_st_channel_0_i          (d2h_st_channel_0_i),           //   input,   width = 11,                       .channel
                        .d2h_st_valid_0_i            (d2h_st_valid_0_i ),             //   input,    width = 1,                       .valid
                        .d2h_st_data_0_i             (d2h_st_data_0_i  ),              //   input,  width = 512,                       .data
                        .d2h_st_ready_0_o            (d2h_st_ready_0_o ),             //  output,    width = 1,                       .ready
                        .h2d_st_sof_0_o              (h2d_st_sof_0_o   ),               //  output,    width = 1,            p0_h2d_st_0.startofpacket
                        .h2d_st_eof_0_o              (h2d_st_eof_0_o   ),               //  output,    width = 1,                       .endofpacket
                        .h2d_st_empty_0_o            (h2d_st_empty_0_o ),             //  output,    width = 6,                       .empty
                        .h2d_st_ready_0_i            (h2d_st_ready_0_i ),             //   input,    width = 1,                       .ready
                        .h2d_st_valid_0_o            (h2d_st_valid_0_o ),             //  output,    width = 1,                       .valid
                        .h2d_st_data_0_o             (h2d_st_data_0_o  ),              //  output,  width = 512,                       .data
                        .h2d_st_channel_0_o          (h2d_st_channel_0_o),           //  output,   width = 11,                       .channel
		       



                       
                                                                           
					   .p0_app_slow_reset_status_n   (app_reset_status        ),   //  output,    width = 1, p0_slow_reset_status_n.reset_n
					   //.p0_app_int_i                 ('d0                     ),                 //   input,    width = 8,                 p0_int.app_int
					   //.p0_app_int_ready_o           (                        ),           //  output,    width = 8,                       .app_int_ready
					   .p0_link_up_o                 (pcie_link_up            ),                 //  output,    width = 1,          p0_hip_status.link_up
					   .p0_dl_up_o                   (data_link_up            ),                   //  output,    width = 1,                       .dl_up
					   .p0_surprise_down_err_o       (                        ),       //  output,    width = 1,                       .surprise_down_err
					   .p0_dl_timer_update_o         (                        ),         //  output,    width = 1,                       .dl_timer_update
					   .p0_ltssm_state_delay_o       (                        ),       //  output,    width = 6,                       .ltssm_state_delay
					   .p0_ltssm_st_hipfifo_ovrflw_o (                        ), //  output,    width = 1,                       .ltssm_st_hipfifo_ovrflw
					   .p0_app_xfer_pending_i        (1'd0                    ),        //   input,    width = 1,          p0_power_mgnt.app_xfer_pending

					   .ninit_done                   (resetip_ninit_done_reset),                   //   input,    width = 1,             ninit_done.reset
					   
					   .refclk0                      (PCIE0_GT_0_clk_p        ),                      //   input,    width = 1,                refclk0.clk
					   .refclk1                      (PCIE0_GT_1_clk_p        ),                      //   input,    width = 1,                refclk1.clk
                                                                              
					   .app_slow_clk                 (                        ),                 //  output,    width = 1,           app_slow_clk.clk
                                                                              
					   .rx_n_in0                     (PCIE0_GT_0_grx_n[0]     ),                     //   input,    width = 1,             hip_serial.rx_n_in0
					   .rx_n_in1                     (PCIE0_GT_0_grx_n[1]     ),                     //   input,    width = 1,                       .rx_n_in1
					   .rx_n_in2                     (PCIE0_GT_0_grx_n[2]     ),                     //   input,    width = 1,                       .rx_n_in2
					   .rx_n_in3                     (PCIE0_GT_0_grx_n[3]     ),                     //   input,    width = 1,                       .rx_n_in3
					   .rx_n_in4                     (PCIE0_GT_0_grx_n[4]     ),                     //   input,    width = 1,                       .rx_n_in4
					   .rx_n_in5                     (PCIE0_GT_0_grx_n[5]     ),                     //   input,    width = 1,                       .rx_n_in5
					   .rx_n_in6                     (PCIE0_GT_0_grx_n[6]     ),                     //   input,    width = 1,                       .rx_n_in6
					   .rx_n_in7                     (PCIE0_GT_0_grx_n[7]     ),                     //   input,    width = 1,                       .rx_n_in7
					   .rx_n_in8                     (PCIE0_GT_0_grx_n[8]     ),                     //   input,    width = 1,                       .rx_n_in8
					   .rx_n_in9                     (PCIE0_GT_0_grx_n[9]     ),                     //   input,    width = 1,                       .rx_n_in9
					   .rx_n_in10                    (PCIE0_GT_0_grx_n[10]    ),                    //   input,    width = 1,                       .rx_n_in10
					   .rx_n_in11                    (PCIE0_GT_0_grx_n[11]    ),                    //   input,    width = 1,                       .rx_n_in11
					   .rx_n_in12                    (PCIE0_GT_0_grx_n[12]    ),                    //   input,    width = 1,                       .rx_n_in12
					   .rx_n_in13                    (PCIE0_GT_0_grx_n[13]    ),                    //   input,    width = 1,                       .rx_n_in13
					   .rx_n_in14                    (PCIE0_GT_0_grx_n[14]    ),                    //   input,    width = 1,                       .rx_n_in14
					   .rx_n_in15                    (PCIE0_GT_0_grx_n[15]    ),                    //   input,    width = 1,                       .rx_n_in15
					   .rx_p_in0                     (PCIE0_GT_0_grx_p[0]     ),                     //   input,    width = 1,                       .rx_p_in0
					   .rx_p_in1                     (PCIE0_GT_0_grx_p[1]     ),                     //   input,    width = 1,                       .rx_p_in1
					   .rx_p_in2                     (PCIE0_GT_0_grx_p[2]     ),                     //   input,    width = 1,                       .rx_p_in2
					   .rx_p_in3                     (PCIE0_GT_0_grx_p[3]     ),                     //   input,    width = 1,                       .rx_p_in3
					   .rx_p_in4                     (PCIE0_GT_0_grx_p[4]     ),                     //   input,    width = 1,                       .rx_p_in4
					   .rx_p_in5                     (PCIE0_GT_0_grx_p[5]     ),                     //   input,    width = 1,                       .rx_p_in5
					   .rx_p_in6                     (PCIE0_GT_0_grx_p[6]     ),                     //   input,    width = 1,                       .rx_p_in6
					   .rx_p_in7                     (PCIE0_GT_0_grx_p[7]     ),                     //   input,    width = 1,                       .rx_p_in7
					   .rx_p_in8                     (PCIE0_GT_0_grx_p[8]     ),                     //   input,    width = 1,                       .rx_p_in8
					   .rx_p_in9                     (PCIE0_GT_0_grx_p[9]     ),                     //   input,    width = 1,                       .rx_p_in9
					   .rx_p_in10                    (PCIE0_GT_0_grx_p[10]    ),                    //   input,    width = 1,                       .rx_p_in10
					   .rx_p_in11                    (PCIE0_GT_0_grx_p[11]    ),                    //   input,    width = 1,                       .rx_p_in11
					   .rx_p_in12                    (PCIE0_GT_0_grx_p[12]    ),                    //   input,    width = 1,                       .rx_p_in12
					   .rx_p_in13                    (PCIE0_GT_0_grx_p[13]    ),                    //   input,    width = 1,                       .rx_p_in13
					   .rx_p_in14                    (PCIE0_GT_0_grx_p[14]    ),                    //   input,    width = 1,                       .rx_p_in14
					   .rx_p_in15                    (PCIE0_GT_0_grx_p[15]    ),                    //   input,    width = 1,                       .rx_p_in15
					   .tx_n_out0                    (PCIE0_GT_0_gtx_n[0]     ),                    //  output,    width = 1,                       .tx_n_out0
					   .tx_n_out1                    (PCIE0_GT_0_gtx_n[1]     ),                    //  output,    width = 1,                       .tx_n_out1
					   .tx_n_out2                    (PCIE0_GT_0_gtx_n[2]     ),                    //  output,    width = 1,                       .tx_n_out2
					   .tx_n_out3                    (PCIE0_GT_0_gtx_n[3]     ),                    //  output,    width = 1,                       .tx_n_out3
					   .tx_n_out4                    (PCIE0_GT_0_gtx_n[4]     ),                    //  output,    width = 1,                       .tx_n_out4
					   .tx_n_out5                    (PCIE0_GT_0_gtx_n[5]     ),                    //  output,    width = 1,                       .tx_n_out5
					   .tx_n_out6                    (PCIE0_GT_0_gtx_n[6]     ),                    //  output,    width = 1,                       .tx_n_out6
					   .tx_n_out7                    (PCIE0_GT_0_gtx_n[7]     ),                    //  output,    width = 1,                       .tx_n_out7
					   .tx_n_out8                    (PCIE0_GT_0_gtx_n[8]     ),                    //  output,    width = 1,                       .tx_n_out8
					   .tx_n_out9                    (PCIE0_GT_0_gtx_n[9]     ),                    //  output,    width = 1,                       .tx_n_out9
					   .tx_n_out10                   (PCIE0_GT_0_gtx_n[10]    ),                   //  output,    width = 1,                       .tx_n_out10
					   .tx_n_out11                   (PCIE0_GT_0_gtx_n[11]    ),                   //  output,    width = 1,                       .tx_n_out11
					   .tx_n_out12                   (PCIE0_GT_0_gtx_n[12]    ),                   //  output,    width = 1,                       .tx_n_out12
					   .tx_n_out13                   (PCIE0_GT_0_gtx_n[13]    ),                   //  output,    width = 1,                       .tx_n_out13
					   .tx_n_out14                   (PCIE0_GT_0_gtx_n[14]    ),                   //  output,    width = 1,                       .tx_n_out14
					   .tx_n_out15                   (PCIE0_GT_0_gtx_n[15]    ),                   //  output,    width = 1,                       .tx_n_out15
					   .tx_p_out0                    (PCIE0_GT_0_gtx_p[0]     ),                    //  output,    width = 1,                       .tx_p_out0
					   .tx_p_out1                    (PCIE0_GT_0_gtx_p[1]     ),                    //  output,    width = 1,                       .tx_p_out1
					   .tx_p_out2                    (PCIE0_GT_0_gtx_p[2]     ),                    //  output,    width = 1,                       .tx_p_out2
					   .tx_p_out3                    (PCIE0_GT_0_gtx_p[3]     ),                    //  output,    width = 1,                       .tx_p_out3
					   .tx_p_out4                    (PCIE0_GT_0_gtx_p[4]     ),                    //  output,    width = 1,                       .tx_p_out4
					   .tx_p_out5                    (PCIE0_GT_0_gtx_p[5]     ),                    //  output,    width = 1,                       .tx_p_out5
					   .tx_p_out6                    (PCIE0_GT_0_gtx_p[6]     ),                    //  output,    width = 1,                       .tx_p_out6
					   .tx_p_out7                    (PCIE0_GT_0_gtx_p[7]     ),                    //  output,    width = 1,                       .tx_p_out7
					   .tx_p_out8                    (PCIE0_GT_0_gtx_p[8]     ),                    //  output,    width = 1,                       .tx_p_out8
					   .tx_p_out9                    (PCIE0_GT_0_gtx_p[9]     ),                    //  output,    width = 1,                       .tx_p_out9
					   .tx_p_out10                   (PCIE0_GT_0_gtx_p[10]    ),                   //  output,    width = 1,                       .tx_p_out10
					   .tx_p_out11                   (PCIE0_GT_0_gtx_p[11]    ),                   //  output,    width = 1,                       .tx_p_out11
					   .tx_p_out12                   (PCIE0_GT_0_gtx_p[12]    ),                   //  output,    width = 1,                       .tx_p_out12
					   .tx_p_out13                   (PCIE0_GT_0_gtx_p[13]    ),                   //  output,    width = 1,                       .tx_p_out13
					   .tx_p_out14                   (PCIE0_GT_0_gtx_p[14]    ),                   //  output,    width = 1,                       .tx_p_out14
					   .tx_p_out15                   (PCIE0_GT_0_gtx_p[15]    ),                   //  output,    width = 1,                       .tx_p_out15
					   .pin_perst_n                  (pcie_reset_n            )                   //   input,    width = 1,              pin_perst.reset_n
					   );

   
endmodule // pcie_top
