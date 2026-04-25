module map_controller (
  input logic        rst_n,
  input logic        clk,
//In
  input logic  [2:0] map_id,
  input logic        map_load_start,
//Out
  output logic       map_load_done,
  output logic [9:0] addr_1,
  output logic [8:0] piece_id_wr_1
);

logic         aclr;
logic         cnt_en;

logic [12:0]  q;

logic [9:0] internal_count;

assign q = (map_id - 7'd1)*10'd1000 + internal_count;

assign map_load_done = addr_1 == 10'd961;

assign addr_1 = internal_count - 2'd1;

map_rom map_rom_u(
  .address(q),
  .clock(clk),
  .q(piece_id_wr_1)
);

render_counter render_counter_u(
  .aclr(aclr|~rst_n),
  .clock(clk),
  .cnt_en(cnt_en),
  .q(internal_count)
);



map_fsm map_fsm_u(
  .clk(clk),
  .rst_n(rst_n),
  .map_load_start(map_load_start),
  .done(map_load_done),

  .aclr(aclr),
  .cnt_en(cnt_en)
);

endmodule