// (C) 2001-2024 Intel Corporation. All rights reserved.
// Your use of Intel Corporation's design tools, logic functions and other 
// software and tools, and its AMPP partner logic functions, and any output 
// files from any of the foregoing (including device programming or simulation 
// files), and any associated documentation or information are expressly subject 
// to the terms and conditions of the Intel Program License Subscription 
// Agreement, Intel FPGA IP License Agreement, or other applicable 
// license agreement, including, without limitation, that your use is for the 
// sole purpose of programming logic devices manufactured by Intel and sold by 
// Intel or its authorized distributors.  Please refer to the applicable 
// agreement for further details.



`timescale 1ps / 1ps 

module fim_resync #(
   parameter SYNC_CHAIN_LENGTH = 2,  
   parameter WIDTH             = 1,  
   parameter INIT_VALUE        = 0,
   parameter NO_CUT		= 1	  
)(
   input  logic              clk,
   input  logic              reset,
   input  logic  [WIDTH-1:0] d,
   output logic  [WIDTH-1:0] q
);

localparam  INT_LEN       = (SYNC_CHAIN_LENGTH > 1) ? SYNC_CHAIN_LENGTH : 2;
localparam  L_INIT_VALUE  = (INIT_VALUE == 1) ? 1'b1 : 1'b0;

genvar ig;

generate
   for(ig=0;ig<WIDTH;ig=ig+1) begin : resync_chains
      wire d_in;   
      wire sync_d_in;
      wire sync_q_out;
      
      assign d_in = d[ig];
      
      assign sync_d_in = (INIT_VALUE == 1) ? ~d_in : d_in;
      assign q[ig] = (INIT_VALUE == 1)  ? ~sync_q_out : sync_q_out;
      
      if (NO_CUT == 0) begin
         altera_std_synchronizer #(
            .depth(INT_LEN)				
         ) synchronizer (
            .clk      (clk),
            .reset_n  (~reset),
            .din      (sync_d_in),
            .dout     (sync_q_out)
         );
         
         initial begin
            synchronizer.dreg = {(INT_LEN-1){1'b0}};
            synchronizer.din_s1 = 1'b0;
         end

      end else begin
         altera_std_synchronizer_nocut #(
            .depth(INT_LEN)
         ) synchronizer_nocut (
            .clk      (clk),
            .reset_n  (~reset),
            .din      (sync_d_in),
            .dout     (sync_q_out)
         );

         initial begin
            synchronizer_nocut.dreg = {(INT_LEN-1){1'b0}};
            synchronizer_nocut.din_s1 = 1'b0;
         end
      end
   end 
endgenerate
endmodule
`ifdef QUESTA_INTEL_OEM
`pragma questa_oem_00 "8aFrJEo1yygebd74a8md/yDcSVKbulzF1F2rtf3+aaForgMz73uba/yHNeFYFZ2YkKYCwYjw7rtt+Xp0uiKSB+4MrmFoL2bMZg2i7d7DUOZRRGYTJjtW7T7i44nVqnxPkSnp2CAJvOPhz4lx7r98H1ayc7/YAuv9G1orwsk6EYg8bE3Js4qZRDWPh+vBOh/Wr9Wf+2AzcYIwsz08/kzICnXwrr6XSrKXNoszeDhgFSjmUMpHZtsbtGGdVbS7+V4CM74FUsaNKlkA0T/yFP1osDoq5KAXeDpUxkMk/9dmw1ZuyVBh8oN2FfugIO44OgQh1O5mgzwmyqcLyvulPQvGYBmQUxjB+O8ntb5dmHtwTJR6005SPBKBBYtXdMiU+oxFqdK7UPKgfVgjq4MyhZ1IyvCdA1qqSs58MHlGGJnFBNteLPSRgFPD/F0NMSK2luE8z2AJETwQpXawhyG6PhXBLPTIkMCMQfTHdX6n34HnYRXJWK7zVTQFQzCHs/qglgrYK3nEnCVGnZIb5QemlvEV3Eltg7R6ROBNe3AHZiUQ0dgHzvJLpZDsgGy8FYFQC6KjHEjib+y5XmoyY1VHvhyRdR1terYLYiUb9rkNmakFxObxoSiUiZh69m+xyfRhVK/XoafB5tsilt7lbaCxDBZQ/Gnqrb8Z7OJqFNbKlQWyQDjFLD11lWQtAz+Bg0XOw5y3VstJJwemSzVMyLxlDEVLlyXANSsD8W9ctRL5jZgeqwuNjclpd/oT0wsDWsU71EcPPB2iCLbubW1sZvFnEAzKIzReegXcQJuWg2Y+hZclwHguTIlLbvhkSwN8oTn7Hgo/zqK8HG2kMiSGCQHOPhNxU7B41pjmBRlJPDStPJ4dgoULS4dRLUNKlz18VTbD1nQRsM0G/9Tp2yisSvW/3iuBD+0eRy1Fk2qrfgYmgZ83F9Fk/hexEeGMRQ3Boh1X6esXDkJAK4EPjcST8RzvUOs5tPZGoU7toH4zWcyP9UmvPCNq3J5jV7dXLoxkvG0CT+6x"
`endif