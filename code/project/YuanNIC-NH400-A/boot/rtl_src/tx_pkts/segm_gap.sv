`resetall
`default_nettype none
`timescale 1ns / 1ps

module segm_gap #(
    parameter S_DATA_WIDTH                          = 1024,
    parameter S_EMTY_WIDTH                          = (S_DATA_WIDTH/64)*3,
    parameter S_INFRAME_WIDTH                       = (S_DATA_WIDTH/64)
)(          
    input   wire                                    clk,
    input   wire                                    rst_n,
    input   wire    [S_DATA_WIDTH-1:0]              s_gap_data,
    input   wire    [S_INFRAME_WIDTH*3-1:0]         s_gap_emty,
    input   wire    [S_INFRAME_WIDTH-1:0]           s_gap_frame,
    input   wire    [31:0]                          s_gap_gap,
    input   wire    [2-1:0]                         s_gap_eop_num,
    input   wire    [4-1:0]                         s_gap_eop_pos,
    input   wire                                    s_gap_valid,
    output  wire                                    s_gap_ready,

    output  reg     [S_DATA_WIDTH-1:0]              m_gap_data,
    output  reg     [S_INFRAME_WIDTH*3-1:0]         m_gap_emty,
    output  reg     [S_INFRAME_WIDTH-1:0]           m_gap_frame,
    output  reg                                     m_gap_valid,
    input   wire                                    m_gap_ready
);
    reg     [S_DATA_WIDTH-1:0]                      gap_data_d[2:0];
    reg     [S_INFRAME_WIDTH*3-1:0]                 gap_emty_d[2:0];
    reg     [S_INFRAME_WIDTH-1:0]                   gap_frame_d[2:0];
    reg                                             gap_valid_d[2:0];
    reg                                             gap_gap_d[2:0];
    wire                                            fram_vld;
    reg     [1:0]                                   eop_num_d[2:0];
    wire                                            eop_vld_d1;
    reg     [1:0]                                   eop_num_d1_reg;
    reg     [4:0]                                   eop_pos_d[2:0];
    reg     [31:0]                                  gapa_cfg_d0;
    reg     [31:0]                                  gapb_cfg_d0;
    reg     [31:0]                                  gap_cfg_d1;
    wire                                            gap_cfg_d1_vld;
    reg     [15:0]                                  gap_loop_cnt_d0;
    reg     [27:0]                                  wait_cnt_d;
    reg                                             wait_vld_d[3:2];
    wire    [15:0]                                  num_gap;
    reg     [31:0]                                  gap_sum_d[3:2];

    assign s_gap_ready = m_gap_ready & (~wait_vld_d[2]);
    //assign s_gap_ready = m_gap_ready;
    assign fram_vld = s_gap_ready & s_gap_valid;
    always @(posedge clk ) begin
        if(!rst_n)begin 
            gap_frame_d[0]   <= 16'b0;
            gap_frame_d[1]   <= 16'b0;
            gap_frame_d[2]   <= 16'b0;
        end  
        else if(s_gap_ready)begin 
            gap_data_d[2:0]  <= {gap_data_d[1:0],s_gap_data};
            gap_emty_d[2:0]  <= {gap_emty_d[1:0],s_gap_emty};
            gap_frame_d[2:0] <= {gap_frame_d[1:0],s_gap_frame&{S_INFRAME_WIDTH{s_gap_valid}}};
            eop_num_d[2:0]   <= {eop_num_d[1:0],s_gap_eop_num};
            eop_pos_d[2:0]   <= {eop_pos_d[1:0],s_gap_eop_pos};
            gap_gap_d[2:0]   <= {gap_gap_d[1:0],s_gap_gap};
            gap_valid_d[2:0] <= {gap_valid_d[1:0],fram_vld};
        end  
        
    end

    always @(posedge clk ) begin
        if(!rst_n)
            gap_sum_d[2]  <= 32'b0;
        else if(m_gap_ready & wait_vld_d[2] & wait_cnt_d+1'b1==gap_sum_d[2][31:4])begin 
            gap_sum_d[2][31:4]  <= 28'b0;
        end else if(s_gap_ready & eop_num_d[1] != 0) 
            gap_sum_d[2]  <= gap_sum_d[2] + gap_gap_d[1];

        if(m_gap_ready)
            gap_sum_d[3] <= gap_sum_d[2];
    end

    always @(posedge clk) begin
        if(!rst_n)
            wait_vld_d[2] <= 1'b0;
        else if(m_gap_ready & wait_vld_d[2] & wait_cnt_d+1'd1==gap_sum_d[2][31:4])
            wait_vld_d[2] <= 1'b0;
        else if(m_gap_ready & gap_sum_d[2] + gap_cfg_d1 >= 32'd16)
            wait_vld_d[2] <= 1'b1;

        if(m_gap_ready)
            wait_vld_d[3] <= wait_vld_d[2];
    end

    always @(posedge clk ) begin
        if(!rst_n)
            wait_cnt_d <= 28'd0;
        else if(m_gap_ready & wait_vld_d[2])
            wait_cnt_d <= wait_cnt_d + 1'd1;
        else if(m_gap_ready & wait_vld_d[3] & wait_cnt_d==gap_sum_d[3][31:4])
            wait_cnt_d <= 28'd0;
    end

    always @(posedge clk ) begin
        m_gap_valid <= m_gap_ready;
    end

    generate
        for (genvar i=0 ; i<16 ; i=i+1) begin
            always @(posedge clk ) begin
                if(!rst_n)
                    m_gap_frame[i] <= 1'b0;
                else if(wait_vld_d[2] & wait_cnt_d==28'd0 & i<=eop_pos_d[2])
                    m_gap_frame[i] <= gap_frame_d[2][i];
                else if(wait_vld_d[3] & wait_cnt_d==gap_sum_d[3][31:4] & i>eop_pos_d[2])
                    m_gap_frame[i] <= gap_frame_d[2][i];
                else if(wait_vld_d[2] | wait_vld_d[3])
                    m_gap_frame[i] <= 1'b0;
                else if(m_gap_ready)
                    m_gap_frame[i] <= gap_frame_d[2][i];
            end

            always @(posedge clk ) begin
                if(m_gap_ready)begin 
                    m_gap_data[i*64+:64] <= gap_data_d[2][i*64+:64];
                    m_gap_emty[i*3+:3]   <= gap_emty_d[2][i*3+:3];
                end 
            end
        end
    endgenerate
endmodule 
`resetall
