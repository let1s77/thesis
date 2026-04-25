`include "../soc/ipu_addr_map_soc.vh"

module ipu_soc (
    input               clk,
    input               rst_n,

    // -------------------------------------------------------------
    // Simplified register access (to be connected later by APB/AHB wrapper)
    // -------------------------------------------------------------
    input               reg_wr_en,
    input               reg_rd_en,
    input      [31:0]   reg_addr,
    input      [31:0]   reg_wdata,
    output     [31:0]   reg_rdata,

    // -------------------------------------------------------------
    // System-side access to IMG_IN BRAM  (Port A)
    // local word address inside IMG_IN buffer
    // -------------------------------------------------------------
    input               img_in_sys_en,
    input               img_in_sys_we,
    input      [15:0]   img_in_sys_addr,
    input      [31:0]   img_in_sys_wdata,
    output     [31:0]   img_in_sys_rdata,

    // -------------------------------------------------------------
    // System-side access to IMG_OUT BRAM (Port A)
    // local word address inside IMG_OUT buffer
    // -------------------------------------------------------------
    input               img_out_sys_en,
    input               img_out_sys_we,
    input      [15:0]   img_out_sys_addr,
    input      [31:0]   img_out_sys_wdata,
    output     [31:0]   img_out_sys_rdata,

    // -------------------------------------------------------------
    // System-side access to IMG_TMP BRAM (Port A)
    // local word address inside IMG_TMP buffer
    // -------------------------------------------------------------
    input               img_tmp_sys_en,
    input               img_tmp_sys_we,
    input      [15:0]   img_tmp_sys_addr,
    input      [31:0]   img_tmp_sys_wdata,
    output     [31:0]   img_tmp_sys_rdata,

    // IRQ
    output              ipu_irq
);

    // =============================================================
    // BRAM interconnect between ipu_core and external frame buffers
    // =============================================================
    wire        in_bram_en;
    wire [15:0] in_bram_addr;
    wire [31:0] in_bram_rdata;

    wire        out_bram_we;
    wire [15:0] out_bram_addr;
    wire [31:0] out_bram_wdata;

    wire        tmp_bram_en;
    wire        tmp_bram_we;
    wire [15:0] tmp_bram_addr;
    wire [31:0] tmp_bram_wdata;
    wire [31:0] tmp_bram_rdata;

    // =============================================================
    // External BRAMs at SoC top-level
    // =============================================================
    img_in_bram u_img_in_bram (
        .clk       (clk),
        .sys_en    (img_in_sys_en),
        .sys_we    (img_in_sys_we),
        .sys_addr  (img_in_sys_addr),
        .sys_wdata (img_in_sys_wdata),
        .sys_rdata (img_in_sys_rdata),
        .ipu_en    (in_bram_en),
        .ipu_addr  (in_bram_addr),
        .ipu_rdata (in_bram_rdata)
    );

    img_out_bram u_img_out_bram (
        .clk       (clk),
        .sys_en    (img_out_sys_en),
        .sys_we    (img_out_sys_we),
        .sys_addr  (img_out_sys_addr),
        .sys_wdata (img_out_sys_wdata),
        .sys_rdata (img_out_sys_rdata),
        .ipu_en    (1'b1),
        .ipu_we    (out_bram_we),
        .ipu_addr  (out_bram_addr),
        .ipu_wdata (out_bram_wdata),
        .ipu_rdata ()
    );

    img_tmp_bram u_img_tmp_bram (
        .clk       (clk),
        .sys_en    (img_tmp_sys_en),
        .sys_we    (img_tmp_sys_we),
        .sys_addr  (img_tmp_sys_addr),
        .sys_wdata (img_tmp_sys_wdata),
        .sys_rdata (img_tmp_sys_rdata),
        .ipu_en    (tmp_bram_en),
        .ipu_we    (tmp_bram_we),
        .ipu_addr  (tmp_bram_addr),
        .ipu_wdata (tmp_bram_wdata),
        .ipu_rdata (tmp_bram_rdata)
    );

    // =============================================================
    // IPU core (BRAM moved outside)
    // =============================================================
    ipu_core u_ipu_core (
        .clk           (clk),
        .rst_n         (rst_n),

        .reg_wr_en     (reg_wr_en),
        .reg_rd_en     (reg_rd_en),
        .reg_addr      (reg_addr),
        .reg_wdata     (reg_wdata),
        .reg_rdata     (reg_rdata),

        .in_bram_en    (in_bram_en),
        .in_bram_addr  (in_bram_addr),
        .in_bram_rdata (in_bram_rdata),

        .out_bram_we   (out_bram_we),
        .out_bram_addr (out_bram_addr),
        .out_bram_wdata(out_bram_wdata),

        .tmp_bram_en   (tmp_bram_en),
        .tmp_bram_we   (tmp_bram_we),
        .tmp_bram_addr (tmp_bram_addr),
        .tmp_bram_wdata(tmp_bram_wdata),
        .tmp_bram_rdata(tmp_bram_rdata),

        .ipu_irq       (ipu_irq)
    );

endmodule


// img_tmp_bram module moved to 00_src/IPU/mem/img_tmp_bram.v
// (compiled as VERILOG_FILE for reliable M10K inference)