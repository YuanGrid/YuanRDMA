`timescale 1ns/1ps
module packet_adapter_register #(
    parameter FILTER_NUM = 4
) (
    input           [27:0]                  s_avm_addr ,
    input                                   s_avm_read ,
    input                                   s_avm_write,
    input           [31:0]                  s_avm_wdat ,
    output                                  s_avm_wait ,
    output          [31:0]                  s_avm_rdat ,
    output                                  s_avm_rvld ,
    output          [1:0]                   s_avm_rspo ,
    output                                  s_avm_wrsp ,
    input           [63:0]                  stream_pkt_rdata,
    input           [63:0]                  stream_byt_rdata,
    input           [63:0]                  reg_rx_pkts_recv,
    input           [63:0]                  reg_rx_bytes_recv,
    input           [63:0]                  reg_rx_pkts_drop,
    input           [63:0]                  reg_rx_bytes_drop,
    input           [63:0]                  reg_rx_pkts_err,
    input           [63:0]                  reg_rx_bytes_err,
    input           [63:0]                  reg_rx_pkts_ip_checksum_err,
    input           [63:0]                  reg_rx_pkt_sum_delay,
    input           [63:0]                  reg_rx_pkt_max_delay,
    input           [63:0]                  reg_rx_pkt_min_delay,
    input           [63:0]                  reg_rx_pkt_max_jitter,
    input           [63:0]                  reg_rx_pkt_min_jitter,
    input           [63:0]                  reg_rx_pkt_sum_jitter,
    input           [63:0]                  reg_rx_pkt_start_time,
    input           [63:0]                  reg_rx_pkt_stop_time,
    input           [63:0]                  rx_pkt_sum_delay,
    input           [63:0]                  rx_pkt_max_delay,
    input           [63:0]                  rx_pkt_min_delay,
    input           [63:0]                  reg_rocev2_pkt_rt_delay,
    input           [63:0]                  reg_rocev2_pkt_max_delay,
    input           [63:0]                  reg_rocev2_pkt_min_delay,
    input           [63:0]                  reg_rocev2_pkt_max_jitter,
    input           [63:0]                  reg_rocev2_pkt_min_jitter,
    input           [63:0]                  reg_rocev2_pkt_rt_jitter,
    input           [63:0]                  reg_rocev2_rx_pkts,
    input           [63:0]                  reg_rocev2_pkt_sum_delay,
    input           [63:0]                  reg_rocev2_pkt_sum_jitter,
    input           [31:0]                  stream_max_delay, 
    input           [31:0]                  stream_min_delay, 
    input           [63:0]                  stream_sum_delay, 
    input           [31:0]                  stream_max_jitter,
    input           [31:0]                  stream_min_jitter,
    input           [63:0]                  stream_sum_jitter,
    output  reg                             stream_pkt_r_req,
    output  reg     [15:0]                  stream_pkt_id_r,
    output                                  stream_pkt_rst,
    output  reg                             rx_all_en,
    output  reg                             work_mode,
    output  reg                             rx_pkt_en,
    output  reg                             rx_pkt_mix_en,
    output  reg                             rx_pkt_filter_en,
    output  reg                             rx_pkt_filter_type,
    output  reg                             test_mode,
    output  reg                             timestamp_delay_type,
    output  reg     [31:0]                  timestamp_delay_value,

  output reg  [             31 :0]    policy_vld        ,//=                 32'b0,
  output reg  [    FILTER_NUM-1:0]    process_mode      ,//=  {    FILTER_NUM{1'b0}},             
  output reg  [    FILTER_NUM-1:0]    field_relation    ,//=  {    FILTER_NUM{1'b0}},             

  output reg  [    FILTER_NUM-1:0]    dmac_en           ,//=  {    FILTER_NUM{1'b0}},
  output reg  [    FILTER_NUM-1:0]    dmac_mode         ,//=  {    FILTER_NUM{1'b0}},
  output reg  [ 48*FILTER_NUM-1:0]    dmac_mask         ,//=  { 48*FILTER_NUM{1'b0}},
  output reg  [ 48*FILTER_NUM-1:0]    dmac_value        ,//=  { 48*FILTER_NUM{1'b0}},
  output reg  [    FILTER_NUM-1:0]    smac_en           ,//=  {    FILTER_NUM{1'b0}},
  output reg  [    FILTER_NUM-1:0]    smac_mode         ,//=  {    FILTER_NUM{1'b0}},
  output reg  [ 48*FILTER_NUM-1:0]    smac_mask         ,//=  { 48*FILTER_NUM{1'b0}},
  output reg  [ 48*FILTER_NUM-1:0]    smac_value        ,//=  { 48*FILTER_NUM{1'b0}},
  output reg  [    FILTER_NUM-1:0]    vlanid_en         ,//=  {    FILTER_NUM{1'b0}},
  output reg  [    FILTER_NUM-1:0]    vlanid_mode       ,//=  {    FILTER_NUM{1'b0}},
  output reg  [ 12*FILTER_NUM-1:0]    vlanid_mask       ,//=  { 12*FILTER_NUM{1'b0}},
  output reg  [ 12*FILTER_NUM-1:0]    vlanid_value      ,//=  { 12*FILTER_NUM{1'b0}},
  output reg  [    FILTER_NUM-1:0]    protocol_en       ,//=  {    FILTER_NUM{1'b0}},        
  output reg  [    FILTER_NUM-1:0]    protocol_mode     ,//=  {    FILTER_NUM{1'b0}},        
  output reg  [  8*FILTER_NUM-1:0]    protocol_mask     ,//=  {  8*FILTER_NUM{1'b0}},        
  output reg  [  8*FILTER_NUM-1:0]    protocol_value    ,//=  {  8*FILTER_NUM{1'b0}},        
  output reg  [    FILTER_NUM-1:0]    sipv4_en          ,//=  {    FILTER_NUM{1'b0}},    
  output reg  [    FILTER_NUM-1:0]    sipv4_mode        ,//=  {    FILTER_NUM{1'b0}},    
  output reg  [ 32*FILTER_NUM-1:0]    sipv4_mask        ,//=  { 32*FILTER_NUM{1'b0}},    
  output reg  [ 32*FILTER_NUM-1:0]    sipv4_value       ,//=  { 32*FILTER_NUM{1'b0}},    
  output reg  [    FILTER_NUM-1:0]    dipv4_en          ,//=  {    FILTER_NUM{1'b0}},             
  output reg  [    FILTER_NUM-1:0]    dipv4_mode        ,//=  {    FILTER_NUM{1'b0}},             
  output reg  [ 32*FILTER_NUM-1:0]    dipv4_mask        ,//=  { 32*FILTER_NUM{1'b0}},             
  output reg  [ 32*FILTER_NUM-1:0]    dipv4_value       ,//=  { 32*FILTER_NUM{1'b0}},             
  output reg  [    FILTER_NUM-1:0]    sipv6_en          ,//=  {    FILTER_NUM{1'b0}},             
  output reg  [    FILTER_NUM-1:0]    sipv6_mode        ,//=  {    FILTER_NUM{1'b0}},             
  output reg  [128*FILTER_NUM-1:0]    sipv6_mask        ,//=  {128*FILTER_NUM{1'b0}},             
  output reg  [128*FILTER_NUM-1:0]    sipv6_value       ,//=  {128*FILTER_NUM{1'b0}},             
  output reg  [    FILTER_NUM-1:0]    dipv6_en          ,//=  {    FILTER_NUM{1'b0}},             
  output reg  [    FILTER_NUM-1:0]    dipv6_mode        ,//=  {    FILTER_NUM{1'b0}},             
  output reg  [128*FILTER_NUM-1:0]    dipv6_mask        ,//=  {128*FILTER_NUM{1'b0}},             
  output reg  [128*FILTER_NUM-1:0]    dipv6_value       ,//=  {128*FILTER_NUM{1'b0}},             
  output reg  [    FILTER_NUM-1:0]    sport_en          ,//=  {    FILTER_NUM{1'b0}},             
  output reg  [    FILTER_NUM-1:0]    sport_mode        ,//=  {    FILTER_NUM{1'b0}},             
  output reg  [ 16*FILTER_NUM-1:0]    sport_mask        ,//=  { 16*FILTER_NUM{1'b0}},             
  output reg  [ 16*FILTER_NUM-1:0]    sport_value       ,//=  { 16*FILTER_NUM{1'b0}},             
  output reg  [    FILTER_NUM-1:0]    dport_en          ,//=  {    FILTER_NUM{1'b0}},             
  output reg  [    FILTER_NUM-1:0]    dport_mode        ,//=  {    FILTER_NUM{1'b0}},             
  output reg  [ 16*FILTER_NUM-1:0]    dport_mask        ,//=  { 16*FILTER_NUM{1'b0}},             
  output reg  [ 16*FILTER_NUM-1:0]    dport_value       ,//=  { 16*FILTER_NUM{1'b0}},             
  output reg  [    FILTER_NUM-1:0]    pkt_length_en     ,//=  {    FILTER_NUM{1'b0}},             
  output reg  [    FILTER_NUM-1:0]    pkt_length_mode   ,//=  {    FILTER_NUM{1'b0}},             
  output reg  [ 16*FILTER_NUM-1:0]    pkt_length_mask   ,//=  { 16*FILTER_NUM{1'b0}},             
  output reg  [ 16*FILTER_NUM-1:0]    pkt_length_value  ,//=  { 16*FILTER_NUM{1'b0}},             
  input       [ 64*FILTER_NUM-1:0]    filter_match_pkts ,
  input       [ 64*FILTER_NUM-1:0]    filter_match_bytes,

    input                                   axil_aclk,
    input                                   axis_aclk,
    input                                   axil_aresetn
);
    //1400000 base_addr
    localparam C_ADDR_W                     = 28;
    localparam REG_RX_PKTS_ENABLE           = 12'h000;
    localparam REG_RX_PKTS_MIXED_ENABLE     = 12'h004;
    localparam REG_RX_PKTS_CLEAR            = 12'h008;
    localparam REG_RX_PKTS_FILTER_ENABLE    = 12'h00C;
    localparam REG_RX_PKTS_FILTER_TYPE      = 12'h018;
    localparam REG_RX_PKTS_ALL_ENABLE       = 12'h200;
    localparam REG_RX_PKTS_WORK_MODE        = 12'h204;
    localparam REG_RX_FILTER_BASE           = 12'h01C;
    localparam REG_RX_FILTER_INFO           = 12'h020;
    localparam REG_RX_FILTER_DONE           = 12'h024;
    localparam REG_RX_FILTER_POLICY_EN      = 12'h028;
    localparam REG_RX_FILTER_PROCESS_MODE   = 12'h02C;
    localparam REG_RX_FILTER_FIELD_RELATION = 12'h0F0;
    localparam REG_RX_FILTER_SIP_0          = 12'h300;
    localparam REG_RX_FILTER_SIP_1          = 12'h304;
    localparam REG_RX_FILTER_SIP_2          = 12'h308;
    localparam REG_RX_FILTER_SIP_3          = 12'h30C;
    localparam REG_RX_FILTER_DIP_0          = 12'h310;
    localparam REG_RX_FILTER_DIP_1          = 12'h314;
    localparam REG_RX_FILTER_DIP_2          = 12'h318;
    localparam REG_RX_FILTER_DIP_3          = 12'h31C;
    localparam REG_RX_FILTER_SP_DP          = 12'h320;
    localparam REG_RX_FILTER_MASK           = 12'h324;
    localparam DMAC_EN             =  12'h400;
    localparam DMAC_MODE           =  12'h404;
    localparam DMAC_MASK_31_0      =  12'h408;
    localparam DMAC_MASK_47_32     =  12'h40C;
    localparam DMAC_VALUE_31_0     =  12'h410;
    localparam DMAC_VALUE_47_32    =  12'h414;
    localparam SMAC_EN             =  12'h418;
    localparam SMAC_MODE           =  12'h41C;
    localparam SMAC_MASK_31_0      =  12'h420;
    localparam SMAC_MASK_47_32     =  12'h424;
    localparam SMAC_VALUE_31_0     =  12'h428;
    localparam SMAC_VALUE_47_32    =  12'h42C;
    localparam VLANID1_EN          =  12'h430;
    localparam VLANID1_MODE        =  12'h434;
    localparam VLANID1_MASK        =  12'h438;
    localparam VLANID1_VALUE       =  12'h43C;
  //localparam VLANID2_EN          =  12'h440;
  //localparam VLANID2_MODE        =  12'h444;
  //localparam VLANID2_MASK        =  12'h448;
  //localparam VLANID2_VALUE       =  12'h44C;
    localparam PROTOCOL_EN         =  12'h450;        
    localparam PROTOCOL_MODE       =  12'h454;        
    localparam PROTOCOL_MASK       =  12'h458;        
    localparam PROTOCOL_VALUE      =  12'h45C;        
    localparam SIPV4_EN            =  12'h460;    
    localparam SIPV4_MODE          =  12'h464;    
    localparam SIPV4_MASK          =  12'h468;    
    localparam SIPV4_VALUE         =  12'h46C;    
    localparam DIPV4_EN            =  12'h470;             
    localparam DIPV4_MODE          =  12'h474;             
    localparam DIPV4_MASK          =  12'h478;             
    localparam DIPV4_VALUE         =  12'h47C;             
    localparam SIPV6_EN            =  12'h480;             
    localparam SIPV6_MODE          =  12'h484;             
    localparam SIPV6_MASK_31_0     =  12'h488;             
    localparam SIPV6_MASK_63_32    =  12'h48C;             
    localparam SIPV6_MASK_95_64    =  12'h490;             
    localparam SIPV6_MASK_127_96   =  12'h494;             
    localparam SIPV6_VALUE_31_0    =  12'h498;             
    localparam SIPV6_VALUE_63_32   =  12'h49C;             
    localparam SIPV6_VALUE_95_64   =  12'h4A0;             
    localparam SIPV6_VALUE_127_96  =  12'h4A4;             
    localparam DIPV6_EN            =  12'h4A8;             
    localparam DIPV6_MODE          =  12'h4AC;             
    localparam DIPV6_MASK_31_0     =  12'h4B0;             
    localparam DIPV6_MASK_63_32    =  12'h4B4;             
    localparam DIPV6_MASK_95_64    =  12'h4B8;             
    localparam DIPV6_MASK_127_96   =  12'h4BC;             
    localparam DIPV6_VALUE_31_0    =  12'h4C0;             
    localparam DIPV6_VALUE_63_32   =  12'h4C4;             
    localparam DIPV6_VALUE_95_64   =  12'h4C8;             
    localparam DIPV6_VALUE_127_96  =  12'h4CC;             
    localparam SPORT_EN            =  12'h4D0;             
    localparam SPORT_MODE          =  12'h4D4;             
    localparam SPORT_MASK          =  12'h4D8;             
    localparam SPORT_VALUE         =  12'h4DC;             
    localparam DPORT_EN            =  12'h4E0;             
    localparam DPORT_MODE          =  12'h4E4;             
    localparam DPORT_MASK          =  12'h4E8;             
    localparam DPORT_VALUE         =  12'h4EC;
    localparam PKT_LENGTH_EN       =  12'h4F0;             
    localparam PKT_LENGTH_MODE     =  12'h4F4;             
    localparam PKT_LENGTH_MASK     =  12'h4F8;             
    localparam PKT_LENGTH_VALUE    =  12'h4FC;
    localparam REG_RX_PKTS_RECV_LOWER       = 12'h030;
    localparam REG_RX_PKTS_RECV_UPPER       = 12'h034;
    localparam REG_RX_BYTES_RECV_LOWER      = 12'h038;
    localparam REG_RX_BYTES_RECV_UPPER      = 12'h03C;
    localparam REG_RX_PKTS_DROP_LOWER       = 12'h040;
    localparam REG_RX_PKTS_DROP_UPPER       = 12'h044;
    localparam REG_RX_BYTES_DROP_LOWER      = 12'h048;
    localparam REG_RX_BYTES_DROP_UPPER      = 12'h04C;
    localparam REG_RX_PKTS_ERR_LOWER        = 12'h050;
    localparam REG_RX_PKTS_ERR_UPPER        = 12'h054;
    localparam REG_RX_BYTES_ERR_LOWER       = 12'h058;
    localparam REG_RX_BYTES_ERR_UPPER       = 12'h05C;
    localparam REG_RX_IP_CKSUM_ERR_LOWER    = 12'h060;
    localparam REG_RX_IP_CKSUM_ERR_UPPER    = 12'h064;
    localparam REG_RX_PKTS_STREAM_LOWER     = 12'h070;
    localparam REG_RX_PKTS_STREAM_UPPER     = 12'h074;
    localparam REG_RX_BYTES_STREAM_LOWER    = 12'h078;
    localparam REG_RX_BYTES_STREAM_UPPER    = 12'h07C;  
    localparam REG_RX_ARP_QID               = 12'h090;
    localparam REG_RX_TEST_MODE             = 12'h094;
    localparam REG_RX_TIMEDELAY_TYPE        = 12'h098;  
    localparam REG_RX_TIMEDELAY_VAL         = 12'h09C; 
    localparam REG_RX_BPS_LOWER             = 12'h0A0;
    localparam REG_RX_BPS_UPPER             = 12'h0A4;
    localparam REG_RX_PPS_LOWER             = 12'h0A8;
    localparam REG_RX_PPS_UPPER             = 12'h0AC;
    localparam REG_RX_STATIME_LOWER         = 12'h0B0;
    localparam REG_RX_STATIME_UPPER         = 12'h0B4;
    localparam REG_RX_STPTIME_LOWER         = 12'h0B8;
    localparam REG_RX_STPTIME_UPPER         = 12'h0BC;

    localparam FILTER0_MATCH_PKTS_L  = 12'h380;
    localparam FILTER0_MATCH_PKTS_H  = 12'h384;
    localparam FILTER1_MATCH_PKTS_L  = 12'h388;
    localparam FILTER1_MATCH_PKTS_H  = 12'h38C;
    localparam FILTER2_MATCH_PKTS_L  = 12'h390;
    localparam FILTER2_MATCH_PKTS_H  = 12'h394;
    localparam FILTER3_MATCH_PKTS_L  = 12'h398;
    localparam FILTER3_MATCH_PKTS_H  = 12'h39C;
    localparam FILTER4_MATCH_PKTS_L  = 12'h3A0;
    localparam FILTER4_MATCH_PKTS_H  = 12'h3A4;
    localparam FILTER5_MATCH_PKTS_L  = 12'h3A8;
    localparam FILTER5_MATCH_PKTS_H  = 12'h3AC;
    localparam FILTER6_MATCH_PKTS_L  = 12'h3B0;
    localparam FILTER6_MATCH_PKTS_H  = 12'h3B4;
    localparam FILTER7_MATCH_PKTS_L  = 12'h3B8;
    localparam FILTER7_MATCH_PKTS_H  = 12'h3BC;
  
    localparam FILTER0_MATCH_BYTES_L  = 12'h300;
    localparam FILTER0_MATCH_BYTES_H  = 12'h304;
    localparam FILTER1_MATCH_BYTES_L  = 12'h308;
    localparam FILTER1_MATCH_BYTES_H  = 12'h30C;
    localparam FILTER2_MATCH_BYTES_L  = 12'h310;
    localparam FILTER2_MATCH_BYTES_H  = 12'h314;
    localparam FILTER3_MATCH_BYTES_L  = 12'h318;
    localparam FILTER3_MATCH_BYTES_H  = 12'h31C;
    localparam FILTER4_MATCH_BYTES_L  = 12'h320;
    localparam FILTER4_MATCH_BYTES_H  = 12'h324;
    localparam FILTER5_MATCH_BYTES_L  = 12'h328;
    localparam FILTER5_MATCH_BYTES_H  = 12'h32C;
    localparam FILTER6_MATCH_BYTES_L  = 12'h330;
    localparam FILTER6_MATCH_BYTES_H  = 12'h334;
    localparam FILTER7_MATCH_BYTES_L  = 12'h338;
    localparam FILTER7_MATCH_BYTES_H  = 12'h33C;

    localparam REG_RX_SUM_TIMESTAMP_LOWER   = 12'h100;
    localparam REG_RX_SUM_TIMESTAMP_UPPER   = 12'h104;
    localparam REG_RX_MAX_TIMESTAMP_LOWER   = 12'h108;
    localparam REG_RX_MAX_TIMESTAMP_UPPER   = 12'h10C;
    localparam REG_RX_MIN_TIMESTAMP_LOWER   = 12'h110;
    localparam REG_RX_MIN_TIMESTAMP_UPPER   = 12'h114;
    localparam REG_RX_SUM_JITTER_LOWER      = 12'h118;
    localparam REG_RX_SUM_JITTER_UPPER      = 12'h11C;
    localparam REG_RX_MAX_JITTER_LOWER      = 12'h120;
    localparam REG_RX_MAX_JITTER_UPPER      = 12'h124;
    localparam REG_RX_MIN_JITTER_LOWER      = 12'h128;
    localparam REG_RX_MIN_JITTER_UPPER      = 12'h12C;
    localparam REG_ROCEV2_RT_TIMESTAMP_LOWER   = 12'h130;
    localparam REG_ROCEV2_RT_TIMESTAMP_UPPER   = 12'h134;
    localparam REG_ROCEV2_MAX_TIMESTAMP_LOWER  = 12'h138;
    localparam REG_ROCEV2_MAX_TIMESTAMP_UPPER  = 12'h13C;
    localparam REG_ROCEV2_MIN_TIMESTAMP_LOWER  = 12'h140;
    localparam REG_ROCEV2_MIN_TIMESTAMP_UPPER  = 12'h144;
    localparam REG_ROCEV2_RT_JITTER_LOWER      = 12'h148;
    localparam REG_ROCEV2_RT_JITTER_UPPER      = 12'h14C;
    localparam REG_ROCEV2_MAX_JITTER_LOWER     = 12'h150;
    localparam REG_ROCEV2_MAX_JITTER_UPPER     = 12'h154;
    localparam REG_ROCEV2_MIN_JITTER_LOWER     = 12'h158;
    localparam REG_ROCEV2_MIN_JITTER_UPPER     = 12'h15C;
    localparam REG_ROCEV2_PKTS_LOWER           = 12'h190;
    localparam REG_ROCEV2_PKTS_UPPER           = 12'h194;
    localparam REG_ROCEV2_SUM_TIMESTAMP_LOWER  = 12'h198;
    localparam REG_ROCEV2_SUM_TIMESTAMP_UPPER  = 12'h19C; 
    localparam REG_ROCEV2_SUM_JITTER_LOWER     = 12'h1A0;
    localparam REG_ROCEV2_SUM_JITTER_UPPER     = 12'h1A4;
    localparam REG_RX_STREAM_SUM_TIMESTAMP_LOWER  = 12'h160;
    localparam REG_RX_STREAM_SUM_TIMESTAMP_UPPER  = 12'h164;
    localparam REG_RX_STREAM_MAX_TIMESTAMP_LOWER  = 12'h168;
    localparam REG_RX_STREAM_MAX_TIMESTAMP_UPPER  = 12'h16C;
    localparam REG_RX_STREAM_MIN_TIMESTAMP_LOWER  = 12'h170;
    localparam REG_RX_STREAM_MIN_TIMESTAMP_UPPER  = 12'h174;
    localparam REG_RX_STREAM_SUM_JITTER_LOWER     = 12'h178;
    localparam REG_RX_STREAM_SUM_JITTER_UPPER     = 12'h17C;
    localparam REG_RX_STREAM_MAX_JITTER_LOWER     = 12'h180;
    localparam REG_RX_STREAM_MAX_JITTER_UPPER     = 12'h184;
    localparam REG_RX_STREAM_MIN_JITTER_LOWER     = 12'h188;
    localparam REG_RX_STREAM_MIN_JITTER_UPPER     = 12'h18C;
  
    wire                reg_en;
    wire                reg_we;
    wire [C_ADDR_W-1:0] reg_addr;
    wire         [31:0] reg_din;
    reg          [31:0] reg_dout;
    reg                 reg_statis_cnt_clear_en;   
    reg [4:0]           base_filter;//= 5'd0;           
    reg                 filter_done;//= 1'b0;
    reg  [319:0]        info_filter_item; 

  avm_register #(
    .CLOCKING_MODE ("common_clock"),
    .ADDR_W        (C_ADDR_W),
    .DATA_W        (32)
  ) axil_reg_inst (
    .avm_addr       (s_avm_addr         ),
    .avm_read       (s_avm_read         ),
    .avm_write      (s_avm_write        ),
    .avm_wdat       (s_avm_wdat         ),
    .avm_wait       (s_avm_wait         ),
    .avm_rdat       (s_avm_rdat         ),
    .avm_rvld       (s_avm_rvld         ),
    .avm_rspo       (s_avm_rspo         ),
    .avm_wrsp       (s_avm_wrsp         ),

    .reg_en         (reg_en),
    .reg_we         (reg_we),
    .reg_addr       (reg_addr),
    .reg_din        (reg_din),
    .reg_dout       (reg_dout),

    .clk            (axil_aclk),
    .rst_n          (axil_aresetn)
  );

  assign stream_pkt_rst = reg_statis_cnt_clear_en;

 always @(posedge axil_aclk) 
  begin
     if (~axil_aresetn) 
     	 base_filter <= 5'd0;
     else if (reg_en && reg_we && reg_addr == REG_RX_FILTER_BASE)
	     base_filter <= reg_din[4:0];
  end  

 always @(posedge axil_aclk) 
  begin
     if (~axil_aresetn) 
     	 filter_done <= 1'b0;
     else if (reg_en && reg_we && reg_addr == REG_RX_FILTER_DONE)
     	 filter_done <= reg_din[0];
  end 

 always @(posedge axil_aclk) 
  begin
     if (~axil_aresetn) 
     	  policy_vld <= 32'h0000_0000;
     else if (reg_en && reg_we && reg_addr == REG_RX_FILTER_POLICY_EN)
     	  policy_vld <= reg_din[31:0];
  end 

  always @(posedge axil_aclk) 
  begin
     if (~axil_aresetn) 
     	  process_mode <= {    FILTER_NUM{1'b0}};
     else if (reg_en && reg_we && reg_addr == REG_RX_FILTER_PROCESS_MODE)
     	  process_mode <= reg_din[FILTER_NUM-1:0];
  end 

 always @(posedge axil_aclk) 
  begin
     if (~axil_aresetn) 
     	  field_relation <= {    FILTER_NUM{1'b0}};
     else if (reg_en && reg_we && reg_addr == REG_RX_FILTER_FIELD_RELATION)
     	  field_relation <= reg_din[FILTER_NUM-1:0];
  end 

  generate
    for(genvar i =0; i < FILTER_NUM; i = i+1) begin: gen_field_cfg
      always @(posedge axil_aclk) begin
        if (~axil_aresetn)begin 
          dmac_en             [i]             <=   1'b0;
          dmac_mode           [i]             <=   1'b0;
          dmac_value          [48*i +: 48]    <=  48'b0;
          dmac_mask           [48*i +: 48]    <=  48'b0;
          smac_en             [i]             <=   1'b0;
          smac_mode           [i]             <=   1'b0;
          smac_mask           [48*i +: 48]    <=  48'b0;
          smac_value          [48*i +: 48]    <=  48'b0;
          vlanid_en           [i]             <=   1'b0;
          vlanid_mode         [i]             <=   1'b0;
          vlanid_mask         [12*i +: 12]    <=  12'b0;
          vlanid_value        [12*i +: 12]    <=  12'b0;
          protocol_en         [i]             <=   1'b0;        
          protocol_mode       [i]             <=   1'b0;        
          protocol_mask       [ 8*i +:  8]    <=   8'b0;        
          protocol_value      [ 8*i +:  8]    <=   8'b0;        
          sipv4_en            [i]             <=   1'b0;    
          sipv4_mode          [i]             <=   1'b0;    
          sipv4_mask          [32*i +: 32]    <=  32'b0;    
          sipv4_value         [32*i +: 32]    <=  32'b0;    
          dipv4_en            [i]             <=   1'b0;   
          dipv4_mode          [i]             <=   1'b0;   
          dipv4_mask          [32*i +: 32]    <=  32'b0;             
          dipv4_value         [32*i +: 32]    <=  32'b0;             
          sipv6_en            [i]             <=   1'b0;             
          sipv6_mode          [i]             <=   1'b0;             
          sipv6_mask          [128*i +: 128]  <= 128'b0;             
          sipv6_value         [128*i +: 128]  <= 128'b0;             
          dipv6_en            [i]             <=   1'b0;             
          dipv6_mode          [i]             <=   1'b0;             
          dipv6_mask          [128*i +: 128]  <= 128'b0;             
          dipv6_value         [128*i +: 128]  <= 128'b0;             
          sport_en            [i]             <=   1'b0;             
          sport_mode          [i]             <=   1'b0;             
          sport_mask          [16*i +: 16]    <=  16'b0;             
          sport_value         [16*i +: 16]    <=  16'b0;             
          dport_en            [i]             <=   1'b0;             
          dport_mode          [i]             <=   1'b0;             
          dport_mask          [16*i +: 16]    <=  16'b0;             
          dport_value         [16*i +: 16]    <=  16'b0;             
          pkt_length_en       [i]             <=   1'b0;             
          pkt_length_mode     [i]             <=   1'b0;             
          pkt_length_mask     [16*i +: 16]    <=  16'b0;             
          pkt_length_value    [16*i +: 16]    <=  16'b0;             
        end  
        else begin
          // DMAC
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == DMAC_EN)begin
            dmac_en[i] <= reg_din[0:0];
          end
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == DMAC_MODE)begin
            dmac_mode[i] <= reg_din[0:0];
          end
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == DMAC_MASK_31_0)begin
            dmac_mask[48*i +: 32] <= reg_din[31:0];
          end
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == DMAC_MASK_47_32)begin
            dmac_mask[(48*i+32) +: 16] <= reg_din[15:0];
          end
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == DMAC_VALUE_31_0)begin
            dmac_value[48*i +: 32] <= reg_din[31:0];
          end
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == DMAC_VALUE_47_32)begin
            dmac_value[(48*i+32) +: 16] <= reg_din[15:0];
          end
          // SMAC
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == SMAC_EN)begin
            smac_en[i] <= reg_din[0:0];
          end
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == SMAC_MODE)begin
            smac_mode[i] <= reg_din[0:0];
          end
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == SMAC_MASK_31_0)begin
            smac_mask[48*i +: 32]<= reg_din[31:0];
          end
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == SMAC_MASK_47_32)begin
            smac_mask[(48*i+32) +: 16] <= reg_din[15:0];
          end
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == SMAC_VALUE_31_0)begin
            smac_value[48*i +: 32]<= reg_din[31:0];
          end
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == SMAC_VALUE_47_32)begin
            smac_value[(48*i+32) +: 16] <= reg_din[15:0];
          end
          // VLANID1
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == VLANID1_EN)begin
            vlanid_en[i] <= reg_din[0:0];
          end
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == VLANID1_MODE)begin
            vlanid_mode[i] <= reg_din[0:0];
          end
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == VLANID1_MASK)begin
            vlanid_mask[12*i +: 12] <= reg_din[11:0];
          end
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == VLANID1_VALUE)begin
            vlanid_value[12*i +: 12] <= reg_din[11:0];
          end
          // PROTOCOL
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == PROTOCOL_EN)begin
            protocol_en[i] <= reg_din[0:0];
          end
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == PROTOCOL_MODE)begin
            protocol_mode[i] <= reg_din[0:0];
          end
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == PROTOCOL_MASK)begin
            protocol_mask[8*i +: 8] <= reg_din[7:0];
          end
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == PROTOCOL_VALUE)begin
            protocol_value[8*i +: 8] <= reg_din[7:0];
          end
          // SIPV4
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == SIPV4_EN)begin
            sipv4_en[i] <= reg_din[0:0];
          end
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == SIPV4_MODE)begin
            sipv4_mode[i] <= reg_din[0:0];
          end
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == SIPV4_MASK)begin
            sipv4_mask[32*i +: 32]<= reg_din[31:0];
          end
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == SIPV4_VALUE)begin
            sipv4_value[32*i +: 32]<= reg_din[31:0];
          end
          // DIPV4
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == DIPV4_EN)begin
            dipv4_en[i] <= reg_din[0:0];
          end
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == DIPV4_MODE)begin
            dipv4_mode[i] <= reg_din[0:0];
          end
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == DIPV4_MASK)begin
            dipv4_mask[32*i +: 32]<= reg_din[31:0];
          end
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == DIPV4_VALUE)begin
            dipv4_value[32*i +: 32]<= reg_din[31:0];
          end
          // SIPV6
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == SIPV6_EN)begin
            sipv6_en[i] <= reg_din[0:0];
          end
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == SIPV6_MODE)begin
            sipv6_mode[i] <= reg_din[0:0];
          end
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == SIPV6_MASK_31_0)begin
            sipv6_mask[128*i +: 32]<= reg_din[31:0];
          end
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == SIPV6_MASK_63_32)begin
            sipv6_mask[(128*i+32) +: 32] <= reg_din[31:0];
          end
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == SIPV6_MASK_95_64)begin
            sipv6_mask[(128*i+64) +: 32] <= reg_din[31:0];
          end
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == SIPV6_MASK_127_96)begin
            sipv6_mask[(128*i+96) +: 32] <= reg_din[31:0];
          end
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == SIPV6_VALUE_31_0)begin
            sipv6_value[128*i +: 32]<= reg_din[31:0];
          end
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == SIPV6_VALUE_63_32)begin
            sipv6_value[(128*i+32) +: 32] <= reg_din[31:0];
          end
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == SIPV6_VALUE_95_64)begin
            sipv6_value[(128*i+64) +: 32] <= reg_din[31:0];
          end
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == SIPV6_VALUE_127_96)begin
            sipv6_value[(128*i+96) +: 32] <= reg_din[31:0];
          end
          // DIPV6
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == DIPV6_EN)begin
            dipv6_en[i] <= reg_din[0:0];
          end
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == DIPV6_MODE)begin
            dipv6_mode[i] <= reg_din[0:0];
          end
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == DIPV6_MASK_31_0)begin
            dipv6_mask[128*i +: 32] <= reg_din[31:0];
          end
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == DIPV6_MASK_63_32)begin
            dipv6_mask[(128*i+32) +: 32] <= reg_din[31:0];
          end
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == DIPV6_MASK_95_64)begin
            dipv6_mask[(128*i+64) +: 32] <= reg_din[31:0];
          end
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == DIPV6_MASK_127_96)begin
            dipv6_mask[(128*i+96) +: 32] <= reg_din[31:0];
          end
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == DIPV6_VALUE_31_0)begin
            dipv6_value[128*i +: 32] <= reg_din[31:0];
          end
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == DIPV6_VALUE_63_32)begin
            dipv6_value[(128*i+32) +: 32] <= reg_din[31:0];
          end
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == DIPV6_VALUE_95_64)begin
            dipv6_value[(128*i+64) +: 32] <= reg_din[31:0];
          end
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == DIPV6_VALUE_127_96)begin
            dipv6_value[(128*i+96) +: 32] <= reg_din[31:0];
          end
          // SPORT
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == SPORT_EN)begin
            sport_en[i] <= reg_din[0:0];
          end
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == SPORT_MODE)begin
            sport_mode[i] <= reg_din[0:0];
          end
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == SPORT_MASK)begin
            sport_mask[16*i +: 16] <= reg_din[15:0];
          end
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == SPORT_VALUE)begin
            sport_value[16*i +: 16] <= reg_din[15:0];
          end
          // DPORT
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == DPORT_EN)begin
            dport_en[i] <= reg_din[0:0];
          end
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == DPORT_MODE)begin
            dport_mode[i] <= reg_din[0:0];
          end
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == DPORT_MASK)begin
            dport_mask[16*i +: 16] <= reg_din[15:0];
          end
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == DPORT_VALUE)begin
            dport_value[16*i +: 16] <= reg_din[15:0];
          end
          // PKT_LENGTH
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == PKT_LENGTH_EN)begin
            pkt_length_en[i] <= reg_din[0:0];
          end
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == PKT_LENGTH_MODE)begin
            pkt_length_mode[i] <= reg_din[0:0];
          end
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == PKT_LENGTH_MASK)begin
            pkt_length_mask[16*i +: 16] <= reg_din[15:0];
          end
          if (i == base_filter && !filter_done && reg_en && reg_we && reg_addr == PKT_LENGTH_VALUE)begin
            pkt_length_value[16*i +: 16] <= reg_din[15:0];
          end
        end
      end
    end
  endgenerate

  always @(posedge axil_aclk) 
  begin
     if (~axil_aresetn)begin 
     	 reg_statis_cnt_clear_en <= 0;
       stream_pkt_r_req <= 0;
       stream_pkt_id_r <= 16'd0;
     end       
     else if (reg_en && reg_we && reg_addr == REG_RX_PKTS_CLEAR)begin
	     reg_statis_cnt_clear_en <= reg_din[16];
       if(reg_din[16] == 1'b0)begin
         stream_pkt_r_req <= 1'b1;
         stream_pkt_id_r = reg_din[15:0];
       end
     end   
     else begin
     	 reg_statis_cnt_clear_en <= 0;
       stream_pkt_r_req <= 0;
     end   
  end   

 always @(posedge axil_aclk) 
  begin
     if (~axil_aresetn) 
     	rx_pkt_en <= 1'b0;
     else if (reg_en && reg_we && reg_addr == REG_RX_PKTS_ENABLE)
	    rx_pkt_en <= reg_din[0];
  end   

 always @(posedge axil_aclk) 
  begin
     if (~axil_aresetn) 
     	rx_pkt_mix_en <= 0;
     else if (reg_en && reg_we && reg_addr == REG_RX_PKTS_MIXED_ENABLE)
	rx_pkt_mix_en <= reg_din[0];
  end 
 
  always @(posedge axil_aclk) 
  begin
     if (~axil_aresetn) 
     	rx_pkt_filter_en <= 0;
     else if (reg_en && reg_we && reg_addr == REG_RX_PKTS_FILTER_ENABLE)
	    rx_pkt_filter_en <= reg_din[0];
  end 

  always @(posedge axil_aclk) 
  begin
     if (~axil_aresetn) 
     	rx_pkt_filter_type <= 0;
     else if (reg_en && reg_we && reg_addr == REG_RX_PKTS_FILTER_TYPE)
	rx_pkt_filter_type <= reg_din[0];
  end 

  always @(posedge axil_aclk) 
  begin
     if (~axil_aresetn) 
     	rx_all_en <= 1'b1;
     else if (reg_en && reg_we && reg_addr == REG_RX_PKTS_ALL_ENABLE)
	    rx_all_en <= reg_din[0];
  end
 
  always @(posedge axil_aclk) 
  begin
     if (~axil_aresetn) 
     	work_mode <= 0;
     else if (reg_en && reg_we && reg_addr == REG_RX_PKTS_WORK_MODE)
	work_mode <= reg_din[0];
  end

  always @(posedge axil_aclk) 
  begin
     if (~axil_aresetn)     
        test_mode <= 0 ;
     else if (reg_en && reg_we && reg_addr == REG_RX_TEST_MODE)
	      test_mode <= reg_din[0];
   end

  always @(posedge axil_aclk) 
  begin
     if (~axil_aresetn)     
        timestamp_delay_type <= 0 ;
     else if (reg_en && reg_we && reg_addr == REG_RX_TIMEDELAY_TYPE)
	    timestamp_delay_type <= reg_din[0];
   end
   always @(posedge axil_aclk) 
  begin
     if (~axil_aresetn)begin     
        timestamp_delay_value <= 32'h0;
     end   
     else if (reg_en && reg_we && reg_addr == REG_RX_TIMEDELAY_VAL)begin
	    timestamp_delay_value <= reg_din; 
	  end   
   end

generate
  always @(posedge axil_aclk) begin
    if (~axil_aresetn) begin
      reg_dout <= 0;
    end
    else if (reg_en && ~reg_we) begin
      case (reg_addr)
        REG_RX_PKTS_ENABLE        : begin
            reg_dout <= {31'd0,rx_pkt_en};
        end
        REG_RX_PKTS_MIXED_ENABLE  : begin
            reg_dout <= {31'd0,rx_pkt_mix_en};
        end    
        REG_RX_PKTS_CLEAR         : begin
            reg_dout <= {31'd0,reg_statis_cnt_clear_en};
        end
	    REG_RX_PKTS_FILTER_ENABLE : begin
            reg_dout <= {31'd0,rx_pkt_filter_en};
    	end
        REG_RX_PKTS_FILTER_TYPE   : begin
            reg_dout <= {31'd0,rx_pkt_filter_type};
        end
        REG_RX_FILTER_BASE : begin
            reg_dout <= {27'd0,base_filter};
        end
        REG_RX_FILTER_DONE : begin
            reg_dout <= {31'd0,filter_done};
        end    
        REG_RX_FILTER_POLICY_EN : begin
            reg_dout <= policy_vld;
        end        
        REG_RX_FILTER_PROCESS_MODE : begin
            reg_dout <= {{(32-FILTER_NUM){1'b0}},process_mode[FILTER_NUM-1:0]};
        end        
        REG_RX_FILTER_FIELD_RELATION : begin
            reg_dout <= {{(32-FILTER_NUM){1'b0}},field_relation[FILTER_NUM-1:0]};
        end        
	     REG_RX_PKTS_RECV_LOWER: begin
          reg_dout <= reg_rx_pkts_recv[31:0];
        end
        REG_RX_PKTS_RECV_UPPER: begin
          reg_dout <= reg_rx_pkts_recv[63:32];
        end
        REG_RX_BYTES_RECV_LOWER: begin
          reg_dout <= reg_rx_bytes_recv[31:0];
        end
        REG_RX_BYTES_RECV_UPPER: begin
          reg_dout <= reg_rx_bytes_recv[63:32];
        end
        REG_RX_PKTS_DROP_LOWER: begin
          reg_dout <= reg_rx_pkts_drop[31:0];
        end
        REG_RX_PKTS_DROP_UPPER: begin
          reg_dout <= reg_rx_pkts_drop[63:32];
        end
        REG_RX_BYTES_DROP_LOWER: begin
          reg_dout <= reg_rx_bytes_drop[31:0];
        end
        REG_RX_BYTES_DROP_UPPER: begin
          reg_dout <= reg_rx_bytes_drop[63:32];
        end
        REG_RX_PKTS_ERR_LOWER: begin
          reg_dout <= reg_rx_pkts_err[31:0];
        end
        REG_RX_PKTS_ERR_UPPER: begin
          reg_dout <= reg_rx_pkts_err[63:32];
        end
        REG_RX_BYTES_ERR_LOWER: begin
          reg_dout <= reg_rx_bytes_err[31:0];
        end
        REG_RX_BYTES_ERR_UPPER: begin
          reg_dout <= reg_rx_bytes_err[63:32];
        end
        REG_RX_IP_CKSUM_ERR_LOWER: begin
          reg_dout <= reg_rx_pkts_ip_checksum_err[31:0];
        end
        REG_RX_IP_CKSUM_ERR_UPPER: begin
          reg_dout <= reg_rx_pkts_ip_checksum_err[63:32];
        end
        REG_RX_PKTS_STREAM_LOWER: begin
          reg_dout <= stream_pkt_rdata[31:0];
        end
        REG_RX_PKTS_STREAM_UPPER: begin
          reg_dout <= stream_pkt_rdata[63:32];
        end
        REG_RX_BYTES_STREAM_LOWER: begin
          reg_dout <= stream_byt_rdata[31:0];
        end
        REG_RX_BYTES_STREAM_UPPER: begin
          reg_dout <= stream_byt_rdata[63:32];
        end
        REG_RX_SUM_TIMESTAMP_LOWER: begin
	      reg_dout <= reg_rx_pkt_sum_delay[31:0];
        end  
        REG_RX_SUM_TIMESTAMP_UPPER: begin
	      reg_dout <= reg_rx_pkt_sum_delay[63:32];
        end  
        REG_RX_MAX_TIMESTAMP_LOWER: begin
	      reg_dout <= reg_rx_pkt_max_delay[31:0];
        end  
        REG_RX_MAX_TIMESTAMP_UPPER: begin
	      reg_dout <= reg_rx_pkt_max_delay[63:32];
        end 
        REG_RX_MIN_TIMESTAMP_LOWER: begin
	      reg_dout <= reg_rx_pkt_min_delay[31:0];
        end  
        REG_RX_MIN_TIMESTAMP_UPPER: begin
	      reg_dout <= reg_rx_pkt_min_delay[63:32];
        end 
        REG_RX_SUM_JITTER_LOWER: begin
	      reg_dout <= reg_rx_pkt_sum_jitter[31:0];
        end  
        REG_RX_SUM_JITTER_UPPER: begin
	      reg_dout <= reg_rx_pkt_sum_jitter[63:32];
        end 
        REG_RX_MAX_JITTER_LOWER: begin
	      reg_dout <= reg_rx_pkt_max_jitter[31:0];
        end  
        REG_RX_MAX_JITTER_UPPER: begin
	      reg_dout <= reg_rx_pkt_max_jitter[63:32];
        end 
        REG_RX_MIN_JITTER_LOWER: begin
	      reg_dout <= reg_rx_pkt_min_jitter[31:0];
        end  
        REG_RX_MIN_JITTER_UPPER: begin
	      reg_dout <= reg_rx_pkt_min_jitter[63:32];
        end 
        REG_RX_PKTS_ALL_ENABLE: begin
          reg_dout <= {31'd0,rx_all_en};
        end 
        REG_RX_PKTS_WORK_MODE: begin
          reg_dout <= {31'd0,work_mode};
        end  
        REG_RX_STATIME_LOWER : begin
          reg_dout <= reg_rx_pkt_start_time[31:0];
        end
        REG_RX_STATIME_UPPER: begin
          reg_dout <= reg_rx_pkt_start_time[63:32];
        end
        REG_RX_STPTIME_LOWER : begin
          reg_dout <= reg_rx_pkt_stop_time[31:0];
        end
        REG_RX_STPTIME_UPPER: begin
          reg_dout <= reg_rx_pkt_stop_time[63:32];
        end
        REG_RX_TEST_MODE: begin
          reg_dout <= {31'd0,test_mode};
        end  
        REG_RX_TIMEDELAY_TYPE: begin
          reg_dout <= {31'd0,timestamp_delay_type};
        end  
/*        REG_RX_FILTER_SIP_0: begin
          reg_dout <= info_filter_item[319:288];
        end  
        REG_RX_FILTER_SIP_1: begin
          reg_dout <= info_filter_item[287:256];
        end  
         REG_RX_FILTER_SIP_2: begin
          reg_dout <= info_filter_item[255:224];
        end        
        REG_RX_FILTER_SIP_3: begin
          reg_dout <= info_filter_item[223:192];
        end  
        REG_RX_FILTER_DIP_0: begin
          reg_dout <= info_filter_item[191:160];
        end  
        REG_RX_FILTER_DIP_1: begin
          reg_dout <= info_filter_item[159:128];
        end  
         REG_RX_FILTER_DIP_2: begin
          reg_dout <= info_filter_item[127:96];
        end        
        REG_RX_FILTER_DIP_3: begin
          reg_dout <= info_filter_item[95:64];
        end 
        REG_RX_FILTER_SP_DP: begin
          reg_dout <= info_filter_item[63:32];
        end 
        REG_RX_FILTER_MASK: begin
          reg_dout <= info_filter_item[31:0];
        end 
*/
        REG_RX_TIMEDELAY_VAL: begin
          reg_dout <= timestamp_delay_value;
        end
        REG_ROCEV2_RT_TIMESTAMP_LOWER: begin
	      reg_dout <= reg_rocev2_pkt_rt_delay[31:0];
        end  
        REG_ROCEV2_RT_TIMESTAMP_UPPER: begin
	      reg_dout <= reg_rocev2_pkt_rt_delay[63:32];
        end  
        REG_ROCEV2_MAX_TIMESTAMP_LOWER: begin
	      reg_dout <= reg_rocev2_pkt_max_delay[31:0];
        end  
        REG_ROCEV2_MAX_TIMESTAMP_UPPER: begin
	      reg_dout <= reg_rocev2_pkt_max_delay[63:32];
        end 
        REG_ROCEV2_MIN_TIMESTAMP_LOWER: begin
	      reg_dout <= reg_rocev2_pkt_min_delay[31:0];
        end  
        REG_ROCEV2_MIN_TIMESTAMP_UPPER: begin
	      reg_dout <= reg_rocev2_pkt_min_delay[63:32];
        end 
        REG_ROCEV2_RT_JITTER_LOWER: begin
	      reg_dout <= reg_rocev2_pkt_rt_jitter[31:0];
        end  
        REG_ROCEV2_RT_JITTER_UPPER: begin
	      reg_dout <= reg_rocev2_pkt_rt_jitter[63:32];
        end 
        REG_ROCEV2_MAX_JITTER_LOWER: begin
	      reg_dout <= reg_rocev2_pkt_max_jitter[31:0];
        end  
        REG_ROCEV2_MAX_JITTER_UPPER: begin
	      reg_dout <= reg_rocev2_pkt_max_jitter[63:32];
        end 
        REG_ROCEV2_MIN_JITTER_LOWER: begin
	      reg_dout <= reg_rocev2_pkt_min_jitter[31:0];
        end  
        REG_ROCEV2_MIN_JITTER_UPPER: begin
	      reg_dout <= reg_rocev2_pkt_min_jitter[63:32];
        end 
        REG_ROCEV2_PKTS_LOWER: begin
	      reg_dout <= reg_rocev2_rx_pkts[31:0];
        end
        REG_ROCEV2_PKTS_UPPER: begin
	      reg_dout <= reg_rocev2_rx_pkts[63:32];
        end
        REG_ROCEV2_SUM_TIMESTAMP_LOWER: begin
	      reg_dout <= reg_rocev2_pkt_sum_delay[31:0];
        end  
        REG_ROCEV2_SUM_TIMESTAMP_UPPER: begin
	      reg_dout <= reg_rocev2_pkt_sum_delay[63:32];
        end 
        REG_ROCEV2_SUM_JITTER_LOWER: begin
	      reg_dout <= reg_rocev2_pkt_sum_jitter[31:0];
        end  
        REG_ROCEV2_SUM_JITTER_UPPER: begin
	      reg_dout <= reg_rocev2_pkt_sum_jitter[63:32];
        end  
        REG_RX_STREAM_SUM_TIMESTAMP_LOWER: begin
	      reg_dout <= stream_sum_delay[31:0];
        end  
        REG_RX_STREAM_SUM_TIMESTAMP_UPPER: begin
	      reg_dout <= stream_sum_delay[63:32];
        end  
        REG_RX_STREAM_MAX_TIMESTAMP_LOWER: begin
	      reg_dout <= stream_max_delay[31:0];
        end  
        REG_RX_STREAM_MAX_TIMESTAMP_UPPER: begin
	      reg_dout <= 0;
        end 
        REG_RX_STREAM_MIN_TIMESTAMP_LOWER: begin
	      reg_dout <= stream_min_delay[31:0];
        end  
        REG_RX_STREAM_MIN_TIMESTAMP_UPPER: begin
	      reg_dout <= 0;
        end 
        REG_RX_STREAM_SUM_JITTER_LOWER: begin
	      reg_dout <= stream_sum_jitter[31:0];
        end  
        REG_RX_STREAM_SUM_JITTER_UPPER: begin
	      reg_dout <= stream_sum_jitter[63:32];
        end 
        REG_RX_STREAM_MAX_JITTER_LOWER: begin
	      reg_dout <= reg_rx_pkt_max_jitter[31:0];
        end  
        REG_RX_STREAM_MAX_JITTER_UPPER: begin
	      reg_dout <= stream_max_jitter;
        end 
        REG_RX_STREAM_MIN_JITTER_LOWER: begin
	      reg_dout <= stream_min_jitter[31:0];
        end  
        REG_RX_STREAM_MIN_JITTER_UPPER: begin
	      reg_dout <= 0;
        end 
        DMAC_EN: begin
          reg_dout <= dmac_en[0];
        end
        DMAC_MODE: begin
          reg_dout <= dmac_mode[0];
        end
        DMAC_MASK_31_0: begin
          reg_dout <= dmac_mask[31:0];
        end
        DMAC_MASK_47_32: begin
          reg_dout <= dmac_mask[47:32];
        end
        DMAC_VALUE_31_0: begin
          reg_dout <= dmac_value[31:0];
        end
        DMAC_VALUE_47_32: begin
          reg_dout <= dmac_value[47:32];
        end
        SMAC_EN: begin
          reg_dout <= smac_en[0];
        end
        SMAC_MODE: begin
          reg_dout <= smac_mode[0];
        end
        SMAC_MASK_31_0: begin
          reg_dout <= smac_mask[31:0];
        end
        SMAC_MASK_47_32: begin
          reg_dout <= smac_mask[47:32];
        end
        SMAC_VALUE_31_0: begin
          reg_dout <= smac_value[31:0];
        end
        SMAC_VALUE_47_32: begin
          reg_dout <= smac_value[47:32];
        end
        VLANID1_EN: begin
          reg_dout <= vlanid_en[0];
        end
        VLANID1_MODE: begin
          reg_dout <= vlanid_mode[0];
        end
        VLANID1_MASK: begin
          reg_dout <= vlanid_mask[11:0];
        end
        VLANID1_VALUE: begin
          reg_dout <= vlanid_value[11:0];
        end
        PROTOCOL_EN: begin
          reg_dout <= protocol_en[0];
        end
        PROTOCOL_MODE: begin
          reg_dout <= protocol_mode[0];
        end
        PROTOCOL_MASK: begin
          reg_dout <= protocol_mask[7:0];
        end
        PROTOCOL_VALUE: begin
          reg_dout <= protocol_value[7:0];
        end
        SIPV4_EN: begin
          reg_dout <= sipv4_en[0];
        end
        SIPV4_MODE: begin
          reg_dout <= sipv4_mode[0];
        end
        SIPV4_MASK: begin
          reg_dout <= sipv4_mask[31:0];
        end
        SIPV4_VALUE: begin
          reg_dout <= sipv4_value[31:0];
        end
        DIPV4_EN: begin
          reg_dout <= dipv4_en[0];
        end
        DIPV4_MODE: begin
          reg_dout <= dipv4_mode[0];
        end
        DIPV4_MASK: begin
          reg_dout <= dipv4_mask[31:0];
        end
        DIPV4_VALUE: begin
          reg_dout <= dipv4_value[31:0];
        end
        SIPV6_EN: begin
          reg_dout <= sipv6_en[0];
        end
        SIPV6_MODE: begin
          reg_dout <= sipv6_mode[0];
        end
        SIPV6_MASK_31_0: begin
          reg_dout <= sipv6_mask[31:0];
        end
        SIPV6_MASK_63_32: begin
          reg_dout <= sipv6_mask[63:32];
        end
        SIPV6_MASK_95_64: begin
          reg_dout <= sipv6_mask[95:64];
        end
        SIPV6_MASK_127_96: begin
          reg_dout <= sipv6_mask[127:96];
        end
        SIPV6_VALUE_31_0: begin
          reg_dout <= sipv6_value[31:0];
        end
        SIPV6_VALUE_63_32: begin
          reg_dout <= sipv6_value[63:32];
        end
        SIPV6_VALUE_95_64: begin
          reg_dout <= sipv6_value[95:64];
        end
        SIPV6_VALUE_127_96: begin
          reg_dout <= sipv6_value[127:96];
        end
        DIPV6_EN: begin
          reg_dout <= dipv6_en[0];
        end
        DIPV6_MODE: begin
          reg_dout <= dipv6_mode[0];
        end
        DIPV6_MASK_31_0: begin
          reg_dout <= dipv6_mask[31:0];
        end
        DIPV6_MASK_63_32: begin
          reg_dout <= dipv6_mask[63:32];
        end
        DIPV6_MASK_95_64: begin
          reg_dout <= dipv6_mask[95:64];
        end
        DIPV6_MASK_127_96: begin
          reg_dout <= dipv6_mask[127:96];
        end
        DIPV6_VALUE_31_0: begin
          reg_dout <= dipv6_value[31:0];
        end
        DIPV6_VALUE_63_32: begin
          reg_dout <= dipv6_value[63:32];
        end
        DIPV6_VALUE_95_64: begin
          reg_dout <= dipv6_value[95:64];
        end
        DIPV6_VALUE_127_96: begin
          reg_dout <= dipv6_value[127:96];
        end
        SPORT_EN: begin
          reg_dout <= sport_en[0];
        end
        SPORT_MODE: begin
          reg_dout <= sport_mode[0];
        end
        SPORT_MASK: begin
          reg_dout <= sport_mask[15:0];
        end
        SPORT_VALUE: begin
          reg_dout <= sport_value[15:0];
        end
        DPORT_EN: begin
          reg_dout <= dport_en[0];
        end
        DPORT_MODE: begin
          reg_dout <= dport_mode[0];
        end
        DPORT_MASK: begin
          reg_dout <= dport_mask[15:0];
        end
        DPORT_VALUE: begin
          reg_dout <= dport_value[15:0];
        end
        PKT_LENGTH_EN: begin
          reg_dout <= pkt_length_en[0];
        end
        PKT_LENGTH_MODE: begin
          reg_dout <= pkt_length_mode[0];
        end
        PKT_LENGTH_MASK: begin
          reg_dout <= pkt_length_mask[15:0];
        end
        PKT_LENGTH_VALUE: begin
          reg_dout <= pkt_length_value[15:0];
        end
        FILTER0_MATCH_PKTS_L: begin
          if (FILTER_NUM >= 1)
            reg_dout <= filter_match_pkts[64*0 +: 32];
          else
            reg_dout <= 32'hDEADBEEF;
        end
        FILTER0_MATCH_PKTS_H: begin
          if (FILTER_NUM >= 1)
            reg_dout <= filter_match_pkts[(64*0+32) +: 32];
          else
            reg_dout <= 32'hDEADBEEF;
        end
        FILTER1_MATCH_PKTS_L: begin
          if (FILTER_NUM >= 2)
            reg_dout <= filter_match_pkts[64*1 +: 32];
          else
            reg_dout <= 32'hDEADBEEF;
        end
        FILTER1_MATCH_PKTS_H: begin
          if (FILTER_NUM >= 2)
            reg_dout <= filter_match_pkts[(64*1+32) +: 32];
          else
            reg_dout <= 32'hDEADBEEF;
        end
        FILTER2_MATCH_PKTS_L: begin
          if (FILTER_NUM >= 3)
            reg_dout <= filter_match_pkts[64*2 +: 32];
          else
            reg_dout <= 32'hDEADBEEF;
        end
        FILTER2_MATCH_PKTS_H: begin
          if (FILTER_NUM >= 3)
            reg_dout <= filter_match_pkts[(64*2+32) +: 32];
          else
            reg_dout <= 32'hDEADBEEF;
        end
        FILTER3_MATCH_PKTS_L: begin
          if (FILTER_NUM >= 4)
            reg_dout <= filter_match_pkts[64*3 +: 32];
          else
            reg_dout <= 32'hDEADBEEF;
        end
        FILTER3_MATCH_PKTS_H: begin
          if (FILTER_NUM >= 4)
            reg_dout <= filter_match_pkts[(64*3+32) +: 32];
          else
            reg_dout <= 32'hDEADBEEF;
        end
        FILTER4_MATCH_PKTS_L: begin
          if (FILTER_NUM >= 5)
            reg_dout <= filter_match_pkts[64*4 +: 32];
          else
            reg_dout <= 32'hDEADBEEF;
        end
        FILTER4_MATCH_PKTS_H: begin
          if (FILTER_NUM >= 5)
            reg_dout <= filter_match_pkts[(64*4+32) +: 32];
          else
            reg_dout <= 32'hDEADBEEF;
        end
        FILTER5_MATCH_PKTS_L: begin
          if (FILTER_NUM >= 6)
            reg_dout <= filter_match_pkts[64*5 +: 32];
          else
            reg_dout <= 32'hDEADBEEF;
        end
        FILTER5_MATCH_PKTS_H: begin
          if (FILTER_NUM >= 6)
            reg_dout <= filter_match_pkts[(64*5+32) +: 32];
          else
            reg_dout <= 32'hDEADBEEF;
        end
        FILTER6_MATCH_PKTS_L: begin
          if (FILTER_NUM >= 7)
            reg_dout <= filter_match_pkts[64*6 +: 32];
          else
            reg_dout <= 32'hDEADBEEF;
        end
        FILTER6_MATCH_PKTS_H: begin
          if (FILTER_NUM >= 7)
            reg_dout <= filter_match_pkts[(64*6+32) +: 32];
          else
            reg_dout <= 32'hDEADBEEF;
        end
        FILTER7_MATCH_PKTS_L: begin
          if (FILTER_NUM >= 8)
            reg_dout <= filter_match_pkts[64*7 +: 32];
          else
            reg_dout <= 32'hDEADBEEF;
        end
        FILTER7_MATCH_PKTS_H: begin
          if (FILTER_NUM >= 8)
            reg_dout <= filter_match_pkts[(64*7+32) +: 32];
          else
            reg_dout <= 32'hDEADBEEF;
        end
        FILTER0_MATCH_BYTES_L: begin
          if (FILTER_NUM >= 1)
            reg_dout <= filter_match_bytes[64*0 +: 32];
          else
            reg_dout <= 32'hDEADBEEF;
        end
        FILTER0_MATCH_BYTES_H: begin
          if (FILTER_NUM >= 1)
            reg_dout <= filter_match_bytes[(64*0+32) +: 32];
          else
            reg_dout <= 32'hDEADBEEF;
        end
        FILTER1_MATCH_BYTES_L: begin
          if (FILTER_NUM >= 2)
            reg_dout <= filter_match_bytes[64*1 +: 32];
          else
            reg_dout <= 32'hDEADBEEF;
        end
        FILTER1_MATCH_BYTES_H: begin
          if (FILTER_NUM >= 2)
            reg_dout <= filter_match_bytes[(64*1+32) +: 32];
          else
            reg_dout <= 32'hDEADBEEF;
        end
        FILTER2_MATCH_BYTES_L: begin
          if (FILTER_NUM >= 3)
            reg_dout <= filter_match_bytes[64*2 +: 32];
          else
            reg_dout <= 32'hDEADBEEF;
        end
        FILTER2_MATCH_BYTES_H: begin
          if (FILTER_NUM >= 3)
            reg_dout <= filter_match_bytes[(64*2+32) +: 32];
          else
            reg_dout <= 32'hDEADBEEF;
        end
        FILTER3_MATCH_BYTES_L: begin
          if (FILTER_NUM >= 4)
            reg_dout <= filter_match_bytes[64*3 +: 32];
          else
            reg_dout <= 32'hDEADBEEF;
        end
        FILTER3_MATCH_BYTES_H: begin
          if (FILTER_NUM >= 4)
            reg_dout <= filter_match_bytes[(64*3+32) +: 32];
          else
            reg_dout <= 32'hDEADBEEF;
        end
        FILTER4_MATCH_BYTES_L: begin
          if (FILTER_NUM >= 5)
            reg_dout <= filter_match_bytes[64*4 +: 32];
          else
            reg_dout <= 32'hDEADBEEF;
        end
        FILTER4_MATCH_BYTES_H: begin
          if (FILTER_NUM >= 5)
            reg_dout <= filter_match_bytes[(64*4+32) +: 32];
          else
            reg_dout <= 32'hDEADBEEF;
        end
        FILTER5_MATCH_BYTES_L: begin
          if (FILTER_NUM >= 6)
            reg_dout <= filter_match_bytes[64*5 +: 32];
          else
            reg_dout <= 32'hDEADBEEF;
        end
        FILTER5_MATCH_BYTES_H: begin
          if (FILTER_NUM >= 6)
            reg_dout <= filter_match_bytes[(64*5+32) +: 32];
          else
            reg_dout <= 32'hDEADBEEF;
        end
        FILTER6_MATCH_BYTES_L: begin
          if (FILTER_NUM >= 7)
            reg_dout <= filter_match_bytes[64*6 +: 32];
          else
            reg_dout <= 32'hDEADBEEF;
        end
        FILTER6_MATCH_BYTES_H: begin
          if (FILTER_NUM >= 7)
            reg_dout <= filter_match_bytes[(64*6+32) +: 32];
          else
            reg_dout <= 32'hDEADBEEF;
        end
        FILTER7_MATCH_BYTES_L: begin
          if (FILTER_NUM >= 8)
            reg_dout <= filter_match_bytes[64*7 +: 32];
          else
            reg_dout <= 32'hDEADBEEF;
        end
        FILTER7_MATCH_BYTES_H: begin
          if (FILTER_NUM >= 8)
            reg_dout <= filter_match_bytes[(64*7+32) +: 32];
          else
            reg_dout <= 32'hDEADBEEF;
        end
	      default: begin
          reg_dout <= 32'hDEADBEEF;
        end
      endcase
    end
  end
endgenerate


endmodule

