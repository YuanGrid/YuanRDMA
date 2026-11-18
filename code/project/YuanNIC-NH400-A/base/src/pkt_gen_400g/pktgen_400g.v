//-----------------------------------------------------------------------------
// Title         : pktgen_400g
// Project       : MA_A3
//-----------------------------------------------------------------------------
// File          : pktgen_400g.v
// Author        :   <Administrator@DESKTOP-SKNAR7C>
// Created       : 08.06.2024
// Last modified : 08.06.2024
//-----------------------------------------------------------------------------
// Description :
// 
// Modification history :
// 08.06.2024 : created
//-----------------------------------------------------------------------------

`include "../top/define.v"

module pktgen_400g (/*AUTOARG*/
   // Outputs
   tx_ack, tx_wenb, tx_wdat, tx_weop, tx_winf,
   // Inputs
   rst, clk, cur_time, tx_mod, tx_num, tx_req, tx_stop, tx_busy
   ) ;
   input  wire                  rst;
   input  wire 					clk;

   input  wire [31:0] 			cur_time;

   input  wire [3:0] 			tx_mod;//len_mod
   input  wire [31:0] 			tx_num;//tx_num == 0ʱ, send pkt forever
   input  wire 					tx_req; 
   input  wire 					tx_stop; //ǿ��ֹͣ
   output  reg 					tx_ack;

   output  reg 					tx_wenb;
   output wire [1023:0] 		tx_wdat;
   output wire [47:0] 			tx_weop;
   output wire [15:0] 			tx_winf;
   input  wire 					tx_busy;

   wire [47:0] 					eth_dmac;
   wire [47:0] 					eth_smac;
   wire [15:0] 					eth_type;
   wire [15:0] 					eth_pld;
   reg [31:0] 					pkt_indx;
   
   assign eth_dmac = {24'h002145,cur_time[23:0]};
   assign eth_smac = {24'h002245,pkt_indx[23:0]};
   assign eth_type = 16'h8050;
   assign eth_pld  = 16'hFFFF;

   wire [127:0] 				pkt_header;

   assign pkt_header = {eth_dmac[47:0],eth_smac[47:0],eth_type[15:0],eth_pld[15:0]};

   wire [127:0] 				lit_header; //pkt header little

   genvar 						i;
   
   generate
	  for(i=0;i <= 15;i=i+1) begin :order_gen
		 assign lit_header[i*8+7:i*8] = pkt_header[(15-i)*8+7:(15-i)*8];
	  end
   endgenerate

   reg [63:0] 					pld_dat = 64'hF000_1234_5678_ABCD;
   reg [63:0] 					pld_tmp;
   
   always @ ( posedge clk ) begin
	  pld_tmp     = pld_dat;
	  pld_tmp[0]  = pld_dat[63] ^ pld_dat[32] ^ pld_dat[15];
	  pld_tmp[24] = pld_dat[25] ^ pld_dat[24] ^ pld_dat[2];
	  pld_tmp[48] = pld_dat[0]  ^ pld_dat[1]  ^ pld_dat[2];
	  pld_dat     = {pld_tmp[62:0],pld_tmp[63]};
   end
   
   wire [63:0] 					header_seg0;
   wire [63:0] 					header_seg1;

   assign header_seg0 = lit_header[63:0];
   assign header_seg1 = lit_header[127:64];


   parameter IDLE = 4'b0001;
   parameter WORK = 4'b0010;
   parameter WAIT = 4'b0100;
   parameter STOP = 4'b1000;

   reg [3:0] 					cur_stat;
   reg [3:0] 					nxt_stat;
   wire 						tx_eop;   
   reg [3:0] 					stop_cnt;
   wire                         pkt_stop;

   always @ ( posedge clk, posedge rst ) begin
	  if(rst == 1'b1)
		cur_stat <= IDLE;
	  else
		cur_stat <= nxt_stat;
   end

   always @ ( * ) begin
	  case (cur_stat)
		IDLE:
		  if(tx_req == 1'b1)
			nxt_stat <= WORK;
		  else
			nxt_stat <= IDLE;

		WORK:
		  if(tx_eop == 1'b1)
			if(pkt_stop == 1'b1)
			  nxt_stat <= STOP;
			else
			  if(tx_busy == 1'b1)
				nxt_stat <= WAIT;
			  else
				nxt_stat <= WORK;
		  else
			nxt_stat <= WORK;

		WAIT:
		  if(tx_busy == 1'b0)
			nxt_stat <= WORK;
		  else
			nxt_stat <= WAIT;

		STOP:
		  if(stop_cnt == 4'd0)
			nxt_stat <= IDLE;
		  else
			nxt_stat <= STOP;

		default: nxt_stat <= IDLE;
	  endcase // case (cur_stat)
   end // always @ ( * )

   reg [6:0]              byt128_cnt;
   reg [6:0] 			  byt128_len;
   reg                    send_64b;
   reg [3:0]              tx_mod_d;
   
   always @ ( posedge clk ) begin
	  if(cur_stat == IDLE && nxt_stat != IDLE) begin
		 case (tx_mod) //lengnth mode
		   4'b0000: byt128_len <= 7'd0; //send 64bytes packet
		   4'b0001: byt128_len <= 7'd0; //128bytes
		   4'b0010: byt128_len <= 7'd1; //256bytes
		   4'b0011: byt128_len <= 7'd3; //512bytes
		   4'b0100: byt128_len <= 7'd7; //1024bytes
		   4'b0101: byt128_len <= 7'd11; //1518bytes
		   4'b0110: byt128_len <= 7'd15; //2048bytes
		   4'b0111: byt128_len <= 7'd74; //9600bytes
		   default: byt128_len <= 7'd31; //4096bytes
		 endcase // case (tx_mod)
		 send_64b <= (tx_mod == 4'h0);
		 tx_mod_d <= tx_mod;
	  end
   end // always @ ( posedge clk )

   reg [31:0]             tx_pkt_cnt;

   always @ ( posedge clk ) begin
	  if(cur_stat == IDLE && nxt_stat != IDLE) begin
		 if(tx_mod == 4'h0)//64�ֽ� һ�η�2������,���Ե�������
		   tx_pkt_cnt <= tx_num[31:1] + tx_num[0] - 1'b1;
		 else
		   tx_pkt_cnt <= tx_num[31:0] - 1'b1;
	  end
	  else if(cur_stat == WORK && tx_eop == 1'b1) begin
		 tx_pkt_cnt <= tx_pkt_cnt - 1'b1;
	  end
   end // always @ ( posedge clk )

   always @ ( posedge clk ) begin
	  if(cur_stat == IDLE && nxt_stat != IDLE) 
		pkt_indx <= 32'd0;
	  else if(cur_stat == WORK && tx_eop == 1'b1)
		pkt_indx <= pkt_indx + 1'b1;
   end
   
   wire                      stop0;
   wire 					 stop1;
   reg 						 send_forever;

   always @ ( posedge clk ) begin
	  if((cur_stat == IDLE) && (nxt_stat != IDLE))
		if(tx_num == 32'h0)
		  send_forever <= 1'b1;
		else
		  send_forever <= 1'b0;
   end
   
   assign stop0     = tx_stop;
   assign stop1     = (tx_pkt_cnt == 32'h0) & (send_forever == 1'b0);
   assign pkt_stop  = stop0 | stop1;
				  
   always @ ( posedge clk ) begin
	  if(cur_stat == IDLE && nxt_stat != IDLE)
		byt128_cnt <= 7'd0;
	  else if(cur_stat == WORK)
		if(byt128_cnt == byt128_len)
		  byt128_cnt <= 7'd0;
		else
		  byt128_cnt <= byt128_cnt + 1'b1;
   end

   assign tx_eop = (cur_stat == WORK) && (byt128_cnt == byt128_len);

   always @ ( posedge clk ) begin
	  if(cur_stat == WORK && nxt_stat == STOP)
		stop_cnt <= 4'd15;
	  else
		stop_cnt <= stop_cnt - 1'b1;

	  if(cur_stat == WORK && nxt_stat == STOP)
		tx_ack <= 1'b1;
	  else if(cur_stat == STOP && stop_cnt == 4'd8)
		tx_ack <= 1'b0;
   end

   reg [63:0]            tx_dat0 , tx_dat1 ,tx_dat2 ,tx_dat3;
   reg [63:0]            tx_dat4 , tx_dat5 ,tx_dat6 ,tx_dat7;
   reg [63:0]            tx_dat8 , tx_dat9 ,tx_dat10,tx_dat11;
   reg [63:0]            tx_dat12, tx_dat13,tx_dat14,tx_dat15;
   
   
   always @ ( posedge clk ) begin
	  if(byt128_cnt == 7'd0) begin
		 tx_dat0 <= header_seg0;
		 tx_dat1 <= header_seg1;
	  end
	  else begin
		 tx_dat0 <= pld_dat;
		 tx_dat1 <= pld_dat;
	  end
	  
	  if(byt128_cnt == 7'd0 && send_64b == 1'b1) begin
		 tx_dat8 <= header_seg0;
		 tx_dat9 <= header_seg1;
	  end
	  else begin
		 tx_dat8 <= pld_dat;
		 tx_dat9 <= pld_dat;
	  end
	  
	  tx_dat2 <= pld_dat;
	  tx_dat3 <= pld_dat;
	  tx_dat4 <= pld_dat;
	  tx_dat5 <= pld_dat;
	  tx_dat6 <= pld_dat;
	  tx_dat7 <= pld_dat;
	  
	  tx_dat10<= pld_dat;
	  tx_dat11<= pld_dat;
	  tx_dat12<= pld_dat;
	  tx_dat13<= pld_dat;
	  tx_dat14<= pld_dat;
	  tx_dat15<= pld_dat;
	  
   end // always @ ( posedge clk )
   
   reg               tx_inf0 , tx_inf1 ,tx_inf2 ,tx_inf3;
   reg               tx_inf4 , tx_inf5 ,tx_inf6 ,tx_inf7;
   reg               tx_inf8 , tx_inf9 ,tx_inf10,tx_inf11;
   reg               tx_inf12, tx_inf13,tx_inf14,tx_inf15;   
   
   reg [2:0]         tx_eop0 , tx_eop1 ,tx_eop2 ,tx_eop3;
   reg [2:0]         tx_eop4 , tx_eop5 ,tx_eop6 ,tx_eop7;
   reg [2:0]         tx_eop8 , tx_eop9 ,tx_eop10,tx_eop11;
   reg [2:0]         tx_eop12, tx_eop13,tx_eop14,tx_eop15; 

   always @ ( posedge clk ) begin
	  tx_inf0  = 1'b1;
	  tx_inf1  = 1'b1;
	  tx_inf2  = 1'b1;
	  tx_inf3  = 1'b1;
	  tx_inf4  = 1'b1;
	  tx_inf5  = 1'b1;
	  tx_inf6  = 1'b1;
	  tx_inf7  = 1'b1;
	  tx_inf8  = 1'b1;
	  tx_inf9  = 1'b1;
	  tx_inf10 = 1'b1;
	  tx_inf11 = 1'b1;
	  tx_inf12 = 1'b1;
	  tx_inf13 = 1'b1;
	  tx_inf14 = 1'b1;
	  tx_inf15 = 1'b1;

	  tx_eop0  = 3'd0;
	  tx_eop1  = 3'd0;
	  tx_eop2  = 3'd0;
	  tx_eop3  = 3'd0;
	  tx_eop4  = 3'd0;
	  tx_eop5  = 3'd0;
	  tx_eop6  = 3'd0;
	  tx_eop7  = 3'd0;
	  tx_eop8  = 3'd0;
	  tx_eop9  = 3'd0;
	  tx_eop10 = 3'd0;
	  tx_eop11 = 3'd0;
	  tx_eop12 = 3'd0;
	  tx_eop13 = 3'd0;
	  tx_eop14 = 3'd0;
	  tx_eop15 = 3'd0;
	  
	  if(tx_eop == 1'b1) begin
		 case (tx_mod_d)
		   4'b0000: begin //64
			  tx_inf7  = 1'b0;
			  tx_eop7  = 3'b100;
			
			  tx_inf15 = 1'b0;
			  tx_eop15 = 3'b100;
		   end

		   4'b0001: begin //128
			  tx_inf15 = 1'b0;
			  tx_eop15 = 3'b100;
		   end

		   4'b0010: begin//256
			  tx_inf15 = 1'b0;
			  tx_eop15 = 3'b100;
		   end

		   4'b0011: begin //512
			  tx_inf15 = 1'b0;
			  tx_eop15 = 3'b100;
		   end

		   4'b0100: begin //1024
			  tx_inf15 = 1'b0;
			  tx_eop15 = 3'b100;
		   end

		   4'b0101: begin //1518
			  tx_inf13 = 1'b0;
			  tx_eop13 = 3'b110;
			  
			  tx_inf14 = 1'b0;
			  tx_eop14 = 3'b0;

			  tx_inf15 = 1'b0;
			  tx_eop15 = 3'b0;
		   end

		   4'b0110: begin//2048
			  tx_inf15 = 1'b0;
			  tx_eop15 = 3'b100;
		   end

		   4'b0111: begin //9600
			  tx_inf15 = 1'b0;
			  tx_eop15 = 3'b100;
		   end

		   default: begin //4096
			  tx_inf15 = 1'b0;
			  tx_eop15 = 3'b100;
		   end
		 endcase // case (tx_mod_d)
	  end // if (tx_eop == 1'b1)
   end // always @ ( posedge clk )

   always @ ( posedge clk ) begin
	  if(cur_stat == WORK)
		tx_wenb <= 1'b1;
	  else
		tx_wenb <= 1'b0;
   end

   assign tx_weop = {tx_eop15,tx_eop14,tx_eop13,tx_eop12,tx_eop11,tx_eop10,tx_eop9,tx_eop8,
					 tx_eop7 ,tx_eop6 ,tx_eop5 ,tx_eop4 ,tx_eop3 ,tx_eop2 ,tx_eop1,tx_eop0};

   assign tx_wdat = {tx_dat15,tx_dat14,tx_dat13,tx_dat12,tx_dat11,tx_dat10,tx_dat9,tx_dat8,
					 tx_dat7 ,tx_dat6 ,tx_dat5 ,tx_dat4 ,tx_dat3 ,tx_dat2 ,tx_dat1,tx_dat0};
   
   assign tx_winf = {tx_inf15,tx_inf14,tx_inf13,tx_inf12,tx_inf11,tx_inf10,tx_inf9,tx_inf8,
					 tx_inf7 ,tx_inf6 ,tx_inf5 ,tx_inf4 ,tx_inf3 ,tx_inf2 ,tx_inf1,tx_inf0};

endmodule // pktgen_400g

