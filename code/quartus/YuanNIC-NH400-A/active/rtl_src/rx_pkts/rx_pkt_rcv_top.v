`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/03/31 16:28:41
// Design Name: 
// Module Name: rx_pkt_rcv_top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////  

module rx_pkt_rcv_top#(
    parameter                       DATA_W      = 1024,
    parameter                       FLOW_NUM    = 10240,
    parameter                       STREAM_ID_W = 13
)
(
    input   [27:0]                  s_avm_addr ,
    input                           s_avm_read ,
    input                           s_avm_write,
    input   [31:0]                  s_avm_wdat ,
    output                          s_avm_wait ,
    output  [31:0]                  s_avm_rdat ,
    output                          s_avm_rvld ,
    output  [1:0]                   s_avm_rspo ,
    output                          s_avm_wrsp ,
    input                           s_axis_rx0_tvalid,
    input   [DATA_W-1:0]            s_axis_rx0_tdata,
    input   [$clog2(DATA_W/8)-1:0]  s_axis_rx0_tkeep,
    input                           s_axis_rx0_tlast,
    input   [3-1:0]                 s_axis_rx0_tuser_err,
    input   [64-1:0]                s_axis_rx0_ttime,
    input                           s_axis_rx1_tvalid,
    input   [DATA_W-1:0]            s_axis_rx1_tdata,
    input   [$clog2(DATA_W/8)-1:0]  s_axis_rx1_tkeep,
    input                           s_axis_rx1_tlast,
    input   [3-1:0]                 s_axis_rx1_tuser_err,
    input   [64-1:0]                s_axis_rx1_ttime,
    output                          m_axis_rx_tvalid,
    output  [DATA_W-1:0]            m_axis_rx_tdata,
    output  [$clog2(DATA_W/8)-1:0]  m_axis_rx_tkeep,
    output                          m_axis_rx_tlast,
    input                           m_axis_rx_tready,  
    output                          timestamp_delay_type  ,
    input                           cnt_clear_en          , 
    output  [63:0]                  eth_fcs_err_cnt       , 
    output  [63:0]                  eth_mfmd_err_cnt      , 
    output  [63:0]                  eth_under_over_err_cnt, 
    output  [63:0]                  eth_plen_err_cnt      , 
    output  [63:0]                  eth_fifo_full_err_cnt , 
    input                           link_up0,
    input                           mac_rstn,
    input                           axil_rstn,
    input                           pcie_rstn,
    input   [63:0]                  time_stamp, 
    input                           axis_aclk,
    input                           axil_aclk,
    input                           mac_clk
);

    localparam  FILTER_NUM = 4;

    wire    [63:0]                  stream_pkt_rdata           [1:0];
    wire    [63:0]                  stream_byt_rdata           [1:0];
    wire    [63:0]                  reg_rx_pkts_recv           [1:0];
    wire    [63:0]                  reg_rx_bytes_recv          [1:0];
    wire    [63:0]                  reg_rx_pkts_drop           [1:0];
    wire    [63:0]                  reg_rx_bytes_drop          [1:0];
    wire    [63:0]                  reg_rx_pkts_err            [1:0];
    wire    [63:0]                  reg_rx_bytes_err           [1:0];
    wire    [63:0]                  reg_rx_pkts_ip_checksum_err[1:0];
    wire    [63:0]                  reg_rx_pkt_sum_delay       [1:0];
    wire    [63:0]                  reg_rx_pkt_max_delay       [1:0];
    wire    [63:0]                  reg_rx_pkt_min_delay       [1:0];
    wire    [63:0]                  reg_rx_pkt_max_jitter      [1:0];
    wire    [63:0]                  reg_rx_pkt_min_jitter      [1:0];
    wire    [63:0]                  reg_rx_pkt_sum_jitter      [1:0];
    wire    [63:0]                  reg_rx_pkt_start_time      [1:0];
    wire    [63:0]                  reg_rx_pkt_stop_time       [1:0];
    wire    [63:0]                  rx_pkt_sum_delay           [1:0];
    wire    [63:0]                  rx_pkt_max_delay           [1:0];
    wire    [63:0]                  rx_pkt_min_delay           [1:0];
    wire    [63:0]                  reg_rocev2_pkt_rt_delay    [1:0];
    wire    [63:0]                  reg_rocev2_pkt_max_delay   [1:0];
    wire    [63:0]                  reg_rocev2_pkt_min_delay   [1:0];
    wire    [63:0]                  reg_rocev2_pkt_max_jitter  [1:0];
    wire    [63:0]                  reg_rocev2_pkt_min_jitter  [1:0];
    wire    [63:0]                  reg_rocev2_pkt_rt_jitter   [1:0];
    wire    [63:0]                  reg_rocev2_rx_pkts         [1:0];
    wire    [63:0]                  reg_rocev2_pkt_sum_delay   [1:0];
    wire    [63:0]                  reg_rocev2_pkt_sum_jitter  [1:0];
    wire    [31:0]                  stream_max_delay           [1:0];
    wire    [31:0]                  stream_min_delay           [1:0];
    wire    [63:0]                  stream_sum_delay           [1:0];
    wire    [31:0]                  stream_max_jitter          [1:0];
    wire    [31:0]                  stream_min_jitter          [1:0];
    wire    [63:0]                  stream_sum_jitter          [1:0];
    reg     [63:0]                  stream_pkt_rdata_sum           ;
    reg     [63:0]                  stream_byt_rdata_sum           ;
    reg     [63:0]                  reg_rx_pkts_recv_sum           ;
    reg     [63:0]                  reg_rx_bytes_recv_sum          ;
    reg     [63:0]                  reg_rx_pkts_drop_sum           ;
    reg     [63:0]                  reg_rx_bytes_drop_sum          ;
    reg     [63:0]                  reg_rx_pkts_err_sum            ;
    reg     [63:0]                  reg_rx_bytes_err_sum           ;
    reg     [63:0]                  reg_rx_pkts_ip_checksum_err_sum;
    reg     [63:0]                  reg_rx_pkt_sum_delay_sum       ;
    reg     [63:0]                  reg_rx_pkt_max_delay_sum       ;
    reg     [63:0]                  reg_rx_pkt_min_delay_sum       ;
    reg     [63:0]                  reg_rx_pkt_max_jitter_sum      ;
    reg     [63:0]                  reg_rx_pkt_min_jitter_sum      ;
    reg     [63:0]                  reg_rx_pkt_sum_jitter_sum      ;
    reg     [63:0]                  reg_rx_pkt_start_time_sum      ;
    reg     [63:0]                  reg_rx_pkt_stop_time_sum       ;
    reg     [63:0]                  rx_pkt_sum_delay_sum           ;
    reg     [63:0]                  rx_pkt_max_delay_sum           ;
    reg     [63:0]                  rx_pkt_min_delay_sum           ;
    reg     [63:0]                  reg_rocev2_pkt_rt_delay_sum    ;
    reg     [63:0]                  reg_rocev2_pkt_max_delay_sum   ;
    reg     [63:0]                  reg_rocev2_pkt_min_delay_sum   ;
    reg     [63:0]                  reg_rocev2_pkt_max_jitter_sum  ;
    reg     [63:0]                  reg_rocev2_pkt_min_jitter_sum  ;
    reg     [63:0]                  reg_rocev2_pkt_rt_jitter_sum   ;
    reg     [63:0]                  reg_rocev2_rx_pkts_sum         ;
    reg     [63:0]                  reg_rocev2_pkt_sum_delay_sum   ;
    reg     [63:0]                  reg_rocev2_pkt_sum_jitter_sum  ;
    reg     [31:0]                  stream_max_delay_sum           ;
    reg     [31:0]                  stream_min_delay_sum           ;
    reg     [63:0]                  stream_sum_delay_sum           ;
    reg     [31:0]                  stream_max_jitter_sum          ;
    reg     [31:0]                  stream_min_jitter_sum          ;
    reg     [63:0]                  stream_sum_jitter_sum          ;

    wire                            stream_pkt_r_req      ;
    wire     [15:0]                 stream_pkt_id_r       ;
    wire                            stream_pkt_rst        ;
    wire                            rx_all_en             ;
    wire                            work_mode             ;
    wire                            rx_pkt_en             ;
    wire                            rx_pkt_mix_en         ;
    wire                            rx_pkt_filter_en      ;
    wire                            rx_pkt_filter_type    ;
    wire                            test_mode             ;
    wire     [31:0]                 timestamp_delay_value ;
    wire     [31:0]             policy_vld;
    wire   [    FILTER_NUM-1:0] process_mode;             
    wire   [    FILTER_NUM-1:0] field_relation;  
    wire   [    FILTER_NUM-1:0] dmac_en           ;
    wire   [    FILTER_NUM-1:0] dmac_mode         ;
    wire   [ 48*FILTER_NUM-1:0] dmac_mask         ;
    wire   [ 48*FILTER_NUM-1:0] dmac_value        ;
    wire   [    FILTER_NUM-1:0] smac_en           ;
    wire   [    FILTER_NUM-1:0] smac_mode         ;
    wire   [ 48*FILTER_NUM-1:0] smac_mask         ;
    wire   [ 48*FILTER_NUM-1:0] smac_value        ;
    wire   [    FILTER_NUM-1:0] vlanid_en         ;
    wire   [    FILTER_NUM-1:0] vlanid_mode       ;
    wire   [ 12*FILTER_NUM-1:0] vlanid_mask       ;
    wire   [ 12*FILTER_NUM-1:0] vlanid_value      ;
    wire   [    FILTER_NUM-1:0] protocol_en       ;        
    wire   [    FILTER_NUM-1:0] protocol_mode     ;        
    wire   [  8*FILTER_NUM-1:0] protocol_mask     ;        
    wire   [  8*FILTER_NUM-1:0] protocol_value    ;        
    wire   [    FILTER_NUM-1:0] sipv4_en          ;    
    wire   [    FILTER_NUM-1:0] sipv4_mode        ;    
    wire   [ 32*FILTER_NUM-1:0] sipv4_mask        ;    
    wire   [ 32*FILTER_NUM-1:0] sipv4_value       ;    
    wire   [    FILTER_NUM-1:0] dipv4_en          ;             
    wire   [    FILTER_NUM-1:0] dipv4_mode        ;             
    wire   [ 32*FILTER_NUM-1:0] dipv4_mask        ;             
    wire   [ 32*FILTER_NUM-1:0] dipv4_value       ;             
    wire   [    FILTER_NUM-1:0] sipv6_en          ;             
    wire   [    FILTER_NUM-1:0] sipv6_mode        ;             
    wire   [128*FILTER_NUM-1:0] sipv6_mask        ;             
    wire   [128*FILTER_NUM-1:0] sipv6_value       ;             
    wire   [    FILTER_NUM-1:0] dipv6_en          ;             
    wire   [    FILTER_NUM-1:0] dipv6_mode        ;             
    wire   [128*FILTER_NUM-1:0] dipv6_mask        ;             
    wire   [128*FILTER_NUM-1:0] dipv6_value       ;             
    wire   [    FILTER_NUM-1:0] sport_en          ;             
    wire   [    FILTER_NUM-1:0] sport_mode        ;             
    wire   [ 16*FILTER_NUM-1:0] sport_mask        ;             
    wire   [ 16*FILTER_NUM-1:0] sport_value       ;             
    wire   [    FILTER_NUM-1:0] dport_en          ;             
    wire   [    FILTER_NUM-1:0] dport_mode        ;             
    wire   [ 16*FILTER_NUM-1:0] dport_mask        ;             
    wire   [ 16*FILTER_NUM-1:0] dport_value       ;             
    wire   [    FILTER_NUM-1:0] pkt_length_en     ;             
    wire   [    FILTER_NUM-1:0] pkt_length_mode   ;             
    wire   [ 16*FILTER_NUM-1:0] pkt_length_mask   ;             
    wire   [ 16*FILTER_NUM-1:0] pkt_length_value  ;             
    wire   [ 64*FILTER_NUM-1:0] filter_match_pkts [1:0] ;
    wire   [ 64*FILTER_NUM-1:0] filter_match_bytes [1:0] ;
    reg    [ 64*FILTER_NUM-1:0] filter_match_pkts_sum  ;
    reg    [ 64*FILTER_NUM-1:0] filter_match_bytes_sum  ;

    wire                            m_axis_rx0_tvalid     ;
    wire    [DATA_W-1:0]            m_axis_rx0_tdata      ;
    wire    [$clog2(DATA_W/8)-1:0]  m_axis_rx0_tkeep      ;
    wire                            m_axis_rx0_tlast      ;
    wire    [3:0]                   m_axis_rx0_tuser_err  ;
    wire                            m_axis_rx1_tvalid     ;
    wire    [DATA_W-1:0]            m_axis_rx1_tdata      ;
    wire    [$clog2(DATA_W/8)-1:0]  m_axis_rx1_tkeep      ;
    wire                            m_axis_rx1_tlast      ;
    wire    [3:0]                   m_axis_rx1_tuser_err  ;

    always @(posedge mac_clk) begin
        reg_rx_pkts_recv_sum           <= sum64(reg_rx_pkts_recv           [1],reg_rx_pkts_recv           [0]);
        reg_rx_bytes_recv_sum          <= sum64(reg_rx_bytes_recv          [1],reg_rx_bytes_recv          [0]);
        reg_rx_pkts_drop_sum           <= sum64(reg_rx_pkts_drop           [1],reg_rx_pkts_drop           [0]);
        reg_rx_bytes_drop_sum          <= sum64(reg_rx_bytes_drop          [1],reg_rx_bytes_drop          [0]);
        reg_rx_pkts_err_sum            <= sum64(reg_rx_pkts_err            [1],reg_rx_pkts_err            [0]);
        reg_rx_bytes_err_sum           <= sum64(reg_rx_bytes_err           [1],reg_rx_bytes_err           [0]);
        reg_rx_pkts_ip_checksum_err_sum<= sum64(reg_rx_pkts_ip_checksum_err[1],reg_rx_pkts_ip_checksum_err[0]);
        reg_rx_pkt_sum_delay_sum       <= sum64(reg_rx_pkt_sum_delay       [1],reg_rx_pkt_sum_delay       [0]);
        reg_rx_pkt_max_delay_sum       <= max64(reg_rx_pkt_max_delay       [1],reg_rx_pkt_max_delay       [0]);
        reg_rx_pkt_min_delay_sum       <= min64(reg_rx_pkt_min_delay       [1],reg_rx_pkt_min_delay       [0]);
        reg_rx_pkt_max_jitter_sum      <= max64(reg_rx_pkt_max_jitter      [1],reg_rx_pkt_max_jitter      [0]);
        reg_rx_pkt_min_jitter_sum      <= min64(reg_rx_pkt_min_jitter      [1],reg_rx_pkt_min_jitter      [0]);
        reg_rx_pkt_sum_jitter_sum      <= sum64(reg_rx_pkt_sum_jitter      [1],reg_rx_pkt_sum_jitter      [0]);
        reg_rx_pkt_start_time_sum      <= min64(reg_rx_pkt_start_time      [1],reg_rx_pkt_start_time      [0]);
        reg_rx_pkt_stop_time_sum       <= max64(reg_rx_pkt_stop_time       [1],reg_rx_pkt_stop_time       [0]);
        rx_pkt_sum_delay_sum           <= sum64(rx_pkt_sum_delay           [1],rx_pkt_sum_delay           [0]);
        rx_pkt_max_delay_sum           <= max64(rx_pkt_max_delay           [1],rx_pkt_max_delay           [0]);
        rx_pkt_min_delay_sum           <= min64(rx_pkt_min_delay           [1],rx_pkt_min_delay           [0]);
        reg_rocev2_pkt_rt_delay_sum    <= sum64(reg_rocev2_pkt_rt_delay    [1],reg_rocev2_pkt_rt_delay    [0]);
        reg_rocev2_pkt_max_delay_sum   <= max64(reg_rocev2_pkt_max_delay   [1],reg_rocev2_pkt_max_delay   [0]);
        reg_rocev2_pkt_min_delay_sum   <= min64(reg_rocev2_pkt_min_delay   [1],reg_rocev2_pkt_min_delay   [0]);
        reg_rocev2_pkt_max_jitter_sum  <= max64(reg_rocev2_pkt_max_jitter  [1],reg_rocev2_pkt_max_jitter  [0]);
        reg_rocev2_pkt_min_jitter_sum  <= min64(reg_rocev2_pkt_min_jitter  [1],reg_rocev2_pkt_min_jitter  [0]);
        reg_rocev2_pkt_rt_jitter_sum   <= sum64(reg_rocev2_pkt_rt_jitter   [1],reg_rocev2_pkt_rt_jitter   [0]);
        reg_rocev2_rx_pkts_sum         <= sum64(reg_rocev2_rx_pkts         [1],reg_rocev2_rx_pkts         [0]);
        reg_rocev2_pkt_sum_delay_sum   <= sum64(reg_rocev2_pkt_sum_delay   [1],reg_rocev2_pkt_sum_delay   [0]);
        reg_rocev2_pkt_sum_jitter_sum  <= sum64(reg_rocev2_pkt_sum_jitter  [1],reg_rocev2_pkt_sum_jitter  [0]);
    end 
    always @(posedge axil_aclk) begin
        stream_pkt_rdata_sum           <= sum64(stream_pkt_rdata           [1],stream_pkt_rdata           [0]);
        stream_byt_rdata_sum           <= sum64(stream_byt_rdata           [1],stream_byt_rdata           [0]);
        stream_max_delay_sum           <= max32(stream_max_delay           [1],stream_max_delay           [0]);
        stream_min_delay_sum           <= min32(stream_min_delay           [1],stream_min_delay           [0]);
        stream_sum_delay_sum           <= sum64(stream_sum_delay           [1],stream_sum_delay           [0]);
        stream_max_jitter_sum          <= max32(stream_max_jitter          [1],stream_max_jitter          [0]);
        stream_min_jitter_sum          <= min32(stream_min_jitter          [1],stream_min_jitter          [0]);
        stream_sum_jitter_sum          <= sum64(stream_sum_jitter          [1],stream_sum_jitter          [0]);
    end

generate
    for(genvar i = 0; i < FILTER_NUM; i = i + 1) begin: gen_filter_match_x_sum
        always @(posedge mac_clk) begin
            filter_match_pkts_sum [64*i +: 64] <= sum64(filter_match_pkts     [1][64*i +: 64], filter_match_pkts     [0][64*i +: 64]);
            filter_match_bytes_sum[64*i +: 64] <= sum64(filter_match_bytes    [1][64*i +: 64], filter_match_bytes    [0][64*i +: 64]);
        end   
    end
endgenerate

    rx_pkt_pkg #(
        .CMAC_ID                    (0                      ),
        .DATA_W                     (DATA_W                 ),
        .FLOW_NUM                   (FLOW_NUM               ),
        .STREAM_ID_W                (STREAM_ID_W            ),
        .FILTER_NUM                 (FILTER_NUM)
    ) 
    u1_rx_pkt_pkg_inst 
    (
        .s_axis_rx_tvalid           (s_axis_rx0_tvalid      ),
        .s_axis_rx_tdata            (s_axis_rx0_tdata       ),
        .s_axis_rx_tkeep            (s_axis_rx0_tkeep       ),
        .s_axis_rx_tlast            (s_axis_rx0_tlast       ),
        .s_axis_rx_tuser_err        (s_axis_rx0_tuser_err   ),
        .s_axis_rx_ttime            (s_axis_rx0_ttime       ),
        .m_axis_rx_tvalid           (m_axis_rx0_tvalid      ),
        .m_axis_rx_tdata            (m_axis_rx0_tdata       ),
        .m_axis_rx_tkeep            (m_axis_rx0_tkeep       ),
        .m_axis_rx_tlast            (m_axis_rx0_tlast       ),
        .m_axis_rx_tuser_err        (m_axis_rx0_tuser_err   ),
        .stream_pkt_rdata           (stream_pkt_rdata           [0]),
        .stream_byt_rdata           (stream_byt_rdata           [0]),
        .reg_rx_pkts_recv           (reg_rx_pkts_recv           [0]),
        .reg_rx_bytes_recv          (reg_rx_bytes_recv          [0]),
        .reg_rx_pkts_drop           (reg_rx_pkts_drop           [0]),
        .reg_rx_bytes_drop          (reg_rx_bytes_drop          [0]),
        .reg_rx_pkts_err            (reg_rx_pkts_err            [0]),
        .reg_rx_bytes_err           (reg_rx_bytes_err           [0]),
        .reg_rx_pkts_ip_checksum_err(reg_rx_pkts_ip_checksum_err[0]),
        .reg_rx_pkt_sum_delay       (reg_rx_pkt_sum_delay       [0]),
        .reg_rx_pkt_max_delay       (reg_rx_pkt_max_delay       [0]),
        .reg_rx_pkt_min_delay       (reg_rx_pkt_min_delay       [0]),
        .reg_rx_pkt_max_jitter      (reg_rx_pkt_max_jitter      [0]),
        .reg_rx_pkt_min_jitter      (reg_rx_pkt_min_jitter      [0]),
        .reg_rx_pkt_sum_jitter      (reg_rx_pkt_sum_jitter      [0]),
        .reg_rx_pkt_start_time      (reg_rx_pkt_start_time      [0]),
        .reg_rx_pkt_stop_time       (reg_rx_pkt_stop_time       [0]),
        .rx_pkt_sum_delay           (rx_pkt_sum_delay           [0]),
        .rx_pkt_max_delay           (rx_pkt_max_delay           [0]),
        .rx_pkt_min_delay           (rx_pkt_min_delay           [0]),
        .reg_rocev2_pkt_rt_delay    (reg_rocev2_pkt_rt_delay    [0]),
        .reg_rocev2_pkt_max_delay   (reg_rocev2_pkt_max_delay   [0]),
        .reg_rocev2_pkt_min_delay   (reg_rocev2_pkt_min_delay   [0]),
        .reg_rocev2_pkt_max_jitter  (reg_rocev2_pkt_max_jitter  [0]),
        .reg_rocev2_pkt_min_jitter  (reg_rocev2_pkt_min_jitter  [0]),
        .reg_rocev2_pkt_rt_jitter   (reg_rocev2_pkt_rt_jitter   [0]),
        .reg_rocev2_rx_pkts         (reg_rocev2_rx_pkts         [0]),
        .reg_rocev2_pkt_sum_delay   (reg_rocev2_pkt_sum_delay   [0]),
        .reg_rocev2_pkt_sum_jitter  (reg_rocev2_pkt_sum_jitter  [0]),
        .stream_max_delay           (stream_max_delay           [0]), 
        .stream_min_delay           (stream_min_delay           [0]), 
        .stream_sum_delay           (stream_sum_delay           [0]), 
        .stream_max_jitter          (stream_max_jitter          [0]),
        .stream_min_jitter          (stream_min_jitter          [0]),
        .stream_sum_jitter          (stream_sum_jitter          [0]),
        .stream_pkt_r_req           (stream_pkt_r_req               ),
        .stream_pkt_id_r            (stream_pkt_id_r                ),
        .stream_pkt_rst             (stream_pkt_rst                 ),
        .rx_all_en                  (rx_all_en                      ),
        .work_mode                  (work_mode                      ),
        .rx_pkt_en                  (rx_pkt_en                      ),
        .rx_pkt_mix_en              (rx_pkt_mix_en                  ),
        .rx_pkt_filter_en           (rx_pkt_filter_en               ),
        .rx_pkt_filter_type         (rx_pkt_filter_type             ),
        .test_mode                  (test_mode                      ),
        .timestamp_delay_type       (timestamp_delay_type           ),
        .timestamp_delay_value      (timestamp_delay_value          ),
        .policy_vld        (policy_vld      ), 
        .process_mode      (process_mode    ),
        .field_relation    (field_relation  ),             
        .dmac_en           (dmac_en         ),
        .dmac_mode         (dmac_mode       ),
        .dmac_mask         (dmac_mask       ),
        .dmac_value        (dmac_value      ),
        .smac_en           (smac_en         ),
        .smac_mode         (smac_mode       ),
        .smac_mask         (smac_mask       ),
        .smac_value        (smac_value      ),
        .vlanid_en         (vlanid_en       ),
        .vlanid_mode       (vlanid_mode     ),
        .vlanid_mask       (vlanid_mask     ),
        .vlanid_value      (vlanid_value    ),
        .protocol_en       (protocol_en     ),        
        .protocol_mode     (protocol_mode   ),        
        .protocol_mask     (protocol_mask   ),        
        .protocol_value    (protocol_value  ),        
        .sipv4_en          (sipv4_en        ),    
        .sipv4_mode        (sipv4_mode      ),    
        .sipv4_mask        (sipv4_mask      ),    
        .sipv4_value       (sipv4_value     ),    
        .dipv4_en          (dipv4_en        ),             
        .dipv4_mode        (dipv4_mode      ),             
        .dipv4_mask        (dipv4_mask      ),             
        .dipv4_value       (dipv4_value     ),             
        .sipv6_en          (sipv6_en        ),             
        .sipv6_mode        (sipv6_mode      ),             
        .sipv6_mask        (sipv6_mask      ),             
        .sipv6_value       (sipv6_value     ),             
        .dipv6_en          (dipv6_en        ),             
        .dipv6_mode        (dipv6_mode      ),             
        .dipv6_mask        (dipv6_mask      ),             
        .dipv6_value       (dipv6_value     ),             
        .sport_en          (sport_en        ),             
        .sport_mode        (sport_mode      ),             
        .sport_mask        (sport_mask      ),             
        .sport_value       (sport_value     ),             
        .dport_en          (dport_en        ),             
        .dport_mode        (dport_mode      ),             
        .dport_mask        (dport_mask      ),             
        .dport_value       (dport_value     ),             
        .pkt_length_en     (pkt_length_en      ),             
        .pkt_length_mode   (pkt_length_mode    ),             
        .pkt_length_mask   (pkt_length_mask    ),             
        .pkt_length_value  (pkt_length_value   ),             
        .filter_match_pkts (filter_match_pkts[0]  ),
        .filter_match_bytes(filter_match_bytes[0] ),
        .link_up                    (link_up0               ),
        .time_stamp                 (time_stamp             ),
        .cmac_clk                   (mac_clk                ),
        .cmac_rstn                  (mac_rstn           ),
        .axis_rstn                  (mac_rstn           ), 
        .axil_aclk                  (axil_aclk              )
    );

    rx_pkt_pkg #(
        .CMAC_ID                    (1),
        .DATA_W                     (DATA_W                 ),
        .FLOW_NUM                   (FLOW_NUM               ),
        .STREAM_ID_W                (STREAM_ID_W            ),
        .FILTER_NUM                 (FILTER_NUM)
    ) 
    u2_rx_pkt_pkg_inst1 
    (
        .s_axis_rx_tvalid           (s_axis_rx1_tvalid      ),
        .s_axis_rx_tdata            (s_axis_rx1_tdata       ),
        .s_axis_rx_tkeep            (s_axis_rx1_tkeep       ),
        .s_axis_rx_tlast            (s_axis_rx1_tlast       ),
        .s_axis_rx_tuser_err        (s_axis_rx1_tuser_err   ),
        .s_axis_rx_ttime            (s_axis_rx1_ttime       ),
        .m_axis_rx_tvalid           (m_axis_rx1_tvalid      ),
        .m_axis_rx_tdata            (m_axis_rx1_tdata       ),
        .m_axis_rx_tkeep            (m_axis_rx1_tkeep       ),
        .m_axis_rx_tlast            (m_axis_rx1_tlast       ),
        .m_axis_rx_tuser_err        (m_axis_rx1_tuser_err   ),
        .stream_pkt_rdata           (stream_pkt_rdata           [1]),
        .stream_byt_rdata           (stream_byt_rdata           [1]),
        .reg_rx_pkts_recv           (reg_rx_pkts_recv           [1]),
        .reg_rx_bytes_recv          (reg_rx_bytes_recv          [1]),
        .reg_rx_pkts_drop           (reg_rx_pkts_drop           [1]),
        .reg_rx_bytes_drop          (reg_rx_bytes_drop          [1]),
        .reg_rx_pkts_err            (reg_rx_pkts_err            [1]),
        .reg_rx_bytes_err           (reg_rx_bytes_err           [1]),
        .reg_rx_pkts_ip_checksum_err(reg_rx_pkts_ip_checksum_err[1]),
        .reg_rx_pkt_sum_delay       (reg_rx_pkt_sum_delay       [1]),
        .reg_rx_pkt_max_delay       (reg_rx_pkt_max_delay       [1]),
        .reg_rx_pkt_min_delay       (reg_rx_pkt_min_delay       [1]),
        .reg_rx_pkt_max_jitter      (reg_rx_pkt_max_jitter      [1]),
        .reg_rx_pkt_min_jitter      (reg_rx_pkt_min_jitter      [1]),
        .reg_rx_pkt_sum_jitter      (reg_rx_pkt_sum_jitter      [1]),
        .reg_rx_pkt_start_time      (reg_rx_pkt_start_time      [1]),
        .reg_rx_pkt_stop_time       (reg_rx_pkt_stop_time       [1]),
        .rx_pkt_sum_delay           (rx_pkt_sum_delay           [1]),
        .rx_pkt_max_delay           (rx_pkt_max_delay           [1]),
        .rx_pkt_min_delay           (rx_pkt_min_delay           [1]),
        .reg_rocev2_pkt_rt_delay    (reg_rocev2_pkt_rt_delay    [1]),
        .reg_rocev2_pkt_max_delay   (reg_rocev2_pkt_max_delay   [1]),
        .reg_rocev2_pkt_min_delay   (reg_rocev2_pkt_min_delay   [1]),
        .reg_rocev2_pkt_max_jitter  (reg_rocev2_pkt_max_jitter  [1]),
        .reg_rocev2_pkt_min_jitter  (reg_rocev2_pkt_min_jitter  [1]),
        .reg_rocev2_pkt_rt_jitter   (reg_rocev2_pkt_rt_jitter   [1]),
        .reg_rocev2_rx_pkts         (reg_rocev2_rx_pkts         [1]),
        .reg_rocev2_pkt_sum_delay   (reg_rocev2_pkt_sum_delay   [1]),
        .reg_rocev2_pkt_sum_jitter  (reg_rocev2_pkt_sum_jitter  [1]),
        .stream_max_delay           (stream_max_delay           [1]), 
        .stream_min_delay           (stream_min_delay           [1]), 
        .stream_sum_delay           (stream_sum_delay           [1]), 
        .stream_max_jitter          (stream_max_jitter          [1]),
        .stream_min_jitter          (stream_min_jitter          [1]),
        .stream_sum_jitter          (stream_sum_jitter          [1]),
        .stream_pkt_r_req           (stream_pkt_r_req               ),
        .stream_pkt_id_r            (stream_pkt_id_r                ),
        .stream_pkt_rst             (stream_pkt_rst                 ),
        .rx_all_en                  (rx_all_en                      ),
        .work_mode                  (work_mode                      ),
        .rx_pkt_en                  (rx_pkt_en                      ),
        .rx_pkt_mix_en              (rx_pkt_mix_en                  ),
        .rx_pkt_filter_en           (rx_pkt_filter_en               ),
        .rx_pkt_filter_type         (rx_pkt_filter_type             ),
        .test_mode                  (test_mode                      ),
        .timestamp_delay_type       (timestamp_delay_type           ),
        .timestamp_delay_value      (timestamp_delay_value          ),
        .policy_vld        (policy_vld      ), 
        .process_mode      (process_mode    ),
        .field_relation    (field_relation  ),             
        .dmac_en           (dmac_en         ),
        .dmac_mode         (dmac_mode       ),
        .dmac_mask         (dmac_mask       ),
        .dmac_value        (dmac_value      ),
        .smac_en           (smac_en         ),
        .smac_mode         (smac_mode       ),
        .smac_mask         (smac_mask       ),
        .smac_value        (smac_value      ),
        .vlanid_en         (vlanid_en       ),
        .vlanid_mode       (vlanid_mode     ),
        .vlanid_mask       (vlanid_mask     ),
        .vlanid_value      (vlanid_value    ),
        .protocol_en       (protocol_en     ),        
        .protocol_mode     (protocol_mode   ),        
        .protocol_mask     (protocol_mask   ),        
        .protocol_value    (protocol_value  ),        
        .sipv4_en          (sipv4_en        ),    
        .sipv4_mode        (sipv4_mode      ),    
        .sipv4_mask        (sipv4_mask      ),    
        .sipv4_value       (sipv4_value     ),    
        .dipv4_en          (dipv4_en        ),             
        .dipv4_mode        (dipv4_mode      ),             
        .dipv4_mask        (dipv4_mask      ),             
        .dipv4_value       (dipv4_value     ),             
        .sipv6_en          (sipv6_en        ),             
        .sipv6_mode        (sipv6_mode      ),             
        .sipv6_mask        (sipv6_mask      ),             
        .sipv6_value       (sipv6_value     ),             
        .dipv6_en          (dipv6_en        ),             
        .dipv6_mode        (dipv6_mode      ),             
        .dipv6_mask        (dipv6_mask      ),             
        .dipv6_value       (dipv6_value     ),             
        .sport_en          (sport_en        ),             
        .sport_mode        (sport_mode      ),             
        .sport_mask        (sport_mask      ),             
        .sport_value       (sport_value     ),             
        .dport_en          (dport_en        ),             
        .dport_mode        (dport_mode      ),             
        .dport_mask        (dport_mask      ),             
        .dport_value       (dport_value     ),             
        .pkt_length_en     (pkt_length_en      ),             
        .pkt_length_mode   (pkt_length_mode    ),             
        .pkt_length_mask   (pkt_length_mask    ),             
        .pkt_length_value  (pkt_length_value   ),             
        .filter_match_pkts (filter_match_pkts[1]  ),
        .filter_match_bytes(filter_match_bytes[1] ),
        .link_up                    (link_up0               ),
        .time_stamp                 (time_stamp             ),
        .cmac_clk                   (mac_clk               ),
        .cmac_rstn                  (mac_rstn           ),
        .axis_rstn                  (mac_rstn           ), 
        .axil_aclk                  (axil_aclk              )
    );

    rx_mux_nto1#
    (
        .RCV_NUM                    (2                      ),
        .DATA_W                     (1024                   )
    )
    u3_rx_mux_nto1
    (    
        .s_clk                      (mac_clk        ),
        .m_clk                      (axis_aclk      ),
        .rst_n                      (mac_rstn   ),
        .m_rst_n                    (pcie_rstn   ),
        .s_axis_rx_tvalid           ({m_axis_rx1_tvalid,m_axis_rx0_tvalid}),
        .s_axis_rx_tdata            ({m_axis_rx1_tdata,m_axis_rx0_tdata}),
        .s_axis_rx_tkeep            ({m_axis_rx1_tkeep,m_axis_rx0_tkeep}),
        .s_axis_rx_tlast            ({m_axis_rx1_tlast,m_axis_rx0_tlast}),
        .s_axis_rx_tuser            ({m_axis_rx1_tuser_err,m_axis_rx0_tuser_err}),
        .m_axis_rx_tvalid           (m_axis_rx_tvalid       ),
        .m_axis_rx_tdata            (m_axis_rx_tdata        ),
        .m_axis_rx_tkeep            (m_axis_rx_tkeep        ),
        .m_axis_rx_tlast            (m_axis_rx_tlast        ),
        .m_axis_rx_tready           (m_axis_rx_tready       ),
        .cnt_clear_en               (cnt_clear_en           ),
        .eth_fcs_err_cnt            (eth_fcs_err_cnt        ),
        .eth_mfmd_err_cnt           (eth_mfmd_err_cnt       ),
        .eth_under_over_err_cnt     (eth_under_over_err_cnt ),
        .eth_plen_err_cnt           (eth_plen_err_cnt       ),
        .eth_fifo_full_err_cnt      (eth_fifo_full_err_cnt  )
    );

    packet_adapter_register #(
        .FILTER_NUM                 (FILTER_NUM)
    )
    u4_reg_inst (
        .s_avm_addr                         (s_avm_addr                 ),
        .s_avm_read                         (s_avm_read                 ),
        .s_avm_write                        (s_avm_write                ),
        .s_avm_wdat                         (s_avm_wdat                 ),
        .s_avm_wait                         (s_avm_wait                 ),
        .s_avm_rdat                         (s_avm_rdat                 ),
        .s_avm_rvld                         (s_avm_rvld                 ),
        .s_avm_rspo                         (s_avm_rspo                 ),
        .s_avm_wrsp                         (s_avm_wrsp                 ),
        .stream_pkt_rdata                   (stream_pkt_rdata_sum           ),
        .stream_byt_rdata                   (stream_byt_rdata_sum           ),
        .reg_rx_pkts_recv                   (reg_rx_pkts_recv_sum           ),
        .reg_rx_bytes_recv                  (reg_rx_bytes_recv_sum          ),
        .reg_rx_pkts_drop                   (reg_rx_pkts_drop_sum           ),
        .reg_rx_bytes_drop                  (reg_rx_bytes_drop_sum          ),
        .reg_rx_pkts_err                    (reg_rx_pkts_err_sum            ),
        .reg_rx_bytes_err                   (reg_rx_bytes_err_sum           ),
        .reg_rx_pkts_ip_checksum_err        (reg_rx_pkts_ip_checksum_err_sum),
        .reg_rx_pkt_sum_delay               (reg_rx_pkt_sum_delay_sum       ),
        .reg_rx_pkt_max_delay               (reg_rx_pkt_max_delay_sum       ),
        .reg_rx_pkt_min_delay               (reg_rx_pkt_min_delay_sum       ),
        .reg_rx_pkt_max_jitter              (reg_rx_pkt_max_jitter_sum      ),
        .reg_rx_pkt_min_jitter              (reg_rx_pkt_min_jitter_sum      ),
        .reg_rx_pkt_sum_jitter              (reg_rx_pkt_sum_jitter_sum      ),
        .reg_rx_pkt_start_time              (reg_rx_pkt_start_time_sum      ),
        .reg_rx_pkt_stop_time               (reg_rx_pkt_stop_time_sum       ),
        .rx_pkt_sum_delay                   (rx_pkt_sum_delay_sum           ),
        .rx_pkt_max_delay                   (rx_pkt_max_delay_sum           ),
        .rx_pkt_min_delay                   (rx_pkt_min_delay_sum           ),
        .reg_rocev2_pkt_rt_delay            (reg_rocev2_pkt_rt_delay_sum    ),
        .reg_rocev2_pkt_max_delay           (reg_rocev2_pkt_max_delay_sum   ),
        .reg_rocev2_pkt_min_delay           (reg_rocev2_pkt_min_delay_sum   ),
        .reg_rocev2_pkt_max_jitter          (reg_rocev2_pkt_max_jitter_sum  ),
        .reg_rocev2_pkt_min_jitter          (reg_rocev2_pkt_min_jitter_sum  ),
        .reg_rocev2_pkt_rt_jitter           (reg_rocev2_pkt_rt_jitter_sum   ),
        .reg_rocev2_rx_pkts                 (reg_rocev2_rx_pkts_sum         ),
        .reg_rocev2_pkt_sum_delay           (reg_rocev2_pkt_sum_delay_sum   ),
        .reg_rocev2_pkt_sum_jitter          (reg_rocev2_pkt_sum_jitter_sum  ),
        .stream_max_delay                   (stream_max_delay_sum           ), 
        .stream_min_delay                   (stream_min_delay_sum           ), 
        .stream_sum_delay                   (stream_sum_delay_sum           ), 
        .stream_max_jitter                  (stream_max_jitter_sum          ),
        .stream_min_jitter                  (stream_min_jitter_sum          ),
        .stream_sum_jitter                  (stream_sum_jitter_sum          ),

        .stream_pkt_r_req                   (stream_pkt_r_req               ),
        .stream_pkt_id_r                    (stream_pkt_id_r                ),
        .stream_pkt_rst                     (stream_pkt_rst                 ),
        .rx_all_en                          (rx_all_en                      ),
        .work_mode                          (work_mode                      ),
        .rx_pkt_en                          (rx_pkt_en                      ),
        .rx_pkt_mix_en                      (rx_pkt_mix_en                  ),
        .rx_pkt_filter_en                   (rx_pkt_filter_en               ),
        .rx_pkt_filter_type                 (rx_pkt_filter_type             ),
        .test_mode                          (test_mode                      ),
        .timestamp_delay_type               (timestamp_delay_type           ),
        .timestamp_delay_value              (timestamp_delay_value          ),
        .policy_vld        (policy_vld      ),
        .process_mode      (process_mode    ),
        .field_relation    (field_relation  ),             
        .dmac_en           (dmac_en         ),
        .dmac_mode         (dmac_mode       ),
        .dmac_mask         (dmac_mask       ),
        .dmac_value        (dmac_value      ),
        .smac_en           (smac_en         ),
        .smac_mode         (smac_mode       ),
        .smac_mask         (smac_mask       ),
        .smac_value        (smac_value      ),
        .vlanid_en         (vlanid_en       ),
        .vlanid_mode       (vlanid_mode     ),
        .vlanid_mask       (vlanid_mask     ),
        .vlanid_value      (vlanid_value    ),
        .protocol_en       (protocol_en     ),        
        .protocol_mode     (protocol_mode   ),        
        .protocol_mask     (protocol_mask   ),        
        .protocol_value    (protocol_value  ),        
        .sipv4_en          (sipv4_en        ),    
        .sipv4_mode        (sipv4_mode      ),    
        .sipv4_mask        (sipv4_mask      ),    
        .sipv4_value       (sipv4_value     ),    
        .dipv4_en          (dipv4_en        ),             
        .dipv4_mode        (dipv4_mode      ),             
        .dipv4_mask        (dipv4_mask      ),             
        .dipv4_value       (dipv4_value     ),             
        .sipv6_en          (sipv6_en        ),             
        .sipv6_mode        (sipv6_mode      ),             
        .sipv6_mask        (sipv6_mask      ),             
        .sipv6_value       (sipv6_value     ),             
        .dipv6_en          (dipv6_en        ),             
        .dipv6_mode        (dipv6_mode      ),             
        .dipv6_mask        (dipv6_mask      ),             
        .dipv6_value       (dipv6_value     ),             
        .sport_en          (sport_en        ),             
        .sport_mode        (sport_mode      ),             
        .sport_mask        (sport_mask      ),             
        .sport_value       (sport_value     ),             
        .dport_en          (dport_en        ),             
        .dport_mode        (dport_mode      ),             
        .dport_mask        (dport_mask      ),             
        .dport_value       (dport_value     ),             
        .pkt_length_en     (pkt_length_en      ),             
        .pkt_length_mode   (pkt_length_mode    ),             
        .pkt_length_mask   (pkt_length_mask    ),             
        .pkt_length_value  (pkt_length_value   ),             
        .filter_match_pkts (filter_match_pkts_sum  ),
        .filter_match_bytes(filter_match_bytes_sum ),
        .axil_aclk                          (axil_aclk                      ),
        .axis_aclk                          (mac_clk                        ),
        .axil_aresetn                       (axil_rstn                      )
    );

    function [63:0] sum64;
        input [63:0] a; 
        input [63:0] b; 
        begin
            sum64 = a+b;
        end
    endfunction

    function [31:0] sum32;
        input [31:0] a; 
        input [31:0] b; 
        begin
            sum32 = a+b;
        end
    endfunction

    function [63:0] max64;
        input [63:0] a; 
        input [63:0] b; 
        begin
            if(a>b)
                max64 = a;
            else
                max64 = b;
        end
    endfunction

    function [31:0] max32;
        input [31:0] a; 
        input [31:0] b; 
        begin
            if(a>b)
                max32 = a;
            else
                max32 = b;
        end
    endfunction

    function [63:0] min64;
        input [63:0] a; 
        input [63:0] b; 
        begin
            if(a>b)
                min64 = b;
            else 
                min64 = a;
        end
    endfunction

    function [31:0] min32;
        input [31:0] a; 
        input [31:0] b; 
        begin
            if(a>b)
                min32 = b;
            else 
                min32 = a;
        end
    endfunction

endmodule
