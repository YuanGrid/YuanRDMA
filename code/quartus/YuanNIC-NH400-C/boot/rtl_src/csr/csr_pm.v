
`include "../top/global_define.vh"
// `define     UDLY                1
module csr_pm  (

input   wire                        Rst                     ,
input   wire                        HardRst                 ,

input   wire                        Gclk125m                ,
input   wire                        Gclk250m                ,
                                                            
input   wire                        SirSel                  ,
input   wire    [31:0]              SirAddr                 ,
input   wire                        SirRead                 ,
input   wire    [31:0]              SirWdat                 ,
output  wire    [31:0]              SirRdat                 ,
output  wire                        SirDackh                ,

//csr11
input   wire                        DcmLock                 ,
input   wire    [4:0]               Dimm0InitDone           ,
//csr12
output  wire    [31:0]              TestData                ,
input   wire    [31:0]              ErrMsg                  ,
//csr14
output  wire    [7:0]               SoftFpgaRstVal          ,
input   wire                        SoftFpgaRstClr          ,

//csr20
output  wire 	[3:0]  	            sdm_mb_addr             ,
output  wire 	[31:0] 	            sdm_mb_wdat             ,
output  wire        	            sdm_mb_write            ,
output  wire 					    sdm_mb_read             ,
input   wire 	[31:0] 	            sdm_mb_rdat             ,
input   wire                        sdm_mb_rvld             , 
input   wire                        sdm_mb_wait             ,                                   
input   wire  			            sdm_mb_irq              ,
input   wire 	[23:0]         		sdm_mb_status           , 
output	wire						sdm_mb_rst				,
output	wire						mb_mon_req				,
output	wire	[7:0]				mb_mon_time				,
//csr15		
//output  wire 			            eth_ctl_write           ,
//output  wire 			            eth_ctl_read           	,
//output  wire 	[23:0] 	            eth_ctl_addr            ,
//output  wire 	[31:0] 	            eth_ctl_wdat            ,
//output  wire 	[3:0] 	            eth_ctl_byte            ,
//input   wire 	[31:0] 	            eth_ctl_rdat            ,
//input   wire                        eth_ctl_rvld            , 
//input   wire 						eth_ctl_wait	        ,

//csr11
output  wire 			            eth_ctl_req            	,
output  wire 			            eth_ctl_rwn            	,
output  wire 	[31:0] 	            eth_ctl_addr            ,
output  wire 	[31:0] 	            eth_ctl_wdat            ,
input  wire 	[31:0] 	            eth_ctl_rdat            ,
output  wire 	[3:0]				eth_ctl_byte	        ,
input   wire 	 	            	eth_ctl_ack             ,
input   wire    [31:0]              eth_ctl_status          , 

output  wire                        eth_tx_req              , 
output  wire 	[3:0]            	eth_tx_mod              ,
output  wire 	[31:0]             	eth_tx_num              ,
output  wire                        eth_tx_stop             ,
input   wire                        eth_tx_ack              ,
output  wire                        tx_crc_err              ,

output	wire						eth_all_rst				,
input	wire						eth_all_rst_ack			,
output	wire						eth_tx_rst				,
input	wire						eth_tx_rst_ack			,
output	wire						eth_rx_rst				,
input	wire						eth_rx_rst_ack			,

input	wire          				eth_cdr_lock			,        
input	wire          				eth_tx_pll_locked		,               
input	wire          				eth_tx_lanes_stable		,             
input	wire          				eth_sys_pll_locked		,              
input	wire          				eth_rx_pcs_ready		,                
input	wire          				eth_rx_block_lock		,               
input	wire          				eth_rx_am_lock			,                  
input	wire          				eth_local_fault_status	,          
input	wire          				eth_remote_fault_status	,         
input	wire          				eth_rx_hi_ber			,                 
input	wire          				eth_rx_pcs_fully_aligned,      

input  	wire 				 		opt_mod_los         	,
input  	wire 				 		opt_mod_pst         	,//present
output 	wire 				 		opt_mod_lpm         	,//low power mode
output 	wire 	 			 		opt_mod_rst         	,//
//csr110
output	wire						test_enb				,
output	wire 						test_type				,
output	wire 	[1:0]				test_wr					,
input	wire						test_done				,
input	wire						err_flag				,
input	wire 	[31:0]				err_cnt					,
input	wire						rd_done					,
input	wire	[31:0]				rd_addr					,
output	wire	[31:0]				DDR_END_ADDR			,

output	wire 						addr_mode				,
output	wire 	[7:0]				addr_seed				,

output	wire 	[1:0]				dat_mode				,
output	wire 	[31:0]				ddr_dat0				,
output	wire 	[31:0]				ddr_dat1				,
output	wire 	[31:0]				ddr_dat2				,
output	wire 	[31:0]				ddr_dat3				,
	
input	wire 	[31:0]				total_time_w			,
input	wire 	[31:0]				total_cnt_w				,
input	wire 	[31:0]				total_time_r			,
input	wire 	[31:0]				total_cnt_r				,

input	wire						ddr4_cal_sucess			,
input	wire						ddr4_cal_fail			,

output	wire						ddr_ctl_req				,
output	wire						ddr_ctl_rwn				,
output	wire	[31:0]				ddr_ctl_addr			,
output	wire	[127:0]				ddr_ctl_wdat			,
input	wire	[127:0]				ddr_ctl_rdat			,
input	wire						ddr_ctl_ack				,
//csr40
output	wire						i2c_m_cpld_sel			,
output	wire						i2c_m_cpld_rw			,
output	wire	[4:0]				i2c_m_cpld_dlen			,
output	wire	[2:0]				i2c_m_cpld_mode			,
output	wire	[31:0]				i2c_m_cpld_addr			,
output	wire	[6:0]				i2c_m_cpld_dev_id		,
output	wire	[127:0]				i2c_m_cpld_data			,
input	wire	[127:0]				i2c_m_cpld_rdata		,
input	wire						i2c_m_cpld_done			,
input	wire						i2c_m_cpld_ack			,

//csr0f
output  wire                        IbusStatSel             ,
output  wire                        IbusStatRead            ,
output  wire   [12:0]               IbusStatAddr            ,
output  wire   [63:0]               IbusStatWdat            ,
input   wire   [63:0]               IbusStatRdat            ,
input   wire                        IbusStatDack            ,                                                   
output  wire                        StatClrReq              ,
input   wire                        StatClrOver             				

             );

/************************************************************/
wire    [15:0]  SirAddrx            ;
wire            SirReadx            ;
wire    [31:0]  SirWdatx            ;
               
wire            SirSel10            ;
wire            SirRead10           ;
wire            SirDack10           ;
wire    [31:0]  SirRdat10           ;

wire            SirSel11            ;
wire            SirRead11           ;
wire            SirDack11           ;
wire    [31:0]  SirRdat11           ;

wire            SirSel12            ;
wire            SirRead12           ;
wire            SirDack12           ;
wire    [31:0]  SirRdat12           ;

wire            SirSel14            ;
wire            SirRead14           ;
wire            SirDack14           ;
wire    [31:0]  SirRdat14           ;

wire            SirSel15            ;
wire            SirRead15           ;
wire            SirDack15           ;
wire    [31:0]  SirRdat15           ;

wire            SirSel16            ;
wire            SirRead16           ;
wire            SirDack16           ;
wire    [31:0]  SirRdat16           ;

wire            SirSel17            ;
wire            SirRead17           ;
wire            SirDack17           ;
wire    [31:0]  SirRdat17           ;

wire            SirSel18            ;
wire            SirRead18           ;
wire            SirDack18           ;
wire    [31:0]  SirRdat18           ;
                
wire            SirSel19            ;
wire            SirRead19           ;
wire            SirDack19           ;
wire    [31:0]  SirRdat19           ;
                
wire            SirSel1a            ;
wire            SirRead1a           ;
wire            SirDack1a           ;
wire    [31:0]  SirRdat1a           ;
                
wire            SirSel1b            ;
wire            SirRead1b           ;
wire            SirDack1b           ;
wire    [31:0]  SirRdat1b           ;


wire            SirSel1e            ;
wire            SirRead1e           ;
wire            SirDack1e           ;
wire    [31:0]  SirRdat1e           ;

wire            SirSel1f            ;
wire            SirRead1f           ;
wire            SirDack1f           ;
wire    [31:0]  SirRdat1f           ;

wire            SirSel20            ;
wire            SirRead20           ;
wire            SirDack20           ;
wire    [31:0]  SirRdat20           ;

wire            SirSel40            ;
wire            SirRead40           ;
wire            SirDack40           ;
wire    [31:0]  SirRdat40           ;

wire            SirSel110           ;
wire            SirRead110          ;
wire            SirDack110          ;
wire    [31:0]  SirRdat110          ;
/**************************************************************************************************/
/********************************************************************\
*                                                                    *
*               local bus module                                     *
*                                                                    *
\********************************************************************/
sempir    U_sempir(
                .Clk                (Gclk125m           ),
                .Rst                (HardRst            ),

                .SirSel             (SirSel             ),
                .SirAddr            (SirAddr[31:0]      ),
                .SirRead            (SirRead            ),
                .SirWdat            (SirWdat            ),
                .SirRdat            (SirRdat            ),
                .SirDackh           (SirDackh           ),

                .SirAddrx           (SirAddrx           ),
                .SirWdatx           (SirWdatx           ),
                                                        
                .SirSel10           (SirSel10           ),
                .SirRead10          (SirRead10          ),
                .SirDack10          (SirDack10          ),
                .SirRdat10          (SirRdat10          ),
                
				.SirSel11           (SirSel11           ),
                .SirRead11          (SirRead11          ),
                .SirDack11          (SirDack11          ),
                .SirRdat11          (SirRdat11          ),
				
				.SirSel12           (SirSel12           ),
                .SirRead12          (SirRead12          ),
                .SirDack12          (SirDack12          ),
                .SirRdat12          (SirRdat12          ),

                .SirSel14           (SirSel14           ),
                .SirRead14          (SirRead14          ),
                .SirDack14          (SirDack14          ),
                .SirRdat14          (SirRdat14          ),

                .SirSel15           (SirSel15           ),
                .SirRead15          (SirRead15          ),
                .SirDack15          (SirDack15          ),
                .SirRdat15          (SirRdat15          ),

                .SirSel16           (SirSel16           ),
                .SirRead16          (SirRead16          ),
                .SirDack16          (SirDack16          ),
                .SirRdat16          (SirRdat16          ),

                .SirSel17           (SirSel17           ),
                .SirRead17          (SirRead17          ),
                .SirDack17          (SirDack17          ),
                .SirRdat17          (SirRdat17          ),
                
                .SirSel18           (SirSel18           ),
                .SirRead18          (SirRead18          ),
                .SirDack18          (SirDack18          ),
                .SirRdat18          (SirRdat18          ),
                                     
                .SirSel19           (SirSel19           ),
                .SirRead19          (SirRead19          ),
                .SirDack19          (SirDack19          ),
                .SirRdat19          (SirRdat19          ),
                                     
                .SirSel1a           (SirSel1a           ),
                .SirRead1a          (SirRead1a          ),
                .SirDack1a          (SirDack1a          ),
                .SirRdat1a          (SirRdat1a          ),
                                     
                .SirSel1b           (SirSel1b           ),
                .SirRead1b          (SirRead1b          ),
                .SirDack1b          (SirDack1b          ),
                .SirRdat1b          (SirRdat1b          ),
                
                .SirSel1e           (SirSel1e           ),
                .SirRead1e          (SirRead1e          ),                
                .SirDack1e          (SirDack1e          ),
                .SirRdat1e          (SirRdat1e          ),

                .SirSel1f           (SirSel1f           ),
                .SirRead1f          (SirRead1f          ),                
                .SirDack1f          (SirDack1f	        ),
                .SirRdat1f          (SirRdat1f        	),
				
                .SirSel20           (SirSel20           ),
                .SirRead20          (SirRead20          ),                
                .SirDack20          (SirDack20	        ),
                .SirRdat20          (SirRdat20        	),
                
				.SirSel40           (SirSel40           ),
                .SirRead40          (SirRead40          ),                
                .SirDack40          (SirDack40	        ),
                .SirRdat40          (SirRdat40        	),
				
				.SirSel110          (SirSel110          ),
                .SirRead110         (SirRead110         ),                
                .SirDack110         (SirDack110        	),
                .SirRdat110         (SirRdat110       	)
                
                );
               
//assign	SirDack10   = 1'b0  ;
//assign	SirRdat10   = 32'h0 ;
//assign	SirDack12   = 1'b0  ;
//assign	SirRdat12   = 32'h0 ;
//assign	SirDack14   = 1'b0  ;
//assign	SirRdat14   = 32'h0 ;
//assign	SirDack15   = 1'b0  ;
//assign	SirRdat15   = 32'h0 ;
assign	SirDack16   = 1'b0  ;
assign	SirRdat16   = 32'h0 ;
//assign	SirDack17   = 1'b0  ;
//assign	SirRdat17   = 32'h0	;
assign	SirDack18   = 1'b0  ;
assign	SirRdat18   = 32'h0 ;
assign	SirDack19   = 1'b0  ;
assign	SirRdat19   = 32'h0 ;
assign	SirDack1a   = 1'b0  ;
assign	SirRdat1a   = 32'h0 ;
assign	SirDack1b   = 1'b0  ;
assign	SirRdat1b   = 32'h0	;
assign	SirDack1e   = 1'b0  ;
assign	SirRdat1e   = 32'h0	;  
assign	SirDack1f   = 1'b0  ;
assign	SirRdat1f   = 32'h0	;          
//assign	SirDack20   = 1'b0  ;
//assign	SirRdat20   = 32'h0	;      
/********************************************************************\
*                                                                    *
*               CSR                                                  *
*                                                                    *
\********************************************************************/

// global
csr10_pm  U_csr10_pm(
                .Clk                    (Gclk250m           ),
                .Rst                    (HardRst            ),
                                                            
                .SirAddr                (SirAddrx           ),
                .SirRead                (SirRead10          ),
                .SirWdat                (SirWdatx           ),
                                                            
                .SirSel                 (SirSel10           ),
                .SirDack                (SirDack10          ),
                .SirRdat                (SirRdat10          )
              );

//csr11 for eth400g register     
csr11_pm  U_csr11_pm(
                .Clk                    	(Gclk250m           		),     
                .Rst                    	(Rst                		),
			
                .SirAddr                	(SirAddrx           		),  
                .SirRead                	(SirRead11          		),
                .SirWdat                	(SirWdatx           		),
			
                .SirSel                 	(SirSel11           		), 
                .SirDack                	(SirDack11          		),
                .SirRdat                	(SirRdat11          		),
			
			//间接操作
                .eth_ctl_req            	(eth_ctl_req        		), 
                .eth_ctl_rwn            	(eth_ctl_rwn        		),
                .eth_ctl_addr           	(eth_ctl_addr       		),
                .eth_ctl_wdat           	(eth_ctl_wdat       		),
                .eth_ctl_rdat           	(eth_ctl_rdat       		),
                .eth_ctl_byte           	(eth_ctl_byte       		),
                .eth_ctl_ack            	(eth_ctl_ack        		),
                .eth_ctl_status         	(eth_ctl_status     		),
							
                .eth_tx_req             	(eth_tx_req         		), 
                .eth_tx_mod             	(eth_tx_mod         		),
                .eth_tx_num             	(eth_tx_num         		),
                .eth_tx_stop            	(eth_tx_stop        		),
                .eth_tx_ack             	(eth_tx_ack         		),
                .tx_crc_err             	(tx_crc_err         		),
					
				.eth_all_rst				(eth_all_rst				),
				.eth_all_rst_ack			(eth_all_rst_ack			),
				.eth_tx_rst					(eth_tx_rst					),
				.eth_tx_rst_ack				(eth_tx_rst_ack				),
				.eth_rx_rst					(eth_rx_rst					),
				.eth_rx_rst_ack				(eth_rx_rst_ack				),
											
				.eth_cdr_lock				(eth_cdr_lock				),        
				.eth_tx_pll_locked			(eth_tx_pll_locked			),               
				.eth_tx_lanes_stable		(eth_tx_lanes_stable		),             
				.eth_sys_pll_locked			(eth_sys_pll_locked			),              
				.eth_rx_pcs_ready			(eth_rx_pcs_ready			),                
				.eth_rx_block_lock			(eth_rx_block_lock			),               
				.eth_rx_am_lock				(eth_rx_am_lock				),                  
				.eth_local_fault_status		(eth_local_fault_status		),          
				.eth_remote_fault_status	(eth_remote_fault_status	),         
				.eth_rx_hi_ber				(eth_rx_hi_ber				),                 
				.eth_rx_pcs_fully_aligned	(eth_rx_pcs_fully_aligned	),
				
				.opt_mod_los				(opt_mod_los				),
				.opt_mod_pst				(opt_mod_pst				),
				.opt_mod_lpm				(opt_mod_lpm				),
				.opt_mod_rst				(opt_mod_rst				)
				
                );

// test
csr12_pm  U_csr12_pm(
                .Clk                    (Gclk250m           ),
                .Rst                    (HardRst            ),
                                                            
                .SirAddr                (SirAddrx           ),
                .SirRead                (SirRead12          ),
                .SirWdat                (SirWdatx           ),
                                                            
                .SirSel                 (SirSel12           ),
                .SirDack                (SirDack12          ),
                .SirRdat                (SirRdat12          ),
				
				.TestData               (TestData           )
              );

// soft reset
csr14_pm  U_csr14_pm(
                .Clk                    (Gclk250m           ),
                .Rst                    (HardRst            ),
                                                            
                .SirAddr                (SirAddrx           ),
                .SirRead                (SirRead14          ),
                .SirWdat                (SirWdatx           ),
                                                            
                .SirSel                 (SirSel14           ),
                .SirDack                (SirDack14          ),
                .SirRdat                (SirRdat14          ),
				
				.SoftFpgaRstVal			(SoftFpgaRstVal		),
				.SoftFpgaRstClr			(SoftFpgaRstClr		)
              );
			  
//csr for eth400g 直接操作
csr15_pm  U_csr15_pm(
                .Clk                    (Gclk250m           ),     
                .Rst                    (Rst                ),

                .SirAddr                (SirAddrx           ),  
                .SirRead                (SirRead15          ),
                .SirWdat                (SirWdatx           ),

                .SirSel                 (SirSel15           ), 
                .SirDack                (SirDack15          ),
                .SirRdat                (SirRdat15          )
 
                //.eth_ctl_addr           (eth_ctl_addr       ), 
                //.eth_ctl_wdat           (eth_ctl_wdat       ),
                //.eth_ctl_write          (eth_ctl_write      ),
                //.eth_ctl_read           (eth_ctl_read       ),
                //.eth_ctl_byte           (eth_ctl_byte       ),
                //.eth_ctl_rdat           (eth_ctl_rdat       ),
                //.eth_ctl_rvld           (eth_ctl_rvld       ),
                //.eth_ctl_wait           (eth_ctl_wait       )
                ); 
//ddr
csr17_pm  U_csr17_pm(
                .Clk                    (Gclk250m           ),
                .Rst                    (HardRst            ),
                                                            
                .SirAddr                (SirAddrx           ),
                .SirRead                (SirRead17          ),
                .SirWdat                (SirWdatx           ),
                                                            
                .SirSel                 (SirSel17           ),
                .SirDack                (SirDack17          ),
                .SirRdat                (SirRdat17          )
              );				
//mailbox for configuartion flash and I2C interface 
csr20_pm  U_csr20_pm(
                .Clk                    (Gclk250m           ),     
                .Rst                    (Rst                ),

                .SirAddr                (SirAddrx           ),  
                .SirRead                (SirRead20          ),
                .SirWdat                (SirWdatx           ),

                .SirSel                 (SirSel20           ), 
                .SirDack                (SirDack20          ),
                .SirRdat                (SirRdat20          ),
 
                .sdm_mb_addr            (sdm_mb_addr        ), 
                .sdm_mb_wdat            (sdm_mb_wdat        ),
                .sdm_mb_write           (sdm_mb_write       ),
                .sdm_mb_read            (sdm_mb_read        ),
                .sdm_mb_rdat            (sdm_mb_rdat        ),
                .sdm_mb_rvld            (sdm_mb_rvld        ),
                .sdm_mb_wait            (sdm_mb_wait        ),
                .sdm_mb_irq             (sdm_mb_irq         ),
                .sdm_mb_status          (sdm_mb_status      ),
				.sdm_mb_rst				(sdm_mb_rst			),
				
				.mb_mon_req				(mb_mon_req			),
				.mb_mon_time			(mb_mon_time		)
                );

   
  
//i2c_m_cpld_scl/sda 
csr40_pm  U_csr40_pm(
                .Clk                    (Gclk250m           ),     
                .Rst                    (Rst                ),

                .SirAddr                (SirAddrx           ),  
                .SirRead                (SirRead40          ),
                .SirWdat                (SirWdatx           ),

                .SirSel                 (SirSel40           ), 
                .SirDack                (SirDack40          ),
                .SirRdat                (SirRdat40          ),
 
                .i2c_m_cpld_sel         (i2c_m_cpld_sel     ), 
                .i2c_m_cpld_rw          (i2c_m_cpld_rw      ),
                .i2c_m_cpld_dlen        (i2c_m_cpld_dlen    ),
                .i2c_m_cpld_mode        (i2c_m_cpld_mode    ),
                .i2c_m_cpld_addr        (i2c_m_cpld_addr    ),
                .i2c_m_cpld_dev_id      (i2c_m_cpld_dev_id  ),
                .i2c_m_cpld_data        (i2c_m_cpld_data    ),
                .i2c_m_cpld_rdata       (i2c_m_cpld_rdata   ),
                //.i2c_m_cpld_done  		(i2c_m_cpld_done  	),
				.i2c_m_cpld_ack			(i2c_m_cpld_ack		)
				
                );
//ddr_test
csr110_pm  U_csr110_pm(
                .Clk                    (Gclk250m           ),     
                .Rst                    (Rst                ),

                .SirAddr                (SirAddrx           ),  
                .SirRead                (SirRead110         ),
                .SirWdat                (SirWdatx           ),

                .SirSel                 (SirSel110          ), 
                .SirDack                (SirDack110         ),
                .SirRdat                (SirRdat110         ),
 
                .test_enb            	(test_enb   		), 
                .test_type            	(test_type  		),
                .test_wr            	(test_wr    		),
				.test_done           	(test_done  		),
                .err_flag            	(err_flag   		),
                .err_cnt            	(err_cnt    		),
				.rd_done				(rd_done			),
				.rd_addr				(rd_addr			),
				.DDR_END_ADDR			(DDR_END_ADDR		),
				
				.addr_mode            	(addr_mode  		),
                .addr_seed             	(addr_seed  		),
												
				.dat_mode          		(dat_mode   		),
                .ddr_dat0				(ddr_dat0			),
				.ddr_dat1				(ddr_dat1			),
				.ddr_dat2               (ddr_dat2   		),
				.ddr_dat3               (ddr_dat3   		),
												
				.total_time_w			(total_time_w		),
				.total_cnt_w			(total_cnt_w		),
				.total_time_r			(total_time_r		),
				.total_cnt_r			(total_cnt_r		),
				
				.ddr4_cal_sucess		(ddr4_cal_sucess	),
				.ddr4_cal_fail			(ddr4_cal_fail		),
				
				.ddr_ctl_req			(ddr_ctl_req		),
				.ddr_ctl_rwn			(ddr_ctl_rwn		),
				.ddr_ctl_addr			(ddr_ctl_addr		),
				.ddr_ctl_wdat			(ddr_ctl_wdat		),
				.ddr_ctl_rdat			(ddr_ctl_rdat		),
				.ddr_ctl_ack			(ddr_ctl_ack		)
				
				);                       
//statis
/* csr0f_pm  U_csr0f_pm(            
               .Clk                     (Gclk250m           ), 
               .Rst                     (Rst                ),
                                                            
               .SirAddr                 (SirAddrx           ),
               .SirRead                 (SirRead0f          ),
               .SirWdat                 (SirWdatx           ),
                                                            
               .SirSel                  (SirSel0f           ),
               .SirDack                 (SirDack0f          ),
               .SirRdat                 (SirRdat0f          ),
                                                            
               .IbusStatSel             (IbusStatSel        ),
               .IbusStatRead            (IbusStatRead       ),
               .IbusStatAddr            (IbusStatAddr       ),
               .IbusStatWdat            (IbusStatWdat       ),
               .IbusStatRdat            (IbusStatRdat       ),
               .IbusStatDack            (IbusStatDack       ),
               .StatClrReq              (StatClrReq         ),
               .StatClrOver             (StatClrOver        )
               );
  */
endmodule
              
              