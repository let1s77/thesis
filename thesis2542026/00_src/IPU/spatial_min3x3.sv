// spatial_min3x3.sv
// Stream 3x3 min filter for 8-bit pixel stream using line buffers + search_block_min.
// Includes valid + sky alignment (4-cycle delay chain like dark_channel style).
// No function/task.

module spatial_min3x3 #(
  parameter int IMG_WIDTH = 512
)(
  input  logic       clk,
  input  logic       rst_n,
  input  logic       i_valid,
  input  logic [7:0] i_pix,
  input  logic       i_sky,

  output logic       o_valid,
  output logic [7:0] o_pix_min,
  output logic       o_sky
);

  (* ramstyle = "M10K, no_rw_check" *) logic [7:0] line_buf_0 [0:IMG_WIDTH-1];
  (* ramstyle = "M10K, no_rw_check" *) logic [7:0] line_buf_1 [0:IMG_WIDTH-1];

  logic [15:0] col_cnt;
  logic [7:0]  row0_data, row1_data, row2_data;

  // init memory to avoid 'x' in simulation (synthesis will ignore)
`ifndef SYNTHESIS
  initial begin
    for (int i=0; i<IMG_WIDTH; i++) begin
      line_buf_0[i] = 8'd0;
      line_buf_1[i] = 8'd0;
    end
  end
`endif

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      col_cnt   <= 16'd0;
      row0_data <= 8'd0;
      row1_data <= 8'd0;
      row2_data <= 8'd0;
    end else if (i_valid) begin
      row0_data <= line_buf_1[col_cnt];
      row1_data <= line_buf_0[col_cnt];
      row2_data <= i_pix;

      line_buf_1[col_cnt] <= line_buf_0[col_cnt];
      line_buf_0[col_cnt] <= i_pix;

      if (col_cnt == IMG_WIDTH-1) col_cnt <= 16'd0;
      else                        col_cnt <= col_cnt + 16'd1;
    end
  end

  // shift regs to form 3x3 window
  logic [7:0] p11, p12, p13;
  logic [7:0] p21, p22, p23;
  logic [7:0] p31, p32, p33;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      p11<=0; p12<=0; p13<=0;
      p21<=0; p22<=0; p23<=0;
      p31<=0; p32<=0; p33<=0;
    end else if (i_valid) begin
      p11 <= p12;   p12 <= p13;   p13 <= row0_data;
      p21 <= p22;   p22 <= p23;   p23 <= row1_data;
      p31 <= p32;   p32 <= p33;   p33 <= row2_data;
    end
  end

  // 3x3 min (pipelined inside search_block_min)
  search_block_min u_search_block_min (
    .i_clk      (clk),
    .i_rst_n    (rst_n),
    .i_p11      (p11), .i_p12(p12), .i_p13(p13),
    .i_p21      (p21), .i_p22(p22), .i_p23(p23),
    .i_p31      (p31), .i_p32(p32), .i_p33(p33),
    .o_block_min(o_pix_min)
  );

  // Align valid + sky (match style used in estimate_transmission_optimized)
  logic v_d1, v_d2, v_d3, v_d4;
  logic s_d1, s_d2, s_d3, s_d4;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      v_d1 <= 1'b0; v_d2 <= 1'b0; v_d3 <= 1'b0; v_d4 <= 1'b0;
      s_d1 <= 1'b0; s_d2 <= 1'b0; s_d3 <= 1'b0; s_d4 <= 1'b0;
    end else begin
      v_d1 <= i_valid;
      v_d2 <= v_d1;
      v_d3 <= v_d2;
      v_d4 <= v_d3;

      s_d1 <= i_sky;
      s_d2 <= s_d1;
      s_d3 <= s_d2;
      s_d4 <= s_d3;
    end
  end

  assign o_valid = v_d4;
  assign o_sky   = s_d4;

endmodule
