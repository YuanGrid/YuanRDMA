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

module csr17_pm  (
                Clk                 ,
                Rst                 ,
                                    
                SirAddr             ,
                SirRead             ,
                SirWdat             ,
                                    
                SirSel              ,
                SirDack             ,
                SirRdat             
				  
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

/********************************************************************\
*                                                                    *
*               Metastability harder for SirSelx                     *
*                                                                    *
\********************************************************************/


/********************************************************************\
*                                                                    *
*               Adress : 16'h0200                                    *
*               Content: {Ver[7:0],Rev[7:0],SubVer[15:0]}            *
*                                                                    *
\********************************************************************/
parameter       ADDR0200 = 16'h0200;

wire            SirDack0200     ;
wire    [31:0]  SirRdat0200     ;

wire            SirDack0200r0   ;      
wire    [31:0]  SirRdat0200r0   ;

reg_para  U_ADDR0200_r0(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirDack    (SirDack0200r0      ),
                .SirRdat    (SirRdat0200r0      )
                );
defparam
U_ADDR0200_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0200_r0.DATAWIDTH   = 32,
U_ADDR0200_r0.ININTVALUE  = {`DDR_FRE,`DDR_WIDTH,`DDR_NUM},    
U_ADDR0200_r0.REGADDRESS  = ADDR0200;

assign SirDack0200 = SirDack0200r0;
assign SirRdat0200[31:0] = SirRdat0200r0[31:0];

/********************************************************************\
*                                                                    *
*               Adress : 16'h0204                                    *
*               Content: {VER_TYPE[15:0],Build[15:0]}                 *
*                                                                    *
\********************************************************************/
parameter       ADDR0204 = 16'h0204;

wire            SirDack0204     ;
wire    [31:0]  SirRdat0204     ;

wire            SirDack0204r0   ;
wire    [31:0]  SirRdat0204r0   ;

reg_para  U_ADDR0204_r0(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel            ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirDack    (SirDack0204r0      ),
                .SirRdat    (SirRdat0204r0      )
                );
defparam
U_ADDR0204_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0204_r0.DATAWIDTH   = 32,
U_ADDR0204_r0.ININTVALUE  = {6'b0,`DIMM_VAL,`ECC_VAL,`ECC_WIDTH,`DDR_TYPE,`DDR_CAPACITY},
U_ADDR0204_r0.REGADDRESS  = ADDR0204;

assign SirDack0204 = SirDack0204r0;
assign SirRdat0204[31:0] = SirRdat0204r0[31:0];

/********************************************************************\
*                                                                    *
*               Adress : 16'h0208                                    *
*               Content: {YEAR[15:0],MON[7:0],DATE[7:0]}             *
*                                                                    *
\********************************************************************/
parameter       ADDR0208 = 16'h0208;

wire            SirDack0208     ;
wire    [31:0]  SirRdat0208     ;

wire            SirDack0208r0   ;      
wire    [31:0]  SirRdat0208r0   ;

reg_para  U_ADDR0208_r0(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel            ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirDack    (SirDack0208r0      ),
                .SirRdat    (SirRdat0208r0      )
                );
defparam
U_ADDR0208_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0208_r0.DATAWIDTH   = 32,
U_ADDR0208_r0.ININTVALUE  = {3'b0,`DDR_DIE,`COMPONENT_VENDOR,`COMPONENT_TYPE,`COMPONENT_WIDTH,`COMPONENT_CAPACITY},    
U_ADDR0208_r0.REGADDRESS  = ADDR0208;

assign SirDack0208 = SirDack0208r0;
assign SirRdat0208[31:0] = SirRdat0208r0[31:0];

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
        SirDack <= #`UDLY SirDack0200 | SirDack0204 | SirDack0208
				   ;
end       

always @ (posedge Clk)
begin
        SirRdat <= #`UDLY  SirRdat0200 | SirRdat0204 | SirRdat0208
						;
end

endmodule
