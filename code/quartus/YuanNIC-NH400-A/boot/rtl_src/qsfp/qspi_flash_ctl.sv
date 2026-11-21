`resetall
`default_nettype none
`timescale 1ns / 1ps

module qspi_flash_ctl #(parameter ADDR_W = 28,
                        parameter DATA_W = 32 )
(
    input   wire                        clk,
    input   wire                        rst_n,
    // AVM Slave Interface
    input   wire    [ADDR_W-1:0]        s_avm_addr ,
    input   wire                        s_avm_read ,
    input   wire                        s_avm_write,
    input   wire    [DATA_W-1:0]        s_avm_wdat ,
    output  wire                        s_avm_wait ,
    output  wire    [DATA_W-1:0]        s_avm_rdat ,
    output  wire                        s_avm_rvld ,
    output  wire    [1:0]               s_avm_rspo ,
    output  wire                        s_avm_wrsp ,

    // AVM Slave Interface from csr_pm to Mailbox
    input   wire    [3:0]               s_csr20_addr,       
    input   wire                        s_csr20_write,         
    input   wire    [31:0]              s_csr20_wdat,     
    input   wire                        s_csr20_read,          
    output  wire    [31:0]              s_csr20_rdat,      
    output  wire                        s_csr20_rvld, 
    output  wire                        s_csr20_wait,
    output  wire                        s_csr20_irq ,   
    

    // AVM Master Interface to Mailbox
    output wire  [3:0]                  m_avm_addr,
    output wire                         m_avm_write,
    output wire                         m_avm_read,
    output wire  [31:0]                 m_avm_wdat,
    input  wire  [31:0]                 m_avm_rdat,
    input  wire                         m_avm_wait,
    input  wire                         m_avm_rvld,
    input  wire                         m_avm_irq
);

    localparam RESTART_RD_ADDR = 28'd4;

    wire [3:0]              avl_avm_addr  ;
    wire                    avl_avm_write ;
    wire                    avl_avm_read  ;
    wire [31:0]             avl_avm_wdat  ;
    wire [31:0]             avl_avm_rdat  ;
    wire                    avl_avm_wait  ;
    wire                    avl_avm_rvld  ;

    wire                    reg_en;
    wire                    reg_we;
    wire [28-1:0]           reg_addr;
    wire         [31:0]     reg_din;
    wire         [31:0]     reg_dout;

    reg [23:0]              wait_counter = 24'd0;
    reg                     read_start = 1'b0;

    wire [31:0]             ram_wrdata;
    wire [11:0]             ram_wraddr;
    wire                    ram_we;

    wire                    read_busy;
    wire                    read_done;
    wire [1:0]              read_error;

    assign m_avm_addr = read_busy? avl_avm_addr : s_csr20_addr;
    assign m_avm_write = read_busy? avl_avm_write : s_csr20_write;
    assign m_avm_read = read_busy? avl_avm_read : s_csr20_read;
    assign m_avm_wdat = read_busy? avl_avm_wdat : s_csr20_wdat;
    
    assign s_csr20_rdat = m_avm_rdat;
    assign s_csr20_rvld = m_avm_rvld;
    assign s_csr20_wait = m_avm_wait;
    assign s_csr20_irq =  m_avm_irq;

    assign avl_avm_rdat = m_avm_rdat;
    assign avl_avm_rvld = m_avm_rvld;
    assign avl_avm_wait = m_avm_wait;
    
    avm_register #(
        .CLOCKING_MODE ("common_clock"),
        .ADDR_W        (ADDR_W),
        .DATA_W        (DATA_W)
    ) avl_reg_inst (
        .avm_addr                     (s_avm_addr         ),
        .avm_read                     (s_avm_read         ),
        .avm_write                    (s_avm_write        ),
        .avm_wdat                     (s_avm_wdat         ),
        .avm_wait                     (s_avm_wait         ),
        .avm_rdat                     (s_avm_rdat         ),
        .avm_rvld                     (s_avm_rvld         ),
        .avm_rspo                     (s_avm_rspo         ),
        .avm_wrsp                     (s_avm_wrsp         ),

        .reg_en         (reg_en),
        .reg_we         (reg_we),
        .reg_addr       (reg_addr),
        .reg_din        (reg_din),
        .reg_dout       (reg_dout),

        .clk        (clk),
        .rst_n      (rst_n)
  );


    always@(posedge clk)
    begin
        if (wait_counter < 24'hffffff)
            wait_counter <= wait_counter + 1'b1;

        read_start <= 1'b0;
        if (wait_counter == 24'hfffffe) // wait 0.134s after fpga boot
            read_start <= 1'b1;
        if(reg_en && reg_we && (reg_addr == RESTART_RD_ADDR)) begin
            read_start <= reg_din[0];
        end
        if (!rst_n) begin
            wait_counter <= 24'h0;
            read_start <= 1'b0;
        end
    end


   read_macs #(
        .READ_WORDS(128),
        .SECTOR_ADDR(32'h07ff0000),
        .TIMEOUT_VAL(20000000)
   )  u00_read_macs(
        .clk(clk),
        .rst_n(rst_n),
        .start(read_start),
        .busy(read_busy),
        .done(read_done),
        .error(read_error),
        // Avalon-MM Master Interface
        .avl_addr         (avl_avm_addr),
        .avl_write        (avl_avm_write),
        .avl_read         (avl_avm_read),
        .avl_writedata    (avl_avm_wdat),
        .avl_readdata     (avl_avm_rdat),
        .avl_waitrequest  (avl_avm_wait),
        .avl_readdatavalid(avl_avm_rvld),
        // RAM Interface
        .ram_addr(ram_wraddr),
        .ram_we(ram_we),
        .ram_wdata(ram_wrdata)
    );


    ram #(
        .ram_block_type     ("M20K" ),
        .widthad_a          (10     ),
        .widthad_b          (10     ),
        .width_a            (32     ),
        .width_b            (32     )
    )
    mac_ram
    (
        .wrclock            (clk          ),
        .wren               (ram_we    ),
        .wraddress          (ram_wraddr[9:0] ),
        .data               (ram_wrdata ),
        .rdclock            (clk          ),
        .rden               (1'b1   ),
        .rdaddress          (reg_addr[11:2] ),
        .q                  (reg_dout )
    );

endmodule
