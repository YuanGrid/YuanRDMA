// 2009/09/19      zhangjun      1.0             Original
//
// ***************************************************************************************
// DEFINE
//  
//                                                  
// ***************************************************************************************
//
// Module       :    csr01_pm
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
`include "../top/build.v"

module csr14_pm  (
                Clk                 ,
                Rst                 ,
                                    
                SirAddr             ,
                SirRead             ,
                SirWdat             ,
                                    
                SirSel              ,
                SirDack             ,
                SirRdat             ,

                SoftFpgaRstVal      ,
                SoftFpgaRstClr      
				  
               );
                
parameter       SLAVE_SIZE  = 16;
                                            
input   wire                        Clk                 ;
input   wire                        Rst                 ;
                                                        
input   wire    [(SLAVE_SIZE-1):0]  SirAddr             ;
input   wire                        SirRead             ;
input   wire    [31:0]              SirWdat             ;
                                                        
input   wire                        SirSel              ;
output  reg                         SirDack             ;
output  reg     [31:0]              SirRdat             ;

output  wire    [7:0]               SoftFpgaRstVal      ;
input   wire                        SoftFpgaRstClr      ;

/********************************************************************\
*                                                                    *
*               Metastability harder for SirSelx                     *
*                                                                    *
\********************************************************************/

//////////////////////////////////////////////////////////////////////
//	地址10020寄存器复位不应使用全局复位寄存器，否则sys_rst生效时，
//	0x5a值会立马别清除，达不到长时间复位的效果
//////////////////////////////////////////////////////////////////////
reg 		InitRst = 'h0;
reg [7:0]	InitCnt = 'h0;
always @ (posedge Clk)
begin
	if(InitCnt == 8'hff)
		InitCnt <= InitCnt;
	else
		InitCnt <= InitCnt + 1'h1;
		
	InitRst <= InitCnt != 8'hff;
end
/********************************************************************\
*                                                                    *
*               Adress : 16'h0000                                    *
*               Content: {24'h0, Soft Reset[7:0]}                    *
*                                                                    *
\********************************************************************/
parameter       ADDR0000   = 16'h0000  ;

wire            SirDack0000     ;
wire    [31:0]  SirRdat0000     ;

wire    [7:0]   SirRdat0000r0   ;
wire            Clr0000r0       ;
wire    [7:0]   Q0000r0         ;

reg_rwsc  U_ADDR0000_r0(
                .Clk        (Clk                ),
                .Rst        (InitRst            ),
                                                
                .SirSel     (SirSel            ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirWdat    (SirWdat[7:0]       ),
                .SirDack    (SirDack0000        ),
                .SirRdat    (SirRdat0000r0      ),

                .Clr        (Clr0000r0          ),
                .Q          (Q0000r0[7:0]       )
                );
defparam
U_ADDR0000_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0000_r0.DATAWIDTH   = 8,
U_ADDR0000_r0.ININTVALUE  = 8'h0,
U_ADDR0000_r0.REGADDRESS  = ADDR0000;

assign SoftFpgaRstVal = Q0000r0[7:0];
assign Clr0000r0      = SoftFpgaRstClr;

assign SirRdat0000[31:0] = {24'h0, SirRdat0000r0[7:0]};

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
        SirDack <= #`UDLY SirDack0000 ;
end       

always @ (posedge Clk)
begin
        SirRdat <= #`UDLY SirRdat0000 ;
end

endmodule
