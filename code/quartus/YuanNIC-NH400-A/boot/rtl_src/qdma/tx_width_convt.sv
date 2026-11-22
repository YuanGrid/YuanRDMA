`resetall
`default_nettype none
`timescale 1ns / 1ps

module tx_width_convt #(
    parameter       DATA_WIDTH                  = 512,
    parameter       ST_EMTY_WIDTH               = $clog2(DATA_WIDTH/8),// EOP空字节计数位宽
    parameter       CHANNEL_WIDTH               = 11        // 信道号位宽
) // EOP空字节计数位宽
(
    input   wire    [DATA_WIDTH-1:0]            s_avst_data,
    input   wire    [ST_EMTY_WIDTH-1:0]         s_avst_emty,
    input   wire    [CHANNEL_WIDTH-1:0]         s_avst_channel,
    input   wire                                s_avst_valid,
    input   wire                                s_avst_eof,
    input   wire                                s_avst_sof,
    output  wire                                s_avst_ready,
    output  wire    [2*DATA_WIDTH-1:0]          m_axis_tx_data,
    output  wire    [ST_EMTY_WIDTH:0]           m_axis_tx_usef,
    output  wire                                m_axis_tx_last,
    output  reg                                 m_axis_tx_valid,
    input   wire                                m_axis_tx_ready,
    input   wire    						    dma_clk,
    input   wire    						    dma_rst,
    input   wire    						    mac_tx_clk,
    input   wire    						    mac_tx_rst
);
    localparam FIFO_REAL_W = DATA_WIDTH*2 + ST_EMTY_WIDTH+1 + 1;

    reg     [2*DATA_WIDTH-1:0] 	                s_axis_tdata_i		;
    reg     [ST_EMTY_WIDTH:0]                   s_axis_temty_i		;
    reg                        	                s_axis_tvalid_i	    ;
    reg                        	                s_axis_tlast_i		;
    reg                                         s_axis_cnt			;
    wire                                        data_fifo_wen       ;
    wire    [FIFO_REAL_W-1:0]                   data_fifo_wdata     ;
    wire                                        data_fifo_pfull     ;
    wire                                        data_fifo_ren       ;
    wire    [FIFO_REAL_W-1:0]                   data_fifo_rdata     ;
    wire                                        data_fifo_empty     ;

    assign s_avst_ready = ~data_fifo_pfull;

    always @(posedge dma_clk ) begin
        if(dma_rst)
            s_axis_cnt <= 1'b0;
        else if(s_avst_valid & s_avst_eof)
            s_axis_cnt <= 1'b0;
        else if(s_avst_valid)
            s_axis_cnt <= ~s_axis_cnt;
    end

    always @(posedge dma_clk) begin
        if(dma_rst)
            s_axis_tvalid_i <= 1'b0;
        else if(s_avst_valid & (s_axis_cnt | s_avst_eof))
            s_axis_tvalid_i <= 1'b1;
        else if(s_axis_tvalid_i)
            s_axis_tvalid_i <= 1'b0;
    end

    always @(posedge dma_clk ) begin
        if(s_avst_valid & (!s_axis_cnt))
            s_axis_tdata_i[0+:DATA_WIDTH] 				<= swap_endian_64(s_avst_data);

        if(dma_rst)
            s_axis_tdata_i[DATA_WIDTH+:DATA_WIDTH]      <= 512'b0;
        else if(s_avst_valid & (s_axis_cnt | s_avst_sof))
            s_axis_tdata_i[DATA_WIDTH+:DATA_WIDTH] 		<= swap_endian_64(s_avst_data);
    end

    always @(posedge dma_clk ) begin
        if(s_avst_valid & s_avst_eof)
            s_axis_temty_i[0+:ST_EMTY_WIDTH+1] <= 8'd128-s_avst_emty-((~s_axis_cnt)<<6);
        else if(s_avst_valid)
            s_axis_temty_i[0+:ST_EMTY_WIDTH+1] <= 0;
    end

    always @(posedge dma_clk) begin
        if(dma_rst)
            s_axis_tlast_i <= 1'b0;
        else if(s_avst_valid & s_avst_eof)
            s_axis_tlast_i <= 1'b1;
        else if(s_axis_tvalid_i & s_axis_tlast_i)
            s_axis_tlast_i <= 1'b0;
    end
    assign data_fifo_wen   = s_axis_tvalid_i;
    assign data_fifo_wdata = {s_axis_tlast_i,s_axis_temty_i,s_axis_tdata_i};

    /******************************************mac clk*********************************************/
    assign data_fifo_ren = m_axis_tx_valid ? m_axis_tx_ready & (~data_fifo_empty) : (~data_fifo_empty);

    always @(posedge mac_tx_clk ) begin
        if(dma_rst)
            m_axis_tx_valid <= 1'b0;
        else if(data_fifo_ren)
            m_axis_tx_valid <= 1'b1;
        else if(m_axis_tx_valid & m_axis_tx_ready & m_axis_tx_last)
            m_axis_tx_valid <= 1'b0;
    end

    assign m_axis_tx_last = data_fifo_rdata[FIFO_REAL_W-1];
    assign m_axis_tx_usef = data_fifo_rdata[DATA_WIDTH*2+:ST_EMTY_WIDTH+1];
    assign m_axis_tx_data = data_fifo_rdata[DATA_WIDTH*2-1:0];

/******************************模块例化************************************************/

    dfifo #(
        .FIFO_TYPE                          ("M20K"             ),
        .SHOWAHEAD                          ("OFF"              ),
        .PACKET_FIFO                        ("YES"              ),
        .FULLTHRESHOLD                      (500                ),
        .DEPTH                              (512                ),
        .WIDTH                              (FIFO_REAL_W        )
    )u0_data_fifo(
        .aclr                               (dma_rst            ),
        .wrclk                              (dma_clk            ),
        .wrreq                              (data_fifo_wen      ),
        .data                               (data_fifo_wdata    ),
        .wrpfull                            (data_fifo_pfull    ),
        .wrusedw                            (),
        .rdclk                              (mac_tx_clk         ),
        .rdreq                              (data_fifo_ren      ),
        .q                                  (data_fifo_rdata    ),
        .rdempty                            (data_fifo_empty    ),
        .rdusedw                            ()
    );

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