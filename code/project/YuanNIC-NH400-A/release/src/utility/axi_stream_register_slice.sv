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
// This module delays the input stream for a single cycle.  It provides two
// working mode: fully-registered mode and forward-only mode, specified using
// the mode string "full" and "forward" respectively.
//
// The fully-registered mode completely isolates the slave and master interface
// from a timing perspective.  It uses two sets of registers, one of which
// buffers data when back-pressure happens.  All the output signals are driven
// by flip-flops.
//
// The forward-only mode uses only one set of registers.  Its `s_axis_tready` is
// driven by combinational logic derived from `m_axis_tready` and internal
// state.  This mode makes it more likely to create a long, timing-critical,
// combinational path on `m_axis_tready`.  Hence, it probably should be used in
// regions with relaxed slack, or in the case that a single cycle delay is
// needed for synchronization purpose.
`timescale 1ns/1ps
module axi_stream_register_slice #(
  parameter int TDATA_W = 1024,
  parameter int TKEEP_W = (TDATA_W/8),
  parameter int TID_W   = 8,
  parameter int TDEST_W = 4,
  parameter int TUSER_W = 8,
  parameter     MODE    = "full"
) (
  input                    s_axis_tvalid,
  input      [TDATA_W-1:0] s_axis_tdata,
  input      [TKEEP_W-1:0] s_axis_tkeep,
  input                    s_axis_tlast,
  input        [TID_W-1:0] s_axis_tid,
  input      [TDEST_W-1:0] s_axis_tdest,
  input      [TUSER_W-1:0] s_axis_tuser,
  output                   s_axis_tready,

  output                   m_axis_tvalid,
  output     [TDATA_W-1:0] m_axis_tdata,
  output     [TKEEP_W-1:0] m_axis_tkeep,
  output                   m_axis_tlast,
  output       [TID_W-1:0] m_axis_tid,
  output     [TDEST_W-1:0] m_axis_tdest,
  output     [TUSER_W-1:0] m_axis_tuser,
  input                    m_axis_tready,

  input                    aclk,
  input                    aresetn
);

  // Parameter DRC
  initial begin
    if (MODE != "full" && MODE != "forward") begin
      $fatal("[%m] Unknown mode %s", MODE);
    end
  end

  // B6419：数据寄存器一律不挂复位，只复位 filled。
  // B6418 pld_clkout 里 mac_rstn_u（YuanRDMA.v:722）的一位复位寄存器扇出到 u21 / u82 /
  // u_axis_keep_pack 两个 slice 的每一位 tdata 的 sclr，共 543 个违例端点（最差 −0.178，1 级逻辑、走线 1.68 ns）。
  // tdata/tkeep/... 只在 filled 为 1 时才被下游采用，复位值没有意义。
  // 同时把数据使能化简成只依赖寄存器 + m_axis_tready 一级（与 roce/roce_skid.sv 同构）：
  //   full 模式：stage0 在「空或本拍被取走」时装载（源 = filled[1] ? stage1 : s_axis）；
  //              stage1 在「空」时每拍跟随 s_axis，进入 2'b11 那一拍装进来的正是被反压的那一拍。
  //   forward 模式：数据在「s_axis_tready 为 1」时装载（= ~filled || m_axis_tready）。
  // 与原写法逐状态等价（filled 的状态机一字未改；原写法里不装载的分支，新写法装载的都是 filled=0 的无效槽）。
  generate if (MODE == "forward") begin: forward_mode
    reg     [TDATA_W-1:0] axis_tdata;
    reg     [TKEEP_W-1:0] axis_tkeep;
    reg                   axis_tlast;
    reg     [TUSER_W-1:0] axis_tuser;
    reg       [TID_W-1:0] axis_tid;
    reg     [TDEST_W-1:0] axis_tdest;

    reg                   filled;

    assign s_axis_tready = ~filled || m_axis_tready;
    assign m_axis_tvalid = filled;
    assign m_axis_tdata  = axis_tdata;
    assign m_axis_tkeep  = axis_tkeep;
    assign m_axis_tlast  = axis_tlast;
    assign m_axis_tuser  = axis_tuser;
    assign m_axis_tid    = axis_tid;
    assign m_axis_tdest  = axis_tdest;

    always @(posedge aclk) begin
      if (~aresetn) begin
        filled <= 1'b0;
      end
      else begin
        case (filled)
          1'b0: if (s_axis_tvalid) filled <= 1'b1;
          1'b1: if (~s_axis_tvalid && m_axis_tready) filled <= 1'b0;
        endcase
      end
    end

    // 原写法：filled=0 且 s_valid 装载；filled=1 且 s_valid && m_ready 装载。
    // 新写法在 (~filled || m_ready) 时总是装载：多装的情形都是 s_valid=0，此时 filled 下一拍为 0，数据无效。
    always @(posedge aclk) begin
      if (~filled || m_axis_tready) begin
        axis_tdata <= s_axis_tdata;
        axis_tkeep <= s_axis_tkeep;
        axis_tlast <= s_axis_tlast;
        axis_tuser <= s_axis_tuser;
        axis_tid   <= s_axis_tid;
        axis_tdest <= s_axis_tdest;
      end
    end
  end: forward_mode
  else begin: full_mode
    reg     [TDATA_W-1:0] axis_tdata[0:1];
    reg     [TKEEP_W-1:0] axis_tkeep[0:1];
    reg                   axis_tlast[0:1];
    reg     [TUSER_W-1:0] axis_tuser[0:1];
    reg       [TID_W-1:0] axis_tid[0:1];
    reg     [TDEST_W-1:0] axis_tdest[0:1];

    reg             [1:0] filled;
    
    assign s_axis_tready = ~filled[1];
    assign m_axis_tvalid = filled[0];
    assign m_axis_tdata  = axis_tdata[0];
    assign m_axis_tkeep  = axis_tkeep[0];
    assign m_axis_tlast  = axis_tlast[0];
    assign m_axis_tuser  = axis_tuser[0];
    assign m_axis_tid    = axis_tid[0];
    assign m_axis_tdest  = axis_tdest[0];

    // filled 状态机与原版逐字相同
    always @(posedge aclk) begin
      if (~aresetn) begin
        filled <= 2'b00;
      end
      else begin
        case (filled)
          2'b00: if (s_axis_tvalid) filled <= 2'b01;
          2'b01: begin
            if (s_axis_tvalid && ~m_axis_tready)       filled <= 2'b11;
            else if (~s_axis_tvalid && m_axis_tready)  filled <= 2'b00;
          end
          2'b11: if (m_axis_tready) filled <= 2'b01;
          default: filled <= 2'b00;
        endcase
      end
    end

    // stage0：空（filled[0]=0）或本拍被取走时装载；有 stage1 就取 stage1，否则取入口。
    //   00：装入口（原写法只在 s_valid 时装；s_valid=0 时 filled 保持 00，装进来的是无效槽）
    //   01 且 m_ready：装入口（s_valid=0 时 filled→00，同上）
    //   11 且 m_ready：装 stage1
    always @(posedge aclk) begin
      if (~filled[0] || m_axis_tready) begin
        axis_tdata[0] <= filled[1] ? axis_tdata[1] : s_axis_tdata;
        axis_tkeep[0] <= filled[1] ? axis_tkeep[1] : s_axis_tkeep;
        axis_tlast[0] <= filled[1] ? axis_tlast[1] : s_axis_tlast;
        axis_tuser[0] <= filled[1] ? axis_tuser[1] : s_axis_tuser;
        axis_tid[0]   <= filled[1] ? axis_tid[1]   : s_axis_tid;
        axis_tdest[0] <= filled[1] ? axis_tdest[1] : s_axis_tdest;
      end
    end

    // stage1：空（filled[1]=0）时每拍跟随入口；01→11 的那一拍装进来的就是被反压的那一拍，之后保持。
    always @(posedge aclk) begin
      if (~filled[1]) begin
        axis_tdata[1] <= s_axis_tdata;
        axis_tkeep[1] <= s_axis_tkeep;
        axis_tlast[1] <= s_axis_tlast;
        axis_tuser[1] <= s_axis_tuser;
        axis_tid[1]   <= s_axis_tid;
        axis_tdest[1] <= s_axis_tdest;
      end
    end
  end
  endgenerate

endmodule: axi_stream_register_slice
