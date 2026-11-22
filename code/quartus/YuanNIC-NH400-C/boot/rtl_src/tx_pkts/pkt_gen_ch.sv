`resetall
`timescale 1ns /100ps
`default_nettype none
module pkt_gen_ch#(
    parameter                   DATA_W          = 1024,
    parameter                   INFO_W          = 36+12+16,
    parameter                   ADDR_W          = 12  ,
    parameter                   CFG_ADDR_W      = 10  ,
    parameter                   CFG_DATA_W      = 64  ,
    parameter                   PORT_ID         = 0
)
(
    input   wire                            clk,
    input   wire                            rst_n,
    output  reg     [ADDR_W-1:0]            pkt_tem_rdptr, // ADDR for Template buf READ
    input   wire    [DATA_W-1:0]            pkt_tem_data, // DATA from Template buf
    input   wire    [ADDR_W-1:0]            pkt_tem_len, 
    output  reg                             sjump_ram_renb,
    output  reg     [ADDR_W-1:0]            sjump_ram_addrb,
    input   wire    [44-1:0]                sjump_ram_doutb,
    output  reg                             m_gen_axis_tvalid,
    output  reg     [DATA_W-1:0]            m_gen_axis_tdata,
    output  reg     [$clog2(DATA_W/8)-1:0]  m_gen_axis_tusef,
    output  reg                             m_gen_axis_tlast,
    output  reg     [15:0]                  m_gen_axis_len,
    input   wire                            m_gen_axis_tready,
    input   wire                            m_gen_axis_fifo_afull,
    output  reg                             gen_info_fifo_wen,
    output  reg     [INFO_W-1:0]            gen_info_fifo_wdata,
    input   wire                            gen_info_fifo_afull,
    input   wire    [4:0]                   pkt_lw_wptr,
    input   wire    [21:0]                  pkt_lw_regs_0,
    input   wire    [21:0]                  pkt_lw_regs_1,
    input   wire    [21:0]                  pkt_lw_regs_2,
    input   wire    [21:0]                  pkt_lw_regs_3,
    input   wire    [21:0]                  pkt_lw_regs_4,
    input   wire    [21:0]                  pkt_lw_regs_5,
    input   wire    [21:0]                  pkt_lw_regs_6,
    input   wire    [21:0]                  pkt_lw_regs_7,
    input   wire    [15:0]                  num_gap_a,
    input   wire    [31:0]                  gap_a,
    input   wire    [15:0]                  num_gap_b,
    input   wire    [31:0]                  gap_b,
    input   wire                            stream_cfg_done,
    input   wire                            start_send,
    input   wire    [31:0]                  max_packet_count,
    input   wire    [63:0]                  max_send_time,
    input   wire    [63:0]                  send_time_cnt,
    output  wire    [31:0]                  sending_status,
    output  reg                             pkt_send_stop_rst,
    input   wire    [31:0]                  dyn_sip_start,
    input   wire    [31:0]                  dyn_sip_end,
    input   wire    [15:0]                  dyn_sip_step,
    input   wire                            dyn_sip_en,
    input   wire    [31:0]                  dyn_dip_start,
    input   wire    [31:0]                  dyn_dip_end,
    input   wire    [15:0]                  dyn_dip_step,
    input   wire                            dyn_dip_en,
    input   wire    [15:0]                  dyn_sport_start,
    input   wire    [15:0]                  dyn_sport_end,
    input   wire    [15:0]                  dyn_sport_step,
    input   wire                            dyn_sport_en,
    input   wire    [15:0]                  dyn_dport_start,
    input   wire    [15:0]                  dyn_dport_end,
    input   wire    [15:0]                  dyn_dport_step,
    input   wire                            dyn_dport_en,
    input   wire    [127:0]                 ipv6_dyn_sip_start,
    input   wire    [127:0]                 ipv6_dyn_sip_end,
    input   wire    [15:0]                  ipv6_dyn_sip_step,
    input   wire                            ipv6_dyn_sip_en,
    input   wire    [127:0]                 ipv6_dyn_dip_start,
    input   wire    [127:0]                 ipv6_dyn_dip_end,
    input   wire    [15:0]                  ipv6_dyn_dip_step,
    input   wire                            ipv6_dyn_dip_en,
    input   wire    [15:0]                  ipv6_dyn_sport_start,
    input   wire    [15:0]                  ipv6_dyn_sport_end,
    input   wire    [15:0]                  ipv6_dyn_sport_step,
    input   wire                            ipv6_dyn_sport_en,
    input   wire    [15:0]                  ipv6_dyn_dport_start,
    input   wire    [15:0]                  ipv6_dyn_dport_end,
    input   wire    [15:0]                  ipv6_dyn_dport_step,
    input   wire                            ipv6_dyn_dport_en,
    input   wire                            dyn_mode// 0: SIP->DIP->SPORT-DPORT,1:DIP->SIP->DPORT->SPORT
);                                        
    localparam ETH_DMAC_OFFSET              = 0;                             //0
    localparam ETH_SMAC_OFFSET              = ETH_DMAC_OFFSET +48;           //48
    localparam ETH_LEN_TYPE_OFFSET          = ETH_SMAC_OFFSET +48;           //96
    
    localparam IP_PKT_START_POS             = 14<<3;                                //112
    localparam IP_PKT_VERSION               = IP_PKT_START_POS;                     //112
    localparam IP_PKT_HEADER_LEN            = IP_PKT_VERSION +4;             //116
    localparam IP_PKT_TOS                   = IP_PKT_HEADER_LEN +4;          //120
    localparam IP_PKT_LENGTH                = IP_PKT_TOS + 8;                //128
    localparam IP_PKT_IDENT                 = IP_PKT_LENGTH + 16;            //144
    localparam IP_PKT_FLAGS                 = IP_PKT_IDENT + 16;             //160
    localparam IP_PKT_FRAGMENT              = IP_PKT_FLAGS +3;               //163
    localparam IP_PKT_TTL                   = IP_PKT_FRAGMENT + 13;          //176
    localparam IP_PKT_PROTOCOL              = IP_PKT_TTL + 8;                //184
    localparam IP_PKT_HEADER_CKSM           = IP_PKT_PROTOCOL + 8;           //192
    localparam IP_PKT_SRC_IP                = IP_PKT_HEADER_CKSM + 16;       //208
    localparam IP_PKT_DEST_IP               = IP_PKT_SRC_IP + 32;            //240
    localparam IP_PKT_HEADER_OP             = IP_PKT_DEST_IP + 32;           //272
    localparam UDP_PKT_START_POS            = IP_PKT_HEADER_OP + 0;          //272
    localparam UDP_PKT_SPORT                = UDP_PKT_START_POS;             //272
    localparam UDP_PKT_DPORT                = UDP_PKT_SPORT + 16;            //288
    localparam UDP_PKT_LENGTH               = UDP_PKT_DPORT + 16;            //304
    localparam UDP_PKT_CKSM                 = UDP_PKT_LENGTH + 16;           //320

    localparam IPV6_PKT_START_POS           = 14<<3;                         //112
    localparam IPV6_PKT_VERSION             = IPV6_PKT_START_POS;            //112
    localparam IPV6_PKT_PAYLOAD_LEN         = IPV6_PKT_VERSION + (4<<3);     //144
    localparam IPV6_PKT_NEXTHDR             = IPV6_PKT_PAYLOAD_LEN + (2<<3); //160
    localparam IPV6_PKT_HOPLIMIT            = IPV6_PKT_NEXTHDR + (1<<3);     //168
    localparam IPV6_PKT_SRC_IP              = IPV6_PKT_HOPLIMIT + (1<<3);    //176
    localparam IPV6_PKT_DEST_IP             = IPV6_PKT_SRC_IP + (16<<3);     //304
    localparam IPV6_PKT_EXTE_HEADER         = IPV6_PKT_DEST_IP + (16<<3);    //432
    localparam UDP_V6_PKT_START_POS         = IPV6_PKT_EXTE_HEADER + 0;      //432
    localparam UDP_V6_PKT_SPORT             = UDP_V6_PKT_START_POS;          //432
    localparam UDP_V6_PKT_DPORT             = UDP_V6_PKT_SPORT + 16;         //448
    localparam UDP_V6_PKT_LENGTH            = UDP_V6_PKT_DPORT + 16;         //464
    localparam UDP_V6_PKT_CKSM              = UDP_V6_PKT_LENGTH + 16;        //480

    localparam VLAN1_V6_UDP_CKSM            = 0;
    localparam VLAN2_V6_UDP_DPORT           = 0;
    localparam VLAN2_V6_UDP_LENGTH          = VLAN2_V6_UDP_DPORT + 16;
    localparam VLAN2_V6_UDP_CKSM            = VLAN2_V6_UDP_LENGTH + 16;
    
    localparam ETH_VLAN1_OFFSET             = 96;
    localparam ETH_VLAN2_OFFSET             = ETH_VLAN1_OFFSET + 32;
    localparam ETH_TYPE_OFFSET              = ETH_VLAN2_OFFSET + 32;
    localparam ETH_VLAN_TYPE0               = 16'h0081;
    localparam ETH_VLAN_TYPE1               = 16'hA888;
    localparam ETH_VLAN_TYPE2               = 16'h0091;
    localparam ETH_VLAN_TYPE3               = 16'h0092;
    localparam ETH_IPV4_TYPE                = 16'h0008;
    localparam ETH_IPV6_TYPE                = 16'hDD86;

    localparam MAX_JUMP_NUM                     = 1;

    reg                     start_send_ff[0:0];
    reg                     stream_cfg_done_ff[0:0];
    reg                     start_send_flag;
    reg                     sending_vld ;
    wire                    time_send_en ;
    wire                    pkt_send_en ;
    reg     [31:0]          send_pkt_cnt;
    reg                     direct_stop;
    reg                     time_stop;
    reg                     cnt_stop;
    reg     [4:0]           pkt_lw_rptr;
    wire                    rd_new_pkt;
    reg                     rd_fir_head;
    reg                     payload_add;
    reg                     payload_wait_afull;
    wire                    cur_pkt_end;
    reg                     wait_fifo_afull;
    reg     [15:0]          pkt_length_cfg;
    reg     [2:0]           len_loop_cnt;
    reg     [7:0]           pkt_weight_cfg;
    reg     [7:0]           weight_loop_cnt;
    reg     [15:0]          payload_add_cnt;
    reg     [4:0]           deal_end_vld;
    reg     [7:0]           gen_head_vld;
    reg     [3:0]           gen_pkt_vld;
    reg     [DATA_W-1:0]    gen_pkt_data[3:1];
    wire    [15:0]          vlan_type1[0:0];
    wire    [15:0]          vlan_type2[0:0];
    reg                     vlan1_flag[4:1];
    reg                     vlan2_flag[4:1];
    wire    [15:0]          eth_type[1:1];
    reg     [15:0]          eth_type_reg[2:2];
    wire    [159:0]         ipv4_old_head[2:2];
    reg     [31:0]          ipv4_new_sip[3:1];
    reg     [31:0]          ipv4_new_dip[3:2];
    reg     [15:0]          ipv4_new_sport[3:3];
    reg     [15:0]          ipv4_new_dport[3:3];
    reg     [31:0]          ipv6_new_sip[3:1];
    reg     [31:0]          ipv6_new_dip[3:2];
    reg     [15:0]          ipv6_new_sport[4:3];
    reg     [15:0]          ipv6_new_dport[4:3];  
    reg                     ipv4_sip_en[4:3];
    reg                     ipv4_dip_en[4:3];
    reg                     ipv4_sport_en[4:3];
    reg                     ipv4_dport_en[4:3];
    reg                     ipv6_sip_en[4:3];
    reg                     ipv6_dip_en[4:3];
    reg                     ipv6_sport_en[4:3];
    reg                     ipv6_dport_en[4:3];
    wire                    ipv4_dip_of[2:2] ;
    reg                     ipv4_sip_of[2:2] ;
    wire                    ipv4_dport_of[3:3] ;
    wire                    ipv4_sport_of[3:3] ;
    wire                    ipv6_dip_of[2:2] ;
    reg                     ipv6_sip_of[2:2] ;
    wire                    ipv6_dport_of[3:3] ;
    wire                    ipv6_sport_of[3:3] ;
    reg                     ipv4_change_of[2:2] ;
    reg                     ipv6_change_of[2:2] ;
    reg                     dipv4_chge_vld_d2;
    reg                     spv4_chge_vld_d3;
    reg                     dpv4_chge_vld_d3;
    reg                     dipv6_chge_vld_d2;
    reg                     dpv6_chge_vld_d3;
    reg                     spv6_chge_vld_d3;   
    reg                     ipv4_flag[3:2];
    reg                     ipv6_flag[5:2];
    reg     [15:0]          ip_len[3:3];
    reg     [15:0]          udp_len[4:4];
    reg     [15:0]          pkt_len_cfg_reg[4:0];
    reg     [159:0]         ipv4_header[4:4];
    reg     [17:0]          ip_cksm_5d[3:0];
    reg     [18:0]          ip_cksm_6d[1:0];
    reg     [19:0]          ip_cksm_7d;
    reg     [9:0]           gen_pkt_wcnt[3:0];
    reg     [11:0]          pkt_stream_id[4:0];
    reg                     calc_udp_cksm_en[5:5];
    reg                     calc_udp_cksm_sop[5:5];
    reg                     calc_udp_cksm_eop[5:5];
    reg     [DATA_W-1:0]    calc_udp_cksm_dt[5:5];
    reg     [DATA_W-1:0]    m_gen_axis_tkeep;
    wire    [DATA_W-1:0]    m_gen_axis_tkeep_512[4:4];
    wire                    udp_cksm_en[13:13];
    wire    [15:0]          udp_cksm[13:13];
    reg     [INFO_W-17:0]   udp_cksm_offset[13:5];
    wire                    pkt_fifo_afull;
    reg     [11:0]          pkt_send_stop;
    reg     [1023:0]        pkt_tem_data_d1[2:1];
    reg                     cur_pkt_end_d1[2:1];
    reg                     rd_fir_head_d1[2:1];
    reg                     rd_sec_head_d1[2:1];
    reg                     payload_add_d1[2:1];
    reg     [15:0]          pkt_length_cfg_d1[2:1];
    reg     [15:0]          payload_add_cnt_d1[2:1];
    reg     [12:0]          pkt_tem_rdptr_d1[2:1];
    
    wire    [3:0]           tuple_mask_d1;
    reg     [3:0]           tuple_mask_d2;
    wire    [6:0]           tuple_offset_d1;
    reg     [6:0]           tuple_offset_d2;
    wire    [31:0]          tuple_add;

    reg     [31:0]          tuple_add_rslt_d2;

/*配置完成，开始生成报文*/
    //报文发送、停止管理
    assign pkt_fifo_afull = gen_info_fifo_afull | m_gen_axis_fifo_afull;

    always @(posedge clk ) begin
        start_send_ff[0]    <= start_send;
        stream_cfg_done_ff[0]  <= stream_cfg_done;
    end

    always @(posedge clk ) begin
        if((!pkt_fifo_afull) && stream_cfg_done && start_send & (!start_send_ff[0]))
            start_send_flag <= 1'b1;
        else if((!pkt_fifo_afull) && start_send_ff[0] && stream_cfg_done && (!stream_cfg_done_ff[0]))
            start_send_flag <= 1'b1;
        else  
            start_send_flag <= 1'b0;
    end

    assign time_send_en    = max_send_time    > 0 ? 1'b1 : 1'b0;
    assign pkt_send_en     = max_packet_count > 0 ? 1'b1 : 1'b0;

    always @(posedge clk ) begin
        if(~sending_vld)
            send_pkt_cnt <= 32'd1+PORT_ID;
        else if(rd_fir_head)
            send_pkt_cnt <= send_pkt_cnt + 2'd2;
    end

    always @(posedge clk ) begin
        if(!rst_n)
            sending_vld <= 1'b0;
        else if((!start_send_ff[0]) || (time_send_en && send_time_cnt>= max_send_time))
            sending_vld <= 1'b0;
        else if(pkt_send_en & rd_fir_head & send_pkt_cnt+1 >= max_packet_count)
            sending_vld <= 1'b0;
        else if(start_send_flag)
            sending_vld <= 1'b1;
    end
    always @(posedge clk ) begin
        direct_stop       <= start_send_flag ? 1'b0 : (!start_send) & start_send_ff[0] & (!time_stop) & (!cnt_stop) ? 1'b1 : direct_stop;
        time_stop         <= start_send_flag ? 1'b0 : time_send_en && send_time_cnt>= max_send_time   ? 1'b1 : time_stop;
        cnt_stop          <= start_send_flag ? 1'b0 : rd_fir_head & pkt_send_en && send_pkt_cnt+1 >= max_packet_count ? 1'b1 : cnt_stop;
        pkt_send_stop[11:0]<= {pkt_send_stop[10:0],(time_stop | cnt_stop)};
    end

    always @(posedge clk ) begin
        if(!rst_n)
            pkt_send_stop_rst <= 1'b0;
        else if(pkt_send_stop == 12'h001)
            pkt_send_stop_rst <= 1'b1;
        else if(pkt_send_stop == 12'hfff)
            pkt_send_stop_rst <= 1'b0;
    end
    assign sending_status = {28'b0,time_stop,direct_stop,cnt_stop,sending_vld};

    //流模版读取结束、payload填充待结束之后读取新模版
    always @(posedge clk ) begin
        if(rd_fir_head & pkt_send_en & send_pkt_cnt+1 >= max_packet_count)
            rd_fir_head <= 1'b0;
        else if(sending_vld && (!pkt_fifo_afull) && (wait_fifo_afull | cur_pkt_end))//后级反压，等待反压结束之后 或者 报文eop的时候 接续发包 
            rd_fir_head <= 1'b1;
        else 
            rd_fir_head <= start_send_flag;
    end

    always @(posedge clk ) begin
        if(!rst_n)
            payload_add <= 1'b0;
        else if((payload_add && payload_add_cnt >= pkt_length_cfg_d1[1]) || (pkt_fifo_afull && payload_add))
            payload_add <= 1'b0;
        else if((rd_fir_head && pkt_length_cfg > 16'(DATA_W/8)) || (payload_wait_afull && (!pkt_fifo_afull)))
            payload_add <= 1'b1;
    end

    always @(posedge clk ) begin
        if(!rst_n)
            payload_wait_afull <= 1'b0;
        else if(payload_wait_afull && (!pkt_fifo_afull))
            payload_wait_afull <= 1'b0;
        else if(payload_add && payload_add_cnt < pkt_length_cfg_d1[1] && pkt_fifo_afull)
            payload_wait_afull <= 1'b1;
    end
    //初始值为流模版中的128字节加上第一次填充的128字节
    always @(posedge clk ) begin
        if(!rst_n)
            payload_add_cnt <= 16'd128+16'(DATA_W/8);//从256开始计数
        else if(rd_fir_head)
            payload_add_cnt <= 16'd128+16'(DATA_W/8);//从256开始计数
        else if(payload_add)
            payload_add_cnt <= payload_add_cnt + 16'(DATA_W/8);
    end

    assign cur_pkt_end    = (pkt_length_cfg <= 16'(DATA_W/8) & rd_fir_head) ? 1'b1 : payload_add && payload_add_cnt >= pkt_length_cfg_d1[1];

    always @(posedge clk ) begin
        if(!rst_n)
            wait_fifo_afull <= 1'b0;
        else if(!pkt_fifo_afull)
            wait_fifo_afull <= 1'b0;
        else if(cur_pkt_end && pkt_fifo_afull)
            wait_fifo_afull <= 1'b1;
    end
    
    always @(posedge clk ) begin
        if((rd_fir_head && (weight_loop_cnt >= pkt_weight_cfg)) | (start_send_flag))
            weight_loop_cnt <= 8'd1;
        else if(rd_fir_head)
            weight_loop_cnt <= weight_loop_cnt + 1'b1;
    end

    always @(posedge clk ) begin
        if(pkt_lw_wptr[2:0] == 3'd1)
            len_loop_cnt <= 3'd0;
        else if(start_send_flag)
            len_loop_cnt <= 3'd1;
        else if(rd_fir_head && (len_loop_cnt+3'd1) == pkt_lw_wptr[2:0] && (weight_loop_cnt >= pkt_weight_cfg))
            len_loop_cnt <= 3'd0;
        else if(rd_fir_head && (weight_loop_cnt >= pkt_weight_cfg))
            len_loop_cnt <= len_loop_cnt + 1'b1;
    end

    always @(posedge clk ) begin
        if(start_send_flag)begin 
            pkt_length_cfg <= pkt_lw_regs_0[21:8];
            pkt_weight_cfg <= pkt_lw_regs_0[7:0];
        end  
        else if(rd_fir_head && (weight_loop_cnt >= pkt_weight_cfg))
            case (len_loop_cnt)
                3'd0:{pkt_length_cfg,pkt_weight_cfg} <= {2'b0,pkt_lw_regs_0[21:0]};
                3'd1:{pkt_length_cfg,pkt_weight_cfg} <= {2'b0,pkt_lw_regs_1[21:0]};
                3'd2:{pkt_length_cfg,pkt_weight_cfg} <= {2'b0,pkt_lw_regs_2[21:0]};
                3'd3:{pkt_length_cfg,pkt_weight_cfg} <= {2'b0,pkt_lw_regs_3[21:0]};
                3'd4:{pkt_length_cfg,pkt_weight_cfg} <= {2'b0,pkt_lw_regs_4[21:0]};
                3'd5:{pkt_length_cfg,pkt_weight_cfg} <= {2'b0,pkt_lw_regs_5[21:0]};
                3'd6:{pkt_length_cfg,pkt_weight_cfg} <= {2'b0,pkt_lw_regs_6[21:0]};
                3'd7:{pkt_length_cfg,pkt_weight_cfg} <= {2'b0,pkt_lw_regs_7[21:0]};
            endcase
    end

    //发送 读取流模版的ram地址
    //stream jump table rd and wr
    always @(posedge clk ) begin
        if(start_send_flag & pkt_tem_len > 1) begin
            pkt_tem_rdptr   <= ADDR_W'(PORT_ID);
            sjump_ram_addrb <= ADDR_W'(PORT_ID);
        end else if((cur_pkt_end && (pkt_tem_rdptr+2 == pkt_tem_len)) || pkt_tem_len == 1 ) begin
            pkt_tem_rdptr   <= ADDR_W'(0);
            sjump_ram_addrb <= ADDR_W'(0);
        end else if(cur_pkt_end && (pkt_tem_rdptr+1 == pkt_tem_len)) begin
            pkt_tem_rdptr   <= ADDR_W'(1);
            sjump_ram_addrb <= ADDR_W'(1);
        end else if(cur_pkt_end) begin
            pkt_tem_rdptr   <= pkt_tem_rdptr + 2'd2;
            sjump_ram_addrb <= sjump_ram_addrb + 2'd2;
        end

        sjump_ram_renb <= start_send_flag | cur_pkt_end;
    end

    always @(posedge clk ) begin
        cur_pkt_end_d1[2:1]      <= {cur_pkt_end_d1[1]    ,cur_pkt_end      };
        rd_fir_head_d1[2:1]      <= {rd_fir_head_d1[1]    ,rd_fir_head      };
        payload_add_d1[2:1]      <= {payload_add_d1[1]    ,payload_add      };
        payload_add_cnt_d1[2:1]  <= {payload_add_cnt_d1[1],payload_add_cnt  };
        pkt_tem_rdptr_d1[2:1]    <= {pkt_tem_rdptr_d1[1]  ,pkt_tem_rdptr    };
        pkt_tem_data_d1[2:1]     <= {pkt_tem_data_d1[1]   ,pkt_tem_data     };
        if(!rst_n)
            pkt_length_cfg_d1[1] <= 16'd0;
        else if(rd_fir_head)
            pkt_length_cfg_d1[1] <= pkt_length_cfg  ;

        pkt_length_cfg_d1[2] <= pkt_length_cfg_d1[1]  ;
    end

    always @(posedge clk ) begin
        deal_end_vld[4:0]     <= {deal_end_vld[3:0],cur_pkt_end_d1[2]};
        gen_head_vld[7:0]     <= {gen_head_vld[6:0],rd_fir_head_d1[2]};
        gen_pkt_vld[3:0]      <= {gen_pkt_vld[2:0],(rd_fir_head_d1[2] | payload_add_d1[2])} ;
        pkt_len_cfg_reg[4:0]  <= {pkt_len_cfg_reg[3:0],pkt_length_cfg_d1[2]};
        gen_pkt_wcnt[3:0]     <= {gen_pkt_wcnt[2:0],payload_add_cnt_d1[2][15:6]};
        pkt_stream_id[4:0]    <= {pkt_stream_id[3:0],pkt_tem_rdptr_d1[2][12:1]};
        tuple_mask_d2         <= tuple_mask_d1;
        tuple_offset_d2       <= tuple_offset_d1;
    end

    assign tuple_offset_d1  = sjump_ram_doutb[42:36];
    assign tuple_mask_d1    = sjump_ram_doutb[35:32];
    assign tuple_add        = sjump_ram_doutb[31:00];

    always @(posedge clk ) begin
        tuple_add_rslt_d2 <= swap_4bytes(pkt_tem_data_d1[2][(tuple_offset_d1*8+7)-:32]) + tuple_add;
    end
    
    always @(posedge clk ) begin
        if(|gen_head_vld[1])
            gen_pkt_data[2] <=  pkt_tem_data_d1[2];
        else begin   
            gen_pkt_data[2] <= 1024'b0;
        end

        gen_pkt_data[3]       <= gen_pkt_data[2];

        if(gen_head_vld[2] & tuple_mask_d2[0])//1st 64B
            gen_pkt_data[3][ (tuple_offset_d2*8+7-00)-:8] <=  swap_4bytes_3(tuple_add_rslt_d2);//[31:24];
        if(gen_head_vld[2] & tuple_mask_d2[1])//2st 64B
            gen_pkt_data[3][ (tuple_offset_d2*8+7-08)-:8] <=  swap_4bytes_2(tuple_add_rslt_d2);//[23:16];
        if(gen_head_vld[2] & tuple_mask_d2[2])//3st 64B
            gen_pkt_data[3][ (tuple_offset_d2*8+7-16)-:8] <=  swap_4bytes_1(tuple_add_rslt_d2);//[15: 8];
        if(gen_head_vld[2] & tuple_mask_d2[3])//4st 64B
            gen_pkt_data[3][ (tuple_offset_d2*8+7-24)-:8] <=  swap_4bytes_0(tuple_add_rslt_d2);//[ 7: 0];
    end

    //对流模版进行简单解析
    assign vlan_type1[0] =  pkt_tem_data[ETH_VLAN1_OFFSET +:16];
    assign vlan_type2[0] =  pkt_tem_data[ETH_VLAN2_OFFSET +:16];

    always @(posedge clk ) begin
        if(gen_head_vld[0] && (!((vlan_type1[0]^ETH_VLAN_TYPE0) && (vlan_type1[0]^ETH_VLAN_TYPE1) && (vlan_type1[0]^ETH_VLAN_TYPE2) && (vlan_type1[0]^ETH_VLAN_TYPE3))) && 
                              (  (vlan_type2[0]^ETH_VLAN_TYPE0) && (vlan_type2[0]^ETH_VLAN_TYPE1) && (vlan_type2[0]^ETH_VLAN_TYPE2) && (vlan_type2[0]^ETH_VLAN_TYPE3)))
            vlan1_flag[1] <= 1'b1;
        else 
            vlan1_flag[1] <= 1'b0;

        vlan1_flag[4:2] <= vlan1_flag[3:1];
    end

    always @(posedge clk ) begin
        if(gen_head_vld[0] && (!((vlan_type1[0]^ETH_VLAN_TYPE0) && (vlan_type1[0]^ETH_VLAN_TYPE1) && (vlan_type1[0]^ETH_VLAN_TYPE2) && (vlan_type1[0]^ETH_VLAN_TYPE3))) && 
                              (!((vlan_type2[0]^ETH_VLAN_TYPE0) && (vlan_type2[0]^ETH_VLAN_TYPE1) && (vlan_type2[0]^ETH_VLAN_TYPE2) && (vlan_type2[0]^ETH_VLAN_TYPE3))))
            vlan2_flag[1] <= 1'b1;
        else 
            vlan2_flag[1] <= 1'b0;

        vlan2_flag[4:2] <= vlan2_flag[3:1];
    end

    assign eth_type[1] = vlan1_flag[1]   ? pkt_tem_data_d1[2][ETH_VLAN2_OFFSET+:16] :
                         vlan2_flag[1]   ? pkt_tem_data_d1[2][ETH_TYPE_OFFSET+:16]  :
                         gen_head_vld[1] ? pkt_tem_data_d1[2][ETH_VLAN1_OFFSET+:16] :eth_type_reg[2] ;
    always @(posedge clk ) begin
        eth_type_reg[2] <= eth_type[1];
    end

    assign ipv4_old_head[2] = vlan1_flag[2] ? gen_pkt_data[2][(IP_PKT_START_POS+32)+:160] :
                              vlan2_flag[2] ? gen_pkt_data[2][(IP_PKT_START_POS+64)+:160] : gen_pkt_data[2][IP_PKT_START_POS+:160] ;
    //ip 和 port的跳变控制
    //ipv4
    always @(posedge clk ) begin
        if(start_send_flag)
            ipv4_new_sip[1] <= dyn_sip_start;
        else if(dyn_sip_en && deal_end_vld[1] && eth_type[1] == ETH_IPV4_TYPE && (ipv4_new_sip[1] + dyn_sip_step) > (dyn_sip_end))
            ipv4_new_sip[1] <= dyn_sip_start;
        else if(dyn_sip_en && deal_end_vld[1] && eth_type[1] == ETH_IPV4_TYPE)
            ipv4_new_sip[1] <= ipv4_new_sip[1] + dyn_sip_step;
        
        ipv4_new_sip[3:2] <= ipv4_new_sip[2:1];
    end

    always @(posedge clk ) begin
        ipv4_sip_of[2] <= (!dyn_sip_en) || (dyn_sip_en && (ipv4_new_sip[1] + dyn_sip_step) > (dyn_sip_end));
    end
    
    always @(posedge clk ) begin
        dipv4_chge_vld_d2 <= dyn_dip_en & deal_end_vld[1] & eth_type[1] == ETH_IPV4_TYPE;

        if(start_send_flag)
            ipv4_new_dip[2] <= dyn_dip_start;
        else if(dipv4_chge_vld_d2 && (ipv4_new_dip[2] + dyn_dip_step) > (dyn_dip_end) && ipv4_sip_of[2])
            ipv4_new_dip[2] <= dyn_dip_start;
        else if(dipv4_chge_vld_d2 && ipv4_sip_of[2])
            ipv4_new_dip[2] <= ipv4_new_dip[2] + dyn_dip_step;
        
        ipv4_new_dip[3] <= ipv4_new_dip[2];
    end

    assign ipv4_dip_of[2] = (!dyn_dip_en) || (dyn_dip_en && (ipv4_new_dip[2] + dyn_dip_step) > (dyn_dip_end));

    always @(posedge clk ) begin
        if(deal_end_vld[2] && ipv4_dip_of[2] && ipv4_sip_of[2])
            ipv4_change_of[2] <= 1'b1;
        else 
            ipv4_change_of[2] <= 1'b0;
    end
  
    always @(posedge clk ) begin
        spv4_chge_vld_d3 <= deal_end_vld[2] && dyn_sport_en && ipv4_flag[2];
        if( start_send_flag)
            ipv4_new_sport[3] <= dyn_sport_start;
        else if(ipv4_change_of[2] && spv4_chge_vld_d3  && (ipv4_new_sport[3] + dyn_sport_step) > dyn_sport_end)
            ipv4_new_sport[3] <= dyn_sport_start;
        else if(ipv4_change_of[2] && spv4_chge_vld_d3 )
            ipv4_new_sport[3] <= ipv4_new_sport[3] + dyn_sport_step;
    end

    assign ipv4_sport_of[3] = (!dyn_sport_en) || (dyn_sport_en && (ipv4_new_sport[3] + dyn_sport_step) > dyn_sport_end);

    always @(posedge clk ) begin
        dpv4_chge_vld_d3 <= deal_end_vld[2] && dyn_dport_en && ipv4_flag[2];
        if(start_send_flag)
            ipv4_new_dport[3] <= dyn_dport_start;
        else if(ipv4_change_of[2] && dpv4_chge_vld_d3  && (ipv4_new_dport[3] + dyn_dport_step) > (dyn_dport_end) && ipv4_sport_of[3])
            ipv4_new_dport[3] <= dyn_dport_start;
        else if(ipv4_change_of[2] && dpv4_chge_vld_d3 && ipv4_sport_of[3])
            ipv4_new_dport[3] <= ipv4_new_dport[3] + dyn_dport_step;
    end

    assign ipv4_dport_of[3] = (!dyn_dport_en) || (dyn_dport_en && (ipv4_new_dport[3] + dyn_dport_step) > (dyn_dport_end));
    //ipv6

    always @(posedge clk ) begin
        if(start_send_flag)
            ipv6_new_sip[1] <= ipv6_dyn_sip_start[31:0];
        else if(ipv6_dyn_sip_en && deal_end_vld[1] && eth_type[1] == ETH_IPV6_TYPE && (ipv6_new_sip[1] + ipv6_dyn_sip_step) > (ipv6_dyn_sip_end[31:0]))
            ipv6_new_sip[1] <= ipv6_dyn_sip_start[31:0];
        else if(ipv6_dyn_sip_en && deal_end_vld[1] && eth_type[1] == ETH_IPV6_TYPE)
            ipv6_new_sip[1] <= ipv6_new_sip[1] + ipv6_dyn_sip_step;

        ipv6_new_sip[3:2] <= ipv6_new_sip[2:1];
    end

    always @(posedge clk ) begin
        ipv6_sip_of[2] <= (!ipv6_dyn_sip_en) || (ipv6_dyn_sip_en && (ipv6_new_sip[1] + ipv6_dyn_sip_step) > (ipv6_dyn_sip_end[31:0]));
    end

    always @(posedge clk ) begin
        dipv6_chge_vld_d2 <= deal_end_vld[1] && ipv6_dyn_dip_en && eth_type[1] == ETH_IPV6_TYPE;
        if(start_send_flag)
            ipv6_new_dip[2] <= ipv6_dyn_dip_start[31:0];
        else if(dipv6_chge_vld_d2 && (ipv6_new_dip[2] + ipv6_dyn_dip_step) > (ipv6_dyn_dip_end[31:0]) && ipv6_sip_of[2])
            ipv6_new_dip[2] <= ipv6_dyn_dip_start[31:0];
        else if(dipv6_chge_vld_d2 && ipv6_sip_of[2])
            ipv6_new_dip[2] <= ipv6_new_dip[2] + ipv6_dyn_dip_step;

        ipv6_new_dip[3] <= ipv6_new_dip[2];
    end

    assign ipv6_dip_of[2] = (!ipv6_dyn_dip_en) || (ipv6_dyn_dip_en && (ipv6_new_dip[2] + ipv6_dyn_dip_step) > (ipv6_dyn_dip_end[31:0]));

    always @(posedge clk ) begin
        if(deal_end_vld[2] && ipv6_dip_of[2] && ipv6_sip_of[2])
            ipv6_change_of[2] <= 1'b1;
        else 
            ipv6_change_of[2] <= 1'b0;
    end

    always @(posedge clk ) begin
        spv6_chge_vld_d3 <= deal_end_vld[2] && ipv6_dyn_sport_en && ipv6_flag[2];
        if(start_send_flag)
            ipv6_new_sport[3] <= ipv6_dyn_sport_start;
        else if(ipv6_change_of[2] && spv6_chge_vld_d3 && (ipv6_new_sport[3] + ipv6_dyn_sport_step) > (ipv6_dyn_sport_end))
            ipv6_new_sport[3] <= ipv6_dyn_sport_start;
        else if(ipv6_change_of[2] && spv6_chge_vld_d3)
            ipv6_new_sport[3] <= ipv6_new_sport[3] + ipv6_dyn_sport_step;

        ipv6_new_sport[4] <= ipv6_new_sport[3];
    end

    assign ipv6_sport_of[3] = (!ipv6_dyn_sport_en) || (ipv6_dyn_sport_en && (ipv6_new_sport[3] + ipv6_dyn_sport_step) > (ipv6_dyn_sport_end));

    always @(posedge clk ) begin
        dpv6_chge_vld_d3 <= deal_end_vld[2] && ipv6_dyn_dport_en && ipv6_flag[2];
        if(start_send_flag)
            ipv6_new_dport[3] <= ipv6_dyn_dport_start;
        else if(ipv6_change_of[2] && dpv6_chge_vld_d3 && (ipv6_new_dport[3] + ipv6_dyn_dport_step) > (ipv6_dyn_dport_end) && ipv6_sport_of[3])
            ipv6_new_dport[3] <= ipv6_dyn_dport_start;
        else if(ipv6_change_of[2] && dpv6_chge_vld_d3 && ipv6_sport_of[3])
            ipv6_new_dport[3] <= ipv6_new_dport[3] + ipv6_dyn_dport_step;
        
        ipv6_new_dport[4] <= ipv6_new_dport[3];
    end
    assign ipv6_dport_of[3] = (!ipv6_dyn_dport_en) || (ipv6_dyn_dport_en && (ipv6_new_dport[3] + ipv6_dyn_dport_step) > (ipv6_dyn_dport_end));

    always @(posedge clk ) begin
        ipv4_sip_en[4:3]   <= {ipv4_sip_en[3],dyn_sip_en};
        ipv4_dip_en[4:3]   <= {ipv4_dip_en[3],dyn_dip_en};
        ipv4_sport_en[4:3] <= {ipv4_sport_en[3],dyn_sport_en};
        ipv4_dport_en[4:3] <= {ipv4_dport_en[3],dyn_dport_en};

        ipv6_sip_en[4:3]   <= {ipv6_sip_en[3],ipv6_dyn_sip_en};
        ipv6_dip_en[4:3]   <= {ipv6_dip_en[3],ipv6_dyn_dip_en};
        ipv6_sport_en[4:3] <= {ipv6_sport_en[3],ipv6_dyn_sport_en};
        ipv6_dport_en[4:3] <= {ipv6_dport_en[3],ipv6_dyn_dport_en};
    end

    //报文的 payload len 和 udp len 计算
    always @(posedge clk ) begin
        if(gen_head_vld[1] && eth_type[1] == ETH_IPV4_TYPE)
            ipv4_flag[2]   <= 1'b1;
        else if(gen_head_vld[2])
            ipv4_flag[2] <= 1'b0;
        ipv4_flag[3] <= ipv4_flag[2];
    end

    always @(posedge clk ) begin
        if(gen_head_vld[1] && eth_type[1] == ETH_IPV6_TYPE)
            ipv6_flag[2] <= 1'b1;
        else if(gen_head_vld[1])
            ipv6_flag[2] <= 1'b0;
        ipv6_flag[5:3] <= ipv6_flag[4:2];
    end

    always @(posedge clk ) begin
        if(gen_head_vld[2] && ipv4_flag[2] && vlan2_flag[2])
            ip_len[3] <= pkt_len_cfg_reg[2] - 16'd22;
        else if(gen_head_vld[2] && ipv4_flag[2] && vlan1_flag[2])
            ip_len[3] <= pkt_len_cfg_reg[2] - 16'd18;
        else if(gen_head_vld[2] && ipv4_flag[2])
            ip_len[3] <= pkt_len_cfg_reg[2] - 16'd14;
        else if(gen_head_vld[2] && ipv6_flag[2] && vlan2_flag[2])
            ip_len[3] <= pkt_len_cfg_reg[2] - 16'd62;
        else if(gen_head_vld[2] && ipv6_flag[2] && vlan1_flag[2])
            ip_len[3] <= pkt_len_cfg_reg[2] - 16'd58;
        else if(gen_head_vld[2] && ipv6_flag[2])
            ip_len[3] <= pkt_len_cfg_reg[2] - 16'd54;
    end
    //ipv4报文头 计算ip cksm
    always @(posedge clk ) begin
        case ({vlan1_flag[3],vlan2_flag[3]})
            2'b10:begin 
                ipv4_header[4][(IP_PKT_VERSION-112)+:16]      <= gen_pkt_data[3][(IP_PKT_VERSION+32)+:16];
                ipv4_header[4][(IP_PKT_LENGTH-112)+:16]       <= swap_bytes(ip_len[3]);
                ipv4_header[4][(IP_PKT_IDENT-112)+:48]        <= gen_pkt_data[3][(IP_PKT_IDENT+32)+:48];
                ipv4_header[4][(IP_PKT_HEADER_CKSM-112)+:16]  <= 16'd0;
                ipv4_header[4][(IP_PKT_SRC_IP-112)+:32]       <= dyn_dip_en &   dyn_mode ? swap_4bytes(ipv4_new_dip[3]) : 
                                                                 dyn_sip_en & (!dyn_mode)? swap_4bytes(ipv4_new_sip[3]) : gen_pkt_data[3][(IP_PKT_SRC_IP+32)+:32];

                ipv4_header[4][(IP_PKT_DEST_IP-112)+:32]      <= dyn_sip_en &   dyn_mode ? swap_4bytes(ipv4_new_sip[3]) :
                                                                 dyn_dip_en & (!dyn_mode)? swap_4bytes(ipv4_new_dip[3]) : gen_pkt_data[3][(IP_PKT_DEST_IP+32)+:32];
            end
            2'b01:begin 
                ipv4_header[4][(IP_PKT_VERSION-112)+:16]      <= gen_pkt_data[3][(IP_PKT_VERSION+64)+:16];
                ipv4_header[4][(IP_PKT_LENGTH-112)+:16]       <= swap_bytes(ip_len[3]);
                ipv4_header[4][(IP_PKT_IDENT-112)+:48]        <= gen_pkt_data[3][(IP_PKT_IDENT+64)+:48];
                ipv4_header[4][(IP_PKT_HEADER_CKSM-112)+:16]  <= 16'd0;
                ipv4_header[4][(IP_PKT_SRC_IP-112)+:32]       <= dyn_dip_en &   dyn_mode ? swap_4bytes(ipv4_new_dip[3]) : 
                                                                 dyn_sip_en & (!dyn_mode)? swap_4bytes(ipv4_new_sip[3]) : gen_pkt_data[3][(IP_PKT_SRC_IP+64)+:32];
                ipv4_header[4][(IP_PKT_DEST_IP-112)+:32]      <= dyn_sip_en &   dyn_mode ? swap_4bytes(ipv4_new_sip[3]) : 
                                                                 dyn_dip_en & (!dyn_mode)? swap_4bytes(ipv4_new_dip[3]) : gen_pkt_data[3][(IP_PKT_DEST_IP+64)+:32];
            end
            default:begin 
                ipv4_header[4][(IP_PKT_VERSION-112)+:16]      <= gen_pkt_data[3][IP_PKT_VERSION+:16];
                ipv4_header[4][(IP_PKT_LENGTH-112)+:16]       <= swap_bytes(ip_len[3]);
                ipv4_header[4][(IP_PKT_IDENT-112)+:48]        <= gen_pkt_data[3][IP_PKT_IDENT+:48];
                ipv4_header[4][(IP_PKT_HEADER_CKSM-112)+:16]  <= 16'd0;
                ipv4_header[4][(IP_PKT_SRC_IP-112)+:32]       <= dyn_dip_en &   dyn_mode ? swap_4bytes(ipv4_new_dip[3]) : 
                                                                 dyn_sip_en & (!dyn_mode)? swap_4bytes(ipv4_new_sip[3]) : gen_pkt_data[3][IP_PKT_SRC_IP+:32];
                ipv4_header[4][(IP_PKT_DEST_IP-112)+:32]      <= dyn_sip_en &   dyn_mode ? swap_4bytes(ipv4_new_sip[3]) : 
                                                                 dyn_dip_en & (!dyn_mode)? swap_4bytes(ipv4_new_dip[3]) : gen_pkt_data[3][IP_PKT_DEST_IP+:32];
            end
        endcase
    end

    always @(posedge clk ) begin
        ip_cksm_5d[0] <= swap_bytes(ipv4_header[4][(0*16)+:16]) + swap_bytes(ipv4_header[4][(1*16)+:16]) + swap_bytes(ipv4_header[4][(2*16)+:16]);
        ip_cksm_5d[1] <= swap_bytes(ipv4_header[4][(3*16)+:16]) + swap_bytes(ipv4_header[4][(4*16)+:16]) + swap_bytes(ipv4_header[4][(5*16)+:16]);
        ip_cksm_5d[2] <= swap_bytes(ipv4_header[4][(6*16)+:16]) + swap_bytes(ipv4_header[4][(7*16)+:16]);
        ip_cksm_5d[3] <= swap_bytes(ipv4_header[4][(8*16)+:16]) + swap_bytes(ipv4_header[4][(9*16)+:16]);
        ip_cksm_6d[0] <= ip_cksm_5d[0] + ip_cksm_5d[1];
        ip_cksm_6d[1] <= ip_cksm_5d[2] + ip_cksm_5d[3];
        ip_cksm_7d    <= ip_cksm_6d[0] + ip_cksm_6d[1];
    end

    //修改报文 ip port  len 
    always @(posedge clk ) begin
        m_gen_axis_tvalid   <= gen_pkt_vld[3];
        m_gen_axis_tdata    <= gen_pkt_data[3];
        m_gen_axis_tusef    <= deal_end_vld[3] ? pkt_len_cfg_reg[3][0+:$clog2(DATA_W/8)] : {$clog2(DATA_W/8){1'b0}};
        m_gen_axis_tlast    <= deal_end_vld[3];
        m_gen_axis_len      <= pkt_len_cfg_reg[3];
        m_gen_axis_tkeep    <= deal_end_vld[3] && (|pkt_len_cfg_reg[3][6:0]) ? {128{1'b1}} >> (128-pkt_len_cfg_reg[3][6:0]) : {128{1'b1}};
        if(gen_head_vld[3])begin
            case ({ipv6_flag[3],vlan1_flag[3],vlan2_flag[3]}) 
                3'b010:begin//ipv4 1 vlan 
                    m_gen_axis_tdata[(IP_PKT_LENGTH+32)+:16]      <= swap_bytes(ip_len[3]);
                    m_gen_axis_tdata[(IP_PKT_HEADER_CKSM+32)+:16] <= 16'b0;
                    m_gen_axis_tdata[(IP_PKT_SRC_IP+32)+:32]      <= ipv4_dip_en[3] &   dyn_mode ? swap_4bytes(ipv4_new_dip[3]) :
                                                                     ipv4_sip_en[3] & (!dyn_mode)? swap_4bytes(ipv4_new_sip[3]) : gen_pkt_data[3][(IP_PKT_SRC_IP+32)+:32];
                    m_gen_axis_tdata[(IP_PKT_DEST_IP+32)+:32]     <= ipv4_sip_en[3] &   dyn_mode ? swap_4bytes(ipv4_new_sip[3]) : 
                                                                     ipv4_dip_en[3] & (!dyn_mode)? swap_4bytes(ipv4_new_dip[3]) : gen_pkt_data[3][(IP_PKT_DEST_IP+32)+:32];
                    m_gen_axis_tdata[(UDP_PKT_SPORT+32)+:16]      <= ipv4_dport_en[3] &   dyn_mode ? swap_bytes(ipv4_new_dport[3]) :
                                                                     ipv4_sport_en[3] & (!dyn_mode)? swap_bytes(ipv4_new_sport[3]) : gen_pkt_data[3][(UDP_PKT_SPORT+32)+:16];
                    m_gen_axis_tdata[(UDP_PKT_DPORT+32)+:16]      <= ipv4_sport_en[3] &   dyn_mode ? swap_bytes(ipv4_new_sport[3]) : 
                                                                     ipv4_dport_en[3] & (!dyn_mode)? swap_bytes(ipv4_new_dport[3]) : gen_pkt_data[3][(UDP_PKT_DPORT+32)+:16];
                    m_gen_axis_tdata[(UDP_PKT_LENGTH+32)+:16]     <= swap_bytes(ip_len[3]-20);
                    udp_len[4]                                      <= ip_len[3]-20;
                end  
                3'b001:begin//ipv4 2 vlan 
                    m_gen_axis_tdata[(IP_PKT_LENGTH+64)+:16]      <= swap_bytes(ip_len[3]);
                    m_gen_axis_tdata[(IP_PKT_HEADER_CKSM+64)+:16] <= 16'b0;;
                    m_gen_axis_tdata[(IP_PKT_SRC_IP+64)+:32]      <= ipv4_dip_en[3] &   dyn_mode ? swap_4bytes(ipv4_new_dip[3]) :
                                                                     ipv4_sip_en[3] & (!dyn_mode)? swap_4bytes(ipv4_new_sip[3]) : gen_pkt_data[3][(IP_PKT_SRC_IP+64)+:32];
                    m_gen_axis_tdata[(IP_PKT_DEST_IP+64)+:32]     <= ipv4_sip_en[3] &   dyn_mode ? swap_4bytes(ipv4_new_sip[3]) : 
                                                                     ipv4_dip_en[3] & (!dyn_mode)? swap_4bytes(ipv4_new_dip[3]) : gen_pkt_data[3][(IP_PKT_DEST_IP+64)+:32];
                    m_gen_axis_tdata[(UDP_PKT_SPORT+64)+:16]      <= ipv4_dport_en[3] &   dyn_mode ? swap_bytes(ipv4_new_dport[3]) :
                                                                     ipv4_sport_en[3] & (!dyn_mode)? swap_bytes(ipv4_new_sport[3]) : gen_pkt_data[3][(UDP_PKT_SPORT+64)+:16];
                    m_gen_axis_tdata[(UDP_PKT_DPORT+64)+:16]      <= ipv4_sport_en[3] &   dyn_mode ? swap_bytes(ipv4_new_sport[3]) : 
                                                                     ipv4_dport_en[3] & (!dyn_mode)? swap_bytes(ipv4_new_dport[3]) : gen_pkt_data[3][(UDP_PKT_DPORT+64)+:16];
                    m_gen_axis_tdata[(UDP_PKT_LENGTH+64)+:16]     <= swap_bytes(ip_len[3]-20);
                    udp_len[4]                                      <= ip_len[3]-20;
                end
                3'b110:begin //ipv6 1 vlan 
                    m_gen_axis_tdata[(IPV6_PKT_PAYLOAD_LEN+32)+:16]<= swap_bytes(ip_len[3]);
                    m_gen_axis_tdata[(IPV6_PKT_SRC_IP+32)+:128]   <= ipv6_dip_en[3] &   dyn_mode ? swap_16bytes({ipv6_dyn_dip_start[127:32],ipv6_new_dip[3]}) :
                                                                     ipv6_sip_en[3] & (!dyn_mode)? swap_16bytes({ipv6_dyn_sip_start[127:32],ipv6_new_sip[3]}) : gen_pkt_data[3][(IPV6_PKT_SRC_IP+32)+:128];
                    m_gen_axis_tdata[(IPV6_PKT_DEST_IP+32)+:128]  <= ipv6_sip_en[3] &   dyn_mode ? swap_16bytes({ipv6_dyn_sip_start[127:32],ipv6_new_sip[3]}) : 
                                                                     ipv6_dip_en[3] & (!dyn_mode)? swap_16bytes({ipv6_dyn_dip_start[127:32],ipv6_new_dip[3]}) : gen_pkt_data[3][(IPV6_PKT_DEST_IP+32)+:128];
                    m_gen_axis_tdata[(UDP_V6_PKT_SPORT+32)+:16]   <= ipv6_dport_en[3] &   dyn_mode ? swap_bytes(ipv6_new_dport[3]) :
                                                                     ipv6_sport_en[3] & (!dyn_mode)? swap_bytes(ipv6_new_sport[3]) : gen_pkt_data[3][(UDP_V6_PKT_SPORT+32)+:16];
                    m_gen_axis_tdata[(UDP_V6_PKT_DPORT+32)+:16]   <= ipv6_sport_en[3] &   dyn_mode ? swap_bytes(ipv6_new_sport[3]) :
                                                                     ipv6_dport_en[3] & (!dyn_mode)? swap_bytes(ipv6_new_dport[3]) : gen_pkt_data[3][(UDP_V6_PKT_DPORT+32)+:16];
                    m_gen_axis_tdata[(UDP_V6_PKT_LENGTH+32)+:16]  <= swap_bytes(ip_len[3]);
                    udp_len[4]                                    <= ip_len[3];
                end
                3'b101:begin//ipv6 2 vlan 
                    m_gen_axis_tdata[(IPV6_PKT_PAYLOAD_LEN+64)+:16]<= swap_bytes(ip_len[3]);
                    m_gen_axis_tdata[(UDP_V6_PKT_LENGTH+64)+:16]  <= swap_bytes(ip_len[3]);
		            m_gen_axis_tdata[(IPV6_PKT_SRC_IP+64)+:128]   <= ipv6_dip_en[3] &   dyn_mode ? swap_16bytes({ipv6_dyn_dip_start[127:32],ipv6_new_dip[3]}) :
                                                                     ipv6_sip_en[3] & (!dyn_mode)? swap_16bytes({ipv6_dyn_sip_start[127:32],ipv6_new_sip[3]}) : gen_pkt_data[3][(IPV6_PKT_SRC_IP+64)+:128];
                    m_gen_axis_tdata[(IPV6_PKT_DEST_IP+64)+:128]  <= ipv6_sip_en[3] &   dyn_mode ? swap_16bytes({ipv6_dyn_sip_start[127:32],ipv6_new_sip[3]}) : 
                                                                     ipv6_dip_en[3] & (!dyn_mode)? swap_16bytes({ipv6_dyn_dip_start[127:32],ipv6_new_dip[3]}) : gen_pkt_data[3][(IPV6_PKT_DEST_IP+64)+:128];
                    m_gen_axis_tdata[(UDP_V6_PKT_SPORT+64)+:16]   <= ipv6_dport_en[3] &   dyn_mode ? swap_bytes(ipv6_new_dport[3]) :
                                                                     ipv6_sport_en[3] & (!dyn_mode)? swap_bytes(ipv6_new_sport[3]) : gen_pkt_data[3][(UDP_V6_PKT_SPORT+64)+:16];
                    m_gen_axis_tdata[(UDP_V6_PKT_DPORT+64)+:16]   <= ipv6_sport_en[3] &   dyn_mode ? swap_bytes(ipv6_new_sport[3]) :
                                                                     ipv6_dport_en[3] & (!dyn_mode)? swap_bytes(ipv6_new_dport[3]) : gen_pkt_data[3][(UDP_V6_PKT_DPORT+64)+:16];
                    udp_len[4]                                    <= ip_len[3];
                end
                3'b100:begin//ipv6 0 vlan  
                    m_gen_axis_tdata[(IPV6_PKT_PAYLOAD_LEN)+:16]  <= swap_bytes(ip_len[3]);
                    m_gen_axis_tdata[(IPV6_PKT_SRC_IP)+:128]      <= ipv6_dip_en[3] &   dyn_mode ? swap_16bytes({ipv6_dyn_dip_start[127:32],ipv6_new_dip[3]}) :
                                                                     ipv6_sip_en[3] & (!dyn_mode)? swap_16bytes({ipv6_dyn_sip_start[127:32],ipv6_new_sip[3]}) : gen_pkt_data[3][(IPV6_PKT_SRC_IP)+:128];
                    m_gen_axis_tdata[(IPV6_PKT_DEST_IP)+:128]     <= ipv6_sip_en[3] &   dyn_mode ? swap_16bytes({ipv6_dyn_sip_start[127:32],ipv6_new_sip[3]}) : 
                                                                     ipv6_dip_en[3] & (!dyn_mode)? swap_16bytes({ipv6_dyn_dip_start[127:32],ipv6_new_dip[3]}) : gen_pkt_data[3][(IPV6_PKT_DEST_IP)+:128];
                    m_gen_axis_tdata[(UDP_V6_PKT_SPORT)+:16]      <= ipv6_dport_en[3] &   dyn_mode ? swap_bytes(ipv6_new_dport[3]) :
                                                                     ipv6_sport_en[3] & (!dyn_mode)? swap_bytes(ipv6_new_sport[3]) : gen_pkt_data[3][(UDP_V6_PKT_SPORT)+:16];
                    m_gen_axis_tdata[(UDP_V6_PKT_DPORT)+:16]      <= ipv6_sport_en[3] &   dyn_mode ? swap_bytes(ipv6_new_sport[3]) :
                                                                     ipv6_dport_en[3] & (!dyn_mode)? swap_bytes(ipv6_new_dport[3]) : gen_pkt_data[3][(UDP_V6_PKT_DPORT)+:16];
                    m_gen_axis_tdata[(UDP_V6_PKT_LENGTH)+:16]     <= swap_bytes(ip_len[3]);
                    udp_len[4]                                      <= ip_len[3];
                end
                default:begin//ipv4 0 vlan 和其他
                    m_gen_axis_tdata[(IP_PKT_LENGTH)+:16]         <= swap_bytes(ip_len[3]);
                    m_gen_axis_tdata[(IP_PKT_HEADER_CKSM)+:16]    <= 16'b0;
                    m_gen_axis_tdata[(IP_PKT_SRC_IP)+:32]         <= ipv4_dip_en[3] &   dyn_mode ? swap_4bytes(ipv4_new_dip[3]) :
                                                                     ipv4_sip_en[3] & (!dyn_mode)? swap_4bytes(ipv4_new_sip[3]) : gen_pkt_data[3][(IP_PKT_SRC_IP)+:32];
                    m_gen_axis_tdata[(IP_PKT_DEST_IP)+:32]        <= ipv4_sip_en[3] &   dyn_mode ? swap_4bytes(ipv4_new_sip[3]) : 
                                                                     ipv4_dip_en[3] & (!dyn_mode)? swap_4bytes(ipv4_new_dip[3]) : gen_pkt_data[3][(IP_PKT_DEST_IP)+:32];
                    m_gen_axis_tdata[(UDP_PKT_SPORT)+:16]         <= ipv4_dport_en[3] &   dyn_mode ? swap_bytes(ipv4_new_dport[3]) :
                                                                     ipv4_sport_en[3] & (!dyn_mode)? swap_bytes(ipv4_new_sport[3]) : gen_pkt_data[3][(UDP_PKT_SPORT)+:16];
                    m_gen_axis_tdata[(UDP_PKT_DPORT)+:16]         <= ipv4_sport_en[3] &   dyn_mode ? swap_bytes(ipv4_new_sport[3]) : 
                                                                     ipv4_dport_en[3] & (!dyn_mode)? swap_bytes(ipv4_new_dport[3]) : gen_pkt_data[3][(UDP_PKT_DPORT)+:16];
                    m_gen_axis_tdata[(UDP_PKT_LENGTH)+:16]        <= swap_bytes(ip_len[3]-20);
                    udp_len[4]                                      <= ip_len[3]-20;
                end 
            endcase
        end 
    end
 
    //提取报文的payload 以及 伪ip头，用于计算udp cksm,最后一拍数据不够64字节时，用“00”补齐。
    generate
        for (genvar i=0 ; i<(DATA_W/8) ; i=i+1 ) begin
            assign m_gen_axis_tkeep_512[4][i*8+:8] = {8{m_gen_axis_tkeep[i]}};
        end
    endgenerate

    always @(posedge clk ) begin
        calc_udp_cksm_en[5]     <= m_gen_axis_tvalid;
        calc_udp_cksm_sop[5]    <= gen_head_vld[4];
        calc_udp_cksm_eop[5]    <= deal_end_vld[4];
        calc_udp_cksm_dt[5]     <= m_gen_axis_tdata & m_gen_axis_tkeep_512[4];
        udp_cksm_offset[5]      <= gen_head_vld[4] ? {pkt_len_cfg_reg[4],pkt_stream_id[4],16'd0,1'b0,ipv6_flag[4],vlan1_flag[4],vlan2_flag[4]} : udp_cksm_offset[5];
        udp_cksm_offset[7:6]    <= udp_cksm_offset[6:5];    
        udp_cksm_offset[8]      <= gen_head_vld[7] ? {udp_cksm_offset[7][20+:28],swap_bytes(~(ip_cksm_7d[15:0]+ip_cksm_7d[19:16])),udp_cksm_offset[7][0+:4]} : udp_cksm_offset[8];
        udp_cksm_offset[13:9]   <= udp_cksm_offset[12:8];

        if(gen_head_vld[4])
            case ({ipv6_flag[4],vlan1_flag[4],vlan2_flag[4]})
                3'b001:begin //ipv4 2 vlan 
                    calc_udp_cksm_dt[5][0 +:64] <= {m_gen_axis_tdata[(IP_PKT_SRC_IP+64)+:32],(m_gen_axis_tdata[(IP_PKT_DEST_IP+64)+:32])};
                    calc_udp_cksm_dt[5][64+:32] <= swap_4bytes({udp_len[4],8'b0,8'h11});
                    calc_udp_cksm_dt[5][335:96] <= 240'b0;
                    calc_udp_cksm_dt[5][384+:16]<= 16'b0;//udp cksm 清零
                end 
                3'b010:begin //ipv4 1 vlan 
                    calc_udp_cksm_dt[5][0 +:64] <= {m_gen_axis_tdata[(IP_PKT_SRC_IP+32)+:32],(m_gen_axis_tdata[(IP_PKT_DEST_IP+32)+:32])};
                    calc_udp_cksm_dt[5][64+:32] <= swap_4bytes({udp_len[4],8'b0,8'h11});
                    calc_udp_cksm_dt[5][303:96] <= 208'b0;
                    calc_udp_cksm_dt[5][352+:16]<= 16'b0;//udp cksm 清零
                end
                3'b101:begin //ipv6 2 vlan 
                    calc_udp_cksm_dt[5][0 +:256]<= {m_gen_axis_tdata[(IPV6_PKT_SRC_IP+64)+:128],(m_gen_axis_tdata[(IPV6_PKT_DEST_IP+64)+:128])};
                    calc_udp_cksm_dt[5][256+:32]<= swap_4bytes({udp_len[4],8'h0,8'h11});
                    calc_udp_cksm_dt[5][495:288]<= 208'b0;
                    calc_udp_cksm_dt[5][544+:16]<= 16'b0;//udp cksm 清零
                end 
                3'b110:begin //ipv6 1 vlan 
                    calc_udp_cksm_dt[5][0 +:256]<= {m_gen_axis_tdata[(IPV6_PKT_SRC_IP+32)+:128],(m_gen_axis_tdata[(IPV6_PKT_DEST_IP+32)+:128])};
                    calc_udp_cksm_dt[5][256+:32]<= swap_4bytes({udp_len[4],8'h00,8'h11});
                    calc_udp_cksm_dt[5][463:288]<= 176'b0;
                    calc_udp_cksm_dt[5][512+:16]<= 16'b0;//udp cksm 清零
                end
                3'b100:begin //ipv6 0 vlan 
                    calc_udp_cksm_dt[5][0 +:256]<= {m_gen_axis_tdata[(IPV6_PKT_SRC_IP)+:128],(m_gen_axis_tdata[(IPV6_PKT_DEST_IP)+:128])};
                    calc_udp_cksm_dt[5][256+:32]<= swap_4bytes({udp_len[4],8'b0,8'h11});
                    calc_udp_cksm_dt[5][431:288]<= 144'b0;
                    calc_udp_cksm_dt[5][480+:16]<= 16'b0;
                end
                default:begin //ipv4 0 vlan 
                    calc_udp_cksm_dt[5][0 +:64] <= {m_gen_axis_tdata[(IP_PKT_SRC_IP)+:32],(m_gen_axis_tdata[(IP_PKT_DEST_IP)+:32])};
                    calc_udp_cksm_dt[5][64+:32] <= swap_4bytes({udp_len[4],8'b0,8'h11});
                    calc_udp_cksm_dt[5][271:96] <= 176'b0;
                    calc_udp_cksm_dt[5][320+:16]<= 16'b0;//udp cksm 清零
                end 
            endcase
    end
    //输出info信息,1 pkt_tem_rdptr当做pkt_stream_id，向后传递；2 udp cksm offset 用来确定要修改的cksm的位置；
    // 3 pkt_len计算从fifo中的读取长度，以及向后传递； 4 计算出的udp cksm。
    always @(posedge clk ) begin
        gen_info_fifo_wen   <= udp_cksm_en[13];
        gen_info_fifo_wdata <= {udp_cksm_offset[13],swap_bytes(udp_cksm[13])};
    end
/*
    generate
        if(PORT_ID == 0)begin
            ila_ch
            pkt_gen_ch_ila_u
            (
                .clk        (clk),
                .probe0     (pkt_tem_len),
                .probe1     (pkt_tem_rdptr),
                .probe2     (m_gen_axis_tvalid),
                .probe3     (m_gen_axis_tlast),
                .probe4     (m_gen_axis_len),
                .probe5     (pkt_tem_data),
                .probe6     (m_gen_axis_tdata),
                .probe7     (m_gen_axis_tready),
                .probe8     (gen_info_fifo_wen),
                .probe9     (gen_info_fifo_wdata),
                .probe10     (gen_info_fifo_afull),
                .probe11     (pkt_lw_wptr),
                .probe12     (start_send_flag),
                .probe13     (payload_wait_afull),
                .probe14     (rd_new_pkt),
                .probe15     (rd_fir_head),
                .probe16     (rd_sec_head),
                .probe17     (payload_add),
                .probe19     (cur_pkt_end),
                .probe21     (pkt_length_cfg),
                .probe22     (pkt_weight_cfg)
            );
        end
    endgenerate
*/
    udp_cksm_calc
    udp_cksm_u
    (
        .clk        (clk                                ),
        .rst_n      (rst_n                              ),
        .pkt_en     (calc_udp_cksm_en[5]                ),
        .pkt_sop    (calc_udp_cksm_sop[5]               ),
        .pkt_eop    (calc_udp_cksm_eop[5]               ),
        .pkt_data   (swap_64bytes(calc_udp_cksm_dt[5])  ),
        .cksm_en    (udp_cksm_en[13]                    ),
        .cksm       (udp_cksm[13]                       )
    );

    function [15:0] swap_bytes;
        input [15:0] data_in;
        begin : swap
            swap_bytes = {data_in[7:0],data_in[15:8]};
        end
    endfunction

    function [31:0] swap_4bytes;
        input [31:0] data_in;
        begin : swap
            swap_4bytes = {data_in[7:0],data_in[15:8],data_in[23:16],data_in[31:24]};
        end
    endfunction

    function [7:0] swap_4bytes_3;
        input [31:0] data_in;
        begin : swap
            swap_4bytes_3 = data_in[7:0];
        end
    endfunction

    function [7:0] swap_4bytes_2;
        input [31:0] data_in;
        begin : swap
            swap_4bytes_2 = data_in[15:8];
        end
    endfunction

    function [7:0] swap_4bytes_1;
        input [31:0] data_in;
        begin : swap
            swap_4bytes_1 = data_in[23:16];
        end
    endfunction

    function [7:0] swap_4bytes_0;
        input [31:0] data_in;
        begin : swap
            swap_4bytes_0 = data_in[31:24];
        end
    endfunction

    function [6*8-1:0] swap_6bytes;
        input [6*8-1:0] data_in;
        integer i;
        begin : swap
            for (i=0;i<6;i=i+1)begin 
                swap_6bytes[i*8 +:8] = data_in[(5-i)*8 +: 8] ;
            end  
        end
    endfunction


    function [16*8-1:0] swap_16bytes;
        input [16*8-1:0] data_in;
        integer i;
        begin : swap
            for (i=0;i<16;i=i+1)begin 
                swap_16bytes[i*8 +:8] = data_in[(15-i)*8 +: 8] ;
            end  
        end
    endfunction

    function [64*8-1:0] swap_64bytes;
        input [64*8-1:0] data_in;
        integer i;
        begin : swap
            for (i=0;i<64;i=i+1)begin 
                swap_64bytes[i*8 +:8] = data_in[(63-i)*8 +: 8] ;
            end  
        end
    endfunction

    function [15:0] compute_ip_chk;
        input   [159:0] data_in;
        reg     [159:0] cur_data;
        integer i;
        reg     carry ;
        reg     [16:0] add_1st[0:4];
        reg     [17:0] add_2nd[0:2];
        reg     [18:0] add_3rd[0:1];
        reg     [19:0] dout;
        begin : calc_block
            cur_data = data_in;
            for(i=0;i<5;i=i+1) begin
                add_1st[i] = swap_bytes(cur_data[i*2*16 +:16]) + swap_bytes(cur_data[((i*2+1)*16)+:16]);
            end
            for(i=0;i<2;i=i+1) begin
                add_2nd[i] = add_1st[i*2] + add_1st[i*2+1];
            end
            add_2nd[2]      = {1'b0,add_1st[4]};
            add_3rd[0]      = add_2nd[0] + add_2nd[1];
            add_3rd[1]      = {1'b0,add_2nd[2]};
            dout            = add_3rd[0] + add_3rd[1];
            dout            = dout[15:0] + dout[19:16];
            dout            = dout[15:0] + dout[19:16];
            compute_ip_chk  = ~(dout[15:0]);
        end
    endfunction

    function [31:0] cnt_x_step;
        input [15:0] step;
        input [15:0] cnt;
        input [15:0] cnt_max;
        begin : stream_jump_temp_func
            if(cnt < cnt_max) cnt_x_step = step * cnt;
            else              cnt_x_step = 0;
        end
    endfunction

    module udp_cksm_calc
    (
        input   wire                clk,
        input   wire                rst_n,
        input   wire                pkt_en,
        input   wire                pkt_sop,
        input   wire                pkt_eop,
        input   wire    [1023:0]    pkt_data,
        output  reg                 cksm_en,
        output  reg     [15:0]      cksm
    );

        reg     [16:0]      calc_1st[31:0];
        reg     [17:0]      calc_2st[15:0];
        reg     [18:0]      calc_3st[7:0];
        reg     [19:0]      calc_4st[3:0];
        reg     [20:0]      calc_5st[1:0];
        reg     [21:0]      calc_6st;
        reg     [16:0]      calc_7st;

        reg                 sop_ff[7:1];
        reg                 eop_ff[7:1];

        always @(posedge clk ) begin
            sop_ff[7:1] <= {sop_ff[6:1],pkt_sop&pkt_en};
            eop_ff[7:1] <= {eop_ff[6:1],pkt_eop&pkt_en};
        end
        
        generate
            for (genvar i=0 ; i<32 ; i=i+1 ) begin
                always @(posedge clk ) begin
                    calc_1st[i] <= pkt_data[32*i +:16] + pkt_data[(32*i+16) +:16];
                end
            end
            for (genvar i=0 ; i<16 ; i=i+1 ) begin
                always @(posedge clk ) begin
                    calc_2st[i] <= calc_1st[2*i] + calc_1st[2*i+1];
                end
            end
            for (genvar i=0 ; i<8 ; i=i+1 ) begin
                always @(posedge clk ) begin
                    calc_3st[i] <= calc_2st[2*i] + calc_2st[2*i+1];
                end
            end
            for (genvar i=0 ; i<4 ; i=i+1 ) begin
                always @(posedge clk ) begin
                    calc_4st[i] <= calc_3st[2*i] + calc_3st[2*i+1];
                end
            end
            for (genvar i=0 ; i<2 ; i=i+1) begin
                always @(posedge clk ) begin
                    calc_5st[i] <= calc_4st[2*i] + calc_4st[2*i+1];
                end
            end
            always @(posedge clk ) begin
                calc_6st <= calc_5st[0] + calc_5st[1];
            end

            always @(posedge clk ) begin
                if(sop_ff[6])
                    calc_7st <= calc_6st[21:16] + calc_6st[15:0];
                else  
                    calc_7st <= calc_7st[15:0] + calc_7st[16] + calc_6st[21:16] + calc_6st[15:0];
            end
            always @(posedge clk ) begin
                cksm    <= ~(calc_7st[15:0] + calc_7st[16]);
                cksm_en <= eop_ff[7];
            end
        endgenerate
    endmodule

endmodule
`resetall

