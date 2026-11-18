//
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
module stream_st_ram 
(  
input          stream_pkt_tvalid,
input          stream_pkt_tlast,
input          stream_pkt_tready,
input [31:0]   timestamp_delay, 
input          stream_pkt_r_req,
input [15:0]   stream_pkt_id_w,
input [15:0]   stream_pkt_id_r,
input          stream_pkt_rst,
output reg [31:0] stream_max_delay, 
output reg [31:0] stream_min_delay, 
output reg [63:0] stream_sum_delay, 
output reg [31:0] stream_max_jitter,
output reg [31:0] stream_min_jitter,
output reg [63:0] stream_sum_jitter,

input    axis_aclk,
input    axil_aclk,
input    axis_rstn
);


reg  [63:0]  stream_pkt_dina_sum[0:1];
reg  [31:0]  stream_pkt_dina_max[0:1];
reg  [31:0]  stream_pkt_dina_min[0:1];
reg  [63:0]  stream_pkt_dina_sumjitter[0:1];
reg  [31:0]  stream_pkt_dina_maxjitter[0:1];
reg  [31:0]  stream_pkt_dina_minjitter[0:1];
wire  [63:0]  stream_pkt_douta_sum[0:1];
wire  [31:0]  stream_pkt_douta_max[0:1];
wire  [31:0]  stream_pkt_douta_min[0:1];
wire  [63:0]  stream_pkt_douta_sumjitter[0:1];
wire  [31:0]  stream_pkt_douta_maxjitter[0:1];
wire  [31:0]  stream_pkt_douta_minjitter[0:1];
wire  [1:0]   stream_pkt_wr;
reg   [1:0]   stream_pkt_wea;
reg           stream_pkt_web;
reg  [11:0]   stream_pkt_addra[0:1];
reg  [8:0]    stream_pkt_addrb;
reg  [63:0]   stream_pkt_dinb; 
reg  [31:0]   stream_timestamp_delay[0:1];

wire  [63:0]  stream_pkt_doutb_sum[0:1];
wire  [31:0]  stream_pkt_doutb_max[0:1];
wire  [31:0]  stream_pkt_doutb_min[0:1];
wire  [63:0]  stream_pkt_doutb_sumjitter[0:1];
wire  [31:0]  stream_pkt_doutb_maxjitter[0:1];
wire  [31:0]  stream_pkt_doutb_minjitter[0:1];
reg          stream_pkt_renb;
reg          stream_pkt_rreq_cdc1;
reg          stream_pkt_rreq_cdc2;
reg [11:0]   stream_pkt_rid_cdc;
reg          stream_pkt_renb_cdc1;
reg          stream_pkt_renb_cdc2;

reg          stream_pkt_rst_cdc1;
reg          stream_pkt_rst_cdc2;


reg          stream_pkt_wr0;
reg          stream_pkt_wr1;

reg          clearing;


  function [31:0] delay_sel;
    input [31:0] a; 
    input [31:0] b; 
    input [0:0]  c; 
    reg [31:0] result; 
    begin
      if (a == 0) begin 
        result = b;
      end  
      else begin
        if((a<=b && c==0) || (a>=b && c==1))  
          result = b; 
        else
          result = a; 
      end  
     delay_sel = result;
    end
  endfunction

  function [31:0] jitter_sel;
    input [31:0] a; 
    input [31:0] b; 
    input [31:0] c; 
    input [0:0]  d; 
    reg [31:0] result; 
    reg [31:0] value;
    begin
      if(b >= c) begin
        value = b-c;
      end  
      else begin    
        value = c-b;
      end 
      if (b == 0) begin 
        result = 0;
      end  
      else begin
        if(a == 0)begin
          result = value;
        end
        else begin
          if((a<=value && c==0) || (a>=value && c==1))  
            result = value; 
          else
            result = a; 
        end
      end  
      jitter_sel = result;
    end
  endfunction

  function [63:0] jitter_sum_sel;
    input [63:0] a; 
    input [31:0] b; 
    input [31:0] c; 
    reg [63:0] result; 
    reg [31:0] value;
    begin
      if(b >= c) begin
        value = b-c;
      end  
      else begin    
        value = c-b;
      end 
      if (b == 0) begin 
        result = 0;
      end  
      else begin
        if(a == 0)
          result = value;
        else
          result = a + value;
      end  
      jitter_sum_sel = result;
    end
  endfunction


generate for (genvar i = 0;i<2;i=i+1) begin 
  always @(posedge axis_aclk ) begin
    stream_pkt_dina_sum[i] <= stream_pkt_douta_sum[i] + stream_timestamp_delay[i]; 
    stream_pkt_dina_max[i] <= delay_sel(stream_pkt_douta_max[i],stream_timestamp_delay[i],0); 
    stream_pkt_dina_min[i] <= delay_sel(stream_pkt_douta_min[i],stream_timestamp_delay[i],1); 
    stream_pkt_dina_sumjitter[i] <= jitter_sum_sel(stream_pkt_douta_sumjitter[i],stream_pkt_douta_max[i],stream_timestamp_delay[i]); 
    stream_pkt_dina_maxjitter[i] <= jitter_sel(stream_pkt_douta_maxjitter[i],stream_pkt_douta_max[i],stream_timestamp_delay[i],0); 
    stream_pkt_dina_minjitter[i] <= jitter_sel(stream_pkt_douta_minjitter[i],stream_pkt_douta_max[i],stream_timestamp_delay[i],1); 
  end
//assign  stream_pkt_dina_sum[i] = stream_pkt_douta_sum[i] + stream_timestamp_delay[i]; 
//assign  stream_pkt_dina_max[i] = delay_sel(stream_pkt_douta_max[i],stream_timestamp_delay[i],0); 
//assign  stream_pkt_dina_min[i] = delay_sel(stream_pkt_douta_min[i],stream_timestamp_delay[i],1); 
//assign  stream_pkt_dina_sumjitter[i] = jitter_sum_sel(stream_pkt_douta_sumjitter[i],stream_pkt_douta_max[i],stream_timestamp_delay[i]); 
//assign  stream_pkt_dina_maxjitter[i] = jitter_sel(stream_pkt_douta_maxjitter[i],stream_pkt_douta_max[i],stream_timestamp_delay[i],0); 
//assign  stream_pkt_dina_minjitter[i] = jitter_sel(stream_pkt_douta_minjitter[i],stream_pkt_douta_max[i],stream_timestamp_delay[i],1); 
end
endgenerate  

 always@(posedge axis_aclk)
 begin
   if(!axis_rstn)begin
     stream_pkt_wea[0]   <= 1'b0;
     stream_pkt_wr0    <= 1'b0;
     stream_pkt_addra[0] <= 12'd0;
     stream_timestamp_delay[0] <= 32'd0;
   end  
   else begin
     stream_pkt_wr0  <=  ~stream_pkt_wr0 & stream_pkt_tvalid & stream_pkt_tlast & stream_pkt_tready & (stream_pkt_id_w[11:8] == 4'h0);
     if(~stream_pkt_wr0 & stream_pkt_tvalid & stream_pkt_tlast & stream_pkt_tready)begin
       stream_pkt_addra[0] <= stream_pkt_id_w[11:0];
       stream_timestamp_delay[0] <= timestamp_delay;
     end 
     stream_pkt_wea[0] <= stream_pkt_wr0;
   end  
 end  
    assign stream_pkt_wr[0] = stream_pkt_wr0;

 always@(posedge axis_aclk)
 begin
   if(!axis_rstn)begin
     stream_pkt_wea[1]   <= 1'b0;
     stream_pkt_wr1      <= 1'b0;
     stream_pkt_addra[1] <= 12'd0;
     stream_timestamp_delay[1] <= 32'd0;
   end  
   else begin
     stream_pkt_wr1  <= stream_pkt_wr0 & stream_pkt_tvalid & stream_pkt_tlast & stream_pkt_tready & (stream_pkt_id_w[11:8] == 4'h0);
     if(stream_pkt_wr0 & stream_pkt_tvalid & stream_pkt_tlast & stream_pkt_tready)begin
       stream_pkt_addra[1] <= stream_pkt_id_w[11:0];
       stream_timestamp_delay[1] <= timestamp_delay;
     end 
     stream_pkt_wea[1] <= stream_pkt_wr1;
   end  
 end 
    assign stream_pkt_wr[1] = stream_pkt_wr1;

    always@(posedge axis_aclk)begin
        stream_pkt_dinb  <= 64'd0;

        if(!axis_rstn)
            stream_pkt_web    <= 1'b0;
        else if(stream_pkt_web & stream_pkt_addrb == 9'd511)
            stream_pkt_web    <= 1'b0;
        else if(stream_pkt_rst_cdc2)
            stream_pkt_web    <= 1'b1;

        if(stream_pkt_web)
            stream_pkt_addrb <= stream_pkt_addrb + 1'b1;
        else if(stream_pkt_rst_cdc2 )
            stream_pkt_addrb <= 9'd0;
        else  
            stream_pkt_addrb <= stream_pkt_id_r[8:0];
    end

    always @(posedge axil_aclk ) begin
        if(!axis_rstn)
            stream_pkt_rst_cdc1 <= 1'b0;
        else if(stream_pkt_web)
            stream_pkt_rst_cdc1 <= 1'b0;
        else if(stream_pkt_rst)
            stream_pkt_rst_cdc1 <= 1'b1;

        stream_pkt_rst_cdc2 <= stream_pkt_rst_cdc1;
    end

    always @(posedge axil_aclk) begin
        if(!axis_rstn)
            stream_pkt_rreq_cdc1 <= 1'b0;
        else if(stream_pkt_renb_cdc2)
            stream_pkt_rreq_cdc1 <= 1'b0;
        else if(stream_pkt_r_req )
            stream_pkt_rreq_cdc1 <= 1'b1;

        stream_pkt_rreq_cdc2 <= stream_pkt_rreq_cdc1;

        if(stream_pkt_r_req)
            stream_pkt_rid_cdc <= stream_pkt_id_r[11:0];
    end

    always @(posedge axis_aclk ) begin
       if(stream_pkt_rreq_cdc2)
           stream_pkt_renb <= 1'b1;
       else  
           stream_pkt_renb <= 1'b0;
    end

    always @(posedge axis_aclk ) begin
        if(!axis_rstn)
            stream_pkt_renb_cdc1 <= 1'b0;
        else if(~stream_pkt_rreq_cdc2)
            stream_pkt_renb_cdc1 <= 1'b0;
        else if(stream_pkt_renb)
            stream_pkt_renb_cdc1 <= 1'b1;
        else 

        stream_pkt_renb_cdc2 <= stream_pkt_renb_cdc1;
    end

    always @(posedge axis_aclk ) begin
        stream_sum_delay  <= stream_pkt_doutb_sum[0] + stream_pkt_doutb_sum[1]; 
        stream_max_delay  <= (stream_pkt_doutb_max[0]>stream_pkt_doutb_max[1]) ? stream_pkt_doutb_max[0] : stream_pkt_doutb_max[1]; 
        stream_min_delay  <= (stream_pkt_doutb_min[0]>stream_pkt_doutb_min[1]) ? stream_pkt_doutb_min[1] : stream_pkt_doutb_min[0]; 
        stream_sum_jitter <= stream_pkt_doutb_sumjitter[0] + stream_pkt_doutb_sumjitter[1]; 
        stream_max_jitter <= (stream_pkt_doutb_maxjitter[0]>stream_pkt_doutb_maxjitter[1]) ? stream_pkt_doutb_maxjitter[0] : stream_pkt_doutb_maxjitter[1]; 
        stream_min_jitter <= (stream_pkt_doutb_minjitter[0]>stream_pkt_doutb_minjitter[1]) ? stream_pkt_doutb_minjitter[1] : stream_pkt_doutb_minjitter[0]; 
    end

generate for (genvar i = 0;i<2;i=i+1) begin : gen_pkt_ram_sumdelay
    ram_2r2w #(
        .ram_block_type         ("M20K"             ),
        .widthad_a              (9                  ),
        .widthad_b              (9                  ),
        .width_a                (64                 ),
        .width_b                (64                 )
    )
    stream_pkt_ram_sumdelay
    (
        .address_a              (stream_pkt_addra[i]    ),
        .address_b              (stream_pkt_addrb       ),
        .data_a                 (stream_pkt_dina_sum[i] ),
        .data_b                 (stream_pkt_dinb        ),
        .rden_a                 (stream_pkt_wr[i]       ),
        .rden_b                 (stream_pkt_renb        ),
        .wren_a                 (stream_pkt_wea[i]      ),
        .wren_b                 (stream_pkt_web         ),
        .clock                  (axis_aclk              ),
        .q_a                    (stream_pkt_douta_sum[i]  ),
        .q_b                    (stream_pkt_doutb_sum[i]  )
    );
end
endgenerate  

generate for (genvar i = 0;i<2;i=i+1) begin : gen_pkt_ram_maxdelay
    ram_2r2w #(
        .ram_block_type         ("M20K"             ),
        .widthad_a              (9                  ),
        .widthad_b              (9                  ),
        .width_a                (32                 ),
        .width_b                (32                 )
    )
    stream_pkt_ram_max
    (
        .address_a              (stream_pkt_addra[i]    ),
        .address_b              (stream_pkt_addrb        ),
        .data_a                 (stream_pkt_dina_max[i] ),
        .data_b                 (stream_pkt_dinb        ),
        .rden_a                 (stream_pkt_wr[i]       ),
        .rden_b                 (stream_pkt_renb        ),
        .wren_a                 (stream_pkt_wea[i]     ),
        .wren_b                 (stream_pkt_web         ),
        .clock                  (axis_aclk              ),
        .q_a                    (stream_pkt_douta_max[i]  ),
        .q_b                    (stream_pkt_doutb_max[i]  )
    );
end
endgenerate  

generate for (genvar i = 0;i<2;i=i+1) begin : gen_pkt_ram_mindelay
    ram_2r2w #(
        .ram_block_type         ("M20K"             ),
        .widthad_a              (9                  ),
        .widthad_b              (9                  ),
        .width_a                (32                 ),
        .width_b                (32                 )
    )
    stream_pkt_ram_min
    (
        .address_a              (stream_pkt_addra[i]    ),
        .address_b              (stream_pkt_addrb        ),
        .data_a                 (stream_pkt_dina_min[i] ),
        .data_b                 (stream_pkt_dinb        ),
        .rden_a                 (stream_pkt_wr[i]       ),
        .rden_b                 (stream_pkt_renb        ),
        .wren_a                 (stream_pkt_wea[i]     ),
        .wren_b                 (stream_pkt_web         ),
        .clock                  (axis_aclk              ),
        .q_a                    (stream_pkt_douta_min[i]  ),
        .q_b                    (stream_pkt_doutb_min[i]  )
    );
end
endgenerate 

generate for (genvar i = 0;i<2;i=i+1) begin : gen_pkt_ram_sumjitter
    ram_2r2w #(
        .ram_block_type         ("M20K"             ),
        .widthad_a              (9                  ),
        .widthad_b              (9                  ),
        .width_a                (64                 ),
        .width_b                (64                 )
    )
    stream_pkt_ram_sumjitter
    (
        .address_a              (stream_pkt_addra[i]    ),
        .address_b              (stream_pkt_addrb        ),
        .data_a                 (stream_pkt_dina_sumjitter[i] ),
        .data_b                 (stream_pkt_dinb        ),
        .rden_a                 (stream_pkt_wr[i]       ),
        .rden_b                 (stream_pkt_renb        ),
        .wren_a                 (stream_pkt_wea[i]     ),
        .wren_b                 (stream_pkt_web         ),
        .clock                  (axis_aclk              ),
        .q_a                    (stream_pkt_douta_sumjitter[i]  ),
        .q_b                    (stream_pkt_doutb_sumjitter[i]  )
    );
end
endgenerate  

generate for (genvar i = 0;i<2;i=i+1) begin : gen_pkt_ram_maxjitter
    ram_2r2w #(
        .ram_block_type         ("M20K"             ),
        .widthad_a              (9                  ),
        .widthad_b              (9                  ),
        .width_a                (32                 ),
        .width_b                (32                 )
    )
    stream_pkt_ram_maxjitter
    (
        .address_a              (stream_pkt_addra[i]    ),
        .address_b              (stream_pkt_addrb        ),
        .data_a                 (stream_pkt_dina_maxjitter[i] ),
        .data_b                 (stream_pkt_dinb        ),
        .rden_a                 (stream_pkt_wr[i]       ),
        .rden_b                 (stream_pkt_renb        ),
        .wren_a                 (stream_pkt_wea[i]     ),
        .wren_b                 (stream_pkt_web         ),
        .clock                  (axis_aclk              ),
        .q_a                    (stream_pkt_douta_maxjitter[i]  ),
        .q_b                    (stream_pkt_doutb_maxjitter[i]  )
    );
end
endgenerate  

generate for (genvar i = 0;i<2;i=i+1) begin : gen_pkt_ram_minjitter
    ram_2r2w #(
        .ram_block_type         ("M20K"             ),
        .widthad_a              (9                  ),
        .widthad_b              (9                  ),
        .width_a                (32                 ),
        .width_b                (32                 )
    )
    stream_pkt_ram_minjitter
    (
        .address_a              (stream_pkt_addra[i]    ),
        .address_b              (stream_pkt_addrb        ),
        .data_a                 (stream_pkt_dina_minjitter[i] ),
        .data_b                 (stream_pkt_dinb        ),
        .rden_a                 (stream_pkt_wr[i]       ),
        .rden_b                 (stream_pkt_renb        ),
        .wren_a                 (stream_pkt_wea[i]      ),
        .wren_b                 (stream_pkt_web         ),
        .clock                  (axis_aclk              ),
        .q_a                    (stream_pkt_douta_minjitter[i]  ),
        .q_b                    (stream_pkt_doutb_minjitter[i]  )
    );
end
endgenerate 



 endmodule
