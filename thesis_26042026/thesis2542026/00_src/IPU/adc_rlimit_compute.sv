//==============================================================================
// Module: adc_rlimit_compute
// Description:
//   Compute r_limit = mean of all d_lambda values in the 5x5 window (Eq. 9).
//
//   Maps to Python sub-block: rlimit_calc
//
//   r_limit = (Σ d_λ(k, center)) / M ,  M = 25
//
//   Hardware-friendly division by 25:
//     x / 25 ≈ (x * 41) >> 10   (41/1024 = 0.04003 ≈ 1/24.97)
//     Max sum ≈ 24*106 = 2544, (2544*41)>>10 = 101 → fits in 10 bits.
//
//   Pipeline: 2 stages
//     Stage 1: Sum all 25 d_lambda values (adder tree) + delay d_lambda by 1
//     Stage 2: Multiply by 41, shift right 10  + delay d_lambda by 1
//
//   Output: r_limit (10-bit) + delayed d_lambda (aligned with r_limit)
//   MC window pixels are aligned separately in the top wrapper.
//==============================================================================

module adc_rlimit_compute (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       i_valid,

    // 25 d_lambda values (10-bit each)
    input  logic [9:0] dl00, dl01, dl02, dl03, dl04,
    input  logic [9:0] dl10, dl11, dl12, dl13, dl14,
    input  logic [9:0] dl20, dl21, dl22, dl23, dl24,
    input  logic [9:0] dl30, dl31, dl32, dl33, dl34,
    input  logic [9:0] dl40, dl41, dl42, dl43, dl44,

    // Delayed d_lambda (for ASE comparison, aligned with r_limit, +2 cycles)
    output logic [9:0] dl_d00, dl_d01, dl_d02, dl_d03, dl_d04,
    output logic [9:0] dl_d10, dl_d11, dl_d12, dl_d13, dl_d14,
    output logic [9:0] dl_d20, dl_d21, dl_d22, dl_d23, dl_d24,
    output logic [9:0] dl_d30, dl_d31, dl_d32, dl_d33, dl_d34,
    output logic [9:0] dl_d40, dl_d41, dl_d42, dl_d43, dl_d44,

    // r_limit output
    output logic [9:0] o_rlimit,
    output logic       o_valid
);

    // ================================================================
    // Stage 1: Adder tree to sum all 25 d_lambda values
    // ================================================================
    logic [12:0] sum_s1 [0:12];

    always_comb begin
        sum_s1[0]  = {3'd0, dl00} + {3'd0, dl01};
        sum_s1[1]  = {3'd0, dl02} + {3'd0, dl03};
        sum_s1[2]  = {3'd0, dl04};
        sum_s1[3]  = {3'd0, dl10} + {3'd0, dl11};
        sum_s1[4]  = {3'd0, dl12} + {3'd0, dl13};
        sum_s1[5]  = {3'd0, dl14};
        sum_s1[6]  = {3'd0, dl20} + {3'd0, dl21};
        sum_s1[7]  = {3'd0, dl22} + {3'd0, dl23};
        sum_s1[8]  = {3'd0, dl24};
        sum_s1[9]  = {3'd0, dl30} + {3'd0, dl31};
        sum_s1[10] = {3'd0, dl32} + {3'd0, dl33};
        sum_s1[11] = {3'd0, dl34};
        sum_s1[12] = {3'd0, dl40} + {3'd0, dl41};
    end

    logic [14:0] sum_total;
    always_comb begin
        sum_total = {2'd0, sum_s1[0]} + {2'd0, sum_s1[1]} + {2'd0, sum_s1[2]}
                  + {2'd0, sum_s1[3]} + {2'd0, sum_s1[4]} + {2'd0, sum_s1[5]}
                  + {2'd0, sum_s1[6]} + {2'd0, sum_s1[7]} + {2'd0, sum_s1[8]}
                  + {2'd0, sum_s1[9]} + {2'd0, sum_s1[10]} + {2'd0, sum_s1[11]}
                  + {2'd0, sum_s1[12]}
                  + {5'd0, dl42} + {5'd0, dl43} + {5'd0, dl44};
    end

    // Register Stage 1 output
    logic [14:0] sum_total_r;
    logic        valid_s1;

    // Delay d_lambda by 1 cycle (stage 1)
    logic [9:0] dl_s1_00, dl_s1_01, dl_s1_02, dl_s1_03, dl_s1_04;
    logic [9:0] dl_s1_10, dl_s1_11, dl_s1_12, dl_s1_13, dl_s1_14;
    logic [9:0] dl_s1_20, dl_s1_21, dl_s1_22, dl_s1_23, dl_s1_24;
    logic [9:0] dl_s1_30, dl_s1_31, dl_s1_32, dl_s1_33, dl_s1_34;
    logic [9:0] dl_s1_40, dl_s1_41, dl_s1_42, dl_s1_43, dl_s1_44;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sum_total_r <= '0;
            valid_s1    <= 1'b0;
            {dl_s1_00, dl_s1_01, dl_s1_02, dl_s1_03, dl_s1_04} <= '0;
            {dl_s1_10, dl_s1_11, dl_s1_12, dl_s1_13, dl_s1_14} <= '0;
            {dl_s1_20, dl_s1_21, dl_s1_22, dl_s1_23, dl_s1_24} <= '0;
            {dl_s1_30, dl_s1_31, dl_s1_32, dl_s1_33, dl_s1_34} <= '0;
            {dl_s1_40, dl_s1_41, dl_s1_42, dl_s1_43, dl_s1_44} <= '0;
        end else begin
            valid_s1    <= i_valid;
            sum_total_r <= sum_total;

            if (i_valid) begin
                dl_s1_00<=dl00; dl_s1_01<=dl01; dl_s1_02<=dl02; dl_s1_03<=dl03; dl_s1_04<=dl04;
                dl_s1_10<=dl10; dl_s1_11<=dl11; dl_s1_12<=dl12; dl_s1_13<=dl13; dl_s1_14<=dl14;
                dl_s1_20<=dl20; dl_s1_21<=dl21; dl_s1_22<=dl22; dl_s1_23<=dl23; dl_s1_24<=dl24;
                dl_s1_30<=dl30; dl_s1_31<=dl31; dl_s1_32<=dl32; dl_s1_33<=dl33; dl_s1_34<=dl34;
                dl_s1_40<=dl40; dl_s1_41<=dl41; dl_s1_42<=dl42; dl_s1_43<=dl43; dl_s1_44<=dl44;
            end
        end
    end

    // ================================================================
    // Stage 2: Divide by 25 using multiply-shift
    //   r_limit = (sum_total * 41) >> 10
    // ================================================================
    logic [20:0] mul_result;
    logic [9:0]  rlimit_comb;

    always_comb begin
        mul_result  = sum_total_r * 7'd41;
        rlimit_comb = mul_result[19:10];
    end

    // Register Stage 2 output
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_rlimit <= '0;
            o_valid  <= 1'b0;
            {dl_d00, dl_d01, dl_d02, dl_d03, dl_d04} <= '0;
            {dl_d10, dl_d11, dl_d12, dl_d13, dl_d14} <= '0;
            {dl_d20, dl_d21, dl_d22, dl_d23, dl_d24} <= '0;
            {dl_d30, dl_d31, dl_d32, dl_d33, dl_d34} <= '0;
            {dl_d40, dl_d41, dl_d42, dl_d43, dl_d44} <= '0;
        end else begin
            o_valid  <= valid_s1;
            o_rlimit <= rlimit_comb;

            if (valid_s1) begin
                dl_d00<=dl_s1_00; dl_d01<=dl_s1_01; dl_d02<=dl_s1_02; dl_d03<=dl_s1_03; dl_d04<=dl_s1_04;
                dl_d10<=dl_s1_10; dl_d11<=dl_s1_11; dl_d12<=dl_s1_12; dl_d13<=dl_s1_13; dl_d14<=dl_s1_14;
                dl_d20<=dl_s1_20; dl_d21<=dl_s1_21; dl_d22<=dl_s1_22; dl_d23<=dl_s1_23; dl_d24<=dl_s1_24;
                dl_d30<=dl_s1_30; dl_d31<=dl_s1_31; dl_d32<=dl_s1_32; dl_d33<=dl_s1_33; dl_d34<=dl_s1_34;
                dl_d40<=dl_s1_40; dl_d41<=dl_s1_41; dl_d42<=dl_s1_42; dl_d43<=dl_s1_43; dl_d44<=dl_s1_44;
            end
        end
    end

endmodule
