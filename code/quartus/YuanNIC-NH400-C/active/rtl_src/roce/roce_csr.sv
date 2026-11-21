// roce_csr.sv
// RoCE 引擎 CSR：全局寄存器、表写口、doorbell、计数器、DMA 自测。地址见 yuanrdma_hw.h。
// AVMM 时序复用 util/avm_register.sv（读 2 拍、写 1 拍返回）。
`default_nettype none
`timescale 1ns/1ps
module roce_csr
    import roce_pkg::*;
#(
    parameter int CORE_CLOCK_MHZ = 250
)(
    input  wire                 clk,
    input  wire                 rst_n,
    // AVMM slave（clk 域）
    input  wire  [27:0]         upstream_address,
    input  wire                 upstream_read,
    input  wire                 upstream_write,
    input  wire  [31:0]         upstream_write_data,
    output wire                 upstream_wait,
    output wire  [31:0]         upstream_read_data,
    output wire                 upstream_read_valid,
    output wire  [1:0]          upstream_response,
    output wire                 upstream_write_response,
    // 全局
    output reg                  ctrl_enable,
    // REG_CTRL[2] = PFC_GATE_DIS（写 1 关门控，复位 0）。故意做成「关」位：驱动/rdmacli 都只写
    // CTRL=ENABLE，若做成 enable 位，每次写 CTRL 都会把门控清掉。
    output reg                  pfc_gate_enable, // 收到 PFC/PAUSE 时 RoCE 停止派发新 WQE；= ~REG_CTRL[2]
    output reg                  soft_rst,       // 单拍
    output reg   [47:0]         local_mac,      // [7:0] 为线上第 0 字节
    output reg   [31:0]         local_ip,       // [7:0] 为线上第 0 字节
    input  wire                 link_up,
    // 表写口
    output reg                  table_request,        // 单拍
    output reg                  table_write_enable,
    output reg   [3:0]          table_select,
    output reg   [23:0]         table_index,
    output wire  [511:0]        table_write_data,
    input  wire                 table_ack,        // 单拍
    input  wire                 table_error,        // 与 table_ack 同拍
    input  wire  [511:0]        table_read_data,      // 与 table_ack 同拍
    // doorbell（单拍）
    output reg                  doorbell_sq_valid,
    output reg                  doorbell_rq_valid,
    output reg                  doorbell_cq_valid,
    output reg   [31:0]         doorbell_data,
    // 计数器递增（单拍，clk 域）
    input  wire  [CNT_NUM-1:0]  counter_increment,
    // MAC 域计数器（已跨到 clk 域的绝对值），覆盖对应编号
    input  wire  [31:0]         counter_rx_icrc_error,
    input  wire  [31:0]         counter_rx_drop,
    // BAS 观测（roce_bas_mon，已在 clk 域）
    input  wire  [5*32-1:0]     counter_bas,        // 每 32 位一组，序号 0..4 = CNT_BAS_AW_HS..CNT_BAS_R_LAST
    input  wire  [10:0]         debug_bas_sticky,
    input  wire  [7:0]          debug_bas_live,
    output reg                  debug_bas_sticky_clear, // 单拍
    input  wire  [31:0]         debug_rx_state,
    // 软复位状态回读（roce_top 把展宽后的电平送回来）
    input  wire                 soft_rst_active,
    // 扩展调试寄存器（0x0500..0x05CC，地址表见 roce_debug.sv）。
    // 这些偏移落在本 CSR 窗口内，读数据由 roce_debug 组合给出，这里只做二选一。
    input  wire  [31:0]         debug_read_value,
    input  wire                 debug_read_hit,
    output wire                 debug_write_enable,
    output wire  [19:0]         debug_write_offset,
    output wire  [31:0]         debug_write_value,
    // DMA 自测
    output reg   [63:0]         dma_test_source,
    output reg   [63:0]         dma_test_destination,
    output reg   [12:0]         dma_test_length,
    output reg   [31:0]         dma_test_repeat,
    output reg                  dma_test_start,       // 单拍
    input  wire                 dma_test_busy,
    input  wire                 dma_test_done,
    input  wire                 dma_test_error,
    input  wire  [31:0]         dma_test_cycles
);
    wire         register_enable;
    wire         register_write_enable;
    wire [27:0]  register_address;
    wire [31:0]  register_write_value;
    reg  [31:0]  register_read_value;

    // reset 已发生的粘滞标志（读清零）。soft_rst_active 只有 256 个 core 周期
    // （100 MHz 下 2.56 us），而 MMIO 一次往返就是 1 us 量级、rdmacli 的轮询间隔是
    // 2 ms，单看电平必然读不到。粘滞位让"复位确实发生过"这件事在任意时刻都能被读到。
    reg          soft_rst_seen;

    // REG_SOFT_RST 的读地址命中（读寄存器时 +1 拍，用于读清零）
    wire         soft_rst_read  = register_enable & ~register_write_enable &
                                  (register_offset == REG_SOFT_RST);

    avm_register #(
        .CLOCKING_MODE ("common_clock"),
        .ADDR_W        (28),
        .DATA_W        (32)
    ) u_avm_reg (
        .avm_addr  (upstream_address ),
        .avm_read  (upstream_read ),
        .avm_write (upstream_write),
        .avm_wdat  (upstream_write_data ),
        .avm_wait  (upstream_wait ),
        .avm_rdat  (upstream_read_data ),
        .avm_rvld  (upstream_read_valid ),
        .avm_rspo  (upstream_response ),
        .avm_wrsp  (upstream_write_response ),
        .reg_en    (register_enable     ),
        .reg_we    (register_write_enable     ),
        .reg_addr  (register_address   ),
        .reg_din   (register_write_value    ),
        .reg_dout  (register_read_value   ),
        .clk       (clk        ),
        .rst_n     (rst_n      )
    );

    wire [19:0] register_offset  = register_address[19:0];
    wire        register_write = register_enable & register_write_enable;

    reg  [31:0] command_data [0:15];
    reg  [31:0] command_read_data [0:15];
    reg         command_busy;
    reg         command_error;
    reg  [31:0] counter_value [0:CNT_NUM-1];

    genvar index;
    generate
        for (index = 0; index < 16; index = index + 1) begin : gen_command_word
            assign table_write_data[index*32 +: 32] = command_data[index];
        end
    endgenerate

    // 软复位粘滞标志：电平一旦看到就置位，读本寄存器清掉。
    // 读清零放在这里而不是读数据路径里，是因为读数据在 register_enable 当拍才锁存，
    // 用它去清会让"读-清"晚一拍跑掉；soft_rst_read 已经包含读操作的单拍使能。
    always @(posedge clk) begin
        if (!rst_n)
            soft_rst_seen <= 1'b0;
        else if (soft_rst_active)
            soft_rst_seen <= 1'b1;
        else if (soft_rst_read)
            soft_rst_seen <= 1'b0;
    end

    // 写
    always @(posedge clk) begin
        soft_rst  <= 1'b0;
        table_request   <= 1'b0;
        doorbell_sq_valid <= 1'b0;
        doorbell_rq_valid <= 1'b0;
        doorbell_cq_valid <= 1'b0;
        dma_test_start  <= 1'b0;
        debug_bas_sticky_clear <= 1'b0;
        if (!rst_n) begin
            ctrl_enable <= 1'b0;
            pfc_gate_enable <= 1'b1;
            local_mac   <= 48'd0;
            local_ip    <= 32'd0;
            dma_test_length      <= 13'd64;
            dma_test_repeat   <= 32'd1;
        end else if (register_write) begin
            case (register_offset)
                REG_CTRL:      begin ctrl_enable <= register_write_value[0]; soft_rst <= register_write_value[1];
                                    pfc_gate_enable <= !register_write_value[2]; end
                REG_MAC_LO:    local_mac[31:0]  <= register_write_value;
                REG_MAC_HI:    local_mac[47:32] <= register_write_value[15:0];
                REG_IPV4:      local_ip         <= register_write_value;
                REG_CMD:       if (!command_busy) begin
                                   table_request <= 1'b1;
                                   table_write_enable  <= register_write_value[31];
                                   table_select <= register_write_value[27:24];
                                   table_index <= register_write_value[23:0];
                               end
                REG_DT_SRC_LO: dma_test_source[31:0]  <= register_write_value;
                REG_DT_SRC_HI: dma_test_source[63:32] <= register_write_value;
                REG_DT_DST_LO: dma_test_destination[31:0]  <= register_write_value;
                REG_DT_DST_HI: dma_test_destination[63:32] <= register_write_value;
                REG_DT_LEN:    dma_test_length        <= register_write_value[12:0];
                REG_DT_REPEAT: dma_test_repeat     <= register_write_value;
                REG_DT_CTRL:   dma_test_start      <= register_write_value[0];
                REG_DBG_BAS_STICKY: debug_bas_sticky_clear <= 1'b1;   // 任意写清全部 sticky
                /* 软复位：任意写触发，roce_top 把它展宽成 256 个 core 周期，再分别同步到
                 * mac_clk / pcie_clk，复位除本 CSR 之外的全部数据通路。写 CTRL[1] 是等价入口，
                 * 保留给老工具。CSR 自身不复位，所以 MAC/IP/CTRL 保持，无需重新配置。 */
                REG_SOFT_RST:  soft_rst <= 1'b1;
                DB_SQ:         doorbell_sq_valid     <= 1'b1;
                DB_RQ:         doorbell_rq_valid     <= 1'b1;
                DB_CQ:         doorbell_cq_valid     <= 1'b1;
                default: ;
            endcase
            doorbell_data <= register_write_value;
        end
    end

    always @(posedge clk) begin
        if (register_write && register_offset[19:6] == REG_CMD_DATA[19:6])
            command_data[register_offset[5:2]] <= register_write_value;
    end

    // 表命令状态
    // soft_rst 在这里必须显式清 command_busy：roce_tbl 的复位分支（roce_tbl.sv:91）
    // 会在中途中止 MTT 写入序列且不产生 table_ack，若不清，command_busy 永远卡 1，
    // 之后所有 REG_CMD 写都被下面的 `if (!command_busy)` 丢掉，只有重烧才能恢复。
    integer word_index;
    always @(posedge clk) begin
        if (!rst_n || soft_rst) begin
            command_busy  <= 1'b0;
            command_error <= 1'b0;
        end else if (table_request) begin
            command_busy  <= 1'b1;
            command_error <= 1'b0;
        end else if (table_ack) begin
            command_busy  <= 1'b0;
            command_error <= table_error;
        end
        if (table_ack)
            for (word_index = 0; word_index < 16; word_index = word_index + 1)
                command_read_data[word_index] <= table_read_data[word_index*32 +: 32];
    end

    // 计数器
    generate
        for (index = 0; index < CNT_NUM; index = index + 1) begin : gen_counter
            always @(posedge clk) begin
                if (!rst_n)
                    counter_value[index] <= 32'd0;
                else if (counter_increment[index])
                    counter_value[index] <= counter_value[index] + 32'd1;
            end
        end
    endgenerate

    // 调试寄存器写口（roce_debug 自己在 core 域处理，单拍）
    assign debug_write_enable = register_write;
    assign debug_write_offset = register_offset;
    assign debug_write_value  = register_write_value;

    // 读
    always @(posedge clk) begin
        if (register_enable) begin
            if (debug_read_hit)
                register_read_value <= debug_read_value;
            else if (register_offset[19:6] == REG_CMD_DATA[19:6])
                register_read_value <= command_read_data[register_offset[5:2]];
            else if (register_offset[19:8] == REG_CNT[19:8])
                register_read_value <= (register_offset[7:2] == 6'(CNT_RX_ICRC_ERR)) ? counter_rx_icrc_error :
                            (register_offset[7:2] == 6'(CNT_RX_DROP))     ? counter_rx_drop :
                            // 上界必须是 CNT_BAS_R_LAST 而不是 CNT_NUM：counter_bas 只有 5 组
                            // （CNT_BAS_AW_HS..CNT_BAS_R_LAST），CNT_NUM 末尾还有 counter_value
                            // 组的计数。写成 < CNT_NUM 会让新增的末尾编号落进本分支，算成
                            // counter_bas[160 +: 32] 越界（B6389 加 CNT_RESP_CYCLES=23 /
                            // CNT_DISP_BUSY_CYCLES=24 时踩到）。
                            (register_offset[7:2] >= 6'(CNT_BAS_AW_HS) && register_offset[7:2] <= 6'(CNT_BAS_R_LAST))
                                ? counter_bas[(register_offset[7:2] - 6'(CNT_BAS_AW_HS))*32 +: 32] :
                            (register_offset[7:2] < CNT_NUM) ? counter_value[5'(register_offset[7:2])] : 32'd0;
            else case (register_offset)
                REG_ID:         register_read_value <= ID_MAGIC;
                REG_VERSION:    register_read_value <= HW_VERSION;
                REG_CAPS:       register_read_value <= {8'($clog2(MTT_NUM)), 8'($clog2(MR_NUM)),
                                             8'($clog2(CQ_NUM)), 8'($clog2(QP_NUM))};
                REG_CTRL:       register_read_value <= {29'd0, !pfc_gate_enable, 1'b0, ctrl_enable};
                REG_STATUS:     register_read_value <= {31'd0, link_up};
                REG_CORE_CLOCK: register_read_value <= 32'(CORE_CLOCK_MHZ);
                REG_MAC_LO:     register_read_value <= local_mac[31:0];
                REG_MAC_HI:     register_read_value <= {16'd0, local_mac[47:32]};
                REG_IPV4:       register_read_value <= local_ip;
                REG_CMD_STATUS: register_read_value <= {30'd0, command_error, command_busy};
                REG_DT_SRC_LO:  register_read_value <= dma_test_source[31:0];
                REG_DT_SRC_HI:  register_read_value <= dma_test_source[63:32];
                REG_DT_DST_LO:  register_read_value <= dma_test_destination[31:0];
                REG_DT_DST_HI:  register_read_value <= dma_test_destination[63:32];
                REG_DT_LEN:     register_read_value <= {19'd0, dma_test_length};
                REG_DT_REPEAT:  register_read_value <= dma_test_repeat;
                REG_DT_STATUS:  register_read_value <= {29'd0, dma_test_error, dma_test_done, dma_test_busy};
                REG_DT_CYCLES:  register_read_value <= dma_test_cycles;
                REG_DBG_BAS_STICKY: register_read_value <= {21'd0, debug_bas_sticky};
                REG_DBG_BAS_LIVE:   register_read_value <= {24'd0, debug_bas_live};
                REG_DBG_RX_STATE:   register_read_value <= debug_rx_state;
                REG_SOFT_RST:       register_read_value <= {30'd0, soft_rst_seen, soft_rst_active};
                default:        register_read_value <= 32'hdeadbeef;
            endcase
        end
    end
endmodule
`default_nettype wire
