//-----------------------------------------------------------------------------
// Title         : ddr4_top,v
// Project       : MA_A3
// Description :
// 
// Modification history :
// 12.06.2024 : created
//-----------------------------------------------------------------------------

`include "../top/define.vh"

module ddr4_top (
				 input  wire [0:0] 		 c0_sys_clk_p         ,
                                                              
				 output wire [0:0] 		 c0_ddr4_act_n        ,
				 output wire [16:0] 	 c0_ddr4_adr          ,
				 input  wire [0:0] 		 c0_ddr4_alert_n      ,
				 output wire [1:0] 		 c0_ddr4_ba           ,
				 output wire [0:0] 		 c0_ddr4_bg           ,
				 output wire [0:0] 		 c0_ddr4_ck_c         ,
				 output wire [0:0] 		 c0_ddr4_ck_t         ,
				 output wire [0:0] 		 c0_ddr4_cke          ,
				 output wire [0:0] 		 c0_ddr4_cs_n         ,
				 output wire [0:0] 		 c0_ddr4_odt          ,
				 inout  wire [1:0] 		 c0_ddr4_dm_n         ,
				 inout  wire [15:0] 	 c0_ddr4_dq           ,
				 inout  wire [1:0] 		 c0_ddr4_dqs_c        ,
				 inout  wire [1:0] 		 c0_ddr4_dqs_t        ,
				 output wire [0:0] 		 c0_ddr4_par          ,
				 output wire [0:0] 		 c0_ddr4_reset_n      ,
   
				 input  wire [0:0] 		 c0_oct_oct_rzqin     ,

				 input  wire 			 local_reset_req      ,//reset
				 output wire 			 local_reset_done     ,
				 
				 output wire 			 local_cal_success    ,
				 output wire 			 local_cal_fail       ,
   
				 output wire 			 app_emif_usr_rst     ,
				 output wire 			 app_emif_usr_clk     ,

				 output wire 			 app_amm_ready        ,
				 input  wire 			 app_amm_read         ,
				 input  wire 			 app_amm_write        ,
				 input  wire [26:0] 	 app_amm_addr         ,//16 byte address
				 output wire [127:0] 	 app_amm_rdat         ,
				 output wire 			 app_amm_rvld         ,
				 input  wire [127:0] 	 app_amm_wdat         ,
				 input  wire [15:0] 	 app_amm_byte         ,
				 input  wire [6:0] 		 app_amm_bcnt         
				 );
   
				 wire 					 emif_calbus_read;
				 wire 					 emif_calbus_write;
				 wire [19:0] 			 emif_calbus_address;
				 wire [31:0] 			 emif_calbus_wdata;
				 wire [31:0] 			 emif_calbus_rdata;
				 wire [4095:0] 			 emif_calbus_seq_param_tbl;
				 wire 					 emif_calbus_clk;
   
   ed_synth_emif_cal 
	 U0_emif_cal (
				  .calbus_read_0          (emif_calbus_read           ),         //  output,     width = 1,   emif_calbus_0.calbus_read
				  .calbus_write_0         (emif_calbus_write          ),        //  output,     width = 1,                .calbus_write
				  .calbus_address_0       (emif_calbus_address        ),      //  output,    width = 20,                .calbus_address
				  .calbus_wdata_0         (emif_calbus_wdata          ),        //  output,    width = 32,                .calbus_wdata
				  .calbus_rdata_0         (emif_calbus_rdata          ),         //   input,    width = 32,                .calbus_rdata
				  .calbus_seq_param_tbl_0 (emif_calbus_seq_param_tbl  ),      //   input,  width = 4096,                .calbus_seq_param_tbl
				  .calbus_clk             (emif_calbus_clk            )                //  output,     width = 1, emif_calbus_clk.clk
				  );

   wire 					 emif_rst_req;
   wire 					 emif_rst_done;
   wire 					 emif_pll_ref_clk_out;
   wire 					 emif_pll_locked;
   wire 					 app_emif_usr_reset_n;

   assign app_emif_usr_rst = ~app_emif_usr_reset_n;
   
   ddr4_16gb 
	 U0_ddr4_16gb(
				 .local_reset_req      (emif_rst_req                  ),      //   input,     width = 1,    local_reset_req.local_reset_req
				 .local_reset_done     (emif_rst_done                 ),     //  output,     width = 1, local_reset_status.local_reset_done
		
				 .pll_ref_clk          (c0_sys_clk_p                  ),          //   input,     width = 1,        pll_ref_clk.clk
				 .pll_ref_clk_out      (emif_pll_ref_clk_out          ),                              //  output,     width = 1,    pll_ref_clk_out.clk
				 .pll_locked           (emif_pll_locked               ),                            //  output,     width = 1,   
				 
				 
				 .oct_rzqin            (c0_oct_oct_rzqin              ),            //   input,     width = 1,                oct.oct_rzqin
				 .mem_ck               (c0_ddr4_ck_t[0]               ),               //  output,     width = 1,                mem.mem_ck
				 .mem_ck_n             (c0_ddr4_ck_c[0]               ),             //  output,     width = 1,                   .mem_ck_n
				 .mem_a                (c0_ddr4_adr[16:0]             ),                //  output,    width = 17,                   .mem_a
				 .mem_act_n            (c0_ddr4_act_n[0]              ),            //  output,     width = 1,                   .mem_act_n
				 .mem_ba               (c0_ddr4_ba[1:0]               ),               //  output,     width = 2,                   .mem_ba
				 .mem_bg               (c0_ddr4_bg[0:0]               ),               //  output,     width = 2,                   .mem_bg
				 .mem_cke              (c0_ddr4_cke[0:0]              ),              //  output,     width = 1,                   .mem_cke
				 .mem_cs_n             (c0_ddr4_cs_n[0:0]             ),             //  output,     width = 1,                   .mem_cs_n
				 .mem_odt              (c0_ddr4_odt[0:0]              ),              //  output,     width = 1,                   .mem_odt
				 .mem_reset_n          (c0_ddr4_reset_n[0:0]          ),          //  output,     width = 1,                   .mem_reset_n
				 .mem_par              (c0_ddr4_par[0:0]              ),              //  output,     width = 1,                   .mem_par
				 .mem_alert_n          (c0_ddr4_alert_n[0:0]          ),          //   input,     width = 1,                   .mem_alert_n
				 .mem_dqs              (c0_ddr4_dqs_t[1:0]            ),              //   inout,     width = 2,                   .mem_dqs
				 .mem_dqs_n            (c0_ddr4_dqs_c[1:0]            ),            //   inout,     width = 2,                   .mem_dqs_n
				 .mem_dq               (c0_ddr4_dq[15:0]              ),               //   inout,    width = 16,                   .mem_dq
				 .mem_dbi_n            (c0_ddr4_dm_n[1:0]             ),            //   inout,     width = 2,                   .mem_dbi_n
				
				 .local_cal_success    (local_cal_success             ),    //  output,     width = 1,             status.local_cal_success
				 .local_cal_fail       (local_cal_fail                ),       //  output,     width = 1,                   .local_cal_fail
				 
				 .emif_usr_reset_n     (app_emif_usr_reset_n          ),     //  output,     width = 1,   emif_usr_reset_n.reset_n
				 .emif_usr_clk         (app_emif_usr_clk              ),         //  output,     width = 1,       emif_usr_clk.clk
		         .amm_ready_0          (app_amm_ready                 ),          //  output,     width = 1,         ctrl_amm_0.waitrequest_n
		         .amm_read_0           (app_amm_read                  ),           //   input,     width = 1,                   .read
		         .amm_write_0          (app_amm_write                 ),          //   input,     width = 1,                   .write
		         .amm_address_0        (app_amm_addr                  ),        //   input,    width = 27,                   .address
		         .amm_readdata_0       (app_amm_rdat[127:0]           ),       //  output,   width = 128,                   .readdata
		         .amm_writedata_0      (app_amm_wdat[127:0]           ),      //   input,   width = 128,                   .writedata
		         .amm_burstcount_0     (app_amm_bcnt[6:0]             ),     //   input,     width = 7,                   .burstcount
		         .amm_byteenable_0     (app_amm_byte[15:0]            ),     //   input,    width = 16,                   .byteenable
		         .amm_readdatavalid_0  (app_amm_rvld                  ),  //  output,     width = 1,                   .readdatavalid
		         
				 .calbus_read          (emif_calbus_read              ),          //   input,     width = 1,        emif_calbus.calbus_read
		         .calbus_write         (emif_calbus_write             ),         //   input,     width = 1,                   .calbus_write
		         .calbus_address       (emif_calbus_address           ),       //   input,    width = 20,                   .calbus_address
		         .calbus_wdata         (emif_calbus_wdata             ),         //   input,    width = 32,                   .calbus_wdata
		         .calbus_rdata         (emif_calbus_rdata             ),         //  output,    width = 32,                   .calbus_rdata
		         .calbus_seq_param_tbl (emif_calbus_seq_param_tbl     ), //  output,  width = 4096,                   .calbus_seq_param_tbl
		         .calbus_clk           (emif_calbus_clk               )            //   input,     width = 1,    emif_calbus_clk.clk
				 );
   
   ed_synth_local_reset_combiner 
	 U0_emif_rst(
				 .clk                   (emif_pll_ref_clk_out         ),                              //   input,  width = 1,             generic_clk.clk
				 .reset_n               (emif_pll_locked              ),                            //   input,  width = 1, generic_conduit_reset_n.pll_locked
                                                                      
				 .local_reset_req       (local_reset_req              ),                                            //   input,  width = 1,         local_reset_req.local_reset_req
				 .local_reset_done      (local_reset_done             ),                                            //  output,  width = 1,      local_reset_status.local_reset_done
                                                                      
				 .local_reset_req_out_0 (emif_rst_req                 ), //  output,  width = 1,   local_reset_req_out_0.local_reset_req
				 .local_reset_done_in_0 (emif_rst_done                )              //   input,  width = 1, local_reset_status_in_0.local_reset_done
				 );
   
endmodule // ddr4_top
