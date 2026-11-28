// roce_dma_rd_narrow.sv
// DMA 读数据（宽，DW 位）按 tag 分流前的「窄客户端」拆拍：
//   - tag == WIDE_TAG（roce_tx 的 payload）：原样透传，一拍 DW/8 字节；
//   - 其它 tag（req WQE 取指、resp RQ 取指、dma_test）：把一个宽拍拆成两个 DW/2 位半拍，
//     半拍放在 m_data 的低 DW/2 位，keep 一并右移。窄客户端只接 m_data[DW/2-1:0]，
//     看到的拍序列与读数据还是 DW/2 位时**逐拍相同**（每拍 DW/16 字节、只有末拍不满、tlast 在末拍），
//     所以这些客户端的代码不用改。
// 宽拍的高半 keep 全 0（请求末拍只剩低半）时不拆，直接作为末拍送出。
//
// 放在 u_dma 与读数据 skid 之间：本模块的 2:1 选择只在 skid 之前，skid 重新寄存，
// tx 的宽数据通路上不因此多一级组合逻辑。
`default_nettype none
`timescale 1ns/1ps
module roce_dma_rd_narrow #(
    parameter int DW       = 2048,
    parameter int TAG_W    = 4,
    parameter int WIDE_TAG = 2
)(
    input  wire              clk,
    input  wire              rst,
    input  wire              s_valid,
    output wire              s_ready,
    input  wire [DW-1:0]     s_data,
    input  wire [DW/8-1:0]   s_keep,
    input  wire              s_last,
    input  wire [TAG_W-1:0]  s_tag,
    input  wire              s_error,
    output wire              m_valid,
    input  wire              m_ready,
    output wire [DW-1:0]     m_data,
    output wire [DW/8-1:0]   m_keep,
    output wire              m_last,
    output wire [TAG_W-1:0]  m_tag,
    output wire              m_error
);
    localparam int HW = DW / 2;
    localparam int HK = DW / 16;

    reg  phase;                                    // 1 = 正在送当前宽拍的高半
    wire wide   = (s_tag == TAG_W'(WIDE_TAG));
    wire has_hi = |s_keep[DW/8-1:HK];
    wire split  = !wide && has_hi;

    assign m_valid = s_valid;
    assign m_data  = phase ? {{HW{1'b0}}, s_data[DW-1:HW]} : s_data;
    assign m_keep  = phase ? {{HK{1'b0}}, s_keep[DW/8-1:HK]}
                   : (wide ? s_keep : {{HK{1'b0}}, s_keep[HK-1:0]});
    assign m_last  = (split && !phase) ? 1'b0 : s_last;
    assign m_tag   = s_tag;
    assign m_error = s_error;
    assign s_ready = m_ready && (!split || phase);

    always @(posedge clk) begin
        if (rst)                              phase <= 1'b0;
        else if (s_valid && m_ready && split) phase <= !phase;
    end
endmodule
`default_nettype wire
