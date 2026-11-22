// roce_rx_front.sv
// RX 前端（MAC 时钟域，**不再做 CDC**）：
//  每路 rx_path_avst 输出：分类（IPv4 无选项、UDP 4791、目的 MAC/IP 为本机）-> ICRC 校验
//  -> 暂存（等 ICRC 结果）-> frame FIFO（坏帧丢弃）；两路按帧合并后送出。
//  rx_path_avst 输出没有反压：在 SOP 处检查暂存空间，不够则整帧丢弃并计数。
// 输入约定：第 0 字节在 [7:0]；transfer_length = 帧长 mod 128（0 表示末拍 128 字节满）。
// 输出：1024 bit 以太网帧（含 ICRC，不含 FCS），keep 从第 0 字节连续（B6386 起与 MAC 侧同宽）。
//
// B6407：输出改为 **mac_clk 域**，CDC 交给下游 roce_rx_demux 的每 lane FIFO。
// 原因是单条 core_clk 1024 bit 通路的天花板只有 102.4 Gb/s，见 roce_rx_demux.sv 文件头。
//
// B6418：两路合并改为**按线上到达顺序**输出（此前是按帧轮转、空则让出，会乱序）。
//  rx_path_avst 把线上**所有**帧（RoCE、ARP、TCP……）严格交替分给两路：全局第 g 帧进第 g mod 2 路
//  （data_concat 的 write_shift，复位后第 0 帧进 lane0）。本模块每路数「本路第几帧」
//  （lane_frame_index，按末拍计、所有帧都计），全局位置 = 2 × 本路序号 + 路号。
//  旧合并在非 RoCE 帧被过滤、某一路连续出现两个 RoCE 帧、而下游又在反压时，会把 N+2 排到 N+1
//  前面；两路 data_concat 各自存储转发，长帧后跟短帧时到达本模块的先后也会颠倒。
//  上板现象：对端发的每个包都进了引擎，响应方却发序号错误 NAK（roce-optimization-log §44.6）。
//  - 令牌 FIFO：每路在 SOP 把**被接收**帧的本路序号压进去；判决 FIFO：提交进 frame FIFO 时压入好/坏
//    （坏帧在 frame FIFO 里整帧丢弃，合并级靠判决知道跳过）。
//  - 合并：两路都有令牌时比序号；只有一路有令牌时，等另一路把「排在它前面的那一帧」走完
//    （另一路的帧数延迟 SEEN_DELAY 拍再比，保证对方那帧若被接收，其令牌已经可见）。
//  - lane_frame_index 只被 mac_seq_rst（与 rx_path_avst 同一个 MAC 复位）复位，RoCE 软复位不清它，
//    否则与 data_concat 的交替相位对不上。两路长时间全空闲时核对一次交替关系，不满足就重新对齐。
//  - 顺序定不下来超过 4095 拍就强制放行（只在计数失步时才会发生），计数器可读。
`default_nettype none
`timescale 1ns/1ps
module roce_rx_front #(
    parameter int MAX_BEATS = 64            // 单帧最多 64 x 128 B，超长截断并判坏
)(
    input  wire              clk,
    input  wire              rst,
    input  wire              mac_clk,
    input  wire              mac_rst,
    // MAC 硬复位（B6418）：只复位每路帧序号计数。必须与 rx_path_avst 的 mac_rst_n 是同一个信号，
    // 且**不能**并入 RoCE 软复位——序号要和 data_concat 的交替相位一直对齐。
    input  wire              mac_seq_rst,
    // 配置（clk 域，准静态）
    input  wire              config_enable,
    input  wire  [31:0]      config_ip,
    input  wire  [47:0]      config_mac,
    // 两路输入（mac_clk 域）
    input  wire  [1:0]       rx_valid,
    input  wire  [2047:0]    rx_data,
    input  wire  [13:0]      rx_last_bytes,
    input  wire  [5:0]       rx_error,
    input  wire  [1:0]       rx_last,
    // 输出（**mac_clk 域**，B6407 起不再跨域；CDC 在下游 roce_rx_demux 的每 lane FIFO）
    output wire              out_valid,
    input  wire              out_ready,
    output wire  [1023:0]    out_data,
    output wire  [127:0]     out_keep,
    output wire              out_last,
    // 计数（clk 域，两路之和）——保留给 0x0200 计数器窗口，兼容既有工具
    output wire  [31:0]      counter_icrc_error,
    output wire  [31:0]      counter_drop,
    // 调试：lane0 暂存占用（clk 域，未做格雷码，仅供观察）。
    // 必须是 10 位：计数器工作区间 0..511，跨过 256，截成 8 位会混叠，
    // 读出 184 其实是 440（正好门限），会把"FIFO 已满"误判成"FIFO 没满却丢包"。
    output reg   [9:0]       debug_staging_occupancy,
    // ---------------------------------------------------------------- 每 lane 统计（clk 域）
    // 数组端口在 Verilog-2001 顶层不可综合/不可连接，一律打平成向量：低位是 lane0。
    // 为什么需要分 lane：两路 MAC 输入各自独立暂存、独立丢帧，只暴露两路之和时
    // 「丢包只发生在 lane1」这种单路故障会被摊薄成 50%，看不出是哪一路的问题。
    output wire  [63:0]      counter_lane_frames,       // [31:0]=lane0，[63:32]=lane1，完成帧数
    output wire  [63:0]      counter_lane_icrc_error,   // 同上，ICRC 校验失败帧
    output wire  [63:0]      counter_lane_drop,         // 同上，staging 满整帧丢弃
    output wire  [19:0]      debug_lane_staging,        // {lane1_occ[9:0], lane0_occ[9:0]} 实时占用
    output wire  [19:0]      debug_lane_staging_peak,   // 同上，自复位/清除以来的峰值
    // 清除峰值：clk 域单拍脉冲，内部同步成 mac 域脉冲
    input  wire              lane_peak_clear,
    // 合并级事件计数（clk 域，B6418）：force = 顺序超时强制放行次数；rebase = 空闲时重新对齐序号次数。
    // 正常运行两者都应恒为 0，非 0 说明两路帧序号与 rx_path_avst 的交替失步过。
    output wire  [31:0]      counter_merge_force,
    output wire  [31:0]      counter_merge_rebase,
    // ---------------------------------------------------------------- PFC 水位（mac_clk 域）
    // 每 lane、每优先级的 staging 占用（拍）与「暂存满整帧丢弃」脉冲，直接进 roce_pfc 做发
    // XOFF 的判据。优先级取 IPv4 TOS[7:5] = DSCP[5:3]（mlx5 默认 dscp2prio = DSCP>>3）。
    // 为什么按优先级分：共享 staging 里一个优先级灌满会把其它优先级一起拖下水，只按总量发
    // PFC 就只能全停；分组统计后能只停灌满的那一个（发不了再退化成全停，见 roce_pfc.sv）。
    // 拍数而不是字节：占用本来就是按拍推进的，乘 128 没有信息量。
    // 本模块固定两路 MAC 输入，所以宽度写死 2 路（不要和 roce_top 的 RDMA core LANES=4 混淆）。
    output wire  [2*8*10-1:0] lane_occupancy,   // [(lane*8+p)*10 +: 10]
    output wire  [2*8-1:0]    lane_drop         // [lane*8+p] 单拍脉冲
);

    // 配置同步到 mac_clk（准静态，只做两级寄存）
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    reg [80:0] config_sync1, config_sync2;
    always @(posedge mac_clk) begin
        config_sync1 <= {config_enable, config_ip, config_mac};
        config_sync2 <= config_sync1;
    end
    wire        mac_enable  = config_sync2[80];
    wire [31:0] mac_local_ip  = config_sync2[79:48];
    wire [47:0] mac_local_mac = config_sync2[47:0];

    wire [1:0]    frame_valid, frame_ready, frame_last;
    wire [2047:0] frame_data;
    wire [255:0]  frame_keep;
    wire [31:0]   lane_icrc_error_count [0:1];
    wire [31:0]   lane_drop_count [0:1];
    wire [31:0]   lane_frame_count [0:1];
    wire [9:0]    lane_staging_occupancy [0:1];
    wire [9:0]    lane_staging_peak [0:1];

    // 峰值清除：clk 域单拍脉冲 -> mac 域单拍脉冲（电平翻转 + 双边沿检测，不用跨域脉冲直接打）
    reg           peak_clear_toggle;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    reg [1:0]     peak_clear_sync;
    reg           peak_clear_seen;
    always @(posedge clk) begin
        if (rst) peak_clear_toggle <= 1'b0;
        else if (lane_peak_clear) peak_clear_toggle <= ~peak_clear_toggle;
    end
    always @(posedge mac_clk) begin
        peak_clear_sync <= {peak_clear_sync[0], peak_clear_toggle};
    end
    wire mac_peak_clear = peak_clear_sync[1] ^ peak_clear_seen;
    always @(posedge mac_clk) peak_clear_seen <= peak_clear_sync[1];

    function automatic [127:0] keep_from_length(input [6:0] n);
        keep_from_length = (n == 7'd0) ? {128{1'b1}} : ((128'd1 << n) - 128'd1);
    endfunction

    // ---------------- 到达顺序（B6418），各路生成块与合并级共用
    localparam int SEQ_W       = 16;     // 本路帧序号位宽，比较按模 2^16、窗口 ±2^15 帧
    localparam int TOKEN_DEPTH = 1024;   // 令牌 / 判决 FIFO 深度：≥ staging + frame FIFO 能同时容纳的帧数
    localparam int SEEN_DELAY  = 16;     // 帧数延迟拍数：> 令牌从压入到 FIFO 输出可见的延迟（约 6 拍）
    reg  [SEQ_W-1:0] lane_frame_index [0:1];     // 本路已结束（末拍过了 stage0）的帧数 = 下一帧的本路序号
    wire [1:0]       lane_eop;                   // 本拍 stage0 是某帧末拍
    wire [1:0]       token_valid, token_pop;
    wire [SEQ_W-1:0] token_head [0:1];
    wire [1:0]       verdict_valid, verdict_good;

    // 复位释放后 16 拍内不接收新帧（B6418）。axis_async_fifo 在复位释放后还要 3 拍（s_rst_sync3_reg）
    // 才拉高 s_axis_tready，而 staging / ICRC 结果 / 令牌 / 判决 FIFO 的 tready 都没接（正常运行时恒有空间）。
    // 若一帧恰好在复位释放那一刻开始，头一两拍会被 staging FIFO 静默丢掉，而 ICRC 与令牌照常记账，
    // 结果是一个缺了头的帧带着「校验通过」进解析。RoCE 软复位（dp_mac_rst）在有流量时就可能碰上。
    // 被挡住的帧按「暂存满」整帧丢弃并计入 counter_drop，对端 go-back-N 重传。
    reg  [4:0]       post_reset_count;
    wire             post_reset_hold = (post_reset_count != 5'd0);
    always @(posedge mac_clk) begin
        if (mac_rst)              post_reset_count <= 5'd16;
        else if (post_reset_hold) post_reset_count <= post_reset_count - 5'd1;
    end

    // B6442：统计计数器的复位改用**本模块内寄存的副本**。
    //
    // B6441 tx_clkout 实测：`mac_rstn`（X192）直连本模块的 roce_gray_cnt 计数器（X197），
    // 单跳 IC 1.874 ns / lv=1 / cell 0.085，265 个端点 −0.078——在 390.6 MHz 的 tx_clkout 上，
    // 1.87 ns 走线就吃掉 73% 的周期。计数器是纯观测量，复位晚 1 拍对任何判读都无影响，
    // 所以让它们吃本地寄存副本，把「远端一处 → 265 个远端负载」换成「本地一处 → 本地多点」。
    //
    // **只给 roce_gray_cnt 用**：数据通路仍用未寄存的 mac_rst，帧序号复位 mac_seq_rst 的
    // 相位关系（与 rx_path_avst 的 data_concat 交替）完全不动。
    // dont_merge 让 fitter 把副本摆在本模块里边，必要时自行复制到各 lane 附近。
    (* dont_merge *) reg mac_rst_stat;
    always @(posedge mac_clk) mac_rst_stat <= mac_rst;

    genvar lane;
    generate
        for (lane = 0; lane < 2; lane = lane + 1) begin : gen_lane
            // ---------------- stage 0：寄存输入
            reg          stage0_valid, stage0_last;
            reg [1023:0] stage0_data;
            reg [6:0]    stage0_length;
            reg [2:0]    stage0_error;
            reg          in_packet;
            always @(posedge mac_clk) begin
                stage0_valid <= rx_valid[lane];
                stage0_last <= rx_last[lane];
                stage0_data <= rx_data[lane*1024 +: 1024];
                stage0_length <= rx_last_bytes[lane*7 +: 7];
                stage0_error <= rx_error[lane*3 +: 3];
                if (mac_rst)    in_packet <= 1'b0;
                else if (stage0_valid) in_packet <= !stage0_last;
            end
            wire stage0_start = stage0_valid && !in_packet;

            wire is_roce_frame = mac_enable &&
                           (stage0_data[0 +: 48]     == mac_local_mac) &&
                           (stage0_data[12*8 +: 16]  == 16'h0008) &&     // EtherType 0x0800
                           (stage0_data[14*8 +: 8]   == 8'h45) &&        // IPv4, IHL=5
                           (stage0_data[23*8 +: 8]   == 8'h11) &&        // UDP
                           (stage0_data[30*8 +: 32]  == mac_local_ip) &&
                           (stage0_data[36*8 +: 16]  == 16'hB712);       // dport 4791

            // ---------------- staging FIFO 占用（按 push/pop 精确计数；SOP 时要能放下一整帧）
            // 原实现一律按 MAX_BEATS(64) 预留 72 拍，而 1 KB 帧实际只占 9 拍，白占 55 拍，
            // 使可用深度从 495 掉到 440（门限之外的那 55 拍永远用不上）。
            // 帧长在第 0 拍就能读到：IPv4 total length 在字节 16..17，加 14 字节以太网头即帧长。
            wire [15:0] sop_ip_total_length = {stage0_data[16*8 +: 8], stage0_data[17*8 +: 8]};
            wire [16:0] sop_frame_bytes      = {1'b0, sop_ip_total_length} + 17'd14;
            // 拍数 = ceil(frame_bytes / 128)，夹在 [1, MAX_BEATS]
            wire [9:0]  sop_frame_beats_raw  = 10'((sop_frame_bytes + 17'd127) >> 7);
            wire [9:0]  sop_frame_beats      = (sop_frame_beats_raw == 10'd0)                  ? 10'd1 :
                                               (sop_frame_beats_raw > 10'(MAX_BEATS))          ? 10'(MAX_BEATS) :
                                                                                                 sop_frame_beats_raw;
            // 只有帧长 >= 128 B 才用精确值：更短的帧可能被 MAC 补齐到以太网最小帧，
            // 按 IP 长度截断会切掉补齐字节、ICRC 必然失败。短帧继续按 MAX_BEATS 预留。
            // 注意这两个值是从 stage0_data 组合出来的，只在 SOP 那拍有效（帧中途 stage0_data
            // 已换成别的拍），所以接受判决用组合值、帧中途的截断判决用 SOP 锁存值（见下）。
            wire        sop_len_trusted      = (sop_frame_bytes >= 17'd128);
            wire [9:0]  sop_reserve          = sop_len_trusted ? sop_frame_beats : 10'(MAX_BEATS);
            wire [6:0]  sop_beat_limit_next  = sop_len_trusted ? sop_frame_beats[6:0] : 7'(MAX_BEATS);

            reg  [9:0] staging_occupancy;
            wire       staging_pop;
            wire       staging_has_room   = (staging_occupancy <= (10'd512 - sop_reserve - 10'd8));
            // B6418：令牌 FIFO 也要有空位（留 8 个余量盖住压入流水），否则整帧按「满」丢弃并计数。
            // 正常情况下 staging 先满（512 拍 ≥ 帧数），这一条基本不会是瓶颈。
            reg  [10:0] token_occupancy;
            wire        token_has_room    = (token_occupancy <= 11'(TOKEN_DEPTH - 8));
            wire        accept_frame = is_roce_frame && staging_has_room && token_has_room && !post_reset_hold;
            assign lane_eop[lane] = stage0_valid && stage0_last;

            // 本帧的拍数上限，SOP 那拍锁存，帧中途的截断判断用这个（对应原实现的 MAX_BEATS）。
            reg  [6:0] sop_beat_limit;

            // ---------------- stage 1：入 ICRC 与 staging
            reg          stage1_push, stage1_start, stage1_last, stage1_bad;
            reg [1023:0] stage1_data;
            reg [127:0]  stage1_keep;
            reg          frame_accepted, error_accumulated;
            reg [6:0]    beat_count;
            reg          drop_event;
            // PFC：本帧优先级 = IPv4 TOS[7:5]（= DSCP[5:3]，与 roce_req/roce_resp 取 QPC TOS 的口径一致），
            // SOP 那拍锁存、整帧不变。时序关系（与 stage1_push 对齐，别改成别的拍）：
            //   SOP 在 stage0 的那拍 T → 沿 T+1：stage1_push（首拍）、frame_prio、drop_event 同时更新。
            //   所以 stage1_push 那拍的 frame_prio 恒为「这一拍数据所属帧」的优先级；
            //   drop_event 与 frame_prio 也同拍有效（drop_event 是单拍脉冲），直接相与即可。
            //   **不要**再晚一拍采 drop_event：下一帧 SOP 紧跟时 frame_prio 已换成下一帧的。
            reg  [2:0]   frame_prio;
            wire [2:0]   sop_prio  = stage0_data[15*8 + 5 +: 3];
            always @(posedge mac_clk) begin
                stage1_push   <= 1'b0;
                drop_event <= 1'b0;
                stage1_data      <= stage0_data;
                stage1_keep      <= stage0_last ? keep_from_length(stage0_length) : {128{1'b1}};
                if (mac_rst) begin
                    frame_accepted <= 1'b0;
                    sop_beat_limit <= 7'(MAX_BEATS);
                    frame_prio     <= 3'd0;
                end else if (stage0_valid) begin
                    if (stage0_start) begin
                        drop_event <= is_roce_frame && !accept_frame;
                        frame_prio <= sop_prio;
                        stage1_push   <= accept_frame;
                        stage1_start    <= 1'b1;
                        stage1_last   <= stage0_last;
                        stage1_bad    <= |stage0_error;
                        error_accumulated <= |stage0_error;
                        frame_accepted   <= accept_frame && !stage0_last;
                        beat_count     <= 7'd1;
                        sop_beat_limit <= sop_beat_limit_next;   // 只在 SOP 这拍有效
                    end else if (frame_accepted) begin
                        stage1_push   <= 1'b1;
                        stage1_start    <= 1'b0;
                        beat_count     <= beat_count + 7'd1;
                        error_accumulated <= error_accumulated | (|stage0_error);
                        if (stage0_last) begin
                            stage1_last <= 1'b1;
                            stage1_bad  <= error_accumulated | (|stage0_error);
                            frame_accepted <= 1'b0;
                        end else if (beat_count == (sop_beat_limit - 7'd1)) begin
                            stage1_last <= 1'b1;                      // 截断
                            stage1_bad  <= 1'b1;
                            frame_accepted <= 1'b0;
                        end else begin
                            stage1_last <= 1'b0;
                        end
                    end
                end
            end

            wire icrc_result_valid, icrc_result_ok;
            roce_icrc #(.DW(1024), .N_PIPE(4)) u_icrc (
                .clk(mac_clk), .rst(mac_rst),
                .in_valid(stage1_push), .in_data(stage1_data), .in_keep(stage1_keep), .in_first(stage1_start), .in_last(stage1_last),
                .out_valid(icrc_result_valid), .out_icrc(), .out_icrc_ok(icrc_result_ok)
            );

            wire         staging_valid, staging_last, staging_bad;
            wire [1023:0] staging_data;
            wire [127:0]  staging_keep;
            wire          staging_ready;
            // staging FIFO 的 tuser 加 3 位优先级（PFC）：出队时按同一优先级扣减占用，
            // 这样每优先级的计数与总占用严格同步增减（同一条 push/pop 事件驱动）。
            wire [2:0]   staging_prio;
            axis_async_fifo #(
                .DEPTH(512), .DATA_WIDTH(1024), .KEEP_ENABLE(0), .LAST_ENABLE(1),
                .USER_ENABLE(1), .USER_WIDTH(132)
            ) u_staging_fifo (
                .s_clk(mac_clk), .s_rst(mac_rst),
                .s_axis_tdata(stage1_data), .s_axis_tkeep('0), .s_axis_tvalid(stage1_push), .s_axis_tready(),
                .s_axis_tlast(stage1_last), .s_axis_tid(8'd0), .s_axis_tdest(8'd0),
                .s_axis_tuser({frame_prio, stage1_last & stage1_bad, stage1_keep}),
                .m_clk(mac_clk), .m_rst(mac_rst),
                .m_axis_tdata(staging_data), .m_axis_tkeep(), .m_axis_tvalid(staging_valid), .m_axis_tready(staging_ready),
                .m_axis_tlast(staging_last), .m_axis_tid(), .m_axis_tdest(),
                .m_axis_tuser({staging_prio, staging_bad, staging_keep}),
                .s_pause_req(1'b0), .s_pause_ack(), .m_pause_req(1'b0), .m_pause_ack(),
                .s_status_depth(), .s_status_depth_commit(), .s_status_overflow(),
                .s_status_bad_frame(), .s_status_good_frame(),
                .m_status_depth(), .m_status_depth_commit(), .m_status_overflow(),
                .m_status_bad_frame(), .m_status_good_frame()
            );

            assign staging_pop = staging_valid && staging_ready;
            assign lane_staging_occupancy[lane] = staging_occupancy;
            always @(posedge mac_clk) begin
                if (mac_rst) staging_occupancy <= 10'd0;
                else      staging_occupancy <= staging_occupancy + {9'd0, stage1_push} - {9'd0, staging_pop};
            end

            // ---------------- PFC：每优先级占用与丢帧脉冲
            // 每优先级一个「拍」计数器，与 staging_occupancy 同源增减；按 lane 打平输出给 roce_pfc。
            // 判据（发 XOFF）在 roce_pfc 里，这里只给原始计数。
            // 每个计数器在自己的生成块里声明，避免同一数组被多个 always 块驱动（Quartus 会报多驱动）。
            for (genvar pp = 0; pp < 8; pp = pp + 1) begin : gen_prio_occ
                reg [9:0] prio_occupancy;
                always @(posedge mac_clk) begin
                    // B6442：同下面的 roce_gray_cnt，改用本地寄存副本（见文件上文 mac_rst_stat）。
                    // 这 8×2 组计数器在 B6441 里另有 29 条 mac_rstn 扇出违例。占用值是给
                    // 发 XOFF 用的慢变量，复位多保持 1 拍只会让它多停在 0 一拍。
                    if (mac_rst_stat)
                        prio_occupancy <= 10'd0;
                    else
                        prio_occupancy <= prio_occupancy
                            + {9'd0, (stage1_push && (frame_prio   == 3'(pp)))}
                            - {9'd0, (staging_pop && (staging_prio == 3'(pp)))};
                end
                assign lane_occupancy[(lane*8 + pp)*10 +: 10] = prio_occupancy;
                assign lane_drop[lane*8 + pp] = drop_event && (frame_prio == 3'(pp));
            end

            // 暂存占用峰值：只看本 lane 自己的 FIFO，过门限前能到多高是判断
            // 「偶发尖峰 vs 稳态贴门限」的直接证据。
            reg [9:0] staging_peak;
            always @(posedge mac_clk) begin
                if (mac_rst || mac_peak_clear) staging_peak <= 10'd0;
                else if (staging_occupancy > staging_peak) staging_peak <= staging_occupancy;
            end
            assign lane_staging_peak[lane] = staging_peak;

            // 本 lane 成功交给合并级的完整帧数（末拍握手）。两路不平衡本身就是故障信息：
            // 正常时两路应大致相等，差得远说明一路在丢或者 MAC 侧只用了其中一路。
            roce_gray_cnt u_frame_counter (.source_clk(mac_clk), .source_rst(mac_rst_stat),
                .source_increment(frame_valid[lane] && frame_ready[lane] && frame_last[lane]),
                .dest_clk(clk), .dest_count(lane_frame_count[lane]));

            wire result_valid, result_ok, result_ready;
            axis_async_fifo #(
                .DEPTH(128), .DATA_WIDTH(1), .KEEP_ENABLE(0), .LAST_ENABLE(0), .USER_ENABLE(0)
            ) u_result_fifo (
                .s_clk(mac_clk), .s_rst(mac_rst),
                .s_axis_tdata(icrc_result_ok), .s_axis_tkeep('0), .s_axis_tvalid(icrc_result_valid), .s_axis_tready(),
                .s_axis_tlast(1'b1), .s_axis_tid(8'd0), .s_axis_tdest(8'd0), .s_axis_tuser(1'b0),
                .m_clk(mac_clk), .m_rst(mac_rst),
                .m_axis_tdata(result_ok), .m_axis_tkeep(), .m_axis_tvalid(result_valid), .m_axis_tready(result_ready),
                .m_axis_tlast(), .m_axis_tid(), .m_axis_tdest(), .m_axis_tuser(),
                .s_pause_req(1'b0), .s_pause_ack(), .m_pause_req(1'b0), .m_pause_ack(),
                .s_status_depth(), .s_status_depth_commit(), .s_status_overflow(),
                .s_status_bad_frame(), .s_status_good_frame(),
                .m_status_depth(), .m_status_depth_commit(), .m_status_overflow(),
                .m_status_bad_frame(), .m_status_good_frame()
            );

            // 末拍等 ICRC 结果，坏帧在 frame FIFO 中整帧丢弃
            wire frame_fifo_ready;
            wire frame_fifo_valid = staging_valid && (!staging_last || result_valid);
            wire frame_fifo_bad   = staging_last && (staging_bad || !result_ok);
            assign staging_ready = frame_fifo_ready && (!staging_last || result_valid);
            assign result_ready     = staging_valid && staging_last && frame_fifo_ready;

            axis_async_fifo #(
                .DEPTH(512*128), .DATA_WIDTH(1024), .KEEP_ENABLE(1), .KEEP_WIDTH(128),
                .LAST_ENABLE(1), .USER_ENABLE(1), .USER_WIDTH(1),
                .FRAME_FIFO(1), .DROP_BAD_FRAME(1), .USER_BAD_FRAME_VALUE(1'b1), .USER_BAD_FRAME_MASK(1'b1)
            ) u_frame (
                .s_clk(mac_clk), .s_rst(mac_rst),
                .s_axis_tdata(staging_data), .s_axis_tkeep(staging_keep), .s_axis_tvalid(frame_fifo_valid), .s_axis_tready(frame_fifo_ready),
                .s_axis_tlast(staging_last), .s_axis_tid(8'd0), .s_axis_tdest(8'd0), .s_axis_tuser(frame_fifo_bad),
                .m_clk(mac_clk), .m_rst(mac_rst),
                .m_axis_tdata(frame_data[lane*1024 +: 1024]), .m_axis_tkeep(frame_keep[lane*128 +: 128]),
                .m_axis_tvalid(frame_valid[lane]), .m_axis_tready(frame_ready[lane]), .m_axis_tlast(frame_last[lane]),
                .m_axis_tid(), .m_axis_tdest(), .m_axis_tuser(),
                .s_pause_req(1'b0), .s_pause_ack(), .m_pause_req(1'b0), .m_pause_ack(),
                .s_status_depth(), .s_status_depth_commit(), .s_status_overflow(),
                .s_status_bad_frame(), .s_status_good_frame(),
                .m_status_depth(), .m_status_depth_commit(), .m_status_overflow(),
                .m_status_bad_frame(), .m_status_good_frame()
            );

            // ---------------- 令牌（B6418）：被接收的帧在 SOP 压入本路序号，与 stage1 首拍同拍。
            // 序号取 SOP 这拍的 lane_frame_index（本路此前已结束的帧数）；单拍帧的末拍计数在同拍
            // 才加，取到的仍是加之前的值，正确。
            reg              token_push;
            reg  [SEQ_W-1:0] token_value;
            always @(posedge mac_clk) begin
                token_push  <= !mac_rst && stage0_start && accept_frame;
                token_value <= lane_frame_index[lane];
            end
            always @(posedge mac_clk) begin
                if (mac_rst) token_occupancy <= 11'd0;
                else         token_occupancy <= token_occupancy + {10'd0, token_push} - {10'd0, token_pop[lane]};
            end
            axis_async_fifo #(
                .DEPTH(TOKEN_DEPTH), .DATA_WIDTH(SEQ_W), .KEEP_ENABLE(0), .LAST_ENABLE(0), .USER_ENABLE(0)
            ) u_token_fifo (
                .s_clk(mac_clk), .s_rst(mac_rst),
                .s_axis_tdata(token_value), .s_axis_tkeep('0), .s_axis_tvalid(token_push), .s_axis_tready(),
                .s_axis_tlast(1'b1), .s_axis_tid(8'd0), .s_axis_tdest(8'd0), .s_axis_tuser(1'b0),
                .m_clk(mac_clk), .m_rst(mac_rst),
                .m_axis_tdata(token_head[lane]), .m_axis_tkeep(), .m_axis_tvalid(token_valid[lane]), .m_axis_tready(token_pop[lane]),
                .m_axis_tlast(), .m_axis_tid(), .m_axis_tdest(), .m_axis_tuser(),
                .s_pause_req(1'b0), .s_pause_ack(), .m_pause_req(1'b0), .m_pause_ack(),
                .s_status_depth(), .s_status_depth_commit(), .s_status_overflow(),
                .s_status_bad_frame(), .s_status_good_frame(),
                .m_status_depth(), .m_status_depth_commit(), .m_status_overflow(),
                .m_status_bad_frame(), .m_status_good_frame()
            );

            // ---------------- 判决（B6418）：每个被接收的帧在提交进 frame FIFO（末拍握手）时压入好 / 坏，
            // 与令牌一一对应、同序。坏帧（ICRC 错、MAC 报错、截断）在 frame FIFO 里被整帧丢弃，
            // 合并级凭判决只消掉令牌。深度与令牌 FIFO 相同：未出队的判决数 ≤ 未出队的令牌数，不会溢出。
            axis_async_fifo #(
                .DEPTH(TOKEN_DEPTH), .DATA_WIDTH(1), .KEEP_ENABLE(0), .LAST_ENABLE(0), .USER_ENABLE(0)
            ) u_verdict_fifo (
                .s_clk(mac_clk), .s_rst(mac_rst),
                .s_axis_tdata(!frame_fifo_bad), .s_axis_tkeep('0), .s_axis_tvalid(staging_valid && staging_ready && staging_last),
                .s_axis_tready(),
                .s_axis_tlast(1'b1), .s_axis_tid(8'd0), .s_axis_tdest(8'd0), .s_axis_tuser(1'b0),
                .m_clk(mac_clk), .m_rst(mac_rst),
                .m_axis_tdata(verdict_good[lane]), .m_axis_tkeep(), .m_axis_tvalid(verdict_valid[lane]), .m_axis_tready(token_pop[lane]),
                .m_axis_tlast(), .m_axis_tid(), .m_axis_tdest(), .m_axis_tuser(),
                .s_pause_req(1'b0), .s_pause_ack(), .m_pause_req(1'b0), .m_pause_ack(),
                .s_status_depth(), .s_status_depth_commit(), .s_status_overflow(),
                .s_status_bad_frame(), .s_status_good_frame(),
                .m_status_depth(), .m_status_depth_commit(), .m_status_overflow(),
                .m_status_bad_frame(), .m_status_good_frame()
            );

            roce_gray_cnt u_icrc_error_counter (.source_clk(mac_clk), .source_rst(mac_rst_stat),
                .source_increment(result_valid && result_ready && !result_ok), .dest_clk(clk), .dest_count(lane_icrc_error_count[lane]));
            roce_gray_cnt u_drop_counter (.source_clk(mac_clk), .source_rst(mac_rst_stat),
                .source_increment(drop_event), .dest_clk(clk), .dest_count(lane_drop_count[lane]));
        end
    endgenerate

    assign counter_icrc_error = lane_icrc_error_count[0] + lane_icrc_error_count[1];
    assign counter_drop     = lane_drop_count[0] + lane_drop_count[1];

    assign counter_lane_frames     = {lane_frame_count[1],     lane_frame_count[0]};
    assign counter_lane_icrc_error = {lane_icrc_error_count[1], lane_icrc_error_count[0]};
    assign counter_lane_drop       = {lane_drop_count[1],      lane_drop_count[0]};

    // 两路暂存占用/峰值同步到 clk 域（只做两级寄存，仅供观察；占用是渐变值，
    // 跨域的个别位不一致不影响"离门限还有多少"这个判断）
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    reg [19:0] lane_staging_sync1, lane_staging_sync2;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    reg [19:0] lane_peak_sync1, lane_peak_sync2;
    always @(posedge clk) begin
        lane_staging_sync1 <= {lane_staging_occupancy[1], lane_staging_occupancy[0]};
        lane_staging_sync2 <= lane_staging_sync1;
        lane_peak_sync1    <= {lane_staging_peak[1], lane_staging_peak[0]};
        lane_peak_sync2    <= lane_peak_sync1;
    end
    assign debug_lane_staging      = lane_staging_sync2;
    assign debug_lane_staging_peak = lane_peak_sync2;

    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    reg [9:0] staging_occupancy_sync;
    always @(posedge clk) begin
        staging_occupancy_sync  <= lane_staging_occupancy[0];
        debug_staging_occupancy <= staging_occupancy_sync;
    end

    // ---------------- 每路帧序号（B6418）
    // 只被 mac_seq_rst 复位；空闲重新对齐（rebase）只改 lane1，见下。
    wire             merge_rebase;
    wire [SEQ_W-1:0] rebase_index1;
    always @(posedge mac_clk) begin
        if (mac_seq_rst) begin
            lane_frame_index[0] <= '0;
            lane_frame_index[1] <= '0;
        end else begin
            if (lane_eop[0]) lane_frame_index[0] <= lane_frame_index[0] + 1'b1;
            if (merge_rebase)     lane_frame_index[1] <= rebase_index1;
            else if (lane_eop[1]) lane_frame_index[1] <= lane_frame_index[1] + 1'b1;
        end
    end
    // 延迟 SEEN_DELAY 拍的帧数：某路帧数走到这里时，那些帧若被接收，令牌必然已经在 FIFO 输出端可见。
    reg  [SEQ_W-1:0] seen_pipe0 [0:SEEN_DELAY-1];
    reg  [SEQ_W-1:0] seen_pipe1 [0:SEEN_DELAY-1];
    integer          seen_k;
    always @(posedge mac_clk) begin
        if (mac_seq_rst) begin
            for (seen_k = 0; seen_k < SEEN_DELAY; seen_k = seen_k + 1) begin
                seen_pipe0[seen_k] <= '0;
                seen_pipe1[seen_k] <= '0;
            end
        end else begin
            seen_pipe0[0] <= lane_frame_index[0];
            for (seen_k = 1; seen_k < SEEN_DELAY; seen_k = seen_k + 1) seen_pipe0[seen_k] <= seen_pipe0[seen_k-1];
            if (merge_rebase) begin
                for (seen_k = 0; seen_k < SEEN_DELAY; seen_k = seen_k + 1) seen_pipe1[seen_k] <= rebase_index1;
            end else begin
                seen_pipe1[0] <= lane_frame_index[1];
                for (seen_k = 1; seen_k < SEEN_DELAY; seen_k = seen_k + 1) seen_pipe1[seen_k] <= seen_pipe1[seen_k-1];
            end
        end
    end
    wire [SEQ_W-1:0] seen_late0 = seen_pipe0[SEEN_DELAY-1];
    wire [SEQ_W-1:0] seen_late1 = seen_pipe1[SEEN_DELAY-1];

    // ---------------- 两路按到达顺序合并（B6418）
    // 全局位置：lane0 第 i 帧 = 2i，lane1 第 i 帧 = 2i+1。
    //   两路都有令牌：序号小的先，相等时 lane0 先（idx0 <= idx1）。
    //   只有 lane0 有令牌 idx0：lane1 必须已走完序号 < idx0 的帧（seen_late1 >= idx0）。
    //   只有 lane1 有令牌 idx1：lane0 必须已走完序号 <= idx1 的帧（seen_late0 >= idx1 + 1）。
    // 比较都按模 2^SEQ_W、最高位当符号。
    //
    // 判决寄存一拍（dec_*）：比较器与 16 位减法不进 ready 路径。本拍若有令牌出队，下一拍的 dec
    // 作废（它看的是出队前的队头），所以出队后至少隔一拍才能再选——只影响连续的单拍帧，
    // 多拍帧在本帧传输期间就把下一个判决算好了，帧间零空拍。
    // 本拍没有出队时，下一拍的队头只可能「新出现」（另一路原来是空的）：只有一路有令牌时放行依据是
    // seen_late，凡是被它算作「已走完」的帧，令牌都已可见；新出现的令牌序号只会更大，判决仍然成立。
    wire [SEQ_W-1:0] head0 = token_head[0];
    wire [SEQ_W-1:0] head1 = token_head[1];
    wire [SEQ_W-1:0] diff_heads  = head1 - head0;
    wire [SEQ_W-1:0] diff_clear0 = seen_late1 - head0;
    wire [SEQ_W-1:0] diff_clear1 = seen_late0 - head1 - 1'b1;
    wire             lane0_first = !diff_heads[SEQ_W-1];
    wire             clear0      = !diff_clear0[SEQ_W-1];
    wire             clear1      = !diff_clear1[SEQ_W-1];
    reg              force_release;
    wire             both_tokens = token_valid[0] && token_valid[1];
    wire             next_lane   = both_tokens ? !lane0_first : !token_valid[0];
    wire             next_ok     = both_tokens ||
                                   (token_valid[0] && (clear0 || force_release)) ||
                                   (token_valid[1] && (clear1 || force_release));

    reg  dec_valid, dec_lane;
    reg  merge_in_frame, merge_lane;
    wire exec_lane   = dec_lane;
    wire exec_now    = !merge_in_frame && dec_valid;
    wire exec_out    = exec_now && verdict_valid[exec_lane] &&  verdict_good[exec_lane] && frame_valid[exec_lane];
    wire exec_drop   = exec_now && verdict_valid[exec_lane] && !verdict_good[exec_lane];
    wire out_lane    = merge_in_frame ? merge_lane : exec_lane;
    wire merge_valid = merge_in_frame ? frame_valid[merge_lane] : exec_out;
    wire merge_ready;
    wire beat_fire   = merge_valid && merge_ready;
    wire first_fire  = exec_out && merge_ready;
    assign frame_ready = {out_lane & beat_fire, ~out_lane & beat_fire};
    assign token_pop   = {(exec_lane && (first_fire || exec_drop)), (!exec_lane && (first_fire || exec_drop))};

    always @(posedge mac_clk) begin
        if (mac_rst) begin
            merge_in_frame <= 1'b0;
            merge_lane     <= 1'b0;
            dec_valid      <= 1'b0;
            dec_lane       <= 1'b0;
        end else begin
            if (merge_in_frame) begin
                if (beat_fire && frame_last[merge_lane]) merge_in_frame <= 1'b0;
            end else if (first_fire) begin
                merge_in_frame <= !frame_last[exec_lane];
                merge_lane     <= exec_lane;
            end
            dec_valid <= next_ok && !(|token_pop);
            dec_lane  <= next_lane;
        end
    end

    // 顺序超时：有令牌但顺序定不下来（等另一路的帧）连续 4095 拍，就放行。正常时另一路的帧最多晚
    // 一个最大帧 + data_concat 流水（< 100 拍）就会到；只有序号与 rx_path_avst 的交替失步才会走到这里。
    reg  [11:0] order_wait;
    reg         force_event;
    wire        ordering_wait = !merge_in_frame && (|token_valid) && !next_ok;
    always @(posedge mac_clk) begin
        force_event <= 1'b0;
        if (mac_rst || !ordering_wait) begin
            order_wait    <= 12'd0;
            force_release <= 1'b0;
        end else if (order_wait == 12'hFFF) begin
            force_release <= 1'b1;
            force_event   <= !force_release;
        end else begin
            order_wait <= order_wait + 12'd1;
        end
    end

    // 空闲重新对齐：两路输入、令牌、判决、合并全空闲 256 拍后核对一次交替关系。
    // 线上 T 帧严格交替时 lane0 = ceil(T/2)、lane1 = floor(T/2)，差只能是 0 或 1；不是就说明失步
    // （例如上游丢过帧），把 lane1 的序号改到最接近的合法值：差 >= 2 → 差 1，差 < 0 → 差 0。
    // 256 拍远大于 data_concat 把一个已收完的帧送出来所需的时间，空闲到这时不会还有帧卡在半路。
    reg  [8:0] quiet_count;
    wire       quiet_now = !merge_in_frame && !(|token_valid) && !(|verdict_valid) && !(|rx_valid);
    always @(posedge mac_clk) begin
        if (mac_rst || !quiet_now)       quiet_count <= 9'd0;
        else if (quiet_count != 9'h1FF)  quiet_count <= quiet_count + 9'd1;
    end
    wire [SEQ_W-1:0] lane_diff = lane_frame_index[0] - lane_frame_index[1];
    wire             diff_legal = (lane_diff == '0) || (lane_diff == SEQ_W'(1));
    assign merge_rebase  = (quiet_count == 9'd256) && !diff_legal;
    assign rebase_index1 = lane_diff[SEQ_W-1] ? lane_frame_index[0] : (lane_frame_index[0] - 1'b1);

    roce_gray_cnt u_merge_force_counter (.source_clk(mac_clk), .source_rst(mac_rst_stat),
        .source_increment(force_event), .dest_clk(clk), .dest_count(counter_merge_force));
    roce_gray_cnt u_merge_rebase_counter (.source_clk(mac_clk), .source_rst(mac_rst_stat),
        .source_increment(merge_rebase), .dest_clk(clk), .dest_count(counter_merge_rebase));

    // 1024 bit（B6386）：不再降到 512，直接以 MAC 侧位宽输出。
    // 删掉的 axis_adapter（1024->512）原本是每 128 B 输入要 2 个输出拍的反向限速点。
    //
    // B6407：这里**不再放 CDC FIFO**。原来单条 u_cdc（256 拍 @ core_clk 100 MHz）
    // 把整条 RX 通路的天花板压在 102.4 Gb/s、payload 约 91 Gb/s，`-q 4` 读需要的
    // 116 Gb/s 永远到不了。改成把合并后的流原样送出（mac_clk 域），由调用方
    // roce_rx_demux 按 dest_qpn 分流，每 lane 一份异步 FIFO 各自过域。
    assign out_valid = merge_valid;
    assign out_data  = frame_data[out_lane*1024 +: 1024];
    assign out_keep  = frame_keep[out_lane*128 +: 128];
    assign out_last  = frame_last[out_lane];
    assign merge_ready = out_ready;
endmodule
`default_nettype wire
