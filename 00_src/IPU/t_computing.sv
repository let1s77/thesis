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

    logic [15:0] modify_A;
    logic [15:0] div_q;
    logic [7:0]  div_q_sat;
    logic [8:0]  tx_tmp;

    logic [7:0] tx_raw_comb;
    logic [7:0] tx_used_comb;

    always_comb begin
        modify_A   = i_dark * OMEGA_Q8;
        div_q      = 16'd0;
        div_q_sat  = 8'd0;
        tx_tmp     = 9'd0;
        tx_raw_comb = 8'd0;

        if (i_A == 8'd0) begin
            tx_raw_comb = TX_WHEN_A_ZERO;
        end else begin
            div_q = modify_A / i_A;
            // Saturate quotient to avoid wrap-around from low-byte truncation.
            div_q_sat = (div_q > 16'd255) ? 8'd255 : div_q[7:0];
            tx_tmp = 9'd255 - {1'b0, div_q_sat};

            if (tx_tmp[8]) tx_raw_comb = 8'd0;
            else           tx_raw_comb = tx_tmp[7:0];
        end

        tx_used_comb = (tx_raw_comb < TX_MIN) ? TX_MIN : tx_raw_comb;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_valid   <= 1'b0;
            o_tx_raw  <= 8'd0;
            o_tx_used <= 8'd0;
        end else begin
            o_valid <= i_valid;
            if (i_valid) begin
                o_tx_raw  <= tx_raw_comb;
                o_tx_used <= tx_used_comb;
            end
        end
    end

endmodule
