// 2006/02/24    john.wang         1.0                Original
//
// ***************************************************************************************
// DEFINE
//  
//                                                  
// ***************************************************************************************
//
// Module       :    reg_ro
// Called by    :    
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

module reg_ro(
                Clk         ,
                Rst         ,

                SirSel      ,
                SirRead     ,
                SirAddr     ,
                SirDack     ,
                SirRdat     ,

                Load        ,
                D        
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
output                      SirDack     ;
output  [(DATAWIDTH-1):0]   SirRdat     ;

input                       Load        ;
input   [(DATAWIDTH-1):0]   D           ;

/**************************************************************************************************/
wire                        Clk         ;
wire                        Rst         ;
                            
wire                        SirSel      ;
wire                        SirRead     ;
wire    [(ADDRWIDTH-1):0]   SirAddr     ;
reg                         SirDack ='d0;
reg	    [(DATAWIDTH-1):0]   SirRdat ='d0;

wire                        Load        ;
wire    [(DATAWIDTH-1):0]   D           ;
reg     [(DATAWIDTH-1):0]   Q       ='d0;

/**************************************************************************************************/
always @ (posedge Clk )
begin
    if (Load == 1'b1)
       Q <= #`UDLY D;
    else;
end       

always @ (posedge Clk )
begin
    if ((SirSel == 1'b1) && (SirAddr == REGADDRESS))
       SirDack <= #`UDLY 1'b1;
    else
       SirDack <= #`UDLY 1'b0;
end       

always @ (posedge Clk )
begin
    if((SirAddr == REGADDRESS) && (SirRead == 1'b1))
    	SirRdat <= Q;
    else
    	SirRdat <= {DATAWIDTH{1'b0}};
end



//assign SirRdat = ((SirSel == 1'b1) && (SirAddr == REGADDRESS) && (SirRead == 1'b1)) ? Q :{DATAWIDTH{1'b0}};



endmodule