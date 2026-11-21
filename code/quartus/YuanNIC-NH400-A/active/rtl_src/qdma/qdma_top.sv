`resetall
`default_nettype none
`timescale 1ns / 1ps

module qdma_top #
(
    parameter   DATA_W                  = 1024,
    parameter   EMTY_W                  = 7,          // EOP空字节计数位宽
    parameter   CHANNEL_W               = 11        // 信道号位宽
) // EOP空字节计数位宽
(
    input   wire    [27:0]              s_avm_addr          ,
    input   wire                        s_avm_read          ,
    input   wire                        s_avm_write         ,
    input   wire    [31:0]              s_avm_wdat          ,
    output  wire                        s_avm_wait          ,
    output  wire    [31:0]              s_avm_rdat          ,
    output  wire                        s_avm_rvld          ,
    output  wire    [1:0]               s_avm_rspo          ,
    output  wire                        s_avm_wrsp          ,
    output  reg                         m_d2h_st_sof        ,
    output  wire                        m_d2h_st_eof        ,
    output  wire    [EMTY_W-1:0]        m_d2h_st_empty      ,
    output  wire    [CHANNEL_W-1:0]     m_d2h_st_channel    ,
    output  wire                        m_d2h_st_valid      ,
    output  wire    [DATA_W-1:0]        m_d2h_st_data       ,
    input   wire                        m_d2h_st_ready      ,
    input   wire                        s_d2h_axis_last     ,
    input   wire    [EMTY_W-1:0]        s_d2h_axis_empty    ,
    input   wire                        s_d2h_axis_valid    ,
    input   wire    [DATA_W-1:0]        s_d2h_axis_data     ,
    output  wire                        s_d2h_axis_ready    ,
    input   wire                        s_h2d_st_sof        ,
    input   wire                        s_h2d_st_eop        ,
    input   wire    [EMTY_W-1:0]        s_h2d_st_empty      ,
    output  wire                        s_h2d_st_ready      ,
    input   wire                        s_h2d_st_valid      ,
    input   wire    [DATA_W-1:0]        s_h2d_st_data       ,
    input   wire    [CHANNEL_W-1:0]     s_h2d_st_channel    ,
    output  wire                        m_h2d_axis_last     ,
    output  wire    [EMTY_W-1:0]        m_h2d_axis_empty    ,
    input   wire                        m_h2d_axis_ready    ,
    output  wire                        m_h2d_axis_valid    ,
    output  wire    [DATA_W-1:0]        m_h2d_axis_data     ,
    input   wire    [8:0]               rx_pfc              ,
    input   wire                        statis_cnt_clear_en ,
    output  wire    [8*32-1:0]          pfc_pkt_drop_cnt    ,
    output  wire    [8*32-1:0]          pfc_pkt_in_cnt      ,
    output  wire    [8*32-1:0]          pfc_pkt_out_cnt     ,
    input   wire                        axil_aclk           ,
    input   wire                        axil_rst            ,
    input   wire                        dma_clk             ,
    input   wire                        dma_rst             ,
    input   wire                        mac_clk             ,
    input   wire                        mac_rst             
);
    wire                                rxw_to_regl_tvalid  ;
    wire    [DATA_W-1:0]                rxw_to_regl_tdata   ;
    wire    [EMTY_W-1:0]                rxw_to_regl_tkeep   ;
    wire                                rxw_to_regl_tlast   ;
    wire                                rxw_to_regl_tready  ;

    wire                                regl_to_qdma_tvalid ;
    wire    [DATA_W-1:0]                regl_to_qdma_tdata  ;
    wire    [EMTY_W-1:0]                regl_to_qdma_tkeep  ;
    wire                                regl_to_qdma_tlast  ;
    wire                                regl_to_qdma_tready ;

    wire                                qdma_to_fifo_valid  ;
    wire    [DATA_W-1:0]                qdma_to_fifo_data   ;
    wire    [EMTY_W-1:0]                qdma_to_fifo_empty  ;
    wire                                qdma_to_fifo_last   ;
    wire                                qdma_to_fifo_ready  ;
    reg     [EMTY_W-1:0]                qdma_to_fifo_usef   ;

    wire                                fifo_to_pfc_pa_valid   ;
    wire    [DATA_W-1:0]                fifo_to_pfc_pa_data    ;
    reg     [EMTY_W-1:0]                fifo_to_pfc_pa_usef    ;
    wire                                fifo_to_pfc_pa_last    ;
    wire                                fifo_to_pfc_pa_ready   ;

    wire                                parser_to_func_valid   ;
    wire    [DATA_W-1:0]                parser_to_func_data    ;
    reg     [EMTY_W-1:0]                parser_to_func_usef    ;
    wire                                parser_to_func_last    ;
    wire                                parser_to_func_ready   ;
    wire    [2:0]                       parser_to_func_Priority;

    assign rxw_to_regl_tvalid   = s_d2h_axis_valid;
    assign rxw_to_regl_tdata    = s_d2h_axis_data;
    assign rxw_to_regl_tkeep    = (s_d2h_axis_empty == 0 || s_d2h_axis_last == 1'b0)?0:128-s_d2h_axis_empty;
    assign rxw_to_regl_tlast    = s_d2h_axis_last;
    assign s_d2h_axis_ready     = rxw_to_regl_tready;

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
        .aresetn                            (~dma_rst           )
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
        .m_axis_h2c_tvalid              (qdma_to_fifo_valid  ),
        .m_axis_h2c_tdata               (qdma_to_fifo_data   ),
        .m_axis_h2c_tkeep               (qdma_to_fifo_empty  ),
        .m_axis_h2c_tlast               (qdma_to_fifo_last   ),
        .m_axis_h2c_tready              (qdma_to_fifo_ready  ),
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
        .dma_rstn                       (~dma_rst           ),
        .axil_aresetn                   (~axil_rst          )
    );

    always @(posedge dma_clk ) begin
        if(dma_rst)
            m_d2h_st_sof <= 1'b1;
        else if(m_d2h_st_eof & m_d2h_st_valid & m_d2h_st_ready)
            m_d2h_st_sof <= 1'b1;
        else if(m_d2h_st_valid & m_d2h_st_ready)
            m_d2h_st_sof <= 1'b0;
    end
    
    always_comb begin
        if(qdma_to_fifo_last) begin
            if(qdma_to_fifo_empty == 0)
                qdma_to_fifo_usef = 0;
            else
                qdma_to_fifo_usef = 128 - qdma_to_fifo_empty;
        end else begin
            qdma_to_fifo_usef = 0;
        end
    end

    axis_fifo #(
        .CLOCKING_MODE              ("DCFIFO"               ),
        .FIFO_TYPE                  ("M20K"                 ),
        .PACKET_FIFO                ("true"                 ),
        .FIFO_DEPTH                 (64                     ),
        .TDATA_WIDTH                (DATA_W                 ),
        .TUSER_WIDTH                (EMTY_W                 ),
        .ALMOST_EMPTY               (1                      ),
        .ALMOST_AFULL               (60                     ),
        .KEEP_EN                    ("OFF"                  ),//"ON"时 keep有效，off时emty有效
        .EOP_POP_DELAY              (1                      ) //断开 eop FIFO 读指针的临界组合路径
    )u2_tx_fifo_inst(
        .s_axis_tvalid              (qdma_to_fifo_valid     ),
        .s_axis_tready              (qdma_to_fifo_ready     ),
        .s_axis_tdata               (qdma_to_fifo_data      ),
        .s_axis_temty               (                       ),
        .s_axis_tkeep               (                       ),
        .s_axis_tlast               (qdma_to_fifo_last      ),
        .s_axis_tuser               (qdma_to_fifo_usef      ),
        .s_axis_pfull               (                       ),
        .s_axis_drop                (1'b0                   ),
        .m_axis_tvalid              (fifo_to_pfc_pa_valid   ),
        .m_axis_tready              (fifo_to_pfc_pa_ready   ),
        .m_axis_tdata               (fifo_to_pfc_pa_data    ),
        .m_axis_temty               (                       ),
        .m_axis_tkeep               (                       ),
        .m_axis_tlast               (fifo_to_pfc_pa_last    ),
        .m_axis_tuser               (fifo_to_pfc_pa_usef    ),
        .s_aresetn                  (~dma_rst               ),
        .s_clk                      (dma_clk                ),
        .m_clk                      (mac_clk                )
    );

    pfc_parser #(
        .DATA_W                     (DATA_W                 )
    )
    u3_pfc_parser
    (    
        .clk                        (mac_clk                ),
        .rst_n                      (~mac_rst               ),
        .s_axis_rx_tvalid           (fifo_to_pfc_pa_valid   ),
        .s_axis_rx_tdata            (fifo_to_pfc_pa_data    ),
        .s_axis_rx_tkeep            (fifo_to_pfc_pa_usef    ),
        .s_axis_rx_tlast            (fifo_to_pfc_pa_last    ),
        .s_axis_rx_ready            (fifo_to_pfc_pa_ready   ),
        .m_axis_rx_tvalid           (parser_to_func_valid   ),
        .m_axis_rx_tdata            (parser_to_func_data    ),
        .m_axis_rx_tkeep            (parser_to_func_usef    ),
        .m_axis_rx_tlast            (parser_to_func_last    ),
        .m_axis_rx_Priority         (parser_to_func_Priority),
        .m_axis_rx_tready           (parser_to_func_ready   )
    );

    pfc_function #(
        .DATA_W                     (1024                   )
    )
    u4_pfc_function
    (
        .clk                        (mac_clk                ),
        .rst_n                      (~mac_rst               ),
        .rx_pfc                     (rx_pfc                 ),
        .s_axis_rx_tvalid           (parser_to_func_valid   ),
        .s_axis_rx_tdata            (parser_to_func_data    ),
        .s_axis_rx_tkeep            (parser_to_func_usef    ),
        .s_axis_rx_tlast            (parser_to_func_last    ),
        .s_axis_rx_Priority         (parser_to_func_Priority),
        .s_axis_rx_ready            (parser_to_func_ready   ),
        .m_axis_rx_tvalid           (m_h2d_axis_valid       ),
        .m_axis_rx_tdata            (m_h2d_axis_data        ),
        .m_axis_rx_tkeep            (m_h2d_axis_empty       ),
        .m_axis_rx_tlast            (m_h2d_axis_last        ),
        .m_axis_rx_tready           (m_h2d_axis_ready       ),
        .statis_cnt_clear_en        (statis_cnt_clear_en    ),
        .pfc_pkt_drop_cnt           (pfc_pkt_drop_cnt       ),
        .pfc_pkt_in_cnt             (pfc_pkt_in_cnt         ),
        .pfc_pkt_out_cnt            (pfc_pkt_out_cnt        )
    );
 
    function [1023:0] swap_endian_128;
        input [1023:0] din;
        integer i;
        reg [7:0] tmp_data;
        begin : swap_block_64
            for(i=0;i<128;i=i+1)
                swap_endian_128[(127-i)*8 +:8] = din[i*8 +:8];
        end
    endfunction

    function [511:0] swap_endian_64;
        input [511:0] din;
        integer i;
        reg [7:0] tmp_data;
        begin : swap_block_64
            for(i=0;i<64;i=i+1)
                swap_endian_64[(63-i)*8 +:8] = din[i*8 +:8];
        end
    endfunction

endmodule
`resetall