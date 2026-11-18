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
module rx_width_convt #(
    parameter                               S_DATA_W    = 1024,
    parameter                               S_INFO_W    = $clog2(S_DATA_W/8),
    parameter                               M_DATA_W    = 512,
    parameter                               M_INFO_W    = $clog2(M_DATA_W/8)
)(    
    input                                   clk,
    input                                   rst_n,
    input                                   s_axis_tvalid,
    input           [S_DATA_W-1:0]          s_axis_tdata,
    input           [S_INFO_W-1:0]          s_axis_tkeep,
    input                                   s_axis_tlast,
    output  wire                            s_axis_tready,
    output  reg                             m_axis_tvalid,
    output  reg     [M_DATA_W-1:0]          m_axis_tdata,
    output  reg     [M_INFO_W-1:0]          m_axis_tkeep,
    output  reg                             m_axis_tlast,
    input                                   m_axis_tready
);
    reg                                     convt_cnt;
    reg     [M_DATA_W-1:0]                  s_axis_tdata_half;
    wire                                    s_axis_less_64;
    reg     [S_INFO_W-1:0]                  s_axis_tkeep_reg;
    reg                                     s_axis_tlast_reg;
    reg                                     s_axis_data_vld;
    reg                                     s_axis_tready_reg;


    //assign s_axis_tready = m_axis_tready & convt_cnt
    assign s_axis_less_64 = s_axis_tready & s_axis_tvalid & s_axis_tlast & s_axis_tkeep <= S_INFO_W'(2**M_INFO_W) & s_axis_tkeep != 0;

    always @(posedge clk ) begin
        if(!rst_n)
            s_axis_tready_reg <= 1'b1;
        else 
            s_axis_tready_reg <= s_axis_tready;

        s_axis_data_vld   <= s_axis_tvalid & s_axis_tready;
    end

    assign s_axis_tready = m_axis_tvalid & m_axis_tready & (convt_cnt | m_axis_tlast) ? 1'b1:
                           s_axis_data_vld                                            ? 1'b0:s_axis_tready_reg;

    always @(posedge clk ) begin
        if(!rst_n)
            m_axis_tvalid <= 1'b0;
        else if(s_axis_tready & s_axis_tvalid)
            m_axis_tvalid <= 1'b1;
        else if(m_axis_tvalid & m_axis_tready & (convt_cnt | m_axis_tlast))
            m_axis_tvalid <= 1'b0;
    end

    always @(posedge clk ) begin
        if(!rst_n)
            convt_cnt <= 1'b0;
        else if(m_axis_tvalid & m_axis_tready & m_axis_tlast)
            convt_cnt <= 1'b0;
        else if(m_axis_tvalid & m_axis_tready)
            convt_cnt <= ~convt_cnt;
    end

    always @(posedge clk ) begin
        if(s_axis_tready & s_axis_tvalid)
            s_axis_tdata_half <= s_axis_tdata[M_DATA_W+:M_DATA_W];

        if(s_axis_tready & s_axis_tvalid & (!s_axis_less_64))begin 
            s_axis_tkeep_reg <= s_axis_tkeep;
            s_axis_tlast_reg <= s_axis_tlast;
        end  
    end

    always @(posedge clk ) begin
        if(s_axis_tready & s_axis_tvalid)
            m_axis_tdata <= s_axis_tdata[0+:M_DATA_W];
        else if(m_axis_tvalid & m_axis_tready)
            m_axis_tdata <= s_axis_tdata_half;
    end

    always @(posedge clk ) begin
        if(!rst_n)
            m_axis_tkeep <= {M_INFO_W{1'b0}};
        else if(s_axis_less_64)
            m_axis_tkeep <= 2**M_INFO_W - s_axis_tkeep[M_INFO_W-1:0];
        else if(m_axis_tvalid & m_axis_tready & m_axis_tlast)
            m_axis_tkeep <= {M_INFO_W{1'b0}};
        else if(m_axis_tvalid & m_axis_tready & (!convt_cnt) & s_axis_tlast_reg)
            m_axis_tkeep <= 2**M_INFO_W - s_axis_tkeep_reg[M_INFO_W-1:0];
    end

    always @(posedge clk ) begin
        if(!rst_n)
            m_axis_tlast <= 1'b0;       
        else if(s_axis_less_64)
            m_axis_tlast <= 1'b1;
        else if(m_axis_tvalid & m_axis_tready & m_axis_tlast)
            m_axis_tlast <= 1'b0; 
        else if(m_axis_tvalid & m_axis_tready & (!convt_cnt) & s_axis_tlast_reg)
            m_axis_tlast <= 1'b1;
    end

endmodule
