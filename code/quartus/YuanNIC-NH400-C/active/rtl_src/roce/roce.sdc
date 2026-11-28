# RoCE 引擎 core 时钟（U_clk200m|iopll_0_outclk1，250 MHz）与其他时钟之间
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

# ---------------------------------------------------------------------------------------------------------
# CSR 读链两周期（2026-11-25）
#
# B0118（C 卡 250 MHz）core_clk 违例簇：u_avm_cdc|downstream_address[*] → u_csr|register_read_value[*]，
# 233 条 / 12 个端点 / 7~8 级、最差 −0.168——地址经 roce_top 的窗口判断、roce_debug / roce_pfc / roce_cnp /
# roce_dcqcn 的组合读口、csr_ext 二选一，再进 roce_csr 的读 mux。
#
# 这条路径天然有两个周期：
#   e0  roce_avm_cdc 同拍给出 downstream_address 与单拍 read/write，之后整笔访问保持地址不变
#       （busy 期间不收新请求，地址只在发起新访问的那一拍更新）；
#   e1  avm_register 拉 reg_en（= register_enable）——e0→e1 这一拍 register_enable 必为 0，
#       register_read_value 在 e1 不采样；
#   e2  register_read_value 采样（register_enable 那一拍的组合读数据）。
# 所以「从地址出发」的组合路径按 2 周期检查即可。只放宽从地址出发的这一类：读源若自带寄存器
# （计数器、观测量、配置寄存器），路径起点是那个寄存器，仍按单周期检查；读回语义（数据在 e1→e2 那一拍取）
# 一位不变，不是改 RTL。前提由 roce_csr.sv 里 translate_off 的逐拍检查在仿真中守住。
# ---------------------------------------------------------------------------------------------------------
set roce_csr_addr [get_registers -nowarn {u99_roce_top|u_avm_cdc|downstream_address*}]
set roce_csr_rdv  [get_registers -nowarn {u99_roce_top|u_csr|register_read_value*}]
if {[get_collection_size $roce_csr_addr] > 0 && [get_collection_size $roce_csr_rdv] > 0} {
    set_multicycle_path -setup -end 2 -from $roce_csr_addr -to $roce_csr_rdv
    set_multicycle_path -hold  -end 1 -from $roce_csr_addr -to $roce_csr_rdv
    post_message -type info "roce.sdc: CSR read multicycle 2 applied ([get_collection_size $roce_csr_addr] address regs -> [get_collection_size $roce_csr_rdv] read regs)"
} else {
    post_message -type warning "roce.sdc: CSR read multicycle NOT applied (address regs [get_collection_size $roce_csr_addr], read regs [get_collection_size $roce_csr_rdv])"
}
