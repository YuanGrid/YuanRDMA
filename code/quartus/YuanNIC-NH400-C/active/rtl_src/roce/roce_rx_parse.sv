// roce_rx_parse.sv
// 解析 roce_rx_front 送来的 RoCEv2 帧（IPv4 无选项、无 VLAN）：
//  - 头部字段 -> h_*（内部 16 深 FIFO，每帧一个）；
//  - payload（去掉头、pad_count、ICRC）-> o_*，从第 0 字节对齐，pay_len == 0 的帧没有 payload。
//
// 零空转（B6381）：每帧的输入拍持续按 1 拍/周期消费，帧与帧之间不再有空转拍。
//
// 1024 bit（B6386）：一拍 128 B，最长头 74 B 也落在第 0 拍内，所以不再需要 beat0 缓存
// 来凑跨拍的 RETH/ImmDt 字段（512 位时代这些字段在字节 64..73，跨了第 0/1 拍）。
// 状态机因此塌缩成两个状态：IDLE（收第 0 拍、装元数据、送首拍、同拍写头）与 STREAM
// （其余拍直通）。头部 FIFO 的写入条件也从「beat1 那拍」提前到第 0 拍，省掉一整拍。
//
// 与 B6378 的区别（那一版在这里失败过，别再走回头路）：B6378 只是把 S_PUSH_FIRST /
// S_REPLAY1 的 in_ready 拉高、把 beat 囤进 skid，状态机拍数没变（仍是 N+2 拍），
// 只能挡上游反压，省不了拍数。真正的零空转必须让首拍在收进来的同一拍就流出去。
//
// DW（1024 或 2048）：输入/payload 输出位宽。2048 时一拍 256 B，头部仍在第 0 拍内，
// 字段偏移与 1024 完全相同，状态机与头部 FIFO 不变，只有 skip_align 的数据宽度跟着变；
// 每拍仍消费一个输入拍。payload 第 0 字节在首个输出拍 bit[7:0]，out_keep 从 bit 0 起连续。
`default_nettype none
`timescale 1ns/1ps
module roce_rx_parse
    import roce_pkg::*;
#(
    parameter int DW = 1024                 // 输入帧与 payload 输出的位宽：1024 或 2048
)(
    input  wire              clk,
    input  wire              rst,
    input  wire              in_valid,
    output wire              in_ready,
    input  wire  [DW-1:0]    in_data,
    input  wire  [DW/8-1:0]  in_keep,
    input  wire              in_last,
    // 头部
    output wire              rx_header_valid,
    input  wire              rx_header_ready,
    output rx_hdr_t          rx_header,
    // payload
    output wire              out_valid,
    input  wire              out_ready,
    output wire  [DW-1:0]    out_data,
    output wire  [DW/8-1:0]  out_keep,
    output wire              out_last,
    // 调试：[2:0] 当前 state，见 roce_debug.sv 0x0568
    output wire  [2:0]       debug_state
);
    // 状态编码（0x0568[2:0]）：0=IDLE（帧间，收第 0 拍、装元数据、写头、送首拍）
    //                       2=STREAM（第 1 拍起直通到帧尾）
    localparam [1:0] S_IDLE = 2'd0, S_STREAM = 2'd2;
    reg  [1:0]   state;

    initial begin
        if (DW != 1024 && DW != 2048)
            $fatal(1, "roce_rx_parse: DW=%0d，只支持 1024 或 2048", DW);
    end

    // 解析窗口就是当拍输入：1024/2048 位下 74 B 头全在第 0 拍。
    wire [DW-1:0] header_bytes = in_data;
    function automatic [7:0] header_byte(input integer offset);
        header_byte = header_bytes[offset*8 +: 8];
    endfunction
    function automatic [15:0] read_be16(input integer offset);
        read_be16 = {header_bytes[offset*8 +: 8], header_bytes[(offset+1)*8 +: 8]};
    endfunction
    function automatic [23:0] read_be24(input integer offset);
        read_be24 = {header_bytes[offset*8 +: 8], header_bytes[(offset+1)*8 +: 8], header_bytes[(offset+2)*8 +: 8]};
    endfunction
    function automatic [31:0] read_be32(input integer offset);
        read_be32 = {read_be16(offset), read_be16(offset+2)};
    endfunction
    function automatic [63:0] read_be64(input integer offset);
        read_be64 = {read_be32(offset), read_be32(offset+4)};
    endfunction

    // ---------------- 组合解析（在收拍的那一拍直接算）
    wire [7:0]  opcode      = header_byte(42);
    wire        opcode_has_reth = (opcode == OP_WRITE_FIRST) || (opcode == OP_WRITE_ONLY) ||
                          (opcode == OP_WRITE_ONLY_IMM) || (opcode == OP_READ_REQ);
    wire        opcode_has_aeth = (opcode == OP_READ_RESP_FIRST) || (opcode == OP_READ_RESP_LAST) ||
                          (opcode == OP_READ_RESP_ONLY) || (opcode == OP_ACK);
    wire        opcode_has_immediate  = (opcode == OP_SEND_LAST_IMM) || (opcode == OP_SEND_ONLY_IMM) ||
                          (opcode == OP_WRITE_LAST_IMM) || (opcode == OP_WRITE_ONLY_IMM) ||
                          (opcode == OP_SEND_ONLY_UD_IMM);
    // CNP（0x81）不在 0x00..0x11 区间里，单独放行：它是 4 B BTH + **16 B 保留**（不是 RETH），
    // 所以 extension_length 要按 16 算，payload 恒 0。阶段 3 的 RP 逻辑从这里消费它。
    wire        opcode_is_cnp      = op_is_cnp(opcode);
    // UD（0x64/0x65）：BTH 后跟 DETH 8 B。**RoCEv2 线上没有 40 B GRH**——GRH 是 RoCEv1/IB
    // 的线格式，v2 里 GRH 由接收侧从 IP 头合成后写进接收缓冲（IBTA §9.8.5 / Annex A17），
    // 所以这里的 extension_length 只加 DETH，不加 40。0x65 另外带 4 B ImmDt（由 op_has_imm 计入）。
    wire        opcode_is_ud       = op_is_ud(opcode);
    wire        opcode_supported   = (opcode <= OP_ACK) || opcode_is_cnp || opcode_is_ud;
    wire [6:0]  extension_length     = (opcode_has_reth ? 7'd16 : 7'd0) + (opcode_has_aeth ? 7'd4 : 7'd0) +
                                        (opcode_has_immediate ? 7'd4 : 7'd0) + (opcode_is_cnp ? 7'd16 : 7'd0) +
                                        (opcode_is_ud ? 7'd8 : 7'd0);
    // RETH 在 BTH 后（54）；AETH 在 BTH 后（54）；ImmDt 在 RETH 后（70）、UD 的 DETH 后（62）或 BTH 后（54）
    wire [6:0]  immediate_offset = opcode_has_reth ? 7'd70 : (opcode_is_ud ? 7'd62 : 7'd54);
    wire [15:0] ip_total_length  = read_be16(16);
    wire [15:0] udp_length = read_be16(38);
    wire [7:0]  byte_tos   = header_byte(15);
    wire [7:0]  byte_bth_flags    = header_byte(43);     // SE M PadCnt TVer
    wire [7:0]  byte_bth_fecn  = header_byte(46);
    wire [7:0]  byte_bth_ack_request   = header_byte(50);
    wire [1:0]  pad_count     = byte_bth_flags[5:4];
    wire [16:0] overhead_length     = 17'd8 + 17'd12 + {10'd0, extension_length} + {15'd0, pad_count} + 17'd4;   // UDP+BTH+extension_length+pad_count+ICRC
    wire [16:0] computed_payload_length    = {1'b0, udp_length} - overhead_length;
    wire [23:0] dest_qpn    = read_be24(47);
    wire        length_invalid = ({1'b0, udp_length} < overhead_length) || (computed_payload_length > 17'd4096) ||
                          (ip_total_length != udp_length + 16'd20);

    rx_hdr_t    next_header;
    always @* begin
        next_header           = '0;
        next_header.opcode    = opcode;
        next_header.solicited        = byte_bth_flags[7];
        next_header.ack_request    = byte_bth_ack_request[7];
        next_header.becn      = byte_bth_fecn[6];
        next_header.ecn_congestion        = (byte_tos[1:0] == 2'b11);
        next_header.dest_qpn      = dest_qpn;
        // QPN_BASE 是 QP_NUM 的整数倍时，取低 QP_W 位就等于 dest_qpn-QPN_BASE（扩 QP 时保持这个前提）
        next_header.qp_index    = dest_qpn[QP_W-1:0];
        next_header.qp_valid     = (dest_qpn >= 24'(QPN_BASE)) && (dest_qpn < 24'(QPN_BASE + QP_NUM));
        next_header.psn       = read_be24(51);
        next_header.has_reth  = opcode_has_reth;
        next_header.reth_virtual_address   = read_be64(54);
        next_header.reth_rkey = read_be32(62);
        next_header.reth_length  = read_be32(66);
        next_header.has_aeth  = opcode_has_aeth;
        next_header.aeth_syndrome  = header_byte(54);
        next_header.aeth_msn  = read_be24(55);
        next_header.has_immediate   = opcode_has_immediate;
        next_header.immediate       = header_bytes[immediate_offset*8 +: 32];
        // DETH（UD，IBTA §9.8.5）：Q_Key 4 B（字节 54..57）+ 1 B 保留（58）+ 源 QPN 3 B（59..61）。
        // RC 包恒为 0——58..61 在 WRITE 里是 RETH 的 rkey 尾部、在 SEND 里是 payload 开头，
        // 所以必须用 opcode_is_ud 门控，不能无条件取。
        // 2026-11-27 修：原来读 58..60，ConnectX 的 QP 0x0011df 报成 0x000011（eth0 抓包 + gdb 实取）。
        next_header.has_deth        = opcode_is_ud;
        next_header.deth_qkey       = opcode_is_ud ? read_be32(54) : 32'd0;
        next_header.deth_src_qp     = opcode_is_ud ? read_be24(59) : 24'd0;
        // GRH 合成需要源 IPv4（IBTA §9.8.5：Source GID = ::ffff:<src_ip>）。
        // RoCEv2 线上没有 40 B GRH，这里只取 IPv4 头里的源 IP（字节 26..29，主机序）。
        next_header.src_ip          = opcode_is_ud ? read_be32(26) : 32'd0;
        next_header.ip_ttl          = opcode_is_ud ? header_byte(22) : 8'd0;
        next_header.ip_tos          = opcode_is_ud ? byte_tos : 8'd0;
        // 头部报出去的 payload_length 必须与实际送出的拍数一致：bad 帧（opcode 不支持 /
        // 长度不自洽）的 payload 全部丢弃（has_payload=0），所以这里必须报 0。
        // 2026-11-12 修：原来只按 length_invalid 清零，opcode 不支持时仍报真实长度，
        // 下游 roce_resp 的 MAIN_DRAIN 等一个永远不来的 payload → 卡死并把后续帧吞掉
        // （QP1/GSI 的 UD SEND 0x64 就踩这条，见 test/sim/roce_rx/test_qp1_stall.py）。
        next_header.payload_length   = (length_invalid || !opcode_supported) ? 13'd0
                                                                             : computed_payload_length[12:0];
        next_header.bad       = length_invalid || !opcode_supported;
    end

    // ---------------- 头部 FIFO
    wire header_fifo_ready;
    wire align_meta_ready, align_in_ready;
    // bad 帧（opcode 不支持 / 长度不自洽）一律按零 payload 处理：payload 全部丢弃，只把头部交上去。
    // 剩下的拍由 STREAM 状态照常消费（skip_align 的 bytes_remaining==0 时不出数，然后 frame_close）。
    wire has_payload    = !next_header.bad && (next_header.payload_length != 13'd0);
    wire [12:0] meta_length  = has_payload ? next_header.payload_length : 13'd0;
    wire [6:0]  header_length = 7'd54 + extension_length;

    // 元数据与首拍同拍：IDLE 那拍既装 meta 又把第 0 拍喂进去（skip_align 的 meta_load_first）。
    // header_ok 必须同时门控「能不能收」和「喂不喂给 skip_align」：只在 in_ready 上挡是不够的——
    // skip_align 的 in_ready 与 header FIFO 无关，若此时 align_in_valid 仍为 1，这一拍会被它
    // 静默吃掉，而状态机因为 in_ready=0 什么都没记。两头口径必须完全一致。
    wire        header_ok = (state == S_STREAM) || header_fifo_ready;
    wire        align_meta_valid = (state == S_IDLE) && in_valid && header_ok;
    // 数据始终是活的前端流：IDLE 是第 0 拍，STREAM 是其余。
    wire        align_in_valid = in_valid && header_ok;
    wire [DW-1:0] align_in_data = in_data;
    wire        align_in_last  = in_last;

    // 头 FIFO 没位置就不收第 0 拍（STREAM 拍不写头，不受它限制）。
    // 这条同时保证「收下第 0 拍时当拍一定有位置写头」：FIFO 只有本模块写。
    assign in_ready = align_in_ready && header_ok;

    // 1024 下头部全在第 0 拍，所以 IDLE 拍当场就能写头，不必等 beat1。
    wire push_header = (state == S_IDLE) && in_valid && in_ready;

    axis_async_fifo #(
        .DEPTH(16), .DATA_WIDTH($bits(rx_hdr_t)), .KEEP_ENABLE(0), .LAST_ENABLE(0), .USER_ENABLE(0)
    ) u_header_fifo (
        .s_clk(clk), .s_rst(rst),
        .s_axis_tdata(next_header), .s_axis_tkeep('0), .s_axis_tvalid(push_header),
        .s_axis_tready(header_fifo_ready), .s_axis_tlast(1'b1), .s_axis_tid(8'd0), .s_axis_tdest(8'd0),
        .s_axis_tuser(1'b0),
        .m_clk(clk), .m_rst(rst),
        .m_axis_tdata(rx_header), .m_axis_tkeep(), .m_axis_tvalid(rx_header_valid), .m_axis_tready(rx_header_ready),
        .m_axis_tlast(), .m_axis_tid(), .m_axis_tdest(), .m_axis_tuser(),
        .s_pause_req(1'b0), .s_pause_ack(), .m_pause_req(1'b0), .m_pause_ack(),
        .s_status_depth(), .s_status_depth_commit(), .s_status_overflow(),
        .s_status_bad_frame(), .s_status_good_frame(),
        .m_status_depth(), .m_status_depth_commit(), .m_status_overflow(),
        .m_status_bad_frame(), .m_status_good_frame()
    );

    // ---------------- skip_align
    // 移位窗口：skip = header_length = 54 + extension_length，extension_length 只能是
    // 0/4/8/12/16/20（RETH 16、AETH 4、ImmDt 4、CNP 保留 16、DETH 8 的合法组合，最大是
    // WRITE_ONLY_IMM 的 RETH+ImmDt = 20；不支持的 opcode 一律 0），所以 skip ∈ [54, 74]，
    // 与 TX 实例同一个窗口。窗口内输出与全窗口移位**逐位相同**（含 keep 之外的字节）：
    // 输出字节 i 都取拼接向量的字节 skip+i。收益是移位量 7/8 位 → 5 位、操作数 2*DW → DW+168 位，
    // DW=2048 时全窗口要 8 位移位 × 4096 位操作数，面积与级数都不可接受。
    // 将来加新的扩展头（如 AtomicETH 28 B）必须放大 SKIP_RANGE，下面的仿真断言会先报出来。
    localparam int ALIGN_SKIP_W = (DW >= 2048) ? $clog2(DW / 8) : 7;
    localparam int RX_SKIP_BASE = 54, RX_SKIP_RANGE = 21;
    wire [ALIGN_SKIP_W-1:0] align_skip = ALIGN_SKIP_W'(header_length);
    // synopsys translate_off
    always @(posedge clk) begin
        if (!rst && align_meta_valid && align_meta_ready &&
            (header_length < 7'(RX_SKIP_BASE) || header_length >= 7'(RX_SKIP_BASE + RX_SKIP_RANGE)))
            $error("roce_rx_parse: header_length=%0d 超出 skip_align 窗口 [%0d, %0d)",
                   header_length, RX_SKIP_BASE, RX_SKIP_BASE + RX_SKIP_RANGE);
    end
    // synopsys translate_on
    roce_skip_align #(.DW(DW), .SKIP_BASE(RX_SKIP_BASE), .SKIP_RANGE(RX_SKIP_RANGE)) u_skip_align (
        .clk(clk), .rst(rst),
        .meta_valid(align_meta_valid), .meta_ready(align_meta_ready), .meta_skip(align_skip), .meta_length(meta_length),
        .in_valid(align_in_valid), .in_ready(align_in_ready), .in_data(align_in_data), .in_last(align_in_last),
        .out_valid(out_valid), .out_ready(out_ready), .out_data(out_data), .out_keep(out_keep), .out_last(out_last),
        .debug_state()      // RX 侧的 skip_align 不观测
    );

    // ---------------- 状态机
    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
        end else begin
            case (state)
                // 收第 0 拍：同一拍已装 meta、写头、并把它当首拍送出去；帧到此为止就直接回 IDLE。
                S_IDLE:  if (in_valid && in_ready)
                            state <= in_last ? S_IDLE : S_STREAM;
                // 第 1 拍起直通，直到帧尾那一拍——帧尾消费完，skip_align 会进入 flush/close，
                // 下一拍 IDLE 收的第 0 拍正好可以与它同拍装载，不空转。
                S_STREAM: if (in_valid && in_ready && in_last)
                            state <= S_IDLE;
                default: state <= S_IDLE;
            endcase
        end
    end
    assign debug_state = {1'b0, state};
endmodule
`default_nettype wire
