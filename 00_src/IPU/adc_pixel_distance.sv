//==============================================================================
// Module: adc_pixel_distance
// Description:
//   Compute TOTAL pixel distance (dp_total) along fixed paths from center
//   p[2][2] to each of the 24 neighbors in a 5x5 window.
//
//   Maps to Python sub-block: pixel_distance_calc
//
//   The pixel distance is computed along PATH EDGES (consecutive pairs),
//   NOT as a simple |pij - center|.
//
//   For 1-step paths (inner ring): dp_total = |center - neighbor|
//   For 2-step paths (outer ring): dp_total = |center - intermediate|
//                                            + |intermediate - target|
//
//   Fixed paths (from generate_path_to, diagonal-first):
//     (0,0): (2,2)→(1,1)→(0,0)   (0,1): (2,2)→(1,1)→(0,1)
//     (0,2): (2,2)→(1,2)→(0,2)   (0,3): (2,2)→(1,3)→(0,3)
//     (0,4): (2,2)→(1,3)→(0,4)
//     (1,0): (2,2)→(1,1)→(1,0)   (1,4): (2,2)→(1,3)→(1,4)
//     (2,0): (2,2)→(2,1)→(2,0)   (2,4): (2,2)→(2,3)→(2,4)
//     (3,0): (2,2)→(3,1)→(3,0)   (3,4): (2,2)→(3,3)→(3,4)
//     (4,0): (2,2)→(3,1)→(4,0)   (4,1): (2,2)→(3,1)→(4,1)
//     (4,2): (2,2)→(3,2)→(4,2)   (4,3): (2,2)→(3,3)→(4,3)
//     (4,4): (2,2)→(3,3)→(4,4)
//
//   Output: dp_total [8:0] per position (max 510 for 2-step paths).
//   Registered output — 1 pipeline stage.
//==============================================================================

module adc_pixel_distance (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       i_valid,

    // 5x5 GRAY window input (for computing path pixel distances)
    input  logic [7:0] p00, p01, p02, p03, p04,
    input  logic [7:0] p10, p11, p12, p13, p14,
    input  logic [7:0] p20, p21, p22, p23, p24,
    input  logic [7:0] p30, p31, p32, p33, p34,
    input  logic [7:0] p40, p41, p42, p43, p44,

    // dp_total outputs (registered): total pixel distance along path
    // 9-bit (max 510 for 2-step paths where each edge can be 0..255)
    output logic [8:0] dp00, dp01, dp02, dp03, dp04,
    output logic [8:0] dp10, dp11, dp12, dp13, dp14,
    output logic [8:0] dp20, dp21, dp22, dp23, dp24,
    output logic [8:0] dp30, dp31, dp32, dp33, dp34,
    output logic [8:0] dp40, dp41, dp42, dp43, dp44,

    output logic       o_valid
);

    // Absolute difference helper
    function automatic logic [7:0] absd(
        input logic [7:0] a, input logic [7:0] b
    );
        return (a >= b) ? (a - b) : (b - a);
    endfunction

    logic [7:0] center;
    assign center = p22;

    // ----------------------------------------------------------------
    // Step 1: center-to-inner edge diffs (8 values, for 1-step paths)
    // These are also the FIRST edge of 2-step paths.
    // ----------------------------------------------------------------
    logic [7:0] ec11, ec12, ec13;   // center → row 1
    logic [7:0] ec21, ec23;         // center → row 2
    logic [7:0] ec31, ec32, ec33;   // center → row 3

    always_comb begin
        ec11 = absd(center, p11);
        ec12 = absd(center, p12);
        ec13 = absd(center, p13);
        ec21 = absd(center, p21);
        ec23 = absd(center, p23);
        ec31 = absd(center, p31);
        ec32 = absd(center, p32);
        ec33 = absd(center, p33);
    end

    // ----------------------------------------------------------------
    // Step 2: inner-to-outer edge diffs (16 values, second edge)
    // ----------------------------------------------------------------
    logic [7:0] eo00, eo01, eo10;           // via p11
    logic [7:0] eo02;                       // via p12
    logic [7:0] eo03, eo04, eo14;           // via p13
    logic [7:0] eo20;                       // via p21
    logic [7:0] eo24;                       // via p23
    logic [7:0] eo30, eo40, eo41;           // via p31
    logic [7:0] eo42;                       // via p32
    logic [7:0] eo34, eo43, eo44;           // via p33

    always_comb begin
        // Via p11 → {(0,0), (0,1), (1,0)}
        eo00 = absd(p11, p00);
        eo01 = absd(p11, p01);
        eo10 = absd(p11, p10);
        // Via p12 → {(0,2)}
        eo02 = absd(p12, p02);
        // Via p13 → {(0,3), (0,4), (1,4)}
        eo03 = absd(p13, p03);
        eo04 = absd(p13, p04);
        eo14 = absd(p13, p14);
        // Via p21 → {(2,0)}
        eo20 = absd(p21, p20);
        // Via p23 → {(2,4)}
        eo24 = absd(p23, p24);
        // Via p31 → {(3,0), (4,0), (4,1)}
        eo30 = absd(p31, p30);
        eo40 = absd(p31, p40);
        eo41 = absd(p31, p41);
        // Via p32 → {(4,2)}
        eo42 = absd(p32, p42);
        // Via p33 → {(3,4), (4,3), (4,4)}
        eo34 = absd(p33, p34);
        eo43 = absd(p33, p43);
        eo44 = absd(p33, p44);
    end

    // ----------------------------------------------------------------
    // Step 3: Compute dp_total for each position
    //   1-step: dp_total = ec (single edge)
    //   2-step: dp_total = ec + eo (sum of two edges)
    //   center: dp_total = 0
    // ----------------------------------------------------------------
    logic [8:0] c_dp00, c_dp01, c_dp02, c_dp03, c_dp04;
    logic [8:0] c_dp10, c_dp11, c_dp12, c_dp13, c_dp14;
    logic [8:0] c_dp20, c_dp21, c_dp22, c_dp23, c_dp24;
    logic [8:0] c_dp30, c_dp31, c_dp32, c_dp33, c_dp34;
    logic [8:0] c_dp40, c_dp41, c_dp42, c_dp43, c_dp44;

    always_comb begin
        // Row 0 (all 2-step)
        c_dp00 = {1'b0, ec11} + {1'b0, eo00};
        c_dp01 = {1'b0, ec11} + {1'b0, eo01};
        c_dp02 = {1'b0, ec12} + {1'b0, eo02};
        c_dp03 = {1'b0, ec13} + {1'b0, eo03};
        c_dp04 = {1'b0, ec13} + {1'b0, eo04};

        // Row 1 (mixed)
        c_dp10 = {1'b0, ec11} + {1'b0, eo10};   // 2-step
        c_dp11 = {1'b0, ec11};                    // 1-step
        c_dp12 = {1'b0, ec12};                    // 1-step
        c_dp13 = {1'b0, ec13};                    // 1-step
        c_dp14 = {1'b0, ec13} + {1'b0, eo14};   // 2-step

        // Row 2 (center row)
        c_dp20 = {1'b0, ec21} + {1'b0, eo20};   // 2-step
        c_dp21 = {1'b0, ec21};                    // 1-step
        c_dp22 = 9'd0;                            // center
        c_dp23 = {1'b0, ec23};                    // 1-step
        c_dp24 = {1'b0, ec23} + {1'b0, eo24};   // 2-step

        // Row 3 (mixed)
        c_dp30 = {1'b0, ec31} + {1'b0, eo30};   // 2-step
        c_dp31 = {1'b0, ec31};                    // 1-step
        c_dp32 = {1'b0, ec32};                    // 1-step
        c_dp33 = {1'b0, ec33};                    // 1-step
        c_dp34 = {1'b0, ec33} + {1'b0, eo34};   // 2-step

        // Row 4 (all 2-step)
        c_dp40 = {1'b0, ec31} + {1'b0, eo40};
        c_dp41 = {1'b0, ec31} + {1'b0, eo41};
        c_dp42 = {1'b0, ec32} + {1'b0, eo42};
        c_dp43 = {1'b0, ec33} + {1'b0, eo43};
        c_dp44 = {1'b0, ec33} + {1'b0, eo44};
    end

    // ----------------------------------------------------------------
    // Register outputs (Pipeline stage 1)
    // ----------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            {dp00,dp01,dp02,dp03,dp04} <= '0;
            {dp10,dp11,dp12,dp13,dp14} <= '0;
            {dp20,dp21,dp22,dp23,dp24} <= '0;
            {dp30,dp31,dp32,dp33,dp34} <= '0;
            {dp40,dp41,dp42,dp43,dp44} <= '0;
            o_valid <= 1'b0;
        end else begin
            o_valid <= i_valid;
            if (i_valid) begin
                dp00<=c_dp00; dp01<=c_dp01; dp02<=c_dp02;
                dp03<=c_dp03; dp04<=c_dp04;
                dp10<=c_dp10; dp11<=c_dp11; dp12<=c_dp12;
                dp13<=c_dp13; dp14<=c_dp14;
                dp20<=c_dp20; dp21<=c_dp21; dp22<=c_dp22;
                dp23<=c_dp23; dp24<=c_dp24;
                dp30<=c_dp30; dp31<=c_dp31; dp32<=c_dp32;
                dp33<=c_dp33; dp34<=c_dp34;
                dp40<=c_dp40; dp41<=c_dp41; dp42<=c_dp42;
                dp43<=c_dp43; dp44<=c_dp44;
            end
        end
    end

endmodule
