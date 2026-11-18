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
module timestamp_calc#(
    parameter       DATA_W          = 1024,
    parameter       KEEP_W          = $clog2(DATA_W/8)
)
(
    input                           start,
    input                           rocev2_flag,
    input           [63:0]          loc_time_stamp, 
    input           [31:0]          timestamp_delay_value,
    input           [DATA_W-1:0]    p_axis_tdata,
    input           [DATA_W-1:0]    p_axis_tdata_pre,
    input           [KEEP_W-1:0]    p_axis_tkeep,
    output                          timestamp_valid,
    output          [63:0]          timestamp_delay,
    output  reg     [15:0]          stream_id,
    output  reg     [15:0]          stream_value,
    output  reg                     rocev2_timestamp_vld,
    output  reg     [63:0]          rocev2_timestamp_value,
    input                           aclk,
    input                           aresetn
);


    reg     [31:0]                  rx_stream_id;
    reg     [63:0]                  timestamp_value;
    reg     [63:0]                  rx_timestamp;
    reg     [63:0]                  loc_cnt;
    reg                             timestamp_vld;
    reg     [63:0]                  rocev2_timestamp;
    reg                             update_flag;
    reg                             update_prog;
    reg                             update_prog_d1;
    reg                             update_prog_d2;
    reg                             update_prog_d3;
    reg     [4:0]                   time_stamp_pop;
    reg     [1:0]                   loc_cnt_pop;
    wire    [63:0]                  rx_time_stamp_conv;
    wire    [63:0]                  loc_cnt_conv;
    reg                             start_d1;
    reg     [63:0]                  loc_time_stamp_d1;

    assign timestamp_delay = timestamp_value;
    assign timestamp_valid = timestamp_vld;
    always @(posedge aclk) begin
        if (!aresetn) begin
            rx_timestamp <= 64'b0;
            rx_stream_id <= 32'd0;
        end else if(start)begin
            case (p_axis_tkeep)
                7'd000:begin rocev2_timestamp <= p_axis_tdata[004*8+:64];rx_timestamp <= p_axis_tdata[000*8+:64];rx_stream_id <= p_axis_tdata[012*8 +:32];end  
                7'd127:begin rocev2_timestamp <= p_axis_tdata[005*8+:64];rx_timestamp <= p_axis_tdata[001*8+:64];rx_stream_id <= p_axis_tdata[013*8 +:32];end  
                7'd126:begin rocev2_timestamp <= p_axis_tdata[006*8+:64];rx_timestamp <= p_axis_tdata[002*8+:64];rx_stream_id <= p_axis_tdata[014*8 +:32];end  
                7'd125:begin rocev2_timestamp <= p_axis_tdata[007*8+:64];rx_timestamp <= p_axis_tdata[003*8+:64];rx_stream_id <= p_axis_tdata[015*8 +:32];end  
                7'd124:begin rocev2_timestamp <= p_axis_tdata[008*8+:64];rx_timestamp <= p_axis_tdata[004*8+:64];rx_stream_id <= p_axis_tdata[016*8 +:32];end  
                7'd123:begin rocev2_timestamp <= p_axis_tdata[009*8+:64];rx_timestamp <= p_axis_tdata[005*8+:64];rx_stream_id <= p_axis_tdata[017*8 +:32];end  
                7'd122:begin rocev2_timestamp <= p_axis_tdata[010*8+:64];rx_timestamp <= p_axis_tdata[006*8+:64];rx_stream_id <= p_axis_tdata[018*8 +:32];end  
                7'd121:begin rocev2_timestamp <= p_axis_tdata[011*8+:64];rx_timestamp <= p_axis_tdata[007*8+:64];rx_stream_id <= p_axis_tdata[019*8 +:32];end  
                7'd120:begin rocev2_timestamp <= p_axis_tdata[012*8+:64];rx_timestamp <= p_axis_tdata[008*8+:64];rx_stream_id <= p_axis_tdata[020*8 +:32];end  
                7'd119:begin rocev2_timestamp <= p_axis_tdata[013*8+:64];rx_timestamp <= p_axis_tdata[009*8+:64];rx_stream_id <= p_axis_tdata[021*8 +:32];end  
                7'd118:begin rocev2_timestamp <= p_axis_tdata[014*8+:64];rx_timestamp <= p_axis_tdata[010*8+:64];rx_stream_id <= p_axis_tdata[022*8 +:32];end  
                7'd117:begin rocev2_timestamp <= p_axis_tdata[015*8+:64];rx_timestamp <= p_axis_tdata[011*8+:64];rx_stream_id <= p_axis_tdata[023*8 +:32];end  
                7'd116:begin rocev2_timestamp <= p_axis_tdata[016*8+:64];rx_timestamp <= p_axis_tdata[012*8+:64];rx_stream_id <= p_axis_tdata[024*8 +:32];end  
                7'd115:begin rocev2_timestamp <= p_axis_tdata[017*8+:64];rx_timestamp <= p_axis_tdata[013*8+:64];rx_stream_id <= p_axis_tdata[025*8 +:32];end  
                7'd114:begin rocev2_timestamp <= p_axis_tdata[018*8+:64];rx_timestamp <= p_axis_tdata[014*8+:64];rx_stream_id <= p_axis_tdata[026*8 +:32];end  
                7'd113:begin rocev2_timestamp <= p_axis_tdata[019*8+:64];rx_timestamp <= p_axis_tdata[015*8+:64];rx_stream_id <= p_axis_tdata[027*8 +:32];end  
                7'd112:begin rocev2_timestamp <= p_axis_tdata[020*8+:64];rx_timestamp <= p_axis_tdata[016*8+:64];rx_stream_id <= p_axis_tdata[028*8 +:32];end  
                7'd111:begin rocev2_timestamp <= p_axis_tdata[021*8+:64];rx_timestamp <= p_axis_tdata[017*8+:64];rx_stream_id <= p_axis_tdata[029*8 +:32];end  
                7'd110:begin rocev2_timestamp <= p_axis_tdata[022*8+:64];rx_timestamp <= p_axis_tdata[018*8+:64];rx_stream_id <= p_axis_tdata[030*8 +:32];end  
                7'd109:begin rocev2_timestamp <= p_axis_tdata[023*8+:64];rx_timestamp <= p_axis_tdata[019*8+:64];rx_stream_id <= p_axis_tdata[031*8 +:32];end  
                7'd108:begin rocev2_timestamp <= p_axis_tdata[024*8+:64];rx_timestamp <= p_axis_tdata[020*8+:64];rx_stream_id <= p_axis_tdata[032*8 +:32];end  
                7'd107:begin rocev2_timestamp <= p_axis_tdata[025*8+:64];rx_timestamp <= p_axis_tdata[021*8+:64];rx_stream_id <= p_axis_tdata[033*8 +:32];end  
                7'd106:begin rocev2_timestamp <= p_axis_tdata[026*8+:64];rx_timestamp <= p_axis_tdata[022*8+:64];rx_stream_id <= p_axis_tdata[034*8 +:32];end  
                7'd105:begin rocev2_timestamp <= p_axis_tdata[027*8+:64];rx_timestamp <= p_axis_tdata[023*8+:64];rx_stream_id <= p_axis_tdata[035*8 +:32];end  
                7'd104:begin rocev2_timestamp <= p_axis_tdata[028*8+:64];rx_timestamp <= p_axis_tdata[024*8+:64];rx_stream_id <= p_axis_tdata[036*8 +:32];end  
                7'd103:begin rocev2_timestamp <= p_axis_tdata[029*8+:64];rx_timestamp <= p_axis_tdata[025*8+:64];rx_stream_id <= p_axis_tdata[037*8 +:32];end  
                7'd102:begin rocev2_timestamp <= p_axis_tdata[030*8+:64];rx_timestamp <= p_axis_tdata[026*8+:64];rx_stream_id <= p_axis_tdata[038*8 +:32];end  
                7'd101:begin rocev2_timestamp <= p_axis_tdata[031*8+:64];rx_timestamp <= p_axis_tdata[027*8+:64];rx_stream_id <= p_axis_tdata[039*8 +:32];end  
                7'd100:begin rocev2_timestamp <= p_axis_tdata[032*8+:64];rx_timestamp <= p_axis_tdata[028*8+:64];rx_stream_id <= p_axis_tdata[040*8 +:32];end  
                7'd099:begin rocev2_timestamp <= p_axis_tdata[033*8+:64];rx_timestamp <= p_axis_tdata[029*8+:64];rx_stream_id <= p_axis_tdata[041*8 +:32];end  
                7'd098:begin rocev2_timestamp <= p_axis_tdata[034*8+:64];rx_timestamp <= p_axis_tdata[030*8+:64];rx_stream_id <= p_axis_tdata[042*8 +:32];end  
                7'd097:begin rocev2_timestamp <= p_axis_tdata[035*8+:64];rx_timestamp <= p_axis_tdata[031*8+:64];rx_stream_id <= p_axis_tdata[043*8 +:32];end  
                7'd096:begin rocev2_timestamp <= p_axis_tdata[036*8+:64];rx_timestamp <= p_axis_tdata[032*8+:64];rx_stream_id <= p_axis_tdata[044*8 +:32];end  
                7'd095:begin rocev2_timestamp <= p_axis_tdata[037*8+:64];rx_timestamp <= p_axis_tdata[033*8+:64];rx_stream_id <= p_axis_tdata[045*8 +:32];end  
                7'd094:begin rocev2_timestamp <= p_axis_tdata[038*8+:64];rx_timestamp <= p_axis_tdata[034*8+:64];rx_stream_id <= p_axis_tdata[046*8 +:32];end  
                7'd093:begin rocev2_timestamp <= p_axis_tdata[039*8+:64];rx_timestamp <= p_axis_tdata[035*8+:64];rx_stream_id <= p_axis_tdata[047*8 +:32];end  
                7'd092:begin rocev2_timestamp <= p_axis_tdata[040*8+:64];rx_timestamp <= p_axis_tdata[036*8+:64];rx_stream_id <= p_axis_tdata[048*8 +:32];end  
                7'd091:begin rocev2_timestamp <= p_axis_tdata[041*8+:64];rx_timestamp <= p_axis_tdata[037*8+:64];rx_stream_id <= p_axis_tdata[049*8 +:32];end  
                7'd090:begin rocev2_timestamp <= p_axis_tdata[042*8+:64];rx_timestamp <= p_axis_tdata[038*8+:64];rx_stream_id <= p_axis_tdata[050*8 +:32];end  
                7'd089:begin rocev2_timestamp <= p_axis_tdata[043*8+:64];rx_timestamp <= p_axis_tdata[039*8+:64];rx_stream_id <= p_axis_tdata[051*8 +:32];end  
                7'd088:begin rocev2_timestamp <= p_axis_tdata[044*8+:64];rx_timestamp <= p_axis_tdata[040*8+:64];rx_stream_id <= p_axis_tdata[052*8 +:32];end  
                7'd087:begin rocev2_timestamp <= p_axis_tdata[045*8+:64];rx_timestamp <= p_axis_tdata[041*8+:64];rx_stream_id <= p_axis_tdata[053*8 +:32];end  
                7'd086:begin rocev2_timestamp <= p_axis_tdata[046*8+:64];rx_timestamp <= p_axis_tdata[042*8+:64];rx_stream_id <= p_axis_tdata[054*8 +:32];end  
                7'd085:begin rocev2_timestamp <= p_axis_tdata[047*8+:64];rx_timestamp <= p_axis_tdata[043*8+:64];rx_stream_id <= p_axis_tdata[055*8 +:32];end  
                7'd084:begin rocev2_timestamp <= p_axis_tdata[048*8+:64];rx_timestamp <= p_axis_tdata[044*8+:64];rx_stream_id <= p_axis_tdata[056*8 +:32];end  
                7'd083:begin rocev2_timestamp <= p_axis_tdata[049*8+:64];rx_timestamp <= p_axis_tdata[045*8+:64];rx_stream_id <= p_axis_tdata[057*8 +:32];end  
                7'd082:begin rocev2_timestamp <= p_axis_tdata[050*8+:64];rx_timestamp <= p_axis_tdata[046*8+:64];rx_stream_id <= p_axis_tdata[058*8 +:32];end  
                7'd081:begin rocev2_timestamp <= p_axis_tdata[051*8+:64];rx_timestamp <= p_axis_tdata[047*8+:64];rx_stream_id <= p_axis_tdata[059*8 +:32];end  
                7'd080:begin rocev2_timestamp <= p_axis_tdata[052*8+:64];rx_timestamp <= p_axis_tdata[048*8+:64];rx_stream_id <= p_axis_tdata[060*8 +:32];end  
                7'd079:begin rocev2_timestamp <= p_axis_tdata[053*8+:64];rx_timestamp <= p_axis_tdata[049*8+:64];rx_stream_id <= p_axis_tdata[061*8 +:32];end  
                7'd078:begin rocev2_timestamp <= p_axis_tdata[054*8+:64];rx_timestamp <= p_axis_tdata[050*8+:64];rx_stream_id <= p_axis_tdata[062*8 +:32];end  
                7'd077:begin rocev2_timestamp <= p_axis_tdata[055*8+:64];rx_timestamp <= p_axis_tdata[051*8+:64];rx_stream_id <= p_axis_tdata[063*8 +:32];end  
                7'd076:begin rocev2_timestamp <= p_axis_tdata[056*8+:64];rx_timestamp <= p_axis_tdata[052*8+:64];rx_stream_id <= p_axis_tdata[064*8 +:32];end  
                7'd075:begin rocev2_timestamp <= p_axis_tdata[057*8+:64];rx_timestamp <= p_axis_tdata[053*8+:64];rx_stream_id <= p_axis_tdata[065*8 +:32];end  
                7'd074:begin rocev2_timestamp <= p_axis_tdata[058*8+:64];rx_timestamp <= p_axis_tdata[054*8+:64];rx_stream_id <= p_axis_tdata[066*8 +:32];end  
                7'd073:begin rocev2_timestamp <= p_axis_tdata[059*8+:64];rx_timestamp <= p_axis_tdata[055*8+:64];rx_stream_id <= p_axis_tdata[067*8 +:32];end  
                7'd072:begin rocev2_timestamp <= p_axis_tdata[060*8+:64];rx_timestamp <= p_axis_tdata[056*8+:64];rx_stream_id <= p_axis_tdata[068*8 +:32];end  
                7'd071:begin rocev2_timestamp <= p_axis_tdata[061*8+:64];rx_timestamp <= p_axis_tdata[057*8+:64];rx_stream_id <= p_axis_tdata[069*8 +:32];end  
                7'd070:begin rocev2_timestamp <= p_axis_tdata[062*8+:64];rx_timestamp <= p_axis_tdata[058*8+:64];rx_stream_id <= p_axis_tdata[070*8 +:32];end  
                7'd069:begin rocev2_timestamp <= p_axis_tdata[063*8+:64];rx_timestamp <= p_axis_tdata[059*8+:64];rx_stream_id <= p_axis_tdata[071*8 +:32];end  
                7'd068:begin rocev2_timestamp <= p_axis_tdata[064*8+:64];rx_timestamp <= p_axis_tdata[060*8+:64];rx_stream_id <= p_axis_tdata[072*8 +:32];end  
                7'd067:begin rocev2_timestamp <= p_axis_tdata[065*8+:64];rx_timestamp <= p_axis_tdata[061*8+:64];rx_stream_id <= p_axis_tdata[073*8 +:32];end  
                7'd066:begin rocev2_timestamp <= p_axis_tdata[066*8+:64];rx_timestamp <= p_axis_tdata[062*8+:64];rx_stream_id <= p_axis_tdata[074*8 +:32];end  
                7'd065:begin rocev2_timestamp <= p_axis_tdata[067*8+:64];rx_timestamp <= p_axis_tdata[063*8+:64];rx_stream_id <= p_axis_tdata[075*8 +:32];end  
                7'd064:begin rocev2_timestamp <= p_axis_tdata[068*8+:64];rx_timestamp <= p_axis_tdata[064*8+:64];rx_stream_id <= p_axis_tdata[076*8 +:32];end  
                7'd063:begin rocev2_timestamp <= p_axis_tdata[069*8+:64];rx_timestamp <= p_axis_tdata[065*8+:64];rx_stream_id <= p_axis_tdata[077*8 +:32];end  
                7'd062:begin rocev2_timestamp <= p_axis_tdata[070*8+:64];rx_timestamp <= p_axis_tdata[066*8+:64];rx_stream_id <= p_axis_tdata[078*8 +:32];end  
                7'd061:begin rocev2_timestamp <= p_axis_tdata[071*8+:64];rx_timestamp <= p_axis_tdata[067*8+:64];rx_stream_id <= p_axis_tdata[079*8 +:32];end  
                7'd060:begin rocev2_timestamp <= p_axis_tdata[072*8+:64];rx_timestamp <= p_axis_tdata[068*8+:64];rx_stream_id <= p_axis_tdata[080*8 +:32];end  
                7'd059:begin rocev2_timestamp <= p_axis_tdata[073*8+:64];rx_timestamp <= p_axis_tdata[069*8+:64];rx_stream_id <= p_axis_tdata[081*8 +:32];end  
                7'd058:begin rocev2_timestamp <= p_axis_tdata[074*8+:64];rx_timestamp <= p_axis_tdata[070*8+:64];rx_stream_id <= p_axis_tdata[082*8 +:32];end  
                7'd057:begin rocev2_timestamp <= p_axis_tdata[075*8+:64];rx_timestamp <= p_axis_tdata[071*8+:64];rx_stream_id <= p_axis_tdata[083*8 +:32];end  
                7'd056:begin rocev2_timestamp <= p_axis_tdata[076*8+:64];rx_timestamp <= p_axis_tdata[072*8+:64];rx_stream_id <= p_axis_tdata[084*8 +:32];end  
                7'd055:begin rocev2_timestamp <= p_axis_tdata[077*8+:64];rx_timestamp <= p_axis_tdata[073*8+:64];rx_stream_id <= p_axis_tdata[085*8 +:32];end  
                7'd054:begin rocev2_timestamp <= p_axis_tdata[078*8+:64];rx_timestamp <= p_axis_tdata[074*8+:64];rx_stream_id <= p_axis_tdata[086*8 +:32];end  
                7'd053:begin rocev2_timestamp <= p_axis_tdata[079*8+:64];rx_timestamp <= p_axis_tdata[075*8+:64];rx_stream_id <= p_axis_tdata[087*8 +:32];end  
                7'd052:begin rocev2_timestamp <= p_axis_tdata[080*8+:64];rx_timestamp <= p_axis_tdata[076*8+:64];rx_stream_id <= p_axis_tdata[088*8 +:32];end  
                7'd051:begin rocev2_timestamp <= p_axis_tdata[081*8+:64];rx_timestamp <= p_axis_tdata[077*8+:64];rx_stream_id <= p_axis_tdata[089*8 +:32];end  
                7'd050:begin rocev2_timestamp <= p_axis_tdata[082*8+:64];rx_timestamp <= p_axis_tdata[078*8+:64];rx_stream_id <= p_axis_tdata[090*8 +:32];end  
                7'd049:begin rocev2_timestamp <= p_axis_tdata[083*8+:64];rx_timestamp <= p_axis_tdata[079*8+:64];rx_stream_id <= p_axis_tdata[091*8 +:32];end  
                7'd048:begin rocev2_timestamp <= p_axis_tdata[084*8+:64];rx_timestamp <= p_axis_tdata[080*8+:64];rx_stream_id <= p_axis_tdata[092*8 +:32];end  
                7'd047:begin rocev2_timestamp <= p_axis_tdata[085*8+:64];rx_timestamp <= p_axis_tdata[081*8+:64];rx_stream_id <= p_axis_tdata[093*8 +:32];end  
                7'd046:begin rocev2_timestamp <= p_axis_tdata[086*8+:64];rx_timestamp <= p_axis_tdata[082*8+:64];rx_stream_id <= p_axis_tdata[094*8 +:32];end  
                7'd045:begin rocev2_timestamp <= p_axis_tdata[087*8+:64];rx_timestamp <= p_axis_tdata[083*8+:64];rx_stream_id <= p_axis_tdata[095*8 +:32];end  
                7'd044:begin rocev2_timestamp <= p_axis_tdata[088*8+:64];rx_timestamp <= p_axis_tdata[084*8+:64];rx_stream_id <= p_axis_tdata[096*8 +:32];end  
                7'd043:begin rocev2_timestamp <= p_axis_tdata[089*8+:64];rx_timestamp <= p_axis_tdata[085*8+:64];rx_stream_id <= p_axis_tdata[097*8 +:32];end  
                7'd042:begin rocev2_timestamp <= p_axis_tdata[090*8+:64];rx_timestamp <= p_axis_tdata[086*8+:64];rx_stream_id <= p_axis_tdata[098*8 +:32];end  
                7'd041:begin rocev2_timestamp <= p_axis_tdata[091*8+:64];rx_timestamp <= p_axis_tdata[087*8+:64];rx_stream_id <= p_axis_tdata[099*8 +:32];end  
                7'd040:begin rocev2_timestamp <= p_axis_tdata[092*8+:64];rx_timestamp <= p_axis_tdata[088*8+:64];rx_stream_id <= p_axis_tdata[100*8 +:32];end  
                7'd039:begin rocev2_timestamp <= p_axis_tdata[093*8+:64];rx_timestamp <= p_axis_tdata[089*8+:64];rx_stream_id <= p_axis_tdata[101*8 +:32];end  
                7'd038:begin rocev2_timestamp <= p_axis_tdata[094*8+:64];rx_timestamp <= p_axis_tdata[090*8+:64];rx_stream_id <= p_axis_tdata[102*8 +:32];end  
                7'd037:begin rocev2_timestamp <= p_axis_tdata[095*8+:64];rx_timestamp <= p_axis_tdata[091*8+:64];rx_stream_id <= p_axis_tdata[103*8 +:32];end  
                7'd036:begin rocev2_timestamp <= p_axis_tdata[096*8+:64];rx_timestamp <= p_axis_tdata[092*8+:64];rx_stream_id <= p_axis_tdata[104*8 +:32];end  
                7'd035:begin rocev2_timestamp <= p_axis_tdata[097*8+:64];rx_timestamp <= p_axis_tdata[093*8+:64];rx_stream_id <= p_axis_tdata[105*8 +:32];end  
                7'd034:begin rocev2_timestamp <= p_axis_tdata[098*8+:64];rx_timestamp <= p_axis_tdata[094*8+:64];rx_stream_id <= p_axis_tdata[106*8 +:32];end  
                7'd033:begin rocev2_timestamp <= p_axis_tdata[099*8+:64];rx_timestamp <= p_axis_tdata[095*8+:64];rx_stream_id <= p_axis_tdata[107*8 +:32];end  
                7'd032:begin rocev2_timestamp <= p_axis_tdata[100*8+:64];rx_timestamp <= p_axis_tdata[096*8+:64];rx_stream_id <= p_axis_tdata[108*8 +:32];end  
                7'd031:begin rocev2_timestamp <= p_axis_tdata[101*8+:64];rx_timestamp <= p_axis_tdata[097*8+:64];rx_stream_id <= p_axis_tdata[109*8 +:32];end  
                7'd030:begin rocev2_timestamp <= p_axis_tdata[102*8+:64];rx_timestamp <= p_axis_tdata[098*8+:64];rx_stream_id <= p_axis_tdata[110*8 +:32];end  
                7'd029:begin rocev2_timestamp <= p_axis_tdata[103*8+:64];rx_timestamp <= p_axis_tdata[099*8+:64];rx_stream_id <= p_axis_tdata[111*8 +:32];end  
                7'd028:begin rocev2_timestamp <= p_axis_tdata[104*8+:64];rx_timestamp <= p_axis_tdata[100*8+:64];rx_stream_id <= p_axis_tdata[112*8 +:32];end  
                7'd027:begin rocev2_timestamp <= p_axis_tdata[105*8+:64];rx_timestamp <= p_axis_tdata[101*8+:64];rx_stream_id <= p_axis_tdata[113*8 +:32];end  
                7'd026:begin rocev2_timestamp <= p_axis_tdata[106*8+:64];rx_timestamp <= p_axis_tdata[102*8+:64];rx_stream_id <= p_axis_tdata[114*8 +:32];end  
                7'd025:begin rocev2_timestamp <= p_axis_tdata[107*8+:64];rx_timestamp <= p_axis_tdata[103*8+:64];rx_stream_id <= p_axis_tdata[115*8 +:32];end  
                7'd024:begin rocev2_timestamp <= p_axis_tdata[108*8+:64];rx_timestamp <= p_axis_tdata[104*8+:64];rx_stream_id <= p_axis_tdata[116*8 +:32];end  
                7'd023:begin rocev2_timestamp <= p_axis_tdata[109*8+:64];rx_timestamp <= p_axis_tdata[105*8+:64];rx_stream_id <= p_axis_tdata[117*8 +:32];end  
                7'd022:begin rocev2_timestamp <= p_axis_tdata[110*8+:64];rx_timestamp <= p_axis_tdata[106*8+:64];rx_stream_id <= p_axis_tdata[118*8 +:32];end  
                7'd021:begin rocev2_timestamp <= p_axis_tdata[111*8+:64];rx_timestamp <= p_axis_tdata[107*8+:64];rx_stream_id <= p_axis_tdata[119*8 +:32];end  
                7'd020:begin rocev2_timestamp <= p_axis_tdata[112*8+:64];rx_timestamp <= p_axis_tdata[108*8+:64];rx_stream_id <= p_axis_tdata[120*8 +:32];end  
                7'd019:begin rocev2_timestamp <= p_axis_tdata[113*8+:64];rx_timestamp <= p_axis_tdata[109*8+:64];rx_stream_id <= p_axis_tdata[121*8 +:32];end  
                7'd018:begin rocev2_timestamp <= p_axis_tdata[114*8+:64];rx_timestamp <= p_axis_tdata[110*8+:64];rx_stream_id <= p_axis_tdata[122*8 +:32];end  
                7'd017:begin rocev2_timestamp <= p_axis_tdata[115*8+:64];rx_timestamp <= p_axis_tdata[111*8+:64];rx_stream_id <= p_axis_tdata[123*8 +:32];end  
                7'd016:begin rocev2_timestamp <= p_axis_tdata[116*8+:64];rx_timestamp <= p_axis_tdata[112*8+:64];rx_stream_id <= p_axis_tdata[124*8 +:32];end  
                7'd015:begin rocev2_timestamp <= p_axis_tdata[117*8+:64];rx_timestamp <= p_axis_tdata[113*8+:64];rx_stream_id <= {p_axis_tdata_pre[0*8+:08],p_axis_tdata[125*8 +:24]};end  
                7'd014:begin rocev2_timestamp <= p_axis_tdata[118*8+:64];rx_timestamp <= p_axis_tdata[114*8+:64];rx_stream_id <= {p_axis_tdata_pre[0*8+:16],p_axis_tdata[126*8 +:16]};end  
                7'd013:begin rocev2_timestamp <= p_axis_tdata[119*8+:64];rx_timestamp <= p_axis_tdata[115*8+:64];rx_stream_id <= {p_axis_tdata_pre[0*8+:24],p_axis_tdata[127*8 +:08]};end  
                7'd012:begin rocev2_timestamp <= p_axis_tdata[120*8+:64];rx_timestamp <= p_axis_tdata[116*8+:64];rx_stream_id <= p_axis_tdata_pre[000*8 +:32];end  
                7'd011:begin rocev2_timestamp <= {p_axis_tdata_pre[0*8+:08],p_axis_tdata[121*8+:56]};rx_timestamp <= p_axis_tdata[117*8+:64];rx_stream_id <= p_axis_tdata_pre[001*8 +:32];end
                7'd010:begin rocev2_timestamp <= {p_axis_tdata_pre[0*8+:16],p_axis_tdata[122*8+:48]};rx_timestamp <= p_axis_tdata[118*8+:64];rx_stream_id <= p_axis_tdata_pre[002*8 +:32];end
                7'd009:begin rocev2_timestamp <= {p_axis_tdata_pre[0*8+:24],p_axis_tdata[123*8+:40]};rx_timestamp <= p_axis_tdata[119*8+:64];rx_stream_id <= p_axis_tdata_pre[003*8 +:32];end
                7'd008:begin rocev2_timestamp <= {p_axis_tdata_pre[0*8+:32],p_axis_tdata[124*8+:32]};rx_timestamp <= p_axis_tdata[120*8+:64];rx_stream_id <= p_axis_tdata_pre[004*8 +:32];end
                7'd007:begin rocev2_timestamp <= {p_axis_tdata_pre[0*8+:40],p_axis_tdata[125*8+:24]};rx_timestamp <= {p_axis_tdata_pre[0*8+:08],p_axis_tdata[121*8+:56]};rx_stream_id <= p_axis_tdata_pre[005*8 +:32];end
                7'd006:begin rocev2_timestamp <= {p_axis_tdata_pre[0*8+:48],p_axis_tdata[126*8+:16]};rx_timestamp <= {p_axis_tdata_pre[0*8+:16],p_axis_tdata[122*8+:48]};rx_stream_id <= p_axis_tdata_pre[006*8 +:32];end
                7'd005:begin rocev2_timestamp <= {p_axis_tdata_pre[0*8+:56],p_axis_tdata[127*8+:08]};rx_timestamp <= {p_axis_tdata_pre[0*8+:24],p_axis_tdata[123*8+:40]};rx_stream_id <= p_axis_tdata_pre[007*8 +:32];end
                7'd004:begin rocev2_timestamp <= p_axis_tdata[000*8+:64];rx_timestamp <= {p_axis_tdata_pre[0*8+:32],p_axis_tdata[124*8+:32]};rx_stream_id <= p_axis_tdata_pre[008*8 +:32];end  
                7'd003:begin rocev2_timestamp <= p_axis_tdata[001*8+:64];rx_timestamp <= {p_axis_tdata_pre[0*8+:40],p_axis_tdata[125*8+:24]};rx_stream_id <= p_axis_tdata_pre[009*8 +:32];end  
                7'd002:begin rocev2_timestamp <= p_axis_tdata[002*8+:64];rx_timestamp <= {p_axis_tdata_pre[0*8+:48],p_axis_tdata[126*8+:16]};rx_stream_id <= p_axis_tdata_pre[010*8 +:32];end  
                7'd001:begin rocev2_timestamp <= p_axis_tdata[003*8+:64];rx_timestamp <= {p_axis_tdata_pre[0*8+:56],p_axis_tdata[127*8+:8]};rx_stream_id <= p_axis_tdata_pre[011*8 +:32];end  
            endcase
        end  
    end
 
    always @(posedge aclk ) begin
        start_d1            <= start;
        stream_id           <= rx_stream_id[31:16];
        stream_value        <= rx_stream_id[15:0];
        loc_time_stamp_d1   <= loc_time_stamp;

        if(loc_time_stamp_d1 > rx_timestamp)
            timestamp_value <= loc_time_stamp_d1-rx_timestamp;
        else
            timestamp_value <= 64'b0;

        if(start_d1)
            timestamp_vld   <= 1'b1;
        else
            timestamp_vld   <= 1'b0;
    end

    always @(posedge aclk) begin
        if(loc_time_stamp_d1 > rocev2_timestamp)
            rocev2_timestamp_value <= loc_time_stamp_d1 - rocev2_timestamp;
        else
            rocev2_timestamp_value <= 64'b0;

        if(start_d1 && rocev2_flag && loc_time_stamp_d1 > rocev2_timestamp)
            rocev2_timestamp_vld <= 1'b1;
        else 
            rocev2_timestamp_vld <= 1'b0;
    end  


endmodule	      
