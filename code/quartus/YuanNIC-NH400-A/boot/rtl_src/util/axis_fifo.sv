// (C) 2001-2025 Altera Corporation. All rights reserved.
// Your use of Altera Corporation's design tools, logic functions and other 
// software and tools, and its AMPP partner logic functions, and any output 
// files from any of the foregoing (including device programming or simulation 
// files), and any associated documentation or information are expressly subject 
// to the terms and conditions of the Altera Program License Subscription 
// Agreement, Altera IP License Agreement, or other applicable 
// license agreement, including, without limitation, that your use is for the 
// sole purpose of programming logic devices manufactured by Altera and sold by 
// Altera or its authorized distributors.  Please refer to the applicable 
// agreement for further details.
// synopsys translate_off
`timescale 1 ps / 1 ps
// synopsys translate_on
`default_nettype none
module  axis_fifo #(
    parameter   CLOCKING_MODE                   = "SCFIFO",
    parameter   FIFO_TYPE                       = "M20K",
    parameter   PACKET_FIFO                     = "false",
    parameter   FIFO_DEPTH                      = 512,
    parameter   TDATA_WIDTH                     = 512,
    parameter   TUSER_WIDTH                     = 31,
    parameter   ALMOST_EMPTY                    = 1,
    parameter   ALMOST_AFULL                    = 360,
    parameter   KEEP_EN                         = "ON" //"ON"时 keep有效，off时emty有效
)
(   
    input   wire                                s_axis_tvalid,
    output  wire                                s_axis_tready,
    input   wire    [TDATA_WIDTH-1:0]           s_axis_tdata,
    input   wire    [$clog2(TDATA_WIDTH/8)-1:0] s_axis_temty,
    input   wire    [TDATA_WIDTH/8-1:0]         s_axis_tkeep,
    input   wire                                s_axis_tlast,
    input   wire    [TUSER_WIDTH-1:0]           s_axis_tuser,
    output  wire                                s_axis_pfull,
    input   wire                                s_axis_drop,
    output  reg                                 m_axis_tvalid,
    input   wire                                m_axis_tready,
    output  wire    [TDATA_WIDTH-1:0]           m_axis_tdata,
    output  wire    [$clog2(TDATA_WIDTH/8)-1:0] m_axis_temty,
    output  wire    [TDATA_WIDTH/8-1:0]         m_axis_tkeep,
    output  wire                                m_axis_tlast,
    output  wire    [TUSER_WIDTH-1:0]           m_axis_tuser,
    input   wire                                s_aresetn,
    input   wire                                s_clk,
    input   wire                                m_clk
);
    localparam      REAL_FIFO_TYPE              = FIFO_TYPE == "M20K" ? "RAM_BLOCK_TYPE=M20K" :
                                                FIFO_TYPE == "MLAB" ? "RAM_BLOCK_TYPE=MLAB" : "";
    localparam      REAL_EMTY                   = $clog2(TDATA_WIDTH/8);
    localparam      REAL_WIDTH                  = TDATA_WIDTH+REAL_EMTY+TUSER_WIDTH+1;
    localparam      ADDR_WTH                    = $clog2(FIFO_DEPTH);

    wire                                        ram_wen; 
    reg             [ADDR_WTH-1:0]              ram_waddr;
    wire            [REAL_WIDTH-1:0]            ram_wdata;
    wire                                        ram_ren;
    wire            [ADDR_WTH-1:0]              ram_raddr;
    reg             [ADDR_WTH-1:0]              ram_raddr_reg;
    wire            [REAL_WIDTH-1:0]            ram_rdata;
    wire                                        ram_drop;
    reg                                         ram_full;
    reg                                         ram_pfull;
    reg                                         ram_empty;
    reg             [ADDR_WTH-1:0]              last_waddr;
    wire            [ADDR_WTH-1:0]              ram_raddr_cdc;
    wire            [ADDR_WTH-1:0]              ram_waddr_cdc;
    wire                                        eop_empty;
    wire                                        eop_pempty;
    wire                                        eop_flag;
    reg                                         ram_ren_d1;
    wire            [$clog2(TDATA_WIDTH/8)-1:0] s_ram_temty;
    reg             [$clog2(TDATA_WIDTH/8)-1:0] m_ram_temty;
   
    //write
    assign s_axis_pfull = ram_pfull;
    assign s_axis_tready= ~ram_full;
    assign ram_wen      = s_axis_tvalid;
    always @(posedge s_clk ) begin
        if(!s_aresetn)
            ram_waddr <= {ADDR_WTH{1'b0}};
        else if(ram_wen & ram_drop)
            ram_waddr <=  last_waddr;
        else if(ram_wen & (~ram_full))
            ram_waddr <= ram_waddr + 1'b1;
    end

    always @(posedge s_clk) begin
        if(!s_aresetn)
            last_waddr <= {ADDR_WTH{1'b0}};
        else if(ram_wen & s_axis_tlast & (!ram_drop) & (PACKET_FIFO == "TRUE" || PACKET_FIFO == "true"))
            last_waddr <= ram_waddr+1'b1;
        else if(ram_wen & s_axis_tlast)
            last_waddr <= ram_waddr+1'b1;
    end

    always @(posedge s_clk ) begin
        if(ram_waddr > ram_raddr_cdc & ram_waddr > ram_raddr_cdc+FIFO_DEPTH-4)
            ram_full <= 1'b1;
        else if(ram_waddr < ram_raddr_cdc & ram_waddr+4 > ram_raddr_cdc)
            ram_full <= 1'b1;
        else  
            ram_full <= 1'b0;
    end

    always @(posedge s_clk ) begin
        if(ram_waddr > ram_raddr_cdc & ram_waddr > ram_raddr_cdc+ALMOST_AFULL)
            ram_pfull <= 1'b1;
        else if(ram_waddr < ram_raddr_cdc & ram_waddr > ram_raddr_cdc-FIFO_DEPTH+ALMOST_AFULL)
            ram_pfull <= 1'b1;
        else  
            ram_pfull <= 1'b0;
    end
    //read
    assign ram_ren = 1'b1;

    assign ram_raddr = m_axis_tvalid & m_axis_tready ? ram_raddr_reg + 1'b1 : ram_raddr_reg;


    always @(posedge m_clk ) begin
        if(!s_aresetn)
            ram_raddr_reg <= {ADDR_WTH{1'b0}};
        else
            ram_raddr_reg <= ram_raddr;
    end

    always @(posedge m_clk ) begin
        m_axis_tvalid <= ram_ren & (!ram_empty) & ((!eop_pempty) || ((!eop_empty) & (!eop_flag)));
    end

    assign m_axis_tdata = ram_rdata[0+:TDATA_WIDTH];
    assign m_axis_temty = ram_rdata[TDATA_WIDTH+:REAL_EMTY];
    assign m_axis_tlast = ram_rdata[(TDATA_WIDTH+REAL_EMTY)+:1];

    always @(posedge m_clk ) begin
        if(ram_waddr_cdc == ram_raddr)
            ram_empty <= 1'b1;
        else 
            ram_empty <= 1'b0;
    end

    generate
        if(TUSER_WIDTH == 0)begin 
            assign ram_wdata    = {s_axis_tlast,s_ram_temty,s_axis_tdata};
        end else begin 
            assign ram_wdata    = {s_axis_tuser,s_axis_tlast,s_ram_temty,s_axis_tdata};
            assign m_axis_tuser = ram_rdata[(TDATA_WIDTH+REAL_EMTY+1)+:TUSER_WIDTH];
        end 

        if(KEEP_EN == "ON")begin 
            assign s_ram_temty   = keep2emty(s_axis_tkeep);
            assign m_axis_tkeep  = emty2keep(m_axis_temty);
        end else begin 
            assign s_ram_temty   = s_axis_temty;
        end  

        if(CLOCKING_MODE == "SCFIFO" || CLOCKING_MODE == "scfifo")begin 
            assign ram_raddr_cdc = ram_raddr;
            assign ram_waddr_cdc = ram_waddr;
        end else begin 
            reg                     sr_cdc_req;
            wire                    sr_cdc_resp;
            wire                    mr_cdc_req;
            reg                     mr_cdc_resp;
            wire    [ADDR_WTH-1:0]  mr_cdc_data;
            reg     [ADDR_WTH-1:0]  mr_cdc_data_reg;
            reg                     sw_cdc_req;
            wire                    sw_cdc_resp;
            wire                    mw_cdc_req;
            reg                     mw_cdc_resp;
            wire    [ADDR_WTH-1:0]  mw_cdc_data;
            reg     [ADDR_WTH-1:0]  mw_cdc_data_reg;
            //ram_raddr的时钟域转换
            always @(posedge m_clk) begin
                if(!s_aresetn)
                    sr_cdc_req <= 1'b0;
                else if(sr_cdc_resp)
                    sr_cdc_req <= 1'b0;
                else 
                    sr_cdc_req <= 1'b1;
            end
            data_cdc#(.REQ_W(ADDR_WTH))raddr_cdc_inst(.s_clk(m_clk),.s_rstn(s_aresetn),.s_req(sr_cdc_req),.s_data(ram_raddr),  .s_resp(sr_cdc_resp),
                                                      .m_clk(s_clk),.m_rstn(s_aresetn),.m_req(mr_cdc_req),.m_data(mr_cdc_data),.m_resp(mr_cdc_resp));
            always @(posedge s_clk ) begin
                if(!s_aresetn)
                    mr_cdc_resp <= 1'b0;
                else if(mr_cdc_resp & mr_cdc_req)
                    mr_cdc_resp <= 1'b0;
                else if(mr_cdc_req)
                    mr_cdc_resp <= 1'b1;
            end

            always @(posedge s_clk ) begin
                if(!s_aresetn)
                    mr_cdc_data_reg <= {ADDR_WTH{1'b0}};
                else if(mr_cdc_resp & mr_cdc_req)
                    mr_cdc_data_reg <= mr_cdc_data;
            end
            assign ram_raddr_cdc = mr_cdc_data_reg;
            //ram_waddr的时钟域转换
            always @(posedge s_clk) begin
                if(!s_aresetn)
                    sw_cdc_req <= 1'b0;
                else if(sw_cdc_resp)
                    sw_cdc_req <= 1'b0;
                else 
                    sw_cdc_req <= 1'b1;
            end
            data_cdc#(.REQ_W(ADDR_WTH))waddr_cdc_inst(.s_clk(s_clk),.s_rstn(s_aresetn),.s_req(sw_cdc_req),.s_data(last_waddr), .s_resp(sw_cdc_resp),
                                                      .m_clk(m_clk),.m_rstn(s_aresetn),.m_req(mw_cdc_req),.m_data(mw_cdc_data),.m_resp(mw_cdc_resp));
            always @(posedge m_clk ) begin
                if(!s_aresetn)
                    mw_cdc_resp <= 1'b0;
                else if(mw_cdc_resp & mw_cdc_req)
                    mw_cdc_resp <= 1'b0;
                else if(mw_cdc_req)
                    mw_cdc_resp <= 1'b1;
            end

            always @(posedge m_clk ) begin
                if(!s_aresetn)
                    mw_cdc_data_reg <= {ADDR_WTH{1'b0}};
                else if(mw_cdc_resp & mw_cdc_req)
                    mw_cdc_data_reg <= mw_cdc_data;
            end
            assign ram_waddr_cdc = mw_cdc_data_reg;
        end 

        if(PACKET_FIFO == "FALSE" || PACKET_FIFO == "false")begin 
            reg        eop_pempty_reg;

            assign eop_empty  = 1'b0;
            assign ram_drop   = 1'b0;

            always @(posedge m_clk) begin
                if(ram_waddr_cdc > ram_raddr & ram_waddr_cdc > ram_raddr + 5)
                    eop_pempty_reg <= 1'b0;
                else if(ram_waddr_cdc < ram_raddr & ram_waddr_cdc+2**ADDR_WTH > ram_raddr + 5)
                    eop_pempty_reg <= 1'b0;
                else 
                    eop_pempty_reg <= 1'b1;
            end

            assign eop_pempty = eop_pempty_reg;
            assign eop_flag   = 1'b0;
        end else begin 
            wire            eop_wen;
            wire            eop_ren;
            wire            data_eop;
            assign eop_wen  = ram_wen & s_axis_tlast & (!ram_drop);
            assign data_eop = ram_rdata[(TDATA_WIDTH+REAL_EMTY)+:1];
            assign eop_ren  = m_axis_tvalid & m_axis_tready & data_eop;
            assign eop_flag = m_axis_tvalid & m_axis_tready & data_eop;
            assign ram_drop = s_axis_drop;
            
            if(CLOCKING_MODE == "SCFIFO" || CLOCKING_MODE == "scfifo")begin 
                scfifo #(
                    .add_ram_output_register    ("OFF"          ),
                    .almost_empty_value         (4              ),
                    .almost_full_value          (ALMOST_AFULL   ),
                    .enable_ecc                 ("FALSE"        ),
                    .intended_device_family     ("Agilex 7"     ),
                    .lpm_hint                   ("RAM_BLOCK_TYPE=MLAB" ),
                    .lpm_numwords               (FIFO_DEPTH     ),
                    .lpm_showahead              ("ON"           ),
                    .lpm_type                   ("scfifo"       ),
                    .lpm_width                  (1              ),
                    .lpm_widthu                 ($clog2(FIFO_DEPTH) ),
                    .overflow_checking          ("ON"           ),
                    .underflow_checking         ("ON"           ),
                    .use_eab                    ("ON"           ) 
                )u1_eop_fifo (
                    .aclr                       (~s_aresetn     ),
                    .clock                      (s_clk          ),
                    .data                       (0              ),
                    .rdreq                      (eop_ren        ),
                    .wrreq                      (eop_wen        ),
                    .almost_empty               (eop_pempty     ),
                    .almost_full                (               ),
                    .empty                      (eop_empty      ),
                    .full                       (               ),
                    .q                          (               ),
                    .usedw                      (               ),
                    .eccstatus                  (               ),
                    .sclr                       (1'b0           )
                );
            end else begin 
                wire      [ADDR_WTH-1:0] eop_num;
                assign eop_pempty = eop_num > 4 ? 1'b0 : 1'b1;
                dcfifo #(
                    .enable_ecc                 ("FALSE"        ),
                    .intended_device_family     ("Agilex 7"     ),
                    .lpm_hint                   ("RAM_BLOCK_TYPE=MLAB"),
                    .lpm_numwords               (FIFO_DEPTH     ),
                    .lpm_showahead              ("ON"           ),
                    .lpm_type                   ("dcfifo"       ),
                    .lpm_width                  (1              ),
                    .lpm_widthu                 ($clog2(FIFO_DEPTH)),
                    .overflow_checking          ("ON"           ),
                    .rdsync_delaypipe           (5              ),
                    .read_aclr_synch            ("ON"           ),
                    .underflow_checking         ("ON"           ),
                    .use_eab                    ("ON"           ),
                    .write_aclr_synch           ("ON"           ),
                    .wrsync_delaypipe           (5              )
                )u1_eop_fifo(   
                    .aclr                       (~s_aresetn         ),
                    .data                       (1'b0               ),
                    .rdclk                      (m_clk              ),
                    .rdreq                      (eop_ren            ),
                    .wrclk                      (s_clk              ),
                    .wrreq                      (eop_wen            ),
                    .q                          (                   ),
                    .rdempty                    (eop_empty          ),
                    .rdusedw                    (                   ),
                    .wrfull                     (                   ),
                    .wrusedw                    (eop_num            ),
                    .eccstatus                  (                   ),
                    .rdfull                     (                   ),
                    .wrempty                    (                   )
                );
            end  


        end 
    endgenerate

    ram#(
        .ram_block_type                 (FIFO_TYPE          ),
        .outdata_b_reg                  ("UNUSED"           ),
        .widthad_a                      (ADDR_WTH           ),
        .widthad_b                      (ADDR_WTH           ),
        .width_a                        (REAL_WIDTH         ),
        .width_b                        (REAL_WIDTH         )
    )   
    ram_inst_u  
    (   
        .data                           (ram_wdata          ),
        .rdaddress                      (ram_raddr          ),
        .rdclock                        (m_clk              ),
        .rden                           (ram_ren            ),
        .wraddress                      (ram_waddr          ),
        .wrclock                        (s_clk              ),
        .wren                           (ram_wen            ),
        .q                              (ram_rdata          )
    );

    function [REAL_EMTY-1:0]      keep2emty;
        input [TDATA_WIDTH/8-1:0]   data_in;
        integer i;
        begin : swap
            keep2emty = 0;
            for (i=0;i<REAL_EMTY/8;i=i+1)begin 
                if(~data_in[i])
                    keep2emty = REAL_EMTY/8-i;
            end  
        end
    endfunction

    function [TDATA_WIDTH/8-1:0]    emty2keep;
        input [REAL_EMTY-1:0]       data_in;
        integer i;
        begin : swap
            emty2keep = {TDATA_WIDTH/8{1'b1}}>>data_in;
        end
    endfunction

    
endmodule

module data_cdc#(
        parameter       REQ_W               =  10
    ) (
        input   wire                        s_clk,
        input   wire                        s_rstn,
        input   wire                        s_req,
        input   wire    [REQ_W-1:0]         s_data,
        output  reg                         s_resp,
        input   wire                        m_clk,
        input   wire                        m_rstn,
        output  reg                         m_req,
        output  reg     [REQ_W-1:0]         m_data,
        input   wire                        m_resp
    );
        localparam      S_IDLE              = 2'b00;
        localparam      S_WAIT              = 2'b01;
        localparam      S_END               = 2'b10;

        localparam      M_IDLE              = 2'b00;
        localparam      M_WAIT              = 2'b01;
        localparam      M_END               = 2'b10;
        reg             [1:0]               s_cur_sta;
        reg             [1:0]               s_nxt_sta;
        reg             [1:0]               m_cur_sta;
        reg             [1:0]               m_nxt_sta;
        reg             [3:0]               s_req_flag;
        reg             [2:0]               m_resp_flag;
        reg             [REQ_W-1:0]         s_data_reg;

        always @(posedge s_clk ) begin
            if(!s_rstn)
                s_cur_sta <= S_IDLE;
            else  
                s_cur_sta <= s_nxt_sta;
        end

        always @(*) begin
            case (s_cur_sta)
                S_IDLE:
                    if(s_req) 
                        s_nxt_sta = S_WAIT;
                    else  
                        s_nxt_sta = S_IDLE;
                S_WAIT:
                    if(m_resp_flag[2])
                        s_nxt_sta = S_END; 
                    else 
                        s_nxt_sta = S_WAIT;
                S_END:
                    if(~m_resp_flag[2])
                        s_nxt_sta = S_IDLE;
                    else 
                        s_nxt_sta = S_END;
                default: s_nxt_sta = S_IDLE;
            endcase
        end

        always @(posedge s_clk ) begin
            if(s_req & s_resp)
                s_data_reg <= s_data;
        end

        always @(posedge s_clk ) begin
            if(s_cur_sta == S_IDLE & s_req & ~s_resp)
                s_resp <= 1'b1;
            else  
                s_resp <= 1'b0;
        end


        always @(posedge s_clk ) begin
            if(s_cur_sta == S_IDLE)
                s_req_flag[0] <= 1'b0;
            else if(s_cur_sta == S_WAIT & m_resp_flag[2])
                s_req_flag[0] <= 1'b0;
            else if(s_cur_sta == S_WAIT & s_req & s_resp)
                s_req_flag[0] <= 1'b1;
        end

        always @(posedge s_clk ) begin
            m_resp_flag[2:1] <= m_resp_flag[1:0];
        end

        always @(posedge m_clk) begin
            if(!m_rstn)
                m_cur_sta <= M_IDLE;
            else  
                m_cur_sta <= m_nxt_sta;
        end
    
        always @(*) begin
            case (m_cur_sta)
                M_IDLE:
                    if(s_req_flag[2] & (!s_req_flag[3]))
                        m_nxt_sta = M_WAIT;
                    else 
                        m_nxt_sta = M_IDLE;
                M_WAIT:
                    if(m_resp)
                        m_nxt_sta = M_END;
                    else 
                        m_nxt_sta = M_WAIT;
                M_END:
                    if(~s_req_flag[2])
                        m_nxt_sta = M_IDLE;
                    else 
                        m_nxt_sta = M_END;
                default: m_nxt_sta = M_IDLE;
            endcase
        end

        always @(posedge m_clk ) begin
            if(m_resp & m_req)
                m_req <= 1'b0;
            else if(s_req_flag[2] & (!s_req_flag[3]))
                m_req <= 1'b1;
            else if(m_cur_sta == M_IDLE) 
                m_req <= 1'b0;
        end

        always @(posedge m_clk ) begin
             s_req_flag[3:1] <= s_req_flag[2:0];
        end

        always @(posedge m_clk ) begin
            if(m_cur_sta == M_IDLE)
                m_resp_flag[0] <= 1'b0;
            else if(m_cur_sta == M_END)
                m_resp_flag[0] <= 1'b1;
        end

        always @(posedge m_clk ) begin
            if(s_req_flag[2] & (!s_req_flag[3]))
                m_data <= s_data_reg;
        end
    endmodule

