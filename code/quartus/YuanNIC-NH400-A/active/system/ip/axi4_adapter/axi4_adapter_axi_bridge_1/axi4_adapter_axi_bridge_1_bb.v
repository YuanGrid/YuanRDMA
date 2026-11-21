module axi4_adapter_axi_bridge_1 #(
		parameter USE_PIPELINE              = 1,
		parameter USE_M0_AWID               = 0,
		parameter USE_M0_AWREGION           = 0,
		parameter USE_M0_AWLEN              = 0,
		parameter USE_M0_AWSIZE             = 0,
		parameter USE_M0_AWBURST            = 0,
		parameter USE_M0_AWLOCK             = 0,
		parameter USE_M0_AWCACHE            = 0,
		parameter USE_M0_AWQOS              = 0,
		parameter USE_M0_AWUNIQUE           = 0,
		parameter USE_S0_AWSIZE             = 0,
		parameter USE_S0_ARSIZE             = 0,
		parameter USE_S0_AWREGION           = 0,
		parameter USE_S0_AWLOCK             = 0,
		parameter USE_S0_AWCACHE            = 0,
		parameter USE_S0_AWQOS              = 0,
		parameter USE_S0_AWPROT             = 0,
		parameter USE_S0_RID                = 0,
		parameter USE_S0_BID                = 0,
		parameter USE_M0_WSTRB              = 1,
		parameter USE_S0_WLAST              = 0,
		parameter USE_M0_BID                = 0,
		parameter USE_M0_BRESP              = 1,
		parameter USE_S0_BRESP              = 1,
		parameter USE_M0_ARID               = 0,
		parameter USE_M0_ARREGION           = 0,
		parameter USE_M0_ARLEN              = 0,
		parameter USE_M0_ARSIZE             = 0,
		parameter USE_M0_ARBURST            = 0,
		parameter USE_M0_ARLOCK             = 0,
		parameter USE_M0_ARCACHE            = 0,
		parameter USE_M0_ARQOS              = 0,
		parameter USE_S0_ARREGION           = 0,
		parameter USE_S0_ARLOCK             = 0,
		parameter USE_S0_ARCACHE            = 0,
		parameter USE_S0_ARQOS              = 0,
		parameter USE_S0_ARPROT             = 0,
		parameter USE_M0_RID                = 0,
		parameter USE_M0_RRESP              = 1,
		parameter USE_M0_RLAST              = 0,
		parameter USE_S0_RRESP              = 1,
		parameter M0_ID_WIDTH               = 8,
		parameter S0_ID_WIDTH               = 8,
		parameter DATA_WIDTH                = 64,
		parameter WRITE_ADDR_USER_WIDTH     = 64,
		parameter READ_ADDR_USER_WIDTH      = 64,
		parameter WRITE_DATA_USER_WIDTH     = 16,
		parameter WRITE_RESP_USER_WIDTH     = 16,
		parameter READ_DATA_USER_WIDTH      = 16,
		parameter ADDR_WIDTH                = 26,
		parameter USE_S0_AWUSER             = 0,
		parameter USE_S0_ARUSER             = 0,
		parameter USE_S0_WUSER              = 0,
		parameter USE_S0_RUSER              = 0,
		parameter USE_S0_BUSER              = 0,
		parameter USE_M0_AWUSER             = 0,
		parameter USE_M0_ARUSER             = 0,
		parameter USE_M0_ARSNOOP            = 0,
		parameter USE_M0_AWSNOOP            = 0,
		parameter USE_M0_WUSER              = 0,
		parameter USE_M0_RUSER              = 0,
		parameter USE_M0_BUSER              = 0,
		parameter SAI_WIDTH                 = 1,
		parameter USE_M0_ADDRCHK            = 0,
		parameter USE_M0_DATACHK            = 0,
		parameter USE_M0_SAI                = 0,
		parameter USE_M0_POISON             = 0,
		parameter USE_M0_AWAKEUP            = 0,
		parameter USE_M0_TRACE              = 0,
		parameter USE_S0_ADDRCHK            = 0,
		parameter USE_S0_DATACHK            = 0,
		parameter USE_S0_SAI                = 0,
		parameter USE_S0_POISON             = 0,
		parameter USE_S0_AWAKEUP            = 0,
		parameter USE_S0_TRACE              = 0,
		parameter AXI_VERSION               = "AXI4-Lite",
		parameter ACE_LITE_SUPPORT          = 0,
		parameter ACE5_LITE_SUPPORT         = 0,
		parameter SYNC_RESET                = 0,
		parameter BACKPRESSURE_DURING_RESET = 0
	) (
		input  wire        aclk,       //       clk.clk,     Clock input to Axi Bridge IP
		input  wire        aresetn,    // clk_reset.reset_n, Reset input to Axi Bridge IP
		input  wire [25:0] s0_awaddr,  //        s0.awaddr,  Address of first transfer in a write transaction
		input  wire        s0_awvalid, //          .awvalid, Indication that write address channel signals are valid
		output wire        s0_awready, //          .awready, Indication that a write address channel transfer can be accepted
		input  wire [63:0] s0_wdata,   //          .wdata,   Write Data in transaction
		input  wire [7:0]  s0_wstrb,   //          .wstrb,   Signal indicates which byte lanes hold valid data
		input  wire        s0_wvalid,  //          .wvalid,  Indication that write data channel signals are valid
		output wire        s0_wready,  //          .wready,  Indication that a write data channel transfer can be accepted
		output wire [1:0]  s0_bresp,   //          .bresp,   Write Response signal that indicates the status of a write transaction
		output wire        s0_bvalid,  //          .bvalid,  Indication that write response channel signals are valid
		input  wire        s0_bready,  //          .bready,  Indication that a write response channel transfer can be accepted
		input  wire [25:0] s0_araddr,  //          .araddr,  Address of first transfer in a read transaction
		input  wire        s0_arvalid, //          .arvalid, Indication that read address channel signals are valid
		output wire        s0_arready, //          .arready, Indication that a read address channel transfer can be accepted
		output wire [63:0] s0_rdata,   //          .rdata,   Read Data in transaction
		output wire [1:0]  s0_rresp,   //          .rresp,   Read Response signal that indicates the status of a read transaction
		output wire        s0_rvalid,  //          .rvalid,  Indication that read response channel signals are valid
		input  wire        s0_rready,  //          .rready,  Indication that a read response channel transfer can be accepted
		output wire [25:0] m0_awaddr,  //        m0.awaddr,  Address of first transfer in a write transaction
		output wire [2:0]  m0_awprot,  //          .awprot,  Protection attributes of write transaction : privilege,security level and access type
		output wire        m0_awvalid, //          .awvalid, Indication that write address channel signals are valid
		input  wire        m0_awready, //          .awready, Indication that a write address channel transfer can be accepted
		output wire [63:0] m0_wdata,   //          .wdata,   Write Data in transaction
		output wire [7:0]  m0_wstrb,   //          .wstrb,   Signal indicates which byte lanes hold valid data
		output wire        m0_wvalid,  //          .wvalid,  Indication that write data channel signals are valid
		input  wire        m0_wready,  //          .wready,  Indication that a write data channel transfer can be accepted
		input  wire [1:0]  m0_bresp,   //          .bresp,   Write Response signal that indicates the status of a write transaction
		input  wire        m0_bvalid,  //          .bvalid,  Indication that write response channel signals are valid
		output wire        m0_bready,  //          .bready,  Indication that a write response channel transfer can be accepted
		output wire [25:0] m0_araddr,  //          .araddr,  Address of first transfer in a read transaction
		output wire [2:0]  m0_arprot,  //          .arprot,  Protection attributes of read transaction : privilege,security level and access type
		output wire        m0_arvalid, //          .arvalid, Indication that read address channel signals are valid
		input  wire        m0_arready, //          .arready, Indication that a read address channel transfer can be accepted
		input  wire [63:0] m0_rdata,   //          .rdata,   Read Data in transaction
		input  wire [1:0]  m0_rresp,   //          .rresp,   Read Response signal that indicates the status of a read transaction
		input  wire        m0_rvalid,  //          .rvalid,  Indication that read response channel signals are valid
		output wire        m0_rready   //          .rready,  Indication that a read response channel transfer can be accepted
	);
endmodule

