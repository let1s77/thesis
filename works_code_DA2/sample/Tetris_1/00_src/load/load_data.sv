module load_data (
  input logic clk,
  input logic rst_n,
  input logic       load_data_start,
  input logic [2:0] piece_id_data,
  input logic [2:0] piece_id_next,
  input logic [7:0] lvl_data_reg,
  input logic [19:0] score_data_reg,
  input logic [19:0] top_score_data_reg,
  input logic [9:0] line_data_reg,
  
  output logic         load_data_done,

  output logic       wr_4,rd_4,
  output logic [9:0] addr_4,
  output logic [8:0] piece_id_wr_4
);
  
logic [5:0] color_offset;

logic [3:0] lv_num_1,lv_num_2;
logic [3:0] line_num_1,line_num_2,line_num_3;
logic [3:0] score_num_1,score_num_2,score_num_3,score_num_4,score_num_5,score_num_6;
logic [3:0] top_score_num_1,top_score_num_2,top_score_num_3,top_score_num_4,top_score_num_5,top_score_num_6;

assign color_offset = (lvl_data_reg % 8'd10)*3'd4;
assign lv_num_1 = (lvl_data_reg/32'd10) % 8'd10;
assign lv_num_2 = lvl_data_reg % 8'd10;

assign line_num_1 = (line_data_reg/32'd100) % 8'd10;
assign line_num_2 = (line_data_reg/32'd10) % 8'd10;
assign line_num_3 = line_data_reg % 8'd10;

assign score_num_1 = (score_data_reg/32'd100000) % 8'd10;
assign score_num_2 = (score_data_reg/32'd10000) % 8'd10;
assign score_num_3 = (score_data_reg/32'd1000) % 8'd10;
assign score_num_4 = (score_data_reg/32'd100) % 8'd10;
assign score_num_5 = (score_data_reg/32'd10) % 8'd10;
assign score_num_6 = score_data_reg % 8'd10;


assign top_score_num_1 = (top_score_data_reg/32'd100000) % 8'd10;
assign top_score_num_2 = (top_score_data_reg/32'd10000) % 8'd10;
assign top_score_num_3 = (top_score_data_reg/32'd1000) % 8'd10;
assign top_score_num_4 = (top_score_data_reg/32'd100) % 8'd10;
assign top_score_num_5 = (top_score_data_reg/32'd10) % 8'd10;
assign top_score_num_6 = top_score_data_reg % 8'd10;
//FSM
typedef enum logic [5:0] {
  IDLE                 = 6'd0,
  WAIT_FOR_START       = 6'd1,
  LOAD_NEXT_PIECE_1    = 6'd2,
  LOAD_NEXT_PIECE_2    = 6'd3,
  LOAD_NEXT_PIECE_3    = 6'd4,
  LOAD_NEXT_PIECE_4    = 6'd5,
  LOAD_NEXT_PIECE_5    = 6'd6,
  LOAD_NEXT_PIECE_6    = 6'd7,
  LOAD_NEXT_PIECE_7    = 6'd8,
  LOAD_NEXT_PIECE_8    = 6'd9,
  LOAD_LV_1            = 6'd10,
  LOAD_LV_2            = 6'd11,
  LOAD_LINE_1          = 6'd12,
  LOAD_LINE_2          = 6'd13,
  LOAD_LINE_3          = 6'd14,
  LOAD_SCORE_1         = 6'd15,
  LOAD_SCORE_2         = 6'd16,
  LOAD_SCORE_3         = 6'd17,
  LOAD_SCORE_4         = 6'd18,
  LOAD_SCORE_5         = 6'd19,
  LOAD_SCORE_6         = 6'd20,
  LOAD_CURRENT_PIECE_1 = 6'd21,
  LOAD_CURRENT_PIECE_2 = 6'd22,
  LOAD_CURRENT_PIECE_3 = 6'd23,
  LOAD_CURRENT_PIECE_4 = 6'd24,
  LOAD_CURRENT_PIECE_5 = 6'd25,
  LOAD_CURRENT_PIECE_6 = 6'd26,
  LOAD_CURRENT_PIECE_7 = 6'd27,
  LOAD_CURRENT_PIECE_8 = 6'd28,

  LOAD_TOP_SCORE_1     = 6'd29,
  LOAD_TOP_SCORE_2     = 6'd30,
  LOAD_TOP_SCORE_3     = 6'd31,
  LOAD_TOP_SCORE_4     = 6'd32,
  LOAD_TOP_SCORE_5     = 6'd33,
  LOAD_TOP_SCORE_6     = 6'd34,
  DONE              = 6'd35
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
      next_state = load_data_start ? LOAD_NEXT_PIECE_1 : WAIT_FOR_START;
    end

    LOAD_NEXT_PIECE_1: begin
      next_state = LOAD_NEXT_PIECE_2;
    end

    LOAD_NEXT_PIECE_2: begin
      next_state = LOAD_NEXT_PIECE_3;
    end

    LOAD_NEXT_PIECE_3: begin
      next_state = LOAD_NEXT_PIECE_4;
    end

    LOAD_NEXT_PIECE_4: begin
      next_state = LOAD_NEXT_PIECE_5;
    end

    LOAD_NEXT_PIECE_5: begin
      next_state = LOAD_NEXT_PIECE_6;
    end

    LOAD_NEXT_PIECE_6: begin
      next_state = LOAD_NEXT_PIECE_7;
    end

    LOAD_NEXT_PIECE_7: begin
      next_state = LOAD_NEXT_PIECE_8;
    end

    LOAD_NEXT_PIECE_8: begin
      next_state = LOAD_LV_1;
    end

    LOAD_LV_1: begin
      next_state = LOAD_LV_2;
    end

    LOAD_LV_2: begin
      next_state = LOAD_LINE_1;
    end

    LOAD_LINE_1: begin
      next_state = LOAD_LINE_2;
    end

    LOAD_LINE_2: begin
      next_state = LOAD_LINE_3;
    end

    LOAD_LINE_3: begin
      next_state = LOAD_SCORE_1;
    end

    LOAD_SCORE_1: begin
      next_state = LOAD_SCORE_2;
    end

    LOAD_SCORE_2: begin
      next_state = LOAD_SCORE_3;
    end

    LOAD_SCORE_3: begin
      next_state = LOAD_SCORE_4;
    end

    LOAD_SCORE_4: begin
      next_state = LOAD_SCORE_5;
    end

    LOAD_SCORE_5: begin
      next_state = LOAD_SCORE_6;
    end

    LOAD_SCORE_6: begin
      next_state = LOAD_CURRENT_PIECE_1;
    end
    
    LOAD_CURRENT_PIECE_1: begin
      next_state = LOAD_CURRENT_PIECE_2;
    end

    LOAD_CURRENT_PIECE_2: begin
      next_state = LOAD_CURRENT_PIECE_3;
    end

    LOAD_CURRENT_PIECE_3: begin
      next_state = LOAD_CURRENT_PIECE_4;
    end

    
    LOAD_CURRENT_PIECE_4: begin
      next_state = LOAD_CURRENT_PIECE_5;
    end

    
    LOAD_CURRENT_PIECE_5: begin
      next_state = LOAD_CURRENT_PIECE_6;
    end

    
    LOAD_CURRENT_PIECE_6: begin
      next_state = LOAD_CURRENT_PIECE_7;
    end

    
    LOAD_CURRENT_PIECE_7: begin
      next_state = LOAD_CURRENT_PIECE_8;
    end

    
    LOAD_CURRENT_PIECE_8: begin
      next_state = LOAD_TOP_SCORE_1;
    end


   LOAD_TOP_SCORE_1: begin
      next_state = LOAD_TOP_SCORE_2;
    end

    LOAD_TOP_SCORE_2: begin
      next_state = LOAD_TOP_SCORE_3;
    end

    LOAD_TOP_SCORE_3: begin
      next_state = LOAD_TOP_SCORE_4;
    end

    LOAD_TOP_SCORE_4: begin
      next_state = LOAD_TOP_SCORE_5;
    end

    LOAD_TOP_SCORE_5: begin
      next_state = LOAD_TOP_SCORE_6;
    end

    LOAD_TOP_SCORE_6: begin
      next_state = DONE;
    end


    DONE: begin
      next_state = IDLE;
    end
  endcase
end

always_comb begin
  load_data_done = 1'b0;
  addr_4 = 10'b0;
  wr_4 = 1'b0;
  rd_4 = 1'b0;
  piece_id_wr_4 = 9'd0;
  case(current_state)
    IDLE:
    begin
      load_data_done = 1'b0;
      addr_4 = 10'b0;
      piece_id_wr_4 = 9'd0;
    end

    LOAD_NEXT_PIECE_1:
    begin
      addr_4 = 10'd475;
      wr_4 = 1'b1;
      case(piece_id_next)
        3'd0:piece_id_wr_4 = 9'd242 + color_offset;
        3'd1:piece_id_wr_4 = 9'd243 + color_offset;
        3'd2:piece_id_wr_4 = 9'd244 + color_offset;
        3'd3:piece_id_wr_4 = 9'd18;
        3'd4:piece_id_wr_4 = 9'd18;
        3'd5:piece_id_wr_4 = 9'd244 + color_offset;
        3'd6:piece_id_wr_4 = 9'd242 + color_offset;
        3'd7:piece_id_wr_4 = 9'd18;
        default:piece_id_wr_4 = 9'd18;
      endcase
    end

    LOAD_NEXT_PIECE_2:
    begin
      addr_4 = 10'd476;
      wr_4 = 1'b1;
      case(piece_id_next)
        3'd0:piece_id_wr_4 = 9'd242 + color_offset;
        3'd1:piece_id_wr_4 = 9'd243 + color_offset;
        3'd2:piece_id_wr_4 = 9'd244 + color_offset;
        3'd3:piece_id_wr_4 = 9'd241 + color_offset;
        3'd4:piece_id_wr_4 = 9'd243 + color_offset;
        3'd5:piece_id_wr_4 = 9'd244 + color_offset;
        3'd6:piece_id_wr_4 = 9'd242 + color_offset;
        3'd7:piece_id_wr_4 = 9'd18;
        default:piece_id_wr_4 = 9'd18;
      endcase
    end
    LOAD_NEXT_PIECE_3:
    begin
      addr_4 = 10'd477;
      wr_4 = 1'b1;
      case(piece_id_next)
        3'd0:piece_id_wr_4 = 9'd242 + color_offset;
        3'd1:piece_id_wr_4 = 9'd243 + color_offset;
        3'd2:piece_id_wr_4 = 9'd18;
        3'd3:piece_id_wr_4 = 9'd241 + color_offset;
        3'd4:piece_id_wr_4 = 9'd243 + color_offset;
        3'd5:piece_id_wr_4 = 9'd244 + color_offset;
        3'd6:piece_id_wr_4 = 9'd242 + color_offset;
        3'd7:piece_id_wr_4 = 9'd18;
        default:piece_id_wr_4 = 9'd18;
      endcase
    end

    LOAD_NEXT_PIECE_4:
    begin
      addr_4 = 10'd478;
      wr_4 = 1'b1;
      case(piece_id_next)
        3'd0:piece_id_wr_4 = 9'd18;
        3'd1:piece_id_wr_4 = 9'd18;
        3'd2:piece_id_wr_4 = 9'd18;
        3'd3:piece_id_wr_4 = 9'd18;
        3'd4:piece_id_wr_4 = 9'd18;
        3'd5:piece_id_wr_4 = 9'd18;
        3'd6:piece_id_wr_4 = 9'd242 + color_offset;
        3'd7:piece_id_wr_4 = 9'd18;
        default:piece_id_wr_4 = 9'd18;
      endcase
    end

    LOAD_NEXT_PIECE_5:
    begin
      addr_4 = 10'd507;
      wr_4 = 1'b1;
      case(piece_id_next)
        3'd0:piece_id_wr_4 = 9'd18;
        3'd1:piece_id_wr_4 = 9'd18;
        3'd2:piece_id_wr_4 = 9'd18;
        3'd3:piece_id_wr_4 = 9'd18;
        3'd4:piece_id_wr_4 = 9'd243 + color_offset;
        3'd5:piece_id_wr_4 = 9'd244 + color_offset;
        3'd6:piece_id_wr_4 = 9'd18;
        3'd7:piece_id_wr_4 = 9'd18;
        default:piece_id_wr_4 = 9'd18;
      endcase
    end

    LOAD_NEXT_PIECE_6:
    begin
      addr_4 = 10'd508;
      wr_4 = 1'b1;
      case(piece_id_next)
        3'd0: piece_id_wr_4 = 9'd242 + color_offset;
        3'd1:piece_id_wr_4 = 9'd18;
        3'd2:piece_id_wr_4 = 9'd244 + color_offset;
        3'd3:piece_id_wr_4 = 9'd241 + color_offset;
        3'd4:piece_id_wr_4 = 9'd243 + color_offset;
        3'd5:piece_id_wr_4 = 9'd18;
        3'd6:piece_id_wr_4 = 9'd18;
        3'd7:piece_id_wr_4 = 9'd18;
        default:piece_id_wr_4 = 9'd18;
      endcase
    end

    LOAD_NEXT_PIECE_7:
    begin
      addr_4 = 10'd509;
      wr_4 = 1'b1;
      case(piece_id_next)
        3'd0:piece_id_wr_4 = 9'd18;
        3'd1:piece_id_wr_4 = 9'd243 + color_offset;
        3'd2:piece_id_wr_4 = 9'd244 + color_offset;
        3'd3:piece_id_wr_4 = 9'd241 + color_offset;
        3'd4:piece_id_wr_4 = 9'd18;
        3'd5:piece_id_wr_4 = 9'd18;
        3'd6:piece_id_wr_4 = 9'd18;
        3'd7:piece_id_wr_4 = 9'd18;
        default:piece_id_wr_4 = 9'd18;
      endcase
    end

    LOAD_NEXT_PIECE_8:
    begin
      addr_4 = 10'd510;
      wr_4 = 1'b1;
      case(piece_id_next)
        3'd0:piece_id_wr_4 = 9'd18;
        3'd1:piece_id_wr_4 = 9'd18;
        3'd2:piece_id_wr_4 = 9'd18;
        3'd3:piece_id_wr_4 = 9'd18;
        3'd4:piece_id_wr_4 = 9'd18;
        3'd5:piece_id_wr_4 = 9'd18;
        3'd6:piece_id_wr_4 = 9'd18;
        3'd7:piece_id_wr_4 = 9'd18;
        default:piece_id_wr_4 = 9'd18;
      endcase
    end

    LOAD_LV_1:
    begin
      piece_id_wr_4 = lv_num_1 + 8'd210;
      addr_4 = 10'd668;
      wr_4 = 1'b1;
    end

    LOAD_LV_2:
    begin
      piece_id_wr_4 = lv_num_2 + 8'd210;
      addr_4 = 10'd669;
      wr_4 = 1'b1;
    end

    LOAD_LINE_1:
    begin
      piece_id_wr_4 = line_num_1 + 8'd210;
      addr_4 = 10'd84;
      wr_4 = 1'b1;
    end

    LOAD_LINE_2:
    begin
      piece_id_wr_4 = line_num_2 + 8'd210;
      addr_4 = 10'd85;
      wr_4 = 1'b1;
    end

    LOAD_LINE_3:
    begin
      piece_id_wr_4 = line_num_3 + 8'd210;
      addr_4 = 10'd86;
      wr_4 = 1'b1;
    end

    LOAD_SCORE_1:
    begin
      piece_id_wr_4 = score_num_1 + 8'd210;
      addr_4 = 10'd217;
      wr_4 = 1'b1;
    end

    LOAD_SCORE_2:
    begin
      piece_id_wr_4 = score_num_2 + 8'd210;
      addr_4 = 10'd218;
      wr_4 = 1'b1;
    end

    LOAD_SCORE_3:
    begin
      piece_id_wr_4 = score_num_3 + 8'd210;
      addr_4 = 10'd219;
      wr_4 = 1'b1;;
    end

    LOAD_SCORE_4:
    begin
      piece_id_wr_4 = score_num_4 + 8'd210;
      addr_4 = 10'd220;
      wr_4 = 1'b1;
    end

    LOAD_SCORE_5:
    begin
      piece_id_wr_4 = score_num_5 + 8'd210;
      addr_4 = 10'd221;
      wr_4 = 1'b1;
    end

    LOAD_SCORE_6:
    begin
      piece_id_wr_4 = score_num_6 + 8'd210;
      addr_4 = 10'd222;
      wr_4 = 1'b1;
    end


    LOAD_CURRENT_PIECE_1:
    begin
      addr_4 = 10'd176;
      wr_4 = 1'b1;
      case(piece_id_data)
        3'd0:piece_id_wr_4 = 9'd242 + color_offset;
        3'd1:piece_id_wr_4 = 9'd243 + color_offset;
        3'd2:piece_id_wr_4 = 9'd244 + color_offset;
        3'd3:piece_id_wr_4 = 9'd18;
        3'd4:piece_id_wr_4 = 9'd18;
        3'd5:piece_id_wr_4 = 9'd244 + color_offset;
        3'd6:piece_id_wr_4 = 9'd242 + color_offset;
        3'd7:piece_id_wr_4 = 9'd18;
        default:piece_id_wr_4 = 9'd18;
      endcase
    end

    LOAD_CURRENT_PIECE_2:
    begin
      addr_4 = 10'd177;
      wr_4 = 1'b1;
      case(piece_id_data)
        3'd0:piece_id_wr_4 = 9'd242 + color_offset;
        3'd1:piece_id_wr_4 = 9'd243 + color_offset;
        3'd2:piece_id_wr_4 = 9'd244 + color_offset;
        3'd3:piece_id_wr_4 = 9'd241 + color_offset;
        3'd4:piece_id_wr_4 = 9'd243 + color_offset;
        3'd5:piece_id_wr_4 = 9'd244 + color_offset;
        3'd6:piece_id_wr_4 = 9'd242 + color_offset;
        3'd7:piece_id_wr_4 = 9'd18;
        default:piece_id_wr_4 = 9'd18;
      endcase
    end
    LOAD_CURRENT_PIECE_3:
    begin
      addr_4 = 10'd178;
      wr_4 = 1'b1;
      case(piece_id_data)
        3'd0:piece_id_wr_4 = 9'd242 + color_offset;
        3'd1:piece_id_wr_4 = 9'd243 + color_offset;
        3'd2:piece_id_wr_4 = 9'd18;
        3'd3:piece_id_wr_4 = 9'd241 + color_offset;
        3'd4:piece_id_wr_4 = 9'd243 + color_offset;
        3'd5:piece_id_wr_4 = 9'd244 + color_offset;
        3'd6:piece_id_wr_4 = 9'd242 + color_offset;
        3'd7:piece_id_wr_4 = 9'd18;
        default:piece_id_wr_4 = 9'd18;
      endcase
    end

    LOAD_CURRENT_PIECE_4:
    begin
      addr_4 = 10'd179;
      wr_4 = 1'b1;
      case(piece_id_data)
        3'd0:piece_id_wr_4 = 9'd18;
        3'd1:piece_id_wr_4 = 9'd18;
        3'd2:piece_id_wr_4 = 9'd18;
        3'd3:piece_id_wr_4 = 9'd18;
        3'd4:piece_id_wr_4 = 9'd18;
        3'd5:piece_id_wr_4 = 9'd18;
        3'd6:piece_id_wr_4 = 9'd242 + color_offset;
        3'd7:piece_id_wr_4 = 9'd18;
        default:piece_id_wr_4 = 9'd18;
      endcase
    end

    LOAD_CURRENT_PIECE_5:
    begin
      addr_4 = 10'd208;
      wr_4 = 1'b1;
      case(piece_id_data)
        3'd0:piece_id_wr_4 = 9'd18;
        3'd1:piece_id_wr_4 = 9'd18;
        3'd2:piece_id_wr_4 = 9'd18;
        3'd3:piece_id_wr_4 = 9'd18;
        3'd4:piece_id_wr_4 = 9'd243 + color_offset;
        3'd5:piece_id_wr_4 = 9'd244 + color_offset;
        3'd6:piece_id_wr_4 = 9'd18;
        3'd7:piece_id_wr_4 = 9'd18;
        default:piece_id_wr_4 = 9'd18;
      endcase
    end

    LOAD_CURRENT_PIECE_6:
    begin
      addr_4 = 10'd209;
      wr_4 = 1'b1;
      case(piece_id_data)
        3'd0:piece_id_wr_4 = 9'd242 + color_offset;
        3'd1:piece_id_wr_4 = 9'd18;
        3'd2:piece_id_wr_4 = 9'd244 + color_offset;
        3'd3:piece_id_wr_4 = 9'd241 + color_offset;
        3'd4:piece_id_wr_4 = 9'd243 + color_offset;
        3'd5:piece_id_wr_4 = 9'd18;
        3'd6:piece_id_wr_4 = 9'd18;
        3'd7:piece_id_wr_4 = 9'd18;
        default:piece_id_wr_4 = 9'd18;
      endcase
    end

    LOAD_CURRENT_PIECE_7:
    begin
      addr_4 = 10'd210;
      wr_4 = 1'b1;
      case(piece_id_data)
        3'd0:piece_id_wr_4 = 9'd18;
        3'd1:piece_id_wr_4 = 9'd243 + color_offset;
        3'd2:piece_id_wr_4 = 9'd244 + color_offset;
        3'd3:piece_id_wr_4 = 9'd241 + color_offset;
        3'd4:piece_id_wr_4 = 9'd18;
        3'd5:piece_id_wr_4 = 9'd18;
        3'd6:piece_id_wr_4 = 9'd18;
        3'd7:piece_id_wr_4 = 9'd18;
        default:piece_id_wr_4 = 9'd18;
      endcase
    end

    LOAD_CURRENT_PIECE_8:
    begin
      addr_4 = 10'd211;
      wr_4 = 1'b1;
      case(piece_id_data)
        3'd0:piece_id_wr_4 = 9'd18;
        3'd1:piece_id_wr_4 = 9'd18;
        3'd2:piece_id_wr_4 = 9'd18;
        3'd3:piece_id_wr_4 = 9'd18;
        3'd4:piece_id_wr_4 = 9'd18;
        3'd5:piece_id_wr_4 = 9'd18;
        3'd6:piece_id_wr_4 = 9'd18;
        3'd7:piece_id_wr_4 = 9'd18;
        default:piece_id_wr_4 = 9'd18;
      endcase
    end

    LOAD_TOP_SCORE_1:
    begin
      piece_id_wr_4 = top_score_num_1 + 8'd210;
      addr_4 = 10'd121;
      wr_4 = 1'b1;
    end

    LOAD_TOP_SCORE_2:
    begin
      piece_id_wr_4 = top_score_num_2 + 8'd210;
      addr_4 = 10'd122;
      wr_4 = 1'b1;
    end

    LOAD_TOP_SCORE_3:
    begin
      piece_id_wr_4 = top_score_num_3 + 8'd210;
      addr_4 = 10'd123;
      wr_4 = 1'b1;;
    end

    LOAD_TOP_SCORE_4:
    begin
      piece_id_wr_4 = top_score_num_4 + 8'd210;
      addr_4 = 10'd124;
      wr_4 = 1'b1;
    end

    LOAD_TOP_SCORE_5:
    begin
      piece_id_wr_4 = top_score_num_5 + 8'd210;
      addr_4 = 10'd125;
      wr_4 = 1'b1;
    end

    LOAD_TOP_SCORE_6:
    begin
      piece_id_wr_4 = top_score_num_6 + 8'd210;
      addr_4 = 10'd126;
      wr_4 = 1'b1;
    end


    DONE:
    begin
      piece_id_wr_4= 9'd0;
      addr_4 = 10'd0;
      load_data_done = 1'b1;
    end
  endcase
end



endmodule