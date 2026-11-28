
#system clock 250M and pcie user clock 500M  asynchronous
set_clock_groups -asynchronous -group [get_clocks {U_clk200m|iopll_0_outclk0}] -group [get_clocks {U_pci5_top|U_pcie5x16|intel_pcie_ss_axi_0|u_rtile|intel_pcie_rtile_ast_qhip_pld_clkout_slow}]
set_clock_groups -asynchronous -group [get_clocks {U_clk200m|iopll_0_outclk0}] -group [get_clocks {U_pci5_top|U_pcie5x16|intel_pcie_ss_axi_0|u_rtile|intel_pcie_rtile_ast_qhip_pld_clkout}]
set_clock_groups -asynchronous -group [get_clocks {U_eth400g|U_400g|eth_f_0|tx_clkout|ch23}] -group [get_clocks {U_clk200m|iopll_0_outclk0}]
set_clock_groups -asynchronous -group [get_clocks {U_eth400g|U_400g|eth_f_0|tx_clkout|ch23}] -group [get_clocks {U_pci5_top|U_pcie5x16|intel_pcie_ss_axi_0|u_rtile|intel_pcie_rtile_ast_qhip_pld_clkout}]


create_clock -name {eth_ref_clk} -period 6.400 -waveform { 0.000 3.200 } [get_ports {eth_gt_fht_clk}]
create_clock -name {eth_sys_clk} -period 6.400 -waveform { 0.000 3.200 } [get_ports {eth_gt_fgt_clk}]
create_clock -name {pcie_ref_clk0} -period 10.000 -waveform { 0.000 5.000 } [get_ports {PCIE0_GT_0_clk_p}]
create_clock -name {pcie_ref_clk1} -period 10.000 -waveform { 0.000 5.000 } [get_ports {PCIE0_GT_1_clk_p}]
# C 板 pl_clk_p 是 100 MHz（fpga_ip/clk200m.ip 参考时钟 100.0）；C 板没有 DDR4，不带 EMIF 约束。
# 注意：clk200m 的 IOPLL SDC 先于本文件读入，已按 IP 参考时钟在 pl_clk_p 上建了 U_clk200m|iopll_0_refclk，
# PLL 各输出都由它推导；下面这条 create_clock 会被忽略（Warning 332049/332174），写成与硬件一致的值只为可读。
create_clock -name {pl_clk_100m} -period 10.000 -waveform { 0.000 5.000 } [get_ports {pl_clk_p}]

set_max_delay -from [get_clocks {U_clk200m|iopll_0_outclk0}] -to [get_clocks {U_pci5_top|U_pcie5x16|intel_pcie_ss_axi_0|u_rtile|intel_pcie_rtile_ast_qhip_pld_clkout}] 4
set_max_delay -from [get_clocks {U_pci5_top|U_pcie5x16|intel_pcie_ss_axi_0|u_rtile|intel_pcie_rtile_ast_qhip_pld_clkout}] -to [get_clocks {U_clk200m|iopll_0_outclk0}] 2

set_max_delay -from [get_clocks {U_clk200m|iopll_0_outclk0}]               -to [get_clocks {U_eth400g|U_400g|eth_f_0|tx_clkout|ch23}] 4 
set_max_delay -from [get_clocks {U_eth400g|U_400g|eth_f_0|tx_clkout|ch23}] -to [get_clocks {U_clk200m|iopll_0_outclk0}] 2.409


set_false_path -from [get_clocks {pl_clk_100m}] -to [get_clocks {U_clk200m|iopll_0_outclk0}]
#set_false_path -from [get_clocks {U_clk200m|iopll_0_outclk0}] -to [get_clocks {U_eth400g|U_400g|eth_f_0|tx_clkout|ch23}]
#set_false_path -from [get_clocks {U_clk200m|iopll_0_outclk0}] -to [get_clocks {U_pci5_top|U_pcie5x16|intel_pcie_ss_axi_0|u_rtile|intel_pcie_rtile_ast_qhip_pld_clkout}]
#set_false_path -from [get_clocks {U_pci5_top|U_pcie5x16|intel_pcie_ss_axi_0|u_rtile|intel_pcie_rtile_ast_qhip_pld_clkout}] -to [get_clocks {U_eth400g|U_400g|eth_f_0|tx_clkout|ch23}]
#set_false_path -from [get_clocks {U_eth400g|U_400g|eth_f_0|tx_clkout|ch23}] -to [get_clocks {U_pci5_top|U_pcie5x16|intel_pcie_ss_axi_0|u_rtile|intel_pcie_rtile_ast_qhip_pld_clkout}]
set_false_path -from [get_clocks {U_clk200m|iopll_0_refclk}] -to [get_clocks {U_clk200m|iopll_0_outclk0}]
set_false_path -from [get_clocks {U_pci5_top|U_pcie5x16|intel_pcie_ss_axi_0|u_rtile|intel_pcie_rtile_ast_qhip_pld_clkout}] -to [get_clocks {U_clk200m|iopll_0_outclk0}]

