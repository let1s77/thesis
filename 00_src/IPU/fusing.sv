//==============================================================================
// Module: fusing
// Description:
//   Haze-removal/fusing arithmetic block.
//
//   For each channel:
//     tx_used   = max(tx_raw, TX_MIN)
//     value_tem = ((src - A_c) << 8) + A_c * tx_used
//     out       = value_tem / tx_used
//
//   Output keeps low 8 bits to match legacy RTL behavior.
//   One-cycle registered output.
//==============================================================================

module fusing #(
    parameter logic [7:0] TX_MIN = 8'd15
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic       i_valid,

    input  logic [7:0] i_tx_raw,
    input  logic [7:0] i_A_r,
    input  logic [7:0] i_A_g,
    input  logic [7:0] i_A_b,
    input  logic [7:0] i_src_r,
    input  logic [7:0] i_src_g,
    input  logic [7:0] i_src_b,

    output logic       o_valid,
    output logic [7:0] o_tx_used,
    output logic [7:0] o_out_r,
    output logic [7:0] o_out_g,
    output logic [7:0] o_out_b
);

    logic [7:0] tx_used;

    logic signed [8:0]  diff_r, diff_g, diff_b;
    logic        [15:0] mul_A_tx_r, mul_A_tx_g, mul_A_tx_b;
    logic signed [16:0] value_tem_r, value_tem_g, value_tem_b;
    logic signed [10:0] q_r, q_g, q_b;
    logic [7:0] out_r_comb;
    logic [7:0] out_g_comb;
    logic [7:0] out_b_comb;

    always_comb begin
        tx_used = (i_tx_raw < TX_MIN) ? TX_MIN : i_tx_raw;

        diff_r   = $signed({1'b0, i_src_r}) - $signed({1'b0, i_A_r});
        diff_g   = $signed({1'b0, i_src_g}) - $signed({1'b0, i_A_g});
        diff_b   = $signed({1'b0, i_src_b}) - $signed({1'b0, i_A_b});

        mul_A_tx_r = i_A_r * tx_used;
        mul_A_tx_g = i_A_g * tx_used;
        mul_A_tx_b = i_A_b * tx_used;

        value_tem_r = (diff_r <<< 8) + $signed({1'b0, mul_A_tx_r});
        value_tem_g = (diff_g <<< 8) + $signed({1'b0, mul_A_tx_g});
        value_tem_b = (diff_b <<< 8) + $signed({1'b0, mul_A_tx_b});

        if (tx_used == 8'd0) begin
            q_r = 11'sd0;
            q_g = 11'sd0;
            q_b = 11'sd0;
        end else begin
            q_r = value_tem_r / $signed({1'b0, tx_used});
            q_g = value_tem_g / $signed({1'b0, tx_used});
            q_b = value_tem_b / $signed({1'b0, tx_used});
        end

        // Clamp instead of truncating signed values to avoid wrap-around color artifacts.
        if (q_r < 0) out_r_comb = 8'd0;
        else if (q_r > 11'sd255) out_r_comb = 8'd255;
        else out_r_comb = q_r[7:0];

        if (q_g < 0) out_g_comb = 8'd0;
        else if (q_g > 11'sd255) out_g_comb = 8'd255;
        else out_g_comb = q_g[7:0];

        if (q_b < 0) out_b_comb = 8'd0;
        else if (q_b > 11'sd255) out_b_comb = 8'd255;
        else out_b_comb = q_b[7:0];
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_valid   <= 1'b0;
            o_tx_used <= 8'd0;
            o_out_r   <= 8'd0;
            o_out_g   <= 8'd0;
            o_out_b   <= 8'd0;
        end else begin
            o_valid <= i_valid;
            if (i_valid) begin
                o_tx_used <= tx_used;
                o_out_r   <= out_r_comb;
                o_out_g   <= out_g_comb;
                o_out_b   <= out_b_comb;
            end
        end
    end

endmodule
