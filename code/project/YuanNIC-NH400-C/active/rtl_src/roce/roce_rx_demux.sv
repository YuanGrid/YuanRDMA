// roce_rx_demux.sv
// 方案 A（B6407）：两路 MAC 合并后的 frame 流按 dest_qpn 分流到 LANES 条独立通路，
// 每条通路各自过自己的 CDC，进入 core_clk 域后接自己的 roce_rx_parse。
//
// 为什么要拆（两个独立的问题，一次解决）：
//
// 1) **head-of-line blocking**。原来 rx_frame → 单份 roce_rx_parse → roce_rx_qpn_split。
//    rx_qpn_split 的准入是 `!payload_busy && lane_header_ready[dest]`，而 lane 的
//    header_ready 来自 roce_rx_disp 的 !busy，后者要等 roce_resp 走到 WRITE_BACK 才清
//    （实测 16.000 拍/包）。一个包进了忙 lane，整条共享流就被堵住，后面发给空闲 lane
//    的包全部排队。B6405/B6406 实测 `-q 4` server write 48.36 Gb/s ≈ `-q 1` 的 50.29，
//    而 server read `-q 4` 能到 281.77（它不经过这条链）。见 §33.4。
//
// 2) **单条 CDC 的带宽天花板**。1024 bit @ core_clk 100 MHz = 102.4 Gb/s，扣掉帧开销
//    （1 KB 帧占 9 拍，payload 8 拍）后 payload 上限约 91 Gb/s。`-q 4` 的 client read
//    需要 4 × 29.13 = 116 Gb/s，**不改 CDC 结构永远到不了**。分流放在 CDC 之前、
//    mac_clk 域（390.63 MHz，1024 bit → 约 400 Gb/s，= eth_mac_clk/o_clk_pll，STA 实测 2.560 ns），
//    每 lane 一份 64 拍异步 FIFO，
//    上界就从 102.4 抬到 4 × 102.4 = 409 Gb/s。
//
// 为什么分流能放在首拍：dest_qpn 在 BTH 字节 47..49，落在首拍（1024 bit = 128 B）之内，
// 与 roce_rx_parse 读它的位置完全一致（roce_rx_parse.sv:106）。不需要缓冲整帧。
//
// 归属规则与 roce_rx_qpn_split 一致：qp_valid=0（QPN 不在本端范围）的包交给 lane 0，
// 由它的 resp 计 RX_BAD_QP，计数口径不变。
//
// 本模块工作在 mac_clk 域（输入）与 core_clk 域（输出）之间，FIFO 自带跨域；
// 复位在两侧各自同步，与 roce_rx_front 里原有 u_cdc 的处理方式一致。
`default_nettype none
`timescale 1ns/1ps
module roce_rx_demux
    import roce_pkg::*;
#(
    parameter int LANES = 4,
    parameter int DEPTH = 64                // 每 lane 的异步 FIFO 深度（1024 bit 拍）
)(
    // 输入：mac_clk 域（roce_rx_front 两路合并后的 frame 流）
    input  wire                mac_clk,
    input  wire                mac_rst,
    input  wire                in_valid,
    output wire                in_ready,
    input  wire  [1023:0]      in_data,
    input  wire  [127:0]       in_keep,
    input  wire                in_last,
    // 输出：core_clk 域，每 lane 一条 frame 流
    input  wire                clk,
    input  wire                rst,
    output wire [LANES-1:0]    lane_valid,
    input  wire [LANES-1:0]    lane_ready,
    output wire [LANES*1024-1:0] lane_data,
    output wire [LANES*128-1:0]  lane_keep,
    output wire [LANES-1:0]    lane_last,
    // 调试（mac_clk 域）：{in_frame, 3'd0, sel}，打平成 4 位以对接 roce_debug 的
    // core_rx_split_state 端口（原来放 {payload_busy, payload_owner}，语义已由本模块取代）
    output wire [3:0]          debug_state,
    // 每 lane 统计（core_clk 域，格雷码跨过来）。B6408 加。
    //   为什么需要：B6407 上板时 RX_DROP 一度被当作「每 lane FIFO 溢出」的证据，
    //   实际它来自 roce_rx_front 的 staging FIFO，见 §35.4。demux 自己的丢弃/阻塞
    //   完全没有观测口，只能从 RX_DUP / RX_SEQ_ERR / RETX_NAK 间接推断，归因成本很高。
    //   这里按 lane 分开计数，才能直接回答「是哪个 lane 被堵」。
    output wire [LANES*32-1:0] lane_frames,     // 该 lane 收进的帧数（SOP 拍计数）
    output wire [LANES*32-1:0] lane_stall,      // 该 lane FIFO 满、skid 里的拍推不进去的拍数
    output wire [LANES*32-1:0] lane_sop_stall   // 其中「卡在帧首拍」的次数：这是真正的丢包风险
);
    localparam int LANE_W = (LANES <= 2) ? 1 : (LANES <= 4) ? 2 : 3;

    // SOP 同拍解析：dest_qpn 在 BTH 字节 47..49（与 roce_rx_parse 同一位置）
    wire [23:0] sop_qpn = {in_data[47*8 +: 8], in_data[48*8 +: 8], in_data[49*8 +: 8]};
    wire        sop_qp_valid = (sop_qpn >= 24'(QPN_BASE)) && (sop_qpn < 24'(QPN_BASE + QP_NUM));
    // 必须按 LANES 取模，不能只取 LANE_W 位：LANES=1 时 LANE_W=1，而 QPN 低位仍会给出 1，
    // fifo_ready[1] 越界恒 0 → in_ready 永不有效 → 整条流死锁（单 lane 仿真台子上就是这样）。
    // LANES 为 2 的幂时 `& (LANES-1)` 与取模等价，且综合成与门。
    wire [LANE_W-1:0] sop_lane_raw = sop_qp_valid ? sop_qpn[LANE_W-1:0] : '0;
    wire [LANE_W-1:0] sop_lane     = sop_lane_raw & LANE_W'(LANES - 1);

    // 整帧跟随 SOP 那拍锁定的 sel；帧中途不再改变
    reg               in_frame;
    reg  [LANE_W-1:0] sel;
    wire [LANE_W-1:0] cur_lane = in_frame ? sel : sop_lane;

    wire [LANES-1:0] fifo_ready;

    // ---------------------------------------------------------------- 输入 skid（一拍）
    // 为什么需要：若 in_ready 直接依赖 in_data 的组合译码，就形成
    //   前端 frame FIFO 的 M20K 输出 → dest_qpn 译码 → 4:1 选 fifo_ready → 回到
    //   该 FIFO 的 m_axis_tready
    // 一条跨存储器出口的组合长路径，在 mac_clk（390.63 MHz，2.56 ns）下很可能违例。
    // 加一拍 skid 后，in_ready 只依赖**寄存器** skid_lane / skid_valid：
    //   in_ready = !skid_valid || fifo_ready[skid_lane]
    // 稳态吞吐仍是 1 拍/周期（排出旧拍的同拍收新拍），只多 1 拍固定延迟。
    reg               skid_valid;
    reg  [1023:0]     skid_data;
    reg  [127:0]      skid_keep;
    reg               skid_last;
    reg  [LANE_W-1:0] skid_lane;

    assign in_ready = !skid_valid || fifo_ready[skid_lane];
    wire   take_in  = in_valid && in_ready;

    always @(posedge mac_clk) begin
        if (mac_rst) begin
            skid_valid <= 1'b0;
            skid_data  <= '0;
            skid_keep  <= '0;
            skid_last  <= 1'b0;
            skid_lane  <= '0;
        end else begin
            // 先排出、再收新：两者同拍发生时 skid 换上新数据（非阻塞赋值后者覆盖前者）
            if (skid_valid && fifo_ready[skid_lane]) skid_valid <= 1'b0;
            if (take_in) begin
                skid_valid <= 1'b1;
                skid_data  <= in_data;
                skid_keep  <= in_keep;
                skid_last  <= in_last;
                skid_lane  <= cur_lane;
            end
        end
    end

    // skid 里那拍按锁定的 lane 送，不再看 in_data
    wire [LANES-1:0] fifo_valid = skid_valid ? (LANES'(1) << skid_lane) : '0;

    // ---------------------------------------------------------------- 每 lane 统计
    // 三个量都在 mac_clk 域产生，每拍每个 lane 最多 +1，用 roce_gray_cnt 跨到 core_clk。
    //
    //   lane_frames    ：该 lane 收进的帧数。计数点在「首拍被 skid 收下」，
    //                    与 in_frame 的建立同拍，一帧只加一次。
    //   lane_stall     ：skid 里有拍、但该 lane 的 FIFO 满，本拍推不进去。
    //                    这是 FIFO 深度的直接观测量——q1 压满一条 lane 时它会持续涨。
    //   lane_sop_stall ：其中「卡住的是帧首拍」的次数。首拍进不去意味着整个包要等，
    //                    持续出现就是真实的丢包/降速风险；帧中间偶尔 stall 一拍无碍。
    //
    // 名字叫 stall 而不是 overflow：axis_async_fifo 的 s_status_overflow 只在
    // FRAME_FIFO=1 时才有意义（按帧整包丢），本模块是 FRAME_FIFO=0，上层靠 in_ready
    // 反压，FIFO 本身不会溢出。真实的「丢」发生在更上游的 staging FIFO，所以这里
    // 观测的是**反压强度**，不是丢弃数。判读时看 lane_stall 的增长斜率即可。
    // 该 lane 本拍被反压（skid 有拍、但 FIFO 满）：FIFO 深度的直接观测量。
    wire             stall_this    = skid_valid && !fifo_ready[skid_lane];
    wire [LANES-1:0] stall_lane    = stall_this ? (LANES'(1) << skid_lane) : '0;

    // skid 里那拍是不是帧首。与 skid_data 同拍装入：take_in 那一拍看到的 in_frame
    // 还是「收进之前」的状态，!in_frame 即本拍是 SOP。
    reg              skid_sop;
    always @(posedge mac_clk) begin
        if (mac_rst)   skid_sop <= 1'b0;
        else if (take_in) skid_sop <= !in_frame;
    end

    // 卡住的是帧首拍才是真风险：整包要等，持续出现就降速/丢包。
    wire             sop_stall_this = stall_this && skid_sop;
    wire [LANES-1:0] sop_stall_lane = sop_stall_this ? (LANES'(1) << skid_lane) : '0;

    // 帧数在「首拍被收下」那一拍计，与 in_frame 建立同拍，一帧一次。
    wire [LANES-1:0] frame_lane     = (take_in && !in_frame) ? (LANES'(1) << sop_lane) : '0;

    // 帧边界跟踪以「收进 skid」为准
    always @(posedge mac_clk) begin
        if (mac_rst) begin
            in_frame <= 1'b0;
            sel      <= '0;
        end else if (take_in) begin
            if (!in_frame) begin
                sel      <= sop_lane;
                in_frame <= !in_last;
            end else if (in_last) begin
                in_frame <= 1'b0;
            end
        end
    end

    genvar lane;
    generate
        for (lane = 0; lane < LANES; lane = lane + 1) begin : gen_lane
            // 每 lane 一份跨域 FIFO：s 侧 mac_clk、m 侧 core_clk。
            // FRAME_FIFO=0：本模块保证一帧只会进同一个 lane，不会跨 lane 打断。
            axis_async_fifo #(
                .DEPTH(DEPTH*128), .DATA_WIDTH(1024), .KEEP_ENABLE(1), .KEEP_WIDTH(128),
                .LAST_ENABLE(1), .USER_ENABLE(0)
            ) u_fifo (
                .s_clk(mac_clk), .s_rst(mac_rst),
                .s_axis_tdata(skid_data), .s_axis_tkeep(skid_keep),
                .s_axis_tvalid(fifo_valid[lane]), .s_axis_tready(fifo_ready[lane]),
                .s_axis_tlast(skid_last), .s_axis_tid(8'd0), .s_axis_tdest(8'd0), .s_axis_tuser(1'b0),
                .m_clk(clk), .m_rst(rst),
                .m_axis_tdata(lane_data[lane*1024 +: 1024]), .m_axis_tkeep(lane_keep[lane*128 +: 128]),
                .m_axis_tvalid(lane_valid[lane]), .m_axis_tready(lane_ready[lane]),
                .m_axis_tlast(lane_last[lane]), .m_axis_tid(), .m_axis_tdest(), .m_axis_tuser(),
                .s_pause_req(1'b0), .s_pause_ack(), .m_pause_req(1'b0), .m_pause_ack(),
                .s_status_depth(), .s_status_depth_commit(), .s_status_overflow(),
                .s_status_bad_frame(), .s_status_good_frame(),
                .m_status_depth(), .m_status_depth_commit(), .m_status_overflow(),
                .m_status_bad_frame(), .m_status_good_frame()
            );

            // 每 lane 三个统计量，格雷码跨到 core_clk。W=32，饱和靠回绕（判读一律用增量）。
            roce_gray_cnt #(.W(32)) u_cnt_frames (
                .source_clk(mac_clk), .source_rst(mac_rst),
                .source_increment(frame_lane[lane]),
                .dest_clk(clk), .dest_count(lane_frames[lane*32 +: 32])
            );
            roce_gray_cnt #(.W(32)) u_cnt_stall (
                .source_clk(mac_clk), .source_rst(mac_rst),
                .source_increment(stall_lane[lane]),
                .dest_clk(clk), .dest_count(lane_stall[lane*32 +: 32])
            );
            roce_gray_cnt #(.W(32)) u_cnt_sop_stall (
                .source_clk(mac_clk), .source_rst(mac_rst),
                .source_increment(sop_stall_lane[lane]),
                .dest_clk(clk), .dest_count(lane_sop_stall[lane*32 +: 32])
            );
        end
    endgenerate

    // {in_frame, 保留位, sel}：LANES=4 时是 {in_frame, 1'b0, sel[1:0]}，正好 4 位
    assign debug_state = {in_frame, 1'b0, sel};
endmodule
`default_nettype wire
