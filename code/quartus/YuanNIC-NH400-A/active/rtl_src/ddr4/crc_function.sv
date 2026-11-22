


function [31:0] crc32d1;
   input [0:0]  data_in;
   input [31:0] crc_in;
   reg [31:0] 	lfsr_q,lfsr_c;
   begin
	  lfsr_q = crc_in;
	  
	  lfsr_c[0] = lfsr_q[31] ^ data_in[0];
      lfsr_c[1] = lfsr_q[0] ^ lfsr_q[31] ^ data_in[0];
      lfsr_c[2] = lfsr_q[1] ^ lfsr_q[31] ^ data_in[0];
      lfsr_c[3] = lfsr_q[2];
      lfsr_c[4] = lfsr_q[3] ^ lfsr_q[31] ^ data_in[0];
      lfsr_c[5] = lfsr_q[4] ^ lfsr_q[31] ^ data_in[0];
      lfsr_c[6] = lfsr_q[5];
      lfsr_c[7] = lfsr_q[6] ^ lfsr_q[31] ^ data_in[0];
      lfsr_c[8] = lfsr_q[7] ^ lfsr_q[31] ^ data_in[0];
      lfsr_c[9] = lfsr_q[8];
      lfsr_c[10] = lfsr_q[9] ^ lfsr_q[31] ^ data_in[0];
      lfsr_c[11] = lfsr_q[10] ^ lfsr_q[31] ^ data_in[0];
      lfsr_c[12] = lfsr_q[11] ^ lfsr_q[31] ^ data_in[0];
      lfsr_c[13] = lfsr_q[12];
      lfsr_c[14] = lfsr_q[13];
      lfsr_c[15] = lfsr_q[14];
      lfsr_c[16] = lfsr_q[15] ^ lfsr_q[31] ^ data_in[0];
      lfsr_c[17] = lfsr_q[16];
      lfsr_c[18] = lfsr_q[17];
      lfsr_c[19] = lfsr_q[18];
      lfsr_c[20] = lfsr_q[19];
      lfsr_c[21] = lfsr_q[20];
      lfsr_c[22] = lfsr_q[21] ^ lfsr_q[31] ^ data_in[0];
      lfsr_c[23] = lfsr_q[22] ^ lfsr_q[31] ^ data_in[0];
      lfsr_c[24] = lfsr_q[23];
      lfsr_c[25] = lfsr_q[24];
      lfsr_c[26] = lfsr_q[25] ^ lfsr_q[31] ^ data_in[0];
      lfsr_c[27] = lfsr_q[26];
      lfsr_c[28] = lfsr_q[27];
      lfsr_c[29] = lfsr_q[28];
      lfsr_c[30] = lfsr_q[29];
      lfsr_c[31] = lfsr_q[30];
	  
	  crc32d1 = lfsr_c;
   end
endfunction // crc

function [31:0] crc32d160;
   input [159:0] data_in;
   input [31:0]  crc_in;
   integer 		 i;
   reg [31:0] 	 crc_t;
   begin
	  crc_t = crc_in;
	  for (i=159; i >= 0; i=i-1) begin
		 crc_t = crc32d1(data_in[i],crc_t);
	  end
	  crc32d160 = crc_t;
   end
endfunction //

function [31:0] crc32d128;
   input [127:0] data_in;
   input [31:0]  crc_in;
   integer 		 i;
   reg [31:0] 	 crc_t;
   begin
	  crc_t = crc_in;
	  for (i=127; i >= 0; i=i-1) begin
		 crc_t = crc32d1(data_in[i],crc_t);
	  end
	  crc32d128 = crc_t;
   end
endfunction //

function [31:0] crc32d96;
   input [95:0] data_in;
   input [31:0]  crc_in;
   integer 		 i;
   reg [31:0] 	 crc_t;
   begin
	  crc_t = crc_in;
	  for (i=95; i >= 0; i=i-1) begin
		 crc_t = crc32d1(data_in[i],crc_t);
	  end
	  crc32d96 = crc_t;
   end
endfunction //

function [31:0] crc32d16;
   input [15:0] data_in;
   input [31:0]  crc_in;
   integer 		 i;
   reg [31:0] 	 crc_t;
   begin
	  crc_t = crc_in;
	  for (i=15; i >= 0; i=i-1) begin
		 crc_t = crc32d1(data_in[i],crc_t);
	  end
	  crc32d16 = crc_t;
   end
endfunction //


//-----------------------------------------------------------------------------
// CRC module for data[0:0] ,   crc[31:0]=1+x^5+x^8+x^9+x^10+x^11+x^13+x^14+x^18+x^19+x^20+x^22+x^23+x^25+x^26+x^27+x^28+x^32;
//-----------------------------------------------------------------------------
function [31:0] crc32cd1;
   input [0:0] data_in;
   input [31:0] crc_in;
   reg [31:0] 	lfsr_q,lfsr_c;
   begin
	  lfsr_q = crc_in;
	  
	  lfsr_c[0] = lfsr_q[31] ^ data_in[0];
      lfsr_c[1] = lfsr_q[0];
      lfsr_c[2] = lfsr_q[1];
      lfsr_c[3] = lfsr_q[2];
      lfsr_c[4] = lfsr_q[3];
      lfsr_c[5] = lfsr_q[4] ^ lfsr_q[31] ^ data_in[0];
      lfsr_c[6] = lfsr_q[5];
      lfsr_c[7] = lfsr_q[6];
      lfsr_c[8] = lfsr_q[7] ^ lfsr_q[31] ^ data_in[0];
      lfsr_c[9] = lfsr_q[8] ^ lfsr_q[31] ^ data_in[0];
      lfsr_c[10] = lfsr_q[9] ^ lfsr_q[31] ^ data_in[0];
      lfsr_c[11] = lfsr_q[10] ^ lfsr_q[31] ^ data_in[0];
      lfsr_c[12] = lfsr_q[11];
      lfsr_c[13] = lfsr_q[12] ^ lfsr_q[31] ^ data_in[0];
      lfsr_c[14] = lfsr_q[13] ^ lfsr_q[31] ^ data_in[0];
      lfsr_c[15] = lfsr_q[14];
      lfsr_c[16] = lfsr_q[15];
      lfsr_c[17] = lfsr_q[16];
      lfsr_c[18] = lfsr_q[17] ^ lfsr_q[31] ^ data_in[0];
      lfsr_c[19] = lfsr_q[18] ^ lfsr_q[31] ^ data_in[0];
      lfsr_c[20] = lfsr_q[19] ^ lfsr_q[31] ^ data_in[0];
      lfsr_c[21] = lfsr_q[20];
      lfsr_c[22] = lfsr_q[21] ^ lfsr_q[31] ^ data_in[0];
      lfsr_c[23] = lfsr_q[22] ^ lfsr_q[31] ^ data_in[0];
      lfsr_c[24] = lfsr_q[23];
      lfsr_c[25] = lfsr_q[24] ^ lfsr_q[31] ^ data_in[0];
      lfsr_c[26] = lfsr_q[25] ^ lfsr_q[31] ^ data_in[0];
      lfsr_c[27] = lfsr_q[26] ^ lfsr_q[31] ^ data_in[0];
      lfsr_c[28] = lfsr_q[27] ^ lfsr_q[31] ^ data_in[0];
      lfsr_c[29] = lfsr_q[28];
      lfsr_c[30] = lfsr_q[29];
      lfsr_c[31] = lfsr_q[30];
	  
	  crc32cd1 = lfsr_c;	  
   end
endfunction // crc

function [31:0] crc32cd160;
   input [159:0] data_in;
   input [31:0]  crc_in;
   integer 		 i;
   reg [31:0] 	 crc_t;
   begin
	  crc_t = crc_in;
	  for (i=159; i>=0; i=i-1) begin
		 crc_t = crc32cd1(data_in[i],crc_t);
	  end
	  crc32cd160 = crc_t;
   end
endfunction // crc

function [31:0] crc32cd128;
   input [127:0] data_in;
   input [31:0]  crc_in;
   integer 		 i;
   reg [31:0] 	 crc_t;
   begin
	  crc_t = crc_in;
	  for (i=127; i>=0; i=i-1) begin
		 crc_t = crc32cd1(data_in[i],crc_t);
	  end
	  crc32cd128 = crc_t;
   end
endfunction // crc

function [31:0] crc32cd96;
   input [95:0] data_in;
   input [31:0]  crc_in;
   integer 		 i;
   reg [31:0] 	 crc_t;
   begin
	  crc_t = crc_in;
	  for (i=95; i >= 0; i=i-1) begin
		 crc_t = crc32cd1(data_in[i],crc_t);
	  end
	  crc32cd96 = crc_t;
   end
endfunction //

function [31:0] crc32cd16;
   input [15:0] data_in;
   input [31:0]  crc_in;
   integer 		 i;
   reg [31:0] 	 crc_t;
   begin
	  crc_t = crc_in;
	  for (i=15; i>=0; i=i-1) begin
		 crc_t = crc32cd1(data_in[i],crc_t);
	  end
	  crc32cd16 = crc_t;
   end
endfunction // crc

function [15:0] crc16d1;
   input [0:0]  data_in; 
   input [15:0] crc_in;
   
   reg [15:0] lfsr_q, lfsr_c;
   begin
      lfsr_q = crc_in;     
      lfsr_c[0] = lfsr_q[15] ^ data_in[0];
      lfsr_c[1] = lfsr_q[0];
      lfsr_c[2] = lfsr_q[1] ^ lfsr_q[15] ^ data_in[0];
      lfsr_c[3] = lfsr_q[2];
      lfsr_c[4] = lfsr_q[3];
      lfsr_c[5] = lfsr_q[4];
      lfsr_c[6] = lfsr_q[5];
      lfsr_c[7] = lfsr_q[6];
      lfsr_c[8] = lfsr_q[7];
      lfsr_c[9] = lfsr_q[8];
      lfsr_c[10] = lfsr_q[9];
      lfsr_c[11] = lfsr_q[10];
      lfsr_c[12] = lfsr_q[11];
      lfsr_c[13] = lfsr_q[12];
      lfsr_c[14] = lfsr_q[13];
      lfsr_c[15] = lfsr_q[14] ^ lfsr_q[15] ^ data_in[0];
      
      crc16d1 = lfsr_c;
   end
endfunction

function [15:0] crc16d8;
   input [7:0] data_in;
   input [15:0]  crc_in;
   integer 		 i;
   reg [15:0] 	 crc_t;  
   
   begin
      crc_t = crc_in;
	  for (i=7; i>=0; i=i-1) begin
		 crc_t = crc16d1(data_in[i],crc_t);
	  end 
      crc16d8 = crc_t;      
   end      
endfunction





