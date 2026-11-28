// roce_wr_pack.sv
// DMA 写数据拼拍：客户端每拍 IN_W/8 字节 → 写通路每拍 OUT_W/8 字节。
//   - 把 N = OUT_W/IN_W 个连续输入拍按字节序拼成一个输出拍（第 k 个输入拍放在 bit[k*IN_W +: IN_W]）；
//   - s_last 那一拍无论凑没凑满都立刻送出，没凑到的高位槽补 0。
// 于是输出拍序列就是「同一字节流按 OUT_W/8 字节切拍」的结果：每个写请求恰好
// ceil(len / (OUT_W/8)) 拍，第 0 字节在首拍 bit[7:0]，与 roce_dma_arb / roce_dma 的 WR_DW 约定一致。
// 末拍超出 len 的字节由 roce_dma 按请求长度算的 wstrb 屏蔽，这里不管。
//
// s_last 必须标出**每个写请求**的末拍（请求之间不能跨拍拼）。引擎里的用法：
//   - dma_test（客户端 3）：写数据就是 roce_dma_rd_narrow 之后的 128 B 窄读拍，last 取同拍的读 last；
//   - resp / req（客户端 0/1）在 RX_DW < WR_DW 时：写数据就是 RX payload 拍，last 取 rx_payload_last。
//
// IN_W == OUT_W 时纯连线，与不经过本模块逐位等价（s_last、clk、rst 不用）。
// N > 1 时 s_ready 在「本拍不送出」时恒 1（拍被收进暂存），送出时等于 m_ready；
// 暂存只有 N-1 个槽，不需要复位，只有槽下标 idx 复位。
`default_nettype none
`timescale 1ns/1ps
module roce_wr_pack #(
    parameter int IN_W  = 1024,
    parameter int OUT_W = 2048
)(
    input  wire              clk,
    input  wire              rst,
    input  wire              s_valid,
    output wire              s_ready,
    input  wire [IN_W-1:0]   s_data,
    input  wire              s_last,
    output wire              m_valid,
    input  wire              m_ready,
    output wire [OUT_W-1:0]  m_data
);
    localparam int N = OUT_W / IN_W;

    initial begin
        if (IN_W <= 0 || OUT_W < IN_W || (OUT_W % IN_W) != 0 || (N & (N - 1)) != 0)
            $fatal(1, "roce_wr_pack: OUT_W=%0d 必须是 IN_W=%0d 的 2 的幂倍", OUT_W, IN_W);
    end

    genvar k;
    generate
        if (IN_W <= 0 || OUT_W < IN_W || (OUT_W % IN_W) != 0 || (N & (N - 1)) != 0) begin : g_bad
            // 非法参数：上面的 initial $fatal 只在仿真零时刻 / Quartus 分析期生效，lint 不执行 initial。
            // 例化一个不存在、名字即说明的模块，让 lint 与综合都在展开期直接报错。
            roce_wr_pack_OUT_W_must_be_power_of_2_multiple_of_IN_W u_param_error ();
        end else if (N == 1) begin : g_pass
            assign m_valid = s_valid;
            assign s_ready = m_ready;
            assign m_data  = s_data;
        end else begin : g_pack
            localparam int IW = $clog2(N);
            reg  [IW-1:0]            idx;              // 本拍落在输出拍的第几个槽
            reg  [IN_W-1:0]          acc [N-1];        // 已收的低位槽（槽 N-1 不暂存：到它必送出）
            wire                     emit = s_last || (idx == IW'(N - 1));

            assign m_valid = s_valid && emit;
            assign s_ready = emit ? m_ready : 1'b1;

            // 槽 k：k < idx 取暂存，k == idx 取本拍输入，k > idx 补 0
            for (k = 0; k < N; k = k + 1) begin : g_slot
                if (k < N - 1) begin : g_lo
                    assign m_data[k*IN_W +: IN_W] = (IW'(k) <  idx) ? acc[k] :
                                                    (IW'(k) == idx) ? s_data : {IN_W{1'b0}};
                    always @(posedge clk)
                        if (s_valid && !emit && idx == IW'(k)) acc[k] <= s_data;
                end else begin : g_hi
                    assign m_data[k*IN_W +: IN_W] = (IW'(k) == idx) ? s_data : {IN_W{1'b0}};
                end
            end

            always @(posedge clk) begin
                if (rst)                    idx <= '0;
                else if (s_valid && s_ready) idx <= emit ? '0 : idx + IW'(1);
            end
        end
    endgenerate
endmodule
`default_nettype wire
