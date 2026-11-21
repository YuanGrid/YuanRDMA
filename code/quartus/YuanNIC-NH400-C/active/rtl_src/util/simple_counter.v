module cnt #(
    parameter       WIDTH           = 32
)   
(   
    input   wire                    clear,
    input   wire                    clk,
    input   wire                    vld,
    input   wire    [15:0]          step,
    output  reg     [WIDTH-1:0]     cnt
);
    localparam HALF_W   =   WIDTH/2;
    reg     [HALF_W:0]      low_cnt;
    reg     [HALF_W-1:0]    high_cnt;
    reg                     vld_1d;
    reg                     vld_2d;

    always @(posedge clk ) begin
        vld_2d <= vld_1d;
        vld_1d <= vld;
    end

    always @(posedge clk ) begin
        if(clear)
            low_cnt <= {(HALF_W+1){1'b0}};
        else if(vld)
            low_cnt <= low_cnt[HALF_W-1:0] + step;

        if(low_cnt[HALF_W])
            low_cnt[HALF_W] <= 1'b0;
    end

    always @(posedge clk ) begin
        if(clear)
            high_cnt <= {(HALF_W){1'b0}};
        else if(low_cnt[HALF_W])
            high_cnt <= high_cnt + 1'b1;
    end

    always @(posedge clk ) begin
        if(clear)
            cnt <= {WIDTH{1'b0}};
        else if(vld_2d)
            cnt <= {high_cnt,low_cnt[HALF_W-1:0]};
    end

endmodule