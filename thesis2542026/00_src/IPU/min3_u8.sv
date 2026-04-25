module min3_u8 (
  input  logic [7:0] i_a,
  input  logic [7:0] i_b,
  input  logic [7:0] i_c,
  output logic [7:0] o_min
);
  logic [7:0] min_ab;

  always_comb begin
    min_ab = (i_a < i_b) ? i_a : i_b;
    o_min  = (min_ab < i_c) ? min_ab : i_c;
  end
endmodule
