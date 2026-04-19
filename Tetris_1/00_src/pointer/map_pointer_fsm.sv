module map_pointer_fsm (
  input logic clk,
  input logic rst_n,

  input logic pt_load_start,
  
  output logic pt_load_done,

  input logic [7:0] lvl_data_reg,
  input logic [1:0] pt_data,

  output logic [9:0] addr_2,
  output logic [8:0] piece_id_wr_2

);
  
//FSM
typedef enum logic [3:0] {
  IDLE = 4'd0,
  WAIT_FOR_START = 4'd1,
  RUNNING_1 = 4'd2,
  RUNNING_2 = 4'd3,
  RUNNING_3 = 4'd4,
  RUNNING_4 = 4'd5,
  RUNNING_5 = 4'd6,
  RUNNING_6 = 4'd7,
  RUNNING_7 = 4'd8,
  DONE = 4'd9
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
      next_state = pt_load_start ? RUNNING_1 : WAIT_FOR_START;
    end

    RUNNING_1: begin
      next_state = RUNNING_2;
    end

    RUNNING_2: begin
      next_state = RUNNING_3;
    end

    RUNNING_3: begin
      next_state = RUNNING_4;
    end

    RUNNING_4: begin
      next_state = RUNNING_5;
    end

    RUNNING_5: begin
      next_state = RUNNING_6;
    end

    RUNNING_6: begin
      next_state = RUNNING_7;
    end

    RUNNING_7: begin
      next_state = DONE;
    end

    DONE: begin
      next_state = IDLE;
    end
  endcase
end

always_comb begin
  pt_load_done = 1'b0;
  addr_2 = 10'b0;
  piece_id_wr_2 = 9'd0;
  case(current_state)
    IDLE:
    begin
      pt_load_done = 1'b0;
      addr_2 = 10'b0;
      piece_id_wr_2 = 9'd0;
    end

    RUNNING_1:
    begin
      piece_id_wr_2 = 9'd221;
      case(pt_data[1:0])
        2'd0:addr_2 = 10'd0;
        2'd1:addr_2 = 10'd226;
        2'd2:addr_2 = 10'd237;
        2'd3:addr_2 = 10'd248;
        default:addr_2 = 10'd0;
      endcase
    end

    RUNNING_2:
    begin
      piece_id_wr_2 = 9'd222;
      case(pt_data[1:0])
        2'd0:addr_2 = 10'd0;
        2'd1:addr_2 = 10'd233;
        2'd2:addr_2 = 10'd244;
        2'd3:addr_2 = 10'd255;
        default:addr_2 = 10'd0;
      endcase
    end
    RUNNING_3:
    begin
      piece_id_wr_2 = 9'd18;
      case(pt_data[1:0])
        2'd0:addr_2 = 10'd0;
        2'd1:addr_2 = 10'd237;
        2'd2:addr_2 = 10'd226;
        2'd3:addr_2 = 10'd237;
        default:addr_2 = 10'd0;
      endcase
    end

    RUNNING_4:
    begin
      piece_id_wr_2 = 9'd18;
      case(pt_data[1:0])
        2'd0:addr_2 = 10'd0;
        2'd1:addr_2 = 10'd244;
        2'd2:addr_2 = 10'd233;
        2'd3:addr_2 = 10'd244;
        default:addr_2 = 10'd0;
      endcase
    end
    RUNNING_5:
    begin
      piece_id_wr_2 = 9'd18;
      case(pt_data[1:0])
        2'd0:addr_2 = 10'd0;
        2'd1:addr_2 = 10'd248;
        2'd2:addr_2 = 10'd248;
        2'd3:addr_2 = 10'd226;
        default:addr_2 = 10'd0;
      endcase
    end

    RUNNING_6:
    begin
      piece_id_wr_2 = 9'd18;
      case(pt_data[1:0])
        2'd0:addr_2 = 10'd0;
        2'd1:addr_2 = 10'd255;
        2'd2:addr_2 = 10'd255;
        2'd3:addr_2 = 10'd233;
        default:addr_2 = 10'd0;
      endcase
    end
    RUNNING_7:
    begin
      piece_id_wr_2 = 9'd210 + lvl_data_reg;
      addr_2 = 10'd525;
    end
    DONE:
    begin
      piece_id_wr_2= 9'd0;
      addr_2 = 10'b0;
      pt_load_done = 1'b1;
    end
  endcase
end


endmodule