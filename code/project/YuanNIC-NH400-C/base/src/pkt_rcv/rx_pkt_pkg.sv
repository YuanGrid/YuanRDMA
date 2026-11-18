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
`timescale 1ns/1ps
module rx_pkt_pkg #(
    parameter int                       CMAC_ID     = 0,
    parameter int                       MIN_PKT_LEN = 64,
    parameter int                       MAX_PKT_LEN = 1518,
    parameter real                      PKT_CAP     = 10.5,
    parameter                           DATA_W      = 1024
)(    
    input                               s_axis_rx_tvalid,
    input   [DATA_W-1:0]                s_axis_rx_tdata,
    input   [$clog2(DATA_W/8)-1:0]      s_axis_rx_tkeep,
    input                               s_axis_rx_tlast,
    input   [3-1:0]                     s_axis_rx_tuser_err,
    output                              m_axis_rx_tvalid,
    output  [DATA_W-1:0]                m_axis_rx_tdata,
    output  [$clog2(DATA_W/8)-1:0]      m_axis_rx_tkeep,
    output                              m_axis_rx_tlast,
    output  [3:0]                       m_axis_rx_tuser_err,
    input                               stream_pkt_r_req,
    input   [15:0]                      stream_pkt_id_r,
    input                               stream_pkt_rst,
    output  [31:0]                      stream_pkt_rdata,
    output  [63:0]                      stream_byt_rdata,
    output  reg     [63:0]              reg_rx_pkts_recv,
    output  reg     [63:0]              reg_rx_bytes_recv,
    output  reg     [63:0]              reg_rx_pkts_drop,
    output  reg     [63:0]              reg_rx_bytes_drop,
    output  reg     [63:0]              reg_rx_pkts_err,
    output  reg     [63:0]              reg_rx_bytes_err,
    output  reg     [63:0]              reg_rx_pkts_ip_checksum_err,
    input   wire                        rx_all_en,
    input   wire                        work_mode,
    input   wire                        rx_pkt_en,
    input   wire                        rx_pkt_mix_en,
    input   wire                        rx_pkt_filter_en,
    input   wire                        rx_pkt_filter_type,
    output  wire    [31:0]              stream_max_delay ,
    output  wire    [31:0]              stream_min_delay ,
    output  wire    [63:0]              stream_sum_delay ,
    output  wire    [31:0]              stream_max_jitter,
    output  wire    [31:0]              stream_min_jitter,
    output  wire    [63:0]              stream_sum_jitter,
    output  reg     [63:0]              reg_rx_pkt_sum_delay,
    output  reg     [63:0]              reg_rx_pkt_max_delay,
    output  reg     [63:0]              reg_rx_pkt_min_delay,
    output  reg     [63:0]              reg_rx_pkt_max_jitter,
    output  reg     [63:0]              reg_rx_pkt_min_jitter,
    output  reg     [63:0]              reg_rx_pkt_sum_jitter,
    output  reg     [63:0]              reg_rx_pkt_start_time,
    output  reg     [63:0]              reg_rx_pkt_stop_time,
    output  reg     [63:0]              rx_pkt_sum_delay,
    output  reg     [63:0]              rx_pkt_max_delay,
    output  reg     [63:0]              rx_pkt_min_delay,
    output  reg     [63:0]              reg_rocev2_pkt_rt_delay,
    output  reg     [63:0]              reg_rocev2_pkt_max_delay,
    output  reg     [63:0]              reg_rocev2_pkt_min_delay,
    output  reg     [63:0]              reg_rocev2_pkt_max_jitter,
    output  reg     [63:0]              reg_rocev2_pkt_min_jitter,
    output  reg     [63:0]              reg_rocev2_pkt_rt_jitter,
    output  reg     [63:0]              reg_rocev2_rx_pkts,
    output  reg     [63:0]              reg_rocev2_pkt_sum_delay,
    output  reg     [63:0]              reg_rocev2_pkt_sum_jitter,
    input   wire                        test_mode             ,
    input   wire                        timestamp_delay_type  ,
    input   wire     [31:0]             timestamp_delay_value ,
    input   wire     [31:0]             policy_vld            ,
    input   wire     [319:0]            info_filter_item0     ,
    input   wire     [319:0]            info_filter_item1     ,
    input   wire     [319:0]            info_filter_item2     ,
    input   wire     [319:0]            info_filter_item3     ,
    input   wire     [319:0]            info_filter_item4     ,
    input   wire     [319:0]            info_filter_item5     ,
    input   wire     [319:0]            info_filter_item6     ,
    input   wire     [319:0]            info_filter_item7     ,
    input   [63:0]                      time_stamp, 
    input                               link_up,
    input                               cmac_clk,
    input                               axil_aclk,
    input                               cmac_rstn,
    input                               axis_rstn
);
    localparam  AUTH_CODE = 16'h4e54;
    reg                                 rx_pkt_recv;
    reg                                 rx_pkt_drop;
    reg                                 rx_pkt_err;
    wire    [15:0]                      rx_bytes;
    wire                                ip_checksum_error;
    wire    [319:0]                     info_filter_item[7:0]; 
    wire    [63:0]                      timestamp_delay;
    wire                                timestamp_valid;
    reg                                 rcv_st;
    reg                                 rcv_sp;
    reg     [63:0]                      rx_timestamp_st; 
    wire                                rocev2_timestamp_vld;
    wire    [63:0]                      rocev2_timestamp_value;
    wire    [15:0]                      stream_pkt_id_w;
    wire    [15:0]                      stream_value;
    wire                                arp_icmp_flag;
    wire                                pkt_stream_vld;
    reg                                 pkt_stream_en;
    wire                                ts_delay_stream_vld;
    reg                                 ts_delay_stream_en;
    reg     [31:0]                      timestamp_delay_stream;
    wire                                pkt_recv;
    wire                                pkt_drop;
    wire                                pkt_err;
    wire                                drop;
    wire                                drop_flag;
    wire    [$clog2(DATA_W/8)-1:0]      filter_tkeep;    
    wire    [3-1:0]                     filter_tuser_err;
    wire                                filter_tvalid;   
    wire                                filter_tlast;    
    wire    [DATA_W-1:0]                filter_tdata;  
    wire    [2:0]                       filter_state;
    wire                                dstip_ok;
    wire                                dstport_ok;
    wire                                rx_en;
    wire                                timestamp_val;
    reg     [15:0]                      rx_stream_pkt_id;
    wire    [31:0]                      imestamp_delay_value;
    wire    [31:0]                      tream_max_delay;
    wire    [31:0]                      tream_min_delay; 
    wire    [63:0]                      tream_sum_delay; 
    wire    [31:0]                      tream_max_jitter;
    wire    [31:0]                      tream_min_jitter;
    wire    [63:0]                      tream_sum_jitter;
    reg                                 link_up_d1;
    reg                                 link_up_d2;
    reg                                 rx_pkt_timestamp_prog;
    reg     [63:0]                      timestamp_delay_pre;
    reg                                 rocev2_pkt_timestamp_prog;
    reg     [63:0]                      rocev2_timestamp_delay_pre;
    reg     [63:0]                      rx_pkt_jitter;
    reg                                 rx_pkt_jitter_vld;
    reg                                 rocev2_jitter_vld;
    reg     [63:0]                      rocev2_jitter;
    reg                                 stream_pkt_rst_d1;
    reg                                 stream_pkt_rst_clk_d1;
    reg                                 stream_pkt_rst_clk_d2;
    reg                                 stream_pkt_rst_clk_d3;
    reg                                 stream_pkt_r_req_d1;
    reg                                 stream_pkt_r_req_clk_d1;
    reg                                 stream_pkt_r_req_clk_d2;
    reg                                 stream_pkt_r_req_clk_d3;

    always @(posedge axil_aclk ) begin
        stream_pkt_rst_d1 <= stream_pkt_rst;
        stream_pkt_r_req_d1 <= stream_pkt_r_req;
    end

    always @(posedge cmac_clk ) begin
        stream_pkt_rst_clk_d1 <= stream_pkt_rst_d1|stream_pkt_rst;
        stream_pkt_rst_clk_d2 <= stream_pkt_rst_clk_d1;
        stream_pkt_rst_clk_d3 <= stream_pkt_rst_clk_d2;

        stream_pkt_r_req_clk_d1 <= stream_pkt_r_req_d1|stream_pkt_r_req;
        stream_pkt_r_req_clk_d2 <= stream_pkt_r_req_clk_d1;
        stream_pkt_r_req_clk_d3 <= stream_pkt_r_req_clk_d2;
    end

    always @(posedge cmac_clk) begin
        if(rx_pkt_en & filter_tvalid && filter_tlast && (stream_value==AUTH_CODE))
            rcv_sp <= 1'b1;
        else
            rcv_sp <= 1'b0;
    end   

    always @(posedge cmac_clk) begin
        if((~axis_rstn) | stream_pkt_rst_clk_d3)
            rcv_st <= 1'b0;
        else if(rx_pkt_en & !rcv_st && filter_tvalid && (stream_value==AUTH_CODE))
            rcv_st <= 1'b1;            
    end  

    always @(posedge cmac_clk) begin
        if(rx_pkt_en & !rcv_st && filter_tvalid && (stream_value==AUTH_CODE))
            rx_timestamp_st <= time_stamp; 
    end  
    
    always @(posedge cmac_clk) begin
        if (~axis_rstn) begin
            link_up_d1  <= 0;
            link_up_d2  <= 0;
        end
        else begin
            link_up_d1  <= link_up;
            link_up_d2  <= link_up_d1;
        end
    end

    assign m_axis_rx_tvalid     = filter_tvalid;
    assign m_axis_rx_tdata      = swap_endian_128(filter_tdata);
    assign m_axis_rx_tkeep      = filter_tkeep;
    assign m_axis_rx_tlast      = filter_tlast;
    assign m_axis_rx_tuser_err  = {drop_flag,filter_tuser_err};
    assign rx_en                = link_up_d2&rx_all_en;

    assign info_filter_item[0] = info_filter_item0;
    assign info_filter_item[1] = info_filter_item1;
    assign info_filter_item[2] = info_filter_item2;
    assign info_filter_item[3] = info_filter_item3;
    assign info_filter_item[4] = info_filter_item4;
    assign info_filter_item[5] = info_filter_item5;
    assign info_filter_item[6] = info_filter_item6;
    assign info_filter_item[7] = info_filter_item7;

    pkt_rx_filter #(
        .CMAC_ID(CMAC_ID)
    )u_pkt_rx_filter(
        .rx_pkt_en                          (rx_en),
        .rx_pkt_mix_en                      (rx_pkt_mix_en),
        .rx_pkt_filter_en                   (rx_pkt_filter_en),
        .rx_pkt_filter_type                 (rx_pkt_filter_type),
        .policy_vld                         (policy_vld), 
        .info_filter_item                   (info_filter_item),
        .p_axis_tvalid                      (s_axis_rx_tvalid),
        .p_axis_tdata                       (swap_endian_128(s_axis_rx_tdata)),
        .p_axis_tlast                       (s_axis_rx_tlast),
        .p_axis_tkeep                       (s_axis_rx_tkeep),
        .p_axis_tuser                       (s_axis_rx_tuser_err),
        .drop_flag                          (drop_flag), 
        .aclk                               (cmac_clk),
        .aresetn                            (axis_rstn),
        .d_axis_tvalid                      (filter_tvalid),
        .d_axis_tdata                       (filter_tdata),
        .d_axis_tlast                       (filter_tlast),
        .d_axis_tuser                       (filter_tuser_err),
        .d_axis_tkeep                       (filter_tkeep),
        .timestamp_delay_type               (timestamp_delay_type),
        .timestamp_delay_value              (timestamp_delay_value),
        .time_stamp                         (time_stamp),
        .timestamp_valid                    (timestamp_val),
        .timestamp_delay                    (timestamp_delay),
        .stream_id                          (stream_pkt_id_w),
        .stream_value                       (stream_value),
        .rocev2_timestamp_vld               (rocev2_timestamp_vld),
        .rocev2_timestamp_value             (rocev2_timestamp_value),
        .arp_icmp_flag                      (arp_icmp_flag),
        .filter_state                       (filter_state)
    );

    statistics_ram #(
        .DATA_W                             (32                 ),
        .ADDR_W                             (12                 ),
        .MODE                               ("CNT"              )//"MAX" "MIN" "CNT"
    )u11_pkt_cnt(
        .stream_pkt_tvalid                  (pkt_stream_en      ),
        .stream_pkt_tlast                   (1'b1               ),
        .stream_pkt_tready                  (1'b1               ),
        .new_data                           (32'd1              ),
        .stream_pkt_id_w                    (rx_stream_pkt_id   ),
        .stream_pkt_r_req                   (stream_pkt_r_req_clk_d3),
        .stream_pkt_id_r                    (stream_pkt_id_r    ),
        .stream_pkt_rst                     (stream_pkt_rst_clk_d3),
        .stream_pkt_rdata                   (stream_pkt_rdata   ),
        .axis_aclk                          (cmac_clk           ),
        .axil_aclk                          (axil_aclk          ),
        .axis_rstn                          (axis_rstn          )
    );

    statistics_ram #(
        .DATA_W                             (64                 ),
        .ADDR_W                             (12                 ),
        .MODE                               ("CNT"              )//"MAX" "MIN" "CNT"
    )u12_byte_cnt(
        .stream_pkt_tvalid                  (pkt_stream_en      ),
        .stream_pkt_tlast                   (1'b1               ),
        .stream_pkt_tready                  (1'b1               ),
        .new_data                           (64'(rx_bytes+24)   ),
        .stream_pkt_id_w                    (rx_stream_pkt_id   ),
        .stream_pkt_r_req                   (stream_pkt_r_req_clk_d3),
        .stream_pkt_id_r                    (stream_pkt_id_r    ),
        .stream_pkt_rst                     (stream_pkt_rst_clk_d3),
        .stream_pkt_rdata                   (stream_byt_rdata   ),
        .axis_aclk                          (cmac_clk           ),
        .axil_aclk                          (axil_aclk          ),
        .axis_rstn                          (axis_rstn          )
    );

    statistics_ram #(
        .DATA_W                             (32                             ),
        .ADDR_W                             (9                              ),
        .MODE                               ("MAX"                          )//"MAX" "MIN" "CNT"
    )u21_max_delay(      
        .stream_pkt_tvalid                  (ts_delay_stream_en             ),
        .stream_pkt_tlast                   (1'b1                           ),
        .stream_pkt_tready                  (1'b1                           ),
        .new_data                           (32'(timestamp_delay_stream)    ),
        .stream_pkt_id_w                    (rx_stream_pkt_id               ),
        .stream_pkt_r_req                   (stream_pkt_r_req_clk_d3        ),
        .stream_pkt_id_r                    (stream_pkt_id_r                ),
        .stream_pkt_rst                     (stream_pkt_rst_clk_d3          ),
        .stream_pkt_rdata                   (stream_max_delay               ),
        .axis_aclk                          (cmac_clk                       ),
        .axil_aclk                          (axil_aclk                      ),
        .axis_rstn                          (axis_rstn                      )
    );

    statistics_ram #(
        .DATA_W                             (32                             ),
        .ADDR_W                             (9                              ),
        .MODE                               ("MIN"                          )//"MAX" "MIN" "CNT"
    )u22_min_delay(      
        .stream_pkt_tvalid                  (ts_delay_stream_en             ),
        .stream_pkt_tlast                   (1'b1                           ),
        .stream_pkt_tready                  (1'b1                           ),
        .new_data                           (32'(timestamp_delay_stream)    ),
        .stream_pkt_id_w                    (rx_stream_pkt_id               ),
        .stream_pkt_r_req                   (stream_pkt_r_req_clk_d3        ),
        .stream_pkt_id_r                    (stream_pkt_id_r                ),
        .stream_pkt_rst                     (stream_pkt_rst_clk_d3          ),
        .stream_pkt_rdata                   (stream_min_delay               ),
        .axis_aclk                          (cmac_clk                       ),
        .axil_aclk                          (axil_aclk                      ),
        .axis_rstn                          (axis_rstn                      )
    );

    statistics_ram #(
        .DATA_W                             (64                             ),
        .ADDR_W                             (9                              ),
        .MODE                               ("CNT"                          )//"MAX" "MIN" "CNT"
    )u23_sum_delay(      
        .stream_pkt_tvalid                  (ts_delay_stream_en             ),
        .stream_pkt_tlast                   (1'b1                           ),
        .stream_pkt_tready                  (1'b1                           ),
        .new_data                           (64'(timestamp_delay_stream)    ),
        .stream_pkt_id_w                    (rx_stream_pkt_id               ),
        .stream_pkt_r_req                   (stream_pkt_r_req_clk_d3        ),
        .stream_pkt_id_r                    (stream_pkt_id_r                ),
        .stream_pkt_rst                     (stream_pkt_rst_clk_d3          ),
        .stream_pkt_rdata                   (stream_sum_delay               ),
        .axis_aclk                          (cmac_clk                       ),
        .axil_aclk                          (axil_aclk                      ),
        .axis_rstn                          (axis_rstn                      )
    );

    jitter_st_ram #(
        .DATA_W                             (32                             ),
        .ADDR_W                             (9                              )
    )u24_jitter_delay(  
        .stream_pkt_tvalid                  (ts_delay_stream_en             ),
        .stream_pkt_tlast                   (1'b1                           ),
        .stream_pkt_tready                  (1'b1                           ),
        .new_data                           (32'(timestamp_delay_stream)    ),
        .stream_pkt_id_w                    (rx_stream_pkt_id               ),
        .stream_pkt_r_req                   (stream_pkt_r_req_clk_d3        ),
        .stream_pkt_id_r                    (stream_pkt_id_r                ),
        .stream_pkt_rst                     (stream_pkt_rst_clk_d3          ),
        .stream_minjt_rdata                 (stream_min_jitter              ),
        .stream_maxjt_rdata                 (stream_max_jitter              ),
        .stream_sumjt_rdata                 (stream_sum_jitter              ),
        .axis_aclk                          (cmac_clk                       ),
        .axil_aclk                          (axil_aclk                      ),
        .axis_rstn                          (axis_rstn                      )
    );

    axi_stream_size_counter_rx #(
        .TDATA_W (DATA_W)
    ) size_cnt_inst (
        .p_axis_tvalid    (filter_tvalid),
        .p_axis_tkeep     (filter_tkeep),
        .p_axis_tlast     (filter_tlast),
        .p_axis_tready    (1'b1),
        .size_valid       (),
        .size             (rx_bytes),
        .aclk             (cmac_clk),
        .aresetn          (axis_rstn)
    );
    assign pkt_recv = rx_pkt_en ? filter_tvalid && filter_tlast && ~drop: 0;
    assign pkt_drop = rx_pkt_en ? filter_tvalid && filter_tlast && drop : 0;
    assign pkt_err  = rx_pkt_en ? filter_tvalid && filter_tlast && filter_tuser_err[2] : 0;
    assign timestamp_valid = rx_pkt_en ? timestamp_val && (stream_value==AUTH_CODE) : 0;
    assign pkt_stream_vld = (stream_value==AUTH_CODE) ? (filter_tvalid && filter_tlast) : 0;
    assign ts_delay_stream_vld = (stream_value==AUTH_CODE) ? timestamp_val : 0;

    assign drop = filter_tvalid && filter_tlast && drop_flag;

    always @(posedge cmac_clk) begin
        if (~axis_rstn) begin
            rx_pkt_recv  <= 0;
            rx_pkt_drop  <= 0;
            rx_pkt_err   <= 0;
            pkt_stream_en <= 0;
            rx_stream_pkt_id <= 0;
            ts_delay_stream_en <= 0;
            timestamp_delay_stream <= 0;
        end
        else begin
            rx_pkt_recv  <= pkt_recv;
            rx_pkt_drop  <= pkt_drop;
            rx_pkt_err   <= pkt_err ; 
            pkt_stream_en <= pkt_stream_vld;
            rx_stream_pkt_id <= stream_pkt_id_w;
            ts_delay_stream_en <= ts_delay_stream_vld & stream_pkt_id_w[15:9] == 7'd0;
            timestamp_delay_stream <= timestamp_delay[31:0];
        end
    end

    ip_checksum ip_checksum_inst(
        .p_axis_tvalid          (filter_tvalid),
        .p_axis_tdata           (swap_endian_128(filter_tdata)),
        .p_axis_tlast           (filter_tlast),
        .ip_checksum_error      (ip_checksum_error),
        .aclk                   (cmac_clk),
        .aresetn                (axis_rstn)
    );

    always @(posedge cmac_clk) begin
        if (stream_pkt_rst_clk_d3)begin
            reg_rx_pkts_recv  <= 0;
            reg_rx_bytes_recv <= 0;
        end else if (rx_pkt_recv) begin
            reg_rx_pkts_recv  <= reg_rx_pkts_recv + 1;
            reg_rx_bytes_recv <= reg_rx_bytes_recv + rx_bytes + 64'd24;
        end
    end

    always @(posedge cmac_clk) begin
        if (stream_pkt_rst_clk_d3)begin  
            reg_rx_pkts_drop  <= 0;
            reg_rx_bytes_drop <= 0;
        end
        else if (rx_pkt_drop) begin
            reg_rx_pkts_drop  <= reg_rx_pkts_drop + 1;
            reg_rx_bytes_drop <= reg_rx_bytes_drop + rx_bytes + 64'd24;
        end
    end

    always @(posedge cmac_clk) begin
        if (stream_pkt_rst_clk_d3)begin   
            reg_rx_pkts_err  <= 0;
            reg_rx_bytes_err <= 0;
        end
        else if (rx_pkt_err) begin
            reg_rx_pkts_err  <= reg_rx_pkts_err + 1;
            reg_rx_bytes_err <= reg_rx_bytes_err + rx_bytes + 64'd24;
        end
    end

    always @(posedge cmac_clk) begin
        if (stream_pkt_rst_clk_d3)begin
            reg_rx_pkts_ip_checksum_err  <= 0;
        end
        else if (rx_pkt_recv) begin
            reg_rx_pkts_ip_checksum_err  <= reg_rx_pkts_ip_checksum_err + ip_checksum_error;
        end
    end

    always@(posedge cmac_clk)
    begin
        if (~axis_rstn) 
            reg_rx_pkt_start_time <= 64'd0;
        else if (stream_pkt_rst_clk_d3)
            reg_rx_pkt_start_time <= 64'd0;
        else
            reg_rx_pkt_start_time <= rx_timestamp_st;
    end

    always@(posedge cmac_clk)
    begin
        if (~axis_rstn) 
            reg_rx_pkt_stop_time <= 64'd0;
        else if (stream_pkt_rst_clk_d3)
            reg_rx_pkt_stop_time <= 64'd0;
        else if(rcv_sp)
            reg_rx_pkt_stop_time <= time_stamp;
    end

    always @(posedge cmac_clk) begin
        if (~axis_rstn) 
            rx_pkt_timestamp_prog <= 1'b0;
        else if(!rx_pkt_timestamp_prog && rx_pkt_en)
            rx_pkt_timestamp_prog <= timestamp_valid;
        else if(!rx_pkt_en)
            rx_pkt_timestamp_prog <= 1'b0;
    end  

    always @(posedge cmac_clk) begin
        if (~axis_rstn)
            timestamp_delay_pre   <= 64'd0;
        else if(rx_pkt_en & timestamp_valid)    
            timestamp_delay_pre     <= timestamp_delay;
    end

    always @(posedge cmac_clk) begin
        if (stream_pkt_rst_clk_d3)
            rx_pkt_jitter <= 64'd0;
        else if(rx_pkt_en & timestamp_valid & rx_pkt_timestamp_prog)
            rx_pkt_jitter <= abs_subtract(timestamp_delay_pre,timestamp_delay);
    end

    always @(posedge cmac_clk) begin
        rx_pkt_jitter_vld <= rx_pkt_en & timestamp_valid & rx_pkt_timestamp_prog;
    end



    always @(posedge cmac_clk) begin
        if (stream_pkt_rst_clk_d3)
            reg_rocev2_rx_pkts <= 64'd0;
        else if(rocev2_timestamp_vld)
            reg_rocev2_rx_pkts <= reg_rocev2_rx_pkts + 64'd1;
    end 


    always @(posedge cmac_clk) begin
        if (~axis_rstn) 
            rocev2_pkt_timestamp_prog <= 1'b0;
        else if (stream_pkt_rst_clk_d3)
            rocev2_pkt_timestamp_prog <= 1'b0;
        else if(!rocev2_pkt_timestamp_prog && rocev2_timestamp_vld)
            rocev2_pkt_timestamp_prog <= 1'b1;
    end 

    always @(posedge cmac_clk) begin
        if(~axis_rstn)
            rocev2_timestamp_delay_pre    <= 64'd0;
        else if(rocev2_timestamp_vld)
            rocev2_timestamp_delay_pre  <= rocev2_timestamp_value;
    end

    always @(posedge cmac_clk ) begin
        rocev2_jitter_vld <= rocev2_pkt_timestamp_prog && rocev2_timestamp_vld;
    end

    always @(posedge cmac_clk) begin
        if (stream_pkt_rst_clk_d3)
            rocev2_jitter <= 64'd0;
        else if(rocev2_timestamp_vld & rocev2_pkt_timestamp_prog)
            rocev2_jitter <= abs_subtract(rocev2_timestamp_delay_pre,rocev2_timestamp_value);
    end

    time_delay u0_rx_delay   (.clk(cmac_clk),.clear(stream_pkt_rst_clk_d3),.delay_vld(rx_pkt_en&timestamp_valid),.delay(timestamp_delay),
                              .max_delay(reg_rx_pkt_max_delay),.min_delay(reg_rx_pkt_min_delay),.sum_delay(reg_rx_pkt_sum_delay),.rt_delay());
    time_delay u1_rx_jitter  (.clk(cmac_clk),.clear(stream_pkt_rst_clk_d3),.delay_vld(rx_pkt_jitter_vld),.delay(rx_pkt_jitter),
                              .max_delay(reg_rx_pkt_max_jitter),.min_delay(reg_rx_pkt_min_jitter),.sum_delay(reg_rx_pkt_sum_jitter),.rt_delay());

    time_delay u2_rocev2_delay(.clk(cmac_clk),.clear(stream_pkt_rst_clk_d3),.delay_vld(rocev2_timestamp_vld),.delay(rocev2_timestamp_value),
                               .max_delay(reg_rocev2_pkt_max_delay),.min_delay(reg_rocev2_pkt_min_delay),.sum_delay(reg_rocev2_pkt_sum_delay),.rt_delay(reg_rocev2_pkt_rt_delay));

    time_delay u3_rocev2_jitter(.clk(cmac_clk),.clear(stream_pkt_rst_clk_d3),.delay_vld(rocev2_jitter_vld),.delay(rocev2_jitter),
                               .max_delay(reg_rocev2_pkt_max_jitter),.min_delay(reg_rocev2_pkt_min_jitter),.sum_delay(reg_rocev2_pkt_sum_jitter),.rt_delay(reg_rocev2_pkt_rt_jitter));

    function [63:0] abs_subtract;
        input [63:0] a; 
        input [63:0] b; 
        reg [63:0] result; 
        begin
            if (a >= b) begin 
                result = a - b;
            end else begin
                result = b - a; 
            end  
            abs_subtract = result;
        end
    endfunction

    function [1023:0] swap_endian_128;
		input [1023:0] din;
		integer i;
		reg [7:0] tmp_data;
		begin : swap_block_128
			for(i=0;i<128;i=i+1)
				swap_endian_128[(127-i)*8 +:8] = din[i*8 +:8];
		end
	endfunction
    
    module time_delay (
        input                       clk,
        input                       clear,
        input                       delay_vld,
        input           [63:0]      delay,
        output  reg     [63:0]      max_delay,
        output  reg     [63:0]      min_delay,
        output  reg     [63:0]      sum_delay,
        output  reg     [63:0]      rt_delay
    );
        
        always @(posedge clk) begin
            if (clear)
                max_delay <= 64'd0;
            else if(delay_vld & delay > max_delay)
                max_delay <= delay;
        end
    
        always @(posedge clk) begin
            if (clear)
                min_delay <= {64{1'b1}};
            else if(delay_vld & delay < min_delay)
                min_delay <= delay;
        end

        always @(posedge clk) begin
            if (clear)
                sum_delay <= 64'd0;
            else if(delay_vld)
                sum_delay <= delay + sum_delay;
        end

        always @(posedge clk ) begin
            if(clear)
                rt_delay <= 64'b0;
            else if(delay_vld)
                rt_delay <= delay;
        end

    endmodule


endmodule
