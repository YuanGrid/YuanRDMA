	component axi4_adapter is
		port (
			axi_bridge_in_awid                 : in  std_logic_vector(7 downto 0)    := (others => 'X'); -- awid
			axi_bridge_in_awaddr               : in  std_logic_vector(33 downto 0)   := (others => 'X'); -- awaddr
			axi_bridge_in_awlen                : in  std_logic_vector(7 downto 0)    := (others => 'X'); -- awlen
			axi_bridge_in_awsize               : in  std_logic_vector(2 downto 0)    := (others => 'X'); -- awsize
			axi_bridge_in_awburst              : in  std_logic_vector(1 downto 0)    := (others => 'X'); -- awburst
			axi_bridge_in_awlock               : in  std_logic_vector(0 downto 0)    := (others => 'X'); -- awlock
			axi_bridge_in_awprot               : in  std_logic_vector(2 downto 0)    := (others => 'X'); -- awprot
			axi_bridge_in_awvalid              : in  std_logic                       := 'X';             -- awvalid
			axi_bridge_in_awready              : out std_logic;                                          -- awready
			axi_bridge_in_wdata                : in  std_logic_vector(1023 downto 0) := (others => 'X'); -- wdata
			axi_bridge_in_wstrb                : in  std_logic_vector(127 downto 0)  := (others => 'X'); -- wstrb
			axi_bridge_in_wlast                : in  std_logic                       := 'X';             -- wlast
			axi_bridge_in_wvalid               : in  std_logic                       := 'X';             -- wvalid
			axi_bridge_in_wready               : out std_logic;                                          -- wready
			axi_bridge_in_bid                  : out std_logic_vector(7 downto 0);                       -- bid
			axi_bridge_in_bresp                : out std_logic_vector(1 downto 0);                       -- bresp
			axi_bridge_in_bvalid               : out std_logic;                                          -- bvalid
			axi_bridge_in_bready               : in  std_logic                       := 'X';             -- bready
			axi_bridge_in_arid                 : in  std_logic_vector(7 downto 0)    := (others => 'X'); -- arid
			axi_bridge_in_araddr               : in  std_logic_vector(33 downto 0)   := (others => 'X'); -- araddr
			axi_bridge_in_arlen                : in  std_logic_vector(7 downto 0)    := (others => 'X'); -- arlen
			axi_bridge_in_arsize               : in  std_logic_vector(2 downto 0)    := (others => 'X'); -- arsize
			axi_bridge_in_arburst              : in  std_logic_vector(1 downto 0)    := (others => 'X'); -- arburst
			axi_bridge_in_arlock               : in  std_logic_vector(0 downto 0)    := (others => 'X'); -- arlock
			axi_bridge_in_arprot               : in  std_logic_vector(2 downto 0)    := (others => 'X'); -- arprot
			axi_bridge_in_arvalid              : in  std_logic                       := 'X';             -- arvalid
			axi_bridge_in_arready              : out std_logic;                                          -- arready
			axi_bridge_in_rid                  : out std_logic_vector(7 downto 0);                       -- rid
			axi_bridge_in_rdata                : out std_logic_vector(1023 downto 0);                    -- rdata
			axi_bridge_in_rresp                : out std_logic_vector(1 downto 0);                       -- rresp
			axi_bridge_in_rlast                : out std_logic;                                          -- rlast
			axi_bridge_in_rvalid               : out std_logic;                                          -- rvalid
			axi_bridge_in_rready               : in  std_logic                       := 'X';             -- rready
			axi_bridge_lite_pf0_m0_awaddr      : out std_logic_vector(25 downto 0);                      -- awaddr
			axi_bridge_lite_pf0_m0_awprot      : out std_logic_vector(2 downto 0);                       -- awprot
			axi_bridge_lite_pf0_m0_awvalid     : out std_logic;                                          -- awvalid
			axi_bridge_lite_pf0_m0_awready     : in  std_logic                       := 'X';             -- awready
			axi_bridge_lite_pf0_m0_wdata       : out std_logic_vector(63 downto 0);                      -- wdata
			axi_bridge_lite_pf0_m0_wstrb       : out std_logic_vector(7 downto 0);                       -- wstrb
			axi_bridge_lite_pf0_m0_wvalid      : out std_logic;                                          -- wvalid
			axi_bridge_lite_pf0_m0_wready      : in  std_logic                       := 'X';             -- wready
			axi_bridge_lite_pf0_m0_bresp       : in  std_logic_vector(1 downto 0)    := (others => 'X'); -- bresp
			axi_bridge_lite_pf0_m0_bvalid      : in  std_logic                       := 'X';             -- bvalid
			axi_bridge_lite_pf0_m0_bready      : out std_logic;                                          -- bready
			axi_bridge_lite_pf0_m0_araddr      : out std_logic_vector(25 downto 0);                      -- araddr
			axi_bridge_lite_pf0_m0_arprot      : out std_logic_vector(2 downto 0);                       -- arprot
			axi_bridge_lite_pf0_m0_arvalid     : out std_logic;                                          -- arvalid
			axi_bridge_lite_pf0_m0_arready     : in  std_logic                       := 'X';             -- arready
			axi_bridge_lite_pf0_m0_rdata       : in  std_logic_vector(63 downto 0)   := (others => 'X'); -- rdata
			axi_bridge_lite_pf0_m0_rresp       : in  std_logic_vector(1 downto 0)    := (others => 'X'); -- rresp
			axi_bridge_lite_pf0_m0_rvalid      : in  std_logic                       := 'X';             -- rvalid
			axi_bridge_lite_pf0_m0_rready      : out std_logic;                                          -- rready
			axi_bridge_lite_pf1_m0_awaddr      : out std_logic_vector(13 downto 0);                      -- awaddr
			axi_bridge_lite_pf1_m0_awprot      : out std_logic_vector(2 downto 0);                       -- awprot
			axi_bridge_lite_pf1_m0_awvalid     : out std_logic;                                          -- awvalid
			axi_bridge_lite_pf1_m0_awready     : in  std_logic                       := 'X';             -- awready
			axi_bridge_lite_pf1_m0_wdata       : out std_logic_vector(31 downto 0);                      -- wdata
			axi_bridge_lite_pf1_m0_wstrb       : out std_logic_vector(3 downto 0);                       -- wstrb
			axi_bridge_lite_pf1_m0_wvalid      : out std_logic;                                          -- wvalid
			axi_bridge_lite_pf1_m0_wready      : in  std_logic                       := 'X';             -- wready
			axi_bridge_lite_pf1_m0_bresp       : in  std_logic_vector(1 downto 0)    := (others => 'X'); -- bresp
			axi_bridge_lite_pf1_m0_bvalid      : in  std_logic                       := 'X';             -- bvalid
			axi_bridge_lite_pf1_m0_bready      : out std_logic;                                          -- bready
			axi_bridge_lite_pf1_m0_araddr      : out std_logic_vector(13 downto 0);                      -- araddr
			axi_bridge_lite_pf1_m0_arprot      : out std_logic_vector(2 downto 0);                       -- arprot
			axi_bridge_lite_pf1_m0_arvalid     : out std_logic;                                          -- arvalid
			axi_bridge_lite_pf1_m0_arready     : in  std_logic                       := 'X';             -- arready
			axi_bridge_lite_pf1_m0_rdata       : in  std_logic_vector(31 downto 0)   := (others => 'X'); -- rdata
			axi_bridge_lite_pf1_m0_rresp       : in  std_logic_vector(1 downto 0)    := (others => 'X'); -- rresp
			axi_bridge_lite_pf1_m0_rvalid      : in  std_logic                       := 'X';             -- rvalid
			axi_bridge_lite_pf1_m0_rready      : out std_logic;                                          -- rready
			axi_bridge_lite_pf1_ext_m0_awaddr  : out std_logic_vector(11 downto 0);                      -- awaddr
			axi_bridge_lite_pf1_ext_m0_awprot  : out std_logic_vector(2 downto 0);                       -- awprot
			axi_bridge_lite_pf1_ext_m0_awvalid : out std_logic;                                          -- awvalid
			axi_bridge_lite_pf1_ext_m0_awready : in  std_logic                       := 'X';             -- awready
			axi_bridge_lite_pf1_ext_m0_wdata   : out std_logic_vector(31 downto 0);                      -- wdata
			axi_bridge_lite_pf1_ext_m0_wstrb   : out std_logic_vector(3 downto 0);                       -- wstrb
			axi_bridge_lite_pf1_ext_m0_wvalid  : out std_logic;                                          -- wvalid
			axi_bridge_lite_pf1_ext_m0_wready  : in  std_logic                       := 'X';             -- wready
			axi_bridge_lite_pf1_ext_m0_bresp   : in  std_logic_vector(1 downto 0)    := (others => 'X'); -- bresp
			axi_bridge_lite_pf1_ext_m0_bvalid  : in  std_logic                       := 'X';             -- bvalid
			axi_bridge_lite_pf1_ext_m0_bready  : out std_logic;                                          -- bready
			axi_bridge_lite_pf1_ext_m0_araddr  : out std_logic_vector(11 downto 0);                      -- araddr
			axi_bridge_lite_pf1_ext_m0_arprot  : out std_logic_vector(2 downto 0);                       -- arprot
			axi_bridge_lite_pf1_ext_m0_arvalid : out std_logic;                                          -- arvalid
			axi_bridge_lite_pf1_ext_m0_arready : in  std_logic                       := 'X';             -- arready
			axi_bridge_lite_pf1_ext_m0_rdata   : in  std_logic_vector(31 downto 0)   := (others => 'X'); -- rdata
			axi_bridge_lite_pf1_ext_m0_rresp   : in  std_logic_vector(1 downto 0)    := (others => 'X'); -- rresp
			axi_bridge_lite_pf1_ext_m0_rvalid  : in  std_logic                       := 'X';             -- rvalid
			axi_bridge_lite_pf1_ext_m0_rready  : out std_logic;                                          -- rready
			axi_mm_clk_clk                     : in  std_logic                       := 'X';             -- clk
			axi_lite_clk_clk                   : in  std_logic                       := 'X';             -- clk
			axi_mm_reset_reset                 : in  std_logic                       := 'X';             -- reset
			axi_lite_reset_reset               : in  std_logic                       := 'X'              -- reset
		);
	end component axi4_adapter;

	u0 : component axi4_adapter
		port map (
			axi_bridge_in_awid                 => CONNECTED_TO_axi_bridge_in_awid,                 --              axi_bridge_in.awid
			axi_bridge_in_awaddr               => CONNECTED_TO_axi_bridge_in_awaddr,               --                           .awaddr
			axi_bridge_in_awlen                => CONNECTED_TO_axi_bridge_in_awlen,                --                           .awlen
			axi_bridge_in_awsize               => CONNECTED_TO_axi_bridge_in_awsize,               --                           .awsize
			axi_bridge_in_awburst              => CONNECTED_TO_axi_bridge_in_awburst,              --                           .awburst
			axi_bridge_in_awlock               => CONNECTED_TO_axi_bridge_in_awlock,               --                           .awlock
			axi_bridge_in_awprot               => CONNECTED_TO_axi_bridge_in_awprot,               --                           .awprot
			axi_bridge_in_awvalid              => CONNECTED_TO_axi_bridge_in_awvalid,              --                           .awvalid
			axi_bridge_in_awready              => CONNECTED_TO_axi_bridge_in_awready,              --                           .awready
			axi_bridge_in_wdata                => CONNECTED_TO_axi_bridge_in_wdata,                --                           .wdata
			axi_bridge_in_wstrb                => CONNECTED_TO_axi_bridge_in_wstrb,                --                           .wstrb
			axi_bridge_in_wlast                => CONNECTED_TO_axi_bridge_in_wlast,                --                           .wlast
			axi_bridge_in_wvalid               => CONNECTED_TO_axi_bridge_in_wvalid,               --                           .wvalid
			axi_bridge_in_wready               => CONNECTED_TO_axi_bridge_in_wready,               --                           .wready
			axi_bridge_in_bid                  => CONNECTED_TO_axi_bridge_in_bid,                  --                           .bid
			axi_bridge_in_bresp                => CONNECTED_TO_axi_bridge_in_bresp,                --                           .bresp
			axi_bridge_in_bvalid               => CONNECTED_TO_axi_bridge_in_bvalid,               --                           .bvalid
			axi_bridge_in_bready               => CONNECTED_TO_axi_bridge_in_bready,               --                           .bready
			axi_bridge_in_arid                 => CONNECTED_TO_axi_bridge_in_arid,                 --                           .arid
			axi_bridge_in_araddr               => CONNECTED_TO_axi_bridge_in_araddr,               --                           .araddr
			axi_bridge_in_arlen                => CONNECTED_TO_axi_bridge_in_arlen,                --                           .arlen
			axi_bridge_in_arsize               => CONNECTED_TO_axi_bridge_in_arsize,               --                           .arsize
			axi_bridge_in_arburst              => CONNECTED_TO_axi_bridge_in_arburst,              --                           .arburst
			axi_bridge_in_arlock               => CONNECTED_TO_axi_bridge_in_arlock,               --                           .arlock
			axi_bridge_in_arprot               => CONNECTED_TO_axi_bridge_in_arprot,               --                           .arprot
			axi_bridge_in_arvalid              => CONNECTED_TO_axi_bridge_in_arvalid,              --                           .arvalid
			axi_bridge_in_arready              => CONNECTED_TO_axi_bridge_in_arready,              --                           .arready
			axi_bridge_in_rid                  => CONNECTED_TO_axi_bridge_in_rid,                  --                           .rid
			axi_bridge_in_rdata                => CONNECTED_TO_axi_bridge_in_rdata,                --                           .rdata
			axi_bridge_in_rresp                => CONNECTED_TO_axi_bridge_in_rresp,                --                           .rresp
			axi_bridge_in_rlast                => CONNECTED_TO_axi_bridge_in_rlast,                --                           .rlast
			axi_bridge_in_rvalid               => CONNECTED_TO_axi_bridge_in_rvalid,               --                           .rvalid
			axi_bridge_in_rready               => CONNECTED_TO_axi_bridge_in_rready,               --                           .rready
			axi_bridge_lite_pf0_m0_awaddr      => CONNECTED_TO_axi_bridge_lite_pf0_m0_awaddr,      --     axi_bridge_lite_pf0_m0.awaddr
			axi_bridge_lite_pf0_m0_awprot      => CONNECTED_TO_axi_bridge_lite_pf0_m0_awprot,      --                           .awprot
			axi_bridge_lite_pf0_m0_awvalid     => CONNECTED_TO_axi_bridge_lite_pf0_m0_awvalid,     --                           .awvalid
			axi_bridge_lite_pf0_m0_awready     => CONNECTED_TO_axi_bridge_lite_pf0_m0_awready,     --                           .awready
			axi_bridge_lite_pf0_m0_wdata       => CONNECTED_TO_axi_bridge_lite_pf0_m0_wdata,       --                           .wdata
			axi_bridge_lite_pf0_m0_wstrb       => CONNECTED_TO_axi_bridge_lite_pf0_m0_wstrb,       --                           .wstrb
			axi_bridge_lite_pf0_m0_wvalid      => CONNECTED_TO_axi_bridge_lite_pf0_m0_wvalid,      --                           .wvalid
			axi_bridge_lite_pf0_m0_wready      => CONNECTED_TO_axi_bridge_lite_pf0_m0_wready,      --                           .wready
			axi_bridge_lite_pf0_m0_bresp       => CONNECTED_TO_axi_bridge_lite_pf0_m0_bresp,       --                           .bresp
			axi_bridge_lite_pf0_m0_bvalid      => CONNECTED_TO_axi_bridge_lite_pf0_m0_bvalid,      --                           .bvalid
			axi_bridge_lite_pf0_m0_bready      => CONNECTED_TO_axi_bridge_lite_pf0_m0_bready,      --                           .bready
			axi_bridge_lite_pf0_m0_araddr      => CONNECTED_TO_axi_bridge_lite_pf0_m0_araddr,      --                           .araddr
			axi_bridge_lite_pf0_m0_arprot      => CONNECTED_TO_axi_bridge_lite_pf0_m0_arprot,      --                           .arprot
			axi_bridge_lite_pf0_m0_arvalid     => CONNECTED_TO_axi_bridge_lite_pf0_m0_arvalid,     --                           .arvalid
			axi_bridge_lite_pf0_m0_arready     => CONNECTED_TO_axi_bridge_lite_pf0_m0_arready,     --                           .arready
			axi_bridge_lite_pf0_m0_rdata       => CONNECTED_TO_axi_bridge_lite_pf0_m0_rdata,       --                           .rdata
			axi_bridge_lite_pf0_m0_rresp       => CONNECTED_TO_axi_bridge_lite_pf0_m0_rresp,       --                           .rresp
			axi_bridge_lite_pf0_m0_rvalid      => CONNECTED_TO_axi_bridge_lite_pf0_m0_rvalid,      --                           .rvalid
			axi_bridge_lite_pf0_m0_rready      => CONNECTED_TO_axi_bridge_lite_pf0_m0_rready,      --                           .rready
			axi_bridge_lite_pf1_m0_awaddr      => CONNECTED_TO_axi_bridge_lite_pf1_m0_awaddr,      --     axi_bridge_lite_pf1_m0.awaddr
			axi_bridge_lite_pf1_m0_awprot      => CONNECTED_TO_axi_bridge_lite_pf1_m0_awprot,      --                           .awprot
			axi_bridge_lite_pf1_m0_awvalid     => CONNECTED_TO_axi_bridge_lite_pf1_m0_awvalid,     --                           .awvalid
			axi_bridge_lite_pf1_m0_awready     => CONNECTED_TO_axi_bridge_lite_pf1_m0_awready,     --                           .awready
			axi_bridge_lite_pf1_m0_wdata       => CONNECTED_TO_axi_bridge_lite_pf1_m0_wdata,       --                           .wdata
			axi_bridge_lite_pf1_m0_wstrb       => CONNECTED_TO_axi_bridge_lite_pf1_m0_wstrb,       --                           .wstrb
			axi_bridge_lite_pf1_m0_wvalid      => CONNECTED_TO_axi_bridge_lite_pf1_m0_wvalid,      --                           .wvalid
			axi_bridge_lite_pf1_m0_wready      => CONNECTED_TO_axi_bridge_lite_pf1_m0_wready,      --                           .wready
			axi_bridge_lite_pf1_m0_bresp       => CONNECTED_TO_axi_bridge_lite_pf1_m0_bresp,       --                           .bresp
			axi_bridge_lite_pf1_m0_bvalid      => CONNECTED_TO_axi_bridge_lite_pf1_m0_bvalid,      --                           .bvalid
			axi_bridge_lite_pf1_m0_bready      => CONNECTED_TO_axi_bridge_lite_pf1_m0_bready,      --                           .bready
			axi_bridge_lite_pf1_m0_araddr      => CONNECTED_TO_axi_bridge_lite_pf1_m0_araddr,      --                           .araddr
			axi_bridge_lite_pf1_m0_arprot      => CONNECTED_TO_axi_bridge_lite_pf1_m0_arprot,      --                           .arprot
			axi_bridge_lite_pf1_m0_arvalid     => CONNECTED_TO_axi_bridge_lite_pf1_m0_arvalid,     --                           .arvalid
			axi_bridge_lite_pf1_m0_arready     => CONNECTED_TO_axi_bridge_lite_pf1_m0_arready,     --                           .arready
			axi_bridge_lite_pf1_m0_rdata       => CONNECTED_TO_axi_bridge_lite_pf1_m0_rdata,       --                           .rdata
			axi_bridge_lite_pf1_m0_rresp       => CONNECTED_TO_axi_bridge_lite_pf1_m0_rresp,       --                           .rresp
			axi_bridge_lite_pf1_m0_rvalid      => CONNECTED_TO_axi_bridge_lite_pf1_m0_rvalid,      --                           .rvalid
			axi_bridge_lite_pf1_m0_rready      => CONNECTED_TO_axi_bridge_lite_pf1_m0_rready,      --                           .rready
			axi_bridge_lite_pf1_ext_m0_awaddr  => CONNECTED_TO_axi_bridge_lite_pf1_ext_m0_awaddr,  -- axi_bridge_lite_pf1_ext_m0.awaddr
			axi_bridge_lite_pf1_ext_m0_awprot  => CONNECTED_TO_axi_bridge_lite_pf1_ext_m0_awprot,  --                           .awprot
			axi_bridge_lite_pf1_ext_m0_awvalid => CONNECTED_TO_axi_bridge_lite_pf1_ext_m0_awvalid, --                           .awvalid
			axi_bridge_lite_pf1_ext_m0_awready => CONNECTED_TO_axi_bridge_lite_pf1_ext_m0_awready, --                           .awready
			axi_bridge_lite_pf1_ext_m0_wdata   => CONNECTED_TO_axi_bridge_lite_pf1_ext_m0_wdata,   --                           .wdata
			axi_bridge_lite_pf1_ext_m0_wstrb   => CONNECTED_TO_axi_bridge_lite_pf1_ext_m0_wstrb,   --                           .wstrb
			axi_bridge_lite_pf1_ext_m0_wvalid  => CONNECTED_TO_axi_bridge_lite_pf1_ext_m0_wvalid,  --                           .wvalid
			axi_bridge_lite_pf1_ext_m0_wready  => CONNECTED_TO_axi_bridge_lite_pf1_ext_m0_wready,  --                           .wready
			axi_bridge_lite_pf1_ext_m0_bresp   => CONNECTED_TO_axi_bridge_lite_pf1_ext_m0_bresp,   --                           .bresp
			axi_bridge_lite_pf1_ext_m0_bvalid  => CONNECTED_TO_axi_bridge_lite_pf1_ext_m0_bvalid,  --                           .bvalid
			axi_bridge_lite_pf1_ext_m0_bready  => CONNECTED_TO_axi_bridge_lite_pf1_ext_m0_bready,  --                           .bready
			axi_bridge_lite_pf1_ext_m0_araddr  => CONNECTED_TO_axi_bridge_lite_pf1_ext_m0_araddr,  --                           .araddr
			axi_bridge_lite_pf1_ext_m0_arprot  => CONNECTED_TO_axi_bridge_lite_pf1_ext_m0_arprot,  --                           .arprot
			axi_bridge_lite_pf1_ext_m0_arvalid => CONNECTED_TO_axi_bridge_lite_pf1_ext_m0_arvalid, --                           .arvalid
			axi_bridge_lite_pf1_ext_m0_arready => CONNECTED_TO_axi_bridge_lite_pf1_ext_m0_arready, --                           .arready
			axi_bridge_lite_pf1_ext_m0_rdata   => CONNECTED_TO_axi_bridge_lite_pf1_ext_m0_rdata,   --                           .rdata
			axi_bridge_lite_pf1_ext_m0_rresp   => CONNECTED_TO_axi_bridge_lite_pf1_ext_m0_rresp,   --                           .rresp
			axi_bridge_lite_pf1_ext_m0_rvalid  => CONNECTED_TO_axi_bridge_lite_pf1_ext_m0_rvalid,  --                           .rvalid
			axi_bridge_lite_pf1_ext_m0_rready  => CONNECTED_TO_axi_bridge_lite_pf1_ext_m0_rready,  --                           .rready
			axi_mm_clk_clk                     => CONNECTED_TO_axi_mm_clk_clk,                     --                 axi_mm_clk.clk
			axi_lite_clk_clk                   => CONNECTED_TO_axi_lite_clk_clk,                   --               axi_lite_clk.clk
			axi_mm_reset_reset                 => CONNECTED_TO_axi_mm_reset_reset,                 --               axi_mm_reset.reset
			axi_lite_reset_reset               => CONNECTED_TO_axi_lite_reset_reset                --             axi_lite_reset.reset
		);

