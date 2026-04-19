//=============================================================================
// Module : wrapper
// Description :
//   Top-level wrapper for the DE10-Standard FPGA board.
//   Maps board pins to the current soc_top hierarchy for synthesis.
//=============================================================================

module wrapper (
  input         CLOCK_50,
  input  [17:0] SW,
  input  [ 3:0] KEY,
  output [31:0] PC_debug,
  output [ 6:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5, HEX6, HEX7,
  output [17:0] LEDR,
  output [ 8:0] LEDG,
  output [ 7:0] LCD_DATA,
  output        LCD_RW,
  output        LCD_EN,
  output        LCD_RS,
  output        LCD_ON,
  output        LCD_BLON,
  // VGA DAC (ADV7123)
  output [ 7:0] VGA_R,
  output [ 7:0] VGA_G,
  output [ 7:0] VGA_B,
  output        VGA_CLK,
  output        VGA_HS,
  output        VGA_VS,
  output        VGA_BLANK_N,
  output        VGA_SYNC_N
);

  logic [1:0]  rst_sync_ff;
  logic        rst_n;

  logic [31:0] i_io_sw;
  logic [31:0] o_io_ledr;
  logic [31:0] o_io_ledg;
  logic [31:0] o_io_lcd;
  logic [31:0] o_pc_debug;

  logic [6:0]  o_io_hex0;
  logic [6:0]  o_io_hex1;
  logic [6:0]  o_io_hex2;
  logic [6:0]  o_io_hex3;
  logic [6:0]  o_io_hex4;
  logic [6:0]  o_io_hex5;
  logic [6:0]  o_io_hex6;
  logic [6:0]  o_io_hex7;

  // KEY[0] is active-low reset on the DE10 board.
  // Use async assert and sync release before feeding the SoC reset.
  always_ff @(posedge CLOCK_50 or negedge KEY[0]) begin
    if (!KEY[0]) begin
      rst_sync_ff <= 2'b00;
    end else begin
      rst_sync_ff <= {rst_sync_ff[0], 1'b1};
    end
  end

  assign rst_n   = rst_sync_ff[1];
  assign i_io_sw = {14'd0, SW};

  assign PC_debug = o_pc_debug;
  assign LEDR     = o_io_ledr[17:0];
  assign LEDG     = o_io_ledg[8:0];
  assign {LCD_EN, LCD_RS, LCD_RW, LCD_DATA} = o_io_lcd[10:0];
  assign LCD_ON   = 1'b1;
  assign LCD_BLON = 1'b1;

  assign HEX0 = o_io_hex0;
  assign HEX1 = o_io_hex1;
  assign HEX2 = o_io_hex2;
  assign HEX3 = o_io_hex3;
  assign HEX4 = o_io_hex4;
  assign HEX5 = o_io_hex5;
  assign HEX6 = o_io_hex6;
  assign HEX7 = o_io_hex7;

  soc_top u_soc_top (
    .clk        (CLOCK_50),
    .rst_n      (rst_n),
    .i_io_sw    (i_io_sw),
    .o_io_ledr  (o_io_ledr),
    .o_io_ledg  (o_io_ledg),
    .o_io_lcd   (o_io_lcd),
    .o_io_hex0  (o_io_hex0),
    .o_io_hex1  (o_io_hex1),
    .o_io_hex2  (o_io_hex2),
    .o_io_hex3  (o_io_hex3),
    .o_io_hex4  (o_io_hex4),
    .o_io_hex5  (o_io_hex5),
    .o_io_hex6  (o_io_hex6),
    .o_io_hex7  (o_io_hex7),
    .o_pc_debug (o_pc_debug),
    .o_insn_vld ( ),
    .o_ipu_irq  ( ),
    // VGA read port
    .vga_rd_en   (vga_rd_en),
    .vga_rd_addr (vga_rd_addr),
    .vga_rd_data (vga_rd_data)
  );

  // =========================================================================
  // VGA controller — reads img_out_bram via soc_top VGA port
  // =========================================================================
  logic        vga_rd_en;
  logic [15:0] vga_rd_addr;
  logic [31:0] vga_rd_data;

  wire  [9:0]  vga_h_count;
  wire  [9:0]  vga_v_count;

  // Image centering constants (must match vga_controller localparams)
  localparam int IMG_WIDTH     = 128;
  localparam int IMG_HEIGHT    = 128;
  localparam int H_SYNC        = 96;
  localparam int H_BP          = 48;
  localparam int H_ACTIVE_START = H_SYNC + H_BP;         // 144
  localparam int V_SYNC        = 2;
  localparam int V_BP          = 33;
  localparam int V_ACTIVE_START = V_SYNC + V_BP;          // 35
  localparam int IMG_X_START   = (640 - IMG_WIDTH)  / 2;  // 256
  localparam int IMG_Y_START   = (480 - IMG_HEIGHT) / 2;  // 176

  // Pixel position within image (valid when inside image window)
  wire [9:0] pixel_x = vga_h_count - (H_ACTIVE_START + IMG_X_START);
  wire [9:0] pixel_y = vga_v_count - (V_ACTIVE_START + IMG_Y_START);

  // BRAM address: row * 128 + col = {row[6:0], col[6:0]}
  always_comb begin
    vga_rd_addr = {2'b00, pixel_y[6:0], pixel_x[6:0]};
    vga_rd_en   = 1'b1;  // always read — BRAM output holds when outside window
  end

  // Extract RGB from 32-bit BRAM word: {pad, B[7:0], G[7:0], R[7:0]}
  // Feed upper 4 bits of each channel to VGA controller
  wire [3:0] vga_pixel_r = vga_rd_data[7:4];
  wire [3:0] vga_pixel_g = vga_rd_data[15:12];
  wire [3:0] vga_pixel_b = vga_rd_data[23:20];

  vga_controller #(
    .IMG_WIDTH  (IMG_WIDTH),
    .IMG_HEIGHT (IMG_HEIGHT)
  ) u_vga_controller (
    .clk           (CLOCK_50),
    .rst_n         (rst_n),
    .pixel_red     (vga_pixel_r),
    .pixel_green   (vga_pixel_g),
    .pixel_blue    (vga_pixel_b),
    .hsync         (VGA_HS),
    .vsync         (VGA_VS),
    .blank_n       (VGA_BLANK_N),
    .sync_n        (VGA_SYNC_N),
    .red           (VGA_R),
    .green         (VGA_G),
    .blue          (VGA_B),
    .vga_clk       (VGA_CLK),
    .H_Count_Value (vga_h_count),
    .V_Count_Value (vga_v_count)
  );

endmodule
