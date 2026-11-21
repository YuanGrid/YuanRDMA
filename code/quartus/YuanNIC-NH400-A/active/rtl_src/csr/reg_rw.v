
`include "../top/global_define.vh"

module reg_rw(
                Clk         ,
                Rst         ,

                SirSel      ,
                SirRead     ,
                SirAddr     ,
                SirWdat     ,
                SirDack     ,
                SirRdat     ,

                Q
                );

parameter   ADDRWIDTH   = 8;
parameter   DATAWIDTH   = 1;
parameter   ININTVALUE  = 1'b0;
parameter   REGADDRESS  = 8'h01;

input                       Clk         ;
input                       Rst         ;
                            
input                       SirSel      ;
input                       SirRead     ;
input   [(ADDRWIDTH-1):0]   SirAddr     ;
input   [(DATAWIDTH-1):0]   SirWdat     ;
output                      SirDack     ;
output  [(DATAWIDTH-1):0]   SirRdat     ;

output  [(DATAWIDTH-1):0]   Q           ;

/**************************************************************************************************/
wire                        Clk         ;
wire                        Rst         ;
                            
wire                        SirSel      ;
wire                        SirRead     ;
wire    [(ADDRWIDTH-1):0]   SirAddr     ;
wire    [(DATAWIDTH-1):0]   SirWdat     ;
reg                         SirDack ='d0;
reg	    [(DATAWIDTH-1):0]   SirRdat ='d0;

(* keep = "true", max_fanout = 256 *)reg     [(DATAWIDTH-1):0]   Q           ;

reg                         SirDackL1 ='d0  ;

/**************************************************************************************************/
always @ (posedge Clk )
begin
    if ((SirSel == 1'b1) && (SirAddr == REGADDRESS))
       SirDack <= #`UDLY 1'b1;
    else
       SirDack <= #`UDLY 1'b0;
end       

always @ (posedge Clk )
begin
       SirDackL1 <= #`UDLY SirDack;
end       

always @ (posedge Clk or posedge Rst)
begin
    if (Rst == 1'b1)
       Q <= ININTVALUE;
    else if ((SirSel == 1'b1) && (SirAddr == REGADDRESS) && (SirRead == 1'b0))
//    else if ((SirDack == 1'b1) && (SirDackL1 == 1'b0) && (SirRead == 1'b0))
       Q <= #`UDLY SirWdat;
    else;
end       


always @ (posedge Clk )
begin
    if((SirAddr == REGADDRESS) && (SirRead == 1'b1))
    	SirRdat <= Q;
    else
    	SirRdat <= {DATAWIDTH{1'b0}};
end


//assign SirRdat = ((SirSel == 1'b1) && (SirAddr == REGADDRESS) && (SirRead == 1'b1)) ? Q : {DATAWIDTH{1'b0}};



endmodule