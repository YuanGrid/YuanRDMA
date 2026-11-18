// *************************************************************************
//
// Copyright 2020 Xilinx, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// *************************************************************************
// Address range: 0x0000 - 0x0FFF
// Address width: 12-bit
//
// Register description
// -----------------------------------------------------------------------------
//  Address | Mode |          Description
// -----------------------------------------------------------------------------
//   0x000  |  RO  | Build timestamp register
// -----------------------------------------------------------------------------
//   0x004  |  WO  | System reset register
// -----------------------------------------------------------------------------
//   0x008  |  RO  | System status register
// -----------------------------------------------------------------------------
//   0x00C  |  WO  | Shell reset register
// -----------------------------------------------------------------------------
//   0x010  |  RO  | Shell status register
// -----------------------------------------------------------------------------
//   0x014  |  WO  | User reset register
// -----------------------------------------------------------------------------
//   0x018  |  RO  | User status register
// -----------------------------------------------------------------------------

//speed_unknow  = 0x0
//speed_10m     = 0x1
//speed_100m    = 0x2
//speed_1g      = 0x4
//speed_10g     = 0x8
//speed_40g     = 0x10
//speed_100g    = 0x20
//speed_50g     = 0x40
//speed_25g     = 0x80
//speed_200g    = 0x100
//speed_400g    = 0x200

`timescale 1ns/1ps
`include "time.v"
module system_config_register #(
  parameter [31:0] BUILD_TIMESTAMP = 32'h01010000,
  parameter [15:0] BUILD_PF0_PORT_NUMBER = 16'd1,
  parameter [15:0] BUILD_PF1_PORT_NUMBER = 16'd0,
  parameter [15:0] BUILD_PF2_PORT_NUMBER = 16'd0,
  parameter [15:0] BUILD_PF3_PORT_NUMBER = 16'd0,
  parameter [15:0] BUILD_PORT_SPEED = 16'h200
  
) (
    input   wire    [27:0]              s_avm_addr ,
    input   wire                        s_avm_read ,
    input   wire                        s_avm_write,
    input   wire    [31:0]              s_avm_wdat ,
    output  wire                        s_avm_wait ,
    output  wire    [31:0]              s_avm_rdat ,
    output  wire                        s_avm_rvld ,
    output  wire    [1:0]               s_avm_rspo ,
    output  wire                        s_avm_wrsp ,

  output [31:0] shell_rstn,
  input  [31:0] shell_rst_done,
  output [31:0] user_rstn,
  input  [31:0] user_rst_done,
  
  output        statis_cnt_clear_en,

  input  [63:0]  debug_rx_path_eop_cnt       ,
  input  [63:0]  debug_rx_rcv_last0_cnt      ,
  input  [63:0]  debug_rx_rcv_last1_cnt      ,
  input  [63:0]  debug_qdma_d2h_last_cnt     ,
  input  [63:0]  debug_pcie_d2h_last_cnt     ,
  input  [63:0]  debug_stream_mark0_eop_cnt  ,
  input  [63:0]  debug_stream_mark1_eop_cnt  ,
  input  [63:0]  debug_pcie_h2d_eop_cnt      ,
  input  [63:0]  debug_qdma_h2d_eop_cnt      ,
  input  [63:0]  debug_axis_select_eop_cnt   ,
  input  [63:0]  debug_segm2gap_eop_cnt      ,
  input  [63:0]  debug_gap2mac_eop_cnt       ,
  input  [63:0]  debug_mod_int_status_reg    ,
  input  [31:0]  debug_eth_fcs_err_cnt       , 
  input  [31:0]  debug_eth_mfmd_err_cnt      , 
  input  [31:0]  debug_eth_under_over_err_cnt, 
  input  [31:0]  debug_eth_plen_err_cnt      ,
  input  [31:0]  debug_eth_fifo_full_err_cnt , 
  input  [9:0]   fpga_temp,
  input          link_up0,
  input          link_up1,
  input          link_up2,
  input          link_up3, 
  input          stat_rx_local_fault_0,                        
  input          stat_rx_local_fault_1,                        
  input          stat_rx_local_fault_2,                        
  input          stat_rx_local_fault_3,                        
  input          stat_rx_block_lock_0,                          
  input          stat_rx_block_lock_1,                          
  input          stat_rx_block_lock_2,                          
  input          stat_rx_block_lock_3,                          
  input          stat_rx_remote_fault_0,                      
  input          stat_rx_remote_fault_1,                      
  input          stat_rx_remote_fault_2,                      
  input          stat_rx_remote_fault_3,                      
	
  output [63:0]  gtime_value,
  output         gtime_set,
  
  output  [1:0]  rocev2_stamp_en,
  
  input         aclk,
  input         aresetn
);

  localparam C_ADDR_W = 28;

  // Register address
  localparam REG_DATE            = 12'h000;
  localparam REG_SYSTEM_RST      = 12'h004;
  localparam REG_SYSTEM_STATUS   = 12'h008;
  localparam REG_SHELL_RST       = 12'h00C;
  localparam REG_SHELL_STATUS    = 12'h010;
  localparam REG_USER_RST        = 12'h014;
  localparam REG_USER_STATUS     = 12'h018;

  localparam REG_TIMESTAMP_S     = 12'h01C;
  localparam REG_TIMESTAMP_M     = 12'h020;
  localparam REG_TIMESTAMP_H     = 12'h024;
  localparam REG_TIMESTAMP_En    = 12'h028;  
  localparam REG_VERSION         = 12'h02C;
  localparam REG_TIME            = 12'h034;
  
  localparam REG_FPGA_TEMPER     = 12'h038;
  
  localparam REG_PF0_PORT_NUMBER = 12'h040;  
  localparam REG_PF1_PORT_NUMBER = 12'h044;    
  localparam REG_PF2_PORT_NUMBER = 12'h048;
  localparam REG_PF3_PORT_NUMBER = 12'h04C;  
  localparam REG_PORT_SPEED      = 12'h050; 

  localparam REG_ROCEV2_EN_0     = 12'h060;
  localparam REG_ROCEV2_EN_1     = 12'h064;
  localparam REG_ROCEV2_EN_2     = 12'h068;
  localparam REG_ROCEV2_EN_3     = 12'h06C;
    
  wire [31:0] fpga_build_date = `COMPILE_TIME1;
  wire [31:0] fpga_build_time = `COMPILE_TIME2;
  
  wire [3:0] speed_bits  = 4'd4; // 0: 10G, 1:25G 3:100G,others reversed
  wire [3:0] ports_bits   = 4'd1;  //  num of ports
  wire [1:0] iftype_bits  = 2'd0; //  0:  FIRBE , 1:COPPER 2: WIFI
  wire [1:0] brdtype_bits = 2'd0;  // 0:"27L" 1:"47L" 
  wire [3:0] hw_ver_bits  = 4'd0;   //  0:"A",1:"B"....
  
  wire [31:0] fpgabrd_version = {16'd0,speed_bits,ports_bits,iftype_bits,brdtype_bits,hw_ver_bits};

  
  reg          [31:0] reg_build_timestamp;
  reg                 reg_system_rst;
  reg                 reg_system_status;
  reg          [31:0] reg_shell_rst;
  reg          [31:0] reg_shell_status;
  reg          [31:0] reg_user_rst;
  reg          [31:0] reg_user_status;

  reg          [31:0] shell_rst_last;
  reg          [31:0] user_rst_last;
  reg                 system_rst_last;
  wire                system_rst;
  wire                system_rst_done;
  
  wire                reg_en;
  wire                reg_we;
  wire [C_ADDR_W-1:0] reg_addr;
  wire         [31:0] reg_din;
  reg          [31:0] reg_dout;

  reg          [31:0] reg_build_timestamp_s;
  reg          [31:0] reg_build_timestamp_min;
  reg          [31:0] reg_build_timestamp_hour;
  reg          [2:0]  reg_build_timestamp_en;  
  
  reg                 reg_statis_cnt_clear_en;
  
  reg          [15:0] reg_pf0_port_number = BUILD_PF0_PORT_NUMBER;
  reg          [15:0] reg_pf1_port_number = BUILD_PF1_PORT_NUMBER;  
  reg          [15:0] reg_pf2_port_number = BUILD_PF2_PORT_NUMBER;  
  reg          [15:0] reg_pf3_port_number = BUILD_PF3_PORT_NUMBER;
  reg          [15:0] reg_port_speed      = BUILD_PORT_SPEED;  
  
  reg          [1:0]  reg_rdma_stamp_en; 
  
  assign statis_cnt_clear_en = reg_statis_cnt_clear_en;
  
  //build_datetime #(0) build_stamp(fpga_build_date,fpga_build_time);
  
  avm_register #(
    .CLOCKING_MODE ("common_clock"),
    .ADDR_W        (C_ADDR_W),
    .DATA_W        (32)
  ) axil_reg_inst (
        .avm_addr                     (s_avm_addr         ),
        .avm_read                     (s_avm_read         ),
        .avm_write                    (s_avm_write        ),
        .avm_wdat                     (s_avm_wdat         ),
        .avm_wait                     (s_avm_wait         ),
        .avm_rdat                     (s_avm_rdat         ),
        .avm_rvld                     (s_avm_rvld         ),
        .avm_rspo                     (s_avm_rspo         ),
        .avm_wrsp                     (s_avm_wrsp         ),

    .reg_en         (reg_en),
    .reg_we         (reg_we),
    .reg_addr       (reg_addr),
    .reg_din        (reg_din),
    .reg_dout       (reg_dout),

    .clk        (aclk),
    .rst_n       (aresetn)
  );
  
  always@(posedge aclk) begin
    if(~aresetn)
        reg_rdma_stamp_en <= 2'b00;
    else if(reg_en && reg_we && reg_addr == REG_ROCEV2_EN_0)
        reg_rdma_stamp_en[0] <= reg_din[0];
    else if(reg_en && reg_we && reg_addr == REG_ROCEV2_EN_1)
        reg_rdma_stamp_en[1] <= reg_din[0];
  end
  assign rocev2_stamp_en = reg_rdma_stamp_en;

  always @(posedge aclk) begin
    if (~aresetn) begin
      reg_dout <= 0;
    end
    else if (reg_en && ~reg_we) begin
      case (reg_addr)
        REG_DATE: begin
          reg_dout <= {8'hba,fpga_build_date[23:0]};
        end
        REG_SYSTEM_STATUS: begin
          reg_dout <= {31'b0, reg_system_status};
        end
        REG_SHELL_STATUS: begin
          reg_dout <= reg_shell_status;
        end
        REG_USER_STATUS: begin
          reg_dout <= reg_user_status;
        end
		REG_TIMESTAMP_S: begin
		  reg_dout <= reg_build_timestamp_s;
		end
		REG_TIMESTAMP_M: begin
		  reg_dout <= reg_build_timestamp_min;
		end		
		REG_TIMESTAMP_H: begin
		  reg_dout <= reg_build_timestamp_hour;
		end		
		REG_TIMESTAMP_En: begin
		  reg_dout <= reg_build_timestamp_en;
		end
        
        REG_VERSION: begin
          reg_dout <= fpgabrd_version;
        end
        
        REG_TIME: begin
          reg_dout <= fpga_build_time;
        end
		
		REG_FPGA_TEMPER : begin
          reg_dout <= {21'd0,fpga_temp};
        end			

		REG_PF0_PORT_NUMBER: begin
		  reg_dout <= reg_pf0_port_number;
		end		
		REG_PF1_PORT_NUMBER: begin
		  reg_dout <= reg_pf1_port_number;
		end		
		REG_PF2_PORT_NUMBER: begin
		  reg_dout <= reg_pf2_port_number;
		end				
		REG_PF3_PORT_NUMBER: begin
		  reg_dout <= reg_pf3_port_number;
		end				
		REG_PORT_SPEED: begin
		  reg_dout <= reg_port_speed;
		end	
		REG_ROCEV2_EN_0:begin
		  reg_dout <= {31'd0,reg_rdma_stamp_en[0]};
		end
		REG_ROCEV2_EN_1:begin
		  reg_dout <= {31'd0,reg_rdma_stamp_en[1]};
		end
		12'h030: begin
		  reg_dout <= {30'd0,reg_statis_cnt_clear_en};
		end
		12'h0E4:reg_dout <= debug_eth_fcs_err_cnt       ;
		12'h0E8:reg_dout <= debug_eth_mfmd_err_cnt      ;
		12'h0EC:reg_dout <= debug_eth_under_over_err_cnt;
		12'h0F0:reg_dout <= debug_eth_plen_err_cnt      ;
		12'h0F4:reg_dout <= debug_eth_fifo_full_err_cnt ;
		12'h0F8:reg_dout <= debug_mod_int_status_reg[31:0] ;
		12'h0fC:reg_dout <= debug_mod_int_status_reg[63:32];
		12'h100:reg_dout <= debug_rx_path_eop_cnt       ;
		12'h110:reg_dout <= debug_rx_rcv_last0_cnt      ;
		12'h120:reg_dout <= debug_rx_rcv_last1_cnt      ;
    12'h130:reg_dout <= debug_qdma_d2h_last_cnt     ;
		12'h140:reg_dout <= debug_pcie_d2h_last_cnt     ;
		12'h150:reg_dout <= debug_stream_mark0_eop_cnt  ;
		12'h160:reg_dout <= debug_stream_mark1_eop_cnt  ;
		12'h170:reg_dout <= debug_pcie_h2d_eop_cnt      ;
		12'h180:reg_dout <= debug_qdma_h2d_eop_cnt      ;
		12'h190:reg_dout <= debug_axis_select_eop_cnt   ;
		12'h1a0:reg_dout <= debug_segm2gap_eop_cnt      ;
		12'h1b0:reg_dout <= debug_gap2mac_eop_cnt       ;
		12'h1b8: begin
		  reg_dout <= {24'd0,stat_rx_remote_fault_3,stat_rx_remote_fault_2,stat_rx_remote_fault_1,stat_rx_remote_fault_0,stat_rx_local_fault_3,stat_rx_local_fault_2,stat_rx_local_fault_1,stat_rx_local_fault_0};
		end
		12'h1bc: begin
		  reg_dout <= {28'd0,link_up3,link_up2,link_up1,link_up0};
		end		

        default: begin
          reg_dout <= 32'hDEADBEEF;
        end
      endcase
    end
  end

  always @(posedge aclk) begin
    if (~aresetn) begin
      shell_rst_last  <= 0;
      user_rst_last   <= 0;
      system_rst_last <= 1'b0;
    end
    else begin
      shell_rst_last  <= reg_shell_rst;
      user_rst_last   <= reg_user_rst;
      system_rst_last <= reg_system_rst;
    end
  end

  // Submodule resets are triggered either by writing to the reset registers, or
  // through power-up reset.  These reset signals are active-low and valid for a
  // single cycle.
  generate for (genvar ii = 0; ii < 32; ii = ii + 1) begin : shell_rstn_block
    assign shell_rstn[ii] = ~(system_rst || (~shell_rst_last[ii] && reg_shell_rst[ii]));
    assign user_rstn[ii]  = ~(system_rst || (~user_rst_last[ii] && reg_user_rst[ii]));
  end
  endgenerate

  assign system_rst      = ~system_rst_last && reg_system_rst;
  assign system_rst_done = (&shell_rst_done) && (&user_rst_done);

  // System reset register (write-only)
  //
  // Writing to this register initiates a system-level reset, which lasts until
  // all the submodules are out of reset.  A system-level reset is also done on
  // power up.
  always @(posedge aclk) begin
    if (~aresetn) begin
      reg_system_rst <= 1'b1;
    end
    else if (reg_en && reg_we && reg_addr == REG_SYSTEM_RST) begin
      reg_system_rst <= 1'b1;
    end
    else if (system_rst_done) begin
      reg_system_rst <= 0;
    end
  end
  
  assign gtime_value = {reg_build_timestamp_min,reg_build_timestamp_s};
  assign gtime_set   = reg_build_timestamp_en[0];

  always @(posedge aclk) 
  begin
	if (~aresetn) 
		reg_build_timestamp_en <= 3'd0;
	else if (reg_en && reg_we && reg_addr == REG_TIMESTAMP_En)
		reg_build_timestamp_en[0] <= reg_din[0];
	else
		reg_build_timestamp_en[0] <= 1'b0;
  end 
  
    always @(posedge aclk) 
  begin
	if (~aresetn) 
		reg_build_timestamp_s <= 32'd0;
	else if (reg_en && reg_we && reg_addr == REG_TIMESTAMP_S)
		reg_build_timestamp_s <= reg_din[31:0];
  end
  
    always @(posedge aclk) 
  begin
	if (~aresetn) 
		reg_build_timestamp_min <= 8'd0;
	else if (reg_en && reg_we && reg_addr == REG_TIMESTAMP_M)
		reg_build_timestamp_min <= reg_din[31:0];
  end  
  
  always @(posedge aclk) 
  begin
	if (~aresetn) 
		reg_build_timestamp_hour <= 8'd0;
	else if (reg_en && reg_we && reg_addr == REG_TIMESTAMP_H)
		reg_build_timestamp_hour <= reg_din[31:0];
  end   

  always @(posedge aclk) 
  begin
	if (~aresetn) 
		reg_statis_cnt_clear_en <= "0";
	else if (reg_en && reg_we && reg_addr == 12'h030)
		reg_statis_cnt_clear_en <= reg_din[0];
  end   
  
  // Shell reset register (write-only)
  //
  // 31:3  - reserved
  // 2     - reset for the CMAC subsystem CMAC1
  // 1     - reset for the CMAC subsystem CMAC0
  // 0     - reset for the QDMA subsystem
  // 
  // Writing 1 to a bit of this register initiates a submodule-level reset in
  // the shell logic, which lasts until the corresponding submodule is out of
  // reset.  Mapping between bits and submodules are as follows.
  generate for (genvar ii = 0; ii < 32; ii = ii + 1) begin :reg_shell_rst_block
    always @(posedge aclk) begin
      if (~aresetn) begin
        reg_shell_rst[ii] <= 1'b0;
      end
      else if (reg_en && reg_we && reg_addr == REG_SHELL_RST && reg_din[ii]) begin
        reg_shell_rst[ii] <= 1'b1;
      end
      else if (shell_rst_done[ii]) begin
        reg_shell_rst[ii] <= 0;
      end
    end
  end
  endgenerate

  // User reset register (write-only)
  //
  // Writing 1 to a bit of this register initiates a submodule-level reset in
  // the user logic, which lasts until the corresponding submodule is out of
  // reset.  Mapping between bits and submodules are determined by how the user
  // logic is connected in the top level.
  generate for (genvar ii = 0; ii < 32; ii = ii + 1) begin:reg_user_rst_block
    always @(posedge aclk) begin
      if (~aresetn) begin
        reg_user_rst[ii] <= 1'b0;
      end
      else if (reg_en && reg_we && reg_addr == REG_USER_RST && reg_din[ii]) begin
        reg_user_rst[ii] <= 1'b1;
      end
      else if (user_rst_done[ii]) begin
        reg_user_rst[ii] <= 0;
      end
    end
  end
  endgenerate

  // System status register (read-only)
  // 
  // 31:1  - reserved
  // 0     - system reset done
  // 
  // The register shows the system reset status.
  always @(posedge aclk) begin
    if (~aresetn) begin
      reg_system_status <= 1'b0;
    end
    else if (system_rst) begin
      reg_system_status <= 1'b0;
    end
    else if (system_rst_done) begin
      reg_system_status <= 1'b1;
    end
  end

  // Shell status register (read-only)
  //
  // 31:3  - reserved
  // 2     - CMAC subsystem CMAC1 reset done
  // 1     - CMAC subsystem CMAC0 reset done
  // 0     - QDMA subsystem reset done
  //
  // This register shows the reset status of shell submodules.
  generate for (genvar ii = 0; ii < 32; ii = ii + 1) begin :reg_shell_status_block
    always @(posedge aclk) begin
      if (~aresetn) begin
        reg_shell_status[ii] <= 1'b0;
      end
      else if (~shell_rstn[ii]) begin
        reg_shell_status[ii] <= 1'b0;
      end
      else if (shell_rst_done[ii]) begin
        reg_shell_status[ii] <= 1'b1;
      end
    end
  end
  endgenerate

  // User status register (read-only)
  //
  // This register shows the reset status of user submodules.  Mapping between
  // bits and submodules are determined by how the user logic is connected in
  // the top level.
  generate for (genvar ii = 0; ii < 32; ii = ii + 1) begin:reg_user_status_block
    always @(posedge aclk) begin
      if (~aresetn) begin
        reg_user_status[ii] <= 1'b0;
      end
      else if (~user_rstn[ii]) begin
        reg_user_status[ii] <= 1'b0;
      end
      else if (user_rst_done[ii]) begin
        reg_user_status[ii] <= 1'b1;
      end
    end
  end
  endgenerate

endmodule
