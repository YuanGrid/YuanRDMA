
`include "../top/global_define.vh"

module csr15_pm  (
                Clk                 ,
                Rst                 ,
                                    
                SirAddr             ,
                SirRead             ,
                SirWdat             ,
                                    
                SirSel              ,
                SirDack             ,
                SirRdat             ,

				eth_ctl_addr         ,
				eth_ctl_wdat         ,
				eth_ctl_write        ,
				eth_ctl_read         ,
				eth_ctl_byte         ,
				eth_ctl_rdat         ,
				eth_ctl_rvld         ,
                eth_ctl_wait         ,
				eth_ctl_irq          ,  
                eth_ctl_status       ,

				eth_ctl_rst
               );
                
parameter       SLAVE_SIZE  = 16;
                                            
input   wire                        Clk                 ;
input   wire                        Rst                 ;
                                                        
input   wire    [(SLAVE_SIZE-1):0]  SirAddr             ;
input   wire                        SirRead             ;
input   wire    [31:0]              SirWdat             ;
                                                        
input   wire                        SirSel              ;
output   reg                        SirDack             ;
output   reg    [31:0]              SirRdat             ;

output  wire [23:0]  	            eth_ctl_addr         ;
output  wire [31:0] 	            eth_ctl_wdat         ;
output  wire        	            eth_ctl_write        ;
output  wire 					    eth_ctl_read         ;
output  wire [3:0]					eth_ctl_byte		 ;
input   wire [31:0] 	            eth_ctl_rdat         ;
input   wire                        eth_ctl_rvld         ;  
input   wire                        eth_ctl_wait         ;                                  
input   wire  			            eth_ctl_irq          ;
input   wire [23:0]                 eth_ctl_status       ; //for debug

output	reg 						eth_ctl_rst			;
						  
/********************************************************************\
*                                                                    *
*               Metastability harder for SirSelx                     *
*                                                                    *
\********************************************************************/

wire 			    SirSelh;
   
assign SirSelh = SirSel;

/********************************************************************\
*                                                                    *
*               Adress : 16'h0000-16'h00FF                           *
*               Content: mail_box registers                          *
*                                                                    *
\********************************************************************/   

wire 			                   SirDack00xx;
wire [31:0] 					   SirRdat00xx;

eth_ctl_csr   
  U_eth_ctl_csr (
			  .rst                 (Rst                  ),
			  .clk                 (Clk                  ),

			  .sir_selh            (SirSelh 			 ),
			  .sir_read            (SirRead              ),
			  .sir_dack            (SirDack00xx          ),
			  
			  .sir_addr            (SirAddr[15:0]        ),
			  .sir_wdat            (SirWdat[31:0]        ),
			  .sir_rdat            (SirRdat00xx          ),

			  .eth_ctl_addr        (eth_ctl_addr          ),
			  .eth_ctl_wdat        (eth_ctl_wdat          ),
			  .eth_ctl_write       (eth_ctl_write         ),
			  .eth_ctl_read        (eth_ctl_read          ),
			  .eth_ctl_byte        (eth_ctl_byte          ),
			  .eth_ctl_rdat        (eth_ctl_rdat          ),
			  .eth_ctl_rvld        (eth_ctl_rvld          ),
			  .eth_ctl_wait        (eth_ctl_wait          )
			  );

/********************************************************************\
*                                                                    *
*               generate SirDack and SirRdat                         *
*                                                                    *
\********************************************************************/

always @ (posedge Clk or posedge Rst)
begin
    if (Rst == 1'b1)
        SirDack <= 1'b0;
    else
        SirDack <= #`UDLY
                           SirDack00xx 
						 ;
end       


always @ (posedge Clk or posedge Rst)
begin
    if (Rst == 1'b1)
        SirRdat <= 1'b0;
    else
        SirRdat <= #`UDLY
                           SirRdat00xx 
						 ;
end  

endmodule