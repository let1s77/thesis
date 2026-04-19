// =============================================================================
// Module : peri_apb_wrapper
// Description :
//   APB4 slave wrapper cho peripherals module.
//   Bridge APB4 signals → peripheral interface.
//
//   Address range : 0x1000_0000 - 0x1000_FFFF
//   Peripheral map (từ peripherals.sv):
//     0x1000_0xxx → LED_RED
//     0x1000_1xxx → LED_GREEN
//     0x1000_2xxx → HEX3~0
//     0x1000_3xxx → HEX7~4
//     0x1000_4xxx → LCD
//
//   APB4 timing: zero wait-state (PREADY = 1 luôn)
//   Write: PSEL & PENABLE & PWRITE  → i_write_en = 1
//   Read : PSEL & PENABLE & ~PWRITE → o_data_out → PRDATA
// =============================================================================

module peri_apb_wrapper (
    input  logic        PCLK,
    input  logic        PRESETn,

    // APB4 slave interface
    input  logic        PSEL,
    input  logic        PENABLE,
    input  logic        PWRITE,
    input  logic [31:0] PADDR,
    input  logic [31:0] PWDATA,
    input  logic [3:0]  PSTRB,
    input  logic [2:0]  PPROT,
    output logic [31:0] PRDATA,
    output logic        PREADY,
    output logic        PSLVERR,

    // Physical I/O — kết nối thẳng ra top-level pins
    input  logic [31:0] i_io_sw,
    output logic [31:0] o_io_ledr,
    output logic [31:0] o_io_ledg,
    output logic [31:0] o_io_lcd,
    output logic [6:0]  o_io_hex0,
    output logic [6:0]  o_io_hex1,
    output logic [6:0]  o_io_hex2,
    output logic [6:0]  o_io_hex3,
    output logic [6:0]  o_io_hex4,
    output logic [6:0]  o_io_hex5,
    output logic [6:0]  o_io_hex6,
    output logic [6:0]  o_io_hex7
);

    // =========================================================================
    // APB4 decode
    // =========================================================================
    logic        peri_write_en;
    logic [31:0] peri_rdata;

    // Write: access phase (PSEL & PENABLE & PWRITE)
    assign peri_write_en = PSEL & PENABLE & PWRITE;

    // Zero wait-state
    assign PREADY  = 1'b1;
    assign PSLVERR = 1'b0;

    // PRDATA: combinational read
    assign PRDATA = (PSEL && !PWRITE) ? peri_rdata : 32'h0;

    // =========================================================================
    // Peripheral instance
    // =========================================================================
    peripherals u_peripherals (
        .i_clk       (PCLK),
        .i_reset     (PRESETn),
        .i_peri_addr (PADDR[15:0]),   // dùng 16-bit thấp của PADDR
        .i_data_in   (PWDATA),
        .i_write_en  (peri_write_en),
        .i_io_sw     (i_io_sw),
        .o_data_out  (peri_rdata),
        .o_io_ledr   (o_io_ledr),
        .o_io_ledg   (o_io_ledg),
        .o_io_lcd    (o_io_lcd),
        .o_io_hex0   (o_io_hex0),
        .o_io_hex1   (o_io_hex1),
        .o_io_hex2   (o_io_hex2),
        .o_io_hex3   (o_io_hex3),
        .o_io_hex4   (o_io_hex4),
        .o_io_hex5   (o_io_hex5),
        .o_io_hex6   (o_io_hex6),
        .o_io_hex7   (o_io_hex7)
    );

endmodule
