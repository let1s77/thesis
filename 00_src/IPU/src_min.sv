module src_min(
    input              i_clk,
    input              i_rst_n,
    input       [23:0] i_color,
    output logic [7:0] o_min_rgb
);
    logic [7:0] r, g, b;
    logic [7:0] min_rg, min_rgb_comb;

    always_comb begin
        r = i_color[7:0];
        g = i_color[15:8];
        b = i_color[23:16];
        min_rg = (r < g) ? r : g;
        min_rgb_comb = (min_rg < b) ? min_rg : b;
    end

    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) o_min_rgb <= 8'd0;
        else          o_min_rgb <= min_rgb_comb;
    end
endmodule
