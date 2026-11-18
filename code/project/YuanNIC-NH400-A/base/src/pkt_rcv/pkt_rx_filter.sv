//
//
// Copyright 2020 Xilinx, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// *************************************************************************
`timescale 1ns/1ps
module pkt_rx_filter #(
    parameter       CMAC_ID     = 0,
    parameter       DATA_W      = 1024
)   
(
    input                                   rx_pkt_en,
    input                                   rx_pkt_mix_en,
    input                                   rx_pkt_filter_en,
    input                                   rx_pkt_filter_type,
    input                                   timestamp_delay_type,
    input           [31:0]                  timestamp_delay_value,
    input           [31:0]                  policy_vld,
    input           [319:0]                 info_filter_item[7:0],
    input                                   p_axis_tvalid,
    input           [DATA_W-1:0]            p_axis_tdata,
    input                                   p_axis_tlast,
    input           [$clog2(DATA_W/8)-1:0]  p_axis_tkeep,
    input           [3-1:0]                 p_axis_tuser,
    output                                  p_axis_ready,
    output  reg                             drop_flag,
    output  reg                             d_axis_tvalid,
    output  reg     [DATA_W-1:00]           d_axis_tdata,
    output  reg                             d_axis_tlast,
    output  reg     [$clog2(DATA_W/8)-1:0]  d_axis_tkeep,
    output  reg     [3-1:0]                 d_axis_tuser,
    input                                   d_axis_ready,
    input           [63:0]                  time_stamp, 
    output                                  timestamp_valid,
    output          [63:0]                  timestamp_delay,
    output          [15:0]                  stream_id,
    output          [15:0]                  stream_value,
    output                                  rocev2_timestamp_vld,
    output          [63:0]                  rocev2_timestamp_value,
    output reg                              arp_icmp_flag,
    input                                   aclk,
    input                                   aresetn,
    output          [2:0]                   filter_state
);

 

    localparam IDLE                         = 2'd0;
    localparam HOLD                         = 2'd1; 
    localparam RX_FILTER_PKT                = 2'd2; 
    localparam RX_FILTER_PKT_FOLLOW         = 2'd3; 
    localparam IPV4_DADDR_OFFSET            = 30; 
    localparam IPV4_SADDR_OFFSET            = 34; 
    localparam IPV4_ADDR_LEN                = 4; 
    localparam IPV6_DADDR_OFFSET            = 10; 
    localparam IPV6_SADDR_OFFSET            = 26; 
    localparam IPV6_ADDR_LEN                = 16; 
    localparam IPV4_DPORT_OFFSET            = 26; 
    localparam IPV4_SPORT_OFFSET            = 28; 
    localparam IPV4_PORT_LEN                = 2; 
    localparam IPV6_DPORT_OFFSET            = 6; 
    localparam IPV6_SPORT_OFFSET            = 8; 
    localparam IPV6_PORT_LEN                = 2; 
    localparam ETH_TYPE_ICMP                = 8'h01;
    localparam ETH_TYPE_ICMPV6              = 8'h3a;
    localparam ETH_TYPE_ARP                 = 16'h0806;
    localparam ETH_TYPE_IP4                 = 16'h0800;
    localparam ETH_TYPE_IP6                 = 16'h86DD;
    localparam ETH_TYPE_VLAN0               = 16'h8100;
    localparam ETH_TYPE_VLAN1               = 16'h88A8;
    localparam ETH_TYPE_VLAN2               = 16'h9100;
    localparam ETH_TYPE_VLAN3               = 16'h9200;
    localparam  IPV4_UDPLEN_OFFSET          = 24; 
    localparam  IPV4_UDPOPC_OFFSET          = 21; 
    localparam  IPV6_UDPLEN_OFFSET          = 4; 
    localparam  IPV6_UDPOPC_OFFSET          = 1; 
    localparam ROCEV2_TYPE                  = 16'h12B7;
    localparam ETH_TYPE_UDP                 = 8'h11;
    localparam UDP_LEN                      = 16'h0064;
    localparam ROCEV2_OPCODE_MAX            = 8'h00;
    localparam ROCEV2_OPCODE_MIN            = 8'h10;

    reg     [1:0]                           c_state;
    reg     [1:0]                           n_state;
    reg                                     ip_addr_ok;
    reg                                     port_ok;
    reg                                     calculate_rel;
    reg                                     rx_pkt_drop;  
    reg                                     mix_flag;
    reg     [2:0]                           filter_sel;
    reg                                     start;
    reg     [63:0]                          time_stamp_reg;
    reg     [511:0]                         comparer_info;
    wire    [7:0]                           section_result;
    reg                                     arp_icmp_en;
    reg                                     arp_icmp_en_vld;
    wire    [7:0]                           icmp_type;  
    wire    [7:0]                           icmp_typev6;
    wire    [15:0]                          eth_type;   
    wire    [512-1:0]                       p_axis_tdata_parser_d0; 
    reg                                     vlan1_flag;
    reg                                     vlan2_flag;
    reg     [$clog2(DATA_W/8)-1:0]          p_axis_tkeep_d[2:0];    
    reg     [3-1:0]                         p_axis_tuser_d[2:0];
    reg                                     p_axis_tvalid_d[2:0];   
    reg                                     p_axis_tlast_d[2:0];    
    reg     [DATA_W-1:0]                    p_axis_tdata_d[2:0]; 
    wire    [31:0]                          dip[7:0];
    wire    [31:0]                          sip[7:0];
    wire    [15:0]                          dport[7:0];
    wire    [15:0]                          sport[7:0];
    wire    [7:0]                           mask_dip[7:0];
    wire    [7:0]                           mask_sip[7:0];
    wire    [3:0]                           mask_field[7:0];
    wire                                    mode[7:0];
    wire    [15:0]                          vlan1_type;
    wire    [15:0]                          vlan2_type;
    reg                                     rocev2_st;
    reg                                     rocev2_flag;
    reg     [15:0]                          rocev2_dp;
    reg     [15:0]                          rocev2_udp_len;
    reg     [7:0]                           rocev2_udp_opcode;
    
    assign   filter_state = c_state;
    always @(posedge aclk) begin
        if (~aresetn)
            c_state  <= IDLE;
        else
            c_state  <= n_state;
    end
    always @(*) begin
        case (c_state)
            IDLE:
    	        if (rx_pkt_en)
                    n_state    = HOLD;
                else 
                    n_state    = IDLE;
            HOLD:  
                n_state  = RX_FILTER_PKT;
            RX_FILTER_PKT:
    	        if(p_axis_tvalid_d[0] & (!p_axis_tlast_d[0]))    
    	            n_state  = RX_FILTER_PKT_FOLLOW;
                else if(!rx_pkt_en)
    	            n_state = IDLE;
                else 
                    n_state  = RX_FILTER_PKT;
            RX_FILTER_PKT_FOLLOW:
    	        if(p_axis_tvalid_d[0] && p_axis_tlast_d[0])
                    n_state  = RX_FILTER_PKT;
                else 
                    n_state  = RX_FILTER_PKT_FOLLOW;

            default: n_state = IDLE;
        endcase
    end
    assign vlan1_type = p_axis_tdata[415:400];
    assign vlan2_type = p_axis_tdata[383:368];

    always @(posedge aclk ) begin
        if(~aresetn)begin
            vlan1_flag <= 1'b0;
            vlan2_flag <= 1'b0;
        end
        else if(p_axis_tvalid && (vlan1_type == ETH_TYPE_VLAN0 || vlan1_type == ETH_TYPE_VLAN1 || vlan1_type == ETH_TYPE_VLAN2 || vlan1_type == ETH_TYPE_VLAN3)  
                              && (vlan2_type != ETH_TYPE_VLAN0 && vlan2_type != ETH_TYPE_VLAN1 && vlan2_type != ETH_TYPE_VLAN2 && vlan2_type != ETH_TYPE_VLAN3))begin
            vlan1_flag <= 1'b1;
            vlan2_flag <= 1'b0;
        end 
        else if(p_axis_tvalid && (vlan1_type == ETH_TYPE_VLAN0 || vlan1_type == ETH_TYPE_VLAN1 || vlan1_type == ETH_TYPE_VLAN2 || vlan1_type == ETH_TYPE_VLAN3)  
                              && (vlan2_type == ETH_TYPE_VLAN0 || vlan2_type == ETH_TYPE_VLAN1 || vlan2_type == ETH_TYPE_VLAN2 || vlan2_type == ETH_TYPE_VLAN3))begin
            vlan1_flag <= 1'b0;
            vlan2_flag <= 1'b1;
        end 
        else begin
            vlan1_flag <= 1'b0;
            vlan2_flag <= 1'b0;
        end
    end

    assign p_axis_tdata_parser_d0 = vlan2_flag ? {p_axis_tdata_d[0][511+512:416+512],p_axis_tdata_d[0][351+512:000+512],p_axis_tdata_d[0][511:448]} :
                                    vlan1_flag ? {p_axis_tdata_d[0][511+512:416+512],p_axis_tdata_d[0][383+512:000+512],p_axis_tdata_d[0][511:480]} :
                                                  p_axis_tdata_d[0][511+512:512];

    assign icmp_type   = p_axis_tdata_parser_d0[327:320];
    assign icmp_typev6 = p_axis_tdata_parser_d0[351:344];
    assign eth_type    = p_axis_tdata_parser_d0[415:400];

    always @(posedge aclk) begin
        if (~aresetn)
            arp_icmp_en <= 1'b0;
        else if(c_state == RX_FILTER_PKT & p_axis_tvalid_d[0] & eth_type == ETH_TYPE_ARP)
            arp_icmp_en <= 1'b1;
        else if(c_state == RX_FILTER_PKT & p_axis_tvalid_d[0] & eth_type == ETH_TYPE_IP4 && icmp_type == ETH_TYPE_ICMP)
            arp_icmp_en <= 1'b1;
        else if(c_state == RX_FILTER_PKT & p_axis_tvalid_d[0] & eth_type == ETH_TYPE_IP6 && icmp_typev6 == ETH_TYPE_ICMPV6)
            arp_icmp_en <= 1'b1;
        else
            arp_icmp_en <= 1'b0;

        arp_icmp_flag   <= arp_icmp_en_vld;
        arp_icmp_en_vld <= arp_icmp_en;
    end 

    always @(posedge aclk) begin
        if(c_state == RX_FILTER_PKT & p_axis_tvalid_d[0] & eth_type == ETH_TYPE_IP4)begin 
    	    comparer_info[511:480] <= p_axis_tdata_parser_d0[(IPV4_DADDR_OFFSET*8) +: (IPV4_ADDR_LEN*8)] ;
    	    comparer_info[383:352] <= p_axis_tdata_parser_d0[(IPV4_SADDR_OFFSET*8) +: (IPV4_ADDR_LEN*8)];
    	    comparer_info[79:64]   <= p_axis_tdata_parser_d0[(IPV4_DPORT_OFFSET*8) +: (IPV4_PORT_LEN*8)];
    	    comparer_info[63:48]   <= p_axis_tdata_parser_d0[(IPV4_SPORT_OFFSET*8) +: (IPV4_PORT_LEN*8)];
        end else if(c_state == RX_FILTER_PKT & p_axis_tvalid_d[0] & eth_type == ETH_TYPE_IP6)begin 
    	    comparer_info[511:384] <= p_axis_tdata_parser_d0[(IPV6_DADDR_OFFSET*8) +: (IPV6_ADDR_LEN*8)];
    	    comparer_info[383:256] <= p_axis_tdata_parser_d0[(IPV6_SADDR_OFFSET*8) +: (IPV6_ADDR_LEN*8)];
    	    comparer_info[79:64]   <= p_axis_tdata_parser_d0[(IPV6_DPORT_OFFSET*8) +: (IPV6_PORT_LEN*8)];
    	    comparer_info[63:48]   <= p_axis_tdata_parser_d0[(IPV6_SPORT_OFFSET*8) +: (IPV6_PORT_LEN*8)];         
        end else if(c_state == RX_FILTER_PKT & p_axis_tvalid_d[0])begin 
            comparer_info <= 512'd0;
        end  
    end

    always @(posedge aclk) begin
        if(c_state == IDLE)
        	drop_flag <= 1'b1 ;
        else if(arp_icmp_en_vld | (!policy_vld))
            drop_flag <= 1'b0;
        else
            drop_flag <= |section_result;
    end
 
    always @(posedge aclk) begin
        if((c_state == RX_FILTER_PKT || c_state == RX_FILTER_PKT_FOLLOW) & p_axis_tvalid_d[0] && p_axis_tlast_d[0])
          	start <= 1'b1;
        else
          	start <= 1'b0;
    end    

    always @(posedge aclk) begin
        if(timestamp_delay_type == 0 & c_state == RX_FILTER_PKT & p_axis_tvalid_d[0])
            time_stamp_reg <= time_stamp-timestamp_delay_value;
        else if(timestamp_delay_type == 1 & c_state == RX_FILTER_PKT_FOLLOW & p_axis_tvalid_d[0] && p_axis_tlast_d[0])
            time_stamp_reg <= time_stamp-timestamp_delay_value; 
        else if(timestamp_delay_type == 1 & c_state == RX_FILTER_PKT)
            time_stamp_reg <= time_stamp-timestamp_delay_value;
    end 

    always @(posedge aclk) begin
        p_axis_tvalid_d[2:0] <= {p_axis_tvalid_d[1:0],p_axis_tvalid}; 
        p_axis_tdata_d[2:0]  <= {p_axis_tdata_d[1:0],p_axis_tdata};
        p_axis_tlast_d[2:0]  <= {p_axis_tlast_d[1:0],p_axis_tlast};
        p_axis_tkeep_d[2:0]  <= {p_axis_tkeep_d[1:0],p_axis_tkeep};
        p_axis_tuser_d[2:0]  <= {p_axis_tuser_d[1:0],p_axis_tuser}; 
        d_axis_tvalid        <= p_axis_tvalid_d[2]; 
        d_axis_tdata         <= p_axis_tdata_d[2];
        d_axis_tlast         <= p_axis_tlast_d[2];
        d_axis_tkeep         <= p_axis_tkeep_d[2];
        d_axis_tuser         <= p_axis_tuser_d[2]; 
    end

    generate
        for (genvar i=0 ; i<8 ; i=i+1) begin
            assign sip[i]       = info_filter_item[i][319:288];
            assign dip[i]       = info_filter_item[i][191:160];
            assign sport[i]     = info_filter_item[i][63:48];
            assign dport[i]     = info_filter_item[i][47:32];
            assign mask_dip[i]  = 8'h03;
            assign mask_sip[i]  = 8'h03;
            assign mask_field[i]= info_filter_item[i][3:0];
            assign mode[i]      = info_filter_item[i][31];

            match_section section_u(
                .info               (comparer_info      ),
                .result_en          (section_result[i]  ),
	            .policy_vld         (policy_vld[i]      ),
                .dip                (dip[i]             ),
                .sip                (sip[i]             ),
                .dport              (dport[i]           ),
                .sport              (sport[i]           ),
                .mask_dip           (mask_dip[i]        ),
                .mask_sip           (mask_sip[i]        ),
                .mask_field         (mask_field[i]      ),
                .mode               (mode[i]            ),
                .clk                (aclk               ),   //
                .resetn             (aresetn            )    //valid: low
            );
        end
    endgenerate

    always @(posedge aclk) begin
        if(c_state == RX_FILTER_PKT & p_axis_tvalid_d[0] & eth_type == ETH_TYPE_IP4 && icmp_type == ETH_TYPE_UDP) begin
    	    rocev2_dp           <= p_axis_tdata_d[0][(IPV4_DPORT_OFFSET*8) +: (IPV4_PORT_LEN*8)];
    	    rocev2_udp_len      <= p_axis_tdata_d[0][(IPV4_UDPLEN_OFFSET*8) +: 16];
    	    rocev2_udp_opcode   <= p_axis_tdata_d[0][(IPV4_UDPOPC_OFFSET*8) +: 8];
        end else if(c_state == RX_FILTER_PKT & p_axis_tvalid_d[0] & eth_type == ETH_TYPE_IP6 && icmp_typev6 == ETH_TYPE_UDP)begin
            rocev2_dp           <= p_axis_tdata_d[0][(IPV6_DPORT_OFFSET*8) +: (IPV6_PORT_LEN*8)];
    	    rocev2_udp_len      <= p_axis_tdata_d[0][(IPV6_UDPLEN_OFFSET*8) +: 16];
    	    rocev2_udp_opcode   <= p_axis_tdata_d[0][(IPV6_UDPOPC_OFFSET*8) +: 8];
        end
        else if(c_state == RX_FILTER_PKT & p_axis_tvalid_d[0])
            rocev2_dp           <= 16'd0;
    end

    always @(posedge aclk) begin
        if (~aresetn)
            rocev2_st <= 1'b0;
        else if(c_state == RX_FILTER_PKT & p_axis_tvalid_d[0] & eth_type == ETH_TYPE_IP4 && icmp_type == ETH_TYPE_UDP)
            rocev2_st          <= 1'b1;
        else if(c_state == RX_FILTER_PKT & p_axis_tvalid_d[0] & eth_type == ETH_TYPE_IP6 && icmp_typev6 == ETH_TYPE_UDP)
            rocev2_st         <= 1'b1;
        else if(c_state == RX_FILTER_PKT & p_axis_tvalid_d[0])
            rocev2_st    <= 1'b1;
        else 
            rocev2_st <= 1'b0;
    end

    always @(posedge aclk) begin
        if(rocev2_st & rocev2_dp == ROCEV2_TYPE & rocev2_udp_len >= UDP_LEN & rocev2_udp_opcode >= ROCEV2_OPCODE_MAX && rocev2_udp_opcode <= ROCEV2_OPCODE_MIN)
            rocev2_flag <= 1'b1;
        else
            rocev2_flag <= 1'b0; 
    end

    timestamp_calc timestamp_calc_inst(
        .start                  (start),
        .rocev2_flag            (rocev2_flag),
        .loc_time_stamp         (time_stamp_reg),
        .timestamp_delay_value  (timestamp_delay_value),
        .p_axis_tdata           (p_axis_tdata_d[1]),
        .p_axis_tdata_pre       (p_axis_tdata_d[2]),
        .p_axis_tkeep           (p_axis_tkeep_d[1]), 
        .timestamp_valid        (timestamp_valid),
        .timestamp_delay        (timestamp_delay),
        .stream_id              (stream_id),
        .stream_value           (stream_value),
        .rocev2_timestamp_vld   (rocev2_timestamp_vld),
        .rocev2_timestamp_value (rocev2_timestamp_value),
        .aclk                   (aclk),
        .aresetn                (aresetn)
    );
  
endmodule
