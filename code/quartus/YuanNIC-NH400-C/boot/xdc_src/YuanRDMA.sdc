#system clock 250M and pcie user clock 500M  asynchronous
set_clock_groups -asynchronous -group [get_clocks {U_clk200m|iopll_0_outclk0}] -group [get_clocks {U_pci4_top|U_pcie4x16_mcdma|pcie_rtile_mcdma_0|ast_hip|intel_pcie_rtile_ast_hip_pld_clkout}]
set_clock_groups -asynchronous -group [get_clocks {U_eth400g|U_400g|eth_f_0|tx_clkout|ch23}] -group [get_clocks {U_clk200m|iopll_0_outclk0}]

create_clock -name {eth_ref_clk} -period 6.400 -waveform { 0.000 3.200 } [get_ports {eth_gt_fht_clk}]
create_clock -name {eth_sys_clk} -period 6.400 -waveform { 0.000 3.200 } [get_ports {eth_gt_fgt_clk}]
create_clock -name {pcie_ref_clk0} -period 10.000 -waveform { 0.000 5.000 } [get_ports {PCIE0_GT_0_clk_p}]
create_clock -name {pcie_ref_clk1} -period 10.000 -waveform { 0.000 5.000 } [get_ports {PCIE0_GT_1_clk_p}]
create_clock -name {pl_clk_200m} -period 5.000 -waveform { 0.000 2.500 } [get_ports {pl_clk_p}]

set_max_delay -from [get_clocks {U_clk200m|iopll_0_outclk0}] -to [get_clocks {U_pci4_top|U_pcie4x16_mcdma|pcie_rtile_mcdma_0|ast_hip|intel_pcie_rtile_ast_hip_pld_clkout}] 4
set_max_delay -from [get_clocks {U_pci4_top|U_pcie4x16_mcdma|pcie_rtile_mcdma_0|ast_hip|intel_pcie_rtile_ast_hip_pld_clkout}] -to [get_clocks {U_clk200m|iopll_0_outclk0}] 2

set_max_delay -from [get_clocks {U_clk200m|iopll_0_outclk0}]               -to [get_clocks {U_eth400g|U_400g|eth_f_0|tx_clkout|ch23}] 4
set_max_delay -from [get_clocks {U_eth400g|U_400g|eth_f_0|tx_clkout|ch23}] -to [get_clocks {U_clk200m|iopll_0_outclk0}] 2.409


set_false_path -from [get_clocks {pl_clk_200m}] -to [get_clocks {U_clk200m|iopll_0_outclk0}]
set_false_path -from [get_clocks {U_clk200m|iopll_0_outclk0}] -to [get_clocks {U_eth400g|U_400g|eth_f_0|tx_clkout|ch23}]
set_false_path -from [get_clocks {U_clk200m|iopll_0_outclk0}] -to [get_clocks {U_pci4_top|U_pcie4x16_mcdma|pcie_rtile_mcdma_0|ast_hip|intel_pcie_rtile_ast_hip_pld_clkout}]
set_false_path -from [get_clocks {U_pci4_top|U_pcie4x16_mcdma|pcie_rtile_mcdma_0|ast_hip|intel_pcie_rtile_ast_hip_pld_clkout}] -to [get_clocks {U_eth400g|U_400g|eth_f_0|tx_clkout|ch23}]
set_false_path -from [get_clocks {U_eth400g|U_400g|eth_f_0|tx_clkout|ch23}] -to [get_clocks {U_pci4_top|U_pcie4x16_mcdma|pcie_rtile_mcdma_0|ast_hip|intel_pcie_rtile_ast_hip_pld_clkout}]
set_false_path -from [get_clocks {U_clk200m|iopll_0_refclk}] -to [get_clocks {U_clk200m|iopll_0_outclk0}]
set_false_path -from [get_clocks {U_pci4_top|U_pcie4x16_mcdma|pcie_rtile_mcdma_0|ast_hip|intel_pcie_rtile_ast_hip_pld_clkout}] -to [get_clocks {U_clk200m|iopll_0_outclk0}]




