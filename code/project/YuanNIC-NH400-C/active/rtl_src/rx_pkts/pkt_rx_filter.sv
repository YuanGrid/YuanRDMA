`timescale 1ns/1ps
module pkt_rx_filter #(
    parameter       CMAC_ID     = 0,
    parameter       DATA_W      = 1024,
    parameter       FILTER_NUM  = 4
)   
(
    input                                   rx_pkt_en,
    input                                   rx_pkt_en_config,
    input                                   rx_pkt_mix_en,
    input                                   rx_pkt_filter_en,
    input                                   rx_pkt_filter_type,
    input                                   timestamp_delay_type,
    input           [31:0]                  timestamp_delay_value,
    input           [             8  :0]    filter_en,             
    input           [    FILTER_NUM-1:0]    process_mode,             
    input           [    FILTER_NUM-1:0]    field_relation,  
    input           [    FILTER_NUM-1:0]    dmac_en           ,
    input           [    FILTER_NUM-1:0]    dmac_mode         ,
    input           [ 48*FILTER_NUM-1:0]    dmac_mask         ,
    input           [ 48*FILTER_NUM-1:0]    dmac_value        ,
    input           [    FILTER_NUM-1:0]    smac_en           ,
    input           [    FILTER_NUM-1:0]    smac_mode         ,
    input           [ 48*FILTER_NUM-1:0]    smac_mask         ,
    input           [ 48*FILTER_NUM-1:0]    smac_value        ,
    input           [    FILTER_NUM-1:0]    vlanid_en         ,
    input           [    FILTER_NUM-1:0]    vlanid_mode       ,
    input           [ 12*FILTER_NUM-1:0]    vlanid_mask       ,
    input           [ 12*FILTER_NUM-1:0]    vlanid_value      ,
    input           [    FILTER_NUM-1:0]    protocol_en       ,        
    input           [    FILTER_NUM-1:0]    protocol_mode     ,        
    input           [  8*FILTER_NUM-1:0]    protocol_mask     ,        
    input           [  8*FILTER_NUM-1:0]    protocol_value    ,        
    input           [    FILTER_NUM-1:0]    sipv4_en          ,    
    input           [    FILTER_NUM-1:0]    sipv4_mode        ,    
    input           [ 32*FILTER_NUM-1:0]    sipv4_mask        ,    
    input           [ 32*FILTER_NUM-1:0]    sipv4_value       ,    
    input           [    FILTER_NUM-1:0]    dipv4_en          ,             
    input           [    FILTER_NUM-1:0]    dipv4_mode        ,             
    input           [ 32*FILTER_NUM-1:0]    dipv4_mask        ,             
    input           [ 32*FILTER_NUM-1:0]    dipv4_value       ,             
    input           [    FILTER_NUM-1:0]    sipv6_en          ,             
    input           [    FILTER_NUM-1:0]    sipv6_mode        ,             
    input           [128*FILTER_NUM-1:0]    sipv6_mask        ,             
    input           [128*FILTER_NUM-1:0]    sipv6_value       ,             
    input           [    FILTER_NUM-1:0]    dipv6_en          ,             
    input           [    FILTER_NUM-1:0]    dipv6_mode        ,             
    input           [128*FILTER_NUM-1:0]    dipv6_mask        ,             
    input           [128*FILTER_NUM-1:0]    dipv6_value       ,             
    input           [    FILTER_NUM-1:0]    sport_en          ,             
    input           [    FILTER_NUM-1:0]    sport_mode        ,             
    input           [ 16*FILTER_NUM-1:0]    sport_mask        ,             
    input           [ 16*FILTER_NUM-1:0]    sport_value       ,             
    input           [    FILTER_NUM-1:0]    dport_en          ,             
    input           [    FILTER_NUM-1:0]    dport_mode        ,             
    input           [ 16*FILTER_NUM-1:0]    dport_mask        ,             
    input           [ 16*FILTER_NUM-1:0]    dport_value       ,             
    input           [    FILTER_NUM-1:0]    pkt_length_en     ,             
    input           [    FILTER_NUM-1:0]    pkt_length_mode   ,             
    input           [ 16*FILTER_NUM-1:0]    pkt_length_mask   ,             
    input           [ 16*FILTER_NUM-1:0]    pkt_length_value  ,             
    output reg      [ 64*FILTER_NUM-1:0]    filter_match_pkts ,
    output reg      [ 64*FILTER_NUM-1:0]    filter_match_bytes,
    input                                   p_axis_tvalid,
    input           [DATA_W-1:0]            p_axis_tdata,
    input                                   p_axis_tlast,
    input           [$clog2(DATA_W/8)-1:0]  p_axis_tkeep,
    input           [3-1:0]                 p_axis_tuser,
    input           [64-1:0]                p_axis_ttime,
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

 

localparam IDLE                    = 2'd0;
localparam HOLD                    = 2'd1; 
localparam RX_FILTER_PKT           = 2'd2; 
localparam RX_FILTER_PKT_FOLLOW    = 2'd3; 


localparam DMAC_OFFSET = 58; 
localparam SMAC_OFFSET = 52; 
localparam MAC_LEN    = 6; 
localparam VLANID1_OFFSET = 48; 
localparam VLANID2_OFFSET = 44; 
localparam VLANID_LEN_BIT = 12; 
localparam IPV4_PROTOCOL_OFFSET = 40; 
localparam IPV6_PROTOCOL_OFFSET = 43; 
localparam PROTOCOL_LEN    = 1; 
localparam IPV4_DADDR_OFFSET = 30; 
localparam IPV4_SADDR_OFFSET = 34; 
localparam IPV4_ADDR_LEN    = 4; 
localparam IP_PKT_LENGTH = 46;
localparam IP_PKT_LENGTH_LEN = 2;
localparam IPV6_PKT_PAYLOAD_LENGTH = 44;
localparam IPV6_PKT_PAYLOAD_LENGTH_LEN = 2;
localparam IPV6_DADDR_OFFSET = 10; 
localparam IPV6_SADDR_OFFSET = 26; 
localparam IPV6_ADDR_LEN    = 16; 
localparam IPV4_DPORT_OFFSET = 26; 
localparam IPV4_SPORT_OFFSET = 28; 
localparam IPV4_PORT_LEN    = 2; 
localparam IPV6_DPORT_OFFSET = 6; 
localparam IPV6_SPORT_OFFSET = 8; 
localparam IPV6_PORT_LEN    = 2; 

localparam ETH_TYPE_ICMP    = 8'h01;
localparam ETH_TYPE_ICMPV6  = 8'h3a;
localparam ETH_TYPE_ARP   = 16'h0806;
localparam ETH_TYPE_IP4   = 16'h0800;
localparam ETH_TYPE_IP6   = 16'h86DD;
localparam ETH_TYPE_VLAN0 = 16'h8100;
localparam ETH_TYPE_VLAN1 = 16'h88A8;
localparam ETH_TYPE_VLAN2 = 16'h9100;
localparam ETH_TYPE_VLAN3 = 16'h9200;


localparam  IPV4_UDPLEN_OFFSET = 24; 
localparam  IPV4_UDPOPC_OFFSET = 21; 
localparam  IPV6_UDPLEN_OFFSET = 4; 
localparam  IPV6_UDPOPC_OFFSET = 1; 

localparam ROCEV2_TYPE    = 16'h12B7;
localparam ETH_TYPE_UDP   = 8'h11;
localparam UDP_LEN        = 16'h0064;
localparam ROCEV2_OPCODE_MAX = 8'h00;
localparam ROCEV2_OPCODE_MIN = 8'h10;

    reg     [1:0]                           c_state;
    reg     [1:0]                           n_state;
    reg                                     calculate_rel;
    reg                                     rx_pkt_drop;  
    reg                                     mix_flag;
    reg                                     start;
    reg     [63:0]                          time_stamp_reg;
    reg [47:0] dmac;
    reg [47:0] smac; 
    reg [11:0] vlanid1;
    reg [11:0] vlanid2;
    reg [ 7:0] protocol;
    reg [31:0] sipv4;
    reg [31:0] dipv4;
    reg [127:0] sipv6;
    reg [127:0] dipv6;
    reg [15:0] sport;
    reg [15:0] dport;
    reg [15:0] pkt_length;
    reg [15:0] pkt_length_d1;
    reg  dmac_val;
    reg  smac_val; 
    reg  vlanid1_val;
    reg  vlanid2_val;
    reg  protocol_val;
    reg  sipv4_val;
    reg  dipv4_val;
    reg  sipv6_val;
    reg  dipv6_val;
    reg  sport_val;
    reg  dport_val;
    reg  pkt_length_val;
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
    reg     [63:0]                          p_axis_ttime_d[2:0];   
    reg                                     p_axis_tlast_d[2:0];    
    reg     [DATA_W-1:0]                    p_axis_tdata_d[2:0]; 
    wire    [15:0]                          vlan1_type;
    wire    [15:0]                          vlan2_type;
    wire    [FILTER_NUM-1:0]     match_result;             
    wire    [FILTER_NUM-1:0]     process_result;             
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
  if (~aresetn) begin
    dmac_val <= 1'b0;
    smac_val <= 1'b0; 
    vlanid1_val <= 1'b0;
    vlanid2_val <= 1'b0;
    protocol_val <= 1'b0;
    sipv4_val <= 1'b0;
    dipv4_val <= 1'b0;
    sipv6_val <= 1'b0;
    dipv6_val <= 1'b0;
    sport_val <= 1'b0;
    dport_val <= 1'b0;
    pkt_length_val <= 1'b0;
    dmac <= 48'b0;
    smac <= 48'b0; 
    vlanid1 <= 12'b0;
    vlanid2 <= 12'b0;
    protocol <= 8'b0;
    sipv4 <= 32'b0;
    dipv4 <= 32'b0;
    sipv6 <= 128'b0;
    dipv6 <= 128'b0;
    sport <= 16'b0;
    dport <= 16'b0;
    pkt_length <= 16'b0;
    pkt_length_d1 <= 16'b0;
  end
  else begin
    pkt_length_d1 <= pkt_length;
    if(c_state == RX_FILTER_PKT) begin
      if(p_axis_tvalid_d[0])begin
        dmac_val <= 1'b1;
        smac_val <= 1'b1;
        dmac <= p_axis_tdata_parser_d0[(DMAC_OFFSET*8) +: (MAC_LEN*8)];
        smac <= p_axis_tdata_parser_d0[(SMAC_OFFSET*8) +: (MAC_LEN*8)]; 
        if(vlan1_flag == 1'b1)begin		  
          vlanid1_val <= 1'b1;
          vlanid2_val <= 1'b0;
          vlanid1 <= p_axis_tdata_d[0][(VLANID1_OFFSET*8 + 512) +: VLANID_LEN_BIT];
          vlanid2 <= 12'b0;
        end  
        else if(vlan2_flag == 1'b1) begin
          vlanid1_val <= 1'b1;
          vlanid2_val <= 1'b1;
          vlanid1 <= p_axis_tdata_d[0][(VLANID1_OFFSET*8 + 512) +: VLANID_LEN_BIT];
          vlanid2 <= p_axis_tdata_d[0][(VLANID2_OFFSET*8 + 512) +: VLANID_LEN_BIT];
        end  
        else begin
          vlanid1_val <= 1'b0;
          vlanid2_val <= 1'b0;
        end  
        if(eth_type == ETH_TYPE_IP4)begin		  
          protocol_val <= 1'b1;
          sipv4_val <= 1'b1;
          dipv4_val <= 1'b1;
          sipv6_val <= 1'b0;
          dipv6_val <= 1'b0;
          sport_val <= 1'b1;
          dport_val <= 1'b1;
          protocol <= p_axis_tdata_parser_d0[(IPV4_PROTOCOL_OFFSET*8) +: (PROTOCOL_LEN*8)];	          
          dipv4    <= p_axis_tdata_parser_d0[(IPV4_DADDR_OFFSET*8) +: (IPV4_ADDR_LEN*8)];
          sipv4    <= p_axis_tdata_parser_d0[(IPV4_SADDR_OFFSET*8) +: (IPV4_ADDR_LEN*8)];
          dport    <= p_axis_tdata_parser_d0[(IPV4_DPORT_OFFSET*8) +: (IPV4_PORT_LEN*8)];
          sport    <= p_axis_tdata_parser_d0[(IPV4_SPORT_OFFSET*8) +: (IPV4_PORT_LEN*8)];
          pkt_length_val <= 1'b1;
          if(vlan1_flag == 1'b1)begin		  
            pkt_length <= 16'd14 + 16'd4 + p_axis_tdata_parser_d0[(IP_PKT_LENGTH*8) +: (IP_PKT_LENGTH_LEN*8)];
          end  
          else if(vlan2_flag == 1'b1) begin
            pkt_length <= 16'd14 + 16'd8 + p_axis_tdata_parser_d0[(IP_PKT_LENGTH*8) +: (IP_PKT_LENGTH_LEN*8)];
          end  
          else begin
            pkt_length <= 16'd14 + p_axis_tdata_parser_d0[(IP_PKT_LENGTH*8) +: (IP_PKT_LENGTH_LEN*8)];
          end  
        end  
        else if(eth_type == ETH_TYPE_IP6) begin
          protocol_val <= 1'b1;
          sipv4_val <= 1'b0;
          dipv4_val <= 1'b0;
          sipv6_val <= 1'b1;
          dipv6_val <= 1'b1;
          sport_val <= 1'b1;
          dport_val <= 1'b1;
          protocol <= p_axis_tdata_parser_d0[(IPV6_PROTOCOL_OFFSET*8) +: (PROTOCOL_LEN*8)];	          
          dipv6    <= p_axis_tdata_parser_d0[(IPV6_DADDR_OFFSET*8) +: (IPV6_ADDR_LEN*8)];
          sipv6    <= p_axis_tdata_parser_d0[(IPV6_SADDR_OFFSET*8) +: (IPV6_ADDR_LEN*8)];
          dport    <= p_axis_tdata_parser_d0[(IPV6_DPORT_OFFSET*8) +: (IPV6_PORT_LEN*8)];
          sport    <= p_axis_tdata_parser_d0[(IPV6_SPORT_OFFSET*8) +: (IPV6_PORT_LEN*8)];         
          pkt_length_val <= 1'b1;
          if(vlan1_flag == 1'b1)begin		  
            pkt_length <= 16'd14 + 16'd4 + 16'd40 + p_axis_tdata_parser_d0[(IPV6_PKT_PAYLOAD_LENGTH*8) +: (IPV6_PKT_PAYLOAD_LENGTH_LEN*8)];
          end  
          else if(vlan2_flag == 1'b1) begin
            pkt_length <= 16'd14 + 16'd8 + 16'd40 + p_axis_tdata_parser_d0[(IPV6_PKT_PAYLOAD_LENGTH*8) +: (IPV6_PKT_PAYLOAD_LENGTH_LEN*8)];
          end  
          else begin
            pkt_length <= 16'd14 + 16'd40 + p_axis_tdata_parser_d0[(IPV6_PKT_PAYLOAD_LENGTH*8) +: (IPV6_PKT_PAYLOAD_LENGTH_LEN*8)];
          end  
        end  
        else begin
          protocol_val <= 1'b0;
          sipv4_val <= 1'b0;
          dipv4_val <= 1'b0;
          sipv6_val <= 1'b0;
          dipv6_val <= 1'b0;
          sport_val <= 1'b0;
          dport_val <= 1'b0;
          pkt_length_val <= 1'b0;
        end   
      end
    end
  end  
end


genvar i;
generate
  for(i=0;i<FILTER_NUM;i=i+1) begin : filter_inst
    match_section u_match_section(
    .clk              (aclk                            ),
    .resetn           (aresetn                         ),
                
    .dmac_val         (dmac_val                        ),
    .dmac             (dmac                            ),
    .dmac_en          (dmac_en[i]                      ),
    .dmac_mode        (dmac_mode[i]                    ),
    .dmac_mask        (dmac_mask[48*i +: 48]           ),
    .dmac_value       (dmac_value[48*i +: 48]          ),
    
    .smac_val         (smac_val                        ),
    .smac             (smac                            ),
    .smac_en          (smac_en[i]                      ),
    .smac_mode        (smac_mode[i]                    ),
    .smac_mask        (smac_mask[48*i +: 48]         ),
    .smac_value       (smac_value[48*i +: 48]        ),
    
    .vlanid1_val      (vlanid1_val                     ),
    .vlanid1          (vlanid1                         ),
    .vlanid2_val      (vlanid2_val                     ),
    .vlanid2          (vlanid2                         ),
    .vlanid_en        (vlanid_en[i]                    ),
    .vlanid_mode      (vlanid_mode[i]                  ),
    .vlanid_mask      (vlanid_mask[12*i +: 12]       ),
    .vlanid_value     (vlanid_value[12*i +: 12]      ),
    
    .protocol_val     (protocol_val                    ),
    .protocol         (protocol                        ), 
    .protocol_en      (protocol_en[i]                  ),        
    .protocol_mode    (protocol_mode[i]                ),        
    .protocol_mask    (protocol_mask[8*i +: 8]        ),        
    .protocol_value   (protocol_value[8*i +: 8]       ),        
    
    .sipv4_val        (sipv4_val                       ), 
    .sipv4            (sipv4                           ),      
    .sipv4_en         (sipv4_en[i]                     ),    
    .sipv4_mode       (sipv4_mode[i]                   ),    
    .sipv4_mask       (sipv4_mask[32*i +: 32]        ),    
    .sipv4_value      (sipv4_value[32*i +: 32]       ),    
    
    .dipv4_val        (dipv4_val                       ),          
    .dipv4            (dipv4                           ),      
    .dipv4_en         (dipv4_en[i]                     ),             
    .dipv4_mode       (dipv4_mode[i]                   ),             
    .dipv4_mask       (dipv4_mask[32*i +: 32]        ),             
    .dipv4_value      (dipv4_value[32*i +: 32]       ),             
    
    .sipv6_val        (sipv6_val                       ),          
    .sipv6            (sipv6                           ),      
    .sipv6_en         (sipv6_en[i]                     ),             
    .sipv6_mode       (sipv6_mode[i]                   ),             
    .sipv6_mask       (sipv6_mask[128*i +: 128]     ),             
    .sipv6_value      (sipv6_value[128*i +: 128]    ),             
    
    .dipv6_val        (dipv6_val                       ),          
    .dipv6            (dipv6                           ),      
    .dipv6_en         (dipv6_en[i]                     ),             
    .dipv6_mode       (dipv6_mode[i]                   ),             
    .dipv6_mask       (dipv6_mask[128*i +: 128]     ),             
    .dipv6_value      (dipv6_value[128*i +: 128]    ),             
    
    .sport_val        (sport_val                       ),          
    .sport            (sport                           ),      
    .sport_en         (sport_en[i]                     ),             
    .sport_mode       (sport_mode[i]                   ),             
    .sport_mask       (sport_mask[16*i +: 16]        ),             
    .sport_value      (sport_value[16*i +: 16]       ),             
    
    .dport_val        (dport_val                       ),          
    .dport            (dport                           ),      
    .dport_en         (dport_en[i]                     ),             
    .dport_mode       (dport_mode[i]                   ),             
    .dport_mask       (dport_mask[16*i +: 16]        ),             
    .dport_value      (dport_value[16*i +: 16]       ),             
    
    .pkt_length_val   (pkt_length_val                  ),          
    .pkt_length       (pkt_length                      ),      
    .pkt_length_en    (pkt_length_en[i]                ),             
    .pkt_length_mode  (pkt_length_mode[i]              ),             
    .pkt_length_mask  (pkt_length_mask[16*i +: 16]   ),             
    .pkt_length_value (pkt_length_value[16*i +: 16]  ),             
    
    .filter_en        (filter_en[i]                    ),             
    .process_mode     (process_mode[i]                 ),              
    .field_relation   (field_relation[i]               ),              
    .match_result     (match_result[i]                 ),              
    .process_result   (process_result[i]               )             
    );

    always @(posedge aclk) begin
      if (~aresetn) begin 
        filter_match_pkts[64*i +: 64] <= 64'b0 ;
      end
      else begin
        if(rx_pkt_en_config && p_axis_tvalid_d[2] && p_axis_tlast_d[2] && filter_en[i])
          filter_match_pkts[64*i +: 64] <= filter_match_pkts[64*i +: 64] + match_result[i] ;
      end      
    end

    always @(posedge aclk) begin
      if (~aresetn) begin 
        filter_match_bytes[64*i +: 64] <= 64'b0 ;
      end
      else begin
        if(rx_pkt_en_config && p_axis_tvalid_d[2] && p_axis_tlast_d[2] && filter_en[i] && match_result[i])
          filter_match_bytes[64*i +: 64] <= filter_match_bytes[64*i +: 64] + pkt_length_d1 ;
      end      
    end
  end
endgenerate

    always @(posedge aclk) begin
        if(c_state == IDLE) begin
            drop_flag <= 1'b1 ;
        end
        else begin
            if(arp_icmp_en_vld)begin
                drop_flag <= 1'b0;
            end  
            else begin
                if(filter_en[8] == 1'b1) begin
                    if(filter_en[FILTER_NUM-1:0] == {FILTER_NUM{1'b0}})
                        drop_flag <= 1'b1;
                    else
                        drop_flag <= | process_result;
                end
                else begin
                    if(filter_en[FILTER_NUM-1:0] == {FILTER_NUM{1'b0}})
                        drop_flag <= 1'b0;
                    else
                        drop_flag <= | process_result;
                end  
            end
        end      
    end
 
    always @(posedge aclk) begin
        if((c_state == RX_FILTER_PKT || c_state == RX_FILTER_PKT_FOLLOW) & p_axis_tvalid_d[0] && p_axis_tlast_d[0])
          	start <= 1'b1;
        else
          	start <= 1'b0;
    end    

    always @(posedge aclk) begin
        if((c_state == RX_FILTER_PKT || c_state == RX_FILTER_PKT_FOLLOW) &  & p_axis_tvalid_d[0] && p_axis_tlast_d[0])
            time_stamp_reg <= p_axis_ttime_d[0]-timestamp_delay_value; 
    end 

    always @(posedge aclk) begin
        p_axis_tvalid_d[2:0] <= {p_axis_tvalid_d[1:0],p_axis_tvalid}; 
        p_axis_tdata_d[2:0]  <= {p_axis_tdata_d[1:0],p_axis_tdata};
        p_axis_tlast_d[2:0]  <= {p_axis_tlast_d[1:0],p_axis_tlast};
        p_axis_tkeep_d[2:0]  <= {p_axis_tkeep_d[1:0],p_axis_tkeep};
        p_axis_tuser_d[2:0]  <= {p_axis_tuser_d[1:0],p_axis_tuser}; 
        p_axis_ttime_d[2:0]  <= {p_axis_ttime_d[1:0],p_axis_ttime};
        d_axis_tvalid        <= p_axis_tvalid_d[2]; 
        d_axis_tdata         <= p_axis_tdata_d[2];
        d_axis_tlast         <= p_axis_tlast_d[2];
        d_axis_tkeep         <= p_axis_tkeep_d[2];
        d_axis_tuser         <= p_axis_tuser_d[2]; 
    end

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
