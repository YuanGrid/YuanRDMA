// roce_bas_mon.sv
// BAS 通路观测（只读旁路，不影响数据通路）。pcie_clk 域监听打包总线的五个 AXI 通道：
//  - 5 个握手计数器（格雷码跨到 core 域）：AW 握手、W 末拍握手、B、AR 握手、R 末拍
//  - sticky 位：各通道"出现过 valid / 出现过握手 / 出现过错误响应"，CSR 写 1 清
//  - live 位：当前 valid/ready 电平（两级同步，仅用于看是否卡在某一侧）
// 判定（DMA 自测一次后）：AW_HS == W_LAST_HS == B，AR_HS == R_LAST；
// 有 valid 无握手 = MCDMA 不接收；有握手无响应 = 主机侧/completion 丢失；RESP!=0 = 地址/权限错。
`default_nettype none
`timescale 1ns/1ps
`include "roce_bas_if.vh"
module roce_bas_mon (
    input  wire                   pcie_clk,
    input  wire                   pcie_rst,
    input  wire                   clk,
    input  wire                   rst,
    input  wire [`BAS_M2S_W-1:0]  bas_m2s,
    input  wire [`BAS_S2M_W-1:0]  bas_s2m,
    input  wire                   sticky_clear,       // clk 域单拍
    output wire [31:0]            count_aw,
    output wire [31:0]            count_w_last,
    output wire [31:0]            count_b,
    output wire [31:0]            count_ar,
    output wire [31:0]            count_r_last,
    output reg  [10:0]            sticky,             // clk 域
    output reg  [7:0]             live,               // clk 域
    // 调试：未完成 AR 数 = AR_HS - R_LAST（饱和 255）。跨页请求一个 AR 占两拍 RLAST，
    // 所以正常情况下 R_LAST >= AR_HS；这个值长期 > 0 就是有读请求没回来。
    output wire  [7:0]            debug_ar_outstanding,
    // 调试：{BRESP!=OKAY 见过, RRESP!=OKAY 见过, 见过 AR 握手, 见过 R last}，pcie 域内锁存
    output wire  [3:0]            debug_resp_sticky
);
    wire awvalid = bas_m2s[`BAS_M2S_AWVALID];
    wire awready = bas_s2m[`BAS_S2M_AWREADY];
    wire wvalid  = bas_m2s[`BAS_M2S_WVALID];
    wire wready  = bas_s2m[`BAS_S2M_WREADY];
    wire wlast   = bas_m2s[`BAS_M2S_WLAST];
    wire bvalid  = bas_s2m[`BAS_S2M_BVALID];
    wire bready  = bas_m2s[`BAS_M2S_BREADY];
    wire [1:0] bresp = bas_s2m[`BAS_S2M_BRESP];
    wire arvalid = bas_m2s[`BAS_M2S_ARVALID];
    wire arready = bas_s2m[`BAS_S2M_ARREADY];
    wire rvalid  = bas_s2m[`BAS_S2M_RVALID];
    wire rready  = bas_m2s[`BAS_M2S_RREADY];
    wire rlast   = bas_s2m[`BAS_S2M_RLAST];
    wire [1:0] rresp = bas_s2m[`BAS_S2M_RRESP];

    // 计数器：B6418 起两级——第一级把总线上的原始 valid/ready/last 原样采下（无逻辑，可贴着 MCDMA 放），
    // 第二级算握手脉冲，再进计数器。B6417 只有一级（直接 valid && ready），Hyper-Retiming 把这级
    // 寄存器挪到 MCDMA 旁边（i22~C8_X217_Y179），计数器的进位链就挂在跨芯片的走线上，
    // u_cnt_w 29 个端点 −0.117、b_hs −0.068（roce-optimization-log §44.7）。监视通路晚一拍无所谓。
    reg awvalid_q, awready_q, wvalid_q, wready_q, wlast_q, bvalid_q, bready_q;
    reg arvalid_q, arready_q, rvalid_q, rready_q, rlast_q;
    reg [1:0] bresp_q, rresp_q;
    always @(posedge pcie_clk) begin
        awvalid_q <= awvalid;  awready_q <= awready;
        wvalid_q  <= wvalid;   wready_q  <= wready;   wlast_q <= wlast;
        bvalid_q  <= bvalid;   bready_q  <= bready;   bresp_q <= bresp;
        arvalid_q <= arvalid;  arready_q <= arready;
        rvalid_q  <= rvalid;   rready_q  <= rready;   rlast_q <= rlast;   rresp_q <= rresp;
    end
    reg aw_hs, w_last_hs, b_hs, ar_hs, r_last_hs;
    always @(posedge pcie_clk) begin
        aw_hs     <= awvalid_q && awready_q;
        w_last_hs <= wvalid_q && wready_q && wlast_q;
        b_hs      <= bvalid_q && bready_q;
        ar_hs     <= arvalid_q && arready_q;
        r_last_hs <= rvalid_q && rready_q && rlast_q;
    end
    roce_gray_cnt u_cnt_aw (.source_clk(pcie_clk), .source_rst(pcie_rst), .source_increment(aw_hs),     .dest_clk(clk), .dest_count(count_aw));
    roce_gray_cnt u_cnt_w  (.source_clk(pcie_clk), .source_rst(pcie_rst), .source_increment(w_last_hs), .dest_clk(clk), .dest_count(count_w_last));
    roce_gray_cnt u_cnt_b  (.source_clk(pcie_clk), .source_rst(pcie_rst), .source_increment(b_hs),      .dest_clk(clk), .dest_count(count_b));
    roce_gray_cnt u_cnt_ar (.source_clk(pcie_clk), .source_rst(pcie_rst), .source_increment(ar_hs),     .dest_clk(clk), .dest_count(count_ar));
    roce_gray_cnt u_cnt_r  (.source_clk(pcie_clk), .source_rst(pcie_rst), .source_increment(r_last_hs), .dest_clk(clk), .dest_count(count_r_last));

    // sticky / live 的源在 pcie_clk 域只做寄存，全部电平信号，core 域两级同步后再累积
    reg [10:0] event_pcie;
    reg [7:0]  live_pcie;
    always @(posedge pcie_clk) begin
        // 同样用第一级采样值（B6418），不再直接挂在 MCDMA 的组合输出上
        event_pcie <= {rvalid_q && rresp_q != 2'b00, rvalid_q && rlast_q, rvalid_q, arvalid_q && arready_q, arvalid_q,
                       bvalid_q && bresp_q != 2'b00, bvalid_q, wvalid_q && wready_q, wvalid_q, awvalid_q && awready_q, awvalid_q};
        live_pcie  <= {rvalid_q, arready_q, arvalid_q, bvalid_q, wready_q, wvalid_q, awready_q, awvalid_q};
    end

    // 单拍事件跨到慢时钟可能丢，所以 pcie 域先做 sticky，再同步；clear 用电平握手
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    reg [1:0]  clear_sync;
    reg        clear_req;
    reg [10:0] sticky_pcie;
    always @(posedge pcie_clk) begin
        clear_sync <= {clear_sync[0], clear_req};
        if (pcie_rst || clear_sync[1]) sticky_pcie <= '0;
        else                           sticky_pcie <= sticky_pcie | event_pcie;
    end

    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    reg [18:0] status_sync1, status_sync2;
    reg [7:0]  clear_hold;
    always @(posedge clk) begin
        status_sync1 <= {live_pcie, sticky_pcie};
        status_sync2 <= status_sync1;
        sticky       <= status_sync2[10:0];
        live         <= status_sync2[18:11];
        // clear 电平保持 255 个 core 周期（2.5 us），pcie_clk（500 MHz）一定能采到
        if (rst)                    clear_hold <= '0;
        else if (sticky_clear)      clear_hold <= 8'hff;
        else if (clear_hold != 0)   clear_hold <= clear_hold - 8'd1;
        clear_req <= (clear_hold != 0);
    end
    // ---------------- 未完成 AR 数（core 域的格雷码计数在此相减，饱和到 255）
    // 跨页请求一个 AR 占两拍 RLAST，所以正常情况下 R_LAST >= AR_HS。这个差值长期 > 0
    // 且不动，就是有条读请求的 R 数据一直没回来（2026-10-25 卡死现场是 67）。
    wire [31:0] ar_outstanding = (count_ar > count_r_last) ? (count_ar - count_r_last) : 32'd0;
    assign debug_ar_outstanding = (ar_outstanding > 32'd255) ? 8'hFF : ar_outstanding[7:0];

    reg  [3:0] resp_sticky_pcie;
    always @(posedge pcie_clk) begin
        if (pcie_rst)                       resp_sticky_pcie <= 4'd0;
        else if (sticky_clear)              resp_sticky_pcie <= 4'd0;
        else                                resp_sticky_pcie <= resp_sticky_pcie |
            {bvalid_q && bresp_q != 2'b00, rvalid_q && rresp_q != 2'b00,
             arvalid_q && arready_q, rvalid_q && rready_q && rlast_q};
    end
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    reg  [3:0] resp_sticky_sync1, resp_sticky_sync2;
    always @(posedge clk) begin
        resp_sticky_sync1 <= resp_sticky_pcie;
        resp_sticky_sync2 <= resp_sticky_sync1;
    end
    assign debug_resp_sticky = resp_sticky_sync2;
endmodule
`default_nettype wire
