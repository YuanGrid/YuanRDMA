// roce_tbl.sv
// 资源表：QPC（16）、MPT（64）、MTT（8192，奇偶两个 bank，一次读出相邻两页）、CQC（16），
// 由 CSR 表命令写入（格式见 yuanrdma_hw.h）；另提供 lkey/rkey 地址翻译服务（CLIENTS 个客户端，
// 轮询仲裁，每拍可受理一个，固定 4 拍返回）。
// QP 状态：主机写 QPC 时若 state 变化，qp_state_change[entry] 打一拍；硬件 qp_set_error[entry] 把状态置 ERR。
`default_nettype none
`timescale 1ns/1ps
module roce_tbl
    import roce_pkg::*;
#(
    parameter int CLIENTS = 3
)(
    input  wire                     clk,
    input  wire                     rst,
    // 表命令（来自 roce_csr）
    input  wire                     table_request,
    input  wire                     table_write_enable,
    input  wire  [3:0]              table_select,
    input  wire  [23:0]             table_index,
    input  wire  [511:0]            table_write_data,
    output reg                      table_ack,
    output reg                      table_error,
    output reg   [511:0]            table_read_data,
    // QPC（state 为当前有效状态）
    output wire  [QP_NUM*512-1:0]   qpc,
    // QP 状态单独引出一份（3 bit × QP_NUM）。
    // 为什么需要：req/resp 的每个 QP 扫描条件只要 state 这 3 位，但写法是
    //   qpc_state(qpc[qp*512 +: 512]) == QPS_RTS
    // 会在每个 QP 上实例化一个完整的 512:1 位选择器，16 个串进同一条组合链。
    // 2026-10-31 的 STA（B6383 fit 前）显示 core_clk 关键路径正是从
    //   u_req|fetch_round_robin[1]（扇出 829）出发、21 级逻辑、走线占 59%
    //   → u_resp|out_address → u_resp|out_psn，
    // 这段扫描就是它的开头。改成直接用 qp_state_o[qp]（3 bit mux）可去掉这一级。
    output wire  [QP_NUM*3-1:0]     qp_state_o,
    output reg   [QP_NUM-1:0]       qp_state_change,
    input  wire  [QP_NUM-1:0]       qp_set_error,
    // CQC
    output cqc_t                    cqc [CQ_NUM],
    output reg   [CQ_NUM-1:0]       cq_reset,
    // 地址翻译：长度 transfer_length 的区间 [va, va+transfer_length) 须在 MR 内且不超过一页边界一次（<= 4096）
    input  wire  [CLIENTS-1:0]           translate_valid,
    output wire  [CLIENTS-1:0]           translate_ready,
    input  wire  [CLIENTS*32-1:0]        translate_key,
    input  wire  [CLIENTS*64-1:0]        translate_virtual_address,
    input  wire  [CLIENTS*13-1:0]        translate_length,
    input  wire  [CLIENTS*4-1:0]         translate_access,
    input  wire  [CLIENTS*16-1:0]        translate_protection_domain,
    output reg   [CLIENTS-1:0]           translate_response,     // 单拍，pa0/pa1/err 同拍有效
    output reg   [63:0]             translate_physical_address0,
    output reg   [63:0]             translate_physical_page1,
    output reg                      translate_error
);
    localparam int CLIENT_W = (CLIENTS > 1) ? $clog2(CLIENTS) : 1;

    // ------------------------------------------------------------ 存储
    reg  [511:0] qpc_store  [QP_NUM];
    reg  [2:0]   qp_state_store    [QP_NUM];
    reg  [31:0]  mpt_flags[MR_NUM];
    reg  [31:0]  mpt_key[MR_NUM];
    reg  [63:0]  mpt_virtual_address [MR_NUM];
    reg  [63:0]  mpt_length[MR_NUM];
    reg  [31:0]  mpt_mtt_base[MR_NUM];
    (* ramstyle = "no_rw_check,m20k" *) reg [63:0] mtt_even_bank [MTT_NUM/2];
    (* ramstyle = "no_rw_check,m20k" *) reg [63:0] mtt_odd_bank [MTT_NUM/2];

    genvar qp;
    generate
        for (qp = 0; qp < QP_NUM; qp = qp + 1) begin : gen_qpc
            assign qpc[qp*512 +: 512] = {qpc_store[qp][511:3], qp_state_store[qp]};
            assign qp_state_o[qp*3 +: 3] = qp_state_store[qp];
        end
    endgenerate

    // ------------------------------------------------------------ 表命令
    reg          mtt_write_busy;
    reg  [2:0]   mtt_write_step;
    reg  [12:0]  mtt_write_base;
    reg  [511:0] mtt_write_entries;
    reg          mtt_write_even, mtt_write_odd;
    reg  [11:0]  mtt_write_address;
    reg  [63:0]  mtt_write_value;

    wire [23:0]  command_index = table_index;
    wire         index_valid_qpc = (command_index < QP_NUM);
    wire         index_valid_mpt = (command_index < MR_NUM);
    wire         index_valid_mtt = (command_index[2:0] == 3'd0) && (command_index + 24'd8 <= MTT_NUM);
    wire         index_valid_cqc = (command_index < CQ_NUM);

    integer entry;
    always @(posedge clk) begin
        table_ack  <= 1'b0;
        qp_state_change   <= '0;
        cq_reset   <= '0;
        mtt_write_even <= 1'b0;
        mtt_write_odd <= 1'b0;
        // 硬件把 QP 置错（主机同拍写该 QP 时以主机为准）
        for (entry = 0; entry < QP_NUM; entry = entry + 1)
            if (qp_set_error[entry] && !(table_request && table_write_enable && table_select == TBL_QPC && index_valid_qpc && command_index[3:0] == entry))
                qp_state_store[entry] <= QPS_ERR;

        if (rst) begin
            mtt_write_busy <= 1'b0;
            for (entry = 0; entry < QP_NUM; entry = entry + 1) qp_state_store[entry] <= QPS_RESET;
            for (entry = 0; entry < MR_NUM; entry = entry + 1) mpt_flags[entry] <= 32'd0;
            for (entry = 0; entry < CQ_NUM; entry = entry + 1) cqc[entry].valid <= 1'b0;
        end else if (mtt_write_busy) begin
            mtt_write_address   <= 12'((mtt_write_base + mtt_write_step) >> 1);
            mtt_write_value   <= mtt_write_entries[mtt_write_step*64 +: 64];
            mtt_write_even <= (mtt_write_step[0] == 1'b0);
            mtt_write_odd <= (mtt_write_step[0] == 1'b1);
            mtt_write_step    <= mtt_write_step + 3'd1;
            if (mtt_write_step == 3'd7) begin
                mtt_write_busy <= 1'b0;
                table_ack  <= 1'b1;
                table_error  <= 1'b0;
            end
        end else if (table_request) begin
            table_ack   <= 1'b1;
            table_error   <= 1'b0;
            table_read_data <= '0;
            case (table_select)
                TBL_QPC: if (!index_valid_qpc) table_error <= 1'b1;
                         else if (table_write_enable) begin
                             qpc_store[command_index[3:0]] <= table_write_data;
                             qp_state_store[command_index[3:0]]   <= table_write_data[2:0];
                             if (qp_state_store[command_index[3:0]] != table_write_data[2:0]) qp_state_change[command_index[3:0]] <= 1'b1;
                         end else
                             table_read_data <= {qpc_store[command_index[3:0]][511:3], qp_state_store[command_index[3:0]]};
                TBL_MPT: if (!index_valid_mpt) table_error <= 1'b1;
                         else if (table_write_enable) begin
                             mpt_flags[command_index[5:0]] <= table_write_data[31:0];
                             mpt_key[command_index[5:0]] <= table_write_data[63:32];
                             mpt_virtual_address [command_index[5:0]] <= table_write_data[127:64];
                             mpt_length[command_index[5:0]] <= table_write_data[191:128];
                             mpt_mtt_base[command_index[5:0]] <= table_write_data[223:192];
                         end else
                             table_read_data[223:0] <= {mpt_mtt_base[command_index[5:0]], mpt_length[command_index[5:0]], mpt_virtual_address[command_index[5:0]],
                                                  mpt_key[command_index[5:0]], mpt_flags[command_index[5:0]]};
                TBL_MTT: if (!index_valid_mtt) table_error <= 1'b1;
                         else if (table_write_enable) begin
                             table_ack  <= 1'b0;          // 8 拍写完再应答
                             mtt_write_busy <= 1'b1;
                             mtt_write_step    <= 3'd0;
                             mtt_write_base <= command_index[12:0];
                             mtt_write_entries <= table_write_data;
                         end
                TBL_CQC: if (!index_valid_cqc) table_error <= 1'b1;
                         else if (table_write_enable) begin
                             cqc[command_index[3:0]].base  <= {table_write_data[63:32], table_write_data[31:0]};
                             cqc[command_index[3:0]].log2_depth    <= table_write_data[68:65];
                             cqc[command_index[3:0]].valid <= table_write_data[64];
                             cq_reset[command_index[3:0]]    <= 1'b1;
                         end else
                             table_read_data[95:0] <= {27'd0, cqc[command_index[3:0]].log2_depth, cqc[command_index[3:0]].valid,
                                                 cqc[command_index[3:0]].base};
                default: table_error <= 1'b1;
            endcase
        end
    end

    always @(posedge clk) begin
        if (mtt_write_even) mtt_even_bank[mtt_write_address] <= mtt_write_value;
        if (mtt_write_odd) mtt_odd_bank[mtt_write_address] <= mtt_write_value;
    end

    // ------------------------------------------------------------ 地址翻译
    // S0 仲裁
    reg  [CLIENT_W-1:0] round_robin;
    reg  [CLIENT_W-1:0] picked_client;
    reg           any_request;
    integer client;
    always @* begin
        any_request  = 1'b0;
        picked_client = round_robin;
        for (client = CLIENTS - 1; client >= 0; client = client - 1) begin
            if (translate_valid[(round_robin + client) % CLIENTS]) begin
                any_request  = 1'b1;
                picked_client = CLIENT_W'((round_robin + client) % CLIENTS);
            end
        end
    end
    assign translate_ready = any_request ? (CLIENTS'(1) << picked_client) : '0;
    always @(posedge clk) begin
        if (rst)      round_robin <= '0;
        else if (any_request) round_robin <= CLIENT_W'((picked_client + 1) % CLIENTS);
    end

    // S1
    reg           stage1_valid;
    reg  [CLIENT_W-1:0] stage1_client;
    reg  [31:0]   stage1_key;
    reg  [63:0]   stage1_virtual_address;
    reg  [12:0]   stage1_length;
    reg  [3:0]    stage1_access;
    reg  [15:0]   stage1_protection_domain;
    always @(posedge clk) begin
        stage1_valid  <= any_request && !rst;
        stage1_client  <= picked_client;
        stage1_key  <= translate_key[picked_client*32 +: 32];
        stage1_virtual_address <= translate_virtual_address [picked_client*64 +: 64];
        stage1_length  <= translate_length[picked_client*13 +: 13];
        stage1_access  <= translate_access[picked_client*4  +: 4];
        stage1_protection_domain <= translate_protection_domain [picked_client*16 +: 16];
    end
    wire [5:0]  stage1_mr_index   = stage1_key[5:0];
    wire [31:0] stage1_mpt_flags = mpt_flags[stage1_mr_index];
    wire        stage1_key_ok = stage1_mpt_flags[0] && (mpt_key[stage1_mr_index] == stage1_key) && ((stage1_mpt_flags[4:1] & stage1_access) == stage1_access) &&
                         (stage1_mpt_flags[31:16] == stage1_protection_domain);
    wire [64:0] stage1_offset  = {1'b0, stage1_virtual_address} - {1'b0, mpt_virtual_address[stage1_mr_index]};

    // S2
    reg           stage2_valid, stage2_ok;
    reg  [CLIENT_W-1:0] stage2_client;
    reg  [63:0]   stage2_offset, stage2_mr_length;
    reg  [12:0]   stage2_length;
    reg  [11:0]   stage2_mr_va_low, stage2_va_page_offset;
    reg  [12:0]   stage2_mtt_base;
    always @(posedge clk) begin
        stage2_valid     <= stage1_valid;
        stage2_client     <= stage1_client;
        stage2_ok    <= stage1_key_ok && !stage1_offset[64];
        stage2_offset   <= stage1_offset[63:0];
        stage2_mr_length  <= mpt_length[stage1_mr_index];
        stage2_length     <= stage1_length;
        stage2_mr_va_low  <= mpt_virtual_address[stage1_mr_index][11:0];
        stage2_va_page_offset <= stage1_virtual_address[11:0];
        stage2_mtt_base   <= mpt_mtt_base[stage1_mr_index][12:0];
    end
    wire [64:0] stage2_end_offset  = {1'b0, stage2_offset} + {52'd0, stage2_length};
    wire        stage2_range_ok  = (stage2_length == 13'd0) || (stage2_end_offset <= {1'b0, stage2_mr_length});
    wire [24:0] stage2_page_index = (stage2_offset[24:0] + {13'd0, stage2_mr_va_low}) >> 12;
    wire [12:0] stage2_mtt_index   = stage2_mtt_base + stage2_page_index[12:0];
    // mi 偶：页 mi 在 e[mi/2]，页 mi+1 在 o[mi/2]；mi 奇：页 mi 在 o[mi/2]，页 mi+1 在 e[mi/2+1]
    wire [11:0] odd_bank_address    = stage2_mtt_index[12:1];
    wire [11:0] even_bank_address    = stage2_mtt_index[12:1] + {11'd0, stage2_mtt_index[0]};

    // S3：RAM 输出
    reg           stage3_valid, stage3_ok, stage3_index_odd;
    reg  [CLIENT_W-1:0] stage3_client;
    reg  [11:0]   stage3_va_page_offset;
    reg  [63:0]   even_bank_data, odd_bank_data;
    always @(posedge clk) begin
        stage3_valid     <= stage2_valid;
        stage3_client     <= stage2_client;
        stage3_ok    <= stage2_ok && stage2_range_ok;
        stage3_index_odd   <= stage2_mtt_index[0];
        stage3_va_page_offset <= stage2_va_page_offset;
        even_bank_data     <= mtt_even_bank[even_bank_address];
        odd_bank_data     <= mtt_odd_bank[odd_bank_address];
    end

    // S4：输出
    always @(posedge clk) begin
        translate_response <= '0;
        if (stage3_valid && !rst) translate_response[stage3_client] <= 1'b1;
        translate_error <= !stage3_ok;
        translate_physical_address0 <= {(stage3_index_odd ? odd_bank_data[63:12] : even_bank_data[63:12]), stage3_va_page_offset};
        translate_physical_page1 <= {(stage3_index_odd ? even_bank_data[63:12] : odd_bank_data[63:12]), 12'd0};
    end
endmodule
`default_nettype wire
