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


`include "../top/global_define.vh"

// synopsys translate_off
`timescale 1 ps / 1 ps
// synopsys translate_on
module  ram_delay#(
    parameter  ram_block_type   = "M20K",
    parameter  reg_num          = 3,//reg_num 必须大于3，小于3时直接用ram
    parameter  widthad_a        = 9,
    parameter  widthad_b        = 9,
    parameter  numwords_a       = 2**widthad_a,
    parameter  numwords_b       = 2**widthad_b,
    parameter  width_a          = 512,
    parameter  width_b          = 512,
    parameter  byteena_w        = 1
)
(
    input   [width_a-1:0]       data,
    input   [widthad_b-1:0]     rdaddress,
    input                       rdclock,
    input                       rden,
    input   [widthad_a-1:0]     wraddress,
    input                       wrclock,
    input                       wren,
    input   [byteena_w-1:0]     wren_byte,
    output  [width_b-1:0]       q
);  

    localparam                  RAM_WIDTHAD_A = 12;
    localparam                  RAM_WIDTHAD_B = 12;
    localparam                  RAM_NUMBER_A  = 2**12;
    localparam                  RAM_NUMBER_B  = 2**12;
    localparam                  WIDTH_DIFF    = widthad_b > RAM_WIDTHAD_B ? widthad_b-RAM_WIDTHAD_B : 0;
    localparam                  RAM_NUM       = 2**WIDTH_DIFF;

    wire    [RAM_NUM-1:0]       ram_wren            ;
    wire    [byteena_w-1:0]     ram_wren_byte       ;
    wire    [RAM_WIDTHAD_A-1:0] ram_wraddress       ;
    wire    [width_a-1:0]       ram_data            ;
    wire    [RAM_WIDTHAD_B-1:0] ram_rdaddress       ;
    wire    [width_b-1:0]       ram_q[RAM_NUM-1:0]  ;

    reg     [RAM_NUM-1:0]       rdata_select[5:1]   ;
    reg     [width_b-1:0]       ram_q_d[5:3]        ;

    assign ram_wren_byte   = wren_byte;
    assign ram_wraddress   = wraddress[0+:RAM_WIDTHAD_A];
    assign ram_data        = data     ;
    assign ram_rdaddress   = rdaddress[0+:RAM_WIDTHAD_A];

    always @(posedge rdclock) begin
        rdata_select[1]     <= rdaddress[RAM_WIDTHAD_A+:WIDTH_DIFF];
        rdata_select[5:2]   <= rdata_select[4:1];
    end

    always @(posedge rdclock ) begin
        ram_q_d[3]      <= ram_q[rdata_select[2]];
        ram_q_d[5:4]    <= ram_q_d[4:3];
    end

    assign q = ram_q_d[reg_num];
    
    generate
        for (genvar i=0 ; i<RAM_NUM ; i=i+1) begin
            if (WIDTH_DIFF == 0)
                assign ram_wren[i] = wren;
            else 
                assign ram_wren[i] = wren & wraddress[RAM_WIDTHAD_A+:WIDTH_DIFF]==i;

            ram#(
                .ram_block_type             ("M20K"                     ),
                .outdata_b_reg              ("USED"                     ),
                .widthad_a                  (RAM_WIDTHAD_A              ),
                .widthad_b                  (RAM_WIDTHAD_B              ),
                .numwords_a                 (RAM_NUMBER_A               ),
                .numwords_b                 (RAM_NUMBER_B               ),
                .width_a                    (width_a                    ),
                .width_b                    (width_b                    ),
                .byteena_w                  (byteena_w                  )
            )
            pkt_template_ram0
            (
                .wrclock                    (wrclock                    ),
                .wren                       (ram_wren[i]                ),
                .wren_byte                  (ram_wren_byte              ),
                .wraddress                  (ram_wraddress              ),
                .data                       (ram_data                   ),
                .rdclock                    (rdclock                    ),
                .rden                       (                           ),
                .rdaddress                  (ram_rdaddress              ),
                .q                          (ram_q[i]                   )
            );
        end
    endgenerate





    

endmodule


