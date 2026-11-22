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


// $File: //acds/rel/26.1.1/ip/iconnect/avalon_st/altera_avalon_dc_fifo/altera_dcfifo_synchronizer_bundle.v $
// $Revision: #1 $
// $Date: 2026/05/07 $
// $Author: psgswbuild $
//-------------------------------------------------------------------------------

`timescale 1 ns / 1 ns
module altera_dcfifo_synchronizer_bundle(
                                     clk,
                                     reset_n,
                                     din,
                                     dout
                                     );
   parameter WIDTH = 1;
   parameter DEPTH = 3;   
   parameter retiming_reg_en = 0;

   input clk;
   input reset_n;
   input [WIDTH-1:0] din;
   output [WIDTH-1:0] dout;
   
   genvar i;
   
   generate
      for (i=0; i<WIDTH; i=i+1)
        begin : sync
           altera_std_synchronizer_nocut #(.depth(DEPTH), .retiming_reg_en(retiming_reg_en))
                                   u (
                                      .clk(clk), 
                                      .reset_n(reset_n), 
                                      .din(din[i]), 
                                      .dout(dout[i])
                                      );
        end
   endgenerate
   
endmodule 

`ifdef QUESTA_INTEL_OEM
`pragma questa_oem_00 "OraYGnqZAGf5M3WGiRIUztRR2XPfDUWtSPZUayeiSjFSmrTPINcfoCe/2a8UnQ2IC7jZaYSgYXZKXilBbr8NDXIXu9io8f7PC+p4+oQf/uerp1rLLS7PivmzhjlGjSNWPE+7KYfnsL2S3nAzUxUd2zNZBKOBEGfZToff5axnXurFANpNl/fuHMpgeS08IiPY21928m0zINQukBxVZxQw+UgJrul+Kw3td6vC1MD9Kfwh04wW45nTH5fMiKOy/R8Iwe5dSP2ZHoBV13qbp0U9SCbAbNj3fCFthovl7lBFaWl04Lo8p+5f+rkMtl/A3H35HTQXCghWW7Ybj+6xmxS7EfyTq6cf5oaqeeolCcZq8Zj48IvVamr6E9MELPEUOBpRV+mV57sxk9IB1lTm1IJ/wGIjaHUxb3p6OPqYVB26UGWe8O8b905g1P99hmQFb/eLXsL2AcD7Sg9pg/DfMdAySMFEtiKSJ4s5lxDX6cwa5JrAxKMINYUfaFsijuLBPP2f/7l55lznSOrp2uslf4mNjig3WEhvBYJoqRS2/DF8yH+PU5Et9fFU4ij7UT3N+Pkc5BO7iQ+ob+10d5/yQkvqhRMG1tj+TzyPfdjBijydUh+CJYSMGN2SwjmmxfspJq0MvWn2NgauMdOIoGDMER9ZT/p/Sm1zjPq1QpQO1KcprGZfTRIDGxhlTrCsYFCJ+wNHzxmD2yb93OT9wd0TtH4WLoy5rNPdYWbYjwn03bM/U7fLr9C3y94W4Ps8FnozUq8+oiD2jFUPxXowNEEbPkiH6EM7YfzOoPWMN6hASYQEaUCg+bvXqpuPnmOaKXcz4IRnYiyyxDGhRTOqRUpa++cbj7LlvHBo0DJ8JwkqbK+rSrmzKop+215gueVeKzPfWuZEDLPnfcmLd3Lp2KS4ZstEGVpfgHeEqIcAlzBg+/Ujcdi/qu8aHGxYItIOVKKBNbUYStC+rWWzk0SlhNYcZ6taoNUfbAchl35vSAH9u1bDJGo7NAeipV2cMnzPlVMkE2yV"
`endif