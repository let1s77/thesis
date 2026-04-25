module grid_select (
  input logic [5:0] grid_input_sel,

  input logic [9:0] addr_1,
  input logic [9:0] addr_2,
  input logic [9:0] addr_3,
  input logic [9:0] addr_4,
  input logic [9:0] addr_5,
  input logic [9:0] addr_6,

  input logic rd_1,
  input logic rd_2,
  input logic rd_3,
  input logic rd_4,
  input logic rd_5,
  input logic rd_6,

  input logic wr_1,
  input logic wr_2,
  input logic wr_3,
  input logic wr_4,
  input logic wr_5,
  input logic wr_6,

  input logic [8:0] piece_id_wr_1,
  input logic [8:0] piece_id_wr_2,
  input logic [8:0] piece_id_wr_3,
  input logic [8:0] piece_id_wr_4,
  input logic [8:0] piece_id_wr_5,
  input logic [8:0] piece_id_wr_6,

  output logic [8:0] piece_id_wr,
  output logic [9:0] addr,
  output logic wr,
  output logic rd
);

  always_comb begin : select_input
  piece_id_wr = 9'd0;
  addr = 10'b0;
  wr = 1'b0;
  rd = 1'b0;
  case(grid_input_sel)
    6'd0:begin 
      addr = 10'b0;
      piece_id_wr = 9'd0;
      wr = 1'b0;
      rd = 1'b0;
    end
    6'd1:begin 
      addr = addr_1;
      piece_id_wr = piece_id_wr_1;
      wr = wr_1;
      rd = rd_1;
    end
    6'd2:begin
      addr = addr_2;
      piece_id_wr = piece_id_wr_2;
      wr = wr_2;
      rd = rd_2;
    end
    6'd3:begin
      addr = addr_3;
      piece_id_wr = piece_id_wr_3;
      wr = wr_3;
      rd = rd_3;
    end
    6'd4:begin
      addr = addr_4;
      piece_id_wr = piece_id_wr_4;
      wr = wr_4;
      rd = rd_4;
    end
    6'd5:begin
      addr = addr_5;
      piece_id_wr = piece_id_wr_5;
      wr = wr_5;
      rd = rd_5;
    end

    6'd6:begin
      addr = addr_6;
      piece_id_wr = piece_id_wr_6;
      wr = wr_6;
      rd = rd_6;
    end
    default: begin 
      piece_id_wr = 9'd0;
      addr = 10'b0;
    end
  endcase
end
endmodule