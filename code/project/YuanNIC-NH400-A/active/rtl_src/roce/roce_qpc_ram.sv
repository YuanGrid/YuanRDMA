// roce_qpc_ram.sv
// QPC 存储（高位部分）：每 lane 一份的 M20K 双口 RAM，寄存读（S3）。
//
// 为什么单独一个模块
//   现在 roce_tbl 里的 QPC 是 `reg [511:0] qpc_store [QP_NUM]` 的全组合读：
//   `assign qpc[qp*512 +: 512] = {qpc_store[qp][511:3], qp_state_store[qp]}`
//   下游 req/resp/tx 各自按索引切片，16 QP 时是 16 选 1，128 QP 就是 128 选 1 × 512 位。
//   core_clk 现在 slack 0.002 ns，这条路是 B6383 起的历史关键路径起点，扩 QP 必须换成
//   RAM + 寄存读（读地址打一拍，数据下一拍出）。
//
// 为什么只存 [511:3]
//   QPC 的 [2:0] 是 QP state，必须复位成 RESET；M20K 没有复位端，模块内自己逐项清零要
//   扫 16（128 时 32）拍，这段时间 QP 状态不可用。所以 state 继续留在 roce_tbl 的
//   3 bit × QP_NUM 寄存器阵列（qp_state_store）里，本模块只存不要求复位的其余 509 位。
//   复位后 RAM 内容是未定义值，但在 QP 被写 QPC 之前它不会被任何有效状态读到。
//
// 读口：寄存读，rd_en 那一拍给地址，下一拍 rd_data 有效（rd_valid 与数据同拍）。
//
// S4：按 lane 缩容——DEPTH 与 IDX_LSB 必须成对传
//   每 lane 只持有 QP_NUM/4 个 QP，且持有的是全局索引低 2 位等于本 lane 号的那些 QP
//   （qp_index[1:0] == LANE_ID），也就是全局索引**交错**、步长 4。所以本 lane 的项槽由全局索引
//   的 [6:2] 选，低 2 位丢掉：
//       DEPTH = LANE_QPS(32)，IDX_LSB = LANE_BITS(2)  →  mem[addr[2 +: 5]]
//   这两个参数是一个整体，只传一半全是静默错误，不会有编译或仿真报错：
//     - DEPTH 缩到 32、IDX_LSB 还是 0：只剩 addr[4:0] 参与寻址，本 lane 的 4 个 QP
//       （qp = Lid + 4k，addr[4:0] 每 4 个一循环）落在同一个槽上 4 路别名，互相覆盖；
//     - 只传 IDX_LSB、DEPTH 还是 128：4/5 的槽永远空着，白占 3 倍 M20K。
//   全表模式（单测台子，LANE_ID < 0）传 DEPTH = QP_NUM、IDX_LSB = 0，行为与 S3 逐位相同。
//
// 铁律：rd_addr_q 原样回传**全局**地址，不许改成局部索引。消费方拿 rd_addr_q 与全局 qp_index
//   比较（roce_req:453 的 ctx_ready、roce_req:247 的 fetch_qpc_ok、roce_resp:141 的 qpc_hit）；
//   回传局部索引后比较恒不等，每包多停一拍、带宽腰斩。
//
// S3 消费方用法（连续读）：rd_en 恒 1，每拍把「本拍想要的 QP」送到 rd_addr；下一拍
//   rd_addr_q = 产生 rd_data 的地址，rd_fresh = 读那一沿没有写入（no_rw_check 下同址同沿读写结果
//   未定义，所以只要那一沿有任何写就判不新鲜，让消费方多等一拍重读）。
//   rd_fresh && rd_addr_q == 想要的 QP 时，rd_data 与原来组合读 qpc_store 在本拍给出的值逐位相同
//   （都包含到上一沿为止的全部写入）。
`default_nettype none
`timescale 1ns/1ps
module roce_qpc_ram
    import roce_pkg::*;
#(
    parameter int DEPTH = QP_NUM,         // 每 lane 的项数（lane 模式 QP_NUM >> LANE_BITS，全表模式 QP_NUM）
    // 全局地址里本 RAM 项槽的起始位：lane 模式 = LANE_BITS，全表模式 = 0。必须与 DEPTH 成对给，
    // 见文件头「DEPTH 与 IDX_LSB 必须成对传」。
    parameter int IDX_LSB = 0,
    parameter int WIDTH = 509
)(
    input  wire              clk,
    input  wire              rst,
    // 写口（表命令已在外部合成好单一口）
    input  wire              wr_en,
    input  wire  [15:0]      wr_addr,     // 全局 QP 索引
    input  wire  [WIDTH-1:0] wr_data,     // QPC[511:3]
    // 读口：寄存读
    input  wire              rd_en,
    input  wire  [15:0]      rd_addr,     // 全局 QP 索引
    output reg   [WIDTH-1:0] rd_data,
    output reg               rd_valid,
    output reg   [15:0]      rd_addr_q,   // 产生 rd_data 的地址（全局 QP 索引，原样回传）
    output reg               rd_fresh     // 读那一沿没有写入
);
    localparam int ADDR_W = (DEPTH > 1) ? $clog2(DEPTH) : 1;

    (* ramstyle = "no_rw_check,m20k" *) reg [WIDTH-1:0] mem [DEPTH];

    always @(posedge clk) begin
        if (wr_en)
            mem[wr_addr[IDX_LSB +: ADDR_W]] <= wr_data;
        // 寄存读：读地址当拍锁住，下一拍数据有效
        if (rd_en) begin
            rd_data   <= mem[rd_addr[IDX_LSB +: ADDR_W]];
            rd_addr_q <= rd_addr;
            rd_fresh  <= !wr_en;
        end
        rd_valid <= rd_en;
    end
endmodule
`default_nettype wire
