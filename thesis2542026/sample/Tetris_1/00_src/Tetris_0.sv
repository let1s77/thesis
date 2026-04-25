module Tetris_0 
(
  //System
//In
  input logic  CLOCK_50,
  input logic  KEY3,KEY2,
  input logic [17:0] SW,
  //Keyboard
//In
  input  logic PS2_CLK,
  input  logic PS2_DAT,
  //VGA
//Out
  output logic VGA_HS,
  output logic VGA_VS,
  output logic VGA_SYNC_N,
  output logic VGA_CLK,
  output logic VGA_BLANK_N,
  output logic [7:0] VGA_R,
  output logic [7:0] VGA_G,
  output logic [7:0] VGA_B,
  //Sound
//Out
  // Audio codec pins (DE2-115)
  output logic AUD_XCK,       // 12.288 MHz master clock to WM8731
  output logic AUD_BCLK,      // ~3.072 MHz bit clock
  output logic AUD_DACLRCK,   // 48 kHz LR clock
  output logic AUD_DACDAT,    // I2S data out (to DAC)
  //Sound I2C control to WM8731
//Out
  output logic I2C_SCLK,
//InOut
  inout  wire I2C_SDAT,



  output [6:0] byte_h_digit_h,
  output [6:0] byte_h_digit_l,
  output [6:0] byte_l_digit_h,
  output [6:0] byte_l_digit_l
  
  // input logic KEY0,
  // input logic check_enter,check_left,check_right,check_down, check_x,check_up,check_z,
  // output logic [6:0] cstatec,
  // output logic [7:0] c_statec,


  // output [6:0] LEDR,
  // output led
);


//Control PS/2
logic [15:0] keyboard_data;


//Control_input
logic press_left;
logic press_right;
logic press_up;
logic press_down;
logic press_enter;
logic press_x;
logic press_z;
logic press_space;


//Generator
logic [2:0] piece_id_next, piece_id_data;


//Game FSM
logic [5:0] grid_input_sel;

logic [2:0] map_id;
logic       map_load_start;

logic         pt_load_start;

logic [1:0]   pt_data;
logic         pt_data_en;
logic [1:0]   pt_data_reg;


logic         lvl_aclr;
logic         lvl_en;
logic         lvl_updown;

logic en_gen;

logic st_piece;

logic [9:0] addr_3;
logic [8:0] piece_id_wr_3;

logic [8:0] wr_3;
logic [8:0] rd_3;

logic load_data_done,load_data_start;

logic st_addr;

logic [9:0] pivot_addr;
logic [9:0] init_addr_1;
logic [9:0] init_addr_2;
logic [9:0] init_addr_3;

logic [9:0] pivot_addr_reg;
logic [9:0] cur_addr_1_reg,cur_addr_2_reg,cur_addr_3_reg;

logic [8:0] color_data;
logic       color_en;
logic [8:0] color_data_reg;

logic       move_start;
logic [2:0] move_data;

logic      move_done;

logic      en_timer,aclr_timer;

logic [25:0] time_count;

//Map Controller
logic map_load_done;

logic [8:0] piece_id_wr_1;
logic [9:0] addr_1;

logic wr_1;
logic rd_1;

assign wr_1 = 1'b1;
assign rd_1 = 1'b0;


//Pointer
logic [9:0] addr_2;
logic [8:0] piece_id_wr_2;

logic wr_2;
logic rd_2;

assign wr_2 = 1'b1;
assign rd_2 = 1'b0;

logic [7:0]   lvl_data_reg;

logic         pt_load_done;


logic [3:0] rd_data_blue;
logic [3:0] rd_data_red;
logic [3:0] rd_data_green;

//Load data
logic [9:0] addr_4;
logic [8:0] wr_4;

logic [8:0] rd_4;
logic [8:0] piece_id_wr_4;

//Load move
logic [9:0] addr_5;
logic [8:0] piece_id_wr_5;

logic [8:0] rd_5;
logic [8:0] wr_5;

assign wr_5 = 1'b1;
assign rd_5 = 1'b0;

logic       en_update;
logic [9:0] update_pivot_addr;
logic [9:0] update_addr_1,update_addr_2,update_addr_3;


//Boundary counter
logic boundary_counter_aclr;
logic boundary_counter_en;
logic [4:0] boundary_counter_count;

//Cal next addr
logic [9:0] next_pivot_addr;
logic [9:0] next_addr_1,next_addr_2,next_addr_3;

//Clear line
logic [8:0] piece_id_wr_6;
logic [9:0] addr_6;

logic wr_6;
logic rd_6;

//Clear FSM
  logic clear_line_start;

  logic clear_line_done;

//Line  counter

logic line_counter_aclr;
logic line_counter_cnt;
logic [9:0] line_counter_data;

//current level

logic [7:0] current_lvl;
////// Score

logic [4:0] drop_score_out;
logic drop_score_aclr;
logic drop_score_cnt_en;

logic [2:0] clear_score_out;
logic clear_score_aclr;
logic clear_score_cnt_en;

logic [19:0] next_score;
logic [19:0] score_data_reg;
logic score_data_en;
logic score_data_aclr;

logic [17:0] clear_score_cal;













////////////////////////////////////////////////////////////












////VGA
logic [8:0] piece_id_wr;
logic [9:0] addr;
logic rd;
logic wr;



logic [8:0] piece_id_rd;
logic [8:0] piece_id_rd_checking;


logic [3:0] wr_data_blue;
logic [3:0] wr_data_red;
logic [3:0] wr_data_green;


logic [9:0] H_Count_Value;
logic [9:0] V_Count_Value;

//////Sound
logic AUD_DACDAT_temp_line;
///Top score

logic [19:0] top_score_data_reg;
logic top_score_data_en;

///////////////////////////////////////////
control_ps2 control_ps2_u(
  .clk(CLOCK_50),
  .rst_n(KEY3),

  .ps2_clk(PS2_CLK),
  .ps2_data(PS2_DAT),

  .byte_h_digit_h(byte_h_digit_h),
  .byte_h_digit_l(byte_h_digit_l),
  .byte_l_digit_l(byte_l_digit_l),
  .byte_l_digit_h(byte_l_digit_h),

  .data(keyboard_data)
);

control_input control_input_u(
  .clk(CLOCK_50),
  .rst_n(KEY3),

  .data(keyboard_data),

  .press_left(press_left),
  .press_right(press_right),
  .press_up(press_up),
  .press_down(press_down),
  .press_enter(press_enter),
  .press_x(press_x),
  .press_z(press_z),

  .select_speed_down(select_speed_down),
);
////////////////////////////////////////////////////// Generate piece
piece_generator NES_random_lfsr (
  .clk(CLOCK_50),
  .rst_n(KEY3),
  .en_gen(en_gen),
  .ld_seed(~KEY2),
  .seed(SW[17:2]),
  .piece_id(piece_id_next)
);

d_ff_with_en #(.N(3)) piece_data_u (
  .d(piece_id_next),
  .clk(CLOCK_50),
  .en(st_piece),
  .rst_n(KEY3),
  .q(piece_id_data)
);

logic [6:0] c_state;

//////////////////////////////////////////////////////Game FSM
game_fsm game_fsm_u (
  .clk(CLOCK_50),
  .rst_n(KEY3),
  //Keyboard
//In
  .press_left(press_left),
  .press_right(press_right),
  .press_down(press_down),
  .press_enter(press_enter),
  .press_x(press_x),
  .press_up(press_up),
  .press_z(press_z),
  .select_speed_down(select_speed_down),

  //.press_up(check_up),
  //.press_z(check_z),
  //.press_enter(check_enter),
  //.press_down(check_down),
  //.press_right(check_right),
  //.press_left(check_left),
  //.press_x(check_x),



  //Grid
//Out
  .grid_input_sel(grid_input_sel),
  //Map load
//In
  .map_load_done(map_load_done),
//Out
  .map_id(map_id),
  .map_load_start(map_load_start),

  //Pointer load
//In
  .pt_load_done(pt_load_done),
//Out
  .pt_load_start(pt_load_start),
//In
  .pt_data_reg(pt_data_reg),
//Out
  .pt_data(pt_data),
  .pt_data_en(pt_data_en),

//Out
  .lvl_aclr(lvl_aclr),
  .lvl_en(lvl_en),
  .lvl_updown(lvl_updown),
//In
  .lvl_data_reg(lvl_data_reg),
  .current_lvl(current_lvl),
//New piece + store that piece
  .st_piece(st_piece),
  .en_gen(en_gen),
//Check lose
  .addr_3(addr_3),
  .wr_3(wr_3),
  .rd_3(rd_3),

  .lose_condition(piece_id_rd_checking!=9'd18),
//Load data  
  .load_data_start(load_data_start),
  .load_data_done(load_data_done),
//Store Address
  .st_addr(st_addr),
  .pivot_addr(pivot_addr),
  .init_addr_1(init_addr_1),
  .init_addr_2(init_addr_2),
  .init_addr_3(init_addr_3),
  
  //Current address
  .pivot_addr_reg(pivot_addr_reg),
  .cur_addr_1_reg(cur_addr_1_reg),
  .cur_addr_2_reg(cur_addr_2_reg),
  .cur_addr_3_reg(cur_addr_3_reg),
 //Check
  .check_left_fail(piece_id_rd_checking != 9'd18),
  .check_right_fail(piece_id_rd_checking != 9'd18),
  .check_down_fail(piece_id_rd_checking != 9'd18),
  .check_clockwise_fail(piece_id_rd_checking != 9'd18),
  .check_counter_clockwise_fail(piece_id_rd_checking != 9'd18),
  
  //Color
  .color_data(color_data),
  .color_en(color_en),

  //Move
  .move_start(move_start),
  .move_data(move_data),
  .move_done(move_done),
  //Cal next address
  .next_pivot_addr(next_pivot_addr),
  .next_addr_1(next_addr_1),
  .next_addr_2(next_addr_2),
  .next_addr_3(next_addr_3),

  .time_equal(time_count>(50_000_000/(current_lvl+1'b1))),
  .piece_id_data(piece_id_data),

  .en_timer(en_timer),
  .aclr_timer(aclr_timer),

  .clear_line_start(clear_line_start),
  .clear_line_done(clear_line_done),

  //Line counter
//Out
  .line_counter_aclr(line_counter_aclr),

  //Score
//Out
  .score_data_en(score_data_en),
  .drop_score_aclr(drop_score_aclr),
  .drop_score_cnt_en(drop_score_cnt_en),
  .score_data_aclr(score_data_aclr),

  .clear_score_aclr(clear_score_aclr),

  .top_score_data_en(top_score_data_en),
  .update_score(score_data_reg>top_score_data_reg),

  .cstate(cstatec)
);
//////////////////////////////////////////////////////Map_controller
map_controller map_controller_u(
  .rst_n(KEY3),
  .clk(CLOCK_50),
//In
  .map_id(map_id),
  .map_load_start(map_load_start),
//Out
  .map_load_done(map_load_done),
  .addr_1(addr_1),
  .piece_id_wr_1(piece_id_wr_1)
);

//////////////////////////////////////////////////////current lv calculating 

assign current_lvl = lvl_data_reg + line_counter_data/10;
/////////////////////////////////////////////////////// Pointer and Lv select
map_pointer_fsm map_pointer_fsm_u(
  .clk(CLOCK_50),
  .rst_n(KEY3),
//In
  .pt_load_start(pt_load_start),

  .pt_data(pt_data),


  .lvl_data_reg(lvl_data_reg),
//Out
  .addr_2(addr_2),
  .pt_load_done(pt_load_done),
  .piece_id_wr_2(piece_id_wr_2)
);

lvl_counter lvl_counter(
  .aclr(lvl_aclr),
  .clock(CLOCK_50),
  .cnt_en(lvl_en),
  .updown(lvl_updown),
  .q(lvl_data_reg)
);

d_ff_with_en #(.N(2)) pt_data_u (
  .d(pt_data),
  .clk(CLOCK_50),
  .en(pt_data_en),
  .rst_n(KEY3),
  .q(pt_data_reg)
);

////////////////////////////////////////////////////////////Load data
load_data load_data_u(
  .clk(CLOCK_50),
  .rst_n(KEY3),
  .load_data_done(load_data_done),
  .load_data_start(load_data_start),

  .piece_id_data(piece_id_data),
  .piece_id_next(piece_id_next),
  .lvl_data_reg(current_lvl),
  .score_data_reg(score_data_reg),
  .top_score_data_reg(top_score_data_reg),
  .line_data_reg(line_counter_data),
  
  .wr_4(wr_4),
  .rd_4(rd_4),
  .addr_4(addr_4),
  .piece_id_wr_4(piece_id_wr_4)
);
/////////////////////////////////////////////////////Current Position
d_ff_with_en #(.N(10)) pivot_point (
  .d(en_update ? update_pivot_addr : pivot_addr),
  .clk(CLOCK_50),
  .en(st_addr||en_update),
  .rst_n(KEY3),
  .q(pivot_addr_reg)
);

d_ff_with_en #(.N(10)) other_point_1 (
  .d(en_update ? update_addr_1 : init_addr_1),
  .clk(CLOCK_50),
  .en(st_addr||en_update),
  .rst_n(KEY3),
  .q(cur_addr_1_reg)
);

d_ff_with_en #(.N(10)) other_point_2 (
  .d(en_update ? update_addr_2 : init_addr_2),
  .clk(CLOCK_50),
  .en(st_addr||en_update),
  .rst_n(KEY3),
  .q(cur_addr_2_reg)
);

d_ff_with_en #(.N(10)) other_point_3 (
  .d(en_update ? update_addr_3 : init_addr_3),
  .clk(CLOCK_50),
  .en(st_addr||en_update),
  .rst_n(KEY3),
  .q(cur_addr_3_reg)
);
///////////////////////////////////////////////////// Color Storage
d_ff_with_en #(.N(9)) color_storage (
  .d(color_data),
  .clk(CLOCK_50),
  .en(color_en),
  .rst_n(KEY3),
  .q(color_data_reg)
);


//////////////////////////////////////////////////////////////////////////////////////////////////////////// Clear Line Logic 
  logic clear_counter_aclr;
  logic clear_counter_cnt;
  logic [9:0] clear_counter_data;
  logic clear_counter_aload;
  logic clear_counter_updown;

  logic [9:0] clear_count;

  logic en_ff;

  logic [9:0] clear_count_reg;

  logic [9:0] pivot_addr_reg_reg;
  logic [9:0] cur_addr_3_reg_reg,cur_addr_2_reg_reg,cur_addr_1_reg_reg;
  logic st_addr_clear;

//Shift address calculate

  logic [9:0] next_clear_count;


//Sorting
  logic [9:0] biggest;
  logic [9:0] second;
  logic [9:0] third;
  logic [9:0] smallest;

  logic [9:0] aa, bb, cc, dd;
  logic [9:0] max_ab, min_ab, max_cd, min_cd;

// Checking 
  logic check_biggest,check_third,check_second,check_smallest;

  always_comb begin
    // Start with inputs
    aa = cur_addr_1_reg_reg;
    bb = cur_addr_2_reg_reg;
    cc = cur_addr_3_reg_reg;
    dd = pivot_addr_reg_reg;

    // Remove duplicates (keep first, zero later)
    if (aa/32 == bb/32) bb = 0;
    if (aa/32 == cc/32) cc = 0;
    if (aa/32 == dd/32) dd = 0;

    if (bb/32 == cc/32) cc = 0;
    if (bb/32 == dd/32) dd = 0;

    if (cc/32 == dd/32) dd = 0;
  end

  // Comparator tree
  assign max_ab = (aa > bb) ? aa : bb;
  assign min_ab = (aa > bb) ? bb : aa;

  assign max_cd = (cc > dd) ? cc : dd;
  assign min_cd = (cc > dd) ? dd : cc;

  assign biggest  = (max_ab > max_cd) ? max_ab : max_cd;
  assign smallest = (min_ab < min_cd) ? min_ab : min_cd;
  assign second   = (max_ab > max_cd) ? max_cd : max_ab;
  assign third    = (min_ab < min_cd) ? min_cd : min_ab;


  assign check_biggest = biggest == 0;
  assign check_smallest = smallest == 0;
  assign check_second = second == 0;
  assign check_third  = third == 0;
/////////////////////

clear_line clear_line_u(
  .clk(CLOCK_50),
  .rst_n(KEY3),
  .clear_line_start(clear_line_start),

  .clear_line_done(clear_line_done),

  .blank(piece_id_rd_checking == 6'd18),

  .piece_id_rd_checking(piece_id_rd_checking),
  .clear_counter_aclr(clear_counter_aclr),
  .clear_counter_cnt(clear_counter_cnt),
  .clear_counter_data(clear_counter_data),
  .clear_counter_aload(clear_counter_aload),
  .clear_counter_updown(clear_counter_updown),

  .clear_count(clear_count),

  .piece_id_wr_6(piece_id_wr_6),
  .addr_6(addr_6),

  .wr_6(wr_6),
  .rd_6(rd_6),
  .c_state(c_statec),

  .check_smallest(check_smallest),
  .check_biggest(check_biggest),
  .check_second(check_second),
  .check_third(check_third),
  .st_addr_clear(st_addr_clear),

  .reach_row((clear_count%32)==23),

  .read_small((smallest/32)*32 + 13),
  .read_big((biggest/32)*32 + 13),
  .read_third((third/32)*32 + 13),
  .read_second((second/32)*32 + 13),

  .next_clear_count(clear_count + 7'd32),
  .finish_clear(clear_count==10'd215),
  .clear_count_reg(clear_count_reg),
  .en_ff(en_ff),
  .line_counter_cnt(line_counter_cnt),

  .clear_score_cnt_en(clear_score_cnt_en)
);


clear_counter clear_counter_u(
  .aclr(clear_counter_aclr||~KEY3),
  .sload(clear_counter_aload),
  .cnt_en(clear_counter_cnt),
  .clock(CLOCK_50),
  .data(clear_counter_data),
  .q(clear_count)
);

d_ff_with_en #(.N(10)) support_clean (
  .d(clear_count),
  .clk(CLOCK_50),
  .en(en_ff),
  .rst_n(KEY3),
  .q(clear_count_reg)
);

///////////

d_ff_with_en #(.N(10)) addr_str_0 (
  .d(pivot_addr_reg),
  .clk(CLOCK_50),
  .en(st_addr_clear),
  .rst_n(KEY3),
  .q(pivot_addr_reg_reg)
);


d_ff_with_en #(.N(10)) addr_str_1 (
  .d(cur_addr_1_reg),
  .clk(CLOCK_50),
  .en(st_addr_clear),
  .rst_n(KEY3),
  .q(cur_addr_1_reg_reg)
);


d_ff_with_en #(.N(10)) addr_str_2 (
  .d(cur_addr_2_reg),
  .clk(CLOCK_50),
  .en(st_addr_clear),
  .rst_n(KEY3),
  .q(cur_addr_2_reg_reg)
);

d_ff_with_en #(.N(10)) addr_str_3 (
  .d(cur_addr_3_reg),
  .clk(CLOCK_50),
  .en(st_addr_clear),
  .rst_n(KEY3),
  .q(cur_addr_3_reg_reg)
);

//////////////////////////////////////////////////////////////////////////////////////////////////////////// Load Move
load_move load_move_u(
  .clk(CLOCK_50),
  .rst_n(KEY3),

  .move_start(move_start),
  .move_done(move_done),
  
  .color_data_reg(color_data_reg),

  .pivot_addr_reg(pivot_addr_reg),
  .cur_addr_1_reg(cur_addr_1_reg),
  .cur_addr_2_reg(cur_addr_2_reg),
  .cur_addr_3_reg(cur_addr_3_reg),
  
  .next_pivot_addr(next_pivot_addr),
  .next_addr_1(next_addr_1),
  .next_addr_2(next_addr_2),
  .next_addr_3(next_addr_3),

  .addr_5(addr_5),
  .piece_id_wr_5(piece_id_wr_5),

  .en_update(en_update),
  .update_pivot_addr(update_pivot_addr),
  .update_addr_1(update_addr_1),
  .update_addr_2(update_addr_2),
  .update_addr_3(update_addr_3)

);
////////////////////////////////////////////////////////////Line counter

line_counter line_counter_u (
  .aclr(line_counter_aclr),
  .clock(CLOCK_50),
  .cnt_en(line_counter_cnt),
  .updown(1'b1),
  .q(line_counter_data)
);

////////////////////////////////////////////////////////////Calculate next address
cal_next_addr cal_next_addr_u(
  .pivot_addr_reg(pivot_addr_reg),
  .cur_addr_1_reg(cur_addr_1_reg),
  .cur_addr_2_reg(cur_addr_2_reg),
  .cur_addr_3_reg(cur_addr_3_reg),
  .move_data(move_data),

  .is_square(piece_id_data==3'd3),
  .next_pivot_addr(next_pivot_addr),
  .next_addr_1(next_addr_1),
  .next_addr_2(next_addr_2),
  .next_addr_3(next_addr_3)
);

//////////////////////////////////////////////////////////Timer counter
timer timer_u(
  .aclr(aclr_timer),
  .clock(CLOCK_50),
  .cnt_en(en_timer),
  .q(time_count)
);

////////////////////////////////////////////////////////  Score

d_ff_with_en #(.N(20)) score_reg_u (
  .d(next_score),
  .clk(CLOCK_50),
  .en(score_data_en),
  .rst_n(KEY3 && ~score_data_aclr),
  .q(score_data_reg)
);

drop_counter drop_counter_u(
  .aclr(drop_score_aclr),
  .clock(CLOCK_50),
  .cnt_en(drop_score_cnt_en),
  .q(drop_score_out)
);

clear_score_cnt clear_score_cnt_u(
  .aclr(clear_score_aclr),
  .clock(CLOCK_50),
  .cnt_en(clear_score_cnt_en),
  .q(clear_score_out)
);

clear_score_logic clear_score_logic_u(
  .clear_score_out(clear_score_out),
  .current_lvl(current_lvl),

  .clear_score_cal(clear_score_cal)
);

assign next_score = score_data_reg + drop_score_out + clear_score_cal;
/////////////////////////////////////////////////////////VGA
grid_select grid_select_u(
//In
  .grid_input_sel(grid_input_sel),

  .addr_1(addr_1),
  .addr_2(addr_2),
  .addr_3(addr_3),
  .addr_4(addr_4),
  .addr_5(addr_5),
  .addr_6(addr_6),

  .rd_1(rd_1),
  .rd_2(rd_2),
  .rd_3(rd_3),
  .rd_4(rd_4),
  .rd_5(rd_5),
  .rd_6(rd_6),

  .wr_1(wr_1),
  .wr_2(wr_2),
  .wr_3(wr_3),
  .wr_4(wr_4),
  .wr_5(wr_5),
  .wr_6(wr_6),

  .piece_id_wr_1(piece_id_wr_1),
  .piece_id_wr_2(piece_id_wr_2),
  .piece_id_wr_3(piece_id_wr_3),
  .piece_id_wr_4(piece_id_wr_4),
  .piece_id_wr_5(piece_id_wr_5),
  .piece_id_wr_6(piece_id_wr_6),
//Out
  .piece_id_wr(piece_id_wr),
  .addr(addr),
  .wr(wr),
  .rd(rd)
);

game_grid game_grid_u(
  //Sytem
  .clk(CLOCK_50),
  .rst_n(KEY3),

  //Port A
//In
  .H_Count_Value(H_Count_Value),
  .V_Count_Value(V_Count_Value),
//Out
  .q_a(piece_id_rd),

  //Port B
//In
  .data_b(piece_id_wr),
  .addr_b(addr),
  .rd(rd),
  .wr(wr),
//Out
  .q_b(piece_id_rd_checking)
);

piece_decoder piece_decoder_u(
  //System
  .clk(CLOCK_50),

  .H_Count_Value(H_Count_Value),
  .V_Count_Value(V_Count_Value),

  .piece_id(piece_id_rd),

  .red(wr_data_red),
  .green(wr_data_green),
  .blue(wr_data_blue)

);

vga_line_buffer vga_line_buffer_u(
  .clk(CLOCK_50),
  .rst_n(KEY3),
   
  .current_H_Count_Value(H_Count_Value),
  .current_V_Count_Value(V_Count_Value),
  
  .wr_data_red(wr_data_red),
  .wr_data_green(wr_data_green),
  .wr_data_blue(wr_data_blue),

  .rd_data_red(rd_data_red),
  .rd_data_green(rd_data_green),
  .rd_data_blue(rd_data_blue)
);

vga_controller vga_controller_u(
  .clk(CLOCK_50),
  .rst_n(KEY3),
  
  .pixel_red({rd_data_red,rd_data_red}),
  .pixel_blue({rd_data_blue,rd_data_blue}),
  .pixel_green({rd_data_green,rd_data_green}),

  .hsync(VGA_HS), 
  .vsync(VGA_VS), 
  .blank_n(VGA_BLANK_N),
  .sync_n(VGA_SYNC_N),
  .red(VGA_R), 
  .green(VGA_G),
  .blue(VGA_B),
  .vga_clk(VGA_CLK),
  
  .H_Count_Value(H_Count_Value),
  .V_Count_Value(V_Count_Value)
);


/////////////////////////////////////////////////////////////Sound/////////////////////////////////////////////////////

music_top music_top_u(
  .clk(CLOCK_50),
  .reset(KEY3),
  .SDIN(I2C_SDAT),
  .SCLK(I2C_SCLK),
  .AUD_XCK(AUD_XCK),
  .BCLK(AUD_BCLK),
  .DAC_LR_CLK(AUD_DACLRCK),
  .DAC_DATA(AUD_DACDAT_temp_line)
);

assign AUD_DACDAT = SW[0] ? AUD_DACDAT_temp_line : 1'b0;

//////////////////////////////////////////////////////////Top score/////
d_ff_with_en #(.N(20)) top_score_data_reg_u (
  .d(score_data_reg),
  .clk(CLOCK_50),
  .en(top_score_data_en),
  .rst_n(KEY3),
  .q(top_score_data_reg)
);


//Sub module
endmodule
