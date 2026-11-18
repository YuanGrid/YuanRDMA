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
// Utility block that converts an AXI-Lite interface to simple register R/W
// signals.  The two interfaces can be configured to run under a common clock
// where signals are directly sampled, or independent clocks where CDC buffers
// are included to guarantee data validity.
`timescale 1ns/1ps
module axil_to_avmm_assign #(
    parameter     CLOCKING_MODE = "common_clock",
    parameter int ADDR_W        = 32,
    parameter int DATA_W        = 32
) (
    input   wire                        clk,
    input   wire                        rst_n,
    input   wire                        s_axil_awvalid,
    input   wire    [ADDR_W-1:0]        s_axil_awaddr,
    output  wire                        s_axil_awready,
    input   wire                        s_axil_wvalid,
    input   wire    [DATA_W-1:0]        s_axil_wdata,
    output  wire                        s_axil_wready,
    output  reg                         s_axil_bvalid,
    output  wire    [1:0]               s_axil_bresp,
    input   wire                        s_axil_bready,
    input   wire                        s_axil_arvalid,
    input   wire    [ADDR_W-1:0]        s_axil_araddr,
    output  wire                        s_axil_arready,
    output  wire                        s_axil_rvalid,
    output  wire    [DATA_W-1:0]        s_axil_rdata,
    output  wire    [1:0]               s_axil_rresp,
    input   wire                        s_axil_rready,

    output  wire    [27:0]              avm_addr,
    output  wire    [7:0]               avm_byte,
    output  wire                        avm_read,
    output  wire                        avm_write,
    output  wire    [63:0]              avm_wdat,
    output  wire    [3:0]               avm_bcnt, //支锟斤拷burst_cnt为1
    input   reg                         avm_wait,
    input   reg     [63:0]              avm_rdat,
    input   reg                         avm_rvld,
    input   wire    [1:0]               avm_rspo,
    input   reg                         avm_wrsp //write response valid
);
    reg                 wr_done;
    assign avm_write = s_axil_awvalid & s_axil_wvalid;
    assign avm_read  = s_axil_arvalid;
    assign avm_addr  = s_axil_arvalid ? s_axil_araddr : s_axil_awaddr;
    assign avm_byte  = 8'h0f;
    assign avm_wdat  = {32'b0,s_axil_wdata};
    assign avm_bcnt  = 4'd1;
    assign s_axil_awready = ~avm_wait;
    assign s_axil_wready  = ~avm_wait;
    assign s_axil_bresp   = 2'b0;

    always @(posedge clk ) begin
        if(!rst_n)
            s_axil_bvalid <= 1'b0;
        else if(s_axil_bvalid & s_axil_bready)
            s_axil_bvalid <= 1'b0;
        else if(avm_wrsp)
            s_axil_bvalid <= 1'b1;
    end
endmodule
