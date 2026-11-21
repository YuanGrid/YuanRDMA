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


`include "global_define.vh"
// synopsys translate_off
`timescale 1 ps / 1 ps
// synopsys translate_on
module  dfifo #(
    parameter  FIFO_TYPE     = "M20K",
    parameter  SHOWAHEAD     = "OFF",
    parameter  PACKET_FIFO   = "NO",
    parameter  FULLTHRESHOLD = 512,
    parameter  EMPTYHRESHOLD = 8  ,
    parameter  DEPTH         = 512,
    parameter  WIDTH         = 512
) (
    input   wire                            aclr,
    input   wire    [WIDTH-1:0]             data,
    input   wire                            rdclk,
    input   wire                            rdreq,
    input   wire                            wrclk,
    input   wire                            wrreq,
    output  wire    [WIDTH-1:0]             q,
    output  wire                            rdempty,
    output  wire                            rdpempty,
    output  wire    [$clog2(DEPTH)-1:0]     rdusedw,
    output  wire                            wrpfull,
    output  wire    [$clog2(DEPTH)-1:0]     wrusedw
);

    localparam REAL_FIFO_TYPE = FIFO_TYPE == "M20K" ? "RAM_BLOCK_TYPE=M20K,DISABLE_DCFIFO_EMBEDDED_TIMING_CONSTRAINT=TRUE":
                                FIFO_TYPE == "MLAB" ? "RAM_BLOCK_TYPE=MLAB,DISABLE_DCFIFO_EMBEDDED_TIMING_CONSTRAINT=TRUE":"DISABLE_DCFIFO_EMBEDDED_TIMING_CONSTRAINT=TRUE";

    assign wrpfull  = wrusedw < FULLTHRESHOLD ? 1'b0 : 1'b1;
    assign rdpempty = rdusedw > EMPTYHRESHOLD ? 1'b0 : 1'b1;
    wire                            data_empty  ;
    wire                            eop_wen     ;
    wire    [$clog2(DEPTH)-1:0]     eop_wrusedw ;
    wire                            eop_pfull   ;
    wire                            eop_ren     ;
    wire                            eop_pempty  ;
    wire                            eop_empty   ;
    wire    [$clog2(DEPTH)-1:0]     eop_rdusedw ;

    dcfifo #(
        .enable_ecc             ("FALSE"        ),
        .intended_device_family ("Agilex 7"     ),
        .lpm_hint               (REAL_FIFO_TYPE ),
        .lpm_numwords           (DEPTH          ),
        .lpm_showahead          (SHOWAHEAD      ),
        .lpm_type               ("dcfifo"       ),
        .lpm_width              (WIDTH          ),
        .lpm_widthu             ($clog2(DEPTH)  ),
        .overflow_checking      ("ON"           ),
        .rdsync_delaypipe       (5              ),
        .read_aclr_synch        ("ON"           ),
        .underflow_checking     ("ON"           ),
        .use_eab                ("ON"           ),
        .write_aclr_synch       ("ON"           ),
        .wrsync_delaypipe       (5              )
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
        .rdempty                (data_empty     ),
        .rdusedw                (rdusedw        ),
        .wrfull                 (               ),
        .wrusedw                (wrusedw        ),
        .eccstatus              (               ),
        .rdfull                 (               ),
        .wrempty                (               )
    );
    generate
        if(PACKET_FIFO == "YES" || PACKET_FIFO == "yes")begin 
            if(SHOWAHEAD == "OFF" || SHOWAHEAD == "off")begin 
                reg         data_vld    ;
                always @(posedge rdclk ) begin
                    data_vld <= rdreq;
                end
                assign eop_ren = data_vld & q[WIDTH-1];
            end else begin 
                wire        data_vld;
                assign data_vld = rdreq;
                assign eop_ren = data_vld & q[WIDTH-1];
            end  

            assign eop_wen = wrreq & data[WIDTH-1];
            
            assign eop_pempty = eop_rdusedw >= 2 ? 1'b0 : 1'b1;
            assign rdempty    = (eop_ren & (!eop_pempty)) ? 1'b0 : 
                                eop_ren                ? 1'b1 : eop_empty; 
            dcfifo #(
                .enable_ecc             ("FALSE"        ),
                .intended_device_family ("Agilex 7"     ),
                .lpm_hint               ("RAM_BLOCK_TYPE=MLAB,DISABLE_DCFIFO_EMBEDDED_TIMING_CONSTRAINT=TRUE"),
                .lpm_numwords           (DEPTH          ),
                .lpm_showahead          ("ON"           ),
                .lpm_type               ("dcfifo"       ),
                .lpm_width              (1              ),
                .lpm_widthu             ($clog2(DEPTH)  ),
                .overflow_checking      ("ON"           ),
                .rdsync_delaypipe       (5              ),
                .read_aclr_synch        ("ON"           ),
                .underflow_checking     ("ON"           ),
                .use_eab                ("ON"           ),
                .write_aclr_synch       ("ON"           ),
                .wrsync_delaypipe       (5              )
            )dcfifo_component(
                .aclr                   (aclr           ),
                .data                   (1'b1           ),
                .rdclk                  (rdclk          ),
                .rdreq                  (eop_ren        ),
                .wrclk                  (wrclk          ),
                .wrreq                  (eop_wen        ),
                .q                      (               ),
                .rdempty                (eop_empty      ),
                .rdusedw                (eop_rdusedw    ),
                .wrfull                 (               ),
                .wrusedw                (eop_wrusedw    ),
                .eccstatus              (               ),
                .rdfull                 (               ),
                .wrempty                (               )
            );
        end else begin 
            assign rdempty = data_empty;
        end  
    endgenerate


endmodule


