
`include "../top/global_define.vh"
`include "../top/build_info.v"

module csr00_pm  (
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
*               Adress : 16'h0000                                    *
*               Content: {Ver[7:0],Rev[7:0],SubVer[15:0]}            *
*                                                                    *
\********************************************************************/
parameter       ADDR0000 = 16'h0000;

wire            SirDack0000     ;
wire    [31:0]  SirRdat0000     ;

wire            SirDack0000r0   ;      
wire    [31:0]  SirRdat0000r0   ;

reg_para  U_ADDR0000_r0(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirDack    (SirDack0000r0      ),
                .SirRdat    (SirRdat0000r0      )
                );
defparam
U_ADDR0000_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0000_r0.DATAWIDTH   = 32,
U_ADDR0000_r0.ININTVALUE  = 32'h4e540000,    
U_ADDR0000_r0.REGADDRESS  = ADDR0000;

assign SirDack0000 = SirDack0000r0;
assign SirRdat0000[31:0] = SirRdat0000r0[31:0];

/********************************************************************\
*                                                                    *
*               Adress : 16'h0004                                    *
*               Content: {VER_TYPE[15:0],Build[15:0]}                 *
*                                                                    *
\********************************************************************/
parameter       ADDR0004 = 16'h0004;

wire            SirDack0004     ;
wire    [31:0]  SirRdat0004     ;

wire            SirDack0004r0   ;
wire    [31:0]  SirRdat0004r0   ;

reg_para  U_ADDR0004_r0(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel            ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirDack    (SirDack0004r0      ),
                .SirRdat    (SirRdat0004r0      )
                );
defparam
U_ADDR0004_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0004_r0.DATAWIDTH   = 32,
U_ADDR0004_r0.ININTVALUE  = 32'h20260617,
U_ADDR0004_r0.REGADDRESS  = ADDR0004;

assign SirDack0004 = SirDack0004r0;
assign SirRdat0004[31:0] = SirRdat0004r0[31:0];

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
        SirDack <= #`UDLY SirDack0000 | SirDack0004  ;
end       

always @ (posedge Clk)
begin
        SirRdat <= #`UDLY SirRdat0000 | SirRdat0004 ;
end

endmodule
