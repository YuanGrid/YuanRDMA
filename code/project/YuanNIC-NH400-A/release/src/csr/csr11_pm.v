// 2009/09/19      zhangjun      1.0             Original
//
// ***************************************************************************************
// DEFINE
//  
//                                                  
// ***************************************************************************************
//
// Module       :    csr02_pm
// Called by    :    csr
//
// ***************************************************************************************
//
// ***************************************************************************************
//
// ***************************************************************************************
// CVS version comment
//
// $LOG$
//
// ***************************************************************************************

`include "../top/define.vh"

module csr11_pm  (
                Clk                 ,
                Rst                 ,
                                    
                SirAddr             ,
                SirRead             ,
                SirWdat             ,
                                    
                SirSel              ,
                SirDack             ,
                SirRdat             ,

                eth_ctl_req         ,   
                eth_ctl_rwn         ,
                eth_ctl_addr        ,
                eth_ctl_wdat        ,
                eth_ctl_rdat        ,
                eth_ctl_byte        ,
                eth_ctl_ack         ,
                eth_ctl_status      ,
                
                eth_tx_req          , 
                eth_tx_mod          ,
                eth_tx_num          ,
                eth_tx_stop         ,
                eth_tx_ack          ,
                tx_crc_err         	,

				eth_all_rst				,
				eth_all_rst_ack			,
				eth_tx_rst				,
				eth_tx_rst_ack			,
				eth_rx_rst				,
				eth_rx_rst_ack			,
				
				eth_cdr_lock			,        
				eth_tx_pll_locked		,               
				eth_tx_lanes_stable		,             
				eth_sys_pll_locked		,              
				eth_rx_pcs_ready		,                
				eth_rx_block_lock		,               
				eth_rx_am_lock			,                  
				eth_local_fault_status	,          
				eth_remote_fault_status	,         
				eth_rx_hi_ber			,                 
				eth_rx_pcs_fully_aligned,      				
               
			    opt_mod_los				,
			    opt_mod_pst				,
			    opt_mod_lpm				,
			    opt_mod_rst
			   
			   );
                
parameter       SLAVE_SIZE  = 16;
                                            
input   wire                        Clk                 ;
input   wire                        Rst                 ;
                                                        
input   wire    [(SLAVE_SIZE-1):0]  SirAddr             ;
input   wire                        SirRead             ;
input   wire    [31:0]              SirWdat             ;
                                                        
input   wire                        SirSel              ;
output   reg                        SirDack             ;
output   reg    [31:0]              SirRdat             ;

output  reg  			            eth_ctl_req         ;
output  wire 			            eth_ctl_rwn         ;
output  wire [31:0] 	            eth_ctl_addr        ;
output  wire [31:0] 	            eth_ctl_wdat        ;
output  wire [3:0] 	            	eth_ctl_byte        ;
input   wire [31:0] 	            eth_ctl_rdat        ;
input   wire                        eth_ctl_ack         ;                                    
input   wire [31:0]                 eth_ctl_status      ; //for debug

output  wire                        eth_tx_req          ;
output  wire [3:0]                  eth_tx_mod          ;
output  wire [31:0]                 eth_tx_num          ;
output  wire                        eth_tx_stop         ;
input   wire                        eth_tx_ack          ;
output  wire                        tx_crc_err          ;

output	wire						eth_all_rst				;
input	wire						eth_all_rst_ack			;
output	wire						eth_tx_rst				;
input	wire						eth_tx_rst_ack			;
output	wire						eth_rx_rst				;
input	wire						eth_rx_rst_ack			;
															
input	wire          				eth_cdr_lock			;        
input	wire          				eth_tx_pll_locked		;               
input	wire          				eth_tx_lanes_stable		;             
input	wire          				eth_sys_pll_locked		;              
input	wire          				eth_rx_pcs_ready		;                
input	wire          				eth_rx_block_lock		;               
input	wire          				eth_rx_am_lock			;                  
input	wire          				eth_local_fault_status	;          
input	wire          				eth_remote_fault_status	;         
input	wire          				eth_rx_hi_ber			;                 
input	wire          				eth_rx_pcs_fully_aligned;      
  
input  	wire 				 		opt_mod_los         	;
input  	wire 				 		opt_mod_pst         	;//present
output 	wire 				 		opt_mod_lpm         	;//low power mode
output 	wire 	 			 		opt_mod_rst         	;//
						  
/********************************************************************\
*                                                                    *
*               Metastability harder for SirSelx                     *
*                                                                    *
\********************************************************************/

wire 			    SirSelh;
   
assign SirSelh = SirSel;
/********************************************************************\
*                                                                    *
*               Metastability harder for SirSelx                     *
*                                                                    *
\********************************************************************/
reg             SirSelL1;
reg             SirSelL2;
reg     [15:0]  SirAddrL1;
reg     [15:0]  SirAddrL2;
reg             SirReadL1;
reg             SirReadL2;

always @(posedge Clk or posedge Rst)
begin
    if (Rst == 1'b1)
        begin
            SirSelL1  <= 1'b0;
            SirSelL2  <= 1'b0;
            SirAddrL1 <= 16'h0;
            SirAddrL2 <= 16'h0;
            SirReadL1 <= 1'b0;
            SirReadL2 <= 1'b0;
        end
    else
        begin
            SirSelL1  <= SirSel;
            SirSelL2  <= SirSelL1;
            SirAddrL1 <= SirAddr;
            SirAddrL2 <= SirAddrL1;
            SirReadL1 <= SirRead;
            SirReadL2 <= SirReadL1;
        end
end
/********************************************************************\
*                                                                    *
*               Adress : 16'h0000                                    *
*               Content: {mb_ctl_req,mb_ctl_rwn,30'h0}        	     *
*                                                                    *
\********************************************************************/
parameter       ADDR0000   = 16'h0000  ;

wire            SirDack0000     ;
wire    [31:0]  SirRdat0000     ;

wire            SirDack0000r1   ;
wire            SirRdat0000r1   ;
wire            Q0000r1         ;


reg_rw   U_ADDR0000_r1(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirWdat    (SirWdat[30]        ),
                .SirDack    (SirDack0000r1      ),
                .SirRdat    (SirRdat0000r1      ),

                .Q          (Q0000r1            )
                );
defparam
U_ADDR0000_r1.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0000_r1.DATAWIDTH   = 1,
U_ADDR0000_r1.ININTVALUE  = 1'b0,
U_ADDR0000_r1.REGADDRESS  = ADDR0000;

assign eth_ctl_rwn = Q0000r1;

assign SirDack0000       = SirDack0000r1;
assign SirRdat0000[31:0] = {1'b0,SirRdat0000r1,30'h0};

always @(posedge Clk or posedge Rst)
begin
	if(Rst)
		eth_ctl_req <= 1'b0;
	else if((SirSelL2 == 1'b1) && (SirAddrL2 == ADDR0000))
		eth_ctl_req <= 1'b1;
	else
		eth_ctl_req <= 1'b0;
end

/********************************************************************\
*                                                                    *
*               Adress : 16'h0004                                    *
*               Content: {28'h00_0000,mb_ctl_addr[3:0]}              *
*                                                                    *
\********************************************************************/
parameter       ADDR0004   = 16'h0004  ;

wire            SirDack0004     ;
wire    [31:0]  SirRdat0004     ;

wire            SirDack0004r0   ;
wire    [31:0]  SirRdat0004r0   ;
wire    [31:0]  Q0004r0         ;

reg_rw   U_ADDR0004_r0(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirWdat    (SirWdat[31:0]      ),
                .SirDack    (SirDack0004r0      ),
                .SirRdat    (SirRdat0004r0      ),

                .Q          (Q0004r0[31:0]      )
                );
defparam
U_ADDR0004_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0004_r0.DATAWIDTH   = 32,
U_ADDR0004_r0.ININTVALUE  = 32'h0,
U_ADDR0004_r0.REGADDRESS  = ADDR0004;

assign eth_ctl_addr[31:0] = Q0004r0[31:0];

assign SirDack0004 = SirDack0004r0;
assign SirRdat0004[31:0] = {SirRdat0004r0[31:0]};

/********************************************************************\
*                                                                    *
*               Adress : 16'h0008                                    *
*               Content: mb_ctl_wdat[31:0]/mb_ctl_rdat[31:0]         *
*                                                                    *
\********************************************************************/
parameter       ADDR0008   = 16'h0008  ;

wire            SirDack0008     ;
wire    [31:0]  SirRdat0008     ;
                                
wire            SirDack0008r0   ;
wire    [31:0]  SirRdat0008r0   ;
wire    [31:0]  Q0008r0         ;
wire            Load0008r0      ;
wire    [31:0]  D0008r0         ;

reg_rw   U_ADDR0008_r0w(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirWdat    (SirWdat[31:0]      ),
                .SirDack    (                   ),
                .SirRdat    (                   ),

                .Q          (Q0008r0[31:0]      )
                );
defparam
U_ADDR0008_r0w.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0008_r0w.DATAWIDTH   = 32,
U_ADDR0008_r0w.ININTVALUE  = 32'h0000_0000,
U_ADDR0008_r0w.REGADDRESS  = ADDR0008;

assign eth_ctl_wdat[31:0] = Q0008r0[31:0];

reg_ro  U_ADDR0008_r0r(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirDack    (SirDack0008r0      ),
                .SirRdat    (SirRdat0008r0      ),
                                            
                .Load       (Load0008r0         ),
                .D          (D0008r0[31:0]      )
                );
defparam
U_ADDR0008_r0r.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0008_r0r.DATAWIDTH   = 32,
U_ADDR0008_r0r.ININTVALUE  = 32'h0000_0000,
U_ADDR0008_r0r.REGADDRESS  = ADDR0008;

assign Load0008r0    = 1'b1;
assign D0008r0[31:0] = eth_ctl_rdat[31:0];

assign SirDack0008 = SirDack0008r0;
assign SirRdat0008[31:0] = SirRdat0008r0[31:0];

/********************************************************************\
*                                                                    *
*               Adress : 16'h000c                                    *
*               Content: {30'h0,eth_ctl_ack}   						 *
*                                                                    *
\********************************************************************/
parameter       ADDR000C   = 16'h000C;     

wire            SirDack000C     ;
wire    [31:0]  SirRdat000C     ;
                                
wire            SirDack000Cr0   ;
wire    [31:0]  SirRdat000Cr0   ;
wire            Load000Cr0      ;
wire    [31:0]  D000Cr0         ;     

reg_ro  U_ADDR000C_r0(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirDack    (SirDack000Cr0      ),
                .SirRdat    (SirRdat000Cr0      ),
                                            
                .Load       (Load000Cr0         ),
                .D          (D000Cr0[31:0]      )
                );
defparam
U_ADDR000C_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR000C_r0.DATAWIDTH   = 32,
U_ADDR000C_r0.ININTVALUE  = 32'h0,
U_ADDR000C_r0.REGADDRESS  = ADDR000C;

assign Load000Cr0 = 1'b1;
assign D000Cr0[31:1] 	= 'b0;
assign D000Cr0[0] 		= eth_ctl_ack;

assign SirDack000C = SirDack000Cr0;
assign SirRdat000C[31:0] = SirRdat000Cr0[31:0] ;

/********************************************************************\
*                                                                    *
*               Adress : 16'h0010                                    *
*               Content: {30'h0,eth_all_rst,eth_tx_rst,eth_rx_rst}   *
*                                                                    *
\********************************************************************/
parameter       ADDR0010   = 16'h0010  ;

wire            SirDack0010     ;
wire    [31:0]  SirRdat0010     ;

wire            SirDack0010r0   ;
wire            SirRdat0010r0   ;
wire            Clr0010r0       ;
wire            Q0010r0         ;

wire            SirDack0010r1   ;
wire            SirRdat0010r1   ;
wire            Clr0010r1       ;
wire            Q0010r1         ;

wire            SirDack0010r2   ;
wire            SirRdat0010r2   ;
wire            Clr0010r2       ;
wire            Q0010r2         ;

reg_rwsc  U_ADDR0010_r0(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirWdat    (SirWdat[0]        	),
                .SirDack    (SirDack0010r0      ),
                .SirRdat    (SirRdat0010r0      ),

                .Clr        (Clr0010r0          ),
                .Q          (Q0010r0            )
                );
defparam
U_ADDR0010_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0010_r0.DATAWIDTH   = 1,
U_ADDR0010_r0.ININTVALUE  = 1'h0, 
U_ADDR0010_r0.REGADDRESS  = ADDR0010;

assign Clr0010r0  = eth_all_rst_ack;
assign eth_all_rst = Q0010r0;

reg_rwsc  U_ADDR0010_r1(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirWdat    (SirWdat[1]        	),
                .SirDack    (SirDack0010r1      ),
                .SirRdat    (SirRdat0010r1      ),

                .Clr        (Clr0010r1          ),
                .Q          (Q0010r1            )
                );
defparam
U_ADDR0010_r1.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0010_r1.DATAWIDTH   = 1,
U_ADDR0010_r1.ININTVALUE  = 1'h0, 
U_ADDR0010_r1.REGADDRESS  = ADDR0010;

assign Clr0010r1  = eth_tx_rst_ack;
assign eth_tx_rst = Q0010r1;

reg_rwsc  U_ADDR0010_r2(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirWdat    (SirWdat[2]        	),
                .SirDack    (SirDack0010r2      ),
                .SirRdat    (SirRdat0010r2      ),

                .Clr        (Clr0010r2          ),
                .Q          (Q0010r2            )
                );
defparam
U_ADDR0010_r2.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0010_r2.DATAWIDTH   = 1,
U_ADDR0010_r2.ININTVALUE  = 1'h0, 
U_ADDR0010_r2.REGADDRESS  = ADDR0010;

assign Clr0010r2  = eth_rx_rst_ack;
assign eth_rx_rst = Q0010r2;

assign SirDack0010       = SirDack0010r0 |SirDack0010r1 |SirDack0010r2;
assign SirRdat0010[31:0] = {29'h0,SirRdat0010r2,SirRdat0010r1,SirRdat0010r0};


/********************************************************************\
*                                                                    *
*               Adress : 16'h0014                                    *
*               Content: rsv                                         *
*                                                                    *
\********************************************************************/
parameter       ADDR0014   = 16'h0014;     

wire            SirDack0014     ;
wire    [31:0]  SirRdat0014     ;
                                
wire            SirDack0014r0   ;
wire    [31:0]  SirRdat0014r0   ;
wire            Load0014r0      ;
wire    [31:0]  D0014r0         ;     

reg_ro  U_ADDR0014_r0(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirDack    (SirDack0014r0      ),
                .SirRdat    (SirRdat0014r0      ),
                                            
                .Load       (Load0014r0         ),
                .D          (D0014r0[31:0]      )
                );
defparam
U_ADDR0014_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0014_r0.DATAWIDTH   = 32,
U_ADDR0014_r0.ININTVALUE  = 32'h0,
U_ADDR0014_r0.REGADDRESS  = ADDR0014;

assign Load0014r0 = 1'b1;
assign D0014r0[31:11] 	= 'b0;
assign D0014r0[10] 		= eth_rx_block_lock;
assign D0014r0[9] 		= eth_rx_am_lock;
assign D0014r0[8] 		= eth_local_fault_status;
assign D0014r0[7] 		= eth_remote_fault_status;
assign D0014r0[6] 		= eth_rx_hi_ber;
assign D0014r0[5] 		= eth_rx_pcs_fully_aligned;
assign D0014r0[4] 		= eth_cdr_lock;
assign D0014r0[3] 		= eth_tx_pll_locked;
assign D0014r0[2] 		= eth_tx_lanes_stable;
assign D0014r0[1] 		= eth_sys_pll_locked;
assign D0014r0[0] 		= eth_rx_pcs_ready;

assign SirDack0014 = SirDack0014r0;
assign SirRdat0014[31:0] = SirRdat0014r0[31:0] ;

/********************************************************************\
*                                                                    *
*               Adress : 16'h0018                                    *
*               Content: rsv                                         *
*                                                                    *
\********************************************************************/ 
parameter       ADDR0018   = 16'h0018  ;

wire            SirDack0018     ;
wire    [31:0] 	SirRdat0018     ;
                                
wire            SirDack0018r0   ;
wire    [1:0]  	SirRdat0018r0   ;
wire    [1:0]  	Q0018r0         ;

wire            SirDack0018r1   ;
wire    [1:0]  	SirRdat0018r1   ;
wire    [1:0]  	Q0018r1         ;
wire            Load0018r1      ;
wire    [1:0]  	D0018r1         ;

reg_rw   U_ADDR0018_r0w(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirWdat    (SirWdat[1:0]      	),
                .SirDack    (SirDack0018r0      ),
                .SirRdat    (SirRdat0018r0      ),

                .Q          (Q0018r0[1:0]      	)
                );
defparam
U_ADDR0018_r0w.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0018_r0w.DATAWIDTH   = 2,
U_ADDR0018_r0w.ININTVALUE  = 2'h1,
U_ADDR0018_r0w.REGADDRESS  = ADDR0018;

assign opt_mod_lpm = Q0018r0[1]; //by leonqin
assign opt_mod_rst = Q0018r0[0];

reg_ro  U_ADDR0018_r0r(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirDack    (SirDack0018r1      ),
                .SirRdat    (SirRdat0018r1      ),
                                            
                .Load       (Load0018r1         ),
                .D          (D0018r1[1:0]      	)
                );
defparam
U_ADDR0018_r0r.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0018_r0r.DATAWIDTH   = 2,
U_ADDR0018_r0r.ININTVALUE  = 2'h0,
U_ADDR0018_r0r.REGADDRESS  = ADDR0018;

assign Load0018r1 = 1'b1 ;//read
assign D0018r1[1:0] = {opt_mod_los,opt_mod_pst};

assign SirDack0018 = SirDack0018r1;
assign SirRdat0018[31:0] = {28'b0,SirRdat0018r1[1:0],SirRdat0018r0[1:0]};
/********************************************************************\
*                                                                    *
*               Adress : 16'h001c                                    *
*               Content: rsv                                         *
*                                                                    *
\********************************************************************/

/********************************************************************\
*                                                                    *
*               Adress : 16'h0020                                    *
*               Content: mb_ctl_irq                                  *
*                                                                    *
\********************************************************************/
parameter       ADDR0020   = 16'h0020;     

wire            SirDack0020     ;
wire    [31:0]  SirRdat0020     ;
                                
wire            SirDack0020r0   ;
wire    [31:0]  SirRdat0020r0   ;
wire            Load0020r0      ;
wire    [31:0]  D0020r0         ;     

reg_ro  U_ADDR0020_r0(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirDack    (SirDack0020r0      ),
                .SirRdat    (SirRdat0020r0      ),
                                            
                .Load       (Load0020r0         ),
                .D          (D0020r0[31:0]      )
                );
defparam
U_ADDR0020_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0020_r0.DATAWIDTH   = 32,
U_ADDR0020_r0.ININTVALUE  = 32'h0,
U_ADDR0020_r0.REGADDRESS  = ADDR0020;

assign Load0020r0 = 1'b1;
assign D0020r0[31:0] = {eth_ctl_status[31:0]};

assign SirDack0020 = SirDack0020r0;
assign SirRdat0020[31:0] = SirRdat0020r0[31:0] ;

/********************************************************************\
*                                                                    *
*               Adress : 16'h1000                                    *
*               Content: {tx_req,31'h0}        	                    *
*                                                                    *
\********************************************************************/
parameter       ADDR1000   = 16'h1000  ;

wire            SirDack1000     ;
wire    [31:0]  SirRdat1000     ;

wire            SirDack1000r0   ;
wire            SirRdat1000r0   ;
wire            Clr1000r0       ;
wire            Q1000r0         ;

wire            SirDack1000r1   ;
wire            SirRdat1000r1   ;
wire            Q1000r1         ;

reg_rwsc  U_ADDR1000_r0(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirWdat    (SirWdat[31]        ),
                .SirDack    (SirDack1000r0      ),
                .SirRdat    (SirRdat1000r0      ),

                .Clr        (Clr1000r0          ),
                .Q          (Q1000r0            )
                );
defparam
U_ADDR1000_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR1000_r0.DATAWIDTH   = 1,
U_ADDR1000_r0.ININTVALUE  = 1'h0, 
U_ADDR1000_r0.REGADDRESS  = ADDR1000;

assign Clr1000r0  = eth_tx_ack;
assign eth_tx_req = Q1000r0;

assign SirDack1000       = SirDack1000r0;
assign SirRdat1000[31:0] = {SirRdat1000r0,31'h0};

/********************************************************************\
*                                                                    *
*               Adress : 16'h1004                                    *
*               Content: {28'h00_0000,tx_mod[3:0]}                   *
*                                                                    *
\********************************************************************/
parameter       ADDR1004   = 16'h1004  ;

wire            SirDack1004     ;
wire    [31:0]  SirRdat1004     ;

wire            SirDack1004r0   ;
wire    [3:0]   SirRdat1004r0   ;
wire    [3:0]   Q1004r0         ;

reg_rw   U_ADDR1004_r0(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirWdat    (SirWdat[3:0]       ),
                .SirDack    (SirDack1004r0      ),
                .SirRdat    (SirRdat1004r0      ),

                .Q          (Q1004r0[3:0]      )
                );
defparam
U_ADDR1004_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR1004_r0.DATAWIDTH   = 4,
U_ADDR1004_r0.ININTVALUE  = 4'h0,
U_ADDR1004_r0.REGADDRESS  = ADDR1004;

assign eth_tx_mod[3:0] = Q1004r0[3:0];

assign SirDack1004 = SirDack1004r0;
assign SirRdat1004[31:0] = {28'd0,SirRdat1004r0[3:0]};

/********************************************************************\
*                                                                    *
*               Adress : 16'h1008                                    *
*               Content: {tx_num}                                    *
*                                                                    *
\********************************************************************/
parameter       ADDR1008   = 16'h1008  ;

wire            SirDack1008     ;
wire    [31:0]  SirRdat1008     ;

wire            SirDack1008r0   ;
wire    [31:0]  SirRdat1008r0   ;
wire    [31:0]  Q1008r0         ;

reg_rw   U_ADDR1008_r0(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirWdat    (SirWdat[31:0]      ),
                .SirDack    (SirDack1008r0      ),
                .SirRdat    (SirRdat1008r0      ),

                .Q          (Q1008r0[31:0]      )
                );
defparam
U_ADDR1008_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR1008_r0.DATAWIDTH   = 32,
U_ADDR1008_r0.ININTVALUE  = 32'h0,
U_ADDR1008_r0.REGADDRESS  = ADDR1008;

assign eth_tx_num[31:0] = Q1008r0[31:0];

assign SirDack1008 = SirDack1008r0;
assign SirRdat1008[31:0] = {SirRdat1008r0[31:0]};

/********************************************************************\
*                                                                    *
*               Adress : 16'h100C                                    *
*               Content: {tx_stop,31'h0}      	                     *
*                                                                    *
\********************************************************************/
parameter       ADDR100C   = 16'h100C  ;

wire            SirDack100C     ;
wire    [31:0]  SirRdat100C     ;

wire            SirDack100Cr0   ;
wire            SirRdat100Cr0   ;
wire            Clr100Cr0       ;
wire            Q100Cr0         ;

wire            SirDack100Cr1   ;
wire            SirRdat100Cr1   ;
wire            Q100Cr1         ;

reg_rwsc  U_ADDR100C_r0(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirWdat    (SirWdat[31]        ),
                .SirDack    (SirDack100Cr0      ),
                .SirRdat    (SirRdat100Cr0      ),

                .Clr        (Clr100Cr0          ),
                .Q          (Q100Cr0            )
                );
defparam
U_ADDR100C_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR100C_r0.DATAWIDTH   = 1,
U_ADDR100C_r0.ININTVALUE  = 1'h0, 
U_ADDR100C_r0.REGADDRESS  = ADDR100C;

assign Clr100Cr0  = eth_tx_ack;
assign eth_tx_stop = Q100Cr0;

assign SirDack100C       = SirDack100Cr0;
assign SirRdat100C[31:0] = {SirRdat100Cr0,31'h0};

/********************************************************************\
*                                                                    *
*               Adress : 16'h1010                                    *
*               Content: {tx_crc_err                                 *
*                                                                    *
\********************************************************************/
parameter       ADDR1010   = 16'h1010  ;

wire            SirDack1010     ;
wire    [31:0]  SirRdat1010     ;

wire            SirDack1010r0   ;
wire    [0:0]   SirRdat1010r0   ;
wire    [0:0]   Q1010r0         ;

reg_rw   U_ADDR1010_r0(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirWdat    (SirWdat[0:0]       ),
                .SirDack    (SirDack1010r0      ),
                .SirRdat    (SirRdat1010r0      ),

                .Q          (Q1010r0[0:0]       )
                );
defparam
U_ADDR1010_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR1010_r0.DATAWIDTH   = 1,
U_ADDR1010_r0.ININTVALUE  = 32'h0,
U_ADDR1010_r0.REGADDRESS  = ADDR1010;

assign tx_crc_err = Q1010r0[0:0];

assign SirDack1010 = SirDack1010r0;
assign SirRdat1010[31:0] = {30'd0,SirRdat1010r0[0:0]};   

/********************************************************************\
*                                                                    *
*               generate SirDack and SirRdat                         *
*                                                                    *
\********************************************************************/

always @ (posedge Clk or posedge Rst)
begin
    if (Rst == 1'b1)
        SirDack <= 1'b0;
    else
        SirDack <= #`UDLY
                           SirDack0000 | SirDack0004 | SirDack0008 | SirDack000C |
                           SirDack0010 | SirDack0014 | SirDack0018 | 
                           SirDack0020 |
						   SirDack1000 | SirDack1004 | SirDack1008 | SirDack100C |
						   SirDack1010
						 ;
end       


always @ (posedge Clk or posedge Rst)
begin
    if (Rst == 1'b1)
        SirRdat <= 1'b0;
    else
        SirRdat <= #`UDLY
                           SirRdat0000 | SirRdat0004 | SirRdat0008 | SirRdat000C |
                           SirRdat0010 | SirRdat0014 | SirRdat0018 | 
                           SirRdat0020 |
						   SirRdat1000 | SirRdat1004 | SirRdat1008 | SirRdat100C |
						   SirRdat1010
						 ;
end  

endmodule