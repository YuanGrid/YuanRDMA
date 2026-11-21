// (C) 2001-2026 Altera Corporation. All rights reserved.
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


// (C) 2001-2012 Altera Corporation. All rights reserved.
// Your use of Altera Corporation's design tools, logic functions and other
// software and tools, and its AMPP partner logic functions, and any output
// files any of the foregoing (including device programming or simulation
// files), and any associated documentation or information are expressly subject
// to the terms and conditions of the Altera Program License Subscription
// Agreement, Altera MegaCore Function License Agreement, or other applicable
// license agreement, including, without limitation, that your use is for the
// sole purpose of programming logic devices manufactured by Altera and sold by
// Altera or its authorized distributors.  Please refer to the applicable
// agreement for further details.


// $Id: //acds/main/ip/merlin/altera_merlin_burst_adapter/altera_merlin_burst_adapter.sv#68 $
// $Revision: #68 $
// $Date: 2014/01/23 $

`timescale 1 ns / 1 ns

// -------------------------------------------------------
// Adapter for uncompressed transactions only. This adapter will
// typically be used to adapt burst length for non-bursting 
// wide to narrow Avalon links.
// -------------------------------------------------------
module altera_merlin_burst_adapter_uncompressed_only
#(
    parameter 
    PKT_BYTE_CNT_H  = 5,
    PKT_BYTE_CNT_L  = 0,
    PKT_BYTEEN_H    = 83,
    PKT_BYTEEN_L    = 80,
    ST_DATA_W       = 84,
    ST_CHANNEL_W    = 8
)
(
    input clk,
    input reset,

    // -------------------
    // Command Sink (Input)
    // -------------------
    input                           sink0_valid,
    input  [ST_DATA_W-1 : 0]        sink0_data,
    input  [ST_CHANNEL_W-1 : 0]     sink0_channel,
    input                           sink0_startofpacket,
    input                           sink0_endofpacket,
    output reg                      sink0_ready,

    // -------------------
    // Command Source (Output)
    // -------------------
    output reg                      source0_valid,
    output reg [ST_DATA_W-1    : 0] source0_data,
    output reg [ST_CHANNEL_W-1 : 0] source0_channel,
    output reg                      source0_startofpacket,
    output reg                      source0_endofpacket,
    input                           source0_ready
);
    localparam
        PKT_BYTE_CNT_W = PKT_BYTE_CNT_H - PKT_BYTE_CNT_L + 1,
        NUM_SYMBOLS    = PKT_BYTEEN_H - PKT_BYTEEN_L + 1;

    wire [PKT_BYTE_CNT_W - 1 : 0] num_symbols_sig = NUM_SYMBOLS[PKT_BYTE_CNT_W - 1 : 0];

    always_comb begin : source0_data_assignments
        source0_valid         = sink0_valid;
        source0_channel       = sink0_channel;
        source0_startofpacket = sink0_startofpacket;
        source0_endofpacket   = sink0_endofpacket;

        source0_data          = sink0_data;
        source0_data[PKT_BYTE_CNT_H : PKT_BYTE_CNT_L] = num_symbols_sig;

        sink0_ready = source0_ready;
    end

endmodule



`ifdef QUESTA_INTEL_OEM
`pragma questa_oem_00 "LX4fNUqnOK9YZXada7z4XBduZSVIzRiCZMV68Nw5pi3jGBzEJ7k/q3e2pe2d5ih5hQ+ItbTsv85ur7WT52QvsISuFabvVGM2dFC3XgapA19E935fa4wOMN7g1FoVOeA23o/bx9lzQi1KwtrGAT3WnWAHbOPjvJVj7gDzuux6BsOeHiRy+Hf4CH1XhQbVVKIHvO4RIGSV91Lrvssmc61f/rmN/00diyYUtd7BjtnlFtMlVcpVaslEcu1v3TTTau/vax+HHk8sHtD9bRJUhyNiFcfjCl9UgDoNmg3UlIa6C2yaz8A+0AQHbnwR9+FZAMisQbr2nZntewXKS18C9uC03YySljzqx+dR4aetT+gCRnlBP49LdkO/0SNKbBM9mDvLU/1e8vaeWPSw4PMnG57H2/SosrOMfgMa+AeOBPrM4F7do/mPd9HPKGVGQAYuX+AWod7QsNA5WH3ZNxVlxxpcjQ3mYarCMXB5VTpsl2KBJhLNYoOEa3vWqki+BMvOVun0KwUGjIBqoz2T82KXF9YmYIHAm3N7EdnIKGeWZpDhxCzXeNXGAGe4OdrKTQg0Pyy5OjBl8J/Mh4pR0w7D8Wh/7rpLn1/AZLqtl/ERSQapnCsQqwQ5lCdFMZCFIj8XkQjrc7g6azdTYf3KvJTHyxB4+niotTsqzVQzlNG9a8zvD5oQPI/kyFunlEvNWsYF/TaZB1jgpf3N6FW8kKxyQLg1e0XP3WYIj9Wii+kxzQIawsCyg0B/tKByX9tsguFtIw98+FttsUl1SqLpEPugSmw48ml8dwscI+78UqDleUbr5U/SPs1vnsfppUbTVQsdUJbQye4GNXccNeGcVeplNcJtJQmCOPZhtqAMV5qNDlrvgnU/1BJP70SnDC/G2rx1nO1/b9Y8hYWmlO/UneV6mHCDo61hBFsvDywRik+7Flali7RCZT1SET6prSO6yx6E0apdQjLj6q80rYaCAx5C2tVeEU4oCbHTy+GxC0MEXcW2cicTmgZoenT08wdVbSx4090p"
`endif