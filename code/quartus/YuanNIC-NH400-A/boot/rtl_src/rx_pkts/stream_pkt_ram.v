`timescale 1ns/1ps
module stream_pkt_ram 
(  
input          stream_pkt_tvalid,
input          stream_pkt_tlast,
input          stream_pkt_tready,
input [15:0]   rx_bytes,
input          stream_pkt_r_req,
input [15:0]   stream_pkt_id_w,
input [15:0]   stream_pkt_id_r,
input          stream_pkt_rst,
output reg [31:0]  stream_pkt_rdata,
output reg [63:0]  stream_byt_rdata,

input    axis_aclk,
input    axil_aclk,
input    axis_rstn
);


reg   [31:0]  stream_pkt_dinb; 
reg   [31:0]  stream_pkt_dina0;
reg   [31:0]  stream_pkt_dina1;
reg          stream_pkt_wea0;
reg          stream_pkt_wea1;
reg          stream_pkt_web;
reg  [11:0]  stream_pkt_addra0;
reg  [11:0]  stream_pkt_addra1;
reg          stream_pkt_renb;
reg  [11:0]  stream_pkt_addrb;
wire [31:0]  stream_pkt_douta0;
wire [31:0]  stream_pkt_douta1;
wire [31:0]  stream_pkt_doutb0;
wire [31:0]  stream_pkt_doutb1;

reg  [63:0]  stream_byt_dina0;
reg  [63:0]  stream_byt_dina1;
wire [63:0]  stream_byt_douta0;
wire [63:0]  stream_byt_douta1;
wire [63:0]  stream_byt_doutb0;
wire [63:0]  stream_byt_doutb1;
reg  [63:0]  stream_byt_dinb;

reg          stream_pkt_wr0;
reg          stream_pkt_wr1;
reg [13:0]   rx_bytes_0;
reg [13:0]   rx_bytes_1;
reg          clearing;

reg          stream_pkt_rreq_cdc1;
reg          stream_pkt_rreq_cdc2;
reg [11:0]   stream_pkt_rid_cdc;
reg          stream_pkt_renb_cdc1;
reg          stream_pkt_renb_cdc2;

reg          stream_pkt_rst_cdc1;
reg          stream_pkt_rst_cdc2;

    always @(posedge axis_aclk ) begin
        stream_pkt_dina0 <= stream_pkt_douta0 + 32'd1; 
        stream_pkt_dina1 <= stream_pkt_douta1 + 32'd1; 
        stream_byt_dina0 <= stream_byt_douta0 + rx_bytes_0 + 64'd24;
        stream_byt_dina1 <= stream_byt_douta1 + rx_bytes_1 + 64'd24;
    end

//assign stream_pkt_dina0 = stream_pkt_douta0 + 32'd1; 
//assign stream_pkt_dina1 = stream_pkt_douta1 + 32'd1; 
//assign stream_byt_dina0 = stream_byt_douta0 + rx_bytes_0 + 64'd24;
//assign stream_byt_dina1 = stream_byt_douta1 + rx_bytes_1 + 64'd24;

 always@(posedge axis_aclk)
 begin
   if(!axis_rstn)begin
     stream_pkt_wea0   <= 1'b0;
     stream_pkt_wr0    <= 1'b0;
     stream_pkt_addra0 <= 12'd0;
     rx_bytes_0        <= 11'd0;
   end  
   else begin
     stream_pkt_wr0  <=  ~stream_pkt_wr0 & stream_pkt_tvalid & stream_pkt_tlast & stream_pkt_tready;
     if(~stream_pkt_wr0 & stream_pkt_tvalid & stream_pkt_tlast & stream_pkt_tready)begin
       stream_pkt_addra0 <= stream_pkt_id_w[11:0];
       rx_bytes_0 <= rx_bytes[13:0];
     end 
     stream_pkt_wea0 <= stream_pkt_wr0;
   end  
 end  

 always@(posedge axis_aclk)
 begin
   if(!axis_rstn)begin
     stream_pkt_wea1   <= 1'b0;
     stream_pkt_wr1    <= 1'b0;
     stream_pkt_addra1 <= 12'd0;
     rx_bytes_1        <= 11'd0;
   end  
   else begin
     stream_pkt_wr1  <= stream_pkt_wr0 & stream_pkt_tvalid & stream_pkt_tlast & stream_pkt_tready;
     if(stream_pkt_wr0 & stream_pkt_tvalid & stream_pkt_tlast & stream_pkt_tready)begin
       stream_pkt_addra1 <= stream_pkt_id_w[11:0];
       rx_bytes_1 <= rx_bytes[13:0];
     end 
     stream_pkt_wea1 <= stream_pkt_wr1;
   end  
 end 

    always@(posedge axil_aclk) begin
        stream_pkt_dinb  <= 32'd0;
        stream_byt_dinb  <= 64'd0;

        if(!axis_rstn)
            stream_pkt_web <= 1'b0;
        else if(stream_pkt_web & stream_pkt_addrb == 12'd4095)
            stream_pkt_web <= 1'b0;
        else if(stream_pkt_rst_cdc2)
            stream_pkt_web <=  1'b1;


        if(stream_pkt_web)
            stream_pkt_addrb <= stream_pkt_addrb + 1;
        else if(stream_pkt_rst_cdc2)
            stream_pkt_addrb <= 12'd0;
        else 
            stream_pkt_addrb <= stream_pkt_rid_cdc;
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
        if(stream_pkt_renb_cdc1)begin 
            stream_pkt_rdata <= stream_pkt_doutb0 + stream_pkt_doutb1;
            stream_byt_rdata <= stream_byt_doutb0 + stream_byt_doutb1;
        end  
    end

    ram_2r2w #(
        .ram_block_type         ("M20K"             ),
        .widthad_a              (12                 ),
        .widthad_b              (12                 ),
        .width_a                (32                 ),
        .width_b                (32                 )
    )
    stream_pkt_ram0
    (
        .address_a              (stream_pkt_addra0  ),
        .address_b              (stream_pkt_addrb   ),
        .data_a                 (stream_pkt_dina0   ),
        .data_b                 (stream_pkt_dinb    ),
        .rden_a                 (stream_pkt_wr0     ),
        .rden_b                 (stream_pkt_renb    ),
        .wren_a                 (stream_pkt_wea0    ),
        .wren_b                 (stream_pkt_web     ),
        .clock                  (axis_aclk          ),
        .q_a                    (stream_pkt_douta0  ),
        .q_b                    (stream_pkt_doutb0  )
    );

    ram_2r2w #(
        .ram_block_type         ("M20K"             ),
        .widthad_a              (12                 ),
        .widthad_b              (12                 ),
        .width_a                (32                 ),
        .width_b                (32                 )
    )
    stream_pkt_ram1
    (
        .address_a              (stream_pkt_addra1  ),
        .address_b              (stream_pkt_addrb   ),
        .data_a                 (stream_pkt_dina1   ),
        .data_b                 (stream_pkt_dinb    ),
        .rden_a                 (stream_pkt_wr0     ),
        .rden_b                 (stream_pkt_renb    ),
        .wren_a                 (stream_pkt_wea1    ),
        .wren_b                 (stream_pkt_web     ),
        .clock                  (axis_aclk          ),
        .q_a                    (stream_pkt_douta1  ),
        .q_b                    (stream_pkt_doutb1  )
    );

    ram_2r2w #(
        .ram_block_type         ("M20K"             ),
        .widthad_a              (12                 ),
        .widthad_b              (12                 ),
        .width_a                (64                 ),
        .width_b                (64                 )
    )
    stream_pkt_ram2
    (
        .address_a              (stream_pkt_addra0  ),
        .address_b              (stream_pkt_addrb   ),
        .data_a                 (stream_byt_dina0   ),
        .data_b                 (stream_byt_dinb    ),
        .rden_a                 (stream_pkt_wr0     ),
        .rden_b                 (stream_pkt_renb    ),
        .wren_a                 (stream_pkt_wea0    ),
        .wren_b                 (stream_pkt_web     ),
        .clock                  (axis_aclk          ),
        .q_a                    (stream_byt_douta0  ),
        .q_b                    (stream_byt_doutb0  )
    );

    ram_2r2w #(
        .ram_block_type         ("M20K"             ),
        .widthad_a              (12                 ),
        .widthad_b              (12                 ),
        .width_a                (64                 ),
        .width_b                (64                 )
    )
    stream_pkt_ram3
    (
        .address_a              (stream_pkt_addra1  ),
        .address_b              (stream_pkt_addrb   ),
        .data_a                 (stream_byt_dina1   ),
        .data_b                 (stream_byt_dinb    ),
        .rden_a                 (stream_pkt_wr0     ),
        .rden_b                 (stream_pkt_renb    ),
        .wren_a                 (stream_pkt_wea1    ),
        .wren_b                 (stream_pkt_web     ),
        .clock                  (axis_aclk          ),
        .q_a                    (stream_byt_douta1  ),
        .q_b                    (stream_byt_doutb1  )
    );

endmodule
