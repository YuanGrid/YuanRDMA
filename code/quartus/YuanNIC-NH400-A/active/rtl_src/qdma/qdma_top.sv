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
    // B6462（2026-11-21）：QDMA 侧的 PFC（u3_pfc_parser + u4_pfc_function）已删除，
    // 这三组计数器恒 0。端口保留是为了不改 system_config_register.v 的寄存器映射
    // （0x200 起的 48 个 32 位调试口），软件读到的值从「QDMA PFC 统计」变成全 0。
    // RDMA 侧的 PFC 不受影响：由 roce_req 的 rx_pfc 门控独立完成（见 roce_req.sv 的 tx_pfc_blocked_q），
    // 那里只按 QPC 的 TOS[7:5] 挡新 WQE 派发，不需要 PFC 队列。
    // 删除原因：8 个 2048×1024 的 M20K FIFO = 819 块 M20K（占已用内存 14%），
    // 全部挤在 eth tx_clkout|ch23（415 MHz）域内，B6460 因此负 slack −0.149（TNS −207.5）。
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
    // 末拍有效字节数（不是空字节数！名字沿用旧称 usef 极易误读，B6462 改名）。
    // 编码与 roce_tx.sv 的 frame_last_beat_bytes 一致：**0 表示满拍 128 字节**
    // （EMTY_W=7 装不下 128，全设计统一用 0 代表满拍，见 roce_tx.sv:50 的注释）。
    // 下游 qdma_top 的 m_h2d_axis_empty 端口名同样名不副实（它接的就是这个有效字节数），
    // 改端口名要动顶层连线，暂保留原名，语义以本注释为准。
    reg     [EMTY_W-1:0]                qdma_to_fifo_last_bytes;

    // B6462：原 fifo_to_pfc_pa_* / parser_to_func_* 两组中间线随 PFC 一起删除，
    // u2_tx_fifo_inst 的 m_axis_* 直接驱动模块的 m_h2d_axis_* 端口。
    // 计数器端口在下方用常量 0 驱动（保持寄存器映射不变）。
    assign pfc_pkt_drop_cnt = {8*32{1'b0}};
    assign pfc_pkt_in_cnt   = {8*32{1'b0}};
    assign pfc_pkt_out_cnt  = {8*32{1'b0}};

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
    
    // 空字节数 → 有效字节数。只在本拍是 tlast 时有意义，其余拍给 0。
    always_comb begin
        if(qdma_to_fifo_last) begin
            // 满拍（empty==0）报 0，与 roce_tx 的口径一致（0 代表 128）
            if(qdma_to_fifo_empty == 0)
                qdma_to_fifo_last_bytes = 0;
            else
                qdma_to_fifo_last_bytes = 128 - qdma_to_fifo_empty;
        end else begin
            qdma_to_fifo_last_bytes = 0;
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
        .s_axis_tuser               (qdma_to_fifo_last_bytes),
        .s_axis_pfull               (                       ),
        .s_axis_drop                (1'b0                   ),
        .m_axis_tvalid              (m_h2d_axis_valid       ),
        .m_axis_tready              (m_h2d_axis_ready       ),
        .m_axis_tdata               (m_h2d_axis_data        ),
        .m_axis_temty               (                       ),
        .m_axis_tkeep               (                       ),
        .m_axis_tlast               (m_h2d_axis_last        ),
        .m_axis_tuser               (m_h2d_axis_empty       ),
        .s_aresetn                  (~dma_rst               ),
        .s_clk                      (dma_clk                ),
        .m_clk                      (mac_clk                )
    );

    // B6462（2026-11-21）：原来的 u3_pfc_parser + u4_pfc_function 在此处被删除。
    // 原链路：u2_tx_fifo_inst → pfc_parser（按 IPv4 DSCP 分优先级）→ pfc_function
    //        （8 组 2048×1024 M20K FIFO + 优先级仲裁）→ m_h2d_axis_*。
    // 现在：u2_tx_fifo_inst（64 深 M20K）直接出到 m_h2d_axis_*。
    // 行为差异：QDMA 报文不再按 802.1p 优先级重新排队，退化为单通道先到先出；
    //   RDMA 报文不走这条路径（其 PFC 在 roce_req 内按 QP 门控），不受影响。
    // 收益：819 块 M20K（16.78 Mbit）与整条 8 优先级仲裁逻辑从 eth tx_clkout|ch23 域消失，
    //   该域 B6460 的 −0.149 setup（TNS −207.5、3380 端点）随之消除。
 
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