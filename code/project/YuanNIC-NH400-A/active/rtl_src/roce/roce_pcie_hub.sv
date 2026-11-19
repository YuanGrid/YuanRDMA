// roce_pcie_hub.sv
// Phase 1 PCIe DMA hub（pcie_clk 域）：把 LANES 个 roce_dma 的虚拟 BAS 合并到一条真实 BAS。
//
// AW：轮询选 lane，进 2 深 skid buffer 即算 hub 收下（B6418 起，与 AR 同构）；进 skid 的
//     同一拍把 lane 号压进 W 顺序 FIFO。BAS 看到的 AWVALID/载荷全部来自 skid 寄存器。
// W ：只服务 W 顺序 FIFO 出队到 w_cur 的那个 lane，直到 WLAST 握手。AXI4 不允许 W 交织，
//     W 必须按 AW 的顺序走，这个 FIFO 就是这条规则。
//     **WVALID 不组合依赖 AWREADY**：W 归属在 AW「进 skid」时就确定，而不是「被 MCDMA 接受」时。
//     AXI 允许从设备等到 WVALID 再给 AWREADY，若 W 等 AW 握手才放行就会互等死锁。
//     W 先于 AW 握手出现是合法的（单 lane 的 roce_dma 本来 aw/w 就是两个独立 FIFO）。
// AR：独立轮询，当前 lane 没有 ARVALID 或刚握手时才换。
// B / R：按 BID / RID 低 LANE_W 位路由回 lane；ID 低位 = lane 号，其余位为 0。
// RREADY / BREADY 恒 1：各 lane 的 roce_dma 用读信用保证自己的 R FIFO 不溢出。
//
// 所有 mux 选择信号（aw_grant、w_cur、ar_grant）都是寄存器，500 MHz 下只多一级 mux。
//
// 端口打平（数组端口在 Verilog-2001 顶层不可用）：
//   lane_m2s_flat：lane i 占 [i*BAS_M2S_W +: BAS_M2S_W]
//   lane_s2m_flat：lane i 占 [i*BAS_S2M_W +: BAS_S2M_W]
`default_nettype none
`timescale 1ns/1ps
`include "roce_bas_if.vh"
module roce_pcie_hub #(
    parameter int LANES = 2
)(
    input  wire                         pcie_clk,
    input  wire                         pcie_rst,
    input  wire [LANES*`BAS_M2S_W-1:0]  lane_m2s_flat,
    output wire [LANES*`BAS_S2M_W-1:0]  lane_s2m_flat,
    output wire [`BAS_M2S_W-1:0]        bas_m2s,
    input  wire [`BAS_S2M_W-1:0]        bas_s2m
);
    localparam int LANE_W = (LANES <= 2) ? 1 : (LANES <= 4) ? 2 : 3;
    localparam int MW = `BAS_M2S_W;
    localparam int SW = `BAS_S2M_W;

    // 位段 LSB。宏展开成 "hi:lo"，不能写进 generate 里的 B + `X +: N，所以落成常数。
    localparam int M2S_AWVALID = 0;
    localparam int M2S_WVALID  = 102;
    localparam int M2S_WLAST   = 103;
    localparam int M2S_ARVALID = 1257;
    localparam int S2M_AWREADY = 0,  S2M_WREADY = 1,  S2M_BVALID = 2,  S2M_BID = 3, S2M_BRESP = 7;
    localparam int S2M_ARREADY = 9,  S2M_RVALID = 10, S2M_RLAST  = 11, S2M_RID = 12;
    localparam int S2M_RDATA   = 16, S2M_RRESP  = 1040;

    genvar gi;
    wire [LANES-1:0] lane_awvalid, lane_wvalid, lane_wlast, lane_arvalid;
    generate
        for (gi = 0; gi < LANES; gi = gi + 1) begin : gen_valid
            assign lane_awvalid[gi] = lane_m2s_flat[gi*MW + M2S_AWVALID];
            assign lane_wvalid[gi]  = lane_m2s_flat[gi*MW + M2S_WVALID];
            assign lane_wlast[gi]   = lane_m2s_flat[gi*MW + M2S_WLAST];
            assign lane_arvalid[gi] = lane_m2s_flat[gi*MW + M2S_ARVALID];
        end
    endgenerate

    // 轮询选择：从 start 开始找第一个置位的 lane
    function automatic [LANE_W-1:0] rr_pick(input [LANES-1:0] req, input [LANE_W-1:0] start);
        integer k;
        reg     found;
        begin
            rr_pick = start;
            found   = 1'b0;
            for (k = 0; k < LANES; k = k + 1)
                if (!found && req[(start + k) % LANES]) begin
                    rr_pick = LANE_W'((start + k) % LANES);
                    found   = 1'b1;
                end
        end
    endfunction

    wire bas_awready = bas_s2m[S2M_AWREADY];
    wire bas_wready  = bas_s2m[S2M_WREADY];
    wire bas_arready = bas_s2m[S2M_ARREADY];

    // B6418：AW 也改成 skid（与 AR 同构），W 顺序队列改为寄存器预取出队，R 加两级无使能流水。
    // 目的是清掉 B6417 pld_clkout 里 RoCE 侧约 330 个违例端点（见调试记录 §44.7）：
    //   AW 233：MCDMA aw_skidbuf 的 AWREADY 组合扇出到 4 个 lane 的 u_aw_fifo 读使能 / RAM 地址；
    //   R 54：MCDMA aximm_r_resp_fifo 的 RAM 输出直接到 lane 的 u_r_fifo M20K（r_data_q 被并进 M20K
    //         输入寄存器，等于没有这一级），以及 r_data_q 的 1024 位使能扇出；
    //   wq_sr 7：lane u_w_fifo 输出 → w_last_hs → 32 级移位队列的使能。

    // ---------------------------------------------------------------- W 顺序 FIFO（移位式，32 深）
    // 这个队列记录「每个已发出的 AW 属于哪个 lane」，W 数据严格按它的顺序走（AXI4 不允许 W 交织）。
    //
    // B6400 STA：pld_clkout −0.143 / TNS −205.497，502 条违例里 492 条的**终点**在 4 个 lane 的
    // u_w_fifo，**起点**是本队列的读出，路径 4 级逻辑（存储器读出 + 队头比较 +
    // 扇出到 lane FIFO 的读地址）。根因是把队列做成 128 深数组：被综合成 MLAB，
    // 队头要先经一次存储器读出才能参与仲裁。
    //
    // 改成 32 深、**移位寄存器**实现（每项 2 bit → 64 个 ALM 寄存器）：队头永远是 wq_sr[0]，
    // 直接来自触发器，存储器读出与比较都不在仲裁路径上。出队时整组下移一格，
    // 入队写到当前尾部位置；两者同拍发生时「下移」与「尾部写入」落在不同下标，互不覆盖。
    //
    // 深度取 32 的理由：每 lane 的 u_aw_fifo 是 256 深（B6397），但同时在途的 AW 受
    // PCIe B 响应往返限制，远到不了这个数；4 深（B6398 之前）已验证功能正确，
    // 32 深有 8 倍余量，同时保证数组小到能被放进 ALM 寄存器而不是 MLAB。
    localparam int WQ_DEPTH = 32;
    localparam int WQ_W     = 6;                       // 计数 0..32
    (* ramstyle = "logic" *) reg [LANE_W-1:0] wq_sr [0:WQ_DEPTH-1];
    reg  [WQ_W-1:0]   wq_count;
    wire              wq_empty = (wq_count == 0);
    // B6419：入队延后一拍（wq_push_q），满判断给在途的那一个入队预留一格。
    // B6418 pld_clkout：aw_grant → lane_awvalid 4:1 → aw_in_fire → 尾部译码 → wq_sr 写使能，4 级，21 个端点 −0.111。
    // 现在写使能只来自寄存器（wq_push_q / wq_count / wq_deq）。W 的归属晚一拍进入队列，最多让该 AW 的 W 晚一拍出发。
    wire              wq_full  = (wq_count >= WQ_W'(WQ_DEPTH - 1));
    reg               wq_push_q;
    reg  [LANE_W-1:0] wq_push_lane_q;
    integer           wi;

    // B6418：W 当前归属与下一个归属各一个寄存器（w_cur / w_nxt），队列只负责往 w_nxt 里补。
    // B6417 里 w_last_hs（来自 lane u_w_fifo 的输出 + 4:1 选择）直接做 32 级移位的使能，
    // 7 个端点 −0.106。现在 w_last_hs 只驱动 w_cur / w_cur_valid / w_nxt_valid 三处，
    // 队列移位的条件 wq_deq 只看寄存器（队列非空且 w_nxt 空）。
    // 代价：连续的 1 拍 W 突发每两拍才能出一个（w_nxt 来不及补）；≥ 2 拍的突发（RX payload、
    // 写数据）不受影响。CQE 这类 1 拍写本来就稀疏。
    reg  [LANE_W-1:0] w_cur, w_nxt;
    reg               w_cur_valid, w_nxt_valid;
    wire [LANE_W-1:0] w_sel = w_cur;

    // ---------------------------------------------------------------- AW（B6418 起经 skid buffer）
    // 与 AR 同构：轮询指针 aw_grant 选 lane，请求进 skid（aw_in_fire）即视为 hub 已收下——
    // lane 的 AWREADY 就是 aw_in_fire，与 bas_awready 无组合关系；BAS 看到的 AWVALID/AW 载荷
    // 全部来自 skid 输出级寄存器。W 顺序在「进 skid」时入队：AXI 要求 W 按 AW 的顺序走，
    // skid 本身先进先出，入队顺序就是发到 BAS 的顺序。
    // W 先于 AW 握手出现仍然合法：归属在进 skid 时就确定，不等 MCDMA 的 AWREADY，
    // 所以不会出现「MCDMA 等 WVALID 才给 AWREADY、hub 等 AWREADY 才放 W」的互等。
    reg  [LANE_W-1:0] aw_grant;
    wire [LANE_W-1:0] aw_next      = LANE_W'((aw_grant + 1) % LANES);
    wire              cur_awvalid  = lane_awvalid[aw_grant];
    reg               aw_out_valid, aw_skid_valid;
    wire              aw_in_fire   = cur_awvalid && !aw_skid_valid && !wq_full;
    // B6419：AW 出口再接一级 roce_skid（u_aw_bas_skid），MCDMA 的 AWREADY 只驱动这一级的寄存器使能，
    // 让它可以摆在 MCDMA 旁边；B6418 里 aximm_aw_skidbuf → hub aw_out/aw_skid 33 个端点（1 级逻辑、走线 1.4~1.6 ns，−0.063）。
    wire              aw_bas_ready;
    wire              aw_out_fire  = aw_out_valid && aw_bas_ready;

    // ---------------------------------------------------------------- W（入口侧，出口经 skid buffer）
    // B6395：B6394 里 lane 的 WREADY = bas_wready && (w_sel == lane) 是组合的，500 MHz 下
    // 扇出到两个 lane 的 u_w_fifo 出队逻辑，−0.168 ns。改为 2 深 skid buffer：lane 看到的
    // ready 只来自寄存器（!w_skid_valid），BAS 看到的 WVALID/WDATA 也来自寄存器。
    wire              w_open     = w_cur_valid;
    wire              w_in_valid = w_open && lane_wvalid[w_sel];
    wire              w_in_ready;
    wire              w_last_hs  = w_in_valid && w_in_ready && lane_wlast[w_sel];

    // 队列 → w_nxt → w_cur 两级预取。wq_deq 与 nxt_to_cur 互斥（前者要求 w_nxt 空，后者要求 w_nxt 满）。
    wire              wq_deq     = !wq_empty && !w_nxt_valid;
    wire              nxt_to_cur = w_nxt_valid && (!w_cur_valid || w_last_hs);
    // 移位队列的入队下标：本拍若同时出队，尾部前移一格（写入位置随之减一）。
    wire [WQ_W-1:0]   wq_tail    = wq_count - {{(WQ_W-1){1'b0}}, wq_deq};

    always @(posedge pcie_clk) begin
        if (pcie_rst) begin
            wq_count    <= '0;
            wq_push_q   <= 1'b0;
            wq_push_lane_q <= '0;
            w_cur       <= '0;
            w_nxt       <= '0;
            w_cur_valid <= 1'b0;
            w_nxt_valid <= 1'b0;
            for (wi = 0; wi < WQ_DEPTH; wi = wi + 1)
                wq_sr[wi] <= '0;
        end else begin
            // 移位式：出队时整体下移一格；入队写到「计数 - 同拍出队」的位置。
            // 同拍既出队又入队时，写入下标 = 下移后的尾部，与下移覆盖的下标不重叠。
            for (wi = 0; wi < WQ_DEPTH - 1; wi = wi + 1)
                if (wq_deq) wq_sr[wi] <= wq_sr[wi + 1];
            wq_push_q      <= aw_in_fire;
            wq_push_lane_q <= aw_grant;
            if (wq_push_q)
                wq_sr[wq_tail] <= wq_push_lane_q;
            wq_count <= wq_count + {{(WQ_W-1){1'b0}}, wq_push_q} - {{(WQ_W-1){1'b0}}, wq_deq};

            if (nxt_to_cur) begin
                w_cur       <= w_nxt;
                w_cur_valid <= 1'b1;
            end else if (w_last_hs) begin
                w_cur_valid <= 1'b0;
            end
            if (wq_deq) begin
                w_nxt       <= wq_sr[0];
                w_nxt_valid <= 1'b1;
            end else if (nxt_to_cur) begin
                w_nxt_valid <= 1'b0;
            end
        end
    end

    // AW skid：可变字段 AWADDR..AWLOCK（位 5..101，共 97 位）整段寄存，ID 出站时按 lane 生成。
    // 位段字面量与 roce_bas_if.vh 对应（宏展开是 "hi:lo"，不能放进 +: 表达式，见下方 AR 的说明）。
    localparam int AW_BASE_BIT = 5;                 // = `BAS_M2S_AWADDR 的 lo 位
    localparam int AW_PAY_W    = 97;                // AWADDR 64 + AWUSER 16 + AWLEN 8 + AWSIZE 3 + AWBURST 2 + AWPROT 3 + AWLOCK 1
    wire [AW_PAY_W-1:0] m2s_aw_pay = lane_m2s_flat[aw_grant*MW + AW_BASE_BIT +: AW_PAY_W];
    reg  [AW_PAY_W-1:0] aw_out_data, aw_skid_data;
    reg  [LANE_W-1:0]   aw_out_lane, aw_skid_lane;
    always @(posedge pcie_clk) begin
        if (pcie_rst) begin
            aw_grant      <= '0;
            aw_out_valid  <= 1'b0;
            aw_skid_valid <= 1'b0;
            aw_out_lane   <= '0;
            aw_skid_lane  <= '0;
        end else begin
            if (aw_out_fire || !aw_out_valid) begin
                if (aw_skid_valid) begin
                    aw_out_data   <= aw_skid_data;
                    aw_out_lane   <= aw_skid_lane;
                    aw_out_valid  <= 1'b1;
                    aw_skid_valid <= 1'b0;
                end else if (aw_in_fire) begin
                    aw_out_data  <= m2s_aw_pay;
                    aw_out_lane  <= aw_grant;
                    aw_out_valid <= 1'b1;
                end else begin
                    aw_out_valid <= 1'b0;
                end
            end else if (aw_in_fire) begin
                aw_skid_data  <= m2s_aw_pay;
                aw_skid_lane  <= aw_grant;
                aw_skid_valid <= 1'b1;
            end
            // 轮转依据 skid 入口握手（同 AR）：请求真正进了 skid 才换下一个 lane
            if (aw_in_fire || !cur_awvalid)
                aw_grant <= rr_pick(lane_awvalid & ~(aw_in_fire ? (LANES'(1) << aw_grant) : '0), aw_next);
        end
    end

    // ---------------------------------------------------------------- AR
    // B6402：AR 出口加 2 深 skid buffer，把 MCDMA 的 ARREADY 从 lane 的 FIFO 读路径里摘出来。
    //
    // 要解决的违例：B6401 STA 的 pld_clkout −0.049 那组 40 条，起点是 MCDMA 内部的
    // aximm_ar_info_fifo_almost_full、终点是各 lane u_ar_fifo 的 RAM 读出寄存器，走线 79%。
    // 组合链条是：MCDMA ARREADY → hub 的 ar_grant 仲裁 → lane 的 u_ar_fifo.m_axis_tready
    // → FIFO 读使能 → M20K 输出寄存器。跨半颗芯片的 ready 塞进 2 ns 周期。
    //
    // 为什么必须在 hub 层做，不能在各 lane 的 roce_dma 里做：
    //   AR 的握手实际发生在这里（ar_hs = cur_arvalid && bas_arready）。若各 lane 自己把
    //   ARVALID 寄存一拍，hub 仍按当拍的 lane_arvalid 判断握合并切换 ar_grant，
    //   于是在 lane 的 skid 还持有请求时 grant 就被切走，后续请求会丢。
    //   放在 hub 里，上游（lane 的 ARVALID）与下游（BAS 的 ARREADY）都由同一个 skid 衔接，
    //   ar_grant 的切换依据改为 skid 的入口握手，语义自洽。
    //
    // 为什么不能只把 ready 打一拍：AXI4 的 VALID && READY 必须同拍成立才算传输。
    // 单打 ready 会让从机撤销 READY 的那一拍仍按"上一拍的 READY"弹出一个请求出队，
    // 该请求既没被接受、又从 FIFO 里消失 = 静默丢一个 AR。行为模型验证过确实会丢。
    // skid buffer 同时寄存 valid 与 data，没有这个问题（同一模型跑了 500 次随机试验，零丢失）。
    //
    // 代价：AR 多一拍延迟。不占额外在途量——read_credit 在请求推入 lane FIFO 时就已扣减，
    // 不是按 BAS 握手扣减，所以 skid 里多停一拍不会让读信用过冲。
    reg  [LANE_W-1:0] ar_grant;
    wire [LANE_W-1:0] ar_next = LANE_W'((ar_grant + 1) % LANES);
    wire              cur_arvalid = lane_arvalid[ar_grant];
    // 上游（lane 的 ARVALID）看到的 ready 只来自寄存器，与 bas_arready 无组合关系
    wire              ar_src_ready = !ar_skid_valid;
    // 实际上游握手：选中的 lane 有 ARVALID 且 skid 入口可收
    wire              ar_in_fire   = cur_arvalid && ar_src_ready;
    // 下游握手：skid 输出级有效且 BAS 给出 ARREADY
    wire              ar_out_fire  = ar_out_valid && bas_arready;

    // skid 里存 AR 的**可变**字段，位段从 ARVALID 起到 ARLEN 末位，共 93 位：
    //   [0]      ARVALID（不单独存，下面按 valid 位寄存，这里只为对齐留位）
    //   [4:1]    ARID（skid 里恒 0，出站时按 ar_out_lane 覆盖）
    //   [68:5]   ARADDR
    //   [84:69]  ARUSER（恒 0，一并寄存省得单独走线）
    //   [92:85]  ARLEN
    // ARSIZE/ARBURST/ARPROT/ARLOCK 在 roce_dma 里是常数，不占 skid。
    // 注意：宽度不能写成 `BAS_M2S_ARADDR - `BAS_M2S_ARVALID 之类的表达式——宏展开是 "hi:lo"，
    // 不是整数；改了 roce_bas_if.vh 的位段要同步改这里。
    localparam int AR_PAY_W   = 93;
    localparam int AR_ADDR_LO = 5;
    localparam int AR_ADDR_W  = 64;
    localparam int AR_LEN_LO  = 85;
    localparam int AR_LEN_W   = 8;
    reg  [AR_PAY_W-1:0] ar_out_data, ar_skid_data;
    reg  [LANE_W-1:0]   ar_out_lane, ar_skid_lane;
    reg                 ar_out_valid, ar_skid_valid;

    // 从当前选中的 lane 里取出它的 AR 载荷（ARVALID..ARLEN 这段连续位）。
    // **不能用 `BAS_M2S_ARVALID 做偏移**：该宏展开是 "1257:1257"（hi:lo 形式），
    // 塞进 "+:" 表达式会变成 `ar_grant*MW + 1257:1257 +: 93`，
    // Quartus 报 `syntax error near text +:`、后续 m2s_ar_pay 全部 undeclared。
    // 仿真侧能容忍这种写法，所以门禁抓不到——两边的宏展开规则不同。
    // （注释别以 verilator 这个词开头：它会把 `// verilator ...` 当 pragma 解析，直接报错。）
    // 直接写字面量 1257；改 roce_bas_if.vh 的位段必须同步改这里（与 AR_PAY_W 同一处）。
    localparam int AR_BASE_BIT = 1257;              // = `BAS_M2S_ARVALID 的 lo 位
    wire [AR_PAY_W-1:0] m2s_ar_pay = lane_m2s_flat[ar_grant*MW + AR_BASE_BIT +: AR_PAY_W];

    always @(posedge pcie_clk) begin
        if (pcie_rst) begin
            ar_grant      <= '0;
            ar_out_valid  <= 1'b0;
            ar_skid_valid <= 1'b0;
            ar_out_lane   <= '0;
            ar_skid_lane  <= '0;
        end else begin
            if (ar_out_fire || !ar_out_valid) begin
                if (ar_skid_valid) begin
                    ar_out_data  <= ar_skid_data;
                    ar_out_lane  <= ar_skid_lane;
                    ar_out_valid <= 1'b1;
                    ar_skid_valid <= 1'b0;
                end else if (ar_in_fire) begin
                    ar_out_data  <= m2s_ar_pay;
                    ar_out_lane  <= ar_grant;
                    ar_out_valid <= 1'b1;
                end else begin
                    ar_out_valid <= 1'b0;
                end
            end else if (ar_in_fire) begin
                ar_skid_data  <= m2s_ar_pay;
                ar_skid_lane  <= ar_grant;
                ar_skid_valid <= 1'b1;
            end

            // 仲裁轮转依据改为 skid 的**入口**握手：只有请求真正进了 skid，
            // 才把这个 lane 从候选里摘掉并切下一个。
            if (ar_in_fire || !cur_arvalid)
                ar_grant <= rr_pick(lane_arvalid & ~(ar_in_fire ? (LANES'(1) << ar_grant) : '0), ar_next);
        end
    end

    // ---------------------------------------------------------------- bas_m2s
    wire [MW-1:0] m2s_w  = lane_m2s_flat[w_sel    * MW +: MW];
    wire [MW-1:0] m2s_ar = lane_m2s_flat[ar_grant * MW +: MW];

    // W skid buffer：{WLAST, WSTRB, WDATA} = 1 + 128 + 1024 位，两级（输出级 + 备用级）。
    // w_in_ready 只取寄存器 w_skid_valid，切断 bas_wready → lane FIFO 的组合路径。
    // W 次序不变（FIFO），W 顺序 FIFO 的出队在入口侧 WLAST 握手时发生，与 AW 无关。
    localparam int WB = 1 + 128 + 1024;
    wire [WB-1:0] w_in_data = {m2s_w[`BAS_M2S_WLAST], m2s_w[`BAS_M2S_WSTRB], m2s_w[`BAS_M2S_WDATA]};
    reg           w_out_valid, w_skid_valid;
    reg  [WB-1:0] w_out_data, w_skid_data;
    assign        w_in_ready = !w_skid_valid;
    wire          w_in_fire  = w_in_valid && w_in_ready;
    wire          w_out_fire = w_out_valid && bas_wready;
    always @(posedge pcie_clk) begin
        if (pcie_rst) begin
            w_out_valid  <= 1'b0;
            w_skid_valid <= 1'b0;
        end else if (w_out_fire || !w_out_valid) begin
            // 输出级下一拍空出来：优先搬备用级，其次直接收入口
            if (w_skid_valid) begin
                w_out_data   <= w_skid_data;
                w_out_valid  <= 1'b1;
                w_skid_valid <= 1'b0;
            end else if (w_in_fire) begin
                w_out_data  <= w_in_data;
                w_out_valid <= 1'b1;
            end else begin
                w_out_valid <= 1'b0;
            end
        end else if (w_in_fire) begin
            // 输出级被反压，入口这一拍进备用级（w_in_ready=1 保证备用级此时是空的）
            w_skid_data  <= w_in_data;
            w_skid_valid <= 1'b1;
        end
    end

    // AW 一律走 skid 输出级（B6418）：VALID/载荷全部来自寄存器，ID 按 aw_out_lane 生成。
    // 载荷位段 = AWADDR..AWLOCK（位 5..101），整段贴回。
    wire                aw_bas_valid;
    wire [LANE_W-1:0]   aw_bas_lane;
    wire [AW_PAY_W-1:0] aw_bas_data;
    roce_skid #(.WIDTH(LANE_W + AW_PAY_W)) u_aw_bas_skid (
        .clk(pcie_clk), .rst(pcie_rst),
        .s_valid(aw_out_valid), .s_ready(aw_bas_ready), .s_data({aw_out_lane, aw_out_data}),
        .m_valid(aw_bas_valid), .m_ready(bas_awready), .m_data({aw_bas_lane, aw_bas_data})
    );
    assign bas_m2s[`BAS_M2S_AWVALID] = aw_bas_valid;
    assign bas_m2s[`BAS_M2S_AWID]    = 4'(aw_bas_lane);
    assign bas_m2s[AW_BASE_BIT +: AW_PAY_W] = aw_bas_data;
    assign bas_m2s[`BAS_M2S_WVALID]  = w_out_valid;
    assign bas_m2s[`BAS_M2S_WLAST]   = w_out_data[WB-1];
    assign bas_m2s[`BAS_M2S_WDATA]   = w_out_data[1023:0];
    assign bas_m2s[`BAS_M2S_WSTRB]   = w_out_data[1151:1024];
    assign bas_m2s[`BAS_M2S_BREADY]  = 1'b1;
    // AR 一律走 skid buffer 的输出级（B6402）：VALID/DATA 全部来自寄存器，
    // 与 bas_arready 无组合关系。AR 载荷的位段就是 ARVALID..ARADDR 这 69 位，
    // 所以整段直接贴回去；ID 另按 ar_out_lane 生成（skid 里那份 ID 恒 0，不参与）。
    assign bas_m2s[`BAS_M2S_ARVALID] = ar_out_valid;
    assign bas_m2s[`BAS_M2S_ARID]    = 4'(ar_out_lane);
    assign bas_m2s[`BAS_M2S_ARADDR]  = ar_out_data[AR_ADDR_LO +: AR_ADDR_W];
    assign bas_m2s[`BAS_M2S_ARUSER]  = ar_out_data[69 +: 16];     // 恒 0，随 skid 一起寄存
    assign bas_m2s[`BAS_M2S_ARLEN]   = ar_out_data[AR_LEN_LO +: AR_LEN_W];
    assign bas_m2s[`BAS_M2S_ARSIZE]  = m2s_ar[`BAS_M2S_ARSIZE];   // 以下四项初值恒定，不必寄存
    assign bas_m2s[`BAS_M2S_ARBURST] = m2s_ar[`BAS_M2S_ARBURST];
    assign bas_m2s[`BAS_M2S_ARPROT]  = m2s_ar[`BAS_M2S_ARPROT];
    assign bas_m2s[`BAS_M2S_ARLOCK]  = m2s_ar[`BAS_M2S_ARLOCK];
    assign bas_m2s[`BAS_M2S_RREADY]  = 1'b1;

    // ---------------------------------------------------------------- lane_s2m
    // R：B6418 起三级、全部无使能。
    //   r0_*（共享一份，靠近 MCDMA）：MCDMA 的 R 输出原样寄存，不做任何判断；
    //   gen_s2m[i].r1_*（每 lane 一份，dont_merge）：按 RID 低位算本 lane 的 valid，数据原样；
    //   gen_s2m[i].r_*_q（每 lane 一份，dont_merge）：送 lane 的 u_r_fifo。
    // 为什么要三级：B6417 剩余违例的起点是 MCDMA aximm_r_resp_fifo 的 RAM 输出、终点直接是 lane
    // u_r_fifo 的 M20K——r_data_q 没有 ALM 实体，被并进了 M20K 的输入寄存器（fit.rpt 的
    // Bypassed ALM Register），等于 MCDMA 直连 4 个分散的 RAM（−0.135）。另外 r_data_q 的
    // 使能（RVALID && RID 匹配）扇出 1024 位 × 4 lane（−0.073）。
    // 现在 MCDMA → r0 是一跳本地走线，r0 → r1 → (r_*_q 并进 M20K) 各一跳，最后两级每 lane 独立，
    // 可以沿途摆放；数据寄存器一律不带使能（RREADY 恒 1、没有反压，lane 只看 r_valid_q）。
    // 不加 preserve：B6402 实测 preserve 把 4K 位寄存器全部强制实体化、分散后更差（见下方历史）。
    // 代价：R 多两拍（500 MHz 下 4 ns），读信用在请求入 lane FIFO 时就扣，不受影响。
    // B6419：B 通道也寄存两级（与 R 同构：共享 b0 靠近 MCDMA + 每 lane 一份 b_q）。
    // B6418 pld_clkout：MCDMA aximm_b_info_fifo 读指针 → BVALID → lane u_bresp_fifo 写指针，22 个端点 −0.203（3 级）。
    // BREADY 恒 1，没有反压，加寄存只增加 2 拍延迟（B 响应只用于写完成计数）。
    reg               b0_valid;
    reg  [3:0]        b0_id;
    reg  [1:0]        b0_resp;
    always @(posedge pcie_clk) begin
        b0_valid <= !pcie_rst && bas_s2m[S2M_BVALID];
        b0_id    <= bas_s2m[S2M_BID   +: 4];
        b0_resp  <= bas_s2m[S2M_BRESP +: 2];
    end
    wire [LANE_W-1:0] bid_lane = b0_id[LANE_W-1:0];
    reg               r0_valid, r0_last;
    reg  [3:0]        r0_id;
    reg  [1:0]        r0_resp;
    reg  [1023:0]     r0_data;
    always @(posedge pcie_clk) begin
        r0_valid <= !pcie_rst && bas_s2m[S2M_RVALID];
        r0_last  <= bas_s2m[S2M_RLAST];
        r0_id    <= bas_s2m[S2M_RID   +: 4];
        r0_resp  <= bas_s2m[S2M_RRESP +: 2];
        r0_data  <= bas_s2m[S2M_RDATA +: 1024];
    end
    wire [LANE_W-1:0] r0_lane = r0_id[LANE_W-1:0];
    generate
        for (gi = 0; gi < LANES; gi = gi + 1) begin : gen_s2m
            localparam int B = gi * SW;
            // 历史（pld_clkout，Slow vid2 100°C），供改这一段时参考：
            //   版本    LANES  r_data_q 属性         WNS / TNS / 违例端点数
            //   B6397   2      dont_merge            −0.108 / −7.923
            //   B6401   4      dont_merge            −0.058 / −3.860 / 142
            //   B6402   4      preserve, dont_merge  −0.267 / −895.139 / 5799
            //   B6403   4      preserve, dont_merge  −0.255 / −774.387 / 4836（撤 LogicLock）
            //   B6417   4      dont_merge，单级带使能  R 相关 54 个端点，最差 −0.135
            // dont_merge 映射 DONT_MERGE_REGISTER，只防寄存器合并（4 个 lane 的副本不被并成一份），
            // 不管 LUT 复制，也不阻止被并进 M20K 输入寄存器。
            (* dont_merge *) reg          r1_valid, r1_last;
            (* dont_merge *) reg [3:0]    r1_id;
            (* dont_merge *) reg [1:0]    r1_resp;
            (* dont_merge *) reg [1023:0] r1_data;
            (* dont_merge *) reg          r_valid_q;
            (* dont_merge *) reg          r_last_q;
            (* dont_merge *) reg [3:0]    r_id_q;
            (* dont_merge *) reg [1:0]    r_resp_q;
            (* dont_merge *) reg [1023:0] r_data_q;
            (* dont_merge *) reg          b_valid_q;
            (* dont_merge *) reg [3:0]    b_id_q;
            (* dont_merge *) reg [1:0]    b_resp_q;
            always @(posedge pcie_clk) begin
                b_valid_q <= !pcie_rst && b0_valid && (bid_lane == LANE_W'(gi));
                b_id_q    <= b0_id;
                b_resp_q  <= b0_resp;
            end
            always @(posedge pcie_clk) begin
                r1_valid  <= !pcie_rst && r0_valid && (r0_lane == LANE_W'(gi));
                r1_last   <= r0_last;
                r1_id     <= r0_id;
                r1_resp   <= r0_resp;
                r1_data   <= r0_data;
                r_valid_q <= !pcie_rst && r1_valid;
                r_last_q  <= r1_last;
                r_id_q    <= r1_id;
                r_resp_q  <= r1_resp;
                r_data_q  <= r1_data;
            end
            // AWREADY 与 ARREADY 一样取 skid 的入口握手（B6418），与 bas_awready 无组合关系。
            assign lane_s2m_flat[B + S2M_AWREADY] = aw_in_fire && (aw_grant == LANE_W'(gi));
            assign lane_s2m_flat[B + S2M_WREADY]  = w_in_ready  && w_open    && (w_sel  == LANE_W'(gi));
            assign lane_s2m_flat[B + S2M_BVALID]  = b_valid_q;
            assign lane_s2m_flat[B + S2M_BID   +: 4]    = b_id_q;
            assign lane_s2m_flat[B + S2M_BRESP +: 2]    = b_resp_q;
            // ARREADY 必须和 skid 的"接受"条件一致，即 ar_in_fire，**不能再用 bas_arready**。
            // B6402 首次上板前仿真卡死就是这么来的：请求在 ar_in_fire 那一拍就进了 ar_out_data
            // （或备用级），但 lane 看到的是 bas_arready，于是 hub 已经收下、lane 却继续拉高
            // ARVALID，ar_grant 转一圈回来后又把同一笔 AR 抓一次 → 重复 AR → 没人认领的 R 响应，
            // RID 路由对不上就挂住。对比 W 通道：WREADY = w_in_ready(寄存器) && ...，本来就是对的。
            // 这样也顺带把 bas_arready 从 lane 的 ready 路径上彻底摘掉——这才是加 skid 的本来目的。
            assign lane_s2m_flat[B + S2M_ARREADY] = ar_in_fire && (ar_grant == LANE_W'(gi));
            assign lane_s2m_flat[B + S2M_RVALID]        = r_valid_q;
            assign lane_s2m_flat[B + S2M_RLAST]         = r_last_q;
            assign lane_s2m_flat[B + S2M_RID   +: 4]    = r_id_q;
            assign lane_s2m_flat[B + S2M_RDATA +: 1024] = r_data_q;
            assign lane_s2m_flat[B + S2M_RRESP +: 2]    = r_resp_q;
        end
    endgenerate
endmodule
`default_nettype wire
