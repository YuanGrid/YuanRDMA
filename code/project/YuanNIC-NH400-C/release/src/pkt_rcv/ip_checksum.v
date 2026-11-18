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
module ip_checksum  
(
input         p_axis_tvalid,
input [511:0] p_axis_tdata,
input         p_axis_tlast,
output        ip_checksum_error,
input         aclk,
input         aresetn
);

localparam IDLE                    = 2'd0;
localparam WORK                    = 2'd1; 
localparam TAIL                    = 2'd2; 


reg [31:0] accumulator;
reg [15:0] checksum;

reg [1:0] c_state;
reg [1:0] n_state;


reg [511:0] p_axis_tdata_d1;
reg [511:0] p_axis_tdata_d2;


function [15:0] fold_carry;
    input [31:0] sum;
    reg [31:0] folded;
    begin
        folded = sum;
        if (folded[31:16] != 0) begin
            folded = folded[15:0] + folded[31:16];
        end
        fold_carry = folded[15:0];
    end
endfunction


function [15:0] fold_sum;
    input [511:0] data;
    reg [31:0] sum1;
    reg [31:0] sum2;
    reg [31:0] sum3;
    reg [31:0] sum_all;
    begin
        sum1 = data[48*8 +: 16] + data[46*8 +: 16] + data[44*8 +: 16];
        sum2 = data[42*8 +: 16] + data[40*8 +: 16] + data[36*8 +: 16];
        sum3 = data[34*8 +: 16] + data[32*8 +: 16] + data[30*8 +: 16];
        sum_all = sum1 + sum2 + sum3;
        fold_sum =  sum_all[31:16] + sum_all[15:0];
    end
endfunction


assign  ip_checksum_error = (p_axis_tdata_d2[38*8 +: 16] == checksum) ? 1'b0 : 1'b1;

  always @(*) begin
    n_state  = c_state;
    case (c_state)
      IDLE: begin
        if(p_axis_tvalid) begin    
	   if(!p_axis_tlast)begin
             n_state  = WORK;
           end  
        end 
      end	
   
      WORK: begin
        if(p_axis_tvalid) begin    
	   if(!p_axis_tlast)
             n_state  = TAIL;
           else
             n_state  = IDLE;
        end 
      end	
 
      TAIL: begin
        if(p_axis_tvalid && p_axis_tlast) begin    
             n_state  = IDLE;
        end 
      end	
 
      default: begin    
         n_state = IDLE;
      end
    endcase
  end
  

  always @(posedge aclk) begin
    if (~aresetn) begin
      c_state  <= IDLE;
    end
    else begin
      c_state  <= n_state;
    end
  end    
  
  always @(posedge aclk) begin
    if (!aresetn) begin
      p_axis_tdata_d1 <= 'h0;
    end 
    else begin
      if (c_state == IDLE) begin
        if(p_axis_tvalid)begin
          p_axis_tdata_d1 <= p_axis_tdata;
        end
      end	
    end
  end 
 
  always @(posedge aclk) begin
    if (!aresetn)
      p_axis_tdata_d2 <= 'h0;
    else 
      p_axis_tdata_d2 <= p_axis_tdata_d1;
  end  

  always @(posedge aclk) begin
    if (!aresetn) begin
      accumulator <= 32'h0;
    end 
    else begin
      if (c_state == IDLE) begin
        if(p_axis_tvalid)begin
          accumulator <= fold_sum(p_axis_tdata);
        end  
      end
    end
  end  
 
  always @(posedge aclk) begin
    if (!aresetn) begin
      checksum  <= 16'h0;
    end 
    else begin
      if (c_state == IDLE || c_state == WORK) begin
        checksum <= ~fold_carry(accumulator);
      end
    end  
  end  
		
 
endmodule	      
