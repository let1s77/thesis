// =============================================================================
// Module : lsu (Load/Store Unit)
// Description :
//   Tích hợp memory map theo memory_mapping.xlsx:
//
//   0x0000_0000 - 0x0000_FFFF  : Local memory (DEPTH=16384 words, 64KB)
//   0x0001_0000 - 0x0003_FFFF  : IMG_IN_BUF  BRAM (192KB) — Port A sys
//   0x0004_0000 - 0x0006_FFFF  : IMG_OUT_BUF BRAM (192KB) — Port A sys
//   0x0007_0000 - 0x0009_FFFF  : IMG_TMP_BUF BRAM (192KB) — Port A sys
//   0x1000_0000 - 0x1000_FFFF  : Peripheral (LED/LCD/HEX/Switch) — via APB4
//   0x1001_0000 - 0x1001_0FFF  : DMA registers (reserved, not implemented)
//   0x1002_0000 - 0x1002_0FFF  : IPU Registers — via APB4
//
// Notes:
//   - Vùng BRAM (img_in/out/tmp) truy cập qua sys port (Port A),
//     địa chỉ word = (byte_addr - base) >> 2
//   - Peripheral và IPU register access qua APB4 Master (zero wait-state)
//   - RISC-V single cycle không stall — APB4 dùng PREADY=1 luôn
//   - Giữ nguyên toàn bộ logic byte-mask / misaligned của bản gốc
// =============================================================================

module lsu #(
    parameter DEPTH = 16384
)(
    input  logic        i_clk,
    input  logic        i_reset,
    input  logic        i_lsu_wren,
    input  logic [3:0]  i_byte_num,
    input  logic [31:0] i_st_data,
    input  logic [31:0] i_lsu_addr,
    input  logic [31:0] i_io_sw,
    output logic [31:0] o_ld_data,

    // -------------------------------------------------------------------------
    // Port A: IMG_IN_BUF BRAM (0x0001_0000 - 0x0003_FFFF)
    // -------------------------------------------------------------------------
    output logic        img_in_sys_en,
    output logic        img_in_sys_we,
    output logic [15:0] img_in_sys_addr,
    output logic [31:0] img_in_sys_wdata,
    input  logic [31:0] img_in_sys_rdata,

    // -------------------------------------------------------------------------
    // Port A: IMG_OUT_BUF BRAM (0x0004_0000 - 0x0006_FFFF)
    // -------------------------------------------------------------------------
    output logic        img_out_sys_en,
    output logic        img_out_sys_we,
    output logic [15:0] img_out_sys_addr,
    output logic [31:0] img_out_sys_wdata,
    input  logic [31:0] img_out_sys_rdata,

    // -------------------------------------------------------------------------
    // Port A: IMG_TMP_BUF BRAM (0x0007_0000 - 0x0009_FFFF)
    // -------------------------------------------------------------------------
    output logic        img_tmp_sys_en,
    output logic        img_tmp_sys_we,
    output logic [15:0] img_tmp_sys_addr,
    output logic [31:0] img_tmp_sys_wdata,
    input  logic [31:0] img_tmp_sys_rdata,

    // -------------------------------------------------------------------------
    // APB4 shared bus + separate slave selects
    // -------------------------------------------------------------------------
    output logic        PSEL_peri,
    output logic        PSEL_ipu,
    output logic        PENABLE,
    output logic        PWRITE,
    output logic [31:0] PADDR,
    output logic [31:0] PWDATA,
    output logic [3:0]  PSTRB,
    output logic [2:0]  PPROT,
    input  logic        PREADY_peri,
    input  logic [31:0] PRDATA_peri,
    input  logic        PREADY_ipu,
    input  logic [31:0] PRDATA_ipu
);

    // =========================================================================
    // Address decode
    // =========================================================================
    logic is_mem;       // 0x0000_0000 - 0x0000_7FFF  (local SRAM)
    logic is_img_in;    // 0x0001_0000 - 0x0003_FFFF
    logic is_img_out;   // 0x0004_0000 - 0x0006_FFFF
    logic is_img_tmp;   // 0x0007_0000 - 0x0009_FFFF
    logic is_peri;      // 0x1000_xxxx
    logic is_dma;       // 0x1001_0000 - 0x1001_0FFF (reserved)
    logic is_ipu;       // 0x1002_0xxx

    // Bit-field address decode — eliminates 32-bit comparators (saves ~3ns)
    // Each decode is 1-2 LUT levels instead of 32-bit subtractor chains.
    assign is_mem     = ~(|i_lsu_addr[31:16]);                                         // 0x0000_xxxx
    assign is_img_in  = ~(|i_lsu_addr[31:18]) & (|i_lsu_addr[17:16]);                  // 0x0001..0003_xxxx
    assign is_img_out = ~(|i_lsu_addr[31:19]) & i_lsu_addr[18] & ~(&i_lsu_addr[17:16]);// 0x0004..0006_xxxx
    assign is_img_tmp = ~(|i_lsu_addr[31:20]) &
                        ((i_lsu_addr[19:16] == 4'h7) |
                         (i_lsu_addr[19:16] == 4'h8) |
                         (i_lsu_addr[19:16] == 4'h9));                                 // 0x0007..0009_xxxx
    assign is_peri    = ~(|(i_lsu_addr[31:16] ^ 16'h1000));                             // 0x1000_xxxx
    assign is_dma     = ~(|(i_lsu_addr[31:16] ^ 16'h1001)) & ~(|i_lsu_addr[15:12]);    // 0x1001_0xxx
    assign is_ipu     = ~(|(i_lsu_addr[31:16] ^ 16'h1002)) & ~(|i_lsu_addr[15:12]);    // 0x1002_0xxx

    // =========================================================================
    // Internal signals
    // =========================================================================
    logic [3:0]  byte_mask;
    logic [31:0] mem_rdata;
    logic [31:0] mem_rdata_next;
    logic [31:0] sw_reg;
    logic [1:0]  addr_off;
    logic [31:0] rdata_shift;
    logic [31:0] wdata_shift;
    logic [63:0] mem_double;
    logic [63:0] mem_shifted;

    assign addr_off = i_lsu_addr[1:0];

    // =========================================================================
    // Local SRAM (giữ nguyên)
    // =========================================================================
    memory #(.DEPTH(DEPTH)) mem (
        .i_clk        (i_clk),
        .i_reset      (i_reset),
        .i_addr       (i_lsu_addr[$clog2(DEPTH)-1:0]),
        .i_wdata      (wdata_shift),
        .i_bmask      (byte_mask),
        .i_wren       (i_lsu_wren & is_mem),
        .o_rdata      (mem_rdata),
        .o_rdata_next (mem_rdata_next)
    );

    // =========================================================================
    // Switch register (giữ nguyên)
    // =========================================================================
    always_ff @(posedge i_clk or negedge i_reset) begin
        if (!i_reset) sw_reg <= 32'h0;
        else          sw_reg <= i_io_sw;
    end

    // =========================================================================
    // Byte mask / wdata shift (giữ nguyên hoàn toàn từ bản gốc)
    // =========================================================================
    always_comb begin
        case (i_byte_num)
            4'b0001: begin
                case (addr_off)
                    2'b00: begin wdata_shift = {24'b0, i_st_data[7:0]};        byte_mask = 4'b0001; end
                    2'b01: begin wdata_shift = {16'b0, i_st_data[7:0], 8'b0};  byte_mask = 4'b0010; end
                    2'b10: begin wdata_shift = {8'b0, i_st_data[7:0], 16'b0};  byte_mask = 4'b0100; end
                    2'b11: begin wdata_shift = {i_st_data[7:0], 24'b0};        byte_mask = 4'b1000; end
                    default: begin wdata_shift = 32'b0; byte_mask = 4'b0000; end
                endcase
            end
            4'b0011: begin
                case (addr_off)
                    2'b00: begin wdata_shift = {16'b0, i_st_data[15:0]};         byte_mask = 4'b0011; end
                    2'b01: begin wdata_shift = {8'b0, i_st_data[15:0], 8'b0};    byte_mask = 4'b0110; end
                    2'b10: begin wdata_shift = {i_st_data[15:0], 16'b0};          byte_mask = 4'b1100; end
                    2'b11: begin wdata_shift = {i_st_data[7:0], 24'b0};           byte_mask = 4'b1000; end
                    default: begin wdata_shift = 32'b0; byte_mask = 4'b0000; end
                endcase
            end
            4'b1111: begin wdata_shift = i_st_data; byte_mask = 4'b1111; end
            default: begin wdata_shift = 32'b0;     byte_mask = 4'b0000; end
        endcase
    end

    // =========================================================================
    // BRAM Port A — IMG_IN
    // =========================================================================
    assign img_in_sys_en    = is_img_in;  // always enable when selected
    assign img_in_sys_we    = is_img_in & i_lsu_wren;
    // Bit extraction replaces 32-bit subtraction: addr[15:2] is the word offset
    // within the 64KB segment (valid for DEPTH=16384). Saves one 32-bit adder.
    assign img_in_sys_addr  = {2'b00, i_lsu_addr[15:2]};
    assign img_in_sys_wdata = wdata_shift;

    // =========================================================================
    // BRAM Port A — IMG_OUT
    // =========================================================================
    assign img_out_sys_en    = is_img_out;  // always enable when selected
    assign img_out_sys_we    = is_img_out & i_lsu_wren;
    assign img_out_sys_addr  = {2'b00, i_lsu_addr[15:2]};
    assign img_out_sys_wdata = wdata_shift;

    // =========================================================================
    // BRAM Port A — IMG_TMP
    // =========================================================================
    assign img_tmp_sys_en    = is_img_tmp;  // always enable when selected
    assign img_tmp_sys_we    = is_img_tmp & i_lsu_wren;
    assign img_tmp_sys_addr  = {2'b00, i_lsu_addr[15:2]};
    assign img_tmp_sys_wdata = wdata_shift;

    // =========================================================================
    // APB4 shared bus + 2 PSEL riêng
    // =========================================================================
    assign PSEL_peri = is_peri;
    assign PSEL_ipu  = is_ipu;
    assign PENABLE   = is_peri | is_ipu;
    assign PWRITE    = (is_peri | is_ipu) & i_lsu_wren;
    assign PADDR   = i_lsu_addr;
    assign PWDATA  = wdata_shift;
    assign PSTRB   = i_lsu_wren ? byte_mask : 4'b0000;
    assign PPROT   = 3'b000;

    // =========================================================================
    // Read data mux
    // =========================================================================
    always_comb begin
        mem_shifted = 64'd0;
        rdata_shift = 32'd0;
        mem_double  = {mem_rdata_next, mem_rdata};

        if (is_mem) begin
            mem_shifted = mem_double >> (8 * addr_off);
            rdata_shift = mem_shifted[31:0];
        end else if (is_img_in) begin
            rdata_shift = img_in_sys_rdata;
        end else if (is_img_out) begin
            rdata_shift = img_out_sys_rdata;
        end else if (is_img_tmp) begin
            rdata_shift = img_tmp_sys_rdata;
        end else if (is_peri) begin
            rdata_shift = PRDATA_peri;
        end else if (is_dma) begin
            rdata_shift = 32'b0;
        end else if (is_ipu) begin
            rdata_shift = PRDATA_ipu;
        end else begin
            rdata_shift = 32'b0;
        end

        case (i_byte_num)
            4'b0001: o_ld_data = {{24{rdata_shift[7]}},  rdata_shift[7:0]};
            4'b0011: o_ld_data = {{16{rdata_shift[15]}}, rdata_shift[15:0]};
            4'b0100: o_ld_data = {24'b0,                 rdata_shift[7:0]};
            4'b0101: o_ld_data = {16'b0,                 rdata_shift[15:0]};
            4'b1111: o_ld_data = rdata_shift;
            default: o_ld_data = 32'b0;
        endcase
    end

endmodule