module frame_linear_counter #(
    parameter int IMG_WIDTH  = 512,
    parameter int IMG_HEIGHT = 512,
    parameter int ADDR_WIDTH = 18
)(
    input  logic                  clk,
    input  logic                  rst_n,

    input  logic                  i_clear,
    input  logic                  i_en,

    output logic [ADDR_WIDTH-1:0] o_addr,
    output logic [$clog2(IMG_HEIGHT)-1:0] o_row,
    output logic [$clog2(IMG_WIDTH)-1:0]  o_col,

    output logic                  o_at_top,
    output logic                  o_at_bottom,
    output logic                  o_at_left,
    output logic                  o_at_right
);

    logic [$clog2(IMG_HEIGHT)-1:0] row_r;
    logic [$clog2(IMG_WIDTH)-1:0]  col_r;
    logic [ADDR_WIDTH-1:0]         addr_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row_r  <= '0;
            col_r  <= '0;
            addr_r <= '0;
        end
        else if (i_clear) begin
            row_r  <= '0;
            col_r  <= '0;
            addr_r <= '0;
        end
        else if (i_en) begin
            if ((row_r == IMG_HEIGHT-1) && (col_r == IMG_WIDTH-1))
                addr_r <= '0;
            else
                addr_r <= addr_r + 1'b1;

            if (col_r == IMG_WIDTH-1) begin
                col_r <= '0;
                if (row_r == IMG_HEIGHT-1)
                    row_r <= '0;
                else
                    row_r <= row_r + 1'b1;
            end
            else begin
                col_r <= col_r + 1'b1;
            end
        end
    end

    always_comb begin
        o_addr      = addr_r;
        o_row       = row_r;
        o_col       = col_r;

        o_at_top    = (row_r == 0);
        o_at_bottom = (row_r == IMG_HEIGHT-1);
        o_at_left   = (col_r == 0);
        o_at_right  = (col_r == IMG_WIDTH-1);
    end

endmodule