module control_input (
  input logic clk,
  input logic rst_n,
  input logic [16:0] data,

  input logic select_speed_down,

  output logic press_left,
  output logic press_right,
  output logic press_up,
  output logic press_enter,
  output logic press_down,
  output logic press_x,
  output logic press_z
);
// ENTER key
logic aclr_enter, cnt_en_enter;
logic [25:0] q_enter;


control_delay enter(
  .button_in(data == 16'h005a),
  .clk(clk),
  .rst_n(rst_n),
  .equal(q_enter==26'd10_000_000),

  .aclr(aclr_enter),
  .cnt_en(cnt_en_enter),
  .button_out(press_enter)
);

counter enter_counter (
	.aclr(aclr_enter),
	.clock(clk),
	.cnt_en(cnt_en_enter),
	.q(q_enter)
);

// LEFT key
logic aclr_left, cnt_en_left;
logic [25:0] q_left;

control_delay left(
  .button_in(data == 16'he06b),
  .clk(clk),
  .rst_n(rst_n),
  .equal(q_left==26'd7_000_000),

  .aclr(aclr_left),
  .cnt_en(cnt_en_left),
  .button_out(press_left)
);

counter left_counter (
	.aclr(aclr_left),
	.clock(clk),
	.cnt_en(cnt_en_left),
	.q(q_left)
);

// RIGHT key
logic aclr_right, cnt_en_right;
logic [25:0] q_right;

control_delay right(
  .button_in(data == 16'he074),
  .clk(clk),
  .rst_n(rst_n),
  .equal(q_right==26'd7_000_000),

  .aclr(aclr_right),
  .cnt_en(cnt_en_right),
  .button_out(press_right)
);

counter right_counter (
	.aclr(aclr_right),
	.clock(clk),
	.cnt_en(cnt_en_right),
	.q(q_right)
);


// DOWN key fast
logic aclr_down_1, cnt_en_down_1;
logic [25:0] q_down_1;
logic press_down_1;

control_delay space(
  .button_in(data == 16'he072),
  .clk(clk),
  .rst_n(rst_n),
  .equal(q_down_1==26'd2_500_000),

  .aclr(aclr_down_1),
  .cnt_en(cnt_en_down_1),
  .button_out(press_down_1)
);

counter space_counter (
	.aclr(aclr_down_1),
	.clock(clk),
	.cnt_en(cnt_en_down_1),
	.q(q_down_1)
);


// UP key
logic aclr_up, cnt_en_up;
logic [25:0] q_up;

control_delay up(
  .button_in(data == 16'he075),
  .clk(clk),
  .rst_n(rst_n),
  .equal(q_up==26'd10_000_000),

  .aclr(aclr_up),
  .cnt_en(cnt_en_up),
  .button_out(press_up)
);

counter up_counter (
	.aclr(aclr_up),
	.clock(clk),
	.cnt_en(cnt_en_up),
	.q(q_up)
);



// DOWN key slow
logic aclr_down_0, cnt_en_down_0;
logic [25:0] q_down_0;
logic press_down_0;

control_delay down(
  .button_in(data == 16'he072),
  .clk(clk),
  .rst_n(rst_n),
  .equal(q_down_0==26'd10_000_000),

  .aclr(aclr_down_0),
  .cnt_en(cnt_en_down_0),
  .button_out(press_down_0)
);

counter down_counter (
	.aclr(aclr_down_0),
	.clock(clk),
	.cnt_en(cnt_en_down_0),
	.q(q_down_0)
);

// X key
logic aclr_x, cnt_en_x;
logic [25:0] q_x;

control_delay x(
  .button_in(data == 16'h0022),
  .clk(clk),
  .rst_n(rst_n),
  .equal(q_x==26'd10_000_000),

  .aclr(aclr_x),
  .cnt_en(cnt_en_x),
  .button_out(press_x)
);

counter x_counter (
	.aclr(aclr_x),
	.clock(clk),
	.cnt_en(cnt_en_x),
	.q(q_x)
);

// Z key
logic aclr_z, cnt_en_z;
logic [25:0] q_z;

control_delay z(
  .button_in(data == 16'h001a),
  .clk(clk),
  .rst_n(rst_n),
  .equal(q_z==26'd10_000_000),

  .aclr(aclr_z),
  .cnt_en(cnt_en_z),
  .button_out(press_z)
);

counter z_counter (
	.aclr(aclr_z),
	.clock(clk),
	.cnt_en(cnt_en_z),
	.q(q_z)
);


assign press_down =  select_speed_down ? press_down_0 : press_down_1;
endmodule