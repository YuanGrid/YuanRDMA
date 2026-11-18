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
`default_nettype none
`timescale 1ns/1ps
module avm_config #(
    parameter       int                 USER_NUM              = 6,
    parameter       int                 SLAVE_SIZE            = 20,
    parameter       int                 ADDR_W                = 28,
    parameter       int                 DATA_W                = 32                  
)(
    input   wire    [ADDR_W-1:0]        avm_addr ,
    input   wire    [7:0]               avm_byte ,
    input   wire                        avm_read ,
    input   wire                        avm_write,
    input   wire    [DATA_W-1:0]        avm_wdat ,
    input   wire    [3:0]               avm_bcnt ,
    output  reg                         avm_wait ,
    output  reg     [DATA_W-1:0]        avm_rdat ,
    output  reg                         avm_rvld ,
    output  reg     [1:0]               avm_rspo ,
    output  reg                         avm_wrsp ,
    output  reg     [USER_NUM*ADDR_W-1:0]user_avm_addr ,
    output  reg     [USER_NUM-1:0]      user_avm_read ,
    output  reg     [USER_NUM-1:0]      user_avm_write,
    output  reg     [USER_NUM*DATA_W-1:0]user_avm_wdat,
    input   wire    [USER_NUM-1:0]      user_avm_wait ,
    input   wire    [USER_NUM*DATA_W-1:0]user_avm_rdat,
    input   wire    [USER_NUM-1:0]      user_avm_rvld ,
    input   wire    [USER_NUM*2-1:0]    user_avm_rspo ,
    input   wire    [USER_NUM-1:0]      user_avm_wrsp ,
    input   wire                        clk,
    input   wire                        rst_n
);
    localparam VCS_CFG_ADDR             = 32'h0110_0000; 
    localparam SYS_CFG_ADDR             = 32'h0120_0000;  
    localparam PKT_GEN_CFG_ADDR         = 32'h0130_0000; 
    localparam PKT_RCV_ADDR             = 32'h0140_0000; 
    localparam QDMA_ADDR                = 32'h0150_0000; 
    localparam MACADDR_ADDR             = 32'h0160_0000; 

    wire    [31:0]                      base_addr[USER_NUM-1:0];
    assign base_addr[0] = VCS_CFG_ADDR;
    assign base_addr[1] = SYS_CFG_ADDR;
    assign base_addr[2] = PKT_GEN_CFG_ADDR;
    assign base_addr[3] = PKT_RCV_ADDR;
    assign base_addr[4] = QDMA_ADDR;
    assign base_addr[5] = MACADDR_ADDR;

    always @(posedge clk ) begin
        if(!rst_n)
            avm_wait <= 1'b0;
        else if(avm_rvld | avm_wrsp)
            avm_wait <= 1'b0;
        else if(avm_write | avm_read)
            avm_wait <= 1'b1;
    end

    always @(posedge clk ) begin
        case (user_avm_rvld)
            6'b000001: begin avm_rdat[0+:DATA_W] = user_avm_rdat[0*32+:32]; avm_rspo <= user_avm_rspo[0] ;end 
            6'b000010: begin avm_rdat[0+:DATA_W] = user_avm_rdat[1*32+:32]; avm_rspo <= user_avm_rspo[1] ;end 
            6'b000100: begin avm_rdat[0+:DATA_W] = user_avm_rdat[2*32+:32]; avm_rspo <= user_avm_rspo[2] ;end 
            6'b001000: begin avm_rdat[0+:DATA_W] = user_avm_rdat[3*32+:32]; avm_rspo <= user_avm_rspo[3] ;end 
            6'b010000: begin avm_rdat[0+:DATA_W] = user_avm_rdat[4*32+:32]; avm_rspo <= user_avm_rspo[4] ;end 
            6'b100000: begin avm_rdat[0+:DATA_W] = user_avm_rdat[5*32+:32]; avm_rspo <= user_avm_rspo[5] ;end 
            default : begin avm_rdat[0+:DATA_W] = 32'hdeadbeef    ; avm_rspo <= 2'b00            ;end 
        endcase

        avm_rvld <= |user_avm_rvld;
        avm_wrsp <= |user_avm_wrsp;
    end

    generate
        for (genvar i=0 ; i<USER_NUM ; i=i+1) begin
            always @(posedge clk ) begin
                if(!rst_n)
                    user_avm_read[i] <= 1'b0;
                else if(user_avm_read[i] & (!user_avm_wait[i]))
                    user_avm_read[i] <= 1'b0;
                else if(i==0 & avm_read & (!avm_wait) & avm_addr[SLAVE_SIZE+:8] <= base_addr[i][SLAVE_SIZE+:8])
                    user_avm_read[i] <= 1'b1;
                else if(i>0 & avm_read &  (!avm_wait) & avm_addr[SLAVE_SIZE+:8] == base_addr[i][SLAVE_SIZE+:8])
                    user_avm_read[i] <= 1'b1;
            end

            always @(posedge clk ) begin
                if(!rst_n)
                    user_avm_write[i] <= 1'b0;
                else if(user_avm_write[i] & (!user_avm_wait[i]))
                    user_avm_write[i] <= 1'b0;
                else if(i==0 & avm_write & (!avm_wait) & avm_addr[SLAVE_SIZE+:8] <= base_addr[i][SLAVE_SIZE+:8])
                    user_avm_write[i] <= 1'b1;
                else if(i>0 & avm_write &  (!avm_wait) & avm_addr[SLAVE_SIZE+:8] == base_addr[i][SLAVE_SIZE+:8])
                    user_avm_write[i] <= 1'b1;
            end
            
            always @(posedge clk ) begin
                if(!avm_wait)begin 
                    user_avm_addr[i*ADDR_W+:ADDR_W] <= avm_addr;
                    user_avm_wdat[i*DATA_W+:DATA_W] <= avm_wdat[DATA_W-1:0];
                end  
            end

        end
    endgenerate

endmodule
