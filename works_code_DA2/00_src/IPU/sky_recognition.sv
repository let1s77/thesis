`timescale 1ns/10ps

module sky_recognition (
    input  logic        i_clk,
    input  logic        i_rst_n,
    input  logic        i_valid,
    input  logic [7:0]  i_gray,     //from grayscale
    input  logic [7:0]  i_dark_ch,     //from dark channel
    input  logic [7:0]  i_A0,     // recognition threshold A0 
    // 1: dùng dark_ch để so sánh, 0: dùng gray để so sánh
    input  logic        i_use_dark,

    output logic        o_valid,
    output logic        o_sky,        // 1: sky, 0: non-sky
    output logic [7:0]  o_sky_bw      // 8'hFF: sky, 8'h00: non-sky
);

    logic [7:0] src_val;
    logic       sky_cond;

    always_comb begin
        src_val  = (i_use_dark) ? i_dark_ch : i_gray;
        sky_cond = (src_val > i_A0);     // đúng theo mô tả: greater than A0
    end

    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            o_valid  <= 1'b0;
            o_sky    <= 1'b0;
            o_sky_bw <= 8'h00;
        end else begin
            o_valid <= i_valid;

            if (i_valid) begin
                o_sky    <= sky_cond;
                o_sky_bw <= sky_cond ? 8'hFF : 8'h00;
            end else begin
                o_sky    <= 1'b0;
                o_sky_bw <= 8'h00;
            end
        end
    end

endmodule
