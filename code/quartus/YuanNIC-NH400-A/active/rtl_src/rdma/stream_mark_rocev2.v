`resetall
`default_nettype none
`timescale 1ns / 1ps
module stream_mark_rocev2 #(parameter DATA_WIDTH = 1024,
                     parameter KEEP_WIDTH = 128,
                     parameter EMPTY_WIDTH = 7)
    (
    input  wire                   axis_aclk,
    input  wire                   rst_n,

    input  wire                   s_axis_tvalid,
    input  wire [DATA_WIDTH-1:0]  s_axis_tdata,
    input  wire                   s_axis_tlast,
    input  wire [KEEP_WIDTH-1:0]  s_axis_tkeep,
    input  wire [11-1:0]          s_axis_tchannel,
    input  wire                   s_axis_tuser_sop,
    input  wire                   s_axis_tuser_ipv6,
    input  wire                   s_axis_tuser_insert,
    input  wire [13:0]            s_axis_tuser_len,
    input  wire                   s_axis_tuser_stamp_en,
    output wire                   s_axis_tready,

    output wire                   m_axis_tvalid,
    output wire [DATA_WIDTH-1:0]  m_axis_tdata,
    output wire                   m_axis_tlast,
    output wire [EMPTY_WIDTH-1:0]  m_axis_tkeep,
    output wire [11-1:0]          m_axis_tchannel,
    input  wire                   m_axis_tready,

    input  wire   [63:0]          time_stamp

);
    reg [DATA_WIDTH-1:0] d0_tdata = 0;
    reg [DATA_WIDTH-1:0] d1_tdata = 0;
    reg [DATA_WIDTH-1:0] d2_tdata = 0;
    reg [DATA_WIDTH-1:0] d3_tdata = 0;
    reg [DATA_WIDTH-1:0] d4_tdata = 0;

    reg [KEEP_WIDTH-1:0] d0_tkeep = 0;
    reg [EMPTY_WIDTH-1:0] d1_tkeep = 0;
    reg [EMPTY_WIDTH-1:0] d2_tkeep = 0;
    reg [EMPTY_WIDTH-1:0] d3_tkeep = 0;
    reg [EMPTY_WIDTH-1:0] d4_tkeep = 0;

    reg [11-1:0]         d0_tchan = 0;
    reg [11-1:0]         d1_tchan = 0;
    reg [11-1:0]         d2_tchan = 0;
    reg [11-1:0]         d3_tchan = 0;
    reg [11-1:0]         d4_tchan = 0;

    reg                  d0_tuser_sop = 0;
    reg                  d1_tuser_sop = 0;
    reg                  d2_tuser_sop = 0;
    reg                  d3_tuser_sop = 0;
    reg                  d4_tuser_sop = 0;

    reg [13:0]           d0_tuser_len = 0;
    reg [13:0]           d1_tuser_len = 0;
    reg [13:0]           d2_tuser_len = 0;
    reg [13:0]           d3_tuser_len = 0;
    reg [13:0]           d4_tuser_len = 0;

    reg                  d0_tuser_stamp_en = 0;
    reg                  d1_tuser_stamp_en = 0;
    reg                  d2_tuser_stamp_en = 0;
    reg                  d3_tuser_stamp_en = 0;
    reg                  d4_tuser_stamp_en = 0;

    reg                  d0_tvalid = 0;
    reg                  d1_tvalid = 0;
    reg                  d2_tvalid = 0;
    reg                  d3_tvalid = 0;
    reg                  d4_tvalid = 0;

    reg                  d0_tlast = 0;
    reg                  d1_tlast = 0;
    reg                  d2_tlast = 0;
    reg                  d3_tlast = 0;
    reg                  d4_tlast = 0;

    reg  [13:0]          d0_mark_pos = 0;
    reg  [13:0]          d1_mark_pos = 0;
    reg  [13:0]          d2_mark_pos = 0;
    reg  [13:0]          d3_mark_pos = 0;
    reg  [13:0]          d4_mark_pos = 0;


    reg                 d0_tuser_insert = 0 ;
    reg                 d1_tuser_insert = 0 ;
    reg                 d2_tuser_insert = 0 ;
    reg                 d3_tuser_insert = 0 ;
    reg                 d4_tuser_insert = 0 ;

    reg [5:0]           sub_empty [3:0];
    reg [3:0]           sub_has_zero;

    always @(posedge axis_aclk) 
    begin
        if(m_axis_tready) 
        begin
            if( s_axis_tuser_sop & s_axis_tlast) begin
                if(s_axis_tkeep[7])
                    d0_tkeep <= 7'd0;
                else
                    d0_tkeep <= 128-s_axis_tkeep[6:0];
            end else if(s_axis_tuser_sop & !s_axis_tlast) begin
                d0_tkeep <= 7'd0;
            end else if(!s_axis_tuser_sop & s_axis_tlast) begin
                if(s_axis_tkeep[7:0] == 8'h80)
                    d0_tkeep <= 7'd0;
                else
                    d0_tkeep <= 128-s_axis_tkeep[6:0];                
            end else begin
                d0_tkeep <= 7'd0;
            
            end
        end

    end

    always @(posedge axis_aclk) begin
        if(m_axis_tready) begin     
                d1_tkeep <= d0_tkeep;
            end
    end

    always@(posedge axis_aclk)
    begin
        if(m_axis_tready) begin
            {d0_tchan,d0_tvalid,d0_tlast}<= {s_axis_tchannel,s_axis_tvalid,s_axis_tlast};
            {d1_tchan,d1_tvalid,d1_tlast}<= {d0_tchan,d0_tvalid,d0_tlast};
            {d2_tchan,d2_tvalid,d2_tlast}<= {d1_tchan,d1_tvalid,d1_tlast};
            {d3_tchan,d3_tvalid,d3_tlast}<= {d2_tchan,d2_tvalid,d2_tlast};
            {d4_tchan,d4_tvalid,d4_tlast}<= {d3_tchan,d3_tvalid,d3_tlast};
        end
    end

    always@(posedge axis_aclk)
        if(m_axis_tready) 
            {d4_tkeep,d3_tkeep,d2_tkeep}<= {d3_tkeep,d2_tkeep,d1_tkeep};  



    always@(posedge axis_aclk)
    begin
        if(m_axis_tready) begin
            d0_tuser_len <= s_axis_tuser_len;
            d1_tuser_len <= d0_tuser_len;
            d2_tuser_len <= d1_tuser_len;
            d3_tuser_len <= d2_tuser_len;
            d4_tuser_len <= d3_tuser_len;
        end
    end


    always@(posedge axis_aclk)
    begin
        if(m_axis_tready) begin
            d0_tuser_stamp_en <= s_axis_tuser_stamp_en;
            d1_tuser_stamp_en <= d0_tuser_stamp_en;
            d2_tuser_stamp_en <= d1_tuser_stamp_en;
            d3_tuser_stamp_en <= d2_tuser_stamp_en;
            d4_tuser_stamp_en <= d3_tuser_stamp_en;
        end
    end

    always@(posedge axis_aclk)
    begin
        if(m_axis_tready) begin
            d0_tuser_insert <= s_axis_tuser_insert;
            d1_tuser_insert <= d0_tuser_insert;
            d2_tuser_insert <= d1_tuser_insert;
            d3_tuser_insert <= d2_tuser_insert;
            d4_tuser_insert <= d3_tuser_insert;
        end
    end

    always@(posedge axis_aclk)
    begin
        if(m_axis_tready) begin
            d0_mark_pos <= s_axis_tuser_len - 5'd12; // 8(timestamp)+4(icrc)
            d1_mark_pos <= d0_mark_pos;
            d2_mark_pos <= d1_mark_pos;
            d3_mark_pos <= d2_mark_pos;
            d4_mark_pos <= d3_mark_pos;
        end
    end

    (*mark_debug="true"*)reg [7:0] packet_cnt;
    always@(posedge axis_aclk)
    begin
        if(m_axis_tready & s_axis_tuser_sop)
            packet_cnt <= 8'd0;
        else if(m_axis_tready & s_axis_tvalid)
            packet_cnt <= packet_cnt + 8'd1;
    end
    //reg [5:0] d0_packet_cnt;
    reg [7:0] d1_packet_cnt;
    reg [7:0] d2_packet_cnt;
    reg [7:0] d3_packet_cnt;
    reg [7:0] d4_packet_cnt;

    always@(posedge axis_aclk)
    begin
        if(m_axis_tready) begin
            d1_packet_cnt <= packet_cnt;
            d2_packet_cnt <= d1_packet_cnt;
            d3_packet_cnt <= d2_packet_cnt;
            d4_packet_cnt <= d3_packet_cnt;
        end
    end

    always@(posedge axis_aclk)
    begin
        if(m_axis_tready) begin
            d0_tdata <= s_axis_tdata;
            d1_tdata <= d0_tdata;
            d2_tdata <= d1_tdata;
        end
    end

    reg [95:0] d2_mark_data;
    reg [95:0] d3_mark_data;
    reg [95:0] d4_mark_data;

    function [95:0] swap_endian_w96;
        input [95:0] data_in;
        reg [95:0] temp;
        begin
            temp[7:0]   = data_in[95:88];
            temp[15:8]  = data_in[87:80];
            temp[23:16] = data_in[79:72];
            temp[31:24] = data_in[71:64];
            temp[39:32] = data_in[63:56];
            temp[47:40] = data_in[55:48];
            temp[55:48] = data_in[47:40];
            temp[63:56] = data_in[39:32];
            temp[71:64] = data_in[31:24];
            temp[79:72] = data_in[23:16];
            temp[87:80] = data_in[15:8];
            temp[95:88] = data_in[7:0];
            swap_endian_w96 = temp;
        end
    endfunction

    function [63:0] swap_endian_w64;
        input [63:0] data_in;
        reg [63:0] temp;
        begin
            temp[7:0]   = data_in[63:56];
            temp[15:8]  = data_in[55:48];
            temp[23:16] = data_in[47:40];
            temp[31:24] = data_in[39:32];
            temp[39:32] = data_in[31:24];
            temp[47:40]  = data_in[23:16];
            temp[55:48]  = data_in[15:8];
            temp[63:56]  = data_in[7:0];
            swap_endian_w64 = temp;
        end
    endfunction

    function [15:0] swap_endian_w16;
        input [15:0] data_in;
        reg [15:0] temp;
        begin
            temp[7:0] = data_in[15:8];
            temp[15:8] = data_in[7:0];
            swap_endian_w16 = temp;
        end
    endfunction

    wire [8*12-1:0] stream_mark_unfixed;

    // B6420：插入位置命中条件提前一级算好并寄存（d2_hit_q / d3_hit_q）。
    // B6418 pld_clkout：u82 的 filled[1]（= 本模块 m_axis_tready）→ 包计数比较 → 128 路位置选择 → d4_tdata，
    // 3 级逻辑，52 个端点 −0.134；本模块内部 18 个端点。各级寄存器都只在 m_axis_tready 时整体前移（锁步），
    // 所以「上一级的比较结果随数据一起前移一级」与「本级当场比较」逐拍等价。
    reg d2_hit_q = 1'b0;    // == (d2_packet_cnt == d2_mark_pos[13:7]+1) && d2_tuser_insert && d2_tuser_stamp_en
    reg d3_hit_q = 1'b0;    // == (d3_packet_cnt == d3_mark_pos[13:7])   && d3_tuser_insert && d3_tuser_stamp_en
    always@(posedge axis_aclk)
    begin
        if(m_axis_tready == 1'b1) begin
            d2_hit_q <= (d1_packet_cnt == d1_mark_pos[13:7]+1'b1) && d1_tuser_insert == 1'b1 && d1_tuser_stamp_en == 1'b1;
            d3_hit_q <= (d2_packet_cnt == d2_mark_pos[13:7])      && d2_tuser_insert == 1'b1 && d2_tuser_stamp_en == 1'b1;
        end
    end

    always@(posedge axis_aclk)
    begin
        if(m_axis_tready == 1'b1 && d1_packet_cnt == d1_mark_pos[13:7] && d1_tuser_stamp_en == 1'b1) begin //128B per beat
           d2_mark_data <= swap_endian_w96({time_stamp,32'd0});
        end
        if(m_axis_tready == 1'b1)begin
            d3_mark_data <= d2_mark_data;
            d4_mark_data <= d3_mark_data;
        end
    end

    always@(posedge axis_aclk)
    begin
        if(m_axis_tready == 1'b1 && d2_hit_q) begin
            case(d2_mark_pos[6:0])
                7'd117 : d3_tdata <= {504'd0+512'd0,d2_mark_data[95:88]};
                7'd118 : d3_tdata <= {496'd0+512'd0,d2_mark_data[95:80]};
                7'd119 : d3_tdata <= {488'd0+512'd0,d2_mark_data[95:72]};
                7'd120 : d3_tdata <= {480'd0+512'd0,d2_mark_data[95:64]};
                7'd121 : d3_tdata <= {472'd0+512'd0,d2_mark_data[95:56]};
                7'd122 : d3_tdata <= {464'd0+512'd0,d2_mark_data[95:48]};
                7'd123 : d3_tdata <= {456'd0+512'd0,d2_mark_data[95:40]};
                7'd124 : d3_tdata <= {448'd0+512'd0,d2_mark_data[95:32]};
                7'd125 : d3_tdata <= {440'd0+512'd0,d2_mark_data[95:24]};
                7'd126 : d3_tdata <= {432'd0+512'd0,d2_mark_data[95:16]};
                7'd127 : d3_tdata <= {424'd0+512'd0,d2_mark_data[95:8]};
                default : d3_tdata <= d2_tdata;
            endcase
        end else if(m_axis_tready == 1'b1)
            d3_tdata <= d2_tdata;
    end


    always@(posedge axis_aclk)
    begin
        if(m_axis_tready == 1'b1 && d3_hit_q) begin
            case(d3_mark_pos[6:0])
                7'd0  : d4_tdata <= {512'd0,416'd0, d3_mark_data[95:0]               };
                7'd1  : d4_tdata <= {512'd0,408'd0, d3_mark_data[95:0],d3_tdata[7:0] };
                7'd2  : d4_tdata <= {512'd0,400'd0, d3_mark_data[95:0],d3_tdata[15:0]};
                7'd3  : d4_tdata <= {512'd0,392'd0, d3_mark_data[95:0],d3_tdata[23:0]};
                7'd4  : d4_tdata <= {512'd0,384'd0, d3_mark_data[95:0],d3_tdata[31:0]};
                7'd5  : d4_tdata <= {512'd0,376'd0, d3_mark_data[95:0],d3_tdata[39:0]};
                7'd6  : d4_tdata <= {512'd0,368'd0, d3_mark_data[95:0],d3_tdata[47:0]};
                7'd7  : d4_tdata <= {512'd0,360'd0, d3_mark_data[95:0],d3_tdata[55:0]};
                7'd8  : d4_tdata <= {512'd0,352'd0, d3_mark_data[95:0],d3_tdata[63:0]};
                7'd9  : d4_tdata <= {512'd0,344'd0, d3_mark_data[95:0],d3_tdata[71:0]};

                7'd10 : d4_tdata <= {512'd0,336'd0, d3_mark_data[95:0],d3_tdata[79:0]};
                7'd11 : d4_tdata <= {512'd0,328'd0, d3_mark_data[95:0],d3_tdata[87:0]};
                7'd12 : d4_tdata <= {512'd0,320'd0, d3_mark_data[95:0],d3_tdata[95:0]};
                7'd13 : d4_tdata <= {512'd0,312'd0, d3_mark_data[95:0],d3_tdata[103:0]};
                7'd14 : d4_tdata <= {512'd0,304'd0, d3_mark_data[95:0],d3_tdata[111:0]};
                7'd15 : d4_tdata <= {512'd0,296'd0, d3_mark_data[95:0],d3_tdata[119:0]};
                7'd16 : d4_tdata <= {512'd0,288'd0, d3_mark_data[95:0],d3_tdata[127:0]};
                7'd17 : d4_tdata <= {512'd0,280'd0, d3_mark_data[95:0],d3_tdata[135:0]};
                7'd18 : d4_tdata <= {512'd0,272'd0, d3_mark_data[95:0],d3_tdata[143:0]};
                7'd19 : d4_tdata <= {512'd0,264'd0, d3_mark_data[95:0],d3_tdata[151:0]};

                7'd20 : d4_tdata <= {512'd0,256'd0, d3_mark_data[95:0],d3_tdata[159:0]};
                7'd21 : d4_tdata <= {512'd0,248'd0, d3_mark_data[95:0],d3_tdata[167:0]};
                7'd22 : d4_tdata <= {512'd0,240'd0, d3_mark_data[95:0],d3_tdata[175:0]};
                7'd23 : d4_tdata <= {512'd0,232'd0, d3_mark_data[95:0],d3_tdata[183:0]};
                7'd24 : d4_tdata <= {512'd0,224'd0, d3_mark_data[95:0],d3_tdata[191:0]};
                7'd25 : d4_tdata <= {512'd0,216'd0, d3_mark_data[95:0],d3_tdata[199:0]};
                7'd26 : d4_tdata <= {512'd0,208'd0, d3_mark_data[95:0],d3_tdata[207:0]};
                7'd27 : d4_tdata <= {512'd0,200'd0, d3_mark_data[95:0],d3_tdata[215:0]};
                7'd28 : d4_tdata <= {512'd0,192'd0, d3_mark_data[95:0],d3_tdata[223:0]};
                7'd29 : d4_tdata <= {512'd0,184'd0, d3_mark_data[95:0],d3_tdata[231:0]};

                7'd30 : d4_tdata <= {512'd0,176'd0, d3_mark_data[95:0],d3_tdata[239:0]};
                7'd31 : d4_tdata <= {512'd0,168'd0, d3_mark_data[95:0],d3_tdata[247:0]};
                7'd32 : d4_tdata <= {512'd0,160'd0, d3_mark_data[95:0],d3_tdata[255:0]};
                7'd33 : d4_tdata <= {512'd0,152'd0, d3_mark_data[95:0],d3_tdata[263:0]};
                7'd34 : d4_tdata <= {512'd0,144'd0, d3_mark_data[95:0],d3_tdata[271:0]};
                7'd35 : d4_tdata <= {512'd0,136'd0, d3_mark_data[95:0],d3_tdata[279:0]};
                7'd36 : d4_tdata <= {512'd0,128'd0, d3_mark_data[95:0],d3_tdata[287:0]};
                7'd37 : d4_tdata <= {512'd0,120'd0, d3_mark_data[95:0],d3_tdata[295:0]};
                7'd38 : d4_tdata <= {512'd0,112'd0, d3_mark_data[95:0],d3_tdata[303:0]};
                7'd39 : d4_tdata <= {512'd0,104'd0, d3_mark_data[95:0],d3_tdata[311:0]};

                7'd40 : d4_tdata <= {512'd0,96'd0,  d3_mark_data[95:0],d3_tdata[319:0]};
                7'd41 : d4_tdata <= {512'd0,88'd0,  d3_mark_data[95:0],d3_tdata[327:0]};
                7'd42 : d4_tdata <= {512'd0,80'd0,  d3_mark_data[95:0],d3_tdata[335:0]};
                7'd43 : d4_tdata <= {512'd0,72'd0,  d3_mark_data[95:0],d3_tdata[343:0]};
                7'd44 : d4_tdata <= {512'd0,64'd0,  d3_mark_data[95:0],d3_tdata[351:0]};
                7'd45 : d4_tdata <= {512'd0,56'd0,  d3_mark_data[95:0],d3_tdata[359:0]};
                7'd46 : d4_tdata <= {512'd0,48'd0,  d3_mark_data[95:0],d3_tdata[367:0]};
                7'd47 : d4_tdata <= {512'd0,40'd0,  d3_mark_data[95:0],d3_tdata[375:0]};
                7'd48 : d4_tdata <= {512'd0,32'd0,  d3_mark_data[95:0],d3_tdata[383:0]};
                7'd49 : d4_tdata <= {512'd0,24'd0,  d3_mark_data[95:0],d3_tdata[391:0]};

                7'd50 : d4_tdata <= {512'd0,16'd0,  d3_mark_data[95:0],d3_tdata[399:0]};
                7'd51 : d4_tdata <= {512'd0,8'd0,   d3_mark_data[95:0],d3_tdata[407:0]};
                7'd52 : d4_tdata <= {512'd0,        d3_mark_data[95:0], d3_tdata[415:0]};
                7'd53 : d4_tdata <= {504'd0,        d3_mark_data[95:0], d3_tdata[423:0]};
                7'd54 : d4_tdata <= {496'd0,        d3_mark_data[95:0], d3_tdata[431:0]};
                7'd55 : d4_tdata <= {488'd0,        d3_mark_data[95:0], d3_tdata[439:0]};
                7'd56 : d4_tdata <= {480'd0,        d3_mark_data[95:0], d3_tdata[447:0]};
                7'd57 : d4_tdata <= {472'd0,        d3_mark_data[95:0], d3_tdata[455:0]};
                7'd58 : d4_tdata <= {464'd0,        d3_mark_data[95:0], d3_tdata[463:0]};
                7'd59 : d4_tdata <= {456'd0,        d3_mark_data[95:0], d3_tdata[471:0]};

                7'd60 : d4_tdata <= {448'd0,        d3_mark_data[95:0], d3_tdata[479:0]};
                7'd61 : d4_tdata <= {440'd0,        d3_mark_data[95:0], d3_tdata[487:0]};
                7'd62 : d4_tdata <= {432'd0,        d3_mark_data[95:0], d3_tdata[495:0]};
                7'd63 : d4_tdata <= {424'd0,        d3_mark_data[95:0],  d3_tdata[503:0]};
                7'd64 : d4_tdata <= {416'd0,        d3_mark_data[95:0],  d3_tdata[511:0]};
                7'd65 : d4_tdata <= {408'd0,        d3_mark_data[95:0],  d3_tdata[519:0]};
                7'd66 : d4_tdata <= {400'd0,        d3_mark_data[95:0],  d3_tdata[527:0]};
                7'd67 : d4_tdata <= {392'd0,        d3_mark_data[95:0],  d3_tdata[535:0]};
                7'd68 : d4_tdata <= {384'd0,        d3_mark_data[95:0],  d3_tdata[543:0]};
                7'd69 : d4_tdata <= {376'd0,        d3_mark_data[95:0],  d3_tdata[551:0]};

                7'd70 : d4_tdata <= {368'd0,        d3_mark_data[95:0],  d3_tdata[559:0]};
                7'd71 : d4_tdata <= {360'd0,        d3_mark_data[95:0],  d3_tdata[567:0]};
                7'd72 : d4_tdata <= {352'd0,        d3_mark_data[95:0],  d3_tdata[575:0]};
                7'd73 : d4_tdata <= {344'd0,        d3_mark_data[95:0],  d3_tdata[583:0]};
                7'd74 : d4_tdata <= {336'd0,        d3_mark_data[95:0],  d3_tdata[591:0]};
                7'd75 : d4_tdata <= {328'd0,        d3_mark_data[95:0],  d3_tdata[599:0]};
                7'd76 : d4_tdata <= {320'd0,        d3_mark_data[95:0],  d3_tdata[607:0]};
                7'd77 : d4_tdata <= {312'd0,        d3_mark_data[95:0],  d3_tdata[615:0]};
                7'd78 : d4_tdata <= {304'd0,        d3_mark_data[95:0],  d3_tdata[623:0]};
                7'd79 : d4_tdata <= {296'd0,        d3_mark_data[95:0],  d3_tdata[631:0]};

                7'd80 : d4_tdata <= {288'd0,        d3_mark_data[95:0],  d3_tdata[639:0]};
                7'd81 : d4_tdata <= {280'd0,        d3_mark_data[95:0],  d3_tdata[647:0]};
                7'd82 : d4_tdata <= {272'd0,        d3_mark_data[95:0],  d3_tdata[655:0]};
                7'd83 : d4_tdata <= {264'd0,        d3_mark_data[95:0],  d3_tdata[663:0]};
                7'd84 : d4_tdata <= {256'd0,        d3_mark_data[95:0],  d3_tdata[671:0]};
                7'd85 : d4_tdata <= {248'd0,        d3_mark_data[95:0],  d3_tdata[679:0]};
                7'd86 : d4_tdata <= {240'd0,        d3_mark_data[95:0],  d3_tdata[687:0]};
                7'd87 : d4_tdata <= {232'd0,        d3_mark_data[95:0],  d3_tdata[695:0]};
                7'd88 : d4_tdata <= {224'd0,        d3_mark_data[95:0],  d3_tdata[703:0]};
                7'd89 : d4_tdata <= {216'd0,        d3_mark_data[95:0],  d3_tdata[711:0]};

                7'd90 : d4_tdata <= {208'd0,        d3_mark_data[95:0],  d3_tdata[719:0]};
                7'd91 : d4_tdata <= {200'd0,        d3_mark_data[95:0],  d3_tdata[727:0]};
                7'd92 : d4_tdata <= {192'd0,        d3_mark_data[95:0],  d3_tdata[735:0]};
                7'd93 : d4_tdata <= {184'd0,        d3_mark_data[95:0],  d3_tdata[743:0]};
                7'd94 : d4_tdata <= {176'd0,        d3_mark_data[95:0],  d3_tdata[751:0]};
                7'd95 : d4_tdata <= {168'd0,        d3_mark_data[95:0],  d3_tdata[759:0]};
                7'd96 : d4_tdata <= {160'd0,        d3_mark_data[95:0],  d3_tdata[767:0]};
                7'd97 : d4_tdata <= {152'd0,        d3_mark_data[95:0],  d3_tdata[775:0]};
                7'd98 : d4_tdata <= {144'd0,        d3_mark_data[95:0],  d3_tdata[783:0]};
                7'd99 : d4_tdata <= {136'd0,        d3_mark_data[95:0],  d3_tdata[791:0]};

                7'd100: d4_tdata <= {128'd0,        d3_mark_data[95:0],  d3_tdata[799:0]};
                7'd101 : d4_tdata <= {120'd0,        d3_mark_data[95:0],  d3_tdata[807:0]};
                7'd102 : d4_tdata <= {112'd0,        d3_mark_data[95:0],  d3_tdata[815:0]};
                7'd103 : d4_tdata <= {104'd0,        d3_mark_data[95:0],  d3_tdata[823:0]};
                7'd104 : d4_tdata <= {96'd0,        d3_mark_data[95:0],  d3_tdata[831:0]};
                7'd105 : d4_tdata <= {88'd0,        d3_mark_data[95:0],  d3_tdata[839:0]};
                7'd106 : d4_tdata <= {80'd0,        d3_mark_data[95:0],  d3_tdata[847:0]};
                7'd107 : d4_tdata <= {72'd0,        d3_mark_data[95:0],  d3_tdata[855:0]};
                7'd108 : d4_tdata <= {64'd0,        d3_mark_data[95:0],  d3_tdata[863:0]};
                7'd109 : d4_tdata <= {56'd0,        d3_mark_data[95:0],  d3_tdata[871:0]};

                7'd110: d4_tdata <= {48'd0,        d3_mark_data[95:0],  d3_tdata[879:0]};
                7'd111 : d4_tdata <= {40'd0,        d3_mark_data[95:0],  d3_tdata[887:0]};
                7'd112 : d4_tdata <= {32'd0,        d3_mark_data[95:0],  d3_tdata[895:0]};
                7'd113 : d4_tdata <= {24'd0,        d3_mark_data[95:0],  d3_tdata[903:0]};
                7'd114 : d4_tdata <= {16'd0,        d3_mark_data[95:0],  d3_tdata[911:0]};
                7'd115 : d4_tdata <= {8'd0,        d3_mark_data[95:0],  d3_tdata[919:0]};
                7'd116 : d4_tdata <= {             d3_mark_data[95:0],  d3_tdata[927:0]};
                7'd117 : d4_tdata <= {             d3_mark_data[87:0],  d3_tdata[935:0]};
                7'd118 : d4_tdata <= {             d3_mark_data[79:0],  d3_tdata[943:0]};
                7'd119 : d4_tdata <= {             d3_mark_data[71:0],  d3_tdata[951:0]};

                7'd120 : d4_tdata <= {             d3_mark_data[63:0],  d3_tdata[959:0]};
                7'd121 : d4_tdata <= {             d3_mark_data[55:0],  d3_tdata[967:0]};
                7'd122 : d4_tdata <= {             d3_mark_data[47:0],  d3_tdata[975:0]};
                7'd123 : d4_tdata <= {             d3_mark_data[39:0],  d3_tdata[983:0]};
                7'd124 : d4_tdata <= {             d3_mark_data[31:0],  d3_tdata[991:0]};
                7'd125 : d4_tdata <= {             d3_mark_data[23:0],  d3_tdata[999:0]};
                7'd126 : d4_tdata <= {             d3_mark_data[15:0],  d3_tdata[1007:0]};
                7'd127 : d4_tdata <= {             d3_mark_data[7:0],  d3_tdata[1015:0]};

                default : d4_tdata <= d3_tdata;
            endcase
        end else if(m_axis_tready == 1'b1)
            d4_tdata <= d3_tdata;
    end


    assign m_axis_tdata = d4_tdata;
    assign m_axis_tkeep = d4_tkeep;
    assign m_axis_tchannel = d4_tchan;
    assign m_axis_tlast = d4_tlast;
    assign m_axis_tvalid = d4_tvalid;

    assign s_axis_tready = m_axis_tready;

endmodule
`resetall
