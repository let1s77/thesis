// This module is a VGA horizontal counter
module vga_horizontal_counter( 
  input  logic        clk, 
  output logic        enable_V_Counter, 
  output logic [9:0] H_Count_Value
); 

  always @(posedge clk) begin 
    if (H_Count_Value < 10'd799) begin 
      H_Count_Value <= H_Count_Value + 10'd1; 
      enable_V_Counter <= 1'b0; // disable vertical counter 
    end 
    else begin 
      H_Count_Value <=  10'b0; // reset Horizontal counter 
      enable_V_Counter <=  1'b1; // trigger V counter 
    end 
  end 
endmodule