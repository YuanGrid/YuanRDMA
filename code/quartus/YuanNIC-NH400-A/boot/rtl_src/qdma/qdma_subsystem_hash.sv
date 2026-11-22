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


module  qdma_subsystem_hash(

  input         p_axis_tvalid,
  input [511:0] p_axis_tdata,
  input         p_axis_tlast,
  input         p_axis_tready,

 (*mark_debug = "true"*)   input [319:0] hash_key,
  (*mark_debug = "true"*)  output        hash_result_valid,
  (*mark_debug = "true"*)  output [31:0] hash_result,
  output        arp_icmp_flag,
  input         aclk,
  input         aresetn
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
localparam ETH_TYPE_VLAN0         = 16'h0081;
localparam ETH_TYPE_VLAN1         = 16'hA888;
localparam ETH_TYPE_VLAN2         = 16'h0091;
localparam ETH_TYPE_VLAN3         = 16'h0092;


localparam IDLE                    = 1'b0;
localparam TAIL                    = 1'b1; 

reg  c_state;
reg  n_state;
 
reg [287:0] input_288bit;
reg [31:0] ret_ipv4;
reg [31:0] ret_ipv6;
reg  rss_start;
reg  rss_result_vld_d1;
reg  rss_result_vld_d2;
reg  rss_result_vld_d3;
reg [31:0] hash_result_d1;
reg [31:0] hash_result_d2;
reg [31:0] hash_result_d3;
reg arp_icmp_flag_d1;
reg arp_icmp_flag_d2;
reg arp_icmp_flag_d3;
reg arp_icmp_en;

wire [15:0] eth_type;
reg  [15:0] eth_type_d2;
reg  [3:0]  input_len;
wire [511:0] byte_data;
wire [7:0] icmp_type;

reg         p_axis_tvalid_d1;
reg [511:0] p_axis_tdata_d1 ;
reg         p_axis_tlast_d1 ;
reg         p_axis_tready_d1;

reg         vlan1_flag;
reg         vlan2_flag;
wire [15:0] vlan1_type;
wire [15:0] vlan2_type;
wire [511:0]p_axis_tdata_parser_d1 ;

always @(posedge aclk or negedge aresetn) begin
  if(~aresetn) begin
    p_axis_tvalid_d1 <= 1'b0;
    p_axis_tdata_d1  <= 512'b0;
    p_axis_tlast_d1  <= 1'b0;
    p_axis_tready_d1 <= 1'b0;
  end
  else begin 
    p_axis_tvalid_d1 <= p_axis_tvalid ;
    p_axis_tdata_d1  <= p_axis_tdata  ;
    p_axis_tlast_d1  <= p_axis_tlast  ;
    p_axis_tready_d1 <= p_axis_tready ;
  end 
end 

assign vlan1_type = p_axis_tdata[111:96];
assign vlan2_type = p_axis_tdata[143:128];

always @(posedge aclk or negedge aresetn) begin
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

assign p_axis_tdata_parser_d1 = vlan2_flag ?  {p_axis_tdata[63:00],p_axis_tdata_d1[511:160],p_axis_tdata_d1[95:0]} : 
                                vlan1_flag ?  {p_axis_tdata[32:00],p_axis_tdata_d1[511:128],p_axis_tdata_d1[95:0]} :
                                               p_axis_tdata_d1;
assign icmp_type   = p_axis_tdata_parser_d1[191:184];
assign eth_type    = p_axis_tdata_parser_d1[111:96];
assign byte_data   = byte_reverse(p_axis_tdata_parser_d1);

always @(*) begin
    n_state  = c_state;
    case (c_state)	
      IDLE: begin
        if(p_axis_tvalid_d1 & p_axis_tready_d1) begin    
	      if(p_axis_tlast_d1)
             n_state  = IDLE;
           else
             n_state  = TAIL;
        end 
      end	
 
      TAIL: begin
        if(p_axis_tvalid_d1 & p_axis_tready_d1 & p_axis_tlast_d1) begin    
             n_state  = IDLE;
        end 
      end	
 
      default: begin    
         n_state = IDLE;
      end
    endcase
  end
  

  always @(posedge aclk or negedge aresetn) begin
    if (~aresetn) begin
      c_state  <= IDLE;
    end
    else begin
      c_state  <= n_state;
    end
  end    


    
 always @(posedge aclk or negedge aresetn) begin
    if (~aresetn) begin
      input_288bit <= 288'b0;	
    end
    else begin 
      if(c_state == IDLE)begin
        if(p_axis_tvalid_d1 & p_axis_tready_d1) begin 
          if(eth_type == ETH_TYPE_IP4)begin
            input_288bit[31:0]   <= byte_data[34*8 +: 32];
            input_288bit[63:32]  <= byte_data[30*8 +: 32];
            input_288bit[95:64]  <= byte_data[26*8 +: 32];
          end  
          else if(eth_type == ETH_TYPE_IP6)begin
            input_288bit[31:0]  <= byte_data[38*8 +: 32];
            input_288bit[63:32] <= byte_data[34*8 +: 32];
            input_288bit[95:64] <= byte_data[30*8 +: 32];
            input_288bit[127:96]<= byte_data[26*8 +: 32];
            input_288bit[159:128] <= byte_data[22*8 +: 32];
            input_288bit[191:160] <= byte_data[18*8 +: 32];
            input_288bit[223:192] <= byte_data[14*8 +: 32];
            input_288bit[255:224] <= byte_data[10*8 +: 32];
            input_288bit[287:256] <= byte_data[6*8 +: 32];
          end
        end
      end  
    end  
  end  

    always @(posedge aclk or negedge aresetn) begin
    if (~aresetn) begin
      rss_start  <= 1'b0;
    end
    else if(c_state == IDLE)begin  
       if(p_axis_tvalid_d1 & p_axis_tready_d1) begin 
         rss_start  <= 1'b1;
       end
       else begin
         rss_start  <= 1'b0;
       end
     end
     else begin
        rss_start  <= 1'b0;  
     end      
  end 

  always @(posedge aclk or negedge aresetn) begin
    if (~aresetn) begin
      input_len <= 4'd0;
    end
    else if(c_state == IDLE)begin 
      if(p_axis_tvalid_d1 & p_axis_tready_d1) begin 
        if(eth_type == ETH_TYPE_ARP)
          input_len <= 4'd0;
        else if(eth_type == ETH_TYPE_IP4)
          input_len <= 4'd3;
        else if(eth_type == ETH_TYPE_IP6)
          input_len <= 4'd9;
      end
    end
  end     
      

 always @(posedge aclk or negedge aresetn) begin
    if (~aresetn) begin
       arp_icmp_en <= 1'b0;
    end  
    else if(c_state == IDLE)begin 
      if(p_axis_tvalid_d1 & p_axis_tready_d1) begin  
         if(eth_type == ETH_TYPE_ARP || icmp_type == ETH_TYPE_ICMP)
            arp_icmp_en <= 1'b1;
         else
            arp_icmp_en <= 1'b0;
      end    
      else begin
          arp_icmp_en <= 1'b0;
      end       
    end
    else begin  
      arp_icmp_en <= 1'b0;  
    end 
  end   
      
    always @(*) begin
      if(rss_start)  begin
        ret_ipv6 = 32'b0;
        //for (j = 0 ; j < input_len; j = j + 1) begin
        for (integer j = 0 ; j < 9; j = j + 1) begin
          for (integer i = 0; i < 32; i = i + 1) begin
            if (input_288bit[j*32+i]) begin
              ret_ipv6 = ret_ipv6 ^ ((hash_key[j*32 +: 32]<<(31-i)) | (hash_key[j*32+32 +: 32]>>(i+1)));
            end
          end  
        end
      end else begin 
        ret_ipv6 = 32'b0;
      end  
    end 

    always @(*) begin
      if(rss_start)  begin
        ret_ipv4 = 32'b0;
        //for (j = 0 ; j < input_len; j = j + 1) begin
        for (integer k = 0 ; k < 3; k = k + 1) begin
          for (integer m = 0; m < 32; m = m + 1) begin
            if (input_288bit[k*32+m]) begin
              ret_ipv4 = ret_ipv4 ^ ((hash_key[k*32 +: 32]<<(31-m)) | (hash_key[k*32+32 +: 32]>>(m+1)));
            end
          end  
        end
      end else begin 
        ret_ipv4 = 32'b0;
      end  
    end

    always @(posedge aclk ) begin
        eth_type_d2 <= eth_type;
    end

  always @(posedge aclk or negedge aresetn) begin
    if (~aresetn) begin
      arp_icmp_flag_d1 <= 1'b0;
      arp_icmp_flag_d2 <= 1'b0;
      arp_icmp_flag_d3 <= 1'b0;
      rss_result_vld_d1  <= 1'b0;
      rss_result_vld_d2  <= 1'b0;
      rss_result_vld_d3  <= 1'b0;
      hash_result_d1 <= 32'd0;
      hash_result_d2 <= 32'd0;
      hash_result_d3 <= 32'd0;
    end
    else begin
      arp_icmp_flag_d1 <= arp_icmp_en;
      arp_icmp_flag_d2 <= arp_icmp_flag_d1;
      arp_icmp_flag_d3 <= arp_icmp_flag_d2;
      rss_result_vld_d1  <= rss_start;
      rss_result_vld_d2  <= rss_result_vld_d1;
      rss_result_vld_d3  <= rss_result_vld_d2;
      if(eth_type_d2 == ETH_TYPE_IP6)
        hash_result_d1 <= ret_ipv6;
      else  
        hash_result_d1 <= ret_ipv4;
      hash_result_d2 <= hash_result_d1;
      hash_result_d3 <= hash_result_d2;
    end
   end   
  
  assign  arp_icmp_flag = arp_icmp_flag_d3;  
  assign  hash_result_valid =  rss_result_vld_d3;
  assign  hash_result = hash_result_d3; 
endmodule
