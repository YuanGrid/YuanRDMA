// roce_cnp.sv
// ECN / CNP 的 NP 侧（接收端）：收到 ECN==CE 的 RoCE 包 → 限频生成本端口的 CNP。
//
// 角色：RoCEv2 里 CP = 交换机（按 RED 曲线把队列超阈值的包标 CE），NP = 收包网卡
// （看到 CE 就回一个 CNP 给发送方），RP = 发包网卡（收 CNP 降速）。
// 本模块只做 NP：CE 检测在 roce_rx_parse（header.ecn_congestion = IPv4 TOS[1:0]==2'b11），
// 这里负责「该不该发、多久发一个、发多少个」；CNP 报文本身由 roce_tx 组（opcode 0x81）。
//
// ---------------------------------------------------------------------------------------------
// 为什么限频放在**端口级**而不是每 QP
//   NVIDIA 的 min_time_between_cnps 默认 4 µs 且是端口级（v1 学它）。per-QP 的精确限频需要
//   一张按 QPN 索引的时间戳表，收益很小：CE 标记本来就是突发性的，端口级限频已经能把
//   CNP 风暴挡住。上板如果发现单个 QP 的 CNP 被别的 QP 挤掉，再按 §13 阶段 3 的 RP 表
//   扩成 per-QP（表已经在做，加一个时间戳字段即可）。
//
// 仲裁
//   LANES 个 lane 各自把「最近一个 CE 包的 QP」挂起（roce_engine 里的 cnp_pending），
//   这里做 round-robin 发 grant，一次只 grant 一个 lane，限频定时器到期才发下一个。
//   每个 lane 收到 grant 就用自己那个 QP 组一个 CNP，从**本 lane** 的 roce_tx 出去
//   （CNP 的 dmac/dip/dqpn/sport 都从该 QP 的 QPC 取，所以必须由属主 lane 发）。
//
// 计数器（core 域，拍 = core_clk，A 卡 250 MHz → 4 ns）
//   np_ecn_marked_roce_packets  收到的 CE 数据包数（含被限频丢弃的）——对标 mlx5 同名计数
//   np_cnp_sent                 实际发出的 CNP 数
//   rp_cnp_handled              收到的 CNP 中被处理的（阶段 3 起由 RP 逻辑置位；现在恒 0）
//   rp_cnp_ignored              收到的 CNP 中被忽略的（无此 QP / 未使能）
//   cnp_throttled               CE 包到了但限频窗口没开，被压掉的次数
`default_nettype none
`timescale 1ns/1ps
module roce_cnp #(
    parameter int CORE_CLOCK_MHZ = 250,
    parameter int LANES          = 2
)(
    // ---------------------------------------------------------------- core 域
    input  wire                  clk,
    input  wire                  rst,
    // CSR（偏移由 roce_top 给出，与 roce_pkg 的 REG_CNP_* 一致）
    input  wire [19:0]           reg_offset,
    input  wire [19:0]           reg_write_offset,
    input  wire                  reg_write,
    input  wire [31:0]           reg_write_data,
    output reg  [31:0]           reg_read_data,
    // 配置给各 lane（组合，准静态）
    output wire                  cfg_cnp_en,
    output wire                  cfg_cnp_np_en,      // NP_EN：收到 CE 才发 CNP（B6434 起也门控 lane 的挂起位）
    output wire [7:0]            cfg_cnp_tos,        // 完整 TOS 字节（DSCP<<2 | ECN=00）
    output wire                  cfg_cnp_becn,       // BTH byte4 bit6（B6434，默认 1）
    output wire                  cfg_cnp_fecn,       // BTH byte4 bit7（B6434，默认 0）
    // 事件与仲裁（每 lane）
    input  wire  [LANES-1:0]     cnp_request,        // 有挂起的 CNP
    output reg   [LANES-1:0]     cnp_grant,          // 单拍：本 lane 现在发
    input  wire  [LANES-1:0]     event_ecn_marked,   // 本 lane 收到一个 CE 数据包（单拍）
    input  wire  [LANES-1:0]     event_cnp_sent,     // 本 lane 刚发出一个 CNP（单拍）
    input  wire  [LANES-1:0]     event_cnp_handled,  // RP：本 lane 处理了一个 CNP（阶段 3）
    input  wire  [LANES-1:0]     event_cnp_ignored   // RP：本 lane 忽略了 CNP
);
    // ================================================================ 地址表（0x0A00 窗口）
    localparam logic [19:0] A_ID      = 20'h00A00;  // RO 0x434E5001（"CNP" v1）
    localparam logic [19:0] A_CTRL    = 20'h00A04;  // RW [0]EN [1]NP_EN(收 CE 才发 CNP)
    localparam logic [19:0] A_TOS     = 20'h00A08;  // RW CNP 的 TOS 字节（默认 48<<2 = 0xC0）
    localparam logic [19:0] A_MIN_US  = 20'h00A0C;  // RW 端口级限频 µs（默认 4）
    localparam logic [19:0] A_STATUS  = 20'h00A10;  // RO [0]有 lane 在等 grant [1]限频窗口开着
    localparam logic [19:0] A_BTH     = 20'h00A14;  // RW [0]BECN [1]FECN（B6434；复位 0x1 = BECN=1 FECN=0）
    localparam logic [19:0] A_CNT     = 20'h00A40;  // 8 个计数器
    localparam logic [19:0] A_CLEAR   = 20'h00AFC;

    localparam int C_EN     = 0;
    localparam int C_NP_EN  = 1;

    reg  [1:0]  cfg_ctrl;
    reg  [7:0]  cfg_tos;
    reg  [15:0] cfg_min_us;
    reg  [1:0]  cfg_bth_flags;          // [0]BECN [1]FECN

    // 8 个计数器的编号（与 yuanrdma_hw.h / rdmacli 一致）
    localparam int CNT_NP_ECN_MARKED = 0;
    localparam int CNT_NP_CNP_SENT   = 1;
    localparam int CNT_RP_HANDLED    = 2;
    localparam int CNT_RP_IGNORED    = 3;
    localparam int CNT_THROTTLED     = 4;
    localparam int CNT_COUNT         = 8;

    always @(posedge clk) begin
        if (rst) begin
            cfg_ctrl   <= 2'b11;
            cfg_tos    <= 8'hC0;        // DSCP 48 << 2，ECN 00（NVIDIA cnp_dscp 默认 48）
            cfg_min_us <= 16'd4;
            cfg_bth_flags <= 2'b01;     // BECN=1 FECN=0（NVIDIA/TCP 语义：CNP 带 BECN）
        end else if (reg_write) begin
            case (reg_write_offset)
                A_CTRL:   cfg_ctrl   <= reg_write_data[1:0];
                // B6435：ECN 位强制 00——CNP 自己被标 CE 会让对端 NP 再回一个 CNP，形成环
                A_TOS:    cfg_tos    <= {reg_write_data[7:2], 2'b00};
                A_MIN_US: cfg_min_us <= reg_write_data[15:0];
                A_BTH:    cfg_bth_flags <= reg_write_data[1:0];
                default: ;
            endcase
        end
    end
    wire clear_pulse = reg_write && (reg_write_offset == A_CLEAR);
    assign cfg_cnp_en  = cfg_ctrl[C_EN];
    // NP_EN 同时给各 lane：只关「grant 生成」不够——lane 里已锁存的挂起位/上锁的 grant
    // 会在 NP_EN 关掉之后被下一个 CE 包重新拉起，照样发 CNP（2026-11-10 仿真定位）。
    assign cfg_cnp_np_en = cfg_ctrl[C_NP_EN];
    assign cfg_cnp_tos = cfg_tos;
    assign cfg_cnp_becn = cfg_bth_flags[0];
    assign cfg_cnp_fecn = cfg_bth_flags[1];

    // ================================================================ 限频与仲裁
    // 定时器：grant 后装载 min_us * CORE_CLOCK_MHZ，递减到 0 才允许下一次。
    // min_us == 0 时不定频（每拍都可以 grant）——上板调试「不限频」的用法。
    reg  [31:0] window;
    reg  [31:0] window_load;
    always @* window_load = 32'(cfg_min_us) * 32'(CORE_CLOCK_MHZ);

    reg  [LANES-1:0] grant_q;
    reg  [LANES-1:0] rr_q;                     // 上一轮被 grant 的 lane（从它的下一位起找）
    // round-robin：从 rr_q 的下一位开始扫描，选第一个有请求的 lane。LANES 是 2 的幂
    // （2 或 4），所以 (rr_q + i + 1) & (LANES-1) 就是循环下标，不需要取模除法。
    reg  [LANES-1:0] rr_pick;
    integer ri;
    always @* begin
        rr_pick = '0;
        for (ri = LANES - 1; ri >= 0; ri = ri - 1)
            if (cnp_request[(32'(rr_q) + 32'(ri) + 32'd1) & 32'(LANES - 1)])
                rr_pick = LANES'(1) << ((32'(rr_q) + 32'(ri) + 32'd1) & 32'(LANES - 1));
    end

    wire window_open = cfg_ctrl[C_EN] && cfg_ctrl[C_NP_EN] && (window == 32'd0);
    wire [LANES-1:0] cnp_requested_lane = rr_pick;
    wire             fire               = window_open && (|cnp_request);

    always @(posedge clk) begin
        if (rst) begin
            grant_q <= '0;
            rr_q    <= '0;
            window  <= 32'd0;
        end else begin
            grant_q <= fire ? cnp_requested_lane : '0;
            if (fire) rr_q <= cnp_requested_lane;
            if (fire)                     window <= window_load;      // 允许 0（= 不限频）
            else if (window != 32'd0)     window <= window - 32'd1;
        end
    end
    always @* cnp_grant = grant_q;

    // ================================================================ 计数
    reg [31:0] cnt [0:CNT_COUNT-1];
    reg        blocked_d;                  // 上一拍的「有请求但发不出去」
    // 一个 CE 包是不是被限频压掉：cnp_request 的上升沿出现在窗口关闭期间。
    // 不能在 window 关闭时每拍计——request 会一直挂着直到 grant，那样一次等待会被记成
    // 几百次。只认上升沿：事件由 lane 侧在「收到 CE 且本来没有挂起」那拍给出，正好一包一次。
    // B6435：NP_EN=0 时不是「被限频压掉」，是故意不回 CNP，不能算 throttled
    wire blocked_now = (|cnp_request) && cfg_ctrl[C_NP_EN] && !window_open;
    integer c;
    always @(posedge clk) begin
        if (rst || clear_pulse) begin
            blocked_d <= 1'b0;
            for (c = 0; c < CNT_COUNT; c = c + 1) cnt[c] <= 32'd0;
        end else begin
            blocked_d <= blocked_now;
            // EN=0 时连 CE 统计都停（A/B 对照要能证明「计数确实来自本模块」）；
            // NP_EN=0 只停发 CNP，仍然统计 CE 包——这正是「看到了但故意不回」的对照。
            if (|event_ecn_marked && cfg_ctrl[C_EN])
                cnt[CNT_NP_ECN_MARKED] <= cnt[CNT_NP_ECN_MARKED] + 32'd1;
            if (|event_cnp_sent)                 cnt[CNT_NP_CNP_SENT]   <= cnt[CNT_NP_CNP_SENT]   + 32'd1;
            if (|event_cnp_handled)              cnt[CNT_RP_HANDLED]    <= cnt[CNT_RP_HANDLED]    + 32'd1;
            if (|event_cnp_ignored)              cnt[CNT_RP_IGNORED]    <= cnt[CNT_RP_IGNORED]    + 32'd1;
            if (blocked_now && !blocked_d)       cnt[CNT_THROTTLED]     <= cnt[CNT_THROTTLED]     + 32'd1;
        end
    end

    // ================================================================ 读口
    wire [19:0] cnt_rel = reg_offset - A_CNT;
    always @* begin
        reg_read_data = 32'hdeadbeef;
        if (reg_offset >= A_CNT && reg_offset < A_CNT + 20'(4*CNT_COUNT))
            reg_read_data = cnt[cnt_rel[4:2]];
        else case (reg_offset)
            A_ID:     reg_read_data = 32'h434E_5001;      // "CNP" v1
            A_CTRL:   reg_read_data = {30'd0, cfg_ctrl};
            A_TOS:    reg_read_data = {24'd0, cfg_tos};
            A_MIN_US: reg_read_data = {16'd0, cfg_min_us};
            A_STATUS: reg_read_data = {30'd0, window_open, |cnp_request};
            A_BTH:    reg_read_data = {30'd0, cfg_bth_flags};
            default: ;
        endcase
    end
endmodule
`default_nettype wire
