//==============================================================================
// Module: adc_line_buffer_5x5
// Description:
//   4 line buffers + shift registers to produce a 5x5 pixel window
//   for the ADC Estimation module.
//
//   Input: streaming 8-bit MC (minimum channel) pixels, row by row.
//   Output: 5x5 window (p[0..4][0..4]) centered at (row-2, col-2)
//           + o_valid after sufficient fill.
//
// Latency: 2*IMG_WIDTH + 3 cycles (to fill 2 full rows + shift register warm-up)
//==============================================================================

module adc_line_buffer_5x5 #(
    parameter int IMG_WIDTH  = 128,
    parameter int IMG_HEIGHT = 128
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic       i_valid,
    input  logic [7:0] i_pix,

    // 5x5 window output: p[row][col], p[2][2] = center
    output logic [7:0] p00, p01, p02, p03, p04,
    output logic [7:0] p10, p11, p12, p13, p14,
    output logic [7:0] p20, p21, p22, p23, p24,
    output logic [7:0] p30, p31, p32, p33, p34,
    output logic [7:0] p40, p41, p42, p43, p44,

    output logic       o_valid
);

    // ----------------------------------------------------------------
    // 4 line buffers (row 0 = oldest, row 4 = newest = i_pix)
    // ----------------------------------------------------------------
    (* ramstyle = "M10K, no_rw_check" *) logic [7:0] line_buf_0 [0:IMG_WIDTH-1]; // oldest row (row 0)
    (* ramstyle = "M10K, no_rw_check" *) logic [7:0] line_buf_1 [0:IMG_WIDTH-1]; // row 1
    (* ramstyle = "M10K, no_rw_check" *) logic [7:0] line_buf_2 [0:IMG_WIDTH-1]; // row 2
    (* ramstyle = "M10K, no_rw_check" *) logic [7:0] line_buf_3 [0:IMG_WIDTH-1]; // row 3
    // row 4 = incoming pixel (i_pix)

    // Column counter
    logic [$clog2(IMG_WIDTH)-1:0] col_cnt;

    // Valid pipeline (need at least 2 columns of shift register fill + 4 row delay)
    logic       valid_d1, valid_d2, valid_d3;

    // Pixel counter for global valid tracking
    logic [$clog2(IMG_WIDTH*IMG_HEIGHT+1)-1:0] pix_count;
    localparam int VALID_THRESHOLD = 4 * IMG_WIDTH + 4; // 4 full rows + 4 cols warm-up

    // Init memory for simulation
`ifndef SYNTHESIS
    initial begin
        for (int i = 0; i < IMG_WIDTH; i++) begin
            line_buf_0[i] = 8'd0;
            line_buf_1[i] = 8'd0;
            line_buf_2[i] = 8'd0;
            line_buf_3[i] = 8'd0;
        end
    end
`endif

    // ----------------------------------------------------------------
    // Line buffer shift + column counter
    // ----------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            col_cnt   <= '0;
        end else if (i_valid) begin
            // Cascade shift: buf0 <- buf1 <- buf2 <- buf3 <- i_pix
            line_buf_0[col_cnt] <= line_buf_1[col_cnt];
            line_buf_1[col_cnt] <= line_buf_2[col_cnt];
            line_buf_2[col_cnt] <= line_buf_3[col_cnt];
            line_buf_3[col_cnt] <= i_pix;

            // Column counter
            if (col_cnt == IMG_WIDTH - 1)
                col_cnt <= '0;
            else
                col_cnt <= col_cnt + 1'b1;
        end
    end

    // ----------------------------------------------------------------
    // 5x5 shift registers (5 rows x 5 columns)
    // ----------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            {p00, p01, p02, p03, p04} <= '0;
            {p10, p11, p12, p13, p14} <= '0;
            {p20, p21, p22, p23, p24} <= '0;
            {p30, p31, p32, p33, p34} <= '0;
            {p40, p41, p42, p43, p44} <= '0;
            valid_d1 <= 1'b0;
        end else if (i_valid) begin
            // Row 0 shift
            p00 <= p01; p01 <= p02; p02 <= p03; p03 <= p04; p04 <= line_buf_0[col_cnt];
            // Row 1 shift
            p10 <= p11; p11 <= p12; p12 <= p13; p13 <= p14; p14 <= line_buf_1[col_cnt];
            // Row 2 shift
            p20 <= p21; p21 <= p22; p22 <= p23; p23 <= p24; p24 <= line_buf_2[col_cnt];
            // Row 3 shift
            p30 <= p31; p31 <= p32; p32 <= p33; p33 <= p34; p34 <= line_buf_3[col_cnt];
            // Row 4 shift
            p40 <= p41; p41 <= p42; p42 <= p43; p43 <= p44; p44 <= i_pix;

            valid_d1 <= 1'b1;
        end else begin
            valid_d1 <= 1'b0;
        end
    end

    // ----------------------------------------------------------------
    // Valid tracking: window is valid after enough pixels received
    // ----------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pix_count <= '0;
        end else if (i_valid) begin
            if (pix_count < (IMG_WIDTH * IMG_HEIGHT))
                pix_count <= pix_count + 1;
        end
    end

    assign o_valid = valid_d1 && (pix_count > VALID_THRESHOLD);

endmodule
