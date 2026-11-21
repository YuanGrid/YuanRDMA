module   iic_slave(

 rst,
 clk,

 iic_scl,
 iic_sda,

 sir_addr ,
 sir_read ,
 sir_wdat ,
 sir_sel  ,
 sir_dack ,
 sir_rdat ,
 sir_done ,
 
 i2c_busy
);
parameter   ADDRWIDTH   = 8;
parameter   DATANUMB    = 4;//MAX=4
parameter   DATAWIDTH   = 8*DATANUMB;
parameter   DEVICEID    = 7'h02;//useless now

input                   rst;
input                   clk;
                        
input                   iic_scl;
inout                   iic_sda;

// csr bus
output reg [ADDRWIDTH -1:0]  		sir_addr = 'b0;
output reg            	            sir_read = 'b0;
output reg [DATAWIDTH -1:0]      	sir_wdat = 'b0;
output reg                          sir_sel  = 'b0;
input                               sir_dack;
input      [DATAWIDTH -1:0]         sir_rdat;
input                               sir_done;
output reg                          i2c_busy;
//at24c168

parameter    OptIdl       = 5'b00000;
parameter    OptStart     = 5'b00001; 
parameter    WrStart      = 5'b00010;
parameter    WrDivID      = 5'b00011;
parameter    WrCtrl       = 5'b00100;
parameter    WrAck        = 5'b00101;
parameter    WrRegAdr     = 5'b00110;
parameter    WrRegAck     = 5'b00111;
parameter    RdStart      = 5'b01000;
parameter    RdDivID      = 5'b01001;
parameter    RdCtrl       = 5'b01010;
parameter    RdAck        = 5'b01011;
parameter    RdData       = 5'b01100;
parameter    RdDataNAck   = 5'b01101;
parameter    RdStop       = 5'b01110;
parameter    WrData       = 5'b01111;
parameter    WrDataAck    = 5'b10000;
parameter    WrStop       = 5'b10001;

reg     [4:0]       iic_stat;

reg         scl     ;
reg         scl_r1  ;
reg         sda     ;
reg         sda_r1  ;

always @ (posedge clk or posedge rst)
begin
    if (rst)
       begin
         scl    <= 0;     
         scl_r1 <= 0; 
         sda    <= 0; 
         sda_r1 <= 0; 
       end
    else
       begin 
         scl    <=  iic_scl   ;
         scl_r1 <=   scl              ;
         sda    <=  iic_sda  ;
         sda_r1 <=   sda              ;
       end      
end

wire        negedge_scl; 
wire        posedge_scl;
wire        posedge_sda;
wire        negedge_sda;
wire        start_pos;
wire        end_pos;

assign  negedge_scl = (scl == 1'b0) & (scl_r1 == 1'b1);
assign  posedge_scl = (scl == 1'b1) & (scl_r1 == 1'b0);
assign  posedge_sda = sda & (sda_r1 == 1'b0);
assign  negedge_sda = (sda == 1'b0) & (sda_r1 == 1'b1);
assign  start_pos = negedge_sda & scl_r1;
assign  end_pos = posedge_sda & scl_r1;


reg     [3:0]   DivIDCnt;
reg     [3:0]   RegCnt;
reg     [2:0]   NumCnt;

reg     [6:0]   DivID;
reg     [7:0]   local_adr_latch;
reg             RdFlag;  // 0:write ; 1:read
reg     [31:0]  scl_hcnt;


always @ (posedge clk or posedge rst)
begin
    if (rst)
       iic_stat <= 0;
    else
      case(iic_stat)
         OptIdl     : if (start_pos) iic_stat <= OptStart ; else ;
         OptStart   : if (end_pos)iic_stat <= OptIdl ; else if (negedge_scl)  iic_stat <= WrDivID; else;//iic_stat <= SlotDivID ; else ;
         WrDivID    : if (end_pos)iic_stat <= OptIdl ; else if (DivIDCnt == 4'h7) iic_stat <= WrCtrl ; else ;
         WrCtrl     : if (end_pos || DivID != DEVICEID)iic_stat <= OptIdl ; else if (negedge_scl) iic_stat <= WrAck ; else ;
         WrAck      : if (end_pos)iic_stat <= OptIdl ; else if (RdFlag == 0 && negedge_scl)  iic_stat <= WrRegAdr ;else if (RdFlag == 1 && negedge_scl) iic_stat <= RdData ; else ;
         WrRegAdr   : if (end_pos)iic_stat <= OptIdl ; else if ((negedge_scl)&(RegCnt == 4'h8)) iic_stat <= WrRegAck ; else ;
         WrRegAck   : if (end_pos)iic_stat <= OptIdl ; else if (negedge_scl) iic_stat <= WrData ; else ;
         RdStart    : if (end_pos)iic_stat <= OptIdl ; else if (negedge_scl) iic_stat <= RdDivID ; else ;
         RdDivID    : if (end_pos)iic_stat <= OptIdl ; else if (DivIDCnt == 4'h7) iic_stat <= RdCtrl ; else ;
         RdCtrl     : if (end_pos)iic_stat <= OptIdl ; else if (negedge_scl) iic_stat <= RdAck ; else ;
         RdAck      : if (end_pos)iic_stat <= OptIdl ; else if (negedge_scl) iic_stat <= RdData ; else ;
         RdData     : if (end_pos)iic_stat <= OptIdl ; else if ((negedge_scl)&(RegCnt == 4'h8)) iic_stat <= RdDataNAck ; else ;
         RdDataNAck : if (end_pos)iic_stat <= OptIdl ; else if ((NumCnt == DATANUMB) && negedge_scl) iic_stat <= RdStop;else if (negedge_scl) iic_stat <= RdData; else ;
         RdStop     : if (end_pos)iic_stat <= OptIdl ; else ;
         WrData     : if (end_pos)iic_stat <= OptIdl ; else if (start_pos) iic_stat <= RdStart ;else if ((negedge_scl)&(RegCnt == 4'h8)) iic_stat <= WrDataAck  ;
         WrDataAck  : if (end_pos)iic_stat <= OptIdl ; else if ((NumCnt == DATANUMB) && negedge_scl) iic_stat <= WrStop;else if (negedge_scl) iic_stat <= WrData ; else ;
         WrStop     : if (end_pos)iic_stat <= OptIdl ; else ;
         default    : iic_stat <= 0;
       endcase
end


        
always @ (posedge clk)
begin
    if ((iic_stat == WrDivID) | (iic_stat == RdDivID))
       if ( negedge_scl)   
          DivIDCnt <= DivIDCnt + 4'd1;
       else ;
    else
      DivIDCnt <= 0;
end
             
always @ (posedge clk)
begin
    if ((iic_stat == WrRegAdr) | (iic_stat == RdData) | (iic_stat == WrData))
       if ( posedge_scl)   
          RegCnt <= RegCnt + 4'd1;
       else ;
    else
      RegCnt <= 0;
end

always @ (posedge clk)
begin
    if((iic_stat == RdAck) | (iic_stat == WrRegAck))
        NumCnt <= 3'd1;
    else if ((iic_stat == RdDataNAck) | (iic_stat == WrDataAck))
    begin
       if (negedge_scl)   
          NumCnt <= NumCnt + 3'd1;
    end
end
            
always @ (posedge clk or posedge rst)
begin
    if (rst)
       DivID <= 0;
    else if ((iic_stat == WrDivID) | (iic_stat == RdDivID))           
       if ( negedge_scl)
          DivID <= {DivID[5:0],sda_r1}; 
end

always @ (posedge clk )
begin
    if (rst)
       RdFlag <= 'b0;
    else if (iic_stat == WrCtrl)           
    begin
       if ( negedge_scl)
          RdFlag <= sda_r1;
       else;
    end 
    else if(end_pos)
       RdFlag <= 'b0;
end

always @ (posedge clk)
begin
    if (iic_stat == WrRegAdr)
       if ( negedge_scl)   
         local_adr_latch <= {local_adr_latch[6:0],sda_r1};         
end

always @ (posedge clk)
begin
    if (iic_stat == WrRegAck)  
      sir_addr  <= local_adr_latch;
end

always @ (posedge clk)
begin
    if (iic_stat == WrData)
       if ( negedge_scl)              
         sir_wdat[DATAWIDTH -1:0] <= {sir_wdat[DATAWIDTH -2:0],sda_r1};  
end
always @ (posedge clk)
begin
    if (rst) 
        sir_read  <= 1'b0;
    else if (iic_stat == RdCtrl || (iic_stat == WrAck && RdFlag == 1'b1))
        sir_read  <= 1'b1;
    else if (iic_stat == RdStop )
        sir_read  <= 1'b0;
end                  

always @ (posedge clk)
begin
    if (rst) 
        sir_sel  <= 1'b0;
    else if (iic_stat == RdStop || iic_stat == WrData || iic_stat == OptIdl)
        sir_sel   <= 1'b0;
    else if (iic_stat == RdCtrl || iic_stat == WrStop || (iic_stat == WrAck && RdFlag == 1'b1))
        sir_sel   <= 1'b1;
end  

reg       sda_out;
reg       sda_out_en;
reg [DATAWIDTH -1:0] rdat_shift;

always @ (posedge clk)
begin
    if (iic_stat == RdAck || (iic_stat == WrAck && RdFlag == 1'b1))   
        rdat_shift <= sir_rdat[DATAWIDTH -1:0];
    else if (iic_stat == RdData)
    begin    
       if(negedge_scl) 
          rdat_shift <= rdat_shift << 1;
    end        
end

//prevent there is no end_pos signal
always @(posedge clk)
begin
    if(rst)
        scl_hcnt <= 32'd0;
    else if(scl_r1 == 1'b0)
        scl_hcnt <= 32'd0;
    else if(scl_r1 == 1'b1)
    begin
        if(scl_hcnt == 500_000) //10ms
            scl_hcnt <= scl_hcnt;
        else 
            scl_hcnt <= scl_hcnt + 1;
    end 
end 

always @(posedge clk)
begin
    if(rst)
        i2c_busy <= 1'b0;
    else if(start_pos)
        i2c_busy <= 1'b1;
    else if(end_pos | scl_hcnt == 500_000)
        i2c_busy <= 1'b0;
end 

always @ (posedge clk)
begin
    if (iic_stat == RdData)       
        sda_out <= rdat_shift[DATAWIDTH -1];
    else
        sda_out <= 0;   
end

always @ (posedge clk)
begin
    if ((iic_stat == WrAck)|(iic_stat == WrRegAck)| (iic_stat ==RdAck)|(iic_stat ==RdData)|(iic_stat ==WrDataAck))//|(iic_stat ==RdDataNAck && NumCnt != DATANUMB))     
         sda_out_en <= 1;
    else
       sda_out_en <= 0;    
end

assign  iic_sda = sda_out_en ? sda_out : 1'bz;

endmodule
