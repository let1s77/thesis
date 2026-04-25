// This module is a VGA controller only for DE-Series kit by Altera
module vga_controller #(
  parameter int IMG_WIDTH  = 128,
  parameter int IMG_HEIGHT = 128
) (
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
  output wire         vga_clk,
  output logic [9:0] H_Count_Value,
  output logic [9:0] V_Count_Value
);
  localparam int H_VISIBLE = 640;
  localparam int H_FP      = 16;
  localparam int H_SYNC    = 96;
  localparam int H_BP      = 48;
  localparam int H_TOTAL   = H_VISIBLE + H_FP + H_SYNC + H_BP;

  localparam int V_VISIBLE = 480;
  localparam int V_FP      = 10;
  localparam int V_SYNC    = 2;
  localparam int V_BP      = 33;
  localparam int V_TOTAL   = V_VISIBLE + V_FP + V_SYNC + V_BP;

  localparam int H_ACTIVE_START = H_SYNC + H_BP;
  localparam int H_ACTIVE_END   = H_ACTIVE_START + H_VISIBLE - 1;
  localparam int V_ACTIVE_START = V_SYNC + V_BP;
  localparam int V_ACTIVE_END   = V_ACTIVE_START + V_VISIBLE - 1;

  localparam int IMG_X_START = (H_VISIBLE - IMG_WIDTH) / 2;
  localparam int IMG_X_END   = IMG_X_START + IMG_WIDTH - 1;
  localparam int IMG_Y_START = (V_VISIBLE - IMG_HEIGHT) / 2;
  localparam int IMG_Y_END   = IMG_Y_START + IMG_HEIGHT - 1;

  logic       enable_V_Counter;
  logic       active_video;
  logic       image_window;
  logic [9:0] active_x;
  logic [9:0] active_y;
  logic       pll_locked;

  // PLL: 50 MHz → 25 MHz pixel clock (dedicated PLL block)
  vga_pll pll_u (
      .areset (~rst_n),
      .inclk0 (clk),
      .c0     (vga_clk),
      .locked (pll_locked)
  );
  
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

  assign hsync = (H_Count_Value < H_SYNC) ? 1'b0 : 1'b1;
  assign vsync = (V_Count_Value < V_SYNC) ? 1'b0 : 1'b1;

  assign active_video = (H_Count_Value >= H_ACTIVE_START) && (H_Count_Value <= H_ACTIVE_END) &&
                        (V_Count_Value >= V_ACTIVE_START) && (V_Count_Value <= V_ACTIVE_END);

  assign active_x = H_Count_Value - H_ACTIVE_START;
  assign active_y = V_Count_Value - V_ACTIVE_START;

  // Center 128x128 image in 640x480 active area with 1:1 mapping.
  assign image_window = active_video &&
                        (active_x >= IMG_X_START) && (active_x <= IMG_X_END) &&
                        (active_y >= IMG_Y_START) && (active_y <= IMG_Y_END);

  assign red   = image_window ? {pixel_red,   pixel_red}   : 8'h00;
  assign green = image_window ? {pixel_green, pixel_green} : 8'h00;
  assign blue  = image_window ? {pixel_blue,  pixel_blue}  : 8'h00;
  assign sync_n = 1'b0;
  assign blank_n = active_video;
endmodule