// roce_tx.sv
// TX 组包：2 个任务源（0 响应方 ACK/READ RESP，1 请求方）按包轮询 ->
//  A 级：有 payload 的任务先发 DMA 读，再进在途 FIFO（读与组包流水，掩盖 PCIe 读延迟）；
//  B 级：查 QPC，组 Eth/IPv4/UDP/BTH/扩展头（含 IP 校验和），头部右对齐放进 128 B 两拍，
//        与 payload（尾部 pad_count 补 0）一起送 roce_skip_align 去掉头前填充，输出连续以太网帧
//        （不含 ICRC）。frame_last_bytes = (帧长 + 4) mod 128（加上 ICRC 后末拍有效字节，供 MAC 侧）。
// 头长只有 54/58/70/74 四种（skip = 74/70/58/54，mod 64 不落在 1..3，冲刷最多一拍）。
//
// 每包时序（1024 bit，1 KB 包 = 9 拍）：
//   BUILD_PREP          1 拍：取任务 + 查 QPC + 组头 + 算 IP 校验和 + 右对齐到 128 B + 给
//                            skip_align 元数据，并把头部（恒单拍）同拍送出
//   BUILD_PAYLOAD       8 拍：每拍 128 B payload
// 组包所需的全部组合逻辑都吃 build_job_head（在途 FIFO 的输出，PREP 拍有效）与
// qpc[build_job_head.qp_index]，所以 PREP 一拍就能出完整头部。
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
    input  wire  [QP_NUM*512-1:0]  qpc,
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
    output reg                     event_tx_packet,
    // DCQCN（阶段 3）：**准入**事件——比 event_tx_packet（帧尾）更适合做信用/字节统计，
    // 因为它是「这个包被允许上线」的那一拍，且 job 的值稳定（event_tx_packet 那拍 job 可能
    // 已被下一包的 PREP 覆盖）。
    output reg                     event_tx_admit,
    output reg  [3:0]              event_tx_admit_qp,
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
    // 在途 FIFO 深度（B6413：8 → 16）。
    //
    // 依据（§36.9 / §37）：1 MB 读响应的包率不随 core_clk 变化（100 MHz 8.88 Mpps、
    // 125 MHz 9.53 Mpps），而 8 / 包率 在两个频率下都约等于 840~900 ns，正是 PCIe 读往返；
    // 上板用 0x0578[15:8] 采到未完成 AR 数 p50 = 9、p90 = 10、max = 11，说明每个响应包的
    // 1024 B DMA 读把槽位占满。加深后上限由组包侧的 9 拍/包给出（13.89 Mpps ≈ 113.8 Gb/s）。
    //
    // 选 16 而不是更大：16 个 1024 B 读 = 128 拍，远低于 DMA 侧 read_credit（480），
    // 且 16 × 9 拍 = 144 拍 ≈ 1.15 µs @125 MHz，已能覆盖 860 ns 往返还有余量。
    localparam int INFLIGHT_DEPTH = 16;
    wire      inflight_ready;
    wire [4:0] inflight_used;      // 在途 FIFO 占用（深度 16，$clog2(16)+1 = 5 位）
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
    localparam [1:0] BUILD_PREP = 2'd0, BUILD_PAYLOAD = 2'd1;
    reg  [1:0]    build_state;
    tx_job_t      job;                   // 本包任务（PREP 拍从在途 FIFO 锁存；payload 阶段只用 payload_length）

    function automatic [15:0] swap16(input [15:0] value); swap16 = {value[7:0], value[15:8]}; endfunction
    function automatic [23:0] swap24(input [23:0] value); swap24 = {value[7:0], value[15:8], value[23:16]}; endfunction
    function automatic [31:0] swap32(input [31:0] value); swap32 = {value[7:0], value[15:8], value[23:16], value[31:24]}; endfunction
    function automatic [63:0] swap64(input [63:0] value); swap64 = {swap32(value[31:0]), swap32(value[63:32])}; endfunction

    // 组包输入：在途 FIFO 的输出（PREP 拍有效）与它对应的 QPC。全部是组合值，
    // 所以 PREP 一拍内就能算出完整头部、校验和与右对齐结果。
    tx_job_t      build_job;             // 别名，强调下面这一整段读的是 FIFO 输出
    wire [511:0]  build_qpc;
    assign build_job = build_job_head;
    assign build_qpc = qpc[build_job_head.qp_index*512 +: 512];

    wire       header_has_reth = op_has_reth(build_job.opcode);
    wire       header_has_aeth = op_has_aeth(build_job.opcode);
    wire       header_has_immediate  = op_has_imm(build_job.opcode);
    // CNP：BTH 后跟 16 B 保留（不是 RETH），所以头长与 READ RESP 一样是 70 B，但内容全 0。
    wire       header_is_cnp   = op_is_cnp(build_job.opcode);
    wire [6:0] extension_length    = (header_has_reth ? 7'd16 : 7'd0) + (header_has_aeth ? 7'd4 : 7'd0) +
                                     (header_has_immediate ? 7'd4 : 7'd0) + (header_is_cnp ? 7'd16 : 7'd0);
    wire [1:0] job_pad_count   = 2'(-build_job.payload_length);
    // IP 总长 = 20 + 8 + 12 + extension_length + payload + pad_count + 4(ICRC)
    wire [15:0] computed_ip_total_length = 16'd44 + {9'd0, extension_length} + {3'd0, build_job.payload_length} + {14'd0, job_pad_count};

    // ---- 每 QP 预算的包头静态部分（B6433）
    // B6432 STA：全片最差的 core 路径是 PREP 拍「在途 FIFO 出口 → 512 位 QPC 16 选 1 → 9 操作数 IP 校验和
    // 加法 → 两级折叠 → 包头 → 对齐移位」（每 lane 数千条，−0.20~−0.265 ns）；阶段 2 又往这条链上加了
    // tos_valid 选择与 CNP 的扩展长度。校验和里与包无关的部分（0x4000 标志、TTL/协议、源/目的 IP）只取决于
    // QPC 与本地 IP，二者在 QP 存活期间是准静态的，所以按 QP 预先加好、寄存：PREP 拍只剩「选 1 个 20 位
    // 预算和 + TOS 字 + IP 总长」三操作数加法。QPC 改写后 1 拍生效（QP 建链到发第一个包之间隔着 PCIe 门铃，
    // 远大于 1 拍）。TOS 也按 QP 寄存一份，PREP 拍不再从 512 位 QPC 里选。
    // 每个 QP 一个生成块、各自的寄存器，再打平成向量：避免同一非打平数组被多个 always 块写
    // （Quartus 会按多驱动报错，见 roce_pfc.sv gen_prio_occ 的注释）。
    wire [QP_NUM*20-1:0] qp_csum_base_flat;
    wire [QP_NUM*8-1:0]  qp_tos_flat;
    genvar gq;
    generate
        for (gq = 0; gq < QP_NUM; gq = gq + 1) begin : gen_qp_hdr
            wire [511:0] qc  = qpc[gq*512 +: 512];
            wire [31:0]  dip = qpc_dip(qc);
            wire [7:0]   ttl = qpc_ttl(qc);
            reg  [19:0]  base_q;
            reg  [7:0]   tos_q;
            always @(posedge clk) begin
                tos_q  <= qpc_tos(qc);
                base_q <= 20'h04000 + {4'd0, ttl, 8'h11} +
                          {4'd0, local_ip[7:0], local_ip[15:8]} + {4'd0, local_ip[23:16], local_ip[31:24]} +
                          {4'd0, dip[7:0], dip[15:8]} + {4'd0, dip[23:16], dip[31:24]};
            end
            assign qp_csum_base_flat[gq*20 +: 20] = base_q;
            assign qp_tos_flat[gq*8 +: 8]         = tos_q;
        end
    endgenerate

    // TOS：CNP 用独立 DSCP（NVIDIA cnp_dscp 默认 48，且 ECN 必须为 00，否则 CNP 自己又被标 CE），
    // 其它包沿用 QPC 的 TOS。tos_valid 是任务自带的覆盖位，只有 CNP 置 1。
    wire [7:0]  header_tos = build_job.tos_valid ? build_job.tos : qp_tos_flat[build_job_head.qp_index*8 +: 8];

    // IPv4 头校验和（大端 16 bit 字求和，校验和字段为 0、id 为 0）。当拍算完当拍用，不再寄存。
    // 与 B6432 及以前的 9 操作数写法逐位等价：加法结合律，20 位不溢出（9 × 0xFFFF < 2^20）。
    wire [19:0] computed_checksum_sum = qp_csum_base_flat[build_job_head.qp_index*20 +: 20] +
                        {4'd0, 8'h45, header_tos} + {4'd0, computed_ip_total_length};
    wire [16:0] checksum_fold1 = {1'b0, computed_checksum_sum[15:0]} + {13'd0, computed_checksum_sum[19:16]};
    wire [15:0] checksum_fold2 = checksum_fold1[15:0] + {15'd0, checksum_fold1[16]};
    wire [15:0] computed_checksum = swap16(~checksum_fold2);

    reg [1023:0] header_computed;
    always @* begin
        header_computed = '0;
        header_computed[0   +: 48] = qpc_dmac(build_qpc);
        header_computed[48  +: 48] = local_mac;
        header_computed[96  +: 16] = 16'h0008;                 // EtherType 0x0800
        header_computed[112 +: 8]  = 8'h45;
        header_computed[120 +: 8]  = header_tos;
        header_computed[128 +: 16] = swap16(computed_ip_total_length);
        header_computed[160 +: 16] = 16'h0040;                 // DF
        header_computed[176 +: 8]  = qpc_ttl(build_qpc);
        header_computed[184 +: 8]  = 8'h11;
        header_computed[192 +: 16] = computed_checksum;        // IP 校验和（当拍算完当拍写，不再单独占一拍）
        header_computed[208 +: 32] = local_ip;
        header_computed[240 +: 32] = qpc_dip(build_qpc);
        header_computed[272 +: 16] = swap16(qpc_sport(build_qpc));
        header_computed[288 +: 16] = 16'hB712;                 // 4791
        header_computed[304 +: 16] = swap16(computed_ip_total_length - 16'd20);
        header_computed[336 +: 8]  = build_job.opcode;
        // BTH byte1 = {SE, M, PadCnt, TVer}。M 只有 CNP 以外的 opcode 才置 1（CNP 的 M 必须为 0）。
        header_computed[344 +: 8]  = {build_job.solicited, !header_is_cnp, job_pad_count, 4'd0};
        header_computed[352 +: 16] = 16'hFFFF;                 // P_Key
        header_computed[376 +: 24] = swap24(qpc_dqpn(build_qpc));
        header_computed[400 +: 8]  = {build_job.ack_request, 7'd0};
        header_computed[408 +: 24] = swap24(build_job.psn);
        if (header_has_reth) begin
            header_computed[432 +: 64] = swap64(build_job.reth_virtual_address);
            header_computed[496 +: 32] = swap32(build_job.reth_rkey);
            header_computed[528 +: 32] = swap32(build_job.reth_length);
        end
        if (header_has_aeth) header_computed[432 +: 32] = {swap24(build_job.aeth_msn), build_job.aeth_syndrome};
        if (header_has_immediate)  begin
            if (header_has_reth) header_computed[560 +: 32] = build_job.immediate;
            else        header_computed[432 +: 32] = build_job.immediate;
        end
        // CNP：BTH byte4 = {FECN, BECN, 6'b0}，BECN 置 1（对端据此知道这是拥塞通知）；
        // 16 B 保留字段全 0（header_computed 复位即 0），PSN / AckReq 也都是 0。
        if (header_is_cnp) begin
            header_computed[368 +: 8]  = {cnp_bth_flags[1], cnp_bth_flags[0], 6'b0};  // B6434：{FECN,BECN} 可配
            header_computed[408 +: 24] = 24'd0;          // PSN
            header_computed[400 +: 8]  = 8'd0;           // AckReq=0
        end
    end

    wire [6:0]    build_header_length = 7'd54 + extension_length;
    wire [12:0]   frame_length = 13'd54 + {6'd0, extension_length} + build_job.payload_length + {11'd0, job_pad_count};

    // 1024 bit（B6386）：一拍 128 B，最长头 74 B 也装得进，所有包都是**单拍头**，
    // BUILD_HEADER_BEAT1 状态整个删掉。skip 恒为 128 - header_length。
    //
    // 历史（512 bit，§23）：那时头长 <= 64 的对齐到 64 B 以避开 skip_align 的
    // first_useful_beat=1，否则第 0 拍整拍被丢弃。1024 下 skip < 128 = BEAT_BYTES，
    // first_useful_beat 恒 0，这个区分不再需要，统一对齐到 128 B。
    wire [6:0]    header_skip = 7'd128 - build_header_length;

    // 头部右对齐到 128 B。常量移位，纯连线 + 4:1 选择。
    reg [1023:0] header_aligned;
    always @* begin
        case (build_header_length)
            7'd54:   header_aligned = header_computed << (74*8);    // 对齐 128 B
            7'd58:   header_aligned = header_computed << (70*8);    // 对齐 128 B
            7'd70:   header_aligned = header_computed << (58*8);    // 对齐 128 B
            default: header_aligned = header_computed << (54*8);    // 74 B 头
        endcase
    end

    // ------------------------------------------------------------ skip_align + 帧信息 FIFO
    wire        align_meta_ready, align_in_ready;
    wire        align_meta_valid = (build_state == BUILD_PREP) && build_job_valid;
    wire        align_in_valid = ((build_state == BUILD_PREP) && build_job_valid) ||
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
    assign dma_read_ready = (build_state == BUILD_PAYLOAD) && align_in_ready;

    wire [2:0] align_debug_state;
    roce_skip_align #(.DW(1024)) u_skip_align (
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
    wire        prep_go = (build_state == BUILD_PREP) && build_job_valid &&
                          align_meta_ready && align_in_ready;
    assign build_job_ready = prep_go;
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
                    end
            BUILD_PAYLOAD:  if (dma_read_valid && align_in_ready && dma_read_last) build_state <= BUILD_PREP;
            default: build_state <= BUILD_PREP;
        endcase
    end
    assign debug_state = {inflight_used[4], inflight_used[3:0], align_debug_state, build_state};
endmodule
`default_nettype wire
