// estimate_transmission.sv (modularized)
// Coarse transmission:
//   t(x) = 255 - ((OMEGA_Q8 * min_3x3( min_c( I^c * 255 / A^c ) )) >> 8)
// Clamp: t >= T_MIN
//
// Notes:
// - i_A_* must be stable while streaming pixels for transmission estimation.
// - Normalization uses reciprocal LUT in Q16 to avoid dividers.
// - Optional sky override: if i_use_sky=1 and sky pixel, output i_t_sky.
//
// No function/task. Sub-modules are in separate files:
//   invA_lut_q16.sv, norm_channel_q16.sv, min3_u8.sv, spatial_min3x3.sv, omega_clamp_t.sv

module estimate_transmission #(
  parameter int IMG_WIDTH = 512,
  parameter bit ENABLE_SPATIAL_FILTER = 1'b1,

  // omega in Q0.8, default ~0.95 * 256 = 243
  parameter logic [7:0] OMEGA_Q8 = 8'hF3,

  // minimum transmission clamp (avoid too small t)
  parameter logic [7:0] T_MIN = 8'd26
)(
  input  logic        clk,
  input  logic        rst_n,

  input  logic        i_valid,
  input  logic [23:0] i_color,

  // Atmospheric light per channel (8-bit each), stable during streaming
  input  logic [7:0]  i_A_r,
  input  logic [7:0]  i_A_g,
  input  logic [7:0]  i_A_b,

  // Sky mask aligned with i_color stream
  input  logic        i_sky,
  input  logic        i_use_sky,
  input  logic [7:0]  i_t_sky,

  output logic        o_valid,
  output logic [7:0]  o_t
);

  // ------------------------------------------------------------------------
  // Unpack RGB
  // ------------------------------------------------------------------------
  logic [7:0] r, g, b;
  always_comb begin
    r = i_color[ 7: 0];
    g = i_color[15: 8];
    b = i_color[23:16];
  end

  // ------------------------------------------------------------------------
  // Reciprocal LUT for each channel (Q16)
  // ------------------------------------------------------------------------
  logic [23:0] inv_r, inv_g, inv_b;

  invA_lut_q16 u_inv_r (.i_A(i_A_r), .o_invA_q16(inv_r));
  invA_lut_q16 u_inv_g (.i_A(i_A_g), .o_invA_q16(inv_g));
  invA_lut_q16 u_inv_b (.i_A(i_A_b), .o_invA_q16(inv_b));

  // ------------------------------------------------------------------------
  // Normalize each channel and min over channels
  // ------------------------------------------------------------------------
  logic [7:0] r_n, g_n, b_n;
  norm_channel_q16 u_norm_r (.i_pix(r), .i_invA_q16(inv_r), .o_norm(r_n));
  norm_channel_q16 u_norm_g (.i_pix(g), .i_invA_q16(inv_g), .o_norm(g_n));
  norm_channel_q16 u_norm_b (.i_pix(b), .i_invA_q16(inv_b), .o_norm(b_n));

  logic [7:0] min_norm_c;
  min3_u8 u_min_c (.i_a(r_n), .i_b(g_n), .i_c(b_n), .o_min(min_norm_c));

  // Register min_norm_c (timing cleaner; matches previous behavior)
  logic [7:0] min_norm_r;
  logic       valid_s0;
  logic       sky_s0;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      min_norm_r <= 8'd0;
      valid_s0   <= 1'b0;
      sky_s0     <= 1'b0;
    end else begin
      valid_s0 <= i_valid;
      if (i_valid) begin
        min_norm_r <= min_norm_c;
        sky_s0     <= i_sky;
      end
    end
  end

  // ------------------------------------------------------------------------
  // Optional 3x3 min filter
  // ------------------------------------------------------------------------
  logic [7:0] block_min_out;
  logic       valid_core;
  logic       sky_core;

  generate
    if (ENABLE_SPATIAL_FILTER == 1'b0) begin : GEN_NO_FILTER
      assign block_min_out = min_norm_r;
      assign valid_core    = valid_s0;
      assign sky_core      = sky_s0;
    end else begin : GEN_3X3_MIN
      spatial_min3x3 #(.IMG_WIDTH(IMG_WIDTH)) u_spatial_min3x3 (
        .clk      (clk),
        .rst_n    (rst_n),
        .i_valid  (valid_s0),
        .i_pix    (min_norm_r),
        .i_sky    (sky_s0),
        .o_valid  (valid_core),
        .o_pix_min(block_min_out),
        .o_sky    (sky_core)
      );
    end
  endgenerate

  // ------------------------------------------------------------------------
  // Final omega + clamp
  // ------------------------------------------------------------------------
  logic [7:0] t_clamped;

  omega_clamp_t #(.OMEGA_Q8(OMEGA_Q8), .T_MIN(T_MIN)) u_omega_clamp (
    .i_x(block_min_out),
    .o_t(t_clamped)
  );

  // ------------------------------------------------------------------------
  // Output register + optional sky override
  // ------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      o_valid <= 1'b0;
      o_t     <= 8'd0;
    end else begin
      o_valid <= valid_core;
      if (valid_core) begin
        if (i_use_sky && sky_core) o_t <= i_t_sky;
        else                      o_t <= t_clamped;
      end
    end
  end

endmodule
