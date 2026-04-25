module vga_line_buffer (
  input logic         clk,
  input logic         rst_n,

  input logic  [9:0] current_H_Count_Value,
  input logic  [9:0] current_V_Count_Value,

  input logic  [3:0]  wr_data_red,
  input logic  [3:0]  wr_data_green,
  input logic  [3:0]  wr_data_blue,

  output logic [3:0]  rd_data_red,
  output logic [3:0]  rd_data_green,
  output logic [3:0]  rd_data_blue
);


logic [3:0] rd_data_red_odd;
logic [3:0] rd_data_green_odd;
logic [3:0] rd_data_blue_odd;

logic [3:0] rd_data_red_even;
logic [3:0] rd_data_green_even;
logic [3:0] rd_data_blue_even;

logic sel;

//640 x 4 bit rom (each 4-bit is 1 color)
buffer_ram buffer_ram_u_red_odd(
  .aclr(~rst_n),
  .rdaddress(current_H_Count_Value),
  .rden(sel),
  .clock(clk),
  .data(wr_data_red),
  .wraddress(current_H_Count_Value),
  .wren(~sel),

  .q(rd_data_red_odd)
);

buffer_ram buffer_ram_u_green_odd(
  .aclr(~rst_n),
  .rdaddress(current_H_Count_Value),
  .rden(sel),
  .clock(clk),
  .data(wr_data_green),
  .wraddress(current_H_Count_Value),
  .wren(~sel),

  .q(rd_data_green_odd)
);

buffer_ram buffer_ram_u_blue_odd(
  .aclr(~rst_n),
  .rdaddress(current_H_Count_Value),
  .rden(sel),
  .clock(clk),
  .data(wr_data_blue),
  .wraddress(current_H_Count_Value),
  .wren(~sel),

  .q(rd_data_blue_odd)
);

buffer_ram buffer_ram_u_red_even(
  .aclr(~rst_n),
  .rdaddress(current_H_Count_Value),
  .rden(~sel),
  .clock(clk),
  .data(wr_data_red),
  .wraddress(current_H_Count_Value),
  .wren(sel),

  .q(rd_data_red_even)
);

buffer_ram buffer_ram_u_green_even(
  .aclr(~rst_n),
  .rdaddress(current_H_Count_Value),
  .rden(~sel),
  .clock(clk),
  .data(wr_data_green),
  .wraddress(current_H_Count_Value),
  .wren(sel),

  .q(rd_data_green_even)
);

buffer_ram buffer_ram_u_blue_even(
  .aclr(~rst_n),
  .rdaddress(current_H_Count_Value),
  .rden(~sel),
  .clock(clk),
  .data(wr_data_blue),
  .wraddress(current_H_Count_Value),
  .wren(sel),

  .q(rd_data_blue_even)
);

// Calculate logic for output (Which line will be display and which will be shift into)
assign sel = current_V_Count_Value[0];

assign rd_data_red = sel ? rd_data_red_odd : rd_data_red_even;
assign rd_data_blue = sel ? rd_data_blue_odd : rd_data_blue_even;
assign rd_data_green = sel ? rd_data_green_odd : rd_data_green_even;

endmodule