// roce_req.sv
// 请求方（本端 SQ）：
//  - 取指：SQ doorbell -> 按 QP 轮询从主机 SQ 环读 64 B WQE 到片上环（每 QP 32 槽）；
//  - 发送：按 PMTU 切分 WRITE/SEND，READ 发一个请求包；lkey 翻译后交 roce_tx；
//  - 响应：ACK/NAK/READ RESP 按 PSN 依次退休 WQE（写 CQE），READ RESP 数据写回本地 MR；
//  - 重传：NAK-SEQ / 超时 / 丢失 READ 时 go-back-N（从队头 WQE 内的 PSN 重发，READ 从第一个缺失的响应续读）；
//    RNR NAK 等 RNR 定时器到期后重发。重试次数耗尽 -> 错误 CQE，QP 置 ERR。
// 状态划分：取指相关（pi/fi/fd）只由取指逻辑写；定时器只由定时逻辑写；其余由主状态机写。
`default_nettype none
`timescale 1ns/1ps
module roce_req
    import roce_pkg::*;
#(
    parameter int CORE_CLOCK_MHZ = 250
)(
    input  wire                    clk,
    input  wire                    rst,
    input  wire  [QP_NUM*512-1:0]  qpc,
    input  wire  [QP_NUM*3-1:0]    qp_state_i,     // QPC 的 [2:0] 单独引出，见 roce_tbl.sv
    input  wire  [QP_NUM-1:0]      qp_state_change,
    output reg   [QP_NUM-1:0]      qp_set_error,
    input  wire                    doorbell_sq_valid,
    input  wire  [31:0]            doorbell_data,
    // PFC：接收侧**生效** pause（core 域已同步），[8]=802.3x 全局，[7:0]=每优先级。
    // 这不是 F-tile 的原始电平：roce_pfc 已经做过 honor 掩码、RX 看门狗与 CTRL2.ANY_ALL，
    // 本模块直接按位用即可（见 roce_pfc.sv 文件头的「收方向」）。
    // 只挡「新 WQE 派发」，已开始的包发完；ACK/NAK/READ RESP 的准入在 roce_engine。
    input  wire  [8:0]             rx_pfc,
    input  wire                    pfc_gate_enable,   // = ~REG_CTRL[2]，复位 1；写 CTRL[2]=1 关门控便于 A/B 对照
    // DCQCN 速率准入（阶段 3）：roce_dcqcn 的每 QP 信用闸门。CTRL.EN=0 时恒全 1（不影响行为）。
    // 只挡「派发新 WQE」，已派发的包发完；与 PFC 准入串联（两者都满足才派发）。
    input  wire  [QP_NUM-1:0]      tx_rate_ready,
    // RX（dispatcher 分配的响应包）
    input  wire                    rx_header_valid,
    output reg                     rx_header_ready,
    input  rx_hdr_t                rx_header,
    input  wire                    rx_payload_valid,
    output wire                    rx_payload_ready,
    input  wire  [1023:0]          rx_payload_data,
    input  wire                    rx_payload_last,
    output reg                     done,
    // 地址翻译
    output wire                    translate_valid,
    input  wire                    translate_ready,
    output reg   [31:0]            translate_key,
    output reg   [63:0]            translate_virtual_address,
    output reg   [12:0]            translate_length,
    output reg   [3:0]             translate_access,
    output wire  [15:0]            translate_protection_domain,
    input  wire                    translate_response,
    input  wire  [63:0]            translate_physical_address0,
    input  wire  [63:0]            translate_physical_page1,
    input  wire                    translate_error,
    // DMA 读（WQE 取指）
    output wire                    dma_read_request_valid,
    input  wire                    dma_read_request_ready,
    output wire  [63:0]            dma_read_request_address,
    output wire  [63:0]            dma_read_request_page1,
    output wire  [12:0]            dma_read_request_length,
    input  wire                    dma_read_valid,
    output wire                    dma_read_ready,
    input  wire  [1023:0]          dma_read_data,
    // DMA 写（READ RESP 数据）
    output reg                     dma_write_request_valid,
    input  wire                    dma_write_request_ready,
    output reg   [63:0]            dma_write_request_address,
    output reg   [63:0]            dma_write_request_page1,
    output reg   [12:0]            dma_write_request_length,
    output wire                    dma_write_valid,
    input  wire                    dma_write_ready,
    output wire  [1023:0]          dma_write_data,
    // CQE
    output reg                     cqe_valid,
    input  wire                    cqe_ready,
    output reg   [3:0]             cqe_cq_index,
    output reg   [127:0]           cqe_data,
    // TX 任务
    output reg                     tx_job_valid,
    input  wire                    tx_job_ready,
    output tx_job_t                tx_job,
    // 计数
    output reg                     event_rx_ack,
    output reg                     event_rx_nak,
    output reg                     event_rx_rnr,
    output reg                     event_retransmit_timeout,
    output reg                     event_retransmit_nak,
    // ECN / CNP（阶段 2）：本 QP 收到一个 CNP（BTH opcode 0x81）。CNP 不是 ACK，
    // 不改 PSN / 不动退休逻辑，只报告给 RP 侧（阶段 3 用它降速）；这里只做计数与拒绝非法 QP。
    output reg                     event_rx_cnp,
    output reg   [QP_NUM-1:0]      event_rx_cnp_qp,     // 收到 CNP 的 QP（one-hot，与 event_rx_cnp 同拍）
    // 调试观测（布局见 roce_debug.sv 地址表 0x0560 / 0x0570）
    //   [19:0]  {local_error, recovering, reads_outstanding[4:0],
    //            2'b00, retry_left[2:0], 1'b0, dispatch_reason[1:0], state[4:0]}
    //           即 state[4:0] dispatch_reason[6:5] retry_left[10:8]
    //            reads_outstanding[17:13] recovering[18] local_error[19]
    //   [23:20] qp_index
    //   [47:24] next_psn
    //   [71:48] unacked_psn
    //   [77:72] ack_counter
    //   [95:78] 保留
    //   [127:96] tx_offset
    output wire  [127:0]           debug_state
);
    localparam int WQE_SLOTS = 32;
    // ------------------------------------------------------------ 主状态机拥有的每 QP 状态
    reg  [15:0] qp_tx_index   [QP_NUM];    // 下一个要发的 WQE（SQ 索引）
    reg  [15:0] qp_unacked_index  [QP_NUM];    // 最老未退休的 WQE
    reg  [23:0] qp_next_psn [QP_NUM];
    reg  [23:0] qp_unacked_psn [QP_NUM];
    reg  [31:0] qp_tx_offset  [QP_NUM];    // qp_tx_index 这个 WQE 已发字节
    reg         qp_tx_started [QP_NUM];    // qp_tx_index 这个 WQE 已发过首包（meta 已写）
    reg  [2:0]  qp_retry_left  [QP_NUM];
    reg  [2:0]  qp_rnr_retry_left  [QP_NUM];
    reg  [4:0]  qp_reads_outstanding  [QP_NUM];    // 在途 READ 数
    reg  [5:0]  qp_ack_counter [QP_NUM];
    reg         qp_local_error [QP_NUM];
    reg         qp_rnr_waiting [QP_NUM];    // 等 RNR 定时器
    reg         qp_recovering  [QP_NUM];    // go-back-N 重发后尚无进展：忽略乱序响应/NAK，靠超时兜底

    // ------------------------------------------------------------ 取指逻辑拥有的状态
    reg  [15:0] qp_sq_producer [QP_NUM];
    reg  [15:0] qp_fetch_issued [QP_NUM];      // 已发出取指
    reg  [15:0] qp_fetch_done [QP_NUM];      // 已取回

    // ------------------------------------------------------------ 片上 WQE 环与 meta
    (* ramstyle = "no_rw_check,m20k" *) reg [1023:0] wqe_ram  [QP_NUM*WQE_SLOTS];
    (* ramstyle = "no_rw_check,m20k" *) reg [47:0]  meta_ram [QP_NUM*WQE_SLOTS];
    reg  [8:0]   ram_read_address;
    reg  [511:0] wqe_read_data;
    reg  [47:0]  meta_read_data;
    reg          meta_write_enable;
    reg  [8:0]   meta_write_address;
    reg  [47:0]  meta_write_data;
    reg          wqe_write_enable;
    reg  [8:0]   wqe_write_address;
    reg  [1023:0] wqe_write_data;
    always @(posedge clk) begin
        wqe_read_data  <= wqe_ram[ram_read_address];
        meta_read_data <= meta_ram[ram_read_address];
        if (wqe_write_enable)  wqe_ram[wqe_write_address]   <= wqe_write_data;   // WQE 是 64 B，高 512 位由 rd_align 的 keep 屏蔽、恒 0
        if (meta_write_enable) meta_ram[meta_write_address] <= meta_write_data;
    end

    // 取指在途 FIFO：记录每个读回拍属于哪个 QP（读数据按序返回）
    reg  [3:0]  fetch_owner_fifo [64];
    reg  [6:0]  fetch_owner_write_pointer, fetch_owner_read_pointer;
    wire        fetch_owner_ready = (fetch_owner_write_pointer - fetch_owner_read_pointer) < 7'd64;
    wire [3:0]  fetch_owner_qp = fetch_owner_fifo[fetch_owner_read_pointer[5:0]];

    // ------------------------------------------------------------ 取指 / 发送候选共用
    wire [QP_NUM-1:0] qp_is_rts;
    genvar rts_gen;
    generate
        for (rts_gen = 0; rts_gen < QP_NUM; rts_gen = rts_gen + 1) begin : gen_qp_is_rts
            assign qp_is_rts[rts_gen] = (qp_state_i[rts_gen*3 +: 3] == QPS_RTS);
        end
    endgenerate

    // round-robin 选择：从 start 往上找第一个置位的下标，找不到再从 0 往上找。
    // 与原来「candidate 从 QP_NUM-1 倒序扫、qp = (rr + candidate) % QP_NUM、后写覆盖」的
    // 选择结果逐位相同（都是按 rr, rr+1, ..., rr+15 的顺序取第一个）。
    // 输入是寄存器 + 单 bit 掩码，综合成两个并行的 16 位优先编码 + 2 选 1，不再有变址与比较。
    function automatic [4:0] rr_pick(input [QP_NUM-1:0] cand, input [3:0] start);
        logic [QP_NUM-1:0] upper;
        logic              found_upper, found_any;
        logic [3:0]        index_upper, index_any;
        upper       = cand & ~((QP_NUM'(1) << start) - QP_NUM'(1));
        found_upper = 1'b0;  index_upper = 4'd0;
        found_any   = 1'b0;  index_any   = 4'd0;
        for (int i = QP_NUM - 1; i >= 0; i--) begin
            if (upper[i]) begin found_upper = 1'b1; index_upper = 4'(i); end
            if (cand[i])  begin found_any   = 1'b1; index_any   = 4'(i); end
        end
        rr_pick = {found_any, found_upper ? index_upper : index_any};
    endfunction

    // ------------------------------------------------------------ 取指（B6417：三级流水）
    // 历史：B6409 把「选路 → QPC 读出 → 基址加法」拆成两级；B6416（250 MHz）这里仍是 u_req 内部
    // 最大的违例族（REQ_REQ 5308 条，最差 −0.563）：
    //   fetch_round_robin → (rr+candidate)%16 变址 → 16 路 qp_fetch_issued/qp_sq_producer/
    //   qp_unacked_index 选路 + 16 位减法比较 → 优先链 → fetch_pick → QPC 选路 + 基址加法 → 寄存器。
    // 现在三级：
    //   第 1 级 fetch_eligible_q[qp]：每 QP 按**常量下标**并行算「有未取 WQE 且片上环有空槽」并寄存；
    //   第 2 级 fetch_sel_*        ：资格位 & RTS & ~在途掩码 → rr_pick → 寄存选中的 QP；
    //   第 3 级 fetch_req_*        ：按**寄存器** fetch_sel_qp 读 QPC、算 WQE 地址，寄存后直接驱动 DMA。
    //
    // 正确性（资格位比真实状态晚 1 拍，必须保证同一 WQE 不被取两遍）：
    //   qp_fetch_issued 只在 fetch_fire 时对 fetch_req_qp 自增。某 QP 在
    //     a) 处于第 2 级（fetch_sel_valid && fetch_sel_qp == qp），
    //     b) 处于第 3 级（fetch_req_valid && fetch_req_qp == qp），
    //     c) 上一拍刚握手（fetch_fired_d && fetch_fired_qp_d == qp，自增尚未反映进资格位）
    //   这三种情况下都从候选里排除，所以被选中时它的 issued 已经稳定且资格位已反映最新值；
    //   第 3 级装载时读的 qp_fetch_issued[fetch_sel_qp] 也就是该 QP 当前真实的下一个 WQE。
    //   其余输入的滞后都是保守的：producer 只增（门铃）、unacked_index 只增（退休），
    //   晚 1 拍只会晚 1 拍发现可取；QP 被复位/置错时 qp_is_rts 是当拍值，直接挡住。
    // 代价：单 QP 连续取指 4 拍一个 WQE（原来 2 拍），多 QP 交错时仍可每拍一个。
    //   每个 WQE 至少一包、每包 ≥ 9 拍，取指不在关键路径上。
    reg  [3:0]  fetch_round_robin;
    reg  [QP_NUM-1:0] fetch_eligible_q;
    reg         fetch_sel_valid;
    reg  [3:0]  fetch_sel_qp;
    reg         fetch_req_valid;
    reg  [3:0]  fetch_req_qp;
    reg  [63:0] fetch_req_address;
    reg         fetch_fired_d;
    reg  [3:0]  fetch_fired_qp_d;

    always @(posedge clk) begin
        if (rst) fetch_eligible_q <= '0;
        else
            for (int qp = 0; qp < QP_NUM; qp++)
                fetch_eligible_q[qp] <= (qp_fetch_issued[qp] != qp_sq_producer[qp]) &&
                                        ((qp_fetch_issued[qp] - qp_unacked_index[qp]) < 16'(WQE_SLOTS));
    end

    wire [QP_NUM-1:0] fetch_busy = (fetch_sel_valid ? (QP_NUM'(1) << fetch_sel_qp)     : QP_NUM'(0)) |
                                   (fetch_req_valid ? (QP_NUM'(1) << fetch_req_qp)     : QP_NUM'(0)) |
                                   (fetch_fired_d   ? (QP_NUM'(1) << fetch_fired_qp_d) : QP_NUM'(0));
    wire [QP_NUM-1:0] fetch_candidates = fetch_eligible_q & qp_is_rts & ~fetch_busy;
    wire        fetch_any;
    wire [3:0]  fetch_pick;
    assign {fetch_any, fetch_pick} = rr_pick(fetch_candidates, fetch_round_robin);

    function automatic [63:0] fetch_wqe_address(input [3:0] qp, input [15:0] issued);
        logic [511:0] qpc_ctx;          // 不能叫 context：SystemVerilog 保留字，Verilator 报 syntax error
        qpc_ctx = qpc[qp*512 +: 512];
        fetch_wqe_address = qpc_sq_base(qpc_ctx) +
            {42'd0, issued & ((16'd1 << qpc_sq_lg(qpc_ctx)) - 16'd1), 6'd0};
    endfunction

    wire        fetch_fire     = fetch_req_valid && dma_read_request_ready;
    wire        fetch_move     = fetch_sel_valid && fetch_owner_ready && (!fetch_req_valid || dma_read_request_ready);
    wire        fetch_sel_load = fetch_any && (!fetch_sel_valid || fetch_move);

    assign dma_read_request_valid = fetch_req_valid;
    assign dma_read_request_address  = fetch_req_address;
    assign dma_read_request_page1 = fetch_req_address + 64'd4096;
    assign dma_read_request_length   = 13'd64;
    assign dma_read_ready = 1'b1;

    always @(posedge clk) begin
        if (rst) begin
            fetch_sel_valid   <= 1'b0;
            fetch_sel_qp      <= 4'd0;
            fetch_req_valid   <= 1'b0;
            fetch_req_qp      <= 4'd0;
            fetch_req_address <= 64'd0;
            fetch_fired_d     <= 1'b0;
            fetch_fired_qp_d  <= 4'd0;
        end else begin
            fetch_fired_d    <= fetch_fire;
            fetch_fired_qp_d <= fetch_req_qp;
            // 第 3 级：fetch_move 时装上第 2 级的 QP（同拍旧请求若握手，move 的条件已包含 ready）
            if (fetch_move) begin
                fetch_req_valid   <= 1'b1;
                fetch_req_qp      <= fetch_sel_qp;
                fetch_req_address <= fetch_wqe_address(fetch_sel_qp, qp_fetch_issued[fetch_sel_qp]);
            end else if (fetch_fire) begin
                fetch_req_valid   <= 1'b0;
            end
            // 第 2 级
            if (fetch_sel_load) begin
                fetch_sel_valid <= 1'b1;
                fetch_sel_qp    <= fetch_pick;
            end else if (fetch_move) begin
                fetch_sel_valid <= 1'b0;
            end
        end
    end

    always @(posedge clk) begin
        wqe_write_enable <= 1'b0;
        if (doorbell_sq_valid) qp_sq_producer[doorbell_data[3:0]] <= doorbell_data[31:16];
        if (rst) begin
            fetch_round_robin    <= '0;
            fetch_owner_write_pointer <= '0;
            fetch_owner_read_pointer <= '0;
            // 取指三兄弟只在本块里驱动（门铃写 producer、取指自增 issued、取回自增 done），
            // 所以清零也必须留在这里。主状态机块里再清一次会触发 Quartus
            //   Error (13264): Can't resolve multiple constant drivers
            // ——2026-10-25 B6371 首次编译就栽在这上面。
            for (int qp = 0; qp < QP_NUM; qp++) begin
                qp_sq_producer[qp]  <= 16'd0;
                qp_fetch_issued[qp] <= 16'd0;
                qp_fetch_done[qp]   <= 16'd0;
            end
        end else begin
            if (fetch_fire) begin
                // 握手在第三级完成：owner 记录发给 DMA 的那个 QP，自增它的 issued。
                // round-robin 也在这里推进。下一拍该 QP 由 fetch_fired_d 挡住（资格位还是自增前的），
                // 再下一拍资格位已按自增后的 issued 重算。
                fetch_owner_fifo[fetch_owner_write_pointer[5:0]] <= fetch_req_qp;
                fetch_owner_write_pointer <= fetch_owner_write_pointer + 7'd1;
                qp_fetch_issued[fetch_req_qp] <= qp_fetch_issued[fetch_req_qp] + 16'd1;
                fetch_round_robin <= fetch_req_qp + 4'd1;
            end
            if (dma_read_valid) begin
                wqe_write_enable       <= 1'b1;
                wqe_write_address       <= {fetch_owner_qp, qp_fetch_done[fetch_owner_qp][4:0]};
                wqe_write_data       <= dma_read_data;
                qp_fetch_done[fetch_owner_qp]    <= qp_fetch_done[fetch_owner_qp] + 16'd1;
                fetch_owner_read_pointer       <= fetch_owner_read_pointer + 7'd1;
            end
        end
        for (int qp = 0; qp < QP_NUM; qp++)
            if (qp_state_change[qp] && qp_state_i[qp*3 +: 3] <= QPS_INIT) begin
                qp_sq_producer[qp] <= 16'd0;
                qp_fetch_issued[qp] <= 16'd0;
                qp_fetch_done[qp] <= 16'd0;
            end
    end

    // ------------------------------------------------------------ 定时器（4.096 us 一拍，按 CORE_CLOCK_MHZ 分频）
    localparam int TICK_CYCLES = (CORE_CLOCK_MHZ * 4096 + 500) / 1000;   // 4.096 us
    reg  [11:0] tick_divider;
    wire        timer_tick = (tick_divider == 12'd0);
    reg  [20:0] qp_timer [QP_NUM];
    reg  [QP_NUM-1:0] timer_restart;               // 主状态机发出：有进展/重传
    reg  [17:0] qp_rnr_countdown [QP_NUM];
    reg  [QP_NUM-1:0] rnr_load;
    reg  [17:0] rnr_load_value;
    wire [QP_NUM-1:0] timer_expired, rnr_expired;
    always @(posedge clk) begin
        tick_divider <= (rst || tick_divider == 12'(TICK_CYCLES - 1)) ? 12'd0 : tick_divider + 12'd1;
        for (int qp = 0; qp < QP_NUM; qp++) begin
            if (timer_restart[qp] || qp_unacked_psn[qp] == qp_next_psn[qp])
                qp_timer[qp] <= 21'd0;
            else if (timer_tick && !qp_timer[qp][20])
                qp_timer[qp] <= qp_timer[qp] + 21'd1;
            if (rnr_load[qp])
                qp_rnr_countdown[qp] <= rnr_load_value;
            else if (timer_tick && qp_rnr_countdown[qp] != 18'd0)
                qp_rnr_countdown[qp] <= qp_rnr_countdown[qp] - 18'd1;
        end
    end
    genvar qp_gen;
    generate
        for (qp_gen = 0; qp_gen < QP_NUM; qp_gen = qp_gen + 1) begin : gen_timer
            wire [4:0] timeout_exponent = qpc_timeout(qpc[qp_gen*512 +: 512]);
            wire [4:0] timeout_exponent_clamped = (timeout_exponent > 5'd20) ? 5'd20 : timeout_exponent;
            assign timer_expired[qp_gen] = (timeout_exponent != 5'd0) && (qp_unacked_psn[qp_gen] != qp_next_psn[qp_gen]) &&
                              (qp_timer[qp_gen] >= (21'd1 << timeout_exponent_clamped)) && !qp_rnr_waiting[qp_gen];
            assign rnr_expired[qp_gen] = qp_rnr_waiting[qp_gen] && (qp_rnr_countdown[qp_gen] == 18'd0) && !rnr_load[qp_gen];
        end
    endgenerate

    // RNR NAK 定时器编码 -> 4.096 us 拍数（IBTA 表 45，向上取整）
    function automatic [17:0] rnr_timer_ticks(input [4:0] rnr_code);
        case (rnr_code)
            5'd0:  rnr_timer_ticks = 18'd160000; 5'd1:  rnr_timer_ticks = 18'd3;     5'd2:  rnr_timer_ticks = 18'd5;
            5'd3:  rnr_timer_ticks = 18'd8;      5'd4:  rnr_timer_ticks = 18'd10;    5'd5:  rnr_timer_ticks = 18'd15;
            5'd6:  rnr_timer_ticks = 18'd20;     5'd7:  rnr_timer_ticks = 18'd30;    5'd8:  rnr_timer_ticks = 18'd40;
            5'd9:  rnr_timer_ticks = 18'd59;     5'd10: rnr_timer_ticks = 18'd79;    5'd11: rnr_timer_ticks = 18'd118;
            5'd12: rnr_timer_ticks = 18'd157;    5'd13: rnr_timer_ticks = 18'd235;   5'd14: rnr_timer_ticks = 18'd313;
            5'd15: rnr_timer_ticks = 18'd469;    5'd16: rnr_timer_ticks = 18'd625;   5'd17: rnr_timer_ticks = 18'd938;
            5'd18: rnr_timer_ticks = 18'd1250;   5'd19: rnr_timer_ticks = 18'd1875;  5'd20: rnr_timer_ticks = 18'd2500;
            5'd21: rnr_timer_ticks = 18'd3750;   5'd22: rnr_timer_ticks = 18'd5000;  5'd23: rnr_timer_ticks = 18'd7500;
            5'd24: rnr_timer_ticks = 18'd10000;  5'd25: rnr_timer_ticks = 18'd15000; 5'd26: rnr_timer_ticks = 18'd20000;
            5'd27: rnr_timer_ticks = 18'd30000;  5'd28: rnr_timer_ticks = 18'd40000; 5'd29: rnr_timer_ticks = 18'd60000;
            5'd30: rnr_timer_ticks = 18'd80000;  default: rnr_timer_ticks = 18'd120000;
        endcase
    endfunction
    // ------------------------------------------------------------ 发送候选
    // B6411 的 250 MHz 做法：把「未确认 PSN 窗口」判断从扫描链里拿出来预计算（tx_window_ok）。
    // B6417：其余资格条件也一并按常量下标预计算、寄存成 tx_eligible_q。B6416 里
    //   tx_round_robin → (rr+candidate)%16 变址 → 16 路 qp_fetch_done/qp_tx_index 选路 + 16 位比较
    //   → 优先链 → tx_pick → tx_round_robin
    // 是 652 条、最差 −0.508 的违例；现在扫描只剩 rr_pick（两个 16 位优先编码 + 2 选 1）。
    //
    // 窗口判断是**软流控**（在途 PSN 数 < 2048），不是 24 位空间的回绕判定，2048 ≪ 2^24，
    // 寄存一拍最多让某一个 QP 多发出一包（下一拍窗口就会拦住），不会造成 PSN 歧义。
    //
    // 正确性（资格位晚 1 拍，必须保证同一 WQE 不被重复派发）：
    //   qp_tx_index / qp_local_error / qp_rnr_waiting / PSN 只在 REQ_WRITE_BACK 写回 qp_index
    //   （以及 qp_state_change 复位，那时 qp_is_rts 已为假）。写回后的下一拍主状态机回到 IDLE，
    //   此时 tx_eligible_q 还是写回前算的，所以这一拍用 tx_writeback_d 把 qp_index 挡掉；
    //   再下一拍资格位已按写回后的值重算。qp_fetch_done 只增，晚 1 拍是保守的。
    reg  [QP_NUM-1:0] tx_eligible_q;
    // PFC 准入（2026-11-09）：每个 QP 按 QPC 的 TOS[7:5] 选优先级，被 pause 的优先级不派发新 WQE。
    //   rx_pfc[8] 是 802.3x 全局 pause，挡住所有优先级；rx_pfc[7:0] 是 per-priority，
    //   受控注入已证明 F-tile 逐帧产出（skill/pfc-dcqcn-congestion-control.md §12）。
    // 只挡「新 WQE 派发」：已开始的包（REQ_TX_*）发完，ACK/NAK/READ RESP 由 roce_resp 直接出，不受影响。
    // 优先级 = TOS[7:5] = DSCP[5:3]（与 QDMA 路径 pfc_parser 的 IPv4 分类同口径）。
    //   qpc_tos 在 dw7[23:16]，即 qpc[7*32+16 +: 8]（roce_pkg::qpc_tos），其 [7:5] 直接位选 qpc[7*32+16+5 +: 3]。
    // 与 tx_eligible_q 同拍寄存，选路逻辑上只多一个 QP_NUM 位的与。
    reg  [QP_NUM-1:0] tx_pfc_blocked_q;
    always @(posedge clk) begin
        if (rst) tx_pfc_blocked_q <= '0;
        else
            for (int qp = 0; qp < QP_NUM; qp++)
                tx_pfc_blocked_q[qp] <= pfc_gate_enable &&
                                        (rx_pfc[8] || rx_pfc[qpc[qp*512 + 7*32+16+5 +: 3]]);
    end
    always @(posedge clk) begin
        if (rst) tx_eligible_q <= '0;
        else
            for (int qp = 0; qp < QP_NUM; qp++)
                tx_eligible_q[qp] <= (qp_fetch_done[qp] != qp_tx_index[qp]) && !qp_local_error[qp] &&
                                     !qp_rnr_waiting[qp] &&
                                     (24'(qp_next_psn[qp] - qp_unacked_psn[qp]) < 24'd2048) &&
                                     tx_rate_ready[qp] &&
                                     !tx_pfc_blocked_q[qp];
    end

    reg  [3:0]  tx_round_robin;
    reg         tx_writeback_d;            // 上一拍在 REQ_WRITE_BACK（qp_index 的每 QP 状态刚写回）
    wire        tx_any;
    wire [3:0]  tx_pick;

    // ------------------------------------------------------------ 主状态机
    localparam [4:0] REQ_IDLE = 5'd0, REQ_LOAD = 5'd1, REQ_TX_ADDRESS = 5'd2, REQ_TX_WAIT = 5'd3, REQ_TX_COMPUTE = 5'd4,
                     REQ_TX_TRANSLATE = 5'd5, REQ_TX_TRANSLATE_WAIT = 5'd6, REQ_TX_PUSH = 5'd7, REQ_RX_CLASSIFY = 5'd8, REQ_WALK_START = 5'd9,
                     REQ_WALK_WAIT2 = 5'd10, REQ_WALK_DECIDE = 5'd11, REQ_RESTART = 5'd12, REQ_RESP_TRANSLATE = 5'd13, REQ_RESP_TRANSLATE_WAIT = 5'd14,
                     REQ_RESP_WRITE_REQUEST = 5'd15, REQ_RESP_WRITE_DATA = 5'd16, REQ_RESP_FINISH = 5'd17, REQ_CQE = 5'd18, REQ_DRAIN = 5'd19,
                     REQ_WRITE_BACK = 5'd20, REQ_WALK_WAIT1 = 5'd21;
    localparam [2:0] EVENT_ACK = 3'd0, EVENT_NAK_SEQUENCE = 3'd1, EVENT_RNR_NAK = 3'd2, EVENT_NAK_ERROR = 3'd3, EVENT_READ_RESPONSE = 3'd4,
                     EVENT_TIMEOUT = 3'd5, EVENT_RNR_DONE = 3'd6;
    reg  [4:0]   state, cqe_return_state;
    reg  [1:0]   dispatch_reason;          // 0 发送 1 收包 2 超时 3 RNR 到期
    reg          prefer_tx;                // 收发都有时轮流服务，避免连续 READ 响应把重发/新请求饿住
    reg  [3:0]   qp_index;
    reg  [511:0] qp_context;
    rx_hdr_t     header;
    reg  [2:0]   event_kind;
    reg  [23:0]  retire_psn;            // 退休门限：结束 PSN <= retire_psn 的 WQE 退休
    reg  [7:0]   nak_syndrome;
    reg          payload_consumed, handling_rx;
    // 工作副本
    reg  [15:0]  tx_index, unacked_index;
    reg  [23:0]  next_psn, unacked_psn;
    reg  [31:0]  tx_offset;
    reg          tx_started, local_error, rnr_waiting;
    reg          recovering;
    reg  [2:0]   retry_left, rnr_retry_left;
    reg  [4:0]   reads_outstanding;
    reg  [5:0]   ack_counter;
    // 当前包
    reg  [12:0]  chunk_length;
    reg          packet_first, packet_last;
    reg  [23:0]  wqe_psn_start, wqe_packet_count;
    reg  [63:0]  physical_address0, physical_page1;
    reg  [7:0]   cqe_status;          // CQE 状态
    reg  [15:0]  cqe_wqe_index;         // CQE 对应的 WQE 索引
    reg  [7:0]   cqe_opcode;
    reg  [31:0]  cqe_length;
    reg          cqe_signaled;

    // B6418：写回后那拍不再把 qp_index 挡掉，而是用「写回值本身」算出的资格位替换它。
    //   B6417 的挡法让单 QP 每包在 IDLE 白等 1 拍（每包 14.25 → 14.64 拍，client write −2.6%，
    //   roce-optimization-log §44.3）；多 QP 时 round-robin 能选别的 QP 填上，所以只伤单 QP。
    //   REQ_WRITE_BACK 那拍状态机工作副本（tx_index / next_psn / unacked_psn / local_error / rnr_waiting）
    //   就是要写进 qp_* 的值（同一 always 块里写回排在 qp_state_change 之后，同拍写回优先），
    //   所以在那拍寄存 tx_self_eligible_q，下一拍 IDLE 用它代替 tx_eligible_q[qp_index]——
    //   与 tx_eligible_q 两拍后按写回值重算的结果逐位一致，不会重复派发。
    //   qp_fetch_done[qp_index] 先寄存一拍（fetch_done_current）：只增不减，晚 1 拍是保守的；
    //   qp_index 从 REQ_LOAD 到 REQ_WRITE_BACK 都不变，寄存值在写回那拍已对准本 QP。
    //   全是寄存器项，16 路选路不进比较器，不重新引入 B6416 的扫描关键路径。
    reg  [15:0] fetch_done_current;
    reg         tx_self_eligible_q;
    always @(posedge clk) begin
        fetch_done_current <= qp_fetch_done[qp_index];
        // PFC 门控也要挡这条旁路：它替代的是 tx_eligible_q[qp_index]，若不带
        // !tx_pfc_blocked_q[qp_index]，每次 pause 都会从旁路多放一个包出去。
        tx_self_eligible_q <= (fetch_done_current != tx_index) && !local_error && !rnr_waiting &&
                              (24'(next_psn - unacked_psn) < 24'd2048) &&
                              tx_rate_ready[qp_index] &&
                              !tx_pfc_blocked_q[qp_index];
    end
    wire [QP_NUM-1:0] tx_writeback_mask = tx_writeback_d ? (QP_NUM'(1) << qp_index) : QP_NUM'(0);
    wire [QP_NUM-1:0] tx_candidates = ((tx_eligible_q & ~tx_writeback_mask) |
                                       (tx_self_eligible_q ? tx_writeback_mask : QP_NUM'(0))) & qp_is_rts;
    assign {tx_any, tx_pick} = rr_pick(tx_candidates, tx_round_robin);

    wire [3:0]   wqe_opcode   = wqe_read_data[3:0];
    wire         wqe_signaled  = wqe_read_data[8];
    wire         wqe_solicited   = wqe_read_data[9];
    wire [31:0]  wqe_length  = wqe_read_data[63:32];
    wire [31:0]  wqe_lkey = wqe_read_data[95:64];
    wire [31:0]  wqe_immediate  = wqe_read_data[127:96];
    wire [63:0]  wqe_local_address  = wqe_read_data[191:128];
    wire [63:0]  wqe_remote_address  = wqe_read_data[255:192];
    wire [31:0]  wqe_rkey = wqe_read_data[287:256];
    wire         wqe_is_read   = (wqe_opcode == WQE_READ);
    wire [3:0]   path_mtu_shift  = 4'(qpc_pmtu(qp_context)) + 4'd7;
    wire [12:0]  path_mtu   = pmtu_bytes(qpc_pmtu(qp_context));
    wire [23:0]  meta_psn_start = meta_read_data[47:24];
    wire [23:0]  meta_packet_count  = meta_read_data[23:0];
    wire [23:0]  meta_psn_end   = meta_psn_start + meta_packet_count;          // 下一个 WQE 的起始 PSN
    wire [31:0]  tx_remaining     = wqe_length - tx_offset;
    wire [23:0]  first_packet_count = (wqe_length == 32'd0) ? 24'd1 : 24'((wqe_length + {19'd0, path_mtu} - 32'd1) >> path_mtu_shift);

    function automatic [7:0] wc_opcode_of(input [3:0] wqe_op);
        wc_opcode_of = (wqe_op == WQE_READ) ? WC_RDMA_READ :
                (wqe_op == WQE_WRITE || wqe_op == WQE_WRITE_IMM) ? WC_RDMA_WRITE : WC_SEND;
    endfunction
    function automatic [7:0] tx_opcode_of(input [3:0] wqe_op, input is_first, input is_last);
        case (wqe_op)
            WQE_WRITE:     tx_opcode_of = (is_first && is_last) ? OP_WRITE_ONLY : is_first ? OP_WRITE_FIRST :
                                   is_last ? OP_WRITE_LAST : OP_WRITE_MIDDLE;
            WQE_WRITE_IMM: tx_opcode_of = (is_first && is_last) ? OP_WRITE_ONLY_IMM : is_first ? OP_WRITE_FIRST :
                                   is_last ? OP_WRITE_LAST_IMM : OP_WRITE_MIDDLE;
            WQE_SEND:      tx_opcode_of = (is_first && is_last) ? OP_SEND_ONLY : is_first ? OP_SEND_FIRST :
                                   is_last ? OP_SEND_LAST : OP_SEND_MIDDLE;
            WQE_SEND_IMM:  tx_opcode_of = (is_first && is_last) ? OP_SEND_ONLY_IMM : is_first ? OP_SEND_FIRST :
                                   is_last ? OP_SEND_LAST_IMM : OP_SEND_MIDDLE;
            default:       tx_opcode_of = OP_READ_REQ;
        endcase
    endfunction

    // 响应包分类：退休门限 retire_psn（结束 PSN <= retire_psn 的 WQE 都已完成）
    wire [2:0]  rx_event_kind = (header.opcode != OP_ACK)              ? EVENT_READ_RESPONSE :
                          (header.aeth_syndrome[7:5] == 3'b000)       ? EVENT_ACK  :
                          (header.aeth_syndrome[7:5] == 3'b001)       ? EVENT_RNR_NAK  :
                          (header.aeth_syndrome == AETH_NAK_SEQ)      ? EVENT_NAK_SEQUENCE : EVENT_NAK_ERROR;
    wire [23:0] rx_retire_psn    = (rx_event_kind == EVENT_ACK) ? header.psn + 24'd1 : header.psn;
    wire [23:0] rx_retire_distance   = rx_retire_psn - unacked_psn;

    assign translate_valid = (state == REQ_TX_TRANSLATE) || (state == REQ_RESP_TRANSLATE);
    assign translate_protection_domain    = qpc_pd(qp_context);
    wire   payload_forward    = (state == REQ_RESP_WRITE_DATA);
    assign dma_write_valid = payload_forward && rx_payload_valid;
    assign dma_write_data  = rx_payload_data;
    assign rx_payload_ready  = payload_forward ? dma_write_ready : (state == REQ_DRAIN && !payload_consumed);   // 已收完就不能再接下一包的数据
    always @(posedge clk) begin
        rx_header_ready         <= 1'b0;
        done            <= 1'b0;
        qp_set_error          <= '0;
        timer_restart         <= '0;
        rnr_load          <= '0;
        meta_write_enable         <= 1'b0;
        event_rx_ack       <= 1'b0;
        event_rx_nak       <= 1'b0;
        event_rx_rnr       <= 1'b0;
        event_rx_cnp       <= 1'b0;
        event_rx_cnp_qp    <= '0;
        event_retransmit_timeout <= 1'b0;
        event_retransmit_nak     <= 1'b0;
        for (int qp = 0; qp < QP_NUM; qp++)
            if (qp_state_change[qp]) begin
                if (qp_state_i[qp*3 +: 3] <= QPS_INIT) begin
                    qp_tx_index[qp] <= 16'd0; qp_unacked_index[qp] <= 16'd0; qp_tx_offset[qp] <= 32'd0; qp_tx_started[qp] <= 1'b0;
                    qp_reads_outstanding[qp] <= 5'd0; qp_ack_counter[qp] <= 6'd0; qp_local_error[qp] <= 1'b0; qp_rnr_waiting[qp] <= 1'b0; qp_recovering[qp] <= 1'b0;
                end
                qp_next_psn[qp] <= qpc_sq_psn(qpc[qp*512 +: 512]);
                qp_unacked_psn[qp] <= qpc_sq_psn(qpc[qp*512 +: 512]);
                qp_retry_left[qp]  <= qpc_retry(qpc[qp*512 +: 512]);
                qp_rnr_retry_left[qp]  <= qpc_rnr_rty(qpc[qp*512 +: 512]);
            end
        tx_writeback_d <= !rst && (state == REQ_WRITE_BACK);
        if (rst) begin
            state       <= REQ_IDLE;
            tx_round_robin      <= '0;
            prefer_tx     <= 1'b0;
            tx_job_valid  <= 1'b0;
            cqe_valid  <= 1'b0;
            dma_write_request_valid <= 1'b0;
            // 每 QP 状态必须在这里清，不能只靠 qp_state_change。
            // qp_state_change 只在主机写 QPC 且状态**发生变化**时打一拍；kill -9 之后
            // 新进程重建 QP 时 roce_tbl 的 qp_state_store 已被复位成 RESET，主机再写
            // RESET 不构成变化 → 没有脉冲 → qp_local_error / qp_rnr_waiting /
            // qp_recovering 这些"卡住"标志与 PSN、WQE 索引全部原样留存，数据面再也起不来。
            // 软复位要等效于一次 JTAG 重烧，所有逐 QP 状态一律归零。
            for (int qp = 0; qp < QP_NUM; qp++) begin
                qp_tx_index[qp]        <= 16'd0;
                qp_unacked_index[qp]   <= 16'd0;
                qp_next_psn[qp]        <= 24'd0;
                qp_unacked_psn[qp]     <= 24'd0;
                qp_tx_offset[qp]       <= 32'd0;
                qp_tx_started[qp]      <= 1'b0;
                qp_retry_left[qp]      <= 3'd7;
                qp_rnr_retry_left[qp]  <= 3'd7;
                qp_reads_outstanding[qp] <= 5'd0;
                qp_ack_counter[qp]     <= 6'd0;
                qp_local_error[qp]     <= 1'b0;
                qp_rnr_waiting[qp]     <= 1'b0;
                qp_recovering[qp]      <= 1'b0;
                // qp_sq_producer / qp_fetch_issued / qp_fetch_done 不在这里清：
                // 它们只由上面的取指块驱动，两个时钟块同时赋值会触发
                // Error (13264) Can't resolve multiple constant drivers。
            end
        end else case (state)
            REQ_IDLE: begin
                if (rx_header_valid && !rx_header_ready && !(tx_any && prefer_tx)) begin
                    rx_header_ready <= 1'b1;
                    header       <= rx_header;
                    qp_index      <= rx_header.qp_index;
                    dispatch_reason     <= 2'd1;
                    prefer_tx    <= 1'b1;
                    state      <= REQ_LOAD;
                end else if (|timer_expired) begin
                    for (int qp = QP_NUM - 1; qp >= 0; qp--) if (timer_expired[qp]) qp_index <= 4'(qp);
                    dispatch_reason <= 2'd2;
                    state  <= REQ_LOAD;
                end else if (|rnr_expired) begin
                    for (int qp = QP_NUM - 1; qp >= 0; qp--) if (rnr_expired[qp]) qp_index <= 4'(qp);
                    dispatch_reason <= 2'd3;
                    state  <= REQ_LOAD;
                end else if (tx_any) begin
                    qp_index  <= tx_pick;
                    tx_round_robin <= tx_pick + 4'd1;
                    dispatch_reason <= 2'd0;
                    prefer_tx <= 1'b0;
                    state  <= REQ_LOAD;
                end
            end
            REQ_LOAD: begin
                qp_context    <= qpc[qp_index*512 +: 512];
                tx_index   <= qp_tx_index[qp_index];   unacked_index  <= qp_unacked_index[qp_index];  next_psn <= qp_next_psn[qp_index]; unacked_psn <= qp_unacked_psn[qp_index];
                tx_offset  <= qp_tx_offset[qp_index];  tx_started <= qp_tx_started[qp_index]; retry_left  <= qp_retry_left[qp_index];  rnr_retry_left  <= qp_rnr_retry_left[qp_index];
                reads_outstanding  <= qp_reads_outstanding[qp_index];  ack_counter <= qp_ack_counter[qp_index]; local_error <= qp_local_error[qp_index]; rnr_waiting <= qp_rnr_waiting[qp_index];
                recovering <= qp_recovering[qp_index];
                handling_rx  <= (dispatch_reason == 2'd1);
                payload_consumed <= (dispatch_reason != 2'd1) || (header.payload_length == 13'd0);
                case (dispatch_reason)
                    2'd0: state <= REQ_TX_ADDRESS;
                    2'd1: state <= REQ_RX_CLASSIFY;
                    2'd2: begin event_kind <= EVENT_TIMEOUT;  retire_psn <= qp_unacked_psn[qp_index]; state <= REQ_WALK_START; end
                    default: begin event_kind <= EVENT_RNR_DONE; retire_psn <= qp_unacked_psn[qp_index]; rnr_waiting <= 1'b0; state <= REQ_WALK_START; end
                endcase
            end
            // ---------------- 发送一个包
            REQ_TX_ADDRESS:  begin ram_read_address <= {qp_index, tx_index[4:0]}; state <= REQ_TX_WAIT; end
            REQ_TX_WAIT:  state <= REQ_TX_COMPUTE;
            REQ_TX_COMPUTE:  begin
                if (local_error || qpc_state(qp_context) != QPS_RTS) begin
                    state <= REQ_WRITE_BACK;
                end else if (!tx_started && wqe_is_read && reads_outstanding >= {1'b0, qpc_max_rd(qp_context)} + 5'd1) begin
                    state <= REQ_WRITE_BACK;                                  // 在途 READ 已满
                end else begin
                    wqe_psn_start <= tx_started ? meta_psn_start : next_psn;
                    wqe_packet_count   <= tx_started ? meta_packet_count  : first_packet_count;
                    packet_first <= !tx_started;
                    if (wqe_is_read) begin
                        chunk_length  <= 13'd0;
                        packet_last <= 1'b1;
                    end else begin
                        chunk_length  <= (tx_remaining > {19'd0, path_mtu}) ? path_mtu : tx_remaining[12:0];
                        packet_last <= (tx_remaining <= {19'd0, path_mtu});
                    end
                    translate_key <= wqe_lkey;
                    translate_virtual_address  <= wqe_local_address + {32'd0, tx_offset};
                    translate_length <= (tx_remaining > {19'd0, path_mtu}) ? path_mtu : tx_remaining[12:0];
                    translate_access <= 4'd0;
                    physical_address0    <= '0;
                    physical_page1    <= '0;
                    state     <= (!wqe_is_read && tx_remaining != 32'd0) ? REQ_TX_TRANSLATE : REQ_TX_PUSH;
                end
            end
            REQ_TX_TRANSLATE:  if (translate_ready) state <= REQ_TX_TRANSLATE_WAIT;
            REQ_TX_TRANSLATE_WAIT: if (translate_response) begin
                        physical_address0 <= translate_physical_address0;
                        physical_page1 <= translate_physical_page1;
                        if (translate_error) begin
                            cqe_status <= WCS_LOC_PROT_ERR; cqe_wqe_index <= tx_index; cqe_opcode <= wc_opcode_of(wqe_opcode);
                            cqe_length <= 32'd0; cqe_signaled <= 1'b1; local_error <= 1'b1;
                            qp_set_error[qp_index] <= 1'b1;
                            cqe_return_state <= REQ_WRITE_BACK;
                            state   <= REQ_CQE;
                        end else
                            state <= REQ_TX_PUSH;
                    end
            REQ_TX_PUSH:  begin
                tx_job_valid           <= 1'b1;
                tx_job             <= '0;
                tx_job.qp_index          <= qp_index;
                tx_job.opcode      <= tx_opcode_of(wqe_opcode, packet_first, packet_last);
                tx_job.psn         <= next_psn;
                tx_job.ack_request      <= packet_last || (ack_counter == 6'd63);
                tx_job.solicited          <= packet_last && wqe_solicited;
                tx_job.reth_virtual_address     <= wqe_remote_address + (wqe_is_read ? {32'd0, tx_offset} : 64'd0);   // READ 重发从断点续读
                tx_job.reth_rkey   <= wqe_rkey;
                tx_job.reth_length    <= wqe_length - (wqe_is_read ? tx_offset : 32'd0);
                tx_job.immediate         <= wqe_immediate;
                tx_job.payload_length         <= chunk_length;
                tx_job.physical_address0         <= physical_address0;
                tx_job.physical_page1         <= physical_page1;
                if (tx_job_valid && tx_job_ready) begin
                    tx_job_valid <= 1'b0;
                    if (unacked_psn == next_psn) timer_restart[qp_index] <= 1'b1;
                    next_psn <= wqe_is_read ? wqe_psn_start + wqe_packet_count : next_psn + 24'd1;
                    ack_counter <= packet_last ? 6'd0 : ack_counter + 6'd1;
                    if (packet_first) begin
                        meta_write_enable <= 1'b1;
                        meta_write_address <= {qp_index, tx_index[4:0]};
                        meta_write_data <= {next_psn, wqe_packet_count};
                        tx_started    <= 1'b1;
                    end
                    if (packet_last) begin
                        tx_index   <= tx_index + 16'd1;
                        tx_offset  <= 32'd0;
                        tx_started <= 1'b0;
                        if (wqe_is_read) reads_outstanding <= reads_outstanding + 5'd1;
                    end else
                        tx_offset <= tx_offset + {19'd0, chunk_length};
                    state <= REQ_WRITE_BACK;
                end
            end
            // ---------------- 收到响应包：分类 + 窗口检查
            REQ_RX_CLASSIFY: begin
                if (header.bad || !header.qp_valid || qpc_state(qp_context) != QPS_RTS) begin
                    state <= REQ_DRAIN;
                end else if (op_is_cnp(header.opcode)) begin
                    // CNP：不参与 PSN 逻辑（PSN 恒 0、没有 AETH），只上报。RP 侧（阶段 3）
                    // 会据此把该 QP 的速率降下来；现在只计数，务必别让它走下面的
                    // EVENT_READ_RESPONSE 分支——那个分支会用 psn=0 去推进退休指针。
                    event_rx_cnp    <= 1'b1;
                    event_rx_cnp_qp <= QP_NUM'(1) << qp_index;
                    state <= REQ_DRAIN;
                end else if (rx_retire_distance > 24'(next_psn - unacked_psn)) begin
                    state <= REQ_DRAIN;                                   // 过期或越界
                end else begin
                    event_kind <= rx_event_kind;
                    retire_psn    <= rx_retire_psn;
                    nak_syndrome <= header.aeth_syndrome;
                    if (rx_event_kind == EVENT_ACK) event_rx_ack <= 1'b1;
                    else if (rx_event_kind == EVENT_RNR_NAK) event_rx_rnr <= 1'b1;
                    else if (rx_event_kind != EVENT_READ_RESPONSE) event_rx_nak <= 1'b1;
                    state <= REQ_WALK_START;
                end
            end
            // ---------------- 从队头依次退休
            REQ_WALK_START: begin
                if (unacked_index == tx_index && !tx_started) begin                        // 没有在途 WQE
                    if (event_kind == EVENT_ACK && $signed(retire_psn - unacked_psn) > 0) unacked_psn <= retire_psn;
                    state <= (event_kind == EVENT_READ_RESPONSE) ? REQ_DRAIN : REQ_WRITE_BACK;
                end else begin
                    ram_read_address <= {qp_index, unacked_index[4:0]};
                    state     <= REQ_WALK_WAIT1;
                end
            end
            REQ_WALK_WAIT1: state <= REQ_WALK_WAIT2;
            REQ_WALK_WAIT2: state <= REQ_WALK_DECIDE;
            REQ_WALK_DECIDE: begin
                cqe_opcode    <= wc_opcode_of(wqe_opcode);
                cqe_length <= wqe_length;
                cqe_wqe_index   <= unacked_index;
                cqe_signaled   <= wqe_signaled;
                if ($signed(retire_psn - meta_psn_end) >= 0 && (unacked_index != tx_index)) begin   // 整个 WQE 都在门限前
                    if (wqe_is_read && recovering) begin                    // 已在重发，等进展或超时
                        state <= handling_rx ? REQ_DRAIN : REQ_WRITE_BACK;
                    end else if (wqe_is_read) begin                         // READ 的响应丢了
                        if (retry_left == 3'd0) begin
                            cqe_status <= WCS_RETRY_EXC; cqe_signaled <= 1'b1; local_error <= 1'b1;
                            qp_set_error[qp_index] <= 1'b1; cqe_return_state <= REQ_DRAIN; state <= REQ_CQE;
                        end else begin
                            retry_left <= retry_left - 3'd1; event_retransmit_nak <= 1'b1;
                            retire_psn   <= meta_psn_start;
                            state  <= REQ_RESTART;
                        end
                    end else begin
                        unacked_index  <= unacked_index + 16'd1;
                        unacked_psn <= meta_psn_end;
                        retry_left <= qpc_retry(qp_context); recovering <= 1'b0;
                        timer_restart[qp_index] <= 1'b1;
                        cqe_status  <= WCS_SUCCESS;
                        cqe_return_state <= REQ_WALK_START;
                        state   <= wqe_signaled ? REQ_CQE : REQ_WALK_START;
                    end
                end else case (event_kind)
                    EVENT_ACK: begin
                        if ($signed(retire_psn - unacked_psn) > 0) begin
                            unacked_psn <= retire_psn; retry_left <= qpc_retry(qp_context); timer_restart[qp_index] <= 1'b1;
                            recovering <= 1'b0;
                        end
                        state <= REQ_WRITE_BACK;
                    end
                    EVENT_NAK_SEQUENCE, EVENT_TIMEOUT: begin
                        if (event_kind == EVENT_NAK_SEQUENCE && recovering) begin
                            state <= REQ_WRITE_BACK;                 // 重发前发出的包引起的旧 NAK
                        end else if (retry_left == 3'd0) begin
                            cqe_status <= WCS_RETRY_EXC; cqe_signaled <= 1'b1; local_error <= 1'b1;
                            qp_set_error[qp_index] <= 1'b1; cqe_return_state <= REQ_WRITE_BACK; state <= REQ_CQE;
                        end else begin
                            retry_left <= retry_left - 3'd1;
                            if (event_kind == EVENT_TIMEOUT) event_retransmit_timeout <= 1'b1;
                            else               event_retransmit_nak <= 1'b1;
                            state <= REQ_RESTART;
                        end
                    end
                    EVENT_RNR_NAK: begin
                        unacked_psn <= retire_psn;
                        if (rnr_retry_left == 3'd0) begin
                            cqe_status <= WCS_RNR_RETRY_EXC; cqe_signaled <= 1'b1; local_error <= 1'b1;
                            qp_set_error[qp_index] <= 1'b1; cqe_return_state <= REQ_WRITE_BACK; state <= REQ_CQE;
                        end else begin
                            if (rnr_retry_left != 3'd7) rnr_retry_left <= rnr_retry_left - 3'd1;
                            rnr_waiting        <= 1'b1;
                            rnr_load[qp_index]  <= 1'b1;
                            rnr_load_value    <= rnr_timer_ticks(nak_syndrome[4:0]);
                            state          <= REQ_WRITE_BACK;
                        end
                    end
                    EVENT_RNR_DONE: state <= REQ_RESTART;
                    EVENT_NAK_ERROR: begin
                        cqe_status  <= (nak_syndrome == AETH_NAK_INV)    ? WCS_REM_INV_REQ :
                                (nak_syndrome == AETH_NAK_ACCESS) ? WCS_REM_ACCESS : WCS_REM_OP_ERR;
                        cqe_signaled <= 1'b1; local_error <= 1'b1; qp_set_error[qp_index] <= 1'b1;
                        cqe_return_state <= REQ_WRITE_BACK; state <= REQ_CQE;
                    end
                    default: begin                                   // EVENT_READ_RESPONSE
                        if (!wqe_is_read || retire_psn != unacked_psn) begin
                            if (wqe_is_read && $signed(retire_psn - unacked_psn) > 0 && retry_left != 3'd0 && !recovering) begin
                                retry_left <= retry_left - 3'd1; event_retransmit_nak <= 1'b1;
                                retire_psn   <= meta_psn_start;
                                cqe_return_state <= REQ_DRAIN;
                                state  <= REQ_RESTART;
                            end else
                                state <= REQ_DRAIN;
                        end else begin
                            translate_key <= wqe_lkey;
                            translate_virtual_address  <= wqe_local_address + ({8'd0, 24'(retire_psn - meta_psn_start)} << path_mtu_shift);
                            translate_length <= header.payload_length;
                            translate_access <= ACC_LOCAL_WRITE;
                            state     <= (header.payload_length != 13'd0) ? REQ_RESP_TRANSLATE : REQ_RESP_FINISH;
                        end
                    end
                endcase
            end
            // ---------------- go-back-N：从队头 WQE 内的 PSN retire_psn 重发（READ 从 unacked_psn 续读）
            REQ_RESTART: begin
                recovering <= 1'b1;
                tx_index   <= unacked_index;
                ack_counter <= 6'd0;
                timer_restart[qp_index] <= 1'b1;
                // tx_started=0 时重发的第一个包会按 FIRST 组包，因此只在偏移非 0 时置位；
                // 否则从消息头重发会被对端当作 MIDDLE（is_send_first 为假）回 NAK-Invalid。
                if (wqe_is_read) begin                      // 从第一个没收到的响应 PSN 续读（对端按重复 READ 重做）
                    next_psn <= unacked_psn;
                    tx_offset  <= {8'd0, 24'(unacked_psn - meta_psn_start)} << path_mtu_shift;
                    tx_started <= (unacked_psn != meta_psn_start);
                    reads_outstanding  <= 5'd0;            // 重发时 REQ_TX_PUSH 会再加 1
                end else begin
                    next_psn <= retire_psn;
                    tx_offset  <= {8'd0, 24'(retire_psn - meta_psn_start)} << path_mtu_shift;
                    tx_started <= (retire_psn != meta_psn_start);
                    reads_outstanding  <= 5'd0;
                end
                state <= REQ_WRITE_BACK;
            end
            // ---------------- READ RESP 数据写回本地 MR
            REQ_RESP_TRANSLATE:  if (translate_ready) state <= REQ_RESP_TRANSLATE_WAIT;
            REQ_RESP_TRANSLATE_WAIT: if (translate_response) begin
                       physical_address0 <= translate_physical_address0;
                       physical_page1 <= translate_physical_page1;
                       if (translate_error) begin
                           cqe_status <= WCS_LOC_PROT_ERR; cqe_signaled <= 1'b1; local_error <= 1'b1;
                           qp_set_error[qp_index] <= 1'b1; cqe_return_state <= REQ_DRAIN; state <= REQ_CQE;
                       end else
                           state <= REQ_RESP_WRITE_REQUEST;
                   end
            REQ_RESP_WRITE_REQUEST: begin
                       dma_write_request_valid <= 1'b1;
                       dma_write_request_address  <= physical_address0;
                       dma_write_request_page1 <= physical_page1;
                       dma_write_request_length   <= header.payload_length;
                       if (dma_write_request_valid && dma_write_request_ready) begin
                           dma_write_request_valid <= 1'b0;
                           state       <= REQ_RESP_WRITE_DATA;
                       end
                   end
            REQ_RESP_WRITE_DATA: if (rx_payload_valid && dma_write_ready && rx_payload_last) begin
                       payload_consumed <= 1'b1;
                       state       <= REQ_RESP_FINISH;
                   end
            REQ_RESP_FINISH: begin
                unacked_psn <= retire_psn + 24'd1;
                retry_left <= qpc_retry(qp_context);
                recovering <= 1'b0;
                timer_restart[qp_index] <= 1'b1;
                // 重发还没发出（tx_index 仍指向本 READ）时收到了迟到的原响应：重发起点跟着后移，
                // 本 READ 全部收齐则取消重发，保证 next_psn 不落在 unacked_psn 之前
                if (tx_index == unacked_index && tx_started) begin
                    if (retire_psn + 24'd1 == meta_psn_end) begin
                        tx_index   <= unacked_index + 16'd1;
                        tx_started <= 1'b0;
                        tx_offset  <= 32'd0;
                        next_psn   <= meta_psn_end;
                    end else begin
                        next_psn   <= retire_psn + 24'd1;
                        tx_offset  <= {8'd0, 24'(retire_psn + 24'd1 - meta_psn_start)} << path_mtu_shift;
                    end
                end
                if (retire_psn + 24'd1 == meta_psn_end) begin                        // 最后一个响应包
                    unacked_index  <= unacked_index + 16'd1;
                    reads_outstanding  <= (reads_outstanding != 5'd0) ? reads_outstanding - 5'd1 : 5'd0;
                    cqe_status  <= WCS_SUCCESS;
                    cqe_return_state <= REQ_WRITE_BACK;
                    state   <= wqe_signaled ? REQ_CQE : REQ_WRITE_BACK;
                end else
                    state <= REQ_WRITE_BACK;
            end
            // ---------------- CQE
            REQ_CQE: begin
                cqe_valid <= 1'b1;
                cqe_cq_index    <= qpc_scq(qp_context);
                cqe_data   <= {32'd0, cqe_length, 8'd0, 4'd0, qp_index,
                            16'(cqe_wqe_index & ((16'd1 << qpc_sq_lg(qp_context)) - 16'd1)),
                            1'b0, 13'd0, 1'b0, 1'b0, cqe_status, cqe_opcode};
                if (cqe_valid && cqe_ready) begin
                    cqe_valid <= 1'b0;
                    state      <= cqe_return_state;
                end
            end
            REQ_DRAIN: if (payload_consumed || (rx_payload_valid && rx_payload_last)) begin
                         payload_consumed <= 1'b1;
                         state       <= REQ_WRITE_BACK;
                     end
            REQ_WRITE_BACK: begin
                if (handling_rx && !payload_consumed) begin
                    state <= REQ_DRAIN;
                end else begin
                    qp_tx_index[qp_index]   <= tx_index;   qp_unacked_index[qp_index]  <= unacked_index;  qp_next_psn[qp_index] <= next_psn; qp_unacked_psn[qp_index] <= unacked_psn;
                    qp_tx_offset[qp_index]  <= tx_offset;  qp_tx_started[qp_index] <= tx_started; qp_retry_left[qp_index]  <= retry_left;  qp_rnr_retry_left[qp_index]  <= rnr_retry_left;
                    qp_reads_outstanding[qp_index]  <= reads_outstanding;  qp_ack_counter[qp_index] <= ack_counter; qp_local_error[qp_index] <= local_error; qp_rnr_waiting[qp_index] <= rnr_waiting;
                    qp_recovering[qp_index] <= recovering;
                    done <= handling_rx;
                    state   <= REQ_IDLE;
                end
            end
            default: state <= REQ_IDLE;
        endcase
    end
    assign debug_state = {tx_offset, 18'd0, ack_counter, unacked_psn, next_psn, qp_index,
                          local_error, recovering, reads_outstanding, {2'b00, retry_left},
                          {1'b0, dispatch_reason}, state};
endmodule
`default_nettype wire
