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
module tuple_add_ram #(
    parameter       DATA_W          = 32,
    parameter       ADDR_W          = 12,
    parameter       RAM_ADDR_W      = 10
)
(
    input                           clk,
    input                           rst_n,
    input                           cfg_wen0,
    input           [ADDR_W-1:0]    cfg_waddr0,
    input           [DATA_W-1:0]    cfg_wdata0,
    input                           cfg_wen1,
    input           [ADDR_W-1:0]    cfg_waddr1,
    input           [DATA_W-1:0]    cfg_wdata1,
    input                           rtl_ren,
    input           [ADDR_W-1:0]    rtl_raddr,
    output  reg     [43:0]          rtl_rdata //43:36  offset; 35:32  mask; 31:0 rslt
);
    localparam REAL_ADDR_W          = ADDR_W > RAM_ADDR_W ? RAM_ADDR_W : ADDR_W;
    //tuple_ram0_rdata  31:16      15:0 
    //                  cnt_max    cnt 
    //tuple_ram1_rdata  31         62:56            52:48       47:32       
    //                  en         offset_byte      len         step
    reg     [DATA_W-1:0]            tuple_ram0_wdata[5:3]; 
    reg                             tuple_ram0_wen[5:3];
    reg     [REAL_ADDR_W-1:0]       tuple_ram0_waddr[5:3];
    reg     [REAL_ADDR_W-1:0]       tuple_ram0_raddr[2:1];
    reg                             tuple_ram0_ren[2:1];
    wire    [DATA_W-1:0]            tuple_ram0_rdata[1:1];
    reg     [DATA_W-1:0]            tuple_ram0_rdata_d2;
    wire    [DATA_W-1:0]            tuple_ram1_rdata[1:1];
    reg     [DATA_W-1:0]            tuple_ram1_rdata_d2;
    reg                             ren2d_wen3d_conflict_2d;
    reg                             ren2d_wen4d_conflict_2d;
    reg                             ren2d_wen5d_conflict_2d;

    reg     [15:0]                  tuple_cnt_d3;
    reg                             tuple_en_d3;
    reg     [6:0]                   tuple_offset_d3;
    reg     [3:0]                   tuple_mask_d3;
    reg     [15:0]                  tuple_step_d3;


    generate 
        if(RAM_ADDR_W < ADDR_W)begin
            always @(posedge clk) begin
                tuple_ram0_ren[1] <= rtl_ren & (!(|rtl_raddr[ADDR_W-1:RAM_ADDR_W]));
                tuple_ram0_ren[2] <= tuple_ram0_ren[1];
                tuple_ram0_wen[3] <= tuple_ram0_ren[2] | cfg_wen0 ;
                tuple_ram0_wen[4] <= tuple_ram0_wen[3];
                tuple_ram0_wen[5] <= tuple_ram0_wen[4];
            end
        end else begin 
            always @(posedge clk) begin
                tuple_ram0_ren[1] <= rtl_ren;
                tuple_ram0_ren[2] <= tuple_ram0_ren[1];
                tuple_ram0_wen[3] <= tuple_ram0_ren[2] | cfg_wen0;
                tuple_ram0_wen[4] <= tuple_ram0_wen[3];
                tuple_ram0_wen[5] <= tuple_ram0_wen[4];
            end
        end  
    endgenerate

    always @(posedge clk ) begin
        tuple_ram0_raddr[1] <= rtl_raddr;
        tuple_ram0_raddr[2] <= tuple_ram0_raddr[1];
        tuple_ram0_waddr[3] <= cfg_wen0 ? cfg_waddr0 : tuple_ram0_raddr[2];
        tuple_ram0_waddr[4] <= tuple_ram0_waddr[3];
        tuple_ram0_waddr[5] <= tuple_ram0_waddr[4];
    end

    always @(posedge clk ) begin
        if(cfg_wen0)
            tuple_ram0_wdata[3][31:16] <= cfg_wdata0[31:16];
        else 
            tuple_ram0_wdata[3][31:16] <= tuple_ram0_rdata_d2[31:16];

        tuple_ram0_wdata[4][31:16] <= tuple_ram0_wdata[3][31:16];
        tuple_ram0_wdata[5][31:16] <= tuple_ram0_wdata[4][31:16];
    end

    always @(posedge clk ) begin
        tuple_ram0_rdata_d2 <= tuple_ram0_rdata[1];
        tuple_ram1_rdata_d2 <= tuple_ram1_rdata[1];
    end

    always @(posedge clk ) begin
        if (tuple_ram0_ren[1] & tuple_ram0_ren[2] & tuple_ram0_raddr[1]==tuple_ram0_raddr[2]) 
            ren2d_wen3d_conflict_2d <= 1'b1;
        else
            ren2d_wen3d_conflict_2d <= 1'b0;

        if (tuple_ram0_ren[1] & tuple_ram0_wen[3] & tuple_ram0_raddr[1]==tuple_ram0_waddr[3]) 
            ren2d_wen4d_conflict_2d <= 1'b1;
        else
            ren2d_wen4d_conflict_2d <= 1'b0;

        if (tuple_ram0_ren[1] & tuple_ram0_wen[4] & tuple_ram0_raddr[1]==tuple_ram0_waddr[4]) 
            ren2d_wen5d_conflict_2d <= 1'b1;
        else
            ren2d_wen5d_conflict_2d <= 1'b0;
    end

    always @(posedge clk ) begin
        if(cfg_wen0)
            tuple_ram0_wdata[3][15:0] <= cfg_wdata0[15:0];
        else if(ren2d_wen3d_conflict_2d & tuple_ram0_wdata[3][31:16]>(tuple_ram0_wdata[3][15:0]+1'b1))
            tuple_ram0_wdata[3][15:0] <= tuple_ram0_wdata[3][15:0] + 1'b1;
        else if((!ren2d_wen3d_conflict_2d) & ren2d_wen4d_conflict_2d & tuple_ram0_wdata[4][31:16]>(tuple_ram0_wdata[4][15:0]+1'b1))
            tuple_ram0_wdata[3][15:0] <= tuple_ram0_wdata[4][15:0] + 1'b1; 
        else if((!ren2d_wen3d_conflict_2d) & (!ren2d_wen4d_conflict_2d) & ren2d_wen5d_conflict_2d & tuple_ram0_wdata[5][31:16]>(tuple_ram0_wdata[5][15:0]+1'b1))
            tuple_ram0_wdata[3][15:0] <= tuple_ram0_wdata[5][15:0] + 1'b1; 
        else if((!ren2d_wen3d_conflict_2d) & (!ren2d_wen4d_conflict_2d) & (!ren2d_wen5d_conflict_2d) & tuple_ram0_rdata_d2[31:16]>(tuple_ram0_rdata_d2[15:0]+1'b1))
            tuple_ram0_wdata[3][15:0] <= tuple_ram0_rdata_d2[15:0] + 1'b1;
        else 
            tuple_ram0_wdata[3][15:0] <= 16'd0;

        tuple_ram0_wdata[4][15:0] <= tuple_ram0_wdata[3][15:0];
        tuple_ram0_wdata[5][15:0] <= tuple_ram0_wdata[4][15:0];
    end

    always @(posedge clk ) begin
        if(ren2d_wen3d_conflict_2d)
            tuple_cnt_d3 <= tuple_ram0_wdata[3][15:0];
        else if(ren2d_wen4d_conflict_2d)
            tuple_cnt_d3 <= tuple_ram0_wdata[4][15:0];
        else if(ren2d_wen5d_conflict_2d)
            tuple_cnt_d3 <= tuple_ram0_wdata[5][15:0];
        else
            tuple_cnt_d3 <= tuple_ram0_rdata_d2[15:0];
    end

    always @(posedge clk ) begin
        tuple_ram1_rdata_d2 <= tuple_ram1_rdata[1];
        tuple_en_d3         <= tuple_ram1_rdata_d2[31];
        tuple_offset_d3     <= tuple_ram1_rdata_d2[30:24];
        tuple_mask_d3       <= tuple_ram1_rdata_d2[19:16];
        tuple_step_d3       <= tuple_ram1_rdata_d2[15:0];
    end

    always @(posedge clk ) begin
        rtl_rdata[31:00]  <= tuple_cnt_d3 * tuple_step_d3;
        rtl_rdata[43:36]  <= {1'b0,tuple_offset_d3};
        if(tuple_en_d3 & tuple_offset_d3 > 7'd5)
            rtl_rdata[35:32]  <= tuple_mask_d3;
        else  
            rtl_rdata[35:32]  <= 4'd0;
    end
        
    ram #(
        .ram_block_type         ("M20K"                 ),
        .outdata_b_reg          ("UNUSED"               ),
        .widthad_a              (REAL_ADDR_W            ),
        .widthad_b              (REAL_ADDR_W            ),
        .width_a                (DATA_W                 ),
        .width_b                (DATA_W                 )
    )
    u0_add_ram
    (
        .wrclock                (clk                    ),
        .wren                   (tuple_ram0_wen[3]       ),
        .wraddress              (tuple_ram0_waddr[3]     ),
        .data                   (tuple_ram0_wdata[3]     ),
        .rdclock                (clk                    ),
        .rden                   (rtl_ren                ),
        .rdaddress              (rtl_raddr              ),
        .q                      (tuple_ram0_rdata[1]     )
    );

    ram #(
        .ram_block_type         ("M20K"                 ),
        .outdata_b_reg          ("UNUSED"               ),
        .widthad_a              (REAL_ADDR_W            ),
        .widthad_b              (REAL_ADDR_W            ),
        .width_a                (DATA_W                 ),
        .width_b                (DATA_W                 )
    )
    u0_status_ram
    (
        .wrclock                (clk                    ),
        .wren                   (cfg_wen1               ),
        .wraddress              (cfg_waddr1             ),
        .data                   (cfg_wdata1             ),
        .rdclock                (clk                    ),
        .rden                   (rtl_ren                ),
        .rdaddress              (rtl_raddr              ),
        .q                      (tuple_ram1_rdata[1]     )
    );

endmodule
