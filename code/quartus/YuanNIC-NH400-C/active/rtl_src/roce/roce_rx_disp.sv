// roce_rx_disp.sv
// 把 roce_rx_parse 输出的每个包交给响应方（请求类 opcode）或请求方（ACK/READ RESP），
// payload 流跟随头部归属。一次只处理一个包：等目标模块 done 后再取下一个头。
`default_nettype none
`timescale 1ns/1ps
module roce_rx_disp
    import roce_pkg::*;
(
    input  wire       clk,
    input  wire       rst,
    input  wire       rx_header_valid,
    output wire       rx_header_ready,
    input  rx_hdr_t   rx_header,
    input  wire       rx_payload_valid,
    output wire       rx_payload_ready,
    // 0 = 响应方，1 = 请求方
    output wire [1:0] route_header_valid,
    input  wire [1:0] route_header_ready,
    output wire [1:0] route_payload_valid,
    input  wire [1:0] route_payload_ready,
    input  wire [1:0] route_done,
    output reg        event_rx_packet,
    output wire [1:0] debug_busy_owner   // 调试：{owner, busy}
);
    // CNP 是给**发送方**的回执，走请求方（u_req 负责 rp_cnp_handled 计数）。
    // is_response=1 → port 1 = u_req（请求方）。CNP（0x81）不在 0x0D..0x11 区间，早先写成
    // `&& !op_is_cnp` 是空操作，CNP 落到 u_resp 被当坏包丢掉（RX_BAD_QP 涨、rp_cnp_handled 恒 0，
    // test_dcqcn 步骤 4 失败，2026-11-10 sim11）。必须用 `||` 把 CNP 显式送进请求方。
    wire is_response = ((rx_header.opcode >= OP_READ_RESP_FIRST) && (rx_header.opcode <= OP_ACK)) ||
                       op_is_cnp(rx_header.opcode);
    reg  busy, owner;
    assign debug_busy_owner = {owner, busy};
    wire destination_address = is_response;

    assign route_header_valid = (!busy && rx_header_valid) ? (2'b01 << destination_address) : 2'b00;
    assign rx_header_ready   = !busy && route_header_ready[destination_address];
    // B0123 时序：payload 方向的选路改用寄存的 one-hot 位 busy_owner[i] = busy && owner == i。
    // rx_payload_ready 是 RX payload skid（2305 位）的 m_ready，原来要先按 owner 选 route_payload_ready 再与 busy，
    // 现在每路只是一个与门再或起来（B0122 core_clk 余量 0 的簇 A：u_req|state → u_pay_eng_skid）。
    // busy / owner 照旧保留（头部方向与调试口用），下面的仿真断言逐拍核对 one-hot 与它们一致。
    reg  [1:0] busy_owner;
    assign route_payload_valid = busy_owner & {2{rx_payload_valid}};
    assign rx_payload_ready   = |(busy_owner & route_payload_ready);
    // synthesis translate_off
    always @(posedge clk) begin
        if (!rst && (busy_owner != (busy ? (2'b01 << owner) : 2'b00)))
            $fatal(1, "roce_rx_disp: busy_owner=%b 与 busy=%0d owner=%0d 不一致", busy_owner, busy, owner);
    end
    // synthesis translate_on

    always @(posedge clk) begin
        event_rx_packet <= 1'b0;
        if (rst) begin
            busy       <= 1'b0;
            busy_owner <= 2'b00;
        end else if (!busy) begin
            if (rx_header_valid && rx_header_ready) begin
                busy       <= 1'b1;
                owner      <= destination_address;
                busy_owner <= 2'b01 << destination_address;
                event_rx_packet <= !rx_header.bad;
            end
        end else if (route_done[owner]) begin
            busy       <= 1'b0;
            busy_owner <= 2'b00;
        end
    end
endmodule
`default_nettype wire
