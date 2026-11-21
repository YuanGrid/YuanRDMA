// roce_avm_cdc.sv
// AVMM 单笔访问跨时钟：上游（slot 分流后，clk250m）-> RoCE CSR（core 时钟）。
// 协议同 avm_config：请求单拍、wait 拉高直到 read_valid/write_response。
// 用请求/应答翻转位握手，数据在翻转位同步期间保持不变。
`default_nettype none
`timescale 1ns/1ps
module roce_avm_cdc (
    input  wire         upstream_clk,
    input  wire         upstream_rst_n,
    input  wire  [27:0] upstream_address,
    input  wire         upstream_read,
    input  wire         upstream_write,
    input  wire  [31:0] upstream_write_data,
    output reg          upstream_wait,
    output reg   [31:0] upstream_read_data,
    output reg          upstream_read_valid,
    output wire  [1:0]  upstream_response,
    output reg          upstream_write_response,
    input  wire         downstream_clk,
    input  wire         downstream_rst_n,
    output reg   [27:0] downstream_address,
    output reg          downstream_read,
    output reg          downstream_write,
    output reg   [31:0] downstream_write_data,
    input  wire         downstream_wait,
    input  wire  [31:0] downstream_read_data,
    input  wire         downstream_read_valid,
    input  wire         downstream_write_response
);
    assign upstream_response = 2'b00;

    // ---------------- 上游：锁存请求，翻转 request_toggle，等 ack_toggle 回来
    reg         request_toggle, request_is_write;
    reg  [27:0] request_address;
    reg  [31:0] request_data;
    reg  [31:0] response_data;
    reg         ack_toggle;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    reg  [1:0]  ack_sync;
    reg         ack_seen;
    always @(posedge upstream_clk) begin
        upstream_read_valid     <= 1'b0;
        upstream_write_response <= 1'b0;
        ack_sync <= {ack_sync[0], ack_toggle};
        if (!upstream_rst_n) begin
            upstream_wait  <= 1'b0;
            request_toggle <= 1'b0;
            ack_seen       <= 1'b0;
        end else if (!upstream_wait && (upstream_read || upstream_write)) begin
            upstream_wait    <= 1'b1;
            request_is_write <= upstream_write;
            request_address  <= upstream_address;
            request_data     <= upstream_write_data;
            request_toggle   <= ~request_toggle;
        end else if (upstream_wait && ack_sync[1] != ack_seen) begin
            ack_seen                <= ack_sync[1];
            upstream_wait           <= 1'b0;
            upstream_read_data      <= response_data;
            upstream_read_valid     <= !request_is_write;
            upstream_write_response <= request_is_write;
        end
    end

    // ---------------- 下游：看到 request_toggle 变化就发一次访问，完成后翻转 ack_toggle
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    reg  [1:0]  request_sync;
    reg         request_seen, busy;
    always @(posedge downstream_clk) begin
        downstream_read  <= 1'b0;
        downstream_write <= 1'b0;
        request_sync <= {request_sync[0], request_toggle};
        if (!downstream_rst_n) begin
            request_seen <= 1'b0;
            busy         <= 1'b0;
            ack_toggle   <= 1'b0;
        end else if (!busy && request_sync[1] != request_seen && !downstream_wait) begin
            request_seen          <= request_sync[1];
            busy                  <= 1'b1;
            downstream_address    <= request_address;
            downstream_write_data <= request_data;
            downstream_read       <= !request_is_write;
            downstream_write      <= request_is_write;
        end else if (busy && (downstream_read_valid || downstream_write_response)) begin
            busy          <= 1'b0;
            response_data <= downstream_read_data;
            ack_toggle    <= ~ack_toggle;
        end
    end
endmodule
`default_nettype wire
