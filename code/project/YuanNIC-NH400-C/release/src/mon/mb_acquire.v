// 2022/11/01      caitiantian     1.0             initial

// ***************************************************************************************
`include "../top/define.vh"
module mb_acquire(
	input	wire				clk				,	
	input	wire				reset			,
	
	input	wire				req_enb			,
	input	wire	[7:0]		req_time		,
	
	output  reg		[3:0]	   	mb_addr			,		
	output  reg 	[31:0]	   	mb_wdat			,
	output  reg 				mb_write		,
	output  reg 				mb_read			,
	input  	wire	[31:0] 		mb_rdat			,
	input  	wire 				mb_rvld			,
	input  	wire 				mb_wait			,
	
	output	reg					mb_rst			,
	
	output	reg 	[31:0]		ID_CODE			,
	output	reg 	[63:0]		CHIP_ID			,
	output	reg 	[31:0]		TEMP_LOC0_0		,
	output	reg 	[31:0]		TEMP_LOC1_0		,
	output	reg 	[31:0]		TEMP_LOC1_1		,
	output	reg 	[31:0]		TEMP_LOC2_0		,
	output	reg 	[31:0]		TEMP_LOC2_1		,
	output	reg 	[31:0]		TEMP_LOC3_0		,
	output	reg 	[31:0]		TEMP_LOC3_1		,
	output	reg 	[31:0]		TEMP_LOC4_0		,
	output	reg 	[31:0]		TEMP_LOC4_1		,
	output	reg 	[31:0]		VCC				,
	output	reg 	[31:0]		VCCIO_SDM		,
	output	reg 	[31:0]		VCCPT			,
	output	reg 	[31:0]		VCCRCORE		,
	output	reg 	[31:0]		VCCH_SDM		,
	output	reg 	[31:0]		VCCL_SDM		,
	output	reg 	[31:0]		VCCADC

);
/***************************************************/

reg				req_enb_d1;
reg				req_enb_d2;

always @(posedge clk)
begin
	req_enb_d1	<= req_enb;
	req_enb_d2	<= req_enb_d1;
end

/////////////////////////////////////////////////////
`ifdef	SIM
reg		[127:0]	cur_state;
//reg		[127:0]	cur_state;

parameter		IDLE		=	"IDLE		",
				NON_FILL	=	"NON_FILL	",
				GET_IDCODE	=	"GET_IDCODE	",	
				GET_CHIPID	=	"GET_CHIPID	",	
				GET_VOL		=	"GET_VOL	",	
				VOL_MASK	=	"VOL_MASK	",
				GET_TEMP	=	"GET_TEMP	",
				TEMP_MASK	=	"TEMP_MASK	",
				READ_ISR	=	"READ_ISR	",
				ERR_CODE	=	"ERR_CODE	",
				READ_DAT	=	"READ_DAT	",
				MB_RST		=	"MB_RST		";

`else
reg		[11:0]	cur_state;
//reg		[11:0]	cur_state;

parameter		IDLE		=	12'b000000000001,
				NON_FILL	=	12'b000000000010,
				GET_IDCODE	=	12'b000000000100,
				GET_CHIPID	=	12'b000000001000,
				GET_VOL		=	12'b000000010000,
				VOL_MASK	=	12'b000000100000,
				GET_TEMP	=	12'b000001000000,
				TEMP_MASK	=	12'b000010000000,
				READ_ISR	=	12'b000100000000,
				ERR_CODE	=	12'b001000000000,
				READ_DAT	=	12'b010000000000,
				MB_RST		=	12'b100000000000;
`endif

				
/* always @(posedge clk or posedge reset)
begin
	if(reset)
		cur_state <= IDLE;
	else
		cur_state <= cur_state;
end
 */
reg		[1:0]	rd_type		;
reg		[9:0]	time_cnt	;
reg 			dat_val		;
reg 			dat_ok		;
wire			space_val	;
reg				rd_onecyc	;
reg		[5:0]	rsp_num		;
reg		[9:0]	isr_cnt		;

reg		[7:0]	mb_rst_cnt	;
reg				mb_rst_req	;
reg				mb_rst_done	;	
reg				mb_wait_d	;

always @(posedge clk) mb_wait_d <= mb_wait;

always @(posedge clk or posedge reset)
begin
	if(reset)
		cur_state <= IDLE;
	else begin
	case(cur_state)
	IDLE	:
		if(req_enb_d2 && req_time)
			cur_state	<= NON_FILL;
		else
			cur_state 	<= IDLE;
	NON_FILL:
		if(space_val)
			case(rd_type)
				2'b00	: cur_state <= GET_IDCODE;
				2'b01	: cur_state	<= GET_CHIPID;
				2'b10	: cur_state	<= GET_VOL;
				2'b11	: cur_state	<= GET_TEMP;
				default	: cur_state <= IDLE;
			endcase
		else
			cur_state	<= NON_FILL;
	GET_IDCODE	:
		if((mb_wait == 1'b0) && req_time)
			cur_state	<= READ_ISR;
		else
			cur_state	<= GET_IDCODE;
	GET_CHIPID	:
		if((mb_wait == 1'b0) && req_time)
			cur_state	<= READ_ISR;
		else
			cur_state	<= GET_CHIPID;
	GET_VOL	:
		if((mb_wait == 1'b0) && req_time)
			cur_state	<= VOL_MASK;
		else
			cur_state	<= GET_VOL;
	VOL_MASK:
		if((mb_wait == 1'b0) && req_time)
			cur_state	<= READ_ISR;
		else
			cur_state	<= VOL_MASK;
	GET_TEMP:
		if((mb_wait == 1'b0) && req_time)
			cur_state	<= TEMP_MASK;
		else
			cur_state	<= GET_TEMP;
	TEMP_MASK:
		if((mb_wait == 1'b0) && req_time)
			cur_state	<= READ_ISR;
		else
			cur_state	<= TEMP_MASK;
	READ_ISR	:
		if(mb_rvld == 1'b1)
			if(mb_rdat[0] == 1'b1)
				cur_state	<= ERR_CODE;
			else if(isr_cnt == 10'h0)
				cur_state	<= ERR_CODE;
			else
				cur_state	<= READ_ISR;
		else if(time_cnt == 1'b0)
			cur_state	<= MB_RST;
		else
			cur_state	<= READ_ISR;
	ERR_CODE:
		if(mb_rvld == 1'b1)
			cur_state	<= READ_DAT;
		else if(time_cnt == 1'b0)
			cur_state	<= MB_RST;
		else
			cur_state	<= ERR_CODE;
	READ_DAT:
		if((time_cnt == 1'b0) | (rsp_num == 'b0))
			if(dat_ok && dat_val)
				cur_state	<= IDLE;
			else
				cur_state	<= MB_RST;
		else	
			cur_state	<= READ_DAT;
	MB_RST	:
		if(mb_rst_done)
			cur_state	<= IDLE;
		else
			cur_state	<= MB_RST;
	
	default	:
			cur_state <= IDLE;
	endcase
	end
end

//Temperature Sensor Locations
reg 	[3:0]	cnt1;
reg		[5:0]	req_num ;
wire	[15:0]	temp_loc[0:4];
wire	[15:0]	temp_msk[0:4];

assign 	temp_loc[0] = 16'h0;	assign	temp_msk[0] = 16'b0001; //core0 : temp0 
assign 	temp_loc[1] = 16'h1;	assign 	temp_msk[1] = 16'b0011; //core1 : temp0,temp1
assign 	temp_loc[2] = 16'h2;	assign 	temp_msk[2] = 16'b0011; //core2 : temp0,temp1
assign 	temp_loc[3] = 16'h3;	assign 	temp_msk[3] = 16'b0011; //core3 : temp0,temp1
assign 	temp_loc[4] = 16'h4;	assign 	temp_msk[4] = 16'b0011; //core4 : temp0,temp1

always @(*)
begin
	case(cur_state)
		IDLE	:begin
				mb_read  <= 1'b0;
				mb_write <= 1'b0;
				mb_addr  <= 4'h0; 
				mb_wdat  <= 32'h0; 
			end
		NON_FILL:
				begin
					mb_read	 <= ~rd_onecyc;
					mb_write <= 1'b0;
					mb_addr	 <= 4'h2;
					mb_wdat	 <= 32'h0;
				end
				
		GET_IDCODE:
				if(req_time) begin
					mb_read	 <= 1'b0;
					mb_write <= 1'b1;
					mb_addr	 <= 4'h1;
					mb_wdat	 <= 32'h0010;
				end
				else begin
					mb_read  <= 1'b0;
					mb_write <= 1'b0;
					mb_addr  <= 4'h0; 
					mb_wdat  <= 32'h0; 
				end
		GET_CHIPID:
				if(req_time) begin
					mb_read	 <= 1'b0;
					mb_write <= 1'b1;
					mb_addr	 <= 4'h1;
					mb_wdat	 <= 32'h0012;
				end
				else begin
					mb_read  <= 1'b0;
					mb_write <= 1'b0;
					mb_addr  <= 4'h0; 
					mb_wdat  <= 32'h0; 
				end
		GET_VOL:
				if(req_time) begin
					mb_read	 <= 1'b0;
					mb_write <= 1'b1;
					mb_addr	 <= 4'h0;
					mb_wdat  <= 32'h1018;
				end
				else begin
					mb_read  <= 1'b0;
					mb_write <= 1'b0;
					mb_addr  <= 4'h0; 
					mb_wdat  <= 32'h0; 
				end
		VOL_MASK:
				if(req_time) begin
					mb_read	 <= 1'b0;
					mb_write <= 1'b1;
					mb_addr	 <= 4'h1;
					mb_wdat	 <= 32'b0010_1111_1100;//CH2、CH3、CH4...CH9
				end 
				else begin
					mb_read  <= 1'b0;
					mb_write <= 1'b0;
					mb_addr  <= 4'h0; 
					mb_wdat  <= 32'h0; 
				end
		GET_TEMP:
				if(req_time) begin
					mb_read	 <= 1'b0;
					mb_write <= 1'b1;
					mb_addr	 <= 4'h0;
					mb_wdat	 <= 32'h1019;
				end 
				else begin
					mb_read  <= 1'b0;
					mb_write <= 1'b0;
					mb_addr  <= 4'h0; 
					mb_wdat  <= 32'h0; 
				end
		TEMP_MASK:
				if(req_time) begin
					mb_read	 <= 1'b0;
					mb_write <= 1'b1;
					mb_addr	 <= 4'h1;
					mb_wdat	 <= {temp_loc[cnt1],temp_msk[cnt1]};
				end 
				else begin
					mb_read  <= 1'b0;
					mb_write <= 1'b0;
					mb_addr  <= 4'h0; 
					mb_wdat  <= 32'h0; 
				end
		READ_ISR:
				if((mb_wait == 1'b0) && req_time) begin
					mb_read  <= ~rd_onecyc;//读返回后再发起读请求
					mb_write <= 1'b0;
					mb_addr	 <= 4'h8;
					mb_wdat	 <= 4'h0;
				end
				else begin
					mb_read  <= 1'b0;
					mb_write <= 1'b0;
					mb_addr  <= 4'h0; 
					mb_wdat  <= 32'h0; 
				end
		ERR_CODE:begin
					mb_read <= ~rd_onecyc;//只读一拍
				
					mb_write <= 1'b0;
					mb_addr	 <= 4'h5;
					mb_wdat	 <= 4'h0;
				end
		READ_DAT:begin	//带参数发起命令时，按照掩码位数表示请求个数
				if(req_num == 6'h0)
					mb_read <= 1'b0;
				else	
					mb_read <= 1'b1;
				
				mb_write <= 1'b0;
				mb_addr	 <= 4'h5;
				mb_wdat	 <= 4'h0;
		end
		default:begin
				mb_read	 	<= 1'b0;
				mb_write 	<= 1'b0;
				mb_addr	 	<= 4'h0;
				mb_wdat	 	<= 32'h0;
		end
	endcase

end

					
assign	space_val	= mb_rvld && (mb_rdat != 32'h0);//表示fifo有空间
//assign	dat_val		= mb_rvld && (mb_rdat[0] == 1'b1);//ISR[0],表示数据有效
//assign	dat_ok		= mb_rvld && (mb_rdat[10:0] == 11'h0);//ERROR_CODE = 0x0,表示读命令成功


always @(posedge clk or posedge reset)
begin
	if(reset)begin
		mb_rst		<= 1'b0;
		mb_rst_done	<= 1'b0;
		mb_rst_cnt	<= 'b0;
		rd_type		<= 2'b0;
		cnt1		<= 'b0;
		req_num		<= 'b0;
		rsp_num		<= 'b0;
		time_cnt	<= 10'hff;
		rd_onecyc	<= 1'b0;
		isr_cnt		<= 10'h1f;
	end
	else begin
		case(cur_state)
			IDLE	:begin
					time_cnt	<= 10'hff;
					isr_cnt		<= 10'h1f;
					mb_rst_done <= 1'b0;
			end
			NON_FILL:begin
					if(space_val)
						rd_onecyc <= 1'b0;
					else if(!mb_wait && mb_read)
						rd_onecyc <= 1'b1;
					else;
			end
			GET_IDCODE:begin
					req_num	 <= 6'h1;
			end
			GET_CHIPID:begin
					req_num	 <= 6'h2;
			end
			VOL_MASK:begin
					req_num	 <= mb_wdat[0] + mb_wdat[1] + mb_wdat[2] + mb_wdat[3] + mb_wdat[4] + mb_wdat[5] + mb_wdat[6] + mb_wdat[7] + 
								mb_wdat[8] + mb_wdat[9] + mb_wdat[10]+ mb_wdat[11]+ mb_wdat[12]+ mb_wdat[13]+ mb_wdat[14]+ mb_wdat[15]+
								mb_wdat[16]+ mb_wdat[17]+ mb_wdat[18]+ mb_wdat[19]+ mb_wdat[20]+ mb_wdat[21]+ mb_wdat[22]+ mb_wdat[23]+
								mb_wdat[24]+ mb_wdat[25]+ mb_wdat[26]+ mb_wdat[27]+ mb_wdat[28]+ mb_wdat[29]+ mb_wdat[30]+ mb_wdat[31];
			end
			TEMP_MASK:begin
					req_num	 <= mb_wdat[0] + mb_wdat[1] + mb_wdat[2] + mb_wdat[3] + mb_wdat[4] + mb_wdat[5] + mb_wdat[6] + mb_wdat[7] + 
								mb_wdat[8] + mb_wdat[9] + mb_wdat[10]+ mb_wdat[11]+ mb_wdat[12]+ mb_wdat[13]+ mb_wdat[14]+ mb_wdat[15];
					
					if((mb_wait == 1'b0) && req_time)
						if(cnt1 == 4'h4)
							cnt1 <= 4'b0;
						else
							cnt1 <= cnt1 + 1'b1;
					else;
					
			end
			READ_ISR:begin
					//读数据 超时处理	
					if(time_cnt == 10'b0 | mb_rvld)
						time_cnt <= 10'hff;
					else if(rd_onecyc && (time_cnt > 10'b0))
						time_cnt <= time_cnt - 1'b1;
					else;
			
					if((time_cnt == 1'b0) | mb_rvld)
						rd_onecyc <= 1'b0;
					else if((!mb_wait) && mb_read)
						rd_onecyc <= 1'b1;
					else;
					
					if(isr_cnt > 10'b0)
						isr_cnt <= isr_cnt - mb_read;
					else
						isr_cnt <= 10'b0;
						
					if(mb_rvld)
						dat_val	<= (mb_rdat[0] == 1'b1);
					else;
			end
			ERR_CODE:begin
					rsp_num <= req_num;
						
					if(mb_rvld)
						dat_ok <= (mb_rdat[10:0] == 11'h0);
					else;
						
					//读数据 超时处理	
					if(time_cnt == 10'b0 | mb_rvld)
						time_cnt <= 10'hff;
					else if(time_cnt > 10'b0)
						time_cnt <= time_cnt - 1'b1;
					else;
										
					if((time_cnt == 1'b0) | mb_rvld)
						rd_onecyc <= 1'b0;
					else if((!mb_wait) && mb_read)
						rd_onecyc <= 1'b1;
					else;
			end
			READ_DAT:begin	//带参数发起命令时，按照掩码位数表示请求个数
					if(req_num > 6'b0)
						req_num <= req_num - ((!mb_wait) && mb_read);
					else
						req_num <= 6'b0;
					
					if(rsp_num > 6'b0)
						rsp_num <= rsp_num - mb_rvld;
					else
						rsp_num <= 6'b0;
						
					//读数据 超时处理	
					if(time_cnt == 10'b0 | mb_rvld)
						time_cnt <= 10'hff;
					else if(time_cnt > 10'b0)
						time_cnt <= time_cnt - 1'b1;
					else;
					
					if((time_cnt == 1'b0) | (rsp_num == 'b0))
						if(rd_type == 2'b11)
							if(cnt1 == 4'h0)
								rd_type <= rd_type + 1'b1;
							else;
						else
							rd_type <= rd_type + 1'b1;
					else;
			end
			MB_RST:begin
					if(mb_rst_done)
						mb_rst_cnt <= 'b0;
					else 
						mb_rst_cnt <= mb_rst_cnt + 1'b1;
					
					if(mb_rst_done)
						mb_rst	<= 1'b0;
					else
						mb_rst	<= mb_rst_cnt[7:6] == 2'b01;
					
					mb_rst_done <= (mb_rst_cnt[7:2] == 6'h3f) ? 1'b1 : 1'b0;
			end
		endcase
	end

end

always @(posedge clk or posedge reset)
begin
	if(reset)
	begin
		ID_CODE 		<= 32'b0;
		CHIP_ID			<= 64'b0;
	
		TEMP_LOC0_0		<= 32'b0;	
		TEMP_LOC1_0		<= 32'b0;	
		TEMP_LOC1_1		<= 32'b0;	
		TEMP_LOC2_0		<= 32'b0;	
		TEMP_LOC2_1		<= 32'b0;	
		TEMP_LOC3_0		<= 32'b0;	
		TEMP_LOC3_1		<= 32'b0;	
		TEMP_LOC4_0		<= 32'b0;	
		TEMP_LOC4_1		<= 32'b0;	
	
		VCC				<= 32'b0;
		VCCIO_SDM		<= 32'b0;
		VCCPT			<= 32'b0;
		VCCRCORE		<= 32'b0;
		VCCH_SDM		<= 32'b0;
		VCCL_SDM		<= 32'b0;
		VCCADC			<= 32'b0;
	end
	else if((cur_state == READ_DAT) && dat_ok && dat_val)
		if(mb_rvld)
			case(rd_type)
			2'b00	:ID_CODE	<= mb_rdat;
			2'b01	:CHIP_ID	<= {CHIP_ID[31:0],mb_rdat[31:0]};
			2'b10	:begin
						VCC			<= (rsp_num == 4'h1) ? mb_rdat : VCC		;	
						VCCIO_SDM	<= (rsp_num == 4'h2) ? mb_rdat : VCCIO_SDM	;
						VCCPT		<= (rsp_num == 4'h3) ? mb_rdat : VCCPT		;
						VCCRCORE	<= (rsp_num == 4'h4) ? mb_rdat : VCCRCORE	;
						VCCH_SDM	<= (rsp_num == 4'h5) ? mb_rdat : VCCH_SDM	;
						VCCL_SDM	<= (rsp_num == 4'h6) ? mb_rdat : VCCL_SDM	;
						VCCADC		<= (rsp_num == 4'h7) ? mb_rdat : VCCADC		;
					end
			2'b11	:begin
						TEMP_LOC0_0	<= (cnt1 == 4'h1 && rsp_num == 4'h1) ? mb_rdat : TEMP_LOC0_0;
						TEMP_LOC1_0	<= (cnt1 == 4'h2 && rsp_num == 4'h1) ? mb_rdat : TEMP_LOC1_0;
						TEMP_LOC1_1	<= (cnt1 == 4'h2 && rsp_num == 4'h2) ? mb_rdat : TEMP_LOC1_1;
						TEMP_LOC2_0	<= (cnt1 == 4'h3 && rsp_num == 4'h1) ? mb_rdat : TEMP_LOC2_0;
						TEMP_LOC2_1	<= (cnt1 == 4'h3 && rsp_num == 4'h2) ? mb_rdat : TEMP_LOC2_1;
						TEMP_LOC3_0	<= (cnt1 == 4'h4 && rsp_num == 4'h1) ? mb_rdat : TEMP_LOC3_0;
						TEMP_LOC3_1	<= (cnt1 == 4'h4 && rsp_num == 4'h2) ? mb_rdat : TEMP_LOC3_1;
						TEMP_LOC4_0	<= (cnt1 == 4'h0 && rsp_num == 4'h1) ? mb_rdat : TEMP_LOC4_0;
						TEMP_LOC4_1	<= (cnt1 == 4'h0 && rsp_num == 4'h2) ? mb_rdat : TEMP_LOC4_1;
					end
		endcase
		else;
	else;
end



endmodule



