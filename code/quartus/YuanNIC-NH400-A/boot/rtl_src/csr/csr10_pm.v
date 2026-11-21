
`include "../top/global_define.vh"
`include "../top/build_info.v"

module csr10_pm  (
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
U_ADDR0000_r0.ININTVALUE  = {`VER,`REV,`SUBVER},    
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
U_ADDR0004_r0.ININTVALUE  = {`VER_TYPE,`BUILD},
U_ADDR0004_r0.REGADDRESS  = ADDR0004;

assign SirDack0004 = SirDack0004r0;
assign SirRdat0004[31:0] = SirRdat0004r0[31:0];

/********************************************************************\
*                                                                    *
*               Adress : 16'h0008                                    *
*               Content: {YEAR[15:0],MON[7:0],DATE[7:0]}             *
*                                                                    *
\********************************************************************/
parameter       ADDR0008 = 16'h0008;

wire            SirDack0008     ;
wire    [31:0]  SirRdat0008     ;

wire            SirDack0008r0   ;      
wire    [31:0]  SirRdat0008r0   ;

reg_para  U_ADDR0008_r0(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel            ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirDack    (SirDack0008r0      ),
                .SirRdat    (SirRdat0008r0      )
                );
defparam
U_ADDR0008_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0008_r0.DATAWIDTH   = 32,
U_ADDR0008_r0.ININTVALUE  = {`YEAR,`MON,`DATE},    
U_ADDR0008_r0.REGADDRESS  = ADDR0008;

assign SirDack0008 = SirDack0008r0;
assign SirRdat0008[31:0] = SirRdat0008r0[31:0];

/********************************************************************\
*                                                                    *
*               Adress : 16'h000c                                    *
*               Content: {CHIPNUM[31:0]}                             *
*                                                                    *
\********************************************************************/
parameter       ADDR000c = 16'h000c;

wire            SirDack000c     ;
wire    [31:0]  SirRdat000c     ;

wire            SirDack000cr0   ;      
wire    [31:0]  SirRdat000cr0   ;

reg_para  U_ADDR000c_r0(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel            ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirDack    (SirDack000cr0      ),
                .SirRdat    (SirRdat000cr0      )
                );
defparam
U_ADDR000c_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR000c_r0.DATAWIDTH   = 32,
U_ADDR000c_r0.ININTVALUE  = {`DMA_MODE,`PRODUCT_TYPE,`PRODUCT_ID},    
U_ADDR000c_r0.REGADDRESS  = ADDR000c;

assign SirDack000c = SirDack000cr0;
assign SirRdat000c[31:0] = SirRdat000cr0[31:0];

/********************************************************************\
*                                                                    *
*               Adress : 16'h0010                                    *
*               Content: {BD_TYPE[31:0]}                             *
*                                                                    *
\********************************************************************/
parameter       ADDR0010 = 16'h0010;

wire            SirDack0010     ;
wire    [31:0]  SirRdat0010     ;

wire            SirDack0010r0   ;      
wire    [31:0]  SirRdat0010r0   ;

reg_para  U_ADDR0010_r0(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel            ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirDack    (SirDack0010r0      ),
                .SirRdat    (SirRdat0010r0      )
                );
defparam
U_ADDR0010_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0010_r0.DATAWIDTH   = 32,
U_ADDR0010_r0.ININTVALUE  = `BD_TYPE,    
U_ADDR0010_r0.REGADDRESS  = ADDR0010;

assign SirDack0010 = SirDack0010r0;
assign SirRdat0010[31:0] = SirRdat0010r0[31:0];

/********************************************************************\
*                                                                    *
*               Adress : 16'h0014                                    *
*               Content: {BOM_VERSION[3:0],PCB_VERSION[3:0]}         *
*                                                                    *
\********************************************************************/
parameter       ADDR0014 = 16'h0014;

wire            SirDack0014     ;
wire    [31:0]  SirRdat0014     ;

wire            SirDack0014r0   ;      
wire    [7:0]  	SirRdat0014r0   ;

reg_para  U_ADDR0014_r0(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel            ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirDack    (SirDack0014r0      ),
                .SirRdat    (SirRdat0014r0      )
                );
defparam
U_ADDR0014_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0014_r0.DATAWIDTH   = 8,
U_ADDR0014_r0.ININTVALUE  = {`BOM_VERSION,`PCB_VERSION},    
U_ADDR0014_r0.REGADDRESS  = ADDR0014;

assign SirDack0014 = SirDack0014r0;
assign SirRdat0014[31:0] = {24'h0,SirRdat0014r0[7:0]};

/********************************************************************\
*                                                                    *
*               Adress : 16'h0020                                    *
*               Content: {DDR_PRESENT[31:0]}                             *
*                                                                    *
\********************************************************************/
parameter       ADDR0020 = 16'h0020;

wire            SirDack0020     ;
wire    [31:0]  SirRdat0020     ;

wire            SirDack0020r0   ;      
wire    [31:0]  SirRdat0020r0   ;

reg_para  U_ADDR0020_r0(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel            ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirDack    (SirDack0020r0      ),
                .SirRdat    (SirRdat0020r0      )
                );
defparam
U_ADDR0020_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0020_r0.DATAWIDTH   = 32,
U_ADDR0020_r0.ININTVALUE  = `DDR_PRESENT,    
U_ADDR0020_r0.REGADDRESS  = ADDR0020;

assign SirDack0020 = SirDack0020r0;
assign SirRdat0020[31:0] = SirRdat0020r0[31:0];

/********************************************************************\
*                                                                    *
*               Adress : 16'h0024                                    *
*               Content: {ETH_PRESENT[31:0]}                             *
*                                                                    *
\********************************************************************/
parameter       ADDR0024 = 16'h0024;

wire            SirDack0024     ;
wire    [31:0]  SirRdat0024     ;

wire            SirDack0024r0   ;      
wire    [31:0]  SirRdat0024r0   ;

reg_para  U_ADDR0024_r0(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel            ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirDack    (SirDack0024r0      ),
                .SirRdat    (SirRdat0024r0      )
                );
defparam
U_ADDR0024_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0024_r0.DATAWIDTH   = 32,
U_ADDR0024_r0.ININTVALUE  = `ETH_PRESENT,    
U_ADDR0024_r0.REGADDRESS  = ADDR0024;

assign SirDack0024 = SirDack0024r0;
assign SirRdat0024[31:0] = SirRdat0024r0[31:0];

/********************************************************************\
*                                                                    *
*               Adress : 16'h0028                                    *
*               Content: {DDR_CH_NUM[7:0],HW_PORT_NUM[7:0]}         *
*                                                                    *
\********************************************************************/
parameter       ADDR0028 = 16'h0028;

wire            SirDack0028     ;
wire    [31:0]  SirRdat0028     ;

wire            SirDack0028r0   ;      
wire    [15:0] 	SirRdat0028r0   ;

reg_para  U_ADDR0028_r0(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel            ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirDack    (SirDack0028r0      ),
                .SirRdat    (SirRdat0028r0      )
                );
defparam
U_ADDR0028_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0028_r0.DATAWIDTH   = 16,
U_ADDR0028_r0.ININTVALUE  = {`DDR_CH_NUM,`HW_PORT_NUM},    
U_ADDR0028_r0.REGADDRESS  = ADDR0028;

assign SirDack0028 = SirDack0028r0;
assign SirRdat0028[31:0] = {16'h0,SirRdat0028r0[15:0]};

/********************************************************************\
*                                                                    *
*               Adress : 16'h0100                                    *
*               Content: {PCIE_PORT_NUM[3:0]     					 *
*                                                                    *
\********************************************************************/
parameter       ADDR0100 = 16'h0100;

wire            SirDack0100     ;
wire    [31:0]  SirRdat0100     ;

wire            SirDack0100r0   ;      
wire    [3:0] 	SirRdat0100r0   ;

reg_para  U_ADDR0100_r0(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel            ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirDack    (SirDack0100r0      ),
                .SirRdat    (SirRdat0100r0      )
                );
defparam
U_ADDR0100_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0100_r0.DATAWIDTH   = 4,
U_ADDR0100_r0.ININTVALUE  = `PCIE_PORT_NUM,    
U_ADDR0100_r0.REGADDRESS  = ADDR0100;

assign SirDack0100 = SirDack0100r0;
assign SirRdat0100[31:0] = {28'h0,SirRdat0100r0[3:0]};

/********************************************************************\
*                                                                    *
*               Adress : 16'h0200                                    *
*               Content: {PCIE_PORT0_VENDOR_ID[15:0]     					 *
*                                                                    *
\********************************************************************/
parameter       ADDR0200 = 16'h0200;

wire            SirDack0200     ;
wire    [31:0]  SirRdat0200     ;

wire            SirDack0200r0   ;      
wire    [15:0] 	SirRdat0200r0   ;

reg_para  U_ADDR0200_r0(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel            ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirDack    (SirDack0200r0      ),
                .SirRdat    (SirRdat0200r0      )
                );
defparam
U_ADDR0200_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0200_r0.DATAWIDTH   = 16,
U_ADDR0200_r0.ININTVALUE  = `PCIE_PORT0_VENDOR_ID,    
U_ADDR0200_r0.REGADDRESS  = ADDR0200;

assign SirDack0200 = SirDack0200r0;
assign SirRdat0200[31:0] = {16'h0,SirRdat0200r0[15:0]};

/**********************************************************************************************\
*                                                                    							*
*               Adress : 16'h0204                                    							*
*               Content: {PCIE_PORT0_PF_NUM[7:0],PCIE_PORT0_SPEED[3:0],PCIE_PORT0_LANE[7:0]	 	*
*                                                                    							*
\**********************************************************************************************/
parameter       ADDR0204 = 16'h0204;

wire            SirDack0204     ;
wire    [31:0]  SirRdat0204     ;

wire            SirDack0204r0   ;      
wire    [19:0] 	SirRdat0204r0   ;

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
U_ADDR0204_r0.DATAWIDTH   = 20,
U_ADDR0204_r0.ININTVALUE  = {`PCIE_PORT0_PF_NUM,`PCIE_PORT0_SPEED,`PCIE_PORT0_LANE},    
U_ADDR0204_r0.REGADDRESS  = ADDR0204;

assign SirDack0204 = SirDack0204r0;
assign SirRdat0204[31:0] = {12'h0,SirRdat0204r0[19:0]};

/************************************************************\
*                                                         	*
*               Adress : 16'h0208                          	*
*               Content: {PCIE_PORT0_PF_DMA_EN[15:0]		*
*                                                          	*
\***********************************************************/
parameter       ADDR0208 = 16'h0208;

wire            SirDack0208     ;
wire    [31:0]  SirRdat0208     ;

wire            SirDack0208r0   ;      
wire    [15:0] 	SirRdat0208r0   ;

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
U_ADDR0208_r0.DATAWIDTH   = 16,
U_ADDR0208_r0.ININTVALUE  = {`PCIE_PORT0_PF_DMA_EN},    
U_ADDR0208_r0.REGADDRESS  = ADDR0208;

assign SirDack0208 = SirDack0208r0;
assign SirRdat0208[31:0] = {16'h0,SirRdat0208r0[15:0]};

/************************************************************\
*                                                         	*
*               Adress : 16'h0210                          	*
*               Content: {PORT0_PF0_DEVICE_ID[15:0]		*
*                                                          	*
\***********************************************************/
parameter       ADDR0210 = 16'h0210;

wire            SirDack0210     ;
wire    [31:0]  SirRdat0210     ;

wire            SirDack0210r0   ;      
wire    [15:0] 	SirRdat0210r0   ;

reg_para  U_ADDR0210_r0(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel            ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirDack    (SirDack0210r0      ),
                .SirRdat    (SirRdat0210r0      )
                );
defparam
U_ADDR0210_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0210_r0.DATAWIDTH   = 16,
U_ADDR0210_r0.ININTVALUE  = {`PORT0_PF0_DEVICE_ID},    
U_ADDR0210_r0.REGADDRESS  = ADDR0210;

assign SirDack0210 = SirDack0210r0;
assign SirRdat0210[31:0] = {16'h0,SirRdat0210r0[15:0]};

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
        SirDack <= #`UDLY SirDack0000 | SirDack0004 | SirDack0008 | SirDack000c
                        | SirDack0010 | SirDack0014 
                        | SirDack0020 | SirDack0024 | SirDack0028
						| SirDack0100
						| SirDack0200 | SirDack0204 | SirDack0208
						| SirDack0210
				   ;
end       

always @ (posedge Clk)
begin
        SirRdat <= #`UDLY SirRdat0000 | SirRdat0004 | SirRdat0008 | SirRdat000c
                        | SirRdat0010 | SirRdat0014 
                        | SirRdat0020 | SirRdat0024 | SirRdat0028
						| SirRdat0100
						| SirRdat0200 | SirRdat0204 | SirRdat0208
						| SirRdat0210
						;
end

endmodule
