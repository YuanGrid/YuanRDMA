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
module qdma_function#(
    parameter   int FUNC_ID             = 0
)
(
    input   wire    [27:0]              s_avm_addr ,
    input   wire                        s_avm_read ,
    input   wire                        s_avm_write,
    input   wire    [31:0]              s_avm_wdat ,
    output  wire                        s_avm_wait ,
    output  wire    [31:0]              s_avm_rdat ,
    output  wire                        s_avm_rvld ,
    output  wire    [1:0]               s_avm_rspo ,
    output  wire                        s_avm_wrsp ,
    input                               s_axis_h2c_tvalid,
    input           [511:0]             s_axis_h2c_tdata,
    input           [5:0]               s_axis_h2c_temty,
    input                               s_axis_h2c_tlast,
    input           [10:0]              s_axis_h2c_tuser_qid,
    output                              s_axis_h2c_tready,
    output                              m_axis_h2c_tvalid,
    output          [511:0]             m_axis_h2c_tdata,
    output          [5:0]               m_axis_h2c_tkeep,
    output                              m_axis_h2c_tlast,
    input                               m_axis_h2c_tready,
    input                               s_axis_c2h_tvalid,
    input           [511:0]             s_axis_c2h_tdata,
    input           [5:0]               s_axis_c2h_tkeep,
    input                               s_axis_c2h_tlast,
    output                              s_axis_c2h_tready,
    output  reg                         m_axis_c2h_tvalid,
    output  reg     [511:0]             m_axis_c2h_tdata,
    output  reg                         m_axis_c2h_tlast,
    output  reg     [5:0]               m_axis_c2h_tkeep,
    output  reg     [10:0]              m_axis_c2h_tuser_qid,
    input                               m_axis_c2h_tready,
    input           [10:0]              arp_icmp_qid,
    input                               dma_clk ,
    input                               axil_aclk,
    input                               axis_aclk,
    input                               dma_rstn,
    input                               axil_aresetn
);

    localparam C_PKT_FIFO_DEPTH = 512;
    localparam C_QID_FIFO_DEPTH = C_PKT_FIFO_DEPTH; 
    wire    [15:0]                      q_base;
    wire    [15:0]                      num_q;
    wire    [2047:0]                    indir_table;
    wire    [319:0]                     hash_key;
    reg                                 h2c_started;
    reg                                 h2c_matched;
    wire                                h2c_q_in_range;
    wire                                h2c_match;
    wire                                hash_result_valid;
    wire    [31:0]                      hash_result;
    reg                                 hash_result_valid_d1;
    reg     [15:0]                      hash_result_d1;
    wire                                arp_icmp_flag;
    reg                                 qid_fifo_wr_en;
    reg     [10:0]                      qid_fifo_din;
    wire                                qid_fifo_rd_en;
    wire    [10:0]                      qid_fifo_dout;
    wire                                qid_fifo_empty;
    wire                                qid_fifo_full;
    reg                                 axis_c2h_buf_sop;
    wire                                axis_c2h_buf_tvalid;
    wire    [511:0]                     axis_c2h_buf_tdata;
    wire                                axis_c2h_buf_tlast;
    wire    [5:0]                       axis_c2h_buf_tkeep;
    wire                                axis_c2h_buf_tready;

    always @(posedge axis_aclk) begin
        if (~dma_rstn)
            h2c_started <= 1'b0;
        else if (~h2c_started && s_axis_h2c_tvalid && s_axis_h2c_tready)
            h2c_started <= ~s_axis_h2c_tlast;
        else if (s_axis_h2c_tvalid && s_axis_h2c_tlast && s_axis_h2c_tready)
            h2c_started <= 1'b0;
    end

    always @(posedge axis_aclk) begin
        if (~dma_rstn) begin
            h2c_matched <= 1'b0;
        end else if (~h2c_matched && s_axis_h2c_tvalid && ~s_axis_h2c_tlast && s_axis_h2c_tready) begin
            h2c_matched <= h2c_q_in_range;
        end else if (h2c_matched && s_axis_h2c_tvalid && s_axis_h2c_tlast && s_axis_h2c_tready) begin
            h2c_matched <= 1'b0;
        end
    end

    assign h2c_q_in_range = (s_axis_h2c_tuser_qid >= q_base) &&
                            (s_axis_h2c_tuser_qid < (q_base + num_q));
    assign h2c_match      = (~h2c_started && s_axis_h2c_tvalid && h2c_q_in_range) ||
                            (h2c_started && h2c_matched);

    assign m_axis_h2c_tvalid     = s_axis_h2c_tvalid;//&& h2c_match;
    assign m_axis_h2c_tdata      = s_axis_h2c_tdata;
    assign m_axis_h2c_tlast      = s_axis_h2c_tlast;
    assign s_axis_h2c_tready     = m_axis_h2c_tready;// && h2c_match;
    assign m_axis_h2c_tkeep      = s_axis_h2c_temty;

    assign m_axis_h2c_tuser_src = 16'h1 << FUNC_ID;
    assign m_axis_h2c_tuser_dst = 0;

    always @(posedge axis_aclk ) begin
        hash_result_valid_d1 <= hash_result_valid;
        hash_result_d1       <= indir_table[16*hash_result[6:0]+:16];
    end

    always @(posedge axis_aclk) begin
        if (~dma_rstn) begin
            qid_fifo_wr_en <= 1'b0;
            qid_fifo_din   <= 0;
        end else if (hash_result_valid_d1) begin
            qid_fifo_wr_en <= 1'b1;
            qid_fifo_din   <= hash_result_d1 ;//+ q_base ;//indir_table[16*hash_result[6:0]+:16] + q_base;
        end else begin
            qid_fifo_wr_en <= 1'b0;
        end
    end

    always @(posedge axis_aclk ) begin
        if(~dma_rstn)
            axis_c2h_buf_sop <= 1'b1;
        else if(axis_c2h_buf_tvalid && axis_c2h_buf_tlast && axis_c2h_buf_tready)
            axis_c2h_buf_sop <= 1'b1;
        else if(axis_c2h_buf_tvalid && axis_c2h_buf_tready)
            axis_c2h_buf_sop <= 1'b0;
    end

    assign qid_fifo_rd_en = axis_c2h_buf_tvalid && axis_c2h_buf_sop && axis_c2h_buf_tready;

    always @(posedge axis_aclk ) begin
        if(~dma_rstn)
            m_axis_c2h_tvalid <= 1'b0;
        else if(axis_c2h_buf_tvalid && axis_c2h_buf_tready)
            m_axis_c2h_tvalid <= 1'b1;
        else if(m_axis_c2h_tvalid & m_axis_c2h_tready & m_axis_c2h_tlast)
            m_axis_c2h_tvalid <= 1'b0;
    end

    always @(posedge axis_aclk) begin
        if(m_axis_c2h_tready)begin 
            m_axis_c2h_tdata    <= swap_endian_64(axis_c2h_buf_tdata);
            m_axis_c2h_tlast    <= axis_c2h_buf_tlast;
            m_axis_c2h_tkeep    <= axis_c2h_buf_tkeep;
        end  

        if(qid_fifo_rd_en)
            m_axis_c2h_tuser_qid<= qid_fifo_dout;
    end

    assign axis_c2h_buf_tready   = axis_c2h_buf_sop ? m_axis_c2h_tready && ~qid_fifo_empty : m_axis_c2h_tready;

    qdma_subsystem_hash 
    u1_hash_inst 
    (
        .p_axis_tvalid                      (s_axis_c2h_tvalid  ),
        .p_axis_tdata                       (s_axis_c2h_tdata   ),
        .p_axis_tlast                       (s_axis_c2h_tlast   ),
        .p_axis_tready                      (s_axis_c2h_tready  ),
        .hash_key                           (hash_key           ),
        .hash_result_valid                  (hash_result_valid  ),
        .hash_result                        (hash_result        ),
        .arp_icmp_flag                      (arp_icmp_flag      ),
        .aclk                               (axis_aclk          ),
        .aresetn                            (dma_rstn           )
    );

    sfifo  #(
        .ALMOST_EMPTY                       (1                      ),
        .ALMOST_AFULL                       (1                      ),
        .FIFO_TYPE                          ("M20K"                 ),
        .SHOWAHEAD                          ("ON"                   ),
        .DEPTH                              (C_QID_FIFO_DEPTH       ),
        .WIDTH                              (12                     )
    ) u2_qid_fifo(  
        .aclr                               (~dma_rstn              ),
        .clock                              (dma_clk                ),
        .data                               (qid_fifo_din           ),
        .rdreq                              (qid_fifo_rd_en         ),
        .wrreq                              (qid_fifo_wr_en         ),
        .almost_empty                       (                       ),
        .almost_full                        (                       ),
        .empty                              (qid_fifo_empty         ),
        .full                               (qid_fifo_full          ),
        .q                                  (qid_fifo_dout          ),
        .usedw                              (                       )
    );

    axis_fifo #(
        .CLOCKING_MODE                      ("SCFIFO"               ),
        .FIFO_TYPE                          ("M20K"                 ),
        .PACKET_FIFO                        ("FALSE"                ),
        .FIFO_DEPTH                         (C_PKT_FIFO_DEPTH       ),
        .TDATA_WIDTH                        (512                    ),
        .TUSER_WIDTH                        (0                      ),
        .ALMOST_EMPTY                       (4                      ),
        .ALMOST_AFULL                       (360                    ),
        .KEEP_EN                            ("OFF"                  )//"ON"时 keep有效，off时emty有效
    )axis_fifo_u(           
        .s_axis_tvalid                      (s_axis_c2h_tvalid      ),
        .s_axis_tready                      (s_axis_c2h_tready      ),
        .s_axis_tdata                       (s_axis_c2h_tdata       ),
        .s_axis_temty                       (s_axis_c2h_tkeep       ),
        .s_axis_tkeep                       (                       ),
        .s_axis_tlast                       (s_axis_c2h_tlast       ),
        .s_axis_tuser                       (                       ),
        .s_axis_pfull                       (                       ),
        .s_axis_drop                        (1'b0                   ),
        .m_axis_tvalid                      (axis_c2h_buf_tvalid    ),
        .m_axis_tready                      (axis_c2h_buf_tready    ),
        .m_axis_tdata                       (axis_c2h_buf_tdata     ),
        .m_axis_temty                       (axis_c2h_buf_tkeep     ),
        .m_axis_tkeep                       (                       ),
        .m_axis_tlast                       (axis_c2h_buf_tlast     ),
        .m_axis_tuser                       (                       ),
        .s_aresetn                          (dma_rstn               ),
        .s_clk                              (axis_aclk              ),
        .m_clk                              (axis_aclk              )
    );

    qdma_subsystem_function_register 
    u4_reg_inst
    (
        .s_avm_addr                         (s_avm_addr         ),
        .s_avm_read                         (s_avm_read         ),
        .s_avm_write                        (s_avm_write        ),
        .s_avm_wdat                         (s_avm_wdat         ),
        .s_avm_wait                         (s_avm_wait         ),
        .s_avm_rdat                         (s_avm_rdat         ),
        .s_avm_rvld                         (s_avm_rvld         ),
        .s_avm_rspo                         (s_avm_rspo         ),
        .s_avm_wrsp                         (s_avm_wrsp         ),
        .q_base                             (q_base             ),
        .num_q                              (num_q              ),
        .indir_table                        (indir_table        ),
        .hash_key                           (hash_key           ),
        .axil_aclk                          (axil_aclk          ),
        .axis_aclk                          (axis_aclk          ),
        .axil_aresetn                       (axil_aresetn       )
    );
    function [511:0] swap_endian_64;
		input [511:0] din;
		integer i;
		reg [7:0] tmp_data;
		begin : swap_block_64
			for(i=0;i<64;i=i+1)
				swap_endian_64[(63-i)*8 +:8] = din[i*8 +:8];
		end
	endfunction

endmodule
