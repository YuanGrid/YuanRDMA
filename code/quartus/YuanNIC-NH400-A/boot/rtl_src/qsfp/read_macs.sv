`resetall
`default_nettype none
`timescale 1ns / 1ps

module read_macs #(
    parameter READ_WORDS  = 1024,
    parameter SECTOR_ADDR = 32'h07ff0000,
    parameter TIMEOUT_VAL = 20000000 ,
    parameter WAIT_VAL    = 250000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    output reg         busy,
    output reg         done,
    output reg [1:0]   error,

    output reg  [3:0] avl_addr,
    output reg         avl_write,
    output reg         avl_read,
    output reg  [31:0] avl_writedata,
    input  wire [31:0] avl_readdata,
    input  wire        avl_waitrequest,
    input  wire        avl_readdatavalid,

    output reg  [11:0] ram_addr,
    output reg         ram_we,
    output reg  [31:0] ram_wdata
);

    localparam REG_CMD      = 4'h0;
    localparam REG_CMD_LAST = 4'h1;
    localparam REG_STATUS   = 4'h8;
    localparam REG_RESP     = 4'h5;
    localparam REG_FLV      = 4'h6; 

    localparam CMD_OPEN   = 12'h032; 
    localparam CMD_CLOSE  = 12'h033; 
    localparam CMD_SET_CS = 12'h034; 
    localparam CMD_READ   = 12'h03A; 

    typedef enum reg [3:0] {
        IDLE,
        SEND_CMD_WORD,    
        SEND_CMD_WORD_C,
        POLL_STATUS_REQ,  
        POLL_STATUS_REQ_C,
        POLL_STATUS_WAIT, 
        READ_RESP_REQ,    
        READ_RESP_REQ_C,
        READ_RESP_WAIT,   
        READ_DATA_REQ,    
        READ_DATA_REQ_C,
        READ_DATA_WAIT,   
        NEXT_STEP,
        ERROR_ST,
        DONE_ST
    } state_t;

    state_t state;
    reg [2:0]  step_idx;     
    reg [11:0] word_ptr;     
    reg [31:0] timer;
    reg [23:0] wait_timer;   
    reg        req_accepted; 

    wire [15:0] arg_count = (step_idx == 1) ? 16'd1 : 
                            (step_idx == 2) ? 16'd2 : 
                                              16'd0 ; 

    wire [15:0] total_cmd_words = 1 + arg_count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            {busy, done, error} <= 4'b0;
            {avl_write, avl_read, ram_we} <= 3'b0;
            {timer, word_ptr, step_idx, req_accepted} <= 0;
            wait_timer <= 0;
        end else begin
            ram_we <= 0;
            wait_timer <= 0;

            if (state != IDLE && state != DONE_ST && state != ERROR_ST) begin
                if (timer >= TIMEOUT_VAL) begin
                    state <= ERROR_ST;
                    error <= 2'b10;
                end else timer <= timer + 1;
            end else timer <= 0;

            case (state)
                IDLE: begin
                    done <= 0; error <= 0;
                    if (start) begin
                        state <= SEND_CMD_WORD;
                        busy <= 1; step_idx <= 0; word_ptr <= 0;
                    end
                end

                SEND_CMD_WORD: begin
                    avl_write <= 1;
                    avl_addr <= (word_ptr == total_cmd_words - 1) ? REG_CMD_LAST : REG_CMD;
                    state <= SEND_CMD_WORD_C;
                    if (word_ptr == 0) begin 
                        case (step_idx)
                            0: avl_writedata <= {4'h0, 16'd0, CMD_OPEN};
                            1: avl_writedata <= {4'h0, 16'd1, CMD_SET_CS};
                            2: avl_writedata <= {4'h0, 16'd2, CMD_READ};
                            3: avl_writedata <= {4'h0, 16'd0, CMD_CLOSE};
                        endcase
                    end else begin 
                        if (step_idx == 1) avl_writedata <= 32'h0; 
                        else if (step_idx == 2) begin
                            if (word_ptr == 1) avl_writedata <= SECTOR_ADDR; 
                            else avl_writedata <= READ_WORDS;     
                        end
                    end
                end
                SEND_CMD_WORD_C: begin
                    if (!avl_waitrequest) begin
                        avl_write <= 0;
                        if (word_ptr == total_cmd_words - 1) begin
                            state <= POLL_STATUS_REQ;
                            word_ptr <= 0;
                        end else begin
                            word_ptr <= word_ptr + 1;
                            state <= SEND_CMD_WORD;
                        end
                    end
                end

                POLL_STATUS_REQ: begin
                    if(wait_timer < WAIT_VAL) begin
                        wait_timer <= wait_timer + 1;
                        state <= POLL_STATUS_REQ; 
                    end else begin
                        avl_addr <= REG_STATUS;
                        avl_read <= 1;
                        state <= POLL_STATUS_REQ_C;
                    end
                end

                POLL_STATUS_REQ_C : begin
                    if (!avl_waitrequest) begin
                        avl_read <= 0; 
                        state <= POLL_STATUS_WAIT;
                    end
                end

                POLL_STATUS_WAIT: begin
                    if (avl_readdatavalid) begin
                        if (avl_readdata[0] == 1'b1) state <= READ_RESP_REQ;
                        else state <= POLL_STATUS_REQ; 
                    end
                end

                READ_RESP_REQ: begin
                    if(wait_timer < WAIT_VAL) begin
                        wait_timer <= wait_timer + 1;
                        state <= READ_RESP_REQ; 
                    end else begin
                        avl_addr <= REG_RESP;
                        avl_read <= 1;
                        state <= READ_RESP_REQ_C;
                    end
                end

                READ_RESP_REQ_C: begin
                    if (!avl_waitrequest) begin
                        avl_read <= 0;
                        state <= READ_RESP_WAIT;
                    end
                end

                READ_RESP_WAIT: begin
                    if (avl_readdatavalid) begin
                        if (avl_readdata[11:0] == 12'h000 || avl_readdata[11:0] == 12'h081) begin
                            if (step_idx == 2) begin 
                                state <= READ_DATA_REQ;
                                word_ptr <= 0;
                            end else state <= NEXT_STEP;
                        end else begin
                            state <= ERROR_ST;
                            error <= 2'b01;
                        end
                    end
                end

                READ_DATA_REQ: begin
                    avl_addr <= REG_RESP;
                    avl_read <= 1;
                    state <= READ_DATA_REQ_C;
                end

                READ_DATA_REQ_C: begin
                    if (!avl_waitrequest) begin
                        avl_read <= 0;
                        state <= READ_DATA_WAIT;
                    end
                end

                READ_DATA_WAIT: begin
                    if (avl_readdatavalid) begin
                        ram_we <= 1;
                        ram_addr <= word_ptr;
                        ram_wdata <= avl_readdata;
                        if (word_ptr == READ_WORDS - 1) state <= NEXT_STEP;
                        else begin
                            word_ptr <= word_ptr + 1;
                            state <= READ_DATA_REQ;
                        end
                    end
                end

                NEXT_STEP: begin
                    if(wait_timer < WAIT_VAL) begin
                        wait_timer <= wait_timer + 1;
                        state <= NEXT_STEP; 
                    end else if (step_idx == 3) 
                        state <= DONE_ST;
                    else begin
                        step_idx <= step_idx + 1;
                        word_ptr <= 0;
                        state <= SEND_CMD_WORD;
                    end
                end

                ERROR_ST: begin busy <= 0; state <= IDLE; end
                DONE_ST:  begin busy <= 0; done <= 1; state <= IDLE; end
            endcase
        end
    end
endmodule

`resetall