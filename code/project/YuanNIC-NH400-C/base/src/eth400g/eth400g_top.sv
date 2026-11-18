//-----------------------------------------------------------------------------
// Title         : eth400g_top.v
// Project       : MA_A3
// Description :
// 
// Modification history :
// 12.06.2024 : created
//-----------------------------------------------------------------------------

`include "../top/define.vh"

module eth400g_top (
   input  wire                  eth_gt_fht_clk            ,
   input  wire 					eth_gt_fgt_clk            ,
                                                         
   input  wire [3:0] 			eth_gt_rxn                ,
   input  wire [3:0] 			eth_gt_rxp                ,
                                                         
   output wire [3:0] 			eth_gt_txp                ,
   output wire [3:0] 			eth_gt_txn                ,
                                                     
   input  wire 					i_rx_rst                  ,
   output wire 					o_rx_rst_ack              ,
                                                       
   input  wire 					i_tx_rst                  ,
   output wire 					o_tx_rst_ack              ,
                                                      
   input  wire 					i_rst                     ,
   output wire 					o_rst_ack                 ,
                                                      
   //status                                                    
   output wire 					eth_cdr_lock              ,
   output wire 					eth_tx_pll_locked         ,
   output wire 					eth_tx_lanes_stable       ,
   output wire 					eth_sys_pll_locked        ,
   output wire 					eth_rx_pcs_ready          ,
                                                        
   output wire                  eth_rx_block_lock         ,
   output wire                  eth_rx_am_lock            ,
   output wire                  eth_local_fault_status    ,
   output wire                  eth_remote_fault_status   ,
   output wire                  eth_rx_hi_ber             ,
   output wire                  eth_rx_pcs_fully_aligned  ,

   //register interface for MAC and serders
   input  wire 					avmm_cfg_rst              ,
                                                          
   input  wire 					avmm_cfg_clk              ,
   input  wire [23:0] 			avmm_cfg_addr             ,
   input  wire 					avmm_cfg_read             ,
   input  wire 					avmm_cfg_write            ,
   input  wire [31:0] 			avmm_cfg_wdat             ,
   input  wire [3:0] 			avmm_cfg_byte             ,
   output wire [31:0] 			avmm_cfg_rdat             ,
   output wire 					avmm_cfg_rvld             ,
   output wire 					avmm_cfg_wait_req         ,

   input  wire					i_reconfig_clk			  ,
   //mac tx data segment bus 
   output wire                  eth_mac_clk               ,
                                                        
   input  wire [64*16-1:0] 		i_tx_mac_data             ,
   input  wire 					i_tx_mac_valid            ,
   input  wire [1*16-1:0] 		i_tx_mac_inframe          ,
   input  wire [48-1:0] 		i_tx_mac_eop_empty        ,
   output wire 					o_tx_mac_ready            ,
   input  wire [1*16-1:0] 		i_tx_mac_error            ,
   input  wire [16-1:0] 		i_tx_mac_skip_crc         ,
   
   //mac rx data segment bus
   output wire [64*16-1:0] 		o_rx_mac_data             ,
   output wire 					o_rx_mac_valid            ,
   output wire [1*16-1:0] 		o_rx_mac_inframe          ,
   output wire [48-1:0] 		o_rx_mac_eop_empty        ,
   output wire [2*16-1:0] 		o_rx_mac_error            ,
   output wire [1*16-1:0] 		o_rx_mac_fcs_error        ,
   output wire [48-1:0] 		o_rx_mac_status
					);

//---------------------------------------------------------------
// clk
//---------------------------------------------------------------
 
   wire 						i_clk_sys;
   wire 						i_clk_ref;
   wire                         i_clk_tx;

   systemclk_f_0 
	 U_sys_pll(
			   .in_refclk_fht_0        (eth_gt_fht_clk    ),
			   .in_refclk_fgt_0        (eth_gt_fgt_clk    ),                // refclk_fgt.in_refclk_fgt_0
                                                          
			   .out_systempll_clk_0    (i_clk_sys         ),               // out_systempll_clk_0.clk
			   .out_fht_cmmpll_clk_0   (i_clk_ref         )
			   );

   wire 						o_clk_pll;

   assign i_clk_rx = o_clk_pll;
   assign i_clk_tx = o_clk_pll;
   assign eth_mac_clk = o_clk_pll;
   
//---------------------------------------------------------------
// reset
//---------------------------------------------------------------
   //wire 						i_rx_rst_n;
   //wire 						i_tx_rst_n;
   //wire 						i_rst_n;

   //assign i_rx_rst_n = !i_rx_rst;
   //assign i_tx_rst_n = !i_tx_rst;
   //assign i_rst_n    = !i_rst;
   
   //assign o_rx_rst_ack = !o_rx_rst_ack_n;
   //assign o_tx_rst_ack = !o_tx_rst_ack_n;
   //assign o_rst_ack    = !o_rst_ack_n;
  
  
//---------------------------------------------------------------
// jtag_avalon and avmm_decoder
//---------------------------------------------------------------
  
   wire     [31:0]               master_address;
   wire                          master_read;
   wire                          master_write;
   wire     [31:0]               master_writedata;
   wire     [3:0]                master_byteenable;
   wire     [31:0]               master_readdata;
   wire                          master_readdatavalid;
   wire                          master_waitrequest;
   wire							 reconfig_reset_new;
   // ETH_F AVMM signals
   localparam INSTANCE_NUM = 1;
   
   wire   [INSTANCE_NUM*24-1:0]  reconfig_hw_ip_addr;
   wire   [INSTANCE_NUM-1:0]     reconfig_hw_ip_read;
   wire   [INSTANCE_NUM-1:0]     reconfig_hw_ip_write;
   wire   [INSTANCE_NUM*32-1:0]  reconfig_hw_ip_writedata;
   wire   [INSTANCE_NUM*4-1:0]   reconfig_hw_ip_byteenable;
   wire   [INSTANCE_NUM*32-1:0]  reconfig_hw_ip_readdata;
   wire   [INSTANCE_NUM-1:0]     reconfig_hw_ip_readdata_valid;
   wire   [INSTANCE_NUM-1:0]     reconfig_hw_ip_waitrequest;
    
  // assign	reconfig_reset_new = avmm_cfg_rst;

   wire source_rst_n;
   reg  source_rst_n_sync;
   wire source_tx_rst_n;
   wire source_rx_rst_n;
   wire source_reconfig_reset;
   wire ninit_done;
   reg  ninit_done_sync;
   reg  arst;
   wire reconfig_reset;
   reg  reconfig_reset_sync;

   reg 		reset_till_lanes_stable;
   reg   	tx_lanes_stable_all_sync;
   reg 		tx_lanes_stable_all;
   reg  	tx_lanes_stable_sync;
 
	always @(posedge i_reconfig_clk) begin
		source_rst_n_sync 	<= source_rst_n;
		ninit_done_sync	  	<= ninit_done;
		reconfig_reset_sync <= reconfig_reset;
		tx_lanes_stable_all_sync <= tx_lanes_stable_all;
	end
	
    always @(posedge i_reconfig_clk) begin
        arst     <= ~(~source_rst_n_sync);     
    end


    wire 	i_rst_n;
    wire 	i_tx_rst_n;
    wire 	i_rx_rst_n;
    wire 	o_rx_rst_ack_n;
    wire 	o_tx_rst_ack_n;
    wire 	o_rst_ack_n;

	assign	o_rst_ack		= !o_rst_ack_n;
    assign	o_rx_rst_ack	= !o_rx_rst_ack_n;
	assign	o_tx_rst_ack	= !o_tx_rst_ack_n;
	
	assign i_rst_n			= source_rst_n && (!i_rst);
    assign i_tx_rst_n		= source_tx_rst_n && (!i_tx_rst);
    assign i_rx_rst_n		= source_rx_rst_n && (!i_rx_rst);
    assign reconfig_reset 	= source_reconfig_reset; 
	
	assign reconfig_reset_new = (reconfig_reset_sync | reset_till_lanes_stable); 
  
    wire [7:0] system_status;
    assign system_status[0] = arst;
    assign system_status[1] = &eth_rx_pcs_ready;
    assign system_status[2] = &eth_tx_lanes_stable;
    assign system_status[3] = &eth_tx_pll_locked;
    assign system_status[4] = &eth_cdr_lock;
    assign system_status[5] = |o_rx_rst_ack_n;
    assign system_status[6] = |o_tx_rst_ack_n;
    assign system_status[7] = |o_rst_ack_n;
	
    probe8 prb (
        .source  ({source_rst_n, source_tx_rst_n, source_rx_rst_n, source_reconfig_reset}),
        .probe   (system_status)
    );
    reset_ip reset (
        .ninit_done (ninit_done)
    );

always @ (posedge i_clk_tx) begin
	tx_lanes_stable_sync 	<= eth_tx_lanes_stable;
	tx_lanes_stable_all 	<= &tx_lanes_stable_sync;
end

 always @ (posedge i_reconfig_clk) begin
		if(ninit_done_sync)
			reset_till_lanes_stable <= 1;
		else if(tx_lanes_stable_all_sync)
			reset_till_lanes_stable <= 0;
 end
 
 
`ifdef DC_400G_TOOLKIT

	eth_f_jtag_avalon jtag_master (
        .clk_clk                  (i_reconfig_clk),
        //.clk_reset_reset          (reconfig_reset_sync),
        .clk_reset_reset          (reconfig_reset_new),
        .master_address           (master_address),
        .master_read              (master_read),
        .master_write             (master_write),
        .master_writedata         (master_writedata),
        .master_byteenable        (master_byteenable),
        .master_readdata          (master_readdata),
        .master_readdatavalid     (master_readdatavalid),
        .master_waitrequest       (master_waitrequest),
        .master_reset_reset       ()
);


eth_f_hw_top_avmm_decoder hw_top_avmm_decoder (
    .i_reconfig_clk           (i_reconfig_clk),
   // .i_reconfig_reset         (reconfig_reset_sync),
     .i_reconfig_reset          (reconfig_reset_new),
 
    //---avmm master from Jtag---
    .i_jtag_address           (master_address),
    .i_jtag_read              (master_read),
    .i_jtag_write             (master_write),
    .i_jtag_writedata         (master_writedata),
    .i_jtag_byteenable        (master_byteenable),
    .o_jtag_readdata          (master_readdata),
    .o_jtag_readdatavalid     (master_readdatavalid),
    .o_jtag_waitrequest       (master_waitrequest),

    //---p2p reconfig if---
    .o_reconfig_p2p_addr              (          	),
    .o_reconfig_p2p_read              (          	),
    .o_reconfig_p2p_write             (         	),
    .o_reconfig_p2p_writedata         (     		),
    .o_reconfig_p2p_byteenable        (    			),
    .i_reconfig_p2p_readdata          (32'h0      	),
    .i_reconfig_p2p_readdata_valid    (1'b0			),
    .i_reconfig_p2p_waitrequest       (1'b0   		),

    //---asym reconfig if---
    .o_reconfig_asym_addr              (          	),
    .o_reconfig_asym_read              (          	),
    .o_reconfig_asym_write             (         	),
    .o_reconfig_asym_writedata         (     		),
    .o_reconfig_asym_byteenable        (    		),
    .i_reconfig_asym_readdata          (32'h0      	),
    .i_reconfig_asym_readdata_valid    (1'b0		),
    .i_reconfig_asym_waitrequest       (1'b0   		),

    //---hw_ip reconfig if---

    .o_reconfig_hw_ip_addr              (reconfig_hw_ip_addr          ),
    .o_reconfig_hw_ip_read              (reconfig_hw_ip_read          ),
    .o_reconfig_hw_ip_write             (reconfig_hw_ip_write         ),
    .o_reconfig_hw_ip_writedata         (reconfig_hw_ip_writedata     ),
    .o_reconfig_hw_ip_byteenable        (reconfig_hw_ip_byteenable    ),
    .i_reconfig_hw_ip_readdata          (reconfig_hw_ip_readdata      ),
    .i_reconfig_hw_ip_readdata_valid    (reconfig_hw_ip_readdata_valid),
    .i_reconfig_hw_ip_waitrequest       (reconfig_hw_ip_waitrequest   ),
    
    //---hw_ip reconfig if---

    .o_reconfig_kr_ip_addr              (           ),
    .o_reconfig_kr_ip_read              (           ),
    .o_reconfig_kr_ip_write             (          	),
    .o_reconfig_kr_ip_writedata         (      		),
    .o_reconfig_kr_ip_byteenable        (        	),
    .i_reconfig_kr_ip_readdata          (32'h0     	),
    .i_reconfig_kr_ip_readdata_valid    (1'b0 		),
    .i_reconfig_kr_ip_waitrequest       (1'b0    	),

    //---hw_ip reconfig if---

    .o_reconfig_kr_ip2_addr              (        	),
    .o_reconfig_kr_ip2_read              (          ),
    .o_reconfig_kr_ip2_write             (          ),
    .o_reconfig_kr_ip2_writedata         (      	),
    .o_reconfig_kr_ip2_byteenable        (        	),
    .i_reconfig_kr_ip2_readdata          (32'h0    	),
    .i_reconfig_kr_ip2_readdata_valid    (1'b0 		),
    .i_reconfig_kr_ip2_waitrequest       (1'b0    	),

    //---tod reconfig if---
    .o_tod_addr                         (          	),
    .o_tod_read                         (          	),
    .o_tod_write                        (         	),
    .o_tod_writedata                    (     		),
    .o_tod_byteenable                   (			),
    .i_tod_readdata                     (32'h0      ),
    .i_tod_readdata_valid               (1'b0		),
    .i_tod_waitrequest                  (1'b0   	),

    //---Ctrl IF---
    .i_hw_ip_start_addr         (32'h0000_0000),
    .i_tod_start_addr           (32'h1000_0000),
    .i_asym_start_addr          (32'h1001_5000),
    .i_kr_ip_start_addr         (32'h1010_0000),
    .i_p2p_start_addr           (32'h1002_5000),
    .i_kr_ip2_start_addr         (32'h1020_0000)
);


defparam hw_top_avmm_decoder.IP_NUM             = 1;
defparam hw_top_avmm_decoder.AVMM_ADDR_WIDTH    = 32;
defparam hw_top_avmm_decoder.P2P_ADDR_WIDTH     = 12;
defparam hw_top_avmm_decoder.ASYM_ADDR_WIDTH    = 12;
defparam hw_top_avmm_decoder.KR_IP_ADDR_WIDTH   = 14;
defparam hw_top_avmm_decoder.HW_IP_ADDR_WIDTH   = 24;
defparam hw_top_avmm_decoder.TOD_ADDR_WIDTH     = 6;

`else
//assign	reconfig_reset_new				= avmm_cfg_rst;
assign 	reconfig_hw_ip_addr           	= avmm_cfg_addr;
assign 	reconfig_hw_ip_read           	= avmm_cfg_read;
assign 	reconfig_hw_ip_write          	= avmm_cfg_write;
assign 	reconfig_hw_ip_writedata        = avmm_cfg_wdat;
assign 	reconfig_hw_ip_byteenable       = avmm_cfg_byte;
assign 	avmm_cfg_rdat		          	= reconfig_hw_ip_readdata;
assign 	avmm_cfg_rvld  	 				= reconfig_hw_ip_readdata_valid;
assign 	avmm_cfg_wait_req      			= reconfig_hw_ip_waitrequest;

`endif//DC_400G_TOOLKIT
//---------------------------------------------------------------

   wire 						i_reconfig_eth_write;
   wire 						i_reconfig_eth_read;
   wire [15:0] 					i_reconfig_eth_addr;
   wire [31:0] 					i_reconfig_eth_writedata;
   wire [3:0] 					i_reconfig_eth_byteenable;
   wire [31:0] 					o_reconfig_eth_readdata;
   wire 						o_reconfig_eth_readdata_valid;
   wire 						o_reconfig_eth_waitrequest;

   parameter LANE_NUM = 'd4;
	 
   wire [LANE_NUM-1:0] 			i_reconfig_xcvr_write;
   wire [LANE_NUM-1:0] 			i_reconfig_xcvr_read;
   wire [LANE_NUM*20-1:0] 		i_reconfig_xcvr_addr;
   wire [LANE_NUM*32-1:0] 		i_reconfig_xcvr_writedata;
   wire [LANE_NUM*4-1:0] 		i_reconfig_xcvr_byteenable;
   wire [LANE_NUM*32-1:0] 		o_reconfig_xcvr_readdata;
   wire [LANE_NUM-1:0] 			o_reconfig_xcvr_readdata_valid;
   wire [LANE_NUM-1:0] 			o_reconfig_xcvr_waitrequest;

   
   wire [22:0] 					i_status_addr;
   wire 						i_status_read;
   wire 						i_status_write;
   wire [31:0] 					i_status_writedata;
   wire [3:0] 					i_status_byteenable;
   wire [31:0] 					o_status_readdata;
   wire 						o_status_readdata_valid;
   wire 						o_status_waitrequest;

   eth400g 
	 U_400g(
			.i_clk_rx                         (i_clk_rx                                ),
			.i_clk_tx                         (i_clk_tx                                ),
			
			.o_clk_pll                        (o_clk_pll                               ), 
			.o_clk_tx_div                     (                                        ), 
			.o_clk_rec_div64                  (                                        ), 
			.o_clk_rec_div                    (                                        ),
                                                                                       
			.i_rx_rst_n                       (i_rx_rst_n                              ),                            
			.i_tx_rst_n                       (i_tx_rst_n                              ),                            
			.i_rst_n                          (i_rst_n                                 ),
                                                                                       
			.o_rst_ack_n                      (o_rst_ack_n                             ),
			.o_rx_rst_ack_n                   (o_rx_rst_ack_n                          ),
			.o_tx_rst_ack_n                   (o_tx_rst_ack_n                          ),
                                                                                       
			.i_reconfig_clk                   (i_reconfig_clk                          ),                        
			.i_reconfig_reset                 (reconfig_reset_new                      ),
			
			.o_cdr_lock                       (eth_cdr_lock                            ), 
			.o_tx_pll_locked                  (eth_tx_pll_locked                       ),  
			.o_tx_lanes_stable                (eth_tx_lanes_stable                     ),
                                                                                       
			.o_sys_pll_locked                 (eth_sys_pll_locked                      ),  
			.o_rx_pcs_ready                   (eth_rx_pcs_ready                        ),
                                                                                       
			//mac register interface                                                           
			.i_reconfig_eth_addr              (i_reconfig_eth_addr[15:2]               ),
			.i_reconfig_eth_byteenable        (i_reconfig_eth_byteenable               ),
			.o_reconfig_eth_readdata_valid    (o_reconfig_eth_readdata_valid           ),
			.i_reconfig_eth_read              (i_reconfig_eth_read                     ),
			.i_reconfig_eth_write             (i_reconfig_eth_write                    ),
			.o_reconfig_eth_readdata          (o_reconfig_eth_readdata                 ),
			.i_reconfig_eth_writedata         (i_reconfig_eth_writedata                ),
			.o_reconfig_eth_waitrequest       (o_reconfig_eth_waitrequest              ),

			//serders 0 register interface
			.i_reconfig_xcvr0_addr            (i_reconfig_xcvr_addr[(0*20)+19:(0*20)+2]),
			.i_reconfig_xcvr0_read            (i_reconfig_xcvr_read[0]                 ),
			.i_reconfig_xcvr0_write           (i_reconfig_xcvr_write[0]                ),
			.i_reconfig_xcvr0_writedata       (i_reconfig_xcvr_writedata[0*32+:32]     ),
			.i_reconfig_xcvr0_byteenable      (i_reconfig_xcvr_byteenable[0*4+:4]      ),
			.o_reconfig_xcvr0_readdata        (o_reconfig_xcvr_readdata[0*32+:32]      ),
			.o_reconfig_xcvr0_readdata_valid  (o_reconfig_xcvr_readdata_valid[0]       ),
			.o_reconfig_xcvr0_waitrequest     (o_reconfig_xcvr_waitrequest[0]          ),

			//serders 1 register interface
			.i_reconfig_xcvr1_addr            (i_reconfig_xcvr_addr[(1*20)+19:(1*20)+2]),
			.i_reconfig_xcvr1_read            (i_reconfig_xcvr_read[1]                 ),
			.i_reconfig_xcvr1_write           (i_reconfig_xcvr_write[1]                ),
			.i_reconfig_xcvr1_writedata       (i_reconfig_xcvr_writedata[1*32+:32]     ),
			.i_reconfig_xcvr1_byteenable      (i_reconfig_xcvr_byteenable[1*4+:4]      ),
			.o_reconfig_xcvr1_readdata        (o_reconfig_xcvr_readdata[1*32+:32]      ),
			.o_reconfig_xcvr1_readdata_valid  (o_reconfig_xcvr_readdata_valid[1]       ),
			.o_reconfig_xcvr1_waitrequest     (o_reconfig_xcvr_waitrequest[1]          ),

			//serders 2 register interface
			.i_reconfig_xcvr2_addr            (i_reconfig_xcvr_addr[(2*20)+19:(2*20)+2]),
			.i_reconfig_xcvr2_read            (i_reconfig_xcvr_read[2]                 ),
			.i_reconfig_xcvr2_write           (i_reconfig_xcvr_write[2]                ),
			.i_reconfig_xcvr2_writedata       (i_reconfig_xcvr_writedata[2*32+:32]     ),
			.i_reconfig_xcvr2_byteenable      (i_reconfig_xcvr_byteenable[2*4+:4]      ),
			.o_reconfig_xcvr2_readdata        (o_reconfig_xcvr_readdata[2*32+:32]      ),
			.o_reconfig_xcvr2_readdata_valid  (o_reconfig_xcvr_readdata_valid[2]       ),
			.o_reconfig_xcvr2_waitrequest     (o_reconfig_xcvr_waitrequest[2]          ),
						
			//serders 3 register interface
			.i_reconfig_xcvr3_addr            (i_reconfig_xcvr_addr[(3*20)+19:(3*20)+2]),
			.i_reconfig_xcvr3_read            (i_reconfig_xcvr_read[3]                 ),
			.i_reconfig_xcvr3_write           (i_reconfig_xcvr_write[3]                ),
			.i_reconfig_xcvr3_writedata       (i_reconfig_xcvr_writedata[3*32+:32]     ),
			.i_reconfig_xcvr3_byteenable      (i_reconfig_xcvr_byteenable[3*4+:4]      ),
			.o_reconfig_xcvr3_readdata        (o_reconfig_xcvr_readdata[3*32+:32]      ),
			.o_reconfig_xcvr3_readdata_valid  (o_reconfig_xcvr_readdata_valid[3]       ),
			.o_reconfig_xcvr3_waitrequest     (o_reconfig_xcvr_waitrequest[3]          ),
			
			.o_rx_block_lock                  (eth_rx_block_lock                        ),        
			.o_rx_am_lock                     (eth_rx_am_lock                           ),        
			.o_local_fault_status             (eth_local_fault_status                   ),   
			.o_remote_fault_status            (eth_remote_fault_status                  ),      
			.o_rx_hi_ber                      (eth_rx_hi_ber                            ),        
			.o_rx_pcs_fully_aligned           (eth_rx_pcs_fully_aligned                 ),

			
			.i_clk_sys                        (i_clk_sys                               ),  //Need to connect with sys_pll IP
			.i_clk_ref                        (i_clk_ref                               ),
			
			.i_rx_serial                      (eth_gt_rxp[3:0]                         ),
			.i_rx_serial_n                    (eth_gt_rxn[3:0]                         ), 
			.o_tx_serial                      (eth_gt_txp[3:0]                         ), 
			.o_tx_serial_n                    (eth_gt_txn[3:0]                         ),
			
			.i_tx_pause                       ('d0                                     ),
			.i_tx_pfc                         ('d0                                     ),
			
			.o_rx_pfc                         (                                        ),
			.o_rx_pause                       (                                        ),
			
			.i_tx_mac_data                    (i_tx_mac_data                           ),
			.i_tx_mac_valid                   (i_tx_mac_valid                          ),
			.i_tx_mac_inframe                 (i_tx_mac_inframe                        ),
			.i_tx_mac_eop_empty               (i_tx_mac_eop_empty                      ),
			.o_tx_mac_ready                   (o_tx_mac_ready                          ),
			.i_tx_mac_error                   (i_tx_mac_error                          ),
			.i_tx_mac_skip_crc                (i_tx_mac_skip_crc                       ),
			
			.o_rx_mac_data                    (o_rx_mac_data                           ),
			.o_rx_mac_valid                   (o_rx_mac_valid                          ),
			.o_rx_mac_inframe                 (o_rx_mac_inframe                        ),
			.o_rx_mac_eop_empty               (o_rx_mac_eop_empty                      ),
			.o_rx_mac_error                   (o_rx_mac_error                          ),
			.o_rx_mac_fcs_error               (o_rx_mac_fcs_error                      ),
			.o_rx_mac_status                  (o_rx_mac_status                         ),
			
			.i_stats_snapshot                 (1'b0                        			   )
			);

   parameter AVMM_ETH_START_ADDR    = 24'h00_0000;
   parameter AVMM_XCVR_START_ADDR   = 24'h80_0000;
   parameter AVMM_STATUS_START_ADDR = 24'h10_0000;

   eth_f_hw_ip_avmm_decoder 
	 ip_avmm_decoder(
			  .i_reconfig_clk                   (i_reconfig_clk                  ),
			  .i_reconfig_reset                 (reconfig_reset_new              ),
                                                
			  //---avmm master from Jtag---         
			  .i_jtag_address                   (reconfig_hw_ip_addr           	 ),
			  .i_jtag_read                      (reconfig_hw_ip_read           	 ),
			  .i_jtag_write                     (reconfig_hw_ip_write          	 ),
			  .i_jtag_writedata                 (reconfig_hw_ip_writedata      	 ),
			  .i_jtag_byteenable                (reconfig_hw_ip_byteenable     	 ),
			  .o_jtag_readdata                  (reconfig_hw_ip_readdata       	 ),
			  .o_jtag_readdatavalid             (reconfig_hw_ip_readdata_valid 	 ),
			  .o_jtag_waitrequest               (reconfig_hw_ip_waitrequest    	 ),

			  //---eth reconfig if---
			  .o_reconfig_eth_addr              (i_reconfig_eth_addr             ),
			  .o_reconfig_eth_read              (i_reconfig_eth_read             ),
			  .o_reconfig_eth_write             (i_reconfig_eth_write            ),
			  .o_reconfig_eth_writedata         (i_reconfig_eth_writedata        ),
			  .o_reconfig_eth_byteenable        (i_reconfig_eth_byteenable       ),
			  .i_reconfig_eth_readdata          (o_reconfig_eth_readdata         ),
			  .i_reconfig_eth_readdata_valid    (o_reconfig_eth_readdata_valid   ),
			  .i_reconfig_eth_waitrequest       (o_reconfig_eth_waitrequest      ),

			  //---eth reconfig if---

			  .o_reconfig_xcvr_addr             (i_reconfig_xcvr_addr            ),
			  .o_reconfig_xcvr_read             (i_reconfig_xcvr_read            ),
			  .o_reconfig_xcvr_write            (i_reconfig_xcvr_write           ),
			  .o_reconfig_xcvr_writedata        (i_reconfig_xcvr_writedata       ),
			  .o_reconfig_xcvr_byteenable       (i_reconfig_xcvr_byteenable      ),
			  .i_reconfig_xcvr_readdata         (o_reconfig_xcvr_readdata        ),
			  .i_reconfig_xcvr_readdata_valid   (o_reconfig_xcvr_readdata_valid  ),
			  .i_reconfig_xcvr_waitrequest      (o_reconfig_xcvr_waitrequest     ),
			  
			  //---eth reconfig if---
			  .o_status_addr                    (i_status_addr                   ),
			  .o_status_read                    (i_status_read                   ),
			  .o_status_write                   (i_status_write                  ),
			  .o_status_writedata               (i_status_writedata              ),
			  .o_status_byteenable              (i_status_byteenable             ),
			  .i_status_readdata                (o_status_readdata               ),
			  .i_status_readdata_valid          (o_status_readdata_valid         ),
			  .i_status_waitrequest             (o_status_waitrequest            ),
                                                                                 
			  //---Ctrl IF---
			  .i_eth_start_addr                 (AVMM_ETH_START_ADDR             ),
			  .i_xcvr_start_addr                (AVMM_XCVR_START_ADDR            ),
			  .i_status_start_addr              (AVMM_STATUS_START_ADDR          )
			  );	
   defparam    ip_avmm_decoder.LANE_NUM           = 4;
   defparam    ip_avmm_decoder.AVMM_ADDR_WIDTH    = 24;
   defparam    ip_avmm_decoder.ETH_ADDR_WIDTH     = 16;
   defparam    ip_avmm_decoder.XCVR_ADDR_WIDTH    = 20;
   defparam    ip_avmm_decoder.STATUS_ADDR_WIDTH  = 23;
   
endmodule // eth400g_top


