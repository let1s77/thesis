//==============================================================================
// Module: adc_estimation
// Description:
//   Adaptive Dark Channel (ADC) Estimation module.
//   Implements the ASE (Adaptive Structuring Element) based minimum filtering
//   from the paper "Efficient Dehazing Method" (IEEE Access, 2019).
//
//   Maps to Python function: adc_estimation_top(gray5x5, mc5x5, lambd)
//
//   TWO input streams:
//     - Gray (grayscale): used as the "pilot" to compute ASEs
//     - MC (minimum channel): used as the data for the adaptive min filter
//
//   Algorithm flow (per pixel, streaming):
//     1. adc_line_buffer_5x5 × 2:  Build 5x5 windows from gray and MC streams
//     2. adc_pixel_distance:   Edge-based dp_total along fixed paths (gray)
//     3. adc_path_length:      d_lambda = spatial + lambda * dp_total
//     4. adc_rlimit_compute:   r_limit = mean(d_lambda) ≈ sum*41>>10
//     5. adc_ase_masked_min:   mask = (d_lambda <= r_limit), min(MC masked)
//
//   MC window delay chain: 4 cycles to align MC window with rlimit output.
//   (pixel_distance=1 + path_length=1 + rlimit=2 = 4 pipeline stages)
//
// Parameters:
//   IMG_WIDTH, IMG_HEIGHT: image dimensions
//   LAMBDA_Q8: lambda parameter in Q0.8 (default 51 ≈ 0.2)
//==============================================================================

module adc_estimation #(
    parameter int       IMG_WIDTH  = 128,
    parameter int       IMG_HEIGHT = 128,
    parameter logic [7:0] LAMBDA_Q8 = 8'd51
)(
    input  logic       clk,
    input  logic       rst_n,

    // Control
    input  logic       i_enable,

    // Gray input stream (for ASE computation)
    input  logic       i_gray_valid,
    input  logic [7:0] i_gray_pix,

    // MC input stream (for adaptive min filter)
    input  logic       i_mc_valid,
    input  logic [7:0] i_mc_pix,

    // Output stream
    output logic       o_valid,
    output logic [7:0] o_adc_pix,

    // Frame done pulse
    output logic       o_done
);

    localparam int FRAME_PIXELS = IMG_WIDTH * IMG_HEIGHT;

    // ================================================================
    // Stage 0: Two 5x5 Line Buffers (Gray + MC)
    // ================================================================
    // --- Gray window ---
    logic [7:0] gw00, gw01, gw02, gw03, gw04;
    logic [7:0] gw10, gw11, gw12, gw13, gw14;
    logic [7:0] gw20, gw21, gw22, gw23, gw24;
    logic [7:0] gw30, gw31, gw32, gw33, gw34;
    logic [7:0] gw40, gw41, gw42, gw43, gw44;
    logic       gray_win_valid;

    adc_line_buffer_5x5 #(
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT)
    ) u_line_buf_gray (
        .clk    (clk),
        .rst_n  (rst_n),
        .i_valid(i_gray_valid & i_enable),
        .i_pix  (i_gray_pix),
        .p00(gw00), .p01(gw01), .p02(gw02), .p03(gw03), .p04(gw04),
        .p10(gw10), .p11(gw11), .p12(gw12), .p13(gw13), .p14(gw14),
        .p20(gw20), .p21(gw21), .p22(gw22), .p23(gw23), .p24(gw24),
        .p30(gw30), .p31(gw31), .p32(gw32), .p33(gw33), .p34(gw34),
        .p40(gw40), .p41(gw41), .p42(gw42), .p43(gw43), .p44(gw44),
        .o_valid(gray_win_valid)
    );

    // --- MC window ---
    logic [7:0] mw00, mw01, mw02, mw03, mw04;
    logic [7:0] mw10, mw11, mw12, mw13, mw14;
    logic [7:0] mw20, mw21, mw22, mw23, mw24;
    logic [7:0] mw30, mw31, mw32, mw33, mw34;
    logic [7:0] mw40, mw41, mw42, mw43, mw44;
    logic       mc_win_valid;

    adc_line_buffer_5x5 #(
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT)
    ) u_line_buf_mc (
        .clk    (clk),
        .rst_n  (rst_n),
        .i_valid(i_mc_valid & i_enable),
        .i_pix  (i_mc_pix),
        .p00(mw00), .p01(mw01), .p02(mw02), .p03(mw03), .p04(mw04),
        .p10(mw10), .p11(mw11), .p12(mw12), .p13(mw13), .p14(mw14),
        .p20(mw20), .p21(mw21), .p22(mw22), .p23(mw23), .p24(mw24),
        .p30(mw30), .p31(mw31), .p32(mw32), .p33(mw33), .p34(mw34),
        .p40(mw40), .p41(mw41), .p42(mw42), .p43(mw43), .p44(mw44),
        .o_valid(mc_win_valid)
    );

    // ================================================================
    // Stage 1: Pixel Distance (edge-based dp_total from gray window)
    // ================================================================
    logic [8:0] dp00, dp01, dp02, dp03, dp04;
    logic [8:0] dp10, dp11, dp12, dp13, dp14;
    logic [8:0] dp20, dp21, dp22, dp23, dp24;
    logic [8:0] dp30, dp31, dp32, dp33, dp34;
    logic [8:0] dp40, dp41, dp42, dp43, dp44;
    logic       pdist_valid;

    adc_pixel_distance u_pixel_dist (
        .clk    (clk),
        .rst_n  (rst_n),
        .i_valid(gray_win_valid),
        .p00(gw00), .p01(gw01), .p02(gw02), .p03(gw03), .p04(gw04),
        .p10(gw10), .p11(gw11), .p12(gw12), .p13(gw13), .p14(gw14),
        .p20(gw20), .p21(gw21), .p22(gw22), .p23(gw23), .p24(gw24),
        .p30(gw30), .p31(gw31), .p32(gw32), .p33(gw33), .p34(gw34),
        .p40(gw40), .p41(gw41), .p42(gw42), .p43(gw43), .p44(gw44),
        .dp00(dp00), .dp01(dp01), .dp02(dp02), .dp03(dp03), .dp04(dp04),
        .dp10(dp10), .dp11(dp11), .dp12(dp12), .dp13(dp13), .dp14(dp14),
        .dp20(dp20), .dp21(dp21), .dp22(dp22), .dp23(dp23), .dp24(dp24),
        .dp30(dp30), .dp31(dp31), .dp32(dp32), .dp33(dp33), .dp34(dp34),
        .dp40(dp40), .dp41(dp41), .dp42(dp42), .dp43(dp43), .dp44(dp44),
        .o_valid(pdist_valid)
    );

    // ================================================================
    // Stage 2: Path Length d_lambda = spatial + lambda * dp_total
    // ================================================================
    logic [9:0] dl00, dl01, dl02, dl03, dl04;
    logic [9:0] dl10, dl11, dl12, dl13, dl14;
    logic [9:0] dl20, dl21, dl22, dl23, dl24;
    logic [9:0] dl30, dl31, dl32, dl33, dl34;
    logic [9:0] dl40, dl41, dl42, dl43, dl44;
    logic       path_valid;

    adc_path_length #(
        .LAMBDA_Q8(LAMBDA_Q8)
    ) u_path_len (
        .clk    (clk),
        .rst_n  (rst_n),
        .i_valid(pdist_valid),
        .dp00(dp00), .dp01(dp01), .dp02(dp02), .dp03(dp03), .dp04(dp04),
        .dp10(dp10), .dp11(dp11), .dp12(dp12), .dp13(dp13), .dp14(dp14),
        .dp20(dp20), .dp21(dp21), .dp22(dp22), .dp23(dp23), .dp24(dp24),
        .dp30(dp30), .dp31(dp31), .dp32(dp32), .dp33(dp33), .dp34(dp34),
        .dp40(dp40), .dp41(dp41), .dp42(dp42), .dp43(dp43), .dp44(dp44),
        .dl00(dl00), .dl01(dl01), .dl02(dl02), .dl03(dl03), .dl04(dl04),
        .dl10(dl10), .dl11(dl11), .dl12(dl12), .dl13(dl13), .dl14(dl14),
        .dl20(dl20), .dl21(dl21), .dl22(dl22), .dl23(dl23), .dl24(dl24),
        .dl30(dl30), .dl31(dl31), .dl32(dl32), .dl33(dl33), .dl34(dl34),
        .dl40(dl40), .dl41(dl41), .dl42(dl42), .dl43(dl43), .dl44(dl44),
        .o_valid(path_valid)
    );

    // ================================================================
    // Stage 3-4: r_limit computation (2 pipeline stages)
    // ================================================================
    logic [9:0] rl_dl00, rl_dl01, rl_dl02, rl_dl03, rl_dl04;
    logic [9:0] rl_dl10, rl_dl11, rl_dl12, rl_dl13, rl_dl14;
    logic [9:0] rl_dl20, rl_dl21, rl_dl22, rl_dl23, rl_dl24;
    logic [9:0] rl_dl30, rl_dl31, rl_dl32, rl_dl33, rl_dl34;
    logic [9:0] rl_dl40, rl_dl41, rl_dl42, rl_dl43, rl_dl44;
    logic [9:0] rlimit;
    logic       rlimit_valid;

    adc_rlimit_compute u_rlimit (
        .clk    (clk),
        .rst_n  (rst_n),
        .i_valid(path_valid),
        .dl00(dl00), .dl01(dl01), .dl02(dl02), .dl03(dl03), .dl04(dl04),
        .dl10(dl10), .dl11(dl11), .dl12(dl12), .dl13(dl13), .dl14(dl14),
        .dl20(dl20), .dl21(dl21), .dl22(dl22), .dl23(dl23), .dl24(dl24),
        .dl30(dl30), .dl31(dl31), .dl32(dl32), .dl33(dl33), .dl34(dl34),
        .dl40(dl40), .dl41(dl41), .dl42(dl42), .dl43(dl43), .dl44(dl44),
        .dl_d00(rl_dl00), .dl_d01(rl_dl01), .dl_d02(rl_dl02), .dl_d03(rl_dl03), .dl_d04(rl_dl04),
        .dl_d10(rl_dl10), .dl_d11(rl_dl11), .dl_d12(rl_dl12), .dl_d13(rl_dl13), .dl_d14(rl_dl14),
        .dl_d20(rl_dl20), .dl_d21(rl_dl21), .dl_d22(rl_dl22), .dl_d23(rl_dl23), .dl_d24(rl_dl24),
        .dl_d30(rl_dl30), .dl_d31(rl_dl31), .dl_d32(rl_dl32), .dl_d33(rl_dl33), .dl_d34(rl_dl34),
        .dl_d40(rl_dl40), .dl_d41(rl_dl41), .dl_d42(rl_dl42), .dl_d43(rl_dl43), .dl_d44(rl_dl44),
        .o_rlimit(rlimit),
        .o_valid(rlimit_valid)
    );

    // ================================================================
    // MC Window Delay Chain (4 cycles to align with rlimit output)
    //
    // Pipeline latency from gray_win_valid to rlimit_valid:
    //   pixel_distance(1) + path_length(1) + rlimit(2) = 4 cycles
    //
    // mc_win_valid is synchronized with gray_win_valid, so MC window
    // needs exactly 4 stages of delay to arrive at ase_masked_min
    // at the same time as dl_d* and rlimit.
    //
    // Enable signals per delay stage:
    //   Stage 1: mc_win_valid   (cycle T)
    //   Stage 2: pdist_valid    (cycle T+1)
    //   Stage 3: path_valid     (cycle T+2)
    //   Stage 4: path_valid_d1  (cycle T+3, matches rlimit internal valid_s1)
    // ================================================================
    logic path_valid_d1;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) path_valid_d1 <= 1'b0;
        else        path_valid_d1 <= path_valid;
    end
    logic [7:0] mc_d1_00, mc_d1_01, mc_d1_02, mc_d1_03, mc_d1_04;
    logic [7:0] mc_d1_10, mc_d1_11, mc_d1_12, mc_d1_13, mc_d1_14;
    logic [7:0] mc_d1_20, mc_d1_21, mc_d1_22, mc_d1_23, mc_d1_24;
    logic [7:0] mc_d1_30, mc_d1_31, mc_d1_32, mc_d1_33, mc_d1_34;
    logic [7:0] mc_d1_40, mc_d1_41, mc_d1_42, mc_d1_43, mc_d1_44;

    logic [7:0] mc_d2_00, mc_d2_01, mc_d2_02, mc_d2_03, mc_d2_04;
    logic [7:0] mc_d2_10, mc_d2_11, mc_d2_12, mc_d2_13, mc_d2_14;
    logic [7:0] mc_d2_20, mc_d2_21, mc_d2_22, mc_d2_23, mc_d2_24;
    logic [7:0] mc_d2_30, mc_d2_31, mc_d2_32, mc_d2_33, mc_d2_34;
    logic [7:0] mc_d2_40, mc_d2_41, mc_d2_42, mc_d2_43, mc_d2_44;

    logic [7:0] mc_d3_00, mc_d3_01, mc_d3_02, mc_d3_03, mc_d3_04;
    logic [7:0] mc_d3_10, mc_d3_11, mc_d3_12, mc_d3_13, mc_d3_14;
    logic [7:0] mc_d3_20, mc_d3_21, mc_d3_22, mc_d3_23, mc_d3_24;
    logic [7:0] mc_d3_30, mc_d3_31, mc_d3_32, mc_d3_33, mc_d3_34;
    logic [7:0] mc_d3_40, mc_d3_41, mc_d3_42, mc_d3_43, mc_d3_44;

    logic [7:0] mc_d4_00, mc_d4_01, mc_d4_02, mc_d4_03, mc_d4_04;
    logic [7:0] mc_d4_10, mc_d4_11, mc_d4_12, mc_d4_13, mc_d4_14;
    logic [7:0] mc_d4_20, mc_d4_21, mc_d4_22, mc_d4_23, mc_d4_24;
    logic [7:0] mc_d4_30, mc_d4_31, mc_d4_32, mc_d4_33, mc_d4_34;
    logic [7:0] mc_d4_40, mc_d4_41, mc_d4_42, mc_d4_43, mc_d4_44;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            {mc_d1_00,mc_d1_01,mc_d1_02,mc_d1_03,mc_d1_04} <= '0;
            {mc_d1_10,mc_d1_11,mc_d1_12,mc_d1_13,mc_d1_14} <= '0;
            {mc_d1_20,mc_d1_21,mc_d1_22,mc_d1_23,mc_d1_24} <= '0;
            {mc_d1_30,mc_d1_31,mc_d1_32,mc_d1_33,mc_d1_34} <= '0;
            {mc_d1_40,mc_d1_41,mc_d1_42,mc_d1_43,mc_d1_44} <= '0;

            {mc_d2_00,mc_d2_01,mc_d2_02,mc_d2_03,mc_d2_04} <= '0;
            {mc_d2_10,mc_d2_11,mc_d2_12,mc_d2_13,mc_d2_14} <= '0;
            {mc_d2_20,mc_d2_21,mc_d2_22,mc_d2_23,mc_d2_24} <= '0;
            {mc_d2_30,mc_d2_31,mc_d2_32,mc_d2_33,mc_d2_34} <= '0;
            {mc_d2_40,mc_d2_41,mc_d2_42,mc_d2_43,mc_d2_44} <= '0;

            {mc_d3_00,mc_d3_01,mc_d3_02,mc_d3_03,mc_d3_04} <= '0;
            {mc_d3_10,mc_d3_11,mc_d3_12,mc_d3_13,mc_d3_14} <= '0;
            {mc_d3_20,mc_d3_21,mc_d3_22,mc_d3_23,mc_d3_24} <= '0;
            {mc_d3_30,mc_d3_31,mc_d3_32,mc_d3_33,mc_d3_34} <= '0;
            {mc_d3_40,mc_d3_41,mc_d3_42,mc_d3_43,mc_d3_44} <= '0;

            {mc_d4_00,mc_d4_01,mc_d4_02,mc_d4_03,mc_d4_04} <= '0;
            {mc_d4_10,mc_d4_11,mc_d4_12,mc_d4_13,mc_d4_14} <= '0;
            {mc_d4_20,mc_d4_21,mc_d4_22,mc_d4_23,mc_d4_24} <= '0;
            {mc_d4_30,mc_d4_31,mc_d4_32,mc_d4_33,mc_d4_34} <= '0;
            {mc_d4_40,mc_d4_41,mc_d4_42,mc_d4_43,mc_d4_44} <= '0;
        end else begin
            // Delay stage 1 (aligned with pixel_distance output)
            if (mc_win_valid) begin
                mc_d1_00<=mw00; mc_d1_01<=mw01; mc_d1_02<=mw02; mc_d1_03<=mw03; mc_d1_04<=mw04;
                mc_d1_10<=mw10; mc_d1_11<=mw11; mc_d1_12<=mw12; mc_d1_13<=mw13; mc_d1_14<=mw14;
                mc_d1_20<=mw20; mc_d1_21<=mw21; mc_d1_22<=mw22; mc_d1_23<=mw23; mc_d1_24<=mw24;
                mc_d1_30<=mw30; mc_d1_31<=mw31; mc_d1_32<=mw32; mc_d1_33<=mw33; mc_d1_34<=mw34;
                mc_d1_40<=mw40; mc_d1_41<=mw41; mc_d1_42<=mw42; mc_d1_43<=mw43; mc_d1_44<=mw44;
            end
            // Delay stage 2 (aligned with path_length output)
            if (pdist_valid) begin
                mc_d2_00<=mc_d1_00; mc_d2_01<=mc_d1_01; mc_d2_02<=mc_d1_02; mc_d2_03<=mc_d1_03; mc_d2_04<=mc_d1_04;
                mc_d2_10<=mc_d1_10; mc_d2_11<=mc_d1_11; mc_d2_12<=mc_d1_12; mc_d2_13<=mc_d1_13; mc_d2_14<=mc_d1_14;
                mc_d2_20<=mc_d1_20; mc_d2_21<=mc_d1_21; mc_d2_22<=mc_d1_22; mc_d2_23<=mc_d1_23; mc_d2_24<=mc_d1_24;
                mc_d2_30<=mc_d1_30; mc_d2_31<=mc_d1_31; mc_d2_32<=mc_d1_32; mc_d2_33<=mc_d1_33; mc_d2_34<=mc_d1_34;
                mc_d2_40<=mc_d1_40; mc_d2_41<=mc_d1_41; mc_d2_42<=mc_d1_42; mc_d2_43<=mc_d1_43; mc_d2_44<=mc_d1_44;
            end
            // Delay stage 3 (aligned with rlimit stage 1)
            if (path_valid) begin
                mc_d3_00<=mc_d2_00; mc_d3_01<=mc_d2_01; mc_d3_02<=mc_d2_02; mc_d3_03<=mc_d2_03; mc_d3_04<=mc_d2_04;
                mc_d3_10<=mc_d2_10; mc_d3_11<=mc_d2_11; mc_d3_12<=mc_d2_12; mc_d3_13<=mc_d2_13; mc_d3_14<=mc_d2_14;
                mc_d3_20<=mc_d2_20; mc_d3_21<=mc_d2_21; mc_d3_22<=mc_d2_22; mc_d3_23<=mc_d2_23; mc_d3_24<=mc_d2_24;
                mc_d3_30<=mc_d2_30; mc_d3_31<=mc_d2_31; mc_d3_32<=mc_d2_32; mc_d3_33<=mc_d2_33; mc_d3_34<=mc_d2_34;
                mc_d3_40<=mc_d2_40; mc_d3_41<=mc_d2_41; mc_d3_42<=mc_d2_42; mc_d3_43<=mc_d2_43; mc_d3_44<=mc_d2_44;
            end
            // Delay stage 4 (aligned with rlimit output = ase_masked_min input)
            if (path_valid_d1) begin
                mc_d4_00<=mc_d3_00; mc_d4_01<=mc_d3_01; mc_d4_02<=mc_d3_02; mc_d4_03<=mc_d3_03; mc_d4_04<=mc_d3_04;
                mc_d4_10<=mc_d3_10; mc_d4_11<=mc_d3_11; mc_d4_12<=mc_d3_12; mc_d4_13<=mc_d3_13; mc_d4_14<=mc_d3_14;
                mc_d4_20<=mc_d3_20; mc_d4_21<=mc_d3_21; mc_d4_22<=mc_d3_22; mc_d4_23<=mc_d3_23; mc_d4_24<=mc_d3_24;
                mc_d4_30<=mc_d3_30; mc_d4_31<=mc_d3_31; mc_d4_32<=mc_d3_32; mc_d4_33<=mc_d3_33; mc_d4_34<=mc_d3_34;
                mc_d4_40<=mc_d3_40; mc_d4_41<=mc_d3_41; mc_d4_42<=mc_d3_42; mc_d4_43<=mc_d3_43; mc_d4_44<=mc_d3_44;
            end
        end
    end

    // ================================================================
    // Stage 5: ASE comparison + masked min (uses MC window)
    // ================================================================
    logic [7:0] adc_out;
    logic       adc_valid;

    adc_ase_masked_min u_masked_min (
        .clk    (clk),
        .rst_n  (rst_n),
        .i_valid(rlimit_valid),
        .i_rlimit(rlimit),
        // d_lambda (delayed, aligned with rlimit)
        .dl00(rl_dl00), .dl01(rl_dl01), .dl02(rl_dl02), .dl03(rl_dl03), .dl04(rl_dl04),
        .dl10(rl_dl10), .dl11(rl_dl11), .dl12(rl_dl12), .dl13(rl_dl13), .dl14(rl_dl14),
        .dl20(rl_dl20), .dl21(rl_dl21), .dl22(rl_dl22), .dl23(rl_dl23), .dl24(rl_dl24),
        .dl30(rl_dl30), .dl31(rl_dl31), .dl32(rl_dl32), .dl33(rl_dl33), .dl34(rl_dl34),
        .dl40(rl_dl40), .dl41(rl_dl41), .dl42(rl_dl42), .dl43(rl_dl43), .dl44(rl_dl44),
        // MC window (delayed 4 cycles, aligned with rlimit)
        .pw00(mc_d4_00), .pw01(mc_d4_01), .pw02(mc_d4_02), .pw03(mc_d4_03), .pw04(mc_d4_04),
        .pw10(mc_d4_10), .pw11(mc_d4_11), .pw12(mc_d4_12), .pw13(mc_d4_13), .pw14(mc_d4_14),
        .pw20(mc_d4_20), .pw21(mc_d4_21), .pw22(mc_d4_22), .pw23(mc_d4_23), .pw24(mc_d4_24),
        .pw30(mc_d4_30), .pw31(mc_d4_31), .pw32(mc_d4_32), .pw33(mc_d4_33), .pw34(mc_d4_34),
        .pw40(mc_d4_40), .pw41(mc_d4_41), .pw42(mc_d4_42), .pw43(mc_d4_43), .pw44(mc_d4_44),
        .o_adc(adc_out),
        .o_valid(adc_valid)
    );

    // ================================================================
    // Output + Frame Done counter
    // ================================================================
    assign o_valid   = adc_valid;
    assign o_adc_pix = adc_out;

    logic [31:0] out_count;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_count <= 32'd0;
            o_done    <= 1'b0;
        end else if (!i_enable) begin
            out_count <= 32'd0;
            o_done    <= 1'b0;
        end else begin
            o_done <= 1'b0;
            if (adc_valid) begin
                if (out_count == FRAME_PIXELS - 1) begin
                    o_done    <= 1'b1;
                    out_count <= 32'd0;
                end else begin
                    out_count <= out_count + 1;
                end
            end
        end
    end

endmodule
