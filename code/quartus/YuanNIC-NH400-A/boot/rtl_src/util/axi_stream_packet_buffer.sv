`timescale 1ns/1ps
module axi_stream_packet_buffer #(
  parameter      CLOCKING_MODE   = "independent_clock",
  parameter int  DEPTH_W         = 9,
  parameter int  TDATA_W         = 512,
  parameter int  TKEEP_W         = TDATA_W/8,
  parameter int  TUSER_W         = 1
  // Specify the buffer capcacity in terms of how many maximum-sized packets
  // must fit in
) (
  input                  s_axis_tvalid,
  input    [TDATA_W-1:0] s_axis_tdata,
  input    [TKEEP_W-1:0] s_axis_tkeep,
  input                  s_axis_tlast,
  input    [TUSER_W-1:0] s_axis_tuser,
  output                 s_axis_tready,

  input                  drop,
  output                 drop_busy,

  output                 m_axis_tvalid,
  output   [TDATA_W-1:0] m_axis_tdata,
  output   [TKEEP_W-1:0] m_axis_tkeep,
  output                 m_axis_tlast,
  output   [TUSER_W-1:0] m_axis_tuser,
  input                  m_axis_tready,

  input                  s_aclk,
  input                  s_aresetn,
  input                  m_aclk
);

  // Parameter DRC
  initial begin
    if (CLOCKING_MODE != "common_clock" && CLOCKING_MODE != "independent_clock") begin
      $fatal("[%m] Invalid CLOCKING_MODE");
    end
  end

  localparam C_RAM_DATA_W      = TUSER_W + 1 + TKEEP_W + TDATA_W;
  localparam C_RAM_ADDR_W      = DEPTH_W;
  localparam C_RAM_DEPTH       = 1 << DEPTH_W;

  // Read-side FSM
  localparam S_RD_P00 = 2'd0;
  localparam S_RD_P01 = 2'd1;
  localparam S_RD_P10 = 2'd2;
  localparam S_RD_P11 = 2'd3;

  reg                     drop_in_prog;
  reg                     dropped;

  reg               [1:0] rd_state;
  reg               [1:0] next_rd_state;
  reg  [C_RAM_ADDR_W-1:0] next_ram_addrb;

  wire                    ram_ena;
  wire                    ram_wea;
  reg  [C_RAM_ADDR_W-1:0] ram_addra;
  wire [C_RAM_DATA_W-1:0] ram_dina;
  reg                     ram_enb;
  reg                     ram_regceb;
  reg  [C_RAM_ADDR_W-1:0] ram_addrb;
  wire [C_RAM_DATA_W-1:0] ram_doutb;

  reg    [C_RAM_ADDR_W:0] ram_data_cnt;
  wire                    ram_empty;
  wire                    ram_full;
  reg  [C_RAM_ADDR_W-1:0] ram_addra_checkpoint;

  reg    [C_RAM_ADDR_W:0] partial_pkt_beats;
  reg    [C_RAM_ADDR_W:0] full_pkt_beats;

  wire                    axis_ram_tvalid;
  wire      [TDATA_W-1:0] axis_ram_tdata;
  wire      [TKEEP_W-1:0] axis_ram_tkeep;
  wire                    axis_ram_tlast;
  wire      [TUSER_W-1:0] axis_ram_tuser;
  wire                    axis_ram_tready;

  // The `drop_busy` signal synchronizes with the packet stream `axis_*`.  When
  // asserted, the corresponding beat is not written into the RAM.
  assign drop_busy = drop || drop_in_prog;

  always @(posedge s_aclk) begin
    if (~s_aresetn) begin
      drop_in_prog <= 1'b0;
    end
    else if (s_axis_tvalid && s_axis_tlast && s_axis_tready) begin
      drop_in_prog <= 1'b0;
    end
    else if (drop) begin
      drop_in_prog <= 1'b1;
    end
  end

  always @(posedge s_aclk) begin
    if (~s_aresetn) begin
      dropped <= 1'b0;
    end
    else if (s_axis_tvalid && s_axis_tlast && s_axis_tready && drop_in_prog) begin
      dropped <= 1'b1;
    end
    else if(drop) begin
      dropped <= 1'b1;
    end 
    else begin
      dropped <= 1'b0;
    end
  end

    ram#(
        .ram_block_type         ("M20K"     ),
        .outdata_b_reg          ("USED"     ),
        .widthad_a              (C_RAM_ADDR_W  ),
        .widthad_b              (C_RAM_ADDR_W  ),
        .width_a                (C_RAM_DATA_W  ),
        .width_b                (C_RAM_DATA_W  )
    ) ram_inst (
        .wrclock                (s_aclk         ),
        .wren                   (ram_wea        ),
        .wraddress              (ram_addra      ),
        .data                   (ram_dina       ),
        .rdclock                (s_aclk         ),
        .rden                   (ram_enb        ),
        .rdaddress              (ram_addrb      ),
        .q                      (ram_doutb      )
    );

  // Record how many beats of the incoming packet have been written into RAM.
  // When a full packet is received or when the current packet is dropped, this
  // value resets to 0.
  always @(posedge s_aclk) begin
    if (~s_aresetn) begin
      partial_pkt_beats <= 0;
    end
    else if (drop_busy) begin
      partial_pkt_beats <= 0;
    end
    else if (s_axis_tvalid && s_axis_tready) begin
      partial_pkt_beats <= (s_axis_tlast) ? 0 : (partial_pkt_beats + 1);
    end
  end

  // Record data count in RAM.  Port A is only for writing and port B only for
  // reading.  For port A, `ram_wea` is tied to `ram_ena`.
  always @(posedge s_aclk) begin
    if (~s_aresetn) begin
      ram_data_cnt <= 0;
    end
    else if (drop_busy) begin
      if (ram_enb) begin
        ram_data_cnt <= ram_data_cnt - partial_pkt_beats - 1;
      end
      else begin
        ram_data_cnt <= ram_data_cnt - partial_pkt_beats;
      end
    end
    else if (ram_ena && ~ram_enb) begin
      ram_data_cnt <= ram_data_cnt + 1;
    end
    else if (ram_enb && ~ram_ena) begin
      ram_data_cnt <= ram_data_cnt - 1;
    end
  end

  assign ram_empty     = (ram_data_cnt == 0);
  assign ram_full      = (ram_data_cnt == C_RAM_DEPTH);

  assign s_axis_tready = ~ram_full;
  assign ram_ena       = s_axis_tvalid && s_axis_tready && ~drop_busy;
  assign ram_wea       = ram_ena;
  assign ram_dina      = {s_axis_tuser, s_axis_tlast, s_axis_tkeep, s_axis_tdata};

  // Increment write address for every beat that has not been dropped and rewind
  // to the previous checkpoint when a partial packet is dropped
  always @(posedge s_aclk) begin
    if (~s_aresetn) begin
      ram_addra <= 0;
    end
    else if (drop_busy) begin
      ram_addra <= ram_addra_checkpoint;
    end
    else if (s_axis_tvalid && s_axis_tready) begin
      ram_addra <= ram_addra + 1;
    end
  end

  // Record a checkpoint for write address when a complete packet is written
  // into the buffer
  always @(posedge s_aclk) begin
    if (~s_aresetn) begin
      ram_addra_checkpoint <= 0;
    end
    else if (s_axis_tvalid && s_axis_tready && s_axis_tlast && ~drop_busy) begin
      ram_addra_checkpoint <= ram_addra + 1;
    end
  end

  always @(*) begin
    if (ram_addra_checkpoint == ram_addrb) begin
      full_pkt_beats = (ram_full) ? C_RAM_DEPTH : 0;
    end
    else if (ram_addra_checkpoint > ram_addrb) begin
      full_pkt_beats = ram_addra_checkpoint - ram_addrb;
    end
    else begin
      full_pkt_beats = {1'b1, ram_addra_checkpoint} - ram_addrb;
    end
  end

  // Given that the RAM has a read latency of 2 cycles, the FSM states have the
  // following interpretation.  "PXX" shows the current status of the 2 stage
  // output registers, where "X" being 0 means no valid data and being 1 means
  // there is valid data.  For example, "P10" means that the first stage of
  // output registers, i.e., bank-level ones, have latched read data, while the
  // second stage registers, i.e., those after the MUX, have no data.  State
  // transition is controlled by a combination of `ram_enb`, `ram_regceb` and
  // `axis_ram_tready`.
  always @(*) begin
    ram_enb        = 1'b0;
    ram_regceb     = 1'b0;
    next_ram_addrb = ram_addrb;
    next_rd_state  = rd_state;

    case (rd_state)
      S_RD_P00: begin
        if (full_pkt_beats > 0) begin
          ram_enb        = 1'b1;
          next_ram_addrb = ram_addrb + 1;
          next_rd_state  = S_RD_P10;
        end
      end

      S_RD_P10: begin
        ram_regceb = 1'b1;

        if (full_pkt_beats > 0) begin
          ram_enb        = 1'b1;
          next_ram_addrb = ram_addrb + 1;
          next_rd_state  = S_RD_P11;
        end
        else begin
          next_rd_state  = S_RD_P01;
        end
      end

      S_RD_P01: begin
        if (axis_ram_tvalid && axis_ram_tready) begin
          if (full_pkt_beats > 0) begin
            ram_enb        = 1'b1;
            next_ram_addrb = ram_addrb + 1;
            next_rd_state  = S_RD_P10;
          end
          else begin
            next_rd_state = S_RD_P00;
          end
        end
        else begin
          if (full_pkt_beats > 0) begin
            ram_enb        = 1'b1;
            next_ram_addrb = ram_addrb + 1;
            next_rd_state  = S_RD_P11;
          end
        end
      end

      S_RD_P11: begin
        if (axis_ram_tvalid && axis_ram_tready) begin
          ram_regceb = 1'b1;

          if (full_pkt_beats > 0) begin
            ram_enb        = 1'b1;
            next_ram_addrb = ram_addrb + 1;
          end
          else begin
            next_rd_state = S_RD_P01;
          end
        end
      end
    endcase
  end

  always @(posedge s_aclk) begin
    if (~s_aresetn) begin
      ram_addrb <= 0;
      rd_state  <= S_RD_P00;
    end
    else begin
      ram_addrb <= next_ram_addrb;
      rd_state  <= next_rd_state;
    end
  end

  assign axis_ram_tvalid = ((rd_state == S_RD_P01) || (rd_state == S_RD_P11));
  assign {axis_ram_tuser,axis_ram_tlast, axis_ram_tkeep, axis_ram_tdata} = ram_doutb;

  generate if (CLOCKING_MODE == "independent_clock") begin
    xpm_fifo_axis #(
      .CLOCKING_MODE    (CLOCKING_MODE),
      .FIFO_MEMORY_TYPE ("auto"),
      .PACKET_FIFO      ("false"),
      .FIFO_DEPTH       (16),   // minimum value is fine
      .TDATA_WIDTH      (TDATA_W),
      .TID_WIDTH        (TID_W),
      .TDEST_WIDTH      (TDEST_W),
      .TUSER_WIDTH      (TUSER_W + 16),
      .ECC_MODE         ("no_ecc"),
      .RELATED_CLOCKS   (0),
      .CDC_SYNC_STAGES  (2)
    ) cdc_inst (
      .s_axis_tvalid      (axis_ram_tvalid),
      .s_axis_tdata       (axis_ram_tdata),
      .s_axis_tkeep       (axis_ram_tkeep),
      .s_axis_tstrb       ({(TDATA_W/8){1'b1}}),
      .s_axis_tlast       (axis_ram_tlast),
      .s_axis_tid         (axis_ram_tid),
      .s_axis_tdest       (axis_ram_tdest),
      .s_axis_tuser       ({axis_ram_tuser, size_fifo_dout}),
      .s_axis_tready      (axis_ram_tready),

      .m_axis_tvalid      (m_axis_tvalid),
      .m_axis_tdata       (m_axis_tdata),
      .m_axis_tkeep       (m_axis_tkeep),
      .m_axis_tstrb       (),
      .m_axis_tlast       (m_axis_tlast),
      .m_axis_tid         (m_axis_tid),
      .m_axis_tdest       (m_axis_tdest),
      .m_axis_tuser       ({m_axis_tuser, m_axis_tuser_size}),
      .m_axis_tready      (m_axis_tready),

      .almost_empty_axis  (),
      .prog_empty_axis    (),
      .almost_full_axis   (),
      .prog_full_axis     (),
      .wr_data_count_axis (),
      .rd_data_count_axis (),

      .injectsbiterr_axis (1'b0),
      .injectdbiterr_axis (1'b0),
      .sbiterr_axis       (),
      .dbiterr_axis       (),

      .s_aclk             (s_aclk),
      .m_aclk             (m_aclk),
      .s_aresetn          (s_aresetn)
    );

    axis_async_fifo #(
    .DEPTH(DEPTH),
    .DATA_WIDTH(DATA_WIDTH),
    .LAST_ENABLE(1),
    .ID_ENABLE(0),
    .ID_WIDTH(ID_WIDTH),
    .DEST_ENABLE(DEST_ENABLE),
    .DEST_WIDTH(DEST_WIDTH),
    .USER_ENABLE(USER_ENABLE),
    .USER_WIDTH(USER_WIDTH),
    .RAM_PIPELINE(RAM_PIPELINE),
    .OUTPUT_FIFO_ENABLE(OUTPUT_FIFO_ENABLE),
    .FRAME_FIFO(FRAME_FIFO),
    .USER_BAD_FRAME_VALUE(USER_BAD_FRAME_VALUE),
    .USER_BAD_FRAME_MASK(USER_BAD_FRAME_MASK),
    .DROP_OVERSIZE_FRAME(DROP_OVERSIZE_FRAME),
    .DROP_BAD_FRAME(DROP_BAD_FRAME),
    .DROP_WHEN_FULL(DROP_WHEN_FULL),
    .MARK_WHEN_FULL(MARK_WHEN_FULL),
    .PAUSE_ENABLE(PAUSE_ENABLE),
    .FRAME_PAUSE(FRAME_PAUSE)
)
fifo_inst (
    // AXI input
    .s_clk(s_clk),
    .s_rst(s_rst),
    .s_axis_tdata(s_axis_tdata),
    .s_axis_tkeep(s_axis_tkeep),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tready(s_axis_tready),
    .s_axis_tlast(s_axis_tlast),
    .s_axis_tid(),
    .s_axis_tdest(),
    .s_axis_tuser(),
    // AXI output
    .m_clk(m_clk),
    .m_rst(m_rst),
    .m_axis_tdata(m_axis_tdata),
    .m_axis_tkeep(m_axis_tkeep),
    .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tready(m_axis_tready),
    .m_axis_tlast(m_axis_tlast),
    .m_axis_tid(),
    .m_axis_tdest(),
    .m_axis_tuser()
    
);
  end
  else begin
    assign m_axis_tvalid     = axis_ram_tvalid;
    assign m_axis_tdata      = axis_ram_tdata;
    assign m_axis_tkeep      = axis_ram_tkeep;
    assign m_axis_tlast      = axis_ram_tlast;
    assign m_axis_tuser      = axis_ram_tuser;
    assign axis_ram_tready   = m_axis_tready;
  end
  endgenerate

endmodule: axi_stream_packet_buffer
