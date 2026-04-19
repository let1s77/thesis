module cal_next_addr (
  input logic [9:0] pivot_addr_reg,
  input logic [9:0] cur_addr_1_reg,cur_addr_2_reg,cur_addr_3_reg,
  input logic [2:0] move_data,

  input logic is_square,

  output logic [9:0] next_pivot_addr,
  output logic [9:0] next_addr_1,next_addr_2,next_addr_3
);
  
  always_comb begin
    next_pivot_addr = 10'd0;
    next_addr_1 = 10'd0;
    next_addr_2 = 10'd0;
    next_addr_3 = 10'd0;
  case(move_data)
    3'd1: begin 
      next_pivot_addr = pivot_addr_reg - 1'b1;
      next_addr_1 = cur_addr_1_reg - 1'b1;
      next_addr_2 = cur_addr_2_reg - 1'b1;
      next_addr_3 = cur_addr_3_reg - 1'b1;
    end
    3'd2:begin
      next_pivot_addr =pivot_addr_reg + 1'b1;
      next_addr_1 = cur_addr_1_reg + 1'b1;
      next_addr_2 = cur_addr_2_reg + 1'b1;
      next_addr_3 = cur_addr_3_reg + 1'b1;
    end
    3'd3: begin
      if(is_square) begin
        next_pivot_addr = pivot_addr_reg;
        next_addr_1 = cur_addr_1_reg;
        next_addr_2 = cur_addr_2_reg;
        next_addr_3 = cur_addr_3_reg;
      end else begin
        next_pivot_addr = pivot_addr_reg;
        next_addr_1 = ((pivot_addr_reg >> 5) - ((cur_addr_1_reg[4:0]) - (pivot_addr_reg[4:0]))) << 5 | ((cur_addr_1_reg >> 5) - (pivot_addr_reg >> 5) + (pivot_addr_reg[4:0]));
        next_addr_2 = ((pivot_addr_reg >> 5) - ((cur_addr_2_reg[4:0]) - (pivot_addr_reg[4:0]))) << 5 | ((cur_addr_2_reg >> 5) - (pivot_addr_reg >> 5) + (pivot_addr_reg[4:0]));
        next_addr_3 = ((pivot_addr_reg >> 5) - ((cur_addr_3_reg[4:0]) - (pivot_addr_reg[4:0]))) << 5 | ((cur_addr_3_reg >> 5) - (pivot_addr_reg >> 5) + (pivot_addr_reg[4:0]));
      end
    end
    3'd4:begin
      if(is_square) begin
        next_pivot_addr = next_pivot_addr;
        next_addr_1 = cur_addr_1_reg;
        next_addr_2 = cur_addr_2_reg;
        next_addr_3 = cur_addr_3_reg;
      end else begin
        next_pivot_addr = pivot_addr_reg;
        next_addr_1 = ((pivot_addr_reg >> 5) + ((cur_addr_1_reg[4:0]) - (pivot_addr_reg[4:0]))) << 5 | ((pivot_addr_reg[4:0]) - ((cur_addr_1_reg >> 5) - (pivot_addr_reg >> 5)));
        next_addr_2 = ((pivot_addr_reg >> 5) + ((cur_addr_2_reg[4:0]) - (pivot_addr_reg[4:0]))) << 5 | ((pivot_addr_reg[4:0]) - ((cur_addr_2_reg >> 5) - (pivot_addr_reg >> 5)));
        next_addr_3 = ((pivot_addr_reg >> 5) + ((cur_addr_3_reg[4:0]) - (pivot_addr_reg[4:0]))) << 5 | ((pivot_addr_reg[4:0]) - ((cur_addr_3_reg >> 5) - (pivot_addr_reg >> 5)));
      end
    end
    3'd5:begin
      next_pivot_addr = pivot_addr_reg + 6'd32;
      next_addr_1 = cur_addr_1_reg + 6'd32;
      next_addr_2 = cur_addr_2_reg + 6'd32;
      next_addr_3 = cur_addr_3_reg + 6'd32;
    end
  endcase
  end
endmodule