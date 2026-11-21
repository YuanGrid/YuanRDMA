`resetall
`default_nettype none
`timescale 1ns / 1ps

module data_concat #(
    parameter S_DATA_WIDTH              = 1024,
    parameter S_INFRAME_WIDTH           = S_DATA_WIDTH/64,
    parameter S_SE_POS_EIDTH            = $clog2(S_INFRAME_WIDTH), 
    parameter M_DATA_WIDTH              = S_DATA_WIDTH/S_INFRAME_WIDTH,
    parameter M_EMPTY_WIDTH             = $clog2(S_DATA_WIDTH/8)
)(
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire [S_DATA_WIDTH-1:0]      s_orig_data      ,
    input  wire [S_INFRAME_WIDTH*3-1:0] s_orig_emty      ,
    input  wire [S_INFRAME_WIDTH-1:0]   s_orig_inframe   ,
    input  wire [S_INFRAME_WIDTH*2-1:0] s_orig_error     ,
    input  wire [S_INFRAME_WIDTH-1:0]   s_orig_fcs_error ,
    input  wire                         s_orig_valid     ,
    input  wire [1:0]                   s_sop_num       ,
    input  wire [S_SE_POS_EIDTH-1:0]    s_sop1_pos      ,
    input  wire [S_SE_POS_EIDTH-1:0]    s_sop2_pos      ,
    input  wire [1:0]                   s_eop_num       ,
    input  wire [S_SE_POS_EIDTH-1:0]    s_eop1_pos      ,
    input  wire [2:0]                   s_eop1_empty    ,
    input  wire [S_SE_POS_EIDTH-1:0]    s_eop2_pos      ,
    input  wire [2:0]                   s_eop2_empty    ,
    input  wire                         s_write_flag    ,

    output reg  [S_DATA_WIDTH-1:0]      m_axis_tdata    ,
    output reg  [$clog2(S_DATA_WIDTH/8)-1:0]m_axis_tempty,
    output reg  [2:0]                   m_axis_tuerr    ,
    output reg                          m_axis_tvalid   ,
    input  wire                         m_axis_tready   ,
    output reg                          m_axis_teop    

);

    localparam  INFO_W                  = 19;

    reg         [S_DATA_WIDTH-1:0]      s_orig_data_d[2:1];
    reg         [S_INFRAME_WIDTH*3-1:0] s_orig_emty_d[2:1];
    reg         [S_INFRAME_WIDTH*1-1:0] s_orig_inframe_d[2:1];
    reg                                 s_orig_valid_d[2:1];
    reg         [S_INFRAME_WIDTH*1-1:0] s_orig_fcs_error_d[2:1];
    reg         [S_INFRAME_WIDTH*2-1:0] s_orig_error_d[2:1];
    reg         [1:0]                   sop_num_d[2:1];
    reg         [S_SE_POS_EIDTH-1:0]    sop1_pos_d[2:1];
    reg         [S_SE_POS_EIDTH-1:0]    sop2_pos_d[2:1];
    reg         [1:0]                   eop_num_d[2:1];
    reg         [S_SE_POS_EIDTH:0]      eop1_pos_d[2:1];
    reg         [S_SE_POS_EIDTH:0]      eop2_pos_d[2:1];
    reg         [S_SE_POS_EIDTH:0]      write_num_d[1:1];
    reg         [S_SE_POS_EIDTH-1:0]    start_num_d1[15:0];
    reg         [S_SE_POS_EIDTH-1:0]    start_num_d2[15:0];
    reg                                 write_flag_d[2:1];
    reg         [S_SE_POS_EIDTH-1:0]    cur_sop_pos_d[2:1];
    reg                                 fcs_err_d1;
    reg         [7:0]                   pkt0_len[2:1];
    reg         [7:0]                   pkt1_len[2:1];
    reg         [S_SE_POS_EIDTH-1:0]    data_pos_d1[S_INFRAME_WIDTH*1-1:0];
    reg         [S_INFRAME_WIDTH*1-1:0] data_fifo_wen[3:2];
    reg         [M_DATA_WIDTH-1:0]      data_fifo_wdata[S_INFRAME_WIDTH*1-1:0];
    wire        [S_INFRAME_WIDTH*1-1:0] data_fifo_afull;
    reg                                 info_fifo_wen[8:2];
    reg         [INFO_W-1:0]            info_fifo_wdata[8:2];
    wire                                info_fifo_afull;
    reg                                 info_fifo_ren;
    wire        [INFO_W-1:0]            info_fifo_rdata;
    wire                                info_fifo_pempty;
    wire                                info_fifo_empty;
    reg         [S_INFRAME_WIDTH*1-1:0] data_fifo_ren;
    wire        [M_DATA_WIDTH-1:0]      data_fifo_rdata[S_INFRAME_WIDTH*1-1:0];
    wire        [S_INFRAME_WIDTH*1-1:0] data_fifo_empty;
    reg                                 thr_pkt_flag_d[2:2];
    reg                                 info_read_flag; 
    reg         [15:0]                  pkt_len_d1;
    reg         [2:0]                   pkt_user_err_d1;
    reg         [7:0]                   pkt_clk_num_d1;
    reg         [3:0]                   read_start_num_d[3:1];
    wire        [4:0]                   last_num_d1;
    reg         [7:0]                   pkt_ren_cnt;     
    reg                                 data_fifo_ren_d3;
    reg         [7:0]                   data_empty_d[3:2];
    reg         [2:0]                   data_uerr_d[3:2];

    always @(posedge clk) begin
        if(s_orig_valid)
            s_orig_inframe_d[1]     <= s_orig_inframe;  
        else 
            s_orig_inframe_d[1]     <= 16'd0;  
        s_orig_inframe_d[2]         <= s_orig_inframe_d[1];  

        if(s_orig_valid)begin 
            s_orig_data_d[1]        <= s_orig_data;    
            s_orig_emty_d[1]        <= s_orig_emty;    
        end  

        s_orig_fcs_error_d[2:1]     <= {s_orig_fcs_error_d[1],s_orig_fcs_error};
        s_orig_error_d[2:1]         <= {s_orig_error_d[1],s_orig_error};

        s_orig_valid_d[1]           <= s_orig_valid;
    end

    always @(posedge clk ) begin
        if(s_orig_valid)begin 
            sop1_pos_d[2:1] <= {sop1_pos_d[1],s_sop1_pos};
            sop2_pos_d[2:1] <= {sop2_pos_d[1],s_sop2_pos};
            eop1_pos_d[2:1] <= {eop1_pos_d[1],s_eop1_pos};
            eop2_pos_d[2:1] <= {eop2_pos_d[1],s_eop2_pos};
        end 
        sop_num_d[2:1]   <= {sop_num_d[1],s_sop_num};
        eop_num_d[2:1]   <= {eop_num_d[1],s_eop_num};
        write_flag_d[2:1]<= {write_flag_d[1],s_write_flag};
    end

    always @(posedge clk ) begin
        casex ({s_write_flag,s_sop_num,s_eop_num,s_sop1_pos<s_eop1_pos})
            6'b0_00_00_x: begin write_num_d[1] <= 5'd16;                          pkt0_len[1] <= 8'd128 ;                                       end
            6'b0_01_00_x: begin write_num_d[1] <= 5'(16-s_sop1_pos);              pkt0_len[1] <= (5'd16-s_sop1_pos)<<3;                         end
            6'b0_01_01_1: begin write_num_d[1] <= 5'(s_eop1_pos-s_sop1_pos+1);    pkt0_len[1] <= ((s_eop1_pos-s_sop1_pos)<<3)+4'd8-s_eop1_empty;end
            6'b0_10_01_1: begin write_num_d[1] <= 5'(s_eop1_pos-s_sop1_pos+1);    pkt0_len[1] <= ((s_eop1_pos-s_sop1_pos)<<3)+4'd8-s_eop1_empty;end
            6'b0_10_10_1: begin write_num_d[1] <= 5'(s_eop1_pos-s_sop1_pos+1);    pkt0_len[1] <= ((s_eop1_pos-s_sop1_pos)<<3)+4'd8-s_eop1_empty;end
            6'b0_00_01_x: begin write_num_d[1] <= 5'(s_eop1_pos+1);               pkt0_len[1] <= (s_eop1_pos<<3)+4'd8-s_eop1_empty;             end
            6'b0_01_01_0: begin write_num_d[1] <= 5'(s_eop1_pos+1);               pkt0_len[1] <= (s_eop1_pos<<3)+4'd8-s_eop1_empty;             end
            6'b0_01_10_0: begin write_num_d[1] <= 5'(s_eop1_pos+1);               pkt0_len[1] <= (s_eop1_pos<<3)+4'd8-s_eop1_empty;             end
            6'b0_10_10_0: begin write_num_d[1] <= 5'(s_eop1_pos+1+16-s_sop2_pos); pkt0_len[1] <= (s_eop1_pos<<3)+4'd8-s_eop1_empty;             end
            6'b1_10_01_1: begin write_num_d[1] <= 5'(16-s_sop2_pos);              pkt0_len[1] <= (5'd16-s_sop2_pos)<<3;                         end
            6'b1_10_10_1: begin write_num_d[1] <= 5'(s_eop2_pos-s_sop2_pos+1);    pkt0_len[1] <= ((s_eop2_pos-s_sop2_pos)<<3)+4'd8-s_eop2_empty;end
            6'b1_01_01_0: begin write_num_d[1] <= 5'(16-s_sop1_pos);              pkt0_len[1] <= (5'd16-s_sop1_pos)<<3;                         end
            6'b1_01_10_0: begin write_num_d[1] <= 5'(s_eop2_pos-s_sop1_pos+1);    pkt0_len[1] <= ((s_eop2_pos-s_sop1_pos)<<3)+4'd8-s_eop2_empty;end
            6'b1_10_10_0: begin write_num_d[1] <= 5'(s_eop2_pos-s_sop1_pos+1);    pkt0_len[1] <= ((s_eop2_pos-s_sop1_pos)<<3)+4'd8-s_eop2_empty;end
            default:      begin write_num_d[1] <= 5'd0;                           pkt0_len[1] <= 8'd0 ;                                         end
        endcase

        pkt0_len[2] <= pkt0_len[1];
    end

    always @(posedge clk ) begin
        casex ({s_write_flag,s_sop_num,s_eop_num,s_sop1_pos<s_eop1_pos})
            6'b0_00_00_x: begin fcs_err_d1 <= 1'd0;                          end
            6'b0_01_00_x: begin fcs_err_d1 <= 1'd0;                          end
            6'b0_01_01_1: begin fcs_err_d1 <= 5'(s_eop1_pos-s_sop1_pos+1);   end
            6'b0_10_01_1: begin fcs_err_d1 <= 5'(s_eop1_pos-s_sop1_pos+1);   end
            6'b0_10_10_1: begin fcs_err_d1 <= 5'(s_eop1_pos-s_sop1_pos+1);   end
            6'b0_00_01_x: begin fcs_err_d1 <= 5'(s_eop1_pos+1);              end
            6'b0_01_01_0: begin fcs_err_d1 <= 5'(s_eop1_pos+1);              end
            6'b0_01_10_0: begin fcs_err_d1 <= 5'(s_eop1_pos+1);              end
            6'b0_10_10_0: begin fcs_err_d1 <= 5'(s_eop1_pos+1+16-s_sop2_pos);end
            6'b1_10_01_1: begin fcs_err_d1 <= 5'(16-s_sop2_pos);             end
            6'b1_10_10_1: begin fcs_err_d1 <= 5'(s_eop2_pos-s_sop2_pos+1);   end
            6'b1_01_01_0: begin fcs_err_d1 <= 5'(16-s_sop1_pos);             end
            6'b1_01_10_0: begin fcs_err_d1 <= 5'(s_eop2_pos-s_sop1_pos+1);   end
            6'b1_10_10_0: begin fcs_err_d1 <= 5'(s_eop2_pos-s_sop1_pos+1);   end
            default:      begin fcs_err_d1 <= 5'd0;                          end
        endcase
    end
    

    always @(posedge clk ) begin
        if(s_orig_valid && ~s_write_flag && s_eop_num==2'd2 && s_sop_num==2'd2 && s_sop1_pos > s_eop1_pos)
            pkt1_len[1] <= (5'd16-s_sop2_pos)<<3;
        else 
            pkt1_len[1] <= 8'd0;

        pkt1_len[2] <= pkt1_len[1];
    end

    always @(posedge clk) begin
        if(s_orig_valid && ~s_write_flag && s_sop_num == 2'd2 && s_eop_num == 2'd2 &&  s_sop1_pos > s_eop1_pos)
            cur_sop_pos_d[1] <= s_sop2_pos;
        else if(s_orig_valid && ~s_write_flag && s_sop_num >= 2'd1 && (s_eop_num == 2'd0 || s_sop1_pos < s_eop1_pos))
            cur_sop_pos_d[1] <= s_sop1_pos;
        else if(s_orig_valid && s_write_flag && s_sop_num == 2'd2 && s_sop1_pos < s_eop1_pos)
            cur_sop_pos_d[1] <= s_sop2_pos;
        else if(s_orig_valid && s_write_flag && s_sop_num >= 2'd1 &&  s_sop1_pos > s_eop1_pos)
            cur_sop_pos_d[1] <= s_sop1_pos;

        cur_sop_pos_d[2] <= cur_sop_pos_d[1];
    end

    generate
        for (genvar i=0 ; i<16 ; i=i+1 ) begin
            always @(posedge clk ) begin
                if(!rst_n) 
                    start_num_d1[i] <= 4'd0;
                else if(s_orig_valid_d[1]) 
                    start_num_d1[i] <= start_num_d1[i] + write_num_d[1];

                start_num_d2[i] <= start_num_d1[i];
            end

            always @(posedge clk) begin
                if(s_orig_valid_d[1] && write_num_d[1] == 5'd16 )
                    data_fifo_wen[2][i] <= 1'b1;
                else if(s_orig_valid_d[1] && (start_num_d1[i]+write_num_d[1] > 5'd16) &&  ((start_num_d1[i]+write_num_d[1] > i + 16) || (i >= start_num_d1[i])))
                    data_fifo_wen[2][i] <= 1'b1;
                else if(s_orig_valid_d[1] && (start_num_d1[i]+write_num_d[1] <= 5'd16) && i >= start_num_d1[i] && i < start_num_d1[i]+write_num_d[1])
                    data_fifo_wen[2][i] <= 1'b1;
                else 
                    data_fifo_wen[2][i] <= 1'b0;

                data_fifo_wen[3][i] <= data_fifo_wen[2][i];
            end
            
            always @(posedge clk ) begin
                if(s_orig_valid && ~s_write_flag && s_sop_num == 2'd2 && s_eop_num == 2'd2 &&  s_sop1_pos > s_eop1_pos && i > s_eop1_pos)
                    data_pos_d1[i] <= 4'(s_sop2_pos + i - s_eop1_pos -1);
                else if(s_orig_valid && ~s_write_flag && s_sop_num >= 2'd1 && (s_eop_num == 2'd0  || s_sop1_pos < s_eop1_pos))
                    data_pos_d1[i] <= s_sop1_pos + i;
                else if(s_orig_valid && ~s_write_flag && s_eop_num >= 2'd1 && (s_sop_num == 2'd0 || s_sop1_pos > s_eop1_pos))
                    data_pos_d1[i] <= i;
                else if(s_orig_valid && s_write_flag && s_sop_num == 2'd2 && s_sop1_pos < s_eop1_pos)
                    data_pos_d1[i] <= s_sop2_pos + i;
                else if(s_orig_valid && s_write_flag && s_sop_num >= 2'd1 && s_sop1_pos > s_eop1_pos)
                    data_pos_d1[i] <= s_sop1_pos + i;
                else if(s_orig_valid)
                    data_pos_d1[i] <= i;
            end

            always @(posedge clk ) begin
                s_orig_data_d[2][i*64+:64] <= s_orig_data_d[1][data_pos_d1[i]*64 +: 64];
            end

            always @(posedge clk) begin
                data_fifo_wdata[i] <= s_orig_data_d[2][4'(16+i-start_num_d2[i])*64+:64]; 
            end
        end
    endgenerate

    always @(posedge clk) begin
        if(s_orig_valid_d[1] && ~write_flag_d[1] && sop_num_d[1]==2'd2 && eop_num_d[1]==2'd2 && sop1_pos_d[1] > eop1_pos_d[1])
            thr_pkt_flag_d[2] <= 1'b1;
        else 
            thr_pkt_flag_d[2] <= 1'b0;
    end

    always @(posedge clk) begin
        if(s_orig_valid_d[1] && ~write_flag_d[1] && eop_num_d[1]>=2'd1)
            info_fifo_wen[2] <= 1'b1;            
        else if(s_orig_valid_d[1]  && write_flag_d[1] && sop_num_d[1]==2'd2 && eop_num_d[1]==2'd2 && sop1_pos_d[1] < eop1_pos_d[1])
            info_fifo_wen[2] <= 1'b1;        
        else if(s_orig_valid_d[1]  && write_flag_d[1] && sop_num_d[1]>=2'd1 && eop_num_d[1]==2'd2 && sop1_pos_d[1] > eop1_pos_d[1])
            info_fifo_wen[2] <= 1'b1;
        else if(thr_pkt_flag_d[2] && ~write_flag_d[2] && s_orig_valid_d[1] && eop_num_d[1]>=2'd1)
            info_fifo_wen[2] <= 1'b1;
        else  
            info_fifo_wen[2] <= 1'b0;

        info_fifo_wen[8:3] <= info_fifo_wen[7:2];
    end

    always @(posedge clk) begin
        if(s_orig_valid_d[1] && ~write_flag_d[1] && sop_num_d[1]>=2'd1 && (eop_num_d[1]==2'd0 || sop1_pos_d[1] < eop1_pos_d[1]))
            info_fifo_wdata[2][15:0] <= pkt0_len[1];
        else if(s_orig_valid_d[1] && write_flag_d[1] && sop_num_d[1]>=2'd2 && sop1_pos_d[1] < eop1_pos_d[1])
            info_fifo_wdata[2][15:0] <= pkt0_len[1];
        else if(s_orig_valid_d[1] && write_flag_d[1] && sop_num_d[1]>=2'd1 && sop1_pos_d[1] > eop1_pos_d[1])
            info_fifo_wdata[2][15:0] <= pkt0_len[1];
        else if(thr_pkt_flag_d[2] && s_orig_valid_d[1])
            info_fifo_wdata[2][15:0] <= pkt1_len[2]+pkt0_len[1];
        else if(thr_pkt_flag_d[2] && (!s_orig_valid_d[1]))
            info_fifo_wdata[2][15:0] <= pkt1_len[2];
        else if(s_orig_valid_d[1] && ~write_flag_d[1])
            info_fifo_wdata[2][15:0] <= info_fifo_wdata[2][15:0] + pkt0_len[1];

        if(thr_pkt_flag_d[2])
            info_fifo_wdata[2][18:16] <= {s_orig_fcs_error_d[2][eop1_pos_d[2]],s_orig_error_d[2][eop1_pos_d[2]*2+:2]};
        else 
            info_fifo_wdata[2][18:16] <= {s_orig_fcs_error_d[1][eop1_pos_d[1]],s_orig_error_d[1][eop1_pos_d[1]*2+:2]};

        info_fifo_wdata[8:3] <= info_fifo_wdata[7:2];
    end
/***********************************FIFO例化，function定义*******************************************/
//从两个fifo中调取报文 写进异步fifo中，转换时钟域，转换位宽，带宽不够时丢包
    always @(posedge clk ) begin
        if(m_axis_tready & (!info_fifo_pempty) & info_fifo_ren & info_fifo_rdata[15:0] <= 16'd128)
            info_fifo_ren <= 1'b1;
        else if(m_axis_tready & (!info_fifo_empty) & (!info_fifo_ren) & (!info_read_flag))
            info_fifo_ren <= 1'b1;
        else if(m_axis_tready & (!info_fifo_empty) & info_read_flag & (pkt_ren_cnt + 2'd2) == pkt_clk_num_d1 & pkt_clk_num_d1>=8'd2)
            info_fifo_ren <= 1'b1;
        else  
            info_fifo_ren <= 1'b0;
    end

    //assign info_fifo_ren = m_axis_tready & (!info_fifo_pempty) & ((!info_read_flag) | (info_read_flag & (pkt_ren_cnt + 2'd1) == pkt_clk_num_d1));

    always @(posedge clk) begin
        if(info_fifo_ren)begin 
            pkt_len_d1          <= info_fifo_rdata[15:0];
            pkt_user_err_d1     <= info_fifo_rdata[18:16];
            pkt_clk_num_d1      <= info_fifo_rdata[14:7] + (|info_fifo_rdata[6:0]);
        end  
    end
    
    always @(posedge clk ) begin
        if(!rst_n)
            info_read_flag <= 1'b0;
        else if(info_fifo_ren)
            info_read_flag <= 1'b1;
        else if(info_read_flag && (pkt_ren_cnt + 1'b1) == pkt_clk_num_d1)
            info_read_flag <= 1'b0;
    end

    always @(posedge clk ) begin
        if(info_fifo_ren)
            pkt_ren_cnt <= 8'd0;
        else if(info_read_flag)
            pkt_ren_cnt <= pkt_ren_cnt + 1'b1;
        else  
            pkt_ren_cnt <= 8'd0;
    end

    always @(posedge clk) begin
        if(!rst_n)
            read_start_num_d[1] <= 4'd0;
        else if(info_read_flag && (pkt_ren_cnt + 1'b1) == pkt_clk_num_d1)
            read_start_num_d[1] <= read_start_num_d[1] + pkt_len_d1[6:3] + (|pkt_len_d1[2:0]);

        read_start_num_d[3:2] <= read_start_num_d[2:1];
    end

    assign last_num_d1 = info_read_flag && (pkt_ren_cnt + 1'b1) == pkt_clk_num_d1 ? (pkt_len_d1[6:0] == 7'd0 ? 5'd16 : pkt_len_d1[6:3] + (|pkt_len_d1[2:0])) : 5'd16;

    generate
        for (genvar i=0 ; i<16 ; i=i+1) begin
            always @(posedge clk ) begin
                if(info_read_flag && (pkt_ren_cnt + 1'b1) == pkt_clk_num_d1 && 16 < last_num_d1+read_start_num_d[1] && (i>=read_start_num_d[1] || (16+i < last_num_d1+read_start_num_d[1])))
                    data_fifo_ren[i] <= 1'b1;
                else if(info_read_flag && (pkt_ren_cnt + 1'b1) == pkt_clk_num_d1 && 16 >= last_num_d1+read_start_num_d[1] && i>=read_start_num_d[1] && i < last_num_d1+read_start_num_d[1])
                    data_fifo_ren[i] <= 1'b1;
                else if(info_read_flag && (pkt_ren_cnt + 1'b1) < pkt_clk_num_d1)
                    data_fifo_ren[i] <= 1'b1;
                else  
                    data_fifo_ren[i] <= 1'b0;
            end            

            always @(posedge clk ) begin
                m_axis_tdata[i*64+:64] <= data_fifo_rdata[4'(read_start_num_d[3]+i)];
            end
        end
    endgenerate

    always @(posedge clk ) begin
        data_empty_d[2]  <= (pkt_ren_cnt + 1'b1) == pkt_clk_num_d1 ? {1'b1,pkt_len_d1[6:0]} : {1'b0,7'd0};
        data_empty_d[3]  <= data_empty_d[2];
        data_uerr_d[3:2] <= {data_uerr_d[2],pkt_user_err_d1};
        data_fifo_ren_d3 <= |data_fifo_ren;
    end

    always @(posedge clk ) begin
        m_axis_tvalid     <= data_fifo_ren_d3;
        m_axis_tempty     <= data_empty_d[3][6:0];
        m_axis_tuerr      <= data_uerr_d[3];

        if(!rst_n)
            m_axis_teop   <= 1'b0;
        else 
            m_axis_teop   <= data_empty_d[3][7];
    end

    generate
        for (genvar i=0 ; i<16 ; i=i+1) begin
            sfifo  #(
                .ALMOST_EMPTY       (10     ),
                .ALMOST_AFULL       (500    ),
                .FIFO_TYPE          ("M20K" ),
                .SHOWAHEAD          ("OFF"  ),
                .DEPTH              (512    ),
                .WIDTH              (64     )
            )
            data_fifo0
            (
                .aclr               (!rst_n),
                .clock              (clk),
                .wrreq              (data_fifo_wen[3][i]),
                .data               (data_fifo_wdata[i]),
                .almost_full        (data_fifo_afull[i]),
                .full               (),
                .rdreq              (data_fifo_ren[i]),
                .q                  (data_fifo_rdata[i]),
                .almost_empty       (),
                .empty              (data_fifo_empty[i]),
                .usedw              ()
            );
        end  
    endgenerate
    
    sfifo  #(
        .ALMOST_EMPTY       (8      ),
        .ALMOST_AFULL       (100    ),
        .FIFO_TYPE          ("MLAB" ),
        .SHOWAHEAD          ("ON"   ),
        .DEPTH              (256    ),
        .WIDTH              (INFO_W )
    )
    info_fifo0
    (
        .aclr               (!rst_n),
        .clock              (clk),
        .wrreq              (info_fifo_wen[8]),
        .data               (info_fifo_wdata[8]),
        .almost_full        (info_fifo_afull),
        .full               (),
        .rdreq              (info_fifo_ren  ),
        .q                  (info_fifo_rdata),
        .almost_empty       (info_fifo_pempty),
        .empty              (info_fifo_empty),
        .usedw              ()
    );
endmodule
`resetall
