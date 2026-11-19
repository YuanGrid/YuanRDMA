// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

module tx_channel_fifo #
(
    parameter DEPTH = 65536, // in octets,128*512
    parameter DATA_WIDTH = 1024,
    parameter KEEP_ENABLE = (DATA_WIDTH>8),
    parameter KEEP_WIDTH = ((DATA_WIDTH+7)/8),
    parameter LAST_ENABLE = 1,
    parameter ID_ENABLE = 0,
    parameter ID_WIDTH = 8,
    parameter DEST_ENABLE = 0,
    parameter DEST_WIDTH = 8,
    parameter USER_ENABLE = 0,
    parameter USER_WIDTH = 1,
    parameter RAM_PIPELINE = 1,
    parameter OUTPUT_FIFO_ENABLE = 0,
    parameter FRAME_FIFO = 1,
    parameter USER_BAD_FRAME_VALUE = 1'b1,
    parameter USER_BAD_FRAME_MASK = 1'b1,
    parameter DROP_OVERSIZE_FRAME = FRAME_FIFO,
    parameter DROP_BAD_FRAME = 0,
    parameter DROP_WHEN_FULL = 0,
    parameter MARK_WHEN_FULL = 0,
    parameter PAUSE_ENABLE = 0,
    parameter FRAME_PAUSE = FRAME_FIFO
)(
	input  wire    						  s_clk,
	input  wire    						  s_rst,
	input  wire [DATA_WIDTH-1 : 0 ]       s_axis_tdata,   // (pre_fifo_axis_tdata),
    input  wire [(DATA_WIDTH+7)/8 - 1: 0] s_axis_tkeep,   // (pre_fifo_axis_tkeep),
    input  wire    						  s_axis_tvalid,  // (pre_fifo_axis_tvalid),
	input  wire    						  s_axis_tlast,   // (pre_fifo_axis_tlast),
    output wire    						  s_axis_tready,  // (pre_fifo_axis_tready),
	
	input  wire   						  m_clk, //(m_clk),
    input  wire   						  m_rst, // (m_rst),
    output wire [DATA_WIDTH-1 : 0 ]       m_axis_tdata, //(post_fifo_axis_tdata),
    output wire [(DATA_WIDTH+7)/8 - 1: 0] m_axis_tkeep, //(post_fifo_axis_tkeep),
    output wire    						  m_axis_tvalid, //(post_fifo_axis_tvalid),
    output wire    						  m_axis_tlast,  // (post_fifo_axis_tlast),
	input  wire    						  m_axis_tready //(post_fifo_axis_tready),	
    
	);
    
    (* keep *) wire [$clog2(DEPTH):0] s_status_depth;
    (* keep *) wire [$clog2(DEPTH):0] s_status_depth_commit;
    (* keep *) wire                   s_status_overflow;
    (* keep *) wire                   s_status_bad_frame;
    (* keep *) wire                   s_status_good_frame;
    (* keep *) wire [$clog2(DEPTH):0] m_status_depth;
    (* keep *) wire [$clog2(DEPTH):0] m_status_depth_commit;
    (* keep *) wire                   m_status_overflow;
    (* keep *) wire                   m_status_bad_frame;
    (* keep *) wire                   m_status_good_frame;


axis_async_fifo #(
    .DEPTH(DEPTH),
    .DATA_WIDTH(DATA_WIDTH),
    .LAST_ENABLE(1),
    .ID_ENABLE(ID_ENABLE),
    .ID_WIDTH(ID_WIDTH),
    .DEST_ENABLE(DEST_ENABLE),
    .DEST_WIDTH(DEST_WIDTH),
    .USER_ENABLE(USER_ENABLE),
    .USER_WIDTH(USER_WIDTH),
    .RAM_PIPELINE(RAM_PIPELINE),
    .OUTPUT_FIFO_ENABLE(OUTPUT_FIFO_ENABLE),
    .FRAME_FIFO(FRAME_FIFO),
    .USER_BAD_FRAME_VALUE(USER_BAD_FRAME_VALUE),
    .USER_BAD_FRAME_MASK(USER_BAD_FRAME_MASK),
    .DROP_OVERSIZE_FRAME(DROP_OVERSIZE_FRAME),
    .DROP_BAD_FRAME(DROP_BAD_FRAME),
    .DROP_WHEN_FULL(DROP_WHEN_FULL),
    .MARK_WHEN_FULL(MARK_WHEN_FULL),
    .PAUSE_ENABLE(PAUSE_ENABLE),
    .FRAME_PAUSE(FRAME_PAUSE)
)
fifo_inst (
    // AXI input
    .s_clk(s_clk),
    .s_rst(s_rst),
    .s_axis_tdata(s_axis_tdata),
    .s_axis_tkeep(s_axis_tkeep),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tready(s_axis_tready),
    .s_axis_tlast(s_axis_tlast),
    .s_axis_tid(),
    .s_axis_tdest(),
    .s_axis_tuser(),
    // AXI output
    .m_clk(m_clk),
    .m_rst(m_rst),
    .m_axis_tdata(m_axis_tdata),
    .m_axis_tkeep(m_axis_tkeep),
    .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tready(m_axis_tready),
    .m_axis_tlast(m_axis_tlast),
    .m_axis_tid(),
    .m_axis_tdest(),
    .m_axis_tuser(),
    
    .s_status_depth         (  s_status_depth        ),
    .s_status_depth_commit  (  s_status_depth_commit ),
    .s_status_overflow      (  s_status_overflow     ),
    .s_status_bad_frame     (  s_status_bad_frame    ),
    .s_status_good_frame    (  s_status_good_frame   ),
    .m_status_depth         (  m_status_depth        ),
    .m_status_depth_commit  (  m_status_depth_commit ),
    .m_status_overflow      (  m_status_overflow     ),
    .m_status_bad_frame     (  m_status_bad_frame    ),
    .m_status_good_frame    (  m_status_good_frame   )
    
);



endmodule
`resetall