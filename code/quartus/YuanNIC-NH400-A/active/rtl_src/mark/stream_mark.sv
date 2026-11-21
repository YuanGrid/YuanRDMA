`resetall
`default_nettype none
`timescale 1ns / 1ps
module stream_mark #(
    parameter       DATA_WIDTH                      = 1024,
    parameter       FLOW_NUM                        = 10240,
    parameter       STREAM_ID_W                     = 13 
)(
    input   wire                                    axis_aclk,
    input   wire                                    rst_n,
    input   wire                                    s_axis_tvalid,
    input   wire    [DATA_WIDTH-1:0]                s_axis_tdata,
    input   wire                                    s_axis_tlast,
    input   wire    [$clog2(DATA_WIDTH/8)-1:0]      s_axis_tusef,
    input   wire                                    s_axis_tuser_sop,
    input   wire    [15:0]                          s_axis_tuser_id,
    input   wire                                    s_axis_tuser_stamp_en,
    output  wire                                    m_axis_tvalid,
    output  wire    [DATA_WIDTH-1:0]                m_axis_tdata,
    output  wire                                    m_axis_tlast,
    output  wire    [$clog2(DATA_WIDTH/8)-1:0]      m_axis_tusef,
    input   wire                                    m_axis_tready,
    input   wire    [63:0]                          time_stamp
);
    localparam AUTH_CODE = 16'h4e54;

    reg     [DATA_WIDTH-1:0]                        d0_s_axis_tdata[7:0];
    reg     [$clog2(DATA_WIDTH/8)-1:0]              d0_s_axis_tusef[7:0];
    reg                                             d0_s_axis_tuser_sop[7:0];
    reg     [15:0]                                  d0_s_axis_tuser_id[7:0];
    reg                                             d0_tuser_stamp_en[7:0];
    reg     [7:0]                                   d0_s_axis_tvalid;
    reg                                             d0_s_axis_tlast[7:0];
    reg     [63:0]                                  d0_s_axis_time[6:0];
    wire                                            pkt_time_delay_type_en ;
    reg     [31:0]                                  d3_stream_id_cnt[4:3];
    reg                                             stream_id_rd[2:0] ;
    reg     [STREAM_ID_W-1:0]                       stream_id_raddr[2:0] ;
    wire    [31:0]                                  stream_id_rdata[1:1];
    reg                                             stream_id_wr[3:2] ;
    reg     [STREAM_ID_W-1:0]                       stream_id_waddr[3:2] ;
    reg     [31:0]                                  stream_id_wdata[3:2];
    reg                                             stream_id_rd_d1;
    reg                                             stream_id_rd_reg_d1;
    reg     [31:0]                                  stream_id_rdata_reg_d1;
    reg     [127:0]                                 d5_mark_data[6:5];
    reg     [$clog2(DATA_WIDTH/8):0]                d4_vld_byte[6:4];
    reg     [16:0]                                  d1_s_axis_cksm[2:0];
    reg     [18:0]                                  d2_s_axis_cksm;
    reg     [19:0]                                  d3_s_axis_cksm;
    reg     [15:0]                                  d4_s_axis_cksm;
    reg     [63:0]                                  d1_s_axis_time;
    reg     [63:0]                                  d0_user_time;
    reg     [63:0]                                  d1_user_time;
    wire    [2*16-1:0]                              d2_stream_mark_unfixed;
    reg     [15:0]                                  d3_stream_mark_checksum;

    assign pkt_time_delay_type_en = s_axis_tuser_id[STREAM_ID_W];
    always@(posedge axis_aclk)
    begin
        if(!rst_n)begin 
            d0_s_axis_tvalid[7:0]        <= 8'd0;
        end else if(m_axis_tready) begin
            d0_s_axis_tusef[7:0]         <= {d0_s_axis_tusef[6:0],s_axis_tusef};
            d0_s_axis_tuser_sop[7:0]     <= {d0_s_axis_tuser_sop[6:0],s_axis_tuser_sop};
            d0_s_axis_tuser_id[7:0]      <= {d0_s_axis_tuser_id[6:0],s_axis_tuser_id};
            d0_tuser_stamp_en[7:0]       <= {d0_tuser_stamp_en[6:0],s_axis_tuser_stamp_en};
            d0_s_axis_tvalid[7:0]        <= {d0_s_axis_tvalid[6:0],s_axis_tvalid};
            d0_s_axis_tlast[7:0]         <= {d0_s_axis_tlast[6:0],s_axis_tlast};

            if(s_axis_tvalid & s_axis_tuser_sop && pkt_time_delay_type_en == 1'd0)
                d0_s_axis_time[0] <= time_stamp;
            else if(s_axis_tvalid & s_axis_tlast && pkt_time_delay_type_en == 1'd1)
                d0_s_axis_time[0] <= time_stamp;

            d0_s_axis_time[6:1]   <= d0_s_axis_time[5:0];
        end
    end

    always@(posedge axis_aclk)begin
        if(m_axis_tready)begin 
            stream_id_rd[2:0]    <= {stream_id_rd[1:0],s_axis_tuser_sop&s_axis_tvalid};
            stream_id_raddr[2:0] <= {stream_id_raddr[1:0],s_axis_tuser_id[STREAM_ID_W-1:0]};
            stream_id_wr[3:2]    <= {stream_id_wr[2],stream_id_rd[1]};
            stream_id_waddr[3:2] <= {stream_id_waddr[2],stream_id_raddr[1]};
        end 
    end

    always @(posedge axis_aclk ) begin
        if(m_axis_tready & stream_id_rd[1] && stream_id_wr[2] && stream_id_raddr[1] == stream_id_waddr[2])
            stream_id_wdata[2] <= stream_id_wdata[2] + 1'b1;
        else if(m_axis_tready & stream_id_rd[1] && stream_id_wr[3] && stream_id_raddr[1] == stream_id_waddr[3])
            stream_id_wdata[2] <= stream_id_wdata[3] + 1'b1;
        else if(m_axis_tready & stream_id_rd_reg_d1)
            stream_id_wdata[2] <= stream_id_rdata_reg_d1 + 1'b1;
        else if(m_axis_tready)
            stream_id_wdata[2] <= stream_id_rdata[1] + 1'b1;
        if(m_axis_tready)
            stream_id_wdata[3] <= stream_id_wdata[2];    
    end

    always @(posedge axis_aclk ) begin
        stream_id_rd_d1 <= stream_id_rd[0] & m_axis_tready;

        if(!rst_n)
            stream_id_rd_reg_d1 <= 1'b0;
        else if(~m_axis_tready & stream_id_rd_d1)
            stream_id_rd_reg_d1 <= 1'b1;
        else if(stream_id_rd[1] & m_axis_tready)
            stream_id_rd_reg_d1 <= 1'b0;

        if(stream_id_rd_d1)
            stream_id_rdata_reg_d1 <= stream_id_rdata[1];
    end

    ram#(
        .ram_block_type     ("M20K"         ),
        .widthad_a          (STREAM_ID_W    ),
        .widthad_b          (STREAM_ID_W    ),
        .numwords_a         (FLOW_NUM       ),
        .numwords_b         (FLOW_NUM       ),
        .width_a            (32             ),
        .width_b            (32             )
    )
    stream_id_ram
    (
        .wrclock            (axis_aclk          ),
        .wren               (stream_id_wr[2]    ),
        .wraddress          (stream_id_waddr[2] ),
        .data               (stream_id_wdata[2] ),
        .rdclock            (axis_aclk          ),
        .rden               (stream_id_rd[0]    ),
        .rdaddress          (stream_id_raddr[0] ),
        .q                  (stream_id_rdata[1] )
    );

    always @(posedge axis_aclk ) begin
        if(m_axis_tready)begin 
            d1_s_axis_cksm[0]  <=d0_s_axis_time[0][0*16+:16] + d0_s_axis_time[0][1*16+:16] ;
            d1_s_axis_cksm[1]  <=d0_s_axis_time[0][2*16+:16] + d0_s_axis_time[0][3*16+:16] ;
            d1_s_axis_cksm[2]  <=d0_s_axis_tuser_id[0][15:0] + AUTH_CODE ;
            d2_s_axis_cksm     <=d1_s_axis_cksm[0]           + d1_s_axis_cksm[1] + d1_s_axis_cksm[2];
            if(stream_id_wr[2])
                d3_s_axis_cksm <=d2_s_axis_cksm              + 16'(stream_id_wdata[2] - 1'b1);
            else 
                d3_s_axis_cksm <=d2_s_axis_cksm              + d3_stream_id_cnt[3][15:0];
            d4_s_axis_cksm     <=d3_s_axis_cksm[19:16]+d3_s_axis_cksm[15:0];
        end 
    end

    always@(posedge axis_aclk)
    begin
        if(m_axis_tready == 1'b1 && d0_s_axis_tlast[4] && d0_tuser_stamp_en[4] == 1'b1) begin
           d5_mark_data[5] <= swap_endian_w128({d0_s_axis_tuser_id[4][15:0],AUTH_CODE,d3_stream_id_cnt[4][15:0],~d4_s_axis_cksm,d0_s_axis_time[4]});
        end

        if(m_axis_tready == 1'b1)begin
            d5_mark_data[6] <= d5_mark_data[5];
        end
    end

    always@(posedge axis_aclk)
    begin
        if(m_axis_tready == 1'b1 && stream_id_wr[2] == 1'b1) begin
            d3_stream_id_cnt[3] <= stream_id_wdata[2] - 1'b1;
        end
        if(m_axis_tready == 1'b1)
            d3_stream_id_cnt[4] <= d3_stream_id_cnt[3];
    end

    always @(posedge axis_aclk ) begin
        if(m_axis_tready)
            d0_s_axis_tdata[5:0] <= {d0_s_axis_tdata[4:0],s_axis_tdata};

        if(m_axis_tready & d0_s_axis_tusef[3] == 0)
            d4_vld_byte[6:4] <= {d4_vld_byte[5:4],8'd128};
        else if(m_axis_tready)
            d4_vld_byte[6:4] <= {d4_vld_byte[5:4],d0_s_axis_tusef[3]};
    end

    generate
        for (genvar i=0 ; i<(DATA_WIDTH/8) ; i=i+1) begin
            always @(posedge axis_aclk) begin
                if(m_axis_tready == 1'b1 && d0_s_axis_tlast[5] && d0_tuser_stamp_en[5] == 1'b1 && i+8'd16 >= d4_vld_byte[5])
                    d0_s_axis_tdata[6][i*8+:8] <= d5_mark_data[5][4'(i+8'd16-d4_vld_byte[5])*8+:8];
                else if(m_axis_tready == 1'b1)
                    d0_s_axis_tdata[6][i*8+:8] <= d0_s_axis_tdata[5][i*8+:8];
            end

            always @(posedge axis_aclk) begin
                if(m_axis_tready == 1'b1 && d0_s_axis_tlast[5] && (!d0_s_axis_tlast[6]) && d0_tuser_stamp_en[6] == 1'b1 && d4_vld_byte[5]<8'd16 && i>=7'd112+d4_vld_byte[5])//112=128-16
                    d0_s_axis_tdata[7][i*8+:8] <= d5_mark_data[5][4'(i-7'd112-d4_vld_byte[5])*8+:8];
                else if(m_axis_tready == 1'b1)
                    d0_s_axis_tdata[7][i*8+:8] <= d0_s_axis_tdata[6][i*8+:8];
            end
        end
    endgenerate

    assign m_axis_tdata  = d0_s_axis_tdata[7];
    assign m_axis_tusef  = d0_s_axis_tusef[7];
    assign m_axis_tlast  = d0_s_axis_tlast[7];
    assign m_axis_tvalid = d0_s_axis_tvalid[7];
    

    function [15:0] checksum_fix;
        input [31:0] data_in;
        reg [31:0] cur_data;
        integer i;
        reg carry ;
        reg [16:0] add_1st;
        reg [17:0] add_2nd;
        reg [15:0] dout;
        begin : calc_block
            cur_data = data_in;
            add_1st  = cur_data[16 +:16] + cur_data[0+:16];
            dout     = add_1st[15:0] + add_1st[16];
            checksum_fix = ~dout[15:0];
        end
    endfunction

    function [127:0] swap_endian_w128;
        input [127:0] data_in;
        integer i;
        reg [127:0] temp;
        begin
            for(i=0;i<16;i=i+1)begin 
                temp[i*8+:8] = data_in[(15-i)*8+:8];
            end  
            swap_endian_w128 = temp;
        end
    endfunction

    function [15:0] swap_endian_w16;
        input [15:0] data_in;
        reg    [15:0] temp;
        begin
            temp[7:0] = data_in[15:8];
            temp[15:8] = data_in[7:0];
            swap_endian_w16 = temp;
        end
    endfunction

endmodule
`resetall
