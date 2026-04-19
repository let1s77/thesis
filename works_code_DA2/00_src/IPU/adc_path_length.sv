//==============================================================================
// Module: adc_path_length
// Description:
//   Compute d_lambda for each position in a 5x5 window.
//
//   Maps to Python sub-block: path_length_calc
//
//   d_lambda(target) = spatial_total + lambda * dp_total
//
//   where:
//     spatial_total = sum of D8 distances along the fixed path steps
//       D8 = 2 for diagonal step, D8 = 1 for horizontal/vertical step
//     dp_total = sum of pixel distances along path edges (from pixel_distance)
//     lambda = LAMBDA_Q8 / 256  (Q0.8 fixed-point, default 51 ≈ 0.2)
//
//   Spatial distance table (sum of D8 per step):
//     4  3  2  3  4
//     3  2  1  2  3
//     2  1  0  1  2
//     3  2  1  2  3
//     4  3  2  3  4
//
//   Lambda multiplication: lambda_dp = (LAMBDA_Q8 * dp_total) >> 8
//
//   Output: d_lambda [9:0] per position (max = 4 + 0.2*510 ≈ 106)
//   Registered output — 1 pipeline stage.
//==============================================================================

module adc_path_length #(
    parameter logic [7:0] LAMBDA_Q8 = 8'd51   // λ ≈ 0.199 ≈ 0.2
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic       i_valid,

    // dp_total inputs from adc_pixel_distance (9-bit each)
    input  logic [8:0] dp00, dp01, dp02, dp03, dp04,
    input  logic [8:0] dp10, dp11, dp12, dp13, dp14,
    input  logic [8:0] dp20, dp21, dp22, dp23, dp24,
    input  logic [8:0] dp30, dp31, dp32, dp33, dp34,
    input  logic [8:0] dp40, dp41, dp42, dp43, dp44,

    // d_lambda outputs (10-bit each)
    output logic [9:0] dl00, dl01, dl02, dl03, dl04,
    output logic [9:0] dl10, dl11, dl12, dl13, dl14,
    output logic [9:0] dl20, dl21, dl22, dl23, dl24,
    output logic [9:0] dl30, dl31, dl32, dl33, dl34,
    output logic [9:0] dl40, dl41, dl42, dl43, dl44,

    output logic       o_valid
);

    // ----------------------------------------------------------------
    // Lambda multiplication helper:
    //   lambda_dp = (LAMBDA_Q8 * dp_total) >> 8
    //   dp_total is 9-bit, LAMBDA_Q8 is 8-bit → product is 17-bit
    //   Result after >>8 is at most (255*510)>>8 = 507 → fits in 9 bits
    //   In practice with LAMBDA_Q8=51: max = (51*510)>>8 = 101
    // ----------------------------------------------------------------
    function automatic logic [9:0] lambda_mul(
        input logic [8:0] dp_total
    );
        logic [17:0] prod;
        prod = dp_total * LAMBDA_Q8;
        return prod[17:8];  // >>8, take 10 bits
    endfunction

    // ----------------------------------------------------------------
    // Combinational: d_lambda = spatial + lambda_mul(dp_total)
    // ----------------------------------------------------------------
    logic [9:0] c_dl00, c_dl01, c_dl02, c_dl03, c_dl04;
    logic [9:0] c_dl10, c_dl11, c_dl12, c_dl13, c_dl14;
    logic [9:0] c_dl20, c_dl21, c_dl22, c_dl23, c_dl24;
    logic [9:0] c_dl30, c_dl31, c_dl32, c_dl33, c_dl34;
    logic [9:0] c_dl40, c_dl41, c_dl42, c_dl43, c_dl44;

    always_comb begin
        // Spatial table:  4  3  2  3  4
        //                 3  2  1  2  3
        //                 2  1  0  1  2
        //                 3  2  1  2  3
        //                 4  3  2  3  4
        c_dl00 = 10'd4 + lambda_mul(dp00);
        c_dl01 = 10'd3 + lambda_mul(dp01);
        c_dl02 = 10'd2 + lambda_mul(dp02);
        c_dl03 = 10'd3 + lambda_mul(dp03);
        c_dl04 = 10'd4 + lambda_mul(dp04);

        c_dl10 = 10'd3 + lambda_mul(dp10);
        c_dl11 = 10'd2 + lambda_mul(dp11);
        c_dl12 = 10'd1 + lambda_mul(dp12);
        c_dl13 = 10'd2 + lambda_mul(dp13);
        c_dl14 = 10'd3 + lambda_mul(dp14);

        c_dl20 = 10'd2 + lambda_mul(dp20);
        c_dl21 = 10'd1 + lambda_mul(dp21);
        c_dl22 = 10'd0;  // center
        c_dl23 = 10'd1 + lambda_mul(dp23);
        c_dl24 = 10'd2 + lambda_mul(dp24);

        c_dl30 = 10'd3 + lambda_mul(dp30);
        c_dl31 = 10'd2 + lambda_mul(dp31);
        c_dl32 = 10'd1 + lambda_mul(dp32);
        c_dl33 = 10'd2 + lambda_mul(dp33);
        c_dl34 = 10'd3 + lambda_mul(dp34);

        c_dl40 = 10'd4 + lambda_mul(dp40);
        c_dl41 = 10'd3 + lambda_mul(dp41);
        c_dl42 = 10'd2 + lambda_mul(dp42);
        c_dl43 = 10'd3 + lambda_mul(dp43);
        c_dl44 = 10'd4 + lambda_mul(dp44);
    end

    // ----------------------------------------------------------------
    // Register outputs
    // ----------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            {dl00,dl01,dl02,dl03,dl04} <= '0;
            {dl10,dl11,dl12,dl13,dl14} <= '0;
            {dl20,dl21,dl22,dl23,dl24} <= '0;
            {dl30,dl31,dl32,dl33,dl34} <= '0;
            {dl40,dl41,dl42,dl43,dl44} <= '0;
            o_valid <= 1'b0;
        end else begin
            o_valid <= i_valid;
            if (i_valid) begin
                dl00<=c_dl00; dl01<=c_dl01; dl02<=c_dl02;
                dl03<=c_dl03; dl04<=c_dl04;
                dl10<=c_dl10; dl11<=c_dl11; dl12<=c_dl12;
                dl13<=c_dl13; dl14<=c_dl14;
                dl20<=c_dl20; dl21<=c_dl21; dl22<=c_dl22;
                dl23<=c_dl23; dl24<=c_dl24;
                dl30<=c_dl30; dl31<=c_dl31; dl32<=c_dl32;
                dl33<=c_dl33; dl34<=c_dl34;
                dl40<=c_dl40; dl41<=c_dl41; dl42<=c_dl42;
                dl43<=c_dl43; dl44<=c_dl44;
            end
        end
    end

endmodule
