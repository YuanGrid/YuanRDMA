//
// Module       :    ddr4_test
// Called by    :    
// commment		;
//
// ***************************************************************************************

`include "../top/define.vh"
module ddr_test_ctrl(
	input	wire         		rst				,
	input  	wire         		clk				,
	
	input	wire				test_enb		,
	input	wire				test_type		,//[0]检验[1]性能
	input	wire	[1:0]		ddr_wr			,
	
	input	wire				req_wenb		,
	input	wire	[127:0]		req_wdat		,
	
	input	wire				app_amm_rvld	,
	input	wire	[127:0]		app_amm_rdat	,
	
	output	reg					test_done		,
	output	reg					err_flag		,
	output	reg		[31:0]		err_cnt			
	
);

`ifdef SIM
	parameter DDR_END_ADDR 	= 27'h00000ff;
	parameter ADDR_WIDIH 	= 7;
`else  
	parameter DDR_END_ADDR 	= 27'h007ffff;
	parameter ADDR_WIDIH 	= 18;
`endif

reg				test_enb_d1;
reg				test_enb_d2;
wire			test_init;
wire			test_end;
reg		[31:0]	wr_addr;
reg		[31:0]	rd_addr;

always @(posedge clk)
begin
	test_enb_d1	<= test_enb;
	test_enb_d2	<= test_enb_d1;
end

assign	test_init = test_enb_d1 && (~test_enb_d2);
assign	test_end  = (~test_enb_d1) && test_enb_d2;

always @(posedge clk)
begin
	if(test_init)
		wr_addr <= 'b0;
	else if(req_wenb)
		wr_addr <= wr_addr + 1'b1;
	else;
end

always @(posedge clk)
begin
	if(test_init)
		rd_addr <= 'b0;
	else if(app_amm_rvld)
		rd_addr <= rd_addr + 1'b1;
	else;
end

always @(posedge clk)
begin
	if(test_type == 1'b1)
		test_done <= 1'b0;
	else if(ddr_wr == 2'b10)//只写
		if(wr_addr == DDR_END_ADDR)
			test_done <= 1'b1;
		else
			test_done <= 1'b0;
	else//只读、读写
		if(rd_addr == DDR_END_ADDR)
			test_done <= 1'b1;
		else
			test_done <= 1'b0;
end


wire			req_rden;
wire	[127:0]	req_rdat;
wire			req_empty;
wire	[9:0]	data_wcnt;

`ifdef XILINX_SIM
xfifo_sync_w128d1024_fwft 
	U_fifo(
			.rst                 	(rst              ),
			.clk                	(clk              ),

			.din                 	(req_wdat	   	  ),
			.wr_en                	(req_wenb		  ),
			.full                 	(                 ),
			.almost_full	        (                 ),

			.rd_en                	(req_rden         ),
			.dout                 	(req_rdat         ),
			.empty                	(req_empty        ),
			.almost_empty         	(                 ),
			.data_count           	(data_wcnt        )

);

`else
fifo_sync_w128d1024_fwft 
	U_fifo(
			.aclr                 	(rst              ),
			.clock                	(clk              ),

			.data                 	(req_wdat        	),
			.wrreq                	(req_wenb			),
			.full                 	(                 ),
			//.almost_full          (                 ),

			.rdreq                	(req_rden         ),
			.q                 		(req_rdat         ),
			.empty                	(req_empty        ),
			.almost_empty         	(                 ),
			.usedw           		(data_wcnt        )

);
`endif
   
//assign	req_rdat = 'b0;
assign 	req_rden = ddr_wr[1] ? app_amm_rvld : 1'b0;

reg				error;
reg		[31:0]	error_cnt;

always @(*)
begin
	if(ddr_wr[1] == 1'b0)//不写
		error <= 1'b0;
	else
		error <= ((app_amm_rdat != req_rdat) && app_amm_rvld) ? 1'b1 : 1'b0;
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


endmodule