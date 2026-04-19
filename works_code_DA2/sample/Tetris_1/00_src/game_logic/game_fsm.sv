module game_fsm
(
  input logic clk,
  input logic rst_n,

  input logic press_up,
  input logic press_down,
  input logic press_left,
  input logic press_right,
  input logic press_z,
  input logic press_x,
  input logic press_enter,

  output logic select_speed_down,

  output logic [5:0] grid_input_sel,

  //Map load
//In
  input logic map_load_done,
//Out
  output logic map_load_start,
  output logic [2:0] map_id,

  //Pointer load
//In
  input logic pt_load_done,
//Out
  output logic pt_load_start,

  //Pointer load
//In
  input logic  [1:0] pt_data_reg,
//Out
  output logic       pt_data_en,
  output logic [1:0] pt_data,

  //Lv load
//Out
  output logic       lvl_aclr,
  output logic       lvl_en,
  output logic       lvl_updown,
//In
  input logic  [7:0] lvl_data_reg,
  input logic  [7:0] current_lvl,
  //New piece
  output logic       en_gen,
  output logic       st_piece,

  //Lose checking
  output logic [9:0] addr_3,

  output logic       wr_3,
  output logic       rd_3,

  input logic        lose_condition,

  //Load all data
  input logic        load_data_done,
  output logic       load_data_start,

  //Load position
  output logic [9:0] pivot_addr,
  output logic [9:0] init_addr_1,init_addr_2,init_addr_3,
  output logic       st_addr,

  //Control rotate
  input logic [1:0]  rotate_status,


  
  //Current position
  input logic [9:0] pivot_addr_reg,
  input logic [9:0] cur_addr_1_reg,
  input logic [9:0] cur_addr_2_reg,
  input logic [9:0] cur_addr_3_reg,
  //Checking
  input logic        check_left_fail,
  input logic        check_right_fail,
  input logic        check_down_fail,
  input logic        check_clockwise_fail,
  input logic        check_counter_clockwise_fail,

  //Cal_next addrr
  input logic [9:0] next_pivot_addr,
  input logic [9:0] next_addr_1,next_addr_2,next_addr_3,

  //Color
  output logic [8:0] color_data,
  output logic       color_en,


  input logic        move_done,

  output logic       move_start,
  output logic [2:0] move_data,

  input logic        time_equal,
  output logic       en_timer,aclr_timer,

  input logic  [2:0] piece_id_data,

  //Clear line
  input logic        clear_line_done,
  output logic       clear_line_start,
  //Line counter
//Out
  output logic line_counter_aclr,

  // Score
//Out
  output logic score_data_en,
  output logic drop_score_aclr,
  output logic drop_score_cnt_en,
  output logic score_data_aclr,

  output logic clear_score_aclr,

  output logic top_score_data_en,

  input logic update_score,

  output logic [6:0] cstate
);

logic [8:0] color_offset;
assign color_offset = (current_lvl % 8'd10)*3'd4;
// color_offset = 0;
typedef enum logic [6:0] {
  IDLE                              = 7'd0,
  LOAD_MAP1                         = 7'd1, 
  PRESS_START                       = 7'd2,
  LOAD_MAP2                         = 7'd3, 
  LOAD_PT_A                         = 7'd4, 
  SET_A                             = 7'd5,
  LOAD_PT_B                         = 7'd6, 
  SET_B                             = 7'd7,
  LOAD_PT_C                         = 7'd8, 
  SET_C                             = 7'd9,
  INC_SET_LV                        = 7'd10,
  DEC_SET_LV                        = 7'd11,

  LOAD_MAP3                         = 7'd12,
  GEN_PIECE                         = 7'd13,
  ST_PIECE                          = 7'd14,
  LOAD_DATA                         = 7'd15, //Type + LV
  CHECK_LOSE_00                     = 7'd16,
  CHECK_LOSE_01                     = 7'd17,
  CHECK_LOSE_02                     = 7'd18,
  CHECK_LOSE_03                     = 7'd19,
  CHECK_LOSE_04                     = 7'd20,
  LOSE_SCREEN_0                     = 7'd21,

  START_GAME                        = 7'd22,

  CHECK_LEFT_00                     = 7'd23,
  CHECK_LEFT_01                     = 7'd24,
  CHECK_LEFT_02                     = 7'd25,
  CHECK_LEFT_03                     = 7'd26,
  CHECK_LEFT_04                     = 7'd27,
  MOVE_LEFT                         = 7'd28,

  CHECK_RIGHT_00                    = 7'd29,
  CHECK_RIGHT_01                    = 7'd30,
  CHECK_RIGHT_02                    = 7'd31,
  CHECK_RIGHT_03                    = 7'd32,
  CHECK_RIGHT_04                    = 7'd33,
  MOVE_RIGHT                        = 7'd34,

  CHECK_ROTATE_CLOCKWISE_00         = 7'd35,
  CHECK_ROTATE_CLOCKWISE_01         = 7'd36,
  CHECK_ROTATE_CLOCKWISE_02         = 7'd37,
  CHECK_ROTATE_CLOCKWISE_03         = 7'd38,
  CHECK_ROTATE_CLOCKWISE_04         = 7'd39,
  MOVE_ROTATE_CLOCKWISE             = 7'd40,

  CHECK_ROTATE_COUNTER_CLOCKWISE_00 = 7'd41,
  CHECK_ROTATE_COUNTER_CLOCKWISE_01 = 7'd42,
  CHECK_ROTATE_COUNTER_CLOCKWISE_02 = 7'd43,
  CHECK_ROTATE_COUNTER_CLOCKWISE_03 = 7'd44,
  CHECK_ROTATE_COUNTER_CLOCKWISE_04 = 7'd45,
  MOVE_ROTATE_COUNTER_CLOCKWISE     = 7'd46,

  CHECK_DOWN_00                     = 7'd47,
  CHECK_DOWN_01                     = 7'd48,
  CHECK_DOWN_02                     = 7'd49,
  CHECK_DOWN_03                     = 7'd50,
  CHECK_DOWN_04                     = 7'd51,
  MOVE_DOWN                         = 7'd52,
  CHECK_TIME                        = 7'd53,

  LOAD_ADDRESS                      = 7'd54,

  LOSE_SCREEN_1                     = 7'd55,
  CLEAR_CLOCK                       = 7'd56,
  DO_NOT                            = 7'd57,
  CLEAR_LINE                        = 7'd58,
  CAL_SCORE                         = 7'd59,
  CHECK_TOP_SCORE                   = 7'd60,
  UPDATE_TOP_SCORE                  = 7'd61


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
      next_state = LOAD_MAP1;
    end

    LOAD_MAP1: begin
      next_state = map_load_done ? PRESS_START : LOAD_MAP1;
    end

    PRESS_START: begin
      next_state = press_enter ? LOAD_MAP2 : PRESS_START;
    end

    LOAD_MAP2: begin
      next_state = map_load_done ? LOAD_PT_A : LOAD_MAP2;
    end

    LOAD_PT_A: begin
      next_state = pt_load_done ? SET_A : LOAD_PT_A;
    end

    SET_A: begin
      next_state = press_right ? LOAD_PT_B : press_down ? DEC_SET_LV : press_up ? INC_SET_LV : press_enter ? LOAD_MAP3 : SET_A;
    end

    LOAD_PT_B: begin
      next_state = pt_load_done ? SET_B : LOAD_PT_B;
    end

    SET_B: begin
      next_state = press_left ? LOAD_PT_A : press_right ? LOAD_PT_C: press_down ? DEC_SET_LV : press_up ? INC_SET_LV : SET_B;
    end
    LOAD_PT_C: begin
      next_state = pt_load_done ? SET_C : LOAD_PT_C;
    end

    SET_C: begin
      next_state = press_left ? LOAD_PT_B : press_down ? DEC_SET_LV : press_up ? INC_SET_LV : SET_C;
    end

    INC_SET_LV: begin
      case(pt_data_reg)
        2'b00:next_state = LOAD_PT_A;
        2'b01:next_state = LOAD_PT_A;
        2'b10:next_state = LOAD_PT_B;
        2'b11:next_state = LOAD_PT_C;
      endcase
    end
    DEC_SET_LV: begin
      case(pt_data_reg) 
        2'b00:next_state = LOAD_PT_A;
        2'b01:next_state = LOAD_PT_A;
        2'b10:next_state = LOAD_PT_B;
        2'b11:next_state = LOAD_PT_C;
      endcase
    end
    LOAD_MAP3:begin
      next_state = map_load_done ? ST_PIECE : LOAD_MAP3;
    end
    GEN_PIECE:begin
      next_state = CHECK_LOSE_00;
    end
    ST_PIECE:begin
      next_state = GEN_PIECE;
    end
    CHECK_LOSE_00:begin
      next_state = CHECK_LOSE_01;
    end

    CHECK_LOSE_01:begin
      next_state = lose_condition ? LOSE_SCREEN_0 : CHECK_LOSE_02;
    end

    CHECK_LOSE_02:begin
      next_state = lose_condition ? LOSE_SCREEN_0 : CHECK_LOSE_03;
    end

    CHECK_LOSE_03:begin
      next_state = lose_condition ? LOSE_SCREEN_0 : CHECK_LOSE_04;
    end

    CHECK_LOSE_04:begin
      next_state = lose_condition ? LOSE_SCREEN_0 : LOAD_DATA;
    end

    LOAD_DATA:begin
      next_state = load_data_done ? LOAD_ADDRESS : LOAD_DATA;
    end

    LOAD_ADDRESS:begin
      next_state = START_GAME;
    end

    LOSE_SCREEN_0:begin
      next_state = map_load_done ? LOSE_SCREEN_1 : LOSE_SCREEN_0;
    end

    LOSE_SCREEN_1:begin
      next_state = press_enter ? CHECK_TOP_SCORE : LOSE_SCREEN_1;
    end

    CHECK_TOP_SCORE:begin
      next_state = update_score ? UPDATE_TOP_SCORE : IDLE;
    end
    UPDATE_TOP_SCORE:begin
      next_state = IDLE;
    end
    START_GAME:begin
      next_state = press_left ? CHECK_LEFT_00 : press_right ? CHECK_RIGHT_00 : press_x ? CHECK_ROTATE_CLOCKWISE_00 : press_z ? CHECK_ROTATE_COUNTER_CLOCKWISE_00 : press_down ? CHECK_DOWN_00 : CHECK_TIME;
    end
    //Check
    CHECK_LEFT_00:begin
      next_state = CHECK_LEFT_01;
    end

    CHECK_LEFT_01:begin
      next_state = (next_pivot_addr==cur_addr_1_reg||next_pivot_addr==cur_addr_2_reg||next_pivot_addr==cur_addr_3_reg) ? CHECK_LEFT_02 : check_left_fail ? CHECK_TIME : CHECK_LEFT_02;
    end

    CHECK_LEFT_02:begin
      next_state = (next_addr_1==pivot_addr_reg||next_addr_1==cur_addr_2_reg||next_addr_1==cur_addr_3_reg) ? CHECK_LEFT_03 : check_left_fail ? CHECK_TIME : CHECK_LEFT_03;
    end

    CHECK_LEFT_03:begin
      next_state = (next_addr_2==pivot_addr_reg||next_addr_2==cur_addr_1_reg||next_addr_2==cur_addr_3_reg) ? CHECK_LEFT_04 : check_left_fail ? CHECK_TIME : CHECK_LEFT_04;
    end

    CHECK_LEFT_04:begin
      next_state = (next_addr_3==pivot_addr_reg||next_addr_3==cur_addr_2_reg||next_addr_3==cur_addr_1_reg) ? MOVE_LEFT : check_left_fail ? CHECK_TIME : MOVE_LEFT;
    end

    MOVE_LEFT:begin
      next_state = move_done ? CHECK_TIME : MOVE_LEFT;
    end

    //Check
    CHECK_RIGHT_00:begin
      next_state = CHECK_RIGHT_01;
    end

    CHECK_RIGHT_01:begin
      next_state = (next_pivot_addr==cur_addr_1_reg||next_pivot_addr==cur_addr_2_reg||next_pivot_addr==cur_addr_3_reg) ? CHECK_RIGHT_02 : check_right_fail ? CHECK_TIME : CHECK_RIGHT_02;
    end

    CHECK_RIGHT_02:begin
      next_state = (next_addr_1==pivot_addr_reg||next_addr_1==cur_addr_2_reg||next_addr_1==cur_addr_3_reg) ? CHECK_RIGHT_03 : check_right_fail ? CHECK_TIME : CHECK_RIGHT_03;
    end

    CHECK_RIGHT_03:begin
      next_state = (next_addr_2==pivot_addr_reg||next_addr_2==cur_addr_1_reg||next_addr_2==cur_addr_3_reg) ? CHECK_RIGHT_04 : check_right_fail ? CHECK_TIME : CHECK_RIGHT_04;
    end

    CHECK_RIGHT_04:begin
      next_state = (next_addr_3==pivot_addr_reg||next_addr_3==cur_addr_2_reg||next_addr_3==cur_addr_1_reg) ? MOVE_RIGHT : check_right_fail ? CHECK_TIME : MOVE_RIGHT;
    end

    MOVE_RIGHT:begin
      next_state = move_done ? CHECK_TIME : MOVE_RIGHT;
    end



    //Check
    CHECK_ROTATE_CLOCKWISE_00:begin
      next_state = CHECK_ROTATE_CLOCKWISE_01;
    end

    CHECK_ROTATE_CLOCKWISE_01:begin
      next_state = CHECK_ROTATE_CLOCKWISE_02;
    end

    CHECK_ROTATE_CLOCKWISE_02:begin
      next_state = (next_addr_1==pivot_addr_reg||next_addr_1==cur_addr_2_reg||next_addr_1==cur_addr_3_reg) ? CHECK_ROTATE_CLOCKWISE_03 : check_clockwise_fail ? CHECK_TIME : CHECK_ROTATE_CLOCKWISE_03;
    end

    CHECK_ROTATE_CLOCKWISE_03:begin
      next_state = (next_addr_2==pivot_addr_reg||next_addr_2==cur_addr_1_reg||next_addr_2==cur_addr_3_reg) ? CHECK_ROTATE_CLOCKWISE_04 : check_clockwise_fail ? CHECK_TIME : CHECK_ROTATE_CLOCKWISE_04;
    end

    CHECK_ROTATE_CLOCKWISE_04:begin
      next_state = (next_addr_3==pivot_addr_reg||next_addr_3==cur_addr_2_reg||next_addr_3==cur_addr_1_reg) ? MOVE_ROTATE_CLOCKWISE : check_clockwise_fail ? CHECK_TIME : MOVE_ROTATE_CLOCKWISE;
    end

    MOVE_ROTATE_CLOCKWISE:begin
      next_state = move_done ? CHECK_TIME : MOVE_ROTATE_CLOCKWISE;
    end


    //Check
    CHECK_ROTATE_COUNTER_CLOCKWISE_00:begin
      next_state = CHECK_ROTATE_COUNTER_CLOCKWISE_01;
    end

    CHECK_ROTATE_COUNTER_CLOCKWISE_01:begin
      next_state = CHECK_ROTATE_COUNTER_CLOCKWISE_02;
    end

    CHECK_ROTATE_COUNTER_CLOCKWISE_02:begin
      next_state = (next_addr_1==pivot_addr_reg||next_addr_1==cur_addr_2_reg||next_addr_1==cur_addr_3_reg) ? CHECK_ROTATE_COUNTER_CLOCKWISE_03 : check_counter_clockwise_fail ? CHECK_TIME : CHECK_ROTATE_COUNTER_CLOCKWISE_03;
    end

    CHECK_ROTATE_COUNTER_CLOCKWISE_03:begin
      next_state = (next_addr_2==pivot_addr_reg||next_addr_2==cur_addr_1_reg||next_addr_2==cur_addr_3_reg) ? CHECK_ROTATE_COUNTER_CLOCKWISE_04 : check_counter_clockwise_fail ? CHECK_TIME : CHECK_ROTATE_COUNTER_CLOCKWISE_04;
    end

    CHECK_ROTATE_COUNTER_CLOCKWISE_04:begin
      next_state = (next_addr_3==pivot_addr_reg||next_addr_3==cur_addr_2_reg||next_addr_3==cur_addr_1_reg) ? MOVE_ROTATE_COUNTER_CLOCKWISE : check_counter_clockwise_fail ? CHECK_TIME : MOVE_ROTATE_COUNTER_CLOCKWISE;
    end

    MOVE_ROTATE_COUNTER_CLOCKWISE:begin
      next_state = move_done ? CHECK_TIME : MOVE_ROTATE_COUNTER_CLOCKWISE;
    end

    CHECK_DOWN_00:begin
      next_state = CHECK_DOWN_01;
    end

    CHECK_DOWN_01:begin
      next_state = (next_pivot_addr==cur_addr_1_reg||next_pivot_addr==cur_addr_2_reg||next_pivot_addr==cur_addr_3_reg) ? CHECK_DOWN_02 : check_down_fail ? CLEAR_LINE : CHECK_DOWN_02;
    end

    CHECK_DOWN_02:begin
      next_state = (next_addr_1==pivot_addr_reg||next_addr_1==cur_addr_2_reg||next_addr_1==cur_addr_3_reg) ? CHECK_DOWN_03 : check_down_fail ? CLEAR_LINE : CHECK_DOWN_03;
    end

    CHECK_DOWN_03:begin
      next_state = (next_addr_2==pivot_addr_reg||next_addr_2==cur_addr_1_reg||next_addr_2==cur_addr_3_reg) ? CHECK_DOWN_04 : check_down_fail ? CLEAR_LINE : CHECK_DOWN_04;
    end

    CHECK_DOWN_04:begin
      next_state = (next_addr_3==pivot_addr_reg||next_addr_3==cur_addr_2_reg||next_addr_3==cur_addr_1_reg) ? MOVE_DOWN : check_down_fail ? CLEAR_LINE : MOVE_DOWN;
    end

    MOVE_DOWN:begin
      next_state = move_done ? CLEAR_CLOCK : MOVE_DOWN;
    end

    CLEAR_CLOCK:begin
      next_state = START_GAME;
    end
    
    CLEAR_LINE: begin
      next_state = clear_line_done ? CAL_SCORE :CLEAR_LINE;
    end

    CHECK_TIME:begin 
      next_state = time_equal ? CHECK_DOWN_00 : START_GAME;
    end

    CAL_SCORE: begin
      next_state = ST_PIECE;
    end

    DO_NOT:begin
      next_state = DO_NOT;
    end
  endcase
end

always_comb begin
  aclr_timer = 1'b0;
  en_timer = 1'b0;
  move_start = 1'b0;
  move_data = 3'd0;
  load_data_start = 1'b0;


  grid_input_sel = 6'd0;

  map_id = 3'd0;
  map_load_start = 1'b0;

  pt_load_start = 1'b0;
  pt_data_en = 1'b0;
  pt_data = 2'b00;

  lvl_aclr = 1'b0;
  lvl_en = 1'b0;
  lvl_updown = 1'b0;

  en_gen = 1'b0;
  st_piece = 1'b0;
  
  addr_3 = 10'd0;
  wr_3 = 1'b0;
  rd_3 = 1'b0;

  st_addr = 1'b0;
  pivot_addr = 10'b0;
  init_addr_1 = 10'd0;
  init_addr_2 = 10'd0;
  init_addr_3 = 10'd0;

  color_data = 9'd0;
  color_en = 1'b0;

  clear_line_start = 1'b0;

  line_counter_aclr = 1'b0;

  select_speed_down = 1'b0;

  drop_score_aclr = 1'b0;
  drop_score_cnt_en = 1'b0;

  score_data_en = 1'b0;
  score_data_aclr = 1'b0;

  clear_score_aclr = 1'b0;
  
  top_score_data_en = 1'b0;
  case(current_state)
    IDLE:begin
      line_counter_aclr = 1'b1;
      lvl_aclr = 1'b1;
      map_id = 3'd0;
      map_load_start = 1'b0;
      pt_load_start = 1'b0;
      pt_data = 2'b00;
      grid_input_sel = 6'd0;
    end

    LOAD_MAP1:begin
      lvl_aclr = 1'b0;
      map_load_start = 1'b1;
      map_id = 3'd1;
      grid_input_sel = 6'd1;
    end

    PRESS_START: begin
      map_load_start = 1'b0;
      map_id = 3'd0;
      grid_input_sel = 6'd0;
    end
    LOAD_MAP2: begin
      map_load_start = 1'b1;
      map_id = 3'd2;
      grid_input_sel = 6'd1;
    end
    LOAD_PT_A: begin
      pt_data_en = 1'b1;
      map_load_start = 1'b0;
      map_id = 3'd0;
      pt_data = 2'b01;
      pt_load_start = 1'b1;
      grid_input_sel = 6'd2;
    end
    SET_A: begin
      select_speed_down = 1'b1;
      pt_data_en = 1'b0;
      pt_data = 2'b00;
      lvl_en = 1'b0;
      lvl_updown = 1'b0;
      pt_load_start = 1'b0;
      grid_input_sel = 6'd0;
    end
    LOAD_PT_B: begin
      map_load_start = 1'b0;
      map_id = 3'd0;
      pt_data_en = 1'b1;
      pt_data = 2'b10;
      pt_load_start = 1'b1;
      grid_input_sel = 6'd2;
    end
    SET_B: begin
      select_speed_down = 1'b1;
      pt_data_en = 1'b0;
      pt_data = 2'b00;
      lvl_en = 1'b0;
      lvl_updown = 1'b0;
      pt_load_start = 1'b0;
      grid_input_sel = 6'd0;
    end
    LOAD_PT_C: begin
      map_load_start = 1'b0;
      map_id = 3'd0;
      pt_data_en = 1'b1;
      pt_data = 2'b11;
      pt_load_start = 1'b1;
      grid_input_sel = 6'd2;
    end
    SET_C: begin
      select_speed_down = 1'b1;
      pt_data_en = 1'b0;
      pt_data = 2'b00;
      lvl_en = 1'b0;
      lvl_updown = 1'b0;
      pt_load_start = 1'b0;
      grid_input_sel = 6'd0;
    end
    INC_SET_LV: begin
      if (lvl_data_reg<9) begin
        lvl_en = 1'b1;
        lvl_updown = 1'b1;
      end else begin
        lvl_en = 1'b0;
        lvl_updown = 1'b1;
      end
    end
    DEC_SET_LV:begin
      if (lvl_data_reg==0) begin
        lvl_en = 1'b0;
        lvl_updown = 1'b0;
      end else begin
        lvl_en = 1'b1;
        lvl_updown = 1'b0;
      end
    end
    LOAD_MAP3: begin
      //Reset score here
      drop_score_aclr = 1'b1;

      score_data_aclr = 1'b1;

      clear_score_aclr = 1'b1;

      map_load_start = 1'b1;
      map_id = 3'd4;
      grid_input_sel = 6'd1;
    end
    GEN_PIECE: begin

      drop_score_aclr = 1'b1;
      clear_score_aclr = 1'b1;

      aclr_timer = 1'b1;
      en_timer = 1'b0;
      en_gen = 1'b1;
    end
    ST_PIECE: begin

      drop_score_aclr = 1'b0;
      drop_score_cnt_en = 1'b0;
    
      score_data_en = 1'b0;
      score_data_aclr = 1'b0;

      aclr_timer = 1'b1;
      en_timer = 1'b1;
      en_gen = 1'b0;
      st_piece = 1'b1;
    end

    CHECK_LOSE_00: begin
      grid_input_sel = 6'd3;
      addr_3 = 10'd209;
      wr_3 = 1'b0;
      rd_3 = 1'b1 ;
      en_timer = 1'b1;
      en_gen = 1'b0;
    end

    CHECK_LOSE_01: begin
      grid_input_sel = 6'd3;
      addr_3 = 10'd210;
      wr_3 = 1'b0;
      rd_3 = 1'b1 ;
      en_timer = 1'b1;
    end

    CHECK_LOSE_02: begin
      grid_input_sel = 6'd3;
      addr_3 = 10'd211;
      wr_3 = 1'b0;
      rd_3 = 1'b1 ;
      en_timer = 1'b1;
    end

    CHECK_LOSE_03: begin
      grid_input_sel = 6'd3;
      addr_3 = 10'd212;
      wr_3 = 1'b0;
      rd_3 = 1'b1 ;
      en_timer = 1'b1;
    end

    CHECK_LOSE_04: begin
      grid_input_sel = 6'd3;
      addr_3 = 10'd212;
      wr_3 = 1'b0;
      rd_3 = 1'b1 ;
      en_timer = 1'b1;
    end
    
    LOAD_DATA: begin
      en_timer = 1'b1;
      load_data_start = 1'b1;
      grid_input_sel = 6'd4;
    end

    LOAD_ADDRESS: begin
      en_timer = 1'b1;
      st_addr = 1'b1;
      color_en = 1'b1;
      case(piece_id_data)
        3'd0: begin
          color_data = 9'd242 + color_offset;
          pivot_addr = 10'd177;
          init_addr_1 = 10'd176;
          init_addr_2 = 10'd178;
          init_addr_3 = 10'd209;
        end
        3'd1: begin 
          color_data = 9'd243 + color_offset;
          pivot_addr = 10'd177;
          init_addr_1 = 10'd176;
          init_addr_2 = 10'd178;
          init_addr_3 = 10'd210;
        end
        3'd2: begin 
          color_data = 9'd244 + color_offset;
          pivot_addr = 10'd177;
          init_addr_1 = 10'd176;
          init_addr_2 = 10'd209;
          init_addr_3 = 10'd210;
        end
        3'd3: begin 
          color_data = 9'd241 + color_offset;
          pivot_addr = 10'd177;
          init_addr_1 = 10'd178;
          init_addr_2 = 10'd209;
          init_addr_3 = 10'd210;
        end
        3'd4: begin 
          color_data = 9'd243 + color_offset;
          pivot_addr = 10'd177;
          init_addr_1 = 10'd178;
          init_addr_2 = 10'd208;
          init_addr_3 = 10'd209;
        end
        3'd5: begin 
          color_data = 9'd244 + color_offset;
          pivot_addr = 10'd177;
          init_addr_1 = 10'd176;
          init_addr_2 = 10'd178;
          init_addr_3 = 10'd208;
        end
        3'd6: begin 
          color_data = 9'd242 + color_offset;
          pivot_addr = 10'd177;
          init_addr_1 = 10'd176;
          init_addr_2 = 10'd178;
          init_addr_3 = 10'd179;
        end
        default:begin
          pivot_addr = 10'd0;
          init_addr_1 = 10'd0;
          init_addr_2 = 10'd0;
          init_addr_3 = 10'd0;
        end
      endcase

    end

    LOSE_SCREEN_0: begin
      map_load_start = 1'b1;
      map_id = 3'd3;
      grid_input_sel = 6'd1;
    end

    LOSE_SCREEN_1:begin
      grid_input_sel = 6'd1;
    end

    START_GAME:begin
      en_timer = 1'b1;
    end

    CHECK_LEFT_00:begin
      grid_input_sel = 6'd3; //For checking
      move_data = 3'd1;
      wr_3 = 1'b0;
      rd_3 = 1'b1;
      addr_3 = next_pivot_addr;
      en_timer = 1'b1;
    end

    CHECK_LEFT_01:begin
      grid_input_sel = 6'd3; //For checking
      move_data = 3'd1;
      wr_3 = 1'b0;
      rd_3 = 1'b1;
      addr_3 = next_addr_1;
      en_timer = 1'b1;
    end

    CHECK_LEFT_02:begin
      grid_input_sel = 6'd3; //For checking
      move_data = 3'd1;
      wr_3 = 1'b0;
      rd_3 = 1'b1;
      addr_3 = next_addr_2;
      en_timer = 1'b1;
    end

    CHECK_LEFT_03:begin
      grid_input_sel = 6'd3; //For checking
      move_data = 3'd1;
      move_data = 3'd1;
      wr_3 = 1'b0;
      rd_3 = 1'b1;
      addr_3 = next_addr_3;
      en_timer = 1'b1;
    end

    CHECK_LEFT_04:begin
      grid_input_sel = 6'd3; //For checking
      move_data = 3'd1;
      wr_3 = 1'b0;
      rd_3 = 1'b0;
      addr_3 = 10'b0;
      en_timer = 1'b1;
    end


    MOVE_LEFT:begin
      en_timer = 1'b1;
      move_data = 3'd1;
      move_start = 1'b1;
      grid_input_sel = 6'd5;
    end

    CHECK_RIGHT_00:begin
      grid_input_sel = 6'd3; //For checking
      move_data = 3'd2;
      wr_3 = 1'b0;
      rd_3 = 1'b1;
      addr_3 = next_pivot_addr;
      en_timer = 1'b1;
    end

    CHECK_RIGHT_01:begin
      grid_input_sel = 6'd3; //For checking
      move_data = 3'd2;
      wr_3 = 1'b0;
      rd_3 = 1'b1;
      addr_3 = next_addr_1;
      en_timer = 1'b1;
    end

    CHECK_RIGHT_02:begin
      grid_input_sel = 6'd3; //For checking
      move_data = 3'd2;
      wr_3 = 1'b0;
      rd_3 = 1'b1;
      addr_3 = next_addr_2;
      en_timer = 1'b1;
    end

    CHECK_RIGHT_03:begin
      grid_input_sel = 6'd3; //For checking
      wr_3 = 1'b0;
      move_data = 3'd2;
      rd_3 = 1'b1;
      addr_3 = next_addr_3;
      en_timer = 1'b1;
    end

    CHECK_RIGHT_04:begin
      grid_input_sel = 6'd3; //For checking
      move_data = 3'd2;
      wr_3 = 1'b0;
      rd_3 = 1'b0;
      addr_3 = 10'b0;
      en_timer = 1'b1;
    end

    MOVE_RIGHT:begin
      en_timer = 1'b1;
      move_data = 3'd2;
      move_start = 1'b1;
      grid_input_sel = 6'd5;
    end

    CHECK_ROTATE_CLOCKWISE_00:begin
      grid_input_sel = 6'd3; //For checking
      move_data = 3'd3;
      wr_3 = 1'b0;
      rd_3 = 1'b1;
      addr_3 = next_pivot_addr;
      en_timer = 1'b1;
    end

    CHECK_ROTATE_CLOCKWISE_01:begin
      grid_input_sel = 6'd3; //For checking
      move_data = 3'd3;
      wr_3 = 1'b0;
      rd_3 = 1'b1;
      addr_3 = next_addr_1;
      en_timer = 1'b1;
    end

    CHECK_ROTATE_CLOCKWISE_02:begin
      grid_input_sel = 6'd3; //For checking
      move_data = 3'd3;
      wr_3 = 1'b0;
      rd_3 = 1'b1;
      addr_3 = next_addr_2;
      en_timer = 1'b1;
    end

    CHECK_ROTATE_CLOCKWISE_03:begin
      grid_input_sel = 6'd3; //For checking
      wr_3 = 1'b0;
      move_data = 3'd3;
      rd_3 = 1'b1;
      addr_3 = next_addr_3;
      en_timer = 1'b1;
    end

    CHECK_ROTATE_CLOCKWISE_04:begin
      grid_input_sel = 6'd3; //For checking
      move_data = 3'd3;
      wr_3 = 1'b0;
      rd_3 = 1'b0;
      addr_3 = 10'b0;
      en_timer = 1'b1;
    end

    MOVE_ROTATE_CLOCKWISE:begin
      en_timer = 1'b1;
      move_data = 3'd3;
      move_start = 1'b1;
      grid_input_sel = 6'd5;
    end


    CHECK_ROTATE_COUNTER_CLOCKWISE_00:begin
      grid_input_sel = 6'd3; //For checking
      move_data = 3'd4;
      wr_3 = 1'b0;
      rd_3 = 1'b1;
      addr_3 = next_pivot_addr;
      en_timer = 1'b1;
    end

    CHECK_ROTATE_COUNTER_CLOCKWISE_01:begin
      grid_input_sel = 6'd3; //For checking
      move_data = 3'd4;
      wr_3 = 1'b0;
      rd_3 = 1'b1;
      addr_3 = next_addr_1;
      en_timer = 1'b1;
    end

    CHECK_ROTATE_COUNTER_CLOCKWISE_02:begin
      grid_input_sel = 6'd3; //For checking
      move_data = 3'd4;
      wr_3 = 1'b0;
      rd_3 = 1'b1;
      addr_3 = next_addr_2;
      en_timer = 1'b1;
    end

    CHECK_ROTATE_COUNTER_CLOCKWISE_03:begin
      grid_input_sel = 6'd3; //For checking
      wr_3 = 1'b0;
      move_data = 3'd4;
      rd_3 = 1'b1;
      addr_3 = next_addr_3;
      en_timer = 1'b1;
    end

    CHECK_ROTATE_COUNTER_CLOCKWISE_04:begin
      grid_input_sel = 6'd3; //For checking
      move_data = 3'd4;
      wr_3 = 1'b0;
      rd_3 = 1'b0;
      addr_3 = 10'b0;
      en_timer = 1'b1;
    end

    MOVE_ROTATE_COUNTER_CLOCKWISE:begin
      en_timer = 1'b1;
      move_data = 3'd4;
      move_start = 1'b1;
      grid_input_sel = 6'd5;
    end

    CHECK_DOWN_00:begin
      grid_input_sel = 6'd3; //For checking
      move_data = 3'd5;
      wr_3 = 1'b0;
      rd_3 = 1'b1;
      addr_3 = next_pivot_addr;
      en_timer = 1'b1;
    end

    CHECK_DOWN_01:begin
      grid_input_sel = 6'd3; //For checking
      move_data = 3'd5;
      wr_3 = 1'b0;
      rd_3 = 1'b1;
      addr_3 = next_addr_1;
      en_timer = 1'b1;
    end

    CHECK_DOWN_02:begin
      grid_input_sel = 6'd3; //For checking
      move_data = 3'd5;
      wr_3 = 1'b0;
      rd_3 = 1'b1;
      addr_3 = next_addr_2;
      en_timer = 1'b1;
    end

    CHECK_DOWN_03:begin
      grid_input_sel = 6'd3; //For checking
      move_data = 3'd5;
      wr_3 = 1'b0;
      rd_3 = 1'b1;
      addr_3 = next_addr_3;
      en_timer = 1'b1;
    end

    CHECK_DOWN_04:begin
      grid_input_sel = 6'd3; //For checking
      move_data = 3'd5;
      wr_3 = 1'b0;
      rd_3 = 1'b0;
      addr_3 = 10'b0;
      en_timer = 1'b1;
    end

    MOVE_DOWN:begin
      en_timer = 1'b1;
      move_data = 3'd5;
      move_start = 1'b1;
      grid_input_sel = 6'd5;
    end


    CLEAR_CLOCK:begin

      drop_score_cnt_en = 1'b1;

      aclr_timer =  1'b1;
    end

    CHECK_TIME:begin
      en_timer = 1'b1;
      move_data = 3'd0;
      move_start = 1'b0;
      grid_input_sel = 6'd0;
    end

    CLEAR_LINE: begin
      en_timer = 1'b1;
      grid_input_sel = 6'd6;
      clear_line_start = 1'b1;
    end

    CAL_SCORE: begin
      score_data_en = 1'b1; 
    end
    CHECK_TOP_SCORE:begin
      //Do nothing
    end
    UPDATE_TOP_SCORE:begin
      top_score_data_en = 1'b1;
    end
    DO_NOT: begin
      load_data_start = 1'b0;
      grid_input_sel = 6'd0;
    end
  endcase
end
assign cstate = current_state;
endmodule
