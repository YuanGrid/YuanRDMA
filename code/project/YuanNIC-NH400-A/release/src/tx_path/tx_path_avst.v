`resetall
`default_nettype none
`timescale 1ns / 1ps

module tx_path_avst #(parameter DATA_WIDTH = 512,
	             parameter ST_EMTY_WIDTH = 6,          // EOP空字节计数位宽
				 parameter CHANNEL_WIDTH = 11,        // 信道号位宽
                 parameter SEG_WIDTH   = 64,         // 每段位宽 (16 segments × 64 bits)
                 parameter SEG_CNT     = 2*DATA_WIDTH / SEG_WIDTH,
                 parameter EMPTY_WIDTH = 48          ) // EOP空字节计数位宽
                 (
	input wire [DATA_WIDTH-1:0]         s_avst_data,
    input wire [ST_EMTY_WIDTH-1:0]      s_avst_emty,
	input wire [CHANNEL_WIDTH-1:0]      s_avst_channel,
    input wire                          s_avst_valid,
    input wire                          s_avst_eof,
	input wire 						    s_avst_sof,
	output wire                         s_avst_ready,

	output wire [1024-1:0]              tx_mac_data,
    output wire [SEG_CNT-1:0]           tx_mac_inframe,
    output wire [EMPTY_WIDTH-1:0]       tx_mac_eop_empty,
    output wire                         tx_mac_valid,
	input  wire                         tx_mac_ready,
	
	input  wire 						dma_clk,
	input  wire 						dma_rst,
	input  wire 						mac_tx_clk,
	input  wire 						mac_tx_rst

	);

	
	(* keep *)wire [2*DATA_WIDTH-1:0]    ofifo_axis_tdata	;
	(* keep *)wire [2*DATA_WIDTH/8-1:0]  ofifo_axis_tkeep	;
	(* keep *)wire                       ofifo_axis_tvalid  ;
	(* keep *)wire                       ofifo_axis_tlast	;
	(* keep *)wire                       ofifo_axis_tready  ;

	reg            [2*DATA_WIDTH-1:0] 	 s_axis_tdata_i		;
	reg            [2*DATA_WIDTH/8-1:0]  s_axis_tkeep_i		;
	reg                               	 s_axis_tvalid_i	;
	reg                               	 s_axis_tlast_i		;
	wire                              	 s_axis_tready_i	;
	reg   								 s_axis_cnt			;

	assign s_avst_ready = s_axis_tready_i;

	always @(posedge dma_clk ) begin
		if(dma_rst)
			s_axis_cnt <= 1'b0;
		else if(s_avst_valid & s_avst_eof)
			s_axis_cnt <= 1'b0;
		else if(s_avst_valid)
			s_axis_cnt <= ~s_axis_cnt;
	end

	always @(posedge dma_clk) begin
		if(dma_rst)
			s_axis_tvalid_i <= 1'b0;
		else if(s_avst_valid & (s_axis_cnt | s_avst_eof) & s_axis_tready_i)
			s_axis_tvalid_i <= 1'b1;
		else if(s_axis_tvalid_i & s_axis_tready_i)
			s_axis_tvalid_i <= 1'b0;
	end

	always @(posedge dma_clk ) begin
		if(s_avst_valid & (!s_axis_cnt)) 
			s_axis_tdata_i[0+:DATA_WIDTH] 				<= swap_endian_64(s_avst_data);

		if(s_avst_valid & (s_axis_cnt | s_avst_sof)) 
			s_axis_tdata_i[DATA_WIDTH+:DATA_WIDTH] 		<= swap_endian_64(s_avst_data);
	end

	always @(posedge dma_clk ) begin
		s_axis_tkeep_i[0+:2*DATA_WIDTH/8]<= {2*DATA_WIDTH/8{1'b0}};

		if(s_avst_valid & s_avst_eof)
			s_axis_tkeep_i[0+:ST_EMTY_WIDTH+1] <= 8'd128-s_avst_emty-((~s_axis_cnt)<<6);
		else if(s_avst_valid)
			s_axis_tkeep_i[0+:ST_EMTY_WIDTH+1] <= 0;
	end

	always @(posedge dma_clk) begin
		if(dma_rst)
			s_axis_tlast_i <= 1'b0;
		else if(s_avst_valid & s_avst_eof & s_axis_tready_i)
			s_axis_tlast_i <= 1'b1;
		else if(s_axis_tvalid_i & s_axis_tready_i & s_axis_tlast_i)
			s_axis_tlast_i <= 1'b0;
	end
/******************************debug************************************************/
	(* keep *)wire  		[31:0]		rx_dma_vcnt;
	(* keep *)wire  		[31:0]		tx_mac_vcnt;
    cnt#(.WIDTH(32))cnt_u0(.clear(dma_rst),    .clk(dma_clk),    .vld(s_avst_valid),     .step({15'b0,s_avst_eof}),    .cnt(rx_dma_vcnt));
    cnt#(.WIDTH(32))cnt_u1(.clear(mac_tx_rst), .clk(mac_tx_clk), .vld(ofifo_axis_tvalid),.step({15'b0,ofifo_axis_tlast}),.cnt(tx_mac_vcnt));

/******************************模块例化************************************************/
	tx_channel_fifo #(.DATA_WIDTH(1024)) tx_channelfifo_inst(
		.s_clk			( dma_clk		),
		.s_rst			( dma_rst		),
		.s_axis_tdata	( s_axis_tdata_i	),   // (pre_fifo_axis_tdata),
		.s_axis_tkeep	( s_axis_tkeep_i	),   // (pre_fifo_axis_tkeep),
		.s_axis_tvalid	( s_axis_tvalid_i ),  // (pre_fifo_axis_tvalid),
		.s_axis_tlast	( s_axis_tlast_i	),   // (pre_fifo_axis_tlast),
		.s_axis_tready	( s_axis_tready_i ),  // (pre_fifo_axis_tready),
	
		.m_clk			( mac_tx_clk			), //(m_clk),
		.m_rst			( mac_tx_rst			), // (m_rst),
		.m_axis_tdata	( ofifo_axis_tdata	), //(post_fifo_axis_tdata),
		.m_axis_tkeep	( ofifo_axis_tkeep	), //(post_fifo_axis_tkeep),
		.m_axis_tvalid	( ofifo_axis_tvalid	), //(post_fifo_axis_tvalid),
		.m_axis_tlast	( ofifo_axis_tlast	),  // (post_fifo_axis_tlast),
		.m_axis_tready	( ofifo_axis_tready	) //(post_fifo_axis_tready),

	);
	
	axis_to_fmac_tx_fullpipeline #(.DATA_WIDTH(1024),       // 数据位宽
								   .SEG_WIDTH(64)         // 每段位宽 (16 segments × 64 bits)
								   ) tx_axis2fmac_inst(
		.clk			( mac_tx_clk),
		.rst_n			( ~mac_tx_rst ),                   // 异步复位低有效

		// AXI-Stream 输入接口
		.s_axis_tdata	( ofifo_axis_tdata	),
		.s_axis_tkeep	( ofifo_axis_tkeep	),
		.s_axis_tvalid	( ofifo_axis_tvalid	),
		.s_axis_tready	( ofifo_axis_tready	),
		.s_axis_tlast	( ofifo_axis_tlast	),

		// F-tile TX Segmented Client 输出接口
		.i_tx_mac_data	   (tx_mac_data	   	),
		.i_tx_mac_inframe  (tx_mac_inframe  ),
		.i_tx_mac_eop_empty(tx_mac_eop_empty),
		.i_tx_mac_valid    (tx_mac_valid    ),
		.o_tx_mac_ready    (tx_mac_ready    )
	);

	function [511:0] swap_endian_64;
		input [511:0] din;
		integer i;
		reg [7:0] tmp_data;
		begin : swap_block_64
			for(i=0;i<64;i=i+1)
				swap_endian_64[(63-i)*8 +:8] = din[i*8 +:8];
		end
	endfunction

	function [63:0] emty2keep_64;
		input [5:0] din;
		reg [63:0] tmp_keep;
		begin : emty2keep_64_blk
			case(din)
				6'd0  : tmp_keep = 64'hffff_ffff_ffff_ffff;
				6'd1  : tmp_keep = 64'h7fff_ffff_ffff_ffff;
				6'd2  : tmp_keep = 64'h3fff_ffff_ffff_ffff;
				6'd3  : tmp_keep = 64'h1fff_ffff_ffff_ffff;
				6'd4  : tmp_keep = 64'h0fff_ffff_ffff_ffff;
				6'd5  : tmp_keep = 64'h07ff_ffff_ffff_ffff;
				6'd6  : tmp_keep = 64'h03ff_ffff_ffff_ffff;
				6'd7  : tmp_keep = 64'h01ff_ffff_ffff_ffff;
				6'd8  : tmp_keep = 64'h00ff_ffff_ffff_ffff;
				6'd9  : tmp_keep = 64'h007f_ffff_ffff_ffff;
				6'd10 : tmp_keep = 64'h003f_ffff_ffff_ffff;
				6'd11 : tmp_keep = 64'h001f_ffff_ffff_ffff;
				6'd12 : tmp_keep = 64'h000f_ffff_ffff_ffff;
				6'd13 : tmp_keep = 64'h0007_ffff_ffff_ffff;
				6'd14 : tmp_keep = 64'h0003_ffff_ffff_ffff;
				6'd15 : tmp_keep = 64'h0001_ffff_ffff_ffff;
				6'd16 : tmp_keep = 64'h0000_ffff_ffff_ffff;
				6'd17 : tmp_keep = 64'h0000_7fff_ffff_ffff;
				6'd18 : tmp_keep = 64'h0000_3fff_ffff_ffff;
				6'd19 : tmp_keep = 64'h0000_1fff_ffff_ffff;
				6'd20 : tmp_keep = 64'h0000_0fff_ffff_ffff;
				6'd21 : tmp_keep = 64'h0000_07ff_ffff_ffff;
				6'd22 : tmp_keep = 64'h0000_03ff_ffff_ffff;
				6'd23 : tmp_keep = 64'h0000_01ff_ffff_ffff;
				6'd24 : tmp_keep = 64'h0000_00ff_ffff_ffff;
				6'd25 : tmp_keep = 64'h0000_007f_ffff_ffff;
				6'd26 : tmp_keep = 64'h0000_003f_ffff_ffff;
				6'd27 : tmp_keep = 64'h0000_001f_ffff_ffff;
				6'd28 : tmp_keep = 64'h0000_000f_ffff_ffff;
				6'd29 : tmp_keep = 64'h0000_0007_ffff_ffff;
				6'd30 : tmp_keep = 64'h0000_0003_ffff_ffff;
				6'd31 : tmp_keep = 64'h0000_0001_ffff_ffff;
				6'd32 : tmp_keep = 64'h0000_0000_ffff_ffff;				
				6'd33 : tmp_keep = 64'h0000_0000_7fff_ffff;
				6'd34 : tmp_keep = 64'h0000_0000_3fff_ffff;
				6'd35 : tmp_keep = 64'h0000_0000_1fff_ffff;
				6'd36 : tmp_keep = 64'h0000_0000_0fff_ffff;
				6'd37 : tmp_keep = 64'h0000_0000_07ff_ffff;
				6'd38 : tmp_keep = 64'h0000_0000_03ff_ffff;
				6'd39 : tmp_keep = 64'h0000_0000_01ff_ffff;
				6'd40 : tmp_keep = 64'h0000_0000_00ff_ffff;
				6'd41 : tmp_keep = 64'h0000_0000_007f_ffff;
				6'd42 : tmp_keep = 64'h0000_0000_003f_ffff;
				6'd43 : tmp_keep = 64'h0000_0000_001f_ffff;
				6'd44 : tmp_keep = 64'h0000_0000_000f_ffff;
				6'd45 : tmp_keep = 64'h0000_0000_0007_ffff;
				6'd46 : tmp_keep = 64'h0000_0000_0003_ffff;
				6'd47 : tmp_keep = 64'h0000_0000_0001_ffff;
				6'd48 : tmp_keep = 64'h0000_0000_0000_ffff;
				6'd49 : tmp_keep = 64'h0000_0000_0000_7fff;
				6'd50 : tmp_keep = 64'h0000_0000_0000_3fff;
				6'd51 : tmp_keep = 64'h0000_0000_0000_1fff;
				6'd52 : tmp_keep = 64'h0000_0000_0000_0fff;
				6'd53 : tmp_keep = 64'h0000_0000_0000_07ff;
				6'd54 : tmp_keep = 64'h0000_0000_0000_03ff;
				6'd55 : tmp_keep = 64'h0000_0000_0000_01ff;
				6'd56 : tmp_keep = 64'h0000_0000_0000_00ff;
				6'd57 : tmp_keep = 64'h0000_0000_0000_007f;
				6'd58 : tmp_keep = 64'h0000_0000_0000_003f;
				6'd59 : tmp_keep = 64'h0000_0000_0000_001f;
				6'd60 : tmp_keep = 64'h0000_0000_0000_000f;
				6'd61 : tmp_keep = 64'h0000_0000_0000_0007;
				6'd62 : tmp_keep = 64'h0000_0000_0000_0003;
				6'd63 : tmp_keep = 64'h0000_0000_0000_0001;
				default : tmp_keep = 64'h0000_0000_0000_0000;
			endcase
			emty2keep_64 = tmp_keep;	
		end
	endfunction
	
endmodule
`resetall