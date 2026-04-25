`timescale 1ns/10ps

module dark_channel #(
    parameter IMG_WIDTH = 512,
    parameter ENABLE_SPATIAL_FILTER = 0 
)(
    input              i_clk,
    input              i_rst_n,
    input              i_valid, 
    input       [23:0] i_color,    
    output             o_valid,
    output      [7:0]  o_dark_ch   
);

    // Stage 1: Compute min(R,G,B)
    logic [7:0] pixel_min;
    src_min u_src_min(
        .i_clk      (i_clk),
        .i_rst_n    (i_rst_n),
        .i_color    (i_color),
        .o_min_rgb  (pixel_min)
    );

    generate
        if (ENABLE_SPATIAL_FILTER == 0) begin : SIMPLE_MODE
            // Simple mode: Latency 1 cycle từ src_min
            assign o_valid   = 1'b1; 
            assign o_dark_ch = pixel_min;
            
        end else begin : EXTENDED_MODE
            (* ramstyle = "M10K, no_rw_check" *) logic [7:0] line_buf_0 [0:IMG_WIDTH-1];
            (* ramstyle = "M10K, no_rw_check" *) logic [7:0] line_buf_1 [0:IMG_WIDTH-1];
            logic [15:0] col_cnt;
            logic [7:0] row0_data, row1_data, row2_data;
            logic valid_d1, valid_d2, valid_d3, valid_d4;
            logic [7:0] p11, p12, p13, p21, p22, p23, p31, p32, p33;
            logic [7:0] block_min_out;

            // Khởi tạo memory để tránh 'x' trong mô phỏng
`ifndef SYNTHESIS
            initial begin
                for (int i=0; i<IMG_WIDTH; i++) begin
                    line_buf_0[i] = 8'd0;
                    line_buf_1[i] = 8'd0;
                end
            end
`endif

            always_ff @(posedge i_clk or negedge i_rst_n) begin
                if (!i_rst_n) begin
                    col_cnt <= 16'd0;
                    valid_d1 <= 1'b0;
                    {row0_data, row1_data, row2_data} <= 24'd0;
                end else begin
                    valid_d1 <= i_valid;
                    if (i_valid) begin
                        col_cnt <= (col_cnt == IMG_WIDTH-1) ? 16'd0 : col_cnt + 1'b1;
                        line_buf_1[col_cnt] <= line_buf_0[col_cnt];
                        line_buf_0[col_cnt] <= pixel_min;
                        row0_data <= line_buf_1[col_cnt];
                        row1_data <= line_buf_0[col_cnt];
                        row2_data <= pixel_min;
                    end
                end
            end

            // Stage 3: Shift registers
            always_ff @(posedge i_clk or negedge i_rst_n) begin
                if (!i_rst_n) begin
                    {p11, p12, p13} <= 24'd0;
                    {p21, p22, p23} <= 24'd0;
                    {p31, p32, p33} <= 24'd0;
                    valid_d2 <= 1'b0;
                end else if (valid_d1) begin
                    p11 <= p12; p12 <= p13; p13 <= row0_data;
                    p21 <= p22; p22 <= p23; p23 <= row1_data;
                    p31 <= p32; p32 <= p33; p33 <= row2_data;
                    valid_d2 <= valid_d1;
                end
            end

            search_block_min u_search_block_min(
                .i_clk(i_clk), .i_rst_n(i_rst_n),
                .i_p11(p11), .i_p12(p12), .i_p13(p13),
                .i_p21(p21), .i_p22(p22), .i_p23(p23),
                .i_p31(p31), .i_p32(p32), .i_p33(p33),
                .o_block_min(block_min_out)
            );

            always_ff @(posedge i_clk or negedge i_rst_n) begin
                if (!i_rst_n) begin
                    valid_d3 <= 1'b0;
                    valid_d4 <= 1'b0;
                end else begin
                    valid_d3 <= valid_d2;
                    valid_d4 <= valid_d3;
                end
            end

            assign o_valid   = valid_d4;
            assign o_dark_ch = block_min_out;
        end
    endgenerate
endmodule
