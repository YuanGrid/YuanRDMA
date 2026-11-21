`timescale 1ns/1ps
module jitter_st_ram #(
    parameter       DATA_W          = 32,
    parameter       ADDR_W          = 12
)
(  
    input                           stream_pkt_tvalid,
    input                           stream_pkt_tlast,
    input                           stream_pkt_tready,
    input           [DATA_W-1:0]    new_data,
    input           [ADDR_W-1:0]    stream_pkt_id_w,
    input                           stream_pkt_r_req,
    input           [ADDR_W:0]      stream_pkt_id_r,
    input                           stream_pkt_rst,
    output  reg     [DATA_W-1:0]    stream_minjt_rdata,
    output  reg     [DATA_W-1:0]    stream_maxjt_rdata,
    output  reg     [2*DATA_W-1:0]  stream_sumjt_rdata,
    input                           axis_aclk,
    input                           axil_aclk,
    input                           axis_rstn
);
    reg     [DATA_W-1:0]            pre_time_dly_wdata[0:0];
    reg     [ADDR_W-1:0]            pre_time_dly_waddr[0:0];
    reg                             pre_time_dly_wen  [0:0];
    reg                             pre_time_dly_ren  [0:0];
    reg     [ADDR_W-1:0]            pre_time_dly_raddr[0:0];
    wire    [DATA_W-1:0]            pre_time_dly_rdata[1:1];
    reg     [DATA_W-1:0]            cur_jitter_time[2:2];
    reg     [DATA_W-1:0]            min_jitter_wdata[4:3];
    reg     [ADDR_W-1:0]            min_jitter_waddr[4:3];
    reg                             min_jitter_wen  [4:3];
    reg                             min_jitter_ren  [2:1];
    reg     [ADDR_W-1:0]            min_jitter_raddr[2:1];
    wire    [DATA_W-1:0]            min_jitter_rdata[2:2];
    reg     [DATA_W-1:0]            max_jitter_wdata[4:3];
    reg     [ADDR_W-1:0]            max_jitter_waddr[4:3];
    reg                             max_jitter_wen  [4:3];
    reg                             max_jitter_ren  [2:1];
    reg     [ADDR_W-1:0]            max_jitter_raddr[2:1];
    wire    [DATA_W-1:0]            max_jitter_rdata[2:2];
    reg     [2*DATA_W-1:0]          sum_jitter_wdata[4:3];
    reg     [ADDR_W-1:0]            sum_jitter_waddr[4:3];
    reg                             sum_jitter_wen  [4:3];
    reg                             sum_jitter_ren  [2:1];
    reg     [ADDR_W-1:0]            sum_jitter_raddr[2:1];
    wire    [2*DATA_W-1:0]          sum_jitter_rdata[2:2];
    reg     [DATA_W:0]              new_data_d[2:0];
    reg                             min_cfg_read_wen;
    reg     [ADDR_W-1:0]            min_cfg_read_waddr;
    reg     [DATA_W-1:0]            min_cfg_read_wdata;
    reg                             max_cfg_read_wen;
    reg     [ADDR_W-1:0]            max_cfg_read_waddr;
    reg     [DATA_W-1:0]            max_cfg_read_wdata;
    reg                             sum_cfg_read_wen;
    reg     [ADDR_W-1:0]            sum_cfg_read_waddr;
    reg     [DATA_W-1:0]            sum_cfg_read_wdata;
    reg                             axil_rst_flag;
    reg     [4:0]                   axil_rst_wait_cnt;
    reg                             axis_rst_flag[3:0];
    reg                             static_clear;
    reg     [ADDR_W-1:0]            static_clear_cnt;
//清零操作
    always @(posedge axil_aclk ) begin
        axil_rst_flag <= stream_pkt_rst;

        if(!axis_rstn)
            axis_rst_flag[0] <= 1'b0;
        else if(stream_pkt_rst & (!axil_rst_flag))
            axis_rst_flag[0] <= 1'b1;
        else if(axil_rst_wait_cnt == 5'd30) 
            axis_rst_flag[0] <= 1'b0;
    end

    always @(posedge axil_aclk ) begin
        if(axil_rst_wait_cnt != 0)
            axil_rst_wait_cnt <= axil_rst_wait_cnt + 1'b1;
        else if(stream_pkt_rst & (!axil_rst_flag))
            axil_rst_wait_cnt <= 5'd1;
        else  
            axil_rst_wait_cnt <= 5'd0;
    end

    always @(posedge axis_aclk ) begin
        axis_rst_flag[3:1] <= axis_rst_flag[2:0];

        if((!axis_rst_flag[3]) & axis_rst_flag[2])
            static_clear <= 1'b1;
        else if(static_clear & (&static_clear_cnt))
            static_clear <= 1'b0;
        else if(!axis_rstn)
            static_clear <= 1'b0;
    end

    always @(posedge axis_aclk ) begin
        if(static_clear)
            static_clear_cnt <= static_clear_cnt + 1'b1;
        else 
            static_clear_cnt <= {ADDR_W{1'b0}};
    end
//前一个延时时间寄存
    always @(posedge axis_aclk ) begin
        pre_time_dly_wdata[0] <= new_data;
        pre_time_dly_waddr[0] <= stream_pkt_id_w;
        pre_time_dly_wen  [0] <= stream_pkt_tvalid & stream_pkt_tlast & stream_pkt_tready;
        pre_time_dly_raddr[0] <= stream_pkt_id_w;
        pre_time_dly_ren  [0] <= stream_pkt_tvalid & stream_pkt_tlast & stream_pkt_tready;
        new_data_d[2:0]       <= {new_data_d[1:0],new_data};
    end

    always @(posedge axis_aclk ) begin
        if(pre_time_dly_rdata[1] > new_data_d[1])
            cur_jitter_time[2] <= pre_time_dly_rdata[1] - new_data_d[1];
        else 
            cur_jitter_time[2] <= new_data_d[1] - pre_time_dly_rdata[1];
    end

    always @(posedge axis_aclk ) begin
        min_jitter_ren  [2:1] <= {min_jitter_ren  [1],pre_time_dly_ren  [0]};
        min_jitter_raddr[2:1] <= {min_jitter_raddr[1],pre_time_dly_raddr[0]};
        min_jitter_wen  [4:3] <= {min_jitter_wen  [3],min_jitter_ren  [2]};
        min_jitter_waddr[4:3] <= {min_jitter_waddr[3],min_jitter_raddr[2]};

        max_jitter_ren  [2:1] <= {max_jitter_ren  [1],pre_time_dly_ren  [0]};
        max_jitter_raddr[2:1] <= {max_jitter_raddr[1],pre_time_dly_raddr[0]};
        max_jitter_wen  [4:3] <= {max_jitter_wen  [3],max_jitter_ren  [2]};
        max_jitter_waddr[4:3] <= {max_jitter_waddr[3],max_jitter_raddr[2]};

        sum_jitter_ren  [2:1] <= {sum_jitter_ren  [1],pre_time_dly_ren  [0]};
        sum_jitter_raddr[2:1] <= {sum_jitter_raddr[1],pre_time_dly_raddr[0]};
        sum_jitter_wen  [4:3] <= {sum_jitter_wen  [3],sum_jitter_ren  [2]};
        sum_jitter_waddr[4:3] <= {sum_jitter_waddr[3],sum_jitter_raddr[2]};
    end

    always @(posedge axis_aclk ) begin
        if(static_clear)
            min_jitter_wdata[3] <= {DATA_W{1'b0}};
        else if(min_jitter_ren[2] & min_jitter_wen[3] & min_jitter_raddr[2]==min_jitter_waddr[3])
            min_jitter_wdata[3] <= min_jitter_wdata[3] > cur_jitter_time[2] ? cur_jitter_time[2] : min_jitter_wdata[3];
        else if(min_jitter_ren[2] & min_jitter_wen[4] & min_jitter_raddr[2]==min_jitter_waddr[4])
            min_jitter_wdata[3] <= min_jitter_wdata[4] > cur_jitter_time[2] ? cur_jitter_time[2] : min_jitter_wdata[4];                
        else 
            min_jitter_wdata[3] <= min_jitter_rdata[2] > cur_jitter_time[2] ? cur_jitter_time[2] : min_jitter_rdata[2];

        min_jitter_wdata[4] <= min_jitter_wdata[3];
    end

    always @(posedge axis_aclk ) begin
        if(static_clear)
            max_jitter_wdata[3] <= {DATA_W{1'b0}};
        else if(max_jitter_ren[2] & max_jitter_wen[3] & max_jitter_raddr[2]==max_jitter_waddr[3])
            max_jitter_wdata[3] <= max_jitter_wdata[3] > cur_jitter_time[2] ? cur_jitter_time[2] : max_jitter_wdata[3];
        else if(max_jitter_ren[2] & max_jitter_wen[4] & max_jitter_raddr[2]==max_jitter_waddr[4])
            max_jitter_wdata[3] <= max_jitter_wdata[4] > cur_jitter_time[2] ? cur_jitter_time[2] : max_jitter_wdata[4];                
        else 
            max_jitter_wdata[3] <= max_jitter_rdata[2] > cur_jitter_time[2] ? cur_jitter_time[2] : max_jitter_rdata[2];

        max_jitter_wdata[4] <= max_jitter_wdata[3];
    end

    always @(posedge axis_aclk ) begin
        if(static_clear)
            sum_jitter_wdata[3] <= {2*DATA_W{1'b0}};
        else if(sum_jitter_ren[2] & sum_jitter_wen[3] & sum_jitter_raddr[2]==sum_jitter_waddr[3])
            sum_jitter_wdata[3] <= sum_jitter_wdata[3] + cur_jitter_time[2];
        else if(sum_jitter_ren[2] & sum_jitter_wen[4] & sum_jitter_raddr[2]==sum_jitter_waddr[4])
            sum_jitter_wdata[3] <= sum_jitter_wdata[4] + cur_jitter_time[2];                
        else 
            sum_jitter_wdata[3] <= sum_jitter_rdata[2] + cur_jitter_time[2];

        sum_jitter_wdata[4] <= sum_jitter_wdata[3];
    end

    always @(posedge axis_aclk ) begin
        min_cfg_read_wen   <= min_jitter_wen  [3];
        min_cfg_read_waddr <= min_jitter_waddr[3];
        min_cfg_read_wdata <= min_jitter_wdata[3];

        max_cfg_read_wen   <= max_jitter_wen  [3];
        max_cfg_read_waddr <= max_jitter_waddr[3];
        max_cfg_read_wdata <= max_jitter_wdata[3];

        sum_cfg_read_wen   <= sum_jitter_wen  [3];
        sum_cfg_read_waddr <= sum_jitter_waddr[3];
        sum_cfg_read_wdata <= sum_jitter_wdata[3];
    end

    ram #(
        .ram_block_type         ("M20K"                 ),
        .outdata_b_reg          ("UNUSED"               ),
        .widthad_a              (ADDR_W                 ),
        .widthad_b              (ADDR_W                 ),
        .width_a                (DATA_W                 ),
        .width_b                (DATA_W                 )
    )
    u0_min_jitter
    (
        .wrclock                (axis_aclk              ),
        .wren                   (min_jitter_wen  [3]    ),
        .wraddress              (min_jitter_waddr[3]    ),
        .data                   (min_jitter_wdata[3]    ),
        .rdclock                (axis_aclk              ),
        .rden                   (min_jitter_ren  [1]    ),
        .rdaddress              (min_jitter_raddr[1]    ),
        .q                      (min_jitter_rdata[2]    )
    );

    ram #(
        .ram_block_type         ("M20K"                 ),
        .outdata_b_reg          ("UNUSED"               ),
        .widthad_a              (ADDR_W                 ),
        .widthad_b              (ADDR_W                 ),
        .width_a                (DATA_W                 ),
        .width_b                (DATA_W                 )
    )
    u1_min_read
    (
        .wrclock                (axis_aclk              ),
        .wren                   (min_cfg_read_wen       ),
        .wraddress              (min_cfg_read_waddr     ),
        .data                   (min_cfg_read_wdata     ),
        .rdclock                (axil_aclk              ),
        .rden                   (stream_pkt_r_req       ),
        .rdaddress              (stream_pkt_id_r        ),
        .q                      (stream_minjt_rdata     )
    );

    ram #(
        .ram_block_type         ("M20K"                 ),
        .outdata_b_reg          ("UNUSED"               ),
        .widthad_a              (ADDR_W                 ),
        .widthad_b              (ADDR_W                 ),
        .width_a                (DATA_W                 ),
        .width_b                (DATA_W                 )
    )
    u2_max_jitter
    (
        .wrclock                (axis_aclk              ),
        .wren                   (max_jitter_wen  [3]    ),
        .wraddress              (max_jitter_waddr[3]    ),
        .data                   (max_jitter_wdata[3]    ),
        .rdclock                (axis_aclk              ),
        .rden                   (max_jitter_ren  [1]    ),
        .rdaddress              (max_jitter_raddr[1]    ),
        .q                      (max_jitter_rdata[2]    )
    );

    ram #(
        .ram_block_type         ("M20K"                 ),
        .outdata_b_reg          ("UNUSED"               ),
        .widthad_a              (ADDR_W                 ),
        .widthad_b              (ADDR_W                 ),
        .width_a                (DATA_W                 ),
        .width_b                (DATA_W                 )
    )
    u3_max_read
    (
        .wrclock                (axis_aclk              ),
        .wren                   (max_cfg_read_wen       ),
        .wraddress              (max_cfg_read_waddr     ),
        .data                   (max_cfg_read_wdata     ),
        .rdclock                (axil_aclk              ),
        .rden                   (stream_pkt_r_req       ),
        .rdaddress              (stream_pkt_id_r        ),
        .q                      (stream_maxjt_rdata     )
    );

    ram #(
        .ram_block_type         ("M20K"                 ),
        .outdata_b_reg          ("UNUSED"               ),
        .widthad_a              (ADDR_W                 ),
        .widthad_b              (ADDR_W                 ),
        .width_a                (2*DATA_W               ),
        .width_b                (2*DATA_W               )
    )
    u4_sum_jitter
    (
        .wrclock                (axis_aclk              ),
        .wren                   (sum_jitter_wen  [3]    ),
        .wraddress              (sum_jitter_waddr[3]    ),
        .data                   (sum_jitter_wdata[3]    ),
        .rdclock                (axis_aclk              ),
        .rden                   (sum_jitter_ren  [1]    ),
        .rdaddress              (sum_jitter_raddr[1]    ),
        .q                      (sum_jitter_rdata[2]    )
    );

    ram #(
        .ram_block_type         ("M20K"                 ),
        .outdata_b_reg          ("UNUSED"               ),
        .widthad_a              (ADDR_W                 ),
        .widthad_b              (ADDR_W                 ),
        .width_a                (2*DATA_W               ),
        .width_b                (2*DATA_W               )
    )
    u5_sum_read
    (
        .wrclock                (axis_aclk              ),
        .wren                   (sum_cfg_read_wen       ),
        .wraddress              (sum_cfg_read_waddr     ),
        .data                   (sum_cfg_read_wdata     ),
        .rdclock                (axil_aclk              ),
        .rden                   (stream_pkt_r_req       ),
        .rdaddress              (stream_pkt_id_r        ),
        .q                      (stream_sumjt_rdata     )
    );


  



endmodule
