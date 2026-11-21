
`include "../top/global_define.vh"

module ddr_test_wr(
	input	wire         		rst				,
	input  	wire         		clk				,
	
	input	wire				test_enb		,
	input	wire				test_type		,//[0]检验[1]性能
	output	reg					test_done		,
	
	input	wire				addr_mode		,
	input	wire	[7:0]		addr_seed		,
	input	wire	[26:0]		DDR_END_ADDR	,

	input	wire	[1:0]		ddr_wr			,//[0]读[1]写
	input	wire	[1:0]		dat_mode		,
	input	wire	[31:0]		ddr_dat0		,	
	input	wire	[31:0]		ddr_dat1		,
	input	wire	[31:0]		ddr_dat2		,
	input	wire	[31:0]		ddr_dat3		,
	
	input	wire				app_amm_ready	,
	output	reg					app_amm_read	,
	output	reg					app_amm_write	,
	output	reg		[26:0]		app_amm_addr	,
	output	reg		[127:0]		app_amm_wdat	,
	
	output	reg		[31:0]		total_time_w	,
	output	reg		[31:0]		total_cnt_w		,
	output	reg		[31:0]		total_time_r	,
	output	reg		[31:0]		total_cnt_r		
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
reg		[31:0]		rd_addr;

always @(posedge clk)
begin
	test_enb_d1 <= test_enb;
	test_enb_d2 <= test_enb_d1;
end

assign test_init 	= test_enb_d1 && (~test_enb_d2);
assign rd_enb 		= ddr_wr[0];
assign wr_enb 		= ddr_wr[1];
assign ddr_dat		= {ddr_dat3,ddr_dat2,ddr_dat1,ddr_dat0};

always @(posedge clk)
begin
	if(/* test_type == 1'b1 &&  */rd_enb && wr_enb)
		req_sys <= 1'b1;
	else	
		req_sys <= 1'b0;
end
     
`ifdef SIM

reg		[63:0]	cur_stat;
reg		[63:0]	nxt_stat;

parameter  IDLE			= "IDLE	"	;
parameter  WRITE		= "WRITE"	;
parameter  W_DONE		= "W_DONE"	;
parameter  READ			= "READ	"	;
parameter  W_WAIT		= "W_WAIT"	;
parameter  R_WAIT		= "R_WAIT"	;
parameter  FINI 	  	= "FINI "	;

`else  

reg		[6:0]	cur_stat;
reg		[6:0]	nxt_stat;

parameter  IDLE			= 7'b0000001;
parameter  WRITE		= 7'b0000010;
parameter  W_DONE		= 7'b0000100;
parameter  READ			= 7'b0001000;
parameter  W_WAIT		= 7'b0010000;
parameter  R_WAIT		= 7'b0100000;
parameter  FINI 	  	= 7'b1000000;

`endif 

always @(posedge clk or posedge rst)
begin
	if(rst)
		cur_stat <= IDLE;
	else
		cur_stat <= nxt_stat;
end

always @(*) begin
	case(cur_stat)
		IDLE :
			if(test_init == 1'b1)
				if(wr_enb == 1'b1)
					nxt_stat <= WRITE;
				else if(rd_enb == 1'b1)
					nxt_stat <= READ;
				else;
			else
				nxt_stat <= IDLE;
		WRITE :
			if(req_sys == 1'b1)//读写交替
				if(app_amm_ready == 1'b0)
					nxt_stat <= W_WAIT;
				else
					nxt_stat <= READ;
			else //先写后读
				if(wr_end)
					nxt_stat <= W_DONE;
				else if(app_amm_ready == 1'b0)
					nxt_stat <= W_WAIT;
				else
					nxt_stat <= WRITE;
		W_DONE :
			if(rd_enb == 1'b1)
				nxt_stat <= READ;
			else
				nxt_stat <= FINI;
		READ :
			if(req_sys == 1'b1)//读写交替
				if(rd_end)
					nxt_stat <= FINI;
				else if(app_amm_ready == 1'b0)
					nxt_stat <= R_WAIT;
				else
					nxt_stat <= WRITE;
			else //先写后读
				if(rd_end)
					nxt_stat <= FINI;
				else if(app_amm_ready == 1'b0)
					nxt_stat <= R_WAIT;
				else
					nxt_stat <= READ;
		R_WAIT :
			if(app_amm_ready == 1'b1)
				nxt_stat <= READ;
			else
				nxt_stat <= R_WAIT;
		W_WAIT :
			if(app_amm_ready == 1'b1)
				nxt_stat <= WRITE;
			else
				nxt_stat <= W_WAIT;		
		FINI :
				nxt_stat <= IDLE;
		default : nxt_stat <= IDLE;
	endcase
end

//
always @(posedge clk)
begin
	if(test_enb == 1'b1)
		if(test_type == 1'b1)
			wr_end <= 1'b0;
		else if(wr_addr == (DDR_END_ADDR - 1'b1))
			wr_end <= 1'b1;
		else
			wr_end <= 1'b0;
	else
		wr_end <= 1'b1;
end

always @(posedge clk)
begin
	if(test_enb == 1'b1)
		if(test_type == 1'b1)
			rd_end <= 1'b0;
		else if(rd_addr == (DDR_END_ADDR - 1'b1))
			rd_end <= 1'b1;
		else
			rd_end <= 1'b0;
	else
		rd_end <= 1'b1;
end

//请求结束
always @(posedge clk)
begin
	if(test_done == 1'b1)
		test_done <= 1'b0;
	else if(test_type == 1'b1)
		test_done <= 1'b0;
	else if(ddr_wr == 2'b10)//只写
		if(wr_addr == DDR_END_ADDR)
			test_done <= 1'b1;
		else
			test_done <= 1'b0;
	else//只读、读写
		test_done <= 1'b0;
end


wire 			app_wenb ,app_renb;

//顺序地址
always @(posedge clk)
begin
	if(test_init | test_done)
		wr_addr <= 'b0;
	else if(cur_stat == WRITE)
		if(wr_addr == DDR_END_ADDR)
			wr_addr <= 'b0;
		else if(app_amm_ready)
			wr_addr <= wr_addr + app_wenb;
		else;
	else;	
end

always @(posedge clk)
begin
	if(test_init | test_done)
		rd_addr <= 'b0;
	else if(cur_stat == READ)
		if(rd_addr == DDR_END_ADDR)
			rd_addr <= 'b0;
		else if(app_amm_ready)
			rd_addr <= rd_addr + app_renb;
		else;
	else;
end

//hash
wire	[31:0]	crc_tmp;
wire	[31:0]	test_crc;
reg		[31:0]	test_dat;
reg		[31:0]	wr_addr_d,rd_addr_d;

always @(posedge clk)
begin
	wr_addr_d 	<= wr_addr;
	rd_addr_d 	<= rd_addr;
end	

assign	app_wenb = (cur_stat == WRITE) && app_amm_ready;
assign	app_renb = (cur_stat == READ) && app_amm_ready;


//随机地址
always @(posedge clk)
begin
	if(cur_stat == IDLE)
		test_dat <= 'b0;
	else if(cur_stat == WRITE || ((~req_sys) && (cur_stat == READ)))
		if(app_amm_ready)
			test_dat <= test_dat + addr_seed[7:0];
		else;
	else;
end


assign 	crc_tmp  = crc32d16(test_dat[15:0],32'hFFFF_FFFF);	
assign 	test_crc = crc32d16(test_dat[31:16],crc_tmp);

always @(*)
begin
	if(app_wenb )
	begin
		app_amm_write 	<= 1'b1;
		app_amm_read 	<= 1'b0;
		app_amm_addr	<= addr_mode ? test_crc[26:0] : wr_addr[26:0]; 
	end
	else if(app_renb )
	begin
		app_amm_write	<= 1'b0;
		app_amm_read	<= 1'b1;
		app_amm_addr	<= addr_mode ? test_crc[26:0] : rd_addr[26:0];
	end
	else
	begin
		app_amm_write	<= 'b0;
		app_amm_read	<= 'b0;
		app_amm_addr	<= 'b0;
	end
end

always @(*)
begin
	if(app_wenb)
		case(dat_mode)
			2'd0 : app_amm_wdat <= {4{wr_addr[31:0]}};
			2'd1 : app_amm_wdat <= ddr_dat[127:0];
			2'd2 : app_amm_wdat <= {4{test_crc[31:0]}};
		 default : app_amm_wdat <= 128'b0;
		endcase
	else
		app_amm_wdat <= 'b0;
end

//计算时间
reg				total_time_enb;

always @(posedge clk or posedge rst)
begin
	if(rst)
		total_time_enb <= 1'b0;
	else if(cur_stat == IDLE && nxt_stat != IDLE)
		total_time_enb <= 1'b1;
	else if(cur_stat == FINI)
		total_time_enb <= 1'b0;
	else;
end

always @(posedge clk)
begin
	if(test_init)
		total_time_w	<= 'b0;
	else if(total_time_enb && wr_enb && total_time_w < 32'hFFFF_FFFF)
		total_time_w	<= total_time_w + 1'b1;
	else;
end

always @(posedge clk)
begin
	if(test_init)
		total_cnt_w		<= 'b0;
	else if(app_amm_write && total_cnt_w < 32'hFFFF_FFFF)
		total_cnt_w		<= total_cnt_w + 1'b1;
	else;
end

always @(posedge clk)
begin
	if(test_init)
		total_time_r	<= 'b0;
	else if(total_time_enb && rd_enb && total_time_r < 32'hFFFF_FFFF)
		total_time_r	<= total_time_r + 1'b1;
	else;
end

always @(posedge clk)
begin
	if(test_init)
		total_cnt_r		<= 'b0;
	else if(app_amm_read && total_cnt_r < 32'hFFFF_FFFF)
		total_cnt_r		<= total_cnt_r + 1'b1;
	else;
end

endmodule