// axis_keep_pack
// 把 tkeep 不满的 AXI-Stream 重新打包成每拍全有效的流（小端，低字节在前），
// 端口与 MCDMA h2d_axi_st_* 对齐。
//   输入约束：每拍 tkeep 只能是低位连续的 1（如 0x..000FFFFFF），允许全 1 或全 0。
//   输出：每包除最后一拍外 tkeep 全 1；最后一拍 tkeep 为低位连续的 1，tlast=1。
//   包内有效字节恰好凑满整拍、且该包最后一拍输入 tkeep 全 0 时，凑满的那拍先扣住，
//   空的 tlast 拍到来后把 tlast / sideband / error 并上去，空拍丢掉，输出每拍至少 1 字节。
//   整包 0 字节（每拍 tkeep 都全 0）的包直接丢弃，不输出。输出永远不会出现 tkeep 全 0。
//   tid / tuser_metadata：SB_MODE="SOP"  取包首拍的值，整包不变；
//                         SB_MODE="BEAT" 取触发该输出拍的输入拍的值，包尾拍以输入 tlast 拍为准。
//   tuser_error：包内逐拍累计（OR），末拍输出整包结果。
//   tkeep 无效字节的数据输出为 0。
// 结构（面向 500MHz）：
//   in slice -> A: 清无效字节、算字节数
//            -> B: 累计包内偏移、粗移位（8 字节粒度）
//            -> C: 细移位（1 字节粒度）、预算各 tkeep
//            -> 拼接 / 输出寄存 -> out slice
//   A/B/C 共用推进使能 adv；包尾拼接超过一整拍时多输出一拍（flush），流水停 1 拍。
//   时延约 6 拍。
`timescale 1ns/1ps
`default_nettype none
module axis_keep_pack #(
    parameter   TDATA_WIDTH                 = 1024,
    parameter   TID_WIDTH                   = 12,
    parameter   TMETA_WIDTH                 = 64,
    parameter   SB_MODE                     = "SOP"         // "SOP" / "BEAT"
)(
    input   wire                            clk,
    input   wire                            rst_n,        // 低有效，同步复位

    input   wire                            s_axis_tvalid,
    output  wire                            s_axis_tready,
    input   wire    [TDATA_WIDTH-1:0]       s_axis_tdata,
    input   wire    [TDATA_WIDTH/8-1:0]     s_axis_tkeep,
    input   wire                            s_axis_tlast,
    input   wire    [TMETA_WIDTH-1:0]       s_axis_tuser_metadata,
    input   wire    [TID_WIDTH-1:0]         s_axis_tid,
    input   wire                            s_axis_tuser_error,

    output  wire                            m_axis_tvalid,
    input   wire                            m_axis_tready,
    output  wire    [TDATA_WIDTH-1:0]       m_axis_tdata,
    output  wire    [TDATA_WIDTH/8-1:0]     m_axis_tkeep,
    output  wire                            m_axis_tlast,
    output  wire    [TMETA_WIDTH-1:0]       m_axis_tuser_metadata,
    output  wire    [TID_WIDTH-1:0]         m_axis_tid,
    output  wire                            m_axis_tuser_error,
    // 打包后本拍的有效字节数，与 m_axis_tkeep 同拍、同一套编码（下游 rdma_timestamp_mark 的约定）：
    //   [6:0] = 1..127，bit7 = 1 表示整拍 TDATA_WIDTH/8 字节
    // 在输出寄存级由已寄存的 keep 算，替代 YuanRDMA 里对 128 位 keep 的 popcount 归约，
    // 把那条组合路径从 pcie_app_clk 的时序里去掉（B6437 pld_clkout −0.332 / 398 端点，见优化日志 §62.2）。
    output  wire    [7:0]                   m_axis_tbyte_num
);
    localparam  KW                          = TDATA_WIDTH/8;
    localparam  CW                          = $clog2(KW);   // 包内偏移 0..KW-1 的位宽
    localparam  SBW                         = TID_WIDTH + TMETA_WIDTH;  // {tid, metadata}

    initial begin
        if (KW < 16 || (1 << CW) != KW)
            $fatal(1, "[%m] TDATA_WIDTH must be 2^n and >= 128");
        if (SB_MODE != "SOP" && SB_MODE != "BEAT")
            $fatal(1, "[%m] Unknown SB_MODE %s", SB_MODE);
    end

    // 低位连续 tkeep -> 字节数（0..KW），用边沿检测 + one-hot 编码，避免 popcount 加法树
    function automatic [CW:0] keep2cnt(input [KW-1:0] k);
        integer     i;
        reg [KW:0]  kx;
        reg [CW:0]  idx;
        begin
            kx       = {1'b0, k};
            keep2cnt = '0;
            for (i = 0; i < KW; i = i + 1) begin
                idx = i + 1;
                if (kx[i] & ~kx[i+1])
                    keep2cnt = keep2cnt | idx;
            end
        end
    endfunction

    // 字节数 -> 下游编码（rdma_timestamp_mark 的 tkeep 约定）：整拍给 0x80，其余给字节数
    function automatic [7:0] cnt2vcount(input [CW:0] c);
        begin
            cnt2vcount = (c == KW) ? 8'h80 : {1'b0, c[CW-1:0]};
        end
    endfunction

    // 字节数 -> 低位连续 tkeep
    function automatic [KW-1:0] cnt2keep(input [CW:0] c);
        integer i;
        for (i = 0; i < KW; i = i + 1)
            cnt2keep[i] = (i < c);
    endfunction

    // tkeep 按字节展开成数据位宽的掩码
    function automatic [TDATA_WIDTH-1:0] byte_mask(input [KW-1:0] k);
        integer i;
        for (i = 0; i < KW; i = i + 1)
            byte_mask[i*8 +: 8] = {8{k[i]}};
    endfunction

    //------------------------------------------------------------------
    // 输入 register slice
    //------------------------------------------------------------------
    wire                                    i_vld;
    wire                                    i_rdy;
    wire            [TDATA_WIDTH-1:0]       i_data;
    wire            [KW-1:0]                i_keep;
    wire                                    i_last;
    wire            [TMETA_WIDTH:0]         i_user;     // {error, metadata}
    wire            [TID_WIDTH-1:0]         i_tid;

    axi_stream_register_slice #(
        .TDATA_W                            (TDATA_WIDTH        ),
        .TID_W                              (TID_WIDTH          ),
        .TDEST_W                            (1                  ),
        .TUSER_W                            (TMETA_WIDTH+1      ),
        .MODE                               ("full"             )
    ) u_in_slice (
        .s_axis_tvalid                      (s_axis_tvalid      ),
        .s_axis_tdata                       (s_axis_tdata       ),
        .s_axis_tkeep                       (s_axis_tkeep       ),
        .s_axis_tlast                       (s_axis_tlast       ),
        .s_axis_tid                         (s_axis_tid         ),
        .s_axis_tdest                       (1'b0               ),
        .s_axis_tuser                       ({s_axis_tuser_error, s_axis_tuser_metadata}),
        .s_axis_tready                      (s_axis_tready      ),

        .m_axis_tvalid                      (i_vld              ),
        .m_axis_tdata                       (i_data             ),
        .m_axis_tkeep                       (i_keep             ),
        .m_axis_tlast                       (i_last             ),
        .m_axis_tid                         (i_tid              ),
        .m_axis_tdest                       (                   ),
        .m_axis_tuser                       (i_user             ),
        .m_axis_tready                      (i_rdy              ),

        .aclk                               (clk                ),
        .aresetn                            (rst_n              )
    );

    // A/B/C 三级共用的推进使能，在后面拼接级定义
    wire                                    adv;
    assign i_rdy = adv;

    //------------------------------------------------------------------
    // A 级：清无效字节，算字节数，处理 sideband
    //------------------------------------------------------------------
    reg                                     a_vld;
    reg             [TDATA_WIDTH-1:0]       a_data;
    reg             [CW:0]                  a_cnt;
    reg                                     a_last;
    reg             [SBW-1:0]               a_sb;
    reg                                     a_err;
    reg                                     in_sop;
    reg             [SBW-1:0]               pkt_sb;     // SOP 模式下锁存的包首拍 sideband
    reg                                     pkt_err;    // 包内已累计的 error

    wire            [SBW-1:0]               i_sb     = {i_tid, i_user[TMETA_WIDTH-1:0]};
    wire                                    i_err    = i_user[TMETA_WIDTH];
    wire                                    i_take   = i_vld & adv;

    always @(posedge clk) begin
        if (!rst_n) begin
            a_vld   <= 1'b0;
            in_sop  <= 1'b1;
            pkt_err <= 1'b0;
        end else if (adv) begin
            a_vld   <= i_vld;
            if (i_vld) begin
                in_sop  <= i_last;
                pkt_err <= ~i_last & (i_err | (pkt_err & ~in_sop));
            end
        end
    end

    always @(posedge clk) begin
        if (adv) begin
            a_data  <= i_data & byte_mask(i_keep);
            a_cnt   <= keep2cnt(i_keep);
            a_last  <= i_last;
            a_err   <= i_err | (pkt_err & ~in_sop);
            if (SB_MODE == "BEAT" || in_sop)
                a_sb <= i_sb;
            else
                a_sb <= pkt_sb;
        end
        if (i_take && in_sop)
            pkt_sb  <= i_sb;
    end

    //------------------------------------------------------------------
    // B 级：累计包内偏移 a_ofs（= 拼接级残留字节数），按 8 字节粒度粗移位
    //------------------------------------------------------------------
    reg             [CW-1:0]                a_ofs;
    reg                                     b_vld;
    reg             [TDATA_WIDTH-1:0]       b_data;
    reg             [CW-1:0]                b_ofs;
    reg             [CW:0]                  b_sum;
    reg                                     b_last;
    reg             [SBW-1:0]               b_sb;
    reg                                     b_err;

    wire            [CW:0]                  a_sum    = a_ofs + a_cnt;
    // 循环左移 a_ofs[CW-1:3]*8 字节
    wire            [2*TDATA_WIDTH-1:0]     a_dbl    = {a_data, a_data} << {a_ofs[CW-1:3], 6'd0};

    always @(posedge clk) begin
        if (!rst_n) begin
            a_ofs   <= '0;
            b_vld   <= 1'b0;
        end else if (adv) begin
            b_vld   <= a_vld;
            if (a_vld)
                a_ofs <= a_last ? '0 : a_sum[CW-1:0];
        end
    end

    always @(posedge clk) begin
        if (adv) begin
            b_data  <= a_dbl[2*TDATA_WIDTH-1:TDATA_WIDTH];
            b_ofs   <= a_ofs;
            b_sum   <= a_sum;
            b_last  <= a_last;
            b_sb    <= a_sb;
            b_err   <= a_err;
        end
    end
    //------------------------------------------------------------------
    // C 级：按 1 字节粒度细移位，预算拼接用的各个 tkeep
    //------------------------------------------------------------------
    reg                                     c_vld;
    reg             [TDATA_WIDTH-1:0]       c_data;     // 已循环左移 b_ofs 字节
    reg             [KW-1:0]                c_rkeep;    // 残留字节 tkeep（低 b_ofs 字节）
    reg             [KW-1:0]                c_okeep;    // 本拍输出 tkeep
    reg             [KW-1:0]                c_fkeep;    // flush 拍 tkeep（凑满一拍后剩余部分）
    reg                                     c_full;     // 残留 + 本拍 >= 一整拍
    reg                                     c_last;
    reg                                     c_olast;    // 本拍输出即包尾
    reg                                     c_flush;    // 包尾需再输出一拍
    reg                                     c_null;     // 本拍拼接后没有任何字节
    reg                                     c_hold;     // 本拍恰好凑满整拍且不是包尾
    reg             [SBW-1:0]               c_sb;
    reg                                     c_err;

    wire            [2*TDATA_WIDTH-1:0]     b_dbl    = {b_data, b_data} << {b_ofs[2:0], 3'd0};
    wire                                    b_full   = b_sum[CW];
    wire                                    b_rem0   = (b_sum[CW-1:0] == 0);

    always @(posedge clk) begin
        if (!rst_n)
            c_vld   <= 1'b0;
        else if (adv)
            c_vld   <= b_vld;
    end

    always @(posedge clk) begin
        if (adv) begin
            c_data  <= b_dbl[2*TDATA_WIDTH-1:TDATA_WIDTH];
            c_rkeep <= cnt2keep({1'b0, b_ofs});
            c_okeep <= b_full ? {KW{1'b1}} : cnt2keep(b_sum);
            c_fkeep <= cnt2keep({1'b0, b_sum[CW-1:0]});
            c_full  <= b_full;
            c_last  <= b_last;
            c_olast <= b_last & (~b_full | b_rem0);
            c_flush <= b_last & b_full & ~b_rem0;
            c_null  <= ~b_full & b_rem0;                // 残留 + 本拍 = 0 字节
            c_hold  <= ~b_last & b_full & b_rem0;       // 恰好凑满且非包尾，输出后要扣住
            c_sb    <= b_sb;
            c_err   <= b_err;
        end
    end

    //------------------------------------------------------------------
    // 拼接级 + 输出寄存
    //   r_data 低 r_keep 字节为残留；c_data 字节 i >= 残留数的部分接在残留后面（mrg_lo），
    //   字节 i < 残留数的部分是溢出，凑满一拍时成为新残留（mrg_hi）。
    //   残留数与 B 级 a_ofs 同步推进，c_rkeep 即当前残留的 tkeep。
    //------------------------------------------------------------------
    reg             [TDATA_WIDTH-1:0]       r_data;
    reg             [KW-1:0]                f_keep;
    reg             [SBW-1:0]               f_sb;
    reg                                     f_err;
    reg                                     r_flush;    // r_data 是包尾，需单独输出一拍

    reg                                     o_vld;
    reg             [TDATA_WIDTH-1:0]       o_data;
    reg             [KW-1:0]                o_keep;
    reg                                     o_last;
    reg             [SBW-1:0]               o_sb;
    reg                                     o_err;
    reg             [7:0]                   o_byte_num; // 与 o_keep 同步更新的字节数编码
    reg                                     o_hold;     // o_* 是恰好凑满的非包尾拍，先扣住不送 out slice
    wire                                    o_rdy;      // out slice 的 s_axis_tready，寄存器输出

    // 扣住的拍要等后面的拍来确认：
    //   来的是有字节的拍 -> 扣住的拍不是包尾，放行（o_rel）
    //   来的是空的包尾拍 -> 把 tlast / sideband / error 并到扣住的拍上，空拍丢掉（o_mrg）
    //   来的是空的非包尾拍 -> 直接吃掉，继续扣住
    wire                                    o_rel    = o_hold & c_vld & ~c_null;
    wire                                    o_mrg    = o_hold & c_vld & c_null & c_last & ~r_flush;
    wire                                    o_send   = o_vld & (~o_hold | o_rel);

    wire            [TDATA_WIDTH-1:0]       c_rmask  = byte_mask(c_rkeep);
    wire            [TDATA_WIDTH-1:0]       mrg_lo   = (r_data & c_rmask) | (c_data & ~c_rmask);
    wire            [TDATA_WIDTH-1:0]       mrg_hi   = c_data & c_rmask;
    // 空拍从不产生输出：空的包尾拍要么并入扣住的拍（o_mrg），要么是整包 0 字节，直接丢弃
    wire                                    need_out = (c_full | c_last) & ~c_null;
    wire                                    out_rdy  = ~o_vld | (o_send & o_rdy);
    wire                                    c_take   = c_vld & ~r_flush & (~need_out | out_rdy);

    // C 级为空或本拍被拼接级接收时，A/B/C 整体前进一拍
    assign adv = ~c_vld | c_take;

    always @(posedge clk) begin
        if (!rst_n)
            r_flush <= 1'b0;
        else if (r_flush)
            r_flush <= ~out_rdy;
        else if (c_take)
            r_flush <= c_flush;
    end

    // r_data 只在 c_rkeep 范围内有效，包尾后残留数归 0，不需要复位
    always @(posedge clk) begin
        if (c_take) begin
            r_data  <= c_full ? mrg_hi : mrg_lo;
            f_keep  <= c_fkeep;
            f_sb    <= c_sb;
            f_err   <= c_err;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            o_vld   <= 1'b0;
            o_hold  <= 1'b0;
        end else if (out_rdy) begin
            o_vld   <= r_flush | (c_take & need_out);
            o_hold  <= ~r_flush & c_take & c_hold;
        end else if (o_rel | o_mrg) begin
            o_hold  <= 1'b0;
        end
    end

    always @(posedge clk) begin
        if (o_mrg) begin
            o_last  <= 1'b1;
            o_sb    <= c_sb;                    // 以 tlast 拍为准
            o_err   <= c_err;
        end else if (out_rdy) begin
            if (r_flush) begin
                o_data  <= r_data;
                o_keep  <= f_keep;
                o_last  <= 1'b1;
                o_sb    <= f_sb;
                o_err   <= f_err;
            end else begin
                o_data  <= mrg_lo;
                o_keep  <= c_okeep;
                o_last  <= c_olast;
                o_sb    <= c_sb;
                o_err   <= c_err & c_olast;     // 非包尾拍 error 不输出，统一在末拍给
            end
        end
    end

    // 字节数与输入寄存级之后的 o_keep 逐拍对齐：装载条件与 o_keep 完全一致
    //   o_mrg：o_keep/o_data 保持（是扣住的那拍），这里也保持；
    //   否则 out_rdy 时：r_flush 拍取 f_keep，普通拍取 c_okeep —— 与 o_keep 同源同拍。
    // 计算用已被寄存的 keep，避免回头依赖 b_sum 的多级流水状态：
    //   keep2cnt 是边沿检测 + one-hot（模块内既有实现，注释见上），比原来跨模块的
    //   128 位 popcount 归约短，且不再落在 u82→uxx 这条 flop-to-flop 路径上。
    always @(posedge clk) begin
        if (~o_mrg & out_rdy)
            o_byte_num <= cnt2vcount(keep2cnt(r_flush ? f_keep : c_okeep));
    end

    //------------------------------------------------------------------
    // 输出 register slice
    //   tuser 侧带 = {err, byte_num[7:0], {tid, metadata}}
    //------------------------------------------------------------------
    localparam  USRW                        = TMETA_WIDTH + 1 + 8;
    wire            [USRW-1:0]              m_user;

    axi_stream_register_slice #(
        .TDATA_W                            (TDATA_WIDTH        ),
        .TID_W                              (TID_WIDTH          ),
        .TDEST_W                            (1                  ),
        .TUSER_W                            (USRW               ),
        .MODE                               ("full"             )
    ) u_out_slice (
        .s_axis_tvalid                      (o_send             ),
        .s_axis_tdata                       (o_data             ),
        .s_axis_tkeep                       (o_keep             ),
        .s_axis_tlast                       (o_last             ),
        .s_axis_tid                         (o_sb[SBW-1:TMETA_WIDTH]),
        .s_axis_tdest                       (1'b0               ),
        .s_axis_tuser                       ({o_err, o_byte_num, o_sb[TMETA_WIDTH-1:0]}),
        .s_axis_tready                      (o_rdy              ),

        .m_axis_tvalid                      (m_axis_tvalid      ),
        .m_axis_tdata                       (m_axis_tdata       ),
        .m_axis_tkeep                       (m_axis_tkeep       ),
        .m_axis_tlast                       (m_axis_tlast       ),
        .m_axis_tid                         (m_axis_tid         ),
        .m_axis_tdest                       (                   ),
        .m_axis_tuser                       (m_user             ),
        .m_axis_tready                      (m_axis_tready      ),

        .aclk                               (clk                ),
        .aresetn                            (rst_n              )
    );

    assign m_axis_tuser_metadata = m_user[TMETA_WIDTH-1:0];
    assign m_axis_tbyte_num      = m_user[TMETA_WIDTH +: 8];
    assign m_axis_tuser_error    = m_user[USRW-1];

endmodule
`default_nettype wire
