// roce_cq.sv
// CQE 写回：CLIENTS 个客户端按轮询提交 CQE，按 CQC 写到主机 CQ 环（32 B/项，加 owner 位）。
// CQ doorbell 给出 consumer_index，只用于溢出计数（溢出时仍覆盖写，provider 需保证 CQ 足够深）。
`default_nettype none
`timescale 1ns/1ps
module roce_cq
    import roce_pkg::*;
#(
    parameter int CLIENTS = 2
)(
    input  wire              clk,
    input  wire              rst,
    input  cqc_t             cqc [CQ_NUM],
    input  wire  [CQ_NUM-1:0] cq_reset,
    input  wire              doorbell_cq_valid,
    input  wire  [31:0]      doorbell_data,       // [31:16] consumer_index [7:0] cq_idx
    // CQE 提交：cqe = {imm, byte_len, dw1, dw0}（dw0[31] owner 由本模块填）
    input  wire  [CLIENTS-1:0]    cqe_valid,
    output wire  [CLIENTS-1:0]    cqe_ready,
    input  wire  [CLIENTS*4-1:0]  cqe_cq_index,
    input  wire  [CLIENTS*128-1:0] cqe_data,
    // DMA 写
    output reg               dma_write_request_valid,
    input  wire              dma_write_request_ready,
    output reg   [63:0]      dma_write_request_address,
    output wire  [63:0]      dma_write_request_page1,
    output wire  [12:0]      dma_write_request_length,
    output reg               dma_write_valid,
    input  wire              dma_write_ready,
    output reg   [1023:0]    dma_write_data,
    // 当前这条 CQE 来自哪个客户端（S_IDLE 受理时锁存，S_REQUEST/S_DATA 期间稳定）。
    // Phase 1 多 lane：roce_top 按它把 DMA 写分发到产生该 CQE 的那个 lane 的 DMA，
    // 使 CQE 与它前面的 payload 走同一个 AXI ID，「payload 先于 CQE 可见」的保序不丢。
    output reg   [((CLIENTS > 1) ? $clog2(CLIENTS) : 1)-1:0] dma_write_client,
    // 计数
    output reg               event_cqe,
    output reg               event_overflow
);
    localparam int CLIENT_W = (CLIENTS > 1) ? $clog2(CLIENTS) : 1;

    reg  [15:0] producer_index [CQ_NUM];
    reg  [15:0] consumer_index [CQ_NUM];

    assign dma_write_request_page1 = dma_write_request_address + 64'd4096;   // 32 B 对齐项不会跨页
    assign dma_write_request_length   = 13'd32;

    reg  [CLIENT_W-1:0] round_robin, picked_client;
    reg           any_request;
    integer client;
    always @* begin
        any_request  = 1'b0;
        picked_client = round_robin;
        for (client = CLIENTS - 1; client >= 0; client = client - 1)
            if (cqe_valid[(round_robin + client) % CLIENTS]) begin
                any_request  = 1'b1;
                picked_client = CLIENT_W'((round_robin + client) % CLIENTS);
            end
    end

    localparam [1:0] S_IDLE = 2'd0, S_REQUEST = 2'd1, S_DATA = 2'd2;
    reg  [1:0] state;
    wire       take_cqe = (state == S_IDLE) && any_request;
    assign cqe_ready = take_cqe ? (CLIENTS'(1) << picked_client) : '0;

    wire [3:0]   cq    = cqe_cq_index[picked_client*4 +: 4];
    wire [127:0] cqe_entry    = cqe_data[picked_client*128 +: 128];
    wire [15:0]  producer    = producer_index[cq];
    wire [3:0]   log2_depth   = cqc[cq].log2_depth;
    wire [15:0]  index_mask = (16'd1 << log2_depth) - 16'd1;
    wire         owner_bit  = ~producer[log2_depth];
    wire         ring_full = ((producer - consumer_index[cq]) > index_mask);

    integer entry;
    always @(posedge clk) begin
        event_cqe      <= 1'b0;
        event_overflow <= 1'b0;
        if (doorbell_cq_valid)
            consumer_index[doorbell_data[3:0]] <= doorbell_data[31:16];
        for (entry = 0; entry < CQ_NUM; entry = entry + 1)
            if (cq_reset[entry]) begin
                producer_index[entry] <= 16'd0;
                consumer_index[entry] <= 16'd0;
            end
        if (rst) begin
            state           <= S_IDLE;
            round_robin           <= '0;
            dma_write_client      <= '0;
            dma_write_request_valid <= 1'b0;
            dma_write_valid     <= 1'b0;
            // CQ 环的生产/消费指针同样属于"数据面状态"，软复位必须清零，
            // 否则残留的 producer 会让新连接的 CQE 写回旧位置，owner 位也反相。
            for (entry = 0; entry < CQ_NUM; entry = entry + 1) begin
                producer_index[entry] <= 16'd0;
                consumer_index[entry] <= 16'd0;
            end
        end else case (state)
            S_IDLE: if (any_request) begin
                        round_robin <= CLIENT_W'((picked_client + 1) % CLIENTS);
                        if (!cqc[cq].valid) begin
                            event_overflow <= 1'b1;            // 未配置的 CQ：丢弃
                        end else begin
                            event_cqe       <= 1'b1;
                            event_overflow  <= ring_full;
                            producer_index[cq]        <= producer + 16'd1;
                            dma_write_client          <= picked_client;
                            dma_write_request_address  <= cqc[cq].base + {43'd0, (producer & index_mask), 5'd0};
                            dma_write_request_valid <= 1'b1;
                            // 1024 位写拍：低 32 B 是 CQE，高 96 B 必须为 0——wr_align 会用
                            // request_length=32 算出的 wstrb 把其余字节屏蔽掉，零填充只是让波形可读。
                            dma_write_data      <= {896'd0, cqe_entry[127:32], owner_bit, cqe_entry[30:0]};
                            state           <= S_REQUEST;
                        end
                    end
            S_REQUEST:  if (dma_write_request_ready) begin
                        dma_write_request_valid <= 1'b0;
                        dma_write_valid     <= 1'b1;
                        state           <= S_DATA;
                    end
            S_DATA: if (dma_write_ready) begin
                        dma_write_valid <= 1'b0;
                        state       <= S_IDLE;
                    end
            default: state <= S_IDLE;
        endcase
    end
endmodule
`default_nettype wire
