//
// Module       :    ddr4_test
// Called by    :    
// commment		;
//
// ***************************************************************************************

`include "../top/define.vh"

module ddr_test_rd(
	input	wire         		rst				,
	input  	wire         		clk				,
	
	input	wire				test_enb		,
	input	wire				test_type		,
	output	reg 				test_done		,
	
	input	wire				addr_mode		,
	input	wire	[7:0]		addr_seed		,
	input	wire	[26:0]		DDR_END_ADDR	,
	
	input	wire	[1:0]		ddr_wr			,
	input	wire	[1:0]		dat_mode		,
	input	wire	[31:0]		ddr_dat0		,	
	input	wire	[31:0]		ddr_dat1		,
	input	wire	[31:0]		ddr_dat2		,
	input	wire	[31:0]		ddr_dat3		,
	
	input	wire				app_amm_rvld	,
	input	wire	[127:0]		app_amm_rdat	,
	
	output	reg					err_flag		,
	output	reg		[31:0]		err_cnt			,
	output	reg					rd_done			,
	output	reg		[31:0]		rd_addr			
);
`include "./crc_function.sv"

reg					test_enb_d1;
reg					test_enb_d2;
wire				test_init;
wire				rd_enb;
wire				wr_enb;
wire	[127:0]		ddr_dat;

reg					req_sys;//读写交替
reg					wr_end;
reg					rd_end;
reg		[31:0]		wr_addr;
//reg		[31:0]		rd_addr;

always @(posedge clk)
begin
	test_enb_d1 <= test_enb;
	test_enb_d2 <= test_enb_d1;
end

assign test_init 	= test_enb_d1 && (~test_enb_d2);
assign rd_enb 		= ddr_wr[0];
assign wr_enb 		= ddr_wr[1];
assign ddr_dat		= {ddr_dat3,ddr_dat2,ddr_dat1,ddr_dat0};

//请求结束
always @(posedge clk)
begin
	if(test_done == 1'b1)
		test_done <= 1'b0;
	else if(test_type == 1'b1)
		test_done <= 1'b0;
	else if(ddr_wr == 2'b10)//只写
		test_done <= 1'b0;
	else//只读、读写
		if(rd_addr == DDR_END_ADDR)
			test_done <= 1'b1;
		else
			test_done <= 1'b0;
end

//校验读数据的正确性
//hash
reg		[31:0]	crc_tmp;
reg		[31:0]	test_crc;
reg		[31:0]	test_dat;
reg		[31:0]	rd_addr_d;
reg 			app_tab_renb;
reg		[27:0]	app_tab_addr;
reg		[127:0]	app_tab_wdat;
reg		[127:0]	app_tab_rdat;

//顺序地址
always @(posedge clk)
begin
	if(test_init | test_done)
		rd_addr <= 'b0;
	else if(app_amm_rvld)
		rd_addr <= rd_addr + 1'b1;
	else;
	
	rd_addr_d	<= rd_addr;
end


//随机地址
always @(posedge clk)
begin
	if(test_init)
		test_dat <= 'b0;
	else if(app_amm_rvld)
		test_dat <= test_dat + addr_seed[7:0];
	else;
end

always @(posedge clk)
begin
	crc_tmp  = crc32d16(test_dat[15:0],32'hFFFF_FFFF);	
	test_crc = crc32d16(test_dat[31:16],crc_tmp);
end

always @(posedge clk)
begin
	app_tab_renb	<= app_amm_rvld;
	app_tab_addr	<=	addr_mode ? test_crc[26:0] : rd_addr_d[26:0];
	app_tab_rdat	<= app_amm_rdat;
end

always @(*)
begin
	if(app_tab_renb)
		case(dat_mode)
			2'd0 : app_tab_wdat <= {4{rd_addr_d[31:0]}};
			2'd1 : app_tab_wdat <= ddr_dat[127:0];
			2'd2 : app_tab_wdat <= {4{test_crc[31:0]}};
		 default : app_tab_wdat <= 128'b0;
		endcase
	else
		app_tab_wdat <= 'b0;
end

//对比结果

reg			error;

always @(*)
begin
	if(ddr_wr[0] == 1'b0)//不读
		error <= 1'b0;
	else
		error <= ((app_tab_rdat != app_tab_wdat) && app_tab_renb) ? 1'b1 : 1'b0;
end

always @(posedge clk)
begin
	if(test_init)
		err_flag <= 1'b0;
	else if(error)
		err_flag <= 1'b1;
	else;
end
always @(posedge clk)
begin
	if(test_init)
		err_cnt <= 1'b0;
	else if(error && err_cnt < 32'hffffffff)
		err_cnt <= err_cnt + 1'b1;
	else;
end

always @(posedge clk)
begin
	if(test_init)
		rd_done <= 1'b0;
	else if(ddr_wr[0] == 1'b0)
		rd_done <= 1'b0;
	else if(rd_addr == DDR_END_ADDR)
		rd_done <= 1'b1;
	else;
end

endmodule