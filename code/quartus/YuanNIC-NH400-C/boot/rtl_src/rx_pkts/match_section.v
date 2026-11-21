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

input       [511:0]     info            ,
input                   policy_vld      ,

output                  result_en       ,

input        [31:0]     dip             ,
input        [31:0]     sip             ,
input       [ 15:0]     dport           ,
input       [ 15:0]     sport           ,

input       [  7:0]     mask_dip        ,
input       [  7:0]     mask_sip        ,
input       [  3:0]     mask_field      ,
input                   mode            ,

input                   clk             ,   //
input                   resetn              //valid: low
);



wire    [15:0]  info_dip_1  ;
wire    [15:0]  info_dip_0  ;


wire    [15:0]  info_sip_1  ;
wire    [15:0]  info_sip_0  ;

wire     [15:0]  info_dport  ;
wire     [15:0]  info_sport  ;


wire            en_dip_1    ;
wire            en_dip_0    ;


wire            en_sip_1    ;
wire            en_sip_0    ;

wire            en_dport    ;
wire            en_sport    ;

// reg     [17:0]  result      ;
wire    [5:0]  result      ;

assign          info_dip_1 = info[511:496];
assign          info_dip_0 = info[495:480];


assign          info_sip_1 = info[383:368];
assign          info_sip_0 = info[367:352];

 
assign          info_dport = info[ 79: 64];
assign          info_sport = info[ 63: 48];


assign en_dip_1 = mask_field[2] & mask_dip[1];
assign en_dip_0 = mask_field[2] & mask_dip[0];

assign en_sip_1 = mask_field[3] & mask_sip[1];
assign en_sip_0 = mask_field[3] & mask_sip[0];

assign en_dport = mask_field[0];
assign en_sport = mask_field[1];

assign result_en = policy_vld ?  (mode ? &result : ~(&result)) : 1'b0;          //all field match

/*
match_comparer dip_7(

    .data               (info_dip_7         ),
    .result             (result[17]         ),

    .en                 (en_dip_7           ),
    .condition          (dip[127:112]       ),

    .clk                (clk                ),   //
    .resetn             (resetn             )    //valid: low
);

match_comparer dip_6(

    .data               (info_dip_6         ),
    .result             (result[16]         ),

    .en                 (en_dip_6           ),
    .condition          (dip[111: 96]       ),

    .clk                (clk                ),   //
    .resetn             (resetn             )    //valid: low
);

match_comparer dip_5(

    .data               (info_dip_5         ),
    .result             (result[15]         ),

    .en                 (en_dip_5           ),
    .condition          (dip[ 95: 80]       ),

    .clk                (clk                ),   //
    .resetn             (resetn             )    //valid: low
);

match_comparer dip_4(

    .data               (info_dip_4         ),
    .result             (result[14]         ),

    .en                 (en_dip_4           ),
    .condition          (dip[ 79: 64]       ),

    .clk                (clk                ),   //
    .resetn             (resetn             )    //valid: low
);

match_comparer dip_3(

    .data               (info_dip_3         ),
    .result             (result[13]         ),

    .en                 (en_dip_3           ),
    .condition          (dip[ 63: 48]       ),

    .clk                (clk                ),   //
    .resetn             (resetn             )    //valid: low
);

match_comparer dip_2(

    .data               (info_dip_2         ),
    .result             (result[12]         ),

    .en                 (en_dip_2           ),
    .condition          (dip[ 47: 32]       ),

    .clk                (clk                ),   //
    .resetn             (resetn             )    //valid: low
);
*/
match_comparer dip_1(

    .data               (info_dip_1         ),
    .result             (result[5]         ),

    .en                 (en_dip_1           ),
    .condition          (dip[ 31: 16]       ),

    .clk                (clk                ),   //
    .resetn             (resetn             )    //valid: low
);

match_comparer dip_0(

    .data               (info_dip_0         ),
    .result             (result[4]         ),

    .en                 (en_dip_0           ),
    .condition          (dip[ 15:  0]       ),

    .clk                (clk                ),   //
    .resetn             (resetn             )    //valid: low
);

/*
match_comparer sip_7(

    .data               (info_sip_7         ),
    .result             (result[ 9]         ),

    .en                 (en_sip_7           ),
    .condition          (sip[127:112]       ),

    .clk                (clk                ),   //
    .resetn             (resetn             )    //valid: low
);

match_comparer sip_6(

    .data               (info_sip_6         ),
    .result             (result[ 8]         ),

    .en                 (en_sip_6           ),
    .condition          (sip[111: 96]       ),

    .clk                (clk                ),   //
    .resetn             (resetn             )    //valid: low
);

match_comparer sip_5(

    .data               (info_sip_5         ),
    .result             (result[ 7]         ),

    .en                 (en_sip_5           ),
    .condition          (sip[ 95: 80]       ),

    .clk                (clk                ),   //
    .resetn             (resetn             )    //valid: low
);

match_comparer sip_4(

    .data               (info_sip_4         ),
    .result             (result[ 6]         ),

    .en                 (en_sip_4           ),
    .condition          (sip[ 79: 64]       ),

    .clk                (clk                ),   //
    .resetn             (resetn             )    //valid: low
);

match_comparer sip_3(

    .data               (info_sip_3         ),
    .result             (result[ 5]         ),

    .en                 (en_sip_3           ),
    .condition          (sip[ 63: 48]       ),

    .clk                (clk                ),   //
    .resetn             (resetn             )    //valid: low
);

match_comparer sip_2(

    .data               (info_sip_2         ),
    .result             (result[ 4]         ),

    .en                 (en_sip_2           ),
    .condition          (sip[ 47: 32]       ),

    .clk                (clk                ),   //
    .resetn             (resetn             )    //valid: low
);
*/
match_comparer sip_1(

    .data               (info_sip_1         ),
    .result             (result[ 3]         ),

    .en                 (en_sip_1           ),
    .condition          (sip[ 31: 16]       ),

    .clk                (clk                ),   //
    .resetn             (resetn             )    //valid: low
);

match_comparer sip_0(

    .data               (info_sip_0         ),
    .result             (result[ 2]         ),

    .en                 (en_sip_0           ),
    .condition          (sip[ 15:  0]       ),

    .clk                (clk                ),   //
    .resetn             (resetn             )    //valid: low
);


match_comparer dport_0(

    .data               (info_dport         ),
    .result             (result[ 1]         ),

    .en                 (en_dport           ),
    .condition          (dport              ),

    .clk                (clk                ),   //
    .resetn             (resetn             )    //valid: low
);

match_comparer sport_0(

    .data               (info_sport         ),
    .result             (result[ 0]         ),

    .en                 (en_sport           ),
    .condition          (sport              ),

    .clk                (clk                ),   //
    .resetn             (resetn             )    //valid: low
);



endmodule
