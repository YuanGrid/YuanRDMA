// 2009/09/21      zhangjun      1.0             Original
//
// ***************************************************************************************
// DEFINE
//  
//                                                  
// ***************************************************************************************
//
// Module       :    csr0f_pm
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

module csr0f_pm  (
                Clk                     ,
                Rst                     ,
                                        
                SirAddr                 ,
                SirRead                 ,
                SirWdat                 ,
                                        
                SirSel                  ,
                SirDack                 ,
                SirRdat                 ,

                IbusStatSel             ,
                IbusStatRead            ,
                IbusStatAddr            ,
                IbusStatWdat            ,
                IbusStatRdat            ,
                IbusStatDack            ,
                StatClrReq              ,
                StatClrOver             
             );
             
             
parameter       SLAVE_SIZE  = 16 ;
                                            
input   wire                       Clk             ;
input   wire                       Rst             ;
                                         
input   wire   [(SLAVE_SIZE-1):0]  SirAddr         ;
input   wire                       SirRead         ;
input   wire   [31:0]              SirWdat         ;
                                             
input   wire                       SirSel          ;
output  reg                        SirDack         ;
output  reg    [31:0]              SirRdat         ;   
             
output  wire                       IbusStatSel     ;
output  wire                       IbusStatRead    ;
output  wire   [12:0]              IbusStatAddr    ;
output  wire   [63:0]              IbusStatWdat    ;
input   wire   [63:0]              IbusStatRdat    ;
input   wire                       IbusStatDack    ;
output  wire                       StatClrReq      ;
input   wire                       StatClrOver     ;

/********************************************************************\
*                                                                    *
*               Metastability harder for SirSelx                     *
*                                                                    *
\********************************************************************/
             
/********************************************************************\
*                                                                    *
*               Adress : 16'h0000                                    *
*               Content: {StatOpReq,StatOpcode,30'h0}        		 *
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
wire            SirRdat0000r1   ;
wire            Q0000r1         ;

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

assign Clr0000r0  = IbusStatDack;
assign IbusStatSel = Q0000r0;

reg_rw   U_ADDR0000_r1(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirWdat    (SirWdat[30]        ),
                .SirDack    (SirDack0000r1      ),
                .SirRdat    (SirRdat0000r1      ),

                .Q          (Q0000r1            )
                );
defparam
U_ADDR0000_r1.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0000_r1.DATAWIDTH   = 1,
U_ADDR0000_r1.ININTVALUE  = 1'b0,
U_ADDR0000_r1.REGADDRESS  = ADDR0000;

assign IbusStatRead = Q0000r1;

assign SirDack0000       = SirDack0000r0;
assign SirRdat0000[31:0] = {SirRdat0000r0,SirRdat0000r1,30'h0};

/********************************************************************\
*                                                                    *
*               Adress : 16'h0004                                    *
*               Content: {19'h00_0000,StatAddr[12:0]}                *
*                                                                    *
\********************************************************************/
parameter       ADDR0004   = 16'h0004  ;

wire            SirDack0004     ;
wire    [31:0]  SirRdat0004     ;

wire            SirDack0004r0   ;
wire    [12:0]  SirRdat0004r0   ;
wire    [12:0]  Q0004r0         ;

reg_rw   U_ADDR0004_r0(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirWdat    (SirWdat[12:0]      ),
                .SirDack    (SirDack0004r0      ),
                .SirRdat    (SirRdat0004r0      ),

                .Q          (Q0004r0[12:0]      )
                );
defparam
U_ADDR0004_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0004_r0.DATAWIDTH   = 13,
U_ADDR0004_r0.ININTVALUE  = 13'h0000,
U_ADDR0004_r0.REGADDRESS  = ADDR0004;

assign IbusStatAddr[12:0] = Q0004r0[12:0];

assign SirDack0004 = SirDack0004r0;
assign SirRdat0004[31:0] = {19'h00_0000,SirRdat0004r0[12:0]};

/********************************************************************\
*                                                                    *
*               Adress : 16'h0008                                    *
*               Content: StatWdat[31:0]/StatRdat[31:0]               *
*                                                                    *
\********************************************************************/
parameter       ADDR0008   = 16'h0008  ;

wire            SirDack0008     ;
wire    [31:0]  SirRdat0008     ;
                                
wire            SirDack0008r0   ;
wire    [31:0]  SirRdat0008r0   ;
wire    [31:0]  Q0008r0         ;
wire            Load0008r0      ;
wire    [31:0]  D0008r0         ;

reg_rw   U_ADDR0008_r0w(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirWdat    (SirWdat[31:0]      ),
                .SirDack    (                   ),
                .SirRdat    (                   ),

                .Q          (Q0008r0[31:0]      )
                );
defparam
U_ADDR0008_r0w.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0008_r0w.DATAWIDTH   = 32,
U_ADDR0008_r0w.ININTVALUE  = 32'h0000_0000,
U_ADDR0008_r0w.REGADDRESS  = ADDR0008;

assign IbusStatWdat[31:0] = Q0008r0[31:0];

reg_ro  U_ADDR0008_r0r(
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
U_ADDR0008_r0r.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0008_r0r.DATAWIDTH   = 32,
U_ADDR0008_r0r.ININTVALUE  = 32'h0000_0000,
U_ADDR0008_r0r.REGADDRESS  = ADDR0008;

assign Load0008r0 = IbusStatRead & IbusStatDack;
assign D0008r0[31:0] = IbusStatRdat[31:0];

assign SirDack0008 = SirDack0008r0;
assign SirRdat0008[31:0] = SirRdat0008r0[31:0];

/********************************************************************\
*                                                                    *
*               Adress : 16'h000c                                    *
*               Content: DmaWdat[63:32]/DmaRdat[63:32]               *
*                                                                    *
\********************************************************************/
parameter       ADDR000c   = 16'h000c  ;

wire            SirDack000c     ;
wire    [31:0]  SirRdat000c     ;
                                
wire            SirDack000cr0   ;
wire    [31:0]  SirRdat000cr0   ;
wire    [31:0]  Q000cr0         ;
wire            Load000cr0      ;
wire    [31:0]  D000cr0         ;

reg_rw   U_ADDR000c_r0w(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirWdat    (SirWdat[31:0]      ),
                .SirDack    (                   ),
                .SirRdat    (                   ),

                .Q          (Q000cr0[31:0]      )
                );
defparam
U_ADDR000c_r0w.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR000c_r0w.DATAWIDTH   = 32,
U_ADDR000c_r0w.ININTVALUE  = 32'h0000_0000,
U_ADDR000c_r0w.REGADDRESS  = ADDR000c;

assign IbusStatWdat[63:32] = Q000cr0[31:0];

reg_ro  U_ADDR000c_r0r(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirDack    (SirDack000cr0      ),
                .SirRdat    (SirRdat000cr0      ),
                                            
                .Load       (Load000cr0         ),
                .D          (D000cr0[31:0]      )
                );
defparam
U_ADDR000c_r0r.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR000c_r0r.DATAWIDTH   = 32,
U_ADDR000c_r0r.ININTVALUE  = 32'h0000_0000,
U_ADDR000c_r0r.REGADDRESS  = ADDR000c;

assign Load000cr0 = IbusStatRead & IbusStatDack;
assign D000cr0[31:0] = IbusStatRdat[63:32];

assign SirDack000c = SirDack000cr0;
assign SirRdat000c[31:0] = SirRdat000cr0[31:0];

/********************************************************************\
*                                                                    *
*               Adress : 16'h0010                                    *
*               Content: {StatClrReq,31'h0000_0000}                  *
*                                                                    *
\********************************************************************/
parameter       ADDR0010   = 16'h0010  ;

wire            SirDack0010     ;
wire    [31:0]  SirRdat0010     ;

wire            SirDack0010r0   ;
wire            SirRdat0010r0   ;
wire            Clr0010r0       ;
wire            Q0010r0         ;

reg_rwsc  U_ADDR0010_r0(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirWdat    (SirWdat[31]        ),
                .SirDack    (SirDack0010r0      ),
                .SirRdat    (SirRdat0010r0      ),

                .Clr        (Clr0010r0          ),
                .Q          (Q0010r0            )
                );
defparam
U_ADDR0010_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0010_r0.DATAWIDTH   = 1,
U_ADDR0010_r0.ININTVALUE  = 1'h0, 
U_ADDR0010_r0.REGADDRESS  = ADDR0010;

assign Clr0010r0  = StatClrOver;
assign StatClrReq = Q0010r0;

assign SirDack0010       = SirDack0010r0;
assign SirRdat0010[31:0] = {SirRdat0010r0,31'h0000_0000};


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
        SirDack <= #`UDLY SirDack0000 | SirDack0004 | SirDack0008 | SirDack000c |
                          SirDack0010 
                          ;
end

always @ (posedge Clk)
begin
        SirRdat <= #`UDLY SirRdat0000 | SirRdat0004 | SirRdat0008 | SirRdat000c |
                          SirRdat0010 
                          ;
end


endmodule





