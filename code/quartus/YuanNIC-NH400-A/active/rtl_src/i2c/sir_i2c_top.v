`timescale 1ns / 100ps
module sir_i2c_top #(
        parameter DONE_WAIT_TIME = 18'd1500,
        parameter CLK_PERIOD = 12'd250
    )
    (
    input               clk       	,
    input               rst       	,
	
    input               i2c_sel   	,
    input               i2c_rw_ctl	,
    input   [4:0]	    i2c_dlen  	,
    input   [2:0]	    i2c_mode  	,
    input   [31:0]      i2c_addr  	,
    input   [6:0]       i2c_dev_id	,
    input   [127:0]     i2c_wdata 	,
    output              i2c_ack   	,
    output  [127:0]     i2c_rdata 	,
    output              i2c_done  	,


    inout               scl			,
    inout               sda			
	
) ;

wire		scl_in;
wire		sda_in;
wire		scl_out;
wire		sda_out;

assign 	scl_in 	= scl;
assign	sda_in 	= sda;
assign	scl		= scl_out ? 1'bz : 1'b0;
assign	sda		= sda_out ? 1'bz : 1'b0;

reg             i2c_sel_i      ;
reg		[4:0]	i2c_dlen_i	   ;
reg		[2:0]	i2c_mode_i	   ;
reg     [31:0]  i2c_addr_i     ;
reg     [127:0] i2c_wdata_i     ;


always @( posedge clk ) begin
	if ( rst == 1'b1 ) begin
	    i2c_sel_i <= 1'b0 ;
	    i2c_dlen_i <= 'd0 ;
	    i2c_mode_i <= 'd0 ;
	    i2c_addr_i <= 'd0 ;
	    i2c_wdata_i <= 'd0 ;
	end 
    else begin
		if (i2c_sel&&i2c_done) begin
            i2c_sel_i   <= 1'b1;
		    i2c_dlen_i  <= i2c_dlen  ;
			i2c_mode_i  <= i2c_mode  ;
		    i2c_addr_i  <= i2c_addr  ;
		    i2c_wdata_i <= i2c_wdata ;
        end  
        else if ( i2c_ack == 1'b1)
			i2c_sel_i   <= 1'b0 ;
		else begin
            i2c_sel_i   <= i2c_sel_i ;
		    i2c_dlen_i  <= i2c_dlen  ;
			i2c_mode_i  <= i2c_mode  ;
		    i2c_addr_i  <= i2c_addr  ;
		    i2c_wdata_i <= i2c_wdata ;
        end 
    end
end	

//cpld & other
i2c_core_v1 #( 
    .CLK_PERIOD     (CLK_PERIOD),
    .DONE_WAIT_TIME (DONE_WAIT_TIME)
)u_cpld_i2c_master_direct(
    .Clk            (clk) ,
    .Rst            (rst) ,

    .I2cSirSel      (i2c_sel_i) ,
    .I2cSirRead     (i2c_rw_ctl) ,
    .I2cSirAddr     ({32'd0,i2c_addr_i}) ,
    .I2cSirWdat     (i2c_wdata_i) ,
    .I2cSirRdat     (i2c_rdata) ,
    .I2cSirDackh    (i2c_ack) ,
    .I2cSirDone     (i2c_done) ,
    .I2cDateLen     (i2c_dlen_i) ,
    .I2cChipAddr    (i2c_dev_id) ,
    .I2cMode        ({1'b0,i2c_mode_i}) ,

    .scl_out_z      (scl_out) ,
    .scl_in         (scl_in) ,
    .sda_out_z      (sda_out) ,
    .sda_in         (sda_in)
    );
        
endmodule
