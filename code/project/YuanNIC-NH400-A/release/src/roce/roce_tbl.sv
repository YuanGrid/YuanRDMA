// roce_tbl.sv
// 资源表：QPC（128，每 lane 32 项：lane 交错持有 qp_index[LANE_BITS-1:0]==LANE_ID 的那些 QP）、
// MPT（64）、MTT（8192，奇偶两个 bank，一次读出相邻两页）、CQC（16），
// 由 CSR 表命令写入（格式见 yuanrdma_hw.h）；另提供 lkey/rkey 地址翻译服务（CLIENTS 个客户端，
// 轮询仲裁，每拍可受理一个，固定 4 拍返回）。
// QP 状态：主机写 QPC 时若 state 变化，qp_state_change[entry] 打一拍；硬件 qp_set_error[entry] 把状态置 ERR。
// S4 缩容：RAM 与 qp_state/timeout/prio 寄存器阵列只存本 lane 的 LANE_QPS 项，索引用 lane 局部索引
//   （= 全局 QP 索引去掉低 LANE_BITS 位）；对外引出的 one-hot/镜像总线**仍是 QP_NUM 位、全局下标**。
//   全表模式（LANE_ID < 0，单测台子）局部索引 = 全局索引，深度 = QP_NUM。
`default_nettype none
`timescale 1ns/1ps
module roce_tbl
    import roce_pkg::*;
#(
    parameter int CLIENTS = 3,
    // S2 第一步：QPC 只由属主 lane（qp[LANE_W-1:0]==LANE_ID）写入，非属主写入丢弃、
    // 读回 state=RESET。-1 = 每 lane 持有全表（S2 之前的行为）。
    // 存储缩容（每 lane 只存 1/4）与 RAM 化一起做，见优化日志 §63。
    parameter int LANE_ID = -1,
    // lane 内寄存器数量 = 2^LANE_BITS。**必须由上层按实际的 LANES 传入**：
    // 早先这里直接用了 package 里写死的 LANE_W=2，LANES 一旦变化就会静默错位。
    parameter int LANE_BITS = PKG_LANE_W,
    // S3：消费方读口数（每口一份 RAM 副本，同一写口）
    parameter int QPC_RD_PORTS = 3
)(
    input  wire                     clk,
    input  wire                     rst,
    // 表命令（来自 roce_csr）
    input  wire                     table_request,
    input  wire                     table_write_enable,
    input  wire  [3:0]              table_select,
    input  wire  [23:0]             table_index,
    input  wire  [511:0]            table_write_data,
    output reg                      table_ack,
    output reg                      table_error,
    output reg   [511:0]            table_read_data,
    // S3 起不再输出整张 QPC（QP_NUM×512 位组合读）：消费方改读下面的 M20K 读口。
    // QP 状态单独引出一份（3 bit × QP_NUM）。
    // 为什么需要：req/resp 的每个 QP 扫描条件只要 state 这 3 位，但写法是
    //   qpc_state(qpc[qp*512 +: 512]) == QPS_RTS
    // 会在每个 QP 上实例化一个完整的 512:1 位选择器，16 个串进同一条组合链。
    // 2026-10-31 的 STA（B6383 fit 前）显示 core_clk 关键路径正是从
    //   u_req|fetch_round_robin[1]（扇出 829）出发、21 级逻辑、走线占 59%
    //   → u_resp|out_address → u_resp|out_psn，
    // 这段扫描就是它的开头。改成直接用 qp_state_o[qp]（3 bit mux）可去掉这一级。
    output wire  [QP_NUM*3-1:0]     qp_state_o,
    output reg   [QP_NUM-1:0]       qp_state_change,
    input  wire  [QP_NUM-1:0]       qp_set_error,
    // QPC[511:3] 的观测读口（寄存读 1 拍）：只给单元台子 test/sim/roce_tbl_mirror 直接看 RAM，
    // 引擎里不接（rd_en 接 0）。CSR 的 QPC 表读回走内部的 u_qpc_ram_csr，见下。
    input  wire                     qpc_rd_en,
    input  wire  [15:0]             qpc_rd_addr,
    output wire  [508:0]            qpc_rd_data,
    output wire                     qpc_rd_valid,
    // S3：消费方读口。连续读：每拍给地址，下一拍出数据；qpc_rdp_addr_q / qpc_rdp_fresh 判断数据是否
    //   就是「本拍想要的 QP 的最新 QPC」（见 roce_qpc_ram.sv 文件头）。
    //   口号约定：0 = roce_req 主状态机，1 = roce_req 取指，2 = roce_resp 主状态机。
    input  wire  [QPC_RD_PORTS*16-1:0]  qpc_rdp_addr,
    output wire  [QPC_RD_PORTS*509-1:0] qpc_rdp_data,
    output wire  [QPC_RD_PORTS*16-1:0]  qpc_rdp_addr_q,
    output wire  [QPC_RD_PORTS-1:0]     qpc_rdp_fresh,
    // S3：所有 QP 都要并行看到的小字段（寄存器阵列，与 QPC 同沿写入，时序与原组合读等价）：
    //   timeout 给 roce_req 的重传定时器，prio = TOS[7:5] 给 PFC 准入（req 派发、engine 回包）。
    output wire  [QP_NUM*5-1:0]     qp_timeout_o,
    output wire  [QP_NUM*3-1:0]     qp_prio_o,
    // S3：最近一次 QPC 写入的数据（寄存一拍，与 qp_state_change 同拍有效）。qp_state_change 只由表写
    //   产生且一次只有一个 QP，所以 req/resp 状态变化时装载的初始 PSN / 重试次数直接取这里，
    //   与原来「那一拍按 qp 组合读 qpc」逐位相同（qpc_store 与 qp_state_change 同沿更新）。
    output reg   [511:0]            qpc_last_write,
    // CQC
    output cqc_t                    cqc [CQ_NUM],
    output reg   [CQ_NUM-1:0]       cq_reset,
    // 地址翻译：长度 transfer_length 的区间 [va, va+transfer_length) 须在 MR 内且不超过一页边界一次（<= 4096）
    input  wire  [CLIENTS-1:0]           translate_valid,
    output wire  [CLIENTS-1:0]           translate_ready,
    input  wire  [CLIENTS*32-1:0]        translate_key,
    input  wire  [CLIENTS*64-1:0]        translate_virtual_address,
    input  wire  [CLIENTS*13-1:0]        translate_length,
    input  wire  [CLIENTS*4-1:0]         translate_access,
    input  wire  [CLIENTS*16-1:0]        translate_protection_domain,
    output reg   [CLIENTS-1:0]           translate_response,     // 单拍，pa0/pa1/err 同拍有效
    output reg   [63:0]             translate_physical_address0,
    output reg   [63:0]             translate_physical_page1,
    output reg                      translate_error
);
    localparam int CLIENT_W = (CLIENTS > 1) ? $clog2(CLIENTS) : 1;

    // ------------------------------------------------------------ MTT 池位宽（由 MTT_NUM 推导）
    // 翻译通路与写通路共用，S7 扩池时只改 package 里的 MTT_NUM：
    //   MTT_IDX_W  = 池内页号位宽（8192 → 13，131072 → 17）
    //   MTT_ADDR_W = 单个 bank 的地址位宽 = 池深一半（8192 → 12，131072 → 16）
    localparam int MTT_IDX_W  = (MTT_NUM > 1) ? $clog2(MTT_NUM) : 1;
    localparam int MTT_ADDR_W = (MTT_NUM > 2) ? $clog2(MTT_NUM / 2) : 1;

    // ------------------------------------------------------------ 缩容参数（S4）
    // 本 lane 持有全局索引低 LANE_BITS 位等于 LANE_ID 的 QP（交错）。局部索引 = 全局索引去掉低
    // LANE_BITS 位，即「右移 LANE_BITS」——用常量移位，综合成纯连线（变址移位才是 LUT 链）。
    // 全表模式（LANE_ID < 0）不移位、深度 QP_NUM，与 S3 逐位相同。
    localparam bit       LANE_MODE  = (LANE_ID >= 0);
    localparam int       LIDX_LSB   = LANE_MODE ? LANE_BITS : 0;             // 局部索引起始位
    localparam int       LIDX_W     = QP_W - LIDX_LSB;                       // 局部索引位宽
    localparam int       LCL_DEPTH  = LANE_MODE ? LANE_QPS : QP_NUM;          // 本 lane 的项数
    // LANE_ID 必须落在 2^LANE_BITS 内，否则 qp % (1<<LANE_BITS) == LANE_ID 恒假：本 lane 丢弃全部
    // 写入、state 恒 RESET，是静默错误，这里直接挡在编译期。
    initial begin
        if (LANE_ID >= (1 << LANE_BITS))
            $fatal(1, "roce_tbl: LANE_ID=%0d 超出 2^LANE_BITS=%0d", LANE_ID, 1 << LANE_BITS);
        // S6：CQ_NUM 与 QPC dw0 的 scq/rcq 位段宽度必须一致。package 里不能写 initial，
        // 检查做成函数在那里定义、这里调用——改 CQ_NUM 忘了扩位段，elaboration 期就报错，
        // 而不是等到 CQ40 的 CQE 静默落进 CQ8（S4 的 QP68/QP4 同型事故）。
        if (!cq_field_fits())
            $fatal(1, "roce_tbl: CQ_W=%0d 超过 QPC dw0 的 scq/rcq 位段宽度 %0d（改 CQ_NUM 必须同时扩位段与 ynrdma_qpc.dw0）",
                   CQ_W, CQ_FIELD_W);
        // MTT 池必须是 2 的幂（奇偶分 bank 后每个 bank 也要整除），且至少 2 页。
        // MTT_ADDR_W 用 $clog2(MTT_NUM/2) 推导、base+page 用进位判界，都建立在这一点上；
        // 不满足时这两处会各自错位到不同深度，而不是同一个编译错误。
        if (MTT_NUM < 2 || (1 << MTT_IDX_W) != MTT_NUM)
            $fatal(1, "roce_tbl: MTT_NUM=%0d 必须是 2 的幂且 >= 2（MTT_IDX_W=%0d，MTT_ADDR_W=%0d）",
                   MTT_NUM, MTT_IDX_W, MTT_ADDR_W);
    end

    // ------------------------------------------------------------ 存储
    // S3：QPC[511:3] 只存在 M20K 里（每个读口一份副本，见 gen_rdp / u_qpc_ram_csr），
    // 寄存器阵列 qpc_store 与它的 QP_NUM×512 组合读已删除。
    // S4：以下三个阵列只存本 lane 的 LCL_DEPTH 项，全部用局部索引；对外引出的 qp_state_o /
    // qp_timeout_o / qp_prio_o 仍按 QP_NUM 位展开（见 gen_qpc）。
    reg  [2:0]   qp_state_store    [LCL_DEPTH];
    reg  [4:0]   qp_timeout_store  [LCL_DEPTH];
    reg  [2:0]   qp_prio_store     [LCL_DEPTH];
    reg  [31:0]  mpt_flags[MR_NUM];
    reg  [31:0]  mpt_key[MR_NUM];
    reg  [63:0]  mpt_virtual_address [MR_NUM];
    reg  [63:0]  mpt_length[MR_NUM];
    reg  [31:0]  mpt_mtt_base[MR_NUM];
    // S7：MTT 8192 → 131072（16×）。奇偶双 bank 结构不变：每 bank MTT_NUM/2 = 65536 项 × 64 位
    //   = 4 Mbit。M20K 是 512×40，一项 64 位要 2 块、65536 深要 128 行 → 每 bank 256 块，
    //   双 bank 512 块/实例；roce_tbl 每 lane 一份（4 lane）= 2048 块（原 128）。预算 13272 够。
    //   位宽用 localparam 派生（MTT_IDX_W / MTT_ADDR_W），别写死 12:0 / 11:0。
    (* ramstyle = "no_rw_check,m20k" *) reg [63:0] mtt_even_bank [MTT_NUM/2];
    (* ramstyle = "no_rw_check,m20k" *) reg [63:0] mtt_odd_bank [MTT_NUM/2];

    genvar qp;
    generate
        for (qp = 0; qp < QP_NUM; qp = qp + 1) begin : gen_qpc
            // 输出总线按全局下标展开；属主判定与索引都是常量（qp >> LIDX_LSB 由综合常量折叠），
            // 不产生变址移位。非属主项恒给 RESET/0——总线上每个 lane 只 Drive 自己的那 32 项。
            if (LANE_ID < 0 || qp % (1 << LANE_BITS) == LANE_ID) begin : gen_owned
                assign qp_state_o[qp*3 +: 3] = qp_state_store[qp >> LIDX_LSB];
                assign qp_timeout_o[qp*5 +: 5] = qp_timeout_store[qp >> LIDX_LSB];
                assign qp_prio_o[qp*3 +: 3]    = qp_prio_store[qp >> LIDX_LSB];
            end else begin : gen_foreign
                assign qp_state_o[qp*3 +: 3] = QPS_RESET;
                assign qp_timeout_o[qp*5 +: 5] = 5'd0;
                assign qp_prio_o[qp*3 +: 3]    = 3'd0;
            end
        end
    endgenerate

    // ------------------------------------------------------------ 表命令
    // MTT 写通路的位宽同样随 MTT_NUM 走：原来写死 13/12 位，S7 扩到 131072 后
    // 写 MTT[8192] 会静默落进 MTT[0]（与翻译通路是同一个 bug 的写侧）。
    reg          mtt_write_busy;
    reg  [2:0]   mtt_write_step;
    reg  [MTT_IDX_W-1:0]  mtt_write_base;
    reg  [511:0] mtt_write_entries;
    reg          mtt_write_even, mtt_write_odd;
    reg  [MTT_ADDR_W-1:0] mtt_write_address;
    reg  [63:0]  mtt_write_value;

    wire [23:0]  command_index = table_index;
    // S4：lane 局部索引（= 全局 QP 索引去掉低 LIDX_LSB 位）。全表模式取 [QP_W-1:0]，逐位同 S3。
    // 常数位选切片，综合是纯连线。
    wire [LIDX_W-1:0] command_local = command_index[QP_W-1:LIDX_LSB];
    wire         index_valid_qpc = (command_index < QP_NUM);
    wire         index_valid_mpt = (command_index < MR_NUM);
    // 8 项一组、index 为首项。S7：原来写 `command_index + 24'd8 <= MTT_NUM`，
    //   24 位加法在 command_index 接近 0xFFFFFF 时**回绕**，`0xFFFFF8..0xFFFFFF` 这些越界
    //   索引会被当成合法（写到 base=... 的低位别名上）。这里先扩到 25 位再比，永不回绕。
    wire [24:0]  command_index_ext = {1'b0, command_index};
    wire         index_valid_mtt = (command_index[2:0] == 3'd0) &&
                                   (command_index_ext + 25'd8 <= 25'(MTT_NUM));
    wire         index_valid_cqc = (command_index < CQ_NUM);
    // S6：CQC 下标显式按 CQ_W 切，宽度由 CQ_NUM 决定，不再写死 4 位。
    wire [CQ_W-1:0] command_cq = command_index[CQ_W-1:0];
    // S7（本分支）：MPT 的 mtt_base 是 32 位，但池里只有 MTT_NUM 项。写 MPT 时就拒绝越界 base，
    //   让错误落在「注册 MR」这一步而不是几十年后才在翻译时静默指向别人的页。
    //   翻译通路的 stage2_base_ok 仍在（纵深防御：万一有人绕过这条写口），两条互不替代。
    wire         mpt_mtt_base_bad = (|table_write_data[223:MTT_IDX_W+192]);

    // ---- QPC 镜像 RAM（S3）
    // 写口条件与下面 always 里 TBL_QPC 写分支完全一致（含 lane 归属与 mtt 忙时的互斥）。
    // S4：lane 归属判定落在 command_index 的低 LANE_BITS 位——QPC 表命令的 index 是**表项号**
    //   （= qp_index，0..QP_NUM-1，驱动用 qp->qp_index 直接写，不含 QPN_BASE）。QPN_BASE 只作用于
    //   线上 QPN（roce_rx_parse 判 dest_qpn ∈ [QPN_BASE, QPN_BASE+QP_NUM) 后取低 QP_W 位当表项号），
    //   所以这里不需要、也不能拿 QPN_BASE 去比；index_valid_qpc 用 QP_NUM 判界也仍成立。
    wire qpc_ram_we = !rst && !mtt_write_busy && table_request && table_write_enable &&
                      table_select == TBL_QPC && index_valid_qpc &&
                      (LANE_ID < 0 || command_index[LANE_BITS-1:0] == LANE_BITS'(LANE_ID));

    // 观测读口：lane 模式只占 LANE_QPS 项（DEPTH/IDX_LSB 成对传，见 roce_qpc_ram.sv 文件头）
    roce_qpc_ram #(.DEPTH(LCL_DEPTH), .IDX_LSB(LIDX_LSB)) u_qpc_ram (
        .clk(clk), .rst(rst),
        .wr_en(qpc_ram_we), .wr_addr(16'(command_index)), .wr_data(table_write_data[511:3]),
        .rd_en(qpc_rd_en), .rd_addr(qpc_rd_addr),
        .rd_data(qpc_rd_data), .rd_valid(qpc_rd_valid), .rd_addr_q(), .rd_fresh()
    );

    genvar rp;
    generate
        for (rp = 0; rp < QPC_RD_PORTS; rp = rp + 1) begin : gen_rdp
            roce_qpc_ram #(.DEPTH(LCL_DEPTH), .IDX_LSB(LIDX_LSB)) u_ram (
                .clk(clk), .rst(rst),
                .wr_en(qpc_ram_we), .wr_addr(16'(command_index)), .wr_data(table_write_data[511:3]),
                .rd_en(1'b1), .rd_addr(qpc_rdp_addr[rp*16 +: 16]),
                .rd_data(qpc_rdp_data[rp*509 +: 509]), .rd_valid(),
                .rd_addr_q(qpc_rdp_addr_q[rp*16 +: 16]), .rd_fresh(qpc_rdp_fresh[rp])
            );
        end
    endgenerate

    always @(posedge clk)
        if (qpc_ram_we) begin
            qpc_last_write                       <= table_write_data;
            qp_timeout_store[command_local] <= table_write_data[7*32 +: 5];        // qpc_timeout
            qp_prio_store[command_local]    <= table_write_data[7*32+16+5 +: 3];   // qpc_tos[7:5]
        end

    // CSR 的 QPC 表读回口（表读那一拍给地址，下一拍出数据）
    // S4：CSR 要能读**任意** QP，所以这一份保持全表深度（DEPTH=QP_NUM、IDX_LSB=0），不复用
    //   lane 模式——roce_top 已经按 table_index[LANE_W-1:0] 选属主 lane 应答（roce_top:351），
    //   让属主 lane 读自己的项即可，不需要每 lane 存全表。
    reg              qpc_read_pending;
    reg  [LIDX_W-1:0] qpc_read_index;
    wire [508:0]     qpc_csr_data;
    roce_qpc_ram #(.DEPTH(QP_NUM), .IDX_LSB(0)) u_qpc_ram_csr (
        .clk(clk), .rst(rst),
        .wr_en(qpc_ram_we), .wr_addr(16'(command_index)), .wr_data(table_write_data[511:3]),
        .rd_en(table_request && table_select == TBL_QPC), .rd_addr(16'(command_index)),
        .rd_data(qpc_csr_data), .rd_valid(), .rd_addr_q(), .rd_fresh()
    );

    integer entry;
    always @(posedge clk) begin
        table_ack  <= 1'b0;
        qp_state_change   <= '0;
        cq_reset   <= '0;
        mtt_write_even <= 1'b0;
        mtt_write_odd <= 1'b0;
        // 硬件把 QP 置错（主机同拍写该 QP 时以主机为准）
        // S4：entry 是整个 QP_NUM 的全局下标（循环展开成常量），只有本 lane 拥有的项才写进缩容后的
        //   阵列——否则非属主 lane 会把 entry>>LANE_BITS 写到别人的槽上。entry >> LIDX_LSB 与
        //   entry % (1<<LANE_BITS) 也是常量，不产生变址移位。
        for (entry = 0; entry < QP_NUM; entry = entry + 1)
            if ((LANE_ID < 0 || entry % (1 << LANE_BITS) == LANE_ID) && qp_set_error[entry] &&
                !(table_request && table_write_enable && table_select == TBL_QPC && index_valid_qpc &&
                  command_local == LIDX_W'(entry >> LIDX_LSB)))
                qp_state_store[entry >> LIDX_LSB] <= QPS_ERR;

        // QPC 表读回的第二拍：u_qpc_ram_csr 的数据已出，补上 state 后应答
        qpc_read_pending <= 1'b0;
        if (qpc_read_pending) begin
            table_ack       <= 1'b1;
            table_read_data <= {qpc_csr_data, qp_state_store[qpc_read_index]};
        end
        if (rst) begin
            mtt_write_busy <= 1'b0;
            qpc_read_pending <= 1'b0;
            for (entry = 0; entry < LCL_DEPTH; entry = entry + 1) qp_state_store[entry] <= QPS_RESET;
            for (entry = 0; entry < MR_NUM; entry = entry + 1) mpt_flags[entry] <= 32'd0;
            for (entry = 0; entry < CQ_NUM; entry = entry + 1) cqc[entry].valid <= 1'b0;
        end else if (mtt_write_busy) begin
            mtt_write_address   <= MTT_ADDR_W'((mtt_write_base + MTT_IDX_W'(mtt_write_step)) >> 1);
            mtt_write_value   <= mtt_write_entries[mtt_write_step*64 +: 64];
            mtt_write_even <= (mtt_write_step[0] == 1'b0);
            mtt_write_odd <= (mtt_write_step[0] == 1'b1);
            mtt_write_step    <= mtt_write_step + 3'd1;
            if (mtt_write_step == 3'd7) begin
                mtt_write_busy <= 1'b0;
                table_ack  <= 1'b1;
                table_error  <= 1'b0;
            end
        end else if (table_request) begin
            table_ack   <= 1'b1;
            table_error   <= 1'b0;
            table_read_data <= '0;
            case (table_select)
                TBL_QPC: if (!index_valid_qpc) table_error <= 1'b1;
                         else if (table_write_enable) begin
                             // S4：store 是 lane 局部索引；qp_state_change 是 QP_NUM 位 one-hot 总线，
                             // 仍用**全局**下标写位。
                             if (LANE_ID < 0 || command_index[LANE_BITS-1:0] == LANE_BITS'(LANE_ID)) begin
                             qp_state_store[command_local]   <= table_write_data[2:0];
                             if (qp_state_store[command_local] != table_write_data[2:0]) qp_state_change[command_index[QP_W-1:0]] <= 1'b1;
                             end
                         end else begin
                             // S3：高位在 M20K 里，寄存读要多一拍——这一拍不应答，下一拍再带数据应答
                             // （roce_csr 靠 table_ack 判断完成，延迟一拍对软件不可见）。
                             table_ack      <= 1'b0;
                             qpc_read_pending <= 1'b1;
                             qpc_read_index   <= command_local;
                         end
                TBL_MPT: if (!index_valid_mpt || (table_write_enable && mpt_mtt_base_bad)) table_error <= 1'b1;
                         else if (table_write_enable) begin
                             mpt_flags[command_index[5:0]] <= table_write_data[31:0];
                             mpt_key[command_index[5:0]] <= table_write_data[63:32];
                             mpt_virtual_address [command_index[5:0]] <= table_write_data[127:64];
                             mpt_length[command_index[5:0]] <= table_write_data[191:128];
                             mpt_mtt_base[command_index[5:0]] <= table_write_data[223:192];
                         end else
                             table_read_data[223:0] <= {mpt_mtt_base[command_index[5:0]], mpt_length[command_index[5:0]], mpt_virtual_address[command_index[5:0]],
                                                  mpt_key[command_index[5:0]], mpt_flags[command_index[5:0]]};
                TBL_MTT: if (!index_valid_mtt) table_error <= 1'b1;
                         else if (table_write_enable) begin
                             table_ack  <= 1'b0;          // 8 拍写完再应答
                             mtt_write_busy <= 1'b1;
                             mtt_write_step    <= 3'd0;
                             // 按 MTT_IDX_W 切，不写死 13 位：扩池后写 MTT[8192] 才不会落进 MTT[0]。
                             mtt_write_base <= command_index[MTT_IDX_W-1:0];
                             mtt_write_entries <= table_write_data;
                         end
                TBL_CQC: if (!index_valid_cqc) table_error <= 1'b1;
                         else if (table_write_enable) begin
                             // S6：CQ 下标按 CQ_W 切（16 时 4、64 时 6）。原来写死 [3:0]，
                             // 扩到 64 后写 CQC[40] 会静默落进 CQC[8]（40 & 15 == 8）。
                             cqc[command_cq].base  <= {table_write_data[63:32], table_write_data[31:0]};
                             cqc[command_cq].log2_depth    <= table_write_data[68:65];
                             cqc[command_cq].valid <= table_write_data[64];
                             cq_reset[command_cq]    <= 1'b1;
                         end else
                             table_read_data[95:0] <= {27'd0, cqc[command_cq].log2_depth, cqc[command_cq].valid,
                                                 cqc[command_cq].base};
                default: table_error <= 1'b1;
            endcase
        end
    end

    always @(posedge clk) begin
        if (mtt_write_even) mtt_even_bank[mtt_write_address] <= mtt_write_value;
        if (mtt_write_odd) mtt_odd_bank[mtt_write_address] <= mtt_write_value;
    end

    // ------------------------------------------------------------ 地址翻译
    // S0 仲裁
    reg  [CLIENT_W-1:0] round_robin;
    reg  [CLIENT_W-1:0] picked_client;
    reg           any_request;
    integer client;
    always @* begin
        any_request  = 1'b0;
        picked_client = round_robin;
        for (client = CLIENTS - 1; client >= 0; client = client - 1) begin
            if (translate_valid[(round_robin + client) % CLIENTS]) begin
                any_request  = 1'b1;
                picked_client = CLIENT_W'((round_robin + client) % CLIENTS);
            end
        end
    end
    assign translate_ready = any_request ? (CLIENTS'(1) << picked_client) : '0;
    always @(posedge clk) begin
        if (rst)      round_robin <= '0;
        else if (any_request) round_robin <= CLIENT_W'((picked_client + 1) % CLIENTS);
    end

    // S1
    reg           stage1_valid;
    reg  [CLIENT_W-1:0] stage1_client;
    reg  [31:0]   stage1_key;
    reg  [63:0]   stage1_virtual_address;
    reg  [12:0]   stage1_length;
    reg  [3:0]    stage1_access;
    reg  [15:0]   stage1_protection_domain;
    always @(posedge clk) begin
        stage1_valid  <= any_request && !rst;
        stage1_client  <= picked_client;
        stage1_key  <= translate_key[picked_client*32 +: 32];
        stage1_virtual_address <= translate_virtual_address [picked_client*64 +: 64];
        stage1_length  <= translate_length[picked_client*13 +: 13];
        stage1_access  <= translate_access[picked_client*4  +: 4];
        stage1_protection_domain <= translate_protection_domain [picked_client*16 +: 16];
    end
    wire [5:0]  stage1_mr_index   = stage1_key[5:0];
    wire [31:0] stage1_mpt_flags = mpt_flags[stage1_mr_index];
    wire        stage1_key_ok = stage1_mpt_flags[0] && (mpt_key[stage1_mr_index] == stage1_key) && ((stage1_mpt_flags[4:1] & stage1_access) == stage1_access) &&
                         (stage1_mpt_flags[31:16] == stage1_protection_domain);
    wire [64:0] stage1_offset  = {1'b0, stage1_virtual_address} - {1'b0, mpt_virtual_address[stage1_mr_index]};

    // MTT 池的位宽参数见文件上方（由 MTT_NUM 推导，写通路与翻译通路共用）。

    // S2
    // S7：MTT 扩到 131072 后这里三处**必须**跟着扩宽，否则大 MR 的后半段会静默映射到前半段：
    //   ① stage2_page_index 原来只取 stage2_offset[24:0]（32 MiB）——MR 超过 32 MiB 时高位被
    //      截掉、页号回绕到 MR 开头。B6438 的「单 MR 32 MiB 上限」就是这个截断，不是判界；
    //   ② stage2_mtt_base 原来只取 MPT 的低 13 位——mtt_base >= 8192 的 MR 会别名到靠前的 MR；
    //   ③ stage2_mtt_index 原来只有 13 位——mtt_base + 页号超过 8192 后回绕。
    // 同时补上越界判据 stage2_mtt_ok：mtt_index 必须 < MTT_NUM。以前没有任何检查，越界只是
    //   「读到别的 MR 的页」而不报错；S7 之后必须先出错、再谈功能。
    reg           stage2_valid, stage2_ok;
    reg  [CLIENT_W-1:0] stage2_client;
    reg  [63:0]   stage2_offset, stage2_mr_length;
    reg  [12:0]   stage2_length;
    reg  [11:0]   stage2_mr_va_low, stage2_va_page_offset;
    // **保持 32 位**（MPT 里该字段就是 32 位）：若截成 MTT_IDX_W 位，主机写一个越界的 base
    // 会在这里静默变成池内的另一个值，边界检查永远看到合法值。超宽由 stage2_base_ok 判。
    reg  [31:0]   stage2_mtt_base;
    always @(posedge clk) begin
        stage2_valid     <= stage1_valid;
        stage2_client     <= stage1_client;
        stage2_ok    <= stage1_key_ok && !stage1_offset[64];
        stage2_offset   <= stage1_offset[63:0];
        stage2_mr_length  <= mpt_length[stage1_mr_index];
        stage2_length     <= stage1_length;
        stage2_mr_va_low  <= mpt_virtual_address[stage1_mr_index][11:0];
        stage2_va_page_offset <= stage1_virtual_address[11:0];
        stage2_mtt_base   <= mpt_mtt_base[stage1_mr_index];
    end
    wire [64:0] stage2_end_offset  = {1'b0, stage2_offset} + {52'd0, stage2_length};
    wire        stage2_range_ok  = (stage2_length == 13'd0) || (stage2_end_offset <= {1'b0, stage2_mr_length});
    // ---------------------------------------------------------------- MTT 池边界（2026-11-14 修）
    // 原来的写法是 `stage2_mtt_index = stage2_mtt_base + stage2_page_index[12:0]`，两处会静默回绕：
    //
    //   1) `stage2_page_index` 只有 25 位。偏移超过 32 MiB 后高位被截掉，页号直接绕回池子低端；
    //   2) `base + page` 是 13 位加法。多个 MR 共享同一个 MTT 池时，mtt_base 非零，
    //      一旦和超过 MTT_NUM-1 就回绕，读到**属于另一个 MR** 的物理页。
    //
    // 两者都**没有错误标志、没有计数**，数据直接写到错误的物理地址。这与 S4 的
    // 「QP68 别名到 QP4」（68 & 31 == 4）同构，而那次的代价是整轮功能不可用。
    // 台子：test/sim/roce_mtt_bounds（对修复前的 RTL 是 1 PASS / 3 FAIL）。
    //
    // 三处检查各自独立，最终一起并进 stage3_ok。全部按 MTT_NUM 推导，改池深不用动这里。

    // 检查 [C]：字节偏移必须落在池的覆盖面（MTT_NUM × 4 KB）之内。
    // 用全宽加法，再看「页号以上」的位是否全 0——高位非零说明这一页池子里根本没有。
    // （原来的 `stage2_offset[24:0]` 把这部分高位直接丢了。）
    wire [64:0] stage2_pool_offset = {1'b0, stage2_offset} + {53'd0, stage2_mr_va_low};
    wire        stage2_in_pool     = (stage2_pool_offset[64:MTT_IDX_W+12] == '0);
    wire [MTT_IDX_W-1:0] stage2_page_index = stage2_pool_offset[MTT_IDX_W+11:12];

    // 检查 [A]：base + page 必须 < MTT_NUM。
    // base 比池宽也直接判错（否则下面的加法会把它截成池内的值）。
    wire [MTT_IDX_W:0]   stage2_mtt_index_full = {1'b0, stage2_mtt_base[MTT_IDX_W-1:0]} +
                                                 {1'b0, stage2_page_index};
    wire                 stage2_base_ok   = (stage2_mtt_base[31:MTT_IDX_W] == '0);
    wire                 stage2_mtt_ok    = stage2_base_ok && !stage2_mtt_index_full[MTT_IDX_W];
    wire [MTT_IDX_W-1:0] stage2_mtt_index = stage2_mtt_index_full[MTT_IDX_W-1:0];

    // 检查 [B]：传输跨页时需要 page1 = mtt_index+1，它也必须落在池内。
    // 池的最后一页（mtt_index == MTT_NUM-1）只能整页访问，跨页即越界
    // （原来 even_bank_address 的 +1 会在 MTT_ADDR_W 里回绕，静默读到项 0）。
    // 页面大小固定 4 KB：长度是 13 位，协议要求一次翻译最多跨一个页边界，
    // 所以 va_low + length 落在 14 位内，> 4096 就是跨页。
    wire [13:0] stage2_end_in_page  = {1'b0, stage2_va_page_offset} + {1'b0, stage2_length};
    wire        stage2_crosses_page = (stage2_end_in_page > 14'd4096);
    wire        stage2_page1_ok     = !stage2_crosses_page ||
                                      (stage2_mtt_index_full < (MTT_IDX_W+1)'(MTT_NUM - 1));

    // mi 偶：页 mi 在 e[mi/2]，页 mi+1 在 o[mi/2]；mi 奇：页 mi 在 o[mi/2]，页 mi+1 在 e[mi/2+1]
    wire [MTT_ADDR_W-1:0] odd_bank_address  = stage2_mtt_index[MTT_IDX_W-1:1];
    wire [MTT_ADDR_W-1:0] even_bank_address = stage2_mtt_index[MTT_IDX_W-1:1] +
                                              MTT_ADDR_W'(stage2_mtt_index[0]);

    // S3：RAM 输出
    reg           stage3_valid, stage3_ok, stage3_index_odd;
    reg  [CLIENT_W-1:0] stage3_client;
    reg  [11:0]   stage3_va_page_offset;
    reg  [63:0]   even_bank_data, odd_bank_data;
    always @(posedge clk) begin
        stage3_valid     <= stage2_valid;
        stage3_client     <= stage2_client;
        stage3_ok    <= stage2_ok && stage2_range_ok &&
                        stage2_in_pool && stage2_mtt_ok && stage2_page1_ok;
        stage3_index_odd   <= stage2_mtt_index[0];
        stage3_va_page_offset <= stage2_va_page_offset;
        even_bank_data     <= mtt_even_bank[even_bank_address];
        odd_bank_data     <= mtt_odd_bank[odd_bank_address];
    end

    // S4：输出
    always @(posedge clk) begin
        translate_response <= '0;
        if (stage3_valid && !rst) translate_response[stage3_client] <= 1'b1;
        translate_error <= !stage3_ok;
        translate_physical_address0 <= {(stage3_index_odd ? odd_bank_data[63:12] : even_bank_data[63:12]), stage3_va_page_offset};
        translate_physical_page1 <= {(stage3_index_odd ? even_bank_data[63:12] : odd_bank_data[63:12]), 12'd0};
    end
endmodule
`default_nettype wire
