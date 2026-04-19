// omega_clamp_t.sv
// t = 255 - ((omega_q8 * x) >> 8), clamp to t_min
// omega_q8 is Q0.8.

module omega_clamp_t #(
  parameter logic [7:0] OMEGA_Q8 = 8'hF3,
  parameter logic [7:0] T_MIN    = 8'd26
)(
  input  logic [7:0] i_x,
  output logic [7:0] o_t
);
  logic [15:0] omega_mul;
  logic [7:0]  x_scaled;
  logic [8:0]  t_raw;

  always_comb begin
    omega_mul = i_x * OMEGA_Q8;
    x_scaled  = omega_mul[15:8];           // >>8

    t_raw = 9'd255 - {1'b0, x_scaled};

    if (t_raw[8]) begin
      o_t = T_MIN;
    end else begin
      o_t = (t_raw[7:0] < T_MIN) ? T_MIN : t_raw[7:0];
    end
  end
endmodule
