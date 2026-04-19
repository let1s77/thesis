module clear_score_logic (
  input logic [2:0] clear_score_out,
  input logic [7:0] current_lvl,

  output logic [17:0] clear_score_cal
);
  
  always_comb begin
    case(clear_score_out)
      3'd0: clear_score_cal = 18'd0;
      3'd1: clear_score_cal = 6'd40*(current_lvl + 1'b1);
      3'd2: clear_score_cal = 7'd100*(current_lvl + 1'b1);
      3'd3: clear_score_cal = 9'd300*(current_lvl + 1'b1);
      3'd4: clear_score_cal = 11'd1200*(current_lvl + 1'b1);
      default: clear_score_cal = 18'd0;
    endcase
  end

endmodule