// Memory size: 512*512 * 8-bit (Dark channel output)

module RAM (
    input             i_clk,
    input             i_ren,
    input             i_wen,
    input      [17:0] i_addr,
    input      [7:0]  i_data,
    output reg [7:0]  o_data
);

    reg [7:0] mem [((1<<18) - 1) : 0];

    always @(posedge i_clk) begin
        if (i_ren)
            o_data <= mem[i_addr];
        else
            o_data <= 'd0;
    end

    always @(posedge i_clk) begin
        if (i_wen) begin
            mem[i_addr] <= i_data;
        end
    end

endmodule
