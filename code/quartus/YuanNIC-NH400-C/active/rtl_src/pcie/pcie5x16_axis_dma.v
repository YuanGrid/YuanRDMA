`include "../roce/roce_bas_if.vh"

module pcie5x16_axis_dma (
                          input  wire [`BAS_M2S_W-1:0] pcie5_bas_m2s,
                          output wire [`BAS_S2M_W-1:0] pcie5_bas_s2m,
						  input  wire [15:0] 		 PCIE0_GT_0_grx_n         ,
						  input  wire [15:0] 		 PCIE0_GT_0_grx_p         ,
						  output wire [15:0] 		 PCIE0_GT_0_gtx_n         ,
						  output wire [15:0] 		 PCIE0_GT_0_gtx_p         ,
                                                                              
						  input  wire 				 PCIE0_GT_0_clk_p         ,
						  input  wire 				 PCIE0_GT_1_clk_p         ,
                                                                              
						  input 					 pcie_reset_n             ,

						  input                      clk250m                  ,
						  input                      sys_rst                  ,
                          
                          output wire                axi_st_app_clk           ,
                          output wire                pcie_app_rst             ,
                                                                              
                          output wire                h2d_axi_st_tvalid        ,            
                          input  wire                h2d_axi_st_tready        ,            
                          output wire [1023:0]       h2d_axi_st_tdata         ,          
                          output wire [127:0]        h2d_axi_st_tkeep         ,            
                          output wire                h2d_axi_st_tlast         ,              
                          output wire [63:0]         h2d_axi_st_tuser_metadata,     
                          output wire [11:0]         h2d_axi_st_tid           ,                
                          output wire                h2d_axi_st_tuser_error   ,       
                          
                          input  wire                d2h_axi_st_tvalid        ,             
                          output wire                d2h_axi_st_tready        ,            
                          input  wire [1023:0]       d2h_axi_st_tdata         ,              
                          input  wire [127:0]        d2h_axi_st_tkeep         ,             
                          input  wire                d2h_axi_st_tlast         ,             
                          input  wire [63:0]         d2h_axi_st_tuser_metadata,     
                          input  wire [11:0]         d2h_axi_st_tid           ,               
                          input  wire                d2h_axi_st_tuser_error   ,
                          // BAM AXI-MM master（原 BAR2 PIO；BAS 模式下寄存器访问改走这里）
                          output wire                pcie5_bam_axi_mm_awvalid,
                          input  wire                pcie5_bam_axi_mm_awready,
                          output wire [3:0]          pcie5_bam_axi_mm_awid   ,
                          output wire [33:0]         pcie5_bam_axi_mm_awaddr ,
                          output wire [7:0]          pcie5_bam_axi_mm_awlen  ,
                          output wire [2:0]          pcie5_bam_axi_mm_awsize ,
                          output wire [1:0]          pcie5_bam_axi_mm_awburst,
                          output wire [2:0]          pcie5_bam_axi_mm_awprot ,
                          output wire                pcie5_bam_axi_mm_awlock ,
                          output wire [19:0]         pcie5_bam_axi_mm_awuser ,
                          output wire                pcie5_bam_axi_mm_wvalid ,
                          input  wire                pcie5_bam_axi_mm_wready ,
                          output wire                pcie5_bam_axi_mm_wlast  ,
                          output wire [1023:0]       pcie5_bam_axi_mm_wdata  ,
                          output wire [127:0]        pcie5_bam_axi_mm_wstrb  ,
                          input  wire                pcie5_bam_axi_mm_bvalid ,
                          output wire                pcie5_bam_axi_mm_bready ,
                          input  wire [3:0]          pcie5_bam_axi_mm_bid    ,
                          input  wire [1:0]          pcie5_bam_axi_mm_bresp  ,
                          output wire                pcie5_bam_axi_mm_arvalid,
                          input  wire                pcie5_bam_axi_mm_arready,
                          output wire [3:0]          pcie5_bam_axi_mm_arid   ,
                          output wire [33:0]         pcie5_bam_axi_mm_araddr ,
                          output wire [7:0]          pcie5_bam_axi_mm_arlen  ,
                          output wire [2:0]          pcie5_bam_axi_mm_arsize ,
                          output wire [1:0]          pcie5_bam_axi_mm_arburst,
                          output wire [2:0]          pcie5_bam_axi_mm_arprot ,
                          output wire                pcie5_bam_axi_mm_arlock ,
                          output wire [19:0]         pcie5_bam_axi_mm_aruser ,
                          input  wire                pcie5_bam_axi_mm_rvalid ,
                          output wire                pcie5_bam_axi_mm_rready ,
                          input  wire                pcie5_bam_axi_mm_rlast  ,
                          input  wire [3:0]          pcie5_bam_axi_mm_rid    ,
                          input  wire [1023:0]       pcie5_bam_axi_mm_rdata  ,
                          input  wire [1:0]          pcie5_bam_axi_mm_rresp  ,


						  output wire                pcie_linkup              ,
						  output wire                pcie_data_linkup 
						  ) ;

/********************************************************************\
*                                                                    *
*               configuration init_done                              *
*                                                                    *
\********************************************************************/
   wire 											 ninit_done;
   pcie_ed_resetIP 
	 resetip (
			  .ninit_done (ninit_done)  //  output,  width = 1, ninit_done.reset
			  );

/********************************************************************\
*                                                                    *
*               PCIE_GEN5x16                                         *
* bar0: 2M 64bits for DMA stream                                     *                      
* bar1: 64M 64bts for DMA PIO                                        *
*                                                                    *
\********************************************************************/   

   wire 											 pcie_phy_out_rst_n;
   
   assign pcie_app_rst = !pcie_phy_out_rst_n;
   
   wire                                              p0_app_st_rx_tvalid;                
   wire [1023:0]                                     p0_app_st_rx_tdata;                 
   wire [127:0] 									 p0_app_st_rx_tkeep;
   wire 											 p0_app_st_rx_tlast;
   wire [3:0] 										 p0_app_st_rx_tuser_vendor;
   wire [3:0] 										 p0_app_st_rx_tuser_last_segment;
   wire [3:0] 										 p0_app_st_rx_tuser_hvalid;
   wire [1023:0] 									 p0_app_st_rx_tuser_hdr;
                                      
   wire 											 p0_app_ss_st_tx_tvalid;
   wire 											 p0_ss_app_st_tx_tready;
   wire [1023:0] 									 p0_app_ss_st_tx_tdata;
   wire [127:0] 									 p0_app_ss_st_tx_tkeep;
   wire 											 p0_app_ss_st_tx_tlast;
   wire [3:0] 										 p0_app_ss_st_tx_tuser_last_segment;
   wire [3:0] 										 p0_app_ss_st_tx_tuser_hvalid;
   wire [1023:0] 									 p0_app_ss_st_tx_tuser_hdr;
   
   wire 											 p0_ss_app_st_flrrcvd_tvalid;
   wire [19:0] 										 p0_ss_app_st_flrrcvd_tdata;
   wire 											 p0_app_ss_st_flrcmpl_tvalid;
   wire [19:0] 										 p0_app_ss_st_flrcmpl_tdata;
   wire 											 p0_ss_app_st_flrcmpl_tready;
   wire 											 p0_ss_app_st_txcrdt_tvalid;
   wire [18:0] 										 p0_ss_app_st_txcrdt_tdata;
   wire 											 p0_ss_app_st_rxcrdt_tvalid;
   wire [18:0] 										 p0_ss_app_st_rxcrdt_tdata;
   
   wire           									 pcie_ss_dut_p0_st_ciireq_tvalid;                                                   // pcie_ss_DUT:p0_ss_app_st_ciireq_tvalid -> DUT:ss_app_st_ciireq_tvalid
   wire           									 pcie_ss_dut_p0_st_ciireq_tready;                                                   // DUT:app_ss_st_ciireq_tready -> pcie_ss_DUT:p0_app_ss_st_ciireq_tready
   wire [71:0] 										 pcie_ss_dut_p0_st_ciireq_tdata;                                                    // pcie_ss_DUT:p0_ss_app_st_ciireq_tdata -> DUT:ss_app_st_ciireq_tdata
   wire           									 dut_ss_cii_resp_tvalid;                                                            // DUT:app_ss_st_ciiresp_tvalid -> pcie_ss_DUT:p0_app_ss_st_ciiresp_tvalid
   wire [32:0] 										 dut_ss_cii_resp_tdata;                                                             // DUT:app_ss_st_ciiresp_tdata -> pcie_ss_DUT:p0_app_ss_st_ciiresp_tdata
	
   wire        										 pcie_ss_dut_p0_st_cplto_tvalid;                                                    // pcie_ss_DUT:p0_ss_app_st_cplto_tvalid -> DUT:ss_app_st_cplto_tvalid
   wire [29:0] 										 pcie_ss_dut_p0_st_cplto_tdata;                                                     // pcie_ss_DUT:p0_ss_app_st_cplto_tdata -> DUT:ss_app_st_cplto_tdata
   wire        										 pcie_ss_dut_p0_st_ctrlshadow_tvalid;                                               // pcie_ss_DUT:p0_ss_app_st_ctrlshadow_tvalid -> DUT:ss_app_st_ctrlshadow_tvalid
   wire [39:0] 										 pcie_ss_dut_p0_st_ctrlshadow_tdata;                                                // pcie_ss_DUT:p0_ss_app_st_ctrlshadow_tdata -> DUT:ss_app_st_ctrlshadow_tdata
	
   wire           									 dut_ss_app_err_tvalid;                                                             // DUT:app_ss_st_err_tvalid -> pcie_ss_DUT:p0_app_ss_st_err_tvalid
   wire           									 dut_ss_app_err_tready;                                                             // pcie_ss_DUT:p0_ss_app_st_err_tready -> DUT:ss_app_st_err_tready
   wire [31:0] 										 dut_ss_app_err_tdata;                                                              // DUT:app_ss_st_err_tdata -> pcie_ss_DUT:p0_app_ss_st_err_tdata
   wire           									 dut_ss_app_err_tlast;                                                              // DUT:app_ss_st_err_tlast -> pcie_ss_DUT:p0_app_ss_st_err_tlast
   wire [13:0] 										 dut_app_ss_st_err_tuser_error_type_app_ss_st_err_tuser_error_type;                 // DUT:app_ss_st_err_tuser_error_type -> pcie_ss_DUT:p0_app_ss_st_err_tuser_error_type
	
   wire [19:0] 										 dut_ss_csr_lite_awaddr;                                                            // DUT:app_ss_lite_csr_awaddr -> pcie_ss_DUT:p0_app_ss_lite_csr_awaddr
   wire [1:0] 										 dut_ss_csr_lite_bresp;                                                             // pcie_ss_DUT:p0_ss_app_lite_csr_bresp -> DUT:ss_app_lite_csr_bresp
   wire           									 dut_ss_csr_lite_arready;                                                           // pcie_ss_DUT:p0_ss_app_lite_csr_arready -> DUT:ss_app_lite_csr_arready
   wire [31:0] 										 dut_ss_csr_lite_rdata;                                                             // pcie_ss_DUT:p0_ss_app_lite_csr_rdata -> DUT:ss_app_lite_csr_rdata
   wire           									 dut_ss_csr_lite_wready;                                                            // pcie_ss_DUT:p0_ss_app_lite_csr_wready -> DUT:ss_app_lite_csr_wready
   wire [3:0] 										 dut_ss_csr_lite_wstrb;                                                             // DUT:app_ss_lite_csr_wstrb -> pcie_ss_DUT:p0_app_ss_lite_csr_wstrb
   wire          									 dut_ss_csr_lite_awready;                                                           // pcie_ss_DUT:p0_ss_app_lite_csr_awready -> DUT:ss_app_lite_csr_awready
   wire           									 dut_ss_csr_lite_rready;                                                            // DUT:app_ss_lite_csr_rready -> pcie_ss_DUT:p0_app_ss_lite_csr_rready
   wire           									 dut_ss_csr_lite_bready;                                                            // DUT:app_ss_lite_csr_bready -> pcie_ss_DUT:p0_app_ss_lite_csr_bready
   wire           									 dut_ss_csr_lite_wvalid;                                                            // DUT:app_ss_lite_csr_wvalid -> pcie_ss_DUT:p0_app_ss_lite_csr_wvalid
   wire [19:0] 										 dut_ss_csr_lite_araddr;                                                            // DUT:app_ss_lite_csr_araddr -> pcie_ss_DUT:p0_app_ss_lite_csr_araddr
   wire [1:0] 										 dut_ss_csr_lite_rresp;                                                             // pcie_ss_DUT:p0_ss_app_lite_csr_rresp -> DUT:ss_app_lite_csr_rresp
   wire [2:0] 										 dut_ss_csr_lite_arprot;                                                            // DUT:ss_app_lite_csr_arprot -> pcie_ss_DUT:p0_app_ss_lite_csr_arprot
   wire [31:0] 										 dut_ss_csr_lite_wdata;                                                             // DUT:app_ss_lite_csr_wdata -> pcie_ss_DUT:p0_app_ss_lite_csr_wdata
   wire           									 dut_ss_csr_lite_arvalid;                                                           // DUT:app_ss_lite_csr_arvalid -> pcie_ss_DUT:p0_app_ss_lite_csr_arvalid
   wire [2:0] 										 dut_ss_csr_lite_awprot;                                                            // DUT:ss_app_lite_csr_awprot -> pcie_ss_DUT:p0_app_ss_lite_csr_awprot
   wire           									 dut_ss_csr_lite_bvalid;                                                            // pcie_ss_DUT:p0_ss_app_lite_csr_bvalid -> DUT:ss_app_lite_csr_bvalid
   wire           									 dut_ss_csr_lite_awvalid;                                                           // DUT:app_ss_lite_csr_awvalid -> pcie_ss_DUT:p0_app_ss_lite_csr_awvalid
   wire           									 dut_ss_csr_lite_rvalid;      
   
   wire												 pcie_cold_rst_ack_n;
   wire												 pcie_warm_rst_ack_n;
   
   wire												 p0_initiate_warmrst_req;
   wire												 p0_initiate_rst_req_rdy;
   
   assign p0_initiate_rst_req_rdy = p0_initiate_warmrst_req;
   
   pcie5x16_phy 
	 U_pcie5x16(
				//外部复位PIN
				.pin_perst_n                        (pcie_reset_n                          ),                        //   input,     width = 1,                        pin_perst_n.reset_n
                //PHY输出给stream 接口的业务时钟 500M                                              
				.coreclkout_hip_toapp               (axi_st_app_clk                        ),               //  output,     width = 1,               coreclkout_hip_toapp.clk
                                                                                           
				.p0_pin_perst_n                     (                                      ),                     //  output,     width = 1,                     p0_pin_perst_n.reset_n
                                                                                           
				//输入FPGA加载完成信号,用于内部复位                                                
				.ninit_done                         (ninit_done                            ),                         //   input,     width = 1,                         ninit_done.reset
                                                                                           
				//PCIE IP输出复位                                                                  
				.p0_reset_status_n                  (pcie_phy_out_rst_n                    ),                  //  output,     width = 1,                  p0_reset_status_n.reset_n
				.dummy_user_avmm_rst                (~pcie_phy_out_rst_n                   ),                //   input,     width = 1,                dummy_user_avmm_rst.reset
                                                                                           
				//AXIS业务接口输入时钟                                                             
				.p0_axi_st_clk                      (axi_st_app_clk                        ),                      //   input,     width = 1,                      p0_axi_st_clk.clk
				//AXIS业务复位输入                                                                 
				.p0_axi_st_areset_n                 (pcie_phy_out_rst_n                    ),                 //   input,     width = 1,                 p0_axi_st_areset_n.reset_n
                                                                                           
				.p0_axi_lite_clk                    (clk250m                               ),                    //   input,     width = 1,                    p0_axi_lite_clk.clk
				.p0_axi_lite_areset_n               (!sys_rst                              ),               //   input,     width = 1,               p0_axi_lite_areset_n.reset_n
                                                                                           
				.p0_subsystem_cold_rst_n            (pcie_phy_out_rst_n                    ),            //   input,     width = 1,            p0_subsystem_cold_rst_n.reset_n
				.p0_subsystem_warm_rst_n            (pcie_phy_out_rst_n                    ),            //   input,     width = 1,            p0_subsystem_warm_rst_n.reset_n
				.p0_subsystem_cold_rst_ack_n        (pcie_cold_rst_ack_n                   ),        //  output,     width = 1,        p0_subsystem_cold_rst_ack_n.subsystem_cold_rst_ack_n
				.p0_subsystem_warm_rst_ack_n        (pcie_warm_rst_ack_n                   ),        //  output,     width = 1,        p0_subsystem_warm_rst_ack_n.subsystem_warm_rst_ack_n
                                                                                           
				.p0_subsystem_rst_req               (                                      ),               //   input,     width = 1,               p0_subsystem_rst_req.subsystem_rst_req
				.p0_subsystem_rst_rdy               (                                      ),               //  output,     width = 1,               p0_subsystem_rst_rdy.subsystem_rst_rdy
		
				.p0_initiate_warmrst_req            (p0_initiate_warmrst_req			   ),            //  output,     width = 1,            p0_initiate_warmrst_req.initiate_warmrst_req
				.p0_initiate_rst_req_rdy            (p0_initiate_rst_req_rdy			   ),            //   input,     width = 1,            p0_initiate_rst_req_rdy.initiate_rst_req_rdy
		
				.p0_ss_app_st_rx_tvalid             (p0_app_st_rx_tvalid                   ),             //  output,     width = 1,                           p0_st_rx.tvalid
				.p0_ss_app_st_rx_tdata              (p0_app_st_rx_tdata                    ),              //  output,  width = 1024,                                   .tdata
				.p0_ss_app_st_rx_tkeep              (p0_app_st_rx_tkeep                    ),              //  output,   width = 128,                                   .tkeep
				.p0_ss_app_st_rx_tlast              (p0_app_st_rx_tlast                    ),              //  output,     width = 1,                                   .tlast
				.p0_ss_app_st_rx_tuser_vendor       (p0_app_st_rx_tuser_vendor             ),       //  output,     width = 4,       p0_ss_app_st_rx_tuser_vendor.p0_ss_app_st_rx_tuser_vendor
				.p0_ss_app_st_rx_tuser_last_segment (p0_app_st_rx_tuser_last_segment       ), //  output,     width = 4, p0_ss_app_st_rx_tuser_last_segment.p0_ss_app_st_rx_tuser_last_segment
				.p0_ss_app_st_rx_tuser_hvalid       (p0_app_st_rx_tuser_hvalid             ),       //  output,     width = 4,       p0_ss_app_st_rx_tuser_hvalid.p0_ss_app_st_rx_tuser_hvalid
				.p0_ss_app_st_rx_tuser_hdr          (p0_app_st_rx_tuser_hdr                ),          //  output,  width = 1024,          p0_ss_app_st_rx_tuser_hdr.p0_ss_app_st_rx_tuser_hdr
                                                                                           
                .p0_app_ss_st_tx_tvalid             (p0_app_ss_st_tx_tvalid                ),             //   input,     width = 1,                           p0_st_tx.tvalid
				.p0_ss_app_st_tx_tready             (p0_ss_app_st_tx_tready                ),             //  output,     width = 1,                                   .tready
				.p0_app_ss_st_tx_tdata              (p0_app_ss_st_tx_tdata                 ),              //   input,  width = 1024,                                   .tdata
				.p0_app_ss_st_tx_tkeep              (p0_app_ss_st_tx_tkeep                 ),              //   input,   width = 128,                                   .tkeep
				.p0_app_ss_st_tx_tlast              (p0_app_ss_st_tx_tlast                 ),              //   input,     width = 1,                                   .tlast
				.p0_app_ss_st_tx_tuser_last_segment (p0_app_ss_st_tx_tuser_last_segment    ), //   input,     width = 4, p0_app_ss_st_tx_tuser_last_segment.p0_app_ss_st_tx_tuser_last_segment
				.p0_app_ss_st_tx_tuser_hvalid       (p0_app_ss_st_tx_tuser_hvalid          ),       //   input,     width = 4,       p0_app_ss_st_tx_tuser_hvalid.p0_app_ss_st_tx_tuser_hvalid
				.p0_app_ss_st_tx_tuser_hdr          (p0_app_ss_st_tx_tuser_hdr             ),          //   input,  width = 1024,          p0_app_ss_st_tx_tuser_hdr.p0_app_ss_st_tx_tuser_hdr
				
                .p0_ss_app_st_flrrcvd_tvalid        (p0_ss_app_st_flrrcvd_tvalid           ),        //  output,     width = 1,                      p0_st_flrrcvd.tvalid
				.p0_ss_app_st_flrrcvd_tdata         (p0_ss_app_st_flrrcvd_tdata            ),         //  output,    width = 20,                                   .tdata
				.p0_app_ss_st_flrcmpl_tvalid        (p0_app_ss_st_flrcmpl_tvalid           ),        //   input,     width = 1,                      p0_st_flrcmpl.tvalid
				.p0_app_ss_st_flrcmpl_tdata         (p0_app_ss_st_flrcmpl_tdata            ),         //   input,    width = 20,                                   .tdata
				.p0_ss_app_st_flrcmpl_tready        (p0_ss_app_st_flrcmpl_tready           ),        //  output,     width = 1,                                   .tready
				.p0_ss_app_st_txcrdt_tvalid         (p0_ss_app_st_txcrdt_tvalid            ),         //  output,     width = 1,                       p0_st_txcrdt.tvalid
				.p0_ss_app_st_txcrdt_tdata          (p0_ss_app_st_txcrdt_tdata             ),          //  output,    width = 19,                                   .tdata
				.p0_ss_app_st_rxcrdt_tvalid         (p0_ss_app_st_rxcrdt_tvalid            ),         //   input,     width = 1,                       p0_st_rxcrdt.tvalid
				.p0_ss_app_st_rxcrdt_tdata          (p0_ss_app_st_rxcrdt_tdata             ),          //   input,    width = 19,                                   .tdata
				
				.p0_ss_app_st_ciireq_tvalid         (pcie_ss_dut_p0_st_ciireq_tvalid),                                                   //  output,     width = 1,                       p0_st_ciireq.tvalid
				.p0_app_ss_st_ciireq_tready         (pcie_ss_dut_p0_st_ciireq_tready),                                                   //   input,     width = 1,                                   .tready
				.p0_ss_app_st_ciireq_tdata          (pcie_ss_dut_p0_st_ciireq_tdata),                                                    //  output,    width = 72,                                   .tdata
				.p0_app_ss_st_ciiresp_tvalid        (dut_ss_cii_resp_tvalid),                                                            //   input,     width = 1,                      p0_st_ciiresp.tvalid
				.p0_app_ss_st_ciiresp_tdata         (dut_ss_cii_resp_tdata),                                                             //   input,    width = 33,                                   .tdata
		
				.p0_ss_app_st_ctrlshadow_tvalid     (pcie_ss_dut_p0_st_ctrlshadow_tvalid),                                               //  output,     width = 1,                   p0_st_ctrlshadow.tvalid
				.p0_ss_app_st_ctrlshadow_tdata      (pcie_ss_dut_p0_st_ctrlshadow_tdata),                                                //  output,    width = 40,                                   .tdata
				.p0_ss_app_st_cplto_tvalid          (pcie_ss_dut_p0_st_cplto_tvalid),                                                    //  output,     width = 1,                        p0_st_cplto.tvalid
				.p0_ss_app_st_cplto_tdata           (pcie_ss_dut_p0_st_cplto_tdata),                                                     //  output,    width = 30,                                   .tdata
		
				.p0_app_ss_lite_csr_awvalid         (dut_ss_csr_lite_awvalid				),       //   input,     width = 1,                        p0_lite_csr.awvalid
				.p0_ss_app_lite_csr_awready         (dut_ss_csr_lite_awready				),       //  output,     width = 1,                                   .awready
				.p0_app_ss_lite_csr_awaddr          (dut_ss_csr_lite_awaddr					),         //   input,    width = 20,                                   .awaddr
				.p0_app_ss_lite_csr_awprot          (dut_ss_csr_lite_awprot					),         //   input,     width = 3,                                   .awprot
				.p0_app_ss_lite_csr_wvalid          (dut_ss_csr_lite_wvalid					),         //   input,     width = 1,                                   .wvalid
				.p0_ss_app_lite_csr_wready          (dut_ss_csr_lite_wready					),         //  output,     width = 1,                                   .wready
				.p0_app_ss_lite_csr_wdata           (dut_ss_csr_lite_wdata					),           //   input,    width = 32,                                   .wdata
				.p0_app_ss_lite_csr_wstrb           (dut_ss_csr_lite_wstrb					),           //   input,     width = 4,                                   .wstrb
				.p0_ss_app_lite_csr_bvalid          (dut_ss_csr_lite_bvalid					),         //  output,     width = 1,                                   .bvalid
				.p0_app_ss_lite_csr_bready          (dut_ss_csr_lite_bready					),         //   input,     width = 1,                                   .bready
				.p0_ss_app_lite_csr_bresp           (dut_ss_csr_lite_bresp					),           //  output,     width = 2,                                   .bresp
				.p0_app_ss_lite_csr_arvalid         (dut_ss_csr_lite_arvalid				),       //   input,     width = 1,                                   .arvalid
				.p0_ss_app_lite_csr_arready         (dut_ss_csr_lite_arready				),       //  output,     width = 1,                                   .arready
				.p0_app_ss_lite_csr_araddr          (dut_ss_csr_lite_araddr					),         //   input,    width = 20,                                   .araddr
				.p0_app_ss_lite_csr_arprot          (dut_ss_csr_lite_arprot					),         //   input,     width = 3,                                   .arprot
				.p0_ss_app_lite_csr_rvalid          (dut_ss_csr_lite_rvalid					),         //  output,     width = 1,                                   .rvalid
				.p0_app_ss_lite_csr_rready          (dut_ss_csr_lite_rready					),         //   input,     width = 1,                                   .rready
				.p0_ss_app_lite_csr_rdata           (dut_ss_csr_lite_rdata					),           //  output,    width = 32,                                   .rdata
				.p0_ss_app_lite_csr_rresp           (dut_ss_csr_lite_rresp					),           //  output,     width = 2,                                   .rresp
		
				.p0_app_ss_st_err_tvalid            (dut_ss_app_err_tvalid),                                                             //   input,     width = 1,                          p0_st_err.tvalid
				.p0_app_ss_st_err_tdata             (dut_ss_app_err_tdata),                                                              //   input,    width = 32,                                   .tdata
				.p0_app_ss_st_err_tlast             (dut_ss_app_err_tlast),                                                              //   input,     width = 1,                                   .tlast
				.p0_ss_app_st_err_tready            (dut_ss_app_err_tready),                                                             //  output,     width = 1,                                   .tready
				.p0_app_ss_st_err_tuser_error_type  (dut_app_ss_st_err_tuser_error_type_app_ss_st_err_tuser_error_type),                 //   input,    width = 14,  p0_app_ss_st_err_tuser_error_type.app_ss_st_err_tuser_error_type
		
				.p0_ss_app_serr                     (                                      ),                     //  output,     width = 1,                     p0_ss_app_serr.ss_app_serr
				//.p0_ss_app_linkup                   (pcie_linkup                           ),                   //  output,     width = 1,                   p0_ss_app_linkup.ss_app_linkup
				.p0_ss_app_dlup                     (pcie_data_linkup                      ),                     //  output,     width = 1,                     p0_ss_app_dlup.ss_app_dlup
				.p0_ss_app_surprise_down_err        (                                      ),        //  output,     width = 1,        p0_ss_app_surprise_down_err.ss_app_surprise_down_err
				//.p0_ss_app_ltssmstate               (                                      ),               //  output,     width = 6,               p0_ss_app_ltssmstate.ss_app_ltssmstate
				.p0_ss_app_rx_par_err               (                                      ),               //  output,     width = 1,               p0_ss_app_rx_par_err.ss_app_rx_par_err
				.p0_ss_app_tx_par_err               (                                      ),               //  output,     width = 1,               p0_ss_app_tx_par_err.ss_app_tx_par_err
	
				.tx_n_out0                          (PCIE0_GT_0_gtx_n[0 ]                  ),                          //  output,     width = 1,                         hip_serial.tx_n_out0
				.tx_n_out1                          (PCIE0_GT_0_gtx_n[1 ]                  ),                          //  output,     width = 1,                                   .tx_n_out1
				.tx_n_out2                          (PCIE0_GT_0_gtx_n[2 ]                  ),                          //  output,     width = 1,                                   .tx_n_out2
				.tx_n_out3                          (PCIE0_GT_0_gtx_n[3 ]                  ),                          //  output,     width = 1,                                   .tx_n_out3
				.tx_n_out4                          (PCIE0_GT_0_gtx_n[4 ]                  ),                          //  output,     width = 1,                                   .tx_n_out4
				.tx_n_out5                          (PCIE0_GT_0_gtx_n[5 ]                  ),                          //  output,     width = 1,                                   .tx_n_out5
				.tx_n_out6                          (PCIE0_GT_0_gtx_n[6 ]                  ),                          //  output,     width = 1,                                   .tx_n_out6
				.tx_n_out7                          (PCIE0_GT_0_gtx_n[7 ]                  ),                          //  output,     width = 1,                                   .tx_n_out7
				.tx_n_out8                          (PCIE0_GT_0_gtx_n[8 ]                  ),                          //  output,     width = 1,                                   .tx_n_out8
				.tx_n_out9                          (PCIE0_GT_0_gtx_n[9 ]                  ),                          //  output,     width = 1,                                   .tx_n_out9
				.tx_n_out10                         (PCIE0_GT_0_gtx_n[10]                  ),                         //  output,     width = 1,                                   .tx_n_out10
				.tx_n_out11                         (PCIE0_GT_0_gtx_n[11]                  ),                         //  output,     width = 1,                                   .tx_n_out11
				.tx_n_out12                         (PCIE0_GT_0_gtx_n[12]                  ),                         //  output,     width = 1,                                   .tx_n_out12
				.tx_n_out13                         (PCIE0_GT_0_gtx_n[13]                  ),                         //  output,     width = 1,                                   .tx_n_out13
				.tx_n_out14                         (PCIE0_GT_0_gtx_n[14]                  ),                         //  output,     width = 1,                                   .tx_n_out14
				.tx_n_out15                         (PCIE0_GT_0_gtx_n[15]                  ),                         //  output,     width = 1,                                   .tx_n_out15
                                                                                           
				.tx_p_out0                          (PCIE0_GT_0_gtx_p[0 ]                  ),                          //  output,     width = 1,                                   .tx_p_out0
				.tx_p_out1                          (PCIE0_GT_0_gtx_p[1 ]                  ),                          //  output,     width = 1,                                   .tx_p_out1
				.tx_p_out2                          (PCIE0_GT_0_gtx_p[2 ]                  ),                          //  output,     width = 1,                                   .tx_p_out2
				.tx_p_out3                          (PCIE0_GT_0_gtx_p[3 ]                  ),                          //  output,     width = 1,                                   .tx_p_out3
				.tx_p_out4                          (PCIE0_GT_0_gtx_p[4 ]                  ),                          //  output,     width = 1,                                   .tx_p_out4
				.tx_p_out5                          (PCIE0_GT_0_gtx_p[5 ]                  ),                          //  output,     width = 1,                                   .tx_p_out5
				.tx_p_out6                          (PCIE0_GT_0_gtx_p[6 ]                  ),                          //  output,     width = 1,                                   .tx_p_out6
				.tx_p_out7                          (PCIE0_GT_0_gtx_p[7 ]                  ),                          //  output,     width = 1,                                   .tx_p_out7
				.tx_p_out8                          (PCIE0_GT_0_gtx_p[8 ]                  ),                          //  output,     width = 1,                                   .tx_p_out8
				.tx_p_out9                          (PCIE0_GT_0_gtx_p[9 ]                  ),                          //  output,     width = 1,                                   .tx_p_out9
				.tx_p_out10                         (PCIE0_GT_0_gtx_p[10]                  ),                         //  output,     width = 1,                                   .tx_p_out10
				.tx_p_out11                         (PCIE0_GT_0_gtx_p[11]                  ),                         //  output,     width = 1,                                   .tx_p_out11
				.tx_p_out12                         (PCIE0_GT_0_gtx_p[12]                  ),                         //  output,     width = 1,                                   .tx_p_out12
				.tx_p_out13                         (PCIE0_GT_0_gtx_p[13]                  ),                         //  output,     width = 1,                                   .tx_p_out13
				.tx_p_out14                         (PCIE0_GT_0_gtx_p[14]                  ),                         //  output,     width = 1,                                   .tx_p_out14
				.tx_p_out15                         (PCIE0_GT_0_gtx_p[15]                  ),                         //  output,     width = 1,                                   .tx_p_out15
                                                                                           
				.rx_n_in0                           (PCIE0_GT_0_grx_n[0 ]                  ),                           //   input,     width = 1,                                   .rx_n_in0
				.rx_n_in1                           (PCIE0_GT_0_grx_n[1 ]                  ),                           //   input,     width = 1,                                   .rx_n_in1
				.rx_n_in2                           (PCIE0_GT_0_grx_n[2 ]                  ),                           //   input,     width = 1,                                   .rx_n_in2
				.rx_n_in3                           (PCIE0_GT_0_grx_n[3 ]                  ),                           //   input,     width = 1,                                   .rx_n_in3
				.rx_n_in4                           (PCIE0_GT_0_grx_n[4 ]                  ),                           //   input,     width = 1,                                   .rx_n_in4
				.rx_n_in5                           (PCIE0_GT_0_grx_n[5 ]                  ),                           //   input,     width = 1,                                   .rx_n_in5
				.rx_n_in6                           (PCIE0_GT_0_grx_n[6 ]                  ),                           //   input,     width = 1,                                   .rx_n_in6
				.rx_n_in7                           (PCIE0_GT_0_grx_n[7 ]                  ),                           //   input,     width = 1,                                   .rx_n_in7
				.rx_n_in8                           (PCIE0_GT_0_grx_n[8 ]                  ),                           //   input,     width = 1,                                   .rx_n_in8
				.rx_n_in9                           (PCIE0_GT_0_grx_n[9 ]                  ),                           //   input,     width = 1,                                   .rx_n_in9
				.rx_n_in10                          (PCIE0_GT_0_grx_n[10]                  ),                          //   input,     width = 1,                                   .rx_n_in10
				.rx_n_in11                          (PCIE0_GT_0_grx_n[11]                  ),                          //   input,     width = 1,                                   .rx_n_in11
				.rx_n_in12                          (PCIE0_GT_0_grx_n[12]                  ),                          //   input,     width = 1,                                   .rx_n_in12
				.rx_n_in13                          (PCIE0_GT_0_grx_n[13]                  ),                          //   input,     width = 1,                                   .rx_n_in13
				.rx_n_in14                          (PCIE0_GT_0_grx_n[14]                  ),                          //   input,     width = 1,                                   .rx_n_in14
				.rx_n_in15                          (PCIE0_GT_0_grx_n[15]                  ),                          //   input,     width = 1,                                   .rx_n_in15
                                                                                           
				.rx_p_in0                           (PCIE0_GT_0_grx_p[0 ]                  ),                           //   input,     width = 1,                                   .rx_p_in0
				.rx_p_in1                           (PCIE0_GT_0_grx_p[1 ]                  ),                           //   input,     width = 1,                                   .rx_p_in1
				.rx_p_in2                           (PCIE0_GT_0_grx_p[2 ]                  ),                           //   input,     width = 1,                                   .rx_p_in2
				.rx_p_in3                           (PCIE0_GT_0_grx_p[3 ]                  ),                           //   input,     width = 1,                                   .rx_p_in3
				.rx_p_in4                           (PCIE0_GT_0_grx_p[4 ]                  ),                           //   input,     width = 1,                                   .rx_p_in4
				.rx_p_in5                           (PCIE0_GT_0_grx_p[5 ]                  ),                           //   input,     width = 1,                                   .rx_p_in5
				.rx_p_in6                           (PCIE0_GT_0_grx_p[6 ]                  ),                           //   input,     width = 1,                                   .rx_p_in6
				.rx_p_in7                           (PCIE0_GT_0_grx_p[7 ]                  ),                           //   input,     width = 1,                                   .rx_p_in7
				.rx_p_in8                           (PCIE0_GT_0_grx_p[8 ]                  ),                           //   input,     width = 1,                                   .rx_p_in8
				.rx_p_in9                           (PCIE0_GT_0_grx_p[9 ]                  ),                           //   input,     width = 1,                                   .rx_p_in9
				.rx_p_in10                          (PCIE0_GT_0_grx_p[10]                  ),                          //   input,     width = 1,                                   .rx_p_in10
				.rx_p_in11                          (PCIE0_GT_0_grx_p[11]                  ),                          //   input,     width = 1,                                   .rx_p_in11
				.rx_p_in12                          (PCIE0_GT_0_grx_p[12]                  ),                          //   input,     width = 1,                                   .rx_p_in12
				.rx_p_in13                          (PCIE0_GT_0_grx_p[13]                  ),                          //   input,     width = 1,                                   .rx_p_in13
				.rx_p_in14                          (PCIE0_GT_0_grx_p[14]                  ),                          //   input,     width = 1,                                   .rx_p_in14
				.rx_p_in15                          (PCIE0_GT_0_grx_p[15]                  ),                          //   input,     width = 1,                                   .rx_p_in15
		
                /*
				.p0_ss_app_vf_err_poisonedwrreq_s0  (                                      ),  //  output,     width = 1,  p0_ss_app_vf_err_poisonedwrreq_s0.ss_app_vf_err_poisonedwrreq
				.p0_ss_app_vf_err_poisonedwrreq_s1  (                                      ),  //  output,     width = 1,  p0_ss_app_vf_err_poisonedwrreq_s1.ss_app_vf_err_poisonedwrreq
				.p0_ss_app_vf_err_poisonedcompl_s0  (                                      ),  //  output,     width = 1,  p0_ss_app_vf_err_poisonedcompl_s0.ss_app_vf_err_poisonedcompl
				.p0_ss_app_vf_err_poisonedcompl_s1  (                                      ),  //  output,     width = 1,  p0_ss_app_vf_err_poisonedcompl_s1.ss_app_vf_err_poisonedcompl
				.p0_ss_app_vf_err_ur_postedreq_s0   (                                      ),   //  output,     width = 1,   p0_ss_app_vf_err_ur_postedreq_s0.ss_app_vf_err_ur_postedreq
				.p0_ss_app_vf_err_ur_postedreq_s1   (                                      ),   //  output,     width = 1,   p0_ss_app_vf_err_ur_postedreq_s1.ss_app_vf_err_ur_postedreq
				.p0_ss_app_vf_err_ca_postedreq_s0   (                                      ),   //  output,     width = 1,   p0_ss_app_vf_err_ca_postedreq_s0.ss_app_vf_err_ca_postedreq
				.p0_ss_app_vf_err_ca_postedreq_s1   (                                      ),   //  output,     width = 1,   p0_ss_app_vf_err_ca_postedreq_s1.ss_app_vf_err_ca_postedreq
				.p0_ss_app_vf_err_vf_num_s0         (                                      ),         //  output,    width = 11,         p0_ss_app_vf_err_vf_num_s0.ss_app_vf_err_vf_num
				.p0_ss_app_vf_err_vf_num_s1         (                                      ),         //  output,    width = 11,         p0_ss_app_vf_err_vf_num_s1.ss_app_vf_err_vf_num
				.p0_ss_app_vf_err_func_num_s0       (                                      ),       //  output,     width = 3,       p0_ss_app_vf_err_func_num_s0.ss_app_vf_err_func_num
				.p0_ss_app_vf_err_func_num_s1       (                                      ),       //  output,     width = 3,       p0_ss_app_vf_err_func_num_s1.ss_app_vf_err_func_num
				.p0_ss_app_vf_err_overflow          (                                      ),          //  output,     width = 1,          p0_ss_app_vf_err_overflow.ss_app_vf_err_overflow
				.p0_ss_app_vfnonfatalmsg_ready      (                                      ),      //  output,     width = 1,      p0_ss_app_vfnonfatalmsg_ready.ss_app_vfnonfatalmsg_ready
				.p0_app_ss_sent_vfnonfatalmsg       (                                      ),       //   input,     width = 1,       p0_app_ss_sent_vfnonfatalmsg.app_ss_sent_vfnonfatalmsg
				.p0_app_ss_vfnonfatalmsg_vf_num     (                                      ),     //   input,    width = 11,     p0_app_ss_vfnonfatalmsg_vf_num.app_ss_vfnonfatalmsg_vf_num
				.p0_app_ss_vfnonfatalmsg_func_num   (                                      ),   //   input,     width = 3,   p0_app_ss_vfnonfatalmsg_func_num.app_ss_vfnonfatalmsg_func_num
    */
				.refclk0                            (PCIE0_GT_0_clk_p                      ),                            //   input,     width = 1,                            refclk0.clk
				.refclk1                            (PCIE0_GT_1_clk_p                      )                             //   input,     width = 1,                            refclk1.clk
	);

/********************************************************************\
*                                                                    *
*               AXIS_MCDMA                                           *
* bar0: 2M 64bits for DMA stream                                     *                      
* bar1: 64M 64bts for DMA PIO                                        *
*                                                                    *
\********************************************************************/   

   axi_mcdma 
	 U_MCDMA(
			 .axi_st_clk                      (axi_st_app_clk                       ),                      //   input,     width = 1,                  axi_st_clk.clk
                                                                                    
			 .axi_mm_clk                      (axi_st_app_clk                       ),                      //   input,     width = 1,                  axi_mm_clk.clk
			 .axi_lite_clk                    (clk250m                              ),                    //   input,     width = 1,                axi_lite_clk.clk
                                                                                    
			 .axi_st_areset_n                 (pcie_phy_out_rst_n           		),                 //   input,     width = 1,             axi_st_areset_n.reset_n
			 .axi_mm_areset_n                 (pcie_phy_out_rst_n           		),                 //   input,     width = 1,             axi_mm_areset_n.reset_n
			 .axi_lite_areset_n               (!sys_rst                             ),               //   input,     width = 1,           axi_lite_areset_n.reset_n
		
			 .ss_app_st_rx_tvalid             (p0_app_st_rx_tvalid                  ),             //   input,     width = 1,                    ss_rx_st.tvalid
			 .ss_app_st_rx_tdata              (p0_app_st_rx_tdata                   ),              //   input,  width = 1024,                            .tdata
			 .ss_app_st_rx_tkeep              (p0_app_st_rx_tkeep                   ),              //   input,   width = 128,                            .tkeep
			 .ss_app_st_rx_tlast              (p0_app_st_rx_tlast                   ),              //   input,     width = 1,                            .tlast
			 .ss_app_st_rx_tuser_vendor       (p0_app_st_rx_tuser_vendor            ),       //   input,     width = 4,       ss_rx_st_tuser_vendor.p0_ss_app_st_rx_tuser_vendor
			 .ss_app_st_rx_tuser_last_segment (p0_app_st_rx_tuser_last_segment      ), //   input,     width = 4, ss_rx_st_tuser_last_segment.p0_ss_app_st_rx_tuser_last_segment
			 .ss_app_st_rx_tuser_hvalid       (p0_app_st_rx_tuser_hvalid            ),       //   input,     width = 4,       ss_rx_st_tuser_hvalid.p0_ss_app_st_rx_tuser_hvalid
			 .ss_app_st_rx_tuser_hdr          (p0_app_st_rx_tuser_hdr               ),          //   input,  width = 1024,          ss_rx_st_tuser_hdr.p0_ss_app_st_rx_tuser_hdr
                                                                                    
			 .app_ss_st_tx_tvalid             (p0_app_ss_st_tx_tvalid               ),             //  output,     width = 1,                    ss_tx_st.tvalid
			 .ss_app_st_tx_tready             (p0_ss_app_st_tx_tready               ),             //   input,     width = 1,                            .tready
			 .app_ss_st_tx_tdata              (p0_app_ss_st_tx_tdata                ),              //  output,  width = 1024,                            .tdata
			 .app_ss_st_tx_tkeep              (p0_app_ss_st_tx_tkeep                ),              //  output,   width = 128,                            .tkeep
			 .app_ss_st_tx_tlast              (p0_app_ss_st_tx_tlast                ),              //  output,     width = 1,                            .tlast
			 .app_ss_st_tx_tuser_last_segment (p0_app_ss_st_tx_tuser_last_segment   ), //  output,     width = 4, ss_tx_st_tuser_last_segment.p0_app_ss_st_tx_tuser_last_segment
			 .app_ss_st_tx_tuser_hvalid       (p0_app_ss_st_tx_tuser_hvalid         ),       //  output,     width = 4,       ss_tx_st_tuser_hvalid.p0_app_ss_st_tx_tuser_hvalid
			 .app_ss_st_tx_tuser_hdr          (p0_app_ss_st_tx_tuser_hdr            ),          //  output,  width = 1024,          ss_tx_st_tuser_hdr.p0_app_ss_st_tx_tuser_hdr
		     
              //axi_lite_clk
			 .app_ss_lite_csr_awvalid         (dut_ss_csr_lite_awvalid				),         //  output,     width = 1,                 ss_csr_lite.awvalid
			 .ss_app_lite_csr_awready         (dut_ss_csr_lite_awready				),         //   input,     width = 1,                            .awready
			 .app_ss_lite_csr_awaddr          (dut_ss_csr_lite_awaddr				),           //  output,    width = 20,                            .awaddr
			 .app_ss_lite_csr_wvalid          (dut_ss_csr_lite_wvalid				),           //  output,     width = 1,                            .wvalid
			 .ss_app_lite_csr_wready          (dut_ss_csr_lite_wready				),           //   input,     width = 1,                            .wready
			 .app_ss_lite_csr_wdata           (dut_ss_csr_lite_wdata				),             //  output,    width = 32,                            .wdata
			 .app_ss_lite_csr_wstrb           (dut_ss_csr_lite_wstrb				),             //  output,     width = 4,                            .wstrb
			 .ss_app_lite_csr_bvalid          (dut_ss_csr_lite_bvalid				),           //   input,     width = 1,                            .bvalid
			 .app_ss_lite_csr_bready          (dut_ss_csr_lite_bready				),           //  output,     width = 1,                            .bready
			 .ss_app_lite_csr_bresp           (dut_ss_csr_lite_bresp				),             //   input,     width = 2,                            .bresp
			 .app_ss_lite_csr_arvalid         (dut_ss_csr_lite_arvalid				),         //  output,     width = 1,                            .arvalid
			 .ss_app_lite_csr_arready         (dut_ss_csr_lite_arready				),         //   input,     width = 1,                            .arready
			 .app_ss_lite_csr_araddr          (dut_ss_csr_lite_araddr				),           //  output,    width = 20,                            .araddr
			 .ss_app_lite_csr_rvalid          (dut_ss_csr_lite_rvalid				),           //   input,     width = 1,                            .rvalid
			 .app_ss_lite_csr_rready          (dut_ss_csr_lite_rready				),           //  output,     width = 1,                            .rready
			 .ss_app_lite_csr_rdata           (dut_ss_csr_lite_rdata				),             //   input,    width = 32,                            .rdata
			 .ss_app_lite_csr_rresp           (dut_ss_csr_lite_rresp				),             //   input,     width = 2,                            .rresp
			 .ss_app_lite_csr_awprot          (dut_ss_csr_lite_awprot				),           //  output,     width = 3,                            .awprot
			 .ss_app_lite_csr_arprot          (dut_ss_csr_lite_arprot				),           //  output,     width = 3,                            .arprot
		
			 .h2d_axi_st_tvalid               (h2d_axi_st_tvalid                    ),               //  output,     width = 1,              h2d_st_initatr.tvalid
			 .h2d_axi_st_tready               (h2d_axi_st_tready                    ),               //   input,     width = 1,                            .tready
			 .h2d_axi_st_tdata                (h2d_axi_st_tdata                     ),                //  output,  width = 1024,                            .tdata
			 .h2d_axi_st_tkeep                (h2d_axi_st_tkeep                     ),                //  output,   width = 128,                            .tkeep
			 .h2d_axi_st_tlast                (h2d_axi_st_tlast                     ),                //  output,     width = 1,                            .tlast
			 .h2d_axi_st_tuser_metadata       (h2d_axi_st_tuser_metadata            ),       //  output,    width = 64,                            .tuser
			 .h2d_axi_st_tid                  (h2d_axi_st_tid                       ),                  //  output,    width = 12,                            .tid
			 .h2d_axi_st_tuser_error          (h2d_axi_st_tuser_error               ),          //  output,     width = 1,  h2d_st_initatr_tuser_error.tuser_error
			 
             .d2h_axi_st_tvalid               (d2h_axi_st_tvalid                    ),               //   input,     width = 1,              d2h_st_respndr.tvalid
			 .d2h_axi_st_tready               (d2h_axi_st_tready                    ),               //  output,     width = 1,                            .tready
			 .d2h_axi_st_tdata                (d2h_axi_st_tdata                     ),                //   input,  width = 1024,                            .tdata
			 .d2h_axi_st_tkeep                (d2h_axi_st_tkeep                     ),                //   input,   width = 128,                            .tkeep
			 .d2h_axi_st_tlast                (d2h_axi_st_tlast                     ),                //   input,     width = 1,                            .tlast
			 .d2h_axi_st_tuser_metadata       (d2h_axi_st_tuser_metadata            ),       //   input,    width = 64,                            .tuser
			 .d2h_axi_st_tid                  (d2h_axi_st_tid                       ),                  //   input,    width = 12,                            .tid
			 .d2h_axi_st_tuser_error          (d2h_axi_st_tuser_error               ),          //   input,     width = 1,  d2h_st_respndr_tuser_error.tuser_error
	          
             //axi_lite_clk
			 .bam_axi_mm_awvalid(pcie5_bam_axi_mm_awvalid),
			 .bam_axi_mm_awready(pcie5_bam_axi_mm_awready),
			 .bam_axi_mm_awid(pcie5_bam_axi_mm_awid),
			 .bam_axi_mm_awaddr(pcie5_bam_axi_mm_awaddr),
			 .bam_axi_mm_awlen(pcie5_bam_axi_mm_awlen),
			 .bam_axi_mm_awsize(pcie5_bam_axi_mm_awsize),
			 .bam_axi_mm_awburst(pcie5_bam_axi_mm_awburst),
			 .bam_axi_mm_awprot(pcie5_bam_axi_mm_awprot),
			 .bam_axi_mm_awlock(pcie5_bam_axi_mm_awlock),
			 .bam_axi_mm_awuser(pcie5_bam_axi_mm_awuser),
			 .bam_axi_mm_wvalid(pcie5_bam_axi_mm_wvalid),
			 .bam_axi_mm_wready(pcie5_bam_axi_mm_wready),
			 .bam_axi_mm_wlast(pcie5_bam_axi_mm_wlast),
			 .bam_axi_mm_wdata(pcie5_bam_axi_mm_wdata),
			 .bam_axi_mm_wstrb(pcie5_bam_axi_mm_wstrb),
			 .bam_axi_mm_bvalid(pcie5_bam_axi_mm_bvalid),
			 .bam_axi_mm_bready(pcie5_bam_axi_mm_bready),
			 .bam_axi_mm_bid(pcie5_bam_axi_mm_bid),
			 .bam_axi_mm_bresp(pcie5_bam_axi_mm_bresp),
			 .bam_axi_mm_arvalid(pcie5_bam_axi_mm_arvalid),
			 .bam_axi_mm_arready(pcie5_bam_axi_mm_arready),
			 .bam_axi_mm_arid(pcie5_bam_axi_mm_arid),
			 .bam_axi_mm_araddr(pcie5_bam_axi_mm_araddr),
			 .bam_axi_mm_arlen(pcie5_bam_axi_mm_arlen),
			 .bam_axi_mm_arsize(pcie5_bam_axi_mm_arsize),
			 .bam_axi_mm_arburst(pcie5_bam_axi_mm_arburst),
			 .bam_axi_mm_arprot(pcie5_bam_axi_mm_arprot),
			 .bam_axi_mm_arlock(pcie5_bam_axi_mm_arlock),
			 .bam_axi_mm_aruser(pcie5_bam_axi_mm_aruser),
			 .bam_axi_mm_rvalid(pcie5_bam_axi_mm_rvalid),
			 .bam_axi_mm_rready(pcie5_bam_axi_mm_rready),
			 .bam_axi_mm_rlast(pcie5_bam_axi_mm_rlast),
			 .bam_axi_mm_rid(pcie5_bam_axi_mm_rid),
			 .bam_axi_mm_rdata(pcie5_bam_axi_mm_rdata),
			 .bam_axi_mm_rresp(pcie5_bam_axi_mm_rresp),
		
			 .ss_app_st_ciireq_tvalid         (pcie_ss_dut_p0_st_ciireq_tvalid 		),         //   input,     width = 1,                  ss_cii_req.tvalid
			 .app_ss_st_ciireq_tready         (pcie_ss_dut_p0_st_ciireq_tready   	),         //  output,     width = 1,                            .tready
			 .ss_app_st_ciireq_tdata          (pcie_ss_dut_p0_st_ciireq_tdata     	),          //   input,    width = 72,                            .tdata
			 .app_ss_st_ciiresp_tvalid        (dut_ss_cii_resp_tvalid          		),        //  output,     width = 1,                 ss_cii_resp.tvalid
			 .app_ss_st_ciiresp_tdata         (dut_ss_cii_resp_tdata           		),         //  output,    width = 33,                            .tdata

			 .ss_app_st_flrrcvd_tvalid        (p0_ss_app_st_flrrcvd_tvalid          ),        //   input,     width = 1,                  ss_flrrcvd.tvalid
			 .ss_app_st_flrrcvd_tdata         (p0_ss_app_st_flrrcvd_tdata           ),         //   input,    width = 20,                            .tdata
			 .app_ss_st_flrcmpl_tvalid        (p0_app_ss_st_flrcmpl_tvalid          ),        //  output,     width = 1,                  ss_flrcmpl.tvalid
			 .app_ss_st_flrcmpl_tdata         (p0_app_ss_st_flrcmpl_tdata           ),         //  output,    width = 20,                            .tdata
			 .ss_app_st_flrcmpl_tready        (p0_ss_app_st_flrcmpl_tready          ),        //   input,     width = 1,                            .tready
			 .ss_app_st_txcrdt_tvalid         (p0_ss_app_st_txcrdt_tvalid           ),         //   input,     width = 1,                   ss_txcrdt.tvalid
			 .ss_app_st_txcrdt_tdata          (p0_ss_app_st_txcrdt_tdata            ),          //   input,    width = 19,                            .tdata
			 .app_ss_st_rxcrdt_tvalid         (p0_ss_app_st_rxcrdt_tvalid           ),         //  output,     width = 1,                   ss_rxcrdt.tvalid
			 .app_ss_st_rxcrdt_tdata          (p0_ss_app_st_rxcrdt_tdata            ),          //  output,    width = 19,                            .tdata
			 
			 .ss_app_st_ctrlshadow_tvalid     (pcie_ss_dut_p0_st_ctrlshadow_tvalid	),     //   input,     width = 1,               ss_ctrlshadow.tvalid
			 .ss_app_st_ctrlshadow_tdata      (pcie_ss_dut_p0_st_ctrlshadow_tdata	),      //   input,    width = 40,                            .tdata
			 .ss_app_st_cplto_tvalid          (pcie_ss_dut_p0_st_cplto_tvalid		),          //   input,     width = 1,                    ss_cplto.tvalid
			 .ss_app_st_cplto_tdata           (pcie_ss_dut_p0_st_cplto_tdata		),            //   input,    width = 30,                            .tdata
			 
			 .app_ss_st_err_tvalid            (dut_ss_app_err_tvalid				),                                                             //  output,     width = 1,                     ss_app_err.tvalid
			 .app_ss_st_err_tdata             (dut_ss_app_err_tdata					),                                                              //  output,    width = 32,                               .tdata
			 .app_ss_st_err_tlast             (dut_ss_app_err_tlast					),                                                              //  output,     width = 1,                               .tlast
			 .ss_app_st_err_tready            (dut_ss_app_err_tready				),                                                             //   input,     width = 1,                               .tready
			 .app_ss_st_err_tuser_error_type  (dut_app_ss_st_err_tuser_error_type_app_ss_st_err_tuser_error_type),                  //  output,    width = 14, app_ss_st_err_tuser_error_type.app_ss_st_err_tuser_error_type
	
			 
			 .bas_axi_mm_awvalid(pcie5_bas_m2s[`BAS_M2S_AWVALID]),
			 .bas_axi_mm_awready(pcie5_bas_s2m[`BAS_S2M_AWREADY]),
			 .bas_axi_mm_awid(pcie5_bas_m2s[`BAS_M2S_AWID]),
			 .bas_axi_mm_awaddr(pcie5_bas_m2s[`BAS_M2S_AWADDR]),
			 .bas_axi_mm_awuser(pcie5_bas_m2s[`BAS_M2S_AWUSER]),
			 .bas_axi_mm_awlen(pcie5_bas_m2s[`BAS_M2S_AWLEN]),
			 .bas_axi_mm_awsize(pcie5_bas_m2s[`BAS_M2S_AWSIZE]),
			 .bas_axi_mm_awburst(pcie5_bas_m2s[`BAS_M2S_AWBURST]),
			 .bas_axi_mm_awprot(pcie5_bas_m2s[`BAS_M2S_AWPROT]),
			 .bas_axi_mm_awlock(pcie5_bas_m2s[`BAS_M2S_AWLOCK]),
			 .bas_axi_mm_wvalid(pcie5_bas_m2s[`BAS_M2S_WVALID]),
			 .bas_axi_mm_wready(pcie5_bas_s2m[`BAS_S2M_WREADY]),
			 .bas_axi_mm_wlast(pcie5_bas_m2s[`BAS_M2S_WLAST]),
			 .bas_axi_mm_wdata(pcie5_bas_m2s[`BAS_M2S_WDATA]),
			 .bas_axi_mm_wstrb(pcie5_bas_m2s[`BAS_M2S_WSTRB]),
			 .bas_axi_mm_bvalid(pcie5_bas_s2m[`BAS_S2M_BVALID]),
			 .bas_axi_mm_bready(pcie5_bas_m2s[`BAS_M2S_BREADY]),
			 .bas_axi_mm_bid(pcie5_bas_s2m[`BAS_S2M_BID]),
			 .bas_axi_mm_bresp(pcie5_bas_s2m[`BAS_S2M_BRESP]),
			 .bas_axi_mm_arvalid(pcie5_bas_m2s[`BAS_M2S_ARVALID]),
			 .bas_axi_mm_arready(pcie5_bas_s2m[`BAS_S2M_ARREADY]),
			 .bas_axi_mm_arid(pcie5_bas_m2s[`BAS_M2S_ARID]),
			 .bas_axi_mm_araddr(pcie5_bas_m2s[`BAS_M2S_ARADDR]),
			 .bas_axi_mm_aruser(pcie5_bas_m2s[`BAS_M2S_ARUSER]),
			 .bas_axi_mm_arlen(pcie5_bas_m2s[`BAS_M2S_ARLEN]),
			 .bas_axi_mm_arsize(pcie5_bas_m2s[`BAS_M2S_ARSIZE]),
			 .bas_axi_mm_arburst(pcie5_bas_m2s[`BAS_M2S_ARBURST]),
			 .bas_axi_mm_arprot(pcie5_bas_m2s[`BAS_M2S_ARPROT]),
			 .bas_axi_mm_arlock(pcie5_bas_m2s[`BAS_M2S_ARLOCK]),
			 .bas_axi_mm_rvalid(pcie5_bas_s2m[`BAS_S2M_RVALID]),
			 .bas_axi_mm_rready(pcie5_bas_m2s[`BAS_M2S_RREADY]),
			 .bas_axi_mm_rlast(pcie5_bas_s2m[`BAS_S2M_RLAST]),
			 .bas_axi_mm_rid(pcie5_bas_s2m[`BAS_S2M_RID]),
			 .bas_axi_mm_rdata(pcie5_bas_s2m[`BAS_S2M_RDATA]),
			 .bas_axi_mm_rresp(pcie5_bas_s2m[`BAS_S2M_RRESP])

			 );

endmodule // pcie5x16_axis_dma
