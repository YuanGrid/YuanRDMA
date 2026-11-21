`resetall
`default_nettype none
`timescale 1ns / 1ps

module qdma_top #
(
    parameter   DATA_W                  = 512,
    parameter   EMTY_W                  = 6,          // EOP空字节计数位宽
    parameter   CHANNEL_W               = 11        // 信道号位宽
) // EOP空字节计数位宽
(
    input   wire    [27:0]              s_avm_addr ,
    input   wire                        s_avm_read ,
    input   wire                        s_avm_write,
    input   wire    [31:0]              s_avm_wdat ,
    output  wire                        s_avm_wait ,
    output  wire    [31:0]              s_avm_rdat ,
    output  wire                        s_avm_rvld ,
    output  wire    [1:0]               s_avm_rspo ,
    output  wire                        s_avm_wrsp ,
    output  reg                         m_d2h_st_sof    ,
    output  wire                        m_d2h_st_eof    ,
    output  wire    [EMTY_W-1:0]        m_d2h_st_empty  ,
    output  wire    [CHANNEL_W-1:0]     m_d2h_st_channel,
    output  wire                        m_d2h_st_valid  ,
    output  wire    [DATA_W-1:0]        m_d2h_st_data   ,
    input   wire                        m_d2h_st_ready  ,
    input   wire                        s_d2h_axis_last    ,
    input   wire    [EMTY_W:0]          s_d2h_axis_empty   ,
    input   wire                        s_d2h_axis_valid  ,
    input   wire    [2*DATA_W-1:0]      s_d2h_axis_data   ,
    output  wire                        s_d2h_axis_ready  ,
    input   wire                        s_h2d_st_sof    ,
    input   wire                        s_h2d_st_eop    ,
    input   wire    [EMTY_W-1:0]        s_h2d_st_empty  ,
    output  wire                        s_h2d_st_ready  ,
    input   wire                        s_h2d_st_valid  ,
    input   wire    [DATA_W-1:0]        s_h2d_st_data   ,
    input   wire    [CHANNEL_W-1:0]     s_h2d_st_channel,
    output  wire                        m_h2d_axis_last    ,
    output  wire    [EMTY_W:0]          m_h2d_axis_empty   ,
    input   wire                        m_h2d_axis_ready   ,
    output  wire                        m_h2d_axis_valid   ,
    output  wire    [2*DATA_W-1:0]      m_h2d_axis_data    ,
    input  wire 						axil_aclk,
    input  wire 						dma_clk,
    input  wire 						dma_rst,
    input  wire 						mac_clk,
    input  wire 						mac_rst
);
    wire                                rxw_to_regl_tvalid;
    wire    [DATA_W-1:0]                rxw_to_regl_tdata ;
    wire    [EMTY_W-1:0]                rxw_to_regl_tkeep ;
    wire                                rxw_to_regl_tlast ;
    wire                                rxw_to_regl_tready;

    wire                                regl_to_qdma_tvalid;
    wire    [DATA_W-1:0]                regl_to_qdma_tdata ;
    wire    [EMTY_W-1:0]                regl_to_qdma_tkeep ;
    wire                                regl_to_qdma_tlast ;
    wire                                regl_to_qdma_tready;

    wire                                qdma_to_txw_valid;
    wire    [DATA_W-1:0]                qdma_to_txw_data ;
    wire    [EMTY_W-1:0]                qdma_to_txw_empty ;
    wire                                qdma_to_txw_last ;
    wire                                qdma_to_txw_ready;

    always @(posedge dma_clk ) begin
        if(dma_rst)
            m_d2h_st_sof <= 1'b1;
        else if(m_d2h_st_eof & m_d2h_st_valid & m_d2h_st_ready)
            m_d2h_st_sof <= 1'b1;
        else if(m_d2h_st_valid & m_d2h_st_ready)
            m_d2h_st_sof <= 1'b0;
    end

    rx_width_convt #(
        .S_DATA_W                       (2*DATA_W ),
        .M_DATA_W                       (DATA_W   )
    )
    u0_rx_width_convt
    (    
        .clk                            (dma_clk),
        .rst_n                          (~mac_rst),
        .s_axis_tvalid                  (s_d2h_axis_valid),
        .s_axis_tdata                   (s_d2h_axis_data),
        .s_axis_tkeep                   (s_d2h_axis_empty),
        .s_axis_tlast                   (s_d2h_axis_last),
        .s_axis_tready                  (s_d2h_axis_ready),
        .m_axis_tvalid                  (rxw_to_regl_tvalid),
        .m_axis_tdata                   (rxw_to_regl_tdata ),
        .m_axis_tkeep                   (rxw_to_regl_tkeep ),
        .m_axis_tlast                   (rxw_to_regl_tlast ),
        .m_axis_tready                  (rxw_to_regl_tready)
    );

    axi_stream_register_slice #(
        .TDATA_W                            (DATA_W         ),
        .TID_W                              (1              ),
        .TDEST_W                            (1              ),
        .TUSER_W                            (EMTY_W        ),
        .MODE                               ("full"         )
    )u21_axi_stream_register_slice (
        .s_axis_tvalid                      (rxw_to_regl_tvalid),
        .s_axis_tdata                       (rxw_to_regl_tdata ),
        .s_axis_tkeep                       (                  ),
        .s_axis_tlast                       (rxw_to_regl_tlast ),
        .s_axis_tid                         (                  ),
        .s_axis_tdest                       (                  ),
        .s_axis_tuser                       (rxw_to_regl_tkeep ),
        .s_axis_tready                      (rxw_to_regl_tready),
        .m_axis_tvalid                      (regl_to_qdma_tvalid),
        .m_axis_tdata                       (regl_to_qdma_tdata ),
        .m_axis_tkeep                       (                   ),
        .m_axis_tlast                       (regl_to_qdma_tlast ),
        .m_axis_tid                         (                   ),
        .m_axis_tdest                       (                   ),
        .m_axis_tuser                       (regl_to_qdma_tkeep ),
        .m_axis_tready                      (regl_to_qdma_tready),
        .aclk                               (dma_clk            ),
        .aresetn                            (~mac_rst           )
    );

    qdma_function#(
        .FUNC_ID                        (0                  )
    )
    u1_qdma_function
    (
        .s_avm_addr                     (s_avm_addr         ),
        .s_avm_read                     (s_avm_read         ),
        .s_avm_write                    (s_avm_write        ),
        .s_avm_wdat                     (s_avm_wdat         ),
        .s_avm_wait                     (s_avm_wait         ),
        .s_avm_rdat                     (s_avm_rdat         ),
        .s_avm_rvld                     (s_avm_rvld         ),
        .s_avm_rspo                     (s_avm_rspo         ),
        .s_avm_wrsp                     (s_avm_wrsp         ),
        .s_axis_h2c_tvalid              (s_h2d_st_valid     ),    
        .s_axis_h2c_tdata               (s_h2d_st_data      ),
        .s_axis_h2c_temty               (s_h2d_st_empty     ),
        .s_axis_h2c_tlast               (s_h2d_st_eop       ),
        .s_axis_h2c_tuser_qid           (s_h2d_st_channel   ),
        .s_axis_h2c_tready              (s_h2d_st_ready     ),
        .m_axis_h2c_tvalid              (qdma_to_txw_valid  ),
        .m_axis_h2c_tdata               (qdma_to_txw_data   ),
        .m_axis_h2c_tkeep               (qdma_to_txw_empty  ),
        .m_axis_h2c_tlast               (qdma_to_txw_last   ),
        .m_axis_h2c_tready              (qdma_to_txw_ready  ),
        .s_axis_c2h_tvalid              (regl_to_qdma_tvalid ),
        .s_axis_c2h_tdata               (regl_to_qdma_tdata  ),
        .s_axis_c2h_tkeep               (regl_to_qdma_tkeep  ),
        .s_axis_c2h_tlast               (regl_to_qdma_tlast  ),
        .s_axis_c2h_tready              (regl_to_qdma_tready ),
        .m_axis_c2h_tvalid              (m_d2h_st_valid     ),
        .m_axis_c2h_tdata               (m_d2h_st_data      ),
        .m_axis_c2h_tlast               (m_d2h_st_eof       ),
        .m_axis_c2h_tkeep               (m_d2h_st_empty     ),
        .m_axis_c2h_tuser_qid           (m_d2h_st_channel   ),
        .m_axis_c2h_tready              (m_d2h_st_ready     ),
        .axil_aclk                      (axil_aclk          ),
        .dma_clk                        (dma_clk            ),
        .axis_aclk                      (dma_clk            ),
        .axil_aresetn                   (~mac_rst           )
    );

    tx_width_convt #(
        .DATA_WIDTH                     (512                )
    )
    u2_tx_width_convt
    (
        .s_avst_data                    (qdma_to_txw_data   ),
        .s_avst_emty                    (qdma_to_txw_empty  ),
        .s_avst_channel                 (11'b0              ),
        .s_avst_valid                   (qdma_to_txw_valid  ),
        .s_avst_eof                     (qdma_to_txw_last   ),
        .s_avst_sof                     (1'b0               ),
        .s_avst_ready                   (qdma_to_txw_ready  ),
        .m_axis_tx_data                 (m_h2d_axis_data    ),
        .m_axis_tx_usef                 (m_h2d_axis_empty   ),
        .m_axis_tx_last                 (m_h2d_axis_last    ),
        .m_axis_tx_valid                (m_h2d_axis_valid   ),
        .m_axis_tx_ready                (m_h2d_axis_ready   ),
        .dma_clk                        (dma_clk            ),
        .dma_rst                        (dma_rst            ),
        .mac_tx_clk                     (mac_clk            ),
        .mac_tx_rst                     (mac_rst            )
    ); 
endmodule
`resetall