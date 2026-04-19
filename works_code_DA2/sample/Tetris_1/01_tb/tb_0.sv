`timescale 1ns/1ps

module tb_0;

  // DUT signals
  logic [9:0] pivot_addr_reg;
  logic [9:0] cur_addr_1_reg, cur_addr_2_reg, cur_addr_3_reg;
  logic [2:0] move_data;
  logic [9:0] next_pivot_addr, next_addr_1, next_addr_2, next_addr_3;

  // Instantiate DUT
  cal_next_addr dut (
    .pivot_addr_reg(pivot_addr_reg),
    .cur_addr_1_reg(cur_addr_1_reg),
    .cur_addr_2_reg(cur_addr_2_reg),
    .cur_addr_3_reg(cur_addr_3_reg),
    .move_data(move_data),
    .next_pivot_addr(next_pivot_addr),
    .next_addr_1(next_addr_1),
    .next_addr_2(next_addr_2),
    .next_addr_3(next_addr_3)
  );

  // Task to apply a test case
  task apply_test(input [9:0] pivot, a1, a2, a3);
    begin
      pivot_addr_reg = pivot;
      cur_addr_1_reg = a1;
      cur_addr_2_reg = a2;
      cur_addr_3_reg = a3;

      // Sweep move_data 1..5
      for (int mv = 1; mv <= 5; mv++) begin
        move_data = mv[2:0];
        #1; // allow combinational settle
        $display("pivot=%0d a1=%0d a2=%0d a3=%0d | move=%0d -> next_pivot=%0d next1=%0d next2=%0d next3=%0d",
                 pivot_addr_reg, cur_addr_1_reg, cur_addr_2_reg, cur_addr_3_reg,
                 move_data, next_pivot_addr, next_addr_1, next_addr_2, next_addr_3);
      end
    end
  endtask

  initial begin
    $display("=== Start Simulation ===");
    // Loop through pivot values 205 to 214
    for (int base = 205; base <= 214; base++) begin
      apply_test(base, base+1, base+2, base+3);
    end
    $display("=== Simulation Finished ===");
    $finish;
  end

endmodule
