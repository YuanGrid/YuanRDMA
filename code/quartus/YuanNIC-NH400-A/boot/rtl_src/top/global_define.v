`timescale  1ps/1ps
`define     VER             8'h02
`define     REV             8'h03
`define     SUBVER          16'h0000
`define     YEAR            16'hBA24
`define     MON             8'h12
`define     DATE            8'h04

//csr_define
`define     DMA_MODE        4'h4
`define     PRODUCT_TYPE    16'h4E78
`define     PRODUCT_ID      12'h8
`define     BD_TYPE         32'hA3
`define     BOM_VERSION     4'h0
`define     PCB_VERSION     4'h0


`define		DDR_PRESENT				32'h1
`define		ETH_PRESENT				32'h1
`define		DDR_CH_NUM				8'h1
`define		HW_PORT_NUM				8'h1
`define		PCIE_PORT_NUM			4'h1
`define		PCIE_PORT0_VENDOR_ID	16'h1172
`define		PCIE_PORT0_PF_NUM		8'h1
`define		PCIE_PORT0_SPEED		4'h5
`define		PCIE_PORT0_LANE			8'h10
`define		PCIE_PORT0_PF_DMA_EN	16'h1
`define		PORT0_PF0_DEVICE_ID		16'h0000

`define		DDR_FRE					16'd2666	
`define		DDR_WIDTH				8'd16
`define		DDR_NUM					8'd1			
`define		DIMM_VAL				1'd0
`define		ECC_VAL					1'd0
`define		ECC_WIDTH				8'd0
`define		DDR_TYPE				8'h4
`define		DDR_CAPACITY			8'd16
`define		DDR_DIE					1'b0
`define		COMPONENT_VENDOR		4'h2
`define		COMPONENT_TYPE			8'h0
`define		COMPONENT_WIDTH			8'd16
`define		COMPONENT_CAPACITY		8'd16

//`define ALI_FPGA
//`define MRMAC
`define DCMAC
//`define DC_400G_TOOLKIT
`define DC_200G
`define USE_DCMAC_SLICE
//`define SIM
//`define PR
`define HIGH_POWER 
`define DDR_4NMU
`define fic
//`define PCIE_GEN5X16
//`define ASIC_BRIDGE
//`define DUAL_DIE

`define DDRMC_1
`define DDRMC_2
`define DDRMC_3
`define DDRMC_4

`define ddr_version_type 4'h0001 //4'b0001-2num_2mc_1mig  4'b0010-4num_2mc_1mig 4'b0011-4num_1mc_1mig 4'b0100-4num_2mc_2mig

`define UDLY 1

/****************************************/

`define     DDR_VERSION_TYPE        4'h1
`define     DDR_NUM                 4'h8
`define     NMU_NUM                 8'd16
`define     NMU_TO_DDR              4'h2
`define     DYN_OPEN_FLAG           32'h22af50

/****************************************/

`ifdef  PCIE_GEN5X8
    `ifdef  PCIEX8          //3 pcie ports
        `define PCIE0_VENDOR_ID    16'h10ee  //vendor id ,xilinx-10ee, ali-1ded
        `define PCIE0_PF_NUM       8'h1      
        `define PCIE0_SPEED        4'h5      //pcie gen 5
        `define PCIE0_LANE         8'h8      //pcie x8
        `define PCIE0_PF_DMA_EN    16'h3     //PF0 and 1 use QDMA
        `define PCIE0_PF0_ID       16'hb03f  //pf0 id
        `define PCIE0_PF1_ID       16'hb13f  //pf1 id
        `define PCIE0_PF2_ID       16'h0     //pf2 id 
        `define PCIE0_PF3_ID       16'h0     //pf3 id 
        `define PCIE1_VENDOR_ID    16'h10ee  //vendor id ,xilinx-10ee, ali-1ded 
        `define PCIE1_PF_NUM       8'h1
        `define PCIE1_SPEED        4'h5      //pcie gen 5 
        `define PCIE1_LANE         8'h8      //pcie x8 
        `define PCIE1_PF_DMA_EN    16'h3     //PF0 and 1 use QDMA
        `define PCIE1_PF0_ID       16'hd03f  //pf0 id 
        `define PCIE1_PF1_ID       16'hd13f  //pf1 id 
        `define PCIE1_PF2_ID       16'h0     //pf2 id  
        `define PCIE1_PF3_ID       16'h0     //pf3 id  
        `define PCIE2_VENDOR_ID    16'h10ee  //vendor id ,xilinx-10ee, ali-1ded
        `define PCIE2_PF_NUM       8'h1
        `define PCIE2_SPEED        4'h4      //pcie gen 4 
        `define PCIE2_LANE         8'h8      //pcie x8 
        `define PCIE2_PF_DMA_EN    16'h1
        `define PCIE2_PF0_ID       16'h8038  //??
        `define PCIE2_PF1_ID       16'h0    //??
        `define PCIE2_PF2_ID       16'h0     
        `define PCIE2_PF3_ID       16'h0     
        `define PCIE3_VENDOR_ID    16'h0     
        `define PCIE3_PF_NUM       8'h0
        `define PCIE3_SPEED        4'h0      
        `define PCIE3_LANE         8'h0      
        `define PCIE3_PF_DMA_EN    16'h0
        `define PCIE3_PF0_ID       16'h0     
        `define PCIE3_PF1_ID       16'h0     
        `define PCIE3_PF2_ID       16'h0     
        `define PCIE3_PF3_ID       16'h0     
    `else            //2 ports
        `define PCIE0_VENDOR_ID    16'h1ded 
        `define PCIE0_PF_NUM       8'h1        
        `define PCIE0_SPEED        4'h5      
        `define PCIE0_LANE         8'h8 
        `define PCIE0_PF_DMA_EN    16'h3        
        `define PCIE0_PF0_ID       16'hb03f  
        `define PCIE0_PF1_ID       16'hb13f   
        `define PCIE0_PF2_ID       16'h0      
        `define PCIE0_PF3_ID       16'h0      
        `define PCIE1_VENDOR_ID    16'h1ded
        `define PCIE1_PF_NUM       8'h1
        `define PCIE1_SPEED        4'h5       
        `define PCIE1_LANE         8'h8       
        `define PCIE1_PF_DMA_EN    16'h3
        `define PCIE1_PF0_ID       16'hd03f   
        `define PCIE1_PF1_ID       16'hd13f   
        `define PCIE1_PF2_ID       16'h0      
        `define PCIE1_PF3_ID       16'h0      
        `define PCIE2_VENDOR_ID    16'h0  
        `define PCIE2_PF_NUM       8'h0
        `define PCIE2_SPEED        4'h0      
        `define PCIE2_LANE         8'h0      
        `define PCIE2_PF_DMA_EN    16'h0
        `define PCIE2_PF0_ID       16'h0     
        `define PCIE2_PF1_ID       16'h0     
        `define PCIE2_PF2_ID       16'h0     
        `define PCIE2_PF3_ID       16'h0     
        `define PCIE3_VENDOR_ID    16'h0 
        `define PCIE3_PF_NUM       8'h0
        `define PCIE3_SPEED        4'h0      
        `define PCIE3_LANE         8'h0      
        `define PCIE3_PF_DMA_EN    16'h0
        `define PCIE3_PF0_ID       16'h0     
        `define PCIE3_PF1_ID       16'h0     
        `define PCIE3_PF2_ID       16'h0     
        `define PCIE3_PF3_ID       16'h0     
    `endif
`else
    `ifdef  PCIEX8          //2 pcie ports
        `define PCIE0_VENDOR_ID    16'h10ee  
        `define PCIE0_PF_NUM       8'h4
        `define PCIE0_SPEED        4'h4      
        `define PCIE0_LANE         8'h10     
        `define PCIE0_PF_DMA_EN    16'hf
        `define PCIE0_PF0_ID       16'hb03f  
        `define PCIE0_PF1_ID       16'hb13f   
        `define PCIE0_PF2_ID       16'hb23f   
        `define PCIE0_PF3_ID       16'hb33f   
        `define PCIE1_VENDOR_ID    16'h10ee   
        `define PCIE1_PF_NUM       8'h1
        `define PCIE1_SPEED        4'h4       
        `define PCIE1_LANE         8'h8       
        `define PCIE1_PF_DMA_EN    16'h1
        `define PCIE1_PF0_ID       16'h8038   //??
        `define PCIE1_PF1_ID       16'h0   //??
        `define PCIE1_PF2_ID       16'h0      
        `define PCIE1_PF3_ID       16'h0      
        `define PCIE2_VENDOR_ID    16'h0     
        `define PCIE2_PF_NUM       8'h0
        `define PCIE2_SPEED        4'h0      
        `define PCIE2_LANE         8'h0      
        `define PCIE2_PF_DMA_EN    16'h0
        `define PCIE2_PF0_ID       16'h0     
        `define PCIE2_PF1_ID       16'h0     
        `define PCIE2_PF2_ID       16'h0     
        `define PCIE2_PF3_ID       16'h0     
        `define PCIE3_VENDOR_ID    16'h0     
        `define PCIE3_PF_NUM       8'h0
        `define PCIE3_SPEED        4'h0      
        `define PCIE3_LANE         8'h0      
        `define PCIE3_PF_DMA_EN    16'h0
        `define PCIE3_PF0_ID       16'h0     
        `define PCIE3_PF1_ID       16'h0     
        `define PCIE3_PF2_ID       16'h0     
        `define PCIE3_PF3_ID       16'h0     
    `else            //1 ports
        `define PCIE0_VENDOR_ID    16'h1ded  
        `define PCIE0_PF_NUM       8'h4
        `define PCIE0_SPEED        4'h4      
        `define PCIE0_LANE         8'h10     
        `define PCIE0_PF_DMA_EN    16'h3
        `define PCIE0_PF0_ID       16'h7007  
        `define PCIE0_PF1_ID       16'h7006   
        `define PCIE0_PF2_ID       16'h7005   
        `define PCIE0_PF3_ID       16'h7004   
        `define PCIE1_VENDOR_ID    16'h0      
        `define PCIE1_PF_NUM       8'h0
        `define PCIE1_SPEED        4'h0       
        `define PCIE1_LANE         8'h0       
        `define PCIE1_PF_DMA_EN    16'h0
        `define PCIE1_PF0_ID       16'h0      
        `define PCIE1_PF1_ID       16'h0      
        `define PCIE1_PF2_ID       16'h0      
        `define PCIE1_PF3_ID       16'h0      
        `define PCIE2_VENDOR_ID    16'h0     
        `define PCIE2_PF_NUM       8'h0
        `define PCIE2_SPEED        4'h0      
        `define PCIE2_LANE         8'h0      
        `define PCIE2_PF_DMA_EN    16'h0
        `define PCIE2_PF0_ID       16'h0     
        `define PCIE2_PF1_ID       16'h0     
        `define PCIE2_PF2_ID       16'h0     
        `define PCIE2_PF3_ID       16'h0     
        `define PCIE3_VENDOR_ID    16'h0     
        `define PCIE3_PF_NUM       8'h0
        `define PCIE3_SPEED        4'h0      
        `define PCIE3_LANE         8'h0      
        `define PCIE3_PF_DMA_EN    16'h0
        `define PCIE3_PF0_ID       16'h0     
        `define PCIE3_PF1_ID       16'h0     
        `define PCIE3_PF2_ID       16'h0     
        `define PCIE3_PF3_ID       16'h0     
    `endif
`endif
     
	 
	 
//synthesis translate_off
    `define SIM
    `define XILINX_SIM
//synthesis translate_on
