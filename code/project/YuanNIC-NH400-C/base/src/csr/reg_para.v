// 2006/02/24    john.wang         1.0                Original
//
// ***************************************************************************************
// DEFINE
//  
//                                                  
// ***************************************************************************************
//
// Module       :    reg_para
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

module reg_para(
                Clk         ,
                Rst         ,

                SirSel      ,
                SirRead     ,
                SirAddr     ,
                SirDack     ,
                SirRdat     
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

/**************************************************************************************************/
wire                        Clk         ;
wire                        Rst         ;
                            
wire                        SirSel      ;
wire                        SirRead     ;
wire    [(ADDRWIDTH-1):0]   SirAddr     ;
reg                         SirDack     ;
reg     [(DATAWIDTH-1):0]   SirRdat     ;

/**************************************************************************************************/

always @ (posedge Clk or posedge Rst)
begin
    if (Rst == 1'b1)
       SirDack <= 1'b0;
    else if ((SirSel == 1'b1) && (SirAddr == REGADDRESS))
       SirDack <= #`UDLY 1'b1;
    else
       SirDack <= #`UDLY 1'b0;
end       

always @ (posedge Clk or posedge Rst)
begin
    if (Rst == 1'b1)
    	SirRdat <= {DATAWIDTH{1'b0}};
    else if((SirAddr == REGADDRESS) && (SirRead == 1'b1))
    	SirRdat <= ININTVALUE;
    else
    	SirRdat <= {DATAWIDTH{1'b0}};
end

//assign SirRdat = ((SirSel == 1'b1) && (SirAddr == REGADDRESS) && (SirRead == 1'b1)) ? ININTVALUE : 'b0;



endmodule