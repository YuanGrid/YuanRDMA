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

module csr20_pm  (
                Clk                 ,
                Rst                 ,
                                    
                SirAddr             ,
                SirRead             ,
                SirWdat             ,
                                    
                SirSel              ,
                SirDack             ,
                SirRdat             ,

				sdm_mb_addr         ,
				sdm_mb_wdat         ,
				sdm_mb_write        ,
				sdm_mb_read         ,
				sdm_mb_rdat         ,
				sdm_mb_rvld         ,
                sdm_mb_wait         ,
				sdm_mb_irq          ,  
                sdm_mb_status       ,

				sdm_mb_rst			,
				
				mb_mon_req			,
				mb_mon_time		
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

output  wire [3:0]  	            sdm_mb_addr         ;
output  wire [31:0] 	            sdm_mb_wdat         ;
output  wire        	            sdm_mb_write        ;
output  wire 					    sdm_mb_read         ;
input   wire [31:0] 	            sdm_mb_rdat         ;
input   wire                        sdm_mb_rvld         ;  
input   wire                        sdm_mb_wait         ;                                  
input   wire  			            sdm_mb_irq          ;
input   wire [23:0]                 sdm_mb_status       ; //for debug

output	reg 						sdm_mb_rst			;
output	wire						mb_mon_req			;
output	wire 	[7:0]				mb_mon_time			;						  
/********************************************************************\
*                                                                    *
*               Metastability harder for SirSelx                     *
*                                                                    *
\********************************************************************/

wire 			    SirSelh;
   
assign SirSelh = SirSel;

/********************************************************************\
*                                                                    *
*               Adress : 16'h0000-16'h00FF                           *
*               Content: mail_box registers                          *
*                                                                    *
\********************************************************************/   

wire 			                   SirDack00xx;
wire [31:0] 					   SirRdat00xx;

mb_ctl_csr   
  U_mb_ctl_csr (
			  .rst                 (Rst                  ),
			  .clk                 (Clk                  ),

			  .sir_selh            (SirSelh & (SirAddr[15:8] == 8'h00)),
			  .sir_read            (SirRead              ),
			  .sir_dack            (SirDack00xx          ),
			  
			  .sir_addr            (SirAddr[7:4]         ),
			  .sir_wdat            (SirWdat[31:0]        ),
			  .sir_rdat            (SirRdat00xx          ),

			  .sdm_mb_addr         (sdm_mb_addr          ),
			  .sdm_mb_wdat         (sdm_mb_wdat          ),
			  .sdm_mb_write        (sdm_mb_write         ),
			  .sdm_mb_read         (sdm_mb_read          ),
			  .sdm_mb_rdat         (sdm_mb_rdat          ),
			  .sdm_mb_rvld         (sdm_mb_rvld          ),
			  .sdm_mb_wait         (sdm_mb_wait          )
			  );

/********************************************************************\
*                                                                    *
*               Adress : 16'h0100                                    *
*               Content: mb_ctl_irq                                  *
*                                                                    *
\********************************************************************/
parameter       ADDR0100   = 16'h0100;     

wire            SirDack0100     ;
wire    [31:0]  SirRdat0100     ;
                                
wire            SirDack0100r0   ;
wire    [31:0]  SirRdat0100r0   ;
wire            Load0100r0      ;
wire    [31:0]  D0100r0         ;     

reg_ro  U_ADDR0100_r0(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirDack    (SirDack0100r0      ),
                .SirRdat    (SirRdat0100r0      ),
                                            
                .Load       (Load0100r0         ),
                .D          (D0100r0[31:0]      )
                );
defparam
U_ADDR0100_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0100_r0.DATAWIDTH   = 32,
U_ADDR0100_r0.ININTVALUE  = 32'h0,
U_ADDR0100_r0.REGADDRESS  = ADDR0100;

assign Load0100r0 = 1'b1;
assign D0100r0[31:0] = {sdm_mb_status[23:0],7'h0,sdm_mb_irq};

assign SirDack0100 = SirDack0100r0;
assign SirRdat0100[31:0] = SirRdat0100r0[31:0] ;


/********************************************************************\
*                                                                    *
*               Adress : 16'h0110                                    *
*               Content: {31'h0, mailbox Reset}                      *
*                                                                    *
\********************************************************************/
wire			sdm_mb_rst_req;
reg		[7:0]	sdm_mb_rst_cnt;
reg				sdm_mb_rst_clr;

parameter       ADDR0110   = 16'h0110  ;

wire            SirDack0110     ;
wire    [31:0]  SirRdat0110     ;

wire    		SirRdat0110r0   ;
wire            Clr0110r0       ;
wire    		Q0110r0         ;

reg_rwsc  U_ADDR0110_r0(
                .Clk        (Clk                ),
                .Rst        (Rst            	),
                                                
                .SirSel     (SirSel            	),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirWdat    (SirWdat[0]       	),
                .SirDack    (SirDack0110        ),
                .SirRdat    (SirRdat0110r0      ),

                .Clr        (Clr0110r0          ),
                .Q          (Q0110r0       		)
                );
defparam
U_ADDR0110_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0110_r0.DATAWIDTH   = 1,
U_ADDR0110_r0.ININTVALUE  = 1'h0,
U_ADDR0110_r0.REGADDRESS  = ADDR0110;

assign sdm_mb_rst_req = Q0110r0;
assign Clr0110r0  = sdm_mb_rst_clr;

assign SirRdat0110[31:0] = {31'h0, SirRdat0110r0};

always @(posedge Clk or posedge Rst)
begin
	if(Rst)
		sdm_mb_rst_cnt <= 1'b0;
	else if(sdm_mb_rst_req == 1'b1)
		sdm_mb_rst_cnt <= sdm_mb_rst_cnt + 1'b1;
	else
		sdm_mb_rst_cnt <= 'b0;
end

always @(posedge Clk or posedge Rst)
begin
	if(Rst)
		sdm_mb_rst_clr <= 1'b0;
	else if(sdm_mb_rst_cnt[7:2] == 6'h3f)
		sdm_mb_rst_clr <= 1'b1;
	else
		sdm_mb_rst_clr <= 1'b0;
end

always @(posedge Clk or posedge Rst)
begin
	if(Rst)
		sdm_mb_rst <= 1'b0;
	else if(sdm_mb_rst_cnt[7] == 1'b1)
		sdm_mb_rst <= 1'b1;
	else
		sdm_mb_rst <= 1'b0;
end


/********************************************************************\
*                                                                    *
*               Adress : 16'h0114                                    *
*               Content: {mb_mon_req,mb_mon_time]}              *
*                                                                    *
\********************************************************************/
parameter       ADDR0114   = 16'h0114  ;

wire            SirDack0114     ;
wire    [31:0]  SirRdat0114     ;

wire            SirDack0114r0   ;
wire    [31:0]  SirRdat0114r0   ;
wire    [31:0]  Q0114r0         ;

reg_rw   U_ADDR0114_r0(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirWdat    (SirWdat[31:0]      ),
                .SirDack    (SirDack0114r0      ),
                .SirRdat    (SirRdat0114r0      ),

                .Q          (Q0114r0[31:0]      )
                );
defparam
U_ADDR0114_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0114_r0.DATAWIDTH   = 32,
U_ADDR0114_r0.ININTVALUE  = 32'h0,
U_ADDR0114_r0.REGADDRESS  = ADDR0114;

assign mb_mon_req 	= Q0114r0[31];
assign mb_mon_time 	= Q0114r0[7:0];

assign SirDack0114 = SirDack0114r0;
assign SirRdat0114[31:0] = {SirRdat0114r0[31:0]};

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
                           SirDack00xx | 
                           SirDack0100 | SirDack0110 | SirDack0114
						 ;
end       


always @ (posedge Clk or posedge Rst)
begin
    if (Rst == 1'b1)
        SirRdat <= 1'b0;
    else
        SirRdat <= #`UDLY
                           SirRdat00xx | 
                           SirRdat0100 | SirRdat0110 | SirRdat0114
						 ;
end  

endmodule