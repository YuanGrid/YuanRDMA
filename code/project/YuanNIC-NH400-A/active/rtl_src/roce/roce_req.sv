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
    parameter int CORE_CLOCK_MHZ = 250,
    // S4：本 lane 的编号。每 lane 只持有 global qp[LANE_BITS-1:0] == LANE_ID 的那些 QP（交错持有），
    // 用 qp_local() 做局部索引（QP_LW 位）；每 QP 阵列、候选向量、round-robin 全部在 LANE_QPS 位
    // 局部域里做，只有 QPC 读口地址 / 掩码输出回到全局域。
    // 注意：roce_engine 例化本模块时必须传 .LANE_ID(...)，否则所有实例都当 0 号 lane，
    // 其余 3/4 的 QP 无人服务（静默错误，不是编译错误）。
    parameter int LANE_ID = 0
)(
    input  wire                    clk,
    input  wire                    rst,
    input  wire  [31:0]            local_ip,       // S3：任务里的 IP 校验和静态部分要用
    // S3：QPC 不再以 QP_NUM×512 位组合总线输入，改读 roce_tbl 的 M20K 寄存读口（每口：给地址，
    // 下一拍出数据 + 产生数据的地址 + 读那一沿是否无写入）。口 0 = 主状态机，口 1 = 取指。
    output wire  [15:0]            qpc_rd0_addr,
    input  wire  [508:0]           qpc_rd0_data,
    input  wire  [15:0]            qpc_rd0_addr_q,
    input  wire                    qpc_rd0_fresh,
    output wire  [15:0]            qpc_rd1_addr,
    input  wire  [508:0]           qpc_rd1_data,
    input  wire  [15:0]            qpc_rd1_addr_q,
    input  wire                    qpc_rd1_fresh,
    input  wire  [QP_NUM*5-1:0]    qp_timeout_i,   // 每 QP 重传超时指数（定时器并行扫描用）
    input  wire  [QP_NUM*3-1:0]    qp_prio_i,      // 每 QP 优先级 = TOS[7:5]（PFC 准入用）
    input  wire  [511:0]           qpc_last_write, // 与 qp_state_change 同拍：触发它的那次 QPC 写入值
    output wire  [31:0]            debug_qp_context_low,   // 当前 QP 的 QPC dw0（roce_debug 0x0570 用）
    input  wire  [QP_NUM*3-1:0]    qp_state_i,     // QPC 的 [2:0] 单独引出，见 roce_tbl.sv
    input  wire  [QP_NUM-1:0]      qp_state_change,
    // S4：两个 one-hot 输出仍是全局 QP_NUM 位宽（roce_engine 按全局 QP 看），
    // 内部只有本 lane 的 LANE_QPS 位（qp_set_error_l / event_rx_cnp_qp_l），
    // 由文件下方 gen_global_out 用常量下标展开，其它 lane 的位恒 0。
    output wire  [QP_NUM-1:0]      qp_set_error,
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
    output reg   [CQ_W-1:0]        cqe_cq_index,
    // S（UD）：与 roce_resp 对齐，cqe_data 加宽到 160 bit（dw4 = src_qp/has_grh，全 0 for RC）。
    output reg   [159:0]           cqe_data,
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
    output wire  [QP_NUM-1:0]      event_rx_cnp_qp,     // 收到 CNP 的 QP（one-hot，与 event_rx_cnp 同拍）
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
    // S4（QP 128）：本 lane 只持有自己的 1/4 项（LANE_QPS = QP_NUM >> LANE_BITS = 32）。
    // 索引一律用 lane 局部位 qp[QP_W-1:LANE_BITS]，与 roce_pkg 的 qp_local() 等价。
    // **不能拿全局 qp_index 直接下标**：数组只有 32 项，128 的全局索引会回绕到别的 QP 上，
    // 是静默数据错（Verilator 只报 SELRANGE，-Wno-fatal 下不拦）。
    // 与 roce_resp 一致：索引写裸 part-select 而不是 qp_local(...)——Verilator 对
    // 「NBA 写 + 函数调用下标」偶发 Internal Error（V3MultipleWrite refs on LHS of NBA）。
    // 全局总线（qp_state_i / qp_state_change / qp_set_error / event_rx_cnp_qp）仍是 QP_NUM 位。
    reg  [LANE_QPS-1:0] qp_set_error_l;      // 本 lane 的置错 one-hot（S4）
    reg  [LANE_QPS-1:0] event_rx_cnp_qp_l;    // 本 lane 收到 CNP 的 QP one-hot（S4）
    genvar go;
    generate
        for (go = 0; go < QP_NUM; go = go + 1) begin : gen_global_out
            if (go % (1 << LANE_BITS) == LANE_ID) begin : gen_mine
                assign qp_set_error[go]    = qp_set_error_l[go >> LANE_BITS];
                assign event_rx_cnp_qp[go] = event_rx_cnp_qp_l[go >> LANE_BITS];
            end else begin : gen_other
                assign qp_set_error[go]    = 1'b0;
                assign event_rx_cnp_qp[go] = 1'b0;
            end
        end
    endgenerate

    // ------------------------------------------------------------ 主状态机拥有的每 QP 状态
    reg  [15:0] qp_tx_index   [LANE_QPS];    // 下一个要发的 WQE（SQ 索引）
    reg  [15:0] qp_unacked_index  [LANE_QPS];    // 最老未退休的 WQE
    reg  [23:0] qp_next_psn [LANE_QPS];
    reg  [23:0] qp_unacked_psn [LANE_QPS];
    reg  [31:0] qp_tx_offset  [LANE_QPS];    // qp_tx_index 这个 WQE 已发字节
    reg         qp_tx_started [LANE_QPS];    // qp_tx_index 这个 WQE 已发过首包（meta 已写）
    reg  [2:0]  qp_retry_left  [LANE_QPS];
    reg  [2:0]  qp_rnr_retry_left  [LANE_QPS];
    reg  [4:0]  qp_reads_outstanding  [LANE_QPS];    // 在途 READ 数
    reg  [5:0]  qp_ack_counter [LANE_QPS];
    reg         qp_local_error [LANE_QPS];
    reg         qp_rnr_waiting [LANE_QPS];    // 等 RNR 定时器
    reg         qp_recovering  [LANE_QPS];    // go-back-N 重发后尚无进展：忽略乱序响应/NAK，靠超时兜底

    // ------------------------------------------------------------ 取指逻辑拥有的状态
    reg  [15:0] qp_sq_producer [LANE_QPS];
    reg  [15:0] qp_fetch_issued [LANE_QPS];      // 已发出取指
    reg  [15:0] qp_fetch_done [LANE_QPS];      // 已取回

    // ------------------------------------------------------------ 片上 WQE 环与 meta
    (* ramstyle = "no_rw_check,m20k" *) reg [1023:0] wqe_ram  [LANE_QPS*WQE_SLOTS];
    (* ramstyle = "no_rw_check,m20k" *) reg [47:0]  meta_ram [LANE_QPS*WQE_SLOTS];
    // 片上 WQE 环地址 = {qp_local, slot[4:0]}，位宽随 QP_LW（QP_NUM=16 时 9 位，128 时 10 位）
    localparam int WQE_ADDR_W = QP_LW + 5;
    reg  [WQE_ADDR_W-1:0] ram_read_address;
    reg  [511:0] wqe_read_data;
    reg  [47:0]  meta_read_data;
    reg          meta_write_enable;
    reg  [WQE_ADDR_W-1:0] meta_write_address;
    reg  [47:0]  meta_write_data;
    reg          wqe_write_enable;
    reg  [WQE_ADDR_W-1:0] wqe_write_address;
    reg  [1023:0] wqe_write_data;
    always @(posedge clk) begin
        wqe_read_data  <= wqe_ram[ram_read_address];
        meta_read_data <= meta_ram[ram_read_address];
        if (wqe_write_enable)  wqe_ram[wqe_write_address]   <= wqe_write_data;   // WQE 是 64 B，高 512 位由 rd_align 的 keep 屏蔽、恒 0
        if (meta_write_enable) meta_ram[meta_write_address] <= meta_write_data;
    end

    // 取指在途 FIFO：记录每个读回拍属于哪个 QP（读数据按序返回）
    // S4：存的是 **lane 局部**下标（QP_LW 位），因为下游 qp_fetch_done / qp_fetch_issued
    // 都是 LANE_QPS 项。原来是 QP_W 位；QP_NUM=128 时拼进 WQE_ADDR_W=QP_LW+5=10 位会被截断，
    // 且 qp_fetch_done[fetch_owner_qp] 会用全局号索引 32 项阵列（静默回绕）。
    reg  [QP_LW-1:0] fetch_owner_fifo [64];
    reg  [6:0]  fetch_owner_write_pointer, fetch_owner_read_pointer;
    wire        fetch_owner_ready = (fetch_owner_write_pointer - fetch_owner_read_pointer) < 7'd64;
    wire [QP_LW-1:0] fetch_owner_qp = fetch_owner_fifo[fetch_owner_read_pointer[5:0]];

    // ------------------------------------------------------------ 取指 / 发送候选共用
    // S4：候选向量全部降到 lane 局部域（LANE_QPS=32 位），全局 QP_NUM=128 位只在端口上。
    // 局部下标 i 对应全局 QP = (i << LANE_BITS) | LANE_ID，是**编译期常量**，
    // 所以这里的 generate 全是连线，不产生逻辑级。
    localparam logic [PKG_LANE_W-1:0] LANE_IDX = PKG_LANE_W'(LANE_ID & ((1 << LANE_BITS) - 1));
    wire [LANE_QPS-1:0] qp_is_rts;
    genvar rts_gen;
    generate
        for (rts_gen = 0; rts_gen < LANE_QPS; rts_gen = rts_gen + 1) begin : gen_qp_is_rts
            localparam int GLOBAL_QP = (rts_gen << LANE_BITS) | LANE_ID;
            assign qp_is_rts[rts_gen] = (qp_state_i[GLOBAL_QP*3 +: 3] == QPS_RTS);
        end
    endgenerate

    // round-robin 选择：从 start 往上找第一个置位的下标，找不到再从 0 往上找。
    // 与原来「candidate 倒序扫、qp = (rr + candidate) % N、后写覆盖」的选择结果逐位相同。
    // S4：宽度从 QP_NUM(128) 降到 LANE_QPS(32)——128 位变址移位 + 双 128 位优先编码是
    // 约 15 级 LUT，在 core 250 MHz（B6439 slack 已 −0.09）上不可接受；32 位约 5 级。
    function automatic [QP_LW:0] rr_pick(input [LANE_QPS-1:0] cand, input [QP_LW-1:0] start);
        logic [LANE_QPS-1:0] upper;
        logic                found_upper, found_any;
        logic [QP_LW-1:0]    index_upper, index_any;
        upper       = cand & ~((LANE_QPS'(1) << start) - LANE_QPS'(1));
        found_upper = 1'b0;  index_upper = '0;
        found_any   = 1'b0;  index_any   = '0;
        for (int i = LANE_QPS - 1; i >= 0; i--) begin
            if (upper[i]) begin found_upper = 1'b1; index_upper = QP_LW'(i); end
            if (cand[i])  begin found_any   = 1'b1; index_any   = QP_LW'(i); end
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
    reg  [QP_LW-1:0] fetch_round_robin;
    reg  [LANE_QPS-1:0] fetch_eligible_q;
    reg         fetch_sel_valid;
    reg  [QP_LW-1:0] fetch_sel_qp;          // S4：lane 局部索引（全局 = {qp, LANE_IDX}）
    reg         fetch_req_valid;
    reg  [QP_LW-1:0] fetch_req_qp;
    reg  [63:0] fetch_req_address;
    reg         fetch_fired_d;
    reg  [QP_LW-1:0] fetch_fired_qp_d;

    always @(posedge clk) begin
        if (rst) fetch_eligible_q <= '0;
        else
            for (int lq = 0; lq < LANE_QPS; lq++)
                fetch_eligible_q[lq] <= (qp_fetch_issued[lq] != qp_sq_producer[lq]) &&
                                        ((qp_fetch_issued[lq] - qp_unacked_index[lq]) < 16'(WQE_SLOTS));
    end

    // S4：掩码在 lane 局部域做（32 位变址移位约 3 级），不再对 128 位做
    wire [LANE_QPS-1:0] fetch_busy = (fetch_sel_valid ? (LANE_QPS'(1) << fetch_sel_qp)     : LANE_QPS'(0)) |
                                     (fetch_req_valid ? (LANE_QPS'(1) << fetch_req_qp)     : LANE_QPS'(0)) |
                                     (fetch_fired_d   ? (LANE_QPS'(1) << fetch_fired_qp_d) : LANE_QPS'(0));
    wire [LANE_QPS-1:0] fetch_candidates = fetch_eligible_q & qp_is_rts & ~fetch_busy;
    wire        fetch_any;
    wire [QP_LW-1:0] fetch_pick;
    assign {fetch_any, fetch_pick} = rr_pick(fetch_candidates, fetch_round_robin);

    // S3：取指的 QPC 走读口 1（原来是 qpc 扁平总线按 fetch_sel_qp 做 512 位 × QP_NUM 选 1，
    // S3 要去掉的三处组合选路之一）。地址是寄存器 fetch_sel_qp，数据在它装进第 2 级的**下一拍**才
    // 对得上，fetch_qpc_ok 同时排除「读那一沿正好有 QPC 写入」（同沿读写结果未定义）。
    // 代价：第 2 级至少停 2 拍——单 QP 取指 4 → 5 拍/WQE、多 QP 交错 1 → 2 拍/WQE；
    // 每个 WQE 至少一包、每包 ≥ 9 拍，取指仍不在关键路径上（test_tx_path_profile 复测）。
    // S4 铁律：**读口地址与回传地址都是全局 QP 号**，局部索引只在内部用（{local,LANE_IDX} 拼接）。
    assign       qpc_rd1_addr   = 16'({fetch_sel_qp, LANE_IDX});
    wire [511:0] fetch_qpc      = {qpc_rd1_data, 3'd0};      // state 位不参与地址计算
    wire         fetch_qpc_ok   = qpc_rd1_fresh && (qpc_rd1_addr_q[QP_W-1:0] == {fetch_sel_qp, LANE_IDX});
    function automatic [63:0] fetch_wqe_address(input [511:0] qpc_ctx, input [15:0] issued);
        fetch_wqe_address = qpc_sq_base(qpc_ctx) +
            {42'd0, issued & ((16'd1 << qpc_sq_lg(qpc_ctx)) - 16'd1), 6'd0};
    endfunction

    wire        fetch_fire     = fetch_req_valid && dma_read_request_ready;
    wire        fetch_move     = fetch_sel_valid && fetch_owner_ready && fetch_qpc_ok &&
                                 (!fetch_req_valid || dma_read_request_ready);
    wire        fetch_sel_load = fetch_any && (!fetch_sel_valid || fetch_move);

    assign dma_read_request_valid = fetch_req_valid;
    assign dma_read_request_address  = fetch_req_address;
    assign dma_read_request_page1 = fetch_req_address + 64'd4096;
    assign dma_read_request_length   = 13'd64;
    assign dma_read_ready = 1'b1;

    always @(posedge clk) begin
        if (rst) begin
            fetch_sel_valid   <= 1'b0;
            fetch_sel_qp      <= {QP_LW{1'b0}};
            fetch_req_valid   <= 1'b0;
            fetch_req_qp      <= {QP_LW{1'b0}};
            fetch_req_address <= 64'd0;
            fetch_fired_d     <= 1'b0;
            fetch_fired_qp_d  <= {QP_LW{1'b0}};
        end else begin
            fetch_fired_d    <= fetch_fire;
            fetch_fired_qp_d <= fetch_req_qp;
            // 第 3 级：fetch_move 时装上第 2 级的 QP（同拍旧请求若握手，move 的条件已包含 ready）
            if (fetch_move) begin
                fetch_req_valid   <= 1'b1;
                fetch_req_qp      <= fetch_sel_qp;
                fetch_req_address <= fetch_wqe_address(fetch_qpc, qp_fetch_issued[fetch_sel_qp]);
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
        if (doorbell_sq_valid) qp_sq_producer[doorbell_data[QP_W-1:LANE_BITS]] <= doorbell_data[31:16];   // 门铃 [7:0] = qp_idx（S4：取 lane 局部位；roce_engine 的 owns_doorbell_qp 保证只到属主 lane）
        if (rst) begin
            fetch_round_robin    <= '0;
            fetch_owner_write_pointer <= '0;
            fetch_owner_read_pointer <= '0;
            // 取指三兄弟只在本块里驱动（门铃写 producer、取指自增 issued、取回自增 done），
            // 所以清零也必须留在这里。主状态机块里再清一次会触发 Quartus
            //   Error (13264): Can't resolve multiple constant drivers
            // ——2026-10-25 B6371 首次编译就栽在这上面。
            for (int lq = 0; lq < LANE_QPS; lq++) begin
                qp_sq_producer[lq]  <= 16'd0;
                qp_fetch_issued[lq] <= 16'd0;
                qp_fetch_done[lq]   <= 16'd0;
            end
        end else begin
            if (fetch_fire) begin
                // 握手在第三级完成：owner 记录发给 DMA 的那个 QP，自增它的 issued。
                // round-robin 也在这里推进。下一拍该 QP 由 fetch_fired_d 挡住（资格位还是自增前的），
                // 再下一拍资格位已按自增后的 issued 重算。
                fetch_owner_fifo[fetch_owner_write_pointer[5:0]] <= fetch_req_qp;
                fetch_owner_write_pointer <= fetch_owner_write_pointer + 7'd1;
                qp_fetch_issued[fetch_req_qp] <= qp_fetch_issued[fetch_req_qp] + 16'd1;
                fetch_round_robin <= fetch_req_qp + QP_LW'(1);
            end
            if (dma_read_valid) begin
                wqe_write_enable       <= 1'b1;
                wqe_write_address       <= {fetch_owner_qp, qp_fetch_done[fetch_owner_qp][4:0]};
                wqe_write_data       <= dma_read_data;
                qp_fetch_done[fetch_owner_qp]    <= qp_fetch_done[fetch_owner_qp] + 16'd1;
                fetch_owner_read_pointer       <= fetch_owner_read_pointer + 7'd1;
            end
        end
        // S4：只遍历本 lane 的 32 项。全局号 = (lq << LANE_BITS) | LANE_ID 是**常量表达式**，
        // 对全局总线 qp_state_change / qp_state_i 的切片因此保持静态（不产生变址逻辑）。
        for (int lq = 0; lq < LANE_QPS; lq++) begin
            if (qp_state_change[(lq << LANE_BITS) | LANE_ID] &&
                qp_state_i[((lq << LANE_BITS) | LANE_ID)*3 +: 3] <= QPS_INIT) begin
                qp_sq_producer[lq] <= 16'd0;
                qp_fetch_issued[lq] <= 16'd0;
                qp_fetch_done[lq] <= 16'd0;
            end
        end
    end

    // ------------------------------------------------------------ 定时器（4.096 us 一拍，按 CORE_CLOCK_MHZ 分频）
    localparam int TICK_CYCLES = (CORE_CLOCK_MHZ * 4096 + 500) / 1000;   // 4.096 us
    reg  [11:0] tick_divider;
    wire        timer_tick = (tick_divider == 12'd0);
    // S4：定时器阵列与两个触发向量全部降到 lane 局部域（LANE_QPS=32 项）。
    // 全局 QP 号只在遍历 qp_timeout_i（每 lane 一份、按**全局**下标展开的总线）时用常量拼出来。
    reg  [20:0] qp_timer [LANE_QPS];
    reg  [LANE_QPS-1:0] timer_restart;             // 主状态机发出：有进展/重传（lane 局部）
    reg  [17:0] qp_rnr_countdown [LANE_QPS];
    reg  [LANE_QPS-1:0] rnr_load;
    reg  [17:0] rnr_load_value;
    wire [LANE_QPS-1:0] timer_expired, rnr_expired;
    always @(posedge clk) begin
        tick_divider <= (rst || tick_divider == 12'(TICK_CYCLES - 1)) ? 12'd0 : tick_divider + 12'd1;
        for (int lq = 0; lq < LANE_QPS; lq++) begin
            if (timer_restart[lq] || qp_unacked_psn[lq] == qp_next_psn[lq])
                qp_timer[lq] <= 21'd0;
            else if (timer_tick && !qp_timer[lq][20])
                qp_timer[lq] <= qp_timer[lq] + 21'd1;
            if (rnr_load[lq])
                qp_rnr_countdown[lq] <= rnr_load_value;
            else if (timer_tick && qp_rnr_countdown[lq] != 18'd0)
                qp_rnr_countdown[lq] <= qp_rnr_countdown[lq] - 18'd1;
        end
    end
    genvar qp_gen;
    generate
        for (qp_gen = 0; qp_gen < LANE_QPS; qp_gen = qp_gen + 1) begin : gen_timer
            // 局部下标 qp_gen ↔ 全局 QP 号 (qp_gen << LANE_BITS) | LANE_ID，编译期常量
            localparam int GLOBAL_QP = (qp_gen << LANE_BITS) | LANE_ID;
            wire [4:0] timeout_exponent = qp_timeout_i[GLOBAL_QP*5 +: 5];
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
    reg  [LANE_QPS-1:0] tx_eligible_q;     // S4：lane 局部域（32 位）
    // PFC 准入（2026-11-09）：每个 QP 按 QPC 的 TOS[7:5] 选优先级，被 pause 的优先级不派发新 WQE。
    //   rx_pfc[8] 是 802.3x 全局 pause，挡住所有优先级；rx_pfc[7:0] 是 per-priority，
    //   受控注入已证明 F-tile 逐帧产出（见 PFC/DCQCN 文档 §12）。
    // 只挡「新 WQE 派发」：已开始的包（REQ_TX_*）发完，ACK/NAK/READ RESP 由 roce_resp 直接出，不受影响。
    // 优先级 = TOS[7:5] = DSCP[5:3]（与 QDMA 路径 pfc_parser 的 IPv4 分类同口径）。
    //   qpc_tos 在 dw7[23:16]，即 qpc[7*32+16 +: 8]（roce_pkg::qpc_tos），其 [7:5] 直接位选 qpc[7*32+16+5 +: 3]。
    // 与 tx_eligible_q 同拍寄存，选路逻辑上只多一个 QP_NUM 位的与。
    reg  [LANE_QPS-1:0] tx_pfc_blocked_q;  // S4：lane 局部域（32 位）
    always @(posedge clk) begin
        if (rst) tx_pfc_blocked_q <= '0;
        else
            // S4：lane 局部域（32 项）；rx_pfc / qp_prio_i 是全局展开的总线，用常量号取
            for (int lq = 0; lq < LANE_QPS; lq++)
                tx_pfc_blocked_q[lq] <= pfc_gate_enable &&
                                        (rx_pfc[8] || rx_pfc[qp_prio_i[((lq << LANE_BITS) | LANE_ID)*3 +: 3]]);
    end
    always @(posedge clk) begin
        if (rst) tx_eligible_q <= '0;
        else
            for (int lq = 0; lq < LANE_QPS; lq++)
                tx_eligible_q[lq] <= (qp_fetch_done[lq] != qp_tx_index[lq]) && !qp_local_error[lq] &&
                                     !qp_rnr_waiting[lq] &&
                                     (24'(qp_next_psn[lq] - qp_unacked_psn[lq]) < 24'd2048) &&
                                     tx_rate_ready[(lq << LANE_BITS) | LANE_ID] &&
                                     !tx_pfc_blocked_q[lq];
    end

    reg  [QP_LW-1:0] tx_round_robin;       // S4：lane 局部轮转
    reg         tx_writeback_d;            // 上一拍在 REQ_WRITE_BACK（qp_index 的每 QP 状态刚写回）
    wire        tx_any;
    wire [QP_LW-1:0] tx_pick;

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
    // B6501：寄存器只存 **lane 局部索引**（QP_LW=5 位），全局 qp_index 由常量 LANE_IDX 现拼。
    //   原因：qp_index[LANE_BITS-1:0] 在四个写点全部恒等于 LANE_IDX——
    //     rx_header.qp_index（roce_rx_qpn_split 按 qp_index[LANE_W-1:0] 分发，只送到属主 lane）、
    //     超时/RNR 扫描（(lq << LANE_BITS) | LANE_ID）、tx_pick（{tx_pick, LANE_IDX}）。
    //   所以低 2 位每 lane 两个 flop 是恒定值，却在 STA 里以 _Duplicate 副本跨区布线
    //   （qp_index[1] 副本 → Mux_101，−0.310）。改成局部寄存器后这 4 个 flop 与全部副本消失，
    //   宽 mux 的支路数也少两个常量支路；下游读写点语义逐位不变。
    //   另外 qp_lidx 直接是寄存器的全部，索引/移位不再从 7 位里截 5 位，少一层位选。
    reg  [QP_LW-1:0] qp_lidx;
    // 全局号只在端口/编码边界出现一次：QPC 读口地址、tx_job、UD deth_src_qp、CQE、debug。
    wire [QP_W-1:0]  qp_index = {qp_lidx, LANE_IDX};
    reg  [511:0] qp_context;
    // S3：qp_context 仍是「本包处理期间不变」的 QPC 快照，装载分两段：
    //   REQ_LOAD 拍装 [2:0]（state，寄存器镜像，与原组合读同拍同值）并置 ctx_pending；
    //   读口 0 的地址恒为 qp_index（寄存器），LOAD 那一沿读出，下一拍（LOAD 之后第一个状态）
    //   数据到达即装 [511:3]。LOAD 之后的第一个状态（TX_ADDRESS / RX_CLASSIFY / WALK_START）
    //   都只用 [2:0]，[511:3] 最早在第二个状态才被用到，所以正常情况下**不增加拍数**。
    //   只有那一沿正好有主机 QPC 写入（rd0_fresh=0）时原地多停一拍重读。
    reg          ctx_pending;
    wire         ctx_ready = qpc_rd0_fresh && (qpc_rd0_addr_q[QP_W-1:0] == qp_index);
    assign       qpc_rd0_addr = 16'(qp_index);
    assign       debug_qp_context_low = qp_context[31:0];
    rx_hdr_t     header;
    reg  [2:0]   event_kind;
    reg  [23:0]  retire_psn;            // 退休门限：结束 PSN <= retire_psn 的 WQE 退休
    // B6503 簇 A：meta_ram 读出的**派生量**寄存版，供 walk/restart/resp_finish 用。
    //   原写法里 meta_psn_end = meta_psn_start + meta_packet_count 是纯组合 wire，直接在
    //   REQ_WALK_DECIDE 里参与 retire_psn - meta_psn_end 与 retire_psn + 1 == meta_psn_end，
    //   于是 M20K 输出 → 24 位加法 → 24 位减法/比较 → 状态机下态 mux 全在一拍内完成
    //   （B6502 STA 最差路径 10.182 ns > 4 ns 周期，−0.228）。修法：walk 路径上 REQ_WALK_WAIT2
    //   那一拍原本只是空转（等 M20K 读出），在那一拍把 start / count / end 寄存下来，
    //   判定拍就只剩一级减法和符号判断。**不增加拍数**（WAIT1/WAIT2 本来就在）。
    //   语义不变：ram_read_address 自 REQ_WALK_START 写入后，到 REQ_RESP_FINISH 之间不再改写
    //   （TX 取指与 walk 不会交错），寄存版与读出值逐位相同。REQ_TX_COMPUTE 仍用原组合
    //   wire —— 那条路径只取 [23:0]/[47:24] 的位选，不含加法，且 TX 侧没有空拍可利用。
    reg  [23:0]  meta_psn_start_q;      // REQ_WALK_WAIT2 采样的 WQE 起始 PSN
    reg  [23:0]  meta_psn_end_q;        // 同上，起始 PSN + 包数（已在 WAIT2 算好）
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
    //   见调试记录 §44.3）；多 QP 时 round-robin 能选别的 QP 填上，所以只伤单 QP。
    //   REQ_WRITE_BACK 那拍状态机工作副本（tx_index / next_psn / unacked_psn / local_error / rnr_waiting）
    //   就是要写进 qp_* 的值（同一 always 块里写回排在 qp_state_change 之后，同拍写回优先），
    //   所以在那拍寄存 tx_self_eligible_q，下一拍 IDLE 用它代替 tx_eligible_q[qp_index]——
    //   与 tx_eligible_q 两拍后按写回值重算的结果逐位一致，不会重复派发。
    //   qp_fetch_done[qp_lidx] 先寄存一拍（fetch_done_current）：只增不减，晚 1 拍是保守的；
    //   qp_index 从 REQ_LOAD 到 REQ_WRITE_BACK 都不变，寄存值在写回那拍已对准本 QP。
    //   全是寄存器项，16 路选路不进比较器，不重新引入 B6416 的扫描关键路径。
    reg  [15:0] fetch_done_current;
    reg         tx_self_eligible_q;
    always @(posedge clk) begin
        fetch_done_current <= qp_fetch_done[qp_lidx];
        // PFC 门控也要挡这条旁路：它替代的是 tx_eligible_q[qp_index]，若不带
        // !tx_pfc_blocked_q[qp_index]，每次 pause 都会从旁路多放一个包出去。
        tx_self_eligible_q <= (fetch_done_current != tx_index) && !local_error && !rnr_waiting &&
                              (24'(next_psn - unacked_psn) < 24'd2048) &&
                              tx_rate_ready[qp_index] &&
                              !tx_pfc_blocked_q[qp_lidx];
    end
    // S4：候选向量在 lane 局部域拼（32 位变址移位），qp_index 的低 LANE_BITS 位恒等于 LANE_ID
    wire [LANE_QPS-1:0] tx_writeback_mask = tx_writeback_d ? (LANE_QPS'(1) << qp_lidx)
                                                           : LANE_QPS'(0);
    wire [LANE_QPS-1:0] tx_candidates = ((tx_eligible_q & ~tx_writeback_mask) |
                                       (tx_self_eligible_q ? tx_writeback_mask : LANE_QPS'(0))) & qp_is_rts;
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
    // UD（WQE_UD_SEND / WQE_UD_SEND_IMM）从 rsvd[7] 区取两个新字段（sq_wqe_layout 契约）：
    //   dw9[23:0]  = remote_qpn  → BTH Dest QP（UD 的目的 QPN，与 RC 的 QPC dqpn 无关）
    //   dw10[31:0] = remote_qkey → DETH Q_Key（主机序）
    // 这两片在 RC 下恒 0（provider 写 0），不影响既有 RC 路径。
    wire [23:0]  wqe_ud_qpn  = wqe_read_data[9*32 +: 24];
    wire [31:0]  wqe_ud_qkey = wqe_read_data[10*32 +: 32];
    wire         wqe_is_read   = (wqe_opcode == WQE_READ);
    // UD 发送：不分片、单包、无 ACK/PSN。WQE 编码 5/6（roce_pkg），线上 opcode 0x64/0x65。
    wire         wqe_is_ud     = (wqe_opcode == WQE_UD_SEND) || (wqe_opcode == WQE_UD_SEND_IMM);
    wire [3:0]   path_mtu_shift  = 4'(qpc_pmtu(qp_context)) + 4'd7;
    wire [12:0]  path_mtu   = pmtu_bytes(qpc_pmtu(qp_context));
    wire [23:0]  meta_psn_start = meta_read_data[47:24];
    wire [23:0]  meta_packet_count  = meta_read_data[23:0];
    // B6503 簇 A：原来这里还有 meta_psn_end 这个组合 wire（= meta_psn_start + meta_packet_count），
    //   被 REQ_WALK_DECIDE / REQ_RESTART / REQ_RESP_FINISH 消费。现在这三处的消费者一律读
    //   寄存版 meta_psn_end_q（在 REQ_WALK_WAIT2 打拍），故组合 wire 删除。留着只会被
    //   lint 与综合工具会报 unused，并且诱使后来者再接回关键路径。
    wire [31:0]  tx_remaining     = wqe_length - tx_offset;
    wire [23:0]  first_packet_count = (wqe_length == 32'd0) ? 24'd1 : 24'((wqe_length + {19'd0, path_mtu} - 32'd1) >> path_mtu_shift);

    function automatic [7:0] wc_opcode_of(input [3:0] wqe_op);
        // UD 也报 WC_SEND（IBV_WC_SEND）——落进下面的默认分支即可，
        // 这里显式写一行是为了让「UD 的完成码是 SEND、不是 WRITE/READ」在代码里可见。
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
            // UD 只有一个包（IBTA §9.8.5 的 SEND_ONLY 形态）：不看 is_first/is_last，
            // 恒 0x64/0x65。不做 FIRST/MIDDLE/LAST——UD 没有分片重组语义。
            WQE_UD_SEND:     tx_opcode_of = OP_SEND_ONLY_UD;
            WQE_UD_SEND_IMM: tx_opcode_of = OP_SEND_ONLY_UD_IMM;
            default:       tx_opcode_of = OP_READ_REQ;
        endcase
    endfunction

    // B6439：本包 opcode（REQ_TX_PUSH 拍不变），派生长度全部由它派生
    wire [7:0]  push_opcode = tx_opcode_of(wqe_opcode, packet_first, packet_last);

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
        qp_set_error_l          <= '0;
        timer_restart         <= '0;
        rnr_load          <= '0;
        meta_write_enable         <= 1'b0;
        event_rx_ack       <= 1'b0;
        event_rx_nak       <= 1'b0;
        event_rx_rnr       <= 1'b0;
        event_rx_cnp       <= 1'b0;
        event_rx_cnp_qp_l  <= '0;
        event_retransmit_timeout <= 1'b0;
        event_retransmit_nak     <= 1'b0;
        // S4：只遍历本 lane 的 32 项；全局号 (lq<<LANE_BITS)|LANE_ID 是常量表达式，
        // 对 qp_state_change / qp_state_i 的访问仍为静态切片。
        for (int lq = 0; lq < LANE_QPS; lq++)
            if (qp_state_change[(lq << LANE_BITS) | LANE_ID]) begin
                if (qp_state_i[((lq << LANE_BITS) | LANE_ID)*3 +: 3] <= QPS_INIT) begin
                    qp_tx_index[lq] <= 16'd0; qp_unacked_index[lq] <= 16'd0; qp_tx_offset[lq] <= 32'd0; qp_tx_started[lq] <= 1'b0;
                    qp_reads_outstanding[lq] <= 5'd0; qp_ack_counter[lq] <= 6'd0; qp_local_error[lq] <= 1'b0; qp_rnr_waiting[lq] <= 1'b0; qp_recovering[lq] <= 1'b0;
                end
                // S3：qp_state_change 只由主机写 QPC 产生、一次一个 QP，与 qpc_last_write 同拍有效
                qp_next_psn[lq] <= qpc_sq_psn(qpc_last_write);
                qp_unacked_psn[lq] <= qpc_sq_psn(qpc_last_write);
                qp_retry_left[lq]  <= qpc_retry(qpc_last_write);
                qp_rnr_retry_left[lq]  <= qpc_rnr_rty(qpc_last_write);
            end
        tx_writeback_d <= !rst && (state == REQ_WRITE_BACK);
        if (!rst && ctx_pending && ctx_ready) begin
            qp_context[511:3] <= qpc_rd0_data;
            ctx_pending       <= 1'b0;
        end
        if (rst) begin
            state       <= REQ_IDLE;
            ctx_pending <= 1'b0;
            // B6503 簇 A：meta 派生量的寄存版也归零。功能上它们每进一次 REQ_WALK_WAIT2 就重装，
            // 且所有消费者都在那次重装之后；这里清只是为了让复位后的波形/仿真初值确定
            // （Quartus 若不允许多个初值会给上电值，波形上难分辨）。
            meta_psn_start_q    <= 24'd0;
            meta_psn_end_q      <= 24'd0;
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
            for (int lq = 0; lq < LANE_QPS; lq++) begin     // S4：lane 局部域
                qp_tx_index[lq]        <= 16'd0;
                qp_unacked_index[lq]   <= 16'd0;
                qp_next_psn[lq]        <= 24'd0;
                qp_unacked_psn[lq]     <= 24'd0;
                qp_tx_offset[lq]       <= 32'd0;
                qp_tx_started[lq]      <= 1'b0;
                qp_retry_left[lq]      <= 3'd7;
                qp_rnr_retry_left[lq]  <= 3'd7;
                qp_reads_outstanding[lq] <= 5'd0;
                qp_ack_counter[lq]     <= 6'd0;
                qp_local_error[lq]     <= 1'b0;
                qp_rnr_waiting[lq]     <= 1'b0;
                qp_recovering[lq]      <= 1'b0;
                // qp_sq_producer / qp_fetch_issued / qp_fetch_done 不在这里清：
                // 它们只由上面的取指块驱动，两个时钟块同时赋值会触发
                // Error (13264) Can't resolve multiple constant drivers。
            end
        end else if (ctx_pending && !ctx_ready) begin
            // 读口数据不可用（只在读那一沿撞上 QPC 写时发生）：整个状态机停一拍，下一拍重读
        end else case (state)
            REQ_IDLE: begin
                if (rx_header_valid && !rx_header_ready && !(tx_any && prefer_tx)) begin
                    rx_header_ready <= 1'b1;
                    header       <= rx_header;
                    qp_lidx       <= rx_header.qp_index[QP_W-1:LANE_BITS];
                    dispatch_reason     <= 2'd1;
                    prefer_tx    <= 1'b1;
                    state      <= REQ_LOAD;
                end else if (|timer_expired) begin
                    // S4/B6501：lane 局部遍历，选中的就是局部下标本身（全局号读时才拼 LANE_IDX）
                    for (int lq = LANE_QPS - 1; lq >= 0; lq--)
                        if (timer_expired[lq]) qp_lidx <= QP_LW'(lq);
                    dispatch_reason <= 2'd2;
                    state  <= REQ_LOAD;
                end else if (|rnr_expired) begin
                    for (int lq = LANE_QPS - 1; lq >= 0; lq--)
                        if (rnr_expired[lq]) qp_lidx <= QP_LW'(lq);
                    dispatch_reason <= 2'd3;
                    state  <= REQ_LOAD;
                end else if (tx_any) begin
                    // S4：tx_pick 就是 lane 局部下标，直接寄存；全局号由 {qp_lidx, LANE_IDX} 现拼
                    qp_lidx  <= tx_pick;
                    tx_round_robin <= tx_pick + QP_LW'(1);
                    dispatch_reason <= 2'd0;
                    prefer_tx <= 1'b0;
                    state  <= REQ_LOAD;
                end
            end
            REQ_LOAD: begin
                qp_context[2:0] <= qp_state_i[qp_index*3 +: 3];
                ctx_pending     <= 1'b1;
                tx_index   <= qp_tx_index[qp_lidx];   unacked_index  <= qp_unacked_index[qp_lidx];  next_psn <= qp_next_psn[qp_lidx]; unacked_psn <= qp_unacked_psn[qp_lidx];
                tx_offset  <= qp_tx_offset[qp_lidx];  tx_started <= qp_tx_started[qp_lidx]; retry_left  <= qp_retry_left[qp_lidx];  rnr_retry_left  <= qp_rnr_retry_left[qp_lidx];
                reads_outstanding  <= qp_reads_outstanding[qp_lidx];  ack_counter <= qp_ack_counter[qp_lidx]; local_error <= qp_local_error[qp_lidx]; rnr_waiting <= qp_rnr_waiting[qp_lidx];
                recovering <= qp_recovering[qp_lidx];
                handling_rx  <= (dispatch_reason == 2'd1);
                payload_consumed <= (dispatch_reason != 2'd1) || (header.payload_length == 13'd0);
                case (dispatch_reason)
                    2'd0: state <= REQ_TX_ADDRESS;
                    2'd1: state <= REQ_RX_CLASSIFY;
                    2'd2: begin event_kind <= EVENT_TIMEOUT;  retire_psn <= qp_unacked_psn[qp_lidx]; state <= REQ_WALK_START; end
                    default: begin event_kind <= EVENT_RNR_DONE; retire_psn <= qp_unacked_psn[qp_lidx]; rnr_waiting <= 1'b0; state <= REQ_WALK_START; end
                endcase
            end
            // ---------------- 发送一个包
            REQ_TX_ADDRESS:  begin ram_read_address <= {qp_lidx, tx_index[4:0]}; state <= REQ_TX_WAIT; end
            REQ_TX_WAIT:  state <= REQ_TX_COMPUTE;
            REQ_TX_COMPUTE:  begin
                if (local_error || qpc_state(qp_context) != QPS_RTS) begin
                    state <= REQ_WRITE_BACK;
                /* QP 类型校验（G2.1）：WQE opcode 是 UD 就必须发在 UD QP 上，反之亦然。
                 * 只看 WQE opcode 不够——驱动侧已没有 UD/RC 开关（2026-11-21 起），运行期全靠这一位：
                 * RC QP 里混一条 UD WQE 会直接发出 0x64（对端若按 RC 解释就是未知 opcode）；
                 * UD QP 里混 RC WQE 则会把 UD 的「无 ACK/无 PSN」语义带进 RC 的重传逻辑。
                 * 报 Local Operation Error 并置 QP error，与下面的长度闸同形。 */
                end else if (wqe_is_ud != qpc_is_ud(qp_context)) begin
                    cqe_status <= WCS_LOC_OP_ERR; cqe_wqe_index <= tx_index; cqe_opcode <= wc_opcode_of(wqe_opcode);
                    cqe_length <= 32'd0; cqe_signaled <= 1'b1; local_error <= 1'b1;
                    qp_set_error_l[qp_lidx] <= 1'b1;
                    cqe_return_state <= REQ_WRITE_BACK;
                    state   <= REQ_CQE;
                /* UD 只在「本 QP 没有未退休的 RC WQE」时才允许就地退休。
                 * UD 没有 ACK，发包当拍就要推进 unacked_index（否则本 WQE 永远停在未退休窗口）；
                 * 但若同一个 SQ 里前面还有未 ACK 的 RC WQE，这一推会让 unacked_index 越过它，
                 * 该 RC WQE 的 CQE 之后才按 cursor_wqe_index 报出——**顺序反了**，而 provider
                 * 的 sq_consumer 是按 CQE 的 wqe_index 跳跃推进的，会把中间 WQE 一次性全退休。
                 * 判据：unacked_index == tx_index 表示「此前发出的都已被 ACK 退休」。
                 * 这只是一个运行期兜底，正解仍是「UD QP 只发 UD WQE」（上面的类型闸已保证）。 */
                end else if (wqe_is_ud && (unacked_index != tx_index)) begin
                    cqe_status <= WCS_LOC_OP_ERR; cqe_wqe_index <= tx_index; cqe_opcode <= wc_opcode_of(wqe_opcode);
                    cqe_length <= 32'd0; cqe_signaled <= 1'b1; local_error <= 1'b1;
                    qp_set_error_l[qp_lidx] <= 1'b1;
                    cqe_return_state <= REQ_WRITE_BACK;
                    state   <= REQ_CQE;
                end else if (wqe_is_ud && (wqe_length > {19'd0, path_mtu})) begin
                    // UD 只能单包：WQE length 超过 path_mtu 时**不能切包**（UD 没有 FIRST/MIDDLE/LAST，
                    // 对端也不会重组），必须按 §IBTA C9-96 报 Local Length Error。
                    // RC 之所以不需要这道闸，是因为 REQ_TX_COMPUTE 的 chunk_length 恒 <= path_mtu，
                    // 切包本身就保证了单包不超 MTU；UD 走同一段代码却只发一包，所以必须单独挡。
                    // 与 translate_error 的处理同形：出错误 CQE + 置 QP error + local_error 兜住本 QP
                    // 后续所有 WQE（下次进本状态走第一个分支直接 WRITE_BACK）。
                    cqe_status <= WCS_LOC_LEN_ERR; cqe_wqe_index <= tx_index; cqe_opcode <= wc_opcode_of(wqe_opcode);
                    cqe_length <= 32'd0; cqe_signaled <= 1'b1; local_error <= 1'b1;
                    qp_set_error_l[qp_lidx] <= 1'b1;
                    cqe_return_state <= REQ_WRITE_BACK;
                    state   <= REQ_CQE;
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
                            qp_set_error_l[qp_lidx] <= 1'b1;
                            cqe_return_state <= REQ_WRITE_BACK;
                            state   <= REQ_CQE;
                        end else
                            state <= REQ_TX_PUSH;
                    end
            REQ_TX_PUSH:  begin
                tx_job_valid           <= 1'b1;
                tx_job             <= '0;
                tx_job.qp_index          <= qp_index;
                tx_job.opcode      <= push_opcode;
                // UD 不参与 PSN 逻辑（无 ACK、无重传、无 RNR）：PSN 字段恒 0、AckReq 恒 0。
                // BTH 的 AckReq 位对 UD 无意义（对端不会回 ACK），置 1 只会让对端丢弃/报错。
                tx_job.psn         <= wqe_is_ud ? 24'd0 : next_psn;
                tx_job.ack_request      <= !wqe_is_ud && (packet_last || (ack_counter == 6'd63));
                tx_job.solicited          <= packet_last && wqe_solicited;
                tx_job.reth_virtual_address     <= wqe_remote_address + (wqe_is_read ? {32'd0, tx_offset} : 64'd0);   // READ 重发从断点续读
                tx_job.reth_rkey   <= wqe_rkey;
                tx_job.reth_length    <= wqe_length - (wqe_is_read ? tx_offset : 32'd0);
                tx_job.immediate         <= wqe_immediate;
                tx_job.payload_length         <= chunk_length;
                // B6439：派生长度在任务产生时算好（与 roce_tx 内旧的组合写法逐位等价）
                tx_job.header_length    <= tx_header_length(push_opcode);
                tx_job.header_skip      <= 7'd128 - tx_header_length(push_opcode);
                tx_job.ip_total_length  <= tx_ip_total_length(push_opcode, chunk_length);
                tx_job.frame_length     <= tx_frame_length(push_opcode, chunk_length);
                // §70：G0.1 加派生长度时把这行替换掉了，载荷首地址恒 0（B6439 上板带宽腰斩）
                tx_job.physical_address0      <= physical_address0;
                tx_job.physical_page1         <= physical_page1;
                // S3：组头字段随任务带给 roce_tx（qp_context 在 REQ_LOAD 已装载、本拍稳定）
                tx_job.tos       <= qpc_tos(qp_context);
                tx_job.ttl       <= qpc_ttl(qp_context);
                tx_job.dmac      <= qpc_dmac(qp_context);
                tx_job.dip       <= qpc_dip(qp_context);
                tx_job.sport     <= qpc_sport(qp_context);
                tx_job.dqpn      <= wqe_is_ud ? wqe_ud_qpn : qpc_dqpn(qp_context);
                tx_job.csum_base <= ip_csum_base(qpc_dip(qp_context), qpc_ttl(qp_context), local_ip);
                // UD 的 DETH（G2.1 Step 2）：Q_Key 来自 WQE dw10（per-WR 的 AH，不能放 QPC——
                // 同一 UD QP 允许发往不同目的 QPN/Q_Key）；源 QPN 是本端全局 QPN。
                // 全局 QPN = QPN_BASE(128) + qp_index，编码与 roce_top 的 RX 侧 qp_index 反解一致
                // （roce_pkg 的 QPN_BASE 是 QP_NUM 的整数倍，故低 QP_W 位恰为 qp_index）。
                // **不是** lane 局部索引 qp_lidx——线上写的是 24 bit 全局号。
                // RC 恒 0（IBTA：非 UD 报文的 DETH 不存在）。
                tx_job.deth_qkey   <= wqe_is_ud ? wqe_ud_qkey : 32'd0;
                tx_job.deth_src_qp <= wqe_is_ud ? (24'(QPN_BASE) + {17'd0, qp_index}) : 24'd0;
                if (tx_job_valid && tx_job_ready) begin
                    tx_job_valid <= 1'b0;
                    if (wqe_is_ud) begin
                        // ---------------- UD 完成（单包即整个 WQE）
                        // UD 没有 ACK：不能像 RC 那样等 ACK 把 unacked_index 推过这个 WQE
                        // （那会让本 WQE 永远停在未退休窗口里，CQE 永远不出、QP 卡死）。
                        // 所以发包被取走当拍就地退休：tx_index 与 unacked_index 一起 +1。
                        //   * 不写 meta_ram（{psn_start, packet_count} 只服务于 go-back-N 重发，
                        //     UD 无重传；而 unacked_index 已越过它，REQ_WALK 也不会再读）；
                        //   * 不动 next_psn / unacked_psn：两者保持相等 → 重传定时器永不触发，
                        //     后续 RC WQE 仍从 next_psn 起编 PSN，不会被 UD 吃掉 PSN 空间。
                        //   * tx_started / tx_offset 归零，WQE 视为整体完成。
                        // 完成码：WC_SEND + WCS_SUCCESS，length 报 WQE 的字节数（不是包长）。
                        // 与 REQ_WALK_DECIDE 的成功分支同形，只是触发条件是「发完」而不是「ACK 到」。
                        unacked_index  <= unacked_index + 16'd1;
                        tx_index   <= tx_index + 16'd1;
                        tx_offset  <= 32'd0;
                        tx_started <= 1'b0;
                        ack_counter <= 6'd0;
                        cqe_opcode    <= wc_opcode_of(wqe_opcode);
                        cqe_length <= wqe_length;
                        cqe_wqe_index   <= tx_index;
                        cqe_status  <= WCS_SUCCESS;
                        cqe_signaled   <= wqe_signaled;
                        cqe_return_state <= REQ_WRITE_BACK;
                        state   <= wqe_signaled ? REQ_CQE : REQ_WRITE_BACK;
                    end else begin
                        if (unacked_psn == next_psn) timer_restart[qp_lidx] <= 1'b1;
                        next_psn <= wqe_is_read ? wqe_psn_start + wqe_packet_count : next_psn + 24'd1;
                        ack_counter <= packet_last ? 6'd0 : ack_counter + 6'd1;
                        if (packet_first) begin
                            meta_write_enable <= 1'b1;
                            meta_write_address <= {qp_lidx, tx_index[4:0]};
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
                    event_rx_cnp_qp_l <= LANE_QPS'(1) << qp_lidx;
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
                    ram_read_address <= {qp_lidx, unacked_index[4:0]};
                    state     <= REQ_WALK_WAIT1;
                end
            end
            // B6503 簇 A：本拍 meta_read_data 才有效——REQ_WALK_START 那沿才把地址写进
            //   ram_read_address，同一沿 meta_read_data 取的是**旧地址**；新地址的数据在
            //   REQ_WALK_WAIT2 这一拍才出现在输出上（与 REQ_TX 侧 TX_ADDRESS→TX_WAIT 同构，
            //   那里也是 WAIT 之后才用）。所以采样点只能是 WAIT2，不能在 WAIT1。
            //   本拍原本就只是空转到 DECIDE，寄存不增加任何拍数。
            REQ_WALK_WAIT1: state <= REQ_WALK_WAIT2;
            REQ_WALK_WAIT2: begin
                // start 是对 M20K 输出的纯位选（RAM Tco → flop）；
                // end = start + count 在这一拍做（RAM 输出 → 一级 24 位加法 → flop）。
                // 判定拍因此只剩「减法 + 看符号」，不再有 RAM 输出 → 两级加法 → mux 的锥。
                meta_psn_start_q    <= meta_read_data[47:24];
                meta_psn_end_q      <= meta_read_data[47:24] + meta_read_data[23:0];
                state <= REQ_WALK_DECIDE;
            end
            REQ_WALK_DECIDE: begin
                cqe_opcode    <= wc_opcode_of(wqe_opcode);
                cqe_length <= wqe_length;
                cqe_wqe_index   <= unacked_index;
                cqe_signaled   <= wqe_signaled;
                if ($signed(retire_psn - meta_psn_end_q) >= 0 && (unacked_index != tx_index)) begin   // 整个 WQE 都在门限前
                    if (wqe_is_read && recovering) begin                    // 已在重发，等进展或超时
                        state <= handling_rx ? REQ_DRAIN : REQ_WRITE_BACK;
                    end else if (wqe_is_read) begin                         // READ 的响应丢了
                        if (retry_left == 3'd0) begin
                            cqe_status <= WCS_RETRY_EXC; cqe_signaled <= 1'b1; local_error <= 1'b1;
                            qp_set_error_l[qp_lidx] <= 1'b1; cqe_return_state <= REQ_DRAIN; state <= REQ_CQE;
                        end else begin
                            retry_left <= retry_left - 3'd1; event_retransmit_nak <= 1'b1;
                            retire_psn   <= meta_psn_start_q;
                            state  <= REQ_RESTART;
                        end
                    end else begin
                        unacked_index  <= unacked_index + 16'd1;
                        unacked_psn <= meta_psn_end_q;
                        retry_left <= qpc_retry(qp_context); recovering <= 1'b0;
                        timer_restart[qp_lidx] <= 1'b1;
                        cqe_status  <= WCS_SUCCESS;
                        cqe_return_state <= REQ_WALK_START;
                        state   <= wqe_signaled ? REQ_CQE : REQ_WALK_START;
                    end
                end else case (event_kind)
                    EVENT_ACK: begin
                        if ($signed(retire_psn - unacked_psn) > 0) begin
                            unacked_psn <= retire_psn; retry_left <= qpc_retry(qp_context); timer_restart[qp_lidx] <= 1'b1;
                            recovering <= 1'b0;
                        end
                        state <= REQ_WRITE_BACK;
                    end
                    EVENT_NAK_SEQUENCE, EVENT_TIMEOUT: begin
                        if (event_kind == EVENT_NAK_SEQUENCE && recovering) begin
                            state <= REQ_WRITE_BACK;                 // 重发前发出的包引起的旧 NAK
                        end else if (retry_left == 3'd0) begin
                            cqe_status <= WCS_RETRY_EXC; cqe_signaled <= 1'b1; local_error <= 1'b1;
                            qp_set_error_l[qp_lidx] <= 1'b1; cqe_return_state <= REQ_WRITE_BACK; state <= REQ_CQE;
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
                            qp_set_error_l[qp_lidx] <= 1'b1; cqe_return_state <= REQ_WRITE_BACK; state <= REQ_CQE;
                        end else begin
                            if (rnr_retry_left != 3'd7) rnr_retry_left <= rnr_retry_left - 3'd1;
                            rnr_waiting        <= 1'b1;
                            rnr_load[qp_lidx]  <= 1'b1;
                            rnr_load_value    <= rnr_timer_ticks(nak_syndrome[4:0]);
                            state          <= REQ_WRITE_BACK;
                        end
                    end
                    EVENT_RNR_DONE: state <= REQ_RESTART;
                    EVENT_NAK_ERROR: begin
                        cqe_status  <= (nak_syndrome == AETH_NAK_INV)    ? WCS_REM_INV_REQ :
                                (nak_syndrome == AETH_NAK_ACCESS) ? WCS_REM_ACCESS : WCS_REM_OP_ERR;
                        cqe_signaled <= 1'b1; local_error <= 1'b1; qp_set_error_l[qp_lidx] <= 1'b1;
                        cqe_return_state <= REQ_WRITE_BACK; state <= REQ_CQE;
                    end
                    default: begin                                   // EVENT_READ_RESPONSE
                        if (!wqe_is_read || retire_psn != unacked_psn) begin
                            if (wqe_is_read && $signed(retire_psn - unacked_psn) > 0 && retry_left != 3'd0 && !recovering) begin
                                retry_left <= retry_left - 3'd1; event_retransmit_nak <= 1'b1;
                                retire_psn   <= meta_psn_start_q;
                                cqe_return_state <= REQ_DRAIN;
                                state  <= REQ_RESTART;
                            end else
                                state <= REQ_DRAIN;
                        end else begin
                            translate_key <= wqe_lkey;
                            translate_virtual_address  <= wqe_local_address + ({8'd0, 24'(retire_psn - meta_psn_start_q)} << path_mtu_shift);
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
                timer_restart[qp_lidx] <= 1'b1;
                // tx_started=0 时重发的第一个包会按 FIRST 组包，因此只在偏移非 0 时置位；
                // 否则从消息头重发会被对端当作 MIDDLE（is_send_first 为假）回 NAK-Invalid。
                if (wqe_is_read) begin                      // 从第一个没收到的响应 PSN 续读（对端按重复 READ 重做）
                    next_psn <= unacked_psn;
                    tx_offset  <= {8'd0, 24'(unacked_psn - meta_psn_start_q)} << path_mtu_shift;
                    tx_started <= (unacked_psn != meta_psn_start_q);
                    reads_outstanding  <= 5'd0;            // 重发时 REQ_TX_PUSH 会再加 1
                end else begin
                    next_psn <= retire_psn;
                    tx_offset  <= {8'd0, 24'(retire_psn - meta_psn_start_q)} << path_mtu_shift;
                    tx_started <= (retire_psn != meta_psn_start_q);
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
                           qp_set_error_l[qp_lidx] <= 1'b1; cqe_return_state <= REQ_DRAIN; state <= REQ_CQE;
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
                timer_restart[qp_lidx] <= 1'b1;
                // 重发还没发出（tx_index 仍指向本 READ）时收到了迟到的原响应：重发起点跟着后移，
                // 本 READ 全部收齐则取消重发，保证 next_psn 不落在 unacked_psn 之前
                if (tx_index == unacked_index && tx_started) begin
                    if (retire_psn + 24'd1 == meta_psn_end_q) begin
                        tx_index   <= unacked_index + 16'd1;
                        tx_started <= 1'b0;
                        tx_offset  <= 32'd0;
                        next_psn   <= meta_psn_end_q;
                    end else begin
                        next_psn   <= retire_psn + 24'd1;
                        tx_offset  <= {8'd0, 24'(retire_psn + 24'd1 - meta_psn_start_q)} << path_mtu_shift;
                    end
                end
                if (retire_psn + 24'd1 == meta_psn_end_q) begin                        // 最后一个响应包
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
                cqe_data   <= {32'd0,                              // dw4 = 0（RC 无 src_qp）
                               32'd0, cqe_length, 8'd0, 8'(qp_index),     // dw1[23:16] qp_idx（ABI 8 位）
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
                    qp_tx_index[qp_lidx]   <= tx_index;   qp_unacked_index[qp_lidx]  <= unacked_index;  qp_next_psn[qp_lidx] <= next_psn; qp_unacked_psn[qp_lidx] <= unacked_psn;
                    qp_tx_offset[qp_lidx]  <= tx_offset;  qp_tx_started[qp_lidx] <= tx_started; qp_retry_left[qp_lidx]  <= retry_left;  qp_rnr_retry_left[qp_lidx]  <= rnr_retry_left;
                    qp_reads_outstanding[qp_lidx]  <= reads_outstanding;  qp_ack_counter[qp_lidx] <= ack_counter; qp_local_error[qp_lidx] <= local_error; qp_rnr_waiting[qp_lidx] <= rnr_waiting;
                    qp_recovering[qp_lidx] <= recovering;
                    done <= handling_rx;
                    state   <= REQ_IDLE;
                end
            end
            default: state <= REQ_IDLE;
        endcase
    end
    assign debug_state = {tx_offset, 18'd0, ack_counter, unacked_psn, next_psn, 4'(qp_index),   // [23:20] 只 4 位
                          local_error, recovering, reads_outstanding, {2'b00, retry_left},
                          {1'b0, dispatch_reason}, state};
endmodule
`default_nettype wire
