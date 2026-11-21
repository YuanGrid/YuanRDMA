`resetall
`default_nettype none
`timescale 1ns / 1ps

module axis_to_fmac_tx_fullpipeline #(
    parameter DATA_WIDTH  = 1024,       // 数据位宽
    parameter SEG_WIDTH   = 64,         // 每段位宽 (16 segments × 64 bits)
    parameter SEG_CNT     = DATA_WIDTH / SEG_WIDTH,
    parameter EMPTY_WIDTH = 48          // EOP空字节计数位宽
) (
    input wire clk,
    input wire rst_n,                   // 异步复位低有效

    // AXI-Stream 输入接口
    input wire [DATA_WIDTH-1:0]         s_axis_tdata,
    input wire [DATA_WIDTH/8-1:0]       s_axis_tkeep,
    input wire                          s_axis_tvalid,
    output wire                          s_axis_tready,
    input wire                          s_axis_tlast,

    // F-tile TX Segmented Client 输出接口
    output reg [DATA_WIDTH-1:0]         i_tx_mac_data,
    output reg [SEG_CNT-1:0]            i_tx_mac_inframe,
    output reg [EMPTY_WIDTH-1:0]        i_tx_mac_eop_empty,
    output reg                          i_tx_mac_valid,
	input wire                          o_tx_mac_ready
);

// 流水线寄存器组（三级流水）
reg [DATA_WIDTH-1:0]         tdata_pipe [0:2];
reg                          tlast_pipe [0:2];
reg [SEG_CNT-1:0]            seg_valid_pipe [0:2];
reg [47:0]                   empty_pipe [0:2];  // 无效字节

// 流水线控制信号
wire [1:0] pipe_ready;


// 计算单周期无效字节数（从LSB向MSB扫描）
function [10:0] calc_empty_bytes(input [127:0] tkeep);
    integer i;
	integer valid_byte_count ;
    begin
		valid_byte_count = 0;
        for (i = 0; i < 128; i = i+1) begin
            valid_byte_count = valid_byte_count + tkeep[i];
        end
		calc_empty_bytes = 128 - valid_byte_count;
    end
endfunction

// 流水线阶段1：输入锁存与预处理
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        tdata_pipe[0] <= 0;
        tlast_pipe[0] <= 0;
        seg_valid_pipe[0] <= 0;
        empty_pipe[0] <= 0;

    end else if (s_axis_tready) begin  // 仅当下一级就绪时锁存
        tdata_pipe[0] <= s_axis_tdata;
        tlast_pipe[0] <= s_axis_tlast;

        // 计算段有效性（每8字节对应1段）
        for (integer i = 0; i < SEG_CNT; i = i+1)
            seg_valid_pipe[0][i] <= |s_axis_tkeep[i*8 +: 8];

        // 累计无效字节逻辑
        if (s_axis_tvalid && s_axis_tlast) begin
			for(integer i = 0; i < SEG_CNT ; i = i + 1)
				empty_pipe[0][i*3 +: 3 ] = calc_empty_bytes(s_axis_tkeep[i*8 +:8]);
        end else begin
            empty_pipe[0] <= 0;      // 包尾结束
        end
    end
end

// 流水线阶段2：字节序转换与状态传递
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        tdata_pipe[1] <= 0;
        tlast_pipe[1] <= 0;
        seg_valid_pipe[1] <= 0;
        empty_pipe[1] <= 0;
    end else if (pipe_ready[0]) begin
        tlast_pipe[1] <= tlast_pipe[0];
        seg_valid_pipe[1] <= seg_valid_pipe[0];
        empty_pipe[1] <= empty_pipe[0];

        // 并行字节序转换（16个段独立处理） why 字节序转换?
        for (integer seg = 0; seg < SEG_CNT; seg = seg+1)
            tdata_pipe[1][seg*64 +: 64] <= tdata_pipe[0][seg*64 +: 64]; //swap_bytes64();
    end
end

// 流水线阶段3：输出对齐与流控
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        i_tx_mac_valid <= 0;
        i_tx_mac_data <= 0;
        i_tx_mac_inframe <= 0;
        i_tx_mac_eop_empty <= 0;
    end else if (pipe_ready[1]) begin
        i_tx_mac_data <= tdata_pipe[1];
        i_tx_mac_inframe <= seg_valid_pipe[1];
        i_tx_mac_valid <= 1;
		i_tx_mac_eop_empty <= empty_pipe[1];
    end else begin
		i_tx_mac_valid <= 1'b0;
	end
end

// 全流水线流控逻辑
assign pipe_ready[0] = pipe_ready[1];      // 前级依赖后级
assign pipe_ready[1] = o_tx_mac_ready;     // 末级由下游控制
assign s_axis_tready = pipe_ready[0];      // 输入就绪由首级控制

endmodule
`resetall