//==============================================================================
// Module: t_computing
// Description:
//   Transmission computing block for haze removal pipeline.
//
//   Formula (RTL-aligned):
//     modify_A = dark * OMEGA_Q8
//     tx_raw   = 255 - (modify_A / A)
//     tx_used  = max(tx_raw, TX_MIN)
//
// Notes:
// - Integer division semantics follow synthesizable Verilog division.
// - One-cycle registered output.
//==============================================================================

module t_computing #(
    parameter logic [7:0] OMEGA_Q8       = 8'd255,
    parameter logic [7:0] TX_MIN         = 8'd15,
    parameter logic [7:0] TX_WHEN_A_ZERO = 8'd15
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic       i_valid,
    input  logic [7:0] i_dark,
    input  logic [7:0] i_A,

    output logic       o_valid,
    output logic [7:0] o_tx_raw,
    output logic [7:0] o_tx_used
);

    // ---- Stage 1 combinational: modify_A and recip_A ----
    logic [15:0] modify_A;
    logic [15:0] recip_A;
    recip_lut_q16 u_recip_A (.i_val(i_A), .o_recip_q16(recip_A));

    always_comb begin
        modify_A = i_dark * OMEGA_Q8;
    end

    // Stage 1 pipeline registers
    logic        s1_valid;
    logic [15:0] s1_modify_A;
    logic [15:0] s1_recip_A;
    logic        s1_a_zero;  // flag: i_A was 0

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_valid    <= 1'b0;
            s1_modify_A <= 16'd0;
            s1_recip_A  <= 16'd0;
            s1_a_zero   <= 1'b0;
        end else begin
            s1_valid    <= i_valid;
            s1_modify_A <= modify_A;
            s1_recip_A  <= recip_A;
            s1_a_zero   <= (i_A == 8'd0);
        end
    end

    // ---- Stage 2 combinational: multiply, saturate, subtract, clamp ----
    logic [15:0] div_q;
    logic [7:0]  div_q_sat;
    logic [8:0]  tx_tmp;
    logic [7:0]  tx_raw_comb;
    logic [7:0]  tx_used_comb;

    always_comb begin
        div_q       = 16'd0;
        div_q_sat   = 8'd0;
        tx_tmp      = 9'd0;
        tx_raw_comb = 8'd0;

        if (s1_a_zero) begin
            tx_raw_comb = TX_WHEN_A_ZERO;
        end else begin
            div_q     = (s1_modify_A * s1_recip_A) >> 16;
            div_q_sat = (div_q > 16'd255) ? 8'd255 : div_q[7:0];
            tx_tmp    = 9'd255 - {1'b0, div_q_sat};

            if (tx_tmp[8]) tx_raw_comb = 8'd0;
            else           tx_raw_comb = tx_tmp[7:0];
        end

        tx_used_comb = (tx_raw_comb < TX_MIN) ? TX_MIN : tx_raw_comb;
    end

    // Output register (Stage 2 → output)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_valid   <= 1'b0;
            o_tx_raw  <= 8'd0;
            o_tx_used <= 8'd0;
        end else begin
            o_valid <= s1_valid;
            if (s1_valid) begin
                o_tx_raw  <= tx_raw_comb;
                o_tx_used <= tx_used_comb;
            end
        end
    end

endmodule
