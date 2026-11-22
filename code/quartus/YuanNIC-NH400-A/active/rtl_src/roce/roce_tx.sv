// roce_tx.sv
// TX 组包：2 个任务源（0 响应方 ACK/READ RESP，1 请求方）按包轮询 ->
//  A 级：有 payload 的任务先发 DMA 读，再进在途 FIFO（读与组包流水，掩盖 PCIe 读延迟）；
//  B 级：用任务自带的组头字段（S3 起不再查 QPC）组 Eth/IPv4/UDP/BTH/扩展头（含 IP 校验和），头部右对齐放进 128 B 两拍，
//        与 payload（尾部 pad_count 补 0）一起送 roce_skip_align 去掉头前填充，输出连续以太网帧
//        （不含 ICRC）。frame_last_bytes = (帧长 + 4) mod 128（加上 ICRC 后末拍有效字节，供 MAC 侧）。
// 头长只有 54/58/70/74 四种（skip = 74/70/58/54，mod 64 不落在 1..3，冲刷最多一拍）。
//
// 每包时序（1024 bit，1 KB 包 = 9 拍）：
//   BUILD_PREP          1 拍：取任务 + 组头 + 算 IP 校验和 + 右对齐到 128 B + 给
//                            skip_align 元数据，并把头部（恒单拍）同拍送出
//   BUILD_PAYLOAD       8 拍：每拍 128 B payload
// 组包所需的全部组合逻辑只吃 build_job_head（在途 FIFO 的输出，PREP 拍有效），
// 所以 PREP 一拍就能出完整头部。
//
// 1024 bit（B6386）：引擎内部由 512 位加宽到 1024 位，与 roce_top/MAC 侧同宽，
// 删掉了 roce_tx_out 的 512→1024 适配器。头部最长 74 B，一拍装得下，
// BUILD_HEADER_BEAT1 状态删除（512 位时代 70/74 B 头要占两拍）。
`default_nettype none
`timescale 1ns/1ps
module roce_tx
    import roce_pkg::*;
(
    input  wire                    clk,
    input  wire                    rst,
    input  wire  [47:0]            local_mac,
    input  wire  [31:0]            local_ip,
    // 任务
    input  wire  [1:0]             tx_job_valid,
    output wire  [1:0]             tx_job_ready,
    input  tx_job_t                tx_job [2],
    // DMA 读
    output wire                    dma_read_request_valid,
    input  wire                    dma_read_request_ready,
    output wire  [63:0]            dma_read_request_address,
    output wire  [63:0]            dma_read_request_page1,
    output wire  [12:0]            dma_read_request_length,
    input  wire                    dma_read_valid,
    output wire                    dma_read_ready,
    input  wire  [1023:0]          dma_read_data,
    input  wire  [127:0]           dma_read_keep,
    input  wire                    dma_read_last,
    // 帧输出（不含 ICRC）
    output wire                    frame_valid,
    input  wire                    frame_ready,
    output wire  [1023:0]          frame_data,
    output wire  [127:0]           frame_keep,
    output wire                    frame_last,
    output wire  [6:0]             frame_last_bytes,
    output wire  [6:0]             frame_last_beat_bytes,     // 末拍（不含 ICRC）有效字节数，0 表示 128
    input  wire  [1:0]             cnp_bth_flags,             // B6434：{FECN, BECN}，只对 CNP 生效（默认 2'b01）
    // 重传代际的下发边带（B6461，来自同一 lane 的 roce_req；见 roce-optimization-log.md §111）。
    // roce_req 在**每次** REQ_RESTART 把该 QP 的代际 +1 并在那一拍发一个脉冲；本模块按 QP 记下当前值。
    // 在途 FIFO 里还排着的上一批重传任务代际不符 → PREP 拍整包丢弃（含它自己的 DMA 读拍）。
    // 判据必须与任务里的 rtx 相与：首次发送 / 响应方 / CNP 的 rtx 恒 0，永不被丢弃。
    input  wire                    rtx_epoch_valid,
    input  wire  [QP_LW-1:0]       rtx_epoch_qp,              // lane 局部索引（与 qp_local() 同口径）
    input  wire  [RTX_EPOCH_W-1:0] rtx_epoch_value,
    output reg                     event_tx_packet,
    // DCQCN（阶段 3）：**准入**事件——比 event_tx_packet（帧尾）更适合做信用/字节统计，
    // 因为它是「这个包被允许上线」的那一拍，且 job 的值稳定（event_tx_packet 那拍 job 可能
    // 已被下一包的 PREP 覆盖）。
    output reg                     event_tx_admit,
    output reg  [QP_W-1:0]         event_tx_admit_qp,
    output reg  [12:0]             event_tx_admit_length,
    // 调试：{inflight_used[4:0], skip_align_state[2:0], build_state[1:0]}
    // 布局见 roce_debug.sv 0x056C：[10] = inflight[4]（B6413 起；此前该位恒 0），
    // [9:7] = inflight[3:1]，[6:4] = skip_align，[3:2] 由 tx_mux 拼接，[1:0] = build_state。
    // 深度 16 需要 5 位，正好用掉原先的空位，roce_top / roce_debug 的位宽不用改。
    output wire  [9:0]             debug_state
);
    // ------------------------------------------------------------ A 级
    reg       issue_round_robin;
    wire      issue_pick = tx_job_valid[issue_round_robin] ? issue_round_robin : ~issue_round_robin;
    wire      issue_any  = |tx_job_valid;
    tx_job_t  issue_job;
    assign    issue_job = tx_job[issue_pick];
    // 在途 FIFO 深度（B6413：8 → 16；B6457：16 → 32）。
    //
    // 依据（§36.9 / §37）：1 MB 读响应的包率不随 core_clk 变化（100 MHz 8.88 Mpps、
    // 125 MHz 9.53 Mpps），而 8 / 包率 在两个频率下都约等于 840~900 ns，正是 PCIe 读往返；
    // 上板用 0x0578[15:8] 采到未完成 AR 数 p50 = 9、p90 = 10、max = 11，说明每个响应包的
    // 1024 B DMA 读把槽位占满。加深后上限由组包侧的 9 拍/包给出（13.89 Mpps ≈ 113.8 Gb/s）。
    //
    // B6457 改 32 的依据（roce-optimization-log.md §101，定向台子 test/sim/tx_inflight_rtt）：
    // MTU 1024 下单 QP 实测 143.86 Gb/s = 14.24 拍/包（core 250 MHz），比组包侧结构上限
    // 9 拍多出 6.24 拍。台子显式注入 PCIe 读延迟扫描，确认这 6.24 拍就是槽位不够：
    //   RTT 0/220/440 ns → 9.00 拍；RTT 860 ns（板上实测）→ 12.00 拍；1720 ns → 26.36 拍，
    //   且每轮 inflight_used 都打满。深度 24/32 在 860~1200 ns 全部回到 9.00 拍（结构上限）。
    //
    // 为什么选 32 而不是 24：**两者占用同一个 M20K**。每项 $bits(tx_job_t)=628 bit，
    // 32 深 = 20096 bit = 单个 M20K（20480 bit）的 98.1%，24 深只占 73.6%——RAM 成本相同，
    // 而 32 深多出 34% 的往返余量（真实 PCIe 往返会随负载浮动）。再往上 40/48 就要第二块 M20K。
    // ALM 开销可忽略，代价只有 ADDR_WIDTH 4→5 位。
    // 上限约束不变：32 个 1024 B 读仍在 DMA 侧 read_credit（480）之内。
    localparam int INFLIGHT_DEPTH = 32;
    wire      inflight_ready;
    wire [5:0] inflight_used;      // 在途 FIFO 占用（深度 32，$clog2(32)+1 = 6 位）
    wire      issue_needs_read = (issue_job.payload_length != 13'd0);
    assign dma_read_request_valid = issue_any && inflight_ready && issue_needs_read;
    assign dma_read_request_address  = issue_job.physical_address0;
    assign dma_read_request_page1 = issue_job.physical_page1;
    assign dma_read_request_length   = issue_job.payload_length;
    wire      issue_take = issue_any && inflight_ready && (!issue_needs_read || dma_read_request_ready);
    assign tx_job_ready  = issue_take ? (2'b01 << issue_pick) : 2'b00;
    always @(posedge clk) begin
        if (rst)        issue_round_robin <= 1'b0;
        else if (issue_take) issue_round_robin <= ~issue_pick;
    end
    // 准入事件（DCQCN 信用/升速字节计数用）。
    // **只算数据包**：ACK / NAK / READ RESP / CNP 不参与 DCQCN 的速率控制。若把 ACK 也扣信用，
    // 双向流量下 ACK 会被自己的数据速率拖住 → 对端收不到 ACK → 重传 → 更拥塞（死锁方向）。
    // 判据用 opcode：请求/data 类 <= OP_READ_REQ，响应类与 CNP 都不计。
    wire issue_is_data = (issue_job.opcode <= OP_READ_REQ);
    always @(posedge clk) begin
        event_tx_admit <= issue_take && issue_is_data;
        if (issue_take && issue_is_data) begin
            event_tx_admit_qp     <= issue_job.qp_index;
            event_tx_admit_length <= issue_job.payload_length;
        end
    end

    // 在途任务 FIFO（深度限制提前发出的 DMA 读数）
    wire      build_job_valid;
    wire      build_job_ready;
    tx_job_t  build_job_head;
    axis_async_fifo #(
        .DEPTH(INFLIGHT_DEPTH), .DATA_WIDTH($bits(tx_job_t)), .KEEP_ENABLE(0), .LAST_ENABLE(0), .USER_ENABLE(0)
    ) u_inflight (
        .s_clk(clk), .s_rst(rst),
        .s_axis_tdata(issue_job), .s_axis_tkeep('0), .s_axis_tvalid(issue_take), .s_axis_tready(inflight_ready),
        .s_axis_tlast(1'b1), .s_axis_tid(8'd0), .s_axis_tdest(8'd0), .s_axis_tuser(1'b0),
        .m_clk(clk), .m_rst(rst),
        .m_axis_tdata(build_job_head), .m_axis_tkeep(), .m_axis_tvalid(build_job_valid), .m_axis_tready(build_job_ready),
        .m_axis_tlast(), .m_axis_tid(), .m_axis_tdest(), .m_axis_tuser(),
        .s_pause_req(1'b0), .s_pause_ack(), .m_pause_req(1'b0), .m_pause_ack(),
        .s_status_depth(), .s_status_depth_commit(), .s_status_overflow(),
        .s_status_bad_frame(), .s_status_good_frame(),
        .m_status_depth(inflight_used), .m_status_depth_commit(), .m_status_overflow(),
        .m_status_bad_frame(), .m_status_good_frame()
    );

    // ------------------------------------------------------------ B 级
    // 1024 bit（B6386）：头部恒单拍，只剩 PREP（头+元数据）与 PAYLOAD 两个状态。
    // B6461：加 BUILD_DROP——被代际丢弃的任务若带 payload，它那几拍 DMA 读必须照样收下扔掉
    // （A 级在入队前就发过读请求，读数据是按序的裸流，不收下就会把后面的包整体错位）。
    localparam [1:0] BUILD_PREP = 2'd0, BUILD_PAYLOAD = 2'd1, BUILD_DROP = 2'd2;
    reg  [1:0]    build_state;
    tx_job_t      job;                   // 本包任务（PREP 拍从在途 FIFO 锁存；payload 阶段只用 payload_length）

    function automatic [15:0] swap16(input [15:0] value); swap16 = {value[7:0], value[15:8]}; endfunction
    function automatic [23:0] swap24(input [23:0] value); swap24 = {value[7:0], value[15:8], value[23:16]}; endfunction
    function automatic [31:0] swap32(input [31:0] value); swap32 = {value[7:0], value[15:8], value[23:16], value[31:24]}; endfunction
    function automatic [63:0] swap64(input [63:0] value); swap64 = {swap32(value[31:0]), swap32(value[63:32])}; endfunction

    // 组包输入：在途 FIFO 的输出（PREP 拍有效）。S3 起组头字段都在任务里，没有任何按 QP 的选路。
    tx_job_t      build_job;             // 别名，强调下面这一整段读的是 FIFO 输出
    assign build_job = build_job_head;

    // ------------------------------------------------------------ 重传代际表（B6461，§108.2 第 3 条）
    // 每 QP 一个「当前重发批次号」。写入只有 roce_req 的 REQ_RESTART 脉冲一个来源（一拍一个 QP），
    // 所以是一写一读的小表：32 项 × RTX_EPOCH_W 位（LANE_QPS 项，不是 QP_NUM——每 lane 只服务自己的 QP）。
    //
    // **为什么放在这里而不是让 roce_req 整表广播**：整表 32×4=128 位的跨模块走线没必要；
    // 同拍旁路（见下面的 cur_rtx_epoch）已经把「通知与出队撞在同一拍」的窗口补上了。
    reg  [RTX_EPOCH_W-1:0] rtx_epoch_tbl [LANE_QPS];
    always @(posedge clk) begin
        if (rst) begin
            for (int lq = 0; lq < LANE_QPS; lq++) rtx_epoch_tbl[lq] <= '0;
        end else if (rtx_epoch_valid) begin
            rtx_epoch_tbl[rtx_epoch_qp] <= rtx_epoch_value;
        end
    end
    // 本任务的 QP 的当前代际。qp_local() 把全局 qp_index 换成 lane 局部索引（与表的写法一致；
    // **不能拿全局索引直接下标**——LANE_QPS=32 的阵列被 0..127 的索引回绕到别的 QP 上，是静默错丢）。
    wire [QP_LW-1:0] build_job_qp_l = qp_local(build_job.qp_index);
    // 同拍旁路：通知与出队恰好同一拍、且是同一个 QP 时按新值判。
    // 少了它，每次 restart 都可能有一个旧任务在那一拍「逃过」丢弃（多上线一个重复包，不是致命错，但没必要留口子）。
    wire [RTX_EPOCH_W-1:0] cur_rtx_epoch =
        (rtx_epoch_valid && (rtx_epoch_qp == build_job_qp_l)) ? rtx_epoch_value
                                                              : rtx_epoch_tbl[build_job_qp_l];
    // 丢弃判据：**只对重传任务生效**。首次发送（rtx=0）不论代际是什么都必须上线。
    wire        build_job_stale = build_job.rtx && (build_job.rtx_epoch != cur_rtx_epoch);

    wire       header_has_reth = op_has_reth(build_job.opcode);
    wire       header_has_aeth = op_has_aeth(build_job.opcode);
    wire       header_has_immediate  = op_has_imm(build_job.opcode);
    // UD（0x64/0x65）：BTH 后跟 DETH 8 B（Q_Key 4 B + 源 QPN 3 B + 1 B 保留），而不是 RETH。
    // 目的 QPN 不另带——BTH 的 Dest QP 本身就是 UD 的目的 QPN（复用 build_job.dqpn）。
    wire       header_has_deth = op_has_deth(build_job.opcode);
    // CNP：BTH 后跟 16 B 保留（不是 RETH），所以头长与 READ RESP 一样是 70 B，但内容全 0。
    wire       header_is_cnp   = op_is_cnp(build_job.opcode);
    // B6439：extension_length / header_length / header_skip / ip_total_length / frame_length
    // 全部由产生方算好、随 tx_job 流过在途 FIFO，PREP 拍只读寄存器。
    // B6438 的 core −0.301 ns 最差路径正是「FIFO 出口 → 这四项译码求和 → add_4/5/87/86/88
    // → skip_align 移位」，见 roce-optimization-log.md §68。
    wire [1:0] job_pad_count   = tx_pad_count(build_job.payload_length);
    wire [15:0] computed_ip_total_length = build_job.ip_total_length;

    // ---- IP 校验和（B6433 起三操作数口径）
    // B6433 把与包无关的部分（0x4000 标志、TTL/协议、源/目的 IP）按 QP 预加并寄存，PREP 拍只剩
    // 「静态和 + TOS 字 + IP 总长」三项。S3 起静态和 csum_base 由生成任务的一方从已装载上下文算好、
    // 随任务进在途 FIFO，PREP 拍直接取用：原来的 16 选 1（128 QP 时 128 选 1）选路彻底去掉。
    // TOS 同理：任务里的 tos 恒有效（CNP 由引擎填 cnp_tos），原来的 tos_valid 二选一也去掉。
    wire [7:0]  header_tos = build_job.tos;
    wire [19:0] computed_checksum_sum = build_job.csum_base +
                        {4'd0, 8'h45, header_tos} + {4'd0, computed_ip_total_length};
    wire [16:0] checksum_fold1 = {1'b0, computed_checksum_sum[15:0]} + {13'd0, computed_checksum_sum[19:16]};
    wire [15:0] checksum_fold2 = checksum_fold1[15:0] + {15'd0, checksum_fold1[16]};
    wire [15:0] computed_checksum = swap16(~checksum_fold2);

    reg [1023:0] header_computed;
    always @* begin
        header_computed = '0;
        header_computed[0   +: 48] = build_job.dmac;
        header_computed[48  +: 48] = local_mac;
        header_computed[96  +: 16] = 16'h0008;                 // EtherType 0x0800
        header_computed[112 +: 8]  = 8'h45;
        header_computed[120 +: 8]  = header_tos;
        header_computed[128 +: 16] = swap16(computed_ip_total_length);
        header_computed[160 +: 16] = 16'h0040;                 // DF
        header_computed[176 +: 8]  = build_job.ttl;
        header_computed[184 +: 8]  = 8'h11;
        header_computed[192 +: 16] = computed_checksum;        // IP 校验和（当拍算完当拍写，不再单独占一拍）
        header_computed[208 +: 32] = local_ip;
        header_computed[240 +: 32] = build_job.dip;
        header_computed[272 +: 16] = swap16(build_job.sport);
        header_computed[288 +: 16] = 16'hB712;                 // 4791
        header_computed[304 +: 16] = swap16(computed_ip_total_length - 16'd20);
        header_computed[336 +: 8]  = build_job.opcode;
        // BTH byte1 = {SE, M, PadCnt, TVer}。M 只有 CNP 以外的 opcode 才置 1（CNP 的 M 必须为 0）。
        header_computed[344 +: 8]  = {build_job.solicited, !header_is_cnp, job_pad_count, 4'd0};
        header_computed[352 +: 16] = 16'hFFFF;                 // P_Key
        header_computed[376 +: 24] = swap24(build_job.dqpn);
        header_computed[400 +: 8]  = {build_job.ack_request, 7'd0};
        header_computed[408 +: 24] = swap24(build_job.psn);
        if (header_has_reth) begin
            header_computed[432 +: 64] = swap64(build_job.reth_virtual_address);
            header_computed[496 +: 32] = swap32(build_job.reth_rkey);
            header_computed[528 +: 32] = swap32(build_job.reth_length);
        end
        if (header_has_aeth) header_computed[432 +: 32] = {swap24(build_job.aeth_msn), build_job.aeth_syndrome};
        // UD 的 DETH（IBTA §9.8.5）：BTH 起于字节 42、12 B → DETH 起于字节 54。
        //   [432 +: 32] = 字节 54..57 = Q_Key（网络序，任务里是主机序，swap32）
        //   [464 +: 24] = 字节 58..60 = 源 QPN（24 bit，网络序，swap24）
        //   字节 61（[488 +: 8]）= 保留，header_computed 复位即 0，这里不写。
        // 目的 QPN 在 BTH（[376 +: 24]，上面已按 build_job.dqpn 写过），DETH 里没有。
        if (header_has_deth) begin
            header_computed[432 +: 32] = swap32(build_job.deth_qkey);
            header_computed[464 +: 24] = swap24(build_job.deth_src_qp);
        end
        if (header_has_immediate)  begin
            // ImmDt 的位置随前一种扩展头走：RETH 之后 = 字节 70；DETH 之后 = 字节 62；
            // 都没有 = 字节 54（RC 的 SEND_ONLY_IMM / SEND_LAST_IMM）。
            // **UD_IMM 无 RETH 但有 DETH**，必须落在 62——旧代码只判 RETH，会把它写进 432
            // （字节 54）覆盖 DETH 的 Q_Key，对端 qkey 校验失败整包丢，是静默错帧。
            // 与接收侧 roce_rx_parse.sv 的 immediate_offset（reth?70 : ud?62 : 54）同口径。
            if (header_has_reth)       header_computed[560 +: 32] = build_job.immediate;
            else if (header_has_deth)  header_computed[496 +: 32] = build_job.immediate;
            else                       header_computed[432 +: 32] = build_job.immediate;
        end
        // CNP：BTH byte4 = {FECN, BECN, 6'b0}，BECN 置 1（对端据此知道这是拥塞通知）；
        // 16 B 保留字段全 0（header_computed 复位即 0），PSN / AckReq 也都是 0。
        if (header_is_cnp) begin
            header_computed[368 +: 8]  = {cnp_bth_flags[1], cnp_bth_flags[0], 6'b0};  // B6434：{FECN,BECN} 可配
            header_computed[408 +: 24] = 24'd0;          // PSN
            header_computed[400 +: 8]  = 8'd0;           // AckReq=0
        end
    end

    wire [6:0]    build_header_length = build_job.header_length;
    wire [12:0]   frame_length = build_job.frame_length;

    // 1024 bit（B6386）：一拍 128 B，最长头 74 B 也装得进，所有包都是**单拍头**，
    // BUILD_HEADER_BEAT1 状态整个删掉。skip 恒为 128 - header_length。
    //
    // 历史（512 bit，§23）：那时头长 <= 64 的对齐到 64 B 以避开 skip_align 的
    // first_useful_beat=1，否则第 0 拍整拍被丢弃。1024 下 skip < 128 = BEAT_BYTES，
    // first_useful_beat 恒 0，这个区分不再需要，统一对齐到 128 B。
    wire [6:0]    header_skip = build_job.header_skip;

    // 头部右对齐到 128 B。常量移位，纯连线 + 选择。
    // 语义：128 B 一拍里，头占**最低** header_length 字节([0 +: header_length*8])，
    // 右对齐后这 header_length 字节要落在 [ (128-L)*8 +: L*8 ]，即左移 (128-L)*8 位；
    // 之后 skip_align 用 meta_skip = header_skip = 128-L 丢掉低 (128-L) 字节，剩下的正好是头。
    // **两项必须成对**：case 里的移位量写错，skip 却仍按 L 丢字节 → 头整体错位（静默错帧）。
    reg [1023:0] header_aligned;
    always @* begin
        case (build_header_length)
            7'd54:   header_aligned = header_computed << (74*8);    // 对齐 128 B
            7'd58:   header_aligned = header_computed << (70*8);    // 对齐 128 B
            7'd62:   header_aligned = header_computed << (66*8);    // UD（DETH 8 B）：(128-62)*8
            7'd66:   header_aligned = header_computed << (62*8);    // UD_IMM（DETH 8 + Imm 4）：(128-66)*8
            7'd70:   header_aligned = header_computed << (58*8);    // 对齐 128 B
            default: header_aligned = header_computed << (54*8);    // 74 B 头（CNP / READ RESP）
        endcase
    end

    // ------------------------------------------------------------ skip_align + 帧信息 FIFO
    wire        align_meta_ready, align_in_ready;
    // B6461：被代际淘汰的重传任务不进 skip_align（不进 meta、也不送首拍），只把 FIFO 弹掉。
    wire        align_meta_valid = (build_state == BUILD_PREP) && build_job_valid && !build_job_stale;
    wire        align_in_valid = ((build_state == BUILD_PREP) && build_job_valid && !build_job_stale) ||
                                 ((build_state == BUILD_PAYLOAD) && dma_read_valid);
    wire [1023:0] read_byte_mask;
    genvar byte_lane;
    generate
        for (byte_lane = 0; byte_lane < 128; byte_lane = byte_lane + 1) begin : gen_read_mask
            assign read_byte_mask[byte_lane*8 +: 8] = {8{dma_read_keep[byte_lane]}};
        end
    endgenerate
    // PREP 拍把头部的唯一一拍与元数据同拍送出；payload 拍送 payload。
    wire [1023:0] align_in_data = (build_state == BUILD_PREP) ? header_aligned :
                                 (dma_read_data & read_byte_mask);       // 末拍无效字节清零（作 pad_count）
    // PREP 拍的 last：无 payload 时这一拍就是整帧的末拍。
    // 必须用 build_job（在途 FIFO 输出）而不是 job——job 在 PREP 拍还是上一包的值。
    wire        align_in_last  = (build_state == BUILD_PREP) ? (build_job_head.payload_length == 13'd0) :
                                 (build_state == BUILD_PAYLOAD) ? dma_read_last : 1'b0;
    assign dma_read_ready = ((build_state == BUILD_PAYLOAD) && align_in_ready) ||
                            (build_state == BUILD_DROP);

    wire [2:0] align_debug_state;
    // B6502：skip 的取值范围是**有限**的（header_length 只有 54/58/62/66/70/74 → skip ∈ 54..74），
    // 所以把移位窗口收窄到 [54, 74]：常数 54 B 变成纯连线的位选，桶形移位从 7 位降到 5 位、
    // 操作数从 2048 位降到 1192 位。语义与全窗口逐位等价，见 roce_skip_align.sv 文件头。
    // G0.4 残余（B6501 core −0.320 ns 的 4 条最差路径）的落地改动之一。
    roce_skip_align #(
        .DW(1024), .SKIP_BASE(54), .SKIP_RANGE(21)
    ) u_skip_align (
        .clk(clk), .rst(rst),
        .debug_state(align_debug_state),
        .meta_valid(align_meta_valid), .meta_ready(align_meta_ready), .meta_skip(header_skip), .meta_length(frame_length),
        .in_valid(align_in_valid), .in_ready(align_in_ready), .in_data(align_in_data), .in_last(align_in_last),
        .out_valid(frame_valid), .out_ready(frame_ready), .out_data(frame_data), .out_keep(frame_keep), .out_last(frame_last)
    );

    // 帧信息：元数据被接收时入队，该帧的末拍被输出端取走时出队。
    // 不能用单个寄存器：skip_align 允许下一帧的元数据与上一帧的末拍冲刷同拍（甚至更早），
    // 单个寄存器会在上一帧末拍还在输出时就被下一帧覆盖。帧是严格顺序的，且输出停顿时
    // skip_align 不会再收新元数据（meta_ready 依赖 can_advance），所以队列里最多压 1-2 项，
    // 深度 4 有足够余量。
    // 末拍有效字节数：两者都是 **mod 128** 的值（0 表示 128），与 512 位版的 mod 64 同理。
    // 必须是 [6:0] 而不是 [7:0]：mod 256 会让 182 这样的帧长也算成 182，而下游按
    // "<= 124 则末拍装得下 ICRC" 判断，就会凭空多出一拍（B6386 首轮仿真踩到）。
    wire [12:0] frame_length_with_icrc = frame_length + 13'd4;
    reg  [6:0]  info_last_bytes [0:3];
    reg  [6:0]  info_last_beat_bytes [0:3];
    reg  [1:0]  info_head, info_tail;
    wire        info_push = align_meta_valid && align_meta_ready;
    wire        info_pop  = frame_valid && frame_ready && frame_last;
    always @(posedge clk) begin
        if (rst) begin
            info_head <= 2'd0;
            info_tail <= 2'd0;
        end else begin
            if (info_push) begin
                info_last_bytes[info_tail]      <= frame_length_with_icrc[6:0];
                info_last_beat_bytes[info_tail] <= frame_length[6:0];
                info_tail <= info_tail + 2'd1;
            end
            if (info_pop) info_head <= info_head + 2'd1;
        end
    end
    assign frame_last_bytes  = info_last_bytes[info_head];
    assign frame_last_beat_bytes = info_last_beat_bytes[info_head];

    // ------------------------------------------------------------ B 级状态机
    // 在途 FIFO 只在 PREP 拍、且 skip_align 真的能同时收下元数据和首拍时才弹出任务
    // （否则任务会从 FIFO 里消失，而元数据还没送出去）。
    wire        prep_go = (build_state == BUILD_PREP) && build_job_valid && !build_job_stale &&
                          align_meta_ready && align_in_ready;
    // 丢弃：这一包根本不进 skip_align，所以不受它的就绪约束，一拍弹掉。
    wire        drop_go = (build_state == BUILD_PREP) && build_job_valid && build_job_stale;
    assign build_job_ready = prep_go || drop_go;
    always @(posedge clk) begin
        event_tx_packet <= frame_valid && frame_ready && frame_last;
        if (rst) begin
            build_state <= BUILD_PREP;
        end else case (build_state)
            BUILD_PREP: if (prep_go) begin
                        job  <= build_job_head;
                        // 1024 下头部恒为单拍，PREP 拍就送完了整个头部，直接进 payload。
                        // 必须用 build_job_head 而不是 job：job 在这一拍还是上一包的值。
                        build_state <= (build_job_head.payload_length == 13'd0) ? BUILD_PREP : BUILD_PAYLOAD;
                    end else if (drop_go) begin
                        // 被代际淘汰：无 payload 的直接回 PREP；有 payload 的转到 DROP 把读数据收干净。
                        // `job` 不锁存——DROP 只按 dma_read_last 收拍，不读任务字段。
                        build_state <= (build_job_head.payload_length == 13'd0) ? BUILD_PREP : BUILD_DROP;
                    end
            BUILD_PAYLOAD:  if (dma_read_valid && align_in_ready && dma_read_last) build_state <= BUILD_PREP;
            BUILD_DROP:     if (dma_read_valid && dma_read_ready && dma_read_last) build_state <= BUILD_PREP;
            default: build_state <= BUILD_PREP;
        endcase
    end
    // debug_state 的位宽与 CSR 0x056C 的布局是**固定契约**（[9:5] inflight / [4:2] skip_align /
    // [1:0] build_state），深度 32 后 inflight_used 是 6 位，直接拼会让 debug_state 变成 11 位、
    // roce_top 的 10 位连线失配。这里**饱和到 5 位**：深度 ≥32 时读全 1（即「已满」），
    // 与原来 depth 16 读 16 的语义一致，CSR 位宽和现有解析工具都不用改。
    // B6461 起 build_state 多了编码 2 = BUILD_DROP（在丢一个带 payload 的旧重传），
    // deploy/yuancli 的译码表还没加这一项（2 会显示成原来的占位名），不影响其余读数。
    wire [4:0] inflight_used_sat = inflight_used[5] ? 5'h1F : inflight_used[4:0];
    assign debug_state = {inflight_used_sat, align_debug_state, build_state};
endmodule
`default_nettype wire
