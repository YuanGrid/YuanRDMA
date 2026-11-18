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
module statistics_ram_16k #(
    parameter       DATA_W          = 32,
    parameter       ADDR_W          = 12,
    parameter       CNT_NUM         = 2**ADDR_W,
    parameter       UNIT_ADDR_W     = 12,
    parameter       MODE            = "STATIC"
)
(  
    input                           stream_pkt_tvalid,
    input                           stream_pkt_tlast,
    input                           stream_pkt_tready,
    input           [DATA_W-1:0]    new_data,
    input           [ADDR_W-1:0]    stream_pkt_id_w,
    input                           stream_pkt_r_req,
    input           [ADDR_W:0]      stream_pkt_id_r,
    input                           stream_pkt_rst,
    output          [DATA_W-1:0]    stream_pkt_rdata,
    input                           axis_aclk,
    input                           axil_aclk,
    input                           axis_rstn
);
    localparam                      WIDTH_DIFF    = ADDR_W > UNIT_ADDR_W ? ADDR_W-UNIT_ADDR_W : 0;
    localparam                      RAM_NUM       = 2**WIDTH_DIFF;
    
    wire    [RAM_NUM-1:0]           stream_pkt_tvalid_unit;
    wire    [DATA_W-1:0]            stream_pkt_rdata_unit[RAM_NUM-1:0];
    reg     [WIDTH_DIFF-1:0]        unit_data_select_d[2:1];
    reg     [DATA_W-1:0]            stream_pkt_rdata_reg;

    always @(posedge axil_aclk ) begin
        unit_data_select_d[1] <= stream_pkt_id_r[UNIT_ADDR_W+:WIDTH_DIFF];
        stream_pkt_rdata_reg  <= stream_pkt_rdata_unit[unit_data_select_d[1]];
    end
    assign stream_pkt_rdata = stream_pkt_rdata_reg;
    
    generate
        for (genvar i=0 ; i<RAM_NUM ; i=i+1) begin
            assign stream_pkt_tvalid_unit[i] = stream_pkt_tvalid & (stream_pkt_id_w[UNIT_ADDR_W+:WIDTH_DIFF]==i);

            statistics_ram #(
                .DATA_W                     (DATA_W             ),
                .ADDR_W                     (UNIT_ADDR_W        ),
                .CNT_NUM                    (2**UNIT_ADDR_W     ),
                .MODE                       (MODE               )//"MAX" "MIN" "CNT"
            )u11_pkt_cnt(
                .stream_pkt_tvalid          (stream_pkt_tvalid_unit[i] ),
                .stream_pkt_tlast           (stream_pkt_tlast       ),
                .stream_pkt_tready          (stream_pkt_tready      ),
                .new_data                   (new_data               ),
                .stream_pkt_id_w            (stream_pkt_id_w[UNIT_ADDR_W-1:0]   ),
                .stream_pkt_r_req           (stream_pkt_r_req                   ),
                .stream_pkt_id_r            (stream_pkt_id_r[UNIT_ADDR_W-1:0]   ),
                .stream_pkt_rst             (stream_pkt_rst                     ),
                .stream_pkt_rdata           (stream_pkt_rdata_unit[i]           ),
                .axis_aclk                  (axis_aclk           ),
                .axil_aclk                  (axil_aclk           ),
                .axis_rstn                  (axis_rstn           )
            );
        end
    endgenerate


    
endmodule
