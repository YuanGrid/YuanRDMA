module cnt #(
        parameter               WIDTH = 32
    ) 
    (
        input   wire            clear,
        input   wire            clk,
        input   wire            vld,
        input   wire[15:0]      step,
        output  reg [WIDTH-1:0] cnt
    );
        always @(posedge clk ) begin
            if(clear)
                cnt <= {WIDTH{1'b0}};
            else if(vld)
                cnt <= cnt + step;
        end
    endmodule