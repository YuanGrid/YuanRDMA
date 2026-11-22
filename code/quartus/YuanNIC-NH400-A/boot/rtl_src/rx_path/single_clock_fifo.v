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
module  sfifo  #(
    parameter  ALMOST_EMPTY  = 1,
    parameter  ALMOST_AFULL  = 1,
    parameter  FIFO_TYPE     = "M20K",
    parameter  SHOWAHEAD     = "OFF",
    parameter  DEPTH         = 512,
    parameter  WIDTH         = 512
)
(
    input                       aclr,
    input                       clock,
    input  [WIDTH-1:0]          data,
    input                       rdreq,
    input                       wrreq,
    output                      almost_empty,
    output                      almost_full,
    output                      empty,
    output                      full,
    output [WIDTH-1:0]          q,
    output [$clog2(DEPTH)-1:0]  usedw
);

    localparam REAL_FIFO_TYPE = FIFO_TYPE == "M20K" ? "RAM_BLOCK_TYPE=M20K" :
                                FIFO_TYPE == "MLAB" ? "RAM_BLOCK_TYPE=MLAB" : "";

    scfifo #(
        .add_ram_output_register    ("OFF"          ),
        .almost_empty_value         (ALMOST_EMPTY   ),
        .almost_full_value          (ALMOST_AFULL   ),
        .enable_ecc                 ("FALSE"        ),
        .intended_device_family     ("Agilex 7"     ),
        .lpm_hint                   (REAL_FIFO_TYPE ),
        .lpm_numwords               (DEPTH          ),
        .lpm_showahead              (SHOWAHEAD      ),
        .lpm_type                   ("scfifo"       ),
        .lpm_width                  (WIDTH          ),
        .lpm_widthu                 ($clog2(DEPTH)  ),
        .overflow_checking          ("ON"           ),
        .underflow_checking         ("ON"           ),
        .use_eab                    ("ON"           ) 
    )scfifo_component (
        .aclr                       (aclr           ),
        .clock                      (clock          ),
        .data                       (data           ),
        .rdreq                      (rdreq          ),
        .wrreq                      (wrreq          ),
        .almost_empty               (almost_empty   ),
        .almost_full                (almost_full    ),
        .empty                      (empty          ),
        .full                       (full           ),
        .q                          (q              ),
        .usedw                      (usedw          ),
        .eccstatus                  (               ),
        .sclr                       (1'b0           )
    );
endmodule


