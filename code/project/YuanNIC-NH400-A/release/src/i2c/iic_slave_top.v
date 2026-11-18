module   iic_slave_top(

				rst			,
				clk			,

				iic_scl		,
				iic_sda		,
				iic_busy	,
				
				ID_CODE		,
				CHIP_ID     ,
				TEMP_LOC0_0 ,
				TEMP_LOC1_0 ,
				TEMP_LOC1_1 ,
				TEMP_LOC2_0 ,
				TEMP_LOC2_1 ,
				TEMP_LOC3_0 ,
				TEMP_LOC3_1 ,
				TEMP_LOC4_0 ,
				TEMP_LOC4_1 ,
				VCC         ,
				VCCIO_SDM   ,
				VCCPT       ,
				VCCRCORE    ,
				VCCH_SDM    ,
				VCCL_SDM    ,
				VCCADC     
);

input	wire            rst			;
input   wire            clk			;
                        
input   wire            iic_scl		;
inout   wire            iic_sda		;
output  wire            iic_busy	;

input	wire	[31:0]	ID_CODE		;
input	wire	[63:0]	CHIP_ID		;
input	wire	[31:0]	TEMP_LOC0_0	;
input	wire	[31:0]	TEMP_LOC1_0	;
input	wire	[31:0]	TEMP_LOC1_1	;
input	wire	[31:0]	TEMP_LOC2_0	;
input	wire	[31:0]	TEMP_LOC2_1	;
input	wire	[31:0]	TEMP_LOC3_0	;
input	wire	[31:0]	TEMP_LOC3_1	;
input	wire	[31:0]	TEMP_LOC4_0	;
input	wire	[31:0]	TEMP_LOC4_1	;
input	wire	[31:0]	VCC			;
input	wire	[31:0]	VCCIO_SDM	;
input	wire	[31:0]	VCCPT		;
input	wire	[31:0]	VCCRCORE	;
input	wire	[31:0]	VCCH_SDM	;
input	wire	[31:0]	VCCL_SDM	;
input	wire	[31:0]	VCCADC		;

////////////////////////////////////////////////

wire				cpld_fpga_i2c_sel	;
wire				cpld_fpga_i2c_read	;
wire	[7:0]		cpld_fpga_i2c_addr	;
wire	[31:0]		cpld_fpga_i2c_wdat	;
reg		[31:0]		cpld_fpga_i2c_rdat	;

reg		[3:0]		BRD_ID	;
reg		[3:0]		BOM_VER	;
reg		[3:0]		PCB_VER	;		
reg		[31:0]		test_dat; 
/////////////////////////////////////////////////
iic_slave    U_i2c_cpld_slave (
    .clk              (clk      	),
    .rst              (rst     		),
                                      
    .iic_scl          (iic_scl  	),
    .iic_sda          (iic_sda  	),
    .i2c_busy         (             ),
    
    .sir_addr         (cpld_fpga_i2c_addr   ),
    .sir_read         (cpld_fpga_i2c_read   ),
    .sir_wdat         ({cpld_fpga_i2c_wdat[7:0],cpld_fpga_i2c_wdat[15:8],cpld_fpga_i2c_wdat[23:16],cpld_fpga_i2c_wdat[31:24]}   ),
    .sir_sel          (cpld_fpga_i2c_sel    ),
    .sir_dack         (1'b0                 ),
    .sir_rdat         ({cpld_fpga_i2c_rdat[7:0],cpld_fpga_i2c_rdat[15:8],cpld_fpga_i2c_rdat[23:16],cpld_fpga_i2c_rdat[31:24]}   ),
    .sir_done         (1'b0                 )
);

always @(posedge clk)
begin
	case(cpld_fpga_i2c_addr)
		8'h00	:	cpld_fpga_i2c_rdat <= test_dat;
		8'h01	:	cpld_fpga_i2c_rdat <= ID_CODE[31:0];
		8'h02	:	cpld_fpga_i2c_rdat <= CHIP_ID[31:0];
		8'h03	:	cpld_fpga_i2c_rdat <= CHIP_ID[63:32];
		8'h04	:	cpld_fpga_i2c_rdat <= TEMP_LOC0_0[31:0];
		8'h05	:	cpld_fpga_i2c_rdat <= TEMP_LOC1_0[31:0];
		8'h06	:	cpld_fpga_i2c_rdat <= TEMP_LOC1_1[31:0];
		8'h07	:	cpld_fpga_i2c_rdat <= TEMP_LOC2_0[31:0];
		8'h08	:	cpld_fpga_i2c_rdat <= TEMP_LOC2_1[31:0];
		8'h09	:	cpld_fpga_i2c_rdat <= TEMP_LOC3_0[31:0];
		8'h10	:	cpld_fpga_i2c_rdat <= TEMP_LOC3_1[31:0];
		8'h11	:	cpld_fpga_i2c_rdat <= TEMP_LOC4_0[31:0];
		8'h12	:	cpld_fpga_i2c_rdat <= TEMP_LOC4_1[31:0];
		8'h13	:	cpld_fpga_i2c_rdat <= VCC[31:0];
		8'h14	:	cpld_fpga_i2c_rdat <= VCCIO_SDM[31:0];
		8'h15	:	cpld_fpga_i2c_rdat <= VCCPT[31:0];
		8'h16	:	cpld_fpga_i2c_rdat <= VCCRCORE[31:0];
		8'h17	:	cpld_fpga_i2c_rdat <= VCCH_SDM[31:0];
		8'h18	:	cpld_fpga_i2c_rdat <= VCCL_SDM[31:0];
		8'h19	:	cpld_fpga_i2c_rdat <= VCCADC[31:0];
		default	:	cpld_fpga_i2c_rdat <= 32'h00;
	endcase
end

always @(posedge clk or posedge rst)
begin
	if(rst)
	begin
		test_dat <=	32'h0;
		BRD_ID	 <= 4'b0101;
		BOM_VER	 <= 4'b0000;
		PCB_VER	 <= 4'b0000;
	end	
	else if((cpld_fpga_i2c_sel == 1'b1) && (cpld_fpga_i2c_read == 1'b0))
	begin
		case(cpld_fpga_i2c_addr)
			8'h00	:test_dat 	<= cpld_fpga_i2c_wdat;
			8'h20	:BRD_ID		<= cpld_fpga_i2c_wdat[7:4];
			8'h21	:{BOM_VER,PCB_VER} <= cpld_fpga_i2c_wdat[7:0];
		endcase
	end
	else;
end







endmodule
