module piece_generator
(
  input logic         clk,
  input logic         rst_n,
  input logic         en_gen,
  input logic         ld_seed,
  input logic  [15:0] seed,
  output logic [2:0] piece_id
);
logic [15:0] lfsr_reg;
logic        feedback;

always_ff @(posedge clk or negedge rst_n) begin
  if (!rst_n)
    lfsr_reg <= 16'hBEEF;
  else if (ld_seed|en_gen) begin
    if(ld_seed)
      lfsr_reg <= seed;
    else begin
      feedback = lfsr_reg[15] ^ lfsr_reg[13] ^ lfsr_reg[12] ^ lfsr_reg[10];
      lfsr_reg <= {feedback, lfsr_reg[15:1]};
    end
  end
  else
    lfsr_reg <= lfsr_reg;
end

assign piece_id = (lfsr_reg[2:0] == 3'b111) ? 3'd0 : lfsr_reg[2:0];

endmodule
