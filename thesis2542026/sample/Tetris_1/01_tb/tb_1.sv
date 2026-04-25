`timescale 1ns/1ps

module tb_1;

  // Clock & Reset
  logic clk;
  logic rst_n;

  // DUT inputs
  logic clear_line_start;
  logic [9:0] pivot_addr_reg, cur_addr_1_reg, cur_addr_2_reg, cur_addr_3_reg;
  logic blank;
  logic [9:0] piece_id_rd_checking;

  // DUT outputs
  logic clear_line_done;
  logic [8:0] piece_id_wr_6;
  logic [9:0] addr_6;
  logic wr_6, rd_6;
  logic [6:0] c_state;

  // Clock gen: 100 MHz
  initial clk = 0;
  always #5 clk = ~clk;

  // DUT instance
  clear_line dut (
    .clk(clk),
    .rst_n(rst_n),
    .clear_line_start(clear_line_start),
    .clear_line_done(clear_line_done),
    .pivot_addr_reg(pivot_addr_reg),
    .cur_addr_1_reg(cur_addr_1_reg),
    .cur_addr_2_reg(cur_addr_2_reg),
    .cur_addr_3_reg(cur_addr_3_reg),
    .blank(blank),
    .piece_id_wr_6(piece_id_wr_6),
    .addr_6(addr_6),
    .wr_6(wr_6),
    .rd_6(rd_6),
    .c_state(c_state),
    .piece_id_rd_checking(piece_id_rd_checking)
  );

  // Stimulus
  initial begin
    // Init
    rst_n = 0;
    clear_line_start = 0;
    pivot_addr_reg = 10'd789;      // Example piece pivot
    cur_addr_1_reg = 10'd790;
    cur_addr_2_reg = 10'd757;
    cur_addr_3_reg = 10'd722;
    piece_id_rd_checking = 10'd18; // non-blank ID
    blank = 0;

    // Apply reset
    #20;
    rst_n = 1;

    // Start FSM
    #20;
    clear_line_start = 1;
    #10;
    clear_line_start = 0; // Pulse

    blank = 0;

    #1000000;
    $finish;
  end

  // Debug print
  always @(posedge clk) begin
    $display("[%0t] state=%0d, wr=%0b, rd=%0b, addr=%0d, pid_wr=%0d, done=%0b",
              $time, c_state, wr_6, rd_6, addr_6, piece_id_wr_6, clear_line_done);
  end

endmodule
