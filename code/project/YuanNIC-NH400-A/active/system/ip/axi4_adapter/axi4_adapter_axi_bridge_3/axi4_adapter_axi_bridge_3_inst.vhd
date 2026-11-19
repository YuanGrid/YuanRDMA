	component axi4_adapter_axi_bridge_3 is
		generic (
			USE_PIPELINE              : integer  := 1;
			USE_M0_AWID               : integer  := 0;
			USE_M0_AWREGION           : integer  := 0;
			USE_M0_AWLEN              : integer  := 0;
			USE_M0_AWSIZE             : integer  := 0;
			USE_M0_AWBURST            : integer  := 0;
			USE_M0_AWLOCK             : integer  := 0;
			USE_M0_AWCACHE            : integer  := 0;
			USE_M0_AWQOS              : integer  := 0;
			USE_M0_AWUNIQUE           : integer  := 0;
			USE_S0_AWSIZE             : integer  := 0;
			USE_S0_ARSIZE             : integer  := 0;
			USE_S0_AWREGION           : integer  := 0;
			USE_S0_AWLOCK             : integer  := 0;
			USE_S0_AWCACHE            : integer  := 0;
			USE_S0_AWQOS              : integer  := 0;
			USE_S0_AWPROT             : integer  := 1;
			USE_S0_RID                : integer  := 0;
			USE_S0_BID                : integer  := 0;
			USE_M0_WSTRB              : integer  := 1;
			USE_S0_WLAST              : integer  := 0;
			USE_M0_BID                : integer  := 0;
			USE_M0_BRESP              : integer  := 1;
			USE_S0_BRESP              : integer  := 1;
			USE_M0_ARID               : integer  := 0;
			USE_M0_ARREGION           : integer  := 0;
			USE_M0_ARLEN              : integer  := 0;
			USE_M0_ARSIZE             : integer  := 0;
			USE_M0_ARBURST            : integer  := 0;
			USE_M0_ARLOCK             : integer  := 0;
			USE_M0_ARCACHE            : integer  := 0;
			USE_M0_ARQOS              : integer  := 0;
			USE_S0_ARREGION           : integer  := 0;
			USE_S0_ARLOCK             : integer  := 0;
			USE_S0_ARCACHE            : integer  := 0;
			USE_S0_ARQOS              : integer  := 0;
			USE_S0_ARPROT             : integer  := 1;
			USE_M0_RID                : integer  := 0;
			USE_M0_RRESP              : integer  := 1;
			USE_M0_RLAST              : integer  := 0;
			USE_S0_RRESP              : integer  := 1;
			M0_ID_WIDTH               : positive := 8;
			S0_ID_WIDTH               : positive := 8;
			DATA_WIDTH                : positive := 32;
			WRITE_ADDR_USER_WIDTH     : positive := 64;
			READ_ADDR_USER_WIDTH      : positive := 64;
			WRITE_DATA_USER_WIDTH     : positive := 16;
			WRITE_RESP_USER_WIDTH     : positive := 16;
			READ_DATA_USER_WIDTH      : positive := 16;
			ADDR_WIDTH                : positive := 12;
			USE_S0_AWUSER             : integer  := 0;
			USE_S0_ARUSER             : integer  := 0;
			USE_S0_WUSER              : integer  := 0;
			USE_S0_RUSER              : integer  := 0;
			USE_S0_BUSER              : integer  := 0;
			USE_M0_AWUSER             : integer  := 0;
			USE_M0_ARUSER             : integer  := 0;
			USE_M0_ARSNOOP            : integer  := 0;
			USE_M0_AWSNOOP            : integer  := 0;
			USE_M0_WUSER              : integer  := 0;
			USE_M0_RUSER              : integer  := 0;
			USE_M0_BUSER              : integer  := 0;
			SAI_WIDTH                 : positive := 1;
			USE_M0_ADDRCHK            : integer  := 0;
			USE_M0_DATACHK            : integer  := 0;
			USE_M0_SAI                : integer  := 0;
			USE_M0_POISON             : integer  := 0;
			USE_M0_AWAKEUP            : integer  := 0;
			USE_M0_TRACE              : integer  := 0;
			USE_S0_ADDRCHK            : integer  := 0;
			USE_S0_DATACHK            : integer  := 0;
			USE_S0_SAI                : integer  := 0;
			USE_S0_POISON             : integer  := 0;
			USE_S0_AWAKEUP            : integer  := 0;
			USE_S0_TRACE              : integer  := 0;
			AXI_VERSION               : string   := "AXI4-Lite";
			ACE_LITE_SUPPORT          : integer  := 0;
			ACE5_LITE_SUPPORT         : integer  := 0;
			SYNC_RESET                : integer  := 0;
			BACKPRESSURE_DURING_RESET : integer  := 0
		);
		port (
			aclk       : in  std_logic                     := 'X';             -- clk
			aresetn    : in  std_logic                     := 'X';             -- reset_n
			s0_awaddr  : in  std_logic_vector(11 downto 0) := (others => 'X'); -- awaddr
			s0_awprot  : in  std_logic_vector(2 downto 0)  := (others => 'X'); -- awprot
			s0_awvalid : in  std_logic                     := 'X';             -- awvalid
			s0_awready : out std_logic;                                        -- awready
			s0_wdata   : in  std_logic_vector(31 downto 0) := (others => 'X'); -- wdata
			s0_wstrb   : in  std_logic_vector(3 downto 0)  := (others => 'X'); -- wstrb
			s0_wvalid  : in  std_logic                     := 'X';             -- wvalid
			s0_wready  : out std_logic;                                        -- wready
			s0_bresp   : out std_logic_vector(1 downto 0);                     -- bresp
			s0_bvalid  : out std_logic;                                        -- bvalid
			s0_bready  : in  std_logic                     := 'X';             -- bready
			s0_araddr  : in  std_logic_vector(11 downto 0) := (others => 'X'); -- araddr
			s0_arprot  : in  std_logic_vector(2 downto 0)  := (others => 'X'); -- arprot
			s0_arvalid : in  std_logic                     := 'X';             -- arvalid
			s0_arready : out std_logic;                                        -- arready
			s0_rdata   : out std_logic_vector(31 downto 0);                    -- rdata
			s0_rresp   : out std_logic_vector(1 downto 0);                     -- rresp
			s0_rvalid  : out std_logic;                                        -- rvalid
			s0_rready  : in  std_logic                     := 'X';             -- rready
			m0_awaddr  : out std_logic_vector(11 downto 0);                    -- awaddr
			m0_awprot  : out std_logic_vector(2 downto 0);                     -- awprot
			m0_awvalid : out std_logic;                                        -- awvalid
			m0_awready : in  std_logic                     := 'X';             -- awready
			m0_wdata   : out std_logic_vector(31 downto 0);                    -- wdata
			m0_wstrb   : out std_logic_vector(3 downto 0);                     -- wstrb
			m0_wvalid  : out std_logic;                                        -- wvalid
			m0_wready  : in  std_logic                     := 'X';             -- wready
			m0_bresp   : in  std_logic_vector(1 downto 0)  := (others => 'X'); -- bresp
			m0_bvalid  : in  std_logic                     := 'X';             -- bvalid
			m0_bready  : out std_logic;                                        -- bready
			m0_araddr  : out std_logic_vector(11 downto 0);                    -- araddr
			m0_arprot  : out std_logic_vector(2 downto 0);                     -- arprot
			m0_arvalid : out std_logic;                                        -- arvalid
			m0_arready : in  std_logic                     := 'X';             -- arready
			m0_rdata   : in  std_logic_vector(31 downto 0) := (others => 'X'); -- rdata
			m0_rresp   : in  std_logic_vector(1 downto 0)  := (others => 'X'); -- rresp
			m0_rvalid  : in  std_logic                     := 'X';             -- rvalid
			m0_rready  : out std_logic                                         -- rready
		);
	end component axi4_adapter_axi_bridge_3;

	u0 : component axi4_adapter_axi_bridge_3
		generic map (
			USE_PIPELINE              => INTEGER_VALUE_FOR_USE_PIPELINE,
			USE_M0_AWID               => INTEGER_VALUE_FOR_USE_M0_AWID,
			USE_M0_AWREGION           => INTEGER_VALUE_FOR_USE_M0_AWREGION,
			USE_M0_AWLEN              => INTEGER_VALUE_FOR_USE_M0_AWLEN,
			USE_M0_AWSIZE             => INTEGER_VALUE_FOR_USE_M0_AWSIZE,
			USE_M0_AWBURST            => INTEGER_VALUE_FOR_USE_M0_AWBURST,
			USE_M0_AWLOCK             => INTEGER_VALUE_FOR_USE_M0_AWLOCK,
			USE_M0_AWCACHE            => INTEGER_VALUE_FOR_USE_M0_AWCACHE,
			USE_M0_AWQOS              => INTEGER_VALUE_FOR_USE_M0_AWQOS,
			USE_M0_AWUNIQUE           => INTEGER_VALUE_FOR_USE_M0_AWUNIQUE,
			USE_S0_AWSIZE             => INTEGER_VALUE_FOR_USE_S0_AWSIZE,
			USE_S0_ARSIZE             => INTEGER_VALUE_FOR_USE_S0_ARSIZE,
			USE_S0_AWREGION           => INTEGER_VALUE_FOR_USE_S0_AWREGION,
			USE_S0_AWLOCK             => INTEGER_VALUE_FOR_USE_S0_AWLOCK,
			USE_S0_AWCACHE            => INTEGER_VALUE_FOR_USE_S0_AWCACHE,
			USE_S0_AWQOS              => INTEGER_VALUE_FOR_USE_S0_AWQOS,
			USE_S0_AWPROT             => INTEGER_VALUE_FOR_USE_S0_AWPROT,
			USE_S0_RID                => INTEGER_VALUE_FOR_USE_S0_RID,
			USE_S0_BID                => INTEGER_VALUE_FOR_USE_S0_BID,
			USE_M0_WSTRB              => INTEGER_VALUE_FOR_USE_M0_WSTRB,
			USE_S0_WLAST              => INTEGER_VALUE_FOR_USE_S0_WLAST,
			USE_M0_BID                => INTEGER_VALUE_FOR_USE_M0_BID,
			USE_M0_BRESP              => INTEGER_VALUE_FOR_USE_M0_BRESP,
			USE_S0_BRESP              => INTEGER_VALUE_FOR_USE_S0_BRESP,
			USE_M0_ARID               => INTEGER_VALUE_FOR_USE_M0_ARID,
			USE_M0_ARREGION           => INTEGER_VALUE_FOR_USE_M0_ARREGION,
			USE_M0_ARLEN              => INTEGER_VALUE_FOR_USE_M0_ARLEN,
			USE_M0_ARSIZE             => INTEGER_VALUE_FOR_USE_M0_ARSIZE,
			USE_M0_ARBURST            => INTEGER_VALUE_FOR_USE_M0_ARBURST,
			USE_M0_ARLOCK             => INTEGER_VALUE_FOR_USE_M0_ARLOCK,
			USE_M0_ARCACHE            => INTEGER_VALUE_FOR_USE_M0_ARCACHE,
			USE_M0_ARQOS              => INTEGER_VALUE_FOR_USE_M0_ARQOS,
			USE_S0_ARREGION           => INTEGER_VALUE_FOR_USE_S0_ARREGION,
			USE_S0_ARLOCK             => INTEGER_VALUE_FOR_USE_S0_ARLOCK,
			USE_S0_ARCACHE            => INTEGER_VALUE_FOR_USE_S0_ARCACHE,
			USE_S0_ARQOS              => INTEGER_VALUE_FOR_USE_S0_ARQOS,
			USE_S0_ARPROT             => INTEGER_VALUE_FOR_USE_S0_ARPROT,
			USE_M0_RID                => INTEGER_VALUE_FOR_USE_M0_RID,
			USE_M0_RRESP              => INTEGER_VALUE_FOR_USE_M0_RRESP,
			USE_M0_RLAST              => INTEGER_VALUE_FOR_USE_M0_RLAST,
			USE_S0_RRESP              => INTEGER_VALUE_FOR_USE_S0_RRESP,
			M0_ID_WIDTH               => POSITIVE_VALUE_FOR_M0_ID_WIDTH,
			S0_ID_WIDTH               => POSITIVE_VALUE_FOR_S0_ID_WIDTH,
			DATA_WIDTH                => POSITIVE_VALUE_FOR_DATA_WIDTH,
			WRITE_ADDR_USER_WIDTH     => POSITIVE_VALUE_FOR_WRITE_ADDR_USER_WIDTH,
			READ_ADDR_USER_WIDTH      => POSITIVE_VALUE_FOR_READ_ADDR_USER_WIDTH,
			WRITE_DATA_USER_WIDTH     => POSITIVE_VALUE_FOR_WRITE_DATA_USER_WIDTH,
			WRITE_RESP_USER_WIDTH     => POSITIVE_VALUE_FOR_WRITE_RESP_USER_WIDTH,
			READ_DATA_USER_WIDTH      => POSITIVE_VALUE_FOR_READ_DATA_USER_WIDTH,
			ADDR_WIDTH                => POSITIVE_VALUE_FOR_ADDR_WIDTH,
			USE_S0_AWUSER             => INTEGER_VALUE_FOR_USE_S0_AWUSER,
			USE_S0_ARUSER             => INTEGER_VALUE_FOR_USE_S0_ARUSER,
			USE_S0_WUSER              => INTEGER_VALUE_FOR_USE_S0_WUSER,
			USE_S0_RUSER              => INTEGER_VALUE_FOR_USE_S0_RUSER,
			USE_S0_BUSER              => INTEGER_VALUE_FOR_USE_S0_BUSER,
			USE_M0_AWUSER             => INTEGER_VALUE_FOR_USE_M0_AWUSER,
			USE_M0_ARUSER             => INTEGER_VALUE_FOR_USE_M0_ARUSER,
			USE_M0_ARSNOOP            => INTEGER_VALUE_FOR_USE_M0_ARSNOOP,
			USE_M0_AWSNOOP            => INTEGER_VALUE_FOR_USE_M0_AWSNOOP,
			USE_M0_WUSER              => INTEGER_VALUE_FOR_USE_M0_WUSER,
			USE_M0_RUSER              => INTEGER_VALUE_FOR_USE_M0_RUSER,
			USE_M0_BUSER              => INTEGER_VALUE_FOR_USE_M0_BUSER,
			SAI_WIDTH                 => POSITIVE_VALUE_FOR_SAI_WIDTH,
			USE_M0_ADDRCHK            => INTEGER_VALUE_FOR_USE_M0_ADDRCHK,
			USE_M0_DATACHK            => INTEGER_VALUE_FOR_USE_M0_DATACHK,
			USE_M0_SAI                => INTEGER_VALUE_FOR_USE_M0_SAI,
			USE_M0_POISON             => INTEGER_VALUE_FOR_USE_M0_POISON,
			USE_M0_AWAKEUP            => INTEGER_VALUE_FOR_USE_M0_AWAKEUP,
			USE_M0_TRACE              => INTEGER_VALUE_FOR_USE_M0_TRACE,
			USE_S0_ADDRCHK            => INTEGER_VALUE_FOR_USE_S0_ADDRCHK,
			USE_S0_DATACHK            => INTEGER_VALUE_FOR_USE_S0_DATACHK,
			USE_S0_SAI                => INTEGER_VALUE_FOR_USE_S0_SAI,
			USE_S0_POISON             => INTEGER_VALUE_FOR_USE_S0_POISON,
			USE_S0_AWAKEUP            => INTEGER_VALUE_FOR_USE_S0_AWAKEUP,
			USE_S0_TRACE              => INTEGER_VALUE_FOR_USE_S0_TRACE,
			AXI_VERSION               => STRING_VALUE_FOR_AXI_VERSION,
			ACE_LITE_SUPPORT          => INTEGER_VALUE_FOR_ACE_LITE_SUPPORT,
			ACE5_LITE_SUPPORT         => INTEGER_VALUE_FOR_ACE5_LITE_SUPPORT,
			SYNC_RESET                => INTEGER_VALUE_FOR_SYNC_RESET,
			BACKPRESSURE_DURING_RESET => INTEGER_VALUE_FOR_BACKPRESSURE_DURING_RESET
		)
		port map (
			aclk       => CONNECTED_TO_aclk,       --       clk.clk
			aresetn    => CONNECTED_TO_aresetn,    -- clk_reset.reset_n
			s0_awaddr  => CONNECTED_TO_s0_awaddr,  --        s0.awaddr
			s0_awprot  => CONNECTED_TO_s0_awprot,  --          .awprot
			s0_awvalid => CONNECTED_TO_s0_awvalid, --          .awvalid
			s0_awready => CONNECTED_TO_s0_awready, --          .awready
			s0_wdata   => CONNECTED_TO_s0_wdata,   --          .wdata
			s0_wstrb   => CONNECTED_TO_s0_wstrb,   --          .wstrb
			s0_wvalid  => CONNECTED_TO_s0_wvalid,  --          .wvalid
			s0_wready  => CONNECTED_TO_s0_wready,  --          .wready
			s0_bresp   => CONNECTED_TO_s0_bresp,   --          .bresp
			s0_bvalid  => CONNECTED_TO_s0_bvalid,  --          .bvalid
			s0_bready  => CONNECTED_TO_s0_bready,  --          .bready
			s0_araddr  => CONNECTED_TO_s0_araddr,  --          .araddr
			s0_arprot  => CONNECTED_TO_s0_arprot,  --          .arprot
			s0_arvalid => CONNECTED_TO_s0_arvalid, --          .arvalid
			s0_arready => CONNECTED_TO_s0_arready, --          .arready
			s0_rdata   => CONNECTED_TO_s0_rdata,   --          .rdata
			s0_rresp   => CONNECTED_TO_s0_rresp,   --          .rresp
			s0_rvalid  => CONNECTED_TO_s0_rvalid,  --          .rvalid
			s0_rready  => CONNECTED_TO_s0_rready,  --          .rready
			m0_awaddr  => CONNECTED_TO_m0_awaddr,  --        m0.awaddr
			m0_awprot  => CONNECTED_TO_m0_awprot,  --          .awprot
			m0_awvalid => CONNECTED_TO_m0_awvalid, --          .awvalid
			m0_awready => CONNECTED_TO_m0_awready, --          .awready
			m0_wdata   => CONNECTED_TO_m0_wdata,   --          .wdata
			m0_wstrb   => CONNECTED_TO_m0_wstrb,   --          .wstrb
			m0_wvalid  => CONNECTED_TO_m0_wvalid,  --          .wvalid
			m0_wready  => CONNECTED_TO_m0_wready,  --          .wready
			m0_bresp   => CONNECTED_TO_m0_bresp,   --          .bresp
			m0_bvalid  => CONNECTED_TO_m0_bvalid,  --          .bvalid
			m0_bready  => CONNECTED_TO_m0_bready,  --          .bready
			m0_araddr  => CONNECTED_TO_m0_araddr,  --          .araddr
			m0_arprot  => CONNECTED_TO_m0_arprot,  --          .arprot
			m0_arvalid => CONNECTED_TO_m0_arvalid, --          .arvalid
			m0_arready => CONNECTED_TO_m0_arready, --          .arready
			m0_rdata   => CONNECTED_TO_m0_rdata,   --          .rdata
			m0_rresp   => CONNECTED_TO_m0_rresp,   --          .rresp
			m0_rvalid  => CONNECTED_TO_m0_rvalid,  --          .rvalid
			m0_rready  => CONNECTED_TO_m0_rready   --          .rready
		);

