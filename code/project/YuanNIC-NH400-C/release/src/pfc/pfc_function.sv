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
module pfc_function #(
    parameter                               DATA_W      = 1024,
    parameter                               KEEP_W      = $clog2(DATA_W/8)
)(    
    input                                   clk,
    input                                   rst_n,
    input           [8:0]                   rx_pfc,
    input                                   s_axis_rx_tvalid    ,
    input           [DATA_W-1:0]            s_axis_rx_tdata     ,
    input           [KEEP_W-1:0]            s_axis_rx_tkeep     ,
    input                                   s_axis_rx_tlast     ,
    input           [2:0]                   s_axis_rx_Priority  ,
    output                                  s_axis_rx_ready     ,

    output  reg                             m_axis_rx_tvalid    ,
    output  reg     [DATA_W-1:0]            m_axis_rx_tdata     ,
    output  reg     [KEEP_W-1:0]            m_axis_rx_tkeep     ,
    output  reg                             m_axis_rx_tlast     ,
    input                                   m_axis_rx_tready    ,
    input                                   statis_cnt_clear_en ,
    output          [8*32-1:0]              pfc_pkt_drop_cnt    ,
    output          [8*32-1:0]              pfc_pkt_in_cnt      ,
    output          [8*32-1:0]              pfc_pkt_out_cnt      
);
    localparam                              PRIORITY_NUM = 8;

    reg                                     s_axis_rx_sop_1d     ;
    reg                                     s_axis_rx_tvalid_1d  ;
    reg             [DATA_W-1:0]            s_axis_rx_tdata_1d   ;
    reg             [KEEP_W-1:0]            s_axis_rx_tkeep_1d   ;
    reg                                     s_axis_rx_tlast_1d   ;
    reg             [2:0]                   s_axis_rx_Priority_1d;
    reg             [7:0]                   user_out_select;

    reg                                     user_in_tvalid[PRIORITY_NUM-1:0];
    reg             [DATA_W-1:0]            user_in_tdata [PRIORITY_NUM-1:0];
    reg             [KEEP_W-1:0]            user_in_tkeep [PRIORITY_NUM-1:0];
    reg                                     user_in_tlast [PRIORITY_NUM-1:0];
    reg                                     user_in_tdrop [PRIORITY_NUM-1:0];
    wire                                    user_in_tpfull[PRIORITY_NUM-1:0];
    wire                                    user_in_tready[PRIORITY_NUM-1:0];

    reg                                     user_out_tsop  [PRIORITY_NUM-1:0];
    reg                                     user_out_tvalid[PRIORITY_NUM-1:0];
    reg             [DATA_W-1:0]            user_out_tdata [PRIORITY_NUM-1:0];
    reg             [KEEP_W-1:0]            user_out_tkeep [PRIORITY_NUM-1:0];
    reg                                     user_out_tlast [PRIORITY_NUM-1:0];
    wire                                    user_out_tready[PRIORITY_NUM-1:0];
    wire                                    user_out_pempty[PRIORITY_NUM-1:0];
    //debug 
    reg             [7:0]                   pfc_pkt_drop_vld;
    reg             [7:0]                   pfc_cs_in_vld;
    reg             [7:0]                   pfc_cs_out_vld;
    wire            [31:0]                  wire_pfc_pkt_drop_cnt[7:0];
    wire            [31:0]                  wire_pfc_pkt_in_cnt  [7:0];
    wire            [31:0]                  wire_pfc_pkt_out_cnt [7:0];

    assign s_axis_rx_ready =    (s_axis_rx_Priority_1d==3'd0) ? user_in_tready[0] | rx_pfc[8] | rx_pfc[0] :
                                (s_axis_rx_Priority_1d==3'd1) ? user_in_tready[1] | rx_pfc[8] | rx_pfc[1] :
                                (s_axis_rx_Priority_1d==3'd2) ? user_in_tready[2] | rx_pfc[8] | rx_pfc[2] :
                                (s_axis_rx_Priority_1d==3'd3) ? user_in_tready[3] | rx_pfc[8] | rx_pfc[3] :
                                (s_axis_rx_Priority_1d==3'd4) ? user_in_tready[4] | rx_pfc[8] | rx_pfc[4] :
                                (s_axis_rx_Priority_1d==3'd5) ? user_in_tready[5] | rx_pfc[8] | rx_pfc[5] :
                                (s_axis_rx_Priority_1d==3'd6) ? user_in_tready[6] | rx_pfc[8] | rx_pfc[6] : user_in_tready[7] | rx_pfc[8] | rx_pfc[7] ;

    always @(posedge clk ) begin
        if(s_axis_rx_ready)begin 
            s_axis_rx_tvalid_1d   <= s_axis_rx_tvalid  ;
            s_axis_rx_tdata_1d    <= s_axis_rx_tdata   ;
            s_axis_rx_tkeep_1d    <= s_axis_rx_tkeep   ;
            s_axis_rx_tlast_1d    <= s_axis_rx_tlast   ;
            s_axis_rx_Priority_1d <= s_axis_rx_Priority;
        end
    end

    always @(posedge clk ) begin
        if(!rst_n)
            s_axis_rx_sop_1d <= 1'b1;
        else if(s_axis_rx_ready & s_axis_rx_tvalid_1d & s_axis_rx_tlast_1d)
            s_axis_rx_sop_1d <= 1'b1;
        else if(s_axis_rx_ready & s_axis_rx_tvalid_1d)
            s_axis_rx_sop_1d <= 1'b0;
    end

    generate
        for (genvar i=0 ; i<PRIORITY_NUM ; i=i+1) begin
            always @(posedge clk ) begin
                if(!rst_n)
                    user_in_tvalid[i] <= 1'b0;
                else if(s_axis_rx_tvalid_1d & s_axis_rx_sop_1d & s_axis_rx_Priority_1d==i & (!user_in_tpfull[i]) & (rx_pfc[8] | rx_pfc[i])) 
                    user_in_tvalid[i] <= 1'b1;
                else if(s_axis_rx_tvalid_1d & s_axis_rx_sop_1d & s_axis_rx_Priority_1d==i & user_in_tready[i] & (!rx_pfc[8]) & (!rx_pfc[i]))
                    user_in_tvalid[i] <= 1'b1;
                else if(user_in_tvalid[i] & user_in_tlast[i] & user_in_tready[i])
                    user_in_tvalid[i] <= 1'b0;
            end

            always @(posedge clk ) begin
                if(s_axis_rx_Priority_1d==i & user_in_tready[i])begin 
                    user_in_tdata[i] <= s_axis_rx_tdata_1d;
                    user_in_tkeep[i] <= s_axis_rx_tkeep_1d;
                    user_in_tlast[i] <= s_axis_rx_tlast_1d;
                end 
            end

            axis_fifo #(
                .CLOCKING_MODE              ("SCFIFO"               ),
                .FIFO_TYPE                  ("M20K"                 ),
                .PACKET_FIFO                ("FALSE"                ),
                .FIFO_DEPTH                 (2048                   ),
                .TDATA_WIDTH                (DATA_W                 ),
                .TUSER_WIDTH                (0                      ),
                .ALMOST_EMPTY               (4                      ),
                .ALMOST_AFULL               (2000                   ),
                .DROP_EN                    (0                      ),//不等于0 表示：PACKET_FIFO="true"时s_axis_drop会置1，置1时fifo满时会自动丢包 
                                                                      //等于0 表示：s_axis_drop不会置1，一直为0，fifo满时向后反压
                .KEEP_EN                    ("OFF"                  )//"ON"时 keep有效，off时emty有效
            )axis_fifo_u(   
                .s_axis_tvalid              (user_in_tvalid[i]      ),
                .s_axis_tready              (user_in_tready[i]      ),
                .s_axis_tdata               (user_in_tdata [i]      ),
                .s_axis_temty               (user_in_tkeep [i]      ),
                .s_axis_tkeep               (                       ),
                .s_axis_tlast               (user_in_tlast [i]      ),
                .s_axis_tuser               (                       ),
                .s_axis_pfull               (user_in_tpfull[i]      ),
                .s_axis_drop                (1'b0                   ),
                .m_axis_tvalid              (user_out_tvalid[i]     ),
                .m_axis_tready              (user_out_tready[i]     ),
                .m_axis_tdata               (user_out_tdata [i]     ),
                .m_axis_temty               (user_out_tkeep [i]     ),
                .m_axis_tkeep               (                       ),
                .m_axis_tlast               (user_out_tlast [i]     ),
                .m_axis_tuser               (                       ),
                .ram_full                   (                       ),
                .ram_empty                  (                       ),
                .eop_empty                  (                       ),
                .eop_pempty                 (user_out_pempty[i]     ),
                .s_aresetn                  (rst_n                  ),
                .s_clk                      (clk                    ),
                .m_clk                      (clk                    )
            );  

            always @(posedge clk ) begin
                if(!rst_n)
                    user_out_tsop[i] <= 1'b1;
                else if(user_out_tvalid[i] & user_out_tready[i] & user_out_tlast[i])
                    user_out_tsop[i] <= 1'b1;
                else if(user_out_tvalid[i] & user_out_tready[i])
                    user_out_tsop[i] <= 1'b0;
            end

            assign user_out_tready[i] = user_out_select[i] & m_axis_rx_tready;

        end
    endgenerate

    // ---------------------------------------------------------------- 选择优先级的共享项
    // 原实现每支把「(!rx_pfc[8]) & (!rx_pfc[j]) & cur_valid & cur_ready & cur_last &
    // cand_valid[j] & cand_tsop[j]」整串写一遍：8 支 × 最多 8 条 = 64 个 7 输入长 AND 全进同一个
    // case，415 MHz（周期 2.409 ns）下 slack -0.018，端点 user_out_select[i]~RTM。
    // 拆成三个与支号无关的共享向量后，每支只剩 2 输入 AND。
    // 等价性依据：case 选中第 i 支时 select[i]==1，故 user_out_tready[i] == m_axis_rx_tready，
    // 可以提到支外算；其余各项本就与支号无关。
    wire [7:0] sel_last_done;   // 本 lane 末拍握手完成（tready 已按 select 已知反量化简）
    wire [7:0] cand_ok;         // 候选 lane 可以起新帧（PFC 未暂停 + valid + SOP）
    wire [7:0] stay_ok;         // 本 lane 还有后续拍可继续占用
    genvar gsel;
    generate
        for (gsel = 0; gsel < PRIORITY_NUM; gsel = gsel + 1) begin : gen_sel_terms
            assign sel_last_done[gsel] = user_out_tvalid[gsel] & user_out_tlast[gsel] & m_axis_rx_tready;
            assign cand_ok[gsel]   = (!rx_pfc[8]) & (!rx_pfc[gsel]) & user_out_tvalid[gsel] & user_out_tsop[gsel];
            assign stay_ok[gsel]   = (!rx_pfc[8]) & (!rx_pfc[gsel]) & (!user_out_pempty[gsel]);
        end
    endgenerate

    always @(posedge clk ) begin
        if(!rst_n)
            user_out_select <= 8'h00;
        else
            // 选中第 i 支时 user_out_select[i] 恒为 1，故支内 user_out_tready[i] == m_axis_rx_tready。
            // 据此把每支那串 7 项 AND 拆成三个与支号无关的共享向量（见 gen_sel_terms），
            // 每支就只剩 2 输入 AND + 8:1 优先选择。
            // 标签是 one-hot：8'h00=空闲，8'h01=lane0、8'h02=lane1 … 8'h80=lane7。
            case (user_out_select)
                8'h00:
                    if     (cand_ok[7]) user_out_select <= 8'h80;
                    else if(cand_ok[6]) user_out_select <= 8'h40;
                    else if(cand_ok[5]) user_out_select <= 8'h20;
                    else if(cand_ok[4]) user_out_select <= 8'h10;
                    else if(cand_ok[3]) user_out_select <= 8'h08;
                    else if(cand_ok[2]) user_out_select <= 8'h04;
                    else if(cand_ok[1]) user_out_select <= 8'h02;
                    else if(cand_ok[0]) user_out_select <= 8'h01;
                    else                 user_out_select <= 8'h00;
                8'h01:
                    if     (sel_last_done[0] & cand_ok[7]) user_out_select <= 8'h80;
                    else if(sel_last_done[0] & cand_ok[6]) user_out_select <= 8'h40;
                    else if(sel_last_done[0] & cand_ok[5]) user_out_select <= 8'h20;
                    else if(sel_last_done[0] & cand_ok[4]) user_out_select <= 8'h10;
                    else if(sel_last_done[0] & cand_ok[3]) user_out_select <= 8'h08;
                    else if(sel_last_done[0] & cand_ok[2]) user_out_select <= 8'h04;
                    else if(sel_last_done[0] & cand_ok[1]) user_out_select <= 8'h02;
                    else if(sel_last_done[0] & stay_ok[0]) user_out_select <= 8'h01;
                    else if(sel_last_done[0])               user_out_select <= 8'h00;
                8'h02:
                    if     (sel_last_done[1] & cand_ok[0]) user_out_select <= 8'h01;
                    else if(sel_last_done[1] & cand_ok[7]) user_out_select <= 8'h80;
                    else if(sel_last_done[1] & cand_ok[6]) user_out_select <= 8'h40;
                    else if(sel_last_done[1] & cand_ok[5]) user_out_select <= 8'h20;
                    else if(sel_last_done[1] & cand_ok[4]) user_out_select <= 8'h10;
                    else if(sel_last_done[1] & cand_ok[3]) user_out_select <= 8'h08;
                    else if(sel_last_done[1] & cand_ok[2]) user_out_select <= 8'h04;
                    else if(sel_last_done[1] & stay_ok[1]) user_out_select <= 8'h02;
                    else if(sel_last_done[1])               user_out_select <= 8'h00;
                8'h04:
                    if     (sel_last_done[2] & cand_ok[1]) user_out_select <= 8'h02;
                    else if(sel_last_done[2] & cand_ok[0]) user_out_select <= 8'h01;
                    else if(sel_last_done[2] & cand_ok[7]) user_out_select <= 8'h80;
                    else if(sel_last_done[2] & cand_ok[6]) user_out_select <= 8'h40;
                    else if(sel_last_done[2] & cand_ok[5]) user_out_select <= 8'h20;
                    else if(sel_last_done[2] & cand_ok[4]) user_out_select <= 8'h10;
                    else if(sel_last_done[2] & cand_ok[3]) user_out_select <= 8'h08;
                    else if(sel_last_done[2] & stay_ok[2]) user_out_select <= 8'h04;
                    else if(sel_last_done[2])               user_out_select <= 8'h00;
                8'h08:
                    if     (sel_last_done[3] & cand_ok[2]) user_out_select <= 8'h04;
                    else if(sel_last_done[3] & cand_ok[1]) user_out_select <= 8'h02;
                    else if(sel_last_done[3] & cand_ok[0]) user_out_select <= 8'h01;
                    else if(sel_last_done[3] & cand_ok[7]) user_out_select <= 8'h80;
                    else if(sel_last_done[3] & cand_ok[6]) user_out_select <= 8'h40;
                    else if(sel_last_done[3] & cand_ok[5]) user_out_select <= 8'h20;
                    else if(sel_last_done[3] & cand_ok[4]) user_out_select <= 8'h10;
                    else if(sel_last_done[3] & stay_ok[3]) user_out_select <= 8'h08;
                    else if(sel_last_done[3])               user_out_select <= 8'h00;
                8'h10:
                    if     (sel_last_done[4] & cand_ok[3]) user_out_select <= 8'h08;
                    else if(sel_last_done[4] & cand_ok[2]) user_out_select <= 8'h04;
                    else if(sel_last_done[4] & cand_ok[1]) user_out_select <= 8'h02;
                    else if(sel_last_done[4] & cand_ok[0]) user_out_select <= 8'h01;
                    else if(sel_last_done[4] & cand_ok[7]) user_out_select <= 8'h80;
                    else if(sel_last_done[4] & cand_ok[6]) user_out_select <= 8'h40;
                    else if(sel_last_done[4] & cand_ok[5]) user_out_select <= 8'h20;
                    else if(sel_last_done[4] & stay_ok[4]) user_out_select <= 8'h10;
                    else if(sel_last_done[4])               user_out_select <= 8'h00;
                8'h20:
                    if     (sel_last_done[5] & cand_ok[4]) user_out_select <= 8'h10;
                    else if(sel_last_done[5] & cand_ok[3]) user_out_select <= 8'h08;
                    else if(sel_last_done[5] & cand_ok[2]) user_out_select <= 8'h04;
                    else if(sel_last_done[5] & cand_ok[1]) user_out_select <= 8'h02;
                    else if(sel_last_done[5] & cand_ok[0]) user_out_select <= 8'h01;
                    else if(sel_last_done[5] & cand_ok[7]) user_out_select <= 8'h80;
                    else if(sel_last_done[5] & cand_ok[6]) user_out_select <= 8'h40;
                    else if(sel_last_done[5] & stay_ok[5]) user_out_select <= 8'h20;
                    else if(sel_last_done[5])               user_out_select <= 8'h00;
                8'h40:
                    if     (sel_last_done[6] & cand_ok[5]) user_out_select <= 8'h20;
                    else if(sel_last_done[6] & cand_ok[4]) user_out_select <= 8'h10;
                    else if(sel_last_done[6] & cand_ok[3]) user_out_select <= 8'h08;
                    else if(sel_last_done[6] & cand_ok[2]) user_out_select <= 8'h04;
                    else if(sel_last_done[6] & cand_ok[1]) user_out_select <= 8'h02;
                    else if(sel_last_done[6] & cand_ok[0]) user_out_select <= 8'h01;
                    else if(sel_last_done[6] & cand_ok[7]) user_out_select <= 8'h80;
                    else if(sel_last_done[6] & stay_ok[6]) user_out_select <= 8'h40;
                    else if(sel_last_done[6])               user_out_select <= 8'h00;
                8'h80:
                    if     (sel_last_done[7] & cand_ok[6]) user_out_select <= 8'h40;
                    else if(sel_last_done[7] & cand_ok[5]) user_out_select <= 8'h20;
                    else if(sel_last_done[7] & cand_ok[4]) user_out_select <= 8'h10;
                    else if(sel_last_done[7] & cand_ok[3]) user_out_select <= 8'h08;
                    else if(sel_last_done[7] & cand_ok[2]) user_out_select <= 8'h04;
                    else if(sel_last_done[7] & cand_ok[1]) user_out_select <= 8'h02;
                    else if(sel_last_done[7] & cand_ok[0]) user_out_select <= 8'h01;
                    else if(sel_last_done[7] & stay_ok[7]) user_out_select <= 8'h80;
                    else if(sel_last_done[7])               user_out_select <= 8'h00;
                default: user_out_select <= 8'h00;
            endcase
    end

    always @(posedge clk ) begin
        if(!rst_n)
            m_axis_rx_tvalid <= 1'b0;
        else if(user_out_tvalid[0] & user_out_tready[0] & user_out_tsop[0])
            m_axis_rx_tvalid <= 1'b1;
        else if(user_out_tvalid[1] & user_out_tready[1] & user_out_tsop[1])
            m_axis_rx_tvalid <= 1'b1;
        else if(user_out_tvalid[2] & user_out_tready[2] & user_out_tsop[2])
            m_axis_rx_tvalid <= 1'b1;
        else if(user_out_tvalid[3] & user_out_tready[3] & user_out_tsop[3])
            m_axis_rx_tvalid <= 1'b1;
        else if(user_out_tvalid[4] & user_out_tready[4] & user_out_tsop[4])
            m_axis_rx_tvalid <= 1'b1;
        else if(user_out_tvalid[5] & user_out_tready[5] & user_out_tsop[5])
            m_axis_rx_tvalid <= 1'b1;
        else if(user_out_tvalid[6] & user_out_tready[6] & user_out_tsop[6])
            m_axis_rx_tvalid <= 1'b1;
        else if(user_out_tvalid[7] & user_out_tready[7] & user_out_tsop[7])
            m_axis_rx_tvalid <= 1'b1;
        else if(m_axis_rx_tvalid & m_axis_rx_tready & m_axis_rx_tlast)
            m_axis_rx_tvalid <= 1'b0;
    end

    always @(posedge clk ) begin
        if(user_out_tvalid[0] & user_out_tready[0])begin 
            m_axis_rx_tdata <= user_out_tdata[0];
            m_axis_rx_tkeep <= user_out_tkeep[0];
            m_axis_rx_tlast <= user_out_tlast[0];
        end else if(user_out_tvalid[1] & user_out_tready[1])begin 
            m_axis_rx_tdata <= user_out_tdata[1];
            m_axis_rx_tkeep <= user_out_tkeep[1];
            m_axis_rx_tlast <= user_out_tlast[1];
        end else if(user_out_tvalid[2] & user_out_tready[2])begin 
            m_axis_rx_tdata <= user_out_tdata[2];
            m_axis_rx_tkeep <= user_out_tkeep[2];
            m_axis_rx_tlast <= user_out_tlast[2];
        end else if(user_out_tvalid[3] & user_out_tready[3])begin 
            m_axis_rx_tdata <= user_out_tdata[3];
            m_axis_rx_tkeep <= user_out_tkeep[3];
            m_axis_rx_tlast <= user_out_tlast[3];
        end else if(user_out_tvalid[4] & user_out_tready[4])begin 
            m_axis_rx_tdata <= user_out_tdata[4];
            m_axis_rx_tkeep <= user_out_tkeep[4];
            m_axis_rx_tlast <= user_out_tlast[4];
        end else if(user_out_tvalid[5] & user_out_tready[5])begin 
            m_axis_rx_tdata <= user_out_tdata[5];
            m_axis_rx_tkeep <= user_out_tkeep[5];
            m_axis_rx_tlast <= user_out_tlast[5];
        end else if(user_out_tvalid[6] & user_out_tready[6])begin 
            m_axis_rx_tdata <= user_out_tdata[6];
            m_axis_rx_tkeep <= user_out_tkeep[6];
            m_axis_rx_tlast <= user_out_tlast[6];
        end else if(user_out_tvalid[7] & user_out_tready[7])begin 
            m_axis_rx_tdata <= user_out_tdata[7];
            m_axis_rx_tkeep <= user_out_tkeep[7];
            m_axis_rx_tlast <= user_out_tlast[7];
        end
    end
    //debug 
    generate
        for (genvar i=0 ; i<PRIORITY_NUM ; i=i+1) begin
            always @(posedge clk ) begin
                pfc_pkt_drop_vld[i] <= s_axis_rx_tvalid_1d & s_axis_rx_sop_1d  & user_in_tpfull [i] & s_axis_rx_Priority_1d==i & (rx_pfc[8] | rx_pfc[i]);
                pfc_cs_in_vld   [i] <= user_in_tvalid [i]  & user_in_tlast [i] & user_in_tready [i]                           ;
                pfc_cs_out_vld  [i] <= user_out_tvalid[i]  & user_out_tlast[i] & user_out_tready[i]                           ;
            end

            cnt#(.WIDTH(32))cnt_u0(.clear(statis_cnt_clear_en),.clk(clk),.vld(pfc_pkt_drop_vld[i]),.step({15'b0,1'b1}),.cnt(wire_pfc_pkt_drop_cnt[i]));
            cnt#(.WIDTH(32))cnt_u1(.clear(statis_cnt_clear_en),.clk(clk),.vld(pfc_cs_in_vld   [i]),.step({15'b0,1'b1}),.cnt(wire_pfc_pkt_in_cnt  [i]));
            cnt#(.WIDTH(32))cnt_u2(.clear(statis_cnt_clear_en),.clk(clk),.vld(pfc_cs_out_vld  [i]),.step({15'b0,1'b1}),.cnt(wire_pfc_pkt_out_cnt [i]));

            assign pfc_pkt_drop_cnt[i*32+:32] = wire_pfc_pkt_drop_cnt[i];
            assign pfc_pkt_in_cnt  [i*32+:32] = wire_pfc_pkt_in_cnt  [i];
            assign pfc_pkt_out_cnt [i*32+:32] = wire_pfc_pkt_out_cnt [i];
        end
    endgenerate

endmodule
