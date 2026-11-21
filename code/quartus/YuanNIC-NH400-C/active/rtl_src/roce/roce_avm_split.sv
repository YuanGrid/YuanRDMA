// roce_avm_split.sv
// 把 AVMM 地址窗口 [27:20] == SLOT 的访问分给 RoCE CSR，其余原样转给 avm_config。
// 协议沿用 avm_config：请求为单拍脉冲（wait 为低时），wait 拉高直到 rvld/wrsp。
`default_nettype none
`timescale 1ns/1ps
module roce_avm_split #(
    parameter logic [7:0] SLOT = 8'h17
)(
    // 上游（cdc2cfg）
    input  wire  [27:0] upstream_address,
    input  wire         upstream_read,
    input  wire         upstream_write,
    input  wire  [31:0] upstream_write_data,
    output wire         upstream_wait,
    output wire  [31:0] upstream_read_data,
    output wire         upstream_read_valid,
    output wire  [1:0]  upstream_response,
    output wire         upstream_write_response,
    // 原有 avm_config
    output wire  [27:0] legacy_address,
    output wire         legacy_read,
    output wire         legacy_write,
    output wire  [31:0] legacy_write_data,
    input  wire         legacy_wait,
    input  wire  [31:0] legacy_read_data,
    input  wire         legacy_read_valid,
    input  wire  [1:0]  legacy_response,
    input  wire         legacy_write_response,
    // RoCE CSR
    output wire  [27:0] roce_address,
    output wire         roce_read,
    output wire         roce_write,
    output wire  [31:0] roce_write_data,
    input  wire         roce_wait,
    input  wire  [31:0] roce_read_data,
    input  wire         roce_read_valid,
    input  wire  [1:0]  roce_response,
    input  wire         roce_write_response
);
    wire is_roce_window = (upstream_address[27:20] == SLOT);

    assign legacy_address  = upstream_address;
    assign legacy_write_data  = upstream_write_data;
    assign legacy_read  = upstream_read  & ~is_roce_window;
    assign legacy_write = upstream_write & ~is_roce_window;

    assign roce_address  = upstream_address;
    assign roce_write_data  = upstream_write_data;
    assign roce_read  = upstream_read  & is_roce_window;
    assign roce_write = upstream_write & is_roce_window;

    assign upstream_wait = legacy_wait | roce_wait;
    assign upstream_read_valid = legacy_read_valid | roce_read_valid;
    assign upstream_write_response = legacy_write_response | roce_write_response;
    assign upstream_read_data = roce_read_valid ? roce_read_data : legacy_read_data;
    assign upstream_response = roce_read_valid ? roce_response : legacy_response;
endmodule
`default_nettype wire
