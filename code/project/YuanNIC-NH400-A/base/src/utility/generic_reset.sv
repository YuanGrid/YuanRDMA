module generic_reset #(
    parameter int NUM_INPUT_CLK    = 1,
    parameter int SAMPLE_CLK_INDEX = 0,
    parameter int RESET_DURATION   = 100 //小于1024
) (
    // Reset handshake signals from the system configuration block
    input                      mod_clk,
    input                      mod_rstn,
    output                     mod_rst_done,

    // One reset generated for each clock domain
    input  [NUM_INPUT_CLK-1:0] clk,
    output [NUM_INPUT_CLK-1:0] rstn
);
    reg     [5:0]               mod_rstn_d;
    reg     [7:0]               rst_cnt;
    reg                         rstn_reg;
    reg     [2:0]               rstn_reg_d[NUM_INPUT_CLK-1:0];
    reg                         mod_rst_done_reg;

    always @(posedge mod_clk ) begin
        if(!mod_rstn)
            mod_rstn_d[1:0] <= {mod_rstn_d[0],1'b0};
        else 
            mod_rstn_d[1:0] <= {mod_rstn_d[0],1'b1};

        if(mod_rstn_d[1] & (!mod_rstn_d[0]))
            mod_rstn_d[2] <= 1'b0;
        else if(mod_rst_done_reg)
            mod_rstn_d[2] <= 1'b1;

        mod_rstn_d[5:3] <= mod_rstn_d[4:2];
    end

    always @(posedge mod_clk ) begin
        if(rst_cnt > 10'd0)
            rst_cnt <= rst_cnt + 1'd1;
        else if(mod_rstn_d[5:2] == 0)
            rst_cnt <= 10'd1;
        else 
            rst_cnt <= 10'd0;
    end

    assign mod_rst_done = mod_rst_done_reg;
    
    always @(posedge mod_clk ) begin
        if(rst_cnt > 0 & rst_cnt < RESET_DURATION)begin 
            rstn_reg         <= 1'b0;
        end else begin 
            rstn_reg         <= 1'b1;
        end  
    end

    always @(posedge mod_clk ) begin
        if(rst_cnt > RESET_DURATION)begin 
            mod_rst_done_reg <= 1'b1;
        end else begin 
            mod_rst_done_reg <= 1'b0;
        end  
    end

    generate
        for (genvar i=0 ; i<NUM_INPUT_CLK ; i=i+1) begin
            assign rstn[i] = rstn_reg_d[i][2];
            always @(posedge clk[i] ) begin
                rstn_reg_d[i][2:0] <= {rstn_reg_d[i][1:0],rstn_reg};
            end
        end
    endgenerate
endmodule