
//`timescale 1ns / 1ps
//`define     UDLY                1

//`include "global_define.v"
module i2c_core_v1 #(
        parameter DONE_WAIT_TIME = 18'd1500,
        parameter CLK_PERIOD= 12'd250

)
        (
                Clk                 ,
                Rst                 ,

                I2cSirSel           ,
                I2cSirRead          ,
                I2cSirAddr          ,
                I2cSirWdat          ,
                I2cSirRdat          ,
                I2cSirDackh         ,
                I2cSirDone          ,
                I2cDateLen          ,
                I2cChipAddr         ,
                I2cMode             ,

				scl_out_z           ,
				scl_in              ,
				sda_out_z           ,
				sda_in
                );
input   wire            Clk                 ;
input   wire            Rst                 ;

input                   I2cSirSel           ;
input                   I2cSirRead          ;
input           [63:0]  I2cSirAddr          ;
input           [127:0] I2cSirWdat          ;
output          [127:0] I2cSirRdat          ;
output                  I2cSirDackh         ;
output                  I2cSirDone          ;
input           [4:0]   I2cDateLen          ;
input           [6:0]   I2cChipAddr         ;
input           [3:0]   I2cMode             ;

output                  scl_out_z           ;
input                   scl_in              ;

output                  sda_out_z           ;
input                   sda_in              ;


reg     [127:0] I2cSirRdat          ;
reg             I2cSirDackh         ;
reg             I2cSirDone          ;

reg             lock_i2c_sir_Read   ;
reg     [63:0]  lock_i2c_sir_addr   ;
reg     [127:0] lock_i2c_sir_wdat   ;
reg     [4:0]   lock_i2c_date_len   ;
reg     [6:0]   lock_i2c_chip_addr  ;
reg     [3:0]   lock_i2c_mode       ;


reg             scl_out_z           ;
wire            scl_in              ;
reg             sda_out_z_i         ;
wire            sda_in              ;
reg				sda_t				;


reg	[5:0]   main_state             ;

/********************************************************************\
*                                                                    *
*                      Delay I2cSirDackh                             *
*                                                                    *
\********************************************************************/
reg     I2cSirDackhL1;
always@(posedge Clk or posedge Rst)
begin
    if(Rst)
        I2cSirDackhL1 <= 1'h0;
    else
        I2cSirDackhL1 <= I2cSirDackh;
end

/********************************************************************\
*                                                                    *
*                      Delay I2cSirDone                            *
*                                                                    *
\********************************************************************/
reg [17:0]  cnt_done        ;
reg         dd          ;
reg         I2cSirDone_r;
reg         I2cSirDone_r1;
reg         I2cSirDone_r2;

/********************************************************************\
*                                                                    *
*                       Main FSM                                     *
*                                                                    *
\********************************************************************/

localparam  idle                =6'h00,
            start               =6'h01,
            device_addr_w       =6'h02,
            device_addr_wack    =6'h03,
            reg_addr0           =6'h04,
            reg_addr_ack0       =6'h05,
            reg_addr1           =6'h06,
            reg_addr_ack1       =6'h07,
            reg_addr2           =6'h08,
            reg_addr_ack2       =6'h09,
            reg_addr3           =6'h0A,
            reg_addr_ack3       =6'h0B,
            reg_addr4           =6'h0C,
            reg_addr_ack4       =6'h0D,
            reg_addr5           =6'h0E,
            reg_addr_ack5       =6'h0F,
            reg_addr6           =6'h10,
            reg_addr_ack6       =6'h11,
            reg_addr7           =6'h12,
            reg_addr_ack7       =6'h13,
            restart             =6'h14,
            device_addr_r       =6'h15,
            device_addr_rack    =6'h16,
            read_byte0          =6'h17,
            read_byte_ack0      =6'h18,
            read_byte1          =6'h19,
            read_byte_ack1      =6'h1A,
            read_byte2          =6'h1B,
            read_byte_ack2      =6'h1C,
            read_byte3          =6'h1D,
            read_byte_ack3      =6'h1E,
            read_byte4          =6'h1F,
            read_byte_ack4      =6'h20,
            read_byte5          =6'h21,
            read_byte_ack5      =6'h22,
            read_byte6          =6'h23,
            read_byte_ack6      =6'h24,
            read_byte7          =6'h25,
            read_byte_ack7      =6'h26,
            read_byte8          =6'h27,
            read_byte_ack8      =6'h28,
            read_byte9          =6'h29,
            read_byte_ack9      =6'h2A,
            read_byte10         =6'h2B,
            read_byte_ack10     =6'h2C,
            read_byte11         =6'h2D,
            read_byte_ack11     =6'h2E,
            read_byte12         =6'h2F,
            read_byte_ack12     =6'h30,
            read_byte13         =6'h31,
            read_byte_ack13     =6'h32,
            read_byte14         =6'h33,
            read_byte_ack14     =6'h34,
            read_byte15         =6'h35,
            read_byte_ack15     =6'h36,
            stop                =6'h37,
            finish              =6'h38;

assign sda_out_z = sda_out_z_i || sda_t;
always @(posedge Clk)
begin
	case(main_state)
		idle               ,
		start              ,
		device_addr_w      ,
		reg_addr0          ,
		reg_addr1          ,
		reg_addr2          ,
		reg_addr3          ,
		reg_addr4          ,
		reg_addr5          ,
		reg_addr6          ,
		reg_addr7          :  sda_t <= 1'b0;
		restart            :  sda_t <= 1'b0;
		device_addr_r      :  sda_t <= 1'b0;
		stop               :  sda_t <= 1'b0;
		finish             :  sda_t <= 1'b0;
		device_addr_wack   ,
		reg_addr_ack0      ,
		reg_addr_ack1      ,
		reg_addr_ack2      ,
		reg_addr_ack3      ,
		reg_addr_ack4      ,
		reg_addr_ack5      ,
		reg_addr_ack6      ,
		reg_addr_ack7      ,
		device_addr_rack   :  sda_t <= 1'b1;
		read_byte0         ,
		read_byte1         ,
		read_byte2         ,
		read_byte3         ,
		read_byte4         ,
		read_byte5         ,
		read_byte6         ,
		read_byte7         ,
		read_byte8         ,
		read_byte9         ,
		read_byte10        ,
		read_byte11        ,
		read_byte12        ,
		read_byte13        ,
		read_byte14        ,
		read_byte15        :  sda_t <= lock_i2c_sir_Read;
		read_byte_ack0     ,
		read_byte_ack1     ,
		read_byte_ack2     ,
		read_byte_ack3     ,
		read_byte_ack4     ,
		read_byte_ack5     ,
		read_byte_ack6     ,
		read_byte_ack7     ,
		read_byte_ack8     ,
		read_byte_ack9     ,
		read_byte_ack10    ,
		read_byte_ack11    ,
		read_byte_ack12    ,
		read_byte_ack13    ,
		read_byte_ack14    :  sda_t <= ~lock_i2c_sir_Read;
		read_byte_ack15    :  sda_t <= 1'b1;
		default :   		  sda_t <= 1'b1;
	endcase
end

//always@(posedge Clk or posedge Rst)
//begin
//    if(Rst)	begin
//        I2cSirDone_r2 <= 1'b0;
//        I2cSirDone_r1 <= 1'b0;
//    end
//    else    begin
//        I2cSirDone_r1 <= I2cSirDone_r;
//        I2cSirDone_r2 <= I2cSirDone_r1;
//    end
//end

//always@(posedge Clk or posedge Rst)
//begin
//    if(Rst)
//    begin
//        cnt_done <=	18'h0;
//        dd <= 1'b0;
//    end
//    else
//    begin
//    if(I2cSirDone_r1 == 1'b1 && I2cSirDone_r2 == 1'b0)	begin
//        dd <= 1'b1;
//        cnt_done <=	18'h0;
//    end
//    else if(cnt_done == 18'h249f0)	begin
//        dd <= 1'b0;
//        cnt_done <=	18'h0;
//    end
//    else if(dd == 1'b1)
//        cnt_done <= cnt_done + 18'h1;
//    else
//        cnt_done <= cnt_done;
//     end
//end


//always@(posedge Clk or posedge Rst)
//begin
//    if(Rst)
//        I2cSirDone_r <= 1'b0;
//    else
//    begin
//        if(main_state == finish)
//            I2cSirDone_r <= 1'b1;
//        else if(main_state == start)
//            I2cSirDone_r <= 1'b0;
//        else;

//    end
//end


//always@(posedge Clk or posedge Rst)
//begin
//    if(Rst)
//        I2cSirDone <= 1'b0;
//    else    begin
//        if(I2cSirDone_r1 == 1'b0 && I2cSirDone_r2 == 1'b1)
//            I2cSirDone <= 1'b0;
//        else if(cnt_done == 18'h249f0)
//            I2cSirDone <= 1'b1;
//        else
//            I2cSirDone <= I2cSirDone;
//    end
//end

always@(posedge Clk,posedge Rst)
begin
    if(Rst)
    begin
        cnt_done <=	18'h0;
        I2cSirDone <= 1'b0 ;
    end
    else
    begin
    if(main_state != idle)begin
        cnt_done <=	18'h0;
        I2cSirDone <= 1'b0 ;
    end
    else if(cnt_done < DONE_WAIT_TIME)	begin
        cnt_done <= cnt_done + 18'h1;
        I2cSirDone <= 1'b0 ;
    end
    else
        I2cSirDone <= 1'b1 ;
    end
end


//----------- Generate SCL ---------------------
localparam     CLK_PERIOD_S0    =    12'd0;
localparam     CLK_PERIOD_S1    =    CLK_PERIOD>>2;
localparam     CLK_PERIOD_S2    =    CLK_PERIOD>>1;
localparam     CLK_PERIOD_S3    =    CLK_PERIOD_S1 + CLK_PERIOD_S2;
localparam     BIT_NUM          =    3'b111;

reg [11:0]    clk_cnt;
reg  [2:0]    shift_cnt;

//--------------Parameter define----------------
localparam   ON                  = 1'b1;
localparam   OFF                 = 1'b0;

//-----------------FSM input lock  ------------------
always @(posedge Clk or posedge Rst)
begin
    if(Rst)
    begin
        lock_i2c_sir_Read  <= 1'b0;
        lock_i2c_sir_addr  <= 64'd0;
        lock_i2c_sir_wdat  <= 128'd0;
        lock_i2c_date_len  <= 5'd0;
        lock_i2c_chip_addr <= 7'd0;
        lock_i2c_mode      <= 4'd0;

    end
    else if(main_state == idle)
    begin
        lock_i2c_sir_Read  <= I2cSirRead;
        lock_i2c_sir_addr  <= I2cSirAddr;

        lock_i2c_date_len  <= I2cDateLen;
        lock_i2c_chip_addr <= I2cChipAddr;
        lock_i2c_mode      <= I2cMode;
        case(I2cDateLen)
        5'b00001:lock_i2c_sir_wdat  <= {120'd0,I2cSirWdat[7:0]};
        5'b00010:lock_i2c_sir_wdat  <= {112'd0,I2cSirWdat[7:0],I2cSirWdat[15:8]};
        5'b00011:lock_i2c_sir_wdat  <= {104'd0,I2cSirWdat[7:0],I2cSirWdat[15:8],I2cSirWdat[23:16]};
        5'b00100:lock_i2c_sir_wdat  <= { 96'd0,I2cSirWdat[7:0],I2cSirWdat[15:8],I2cSirWdat[23:16],I2cSirWdat[31:24]};
        5'b00101:lock_i2c_sir_wdat  <= { 88'd0,I2cSirWdat[7:0],I2cSirWdat[15:8],I2cSirWdat[23:16],I2cSirWdat[31:24],I2cSirWdat[39:32]};
        5'b00110:lock_i2c_sir_wdat  <= { 80'd0,I2cSirWdat[7:0],I2cSirWdat[15:8],I2cSirWdat[23:16],I2cSirWdat[31:24],I2cSirWdat[39:32],I2cSirWdat[47:40]};
        5'b00111:lock_i2c_sir_wdat  <= { 72'd0,I2cSirWdat[7:0],I2cSirWdat[15:8],I2cSirWdat[23:16],I2cSirWdat[31:24],I2cSirWdat[39:32],I2cSirWdat[47:40],I2cSirWdat[55:48]};
        5'b01000:lock_i2c_sir_wdat  <= { 64'd0,I2cSirWdat[7:0],I2cSirWdat[15:8],I2cSirWdat[23:16],I2cSirWdat[31:24],I2cSirWdat[39:32],I2cSirWdat[47:40],I2cSirWdat[55:48],I2cSirWdat[63:56]};
        5'b01001:lock_i2c_sir_wdat  <= { 56'd0,I2cSirWdat[7:0],I2cSirWdat[15:8],I2cSirWdat[23:16],I2cSirWdat[31:24],I2cSirWdat[39:32],I2cSirWdat[47:40],I2cSirWdat[55:48],I2cSirWdat[63:56],I2cSirWdat[71:64]};
        5'b01010:lock_i2c_sir_wdat  <= { 48'd0,I2cSirWdat[7:0],I2cSirWdat[15:8],I2cSirWdat[23:16],I2cSirWdat[31:24],I2cSirWdat[39:32],I2cSirWdat[47:40],I2cSirWdat[55:48],I2cSirWdat[63:56],I2cSirWdat[71:64],I2cSirWdat[79:72]};
        5'b01011:lock_i2c_sir_wdat  <= { 40'd0,I2cSirWdat[7:0],I2cSirWdat[15:8],I2cSirWdat[23:16],I2cSirWdat[31:24],I2cSirWdat[39:32],I2cSirWdat[47:40],I2cSirWdat[55:48],I2cSirWdat[63:56],I2cSirWdat[71:64],I2cSirWdat[79:72],I2cSirWdat[87:80]};
        5'b01100:lock_i2c_sir_wdat  <= { 32'd0,I2cSirWdat[7:0],I2cSirWdat[15:8],I2cSirWdat[23:16],I2cSirWdat[31:24],I2cSirWdat[39:32],I2cSirWdat[47:40],I2cSirWdat[55:48],I2cSirWdat[63:56],I2cSirWdat[71:64],I2cSirWdat[79:72],I2cSirWdat[87:80],I2cSirWdat[95:88]};
        5'b01101:lock_i2c_sir_wdat  <= { 24'd0,I2cSirWdat[7:0],I2cSirWdat[15:8],I2cSirWdat[23:16],I2cSirWdat[31:24],I2cSirWdat[39:32],I2cSirWdat[47:40],I2cSirWdat[55:48],I2cSirWdat[63:56],I2cSirWdat[71:64],I2cSirWdat[79:72],I2cSirWdat[87:80],I2cSirWdat[95:88],I2cSirWdat[103:96]};
        5'b01110:lock_i2c_sir_wdat  <= { 16'd0,I2cSirWdat[7:0],I2cSirWdat[15:8],I2cSirWdat[23:16],I2cSirWdat[31:24],I2cSirWdat[39:32],I2cSirWdat[47:40],I2cSirWdat[55:48],I2cSirWdat[63:56],I2cSirWdat[71:64],I2cSirWdat[79:72],I2cSirWdat[87:80],I2cSirWdat[95:88],I2cSirWdat[103:96],I2cSirWdat[111:104]};
        5'b01111:lock_i2c_sir_wdat  <= {  8'd0,I2cSirWdat[7:0],I2cSirWdat[15:8],I2cSirWdat[23:16],I2cSirWdat[31:24],I2cSirWdat[39:32],I2cSirWdat[47:40],I2cSirWdat[55:48],I2cSirWdat[63:56],I2cSirWdat[71:64],I2cSirWdat[79:72],I2cSirWdat[87:80],I2cSirWdat[95:88],I2cSirWdat[103:96],I2cSirWdat[111:104],I2cSirWdat[119:112]};
        default :lock_i2c_sir_wdat  <= {       I2cSirWdat[7:0],I2cSirWdat[15:8],I2cSirWdat[23:16],I2cSirWdat[31:24],I2cSirWdat[39:32],I2cSirWdat[47:40],I2cSirWdat[55:48],I2cSirWdat[63:56],I2cSirWdat[71:64],I2cSirWdat[79:72],I2cSirWdat[87:80],I2cSirWdat[95:88],I2cSirWdat[103:96],I2cSirWdat[111:104],I2cSirWdat[119:112],I2cSirWdat[127:120]};
        endcase
    end

    else;


end

//----------------- Main FSM  ------------------
always @(posedge Clk or posedge Rst)begin
    if (Rst) begin
        main_state  <= idle;
    end else begin
            case(main_state)
                idle:begin
                    if((I2cSirSel == 1'b1) && (I2cSirDackhL1 == 1'b0) && (I2cSirDackh == 1'b0))begin
                            main_state <=  start;
                    end else ;
                end
                start:begin
                    if(clk_cnt == CLK_PERIOD)
                            main_state <=  device_addr_w;
                    else;
                end
                device_addr_w:begin
                    if(clk_cnt == CLK_PERIOD && shift_cnt == BIT_NUM)
                            main_state <=  device_addr_wack;
                    else;
                end
                device_addr_wack:begin
                    if(clk_cnt == CLK_PERIOD)begin
                        case(lock_i2c_mode)
                            4'h0:begin//0B address
                                if(lock_i2c_sir_Read == 1'b0)begin//write
                                    case(lock_i2c_date_len)
                                        5'd0: main_state <=  stop ;
                                        5'd1: main_state <=  read_byte15;
                                        5'd2: main_state <=  read_byte14;
                                        5'd3: main_state <=  read_byte13;
                                        5'd4: main_state <=  read_byte12;
                                        5'd5: main_state <=  read_byte11;
                                        5'd6: main_state <=  read_byte10;
                                        5'd7: main_state <=  read_byte9;
                                        5'd8: main_state <=  read_byte8;
                                        5'd9: main_state <=  read_byte7;
                                        5'd10:main_state <=  read_byte6;
                                        5'd11:main_state <=  read_byte5;
                                        5'd12:main_state <=  read_byte4;
                                        5'd13:main_state <=  read_byte3;
                                        5'd14:main_state <=  read_byte2;
                                        5'd15:main_state <=  read_byte1;
                                        default:main_state <=  read_byte0;//16,other no support
                                    endcase
                                end else//read
                                    main_state <=  restart;//read operate
                            end
                            4'h1:main_state <=  reg_addr7;
                            4'h2:main_state <=  reg_addr6;
                            4'h3:main_state <=  reg_addr5;
                            4'h4:main_state <=  reg_addr4;
                            4'h5:main_state <=  reg_addr3;
                            4'h6:main_state <=  reg_addr2;
                            4'h7:main_state <=  reg_addr1;
                            default:main_state <=  reg_addr0;//8B address,other not support
                        endcase
                    end else;
                end
                reg_addr0:begin
                        if(clk_cnt == CLK_PERIOD && shift_cnt == BIT_NUM)
                               main_state <=  reg_addr_ack0;
                        else;
                end
                reg_addr_ack0: begin
                           if(clk_cnt == CLK_PERIOD)
                               main_state <=  reg_addr1;
                        else;
                end
                reg_addr1:begin
                        if(clk_cnt == CLK_PERIOD && shift_cnt == BIT_NUM)
                               main_state <=  reg_addr_ack1;
                        else;
                end
                reg_addr_ack1: begin
                        if(clk_cnt == CLK_PERIOD)
                               main_state <=  reg_addr2;
                        else;
                end
                reg_addr2:begin
                        if(clk_cnt == CLK_PERIOD && shift_cnt == BIT_NUM)
                               main_state <=  reg_addr_ack2;
                        else;
                end
                reg_addr_ack2: begin
                           if(clk_cnt == CLK_PERIOD)
                               main_state <=  reg_addr3;
                        else;
                end
                reg_addr3:begin
                        if(clk_cnt == CLK_PERIOD && shift_cnt == BIT_NUM)
                               main_state <=  reg_addr_ack3;
                        else;
                end
                reg_addr_ack3: begin
                           if(clk_cnt == CLK_PERIOD)
                               main_state <=  reg_addr4;
                        else;
                end
                reg_addr4:begin
                        if(clk_cnt == CLK_PERIOD && shift_cnt == BIT_NUM)
                               main_state <=  reg_addr_ack4;
                        else;
                end
                reg_addr_ack4: begin
                           if(clk_cnt == CLK_PERIOD)
                               main_state <=  reg_addr5;
                        else;
               end
               reg_addr5:begin
                        if(clk_cnt == CLK_PERIOD && shift_cnt == BIT_NUM)
                               main_state <=  reg_addr_ack5;
                        else;
               end
               reg_addr_ack5: begin
                           if(clk_cnt == CLK_PERIOD)
                               main_state <=  reg_addr6;
                        else;
               end
               reg_addr6:begin
                        if(clk_cnt == CLK_PERIOD && shift_cnt == BIT_NUM)
                               main_state <=  reg_addr_ack6;
                        else;
               end
               reg_addr_ack6: begin
                           if(clk_cnt == CLK_PERIOD)
                               main_state <=  reg_addr7;
                        else;
               end
               reg_addr7:begin
                        if(clk_cnt == CLK_PERIOD && shift_cnt == BIT_NUM)
                               main_state <=  reg_addr_ack7;
                        else;
               end
               reg_addr_ack7:begin
                        if(clk_cnt == CLK_PERIOD)begin
                            if(lock_i2c_sir_Read == 1'b0)begin//write
                                    case(lock_i2c_date_len)
                                        5'd0: main_state <=  stop;
                                        5'd1: main_state <=  read_byte15;
                                        5'd2: main_state <=  read_byte14;
                                        5'd3: main_state <=  read_byte13;
                                        5'd4: main_state <=  read_byte12;
                                        5'd5: main_state <=  read_byte11;
                                        5'd6: main_state <=  read_byte10;
                                        5'd7: main_state <=  read_byte9;
                                        5'd8: main_state <=  read_byte8;
                                        5'd9: main_state <=  read_byte7;
                                        5'd10:main_state <=  read_byte6;
                                        5'd11:main_state <=  read_byte5;
                                        5'd12:main_state <=  read_byte4;
                                        5'd13:main_state <=  read_byte3;
                                        5'd14:main_state <=  read_byte2;
                                        5'd15:main_state <=  read_byte1;
                                        default:main_state <=  read_byte0;
                                    endcase
                            end else begin//read
                                if ( lock_i2c_date_len == 5'd0 )
                                    main_state <=  stop;
                                else
                                    main_state <=  restart;//read operate
                            end
                        end else;
                end
                restart:begin//restart for read
                        if(clk_cnt == CLK_PERIOD)
                            main_state <=  device_addr_r;
                        else;
                end
                device_addr_r:begin//for read
                        if(clk_cnt == CLK_PERIOD && shift_cnt == BIT_NUM)
                            main_state <=  device_addr_rack;
                        else;
                    end
                device_addr_rack:begin//for read
                        if(clk_cnt == CLK_PERIOD)begin
                                    case(lock_i2c_date_len)
                                        5'd0: main_state <=  stop;
                                        5'd1: main_state <=  read_byte15;
                                        5'd2: main_state <=  read_byte14;
                                        5'd3: main_state <=  read_byte13;
                                        5'd4: main_state <=  read_byte12;
                                        5'd5: main_state <=  read_byte11;
                                        5'd6: main_state <=  read_byte10;
                                        5'd7: main_state <=  read_byte9;
                                        5'd8: main_state <=  read_byte8;
                                        5'd9: main_state <=  read_byte7;
                                        5'd10:main_state <=  read_byte6;
                                        5'd11:main_state <=  read_byte5;
                                        5'd12:main_state <=  read_byte4;
                                        5'd13:main_state <=  read_byte3;
                                        5'd14:main_state <=  read_byte2;
                                        5'd15:main_state <=  read_byte1;
                                        default:main_state <=  read_byte0;
                                    endcase
                        end else;
                    end
                read_byte0:begin
                        if(clk_cnt == CLK_PERIOD && shift_cnt == BIT_NUM)
                            main_state <= read_byte_ack0;
                        else;
                end
                read_byte_ack0:begin
                        if(clk_cnt == CLK_PERIOD)
                            main_state <= read_byte1;
                        else;
                end
                read_byte1:begin
                        if(clk_cnt == CLK_PERIOD && shift_cnt == BIT_NUM)
                            main_state <= read_byte_ack1;
                        else;
                end
                read_byte_ack1:begin
                        if(clk_cnt == CLK_PERIOD)
                            main_state <= read_byte2;
                        else;
                end
                read_byte2:begin
                        if(clk_cnt == CLK_PERIOD && shift_cnt == BIT_NUM)
                            main_state <= read_byte_ack2;
                        else;
                end
                read_byte_ack2:begin
                        if(clk_cnt == CLK_PERIOD)
                                main_state <= read_byte3;
                        else;
                end
                read_byte3:begin
                        if(clk_cnt == CLK_PERIOD && shift_cnt == BIT_NUM)
                            main_state <= read_byte_ack3;
                        else;
                end
                read_byte_ack3:begin
                        if(clk_cnt == CLK_PERIOD)
                            main_state <= read_byte4;
                        else;
                end
                read_byte4:begin
                        if(clk_cnt == CLK_PERIOD && shift_cnt == BIT_NUM)
                            main_state <= read_byte_ack4;
                        else;
                end
                read_byte_ack4:begin
                        if(clk_cnt == CLK_PERIOD)
                            main_state <= read_byte5;
                        else;
                end
                read_byte5:begin
                        if(clk_cnt == CLK_PERIOD && shift_cnt == BIT_NUM)
                            main_state <= read_byte_ack5;
                        else;
                end
                read_byte_ack5:begin
                        if(clk_cnt == CLK_PERIOD)
                            main_state <= read_byte6;
                        else;
                end
                read_byte6:begin
                        if(clk_cnt == CLK_PERIOD && shift_cnt == BIT_NUM)
                            main_state <= read_byte_ack6;
                        else;
                end
                read_byte_ack6:begin
                        if(clk_cnt == CLK_PERIOD)
                            main_state <= read_byte7;
                        else;
                end
                read_byte7:begin
                        if(clk_cnt == CLK_PERIOD && shift_cnt == BIT_NUM)
                            main_state <= read_byte_ack7;
                        else;
                end
                read_byte_ack7:begin
                        if(clk_cnt == CLK_PERIOD)
                            main_state <= read_byte8;
                        else;
                end
                read_byte8:begin
                        if(clk_cnt == CLK_PERIOD && shift_cnt == BIT_NUM)
                            main_state <= read_byte_ack8;
                        else;
                end
                read_byte_ack8:begin
                        if(clk_cnt == CLK_PERIOD)
                            main_state <= read_byte9;
                        else;
                end
                read_byte9:begin
                        if(clk_cnt == CLK_PERIOD && shift_cnt == BIT_NUM)
                            main_state <= read_byte_ack9;
                        else;
                end
                read_byte_ack9:begin
                        if(clk_cnt == CLK_PERIOD)
                            main_state <= read_byte10;
                        else;
                end
                read_byte10:begin
                        if(clk_cnt == CLK_PERIOD && shift_cnt == BIT_NUM)
                            main_state <= read_byte_ack10;
                        else;
                end
                read_byte_ack10:begin
                        if(clk_cnt == CLK_PERIOD)
                            main_state <= read_byte11;
                        else;
                end
                read_byte11:begin
                        if(clk_cnt == CLK_PERIOD && shift_cnt == BIT_NUM)
                            main_state <= read_byte_ack11;
                        else;
                end
                read_byte_ack11:begin
                        if(clk_cnt == CLK_PERIOD)
                            main_state <= read_byte12;
                        else;
                end
                read_byte12:begin
                        if(clk_cnt == CLK_PERIOD && shift_cnt == BIT_NUM)
                            main_state <= read_byte_ack12;
                        else;
                end
                read_byte_ack12:begin
                        if(clk_cnt == CLK_PERIOD)
                            main_state <= read_byte13;
                        else;
                end
                read_byte13:begin
                        if(clk_cnt == CLK_PERIOD && shift_cnt == BIT_NUM)
                            main_state <= read_byte_ack13;
                        else;
                end
                read_byte_ack13:begin
                        if(clk_cnt == CLK_PERIOD)
                            main_state <= read_byte14;
                        else;
                end
                read_byte14:begin
                        if(clk_cnt == CLK_PERIOD && shift_cnt == BIT_NUM)
                            main_state <= read_byte_ack14;
                        else;
                end
                read_byte_ack14:begin
                        if(clk_cnt == CLK_PERIOD)
                            main_state <= read_byte15;
                        else;
                end
                read_byte15:begin
                        if(clk_cnt == CLK_PERIOD && shift_cnt == BIT_NUM)
                            main_state <= read_byte_ack15;
                        else;
                end
                read_byte_ack15:begin
                        if(clk_cnt == CLK_PERIOD)
                            main_state <= stop;
                        else;
                end
                stop:begin
                        if(clk_cnt == CLK_PERIOD)
                            main_state <= finish;
                        else;
                end
                finish:begin
                        main_state <= idle;
                end
                default:
                    main_state <= idle;
            endcase
        end
end

//----------------- FSM : cnt control ------------------
always @(posedge Clk or posedge Rst)
begin
    if(Rst)
    begin
        clk_cnt     <= 12'b0;
        shift_cnt   <= 3'b0;
    end
    else
    begin
    //clk_cnt
        if(main_state == idle || main_state == finish)
            clk_cnt     <= 12'b0;
        else
        begin
            if(clk_cnt == CLK_PERIOD)
                clk_cnt     <= 12'b0;
            else if(scl_out_z == ON && scl_in == 1'b0)//wait scl_in = 1
                clk_cnt     <= CLK_PERIOD_S1;           //keep on 1/4 CLK_PERIOD
            else
                clk_cnt     <= clk_cnt + 1'b1;
        end

    //shift_cnt
        if(main_state == device_addr_w || main_state == reg_addr0 || main_state == reg_addr1 || main_state == reg_addr2 || main_state == reg_addr3 || main_state == reg_addr4 || main_state == reg_addr5 || main_state == reg_addr6 || main_state == reg_addr7
		|| main_state == device_addr_r || main_state == read_byte0 || main_state == read_byte1 || main_state == read_byte2 || main_state == read_byte3 || main_state == read_byte4 || main_state == read_byte5 || main_state == read_byte6 || main_state == read_byte7 || main_state == read_byte8 || main_state == read_byte9 || main_state == read_byte10 || main_state == read_byte11 || main_state == read_byte12 || main_state == read_byte13 || main_state == read_byte14 || main_state == read_byte15)
        begin
            if(clk_cnt == CLK_PERIOD)
            begin
                if(shift_cnt == BIT_NUM)
                    shift_cnt   <= 3'b0;
                else
                    shift_cnt   <= shift_cnt + 1'b1;
            end
            else;
        end
        else
            shift_cnt   <= 3'b0;

    end
end

//----------------- FSM : output  ------------------
reg [7:0]   sh8out_buf;
reg [7:0]   sh8in_buf;
reg [7:0]   sh8in_buf_byte0;
reg [7:0]   sh8in_buf_byte1;
reg [7:0]   sh8in_buf_byte2;
reg [7:0]   sh8in_buf_byte3;
reg [7:0]   sh8in_buf_byte4;
reg [7:0]   sh8in_buf_byte5;
reg [7:0]   sh8in_buf_byte6;
reg [7:0]   sh8in_buf_byte7;
reg [7:0]   sh8in_buf_byte8;
reg [7:0]   sh8in_buf_byte9;
reg [7:0]   sh8in_buf_byte10;
reg [7:0]   sh8in_buf_byte11;
reg [7:0]   sh8in_buf_byte12;
reg [7:0]   sh8in_buf_byte13;
reg [7:0]   sh8in_buf_byte14;
reg [7:0]   sh8in_buf_byte15;


always @(posedge Clk or posedge Rst)
begin
    if(Rst) begin
        scl_out_z       <= ON;
        sda_out_z_i       <= ON;
        I2cSirRdat      <= 32'h0000;
        I2cSirDackh     <= 1'b0;
        sh8out_buf      <= 8'b0;
        sh8in_buf_byte0 <= 8'b0;
      	sh8in_buf_byte1 <= 8'b0;
        sh8in_buf_byte2 <= 8'b0;
      	sh8in_buf_byte3 <= 8'b0;
      	sh8in_buf_byte4 <= 8'b0;
      	sh8in_buf_byte5 <= 8'b0;
      	sh8in_buf_byte6 <= 8'b0;
      	sh8in_buf_byte7 <= 8'b0;
      	sh8in_buf_byte8 <= 8'b0;
      	sh8in_buf_byte9 <= 8'b0;
      	sh8in_buf_byte10 <= 8'b0;
      	sh8in_buf_byte11 <= 8'b0;
      	sh8in_buf_byte12 <= 8'b0;
      	sh8in_buf_byte13 <= 8'b0;
      	sh8in_buf_byte14 <= 8'b0;
      	sh8in_buf_byte15 <= 8'b0;
    end else begin
            case(main_state)
                idle:begin
                        scl_out_z   <= ON;
                        sda_out_z_i   <= ON;
                        I2cSirRdat  <=  I2cSirRdat;
                        if ( I2cSirSel == 1'b0)
                            I2cSirDackh <=  1'b0;
                        else ;
                        sh8out_buf      <= 8'b0;
                        sh8in_buf_byte0 <= 8'b0;
                        sh8in_buf_byte1 <= 8'b0;
                        sh8in_buf_byte2 <= 8'b0;
                        sh8in_buf_byte3 <= 8'b0;
						sh8in_buf_byte4 <= 8'b0;
						sh8in_buf_byte5 <= 8'b0;
						sh8in_buf_byte6 <= 8'b0;
						sh8in_buf_byte7 <= 8'b0;
						sh8in_buf_byte8 <= 8'b0;
						sh8in_buf_byte9 <= 8'b0;
						sh8in_buf_byte10 <= 8'b0;
						sh8in_buf_byte11 <= 8'b0;
						sh8in_buf_byte12 <= 8'b0;
						sh8in_buf_byte13 <= 8'b0;
						sh8in_buf_byte14 <= 8'b0;
						sh8in_buf_byte15 <= 8'b0;
                end
                start:begin
                        task_start;
                        I2cSirDackh <=  1'b0;
                        sh8out_buf      <= {lock_i2c_chip_addr,1'b0};//1'b0 for write
                        sh8in_buf_byte0 <= 8'b0;
                        sh8in_buf_byte1 <= 8'b0;
                        sh8in_buf_byte2 <= 8'b0;
                        sh8in_buf_byte3 <= 8'b0;
						sh8in_buf_byte4 <= 8'b0;
						sh8in_buf_byte5 <= 8'b0;
						sh8in_buf_byte6 <= 8'b0;
						sh8in_buf_byte7 <= 8'b0;
						sh8in_buf_byte8 <= 8'b0;
						sh8in_buf_byte9 <= 8'b0;
						sh8in_buf_byte10 <= 8'b0;
						sh8in_buf_byte11 <= 8'b0;
						sh8in_buf_byte12 <= 8'b0;
						sh8in_buf_byte13 <= 8'b0;
						sh8in_buf_byte14 <= 8'b0;
						sh8in_buf_byte15 <= 8'b0;
                end
                device_addr_w:begin
                        task_shift_data_out;
                end
                device_addr_wack:begin
                        task_ack;
                        case(lock_i2c_mode)
                            4'b0001: begin sh8out_buf      <= lock_i2c_sir_addr[7:0];  end
                            4'b0010: begin sh8out_buf      <= lock_i2c_sir_addr[15:8]; end
                            4'b0011: begin sh8out_buf      <= lock_i2c_sir_addr[23:16]; end
                            4'b0100: begin sh8out_buf      <= lock_i2c_sir_addr[31:24]; end
                            4'b0101: begin sh8out_buf      <= lock_i2c_sir_addr[39:32]; end
                            4'b0110: begin sh8out_buf      <= lock_i2c_sir_addr[47:40]; end
                            4'b0111: begin sh8out_buf      <= lock_i2c_sir_addr[55:48]; end
                            default: begin sh8out_buf      <= lock_i2c_sir_addr[63:56]; end
                        endcase
                end
                reg_addr0,reg_addr1,reg_addr2,reg_addr3,reg_addr4,reg_addr5,reg_addr6,reg_addr7:begin
                        task_shift_data_out;
                end
                reg_addr_ack0:begin
                        task_ack;
                        sh8out_buf      <= lock_i2c_sir_addr[55:48];
                end
                reg_addr_ack1:begin
                        task_ack;
                        sh8out_buf      <= lock_i2c_sir_addr[47:40];
                end
                reg_addr_ack2:begin
                        task_ack;
                        sh8out_buf      <= lock_i2c_sir_addr[39:32];
                end
                reg_addr_ack3:begin
                        task_ack;
                        sh8out_buf      <= lock_i2c_sir_addr[31:24];
                end
                reg_addr_ack4:begin
                        task_ack;
                        sh8out_buf      <= lock_i2c_sir_addr[23:16];
                end
                reg_addr_ack5:begin
                        task_ack;
                        sh8out_buf      <= lock_i2c_sir_addr[15:8];
                end
                reg_addr_ack6:begin
                        task_ack;
                        sh8out_buf      <= lock_i2c_sir_addr[7:0];
                end
                reg_addr_ack7:begin
                        task_ack;
                        if(lock_i2c_sir_Read == 1'b0)begin//write
                                case(lock_i2c_date_len)
                                    5'd1: sh8out_buf      <= lock_i2c_sir_wdat[7:0];
                                    5'd2: sh8out_buf      <= lock_i2c_sir_wdat[15:8];
                                    5'd3: sh8out_buf      <= lock_i2c_sir_wdat[23:16];
                                    5'd4: sh8out_buf      <= lock_i2c_sir_wdat[31:24];
                                    5'd5: sh8out_buf      <= lock_i2c_sir_wdat[39:32];
                                    5'd6: sh8out_buf      <= lock_i2c_sir_wdat[47:40];
                                    5'd7: sh8out_buf      <= lock_i2c_sir_wdat[55:48];
                                    5'd8: sh8out_buf      <= lock_i2c_sir_wdat[63:56];
                                    5'd9: sh8out_buf      <= lock_i2c_sir_wdat[71:64];
                                    5'd10:sh8out_buf      <= lock_i2c_sir_wdat[79:72];
                                    5'd11:sh8out_buf      <= lock_i2c_sir_wdat[87:80];
                                    5'd12:sh8out_buf      <= lock_i2c_sir_wdat[95:88];
                                    5'd13:sh8out_buf      <= lock_i2c_sir_wdat[103:96];
                                    5'd14:sh8out_buf      <= lock_i2c_sir_wdat[111:104];
                                    5'd15:sh8out_buf      <= lock_i2c_sir_wdat[119:112];
                                    default:sh8out_buf    <= lock_i2c_sir_wdat[127:120];
                                endcase
                            end else
                                sh8out_buf      <= sh8out_buf;
                end
                restart:begin
                        task_start;
                        sh8out_buf      <= {lock_i2c_chip_addr,1'b1};//1'b1 for read
                    end
                device_addr_r:begin
                        task_shift_data_out;
                end
                device_addr_rack:begin
                        task_ack;
                end
                read_byte0,read_byte1,read_byte2,read_byte3,read_byte4,read_byte5,read_byte6,read_byte7,read_byte8,read_byte9,read_byte10,read_byte11,read_byte12,read_byte13,read_byte14,read_byte15:begin
                        if(lock_i2c_sir_Read == 1'b0)
                            task_shift_data_out;
                        else
                            task_shift_data_in;
                end
                read_byte_ack0:begin
                            if(lock_i2c_sir_Read == 1'b0) begin
                                task_ack;
                                sh8out_buf      <= lock_i2c_sir_wdat[119:112];//for write operate,load high byte.
                            end else
                                task_ack_rd_byte;
                            sh8in_buf_byte15 <=sh8in_buf;
                end
                read_byte_ack1:begin
                            if(lock_i2c_sir_Read == 1'b0) begin
                                task_ack;
                                sh8out_buf      <= lock_i2c_sir_wdat[111:104];//for write operate,load high byte.
                            end else
                                task_ack_rd_byte;
                            sh8in_buf_byte14 <=sh8in_buf;
                end
                read_byte_ack2:begin
                            if(lock_i2c_sir_Read == 1'b0) begin
                                task_ack;
                                sh8out_buf      <= lock_i2c_sir_wdat[103:96];//for write operate,load high byte.
                            end else
                                task_ack_rd_byte;
                            sh8in_buf_byte13 <=sh8in_buf;
                end
                read_byte_ack3:begin
                            if(lock_i2c_sir_Read == 1'b0) begin
                                task_ack;
                                sh8out_buf      <= lock_i2c_sir_wdat[95:88];//for write operate,load high byte.
                            end else
                                task_ack_rd_byte;
                            sh8in_buf_byte12 <=sh8in_buf;
                end
                read_byte_ack4:begin
                            if(lock_i2c_sir_Read == 1'b0) begin
                                task_ack;
                                sh8out_buf      <= lock_i2c_sir_wdat[87:80];//for write operate,load high byte.
                            end else
                                task_ack_rd_byte;
                            sh8in_buf_byte11 <=sh8in_buf;
                end
                read_byte_ack5:begin
                            if(lock_i2c_sir_Read == 1'b0) begin
                                task_ack;
                                sh8out_buf      <= lock_i2c_sir_wdat[79:72];//for write operate,load high byte.
                            end else
                                task_ack_rd_byte;
                            sh8in_buf_byte10 <=sh8in_buf;
                end
                read_byte_ack6:begin
                            if(lock_i2c_sir_Read == 1'b0) begin
                                task_ack;
                                sh8out_buf      <= lock_i2c_sir_wdat[71:64];//for write operate,load high byte.
                            end else
                                task_ack_rd_byte;
                            sh8in_buf_byte9 <=sh8in_buf;
                end
                read_byte_ack7:begin
                            if(lock_i2c_sir_Read == 1'b0) begin
                                task_ack;
                                sh8out_buf      <= lock_i2c_sir_wdat[63:56];//for write operate,load high byte.
                            end else
                                task_ack_rd_byte;
                            sh8in_buf_byte8 <=sh8in_buf;
                end
                read_byte_ack8:begin
                            if(lock_i2c_sir_Read == 1'b0) begin
                                task_ack;
                                sh8out_buf      <= lock_i2c_sir_wdat[55:48];//for write operate,load high byte.
                            end else
                                task_ack_rd_byte;
                            sh8in_buf_byte7 <=sh8in_buf;
                end
                read_byte_ack9:begin
                            if(lock_i2c_sir_Read == 1'b0) begin
                                task_ack;
                                sh8out_buf      <= lock_i2c_sir_wdat[47:40];//for write operate,load high byte.
                            end else
                                task_ack_rd_byte;
                            sh8in_buf_byte6 <=sh8in_buf;
                end
                read_byte_ack10:begin
                            if(lock_i2c_sir_Read == 1'b0) begin
                                task_ack;
                                sh8out_buf      <= lock_i2c_sir_wdat[39:32];//for write operate,load high byte.
                            end else
                                task_ack_rd_byte;
                            sh8in_buf_byte5 <=sh8in_buf;
                end
                read_byte_ack11:begin
                            if(lock_i2c_sir_Read == 1'b0) begin
                                task_ack;
                                sh8out_buf      <= lock_i2c_sir_wdat[31:24];//for write operate,load high byte.
                            end else
                                task_ack_rd_byte;
                            sh8in_buf_byte4 <=sh8in_buf;
                end
                read_byte_ack12:begin
                            if(lock_i2c_sir_Read == 1'b0) begin
                                task_ack;
                                sh8out_buf      <= lock_i2c_sir_wdat[23:16];//for write operate,load high byte.
                            end else
                                task_ack_rd_byte;
                            sh8in_buf_byte3 <=sh8in_buf;
                end
                read_byte_ack13:begin
                            if(lock_i2c_sir_Read == 1'b0) begin
                                task_ack;
                                sh8out_buf      <= lock_i2c_sir_wdat[15:8];//for write operate,load high byte.
                            end else
                                task_ack_rd_byte;
                            sh8in_buf_byte2 <=sh8in_buf;
                end
                read_byte_ack14:begin
                            if(lock_i2c_sir_Read == 1'b0) begin
                                task_ack;
                                sh8out_buf      <= lock_i2c_sir_wdat[7:0];//for write operate,load high byte.
                            end else
                                task_ack_rd_byte;
                            sh8in_buf_byte1 <=sh8in_buf;
                end
                read_byte_ack15:begin
                                task_ack;
                                sh8in_buf_byte0 <=sh8in_buf;
                end
                stop:begin
                        task_stop;
                end
                finish:begin
                    if((lock_i2c_sir_Read == 1'b0)||(lock_i2c_date_len==5'd0))//wirte or length=0
                            I2cSirRdat  <=  {4{32'hFFFFFFFF}};
                    else begin
                        case(lock_i2c_date_len)
                            5'h1:I2cSirRdat  <=  {120'h00,sh8in_buf_byte0};
                            5'h2:I2cSirRdat  <=  {112'h00,sh8in_buf_byte0,sh8in_buf_byte1};
                            5'h3:I2cSirRdat  <=  {104'h00,sh8in_buf_byte0,sh8in_buf_byte1,sh8in_buf_byte2};
                            5'h4:I2cSirRdat  <=  { 96'h00,sh8in_buf_byte0,sh8in_buf_byte1,sh8in_buf_byte2,sh8in_buf_byte3};
                            5'h5:I2cSirRdat  <=  { 88'h00,sh8in_buf_byte0,sh8in_buf_byte1,sh8in_buf_byte2,sh8in_buf_byte3,sh8in_buf_byte4};
                            5'h6:I2cSirRdat  <=  { 80'h00,sh8in_buf_byte0,sh8in_buf_byte1,sh8in_buf_byte2,sh8in_buf_byte3,sh8in_buf_byte4,sh8in_buf_byte5};
                            5'h7:I2cSirRdat  <=  { 72'h00,sh8in_buf_byte0,sh8in_buf_byte1,sh8in_buf_byte2,sh8in_buf_byte3,sh8in_buf_byte4,sh8in_buf_byte5,sh8in_buf_byte6};
                            5'h8:I2cSirRdat  <=  { 64'h00,sh8in_buf_byte0,sh8in_buf_byte1,sh8in_buf_byte2,sh8in_buf_byte3,sh8in_buf_byte4,sh8in_buf_byte5,sh8in_buf_byte6,sh8in_buf_byte7};
                            5'h9:I2cSirRdat  <=  { 56'h00,sh8in_buf_byte0,sh8in_buf_byte1,sh8in_buf_byte2,sh8in_buf_byte3,sh8in_buf_byte4,sh8in_buf_byte5,sh8in_buf_byte6,sh8in_buf_byte7,sh8in_buf_byte8};
                            5'ha:I2cSirRdat  <=  { 48'h00,sh8in_buf_byte0,sh8in_buf_byte1,sh8in_buf_byte2,sh8in_buf_byte3,sh8in_buf_byte4,sh8in_buf_byte5,sh8in_buf_byte6,sh8in_buf_byte7,sh8in_buf_byte8,sh8in_buf_byte9};
                            5'hb:I2cSirRdat  <=  { 40'h00,sh8in_buf_byte0,sh8in_buf_byte1,sh8in_buf_byte2,sh8in_buf_byte3,sh8in_buf_byte4,sh8in_buf_byte5,sh8in_buf_byte6,sh8in_buf_byte7,sh8in_buf_byte8,sh8in_buf_byte9,sh8in_buf_byte10};
                            5'hc:I2cSirRdat  <=  { 32'h00,sh8in_buf_byte0,sh8in_buf_byte1,sh8in_buf_byte2,sh8in_buf_byte3,sh8in_buf_byte4,sh8in_buf_byte5,sh8in_buf_byte6,sh8in_buf_byte7,sh8in_buf_byte8,sh8in_buf_byte9,sh8in_buf_byte10,sh8in_buf_byte11};
                            5'hd:I2cSirRdat  <=  { 24'h00,sh8in_buf_byte0,sh8in_buf_byte1,sh8in_buf_byte2,sh8in_buf_byte3,sh8in_buf_byte4,sh8in_buf_byte5,sh8in_buf_byte6,sh8in_buf_byte7,sh8in_buf_byte8,sh8in_buf_byte9,sh8in_buf_byte10,sh8in_buf_byte11,sh8in_buf_byte12};
                            5'he:I2cSirRdat  <=  { 16'h00,sh8in_buf_byte0,sh8in_buf_byte1,sh8in_buf_byte2,sh8in_buf_byte3,sh8in_buf_byte4,sh8in_buf_byte5,sh8in_buf_byte6,sh8in_buf_byte7,sh8in_buf_byte8,sh8in_buf_byte9,sh8in_buf_byte10,sh8in_buf_byte11,sh8in_buf_byte12,sh8in_buf_byte13};
                            5'hf:I2cSirRdat  <=  {  8'h00,sh8in_buf_byte0,sh8in_buf_byte1,sh8in_buf_byte2,sh8in_buf_byte3,sh8in_buf_byte4,sh8in_buf_byte5,sh8in_buf_byte6,sh8in_buf_byte7,sh8in_buf_byte8,sh8in_buf_byte9,sh8in_buf_byte10,sh8in_buf_byte11,sh8in_buf_byte12,sh8in_buf_byte13,sh8in_buf_byte14};
                            default :I2cSirRdat  <=  {        sh8in_buf_byte0,sh8in_buf_byte1,sh8in_buf_byte2,sh8in_buf_byte3,sh8in_buf_byte4,sh8in_buf_byte5,sh8in_buf_byte6,sh8in_buf_byte7,sh8in_buf_byte8,sh8in_buf_byte9,sh8in_buf_byte10,sh8in_buf_byte11,sh8in_buf_byte12,sh8in_buf_byte13,sh8in_buf_byte14,sh8in_buf_byte15};
                        endcase
                    end
                    I2cSirDackh <=  1'b1;
                end
                default: begin
                    scl_out_z	      <= ON;
                    sda_out_z_i	      <= ON;

                    I2cSirRdat      <= 128'd0;
                    I2cSirDackh     <= 1'b0;

                    sh8out_buf      <= 8'b0;
                    sh8in_buf_byte0 <= 8'b0;
                    sh8in_buf_byte1 <= 8'b0;
					sh8in_buf_byte2 <= 8'b0;
					sh8in_buf_byte3 <= 8'b0;
					sh8in_buf_byte4 <= 8'b0;
					sh8in_buf_byte5 <= 8'b0;
					sh8in_buf_byte6 <= 8'b0;
					sh8in_buf_byte7 <= 8'b0;
					sh8in_buf_byte8 <= 8'b0;
					sh8in_buf_byte9 <= 8'b0;
					sh8in_buf_byte10 <= 8'b0;
					sh8in_buf_byte11 <= 8'b0;
					sh8in_buf_byte12 <= 8'b0;
					sh8in_buf_byte13 <= 8'b0;
					sh8in_buf_byte14 <= 8'b0;
					sh8in_buf_byte15 <= 8'b0;
                end
            endcase
        end
end


//-----------------------------------------------
task task_start;
begin
    if(clk_cnt == CLK_PERIOD_S1)
        scl_out_z <= ON;
    else if(clk_cnt == CLK_PERIOD_S3)
        scl_out_z <= OFF;
    else;

    if(clk_cnt == CLK_PERIOD_S0)
        sda_out_z_i <= ON;
    else if(clk_cnt == CLK_PERIOD_S2)
        sda_out_z_i <= OFF;
    else;

end
endtask

//-----------------------------------------------
task task_shift_data_out;
begin
    if(clk_cnt == CLK_PERIOD_S1)
        scl_out_z <= ON;
    else if(clk_cnt == CLK_PERIOD_S3)
        scl_out_z <= OFF;
    else;

    if(clk_cnt == CLK_PERIOD_S0)
        sda_out_z_i  <= sh8out_buf[7];
    else;

    if(clk_cnt == CLK_PERIOD)
        sh8out_buf <= sh8out_buf<<1;
    else;

end
endtask

//-----------------------------------------------
task task_ack;
begin
    if(clk_cnt == CLK_PERIOD_S1)
        scl_out_z <= ON;
    else if(clk_cnt == CLK_PERIOD_S3)
        scl_out_z <= OFF;
    else;

    sda_out_z_i <= ON;//read bytes cycle, second ack is release for invalid.wirte bytes cycle, ack is always being release.
end
endtask

//-----------------------------------------------
task task_ack_rd_byte;
begin
    if(clk_cnt == CLK_PERIOD_S1)
        scl_out_z <= ON;
    else if(clk_cnt == CLK_PERIOD_S3)
        scl_out_z <= OFF;
    else;


        if(clk_cnt == CLK_PERIOD_S0)
            sda_out_z_i <= OFF;
        else if(clk_cnt == CLK_PERIOD)
            sda_out_z_i <= ON;
        else;

end
endtask



task task_shift_data_in;
begin
    if(clk_cnt == CLK_PERIOD_S1)
        scl_out_z <= ON;
    else
    begin
        if(clk_cnt == CLK_PERIOD_S3)
            scl_out_z <= OFF;
        else;
    end

    if(clk_cnt == CLK_PERIOD_S2)
        sh8in_buf[0] <= sda_in;
    else;

    if(clk_cnt == CLK_PERIOD && shift_cnt != BIT_NUM)
        sh8in_buf[7:1] <= sh8in_buf[6:0];
    else;
end
endtask

//-----------------------------------------------
task task_stop;
begin
    if(clk_cnt == CLK_PERIOD_S1)
        scl_out_z <= ON;
    else;

    if(clk_cnt == CLK_PERIOD_S0)
        sda_out_z_i <= OFF;
    else if(clk_cnt == CLK_PERIOD_S2)
        sda_out_z_i <= ON;
    else;

end
endtask

endmodule


