`resetall
`default_nettype none
`include "global_define.vh"
`define PCIE_GEN5X16

module YuanRDMA (
   //pcie interface
   input  wire [15:0] 		 PCIE0_GT_0_grx_n    ,
   input  wire [15:0] 		 PCIE0_GT_0_grx_p    ,
   output wire [15:0] 		 PCIE0_GT_0_gtx_n    ,
   output wire [15:0] 		 PCIE0_GT_0_gtx_p    ,

   input wire  			 pcie_reset_n        , 

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
   
   //16bits ddr4 for HPS 
   output wire [0:0] 		 c0_ddr4_act_n       ,
   output wire [16:0] 		 c0_ddr4_adr         ,
   input  wire [0:0] 		 c0_ddr4_alert_n     ,
   output wire [1:0] 		 c0_ddr4_ba          ,
   output wire [0:0] 		 c0_ddr4_bg          ,
   output wire [0:0] 		 c0_ddr4_ck_c        ,
   output wire [0:0] 		 c0_ddr4_ck_t        ,
   output wire [0:0] 		 c0_ddr4_cke         ,
   output wire [0:0] 		 c0_ddr4_cs_n        ,
   output wire [0:0] 		 c0_ddr4_odt         ,
   inout  wire [1:0] 		 c0_ddr4_dm_n        ,
   inout  wire [15:0] 		 c0_ddr4_dq          ,
   inout  wire [1:0] 		 c0_ddr4_dqs_c       ,
   inout  wire [1:0] 		 c0_ddr4_dqs_t       ,
   output wire [0:0] 		 c0_ddr4_par         ,
   output wire [0:0] 		 c0_ddr4_reset_n     ,
   
   input  wire [0:0] 		 c0_oct_oct_rzqin    ,

   //ddr4 reference clock 200M
   input  wire [0:0] 		 c0_sys_clk_p        ,

   //fpga core reference clock 200M
   input  wire 				 pl_clk_p            ,
   //fpga core reset
   input  wire 				 ex_reset_n          ,

   //optical module i2c 
   inout  wire 				 i2c_opt_scl0        ,
   inout  wire 				 i2c_opt_sda0        ,

   inout  wire 				 i2c_opt_scl1        ,
   inout  wire 				 i2c_opt_sda1        ,

   input  wire 				 opt_mod_los         ,
   input  wire 				 opt_mod_pst         ,//present
   output wire 				 opt_mod_lpm         ,//low power mode
   output wire 	 			 opt_mod_rst         ,//

   //CPLD 
   input  wire 				 i2c_s_fpga_scl      ,//slave
   inout  wire 				 i2c_s_fpga_sda      ,//slave

   output reg  [7:0] 		 fpga_cpld_gpio      ,
                        
   inout  wire 				 i2c_m_fpga_scl      ,//master
   inout  wire 				 i2c_m_fpga_sda       //master
                   );

/*****************************************************************************\
*                                                                             *
*                  clk & rst module for system                                *
*                                                                             *
*                                                                             *
\*****************************************************************************/

   wire 					 clk250m;
   wire 					 clk100m;
   wire 					 clk50m;
   wire 					 locked;
   wire  [7:0]               soft_rst_val;
   wire                      soft_rst_clr;
   wire						 sys_rst;
`ifndef SIMULATION 
   clk200m
     U_clk200m(
               .refclk                   (pl_clk_p                ),
               
               .rst                      (~ex_reset_n             ),

               .outclk_0                 (clk250m                 ),
               .outclk_1                 (clk100m                 ),
               .outclk_2                 (clk50m                  ),

               .locked                   (locked                  )
               );

   rst
     U_rstm (
             .clk                        ( clk250m                ), 
             .ex_reset_n                 ( ex_reset_n             ),
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


    localparam                  AVM_USER_NUM= 6;

    (* keep *) wire                        pcie2cdc_avm_wait;
    (* keep *) wire [27:0]                 pcie2cdc_avm_addr;
    (* keep *) wire [7:0]                  pcie2cdc_avm_byte;
    (* keep *) wire                        pcie2cdc_avm_read;
    (* keep *) wire [63:0]                 pcie2cdc_avm_rdat;
    (* keep *) wire                        pcie2cdc_avm_rvld;
    (* keep *) wire                        pcie2cdc_avm_write;
    (* keep *) wire [63:0]                 pcie2cdc_avm_wdat;
    (* keep *) wire [3:0]                  pcie2cdc_avm_bcnt;
    (* keep *) wire [1:0]                  pcie2cdc_avm_rspo;
    (* keep *) wire                        pcie2cdc_avm_wrsp;
    
    (* keep *) wire                        cdc2cfg_avm_wait;
    (* keep *) wire [27:0]                 cdc2cfg_avm_addr;
    (* keep *) wire                        cdc2cfg_avm_read;
    (* keep *) wire [31:0]                 cdc2cfg_avm_rdat;
    (* keep *) wire                        cdc2cfg_avm_rvld;
    (* keep *) wire                        cdc2cfg_avm_write;
    (* keep *) wire [31:0]                 cdc2cfg_avm_wdat;
    (* keep *) wire [1:0]                  cdc2cfg_avm_rspo;
    (* keep *) wire                        cdc2cfg_avm_wrsp;

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

   //dma bus signal  
   (*keep*)  wire         d2h_st_sof_0_i    ;               //            p0_d2h_st_0.startofpacket,           Check User Guide for details
   (*keep*)  wire         d2h_st_eof_0_i    ;               //                       .endofpacket,             Check User Guide for details
   (*keep*)  wire [6:0]   d2h_st_empty_0_i  ;             //                       .empty,                   Check User Guide for details
   (*keep*)  wire [11:0]  d2h_st_channel_0_i;           //                       .channel,                 Check User Guide for details
   (*keep*)  wire         d2h_st_valid_0_i  ;             //                       .valid,                   Check User Guide for details
   (*keep*)  wire [1023:0] d2h_st_data_0_i   ;              //                       .data,                    Check User Guide for details
   (*keep*)  wire         d2h_st_ready_0_o  ;             //                       .ready,                   Check User Guide for details

   // nosue for pcie5
   


    `ifdef PCIE_GEN5X16   
    `ifndef SIMULATION
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

   (* keep *) wire           o_h2d_axi_st_tvalid        ;
   (* keep *) wire           o_h2d_axi_st_tready        ;
   (* keep *) wire [1023:0]  o_h2d_axi_st_tdata         ;
   (* keep *) wire [127:0]   o_h2d_axi_st_tkeep         ;
   (* keep *) wire           o_h2d_axi_st_tlast         ;
   (* keep *) wire [63:0]    o_h2d_axi_st_tuser_metadata;
   (* keep *) wire [11:0]    o_h2d_axi_st_tid           ;
   (* keep *) wire           o_h2d_axi_st_tuser_error   ;

   (* keep *) wire           h2d_axi_st_tvalid        ;
   (* keep *) wire           h2d_axi_st_tready        ;
   (* keep *) wire [1023:0]  h2d_axi_st_tdata         ;
   (* keep *) wire [127:0]   h2d_axi_st_tkeep         ;
   (* keep *) wire           h2d_axi_st_tlast         ;
   (* keep *) wire [63:0]    h2d_axi_st_tuser_metadata;
   (* keep *) wire [11:0]    h2d_axi_st_tid           ;
   (* keep *) wire           h2d_axi_st_tuser_error   ;
   (* keep *) wire [7:0]     h2d_axi_st_byte_num      ;
   
   (* keep *) wire          d2h_axi_st_tvalid         ;
   (* keep *) wire          d2h_axi_st_tready         ;
   (* keep *) wire [1023:0] d2h_axi_st_tdata          ;
   (* keep *) wire [127:0]  d2h_axi_st_tkeep          ;
   (* keep *) wire          d2h_axi_st_tlast          ;
   (* keep *) wire [63:0]   d2h_axi_st_tuser_metadata ;
   (* keep *) wire [11:0]   d2h_axi_st_tid            ;
   (* keep *) wire          d2h_axi_st_tuser_error    ;

   function [6:0] tkeep2empty;
    input [127:0] tkeep;
    integer i;
    begin : swap
        tkeep2empty =0;
        for (i=0;i<128;i=i+1)begin
            if( (~tkeep[i]) && (tkeep2empty == 0)) 
               tkeep2empty = 128 - i;
        end
        
    end
   endfunction

    function [6:0] tkeep2empty1;
    input [127:0] tkeep;
    integer i;
    begin : swap
        tkeep2empty1 =0;
        for (i=0;i<128;i=i+1)begin
            if(~tkeep[i]) 
               tkeep2empty1 = tkeep2empty1 + 1;
        end
        
    end
   endfunction

   function [127:0]    empty2tkeep;
        input [6:0]       data_in;
        integer i;
        begin : swap
            empty2tkeep = {128{1'b1}} >> data_in;
        end
    endfunction

   // H2D 末拍有效字节数：B6438 起由 axis_keep_pack 在输出寄存级算出（m_axis_tbyte_num），
   // 这里不再对 128 位 keep 做 popcount —— 那条组合路径是 pcie_app_clk 上的违例来源
   // （优化日志 §62.2：u82→uxx 398 端点、最差 −0.332）。编码约定见 axis_keep_pack.sv。

 

   wire axil_rst_n;
   reset_cdc #(.N(3)) u_reset_cdc(
        .s_clk(pcie_app_clk),
        .rst_n(~pcie_app_rst),
        .d_clk(clk250m),
        .m_rst_n(axil_rst_n)
   );

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
				.sys_rst                   (~axil_rst_n                 ),
				
				.axi_st_app_clk            (pcie_app_clk            ),
				.pcie_app_rst              (pcie_app_rst            ),
				
				.h2d_axi_st_tvalid         (o_h2d_axi_st_tvalid         ),
				.h2d_axi_st_tready         (o_h2d_axi_st_tready         ),
				.h2d_axi_st_tdata          (o_h2d_axi_st_tdata          ),
				.h2d_axi_st_tkeep          (o_h2d_axi_st_tkeep          ),
				.h2d_axi_st_tlast          (o_h2d_axi_st_tlast          ),
				.h2d_axi_st_tuser_metadata (o_h2d_axi_st_tuser_metadata ),
				.h2d_axi_st_tid            (o_h2d_axi_st_tid            ),
				.h2d_axi_st_tuser_error    (o_h2d_axi_st_tuser_error    ),
				
				.d2h_axi_st_tvalid         ( d2h_axi_st_tvalid         ),
				.d2h_axi_st_tready         ( d2h_axi_st_tready         ),
				.d2h_axi_st_tdata          ( d2h_axi_st_tdata          ),
				.d2h_axi_st_tkeep          ( d2h_axi_st_tkeep          ),
				.d2h_axi_st_tlast          ( d2h_axi_st_tlast          ),
				.d2h_axi_st_tuser_metadata ( d2h_axi_st_tuser_metadata ),
				.d2h_axi_st_tid            ( d2h_axi_st_tid            ),
				.d2h_axi_st_tuser_error    ( d2h_axi_st_tuser_error    ),
				
				.pcie5_bam_axi_mm_awvalid  (pcie5_bam_axi_mm_awvalid),
				.pcie5_bam_axi_mm_awready  (pcie5_bam_axi_mm_awready),
				.pcie5_bam_axi_mm_awid     (pcie5_bam_axi_mm_awid   ),
				.pcie5_bam_axi_mm_awaddr   (pcie5_bam_axi_mm_awaddr ),
				.pcie5_bam_axi_mm_awlen    (pcie5_bam_axi_mm_awlen  ),
				.pcie5_bam_axi_mm_awsize   (pcie5_bam_axi_mm_awsize ),
				.pcie5_bam_axi_mm_awburst  (pcie5_bam_axi_mm_awburst),
				.pcie5_bam_axi_mm_awprot   (pcie5_bam_axi_mm_awprot ),
				.pcie5_bam_axi_mm_awlock   (pcie5_bam_axi_mm_awlock ),
				.pcie5_bam_axi_mm_awuser   (pcie5_bam_axi_mm_awuser ),
				.pcie5_bam_axi_mm_wvalid   (pcie5_bam_axi_mm_wvalid ),
				.pcie5_bam_axi_mm_wready   (pcie5_bam_axi_mm_wready ),
				.pcie5_bam_axi_mm_wlast    (pcie5_bam_axi_mm_wlast  ),
				.pcie5_bam_axi_mm_wdata    (pcie5_bam_axi_mm_wdata  ),
				.pcie5_bam_axi_mm_wstrb    (pcie5_bam_axi_mm_wstrb  ),
				.pcie5_bam_axi_mm_bvalid   (pcie5_bam_axi_mm_bvalid ),
				.pcie5_bam_axi_mm_bready   (pcie5_bam_axi_mm_bready ),
				.pcie5_bam_axi_mm_bid      (pcie5_bam_axi_mm_bid    ),
				.pcie5_bam_axi_mm_bresp    (pcie5_bam_axi_mm_bresp  ),
				.pcie5_bam_axi_mm_arvalid  (pcie5_bam_axi_mm_arvalid),
				.pcie5_bam_axi_mm_arready  (pcie5_bam_axi_mm_arready),
				.pcie5_bam_axi_mm_arid     (pcie5_bam_axi_mm_arid   ),
				.pcie5_bam_axi_mm_araddr   (pcie5_bam_axi_mm_araddr ),
				.pcie5_bam_axi_mm_arlen    (pcie5_bam_axi_mm_arlen  ),
				.pcie5_bam_axi_mm_arsize   (pcie5_bam_axi_mm_arsize ),
				.pcie5_bam_axi_mm_arburst  (pcie5_bam_axi_mm_arburst),
				.pcie5_bam_axi_mm_arprot   (pcie5_bam_axi_mm_arprot ),
				.pcie5_bam_axi_mm_arlock   (pcie5_bam_axi_mm_arlock ),
				.pcie5_bam_axi_mm_aruser   (pcie5_bam_axi_mm_aruser ),
				.pcie5_bam_axi_mm_rvalid   (pcie5_bam_axi_mm_rvalid ),
				.pcie5_bam_axi_mm_rready   (pcie5_bam_axi_mm_rready ),
				.pcie5_bam_axi_mm_rlast    (pcie5_bam_axi_mm_rlast  ),
				.pcie5_bam_axi_mm_rid      (pcie5_bam_axi_mm_rid    ),
				.pcie5_bam_axi_mm_rdata    (pcie5_bam_axi_mm_rdata  ),
				.pcie5_bam_axi_mm_rresp    (pcie5_bam_axi_mm_rresp  ),

				// BAS：MCDMA 作为 AXI4 slave，RoCE 引擎从这里读写主机内存
				.pcie5_bas_m2s             (pcie5_bas_m2s           ),
				.pcie5_bas_s2m             (pcie5_bas_s2m           ),
				
				.pcie_linkup               (                        ),  
				.pcie_data_linkup          (                        )
               );

axis_keep_pack #(
        .SB_MODE                   ("BEAT"                     )   // metadata 由软件逐拍填充，取包尾输入拍的值
    ) u_axis_keep_pack
               (
                .clk                       (pcie_app_clk               ),
                .rst_n                     (pcie_clk_rstn[1]           ),

                .s_axis_tvalid             (o_h2d_axi_st_tvalid        ),
                .s_axis_tready             (o_h2d_axi_st_tready        ),
                .s_axis_tdata              (o_h2d_axi_st_tdata         ),
                .s_axis_tkeep              (o_h2d_axi_st_tkeep         ),
                .s_axis_tlast              (o_h2d_axi_st_tlast         ),
                .s_axis_tuser_metadata     (o_h2d_axi_st_tuser_metadata),
                .s_axis_tid                (o_h2d_axi_st_tid           ),
                .s_axis_tuser_error        (o_h2d_axi_st_tuser_error   ),

                .m_axis_tvalid             (h2d_axi_st_tvalid          ),
                .m_axis_tready             (h2d_axi_st_tready          ),
                .m_axis_tdata              (h2d_axi_st_tdata           ),
                .m_axis_tkeep              (h2d_axi_st_tkeep           ),
                .m_axis_tlast              (h2d_axi_st_tlast           ),
                .m_axis_tuser_metadata     (h2d_axi_st_tuser_metadata  ),
                .m_axis_tid                (h2d_axi_st_tid             ),
                .m_axis_tuser_error        (h2d_axi_st_tuser_error     ),
                .m_axis_tbyte_num          (h2d_axi_st_byte_num        )
               );


   (* keep *) wire           h2d_axi_st_reg_tvalid        ;
   (* keep *) wire           h2d_axi_st_reg_tready        ;
   (* keep *) wire [1023:0]  h2d_axi_st_reg_tdata         ;
   (* keep *) wire           h2d_axi_st_reg_tlast         ;
   (* keep *) wire [11:0]    h2d_axi_st_reg_tid           ;
   (* keep *) wire [127:0]   h2d_axi_st_reg_tkeep         ;


    axi_stream_register_slice #(
        .TDATA_W                            (1024         ),
        .TID_W                              (12              ),
        .TDEST_W                            (1              ),
        .TUSER_W                            (1        ),
        .MODE                               ("full"         )
    ) uxx_axi_stream_register_slice (
        .s_axis_tvalid                      ( h2d_axi_st_tvalid ),
        .s_axis_tdata                       ( h2d_axi_st_tdata  ),
        // 末拍有效字节数必须由 axis_keep_pack 打包后的真实 keep 算：
        // tuser_metadata 是 MCDMA 的逐拍侧带、驱动侧从不填（恒 0），打包器又会把多拍
        // 合并成一拍，靠它会让末拍长度丢失，非整拍帧被补成 128 B 整拍。
        //
        // B6438：字节数改由打包器在输出寄存级算出（m_axis_tbyte_num），这里只接一个已寄存的
        // 8 位侧带。原先在此处对 128 位 keep 做 popcount 归约，是 pcie_app_clk 上 u82→uxx
        // 398 端点、最差 −0.332 的二次路径（优化日志 §62.2）。
        .s_axis_tkeep                       ( {120'd0, h2d_axi_st_byte_num} ),
        .s_axis_tlast                       ( h2d_axi_st_tlast  ),
        .s_axis_tid                         ( h2d_axi_st_tid   ),
        .s_axis_tdest                       (                  ),
        .s_axis_tuser                       (   ),
        .s_axis_tready                      ( h2d_axi_st_tready),

        .m_axis_tvalid                      ( h2d_axi_st_reg_tvalid ),
        .m_axis_tdata                       ( h2d_axi_st_reg_tdata  ),
        .m_axis_tkeep                       ( h2d_axi_st_reg_tkeep  ),
        .m_axis_tlast                       ( h2d_axi_st_reg_tlast  ),
        .m_axis_tid                         ( h2d_axi_st_reg_tid    ),
        .m_axis_tdest                       (                   ),
        .m_axis_tuser                       (    ),
        .m_axis_tready                      (h2d_axi_st_reg_tready),
        .aclk                               (pcie_app_clk            ),
        .aresetn                            (pcie_clk_rstn[1]            )
    );
  

    axil_to_avmm_bridge #(.ADDR_W(28),.DATA_W(64)) 
        U_axil2avmm(
        .clk(clk250m),
        .rst_n(axil_rst_n),

        .s_axil_awaddr     (  csr_axi_lite_awaddr    ),
        .s_axil_awvalid    (  csr_axi_lite_awvalid   ),
        .s_axil_awready    (  csr_axi_lite_awready   ),
                                        
        .s_axil_wdata      (  csr_axi_lite_wdata          ),
        .s_axil_wstrb      (  {4'h0,csr_axi_lite_wstrb[3:0]}    ),
        .s_axil_wvalid     (  csr_axi_lite_wvalid         ),
        .s_axil_wready     (  csr_axi_lite_wready         ),
                                       
        .s_axil_bresp      (  csr_axi_lite_bresp          ),
        .s_axil_bvalid     (  csr_axi_lite_bvalid         ),
        .s_axil_bready     (  csr_axi_lite_bready         ),
                                        
        .s_axil_araddr     (  csr_axi_lite_araddr          ),
        .s_axil_arvalid    (  csr_axi_lite_arvalid         ),
        .s_axil_arready    (  csr_axi_lite_arready         ),
                                         
        .s_axil_rdata      (  csr_axi_lite_rdata           ),
        .s_axil_rresp      (  csr_axi_lite_rresp           ),
        .s_axil_rvalid     (  csr_axi_lite_rvalid          ),
        .s_axil_rready     (  csr_axi_lite_rready          ),
                                        
        .avm_address       (  pcie2cdc_avm_addr            ),
        .avm_write         (  pcie2cdc_avm_write           ),
        .avm_read          (  pcie2cdc_avm_read            ),
        .avm_writedata     (  pcie2cdc_avm_wdat            ),
        .avm_byteenable    (  pcie2cdc_avm_byte            ),
        .avm_waitrequest   (  pcie2cdc_avm_wait            ),
        .avm_readdata      (  pcie2cdc_avm_rdat            ),
        .avm_readdatavalid (  pcie2cdc_avm_rvld            )
    );    

    assign pcie2cdc_avm_bcnt = 1;

    `endif
    `endif

                
/*****************************************************************************\
*       tx_path
\*****************************************************************************/
    localparam                  CHANNL_NUM  = 2;
    localparam                  INFO_W      = 16+1+1+5;
    localparam                  DATA_W      = 1024;
    localparam                  USERF_W     = $clog2(DATA_W/8);
    localparam                  FRAME_W     = DATA_W/64;
    localparam                  MAC_DATA_W  = 1024;
    localparam                  MAC_FRAME_W = MAC_DATA_W/64;
    localparam                  FLOW_NUM    = 16384;
    localparam                  STREAM_ID_W = 14   ;
    wire [3:0] 				    eth_tx_mod;
    wire [31:0] 				eth_tx_num;
    wire 					    eth_tx_req;
    wire 					    eth_tx_stop;
    wire 					    eth_tx_ack_p;
    wire 					    tx_crc_err;
    
    // pkt_gen 已删除（测试仪打流逻辑），原 gen_to_reg_*/reg_to_select_*/reg_to_segm_*
    // 全部随之移除；slot 2 现由一个返回 0xdeadbeef 的 avm_register 桩认领。
    wire    [CHANNL_NUM-1:0]        select_tready_bus        ;
    wire    [CHANNL_NUM-1:0]        segm_tready_bus          ;

    wire                            select_to_segm_tvalid;
    wire                            select_to_segm_qdma  ;
    wire    [DATA_W-1:0]            select_to_segm_data ;
    wire    [USERF_W-1:0]           select_to_segm_usef ;
    wire    [INFO_W-1:0]            select_to_segm_tinfo ;
    wire                            select_to_segm_last ;
    wire                            select_to_segm_tready;

    wire                            qdma_to_regslice_tvalid;
    wire    [DATA_W-1:0]            qdma_to_regslice_tdata ;
    wire    [USERF_W-1:0]           qdma_to_regslice_tusef ;
    wire                            qdma_to_regslice_tlast ;
    wire                            qdma_to_regslice_tready;

    wire                            qdma_to_select_tvalid;
    wire    [DATA_W-1:0]            qdma_to_select_tdata ;
    wire    [USERF_W-1:0]           qdma_to_select_tusef ;
    wire                            qdma_to_select_tlast ;
    wire                            qdma_to_select_tready;
    wire    [4:0]                   qdma_to_select_tfr_num;
    // RoCE 引擎调试总线（0x0170_0500..，地址表见 roce/roce_debug.sv 文件头）
    wire    [4:0]                   axis_select_dbg ;
    wire    [9:0]                   axis_to_segm_dbg;
    wire    [136:0]                 roce_mac_debug  ;
    wire    [107:0]                 roce_pcie_debug ;
    // RoCE：u91 输出先经 roce_top 做 2:1 包仲裁，再到 qdma_to_select_*
    wire                            qdma_to_roce_tvalid;
    wire    [DATA_W-1:0]            qdma_to_roce_tdata ;
    wire    [USERF_W-1:0]           qdma_to_roce_tusef ;
    wire                            qdma_to_roce_tlast ;
    wire                            qdma_to_roce_tready;
    // RoCE：MCDMA BAS 打包总线（位段见 src/roce/roce_bas_if.vh）
    wire [1359:0]                   pcie5_bas_m2s;
    wire [1041:0]                   pcie5_bas_s2m;
    // RoCE：BAM AXI-MM 主接口（BAS 模式下 BAR2 寄存器访问经它到 axi4_adapter）
    wire                          pcie5_bam_axi_mm_awvalid;
    wire                          pcie5_bam_axi_mm_awready;
    wire [3:0]                    pcie5_bam_axi_mm_awid   ;
    wire [33:0]                   pcie5_bam_axi_mm_awaddr ;
    wire [7:0]                    pcie5_bam_axi_mm_awlen  ;
    wire [2:0]                    pcie5_bam_axi_mm_awsize ;
    wire [1:0]                    pcie5_bam_axi_mm_awburst;
    wire [2:0]                    pcie5_bam_axi_mm_awprot ;
    wire                          pcie5_bam_axi_mm_awlock ;
    wire [19:0]                   pcie5_bam_axi_mm_awuser ;
    wire                          pcie5_bam_axi_mm_wvalid ;
    wire                          pcie5_bam_axi_mm_wready ;
    wire                          pcie5_bam_axi_mm_wlast  ;
    wire [1023:0]                 pcie5_bam_axi_mm_wdata  ;
    wire [127:0]                  pcie5_bam_axi_mm_wstrb  ;
    wire                          pcie5_bam_axi_mm_bvalid ;
    wire                          pcie5_bam_axi_mm_bready ;
    wire [3:0]                    pcie5_bam_axi_mm_bid    ;
    wire [1:0]                    pcie5_bam_axi_mm_bresp  ;
    wire                          pcie5_bam_axi_mm_arvalid;
    wire                          pcie5_bam_axi_mm_arready;
    wire [3:0]                    pcie5_bam_axi_mm_arid   ;
    wire [33:0]                   pcie5_bam_axi_mm_araddr ;
    wire [7:0]                    pcie5_bam_axi_mm_arlen  ;
    wire [2:0]                    pcie5_bam_axi_mm_arsize ;
    wire [1:0]                    pcie5_bam_axi_mm_arburst;
    wire [2:0]                    pcie5_bam_axi_mm_arprot ;
    wire                          pcie5_bam_axi_mm_arlock ;
    wire [19:0]                   pcie5_bam_axi_mm_aruser ;
    wire                          pcie5_bam_axi_mm_rvalid ;
    wire                          pcie5_bam_axi_mm_rready ;
    wire                          pcie5_bam_axi_mm_rlast  ;
    wire [3:0]                    pcie5_bam_axi_mm_rid    ;
    wire [1023:0]                 pcie5_bam_axi_mm_rdata  ;
    wire [1:0]                    pcie5_bam_axi_mm_rresp  ;
    // RoCE：AVMM 分流后给 avm_config
    wire [27:0]                     cfg_avm_addr;
    wire                            cfg_avm_read;
    wire                            cfg_avm_write;
    wire [31:0]                     cfg_avm_wdat;
    wire                            cfg_avm_wait;
    wire [31:0]                     cfg_avm_rdat;
    wire                            cfg_avm_rvld;
    wire [1:0]                      cfg_avm_rspo;
    wire                            cfg_avm_wrsp;

    wire                            segm_to_reg_tvalid   ;
    wire    [DATA_W-1:0]            segm_to_reg_tdata    ;
    wire    [FRAME_W*3-1:0]         segm_to_reg_emty     ;
    wire    [FRAME_W-1:0]           segm_to_reg_frame    ;
    wire                            segm_to_reg_tready   ;

    wire                            reg_to_h2l_tvalid   ;
    wire    [DATA_W-1:0]            reg_to_h2l_tdata    ;
    wire    [FRAME_W*3-1:0]         reg_to_h2l_emty     ;
    wire    [FRAME_W-1:0]           reg_to_h2l_frame    ;
    wire                            reg_to_h2l_tready   ;

    wire                            gap_to_mac_tvalid;
    wire    [MAC_DATA_W-1:0]        gap_to_mac_tdata ;
    wire    [MAC_FRAME_W*3-1:0]     gap_to_mac_emty  ;
    wire    [MAC_FRAME_W-1:0]       gap_to_mac_frame ;
    wire                            gap_to_mac_tready;

    wire    [MAC_DATA_W-1:0]        rx_mac_data     ;
    wire    [MAC_FRAME_W*3-1:0]     rx_mac_eop_empty;
    wire    [MAC_FRAME_W-1:0]       rx_mac_inframe  ;
    wire    [MAC_FRAME_W*2-1:0]     rx_mac_error    ;
    wire    [MAC_FRAME_W-1:0]       rx_mac_fcs_error;
    wire                            rx_mac_valid    ;

    wire    [DATA_W-1:0]            l2h_to_rx_data     ;
    wire    [FRAME_W*3-1:0]         l2h_to_rx_eop_empty;
    wire    [FRAME_W-1:0]           l2h_to_rx_inframe  ;
    wire    [FRAME_W*2-1:0]         l2h_to_rx_error    ;
    wire    [FRAME_W-1:0]           l2h_to_rx_fcs_error;
    wire                            l2h_to_rx_valid    ;

    wire    [DATA_W-1:0]            rx_to_rcv_tdata[CHANNL_NUM-1:0]    ;
    wire    [7-1:0]                 rx_to_rcv_tempty[CHANNL_NUM-1:0]   ;
    wire    [2:0]                   rx_to_rcv_tuerr[CHANNL_NUM-1:0]    ;
    wire    [63:0]                  rx_to_rcv_time[CHANNL_NUM-1:0]     ;
    wire                            rx_to_rcv_tvalid[CHANNL_NUM-1:0]   ;
    wire                            rx_to_rcv_tready[CHANNL_NUM-1:0]   ;
    wire                            rx_to_rcv_tlast[CHANNL_NUM-1:0]    ;
    wire 					        eth_rx_rst;
    wire 					        eth_tx_rst;

    wire                            rdma_to_regl_tvalid   ;
    wire    [1024-1:0]               rdma_to_regl_tdata    ;
    wire                            rdma_to_regl_tlast    ;
    wire    [6:0]                   rdma_to_regl_tkeep    ;
    wire    [11:0]                  rdma_to_regl_tchannel ;
    wire                            rdma_to_regl_tready   ;

    wire                            regl_to_qdma_tvalid   ;
    wire    [1024-1:0]               regl_to_qdma_tdata    ;
    wire                            regl_to_qdma_tlast    ;
    wire    [6:0]                   regl_to_qdma_tkeep    ;
    wire    [11:0]                  regl_to_qdma_tchannel ;
    wire                            regl_to_qdma_tready   ;

    wire                            rcv_to_qdma_tvalid; 
    wire    [DATA_W-1:0]            rcv_to_qdma_tdata ; 
    wire    [USERF_W-1:0]           rcv_to_qdma_tkeep ; 
    wire                            rcv_to_qdma_tlast ; 
    wire                            rcv_to_qdma_tready; 
    wire    [63:0]                  time_stamp_eth;
    wire    [63:0]                  time_stamp_delay;
    wire    [63:0]                  time_stamp_pcie;
    wire    [63:0]                  gtime_value    ;
    wire                            gtime_set      ;
    wire                            rocev2_stamp_en;
    wire    [8:0]                   tx_pfc;          // system_config REG 0x054：软件强制 XOFF（aclk 域，调试用）
    wire    [8:0]                   roce_tx_pfc;     // RoCE 引擎 roce_pfc 自动生成的 XOFF（eth_mac_clk 域）
    wire    [8:0]                   rx_pfc;
    wire                            statis_cnt_clear_en;
    wire                            timestamp_delay_type;
    wire    [31:0]                  shell_rstn;
    wire    [31:0]                  shell_rst_done;
    wire                            eth_mac_clk;
    // PFC 发送：软件强制 XOFF（system_config 0x054）| RoCE 自动 XOFF（roce_pfc）。
    // 软件位来自 clk250m 域，进 MAC 前补两级同步（原来直连 F-tile，没有同步器）。
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    reg     [8:0]                   tx_pfc_sw_sync1, tx_pfc_sw_sync2;
    always @(posedge eth_mac_clk) begin
        tx_pfc_sw_sync1 <= tx_pfc;
        tx_pfc_sw_sync2 <= tx_pfc_sw_sync1;
    end
    // 进 F-tile 前再寄存一拍（B6433）。B6432 STA：u_pfc|pause_out8 / xoff_out 与 tx_pfc_sw_sync2 →
    // 硬核 hdpldadapt_tx_chnl 输入 −0.235 / −0.227 ns（415 MHz）：OR 门之后直接是一段跨芯片的长线。
    // 寄存器放在硬核旁边，前后都只剩寄存器到寄存器；多 1 拍（2.4 ns）对 µs 级 PFC 反应无影响。
    reg     [8:0]                   mac_tx_pfc;
    always @(posedge eth_mac_clk) mac_tx_pfc <= tx_pfc_sw_sync2 | roce_tx_pfc;
    wire 					        eth_rx_pcs_ready;
    reg                             rx_path_eop_vld;
    reg     [1:0]                   rx_path_eop_num;
    reg                             qdma_d2h_last_vld;
    reg                             pcie_d2h_last_vld;
    reg                             pcie_d2h_sof_vld;
    reg                             pcie_h2d_eop_vld;
    reg                             rdma2qdma_eop_vld;
    reg                             qdma_h2d_eop_vld;
    reg                             axis_select_eop_vld;
    reg     [1:0]                   segm2h2l_eop_num;
    reg     [15:0]                  segm2h2l_frame_d1;
    reg     [1:0]                   gap2mac_eop_num;
    reg     [MAC_FRAME_W-1:0]       gap2mac_frame_d1;
    wire    [31:0]                  rx_path_eop_cnt     ;
    wire    [31:0]                  rx_rcv_last0_cnt    ;
    wire    [31:0]                  rx_rcv_last1_cnt    ;
    wire    [31:0]                  qdma_d2h_last_cnt   ;
    wire    [31:0]                  pcie_d2h_last_cnt   ;
    wire    [31:0]                  pcie_d2h_sof_cnt   ;
    wire    [31:0]                  pcie_h2d_eop_cnt    ;
    wire    [31:0]                  rdma2qdma_eop_cnt    ;
    wire    [31:0]                  qdma_h2d_eop_cnt    ;
    wire    [31:0]                  axis_select_eop_cnt ;
    wire    [31:0]                  segm2h2l_eop_cnt    ;
    wire    [31:0]                  gap2mac_eop_cnt     ;
    wire    [63:0]                  eth_fcs_err_cnt         ;
    wire    [63:0]                  eth_mfmd_err_cnt        ;
    wire    [63:0]                  eth_under_over_err_cnt  ;
    wire    [63:0]                  eth_plen_err_cnt        ;
    wire    [63:0]                  eth_fifo_full_err_cnt   ;
    reg     [59:0]                  mod_int_status_reg      ;
    wire    [2:0]                   clk_rstn[1:0]           ;
    wire    [1:0]                   mac_clk_rstn            ;
    wire    [1:0]                   axil_clk_rstn           ;
    wire    [1:0]                   pcie_clk_rstn           ;
    wire    [8*32-1:0]              pfc_pkt_drop_cnt        ;
    wire    [8*32-1:0]              pfc_pkt_in_cnt          ;
    wire    [8*32-1:0]              pfc_pkt_out_cnt         ;


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

    // ---------------------------------------------------------------
    // slot 2 (0x0130_0000, 原 pkt_gen) 的空桩。
    // pkt_gen 已删除，但 avm_config 的 avm_wait 在"没有用户应答"时会永久
    // 拉高，连带整条 AVMM（含 BAR2）超时。所以这个地址必须仍有人认领：
    // 用 avm_register 每拍返回 0xdeadbeef，写请求直接回 wrsp。
    // ---------------------------------------------------------------
    avm_register #(
        .CLOCKING_MODE                      ("common_clock"              ),
        .ADDR_W                             (28                         ),
        .DATA_W                             (32                         )
    ) u0_pkt_gen_avm_stub
    (
        .avm_addr                           (user_avm_addr [2*28+:28]   ),
        .avm_read                           (user_avm_read [2]          ),
        .avm_write                          (user_avm_write[2]          ),
        .avm_wdat                           (user_avm_wdat [2*32+:32]   ),
        .avm_wait                           (user_avm_wait [2]          ),
        .avm_rdat                           (user_avm_rdat [2*32+:32]   ),
        .avm_rvld                           (user_avm_rvld [2]          ),
        .avm_rspo                           (user_avm_rspo [2*2+:2]     ),
        .avm_wrsp                           (user_avm_wrsp [2]          ),
        .reg_en                             (                           ),
        .reg_we                             (                           ),
        .reg_addr                           (                           ),
        .reg_din                            (                           ),
        .reg_dout                           (32'hdeadbeef               ),
        .clk                                (clk250m                    ),
        .rst_n                              (~pcie_app_rst              )
    );

    assign qdma_to_select_tfr_num = qdma_to_select_tusef==0 ?5'd16:qdma_to_select_tusef[6:3] + |qdma_to_select_tusef[0+:3];
    // axis_select / axis_to_segm 内部按固定 AXIS_NUM=2 写死了 [0]/[1] 两路的仲裁
    // 与拼帧逻辑（见 tx_pkts/axis_to_segm.sv 里的 s_axis_tready[1]、
    // send_select 等），把参数改成 1 会产生越界索引。pkt_gen 删除后保留 2 口，
    // 第 1 口（原来的测试仪打流通道）恒接 0 空闲即可，第 0 口仍是 RoCE/QDMA 主通路。
    axis_select #(
        .S_DATA_WIDTH                       (DATA_W                     ),
        .S_INFO_WIDTH                       (INFO_W                     ),
        .AXIS_NUM                           (CHANNL_NUM                 )
    )
    u2_gen0_qdma_select
    (
        .clk                                (eth_mac_clk                ),
        .rst_n                              (mac_clk_rstn[0]            ),
        .s_axis_tvalid                      ({1'b0                  ,qdma_to_select_tvalid}),
        .s_axis_tdata                       ({{DATA_W{1'b0}}             ,qdma_to_select_tdata }),
        .s_axis_tlast                       ({1'b0                  ,qdma_to_select_tlast }),
        .s_axis_usef                        ({{USERF_W{1'b0}}            ,qdma_to_select_tusef }),
        .s_axis_info                        ({{INFO_W{1'b0}}             ,{qdma_to_select_tfr_num,{INFO_W-5{1'b0}}}}),
        .s_axis_tready                      (select_tready_bus          ),
        .m_axis_tvalid                      (select_to_segm_tvalid      ),
        .m_axis_qdma                        (select_to_segm_qdma        ),
        .m_axis_tdata                       (select_to_segm_data       ),
        .m_axis_tlast                       (select_to_segm_last       ),
        .m_axis_usef                        (select_to_segm_usef       ),
        .m_axis_info                        (select_to_segm_tinfo       ),
        .m_axis_tready                      (select_to_segm_tready      ),
        .debug_state                        (axis_select_dbg            )
    );
    assign qdma_to_select_tready = select_tready_bus[0];
    // 坑：删 pkt_gen 时 axis_to_segm 的 s_axis_tready 从 {reg_to_segm_ready,
    // select_to_segm_tready} 改成 segm_tready_bus，但忘了把 [0] 回接到
    // select_to_segm_tready。未驱动的 wire 恒 0 -> axis_select 的 m_axis_tready 恒 0
    // -> TX 从 axis_select 出口全部堵死，表现为 RX 通、TX 完全不发（B6369）。
    assign select_to_segm_tready = segm_tready_bus[0];

    axis_to_segm #(
        .S_DATA_WIDTH                       (DATA_W                     ),
        .S_INFO_WIDTH                       (INFO_W                     ),
        .FLOW_NUM                           (FLOW_NUM                   ),
        .STREAM_ID_W                        (STREAM_ID_W                ),
        .AXIS_NUM                           (CHANNL_NUM                 )
    )
    u3_axis_to_segm
    (
        .clk                                (eth_mac_clk                ),
        .rst_n                              (mac_clk_rstn[0]            ),
        .time_stamp                         (time_stamp_delay           ),
        .s_axis_pkt_stop_en                 (1'b0                       ),
        .s_axis_tvalid                      ({1'b0                      ,select_to_segm_tvalid }),
        .s_axis_qdma                        ({1'b0                      ,select_to_segm_qdma   }),
        .s_axis_tdata                       ({{DATA_W{1'b0}}                 ,select_to_segm_data   }),
        .s_axis_tlast                       ({1'b0                      ,select_to_segm_last   }),
        .s_axis_usef                        ({{USERF_W{1'b0}}                ,select_to_segm_usef   }),
        .s_axis_finfo                       ({{INFO_W{1'b0}}                 ,select_to_segm_tinfo  }),
        .s_axis_tready                      (segm_tready_bus            ),
        .m_segm_data                        (segm_to_reg_tdata  ),
        .m_segm_emty                        (segm_to_reg_emty   ),
        .m_segm_frame                       (segm_to_reg_frame  ),
        .m_segm_valid                       (segm_to_reg_tvalid ),
        .m_segm_ready                       (segm_to_reg_tready ),
        .debug_state                        (axis_to_segm_dbg   )
    );

    axi_stream_register_slice #(
        .TDATA_W                            (DATA_W                         ),
        .TID_W                              (FRAME_W*3                      ),
        .TDEST_W                            (FRAME_W                        ),
        .TUSER_W                            (1                              ),
        .MODE                               ("full"                         )
    )u03_segm_to_h2l_slice (
        .s_axis_tvalid                      (segm_to_reg_tvalid             ),
        .s_axis_tdata                       (segm_to_reg_tdata              ),
        .s_axis_tkeep                       (                               ),
        .s_axis_tlast                       (                               ),
        .s_axis_tid                         (segm_to_reg_emty               ),
        .s_axis_tdest                       (segm_to_reg_frame              ),
        .s_axis_tuser                       (                               ),
        .s_axis_tready                      (segm_to_reg_tready             ),
        .m_axis_tvalid                      (reg_to_h2l_tvalid              ),
        .m_axis_tdata                       (reg_to_h2l_tdata               ),
        .m_axis_tkeep                       (                               ),
        .m_axis_tlast                       (                               ),
        .m_axis_tid                         (reg_to_h2l_emty                ),
        .m_axis_tdest                       (reg_to_h2l_frame               ),
        .m_axis_tuser                       (                               ),
        .m_axis_tready                      (reg_to_h2l_tready              ),
        .aclk                               (eth_mac_clk                    ),
        .aresetn                            (mac_clk_rstn[0]                )
    );

    segm_dwidth_converter_h2l #(
        .S_DATA_WIDTH                       (DATA_W             ),
        .M_DATA_WIDTH                       (MAC_DATA_W         )
    )
    u4_segm_width_converter_h2l
    (          
        .clk                                (eth_mac_clk        ),
        .rst_n                              (mac_clk_rstn[0]    ),
        .s_segm_data                        (reg_to_h2l_tdata   ),
        .s_segm_emty                        (reg_to_h2l_emty    ),
        .s_segm_frame                       (reg_to_h2l_frame   ),
        .s_segm_valid                       (reg_to_h2l_tvalid  ),
        .s_segm_ready                       (reg_to_h2l_tready  ),
        .m_segm_data                        (gap_to_mac_tdata   ),
        .m_segm_emty                        (gap_to_mac_emty    ),
        .m_segm_frame                       (gap_to_mac_frame   ),
        .m_segm_valid                       (gap_to_mac_tvalid  ),
        .m_segm_ready                       (gap_to_mac_tready  )
    );

/*****************************************************************************\
*       rx_path
\*****************************************************************************/

    segm_dwidth_converter_l2h #(
        .S_DATA_WIDTH                       (MAC_DATA_W         ),
        .M_DATA_WIDTH                       (DATA_W             )
    )
    u5_segm_width_converter_l2h
    (
        .clk                                (eth_mac_clk        ),
        .rst_n                              (mac_clk_rstn[1]    ),
        .s_segm_data                        (rx_mac_data        ),
        .s_segm_emty                        (rx_mac_eop_empty   ),
        .s_segm_frame                       (rx_mac_inframe     ),
        .s_segm_valid                       (rx_mac_valid       ),
        .s_segm_error                       (rx_mac_error       ),
        .s_segm_fcs_error                   (rx_mac_fcs_error   ),
        .m_segm_data                        (l2h_to_rx_data     ),
        .m_segm_emty                        (l2h_to_rx_eop_empty),
        .m_segm_frame                       (l2h_to_rx_inframe  ),
        .m_segm_valid                       (l2h_to_rx_valid    ),
        .m_segm_error                       (l2h_to_rx_error    ),
        .m_segm_fcs_error                   (l2h_to_rx_fcs_error)
    );

    rx_path_avst
    u6_rx_path
    (
        .mac_clk                            (eth_mac_clk),
        .mac_rst_n                          (mac_clk_rstn[1]),
        .timestamp_delay_type               (timestamp_delay_type),
        .time_stamp                         (time_stamp_delay    ),
        .s_mac_data                         (l2h_to_rx_data     ),
        .s_mac_emty                         (l2h_to_rx_eop_empty),
        .s_mac_inframe                      (l2h_to_rx_inframe  ),
        .s_mac_error                        (l2h_to_rx_error    ),
        .s_mac_fcs_error                    (l2h_to_rx_fcs_error),
        .s_mac_valid                        (l2h_to_rx_valid    ),
        .m_axis_tdata0                      (rx_to_rcv_tdata[0]  ),
        .m_axis_tempty0                     (rx_to_rcv_tempty[0] ),
        .m_axis_tuerr0                      (rx_to_rcv_tuerr[0]  ),
        .m_axis_time0                       (rx_to_rcv_time[0]   ),
        .m_axis_tvalid0                     (rx_to_rcv_tvalid[0] ),
        .m_axis_tready0                     (1'b1                ),
        .m_axis_teop0                       (rx_to_rcv_tlast[0]  ),
        .m_axis_tdata1                      (rx_to_rcv_tdata[1]  ),
        .m_axis_tempty1                     (rx_to_rcv_tempty[1] ),
        .m_axis_tuerr1                      (rx_to_rcv_tuerr[1]  ),
        .m_axis_time1                       (rx_to_rcv_time[1]   ),
        .m_axis_tvalid1                     (rx_to_rcv_tvalid[1] ),
        .m_axis_tready1                     (1'b1                ),
        .m_axis_teop1                       (rx_to_rcv_tlast[1]  )
    );

    rx_pkt_rcv_top#(
        .DATA_W                             (DATA_W                   ),
        .FLOW_NUM                           (FLOW_NUM                 ),
        .STREAM_ID_W                        (STREAM_ID_W              )
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
        .s_axis_rx0_ttime                   (rx_to_rcv_time[0]        ),
        .s_axis_rx1_tvalid                  (rx_to_rcv_tvalid[1]      ),
        .s_axis_rx1_tdata                   (rx_to_rcv_tdata[1]       ),
        .s_axis_rx1_tkeep                   (rx_to_rcv_tempty[1]      ),
        .s_axis_rx1_tlast                   (rx_to_rcv_tlast[1]       ),
        .s_axis_rx1_tuser_err               (rx_to_rcv_tuerr[1]       ),
        .s_axis_rx1_ttime                   (rx_to_rcv_time[1]        ),
        .m_axis_rx_tvalid                   (rcv_to_qdma_tvalid       ),
        .m_axis_rx_tdata                    (rcv_to_qdma_tdata        ),
        .m_axis_rx_tkeep                    (rcv_to_qdma_tkeep        ),
        .m_axis_rx_tlast                    (rcv_to_qdma_tlast        ),
        .m_axis_rx_tready                   (rcv_to_qdma_tready       ),
        .timestamp_delay_type               (timestamp_delay_type     ),
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


    rdma_timestamp_mark #(.DATA_WIDTH(1024), .KEEP_WIDTH(128), .EMPTY_WIDTH(7)) u8_rdma_timestamp_mark
    (
        .clk                                (pcie_app_clk           ),
        .rst_n                              (pcie_clk_rstn[1]       ),
        .s_axis_tvalid                      (h2d_axi_st_reg_tvalid      ),
        .s_axis_tdata                       (h2d_axi_st_reg_tdata       ),
        .s_axis_tlast                       (h2d_axi_st_reg_tlast       ),
        .s_axis_tkeep                       (h2d_axi_st_reg_tkeep       ),
        .s_axis_tchannel                    (h2d_axi_st_reg_tid    ),
        .s_axis_tready                      (h2d_axi_st_reg_tready      ),
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
        .TDATA_W                            (DATA_W               ),
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

    qdma_top #(.DATA_W(1024),.EMTY_W(7),.CHANNEL_W(11)) u9_qdma_top
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
        .rx_pfc                             (rx_pfc                     ),
        .statis_cnt_clear_en                (statis_cnt_clear_en        ),
        .pfc_pkt_drop_cnt                   (pfc_pkt_drop_cnt           ),
        .pfc_pkt_in_cnt                     (pfc_pkt_in_cnt             ),
        .pfc_pkt_out_cnt                    (pfc_pkt_out_cnt            ),
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
        .m_axis_tvalid                      (qdma_to_roce_tvalid        ),
        .m_axis_tdata                       (qdma_to_roce_tdata         ),
        .m_axis_tkeep                       (                           ),
        .m_axis_tlast                       (qdma_to_roce_tlast         ),
        .m_axis_tid                         (                           ),
        .m_axis_tdest                       (                           ),
        .m_axis_tuser                       (qdma_to_roce_tusef         ),
        .m_axis_tready                      (qdma_to_roce_tready        ),
        .aclk                               (eth_mac_clk                ),
        .aresetn                            (mac_clk_rstn[1]            )
    );

    axi_stream_register_slice #(
        .TDATA_W                            (DATA_W                         ),
        .TID_W                              (0                              ),
        .TDEST_W                            (0                         ),
        .TUSER_W                            (12                        ),
        .MODE                               ("full"                         )
    )uxx_gen_to_reg_slice (
        .s_axis_tvalid                      (d2h_st_valid_0_i               ),
        .s_axis_tdata                       (d2h_st_data_0_i  ),
        .s_axis_tkeep                       (empty2tkeep(d2h_st_empty_0_i)  ),
        .s_axis_tlast                       (d2h_st_eof_0_i                 ),
        .s_axis_tid                         (                               ),
        .s_axis_tdest                       (                               ),
        .s_axis_tuser                       (d2h_st_channel_0_i ),
        .s_axis_tready                      (d2h_st_ready_0_o               ),

        .m_axis_tvalid                      (d2h_axi_st_tvalid                      ),
        .m_axis_tdata                       (d2h_axi_st_tdata                       ),
        .m_axis_tkeep                       (d2h_axi_st_tkeep                       ),
        .m_axis_tlast                       (d2h_axi_st_tlast                       ),
        .m_axis_tid                         (                                       ),
        .m_axis_tdest                       (                       ),
        .m_axis_tuser                       (d2h_axi_st_tid                       ),
        .m_axis_tready                      (d2h_axi_st_tready                      ),
        .aclk                               (pcie_app_clk                            ),
        .aresetn                            (pcie_clk_rstn[1]                        )
    );



/*****************************************************************************\
*                                                                             *
*                  csr_pro for AVMM                                           *
*                                                                             *
\*****************************************************************************/
`ifdef PCIE_GEN5X16
    assign cdc2cfg_avm_addr  = pcie2cdc_avm_addr;
    assign cdc2cfg_avm_read  = pcie2cdc_avm_read;
    assign cdc2cfg_avm_write = pcie2cdc_avm_write;
    assign cdc2cfg_avm_wdat  = pcie2cdc_avm_wdat[31:0];
    
    
    assign pcie2cdc_avm_rdat = {32'd0,cdc2cfg_avm_rdat}  ;
    assign pcie2cdc_avm_rvld = cdc2cfg_avm_rvld   ;
    assign pcie2cdc_avm_wait = cdc2cfg_avm_wait;
    assign pcie2cdc_avm_rspo = cdc2cfg_avm_rspo   ;
    assign pcie2cdc_avm_wrsp = cdc2cfg_avm_wrsp   ;

`else
    //s is pci
    //output  reg                         s_avm_wait ,
    //output  reg     [2*DATA_W-1:0]      s_avm_rdat ,
    //output  reg                         s_avm_rvld ,
    //output  reg     [1:0]               s_avm_rspo ,
    //output  reg                         s_avm_wrsp ,
    //m is cdc
    //output  reg     [ADDR_W:0]          m_avm_addr ,
    //output  reg                         m_avm_read ,
    //output  reg                         m_avm_write,
    //output  reg     [DATA_W-1:0]        m_avm_wdat ,

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
`endif

    axi4_adapter u0_axi4_to_axilite (
		.axi_bridge_in_awid                 (pcie5_bam_axi_mm_awid  ),
		.axi_bridge_in_awaddr               (pcie5_bam_axi_mm_awaddr),
		.axi_bridge_in_awlen                (pcie5_bam_axi_mm_awlen ),
		.axi_bridge_in_awsize               (pcie5_bam_axi_mm_awsize),
		.axi_bridge_in_awburst              (pcie5_bam_axi_mm_awburst),
		.axi_bridge_in_awlock               (pcie5_bam_axi_mm_awlock),
		.axi_bridge_in_awprot               (pcie5_bam_axi_mm_awprot),
		.axi_bridge_in_awvalid              (pcie5_bam_axi_mm_awvalid),
		.axi_bridge_in_awready              (pcie5_bam_axi_mm_awready),
		.axi_bridge_in_wdata                (pcie5_bam_axi_mm_wdata ),
		.axi_bridge_in_wstrb                (pcie5_bam_axi_mm_wstrb ),
		.axi_bridge_in_wlast                (pcie5_bam_axi_mm_wlast ),
		.axi_bridge_in_wvalid               (pcie5_bam_axi_mm_wvalid),
		.axi_bridge_in_wready               (pcie5_bam_axi_mm_wready),
		.axi_bridge_in_bid                  (pcie5_bam_axi_mm_bid   ),
		.axi_bridge_in_bresp                (pcie5_bam_axi_mm_bresp ),
		.axi_bridge_in_bvalid               (pcie5_bam_axi_mm_bvalid),
		.axi_bridge_in_bready               (pcie5_bam_axi_mm_bready),
		.axi_bridge_in_arid                 (pcie5_bam_axi_mm_arid  ),
		.axi_bridge_in_araddr               (pcie5_bam_axi_mm_araddr),
		.axi_bridge_in_arlen                (pcie5_bam_axi_mm_arlen ),
		.axi_bridge_in_arsize               (pcie5_bam_axi_mm_arsize),
		.axi_bridge_in_arburst              (pcie5_bam_axi_mm_arburst),
		.axi_bridge_in_arlock               (pcie5_bam_axi_mm_arlock),
		.axi_bridge_in_arprot               (pcie5_bam_axi_mm_arprot),
		.axi_bridge_in_arvalid              (pcie5_bam_axi_mm_arvalid),
		.axi_bridge_in_arready              (pcie5_bam_axi_mm_arready),
		.axi_bridge_in_rid                  (pcie5_bam_axi_mm_rid   ),
		.axi_bridge_in_rdata                (pcie5_bam_axi_mm_rdata ),
		.axi_bridge_in_rresp                (pcie5_bam_axi_mm_rresp ),
		.axi_bridge_in_rlast                (pcie5_bam_axi_mm_rlast ),
		.axi_bridge_in_rvalid               (pcie5_bam_axi_mm_rvalid),
		.axi_bridge_in_rready               (pcie5_bam_axi_mm_rready),
		.axi_bridge_lite_pf0_m0_awaddr      (csr_axi_lite_awaddr    ),
		.axi_bridge_lite_pf0_m0_awprot      (csr_axi_lite_awprot    ),
		.axi_bridge_lite_pf0_m0_awvalid     (csr_axi_lite_awvalid   ),
		.axi_bridge_lite_pf0_m0_awready     (csr_axi_lite_awready   ),
		.axi_bridge_lite_pf0_m0_wdata       (csr_axi_lite_wdata     ),
		.axi_bridge_lite_pf0_m0_wstrb       (csr_axi_lite_wstrb     ),
		.axi_bridge_lite_pf0_m0_wvalid      (csr_axi_lite_wvalid    ),
		.axi_bridge_lite_pf0_m0_wready      (csr_axi_lite_wready    ),
		.axi_bridge_lite_pf0_m0_bresp       (csr_axi_lite_bresp     ),
		.axi_bridge_lite_pf0_m0_bvalid      (csr_axi_lite_bvalid    ),
		.axi_bridge_lite_pf0_m0_bready      (csr_axi_lite_bready    ),
		.axi_bridge_lite_pf0_m0_araddr      (csr_axi_lite_araddr    ),
		.axi_bridge_lite_pf0_m0_arprot      (csr_axi_lite_arprot    ),
		.axi_bridge_lite_pf0_m0_arvalid     (csr_axi_lite_arvalid   ),
		.axi_bridge_lite_pf0_m0_arready     (csr_axi_lite_arready   ),
		.axi_bridge_lite_pf0_m0_rdata       (csr_axi_lite_rdata     ),
		.axi_bridge_lite_pf0_m0_rresp       (csr_axi_lite_rresp     ),
		.axi_bridge_lite_pf0_m0_rvalid      (csr_axi_lite_rvalid    ),
		.axi_bridge_lite_pf0_m0_rready      (csr_axi_lite_rready    ),
		.axi_bridge_lite_pf1_m0_awaddr      (),
		.axi_bridge_lite_pf1_m0_awprot      (),
		.axi_bridge_lite_pf1_m0_awvalid     (),
		.axi_bridge_lite_pf1_m0_awready     (1'b0),
		.axi_bridge_lite_pf1_m0_wdata       (),
		.axi_bridge_lite_pf1_m0_wstrb       (),
		.axi_bridge_lite_pf1_m0_wvalid      (),
		.axi_bridge_lite_pf1_m0_wready      (1'b0),
		.axi_bridge_lite_pf1_m0_bresp       (2'b0),
		.axi_bridge_lite_pf1_m0_bvalid      (1'b0),
		.axi_bridge_lite_pf1_m0_bready      (),
		.axi_bridge_lite_pf1_m0_araddr      (),
		.axi_bridge_lite_pf1_m0_arprot      (),
		.axi_bridge_lite_pf1_m0_arvalid     (),
		.axi_bridge_lite_pf1_m0_arready     (1'b0),
		.axi_bridge_lite_pf1_m0_rdata       (32'b0),
		.axi_bridge_lite_pf1_m0_rresp       (2'b0),
		.axi_bridge_lite_pf1_m0_rvalid      (1'b0),
		.axi_bridge_lite_pf1_m0_rready      (),
		.axi_bridge_lite_pf1_ext_m0_awaddr  (),
		.axi_bridge_lite_pf1_ext_m0_awprot  (),
		.axi_bridge_lite_pf1_ext_m0_awvalid (),
		.axi_bridge_lite_pf1_ext_m0_awready (1'b0),
		.axi_bridge_lite_pf1_ext_m0_wdata   (),
		.axi_bridge_lite_pf1_ext_m0_wstrb   (),
		.axi_bridge_lite_pf1_ext_m0_wvalid  (),
		.axi_bridge_lite_pf1_ext_m0_wready  (1'b0),
		.axi_bridge_lite_pf1_ext_m0_bresp   (2'b0),
		.axi_bridge_lite_pf1_ext_m0_bvalid  (1'b0),
		.axi_bridge_lite_pf1_ext_m0_bready  (),
		.axi_bridge_lite_pf1_ext_m0_araddr  (),
		.axi_bridge_lite_pf1_ext_m0_arprot  (),
		.axi_bridge_lite_pf1_ext_m0_arvalid (),
		.axi_bridge_lite_pf1_ext_m0_arready (1'b0),
		.axi_bridge_lite_pf1_ext_m0_rdata   (32'b0),
		.axi_bridge_lite_pf1_ext_m0_rresp   (2'b0),
		.axi_bridge_lite_pf1_ext_m0_rvalid  (1'b0),
		.axi_bridge_lite_pf1_ext_m0_rready  (),
		.axi_mm_clk_clk                     (pcie_app_clk),
		.axi_lite_clk_clk                   (clk250m),
		.axi_mm_reset_reset                 (pcie_app_rst),
		.axi_lite_reset_reset               (~axil_rst_n)
	);

    // RoCEv2 RDMA 引擎（src/roce/）：AVMM 分流 + CSR、BAS DMA、TX 2:1 仲裁、RX 监听
    roce_top #(
        .DATA_W                             (DATA_W             ),
        .USERF_W                            (USERF_W            ),
        // 必须与 clk200m.ip 的 outclk1 一致（250 MHz 分支 = 250.0，周期 4.000 ns；B6409–B6415 是 125 MHz）。
        // 这里漏改过一次：B6409 只改了 roce_top/engine/csr/req 的默认值，本行是显式传参，
        // 把默认值全盖掉，导致 REG_CORE_CLOCK 读 100、TICK_CYCLES 410 拍而非 512
        // （RNR/重传定时器提前 25%），见 roce-optimization-log.md §37.5。
        .CORE_CLOCK_MHZ                     (250                )
    )
    u99_roce_top
    (
        .clk                                (clk250m            ),
        .rst_n                              (axil_clk_rstn[1]   ),
        .core_clk                           (clk100m            ),
        .s_avm_addr                         (cdc2cfg_avm_addr   ),
        .s_avm_read                         (cdc2cfg_avm_read   ),
        .s_avm_write                        (cdc2cfg_avm_write  ),
        .s_avm_wdat                         (cdc2cfg_avm_wdat   ),
        .s_avm_wait                         (cdc2cfg_avm_wait   ),
        .s_avm_rdat                         (cdc2cfg_avm_rdat   ),
        .s_avm_rvld                         (cdc2cfg_avm_rvld   ),
        .s_avm_rspo                         (cdc2cfg_avm_rspo   ),
        .s_avm_wrsp                         (cdc2cfg_avm_wrsp   ),
        .l_avm_addr                         (cfg_avm_addr       ),
        .l_avm_read                         (cfg_avm_read       ),
        .l_avm_write                        (cfg_avm_write      ),
        .l_avm_wdat                         (cfg_avm_wdat       ),
        .l_avm_wait                         (cfg_avm_wait       ),
        .l_avm_rdat                         (cfg_avm_rdat       ),
        .l_avm_rvld                         (cfg_avm_rvld       ),
        .l_avm_rspo                         (cfg_avm_rspo       ),
        .l_avm_wrsp                         (cfg_avm_wrsp       ),
        .pcie_clk                           (pcie_app_clk       ),
        .pcie_rst_n                         (pcie_clk_rstn[1]   ),
        .bas_m2s                            (pcie5_bas_m2s      ),
        .bas_s2m                            (pcie5_bas_s2m      ),
        .mac_clk                            (eth_mac_clk        ),
        .mac_rst_n                          (mac_clk_rstn[1]    ),
        .link_up                            (eth_rx_pcs_ready   ),
        .rx_pfc                             (rx_pfc             ),
        .tx_pfc                             (roce_tx_pfc        ),
        .qdma_tvalid                        (qdma_to_roce_tvalid),
        .qdma_tdata                         (qdma_to_roce_tdata ),
        .qdma_tusef                         (qdma_to_roce_tusef ),
        .qdma_tlast                         (qdma_to_roce_tlast ),
        .qdma_tready                        (qdma_to_roce_tready),
        .tx_tvalid                          (qdma_to_select_tvalid),
        .tx_tdata                           (qdma_to_select_tdata ),
        .tx_tusef                           (qdma_to_select_tusef ),
        .tx_tlast                           (qdma_to_select_tlast ),
        .tx_tready                          (qdma_to_select_tready),
        .rx_tvalid                          ({rx_to_rcv_tvalid[1], rx_to_rcv_tvalid[0]}),
        .rx_tdata                           ({rx_to_rcv_tdata[1],  rx_to_rcv_tdata[0] }),
        .rx_tempty                          ({rx_to_rcv_tempty[1], rx_to_rcv_tempty[0]}),
        .rx_tuerr                           ({rx_to_rcv_tuerr[1],  rx_to_rcv_tuerr[0] }),
        .rx_tlast                           ({rx_to_rcv_tlast[1],  rx_to_rcv_tlast[0] }),
        /* 调试观测（eth_mac_clk / pcie_app_clk 域），位段见 roce/roce_debug.sv。
         * 只观测，不改变任何数据通路信号。 */
        .mac_debug                          (roce_mac_debug     ),
        .pcie_debug                         (roce_pcie_debug    )
    );

    avm_config #(
        .USER_NUM                           (AVM_USER_NUM    )
    )
    u96_avm_config
    (
        .avm_addr                           (cfg_avm_addr       ),
        .avm_byte                           (8'h0f              ),
        .avm_read                           (cfg_avm_read       ),
        .avm_write                          (cfg_avm_write      ),
        .avm_wdat                           (cfg_avm_wdat       ),
        .avm_bcnt                           ( 4'd1              ),
        .avm_wait                           (cfg_avm_wait       ),
        .avm_rdat                           (cfg_avm_rdat       ),
        .avm_rvld                           (cfg_avm_rvld       ),
        .avm_rspo                           (cfg_avm_rspo       ),
        .avm_wrsp                           (cfg_avm_wrsp       ),
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

    /*
     * FPGA 结温（温度监控，2026-10-22）
     *
     * mb_acquire 通过 SDM mailbox 周期轮询 sysmon 温度，落到 TEMP_LOC0_0 ~
     * TEMP_LOC4_1（各 32bit，SDM 原始值，编码见 SDM Mailbox 文档）。
     *
     * 注意命名与 temp_loc 的对应关系（mb_acquire.v:226-230, 553-562）：
     *   TEMP_LOC0_0  <- cnt1==1，即 temp_loc=1 的 temp0（core1）
     *   TEMP_LOC4_0  <- cnt1==0，即 temp_loc=0 的 temp0（core0）
     * 名字里的数字比 temp_loc 大 1，别按字面对应。这里取 TEMP_LOC0_0 接到
     * system_config_register 的 0x038（REG_FPGA_TEMPER），驱动按时间序列采样；
     * 需要换通道时只改下面 assign 一行即可。
     *
     * 编码尚未在板上校准，所以：
     *   - 0x038 只取低 10 位（与 fpga_temp 端口宽度一致），单位按 ℃ 处理；
     *   - 0x03C 输出 32 位原始值，用于上板比对 CPLD/BMC 的真实温度后确定
     *     是否需要 /128、/256 或符号位处理，确认后再改这里的换算。
     * 在此之前不要把 0x038 的读数当成精确温度用于下结论。
     */
    wire [31:0] fpga_temp_raw_w;
    wire [9:0]  fpga_temp_w;

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
        .debug_pcie_d2h_sof_cnt             ({32'b0,pcie_d2h_sof_cnt    }),
        .debug_stream_mark0_eop_cnt         (64'b0),
        .debug_stream_mark1_eop_cnt         (64'b0),
        .debug_pcie_h2d_eop_cnt             ({32'b0,pcie_h2d_eop_cnt    }),
        .debug_rdma2qdma_eop_cnt            ({32'b0,rdma2qdma_eop_cnt   }),
        .debug_qdma_h2d_eop_cnt             ({32'b0,qdma_h2d_eop_cnt    }),
        .debug_axis_select_eop_cnt          ({32'b0,axis_select_eop_cnt }),
        .debug_segm2gap_eop_cnt             ({32'b0,segm2h2l_eop_cnt    }), 
        .debug_gap2mac_eop_cnt              ({32'b0,gap2mac_eop_cnt     }), 
        .debug_mod_int_status_reg           ({5'b0,mod_int_status_reg   }), 
        .debug_eth_fcs_err_cnt              (eth_fcs_err_cnt             ),
        .debug_eth_mfmd_err_cnt             (eth_mfmd_err_cnt            ),
        .debug_eth_under_over_err_cnt       (eth_under_over_err_cnt      ),
        .debug_eth_plen_err_cnt             (eth_plen_err_cnt            ),
        .debug_eth_fifo_full_err_cnt        (eth_fifo_full_err_cnt       ),
        .debug_pfc_pkt_drop_cnt             (pfc_pkt_drop_cnt            ),
        .debug_pfc_pkt_in_cnt               (pfc_pkt_in_cnt              ),
        .debug_pfc_pkt_out_cnt              (pfc_pkt_out_cnt             ),
        .fpga_temp                          (fpga_temp_w                 ),
        .fpga_temp_raw                      (fpga_temp_raw_w             ),
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
        .tx_pfc                             (tx_pfc             ),
        .rx_pfc                             (rx_pfc             ),
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
        pcie_h2d_eop_vld <= h2d_axi_st_tvalid & h2d_axi_st_tlast & h2d_axi_st_tready ;
        rdma2qdma_eop_vld <= regl_to_qdma_tready & regl_to_qdma_tvalid & regl_to_qdma_tlast;
    end

    always @(posedge eth_mac_clk ) begin
        qdma_h2d_eop_vld     <= qdma_to_select_tvalid & qdma_to_select_tready & qdma_to_select_tlast;
        axis_select_eop_vld  <= select_to_segm_tvalid & select_to_segm_last & select_to_segm_tready;

        if(!mac_clk_rstn[0])
            segm2h2l_frame_d1 <= 16'b0;
        else if(segm_to_reg_tvalid)
            segm2h2l_frame_d1 <= segm_to_reg_frame;

        segm2h2l_eop_num  <= segm_to_reg_tvalid ? eop_num({segm_to_reg_frame,segm2h2l_frame_d1[15]}) : 2'd0;

        if(!mac_clk_rstn[0])
            gap2mac_frame_d1 <= 16'b0;
        else if(gap_to_mac_tvalid)
            gap2mac_frame_d1 <= gap_to_mac_frame;

        gap2mac_eop_num  <= gap_to_mac_tvalid ? eop_num({gap_to_mac_frame,gap2mac_frame_d1[MAC_FRAME_W-1]}) : 2'd0;
    end

    cnt#(.WIDTH(32))cnt_u42(.clear(statis_cnt_clear_en),.clk(pcie_app_clk),.vld(pcie_h2d_eop_vld),.step({15'b0,1'b1}),.cnt(pcie_h2d_eop_cnt));
    cnt#(.WIDTH(32))cnt_u43(.clear(statis_cnt_clear_en),.clk(pcie_app_clk),.vld(rdma2qdma_eop_vld),.step({15'b0,1'b1}),.cnt(rdma2qdma_eop_cnt));
    cnt#(.WIDTH(32))cnt_u44(.clear(statis_cnt_clear_en),.clk(eth_mac_clk),.vld(qdma_h2d_eop_vld),.step({15'b0,1'b1}),.cnt(qdma_h2d_eop_cnt));
    cnt#(.WIDTH(32))cnt_u45(.clear(statis_cnt_clear_en),.clk(eth_mac_clk),.vld(axis_select_eop_vld),.step({15'b0,1'b1}),.cnt(axis_select_eop_cnt));
    cnt#(.WIDTH(32))cnt_u46(.clear(statis_cnt_clear_en),.clk(eth_mac_clk),.vld(|segm2h2l_eop_num),.step({14'b0,segm2h2l_eop_num}),.cnt(segm2h2l_eop_cnt));
    cnt#(.WIDTH(32))cnt_u47(.clear(statis_cnt_clear_en),.clk(eth_mac_clk),.vld(|gap2mac_eop_num),.step({14'b0,gap2mac_eop_num}),.cnt(gap2mac_eop_cnt));

    wire    [15:0]      data_fifo_afull0;
    wire    [15:0]      data_fifo_afull1;
    wire    [15:0]      data_fifo_empty0;
    wire    [15:0]      data_fifo_empty1;

    assign  data_fifo_afull0 = u6_rx_path.data_concat0_u.data_fifo_afull;
    assign  data_fifo_afull1 = u6_rx_path.data_concat1_u.data_fifo_afull;
    assign  data_fifo_empty0 = u6_rx_path.data_concat0_u.data_fifo_empty;
    assign  data_fifo_empty1 = u6_rx_path.data_concat1_u.data_fifo_empty;

    /* ------------------------------------------------------------------------
     * RoCE 引擎调试总线（2026-10-25）
     *
     * 为什么在这里组装而不是在 roce_top 内部：TX 组包流水（axis_select ->
     * axis_to_segm -> 寄存器片 -> 位宽转换 -> MAC）在顶层，RoCE 引擎看不到。
     * 卡死现象是「RoCE 引擎计数全冻结、netdev ping 仍通」，要判断帧停在哪一级
     * 必须同时看到整条链。
     *
     * 源信号全部在 eth_mac_clk 域；roce_top 内部再做采样握手跨到 core 域。
     * 各字段用命名切片赋值（不写一整个拼接），字段位置见 roce/roce_debug.sv
     * 的地址表——那边的 mac_debug 端口就是按这张表切的。
     * ---------------------------------------------------------------------- */
    /* RX 侧 lane0/lane1 的 data_concat FIFO 水位（各 16 位 afull + 16 位 empty） */
    wire [31:0] rx_lane0_fifo = {data_fifo_afull0, data_fifo_empty0};
    wire [31:0] rx_lane1_fifo = {data_fifo_afull1, data_fifo_empty1};
    /* rx_mux_nto1 的 FIFO 标志（与原来 mod_int_status_reg[43:54] 同源）：
     * [0] info_afull [1] m_info_empty [3:2] axis_ram_full [5:4] axis_ram_empty
     * [7:6] axis_eop_empty [9:8] s_drop_afull [11:10] s_drop_empty */
    wire [13:0] rx_mux_fifo_dbg = {
        2'd0,
        u7_rx_filet.u3_rx_mux_nto1.s_drop_fifo_empty,
        u7_rx_filet.u3_rx_mux_nto1.s_drop_fifo_afull,
        u7_rx_filet.u3_rx_mux_nto1.axis_fifo_eop_empty,
        u7_rx_filet.u3_rx_mux_nto1.axis_fifo_ram_empty,
        u7_rx_filet.u3_rx_mux_nto1.axis_fifo_ram_full,
        u7_rx_filet.u3_rx_mux_nto1.m_info_fifo_empty,
        u7_rx_filet.u3_rx_mux_nto1.s_info_fifo_afull
    };

    /* 总线布局（与 roce/roce_debug.sv 的 mac_debug 端口逐字段对应，改一处必须改两处）：
     *   [  7:  0] tx_valid   [ 15:  8] tx_ready   [ 23: 16] tx_last
     *   [ 28: 24] axis_select [ 38: 29] axis_to_segm
     *   [ 41: 39] rx_valid   [ 44: 42] rx_ready
     *   [ 76: 45] lane0 fifo [108: 77] lane1 fifo
     *   [122:109] rx_mux_fifo
     *   [136:123] 保留 */
    /* TX 链实测 7 级（从主机到 MAC）：
     *   bit0 qdma_h2d        : QDMA 出口 h2d_axi_st_*        （pcie_app_clk！见下）
     *   bit1 qdma_to_regslice: rdma_timestamp_mark 输出 rdma_to_regl_*
     *   bit2 qdma_to_select  : u82 寄存器片输出 regl_to_qdma_*
     *   bit3 select_to_segm  : axis_select 出口（qdma_to_select_*）
     *   bit4 segm_to_reg     : axis_to_segm 出口
     *   bit5 reg_to_h2l      : u03 寄存器片出口
     *   bit6 gap_to_mac      : 位宽转换器出口（MAC 入口）
     * 注意 bit0/bit1/bit2 在 pcie_app_clk 与 eth_mac_clk 之间有 CDC（u9/qdma 与
     * rdma_timestamp_mark 都在 pcie_app_clk），这里按 eth_mac_clk 采样只用于看
     * 「大致有没有在动」；判死锁看 bit2 以上（纯 eth_mac_clk 域）以及下的快照。 */
    assign roce_mac_debug[  7:  0] = {gap_to_mac_tvalid, reg_to_h2l_tvalid, segm_to_reg_tvalid,
                                      select_to_segm_tvalid, qdma_to_select_tvalid,
                                      regl_to_qdma_tvalid, rdma_to_regl_tvalid, 1'b0};
    assign roce_mac_debug[ 15:  8] = {gap_to_mac_tready, reg_to_h2l_tready, segm_to_reg_tready,
                                      select_to_segm_tready, qdma_to_select_tready,
                                      regl_to_qdma_tready, rdma_to_regl_tready, 1'b0};
    /* 这一段链路没有 tlast（其含义在 emty/frame 矢量里），所以 last 位只接真有 tlast 的级；
     * 其余填 0，判读时忽略。bit4/bit3 用「本拍 frame 矢量非 0」代表这一级有一帧在走。 */
    assign roce_mac_debug[ 23: 16] = {1'b0, 1'b0, |segm_to_reg_frame,
                                      1'b0, qdma_to_select_tlast,
                                      1'b0, rdma_to_regl_tlast, 1'b0};
    assign roce_mac_debug[ 28: 24] = axis_select_dbg;
    assign roce_mac_debug[ 38: 29] = axis_to_segm_dbg;
    assign roce_mac_debug[ 41: 39] = {rcv_to_qdma_tvalid, rx_to_rcv_tvalid[1], rx_to_rcv_tvalid[0]};
    assign roce_mac_debug[ 44: 42] = {rcv_to_qdma_tready, rx_to_rcv_tready[1], rx_to_rcv_tready[0]};
    assign roce_mac_debug[ 76: 45] = rx_lane0_fifo;
    assign roce_mac_debug[108: 77] = rx_lane1_fifo;
    assign roce_mac_debug[122:109] = rx_mux_fifo_dbg;
    assign roce_mac_debug[136:123] = 14'd0;      // 预留

    /* BAS 打包总线的观测点（pcie_app_clk 域）。位段见 roce_bas_if.vh：
     *   ARVALID 1257 / ARADDR 1325:1262 / ARLEN 1349:1342
     *   AWADDR   68:5                            / ARREADY 9 / RVALID 10 / RREADY 1359
     * 这里只取「当前挂在 AXI 上的那笔 AR」和最近一次 AW 地址——卡死时用来看
     * 到底是哪条读请求回不来（0x0594~0x05CC 的快照字段）。 */
    assign roce_pcie_debug[ 63:  0] = pcie5_bas_m2s[1325:1262];              // ARADDR
    assign roce_pcie_debug[ 71: 64] = pcie5_bas_m2s[1349:1342];              // ARLEN
    assign roce_pcie_debug[ 75: 72] = {pcie5_bas_s2m[9],                      // ARREADY
                                       pcie5_bas_m2s[1257],                   // ARVALID
                                       pcie5_bas_m2s[1359],                   // RREADY
                                       pcie5_bas_s2m[10]};                    // RVALID
    assign roce_pcie_debug[107: 76] = pcie5_bas_m2s[68:37];                   // AWADDR[31:0]

    always @(posedge clk250m ) begin
        mod_int_status_reg[00] <= 1'b0 ;   // pkt_gen 已删除
        mod_int_status_reg[01] <= 1'b0 ;
        mod_int_status_reg[02] <= 1'b0 ;
        mod_int_status_reg[03] <= 1'b0 ;
        mod_int_status_reg[04] <= qdma_to_select_tvalid;
        mod_int_status_reg[05] <= ~qdma_to_select_tready;
        mod_int_status_reg[06] <= 1'b0 ;   // pkt_gen 已删除
        mod_int_status_reg[07] <= 1'b0 ;
        mod_int_status_reg[08] <= 1'b0 ;
        mod_int_status_reg[09] <= 1'b0 ;
        mod_int_status_reg[10] <= 1'b0 ;
        mod_int_status_reg[11] <= 1'b0 ;
        mod_int_status_reg[12] <= 1'b0 ;
        mod_int_status_reg[13] <= 1'b0 ;
        mod_int_status_reg[14] <= select_to_segm_tvalid ;
        mod_int_status_reg[15] <= ~select_to_segm_tready;
        mod_int_status_reg[16] <= 1'b0 ;
        mod_int_status_reg[17] <= 1'b0 ;
        mod_int_status_reg[18] <= 1'b0 ;
        mod_int_status_reg[19] <= 1'b0 ;
        mod_int_status_reg[20] <= ~gap_to_mac_tready;
        mod_int_status_reg[21] <= ~gap_to_mac_tvalid;
        mod_int_status_reg[22] <= gap_to_mac_frame!=0?1'b1:1'b0;
        mod_int_status_reg[23] <= rx_to_rcv_tvalid[0];
        mod_int_status_reg[24] <= rx_to_rcv_tvalid[1];
        mod_int_status_reg[25] <= rcv_to_qdma_tvalid;
        mod_int_status_reg[26] <= ~rcv_to_qdma_tready;
        mod_int_status_reg[27] <= d2h_st_valid_0_i;
        mod_int_status_reg[28] <= ~d2h_st_ready_0_o;
        mod_int_status_reg[29] <= h2d_axi_st_tvalid;
        mod_int_status_reg[30] <= ~h2d_axi_st_tready;
        mod_int_status_reg[31] <= rdma_to_regl_tvalid;
        mod_int_status_reg[32] <= ~rdma_to_regl_tready;
        mod_int_status_reg[33] <= regl_to_qdma_tvalid;
        mod_int_status_reg[34] <= ~regl_to_qdma_tready;
        mod_int_status_reg[35] <= |data_fifo_afull0;
        mod_int_status_reg[36] <= ~(&data_fifo_empty0);
        mod_int_status_reg[37] <= u6_rx_path.data_concat0_u.info_fifo_afull;
        mod_int_status_reg[38] <= ~u6_rx_path.data_concat0_u.info_fifo_empty;
        mod_int_status_reg[39] <= |data_fifo_afull1;
        mod_int_status_reg[40] <= ~(&data_fifo_empty1);
        mod_int_status_reg[41] <= u6_rx_path.data_concat1_u.info_fifo_afull;
        mod_int_status_reg[42] <= ~u6_rx_path.data_concat1_u.info_fifo_empty;
        mod_int_status_reg[43] <= u7_rx_filet.u3_rx_mux_nto1.s_drop_fifo_afull[0];
        mod_int_status_reg[44] <= ~u7_rx_filet.u3_rx_mux_nto1.s_drop_fifo_empty[0];
        mod_int_status_reg[45] <= u7_rx_filet.u3_rx_mux_nto1.s_drop_fifo_afull[1];
        mod_int_status_reg[46] <= ~u7_rx_filet.u3_rx_mux_nto1.s_drop_fifo_empty[1];
        mod_int_status_reg[47] <= u7_rx_filet.u3_rx_mux_nto1.s_info_fifo_afull;
        mod_int_status_reg[48] <= ~u7_rx_filet.u3_rx_mux_nto1.m_info_fifo_empty;
        mod_int_status_reg[49] <= u7_rx_filet.u3_rx_mux_nto1.axis_fifo_ram_full[0];
        mod_int_status_reg[50] <= ~u7_rx_filet.u3_rx_mux_nto1.axis_fifo_ram_empty[0];
        mod_int_status_reg[51] <= ~u7_rx_filet.u3_rx_mux_nto1.axis_fifo_eop_empty[0];
        mod_int_status_reg[52] <= u7_rx_filet.u3_rx_mux_nto1.axis_fifo_ram_full[1];
        mod_int_status_reg[53] <= ~u7_rx_filet.u3_rx_mux_nto1.axis_fifo_ram_empty[1];
        mod_int_status_reg[54] <= ~u7_rx_filet.u3_rx_mux_nto1.axis_fifo_eop_empty[1];
        mod_int_status_reg[55] <= u9_qdma_top.u1_qdma_function.qid_fifo_full;
        mod_int_status_reg[56] <= ~u9_qdma_top.u1_qdma_function.qid_fifo_empty;
        mod_int_status_reg[57] <= u9_qdma_top.u1_qdma_function.axis_fifo_u.ram_full;
        mod_int_status_reg[58] <= ~u9_qdma_top.u1_qdma_function.axis_fifo_u.ram_empty;
        mod_int_status_reg[59] <= u9_qdma_top.u1_qdma_function.axis_fifo_u.eop_empty;
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


   

/*****************************************************************************\
*                                                                             *
*                  DDR4 x16 component 2GB                                     *
*                                                                             *
\*****************************************************************************/   

   wire 					 ddr4_reset_req;
   wire 					 ddr4_reset_done;
   wire 					 ddr4_cal_sucess;
   wire 					 ddr4_cal_fail;
   wire 					 ddr4_usr_rst;
   wire 					 ddr4_usr_clk; //333M ?

   wire  					 app_amm_ready;
   wire 					 app_amm_read;
   wire 					 app_amm_write;
   wire [26:0] 				 app_amm_addr;
   wire [127:0] 			 app_amm_rdat;
   wire 					 app_amm_rvld;
   wire [127:0] 			 app_amm_wdat;
   wire [15:0]               app_amm_byte;
   wire [6:0] 				 app_amm_bcnt;
 `ifndef SIMULATION
   ddr4_top
     U_ddr4_top(
                .c0_sys_clk_p             (c0_sys_clk_p            ),
          
                .c0_ddr4_act_n            (c0_ddr4_act_n[0:0]      ),
                .c0_ddr4_adr              (c0_ddr4_adr[16:0]       ),
                .c0_ddr4_alert_n          (c0_ddr4_alert_n[0:0]    ),
                .c0_ddr4_ba               (c0_ddr4_ba[1:0]         ),
                .c0_ddr4_bg               (c0_ddr4_bg[0:0]         ),
                .c0_ddr4_ck_c             (c0_ddr4_ck_c[0:0]       ),
                .c0_ddr4_ck_t             (c0_ddr4_ck_t[0:0]       ),
                .c0_ddr4_cke              (c0_ddr4_cke[0:0]        ),
                .c0_ddr4_cs_n             (c0_ddr4_cs_n[0:0]       ),
                .c0_ddr4_odt              (c0_ddr4_odt[0:0]        ),
                .c0_ddr4_dm_n             (c0_ddr4_dm_n[1:0]       ),
                .c0_ddr4_dq               (c0_ddr4_dq[15:0]        ),
                .c0_ddr4_dqs_c            (c0_ddr4_dqs_c[1:0]      ),
                .c0_ddr4_dqs_t            (c0_ddr4_dqs_t[1:0]      ),
                .c0_ddr4_par              (c0_ddr4_par[0:0]        ),
                .c0_ddr4_reset_n          (c0_ddr4_reset_n[0:0]    ),
               
                .c0_oct_oct_rzqin         (c0_oct_oct_rzqin[0:0]   ),
         
                .local_reset_req          (ddr4_reset_req          ),
                .local_reset_done         (ddr4_reset_done         ),
                                          
                .local_cal_success        (ddr4_cal_sucess         ),
                .local_cal_fail           (ddr4_cal_fail           ),
                                          
                .app_emif_usr_rst         (ddr4_usr_rst            ),
                .app_emif_usr_clk         (ddr4_usr_clk            ), //333.25M ?
                
                .app_amm_ready            (app_amm_ready           ),
                .app_amm_read             (app_amm_read            ),
                .app_amm_write            (app_amm_write           ),
                .app_amm_addr             (app_amm_addr            ),
                .app_amm_rdat             (app_amm_rdat            ),
                .app_amm_rvld             (app_amm_rvld            ),
                .app_amm_wdat             (app_amm_wdat            ),
                .app_amm_byte             (app_amm_byte            ),
                .app_amm_bcnt             (app_amm_bcnt            )
                );

/*****************************************************************************\
*                                                                             *
*                  DDR read and write tester                                  *
*                                                                             *
\*****************************************************************************/      
   wire				test_enb;
   wire				test_type;
   wire		[1:0]	test_wr;
   wire				test_done;
   wire				err_flag;
   wire		[31:0]	err_cnt;
   wire				rd_done;
   wire		[31:0]	rd_addr;
   wire				addr_mode;
   wire		[7:0]	addr_seed;
   wire		[31:0]	DDR_END_ADDR;
   wire		[1:0]	dat_mode;
   wire		[31:0]	ddr_dat0;
   wire		[31:0]	ddr_dat1;
   wire		[31:0]	ddr_dat2;
   wire		[31:0]	ddr_dat3;
   wire		[31:0]	total_time_w;
   wire		[31:0]	total_cnt_w;
   wire		[31:0]	total_time_r;
   wire		[31:0]	total_cnt_r;
   
   reg				test_enb_d1		   , test_enb_d2	 ;	
   reg				test_type_d1       , test_type_d2    ;
   reg		[1:0]	test_wr_d1         , test_wr_d2      ;
   reg				test_done_d1       , test_done_d2    ;
   reg				err_flag_d1        , err_flag_d2     ;
   reg		[31:0]	err_cnt_d1         , err_cnt_d2      ;
   reg				rd_done_d1         , rd_done_d2      ;
   reg		[31:0]	rd_addr_d1         , rd_addr_d2      ;
   reg				addr_mode_d1       , addr_mode_d2    ;
   reg		[7:0]	addr_seed_d1       , addr_seed_d2    ;
   reg		[31:0]	DDR_END_ADDR_D1    , DDR_END_ADDR_D2 ;
   reg		[1:0]	dat_mode_d1        , dat_mode_d2     ;
   reg		[31:0]	ddr_dat0_d1        , ddr_dat0_d2     ;
   reg		[31:0]	ddr_dat1_d1        , ddr_dat1_d2     ;
   reg		[31:0]	ddr_dat2_d1        , ddr_dat2_d2     ;
   reg		[31:0]	ddr_dat3_d1        , ddr_dat3_d2     ;
   reg		[31:0]	total_time_w_d1    , total_time_w_d2 ;
   reg		[31:0]	total_cnt_w_d1     , total_cnt_w_d2  ;
   reg		[31:0]	total_time_r_d1    , total_time_r_d2 ;
   reg		[31:0]	total_cnt_r_d1     , total_cnt_r_d2  ;
   reg				ddr4_cal_sucess_d1 , ddr4_cal_sucess_d2	;
   reg				ddr4_cal_fail_d1   , ddr4_cal_fail_d2	;
   
   
   ddr4_tg
     U_ddr4_tg(
               .rst                      (ddr4_usr_rst             ),
               .clk                      (ddr4_usr_clk             ),
               
               .test_enb				 (test_enb_d2  			   ),
               .test_type				 (test_type_d2 			   ),
               .ddr_wr				  	 (test_wr_d2   			   ),
               .test_done				 (test_done  			   ),
               .err_flag                 (err_flag   			   ),
               .err_cnt                  (err_cnt    			   ),
               .rd_done					 (rd_done				   ),
               .rd_addr					 (rd_addr				   ),
                                                    
               .addr_mode                (addr_mode_d2 			   ),
               .addr_seed                (addr_seed_d2 			   ),
               .DDR_END_ADDR			 (DDR_END_ADDR_D2[26:0]	   ),
                                                                
               .dat_mode                 (dat_mode_d2  			   ),
               .ddr_dat0                 (ddr_dat0_d2			   ),
               .ddr_dat1                 (ddr_dat1_d2			   ),
               .ddr_dat2                 (ddr_dat2_d2  			   ),
               .ddr_dat3                 (ddr_dat3_d2  			   ),
                                                 
               .total_time_w             (total_time_w			   ),
               .total_cnt_w              (total_cnt_w		   	   ),
               .total_time_r		     (total_time_r			   ),
               .total_cnt_r				 (total_cnt_r			   ),
               
               .app_amm_ready            (app_amm_ready            ),
               .app_amm_read             (app_amm_read             ),
               .app_amm_write            (app_amm_write            ),
               .app_amm_addr             (app_amm_addr             ),
               .app_amm_rdat             (app_amm_rdat             ),
               .app_amm_rvld             (app_amm_rvld             ),
               .app_amm_wdat             (app_amm_wdat             ),
               .app_amm_byte             (app_amm_byte             ),
               .app_amm_bcnt             (app_amm_bcnt             )
               );

//跨时钟域处理
always @(posedge ddr4_usr_clk)
begin
    test_enb_d1 	<= test_enb;		test_enb_d2 	<= test_enb_d1;
    test_type_d1	<= test_type;       test_type_d2	<= test_type_d1;
    test_wr_d1		<= test_wr;         test_wr_d2		<= test_wr_d1;
    addr_mode_d1	<= addr_mode;       addr_mode_d2	<= addr_mode_d1;
    addr_seed_d1	<= addr_seed;       addr_seed_d2	<= addr_seed_d1;
    dat_mode_d1		<= dat_mode;        dat_mode_d2		<= dat_mode_d1;
    ddr_dat0_d1		<= ddr_dat0;        ddr_dat0_d2		<= ddr_dat0_d1;
    ddr_dat1_d1		<= ddr_dat1;        ddr_dat1_d2		<= ddr_dat1_d1;
    ddr_dat2_d1		<= ddr_dat2;        ddr_dat2_d2		<= ddr_dat2_d1;
    ddr_dat3_d1		<= ddr_dat3;        ddr_dat3_d2		<= ddr_dat3_d1;
                                        
    DDR_END_ADDR_D1	<= DDR_END_ADDR;    DDR_END_ADDR_D2	<= DDR_END_ADDR_D1;

end

always @(posedge clk250m)
begin
    test_done_d1	<= test_done;		test_done_d2	<= test_done_d1;
    err_flag_d1		<= err_flag;        err_flag_d2		<= err_flag_d1;
    err_cnt_d1		<= err_cnt;         err_cnt_d2		<= err_cnt_d1;
    rd_done_d1		<= rd_done;         rd_done_d2		<= rd_done_d1;
    rd_addr_d1		<= rd_addr;         rd_addr_d2		<= rd_addr_d1;
                                        
    total_time_w_d1	<= total_time_w;    total_time_w_d2	<= total_time_w_d1;
    total_time_r_d1	<= total_time_r;    total_time_r_d2	<= total_time_r_d1;
    total_cnt_w_d1	<= total_cnt_w;     total_cnt_w_d2	<= total_cnt_w_d1;
    total_cnt_r_d1	<= total_cnt_r;     total_cnt_r_d2	<= total_cnt_r_d1;

    ddr4_cal_fail_d1   <= ddr4_cal_fail;	ddr4_cal_fail_d2  	<= ddr4_cal_fail_d1;
    ddr4_cal_sucess_d1 <= ddr4_cal_sucess;	ddr4_cal_sucess_d2  <= ddr4_cal_sucess_d1; 
end

 /*****************************************************************************\
*                                                                             *
*                  ddr4  debug                                     			  *
*                                                                             *
\*****************************************************************************/   
   wire                      ddr_ctl_req;
   wire 					 ddr_ctl_rwn;
   wire [31:0] 				 ddr_ctl_addr;
   wire [127:0]				 ddr_ctl_wdat;
   wire [127:0]				 ddr_ctl_rdat;
   wire 					 ddr_ctl_ack;
   
/*
   ddr_ctl
     U_ddr_debug_ctl(
              .rst                       (ddr4_usr_rst           ),
              .clk                       (ddr4_usr_clk           ),
                                                                 
              //ddr controller csr                                 
              .ddr_ctl_req               (ddr_ctl_req            ),
              .ddr_ctl_rwn               (ddr_ctl_rwn            ),
              .ddr_ctl_addr              (ddr_ctl_addr           ),
              .ddr_ctl_wdat              (ddr_ctl_wdat           ),
              .ddr_ctl_byte				 (ddr_ctl_byte			 ),
              .ddr_ctl_rdat              (ddr_ctl_rdat           ),
              .ddr_ctl_ack               (ddr_ctl_ack            ),

              .app_amm_ready			 (ddr_dbg_ready			 ),																
              .app_amm_write             (ddr_dbg_write			 ),
              .app_amm_read              (ddr_dbg_read 			 ),
              .app_amm_addr              (ddr_dbg_addr 			 ),
              .app_amm_wdat              (ddr_dbg_wdat 			 ),
              .app_amm_rdat              (ddr_dbg_rdat 			 ),
              .app_amm_rvld              (ddr_dbg_rvld 			 ),
              .app_amm_byte          	 (ddr_dbg_byte 			 ),
              .app_amm_bcnt          	 (ddr_dbg_bcnt 			 )
              );    
 
always @(*)
begin
    if(test_enb)
        begin
            app_amm_read 	<= ddr_tg_read;
            app_amm_write 	<= ddr_tg_write;
            app_amm_addr 	<= ddr_tg_addr[26:0];
            app_amm_wdat 	<= ddr_tg_wdat;
            app_amm_byte 	<= ddr_tg_byte;
            app_amm_bcnt 	<= ddr_tg_bcnt;
        end
    else 
        begin
            app_amm_read 	<= ddr_dbg_read;
            app_amm_write 	<= ddr_dbg_write;
            app_amm_addr 	<= ddr_dbg_addr[26:0];
            app_amm_wdat 	<= ddr_dbg_wdat;
            app_amm_byte 	<= ddr_dbg_byte;
            app_amm_bcnt 	<= ddr_dbg_bcnt;
        end

    ddr_tg_ready	<= app_amm_ready;
    ddr_tg_rvld		<= app_amm_rvld;
    ddr_tg_rdat		<= app_amm_rdat;

    ddr_dbg_ready	<= app_amm_ready;
    ddr_dbg_rvld	<= app_amm_rvld;
    ddr_dbg_rdat	<= app_amm_rdat;
end			   */
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

   wire [47:0]              rx_mac_status;
   
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
              .tx_pfc                     (mac_tx_pfc              ),
              .rx_pfc                     (rx_pfc                  ),
             
              .i_tx_mac_data              (gap_to_mac_tdata        ),  
              .i_tx_mac_valid             (gap_to_mac_tvalid       ),
              .i_tx_mac_inframe           (gap_to_mac_frame        ),
              .i_tx_mac_eop_empty         (gap_to_mac_emty         ),
              .o_tx_mac_ready             (gap_to_mac_tready       ),
              .i_tx_mac_error             ({MAC_FRAME_W*2{1'b0}}   ),
              .i_tx_mac_skip_crc          ({MAC_FRAME_W{1'b0}}     ),

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

    /* FPGA 结温：见 system_config_register 例化处注释（TEMP_LOC0_0 = temp_loc 1 的 temp0） */
    assign fpga_temp_raw_w = TEMP_LOC0_0;
    assign fpga_temp_w     = fpga_temp_raw_w[9:0];

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
wire beat_1us;
wire beat_100us;


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

/*****************************************************************************\
*                                                                             *
*                  GPIO test                                                  *
*                                                                             *
\*****************************************************************************/

   reg [15:0] 				 tst_cnt = 16'h55aa;
   
   reg                       i2c_opt_scl0_t    ;
   reg                       i2c_opt_sda0_t    ;  
   reg                       i2c_opt_scl1_t    ;
   reg                       i2c_opt_sda1_t    ;  
   reg   						  opt_mod_lpm_t     ;
   reg   						  opt_mod_rst_t     ;
   reg                       i2c_m_cpld_scl_t  ;
   reg                       i2c_m_cpld_sda_t  ;
   reg   [2:0]               fpga_cpld_gpio_t  ;
   reg                       i2c_s_fpga_sda_t  ;
   reg                       i2c_s_fpga_scl_t  ;
   
   always @ ( posedge clk100m ) begin

      tst_cnt <= {tst_cnt[14:0],tst_cnt[15]} ^ 16'h1235;
      
      i2c_opt_scl0_t    <= tst_cnt[0] ^ tst_cnt[8];
      i2c_opt_sda0_t    <= tst_cnt[1] ^ tst_cnt[9];
                        
      i2c_opt_scl1_t    <= tst_cnt[2] ^ tst_cnt[14];
      i2c_opt_sda1_t    <= tst_cnt[3] ^ tst_cnt[13];
      
      opt_mod_lpm_t    <= opt_mod_los;
      opt_mod_rst_t    <= opt_mod_pst;

      i2c_m_cpld_scl_t <= tst_cnt[4] ^ tst_cnt[0];
      i2c_m_cpld_sda_t <= tst_cnt[5] ^ tst_cnt[7];

      fpga_cpld_gpio_t <= tst_cnt[8:6];

      i2c_s_fpga_sda_t <= tst_cnt[6] ^ tst_cnt[7] ^ i2c_m_fpga_scl;
      i2c_s_fpga_scl_t <= tst_cnt[7] ^ tst_cnt[8];
   end
   
   assign i2c_opt_scl0    = i2c_opt_scl0_t;  
   assign i2c_opt_sda0    = i2c_opt_sda0_t;                    
   assign i2c_opt_scl1    = i2c_opt_scl1_t;  
   assign i2c_opt_sda1    = i2c_opt_sda1_t;  
   //assign opt_mod_lpm     = 1'b1;   
   //assign opt_mod_rst     = 1'b1;   
   always @(posedge eth_mac_clk)  
   begin
        fpga_cpld_gpio[0] <= (eth_system_stat == 32'h63f);
        fpga_cpld_gpio[1] <= (rx_mac_inframe != 'b0) | (gap_to_mac_frame != 'b0);
        fpga_cpld_gpio[7:2] <= 'b0;
   end 
  // assign i2c_m_fpga_sda  = i2c_s_fpga_sda_t;
  // assign i2c_m_fpga_scl  = i2c_s_fpga_scl_t;
`endif             
endmodule // YuanRDMA
