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




module rst_ctrl #(
   parameter  HIP_COM = "HIP_NATIVE"
)
(
   input    clk_sys,             
   input    clk_100m,            
   input    pcie_reset_status,   
   input    pcie_cold_rst_ack_n, 
   input    pcie_warm_rst_ack_n, 
   input    pll_locked_i,
   input    initiate_warmrst_req,
   output   initiate_rst_req_rdy,

   input    ninit_done,          
   output   pll_locked_o,
   output   rst_n_sys,           
   output   rst_n_100m,          
   output   pwr_good_n,          
   output   pcie_cold_rst_n,     
   output   pcie_warm_rst_n      
);

wire  rst_n, rst_n_sync, rst_n_sys_i, rst_n_100m_i;
wire  npor;
logic pll_locked;
logic pll_locked_sys, pll_locked_100m, pll_locked_sys_sync, pll_locked_100m_sync;

assign pll_locked_o = pll_locked_i;

generate
   if (HIP_COM == "HIP_NATIVE") begin
      assign pll_locked = 1'b1;
      assign rst_n_sys_i = npor && pll_locked && ~pcie_reset_status;
      assign rst_n_100m_i = npor && pll_locked && ~pcie_reset_status;
   end else begin

      altera_std_synchronizer clk_sys_pll_locked   ( .clk(clk_sys),     .reset_n(1'b1), .din(pll_locked_i), .dout(pll_locked_sys_sync) );

      always_ff@(posedge clk_sys)
      begin
            pll_locked_sys <= (pll_locked_sys_sync === 1'b1) ? 1'b1 : 1'b0;
      end

      altera_std_synchronizer clk_100m_pll_locked   ( .clk(clk_100m),     .reset_n(1'b1), .din(pll_locked_i), .dout(pll_locked_100m_sync) );

      always_ff@(posedge clk_100m)
      begin
            pll_locked_100m <= (pll_locked_100m_sync === 1'b1) ? 1'b1 : 1'b0;
      end

      assign rst_n_sys_i = npor && pll_locked_sys && ~pcie_reset_status;
      assign rst_n_100m_i = npor && pll_locked_100m && ~pcie_reset_status;
   end
endgenerate


assign initiate_rst_req_rdy = initiate_warmrst_req;

assign npor  = ~ninit_done; 

fim_resync #(
   .SYNC_CHAIN_LENGTH(3),
   .WIDTH(1),
   .INIT_VALUE(0),
   .NO_CUT(1)
) rst_in_resync (
   .clk   (clk_sys),
   .reset (~rst_n_sys_i),
   .d     (1'b1),
   .q     (rst_n_sync)
);


logic pcie_cold_rst_ack_n_sync;
logic pcie_warm_rst_ack_n_sync;
logic pcie_rst_ack;
logic pcie_rst_release;
logic pcie_rst_n;
logic fim_rst_n;

`ifdef INCLUDE_PCIE_SS
   fim_resync #(
      .SYNC_CHAIN_LENGTH(3),
      .WIDTH(2),
      .INIT_VALUE(0),
      .NO_CUT(1)
   ) pcie_cold_rst_ack_sync (
      .clk   (clk_sys),
      .reset (1'b0),
      .d     ({pcie_cold_rst_ack_n, pcie_warm_rst_ack_n}),
      .q     ({pcie_cold_rst_ack_n_sync, pcie_warm_rst_ack_n_sync})
   );
`else
   assign pcie_cold_rst_ack_n_sync = pcie_rst_n;
   assign pcie_warm_rst_ack_n_sync = pcie_rst_n;
`endif

assign pcie_rst_ack = (~pcie_cold_rst_ack_n_sync && ~pcie_warm_rst_ack_n_sync);
assign pcie_rst_release = (pcie_rst_n && pcie_cold_rst_ack_n_sync && pcie_warm_rst_ack_n_sync);

always_ff @(posedge clk_sys) begin
   if (~rst_n_sync) begin
      pcie_rst_n <= 1'b0;
   end else begin
     if (~pcie_rst_n && pcie_rst_ack) begin
         pcie_rst_n <= 1'b1;
     end
   end
end
always_ff @(posedge clk_sys) begin
   if (~rst_n_sync) begin
      fim_rst_n  <= 1'b0;
   end else begin
      if (~fim_rst_n && pcie_rst_release) begin
         fim_rst_n <= 1'b1;
      end
   end
end


assign pcie_cold_rst_n = pcie_rst_n;
assign pcie_warm_rst_n = pcie_rst_n;

fim_resync #(
   .SYNC_CHAIN_LENGTH(3),
   .WIDTH(1),
   .INIT_VALUE(0),
   .NO_CUT(1)
) rst_clk_sys_resync (
   .clk   (clk_sys),
   .reset (~rst_n_sys_i | ~fim_rst_n),
   .d     (1'b1),
   .q     (rst_n_sys)
);

fim_resync #(
   .SYNC_CHAIN_LENGTH(3),
   .WIDTH(1),
   .INIT_VALUE(0),
   .NO_CUT(1)
) rst_clk100m_resync (
   .clk   (clk_100m),
   .reset (~rst_n_100m_i | ~fim_rst_n),
   .d     (1'b1),
   .q     (rst_n_100m)
);


endmodule
`ifdef QUESTA_INTEL_OEM
`pragma questa_oem_00 "8aFrJEo1yygebd74a8md/yDcSVKbulzF1F2rtf3+aaForgMz73uba/yHNeFYFZ2YkKYCwYjw7rtt+Xp0uiKSB+4MrmFoL2bMZg2i7d7DUOZRRGYTJjtW7T7i44nVqnxPkSnp2CAJvOPhz4lx7r98H1ayc7/YAuv9G1orwsk6EYg8bE3Js4qZRDWPh+vBOh/Wr9Wf+2AzcYIwsz08/kzICnXwrr6XSrKXNoszeDhgFSjvUDSAJktZRGpl2jXPAkkruDypiiQXsd/1eGVjcdH+AVKpTFtIPkwhAgCGOa2T0fUeg/NM4ddHHC+20ukfXxxVWkuYfqvxLrv7pliU6VMZJXdZM+R9UVNnb9kNYYyA5QSOOkQBRHHEzu5F+/FRresuBDfmQLewX4BJKYbuObpBZhYvOlvMDJiP4VLTz6/1jGguJEPSLikEQnXEDO5kDulWaWDVPQ2hVz+lwMQrA2M/azDGm9w7AqGeB0m3UpKe6uM0geml4z3nGoGTCyCKtn4iEVMsdYAzh6nhbqQsu5Dd6VAQ72qv2YLmzELuaC3GheLJFRP/c+qMyKasrb76eBnt15FVs03uaAEp3dKRv6iL+sjotkB+qrwTFR/kLrJsh+eQOG769bGELLAOMAdBnEi/su6M/vHahyaWHSpwuCN6vl1IYh5FQb/EBg6AUcRZD3yrR+wh3gXUYN+ZeJKAGpsu8CT4CBRc5wVQtM1JPbMYtDFiWkUtKFQtH5iGeKWaFUd6yjSCoq4h3JOs7QKffvnLENJyedgEsvzDzJ6N/sGZ5t1EkxpBEXpMhtceTm4H5zmb7SJwKp9lVMa5+w3GS0ynt7Mk7JHkxnK6+IuaOd1sK9pZ7s30qOTUFM3+DvWXPq+Nch6bX5+NtzhFnj2/yG+o9O/72QtohVzsmACZLXQtqCIsBGU1kr+K8Q+zukysGkhMuJeul4ii/oksavgOArTICXUWkxxoop2AdJYDr8+SqSrAuXP6H3ygzdUv7HGsTd3P7uEL2d7JJhxuz3lCRHCR"
`endif