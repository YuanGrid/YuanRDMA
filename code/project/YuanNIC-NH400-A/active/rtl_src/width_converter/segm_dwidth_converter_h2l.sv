`resetall
`default_nettype none
`timescale 1ns / 1ps

module segm_dwidth_converter_h2l #(
    parameter S_DATA_WIDTH                          = 1024,
    parameter S_INFRAME_WIDTH                       = (S_DATA_WIDTH/64),
    parameter S_EMPTY_WIDTH                         = S_INFRAME_WIDTH*3,
    parameter M_DATA_WIDTH                          = 1024,
    parameter M_INFRAME_WIDTH                       = (M_DATA_WIDTH/64),
    parameter M_EMPTY_WIDTH                         = M_INFRAME_WIDTH*3
)(          
    input   wire                                    clk,
    input   wire                                    rst_n,
    input   wire    [S_DATA_WIDTH-1:0]              s_segm_data,
    input   wire    [S_EMPTY_WIDTH-1:0]             s_segm_emty,
    input   wire    [S_INFRAME_WIDTH-1:0]           s_segm_frame,
    input   wire                                    s_segm_valid,
    output  wire                                    s_segm_ready,

    output  reg     [M_DATA_WIDTH-1:0]              m_segm_data,
    output  reg     [M_EMPTY_WIDTH-1:0]             m_segm_emty,
    output  reg     [M_INFRAME_WIDTH-1:0]           m_segm_frame,
    output  reg                                     m_segm_valid,
    input   wire                                    m_segm_ready
);
    localparam      CLK_NUM                         = S_DATA_WIDTH/M_DATA_WIDTH;

    reg            [S_DATA_WIDTH-1:0]               s_segm_data_reg;
    reg            [S_EMPTY_WIDTH-1:0]              s_segm_emty_reg;
    reg            [S_INFRAME_WIDTH-1:0]            s_segm_frame_reg;

    wire                                            m_segm_vcnt0;                                 
    reg            [CLK_NUM-1:0]                    m_segm_vcnt;                                 

    assign s_segm_ready = m_segm_ready & (m_segm_vcnt[CLK_NUM-1] | m_segm_vcnt==0);

    always @(posedge clk ) begin
        if(!rst_n)begin
            s_segm_emty_reg  <= {S_EMPTY_WIDTH{1'b0}};
            s_segm_frame_reg <= {S_INFRAME_WIDTH{1'b0}};
        end else if(s_segm_ready & s_segm_valid)begin 
            s_segm_data_reg  <= s_segm_data;
            s_segm_emty_reg  <= s_segm_emty;
            s_segm_frame_reg <= s_segm_frame;
        end else if (m_segm_ready & S_DATA_WIDTH==M_DATA_WIDTH)begin 
            s_segm_data_reg  <= {S_DATA_WIDTH   {1'b0}};
            s_segm_emty_reg  <= {S_EMPTY_WIDTH  {1'b0}};
            s_segm_frame_reg <= {S_INFRAME_WIDTH{1'b0}};
        end else if(m_segm_ready & S_DATA_WIDTH>M_DATA_WIDTH) begin 
            s_segm_data_reg  <= {{M_DATA_WIDTH   {1'b0}},s_segm_data_reg [S_DATA_WIDTH   -1:M_DATA_WIDTH   ]};
            s_segm_emty_reg  <= {{M_EMPTY_WIDTH  {1'b0}},s_segm_emty_reg [S_EMPTY_WIDTH  -1:M_EMPTY_WIDTH  ]};
            s_segm_frame_reg <= {{M_INFRAME_WIDTH{1'b0}},s_segm_frame_reg[S_INFRAME_WIDTH-1:M_INFRAME_WIDTH]};
        end
    end

    assign m_segm_vcnt0 = s_segm_ready & s_segm_valid;

    generate
        if(CLK_NUM==1)begin 
            always @(posedge clk ) begin
                m_segm_vcnt[0] <= m_segm_vcnt0;
            end
        end else if(CLK_NUM>1)begin 
            for (genvar i=1 ; i<CLK_NUM ; i=i+1) begin
                always @(posedge clk ) begin
                    if(m_segm_ready)
                        m_segm_vcnt[CLK_NUM-1:0] <= {m_segm_vcnt[CLK_NUM-2:0],m_segm_vcnt0};
                end
            end
        end  
    endgenerate

    always @(posedge clk ) begin
        m_segm_valid <= m_segm_ready;

        if(m_segm_ready)begin 
            m_segm_data  <= s_segm_data_reg[M_DATA_WIDTH-1:0];
            m_segm_emty  <= s_segm_emty_reg[M_EMPTY_WIDTH-1:0];
            m_segm_frame <= s_segm_frame_reg[M_INFRAME_WIDTH-1:0];
        end 
    end

endmodule 
`resetall
