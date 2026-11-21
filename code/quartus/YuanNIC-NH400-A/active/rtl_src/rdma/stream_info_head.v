`resetall
`default_nettype none
`timescale 1ns / 1ps
module stream_info_head #(parameter DATA_WIDTH = 1024,
                          parameter KEEP_WIDTH = 128)
    (
    input  wire                   axis_aclk,
    input  wire                   rst_n,
 
    input  wire                   s_axis_tvalid,
    input  wire [DATA_WIDTH-1:0]  s_axis_tdata,
    input  wire                   s_axis_tlast,
    input  wire [KEEP_WIDTH-1:0]  s_axis_tkeep,
    input  wire [11-1:0]          s_axis_tchannel,
    output wire                   s_axis_tready,

    output wire                   m_axis_tvalid,
    output wire [DATA_WIDTH-1:0]  m_axis_tdata,
    output wire                   m_axis_tlast,
    output wire [KEEP_WIDTH-1:0]  m_axis_tkeep,
    output wire [11-1:0]          m_axis_tchannel,
    output wire                   m_axis_tuser_sop,
    output wire                   m_axis_tuser_ipv6,
    output wire [13:0]            m_axis_tuser_len,
    output wire                   m_axis_tuser_insert,
    input  wire                   m_axis_tready

);
    localparam          MAC_TYPE_OFFSET = 12;
    localparam          IP_HEAD_OFFSET  = 14;
    localparam          IP_TYPE_OFFSET  = 14;
    localparam          IPV4_PROTOCOL_OFFSET   = IP_HEAD_OFFSET + 9;
    localparam          IPV6_PROTOCOL_OFFSET   = IP_HEAD_OFFSET + 6;
    localparam          IPV4_LENGTH_OFFSET = IP_HEAD_OFFSET + 2;
    localparam          IPV6_LENGTH_OFFSET = IP_HEAD_OFFSET + 4;
    localparam          UDP_V4_BASE = IP_HEAD_OFFSET + 20;
    localparam          UDP_V6_BASE = IP_HEAD_OFFSET + 40;
    localparam          UDP_DPORT_OFFSET = 2;
    localparam          UDP_LENGTH_OFFSET = 4;
    localparam          BTH_V4_BASE = UDP_V4_BASE + 8;
    localparam          BTH_V6_BASE = UDP_V6_BASE + 8;

    localparam          ROCEV2_UDP_PORT = 16'd4791;
    localparam          ETH_VLAN_TYPE0   = 16'h0081;
    localparam          ETH_VLAN_TYPE1   = 16'hA888;
    localparam          ETH_VLAN_TYPE2   = 16'h0091;
    localparam          ETH_VLAN_TYPE3   = 16'h0092;
    
    
    (*mark_debug="true"*)reg                 stream_sop    = 1'b1;
    reg                 d0_stream_sop = 1'b0;
    reg                 d1_stream_sop = 1'b0;

    reg [DATA_WIDTH-1:0] d1_tdata  = 0 ;
    reg [KEEP_WIDTH-1:0] d1_tkeep  = 0 ;
    reg [11-1:0]         d1_tchan  = 0 ;
    reg                  d1_tvalid = 0 ;
    reg                  d1_tlast = 0 ;
    reg [13:0]           d1_tuser_len = 0 ;
    reg                  d1_tuser_insert = 0 ;
    reg                  d1_tuser_ipv6 = 0 ;

    reg [DATA_WIDTH-1:0] d0_tdata  = 0 ;
    reg [KEEP_WIDTH-1:0] d0_tkeep  = 0 ;
    reg [11-1:0]         d0_tchan  = 0 ;
    reg                  d0_tvalid = 0 ;
    reg                  d0_tlast = 0  ;

    wire [15:0]          vlan1_type;
    wire [15:0]          vlan2_type;
    reg                  vlan1_flag;
    reg                  vlan2_flag;
    wire [511:0]         d0_data_parser;

    always @(posedge axis_aclk ) begin
        if(s_axis_tready)begin
            d0_tdata  <= s_axis_tdata  ;
            d0_tkeep  <= s_axis_tkeep  ;
            d0_tchan  <= s_axis_tchannel  ;
            d0_tvalid <= s_axis_tvalid ;
            d0_tlast  <= s_axis_tlast  ;
        end     
    end

    assign vlan1_type = s_axis_tdata[MAC_TYPE_OFFSET*8 + 15: MAC_TYPE_OFFSET*8];
    assign vlan2_type = s_axis_tdata[MAC_TYPE_OFFSET*8 + 47: MAC_TYPE_OFFSET*8 + 32];

    always @(posedge axis_aclk ) begin
        if(!rst_n)begin
            vlan1_flag <= 1'b0;
            vlan2_flag <= 1'b0;
        end
        else if(s_axis_tvalid && stream_sop && (vlan1_type == ETH_VLAN_TYPE0 || vlan1_type == ETH_VLAN_TYPE1 || vlan1_type == ETH_VLAN_TYPE2 || vlan1_type == ETH_VLAN_TYPE3) 
                                            && (vlan2_type != ETH_VLAN_TYPE0 && vlan2_type != ETH_VLAN_TYPE1 && vlan2_type != ETH_VLAN_TYPE2 && vlan2_type != ETH_VLAN_TYPE3))begin 
            vlan1_flag <= 1'b1;
            vlan2_flag <= 1'b0;
        end else if(s_axis_tvalid && stream_sop && (vlan1_type == ETH_VLAN_TYPE0 || vlan1_type == ETH_VLAN_TYPE1 || vlan1_type == ETH_VLAN_TYPE2 || vlan1_type == ETH_VLAN_TYPE3) 
                                                && (vlan2_type == ETH_VLAN_TYPE0 || vlan2_type == ETH_VLAN_TYPE1 || vlan2_type == ETH_VLAN_TYPE2 || vlan2_type == ETH_VLAN_TYPE3))begin
            vlan1_flag <= 1'b0;
            vlan2_flag <= 1'b1;
        end else if(s_axis_tvalid && stream_sop)begin
            vlan1_flag <= 1'b0;
            vlan2_flag <= 1'b0;
        end
    end

    assign d0_data_parser = vlan2_flag ? {s_axis_tdata[63:0],d0_tdata[511:160],d0_tdata[95:0]}:
                            vlan1_flag ? {s_axis_tdata[31:0],d0_tdata[511:128],d0_tdata[95:0]}:
                                          d0_tdata[511:0];
    always@(posedge axis_aclk ) begin
        if(!rst_n)
            stream_sop <= 1'b1;
        else if (s_axis_tvalid & s_axis_tlast & s_axis_tready) begin
            stream_sop <= 1'b1;
        end else if (s_axis_tvalid && s_axis_tready) begin
            stream_sop <= 1'b0;
        end
        if(m_axis_tready) begin
            d0_stream_sop <= stream_sop;
            d1_stream_sop <= d0_stream_sop;
        end
    end

    always@(posedge axis_aclk)
    begin
        if(m_axis_tready) begin
            d1_tdata <= d0_tdata;
        end
    end

    always@(posedge axis_aclk)
    begin
        if(m_axis_tready) begin 
            d1_tkeep <= d0_tkeep;
            d1_tchan <= d0_tchan;
        end
    end

    always@(posedge axis_aclk)
    begin
        if(m_axis_tready) begin
            d1_tvalid <= d0_tvalid;
        end
    end

    always@(posedge axis_aclk)
    begin
        if(m_axis_tready) begin
            d1_tlast <= d0_tlast;
        end
    end

    (*mark_debug="true"*) wire [3:0] ip_type       = d0_data_parser[IP_TYPE_OFFSET*8 + 7 :IP_TYPE_OFFSET*8+4];
    (*mark_debug="true"*) wire [7:0] ipv4_protocol = d0_data_parser[IPV4_PROTOCOL_OFFSET*8 + 7 : IPV4_PROTOCOL_OFFSET*8];
    (*mark_debug="true"*) wire [7:0] ipv6_protocol = d0_data_parser[IPV6_PROTOCOL_OFFSET*8 + 7 : IPV6_PROTOCOL_OFFSET*8];
    (*mark_debug="true"*) wire [15:0] udp_v4_length= {d0_data_parser[(UDP_V4_BASE + UDP_LENGTH_OFFSET)*8 +7 : (UDP_V4_BASE + UDP_LENGTH_OFFSET)*8],d0_data_parser[(UDP_V4_BASE + UDP_LENGTH_OFFSET)*8 +15 : (UDP_V4_BASE + UDP_LENGTH_OFFSET)*8+8]};
    (*mark_debug="true"*) wire [15:0] udp_v6_length= {d0_data_parser[(UDP_V6_BASE + UDP_LENGTH_OFFSET)*8 +7 : (UDP_V6_BASE + UDP_LENGTH_OFFSET)*8],d0_data_parser[(UDP_V6_BASE + UDP_LENGTH_OFFSET)*8 +15 : (UDP_V6_BASE + UDP_LENGTH_OFFSET)*8+8]};
    (*mark_debug="true"*) wire [15:0] udp_v4_dport = {d0_data_parser[(UDP_V4_BASE + UDP_DPORT_OFFSET)*8 +7 : (UDP_V4_BASE + UDP_DPORT_OFFSET)*8],d0_data_parser[(UDP_V4_BASE + UDP_DPORT_OFFSET)*8 +15 : (UDP_V4_BASE + UDP_DPORT_OFFSET)*8+8]};
    (*mark_debug="true"*) wire [15:0] udp_v6_dport = {d0_data_parser[(UDP_V6_BASE + UDP_DPORT_OFFSET)*8 +7 : (UDP_V6_BASE + UDP_DPORT_OFFSET)*8],d0_data_parser[(UDP_V6_BASE + UDP_DPORT_OFFSET)*8 +15 : (UDP_V6_BASE + UDP_DPORT_OFFSET)*8+8]};
    (*mark_debug="true"*) wire [7:0]  v4_opcode    = d0_data_parser[BTH_V4_BASE*8 + 7 : BTH_V4_BASE*8];
    (*mark_debug="true"*) wire [7:0]  v6_opcode    = d0_data_parser[BTH_V6_BASE*8 + 7 : BTH_V6_BASE*8];
    (*mark_debug="true"*) wire [15:0] mac_type     = d0_data_parser[MAC_TYPE_OFFSET*8 + 15: MAC_TYPE_OFFSET*8];

    always@(posedge axis_aclk)
    begin
        if(m_axis_tready) begin
            if(d0_stream_sop == 1'b1 &&  mac_type == 16'h0008) begin
                d1_tuser_len <= {d0_data_parser[IPV4_LENGTH_OFFSET*8 + 7 : IPV4_LENGTH_OFFSET*8],d0_data_parser[IPV4_LENGTH_OFFSET*8 + 15:IPV4_LENGTH_OFFSET*8+8] } + 14;
                d1_tuser_ipv6 <= 1'b0;
            end else if(d0_stream_sop == 1'b1 &&  mac_type == 16'hDD86) begin
                    d1_tuser_len <= {d0_data_parser[IPV6_LENGTH_OFFSET*8 + 7 : IPV6_LENGTH_OFFSET*8],d0_data_parser[IPV6_LENGTH_OFFSET*8 + 15:IPV6_LENGTH_OFFSET*8+8] } + 14 +40;
                    d1_tuser_ipv6 <= 1'b1;
            end else if(d0_stream_sop == 1'b1) begin
                    d1_tuser_len <= 14'h0000;
            end
        end
    end

    always@(posedge axis_aclk)
    begin
        if(m_axis_tready) begin
            if(d0_stream_sop == 1'b1 && mac_type == 16'h0008 && ipv4_protocol == 8'h11 && udp_v4_length > 16'd100 && udp_v4_dport == ROCEV2_UDP_PORT && v4_opcode <= 8'h10) begin
                    d1_tuser_insert <= 1'b1;
            end else if(d0_stream_sop == 1'b1 && mac_type == 16'hdd86 && ipv6_protocol == 8'h11 && udp_v6_length > 16'd100 && udp_v6_dport == ROCEV2_UDP_PORT && v6_opcode <= 8'h10) begin
                    d1_tuser_insert <= 1'b1;
            end else if(d0_stream_sop == 1'b1) begin
                    d1_tuser_insert <= 1'b0;
            end
        end
    end

    assign m_axis_tdata = d1_tdata;
    assign m_axis_tkeep = d1_tkeep;
    assign m_axis_tchannel = d1_tchan;
    assign m_axis_tlast = d1_tlast;
    assign m_axis_tvalid = d1_tvalid;
    assign m_axis_tuser_sop = d1_stream_sop;
    assign m_axis_tuser_ipv6 = d1_tuser_ipv6;
    assign m_axis_tuser_len  = d1_tuser_len;
    assign m_axis_tuser_insert = d1_tuser_insert;
    assign s_axis_tready = m_axis_tready;

endmodule
`resetall
