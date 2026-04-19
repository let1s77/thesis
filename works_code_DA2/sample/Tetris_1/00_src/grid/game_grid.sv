module game_grid (
  input logic clk,
  input logic rst_n,

  //Port A
//Input
  input logic [9:0] H_Count_Value,
  input logic [9:0] V_Count_Value,
//Output
  output logic [8:0] q_a,

  //Port B
//Input
  input logic [8:0] data_b,
  input logic [9:0] addr_b,
  input logic rd,
  input logic wr,
//Output
  output logic [8:0] q_b
);
  logic [6:0] temp_piece_cord_x;
  logic [6:0] temp_piece_cord_y;
  logic [9:0] addr_a;
  
  grid grid_ram_u(
    .clock(clk),

    //Read only
    .address_a(addr_a),
    .data_a(9'b0),
    .rden_a(1'b1),
    .wren_a(1'b0),
    .q_a(q_a),

     //Write/Read
    .address_b(addr_b),
    .data_b(data_b),
    .rden_b(rd),
    .wren_b(wr),
    .q_b(q_b)

  );



assign temp_piece_cord_x = (((H_Count_Value/8) < 10'd42) || ((H_Count_Value/8) > 10'd74)) ? 10'b0 : ((H_Count_Value/8) - 10'd41);
assign temp_piece_cord_y = ((((V_Count_Value + 10'b1)/8) < 10'd19)||(((V_Count_Value + 10'b1)/8) > 10'd49))? 10'b0 : (((V_Count_Value + 10'b1)/8) - 10'd19);
assign addr_a = ((V_Count_Value < 10'd151)||(V_Count_Value > 10'd390)||(H_Count_Value < 10'd336)||(H_Count_Value > 10'd591)) ? 10'h0 :(10'd32*temp_piece_cord_y) + temp_piece_cord_x;

endmodule