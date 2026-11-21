
`include "../top/global_define.vh"

module eth_ctl_csr (/*AUTOARG*/
   // Outputs
   sir_dack, sir_rdat, eth_ctl_addr, eth_ctl_wdat, eth_ctl_write,
   eth_ctl_read, eth_ctl_byte,
   // Inputs
   rst, clk, sir_selh, sir_read, sir_addr, sir_wdat, eth_ctl_rdat,
   eth_ctl_rvld, eth_ctl_wait
   ) ;
   input  wire                 rst;
   input  wire 				   clk;

   input  wire 				   sir_selh;
   input  wire 				   sir_read;
   output  reg 				   sir_dack;
   
   input  wire [15:0] 		   sir_addr;
   input  wire [31:0] 		   sir_wdat;
   output  reg [31:0] 		   sir_rdat;

   output  reg [23:0] 		   eth_ctl_addr;
   output  reg [31:0] 		   eth_ctl_wdat;
   output  reg 				   eth_ctl_write;
   output  reg 				   eth_ctl_read;
   output  reg [3:0]		   eth_ctl_byte = 4'hf;
   input  wire [31:0] 		   eth_ctl_rdat;
   input  wire 				   eth_ctl_rvld;
   input  wire 				   eth_ctl_wait;
   
   reg		sir_selh_d1;
   reg		sir_selh_d2;
   wire		sir_selh_pd;
   
   always @ ( posedge clk ) begin
		sir_selh_d1 <= sir_selh;
		sir_selh_d2 <= sir_selh_d1;
   end
   
   assign sir_selh_pd = sir_selh_d1 && (~sir_selh_d2);
   
   always @ ( posedge clk ) begin
	  eth_ctl_addr[23:0] <= {8'h00,sir_addr[15:0]};
	  
	  if(sir_selh_pd == 1'b1 && sir_read == 1'b0)
		eth_ctl_write   <= 1'b1;
	  else if(eth_ctl_wait == 1'b0)
		eth_ctl_write   <= 1'b0;

	  if(sir_selh == 1'b1 && sir_read == 1'b0)
		eth_ctl_wdat    <= sir_wdat[31:0];
	  
	  if(sir_selh_pd == 1'b1 && sir_read == 1'b1)
		eth_ctl_read    <= 1'b1;
	  else if(eth_ctl_wait == 1'b0)
		eth_ctl_read    <= 1'b0;
   end // always @ ( posedge clk )

   reg                        wr_ack;
   reg 						  rd_ack;
   reg [31:0] 				  sir_rdat_p;

   reg 						  eth_ctl_rvld_d;
   reg 						  eth_ctl_rvld_d2;
   
   always @ ( posedge clk ) begin

	  eth_ctl_rvld_d  <= eth_ctl_rvld;
	  eth_ctl_rvld_d2 <= eth_ctl_rvld_d;
	  
	  if((eth_ctl_write == 1'b1) && (eth_ctl_wait == 1'b0))
		wr_ack <= 1'b1;
	  else if(sir_selh == 1'b0)
		wr_ack <= 1'b0;

	  if(sir_selh == 1'b1 && eth_ctl_rvld_d2 == 1'b1)
		rd_ack <= 1'b1;
	  else if(sir_selh == 1'b0)
		rd_ack <= 1'b0;

	  if(eth_ctl_rvld == 1'b1)
		sir_rdat_p <= eth_ctl_rdat[31:0];
	  
	  if(sir_selh == 1'b1)
		sir_rdat <= sir_rdat_p;
	  else
		sir_rdat <= 32'h0;

	  sir_dack <= wr_ack | rd_ack;
   end

   

endmodule // mb_ctl_csr

