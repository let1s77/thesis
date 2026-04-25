`include "soc_addr_map.vh"
`include "ipu_addr_map_soc.vh"

// =============================================================================
// Module : soc_top
// Description :
//   Top-level SoC. BRAMs nằm ở đây, ipu_core instantiate trực tiếp.
//
//   Hierarchy:
//     soc_top
//       ├── single_cycle          RISC-V + LSU
//       ├── peri_apb_wrapper      APB4 slave  0x1000_0000
//       ├── ipu_apb_wrapper       APB4 slave  0x1002_0000
//       ├── ipu_core              IPU datapath (no BRAM inside)
//       ├── img_in_bram           Port A ← single_cycle  Port B ← ipu_core
//       ├── img_out_bram          Port A ← single_cycle  Port B ← ipu_core
//       └── img_tmp_bram          Port A ← single_cycle  Port B ← ipu_core
//
//   Note: ipu_soc.sv vẫn giữ nguyên để dùng cho testbench IPU standalone.
// =============================================================================

module soc_top (
    input  logic        clk,
    input  logic        rst_n,

    // Physical I/O
    input  logic [31:0] i_io_sw,
    output logic [31:0] o_io_ledr,
    output logic [31:0] o_io_ledg,
    output logic [31:0] o_io_lcd,
    output logic [6:0]  o_io_hex0, o_io_hex1, o_io_hex2, o_io_hex3,
    output logic [6:0]  o_io_hex4, o_io_hex5, o_io_hex6, o_io_hex7,

    output logic [31:0] o_pc_debug,
    output logic        o_insn_vld,
    output logic        o_ipu_irq,

    // VGA read port for img_out_bram (Port B shared with IPU writer)
    input  logic        vga_rd_en,
    input  logic [15:0] vga_rd_addr,
    output logic [31:0] vga_rd_data
);

    // =========================================================================
    // APB4 shared bus
    // =========================================================================
    logic        PSEL_peri, PSEL_ipu;
    logic        PENABLE, PWRITE;
    logic [31:0] PADDR, PWDATA;
    logic [3:0]  PSTRB;
    logic [2:0]  PPROT;
    logic        PREADY_peri;
    logic [31:0] PRDATA_peri;
    logic        PREADY_ipu;
    logic [31:0] PRDATA_ipu;

    // =========================================================================
    // BRAM Port A wires (sys ← single_cycle)
    // =========================================================================
    logic        img_in_sys_en,  img_in_sys_we;
    logic [15:0] img_in_sys_addr;
    logic [31:0] img_in_sys_wdata, img_in_sys_rdata;

    logic        img_out_sys_en, img_out_sys_we;
    logic [15:0] img_out_sys_addr;
    logic [31:0] img_out_sys_wdata, img_out_sys_rdata;

    logic        img_tmp_sys_en, img_tmp_sys_we;
    logic [15:0] img_tmp_sys_addr;
    logic [31:0] img_tmp_sys_wdata, img_tmp_sys_rdata;

    // =========================================================================
    // BRAM Port B wires (ipu ← ipu_core)
    // =========================================================================
    logic        in_bram_en;
    logic [15:0] in_bram_addr;
    logic [31:0] in_bram_rdata;

    logic        out_bram_we;
    logic [15:0] out_bram_addr;
    logic [31:0] out_bram_wdata;

    logic        tmp_bram_en, tmp_bram_we;
    logic [15:0] tmp_bram_addr;
    logic [31:0] tmp_bram_wdata, tmp_bram_rdata;

    // =========================================================================
    // IPU register interface (ipu_apb_wrapper → ipu_core)
    // =========================================================================
    logic        reg_wr_en, reg_rd_en;
    logic [31:0] reg_addr, reg_wdata, reg_rdata;

    // =========================================================================
    // single_cycle
    // =========================================================================
    single_cycle u_single_cycle (
        .i_clk              (clk),
        .i_reset            (rst_n),
        .i_io_sw            (i_io_sw),
        .o_pc_debug         (o_pc_debug),
        .o_insn_vld         (o_insn_vld),
        // BRAM Port A
        .img_in_sys_en      (img_in_sys_en),
        .img_in_sys_we      (img_in_sys_we),
        .img_in_sys_addr    (img_in_sys_addr),
        .img_in_sys_wdata   (img_in_sys_wdata),
        .img_in_sys_rdata   (img_in_sys_rdata),
        .img_out_sys_en     (img_out_sys_en),
        .img_out_sys_we     (img_out_sys_we),
        .img_out_sys_addr   (img_out_sys_addr),
        .img_out_sys_wdata  (img_out_sys_wdata),
        .img_out_sys_rdata  (img_out_sys_rdata),
        .img_tmp_sys_en     (img_tmp_sys_en),
        .img_tmp_sys_we     (img_tmp_sys_we),
        .img_tmp_sys_addr   (img_tmp_sys_addr),
        .img_tmp_sys_wdata  (img_tmp_sys_wdata),
        .img_tmp_sys_rdata  (img_tmp_sys_rdata),
        // APB4
        .PSEL_peri          (PSEL_peri),
        .PSEL_ipu           (PSEL_ipu),
        .PENABLE            (PENABLE),
        .PWRITE             (PWRITE),
        .PADDR              (PADDR),
        .PWDATA             (PWDATA),
        .PSTRB              (PSTRB),
        .PPROT              (PPROT),
        .PREADY_peri        (PREADY_peri),
        .PRDATA_peri        (PRDATA_peri),
        .PREADY_ipu         (PREADY_ipu),
        .PRDATA_ipu         (PRDATA_ipu)
    );

    // =========================================================================
    // peri_apb_wrapper  0x1000_0000 - 0x1000_FFFF
    // =========================================================================
    peri_apb_wrapper u_peri_apb_wrapper (
        .PCLK               (clk),
        .PRESETn            (rst_n),
        .PSEL               (PSEL_peri),
        .PENABLE            (PENABLE),
        .PWRITE             (PWRITE),
        .PADDR              (PADDR),
        .PWDATA             (PWDATA),
        .PSTRB              (PSTRB),
        .PPROT              (PPROT),
        .PRDATA             (PRDATA_peri),
        .PREADY             (PREADY_peri),
        .PSLVERR            (/* unused */),
        .i_io_sw            (i_io_sw),
        .o_io_ledr          (o_io_ledr),
        .o_io_ledg          (o_io_ledg),
        .o_io_lcd           (o_io_lcd),
        .o_io_hex0          (o_io_hex0), .o_io_hex1(o_io_hex1),
        .o_io_hex2          (o_io_hex2), .o_io_hex3(o_io_hex3),
        .o_io_hex4          (o_io_hex4), .o_io_hex5(o_io_hex5),
        .o_io_hex6          (o_io_hex6), .o_io_hex7(o_io_hex7)
    );

    // =========================================================================
    // ipu_apb_wrapper  0x1002_0000 - 0x1002_0FFF
    // =========================================================================
    ipu_apb_wrapper u_ipu_apb_wrapper (
        .PCLK               (clk),
        .PRESETn            (rst_n),
        .PSEL               (PSEL_ipu),
        .PENABLE            (PENABLE),
        .PWRITE             (PWRITE),
        .PADDR              (PADDR),
        .PWDATA             (PWDATA),
        .PRDATA             (PRDATA_ipu),
        .PREADY             (PREADY_ipu),
        .PSLVERR            (/* unused */),
        .reg_wr_en          (reg_wr_en),
        .reg_rd_en          (reg_rd_en),
        .reg_addr           (reg_addr),
        .reg_wdata          (reg_wdata),
        .reg_rdata          (reg_rdata)
    );

    // =========================================================================
    // ipu_core — trực tiếp, không qua ipu_soc
    // =========================================================================
    ipu_core u_ipu_core (
        .clk                (clk),
        .rst_n              (rst_n),
        // Register interface
        .reg_wr_en          (reg_wr_en),
        .reg_rd_en          (reg_rd_en),
        .reg_addr           (reg_addr),
        .reg_wdata          (reg_wdata),
        .reg_rdata          (reg_rdata),
        // BRAM Port B
        .in_bram_en         (in_bram_en),
        .in_bram_addr       (in_bram_addr),
        .in_bram_rdata      (in_bram_rdata),
        .out_bram_we        (out_bram_we),
        .out_bram_addr      (out_bram_addr),
        .out_bram_wdata     (out_bram_wdata),
        .tmp_bram_en        (tmp_bram_en),
        .tmp_bram_we        (tmp_bram_we),
        .tmp_bram_addr      (tmp_bram_addr),
        .tmp_bram_wdata     (tmp_bram_wdata),
        .tmp_bram_rdata     (tmp_bram_rdata),
        .ipu_irq            (o_ipu_irq)
    );

    // =========================================================================
    // img_in_bram — dual-port 192KB
    // Port A: single_cycle (sys)   Port B: ipu_core (reader)
    // =========================================================================
    img_in_bram #(
        .DATA_WIDTH (32),
        .ADDR_WIDTH (16),
        .DEPTH      (`IMG_IN_BUF_DEPTH_WORD),
        .INIT_FILE  ("../../06_FGPA_Imple/images/soc_input_128.hex")
    ) u_img_in_bram (
        .clk        (clk),
        // Port A
        .sys_en     (img_in_sys_en),
        .sys_we     (img_in_sys_we),
        .sys_addr   (img_in_sys_addr),
        .sys_wdata  (img_in_sys_wdata),
        .sys_rdata  (img_in_sys_rdata),
        // Port B
        .ipu_en     (in_bram_en),
        .ipu_addr   (in_bram_addr),
        .ipu_rdata  (in_bram_rdata)
    );

    // =========================================================================
    // img_out_bram — dual-port 192KB
    // Port A: single_cycle (sys)   Port B: ipu_core (writer)
    // =========================================================================
    // Port B pipeline register: break the combinational path
    //   WRITE_ENABLE_REG → addr_mux → M10K bypass → read_data
    // by registering all Port B inputs one cycle before M10K.
    reg        img_out_b_en_r;
    reg        img_out_b_we_r;
    reg [15:0] img_out_b_addr_r;
    reg [31:0] img_out_b_wdata_r;

    always @(posedge clk) begin
        img_out_b_en_r    <= out_bram_we | vga_rd_en;
        img_out_b_we_r    <= out_bram_we;
        img_out_b_addr_r  <= out_bram_we ? out_bram_addr : vga_rd_addr;
        img_out_b_wdata_r <= out_bram_wdata;
    end

    img_out_bram #(
        .DATA_WIDTH (32),
        .ADDR_WIDTH (16),
        .DEPTH      (`IMG_OUT_BUF_DEPTH_WORD)
    ) u_img_out_bram (
        .clk        (clk),
        // Port A
        .sys_en     (img_out_sys_en),
        .sys_we     (img_out_sys_we),
        .sys_addr   (img_out_sys_addr),
        .sys_wdata  (img_out_sys_wdata),
        .sys_rdata  (img_out_sys_rdata),
        // Port B: pipelined — IPU writer + VGA reader
        .ipu_en     (img_out_b_en_r),
        .ipu_we     (img_out_b_we_r),
        .ipu_addr   (img_out_b_addr_r),
        .ipu_wdata  (img_out_b_wdata_r),
        .ipu_rdata  (vga_rd_data)
    );

    // =========================================================================
    // img_tmp_bram — dual-port 192KB
    // Port A: single_cycle (sys)   Port B: ipu_core (reserved)
    // =========================================================================
    img_tmp_bram #(
        .DATA_WIDTH (32),
        .ADDR_WIDTH (16),
        .DEPTH      (`IMG_TMP_BUF_DEPTH_WORD)
    ) u_img_tmp_bram (
        .clk        (clk),
        // Port A
        .sys_en     (img_tmp_sys_en),
        .sys_we     (img_tmp_sys_we),
        .sys_addr   (img_tmp_sys_addr),
        .sys_wdata  (img_tmp_sys_wdata),
        .sys_rdata  (img_tmp_sys_rdata),
        // Port B
        .ipu_en     (tmp_bram_en),
        .ipu_we     (tmp_bram_we),
        .ipu_addr   (tmp_bram_addr),
        .ipu_wdata  (tmp_bram_wdata),
        .ipu_rdata  (tmp_bram_rdata)
    );

endmodule