// Memory size: 128*128 * 24-bit (RGB input image)

module ROM(
    input             i_clk,
    input             i_ren,
    input      [13:0] i_addr,
    output reg [23:0] o_data
);

    reg [23:0] mem [((1<<14) - 1) : 0];

    always @(posedge i_clk) begin
        if (i_ren)
            o_data <= mem[i_addr];
        else
            o_data <= 'd0;
    end

endmodule
