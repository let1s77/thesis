// norm_channel_q16.sv
// Normalize an 8-bit channel by invA_q16:
//   q16 = pix * invA_q16  (pix 8b, inv 24b -> 32b)
//   norm = q16 >> 16      (approx floor(pix*255/A))
// Saturate to 255.

module norm_channel_q16 (
  input  logic [7:0]  i_pix,
  input  logic [23:0] i_invA_q16,
  output logic [7:0]  o_norm
);
  logic [31:0] mul_q;
  logic [15:0] q16;

  always_comb begin
    mul_q = i_pix * i_invA_q16;
    q16   = mul_q[31:16];

    // Saturate if >255
    o_norm = (q16[15:8] != 8'd0) ? 8'hFF : q16[7:0];
  end
endmodule
