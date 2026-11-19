
`timescale 1ns/1ps
module qdma_subsystem_function_register (
  input   wire    [27:0]              s_avm_addr ,
  input   wire                        s_avm_read ,
  input   wire                        s_avm_write,
  input   wire    [31:0]              s_avm_wdat ,
  output  wire                        s_avm_wait ,
  output  wire    [31:0]              s_avm_rdat ,
  output  wire                        s_avm_rvld ,
  output  wire    [1:0]               s_avm_rspo ,
  output  wire                        s_avm_wrsp ,

  output   [15:0] q_base,
  output   [15:0] num_q,
  output [2047:0] indir_table,
  output  [319:0] hash_key,

  input           axil_aclk,
  input           axis_aclk,
  input           axil_aresetn
);

  //`define DEFAULT_HKEY 320'h7C9C37DE18DC4386D9270F6F260374B8BFD0404B7872E224DC1B91BB011BA7A6376CC87ED6E31417
`define DEFAULT_HKEY 320'hBEAC01FA6A42B73B8030F20C77CB2DA3AE7B30B4D0CA2BCB43A38FB04167253D255B0EC26D5A56DA
  localparam C_ADDR_W = 28;

  localparam REG_QCONF      = 12'h000;
  localparam REG_TABLE_BASE = 12'h400;
  localparam REG_TABLE_MASK = 12'h600;
  localparam REG_HKEY_BASE  = 12'h600;

  reg          [31:0] reg_qconf;
  reg          [15:0] reg_table[0:127];
  reg          [31:0] reg_hkey[0:9];

  wire                reg_en;
  wire                reg_we;
  wire [C_ADDR_W-1:0] reg_addr;
  wire         [31:0] reg_din;
  reg          [31:0] reg_dout;

  avm_register #(
    .CLOCKING_MODE ("common_clock"),
    .ADDR_W        (C_ADDR_W),
    .DATA_W        (32)
  ) axil_reg_inst (
    .avm_addr                         (s_avm_addr         ),
    .avm_read                         (s_avm_read         ),
    .avm_write                        (s_avm_write        ),
    .avm_wdat                         (s_avm_wdat         ),
    .avm_wait                         (s_avm_wait         ),
    .avm_rdat                         (s_avm_rdat         ),
    .avm_rvld                         (s_avm_rvld         ),
    .avm_rspo                         (s_avm_rspo         ),
    .avm_wrsp                         (s_avm_wrsp         ),

    .reg_en         (reg_en),
    .reg_we         (reg_we),
    .reg_addr       (reg_addr),
    .reg_din        (reg_din),
    .reg_dout       (reg_dout),

    .clk      (axil_aclk),
    .rst_n   (axil_aresetn)
  );

  always @(posedge axil_aclk) begin
    if (~axil_aresetn) begin
      reg_dout <= 0;
    end
    else if (reg_en && ~reg_we) begin
      if ((reg_addr & REG_TABLE_MASK) == REG_TABLE_BASE) begin
        reg_dout[15:0] <= reg_table[reg_addr[8:2]];
      end
      else if ((reg_addr >= REG_HKEY_BASE) && (reg_addr < REG_HKEY_BASE + (10 << 2))) begin
        for (int i = 0; i < 10; i++) begin
          if (((reg_addr - REG_HKEY_BASE) >> 2) == i) begin
            reg_dout <= reg_hkey[i];
            break;
          end
        end
      end
      else begin
        case (reg_addr)
          REG_QCONF: begin
            reg_dout <= reg_qconf;
          end
          default: begin
            reg_dout <= 32'hDEADBEEF;
          end
        endcase
      end
    end
  end

  always @(posedge axil_aclk) begin
    if (~axil_aresetn) begin
      reg_qconf <= 1;
    end
    else if (reg_en && reg_we && reg_addr == REG_QCONF) begin
      reg_qconf <= reg_din;
    end
  end

  assign q_base = reg_qconf[31:16];
  assign num_q  = reg_qconf[15:0];

  generate for (genvar i = 0; i < 128; i++) begin
    always @(posedge axil_aclk) begin
      if (~axil_aresetn) begin
        reg_table[i] <= 0;
      end
      else if (reg_en && reg_we && ((reg_addr & REG_TABLE_MASK) == REG_TABLE_BASE) && (reg_addr[8:2] == i)) begin
        reg_table[i] <= reg_din[15:0];
      end
    end

    assign indir_table[16*i+:16] = reg_table[i];
  end
  endgenerate

  generate for (genvar i = 0; i < 10; i++) begin
    wire [319:0] shifted_hkey;

    assign shifted_hkey = (`DEFAULT_HKEY >> (i * 32));

    always @(posedge axil_aclk) begin
      if (~axil_aresetn) begin
        reg_hkey[i] <= shifted_hkey[31:0];
      end
      else if (reg_en && reg_we && ((reg_addr - REG_HKEY_BASE) >> 2) == i) begin
        reg_hkey[i] <= reg_din;
      end
    end

    assign hash_key[32*i+:32] = {reg_hkey[i][7:0],reg_hkey[i][15:8],reg_hkey[i][23:16],reg_hkey[i][31:24]};
  end
  endgenerate

endmodule: qdma_subsystem_function_register
