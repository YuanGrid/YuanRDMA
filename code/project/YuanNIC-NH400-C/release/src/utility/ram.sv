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


`include "../top/define.vh"

// synopsys translate_off
`timescale 1 ps / 1 ps
// synopsys translate_on
module  ram#(
    parameter  ram_block_type   = "M20K",
    parameter  outdata_b_reg    = "UNUSED",
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


    wire [width_b-1:0]          o_data_b;
    wire [byteena_w-1:0]        byteena_a;

    localparam real_out_b_reg = outdata_b_reg=="USED" & widthad_b>=12 ? "CLOCK1" : "UNUSED" ;

    assign byteena_a = byteena_w == 1 ? 1'b1 : wren_byte;
    generate
        if(outdata_b_reg == "UNUSED")begin :unused_mode
            assign  q = o_data_b;
        end else if(outdata_b_reg=="USED" & widthad_b>=12) begin 
            assign  q = o_data_b;
        end else begin :used_mode
            reg  [width_b-1:0]  o_data_b_reg;
            always @(posedge rdclock ) begin
                o_data_b_reg <= o_data_b;
            end
            assign q = o_data_b_reg;
        end 
    endgenerate

`ifdef SIMULATION
    altsyncram
`else 
    altera_syncram
`endif 
    altera_syncram_component (
        .address_a              (wraddress),
        .address_b              (rdaddress),
        .clock0                 (wrclock),
        .clock1                 (rdclock),
        .data_a                 (data),
        .wren_a                 (wren),
        .q_b                    (o_data_b),
        .aclr0                  (1'b0),
        .aclr1                  (1'b0),
        //.address2_a             (1'b1),
        //.address2_b             (1'b1),
        .addressstall_a         (1'b0),
        .addressstall_b         (1'b0),
        .byteena_a              (byteena_a),
        .byteena_b              (1'b1),
        .clocken0               (1'b1),
        .clocken1               (1'b1),
        .clocken2               (1'b1),
        .clocken3               (1'b1),
        .data_b                 ({width_b{1'b1}}),
        //.eccencbypass           (1'b0),
        //.eccencparity           (8'b0),
        .eccstatus              (),
        .q_a                    (),
        .rden_a                 (1'b1),
        .rden_b                 (1'b1),
        //.sclr                   (1'b0),
        .wren_b                 (1'b0));
    defparam
        altera_syncram_component.address_aclr_b  = "NONE",
        altera_syncram_component.address_reg_b  = "CLOCK1",
        altera_syncram_component.clock_enable_input_a  = "BYPASS",
        altera_syncram_component.clock_enable_input_b  = "BYPASS",
        altera_syncram_component.clock_enable_output_b  = "BYPASS",
        //altera_syncram_component.enable_force_to_zero  = "FALSE",
        altera_syncram_component.intended_device_family  = "Agilex 7",
        altera_syncram_component.lpm_type  = "altera_syncram",
        altera_syncram_component.numwords_a  = numwords_a,
        altera_syncram_component.numwords_b  = numwords_b,
        altera_syncram_component.operation_mode  = "DUAL_PORT",
        altera_syncram_component.outdata_aclr_b  = "NONE",
        //altera_syncram_component.outdata_sclr_b  = "NONE",
        altera_syncram_component.outdata_reg_b  = real_out_b_reg,
        altera_syncram_component.power_up_uninitialized  = "FALSE",
        altera_syncram_component.ram_block_type  = ram_block_type,
        altera_syncram_component.read_during_write_mode_mixed_ports  = "OLD_DATA",
        altera_syncram_component.widthad_a  = widthad_a,
        altera_syncram_component.widthad_b  = widthad_b,
        altera_syncram_component.width_a  = width_a,
        altera_syncram_component.width_b  = width_b,
        altera_syncram_component.width_byteena_a  = byteena_w;








endmodule


