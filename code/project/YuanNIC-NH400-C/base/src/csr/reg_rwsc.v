// 2006/02/24    john.wang         1.0                Original
//
// ***************************************************************************************
// DEFINE
//  
//                                                  
// ***************************************************************************************
//
// Module       :    reg_rwsc
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

module reg_rwsc(
                Clk         ,
                Rst         ,

                SirSel      ,
                SirRead     ,
                SirAddr     ,
                SirWdat     ,
                SirDack     ,
                SirRdat     ,

                Clr         ,
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

input                       Clr         ;
output  [(DATAWIDTH-1):0]   Q           ;

/**************************************************************************************************/
wire                        Clk         ;
wire                        Rst         ;
                            
wire                        SirSel      ;
wire                        SirRead     ;
wire    [(ADDRWIDTH-1):0]   SirAddr     ;
wire    [(DATAWIDTH-1):0]   SirWdat     ;
reg                         SirDack ='d0;
reg     [(DATAWIDTH-1):0]   SirRdat ='d0;

wire                        Clr         ;
reg     [(DATAWIDTH-1):0]   Q           ;

reg                         SirDackL1='d0;

wire                        SirSelh     ;
reg                         SirSel1     ;
reg                         SirSel2     ;

/**************************************************************************************************/
always @ (posedge Clk or posedge Rst)
begin
	if(Rst)
		begin
		SirSel1 <= 1'b0;
		SirSel2 <= 1'b0;
		end
	else
		begin
		SirSel1 <= SirSel;
		SirSel2 <= SirSel1;
		end
end

assign	SirSelh = SirSel1 & (~SirSel2);

always @ (posedge Clk )
begin
    if ((SirSel == 1'b1) && (SirAddr == REGADDRESS))
       SirDack <= #`UDLY 1'b1;
    else
       SirDack <= #`UDLY 1'b0;
end       

always @ (posedge Clk)
begin
       SirDackL1 <= #`UDLY SirDack;
end       

always @ (posedge Clk or posedge Rst)
begin
    if (Rst == 1'b1)
       Q <= ININTVALUE;
//    else if ((SirSel == 1'b1) && (SirAddr == REGADDRESS) && (SirRead == 1'b0))
    else if (Clr == 1'b1)
       Q <= #`UDLY ININTVALUE;
    else if ((SirSel == 1'b1) && (SirAddr == REGADDRESS) && (SirRead == 1'b0))
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