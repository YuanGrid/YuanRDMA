`timescale 1ns/1ps
module rx_mux_nto1 #(
    parameter int                           RCV_NUM     = 2,
    parameter                               DATA_W      = 1024,
    parameter                               KEEP_W      = $clog2(DATA_W/8)
)(    
    input                                   s_clk,
    input                                   m_clk,
    input                                   rst_n,
    input                                   m_rst_n,
    input           [RCV_NUM-1:0]           s_axis_rx_tvalid,
    input   reg     [RCV_NUM*DATA_W-1:0]    s_axis_rx_tdata,
    input           [RCV_NUM*KEEP_W-1:0]    s_axis_rx_tkeep,
    input           [RCV_NUM-1:0]           s_axis_rx_tlast,
    input           [RCV_NUM*4-1:0]         s_axis_rx_tuser,
    output  reg                             m_axis_rx_tvalid,
    output  reg     [DATA_W-1:0]            m_axis_rx_tdata,
    output  reg     [KEEP_W-1:0]            m_axis_rx_tkeep,
    output  reg                             m_axis_rx_tlast,
    input                                   m_axis_rx_tready,
    input   wire                            cnt_clear_en,
    output  wire    [RCV_NUM*32-1:0]        eth_fcs_err_cnt,
    output  wire    [RCV_NUM*32-1:0]        eth_mfmd_err_cnt,
    output  wire    [RCV_NUM*32-1:0]        eth_under_over_err_cnt,
    output  wire    [RCV_NUM*32-1:0]        eth_plen_err_cnt,
    output  wire    [RCV_NUM*32-1:0]        eth_fifo_full_err_cnt
);
    reg                                     s_axis_fifo_valid[RCV_NUM-1:0];
    reg     [DATA_W-1:0]                    s_axis_fifo_data[RCV_NUM-1:0];
    reg     [KEEP_W-1:0]                    s_axis_fifo_keep[RCV_NUM-1:0];
    reg                                     s_axis_fifo_last[RCV_NUM-1:0];
    reg                                     s_axis_fifo_drop[RCV_NUM-1:0];
    wire        s_axis_fifo_drop_eff[RCV_NUM-1:0];   // 有效丢弃：drop 寄存器 | 本拍 FIFO 满
    wire                                    s_axis_fifo_ready[RCV_NUM-1:0];
    wire                                    m_axis_fifo_valid[RCV_NUM-1:0];
    wire    [DATA_W-1:0]                    m_axis_fifo_data[RCV_NUM-1:0];
    wire    [KEEP_W-1:0]                    m_axis_fifo_keep[RCV_NUM-1:0];
    wire                                    m_axis_fifo_last[RCV_NUM-1:0];
    wire                                    m_axis_fifo_ready[RCV_NUM-1:0];
    // B6420：axis_fifo 出口到选择逻辑之间加一级全寄存 slice（每路一个）。
    // B6418 pld_clkout：RAM（无输出寄存器）读出的 tlast → m_axis_last → select[]，2 级逻辑，−0.237；
    // RAM 读出 → eop FIFO 读指针 −0.350（B6419 已由 EOP_POP_DELAY 处理）。slice 之后 select / 输出寄存器
    // 只看寄存器，RAM 读出只进 slice 的数据寄存器。每路流的帧边界与顺序不变，只多 1 拍延迟。
    wire                                    fifo_q_valid[RCV_NUM-1:0];
    wire    [DATA_W-1:0]                    fifo_q_data[RCV_NUM-1:0];
    wire    [KEEP_W-1:0]                    fifo_q_keep[RCV_NUM-1:0];
    wire                                    fifo_q_last[RCV_NUM-1:0];
    wire                                    fifo_q_ready[RCV_NUM-1:0];
    wire    [RCV_NUM-1:0]                   axis_fifo_ram_full ;
    wire    [RCV_NUM-1:0]                   axis_fifo_ram_empty;
    wire    [RCV_NUM-1:0]                   axis_fifo_eop_empty;
    reg                                     eth_fcs_err_vld[RCV_NUM-1:0];
    reg                                     eth_mfmd_err_vld[RCV_NUM-1:0];
    reg                                     eth_under_over_err_vld[RCV_NUM-1:0];
    reg                                     eth_plen_err_vld[RCV_NUM-1:0];
    reg                                     eth_fifo_full_err_vld[RCV_NUM-1:0];
    reg     [RCV_NUM-1:0]                   select;
    wire    [RCV_NUM-1:0]                   m_axis_last;
    reg     [7:0]                           reg_wait_cnt;
    reg     [RCV_NUM-1:0]                   s_drop_fifo_wen;
    reg     [RCV_NUM-1:0]                   s_drop_fifo_wdata;
    wire    [RCV_NUM-1:0]                   s_drop_fifo_afull;
    reg     [RCV_NUM-1:0]                   s_drop_fifo_ren;
    wire    [RCV_NUM-1:0]                   s_drop_fifo_rdata;
    wire    [RCV_NUM-1:0]                   s_drop_fifo_empty;
    wire    [RCV_NUM-1:0]                   s_drop_fifo_pempty;
    reg                                     s_drop_select;
    reg                                     s_info_fifo_wen;
    reg     [1:0]                           s_info_fifo_wdata;
    wire                                    s_info_fifo_afull;
    reg                                     m_info_fifo_ren;
    wire    [1:0]                           m_info_fifo_rdata;
    wire                                    m_info_fifo_empty;
    reg                                     m_info_fifo_pempty;
    wire    [8:0]                           m_info_fifo_rcnt;
    reg                                     pkt_select_done;
    reg     [1:0]                           fir_info_reg;
    reg                                     fir_info_reg_vld;
    reg                                     sec_info_reg_vld;
    generate
        for(genvar i=0 ; i<RCV_NUM ; i=i+1)begin 
            always @(posedge s_clk ) begin
                s_axis_fifo_valid[i] <= s_axis_rx_tvalid[i];
                s_axis_fifo_data[i]  <= s_axis_rx_tdata[i*DATA_W+:DATA_W];
                s_axis_fifo_keep[i]  <= s_axis_rx_tkeep[i*KEEP_W+:KEEP_W];
                s_axis_fifo_last[i]  <= s_axis_rx_tlast[i];

                if(!rst_n)
                    s_axis_fifo_drop[i] <= 1'b0;
                else if(s_axis_rx_tvalid[i] & s_axis_rx_tlast[i] & (|s_axis_rx_tuser[(i*4+2)+:2]))
                    s_axis_fifo_drop[i] <= 1'b1;
                else if(s_axis_rx_tvalid[i] & (!s_axis_fifo_ready[i]))
                    s_axis_fifo_drop[i] <= 1'b1;
                // 2026-11-12：FIFO 在帧中间某拍拒写（本拍 ram_full）时整帧剩余拍一起丢，
                // 防止帧内有气泡、下一拍到来时 ram_full 已落下而把后半帧写进去拼成残帧。
                else if(s_axis_fifo_valid[i] & (!s_axis_fifo_ready[i]) & (!s_axis_fifo_last[i]))
                    s_axis_fifo_drop[i] <= 1'b1;
                else if(s_axis_fifo_valid[i] & s_axis_fifo_last[i])
                    s_axis_fifo_drop[i] <= 1'b0;
            end

            // 2026-11-12 修复「满边沿 phantom」（skill/roce-optimization-log.md §66，台子 test/sim/rx_mux）：
            // s_axis_fifo_drop 在第 t 拍按 ready(t) = ~ram_full(t) 算出、随数据打一拍到 t+1 使用；
            // axis_fifo 却在第 t+1 拍按 ram_full(t+1) 决定写不写。ram_full 恰在帧尾那一拍升起时，
            // mux 往 drop FIFO 记「保留」而 FIFO 没提交这帧 → info FIFO 比数据 lane 多一条，
            // 合并级从此错位一帧（板上 ping 奇偶交替 ~1 s、新回包先出旧回包紧随，只有重配能清）。
            // 修法：本拍 FIFO 满并入有效丢弃，同一信号送 axis_fifo（拒写即整帧回滚）、drop FIFO 记录与丢帧计数。
            assign s_axis_fifo_drop_eff[i] = s_axis_fifo_drop[i] | (s_axis_fifo_valid[i] & (!s_axis_fifo_ready[i]));

            always @(posedge s_clk ) begin
                s_drop_fifo_wen[i]      <= s_axis_fifo_valid[i] & s_axis_fifo_last[i];
                s_drop_fifo_wdata[i]    <= s_axis_fifo_valid[i] & s_axis_fifo_last[i] & s_axis_fifo_drop_eff[i];
            end
        end  
    endgenerate
    //同步fifo写处理  
    always @(posedge s_clk ) begin
        if(!rst_n)
            s_drop_select <= 1'b0;
        else if(s_drop_fifo_ren[0] & (!s_drop_fifo_ren[1]))
            s_drop_select <= 1'b1;
        else if(s_drop_fifo_ren[1] & (!s_drop_fifo_ren[0]))
            s_drop_select <= 1'b0;
    end

    assign s_drop_fifo_ren[0] = (!s_drop_fifo_empty[0]) & (!s_drop_select);
    assign s_drop_fifo_ren[1] = (!s_drop_fifo_empty[1]) & (s_drop_select | ((!s_drop_fifo_empty[0]) & (!s_drop_select)));

    always @(posedge s_clk ) begin
        if((s_drop_fifo_ren[0] & (!s_drop_fifo_rdata[0])) || (s_drop_fifo_ren[1] & (!s_drop_fifo_rdata[1])))
            s_info_fifo_wen <= 1'b1;
        else 
            s_info_fifo_wen <= 1'b0;

        s_info_fifo_wdata[0] <= s_drop_fifo_ren[0] & (!s_drop_fifo_rdata[0]);
        s_info_fifo_wdata[1] <= s_drop_fifo_ren[1] & (!s_drop_fifo_rdata[1]);
    end

    /*******************************************m_clk******************************************************/
    always @(posedge m_clk ) begin
        if(m_info_fifo_rcnt > 9'd6)
            m_info_fifo_pempty <= 1'b0;
        else  
            m_info_fifo_pempty <= 1'b1;
    end

    always @(posedge m_clk ) begin
        if(select==2'b0 && !m_info_fifo_empty && !m_info_fifo_ren)
            m_info_fifo_ren <= 1'b1;
        else if(select==2'b0 && !m_info_fifo_pempty && m_info_fifo_ren && m_info_fifo_rdata != 2'b11)
            m_info_fifo_ren <= 1'b1;
        else if(!m_info_fifo_pempty && m_info_fifo_ren && m_info_fifo_rdata != 2'b11 && |m_axis_last)
            m_info_fifo_ren <= 1'b1;
        else if(fir_info_reg_vld && fir_info_reg==2'b01 && !m_info_fifo_empty && |m_axis_last)
            m_info_fifo_ren <= 1'b1;
        else if(sec_info_reg_vld && !m_info_fifo_empty && |m_axis_last)
            m_info_fifo_ren <= 1'b1;
        else  
            m_info_fifo_ren <= 1'b0;
    end

    always @(posedge m_clk ) begin
        if(!m_rst_n)
            fir_info_reg_vld <= 1'b0;
        else if(fir_info_reg_vld && |m_axis_last)
            fir_info_reg_vld <= 1'b0;
        else if(m_info_fifo_ren & m_info_fifo_rdata[0] & (|select) & m_axis_last==2'b0)
            fir_info_reg_vld <= 1'b1;
    end

    always @(posedge m_clk ) begin
        if(!m_rst_n)
            sec_info_reg_vld <= 1'b0;
        else if(sec_info_reg_vld && |m_axis_last)
            sec_info_reg_vld <= 1'b0;
        else if(m_info_fifo_ren & m_info_fifo_rdata==2'b10 & (|select) & m_axis_last==2'b0)
            sec_info_reg_vld <= 1'b1;
        else if(fir_info_reg_vld & fir_info_reg==2'b11 & (|m_axis_last))
            sec_info_reg_vld <= 1'b1;
        else if(m_info_fifo_ren & m_info_fifo_rdata==2'b11 & ((|m_axis_last) | (select==2'b0)))
            sec_info_reg_vld <= 1'b1;
    end

    always @(posedge m_clk ) begin
        if(!m_rst_n)
            fir_info_reg <= 2'b0;
        else if(m_info_fifo_ren)
            fir_info_reg <= m_info_fifo_rdata;
    end

    always @(posedge m_clk ) begin
        if(!m_rst_n)
            select[0] <= 1'b0;
        else if(m_info_fifo_ren & m_info_fifo_rdata[0] & ((|m_axis_last) | (select==2'b0)))
            select[0] <= 1'b1;
        else if(fir_info_reg_vld & (|m_axis_last) & (!sec_info_reg_vld))
            select[0] <= 1'b1;
        else if(m_axis_last[0])
            select[0] <= 1'b0;
    end

    always @(posedge m_clk ) begin
        if(!m_rst_n)
            select[1] <= 1'b0;
        else if(m_info_fifo_ren & m_info_fifo_rdata==2'b10 & ((|m_axis_last) | (select==2'b0)))
            select[1] <= 1'b1;
        else if(sec_info_reg_vld & (|m_axis_last))
            select[1] <= 1'b1;
        else if(m_axis_last[1])
            select[1] <= 1'b0;
    end

    assign m_axis_fifo_ready[0] = select[0] & m_axis_rx_tready;
    assign m_axis_fifo_ready[1] = select[1] & m_axis_rx_tready;

    assign m_axis_last[0]   = m_axis_fifo_ready[0] & m_axis_fifo_valid[0] & m_axis_fifo_last[0];
    assign m_axis_last[1]   = m_axis_fifo_ready[1] & m_axis_fifo_valid[1] & m_axis_fifo_last[1];

    always @(posedge m_clk ) begin
        if(!m_rst_n)
            m_axis_rx_tvalid <= 1'b0;
        else if((m_axis_fifo_ready[0] & m_axis_fifo_valid[0])||(m_axis_fifo_ready[1] & m_axis_fifo_valid[1]))
            m_axis_rx_tvalid <= 1'b1;
        else if(m_axis_rx_tvalid & m_axis_rx_tready)
            m_axis_rx_tvalid <= 1'b0;
    end

    always @(posedge m_clk ) begin
        if(m_axis_fifo_ready[0] & m_axis_fifo_valid[0])begin 
            m_axis_rx_tdata     <= m_axis_fifo_data[0];
            m_axis_rx_tkeep     <= m_axis_fifo_keep[0];
            m_axis_rx_tlast     <= m_axis_fifo_last[0];
        end else if(m_axis_fifo_ready[1] & m_axis_fifo_valid[1])begin 
            m_axis_rx_tdata     <= m_axis_fifo_data[1];
            m_axis_rx_tkeep     <= m_axis_fifo_keep[1];
            m_axis_rx_tlast     <= m_axis_fifo_last[1];
        end 
    end
/**********************************************************************************************/

    always @(posedge s_clk ) begin
        eth_fcs_err_vld[0]        <= s_axis_rx_tvalid[0] & s_axis_rx_tlast[0] & s_axis_rx_tuser[0*4+2] ;
        eth_fcs_err_vld[1]        <= s_axis_rx_tvalid[1] & s_axis_rx_tlast[1] & s_axis_rx_tuser[1*4+2] ;
        eth_mfmd_err_vld[0]       <= s_axis_rx_tvalid[0] & s_axis_rx_tlast[0] & s_axis_rx_tuser[0*4+:3] == 3'b101;
        eth_mfmd_err_vld[1]       <= s_axis_rx_tvalid[1] & s_axis_rx_tlast[1] & s_axis_rx_tuser[1*4+:3] == 3'b101;
        eth_under_over_err_vld[0] <= s_axis_rx_tvalid[0] & s_axis_rx_tlast[0] & s_axis_rx_tuser[0*4+:3] == 3'b110;
        eth_under_over_err_vld[1] <= s_axis_rx_tvalid[1] & s_axis_rx_tlast[1] & s_axis_rx_tuser[1*4+:3] == 3'b110;
        eth_plen_err_vld[0]       <= s_axis_rx_tvalid[0] & s_axis_rx_tlast[0] & s_axis_rx_tuser[0*4+:3] == 3'b111;
        eth_plen_err_vld[1]       <= s_axis_rx_tvalid[1] & s_axis_rx_tlast[1] & s_axis_rx_tuser[1*4+:3] == 3'b111;
        eth_fifo_full_err_vld[0]  <= s_axis_fifo_valid[0] & s_axis_fifo_last[0] & s_axis_fifo_drop_eff[0];
        eth_fifo_full_err_vld[1]  <= s_axis_fifo_valid[1] & s_axis_fifo_last[1] & s_axis_fifo_drop_eff[1];
    end

    cnt#(.WIDTH(32))cnt_u00(.clear(cnt_clear_en),.clk(s_clk),.vld(eth_fcs_err_vld[0]),.step({15'b0,1'b1}),.cnt(eth_fcs_err_cnt[0*32+:32]));
    cnt#(.WIDTH(32))cnt_u01(.clear(cnt_clear_en),.clk(s_clk),.vld(eth_fcs_err_vld[1]),.step({15'b0,1'b1}),.cnt(eth_fcs_err_cnt[1*32+:32]));
    cnt#(.WIDTH(32))cnt_u02(.clear(cnt_clear_en),.clk(s_clk),.vld(eth_mfmd_err_vld[0]),.step({15'b0,1'b1}),.cnt(eth_mfmd_err_cnt[0*32+:32]));
    cnt#(.WIDTH(32))cnt_u03(.clear(cnt_clear_en),.clk(s_clk),.vld(eth_mfmd_err_vld[1]),.step({15'b0,1'b1}),.cnt(eth_mfmd_err_cnt[1*32+:32]));
    cnt#(.WIDTH(32))cnt_u04(.clear(cnt_clear_en),.clk(s_clk),.vld(eth_under_over_err_vld[0]),.step({15'b0,1'b1}),.cnt(eth_under_over_err_cnt[0*32+:32]));
    cnt#(.WIDTH(32))cnt_u05(.clear(cnt_clear_en),.clk(s_clk),.vld(eth_under_over_err_vld[1]),.step({15'b0,1'b1}),.cnt(eth_under_over_err_cnt[1*32+:32]));
    cnt#(.WIDTH(32))cnt_u06(.clear(cnt_clear_en),.clk(s_clk),.vld(eth_plen_err_vld[0]),.step({15'b0,1'b1}),.cnt(eth_plen_err_cnt[0*32+:32]));
    cnt#(.WIDTH(32))cnt_u07(.clear(cnt_clear_en),.clk(s_clk),.vld(eth_plen_err_vld[1]),.step({15'b0,1'b1}),.cnt(eth_plen_err_cnt[1*32+:32]));
    cnt#(.WIDTH(32))cnt_u08(.clear(cnt_clear_en),.clk(s_clk),.vld(eth_fifo_full_err_vld[0]),.step({15'b0,1'b1}),.cnt(eth_fifo_full_err_cnt[0*32+:32]));
    cnt#(.WIDTH(32))cnt_u09(.clear(cnt_clear_en),.clk(s_clk),.vld(eth_fifo_full_err_vld[1]),.step({15'b0,1'b1}),.cnt(eth_fifo_full_err_cnt[1*32+:32]));

    generate
        for(genvar i=0 ; i<RCV_NUM ; i=i+1)begin
            axis_fifo #(
                .CLOCKING_MODE              ("DCFIFO"               ),
                .FIFO_TYPE                  ("M20K"                 ),
                .PACKET_FIFO                ("TRUE"                 ),
                .FIFO_DEPTH                 (512                    ),
                .TDATA_WIDTH                (DATA_W                 ),
                .TUSER_WIDTH                (0                      ),
                .ALMOST_EMPTY               (4                      ),
                .ALMOST_AFULL               (360                    ),
                .DROP_EN                    (1                      ),//不等于0 表示：PACKET_FIFO="true"时s_axis_drop会置1，置1时fifo满时会自动丢包 
                                                                      //等于0 表示：s_axis_drop不会置1，一直为0，fifo满时向后反压
                .KEEP_EN                    ("OFF"                  ),//"ON"时 keep有效，off时emty有效
                // B6419：B6418 pld_clkout 全局最差 −0.350 在这里：RAM 输出的 tlast 位 → eop_pop → u1_eop_fifo
                // 读指针（M20K 无输出寄存器，uTco 大）。打一拍弹出（配合 axis_fifo 的 eop_hold 防护）。
                .EOP_POP_DELAY              (1                      )
            )axis_fifo_u(   
                .s_axis_tvalid              (s_axis_fifo_valid[i]   ),
                .s_axis_tready              (s_axis_fifo_ready[i]   ),
                .s_axis_tdata               (s_axis_fifo_data[i]    ),
                .s_axis_temty               (s_axis_fifo_keep[i]    ),
                .s_axis_tkeep               (                       ),
                .s_axis_tlast               (s_axis_fifo_last[i]    ),
                .s_axis_tuser               (                       ),
                .s_axis_pfull               (                       ),
                .s_axis_drop                (s_axis_fifo_drop_eff[i]),
                .m_axis_tvalid              (fifo_q_valid[i]        ),
                .m_axis_tready              (fifo_q_ready[i]        ),
                .m_axis_tdata               (fifo_q_data[i]         ),
                .m_axis_temty               (fifo_q_keep[i]         ),
                .m_axis_tkeep               (                       ),
                .m_axis_tlast               (fifo_q_last[i]         ),
                .m_axis_tuser               (                       ),
                .ram_full                   (axis_fifo_ram_full[i]  ),
                .ram_empty                  (axis_fifo_ram_empty[i] ),
                .eop_empty                  (axis_fifo_eop_empty[i] ),
                .s_aresetn                  (rst_n                  ),
                .s_clk                      (s_clk                  ),
                .m_clk                      (m_clk                  )
            );

            axi_stream_register_slice #(
                .TDATA_W                    (DATA_W                 ),
                .TID_W                      (1                      ),
                .TDEST_W                    (1                      ),
                .TUSER_W                    (KEEP_W                 ),
                .MODE                       ("full"                 )
            ) u_out_slice (
                .s_axis_tvalid              (fifo_q_valid[i]        ),
                .s_axis_tdata               (fifo_q_data[i]         ),
                .s_axis_tkeep               (                       ),
                .s_axis_tlast               (fifo_q_last[i]         ),
                .s_axis_tid                 (1'b0                   ),
                .s_axis_tdest               (1'b0                   ),
                .s_axis_tuser               (fifo_q_keep[i]         ),
                .s_axis_tready              (fifo_q_ready[i]        ),
                .m_axis_tvalid              (m_axis_fifo_valid[i]   ),
                .m_axis_tdata               (m_axis_fifo_data[i]    ),
                .m_axis_tkeep               (                       ),
                .m_axis_tlast               (m_axis_fifo_last[i]    ),
                .m_axis_tid                 (                       ),
                .m_axis_tdest               (                       ),
                .m_axis_tuser               (m_axis_fifo_keep[i]    ),
                .m_axis_tready              (m_axis_fifo_ready[i]   ),
                .aclk                       (m_clk                  ),
                .aresetn                    (m_rst_n                )
            );

            sfifo  #(
                .ALMOST_EMPTY               (6                      ),
                .ALMOST_AFULL               (120                    ),
                .FIFO_TYPE                  ("MLAB"                 ),
                .SHOWAHEAD                  ("ON"                   ),
                .DEPTH                      (128                    ),
                .WIDTH                      (1                      )
            ) u2_drop_fifo(  
                .aclr                       (~rst_n                 ),
                .clock                      (s_clk                  ),
                .wrreq                      (s_drop_fifo_wen[i]     ),
                .data                       (s_drop_fifo_wdata[i]   ),
                .almost_full                (                       ),
                .full                       (s_drop_fifo_afull[i]   ),
                .rdreq                      (s_drop_fifo_ren[i]     ),
                .q                          (s_drop_fifo_rdata[i]   ),
                .empty                      (s_drop_fifo_empty[i]   ),
                .almost_empty               (s_drop_fifo_pempty[i]  ),
                .usedw                      (                       )
            );
        end 
    endgenerate

    dfifo #(
        .FIFO_TYPE                          ("MLAB"             ),
        .SHOWAHEAD                          ("ON"               ),
        .PACKET_FIFO                        ("NO"               ),
        .FULLTHRESHOLD                      (1000               ),
        .DEPTH                              (1024               ),
        .WIDTH                              (2                  )
    )u0_data_fifo(
        .aclr                               (~rst_n             ),
        .wrclk                              (s_clk              ),
        .wrreq                              (s_info_fifo_wen    ),
        .data                               (s_info_fifo_wdata  ),
        .wrpfull                            (s_info_fifo_afull  ),
        .wrusedw                            (),
        .rdclk                              (m_clk              ),
        .rdreq                              (m_info_fifo_ren    ),
        .q                                  (m_info_fifo_rdata  ),
        .rdempty                            (m_info_fifo_empty  ),
        .rdusedw                            (m_info_fifo_rcnt   )
    );

endmodule
