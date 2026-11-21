`resetall
`default_nettype none
`timescale 1ns / 1ps

module rx_path_avst #(
    parameter S_DATA_WIDTH              = 1024,
    parameter S_EMTY_WIDTH              = 48,
    parameter S_INFRAME_WIDTH           = 16,
    parameter M_DATA_WIDTH              = 512,
    parameter M_KEEP_WIDTH              = (M_DATA_WIDTH/8)    
)(
    input  wire                         mac_clk         ,
    input  wire                         mac_rst_n       ,

    input  wire [S_DATA_WIDTH-1:0]      s_mac_data      ,
    input  wire [S_INFRAME_WIDTH*3-1:0] s_mac_emty      ,
    input  wire [S_INFRAME_WIDTH-1:0]   s_mac_inframe   ,
    input  wire [S_INFRAME_WIDTH*2-1:0] s_mac_error     ,
    input  wire [S_INFRAME_WIDTH-1:0]   s_mac_fcs_error ,
    input  wire                         s_mac_valid     ,

    output reg  [S_DATA_WIDTH-1:0]      m_axis_tdata0   ,
    output reg  [$clog2(S_DATA_WIDTH/8)-1:0]m_axis_tempty0,
    output wire [2:0]                   m_axis_tuerr0  ,
    output reg                          m_axis_tvalid0  ,
    input  wire                         m_axis_tready0  ,
    output reg                          m_axis_teop0    ,   

    output reg  [S_DATA_WIDTH-1:0]      m_axis_tdata1    ,
    output wire [$clog2(S_DATA_WIDTH/8)-1:0]m_axis_tempty1,
    output wire [2:0]                   m_axis_tuerr1    ,
    output reg                          m_axis_tvalid1   ,
    input  wire                         m_axis_tready1   ,
    output reg                          m_axis_teop1    

);
    localparam S_DATA_EMTY_WIDTH = $clog2(S_DATA_WIDTH/8);

    reg         [S_DATA_WIDTH-1:0]      mac_data_d[1:1];
    reg         [S_INFRAME_WIDTH*3-1:0] mac_emty_d[1:1];
    reg         [S_INFRAME_WIDTH*1-1:0] mac_inframe_d[1:1];
    reg         [S_INFRAME_WIDTH*2-1:0] mac_error_d[1:1];
    reg         [S_INFRAME_WIDTH*3-1:0] mac_fcs_error_d[1:1];
    reg                                 mac_valid_d[1:1];
    reg         [1:0]                   sop_num_d[1:1];
    reg         [3:0]                   sop1_pos_d[1:1];
    reg         [3:0]                   sop2_pos_d[1:1];
    reg         [1:0]                   eop_num_d[1:1];
    reg         [3:0]                   eop1_pos_d[1:1];
    reg         [3:0]                   eop1_empty_d[1:1];
    reg                                 eop1_fcs_err_d[1:1];
    reg         [3:0]                   eop2_pos_d[1:1];
    reg         [3:0]                   eop2_empty_d[1:1];
    reg                                 eop2_fcs_err_d[1:1];
    reg                                 write_shift_d[1:1];

    always @(posedge mac_clk) begin
        if(!mac_rst_n)
            mac_inframe_d[1]      <= 16'd0;
        else if(s_mac_valid)
            mac_inframe_d[1]      <= s_mac_inframe;  

        if(s_mac_valid)begin 
            mac_data_d[1]         <= s_mac_data;    
            mac_emty_d[1]         <= s_mac_emty;    
            mac_error_d[1]        <= s_mac_error;    
            mac_fcs_error_d[1]    <= s_mac_fcs_error;    
        end  
    end

    always @(posedge mac_clk) begin
        if(s_mac_valid & (s_mac_inframe == 16'd0) & mac_inframe_d[1][15] == 1'b0)
            mac_valid_d[1] <= 1'b0;
        else  
            mac_valid_d[1] <= s_mac_valid;
    end

    always @(posedge mac_clk ) begin
        if(s_mac_valid)begin 
            sop1_pos_d[1]   <= sop1_bit_pos({s_mac_inframe,mac_inframe_d[1][15]});
            sop2_pos_d[1]   <= sop2_bit_pos({s_mac_inframe,mac_inframe_d[1][15]});
            eop1_pos_d[1]   <= eop1_bit_pos({s_mac_inframe,mac_inframe_d[1][15]});
            eop1_empty_d[1] <= eop1_empty({s_mac_inframe,mac_inframe_d[1][15]},s_mac_emty);
            eop2_pos_d[1]   <= eop2_bit_pos({s_mac_inframe,mac_inframe_d[1][15]});
            eop2_empty_d[1] <= eop2_empty({s_mac_inframe,mac_inframe_d[1][15]},s_mac_emty);
        end 
        sop_num_d[1]  <= s_mac_valid ? sop_num({s_mac_inframe,mac_inframe_d[1][15]}) : 2'd0;
        eop_num_d[1]  <= s_mac_valid ? eop_num({s_mac_inframe,mac_inframe_d[1][15]}) : 2'd0;
    end

    always @(posedge mac_clk) begin
        if(!mac_rst_n)
            write_shift_d[1] <= 1'b0;//先写0 再写1
        else if(mac_valid_d[1] & eop_num_d[1]==2'd1)
            write_shift_d[1] <= ~write_shift_d[1];
    end

    data_concat #(
        .S_DATA_WIDTH                   (1024                       )
    )
    data_concat0_u
    (
        .clk                            (mac_clk                    ),
        .rst_n                          (mac_rst_n                  ),
        .s_orig_data                    (mac_data_d[1]              ),
        .s_orig_emty                    (mac_emty_d[1]              ),
        .s_orig_inframe                 (mac_inframe_d[1]           ),
        .s_orig_error                   (mac_error_d[1]             ),
        .s_orig_fcs_error               (mac_fcs_error_d[1]         ),
        .s_orig_valid                   (mac_valid_d[1]             ),
        .s_sop_num                      (sop_num_d[1]               ),
        .s_sop1_pos                     (sop1_pos_d[1]              ),
        .s_sop2_pos                     (sop2_pos_d[1]              ),
        .s_eop_num                      (eop_num_d[1]               ),
        .s_eop1_pos                     (eop1_pos_d[1]              ),
        .s_eop1_empty                   (eop1_empty_d[1]            ),
        .s_eop2_pos                     (eop2_pos_d[1]              ),
        .s_eop2_empty                   (eop2_empty_d[1]            ),
        .s_write_flag                   (write_shift_d[1]           ),
        .m_axis_tdata                   (m_axis_tdata0              ),
        .m_axis_tempty                  (m_axis_tempty0             ),
        .m_axis_tuerr                   (m_axis_tuerr0              ),
        .m_axis_tvalid                  (m_axis_tvalid0             ),
        .m_axis_tready                  (m_axis_tready0             ),
        .m_axis_teop                    (m_axis_teop0               )
    );

    data_concat #(
        .S_DATA_WIDTH                   (1024                       )
    )
    data_concat1_u
    (
        .clk                            (mac_clk                    ),
        .rst_n                          (mac_rst_n                  ),
        .s_orig_data                    (mac_data_d[1]              ),
        .s_orig_emty                    (mac_emty_d[1]              ),
        .s_orig_inframe                 (mac_inframe_d[1]           ),
        .s_orig_error                   (mac_error_d[1]             ),
        .s_orig_fcs_error               (mac_fcs_error_d[1]         ),
        .s_orig_valid                   (mac_valid_d[1]             ),
        .s_sop_num                      (sop_num_d[1]               ),
        .s_sop1_pos                     (sop1_pos_d[1]              ),
        .s_sop2_pos                     (sop2_pos_d[1]              ),
        .s_eop_num                      (eop_num_d[1]               ),
        .s_eop1_pos                     (eop1_pos_d[1]              ),
        .s_eop1_empty                   (eop1_empty_d[1]            ),
        .s_eop2_pos                     (eop2_pos_d[1]              ),
        .s_eop2_empty                   (eop2_empty_d[1]            ),
        .s_write_flag                   (~write_shift_d[1]          ),
        .m_axis_tdata                   (m_axis_tdata1              ),
        .m_axis_tempty                  (m_axis_tempty1             ),
        .m_axis_tuerr                   (m_axis_tuerr1              ),
        .m_axis_tvalid                  (m_axis_tvalid1             ),
        .m_axis_tready                  (m_axis_tready1             ),
        .m_axis_teop                    (m_axis_teop1               )
    );

/***********************************FIFO例化，function定义*******************************************/
    function [1:0] sop_num;
        input [16:0] frame;
        integer i;
        begin : swap
            sop_num = 0 ;
            for (i=0;i<16;i=i+1)begin
                if(~frame[i] && frame[i+1]) 
                    sop_num = sop_num + 1;
            end  
        end
    endfunction

    function [3:0] sop1_bit_pos;
        input [16:0] frame;
        integer i;
        begin : swap
            sop1_bit_pos=0;
            for (i=0;i<16;i=i+1)begin
                if(~frame[15-i] && frame[16-i])
                    sop1_bit_pos = 15-i;
            end  
        end
    endfunction

    function [3:0] sop2_bit_pos;
        input [16:0] frame;
        integer i;
        begin : swap
            sop2_bit_pos = 0 ;
            for (i=0;i<16;i=i+1)begin
                if(~frame[i] && frame[i+1])
                    sop2_bit_pos = i;
            end  
        end
    endfunction

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

    function [3:0] eop1_bit_pos;
        input [16:0] frame;
        integer i;
        begin : swap
            eop1_bit_pos = 0;
            for (i=0;i<16;i=i+1)begin
                if(frame[15-i] && ~frame[16-i])
                    eop1_bit_pos = 15-i;
            end  
        end
    endfunction

    function [2:0] eop1_empty;
        input [16:0]    frame;
        input [16*3-1:0]empty;
        integer i;
        begin : swap
            eop1_empty = 0;
            for (i=0;i<16;i=i+1)begin
                if(frame[15-i] && ~frame[16-i])
                    eop1_empty = empty[(15-i)*3+:3];
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

    function [2:0] eop2_empty;
        input [16:0]    frame;
        input [16*3-1:0]empty;
        integer i;
        begin : swap
            eop2_empty = 0;
            for (i=0;i<16;i=i+1)begin
                if(frame[i] && ~frame[i+1])
                    eop2_empty = empty[i*3+:3];
            end  
        end
    endfunction

    function [511:0] swap_endian_64;
		input [511:0] din;
		integer i;
		reg [7:0] tmp_data;
		begin : swap_block_64
			for(i=0;i<64;i=i+1)
				swap_endian_64[(63-i)*8 +:8] = din[i*8 +:8];
		end
	endfunction

endmodule
`resetall
