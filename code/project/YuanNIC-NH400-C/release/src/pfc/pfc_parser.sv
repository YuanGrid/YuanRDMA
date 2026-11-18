// *************************************************************************
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
module pfc_parser #(
    parameter                               DATA_W      = 1024,
    parameter                               KEEP_W      = $clog2(DATA_W/8)
)(    
    input                                   clk,
    input                                   rst_n,
    input                                   s_axis_rx_tvalid,
    input   reg     [DATA_W-1:0]            s_axis_rx_tdata,
    input           [KEEP_W-1:0]            s_axis_rx_tkeep,
    input                                   s_axis_rx_tlast,
    output                                  s_axis_rx_ready,

    output  reg                             m_axis_rx_tvalid,
    output  reg     [DATA_W-1:0]            m_axis_rx_tdata,
    output  reg     [KEEP_W-1:0]            m_axis_rx_tkeep,
    output  reg                             m_axis_rx_tlast,
    output  reg     [2:0]                   m_axis_rx_Priority,
    input                                   m_axis_rx_tready
);

    localparam ETH_DMAC_OFFSET              = 0;                             //0
    localparam ETH_SMAC_OFFSET              = ETH_DMAC_OFFSET +48;           //48
    localparam ETH_TYPE_OFFSET              = ETH_SMAC_OFFSET +48;           //96
    
    localparam IP_PKT_START_POS             = 14<<3;                         //112
    localparam IP_PKT_VERSION               = IP_PKT_START_POS;              //112
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

    localparam ETH_VLAN1_OFFSET             = 96;
    localparam ETH_VLAN2_OFFSET             = ETH_VLAN1_OFFSET + 32;
    localparam ETH_VLAN_OFFSET              = ETH_VLAN2_OFFSET + 32;
    localparam ETH_VLAN_TYPE0               = 16'h0081;
    localparam ETH_VLAN_TYPE1               = 16'hA888;
    localparam ETH_VLAN_TYPE2               = 16'h0091;
    localparam ETH_VLAN_TYPE3               = 16'h0092;
    localparam ETH_IPV4_TYPE                = 16'h0008;
    localparam ETH_IPV6_TYPE                = 16'hDD86;

    reg                                     s_axis_rx_sop;
    wire    [15:0]                          eth_type;
    wire    [31:0]                          vlan_type1;
    wire    [31:0]                          vlan_type2;
    reg     [15:0]                          pkt_dport;
    reg     [DATA_W-1:0]                    axis_parser_data_1d;
    reg     [31:0]                          vlan_type1_1d;
    reg     [31:0]                          vlan_type2_1d;
    reg                                     ipv4_flag_1d;
    reg                                     ipv6_flag_1d;
    reg                                     vlan_flag1_1d;
    reg                                     vlan_flag2_1d;
    reg                                     axis_rx_tvalid_1d;
    reg     [DATA_W-1:0]                    axis_rx_tdata_1d;
    reg     [KEEP_W-1:0]                    axis_rx_tkeep_1d;
    reg                                     axis_rx_tlast_1d;
    reg                                     axis_rx_sop_1d;

    assign s_axis_rx_ready = m_axis_rx_tready;

    always @(posedge clk ) begin
        if(!rst_n)
            s_axis_rx_sop <= 1'b1;
        else if(s_axis_rx_tvalid & s_axis_rx_tlast & s_axis_rx_ready)
            s_axis_rx_sop <= 1'b1;
        else if(s_axis_rx_tvalid & s_axis_rx_ready)
            s_axis_rx_sop <= 1'b0;
    end

    assign vlan_type1 = s_axis_rx_tdata[ETH_VLAN1_OFFSET+:32];
    assign vlan_type2 = s_axis_rx_tdata[ETH_VLAN2_OFFSET+:32];
    assign eth_type   = s_axis_rx_tdata[ETH_VLAN_OFFSET +:16];

    always @(posedge clk ) begin
        if(!rst_n)
            vlan_flag1_1d <= 1'b0;
        else if((s_axis_rx_tvalid & s_axis_rx_ready & s_axis_rx_sop) & 
                (vlan_type1[15:0]==ETH_VLAN_TYPE0 | vlan_type1[15:0]==ETH_VLAN_TYPE1 | vlan_type1[15:0]==ETH_VLAN_TYPE2 | vlan_type1[15:0]==ETH_VLAN_TYPE3) & 
                (vlan_type2[15:0]!=ETH_VLAN_TYPE0 & vlan_type2[15:0]!=ETH_VLAN_TYPE1 & vlan_type2[15:0]!=ETH_VLAN_TYPE2 & vlan_type2[15:0]!=ETH_VLAN_TYPE3) )
            vlan_flag1_1d <= 1'b1;
        else if(s_axis_rx_tvalid & s_axis_rx_ready & s_axis_rx_sop)
            vlan_flag1_1d <= 1'b0;
    end

    always @(posedge clk ) begin
        if(!rst_n)
            vlan_flag2_1d <= 1'b0;
        else if((s_axis_rx_tvalid & s_axis_rx_ready & s_axis_rx_sop) & 
                (vlan_type1[15:0]==ETH_VLAN_TYPE0 | vlan_type1[15:0]==ETH_VLAN_TYPE1 | vlan_type1[15:0]==ETH_VLAN_TYPE2 | vlan_type1[15:0]==ETH_VLAN_TYPE3) & 
                (vlan_type2[15:0]==ETH_VLAN_TYPE0 | vlan_type2[15:0]==ETH_VLAN_TYPE1 | vlan_type2[15:0]==ETH_VLAN_TYPE2 | vlan_type2[15:0]==ETH_VLAN_TYPE3))
            vlan_flag2_1d <= 1'b1;
        else if(s_axis_rx_tvalid & s_axis_rx_ready & s_axis_rx_sop)
            vlan_flag2_1d <= 1'b0;
    end

    always @(posedge clk ) begin
        if(!rst_n)
            ipv4_flag_1d <= 1'b0;
        else if((s_axis_rx_tvalid & s_axis_rx_ready & s_axis_rx_sop) & vlan_type2[15:0]==ETH_IPV4_TYPE & 
                (vlan_type1[15:0]==ETH_VLAN_TYPE0 | vlan_type1[15:0]==ETH_VLAN_TYPE1 | vlan_type1[15:0]==ETH_VLAN_TYPE2 | vlan_type1[15:0]==ETH_VLAN_TYPE3) & 
                (vlan_type2[15:0]!=ETH_VLAN_TYPE0 & vlan_type2[15:0]!=ETH_VLAN_TYPE1 & vlan_type2[15:0]!=ETH_VLAN_TYPE2 & vlan_type2[15:0]!=ETH_VLAN_TYPE3) )
            ipv4_flag_1d <= 1'b1;
        else if((s_axis_rx_tvalid & s_axis_rx_ready & s_axis_rx_sop) & eth_type==ETH_IPV4_TYPE & 
                (vlan_type1[15:0]==ETH_VLAN_TYPE0 | vlan_type1[15:0]==ETH_VLAN_TYPE1 | vlan_type1[15:0]==ETH_VLAN_TYPE2 | vlan_type1[15:0]==ETH_VLAN_TYPE3) & 
                (vlan_type2[15:0]==ETH_VLAN_TYPE0 | vlan_type2[15:0]==ETH_VLAN_TYPE1 | vlan_type2[15:0]==ETH_VLAN_TYPE2 | vlan_type2[15:0]==ETH_VLAN_TYPE3) )
            ipv4_flag_1d <= 1'b1;
        else if((s_axis_rx_tvalid & s_axis_rx_ready & s_axis_rx_sop) & vlan_type1[15:0]==ETH_IPV4_TYPE)
            ipv4_flag_1d <= 1'b1;
        else if((s_axis_rx_tvalid & s_axis_rx_ready & s_axis_rx_sop))
            ipv4_flag_1d <= 1'b0;
    end

    always @(posedge clk ) begin
        if(!rst_n)
            ipv6_flag_1d <= 1'b0;
        else if((s_axis_rx_tvalid & s_axis_rx_ready & s_axis_rx_sop) & vlan_type2[15:0]==ETH_IPV6_TYPE & 
                (vlan_type1[15:0]==ETH_VLAN_TYPE0 | vlan_type1[15:0]==ETH_VLAN_TYPE1 | vlan_type1[15:0]==ETH_VLAN_TYPE2 | vlan_type1[15:0]==ETH_VLAN_TYPE3) & 
                (vlan_type2[15:0]!=ETH_VLAN_TYPE0 & vlan_type2[15:0]!=ETH_VLAN_TYPE1 & vlan_type2[15:0]!=ETH_VLAN_TYPE2 & vlan_type2[15:0]!=ETH_VLAN_TYPE3) )
            ipv6_flag_1d <= 1'b1;
        else if((s_axis_rx_tvalid & s_axis_rx_ready & s_axis_rx_sop) & eth_type==ETH_IPV6_TYPE & 
                (vlan_type1[15:0]==ETH_VLAN_TYPE0 | vlan_type1[15:0]==ETH_VLAN_TYPE1 | vlan_type1[15:0]==ETH_VLAN_TYPE2 | vlan_type1[15:0]==ETH_VLAN_TYPE3) & 
                (vlan_type2[15:0]==ETH_VLAN_TYPE0 | vlan_type2[15:0]==ETH_VLAN_TYPE1 | vlan_type2[15:0]==ETH_VLAN_TYPE2 | vlan_type2[15:0]==ETH_VLAN_TYPE3) )
            ipv6_flag_1d <= 1'b1;
        else if((s_axis_rx_tvalid & s_axis_rx_ready & s_axis_rx_sop) & vlan_type1[15:0]==ETH_IPV6_TYPE)
            ipv6_flag_1d <= 1'b1;
        else if(s_axis_rx_tvalid & s_axis_rx_ready & s_axis_rx_sop)
            ipv6_flag_1d <= 1'b0;
    end

    assign axis_parser_data_1d = vlan_flag1_1d ? {axis_rx_tdata_1d[0+:ETH_VLAN1_OFFSET],axis_rx_tdata_1d[ETH_VLAN2_OFFSET +:(DATA_W-ETH_VLAN2_OFFSET)], s_axis_rx_tdata[0+:32]} : 
                                 vlan_flag2_1d ? {axis_rx_tdata_1d[0+:ETH_VLAN1_OFFSET],axis_rx_tdata_1d[ETH_VLAN_OFFSET  +:(DATA_W-ETH_VLAN_OFFSET )], s_axis_rx_tdata[0+:64]} : axis_rx_tdata_1d;

    always @(posedge clk ) begin
        if(m_axis_rx_tready)begin 
            vlan_type1_1d <= vlan_type1;
            vlan_type2_1d <= vlan_type2;
        end  
    end

    always @(posedge clk ) begin
        if(m_axis_rx_tready)begin 
            axis_rx_tvalid_1d <= s_axis_rx_tvalid ;
            axis_rx_tdata_1d  <= s_axis_rx_tdata  ;
            axis_rx_tkeep_1d  <= s_axis_rx_tkeep  ;
            axis_rx_tlast_1d  <= s_axis_rx_tlast  ;
            axis_rx_sop_1d    <= s_axis_rx_sop    ;

            m_axis_rx_tvalid  <= axis_rx_tvalid_1d;
            m_axis_rx_tdata   <= axis_rx_tdata_1d ;
            m_axis_rx_tkeep   <= axis_rx_tkeep_1d ;
            m_axis_rx_tlast   <= axis_rx_tlast_1d ;
        end

        if(m_axis_rx_tready & axis_rx_tvalid_1d & axis_rx_sop_1d & (vlan_flag1_1d|vlan_flag2_1d))
            m_axis_rx_Priority <= vlan_type1_1d[23:21];
        else if(m_axis_rx_tready & axis_rx_tvalid_1d & axis_rx_sop_1d & ipv4_flag_1d)
            m_axis_rx_Priority <= axis_parser_data_1d[(IP_PKT_TOS+5)+:3];
        else if(m_axis_rx_tready & axis_rx_tvalid_1d & axis_rx_sop_1d & ipv6_flag_1d)
            m_axis_rx_Priority <= axis_parser_data_1d[(IPV6_PKT_START_POS+1)+:3];
        else if(m_axis_rx_tready & axis_rx_tvalid_1d & axis_rx_sop_1d)
            m_axis_rx_Priority <= 3'd0;
    end

endmodule
