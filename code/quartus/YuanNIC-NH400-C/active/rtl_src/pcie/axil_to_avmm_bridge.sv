`resetall
`default_nettype none
`timescale 1ns/1ps

module axil_to_avmm_bridge #(
    parameter int ADDR_W = 32,
    parameter int DATA_W = 32,
    localparam int BYTE_W = DATA_W / 8
) (
    input  wire                 clk,
    input  wire                 rst_n,

    input  wire [ADDR_W-1:0]    s_axil_awaddr,
    input  wire                 s_axil_awvalid,
    output reg                  s_axil_awready,

    input  wire [DATA_W-1:0]    s_axil_wdata,
    input  wire [BYTE_W-1:0]    s_axil_wstrb,
    input  wire                 s_axil_wvalid,
    output reg                  s_axil_wready,

    output reg  [1:0]           s_axil_bresp,
    output reg                  s_axil_bvalid,
    input  wire                 s_axil_bready,

    input  wire [ADDR_W-1:0]    s_axil_araddr,
    input  wire                 s_axil_arvalid,
    output reg                  s_axil_arready,

    output reg  [DATA_W-1:0]    s_axil_rdata,
    output reg  [1:0]           s_axil_rresp,
    output reg                  s_axil_rvalid,
    input  wire                 s_axil_rready,

    output reg  [ADDR_W-1:0]    avm_address,
    output reg                  avm_write,
    output reg                  avm_read,
    output reg  [DATA_W-1:0]    avm_writedata,
    output reg  [BYTE_W-1:0]    avm_byteenable,
    input  wire                 avm_waitrequest,
    input  wire [DATA_W-1:0]    avm_readdata,
    input  wire                 avm_readdatavalid
);

    typedef enum logic [2:0] {
        ST_IDLE      = 3'b000,
        ST_AVM_WRITE = 3'b001,
        ST_AVM_READ  = 3'b010,
        ST_AXI_BRESP = 3'b011,
        ST_AXI_RRESP = 3'b100
    } state_t;

    state_t current_state, next_state;

    reg [ADDR_W-1:0] reg_awaddr;
    reg [DATA_W-1:0] reg_wdata;
    reg [BYTE_W-1:0] reg_wstrb;
    reg              waddr_valid;
    reg              wdata_valid;

    reg [ADDR_W-1:0] reg_araddr;
    reg              raddr_valid;

    always_comb begin
        s_axil_awready = (current_state == ST_IDLE) && !waddr_valid;
        s_axil_wready  = (current_state == ST_IDLE) && !wdata_valid;
        s_axil_arready = (current_state == ST_IDLE) && !raddr_valid;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_awaddr  <= '0;
            waddr_valid <= 1'b0;
        end else if (s_axil_awvalid && s_axil_awready) begin
            reg_awaddr  <= s_axil_awaddr;
            waddr_valid <= 1'b1;
        end else if (s_axil_bvalid && s_axil_bready) begin
            waddr_valid <= 1'b0;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_wdata   <= '0;
            reg_wstrb   <= '0;
            wdata_valid <= 1'b0;
        end else if (s_axil_wvalid && s_axil_wready) begin
            reg_wdata   <= s_axil_wdata;
            reg_wstrb   <= s_axil_wstrb;
            wdata_valid <= 1'b1;
        end else if (s_axil_bvalid && s_axil_bready) begin
            wdata_valid <= 1'b0;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_araddr  <= '0;
            raddr_valid <= 1'b0;
        end else if (s_axil_arvalid && s_axil_arready) begin
            reg_araddr  <= s_axil_araddr;
            raddr_valid <= 1'b1;
        end else if (s_axil_rvalid && s_axil_rready) begin
            raddr_valid <= 1'b0;
        end
    end

    always_comb begin
        next_state = current_state;
        case (current_state)
            ST_IDLE: begin
                if (raddr_valid) begin
                    next_state = ST_AVM_READ;
                end else if (waddr_valid && wdata_valid) begin
                    next_state = ST_AVM_WRITE;
                end
            end

            ST_AVM_WRITE: begin
                if (!avm_waitrequest) begin
                    next_state = ST_AXI_BRESP;
                end
            end

            ST_AVM_READ: begin
                if (!avm_waitrequest) begin
                    next_state = ST_AXI_RRESP;
                end
            end

            ST_AXI_BRESP: begin
                if (s_axil_bvalid && s_axil_bready) begin
                    next_state = ST_IDLE;
                end
            end

            ST_AXI_RRESP: begin
                if (s_axil_rvalid && s_axil_rready) begin
                    next_state = ST_IDLE;
                end
            end

            default: next_state = ST_IDLE;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= ST_IDLE;
        end else begin
            current_state <= next_state;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            avm_address    <= '0;
            avm_write      <= 1'b0;
            avm_read       <= 1'b0;
            avm_writedata  <= '0;
            avm_byteenable <= '0;
        end else begin
            avm_write <= 1'b0;
            avm_read  <= 1'b0;

            case (current_state)
                ST_AVM_WRITE: begin
                    avm_address    <= reg_awaddr >> 1;
                    avm_write      <= 1'b1;
                    avm_writedata  <= reg_wdata;
                    avm_byteenable <= reg_wstrb;
                end

                ST_AVM_READ: begin
                    avm_address    <= reg_araddr >> 1;
                    avm_read       <= 1'b1;
                    avm_writedata  <= '0;
                    avm_byteenable <= '1;
                end

                default: begin
                    avm_writedata  <= '0;
                    avm_byteenable <= avm_byteenable;
                end
            endcase
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axil_bvalid <= 1'b0;
            s_axil_bresp  <= 2'b00;
        end else begin
            if (current_state == ST_AVM_WRITE && !avm_waitrequest) begin
                s_axil_bvalid <= 1'b1;
                s_axil_bresp  <= 2'b00;
            end else if (s_axil_bvalid && s_axil_bready) begin
                s_axil_bvalid <= 1'b0;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axil_rvalid <= 1'b0;
            s_axil_rdata  <= '0;
            s_axil_rresp  <= 2'b00;
        end else begin
            if (current_state == ST_AXI_RRESP && avm_readdatavalid && !s_axil_rvalid) begin
                s_axil_rdata  <= avm_readdata;
                s_axil_rresp  <= 2'b00;
                s_axil_rvalid <= 1'b1;
            end else if (s_axil_rvalid && s_axil_rready) begin
                s_axil_rvalid <= 1'b0;
            end
        end
    end

endmodule
