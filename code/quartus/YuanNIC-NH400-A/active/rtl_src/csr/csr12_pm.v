
`include "../top/global_define.vh"
`include "../top/build_info.v"

module csr12_pm  (
                Clk                 ,
                Rst                 ,
                                    
                SirAddr             ,
                SirRead             ,
                SirWdat             ,
                                    
                SirSel              ,
                SirDack             ,
                SirRdat             ,

                TestData            
				  
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

output  wire    [31:0]              TestData            ;

/********************************************************************\
*                                                                    *
*               Metastability harder for SirSelx                     *
*                                                                    *
\********************************************************************/

/********************************************************************\
*                                                                    *
*               Adress : 16'h0000                                    *
*               Content: {RW test register}                          *
*                                                                    *
\********************************************************************/
parameter       ADDR0000   = 16'h0000  ;

wire            SirDack0000     ;
wire    [31:0]  SirRdat0000     ;

wire            SirDack0000r0   ;
wire    [31:0]  SirRdat0000r0   ;
wire    [31:0]  Q0000r0         ;

reg_rw   U_ADDR0000_r0(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel            ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirWdat    (SirWdat[31:0]      ),
                .SirDack    (SirDack0000r0      ),
                .SirRdat    (SirRdat0000r0      ),

                .Q          (Q0000r0[31:0]      )
                );
defparam
U_ADDR0000_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0000_r0.DATAWIDTH   = 32,
U_ADDR0000_r0.ININTVALUE  = 32'h0,
U_ADDR0000_r0.REGADDRESS  = ADDR0000;

assign TestData = Q0000r0[31:0];

assign SirDack0000 = SirDack0000r0;
assign SirRdat0000[31:0] = SirRdat0000r0[31:0];

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
