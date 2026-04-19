module bank_pingpong_stream #(
    parameter int DATA_WIDTH = 8,
    parameter int IMG_WIDTH  = 512,
    parameter int IMG_HEIGHT = 512,
    parameter int ADDR_WIDTH = 18
)(
    input  logic                  clk,
    input  logic                  rst_n,

    // swap bank sau mỗi frame / phase
    input  logic                  i_swap,

    // -----------------------------
    // Write stream side
    // -----------------------------
    input  logic                  i_wr_clear,   // clear counter write
    input  logic                  i_wr_valid,
    input  logic [DATA_WIDTH-1:0] i_wr_data,

    // -----------------------------
    // Read stream side
    // -----------------------------
    input  logic                  i_rd_clear,   // clear counter read
    input  logic                  i_rd_en,
    output logic [DATA_WIDTH-1:0] o_rd_data,

    // -----------------------------
    // Read-side position info
    // dùng cho ADC estimation
    // -----------------------------
    output logic [ADDR_WIDTH-1:0] o_rd_addr,
    output logic [$clog2(IMG_HEIGHT)-1:0] o_rd_row,
    output logic [$clog2(IMG_WIDTH)-1:0]  o_rd_col,
    output logic                  o_at_top,
    output logic                  o_at_bottom,
    output logic                  o_at_left,
    output logic                  o_at_right,

    // debug
    output logic                  o_wr_bank_sel,
    output logic                  o_rd_bank_sel
);

    // ============================================================
    // Bank select
    // bank_sel = 0:
    //   BANK1 write
    //   BANK2 read
    // bank_sel = 1:
    //   BANK2 write
    //   BANK1 read
    // ============================================================
    logic bank_sel;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            bank_sel <= 1'b0;
        else if (i_swap)
            bank_sel <= ~bank_sel;
    end

    assign o_wr_bank_sel = bank_sel;
    assign o_rd_bank_sel = ~bank_sel;

    // ============================================================
    // Write counter
    // ============================================================
    logic [ADDR_WIDTH-1:0] wr_addr;
    logic [$clog2(IMG_HEIGHT)-1:0] wr_row_unused;
    logic [$clog2(IMG_WIDTH)-1:0]  wr_col_unused;
    logic wr_top_unused, wr_bottom_unused, wr_left_unused, wr_right_unused;

    frame_linear_counter #(
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_wr_counter (
        .clk        (clk),
        .rst_n      (rst_n),
        .i_clear    (i_wr_clear),
        .i_en       (i_wr_valid),
        .o_addr     (wr_addr),
        .o_row      (wr_row_unused),
        .o_col      (wr_col_unused),
        .o_at_top   (wr_top_unused),
        .o_at_bottom(wr_bottom_unused),
        .o_at_left  (wr_left_unused),
        .o_at_right (wr_right_unused)
    );

    // ============================================================
    // Read counter
    // ============================================================
    logic [ADDR_WIDTH-1:0] rd_addr;
    logic [$clog2(IMG_HEIGHT)-1:0] rd_row;
    logic [$clog2(IMG_WIDTH)-1:0]  rd_col;
    logic rd_top, rd_bottom, rd_left, rd_right;

    frame_linear_counter #(
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_rd_counter (
        .clk        (clk),
        .rst_n      (rst_n),
        .i_clear    (i_rd_clear),
        .i_en       (i_rd_en),
        .o_addr     (rd_addr),
        .o_row      (rd_row),
        .o_col      (rd_col),
        .o_at_top   (rd_top),
        .o_at_bottom(rd_bottom),
        .o_at_left  (rd_left),
        .o_at_right (rd_right)
    );

    assign o_rd_addr   = rd_addr;
    assign o_rd_row    = rd_row;
    assign o_rd_col    = rd_col;
    assign o_at_top    = rd_top;
    assign o_at_bottom = rd_bottom;
    assign o_at_left   = rd_left;
    assign o_at_right  = rd_right;

    // ============================================================
    // BRAM banks
    // ============================================================
    logic wr_en_b0, wr_en_b1;
    logic rd_en_b0, rd_en_b1;

    logic [DATA_WIDTH-1:0] rd_data_b0, rd_data_b1;

    assign wr_en_b0 = (bank_sel == 1'b0) ? i_wr_valid : 1'b0;
    assign wr_en_b1 = (bank_sel == 1'b1) ? i_wr_valid : 1'b0;

    assign rd_en_b0 = (bank_sel == 1'b1) ? i_rd_en : 1'b0;
    assign rd_en_b1 = (bank_sel == 1'b0) ? i_rd_en : 1'b0;

    bank_bram #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_bank1 (
        .clk    (clk),
        .wr_en  (wr_en_b0),
        .wr_addr(wr_addr),
        .wr_data(i_wr_data),
        .rd_en  (rd_en_b0),
        .rd_addr(rd_addr),
        .rd_data(rd_data_b0)
    );

    bank_bram #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_bank2 (
        .clk    (clk),
        .wr_en  (wr_en_b1),
        .wr_addr(wr_addr),
        .wr_data(i_wr_data),
        .rd_en  (rd_en_b1),
        .rd_addr(rd_addr),
        .rd_data(rd_data_b1)
    );

    always_comb begin
        if (bank_sel == 1'b0)
            o_rd_data = rd_data_b1;
        else
            o_rd_data = rd_data_b0;
    end

endmodule