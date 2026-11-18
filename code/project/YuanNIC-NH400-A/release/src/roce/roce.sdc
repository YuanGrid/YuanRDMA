# RoCE 引擎 core 时钟（U_clk200m|iopll_0_outclk1，A 型板 250 MHz，C 卡 / BittWare 125 MHz）与其他时钟之间
# 全部经异步 FIFO / 同步器，按原工程 YuanRDMA.sdc 的做法设为异步时钟组。
set roce_core_clock [get_clocks {U_clk200m|iopll_0_outclk1}]
set_clock_groups -asynchronous -group $roce_core_clock -group [get_clocks {U_clk200m|iopll_0_outclk0}]
set_clock_groups -asynchronous -group $roce_core_clock -group [get_clocks {U_pci5_top|U_pcie5x16|intel_pcie_ss_axi_0|u_rtile|intel_pcie_rtile_ast_qhip_pld_clkout}]
set_clock_groups -asynchronous -group $roce_core_clock -group [get_clocks {U_eth400g|U_400g|eth_f_0|tx_clkout|ch23}]

# ---------------------------------------------------------------------------------------------------------
# B6418：跨时钟 FIFO 指针总线的偏斜 / 线延迟约束
#
# 上面的异步时钟组把这些路径从 setup/hold 分析里整体切掉了，而 axis_async_fifo（verilog-axis）
# 没有嵌入式约束，上游配套的 set_max_skew SDC 也没有加载——格雷码指针各位之间的偏斜完全不受约束。
# 格雷码同步要求同一总线各位到同步器第一级的偏斜小于源时钟周期，否则目的侧可能在同一拍
# 采到两位跳变、得到一个从未出现过的指针值（FIFO 假满 / 假空 / 读到没写的数据）。
# B6417 实测（reference/b6417_timing/cdc_skew.txt）最大偏斜 0.503 ns，这次布局下安全，但没有保证。
#
# 写法与 Intel dcfifo 的嵌入式 SDC 一致：set_max_skew 取 0.8 × 源时钟周期，set_net_delay 取 0.8 × 目的
# 时钟周期。这两类约束不受 clock group / false path 影响，Fitter 会照着布线，STA 用 report_max_skew /
# report_net_delay 检查。偏斜必须**按总线**算，所以逐个 FIFO 实例、逐条指针分别下，不能用一个
# 通配集合把所有 FIFO 的位混在一起（那样算出来的是全芯片的路径差）。
#
# 只约束真正跨时钟的实例（同时钟的 axis_async_fifo 按普通寄存器路径分析，不需要）：
#   各 lane u_dma：u_ar_fifo / u_aw_fifo / u_w_fifo（core → pld_clkout）、u_r_fifo / u_bresp_fifo（pld_clkout → core）
#   u_rx_demux 每 lane u_fifo（mac_clk → core）
#   各 lane u_tx_out|u_cdc（core → mac_clk，FRAME_FIFO：写侧是二进制提交指针 wr_ptr_sync_commit_reg，
#   靠 wr_ptr_update 三级同步握手后采样，数据须在握手完成前稳定，同样按总线约束偏斜与线延迟）
# 名字查不到的组合（例如非 FRAME_FIFO 实例没有提交指针）直接跳过。
# 注意：Quartus 的名字匹配里方括号**不要转义**——`gen_lane\[0\]` 一个都匹配不到（2026-11-08 在 B6417 网表上实测），
# `gen_lane[0]` 才行；Tcl 双引号字符串里写成 \[ \] 只是为了不触发命令替换，传给 get_keepers 的是裸方括号。
# ---------------------------------------------------------------------------------------------------------
set roce_cdc_applied 0
proc roce_cdc_bus {src dst} {
    global roce_cdc_applied
    set from [get_keepers -nowarn $src]
    set to   [get_keepers -nowarn $dst]
    if {[get_collection_size $from] == 0 || [get_collection_size $to] == 0} { return }
    set_max_skew  -from $from -to $to -get_skew_value_from_clock_period src_clock_period -skew_value_multiplier 0.8
    set_net_delay -from $from -to $to -max -get_value_from_clock_period dst_clock_period -value_multiplier 0.8
    incr roce_cdc_applied
}

set roce_cdc_fifos {}
for {set roce_lane 0} {$roce_lane < 4} {incr roce_lane} {
    foreach roce_fifo {u_ar_fifo u_r_fifo u_aw_fifo u_w_fifo u_bresp_fifo} {
        lappend roce_cdc_fifos "u99_roce_top|gen_lane\[$roce_lane\].u_engine|u_dma|$roce_fifo"
    }
    lappend roce_cdc_fifos "u99_roce_top|u_rx_demux|gen_lane\[$roce_lane\].u_fifo"
    lappend roce_cdc_fifos "u99_roce_top|gen_lane\[$roce_lane\].u_engine|u_tx_out|u_cdc"
}
foreach roce_inst $roce_cdc_fifos {
    roce_cdc_bus "$roce_inst|wr_ptr_gray_reg\[*\]"        "$roce_inst|wr_ptr_gray_sync1_reg\[*\]"
    roce_cdc_bus "$roce_inst|rd_ptr_gray_reg\[*\]"        "$roce_inst|rd_ptr_gray_sync1_reg\[*\]"
    roce_cdc_bus "$roce_inst|wr_ptr_sync_commit_reg\[*\]" "$roce_inst|wr_ptr_commit_sync_reg\[*\]"
}
# 预期 4 lane × (u_dma 5 个 FIFO × 2 条格雷码 + demux 2 条 + u_cdc 读格雷码 1 条 + 提交指针 1 条) = 56 条；
# 编译日志里搜 "roce.sdc: CDC" 核对，数量不对说明实例改名了、约束静默落空。
post_message -type info "roce.sdc: CDC skew/net-delay constraints applied to $roce_cdc_applied pointer buses (expect 56)"
