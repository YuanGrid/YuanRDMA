`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/07/16 09:59:09
// Design Name: 
// Module Name: match_section
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
//////////////////////////////////////////////////////////////////////////////////


module match_section(
input               clk ,
input               resetn ,

input               dmac_val,
input    [47:0]     dmac,
input               dmac_en    ,
input               dmac_mode  ,
input    [47:0]     dmac_mask  ,
input    [47:0]     dmac_value ,

input               smac_val, 
input   [47:0]      smac, 
input               smac_en    ,
input               smac_mode  ,
input    [47:0]     smac_mask  ,
input    [47:0]     smac_value ,

input               vlanid1_val,
input   [11:0]      vlanid1,
input               vlanid2_val,
input   [11:0]      vlanid2,
input               vlanid_en    ,
input               vlanid_mode  ,
input    [11:0]     vlanid_mask  ,
input    [11:0]     vlanid_value ,

input               protocol_val,
input   [ 7:0]      protocol,
input               protocol_en    ,
input               protocol_mode  ,
input    [ 7:0]     protocol_mask  ,
input    [ 7:0]     protocol_value ,

input               sipv4_val,
input   [31:0]      sipv4,
input               sipv4_en    ,
input               sipv4_mode  ,
input    [31:0]     sipv4_mask  ,
input    [31:0]     sipv4_value ,

input               dipv4_val,
input   [31:0]      dipv4,
input               dipv4_en    ,
input               dipv4_mode  ,
input    [31:0]     dipv4_mask  ,
input    [31:0]     dipv4_value ,

input               sipv6_val,
input   [127:0]     sipv6,
input               sipv6_en    ,
input               sipv6_mode  ,
input    [127:0]    sipv6_mask  ,
input    [127:0]    sipv6_value ,

input               dipv6_val,
input   [127:0]     dipv6,
input               dipv6_en    ,
input               dipv6_mode  ,
input    [127:0]    dipv6_mask  ,
input    [127:0]    dipv6_value ,

input               sport_val,
input   [15:0]      sport,
input               sport_en    ,
input               sport_mode  ,
input    [15:0]     sport_mask  ,
input    [15:0]     sport_value ,

input               dport_val,
input   [15:0]      dport,
input               dport_en    ,
input               dport_mode  ,
input    [15:0]     dport_mask  ,
input    [15:0]     dport_value ,

input               pkt_length_val,
input   [15:0]      pkt_length,
input               pkt_length_en     ,             
input               pkt_length_mode   ,             
input    [15:0]     pkt_length_mask   ,             
input    [15:0]     pkt_length_value  ,             

input               filter_en   ,
input               process_mode ,   //0:pkt pass, 1:pkt drop
input               field_relation , //0:and, 1:or
output              match_result ,   //0:not match, 1:match
output              process_result   //0:pkt pass, 1:pkt drop
);


wire [10:0] match_result_field;

assign match_result = field_relation ? (| match_result_field) : (& match_result_field);
assign process_result = filter_en ? (process_mode ? match_result : ~match_result) : 1'b0;

match_comparer#(
    .DATA_WIDTH ( 48 )
)
dmac_matcher(
    .clk             ( clk           ),
    .resetn          ( resetn        ),
    .field_valid     ( dmac_val      ),
    .field_data      ( dmac          ),
    .match_en        ( dmac_en       ),
    .field_relation  ( field_relation),
    .match_mode      ( dmac_mode     ),
    .match_mask      ( dmac_mask     ),
    .match_value     ( dmac_value    ),
    .match_result    ( match_result_field[0]    )  
);

match_comparer#(
    .DATA_WIDTH ( 48 )
)
smac_matcher(
    .clk             ( clk           ),
    .resetn          ( resetn        ),
    .field_valid     ( smac_val      ),
    .field_data      ( smac          ),
    .match_en        ( smac_en       ),
    .field_relation  ( field_relation),
    .match_mode      ( smac_mode     ),
    .match_mask      ( smac_mask     ),
    .match_value     ( smac_value    ),
    .match_result    ( match_result_field[1]    )  
);

match_comparer_vlanid#(
    .DATA_WIDTH ( 12 )
)
vlanid_matcher(
    .clk             ( clk              ),
    .resetn          ( resetn           ),
    .vlanid1_valid   ( vlanid1_val      ),
    .vlanid1_data    ( vlanid1          ),
    .vlanid2_valid   ( vlanid2_val      ),
    .vlanid2_data    ( vlanid2          ),
    .match_en        ( vlanid_en        ),
    .field_relation  ( field_relation   ),
    .match_mode      ( vlanid_mode      ),
    .match_mask      ( vlanid_mask      ),
    .match_value     ( vlanid_value     ),
    .match_result    ( match_result_field[2]    )  
);

match_comparer#(
    .DATA_WIDTH ( 8 )
)
protocol_matcher(
    .clk             ( clk           ),
    .resetn          ( resetn        ),
    .field_valid     ( protocol_val      ),
    .field_data      ( protocol          ),
    .match_en        ( protocol_en       ),
    .field_relation  ( field_relation),
    .match_mode      ( protocol_mode     ),
    .match_mask      ( protocol_mask     ),
    .match_value     ( protocol_value    ),
    .match_result    ( match_result_field[3]    )  
);

match_comparer#(
    .DATA_WIDTH ( 32 )
)
sipv4_matcher(
    .clk             ( clk           ),
    .resetn          ( resetn        ),
    .field_valid     ( sipv4_val      ),
    .field_data      ( sipv4          ),
    .match_en        ( sipv4_en       ),
    .field_relation  ( field_relation),
    .match_mode      ( sipv4_mode     ),
    .match_mask      ( sipv4_mask     ),
    .match_value     ( sipv4_value    ),
    .match_result    ( match_result_field[4]    )  
);

match_comparer#(
    .DATA_WIDTH ( 32 )
)
dipv4_matcher(
    .clk             ( clk           ),
    .resetn          ( resetn        ),
    .field_valid     ( dipv4_val      ),
    .field_data      ( dipv4          ),
    .match_en        ( dipv4_en       ),
    .field_relation  ( field_relation),
    .match_mode      ( dipv4_mode     ),
    .match_mask      ( dipv4_mask     ),
    .match_value     ( dipv4_value    ),
    .match_result    ( match_result_field[5]    )  
);

match_comparer#(
    .DATA_WIDTH ( 128 )
)
sipv6_matcher(
    .clk             ( clk           ),
    .resetn          ( resetn        ),
    .field_valid     ( sipv6_val      ),
    .field_data      ( sipv6          ),
    .match_en        ( sipv6_en       ),
    .field_relation  ( field_relation),
    .match_mode      ( sipv6_mode     ),
    .match_mask      ( sipv6_mask     ),
    .match_value     ( sipv6_value    ),
    .match_result    ( match_result_field[6]    )  
);

match_comparer#(
    .DATA_WIDTH ( 128 )
)
dipv6_matcher(
    .clk             ( clk           ),
    .resetn          ( resetn        ),
    .field_valid     ( dipv6_val      ),
    .field_data      ( dipv6          ),
    .match_en        ( dipv6_en       ),
    .field_relation  ( field_relation),
    .match_mode      ( dipv6_mode     ),
    .match_mask      ( dipv6_mask     ),
    .match_value     ( dipv6_value    ),
    .match_result    ( match_result_field[7]    )  
);

match_comparer#(
    .DATA_WIDTH ( 16 )
)
sport_matcher(
    .clk             ( clk           ),
    .resetn          ( resetn        ),
    .field_valid     ( sport_val      ),
    .field_data      ( sport          ),
    .match_en        ( sport_en       ),
    .field_relation  ( field_relation),
    .match_mode      ( sport_mode     ),
    .match_mask      ( sport_mask     ),
    .match_value     ( sport_value    ),
    .match_result    ( match_result_field[8]    )  
);

match_comparer#(
    .DATA_WIDTH ( 16 )
)
dport_matcher(
    .clk             ( clk           ),
    .resetn          ( resetn        ),
    .field_valid     ( dport_val      ),
    .field_data      ( dport          ),
    .match_en        ( dport_en       ),
    .field_relation  ( field_relation),
    .match_mode      ( dport_mode     ),
    .match_mask      ( dport_mask     ),
    .match_value     ( dport_value    ),
    .match_result    ( match_result_field[9]    )  
);

match_comparer#(
    .DATA_WIDTH ( 16 )
)
pkt_length_matcher(
    .clk             ( clk           ),
    .resetn          ( resetn        ),
    .field_valid     ( pkt_length_val      ),
    .field_data      ( pkt_length          ),
    .match_en        ( pkt_length_en       ),
    .field_relation  ( field_relation),
    .match_mode      ( pkt_length_mode     ),
    .match_mask      ( pkt_length_mask     ),
    .match_value     ( pkt_length_value    ),
    .match_result    ( match_result_field[10]    )  
);



endmodule



module match_comparer_vlanid #(
    parameter DATA_WIDTH = 16
)
(
    input                           clk             ,
    input                           resetn          ,
    input                           vlanid1_valid   ,
    input       [DATA_WIDTH-1:0]    vlanid1_data    ,
    input                           vlanid2_valid   ,
    input       [DATA_WIDTH-1:0]    vlanid2_data    ,
    input                           field_relation  , //0:and, 1:or
    input                           match_en        ,
    input                           match_mode      , //0:equal, 1:not equal
    input       [DATA_WIDTH-1:0]    match_mask      ,
    input       [DATA_WIDTH-1:0]    match_value     ,
    output  reg                     match_result      //0:not match, 1:match
);

always @(posedge clk) begin
    if (!resetn) begin
        match_result <= 1'b0;
    end
    else if (!match_en) begin        
        if (field_relation) begin
            match_result <= 1'b0;
        end
        else begin
            match_result <= 1'b1;
        end
    end
    else begin
        if ((vlanid1_valid == 1'b0) && (vlanid2_valid == 1'b0)) begin
            match_result <= 1'b0;
        end
        else if ((vlanid1_valid == 1'b1) && (vlanid2_valid == 1'b0)) begin
            if (match_mode) begin
                match_result <= ((vlanid1_data & match_mask) != (match_value & match_mask)) ? 1'b1 : 1'b0;
            end
            else begin
                match_result <= ((vlanid1_data & match_mask) == (match_value & match_mask)) ? 1'b1 : 1'b0;
            end
        end
        else if ((vlanid1_valid == 1'b1) && (vlanid2_valid == 1'b1)) begin
            if (match_mode) begin
                match_result <= (((vlanid1_data & match_mask) != (match_value & match_mask)) && ((vlanid2_data & match_mask) != (match_value & match_mask))) ? 1'b1 : 1'b0;
            end
            else begin
                match_result <= (((vlanid1_data & match_mask) == (match_value & match_mask)) || ((vlanid2_data & match_mask) == (match_value & match_mask))) ? 1'b1 : 1'b0;
            end
        end
        else begin //((vlanid1_valid == 1'b0) && (vlanid2_valid == 1'b1))
            match_result <= 1'b0;
        end
    end
end

endmodule