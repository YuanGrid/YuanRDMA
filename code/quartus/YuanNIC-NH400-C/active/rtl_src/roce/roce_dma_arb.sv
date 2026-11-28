// roce_dma_arb.sv
// roce_dma 前的多客户端仲裁。
// - 读：请求轮询仲裁，tag = 客户端号；读数据按 tag 分发（读数据按序返回，某客户端不接收会
//   堵住其后所有读数据，所以 WQE 取指类客户端必须一直能收）。
// - 写：请求轮询仲裁，授权后锁定该客户端直到 ceil(transfer_length/(WR_DW/8)) 拍数据写完；写完成按请求顺序
//   返回给对应客户端。
// - 写数据位宽 WR_DW（1024 / 2048）纯透传；锁定拍数按 WR_DW/8 字节一拍计，与 roce_dma 的输入约定一致。
`default_nettype none
`timescale 1ns/1ps
module roce_dma_arb #(
    parameter int READ_CLIENTS = 4,
    parameter int WRITE_CLIENTS = 4,
    parameter int RD_DW = 1024,             // 读数据位宽（纯透传，仲裁逻辑与位宽无关）
    parameter int WR_DW = 1024              // 写数据位宽（纯透传；只影响每请求的数据拍数）
)(
    input  wire                 clk,
    input  wire                 rst,
    // 读客户端
    input  wire  [READ_CLIENTS-1:0]       dma_read_request_valid,
    output wire  [READ_CLIENTS-1:0]       dma_read_request_ready,
    input  wire  [READ_CLIENTS*64-1:0]    dma_read_request_address,
    input  wire  [READ_CLIENTS*64-1:0]    dma_read_request_page1,
    input  wire  [READ_CLIENTS*13-1:0]    dma_read_request_length,
    output wire  [READ_CLIENTS-1:0]       dma_read_valid,
    input  wire  [READ_CLIENTS-1:0]       dma_read_ready,
    output wire  [RD_DW-1:0]    dma_read_data,
    output wire  [RD_DW/8-1:0]  dma_read_keep,
    output wire                 dma_read_last,
    output wire                 dma_read_error,
    // 写客户端
    input  wire  [WRITE_CLIENTS-1:0]       dma_write_request_valid,
    output wire  [WRITE_CLIENTS-1:0]       dma_write_request_ready,
    input  wire  [WRITE_CLIENTS*64-1:0]    dma_write_request_address,
    input  wire  [WRITE_CLIENTS*64-1:0]    dma_write_request_page1,
    input  wire  [WRITE_CLIENTS*13-1:0]    dma_write_request_length,
    input  wire  [WRITE_CLIENTS-1:0]       dma_write_valid,
    output wire  [WRITE_CLIENTS-1:0]       dma_write_ready,
    input  wire  [WRITE_CLIENTS*WR_DW-1:0] dma_write_data,
    output reg   [WRITE_CLIENTS-1:0]       dma_write_complete,
    output reg                  dma_write_complete_error,
    // 到 roce_dma
    output wire                 downstream_read_request_valid,
    input  wire                 downstream_read_request_ready,
    output wire  [63:0]         downstream_read_request_address,
    output wire  [63:0]         downstream_read_request_page1,
    output wire  [12:0]         downstream_read_request_length,
    output wire  [3:0]          downstream_read_request_tag,
    input  wire                 downstream_read_valid,
    output wire                 downstream_read_ready,
    input  wire  [RD_DW-1:0]    downstream_read_data,
    input  wire  [RD_DW/8-1:0]  downstream_read_keep,
    input  wire                 downstream_read_last,
    input  wire  [3:0]          downstream_read_tag,
    input  wire                 downstream_read_error,
    output wire                 downstream_write_request_valid,
    input  wire                 downstream_write_request_ready,
    output wire  [63:0]         downstream_write_request_address,
    output wire  [63:0]         downstream_write_request_page1,
    output wire  [12:0]         downstream_write_request_length,
    output wire                 downstream_write_valid,
    input  wire                 downstream_write_ready,
    output wire  [WR_DW-1:0]    downstream_write_data,
    input  wire                 downstream_write_complete,
    input  wire                 downstream_write_complete_error
);
    localparam int READ_CLIENT_W = (READ_CLIENTS > 1) ? $clog2(READ_CLIENTS) : 1;
    localparam int WRITE_CLIENT_W = (WRITE_CLIENTS > 1) ? $clog2(WRITE_CLIENTS) : 1;

    // ------------------------------------------------------------ 读
    reg  [READ_CLIENT_W-1:0] read_round_robin, read_pick;
    reg           read_any;
    integer client;
    always @* begin
        read_any  = 1'b0;
        read_pick = read_round_robin;
        for (client = READ_CLIENTS - 1; client >= 0; client = client - 1)
            if (dma_read_request_valid[(read_round_robin + client) % READ_CLIENTS]) begin
                read_any  = 1'b1;
                read_pick = READ_CLIENT_W'((read_round_robin + client) % READ_CLIENTS);
            end
    end
    assign downstream_read_request_valid = read_any;
    assign downstream_read_request_address  = dma_read_request_address [read_pick*64 +: 64];
    assign downstream_read_request_page1 = dma_read_request_page1[read_pick*64 +: 64];
    assign downstream_read_request_length   = dma_read_request_length  [read_pick*13 +: 13];
    assign downstream_read_request_tag   = 4'(read_pick);
    assign dma_read_request_ready   = (read_any && downstream_read_request_ready) ? (READ_CLIENTS'(1) << read_pick) : '0;
    always @(posedge clk) begin
        if (rst)                         read_round_robin <= '0;
        else if (read_any && downstream_read_request_ready)     read_round_robin <= READ_CLIENT_W'((read_pick + 1) % READ_CLIENTS);
    end

    genvar client_index;
    generate
        for (client_index = 0; client_index < READ_CLIENTS; client_index = client_index + 1) begin : gen_read_valid
            assign dma_read_valid[client_index] = downstream_read_valid && (downstream_read_tag == client_index);
        end
    endgenerate
    assign downstream_read_ready = dma_read_ready[downstream_read_tag[READ_CLIENT_W-1:0]];
    assign dma_read_data    = downstream_read_data;
    assign dma_read_keep    = downstream_read_keep;
    assign dma_read_last    = downstream_read_last;
    assign dma_read_error     = downstream_read_error;

    // ------------------------------------------------------------ 写
    reg  [WRITE_CLIENT_W-1:0] write_round_robin, write_pick, write_owner;
    reg           write_any, write_locked;
    reg  [6:0]    write_beats_left;
    always @* begin
        write_any  = 1'b0;
        write_pick = write_round_robin;
        for (client = WRITE_CLIENTS - 1; client >= 0; client = client - 1)
            if (dma_write_request_valid[(write_round_robin + client) % WRITE_CLIENTS]) begin
                write_any  = 1'b1;
                write_pick = WRITE_CLIENT_W'((write_round_robin + client) % WRITE_CLIENTS);
            end
    end
    wire          order_fifo_full;
    wire          write_grant = !write_locked && write_any && !order_fifo_full;
    assign downstream_write_request_valid = write_grant;
    assign downstream_write_request_address  = dma_write_request_address [write_pick*64 +: 64];
    assign downstream_write_request_page1 = dma_write_request_page1[write_pick*64 +: 64];
    assign downstream_write_request_length   = dma_write_request_length  [write_pick*13 +: 13];
    assign dma_write_request_ready   = (write_grant && downstream_write_request_ready) ? (WRITE_CLIENTS'(1) << write_pick) : '0;

    // B0123 时序：写数据方向的握手改用寄存的 one-hot 位 write_owner_oh[i] = write_locked && write_owner == i。
    // dma_write_ready 原来是「write_locked && downstream_write_ready 再按 write_owner 移位」，它经 resp / req 的
    // rx_payload_ready、u_disp 一路串到 RX payload skid 的 2305 位装载使能（B0122 core_clk 余量 0 的簇 A）；
    // 现在每个客户端只是 write_owner_oh[i] && downstream_write_ready 一个与门。数据仍按 write_owner 选路
    // （不在握手环上）。write_locked / write_owner 照旧保留，下面的仿真断言逐拍核对 one-hot 与它们一致。
    reg  [WRITE_CLIENTS-1:0] write_owner_oh;
    assign downstream_write_valid = |(write_owner_oh & dma_write_valid);
    assign downstream_write_data  = dma_write_data[write_owner*WR_DW +: WR_DW];
    assign dma_write_ready   = write_owner_oh & {WRITE_CLIENTS{downstream_write_ready}};
    // synthesis translate_off
    always @(posedge clk) begin
        if (!rst && (write_owner_oh != (write_locked ? (WRITE_CLIENTS'(1) << write_owner) : '0)))
            $fatal(1, "roce_dma_arb: write_owner_oh=%b 与 write_locked=%0d write_owner=%0d 不一致",
                   write_owner_oh, write_locked, write_owner);
    end
    // synthesis translate_on

    // 写完成顺序 FIFO（客户端号）
    reg  [WRITE_CLIENT_W-1:0] order_fifo [64];
    reg  [6:0]    order_write_pointer, order_read_pointer;
    assign order_fifo_full = (order_write_pointer - order_read_pointer) == 7'd64;

    always @(posedge clk) begin
        dma_write_complete     <= '0;
        dma_write_complete_error <= downstream_write_complete_error;
        if (rst) begin
            write_round_robin   <= '0;
            write_locked <= 1'b0;
            write_owner_oh <= '0;
            order_write_pointer <= '0;
            order_read_pointer <= '0;
        end else begin
            if (write_grant && downstream_write_request_ready) begin
                write_round_robin       <= WRITE_CLIENT_W'((write_pick + 1) % WRITE_CLIENTS);
                write_owner      <= write_pick;
                write_locked     <= 1'b1;
                write_owner_oh   <= WRITE_CLIENTS'(1) << write_pick;
                write_beats_left    <= 7'((downstream_write_request_length + 13'(WR_DW/8 - 1)) >> $clog2(WR_DW/8));
                order_fifo[order_write_pointer[5:0]] <= write_pick;
                order_write_pointer     <= order_write_pointer + 7'd1;
            end
            if (downstream_write_valid && downstream_write_ready) begin
                write_beats_left <= write_beats_left - 7'd1;
                if (write_beats_left == 7'd1) begin
                    write_locked   <= 1'b0;
                    write_owner_oh <= '0;
                end
            end
            if (downstream_write_complete) begin
                dma_write_complete[order_fifo[order_read_pointer[5:0]]] <= 1'b1;
                order_read_pointer <= order_read_pointer + 7'd1;
            end
        end
    end
endmodule
`default_nettype wire
