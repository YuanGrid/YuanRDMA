
`include "../top/global_define.vh"

module csr40_pm  (
                Clk                 ,
                Rst                 ,
                                    
                SirAddr             ,
                SirRead             ,
                SirWdat             ,
                                    
                SirSel              ,
                SirDack             ,
                SirRdat             ,
				
				i2c_m_cpld_sel		,
				i2c_m_cpld_rw		,
				i2c_m_cpld_dlen		,
				i2c_m_cpld_mode		,
				i2c_m_cpld_addr		,
				i2c_m_cpld_dev_id	,
				i2c_m_cpld_data		,
				i2c_m_cpld_rdata	,
//				i2c_m_cpld_done		,
				i2c_m_cpld_ack
				
               );
                
parameter       SLAVE_SIZE  = 16;
                                            
input   wire                        Clk                 ;
input   wire                        Rst                 ;
                                                        
input   wire    [(SLAVE_SIZE-1):0]  SirAddr             ;
input   wire                        SirRead             ;
input   wire    [31:0]              SirWdat             ;
                                                        
input   wire                        SirSel              ;
output   reg                        SirDack             ;
output   reg    [31:0]              SirRdat             ;

output	wire						i2c_m_cpld_sel		;
output	wire						i2c_m_cpld_rw		;
output	wire	[4:0]				i2c_m_cpld_dlen		;
output	wire	[2:0]				i2c_m_cpld_mode		;
output	wire	[31:0]				i2c_m_cpld_addr		;
output	wire	[6:0]				i2c_m_cpld_dev_id	;
output	wire	[127:0]				i2c_m_cpld_data		;
input	wire	[127:0]				i2c_m_cpld_rdata	;
//input	wire						i2c_m_cpld_done		;
input	wire						i2c_m_cpld_ack		;

/********************************************************************\
*                                                                    *
*               Metastability harder for SirSelx                     *
*                                                                    *
\********************************************************************/

wire 			    SirSelh;
   
assign SirSelh = SirSel;

reg 				i2c_m_cpld_done;

always @(posedge Clk or posedge Rst)
begin
	if(Rst)
		i2c_m_cpld_done <= 1'b1;
	else if(i2c_m_cpld_sel)
		i2c_m_cpld_done <= 1'b0;
	else if(i2c_m_cpld_ack)
		i2c_m_cpld_done <= 1'b1;
	else;
end

/********************************************************************\
*                                                                    *
*               Adress : 16'h0000                                    *
*               Content: {i2c_m_cpld_sel,i2c_m_cpld_rw,i2c_m_cpld_mode}        	     *
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
wire    [30:0]  SirRdat0000r1   ;
wire    [30:0]  Q0000r1         ;

wire            SirDack0000r2   ;
wire      		SirRdat0000r2   ;
wire      		Q0000r2         ;
wire    		D0000r2         ;
wire            Load0000r2      ;

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

assign Clr0000r0  		= i2c_m_cpld_ack ;
assign i2c_m_cpld_sel   = Q0000r0;

reg_rw   U_ADDR0000_r1(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirWdat    ({SirWdat[30:24],16'h1,SirWdat[7:0]}),
                .SirDack    (SirDack0000r1      ),
                .SirRdat    (SirRdat0000r1      ),

                .Q          (Q0000r1            )
                );
defparam
U_ADDR0000_r1.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0000_r1.DATAWIDTH   = 31,
U_ADDR0000_r1.ININTVALUE  = {1'b1,30'h0},
U_ADDR0000_r1.REGADDRESS  = ADDR0000;

assign i2c_m_cpld_rw 		= Q0000r1[30];
assign i2c_m_cpld_mode[2] 	= Q0000r1[0];

reg_ro  U_ADDR0000_r2(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirDack    (SirDack0000r2      ),
                .SirRdat    (SirRdat0000r2      ),
                                            
                .Load       (Load0000r2         ),
                .D          (D0000r2			)
                );
defparam
U_ADDR0000_r2.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0000_r2.DATAWIDTH   = 1,
U_ADDR0000_r2.ININTVALUE  = 1'h0,
U_ADDR0000_r2.REGADDRESS  = ADDR0000;

assign Load0000r2 = 1'b1 ;//read
assign D0000r2    = i2c_m_cpld_done;

assign SirDack0000       = SirDack0000r0 | SirDack0000r2;
assign SirRdat0000[31:0] = {SirRdat0000r0,SirRdat0000r1[30:24],SirRdat0000r2,SirRdat0000r1[22:0]};

/********************************************************************\
*                                                                    *
*               Adress : 16'h0004                                    *
*               Content: i2c_m_cpld_addr		                     *
*                                                                    *
\********************************************************************/
parameter       ADDR0004   = 16'h0004  ;

wire            SirDack0004     ;
wire    [31:0]  SirRdat0004     ;

wire            SirDack0004r0   ;
wire    [31:0]  SirRdat0004r0   ;
wire    [31:0]  Q0004r0         ;

reg_rw   U_ADDR0004_r0(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirWdat    (SirWdat[31:0]      ),
                .SirDack    (SirDack0004r0      ),
                .SirRdat    (SirRdat0004r0      ),

                .Q          (Q0004r0[31:0]      )
                );
defparam
U_ADDR0004_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0004_r0.DATAWIDTH   = 32,
U_ADDR0004_r0.ININTVALUE  = 32'h0,
U_ADDR0004_r0.REGADDRESS  = ADDR0004;

assign i2c_m_cpld_mode[1:0] = Q0004r0[31:30];
assign i2c_m_cpld_addr 		= Q0004r0[31:0];

assign SirDack0004 = SirDack0004r0;
assign SirRdat0004[31:0] = {SirRdat0004r0[31:0]};


/********************************************************************\
*                                                                    *
*               Adress : 16'h0008                                    *
*               Content: i2c_m_cpld_dlen	                     *
*                                                                    *
\********************************************************************/
parameter       ADDR0008   = 16'h0008  ;

wire            SirDack0008     ;
wire    [31:0]  SirRdat0008     ;

wire            SirDack0008r0   ;
wire    [31:0]  SirRdat0008r0   ;
wire    [31:0]  Q0008r0         ;

reg_rw   U_ADDR0008_r0(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirWdat    (SirWdat[31:0]      ),
                .SirDack    (SirDack0008r0      ),
                .SirRdat    (SirRdat0008r0      ),

                .Q          (Q0008r0[31:0]      )
                );
defparam
U_ADDR0008_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0008_r0.DATAWIDTH   = 32,
U_ADDR0008_r0.ININTVALUE  = 32'h0,
U_ADDR0008_r0.REGADDRESS  = ADDR0008;

assign i2c_m_cpld_dlen[4:0] = Q0008r0[4:0];

assign SirDack0008 = SirDack0008r0;
assign SirRdat0008[31:0] = SirRdat0008r0[31:0];


/********************************************************************\
*                                                                    *
*               Adress : 16'h000c                                    *
*               Content: {i2c_m_cpld_data[31:0]/i2c_m_cpld_rdata[31:0]}*
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
U_ADDR000c_r0w.ININTVALUE  = 32'h0,
U_ADDR000c_r0w.REGADDRESS  = ADDR000c;

assign i2c_m_cpld_data[31:0] = Q000cr0[31:0];

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
U_ADDR000c_r0r.ININTVALUE  = 32'h0,
U_ADDR000c_r0r.REGADDRESS  = ADDR000c;

assign Load000cr0 = 1'b1 ;//read
assign D000cr0[31:0] = i2c_m_cpld_rw ? i2c_m_cpld_rdata[31:0] : i2c_m_cpld_data[31:0];

assign SirDack000c = SirDack000cr0;
assign SirRdat000c[31:0] = SirRdat000cr0[31:0];

/********************************************************************\
*                                                                    *
*               Adress : 16'h0010                                    *
*               Content: i2c_m_cpld_dev_id                           *
*                                                                    *
\********************************************************************/
parameter       ADDR0010   = 16'h0010  ;

wire            SirDack0010     ;
wire    [31:0]  SirRdat0010     ;

wire            SirDack0010r0   ;
wire    [6:0]   SirRdat0010r0   ;
wire    [6:0]   Q0010r0         ;

reg_rw   U_ADDR0010_r0(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirWdat    (SirWdat[6:0]       ),
                .SirDack    (SirDack0010r0      ),
                .SirRdat    (SirRdat0010r0      ),

                .Q          (Q0010r0[6:0]       )
                );
defparam
U_ADDR0010_r0.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0010_r0.DATAWIDTH   = 7,
U_ADDR0010_r0.ININTVALUE  = 7'h0,
U_ADDR0010_r0.REGADDRESS  = ADDR0010;

assign i2c_m_cpld_dev_id = Q0010r0[6:0];

assign SirDack0010 = SirDack0010r0;
assign SirRdat0010[31:0] = {25'h0,SirRdat0010r0[6:0]};

/********************************************************************\
*                                                                    *
*               Adress : 16'h0014                                    *
*               Content: i2c_m_cpld_data/rdata[63:32]                *
*                                                                    *
\********************************************************************/
parameter       ADDR0014   = 16'h0014  ;

wire            SirDack0014     ;
wire    [31:0]  SirRdat0014     ;
                                
wire            SirDack0014r0   ;
wire    [31:0]  SirRdat0014r0   ;
wire    [31:0]  Q0014r0         ;
wire            Load0014r0      ;
wire    [31:0]  D0014r0         ;

reg_rw   U_ADDR0014_r0w(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirWdat    (SirWdat[31:0]      ),
                .SirDack    (                   ),
                .SirRdat    (                   ),

                .Q          (Q0014r0[31:0]      )
                );
defparam
U_ADDR0014_r0w.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0014_r0w.DATAWIDTH   = 32,
U_ADDR0014_r0w.ININTVALUE  = 32'h0,
U_ADDR0014_r0w.REGADDRESS  = ADDR0014;

assign i2c_m_cpld_data[63:32] = Q0014r0[31:0];

reg_ro  U_ADDR0014_r0r(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirDack    (SirDack0014r0      ),
                .SirRdat    (SirRdat0014r0      ),
                                            
                .Load       (Load0014r0         ),
                .D          (D0014r0[31:0]      )
                );
defparam
U_ADDR0014_r0r.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0014_r0r.DATAWIDTH   = 32,
U_ADDR0014_r0r.ININTVALUE  = 32'h0,
U_ADDR0014_r0r.REGADDRESS  = ADDR0014;

assign Load0014r0 = 1'b1 ;//read
assign D0014r0[31:0] = i2c_m_cpld_rw ? i2c_m_cpld_rdata[63:32] : i2c_m_cpld_data[63:32];

assign SirDack0014 = SirDack0014r0;
assign SirRdat0014[31:0] = SirRdat0014r0[31:0];
/********************************************************************\
*                                                                    *
*               Adress : 16'h0018                                    *
*               Content: i2c_m_cpld_data/rdata[95:64]				*
*                                                                    *
\********************************************************************/ 
parameter       ADDR0018   = 16'h0018  ;

wire            SirDack0018     ;
wire    [31:0]  SirRdat0018     ;
                                
wire            SirDack0018r0   ;
wire    [31:0]  SirRdat0018r0   ;
wire    [31:0]  Q0018r0         ;
wire            Load0018r0      ;
wire    [31:0]  D0018r0         ;

reg_rw   U_ADDR0018_r0w(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirWdat    (SirWdat[31:0]      ),
                .SirDack    (                   ),
                .SirRdat    (                   ),

                .Q          (Q0018r0[31:0]      )
                );
defparam
U_ADDR0018_r0w.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0018_r0w.DATAWIDTH   = 32,
U_ADDR0018_r0w.ININTVALUE  = 32'h0,
U_ADDR0018_r0w.REGADDRESS  = ADDR0018;

assign i2c_m_cpld_data[95:64] = Q0018r0[31:0];

reg_ro  U_ADDR0018_r0r(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirDack    (SirDack0018r0      ),
                .SirRdat    (SirRdat0018r0      ),
                                            
                .Load       (Load0018r0         ),
                .D          (D0018r0[31:0]      )
                );
defparam
U_ADDR0018_r0r.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR0018_r0r.DATAWIDTH   = 32,
U_ADDR0018_r0r.ININTVALUE  = 32'h0,
U_ADDR0018_r0r.REGADDRESS  = ADDR0018;

assign Load0018r0 = 1'b1 ;//read
assign D0018r0[31:0] = i2c_m_cpld_rw ? i2c_m_cpld_rdata[95:64] : i2c_m_cpld_data[95:64];

assign SirDack0018 = SirDack0018r0;
assign SirRdat0018[31:0] = SirRdat0018r0[31:0];
/********************************************************************\
*                                                                    *
*               Adress : 16'h001c                                    *
*               Content: i2c_m_cpld_data/rdata[127:96]				 *
*                                                                    *
\********************************************************************/
parameter       ADDR001c   = 16'h001c  ;

wire            SirDack001c     ;
wire    [31:0]  SirRdat001c     ;
                                
wire            SirDack001cr0   ;
wire    [31:0]  SirRdat001cr0   ;
wire    [31:0]  Q001cr0         ;
wire            Load001cr0      ;
wire    [31:0]  D001cr0         ;

reg_rw   U_ADDR001c_r0w(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirWdat    (SirWdat[31:0]      ),
                .SirDack    (                   ),
                .SirRdat    (                   ),

                .Q          (Q001cr0[31:0]      )
                );
defparam
U_ADDR001c_r0w.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR001c_r0w.DATAWIDTH   = 32,
U_ADDR001c_r0w.ININTVALUE  = 32'h0,
U_ADDR001c_r0w.REGADDRESS  = ADDR001c;

assign i2c_m_cpld_data[127:96] = Q001cr0[31:0];

reg_ro  U_ADDR001c_r0r(
                .Clk        (Clk                ),
                .Rst        (Rst                ),
                                                
                .SirSel     (SirSel             ),
                .SirRead    (SirRead            ),
                .SirAddr    (SirAddr            ),
                .SirDack    (SirDack001cr0      ),
                .SirRdat    (SirRdat001cr0      ),
                                            
                .Load       (Load001cr0         ),
                .D          (D001cr0[31:0]      )
                );
defparam
U_ADDR001c_r0r.ADDRWIDTH   = SLAVE_SIZE,
U_ADDR001c_r0r.DATAWIDTH   = 32,
U_ADDR001c_r0r.ININTVALUE  = 32'h0,
U_ADDR001c_r0r.REGADDRESS  = ADDR001c;

assign Load001cr0 = 1'b1 ;//read
assign D001cr0[31:0] = i2c_m_cpld_rw ? i2c_m_cpld_rdata[127:96] : i2c_m_cpld_data[127:96];

assign SirDack001c = SirDack001cr0;
assign SirRdat001c[31:0] = SirRdat001cr0[31:0];

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
        SirDack <= #`UDLY  SirDack0000 | SirDack0004 | SirDack0008 | SirDack000c |
						   SirDack0010 | SirDack0014 | SirDack0018 | SirDack001c 
						 ;
end       


always @ (posedge Clk or posedge Rst)
begin
    if (Rst == 1'b1)
        SirRdat <= 1'b0;
    else
        SirRdat <= #`UDLY SirRdat0000 | SirRdat0004 | SirRdat0008 | SirRdat000c |
						  SirRdat0010 | SirRdat0014 | SirRdat0018 | SirRdat001c 
						 ;
end  

endmodule