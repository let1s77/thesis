module load_move (
  input logic       clk,
  input logic       rst_n,

  input logic       move_start,

  output logic       move_done,

  input logic [8:0] color_data_reg,

  input logic [9:0] pivot_addr_reg,cur_addr_1_reg,cur_addr_2_reg,cur_addr_3_reg,
  
  input logic [9:0] next_pivot_addr,
  input logic [9:0] next_addr_1,next_addr_2,next_addr_3,
  
  output logic       en_update,
  output logic [9:0] update_pivot_addr,
  output logic [9:0] update_addr_1,update_addr_2,update_addr_3,

  output logic [10:0] addr_5,
  output logic [9:0] piece_id_wr_5
);
  
//FSM
typedef enum logic [3:0] {
  IDLE           = 4'd0,
  WAIT_FOR_START = 4'd1,
  DEL_1          = 4'd2,
  DEL_2          = 4'd3,
  DEL_3          = 4'd4,
  DEL_4          = 4'd5,
  PR_1           = 4'd6,
  PR_2           = 4'd7,
  PR_3           = 4'd8,
  PR_4           = 4'd9,
  UP_ADDR        = 4'd10,
  DONE = 4'd11
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
      next_state = move_start ? DEL_1 : WAIT_FOR_START;
    end

    DEL_1: begin
      next_state = DEL_2;
    end

    DEL_2: begin
      next_state = DEL_3;
    end

    DEL_3: begin
      next_state = DEL_4;
    end

    DEL_4: begin
      next_state = PR_1;
    end

    PR_1: begin
      next_state = PR_2;
    end

    PR_2: begin
      next_state = PR_3;
    end

    PR_3: begin
      next_state = PR_4;
    end

    PR_4: begin
      next_state = UP_ADDR;
    end

    UP_ADDR: begin
      next_state = DONE;
    end

    DONE: begin
      next_state = IDLE;
    end
  endcase
end

always_comb begin
  update_pivot_addr = 10'd0;
  update_addr_1 = 10'd0;
  update_addr_2 = 10'd0;
  update_addr_3 = 10'd0;
  en_update = 1'b0;
  move_done = 1'b0;
  addr_5 = 10'h0;
  piece_id_wr_5 = 9'd0;
  case(current_state)
    IDLE:
    begin
      move_done = 1'b0;
      addr_5 = 10'h0;
      piece_id_wr_5 = 9'd0;
    end

    DEL_1:
    begin
      piece_id_wr_5 = 9'd18;
      addr_5 = pivot_addr_reg;
    end

    DEL_2:
    begin
      piece_id_wr_5 = 9'd18;
      addr_5 = cur_addr_1_reg;
    end

    DEL_3:
    begin
      piece_id_wr_5 = 9'd18;
      addr_5 = cur_addr_2_reg;
    end

    DEL_4:
    begin
      piece_id_wr_5 = 9'd18;
      addr_5 = cur_addr_3_reg;
    end

    PR_1:
    begin
      piece_id_wr_5 = color_data_reg;
      addr_5 = next_pivot_addr;
    end

    PR_2:
    begin
      piece_id_wr_5 = color_data_reg;
      addr_5 = next_addr_1;
    end

    PR_3:
    begin
      piece_id_wr_5 = color_data_reg;
      addr_5 = next_addr_2;
    end

    PR_4:
    begin
      piece_id_wr_5 = color_data_reg;
      addr_5 = next_addr_3;
    end

    UP_ADDR: begin
      en_update = 1'b1;
      update_pivot_addr = next_pivot_addr;
      update_addr_1 = next_addr_1;
      update_addr_2 = next_addr_2;
      update_addr_3 = next_addr_3;
    end

    DONE:
    begin
      en_update = 1'b0;
      piece_id_wr_5 = 9'd0;
      addr_5 = 10'h0;
      move_done = 1'b1;
    end
  endcase
end


endmodule



  //3'd3: en[((pivot_addr_reg >> 5) - ((cur_addr_1_reg[4:0]) - (pivot_addr_reg[4:0]))) << 5 | ((cur_addr_1_reg >> 5) - (pivot_addr_reg >> 5) + (pivot_addr_reg[4:0]))] = 1'b1;

        //3'd4: en[((pivot_addr_reg >> 5) + ((cur_addr_1_reg[4:0]) - (pivot_addr_reg[4:0]))) << 5 | ((pivot_addr_reg[4:0]) - ((cur_addr_1_reg >> 5) - (pivot_addr_reg >> 5)))] = 1'b1;
    // // Rotate CW
    // 3'd3: begin
    //   update_addr_1 = (((pivot_addr_reg >> 5) -
    //                 ((cur_addr_1_reg & 5'h1F) - (pivot_addr_reg & 5'h1F))) << 5)
    //                + ((cur_addr_1_reg >> 5) - (pivot_addr_reg >> 5) + (pivot_addr_reg & 5'h1F));

    //   update_addr_2 = (((pivot_addr_reg >> 5) -
    //                 ((cur_addr_2_reg & 5'h1F) - (pivot_addr_reg & 5'h1F))) << 5)
    //                + ((cur_addr_2_reg >> 5) - (pivot_addr_reg >> 5) + (pivot_addr_reg & 5'h1F));

    //   update_addr_3 = (((pivot_addr_reg >> 5) -
    //                 ((cur_addr_3_reg & 5'h1F) - (pivot_addr_reg & 5'h1F))) << 5)
    //                + ((cur_addr_3_reg >> 5) - (pivot_addr_reg >> 5) + (pivot_addr_reg & 5'h1F));
    // end

    // // Rotate CCW
    // 3'd4: begin
    //   update_addr_1 = (((pivot_addr_reg >> 5) +
    //                 ((cur_addr_1_reg & 5'h1F) - (pivot_addr_reg & 5'h1F))) << 5)
    //                + ((pivot_addr_reg & 5'h1F) - ((cur_addr_1_reg >> 5) - (pivot_addr_reg >> 5)));

    //   update_addr_2 = (((pivot_addr_reg >> 5) +
    //                 ((cur_addr_2_reg & 5'h1F) - (pivot_addr_reg & 5'h1F))) << 5)
    //                + ((pivot_addr_reg & 5'h1F) - ((cur_addr_2_reg >> 5) - (pivot_addr_reg >> 5)));

    //   update_addr_3 = (((pivot_addr_reg >> 5) +
    //                 ((cur_addr_3_reg & 5'h1F) - (pivot_addr_reg & 5'h1F))) << 5)
    //                + ((pivot_addr_reg & 5'h1F) - ((cur_addr_3_reg >> 5) - (pivot_addr_reg >> 5)));
    // end

    // Move down