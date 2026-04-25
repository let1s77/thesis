`ifndef IPU_APB_WRAPPER_V
`define IPU_APB_WRAPPER_V

module ipu_apb_wrapper (
    input               PCLK,
    input               PRESETn,

    input               PSEL,
    input               PENABLE,
    input               PWRITE,
    input      [31:0]   PADDR,
    input      [31:0]   PWDATA,
    output reg [31:0]   PRDATA,
    output              PREADY,
    output              PSLVERR,

    // To IPU core register interface
    output              reg_wr_en,
    output              reg_rd_en,
    output     [31:0]   reg_addr,
    output     [31:0]   reg_wdata,
    input      [31:0]   reg_rdata
);

    // -------------------------------------------------------------
    // Simple APB transfer:
    // write: PSEL & PENABLE & PWRITE
    // read : PSEL & PENABLE & ~PWRITE
    // -------------------------------------------------------------
    assign reg_wr_en = PSEL & PENABLE &  PWRITE;
    assign reg_rd_en = PSEL & PENABLE & ~PWRITE;
    assign reg_addr  = PADDR;
    assign reg_wdata = PWDATA;

    assign PREADY  = 1'b1;   // zero wait-state
    assign PSLVERR = 1'b0;   // no error handling for now

    always @(*) begin
        PRDATA = 32'd0;
        if (PSEL && !PWRITE)
            PRDATA = reg_rdata;
    end

endmodule

`endif