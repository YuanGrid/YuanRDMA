// roce_dma.sv
// RoCE 引擎的主机 DMA：core 时钟域的读/写请求接口 -> MCDMA BAS（AXI4 slave，pcie_clk 域）。
// - 读：单 ARID，读回按序；按读回 FIFO 空间做信用控制，BAS 不会被 rready 反压。
// - 写：单 AWID，同 ID 写按序完成（payload 写先于 CQE 写可见）；每请求一个 dma_write_complete。
// - 每个请求 1..4096 字节，最多跨一个 4 KB 页：addr 为首字节物理地址，page1 为下一页的
//   物理页地址（低 12 位忽略，不跨页时无用）。跨页时拆成两个 AXI burst，对齐模块仍视为
//   一个连续请求（页内偏移在 VA/PA 中相同，128 B 拍在两页间首尾相接）。
`default_nettype none
`timescale 1ns/1ps
`include "roce_bas_if.vh"
module roce_dma #(
    parameter int TAG_W = 4,
    // 读数据（core 侧）位宽：1024 或 2048。
    parameter int RD_DW = 1024,
    // 写数据（core 侧）位宽：1024 或 2048。BAS 侧恒 1024 位、AWSIZE=7，见下面「写数据位宽」。
    parameter int WR_DW = 1024
)(
    input  wire                   clk,
    input  wire                   rst,
    input  wire                   pcie_clk,
    input  wire                   pcie_rst,
    // BAS 打包总线（pcie_clk 域）
    output wire [`BAS_M2S_W-1:0]  bas_m2s,
    input  wire [`BAS_S2M_W-1:0]  bas_s2m,
    // 读请求
    input  wire                   dma_read_request_valid,
    output wire                   dma_read_request_ready,
    input  wire  [63:0]           dma_read_request_address,
    input  wire  [63:0]           dma_read_request_page1,
    input  wire  [12:0]           dma_read_request_length,
    input  wire  [TAG_W-1:0]      dma_read_request_tag,
    // 读数据（每请求以 last 结束）
    output wire                   dma_read_valid,
    input  wire                   dma_read_ready,
    output wire  [RD_DW-1:0]      dma_read_data,
    output wire  [RD_DW/8-1:0]    dma_read_keep,
    output wire                   dma_read_last,
    output wire  [TAG_W-1:0]      dma_read_tag,
    output wire                   dma_read_error,
    // 写请求 + 数据
    input  wire                   dma_write_request_valid,
    output wire                   dma_write_request_ready,
    input  wire  [63:0]           dma_write_request_address,
    input  wire  [63:0]           dma_write_request_page1,
    input  wire  [12:0]           dma_write_request_length,
    // 写数据：每请求 ceil(length/(WR_DW/8)) 拍，payload 第 i 字节在首拍起的 bit[8i+7:8i]
    input  wire                   dma_write_valid,
    output wire                   dma_write_ready,
    input  wire  [WR_DW-1:0]      dma_write_data,
    // 写完成（每请求一拍，按序）
    output wire                   dma_write_complete,
    output wire                   dma_write_complete_error,
    // 调试：[9:0] read_credit；[10] read_second_phase；[11] ar_fifo 非空；
    //       [12] read_meta 非空；[13] read_beat_valid。布局见 roce_debug.sv 0x0574。
    // read_credit 是最关键的：它减到不足以覆盖一个新请求的拍数时，AR 就永远发不出去，
    // 表现为「读请求不再发出、计数全冻结」，且软复位之前不会自愈。
    output wire  [13:0]           debug_state
);
    // ------------------------------------------------------------ 读数据位宽
    // RD_DW=2048：core 250 MHz 每拍要 256 B，而 BAS R 是 1024 bit @ 500 MHz（每 core 拍 2 个 R 拍）。
    // 做法：**读请求按 256 B 对齐、拍数恒为偶数**，于是每个 AXI burst 的 R 拍成对出现，pcie 域把
    // 相邻两拍拼成一个 2048 位条目写进 R FIFO（拼对永不跨 burst，也就永不跨请求，没有半对等待）。
    // rd_align 在 core 域按 256 B 一拍对齐，起点偏移 s = addr[7:0]。
    //   代价：起点不在 256 B 边界时最多多读 128 B（同一 256 B 块内，绝不跨 4 KB 页，IOMMU 安全）；
    //   1 KB 对齐 payload 不多读。
    // RD_DW=1024：与改动之前逐位等价（128 B 对齐、R FIFO 1024 位、每次弹 1 拍）。
    localparam int PAIR   = RD_DW / 1024;             // 每个 R FIFO 条目含几个 R 拍：1 / 2
    localparam int LA     = $clog2(RD_DW / 8);        // 对齐粒度位数：7（128 B）/ 8（256 B）
    localparam int READ_FIFO_DEPTH   = 512;           // 以 R 拍计（与 PAIR 无关，RAM 位数不变）
    localparam int READ_CREDITS = READ_FIFO_DEPTH - 32;

    // ------------------------------------------------------------ 写数据位宽（WR_DW）
    // WR_DW=2048：core 250 MHz 每拍收 256 B，BAS W 是 1024 bit @ 500 MHz（每 core 拍 2 个 W 拍），带宽相等。
    // 做法（读侧拼对的镜像）：AW / B 全部照旧按 128 B 拍生成，wr_align 在 core 域一拍出两个 128 B 半拍
    // （每半拍各带 last、高半拍另带 valid），W FIFO 2048 位入，pcie 域每个条目拆成 1~2 个 W 拍。
    // 头拍拆分 / 跨页使 burst 边界可能落在条目中间、请求总拍数为奇数时末条目只有低半拍，
    // 这些都由逐半拍的 last / valid 表达，WLAST 与每个 AW 的 AWLEN 逐拍对齐。
    // WR_DW=1024：与改动之前逐位等价（W FIFO 1024 位、每条目 1 个 W 拍）。
    localparam int WR_H   = WR_DW / 1024;             // 每个 W FIFO 条目含几个 W 拍：1 / 2
    localparam int W_USER_W = (WR_H == 2) ? 2 : 1;    // W FIFO 的 tuser：{高半拍 valid, 高半拍 last}

    // ------------------------------------------------------------ 写请求在途深度（B6397）
    // AW FIFO 与 B 计数 FIFO 原来都是 32/64，1 KB MTU 下每包一个写请求、约 8 拍一个，
    // 只够缓冲 256~512 拍。PCIe 写响应（B）的往返远不止这个量级，于是
    // dma_write_request_ready 会周期性掉下来，roce_resp 卡在 MAIN_WRITE_REQUEST 等它。
    // 板上实测（B6396，1 MB write_bw 服务端，采样 8 s）：
    //   WRITE_DATA 8.04 拍（理论 8.0，搬运已最优）
    //   WRITE_REQUEST 2.61 拍、TRANSLATE_WAIT 1.50 拍 ← 全在等请求受理
    //   resp 占空 69.4%、rx_disp busy 81.9%、staging 均值 151 峰值贴 511
    // 即：**不是搬运慢，是请求发不出去导致上游积压**。
    //
    // 加深到 256/512：M20K 占用只增约 8 个（AW 72 bit × 256 ≈ 2 个，B 计数 1 bit × 512 ≈ 1 个），
    // 当前 28%（3,697/13,272）余量充足。不改任何状态机与握手语义，只改缓冲深度。
    localparam int WRITE_AW_FIFO_DEPTH = 256;
    localparam int WRITE_B_FIFO_DEPTH  = 512;

    // ------------------------------------------------------------ pcie_clk 侧 FIFO 的 RAM 读流水（B6400）
    // B6399 STA：pld_clkout（500 MHz）setup −0.263 / TNS −388.674，违例全在 u_ar_fifo / u_w_fifo
    // 的 M20K → m_axis_pipe_reg：0 级逻辑，M20K uTco 1.330 ns + 走线 0.643 ns，2 ns 周期装不下。
    // 2 lane 时同类路径擦边能过，4 lane 后这些 FIFO 从 2 份变 4 份、布局分散，就全面违例。
    // RAM_PIPELINE=2：M20K 输出先进一级寄存器（可吸进 RAM 块内部的输出寄存器），再走线。
    // 代价：读出多 1 拍延迟；握手语义、深度、读信用（READ_CREDITS）都不变。
    localparam int PCIE_FIFO_RAM_PIPELINE = 2;
    // B6419：pcie 侧出口 FIFO（u_ar_fifo / u_aw_fifo / u_w_fifo）打开 OUTPUT_FIFO_ENABLE。
    // B6418 pld_clkout：hub 的 w_skid_valid（寄存器）→ lane WREADY → u_w_fifo 的 M20K 读使能 / 输出寄存器使能，
    // 92 个端点（lane2 占 80，−0.102）；u_w_fifo 的 m_terminate_frame → m_axis_tvalid → hub w_cur（−0.207，4 级）；
    // AW/AR 也是 hub 入口握手 → lane FIFO 读使能的环。打开后 RAM 读与流水寄存器不再挂 m_axis_tready，
    // 由 FIFO 内部一个 16 深 MLAB 输出 FIFO 接住，hub 的 ready 只驱动输出 FIFO 的读指针与输出寄存器。
    // 代价：每 lane 多 1~2 拍固定延迟（pcie_clk 500 MHz）+ 约 1.2 K 位 MLAB；握手语义不变。
    localparam int PCIE_FIFO_OUTPUT_FIFO = 1;

    // ------------------------------------------------------------ 读
    // 页内：起点 128 B 对齐偏移 o0，终点 e = addr[11:0] + transfer_length；e > 4096 则跨页
    wire [13:0] read_end_in_page     = {2'd0, dma_read_request_address[11:0]} + {1'b0, dma_read_request_length};
    wire        read_crosses_page     = read_end_in_page > 14'd4096;
    // ------------------------------------------------------------ 拍数直接算「beat-1」（B6503，簇 C）
    // **动机**：B6502 STA 有 2 条 core 违例（−0.218 / −0.222）走
    //     u_tx|issue_job.physical_address0[0] → u_dma|u_ar_fifo|mem_rtl_0（M20K 写口）。
    // 原始链路是 7 级逻辑、5 个算术级：
    //   addr[6:0] → read_end_in_page(+len) → +127 → >>7 → −addr[11:7] → 跨页 mux → −1 → RAM。
    // 而 AXI 的 ARLEN 本来就等于「拍数−1」，FIFO 里再减一次纯属把常数折叠留到了最后。
    //
    // 三条恒等式（下面每一个都用穷举核对过：addr 0..4095 × len 1..299 ∪ {1024,2048,3000,4095,4096}，
    // 非跨页 1 186 375 例、跨页 58 809 例，全部相等）：
    //   非跨页：beats = ceil((o0 + len)/128)，于是
    //           beats−1 = (o0 + len − 1) >> 7          （只吃 addr[6:0]，跟 addr[11:7] 无关）
    //   跨页第一段：beats−1 = 31 − addr[11:7] = ~addr[11:7]（5 位取反，零级逻辑）
    //   跨页第二段：beats−1 = (addr[11:0] + len − 4097) >> 7
    // 这样 ARLEN 字段少掉 **3 个加法级 + 1 个减法级**，且 addr[6:0] 只进一个加法器（原来进 +len 和 −addr[11:7] 两处）。
    //
    // 与原来等价的前提：o0 + len ≤ 4096（非跨页的定义）时 beats ≥ 1，故 beats−1 ≥ 0 不会下溢；
    // 跨页第二段 len ≥ 4097 − addr[11:0] 保证被减数非负。**零长度读在原实现里就是走不进来的**
    // （roce_tx 的 issue_needs_read / roce_resp 的两处 (payload_length != 0) 守卫），故不额外加钳位，
    // 保持与原实现逐位一致的语义（原实现在 len=0 时也会给出 beats=0，即 ARLEN=63，不是本次要改的行为）。
    // 位宽：o0+len 最大 127+4096 = 4223 → 13 位；o12+len 最大 4095+4096 = 8191 → 13 位。
    // 两个常量减法都在 13 位上做，否则被减数先被截断成 12 位会下溢（第一版就踩了这个，
    // trace 里跨页第二段放出 arlen=32 即 33 拍的假 burst）。
    // PAIR=2 时同一套恒等式按 256 B 粒度算「块数−1」，再换成 R 拍数−1 = 2×(块数−1)+1。
    wire [12:0] read_non_cross_m1     = (13'(13'(dma_read_request_address[LA-1:0]) + {1'b0, dma_read_request_length}) - 13'd1) >> LA;
    wire [12:0] read_cross_second_m1  = (13'(dma_read_request_address[11:0] + {1'b0, dma_read_request_length}) - 13'd4097) >> LA;
    // 跨页第一段的 ~addr[11:7] 必须显式零扩展（{1'b0, ~addr[11:7]}）。
    // 写成 6'(~addr[11:7]) 时 Verilator 5.032 会把操作数先扩到 6 位再取反，addr[11:7]=31 得到 6'h20=32；
    // 写成 ~addr[11:7] 同样中招（同见本机隔离用例 /tmp/bt/t2.sv：v1/v4=32，v2/v5=0）。
    wire [5:0]  read_first_blocks_m1  = read_crosses_page ? 6'({1'b0, ~dma_read_request_address[11:LA]}) : read_non_cross_m1[5:0];
    wire [5:0]  read_second_blocks_m1 = read_cross_second_m1[5:0];
    wire [5:0]  read_first_burst_m1   = (PAIR == 2) ? {read_first_blocks_m1[4:0], 1'b1}  : read_first_blocks_m1;
    wire [5:0]  read_second_burst_m1  = (PAIR == 2) ? {read_second_blocks_m1[4:0], 1'b1} : read_second_blocks_m1;
    wire [5:0]  read_ar_beats_m1      = read_second_phase ? read_second_burst_m1 : read_first_burst_m1;   // 直接进 AR FIFO
    // 信用记账仍用「拍数」而不是「beat−1」，且**保持原来的算式不动**：这条链的终点是 read_credit 寄存器，
    // 有一整拍余量（不在违例名单里），改它只会引入新的等价性风险。
    localparam int BLK = 1 << LA;                    // 128 / 256
    wire [5:0]  read_first_burst_blocks   = read_crosses_page ? 6'((4096 / BLK) - dma_read_request_address[11:LA])
                                                              : 6'(((read_end_in_page + 14'(BLK - 1)) >> LA) - dma_read_request_address[11:LA]);
    wire [5:0]  read_second_burst_blocks  = 6'((read_end_in_page - 14'd4096 + 14'(BLK - 1)) >> LA);
    wire [5:0]  read_first_burst_beats    = 6'(read_first_burst_blocks * PAIR);
    wire [5:0]  read_second_burst_beats   = 6'(read_second_burst_blocks * PAIR);
    wire [6:0]  read_total_beats = {1'b0, read_first_burst_beats} + (read_crosses_page ? {1'b0, read_second_burst_beats} : 7'd0);   // 1..33（PAIR=2：2..34）

    reg  [9:0]  read_credit;
    reg         read_second_phase;                 // 跨页请求已发出第一个 burst
    wire        ar_fifo_ready, read_meta_fifo_ready;
    // 2026-10-31（B6384，A3）：受理门限改用「单请求最多可能占用的拍数」这个常数，
    // 使 dma_read_request_ready 不再依赖由地址组合算出的 read_total_beats。
    //
    // 原来 (credit >= read_total_beats) 把一条超长的组合链串了起来：
    //   地址 → read_end_in_page → read_first_burst_beats → read_total_beats
    //        → 和 credit 比较 → ready → roce_tx 的 issue_take → roce_resp 的 out_psn
    // B6383 的 STA 里这条就是 core_clk 的关键路径（21 级逻辑、走线占 59%）。
    //
    // 安全性：MAX_READ_BEATS_PER_REQ = 33（4096 字节 + 128 B 对齐后的最坏情况，
    // 见 read_total_beats 的注释「1..33」）。用常数门限只会比原来**更保守**——
    // 任何原来会被受理的请求，现在要么仍被受理，要么因信用不足而晚一拍，
    // 绝不可能出现原来拦住、现在放行的情况，所以 R FIFO 不会因此溢出。
    // 代价：小请求（WQE 取指 64 B = 1~2 拍）在信用低于 33 时会多等，
    // 但 credit 只有降到 ~33 才触发，此时 480 深度的读 FIFO 已接近满、系统本就反压。
    // PAIR=2：4096 B + 255 B 偏移 → 17 个 256 B 块 = 34 拍。
    localparam int MAX_READ_BEATS_PER_REQ = (PAIR == 2) ? 34 : 33;
    wire        read_credit_ok = read_second_phase ||
                                 (read_credit >= 10'(MAX_READ_BEATS_PER_REQ));
    wire        read_ar_push = dma_read_request_valid && ar_fifo_ready && read_meta_fifo_ready &&
                             read_credit_ok;
    wire        read_request_done  = read_ar_push && (!read_crosses_page || read_second_phase);   // 请求完成（推元数据）
    assign dma_read_request_ready  = read_request_done;
    wire [63:0] read_ar_address  = read_second_phase ? {dma_read_request_page1[63:12], 12'd0} : {dma_read_request_address[63:LA], LA'(0)};

    always @(posedge clk) begin
        if (rst)             read_second_phase <= 1'b0;
        else if (read_request_done)    read_second_phase <= 1'b0;
        else if (read_ar_push) read_second_phase <= 1'b1;
    end

    wire        read_beat_valid, read_beat_ready, read_beat_error;
    wire [RD_DW-1:0] read_beat_data;
    wire        read_beat_pop   = read_beat_valid && read_beat_ready;

    always @(posedge clk) begin
        if (rst)
            read_credit <= 10'(READ_CREDITS);
        else
            read_credit <= read_credit - ((read_ar_push && !read_second_phase) ? {3'd0, read_total_beats} : 10'd0)
                                       + (read_beat_pop ? 10'(PAIR) : 10'd0);
    end

    wire [71:0] ar_fifo_data;
    wire        ar_fifo_valid;
    // B6402：ARREADY 打一拍再进 FIFO 出口。
    // B6401 STA：−0.049 那组 40 条违例起点是 MCDMA 内部的 aximm_ar_info_fifo_almost_full、
    // 终点是各 lane u_ar_fifo 的推入逻辑，走线占 79%——这是**反压链**，不是数据通路
    // （MCDMA 的"AR 队列几乎满"要一路扇出到 4 个 lane 的 FIFO 出口才能停下推入）。
    // 在 ready 环路上直接加深 FIFO 没有用（只会让"满了"更晚传到本端），但 ready 是慢变量，
    // 打一拍完全不影响功能：AR 通道本来就靠 read_credit 保证不过冲，
    // 晚一拍只是让本端多排一个请求进 FIFO，而 FIFO 深度 32 + 信用余量 32 足够吸收。
    wire        bas_arready = bas_s2m[`BAS_S2M_ARREADY];

    axis_async_fifo #(
        .DEPTH(32), .DATA_WIDTH(72), .KEEP_ENABLE(0), .LAST_ENABLE(0), .USER_ENABLE(0),
        .RAM_PIPELINE(PCIE_FIFO_RAM_PIPELINE), .OUTPUT_FIFO_ENABLE(PCIE_FIFO_OUTPUT_FIFO)
    ) u_ar_fifo (
        .s_clk(clk), .s_rst(rst),
        .s_axis_tdata({2'd0, read_ar_beats_m1, read_ar_address}),
        .s_axis_tkeep('0), .s_axis_tvalid(read_ar_push), .s_axis_tready(ar_fifo_ready),
        .s_axis_tlast(1'b1), .s_axis_tid(8'd0), .s_axis_tdest(8'd0), .s_axis_tuser(1'b0),
        .m_clk(pcie_clk), .m_rst(pcie_rst),
        .m_axis_tdata(ar_fifo_data), .m_axis_tkeep(), .m_axis_tvalid(ar_fifo_valid),
        .m_axis_tready(bas_arready), .m_axis_tlast(), .m_axis_tid(), .m_axis_tdest(), .m_axis_tuser(),
        .s_pause_req(1'b0), .s_pause_ack(), .m_pause_req(1'b0), .m_pause_ack(),
        .s_status_depth(), .s_status_depth_commit(), .s_status_overflow(),
        .s_status_bad_frame(), .s_status_good_frame(),
        .m_status_depth(), .m_status_depth_commit(), .m_status_overflow(),
        .m_status_bad_frame(), .m_status_good_frame()
    );

    // 读元数据（core 域同步 FIFO，用 axis_async_fifo 同时钟）
    wire [LA-1:0]    read_meta_address_low;
    wire [12:0]      read_meta_length;
    wire [TAG_W-1:0] read_meta_tag;
    wire             read_meta_valid, read_meta_ready;
    axis_async_fifo #(
        .DEPTH(64), .DATA_WIDTH(13+LA+TAG_W), .KEEP_ENABLE(0), .LAST_ENABLE(0), .USER_ENABLE(0)
    ) u_meta_fifo (
        .s_clk(clk), .s_rst(rst),
        .s_axis_tdata({dma_read_request_tag, dma_read_request_length, dma_read_request_address[LA-1:0]}),
        .s_axis_tkeep('0), .s_axis_tvalid(read_request_done), .s_axis_tready(read_meta_fifo_ready),
        .s_axis_tlast(1'b1), .s_axis_tid(8'd0), .s_axis_tdest(8'd0), .s_axis_tuser(1'b0),
        .m_clk(clk), .m_rst(rst),
        .m_axis_tdata({read_meta_tag, read_meta_length, read_meta_address_low}), .m_axis_tkeep(), .m_axis_tvalid(read_meta_valid),
        .m_axis_tready(read_meta_ready), .m_axis_tlast(), .m_axis_tid(), .m_axis_tdest(), .m_axis_tuser(),
        .s_pause_req(1'b0), .s_pause_ack(), .m_pause_req(1'b0), .m_pause_ack(),
        .s_status_depth(), .s_status_depth_commit(), .s_status_overflow(),
        .s_status_bad_frame(), .s_status_good_frame(),
        .m_status_depth(), .m_status_depth_commit(), .m_status_overflow(),
        .m_status_bad_frame(), .m_status_good_frame()
    );

    // R 通道 -> core
    wire bas_rvalid = bas_s2m[`BAS_S2M_RVALID];
    wire              r_fifo_push;
    wire [RD_DW-1:0]  r_fifo_data;
    wire              r_fifo_error;
    generate
        if (PAIR == 2) begin : gen_r_pair
            // pcie 域拼对：偶数拍先存，奇数拍到时连同存下的一起写一个 2048 位条目。
            // 每个 burst 的拍数恒为偶数（见上面 read_*_burst_m1 的最低位恒 1），所以拼对边界
            // 与 burst 边界重合，r_lo_valid 在 burst 之间恒为 0，不会有半对滞留。
            reg  [1023:0] r_lo_data;
            reg           r_lo_valid, r_lo_error;
            always @(posedge pcie_clk) begin
                if (pcie_rst) begin
                    r_lo_valid <= 1'b0;
                end else if (bas_rvalid) begin
                    r_lo_valid <= !r_lo_valid;
                    if (!r_lo_valid) begin
                        r_lo_data  <= bas_s2m[`BAS_S2M_RDATA];
                        r_lo_error <= (bas_s2m[`BAS_S2M_RRESP] != 2'b00);
                    end
                end
            end
            assign r_fifo_push  = bas_rvalid && r_lo_valid;
            assign r_fifo_data  = {bas_s2m[`BAS_S2M_RDATA], r_lo_data};
            assign r_fifo_error = r_lo_error || (bas_s2m[`BAS_S2M_RRESP] != 2'b00);
        end else begin : gen_r_single
            assign r_fifo_push  = bas_rvalid;
            assign r_fifo_data  = bas_s2m[`BAS_S2M_RDATA];
            assign r_fifo_error = (bas_s2m[`BAS_S2M_RRESP] != 2'b00);
        end
    endgenerate
    axis_async_fifo #(
        .DEPTH(READ_FIFO_DEPTH / PAIR), .DATA_WIDTH(RD_DW), .KEEP_ENABLE(0), .LAST_ENABLE(0),
        .USER_ENABLE(1), .USER_WIDTH(1)
    ) u_r_fifo (
        .s_clk(pcie_clk), .s_rst(pcie_rst),
        .s_axis_tdata(r_fifo_data),
        .s_axis_tkeep('0), .s_axis_tvalid(r_fifo_push), .s_axis_tready(),
        .s_axis_tlast(1'b1), .s_axis_tid(8'd0), .s_axis_tdest(8'd0),
        .s_axis_tuser(r_fifo_error),
        .m_clk(clk), .m_rst(rst),
        .m_axis_tdata(read_beat_data), .m_axis_tkeep(), .m_axis_tvalid(read_beat_valid),
        .m_axis_tready(read_beat_ready), .m_axis_tlast(), .m_axis_tid(), .m_axis_tdest(),
        .m_axis_tuser(read_beat_error),
        .s_pause_req(1'b0), .s_pause_ack(), .m_pause_req(1'b0), .m_pause_ack(),
        .s_status_depth(), .s_status_depth_commit(), .s_status_overflow(),
        .s_status_bad_frame(), .s_status_good_frame(),
        .m_status_depth(), .m_status_depth_commit(), .m_status_overflow(),
        .m_status_bad_frame(), .m_status_good_frame()
    );

    roce_dma_rd_align #(.TAG_W(TAG_W), .DW(RD_DW)) u_rd_align (
        .clk(clk), .rst(rst),
        .meta_valid(read_meta_valid), .meta_ready(read_meta_ready), .meta_address_low(read_meta_address_low), .meta_length(read_meta_length), .meta_tag(read_meta_tag),
        .in_valid(read_beat_valid), .in_ready(read_beat_ready), .in_data(read_beat_data), .in_error(read_beat_error),
        .out_valid(dma_read_valid), .out_ready(dma_read_ready), .out_data(dma_read_data), .out_keep(dma_read_keep),
        .out_last(dma_read_last), .out_tag(dma_read_tag), .out_error(dma_read_error)
    );

    // ------------------------------------------------------------ 写
    wire [13:0] write_end_in_page     = {2'd0, dma_write_request_address[11:0]} + {1'b0, dma_write_request_length};
    wire        write_crosses_page     = write_end_in_page > 14'd4096;
    // B6393：零长度时 write_end_in_page == address[11:0]，非跨页分支计算结果为 0 → aw_fifo
    // 里 AWLEN = beats-1 = 6'h3f（63 拍），BAS 等 64 拍 W 数据但 W 一拍不发 → 死锁。
    // 钳到 1：退化成一拍全 0 wstrb 的合法 AXI 写，对长度 ≥1 是等价变换。
    wire [5:0]  write_first_burst_beats    = write_crosses_page ? 6'(32 - dma_write_request_address[11:7]) :
                                             (6'(((write_end_in_page + 14'd127) >> 7) - dma_write_request_address[11:7]) == 6'd0) ? 6'd1
                                           : 6'(((write_end_in_page + 14'd127) >> 7) - dma_write_request_address[11:7]);
    wire [5:0]  write_second_burst_beats    = 6'((write_end_in_page - 14'd4096 + 14'd127) >> 7);
    // 头拍拆分（2026-11-24）：起始地址不按 128 B 对齐、且首页不止一拍时，首拍单独发一个 1 拍 burst，
    // 首页余下的拍再发一个对齐 burst（跨页时第二页照旧再一个）。一个请求因此最多 3 个 AW / 3 个 B。
    // 原因（上板实测，B0116）：PCIe BAS 对「多拍 burst 的首拍 wstrb 低位为 0」不按 wstrb 屏蔽，
    // 把首拍里地址之前的 addr[6:0] 个字节用它内部缓冲的旧数据一并写出——接收缓冲之前的主机内存被改写
    // （malloc 的块头被冲掉，ucmatose 在 free 时崩）。单拍 burst 的部分 wstrb、多拍 burst 末拍的部分
    // wstrb 上板都正确，所以只把首拍拆出去。地址对齐的写（perftest/NCCL 缓冲、CQE）完全不受影响。
    wire        write_head_split = (dma_write_request_address[6:0] != 7'd0) && (write_first_burst_beats > 6'd1);
    // 0 = 首个 burst（头拍，或不拆分时的整段首页）；1 = 首页余下（只在头拍拆分时有）；2 = 第二页
    reg  [1:0]  write_phase;
    // B0121 时序：请求在**首个 burst 入队那拍**就从上游取走（dma_write_request_ready = write_request_start），
    // 首页余下 / 第二页这两个后续 burst 用下面在那一拍锁存的字段发，不再回头读上游。
    //
    // 原来请求要等最后一个 burst 才 ready，ready 里带着「是不是最后一个」，而这要从请求现算跨页与头拍拆分
    // （end_in_page、+127、−addr[11:7] 三级加法）。B0120（2048 位）core_clk 违例环之一就是它：
    // engine 的 u_write_request_skid.main_data → 三级加法 → write_head_split → write_last_burst
    // → write_request_done（= ready）→ 回到同一个 skid 的装载使能（扇出 141 位），−0.018，近临界 118 条。
    // 现在 ready 只看 valid、aw_space_q、write_align_ready、bresp_count_fifo_ready 和 phase，与请求内容无关，
    // 环上没有数据通路；跨页 / 拆分 / 拍数只进 write_phase 与锁存寄存器的 D 端。
    // u_wr_align 与 B 计数 FIFO 本来就只在首个 burst 那拍采样请求（u_wr_align 空闲时每拍装载字段，request_valid
    // 那拍进入 request_active 后保持），提前取走对它们没有影响；请求更早离开 skid，下一个请求更早就位，吞吐只会持平或更好。
    reg  [63:12] write_rest_page0;        // 首页余下：address[63:12]
    reg  [4:0]   write_rest_block;        //           address[11:7] + 1（头拍拆分要求首页 > 1 拍，addr[11:7] != 31，不进位出页）
    reg  [5:0]   write_rest_first_m1;     //           首页拍数 − 1
    reg  [63:12] write_rest_page1;        // 第二页：page1[63:12]
    reg  [5:0]   write_rest_second;       //         第二页拍数
    reg          write_rest_crosses;      // 首页余下之后还有没有第二页
    wire        write_last_burst = (write_phase == 2'd0) ? (!write_crosses_page && !write_head_split) :
                                   (write_phase == 2'd1) ? !write_rest_crosses : 1'b1;
    wire        aw_fifo_ready, write_align_ready, bresp_count_fifo_ready;
    // B6420：AW FIFO 的「可写」改用寄存器（aw_space_q）。B6418 core 时钟最差路径之一（+0.020）：
    // u_aw_fifo 写指针格雷码 → full 比较 → s_axis_tready → write_aw_push → 请求 ready → engine 的 u_write_request_skid。
    // aw_space_q = 上一拍的 s_axis_tready 且 寄存的深度（s_depth_reg，读指针同步滞后只会偏大）< DEPTH-8；
    // 深度读数最多滞后 2 次入队，留 8 格裕量保证 aw_space_q=1 时 FIFO 一定没满。可用深度 256 → 248，无其它影响。
    wire [$clog2(WRITE_AW_FIFO_DEPTH):0] aw_fifo_depth;
    reg         aw_space_q;
    always @(posedge clk) begin
        if (rst) aw_space_q <= 1'b0;
        else     aw_space_q <= aw_fifo_ready && (aw_fifo_depth < ($clog2(WRITE_AW_FIFO_DEPTH)+1)'(WRITE_AW_FIFO_DEPTH - 8));
    end
    // B0123：B 计数 FIFO 的「可写」同样改用寄存器（bresp_space_q）。B0122 core_clk 余量 0 的一簇（+0.001～+0.006）
    // 从 u_bresp_count_fifo 的格雷码指针出发：组合 full 比较 → s_axis_tready → write_request_start → u_wr_align。
    // 这个 FIFO 两侧都是 clk，格雷码同步与组合 full 比较本来就是多余的，指针寄存器又带上电初值，Hyper-Retimer
    // 不能把寄存器前移。bresp_space_q = 上一拍的 s_axis_tready 且 寄存深度 < DEPTH-8：深度是上一拍的写指针减
    // 同步后的读指针，只会偏大，最多漏算 2 次入队，所以 bresp_space_q=1 那拍 FIFO 一定没满。可用深度 512 → 504。
    wire [$clog2(WRITE_B_FIFO_DEPTH):0] bresp_count_fifo_depth;
    reg         bresp_space_q;
    always @(posedge clk) begin
        if (rst) bresp_space_q <= 1'b0;
        else     bresp_space_q <= bresp_count_fifo_ready &&
                                  (bresp_count_fifo_depth < ($clog2(WRITE_B_FIFO_DEPTH)+1)'(WRITE_B_FIFO_DEPTH - 8));
    end
    // phase 0 要上游有请求、对齐模块与 B 计数 FIFO 能收；后续 burst 的请求已在本模块里，只等 AW FIFO 有空。
    wire        write_aw_push = (write_phase != 2'd0) ? aw_space_q
                                                      : (dma_write_request_valid && aw_space_q && write_align_ready && bresp_space_q);
    wire        write_request_done    = write_aw_push && write_last_burst;     // 本请求最后一个 burst 入队
    wire        write_request_start   = write_aw_push && (write_phase == 2'd0);    // 对齐模块与 B 计数在首个 burst 时入队
    assign dma_write_request_ready    = write_request_start;
    wire [63:0] write_aw_address  = (write_phase == 2'd2) ? {write_rest_page1, 12'd0} :
                                    (write_phase == 2'd1) ? {write_rest_page0, write_rest_block, 7'd0} :
                                                            {dma_write_request_address[63:7], 7'd0};
    wire [5:0]  write_aw_beats = (write_phase == 2'd2) ? write_rest_second :
                                 (write_phase == 2'd1) ? write_rest_first_m1 :
                                 write_head_split      ? 6'd1 : write_first_burst_beats;

    always @(posedge clk) begin
        if (rst)                     write_phase <= 2'd0;
        else if (write_request_done) write_phase <= 2'd0;
        else if (write_aw_push)      write_phase <= ((write_phase == 2'd0) && write_head_split) ? 2'd1 : 2'd2;
    end
    // 后续 burst 的字段：phase 0 时每拍跟着上游请求装载，首个 burst 入队（请求被取走）那拍装进来的就是本请求，
    // 之后 phase 1 / 2 保持。数据寄存器不挂复位（只在 phase != 0 时被读）。B0123 时序：使能原来是
    // write_request_start（由 aw_space_q、wr_align / B 计数可收与上游 valid 组合出来，扇出约 120 位），
    // 现在只看本地的 write_phase，每请求拍数与锁存值都不变。
    always @(posedge clk) begin
        if (write_phase == 2'd0) begin
            write_rest_page0    <= dma_write_request_address[63:12];
            write_rest_block    <= dma_write_request_address[11:7] + 5'd1;
            write_rest_first_m1 <= write_first_burst_beats - 6'd1;
            write_rest_page1    <= dma_write_request_page1[63:12];
            write_rest_second   <= write_second_burst_beats;
            write_rest_crosses  <= write_crosses_page;
        end
    end

    wire [71:0] aw_fifo_data;
    wire        aw_fifo_valid;
    wire        bas_awready = bas_s2m[`BAS_S2M_AWREADY];
    axis_async_fifo #(
        .DEPTH(WRITE_AW_FIFO_DEPTH), .DATA_WIDTH(72), .KEEP_ENABLE(0), .LAST_ENABLE(0), .USER_ENABLE(0),
        .RAM_PIPELINE(PCIE_FIFO_RAM_PIPELINE), .OUTPUT_FIFO_ENABLE(PCIE_FIFO_OUTPUT_FIFO)
    ) u_aw_fifo (
        .s_clk(clk), .s_rst(rst),
        .s_axis_tdata({2'd0, write_aw_beats - 6'd1, write_aw_address}),
        .s_axis_tkeep('0), .s_axis_tvalid(write_aw_push), .s_axis_tready(aw_fifo_ready),
        .s_axis_tlast(1'b1), .s_axis_tid(8'd0), .s_axis_tdest(8'd0), .s_axis_tuser(1'b0),
        .m_clk(pcie_clk), .m_rst(pcie_rst),
        .m_axis_tdata(aw_fifo_data), .m_axis_tkeep(), .m_axis_tvalid(aw_fifo_valid),
        .m_axis_tready(bas_awready), .m_axis_tlast(), .m_axis_tid(), .m_axis_tdest(), .m_axis_tuser(),
        .s_pause_req(1'b0), .s_pause_ack(), .m_pause_req(1'b0), .m_pause_ack(),
        .s_status_depth(aw_fifo_depth), .s_status_depth_commit(), .s_status_overflow(),
        .s_status_bad_frame(), .s_status_good_frame(),
        .m_status_depth(), .m_status_depth_commit(), .m_status_overflow(),
        .m_status_bad_frame(), .m_status_good_frame()
    );

    wire               aligned_write_valid, aligned_write_ready;
    wire [WR_DW-1:0]   aligned_write_data;
    wire [WR_DW/8-1:0] aligned_write_strobe;
    wire [WR_H-1:0]    aligned_write_last, aligned_write_half_valid;
    roce_dma_wr_align #(.DW(WR_DW)) u_wr_align (
        .clk(clk), .rst(rst),
        .request_valid(write_request_start), .request_ready(write_align_ready), .request_address_low(dma_write_request_address[6:0]), .request_length(dma_write_request_length),
        .request_first_burst_beats(write_crosses_page ? write_first_burst_beats : 6'd0),
        .request_head_split(write_head_split),
        .write_data_in_valid(dma_write_valid), .write_data_in_ready(dma_write_ready), .write_data_in(dma_write_data),
        .write_valid(aligned_write_valid), .write_ready(aligned_write_ready), .write_data(aligned_write_data), .write_strobe(aligned_write_strobe), .write_last(aligned_write_last),
        .write_half_valid(aligned_write_half_valid)
    );

    // W FIFO：DEPTH 按字节（KEEP 打开时），两种位宽都是 64 KB——WR_DW=2048 时 256 条目 × 2048 位，RAM 位数不变。
    // 实例名保持 u_w_fifo（roce.sdc 按 u_dma|u_w_fifo 下格雷码指针的偏斜约束），所以不包进 generate。
    wire [W_USER_W-1:0] w_fifo_s_user;
    wire [W_USER_W-1:0] w_fifo_user;
    wire               w_fifo_valid, w_fifo_last, w_fifo_pop;
    wire [WR_DW-1:0]   w_fifo_data;
    wire [WR_DW/8-1:0] w_fifo_strobe;
    wire               bas_wready = bas_s2m[`BAS_S2M_WREADY];
    axis_async_fifo #(
        .DEPTH(512*128), .DATA_WIDTH(WR_DW), .KEEP_ENABLE(1), .KEEP_WIDTH(WR_DW/8),   // KEEP 打开时 DEPTH 按字节
        .LAST_ENABLE(1), .USER_ENABLE((WR_H == 2) ? 1 : 0), .USER_WIDTH(W_USER_W),
        .RAM_PIPELINE(PCIE_FIFO_RAM_PIPELINE), .OUTPUT_FIFO_ENABLE(PCIE_FIFO_OUTPUT_FIFO)
    ) u_w_fifo (
        .s_clk(clk), .s_rst(rst),
        .s_axis_tdata(aligned_write_data), .s_axis_tkeep(aligned_write_strobe), .s_axis_tvalid(aligned_write_valid),
        .s_axis_tready(aligned_write_ready), .s_axis_tlast(aligned_write_last[0]),
        .s_axis_tid(8'd0), .s_axis_tdest(8'd0), .s_axis_tuser(w_fifo_s_user),
        .m_clk(pcie_clk), .m_rst(pcie_rst),
        .m_axis_tdata(w_fifo_data), .m_axis_tkeep(w_fifo_strobe), .m_axis_tvalid(w_fifo_valid),
        .m_axis_tready(w_fifo_pop), .m_axis_tlast(w_fifo_last), .m_axis_tid(), .m_axis_tdest(),
        .m_axis_tuser(w_fifo_user),
        .s_pause_req(1'b0), .s_pause_ack(), .m_pause_req(1'b0), .m_pause_ack(),
        .s_status_depth(), .s_status_depth_commit(), .s_status_overflow(),
        .s_status_bad_frame(), .s_status_good_frame(),
        .m_status_depth(), .m_status_depth_commit(), .m_status_overflow(),
        .m_status_bad_frame(), .m_status_good_frame()
    );

    // pcie 域：W FIFO 条目 → BAS W 拍
    wire          bas_w_valid, bas_w_last;
    wire [1023:0] bas_w_data;
    wire [127:0]  bas_w_strobe;
    generate
        if (WR_H == 2) begin : gen_w_split
            // 每个条目先发低半拍，高半拍有效时下一拍再发高半拍；发完条目里最后一个有效半拍才弹出。
            // 条目之间不插空拍：弹出那拍 FIFO 的输出（OUTPUT_FIFO_ENABLE）下一拍就换成下一个条目，
            // 所以只要 FIFO 不空，W 每个 pcie 拍出 1 拍（1024 bit × 500 MHz = 2048 bit × 250 MHz）。
            // w_half / 高半拍 valid 都是寄存器输出，w_fifo_pop 只比原来多一级与门。
            reg  w_half;                                  // 0 = 正在发低半拍，1 = 正在发高半拍
            wire hi_valid = w_fifo_user[1];
            wire hi_last  = w_fifo_user[0];
            always @(posedge pcie_clk) begin
                if (pcie_rst)
                    w_half <= 1'b0;
                else if (w_fifo_valid && bas_wready)
                    w_half <= !w_half && hi_valid;
            end
            assign w_fifo_s_user = {aligned_write_half_valid[1], aligned_write_last[1]};
            assign w_fifo_pop    = bas_wready && (w_half || !hi_valid);
            assign bas_w_valid   = w_fifo_valid;
            assign bas_w_data    = w_half ? w_fifo_data[2047:1024]  : w_fifo_data[1023:0];
            assign bas_w_strobe  = w_half ? w_fifo_strobe[255:128] : w_fifo_strobe[127:0];
            assign bas_w_last    = w_half ? hi_last : w_fifo_last;
        end else begin : gen_w_direct
            assign w_fifo_s_user = 1'b0;
            assign w_fifo_pop    = bas_wready;
            assign bas_w_valid   = w_fifo_valid;
            assign bas_w_data    = w_fifo_data;
            assign bas_w_strobe  = w_fifo_strobe;
            assign bas_w_last    = w_fifo_last;
        end
    endgenerate

    // B 通道 -> core（每个 AW 一个 B）
    wire bas_bvalid = bas_s2m[`BAS_S2M_BVALID];
    wire bresp_valid, bresp_error;
    axis_async_fifo #(
        .DEPTH(64), .DATA_WIDTH(1), .KEEP_ENABLE(0), .LAST_ENABLE(0), .USER_ENABLE(0)
    ) u_bresp_fifo (
        .s_clk(pcie_clk), .s_rst(pcie_rst),
        .s_axis_tdata(bas_s2m[`BAS_S2M_BRESP] != 2'b00),
        .s_axis_tkeep('0), .s_axis_tvalid(bas_bvalid), .s_axis_tready(),
        .s_axis_tlast(1'b1), .s_axis_tid(8'd0), .s_axis_tdest(8'd0), .s_axis_tuser(1'b0),
        .m_clk(clk), .m_rst(rst),
        .m_axis_tdata(bresp_error), .m_axis_tkeep(), .m_axis_tvalid(bresp_valid),
        .m_axis_tready(1'b1), .m_axis_tlast(), .m_axis_tid(), .m_axis_tdest(), .m_axis_tuser(),
        .s_pause_req(1'b0), .s_pause_ack(), .m_pause_req(1'b0), .m_pause_ack(),
        .s_status_depth(), .s_status_depth_commit(), .s_status_overflow(),
        .s_status_bad_frame(), .s_status_good_frame(),
        .m_status_depth(), .m_status_depth_commit(), .m_status_overflow(),
        .m_status_bad_frame(), .m_status_good_frame()
    );
    // 每请求期望的 B 个数减 1（0..2 = 头拍拆分 + 跨页），与 AW 同序
    wire       bresp_count_valid;
    wire [1:0] bresp_expect_m1;
    wire [1:0] write_bursts_m1 = {1'b0, write_head_split} + {1'b0, write_crosses_page};
    reg  [1:0] bresp_seen;
    reg        bresp_error_accumulated;
    wire       bresp_request_last = (bresp_seen == bresp_expect_m1);
    axis_async_fifo #(
        .DEPTH(WRITE_B_FIFO_DEPTH), .DATA_WIDTH(2), .KEEP_ENABLE(0), .LAST_ENABLE(0), .USER_ENABLE(0)
    ) u_bresp_count_fifo (
        .s_clk(clk), .s_rst(rst),
        .s_axis_tdata(write_bursts_m1), .s_axis_tkeep('0), .s_axis_tvalid(write_request_start), .s_axis_tready(bresp_count_fifo_ready),
        .s_axis_tlast(1'b1), .s_axis_tid(8'd0), .s_axis_tdest(8'd0), .s_axis_tuser(1'b0),
        .m_clk(clk), .m_rst(rst),
        .m_axis_tdata(bresp_expect_m1), .m_axis_tkeep(), .m_axis_tvalid(bresp_count_valid),
        .m_axis_tready(bresp_valid && bresp_request_last), .m_axis_tlast(), .m_axis_tid(),
        .m_axis_tdest(), .m_axis_tuser(),
        .s_pause_req(1'b0), .s_pause_ack(), .m_pause_req(1'b0), .m_pause_ack(),
        .s_status_depth(bresp_count_fifo_depth), .s_status_depth_commit(), .s_status_overflow(),
        .s_status_bad_frame(), .s_status_good_frame(),
        .m_status_depth(), .m_status_depth_commit(), .m_status_overflow(),
        .m_status_bad_frame(), .m_status_good_frame()
    );
    always @(posedge clk) begin
        if (rst) begin
            bresp_seen              <= 2'd0;
            bresp_error_accumulated <= 1'b0;
        end else if (bresp_valid) begin
            if (bresp_request_last) begin
                bresp_seen              <= 2'd0;
                bresp_error_accumulated <= 1'b0;
            end else begin
                bresp_seen              <= bresp_seen + 2'd1;
                bresp_error_accumulated <= bresp_error_accumulated | bresp_error;
            end
        end
    end
    // B 一定晚于对应 AW 入队，bresp_count_valid 此时必为 1；一个请求的最后一个 B 到达才算完成
    assign dma_write_complete     = bresp_valid && bresp_request_last;
    assign dma_write_complete_error = bresp_error || bresp_error_accumulated;

    // ------------------------------------------------------------ BAS 打包
    assign bas_m2s[`BAS_M2S_AWVALID] = aw_fifo_valid;
    assign bas_m2s[`BAS_M2S_AWID]    = 4'd0;
    assign bas_m2s[`BAS_M2S_AWADDR]  = aw_fifo_data[63:0];
    assign bas_m2s[`BAS_M2S_AWUSER]  = 16'd0;              // {vf_num, vf_active, pf_num} = PF0
    assign bas_m2s[`BAS_M2S_AWLEN]   = {2'd0, aw_fifo_data[69:64]};
    assign bas_m2s[`BAS_M2S_AWSIZE]  = 3'd7;               // 128 B
    assign bas_m2s[`BAS_M2S_AWBURST] = 2'b01;              // INCR
    assign bas_m2s[`BAS_M2S_AWPROT]  = 3'd0;
    assign bas_m2s[`BAS_M2S_AWLOCK]  = 1'b0;
    assign bas_m2s[`BAS_M2S_WVALID]  = bas_w_valid;
    assign bas_m2s[`BAS_M2S_WLAST]   = bas_w_last;
    assign bas_m2s[`BAS_M2S_WDATA]   = bas_w_data;
    assign bas_m2s[`BAS_M2S_WSTRB]   = bas_w_strobe;
    assign bas_m2s[`BAS_M2S_BREADY]  = 1'b1;
    assign bas_m2s[`BAS_M2S_ARVALID] = ar_fifo_valid;
    assign bas_m2s[`BAS_M2S_ARID]    = 4'd0;
    assign bas_m2s[`BAS_M2S_ARADDR]  = ar_fifo_data[63:0];
    assign bas_m2s[`BAS_M2S_ARUSER]  = 16'd0;
    assign bas_m2s[`BAS_M2S_ARLEN]   = {2'd0, ar_fifo_data[69:64]};
    assign bas_m2s[`BAS_M2S_ARSIZE]  = 3'd7;
    assign bas_m2s[`BAS_M2S_ARBURST] = 2'b01;
    assign bas_m2s[`BAS_M2S_ARPROT]  = 3'd0;
    assign bas_m2s[`BAS_M2S_ARLOCK]  = 1'b0;
    assign bas_m2s[`BAS_M2S_RREADY]  = 1'b1;               // 由信用保证 R FIFO 不溢出
    assign debug_state = {read_beat_valid, read_meta_valid, ar_fifo_valid,
                          read_second_phase, read_credit};
endmodule
`default_nettype wire
