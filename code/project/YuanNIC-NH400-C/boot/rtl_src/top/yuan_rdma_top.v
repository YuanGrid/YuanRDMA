
`include "global_define.vh"

module YuanRDMA (
   //pcie interface
   input  wire [15:0] 		 PCIE0_GT_0_grx_n    ,
   input  wire [15:0] 		 PCIE0_GT_0_grx_p    ,
   output wire [15:0] 		 PCIE0_GT_0_gtx_n    ,
   output wire [15:0] 		 PCIE0_GT_0_gtx_p    ,

   input 					 pcie_reset_n        , 

   //reference clock for pcie_x16 or pcie_x8
   input  wire 				 PCIE0_GT_0_clk_p    ,

   //reference clock for pcie_x8
   input  wire 				 PCIE0_GT_1_clk_p    ,

   //eth-400G
   input  wire [3:0] 		 eth_gt_rxn_in       ,
   input  wire [3:0] 		 eth_gt_rxp_in       ,
   output wire [3:0] 		 eth_gt_txn_out      ,
   output wire [3:0] 		 eth_gt_txp_out      ,

   //eth interface reference clock
   input  wire 				 eth_gt_fht_clk      ,
   //eth MAC system clock 
   input  wire 				 eth_gt_fgt_clk      ,


   //fpga core reference clock 200M
   input  wire 				 pl_clk_p            ,
   //fpga core reset
   input  wire 				 ex_reset_n          ,

   input  wire 				 opt_mod_los         ,
   input  wire 				 opt_mod_pst         ,//present
   output wire 				 opt_mod_lpm         ,//low power mode
   output wire 	 			 opt_mod_rst       
                   );

/*****************************************************************************\
*                                                                             *
*                  clk & rst module for system                                *
*                                                                             *
*                                                                             *
\*****************************************************************************/



   wire 				 i2c_s_fpga_scl  ;
   wire 				 i2c_s_fpga_sda  ;                           
   wire 				 i2c_m_fpga_scl  ;
   wire 				 i2c_m_fpga_sda  ;

   wire 					 clk250m;
   wire 					 clk100m;
   wire 					 clk50m;
   wire 					 locked;
   wire  [7:0]               soft_rst_val;
   wire                      soft_rst_clr;
   wire						 sys_rst;

   wire                  ex_reset_n_null = 1'b1;
`ifndef SIMULATION 
   clk200m
     U_clk200m(
               .refclk                   (pl_clk_p                ),
               
               .rst                      (~ex_reset_n_null             ),

               .outclk_0                 (clk250m                 ),
               .outclk_1                 (clk100m                 ),
               .outclk_2                 (clk50m                  ),

               .locked                   (locked                  )
               );

   rst
     U_rstm (
             .clk                        ( clk250m                ), 
             .ex_reset_n                 ( ex_reset_n_null             ),
             .mmcm_lock                  ( 1'b1                   ),

             .soft_rst_val               ( soft_rst_val           ),
             .soft_rst_clr               ( soft_rst_clr           ),
             
             .hard_rst                   (                        ),
             .sys_rst                    (sys_rst                 )
             );
`endif
/*****************************************************************************\
*                                                                             *
*                  PCIE DMA and PIO                                           *
*                                                                             *
\*****************************************************************************/ 
   wire 					 pcie_app_rst;
   wire 					 pcie_app_clk; //500M

   wire 					 sir_sel    ;
   wire 					 sir_read   ;
   wire [31:0] 				 sir_addr   ;
   wire [31:0] 				 sir_wdat   ;
   wire [31:0] 				 sir_rdat   ;
   wire 					 sir_dack   ;

`ifndef PCIE_GEN5X16   
    localparam                  AVM_USER_NUM= 6;

    wire                        pcie2cdc_avm_wait;
    wire [27:0]                 pcie2cdc_avm_addr;
    wire [7:0]                  pcie2cdc_avm_byte;
    wire                        pcie2cdc_avm_read;
    wire [63:0]                 pcie2cdc_avm_rdat;
    wire                        pcie2cdc_avm_rvld;
    wire                        pcie2cdc_avm_write;
    wire [63:0]                 pcie2cdc_avm_wdat;
    wire [3:0]                  pcie2cdc_avm_bcnt;
    wire [1:0]                  pcie2cdc_avm_rspo;
    wire                        pcie2cdc_avm_wrsp;

    wire                        cdc2cfg_avm_wait;
    wire [27:0]                 cdc2cfg_avm_addr;
    wire [7:0]                  cdc2cfg_avm_byte;
    wire                        cdc2cfg_avm_read;
    wire [31:0]                 cdc2cfg_avm_rdat;
    wire                        cdc2cfg_avm_rvld;
    wire                        cdc2cfg_avm_write;
    wire [31:0]                 cdc2cfg_avm_wdat;
    wire [3:0]                  cdc2cfg_avm_bcnt;
    wire [1:0]                  cdc2cfg_avm_rspo;
    wire                        cdc2cfg_avm_wrsp;

    wire    [AVM_USER_NUM*28-1:0]   user_avm_addr ;
    wire    [AVM_USER_NUM-1:0]      user_avm_read ;
    wire    [AVM_USER_NUM-1:0]      user_avm_write;
    wire    [AVM_USER_NUM*32-1:0]   user_avm_wdat ;
    wire    [AVM_USER_NUM-1:0]      user_avm_wait ;
    wire    [AVM_USER_NUM*32-1:0]   user_avm_rdat ;
    wire    [AVM_USER_NUM-1:0]      user_avm_rvld ;
    wire    [AVM_USER_NUM*2-1:0]    user_avm_rspo ;
    wire    [AVM_USER_NUM-1:0]      user_avm_wrsp ;

   (* keep *) wire 				 h2ddm_wait_req   = 1'b0  ;
   (* keep *) wire 				 h2ddm_write         ;
   (* keep *) wire [63:0] 		 h2ddm_addr          ;
   (* keep *) wire [3:0] 		 h2ddm_bcnt          ;
   (* keep *) wire [63:0] 		 h2ddm_byte          ;
   (* keep *) wire [511:0] 		 h2ddm_wdat          ;
   
   //dma bus signal  
   (*keep*)  wire         d2h_st_sof_0_i    ;               //            p0_d2h_st_0.startofpacket,           Check User Guide for details
   (*keep*)  wire         d2h_st_eof_0_i    ;               //                       .endofpacket,             Check User Guide for details
   (*keep*)  wire [5:0]   d2h_st_empty_0_i  ;             //                       .empty,                   Check User Guide for details
   (*keep*)  wire [10:0]  d2h_st_channel_0_i;           //                       .channel,                 Check User Guide for details
   (*keep*)  wire         d2h_st_valid_0_i  ;             //                       .valid,                   Check User Guide for details
   (*keep*)  wire [511:0] d2h_st_data_0_i   ;              //                       .data,                    Check User Guide for details
   (*keep*)  wire         d2h_st_ready_0_o  ;             //                       .ready,                   Check User Guide for details
   (*keep*)  wire         h2d_st_sof_0_o    ;               //            p0_h2d_st_0.startofpacket,           Check User Guide for details
   (*keep*)  wire         h2d_st_eof_0_o    ;               //                       .endofpacket,             Check User Guide for details
   (*keep*)  wire [5:0]   h2d_st_empty_0_o  ;             //                       .empty,                   Check User Guide for details
   (*keep*)  wire         h2d_st_valid_0_o  ;             //                       .valid,                   Check User Guide for details
   (*keep*)  wire [511:0] h2d_st_data_0_o   ;              //                       .data,                    Check User Guide for details
   (*keep*)  wire [10:0]  h2d_st_channel_0_o;           //                       .channel,                 Check User Guide for details   
   (*keep*)  wire         h2d_st_ready_0_i  ;            //                       .ready,                   Check User Guide for details
    wire            tx_gen_mac_ready     ;
    wire            tx_gen_mac_valid     ;
    wire [15:0]     tx_gen_mac_inframe   ;
    wire [47:0]     tx_gen_mac_eop_empty ;
    wire [1023:0]   tx_gen_mac_data      ;
    wire [15:0]     tx_gen_mac_error     ;
    wire [15:0]     tx_gen_mac_skip_crc  ;
    `ifndef SIMULATION
    pcie_top
    U_pci4_top(
        .PCIE0_GT_0_grx_n         (PCIE0_GT_0_grx_n        ), 
        .PCIE0_GT_0_grx_p         (PCIE0_GT_0_grx_p        ),
        .PCIE0_GT_0_gtx_n         (PCIE0_GT_0_gtx_n        ),
        .PCIE0_GT_0_gtx_p         (PCIE0_GT_0_gtx_p        ),
        .PCIE0_GT_0_clk_p         (PCIE0_GT_0_clk_p        ),
        .PCIE0_GT_1_clk_p         (PCIE0_GT_1_clk_p        ),
        .pcie_reset_n             (pcie_reset_n            ),
                                
        .pcie_app_rst             (pcie_app_rst            ),
        .pcie_app_clk             (pcie_app_clk            ),
        //pio csr interface
        .avmm_wait_req            (pcie2cdc_avm_wait       ),
        .avmm_addr                (pcie2cdc_avm_addr       ),
        .avmm_byte                (pcie2cdc_avm_byte       ),
        .avmm_read                (pcie2cdc_avm_read       ),
        .avmm_rdat                (pcie2cdc_avm_rdat       ),
        .avmm_rvld                (pcie2cdc_avm_rvld       ),
        .avmm_write               (pcie2cdc_avm_write      ),
        .avmm_wdat                (pcie2cdc_avm_wdat       ),
        .avmm_bcnt                (pcie2cdc_avm_bcnt       ),
        .avmm_rspo                (pcie2cdc_avm_rspo       ),
        .avmm_write_rsp           (pcie2cdc_avm_wrsp       ),
        // DMA avalon-st interface 
        .d2h_st_sof_0_i           (d2h_st_sof_0_i           ),               //   input,    width = 1,            p0_d2h_st_0.startofpacket
        .d2h_st_eof_0_i           (d2h_st_eof_0_i           ),               //   input,    width = 1,                       .endofpacket
        .d2h_st_empty_0_i         (d2h_st_empty_0_i         ),             //   input,    width = 6,                       .empty
        .d2h_st_channel_0_i       (d2h_st_channel_0_i       ),           //   input,   width = 11,                       .channel
        .d2h_st_valid_0_i         (d2h_st_valid_0_i         ),             //   input,    width = 1,                       .valid
        .d2h_st_data_0_i          (d2h_st_data_0_i          ),              //   input,  width = 512,                       .data
        .d2h_st_ready_0_o         (d2h_st_ready_0_o         ),             //  output,    width = 1,                       .ready
        .h2d_st_sof_0_o           (h2d_st_sof_0_o           ),               //  output,    width = 1,            p0_h2d_st_0.startofpacket
        .h2d_st_eof_0_o           (h2d_st_eof_0_o           ),               //  output,    width = 1,                       .endofpacket
        .h2d_st_empty_0_o         (h2d_st_empty_0_o         ),             //  output,    width = 6,                       .empty
        .h2d_st_ready_0_i         (h2d_st_ready_0_i         ),             //   input,    width = 1,                       .ready
        .h2d_st_valid_0_o         (h2d_st_valid_0_o         ),             //  output,    width = 1,                       .valid
        .h2d_st_data_0_o          (h2d_st_data_0_o          ),              //  output,  width = 512,                       .data
        .h2d_st_channel_0_o       (h2d_st_channel_0_o       ),           //  output,   width = 11,                       .channel
        .app_reset_status         (                         ),
        .pcie_link_up             (                         ),
        .data_link_up             (                         )
    );
    `endif
                
/*****************************************************************************\
*       tx_path
\*****************************************************************************/
    localparam                  CHANNL_NUM  = 2;
    localparam                  DATA_W      = 1024;
    localparam                  USERF_W     = $clog2(DATA_W/8);
    localparam                  FRAME_W     = DATA_W/64;
    wire [3:0] 				    eth_tx_mod;
    wire [31:0] 				eth_tx_num;
    wire 					    eth_tx_req;
    wire 					    eth_tx_stop;
    wire 					    eth_tx_ack_p;
    wire 					    tx_crc_err;
    
    wire    [CHANNL_NUM-1:0]    gen_to_strmak_tvalid        ;
    wire    [CHANNL_NUM*DATA_W-1:0]gen_to_strmak_tdata      ;
    wire    [CHANNL_NUM*USERF_W-1:0]gen_to_strmak_tusef     ;
    wire    [CHANNL_NUM-1:0]    gen_to_strmak_tlast         ;
    wire    [CHANNL_NUM-1:0]    gen_to_strmak_tready        ;
    wire    [CHANNL_NUM-1:0]    gen_to_strmak_tuser_sop     ;
    wire    [CHANNL_NUM*48-1:0] gen_to_strmak_tuser_id      ;
    wire    [CHANNL_NUM-1:0]    gen_to_strmak_tuser_stamp_en;
    wire                        gen_to_segm_pkt_stop_en;
    wire                        clk400_1s_en;

    wire                        strmak_to_regslice_tvalid [CHANNL_NUM-1:0];
    wire    [DATA_W-1:0]        strmak_to_regslice_tdata  [CHANNL_NUM-1:0];
    wire    [USERF_W-1:0]       strmak_to_regslice_tusef  [CHANNL_NUM-1:0];
    wire    [37-1:0]            strmak_to_regslice_tinfo  [CHANNL_NUM-1:0];
    wire                        strmak_to_regslice_tlast  [CHANNL_NUM-1:0];
    wire                        strmak_to_regslice_tready [CHANNL_NUM-1:0];

    wire                        regslice_to_select_tvalid [CHANNL_NUM-1:0];
    wire    [DATA_W-1:0]        regslice_to_select_tdata  [CHANNL_NUM-1:0];
    wire    [USERF_W-1:0]       regslice_to_select_tusef  [CHANNL_NUM-1:0];
    wire    [37-1:0]            regslice_to_select_tinfo  [CHANNL_NUM-1:0];
    wire                        regslice_to_select_tlast  [CHANNL_NUM-1:0];
    wire                        regslice_to_select_tready [CHANNL_NUM-1:0];

    wire                        qdma_to_regslice_tvalid;
    wire    [DATA_W-1:0]        qdma_to_regslice_tdata ;
    wire    [USERF_W-1:0]       qdma_to_regslice_tusef ;
    wire                        qdma_to_regslice_tlast ;
    wire                        qdma_to_regslice_tready;

    wire                        qdma_to_select_tvalid;
    wire    [DATA_W-1:0]        qdma_to_select_tdata ;
    wire    [USERF_W-1:0]       qdma_to_select_tusef ;
    wire                        qdma_to_select_tlast ;
    wire                        qdma_to_select_tready;
    wire    [4:0]               qdma_to_select_tfr_num;

    wire                        select_to_segm_tvalid;
    wire                        select_to_segm_qdma  ;
    wire    [DATA_W-1:0]        select_to_segm_tdata ;
    wire    [USERF_W-1:0]       select_to_segm_tusef ;
    wire    [37-1:0]            select_to_segm_tinfo ;
    wire                        select_to_segm_tlast ;
    wire                        select_to_segm_tready;

    wire                        segm_to_regslice_tvalid;
    wire    [DATA_W-1:0]        segm_to_regslice_tdata ;
    wire    [FRAME_W*3-1:0]     segm_to_regslice_emty  ;
    wire    [FRAME_W-1:0]       segm_to_regslice_frame ;
    wire    [41-1:0]            segm_to_regslice_info  ;
    wire                        segm_to_regslice_tready;

    wire                        regslice_to_gap_tvalid;
    wire    [DATA_W-1:0]        regslice_to_gap_tdata ;
    wire    [FRAME_W*3-1:0]     regslice_to_gap_emty  ;
    wire    [FRAME_W-1:0]       regslice_to_gap_frame ;
    wire    [41-1:0]            regslice_to_gap_info  ;
    wire                        regslice_to_gap_tready;

    wire                        gap_to_mac_tvalid;
    wire    [DATA_W-1:0]        gap_to_mac_tdata ;
    wire    [FRAME_W*3-1:0]     gap_to_mac_emty  ;
    wire    [FRAME_W-1:0]       gap_to_mac_frame ;
    wire                        gap_to_mac_tready;

    wire    [DATA_W-1:0]        rx_mac_data     ;
    wire    [FRAME_W*3-1:0]     rx_mac_eop_empty;
    wire    [FRAME_W-1:0]       rx_mac_inframe  ;
    wire    [FRAME_W*2-1:0]     rx_mac_error    ;
    wire    [FRAME_W-1:0]       rx_mac_fcs_error;
    wire                        rx_mac_valid    ;

    wire    [DATA_W-1:0]        rx_to_rcv_tdata[CHANNL_NUM-1:0]    ;
    wire    [7-1:0]             rx_to_rcv_tempty[CHANNL_NUM-1:0]   ;
    wire    [2:0]               rx_to_rcv_tuerr[CHANNL_NUM-1:0]    ;
    wire                        rx_to_rcv_tvalid[CHANNL_NUM-1:0]   ;
    wire                        rx_to_rcv_tready[CHANNL_NUM-1:0]   ;
    wire                        rx_to_rcv_tlast[CHANNL_NUM-1:0]    ;
    wire 					    eth_rx_rst;
    wire 					    eth_tx_rst;

    wire                        rdma_to_regl_tvalid   ;
    wire    [512-1:0]           rdma_to_regl_tdata    ;
    wire                        rdma_to_regl_tlast    ;
    wire    [5:0]               rdma_to_regl_tkeep    ;
    wire    [11:0]              rdma_to_regl_tchannel ;
    wire                        rdma_to_regl_tready   ;

    wire                        regl_to_qdma_tvalid   ;
    wire    [512-1:0]           regl_to_qdma_tdata    ;
    wire                        regl_to_qdma_tlast    ;
    wire    [5:0]               regl_to_qdma_tkeep    ;
    wire    [11:0]              regl_to_qdma_tchannel ;
    wire                        regl_to_qdma_tready   ;

    wire                        rcv_to_qdma_tvalid; 
    wire    [DATA_W-1:0]        rcv_to_qdma_tdata ; 
    wire    [USERF_W-1:0]       rcv_to_qdma_tkeep ; 
    wire                        rcv_to_qdma_tlast ; 
    wire                        rcv_to_qdma_tready; 
    wire    [63:0]              time_stamp_eth;
    wire    [63:0]              time_stamp_delay;
    wire    [63:0]              time_stamp_eth_rcv;
    wire    [63:0]              time_stamp_clk250;
    wire    [63:0]              time_stamp_pcie;
    wire    [63:0]              gtime_value    ;
    wire                        gtime_set      ;
    wire                        rocev2_stamp_en;
    wire                        statis_cnt_clear_en;
    wire    [31:0]              shell_rstn;
    wire    [31:0]              shell_rst_done;
    wire                        eth_mac_clk;
    wire 					    eth_rx_pcs_ready;
    reg                         rx_path_eop_vld;
    reg     [1:0]               rx_path_eop_num;
    reg                         qdma_d2h_last_vld;
    reg                         pcie_d2h_last_vld;
    reg                         pcie_d2h_sof_vld;
    reg                         stream_mark0_eop_vld;
    reg                         stream_mark1_eop_vld;
    reg                         pcie_h2d_eop_vld;
    reg                         rdma2qdma_eop_vld;
    reg                         qdma_h2d_eop_vld;
    reg                         axis_select_eop_vld;
    reg     [1:0]               segm2gap_eop_num;
    reg     [15:0]              segm2gap_frame_d1;
    reg     [1:0]               gap2mac_eop_num;
    reg     [15:0]              gap2mac_frame_d1;
    wire    [31:0]              rx_path_eop_cnt     ;
    wire    [31:0]              rx_rcv_last0_cnt    ;
    wire    [31:0]              rx_rcv_last1_cnt    ;
    wire    [31:0]              qdma_d2h_last_cnt   ;
    wire    [31:0]              pcie_d2h_last_cnt   ;
    wire    [31:0]              pcie_d2h_sof_cnt   ;
    wire    [31:0]              stream_mark0_eop_cnt;
    wire    [31:0]              stream_mark1_eop_cnt;
    wire    [31:0]              pcie_h2d_eop_cnt    ;
    wire    [31:0]              rdma2qdma_eop_cnt    ;
    wire    [31:0]              qdma_h2d_eop_cnt    ;
    wire    [31:0]              axis_select_eop_cnt ;
    wire    [31:0]              segm2gap_eop_cnt    ;
    wire    [31:0]              gap2mac_eop_cnt     ;
    wire    [31:0]              gap2mac_eop_1s_cnt     ;
    reg     [31:0]              gap2mac_eop_1s_cnt_reg  ;
    wire    [63:0]              eth_fcs_err_cnt         ;
    wire    [63:0]              eth_mfmd_err_cnt        ;
    wire    [63:0]              eth_under_over_err_cnt  ;
    wire    [63:0]              eth_plen_err_cnt        ;
    wire    [63:0]              eth_fifo_full_err_cnt   ;
    reg     [58:0]              mod_int_status_reg      ;
    wire    [2:0]               clk_rstn[1:0]           ;
    wire    [1:0]               mac_clk_rstn            ;
    wire    [1:0]               axil_clk_rstn           ;
    wire    [1:0]               pcie_clk_rstn           ;

    assign shell_rst_done[31:2] = {30{1'b1}};

    generate
        for (genvar i=0 ; i<2 ; i=i+1) begin
            generic_reset #(
                .NUM_INPUT_CLK                          (3),
                .RESET_DURATION                         (100)
            ) mac_rstn_u (                      
                .mod_clk                                (clk250m      ),
                .mod_rstn                               (shell_rstn[i]),
                .mod_rst_done                           (shell_rst_done[i]),
                .clk                                    ({pcie_app_clk,clk250m,eth_mac_clk}),
                .rstn                                   (clk_rstn[i])
            );

            assign mac_clk_rstn[i]  = clk_rstn[i][0];
            assign axil_clk_rstn[i] = clk_rstn[i][1];
            assign pcie_clk_rstn[i] = clk_rstn[i][2];
        end
    endgenerate
    
    pkt_gen
    u0_pkt_gen
    (      
        .s_avm_addr                         (user_avm_addr [2*28+:28] ),
        .s_avm_read                         (user_avm_read [2]        ),
        .s_avm_write                        (user_avm_write[2]        ),
        .s_avm_wdat                         (user_avm_wdat [2*32+:32] ),
        .s_avm_wait                         (user_avm_wait [2]        ),
        .s_avm_rdat                         (user_avm_rdat [2*32+:32] ),
        .s_avm_rvld                         (user_avm_rvld [2]        ),
        .s_avm_rspo                         (user_avm_rspo [2*2+:2]   ),
        .s_avm_wrsp                         (user_avm_wrsp [2]        ),
        .m_axis_pkt_tx_tvalid               (gen_to_strmak_tvalid           ),
        .m_axis_pkt_tx_tdata                (gen_to_strmak_tdata            ),
        .m_axis_pkt_tx_tusef                (gen_to_strmak_tusef            ),
        .m_axis_pkt_tx_tlast                (gen_to_strmak_tlast            ),
        .m_axis_pkt_tx_tready               (gen_to_strmak_tready           ),
        .m_axis_pkt_tx_tuser_sop            (gen_to_strmak_tuser_sop        ),
        .m_axis_pkt_tx_tuser_id             (gen_to_strmak_tuser_id         ),
        .m_axis_pkt_tx_tuser_stamp_en       (gen_to_strmak_tuser_stamp_en   ),
        .m_gen_stop_en                      (gen_to_segm_pkt_stop_en        ),
        .clk400_1s_en                       (clk400_1s_en                   ),
        .time_stamp                         (time_stamp_eth                 ),
        .mac_rstn                           (mac_clk_rstn[0]                ),
        .axil_rstn                          (axil_clk_rstn[0]               ),
        .axil_aclk                          (clk250m                        ),
        .axis_aclk                          (eth_mac_clk                    ),
        .cmac_clk                           (eth_mac_clk                    )
    );

    stream_mark
    u1_stream_mark
    (
        .axis_aclk                          (eth_mac_clk                            ),
        .rst_n                              (mac_clk_rstn[0]                        ),
        .s_axis_tvalid                      (gen_to_strmak_tvalid[0]                ),
        .s_axis_tdata                       (gen_to_strmak_tdata[0*DATA_W+:DATA_W]  ),
        .s_axis_tlast                       (gen_to_strmak_tlast[0]                 ),
        .s_axis_tusef                       (gen_to_strmak_tusef[0*USERF_W+:USERF_W]),
        .s_axis_tuser_sop                   (gen_to_strmak_tuser_sop[0]             ),
        .s_axis_tuser_id                    (gen_to_strmak_tuser_id[0*48+:48]       ),
        .s_axis_tuser_stamp_en              (gen_to_strmak_tuser_stamp_en[0]        ),
        .s_axis_tready                      (gen_to_strmak_tready[0]                ),
        .m_axis_tvalid                      (strmak_to_regslice_tvalid [0]),
        .m_axis_tdata                       (strmak_to_regslice_tdata  [0]),
        .m_axis_tlast                       (strmak_to_regslice_tlast  [0]),
        .m_axis_tusef                       (strmak_to_regslice_tusef  [0]),
        .m_axis_tinfo                       (strmak_to_regslice_tinfo  [0]),
        .m_axis_tready                      (strmak_to_regslice_tready [0]),
        .time_stamp                         (time_stamp_delay             )
    );

    stream_mark
    u2_stream_mark
    (
        .axis_aclk                          (eth_mac_clk                            ),
        .rst_n                              (mac_clk_rstn[0]                        ),
        .s_axis_tvalid                      (gen_to_strmak_tvalid[1]                ),
        .s_axis_tdata                       (gen_to_strmak_tdata[1*DATA_W+:DATA_W]  ),
        .s_axis_tlast                       (gen_to_strmak_tlast[1]                 ),
        .s_axis_tusef                       (gen_to_strmak_tusef[1*USERF_W+:USERF_W]),
        .s_axis_tuser_sop                   (gen_to_strmak_tuser_sop[1]             ),
        .s_axis_tuser_id                    (gen_to_strmak_tuser_id[1*48+:48]       ),
        .s_axis_tuser_stamp_en              (gen_to_strmak_tuser_stamp_en[1]        ),
        .s_axis_tready                      (gen_to_strmak_tready[1]                ),
        .m_axis_tvalid                      (strmak_to_regslice_tvalid [1]),
        .m_axis_tdata                       (strmak_to_regslice_tdata  [1]),
        .m_axis_tlast                       (strmak_to_regslice_tlast  [1]),
        .m_axis_tusef                       (strmak_to_regslice_tusef  [1]),
        .m_axis_tinfo                       (strmak_to_regslice_tinfo  [1]),
        .m_axis_tready                      (strmak_to_regslice_tready [1]),
        .time_stamp                         (time_stamp_delay             )
    );

    axi_stream_register_slice #(
        .TDATA_W                            (DATA_W         ),
        .TID_W                              (1              ),
        .TDEST_W                            (37             ),
        .TUSER_W                            (USERF_W        ),
        .MODE                               ("full"         )
    )u21_streammark2select_reg_slice (
        .s_axis_tvalid                      (strmak_to_regslice_tvalid [0]),
        .s_axis_tdata                       (strmak_to_regslice_tdata  [0]),
        .s_axis_tkeep                       (                             ),
        .s_axis_tlast                       (strmak_to_regslice_tlast  [0]),
        .s_axis_tid                         (                             ),
        .s_axis_tdest                       (strmak_to_regslice_tinfo  [0]),
        .s_axis_tuser                       (strmak_to_regslice_tusef  [0]),
        .s_axis_tready                      (strmak_to_regslice_tready [0]),
        .m_axis_tvalid                      (regslice_to_select_tvalid [0]),
        .m_axis_tdata                       (regslice_to_select_tdata  [0]),
        .m_axis_tkeep                       (                             ),
        .m_axis_tlast                       (regslice_to_select_tlast  [0]),
        .m_axis_tid                         (                             ),
        .m_axis_tdest                       (regslice_to_select_tinfo  [0]),
        .m_axis_tuser                       (regslice_to_select_tusef  [0]),
        .m_axis_tready                      (regslice_to_select_tready [0]),
        .aclk                               (eth_mac_clk                  ),
        .aresetn                            (mac_clk_rstn[0]              )
    );

    axi_stream_register_slice #(
        .TDATA_W                            (DATA_W         ),
        .TID_W                              (1              ),
        .TDEST_W                            (37             ),
        .TUSER_W                            (USERF_W        ),
        .MODE                               ("full"         )
    )u22_streammark2segm_reg_slice (
        .s_axis_tvalid                      (strmak_to_regslice_tvalid [1]),
        .s_axis_tdata                       (strmak_to_regslice_tdata  [1]),
        .s_axis_tkeep                       (                             ),
        .s_axis_tlast                       (strmak_to_regslice_tlast  [1]),
        .s_axis_tid                         (                             ),
        .s_axis_tdest                       (strmak_to_regslice_tinfo[1]),
        .s_axis_tuser                       (strmak_to_regslice_tusef  [1]),
        .s_axis_tready                      (strmak_to_regslice_tready [1]),
        .m_axis_tvalid                      (regslice_to_select_tvalid [1]),
        .m_axis_tdata                       (regslice_to_select_tdata  [1]),
        .m_axis_tkeep                       (                             ),
        .m_axis_tlast                       (regslice_to_select_tlast  [1]),
        .m_axis_tid                         (                             ),
        .m_axis_tdest                       (regslice_to_select_tinfo  [1]),
        .m_axis_tuser                       (regslice_to_select_tusef  [1]),
        .m_axis_tready                      (regslice_to_select_tready [1]),
        .aclk                               (eth_mac_clk                  ),
        .aresetn                            (mac_clk_rstn[0]              )
    );

    assign qdma_to_select_tfr_num = qdma_to_select_tusef==0 ?5'd16:qdma_to_select_tusef[6:3] + |qdma_to_select_tusef[0+:3];

    axis_select #(
        .AXIS_NUM                           (2      )
    )
    u3_gen0_qdma_select                         
    (          
        .clk                                (eth_mac_clk        ),
        .rst_n                              (mac_clk_rstn[0]      ),
        .s_axis_tvalid                      ({regslice_to_select_tvalid[0],qdma_to_select_tvalid}),
        .s_axis_tdata                       ({regslice_to_select_tdata [0],qdma_to_select_tdata }),
        .s_axis_tlast                       ({regslice_to_select_tlast [0],qdma_to_select_tlast }),
        .s_axis_usef                        ({regslice_to_select_tusef [0],qdma_to_select_tusef }),
        .s_axis_info                        ({regslice_to_select_tinfo [0],{qdma_to_select_tfr_num,32'b0}}),
        .s_axis_tready                      ({regslice_to_select_tready[0],qdma_to_select_tready}),
        .m_axis_tvalid                      (select_to_segm_tvalid  ),
        .m_axis_qdma                        (select_to_segm_qdma    ),
        .m_axis_tdata                       (select_to_segm_tdata   ),
        .m_axis_tlast                       (select_to_segm_tlast   ),
        .m_axis_usef                        (select_to_segm_tusef   ),
        .m_axis_info                        (select_to_segm_tinfo ),
        .m_axis_tready                      (select_to_segm_tready  )
    );

    axis_to_segm #(
        .AXIS_NUM                           (2      )
    )
    u4_axis_to_segm
    (          
        .clk                                (eth_mac_clk             ),
        .rst_n                              (mac_clk_rstn[0]           ),
        .s_axis_tvalid                      ({regslice_to_select_tvalid [1],select_to_segm_tvalid}),
        .s_axis_qdma                        ({1'b0                         ,select_to_segm_qdma  }),
        .s_axis_tdata                       ({regslice_to_select_tdata  [1],select_to_segm_tdata }),
        .s_axis_tlast                       ({regslice_to_select_tlast  [1],select_to_segm_tlast }),
        .s_axis_usef                        ({regslice_to_select_tusef  [1],select_to_segm_tusef }),
        .s_axis_finfo                       ({regslice_to_select_tinfo  [1],select_to_segm_tinfo }),
        .s_axis_tready                      ({regslice_to_select_tready [1],select_to_segm_tready}),
        .s_axis_pkt_stop_en                 (gen_to_segm_pkt_stop_en ),
        .m_segm_data                        (segm_to_regslice_tdata  ),
        .m_segm_emty                        (segm_to_regslice_emty   ),
        .m_segm_frame                       (segm_to_regslice_frame  ),
        .m_segm_info                        (segm_to_regslice_info   ),
        .m_segm_valid                       (segm_to_regslice_tvalid ),
        .m_segm_ready                       (segm_to_regslice_tready )
    );

    axi_stream_register_slice #(
        .TDATA_W                            (DATA_W         ),
        .TKEEP_W                            (1              ),
        .TID_W                              (FRAME_W*3      ),
        .TDEST_W                            (FRAME_W        ),
        .TUSER_W                            (41             ),
        .MODE                               ("full"         )
    )u41_segm2gap_reg_slice (
        .s_axis_tvalid                      (segm_to_regslice_tvalid     ),
        .s_axis_tdata                       (segm_to_regslice_tdata      ),
        .s_axis_tkeep                       (                            ),
        .s_axis_tlast                       (                            ),
        .s_axis_tid                         (segm_to_regslice_emty       ),
        .s_axis_tdest                       (segm_to_regslice_frame      ),
        .s_axis_tuser                       (segm_to_regslice_info       ),
        .s_axis_tready                      (segm_to_regslice_tready     ),
        .m_axis_tvalid                      (regslice_to_gap_tvalid      ),
        .m_axis_tdata                       (regslice_to_gap_tdata       ),
        .m_axis_tkeep                       (                            ),
        .m_axis_tlast                       (                            ),
        .m_axis_tid                         (regslice_to_gap_emty        ),
        .m_axis_tdest                       (regslice_to_gap_frame       ),
        .m_axis_tuser                       (regslice_to_gap_info        ),
        .m_axis_tready                      (regslice_to_gap_tready      ),
        .aclk                               (eth_mac_clk                 ),
        .aresetn                            (mac_clk_rstn[0]               )
    );

    segm_gap
    u5_segm_gap
    (          
        .clk                                (eth_mac_clk                 ),
        .rst_n                              (mac_clk_rstn[0]             ),
        .s_gap_data                         (regslice_to_gap_tdata       ),
        .s_gap_emty                         (regslice_to_gap_emty        ),
        .s_gap_frame                        (regslice_to_gap_frame       ),
        .s_gap_gap                          (regslice_to_gap_info[31:0]  ),
        .s_gap_eop_num                      (regslice_to_gap_info[33:32] ),
        .s_gap_eop_pos                      (regslice_to_gap_info[40:36] ),
        .s_gap_valid                        (regslice_to_gap_tvalid ),
        .s_gap_ready                        (regslice_to_gap_tready ),
        .m_gap_data                         (gap_to_mac_tdata   ),
        .m_gap_emty                         (gap_to_mac_emty    ),
        .m_gap_frame                        (gap_to_mac_frame   ),
        .m_gap_valid                        (gap_to_mac_tvalid  ),
        .m_gap_ready                        (gap_to_mac_tready  )
    );

/*****************************************************************************\
*       rx_path
\*****************************************************************************/
    rx_path_avst
    u6_rx_path
    (
        .mac_clk                            (eth_mac_clk),
        .mac_rst_n                          (mac_clk_rstn[1]),
        .s_mac_data                         (rx_mac_data       ),
        .s_mac_emty                         (rx_mac_eop_empty  ),
        .s_mac_inframe                      (rx_mac_inframe    ),
        .s_mac_error                        (rx_mac_error      ),
        .s_mac_fcs_error                    (rx_mac_fcs_error  ),
        .s_mac_valid                        (rx_mac_valid      ),
        .m_axis_tdata0                      (rx_to_rcv_tdata[0] ),
        .m_axis_tempty0                     (rx_to_rcv_tempty[0]),
        .m_axis_tuerr0                      (rx_to_rcv_tuerr[0] ),
        .m_axis_tvalid0                     (rx_to_rcv_tvalid[0]),
        .m_axis_tready0                     (1'b1               ),
        .m_axis_teop0                       (rx_to_rcv_tlast[0] ),
        .m_axis_tdata1                      (rx_to_rcv_tdata[1] ),
        .m_axis_tempty1                     (rx_to_rcv_tempty[1]),
        .m_axis_tuerr1                      (rx_to_rcv_tuerr[1] ),
        .m_axis_tvalid1                     (rx_to_rcv_tvalid[1]),
        .m_axis_tready1                     (1'b1               ),
        .m_axis_teop1                       (rx_to_rcv_tlast[1] )
    );

    rx_pkt_rcv_top#(
        .DATA_W                             (DATA_W                     )
    )
    u7_rx_filet
    (
        .s_avm_addr                         (user_avm_addr [3*28+:28] ),
        .s_avm_read                         (user_avm_read [3]        ),
        .s_avm_write                        (user_avm_write[3]        ),
        .s_avm_wdat                         (user_avm_wdat [3*32+:32] ),
        .s_avm_wait                         (user_avm_wait [3]        ),
        .s_avm_rdat                         (user_avm_rdat [3*32+:32] ),
        .s_avm_rvld                         (user_avm_rvld [3]        ),
        .s_avm_rspo                         (user_avm_rspo [3*2+:2]   ),
        .s_avm_wrsp                         (user_avm_wrsp [3]        ),
        .s_axis_rx0_tvalid                  (rx_to_rcv_tvalid[0]      ),
        .s_axis_rx0_tdata                   (rx_to_rcv_tdata[0]       ),
        .s_axis_rx0_tkeep                   (rx_to_rcv_tempty[0]      ),
        .s_axis_rx0_tlast                   (rx_to_rcv_tlast[0]       ),
        .s_axis_rx0_tuser_err               (rx_to_rcv_tuerr[0]       ),
        .s_axis_rx1_tvalid                  (rx_to_rcv_tvalid[1]      ),
        .s_axis_rx1_tdata                   (rx_to_rcv_tdata[1]       ),
        .s_axis_rx1_tkeep                   (rx_to_rcv_tempty[1]      ),
        .s_axis_rx1_tlast                   (rx_to_rcv_tlast[1]       ),
        .s_axis_rx1_tuser_err               (rx_to_rcv_tuerr[1]       ),
        .m_axis_rx_tvalid                   (rcv_to_qdma_tvalid       ),
        .m_axis_rx_tdata                    (rcv_to_qdma_tdata        ),
        .m_axis_rx_tkeep                    (rcv_to_qdma_tkeep        ),
        .m_axis_rx_tlast                    (rcv_to_qdma_tlast        ),
        .m_axis_rx_tready                   (rcv_to_qdma_tready       ),
        .cnt_clear_en                       (statis_cnt_clear_en      ),
        .eth_fcs_err_cnt                    (eth_fcs_err_cnt          ),
        .eth_mfmd_err_cnt                   (eth_mfmd_err_cnt         ),
        .eth_under_over_err_cnt             (eth_under_over_err_cnt   ),
        .eth_plen_err_cnt                   (eth_plen_err_cnt         ),
        .eth_fifo_full_err_cnt              (eth_fifo_full_err_cnt    ),
        .link_up0                           (eth_rx_pcs_ready         ),
        .mac_rstn                           (mac_clk_rstn[1]          ),
        .axil_rstn                          (axil_clk_rstn[1]         ),
        .pcie_rstn                          (pcie_clk_rstn[1]         ),
        .time_stamp                         (time_stamp_delay         ),
        .axis_aclk                          (pcie_app_clk             ),
        .axil_aclk                          (clk250m                  ),
        .mac_clk                            (eth_mac_clk              )
    );

    rdma_timestamp_mark
    u8_rdma_timestamp_mark
    (
        .clk                                (pcie_app_clk           ),
        .rst_n                              (pcie_clk_rstn[1]       ),
        .s_axis_tvalid                      (h2d_st_valid_0_o       ),
        .s_axis_tdata                       (h2d_st_data_0_o        ),
        .s_axis_tlast                       (h2d_st_eof_0_o         ),
        .s_axis_tkeep                       (h2d_st_empty_0_o       ),
        .s_axis_tchannel                    (h2d_st_channel_0_o     ),
        .s_axis_tready                      (h2d_st_ready_0_i       ),
        .m_axis_tvalid                      (rdma_to_regl_tvalid    ),
        .m_axis_tdata                       (rdma_to_regl_tdata     ),
        .m_axis_tlast                       (rdma_to_regl_tlast     ),
        .m_axis_tkeep                       (rdma_to_regl_tkeep     ),
        .m_axis_tchannel                    (rdma_to_regl_tchannel  ),
        .m_axis_tready                      (rdma_to_regl_tready    ),
        .time_stamp                         (time_stamp_pcie        ),
        .rdma_tx_timestamp_en               (rocev2_stamp_en        )
    );

    axi_stream_register_slice #(
        .TDATA_W                            (DATA_W/2               ),
        .TID_W                              (12                     ),
        .TDEST_W                            (1                      ),
        .TUSER_W                            (USERF_W                ),
        .MODE                               ("full"                 )
    )u82_axi_stream_register_slice (
        .s_axis_tvalid                      (rdma_to_regl_tvalid    ),
        .s_axis_tdata                       (rdma_to_regl_tdata     ),
        .s_axis_tkeep                       (                       ),
        .s_axis_tlast                       (rdma_to_regl_tlast     ),
        .s_axis_tid                         (rdma_to_regl_tchannel  ),
        .s_axis_tdest                       (                       ),
        .s_axis_tuser                       (rdma_to_regl_tkeep     ),
        .s_axis_tready                      (rdma_to_regl_tready    ),
        .m_axis_tvalid                      (regl_to_qdma_tvalid    ),
        .m_axis_tdata                       (regl_to_qdma_tdata     ),
        .m_axis_tkeep                       (                       ),
        .m_axis_tlast                       (regl_to_qdma_tlast     ),
        .m_axis_tid                         (regl_to_qdma_tchannel  ),
        .m_axis_tdest                       (                       ),
        .m_axis_tuser                       (regl_to_qdma_tkeep     ),
        .m_axis_tready                      (regl_to_qdma_tready    ),
        .aclk                               (pcie_app_clk           ),
        .aresetn                            (pcie_clk_rstn[1]       )
    );

    qdma_top
    u9_qdma_top
    (
        .s_avm_addr                         (user_avm_addr [4*28+:28]   ),
        .s_avm_read                         (user_avm_read [4]          ),
        .s_avm_write                        (user_avm_write[4]          ),
        .s_avm_wdat                         (user_avm_wdat [4*32+:32]   ),
        .s_avm_wait                         (user_avm_wait [4]          ),
        .s_avm_rdat                         (user_avm_rdat [4*32+:32]   ),
        .s_avm_rvld                         (user_avm_rvld [4]          ),
        .s_avm_rspo                         (user_avm_rspo [4*2+:2]     ),
        .s_avm_wrsp                         (user_avm_wrsp [4]          ),
        .m_d2h_st_sof                       (d2h_st_sof_0_i             ),
        .m_d2h_st_eof                       (d2h_st_eof_0_i             ),
        .m_d2h_st_empty                     (d2h_st_empty_0_i           ),
        .m_d2h_st_channel                   (d2h_st_channel_0_i         ),
        .m_d2h_st_valid                     (d2h_st_valid_0_i           ),
        .m_d2h_st_data                      (d2h_st_data_0_i            ),
        .m_d2h_st_ready                     (d2h_st_ready_0_o           ),
        .s_d2h_axis_last                    (rcv_to_qdma_tlast          ),
        .s_d2h_axis_empty                   (rcv_to_qdma_tkeep          ),
        .s_d2h_axis_valid                   (rcv_to_qdma_tvalid         ),
        .s_d2h_axis_data                    (rcv_to_qdma_tdata          ),
        .s_d2h_axis_ready                   (rcv_to_qdma_tready         ),
        .s_h2d_st_sof                       (1'b0                       ),
        .s_h2d_st_eop                       (regl_to_qdma_tlast         ),
        .s_h2d_st_empty                     (regl_to_qdma_tkeep         ),
        .s_h2d_st_ready                     (regl_to_qdma_tready        ),
        .s_h2d_st_valid                     (regl_to_qdma_tvalid        ),
        .s_h2d_st_data                      (regl_to_qdma_tdata         ),
        .s_h2d_st_channel                   (regl_to_qdma_tchannel      ),
        .m_h2d_axis_last                    (qdma_to_regslice_tlast     ),
        .m_h2d_axis_empty                   (qdma_to_regslice_tusef     ),
        .m_h2d_axis_ready                   (qdma_to_regslice_tready    ),
        .m_h2d_axis_valid                   (qdma_to_regslice_tvalid    ),
        .m_h2d_axis_data                    (qdma_to_regslice_tdata     ),
        .axil_aclk                          (clk250m                    ),
        .axil_rst                           (~axil_clk_rstn[1]           ),
        .dma_clk                            (pcie_app_clk               ),
        .dma_rst                            (~pcie_clk_rstn[1]          ),
        .mac_clk                            (eth_mac_clk                ),
        .mac_rst                            (~mac_clk_rstn[1]           )
    );

    axi_stream_register_slice #(
        .TDATA_W                            (DATA_W                     ),
        .TID_W                              (1                          ),
        .TDEST_W                            (1                          ),
        .TUSER_W                            (USERF_W                    ),
        .MODE                               ("full"                     )
    )u91_qdma2select_reg_slice (
        .s_axis_tvalid                      (qdma_to_regslice_tvalid    ),
        .s_axis_tdata                       (qdma_to_regslice_tdata     ),
        .s_axis_tkeep                       (                           ),
        .s_axis_tlast                       (qdma_to_regslice_tlast     ),
        .s_axis_tid                         (                           ),
        .s_axis_tdest                       (                           ),
        .s_axis_tuser                       (qdma_to_regslice_tusef     ),
        .s_axis_tready                      (qdma_to_regslice_tready    ),
        .m_axis_tvalid                      (qdma_to_select_tvalid      ),
        .m_axis_tdata                       (qdma_to_select_tdata       ),
        .m_axis_tkeep                       (                           ),
        .m_axis_tlast                       (qdma_to_select_tlast       ),
        .m_axis_tid                         (                           ),
        .m_axis_tdest                       (                           ),
        .m_axis_tuser                       (qdma_to_select_tusef       ),
        .m_axis_tready                      (qdma_to_select_tready      ),
        .aclk                               (eth_mac_clk                ),
        .aresetn                            (mac_clk_rstn[1]            )
    );

/*****************************************************************************\
*                                                                             *
*                  csr_pro for AVMM                                           *
*                                                                             *
\*****************************************************************************/
    avm_cdc
    u95_avm_cdc
    (
        .s_avm_addr                         (pcie2cdc_avm_addr),
        .s_avm_byte                         (pcie2cdc_avm_byte),
        .s_avm_read                         (pcie2cdc_avm_read),
        .s_avm_write                        (pcie2cdc_avm_write),
        .s_avm_wdat                         (pcie2cdc_avm_wdat),
        .s_avm_bcnt                         (pcie2cdc_avm_bcnt),
        .s_avm_wait                         (pcie2cdc_avm_wait),
        .s_avm_rdat                         (pcie2cdc_avm_rdat),
        .s_avm_rvld                         (pcie2cdc_avm_rvld),
        .s_avm_rspo                         (pcie2cdc_avm_rspo),
        .s_avm_wrsp                         (pcie2cdc_avm_wrsp),
        .m_avm_addr                         (cdc2cfg_avm_addr ),
        .m_avm_read                         (cdc2cfg_avm_read ),
        .m_avm_write                        (cdc2cfg_avm_write),
        .m_avm_wdat                         (cdc2cfg_avm_wdat ),
        .m_avm_wait                         (cdc2cfg_avm_wait ),
        .m_avm_rdat                         (cdc2cfg_avm_rdat ),
        .m_avm_rvld                         (cdc2cfg_avm_rvld ),
        .m_avm_rspo                         (cdc2cfg_avm_rspo ),
        .m_avm_wrsp                         (cdc2cfg_avm_wrsp ),
        .s_clk                              (pcie_app_clk     ),
        .m_clk                              (clk250m          ),
        .rst_n                              (~pcie_app_rst    )
    );

    avm_config #(
        .USER_NUM                           (AVM_USER_NUM    )
    )
    u96_avm_config
    (
        .avm_addr                           (cdc2cfg_avm_addr   ),
        .avm_byte                           (8'h0f              ),
        .avm_read                           (cdc2cfg_avm_read   ),
        .avm_write                          (cdc2cfg_avm_write  ),
        .avm_wdat                           (cdc2cfg_avm_wdat   ),
        .avm_bcnt                           ( 4'd1              ),
        .avm_wait                           (cdc2cfg_avm_wait   ),
        .avm_rdat                           (cdc2cfg_avm_rdat   ),
        .avm_rvld                           (cdc2cfg_avm_rvld   ),
        .avm_rspo                           (cdc2cfg_avm_rspo   ),
        .avm_wrsp                           (cdc2cfg_avm_wrsp   ),
        .user_avm_addr                      (user_avm_addr      ),
        .user_avm_read                      (user_avm_read      ),
        .user_avm_write                     (user_avm_write     ),
        .user_avm_wdat                      (user_avm_wdat      ),
        .user_avm_wait                      (user_avm_wait      ),
        .user_avm_rdat                      (user_avm_rdat      ),
        .user_avm_rvld                      (user_avm_rvld      ),
        .user_avm_rspo                      (user_avm_rspo      ),
        .user_avm_wrsp                      (user_avm_wrsp      ),
        .clk                                (clk250m            ),
        .rst_n                              (~pcie_app_rst      )
    );

    time_stamp #(.FREQ(4))
    u97_time_stamp(
        .clk_r                              (clk250m            ),
        .gtime_value                        (gtime_value        ),
        .gtime_set                          (gtime_set          ),
        .rst_n                              (~sys_rst           ),
        .clk1                               (eth_mac_clk        ),
        .time_stamp_clk1                    (time_stamp_eth     ),
        .clk2                               (                   ),
        .time_stamp_clk2                    (                   ),
        .clk3                               (                   ),
        .time_stamp_clk3                    (                   ),
        .clk4                               (                   ),
        .time_stamp_clk4                    (                   ),
        .clk5                               (                   ),
        .time_stamp_clk5                    (                   )
    );

    reg     gtime_set_500m_d1;
    reg     gtime_set_500m_d2;
    reg     gtime_set_500m_d3;
    reg     gtime_set_250m_d1;

    always @(posedge clk250m ) begin
        gtime_set_250m_d1 <= gtime_set;
    end

    always @(posedge pcie_app_clk ) begin
        gtime_set_500m_d1 <= gtime_set_250m_d1 | gtime_set;
        gtime_set_500m_d2 <= gtime_set_500m_d1;
        gtime_set_500m_d3 <= gtime_set_500m_d2;
    end

    time_stamp #(.FREQ(2))
    u97_time_stamp1(
        .clk_r                              (pcie_app_clk       ),
        .gtime_value                        (gtime_value        ),
        .gtime_set                          (gtime_set_500m_d3  ),
        .rst_n                              (~sys_rst           ),
        .clk1                               (eth_mac_clk        ),
        .time_stamp_clk1                    (time_stamp_delay   ),
        .clk2                               (pcie_app_clk       ),
        .time_stamp_clk2                    (time_stamp_pcie    ),
        .clk3                               (                   ),
        .time_stamp_clk3                    (                   ),
        .clk4                               (                   ),
        .time_stamp_clk4                    (                   ),
        .clk5                               (                   ),
        .time_stamp_clk5                    (                   )
    );

    system_config_register
    u98_system_config_register
    (
        .s_avm_addr                         (user_avm_addr [1*28+:28]   ),
        .s_avm_read                         (user_avm_read [1]          ),
        .s_avm_write                        (user_avm_write[1]          ),
        .s_avm_wdat                         (user_avm_wdat [1*32+:32]   ),
        .s_avm_wait                         (user_avm_wait [1]          ),
        .s_avm_rdat                         (user_avm_rdat [1*32+:32]   ),
        .s_avm_rvld                         (user_avm_rvld [1]          ),
        .s_avm_rspo                         (user_avm_rspo [1*2+:2]     ),
        .s_avm_wrsp                         (user_avm_wrsp [1]          ),
        .shell_rstn                         (shell_rstn                 ),
        .shell_rst_done                     (shell_rst_done             ),
        .user_rstn                          (                           ),
        .user_rst_done                      ({32{1'b1}}                 ),
        .statis_cnt_clear_en                (statis_cnt_clear_en        ),
        .debug_rx_path_eop_cnt              ({32'b0,rx_path_eop_cnt     }),
        .debug_rx_rcv_last0_cnt             ({32'b0,rx_rcv_last0_cnt    }),
        .debug_rx_rcv_last1_cnt             ({32'b0,rx_rcv_last1_cnt    }),
        .debug_qdma_d2h_last_cnt            ({32'b0,qdma_d2h_last_cnt   }),
        .debug_pcie_d2h_last_cnt            ({32'b0,pcie_d2h_last_cnt   }),
        .gap2mac_eop_1s_cnt_reg             ({32'b0,gap2mac_eop_1s_cnt_reg  }),
        .debug_stream_mark0_eop_cnt         ({32'b0,stream_mark0_eop_cnt}),
        .debug_stream_mark1_eop_cnt         ({32'b0,stream_mark1_eop_cnt}),
        .debug_pcie_h2d_eop_cnt             ({32'b0,pcie_h2d_eop_cnt    }),
        .debug_rdma2qdma_eop_cnt            ({32'b0,rdma2qdma_eop_cnt   }),
        .debug_qdma_h2d_eop_cnt             ({32'b0,qdma_h2d_eop_cnt    }),
        .debug_axis_select_eop_cnt          ({32'b0,axis_select_eop_cnt }),
        .debug_segm2gap_eop_cnt             ({32'b0,segm2gap_eop_cnt    }), 
        .debug_gap2mac_eop_cnt              ({32'b0,gap2mac_eop_cnt     }), 
        .debug_mod_int_status_reg           ({6'b0,mod_int_status_reg   }), 
        .debug_eth_fcs_err_cnt              (eth_fcs_err_cnt             ),
        .debug_eth_mfmd_err_cnt             (eth_mfmd_err_cnt            ),
        .debug_eth_under_over_err_cnt       (eth_under_over_err_cnt      ),
        .debug_eth_plen_err_cnt             (eth_plen_err_cnt            ),
        .debug_eth_fifo_full_err_cnt        (eth_fifo_full_err_cnt       ),
        .fpga_temp                          (64'b0),
        .link_up0                           (64'b0),
        .link_up1                           (64'b0),
        .link_up2                           (64'b0),
        .link_up3                           (64'b0),
        .stat_rx_local_fault_0              (64'b0),
        .stat_rx_local_fault_1              (64'b0),
        .stat_rx_local_fault_2              (64'b0),
        .stat_rx_local_fault_3              (64'b0),
        .stat_rx_block_lock_0               (64'b0),
        .stat_rx_block_lock_1               (64'b0),
        .stat_rx_block_lock_2               (64'b0),
        .stat_rx_block_lock_3               (64'b0),
        .stat_rx_remote_fault_0             (64'b0),
        .stat_rx_remote_fault_1             (64'b0),
        .stat_rx_remote_fault_2             (64'b0),
        .stat_rx_remote_fault_3             (64'b0),
        .gtime_value                        (gtime_value        ),
        .gtime_set                          (gtime_set          ),
        .rocev2_stamp_en                    (rocev2_stamp_en    ),
        .aclk                               (clk250m            ),
        .aresetn                            (~pcie_app_rst   )
    );

    avm2csr
    U_avm2csr(
        .rst                                (pcie_app_rst           ),
        .avm_clk                            (clk250m                 ),
        .clk                                (clk250m                 ),
        .avm_addr                           (user_avm_addr[0*28+:28] ),  
        .avm_byte                           (8'h0F                   ),
        .avm_read                           (user_avm_read[0]        ),
        .avm_write                          (user_avm_write[0]       ),
        .avm_wdat                           (user_avm_wdat[0*32+:32] ),
        .avm_bcnt                           (4'd1                    ),
        .avm_wait                           (user_avm_wait[0]        ),
        .avm_rdat                           (user_avm_rdat[0*32+:32] ),
        .avm_rvld                           (user_avm_rvld[0]        ),
        .avm_rspo                           (user_avm_rspo[0*2+:2]   ),
        .avm_wrsp                           (user_avm_wrsp[0]        ),
        .sir_sel                            (sir_sel                 ), 
        .sir_read                           (sir_read                ),
        .sir_addr                           (sir_addr                ),
        .sir_wdat                           (sir_wdat                ),
        .sir_rdat                           (sir_rdat                ),
        .sir_dack                           (sir_dack                )
    );

    always @(posedge eth_mac_clk ) begin
        rx_path_eop_vld <= u6_rx_path.mac_valid_d[1];
        rx_path_eop_num <= u6_rx_path.eop_num_d[1];
    end
    always @(posedge pcie_app_clk ) begin 
        qdma_d2h_last_vld <= rcv_to_qdma_tvalid & rcv_to_qdma_tlast & rcv_to_qdma_tready;
        pcie_d2h_last_vld <= d2h_st_valid_0_i & d2h_st_eof_0_i & d2h_st_ready_0_o;
        pcie_d2h_sof_vld  <= d2h_st_valid_0_i & d2h_st_sof_0_i & d2h_st_ready_0_o;
    end
    //rx 方向  
    cnt#(.WIDTH(32))cnt_u00(.clear(statis_cnt_clear_en),.clk(eth_mac_clk),.vld(rx_path_eop_vld),.step({14'b0,rx_path_eop_num}),.cnt(rx_path_eop_cnt));
    cnt#(.WIDTH(32))cnt_u05(.clear(statis_cnt_clear_en),.clk(eth_mac_clk),.vld(rx_to_rcv_tvalid[0]),.step({15'b0,rx_to_rcv_tlast[0]}),.cnt(rx_rcv_last0_cnt));
    cnt#(.WIDTH(32))cnt_u06(.clear(statis_cnt_clear_en),.clk(eth_mac_clk),.vld(rx_to_rcv_tvalid[1]),.step({15'b0,rx_to_rcv_tlast[1]}),.cnt(rx_rcv_last1_cnt));
    cnt#(.WIDTH(32))cnt_u07(.clear(statis_cnt_clear_en),.clk(pcie_app_clk),.vld(qdma_d2h_last_vld),.step({15'b0,1'b1}),.cnt(qdma_d2h_last_cnt));
    cnt#(.WIDTH(32))cnt_u08(.clear(statis_cnt_clear_en),.clk(pcie_app_clk),.vld(pcie_d2h_last_vld),.step({15'b0,1'b1}),.cnt(pcie_d2h_last_cnt));
    cnt#(.WIDTH(32))cnt_u09(.clear(statis_cnt_clear_en),.clk(pcie_app_clk),.vld(pcie_d2h_sof_vld),.step({15'b0,1'b1}),.cnt(pcie_d2h_sof_cnt));
    //tx 方向

    always @(posedge pcie_app_clk ) begin
        pcie_h2d_eop_vld <= h2d_st_valid_0_o & h2d_st_eof_0_o & h2d_st_ready_0_i ;
        rdma2qdma_eop_vld <= regl_to_qdma_tready & regl_to_qdma_tvalid & regl_to_qdma_tlast;
    end

    always @(posedge eth_mac_clk ) begin
        qdma_h2d_eop_vld     <= qdma_to_select_tvalid & qdma_to_select_tready & qdma_to_select_tlast;
        axis_select_eop_vld  <= select_to_segm_tvalid & select_to_segm_tlast & select_to_segm_tready;
        stream_mark0_eop_vld <= strmak_to_regslice_tvalid[0] & strmak_to_regslice_tlast [0] & strmak_to_regslice_tready[0];
        stream_mark1_eop_vld <= strmak_to_regslice_tvalid[1] & strmak_to_regslice_tlast [1] & strmak_to_regslice_tready[1];

        segm2gap_frame_d1 <= segm_to_regslice_frame;
        segm2gap_eop_num  <= segm_to_regslice_tvalid&segm_to_regslice_tready ? eop_num({segm_to_regslice_frame,segm2gap_frame_d1[15]}):2'd0;

        if(!mac_clk_rstn[0])
            gap2mac_frame_d1 <= 16'b0;
        else if(gap_to_mac_tvalid)
            gap2mac_frame_d1 <= gap_to_mac_frame;

        gap2mac_eop_num  <= gap_to_mac_tvalid ? eop_num({gap_to_mac_frame,gap2mac_frame_d1[15]}) : 2'd0;
    end

    cnt#(.WIDTH(32))cnt_u40(.clear(statis_cnt_clear_en),.clk(eth_mac_clk),.vld(stream_mark0_eop_vld),.step({15'b0,1'b1}),.cnt(stream_mark0_eop_cnt));
    cnt#(.WIDTH(32))cnt_u41(.clear(statis_cnt_clear_en),.clk(eth_mac_clk),.vld(stream_mark1_eop_vld),.step({15'b0,1'b1}),.cnt(stream_mark1_eop_cnt));
    cnt#(.WIDTH(32))cnt_u42(.clear(statis_cnt_clear_en),.clk(pcie_app_clk),.vld(pcie_h2d_eop_vld),.step({15'b0,1'b1}),.cnt(pcie_h2d_eop_cnt));
    cnt#(.WIDTH(32))cnt_u43(.clear(statis_cnt_clear_en),.clk(pcie_app_clk),.vld(rdma2qdma_eop_vld),.step({15'b0,1'b1}),.cnt(rdma2qdma_eop_cnt));
    cnt#(.WIDTH(32))cnt_u44(.clear(statis_cnt_clear_en),.clk(eth_mac_clk),.vld(qdma_h2d_eop_vld),.step({15'b0,1'b1}),.cnt(qdma_h2d_eop_cnt));
    cnt#(.WIDTH(32))cnt_u45(.clear(statis_cnt_clear_en),.clk(eth_mac_clk),.vld(axis_select_eop_vld),.step({15'b0,1'b1}),.cnt(axis_select_eop_cnt));
    cnt#(.WIDTH(32))cnt_u46(.clear(statis_cnt_clear_en),.clk(eth_mac_clk),.vld(|segm2gap_eop_num),.step({14'b0,segm2gap_eop_num}),.cnt(segm2gap_eop_cnt));
    
    cnt#(.WIDTH(32))cnt_u47(.clear(statis_cnt_clear_en),.clk(eth_mac_clk),.vld(|gap2mac_eop_num),.step({14'b0,gap2mac_eop_num}),.cnt(gap2mac_eop_cnt));
    cnt#(.WIDTH(32))cnt_u48(.clear(clk400_1s_en),.clk(eth_mac_clk),.vld(|gap2mac_eop_num),.step({14'b0,gap2mac_eop_num}),.cnt(gap2mac_eop_1s_cnt));
    always @(posedge eth_mac_clk ) begin
        if(clk400_1s_en) begin
            gap2mac_eop_1s_cnt_reg  <= gap2mac_eop_1s_cnt;
        end
    end

    wire    [15:0]      data_fifo_afull0;
    wire    [15:0]      data_fifo_afull1;
    wire    [15:0]      data_fifo_empty0;
    wire    [15:0]      data_fifo_empty1;

    assign  data_fifo_afull0 = u6_rx_path.data_concat0_u.data_fifo_afull;
    assign  data_fifo_afull1 = u6_rx_path.data_concat1_u.data_fifo_afull;
    assign  data_fifo_empty0 = u6_rx_path.data_concat0_u.data_fifo_empty;
    assign  data_fifo_empty1 = u6_rx_path.data_concat1_u.data_fifo_empty;

    always @(posedge clk250m ) begin
        mod_int_status_reg[00] <= gen_to_strmak_tvalid[0];
        mod_int_status_reg[01] <= ~gen_to_strmak_tready[0];
        mod_int_status_reg[02] <= gen_to_strmak_tvalid[1];
        mod_int_status_reg[03] <= ~gen_to_strmak_tready[1];
        mod_int_status_reg[04] <= strmak_to_regslice_tvalid[0];
        mod_int_status_reg[05] <= ~strmak_to_regslice_tready[0];
        mod_int_status_reg[06] <= strmak_to_regslice_tvalid[1];
        mod_int_status_reg[07] <= ~strmak_to_regslice_tready[1];
        mod_int_status_reg[08] <= regslice_to_select_tvalid[0];
        mod_int_status_reg[09] <= regslice_to_select_tready[0];
        mod_int_status_reg[10] <= regslice_to_select_tvalid[1];
        mod_int_status_reg[11] <= regslice_to_select_tready[1];
        mod_int_status_reg[12] <= qdma_to_select_tvalid;
        mod_int_status_reg[13] <= ~qdma_to_select_tready;
        mod_int_status_reg[14] <= select_to_segm_tvalid;
        mod_int_status_reg[15] <= ~select_to_segm_tready;
        mod_int_status_reg[16] <= segm_to_regslice_tvalid;
        mod_int_status_reg[17] <= ~segm_to_regslice_tready;
        mod_int_status_reg[18] <= segm_to_regslice_frame!=0?1'b1:1'b0;
        mod_int_status_reg[19] <= ~gap_to_mac_tready;
        mod_int_status_reg[20] <= ~gap_to_mac_tvalid;
        mod_int_status_reg[21] <= gap_to_mac_frame!=0?1'b1:1'b0;
        mod_int_status_reg[22] <= rx_to_rcv_tvalid[0];
        mod_int_status_reg[23] <= rx_to_rcv_tvalid[1];
        mod_int_status_reg[24] <= rcv_to_qdma_tvalid;
        mod_int_status_reg[25] <= ~rcv_to_qdma_tready;
        mod_int_status_reg[26] <= d2h_st_valid_0_i;
        mod_int_status_reg[27] <= ~d2h_st_ready_0_o;
        mod_int_status_reg[28] <= h2d_st_valid_0_o;
        mod_int_status_reg[29] <= ~h2d_st_ready_0_i;
        mod_int_status_reg[30] <= rdma_to_regl_tvalid;
        mod_int_status_reg[31] <= ~rdma_to_regl_tready;
        mod_int_status_reg[32] <= regl_to_qdma_tvalid;
        mod_int_status_reg[33] <= ~regl_to_qdma_tready;
        mod_int_status_reg[34] <= |data_fifo_afull0;
        mod_int_status_reg[35] <= ~(&data_fifo_empty0);
        mod_int_status_reg[36] <= u6_rx_path.data_concat0_u.info_fifo_afull;
        mod_int_status_reg[37] <= ~u6_rx_path.data_concat0_u.info_fifo_empty;
        mod_int_status_reg[38] <= |data_fifo_afull1;
        mod_int_status_reg[39] <= ~(&data_fifo_empty1);
        mod_int_status_reg[40] <= u6_rx_path.data_concat1_u.info_fifo_afull;
        mod_int_status_reg[41] <= ~u6_rx_path.data_concat1_u.info_fifo_empty;
        mod_int_status_reg[42] <= u7_rx_filet.u3_rx_mux_nto1.s_drop_fifo_afull[0];
        mod_int_status_reg[43] <= ~u7_rx_filet.u3_rx_mux_nto1.s_drop_fifo_empty[0];
        mod_int_status_reg[44] <= u7_rx_filet.u3_rx_mux_nto1.s_drop_fifo_afull[1];
        mod_int_status_reg[45] <= ~u7_rx_filet.u3_rx_mux_nto1.s_drop_fifo_empty[1];
        mod_int_status_reg[46] <= u7_rx_filet.u3_rx_mux_nto1.s_info_fifo_afull;
        mod_int_status_reg[47] <= ~u7_rx_filet.u3_rx_mux_nto1.m_info_fifo_empty;
        mod_int_status_reg[48] <= u7_rx_filet.u3_rx_mux_nto1.axis_fifo_ram_full[0];
        mod_int_status_reg[49] <= ~u7_rx_filet.u3_rx_mux_nto1.axis_fifo_ram_empty[0];
        mod_int_status_reg[50] <= ~u7_rx_filet.u3_rx_mux_nto1.axis_fifo_eop_empty[0];
        mod_int_status_reg[51] <= u7_rx_filet.u3_rx_mux_nto1.axis_fifo_ram_full[1];
        mod_int_status_reg[52] <= ~u7_rx_filet.u3_rx_mux_nto1.axis_fifo_ram_empty[1];
        mod_int_status_reg[53] <= ~u7_rx_filet.u3_rx_mux_nto1.axis_fifo_eop_empty[1];
        mod_int_status_reg[54] <= u9_qdma_top.u1_qdma_function.qid_fifo_full;
        mod_int_status_reg[55] <= ~u9_qdma_top.u1_qdma_function.qid_fifo_empty;
        mod_int_status_reg[56] <= u9_qdma_top.u1_qdma_function.axis_fifo_u.ram_full;
        mod_int_status_reg[57] <= ~u9_qdma_top.u1_qdma_function.axis_fifo_u.ram_empty;
        mod_int_status_reg[58] <= u9_qdma_top.u1_qdma_function.axis_fifo_u.eop_empty;
    end
   

    function [1:0] eop_num;
        input [16:0] frame;
        integer i;
        begin : swap
            eop_num = 0 ;
            for (i=0;i<16;i=i+1)begin
                if(frame[i] && ~frame[i+1]) 
                    eop_num = eop_num + 1;
            end  
        end
    endfunction



`else // !`ifndef PCIE_GEN5X16

/*****************************************************************************\
*                                                                             *
*                  PCIE GEN5x16 DMA and PIO                                   *
*                                                                             *
\*****************************************************************************/ 

   wire 					 csr_axi_lite_awvalid  ;
   wire 					 csr_axi_lite_awready  ;
   wire [28:0] 				 csr_axi_lite_awaddr   ;

   wire 					 csr_axi_lite_wvalid   ;
   wire 					 csr_axi_lite_wready   ;
   wire [63:0] 				 csr_axi_lite_wdata    ;
   wire [7:0] 				 csr_axi_lite_wstrb    ;
   
   wire 					 csr_axi_lite_bvalid   ;
   wire 					 csr_axi_lite_bready   ;
   wire [1:0] 				 csr_axi_lite_bresp    ;

   wire 					 csr_axi_lite_arvalid  ;
   wire 					 csr_axi_lite_arready  ;
   wire [28:0] 				 csr_axi_lite_araddr   ;
         
   wire 					 csr_axi_lite_rvalid   ;
   wire 					 csr_axi_lite_rready   ;
   wire [63:0] 				 csr_axi_lite_rdata    ;

   wire [1:0] 				 csr_axi_lite_rresp    ;
   wire [2:0] 				 csr_axi_lite_awprot   ;
   wire [2:0] 				 csr_axi_lite_arprot   ;

   pcie5x16_axis_dma
     U_pci5_top(
                .PCIE0_GT_0_grx_n          (PCIE0_GT_0_grx_n        ), 
                .PCIE0_GT_0_grx_p          (PCIE0_GT_0_grx_p        ),
                .PCIE0_GT_0_gtx_n          (PCIE0_GT_0_gtx_n        ),
                .PCIE0_GT_0_gtx_p          (PCIE0_GT_0_gtx_p        ),
                
                .PCIE0_GT_0_clk_p          (PCIE0_GT_0_clk_p        ),
                .PCIE0_GT_1_clk_p          (PCIE0_GT_1_clk_p        ),
                
                .pcie_reset_n              (pcie_reset_n            ),
                
                .clk250m                   (clk250m                 ),
                .sys_rst                   (sys_rst                 ),
                
                .axi_st_app_clk            (pcie_app_clk            ),
                .pcie_app_rst              (pcie_app_rst            ),
                
                .h2d_axi_st_tvalid         (                        ),
                .h2d_axi_st_tready         (                        ),
                .h2d_axi_st_tdata          (                        ),
                .h2d_axi_st_tkeep          (                        ),
                .h2d_axi_st_tlast          (                        ),
                .h2d_axi_st_tuser_metadata (                        ),
                .h2d_axi_st_tid            (                        ),
                .h2d_axi_st_tuser_error    (                        ),
                
                .d2h_axi_st_tvalid         (                        ),
                .d2h_axi_st_tready         (                        ),
                .d2h_axi_st_tdata          (                        ),
                .d2h_axi_st_tkeep          (                        ),
                .d2h_axi_st_tlast          (                        ),
                .d2h_axi_st_tuser_metadata (                        ),
                .d2h_axi_st_tid            (                        ),
                .d2h_axi_st_tuser_error    (                        ),
                
                .rx_pio_axi_lite_awvalid   (csr_axi_lite_awvalid    ),
                .rx_pio_axi_lite_awready   (csr_axi_lite_awready    ),
                .rx_pio_axi_lite_awaddr    (csr_axi_lite_awaddr     ),
                
                .rx_pio_axi_lite_wvalid    (csr_axi_lite_wvalid     ),
                .rx_pio_axi_lite_wready    (csr_axi_lite_wready     ),
                .rx_pio_axi_lite_wdata     (csr_axi_lite_wdata      ),
                .rx_pio_axi_lite_wstrb     (csr_axi_lite_wstrb      ),
                
                .rx_pio_axi_lite_bvalid    (csr_axi_lite_bvalid     ),
                .rx_pio_axi_lite_bready    (csr_axi_lite_bready     ),
                .rx_pio_axi_lite_bresp     (csr_axi_lite_bresp      ),
                
                .rx_pio_axi_lite_arvalid   (csr_axi_lite_arvalid    ),
                .rx_pio_axi_lite_arready   (csr_axi_lite_arready    ),
                .rx_pio_axi_lite_araddr    (csr_axi_lite_araddr     ),
                
                .rx_pio_axi_lite_rvalid    (csr_axi_lite_rvalid     ),
                .rx_pio_axi_lite_rready    (csr_axi_lite_rready     ),
                .rx_pio_axi_lite_rdata     (csr_axi_lite_rdata      ),
                
                .rx_pio_axi_lite_rresp     (csr_axi_lite_rresp      ),
                .rx_pio_axi_lite_awprot    (csr_axi_lite_awprot     ),
                .rx_pio_axi_lite_arprot    (csr_axi_lite_arprot     ),
                
                .pcie_linkup               (                        ),  
                .pcie_data_linkup          (                        )
               );
                  
/*****************************************************************************\
*                                                                             *
*                  csr_pro for AXI_LITE                                       *
*                                                                             *
\*****************************************************************************/ 
   csr_pro 
     U_csr_pro (                                                                                      
                .rst                       (sys_rst                  ),                                                               
                .clk                       (clk250m                  ),                                                             
                .pcie_link_up              (1'b1                     ),                                                               
                                                                                 
                .m_axil_awaddr             (csr_axi_lite_awaddr      ),
                .m_axil_awvalid            (csr_axi_lite_awvalid     ),
                .m_axil_awready            (csr_axi_lite_awready     ),
                                                                     
                .m_axil_wdata              (csr_axi_lite_wdata       ),
                .m_axil_wstrb              (csr_axi_lite_wstrb       ),
                .m_axil_wvalid             (csr_axi_lite_wvalid      ),
                .m_axil_wready             (csr_axi_lite_wready      ),
                                                                     
                .m_axil_bvalid             (csr_axi_lite_bvalid      ),
                .m_axil_bresp              (csr_axi_lite_bresp       ),
                .m_axil_bready             (csr_axi_lite_bready      ),
                                                                     
                .m_axil_araddr             (csr_axi_lite_araddr      ),
                .m_axil_arvalid            (csr_axi_lite_arvalid     ),
                .m_axil_arready            (csr_axi_lite_arready     ),
                                                                     
                .m_axil_rdata              (csr_axi_lite_rdata       ),
                .m_axil_rresp              (csr_axi_lite_rresp       ),
                .m_axil_rvalid             (csr_axi_lite_rvalid      ),
                .m_axil_rready             (csr_axi_lite_rready      ),
                                                                     
                .sir_sel                   (sir_sel                  ),                                                               
                .sir_addr                  (sir_addr                 ),                                                               
                .sir_read                  (sir_read                 ),                                                               
                .sir_wdat                  (sir_wdat                 ),                                                               
                .sir_rdat                  (sir_rdat                 ),                                                               
                .sir_dack                  (sir_dack                 )
); 
   
`endif // !`ifndef PCIE_GEN5X16
   

/*****************************************************************************\
*                                                                             *
*                  eth400G interface                                          *
*                                                                             *
\*****************************************************************************/
   wire 					 eth_rx_rst_ack;
   wire 					 eth_tx_rst_ack;
   wire 					 eth_all_rst;
   wire 					 eth_all_rst_ack;

   wire 					 eth_cdr_lock;
   wire 					 eth_tx_pll_locked;
   wire 					 eth_tx_lanes_stable;
   wire 					 eth_sys_pll_locked;
   
   wire 					 eth_rx_block_lock;
   wire 					 eth_rx_am_lock;
   wire 					 eth_local_fault_status;
   wire 					 eth_remote_fault_status;
   wire 					 eth_rx_hi_ber;
   wire 					 eth_rx_pcs_fully_aligned;
   
   (* keep *) wire rx_inframes_zero = rx_mac_inframe == 16'h0000;
   
   wire  [31:0]              eth_cfg_addr       ;
   wire                      eth_cfg_read       ;  
   wire                      eth_cfg_write      ;  
   wire [31:0]               eth_cfg_wdat       ;
   wire [3:0]                eth_cfg_byte       ;
   wire [31:0]               eth_cfg_rdat       ;
   wire                      eth_cfg_rvld       ;  
   wire                      eth_cfg_wait_req   ;  
   
   wire	[31:0]				 eth_system_stat	;
   
   assign	eth_system_stat[31:11] 	= 'b0;
   assign 	eth_system_stat[10]		= eth_rx_block_lock;
   assign 	eth_system_stat[9] 		= eth_rx_am_lock;
   assign 	eth_system_stat[8] 		= eth_local_fault_status;
   assign 	eth_system_stat[7] 		= eth_remote_fault_status;
   assign 	eth_system_stat[6] 		= eth_rx_hi_ber;
   assign 	eth_system_stat[5] 		= eth_rx_pcs_fully_aligned;
   assign 	eth_system_stat[4] 		= eth_cdr_lock;
   assign 	eth_system_stat[3] 		= eth_tx_pll_locked;
   assign 	eth_system_stat[2] 		= eth_tx_lanes_stable;
   assign 	eth_system_stat[1] 		= eth_sys_pll_locked;
   assign 	eth_system_stat[0] 		= eth_rx_pcs_ready;
   
   eth400g_top
     U_eth400g(
              .eth_gt_fht_clk             (eth_gt_fht_clk          ),
              .eth_gt_fgt_clk             (eth_gt_fgt_clk          ),
              
              .eth_gt_rxn                 (eth_gt_rxn_in           ),
              .eth_gt_rxp                 (eth_gt_rxp_in           ),
              
              .eth_gt_txn                 (eth_gt_txn_out          ),
              .eth_gt_txp                 (eth_gt_txp_out          ),

              .i_rx_rst                   (eth_rx_rst              ),  
              .o_rx_rst_ack               (eth_rx_rst_ack          ),
              
              .i_tx_rst                   (eth_tx_rst              ), 
              .o_tx_rst_ack               (eth_tx_rst_ack          ),
              
              .i_rst                      (eth_all_rst             ),  
              .o_rst_ack                  (eth_all_rst_ack         ),

              .eth_cdr_lock               (eth_cdr_lock            ),   
              .eth_tx_pll_locked          (eth_tx_pll_locked       ),
              .eth_tx_lanes_stable        (eth_tx_lanes_stable     ),
              .eth_sys_pll_locked         (eth_sys_pll_locked      ),
              .eth_rx_pcs_ready           (eth_rx_pcs_ready        ),
              
              .eth_rx_block_lock          (eth_rx_block_lock       ),
              .eth_rx_am_lock             (eth_rx_am_lock          ),
              .eth_local_fault_status     (eth_local_fault_status  ),
              .eth_remote_fault_status    (eth_remote_fault_status ),
              .eth_rx_hi_ber              (eth_rx_hi_ber           ),
              .eth_rx_pcs_fully_aligned   (eth_rx_pcs_fully_aligned),
              
              .avmm_cfg_rst               (sys_rst                 ),
              .avmm_cfg_clk               (clk250m                 ),
              .avmm_cfg_addr              (eth_cfg_addr[23:0]      ),
              .avmm_cfg_read              (eth_cfg_read            ),
              .avmm_cfg_write             (eth_cfg_write           ),
              .avmm_cfg_wdat              (eth_cfg_wdat[31:0]      ),
              .avmm_cfg_byte              (eth_cfg_byte[3:0]       ),
              .avmm_cfg_rdat              (eth_cfg_rdat[31:0]      ),
              .avmm_cfg_rvld              (eth_cfg_rvld            ),
              .avmm_cfg_wait_req          (eth_cfg_wait_req        ),

              .i_reconfig_clk			  (clk250m				   ),
              .eth_mac_clk                (eth_mac_clk             ),
             
              .i_tx_mac_data              (gap_to_mac_tdata        ),  
              .i_tx_mac_valid             (gap_to_mac_tvalid       ),
              .i_tx_mac_inframe           (gap_to_mac_frame        ),
              .i_tx_mac_eop_empty         (gap_to_mac_emty         ),
              .o_tx_mac_ready             (gap_to_mac_tready       ),
              .i_tx_mac_error             (16'd0                   ),
              .i_tx_mac_skip_crc          (16'd0                   ),

              .o_rx_mac_data              (rx_mac_data             ), 
              .o_rx_mac_valid             (rx_mac_valid            ),
              .o_rx_mac_inframe           (rx_mac_inframe          ),
              .o_rx_mac_eop_empty         (rx_mac_eop_empty        ),
              .o_rx_mac_error             (rx_mac_error            ),
              .o_rx_mac_fcs_error         (rx_mac_fcs_error        ),
              .o_rx_mac_status            (rx_mac_status           )
              );

 /*****************************************************************************\
*                                                                             *
*                  eth400g csr interface                                      *
*                                                                             *
\*****************************************************************************/   
   wire                      eth_ctl_req;
   wire 					 eth_ctl_rwn;
   wire [31:0] 				 eth_ctl_addr;
   wire [31:0] 				 eth_ctl_wdat;
   wire [3:0] 				 eth_ctl_byte;
   wire [31:0] 				 eth_ctl_rdat;
   wire 					 eth_ctl_ack;

   mb_ctl
     U_eth_ctl(
              .rst                       (sys_rst                ),
              .clk                       (clk250m                ),
             
              //mailbox controller csr                                 
              .mb_ctl_req                (eth_ctl_req            ),
              .mb_ctl_rwn                (eth_ctl_rwn            ),
              .mb_ctl_addr               (eth_ctl_addr           ),
              .mb_ctl_wdat               (eth_ctl_wdat           ),
              .mb_ctl_byte				 (eth_ctl_byte			 ),
              .mb_ctl_rdat               (eth_ctl_rdat           ),
              .mb_ctl_ack                (eth_ctl_ack            ),
              .mb_ctl_irq                (                       ),
              
              .sdm_mb_addr               (eth_cfg_addr[31:0]     ),
              .sdm_mb_byte               (eth_cfg_byte[3:0]      ),
              .sdm_mb_wdat               (eth_cfg_wdat[31:0]     ),
              .sdm_mb_write              (eth_cfg_write          ),
              .sdm_mb_read               (eth_cfg_read           ),
              .sdm_mb_rdat               (eth_cfg_rdat[31:0]     ),
              .sdm_mb_rvld               (eth_cfg_rvld           ),
              .sdm_mb_wait_req           (eth_cfg_wait_req       ),
              .sdm_mb_irq                (1'd0                   )
              );
   
    
/*****************************************************************************\
*                                                                             *
*                  eth400g pkt_generate                                       *
*                                                                             *
\*****************************************************************************/

    

   reg 						 eth_tx_ack;
   reg 						 eth_tx_ack_p2;
   
   //eth_tx_ack cross eth_mac_clk to clk250m
   always @ (posedge clk250m) eth_tx_ack_p2 <= eth_tx_ack_p;
   always @ (posedge clk250m) eth_tx_ack    <= eth_tx_ack_p2;

/*****************************************************************************\
*                                                                             *
*                  i2c_m_cpld                                                        *
*                                                                             *
\*****************************************************************************/
  
wire				i2c_m_cpld_sel		;
wire				i2c_m_cpld_rw		;
wire	[4:0]		i2c_m_cpld_dlen		;
wire	[2:0]		i2c_m_cpld_mode		;
wire	[31:0]		i2c_m_cpld_addr		;
wire	[6:0]		i2c_m_cpld_dev_id	;
wire	[127:0]		i2c_m_cpld_data		;
wire	[127:0]		i2c_m_cpld_rdata	;
wire				i2c_m_cpld_done		;
wire				i2c_m_cpld_ack		;

//cpld 
sir_i2c_top#(
            .DONE_WAIT_TIME ( 18'd1500 ),
            .CLK_PERIOD     ( 12'd250  )
            )
            U_cpld_i2c_top(
            .clk            (clk250m           		),
            .rst            (sys_rst           		),
            
            .i2c_sel        (i2c_m_cpld_sel	   		),
            .i2c_rw_ctl     (i2c_m_cpld_rw			),
            .i2c_dlen       (i2c_m_cpld_dlen	   	),
            .i2c_mode       (i2c_m_cpld_mode	   	),
            .i2c_addr       (i2c_m_cpld_addr	   	),
            .i2c_dev_id     (i2c_m_cpld_dev_id   	),
            .i2c_wdata      (i2c_m_cpld_data	   	),
            .i2c_rdata      (i2c_m_cpld_rdata	   	),
            .i2c_done       (i2c_m_cpld_done	   	),
            .i2c_ack        (i2c_m_cpld_ack	   		),
        
            .scl         	(i2c_m_fpga_scl        	),
            .sda         	(i2c_m_fpga_sda        	)
);


/*****************************************************************************\
*                                                                             *
*                  mailbox for update fpga version to SDM flash               *
*                                                                             *
*                                                                             *
\*****************************************************************************/
   wire [3:0] 				 csr_mb_addr;
   wire 					 csr_mb_write;
   wire [31:0] 				 csr_mb_wdat;
   wire 					 csr_mb_read;
   reg  [31:0] 				 csr_mb_rdat;
   reg  					 csr_mb_rvld;
   reg  					 csr_mb_wait;
   reg  					 csr_mb_irq;
   wire						 csr_mb_rst;	
   
   reg  [3:0] 				 sdm_mb_addr;
   reg  					 sdm_mb_write;
   reg  [31:0] 				 sdm_mb_wdat;
   reg  					 sdm_mb_read;
   wire [31:0] 				 sdm_mb_rdat;
   wire 					 sdm_mb_rvld;
   wire 					 sdm_mb_wait;
   wire 					 sdm_mb_irq;
   reg 						 sdm_mb_rst;
  
   wire [3:0] 				 avm_mb_addr;
   wire  					 avm_mb_write;
   wire [31:0] 				 avm_mb_wdat;
   wire  					 avm_mb_read;
   wire [31:0] 				 avm_mb_rdat;
   wire 					 avm_mb_rvld;
   wire 					 avm_mb_wait;
   wire 					 avm_mb_irq; 



    qspi_flash_ctl u30_read_macks(
        .clk( clk250m  ),
        .rst_n(!sys_rst ),
        // AVM Slave Interface
        .s_avm_addr ( user_avm_addr[5*28 +: 28] ) ,
        .s_avm_read ( user_avm_read [5]         ) ,
        .s_avm_write( user_avm_write[5]         ),
        .s_avm_wdat ( user_avm_wdat [5*32 +:32] ) ,
        .s_avm_wait ( user_avm_wait [5]         ) ,
        .s_avm_rdat ( user_avm_rdat [5*32 +:32] ) ,
        .s_avm_rvld ( user_avm_rvld [5]         ) ,
        .s_avm_rspo ( user_avm_rspo [5*2 +:2]   ) ,
        .s_avm_wrsp ( user_avm_wrsp [5]         ) ,

        // AVM Slave Interface from csr_pm to Mailbox
        .s_csr20_addr ( sdm_mb_addr ),       
        .s_csr20_write( sdm_mb_write ),         
        .s_csr20_wdat ( sdm_mb_wdat ),     
        .s_csr20_read ( sdm_mb_read ),          
        .s_csr20_rdat ( sdm_mb_rdat ),      
        .s_csr20_rvld ( sdm_mb_rvld ), 
        .s_csr20_wait ( sdm_mb_wait ),
        .s_csr20_irq  ( sdm_mb_irq  ),   
    

        // AVM Master Interface to Mailbox
        .m_avm_addr ( avm_mb_addr ),
        .m_avm_write( avm_mb_write),
        .m_avm_read ( avm_mb_read ),
        .m_avm_wdat ( avm_mb_wdat ),
        .m_avm_rdat ( avm_mb_rdat ),
        .m_avm_wait ( avm_mb_wait ),
        .m_avm_rvld ( avm_mb_rvld ),
        .m_avm_irq  ( avm_mb_irq)
    );
   

   mailbox 
     U_mailbox(
               .in_clk_clk               (clk250m                ),         
               .in_reset_reset           (sys_rst|sdm_mb_rst     ),
               
               .avmm_address             (avm_mb_addr[3:0]       ),       
               .avmm_write               (avm_mb_write           ),         
               .avmm_writedata           (avm_mb_wdat[31:0]      ),     
               .avmm_read                (avm_mb_read            ),          
               .avmm_readdata            (avm_mb_rdat[31:0]      ),      
               .avmm_readdatavalid       (avm_mb_rvld            ), 
               .avmm_waitrequest         (avm_mb_wait            ),   
               .irq_irq                  (avm_mb_irq             )             
               );         
               
/*****************************************************************************\
*                                                                             *
*                  i2c_s_cpld                                                        *
*                                                                             *
\*****************************************************************************/

wire				mb_mon_req		;
wire	[7:0]		mb_mon_time		;
  
wire	[3:0]		i2c_mb_addr		;
wire	[31:0]		i2c_mb_wdat		;
wire				i2c_mb_write	;
wire				i2c_mb_read		;
reg 	[31:0]		i2c_mb_rdat		;
reg 				i2c_mb_rvld		;
reg 				i2c_mb_wait		;
wire				i2c_mb_rst		;

wire	[31:0]		ID_CODE			;
wire	[63:0]		CHIP_ID			;
wire	[31:0]		TEMP_LOC0_0		;
wire	[31:0]		TEMP_LOC1_0		;
wire	[31:0]		TEMP_LOC1_1		;
wire	[31:0]		TEMP_LOC2_0		;
wire	[31:0]		TEMP_LOC2_1		;
wire	[31:0]		TEMP_LOC3_0		;
wire	[31:0]		TEMP_LOC3_1		;
wire	[31:0]		TEMP_LOC4_0		;
wire	[31:0]		TEMP_LOC4_1		;
wire	[31:0]		VCC				;
wire	[31:0]		VCCIO_SDM		;
wire	[31:0]		VCCPT			;
wire	[31:0]		VCCRCORE		;
wire	[31:0]		VCCH_SDM		;
wire	[31:0]		VCCL_SDM		;
wire	[31:0]		VCCADC			;

always @(*)
begin
    if(mb_mon_req)
    begin
        sdm_mb_addr 	<= i2c_mb_addr;
        sdm_mb_write	<= i2c_mb_write;
        sdm_mb_read		<= i2c_mb_read;
        sdm_mb_wdat		<= i2c_mb_wdat;
        sdm_mb_rst		<= i2c_mb_rst;
    end
    else
    begin
        sdm_mb_addr		<= csr_mb_addr;
        sdm_mb_write	<= csr_mb_write;
        sdm_mb_read		<= csr_mb_read;
        sdm_mb_wdat		<= csr_mb_wdat;
        sdm_mb_rst		<= csr_mb_rst;
    end
    
    i2c_mb_wait		<= sdm_mb_wait;
    i2c_mb_rvld		<= sdm_mb_rvld;
    i2c_mb_rdat		<= sdm_mb_rdat;

    csr_mb_wait		<= sdm_mb_wait;
    csr_mb_rvld		<= sdm_mb_rvld;
    csr_mb_rdat		<= sdm_mb_rdat;
    csr_mb_irq		<= sdm_mb_irq;
    
end

/***************************************************/
wire			beat_1s;
wire			beat_1ms;
reg 			mon_time;

beat_time #(
    .BEAT_100US_CNT (15'd24999	),//250M
    .BEAT_1US_CNT	(15'd249	) )
    U_beat_time (
    .clk                ( clk250m		),  
    .locked             ( locked		), 

    .beat_1us           ( beat_1us		), 
    .beat_100us         ( beat_100us 	), 
    .beat_1ms           ( beat_1ms		), 
    .beat_1s            ( beat_1s		)
);

always @(posedge clk250m)
begin
    if(mb_mon_time == 1'b0)
        mon_time	<= beat_1s;
    else	
        mon_time	<= beat_1ms;
end
    
//cpld 
mb_acquire	
        U_mb_acquire(
            .clk            (clk250m           		),
            .reset          (sys_rst           		),
            
            .req_enb		(mb_mon_req				),
            .req_time		(mon_time				),
            
            .mb_addr		(i2c_mb_addr			),
            .mb_wdat		(i2c_mb_wdat			),
            .mb_write		(i2c_mb_write			),
            .mb_read        (i2c_mb_read			),
            .mb_rdat        (i2c_mb_rdat			),
            .mb_rvld        (i2c_mb_rvld			),
            .mb_wait        (i2c_mb_wait			),
            .mb_rst         (i2c_mb_rst				),
            
            .ID_CODE		(ID_CODE				),
            .CHIP_ID        (CHIP_ID    			),
            .TEMP_LOC0_0    (TEMP_LOC0_0			),
            .TEMP_LOC1_0    (TEMP_LOC1_0			),
            .TEMP_LOC1_1    (TEMP_LOC1_1			),
            .TEMP_LOC2_0    (TEMP_LOC2_0			),
            .TEMP_LOC2_1    (TEMP_LOC2_1			),
            .TEMP_LOC3_0    (TEMP_LOC3_0			),
            .TEMP_LOC3_1    (TEMP_LOC3_1			),
            .TEMP_LOC4_0    (TEMP_LOC4_0			),
            .TEMP_LOC4_1    (TEMP_LOC4_1			),
            .VCC            (VCC        			),
            .VCCIO_SDM      (VCCIO_SDM  			),
            .VCCPT          (VCCPT      			),
            .VCCRCORE       (VCCRCORE   			),
            .VCCH_SDM       (VCCH_SDM   			),
            .VCCL_SDM		(VCCL_SDM				),
            .VCCADC         (VCCADC     			)
);

iic_slave_top	
            U_iic_slave_top(
            .clk			(clk250m			),
            .rst			(sys_rst			),
            
            .iic_scl		(i2c_s_fpga_scl		),
            .iic_sda		(i2c_s_fpga_sda		),
            .iic_busy		(),

            .ID_CODE		(ID_CODE			),
            .CHIP_ID        (CHIP_ID    		),
            .TEMP_LOC0_0    (TEMP_LOC0_0		),
            .TEMP_LOC1_0    (TEMP_LOC1_0		),
            .TEMP_LOC1_1    (TEMP_LOC1_1		),
            .TEMP_LOC2_0    (TEMP_LOC2_0		),
            .TEMP_LOC2_1    (TEMP_LOC2_1		),
            .TEMP_LOC3_0    (TEMP_LOC3_0		),
            .TEMP_LOC3_1    (TEMP_LOC3_1		),
            .TEMP_LOC4_0    (TEMP_LOC4_0		),
            .TEMP_LOC4_1    (TEMP_LOC4_1		),
            .VCC            (VCC        		),
            .VCCIO_SDM      (VCCIO_SDM  		),
            .VCCPT          (VCCPT      		),
            .VCCRCORE       (VCCRCORE   		),
            .VCCH_SDM       (VCCH_SDM   		),
            .VCCL_SDM       (VCCL_SDM			),	
            .VCCADC  		(VCCADC				)                  
); 

/*****************************************************************************\
*                                                                             *
*                  CSR                                                        *
*                                                                             *
\*****************************************************************************/   
   csr_pm
     U_csr_pm(
              .Rst                        (pcie_app_rst            ),          
              .HardRst                    (pcie_app_rst            ),

              .Gclk125m                   (clk250m                 ),
              .Gclk250m                   (clk250m                 ),

              .SirSel                     (sir_sel                 ),
              .SirAddr                    (sir_addr[31:0]          ),
              .SirRead                    (sir_read                ),
              .SirWdat                    (sir_wdat[31:0]          ),
              .SirRdat                    (sir_rdat[31:0]          ),
              .SirDackh                   (sir_dack                ),

              //csr11/12/14
              .DcmLock                    ('d0                     ),
              .Dimm0InitDone              ('d0                     ),
              .TestData                   (                        ),
              .ErrMsg                     (32'h0                   ),
              .SoftFpgaRstVal             (soft_rst_val            ),
              .SoftFpgaRstClr             (soft_rst_clr            ),

              //csr20
              .sdm_mb_addr                (csr_mb_addr             ), 
              .sdm_mb_wdat                (csr_mb_wdat             ),
              .sdm_mb_write               (csr_mb_write            ),
              .sdm_mb_read                (csr_mb_read             ),
              .sdm_mb_rdat                (csr_mb_rdat             ),
              .sdm_mb_rvld                (csr_mb_rvld             ),
              .sdm_mb_wait                (csr_mb_wait             ),
              .sdm_mb_irq                 (csr_mb_irq              ),
              .sdm_mb_status              (24'h0                   ),
              .sdm_mb_rst				  (csr_mb_rst			   ),
              
              .mb_mon_req				  (mb_mon_req			   ),
              .mb_mon_time				  (mb_mon_time			   ),
              //csr11
              .eth_ctl_req                (eth_ctl_req   		   ),
              .eth_ctl_rwn                (eth_ctl_rwn   		   ),
              .eth_ctl_addr               (eth_ctl_addr  		   ),
              .eth_ctl_wdat               (eth_ctl_wdat  		   ),
              //.eth_ctl_byte               (eth_ctl_byte  		   ),
              .eth_ctl_rdat               (eth_ctl_rdat  		   ),
              .eth_ctl_ack                (eth_ctl_ack   		   ),
              .eth_ctl_status             (32'h0				   ),
              
              //csr11
              .eth_tx_req                 (eth_tx_req              ),
              .eth_tx_mod                 (eth_tx_mod[3:0]         ),
              .eth_tx_num                 (eth_tx_num[31:0]        ),
              .eth_tx_stop                (eth_tx_stop             ),
              .eth_tx_ack                 (eth_tx_ack              ),
              .tx_crc_err                 (tx_crc_err              ),
              
              .eth_all_rst				  (eth_all_rst				),
              .eth_all_rst_ack			  (eth_all_rst_ack			),
              .eth_tx_rst				  (eth_tx_rst				),
              .eth_tx_rst_ack			  (eth_tx_rst_ack			),
              .eth_rx_rst				  (eth_rx_rst				),
              .eth_rx_rst_ack			  (eth_rx_rst_ack			),
                                            
              .eth_cdr_lock				  (eth_cdr_lock				),        
              .eth_tx_pll_locked		  (eth_tx_pll_locked		),               
              .eth_tx_lanes_stable		  (eth_tx_lanes_stable		),             
              .eth_sys_pll_locked		  (eth_sys_pll_locked		),              
              .eth_rx_pcs_ready			  (eth_rx_pcs_ready			),                
              .eth_rx_block_lock		  (eth_rx_block_lock		),               
              .eth_rx_am_lock			  (eth_rx_am_lock			),                 
              .eth_local_fault_status	  (eth_local_fault_status	),          
              .eth_remote_fault_status	  (eth_remote_fault_status	),         
              .eth_rx_hi_ber			  (eth_rx_hi_ber			),                 
              .eth_rx_pcs_fully_aligned	  (eth_rx_pcs_fully_aligned	),
                                          
              .opt_mod_los				  (opt_mod_los				),
              .opt_mod_pst				  (opt_mod_pst				),
              .opt_mod_lpm				  (opt_mod_lpm				),
              .opt_mod_rst				  (opt_mod_rst				),
              
              //csr110
              .test_enb					  (test_enb   			   ),
              .test_type				  (test_type  			   ),
              .test_wr				  	  (test_wr    			   ),
              .test_done				  (test_done_d2			   ),
              .err_flag                   (err_flag_d2 			   ),
              .err_cnt                    (err_cnt_d2  			   ),
              .rd_addr					  (rd_addr_d2			   ),
              .rd_done					  (rd_done_d2			   ),
              .DDR_END_ADDR				  (DDR_END_ADDR			   ),
              
              .addr_mode                  (addr_mode  			   ),
              .addr_seed                  (addr_seed  			   ),
                                                                   
              .dat_mode                   (dat_mode   			   ),
              .ddr_dat0                   (ddr_dat0				   ),
              .ddr_dat1                   (ddr_dat1				   ),
              .ddr_dat2                   (ddr_dat2   			   ),
              .ddr_dat3                   (ddr_dat3   			   ),
                                                  
              .total_time_w               (total_time_w_d2		   ),
              .total_cnt_w                (total_cnt_w_d2	   	   ),
              .total_time_r		     	  (total_time_r_d2		   ),
              .total_cnt_r				  (total_cnt_r_d2		   ),
               
              .ddr4_cal_sucess			  (ddr4_cal_sucess_d2	   ),
              .ddr4_cal_fail			  (ddr4_cal_fail_d2		   ),
               
              .ddr_ctl_req                (ddr_ctl_req   		   ),
              .ddr_ctl_rwn                (ddr_ctl_rwn   		   ),
              .ddr_ctl_addr               (ddr_ctl_addr  		   ),
              .ddr_ctl_wdat               (ddr_ctl_wdat  		   ),
              //.ddr_ctl_byte               (ddr_ctl_byte  		   ),
              .ddr_ctl_rdat               (ddr_ctl_rdat  		   ),
              .ddr_ctl_ack                (ddr_ctl_ack   		   ),
              
              //csr40
              .i2c_m_cpld_sel			  (i2c_m_cpld_sel		   ),	
              .i2c_m_cpld_rw              (i2c_m_cpld_rw		   ),
              .i2c_m_cpld_dlen            (i2c_m_cpld_dlen		   ),
              .i2c_m_cpld_mode            (i2c_m_cpld_mode		   ),
              .i2c_m_cpld_addr            (i2c_m_cpld_addr		   ),
              .i2c_m_cpld_dev_id          (i2c_m_cpld_dev_id	   ),
              .i2c_m_cpld_data            (i2c_m_cpld_data		   ),
              .i2c_m_cpld_rdata           (i2c_m_cpld_rdata		   ),
              .i2c_m_cpld_done            (i2c_m_cpld_done		   ),
              .i2c_m_cpld_ack             (i2c_m_cpld_ack		   ),
              
              //csr0f
              .IbusStatSel                (                        ),
              .IbusStatRead               (                        ),
              .IbusStatAddr               (                        ),
              .IbusStatWdat               (                        ),
              .IbusStatRdat               (                        ),
              .IbusStatDack               (                        ),
              .StatClrReq                 (                        ),
              .StatClrOver                (1'd0                    )
              );

  
          
endmodule // YuanRDMA
