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

`default_nettype none
`timescale 1ns/1ps
module avm_register #(
    parameter                           CLOCKING_MODE = "common_clock",
    parameter       int                 ADDR_W = 28,
    parameter       int                 DATA_W = 32
) (
    input   wire    [ADDR_W-1:0]        avm_addr ,
    input   wire                        avm_read ,
    input   wire                        avm_write,
    input   wire    [DATA_W-1:0]        avm_wdat ,
    output  reg                         avm_wait ,
    output  reg     [DATA_W-1:0]        avm_rdat ,
    output  reg                         avm_rvld ,
    output  reg     [1:0]               avm_rspo ,
    output  reg                         avm_wrsp ,
    output  reg                         reg_en,
    output  reg                         reg_we,
    output  reg     [ADDR_W-1:0]        reg_addr,
    output  reg     [DATA_W-1:0]        reg_din,
    input   wire    [DATA_W-1:0]        reg_dout,
    input   wire                        clk,
    input   wire                        rst_n
);
    reg                                 reg_en_d1;
    reg                                 reg_we_d1;

    always @(posedge clk ) begin
        if(!rst_n)
            avm_wait <= 1'b0;
        else if(avm_wrsp | avm_rvld)
            avm_wait <= 1'b0;
        else if(avm_write | avm_read)
            avm_wait <= 1'b1;
    end

    always @(posedge clk ) begin
        avm_rdat <= reg_dout;
        avm_rvld <= reg_en_d1 & (~reg_we_d1);
        avm_rspo <= 2'b0;
        avm_wrsp <= reg_we;
        reg_en_d1 <= reg_en;
        reg_we_d1 <= reg_we;
    end

    always @(posedge clk ) begin
        reg_en   <= (~avm_wait) & (avm_read|avm_write);
        reg_we   <= (~avm_wait) & (avm_write);
        reg_addr <= {8'd0,avm_addr[19:0]};
        reg_din  <= avm_wdat;
    end

endmodule
