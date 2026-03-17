//==============================================================================
// Module: t_compute_fuse
// Description:
//   Top wrapper for transmission computing + fusing pipeline.
//
// Pipeline:
//   Stage 1: t_computing
//   Stage 2: fusing
//
// Total latency: 2 cycles from i_valid to o_valid.
//==============================================================================

module t_compute_fuse #(
    parameter logic [7:0] OMEGA_Q8       = 8'd255,
    parameter logic [7:0] TX_MIN         = 8'd15,
    parameter logic [7:0] TX_WHEN_A_ZERO = 8'd15
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic       i_valid,

    input  logic [7:0] i_dark,
    input  logic [7:0] i_A,
    input  logic [7:0] i_A_r,
    input  logic [7:0] i_A_g,
    input  logic [7:0] i_A_b,
    input  logic [7:0] i_src_r,
    input  logic [7:0] i_src_g,
    input  logic [7:0] i_src_b,

    output logic       o_valid,
    output logic [7:0] o_tx_raw,
    output logic [7:0] o_tx_used,
    output logic [7:0] o_out_r,
    output logic [7:0] o_out_g,
    output logic [7:0] o_out_b
);

    logic       tx_valid;
    logic [7:0] tx_raw_s1;

    logic [7:0] A_r_d1, A_g_d1, A_b_d1;
    logic [7:0] src_r_d1, src_g_d1, src_b_d1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            A_r_d1   <= 8'd0;
            A_g_d1   <= 8'd0;
            A_b_d1   <= 8'd0;
            src_r_d1 <= 8'd0;
            src_g_d1 <= 8'd0;
            src_b_d1 <= 8'd0;
        end else if (i_valid) begin
            A_r_d1   <= i_A_r;
            A_g_d1   <= i_A_g;
            A_b_d1   <= i_A_b;
            src_r_d1 <= i_src_r;
            src_g_d1 <= i_src_g;
            src_b_d1 <= i_src_b;
        end
    end

    t_computing #(
        .OMEGA_Q8      (OMEGA_Q8),
        .TX_MIN        (TX_MIN),
        .TX_WHEN_A_ZERO(TX_WHEN_A_ZERO)
    ) u_t_computing (
        .clk      (clk),
        .rst_n    (rst_n),
        .i_valid  (i_valid),
        .i_dark   (i_dark),
        .i_A      (i_A),
        .o_valid  (tx_valid),
        .o_tx_raw (tx_raw_s1),
        .o_tx_used()
    );

    fusing #(
        .TX_MIN(TX_MIN)
    ) u_fusing (
        .clk      (clk),
        .rst_n    (rst_n),
        .i_valid  (tx_valid),
        .i_tx_raw (tx_raw_s1),
        .i_A_r    (A_r_d1),
        .i_A_g    (A_g_d1),
        .i_A_b    (A_b_d1),
        .i_src_r  (src_r_d1),
        .i_src_g  (src_g_d1),
        .i_src_b  (src_b_d1),
        .o_valid  (o_valid),
        .o_tx_used(o_tx_used),
        .o_out_r  (o_out_r),
        .o_out_g  (o_out_g),
        .o_out_b  (o_out_b)
    );

    assign o_tx_raw = tx_raw_s1;

endmodule
