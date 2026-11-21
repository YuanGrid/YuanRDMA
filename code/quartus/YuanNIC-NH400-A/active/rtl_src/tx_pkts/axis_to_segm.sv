`resetall
`default_nettype none
`timescale 1ns / 1ps

module axis_to_segm #(
    parameter S_DATA_WIDTH                          = 1024,
    parameter S_EMTY_WIDTH                          = (S_DATA_WIDTH/64)*3,
    parameter S_INFRAME_WIDTH                       = (S_DATA_WIDTH/64),
    parameter S_USEF_WIDTH                          = $clog2(S_DATA_WIDTH/8),
    parameter S_INFO_WIDTH                          = 32,
    parameter FLOW_NUM                              = 16384,
    parameter STREAM_ID_W                           = 14,
    parameter AXIS_NUM                              = 2
)(          
    input   wire                                    clk,
    input   wire                                    rst_n,
    input   wire    [63:0]                          time_stamp,
    input   wire    [AXIS_NUM-1:0]                  s_axis_tvalid,
    input   wire    [AXIS_NUM-1:0]                  s_axis_qdma,
    input   wire    [AXIS_NUM*S_DATA_WIDTH-1:0]     s_axis_tdata,
    input   wire    [AXIS_NUM-1:0]                  s_axis_tlast,
    input   wire    [AXIS_NUM*S_USEF_WIDTH-1:0]     s_axis_usef,
    input   wire    [AXIS_NUM*S_INFO_WIDTH-1:0]     s_axis_finfo,
    output  reg     [AXIS_NUM-1:0]                  s_axis_tready,
    input   wire                                    s_axis_pkt_stop_en,
    output  reg                                     m_segm_qdma,
    output  reg     [S_DATA_WIDTH-1:0]              m_segm_data,
    output  reg     [S_INFRAME_WIDTH*3-1:0]         m_segm_emty,
    output  reg     [S_INFRAME_WIDTH-1:0]           m_segm_frame,
    output  reg                                     m_segm_valid,
    input   wire                                    m_segm_ready,
    // 调试：[0] send_select；[1] send_select 为 1（第 1 路已恒空，这是危险态）；
    //       [2] s_axis_tready[0]；[3] m_segm_ready；[4] axis_frame_num[0] 非 0；
    //       [9:5] start_num
    output  wire    [9:0]                           debug_state
);
    reg                                             send_select;//0 send0;1 send1;2 qdma
    reg                                             send_select_d1;//0 send0;1 send1;2 qdma
    reg     [3:0]                                   start_num;
    reg     [3:0]                                   start_num_d1;
    wire                                            axis_last[AXIS_NUM-1:0];
    wire                                            axis_vld[AXIS_NUM-1:0];
    reg     [S_USEF_WIDTH-1:0]                      axis_usef[AXIS_NUM-1:0];
    reg     [S_INFO_WIDTH-1:0]                      axis_info[AXIS_NUM-1:0];
    wire    [4:0]                                   axis_frame_num[AXIS_NUM-1:0];
    reg     [4:0]                                   axis_frame_num_d1[AXIS_NUM-1:0];
    reg     [4:0]                                   axis_frame_num0_d[8:0];
    reg     [4:0]                                   axis_frame_num1_d[8:0];
    wire    [S_DATA_WIDTH-1:0]                      axis_tdata[AXIS_NUM-1:0];
    reg     [S_DATA_WIDTH-1:0]                      axis_tdata_d1[AXIS_NUM-1:0];
    reg                                             axis_last_d1[AXIS_NUM-1:0];
    reg                                             axis_vld_d1[AXIS_NUM-1:0];
    reg     [S_INFO_WIDTH-1:0]                      axis_info_d1[AXIS_NUM-1:0];
    reg     [S_USEF_WIDTH-1:0]                      axis_usef_d1[AXIS_NUM-1:0];
    reg                                             axis_qdma_d1[AXIS_NUM-1:0];
    wire                                            axis_valid_7d[AXIS_NUM-1:0];
    wire    [S_DATA_WIDTH-1:0]                      axis_data_7d[AXIS_NUM-1:0];
    wire                                            axis_last_7d[AXIS_NUM-1:0];
    reg                                             axis_valid_d8[AXIS_NUM-1:0];
    reg     [S_DATA_WIDTH-1:0]                      axis_data_d8[AXIS_NUM-1:0];
    reg                                             axis_last_d8[AXIS_NUM-1:0];
    reg                                             axis_valid_d9[AXIS_NUM-1:0];
    reg     [S_DATA_WIDTH-1:0]                      axis_data_d9[AXIS_NUM-1:0];
    reg                                             axis_last_d9[AXIS_NUM-1:0];

    reg     [8:0]                                   axis_usef0_d[8:0];
    reg     [8:0]                                   axis_usef1_d[8:0];
    reg     [8:0]                                   send_select_d;//0 send0;1 send1;2 qdma
    reg                                             wait_data_select_d9;
    reg     [S_DATA_WIDTH-1:0]                      wait_data_d9;
    reg     [S_USEF_WIDTH-1:0]                      wait_usef_d9;
    reg                                             mac_frame_continue_d8;
    reg     [3:0]                                   wait_st_num_d8;
    reg     [3:0]                                   start_num_d[7:0];
    reg     [3:0]                                   start_num_d8[15:0];
    reg     [3:0]                                   start_num_d9[15:0];
    reg     [4:0]                                   start_num0_d8[15:0];
    reg     [4:0]                                   start_num1_d8[15:0];
    reg     [4:0]                                   start_num2_d8[15:0];
    reg     [4:0]                                   data_pos_d9[15:0];
    reg     [63:0]                                  m_segm_data_wire[15:0];
    reg     [S_INFRAME_WIDTH*3-1:0]                 segm_emty;
    reg     [S_INFRAME_WIDTH-1:0]                   segm_frame;
    reg                                             segm_valid;

    generate
        for(genvar i=0 ; i<AXIS_NUM ; i=i+1)begin :stream_mark_u
            assign axis_last[i]     = s_axis_tready[i] && s_axis_tvalid[i] && s_axis_tlast[i];
            assign axis_vld[i]      = s_axis_tready[i] && s_axis_tvalid[i];
            assign axis_tdata[i]    = s_axis_tdata[i*S_DATA_WIDTH+:S_DATA_WIDTH];
            assign axis_usef[i]     = s_axis_usef[i*S_USEF_WIDTH+:S_USEF_WIDTH];
            assign axis_info[i]     = s_axis_finfo[i*S_INFO_WIDTH+:S_INFO_WIDTH];
            assign axis_frame_num[i]= s_axis_finfo[(i*S_INFO_WIDTH+18)+:5];

            always @(posedge clk ) begin 
                if(m_segm_ready)begin
                    axis_tdata_d1[i]    <= axis_tdata[i];
                    axis_last_d1[i]     <= axis_last[i];
                    axis_vld_d1[i]      <= axis_vld[i];
                    axis_usef_d1[i]     <= axis_usef[i];
                    axis_info_d1[i]     <= axis_info[i];
                    axis_frame_num_d1[i]<= axis_frame_num[i];
                    axis_qdma_d1[i]     <= s_axis_qdma[i];
                end  
            end
            stream_mark #(
                .DATA_WIDTH             (S_DATA_WIDTH               ),
                .FLOW_NUM               (FLOW_NUM                   ),
                .STREAM_ID_W            (STREAM_ID_W                ) 
            )
            u1_stream_mark
            (
                .axis_aclk              (clk                        ),
                .rst_n                  (rst_n                      ),
                .s_axis_tvalid          (axis_vld_d1    [i]         ),
                .s_axis_tdata           (axis_tdata_d1  [i]         ),
                .s_axis_tlast           (axis_last_d1   [i]         ),
                .s_axis_tusef           (axis_usef_d1   [i]         ),
                .s_axis_tuser_sop       (axis_info_d1   [i][17]     ),
                .s_axis_tuser_id        (axis_info_d1   [i][15:0]   ),
                .s_axis_tuser_stamp_en  (axis_info_d1   [i][16]     ),
                .m_axis_tvalid          (axis_valid_7d  [i]         ),
                .m_axis_tdata           (axis_data_7d   [i]         ),
                .m_axis_tlast           (axis_last_7d   [i]         ),
                .m_axis_tready          (m_segm_ready               ),
                .time_stamp             (time_stamp                 )
            );
        end  
    endgenerate 

    always @(posedge clk ) begin
        if(axis_vld[0] & axis_vld[1] & start_num + axis_frame_num[1] + axis_frame_num[0] >=5'd16)
            start_num <= start_num + axis_frame_num[0] + axis_frame_num[1];
        else if((!send_select) & axis_vld[0] & start_num + axis_frame_num[0] >=5'd16 )
            start_num <= start_num + axis_frame_num[0];
        else if(send_select & axis_vld[1]  & start_num + axis_frame_num[1] >=5'd16 )
            start_num <= start_num + axis_frame_num[1];
        else if(m_segm_ready)
            start_num <= 4'd0;
    end

    always @(posedge clk ) begin
        if(!rst_n)
            send_select <= 1'b0;
        // 追加 s_axis_tvalid[1] 门控：pkt_gen 已删除，第 1 口恒接 0 空闲。
        // 原条件只看 axis_last[0]，通道 1 无数据时也会切到它；而切回通道 0 需要
        // axis_last[1]，永远等不到，s_axis_tready[0] 就此永久为 0，TX 全卡死。
        else if((~send_select) & axis_last[0] & (!axis_last[1]) & (!s_axis_qdma[0]) & s_axis_tvalid[1])
            send_select <= 1'b1;
        else if(  send_select  & axis_last[1] & ((s_axis_qdma[0] & axis_vld[0]) || (!axis_last[0])))
            send_select <= 1'b0;
        else if(s_axis_pkt_stop_en & s_axis_tvalid==2'b01)
            send_select <= 1'b0;
        else if(s_axis_pkt_stop_en & s_axis_tvalid==2'b10)
            send_select <= 1'b1;
    end

    always @(posedge clk ) begin
        if(m_segm_ready)begin 
            send_select_d1 <= send_select;
            start_num_d1 <= start_num;
        end
    end

    assign s_axis_tready[0] = m_segm_ready & ((~send_select) || (  send_select  & axis_last[1] & axis_frame_num[1]+start_num<5'd16));
    assign s_axis_tready[1] = m_segm_ready & (( send_select) || ((~send_select) & axis_last[0] & axis_frame_num[0]+start_num<5'd16) & (!s_axis_qdma[0]));

//总线转换
    always @(posedge clk ) begin
        if(m_segm_ready)begin 
            send_select_d <= {send_select_d[7:0],send_select_d1};
            start_num_d   <= {start_num_d[6:0],start_num_d1};
            axis_frame_num0_d <= {axis_frame_num0_d[7:0],axis_frame_num_d1[0]};
            axis_frame_num1_d <= {axis_frame_num1_d[7:0],axis_frame_num_d1[1]};
            axis_usef0_d      <= {axis_usef0_d[7:0],axis_usef_d1[0]};
            axis_usef1_d      <= {axis_usef1_d[7:0],axis_usef_d1[1]};
            axis_valid_d8     <= axis_valid_7d;
            axis_valid_d9     <= axis_valid_d8;
            axis_last_d8      <= axis_last_7d;
            axis_last_d9      <= axis_last_d8;
            axis_data_d8      <= axis_data_7d;
            axis_data_d9      <= axis_data_d8;            
        end  
    end

    always @(posedge clk ) begin
        if(m_segm_ready & (!send_select_d[8]) & axis_last_d8[0] & axis_valid_d8[1] & start_num0_d8[0]<=5'd16) 
            wait_usef_d9      <= axis_usef1_d[8];
        else if(m_segm_ready & send_select_d[8] & axis_last_d8[1] & axis_valid_d8[0] & start_num1_d8[0]<=5'd16) 
            wait_usef_d9      <= axis_usef0_d[8];
        else if(m_segm_ready & (!send_select_d[8]) & axis_valid_d8[0]) 
            wait_usef_d9      <= axis_usef0_d[8];
        else if(m_segm_ready & send_select_d[8] & axis_valid_d8[1]) 
            wait_usef_d9      <= axis_usef1_d[8];
    end

    always @(posedge clk ) begin
        if(m_segm_ready & (!send_select_d[8]) & axis_last_d8[0] & axis_valid_d8[1] & start_num0_d8[0]<=5'd16)
            wait_data_select_d9    <= 1'b1;
        else if(m_segm_ready & send_select_d[8] & axis_last_d8[1] & axis_valid_d8[0] & start_num1_d8[0]<=5'd16)
            wait_data_select_d9    <= 1'b0;
        else if(m_segm_ready & (!send_select_d[8]) & axis_valid_d8[0])
            wait_data_select_d9    <= 1'b0;
        else if(m_segm_ready & send_select_d[8] & axis_valid_d8[1])
            wait_data_select_d9    <= 1'b1;

        if(m_segm_ready & wait_data_select_d9)
            wait_data_d9 <= axis_data_d9[1]; 
        else if(m_segm_ready)
            wait_data_d9 <= axis_data_d9[0]; 
    end  
//************************************************************************************/
    always @(posedge clk ) begin
        if(!rst_n)
            wait_st_num_d8 <= 4'b0;
        else if(m_segm_ready & (!send_select_d[8]) & axis_last_d8[0] & axis_valid_d8[1])
            wait_st_num_d8 <= axis_frame_num1_d[8]-start_num2_d8[1][3:0]; 
        else if(m_segm_ready & send_select_d[8] & axis_last_d8[1] & axis_valid_d8[0])
            wait_st_num_d8 <= axis_frame_num0_d[8]-start_num2_d8[1][3:0]; 
        else if(m_segm_ready & (!send_select_d[8]) & axis_valid_d8[0])
            wait_st_num_d8 <= axis_frame_num0_d[8]-start_num0_d8[1][3:0]; 
        else if(m_segm_ready & send_select_d[8] & axis_valid_d8[1])
            wait_st_num_d8 <= axis_frame_num1_d[8]-start_num1_d8[1][3:0]; 
    end

    always @(posedge clk ) begin
        if(!rst_n)
            mac_frame_continue_d8 <= 1'b0;
        else if(m_segm_ready & (!send_select_d[8]) & axis_last_d8[0] & (!axis_valid_d8[1]) & start_num0_d8[2]>5'd16)
            mac_frame_continue_d8 <= 1'b1;
        else if(m_segm_ready & send_select_d[8] & axis_last_d8[1] & (!axis_valid_d8[0]) & start_num1_d8[2]>5'd16)
            mac_frame_continue_d8 <= 1'b1;
        else if(m_segm_ready & axis_last_d8[0] & axis_last_d8[1] & start_num2_d8[2]>5'd16)
            mac_frame_continue_d8 <= 1'b1;
        else if(m_segm_ready)
            mac_frame_continue_d8 <= 1'b0;
    end

    always @(posedge clk ) begin
        if(!rst_n)
            segm_valid <= 1'b0;
        else if(m_segm_ready)
            segm_valid <= axis_valid_d8[0] | axis_valid_d8[1] | mac_frame_continue_d8;
    end

    always @(posedge clk ) begin
        if(!rst_n)
            m_segm_valid <= 1'b0;
        else if(m_segm_ready)
            m_segm_valid <= segm_valid;
    end

    generate
        for (genvar i=0 ; i<16 ; i=i+1 ) begin
            always @(posedge clk ) begin
                if(m_segm_ready)begin 
                    start_num_d8[i] <= start_num_d[7];
                    start_num_d9[i] <= start_num_d8[i];
                end  
            end

            always @(posedge clk ) begin
                if(m_segm_ready)begin 
                    start_num0_d8[i] <= start_num_d[7] + axis_frame_num0_d[7];
                    start_num1_d8[i] <= start_num_d[7] + axis_frame_num1_d[7];
                    start_num2_d8[i] <= start_num_d[7] + axis_frame_num1_d[7] + axis_frame_num0_d[7];
                end 
            end
            
            always @(posedge clk ) begin
                if(!rst_n)
                    segm_frame[i] <= 1'b0;
                else if(m_segm_ready & (!send_select_d[8]) & axis_last_d8[0] & start_num0_d8[i]<=5'd16 & i==start_num0_d8[i]-1)
                    segm_frame[i] <= 1'b0;
                else if(m_segm_ready & (!send_select_d[8]) & axis_last_d8[0] & (!axis_valid_d8[1]) & start_num0_d8[i]<=5'd16 & i>start_num0_d8[i]-1)
                    segm_frame[i] <= 1'b0;
                else if(m_segm_ready & send_select_d[8] & axis_last_d8[1] & start_num1_d8[i]<=5'd16 & i==start_num1_d8[i]-1)
                    segm_frame[i] <= 1'b0;
                else if(m_segm_ready & send_select_d[8] & axis_last_d8[1] & (!axis_valid_d8[0]) & start_num1_d8[i]<=5'd16 & i>start_num1_d8[i]-1)
                    segm_frame[i] <= 1'b0;
                else if(m_segm_ready & axis_last_d8[0] & axis_last_d8[1] & start_num2_d8[i]<=5'd16 & i>=start_num2_d8[i]-1)
                    segm_frame[i] <= 1'b0;
                else if(m_segm_ready & mac_frame_continue_d8 & (axis_valid_d8[0] | axis_valid_d8[1]) & i+1==start_num_d8[i])
                    segm_frame[i] <= 1'b0;
                else if(m_segm_ready & mac_frame_continue_d8 & (!axis_valid_d8[0]) & (!axis_valid_d8[1]) & i+1<start_num_d8[i])
                    segm_frame[i] <= 1'b1;
                else if(m_segm_ready & (((!send_select_d[8]) & axis_valid_d8[0]) || (send_select_d[8] & axis_valid_d8[1])))
                    segm_frame[i] <= 1'b1;
                else if(m_segm_ready)
                    segm_frame[i] <= 1'b0;
            end

            always @(posedge clk ) begin
                if(!rst_n)
                    segm_emty[i*3+:3] <= 3'd0;
                else if(m_segm_ready & (!send_select_d[8]) & axis_last_d8[0] & start_num0_d8[i]<=5'd16 & i==start_num0_d8[i]-1)
                    segm_emty[i*3+:3] <= 3'(4'd8-axis_usef0_d[8]);
                else if(m_segm_ready & (!send_select_d[8]) & axis_last_d8[0] & axis_last_d8[1] & start_num2_d8[i]<=5'd16 & i==start_num2_d8[i]-1)
                    segm_emty[i*3+:3] <= 3'(4'd8-axis_usef1_d[8]);
                else if(m_segm_ready & send_select_d[8] & axis_last_d8[1] & start_num1_d8[i]<=5'd16 & i==start_num1_d8[i]-1)
                    segm_emty[i*3+:3] <= 3'(4'd8-axis_usef1_d[8]);
                else if(m_segm_ready & send_select_d[8] & axis_last_d8[0] & axis_last_d8[1] & start_num2_d8[i]<=5'd16 & i==start_num2_d8[i]-1)
                    segm_emty[i*3+:3] <= 3'(4'd8-axis_usef0_d[8]);
                else if(m_segm_ready & mac_frame_continue_d8 & i+1==start_num_d8[i])
                    segm_emty[i*3+:3] <= 3'(4'd8-wait_usef_d9);
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
                if(m_segm_ready & i<start_num_d8[i])
                    data_pos_d9[i] <= {1'b0,4'(wait_st_num_d8+i)};
                else if(m_segm_ready & (!send_select_d[8]) & axis_last_d8[0] & axis_valid_d8[1] & i>=start_num0_d8[i])
                    data_pos_d9[i] <= {1'b1,4'((i-start_num0_d8[i]))};
                else if(m_segm_ready & send_select_d[8] & axis_last_d8[1] & axis_valid_d8[0] & i>=start_num1_d8[i])
                    data_pos_d9[i] <= {1'b0,4'((i-start_num1_d8[i]))};
                else if(m_segm_ready & (!send_select_d[8]) & axis_valid_d8[0] & i>=start_num_d8[i])
                    data_pos_d9[i] <= {1'b0,4'((i-start_num_d8[i]))};
                else if(m_segm_ready & send_select_d[8] & axis_valid_d8[1] & i>=start_num_d8[i])
                    data_pos_d9[i] <= {1'b1,4'((i-start_num_d8[i]))};
            end

            always @(posedge clk ) begin
                if(m_segm_ready & i<start_num_d9[i])
                    m_segm_data_wire[i] <= wait_data_d9[data_pos_d9[i][3:0]*64+:64];
                else if(m_segm_ready & data_pos_d9[i][4])
                    m_segm_data_wire[i] <= axis_data_d9[1][data_pos_d9[i][3:0]*64+:64];
                else if(m_segm_ready)
                    m_segm_data_wire[i] <= axis_data_d9[0][data_pos_d9[i][3:0]*64+:64];
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
    assign debug_state = {start_num, |axis_frame_num[0], m_segm_ready, s_axis_tready[0],
                          send_select, send_select};
endmodule 
`resetall
