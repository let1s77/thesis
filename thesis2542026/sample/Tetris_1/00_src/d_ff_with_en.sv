module d_ff_with_en #(
  parameter N = 1
) (
  input  logic [N-1:0] d,
  input  logic       clk,
  input  logic       en,
  input  logic       rst_n,
  output logic [N-1:0] q
);
  
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      q <= '0;
    else if (en)
      q <= d;
	 else;
  end

endmodule
