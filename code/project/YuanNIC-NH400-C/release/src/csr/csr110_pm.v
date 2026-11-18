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

module csr110_pm  (
                Clk                 ,
                Rst                 ,
                                    
                SirAddr             ,
                SirRead             ,
                SirWdat             ,
                                    
                SirSel              ,
                SirDack             ,
                SirRdat             ,

                test_enb   			,   
                test_type  			,
                test_wr    			,
                test_done  			,
                err_flag   			,
                err_cnt    			,
				rd_done				,
				rd_addr				,
				DDR_END_ADDR		,
				
                addr_mode  			,
                addr_seed  			, 
                			
                dat_mode   			,
                ddr_dat0			,
                ddr_dat1			,
                ddr_dat2       		,
				ddr_dat3   			,
							
				total_time_r		,
				total_cnt_r			,
				total_time_w		,
				total_cnt_w			,
				
				ddr4_cal_sucess		,
				ddr4_cal_fail		,
				
				ddr_ctl_req			,
				ddr_ctl_rwn			,
				ddr_ctl_addr		,
				ddr_ctl_wdat		,
				ddr_ctl_rdat		,
				ddr_ctl_ack		
				
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

output	wire						test_enb			;
output	wire						test_type			;
output	wire	[1:0]				test_wr				;
input	wire						test_done			;
input	wire						err_flag			;
input	wire	[31:0]				err_cnt				;
input	wire						rd_done				;
input	wire	[31:0]				rd_addr				;
output	wire	[31:0]				DDR_END_ADDR		;

output	wire						addr_mode			;
output	wire	[7:0]				addr_seed			;

output	wire	[1:0]				dat_mode			;
output	wire	[31:0]				ddr_dat0			;
output	wire	[31:0]				ddr_dat1			;
output	wire	[31:0]				ddr_dat2			;
output	wire	[31:0]				ddr_dat3			;

input	wire	[31:0]				total_time_r		;
input	wire	[31:0]				total_cnt_r			;
input	wire	[31:0]				total_time_w		;
input	wire	[31:0]				total_cnt_w			;

input	wire						ddr4_cal_sucess		;
input	wire						ddr4_cal_fail		;

output	reg							ddr_ctl_req			;
output	wire						ddr_ctl_rwn			;
output	wire	[31:0]				ddr_ctl_addr		;
output	wire	[127:0]				ddr_ctl_wdat		;
input	wire	[127:0]				ddr_ctl_rdat		;
input	wire						ddr_ctl_ack			;
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
*               Content: {test_enb}        	     *
*                                                                    *
\********************************************************************/
parameter       ADDR0000   = 16'h0000  ;

wire            SirDack0000     ;
wire    [31:0]  SirRdat0000     ;

wire            SirDack0000r0   ;
wire            SirRdat0000r0   ;
wire            Clr0000r0       ;
wire            Q0000r0         ;

wire            SirDack0000r1   ;
wire    [2:0]   SirRdat0000r1   ;
wire    [2:0]   Q0000r1         ;

reg_rwsc  U_ADDR0000_r0(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirWdat    (SirWdat[31]        ),
                .SirDack    (SirDack0000r0      ),
                .SirRdat    (SirRdat0000r0      ),

                .Clr        (Clr0000r0          ),
                .Q          (Q0000r0            )
                );
defparam
U_ADDR0000_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0000_r0.DATAWIDTH   = 1,
U_ADDR0000_r0.ININTVALUE  = 1'h0, 
U_ADDR0000_r0.REGADDRESS  = ADDR0000;

assign Clr0000r0  = test_done;
assign test_enb   = Q0000r0;

reg_rw   U_ADDR0000_r1(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirWdat    (SirWdat[2:0]       ),
                .SirDack    (SirDack0000r1      ),
                .SirRdat    (SirRdat0000r1      ),

                .Q          (Q0000r1            )
                );
defparam
U_ADDR0000_r1.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0000_r1.DATAWIDTH   = 3,
U_ADDR0000_r1.ININTVALUE  = 3'b0,
U_ADDR0000_r1.REGADDRESS  = ADDR0000;

assign test_type = Q0000r1[2];
assign test_wr 	 = Q0000r1[1:0];

assign SirDack0000       = SirDack0000r0;
assign SirRdat0000[31:0] = {SirRdat0000r0,28'h0,SirRdat0000r1[2:0]};

/********************************************************************\
*                                                                    *
*               Adress : 16'h0004                                    *
*               Content: test_done,err_flag		                     *
*                                                                    *
\********************************************************************/
parameter       ADDR0004   = 16'h0004;     

wire            SirDack0004     ;
wire    [31:0]  SirRdat0004     ;
                                
wire            SirDack0004r0   ;
wire    [31:0]  SirRdat0004r0   ;
wire            Load0004r0      ;
wire    [31:0]  D0004r0         ;     

reg_ro  U_ADDR0004_r0(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirDack    (SirDack0004r0      ),
                .SirRdat    (SirRdat0004r0      ),
                                            
                .Load       (Load0004r0         ),
                .D          (D0004r0[31:0]      )
                );
defparam
U_ADDR0004_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0004_r0.DATAWIDTH   = 32,
U_ADDR0004_r0.ININTVALUE  = 32'h0,
U_ADDR0004_r0.REGADDRESS  = ADDR0004;

assign Load0004r0 = 1'b1;
assign D0004r0[31] 	 = test_done;
assign D0004r0[30:2] = 'b0;
assign D0004r0[1] 	 = ~rd_done;
assign D0004r0[0] 	 = err_flag;

assign SirDack0004 = SirDack0004r0;
assign SirRdat0004[31:0] = SirRdat0004r0[31:0] ;


/********************************************************************\
*                                                                    *
*               Adress : 16'h0008                                    *
*               Content: err_cnt	                     *
*                                                                    *
\********************************************************************/
parameter       ADDR0008   = 16'h0008;     

wire            SirDack0008     ;
wire    [31:0]  SirRdat0008     ;
                                
wire            SirDack0008r0   ;
wire    [31:0]  SirRdat0008r0   ;
wire            Load0008r0      ;
wire    [31:0]  D0008r0         ;     

reg_ro  U_ADDR0008_r0(
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
U_ADDR0008_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0008_r0.DATAWIDTH   = 32,
U_ADDR0008_r0.ININTVALUE  = 32'h0,
U_ADDR0008_r0.REGADDRESS  = ADDR0008;

assign Load0008r0 = 1'b1;
assign D0008r0 	  = err_cnt[31:0];

assign SirDack0008 = SirDack0008r0;
assign SirRdat0008[31:0] = SirRdat0008r0[31:0] ;
/********************************************************************\
*                                                                    *
*               Adress : 16'h000c                                    *
*               Content: {addr_mode,addr_seed]}              *
*                                                                    *
\********************************************************************/
parameter       ADDR000c   = 16'h000c  ;

wire            SirDack000c     ;
wire    [31:0]  SirRdat000c     ;

wire            SirDack000cr0   ;
wire    [31:0]  SirRdat000cr0   ;
wire    [31:0]  Q000cr0         ;

reg_rw   U_ADDR000c_r0(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirWdat    (SirWdat[31:0]      ),
                .SirDack    (SirDack000cr0      ),
                .SirRdat    (SirRdat000cr0      ),

                .Q          (Q000cr0[31:0]      )
                );
defparam
U_ADDR000c_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR000c_r0.DATAWIDTH   = 32,
U_ADDR000c_r0.ININTVALUE  = 32'h0,
U_ADDR000c_r0.REGADDRESS  = ADDR000c;

assign addr_mode = Q000cr0[8];
assign addr_seed = Q000cr0[7:0];

assign SirDack000c = SirDack000cr0;
assign SirRdat000c[31:0] = {SirRdat000cr0[31:0]};

/********************************************************************\
*                                                                    *
*               Adress : 16'h0010                                    *
*               Content: dat_mode                                     *
*                                                                    *
\********************************************************************/
parameter       ADDR0010   = 16'h0010  ;

wire            SirDack0010     ;
wire    [31:0]  SirRdat0010     ;

wire            SirDack0010r0   ;
wire    [1:0]   SirRdat0010r0   ;
wire    [1:0]   Q0010r0         ;

reg_rw   U_ADDR0010_r0(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirWdat    (SirWdat[1:0]       ),
                .SirDack    (SirDack0010r0      ),
                .SirRdat    (SirRdat0010r0      ),

                .Q          (Q0010r0[1:0]       )
                );
defparam
U_ADDR0010_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0010_r0.DATAWIDTH   = 2,
U_ADDR0010_r0.ININTVALUE  = 2'h0,
U_ADDR0010_r0.REGADDRESS  = ADDR0010;

assign dat_mode = Q0010r0[1:0];

assign SirDack0010 = SirDack0010r0;
assign SirRdat0010[31:0] = {30'h0,SirRdat0010r0[1:0]};

/********************************************************************\
*                                                                    *
*               Adress : 16'h0014                                    *
*               Content: ddr_dat0                                    *
*                                                                    *
\********************************************************************/
parameter       ADDR0014   = 16'h0014  ;

wire            SirDack0014     ;
wire    [31:0]  SirRdat0014     ;

wire            SirDack0014r0   ;
wire    [31:0]  SirRdat0014r0   ;
wire    [31:0]  Q0014r0         ;

reg_rw   U_ADDR0014_r0(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirWdat    (SirWdat[31:0]      ),
                .SirDack    (SirDack0014r0      ),
                .SirRdat    (SirRdat0014r0      ),

                .Q          (Q0014r0[31:0]      )
                );
defparam
U_ADDR0014_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0014_r0.DATAWIDTH   = 32,
U_ADDR0014_r0.ININTVALUE  = 32'h0,
U_ADDR0014_r0.REGADDRESS  = ADDR0014;

assign ddr_dat0 = Q0014r0[31:0];

assign SirDack0014 = SirDack0014r0;
assign SirRdat0014[31:0] = {SirRdat0014r0[31:0]};

/********************************************************************\
*                                                                    *
*               Adress : 16'h0018                                    *
*               Content: ddr_dat1                                    *
*                                                                    *
\********************************************************************/ 
parameter       ADDR0018   = 16'h0018  ;

wire            SirDack0018     ;
wire    [31:0]  SirRdat0018     ;

wire            SirDack0018r0   ;
wire    [31:0]  SirRdat0018r0   ;
wire    [31:0]  Q0018r0         ;

reg_rw   U_ADDR0018_r0(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirWdat    (SirWdat[31:0]      ),
                .SirDack    (SirDack0018r0      ),
                .SirRdat    (SirRdat0018r0      ),

                .Q          (Q0018r0[31:0]      )
                );
defparam
U_ADDR0018_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0018_r0.DATAWIDTH   = 32,
U_ADDR0018_r0.ININTVALUE  = 32'h0,
U_ADDR0018_r0.REGADDRESS  = ADDR0018;

assign ddr_dat1 = Q0018r0[31:0];

assign SirDack0018 = SirDack0018r0;
assign SirRdat0018[31:0] = {SirRdat0018r0[31:0]};
/********************************************************************\
*                                                                    *
*               Adress : 16'h001c                                    *
*               Content: ddr_dat2                                    *
*                                                                    *
\********************************************************************/
parameter       ADDR001c   = 16'h001c  ;

wire            SirDack001c     ;
wire    [31:0]  SirRdat001c     ;

wire            SirDack001cr0   ;
wire    [31:0]  SirRdat001cr0   ;
wire    [31:0]  Q001cr0         ;

reg_rw   U_ADDR001c_r0(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirWdat    (SirWdat[31:0]      ),
                .SirDack    (SirDack001cr0      ),
                .SirRdat    (SirRdat001cr0      ),

                .Q          (Q001cr0[31:0]      )
                );
defparam
U_ADDR001c_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR001c_r0.DATAWIDTH   = 32,
U_ADDR001c_r0.ININTVALUE  = 32'h0,
U_ADDR001c_r0.REGADDRESS  = ADDR001c;

assign ddr_dat2 = Q001cr0[31:0];

assign SirDack001c = SirDack001cr0;
assign SirRdat001c[31:0] = {SirRdat001cr0[31:0]};
/********************************************************************\
*                                                                    *
*               Adress : 16'h0020                                    *
*               Content: ddr_dat3                                    *
*                                                                    *
\********************************************************************/
parameter       ADDR0020   = 16'h0020  ;

wire            SirDack0020     ;
wire    [31:0]  SirRdat0020     ;

wire            SirDack0020r0   ;
wire    [31:0]  SirRdat0020r0   ;
wire    [31:0]  Q0020r0         ;

reg_rw   U_ADDR0020_r0(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirWdat    (SirWdat[31:0]      ),
                .SirDack    (SirDack0020r0      ),
                .SirRdat    (SirRdat0020r0      ),

                .Q          (Q0020r0[31:0]      )
                );
defparam
U_ADDR0020_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0020_r0.DATAWIDTH   = 32,
U_ADDR0020_r0.ININTVALUE  = 32'h0,
U_ADDR0020_r0.REGADDRESS  = ADDR0020;

assign ddr_dat3 = Q0020r0[31:0];

assign SirDack0020 = SirDack0020r0;
assign SirRdat0020[31:0] = {SirRdat0020r0[31:0]};

/********************************************************************\
*                                                                    *
*               Adress : 16'h0024                                    *
*               Content: total_time_r			                     *
*                                                                    *
\********************************************************************/
parameter       ADDR0024   = 16'h0024;     

wire            SirDack0024     ;
wire    [31:0]  SirRdat0024    ;
                                
wire            SirDack0024r0   ;
wire    [31:0]  SirRdat0024r0   ;
wire            Load0024r0      ;
wire    [31:0]  D0024r0         ;     

reg_ro  U_ADDR0024_r0(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirDack    (SirDack0024r0      ),
                .SirRdat    (SirRdat0024r0      ),
                                            
                .Load       (Load0024r0         ),
                .D          (D0024r0[31:0]      )
                );
defparam
U_ADDR0024_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0024_r0.DATAWIDTH   = 32,
U_ADDR0024_r0.ININTVALUE  = 32'h0,
U_ADDR0024_r0.REGADDRESS  = ADDR0024;

assign Load0024r0 = 1'b1;
assign D0024r0 	  = total_time_r[31:0];

assign SirDack0024 = SirDack0024r0;
assign SirRdat0024[31:0] = SirRdat0024r0[31:0] ;

/********************************************************************\
*                                                                    *
*               Adress : 16'h0028                                    *
*               Content: total_cnt_r			                     *
*                                                                    *
\********************************************************************/
parameter       ADDR0028   = 16'h0028;     

wire            SirDack0028     ;
wire    [31:0]  SirRdat0028    	;
                                
wire            SirDack0028r0   ;
wire    [31:0]  SirRdat0028r0   ;
wire            Load0028r0      ;
wire    [31:0]  D0028r0         ;     

reg_ro  U_ADDR0028_r0(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirDack    (SirDack0028r0      ),
                .SirRdat    (SirRdat0028r0      ),
                                            
                .Load       (Load0028r0         ),
                .D          (D0028r0[31:0]      )
                );
defparam
U_ADDR0028_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0028_r0.DATAWIDTH   = 32,
U_ADDR0028_r0.ININTVALUE  = 32'h0,
U_ADDR0028_r0.REGADDRESS  = ADDR0028;

assign Load0028r0 = 1'b1;
assign D0028r0 	  = total_cnt_r[31:0];

assign SirDack0028 = SirDack0028r0;
assign SirRdat0028[31:0] = SirRdat0028r0[31:0] ;
/********************************************************************\
*                                                                    *
*               Adress : 16'h002c                                    *
*               Content: total_time_w			                     *
*                                                                    *
\********************************************************************/
parameter       ADDR002c   = 16'h002c;     

wire            SirDack002c     ;
wire    [31:0]  SirRdat002c    ;
                                
wire            SirDack002cr0   ;
wire    [31:0]  SirRdat002cr0   ;
wire            Load002cr0      ;
wire    [31:0]  D002cr0         ;     

reg_ro  U_ADDR002c_r0(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirDack    (SirDack002cr0      ),
                .SirRdat    (SirRdat002cr0      ),
                                            
                .Load       (Load002cr0         ),
                .D          (D002cr0[31:0]      )
                );
defparam
U_ADDR002c_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR002c_r0.DATAWIDTH   = 32,
U_ADDR002c_r0.ININTVALUE  = 32'h0,
U_ADDR002c_r0.REGADDRESS  = ADDR002c;

assign Load002cr0 = 1'b1;
assign D002cr0 	  = total_time_w[31:0];

assign SirDack002c = SirDack002cr0;
assign SirRdat002c[31:0] = SirRdat002cr0[31:0] ;

/********************************************************************\
*                                                                    *
*               Adress : 16'h0030                                    *
*               Content: total_cnt_w			                     *
*                                                                    *
\********************************************************************/
parameter       ADDR0030   = 16'h0030;     

wire            SirDack0030     ;
wire    [31:0]  SirRdat0030    	;
                                
wire            SirDack0030r0   ;
wire    [31:0]  SirRdat0030r0   ;
wire            Load0030r0      ;
wire    [31:0]  D0030r0         ;     

reg_ro  U_ADDR0030_r0(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirDack    (SirDack0030r0      ),
                .SirRdat    (SirRdat0030r0      ),
                                            
                .Load       (Load0030r0         ),
                .D          (D0030r0[31:0]      )
                );
defparam
U_ADDR0030_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0030_r0.DATAWIDTH   = 32,
U_ADDR0030_r0.ININTVALUE  = 32'h0,
U_ADDR0030_r0.REGADDRESS  = ADDR0030;

assign Load0030r0 = 1'b1;
assign D0030r0 	  = total_cnt_w[31:0];

assign SirDack0030 = SirDack0030r0;
assign SirRdat0030[31:0] = SirRdat0030r0[31:0] ;


/********************************************************************\
*                                                                    *
*               Adress : 16'h0034                                    *
*               Content: DDR_END_ADDR                                    *
*                                                                    *
\********************************************************************/
parameter       ADDR0034   = 16'h0034  ;

wire            SirDack0034     ;
wire    [31:0]  SirRdat0034     ;

wire            SirDack0034r0   ;
wire    [31:0]  SirRdat0034r0   ;
wire    [31:0]  Q0034r0         ;

reg_rw   U_ADDR0034_r0(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirWdat    (SirWdat[31:0]      ),
                .SirDack    (SirDack0034r0      ),
                .SirRdat    (SirRdat0034r0      ),

                .Q          (Q0034r0[31:0]      )
                );
defparam
U_ADDR0034_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0034_r0.DATAWIDTH   = 32,
U_ADDR0034_r0.ININTVALUE  = 32'h7ffffff,
U_ADDR0034_r0.REGADDRESS  = ADDR0034;

assign DDR_END_ADDR = Q0034r0[31:0];

assign SirDack0034 = SirDack0034r0;
assign SirRdat0034[31:0] = {SirRdat0034r0[31:0]};

/********************************************************************\
*                                                                    *
*               Adress : 16'h0038                                    *
*               Content: rd_addr				                     *
*                                                                    *
\********************************************************************/
parameter       ADDR0038   = 16'h0038;     

wire            SirDack0038     ;
wire    [31:0]  SirRdat0038    	;
                                
wire            SirDack0038r0   ;
wire    [31:0]  SirRdat0038r0   ;
wire            Load0038r0      ;
wire    [31:0]  D0038r0         ;     

reg_ro  U_ADDR0038_r0(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirDack    (SirDack0038r0      ),
                .SirRdat    (SirRdat0038r0      ),
                                            
                .Load       (Load0038r0         ),
                .D          (D0038r0[31:0]      )
                );
defparam
U_ADDR0038_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0038_r0.DATAWIDTH   = 32,
U_ADDR0038_r0.ININTVALUE  = 32'h0,
U_ADDR0038_r0.REGADDRESS  = ADDR0038;

assign Load0038r0 	= 1'b1;
assign D0038r0[31:0]= rd_addr;

assign SirDack0038 = SirDack0038r0;
assign SirRdat0038[31:0] = SirRdat0038r0[31:0] ;
/********************************************************************\
*                                                                    *
*               Adress : 16'h0040                                    *
*               Content: ddr4_cal_fail,ddr4_cal_sucess				                     *
*                                                                    *
\********************************************************************/
parameter       ADDR0040   = 16'h0040;     

wire            SirDack0040     ;
wire    [31:0]  SirRdat0040    	;
                                
wire            SirDack0040r0   ;
wire    [31:0]  SirRdat0040r0   ;
wire            Load0040r0      ;
wire    [31:0]  D0040r0         ;     

reg_ro  U_ADDR0040_r0(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirDack    (SirDack0040r0      ),
                .SirRdat    (SirRdat0040r0      ),
                                            
                .Load       (Load0040r0         ),
                .D          (D0040r0[31:0]      )
                );
defparam
U_ADDR0040_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0040_r0.DATAWIDTH   = 32,
U_ADDR0040_r0.ININTVALUE  = 32'h0,
U_ADDR0040_r0.REGADDRESS  = ADDR0040;

assign Load0040r0 = 1'b1;
assign D0040r0[31:2]= 'b0;
assign D0040r0[1] 	= ddr4_cal_fail;
assign D0040r0[0] 	= ddr4_cal_sucess;

assign SirDack0040 = SirDack0040r0;
assign SirRdat0040[31:0] = SirRdat0040r0[31:0] ;

/********************************************************************\
*                                                                    *
*               Adress : 16'h0050                                    *
*               Content: {ddr_ctl_req,ddr_ctl_rwn,30'h0}        	     *
*                                                                    *
\********************************************************************/
parameter       ADDR0050   = 16'h0050  ;

wire            SirDack0050     ;
wire    [31:0]  SirRdat0050     ;

wire            SirDack0050r1   ;
wire            SirRdat0050r1   ;
wire            Q0050r1         ;


reg_rw   U_ADDR0050_r1(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirWdat    (SirWdat[30]        ),
                .SirDack    (SirDack0050r1      ),
                .SirRdat    (SirRdat0050r1      ),

                .Q          (Q0050r1            )
                );
defparam
U_ADDR0050_r1.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0050_r1.DATAWIDTH   = 1,
U_ADDR0050_r1.ININTVALUE  = 1'b0,
U_ADDR0050_r1.REGADDRESS  = ADDR0050;

assign ddr_ctl_rwn = Q0050r1;

assign SirDack0050       = SirDack0050r1;
assign SirRdat0050[31:0] = {1'b0,SirRdat0050r1,30'h0};

always @(posedge Clk or posedge Rst)
begin
	if(Rst)
		ddr_ctl_req <= 1'b0;
	else if((SirSelL2 == 1'b1) && (SirAddrL2 == ADDR0050))
		ddr_ctl_req <= 1'b1;
	else
		ddr_ctl_req <= 1'b0;
end

/********************************************************************\
*                                                                    *
*               Adress : 16'h0054                                    *
*               Content: {28'h00_0050,ddr_ctl_addr[3:0]}              *
*                                                                    *
\********************************************************************/
parameter       ADDR0054   = 16'h0054  ;

wire            SirDack0054     ;
wire    [31:0]  SirRdat0054     ;

wire            SirDack0054r0   ;
wire    [31:0]  SirRdat0054r0   ;
wire    [31:0]  Q0054r0         ;

reg_rw   U_ADDR0054_r0(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirWdat    (SirWdat[31:0]      ),
                .SirDack    (SirDack0054r0      ),
                .SirRdat    (SirRdat0054r0      ),

                .Q          (Q0054r0[31:0]      )
                );
defparam
U_ADDR0054_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0054_r0.DATAWIDTH   = 32,
U_ADDR0054_r0.ININTVALUE  = 32'h0,
U_ADDR0054_r0.REGADDRESS  = ADDR0054;

assign ddr_ctl_addr[31:0] = Q0054r0[31:0];

assign SirDack0054 = SirDack0054r0;
assign SirRdat0054[31:0] = {SirRdat0054r0[31:0]};

/********************************************************************\
*                                                                    *
*               Adress : 16'h0058                                    *
*               Content: ddr_ctl_wdat[31:0]/ddr_ctl_rdat[31:0]     *
*                                                                    *
\********************************************************************/
parameter       ADDR0058   = 16'h0058  ;

wire            SirDack0058     ;
wire    [31:0]  SirRdat0058     ;
                                
wire            SirDack0058r0   ;
wire    [31:0]  SirRdat0058r0   ;
wire    [31:0]  Q0058r0         ;
wire            Load0058r0      ;
wire    [31:0]  D0058r0         ;

reg_rw   U_ADDR0058_r0w(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirWdat    (SirWdat[31:0]      ),
                .SirDack    (                   ),
                .SirRdat    (                   ),

                .Q          (Q0058r0[31:0]      )
                );
defparam
U_ADDR0058_r0w.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0058_r0w.DATAWIDTH   = 32,
U_ADDR0058_r0w.ININTVALUE  = 32'h0050_0050,
U_ADDR0058_r0w.REGADDRESS  = ADDR0058;

assign ddr_ctl_wdat[31:0] = Q0058r0[31:0];

reg_ro  U_ADDR0058_r0r(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirDack    (SirDack0058r0      ),
                .SirRdat    (SirRdat0058r0      ),
                                            
                .Load       (Load0058r0         ),
                .D          (D0058r0[31:0]      )
                );
defparam
U_ADDR0058_r0r.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0058_r0r.DATAWIDTH   = 32,
U_ADDR0058_r0r.ININTVALUE  = 32'h0050_0050,
U_ADDR0058_r0r.REGADDRESS  = ADDR0058;

assign Load0058r0    = 1'b1;
assign D0058r0[31:0] = ddr_ctl_rdat[31:0];

assign SirDack0058 = SirDack0058r0;
assign SirRdat0058[31:0] = SirRdat0058r0[31:0];

/********************************************************************\
*                                                                    *
*               Adress : 16'h005C                                    *
*               Content: ddr_ctl_wdat[63:32]/ddr_ctl_rdat[63:32]         *
*                                                                    *
\********************************************************************/
parameter       ADDR005C   = 16'h005C  ;

wire            SirDack005C     ;
wire    [31:0]  SirRdat005C     ;
                                
wire            SirDack005Cr0   ;
wire    [31:0]  SirRdat005Cr0   ;
wire    [31:0]  Q005Cr0         ;
wire            Load005Cr0      ;
wire    [31:0]  D005Cr0         ;

reg_rw   U_ADDR005C_r0w(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirWdat    (SirWdat[31:0]      ),
                .SirDack    (                   ),
                .SirRdat    (                   ),

                .Q          (Q005Cr0[31:0]      )
                );
defparam
U_ADDR005C_r0w.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR005C_r0w.DATAWIDTH   = 32,
U_ADDR005C_r0w.ININTVALUE  = 32'h0000_0000,
U_ADDR005C_r0w.REGADDRESS  = ADDR005C;

assign ddr_ctl_wdat[63:32] = Q005Cr0[31:0];

reg_ro  U_ADDR005C_r0r(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirDack    (SirDack005Cr0      ),
                .SirRdat    (SirRdat005Cr0      ),
                                            
                .Load       (Load005Cr0         ),
                .D          (D005Cr0[31:0]      )
                );
defparam
U_ADDR005C_r0r.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR005C_r0r.DATAWIDTH   = 32,
U_ADDR005C_r0r.ININTVALUE  = 32'h0000_0000,
U_ADDR005C_r0r.REGADDRESS  = ADDR005C;

assign Load005Cr0    = 1'b1;
assign D005Cr0[31:0] = ddr_ctl_rdat[63:32];

assign SirDack005C = SirDack005Cr0;
assign SirRdat005C[31:0] = SirRdat005Cr0[31:0];

/********************************************************************\
*                                                                    *
*               Adress : 16'h0060                                    *
*               Content: ddr_ctl_wdat[95:64]/ddr_ctl_rdat[95:64]         *
*                                                                    *
\********************************************************************/
parameter       ADDR0060   = 16'h0060  ;

wire            SirDack0060     ;
wire    [31:0]  SirRdat0060     ;
                                
wire            SirDack0060r0   ;
wire    [31:0]  SirRdat0060r0   ;
wire    [31:0]  Q0060r0         ;
wire            Load0060r0      ;
wire    [31:0]  D0060r0         ;

reg_rw   U_ADDR0060_r0w(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirWdat    (SirWdat[31:0]      ),
                .SirDack    (                   ),
                .SirRdat    (                   ),

                .Q          (Q0060r0[31:0]      )
                );
defparam
U_ADDR0060_r0w.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0060_r0w.DATAWIDTH   = 32,
U_ADDR0060_r0w.ININTVALUE  = 32'h0000_0000,
U_ADDR0060_r0w.REGADDRESS  = ADDR0060;

assign ddr_ctl_wdat[95:64] = Q0060r0[31:0];

reg_ro  U_ADDR0060_r0r(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirDack    (SirDack0060r0      ),
                .SirRdat    (SirRdat0060r0      ),
                                            
                .Load       (Load0060r0         ),
                .D          (D0060r0[31:0]      )
                );
defparam
U_ADDR0060_r0r.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0060_r0r.DATAWIDTH   = 32,
U_ADDR0060_r0r.ININTVALUE  = 32'h0000_0000,
U_ADDR0060_r0r.REGADDRESS  = ADDR0060;

assign Load0060r0    = 1'b1;
assign D0060r0[31:0] = ddr_ctl_rdat[95:64];

assign SirDack0060 = SirDack0060r0;
assign SirRdat0060[31:0] = SirRdat0060r0[31:0];

/********************************************************************\
*                                                                    *
*               Adress : 16'h0064                                    *
*               Content: ddr_ctl_wdat[127:96]/ddr_ctl_rdat[127:96]         *
*                                                                    *
\********************************************************************/
parameter       ADDR0064   = 16'h0064  ;

wire            SirDack0064     ;
wire    [31:0]  SirRdat0064     ;
                                
wire            SirDack0064r0   ;
wire    [31:0]  SirRdat0064r0   ;
wire    [31:0]  Q0064r0         ;
wire            Load0064r0      ;
wire    [31:0]  D0064r0         ;

reg_rw   U_ADDR0064_r0w(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirWdat    (SirWdat[31:0]      ),
                .SirDack    (                   ),
                .SirRdat    (                   ),

                .Q          (Q0064r0[31:0]      )
                );
defparam
U_ADDR0064_r0w.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0064_r0w.DATAWIDTH   = 32,
U_ADDR0064_r0w.ININTVALUE  = 32'h0000_0000,
U_ADDR0064_r0w.REGADDRESS  = ADDR0064;

assign ddr_ctl_wdat[127:96] = Q0064r0[31:0];

reg_ro  U_ADDR0064_r0r(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirDack    (SirDack0064r0      ),
                .SirRdat    (SirRdat0064r0      ),
                                            
                .Load       (Load0064r0         ),
                .D          (D0064r0[31:0]      )
                );
defparam
U_ADDR0064_r0r.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0064_r0r.DATAWIDTH   = 32,
U_ADDR0064_r0r.ININTVALUE  = 32'h0000_0000,
U_ADDR0064_r0r.REGADDRESS  = ADDR0064;

assign Load0064r0    = 1'b1;
assign D0064r0[31:0] = ddr_ctl_rdat[127:96];

assign SirDack0064 = SirDack0064r0;
assign SirRdat0064[31:0] = SirRdat0064r0[31:0];

/********************************************************************\
*                                                                    *
*               Adress : 16'h0068                                    *
*               Content: {30'h0,ddr_ctl_ack}   						 *
*                                                                    *
\********************************************************************/
parameter       ADDR0068   = 16'h0068;     

wire            SirDack0068     ;
wire    [31:0]  SirRdat0068     ;
                                
wire            SirDack0068r0   ;
wire    [31:0]  SirRdat0068r0   ;
wire            Load0068r0      ;
wire    [31:0]  D0068r0         ;     

reg_ro  U_ADDR0068_r0(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirDack    (SirDack0068r0      ),
                .SirRdat    (SirRdat0068r0      ),
                                            
                .Load       (Load0068r0         ),
                .D          (D0068r0[31:0]      )
                );
defparam
U_ADDR0068_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0068_r0.DATAWIDTH   = 32,
U_ADDR0068_r0.ININTVALUE  = 32'h0,
U_ADDR0068_r0.REGADDRESS  = ADDR0068;

assign Load0068r0 = 1'b1;
assign D0068r0[31:1] 	= 'b0;
assign D0068r0[0] 		= ddr_ctl_ack;

assign SirDack0068 = SirDack0068r0;
assign SirRdat0068[31:0] = SirRdat0068r0[31:0] ;
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
        SirDack <= #`UDLY  SirDack0000 | SirDack0004 | SirDack0008 | SirDack000c |
						   SirDack0010 | SirDack0014 | SirDack0018 | SirDack001c |
                           SirDack0020 | SirDack0024 | SirDack0028 | SirDack002c |
						   SirDack0030 | SirDack0034 | SirDack0038 |
						   SirDack0040 |
						   SirDack0050 | SirDack0054 | SirDack0058 | SirDack005C |
						   SirDack0060 | SirDack0064 | SirDack0068
						 ;
end       


always @ (posedge Clk or posedge Rst)
begin
    if (Rst == 1'b1)
        SirRdat <= 1'b0;
    else
        SirRdat <= #`UDLY SirRdat0000 | SirRdat0004 | SirRdat0008 | SirRdat000c |
						  SirRdat0010 | SirRdat0014 | SirRdat0018 | SirRdat001c |
                          SirRdat0020 | SirRdat0024 | SirRdat0028 | SirRdat002c |
						  SirRdat0030 | SirRdat0034 | SirRdat0038 |
						  SirRdat0040 | 
						  SirRdat0050 | SirRdat0054 | SirRdat0058 | SirRdat005C |
						  SirRdat0060 | SirRdat0064 | SirRdat0068
						 ;
end  

endmodule