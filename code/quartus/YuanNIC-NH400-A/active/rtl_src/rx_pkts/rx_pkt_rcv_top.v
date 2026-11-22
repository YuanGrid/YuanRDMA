`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/03/31 16:28:41
// Design Name: 
// Module Name: rx_pkt_rcv_top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
// B6462（2026-11-21）：删除全部测试仪功能，只保留真实的收包通路。
//   删除：u1_rx_pkt_pkg_inst / u2_rx_pkt_pkg_inst（rx_pkt_pkg：报文过滤 + 延迟/抖动/
//         字节统计 + 流缓存）、u4_reg_inst（packet_adapter_register：那套寄存器的 case 表）、
//         以及两路统计的 sum/max/min 合并逻辑。
//   保留：u3_rx_mux_nto1（两个 MAC 口 → 单路的真收包通路）与它的以太网错误计数。
//   现状：s_axis_rx0/1 → rx_mux_nto1 → m_axis_rx_*。
//
// AVM 从设备：原来的 packet_adapter_register 是这个 BAR（user_avm[3]）唯一的应答方，
//   avm_config 对 user_avm_wait 没有超时保护，直接删掉会让该 BAR 的总线访问永久挂住。
//   所以这里保留一个 avm_register 作为空寄存器文件：正常握手、读回恒 0、写丢弃。
//   寄存器地址空间仍在（不越界、不报错），只是不再有功能。
//////////////////////////////////////////////////////////////////////////////////  

module rx_pkt_rcv_top#(
    parameter                       DATA_W      = 1024,
    parameter                       FLOW_NUM    = 10240,
    parameter                       STREAM_ID_W = 13
)
(
    input   [27:0]                  s_avm_addr ,
    input                           s_avm_read ,
    input                           s_avm_write,
    input   [31:0]                  s_avm_wdat ,
    output                          s_avm_wait ,
    output  [31:0]                  s_avm_rdat ,
    output                          s_avm_rvld ,
    output  [1:0]                   s_avm_rspo ,
    output                          s_avm_wrsp ,
    input                           s_axis_rx0_tvalid,
    input   [DATA_W-1:0]            s_axis_rx0_tdata,
    input   [$clog2(DATA_W/8)-1:0]  s_axis_rx0_tkeep,
    input                           s_axis_rx0_tlast,
    input   [3-1:0]                 s_axis_rx0_tuser_err,
    input   [64-1:0]                s_axis_rx0_ttime,
    input                           s_axis_rx1_tvalid,
    input   [DATA_W-1:0]            s_axis_rx1_tdata,
    input   [$clog2(DATA_W/8)-1:0]  s_axis_rx1_tkeep,
    input                           s_axis_rx1_tlast,
    input   [3-1:0]                 s_axis_rx1_tuser_err,
    input   [64-1:0]                s_axis_rx1_ttime,
    output                          m_axis_rx_tvalid,
    output  [DATA_W-1:0]            m_axis_rx_tdata,
    output  [$clog2(DATA_W/8)-1:0]  m_axis_rx_tkeep,
    output                          m_axis_rx_tlast,
    input                           m_axis_rx_tready,  
    output                          timestamp_delay_type  ,
    input                           cnt_clear_en          , 
    output  [63:0]                  eth_fcs_err_cnt       , 
    output  [63:0]                  eth_mfmd_err_cnt      , 
    output  [63:0]                  eth_under_over_err_cnt, 
    output  [63:0]                  eth_plen_err_cnt      , 
    output  [63:0]                  eth_fifo_full_err_cnt , 
    input                           link_up0,
    input                           mac_rstn,
    input                           axil_rstn,
    input                           pcie_rstn,
    input   [63:0]                  time_stamp, 
    input                           axis_aclk,
    input                           axil_aclk,
    input                           mac_clk
);

    // ---------------------------------------------------------------- 空寄存器文件
    // 只为维持 AVM 握手（见文件头）。reg_dout 恒 0：读回全 0，写入被丢弃。
    wire            reg_en_unused  ;
    wire            reg_we_unused  ;
    wire [27:0]     reg_addr_unused;
    wire [31:0]     reg_din_unused ;

    avm_register #(
        .ADDR_W                     (28                     ),
        .DATA_W                     (32                     )
    ) u_avm_stub (
        .avm_addr                   (s_avm_addr             ),
        .avm_read                   (s_avm_read             ),
        .avm_write                  (s_avm_write            ),
        .avm_wdat                   (s_avm_wdat             ),
        .avm_wait                   (s_avm_wait             ),
        .avm_rdat                   (s_avm_rdat             ),
        .avm_rvld                   (s_avm_rvld             ),
        .avm_rspo                   (s_avm_rspo             ),
        .avm_wrsp                   (s_avm_wrsp             ),
        .reg_en                     (reg_en_unused          ),
        .reg_we                     (reg_we_unused          ),
        .reg_addr                   (reg_addr_unused        ),
        .reg_din                    (reg_din_unused         ),
        .reg_dout                   (32'd0                  ),
        .clk                        (axil_aclk              ),
        .rst_n                      (axil_rstn              )
    );

    // ---------------------------------------------------------------- 收包合并
    // 唯一的收包通路：两个 MAC 口的 AXIS 合并成一路。
    rx_mux_nto1#
    (
        .RCV_NUM                    (2                      ),
        .DATA_W                     (1024                   )
    )
    u3_rx_mux_nto1
    (    
        .s_clk                      (mac_clk        ),
        .m_clk                      (axis_aclk      ),
        .rst_n                      (mac_rstn   ),
        .m_rst_n                    (pcie_rstn   ),
        .s_axis_rx_tvalid           ({s_axis_rx1_tvalid,s_axis_rx0_tvalid}),
        .s_axis_rx_tdata            ({s_axis_rx1_tdata,s_axis_rx0_tdata}),
        .s_axis_rx_tkeep            ({s_axis_rx1_tkeep,s_axis_rx0_tkeep}),
        .s_axis_rx_tlast            ({s_axis_rx1_tlast,s_axis_rx0_tlast}),
        .s_axis_rx_tuser            ({s_axis_rx1_tuser_err,s_axis_rx0_tuser_err}),
        .m_axis_rx_tvalid           (m_axis_rx_tvalid       ),
        .m_axis_rx_tdata            (m_axis_rx_tdata        ),
        .m_axis_rx_tkeep            (m_axis_rx_tkeep        ),
        .m_axis_rx_tlast            (m_axis_rx_tlast        ),
        .m_axis_rx_tready           (m_axis_rx_tready       ),
        .cnt_clear_en               (cnt_clear_en           ),
        .eth_fcs_err_cnt            (eth_fcs_err_cnt        ),
        .eth_mfmd_err_cnt           (eth_mfmd_err_cnt       ),
        .eth_under_over_err_cnt     (eth_under_over_err_cnt ),
        .eth_plen_err_cnt           (eth_plen_err_cnt       ),
        .eth_fifo_full_err_cnt      (eth_fifo_full_err_cnt  )
    );

    // timestamp_delay_type 原本由 packet_adapter_register 驱动（测试仪的时间戳延迟补偿）。
    // 功能删除后恒 0 = 不插值/不补偿，时间戳按原值透传。
    assign timestamp_delay_type = 1'b0;

endmodule
