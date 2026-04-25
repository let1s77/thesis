module control_delay (
  input logic        button_in,
  input logic        clk,
  input logic        rst_n,
  input logic        equal,

  output logic       aclr,
  output logic       cnt_en,
  output logic       button_out,

  output logic [6:0] cstate
);
  // State encoding
  typedef enum logic [3:0] {
    S0  = 4'd0,
    S1  = 4'd1,
    S2  = 4'd2,
    S3  = 4'd3,
    S4  = 4'd4,
    S5  = 4'd5,
    S6  = 4'd6,
    S7  = 4'd7,
    S8  = 4'd8,
    S9  = 4'd9,
    S10  = 4'd10
    
  } state_t;
  
  state_t current_state, next_state;
  // State register
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) 
      current_state <= S0; // Reset to initial state
    else
      current_state <= next_state; // Update state
  end

  always_comb begin
  next_state = current_state;
  aclr = 1'b1;
  cnt_en = 1'b0;
  button_out = 1'b0;

    case (current_state)
      // Wait for button in 
      S0: begin
        aclr = 1'b1;
        cnt_en = 1'b0;
        button_out = 1'b0;
        next_state = button_in ? S1 : S0;
      end

      S1: begin
        aclr = 1'b1;
        cnt_en = 1'b0;
        button_out = 1'b1;
        next_state = S2;
      end

      S2: begin
        aclr = 1'b1;
        cnt_en = 1'b0;
        button_out = 1'b1;
        next_state = S3;
      end
      S3: begin
        aclr = 1'b1;
        cnt_en = 1'b0;
        button_out = 1'b1;
        next_state = S4;
      end
      S4: begin
        aclr = 1'b1;
        cnt_en = 1'b0;
        button_out = 1'b1;
        next_state = S5;
      end
      S5: begin
        aclr = 1'b1;
        cnt_en = 1'b0;
        button_out = 1'b1;
        next_state = S6;
      end
      S6: begin
        aclr = 1'b1;
        cnt_en = 1'b0;
        button_out = 1'b1;
        next_state = S7;
      end
      S7: begin
        aclr = 1'b1;
        cnt_en = 1'b0;
        button_out = 1'b1;
        next_state = S8;
      end
      S8: begin
        aclr = 1'b1;
        cnt_en = 1'b0;
        button_out = 1'b1;
        next_state = S9;
      end
      S9: begin
        aclr = 1'b1;
        cnt_en = 1'b0;
        button_out = 1'b1;
        next_state = S10;
      end

      S10: begin
        aclr = 1'b0;
        cnt_en = 1'b1;
        button_out = 1'b0;
        next_state = equal ? S0 : S10;
      end
    endcase
  end
  assign cstate = current_state;
endmodule