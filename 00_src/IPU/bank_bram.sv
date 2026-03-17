module bank_bram #(
    parameter int DATA_WIDTH = 8,
    parameter int ADDR_WIDTH = 18
)(
    input  logic                  clk,

    input  logic                  wr_en,
    input  logic [ADDR_WIDTH-1:0] wr_addr,
    input  logic [DATA_WIDTH-1:0] wr_data,

    input  logic                  rd_en,
    input  logic [ADDR_WIDTH-1:0] rd_addr,
    output logic [DATA_WIDTH-1:0] rd_data
);

    localparam int DEPTH = (1 << ADDR_WIDTH);

    (* ram_style = "block" *)
    logic [DATA_WIDTH-1:0] mem [DEPTH];

    integer k;
    initial begin
        rd_data = '0;
        for (k = 0; k < DEPTH; k = k + 1)
            mem[k] = '0;
    end

    always @(posedge clk) begin
        if (wr_en)
            mem[wr_addr] <= wr_data;

        if (rd_en)
            rd_data <= mem[rd_addr];
    end

endmodule
