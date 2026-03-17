//==============================================================================
// Module: adc_ase_masked_min
// Description:
//   Final stage of ADC Estimation: ASE comparison + masked minimum filter.
//
//   For each pixel in the 5x5 window:
//     If d_lambda[i][j] <= r_limit → pixel is IN the ASE → include in min
//     If d_lambda[i][j] >  r_limit → pixel is OUT of ASE → exclude
//
//   The center pixel (2,2) always has d_lambda=0, so it's always included.
//
//   Output: min(pixels in ASE) = Adaptive Dark Channel value
//
//   This is a single-cycle combinational comparator + min tree, registered.
//   Reference: Paper Eq. (10) and Algorithm 1, step 6.
//==============================================================================

module adc_ase_masked_min (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       i_valid,

    // r_limit threshold
    input  logic [9:0] i_rlimit,

    // d_lambda values (for comparison)
    input  logic [9:0] dl00, dl01, dl02, dl03, dl04,
    input  logic [9:0] dl10, dl11, dl12, dl13, dl14,
    input  logic [9:0] dl20, dl21, dl22, dl23, dl24,
    input  logic [9:0] dl30, dl31, dl32, dl33, dl34,
    input  logic [9:0] dl40, dl41, dl42, dl43, dl44,

    // Window pixel values (for min selection)
    input  logic [7:0] pw00, pw01, pw02, pw03, pw04,
    input  logic [7:0] pw10, pw11, pw12, pw13, pw14,
    input  logic [7:0] pw20, pw21, pw22, pw23, pw24,
    input  logic [7:0] pw30, pw31, pw32, pw33, pw34,
    input  logic [7:0] pw40, pw41, pw42, pw43, pw44,

    // ADC output
    output logic [7:0] o_adc,
    output logic       o_valid
);

    // ----------------------------------------------------------------
    // ASE mask: 1 if pixel is within adaptive structuring element
    // ----------------------------------------------------------------
    logic mask [0:4][0:4];

    always_comb begin
        mask[0][0] = (dl00 <= i_rlimit);
        mask[0][1] = (dl01 <= i_rlimit);
        mask[0][2] = (dl02 <= i_rlimit);
        mask[0][3] = (dl03 <= i_rlimit);
        mask[0][4] = (dl04 <= i_rlimit);

        mask[1][0] = (dl10 <= i_rlimit);
        mask[1][1] = (dl11 <= i_rlimit);
        mask[1][2] = (dl12 <= i_rlimit);
        mask[1][3] = (dl13 <= i_rlimit);
        mask[1][4] = (dl14 <= i_rlimit);

        mask[2][0] = (dl20 <= i_rlimit);
        mask[2][1] = (dl21 <= i_rlimit);
        mask[2][2] = 1'b1;                // center always in ASE
        mask[2][3] = (dl23 <= i_rlimit);
        mask[2][4] = (dl24 <= i_rlimit);

        mask[3][0] = (dl30 <= i_rlimit);
        mask[3][1] = (dl31 <= i_rlimit);
        mask[3][2] = (dl32 <= i_rlimit);
        mask[3][3] = (dl33 <= i_rlimit);
        mask[3][4] = (dl34 <= i_rlimit);

        mask[4][0] = (dl40 <= i_rlimit);
        mask[4][1] = (dl41 <= i_rlimit);
        mask[4][2] = (dl42 <= i_rlimit);
        mask[4][3] = (dl43 <= i_rlimit);
        mask[4][4] = (dl44 <= i_rlimit);
    end

    // ----------------------------------------------------------------
    // Masked pixel values: if mask=0, force to 255 (won't affect min)
    // ----------------------------------------------------------------
    logic [7:0] m [0:4][0:4];

    always_comb begin
        m[0][0] = mask[0][0] ? pw00 : 8'hFF;
        m[0][1] = mask[0][1] ? pw01 : 8'hFF;
        m[0][2] = mask[0][2] ? pw02 : 8'hFF;
        m[0][3] = mask[0][3] ? pw03 : 8'hFF;
        m[0][4] = mask[0][4] ? pw04 : 8'hFF;

        m[1][0] = mask[1][0] ? pw10 : 8'hFF;
        m[1][1] = mask[1][1] ? pw11 : 8'hFF;
        m[1][2] = mask[1][2] ? pw12 : 8'hFF;
        m[1][3] = mask[1][3] ? pw13 : 8'hFF;
        m[1][4] = mask[1][4] ? pw14 : 8'hFF;

        m[2][0] = mask[2][0] ? pw20 : 8'hFF;
        m[2][1] = mask[2][1] ? pw21 : 8'hFF;
        m[2][2] = pw22;  // center always included
        m[2][3] = mask[2][3] ? pw23 : 8'hFF;
        m[2][4] = mask[2][4] ? pw24 : 8'hFF;

        m[3][0] = mask[3][0] ? pw30 : 8'hFF;
        m[3][1] = mask[3][1] ? pw31 : 8'hFF;
        m[3][2] = mask[3][2] ? pw32 : 8'hFF;
        m[3][3] = mask[3][3] ? pw33 : 8'hFF;
        m[3][4] = mask[3][4] ? pw34 : 8'hFF;

        m[4][0] = mask[4][0] ? pw40 : 8'hFF;
        m[4][1] = mask[4][1] ? pw41 : 8'hFF;
        m[4][2] = mask[4][2] ? pw42 : 8'hFF;
        m[4][3] = mask[4][3] ? pw43 : 8'hFF;
        m[4][4] = mask[4][4] ? pw44 : 8'hFF;
    end

    // ----------------------------------------------------------------
    // Min tree: find minimum across all 25 masked values
    // Level 1: min of pairs per row (5 values → 3 mins, but keep it simple with cascade)
    // ----------------------------------------------------------------
    // Row mins
    logic [7:0] row_min [0:4];

    always_comb begin
        for (int r = 0; r < 5; r++) begin
            logic [7:0] a, b, c, d, e;
            logic [7:0] ab_min, cd_min, abcd_min;
            a = m[r][0]; b = m[r][1]; c = m[r][2]; d = m[r][3]; e = m[r][4];
            // min of 5 values using 4 comparisons
            ab_min   = (a < b) ? a : b;
            cd_min   = (c < d) ? c : d;
            abcd_min = (ab_min < cd_min) ? ab_min : cd_min;
            row_min[r] = (abcd_min < e) ? abcd_min : e;
        end
    end

    // Final min across 5 rows
    logic [7:0] adc_comb;
    always_comb begin
        logic [7:0] r01_min, r23_min, r0123_min;
        r01_min   = (row_min[0] < row_min[1]) ? row_min[0] : row_min[1];
        r23_min   = (row_min[2] < row_min[3]) ? row_min[2] : row_min[3];
        r0123_min = (r01_min < r23_min) ? r01_min : r23_min;
        adc_comb  = (r0123_min < row_min[4]) ? r0123_min : row_min[4];
    end

    // ----------------------------------------------------------------
    // Register output
    // ----------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_adc   <= 8'd0;
            o_valid <= 1'b0;
        end else begin
            o_valid <= i_valid;
            if (i_valid)
                o_adc <= adc_comb;
        end
    end

endmodule
