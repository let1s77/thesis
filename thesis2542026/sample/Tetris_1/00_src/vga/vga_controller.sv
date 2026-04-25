// This module is a VGA controller only for DE-Series kit by Altera
module vga_controller (
  input  logic        clk,
  input  logic        rst_n,

  input  logic [3:0] pixel_red,
  input  logic [3:0] pixel_green,
  input  logic [3:0] pixel_blue,
  
  output logic        hsync, 
  output logic        vsync, 
  output logic        blank_n,
  output logic        sync_n,
  output logic [7:0]  red, 
  output logic [7:0]  green,
  output logic [7:0]  blue,
  output logic        vga_clk,
  output logic [9:0] H_Count_Value,
  output logic [9:0] V_Count_Value
);
  logic       clk_pll, enable_V_Counter;

  // PLL pll_u (
  //   .ref_clk_clk(clk), 
  //   .vga_clk_clk(clk_pll)
  // ); 

  always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n)
            vga_clk <= 1'b0;
        else
            vga_clk <= ~vga_clk;  // toggle every rising edge
  end


  // assign vga_clk = clk_pll;
  
  vga_horizontal_counter vga_horizontal_counter_u (
    .clk(vga_clk), 
    .enable_V_Counter(enable_V_Counter), 
    .H_Count_Value(H_Count_Value)
  ); 
  
  vga_vertical_counter vga_vertical_counter_u (
    .clk(vga_clk), 
    .enable_V_Counter(enable_V_Counter),
    .V_Count_Value(V_Count_Value)
  ); 

  assign hsync = (H_Count_Value < 96)? 1'b0:1'b1; 
  assign vsync = (V_Count_Value < 2) ? 1'b0:1'b1; 
  // colors all colors high white screen 
  assign red = (H_Count_Value < 784 && H_Count_Value > 143 && V_Count_Value < 515 && V_Count_Value > 34) ? {pixel_red,pixel_red} : 8'h0; 
  assign green = (H_Count_Value < 784 && H_Count_Value > 143 && V_Count_Value < 515 && V_Count_Value > 34) ? {pixel_green,pixel_green} : 8'h0; 
  assign blue = (H_Count_Value < 784 && H_Count_Value > 143 && V_Count_Value < 515 && V_Count_Value > 34) ? {pixel_blue,pixel_blue} : 8'h0;
  assign sync_n = 1'b0;
  assign blank_n = hsync & vsync;
endmodule