module clear_line (
  input logic clk,
  input logic rst_n,
  input logic clear_line_start,

  output logic clear_line_done,
  
  input logic blank,

  output logic [8:0] piece_id_wr_6,
  output logic [9:0] addr_6,

  output logic wr_6,
  output logic rd_6,

  output logic [6:0] c_state,

  input logic [8:0] piece_id_rd_checking,

  output logic en_ff,

  input logic [9:0] clear_count,
  output logic clear_counter_aclr,
  output logic clear_counter_cnt,
  output logic [9:0] clear_counter_data,
  output logic clear_counter_aload,
  output logic clear_counter_updown,

  input logic check_smallest,check_biggest,check_second,check_third,

  output logic st_addr_clear,

  input logic reach_row,

  input logic [9:0] read_small,read_big,read_third,read_second,
  input logic finish_clear,
  input logic [9:0] next_clear_count,
  input logic [9:0] clear_count_reg,

  output logic line_counter_cnt,

  output logic clear_score_cnt_en
  
);


//FSM
  typedef enum logic [6:0] {
  IDLE                 = 7'd0,
  WAIT_FOR_START       = 7'd1,
  CHECK_LINE_00        = 7'd2,
  CHECK_LINE_01        = 7'd3,
  CHECK_LINE_02        = 7'd4,
  CHECK_LINE_03        = 7'd5,
  CHECK_LINE_04        = 7'd6,
  // CHECK_LINE_05        = 7'd7,
  // CHECK_LINE_06        = 7'd8,
  // CHECK_LINE_07        = 7'd9,
  // CHECK_LINE_08        = 7'd10,
  // CHECK_LINE_09        = 7'd11,
  // CHECK_LINE_0A        = 7'd12,
  // CHECK_LINE_0B        = 7'd13,

  CLEAR_LINE_00        = 7'd7,
  CLEAR_LINE_01        = 7'd9,
  CLEAR_LINE_02        = 7'd10,
  CLEAR_LINE_03        = 7'd11,
  CLEAR_LINE_04        = 7'd12,
  CLEAR_LINE_05        = 7'd13,

  CHECK_LINE_10        = 7'd14,
  CHECK_LINE_11        = 7'd15,
  CHECK_LINE_12        = 7'd16,
  CHECK_LINE_13        = 7'd17,
  CHECK_LINE_14        = 7'd18,
  // CHECK_LINE_15        = 7'd25,
  // CHECK_LINE_16        = 7'd26,
  // CHECK_LINE_17        = 7'd27,
  // CHECK_LINE_18        = 7'd28,
  // CHECK_LINE_19        = 7'd29,
  // CHECK_LINE_1A        = 7'd30,
  // CHECK_LINE_1B        = 7'd31,

  CLEAR_LINE_10        = 7'd19,
  CLEAR_LINE_11        = 7'd20,
  CLEAR_LINE_12        = 7'd21,
  CLEAR_LINE_13        = 7'd22,
  CLEAR_LINE_14        = 7'd23,
  CLEAR_LINE_15        = 7'd24,

  CHECK_LINE_20        = 7'd25,
  CHECK_LINE_21        = 7'd26,
  CHECK_LINE_22        = 7'd27,
  CHECK_LINE_23        = 7'd28,
  CHECK_LINE_24        = 7'd29,
  // CHECK_LINE_25        = 7'd43,
  // CHECK_LINE_26        = 7'd44,
  // CHECK_LINE_27        = 7'd45,
  // CHECK_LINE_28        = 7'd46,
  // CHECK_LINE_29        = 7'd47,
  // CHECK_LINE_2A        = 7'd48,
  // CHECK_LINE_2B        = 7'd49,

  CLEAR_LINE_20        = 7'd30,
  CLEAR_LINE_21        = 7'd31,
  CLEAR_LINE_22        = 7'd32,
  CLEAR_LINE_23        = 7'd33,
  CLEAR_LINE_24        = 7'd34,
  CLEAR_LINE_25        = 7'd35,


  CHECK_LINE_30        = 7'd36,
  CHECK_LINE_31        = 7'd37,
  CHECK_LINE_32        = 7'd38,
  CHECK_LINE_33        = 7'd39,
  CHECK_LINE_34        = 7'd40,
  // CHECK_LINE_35        = 7'd61,
  // CHECK_LINE_36        = 7'd62,
  // CHECK_LINE_37        = 7'd63,
  // CHECK_LINE_38        = 7'd64,
  // CHECK_LINE_39        = 7'd65,
  // CHECK_LINE_3A        = 7'd66,
  // CHECK_LINE_3B        = 7'd67,

  CLEAR_LINE_30        = 7'd41,
  CLEAR_LINE_31        = 7'd42,
  CLEAR_LINE_32        = 7'd43,
  CLEAR_LINE_33        = 7'd44,
  CLEAR_LINE_34        = 7'd45,
  CLEAR_LINE_35        = 7'd46,

  DONE                 = 7'd47,
  CLEAR_LINE_36        = 7'd48,
  CLEAR_LINE_16        = 7'd79,
  CLEAR_LINE_06        = 7'd50,
  CLEAR_LINE_26        = 7'd51,
  CLEAR_LINE_37        = 7'd52
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
      next_state = clear_line_start ? CHECK_LINE_00 : WAIT_FOR_START;
    end

//Smallest
    CHECK_LINE_00:begin
      next_state = check_smallest ? CHECK_LINE_10 : CHECK_LINE_01;
    end
    CHECK_LINE_01:begin
      next_state = CHECK_LINE_02;
    end

    CHECK_LINE_02:begin
      next_state = blank ? CHECK_LINE_10 : CHECK_LINE_03;
    end

    CHECK_LINE_03: begin
      next_state = CHECK_LINE_04;
    end

    CHECK_LINE_04:begin
      next_state = reach_row ? CLEAR_LINE_00 : CHECK_LINE_01;
    end


    CLEAR_LINE_00:begin
      next_state = CLEAR_LINE_01;
    end

    CLEAR_LINE_01:begin
      next_state = CLEAR_LINE_02;
    end

    CLEAR_LINE_02:begin
      next_state = CLEAR_LINE_03;
    end

    CLEAR_LINE_03:begin
      next_state = CLEAR_LINE_06;
    end

    CLEAR_LINE_04: begin
      next_state = reach_row ? CLEAR_LINE_05 : CLEAR_LINE_01;
    end

    CLEAR_LINE_06: begin
      next_state = finish_clear ? CHECK_LINE_10 : CLEAR_LINE_04;
    end

    CLEAR_LINE_05: begin
      next_state =  CLEAR_LINE_01;
    end

//third
    CHECK_LINE_10:begin
      next_state = check_third ? CHECK_LINE_20 : CHECK_LINE_11;
    end
    CHECK_LINE_11:begin
      next_state = CHECK_LINE_12;
    end

    CHECK_LINE_12:begin
      next_state = blank ? CHECK_LINE_20 : CHECK_LINE_13;
    end

    CHECK_LINE_13: begin
      next_state = CHECK_LINE_14;
    end

    CHECK_LINE_14:begin
      next_state = reach_row ? CLEAR_LINE_10 : CHECK_LINE_11;
    end


    CLEAR_LINE_10:begin
      next_state = CLEAR_LINE_11;
    end

    CLEAR_LINE_11:begin
      next_state = CLEAR_LINE_12;
    end

    CLEAR_LINE_12:begin
      next_state = CLEAR_LINE_13;
    end

    CLEAR_LINE_13:begin
      next_state = CLEAR_LINE_16;
    end

    CLEAR_LINE_14: begin
      next_state = reach_row ? CLEAR_LINE_15 : CLEAR_LINE_11;
    end

    CLEAR_LINE_16: begin
      next_state = finish_clear ? CHECK_LINE_20 : CLEAR_LINE_14;
    end

    CLEAR_LINE_15: begin
      next_state =  CLEAR_LINE_11;
    end



//second
    CHECK_LINE_20:begin
      next_state = check_second ? CHECK_LINE_30 : CHECK_LINE_21;
    end
    CHECK_LINE_21:begin
      next_state = CHECK_LINE_22;
    end

    CHECK_LINE_22:begin
      next_state = blank ? CHECK_LINE_30 : CHECK_LINE_23;
    end

    CHECK_LINE_23: begin
      next_state = CHECK_LINE_24;
    end

    CHECK_LINE_24:begin
      next_state = reach_row ? CLEAR_LINE_20 : CHECK_LINE_21;
    end


    CLEAR_LINE_20:begin
      next_state = CLEAR_LINE_21;
    end

    CLEAR_LINE_21:begin
      next_state = CLEAR_LINE_22;
    end

    CLEAR_LINE_22:begin
      next_state = CLEAR_LINE_23;
    end

    CLEAR_LINE_23:begin
      next_state = CLEAR_LINE_26;
    end

    CLEAR_LINE_24: begin
      next_state = reach_row ? CLEAR_LINE_25 : CLEAR_LINE_21;
    end

    CLEAR_LINE_26: begin
      next_state = finish_clear ? CHECK_LINE_30 : CLEAR_LINE_24;
    end

    CLEAR_LINE_25: begin
      next_state =  CLEAR_LINE_21;
    end



//biggest
    CHECK_LINE_30:begin
      next_state = check_biggest ? DONE : CHECK_LINE_31;
    end
    CHECK_LINE_31:begin
      next_state = CHECK_LINE_32;
    end

    CHECK_LINE_32:begin
      next_state = blank ? DONE : CHECK_LINE_33;
    end

    CHECK_LINE_33: begin
      next_state = CHECK_LINE_34;
    end

    CHECK_LINE_34:begin
      next_state = reach_row ? CLEAR_LINE_30 : CHECK_LINE_31;
    end


    CLEAR_LINE_30:begin
      next_state = CLEAR_LINE_31;
    end

    CLEAR_LINE_31:begin
      next_state = CLEAR_LINE_32;
    end

    CLEAR_LINE_32:begin
      next_state = CLEAR_LINE_33;
    end

    CLEAR_LINE_33:begin
      next_state = CLEAR_LINE_36;
    end

    CLEAR_LINE_34: begin
      next_state = reach_row ? CLEAR_LINE_35 : CLEAR_LINE_31;
    end

    CLEAR_LINE_36: begin
      next_state = finish_clear ? DONE : CLEAR_LINE_34;
    end

    CLEAR_LINE_35: begin
      next_state =  CLEAR_LINE_31;
    end



    DONE: begin
      next_state = IDLE;
    end
  endcase
end

always_comb begin
  en_ff = 1'b0;
  clear_line_done = 1'b0;
  addr_6 = 10'b0;
  wr_6 = 1'b0;
  rd_6 = 1'b0;
  piece_id_wr_6 = 9'd0;
  
  clear_counter_aclr = 1'b0;
  clear_counter_cnt = 1'b0;
  clear_counter_data = 10'd0;
  clear_counter_aload = 1'b0;
  clear_counter_updown = 1'b0;
  
  st_addr_clear = 1'b0;
  line_counter_cnt = 1'b0;

  clear_score_cnt_en = 1'b0;

  case(current_state)
    IDLE:
    begin
      clear_line_done = 1'b0;
      addr_6 = 10'b0;
      piece_id_wr_6 = 9'd0;
    end

    WAIT_FOR_START: begin
      st_addr_clear = 1'b1;
      clear_counter_aclr = 1'b1;
    end


//Smallest
    CHECK_LINE_00:
    begin
      clear_counter_aclr = 1'b0;
      clear_counter_data = read_small;
      clear_counter_aload = 1'b1;
      st_addr_clear = 1'b0;
      clear_line_done = 1'b0;
    end
   //REad
    CHECK_LINE_01:
    begin
      rd_6 = 1'b1;
      addr_6 = clear_count;
    end

    CHECK_LINE_02:
    begin
      //Do nothing
    end
   //+1
    CHECK_LINE_03:
    begin
      clear_counter_updown = 1'b1;
      clear_counter_cnt = 1'b1;
    end

    CHECK_LINE_04:
    begin
      //Do nothing
      clear_counter_updown = 1'b0;
      clear_counter_cnt = 1'b0;
    end


//Clear highest
    //Load init read address
    CLEAR_LINE_00: begin
      line_counter_cnt = 1'b1;
      clear_counter_aclr = 1'b0;
      clear_counter_cnt = 1'b0;
      clear_counter_data = read_small-10'd32;
      clear_counter_aload = 1'b1;
      clear_counter_updown = 1'b0;

      clear_score_cnt_en = 1'b1;
    end
   //Read
    CLEAR_LINE_01: begin
      rd_6 = 1'b1;
      addr_6 = clear_count;
      clear_counter_cnt = 1'b0;
      clear_counter_updown = 1'b0;
    end
  //Write
    CLEAR_LINE_02: begin
      wr_6 = 1'b1;
      addr_6 = next_clear_count;
      piece_id_wr_6 = piece_id_rd_checking;
      clear_counter_cnt = 1'b0;
      clear_counter_updown = 1'b0;
    end
  //+1
    CLEAR_LINE_03: begin
      clear_counter_cnt = 1'b1;
      clear_counter_updown = 1'b1;
    end

    CLEAR_LINE_04: begin
      //Do nothing
    end

     CLEAR_LINE_05: begin
      clear_counter_data = clear_count_reg-10'd42;
      clear_counter_aload = 1'b1;
      clear_counter_updown = 1'b0;
    end

    CLEAR_LINE_06: begin
      en_ff = 1'b1;
      clear_counter_cnt = 1'b0;
      clear_counter_updown = 1'b0;
    end

  
//Third
    CHECK_LINE_10:
    begin
      clear_counter_aclr = 1'b0;
      clear_counter_data = read_third;
      clear_counter_aload = 1'b1;
      st_addr_clear = 1'b0;
      clear_line_done = 1'b0;
    end
   //REad
    CHECK_LINE_11:
    begin
      rd_6 = 1'b1;
      addr_6 = clear_count;
    end

    CHECK_LINE_12:
    begin
      //Do nothing
    end
   //+1
    CHECK_LINE_13:
    begin
      clear_counter_updown = 1'b1;
      clear_counter_cnt = 1'b1;
    end

    CHECK_LINE_14:
    begin
      //Do nothing
      clear_counter_updown = 1'b0;
      clear_counter_cnt = 1'b0;
    end


//Clear highest
    //Load init read address
    CLEAR_LINE_10: begin
      line_counter_cnt = 1'b1;
      clear_counter_aclr = 1'b0;
      clear_counter_cnt = 1'b0;
      clear_counter_data = read_third-32;
      clear_counter_aload = 1'b1;
      clear_counter_updown = 1'b0;

      clear_score_cnt_en = 1'b1;
    end
   //Read
    CLEAR_LINE_11: begin
      rd_6 = 1'b1;
      addr_6 = clear_count;
      clear_counter_cnt = 1'b0;
      clear_counter_updown = 1'b0;
    end
  //Write
    CLEAR_LINE_12: begin
      wr_6 = 1'b1;
      addr_6 = next_clear_count;
      piece_id_wr_6 = piece_id_rd_checking;
      clear_counter_cnt = 1'b0;
      clear_counter_updown = 1'b0;
    end
  //+1
    CLEAR_LINE_13: begin
      clear_counter_cnt = 1'b1;
      clear_counter_updown = 1'b1;
    end

    CLEAR_LINE_14: begin
      //Do nothing
    end

     CLEAR_LINE_15: begin
      clear_counter_data = clear_count_reg-10'd42;
      clear_counter_aload = 1'b1;
      clear_counter_updown = 1'b0;
    end

    CLEAR_LINE_16: begin
      en_ff = 1'b1;
      clear_counter_cnt = 1'b0;
      clear_counter_updown = 1'b0;
    end




//Second
    CHECK_LINE_20:
    begin
      clear_counter_aclr = 1'b0;
      clear_counter_data = read_second;
      clear_counter_aload = 1'b1;
      st_addr_clear = 1'b0;
      clear_line_done = 1'b0;
    end
   //REad
    CHECK_LINE_21:
    begin
      rd_6 = 1'b1;
      addr_6 = clear_count;
    end

    CHECK_LINE_22:
    begin
      //Do nothing
    end
   //+1
    CHECK_LINE_23:
    begin
      clear_counter_updown = 1'b1;
      clear_counter_cnt = 1'b1;
    end

    CHECK_LINE_24:
    begin
      //Do nothing
      clear_counter_updown = 1'b0;
      clear_counter_cnt = 1'b0;
    end


//Clear highest
    //Load init read address
    CLEAR_LINE_20: begin
      line_counter_cnt = 1'b1;
      clear_counter_aclr = 1'b0;
      clear_counter_cnt = 1'b0;
      clear_counter_data = read_second-32;
      clear_counter_aload = 1'b1;
      clear_counter_updown = 1'b0;

      clear_score_cnt_en = 1'b1;
    end
   //Read
    CLEAR_LINE_21: begin
      rd_6 = 1'b1;
      addr_6 = clear_count;
      clear_counter_cnt = 1'b0;
      clear_counter_updown = 1'b0;
    end
  //Write
    CLEAR_LINE_22: begin
      wr_6 = 1'b1;
      addr_6 = next_clear_count;
      piece_id_wr_6 = piece_id_rd_checking;
      clear_counter_cnt = 1'b0;
      clear_counter_updown = 1'b0;
    end
  //+1
    CLEAR_LINE_23: begin
      clear_counter_cnt = 1'b1;
      clear_counter_updown = 1'b1;
    end

    CLEAR_LINE_24: begin
      //Do nothing
    end

     CLEAR_LINE_25: begin
      clear_counter_data = clear_count_reg-10'd42;
      clear_counter_aload = 1'b1;
      clear_counter_updown = 1'b0;
    end

    CLEAR_LINE_26: begin
      en_ff = 1'b1;
      clear_counter_cnt = 1'b0;
      clear_counter_updown = 1'b0;
    end



//big
    CHECK_LINE_30:
    begin
      clear_counter_aclr = 1'b0;
      clear_counter_data = read_big;
      clear_counter_aload = 1'b1;
      st_addr_clear = 1'b0;
      clear_line_done = 1'b0;
    end
   //REad
    CHECK_LINE_31:
    begin
      rd_6 = 1'b1;
      addr_6 = clear_count;
    end

    CHECK_LINE_32:
    begin
      //Do nothing
    end
   //+1
    CHECK_LINE_33:
    begin
      clear_counter_updown = 1'b1;
      clear_counter_cnt = 1'b1;
    end

    CHECK_LINE_34:
    begin
      //Do nothing
      clear_counter_updown = 1'b0;
      clear_counter_cnt = 1'b0;
    end


//Clear highest
    //Load init read address
    CLEAR_LINE_30: begin
      line_counter_cnt = 1'b1;
      clear_counter_aclr = 1'b0;
      clear_counter_cnt = 1'b0;
      clear_counter_data = read_big-32;
      clear_counter_aload = 1'b1;
      clear_counter_updown = 1'b0;

      clear_score_cnt_en = 1'b1;
    end
   //Read
    CLEAR_LINE_31: begin
      rd_6 = 1'b1;
      addr_6 = clear_count;
      clear_counter_cnt = 1'b0;
      clear_counter_updown = 1'b0;
    end
  //Write
    CLEAR_LINE_32: begin
      wr_6 = 1'b1;
      addr_6 = next_clear_count;
      piece_id_wr_6 = piece_id_rd_checking;
      clear_counter_cnt = 1'b0;
      clear_counter_updown = 1'b0;
    end
  //+1
    CLEAR_LINE_33: begin
      clear_counter_cnt = 1'b1;
      clear_counter_updown = 1'b1;
    end

    CLEAR_LINE_34: begin
      //Do nothing
    end

     CLEAR_LINE_35: begin
      clear_counter_data = clear_count_reg-10'd42;
      clear_counter_aload = 1'b1;
      clear_counter_updown = 1'b0;
    end

    CLEAR_LINE_36: begin
      en_ff = 1'b1;
      clear_counter_cnt = 1'b0;
      clear_counter_updown = 1'b0;
    end


    DONE:
    begin
      piece_id_wr_6 = 9'd0;
      addr_6 = 10'd0;
      clear_line_done = 1'b1;
    end
  endcase
end


assign c_state = current_state;
endmodule
























//     CHECK_LINE_10:
//     begin
//       clear_line_done = 1'b0;
//     end

//     CHECK_LINE_11:
//     begin
//       rd_6 = 1'b1;
//       addr_6 = (third & ~10'b0000011111) | 5'd13;
//     end

//     CHECK_LINE_12:
//     begin
//       rd_6 = 1'b1;
//       addr_6 = (third & ~10'b0000011111) | 5'd14;
//     end

//     CHECK_LINE_13:
//     begin
//       rd_6 = 1'b1;
//       addr_6 = (third & ~10'b0000011111) | 5'd15;
//     end

//     CHECK_LINE_14:
//     begin
//       rd_6 = 1'b1;
//       addr_6 = (third & ~10'b0000011111) | 5'd16;
//     end

//     CHECK_LINE_15:
//     begin
//       rd_6 = 1'b1;
//       addr_6 = (third & ~10'b0000011111) | 5'd17;
//     end

//     CHECK_LINE_16:
//     begin
//       rd_6 = 1'b1;
//       addr_6 = (third & ~10'b0000011111) | 5'd18;
//     end

//     CHECK_LINE_17:
//     begin
//       rd_6 = 1'b1;
//       addr_6 = (third & ~10'b0000011111) | 5'd19;
//     end

//     CHECK_LINE_18:
//     begin
//       rd_6 = 1'b1;
//       addr_6 = (third & ~10'b0000011111) | 5'd20;
//     end

//     CHECK_LINE_19:
//     begin
//       rd_6 = 1'b1;
//       addr_6 = (third & ~10'b0000011111) | 5'd21;
//     end
    
//     CHECK_LINE_1A:
//     begin
//       rd_6 = 1'b1;
//       addr_6 = (third & ~10'b0000011111) | 5'd22;
//     end

//     CHECK_LINE_1B:
//     begin
//       clear_line_done = 1'b0;
//       clear_counter_aclr = 1'b1;
//     end

// //Clear highest
// //Load init
//     CLEAR_LINE_10: begin
//       clear_counter_aclr = 1'b0;
//       clear_counter_cnt = 1'b0;
//       clear_counter_data = ((third/32)-1) * 32 + 13;
//       clear_counter_aload = 1'b1;
//       clear_counter_updown = 1'b0;
//     end
// //Read
//     CLEAR_LINE_11: begin
//       rd_6 = 1'b1;
//       wr_6 = 1'b0;
//       addr_6 = clear_count;
//       clear_counter_cnt = 1'b0;
//       clear_counter_updown = 1'b0;
//     end
// //Write
//     CLEAR_LINE_12: begin
//       rd_6 = 1'b0;
//       wr_6 = 1'b1;
//       addr_6 = next_clear_count;
//       piece_id_wr_6 = piece_id_rd_checking;
//       clear_counter_cnt = 1'b0;
//       clear_counter_updown = 1'b0;
//     end
// //+1
//     CLEAR_LINE_13: begin
//       clear_counter_cnt = 1'b1;
//       clear_counter_updown = 1'b1;
//     end

//     CLEAR_LINE_16: begin
//       en_ff = 1'b1;
//     end

//      CLEAR_LINE_15: begin
//       clear_counter_data = clear_count_reg - 10'd42;
//       clear_counter_aload = 1'b1;
//       clear_counter_updown = 1'b0;
//     end




//     CHECK_LINE_20:
//     begin
//       clear_line_done = 1'b0;
//     end

//     CHECK_LINE_21:
//     begin
//       rd_6 = 1'b1;
//       addr_6 = (second & ~10'b0000011111) | 5'd13;
//     end

//     CHECK_LINE_22:
//     begin
//       rd_6 = 1'b1;
//       addr_6 = (second & ~10'b0000011111) | 5'd14;
//     end

//     CHECK_LINE_23:
//     begin
//       rd_6 = 1'b1;
//       addr_6 = (second & ~10'b0000011111) | 5'd15;
//     end

//     CHECK_LINE_24:
//     begin
//       rd_6 = 1'b1;
//       addr_6 = (second & ~10'b0000011111) | 5'd16;
//     end

//     CHECK_LINE_25:
//     begin
//       rd_6 = 1'b1;
//       addr_6 = (second & ~10'b0000011111) | 5'd17;
//     end

//     CHECK_LINE_26:
//     begin
//       rd_6 = 1'b1;
//       addr_6 = (second & ~10'b0000011111) | 5'd18;
//     end

//     CHECK_LINE_27:
//     begin
//       rd_6 = 1'b1;
//       addr_6 = (second & ~10'b0000011111) | 5'd19;
//     end

//     CHECK_LINE_28:
//     begin
//       rd_6 = 1'b1;
//       addr_6 = (second & ~10'b0000011111) | 5'd20;
//     end

//     CHECK_LINE_29:
//     begin
//       rd_6 = 1'b1;
//       addr_6 = (second & ~10'b0000011111) | 5'd21;
//     end
    
//     CHECK_LINE_2A:
//     begin
//       rd_6 = 1'b1;
//       addr_6 = (second & ~10'b0000011111) | 5'd22;
//     end

//     CHECK_LINE_2B:
//     begin
//       clear_line_done = 1'b0;
//       clear_counter_aclr = 1'b1;
//     end

// //Clear highest
// //Load init
//     CLEAR_LINE_20: begin
//       clear_counter_aclr = 1'b0;
//       clear_counter_cnt = 1'b0;
//       clear_counter_data = ((second/32) - 1)*32 + 13;
//       clear_counter_aload = 1'b1;
//       clear_counter_updown = 1'b0;
//     end
// //Read
//     CLEAR_LINE_21: begin
//       rd_6 = 1'b1;
//       wr_6 = 1'b0;
//       addr_6 = clear_count;
//       clear_counter_cnt = 1'b0;
//       clear_counter_updown = 1'b0;
//     end
// //Write
//     CLEAR_LINE_22: begin
//       rd_6 = 1'b0;
//       wr_6 = 1'b1;
//       addr_6 = next_clear_count;
//       piece_id_wr_6 = piece_id_rd_checking;
//       clear_counter_cnt = 1'b0;
//       clear_counter_updown = 1'b0;
//     end
// //+1
//     CLEAR_LINE_23: begin
//       clear_counter_cnt = 1'b1;
//       clear_counter_updown = 1'b1;
//     end

//     CLEAR_LINE_26: begin
//      en_ff = 1'b1;
//     end

//      CLEAR_LINE_25: begin
//       clear_counter_data = clear_count_reg - 10'd42;
//       clear_counter_aload = 1'b1;
//       clear_counter_updown = 1'b0;
//     end



//     CHECK_LINE_30:
//     begin
//       clear_line_done = 1'b0;
//     end

//     CHECK_LINE_31:
//     begin
//       rd_6 = 1'b1;
//       addr_6 = (biggest & ~10'b0000011111) | 5'd13;
//     end

//     CHECK_LINE_32:
//     begin
//       rd_6 = 1'b1;
//       addr_6 = (biggest & ~10'b0000011111) | 5'd14;
//     end

//     CHECK_LINE_33:
//     begin
//       rd_6 = 1'b1;
//       addr_6 = (biggest & ~10'b0000011111) | 5'd15;
//     end

//     CHECK_LINE_34:
//     begin
//       rd_6 = 1'b1;
//       addr_6 = (biggest & ~10'b0000011111) | 5'd16;
//     end

//     CHECK_LINE_35:
//     begin
//       rd_6 = 1'b1;
//       addr_6 = (biggest & ~10'b0000011111) | 5'd17;
//     end

//     CHECK_LINE_36:
//     begin
//       rd_6 = 1'b1;
//       addr_6 = (biggest & ~10'b0000011111) | 5'd18;
//     end

//     CHECK_LINE_37:
//     begin
//       rd_6 = 1'b1;
//       addr_6 = (biggest & ~10'b0000011111) | 5'd19;
//     end

//     CHECK_LINE_38:
//     begin
//       rd_6 = 1'b1;
//       addr_6 = (biggest & ~10'b0000011111) | 5'd20;
//     end

//     CHECK_LINE_39:
//     begin
//       rd_6 = 1'b1;
//       addr_6 = (biggest & ~10'b0000011111) | 5'd21;
//     end
    
//     CHECK_LINE_3A:
//     begin
//       rd_6 = 1'b1;
//       addr_6 = (biggest & ~10'b0000011111) | 5'd22;
//     end

//     CHECK_LINE_3B:
//     begin
//       clear_line_done = 1'b0;
//       clear_counter_aclr = 1'b1;
//     end

// //Clear highest
// //Load init
//     CLEAR_LINE_30: begin
//       clear_counter_aclr = 1'b0;
//       clear_counter_cnt = 1'b0;
//       clear_counter_data = ((biggest/32) - 1)*32 + 13;
//       clear_counter_aload = 1'b1;
//       clear_counter_updown = 1'b0;
//     end
// //Read
//     CLEAR_LINE_31: begin
//       rd_6 = 1'b1;
//       wr_6 = 1'b0;
//       addr_6 = clear_count;
//       clear_counter_cnt = 1'b0;
//       clear_counter_updown = 1'b0;
//     end

//     //Write
//     CLEAR_LINE_37: begin
//     end

// //Write
//     CLEAR_LINE_32: begin
//       rd_6 = 1'b0;
//       wr_6 = 1'b1;
//       addr_6 = next_clear_count;
//       piece_id_wr_6 = piece_id_rd_checking;
//       clear_counter_cnt = 1'b0;
//       clear_counter_updown = 1'b0;
//     end
// //+1
//     CLEAR_LINE_33: begin
//       clear_counter_cnt = 1'b1;
//       clear_counter_updown = 1'b1;
//     end

//     CLEAR_LINE_36: begin
//       en_ff = 1'b1;
//     end

//     CLEAR_LINE_35: begin
//       clear_counter_data = clear_count_reg - 10'd42;
//       clear_counter_aload = 1'b1;
//       clear_counter_updown = 1'b0;
//     end














































// //Second
//     CHECK_LINE_10:begin
//       next_state = check_third ? CHECK_LINE_20 : CHECK_LINE_11;

//     end
//     CHECK_LINE_11:begin
//       next_state = CHECK_LINE_12;
//     end

//     CHECK_LINE_12:begin
//       next_state = blank ? CHECK_LINE_20 : CHECK_LINE_13;
//     end

//     CHECK_LINE_13:begin
//       next_state = blank ? CHECK_LINE_20 : CHECK_LINE_14;
//     end

//     CHECK_LINE_14:begin
//       next_state = blank ? CHECK_LINE_20 : CHECK_LINE_15;
//     end

//     CHECK_LINE_15:begin
//       next_state = blank ? CHECK_LINE_20 : CHECK_LINE_16;
//     end

//     CHECK_LINE_16:begin
//       next_state = blank ? CHECK_LINE_20 : CHECK_LINE_17;
//     end

//     CHECK_LINE_17:begin
//       next_state = blank ? CHECK_LINE_20 : CHECK_LINE_18;
//     end

//     CHECK_LINE_18:begin
//       next_state = blank ? CHECK_LINE_20 : CHECK_LINE_19;
//     end

//     CHECK_LINE_19:begin
//       next_state = blank ? CHECK_LINE_20 : CHECK_LINE_1A;
//     end

//     CHECK_LINE_1A:begin
//       next_state = blank ? CHECK_LINE_20 : CHECK_LINE_1B;
//     end

//     CHECK_LINE_1B:begin
//       next_state = blank ? CHECK_LINE_20 : CLEAR_LINE_10;
//     end

//     CLEAR_LINE_10:begin
//       next_state = CLEAR_LINE_11;
//     end

//     CLEAR_LINE_11:begin
//       next_state = CLEAR_LINE_12;
//     end

//     CLEAR_LINE_12:begin
//       next_state = CLEAR_LINE_13;
//     end

//     CLEAR_LINE_13:begin
//       next_state = CLEAR_LINE_14;
//     end

//     CLEAR_LINE_14: begin
//       next_state = next_clear_count[4:0] == 23 ? CLEAR_LINE_15 : CLEAR_LINE_11;
//     end

//     CLEAR_LINE_16: begin
//       next_state = (next_clear_count  < 10'd216) ? CHECK_LINE_20 : CLEAR_LINE_14;
//     end

//     CLEAR_LINE_15: begin
//       next_state =  CLEAR_LINE_11;
//     end



// //Third
//     CHECK_LINE_20:begin
//       next_state = check_second ? CHECK_LINE_30 : CHECK_LINE_21;
//     end
//     CHECK_LINE_21:begin
//       next_state = CHECK_LINE_22;
//     end

//     CHECK_LINE_22:begin
//       next_state = blank ? CHECK_LINE_30 : CHECK_LINE_23;
//     end

//     CHECK_LINE_23:begin
//       next_state = blank ? CHECK_LINE_30 : CHECK_LINE_24;
//     end

//     CHECK_LINE_24:begin
//       next_state = blank ? CHECK_LINE_30 : CHECK_LINE_25;
//     end

//     CHECK_LINE_25:begin
//       next_state = blank ? CHECK_LINE_30 : CHECK_LINE_26;
//     end

//     CHECK_LINE_26:begin
//       next_state = blank ? CHECK_LINE_30 : CHECK_LINE_27;
//     end

//     CHECK_LINE_27:begin
//       next_state = blank ? CHECK_LINE_30 : CHECK_LINE_28;
//     end

//     CHECK_LINE_28:begin
//       next_state = blank ? CHECK_LINE_30 : CHECK_LINE_29;
//     end

//     CHECK_LINE_29:begin
//       next_state = blank ? CHECK_LINE_30 : CHECK_LINE_2A;
//     end

//     CHECK_LINE_2A:begin
//       next_state = blank ? CHECK_LINE_30 : CHECK_LINE_2B;
//     end

//     CHECK_LINE_2B:begin
//       next_state = blank ? CHECK_LINE_30 : CLEAR_LINE_20;
//     end


//     CLEAR_LINE_20:begin
//       next_state = CLEAR_LINE_21;
//     end

//     CLEAR_LINE_21:begin
//       next_state = CLEAR_LINE_22;
//     end

//     CLEAR_LINE_22:begin
//       next_state = CLEAR_LINE_23;
//     end

//     CLEAR_LINE_23:begin
//       next_state = CLEAR_LINE_26;
//     end

//     CLEAR_LINE_24: begin
//       next_state =  next_clear_count[4:0] == 23 ? CLEAR_LINE_25 : CLEAR_LINE_21;
//     end

//     CLEAR_LINE_26: begin
//       next_state = (next_clear_count  < 10'd216) ? CHECK_LINE_30 : CLEAR_LINE_24;
//     end

//     CLEAR_LINE_25: begin
//       next_state =  CLEAR_LINE_21;
//     end




// //Biggest
//     CHECK_LINE_30:begin
//       next_state = check_biggest ? DONE : CHECK_LINE_31;
//     end
//     CHECK_LINE_31:begin
//       next_state = CHECK_LINE_32;
//     end

//     CHECK_LINE_32:begin
//       next_state = blank ? DONE : CHECK_LINE_33;
//     end

//     CHECK_LINE_33:begin
//       next_state = blank ? DONE : CHECK_LINE_34;
//     end

//     CHECK_LINE_34:begin
//       next_state = blank ? DONE : CHECK_LINE_35;
//     end

//     CHECK_LINE_35:begin
//       next_state = blank ? DONE : CHECK_LINE_36;
//     end

//     CHECK_LINE_36:begin
//       next_state = blank ? DONE : CHECK_LINE_37;
//     end

//     CHECK_LINE_37:begin
//       next_state = blank ? DONE : CHECK_LINE_38;
//     end

//     CHECK_LINE_38:begin
//       next_state = blank ? DONE : CHECK_LINE_39;
//     end

//     CHECK_LINE_39:begin
//       next_state = blank ? DONE : CHECK_LINE_3A;
//     end

//     CHECK_LINE_3A:begin
//       next_state = blank ? DONE : CHECK_LINE_3B;
//     end

//     CHECK_LINE_3B:begin
//       next_state = blank ? DONE : CLEAR_LINE_30;
//     end

//     CLEAR_LINE_30:begin
//       next_state = CLEAR_LINE_31;
//     end

//     CLEAR_LINE_31:begin
//       next_state = CLEAR_LINE_37;
//     end

//     CLEAR_LINE_37:begin
//       next_state = CLEAR_LINE_32;
//     end

//     CLEAR_LINE_32:begin
//       next_state = CLEAR_LINE_33;
//     end

//     CLEAR_LINE_33:begin
//       next_state = CLEAR_LINE_36;
//     end

//     CLEAR_LINE_34: begin
//       next_state =  next_clear_count[4:0] == 23 ? CLEAR_LINE_35 : CLEAR_LINE_31;
//     end

//     CLEAR_LINE_36: begin
//       next_state = (next_clear_count  < 10'd216) ? DONE : CLEAR_LINE_34;
//     end

//     CLEAR_LINE_35: begin
//       next_state =  CLEAR_LINE_31;
//     end




































    // CHECK_LINE_05:
    // begin
    //   rd_6 = 1'b1;
    //   addr_6 = (smallest & ~10'b0000011111) | 5'd17;
    // end

    // CHECK_LINE_06:
    // begin
    //   rd_6 = 1'b1;
    //   addr_6 = (smallest & ~10'b0000011111) | 5'd18;
    // end

    // CHECK_LINE_07:
    // begin
    //   rd_6 = 1'b1;
    //   addr_6 = (smallest & ~10'b0000011111) | 5'd19;
    // end

    // CHECK_LINE_08:
    // begin
    //   rd_6 = 1'b1;
    //   addr_6 = (smallest & ~10'b0000011111) | 5'd20;
    // end

    // CHECK_LINE_09:
    // begin
    //   rd_6 = 1'b1;
    //   addr_6 = (smallest & ~10'b0000011111) | 5'd21;
    // end
    
    // CHECK_LINE_0A:
    // begin
    //   rd_6 = 1'b1;
    //   addr_6 = (smallest & ~10'b0000011111) | 5'd22;
    // end

    // CHECK_LINE_0B:
    // begin
    //   clear_line_done = 1'b0;
    //   clear_counter_aclr = 1'b0;
    // end
