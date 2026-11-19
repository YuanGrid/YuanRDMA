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
// **QP_NUM 是本模块的独立参数，可以小于引擎的 QP_NUM；未覆盖的 QP 恒放行。**
//   本模块只维护 QP 0 .. QP_NUM-1 的速率上下文。范围之外的 QP 既不产生 CNP/准入事件，
//   也不占 tx_rate_ready 的有效位；顶层把 tx_rate_ready 的高位硬接 1'b1，这些 QP 不受限。
//   S4（2026-11）：引擎 QP_NUM = 128，roce_top 当时只实例化 DCQCN_QP_NUM = 16（先保住
//   扫描周期与 one-hot 的规模）。
//   S5（2026-11-14）：DCQCN_QP_NUM = QP_NUM = 128，全部 QP 都受限速；本模块按 QP_NUM 参数
//   展开，扫描轮 128 拍 = 512 ns @250 MHz，仍小于 1 µs 的 α 周期。
//
// 为什么用「每拍扫一个 QP」而不是每 QP 一套定时器
//   一轮扫描 QP_NUM 拍（16 时 64 ns、128 时 512 ns @250 MHz），都比 1 µs 的 α 周期小；
//   每 QP 只存时间戳，比较在扫描那一拍做。QP_NUM × ~160 bit 的上下文全部是寄存器
//   （128 × 160 ≈ 20480 个触发器，
//   Agilex 7 上一块 ALM 都不缺），不占 M20K，也没有表读写的长路径。
//   扫描周期与 QP_NUM 成正比：QP_NUM = 128 时一轮 128 拍 = 512 ns，仍小于 ALPHA_US 的 1 µs，
//   但上下文触发器涨到 8 倍，S5 扩容时要一并核面积与时序。
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
    /* 默认值必须与 roce_pkg 的 QP_NUM 一致：本模块的上下文阵列按它展开，
     * 而不传参的例化（新台子等）若静默得到 16，会与 yuanrdma_hw.h 宣称的 128 不符。 */
    parameter int QP_NUM         = 128,
    parameter int QP_W           = (QP_NUM > 1) ? $clog2(QP_NUM) : 1
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
    input  wire  [QP_W-1:0]         cnp_qp_index,     // 同一拍该 CNP 的 QP 索引
    input  wire                     event_tx_valid,   // 发包事件（单拍）
    input  wire  [QP_W-1:0]         event_tx_qp,
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
    localparam logic [19:0] A_STATUS   = 20'h00B2C;   // RO [STATUS_W-1:0] 被限速（credit=0）的 QP；STATUS_W = min(QP_NUM, 32)
    localparam logic [19:0] A_QP       = 20'h00B30;   // RW 选择要读的 QP（0..QP_NUM-1）
    localparam logic [19:0] A_QP_RC    = 20'h00B34;   // RO 选中 QP 的 RC（Mb/s）
    localparam logic [19:0] A_QP_RT    = 20'h00B38;   // RO 选中 QP 的 RT
    localparam logic [19:0] A_QP_ALPHA = 20'h00B3C;   // RO 选中 QP 的 α（10 bit 小数）
    localparam logic [19:0] A_QP_CRED  = 20'h00B40;   // RO 选中 QP 的信用（1/2048 字节，有符号显示为 0 以上）
    localparam logic [19:0] A_QP_STATE = 20'h00B44;   // RO [4:0]iT [5]cnp_seen [13:8]iB
    localparam logic [19:0] A_QP_CNT   = 20'h00B48;   // RO 选中 QP 收到 CNP 的次数
    // B6434：手册 yuncli flexcc 的三个参数
    localparam logic [19:0] A_INIT_ALPHA  = 20'h00B4C; // RW α 初值（默认 1023）；写入即重载全部 QP_NUM 个 QP
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
    reg  [QP_W-1:0] cfg_qp_sel;
    // ---- B6434：手册 flexcc 参数
    reg  [9:0]  cfg_init_alpha;       // α 初值（1023 = 1.0）
    reg  [9:0]  cfg_g;                // g ×1024，默认 5
    reg  [7:0]  cfg_max_hai_f;        // HAI 步长倍数上限，默认 1
    reg  [19:0] cfg_hai_eff;          // = cfg_hai × cfg_max_hai_f（写后一拍算好，数据通路不做乘法）
    reg         hai_eff_pending;      // 上一拍有 A_HAI / A_MAX_HAI_F 写入，本拍重算 cfg_hai_eff
    reg         reload_alpha;         // 写 INIT_ALPHA 的下一拍重载全部 QP_NUM 个 QP 的 α

    // HAI 有效步长的乘积。**拆成两拍**（G0.4 恢复，B6501 STA 复核）：
    //
    // B6440 的 core 最差路径就是这一处（Slow vid2b 100C，250 MHz，slack −0.181）：
    //   u_csr|u_avm_reg|reg_din[11] → u_dcqcn|cfg_hai_eff[18]~LRTM_5.comb
    //   2 级逻辑 / 数据延迟 4.050 ns（IC 1.437 + cell 2.384，其中 DSP 乘法独占 2.151）
    // B6501（QP 128 + UD/CM 之后）仍是违例：cfg_max_hai_f[2]~DUPLICATE → cfg_hai_eff[2]
    //   单条 slack −0.305，属同一处「选择器 + 20×8 DSP + 夹位」串一拍的结构。
    // 原来是「写那一拍用 reg_write_data 走二选一 → 乘法 → 夹位 → 打寄存器」，一拍里串了
    // 选择器 + 20×8 DSP + 比较。这里改成「写那一拍只置 pending，下一拍用**已更新**的
    // cfg_hai / cfg_max_hai_f 重算」：操作数全变成模块内寄存器，D 口只剩 DSP + 一级夹位，
    // 选择器与跨区走线都移到 pending 这条浅路径上（1 位）。
    //
    // 代价只有一拍延迟，且只在这两个寄存器被写时发生一次：cfg_hai_eff 是纯配置量，
    // 唯一的读者是下面的 rt_hai_sum（S2 的 HAI 升速项），**不在任何攒包/发送通路上**，
    // 也不经 CSR 回读（A_HAI / A_MAX_HAI_F 读的是 cfg_hai / cfg_max_hai_f 原件），
    // 软件写完轮询读回，晚一拍不可见。
    // 背靠背写 A_HAI 与 A_MAX_HAI_F 时 pending 连续两拍有效：第一拍重算用的是旧倍数（中间态），
    // 第二拍重算读到的是两个寄存器的新值，最终收敛到正确乘积（台子 test_back_to_back 覆盖）。
    // 上限 0xFFFFF × 255 = 0xFFFC01，夹到 20 位（夹位逻辑与改动前逐位相同）
    wire [27:0] hai_eff_prod = {8'd0, cfg_hai} * {20'd0, cfg_max_hai_f};
    wire [19:0] hai_eff_next = (hai_eff_prod > 28'hFFFFF) ? 20'hFFFFF : hai_eff_prod[19:0];
    wire        hai_eff_req  = reg_write &&
                               (reg_write_offset == A_HAI || reg_write_offset == A_MAX_HAI_F);

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
            cfg_qp_sel    <= {QP_W{1'b0}};
            cfg_init_alpha <= 10'd1023;       // initial_alpha_value = 1.0
            cfg_g          <= 10'd5;          // dce_tcp_g = 1019 → 1024-1019 = 5（即 g=5/1024）
            cfg_max_hai_f  <= 8'd1;           // 步长即 hai_rate，与 B6433 行为逐位一致
            cfg_hai_eff    <= 20'd50;
            hai_eff_pending <= 1'b0;
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
                // A_QP 只允许写到 QP_NUM-1：QP_NUM 不是 2 的幂时高位会指到阵列外，
                // 读口 select 到不存在的项没有驱动（X / 读到别的项）。比较先扩到 32 位再比，
                // 不能写成 QP_W'(QP_NUM)——QP_NUM = 16 时 QP_W'(16) 截成 0，比较恒假。
                // QP_NUM = 16（2 的幂）时本夹紧是恒等，行为与改动前逐位一致。
                A_QP:        cfg_qp_sel   <= (32'(reg_write_data[QP_W-1:0]) < 32'(QP_NUM)) ?
                                              reg_write_data[QP_W-1:0] : {QP_W{1'b0}};
                A_INIT_ALPHA:begin
                    cfg_init_alpha <= reg_write_data[9:0];
                    reload_alpha   <= 1'b1;   // 下一拍把 QP_NUM 个 QP 的 α 一起重载（见扫描写回块）
                end
                A_G:         cfg_g        <= reg_write_data[9:0];
                A_MAX_HAI_F: cfg_max_hai_f<= reg_write_data[7:0];
                default: ;
            endcase
            // HAI 有效步长：本拍只登记请求，下一拍用已更新的 cfg_hai / cfg_max_hai_f 重算
            // （把「选择器 + DSP + 夹位」从一拍拆成两拍，见上面 hai_eff_prod 处的说明）。
            // pending 在「没有任何写」的拍也走这个分支被清零，所以写一次只重算一次。
            hai_eff_pending <= hai_eff_req;
        end else begin
            reload_alpha    <= 1'b0;
            hai_eff_pending <= 1'b0;
        end
        // 重算拍：写分支占本拍时 pending 只在下一拍生效（非阻塞赋值）；背靠背写时连续两拍
        // pending 有效，最后一拍读到的是两个寄存器的新值，结果收敛正确。
        // 必须带 !rst：复位沿上 pending 的旧值会盖掉上面的复位赋值
        // （同一 always 里对同一 reg 的两次非阻塞赋值，后者胜），导致 cfg_hai_eff 复位值被改。
        // 操作数全为模块内寄存器（cfg_hai / cfg_max_hai_f 直出），这条路径上没有 reg_write_data、
        // 没有二选一：D 口 = DSP 乘法 → 一级夹位 → 寄存器。
        if (!rst && hai_eff_pending) cfg_hai_eff <= hai_eff_next;
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
    // A_STATUS 的位宽：QP_NUM 小于 32 时按 QP_NUM 报，否则只报前 32 个
    localparam int STATUS_W = (QP_NUM < 32) ? QP_NUM : 32;

    reg  [19:0] qp_rc       [0:QP_NUM-1];
    reg  [19:0] qp_rt       [0:QP_NUM-1];
    reg  [9:0]  qp_alpha    [0:QP_NUM-1];
    reg  [4:0]  qp_it       [0:QP_NUM-1];
    reg  [4:0]  qp_ib       [0:QP_NUM-1];
    reg  [23:0] qp_bc       [0:QP_NUM-1];        // 自上次升速以来发出的字节
    reg  [31:0] qp_credit   [0:QP_NUM-1];
    reg  [31:0] qp_alpha_ts [0:QP_NUM-1];
    reg  [31:0] qp_red_ts   [0:QP_NUM-1];
    reg  [31:0] qp_inc_ts   [0:QP_NUM-1];
    reg         qp_cnp_seen [0:QP_NUM-1];
    reg  [31:0] qp_cnp_cnt  [0:QP_NUM-1];

    // 每 QP 上下文的复位与更新**都在同一个 always 块里**（见下面的「扫描写回」）。
    // 早先复位单独一个 always、线速夹紧又在第三个 always，Quartus 报
    //   Error (13264) Can't resolve multiple constant drivers for net "qp_rc[...]"
    // 而 verilator 的 lint 因为 -Wno-MULTIDRIVEN 完全看不出来（一直瞒到 B6425 综合）。
    // 规则：同一寄存器的所有写点必须收敛到一个 always。见 tool/quartus_syntax_check.sh。
    integer qi;

    // ================================================================ 时序（B6429，2026-11-10）
    // B6428 core 时钟 −1.794 ns / 27 203 端点，19 984 条路径在 u_dcqcn 内部（平均 9.1 级）：
    // 「QP_NUM 选 1 读上下文 → RC×α 乘 → 比较/选/减 → 写回」一拍走完，外加信用环
    // 「u_req 准入 → 包成本乘 → QP_NUM 路比较/减 → qp_credit」也在一拍里。改法：
    //   1) 扫描拆成两级流水：S1 读上下文、算乘法与所有时间比较并寄存；S2 只做选择与写回。
    //      S1/S2 处理的是相邻的两个 QP（scan 每拍仍 +1），写回一律用锁存的 sq_q。
    //      **B6503 起是三级**：S0 读口 mux → S1 乘法/比较 → S2 选择/写回（见下面 s_* 寄存级）。
    //      每拍仍只前进一个 QP，一轮仍是 QP_NUM 拍；多出的是一级固定延迟，不是扫描周期。
    //   2) 输入事件（CNP / 准入）在模块入口打一拍；包成本在入口寄存。
    //   3) tx_rate_ready 改成寄存输出（复位全 1：EN=0 时与没有 DCQCN 逐位一致）。
    // 代价：准入 → 停发的反馈多约 2 拍，信用归零后还可能放过 1~2 个包（信用在 0 饱和、不追扣），
    // 限速时实际速率略高于 RC——不是正确性问题。一轮扫描仍是 QP_NUM 拍（S1/S2 重叠）。

    // ---------------------------------------------------------------- 输入事件打一拍
    reg  [QP_NUM-1:0] ev_cnp_vec;        // 本拍（已寄存）的 CNP one-hot
    reg               ev_tx_v;
    reg  [QP_W-1:0]   ev_tx_qp;
    reg  [31:0]       ev_tx_cost;        // (len + 100) × 2048，入口就算好
    reg  [12:0]       ev_tx_len;
    always @(posedge clk) begin
        if (rst) begin
            ev_cnp_vec <= '0;
            ev_tx_v    <= 1'b0;
            ev_tx_qp   <= {QP_W{1'b0}};
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

    // ---------------------------------------------------------------- S0/S1：读上下文 + 算
    reg  [QP_W-1:0] scan;                  // S0 正在读的 QP
    wire [QP_W-1:0] sq = scan;

    // S0 组合：QP_NUM 选 1 读出（寄存器阵列，读口是纯 mux）
    wire [19:0] r_rc       = qp_rc[sq];
    wire [19:0] r_rt       = qp_rt[sq];
    wire [9:0]  r_alpha    = qp_alpha[sq];
    wire [4:0]  r_it       = qp_it[sq];
    wire [4:0]  r_ib       = qp_ib[sq];
    wire [23:0] r_bc       = qp_bc[sq];
    wire [31:0] r_alpha_ts = qp_alpha_ts[sq];
    wire [31:0] r_red_ts   = qp_red_ts[sq];
    wire [31:0] r_inc_ts   = qp_inc_ts[sq];

    // ---- B6503：S0 → S1 寄存级（簇 B，`red_next[0]~dff → mult_2~DATAOUTA0|ax[11]`，−0.221）
    //
    // B6502 的 STA 事实（Slow vid2b 100C，250 MHz，sta.rpt Path #6）：
    //   From  u_dcqcn|red_next[0]~8_R6_X220_Y311_N0_I7_dff
    //   To    u_dcqcn|mult_2~DATAOUTA0~OUTPUT_REG      （终点元件 mult_2~DATAOUTA0|ax[11]）
    //   5 级逻辑 / 数据延迟 2.246 ns（IC 1.734 = 77%，最长一段 0.619；Cell 仅 0.379）
    //   uTsu = −1.859（DSP 输入寄存器的建立时间占 4.000 ns 周期的 46%）
    //   slack = −0.221
    //
    // **这条路径不是「red_next 做乘法」。** `red_next`（下面的 :387 附近）是纯组合 wire，
    // 只喂 qp_rc/qp_rt 的写口；起点那个 flop 是 Quartus 按 D 口网络给 qp_rc 阵列起的名字。
    // 真实结构是：qp_rc 阵列 flop → 128 选 1 读口（Mux_19~38/39/40/910，4 级）
    //              → mult_2|ax[11]，而 mult_2 是 20×10 的 red_mul = r_rc × r_alpha（:322）。
    // 所以病根是**读口 mux 的走线直接撞 DSP 硬宏的输入寄存器**：mux 的终点是 uTsu = 1.859 ns
    // 的硬宏寄存器，不是 uTsu ≈ 0.05 ns 的 ALM flop。多给一拍（把 red_next 打一拍）对它无效，
    // 因为那条路径的起点和终点都不经过 red_next。
    //
    // 改法：在读口与乘法之间插一级**普通** ALM 寄存器（s_*）。mux 的终点变成 ALM 的 D 口，
    //       乘法器的输入变成模块内寄存器直出（与前文 hai_eff_prod 的 G0.4 手法同型）。
    // 代价：一套（**不是每 QP 一套**）共 188 个 flop：sq_s 7 + s_rc/s_rt 40 + s_alpha 10 +
    //       s_it/s_ib 10 + s_bc 24 + 三个时间戳 96 + s_cnp_seen 1。
    //       流水从 2 级变 3 级；扫描**仍是每拍一个 QP**，一轮仍 QP_NUM 拍 = 512 ns @250 MHz，
    //       小于 1 µs 的 α 周期，所以本模块头注释里「扫描周期必须小于 ALPHA_US」的约束不破。
    // 语义：s_* 只是把「读出」与「用」错开一拍，写回仍落在该 QP 自己的窗口里；
    //       sq_q 跟着多走一级，写回索引与数据始终配对。DCQCN 的收敛不受影响
    //       （α/降速/升速窗口都是 µs 量级，一拍 4 ns 只增加固定延迟，不改变任何阈值比较的结果）。
    reg  [QP_W-1:0] sq_s;
    reg  [19:0]     s_rc, s_rt;
    reg  [9:0]      s_alpha;
    reg  [4:0]      s_it, s_ib;
    reg  [23:0]     s_bc;
    reg  [31:0]     s_alpha_ts, s_red_ts, s_inc_ts;
    reg             s_cnp_seen;
    always @(posedge clk) begin
        if (rst) begin
            sq_s       <= {QP_W{1'b0}};
            s_rc       <= 20'd0;
            s_rt       <= 20'd0;
            s_alpha    <= 10'd0;
            s_it       <= 5'd0;
            s_ib       <= 5'd0;
            s_bc       <= 24'd0;
            s_alpha_ts <= 32'd0;
            s_red_ts   <= 32'd0;
            s_inc_ts   <= 32'd0;
            s_cnp_seen <= 1'b0;
        end else begin
            sq_s       <= sq;
            s_rc       <= r_rc;
            s_rt       <= r_rt;
            s_alpha    <= r_alpha;
            s_it       <= r_it;
            s_ib       <= r_ib;
            s_bc       <= r_bc;
            s_alpha_ts <= r_alpha_ts;
            s_red_ts   <= r_red_ts;
            s_inc_ts   <= r_inc_ts;
            s_cnp_seen <= qp_cnp_seen[sq];
        end
    end

    // α = (1-g)·α + g·[收到 CNP]，g 可配（默认 5/1024，dce_tcp_g = 1019）。
    // cfg_g 为 10 位、s_alpha 10 位，乘积最大 1023×1023 = 1 046 529，要 20 位。
    // B6503：操作数从 r_alpha / r_rc（读口直出）改成 s_alpha / s_rc（S0 寄存后），
    // 乘法器的 D 口只剩 DSP + 一级夹位，读口 mux 的 4 级走线被挡在 s_* 之前。
    wire [19:0] alpha_mul  = s_alpha * cfg_g;
    wire [9:0]  alpha_dec  = s_alpha - alpha_mul[19:10];
    // 降幅乘积：RC × α，30 位；右移 11 后最多 19 位
    wire [29:0] red_mul    = s_rc * s_alpha;

    // S1 → S2 流水寄存器（全部是 S1 读出值与比较结果）
    reg  [QP_W-1:0] sq_q;
    reg         p_valid;
    reg  [19:0] p_rc, p_rt;
    reg  [9:0]  p_alpha_dec;
    reg  [4:0]  p_it, p_ib;
    reg  [19:0] p_red_full;               // RC×α >> 11
    reg         p_do_alpha, p_do_red, p_do_inc, p_do_fr, p_do_hai;
    reg         p_cnp_seen;               // S1 拍读到的 cnp_seen
    always @(posedge clk) begin
        if (rst) begin
            sq_q        <= {QP_W{1'b0}};
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
            sq_q        <= sq_s;
            p_valid     <= 1'b1;
            p_rc        <= s_rc;
            p_rt        <= s_rt;
            p_alpha_dec <= alpha_dec;
            p_it        <= s_it;
            p_ib        <= s_ib;
            p_red_full  <= {1'b0, red_mul[29:11]};
            // B6435：α 的衰减写回也受 EN 门控（降速/升速两条通路本来就受）。否则 EN=0 期间
            // α 每 ALPHA_US 衰减一次，约 3 ms 就从 1023 掉到接近 0；之后再打开 EN，首个 CNP
            // 的降幅是 RC·α/2048，几乎不降速，现场看起来像「开了 DCQCN 不工作」。
            // B6503：时间戳与 bc 比较的操作数一并改用 s_*（原来读口直出），与 sq_q 同相。
            p_do_alpha  <= dcqcn_en && (cfg_alpha_us != 16'd0) && (now_us - s_alpha_ts >= {16'd0, cfg_alpha_us});
            // 窗口到期即一次降速判定：有 CNP（seen）就降，没有就只推进窗口。
            p_do_red    <= dcqcn_en && (cfg_red_us != 16'd0) && (now_us - s_red_ts >= {16'd0, cfg_red_us});
            // 字节触发（rpg_byte_reset）与时间触发（rpg_time_reset）各算一次升速事件
            p_do_inc    <= dcqcn_en && (((cfg_inc_us != 16'd0) && (now_us - s_inc_ts >= {16'd0, cfg_inc_us})) ||
                                        (s_bc >= cfg_inc_bytes));
            // 论文：max(iT,iB) < F → FR；min(iT,iB) >= F → HAI；否则 AI。
            p_do_fr     <= (s_it < cfg_thresh) && (s_ib < cfg_thresh);
            p_do_hai    <= cfg_ctrl[C_HAI_EN] && !((s_it < cfg_thresh) && (s_ib < cfg_thresh)) &&
                           (s_ib >= cfg_thresh) && (s_it >= cfg_thresh);
            // B6503：s_cnp_seen 是 S0 拍（t）读到的值，p_cnp_seen 在 t+2 才被 S2 用；
            // 中间 S1 拍（t+1）若来了该 QP 的 CNP 会被漏掉。所以 S1 这一级要把**实时的**
            // qp_cnp_seen[sq_s] 一起 OR 进来：覆盖 t（经 s_cnp_seen）与 t+1（实时），
            // S2 再用实时的覆盖 t+2 —— 三拍全覆盖，比 B6502 的两拍覆盖更宽，不会倒退。
            // 1 位或，扇出对时序无影响。
            p_cnp_seen  <= s_cnp_seen | qp_cnp_seen[sq_s];
        end
    end

    // ---------------------------------------------------------------- S2：选择与写回
    // CNP 被吞的风险（与 86f6f93b 同类）：S1 读 cnp_seen 那一拍若正好来了这个 QP 的 CNP，
    // 事件块在那拍末尾才置 1，p_cnp_seen 读到的是 0。所以 S2 用「S1 读到的值 | 实时的 1 位」，
    // 1 位 QP_NUM 选 1 不影响时序。降速、只推进窗口、RATE_DEC 计数三处统一用 cnp_eff。
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
            for (qi = 0; qi < QP_NUM; qi = qi + 1) begin
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
            scan <= {QP_W{1'b0}};
        end else begin
            // ---- B6434：写 INIT_ALPHA 后重载全部 QP_NUM 个 QP 的 α（放在扫描写回**之前**，
            // 这样同一拍扫描的写回仍然优先；reload 只在配置写后的那一拍出现一次）。
            if (reload_alpha)
                for (qi = 0; qi < QP_NUM; qi = qi + 1) qp_alpha[qi] <= cfg_init_alpha;
            // ---- 线速夹紧：放在本块**最前面**，后面的具体写回按源码顺序覆盖它。
            for (qi = 0; qi < QP_NUM; qi = qi + 1) begin
                if (qp_rc[qi] > cfg_line) qp_rc[qi] <= cfg_line;
                if (qp_rt[qi] > cfg_line) qp_rt[qi] <= cfg_line;
            end
            // ---- credit：每拍每 QP 并行更新（不经扫描）。
            // 每 µs 补 rc×256；同拍若该 QP 有包被准入（入口已寄存）则扣包成本，在 0 饱和。
            for (qi = 0; qi < QP_NUM; qi = qi + 1) begin
                if (cfg_ctrl[C_CRED_CLR]) begin
                    qp_credit[qi] <= 32'd0;      // 调试：强制空桶，验证派发被信用挡住
                end else if (!dcqcn_en) begin
                    qp_credit[qi] <= CREDIT_CAP;
                end else begin
                    leaked = us_tick ? ((qp_credit[qi] + ({12'd0, qp_rc[qi]} << 8) > CREDIT_CAP) ?
                                        CREDIT_CAP : (qp_credit[qi] + ({12'd0, qp_rc[qi]} << 8)))
                                     : qp_credit[qi];
                    if (ev_tx_v && (ev_tx_qp == qi[QP_W-1:0]))
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
                for (qi = 0; qi < QP_NUM; qi = qi + 1) qp_cnp_seen[qi] <= 1'b0;
            if (ev_cnp_any) begin
                for (qi = 0; qi < QP_NUM; qi = qi + 1)
                    if (ev_cnp_vec[qi]) begin
                        if (dcqcn_en) qp_cnp_seen[qi] <= 1'b1;
                        qp_cnp_cnt[qi]  <= qp_cnp_cnt[qi] + 32'd1;
                    end
            end
            // ---- S2 写回（索引一律 sq_q）
            // B6435：重载那一拍不做扫描写回，否则 sq_q 那个 QP 会被 alpha_next 覆盖掉，
            // 软件写 INIT_ALPHA 后逐个读回会偶发一个不是新值（QP_NUM 个里最多 1 个）。
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
                for (qi = 0; qi < QP_NUM; qi = qi + 1)
                    if ((ev_tx_qp == qi[QP_W-1:0]) && !((do_inc_eff || do_red_hit) && (sq_q == qi[QP_W-1:0])))
                        qp_bc[qi] <= (qp_bc[qi] + {11'd0, ev_tx_len}) > cfg_inc_bytes ?
                                     cfg_inc_bytes : (qp_bc[qi] + {11'd0, ev_tx_len});
            end
            // 扫描指针只在 0..QP_NUM-1 之间回绕，**不能**直接 +1 让 QP_W 位自然溢出：
            // QP_NUM 不是 2 的幂（例如 24）时，自然溢出会扫到 QP_NUM..2^QP_W-1 这些不存在的项，
            // 读口越界、写回会写进不存在的 QP。QP_NUM 为 2 的幂时本写法与 +1 逐位等价。
            scan <= (scan == QP_W'(QP_NUM - 1)) ? {QP_W{1'b0}} : (scan + QP_W'(1));
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
    wire [QP_W-1:0] qsel = cfg_qp_sel;
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
            // A_STATUS 固定 32 位字：QP_NUM > 32 时只报前 32 个 QP 的限速状态（调试用，不影响限速）。
            A_STATUS:   reg_read_data = {{(32-STATUS_W){1'b0}}, ~tx_rate_ready[STATUS_W-1:0]};
            // S5：QP_W 随 QP_NUM 涨（128 → 7），填充位宽必须用 (32-QP_W) 而不是写死 28。
            // QP_NUM=16（QP_W=4）时与改动前逐位相同（32-4=28）。
            A_QP:       reg_read_data = {{(32-QP_W){1'b0}}, cfg_qp_sel};
            A_QP_RC:    reg_read_data = {12'd0, qp_rc[qsel]};
            A_QP_RT:    reg_read_data = {12'd0, qp_rt[qsel]};
            A_QP_ALPHA: reg_read_data = {22'd0, qp_alpha[qsel]};
            A_QP_CRED:  reg_read_data = qp_credit[qsel];
            // [4:0] iT  [5] cnp_seen  [7:6] 0  [12:8] iB —— 字段位置沿用老布局，但 iB 只有 5 位
            // （qp_ib 是 [4:0]），所以 [13] 恒 0。拼接 = 19+5+2+1+5 = 32 位。
            // 早先补 18 位只拼出 31 位（-Wall 报 WIDTHEXPAND，最高位恒 0 所以读回值碰巧对）。
            A_QP_STATE: reg_read_data = {19'd0, qp_ib[qsel], 2'd0, qp_cnp_seen[qsel], qp_it[qsel]};
            A_QP_CNT:   reg_read_data = qp_cnp_cnt[qsel];
            A_INIT_ALPHA:  reg_read_data = {22'd0, cfg_init_alpha};
            A_G:           reg_read_data = {22'd0, cfg_g};
            A_MAX_HAI_F:   reg_read_data = {24'd0, cfg_max_hai_f};
            default: ;
        endcase
    end

endmodule
`default_nettype wire
