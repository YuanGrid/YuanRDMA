
`include "../top/global_define.vh"

module mb_ctl_csr (/*AUTOARG*/
   // Outputs
   sir_dack, sir_rdat, sdm_mb_addr, sdm_mb_wdat, sdm_mb_write,
   sdm_mb_read,
   // Inputs
   rst, clk, sir_selh, sir_read, sir_addr, sir_wdat, sdm_mb_rdat,
   sdm_mb_rvld, sdm_mb_wait
   ) ;
   input  wire                 rst;
   input  wire 				   clk;

   input  wire 				   sir_selh;
   input  wire 				   sir_read;
   output  reg 				   sir_dack;
   
   input  wire [7:0] 		   sir_addr;
   input  wire [31:0] 		   sir_wdat;
   output  reg [31:0] 		   sir_rdat;

   output  reg [3:0] 		   sdm_mb_addr;
   output  reg [31:0] 		   sdm_mb_wdat;
   output  reg 				   sdm_mb_write;
   output  reg 				   sdm_mb_read;
   input  wire [31:0] 		   sdm_mb_rdat;
   input  wire 				   sdm_mb_rvld;
   input  wire 				   sdm_mb_wait;
   
   reg		sir_selh_d1;
   reg		sir_selh_d2;
   wire		sir_selh_pd;
   
   always @ ( posedge clk ) begin
		sir_selh_d1 <= sir_selh;
		sir_selh_d2 <= sir_selh_d1;
   end
   
   assign sir_selh_pd = sir_selh_d1 && (~sir_selh_d2);
   
   always @ ( posedge clk ) begin
	  sdm_mb_addr[3:0] <= sir_addr[3:0];
	  
	  if(sir_selh_pd == 1'b1 && sir_read == 1'b0)
		sdm_mb_write   <= 1'b1;
	  else if(sdm_mb_wait == 1'b0)
		sdm_mb_write   <= 1'b0;

	  if(sir_selh == 1'b1 && sir_read == 1'b0)
		sdm_mb_wdat    <= sir_wdat;
	  
	  if(sir_selh_pd == 1'b1 && sir_read == 1'b1)
		sdm_mb_read    <= 1'b1;
	  else if(sdm_mb_wait == 1'b0)
		sdm_mb_read    <= 1'b0;
   end // always @ ( posedge clk )

   reg                        wr_ack;
   reg 						  rd_ack;
   reg [31:0] 				  sir_rdat_p;

   reg 						  sdm_mb_rvld_d;
   reg 						  sdm_mb_rvld_d2;
   
   always @ ( posedge clk ) begin

	  sdm_mb_rvld_d  <= sdm_mb_rvld;
	  sdm_mb_rvld_d2 <= sdm_mb_rvld_d;
	  
	  if((sdm_mb_write == 1'b1) && (sdm_mb_wait == 1'b0))
		wr_ack <= 1'b1;
	  else if(sir_selh == 1'b0)
		wr_ack <= 1'b0;

	  if(sir_selh == 1'b1 && sdm_mb_rvld_d2 == 1'b1)
		rd_ack <= 1'b1;
	  else if(sir_selh == 1'b0)
		rd_ack <= 1'b0;

	  if(sdm_mb_rvld == 1'b1)
		sir_rdat_p <= sdm_mb_rdat;
	  
	  if(sir_selh == 1'b1)
		sir_rdat <= sir_rdat_p;
	  else
		sir_rdat <= 32'h0;

	  sir_dack <= wr_ack | rd_ack;
   end

   

endmodule // mb_ctl_csr

