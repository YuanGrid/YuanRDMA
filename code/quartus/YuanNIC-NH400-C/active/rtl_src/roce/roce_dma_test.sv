// roce_dma_test.sv
// BAS 自测：重复 N 次 “读 source_address 的 transfer_length 字节 -> 写到 destination_address”，统计总周期数，用于上板验证
// BAS 读写正确性和带宽（带宽 = N*transfer_length*8 / (cycle_count*4ns)）。transfer_length 可到 4096 且可跨页
// （source_address/destination_address 须物理连续）。
`default_nettype none
`timescale 1ns/1ps
module roce_dma_test (
    input  wire               clk,
    input  wire               rst,
    input  wire  [63:0]       source_address,
    input  wire  [63:0]       destination_address,
    input  wire  [12:0]       transfer_length,
    input  wire  [31:0]       repeat_count,
    input  wire               start,
    output reg                busy,
    output reg                done,
    output reg                error,
    output reg   [31:0]       cycle_count,
    // DMA 读
    output wire               dma_read_request_valid,
    input  wire               dma_read_request_ready,
    output wire  [63:0]       dma_read_request_address,
    output wire  [63:0]       dma_read_request_page1,
    output wire  [12:0]       dma_read_request_length,
    input  wire               dma_read_valid,
    output wire               dma_read_ready,
    input  wire  [1023:0]     dma_read_data,
    input  wire               dma_read_error,
    // DMA 写
    output wire               dma_write_request_valid,
    input  wire               dma_write_request_ready,
    output wire  [63:0]       dma_write_request_address,
    output wire  [63:0]       dma_write_request_page1,
    output wire  [12:0]       dma_write_request_length,
    output wire               dma_write_valid,
    input  wire               dma_write_ready,
    output wire  [1023:0]     dma_write_data,
    input  wire               dma_write_complete,
    input  wire               dma_write_complete_error
);
    reg  [31:0] total_count, reads_issued, writes_issued, writes_completed;

    assign dma_read_request_valid = busy && (reads_issued != total_count);
    // 自测缓冲区要求物理连续：跨页时下一页 = 本页 + 4 KB
    assign dma_read_request_address  = source_address;
    assign dma_read_request_page1 = source_address + 64'd4096;
    assign dma_write_request_page1 = destination_address + 64'd4096;
    assign dma_read_request_length   = transfer_length;
    assign dma_write_request_valid = busy && (writes_issued != total_count) && (writes_issued != reads_issued);
    assign dma_write_request_address  = destination_address;
    assign dma_write_request_length   = transfer_length;

    // 读数据直接作为写数据（同一请求的拍数相同）
    assign dma_write_valid = dma_read_valid;
    assign dma_read_ready = dma_write_ready;
    assign dma_write_data  = dma_read_data;

    always @(posedge clk) begin
        if (rst) begin
            busy <= 1'b0;
            done <= 1'b0;
            error  <= 1'b0;
        end else if (start && !busy) begin
            // B6393：transfer_length=0 会把读写两条通道一起打死（read_first_burst_beats 算
            // 0 → ARLEN=63，roce_dma_rd_align 的 beat_count 也算 0 → meta_ready 恒 0，
            // 所有读请求堵死），在源头拒绝比下游钳位更安全。
            if (transfer_length == 13'd0) begin
                error <= 1'b1;
                done  <= 1'b0;
                // busy 不置位，调用方 poll busy==0 后可检查 error
            end else begin
            busy    <= 1'b1;
            done    <= 1'b0;
            error     <= 1'b0;
            total_count       <= (repeat_count == 32'd0) ? 32'd1 : repeat_count;
            reads_issued  <= 32'd0;
            writes_issued  <= 32'd0;
            writes_completed <= 32'd0;
            cycle_count  <= 32'd0;
            end
        end else if (busy) begin
            cycle_count <= cycle_count + 32'd1;
            if (dma_read_request_valid && dma_read_request_ready) reads_issued <= reads_issued + 32'd1;
            if (dma_write_request_valid && dma_write_request_ready) writes_issued <= writes_issued + 32'd1;
            if (dma_read_valid && dma_read_ready && dma_read_error) error <= 1'b1;
            if (dma_write_complete) begin
                writes_completed <= writes_completed + 32'd1;
                if (dma_write_complete_error) error <= 1'b1;
                if (writes_completed + 32'd1 == total_count) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                end
            end
        end
    end
endmodule
`default_nettype wire
