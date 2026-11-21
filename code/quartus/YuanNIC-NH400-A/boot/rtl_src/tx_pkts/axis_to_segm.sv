`resetall
`default_nettype none
`timescale 1ns / 1ps

module axis_to_segm #(
    parameter S_DATA_WIDTH                          = 1024,
    parameter S_EMTY_WIDTH                          = (S_DATA_WIDTH/64)*3,
    parameter S_INFRAME_WIDTH                       = (S_DATA_WIDTH/64),
    parameter S_USEF_WIDTH                          = $clog2(S_DATA_WIDTH/8),
    parameter AXIS_NUM                              = 2
)(          
    input   wire                                    clk,
    input   wire                                    rst_n,
    input   wire    [AXIS_NUM-1:0]                  s_axis_tvalid,
    input   wire    [AXIS_NUM-1:0]                  s_axis_qdma,
    input   wire    [AXIS_NUM*S_DATA_WIDTH-1:0]     s_axis_tdata,
    input   wire    [AXIS_NUM-1:0]                  s_axis_tlast,
    input   wire    [AXIS_NUM*S_USEF_WIDTH-1:0]     s_axis_usef,
    input   wire    [AXIS_NUM*37-1:0]               s_axis_finfo,
    output  reg     [AXIS_NUM-1:0]                  s_axis_tready,
    input   wire                                    s_axis_pkt_stop_en,
    output  reg                                     m_segm_qdma,
    output  reg     [S_DATA_WIDTH-1:0]              m_segm_data,
    output  reg     [S_INFRAME_WIDTH*3-1:0]         m_segm_emty,
    output  reg     [S_INFRAME_WIDTH-1:0]           m_segm_frame,
    output  reg     [41:0]                          m_segm_info,
    output  reg                                     m_segm_valid,
    input   wire                                    m_segm_ready
);
    reg                                             send_select;//0 send0;1 send1;2 qdma
    reg                                             send_select_d1;//0 send0;1 send1;2 qdma
    wire                                            axis_last[AXIS_NUM-1:0];
    wire                                            axis_vld[AXIS_NUM-1:0];
    reg     [S_USEF_WIDTH-1:0]                      axis_usef[AXIS_NUM-1:0];
    wire    [4:0]                                   axis_frame_num[AXIS_NUM-1:0];
    wire    [31:0]                                  axis_frame_gap[AXIS_NUM-1:0];
    wire    [S_DATA_WIDTH-1:0]                      axis_tdata[AXIS_NUM-1:0];
    reg     [S_DATA_WIDTH-1:0]                      axis_tdata_d1[AXIS_NUM-1:0];
    reg     [S_DATA_WIDTH-1:0]                      axis_tdata_d2[AXIS_NUM-1:0];
    reg                                             axis_last_d1[AXIS_NUM-1:0];
    reg                                             axis_vld_d1[AXIS_NUM-1:0];
    reg     [5-1:0]                                 axis_frame_num_d1[AXIS_NUM-1:0];
    reg     [32-1:0]                                axis_frame_gap_d1[AXIS_NUM-1:0];
    reg     [32-1:0]                                axis_frame_gap_d2;
    reg     [S_USEF_WIDTH-1:0]                      axis_usef_d1[AXIS_NUM-1:0];
    reg                                             wait_data_select_d2;
    reg     [S_DATA_WIDTH-1:0]                      wait_data_d2;
    reg     [S_USEF_WIDTH-1:0]                      wait_usef_d1;
    reg                                             mac_frame_continue_d1;
    reg     [3:0]                                   wait_st_num_d1;
    reg     [3:0]                                   start_num[15:0];
    reg     [3:0]                                   start_num_d1[15:0];
    reg     [3:0]                                   start_num_d2[15:0];
    reg     [4:0]                                   start_num0_d1[15:0];
    reg     [4:0]                                   start_num1_d1[15:0];
    reg     [4:0]                                   start_num2_d1[15:0];
    reg     [4:0]                                   data_pos_d2[15:0];
    reg     [63:0]                                  m_segm_data_wire[15:0];
    reg     [S_INFRAME_WIDTH*3-1:0]                 segm_emty ;
    reg     [S_INFRAME_WIDTH-1:0]                   segm_frame;
    reg                                             segm_valid;

    generate
        for(genvar i=0 ; i<AXIS_NUM ; i=i+1)begin 
            assign axis_last[i]     = s_axis_tready[i] && s_axis_tvalid[i] && s_axis_tlast[i];
            assign axis_vld[i]      = s_axis_tready[i] && s_axis_tvalid[i];
            assign axis_tdata[i]    = s_axis_tdata[i*S_DATA_WIDTH+:S_DATA_WIDTH];
            assign axis_usef[i]     = s_axis_usef[i*S_USEF_WIDTH+:S_USEF_WIDTH];
            assign axis_frame_num[i]= s_axis_finfo[(i*37+32)+:5];
            assign axis_frame_gap[i]= s_axis_finfo[i*37+:32];
            always @(posedge clk ) begin
                if(m_segm_ready)begin
                    axis_tdata_d1[i]    <= axis_tdata[i];
                    axis_tdata_d2[i]    <= axis_tdata_d1[i];
                    axis_last_d1[i]     <= axis_last[i];
                    axis_vld_d1[i]      <= axis_vld[i];
                    axis_frame_num_d1[i]<= axis_frame_num[i];
                    axis_frame_gap_d1[i]<= axis_frame_gap[i];
                    axis_usef_d1[i]     <= axis_usef[i];
                end 
            end
        end  
    endgenerate 

    always @(posedge clk ) begin
        if(!rst_n)
            axis_frame_gap_d2 <= 32'b0;
        else if(m_segm_ready & axis_last_d1[0] & axis_last_d1[1])
            axis_frame_gap_d2 <= axis_frame_gap_d1[0] + axis_frame_gap_d1[1];
        else if(m_segm_ready & axis_last_d1[0])
            axis_frame_gap_d2 <= axis_frame_gap_d1[0];
        else if(m_segm_ready & axis_last_d1[1])
            axis_frame_gap_d2 <= axis_frame_gap_d1[1];
    end
    
    always @(posedge clk ) begin
        if(!rst_n)
            send_select <= 1'b0;
        else if((~send_select) & axis_last[0] & (!axis_last[1]) & (!s_axis_qdma[0]))
            send_select <= 1'b1;
        else if(  send_select  & axis_last[1] & ((s_axis_qdma[0] & axis_vld[0]) || (!axis_last[0])))
            send_select <= 1'b0;
        else if(s_axis_pkt_stop_en & s_axis_tvalid==2'b01)
            send_select <= 1'b0;
        else if(s_axis_pkt_stop_en & s_axis_tvalid==2'b10)
            send_select <= 1'b1;

        if(!rst_n)
            send_select_d1 <= 1'b0;
        else if(m_segm_ready)
            send_select_d1 <= send_select;
    end

    assign s_axis_tready[0] = m_segm_ready & ((~send_select) || (  send_select  & axis_last[1] & axis_frame_num[1]+start_num[0]<5'd16));
    assign s_axis_tready[1] = m_segm_ready & (( send_select) || ((~send_select) & axis_last[0] & axis_frame_num[0]+start_num[1]<5'd16) & (!s_axis_qdma[0]));

    always @(posedge clk ) begin
        if(m_segm_ready & (!send_select_d1) & axis_last_d1[0] & axis_vld_d1[1] & start_num0_d1[0]<=5'd16) 
            wait_usef_d1      <= axis_usef_d1[1];
        else if(m_segm_ready & send_select_d1 & axis_last_d1[1] & axis_vld_d1[0] & start_num1_d1[0]<=5'd16) 
            wait_usef_d1      <= axis_usef_d1[0];
        else if(m_segm_ready & (!send_select_d1) & axis_vld_d1[0]) 
            wait_usef_d1      <= axis_usef_d1[0];
        else if(m_segm_ready & send_select_d1 & axis_vld_d1[1]) 
            wait_usef_d1      <= axis_usef_d1[1];
    end

    always @(posedge clk ) begin
        if(m_segm_ready & (!send_select_d1) & axis_last_d1[0] & axis_vld_d1[1] & start_num0_d1[0]<=5'd16)
            wait_data_select_d2    <= 1'b1;
        else if(m_segm_ready & send_select_d1 & axis_last_d1[1] & axis_vld_d1[0] & start_num1_d1[0]<=5'd16)
            wait_data_select_d2    <= 1'b0;
        else if(m_segm_ready & (!send_select_d1) & axis_vld_d1[0])
            wait_data_select_d2    <= 1'b0;
        else if(m_segm_ready & send_select_d1 & axis_vld_d1[1])
            wait_data_select_d2    <= 1'b1;

        if(m_segm_ready & wait_data_select_d2)
            wait_data_d2 <= axis_tdata_d2[1]; 
        else if(m_segm_ready)
            wait_data_d2 <= axis_tdata_d2[0]; 
    end  
//************************************************************************************/
    

    always @(posedge clk ) begin
        if(!rst_n)
            wait_st_num_d1 <= 4'b0;
        else if(m_segm_ready & (!send_select_d1) & axis_last_d1[0] & axis_vld_d1[1])
            wait_st_num_d1 <= axis_frame_num_d1[1]-start_num2_d1[1][3:0]; 
        else if(m_segm_ready & send_select_d1 & axis_last_d1[1] & axis_vld_d1[0])
            wait_st_num_d1 <= axis_frame_num_d1[0]-start_num2_d1[1][3:0]; 
        else if(m_segm_ready & (!send_select_d1) & axis_vld_d1[0])
            wait_st_num_d1 <= axis_frame_num_d1[0]-start_num0_d1[1][3:0]; 
        else if(m_segm_ready & send_select_d1 & axis_vld_d1[1])
            wait_st_num_d1 <= axis_frame_num_d1[1]-start_num1_d1[1][3:0]; 
    end

    always @(posedge clk ) begin
        if(!rst_n)
            mac_frame_continue_d1 <= 1'b0;
        else if(m_segm_ready & (!send_select_d1) & axis_last_d1[0] & (!axis_vld_d1[1]) & start_num0_d1[2]>5'd16)
            mac_frame_continue_d1 <= 1'b1;
        else if(m_segm_ready & send_select_d1 & axis_last_d1[1] & (!axis_vld_d1[0]) & start_num1_d1[2]>5'd16)
            mac_frame_continue_d1 <= 1'b1;
        else if(m_segm_ready & axis_last_d1[0] & axis_last_d1[1] & start_num2_d1[2]>5'd16)
            mac_frame_continue_d1 <= 1'b1;
        else if(m_segm_ready)
            mac_frame_continue_d1 <= 1'b0;
    end

    always @(posedge clk ) begin
        if(!rst_n)begin 
            segm_valid      <= 1'b0;
            m_segm_valid    <= 1'b0;
            m_segm_info     <= 41'd0;
        end else if(m_segm_ready)begin 
            segm_valid      <= axis_vld_d1[0] | axis_vld_d1[1] | mac_frame_continue_d1;
            m_segm_valid    <= segm_valid;
            m_segm_info     <= {eop2_bit_pos({segm_frame,m_segm_frame[15]}),2'b0,eop_num({segm_frame,m_segm_frame[15]}),axis_frame_gap_d2};
        end  
    end

    generate
        for (genvar i=0 ; i<16 ; i=i+1 ) begin
            always @(posedge clk ) begin
                if(axis_vld[0] & axis_vld[1] & start_num[i] + axis_frame_num[1] + axis_frame_num[0] >=5'd16)
                    start_num[i] <= start_num[i] + axis_frame_num[0] + axis_frame_num[1];
                else if((!send_select) & axis_vld[0] & start_num[i] + axis_frame_num[0] >=5'd16 )
                    start_num[i] <= start_num[i] + axis_frame_num[0];
                else if(send_select & axis_vld[1]  & start_num[i] + axis_frame_num[1] >=5'd16 )
                    start_num[i] <= start_num[i] + axis_frame_num[1];
                else if(m_segm_ready)
                    start_num[i] <= 4'd0;
                
                if(m_segm_ready)begin 
                    start_num_d1[i] <= start_num[i];
                    start_num_d2[i] <= start_num_d1[i];
                end  
            end

            always @(posedge clk ) begin
                if(m_segm_ready)begin 
                    start_num0_d1[i] <= start_num[i] + axis_frame_num[0];
                    start_num1_d1[i] <= start_num[i] + axis_frame_num[1];
                    start_num2_d1[i] <= start_num[i] + axis_frame_num[1] + axis_frame_num[0];
                end 
            end
            
            always @(posedge clk ) begin
                if(!rst_n)
                    segm_frame[i] <= 1'b0;
                else if(m_segm_ready & (!send_select_d1) & axis_last_d1[0] & start_num0_d1[i]<=5'd16 & i==start_num0_d1[i]-1)
                    segm_frame[i] <= 1'b0;
                else if(m_segm_ready & (!send_select_d1) & axis_last_d1[0] & (!axis_vld_d1[1]) & start_num0_d1[i]<=5'd16 & i>start_num0_d1[i]-1)
                    segm_frame[i] <= 1'b0;
                else if(m_segm_ready & send_select_d1 & axis_last_d1[1] & start_num1_d1[i]<=5'd16 & i==start_num1_d1[i]-1)
                    segm_frame[i] <= 1'b0;
                else if(m_segm_ready & send_select_d1 & axis_last_d1[1] & (!axis_vld_d1[0]) & start_num1_d1[i]<=5'd16 & i>start_num1_d1[i]-1)
                    segm_frame[i] <= 1'b0;
                else if(m_segm_ready & axis_last_d1[0] & axis_last_d1[1] & start_num2_d1[i]<=5'd16 & i>=start_num2_d1[i]-1)
                    segm_frame[i] <= 1'b0;
                else if(m_segm_ready & mac_frame_continue_d1 & (axis_vld_d1[0] | axis_vld_d1[1]) & i+1==start_num_d1[i])
                    segm_frame[i] <= 1'b0;
                else if(m_segm_ready & mac_frame_continue_d1 & (!axis_vld_d1[0]) & (!axis_vld_d1[1]) & i+1<start_num_d1[i])
                    segm_frame[i] <= 1'b1;
                else if(m_segm_ready & (((!send_select_d1) & axis_vld_d1[0]) || (send_select_d1 & axis_vld_d1[1])))
                    segm_frame[i] <= 1'b1;
                else if(m_segm_ready)
                    segm_frame[i] <= 1'b0;
            end

            always @(posedge clk ) begin
                if(!rst_n)
                    segm_emty[i*3+:3] <= 3'd0;
                else if(m_segm_ready & (!send_select_d1) & axis_last_d1[0] & start_num0_d1[i]<=5'd16 & i==start_num0_d1[i]-1)
                    segm_emty[i*3+:3] <= 3'(4'd8-axis_usef_d1[0]);
                else if(m_segm_ready & (!send_select_d1) & axis_last_d1[0] & axis_last_d1[1] & start_num2_d1[i]<=5'd16 & i==start_num2_d1[i]-1)
                    segm_emty[i*3+:3] <= 3'(4'd8-axis_usef_d1[1]);
                else if(m_segm_ready & send_select_d1 & axis_last_d1[1] & start_num1_d1[i]<=5'd16 & i==start_num1_d1[i]-1)
                    segm_emty[i*3+:3] <= 3'(4'd8-axis_usef_d1[1]);
                else if(m_segm_ready & send_select_d1 & axis_last_d1[0] & axis_last_d1[1] & start_num2_d1[i]<=5'd16 & i==start_num2_d1[i]-1)
                    segm_emty[i*3+:3] <= 3'(4'd8-axis_usef_d1[0]);
                else if(m_segm_ready & mac_frame_continue_d1 & i+1==start_num_d1[i])
                    segm_emty[i*3+:3] <= 3'(4'd8-wait_usef_d1);
                else if(m_segm_ready)
                    segm_emty[i*3+:3] <= 3'd0;
            end

            always @(posedge clk ) begin
                if(!rst_n)begin 
                    m_segm_emty[i*3+:3] <= 3'b0;
                    m_segm_frame[i]     <= 1'b0;
                end else if(m_segm_ready)begin 
                    m_segm_emty[i*3+:3] <= segm_emty[i*3+:3];
                    m_segm_frame[i]     <= segm_frame[i] & segm_valid;
                end
            end
 
            always @(posedge clk ) begin
                if(m_segm_ready & i<start_num_d1[i])
                    data_pos_d2[i] <= {1'b0,4'(wait_st_num_d1+i)};
                else if(m_segm_ready & (!send_select_d1) & axis_last_d1[0] & axis_vld_d1[1] & i>=start_num0_d1[i])
                    data_pos_d2[i] <= {1'b1,4'((i-start_num0_d1[i]))};
                else if(m_segm_ready & send_select_d1 & axis_last_d1[1] & axis_vld_d1[0] & i>=start_num1_d1[i])
                    data_pos_d2[i] <= {1'b0,4'((i-start_num1_d1[i]))};
                else if(m_segm_ready & (!send_select_d1) & axis_vld_d1[0] & i>=start_num_d1[i])
                    data_pos_d2[i] <= {1'b0,4'((i-start_num_d1[i]))};
                else if(m_segm_ready & send_select_d1 & axis_vld_d1[1] & i>=start_num_d1[i])
                    data_pos_d2[i] <= {1'b1,4'((i-start_num_d1[i]))};
            end

            always @(posedge clk ) begin
                if(m_segm_ready & i<start_num_d2[i])
                    m_segm_data_wire[i] <= wait_data_d2[data_pos_d2[i][3:0]*64+:64];
                else if(m_segm_ready & data_pos_d2[i][4])
                    m_segm_data_wire[i] <= axis_tdata_d2[1][data_pos_d2[i][3:0]*64+:64];
                else if(m_segm_ready)
                    m_segm_data_wire[i] <= axis_tdata_d2[0][data_pos_d2[i][3:0]*64+:64];
            end

            assign m_segm_data[i*64+:64] = m_segm_data_wire[i];
        end
    endgenerate

    function [1:0] eop_num;
        input [16:0] frame;
        integer i;
        begin : swap
            eop_num = 0 ;
            for (i=0;i<16;i=i+1)begin
                if(frame[i] && ~frame[i+1]) 
                    eop_num = eop_num + 1;
            end  
        end
    endfunction

    function [3:0] eop2_bit_pos;
        input [16:0] frame;
        integer i;
        begin : swap
            eop2_bit_pos = 0;
            for (i=0;i<16;i=i+1)begin
                if(frame[i] && ~frame[i+1])
                    eop2_bit_pos = i;
            end  
        end
    endfunction
endmodule 
`resetall
