// 2015/09/9      fuyajuan      1.0             Original
//
// ***************************************************************************************
// DEFINE
//  
//                                                  
// ***************************************************************************************
//
// Module       :    pcie_pro_pm 
// Called by    :    
//
// ***************************************************************************************
//
// ***************************************************************************************
//
// ***************************************************************************************
// CVS version comment
//
// $LOG$
//
// ***************************************************************************************

`include "../top/define.vh"

module csr_pro	(
		input	wire				rst					,
		input	wire				clk					,					
		input	wire				pcie_link_up				,
					
//-- AXI Master Write Address Channel           
     	input	wire [31:0] 		m_axil_awaddr    	,                     
     	input 	wire				m_axil_awvalid   	,          
     	output	reg	 				m_axil_awready   	,          
     	                                               
//-- AXI Master Write Data Channel             
     	input	wire [63:0] 		m_axil_wdata     	,         
     	input	wire [7:0]  		m_axil_wstrb     	,         
     	input	wire 				m_axil_wvalid    	,         
     	output	reg 				m_axil_wready    	,         
//-- AXI Master Write Response Channel      	   
     	output	reg 				m_axil_bvalid    	,
     	output	reg [1:0]  			m_axil_bresp     	,       
     	input	wire 				m_axil_bready    	,   
     	                                            	
//-- AXI Master Read Address Channel        	   
     	input 	wire[31:0] 			m_axil_araddr    	,                    
     	input 	wire				m_axil_arvalid   	,          
     	output  reg					m_axil_arready   	,          
//-- AXI Master Read Data Channel           	   
     	output	reg [63:0] 			m_axil_rdata     	,         
     	output  reg	[1:0]  			m_axil_rresp     	,         
     	output  reg					m_axil_rvalid    	,         
     	input	wire 				m_axil_rready    	,     
     
//csr interface
					
	 	output	wire				sir_sel				,
	 	output	wire	[31:0]		sir_addr			,
	 	output	wire				sir_read			,
	 	output	wire	[31:0]		sir_wdat			,
	 	input	wire	[31:0]		sir_rdat			,
	 	input	wire				sir_dack		

             );


parameter		PCIE_INIT	= 9'b000000001	;
parameter		PCIE_IDLE	= 9'b000000010	;
parameter       PCIE_WR_T   = 9'b000000100	;
parameter		PCIE_WR		= 9'b000001000	;
parameter       PCIE_RD_T   = 9'b000010000	;
parameter		PCIE_RD		= 9'b000100000	;
parameter		PCIE_DLY	= 9'b001000000	;
parameter		WR_END  	= 9'b010000000	;
parameter		RD_END  	= 9'b100000000	;

reg		[8:0]		pcie_state			;

reg					sir_sel1		;
reg		[31:0]		sir_addr1		;
reg					sir_read1		;
reg		[31:0]		sir_wdat1		;

wire	[31:0]		sir_rdat1;

assign sir_rdat1 = sir_rdat[31:0];
//assign sir_rdat1 = sir_rdat;


reg		[8:0]		sir_rd_cnt;
reg		[8:0]		sir_wr_cnt;
wire                time_out  ;

always @(posedge clk or posedge rst)
begin
	if(rst == 1'b1)
		sir_rd_cnt <= #`UDLY 9'd0;
	else if(pcie_state == PCIE_RD)
		if(sir_rd_cnt == 9'h1ff)
			sir_rd_cnt <= #`UDLY sir_rd_cnt;
		else
			sir_rd_cnt <= #`UDLY sir_rd_cnt + 1'b1;
	else
		sir_rd_cnt <= #`UDLY 9'd0;
end


always @ ( posedge clk or posedge rst) 
begin
    if(rst==1'b1)
 	    sir_wr_cnt	<= #`UDLY 9'h0;
    else if(pcie_state == PCIE_WR)
        if(sir_wr_cnt == 9'h1ff)
            sir_wr_cnt <= #`UDLY sir_wr_cnt;
        else 
            sir_wr_cnt <= #`UDLY sir_wr_cnt + 1'b1;
    else 
        sir_wr_cnt <= #`UDLY 9'h0;
end

assign  time_out = (sir_rd_cnt == 9'h1ff);

always @(posedge clk or posedge rst)
begin
	if(rst==1'b1)
		begin
		pcie_state 		<= #`UDLY PCIE_INIT;
		sir_sel1		<= #`UDLY 'b0;
		sir_addr1		<= #`UDLY 'b0;
		sir_read1		<= #`UDLY 'b0;
		sir_wdat1		<= #`UDLY 'b0;
		m_axil_bresp	<= #`UDLY 'b0;
		m_axil_awready	<= #`UDLY 'b0;
		m_axil_wready	<= #`UDLY 'b0;
		m_axil_bvalid	<= #`UDLY 'b0;
		m_axil_arready	<= #`UDLY 'b0;
		m_axil_rvalid	<= #`UDLY 'b0;
		m_axil_rdata	<= #`UDLY 'b0;
		m_axil_rresp	<= #`UDLY 2'b0;
		end	
	else
		case(pcie_state)
			PCIE_INIT :
				begin
				if(pcie_link_up==1'b1)
					begin
					pcie_state 		<= #`UDLY PCIE_IDLE;
					
					m_axil_awready	<= #`UDLY 1'b0;
					m_axil_wready	<= #`UDLY 1'b0;
					m_axil_arready 	<= #`UDLY 1'b0;
					end
				else
					begin
					pcie_state	<= #`UDLY pcie_state;
					
					m_axil_awready	<= #`UDLY 1'b0;
					m_axil_wready	<= #`UDLY 1'b0;
					m_axil_arready 	<= #`UDLY 1'b0;
					end
				end
				
			PCIE_IDLE :
				begin
				if(m_axil_awvalid == 1'b1)					
					begin
					pcie_state	<= #`UDLY PCIE_WR_T;
					
					sir_addr1		<= #`UDLY m_axil_awaddr ;
					m_axil_awready	<= #`UDLY 1'b1;
					m_axil_wready	<= #`UDLY 1'b1;
					m_axil_arready 	<= #`UDLY 1'b0;
					end
				else if (m_axil_arvalid == 1'b1 )
					begin
					pcie_state	<= #`UDLY PCIE_RD_T;
					
					sir_addr1		<= #`UDLY m_axil_araddr ;
					m_axil_awready	<= #`UDLY 1'b0;
					m_axil_wready	<= #`UDLY 1'b0;
					m_axil_arready 	<= #`UDLY 1'b1;
					end
			    else
			        begin
					pcie_state	<= #`UDLY pcie_state;
					
					m_axil_awready	<= #`UDLY 1'b0;
					m_axil_wready	<= #`UDLY 1'b0;
					m_axil_arready 	<= #`UDLY 1'b0;
					end	
			    end				
										
		    PCIE_WR_T   :
		        begin				
				if(m_axil_wvalid == 1'b1 )
					begin
					pcie_state 		<= #`UDLY PCIE_WR;
					
					m_axil_awready	<= #`UDLY 1'b0;
					m_axil_wready	<= #`UDLY 1'b0;
					m_axil_arready 	<= #`UDLY 1'b0;
					sir_sel1		<= #`UDLY 1'b1;
					sir_wdat1		<= #`UDLY m_axil_wdata[31:0];
					sir_read1		<= #`UDLY 1'b0;
					end
				else
				    begin
					pcie_state	<= #`UDLY PCIE_WR_T;
					
					sir_addr1		<= #`UDLY m_axil_awaddr ;
					m_axil_awready	<= #`UDLY 1'b1;
					m_axil_wready	<= #`UDLY 1'b1;
					m_axil_arready 	<= #`UDLY 1'b0;
					end	
			    end

			PCIE_RD_T :		
				begin	
                    pcie_state 		<= #`UDLY PCIE_RD;
                    
                    m_axil_awready	<= #`UDLY 1'b0;
                    m_axil_wready	<= #`UDLY 1'b0;
                    m_axil_arready 	<= #`UDLY 1'b0;		
                    sir_addr1		<= #`UDLY m_axil_araddr ;
                    sir_sel1		<= #`UDLY 1'b1;
                    sir_read1		<= #`UDLY 1'b1;
				end
					
			PCIE_WR :
				begin
                    m_axil_bresp	<= #`UDLY 2'b0;
				 
                if((sir_wr_cnt == 9'h1ff)|(sir_dack == 1'b1))
				    begin
				    pcie_state 		<= #`UDLY WR_END;
				    sir_sel1 		<= #`UDLY 1'b0;
                    m_axil_bvalid    <= #`UDLY 1'b0;
				    end
			    
				end
			PCIE_RD :
				begin
					m_axil_rresp	<= #`UDLY 2'b0;
					
				if((sir_rd_cnt == 9'h1ff)|(sir_dack == 1'b1))
					begin
                    pcie_state 		<= #`UDLY RD_END;
                    sir_sel1 		<= #`UDLY 1'b0;			
					m_axil_rvalid 	<= #`UDLY 1'b0;
                    m_axil_rdata	<= #`UDLY (sir_dack == 1'b1) ? {32'h0,sir_rdat1} : 64'hfffe_feff ;
					end 
				end
			WR_END :
				begin
                if(m_axil_bready && m_axil_bvalid)
                    begin
                    pcie_state 		<= #`UDLY PCIE_DLY;
                    m_axil_bvalid   <= #`UDLY 1'b0;
                    end
                else if(sir_dack == 1'b0)
                    begin
                    m_axil_bvalid   <= #`UDLY 1'b1;
                    end
                else;
				end
			RD_END :
				begin
                if(m_axil_rready && m_axil_rvalid)
                    begin
                    pcie_state 		<= #`UDLY PCIE_DLY;
                    m_axil_rvalid   <= #`UDLY 1'b0;
                    end
                else if(sir_dack == 1'b0)
                    begin
                    m_axil_rvalid   <= #`UDLY 1'b1;
                    end
                else;
				end
			PCIE_DLY :
                begin
                    pcie_state 		<= #`UDLY PCIE_IDLE;
    
                    sir_addr1		<= #`UDLY 32'b0; 
                    sir_wdat1		<= #`UDLY 32'b0;
                    sir_read1		<= #`UDLY 1'b0;
                    m_axil_bvalid	<= #`UDLY 1'b0;
                    m_axil_rvalid 	<= #`UDLY 1'b0;
				end
			default:
			    begin
                    pcie_state 		<= #`UDLY PCIE_IDLE;
                    
                    m_axil_awready	<= #`UDLY 1'b0;
                    m_axil_wready	<= #`UDLY 1'b0;
                    m_axil_arready 	<= #`UDLY 1'b0;
                
				end
		endcase
			
end



assign	sir_sel =  sir_sel1 ;
assign	sir_addr = sir_addr1 ;
assign	sir_read = sir_read1 ;
assign	sir_wdat = sir_wdat1[31:0] ;
//assign	sir_wdat = sir_wdat1;

endmodule