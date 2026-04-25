// This module is a VGA vertical counter
module vga_vertical_counter( 
  input  logic        clk, 
  input  logic        enable_V_Counter, 
  output logic [9:0] V_Count_Value
); 
always @(posedge clk) begin 
  // keep counting until 525 
  if(enable_V_Counter == 1'b1) begin
    if (V_Count_Value < 10'd524) 
      V_Count_Value <= V_Count_Value + 10'd1; 
    else V_Count_Value <= 10'b0; // reset Horizontal counter 
  end 
end
endmodule