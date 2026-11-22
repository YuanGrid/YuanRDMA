//********************************************************************** */
//   Module   : pkt_send_ch
//   Function : Read datas frm TxBuf ,adn Send them without spped limit
//   Create   : by Leonqin
//   Version  : 0.1a
//   Date     : 2025.03.15
//   Function : ADD signal stream_sop,indicate start of packet
//   Version  : 0.1
//   Date     : 2024.11.17
//   To       : .........
//********************************************************************** */
`resetall
`timescale 1ns / 100ps
`default_nettype none

module pkt_send_ch_dbuf #(
    parameter       PORT_ID         = 0,
    parameter       DATA_W          = 1024,
    parameter       EMTY_W          = $clog2(DATA_W/8),
    parameter       INFO_W          = 36+12+16
)
(
    input   wire                    clk,
    input   wire                    rst_n,
    input   wire                    cmac_clk,
    input   wire    [15:0]          num_gap_a,
    input   wire    [31:0]          gap_a,
    input   wire    [15:0]          num_gap_b,
    input   wire    [31:0]          gap_b,
    output  reg     [DATA_W-1:0]    m_axis_tdata,
    output  reg     [EMTY_W-1:0]    m_axis_tusef,
    output  reg                     m_axis_tvalid,
    output  reg                     m_axis_tlast,
    output  reg     [47:0]          m_axis_tid,
    output  reg     [15:0]          m_axis_tplen,
    output  reg                     m_axis_tstamp_en,
    output  reg                     m_axis_tsop,
    input   wire                    m_axis_tready,
    input   wire                    gen_axis_tvalid,
    input   wire    [DATA_W-1:0]    gen_axis_tdata,
    input   wire    [EMTY_W-1:0]    gen_axis_tusef,
    input   wire                    gen_axis_tlast,
    input   wire    [11:0]          gen_axis_id,
    output  wire                    gen_axis_tready,
    output  reg                     gen_axis_fifo_afull,
    input   wire                    gen_info_fifo_wen,
    input   wire    [INFO_W-1:0]    gen_info_fifo_wdata,
    output  wire                    gen_info_fifo_afull,
    output  reg                     axis_fifo_vld_err
);
    localparam IP_PKT_CKSM          = 192;
    localparam UDP_PKT_CKSM         = 320;
    localparam UDP_V6_PKT_CKSM      = 480;
    localparam UDP_CKSM_P           = 0;
    localparam PKT_TYPE_P           = UDP_CKSM_P+16;
    localparam IP_CKSM_P            = PKT_TYPE_P+4;
    localparam STRM_ID_P            = IP_CKSM_P+16;
    localparam PKT_LEN_P            = STRM_ID_P+12;
    wire                            axis_pkt_ready;
    wire                            axis_pkt_valid;
    wire    [DATA_W-1:0]            axis_pkt_data;
    wire    [EMTY_W-1:0]            axis_pkt_usef;
    wire                            axis_pkt_last;
    wire    [11:0]                  axis_pkt_id;
    reg                             axis_pkt_sop;
    wire                            gen_info_fifo_ren;
    wire    [INFO_W-1:0]            gen_info_fifo_rdata;
    wire                            gen_info_fifo_empty;
    reg                             m_axis_tready_1d;
    wire    [11:0]                  strm_id;
    wire    [15:0]                  pkt_len;
    wire    [15:0]                  ip_cksm;
    wire    [2:0]                   pkt_type;
    wire    [15:0]                  udp_cksm;
    reg     [2:0]                   pkt_type_reg ;
    reg     [15:0]                  udp_cksm_reg ;
    reg                             pkt_sending;
    reg     [8:0]                   fifo_cnt;
    reg     [15:0]                  gap_loop_cnt;
    reg     [15:0]                  cfg_gap_num;
    wire                            fifo_input_valid;
    wire                            fifo_output_valid;

    //fifo 读逻辑控制
    //必须等info非空时才能读报文，但是在读报文中间，只关心下级模块是否ready
    always @(posedge cmac_clk ) begin
        m_axis_tready_1d <= m_axis_tready ;
    end
    assign axis_pkt_ready = pkt_sending ? m_axis_tready   : (m_axis_tready & (!gen_info_fifo_empty));

    always @(posedge cmac_clk ) begin
        if(!rst_n)
            axis_pkt_sop <= 1'b1;
        else if(axis_pkt_valid & (!axis_pkt_last) & axis_pkt_ready)
            axis_pkt_sop <= 1'b0;
        else if(axis_pkt_valid & axis_pkt_last & axis_pkt_ready)
            axis_pkt_sop <= 1'b1;
    end

    always @(posedge cmac_clk ) begin
        if(!rst_n)
            pkt_sending <= 1'b0;
        else if(axis_pkt_valid & axis_pkt_sop & (!axis_pkt_last) & axis_pkt_ready)
            pkt_sending <= 1'b1;
        else if(axis_pkt_valid & (!axis_pkt_sop) & axis_pkt_last & axis_pkt_ready)
            pkt_sending <= 1'b0;
    end

    always @(posedge clk ) begin
        cfg_gap_num <= num_gap_a + num_gap_b; 
    end  


    always @(posedge clk ) begin
        if(!rst_n)
            gap_loop_cnt <= 16'd1 + PORT_ID;
        else if(axis_pkt_valid & axis_pkt_ready & axis_pkt_last & gap_loop_cnt==cfg_gap_num)
            gap_loop_cnt <= 16'd2;
        else if(axis_pkt_valid & axis_pkt_ready & axis_pkt_last & gap_loop_cnt+1==cfg_gap_num)
            gap_loop_cnt <= 16'd1;
        else if(axis_pkt_valid & axis_pkt_ready & axis_pkt_last)
            gap_loop_cnt <= gap_loop_cnt+2'd2;
    end
    
    assign gen_info_fifo_ren = axis_pkt_valid & axis_pkt_ready & axis_pkt_sop ;
    assign pkt_len           = gen_info_fifo_rdata[PKT_LEN_P+:16];
    assign strm_id           = gen_info_fifo_rdata[STRM_ID_P+:12];
    assign ip_cksm           = gen_info_fifo_rdata[IP_CKSM_P+:16];
    assign pkt_type          = gen_info_fifo_rdata[PKT_TYPE_P+:3];
    assign udp_cksm          = gen_info_fifo_rdata[UDP_CKSM_P+:16];
    always @(posedge cmac_clk ) begin
        if(gen_info_fifo_ren)begin 
            pkt_type_reg <= pkt_type;
            udp_cksm_reg <= udp_cksm;
        end 
    end
    
    always @(posedge cmac_clk ) begin
        if(!rst_n)
            m_axis_tvalid  <= 1'b0;
        else if(axis_pkt_valid &  axis_pkt_ready)
            m_axis_tvalid  <= 1'b1;
        else if(m_axis_tvalid && m_axis_tready && m_axis_tlast)
            m_axis_tvalid  <= 1'b0;
    end

    always @(posedge cmac_clk ) begin
        if(!rst_n)begin 
            m_axis_tsop     <= 1'b0;
            m_axis_tlast    <= 1'b0;
        end else if(axis_pkt_valid & axis_pkt_ready)begin 
            m_axis_tsop     <= axis_pkt_sop;
            m_axis_tlast    <= axis_pkt_last;
        end  
    end

    always @(posedge cmac_clk ) begin
        if(!rst_n)
            m_axis_tstamp_en <= 1'b0;
        else if(axis_pkt_valid && axis_pkt_sop && pkt_type[2:0] == 3'b001 && pkt_len[13:0] < 14'd66)
            m_axis_tstamp_en <= 1'b0;
        else if(axis_pkt_valid && axis_pkt_sop && pkt_type[2:0] == 3'b100 && pkt_len[13:0] < 14'd78)
            m_axis_tstamp_en <= 1'b0;
        else if(axis_pkt_valid && axis_pkt_sop && pkt_type[2:0] == 3'b110 && pkt_len[13:0] < 14'd82)
            m_axis_tstamp_en <= 1'b0;
        else if(axis_pkt_valid && axis_pkt_sop && pkt_type[2:0] == 3'b101 && pkt_len[13:0] < 14'd86)
            m_axis_tstamp_en <= 1'b0;
        else if(axis_pkt_valid && axis_pkt_sop)
            m_axis_tstamp_en <= 1'b1;
    end

    always @(posedge cmac_clk) begin
        if(axis_pkt_valid & axis_pkt_ready)begin 
            m_axis_tdata            <= axis_pkt_data;
            m_axis_tusef            <= axis_pkt_usef;
            m_axis_tplen            <= axis_pkt_sop & axis_pkt_valid & axis_pkt_ready ? pkt_len : m_axis_tplen;
            m_axis_tid[15:0]        <= axis_pkt_sop & axis_pkt_valid & axis_pkt_ready ? {4'b0,strm_id} : m_axis_tid[15:0];
            m_axis_tid[47:16]       <= gap_loop_cnt<=num_gap_a ? gap_a : gap_b;
        end 

        if(axis_pkt_valid & axis_pkt_ready & axis_pkt_sop)
            case (pkt_type)//ipv6flag  valn1flag vlan2flag
                3'b100 :m_axis_tdata[(UDP_V6_PKT_CKSM)+:16]     <= udp_cksm;//ipv6 0 vlan
                3'b110 :m_axis_tdata[(UDP_V6_PKT_CKSM+32)+:16]  <= udp_cksm;//ipv6 1 vlan
                3'b101 :m_axis_tdata[(UDP_V6_PKT_CKSM+64)+:16]  <= udp_cksm;//ipv6 2 vlan
                3'b001 :begin 
                    m_axis_tdata[(IP_PKT_CKSM+64)+:16]          <= ip_cksm;//ipv4 2 vlan
                    m_axis_tdata[(UDP_PKT_CKSM+64)+:16]         <= udp_cksm;//ipv4 2 vlan
                end  
                3'b010 :begin 
                    m_axis_tdata[(IP_PKT_CKSM+32)+:16]          <= ip_cksm;//ipv4 1 vlan 
                    m_axis_tdata[(UDP_PKT_CKSM+32)+:16]         <= udp_cksm;//ipv4 1 vlan 
                end  
                default:begin 
                    m_axis_tdata[(IP_PKT_CKSM)+:16]             <= ip_cksm;//ipv4 0 vlan
                    m_axis_tdata[(UDP_PKT_CKSM)+:16]            <= udp_cksm;//ipv4 0 vlan
                end  
            endcase
    end
/*****************************debug*******************************************************/
    always @(posedge cmac_clk ) begin
        if(!rst_n)
            axis_fifo_vld_err <= 1'b0;
        else if(pkt_sending & (~axis_pkt_valid))
            axis_fifo_vld_err <= 1'b1;
    end

    assign fifo_input_valid  = gen_axis_tvalid & gen_axis_tready;
    assign fifo_output_valid = axis_pkt_valid & axis_pkt_ready;

    always @(posedge clk ) begin
        if(!rst_n)
            fifo_cnt <= 9'd0;
        else if(fifo_input_valid & (!fifo_output_valid))
            fifo_cnt <= fifo_cnt + 1'b1;
        else if((!fifo_input_valid) & fifo_output_valid)
            fifo_cnt <= fifo_cnt - 1'b1;
    end

    always @(posedge clk ) begin
        if(fifo_cnt >= 9'd450)
            gen_axis_fifo_afull <= 1'b1;
        else  
            gen_axis_fifo_afull <= 1'b0;
    end

    axis_fifo #(
        .CLOCKING_MODE              ("SCFIFO"               ),
        .FIFO_TYPE                  ("M20K"                 ),
        .PACKET_FIFO                ("false"                ),
        .FIFO_DEPTH                 (512                    ),
        .TDATA_WIDTH                (DATA_W                 ),
        .TUSER_WIDTH                (0                      ),
        .ALMOST_EMPTY               (1                      ),
        .ALMOST_AFULL               (360                    ),
        .KEEP_EN                    ("OFF"                  )//"ON"时 keep有效，off时emty有效
    )u0_pkt_fifo_inst(   
        .s_axis_tvalid              (gen_axis_tvalid        ),
        .s_axis_tready              (gen_axis_tready        ),
        .s_axis_tdata               (gen_axis_tdata         ),
        .s_axis_temty               (gen_axis_tusef         ),
        .s_axis_tkeep               (                       ),
        .s_axis_tlast               (gen_axis_tlast         ),
        .s_axis_tuser               (                       ),
        .s_axis_pfull               (                       ),
        .s_axis_drop                (                       ),
        .m_axis_tvalid              (axis_pkt_valid         ),
        .m_axis_tready              (axis_pkt_ready         ),
        .m_axis_tdata               (axis_pkt_data          ),
        .m_axis_temty               (axis_pkt_usef          ),
        .m_axis_tkeep               (                       ),
        .m_axis_tlast               (axis_pkt_last          ),
        .m_axis_tuser               (                       ),
        .s_aresetn                  (rst_n                  ),
        .s_clk                      (clk                    ),
        .m_clk                      (cmac_clk               )
    );

    dfifo #(
        .FIFO_TYPE                  ("MLAB"                 ),
        .SHOWAHEAD                  ("ON"                   ), 
        .DEPTH                      (128                    ), 
        .FULLTHRESHOLD              (100                    ),
        .WIDTH                      (INFO_W                 )
    )       
    info_fifo_u     
    (       
        .rdclk                      (cmac_clk               ),
        .wrclk                      (clk                    ),
        .aclr                       (!rst_n                 ),
        .wrreq                      (gen_info_fifo_wen      ),
        .data                       (gen_info_fifo_wdata    ),
        .wrpfull                    (gen_info_fifo_afull    ),
        .rdreq                      (gen_info_fifo_ren      ),
        .q                          (gen_info_fifo_rdata    ),
        .rdempty                    (gen_info_fifo_empty    )
    );
endmodule
`resetall







    

