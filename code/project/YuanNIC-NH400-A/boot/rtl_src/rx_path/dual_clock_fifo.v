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
module  dfifo #(
    parameter  FIFO_TYPE     = "M20K",
    parameter  SHOWAHEAD     = "OFF",
    parameter  FULLTHRESHOLD = 512,
    parameter  DEPTH         = 512,
    parameter  WIDTH         = 512
) (
    input                       aclr,
    input  [WIDTH-1:0]          data,
    input                       rdclk,
    input                       rdreq,
    input                       wrclk,
    input                       wrreq,
    output [WIDTH-1:0]          q,
    output                      rdempty,
    output [$clog2(DEPTH)-1:0]  rdusedw,
    output                      wrfull,
    output [$clog2(DEPTH)-1:0]  wrusedw
);

    localparam REAL_FIFO_TYPE = FIFO_TYPE == "M20K" ? "RAM_BLOCK_TYPE=M20K,DISABLE_DCFIFO_EMBEDDED_TIMING_CONSTRAINT=TRUE":
                                FIFO_TYPE == "MLAB" ? "RAM_BLOCK_TYPE=MLAB,DISABLE_DCFIFO_EMBEDDED_TIMING_CONSTRAINT=TRUE":"DISABLE_DCFIFO_EMBEDDED_TIMING_CONSTRAINT=TRUE";

    assign wrfull = wrusedw < FULLTHRESHOLD ? 1'b0 : 1'b1;

    dcfifo #(
        .enable_ecc             ("FALSE"        ),
        .intended_device_family ("Agilex 7"     ),
        .lpm_hint               (REAL_FIFO_TYPE ),
        .lpm_numwords           (DEPTH          ),
        .lpm_showahead          ("OFF"          ),
        .lpm_type               ("dcfifo"      ),
        .lpm_width              (WIDTH         ),
        .lpm_widthu             ($clog2(DEPTH) ),
        .overflow_checking      ("ON"          ),
        .rdsync_delaypipe       (5             ),
        .read_aclr_synch        ("ON"          ),
        .underflow_checking     ("ON"          ),
        .use_eab                ("ON"          ),
        .write_aclr_synch       ("ON"          ),
        .wrsync_delaypipe       (5             )
    )
    dcfifo_component
    (
        .aclr                   (aclr           ),
        .data                   (data           ),
        .rdclk                  (rdclk          ),
        .rdreq                  (rdreq          ),
        .wrclk                  (wrclk          ),
        .wrreq                  (wrreq          ),
        .q                      (q              ),
        .rdempty                (rdempty        ),
        .rdusedw                (rdusedw        ),
        .wrfull                 (               ),
        .wrusedw                (wrusedw        ),
        .eccstatus              (               ),
        .rdfull                 (               ),
        .wrempty                (               )
    );


endmodule


