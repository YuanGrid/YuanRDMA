// roce_bas_if.vh
// MCDMA BAS（AXI4 slave，axi_st_app_clk 域）打包总线的位段定义。
// pcie5x16_axis_dma.v 用它把 bas_axi_mm_* 接到两根打包总线上，src/roce 内拆包。
// m2s：RDMA 引擎 -> MCDMA；s2m：MCDMA -> RDMA 引擎。
`ifndef ROCE_BAS_IF_VH
`define ROCE_BAS_IF_VH

`define BAS_M2S_AWVALID  0:0
`define BAS_M2S_AWID     4:1
`define BAS_M2S_AWADDR   68:5
`define BAS_M2S_AWUSER   84:69
`define BAS_M2S_AWLEN    92:85
`define BAS_M2S_AWSIZE   95:93
`define BAS_M2S_AWBURST  97:96
`define BAS_M2S_AWPROT   100:98
`define BAS_M2S_AWLOCK   101:101
`define BAS_M2S_WVALID   102:102
`define BAS_M2S_WLAST    103:103
`define BAS_M2S_WDATA    1127:104
`define BAS_M2S_WSTRB    1255:1128
`define BAS_M2S_BREADY   1256:1256
`define BAS_M2S_ARVALID  1257:1257
`define BAS_M2S_ARID     1261:1258
`define BAS_M2S_ARADDR   1325:1262
`define BAS_M2S_ARUSER   1341:1326
`define BAS_M2S_ARLEN    1349:1342
`define BAS_M2S_ARSIZE   1352:1350
`define BAS_M2S_ARBURST  1354:1353
`define BAS_M2S_ARPROT   1357:1355
`define BAS_M2S_ARLOCK   1358:1358
`define BAS_M2S_RREADY   1359:1359
`define BAS_M2S_W        1360

`define BAS_S2M_AWREADY  0:0
`define BAS_S2M_WREADY   1:1
`define BAS_S2M_BVALID   2:2
`define BAS_S2M_BID      6:3
`define BAS_S2M_BRESP    8:7
`define BAS_S2M_ARREADY  9:9
`define BAS_S2M_RVALID   10:10
`define BAS_S2M_RLAST    11:11
`define BAS_S2M_RID      15:12
`define BAS_S2M_RDATA    1039:16
`define BAS_S2M_RRESP    1041:1040
`define BAS_S2M_W        1042

`endif
