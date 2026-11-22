// roce_pfc.sv
// RoCE 引擎的 PFC 控制器（收、发两个方向）。地址表必须与 code/rdmasw/include/yuanrdma_hw.h 的
// YNRDMA_PFC_* 以及 deploy/yuancli 的 PFC_* 一致，三处一起改。
//
// 为什么判定放在 mac_clk 域
//   F-tile 的 i_tx_pfc / i_tx_pause 与 o_rx_pfc / o_rx_pause 都在 eth_mac_clk（= o_clk_pll，
//   A 型板 415 MHz）域；rx_front 的 staging 占用、RoCE 每 lane TX 出口也在同一域。PFC 的
//   响应时间要紧（400G 下 1 µs ≈ 50 KB），所以收发两个方向的判定都在 mac 域完成；跨域的只有
//   配置 bundle（准静态，两级同步）与给 core 域准入/计数用的电平（两级同步）。
//
// ---------------------------------------------------------------------------------------------
// 收方向（我们被对端暂停）
//   pause[8] = rx_pfc[8] && HONOR8                         802.3x：全部优先级
//   pause[p] = rx_pfc[p] && HONOR[p] && !rx_wd_hit[p]      802.1Qbb：只停优先级 p
//   CTRL2.ANY_ALL：任一优先级被暂停 ⇒ 8 个优先级全停（对端只能整体暂停/映射对不上时的兜底）
//   CTRL.RX_EN=0 时 pause 恒 0（A/B 对照用）。
//   落点有三处（都按 QPC 的 TOS[7:5] 取优先级，与 rx_front 发 XOFF 的分类口径一致）：
//     ① roce_req 派发新 WQE（pause_core）                —— 不让新包进流水
//     ② roce_resp 发 ACK / READ RESP（pause_core，CTRL.RESP_GATE）
//     ③ 每 lane TX 出口按帧头 TOS 在帧边界挡（pause_mac，CTRL.EGRESS_GATE，roce_pfc_egress.sv）
//        —— 已在流水里的包（每 lane 最多 16 个在途 job + 出口 FIFO）不会在 pause 后继续上线，
//        pause 生效后每 lane 至多再发完当前这一帧。只靠①时最坏还能漏出 4 lane × 16 × MTU。
//   rx_wd_hit[p]：对端连续暂停该优先级超过 WD_RX_US 后不再理会（默认关闭：不理会对端 pause
//     本身就破坏无损，只在对端有 bug / PFC 死锁时由软件打开）。
//
// 发方向（我们暂停对端）
//   每 lane、每优先级的 staging 占用 occ[lane][p]（roce_rx_front，单位拍 = 128 B）：
//     置位：TX_MASK[p] && (任一 lane occ >= XOFF_THR[p] 或该优先级本拍有丢帧)
//     清除：所有 lane occ <= XON_THR[p] 且最短保持 HOLD_US 到时 —— 迟滞 + 最短保持，防抖
//   升级为「全部暂停」（按优先级发不了就全停）：
//     ① 拥塞的优先级不在 TX_MASK 里（我们没资格单独暂停它）；
//     ② 任一 lane 的总占用 >= ALL_THR；
//     ③ CTRL2.GLOBAL=1：任何拥塞都直接整体暂停。
//     升级后的形式：CTRL2.MODE8=1 → i_tx_pause（802.3x，停全部）；
//                   CTRL2.MODE8=0 → TX_MASK 里的优先级全部拉高（PFC 全停），
//                   CTRL2.ESC8=1 时另外再叠一路 802.3x。
//     升级同样带最短保持（esc_hold），不会随占用抖动逐拍开关。
//   TX 看门狗：某优先级 XOFF 连续保持超过 WD_TX_US（默认 100 ms）时强制放开并计数 —— 本端 RX
//     一旦卡死（PCIe/驱动挂住），不放开会把对端永远按死。源电平回落后重新武装。
//
// ---------------------------------------------------------------------------------------------
// 计数（core 域，TICK 单位 = core_clk 拍；A 卡 250 MHz → 4 ns，换算 µs 除以 CORE_CLOCK_MHZ）
//   0x900 + 4*k：
//     k = 0..8    RX_EVT[p]   生效的被暂停段数（上升沿；刷新帧不产生新段，所以不是帧数）
//     k = 9..17   RX_TICK[p]  生效的被暂停持续拍数
//     k = 18..26  TX_EVT[p]   我们发出 XOFF 的段数
//     k = 27..35  TX_TICK[p]  我们发出 XOFF 的持续拍数
//     k = 36..43  DROP[p]     staging 满整帧丢弃（按优先级）
//     k = 44      RX_WD_TRIP  接收侧看门狗触发次数（上升沿）
//     k = 45      TX_WD_TRIP  发送侧看门狗触发次数（上升沿）
//     k = 46      EGRESS_HOLD_TICK  任一 RoCE lane 出口因 pause 挡帧的拍数
//     k = 47      ESCALATE_EVT     升级为整体暂停的次数
//   写 0x9FC 清全部计数（DROP 用基线相减实现：源计数器在 mac 域，不能从 core 域清）。
`default_nettype none
`timescale 1ns/1ps
module roce_pfc #(
    parameter int CORE_CLOCK_MHZ = 250,
    parameter int MAC_CLOCK_MHZ  = 415,   // eth_mac_clk（F-tile o_clk_pll），只用于 µs tick
    parameter int RX_LANES       = 2,     // MAC 输入 lane 数（= roce_rx_front 的两路）
    parameter int TX_LANES       = 4      // RoCE 引擎 lane 数（出口挡帧的 lane）
)(
    // ---------------------------------------------------------------- core 域
    input  wire                       clk,
    input  wire                       rst,
    input  wire  [19:0]               reg_offset,      // 读地址（roce_avm_cdc 保持到读响应）
    input  wire  [19:0]               reg_write_offset,// 写地址（roce_csr 的 register_offset，与 reg_write 同拍）
    input  wire                       reg_write,       // 单拍；本模块自己按地址译码，只响应 0x0800..0x09FC
    input  wire  [31:0]               reg_write_data,
    output reg   [31:0]               reg_read_data,   // 组合读（偏移由 roce_csr 保持到读响应）
    output wire  [8:0]                pause_core,      // 收方向生效 pause：[8]=802.3x
    output wire                       resp_gate_core,  // CTRL.RESP_GATE
    // ---------------------------------------------------------------- mac 域
    input  wire                       mac_clk,
    input  wire                       mac_rst,
    input  wire  [RX_LANES*8*10-1:0]  lane_occupancy,  // 每 lane 每优先级 staging 占用（拍）
    input  wire  [RX_LANES*8-1:0]     lane_drop,       // 每 lane 每优先级「暂存满整帧丢弃」单拍脉冲
    input  wire  [8:0]                rx_pfc,          // F-tile {o_rx_pause, o_rx_pfc[7:0]}
    output wire  [8:0]                tx_pfc,          // F-tile {i_tx_pause, i_tx_pfc[7:0]}
    output wire  [8:0]                pause_mac,       // 收方向生效 pause（mac 域，给出口挡帧）
    output wire                       egress_gate_mac, // CTRL.EGRESS_GATE（mac 域）
    input  wire  [TX_LANES-1:0]       egress_hold      // 每 lane 出口正在挡帧（mac 域电平）
);
    // ================================================================ 地址表
    localparam logic [19:0] A_ID       = 20'h00800;   // RO 0x5046_4301（"PFC" v1）
    localparam logic [19:0] A_CTRL     = 20'h00804;
    localparam logic [19:0] A_TX_MASK  = 20'h00808;
    localparam logic [19:0] A_RX_HONOR = 20'h0080C;
    localparam logic [19:0] A_CTRL2    = 20'h00810;
    localparam logic [19:0] A_ALL_THR  = 20'h00814;
    localparam logic [19:0] A_HOLD_US  = 20'h00818;
    localparam logic [19:0] A_WD_TX_US = 20'h0081C;
    localparam logic [19:0] A_WD_RX_US = 20'h00820;
    localparam logic [19:0] A_STATUS   = 20'h00824;
    localparam logic [19:0] A_STATUS2  = 20'h00828;
    localparam logic [19:0] A_WD_WARN  = 20'h0082C;   // RW XOFF 持续超此值只告警、不关 PFC（B6434；0 = 关）
    localparam logic [19:0] A_XOFF_THR = 20'h00840;   // +4*p
    localparam logic [19:0] A_XON_THR  = 20'h00860;   // +4*p
    localparam logic [19:0] A_OCC      = 20'h00880;   // +4*(lane*8+p)
    localparam logic [19:0] A_CNT      = 20'h00900;   // 48 个计数器
    localparam logic [19:0] A_CLEAR    = 20'h009FC;

    // CTRL 位（复位 0x0F）
    localparam int C_TX_EN       = 0;   // 自动发 XOFF（0 = 只统计、不发）
    localparam int C_RX_EN       = 1;   // 按收到的 pause 停发
    localparam int C_RESP_GATE   = 2;   // ACK / READ RESP 也按 pause 挡
    localparam int C_EGRESS_GATE = 3;   // 每 lane 出口按帧头优先级挡
    // CTRL2 位（复位 0）
    localparam int C2_GLOBAL  = 0;
    localparam int C2_MODE8   = 1;
    localparam int C2_ESC8    = 2;
    localparam int C2_ANY_ALL = 3;
    localparam int C2_RX_WD   = 4;

    // ================================================================ core 域配置
    reg  [7:0]  cfg_tx_mask;
    reg  [7:0]  cfg_rx_honor;
    reg         cfg_honor8;
    reg  [11:0] cfg_all_thr;
    reg  [15:0] cfg_hold_us;
    reg  [23:0] cfg_wd_tx_us;
    reg  [23:0] cfg_wd_rx_us;
    reg  [23:0] cfg_wd_warn_us;         // B6434：只告警的阈值（0 = 关）
    reg  [3:0]  cfg_ctrl;
    reg  [4:0]  cfg_ctrl2;
    reg  [9:0]  cfg_xoff_thr [0:7];
    reg  [9:0]  cfg_xon_thr  [0:7];

    // 复位默认：收发都开、8 个优先级都允许暂停/都理会。阈值按 staging（每 lane 512 拍 = 64 KB）
    // 的一半 / 四分之一：XOFF 后还剩 256 拍 = 32 KB 余量，400G 单 lane ~200 Gb/s 下约 1.3 µs，
    // 覆盖对端反应（802.3bs 规定 400G 最长 905 quanta ≈ 1.16 µs）与在途帧；总占用 448 拍
    // 升级为整体暂停。最短保持 10 µs：staging 64 KB 在 ~80 Gb/s 下约 6.5 µs 排空，100 µs（B6432 及以前）把对端
    // 按停太久，无损但 client read 77→41 Gb/s；10 µs 无损且 78.75，2 µs 带宽相同但 pause 帧翻倍（§56.3）。
    integer i;
    always @(posedge clk) begin
        if (rst) begin
            cfg_tx_mask  <= 8'hFF;
            cfg_rx_honor <= 8'hFF;
            cfg_honor8   <= 1'b1;
            cfg_all_thr  <= 12'd448;
            cfg_hold_us  <= 16'd10;     // B6432 上板：100 µs 时无损但 client read 77→41 Gb/s；10 µs 无损且 78.75（§56.3）
            cfg_wd_tx_us <= 24'd100_000;
            cfg_wd_rx_us <= 24'd0;
            cfg_wd_warn_us <= 24'd0;    // B6434：默认关（只在显式配置时告警）
            cfg_ctrl     <= 4'b1111;
            cfg_ctrl2    <= 5'b00000;
            for (i = 0; i < 8; i = i + 1) begin
                cfg_xoff_thr[i] <= 10'd256;
                cfg_xon_thr[i]  <= 10'd128;
            end
        end else if (reg_write) begin
            case (reg_write_offset)
                A_CTRL:     cfg_ctrl     <= reg_write_data[3:0];
                A_TX_MASK:  cfg_tx_mask  <= reg_write_data[7:0];
                A_RX_HONOR: begin cfg_rx_honor <= reg_write_data[7:0]; cfg_honor8 <= reg_write_data[8]; end
                A_CTRL2:    cfg_ctrl2    <= reg_write_data[4:0];
                A_ALL_THR:  cfg_all_thr  <= reg_write_data[11:0];
                A_HOLD_US:  cfg_hold_us  <= reg_write_data[15:0];
                A_WD_TX_US: cfg_wd_tx_us <= reg_write_data[23:0];
                A_WD_RX_US: cfg_wd_rx_us <= reg_write_data[23:0];
                A_WD_WARN:  cfg_wd_warn_us <= reg_write_data[23:0];
                default: ;
            endcase
            if (reg_write_offset >= A_XOFF_THR && reg_write_offset < A_XOFF_THR + 20'd32)
                cfg_xoff_thr[reg_write_offset[4:2]] <= reg_write_data[9:0];
            if (reg_write_offset >= A_XON_THR && reg_write_offset < A_XON_THR + 20'd32)
                cfg_xon_thr[reg_write_offset[4:2]] <= reg_write_data[9:0];
        end
    end
    wire clear_pulse = reg_write && (reg_write_offset == A_CLEAR);
    assign resp_gate_core = cfg_ctrl[C_RESP_GATE];

    // ---------------------------------------------------------------- 配置 bundle → mac 域
    // 阈值/掩码在 mac 域参与比较，必须整包同步。准静态（只在软件写时变），两级寄存足够；
    // 写入当拍各位可能先后到达，最多造成一两拍的混合配置，不构成握手、不会卡死。
    wire [79:0] xoff_thr_flat, xon_thr_flat;
    genvar gx;
    generate
        for (gx = 0; gx < 8; gx = gx + 1) begin : gen_thr_flat
            assign xoff_thr_flat[gx*10 +: 10] = cfg_xoff_thr[gx];
            assign xon_thr_flat [gx*10 +: 10] = cfg_xon_thr [gx];
        end
    endgenerate
    localparam int CFG_W = 80 + 80 + 8 + 8 + 1 + 12 + 16 + 24 + 24 + 24 + 4 + 5;   // 286（B6434 加 WD_WARN）
    wire [CFG_W-1:0] cfg_bundle = {cfg_ctrl2, cfg_ctrl, cfg_wd_warn_us, cfg_wd_rx_us, cfg_wd_tx_us, cfg_hold_us,
                                   cfg_all_thr, cfg_honor8, cfg_rx_honor, cfg_tx_mask,
                                   xoff_thr_flat, xon_thr_flat};
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    reg [CFG_W-1:0] cfg_sync1, cfg_sync2;
    always @(posedge mac_clk) begin
        cfg_sync1 <= cfg_bundle;
        cfg_sync2 <= cfg_sync1;
    end
    wire [4:0]  m_ctrl2     = cfg_sync2[285:281];
    wire [3:0]  m_ctrl      = cfg_sync2[280:277];
    wire [23:0] m_wd_warn_us= cfg_sync2[276:253];
    wire [23:0] m_wd_rx_us  = cfg_sync2[252:229];
    wire [23:0] m_wd_tx_us  = cfg_sync2[228:205];
    wire [15:0] m_hold_us   = cfg_sync2[204:189];
    wire [11:0] m_all_thr   = cfg_sync2[188:177];
    wire        m_honor8    = cfg_sync2[176];
    wire [7:0]  m_rx_honor  = cfg_sync2[175:168];
    wire [7:0]  m_tx_mask   = cfg_sync2[167:160];
    wire [79:0] m_xoff_flat = cfg_sync2[159:80];
    wire [79:0] m_xon_flat  = cfg_sync2[79:0];
    wire        m_tx_en     = m_ctrl[C_TX_EN];
    wire        m_rx_en     = m_ctrl[C_RX_EN];
    assign egress_gate_mac  = m_ctrl[C_EGRESS_GATE];

    // ================================================================ mac 域：µs tick
    reg  [15:0] us_div;
    wire        us_tick = (us_div == 16'(MAC_CLOCK_MHZ - 1));
    always @(posedge mac_clk) begin
        if (mac_rst) us_div <= 16'd0;
        else         us_div <= us_tick ? 16'd0 : (us_div + 16'd1);
    end

    // ================================================================ mac 域：收方向
    // o_rx_pfc / o_rx_pause 与 eth_mac_clk 同源，仍先打两拍：F-tile 侧时钟若有变动不会静默出错。
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    reg  [8:0]  rx_pfc_s1, rx_pfc_s2;
    always @(posedge mac_clk) begin
        rx_pfc_s1 <= rx_pfc;
        rx_pfc_s2 <= rx_pfc_s1;
    end
    wire [7:0]  rx_raw = rx_pfc_s2[7:0] & m_rx_honor;

    reg  [7:0]  rx_wd_hit;
    reg  [23:0] rx_wd_cnt [0:7];
    reg         rx_wd_hit8;             // B6435：802.3x 的看门狗命中位
    reg  [23:0] rx_wd_cnt8;
    reg  [7:0]  pause_lvl;
    reg         pause_lvl8;
    integer rp;
    always @(posedge mac_clk) begin
        if (mac_rst) begin
            pause_lvl  <= 8'd0;
            pause_lvl8 <= 1'b0;
            rx_wd_hit  <= 8'd0;
            rx_wd_hit8 <= 1'b0;
            rx_wd_cnt8 <= 24'd0;
            for (rp = 0; rp < 8; rp = rp + 1) rx_wd_cnt[rp] <= 24'd0;
        end else begin
            // B6435：802.3x 也走同一条看门狗。对端若一直按着全局 pause（MAC 卡死/对端 bug），
            // 之前没有任何超时能救，本端 TX 永久停发；per-priority 路径早就有这层保护。
            if (!(rx_pfc_s2[8] & m_honor8) || !m_ctrl2[C2_RX_WD] || (m_wd_rx_us == 24'd0)) begin
                rx_wd_cnt8 <= 24'd0;
                rx_wd_hit8 <= 1'b0;
            end else if (!rx_wd_hit8 && us_tick) begin
                if (rx_wd_cnt8 + 24'd1 >= m_wd_rx_us) rx_wd_hit8 <= 1'b1;
                rx_wd_cnt8 <= rx_wd_cnt8 + 24'd1;
            end
            pause_lvl8 <= rx_pfc_s2[8] & m_honor8 & m_rx_en & ~rx_wd_hit8;
            for (rp = 0; rp < 8; rp = rp + 1) begin
                // 看门狗只在「理会的 pause 连续有效」时计时；pause 一释放就清零、重新武装。
                // B6435：软件把 RX_WD_EN 关掉或把 WD_RX_US 写成 0 时也要清零——否则已经命中的
                // rx_wd_hit 会一直保持，pause 继续被忽略，A/B 对照「关掉看门狗就恢复理会」不成立。
                if (!rx_raw[rp] || !m_ctrl2[C2_RX_WD] || (m_wd_rx_us == 24'd0)) begin
                    rx_wd_cnt[rp] <= 24'd0;
                    rx_wd_hit[rp] <= 1'b0;
                end else if (m_ctrl2[C2_RX_WD] && (m_wd_rx_us != 24'd0) && !rx_wd_hit[rp] && us_tick) begin
                    if (rx_wd_cnt[rp] + 24'd1 >= m_wd_rx_us) rx_wd_hit[rp] <= 1'b1;
                    rx_wd_cnt[rp] <= rx_wd_cnt[rp] + 24'd1;
                end
            end
            if (!m_rx_en)
                pause_lvl <= 8'd0;
            else if (m_ctrl2[C2_ANY_ALL])
                pause_lvl <= (|(rx_raw & ~rx_wd_hit)) ? 8'hFF : 8'd0;
            else
                pause_lvl <= rx_raw & ~rx_wd_hit;
        end
    end
    assign pause_mac = {pause_lvl8, pause_lvl};

    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    reg  [8:0]  pause_core_s1, pause_core_s2;
    always @(posedge clk) begin
        pause_core_s1 <= pause_mac;
        pause_core_s2 <= pause_core_s1;
    end
    assign pause_core = pause_core_s2;

    // ================================================================ mac 域：发方向
    // 比较都先打一拍（occ_hi_q / occ_lo_q / total_hi_q），把 16 路 10 位比较与 8 路求和从
    // 415 MHz 的单拍路径里拆出去。多 1 拍（2.4 ns）对 µs 级的 PFC 反应时间没有影响。
    reg  [7:0]  occ_hi_q, occ_lo_q, drop_q;
    reg         total_hi_q;
    // lane_total 的位宽是 13：8 路 × 10 位，每路最大 1023，和为 8184，12 位会回绕
    // （m_all_thr 的上限是 4095，回绕后比较会漏判整体拥塞）。
    reg  [12:0] lane_total_q [0:RX_LANES-1];
    integer lp, ll;
    // 函数定义放在使用之前：SystemVerilog 对模块级函数没有「先声明后使用」的要求
    // （Quartus 与 verilator 都接受后置定义），但前置是零成本的，读代码时不用往回翻。
    // 注意：注释行不要以 "Verilator" 开头——verilator 会把它当成 //%verilator 元注释解析并报错。
    function automatic [12:0] lane_total(input integer ln);
        integer q;
        begin
            lane_total = 13'd0;
            for (q = 0; q < 8; q = q + 1) lane_total = lane_total + {3'd0, lane_occupancy[(ln*8 + q)*10 +: 10]};
        end
    endfunction
    always @(posedge mac_clk) begin
        if (mac_rst) begin
            occ_hi_q   <= 8'd0;
            occ_lo_q   <= 8'hFF;
            drop_q     <= 8'd0;
            total_hi_q <= 1'b0;
            for (ll = 0; ll < RX_LANES; ll = ll + 1) lane_total_q[ll] <= 13'd0;
        end else begin
            for (lp = 0; lp < 8; lp = lp + 1) begin
                occ_hi_q[lp] <= 1'b0;
                occ_lo_q[lp] <= 1'b1;
                drop_q[lp]   <= 1'b0;
                for (ll = 0; ll < RX_LANES; ll = ll + 1) begin
                    if (lane_occupancy[(ll*8 + lp)*10 +: 10] >= m_xoff_flat[lp*10 +: 10]) occ_hi_q[lp] <= 1'b1;
                    if (lane_occupancy[(ll*8 + lp)*10 +: 10] >  m_xon_flat [lp*10 +: 10]) occ_lo_q[lp] <= 1'b0;
                    if (lane_drop[ll*8 + lp])                                             drop_q[lp]   <= 1'b1;
                end
            end
            // 8 路 10 位求和打一拍（lane_total_q），比较放在下一拍：415 MHz 下单拍里
            // 「8 级加法树 + 13 位比较」是这条时钟域里最深的一条组合路径。多 1 拍（2.4 ns）
            // 对 µs 级的 PFC 反应时间没有影响（ALL_THR 是 448 拍量级的阈值）。
            total_hi_q <= 1'b0;
            for (ll = 0; ll < RX_LANES; ll = ll + 1) begin
                lane_total_q[ll] <= lane_total(ll);
                if (lane_total_q[ll] >= {1'b0, m_all_thr}) total_hi_q <= 1'b1;
            end
        end
    end

    wire [7:0] cong      = occ_hi_q | drop_q;              // 本拍拥塞的优先级
    wire [7:0] unl_cong  = cong & ~m_tx_mask;              // 拥塞但无权单独暂停
    wire       esc_now   = m_ctrl2[C2_GLOBAL] ? (|cong) : ((|unl_cong) || total_hi_q);

    reg  [7:0]  xoff_src;
    reg  [7:0]  tx_wd_force;
    reg  [7:0]  tx_wd_warn;         // B6434：持续 XOFF 超过 WD_WARN_US 的告警位（只告警，不放开）
    reg  [15:0] hold_cnt [0:7];
    reg  [23:0] tx_wd_cnt [0:7];
    reg         esc_src;
    reg  [15:0] esc_hold;
    reg  [7:0]  xoff_out;
    reg         pause_out8;
    integer tp;
    always @(posedge mac_clk) begin
        if (mac_rst) begin
            xoff_src    <= 8'd0;
            tx_wd_force <= 8'd0;
            tx_wd_warn  <= 8'd0;
            esc_src     <= 1'b0;
            esc_hold    <= 16'd0;
            xoff_out    <= 8'd0;
            pause_out8  <= 1'b0;
            for (tp = 0; tp < 8; tp = tp + 1) begin
                hold_cnt[tp]  <= 16'd0;
                tx_wd_cnt[tp] <= 24'd0;
            end
        end else begin
            for (tp = 0; tp < 8; tp = tp + 1) begin
                // 迟滞 + 最短保持：置位时装载保持计数；保持计数每 µs 减一；
                // 只有占用回到 XON 以下（occ_lo_q）且保持计数归零才清。
                if (m_tx_mask[tp] && cong[tp]) begin
                    xoff_src[tp] <= 1'b1;
                    hold_cnt[tp] <= m_hold_us;
                end else begin
                    if (us_tick && (hold_cnt[tp] != 16'd0)) hold_cnt[tp] <= hold_cnt[tp] - 16'd1;
                    if (occ_lo_q[tp] && (hold_cnt[tp] == 16'd0)) xoff_src[tp] <= 1'b0;
                end
                // TX 看门狗：连续 XOFF 超时 → 强制放开，直到源电平自己回落
                // B6434：告警阈值（WD_WARN_US）用同一个计数器，只置告警位、不放开 XOFF。
                // 计数推进条件保持与 B6433 一致——两个阈值都为 0 时不计数。
                if (!xoff_src[tp]) begin
                    tx_wd_cnt[tp]   <= 24'd0;
                    tx_wd_force[tp] <= 1'b0;
                    tx_wd_warn[tp]  <= 1'b0;
                end else begin
                    if (us_tick && (((m_wd_tx_us   != 24'd0) && !tx_wd_force[tp]) ||
                                    ((m_wd_warn_us != 24'd0) && !tx_wd_warn[tp])))
                        tx_wd_cnt[tp] <= (tx_wd_cnt[tp] == 24'hFFFFFF) ? tx_wd_cnt[tp]
                                                                      : tx_wd_cnt[tp] + 24'd1;
                    if ((m_wd_tx_us != 24'd0) && !tx_wd_force[tp] && us_tick &&
                        (tx_wd_cnt[tp] + 24'd1 >= m_wd_tx_us))
                        tx_wd_force[tp] <= 1'b1;
                    if ((m_wd_warn_us != 24'd0) && !tx_wd_warn[tp] && us_tick &&
                        (tx_wd_cnt[tp] + 24'd1 >= m_wd_warn_us))
                        tx_wd_warn[tp] <= 1'b1;
                end
            end
            // 整体暂停（升级）同样迟滞 + 最短保持；释放条件：不再满足升级条件且全部优先级回到 XON 以下
            if (esc_now) begin
                esc_src  <= 1'b1;
                esc_hold <= m_hold_us;
            end else begin
                if (us_tick && (esc_hold != 16'd0)) esc_hold <= esc_hold - 16'd1;
                if ((&occ_lo_q) && (esc_hold == 16'd0)) esc_src <= 1'b0;
            end
            // 输出
            if (m_ctrl2[C2_MODE8]) begin
                xoff_out   <= 8'd0;
                // B6435：释放条件改成「还有未被看门狗强制的拥塞优先级」才按着。
                // 原来是 !(&tx_wd_force)，只要有一个优先级没被强制就永远按着 802.3x——
                // 单优先级拥塞时看门狗已经放开，802.3x 却解不开。
                pause_out8 <= m_tx_en && ((|(xoff_src & ~tx_wd_force)) ||
                                          (esc_src && (|(cong & ~tx_wd_force))));
            end else begin
                pause_out8 <= m_tx_en && m_ctrl2[C2_ESC8] && esc_src && !(&tx_wd_force);
                // B6435：GLOBAL=1 是「任何拥塞都整体暂停」，不能因为 TX_MASK=0 而什么都不发
                for (tp = 0; tp < 8; tp = tp + 1)
                    xoff_out[tp] <= m_tx_en && !tx_wd_force[tp] &&
                                    (xoff_src[tp] ||
                                     (esc_src && (m_tx_mask[tp] || m_ctrl2[C2_GLOBAL])));
            end
        end
    end
    assign tx_pfc = {pause_out8, xoff_out};

    // ================================================================ core 域：计数
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    reg  [8:0]  tx_s1, tx_s2;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    reg  [24:0] wd_s1, wd_s2;        // {rx_wd_hit8, rx_wd_hit, tx_wd_force, tx_wd_warn} 观测与计数
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    reg  [1:0]  esc_s1, esc_s2;      // {esc_src, |egress_hold}
    always @(posedge clk) begin
        tx_s1  <= tx_pfc;
        tx_s2  <= tx_s1;
        wd_s1  <= {rx_wd_hit8, rx_wd_hit, tx_wd_force, tx_wd_warn};
        wd_s2  <= wd_s1;
        esc_s1 <= {esc_src, |egress_hold};
        esc_s2 <= esc_s1;
    end
    wire [7:0] rx_wd_core  = wd_s2[23:16];
    wire [7:0] tx_wd_core  = wd_s2[15:8];
    wire [7:0] tx_wn_core  = wd_s2[7:0];
    wire       rx_wd8_core = wd_s2[24];            // B6435：802.3x 看门狗命中
    wire       esc_core    = esc_s2[1];
    wire       egress_core = esc_s2[0];

    reg  [8:0]  rx_d, tx_d;
    reg         rx_wd_any_d, tx_wd_any_d, tx_wn_any_d, esc_d;
    always @(posedge clk) begin
        rx_d        <= pause_core_s2;
        tx_d        <= tx_s2;
        rx_wd_any_d <= |rx_wd_core || rx_wd8_core;
        tx_wd_any_d <= |tx_wd_core;
        tx_wn_any_d <= |tx_wn_core;
        esc_d       <= esc_core;
    end

    reg  [31:0] cnt [0:48];
    wire [31:0] drop_src [0:7];
    reg  [31:0] drop_base [0:7];
    integer c;
    always @(posedge clk) begin
        if (rst || clear_pulse) begin
            for (c = 0; c < 49; c = c + 1) cnt[c] <= 32'd0;
            for (c = 0; c < 8; c = c + 1)  drop_base[c] <= rst ? 32'd0 : drop_src[c];
        end else begin
            for (c = 0; c < 9; c = c + 1) begin
                if (pause_core_s2[c] && !rx_d[c]) cnt[c]      <= cnt[c] + 32'd1;
                if (pause_core_s2[c])             cnt[9 + c]  <= cnt[9 + c] + 32'd1;
                if (tx_s2[c] && !tx_d[c])         cnt[18 + c] <= cnt[18 + c] + 32'd1;
                if (tx_s2[c])                     cnt[27 + c] <= cnt[27 + c] + 32'd1;
            end
            for (c = 0; c < 8; c = c + 1) cnt[36 + c] <= drop_src[c] - drop_base[c];
            if (((|rx_wd_core) || rx_wd8_core) && !rx_wd_any_d) cnt[44] <= cnt[44] + 32'd1;
            if ((|tx_wd_core) && !tx_wd_any_d) cnt[45] <= cnt[45] + 32'd1;
            if (egress_core)                   cnt[46] <= cnt[46] + 32'd1;
            if (esc_core && !esc_d)            cnt[47] <= cnt[47] + 32'd1;
            if ((|tx_wn_core) && !tx_wn_any_d) cnt[48] <= cnt[48] + 32'd1;   // B6434 告警
        end
    end

    // 丢帧：mac 域脉冲 → 每优先级一个格雷码计数器 → core 域绝对值（清零用基线相减）
    genvar gd;
    generate
        for (gd = 0; gd < 8; gd = gd + 1) begin : gen_drop
            reg drop_or;
            integer dl;
            always @* begin
                drop_or = 1'b0;
                for (dl = 0; dl < RX_LANES; dl = dl + 1) drop_or = drop_or | lane_drop[dl*8 + gd];
            end
            roce_gray_cnt u_drop_cnt (
                .source_clk(mac_clk), .source_rst(mac_rst),
                .source_increment(drop_or),
                .dest_clk(clk), .dest_count(drop_src[gd]));
        end
    endgenerate

    // 占用观测副本（mac → core，只给读口；本来就是渐变的观测量，两级寄存足够）
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    reg  [RX_LANES*8*10-1:0] occ_s1, occ_s2;
    always @(posedge clk) begin
        occ_s1 <= lane_occupancy;
        occ_s2 <= occ_s1;
    end

    // ================================================================ core 域：读口
    wire [19:0] cnt_rel = reg_offset - A_CNT;
    wire [19:0] occ_rel = reg_offset - A_OCC;
    always @* begin
        reg_read_data = 32'hdeadbeef;
        if (reg_offset >= A_CNT && reg_offset < A_CNT + 20'd196)
            reg_read_data = cnt[cnt_rel[7:2]];
        else if (reg_offset >= A_OCC && reg_offset < A_OCC + 20'(4*RX_LANES*8))
            reg_read_data = {22'd0, occ_s2[occ_rel[6:2]*10 +: 10]};
        else if (reg_offset >= A_XOFF_THR && reg_offset < A_XOFF_THR + 20'd32)
            reg_read_data = {22'd0, cfg_xoff_thr[reg_offset[4:2]]};
        else if (reg_offset >= A_XON_THR && reg_offset < A_XON_THR + 20'd32)
            reg_read_data = {22'd0, cfg_xon_thr[reg_offset[4:2]]};
        else case (reg_offset)
            A_ID:       reg_read_data = 32'h5046_4301;
            A_CTRL:     reg_read_data = {28'd0, cfg_ctrl};
            A_TX_MASK:  reg_read_data = {24'd0, cfg_tx_mask};
            A_RX_HONOR: reg_read_data = {23'd0, cfg_honor8, cfg_rx_honor};
            A_CTRL2:    reg_read_data = {27'd0, cfg_ctrl2};
            A_ALL_THR:  reg_read_data = {20'd0, cfg_all_thr};
            A_HOLD_US:  reg_read_data = {16'd0, cfg_hold_us};
            A_WD_TX_US: reg_read_data = {8'd0, cfg_wd_tx_us};
            A_WD_RX_US: reg_read_data = {8'd0, cfg_wd_rx_us};
            A_WD_WARN:  reg_read_data = {8'd0, cfg_wd_warn_us};
            // STATUS：[8:0] 收方向生效 pause  [24:16] 我们发出的 tx_pfc  [25] 升级中  [26] 出口挡帧中
            A_STATUS:   reg_read_data = {5'd0, egress_core, esc_core, tx_s2, 7'd0, pause_core_s2};
            // STATUS2：[7:0] 接收看门狗命中  [15:8] 发送看门狗强制放开  [23:16] 发送看门狗告警（B6434）
            // STATUS2：[7:0] 接收看门狗命中  [15:8] 发送看门狗强制放开  [23:16] 发送看门狗告警（B6434）
            //         [24] 802.3x 接收看门狗命中（B6435）
            A_STATUS2:  reg_read_data = {7'd0, rx_wd8_core, tx_wn_core, tx_wd_core, rx_wd_core};
            default: ;
        endcase
    end

endmodule
`default_nettype wire
