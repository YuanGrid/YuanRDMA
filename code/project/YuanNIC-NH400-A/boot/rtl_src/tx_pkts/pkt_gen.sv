`resetall
`default_nettype none
`timescale 1ns / 1ps
module pkt_gen #(
    parameter DATA_W                            = 1024,
    parameter USEF_W                            = $clog2(DATA_W/8),
    parameter INFO_W                            = 48,
    parameter PORT_ID                           = 0,
    parameter GEN_NUM                           = 2
) (             
    input     wire    [27:0]                    s_avm_addr ,
    input     wire                              s_avm_read ,
    input     wire                              s_avm_write,
    input     wire    [31:0]                    s_avm_wdat ,
    output    wire                              s_avm_wait ,
    output    wire    [31:0]                    s_avm_rdat ,
    output    wire                              s_avm_rvld ,
    output    wire    [1:0]                     s_avm_rspo ,
    output    wire                              s_avm_wrsp ,
    input     wire    [63:0]                    time_stamp,
    output    wire    [GEN_NUM-1:0]             m_axis_pkt_tx_tvalid,
    output    wire    [GEN_NUM*DATA_W-1:0]      m_axis_pkt_tx_tdata,
    output    wire    [GEN_NUM*USEF_W-1:0]      m_axis_pkt_tx_tusef,
    output    wire    [GEN_NUM-1:0]             m_axis_pkt_tx_tlast,
    input     wire    [GEN_NUM-1:0]             m_axis_pkt_tx_tready,
    output    wire    [GEN_NUM-1:0]             m_axis_pkt_tx_tuser_sop,
    output    wire    [GEN_NUM*48-1:0]          m_axis_pkt_tx_tuser_id,
    output    wire    [GEN_NUM-1:0]             m_axis_pkt_tx_tuser_stamp_en,
    output    reg                               m_gen_stop_en,
    input     wire                              box_rstn,
    input     wire                              axil_aclk,
    input     wire                              axis_aclk,
    input     wire                              cmac_clk
);  

    localparam  BOX0_BASE = 24'h100000;
    localparam  LOCALADDR_WIDTH = 24;
    localparam  STREAM_SEND_START_ADDR_0        = 24'h100000 - BOX0_BASE + 16'h1000*PORT_ID,
                STREAM_SEND_STOPC_ADDR_0        = 24'h100004 - BOX0_BASE + 16'h1000*PORT_ID, 
                STREAM_SEND_STAS_ID_ADDR        = 24'h100008 - BOX0_BASE + 16'h1000*PORT_ID,
                STREAM_SEND_STAS_PKTS_LOW_ADDR  = 24'h10000c - BOX0_BASE + 16'h1000*PORT_ID,
                STREAM_SEND_STAS_PKTS_HIGH_ADDR = 24'h100010 - BOX0_BASE + 16'h1000*PORT_ID,
                STREAM_SEND_STAS_BYTES_LOW_ADDR = 24'h100014 - BOX0_BASE + 16'h1000*PORT_ID,
                STREAM_SEND_STAS_BYTES_HIGH_ADDR= 24'h100018 - BOX0_BASE + 16'h1000*PORT_ID,
                STREAM_SEND_STAS_BPS_LOW_ADDR   = 24'h10001c - BOX0_BASE + 16'h1000*PORT_ID,
                STREAM_SEND_STAS_BPS_HIGH_ADDR  = 24'h100020 - BOX0_BASE + 16'h1000*PORT_ID,
                STREAM_SEND_STAS_PPS_LOW_ADDR   = 24'h100024 - BOX0_BASE + 16'h1000*PORT_ID,
                STREAM_SEND_STAS_PPS_HIGH_ADDR  = 24'h100028 - BOX0_BASE + 16'h1000*PORT_ID,
                STREAM_SEND_STAS_START_LOW_ADDR = 24'h10002c - BOX0_BASE + 16'h1000*PORT_ID,
                STREAM_SEND_STAS_START_HIGH_ADDR= 24'h100030 - BOX0_BASE + 16'h1000*PORT_ID,
                STREAM_SEND_STAS_STOP_LOW_ADDR  = 24'h100034 - BOX0_BASE + 16'h1000*PORT_ID,
                STREAM_SEND_STAS_STOP_HIGH_ADDR = 24'h100038 - BOX0_BASE + 16'h1000*PORT_ID,
                STREAM_ID_SEND_PKTS_LOW_ADDR    = 24'h10003c - BOX0_BASE + 16'h1000*PORT_ID,
                STREAM_ID_SEND_PKTS_HIGH_ADDR   = 24'h100040 - BOX0_BASE + 16'h1000*PORT_ID,
                STREAM_ID_SEND_BYTES_LOW_ADDR   = 24'h100044 - BOX0_BASE + 16'h1000*PORT_ID,
                STREAM_ID_SEND_BYTES_HIGH_ADDR  = 24'h100048 - BOX0_BASE + 16'h1000*PORT_ID,
                STREAM_SEND_STOP_LEN_L_ADDR     = 24'h100050 - BOX0_BASE + 16'h1000*PORT_ID,
                STREAM_SEND_STOP_LEN_H_ADDR     = 24'h100054 - BOX0_BASE + 16'h1000*PORT_ID,
                STREAM_SEND_STOP_TIME_L_ADDR    = 24'h100058 - BOX0_BASE + 16'h1000*PORT_ID,
                STREAM_SEND_STOP_TIME_H_ADDR    = 24'h10005c - BOX0_BASE + 16'h1000*PORT_ID,
                DEBUG_STATUS_ADDR               = 24'h100060 - BOX0_BASE + 16'h1000*PORT_ID,
                PKT_TIMESTAMP_DELAY_TYPE        = 24'h100070 - BOX0_BASE + 16'h1000*PORT_ID,
                PKT_SEND_GAPNUM_ADDR            = 24'h1000FC - BOX0_BASE + 16'h1000*PORT_ID,// 31..16 : GAPB NUM , 15..00 : GAPA NUM
                PKT_SEND_GAP_ADDR               = 24'h100100 - BOX0_BASE + 16'h1000*PORT_ID,// PKT_DYN_VIRTUAL_USERS_ADDR
                PKT_SET_LENGTH_ADDR             = 24'h100104 - BOX0_BASE + 16'h1000*PORT_ID,// 31..16 : HEADER LEN 15..0: PKT_LEN?
                PKT_SEND_GAPA_ADDR              = 24'h100108 - BOX0_BASE + 16'h1000*PORT_ID,// GAPA
                PKT_SEND_GAPB_ADDR              = 24'h10010c - BOX0_BASE + 16'h1000*PORT_ID,// GAPB
                // Registers for dynamic Five-Tubles generation
                PKT_DYN_SIP_START_ADDR          = 24'h100110 - BOX0_BASE + 16'h1000*PORT_ID, 
                PKT_DYN_SIP_END_ADDR            = 24'h100114 - BOX0_BASE + 16'h1000*PORT_ID,
                PKT_DYN_SIP_EN_ADDR             = 24'h100118 - BOX0_BASE + 16'h1000*PORT_ID,
                PKT_DYN_DIP_START_ADDR          = 24'h10011C - BOX0_BASE + 16'h1000*PORT_ID, 
                PKT_DYN_DIP_END_ADDR            = 24'h100120 - BOX0_BASE + 16'h1000*PORT_ID,
                PKT_DYN_DIP_EN_ADDR             = 24'h100124 - BOX0_BASE + 16'h1000*PORT_ID,
                PKT_DYN_SPORT_START_ADDR        = 24'h100128 - BOX0_BASE + 16'h1000*PORT_ID,
                PKT_DYN_SPORT_END_ADDR          = 24'h10012C - BOX0_BASE + 16'h1000*PORT_ID,
                PKT_DYN_SPORT_EN_ADDR           = 24'h100130 - BOX0_BASE + 16'h1000*PORT_ID,
                PKT_DYN_DPORT_START_ADDR        = 24'h100134 - BOX0_BASE + 16'h1000*PORT_ID,
                PKT_DYN_DPORT_END_ADDR          = 24'h100138 - BOX0_BASE + 16'h1000*PORT_ID,
                PKT_DYN_DPORT_EN_ADDR           = 24'h10013C - BOX0_BASE + 16'h1000*PORT_ID,
                PKT_DYN_MODE_ADDR               = 24'h100140 - BOX0_BASE + 16'h1000*PORT_ID,
                PKT_DYN_IPV6_ADDR               = 24'h100144 - BOX0_BASE + 16'h1000*PORT_ID,
	            IPV6_PKT_DYN_SIP_START_0_ADDR   = 24'h100150 - BOX0_BASE + 16'h1000*PORT_ID,
                IPV6_PKT_DYN_SIP_START_1_ADDR   = 24'h100154 - BOX0_BASE + 16'h1000*PORT_ID,
                IPV6_PKT_DYN_SIP_START_2_ADDR   = 24'h100158 - BOX0_BASE + 16'h1000*PORT_ID,
                IPV6_PKT_DYN_SIP_START_3_ADDR   = 24'h10015C - BOX0_BASE + 16'h1000*PORT_ID,
                IPV6_PKT_DYN_SIP_END_0_ADDR     = 24'h100160 - BOX0_BASE + 16'h1000*PORT_ID,
                IPV6_PKT_DYN_SIP_END_1_ADDR     = 24'h100164 - BOX0_BASE + 16'h1000*PORT_ID,
                IPV6_PKT_DYN_SIP_END_2_ADDR     = 24'h100168 - BOX0_BASE + 16'h1000*PORT_ID,
                IPV6_PKT_DYN_SIP_END_3_ADDR     = 24'h10016C - BOX0_BASE + 16'h1000*PORT_ID,
                IPV6_PKT_DYN_SIP_EN_ADDR        = 24'h100170 - BOX0_BASE + 16'h1000*PORT_ID,
                IPV6_PKT_DYN_DIP_START_0_ADDR   = 24'h100174 - BOX0_BASE + 16'h1000*PORT_ID,
                IPV6_PKT_DYN_DIP_START_1_ADDR   = 24'h100178 - BOX0_BASE + 16'h1000*PORT_ID,
                IPV6_PKT_DYN_DIP_START_2_ADDR   = 24'h10017C - BOX0_BASE + 16'h1000*PORT_ID,
                IPV6_PKT_DYN_DIP_START_3_ADDR   = 24'h100180 - BOX0_BASE + 16'h1000*PORT_ID,
                IPV6_PKT_DYN_DIP_END_0_ADDR     = 24'h100184 - BOX0_BASE + 16'h1000*PORT_ID,
                IPV6_PKT_DYN_DIP_END_1_ADDR     = 24'h100188 - BOX0_BASE + 16'h1000*PORT_ID,
                IPV6_PKT_DYN_DIP_END_2_ADDR     = 24'h10018C - BOX0_BASE + 16'h1000*PORT_ID,
                IPV6_PKT_DYN_DIP_END_3_ADDR     = 24'h100190 - BOX0_BASE + 16'h1000*PORT_ID,
                IPV6_PKT_DYN_DIP_EN_ADDR        = 24'h100194 - BOX0_BASE + 16'h1000*PORT_ID,
                IPV6_PKT_DYN_SPORT_START_ADDR   = 24'h100198 - BOX0_BASE + 16'h1000*PORT_ID,
                IPV6_PKT_DYN_SPORT_END_ADDR     = 24'h10019C - BOX0_BASE + 16'h1000*PORT_ID,
                IPV6_PKT_DYN_SPORT_EN_ADDR      = 24'h1001A0 - BOX0_BASE + 16'h1000*PORT_ID,
                IPV6_PKT_DYN_DPORT_START_ADDR   = 24'h1001A4 - BOX0_BASE + 16'h1000*PORT_ID,
                IPV6_PKT_DYN_DPORT_END_ADDR     = 24'h1001A8 - BOX0_BASE + 16'h1000*PORT_ID,
                IPV6_PKT_DYN_DPORT_EN_ADDR      = 24'h1001AC - BOX0_BASE + 16'h1000*PORT_ID,           
                PKT_TEMPLATE_ITEM0              = 24'h110044 - BOX0_BASE + 16'h1000*PORT_ID, 
                PKT_TEMPLATE_WRITE0             = 24'h110048 - BOX0_BASE + 16'h1000*PORT_ID,
                PKT_TEMPLATE_WDONE0             = 24'h11004c - BOX0_BASE + 16'h1000*PORT_ID,
                PKT_TEMPLATE_LEN0               = 24'h110050 - BOX0_BASE + 16'h1000*PORT_ID,
                PKT_LW_PTR_RESET                = 24'h110054 - BOX0_BASE + 16'h1000*PORT_ID, 
                PKT_LW_WRITE                    = 24'h110058 - BOX0_BASE + 16'h1000*PORT_ID,
                STREAM_JUMP_ITEM0               = 24'h110064 - BOX0_BASE + 16'h1000*PORT_ID, 
                STREAM_JUMP_WRITE0              = 24'h110068 - BOX0_BASE + 16'h1000*PORT_ID,
                STREAM_JUMP_WDONE0              = 24'h11006c - BOX0_BASE + 16'h1000*PORT_ID,
                STREAM_JUMP_NUM0                = 24'h110070 - BOX0_BASE + 16'h1000*PORT_ID;
    localparam NUMS_OF_STREAM                   = GEN_NUM;

    wire                                        reg_en;
    wire                                        reg_we;
    wire    [LOCALADDR_WIDTH-1:0]               reg_addr;
    wire    [31:0]                              reg_din;
    reg     [31:0]                              reg_dout;
    reg     [16:0]                              pkt_template_ram_addr0; //32*131072 = 512*8192
    wire                                        pkt_template_ram_we;
    wire    [11:0]                              pkt_template_ram_raddr0[GEN_NUM-1:0];
    wire    [DATA_W-1:0]                        pkt_template_ram_q0[GEN_NUM-1:0];
    wire                                        axil_rstn;
    wire                                        mac_rstn;
    reg     [1:0]                               pkt_send_stop_rst; 
    wire                                        pkt_send_stop_rst_axis_aclk[GEN_NUM-1:0];  // from pkt_send ,sending stopped caused by packets limited
    wire                                        s_ena;
    reg     [3:0]                               s_ena_400;
    reg     [4:0]                               wait_cnt;
    wire                                        us_ena,ms_ena;
    wire    [31:0]                              sending_status[GEN_NUM-1:0];
    reg     [63:0]                              tx_send_start_time;
    reg     [63:0]                              tx_send_stop_time;
    reg     [63:0]                              tx_pkt_stream_cnt[0:NUMS_OF_STREAM-1];
    reg     [63:0]                              tx_bytes_stream_cnt[0:NUMS_OF_STREAM-1];
    reg     [63:0]                              tx_bps_stream_cnt[0:NUMS_OF_STREAM-1];
    reg     [63:0]                              tx_pps_stream_cnt[0:NUMS_OF_STREAM-1];
    reg     [63:0]                              tx_pkt_stream_stas[0:NUMS_OF_STREAM-1];
    reg     [63:0]                              tx_bytes_stream_stas[0:NUMS_OF_STREAM-1];
    reg     [63:0]                              tx_bps_stream_stas[0:NUMS_OF_STREAM-1]; 
    reg     [63:0]                              tx_pps_stream_stas[0:NUMS_OF_STREAM-1];
    reg                                         tx_stream_stas_rst;
    reg     [63:0]                              tx_bps_stream_reg[0:NUMS_OF_STREAM-1];
    reg     [63:0]                              tx_pps_stream_reg[0:NUMS_OF_STREAM-1];
    reg     [63:0]                              tx_pkt_stream_stas_sum;
    reg     [63:0]                              tx_bytes_stream_stas_sum;
    reg     [63:0]                              tx_bps_stream_stas_sum; 
    reg     [63:0]                              tx_pps_stream_stas_sum;
    reg                                         pkt_time_delay_type_en;
    reg                                         tx_stream_stas_rst_d1;
    reg                                         tx_stream_stas_rst_mac_d1;
    reg                                         tx_stream_stas_rst_mac_d2;
    reg                                         tx_stream_stas_rst_mac_d3;
    reg     [31:0]                              stream_jump_num;        
    wire                                        sending_stopped; // axil_aclk domain
    wire                                        sending_start_fb;
    wire                                        sending_stop_fb; // axis_aclk domain
    reg                                         ipv6_enable;
    wire    [255:0]                             pkt_trans_data;
    wire    [10:0]                              pkt_trans_rdptr;
    wire    [511:0]                             pkt_ram_q;
    wire    [9:0]                               pkt_ram_rdptr;
    wire    [9:0]                               pkt_ram_wrptr;
    wire    [13:0]                              pkt_lena;
    wire    [13:0]                              pkt_lenb;
    wire    [11:0]                              pkt_stream_id_a;
    wire    [11:0]                              pkt_stream_id_b;
    reg     [1:0]                               start_stop_cdc;
    wire                                        gen_axis_tvalid    [GEN_NUM-1:0] ;
    wire    [DATA_W-1:0]                        gen_axis_tdata     [GEN_NUM-1:0] ;
    wire    [15:0]                              gen_axis_len       [GEN_NUM-1:0] ;
    wire                                        gen_axis_tlast     [GEN_NUM-1:0] ;
    wire    [$clog2(DATA_W/8)-1:0]              gen_axis_tusef     [GEN_NUM-1:0] ;
    wire                                        gen_axis_tready    [GEN_NUM-1:0] ;
    wire                                        gen_axis_fifo_afull[GEN_NUM-1:0] ;
    wire                                        gen_info_fifo_wen  [GEN_NUM-1:0] ;
    wire    [INFO_W-1:0]                        gen_info_fifo_wdata[GEN_NUM-1:0] ;
    wire                                        gen_info_fifo_afull[GEN_NUM-1:0] ; 
    wire                                        axis_fifo_vld_err  [GEN_NUM-1:0] ;   
    wire    [47:0]                              axis_ch_tuser_id   [GEN_NUM-1:0] ;
    reg                                         sending_d1,sending_d2;
    reg                                         stream_pkt_r_req;
    reg                                         stream_pkt_r_req_d1;
    reg                                         stream_pkt_r_req_mac_d1;
    reg                                         stream_pkt_r_req_mac_d2;
    reg                                         stream_pkt_r_req_mac_d3;
    reg     [15:0]                              stream_pkt_id_r;
    wire    [31:0]                              stream_pkt_rdata[GEN_NUM-1:0];
    reg     [31:0]                              stream_pkt_rdata_sum;
    wire    [63:0]                              stream_byt_rdata[GEN_NUM-1:0]; 
    reg     [63:0]                              stream_byt_rdata_sum; 
    reg     [63:0]                              stream_send_time_reg;
    reg     [63:0]                              stream_stop_time_reg;
    reg     [63:0]                              stream_stop_len_reg;
    reg     [31:0]                              stream_stopc_reg;
    reg     [15:0]                              pkt_header_len; // channel 0 header len
    reg     [15:0]                              pkt_length;     // channel 0 pkt len(total?)
    wire    [31:0]                              ramq_si_0;
    wire    [31:0]                              ramq_ctrl_0;
    wire    [31:0]                              ramq_templ_0;
    wire    [10:0]                              stream_jump_ram_addra1[GEN_NUM-1:0];//32* 2048=64 *1024
    wire    [10:0]                              stream_jump_ram_addra2[GEN_NUM-1:0];//32* 2048=64 *1024
    reg     [10:0]                              stream_jump_ram_addra_125m;//32* 2048=64 *1024
    reg     [10:0]                              stream_jump_ram_addra_config_250m[2:1];
    reg     [31:0]                              stream_jump_ram_data_config_250m[2:1];
    wire                                        stream_jump_ram_wea_250m[GEN_NUM-1:0];
    wire    [10:0]                              stream_jump_ram_addra_250m[GEN_NUM-1:0];
    wire    [31:0]                              stream_jump_ram_dina_250m_1[GEN_NUM-1:0];
    wire    [31:0]                              stream_jump_ram_dina_250m_2[GEN_NUM-1:0];
    wire                                        stream_jump_ram_wea1[GEN_NUM-1:0];
    wire                                        stream_jump_ram_wea2[GEN_NUM-1:0];
    //125M时钟配置转到250M时钟
    //stream_jump_ram_wea
    wire                                        stream_jump_ram_config_wea1_temp;
    wire                                        stream_jump_ram_config_wea2_temp;
    reg     [0:0]                               stream_jump_ram_config_wea1_temp_delay[3:1];
    reg     [0:0]                               stream_jump_ram_config_wea2_temp_delay[3:1];
    wire                                        stream_jump_ram_config_wea1 ;
    wire                                        stream_jump_ram_config_wea2 ;

    //stream_jump_ram_addra
    reg     [31:0]                              stream_start_stop_reg;
    reg     [4:0]                               pkt_lw_wptr = 'd0;
    wire                                        pkt_lw_we;
    reg     [21:0]                              pkt_lw_regs[0:7];
    wire    [31 : 0]                            stream_jump_ram_dina1[GEN_NUM-1:0];
    wire    [31 : 0]                            stream_jump_ram_dina2[GEN_NUM-1:0];
    wire    [31:0]                              stream_jump_ram_douta1[GEN_NUM-1:0];
    wire    [31:0]                              stream_jump_ram_douta2[GEN_NUM-1:0];
    wire    [9 : 0]                             stream_jump_ram_addrb[GEN_NUM-1:0];
    wire    [63 : 0]                            stream_jump_ram_doutb1[GEN_NUM-1:0];
    wire    [63 : 0]                            stream_jump_ram_doutb2[GEN_NUM-1:0];
    reg                                         stream_cfg_done;
    reg     [11:0]                              pkt_template_item_len;
    reg     [12:0]                              sending_axilclk_d;
    reg     [13:0]                              pkt_len_a; // pkt length in Bytes;
    reg     [13:0]                              pkt_len_b; // pkt length in Bytes;
    reg                                         pkt_ch_sel;
    reg     [1:0]                               pkt_ch_valid;
    reg     [31:0]                              dyn_sip_start[1:0];
    reg     [31:0]                              dyn_sip_end[1:0];
    reg     [15:0]                              dyn_sip_step[1:0];
    reg                                         dyn_sip_en[1:0];
    reg     [31:0]                              dyn_dip_start[1:0];
    reg     [31:0]                              dyn_dip_end[1:0];
    reg     [15:0]                              dyn_dip_step[1:0];
    reg                                         dyn_dip_en[1:0];
    reg     [15:0]                              dyn_sport_start[1:0];
    reg     [15:0]                              dyn_sport_end[1:0];
    reg     [15:0]                              dyn_sport_step[1:0];
    reg                                         dyn_sport_en[1:0];
    reg     [15:0]                              dyn_dport_start[1:0];
    reg     [15:0]                              dyn_dport_end[1:0];
    reg     [15:0]                              dyn_dport_step[1:0];
    reg                                         dyn_dport_en[1:0];
    reg                                         dyn_mode;
    reg     [127:0]                             ipv6_dyn_sip_start[1:0];
    reg     [127:0]                             ipv6_dyn_sip_end[1:0];
    reg     [15:0]                              ipv6_dyn_sip_step[1:0];
    reg                                         ipv6_dyn_sip_en[1:0];
    reg     [127:0]                             ipv6_dyn_dip_start[1:0];
    reg     [127:0]                             ipv6_dyn_dip_end[1:0];
    reg     [15:0]                              ipv6_dyn_dip_step[1:0];
    reg                                         ipv6_dyn_dip_en[1:0];
    reg     [15:0]                              ipv6_dyn_sport_start[1:0];
    reg     [15:0]                              ipv6_dyn_sport_end[1:0];
    reg     [15:0]                              ipv6_dyn_sport_step[1:0];
    reg                                         ipv6_dyn_sport_en[1:0];
    reg     [15:0]                              ipv6_dyn_dport_start[1:0];
    reg     [15:0]                              ipv6_dyn_dport_end[1:0];
    reg     [15:0]                              ipv6_dyn_dport_step[1:0];
    reg                                         ipv6_dyn_dport_en[1:0];
    reg     [15:0]                              num_gap_a;  
    reg     [31:0]                              gap_a    ;  
    reg     [15:0]                              num_gap_b;  
    reg     [31:0]                              gap_b    ;  
    
    assign axil_rstn = box_rstn;
    assign mac_rstn  = box_rstn;

    always@(posedge axil_aclk)begin
      if(!axil_rstn)
          pkt_send_stop_rst <= 2'b00;
      else
          pkt_send_stop_rst <= {pkt_send_stop_rst[0],pkt_send_stop_rst_axis_aclk[0]&pkt_send_stop_rst_axis_aclk[1]};
    end
  
    avm_register #(
        .CLOCKING_MODE                          ("common_clock"),
        .ADDR_W                                 (24),
        .DATA_W                                 (32)
    ) axil_reg_inst (                       
        .avm_addr                               (s_avm_addr         ),
        .avm_read                               (s_avm_read         ),
        .avm_write                              (s_avm_write        ),
        .avm_wdat                               (s_avm_wdat         ),
        .avm_wait                               (s_avm_wait         ),
        .avm_rdat                               (s_avm_rdat         ),
        .avm_rvld                               (s_avm_rvld         ),
        .avm_rspo                               (s_avm_rspo         ),
        .avm_wrsp                               (s_avm_wrsp         ),
        .reg_en                                 (reg_en),
        .reg_we                                 (reg_we),
        .reg_addr                               (reg_addr),
        .reg_din                                (reg_din),
        .reg_dout                               (reg_dout),
        .clk                                    (axil_aclk),
        .rst_n                                  (axil_rstn)
    );
    
    always@(posedge axil_aclk)begin
        if(reg_we & reg_en & reg_addr == IPV6_PKT_DYN_SIP_START_0_ADDR) ipv6_dyn_sip_start[0][31:0] <= reg_din;
        if(reg_we & reg_en & reg_addr == IPV6_PKT_DYN_SIP_START_1_ADDR) ipv6_dyn_sip_start[0][63:32] <= reg_din;
        if(reg_we & reg_en & reg_addr == IPV6_PKT_DYN_SIP_START_2_ADDR) ipv6_dyn_sip_start[0][95:64] <= reg_din;
        if(reg_we & reg_en & reg_addr == IPV6_PKT_DYN_SIP_START_3_ADDR) ipv6_dyn_sip_start[0][127:96] <= reg_din;
        if(reg_we & reg_en & reg_addr == IPV6_PKT_DYN_SIP_END_0_ADDR)   ipv6_dyn_sip_end[0][31:0] <= reg_din;
        if(reg_we & reg_en & reg_addr == IPV6_PKT_DYN_SIP_END_1_ADDR)   ipv6_dyn_sip_end[0][63:32] <= reg_din;
        if(reg_we & reg_en & reg_addr == IPV6_PKT_DYN_SIP_END_2_ADDR)   ipv6_dyn_sip_end[0][95:64] <= reg_din;
        if(reg_we & reg_en & reg_addr == IPV6_PKT_DYN_SIP_END_3_ADDR)   ipv6_dyn_sip_end[0][127:96] <= reg_din;
        if(reg_we & reg_en & reg_addr == IPV6_PKT_DYN_SIP_EN_ADDR)      {ipv6_dyn_sip_step[0],ipv6_dyn_sip_en[0]} <= {reg_din[31:16],reg_din[0]};
        if(!axil_rstn | sending_stopped)begin
            ipv6_dyn_sip_start[0] <= 128'd0;
            ipv6_dyn_sip_end[0] <= 128'd0;
            ipv6_dyn_sip_step[0] <= 16'd0;
            ipv6_dyn_sip_en[0] <= 1'b0;
        end
    end

    always@(posedge axil_aclk)begin
        if(reg_we & reg_en & reg_addr == IPV6_PKT_DYN_DIP_START_0_ADDR) ipv6_dyn_dip_start[0][31:0] <= reg_din;
        if(reg_we & reg_en & reg_addr == IPV6_PKT_DYN_DIP_START_1_ADDR) ipv6_dyn_dip_start[0][63:32] <= reg_din;
        if(reg_we & reg_en & reg_addr == IPV6_PKT_DYN_DIP_START_2_ADDR) ipv6_dyn_dip_start[0][95:64] <= reg_din;
        if(reg_we & reg_en & reg_addr == IPV6_PKT_DYN_DIP_START_3_ADDR) ipv6_dyn_dip_start[0][127:96] <= reg_din;
        if(reg_we & reg_en & reg_addr == IPV6_PKT_DYN_DIP_END_0_ADDR)   ipv6_dyn_dip_end[0][31:0] <= reg_din;
        if(reg_we & reg_en & reg_addr == IPV6_PKT_DYN_DIP_END_1_ADDR)   ipv6_dyn_dip_end[0][63:32] <= reg_din;
        if(reg_we & reg_en & reg_addr == IPV6_PKT_DYN_DIP_END_2_ADDR)   ipv6_dyn_dip_end[0][95:64] <= reg_din;
        if(reg_we & reg_en & reg_addr == IPV6_PKT_DYN_DIP_END_3_ADDR)   ipv6_dyn_dip_end[0][127:96] <= reg_din;
        if(reg_we & reg_en & reg_addr == IPV6_PKT_DYN_DIP_EN_ADDR)      {ipv6_dyn_dip_step[0],ipv6_dyn_dip_en[0]} <= {reg_din[31:16],reg_din[0]};
        if(!axil_rstn | sending_stopped)begin
            ipv6_dyn_dip_start[0] <= 128'd0;
            ipv6_dyn_dip_end[0] <= 128'd0;
            ipv6_dyn_dip_step[0] <= 16'd0;
            ipv6_dyn_dip_en[0] <= 1'b0;
        end
    end

    always@(posedge axil_aclk)begin
        if(reg_we & reg_en & reg_addr == IPV6_PKT_DYN_SPORT_START_ADDR) ipv6_dyn_sport_start[0] <= reg_din[15:0];
        if(reg_we & reg_en & reg_addr == IPV6_PKT_DYN_SPORT_END_ADDR)   ipv6_dyn_sport_end[0] <= reg_din[15:0];
        if(reg_we & reg_en & reg_addr == IPV6_PKT_DYN_SPORT_EN_ADDR)    {ipv6_dyn_sport_step[0],ipv6_dyn_sport_en[0]} <= {reg_din[31:16],reg_din[0]};
        if(!axil_rstn | sending_stopped)begin
            ipv6_dyn_sport_start[0] <= 16'd0;
            ipv6_dyn_sport_end[0] <= 16'd0;
            ipv6_dyn_sport_step[0] <= 16'd0;
            ipv6_dyn_sport_en[0] <= 1'b0;
        end
    end

    always@(posedge axil_aclk)begin
        if(reg_we & reg_en & reg_addr == IPV6_PKT_DYN_DPORT_START_ADDR) ipv6_dyn_dport_start[0] <= reg_din[15:0];
        if(reg_we & reg_en & reg_addr == IPV6_PKT_DYN_DPORT_END_ADDR)   ipv6_dyn_dport_end[0] <= reg_din[15:0];
        if(reg_we & reg_en & reg_addr == IPV6_PKT_DYN_DPORT_EN_ADDR)    {ipv6_dyn_dport_step[0],ipv6_dyn_dport_en[0]} <= {reg_din[31:16],reg_din[0]};
        if(!axil_rstn | sending_stopped)begin
            ipv6_dyn_dport_start[0] <= 16'd0;
            ipv6_dyn_dport_end[0] <= 16'd0;
            ipv6_dyn_dport_step[0] <= 16'd0;
            ipv6_dyn_dport_en[0] <= 1'b0;
        end
    end

    always@(posedge axil_aclk)begin
        if(reg_we & reg_en & reg_addr == PKT_DYN_SIP_START_ADDR) dyn_sip_start[0] <= reg_din;
        if(reg_we & reg_en & reg_addr == PKT_DYN_SIP_END_ADDR)   dyn_sip_end[0] <= reg_din;
        if(reg_we & reg_en & reg_addr == PKT_DYN_SIP_EN_ADDR)    {dyn_sip_step[0],dyn_sip_en[0]} <= {reg_din[31:16],reg_din[0]};
        if(reg_we & reg_en & reg_addr == PKT_DYN_MODE_ADDR)      dyn_mode <= reg_din[0];
        if(reg_we & reg_en & reg_addr == PKT_DYN_IPV6_ADDR)      ipv6_enable <= reg_din[0];
        if(!axil_rstn | sending_stopped)begin
            dyn_sip_start[0]<= 32'd0;
            dyn_sip_end[0]  <= 32'd0;
            dyn_sip_step[0] <= 16'd0;
            dyn_sip_en[0]   <= 1'b0;
            dyn_mode        <= 1'b0;
            ipv6_enable     <= 1'b0;
        end
    end
    
    always@(posedge axil_aclk)begin
        if(reg_we & reg_en & reg_addr == PKT_DYN_DIP_START_ADDR)
            dyn_dip_start[0] <= reg_din;
        if(reg_we & reg_en & reg_addr == PKT_DYN_DIP_END_ADDR)
            dyn_dip_end[0] <= reg_din;
        if(reg_we & reg_en & reg_addr == PKT_DYN_DIP_EN_ADDR)
            {dyn_dip_step[0],dyn_dip_en[0]} <= {reg_din[31:16],reg_din[0]};
        if(!axil_rstn |sending_stopped)begin
            dyn_dip_start[0] <= 32'd0;
            dyn_dip_end[0] <= 32'd0;
            dyn_dip_step[0] <= 32'd0;
            dyn_dip_en[0] <= 1'b0;
        end
    end

    always@(posedge axil_aclk)begin
        if(reg_we & reg_en & reg_addr == PKT_DYN_SPORT_START_ADDR)
            dyn_sport_start[0] <= reg_din[15:0];
        if(reg_we & reg_en & reg_addr == PKT_DYN_SPORT_END_ADDR)
            dyn_sport_end[0] <= reg_din[15:0];
        if(reg_we & reg_en & reg_addr == PKT_DYN_SPORT_EN_ADDR)
            {dyn_sport_step[0],dyn_sport_en[0]} <= {reg_din[31:16],reg_din[0]};
        if(!axil_rstn |sending_stopped)begin
            dyn_sport_start[0] <= 16'd0;
            dyn_sport_end[0] <= 16'd0;
            dyn_sport_step[0] <= 16'd0;
            dyn_sport_en[0] <= 1'b0;
        end
    end

    always@(posedge axil_aclk)begin
        if(reg_we & reg_en & reg_addr == PKT_DYN_DPORT_START_ADDR)
            dyn_dport_start[0] <= reg_din[15:0];
        if(reg_we & reg_en & reg_addr == PKT_DYN_DPORT_END_ADDR)
            dyn_dport_end[0] <= reg_din[15:0];
        if(reg_we & reg_en & reg_addr == PKT_DYN_DPORT_EN_ADDR)
            {dyn_dport_step[0],dyn_dport_en[0]} <= {reg_din[31:16],reg_din[0]};
        if(!axil_rstn | sending_stopped)begin
            dyn_dport_start[0] <= 16'd0;
            dyn_dport_end[0] <= 16'd0;
            dyn_dport_step[0] <= 16'd0;
            dyn_dport_en[0] <= 1'b0;
        end
    end

    always@(posedge axil_aclk)begin
        if(reg_we & reg_en & reg_addr == STREAM_JUMP_NUM0) stream_jump_num <= reg_din;
        if(!axil_rstn) begin
            stream_jump_num <= 32'd0;
        end
    end

    always@(posedge axil_aclk)
    begin
        if(reg_we & reg_en & reg_addr == STREAM_SEND_START_ADDR_0)
            stream_start_stop_reg <= reg_din;
        if(!axil_rstn) 
            stream_start_stop_reg <= 32'd0;
        if(pkt_send_stop_rst[1]) 
            stream_start_stop_reg <= 32'd0;
    end
    
    always@(posedge axil_aclk)
    begin
        if(reg_we & reg_en & reg_addr == STREAM_SEND_STOPC_ADDR_0)
            stream_stopc_reg <= reg_din;
        if(!axil_rstn) 
            stream_stopc_reg <= 32'd0;
    end
    
    always@(posedge axil_aclk)
    begin
        if(reg_we & reg_en & reg_addr == STREAM_SEND_STOP_LEN_L_ADDR)
            stream_stop_len_reg[31:0] <= reg_din;
        if(reg_we & reg_en & reg_addr == STREAM_SEND_STOP_LEN_H_ADDR)
            stream_stop_len_reg[63:32] <= reg_din;
        if(!axil_rstn) 
            stream_stop_len_reg[63:0] <= 64'd0;
    end

    always@(posedge axil_aclk)
    begin
        if(reg_we & reg_en & reg_addr == STREAM_SEND_STOP_TIME_L_ADDR)
            stream_stop_time_reg[31:0] <= reg_din;
        if(reg_we & reg_en & reg_addr == STREAM_SEND_STOP_TIME_H_ADDR)
            stream_stop_time_reg[63:32] <= reg_din;
        if(!axil_rstn) 
            stream_stop_time_reg[63:0] <= 64'd0;
    end
    
    always@(posedge axil_aclk)
    begin
        if(reg_we & reg_en & reg_addr == PKT_LW_PTR_RESET)
            pkt_lw_wptr <= 'd0; //reg_din[12:0];
        else if(reg_we & reg_en & reg_addr == PKT_LW_WRITE & pkt_lw_wptr < 4'd8) // Max 8 Length-Weigth Group
            pkt_lw_wptr <= pkt_lw_wptr + 1'b1;
    end 
    
    assign pkt_lw_we = reg_we & reg_en & reg_addr == PKT_LW_WRITE & pkt_lw_wptr < 4'd8;

    generate for(genvar i=0;i<8;i=i+1)
        begin:write_lw_regs
            always@(posedge axil_aclk)
            begin
                if(!axil_rstn)
                     pkt_lw_regs[i] <= 'd0;
                else if(pkt_lw_we && pkt_lw_wptr[2:0] == i)
                     pkt_lw_regs[i]  <= {reg_din[16 +: 14],reg_din[7:0]};
            end
        end
    endgenerate
    
    always@(posedge axil_aclk)
    begin
        if(reg_we & reg_en & reg_addr == PKT_SEND_GAPA_ADDR)
            gap_a <= reg_din;
        if(reg_we & reg_en & reg_addr == PKT_SEND_GAPB_ADDR)
            gap_b <= reg_din;
        if(reg_we & reg_en & reg_addr == PKT_SEND_GAPNUM_ADDR)
            {num_gap_b,num_gap_a} <= reg_din;
        if(!axil_rstn) begin
            num_gap_a <= 16'd0;
            num_gap_b <= 16'd0;
            gap_a <= 32'd0;
            gap_b <= 32'd0;
        end
    end
    
    always @(posedge axil_aclk ) begin
        if(!axil_rstn)
            pkt_time_delay_type_en <= 1'b0;
        else if(reg_we & reg_en & reg_addr == PKT_TIMESTAMP_DELAY_TYPE)
            pkt_time_delay_type_en <= reg_din[0];
    end

    always@(posedge axil_aclk)
    begin
        if(!axil_rstn) begin
            {pkt_header_len,pkt_length} <= 32'd0;
        end else if(reg_we & reg_en & reg_addr == PKT_SET_LENGTH_ADDR)
            {pkt_header_len,pkt_length} <= reg_din;
    end
    
    assign stream_jump_ram_config_wea1_temp = reg_addr == STREAM_JUMP_WRITE0 && reg_we && reg_en && stream_jump_num == 0;
    assign stream_jump_ram_config_wea2_temp = reg_addr == STREAM_JUMP_WRITE0 && reg_we && reg_en && stream_jump_num == 1;

    always @(posedge axis_aclk ) begin
        if(!mac_rstn) begin
            stream_jump_ram_config_wea1_temp_delay[1] <= 'b0;
            stream_jump_ram_config_wea1_temp_delay[2] <= 'b0;
            stream_jump_ram_config_wea1_temp_delay[3] <= 'b0;
            stream_jump_ram_config_wea2_temp_delay[1] <= 'b0;
            stream_jump_ram_config_wea2_temp_delay[2] <= 'b0;
            stream_jump_ram_config_wea2_temp_delay[3] <= 'b0;
        end else begin
            stream_jump_ram_config_wea1_temp_delay[1] <= stream_jump_ram_config_wea1_temp;
            stream_jump_ram_config_wea1_temp_delay[2] <= stream_jump_ram_config_wea1_temp_delay[1];
            stream_jump_ram_config_wea1_temp_delay[3] <= stream_jump_ram_config_wea1_temp_delay[2];
            stream_jump_ram_config_wea2_temp_delay[1] <= stream_jump_ram_config_wea2_temp;
            stream_jump_ram_config_wea2_temp_delay[2] <= stream_jump_ram_config_wea2_temp_delay[1];
            stream_jump_ram_config_wea2_temp_delay[3] <= stream_jump_ram_config_wea2_temp_delay[2];
        end
    end

    always@(posedge axil_aclk)
    begin
        if(!axil_rstn) begin
            stream_jump_ram_addra_125m  <= 'd0;
        end else if(reg_we & reg_en & reg_addr == STREAM_JUMP_ITEM0)begin
            stream_jump_ram_addra_125m <= reg_din[9:0]<<1;
        end else if(reg_we & reg_en & reg_addr == STREAM_JUMP_WRITE0) begin
            stream_jump_ram_addra_125m <= stream_jump_ram_addra_125m + 1'b1;
        end else if(reg_we & reg_en & reg_addr == STREAM_JUMP_WDONE0)
            stream_jump_ram_addra_125m <= 'd0;
    end
    
    always @(posedge axis_aclk ) begin
        stream_jump_ram_addra_config_250m[1] <= stream_jump_ram_addra_125m;
        stream_jump_ram_addra_config_250m[2] <= stream_jump_ram_addra_config_250m[1];
    end
    
    assign stream_jump_ram_config_wea1 = stream_jump_ram_config_wea1_temp_delay[2] & (~stream_jump_ram_config_wea1_temp_delay[3]);
    assign stream_jump_ram_config_wea2 = stream_jump_ram_config_wea2_temp_delay[2] & (~stream_jump_ram_config_wea2_temp_delay[3]);
    
    //stream_jump_ram_dina    
    always @(posedge axis_aclk ) begin
        if(!mac_rstn) begin
            stream_jump_ram_data_config_250m[1] <= 0;
            stream_jump_ram_data_config_250m[2] <= 0;
        end else begin
            stream_jump_ram_data_config_250m[1] <= reg_din;
            stream_jump_ram_data_config_250m[2] <= stream_jump_ram_data_config_250m[1];
        end
    end
  
    always@(posedge axil_aclk)
    begin
        if(!axil_rstn)
            pkt_template_item_len <= 12'd1;
        else if(reg_we & reg_en & reg_addr == PKT_TEMPLATE_LEN0)
            pkt_template_item_len <= reg_din[11:0];
    end   
    
    
    always@(posedge axil_aclk)
    begin
        if(!axil_rstn) begin
            pkt_template_ram_addr0 <= 'd0;            
        end else if(reg_we & reg_en & reg_addr == PKT_TEMPLATE_ITEM0)begin
            pkt_template_ram_addr0 <= reg_din[11:0] << 5;
        end else if(reg_we & reg_en & reg_addr == PKT_TEMPLATE_WRITE0) begin
            pkt_template_ram_addr0 <= pkt_template_ram_addr0 + 1'b1;
        end else if(reg_we & reg_en & reg_addr == PKT_TEMPLATE_WDONE0) begin
            pkt_template_ram_addr0 <= 'd0;
        end
    end
        
    always@(posedge axil_aclk)
    begin
        if(!axil_rstn)
            sending_axilclk_d <= 13'b000;
        else
            sending_axilclk_d <= {sending_axilclk_d[11:0],sending_status[0][0]|sending_status[1][0]};
    end
    assign sending_stopped = sending_axilclk_d[12]& ~sending_axilclk_d[11];
    
    always@(posedge axil_aclk)
    begin
        if(!axil_rstn) begin
            stream_cfg_done <= 1'b0; //TODO : in future
        end else if(reg_we & reg_en & reg_addr == PKT_TEMPLATE_WDONE0) begin
            stream_cfg_done <= reg_din[0];
        end else if(sending_stopped)
            stream_cfg_done <= 1'b0;
    end

    assign pkt_template_ram_we = reg_addr == PKT_TEMPLATE_WRITE0 && reg_we && reg_en;

    always@(posedge axis_aclk)
        start_stop_cdc <= {start_stop_cdc[0],stream_start_stop_reg[0]};
    
    generate
        for (genvar i=0 ; i<GEN_NUM ; i=i+1) begin
            assign stream_jump_ram_wea1[i] = stream_jump_ram_config_wea1 | stream_jump_ram_wea_250m[i];
            assign stream_jump_ram_wea2[i] = stream_jump_ram_config_wea2 | stream_jump_ram_wea_250m[i];
            assign stream_jump_ram_addra1[i] = stream_jump_ram_config_wea1? stream_jump_ram_addra_config_250m[2]: stream_jump_ram_addra_250m[i];
            assign stream_jump_ram_addra2[i] = stream_jump_ram_config_wea2? stream_jump_ram_addra_config_250m[2]: stream_jump_ram_addra_250m[i];
            assign stream_jump_ram_dina1[i] = stream_jump_ram_config_wea1? stream_jump_ram_data_config_250m[2]: stream_jump_ram_dina_250m_1[i];
            assign stream_jump_ram_dina2[i] = stream_jump_ram_config_wea2? stream_jump_ram_data_config_250m[2]: stream_jump_ram_dina_250m_2[i];


            ram#(
                .ram_block_type             ("M20K"                 ),
                .outdata_b_reg              ("USED"                 ),
                .widthad_a                  (11                     ),
                .widthad_b                  (10                     ),
                .width_a                    (32                     ),
                .width_b                    (64                     )
            )
            stream_jump_ram1
            (
                .wrclock                    (axis_aclk                  ),
                .wren                       (stream_jump_ram_wea1[i]    ),
                .wraddress                  (stream_jump_ram_addra1[i]  ),
                .data                       (stream_jump_ram_dina1[i]   ),
                .rdclock                    (axis_aclk                  ),
                .rden                       (                           ),
                .rdaddress                  (stream_jump_ram_addrb[i]   ),
                .q                          (stream_jump_ram_doutb1[i]  )
            );

            ram#(
                .ram_block_type             ("M20K"                     ),
                .outdata_b_reg              ("USED"                     ),
                .widthad_a                  (11                         ),
                .widthad_b                  (10                         ),
                .width_a                    (32                         ),
                .width_b                    (64                         )
            )
            stream_jump_ram2
            (
                .wrclock                    (axis_aclk                 ),
                .wren                       (stream_jump_ram_wea2[i]   ),
                .wraddress                  (stream_jump_ram_addra2[i] ),
                .data                       (stream_jump_ram_dina2[i]  ),
                .rdclock                    (axis_aclk                 ),
                .rden                       (                          ),
                .rdaddress                  (stream_jump_ram_addrb[i]  ),
                .q                          (stream_jump_ram_doutb2[i] )
            );

            ram#(
                .ram_block_type             ("M20K"                     ),
                .outdata_b_reg              ("USED"                     ),
                .widthad_a                  (17                         ),
                .widthad_b                  (12                         ),
                .width_a                    (32                         ),
                .width_b                    (1024                       )
            )
            pkt_template_ram0
            (
                .wrclock                    (axil_aclk                  ),
                .wren                       (pkt_template_ram_we        ),
                .wraddress                  (pkt_template_ram_addr0     ),
                .data                       (reg_din                    ),
                .rdclock                    (axis_aclk                  ),
                .rden                       (                           ),
                .rdaddress                  (pkt_template_ram_raddr0[i] ),
                .q                          (pkt_template_ram_q0[i]     )
            );
            
            always @(posedge axis_aclk ) begin
                dyn_sip_start       [1] <= dyn_mode ? dyn_dip_start       [0] : dyn_sip_start       [0];
                dyn_sip_end         [1] <= dyn_mode ? dyn_dip_end         [0] : dyn_sip_end         [0];
                dyn_sip_step        [1] <= dyn_mode ? dyn_dip_step        [0] : dyn_sip_step        [0];
                dyn_sip_en          [1] <= dyn_mode ? dyn_dip_en          [0] : dyn_sip_en          [0];
                dyn_dip_start       [1] <= dyn_mode ? dyn_sip_start       [0] : dyn_dip_start       [0];
                dyn_dip_end         [1] <= dyn_mode ? dyn_sip_end         [0] : dyn_dip_end         [0];
                dyn_dip_step        [1] <= dyn_mode ? dyn_sip_step        [0] : dyn_dip_step        [0];
                dyn_dip_en          [1] <= dyn_mode ? dyn_sip_en          [0] : dyn_dip_en          [0];
                dyn_sport_start     [1] <= dyn_mode ? dyn_dport_start     [0] : dyn_sport_start     [0];
                dyn_sport_end       [1] <= dyn_mode ? dyn_dport_end       [0] : dyn_sport_end       [0];
                dyn_sport_step      [1] <= dyn_mode ? dyn_dport_step      [0] : dyn_sport_step      [0];
                dyn_sport_en        [1] <= dyn_mode ? dyn_dport_en        [0] : dyn_sport_en        [0];
                dyn_dport_start     [1] <= dyn_mode ? dyn_sport_start     [0] : dyn_dport_start     [0];
                dyn_dport_end       [1] <= dyn_mode ? dyn_sport_end       [0] : dyn_dport_end       [0];
                dyn_dport_step      [1] <= dyn_mode ? dyn_sport_step      [0] : dyn_dport_step      [0];
                dyn_dport_en        [1] <= dyn_mode ? dyn_sport_en        [0] : dyn_dport_en        [0];
                ipv6_dyn_sip_start  [1] <= dyn_mode ? ipv6_dyn_dip_start  [0] : ipv6_dyn_sip_start  [0];
                ipv6_dyn_sip_end    [1] <= dyn_mode ? ipv6_dyn_dip_end    [0] : ipv6_dyn_sip_end    [0];
                ipv6_dyn_sip_step   [1] <= dyn_mode ? ipv6_dyn_dip_step   [0] : ipv6_dyn_sip_step   [0];
                ipv6_dyn_sip_en     [1] <= dyn_mode ? ipv6_dyn_dip_en     [0] : ipv6_dyn_sip_en     [0];
                ipv6_dyn_dip_start  [1] <= dyn_mode ? ipv6_dyn_sip_start  [0] : ipv6_dyn_dip_start  [0];
                ipv6_dyn_dip_end    [1] <= dyn_mode ? ipv6_dyn_sip_end    [0] : ipv6_dyn_dip_end    [0];
                ipv6_dyn_dip_step   [1] <= dyn_mode ? ipv6_dyn_sip_step   [0] : ipv6_dyn_dip_step   [0];
                ipv6_dyn_dip_en     [1] <= dyn_mode ? ipv6_dyn_sip_en     [0] : ipv6_dyn_dip_en     [0];
                ipv6_dyn_sport_start[1] <= dyn_mode ? ipv6_dyn_dport_start[0] : ipv6_dyn_sport_start[0];
                ipv6_dyn_sport_end  [1] <= dyn_mode ? ipv6_dyn_dport_end  [0] : ipv6_dyn_sport_end  [0];
                ipv6_dyn_sport_step [1] <= dyn_mode ? ipv6_dyn_dport_step [0] : ipv6_dyn_sport_step [0];
                ipv6_dyn_sport_en   [1] <= dyn_mode ? ipv6_dyn_dport_en   [0] : ipv6_dyn_sport_en   [0];
                ipv6_dyn_dport_start[1] <= dyn_mode ? ipv6_dyn_sport_start[0] : ipv6_dyn_dport_start[0];
                ipv6_dyn_dport_end  [1] <= dyn_mode ? ipv6_dyn_sport_end  [0] : ipv6_dyn_dport_end  [0];
                ipv6_dyn_dport_step [1] <= dyn_mode ? ipv6_dyn_sport_step [0] : ipv6_dyn_dport_step [0];
                ipv6_dyn_dport_en   [1] <= dyn_mode ? ipv6_dyn_sport_en   [0] : ipv6_dyn_dport_en   [0];
            end

            pkt_gen_ch#(
                .PORT_ID                    (i                              ),
                .DATA_W                     (DATA_W                         ),
                .INFO_W                     (INFO_W                         ),
                .ADDR_W                     (12                             ),
                .CFG_ADDR_W                 (10                             ),
                .CFG_DATA_W                 (64                             )
            )
            u_pkt_gen_ch (
                .clk                        ( axis_aclk                     ), //IN
                .rst_n                      ( mac_rstn                      ), //In
                .pkt_tem_data               ( pkt_template_ram_q0[i]        ), //In
                .pkt_tem_rdptr              ( pkt_template_ram_raddr0[i]    ), //Out
                .pkt_tem_len                ( pkt_template_item_len         ),//????
                .sjump_ram_wea              (stream_jump_ram_wea_250m[i]    ),
                .sjump_ram_addra            (stream_jump_ram_addra_250m[i]  ),
                .sjump_ram_dina_1           (stream_jump_ram_dina_250m_1[i] ),
                .sjump_ram_dina_2           (stream_jump_ram_dina_250m_2[i] ), 
                .sjump_ram_addrb            (stream_jump_ram_addrb[i]       ),
                .sjump_ram_doutb_1          (stream_jump_ram_doutb1[i]      ),
                .sjump_ram_doutb_2          (stream_jump_ram_doutb2[i]      ),
                .m_gen_axis_tvalid          (gen_axis_tvalid    [i]         ),
                .m_gen_axis_tdata           (gen_axis_tdata     [i]         ),
                .m_gen_axis_tusef           (gen_axis_tusef     [i]         ),
                .m_gen_axis_tlast           (gen_axis_tlast     [i]         ),
                .m_gen_axis_tready          (gen_axis_tready    [i]         ),
                .m_gen_axis_fifo_afull      (gen_axis_fifo_afull[i]         ),
                .m_gen_axis_len             (gen_axis_len       [i]         ),
                .gen_info_fifo_wen          (gen_info_fifo_wen  [i]         ),
                .gen_info_fifo_wdata        (gen_info_fifo_wdata[i]         ),
                .gen_info_fifo_afull        (gen_info_fifo_afull[i]         ),
                .pkt_lw_wptr                (pkt_lw_wptr                    ),
                .pkt_lw_regs_0              (pkt_lw_regs[0]                 ),
                .pkt_lw_regs_1              (pkt_lw_regs[1]                 ),
                .pkt_lw_regs_2              (pkt_lw_regs[2]                 ),
                .pkt_lw_regs_3              (pkt_lw_regs[3]                 ),
                .pkt_lw_regs_4              (pkt_lw_regs[4]                 ),
                .pkt_lw_regs_5              (pkt_lw_regs[5]                 ),
                .pkt_lw_regs_6              (pkt_lw_regs[6]                 ),
                .pkt_lw_regs_7              (pkt_lw_regs[7]                 ), 
                .stream_cfg_done            (stream_cfg_done                ),
                .start_send                 (start_stop_cdc                 ),
                .max_packet_count           (stream_stop_len_reg[0*32+:32]  ),
                .max_send_time              (stream_stop_time_reg           ),
                .send_time_cnt              (stream_send_time_reg           ),
                .sending_status             (sending_status[i]              ),
                .pkt_send_stop_rst          ( pkt_send_stop_rst_axis_aclk[i]   ),
                .dyn_sip_start              ( dyn_sip_start       [1]      ),
                .dyn_sip_end                ( dyn_sip_end         [1]      ),
                .dyn_sip_step               ( dyn_sip_step        [1]      ),
                .dyn_sip_en                 ( dyn_sip_en          [1]      ),
                .dyn_dip_start              ( dyn_dip_start       [1]      ),
                .dyn_dip_end                ( dyn_dip_end         [1]      ),
                .dyn_dip_step               ( dyn_dip_step        [1]      ),
                .dyn_dip_en                 ( dyn_dip_en          [1]      ),
                .dyn_sport_start            ( dyn_sport_start     [1]      ),
                .dyn_sport_end              ( dyn_sport_end       [1]      ),
                .dyn_sport_step             ( dyn_sport_step      [1]      ),
                .dyn_sport_en               ( dyn_sport_en        [1]      ),
                .dyn_dport_start            ( dyn_dport_start     [1]      ),
                .dyn_dport_end              ( dyn_dport_end       [1]      ),
                .dyn_dport_step             ( dyn_dport_step      [1]      ),
                .dyn_dport_en               ( dyn_dport_en        [1]      ),
	            .ipv6_dyn_sip_start         ( ipv6_dyn_sip_start  [1]      ),  
                .ipv6_dyn_sip_end           ( ipv6_dyn_sip_end    [1]      ),
                .ipv6_dyn_sip_step          ( ipv6_dyn_sip_step   [1]      ),
                .ipv6_dyn_sip_en            ( ipv6_dyn_sip_en     [1]      ),
                .ipv6_dyn_dip_start         ( ipv6_dyn_dip_start  [1]      ),
                .ipv6_dyn_dip_end           ( ipv6_dyn_dip_end    [1]      ),
                .ipv6_dyn_dip_step          ( ipv6_dyn_dip_step   [1]      ),
                .ipv6_dyn_dip_en            ( ipv6_dyn_dip_en     [1]      ),
                .ipv6_dyn_sport_start       ( ipv6_dyn_sport_start[1]      ),
                .ipv6_dyn_sport_end         ( ipv6_dyn_sport_end  [1]      ),
                .ipv6_dyn_sport_step        ( ipv6_dyn_sport_step [1]      ),
                .ipv6_dyn_sport_en          ( ipv6_dyn_sport_en   [1]      ),
                .ipv6_dyn_dport_start       ( ipv6_dyn_dport_start[1]      ),
                .ipv6_dyn_dport_end         ( ipv6_dyn_dport_end  [1]      ),
                .ipv6_dyn_dport_step        ( ipv6_dyn_dport_step [1]      ),
                .ipv6_dyn_dport_en          ( ipv6_dyn_dport_en   [1]      ),
                .dyn_mode                   ( dyn_mode                     )
            );

            pkt_send_ch_dbuf#(
                .PORT_ID                    (i                              ),
                .DATA_W                     (DATA_W                         ),
                .INFO_W                     (INFO_W                         )
            )  
            u_pkt_send_ch_dbuf 
            (
                .clk                        ( axis_aclk                     ),
                .rst_n                      ( mac_rstn                      ),
                .cmac_clk                   ( cmac_clk                      ),
                .num_gap_a                  (num_gap_a                      ),
                .gap_a                      (gap_a                          ),
                .num_gap_b                  (num_gap_b                      ),
                .gap_b                      (gap_b                          ),
                .m_axis_tready              ( m_axis_pkt_tx_tready[i]       ),
                .m_axis_tdata               ( m_axis_pkt_tx_tdata[i*DATA_W+:DATA_W]),
                .m_axis_tusef               ( m_axis_pkt_tx_tusef[i*USEF_W+:USEF_W]),
                .m_axis_tvalid              ( m_axis_pkt_tx_tvalid[i]       ),
                .m_axis_tlast               ( m_axis_pkt_tx_tlast[i]        ),
                .m_axis_tsop                ( m_axis_pkt_tx_tuser_sop[i]    ),
                .m_axis_tid                 ( axis_ch_tuser_id[i]           ),
                .m_axis_tstamp_en           ( m_axis_pkt_tx_tuser_stamp_en[i]),
                .gen_axis_tvalid            (gen_axis_tvalid    [i]         ),
                .gen_axis_tdata             (gen_axis_tdata     [i]         ),
                .gen_axis_tlast             (gen_axis_tlast     [i]         ),
                .gen_axis_tusef             (gen_axis_tusef     [i]         ),
                .gen_axis_tready            (gen_axis_tready    [i]         ),
                .gen_axis_fifo_afull        (gen_axis_fifo_afull[i]         ),
                .gen_info_fifo_wen          (gen_info_fifo_wen  [i]         ),
                .gen_info_fifo_wdata        (gen_info_fifo_wdata[i]         ),
                .gen_info_fifo_afull        (gen_info_fifo_afull[i]         ),
                .axis_fifo_vld_err          (axis_fifo_vld_err  [i]         )
            );

            statistics_ram #(
                .DATA_W                     (32                 ),
                .ADDR_W                     (12                 ),
                .MODE                       ("CNT"              )//"MAX" "MIN" "CNT"
            )u11_pkt_cnt(
                .stream_pkt_tvalid          (gen_axis_tvalid[i] ),
                .stream_pkt_tlast           (gen_axis_tlast[i]  ),
                .stream_pkt_tready          (gen_axis_tready[i] ),
                .new_data                   (32'd1              ),
                .stream_pkt_id_w            (axis_ch_tuser_id[i][11:0]),
                .stream_pkt_r_req           (stream_pkt_r_req_mac_d3   ),
                .stream_pkt_id_r            (stream_pkt_id_r    ),
                .stream_pkt_rst             (tx_stream_stas_rst_mac_d3 ),
                .stream_pkt_rdata           (stream_pkt_rdata[i]),
                .axis_aclk                  (cmac_clk           ),
                .axil_aclk                  (axil_aclk          ),
                .axis_rstn                  (mac_rstn           )
            );

            statistics_ram #(
                .DATA_W                     (64                 ),
                .ADDR_W                     (12                 ),
                .MODE                       ("CNT"              )//"MAX" "MIN" "CNT"
            )u12_byte_cnt(
                .stream_pkt_tvalid          (gen_axis_tvalid[i] ),
                .stream_pkt_tlast           (gen_axis_tlast[i]  ),
                .stream_pkt_tready          (gen_axis_tready[i] ),
                .new_data                   (64'(gen_axis_len[i]+24)),
                .stream_pkt_id_w            (axis_ch_tuser_id[i][11:0]),
                .stream_pkt_r_req           (stream_pkt_r_req_mac_d3   ),
                .stream_pkt_id_r            (stream_pkt_id_r    ),
                .stream_pkt_rst             (tx_stream_stas_rst_mac_d3 ),
                .stream_pkt_rdata           (stream_byt_rdata[i]),
                .axis_aclk                  (cmac_clk           ),
                .axil_aclk                  (axil_aclk          ),
                .axis_rstn                  (mac_rstn           )
            );

            assign m_axis_pkt_tx_tuser_id[i*48+:16]     = {3'b0,pkt_time_delay_type_en,axis_ch_tuser_id[i][11:0]};
            assign m_axis_pkt_tx_tuser_id[(i*48+16)+:32]= axis_ch_tuser_id[i][16+:32];
            always@(posedge axil_aclk)begin
                if(!axil_rstn) begin
                    tx_pkt_stream_stas[i]   <= 64'd0;
                    tx_bytes_stream_stas[i] <= 64'd0;
                    tx_bps_stream_stas[i]   <= 64'd0;
                    tx_pps_stream_stas[i]   <= 64'd0;   
                end else if(reg_we & reg_en & reg_addr == STREAM_SEND_STAS_ID_ADDR) begin
                    if(reg_din[16] == 1'b1 && (reg_din[15:0] == 16'd1 ||  reg_din[15:0] == 16'd0)) begin
                        tx_pkt_stream_stas[i] <= 64'd0;
                        tx_bytes_stream_stas[i] <= 64'd0;
                        tx_bps_stream_stas[i]   <= 64'd0;
                        tx_pps_stream_stas[i]   <= 64'd0;  
                    end else if(reg_din[10:0] == 11'd1) begin
                        tx_pkt_stream_stas[i]   <= tx_pkt_stream_cnt[i];
                        tx_bytes_stream_stas[i] <= tx_bytes_stream_cnt[i];
                        tx_bps_stream_stas[i]   <= tx_bps_stream_reg[i];
                        tx_pps_stream_stas[i]   <= tx_pps_stream_reg[i];  
                    end 
                end
            end

            always@(posedge axis_aclk)begin
                if(gen_axis_tvalid[i] & gen_axis_tlast[i] & gen_axis_tready[i])
                    tx_pkt_stream_cnt[i] <= tx_pkt_stream_cnt[i] + 1;
                if(gen_axis_tvalid[i] & gen_axis_tready[i] & gen_axis_tlast[i])begin
                    tx_bytes_stream_cnt[i] <= tx_bytes_stream_cnt[i] + gen_axis_len[i][13:0] + 5'd24; // 4BYTES FCS ADDED,or GAP and other?
                end
                if(tx_stream_stas_rst_mac_d3) begin
                    tx_pkt_stream_cnt[i]   <= 64'd0;
                    tx_bytes_stream_cnt[i] <= 'd0;
                end
            end
    
            always@(posedge axis_aclk)begin
                if(gen_axis_tvalid[i] & gen_axis_tlast[i] & gen_axis_tready[i])
                    tx_pps_stream_cnt[i] <= tx_pps_stream_cnt[i] + 1;
                if(gen_axis_tvalid[i] & gen_axis_tready[i] & gen_axis_tlast[i])begin
                    tx_bps_stream_cnt[i] <= tx_bps_stream_cnt[i] + gen_axis_len[i][13:0] + 5'd24; // 4BYTES FCS ADDED,or GAP and other?
                end
                if(s_ena_400[2] & (!s_ena_400[3])) begin
                    tx_pps_stream_cnt[i] <= 64'd0;
                    tx_bps_stream_cnt[i] <= 64'd0;
                    tx_pps_stream_reg[i] <= tx_pps_stream_cnt[i];
                    tx_bps_stream_reg[i] <= tx_bps_stream_cnt[i] <<3;
                end
                if(!mac_rstn)begin
                    tx_pps_stream_cnt[i] <= 64'd0;
                    tx_bps_stream_cnt[i] <= 64'd0;
                    tx_pps_stream_reg[i] <= 64'd0;
                    tx_bps_stream_reg[i] <= 64'd0;
                end
            end
        end
    endgenerate

    always @(posedge axis_aclk ) begin
        m_gen_stop_en <= (|sending_status[0][3:1]) &  (|sending_status[1][3:1]);
    end

    always @(posedge axis_aclk ) begin
        tx_pkt_stream_stas_sum   <= tx_pkt_stream_stas  [0] + tx_pkt_stream_stas  [1];
        tx_bytes_stream_stas_sum <= tx_bytes_stream_stas[0] + tx_bytes_stream_stas[1];
        tx_pps_stream_stas_sum   <= tx_pps_stream_stas  [0] + tx_pps_stream_stas  [1];
        tx_bps_stream_stas_sum   <= tx_bps_stream_stas  [0] + tx_bps_stream_stas  [1]; 
        stream_pkt_rdata_sum     <= stream_pkt_rdata    [0] + stream_pkt_rdata    [1];    
        stream_byt_rdata_sum     <= stream_byt_rdata    [0] + stream_byt_rdata    [1];    
    end

    //  clear Current Stream Stats
    always@(posedge axil_aclk)
    begin
        if(!axil_rstn) begin
            tx_stream_stas_rst <= 1'b0;
            stream_pkt_r_req   <= 1'b0;
            stream_pkt_id_r    <= 16'd0; 
        end    
        else begin
            tx_stream_stas_rst <= 1'b0;
            stream_pkt_r_req <= 1'b0;
            if( reg_we & reg_en & reg_addr == STREAM_SEND_STAS_ID_ADDR)begin
               if( reg_din[16] & (reg_din[15:0] == 16'd1 || reg_din[15:0] == 16'd0))begin
                 tx_stream_stas_rst <= 1'b1;
                end 
                else if(~reg_din[16])begin
                  stream_pkt_r_req <= 1'b1;
                end
                stream_pkt_id_r <= reg_din[15:0];
            end  
        end
    end

    always @(posedge axil_aclk ) begin
        tx_stream_stas_rst_d1 <= tx_stream_stas_rst;
        stream_pkt_r_req_d1   <= stream_pkt_r_req;
    end

    always @(posedge axis_aclk ) begin
        tx_stream_stas_rst_mac_d1 <= tx_stream_stas_rst_d1 | tx_stream_stas_rst;
        tx_stream_stas_rst_mac_d2 <= tx_stream_stas_rst_mac_d1;
        tx_stream_stas_rst_mac_d3 <= tx_stream_stas_rst_mac_d2;

        stream_pkt_r_req_mac_d1 <= stream_pkt_r_req_d1 | stream_pkt_r_req;
        stream_pkt_r_req_mac_d2 <= stream_pkt_r_req_mac_d1;
        stream_pkt_r_req_mac_d3 <= stream_pkt_r_req_mac_d2;
    end

    function [6:0] keep2len;
        input [63:0] axis_keep;
        integer  sum ;
        begin : myblock
            integer i;
            sum = 0;
            for( i=0;i<=63;i=i+1)
                if(axis_keep[i])
                    sum = sum + 1;
            keep2len = sum;
        end
    endfunction

    always@(posedge axis_aclk)
    begin
        sending_d1 <= sending_status[0][0]|sending_status[1][0];
        sending_d2 <= sending_d1;
        if(!mac_rstn) begin
            sending_d1 <= 1'b0;
            sending_d2 <= 1'b0;
        end
    end
    
    assign sending_start_fb = ~sending_d2 & sending_d1;
    assign sending_stop_fb  = sending_d2 & ~sending_d1;
    always@(posedge axis_aclk)
    begin
        if(!mac_rstn) begin
            tx_send_start_time <= 64'd0;
            tx_send_stop_time <= 64'd0;
        end else if(sending_start_fb) begin
            tx_send_start_time <= time_stamp;
        end else if(sending_stop_fb) begin
            tx_send_stop_time <= time_stamp;
        end
    end

    always @(posedge axis_aclk ) begin
        if(sending_d2)
            stream_send_time_reg <= time_stamp - tx_send_start_time;
        else 
            stream_send_time_reg <= 64'b0;
    end

    clkena_gen clkena_gen_inst(
        .clk(axil_aclk),
        .rst_n(axil_rstn),
        .us_ena(us_ena),
        .ms_ena(ms_ena),
        .s_ena(s_ena)
    );

    always @(posedge axil_aclk ) begin
        if(!axil_rstn)
            s_ena_400[0] <= 1'b0;
        else if(s_ena)
            s_ena_400[0] <= 1'b1;
        else if(&wait_cnt)
            s_ena_400[0] <= 1'b0;
    end

    always @(posedge axil_aclk ) begin
        if(s_ena)
            wait_cnt <= 5'd1;
        else if(wait_cnt!=5'd0)
            wait_cnt <= wait_cnt + 1'b1;
        else 
            wait_cnt <= 5'd0;
    end

    always @(posedge axis_aclk ) begin
        s_ena_400[3:1] <= s_ena_400[2:0];
    end

	always@(posedge axil_aclk)
    begin
        if(!axil_rstn) 
            reg_dout <= 32'd0;
        else if(~reg_we & reg_en & reg_addr == STREAM_SEND_START_ADDR_0)
           reg_dout <= sending_status[0] | sending_status[1]; 
        else if(~reg_we & reg_en & reg_addr == STREAM_SEND_STOPC_ADDR_0) 
           reg_dout <= stream_stopc_reg;
        else if(~reg_we & reg_en & reg_addr == STREAM_SEND_STAS_PKTS_LOW_ADDR) 
           reg_dout <= tx_pkt_stream_stas_sum[31:0];
        else if(~reg_we & reg_en & reg_addr == STREAM_SEND_STAS_PKTS_HIGH_ADDR) 
           reg_dout <= tx_pkt_stream_stas_sum[63:32];
        else if(~reg_we & reg_en & reg_addr == STREAM_SEND_STAS_BYTES_LOW_ADDR) 
           reg_dout <= tx_bytes_stream_stas_sum[31:0];
        else if(~reg_we & reg_en & reg_addr == STREAM_SEND_STAS_BYTES_HIGH_ADDR) 
           reg_dout <= tx_bytes_stream_stas_sum[63:32];
        else if(~reg_we & reg_en & reg_addr == STREAM_SEND_STAS_BPS_LOW_ADDR) 
           reg_dout <= tx_bps_stream_stas_sum[31:0];
        else if(~reg_we & reg_en & reg_addr == STREAM_SEND_STAS_BPS_HIGH_ADDR) 
           reg_dout <= tx_bps_stream_stas_sum[63:32];
        else if(~reg_we & reg_en & reg_addr == STREAM_SEND_STAS_PPS_LOW_ADDR) 
           reg_dout <= tx_pps_stream_stas_sum[31:0];
        else if(~reg_we & reg_en & reg_addr == STREAM_SEND_STAS_PPS_HIGH_ADDR) 
           reg_dout <= tx_pps_stream_stas_sum[63:32];
        else if(~reg_we & reg_en & reg_addr == PKT_SEND_GAPA_ADDR)  // could be remove
           reg_dout <= gap_a;
        else if(~reg_we & reg_en & reg_addr == PKT_SEND_GAPB_ADDR)  // could be remove
           reg_dout <= gap_b;
        else if(~reg_we & reg_en & reg_addr == PKT_SEND_GAPNUM_ADDR)  // could be remove
           reg_dout <= {num_gap_b,num_gap_a};
        else if(~reg_we & reg_en & reg_addr == PKT_TIMESTAMP_DELAY_TYPE)
           reg_dout <= {31'b0,pkt_time_delay_type_en};
        else if(~reg_we & reg_en & reg_addr == PKT_DYN_SIP_START_ADDR) // could be remove
           reg_dout <= dyn_sip_start[0];
        else if(~reg_we & reg_en & reg_addr == PKT_DYN_SIP_END_ADDR) // could be remove
            reg_dout <= dyn_sip_end[0];
        else if(~reg_we & reg_en & reg_addr == PKT_DYN_SIP_EN_ADDR) // could be remove
            reg_dout <= {dyn_sip_step[0],15'd0,dyn_sip_en[0]};
        else if(~reg_we & reg_en & reg_addr == PKT_DYN_DIP_START_ADDR) // could be remove
            reg_dout <= dyn_dip_start[0];
        else if(~reg_we & reg_en & reg_addr == PKT_DYN_DIP_END_ADDR) // could be remove
            reg_dout <= dyn_dip_end[0];
        else if(~reg_we & reg_en & reg_addr == PKT_DYN_DIP_EN_ADDR) // could be remove
            reg_dout <= {dyn_dip_step[0],15'd0,dyn_dip_en[0]};
        else if(~reg_we & reg_en & reg_addr == PKT_DYN_SPORT_START_ADDR) // could be remove
            reg_dout <= dyn_sport_start[0];
        else if(~reg_we & reg_en & reg_addr == PKT_DYN_SPORT_END_ADDR) // could be remove
            reg_dout <= dyn_sport_end[0];
        else if(~reg_we & reg_en & reg_addr == PKT_DYN_SPORT_EN_ADDR) // could be remove
            reg_dout <= {dyn_sport_step[0],15'd0,dyn_sport_en[0]};
        else if(~reg_we & reg_en & reg_addr == PKT_DYN_DPORT_START_ADDR) // could be remove
            reg_dout <= dyn_dport_start[0];
        else if(~reg_we & reg_en & reg_addr == PKT_DYN_DPORT_END_ADDR) // could be remove
            reg_dout <= dyn_dport_end[0];
        else if(~reg_we & reg_en & reg_addr == PKT_DYN_DPORT_EN_ADDR) // could be remove
            reg_dout <= {dyn_dport_step[0],15'd0,dyn_dport_en[0]};
        else if(~reg_we & reg_en & reg_addr == PKT_DYN_MODE_ADDR) // could be remove
            reg_dout <= {31'd0,dyn_mode};
        else if(~reg_we & reg_en & reg_addr == STREAM_SEND_STOP_TIME_L_ADDR) // could be remove
            reg_dout <= stream_stop_time_reg[31:0];
        else if(~reg_we & reg_en & reg_addr == STREAM_SEND_STOP_TIME_H_ADDR) // could be remove
            reg_dout <= stream_stop_time_reg[63:32];
        else if(~reg_we & reg_en & reg_addr == STREAM_SEND_STOP_LEN_L_ADDR)
            reg_dout <= stream_stop_len_reg[31:0];
        else if(~reg_we & reg_en & reg_addr == STREAM_SEND_STOP_LEN_H_ADDR)
            reg_dout <= stream_stop_len_reg[63:32];        
        else if(~reg_we & reg_en & reg_addr == STREAM_SEND_STAS_START_LOW_ADDR) // time stampt for start
            reg_dout <= tx_send_start_time[31:0]; 
        else if(~reg_we & reg_en & reg_addr == STREAM_SEND_STAS_START_HIGH_ADDR)
            reg_dout <= tx_send_start_time[63:32]; 
        else if(~reg_we & reg_en & reg_addr == STREAM_SEND_STAS_STOP_LOW_ADDR) // time stamp for stop
            reg_dout <= tx_send_stop_time[31:0]; 
        else if(~reg_we & reg_en & reg_addr == STREAM_SEND_STAS_STOP_HIGH_ADDR)
            reg_dout <= tx_send_stop_time[63:32]; 
        else if(~reg_we & reg_en & reg_addr == STREAM_SEND_STAS_ID_ADDR) 
            reg_dout <= stream_start_stop_reg[31:0];
        else if(~reg_we & reg_en & reg_addr == STREAM_ID_SEND_PKTS_LOW_ADDR)
            reg_dout <= stream_pkt_rdata_sum;
        else if(~reg_we & reg_en & reg_addr == STREAM_ID_SEND_PKTS_HIGH_ADDR)
            reg_dout <= 0;  
        else if(~reg_we & reg_en & reg_addr == STREAM_ID_SEND_BYTES_LOW_ADDR)
            reg_dout <= stream_byt_rdata_sum[31:0];      
        else if(~reg_we & reg_en & reg_addr == STREAM_ID_SEND_BYTES_HIGH_ADDR)
            reg_dout <= stream_byt_rdata_sum[63:32];                
        else if(~reg_we & reg_en & reg_addr == PKT_TEMPLATE_LEN0)
            reg_dout <= {20'd0,pkt_template_item_len};
        else if(~reg_we & reg_en & reg_addr == DEBUG_STATUS_ADDR)
            reg_dout <= {26'd0,axis_fifo_vld_err[0],axis_fifo_vld_err[1],gen_info_fifo_afull[0],gen_info_fifo_afull[1],gen_axis_fifo_afull[0],gen_axis_fifo_afull[1]};
        else if(~reg_we & reg_en & reg_addr == STREAM_JUMP_NUM0)
            reg_dout <= stream_jump_num;
        else if(~reg_we & reg_en & reg_addr == PKT_LW_PTR_RESET)
            reg_dout <= {27'b0,pkt_lw_wptr}; //reg_din[12:0];
        else 
            reg_dout <= 32'hdeadbeef;
    end
    

endmodule
`resetall

