`resetall
`default_nettype none
`timescale 1ns / 1ps

module segm_dwidth_converter_l2h #(
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
    input   wire    [S_INFRAME_WIDTH*2-1:0]         s_segm_error,
    input   wire    [S_INFRAME_WIDTH-1:0]           s_segm_fcs_error,

    output  reg     [M_DATA_WIDTH-1:0]              m_segm_data,
    output  reg     [M_EMPTY_WIDTH-1:0]             m_segm_emty,
    output  reg     [M_INFRAME_WIDTH-1:0]           m_segm_frame,
    output  reg                                     m_segm_valid,
    output  reg     [M_INFRAME_WIDTH*2-1:0]         m_segm_error,
    output  reg     [M_INFRAME_WIDTH-1:0]           m_segm_fcs_error
);
    localparam      CLK_NUM                         = M_DATA_WIDTH/S_DATA_WIDTH;
    localparam      CLK_CNT_W                       = $clog2(CLK_NUM);
    localparam      FREAM_POS_W                     = $clog2(S_INFRAME_WIDTH);

    reg             [S_DATA_WIDTH-1:0]              s_segm_data_d1;
    reg             [S_EMPTY_WIDTH-1:0]             s_segm_emty_d1;
    reg             [S_INFRAME_WIDTH-1:0]           s_segm_frame_d1;
    reg                                             s_segm_valid_d1;
    reg             [S_INFRAME_WIDTH*2-1:0]         s_segm_error_d1;
    reg             [S_INFRAME_WIDTH-1:0]           s_segm_fcs_error_d1;

                                    

    always @(posedge clk ) begin
        s_segm_valid_d1     <= s_segm_valid     ;
        s_segm_frame_d1     <= s_segm_frame     ;
        s_segm_data_d1      <= s_segm_data      ;
        s_segm_emty_d1      <= s_segm_emty      ;
        s_segm_error_d1     <= s_segm_error     ;
        s_segm_fcs_error_d1 <= s_segm_fcs_error ;
    end

    generate
        if(S_DATA_WIDTH==M_DATA_WIDTH)begin 
            always @(posedge clk ) begin
                if(s_segm_valid_d1)begin 
                    m_segm_data     <= s_segm_data_d1     ;
                    m_segm_emty     <= s_segm_emty_d1     ;
                    m_segm_frame    <= s_segm_frame_d1    ;
                    m_segm_error    <= s_segm_error_d1    ;
                    m_segm_fcs_error<= s_segm_fcs_error_d1;
                end
            end
            
            always @(posedge clk ) begin
                if(s_segm_valid_d1)
                    m_segm_valid <= 1'b1;
                else  
                    m_segm_valid <= 1'b0;
            end
        end else begin 
            reg            [CLK_CNT_W-1:0]                  m_segm_vcnt; 
            always @(posedge clk ) begin
                if(!rst_n)
                    m_segm_vcnt <= {CLK_CNT_W{1'b0}};
                else if(s_segm_valid_d1)
                    m_segm_vcnt <= m_segm_vcnt+1'b1;
            end

            always @(posedge clk ) begin
                if(s_segm_valid_d1)begin 
                    m_segm_data     <= {s_segm_data_d1     ,m_segm_data      [M_DATA_WIDTH     -1:S_DATA_WIDTH     ]};
                    m_segm_emty     <= {s_segm_emty_d1     ,m_segm_emty      [M_EMPTY_WIDTH    -1:S_EMPTY_WIDTH    ]};
                    m_segm_frame    <= {s_segm_frame_d1    ,m_segm_frame     [M_INFRAME_WIDTH  -1:S_INFRAME_WIDTH  ]};
                    m_segm_error    <= {s_segm_error_d1    ,m_segm_error     [M_INFRAME_WIDTH*2-1:S_INFRAME_WIDTH*2]};
                    m_segm_fcs_error<= {s_segm_fcs_error_d1,m_segm_fcs_error [M_INFRAME_WIDTH  -1:S_INFRAME_WIDTH  ]};
                end
            end

            always @(posedge clk ) begin
                if(s_segm_valid_d1 & m_segm_vcnt==CLK_NUM-1)
                    m_segm_valid <= 1'b1;
                else  
                    m_segm_valid <= 1'b0;
            end
        end  
    endgenerate
    

endmodule 
`resetall
