// roce_skid.sv
// 两级 skid（全寄存器 register slice）：s 侧 ready 与 m 侧 valid/data 全部由寄存器驱动，
// 两侧的组合路径在这里彻底断开；m_ready 一直为 1 时吞吐 1 拍/拍，只多 1 拍固定延迟。
//
// 与 utility/axi_stream_register_slice.sv 的 "full" 模式同构，区别只在：
//   - 数据寄存器不挂复位（只复位两个 valid 位）。挂同步复位会让 dp_rst 扇出到每一位
//     数据的 sclr，B6416 里 dp_rst 的扇出本身就是第二大违例组；
//   - 一个打平的 WIDTH 位数据口，调用方自己拼 {tag, last, keep, data}。
//
// 不变式：main 空时 skid 必空（只有 main 满且没被取走时才往 skid 里存）。
`default_nettype none
`timescale 1ns/1ps
module roce_skid #(
    parameter int WIDTH = 64
)(
    input  wire              clk,
    input  wire              rst,
    input  wire              s_valid,
    output wire              s_ready,
    input  wire [WIDTH-1:0]  s_data,
    output wire              m_valid,
    input  wire              m_ready,
    output wire [WIDTH-1:0]  m_data
);
    reg              main_valid, skid_valid;
    reg  [WIDTH-1:0] main_data,  skid_data;

    assign s_ready = !skid_valid;
    assign m_valid = main_valid;
    assign m_data  = main_data;

    always @(posedge clk) begin
        if (rst) begin
            main_valid <= 1'b0;
            skid_valid <= 1'b0;
        end else if (!main_valid || m_ready) begin
            // main 本拍空出（或本来就空）：优先补 skid 里压着的那一拍，否则直接收上游
            if (skid_valid) begin
                main_valid <= 1'b1;
                skid_valid <= 1'b0;
            end else begin
                main_valid <= s_valid;
            end
        end else if (s_valid && !skid_valid) begin
            // main 满且没被取走，上游本拍又握手成功（s_ready = !skid_valid = 1）：压进 skid
            skid_valid <= 1'b1;
        end
    end

    // 数据通路不复位：与上面 valid 的分支一一对应
    always @(posedge clk) begin
        if (!main_valid || m_ready) begin
            if (skid_valid) main_data <= skid_data;
            else if (s_valid) main_data <= s_data;
        end else if (s_valid && !skid_valid) begin
            skid_data <= s_data;
        end
    end
endmodule
`default_nettype wire
