module search_block_min(
    input              i_clk,
    input              i_rst_n,
    input       [7:0]  i_p11, i_p12, i_p13, i_p21, i_p22, i_p23, i_p31, i_p32, i_p33,
    output logic [7:0] o_block_min
);
    logic [7:0] m1, m2, m3;
    logic [7:0] m1_r, m2_r, m3_r;
    logic [7:0] final_min_comb;

    always_comb begin
        m1 = (i_p11 < i_p12) ? ((i_p11 < i_p13) ? i_p11 : i_p13) : ((i_p12 < i_p13) ? i_p12 : i_p13);
        m2 = (i_p21 < i_p22) ? ((i_p21 < i_p23) ? i_p21 : i_p23) : ((i_p22 < i_p23) ? i_p22 : i_p23);
        m3 = (i_p31 < i_p32) ? ((i_p31 < i_p33) ? i_p31 : i_p33) : ((i_p32 < i_p33) ? i_p32 : i_p33);
    end

    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            m1_r <= 0; m2_r <= 0; m3_r <= 0;
        end else begin
            m1_r <= m1; m2_r <= m2; m3_r <= m3;
        end
    end

    assign final_min_comb = (m1_r < m2_r) ? ((m1_r < m3_r) ? m1_r : m3_r) : ((m2_r < m3_r) ? m2_r : m3_r);

    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) o_block_min <= 8'd0;
        else          o_block_min <= final_min_comb;
    end
endmodule
