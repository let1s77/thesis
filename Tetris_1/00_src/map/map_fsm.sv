module map_fsm (
  input logic clk,
  input logic rst_n,
  input logic map_load_start,
  input logic done,
  output logic aclr,
  output logic cnt_en
);
  

//FSM
typedef enum logic [1:0] {
  IDLE           = 2'b00,
  WAIT_FOR_START = 2'b01,
  RUNNING        = 2'b10,
  DONE           = 2'b11
} state;

state current_state,next_state;

always_ff @(posedge clk, negedge rst_n) begin
  if (!rst_n)
    current_state <= IDLE;
  else
    current_state <= next_state;  
end

always_comb begin
  next_state = IDLE;
  case(current_state)
    IDLE:begin 
      next_state = WAIT_FOR_START;
    end

    WAIT_FOR_START: begin
      next_state = map_load_start ? RUNNING : WAIT_FOR_START;
    end

    RUNNING: begin
      next_state = done ? DONE : RUNNING;
    end

    DONE: begin
      next_state = IDLE;
    end
  endcase
end

always_comb begin
  aclr = 1'b1;
  cnt_en = 1'b0;
  case(current_state)
    IDLE:
    begin
      aclr = 1'b1;
      cnt_en = 1'b0;
    end

    WAIT_FOR_START:
    begin
      aclr = 1'b1;
      cnt_en = 1'b0;
    end

    RUNNING:
    begin
      aclr = 1'b0;
      cnt_en = 1'b1;
    end

    DONE:
    begin
      aclr = 1'b1;
      cnt_en = 1'b0;
    end
  endcase
end


endmodule