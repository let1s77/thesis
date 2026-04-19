`timescale 1ns/1ps
//`default_nettype none  // (optional, stricter lint)

module tb;
  // Clock period (100 MHz)
  localparam time CLK_PERIOD = 10ns;

  logic i_clk   = 1'b0;
  logic i_rst_n = 1'b0;   // active-low reset
  logic i_left  = 1'b0;
  logic o_hsync;
  logic o_vsync;
  logic o_sync_n;
  logic o_vga_clk;
  logic o_blank_n;
  logic [7:0] o_red;
  logic [7:0] o_green;
  logic [7:0] o_blue;
  logic [9:0] H_Count_Value;
  logic [9:0] V_Count_Value;

  logic check_enter,check_left,check_right,check_down, check_x,check_z,check_up;
  logic [7:0] c_statec;

  logic [6:0] cstatec;
  // DUT
  Tetris_0 dut (
    .i_clk  (i_clk),
    .i_rst_n(i_rst_n),
    .o_hsync(o_hsync),
    .o_vsync(o_vsync),
    .o_sync_n(o_sync_n),
    .o_vga_clk(o_vga_clk),
    .o_blank_n(o_blank_n),
    .o_red(o_red),
    .o_green(o_green),
    .o_blue(o_blue),

    .check_enter(check_enter),
    .check_down(check_down),
    .check_right(check_right),
    .check_left(check_left),
    .check_x(check_x),
    .check_z(check_z),
    .check_up(check_up),
    .cstatec(cstatec),
    .c_statec(c_statec)

  );



  // Clock gen
  always #(2) i_clk = ~i_clk;

  // Reset: hold low for a few cycles, then deassert to 1
  initial begin
    i_rst_n = 1'b0;
    repeat (5) @(posedge i_clk);
    i_rst_n = 1'b1;
  end

  // Run & optional waveform dump
  initial begin
    //$dumpfile("tb.vcd");   // works in many sims (e.g., iverilog/Questa VCD)
    //$dumpvars(0, tb);

    $display("[%0t] TB start", $time);
    wait (i_rst_n === 1'b1);
    $display("[%0t] Reset deasserted", $time);
    check_enter = 1'b0;
    check_down = 1'b0;
    check_x = 1'b0;
    check_right = 1'b0;
    check_left = 1'b0;
        check_z = 1'b0;
        check_up=1'b0;
    // Let it run for a while
    #10001
    check_enter = 1'b1;
    #3
    check_enter = 1'b0;
    #3
    #19999
    check_enter = 1'b1;
    #3
    check_enter = 1'b0;
    repeat (2000) @(posedge i_clk);  // hold for 100 cycles
    check_left = 1'b1;
    #9
    check_left = 1'b0;
    #100
    check_left = 1'b1;
    #9
    check_left = 1'b0;
    #100
    check_left = 1'b1;
    #9
    check_left = 1'b0;

    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_x = 1'b1;
    #9
    check_x = 1'b0;
    #100
    check_x = 1'b1;
    #9
    check_x = 1'b0;

    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #300
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_x = 1'b1;
    #9
    check_x = 1'b0;
    #100
    check_x = 1'b1;
    #9
    check_x = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;


    #300
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;

    #100
    check_right = 1'b1;
    #9
    check_right = 1'b0;

    #100
    check_right = 1'b1;
    #9
    check_right = 1'b0;

    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;

//////////////////////////////////////4
    #300
    check_down = 1'b1;
    #9
    check_down = 1'b0;

    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_x = 1'b1;
    #9
    check_x = 1'b0;

    #100
    check_right = 1'b1;
    #9
    check_right = 1'b0;
    #100
    check_right = 1'b1;
    #9
    check_right = 1'b0;
    #100
    check_right = 1'b1;
    #9
    check_right = 1'b0;
    #100
    check_right = 1'b1;
    #9
    check_right = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    #100
    check_down = 1'b1;
    #9
    check_down = 1'b0;
    
    repeat (1000000) @(posedge i_clk);
    repeat (1000000) @(posedge i_clk);
    repeat (1000000) @(posedge i_clk);
    repeat (1000000) @(posedge i_clk);
    repeat (1000000) @(posedge i_clk);
    
    $finish;
  end
endmodule
