`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/03/05 11:36:21
// Design Name: 
// Module Name: qdma_subsystem_hash_m
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


module  qdma_subsystem_hash #(parameter DATA_WIDTH = 1024) (

  input                  p_axis_tvalid,
  input [DATA_WIDTH-1:0] p_axis_tdata,
  input                  p_axis_tlast,
  input                  p_axis_tready,

  input [319:0]         hash_key,
  output reg            hash_result_valid,
  output reg  [31:0]    hash_result,
  output                arp_icmp_flag,
  input                 aclk,
  input                 aresetn
);


function [511:0] byte_reverse;
    input [511:0] data_in;
    begin
    byte_reverse = {
        data_in[7:0],   data_in[15:8],   data_in[23:16],   data_in[31:24],
        data_in[39:32], data_in[47:40],  data_in[55:48],  data_in[63:56],
        data_in[71:64], data_in[79:72],  data_in[87:80],  data_in[95:88],
        data_in[103:96], data_in[111:104], data_in[119:112], data_in[127:120],
        data_in[135:128], data_in[143:136], data_in[151:144], data_in[159:152],
        data_in[167:160], data_in[175:168], data_in[183:176], data_in[191:184],
        data_in[199:192], data_in[207:200], data_in[215:208], data_in[223:216],
        data_in[231:224], data_in[239:232], data_in[247:240], data_in[255:248],
        data_in[263:256], data_in[271:264], data_in[279:272], data_in[287:280],
        data_in[295:288], data_in[303:296], data_in[311:304], data_in[319:312],
        data_in[327:320], data_in[335:328], data_in[343:336], data_in[351:344],
        data_in[359:352], data_in[367:360], data_in[375:368], data_in[383:376],
        data_in[391:384], data_in[399:392], data_in[407:400], data_in[415:408],
        data_in[423:416], data_in[431:424], data_in[439:432], data_in[447:440],
        data_in[455:448], data_in[463:456], data_in[471:464], data_in[479:472],
        data_in[487:480], data_in[495:488], data_in[503:496], data_in[511:504]
    };
    end
endfunction




localparam ETH_TYPE_ICMP         = 8'h01;
localparam ETH_TYPE_ARP          = 16'h0608;
localparam ETH_TYPE_IP4          = 16'h0008;
localparam ETH_TYPE_IP6          = 16'hDD86;
localparam ETH_TYPE_VLAN0        = 16'h0081;
localparam ETH_TYPE_VLAN1        = 16'hA888;
localparam ETH_TYPE_VLAN2        = 16'h0091;
localparam ETH_TYPE_VLAN3        = 16'h0092;


localparam IDLE                    = 1'b0;
localparam TAIL                    = 1'b1; 

reg  c_state;
reg  n_state;
 
reg [287:0] input_288bit[8:0];
reg [31:0] ret_ipv4;
reg [31:0] ret_ipv6[8:0];
reg [31:0] ret_ipv6_reg[9:0];
reg  rss_start[9:0];
reg  rss_result_vld_d1;
reg  rss_result_vld_d2;
reg  rss_result_vld_d3;
reg [31:0] hash_result_d1;
reg [31:0] hash_result_d2;
reg [31:0] hash_result_d3;

wire [15:0] eth_type;
reg  [15:0] eth_type_d[9:0];
wire [DATA_WIDTH-1:0] byte_data;

reg                  p_axis_tsop;
reg                  p_axis_tsop_d1;
reg                  p_axis_tvalid_d1;
reg [DATA_WIDTH-1:0] p_axis_tdata_d1 ;
reg                  p_axis_tlast_d1 ;
reg                  p_axis_tready_d1;
reg                  p_axis_tsop_d2;
reg                  p_axis_tvalid_d2;
reg [DATA_WIDTH-1:0] p_axis_tdata_d2 ;
reg                  p_axis_tlast_d2 ;
reg                  p_axis_tready_d2;

reg                  vlan1_flag;
reg                  vlan2_flag;
wire [15:0]          vlan1_type;
wire [15:0]          vlan2_type;
reg [511:0] p_axis_tdata_parser_d2 ;

    always @(posedge aclk ) begin
        if(!aresetn)
            p_axis_tsop <= 1'b1;
        else if(p_axis_tvalid & p_axis_tlast & p_axis_tready)
            p_axis_tsop <= 1'b1;
        else if(p_axis_tvalid & p_axis_tready)
            p_axis_tsop <= 1'b0;
    end

    always @(posedge aclk or negedge aresetn) begin
        if(~aresetn) begin
            p_axis_tsop_d1   <= 1'b0;
            p_axis_tvalid_d1 <= 1'b0;
            p_axis_tdata_d1  <= 1024'd0;
            p_axis_tlast_d1  <= 1'b0;
            p_axis_tready_d1 <= 1'b0;
        end else begin 
            p_axis_tsop_d1   <= p_axis_tsop;
            p_axis_tvalid_d1 <= p_axis_tvalid ;
            p_axis_tdata_d1  <= p_axis_tdata  ;
            p_axis_tlast_d1  <= p_axis_tlast  ;
            p_axis_tready_d1 <= p_axis_tready ;
            p_axis_tsop_d2   <= p_axis_tsop_d1;
            p_axis_tvalid_d2 <= p_axis_tvalid_d1 ;
            p_axis_tdata_d2  <= p_axis_tdata_d1  ;
            p_axis_tlast_d2  <= p_axis_tlast_d1  ;
            p_axis_tready_d2 <= p_axis_tready_d1 ;
        end 
    end 

    assign vlan1_type = p_axis_tdata[111:96];
    assign vlan2_type = p_axis_tdata[143:128];

    always @(posedge aclk or negedge aresetn) begin
        if(~aresetn)begin
            vlan1_flag <= 1'b0;
            vlan2_flag <= 1'b0;
        end else if(p_axis_tvalid && (vlan1_type == ETH_TYPE_VLAN0 || vlan1_type == ETH_TYPE_VLAN1 || vlan1_type == ETH_TYPE_VLAN2 || vlan1_type == ETH_TYPE_VLAN3) 
                                  && (vlan2_type != ETH_TYPE_VLAN0 && vlan2_type != ETH_TYPE_VLAN1 && vlan2_type != ETH_TYPE_VLAN2 && vlan2_type != ETH_TYPE_VLAN3))begin
            vlan1_flag <= 1'b1;
            vlan2_flag <= 1'b0;
        end else if(p_axis_tvalid && (vlan1_type == ETH_TYPE_VLAN0 || vlan1_type == ETH_TYPE_VLAN1 || vlan1_type == ETH_TYPE_VLAN2 || vlan1_type == ETH_TYPE_VLAN3) 
                                  && (vlan2_type == ETH_TYPE_VLAN0 || vlan2_type == ETH_TYPE_VLAN1 || vlan2_type == ETH_TYPE_VLAN2 || vlan2_type == ETH_TYPE_VLAN3))begin
            vlan1_flag <= 1'b0;
            vlan2_flag <= 1'b1;
        end else begin 
            vlan1_flag <= 1'b0;
            vlan2_flag <= 1'b0;
        end  
    end

generate if(DATA_WIDTH == 1024) begin 
    always @(posedge aclk ) begin
        if(vlan2_flag)
            p_axis_tdata_parser_d2 <= {p_axis_tdata_d1[63+512:00+512],p_axis_tdata_d1[511:160],p_axis_tdata_d1[95:0]};
        else if(vlan1_flag)
            p_axis_tdata_parser_d2 <= {p_axis_tdata_d1[32+512:00+512],p_axis_tdata_d1[511:128],p_axis_tdata_d1[95:0]};
        else  
            p_axis_tdata_parser_d2 <= p_axis_tdata_d1[511:0];
    end
end
endgenerate

generate if(DATA_WIDTH == 512) begin 
    always @(posedge aclk ) begin
        if(vlan2_flag)
            p_axis_tdata_parser_d2 <= {p_axis_tdata[63:00],p_axis_tdata_d1[511:160],p_axis_tdata_d1[95:0]};
        else if(vlan1_flag)
            p_axis_tdata_parser_d2 <= {p_axis_tdata[32:00],p_axis_tdata_d1[511:128],p_axis_tdata_d1[95:0]};
        else  
            p_axis_tdata_parser_d2 <= p_axis_tdata_d1[511:0];
    end
end
endgenerate

    assign eth_type    = p_axis_tdata_parser_d2[111:96];
    assign byte_data   = byte_reverse(p_axis_tdata_parser_d2);

    always @(posedge aclk) begin
        if(!aresetn)begin 
            input_288bit[0]          <= 288'b0;
        end else if(p_axis_tsop_d2 & p_axis_tvalid_d2 & p_axis_tready_d2 & eth_type == ETH_TYPE_IP4)begin
            input_288bit[0][31:0]    <= byte_data[34*8 +: 32];
            input_288bit[0][63:32]   <= byte_data[30*8 +: 32];
            input_288bit[0][95:64]   <= byte_data[26*8 +: 32];
            input_288bit[0][287:96]  <= 192'b0;
        end else if(p_axis_tsop_d2 & p_axis_tvalid_d2 & p_axis_tready_d2 & eth_type == ETH_TYPE_IP6)begin 
            input_288bit[0][31:0]    <= byte_data[38*8 +: 32];
            input_288bit[0][63:32]   <= byte_data[34*8 +: 32];
            input_288bit[0][95:64]   <= byte_data[30*8 +: 32];
            input_288bit[0][127:96]  <= byte_data[26*8 +: 32];
            input_288bit[0][159:128] <= byte_data[22*8 +: 32];
            input_288bit[0][191:160] <= byte_data[18*8 +: 32];
            input_288bit[0][223:192] <= byte_data[14*8 +: 32];
            input_288bit[0][255:224] <= byte_data[10*8 +: 32];
            input_288bit[0][287:256] <= byte_data[6*8 +: 32];
        end

        input_288bit[8:1] <= input_288bit[7:0];
    end  

    always @(posedge aclk) begin
        if(p_axis_tsop_d2 & p_axis_tvalid_d2 & p_axis_tready_d2)  
            rss_start[0]  <= 1'b1;
        else
            rss_start[0]  <= 1'b0;
        
        rss_start[9:1] <= rss_start[8:0];
    end 

    always @(posedge aclk ) begin
        ret_ipv6_reg[0] <= 32'b0;
    end

    generate
        for (genvar j=0;j<9;j=j+1) begin
            always @(*) begin
                ret_ipv6[j] = ret_ipv6_reg[j];
                for(integer i=0;i<32;i=i+1)begin 
                    if(input_288bit[j][j*32+i])
                        ret_ipv6[j] = ret_ipv6[j]^((hash_key[j*32 +: 32]<<(31-i)) | (hash_key[j*32+32 +: 32]>>(i+1)));
                end  
            end
             always @(posedge aclk ) begin
                ret_ipv6_reg[j+1]<=ret_ipv6[j];
             end
        end
    endgenerate

    always @(posedge aclk ) begin
        eth_type_d[9:0] <= {eth_type_d[8:0],eth_type};
    end

    always @(posedge aclk) begin
        hash_result_valid  <= rss_start[9];
        
        if(eth_type_d[9] == ETH_TYPE_IP6 || eth_type_d[9] == ETH_TYPE_IP4)
            hash_result <= ret_ipv6_reg[9];
        else 
            hash_result <= 32'b0;
        
    end   

endmodule
