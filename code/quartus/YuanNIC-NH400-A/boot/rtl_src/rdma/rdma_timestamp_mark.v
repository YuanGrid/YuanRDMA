`resetall
`default_nettype none
`timescale 1ns / 1ps

module rdma_timestamp_mark(
    input wire clk,
    input wire rst_n,

    input  wire            s_axis_tvalid,
    input  wire [512-1:0]  s_axis_tdata,
    input  wire            s_axis_tlast,
    input  wire [6-1:0]    s_axis_tkeep,
    input  wire [11-1:0]   s_axis_tchannel,
    output wire            s_axis_tready,

    output wire            m_axis_tvalid,
    output wire [512-1:0]  m_axis_tdata,
    output wire            m_axis_tlast,
    output wire [6-1:0]    m_axis_tkeep,
    output wire [11-1:0]   m_axis_tchannel,
    input  wire            m_axis_tready,

    input  wire [63:0]     time_stamp,
    input  wire            rdma_tx_timestamp_en
);

localparam DATA_WIDTH = 512;
localparam KEEP_WIDTH = 6;

wire axis_tvalid                  ;
wire [DATA_WIDTH-1:0] axis_tdata  ;
wire axis_tlast                   ;
wire  [KEEP_WIDTH-1:0] axis_tkeep ;
wire  [11-1:0]         axis_tchannel ;
wire axis_tready                  ;
wire axis_tuser_sop               ;
wire axis_tuser_ipv6              ;
wire [13:0]  axis_tuser_len       ;
wire axis_tuser_insert            ;


stream_info_head u_stream_info_head (
    .axis_aclk               ( clk                             ),
    .rst_n                   ( rst_n                                 ),
    .s_axis_tvalid           ( s_axis_tvalid                         ),
    .s_axis_tdata            ( s_axis_tdata         [DATA_WIDTH-1:0] ),
    .s_axis_tlast            ( s_axis_tlast                          ),
    .s_axis_tkeep            ( s_axis_tkeep         [KEEP_WIDTH-1:0] ),
    .s_axis_tchannel         ( s_axis_tchannel                       ),
    .s_axis_tready           ( s_axis_tready                         ),

    .m_axis_tvalid           ( axis_tvalid                         ),
    .m_axis_tdata            ( axis_tdata         [DATA_WIDTH-1:0] ),
    .m_axis_tlast            ( axis_tlast                          ),
    .m_axis_tkeep            ( axis_tkeep         [KEEP_WIDTH-1:0] ),
    .m_axis_tchannel         ( axis_tchannel      [11-1:0]         ),
    .m_axis_tready           ( axis_tready                         ),
    .m_axis_tuser_sop        ( axis_tuser_sop                      ),
    .m_axis_tuser_ipv6       ( axis_tuser_ipv6                     ),
    .m_axis_tuser_len        ( axis_tuser_len     [13:0]           ),
    .m_axis_tuser_insert     ( axis_tuser_insert                   )
);

stream_mark_rocev2 #(.DATA_WIDTH(DATA_WIDTH),.KEEP_WIDTH ( KEEP_WIDTH))
 u_stream_mark_rocev2 (
    .axis_aclk               ( clk                               ),
    .rst_n                   ( rst_n                                   ),
    .s_axis_tvalid           ( axis_tvalid                           ),
    .s_axis_tdata            ( axis_tdata           [DATA_WIDTH-1:0] ),
    .s_axis_tlast            ( axis_tlast                            ),
    .s_axis_tkeep            ( axis_tkeep           [KEEP_WIDTH-1:0] ),
    .s_axis_tchannel         ( axis_tchannel        [11-1:0]         ),
    .s_axis_tuser_sop        ( axis_tuser_sop                        ),
    .s_axis_tuser_ipv6       ( axis_tuser_ipv6                       ),
    .s_axis_tuser_insert     ( axis_tuser_insert                     ),
    .s_axis_tuser_len        ( axis_tuser_len       [13:0]           ),
    .s_axis_tuser_stamp_en   ( rdma_tx_timestamp_en                  ),
    .s_axis_tready           ( axis_tready                           ),

    .m_axis_tvalid           ( m_axis_tvalid                           ),
    .m_axis_tdata            ( m_axis_tdata           [DATA_WIDTH-1:0] ),
    .m_axis_tlast            ( m_axis_tlast                            ),
    .m_axis_tkeep            ( m_axis_tkeep           [KEEP_WIDTH-1:0] ),
    .m_axis_tchannel         ( m_axis_tchannel        [11-1:0]         ),
    .m_axis_tready           ( m_axis_tready                           ),

    .time_stamp              ( time_stamp             [63:0]           )
);

endmodule
`resetall



