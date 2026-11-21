`timescale 1ns/1ps
module packet_adapter_register (
    input           [27:0]                  s_avm_addr ,
    input                                   s_avm_read ,
    input                                   s_avm_write,
    input           [31:0]                  s_avm_wdat ,
    output                                  s_avm_wait ,
    output          [31:0]                  s_avm_rdat ,
    output                                  s_avm_rvld ,
    output          [1:0]                   s_avm_rspo ,
    output                                  s_avm_wrsp ,
    input           [31:0]                  stream_pkt_rdata,
    input           [63:0]                  stream_byt_rdata,
    input           [63:0]                  reg_rx_pkts_recv,
    input           [63:0]                  reg_rx_bytes_recv,
    input           [63:0]                  reg_rx_pkts_drop,
    input           [63:0]                  reg_rx_bytes_drop,
    input           [63:0]                  reg_rx_pkts_err,
    input           [63:0]                  reg_rx_bytes_err,
    input           [63:0]                  reg_rx_pkts_ip_checksum_err,
    input           [63:0]                  reg_rx_pkt_sum_delay,
    input           [63:0]                  reg_rx_pkt_max_delay,
    input           [63:0]                  reg_rx_pkt_min_delay,
    input           [63:0]                  reg_rx_pkt_max_jitter,
    input           [63:0]                  reg_rx_pkt_min_jitter,
    input           [63:0]                  reg_rx_pkt_sum_jitter,
    input           [63:0]                  reg_rx_pkt_start_time,
    input           [63:0]                  reg_rx_pkt_stop_time,
    input           [63:0]                  rx_pkt_sum_delay,
    input           [63:0]                  rx_pkt_max_delay,
    input           [63:0]                  rx_pkt_min_delay,
    input           [63:0]                  reg_rocev2_pkt_rt_delay,
    input           [63:0]                  reg_rocev2_pkt_max_delay,
    input           [63:0]                  reg_rocev2_pkt_min_delay,
    input           [63:0]                  reg_rocev2_pkt_max_jitter,
    input           [63:0]                  reg_rocev2_pkt_min_jitter,
    input           [63:0]                  reg_rocev2_pkt_rt_jitter,
    input           [63:0]                  reg_rocev2_rx_pkts,
    input           [63:0]                  reg_rocev2_pkt_sum_delay,
    input           [63:0]                  reg_rocev2_pkt_sum_jitter,
    input           [31:0]                  stream_max_delay, 
    input           [31:0]                  stream_min_delay, 
    input           [63:0]                  stream_sum_delay, 
    input           [31:0]                  stream_max_jitter,
    input           [31:0]                  stream_min_jitter,
    input           [63:0]                  stream_sum_jitter,
    output  reg                             stream_pkt_r_req,
    output  reg     [15:0]                  stream_pkt_id_r,
    output                                  stream_pkt_rst,
    output  reg                             rx_all_en,
    output  reg                             work_mode,
    output  reg                             rx_pkt_en,
    output  reg                             rx_pkt_mix_en,
    output  reg                             rx_pkt_filter_en,
    output  reg                             rx_pkt_filter_type,
    output  reg                             test_mode,
    output  reg                             timestamp_delay_type,
    output  reg     [31:0]                  timestamp_delay_value,
    output  reg     [31:0]                  policy_vld,
    output  reg     [319:0]                 info_filter_item0, 
    output  reg     [319:0]                 info_filter_item1, 
    output  reg     [319:0]                 info_filter_item2, 
    output  reg     [319:0]                 info_filter_item3, 
    output  reg     [319:0]                 info_filter_item4, 
    output  reg     [319:0]                 info_filter_item5, 
    output  reg     [319:0]                 info_filter_item6, 
    output  reg     [319:0]                 info_filter_item7, 
    input                                   axil_aclk,
    input                                   axis_aclk,
    input                                   axil_aresetn
);
    //1400000 base_addr
    localparam C_ADDR_W                     = 28;
    localparam REG_RX_PKTS_ENABLE           = 12'h000;
    localparam REG_RX_PKTS_MIXED_ENABLE     = 12'h004;
    localparam REG_RX_PKTS_CLEAR            = 12'h008;
    localparam REG_RX_PKTS_FILTER_ENABLE    = 12'h00C;
    localparam REG_RX_PKTS_FILTER_TYPE      = 12'h018;
    localparam REG_RX_PKTS_ALL_ENABLE       = 12'h200;
    localparam REG_RX_PKTS_WORK_MODE        = 12'h204;
    localparam REG_RX_FILTER_BASE           = 12'h01C;
    localparam REG_RX_FILTER_INFO           = 12'h020;
    localparam REG_RX_FILTER_DONE           = 12'h024;
    localparam REG_RX_FILTER_POLICY_EN      = 12'h028;
    localparam REG_RX_FILTER_SIP_0          = 12'h300;
    localparam REG_RX_FILTER_SIP_1          = 12'h304;
    localparam REG_RX_FILTER_SIP_2          = 12'h308;
    localparam REG_RX_FILTER_SIP_3          = 12'h30C;
    localparam REG_RX_FILTER_DIP_0          = 12'h310;
    localparam REG_RX_FILTER_DIP_1          = 12'h314;
    localparam REG_RX_FILTER_DIP_2          = 12'h318;
    localparam REG_RX_FILTER_DIP_3          = 12'h31C;
    localparam REG_RX_FILTER_SP_DP          = 12'h320;
    localparam REG_RX_FILTER_MASK           = 12'h324;
    localparam REG_RX_PKTS_RECV_LOWER       = 12'h030;
    localparam REG_RX_PKTS_RECV_UPPER       = 12'h034;
    localparam REG_RX_BYTES_RECV_LOWER      = 12'h038;
    localparam REG_RX_BYTES_RECV_UPPER      = 12'h03C;
    localparam REG_RX_PKTS_DROP_LOWER       = 12'h040;
    localparam REG_RX_PKTS_DROP_UPPER       = 12'h044;
    localparam REG_RX_BYTES_DROP_LOWER      = 12'h048;
    localparam REG_RX_BYTES_DROP_UPPER      = 12'h04C;
    localparam REG_RX_PKTS_ERR_LOWER        = 12'h050;
    localparam REG_RX_PKTS_ERR_UPPER        = 12'h054;
    localparam REG_RX_BYTES_ERR_LOWER       = 12'h058;
    localparam REG_RX_BYTES_ERR_UPPER       = 12'h05C;
    localparam REG_RX_IP_CKSUM_ERR_LOWER    = 12'h060;
    localparam REG_RX_IP_CKSUM_ERR_UPPER    = 12'h064;
    localparam REG_RX_PKTS_STREAM_LOWER     = 12'h070;
    localparam REG_RX_PKTS_STREAM_UPPER     = 12'h074;
    localparam REG_RX_BYTES_STREAM_LOWER    = 12'h078;
    localparam REG_RX_BYTES_STREAM_UPPER    = 12'h07C;  
    localparam REG_RX_ARP_QID               = 12'h090;
    localparam REG_RX_TEST_MODE             = 12'h094;
    localparam REG_RX_TIMEDELAY_TYPE        = 12'h098;  
    localparam REG_RX_TIMEDELAY_VAL         = 12'h09C; 
    localparam REG_RX_BPS_LOWER             = 12'h0A0;
    localparam REG_RX_BPS_UPPER             = 12'h0A4;
    localparam REG_RX_PPS_LOWER             = 12'h0A8;
    localparam REG_RX_PPS_UPPER             = 12'h0AC;
    localparam REG_RX_STATIME_LOWER         = 12'h0B0;
    localparam REG_RX_STATIME_UPPER         = 12'h0B4;
    localparam REG_RX_STPTIME_LOWER         = 12'h0B8;
    localparam REG_RX_STPTIME_UPPER         = 12'h0BC;
    localparam REG_RX_SUM_TIMESTAMP_LOWER   = 12'h100;
    localparam REG_RX_SUM_TIMESTAMP_UPPER   = 12'h104;
    localparam REG_RX_MAX_TIMESTAMP_LOWER   = 12'h108;
    localparam REG_RX_MAX_TIMESTAMP_UPPER   = 12'h10C;
    localparam REG_RX_MIN_TIMESTAMP_LOWER   = 12'h110;
    localparam REG_RX_MIN_TIMESTAMP_UPPER   = 12'h114;
    localparam REG_RX_SUM_JITTER_LOWER      = 12'h118;
    localparam REG_RX_SUM_JITTER_UPPER      = 12'h11C;
    localparam REG_RX_MAX_JITTER_LOWER      = 12'h120;
    localparam REG_RX_MAX_JITTER_UPPER      = 12'h124;
    localparam REG_RX_MIN_JITTER_LOWER      = 12'h128;
    localparam REG_RX_MIN_JITTER_UPPER      = 12'h12C;
    localparam REG_ROCEV2_RT_TIMESTAMP_LOWER   = 12'h130;
    localparam REG_ROCEV2_RT_TIMESTAMP_UPPER   = 12'h134;
    localparam REG_ROCEV2_MAX_TIMESTAMP_LOWER  = 12'h138;
    localparam REG_ROCEV2_MAX_TIMESTAMP_UPPER  = 12'h13C;
    localparam REG_ROCEV2_MIN_TIMESTAMP_LOWER  = 12'h140;
    localparam REG_ROCEV2_MIN_TIMESTAMP_UPPER  = 12'h144;
    localparam REG_ROCEV2_RT_JITTER_LOWER      = 12'h148;
    localparam REG_ROCEV2_RT_JITTER_UPPER      = 12'h14C;
    localparam REG_ROCEV2_MAX_JITTER_LOWER     = 12'h150;
    localparam REG_ROCEV2_MAX_JITTER_UPPER     = 12'h154;
    localparam REG_ROCEV2_MIN_JITTER_LOWER     = 12'h158;
    localparam REG_ROCEV2_MIN_JITTER_UPPER     = 12'h15C;
    localparam REG_ROCEV2_PKTS_LOWER           = 12'h190;
    localparam REG_ROCEV2_PKTS_UPPER           = 12'h194;
    localparam REG_ROCEV2_SUM_TIMESTAMP_LOWER  = 12'h198;
    localparam REG_ROCEV2_SUM_TIMESTAMP_UPPER  = 12'h19C; 
    localparam REG_ROCEV2_SUM_JITTER_LOWER     = 12'h1A0;
    localparam REG_ROCEV2_SUM_JITTER_UPPER     = 12'h1A4;
    localparam REG_RX_STREAM_SUM_TIMESTAMP_LOWER  = 12'h160;
    localparam REG_RX_STREAM_SUM_TIMESTAMP_UPPER  = 12'h164;
    localparam REG_RX_STREAM_MAX_TIMESTAMP_LOWER  = 12'h168;
    localparam REG_RX_STREAM_MAX_TIMESTAMP_UPPER  = 12'h16C;
    localparam REG_RX_STREAM_MIN_TIMESTAMP_LOWER  = 12'h170;
    localparam REG_RX_STREAM_MIN_TIMESTAMP_UPPER  = 12'h174;
    localparam REG_RX_STREAM_SUM_JITTER_LOWER     = 12'h178;
    localparam REG_RX_STREAM_SUM_JITTER_UPPER     = 12'h17C;
    localparam REG_RX_STREAM_MAX_JITTER_LOWER     = 12'h180;
    localparam REG_RX_STREAM_MAX_JITTER_UPPER     = 12'h184;
    localparam REG_RX_STREAM_MIN_JITTER_LOWER     = 12'h188;
    localparam REG_RX_STREAM_MIN_JITTER_UPPER     = 12'h18C;
  
    wire                reg_en;
    wire                reg_we;
    wire [C_ADDR_W-1:0] reg_addr;
    wire         [31:0] reg_din;
    reg          [31:0] reg_dout;
    reg                 reg_statis_cnt_clear_en;   
    reg [4:0]           base_filter;           
    reg                 filter_done;
    reg  [319:0]        info_filter_item; 

  avm_register #(
    .CLOCKING_MODE ("common_clock"),
    .ADDR_W        (C_ADDR_W),
    .DATA_W        (32)
  ) axil_reg_inst (
    .avm_addr       (s_avm_addr         ),
    .avm_read       (s_avm_read         ),
    .avm_write      (s_avm_write        ),
    .avm_wdat       (s_avm_wdat         ),
    .avm_wait       (s_avm_wait         ),
    .avm_rdat       (s_avm_rdat         ),
    .avm_rvld       (s_avm_rvld         ),
    .avm_rspo       (s_avm_rspo         ),
    .avm_wrsp       (s_avm_wrsp         ),

    .reg_en         (reg_en),
    .reg_we         (reg_we),
    .reg_addr       (reg_addr),
    .reg_din        (reg_din),
    .reg_dout       (reg_dout),

    .clk            (axil_aclk),
    .rst_n          (axil_aresetn)
  );

  assign stream_pkt_rst = reg_statis_cnt_clear_en;

 always @(posedge axil_aclk) 
  begin
     if (~axil_aresetn) 
     	 base_filter <= 5'd0;
     else if (reg_en && reg_we && reg_addr == REG_RX_FILTER_BASE)
	     base_filter <= reg_din[4:0];
  end  

 always @(posedge axil_aclk) 
  begin
     if (~axil_aresetn) 
     	 filter_done <= 1'b0;
     else if (reg_en && reg_we && reg_addr == REG_RX_FILTER_DONE)
     	 filter_done <= reg_din[0];
  end 

 always @(posedge axil_aclk) 
  begin
     if (~axil_aresetn) 
     	  policy_vld <= 32'd0;
     else if (reg_en && reg_we && reg_addr == REG_RX_FILTER_POLICY_EN)
     	  policy_vld <= reg_din[31:0];
  end 

  always @(posedge axil_aclk) 
  begin
	  if (~axil_aresetn)begin 
       	  info_filter_item0  <= 320'd0;
       	  info_filter_item1  <= 320'd0;
       	  info_filter_item2  <= 320'd0;
       	  info_filter_item3  <= 320'd0;
       	  info_filter_item4  <= 320'd0;
       	  info_filter_item5  <= 320'd0;
       	  info_filter_item6  <= 320'd0;
       	  info_filter_item7  <= 320'd0;

    end  
	  else if (!filter_done && reg_en && reg_we && reg_addr == REG_RX_FILTER_INFO)begin
        case (base_filter)
          5'd0: info_filter_item0   <= {info_filter_item0[287:0],reg_din[31:0]};
          5'd1: info_filter_item1   <= {info_filter_item1[287:0],reg_din[31:0]};
          5'd2: info_filter_item2   <= {info_filter_item2[287:0],reg_din[31:0]};
          5'd3: info_filter_item3   <= {info_filter_item3[287:0],reg_din[31:0]};
          5'd4: info_filter_item4   <= {info_filter_item4[287:0],reg_din[31:0]};
          5'd5: info_filter_item5   <= {info_filter_item5[287:0],reg_din[31:0]};
          5'd6: info_filter_item6   <= {info_filter_item6[287:0],reg_din[31:0]};
          5'd7: info_filter_item7   <= {info_filter_item7[287:0],reg_din[31:0]};

        endcase 
    end
  end  


  always @(posedge axil_aclk) 
  begin
     if (~axil_aresetn)begin 
     	 reg_statis_cnt_clear_en <= 0;
       stream_pkt_r_req <= 0;
       stream_pkt_id_r <= 16'd0;
     end       
     else if (reg_en && reg_we && reg_addr == REG_RX_PKTS_CLEAR)begin
	     reg_statis_cnt_clear_en <= reg_din[16];
       if(reg_din[16] == 1'b0)begin
         stream_pkt_r_req <= 1'b1;
         stream_pkt_id_r = reg_din[15:0];
       end
     end   
     else begin
     	 reg_statis_cnt_clear_en <= 0;
       stream_pkt_r_req <= 0;
     end   
  end   

 always @(posedge axil_aclk) 
  begin
     if (~axil_aresetn) 
     	rx_pkt_en <= 0;
     else if (reg_en && reg_we && reg_addr == REG_RX_PKTS_ENABLE)
	    rx_pkt_en <= reg_din[0];
  end   

 always @(posedge axil_aclk) 
  begin
     if (~axil_aresetn) 
     	rx_pkt_mix_en <= 0;
     else if (reg_en && reg_we && reg_addr == REG_RX_PKTS_MIXED_ENABLE)
	rx_pkt_mix_en <= reg_din[0];
  end 
 
  always @(posedge axil_aclk) 
  begin
     if (~axil_aresetn) 
     	rx_pkt_filter_en <= 0;
     else if (reg_en && reg_we && reg_addr == REG_RX_PKTS_FILTER_ENABLE)
	    rx_pkt_filter_en <= reg_din[0];
  end 

  always @(posedge axil_aclk) 
  begin
     if (~axil_aresetn) 
     	rx_pkt_filter_type <= 0;
     else if (reg_en && reg_we && reg_addr == REG_RX_PKTS_FILTER_TYPE)
	rx_pkt_filter_type <= reg_din[0];
  end 

  always @(posedge axil_aclk) 
  begin
     if (~axil_aresetn) 
     	rx_all_en <= 1'b1;
     else if (reg_en && reg_we && reg_addr == REG_RX_PKTS_ALL_ENABLE)
	    rx_all_en <= reg_din[0];
  end
 
  always @(posedge axil_aclk) 
  begin
     if (~axil_aresetn) 
     	work_mode <= 0;
     else if (reg_en && reg_we && reg_addr == REG_RX_PKTS_WORK_MODE)
	work_mode <= reg_din[0];
  end

  always @(posedge axil_aclk) 
  begin
     if (~axil_aresetn)     
        test_mode <= 0 ;
     else if (reg_en && reg_we && reg_addr == REG_RX_TEST_MODE)
	      test_mode <= reg_din[0];
   end

  always @(posedge axil_aclk) 
  begin
     if (~axil_aresetn)     
        timestamp_delay_type <= 0 ;
     else if (reg_en && reg_we && reg_addr == REG_RX_TIMEDELAY_TYPE)
	    timestamp_delay_type <= reg_din[0];
   end
   always @(posedge axil_aclk) 
  begin
     if (~axil_aresetn)begin     
        timestamp_delay_value <= 32'h2bc;
     end   
     else if (reg_en && reg_we && reg_addr == REG_RX_TIMEDELAY_VAL)begin
	    timestamp_delay_value <= reg_din; 
	  end   
   end

  always @(posedge axil_aclk) begin
    if (~axil_aresetn) begin
      info_filter_item <= 320'd0;
    end
    else begin
      case (base_filter)
        5'd0: info_filter_item  <= info_filter_item0;
        5'd1: info_filter_item  <= info_filter_item1;
        5'd2: info_filter_item  <= info_filter_item2;
        5'd3: info_filter_item  <= info_filter_item3;
        5'd4: info_filter_item  <= info_filter_item4;
        5'd5: info_filter_item  <= info_filter_item5;
        5'd6: info_filter_item  <= info_filter_item6;
        5'd7: info_filter_item  <= info_filter_item7;

      endcase 
    end  
  end

  always @(posedge axil_aclk) begin
    if (~axil_aresetn) begin
      reg_dout <= 0;
    end
    else if (reg_en && ~reg_we) begin
      case (reg_addr)
        REG_RX_PKTS_ENABLE        : begin
            reg_dout <= {31'd0,rx_pkt_en};
        end
        REG_RX_PKTS_MIXED_ENABLE  : begin
            reg_dout <= {31'd0,rx_pkt_mix_en};
        end    
        REG_RX_PKTS_CLEAR         : begin
            reg_dout <= {31'd0,reg_statis_cnt_clear_en};
        end
	    REG_RX_PKTS_FILTER_ENABLE : begin
            reg_dout <= {31'd0,rx_pkt_filter_en};
    	end
        REG_RX_PKTS_FILTER_TYPE   : begin
            reg_dout <= {31'd0,rx_pkt_filter_type};
        end
        REG_RX_FILTER_BASE : begin
            reg_dout <= {27'd0,base_filter};
        end
        REG_RX_FILTER_DONE : begin
            reg_dout <= {31'd0,filter_done};
        end    
        REG_RX_FILTER_POLICY_EN : begin
            reg_dout <= policy_vld;
        end        
	     REG_RX_PKTS_RECV_LOWER: begin
          reg_dout <= reg_rx_pkts_recv[31:0];
        end
        REG_RX_PKTS_RECV_UPPER: begin
          reg_dout <= reg_rx_pkts_recv[63:32];
        end
        REG_RX_BYTES_RECV_LOWER: begin
          reg_dout <= reg_rx_bytes_recv[31:0];
        end
        REG_RX_BYTES_RECV_UPPER: begin
          reg_dout <= reg_rx_bytes_recv[63:32];
        end
        REG_RX_PKTS_DROP_LOWER: begin
          reg_dout <= reg_rx_pkts_drop[31:0];
        end
        REG_RX_PKTS_DROP_UPPER: begin
          reg_dout <= reg_rx_pkts_drop[63:32];
        end
        REG_RX_BYTES_DROP_LOWER: begin
          reg_dout <= reg_rx_bytes_drop[31:0];
        end
        REG_RX_BYTES_DROP_UPPER: begin
          reg_dout <= reg_rx_bytes_drop[63:32];
        end
        REG_RX_PKTS_ERR_LOWER: begin
          reg_dout <= reg_rx_pkts_err[31:0];
        end
        REG_RX_PKTS_ERR_UPPER: begin
          reg_dout <= reg_rx_pkts_err[63:32];
        end
        REG_RX_BYTES_ERR_LOWER: begin
          reg_dout <= reg_rx_bytes_err[31:0];
        end
        REG_RX_BYTES_ERR_UPPER: begin
          reg_dout <= reg_rx_bytes_err[63:32];
        end
        REG_RX_IP_CKSUM_ERR_LOWER: begin
          reg_dout <= reg_rx_pkts_ip_checksum_err[31:0];
        end
        REG_RX_IP_CKSUM_ERR_UPPER: begin
          reg_dout <= reg_rx_pkts_ip_checksum_err[63:32];
        end
        REG_RX_PKTS_STREAM_LOWER: begin
          reg_dout <= stream_pkt_rdata;
        end
        REG_RX_PKTS_STREAM_UPPER: begin
          reg_dout <= 0;
        end
        REG_RX_BYTES_STREAM_LOWER: begin
          reg_dout <= stream_byt_rdata[31:0];
        end
        REG_RX_BYTES_STREAM_UPPER: begin
          reg_dout <= stream_byt_rdata[63:32];
        end
        REG_RX_SUM_TIMESTAMP_LOWER: begin
	      reg_dout <= reg_rx_pkt_sum_delay[31:0];
        end  
        REG_RX_SUM_TIMESTAMP_UPPER: begin
	      reg_dout <= reg_rx_pkt_sum_delay[63:32];
        end  
        REG_RX_MAX_TIMESTAMP_LOWER: begin
	      reg_dout <= reg_rx_pkt_max_delay[31:0];
        end  
        REG_RX_MAX_TIMESTAMP_UPPER: begin
	      reg_dout <= reg_rx_pkt_max_delay[63:32];
        end 
        REG_RX_MIN_TIMESTAMP_LOWER: begin
	      reg_dout <= reg_rx_pkt_min_delay[31:0];
        end  
        REG_RX_MIN_TIMESTAMP_UPPER: begin
	      reg_dout <= reg_rx_pkt_min_delay[63:32];
        end 
        REG_RX_SUM_JITTER_LOWER: begin
	      reg_dout <= reg_rx_pkt_sum_jitter[31:0];
        end  
        REG_RX_SUM_JITTER_UPPER: begin
	      reg_dout <= reg_rx_pkt_sum_jitter[63:32];
        end 
        REG_RX_MAX_JITTER_LOWER: begin
	      reg_dout <= reg_rx_pkt_max_jitter[31:0];
        end  
        REG_RX_MAX_JITTER_UPPER: begin
	      reg_dout <= reg_rx_pkt_max_jitter[63:32];
        end 
        REG_RX_MIN_JITTER_LOWER: begin
	      reg_dout <= reg_rx_pkt_min_jitter[31:0];
        end  
        REG_RX_MIN_JITTER_UPPER: begin
	      reg_dout <= reg_rx_pkt_min_jitter[63:32];
        end 
        REG_RX_PKTS_ALL_ENABLE: begin
          reg_dout <= {31'd0,rx_all_en};
        end 
        REG_RX_PKTS_WORK_MODE: begin
          reg_dout <= {31'd0,work_mode};
        end  
        REG_RX_STATIME_LOWER : begin
          reg_dout <= reg_rx_pkt_start_time[31:0];
        end
        REG_RX_STATIME_UPPER: begin
          reg_dout <= reg_rx_pkt_start_time[63:32];
        end
        REG_RX_STPTIME_LOWER : begin
          reg_dout <= reg_rx_pkt_stop_time[31:0];
        end
        REG_RX_STPTIME_UPPER: begin
          reg_dout <= reg_rx_pkt_stop_time[63:32];
        end
        REG_RX_TEST_MODE: begin
          reg_dout <= {31'd0,test_mode};
        end  
        REG_RX_TIMEDELAY_TYPE: begin
          reg_dout <= {31'd0,timestamp_delay_type};
        end  
        REG_RX_FILTER_SIP_0: begin
          reg_dout <= info_filter_item[319:288];
        end  
        REG_RX_FILTER_SIP_1: begin
          reg_dout <= info_filter_item[287:256];
        end  
         REG_RX_FILTER_SIP_2: begin
          reg_dout <= info_filter_item[255:224];
        end        
        REG_RX_FILTER_SIP_3: begin
          reg_dout <= info_filter_item[223:192];
        end  
        REG_RX_FILTER_DIP_0: begin
          reg_dout <= info_filter_item[191:160];
        end  
        REG_RX_FILTER_DIP_1: begin
          reg_dout <= info_filter_item[159:128];
        end  
         REG_RX_FILTER_DIP_2: begin
          reg_dout <= info_filter_item[127:96];
        end        
        REG_RX_FILTER_DIP_3: begin
          reg_dout <= info_filter_item[95:64];
        end 
        REG_RX_FILTER_SP_DP: begin
          reg_dout <= info_filter_item[63:32];
        end 
        REG_RX_FILTER_MASK: begin
          reg_dout <= info_filter_item[31:0];
        end 
        REG_RX_TIMEDELAY_VAL: begin
          reg_dout <= timestamp_delay_value;
        end
        REG_ROCEV2_RT_TIMESTAMP_LOWER: begin
	      reg_dout <= reg_rocev2_pkt_rt_delay[31:0];
        end  
        REG_ROCEV2_RT_TIMESTAMP_UPPER: begin
	      reg_dout <= reg_rocev2_pkt_rt_delay[63:32];
        end  
        REG_ROCEV2_MAX_TIMESTAMP_LOWER: begin
	      reg_dout <= reg_rocev2_pkt_max_delay[31:0];
        end  
        REG_ROCEV2_MAX_TIMESTAMP_UPPER: begin
	      reg_dout <= reg_rocev2_pkt_max_delay[63:32];
        end 
        REG_ROCEV2_MIN_TIMESTAMP_LOWER: begin
	      reg_dout <= reg_rocev2_pkt_min_delay[31:0];
        end  
        REG_ROCEV2_MIN_TIMESTAMP_UPPER: begin
	      reg_dout <= reg_rocev2_pkt_min_delay[63:32];
        end 
        REG_ROCEV2_RT_JITTER_LOWER: begin
	      reg_dout <= reg_rocev2_pkt_rt_jitter[31:0];
        end  
        REG_ROCEV2_RT_JITTER_UPPER: begin
	      reg_dout <= reg_rocev2_pkt_rt_jitter[63:32];
        end 
        REG_ROCEV2_MAX_JITTER_LOWER: begin
	      reg_dout <= reg_rocev2_pkt_max_jitter[31:0];
        end  
        REG_ROCEV2_MAX_JITTER_UPPER: begin
	      reg_dout <= reg_rocev2_pkt_max_jitter[63:32];
        end 
        REG_ROCEV2_MIN_JITTER_LOWER: begin
	      reg_dout <= reg_rocev2_pkt_min_jitter[31:0];
        end  
        REG_ROCEV2_MIN_JITTER_UPPER: begin
	      reg_dout <= reg_rocev2_pkt_min_jitter[63:32];
        end 
        REG_ROCEV2_PKTS_LOWER: begin
	      reg_dout <= reg_rocev2_rx_pkts[31:0];
        end
        REG_ROCEV2_PKTS_UPPER: begin
	      reg_dout <= reg_rocev2_rx_pkts[63:32];
        end
        REG_ROCEV2_SUM_TIMESTAMP_LOWER: begin
	      reg_dout <= reg_rocev2_pkt_sum_delay[31:0];
        end  
        REG_ROCEV2_SUM_TIMESTAMP_UPPER: begin
	      reg_dout <= reg_rocev2_pkt_sum_delay[63:32];
        end 
        REG_ROCEV2_SUM_JITTER_LOWER: begin
	      reg_dout <= reg_rocev2_pkt_sum_jitter[31:0];
        end  
        REG_ROCEV2_SUM_JITTER_UPPER: begin
	      reg_dout <= reg_rocev2_pkt_sum_jitter[63:32];
        end  
        REG_RX_STREAM_SUM_TIMESTAMP_LOWER: begin
	      reg_dout <= stream_sum_delay[31:0];
        end  
        REG_RX_STREAM_SUM_TIMESTAMP_UPPER: begin
	      reg_dout <= stream_sum_delay[63:32];
        end  
        REG_RX_STREAM_MAX_TIMESTAMP_LOWER: begin
	      reg_dout <= stream_max_delay[31:0];
        end  
        REG_RX_STREAM_MAX_TIMESTAMP_UPPER: begin
	      reg_dout <= 0;
        end 
        REG_RX_STREAM_MIN_TIMESTAMP_LOWER: begin
	      reg_dout <= stream_min_delay[31:0];
        end  
        REG_RX_STREAM_MIN_TIMESTAMP_UPPER: begin
	      reg_dout <= 0;
        end 
        REG_RX_STREAM_SUM_JITTER_LOWER: begin
	      reg_dout <= stream_sum_jitter[31:0];
        end  
        REG_RX_STREAM_SUM_JITTER_UPPER: begin
	      reg_dout <= stream_sum_jitter[63:32];
        end 
        REG_RX_STREAM_MAX_JITTER_LOWER: begin
	      reg_dout <= reg_rx_pkt_max_jitter[31:0];
        end  
        REG_RX_STREAM_MAX_JITTER_UPPER: begin
	      reg_dout <= stream_max_jitter;
        end 
        REG_RX_STREAM_MIN_JITTER_LOWER: begin
	      reg_dout <= stream_min_jitter[31:0];
        end  
        REG_RX_STREAM_MIN_JITTER_UPPER: begin
	      reg_dout <= 0;
        end 

	    default: begin
          reg_dout <= 32'hDEADBEEF;
        end
      endcase
    end
  end

endmodule

