module axi4_adapter (
		input  wire [7:0]    axi_bridge_in_awid,                 //              axi_bridge_in.awid
		input  wire [33:0]   axi_bridge_in_awaddr,               //                           .awaddr
		input  wire [7:0]    axi_bridge_in_awlen,                //                           .awlen
		input  wire [2:0]    axi_bridge_in_awsize,               //                           .awsize
		input  wire [1:0]    axi_bridge_in_awburst,              //                           .awburst
		input  wire [0:0]    axi_bridge_in_awlock,               //                           .awlock
		input  wire [2:0]    axi_bridge_in_awprot,               //                           .awprot
		input  wire          axi_bridge_in_awvalid,              //                           .awvalid
		output wire          axi_bridge_in_awready,              //                           .awready
		input  wire [1023:0] axi_bridge_in_wdata,                //                           .wdata
		input  wire [127:0]  axi_bridge_in_wstrb,                //                           .wstrb
		input  wire          axi_bridge_in_wlast,                //                           .wlast
		input  wire          axi_bridge_in_wvalid,               //                           .wvalid
		output wire          axi_bridge_in_wready,               //                           .wready
		output wire [7:0]    axi_bridge_in_bid,                  //                           .bid
		output wire [1:0]    axi_bridge_in_bresp,                //                           .bresp
		output wire          axi_bridge_in_bvalid,               //                           .bvalid
		input  wire          axi_bridge_in_bready,               //                           .bready
		input  wire [7:0]    axi_bridge_in_arid,                 //                           .arid
		input  wire [33:0]   axi_bridge_in_araddr,               //                           .araddr
		input  wire [7:0]    axi_bridge_in_arlen,                //                           .arlen
		input  wire [2:0]    axi_bridge_in_arsize,               //                           .arsize
		input  wire [1:0]    axi_bridge_in_arburst,              //                           .arburst
		input  wire [0:0]    axi_bridge_in_arlock,               //                           .arlock
		input  wire [2:0]    axi_bridge_in_arprot,               //                           .arprot
		input  wire          axi_bridge_in_arvalid,              //                           .arvalid
		output wire          axi_bridge_in_arready,              //                           .arready
		output wire [7:0]    axi_bridge_in_rid,                  //                           .rid
		output wire [1023:0] axi_bridge_in_rdata,                //                           .rdata
		output wire [1:0]    axi_bridge_in_rresp,                //                           .rresp
		output wire          axi_bridge_in_rlast,                //                           .rlast
		output wire          axi_bridge_in_rvalid,               //                           .rvalid
		input  wire          axi_bridge_in_rready,               //                           .rready
		output wire [25:0]   axi_bridge_lite_pf0_m0_awaddr,      //     axi_bridge_lite_pf0_m0.awaddr
		output wire [2:0]    axi_bridge_lite_pf0_m0_awprot,      //                           .awprot
		output wire          axi_bridge_lite_pf0_m0_awvalid,     //                           .awvalid
		input  wire          axi_bridge_lite_pf0_m0_awready,     //                           .awready
		output wire [63:0]   axi_bridge_lite_pf0_m0_wdata,       //                           .wdata
		output wire [7:0]    axi_bridge_lite_pf0_m0_wstrb,       //                           .wstrb
		output wire          axi_bridge_lite_pf0_m0_wvalid,      //                           .wvalid
		input  wire          axi_bridge_lite_pf0_m0_wready,      //                           .wready
		input  wire [1:0]    axi_bridge_lite_pf0_m0_bresp,       //                           .bresp
		input  wire          axi_bridge_lite_pf0_m0_bvalid,      //                           .bvalid
		output wire          axi_bridge_lite_pf0_m0_bready,      //                           .bready
		output wire [25:0]   axi_bridge_lite_pf0_m0_araddr,      //                           .araddr
		output wire [2:0]    axi_bridge_lite_pf0_m0_arprot,      //                           .arprot
		output wire          axi_bridge_lite_pf0_m0_arvalid,     //                           .arvalid
		input  wire          axi_bridge_lite_pf0_m0_arready,     //                           .arready
		input  wire [63:0]   axi_bridge_lite_pf0_m0_rdata,       //                           .rdata
		input  wire [1:0]    axi_bridge_lite_pf0_m0_rresp,       //                           .rresp
		input  wire          axi_bridge_lite_pf0_m0_rvalid,      //                           .rvalid
		output wire          axi_bridge_lite_pf0_m0_rready,      //                           .rready
		output wire [13:0]   axi_bridge_lite_pf1_m0_awaddr,      //     axi_bridge_lite_pf1_m0.awaddr
		output wire [2:0]    axi_bridge_lite_pf1_m0_awprot,      //                           .awprot
		output wire          axi_bridge_lite_pf1_m0_awvalid,     //                           .awvalid
		input  wire          axi_bridge_lite_pf1_m0_awready,     //                           .awready
		output wire [31:0]   axi_bridge_lite_pf1_m0_wdata,       //                           .wdata
		output wire [3:0]    axi_bridge_lite_pf1_m0_wstrb,       //                           .wstrb
		output wire          axi_bridge_lite_pf1_m0_wvalid,      //                           .wvalid
		input  wire          axi_bridge_lite_pf1_m0_wready,      //                           .wready
		input  wire [1:0]    axi_bridge_lite_pf1_m0_bresp,       //                           .bresp
		input  wire          axi_bridge_lite_pf1_m0_bvalid,      //                           .bvalid
		output wire          axi_bridge_lite_pf1_m0_bready,      //                           .bready
		output wire [13:0]   axi_bridge_lite_pf1_m0_araddr,      //                           .araddr
		output wire [2:0]    axi_bridge_lite_pf1_m0_arprot,      //                           .arprot
		output wire          axi_bridge_lite_pf1_m0_arvalid,     //                           .arvalid
		input  wire          axi_bridge_lite_pf1_m0_arready,     //                           .arready
		input  wire [31:0]   axi_bridge_lite_pf1_m0_rdata,       //                           .rdata
		input  wire [1:0]    axi_bridge_lite_pf1_m0_rresp,       //                           .rresp
		input  wire          axi_bridge_lite_pf1_m0_rvalid,      //                           .rvalid
		output wire          axi_bridge_lite_pf1_m0_rready,      //                           .rready
		output wire [11:0]   axi_bridge_lite_pf1_ext_m0_awaddr,  // axi_bridge_lite_pf1_ext_m0.awaddr
		output wire [2:0]    axi_bridge_lite_pf1_ext_m0_awprot,  //                           .awprot
		output wire          axi_bridge_lite_pf1_ext_m0_awvalid, //                           .awvalid
		input  wire          axi_bridge_lite_pf1_ext_m0_awready, //                           .awready
		output wire [31:0]   axi_bridge_lite_pf1_ext_m0_wdata,   //                           .wdata
		output wire [3:0]    axi_bridge_lite_pf1_ext_m0_wstrb,   //                           .wstrb
		output wire          axi_bridge_lite_pf1_ext_m0_wvalid,  //                           .wvalid
		input  wire          axi_bridge_lite_pf1_ext_m0_wready,  //                           .wready
		input  wire [1:0]    axi_bridge_lite_pf1_ext_m0_bresp,   //                           .bresp
		input  wire          axi_bridge_lite_pf1_ext_m0_bvalid,  //                           .bvalid
		output wire          axi_bridge_lite_pf1_ext_m0_bready,  //                           .bready
		output wire [11:0]   axi_bridge_lite_pf1_ext_m0_araddr,  //                           .araddr
		output wire [2:0]    axi_bridge_lite_pf1_ext_m0_arprot,  //                           .arprot
		output wire          axi_bridge_lite_pf1_ext_m0_arvalid, //                           .arvalid
		input  wire          axi_bridge_lite_pf1_ext_m0_arready, //                           .arready
		input  wire [31:0]   axi_bridge_lite_pf1_ext_m0_rdata,   //                           .rdata
		input  wire [1:0]    axi_bridge_lite_pf1_ext_m0_rresp,   //                           .rresp
		input  wire          axi_bridge_lite_pf1_ext_m0_rvalid,  //                           .rvalid
		output wire          axi_bridge_lite_pf1_ext_m0_rready,  //                           .rready
		input  wire          axi_mm_clk_clk,                     //                 axi_mm_clk.clk
		input  wire          axi_lite_clk_clk,                   //               axi_lite_clk.clk
		input  wire          axi_mm_reset_reset,                 //               axi_mm_reset.reset
		input  wire          axi_lite_reset_reset                //             axi_lite_reset.reset
	);
endmodule

