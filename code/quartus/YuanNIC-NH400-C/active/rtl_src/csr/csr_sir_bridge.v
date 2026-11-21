
`include "../top/global_define.vh"

module  sempir   (

input   wire                        Clk             ,
input   wire                        Rst             ,

input   wire                        SirSel          ,
input   wire    [27:0]   			SirAddr         ,
input   wire                        SirRead         ,
input   wire    [31:0]              SirWdat         ,
output  reg     [31:0]              SirRdat         ,
output  reg                         SirDackh        ,

(* keep = "true", max_fanout = 32 *) output  reg     [15:0]  			 SirAddrx        ,
(* keep = "true", max_fanout = 32 *) output  reg     [31:0]              SirWdatx        ,

(* keep = "true", max_fanout = 32 *) output  reg                         SirSel00        ,
output  reg                         SirRead00		,
input   wire                        SirDack00       ,
input   wire    [31:0]              SirRdat00       ,
                                       
(* keep = "true", max_fanout = 32 *) output  reg                         SirSel10        ,
output  reg                         SirRead10		,
input   wire                        SirDack10       ,
input   wire    [31:0]              SirRdat10       ,

(* keep = "true", max_fanout = 32 *) output  reg                         SirSel11        ,
output  reg                         SirRead11		,
input   wire                        SirDack11       ,
input   wire    [31:0]              SirRdat11       ,
                                    
(* keep = "true", max_fanout = 32 *) output  reg                         SirSel12        ,
output  reg                         SirRead12		,
input   wire                        SirDack12       ,
input   wire    [31:0]              SirRdat12       ,

(* keep = "true", max_fanout = 32 *) output  reg                         SirSel14        ,
output  reg                         SirRead14		,
input   wire                        SirDack14       ,
input   wire    [31:0]              SirRdat14       ,

(* keep = "true", max_fanout = 32 *) output  reg                         SirSel15        ,
output  reg                         SirRead15		,
input   wire                        SirDack15       ,
input   wire    [31:0]              SirRdat15       ,

(* keep = "true", max_fanout = 32 *) output  reg                         SirSel16        ,
output  reg                         SirRead16		,
input   wire                        SirDack16       ,
input   wire    [31:0]              SirRdat16       ,

(* keep = "true", max_fanout = 32 *) output  reg                         SirSel17        ,
output  reg                         SirRead17		,
input   wire                        SirDack17       ,
input   wire    [31:0]              SirRdat17       ,

(* keep = "true", max_fanout = 32 *) output  reg                         SirSel18        ,
output  reg                         SirRead18		,
input   wire                        SirDack18       ,
input   wire    [31:0]              SirRdat18       ,

(* keep = "true", max_fanout = 32 *) output  reg                         SirSel19        ,
output  reg                         SirRead19		,
input   wire                        SirDack19       ,
input   wire    [31:0]              SirRdat19       ,

(* keep = "true", max_fanout = 32 *) output  reg                         SirSel1a        ,
output  reg                         SirRead1a		,
input   wire                        SirDack1a       ,
input   wire    [31:0]              SirRdat1a       ,

(* keep = "true", max_fanout = 32 *) output  reg                         SirSel1b        ,
output  reg                         SirRead1b		,
input   wire                        SirDack1b       ,
input   wire    [31:0]              SirRdat1b       ,


(* keep = "true", max_fanout = 32 *) output  reg                         SirSel1e        ,
output  reg                         SirRead1e		,
input   wire                        SirDack1e       ,
input   wire    [31:0]              SirRdat1e       ,
                                    
(* keep = "true", max_fanout = 32 *) output  reg                         SirSel1f        ,
output  reg                         SirRead1f		,
input   wire                        SirDack1f       ,
input   wire    [31:0]              SirRdat1f       ,

(* keep = "true", max_fanout = 32 *) output  reg                         SirSel20        ,
output  reg                         SirRead20		,
input   wire                        SirDack20       ,
input   wire    [31:0]              SirRdat20       ,


(* keep = "true", max_fanout = 32 *) output  reg                         SirSel40        ,
output  reg                         SirRead40		,
input   wire                        SirDack40       ,
input   wire    [31:0]              SirRdat40       ,

//
(* keep = "true", max_fanout = 32 *) output  reg                         SirSel110        ,
output  reg                         SirRead110		,
input   wire                        SirDack110      ,
input   wire    [31:0]              SirRdat110       


                );

parameter       BASE_SIZE       = 28    ;
parameter       SLAVE_SIZE      = 16    ;

/**************************************************************************************************/
/********************************************************************\
*                                                                    *
*               Metastability harder for SirDack                     *
*                                                                    *
\********************************************************************/
wire            SirDack         ;
reg             SirDackL1       ;
reg             SirDackL2       ;

assign SirDack =  SirDack00 |SirDack10 | SirDack11 | SirDack12
                | SirDack14 | SirDack15 | SirDack16 | SirDack17
                | SirDack18 | SirDack19 | SirDack1a | SirDack1b
                | SirDack1e | SirDack1f | SirDack20 | SirDack40
				| SirDack110
                ;

always @(posedge Clk or posedge Rst)
begin
    if (Rst == 1'b1)
        begin
            SirDackL1 <= 1'b0;
            SirDackL2 <= 1'b0;
            SirDackh  <= 1'b0;
        end
    else
        begin
            SirDackL1 <= #`UDLY SirDack;
            SirDackL2 <= #`UDLY SirDackL1;
            SirDackh  <= #`UDLY SirDackL2;
        end
end

/********************************************************************\
*                                                                    *
*               generate SirRdat                                     *
*                                                                    *
\********************************************************************/
wire	[31:0]		SirRdatL;
assign SirRdatL =  SirRdat00 | SirRdat10 | SirRdat11 | SirRdat12
                 | SirRdat14 | SirRdat15 | SirRdat16 | SirRdat17
                 | SirRdat18 | SirRdat19 | SirRdat1a | SirRdat1b
                 | SirRdat1e | SirRdat1f | SirRdat20 | SirRdat40
				 | SirRdat110
                ;

always @(posedge Clk or posedge Rst)
begin
    if (Rst == 1'b1)
		SirRdat    <= 32'b0;
	else
		SirRdat    <= #`UDLY SirRdatL;
end

/********************************************************************\
*                                                                    *
*               buffer SirAddr, SirRead and SirWdat                  *
*               for synchronous with SirSelx                         *
*                                                                    *
\********************************************************************/
always @(posedge Clk or posedge Rst)
begin
    if (Rst == 1'b1)
        begin
            SirAddrx <= 16'h00;
            SirWdatx <= 32'h0000_0000;
        end
    else
        begin
            SirAddrx <= #`UDLY SirAddr[(SLAVE_SIZE-1):0];   
            SirWdatx <= #`UDLY SirWdat;                  
        end
end

/********************************************************************\
*                                                                    *
*               Address decoder                                      *
*                                                                    *
\********************************************************************/
reg SirSel00Pre,SirSel10Pre,SirSel11Pre,SirSel12Pre;   
reg SirSel14Pre,SirSel15Pre,SirSel16Pre,SirSel17Pre;     
reg SirSel18Pre,SirSel19Pre,SirSel1aPre,SirSel1bPre;     
reg SirSel1ePre,SirSel1fPre,SirSel20Pre,SirSel40Pre;
reg SirSel110Pre;

reg SirSel00PreL1,SirSel10PreL1,SirSel11PreL1,SirSel12PreL1;   
reg SirSel14PreL1,SirSel15PreL1,SirSel16PreL1,SirSel17PreL1;     
reg SirSel18PreL1,SirSel19PreL1,SirSel1aPreL1,SirSel1bPreL1;     
reg SirSel1ePreL1,SirSel1fPreL1,SirSel20PreL1,SirSel40PreL1;        
reg SirSel110PreL1;        

reg SirSel00PreL2,SirSel10PreL2,SirSel11PreL2,SirSel12PreL2;   
reg SirSel14PreL2,SirSel15PreL2,SirSel16PreL2,SirSel17PreL2;     
reg SirSel18PreL2,SirSel19PreL2,SirSel1aPreL2,SirSel1bPreL2;     
reg SirSel1ePreL2,SirSel1fPreL2,SirSel20PreL2,SirSel40PreL2;        
reg SirSel110PreL2;        
   
   
always @(posedge Clk or posedge Rst)
begin
    if (Rst == 1'b1)
        begin
            SirSel00Pre 	<= 1'b0;
			SirSel10Pre 	<= 1'b0;
			SirSel11Pre 	<= 1'b0;
			SirSel12Pre 	<= 1'b0;
			SirSel14Pre 	<= 1'b0;
			SirSel15Pre 	<= 1'b0;
			SirSel16Pre 	<= 1'b0;
			SirSel17Pre 	<= 1'b0;
			SirSel18Pre 	<= 1'b0;
			SirSel19Pre 	<= 1'b0;
			SirSel1aPre 	<= 1'b0;
			SirSel1bPre 	<= 1'b0;
			SirSel1ePre 	<= 1'b0;
            SirSel1fPre 	<= 1'b0;
            SirSel20Pre 	<= 1'b0;
            SirSel40Pre 	<= 1'b0;
            SirSel110Pre 	<= 1'b0;
        end
    else                                                                // support 2^(BASE_SIZE - SLAVE_SIZE) slaves
        begin
            SirSel00Pre 	<= #`UDLY SirSel & (SirAddr[(BASE_SIZE-1):SLAVE_SIZE] == 12'h00);
            SirSel10Pre 	<= #`UDLY SirSel & (SirAddr[(BASE_SIZE-1):SLAVE_SIZE] == 12'h10);
            SirSel11Pre 	<= #`UDLY SirSel & (SirAddr[(BASE_SIZE-1):SLAVE_SIZE] == 12'h11);
            SirSel12Pre 	<= #`UDLY SirSel & (SirAddr[(BASE_SIZE-1):SLAVE_SIZE] == 12'h12);
			SirSel14Pre 	<= #`UDLY SirSel & (SirAddr[(BASE_SIZE-1):SLAVE_SIZE] == 12'h14);
			SirSel15Pre 	<= #`UDLY SirSel & (SirAddr[(BASE_SIZE-1):SLAVE_SIZE] == 12'h15);
			SirSel16Pre 	<= #`UDLY SirSel & (SirAddr[(BASE_SIZE-1):SLAVE_SIZE] == 12'h16);
			SirSel17Pre 	<= #`UDLY SirSel & (SirAddr[(BASE_SIZE-1):SLAVE_SIZE] == 12'h17);
			SirSel18Pre 	<= #`UDLY SirSel & (SirAddr[(BASE_SIZE-1):SLAVE_SIZE] == 12'h18);
			SirSel19Pre 	<= #`UDLY SirSel & (SirAddr[(BASE_SIZE-1):SLAVE_SIZE] == 12'h19);
			SirSel1aPre 	<= #`UDLY SirSel & (SirAddr[(BASE_SIZE-1):SLAVE_SIZE] == 12'h1a);
			SirSel1bPre 	<= #`UDLY SirSel & (SirAddr[(BASE_SIZE-1):SLAVE_SIZE] == 12'h1b);
			SirSel1ePre 	<= #`UDLY SirSel & (SirAddr[(BASE_SIZE-1):SLAVE_SIZE] == 12'h1e);
            SirSel1fPre 	<= #`UDLY SirSel & (SirAddr[(BASE_SIZE-1):SLAVE_SIZE] == 12'h1f);
            SirSel20Pre 	<= #`UDLY SirSel & (SirAddr[(BASE_SIZE-1):SLAVE_SIZE] == 12'h20);
            SirSel40Pre 	<= #`UDLY SirSel & (SirAddr[(BASE_SIZE-1):SLAVE_SIZE] == 12'h40);
            SirSel110Pre 	<= #`UDLY SirSel & (SirAddr[(BASE_SIZE-1):SLAVE_SIZE] == 12'h110);
        end
end

always @(posedge Clk or posedge Rst)
begin
       if (Rst == 1'b1)
        begin
            SirSel00PreL1 	<= 1'b0;
            SirSel10PreL1 	<= 1'b0;
            SirSel11PreL1 	<= 1'b0;
            SirSel12PreL1 	<= 1'b0;
			SirSel14PreL1 	<= 1'b0;
			SirSel15PreL1 	<= 1'b0;
			SirSel16PreL1 	<= 1'b0;
			SirSel17PreL1 	<= 1'b0;
			SirSel18PreL1 	<= 1'b0;
			SirSel19PreL1 	<= 1'b0;
			SirSel1aPreL1 	<= 1'b0;
			SirSel1bPreL1 	<= 1'b0;
			SirSel1ePreL1 	<= 1'b0;
            SirSel1fPreL1 	<= 1'b0;
            SirSel20PreL1 	<= 1'b0;
            SirSel40PreL1 	<= 1'b0;
            SirSel110PreL1 	<= 1'b0;
            
            SirSel00PreL2 	<= 1'b0;
            SirSel10PreL2 	<= 1'b0;
            SirSel11PreL2 	<= 1'b0;
            SirSel12PreL2 	<= 1'b0;
            SirSel14PreL2 	<= 1'b0;
            SirSel15PreL2 	<= 1'b0;
            SirSel16PreL2 	<= 1'b0;
            SirSel17PreL2 	<= 1'b0;
            SirSel18PreL2 	<= 1'b0;
            SirSel19PreL2 	<= 1'b0;
            SirSel1aPreL2 	<= 1'b0;
            SirSel1bPreL2 	<= 1'b0;
            SirSel1ePreL2 	<= 1'b0;
            SirSel1fPreL2 	<= 1'b0;
            SirSel20PreL2 	<= 1'b0;
            SirSel40PreL2 	<= 1'b0;
            SirSel110PreL2 	<= 1'b0;
        end 
    else                                                                // support 2^(BASE_SIZE - SLAVE_SIZE) slaves
        begin
            SirSel00PreL1 	<= #`UDLY SirSel00Pre;
            SirSel10PreL1 	<= #`UDLY SirSel10Pre;
            SirSel11PreL1 	<= #`UDLY SirSel11Pre;
            SirSel12PreL1 	<= #`UDLY SirSel12Pre;
			SirSel14PreL1 	<= #`UDLY SirSel14Pre;
			SirSel15PreL1 	<= #`UDLY SirSel15Pre;
			SirSel16PreL1 	<= #`UDLY SirSel16Pre;
			SirSel17PreL1 	<= #`UDLY SirSel17Pre;
			SirSel18PreL1 	<= #`UDLY SirSel18Pre;
			SirSel19PreL1 	<= #`UDLY SirSel19Pre;
			SirSel1aPreL1 	<= #`UDLY SirSel1aPre;
			SirSel1bPreL1 	<= #`UDLY SirSel1bPre;
			SirSel1ePreL1 	<= #`UDLY SirSel1ePre;
            SirSel1fPreL1 	<= #`UDLY SirSel1fPre;
            SirSel20PreL1 	<= #`UDLY SirSel20Pre;
            SirSel40PreL1 	<= #`UDLY SirSel40Pre;
            SirSel110PreL1 	<= #`UDLY SirSel110Pre;
            
            SirSel00PreL2 	<= #`UDLY SirSel00PreL1;
            SirSel10PreL2 	<= #`UDLY SirSel10PreL1;
            SirSel11PreL2 	<= #`UDLY SirSel11PreL1;
            SirSel12PreL2 	<= #`UDLY SirSel12PreL1;
            SirSel14PreL2 	<= #`UDLY SirSel14PreL1;
            SirSel15PreL2 	<= #`UDLY SirSel15PreL1;
            SirSel16PreL2 	<= #`UDLY SirSel16PreL1;
            SirSel17PreL2 	<= #`UDLY SirSel17PreL1;
            SirSel18PreL2 	<= #`UDLY SirSel18PreL1;
            SirSel19PreL2 	<= #`UDLY SirSel19PreL1;
            SirSel1aPreL2 	<= #`UDLY SirSel1aPreL1;
            SirSel1bPreL2 	<= #`UDLY SirSel1bPreL1;
            SirSel1ePreL2 	<= #`UDLY SirSel1ePreL1;
            SirSel1fPreL2 	<= #`UDLY SirSel1fPreL1;
            SirSel20PreL2 	<= #`UDLY SirSel20PreL1;
            SirSel40PreL2 	<= #`UDLY SirSel40PreL1;
            SirSel110PreL2 	<= #`UDLY SirSel110PreL1;
        end
end   

always @(posedge Clk or posedge Rst)
begin
    if (Rst == 1'b1)
      begin
         SirSel00 	<= 1'b0;
		 SirSel10 	<= 1'b0;
		 SirSel11 	<= 1'b0;
		 SirSel12 	<= 1'b0;
		 SirSel14 	<= 1'b0;
		 SirSel15 	<= 1'b0;
		 SirSel16 	<= 1'b0;
		 SirSel17 	<= 1'b0;
		 SirSel18 	<= 1'b0;
		 SirSel19 	<= 1'b0;
		 SirSel1a 	<= 1'b0;
		 SirSel1b 	<= 1'b0;
		 SirSel1e 	<= 1'b0;
		 SirSel1f 	<= 1'b0;
		 SirSel20 	<= 1'b0;
		 SirSel40 	<= 1'b0;
		 SirSel110 	<= 1'b0;
	  end
	else
	  begin
         SirSel00 	<= #`UDLY SirSel00PreL2;
		 SirSel10 	<= #`UDLY SirSel10PreL2;
		 SirSel11 	<= #`UDLY SirSel11PreL2;
		 SirSel12 	<= #`UDLY SirSel12PreL2;
		 SirSel14 	<= #`UDLY SirSel14PreL2;
		 SirSel15 	<= #`UDLY SirSel15PreL2;
		 SirSel16 	<= #`UDLY SirSel16PreL2;
		 SirSel17 	<= #`UDLY SirSel17PreL2;
		 SirSel18 	<= #`UDLY SirSel18PreL2;
		 SirSel19 	<= #`UDLY SirSel19PreL2;
		 SirSel1a 	<= #`UDLY SirSel1aPreL2;
		 SirSel1b 	<= #`UDLY SirSel1bPreL2;
		 SirSel1e 	<= #`UDLY SirSel1ePreL2;
		 SirSel1f 	<= #`UDLY SirSel1fPreL2;
		 SirSel20 	<= #`UDLY SirSel20PreL2;
		 SirSel40 	<= #`UDLY SirSel40PreL2;
		 SirSel110 	<= #`UDLY SirSel110PreL2;
	  end
end
         
always @(posedge Clk or posedge Rst)
begin    
    if (Rst == 1'b1)
        begin
            SirRead00 	<= 1'b0;
            SirRead10 	<= 1'b0;
            SirRead11 	<= 1'b0;
            SirRead12 	<= 1'b0;
			SirRead14 	<= 1'b0;
			SirRead15 	<= 1'b0;
			SirRead16 	<= 1'b0;
			SirRead17 	<= 1'b0;
			SirRead18 	<= 1'b0;
			SirRead19 	<= 1'b0;
			SirRead1a 	<= 1'b0;
			SirRead1b 	<= 1'b0;
			SirRead1e 	<= 1'b0;
			SirRead1f 	<= 1'b0;
			SirRead20 	<= 1'b0;
			SirRead40 	<= 1'b0;
			SirRead110 	<= 1'b0;
        end
    else
        begin
            SirRead00 	<= #`UDLY SirRead & (SirAddr[(BASE_SIZE-1):SLAVE_SIZE] == 12'h00);
            SirRead10 	<= #`UDLY SirRead & (SirAddr[(BASE_SIZE-1):SLAVE_SIZE] == 12'h10);
            SirRead11 	<= #`UDLY SirRead & (SirAddr[(BASE_SIZE-1):SLAVE_SIZE] == 12'h11);
            SirRead12 	<= #`UDLY SirRead & (SirAddr[(BASE_SIZE-1):SLAVE_SIZE] == 12'h12);
			SirRead14 	<= #`UDLY SirRead & (SirAddr[(BASE_SIZE-1):SLAVE_SIZE] == 12'h14);
			SirRead15 	<= #`UDLY SirRead & (SirAddr[(BASE_SIZE-1):SLAVE_SIZE] == 12'h15);
			SirRead16 	<= #`UDLY SirRead & (SirAddr[(BASE_SIZE-1):SLAVE_SIZE] == 12'h16);
			SirRead17 	<= #`UDLY SirRead & (SirAddr[(BASE_SIZE-1):SLAVE_SIZE] == 12'h17);
			SirRead18 	<= #`UDLY SirRead & (SirAddr[(BASE_SIZE-1):SLAVE_SIZE] == 12'h18);
			SirRead19 	<= #`UDLY SirRead & (SirAddr[(BASE_SIZE-1):SLAVE_SIZE] == 12'h19);
			SirRead1a 	<= #`UDLY SirRead & (SirAddr[(BASE_SIZE-1):SLAVE_SIZE] == 12'h1a);
			SirRead1b 	<= #`UDLY SirRead & (SirAddr[(BASE_SIZE-1):SLAVE_SIZE] == 12'h1b);
			SirRead1e 	<= #`UDLY SirRead & (SirAddr[(BASE_SIZE-1):SLAVE_SIZE] == 12'h1e);
			SirRead1f 	<= #`UDLY SirRead & (SirAddr[(BASE_SIZE-1):SLAVE_SIZE] == 12'h1f);
			SirRead20 	<= #`UDLY SirRead & (SirAddr[(BASE_SIZE-1):SLAVE_SIZE] == 12'h20);
			SirRead40 	<= #`UDLY SirRead & (SirAddr[(BASE_SIZE-1):SLAVE_SIZE] == 12'h40);
			SirRead110 	<= #`UDLY SirRead & (SirAddr[(BASE_SIZE-1):SLAVE_SIZE] == 12'h110);
        end
end


endmodule
