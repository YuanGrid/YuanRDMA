// roce_dcqcn.sv
// DCQCN 的 RP 侧（发送端）：每 QP 一个速率上下文，收到 CNP 降速、定时/按字节升速。
//
// 算法出处：Zhu et al. SIGCOMM 2015 §4；参数默认值照 NVIDIA DOCA（NVIDIA 名 → 本实现的 CSR）：
//   dce_tcp_g 1019（10 bit 小数，g = 5/1024）       → 0x0B50 G（B6434 起可配，默认 5）
//   dce_tcp_rtt 1 µs（α 更新周期）                   → 0x0B14 ALPHA_US
//   initial_alpha_value 1023                         → 0x0B4C INIT_ALPHA（B6434，复位值同）
//   rpg_gd 11（RC 降幅 = RC·α/2^11）                 → 硬编码右移 11
//   rpg_min_dec_fac 50 %（单次降幅上限）              → 降幅不超过 RC/2
//   rpg_min_rate 1 Mb/s                              → 0x0B24 MIN_RATE
//   rate_reduce_monitor_period 4 µs                  → 0x0B18 RED_US
//   clamp_tgt_rate Disable                           → 0x0B04 CTRL.CLAMP_RT（默认 0）
//   rpg_time_reset 300 µs                            → 0x0B1C INC_US
//   rpg_byte_reset 32767×64 B                        → 0x0B20 INC_BYTES（默认 2 MB）
//   rpg_threshold 1（F）                              → 0x0B10 THRESH
//   rpg_ai_rate 5 / rpg_hai_rate 50 Mb/s             → 0x0B08 AI / 0x0B0C HAI
//   （另有 0x0B28 LINE 线速，NVIDIA 没有对应项，它从链路速率来）
// 全部做成 CSR（0xB00 窗口），默认值就是上表；CTRL.EN 默认 0 = 完全不限速。
//
// 为什么用「每拍扫一个 QP」而不是每 QP 一套定时器
//   QP_NUM = 16，一轮扫描 16 拍 = 64 ns @250 MHz，比 1 µs 的 α 周期小四个数量级；每 QP 只存
//   时间戳，比较在扫描那一拍做。16 × ~160 bit 的上下文全部是寄存器（16 × 160 = 2560 个触发器，
//   Agilex 7 上一块 ALM 都不缺），不占 M20K，也没有表读写的长路径。
//
// 速率与信用的定点
//   rc / rt 单位 Mb/s（20 bit，够到 1,048,575，线速 400G = 400,000）。
//   credit 单位 = 1/2048 字节，**每 µs 补充一次**：RC Mb/s 在 1 µs 内是 RC/8 字节
//   = RC×256 个信用单位。按 µs 而不是按拍补，是因为按拍补要把 rc 再乘 CORE_CLOCK_MHZ，
//   20 bit 的 rc 一乘就溢出 32 位，还得随频率改；按 µs 补与频率无关（µs 计数本身按
//   CORE_CLOCK_MHZ 生成），换时钟不用改这里。
//   每发一个包 credit -= (payload + 100 B 头/IFG) × 2048。credit == 0 时该 QP 不可派发。
//   CREDIT_CAP = 128 KB（268 M 单位）：必须同时满足两件事——
//     a) 大于一个最大包的成本（(4096+100)×2048 ≈ 8.6 M），否则 MTU 4096 永远发不出去；
//     b) 大于 1 µs 的线速补充量（400G = 50 KB/µs = 102.4 M 单位），否则限速会低于线速。
//   128 KB 在 400G 下相当于 2.5 µs 的突发，与 mlx5 的量级一致。
`default_nettype none
`timescale 1ns/1ps
module roce_dcqcn #(
    parameter int CORE_CLOCK_MHZ = 250,
    parameter int QP_NUM         = 16
)(
    input  wire                     clk,
    input  wire                     rst,
    // ---------------------------------------------------------------- CSR（0x0B00 窗口）
    input  wire  [19:0]             reg_offset,
    input  wire  [19:0]             reg_write_offset,
    input  wire                     reg_write,
    input  wire  [31:0]             reg_write_data,
    output reg   [31:0]             reg_read_data,
    // 每 QP 调试读口的索引（由 reg_offset 决定）
    // ---------------------------------------------------------------- 每 QP 事件
    input  wire  [QP_NUM-1:0]       event_cnp,        // 收到并接受的 CNP（one-hot，单拍）
    input  wire  [3:0]              cnp_qp_index,     // 同一拍该 CNP 的 QP 索引
    input  wire                     event_tx_valid,   // 发包事件（单拍）
    input  wire  [3:0]              event_tx_qp,
    input  wire  [12:0]             event_tx_length,  // payload 字节
    // ---------------------------------------------------------------- 派发准入
    // 每 QP 的 RC/RT 观测走 0xB30 选择 + 0xB34/0xB38 读口，不再另开打平总线
    // （顶层没人接的总线会被综合当死逻辑优化掉，只会增加仿真面积）。
    output reg   [QP_NUM-1:0]       tx_rate_ready     // credit >= 0；CTRL.EN=0 时全 1
);
    // ================================================================ 地址表
    localparam logic [19:0] A_ID       = 20'h00B00;   // RO 0x4443_5101（"DCQ" v1）
    localparam logic [19:0] A_CTRL     = 20'h00B04;   // RW [0]EN [1]HAI_EN [2]CLAMP_RT
    localparam logic [19:0] A_AI       = 20'h00B08;   // RW rpg_ai_rate  Mb/s（默认 5）
    localparam logic [19:0] A_HAI      = 20'h00B0C;   // RW rpg_hai_rate Mb/s（默认 50）
    localparam logic [19:0] A_THRESH   = 20'h00B10;   // RW rpg_threshold F（默认 1）
    localparam logic [19:0] A_ALPHA_US = 20'h00B14;   // RW dce_tcp_rtt µs（默认 1）
    localparam logic [19:0] A_RED_US   = 20'h00B18;   // RW rate_reduce_monitor_period µs（默认 4）
    localparam logic [19:0] A_INC_US   = 20'h00B1C;   // RW rpg_time_reset µs（默认 300）
    localparam logic [19:0] A_INC_BYTES= 20'h00B20;   // RW rpg_byte_reset × 64 B（默认 32767 → 2 MB）
    localparam logic [19:0] A_MIN_RATE = 20'h00B24;   // RW rpg_min_rate Mb/s（默认 1）
    localparam logic [19:0] A_LINE     = 20'h00B28;   // RW 线速 Mb/s（默认 400000）
    localparam logic [19:0] A_STATUS   = 20'h00B2C;   // RO [15:0] 被限速（credit<0）的 QP
    localparam logic [19:0] A_QP       = 20'h00B30;   // RW 选择要读的 QP（0..15）
    localparam logic [19:0] A_QP_RC    = 20'h00B34;   // RO 选中 QP 的 RC（Mb/s）
    localparam logic [19:0] A_QP_RT    = 20'h00B38;   // RO 选中 QP 的 RT
    localparam logic [19:0] A_QP_ALPHA = 20'h00B3C;   // RO 选中 QP 的 α（10 bit 小数）
    localparam logic [19:0] A_QP_CRED  = 20'h00B40;   // RO 选中 QP 的信用（1/2048 字节，有符号显示为 0 以上）
    localparam logic [19:0] A_QP_STATE = 20'h00B44;   // RO [4:0]iT [5]cnp_seen [13:8]iB
    localparam logic [19:0] A_QP_CNT   = 20'h00B48;   // RO 选中 QP 收到 CNP 的次数
    // B6434：手册 yuncli flexcc 的三个参数
    localparam logic [19:0] A_INIT_ALPHA  = 20'h00B4C; // RW α 初值（默认 1023）；写入即重载全部 16 个 QP
    localparam logic [19:0] A_G           = 20'h00B50; // RW g ×1024（默认 5，即 g=5/1024）
    localparam logic [19:0] A_MAX_HAI_F   = 20'h00B54; // RW HAI 步长上限倍数（默认 1）；HAI 步长 = min(hai×f, max)
    localparam logic [19:0] A_CNT      = 20'h00B80;   // 8 个全局计数器
    localparam logic [19:0] A_CLEAR    = 20'h00BFC;

    localparam int C_EN       = 0;
    localparam int C_HAI_EN   = 1;
    localparam int C_CLAMP_RT = 2;
    localparam int C_CRED_CLR = 3;   // 调试：写 1 期间把每 QP 的信用强制清零（只读回 0）
                                     // 用途：不靠低线速慢慢掏空 128 KB 的桶，直接验证
                                     // 「credit=0 → tx_rate_ready=0 → 派发被挡」这条路径。
                                     // 清掉该位后信用按 σ 从 0 补起（RC 高时几 µs 就回满）。

    // 全局计数器编号
    localparam int CNT_RP_CNP     = 0;   // 收到的 CNP 总数
    localparam int CNT_RATE_DEC   = 1;   // 执行降速的次数
    localparam int CNT_RATE_INC   = 2;   // 执行升速的次数
    localparam int CNT_HAI        = 3;   // HAI 升速次数
    localparam int CNT_FR         = 4;   // 快速恢复次数
    localparam int CNT_STALL_TICK = 5;   // 有 QP 因 credit<0 不能发的拍数
    localparam int CNT_COUNT      = 8;

    // ================================================================ 配置
    reg  [3:0]  cfg_ctrl;
    reg  [19:0] cfg_ai, cfg_hai, cfg_line, cfg_min_rate;
    reg  [4:0]  cfg_thresh;
    reg  [15:0] cfg_alpha_us, cfg_red_us, cfg_inc_us;
    reg  [23:0] cfg_inc_bytes;        // 字节
    reg  [3:0]  cfg_qp_sel;
    // ---- B6434：手册 flexcc 参数
    reg  [9:0]  cfg_init_alpha;       // α 初值（1023 = 1.0）
    reg  [9:0]  cfg_g;                // g ×1024，默认 5
    reg  [7:0]  cfg_max_hai_f;        // HAI 步长倍数上限，默认 1
    reg  [19:0] cfg_hai_eff;          // = cfg_hai × cfg_max_hai_f（写入时算好，数据通路不做乘法）
    reg         reload_alpha;         // 写 INIT_ALPHA 的下一拍重载 16 个 QP 的 α

    // HAI 有效步长的乘积：只在配置写那一拍算，避免把乘法器放进 S1/S2 数据通路。
    // 用「本次写入值优先」避免非阻塞赋值拿到旧值：写 A_HAI 时用 reg_write_data，否则用当前值。
    wire [19:0] hai_new   = (reg_write_offset == A_HAI)       ? reg_write_data[19:0] : cfg_hai;
    wire [7:0]  hai_mf_new= (reg_write_offset == A_MAX_HAI_F) ? reg_write_data[7:0]  : cfg_max_hai_f;
    // 上限 0xFFFFF × 255 = 0xFFFC01，夹到 20 位
    wire [27:0] hai_eff_prod = {8'd0, hai_new} * {20'd0, hai_mf_new};
    wire [19:0] hai_eff_next = (hai_eff_prod > 28'hFFFFF) ? 20'hFFFFF : hai_eff_prod[19:0];

    always @(posedge clk) begin
        if (rst) begin
            cfg_ctrl      <= 4'b0000;          // 默认**关**：不开就不改变任何既有行为
            cfg_ai        <= 20'd5;
            cfg_hai       <= 20'd50;
            cfg_line      <= 20'd400_000;
            cfg_min_rate  <= 20'd1;
            cfg_thresh    <= 5'd1;
            cfg_alpha_us  <= 16'd1;
            cfg_red_us    <= 16'd4;
            cfg_inc_us    <= 16'd300;
            cfg_inc_bytes <= 24'd2_097_088;   // 32767 × 64 B
            cfg_qp_sel    <= 4'd0;
            cfg_init_alpha <= 10'd1023;       // initial_alpha_value = 1.0
            cfg_g          <= 10'd5;          // dce_tcp_g = 1019 → 1024-1019 = 5（即 g=5/1024）
            cfg_max_hai_f  <= 8'd1;           // 步长即 hai_rate，与 B6433 行为逐位一致
            cfg_hai_eff    <= 20'd50;
            reload_alpha   <= 1'b0;
        end else if (reg_write) begin
            case (reg_write_offset)
                A_CTRL:      cfg_ctrl     <= reg_write_data[3:0];
                A_AI:        cfg_ai       <= reg_write_data[19:0];
                A_HAI:       cfg_hai      <= reg_write_data[19:0];
                A_THRESH:    cfg_thresh   <= reg_write_data[4:0];
                A_ALPHA_US:  cfg_alpha_us <= reg_write_data[15:0];
                A_RED_US:    cfg_red_us   <= reg_write_data[15:0];
                A_INC_US:    cfg_inc_us   <= reg_write_data[15:0];
                A_INC_BYTES: cfg_inc_bytes<= reg_write_data[23:0];
                A_MIN_RATE:  cfg_min_rate <= reg_write_data[19:0];
                A_LINE:      cfg_line     <= reg_write_data[19:0];
                A_QP:        cfg_qp_sel   <= reg_write_data[3:0];
                A_INIT_ALPHA:begin
                    cfg_init_alpha <= reg_write_data[9:0];
                    reload_alpha   <= 1'b1;   // 下一拍把 16 个 QP 的 α 一起重载（见扫描写回块）
                end
                A_G:         cfg_g        <= reg_write_data[9:0];
                A_MAX_HAI_F: cfg_max_hai_f<= reg_write_data[7:0];
                default: ;
            endcase
            // HAI 有效步长：AI/HAI/倍数任一个变了都重算（乘积只在这里出现，不在数据通路）
            if (reg_write_offset == A_HAI || reg_write_offset == A_MAX_HAI_F)
                cfg_hai_eff <= hai_eff_next;
        end else begin
            reload_alpha <= 1'b0;
        end
    end
    wire clear_pulse = reg_write && (reg_write_offset == A_CLEAR);
    wire dcqcn_en = cfg_ctrl[C_EN];

    // ================================================================ 时间基准（µs）
    reg  [15:0] us_div;
    wire        us_tick = (us_div == 16'(CORE_CLOCK_MHZ - 1));
    reg  [31:0] now_us;
    always @(posedge clk) begin
        if (rst) begin
            us_div <= 16'd0;
            now_us <= 32'd0;
        end else if (us_tick) begin
            us_div <= 16'd0;
            now_us <= now_us + 32'd1;
        end else begin
            us_div <= us_div + 16'd1;
        end
    end

    // ================================================================ 每 QP 上下文
    localparam logic [31:0] CREDIT_CAP = 32'd268_435_456;  // 128 KB（1/2048 字节单位）

    reg  [19:0] qp_rc       [0:15];
    reg  [19:0] qp_rt       [0:15];
    reg  [9:0]  qp_alpha    [0:15];
    reg  [4:0]  qp_it       [0:15];
    reg  [4:0]  qp_ib       [0:15];
    reg  [23:0] qp_bc       [0:15];        // 自上次升速以来发出的字节
    reg  [31:0] qp_credit   [0:15];
    reg  [31:0] qp_alpha_ts [0:15];
    reg  [31:0] qp_red_ts   [0:15];
    reg  [31:0] qp_inc_ts   [0:15];
    reg         qp_cnp_seen [0:15];
    reg  [31:0] qp_cnp_cnt  [0:15];

    // 每 QP 上下文的复位与更新**都在同一个 always 块里**（见下面的「扫描写回」）。
    // 早先复位单独一个 always、线速夹紧又在第三个 always，Quartus 报
    //   Error (13264) Can't resolve multiple constant drivers for net "qp_rc[...]"
    // 而 verilator 的 lint 因为 -Wno-MULTIDRIVEN 完全看不出来（一直瞒到 B6425 综合）。
    // 规则：同一寄存器的所有写点必须收敛到一个 always。见 tool/quartus_syntax_check.sh。
    integer qi;

    // ================================================================ 时序（B6429，2026-11-10）
    // B6428 core 时钟 −1.794 ns / 27 203 端点，19 984 条路径在 u_dcqcn 内部（平均 9.1 级）：
    // 「16 选 1 读上下文 → RC×α 乘 → 比较/选/减 → 写回」一拍走完，外加信用环
    // 「u_req 准入 → 包成本乘 → 16 路比较/减 → qp_credit」也在一拍里。改法：
    //   1) 扫描拆成两级流水：S1 读上下文、算乘法与所有时间比较并寄存；S2 只做选择与写回。
    //      S1/S2 处理的是相邻的两个 QP（scan 每拍仍 +1），写回一律用锁存的 sq_q。
    //   2) 输入事件（CNP / 准入）在模块入口打一拍；包成本在入口寄存。
    //   3) tx_rate_ready 改成寄存输出（复位全 1：EN=0 时与没有 DCQCN 逐位一致）。
    // 代价：准入 → 停发的反馈多约 2 拍，信用归零后还可能放过 1~2 个包（信用在 0 饱和、不追扣），
    // 限速时实际速率略高于 RC——不是正确性问题。一轮扫描仍是 16 拍（S1/S2 重叠）。

    // ---------------------------------------------------------------- 输入事件打一拍
    reg  [QP_NUM-1:0] ev_cnp_vec;        // 本拍（已寄存）的 CNP one-hot
    reg               ev_tx_v;
    reg  [3:0]        ev_tx_qp;
    reg  [31:0]       ev_tx_cost;        // (len + 100) × 2048，入口就算好
    reg  [12:0]       ev_tx_len;
    always @(posedge clk) begin
        if (rst) begin
            ev_cnp_vec <= '0;
            ev_tx_v    <= 1'b0;
            ev_tx_qp   <= 4'd0;
            ev_tx_cost <= 32'd0;
            ev_tx_len  <= 13'd0;
        end else begin
            ev_cnp_vec <= event_cnp;
            ev_tx_v    <= event_tx_valid;
            ev_tx_qp   <= event_tx_qp;
            ev_tx_len  <= event_tx_length;
            ev_tx_cost <= {8'd0, event_tx_length, 11'd0} + 32'd204_800;   // 乘 2048 = 左移 11
        end
    end
    wire ev_cnp_any = |ev_cnp_vec;

    // ---------------------------------------------------------------- 全局计数
    reg  [31:0] cnt_g [0:CNT_COUNT-1];
    integer gi;

    // ---------------------------------------------------------------- S1：读上下文 + 算
    reg  [3:0] scan;                       // S1 正在读的 QP
    wire [3:0] sq = scan;

    // S1 组合：16 选 1 读出（寄存器阵列，读口是纯 mux）
    wire [19:0] r_rc       = qp_rc[sq];
    wire [19:0] r_rt       = qp_rt[sq];
    wire [9:0]  r_alpha    = qp_alpha[sq];
    wire [4:0]  r_it       = qp_it[sq];
    wire [4:0]  r_ib       = qp_ib[sq];
    wire [23:0] r_bc       = qp_bc[sq];
    wire [31:0] r_alpha_ts = qp_alpha_ts[sq];
    wire [31:0] r_red_ts   = qp_red_ts[sq];
    wire [31:0] r_inc_ts   = qp_inc_ts[sq];

    // α = (1-g)·α + g·[收到 CNP]，g 可配（默认 5/1024，dce_tcp_g = 1019）。
    // cfg_g 为 10 位、r_alpha 10 位，乘积最大 1023×1023 = 1 046 529，要 20 位。
    wire [19:0] alpha_mul  = r_alpha * cfg_g;
    wire [9:0]  alpha_dec  = r_alpha - alpha_mul[19:10];
    // 降幅乘积：RC × α，30 位；右移 11 后最多 19 位
    wire [29:0] red_mul    = r_rc * r_alpha;

    // S1 → S2 流水寄存器（全部是 S1 读出值与比较结果）
    reg  [3:0]  sq_q;
    reg         p_valid;
    reg  [19:0] p_rc, p_rt;
    reg  [9:0]  p_alpha_dec;
    reg  [4:0]  p_it, p_ib;
    reg  [19:0] p_red_full;               // RC×α >> 11
    reg         p_do_alpha, p_do_red, p_do_inc, p_do_fr, p_do_hai;
    reg         p_cnp_seen;               // S1 拍读到的 cnp_seen
    always @(posedge clk) begin
        if (rst) begin
            sq_q        <= 4'd0;
            p_valid     <= 1'b0;
            p_rc        <= 20'd0;
            p_rt        <= 20'd0;
            p_alpha_dec <= 10'd0;
            p_it        <= 5'd0;
            p_ib        <= 5'd0;
            p_red_full  <= 20'd0;
            p_do_alpha  <= 1'b0;
            p_do_red    <= 1'b0;
            p_do_inc    <= 1'b0;
            p_do_fr     <= 1'b0;
            p_do_hai    <= 1'b0;
            p_cnp_seen  <= 1'b0;
        end else begin
            sq_q        <= sq;
            p_valid     <= 1'b1;
            p_rc        <= r_rc;
            p_rt        <= r_rt;
            p_alpha_dec <= alpha_dec;
            p_it        <= r_it;
            p_ib        <= r_ib;
            p_red_full  <= {1'b0, red_mul[29:11]};
            // B6435：α 的衰减写回也受 EN 门控（降速/升速两条通路本来就受）。否则 EN=0 期间
            // α 每 ALPHA_US 衰减一次，约 3 ms 就从 1023 掉到接近 0；之后再打开 EN，首个 CNP
            // 的降幅是 RC·α/2048，几乎不降速，现场看起来像「开了 DCQCN 不工作」。
            p_do_alpha  <= dcqcn_en && (cfg_alpha_us != 16'd0) && (now_us - r_alpha_ts >= {16'd0, cfg_alpha_us});
            // 窗口到期即一次降速判定：有 CNP（seen）就降，没有就只推进窗口。
            p_do_red    <= dcqcn_en && (cfg_red_us != 16'd0) && (now_us - r_red_ts >= {16'd0, cfg_red_us});
            // 字节触发（rpg_byte_reset）与时间触发（rpg_time_reset）各算一次升速事件
            p_do_inc    <= dcqcn_en && (((cfg_inc_us != 16'd0) && (now_us - r_inc_ts >= {16'd0, cfg_inc_us})) ||
                                        (r_bc >= cfg_inc_bytes));
            // 论文：max(iT,iB) < F → FR；min(iT,iB) >= F → HAI；否则 AI。
            p_do_fr     <= (r_it < cfg_thresh) && (r_ib < cfg_thresh);
            p_do_hai    <= cfg_ctrl[C_HAI_EN] && !((r_it < cfg_thresh) && (r_ib < cfg_thresh)) &&
                           (r_ib >= cfg_thresh) && (r_it >= cfg_thresh);
            p_cnp_seen  <= qp_cnp_seen[sq];
        end
    end

    // ---------------------------------------------------------------- S2：选择与写回
    // CNP 被吞的风险（与 86f6f93b 同类）：S1 读 cnp_seen 那一拍若正好来了这个 QP 的 CNP，
    // 事件块在那拍末尾才置 1，p_cnp_seen 读到的是 0。所以 S2 用「S1 读到的值 | 实时的 1 位」，
    // 1 位 16 选 1 不影响时序。降速、只推进窗口、RATE_DEC 计数三处统一用 cnp_eff。
    wire        cnp_eff   = p_cnp_seen | qp_cnp_seen[sq_q];
    wire        do_red_hit = p_valid && p_do_red && cnp_eff;           // 本次执行降速
    // 降速优先：同一次访问里既到降速窗口（且有 CNP）又到升速，执行降速、跳过升速。
    // 早先升速写回排在降速之后会把降速结果覆盖（用的还是降速前的 RC），DCQCN 语义上降速应优先。
    wire        do_inc_eff = p_valid && p_do_inc && !do_red_hit;

    wire [19:0] red_half   = {1'b0, p_rc[19:1]};
    wire [19:0] red_delta  = (p_red_full > red_half) ? red_half : p_red_full;
    wire [19:0] red_next   = (p_rc > (red_delta + cfg_min_rate)) ? (p_rc - red_delta) : cfg_min_rate;
    // α = (1-g)·α + g·[收到 CNP]：衰减项用 cfg_g，增量项同样用 cfg_g（B6434 起可配）
    wire [10:0] alpha_sum  = {1'b0, p_alpha_dec} + (cnp_eff ? {1'b0, cfg_g} : 11'd0);
    wire [9:0]  alpha_next = (alpha_sum > 11'd1023) ? 10'd1023 : alpha_sum[9:0];
    wire [20:0] rt_ai_sum  = {1'b0, p_rt} + {1'b0, cfg_ai};
    wire [20:0] rt_hai_sum = {1'b0, p_rt} + {1'b0, cfg_hai_eff};
    wire [19:0] inc_rt     = (rt_ai_sum  > {1'b0, cfg_line}) ? cfg_line : rt_ai_sum[19:0];
    wire [19:0] inc_rt_hai = (rt_hai_sum > {1'b0, cfg_line}) ? cfg_line : rt_hai_sum[19:0];
    wire [19:0] inc_rt_used= p_do_hai ? inc_rt_hai : inc_rt;
    wire [20:0] inc_sum    = {1'b0, inc_rt_used} + {1'b0, p_rc};
    wire [19:0] inc_rc     = inc_sum[20:1];
    wire [20:0] fr_sum     = {1'b0, p_rt} + {1'b0, p_rc};
    wire [19:0] fr_rc      = fr_sum[20:1];

    // 每 µs 补充的信用 = rc(Mb/s) / 8 字节 = rc × 256 个 (1/2048 B) 单位
    reg  [31:0] leaked;

    // 写回（**所有每 QP 上下文与 cnt_g 的唯一写入点**）
    // cnt_g / qp_* 只能在这个块里写（单一驱动）：早先复位、线速夹紧各在别的 always，
    // Quartus 报 Error (13264) multiple constant drivers；verilator 没有这条告警，看不出来。
    always @(posedge clk) begin
        if (rst || clear_pulse) begin
            for (gi = 0; gi < CNT_COUNT; gi = gi + 1) cnt_g[gi] <= 32'd0;
        end
        if (rst) begin
            // 复位值：RC = RT = 线速，α = 1023（initial_alpha_value）
            for (qi = 0; qi < 16; qi = qi + 1) begin
                qp_rc[qi]       <= 20'd400_000;
                qp_rt[qi]       <= 20'd400_000;
                qp_alpha[qi]    <= 10'd1023;
                qp_it[qi]       <= 5'd0;
                qp_ib[qi]       <= 5'd0;
                qp_bc[qi]       <= 24'd0;
                qp_credit[qi]   <= CREDIT_CAP;
                qp_alpha_ts[qi] <= 32'd0;
                qp_red_ts[qi]   <= 32'd0;
                qp_inc_ts[qi]   <= 32'd0;
                qp_cnp_seen[qi] <= 1'b0;
                qp_cnp_cnt[qi]  <= 32'd0;
            end
            scan <= 4'd0;
        end else begin
            // ---- B6434：写 INIT_ALPHA 后重载全部 16 个 QP 的 α（放在扫描写回**之前**，
            // 这样同一拍扫描的写回仍然优先；reload 只在配置写后的那一拍出现一次）。
            if (reload_alpha)
                for (qi = 0; qi < 16; qi = qi + 1) qp_alpha[qi] <= cfg_init_alpha;
            // ---- 线速夹紧：放在本块**最前面**，后面的具体写回按源码顺序覆盖它。
            for (qi = 0; qi < 16; qi = qi + 1) begin
                if (qp_rc[qi] > cfg_line) qp_rc[qi] <= cfg_line;
                if (qp_rt[qi] > cfg_line) qp_rt[qi] <= cfg_line;
            end
            // ---- credit：每拍每 QP 并行更新（不经扫描）。
            // 每 µs 补 rc×256；同拍若该 QP 有包被准入（入口已寄存）则扣包成本，在 0 饱和。
            for (qi = 0; qi < 16; qi = qi + 1) begin
                if (cfg_ctrl[C_CRED_CLR]) begin
                    qp_credit[qi] <= 32'd0;      // 调试：强制空桶，验证派发被信用挡住
                end else if (!dcqcn_en) begin
                    qp_credit[qi] <= CREDIT_CAP;
                end else begin
                    leaked = us_tick ? ((qp_credit[qi] + ({12'd0, qp_rc[qi]} << 8) > CREDIT_CAP) ?
                                        CREDIT_CAP : (qp_credit[qi] + ({12'd0, qp_rc[qi]} << 8)))
                                     : qp_credit[qi];
                    if (ev_tx_v && (ev_tx_qp == qi[3:0]))
                        qp_credit[qi] <= (leaked > ev_tx_cost) ? (leaked - ev_tx_cost) : 32'd0;
                    else
                        qp_credit[qi] <= leaked;
                end
            end
            // ---- 全局计数
            if (ev_cnp_any && dcqcn_en) cnt_g[CNT_RP_CNP] <= cnt_g[CNT_RP_CNP] + 32'd1;
            if (do_red_hit)             cnt_g[CNT_RATE_DEC] <= cnt_g[CNT_RATE_DEC] + 32'd1;
            if (do_inc_eff) begin
                cnt_g[CNT_RATE_INC] <= cnt_g[CNT_RATE_INC] + 32'd1;
                if (p_do_fr)       cnt_g[CNT_FR]  <= cnt_g[CNT_FR]  + 32'd1;
                else if (p_do_hai) cnt_g[CNT_HAI] <= cnt_g[CNT_HAI] + 32'd1;
            end
            // 归约或 `|` 后面紧跟 `~` 时 Quartus 报 syntax error near text ~（B6425），显式加括号。
            if (dcqcn_en && (|(~tx_rate_ready))) cnt_g[CNT_STALL_TICK] <= cnt_g[CNT_STALL_TICK] + 32'd1;
            // ---- CNP 事件：置 cnp_seen + 计数
            // EN=0 时只计数、不锁存 cnp_seen，并把已锁存的清掉：B6432 上板发现 EN=0 期间收到的 CNP
            // 留下 cnp_seen=1，EN 一打开就被消费成一次降速（§56.5 Q2 的 rate_dec +1）。
            if (!dcqcn_en)
                for (qi = 0; qi < 16; qi = qi + 1) qp_cnp_seen[qi] <= 1'b0;
            if (ev_cnp_any) begin
                for (qi = 0; qi < 16; qi = qi + 1)
                    if (ev_cnp_vec[qi]) begin
                        if (dcqcn_en) qp_cnp_seen[qi] <= 1'b1;
                        qp_cnp_cnt[qi]  <= qp_cnp_cnt[qi] + 32'd1;
                    end
            end
            // ---- S2 写回（索引一律 sq_q）
            // B6435：重载那一拍不做扫描写回，否则 sq_q 那个 QP 会被 alpha_next 覆盖掉，
            // 软件写 INIT_ALPHA 后逐个读回会偶发一个不是新值（16 个里最多 1 个）。
            if (p_valid && p_do_alpha && !reload_alpha) begin
                qp_alpha[sq_q]    <= alpha_next;
                qp_alpha_ts[sq_q] <= now_us;
            end
            // 降速窗口：每 RED_US 一次。窗口内有 CNP 就降，没有就只推进窗口并清 seen。
            // 同拍撞车：上面的事件块可能本拍刚把 qp_cnp_seen[sq_q] 置 1，这里清 0 会把它吞掉，
            // 所以只在「本拍没收到该 QP 的 CNP」时清。
            if (do_red_hit) begin
                qp_rc[sq_q]       <= red_next;
                qp_rt[sq_q]       <= cfg_ctrl[C_CLAMP_RT] ? red_next : p_rt;
                if (!ev_cnp_vec[sq_q]) qp_cnp_seen[sq_q] <= 1'b0;
                qp_red_ts[sq_q]   <= now_us;
                qp_it[sq_q]       <= 5'd0;
                qp_ib[sq_q]       <= 5'd0;
                qp_bc[sq_q]       <= 24'd0;
                qp_inc_ts[sq_q]   <= now_us;
            end else if (p_valid && p_do_red) begin
                if (!ev_cnp_vec[sq_q]) qp_cnp_seen[sq_q] <= 1'b0;
                qp_red_ts[sq_q]   <= now_us;
            end
            if (do_inc_eff) begin
                if (p_do_fr) begin
                    qp_rc[sq_q] <= fr_rc;
                    qp_it[sq_q] <= (p_it < 5'd31) ? (p_it + 5'd1) : p_it;
                    qp_ib[sq_q] <= (p_ib < 5'd31) ? (p_ib + 5'd1) : p_ib;
                end else begin
                    // HAI / AI：RT += R_HAI 或 R_AI，RC = (RT + RC)/2，阶段计数清零
                    qp_rt[sq_q] <= inc_rt_used;
                    qp_rc[sq_q] <= inc_rc;
                    qp_it[sq_q] <= 5'd0;
                    qp_ib[sq_q] <= 5'd0;
                end
                qp_bc[sq_q]     <= 24'd0;
                qp_inc_ts[sq_q] <= now_us;
            end
            // 累计发送字节（升速的字节触发用）。必须挡掉「S2 正在清零的那个 QP」（后写的赢），
            // 否则清零会被这里的加法覆盖、bc 永远不归零。保护条件用 S2 的 sq_q 与 do_inc_eff/do_red_hit。
            if (ev_tx_v) begin
                for (qi = 0; qi < 16; qi = qi + 1)
                    if ((ev_tx_qp == qi[3:0]) && !((do_inc_eff || do_red_hit) && (sq_q == qi[3:0])))
                        qp_bc[qi] <= (qp_bc[qi] + {11'd0, ev_tx_len}) > cfg_inc_bytes ?
                                     cfg_inc_bytes : (qp_bc[qi] + {11'd0, ev_tx_len});
            end
            scan <= scan + 4'd1;
        end
    end

    // ================================================================ 派发准入（寄存输出）
    // 复位全 1：EN=0 时与没有 DCQCN 逐位一致。寄存后 u_req → u_dcqcn → u_req 的环被切开。
    integer tq;
    always @(posedge clk) begin
        if (rst) tx_rate_ready <= '1;
        else
            for (tq = 0; tq < QP_NUM; tq = tq + 1)
                tx_rate_ready[tq] <= !dcqcn_en || (qp_credit[tq] != 32'd0);
    end

    // ================================================================ 读口
    wire [19:0] cnt_rel = reg_offset - A_CNT;
    wire [3:0]  qsel    = cfg_qp_sel;
    always @* begin
        reg_read_data = 32'hdeadbeef;
        if (reg_offset >= A_CNT && reg_offset < A_CNT + 20'(4*CNT_COUNT))
            reg_read_data = cnt_g[cnt_rel[4:2]];
        else case (reg_offset)
            A_ID:       reg_read_data = 32'h4443_5101;                 // "DCQ" v1
            A_CTRL:     reg_read_data = {28'd0, cfg_ctrl};
            A_AI:       reg_read_data = {12'd0, cfg_ai};
            A_HAI:      reg_read_data = {12'd0, cfg_hai};
            A_THRESH:   reg_read_data = {27'd0, cfg_thresh};
            A_ALPHA_US: reg_read_data = {16'd0, cfg_alpha_us};
            A_RED_US:   reg_read_data = {16'd0, cfg_red_us};
            A_INC_US:   reg_read_data = {16'd0, cfg_inc_us};
            A_INC_BYTES:reg_read_data = {8'd0, cfg_inc_bytes};
            A_MIN_RATE: reg_read_data = {12'd0, cfg_min_rate};
            A_LINE:     reg_read_data = {12'd0, cfg_line};
            A_STATUS:   reg_read_data = {16'd0, ~tx_rate_ready[QP_NUM-1:0]};
            A_QP:       reg_read_data = {28'd0, cfg_qp_sel};
            A_QP_RC:    reg_read_data = {12'd0, qp_rc[qsel]};
            A_QP_RT:    reg_read_data = {12'd0, qp_rt[qsel]};
            A_QP_ALPHA: reg_read_data = {22'd0, qp_alpha[qsel]};
            A_QP_CRED:  reg_read_data = qp_credit[qsel];
            // [4:0] iT  [5] cnp_seen  [13:8] iB —— 5+1+2+6 = 14 bit，前面补 18 位 0。
            // 早先写成 19'd0（33 bit 拼 32 位）只是被截掉最高那位 0，值对但位宽是错的。
            A_QP_STATE: reg_read_data = {18'd0, qp_ib[qsel], 2'd0, qp_cnp_seen[qsel], qp_it[qsel]};
            A_QP_CNT:   reg_read_data = qp_cnp_cnt[qsel];
            A_INIT_ALPHA:  reg_read_data = {22'd0, cfg_init_alpha};
            A_G:           reg_read_data = {22'd0, cfg_g};
            A_MAX_HAI_F:   reg_read_data = {24'd0, cfg_max_hai_f};
            default: ;
        endcase
    end

endmodule
`default_nettype wire
