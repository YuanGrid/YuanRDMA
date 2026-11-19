// roce_resp.sv
// 响应方（对端发来的请求）：PSN 检查、WRITE/SEND 落地（rkey/RQ WQE）、READ 请求入队、
// ACK/NAK、接收 CQE。回包（ACK/NAK、READ RESP）经同一个有序队列，保证按 PSN 顺序发出：
//   主状态机（每个请求包一次）-> rq 队列 -> 输出状态机（ACK 一包；READ 按 PMTU 拆包、
//   逐包翻译 rkey）-> TX 任务。
// v1 简化：重复的 WRITE/SEND 回 ACK(expected_psn-1)；重复 READ 重新执行；超前包回一次 NAK-SEQ；
// ACK 合并：AckReq、Last/Only 或每 ACK_EVERY 包回一次。
`default_nettype none
`timescale 1ns/1ps
module roce_resp
    import roce_pkg::*;
#(
    parameter int ACK_EVERY = 16,
    // S4：本实例拥有的 QP = 全局 qp_index[LANE_BITS-1:0] == LANE_ID（交错归属）。
    // 只影响 lane 局部阵列的归属判断（qp_state_change 循环）；索引换算走 qp_local()。
    parameter int LANE_ID = 0
)(
    input  wire                    clk,
    input  wire                    rst,
    input  wire  [31:0]            local_ip,       // S3：回包任务的 IP 校验和静态部分要用
    // S3：当前包已装载的 QPC 工作副本。约定：头部握手那一拍（rx_header_ready=1）它一定已是本包的
    // QPC——MAIN_IDLE 装载与拉 ready 同拍，握手在下一拍。roce_engine 在那一拍锁存 CNP 的组头字段。
    output wire  [511:0]           qp_context_o,
    // S3：QPC 改读 roce_tbl 的 M20K 寄存读口 2（给地址，下一拍出数据 + 产生数据的地址 + 读那一沿无写入）
    output wire  [15:0]            qpc_rd_addr,
    input  wire  [508:0]           qpc_rd_data,
    input  wire  [15:0]            qpc_rd_addr_q,
    input  wire                    qpc_rd_fresh,
    input  wire  [511:0]           qpc_last_write, // 与 qp_state_change 同拍：触发它的那次 QPC 写入值
    input  wire  [QP_NUM*3-1:0]    qp_state_i,     // QPC 的 [2:0] 单独引出，见 roce_tbl.sv
    input  wire  [QP_NUM-1:0]      qp_state_change,
    output wire  [QP_NUM-1:0]      qp_set_error,
    input  wire                    doorbell_rq_valid,
    input  wire  [31:0]            doorbell_data,
    // 表命令总线（用于 MPT 写作废页缓存）
    input  wire                    table_request,
    input  wire                    table_write_enable,
    input  wire  [3:0]             table_select,
    // RX 头部 / payload（由 dispatcher 分配给本模块的包）
    input  wire                    rx_header_valid,
    output reg                     rx_header_ready,
    input  rx_hdr_t                rx_header,
    input  wire                    rx_payload_valid,
    output wire                    rx_payload_ready,
    input  wire  [1023:0]          rx_payload_data,
    input  wire                    rx_payload_last,
    output wire                    done,          // 本包处理完（payload 已全部收下）
    // 地址翻译（主状态机 0、输出状态机 1）
    output wire  [1:0]             translate_valid,
    input  wire  [1:0]             translate_ready,
    output wire  [63:0]            translate_key,
    output wire  [127:0]           translate_virtual_address,
    output wire  [25:0]            translate_length,
    output wire  [7:0]             translate_access,
    output wire  [31:0]            translate_protection_domain,
    input  wire  [1:0]             translate_response,
    input  wire  [63:0]            translate_physical_address0,
    input  wire  [63:0]            translate_physical_page1,
    input  wire                    translate_error,
    // DMA 读（RQ WQE）
    output reg                     dma_read_request_valid,
    input  wire                    dma_read_request_ready,
    output reg   [63:0]            dma_read_request_address,
    output wire  [63:0]            dma_read_request_page1,
    output wire  [12:0]            dma_read_request_length,
    input  wire                    dma_read_valid,
    output wire                    dma_read_ready,
    input  wire  [1023:0]          dma_read_data,
    // DMA 写（payload 落地）
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
    // S（UD）：cqe_data 从 128 → 160 bit，新增 dw4[24:0] = {src_qp_valid[24], src_qp[23:0]}。
    // dw0[18] = has_grh：**恒 0**（GRH 尚未实现，见 MAIN_CQE 处的说明）。provider 目前据此
    // 决定是否置 IBV_WC_GRH —— 置 1 会让 ULP 从 buf[40] 起读载荷，而接收缓冲里没有那 40 B。
    output reg   [159:0]           cqe_data,
    // TX 任务
    output reg                     tx_job_valid,
    input  wire                    tx_job_ready,
    output tx_job_t                tx_job,
    // 计数
    output reg                     event_duplicate,
    output reg                     event_sequence_error,
    output reg                     event_tx_ack,
    output reg                     event_tx_nak,
    output reg                     event_rnr_nak,
    output reg                     event_access_error,
    output reg                     event_drop,
    // 最近一次 access error 快照（B6433）
    output wire  [8*32-1:0]        dbg_access_snapshot,
    input  wire                    dbg_access_snapshot_clr,
    // 页缓存命中/未命中（B6390）：用来在板上直接验收「首包也走缓存」是否生效。
    // 未命中只统计 WRITE 路径（SEND 走 ACC_LOCAL_WRITE，语义不同，不进这条缓存）。
    output reg                     event_page_hit,
    output reg                     event_page_miss,
    // 调试：{out_state[2:0], main_state[3:0]}，布局见 roce_debug.sv 0x0564
    output wire  [6:0]             debug_state
);
    // S4：本 lane 编号（截到 LANE_BITS 位，供 qp_owned 用）。LANE_ID 是 int 参数，
    // 直接当实参传进 qp_owned 会带 32 位宽度，这里先截好，比较只剩 2 位。
    localparam logic [PKG_LANE_W-1:0] LANE_IDX = PKG_LANE_W'(LANE_ID & ((1 << LANE_BITS) - 1));
    // ------------------------------------------------------------ access error 快照（B6433）
    // B6432 上 server send_bw 约 50% 轮次报 remote access error（§56.7）：现有计数只有总数，看不到哪个 QP、
    // 哪一段游标、哪个 key/地址越界。这里在复位后**第一次** access error 时锁存上下文（sticky，不覆盖），
    // 计数饱和；窗口在 roce_top 的 0x0C00 + lane*0x20，第 7 个字是事件总数，写窗口基址清快照与计数。
    //   0 {opcode, bad, qp_valid, qp_index, payload_length}
    //   1 psn  2 翻译 key（SEND=RQ WQE 的 lkey，WRITE=首包 rkey/cursor_key）  3 VA[31:0]
    //   4 {translate_length, rq_consumer}  5 cursor_offset  6 cursor_remaining  7 事件计数
    reg  [7*32-1:0] dbg_access_shot;      // 7 个字，第 8 个字是事件计数（单独寄存）
    reg             acc_err_seen;
    reg  [31:0]     acc_err_cnt;
    // 清除与计数放进主状态机那个 always 块（Quartus 13264：同一寄存器两个 always 块 = 多驱动）。
    // 那里 rst 分支清 acc_err_cnt，常规分支开头清 acc_err_seen；见 MAIN_ 之外的那段「快照维护」。
    assign dbg_access_snapshot = {acc_err_cnt, dbg_access_shot};

    // ------------------------------------------------------------ 每 QP 状态
    // S4（QP 128）：本 lane 只持有自己的 1/4 项（LANE_BITS=2，故 LANE_QPS = QP_NUM >> 2 = 32）。
    // 索引一律用 lane 局部位 qp[QP_W-1:LANE_BITS]，与 roce_pkg 的 qp_local() 等价。
    // **不能拿全局 qp_index 直接下标**：数组只有 32 项，全局索引 0..127 越界后回绕到
    // 别的 QP，是静默数据错（Verilator 只报 SELRANGE，-Wno-fatal 下不拦）。
    // 索引写成裸 part-select 而不是 qp_local(...)：Verilator 对「NBA 写 + 函数调用下标」
    // 偶发 Internal Error（V3Delayed: Multiple Write refs on LHS of NBA），裸位选不会。
    // 缩容后 MAIN_IDLE 的装载是 263 位 × 32:1，原来是 ×128:1 —— 本文件的主要时序收益。
    // 全局总线（qp_set_error_main/out、qp_state_change）仍是 QP_NUM 位，见下。
    reg  [23:0] qp_expected_psn  [LANE_QPS];
    reg  [23:0] qp_msn   [LANE_QPS];
    reg  [4:0]  qp_ack_counter  [LANE_QPS];
    reg         qp_nak_sent   [LANE_QPS];
    reg  [15:0] qp_rq_producer  [LANE_QPS];
    reg  [15:0] qp_rq_consumer  [LANE_QPS];
    reg         qp_message_active  [LANE_QPS];   // 有进行中的 SEND（已取 RQ WQE）或 WRITE 消息
    reg  [31:0] qp_cursor_key  [LANE_QPS];
    reg  [63:0] qp_cursor_address   [LANE_QPS];
    reg  [31:0] qp_cursor_remaining  [LANE_QPS];   // SEND：RQ 缓冲剩余；WRITE：DMA 长度剩余
    reg  [31:0] qp_cursor_offset  [LANE_QPS];   // SEND：已收字节；WRITE：DMA 总长
    reg  [15:0] qp_cursor_wqe_index  [LANE_QPS];
    // 置错总线保持 QP_NUM 位（roce_tbl 按全局索引收，roce_top 把 4 个 lane 或起来）
    reg  [QP_NUM-1:0] qp_set_error_main;

    // 工作副本
    rx_hdr_t    header;
    reg  [QP_W-1:0] qp_index;
    reg  [511:0] qp_context;
    assign qp_context_o = qp_context;
    // S3：读口地址恒为 rx_header.qp_index（预读）。头部在上游等待期间数据总线是稳定的，
    // 所以到 MAIN_IDLE 看见 valid 时读口通常已经给出这个 QP 的 QPC（qpc_hit），仍是一拍装载；
    // 只有头部「刚到达」或读那一沿撞上 QPC 写时才进 MAIN_LOAD 多等一拍（此时不拉 ready，
    // 保证 roce_engine 依赖的「握手那拍 qp_context 已是本包 QPC」不变）。
    assign qpc_rd_addr = 16'(rx_header.qp_index);
    wire   qpc_hit     = qpc_rd_fresh && (qpc_rd_addr_q[QP_W-1:0] == rx_header.qp_index);
    // B6441：path_mtu 与它自己那个 3 位编码一起寄存，和 qp_context 在 MAIN_IDLE 那一拍同时装上。
    // 原来 path_mtu = pmtu_bytes(qpc_pmtu(qp_context)) 是组合展开的 128<<code 桶形移位，
    // 它的下游 read_packet_count 又是一个按 qpc_pmtu 移位的桶形移位，两段串在一条链上：
    // B6440 的 core 第三大户（99 个端点，最差 −0.125）就是
    //   u_resp|qp_context[5](= pmtu[2]) → path_mtu → read_packet_count → fin_expected_psn
    //   → qp_expected_psn[*][23]，6 级逻辑 / IC 2.0 / cell 1.79
    // 两者都是 qp_context 的纯函数、而 qp_context 在这一拍之后的整包内不变，
    // 所以寄存一份与现算逐位等价，**不加拍**（消费者本来就在 MAIN_CLASSIFY 及以后）。
    reg  [12:0] path_mtu_q;
    reg  [2:0]  pmtu_code_q;
    wire [12:0] path_mtu    = path_mtu_q;
    wire [2:0]  pmtu_code   = pmtu_code_q;
    reg  [23:0] expected_psn, msn;
    reg  [4:0]  ack_counter;
    reg         nak_sent, message_active;
    reg  [15:0] rq_consumer;
    reg  [31:0] cursor_key, cursor_remaining, cursor_offset;
    reg  [63:0] cursor_address;
    reg  [15:0] cursor_wqe_index;

    // ------------------------------------------------------------ 页级翻译缓存
    // 一条 WRITE 消息的连续包地址线性推进，同一个 4 KB 页内的多个包共享同一条 MTT 映射。
    // 翻译流水是 TRANSLATE + TRANSLATE_WAIT = 5 拍（仿真实测 TRANSLATE_WAIT 恰好 4.00 拍/包），
    // 命中缓存即可整段跳过，是当前 RX 每包串行开销里最大的一项。
    //
    // 命中条件三选一全部满足：key 相同（同一 MR）、虚拟地址的高位（页号）相同、
    // 且本包是 continuation 包（首包必须走真翻译，建立映射）。
    // 映射在一条消息内不会变——同一 QP 的消息在 RESP 上是串行的——所以同一 key 同一页
    // 的命中是安全的。qp_state_change（含 reset）与错误路径都会作废缓存。
    reg          page_valid;
    reg  [31:0]  page_key;
    reg  [15:0]  page_pd;           // 填缓存时该 QP 的 PD：命中路径必须自己校验（见下）
    reg  [51:0]  page_va_base;      // 命中页的虚拟页号（address[63:12]）
    reg  [51:0]  page_pa0_base;     // 对应物理页基址
    reg  [51:0]  page_pa1_base;     // page1 的物理页基址（表里已算好 next page）
    // ------------------------------------------------------------ 下一页缓存项（B6398）
    // 为什么加：一次真翻译本来就把**相邻两页**的基址都算出来了（translate_physical_page0/1），
    // 但过去只存了第 0 页，于是下一页的第一包又要重走一次 5 拍翻译。1 KB MTU 下每 4 个包
    // 跨一页，实测 PAGE_MISS / RX_PKTS = 28,881,920 / 115,527,680 = 25.0%，
    // TRANSLATE_WAIT 2.14 拍/包就是这么来的。存下第 1 页后 miss 减半到 12.5%。
    //
    // 只存物理页基址，**不存 pa1**：第 1 页的「下一页」是第 2 页，翻译结果里没有。
    // 所以这一项只在**不跨页**的包上命中（跨页要用到 page1，那是未知的）。
    // 1 KB / 4 KB MTU 下包都不会跨 4 KB 页（末地址 = 4096 时判据是 > 4096），所以实际上
    // 这一项覆盖了全部线性写流；2 KB MTU 从偏移 3072 起的包才回落到慢路径。
    reg          page_next_valid;
    reg  [51:0]  page_next_pa0_base; // page_va_base + 1 这一页的物理基址

    // 命中条件：key 相同（同一 MR）、虚拟页号相同、PD 相同、且本包是 WRITE 包。
    //
    // B6390：**首包也允许命中**（原来只有 continuation 包能命中）。依据是 B6389 的实测
    // （`roce-log` §25.4/§25.5）：1 KB 单包消息每包都是首包，命中不了页缓存，固定开销
    // 16.000 拍里有 4.42 拍是 WRITE_REQUEST 拉起时机、2.72 拍是 TRANSLATE_WAIT，合计约
    // 7 拍纯粹因为"必须先翻译再发请求"。而 perftest 反复写同一缓冲区时 key/VA 完全重复，
    // 这是一次白付。
    //
    // 首包的 key/VA 来自头部 RETH，continuation 包来自 cursor_*，所以比较源要分开取。
    //
    // **PD 必须自己比**：真翻译路径由 roce_tbl 校验 `mpt_flags[31:16] == protection_domain`
    // （roce_tbl.sv:208），而命中路径整段绕过翻译，缓存项又是跨 QP 全局共享的。少了这一项，
    // 不同 PD 的 QP 只要知道 rkey 就能绕过保护域检查写远端内存。访问权限位（flags[4:1]）
    // 不必在这里比：那是 MR 属性、与 QP 无关，且 MPT 表写会作废缓存。
    //
    // 其余安全性不变：缓存项由真翻译结果填充，MPT 表写与 qp_state_change（含 MR 注销/重注册）
    // 都会作废它；命中意味着同一 rkey 同一 4 KB 虚拟页，物理页必然相同。
    // 带 Imm 的包仍排除——它们要占 RQ 槽、走 MAIN_RQ_FETCH，不走这条捷径。
    wire [31:0]  page_cmp_key = is_write_first ? header.reth_rkey : cursor_key;
    wire [63:0]  page_cmp_va  = is_write_first ? header.reth_virtual_address : cursor_address;
    // B6393：零长度守卫。payload_length=0 时 has_payload=0、roce_skip_align 一拍都不出，
    // 而 MAIN_WRITE_DATA 的唯一出口要 rx_payload_valid && last → done 永不拉高 →
    // disp.busy 永久挂住 → 整条 RX 停摆。零字节 RDMA WRITE 是合法的（IBA §9.3.1），
    // 不能 NAK；直接走慢路径（MAIN_TRANSLATE → MAIN_TRANSLATE_WAIT → MAIN_FINISH）即可。
    // 把守卫并进名字而不是加 `else if (page_hit && length!=0)`：全文件只此一处使用 page_hit，
    // 写进名字保证日后新增使用点不会重犯；单独加 else if 则电气等价但语义分散。
    // 命中项选择：优先第 0 页（有 pa1，逻辑最简单），其次第 1 页（要求本包不跨页）。
    // 不跨页判据与 roce_dma 的 write_crosses_page 同口径：页内末地址 = 偏移 + 长度。
    // 等于 4096 不算跨页（一页正好写满），与 roce_dma.sv 的 `> 4096` 保持一致。
    wire [12:0] page_end_in_page = {1'b0, page_cmp_va[11:0]} + header.payload_length;
    wire        page_crosses    = (page_end_in_page > 13'd4096);
    wire        page_hit0 = page_valid &&
                            (page_cmp_key == page_key) &&
                            (page_cmp_va[63:12] == page_va_base) &&
                            (qpc_pd(qp_context) == page_pd) &&
                            (is_write_first || is_write_continue) && !is_write_with_immediate &&
                            (header.payload_length != 13'd0);
    wire        page_hit1 = page_next_valid &&
                            (page_cmp_key == page_key) &&
                            (page_cmp_va[63:12] == page_va_base + 52'd1) &&
                            (qpc_pd(qp_context) == page_pd) &&
                            (is_write_first || is_write_continue) && !is_write_with_immediate &&
                            (header.payload_length != 13'd0) && !page_crosses;
    wire        page_hit  = page_hit0 || page_hit1;
    // 命中第 1 页时用的物理基址（第 0 页就是 page_pa0_base）
    wire [51:0] page_hit_pa0_base = page_hit0 ? page_pa0_base : page_next_pa0_base;
    // 命中第 1 页时 pa1 未知：本包已保证不跨页，dma_write_request_page1 不会被用到，
    // 但仍必须给一个确定值（MAIN_WRITE_REQUEST 会重新驱动它），填成本页基址 + 1 页。
    wire [51:0] page_hit_pa1_base = page_hit0 ? page_pa1_base : (page_next_pa0_base + 52'd1);

    // ------------------------------------------------------------ 回包队列
    typedef struct packed {
        logic [QP_W-1:0] qp_index;
        logic        is_read;
        logic [23:0] psn;
        logic [7:0]  syndrome;
        logic [23:0] msn;
        logic [63:0] virtual_address;
        logic [31:0] rkey;
        logic [31:0] payload_length;
        // S3：回包所需的 QPC 字段在入队时从 qp_context 带上，输出状态机不再按 qp_index 查 QPC
        logic [2:0]  pmtu;
        logic [15:0] pd;
        logic [7:0]  tos;
        logic [7:0]  ttl;
        logic [47:0] dmac;
        logic [31:0] dip;
        logic [15:0] sport;
        logic [23:0] dqpn;
    } response_entry_t;
    response_entry_t       response_in, response_out;
    reg         response_in_valid;
    // 本模块自己压进回包 FIFO、尚未被接收的条目。FINISH 快路径会在回包还没走掉时就回到 IDLE，
    // 所以 MAIN_ACK 不能再靠 response_in_valid 判断「是不是我的回包」——那可能是上一包的在途响应。
    reg         resp_pending;
    wire        response_in_ready, response_out_valid;
    reg         response_out_ready;
    axis_async_fifo #(
        .DEPTH(32), .DATA_WIDTH($bits(response_entry_t)), .KEEP_ENABLE(0), .LAST_ENABLE(0), .USER_ENABLE(0)
    ) u_response_fifo (
        .s_clk(clk), .s_rst(rst),
        .s_axis_tdata(response_in), .s_axis_tkeep('0), .s_axis_tvalid(response_in_valid), .s_axis_tready(response_in_ready),
        .s_axis_tlast(1'b1), .s_axis_tid(8'd0), .s_axis_tdest(8'd0), .s_axis_tuser(1'b0),
        .m_clk(clk), .m_rst(rst),
        .m_axis_tdata(response_out), .m_axis_tkeep(), .m_axis_tvalid(response_out_valid), .m_axis_tready(response_out_ready),
        .m_axis_tlast(), .m_axis_tid(), .m_axis_tdest(), .m_axis_tuser(),
        .s_pause_req(1'b0), .s_pause_ack(), .m_pause_req(1'b0), .m_pause_ack(),
        .s_status_depth(), .s_status_depth_commit(), .s_status_overflow(),
        .s_status_bad_frame(), .s_status_good_frame(),
        .m_status_depth(), .m_status_depth_commit(), .m_status_overflow(),
        .m_status_bad_frame(), .m_status_good_frame()
    );
    // ------------------------------------------------------------ 主状态机
    localparam [3:0] MAIN_IDLE = 4'd0, MAIN_LOAD = 4'd1, MAIN_CLASSIFY = 4'd2, MAIN_RQ_FETCH = 4'd3, MAIN_RQ_WAIT = 4'd4,
                     MAIN_TRANSLATE = 4'd5, MAIN_TRANSLATE_WAIT = 4'd6, MAIN_WRITE_REQUEST = 4'd7, MAIN_WRITE_DATA = 4'd8, MAIN_FINISH = 4'd9,
                     MAIN_CQE = 4'd10, MAIN_ACK = 4'd11, MAIN_DRAIN = 4'd12, MAIN_WRITE_BACK = 4'd13;
    reg  [3:0]  main_state;

    wire [7:0]  opcode       = header.opcode;
    // UD（0x64/0x65）：无 PSN 语义、无 ACK、无 RNR，一个包就是一条完整消息。
    // 单独一根线而不是并进 is_send_first：并进去会让下面 `is_send && !message_active` 的
    // 「首包」判断和 RQ 取指逻辑对 UD 误触发（见 skill/ud-transport-plan.md §7.5）。
    wire        is_ud_send       = (opcode == OP_SEND_ONLY_UD) || (opcode == OP_SEND_ONLY_UD_IMM);
    wire        is_send_first    = (opcode == OP_SEND_FIRST) || (opcode == OP_SEND_ONLY) || (opcode == OP_SEND_ONLY_IMM) ||
                                   is_ud_send;
    wire        is_send_continue    = (opcode == OP_SEND_MIDDLE) || (opcode == OP_SEND_LAST) || (opcode == OP_SEND_LAST_IMM);
    wire        is_write_first    = (opcode == OP_WRITE_FIRST) || (opcode == OP_WRITE_ONLY) || (opcode == OP_WRITE_ONLY_IMM);
    wire        is_write_continue    = (opcode == OP_WRITE_MIDDLE) || (opcode == OP_WRITE_LAST) || (opcode == OP_WRITE_LAST_IMM);
    wire        is_read_request    = (opcode == OP_READ_REQ);
    wire        is_send  = is_send_first || is_send_continue;
    wire        is_write = is_write_first || is_write_continue;
    wire        is_message_end   = (opcode == OP_SEND_LAST) || (opcode == OP_SEND_LAST_IMM) || (opcode == OP_SEND_ONLY) ||
                           (opcode == OP_SEND_ONLY_IMM) || (opcode == OP_WRITE_LAST) ||
                           (opcode == OP_WRITE_LAST_IMM) || (opcode == OP_WRITE_ONLY) || (opcode == OP_WRITE_ONLY_IMM) ||
                           is_ud_send;
    wire        is_message_middle   = (opcode == OP_SEND_FIRST) || (opcode == OP_SEND_MIDDLE) ||
                           (opcode == OP_WRITE_FIRST) || (opcode == OP_WRITE_MIDDLE);
    wire        is_write_with_immediate    = (opcode == OP_WRITE_LAST_IMM) || (opcode == OP_WRITE_ONLY_IMM);
    wire        is_request   = is_send || is_write || is_read_request;
    // path_mtu / pmtu_code 已寄存（见 qpc_rd_addr 附近的说明），这里不再现算。
    // UD 无 PSN 语义：强制 delta=0，重复包/超前包两个分支整体短路（三处都靠这一个量）。
    wire [23:0] psn_delta     = is_ud_send ? 24'd0 : (header.psn - expected_psn);
    wire        qp_state_ok    = (qpc_state(qp_context) == QPS_RTR) || (qpc_state(qp_context) == QPS_RTS);
    wire        rq_is_empty = (rq_consumer == qp_rq_producer[qp_index[QP_W-1:LANE_BITS]]);
    // FIRST/MIDDLE 必须正好 PMTU；LAST/ONLY 1..PMTU（ONLY 可为 0）。
    // UD 不受 PMTU 约束（一个包就是一条消息，长度只由 RQ WQE 兜住）。
    wire        length_ok   = is_ud_send ? 1'b1 :
                              is_message_middle ? (header.payload_length == path_mtu) : (header.payload_length <= path_mtu);
    wire [23:0] read_packet_count  = (header.reth_length == 32'd0) ? 24'd1 :
                           24'((header.reth_length + {19'd0, path_mtu} - 32'd1) >> ({1'b0, pmtu_code} + 4'd7));

    // ------------------------------------------------------------ 包尾的下一值（组合）
    // FINISH / ACK / WRITE_BACK 三态的输入全部来自工作副本和 header，彼此没有先后依赖，
    // 所以包尾那一拍就能把「写回 per-QP 数组 + 打 done + 回 ACK」一次算完（原来要 3 拍）。
    // 唯一例外是 SEND / 带 Imm 的消息末包：CQE 字段要寄存后才能发，那条路径仍走 FINISH → CQE → ACK
    // → WRITE_BACK（每消息一次，不值得合并）。
    wire        fin_ack          = !is_read_request && !is_ud_send &&
                                   (header.ack_request || is_message_end || ack_counter == 5'(ACK_EVERY - 1));
    wire        fin_send_response = fin_ack || is_read_request;
    wire        fin_need_cqe     = is_message_end && (is_send || is_write_with_immediate);
    // UD 无 PSN：包尾不推进 expected_psn（否则会与同 QP 上共用的 RC 序号串互相污染）。
    wire [23:0] fin_expected_psn = expected_psn + (is_ud_send ? 24'd0 :
                                   (is_read_request ? read_packet_count : 24'd1));
    wire [23:0] fin_msn          = msn + ((is_read_request || (is_message_end && !is_ud_send)) ? 24'd1 : 24'd0);
    // 读请求不参与 ACK 合并计数（原 FINISH 对读请求完全不碰 ack_counter）。
    wire [4:0]  fin_ack_counter  = is_read_request ? ack_counter : (fin_ack ? 5'd0 : ack_counter + 5'd1);
    wire [31:0] fin_cursor_remaining = is_send          ? cursor_remaining - {19'd0, header.payload_length} :
                                       is_write_first   ? header.reth_length - {19'd0, header.payload_length} :
                                       is_write         ? cursor_remaining - {19'd0, header.payload_length} :
                                                          cursor_remaining;
    wire [31:0] fin_cursor_offset    = is_send      ? cursor_offset + {19'd0, header.payload_length} :
                                       is_write_first ? header.reth_length : cursor_offset;
    wire [63:0] fin_cursor_address   = is_send            ? cursor_address + {51'd0, header.payload_length} :
                                       is_write_first     ? header.reth_virtual_address + {51'd0, header.payload_length} :
                                       is_write           ? cursor_address + {51'd0, header.payload_length} :
                                                            cursor_address;
    wire        fin_message_active   = is_send  ? (is_message_end ? 1'b0 : message_active) :
                                       is_write ? !is_message_end : message_active;
    // 首包（WRITE_ONLY / WRITE_FIRST）要把 rkey 记进 cursor_key，后续 continuation 包靠它继续翻译。
    // 漏了这一项会让首包之后所有包拿旧 key 去查表 → 翻译失败 → NAK_ACCESS → 对端重传 → 挂死。
    wire [31:0] fin_cursor_key       = is_write_first ? header.reth_rkey : cursor_key;

    // B6391：包尾快路径可以执行的条件。两个例外 —— 要发 CQE（字段必须先寄存）与上一包回包
    // 还占着 FIFO 入口 —— 仍走 MAIN_FINISH，那里可以原地等。其余情况末拍就直接收尾回 IDLE。
    wire        fin_fast_ready = !fin_need_cqe && !(fin_send_response && response_in_valid);
    // done 只在收尾那一拍置位、下一拍落下。B6392 起它在 WRITE_DATA 末拍与 MAIN_FINISH
    // 两条路径上都走 fin_fast_path，条件完全相同（都是"payload 末拍握手成功"），所以
    // 单拍包与多拍包看到的行为一致。
    //
    // B6391 第一版曾把 done 做成组合输出（`done = done_reg || fin_now || fin_fin`），
    // 其中 fin_now 用上一拍寄存的 dma_write_ready_q 来截断时序路径。**那版是错的**：
    // 单拍包（payload 只有一拍，perftest write_lat 的 2~128 B 全是）在 WRITE_DATA 的第一拍
    // dma_write_ready_q 还是 0（WRITE_REQUEST 期间尚未受理），fin_now 不成立，于是状态机
    // 走 fin_fast_path 回了 IDLE，而 done 一拍都没拉高 → disp.busy 永挂 → 对端超时重传耗尽。
    // 多拍包末拍前一拍 dma_write_ready 已是 1，所以 1 KB / 1 M 看不出问题，仿真门禁当时
    // 只跑了多拍用例也没拦住。现在 done 一律寄存，与状态机同拍同条件，单拍多拍语义一致，
    // 同时把 dma_write_ready 组合出来的长路径彻底切断（它直通 FIFO gray 指针比较）。
    reg         done_reg;
    assign      done = done_reg;
    // 写回 per-QP 数组 + 打 done + 回 ACK。WRITE_DATA 末拍与 MAIN_FINISH 共用同一段逻辑，
    // 避免两处副本日后各自漂移。全部是寄存器写，不影响同拍的组合判断。
    // 回包条目的 QPC 字段（两个入队点共用，避免两处副本漂移）
    task automatic fill_response_ctx;
        response_in.pmtu  <= qpc_pmtu(qp_context);
        response_in.pd    <= qpc_pd(qp_context);
        response_in.tos   <= qpc_tos(qp_context);
        response_in.ttl   <= qpc_ttl(qp_context);
        response_in.dmac  <= qpc_dmac(qp_context);
        response_in.dip   <= qpc_dip(qp_context);
        response_in.sport <= qpc_sport(qp_context);
        response_in.dqpn  <= qpc_dqpn(qp_context);
    endtask
    task automatic fin_fast_path;
        done_reg <= 1'b1;
        qp_expected_psn[qp_index[QP_W-1:LANE_BITS]] <= fin_expected_psn; qp_msn[qp_index[QP_W-1:LANE_BITS]]  <= fin_msn;
        qp_ack_counter[qp_index[QP_W-1:LANE_BITS]] <= fin_ack_counter;   qp_nak_sent[qp_index[QP_W-1:LANE_BITS]]  <= nak_sent;
        qp_rq_consumer[qp_index[QP_W-1:LANE_BITS]] <= rq_consumer;       qp_message_active[qp_index[QP_W-1:LANE_BITS]] <= fin_message_active;
        qp_cursor_key[qp_index[QP_W-1:LANE_BITS]] <= fin_cursor_key;     qp_cursor_address[qp_index[QP_W-1:LANE_BITS]]  <= fin_cursor_address;
        qp_cursor_remaining[qp_index[QP_W-1:LANE_BITS]] <= fin_cursor_remaining; qp_cursor_offset[qp_index[QP_W-1:LANE_BITS]] <= fin_cursor_offset;
        qp_cursor_wqe_index[qp_index[QP_W-1:LANE_BITS]] <= cursor_wqe_index;
        if (fin_send_response) begin
            response_in_valid <= 1'b1;
            response_in.qp_index    <= qp_index;
            response_in.is_read    <= is_read_request && !fin_ack;
            response_in.psn   <= ack_psn;
            response_in.syndrome   <= syndrome;
            response_in.msn   <= fin_msn;
            response_in.virtual_address    <= header.reth_virtual_address;
            response_in.rkey  <= header.reth_rkey;
            response_in.payload_length   <= header.reth_length;
            fill_response_ctx;
            if (syndrome == AETH_ACK) event_tx_ack <= !(is_read_request && !fin_ack);
            else                      event_tx_nak <= 1'b1;
        end
    endtask

    reg         payload_consumed;       // payload 已被收下
    reg         need_cqe, need_ack, need_error;
    reg  [7:0]  syndrome;
    reg  [23:0] ack_psn;
    reg  [7:0]  cqe_opcode, cqe_status;
    reg  [31:0] cqe_length;
    reg         need_rq_wqe;        // 本包需要取 RQ WQE
    reg  [3:0]  translate_access_main;
    reg  [31:0] translate_key_main;
    reg  [63:0] translate_address_main;
    reg  [12:0] translate_length_main;
    reg  [63:0] physical_address0, physical_page1;
    // 翻译口 0（主状态机）
    assign translate_valid[0] = (main_state == MAIN_TRANSLATE);
    assign translate_key[31:0]  = translate_key_main;
    assign translate_virtual_address[63:0]   = translate_address_main;
    assign translate_length[12:0]  = translate_length_main;
    assign translate_access[3:0]   = translate_access_main;
    assign translate_protection_domain[15:0]   = qpc_pd(qp_context);

    assign dma_read_request_page1 = dma_read_request_address + 64'd4096;
    assign dma_read_request_length   = 13'd32;
    assign dma_read_ready = 1'b1;                 // 取指数据只有一拍，状态机随时能收
    wire   payload_forward    = (main_state == MAIN_WRITE_DATA);
    wire   payload_drop   = (main_state == MAIN_DRAIN) && !payload_consumed;   // 已收完就不能再接下一包的数据
    assign dma_write_valid = payload_forward && rx_payload_valid;
    assign dma_write_data  = rx_payload_data;
    assign rx_payload_ready  = payload_forward ? dma_write_ready : payload_drop;

    always @(posedge clk) begin
        rx_header_ready       <= 1'b0;
        done_reg      <= 1'b0;
        // 回包 FIFO 入口的握手统一在这里清：FINISH 快路径压进条目后立刻回 IDLE，
        // 没有状态能替它撤 valid，所以清除逻辑必须与本状态机无关。
        if (response_in_valid && response_in_ready) begin
            response_in_valid <= 1'b0;
            resp_pending      <= 1'b0;
        end
        qp_set_error_main      <= '0;
        event_duplicate        <= 1'b0;
        event_sequence_error    <= 1'b0;
        event_tx_ack     <= 1'b0;
        event_tx_nak     <= 1'b0;
        event_rnr_nak    <= 1'b0;
        event_access_error <= 1'b0;
        event_drop       <= 1'b0;
        event_page_hit   <= 1'b0;
        event_page_miss  <= 1'b0;
        // MPT 写作废页缓存：MR 注销/重注册后同一 VA+rkey 可能指向新物理页，旧映射必须丢弃。
        // qp_state_change 只在 QP 状态确实变化时打脉冲（reset→reset 不产生），单靠它不足以覆盖
        // 「同一 QP 上先注销再注册 MR」这种状态不变的情形，所以这里直接盯 MPT 表写。
        if (table_request && table_write_enable && table_select == TBL_MPT) begin
            page_valid      <= 1'b0;
            page_next_valid <= 1'b0;
        end
        if (doorbell_rq_valid) qp_rq_producer[doorbell_data[QP_W-1:LANE_BITS]] <= doorbell_data[31:16];   // 门铃 [QP_W-1:0] = qp_idx
        // qp_state_change 是全局 QP_NUM 位的 one-hot 脉冲（roce_tbl 按全局索引打），
        // 非属主位恒为 0。循环按 QP_NUM 静态展开，qp 每一轮都是常量：属主轮的下标
        // qp[QP_W-1:LANE_BITS] 折成常量，非属主轮被 qp_owned 整段折掉。
        // 不用 (1<<qp) 变址移位，也不做 32 项动态选路。
        for (int qp = 0; qp < QP_NUM; qp++)
            if (qp_owned(QP_W'(qp), LANE_IDX) && qp_state_change[qp]) begin
                if (qp_state_i[qp*3 +: 3] <= QPS_INIT) begin
                    qp_rq_producer[qp[QP_W-1:LANE_BITS]] <= 16'd0;
                    qp_rq_consumer[qp[QP_W-1:LANE_BITS]] <= 16'd0;
                    qp_message_active[qp[QP_W-1:LANE_BITS]] <= 1'b0;
                end
                qp_expected_psn[qp[QP_W-1:LANE_BITS]] <= qpc_rq_psn(qpc_last_write);   // S3：同拍的 QPC 写入值
                qp_msn[qp[QP_W-1:LANE_BITS]]  <= 24'd0;
                qp_nak_sent[qp[QP_W-1:LANE_BITS]]  <= 1'b0;
                qp_ack_counter[qp[QP_W-1:LANE_BITS]] <= 5'd0;
                // 页缓存作废：QP 状态变化意味着主机可能已注销/重注册 MR，
                // 同一个 rkey 可能指向新的物理页，旧映射必须丢弃。
                // 两个缓存项（第 0 页 / 下一页）共用 key 与 PD，必须一起作废。
                page_valid      <= 1'b0;
                page_next_valid <= 1'b0;
            end
        if (rst) begin
            main_state        <= MAIN_IDLE;
            dma_read_request_valid  <= 1'b0;
            dma_write_request_valid  <= 1'b0;
            cqe_valid   <= 1'b0;
            response_in_valid <= 1'b0;
            resp_pending      <= 1'b0;
            page_valid  <= 1'b0;      // 页缓存随复位清空
            acc_err_cnt <= 32'd0;     // access error 快照计数（B6433；快照本体 sticky，复位不动也行，但一并清掉更直观）
            dbg_access_shot <= '0;
            // 同 roce_req：逐 QP 状态必须在硬/软复位时全部清空。
            // 只靠 qp_state_change 不够——它要求主机写的状态与 qp_state_store 不同，
            // 而复位后 qp_state_store 已是 RESET，新进程再写 RESET 不产生脉冲，
            // qp_message_active / qp_cursor_* 残留会让 RQ 从旧位置继续取 WQE。
            // 只清本 lane 的 32 项：非属主项本 lane 根本没有存储（S4 缩容），
            // 它们的状态在属主 lane 的复位里清，roce_top 对 4 个 lane 同时给 rst。
            for (int lq = 0; lq < LANE_QPS; lq++) begin
                qp_expected_psn[lq]      <= 24'd0;
                qp_msn[lq]               <= 24'd0;
                qp_ack_counter[lq]       <= 5'd0;
                qp_nak_sent[lq]          <= 1'b0;
                qp_rq_producer[lq]       <= 16'd0;
                qp_rq_consumer[lq]       <= 16'd0;
                qp_message_active[lq]    <= 1'b0;
                qp_cursor_key[lq]        <= 32'd0;
                qp_cursor_address[lq]    <= 64'd0;
                qp_cursor_remaining[lq]  <= 32'd0;
                qp_cursor_offset[lq]     <= 32'd0;
                qp_cursor_wqe_index[lq]  <= 16'd0;
            end
        end else begin
            // access error 快照的「已锁存」标志：软件写窗口基址或复位清；与 capture 在同一 always 块里，
            // capture 分支（MAIN_TRANSLATE_WAIT）后写，优先级更高。
            if (dbg_access_snapshot_clr) acc_err_seen <= 1'b0;
            case (main_state)
            // S3：QPC 改读 roce_tbl 的 M20K 寄存读口（地址 = rx_header.qp_index，恒发），装载拆成
            // 「命中就直接装 / 未命中先 MAIN_LOAD 一拍」两条路：
            //   qpc_hit = 读口数据就是本包 QP 且读那一沿没有 QPC 写入。头部从到达起一直保持
            //   valid 到被受理，地址提前一拍就发出去，所以稳态下 qpc_hit 恒成立，**仍是一拍装载**，
            //   与原来「IDLE 与 LOAD 合并」的拍数完全相同。
            //   代价（§63.5 必须实测的那 1 拍）：头部**刚到达**的那一拍（上一拍总线上的 qp_index 还是
            //   别人）、或读那一沿正好有主机 QPC 写入时，多停一拍 MAIN_LOAD 重读。1024 B 包每包
            //   固定开销原先约 1 拍（≈6%），若每包都吃到这一拍会变成 2 拍。本改动上板/仿真实测见
            //   roce-optimization-log.md §63.6：test_resp_profile 串行开销与改动前相同。
            // 原来的注释（保留作历史）：IDLE 与 LOAD 合并，省下的 1 拍在 1024 B 包上约占每包固定开销的 6%。
            MAIN_IDLE, MAIN_LOAD: if (rx_header_valid && !rx_header_ready && !qpc_hit) begin
                        main_state   <= MAIN_LOAD;         // 预读未命中：读口下一拍就是这个 QP
                    end else if (rx_header_valid && !rx_header_ready) begin
                        rx_header_ready <= 1'b1;
                        header       <= rx_header;
                        qp_index      <= rx_header.qp_index;
                        qp_context    <= {qpc_rd_data, qp_state_i[rx_header.qp_index*3 +: 3]};
                        // B6441：同一拍把 path_mtu 也装上（纯函数，与现算逐位等价，不加拍）
                        // **位偏移必须自己补**：qpc_rd_data 是 [508:0]，即 QPC 的 [511:3]（低 3 位 state
                        // 走另一条线，见上一行的拼接）。直接传给 qpc_xxx() 会被右对齐零扩展到 512 位，
                        // PMTU 取到的就是 QPC[8:6]（scq 的低位）而不是 QPC[5:3]——2026-11-14 凌晨
                        // 就是这么写错一版，导致所有多包 WRITE 报 REM_ACCESS_ERR（st=9）。
                        pmtu_code_q   <= qpc_pmtu({qpc_rd_data, 3'd0});
                        path_mtu_q    <= pmtu_bytes(qpc_pmtu({qpc_rd_data, 3'd0}));
                        // S4：索引取 rx_header.qp_index 的 lane 局部位（qp_index 寄存器这一拍才装载，
                        // 还不能用）。32:1 选路，不是 128:1——这是缩容的收益所在。
                        expected_psn <= qp_expected_psn[rx_header.qp_index[QP_W-1:LANE_BITS]];  msn  <= qp_msn[rx_header.qp_index[QP_W-1:LANE_BITS]];  ack_counter <= qp_ack_counter[rx_header.qp_index[QP_W-1:LANE_BITS]];
                        nak_sent <= qp_nak_sent[rx_header.qp_index[QP_W-1:LANE_BITS]];   rq_consumer <= qp_rq_consumer[rx_header.qp_index[QP_W-1:LANE_BITS]]; message_active <= qp_message_active[rx_header.qp_index[QP_W-1:LANE_BITS]];
                        cursor_key <= qp_cursor_key[rx_header.qp_index[QP_W-1:LANE_BITS]];  cursor_address  <= qp_cursor_address[rx_header.qp_index[QP_W-1:LANE_BITS]];  cursor_remaining <= qp_cursor_remaining[rx_header.qp_index[QP_W-1:LANE_BITS]];
                        cursor_offset <= qp_cursor_offset[rx_header.qp_index[QP_W-1:LANE_BITS]];  cursor_wqe_index <= qp_cursor_wqe_index[rx_header.qp_index[QP_W-1:LANE_BITS]];
                        payload_consumed <= (rx_header.payload_length == 13'd0);
                        need_cqe <= 1'b0; need_ack <= 1'b0; need_error <= 1'b0; need_rq_wqe <= 1'b0;
                        main_state   <= MAIN_CLASSIFY;
                    end else begin
                        main_state   <= MAIN_IDLE;
                    end
            MAIN_CLASSIFY: begin
                syndrome     <= AETH_ACK;
                ack_psn <= header.psn;
                if (header.bad || !header.qp_valid || !qp_state_ok || !is_request) begin
                    event_drop <= 1'b1;
                    main_state      <= MAIN_DRAIN;
                end else if (psn_delta != 24'd0 && psn_delta[23]) begin          // 重复包
                    event_duplicate <= 1'b1;
                    if (is_read_request) begin
                        main_state <= MAIN_ACK;                                     // 重新执行 READ
                    end else begin
                        need_ack  <= 1'b1;
                        ack_psn <= expected_psn - 24'd1;
                        main_state      <= MAIN_ACK;
                    end
                end else if (psn_delta != 24'd0) begin                       // 超前：NAK 一次
                    event_sequence_error <= 1'b1;
                    if (!nak_sent) begin
                        nak_sent    <= 1'b1;
                        need_ack  <= 1'b1;
                        syndrome     <= AETH_NAK_SEQ;
                        ack_psn <= expected_psn;
                        main_state      <= MAIN_ACK;
                    end else
                        main_state <= MAIN_DRAIN;
                end else begin
                    nak_sent <= 1'b0;
                    if (!length_ok && !is_read_request) begin
                        need_error <= 1'b1; need_ack <= 1'b1; syndrome <= AETH_NAK_INV;
                        main_state <= MAIN_ACK;
                    end else if (is_send && !message_active) begin
                        if (!is_send_first) begin
                            need_error <= 1'b1; need_ack <= 1'b1; syndrome <= AETH_NAK_INV;
                            main_state <= MAIN_ACK;
                        end else if (rq_is_empty) begin
                            // UD 没有 RNR 语义（对端不会重传）：RQ 空时静默丢包，不回首包 RNR_NAK。
                            // 回 NAK 反而会让对端把一条「不可靠」报文当可靠报文处理。
                            if (is_ud_send) begin
                                event_drop <= 1'b1;
                                main_state <= MAIN_DRAIN;
                            end else begin
                                event_rnr_nak <= 1'b1;
                                need_ack <= 1'b1; syndrome <= AETH_RNR_NAK | {3'd0, qpc_min_rnr(qp_context)};
                                main_state <= MAIN_ACK;
                            end
                        end else
                            main_state <= MAIN_RQ_FETCH;
                    end else if (is_send) begin
                        if (is_ud_send) begin
                            // UD 的 message_active 应该恒 0（每包都是一条完整消息）。真走到这里说明
                            // 同一 QP 上还有 RC 的 SEND 消息未收完——不报错、不毁 QP，静默丢这一包。
                            event_drop <= 1'b1;
                            main_state <= MAIN_DRAIN;
                        end else if (is_send_first || {19'd0, header.payload_length} > cursor_remaining) begin
                            need_error <= 1'b1; need_ack <= 1'b1; syndrome <= AETH_NAK_INV;
                            main_state <= MAIN_ACK;
                        end else begin
                            translate_key_main <= cursor_key; translate_address_main <= cursor_address; translate_length_main <= header.payload_length;
                            translate_access_main <= ACC_LOCAL_WRITE;
                            main_state <= MAIN_TRANSLATE;
                        end
                    end else if (is_write_first || is_write_continue) begin
                        if (is_write_continue && (!message_active || {19'd0, header.payload_length} > cursor_remaining)) begin
                            need_error <= 1'b1; need_ack <= 1'b1; syndrome <= AETH_NAK_INV;
                            main_state <= MAIN_ACK;
                        end else if (is_write_first && ({19'd0, header.payload_length} > header.reth_length ||
                                               (opcode == OP_WRITE_ONLY || opcode == OP_WRITE_ONLY_IMM) &&
                                               {19'd0, header.payload_length} != header.reth_length)) begin
                            need_error <= 1'b1; need_ack <= 1'b1; syndrome <= AETH_NAK_INV;
                            main_state <= MAIN_ACK;
                        end else if (is_write_with_immediate && rq_is_empty) begin
                            event_rnr_nak <= 1'b1;
                            need_ack <= 1'b1; syndrome <= AETH_RNR_NAK | {3'd0, qpc_min_rnr(qp_context)};
                            main_state <= MAIN_ACK;
                        end else if (page_hit) begin
                            // 页缓存命中：同 key、同 4 KB 页的 WRITE 包（B6390 起含首包），映射必然相同。
                            // 直接拼出物理地址并跳过 MAIN_TRANSLATE + MAIN_TRANSLATE_WAIT 共 5 拍。
                            // pa1 用缓存里 page1 的基址，与翻译表输出的 {page1[63:12], 12'd0} 同构，
                            // 保证跨 4 KB 边界的包仍能正确写到下一页。
                            //
                            // 请求 valid 与地址在这里就置起来（与 TRANSLATE_WAIT 里的翻译路径同样做法）：
                            // 否则进 MAIN_WRITE_REQUEST 时 valid 还是 0，要多花一拍才拉起，
                            // 会把刚省下的翻译拍数吐回去（仿真实测 WRITE_REQUEST 1.00 → 1.73）。
                            //
                            // physical_address0/page1 也必须一起写：MAIN_WRITE_REQUEST 在握手未完成时
                            // 会用这两个寄存器**重新驱动** dma_write_request_*。只写 dma_write_request_*
                            // 的话，ready 晚一拍就会把地址覆盖成上一包的旧值（写错内存）。
                            //
                            // 偏移取 page_cmp_va[11:0] 而不是 cursor_address[11:0]：首包的 cursor 还是
                            // 上一消息的残值，用它会写错页内偏移。
                            event_page_hit            <= 1'b1;
                            physical_address0         <= {page_hit_pa0_base, page_cmp_va[11:0]};
                            physical_page1            <= {page_hit_pa1_base, 12'd0};
                            dma_write_request_valid   <= 1'b1;
                            dma_write_request_address <= {page_hit_pa0_base, page_cmp_va[11:0]};
                            dma_write_request_page1   <= {page_hit_pa1_base, 12'd0};
                            dma_write_request_length  <= header.payload_length;
                            main_state <= MAIN_WRITE_REQUEST;
                        end else begin
                            translate_key_main <= is_write_first ? header.reth_rkey : cursor_key;
                            translate_address_main  <= is_write_first ? header.reth_virtual_address   : cursor_address;
                            translate_length_main <= header.payload_length;
                            translate_access_main <= ACC_REMOTE_WRITE;
                            need_rq_wqe  <= is_write_with_immediate;
                            event_page_miss <= (header.payload_length != 13'd0); // 零长度包不计 miss：它根本没走缓存路径
                            main_state       <= is_write_with_immediate ? MAIN_RQ_FETCH : MAIN_TRANSLATE;
                        end
                    end else begin                                       // READ 请求
                        translate_key_main <= header.reth_rkey; translate_address_main <= header.reth_virtual_address; translate_length_main <= 13'd0;
                        translate_access_main <= ACC_REMOTE_READ;
                        main_state <= MAIN_TRANSLATE;
                    end
                end
            end
            MAIN_RQ_FETCH:  begin
                       dma_read_request_valid <= 1'b1;
                       dma_read_request_address  <= qpc_rq_base(qp_context) +
                                   {43'd0, rq_consumer & ((16'd1 << qpc_rq_lg(qp_context)) - 16'd1), 5'd0};
                       if (dma_read_request_valid && dma_read_request_ready) begin
                           dma_read_request_valid <= 1'b0;
                           main_state       <= MAIN_RQ_WAIT;
                       end
                   end
            MAIN_RQ_WAIT: if (dma_read_valid) begin
                       cursor_wqe_index <= rq_consumer;
                       rq_consumer <= rq_consumer + 16'd1;
                       if (is_send) begin
                           message_active <= 1'b1;
                           cursor_key <= dma_read_data[63:32];
                           cursor_address  <= dma_read_data[127:64];
                           cursor_remaining <= dma_read_data[31:0];
                           cursor_offset <= 32'd0;
                           if ({19'd0, header.payload_length} > dma_read_data[31:0]) begin
                               need_cqe <= 1'b1; cqe_opcode <= WC_RECV; cqe_status <= WCS_LOC_LEN_ERR;
                               cqe_length <= 32'd0;
                               /* UD 没有 ACK/NAK 语义（IBTA §9.8.5）：出错只报本地 CQE，
                                * 不能回线上 NAK，否则对端会收到一个不该存在的 ACK/Nak。 */
                               if (!is_ud_send) begin
                                   need_error <= 1'b1; need_ack <= 1'b1; syndrome <= AETH_NAK_INV;
                               end
                               main_state <= MAIN_CQE;
                           end else begin
                               translate_key_main <= dma_read_data[63:32]; translate_address_main <= dma_read_data[127:64];
                               translate_length_main <= header.payload_length; translate_access_main <= ACC_LOCAL_WRITE;
                               main_state <= MAIN_TRANSLATE;
                           end
                       end else
                           main_state <= MAIN_TRANSLATE;                                  // WRITE w/ Imm：只占 RQ 槽
                   end
            MAIN_TRANSLATE:  if (translate_ready[0]) main_state <= MAIN_TRANSLATE_WAIT;
            MAIN_TRANSLATE_WAIT: if (translate_response[0]) begin
                       physical_address0 <= translate_physical_address0;
                       physical_page1 <= translate_physical_page1;
                       if (translate_error) begin
                           event_access_error <= 1'b1;
                           acc_err_cnt <= acc_err_cnt + 32'd1;
                           if (!acc_err_seen) begin
                               acc_err_seen <= 1'b1;
                               dbg_access_shot <= {cursor_remaining, cursor_offset,
                                                 {translate_length_main, 3'd0, rq_consumer},
                                                 translate_address_main[31:0], translate_key_main, header.psn,
                                                 // S4：qp_index 从 4 位截断改成 QP_W 位（128 QP 下 7 位），
                                                 // 去掉原来的 3'd0 填充正好补上 3 位，字宽仍是 32。
                                                 // 字段位置随之变成 [19:13] —— tool/roce_acc_snapshot.sh 要同步改。
                                                 {header.opcode, header.bad, header.qp_valid, 2'd0, QP_W'(qp_index),
                                                  header.payload_length}};
                           end
                           /* 同 M2a：UD 的翻译失败只报 CQE，不回 NAK。 */
                           if (!is_ud_send) begin
                               need_error <= 1'b1; need_ack <= 1'b1; syndrome <= AETH_NAK_ACCESS;
                           end
                           if (is_send) begin
                               need_cqe <= 1'b1; cqe_opcode <= WC_RECV; cqe_status <= WCS_LOC_PROT_ERR;
                               cqe_length <= 32'd0;
                               main_state <= MAIN_CQE;
                           end else
                               main_state <= MAIN_ACK;
                       end else if (header.payload_length != 13'd0 && !is_read_request) begin
                           // 写请求与翻译结果同拍发出：地址直接取翻译输出，不再等 physical_address0
                           // 寄存一拍。MAIN_WRITE_REQUEST 只需等 ready 并撤 valid，省 1 拍。
                           dma_write_request_valid <= 1'b1;
                           dma_write_request_address  <= translate_physical_address0;
                           dma_write_request_page1 <= translate_physical_page1;
                           dma_write_request_length   <= header.payload_length;
                           // 填充页缓存，供本消息后续 continuation 包直接命中。
                           // 只对远端写（WRITE）填：SEND 走同一分支但用 ACC_LOCAL_WRITE，
                           // 访问类型不同，混进缓存会让 WRITE 绕过应有的权限语义。
                           if (!is_send) begin
                               page_valid     <= 1'b1;
                               page_key       <= translate_key_main;
                               page_pd        <= qpc_pd(qp_context);   // 命中时要用它挡跨 PD 访问
                               page_va_base   <= translate_address_main[63:12];
                               page_pa0_base  <= translate_physical_address0[63:12];
                               page_pa1_base  <= translate_physical_page1[63:12];
                               // 下一页缓存项：同一 key/PD，VA = 本页 + 1，物理基址就是本页的 page1。
                               // 表里已经把 next page 算好了，这里直接捡现成的，不需要额外翻译。
                               page_next_valid    <= 1'b1;
                               page_next_pa0_base <= translate_physical_page1[63:12];
                           end
                           main_state <= MAIN_WRITE_REQUEST;
                       end else
                           main_state <= MAIN_FINISH;
                   end
            MAIN_WRITE_REQUEST:  begin
                       dma_write_request_valid <= 1'b1;
                       dma_write_request_address  <= physical_address0;
                       dma_write_request_page1 <= physical_page1;
                       dma_write_request_length   <= header.payload_length;
                       if (dma_write_request_valid && dma_write_request_ready) begin
                           dma_write_request_valid <= 1'b0;
                           main_state       <= MAIN_WRITE_DATA;
                       end
                   end
            // B6391：快路径与末拍 payload 合并。fin_* 全部由 header 与工作副本组合得出，
            // 在 WRITE_DATA 期间就已有效，所以末拍这一拍就能把「写回 per-QP 数组 + 打 done
            // + 回 ACK」做完直接回 IDLE，不必先进 FINISH 再等一拍。省下的这 1 拍正好落在
            // 包间空档上（B6390 实测每包 15.000 拍里有 4 拍是 resp 空转）。
            // 两个例外仍进 FINISH：需要发 CQE（字段要先寄存）与上一包回包还占着 FIFO 入口。
            MAIN_WRITE_DATA:  if (rx_payload_valid && dma_write_ready && rx_payload_last) begin
                       payload_consumed <= 1'b1;
                       if (fin_fast_ready) begin
                           fin_fast_path;
                           main_state <= MAIN_IDLE;
                       end else
                           main_state <= MAIN_FINISH;
                   end
            MAIN_FINISH: begin
                // 只有 fin_fast_ready 不成立的两种情况才进这里：要发 CQE（字段必须先寄存），
                // 或上一包回包还占着 response_in。走到末尾那个 else 时条件已经满足，
                // 仍复用 fin_fast_path，与 WRITE_DATA 末拍的语义完全一致。
                // 注意 working copy（cursor_*、expected_psn 等）在这些分支里不再更新——下一包的 MAIN_IDLE
                // 全部从 per-QP 数组重新装载，所以直接写数组与写副本再转存等价。
                if (fin_need_cqe) begin
                    // 慢路径：SEND / WRITE_IMM 末包要发 CQE，CQE 字段必须先寄存一拍，仍走 CQE→ACK→WRITE_BACK。
                    if (is_send) begin
                        cursor_remaining <= fin_cursor_remaining;
                        cursor_offset <= fin_cursor_offset;
                        cursor_address  <= fin_cursor_address;
                        need_cqe  <= 1'b1;
                        cqe_opcode  <= WC_RECV;
                        cqe_status  <= WCS_SUCCESS;
                        cqe_length <= fin_cursor_offset;
                    end else begin
                        // LAST_IMM 不改 cursor_key（与合并前一致），ONLY_IMM（is_write_first）才记 rkey
                        cursor_key <= fin_cursor_key;
                        cursor_address  <= fin_cursor_address;
                        cursor_remaining <= fin_cursor_remaining;
                        // LAST_IMM 不改 cursor_offset（与合并前一致），ONLY_IMM 置为 reth_length
                        cursor_offset <= fin_cursor_offset;
                        need_cqe  <= 1'b1;
                        cqe_opcode  <= WC_RECV_RDMA_IMM;
                        cqe_status  <= WCS_SUCCESS;
                        cqe_length <= is_write_first ? header.reth_length : cursor_offset;
                    end
                    message_active <= fin_message_active;
                    expected_psn <= is_read_request ? fin_expected_psn : expected_psn + 24'd1;
                    msn <= is_read_request ? msn + 24'd1 : (is_message_end ? msn + 24'd1 : msn);
                    if (fin_ack) begin need_ack <= 1'b1; ack_counter <= 5'd0; end
                    else ack_counter <= ack_counter + 5'd1;
                    main_state <= MAIN_CQE;
                end else if (fin_send_response && response_in_valid) begin
                    // 上一包的回包还占着 FIFO 入口：原地等位置，不更新任何状态。
                    // 工作副本不动，等下一拍 response_in_valid 落下后再走快路径，重算结果相同（幂等）。
                    // 不能转去 MAIN_ACK——那里分不清"在途的旧回包"和"本包的回包"。
                    main_state <= MAIN_FINISH;
                end else begin
                    fin_fast_path;
                    main_state <= MAIN_IDLE;
                end
            end
            MAIN_CQE: begin
                cqe_valid <= 1'b1;
                cqe_cq_index    <= qpc_rcq(qp_context);
                // dw4[24:0] = {src_qp_valid, src_qp[23:0]}：UD recv 时填 DETH 源 QPN；RC 时全 0。
                // dw0[18] = has_grh：**恒 0**。GRH 目前没有实现——接收缓冲里只有 payload，
                // 没有那 40 B（RoCEv2 线上本来就没有 GRH，要由接收侧从 IPv4/UDP 头合成）。
                // 声明 has_grh=1 会让 ULP 按 IB 语义从 buf[40] 起读载荷（标准 ud_pingpong 就是
                // 这么写的），读到的是错位数据。dw4 的 src_qp 仍然有效（DETH 里有），
                // 只是不带 IBV_WC_GRH 标志。实现 GRH 写入后再把这一位改回 header.has_deth，
                // 并同步 yuanrdma_hw.h 的 dw0[18] 与 provider 的注释。
                // dw0[17] = is_recv（recv CQE 恒 1，不能丢）。
                cqe_data   <= {7'd0, header.has_deth, header.deth_src_qp,     // dw4[31:0]
                               (header.has_immediate ? header.immediate : 32'd0), cqe_length,
                               8'd0, 8'(qp_index), cursor_wqe_index,          // dw1[23:16] qp_idx（ABI 8 位）
                               1'b0, 12'd0, 1'b0, 1'b1, header.has_immediate, cqe_status, cqe_opcode};
                if (cqe_valid && cqe_ready) begin
                    cqe_valid <= 1'b0;
                    main_state      <= MAIN_ACK;
                end
            end
            MAIN_ACK: begin
                // 入队条件改用 resp_pending：FINISH 快路径会把回包留在 FIFO 入口就回 IDLE，
                // 那时 response_in_valid 可能仍是上一包的在途条目，用它会误判成本包已入队。
                if ((need_ack || is_read_request) && !resp_pending && !response_in_valid) begin
                    response_in_valid <= 1'b1;
                    resp_pending      <= 1'b1;
                    response_in.qp_index    <= qp_index;
                    response_in.is_read    <= is_read_request && !need_ack;
                    response_in.psn   <= ack_psn;
                    response_in.syndrome   <= syndrome;
                    response_in.msn   <= msn;   // 注意：这里是自增前的 msn，与 fin_fast_path（:290）用的 fin_msn（已 +1）不一致。
                    // 本端 roce_req 不读 msn，自环测不出差异；接 CX7 跑 SEND 混合流量时
                    // 两条路径回的 AETH msn 不同，可能暴露。待统一（见 §28.7 疑点 6）。
                    response_in.virtual_address    <= header.reth_virtual_address;
                    response_in.rkey  <= header.reth_rkey;
                    response_in.payload_length   <= header.reth_length;
                    fill_response_ctx;
                    if (syndrome == AETH_ACK) event_tx_ack <= !(is_read_request && !need_ack);
                    else                 event_tx_nak <= 1'b1;
                end
                // 本条已进 FIFO 就算交接完成；FIFO 入口的 valid 由顶部统一撤。
                if (resp_pending && response_in_valid) begin
                    // payload 已在 MAIN_WRITE_DATA 收完、且不需要置 QP 错误时，DRAIN 只是空转一拍，
                    // 直接进 WRITE_BACK。
                    main_state <= (payload_consumed && !need_error) ? MAIN_WRITE_BACK : MAIN_DRAIN;
                end else if (!(need_ack || is_read_request) && !resp_pending)
                    main_state <= (payload_consumed && !need_error) ? MAIN_WRITE_BACK : MAIN_DRAIN;
            end
            MAIN_DRAIN: if (payload_consumed || (rx_payload_valid && rx_payload_last)) begin
                         // UD 的错误不把 QP 打进 ERR：UD 没有重传，一个坏包不该毁掉整个 QP。
                         // 错误本身仍按路径报（长度不符 → LOCAL_LEN_ERR CQE；翻译失败 → LOC_PROT_ERR）。
                         if (need_error && !is_ud_send) qp_set_error_main[qp_index] <= 1'b1;
                         main_state <= MAIN_WRITE_BACK;
                     end
            MAIN_WRITE_BACK: begin
                qp_expected_psn[qp_index[QP_W-1:LANE_BITS]] <= expected_psn; qp_msn[qp_index[QP_W-1:LANE_BITS]]  <= msn;  qp_ack_counter[qp_index[QP_W-1:LANE_BITS]] <= ack_counter;
                qp_nak_sent[qp_index[QP_W-1:LANE_BITS]]  <= nak_sent; qp_rq_consumer[qp_index[QP_W-1:LANE_BITS]] <= rq_consumer; qp_message_active[qp_index[QP_W-1:LANE_BITS]] <= message_active;
                qp_cursor_key[qp_index[QP_W-1:LANE_BITS]] <= cursor_key; qp_cursor_address[qp_index[QP_W-1:LANE_BITS]]  <= cursor_address;  qp_cursor_remaining[qp_index[QP_W-1:LANE_BITS]] <= cursor_remaining;
                qp_cursor_offset[qp_index[QP_W-1:LANE_BITS]] <= cursor_offset; qp_cursor_wqe_index[qp_index[QP_W-1:LANE_BITS]] <= cursor_wqe_index;
                done_reg <= 1'b1;
                main_state   <= MAIN_IDLE;
            end
            default: main_state <= MAIN_IDLE;
            endcase
        end
    end
    // ------------------------------------------------------------ 输出状态机
    localparam [2:0] OUT_IDLE = 3'd0, OUT_ACK = 3'd1, OUT_READ_CHUNK = 3'd2, OUT_TRANSLATE = 3'd3, OUT_TRANSLATE_WAIT = 3'd4,
                     OUT_EMIT = 3'd5, OUT_NAK = 3'd6;
    reg  [2:0]   out_state;
    assign debug_state = {out_state, main_state};
    response_entry_t        entry;
    reg  [12:0]  out_path_mtu;
    reg  [15:0]  out_protection_domain;
    reg  [63:0]  out_address;
    reg  [31:0]  out_remaining;
    reg  [23:0]  out_psn;
    reg          out_first, out_last_chunk;
    reg  [12:0]  out_chunk_length;
    reg  [63:0]  out_physical_address0, out_physical_page1;
    reg  [QP_NUM-1:0] qp_set_error_out;
    assign qp_set_error = qp_set_error_main | qp_set_error_out;
    // B6439：READ RESP 的 opcode 与派生长度共用（out_first/out_last_chunk 只在本状态机里改）
    wire [7:0]   out_emit_opcode = (out_first && out_last_chunk) ? OP_READ_RESP_ONLY :
                                   out_first ? OP_READ_RESP_FIRST :
                                   out_last_chunk  ? OP_READ_RESP_LAST : OP_READ_RESP_MID;

    assign translate_valid[1]     = (out_state == OUT_TRANSLATE);
    assign translate_key[63:32]   = entry.rkey;
    assign translate_virtual_address[127:64]   = out_address;
    assign translate_length[25:13]   = out_chunk_length;
    assign translate_access[7:4]     = ACC_REMOTE_READ;
    assign translate_protection_domain[31:16]    = out_protection_domain;

    // 回包任务的组头字段 + 派生长度（S3 与 B6439 的字段在同一处装，避免两版各自漂移）
    task automatic fill_job_hdr(input logic [7:0] opcode, input logic [12:0] payload_length);
        tx_job.tos       <= entry.tos;
        tx_job.ttl       <= entry.ttl;
        tx_job.dmac      <= entry.dmac;
        tx_job.dip       <= entry.dip;
        tx_job.sport     <= entry.sport;
        tx_job.dqpn      <= entry.dqpn;
        tx_job.csum_base <= ip_csum_base(entry.dip, entry.ttl, local_ip);
        // B6439：头长随 opcode 变（ACK/NAK 58 B；READ RESP 70/58/62 B 视 RETH/AETH/IMM）
        tx_job.header_length   <= tx_header_length(opcode);
        tx_job.header_skip     <= 7'd128 - tx_header_length(opcode);
        tx_job.ip_total_length <= tx_ip_total_length(opcode, payload_length);
        tx_job.frame_length    <= tx_frame_length(opcode, payload_length);
    endtask
    always @(posedge clk) begin
        qp_set_error_out   <= '0;
        response_out_ready <= 1'b0;
        if (rst) begin
            out_state      <= OUT_IDLE;
            tx_job_valid <= 1'b0;
        end else case (out_state)
            OUT_IDLE: if (response_out_valid && !response_out_ready) begin
                        response_out_ready <= 1'b1;
                        entry      <= response_out;
                        out_path_mtu  <= pmtu_bytes(response_out.pmtu);
                        out_protection_domain    <= response_out.pd;
                        out_address    <= response_out.virtual_address;
                        out_remaining   <= response_out.payload_length;
                        out_psn   <= response_out.psn;
                        out_first <= 1'b1;
                        out_state     <= response_out.is_read ? OUT_READ_CHUNK : OUT_ACK;
                    end
            OUT_ACK, OUT_NAK: begin
                        tx_job_valid        <= 1'b1;
                        tx_job          <= '0;
                        tx_job.qp_index       <= entry.qp_index;
                        tx_job.opcode   <= OP_ACK;
                        tx_job.psn      <= out_psn;
                        tx_job.aeth_syndrome <= (out_state == OUT_NAK) ? AETH_NAK_ACCESS : entry.syndrome;
                        tx_job.aeth_msn <= entry.msn;
                        fill_job_hdr(OP_ACK, 13'd0);
                        if (tx_job_valid && tx_job_ready) begin
                            tx_job_valid <= 1'b0;
                            out_state      <= OUT_IDLE;
                        end
                    end
            OUT_READ_CHUNK:  begin
                        out_chunk_length <= (out_remaining > {19'd0, out_path_mtu}) ? out_path_mtu : out_remaining[12:0];
                        out_last_chunk <= (out_remaining <= {19'd0, out_path_mtu});
                        out_physical_address0  <= '0;
                        out_physical_page1  <= '0;
                        out_state    <= (out_remaining == 32'd0) ? OUT_EMIT : OUT_TRANSLATE;
                    end
            OUT_TRANSLATE:   if (translate_ready[1]) out_state <= OUT_TRANSLATE_WAIT;
            OUT_TRANSLATE_WAIT:  if (translate_response[1]) begin
                        out_physical_address0 <= translate_physical_address0;
                        out_physical_page1 <= translate_physical_page1;
                        if (translate_error) begin
                            qp_set_error_out[entry.qp_index] <= 1'b1;
                            out_state <= OUT_NAK;
                        end else
                            out_state <= OUT_EMIT;
                    end
            OUT_EMIT: begin
                        tx_job_valid        <= 1'b1;
                        tx_job          <= '0;
                        tx_job.qp_index       <= entry.qp_index;
                        tx_job.opcode   <= out_emit_opcode;
                        tx_job.psn      <= out_psn;
                        tx_job.aeth_syndrome <= AETH_ACK;
                        tx_job.aeth_msn <= entry.msn;
                        tx_job.payload_length      <= out_chunk_length;
                        tx_job.physical_address0      <= out_physical_address0;
                        tx_job.physical_page1      <= out_physical_page1;
                        fill_job_hdr(out_emit_opcode, out_chunk_length);
                        if (tx_job_valid && tx_job_ready) begin
                            tx_job_valid <= 1'b0;
                            out_address     <= out_address + {51'd0, out_chunk_length};
                            out_remaining    <= out_remaining - {19'd0, out_chunk_length};
                            out_psn    <= out_psn + 24'd1;
                            out_first  <= 1'b0;
                            out_state      <= out_last_chunk ? OUT_IDLE : OUT_READ_CHUNK;
                        end
                    end
            default: out_state <= OUT_IDLE;
        endcase
    end
endmodule
`default_nettype wire
