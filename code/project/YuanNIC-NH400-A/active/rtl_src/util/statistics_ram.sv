`timescale 1ns/1ps
module statistics_ram #(
    parameter       DATA_W          = 32,
    parameter       ADDR_W          = 12,
    parameter       CNT_NUM         = 2**ADDR_W,
    parameter       MODE            = "STATIC"
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
    output  reg     [DATA_W-1:0]    stream_pkt_rdata,
    input                           axis_aclk,
    input                           axil_aclk,
    input                           axis_rstn
);
    reg     [DATA_W-1:0]            stream_pkt_dinb[3:2]; 
    reg                             stream_pkt_wenb[3:2];
    reg     [ADDR_W-1:0]            stream_pkt_addrb[3:2];
    reg     [ADDR_W-1:0]            stream_pkt_addra[1:0];
    reg                             stream_pkt_rena[1:0];
    wire    [DATA_W-1:0]            stream_pkt_douta[1:1];
    reg     [DATA_W-1:0]            new_data_d[1:0];
    reg                             cfg_ram_wen;
    reg     [ADDR_W-1:0]            cfg_ram_waddr;
    reg     [DATA_W-1:0]            cfg_ram_wdata;
    reg                             axil_rst_flag;
    reg     [4:0]                   axil_rst_wait_cnt;
    reg                             axis_rst_flag[3:0];
    reg                             static_clear;
    reg     [ADDR_W-1:0]            static_clear_cnt;

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

    always @(posedge axis_aclk) begin
        stream_pkt_rena[0] <= stream_pkt_tvalid & stream_pkt_tlast & stream_pkt_tready ;
        stream_pkt_rena[1] <= stream_pkt_rena[0];
        stream_pkt_wenb[2] <= stream_pkt_rena[1] | static_clear;
        stream_pkt_wenb[3] <= stream_pkt_wenb[2];
        new_data_d[1:0]   <= {new_data_d[0],new_data};
    end

    always @(posedge axis_aclk ) begin
        stream_pkt_addra[0] <= stream_pkt_id_w;
        stream_pkt_addra[1] <= stream_pkt_addra[0];
        stream_pkt_addrb[2] <= static_clear ? static_clear_cnt : stream_pkt_addra[1];
        stream_pkt_addrb[3] <= stream_pkt_addrb[2];
    end

    generate
        if(MODE == "MAX")begin :max_mod
            always @(posedge axis_aclk ) begin
                if(static_clear)
                    stream_pkt_dinb[2] <= {DATA_W{1'b0}};
                else if(stream_pkt_rena[1] & stream_pkt_wenb[2] & stream_pkt_addra[1]==stream_pkt_addrb[2])
                    stream_pkt_dinb[2] <= stream_pkt_dinb[2] < new_data_d[1] ? new_data_d[1] : stream_pkt_dinb[2];
                else if(stream_pkt_rena[1] & stream_pkt_wenb[3] & stream_pkt_addra[1]==stream_pkt_addrb[3])
                    stream_pkt_dinb[2] <= stream_pkt_dinb[3] < new_data_d[1] ? new_data_d[1] : stream_pkt_dinb[3];                
                else 
                    stream_pkt_dinb[2] <= stream_pkt_douta[1] < new_data_d[1] ? new_data_d[1] : stream_pkt_douta[1];

                stream_pkt_dinb[3] <= stream_pkt_dinb[2];
            end
        end else if(MODE == "MIN")begin :min_mod
            always @(posedge axis_aclk ) begin
                if(static_clear)
                    stream_pkt_dinb[2] <= {DATA_W{1'b0}};
                else if(stream_pkt_rena[1] & stream_pkt_wenb[2] & stream_pkt_addra[1]==stream_pkt_addrb[2])
                    stream_pkt_dinb[2] <= stream_pkt_dinb[2] > new_data_d[1] ? new_data_d[1] : stream_pkt_dinb[2];
                else if(stream_pkt_rena[1] & stream_pkt_wenb[3] & stream_pkt_addra[1]==stream_pkt_addrb[3])
                    stream_pkt_dinb[2] <= stream_pkt_dinb[3] > new_data_d[1] ? new_data_d[1] : stream_pkt_dinb[3];                
                else 
                    stream_pkt_dinb[2] <= stream_pkt_douta[1] > new_data_d[1] ? new_data_d[1] : stream_pkt_douta[1];

                stream_pkt_dinb[3] <= stream_pkt_dinb[2];
            end
        end else begin : static_mod
            always @(posedge axis_aclk ) begin
                if(static_clear)
                    stream_pkt_dinb[2] <= {DATA_W{1'b0}};
                else if(stream_pkt_rena[1] & stream_pkt_wenb[2] & stream_pkt_addra[1]==stream_pkt_addrb[2])
                    stream_pkt_dinb[2] <= stream_pkt_dinb[2] + new_data_d[1];
                else if(stream_pkt_rena[1] & stream_pkt_wenb[3] & stream_pkt_addra[1]==stream_pkt_addrb[3])
                    stream_pkt_dinb[2] <= stream_pkt_dinb[3] + new_data_d[1];                
                else 
                    stream_pkt_dinb[2] <= stream_pkt_douta[1] + new_data_d[1];

                stream_pkt_dinb[3] <= stream_pkt_dinb[2];
            end

        end    
    endgenerate

    always @(posedge axis_aclk ) begin
        cfg_ram_wen   <= stream_pkt_wenb[2];
        cfg_ram_waddr <= stream_pkt_addrb[2];
        cfg_ram_wdata <= stream_pkt_dinb[2];
    end

    ram #(
        .ram_block_type         ("M20K"                 ),
        .outdata_b_reg          ("UNUSED"               ),
        .widthad_a              (ADDR_W                 ),
        .widthad_b              (ADDR_W                 ),
        .numwords_a             (CNT_NUM                ),
        .numwords_b             (CNT_NUM                ),
        .width_a                (DATA_W                 ),
        .width_b                (DATA_W                 )
    )
    u0_comp_ram
    (
        .wrclock                (axis_aclk              ),
        .wren                   (stream_pkt_wenb [2]    ),
        .wraddress              (stream_pkt_addrb[2]    ),
        .data                   (stream_pkt_dinb [2]    ),
        .rdclock                (axis_aclk              ),
        .rden                   (stream_pkt_rena [0]    ),
        .rdaddress              (stream_pkt_addra[0]    ),
        .q                      (stream_pkt_douta[1]    )
    );

    ram#(
        .ram_block_type         ("M20K"                 ),
        .outdata_b_reg          ("UNUSED"               ),
        .widthad_a              (ADDR_W                 ),
        .widthad_b              (ADDR_W                 ),
        .numwords_a             (CNT_NUM                ),
        .numwords_b             (CNT_NUM                ),
        .width_a                (DATA_W                 ),
        .width_b                (DATA_W                 )
    )u1_cfg_read_ram(
        .wrclock                (axis_aclk              ),
        .wren                   (cfg_ram_wen            ),
        .wraddress              (cfg_ram_waddr          ),
        .data                   (cfg_ram_wdata          ),
        .rdclock                (axil_aclk              ),
        .rden                   (stream_pkt_r_req       ),
        .rdaddress              (stream_pkt_id_r        ),
        .q                      (stream_pkt_rdata       )
    );



endmodule
