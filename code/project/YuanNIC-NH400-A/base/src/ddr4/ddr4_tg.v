//-----------------------------------------------------------------------------
// Title         : ddr4_tg.v
// Project       : 
//-----------------------------------------------------------------------------
// File          : ddr4_tg.v
// Author        :   <Administrator@DESKTOP-SKNAR7C>
// Created       : 12.06.2024
// Last modified : 12.06.2024
//-----------------------------------------------------------------------------
// Description :
//
//-----------------------------------------------------------------------------
// Copyright (c) 2024 by  This model is the confidential and
// proprietary property of  and the possession or use of this
// file requires a written license from .
//------------------------------------------------------------------------------
// Modification history :
// 12.06.2024 : created
//-----------------------------------------------------------------------------

`include "../top/define.vh"

module ddr4_tg (/*AUTOARG*/
   // Outputs
   app_amm_read, app_amm_write, app_amm_addr, app_amm_wdat,
   app_amm_byte, app_amm_bcnt,
   // Inputs
   rst, clk, app_amm_ready, app_amm_rdat, app_amm_rvld,
   test_enb, test_type, test_done, err_flag, err_cnt, rd_done, rd_addr,
   ddr_wr, addr_mode, addr_seed, dat_mode, DDR_END_ADDR,
   ddr_dat0, ddr_dat1, ddr_dat2, ddr_dat3, total_time_r, total_cnt_r,
   total_time_w, total_cnt_w
   
   ) ;
	input  	wire              	rst;
	input  	wire 				clk;

	input	wire				test_enb	;//测试开始
	input	wire	/* [1:0] */		test_type	;//[0]读写校验，[1]性能测试
	output	reg 				test_done	;//读写校验有效
	output	wire				err_flag	;
	output	wire	[31:0]		err_cnt		;
	output	wire				rd_done		;
	output	wire	[31:0]		rd_addr		;	

	input	wire	[1:0]		ddr_wr		;//[0]读，[1]写
	input	wire				addr_mode	;//0顺序地址，1随机地址
	input	wire	[7:0]		addr_seed	;//随机数时使用
	input	wire	[31:0]		DDR_END_ADDR;
	
	input	wire	[1:0]		dat_mode	;//0写入地址，1写入寄存器数据，2写入随机数
	input	wire	[31:0]		ddr_dat0	;
	input	wire	[31:0]		ddr_dat1	;
	input	wire	[31:0]		ddr_dat2	;
	input	wire	[31:0]		ddr_dat3	;
	
	output	wire	[31:0]		total_time_w;//性能测试时间
	output	wire	[31:0]		total_cnt_w	;//性能测试计数
	output	wire	[31:0]		total_time_r;//性能测试时间
	output	wire	[31:0]		total_cnt_r	;//性能测试计数
	
	input  	wire 				app_amm_ready	;
	output  wire 				app_amm_read	;
	output  wire 				app_amm_write	;
	output  wire 	[26:0] 		app_amm_addr	;//16 byte address
	input  	wire 	[127:0]		app_amm_rdat	;
	input  	wire 				app_amm_rvld	;
	output  wire 	[127:0]		app_amm_wdat	;	
	output  reg 	[15:0] 		app_amm_byte = 16'hffff;
	output 	reg 	[6:0] 		app_amm_bcnt = 7'h1;
   
    wire		test_wr_done;
	wire		test_rd_done;
    
	always @(posedge clk)
	begin
		if(test_enb)
			if(test_wr_done | test_rd_done)
				test_done <= 1'b1;
			else;
		else
			test_done <= 1'b0;
	end
	
	
	//assign 	test_done = test_wr_done | test_rd_done;
   
	ddr_test_wr		U_ddr_wr(
			
			.clk				(clk			),
			.rst				(rst			),
								 				
			.test_enb           (test_enb      	),
			.test_type          (test_type     	),
			.test_done			(test_wr_done	),
								 				
			.addr_mode          (addr_mode     	),
			.addr_seed          (addr_seed     	),
			.DDR_END_ADDR       (DDR_END_ADDR  	),
												
			.ddr_wr				(ddr_wr			),
			.dat_mode           (dat_mode      	),
			.ddr_dat0           (ddr_dat0      	),
			.ddr_dat1           (ddr_dat1      	),
			.ddr_dat2           (ddr_dat2      	),
			.ddr_dat3           (ddr_dat3      	),
													
			.app_amm_ready      (app_amm_ready 	),
			.app_amm_read       (app_amm_read 	),
			.app_amm_write      (app_amm_write 	),
			.app_amm_addr       (app_amm_addr  	),
			.app_amm_wdat       (app_amm_wdat  	),
			
			.total_time_w		(total_time_w	),
			.total_cnt_w		(total_cnt_w	),
			.total_time_r		(total_time_r	),
			.total_cnt_r		(total_cnt_r	)
	
	);
	
	ddr_test_rd		U_ddr_rd(
			
			.clk				(clk			),
			.rst				(rst			),
								 				
			.test_enb           (test_enb      	),
			.test_type          (test_type     	),
			.test_done			(test_rd_done	),
								 				
			.addr_mode          (addr_mode     	),
			.addr_seed          (addr_seed     	),
			.DDR_END_ADDR       (DDR_END_ADDR  	),
												
			.ddr_wr				(ddr_wr			),
			.dat_mode           (dat_mode      	),
			.ddr_dat0           (ddr_dat0      	),
			.ddr_dat1           (ddr_dat1      	),
			.ddr_dat2           (ddr_dat2      	),
			.ddr_dat3           (ddr_dat3      	),
													
			.app_amm_rvld      	(app_amm_rvld 	),
			.app_amm_rdat       (app_amm_rdat 	),
			
			.err_flag			(err_flag		),
			.err_cnt			(err_cnt		),
			.rd_done			(rd_done		),
			.rd_addr			(rd_addr		)
	
	);
endmodule // ddr4_tg
