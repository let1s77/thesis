`timescale 1ns / 1ns

module single_cycle_tb;

    localparam int BRAM_WORDS = 49152; // 192KB / 4
    localparam int APB_WORDS  = 1024;  // 4KB / 4 (IPU register stub)

    logic i_clk;
    logic i_reset;
    logic [31:0] i_io_sw;
    logic [31:0] o_pc_debug;
    logic        o_insn_vld;

    // BRAM Port-A model wires
    logic        img_in_sys_en;
    logic        img_in_sys_we;
    logic [15:0] img_in_sys_addr;
    logic [31:0] img_in_sys_wdata;
    logic [31:0] img_in_sys_rdata;

    logic        img_out_sys_en;
    logic        img_out_sys_we;
    logic [15:0] img_out_sys_addr;
    logic [31:0] img_out_sys_wdata;
    logic [31:0] img_out_sys_rdata;

    logic        img_tmp_sys_en;
    logic        img_tmp_sys_we;
    logic [15:0] img_tmp_sys_addr;
    logic [31:0] img_tmp_sys_wdata;
    logic [31:0] img_tmp_sys_rdata;

    // APB4 shared bus wires + separate PSEL outputs from LSU
    logic        PSEL_peri;
    logic        PSEL_ipu;
    logic        PENABLE;
    logic        PWRITE;
    logic [31:0] PADDR;
    logic [31:0] PWDATA;
    logic [3:0]  PSTRB;
    logic [2:0]  PPROT;
    logic        PREADY_peri;
    logic [31:0] PRDATA_peri;
    logic        PREADY_ipu;
    logic [31:0] PRDATA_ipu;

    // External peripheral outputs (for visibility / ISA character output)
    logic [31:0] peri_io_ledr;
    logic [31:0] peri_io_ledg;
    logic [31:0] peri_io_lcd;
    logic [6:0]  peri_io_hex0, peri_io_hex1, peri_io_hex2, peri_io_hex3;
    logic [6:0]  peri_io_hex4, peri_io_hex5, peri_io_hex6, peri_io_hex7;

    logic [31:0] img_in_mem  [0:BRAM_WORDS-1];
    logic [31:0] img_out_mem [0:BRAM_WORDS-1];
    logic [31:0] img_tmp_mem [0:BRAM_WORDS-1];
    logic [31:0] apb_regs    [0:APB_WORDS-1];
    logic [31:0] cycle_cnt;
    integer idx;

    task automatic log_start(input string test_name);
    begin
        $display("<at time %0t ns> [START] %s", $time, test_name);
    end
    endtask

    single_cycle dut (
        .i_clk(i_clk),
        .i_reset(i_reset),
        .i_io_sw(i_io_sw),
        .o_pc_debug(o_pc_debug),
        .o_insn_vld(o_insn_vld),

        .img_in_sys_en(img_in_sys_en),
        .img_in_sys_we(img_in_sys_we),
        .img_in_sys_addr(img_in_sys_addr),
        .img_in_sys_wdata(img_in_sys_wdata),
        .img_in_sys_rdata(img_in_sys_rdata),

        .img_out_sys_en(img_out_sys_en),
        .img_out_sys_we(img_out_sys_we),
        .img_out_sys_addr(img_out_sys_addr),
        .img_out_sys_wdata(img_out_sys_wdata),
        .img_out_sys_rdata(img_out_sys_rdata),

        .img_tmp_sys_en(img_tmp_sys_en),
        .img_tmp_sys_we(img_tmp_sys_we),
        .img_tmp_sys_addr(img_tmp_sys_addr),
        .img_tmp_sys_wdata(img_tmp_sys_wdata),
        .img_tmp_sys_rdata(img_tmp_sys_rdata),

        .PSEL_peri(PSEL_peri),
        .PSEL_ipu(PSEL_ipu),
        .PENABLE(PENABLE),
        .PWRITE(PWRITE),
        .PADDR(PADDR),
        .PWDATA(PWDATA),
        .PSTRB(PSTRB),
        .PPROT(PPROT),
        .PREADY_peri(PREADY_peri),
        .PRDATA_peri(PRDATA_peri),
        .PREADY_ipu(PREADY_ipu),
        .PRDATA_ipu(PRDATA_ipu)
    );

    // Point instruction memory to RV32I test image and enlarge depth so file is not truncated.
    defparam dut.instr_mem_inst.DEPTH = 8192;
    defparam dut.instr_mem_inst.MEM = "../01_sim/RISC_V/02_test/isa_4b.hex";

    // External peripheral APB slave wrapper
    peri_apb_wrapper u_peri_apb_wrapper (
        .PCLK      (i_clk),
        .PRESETn   (i_reset),
        .PSEL      (PSEL_peri),
        .PENABLE   (PENABLE),
        .PWRITE    (PWRITE),
        .PADDR     (PADDR),
        .PWDATA    (PWDATA),
        .PSTRB     (PSTRB),
        .PPROT     (PPROT),
        .PRDATA    (PRDATA_peri),
        .PREADY    (PREADY_peri),
        .PSLVERR   (),
        .i_io_sw   (i_io_sw),
        .o_io_ledr (peri_io_ledr),
        .o_io_ledg (peri_io_ledg),
        .o_io_lcd  (peri_io_lcd),
        .o_io_hex0 (peri_io_hex0),
        .o_io_hex1 (peri_io_hex1),
        .o_io_hex2 (peri_io_hex2),
        .o_io_hex3 (peri_io_hex3),
        .o_io_hex4 (peri_io_hex4),
        .o_io_hex5 (peri_io_hex5),
        .o_io_hex6 (peri_io_hex6),
        .o_io_hex7 (peri_io_hex7)
    );

    // Clock period = 10ns
    initial begin
        i_clk = 1'b0;
        forever #5 i_clk = ~i_clk;
    end

    initial begin
        log_start("RISC-V single_cycle ISA bring-up");
        i_reset = 1'b0;
        i_io_sw = 32'h1234_5678;

        for (idx = 0; idx < BRAM_WORDS; idx = idx + 1) begin
            img_in_mem[idx]  = 32'd0;
            img_out_mem[idx] = 32'd0;
            img_tmp_mem[idx] = 32'd0;
        end

        for (idx = 0; idx < APB_WORDS; idx = idx + 1) begin
            apb_regs[idx] = 32'd0;
        end

        // Let reset hold for a couple clocks.
        #20;
        i_reset = 1'b1;
        log_start("RISC-V single_cycle ISA execution");
    end

    // BRAM models: synchronous write, asynchronous read for single-cycle LSU path.
    always @(posedge i_clk) begin
        if (img_in_sys_en && img_in_sys_we && (img_in_sys_addr < BRAM_WORDS)) begin
            img_in_mem[img_in_sys_addr] <= img_in_sys_wdata;
        end
        if (img_out_sys_en && img_out_sys_we && (img_out_sys_addr < BRAM_WORDS)) begin
            img_out_mem[img_out_sys_addr] <= img_out_sys_wdata;
        end
        if (img_tmp_sys_en && img_tmp_sys_we && (img_tmp_sys_addr < BRAM_WORDS)) begin
            img_tmp_mem[img_tmp_sys_addr] <= img_tmp_sys_wdata;
        end
    end

    always_comb begin
        img_in_sys_rdata  = (img_in_sys_addr  < BRAM_WORDS) ? img_in_mem[img_in_sys_addr]   : 32'd0;
        img_out_sys_rdata = (img_out_sys_addr < BRAM_WORDS) ? img_out_mem[img_out_sys_addr] : 32'd0;
        img_tmp_sys_rdata = (img_tmp_sys_addr < BRAM_WORDS) ? img_tmp_mem[img_tmp_sys_addr] : 32'd0;
    end

    // IPU APB4 stub: always-ready simple register block.
    assign PREADY_ipu = 1'b1;
    assign PRDATA_ipu = (PADDR[11:2] < APB_WORDS) ? apb_regs[PADDR[11:2]] : 32'd0;

    always @(posedge i_clk) begin
        if (PSEL_ipu && PENABLE && PWRITE && (PADDR[11:2] < APB_WORDS)) begin
            apb_regs[PADDR[11:2]] <= PWDATA;
        end
    end

    // ISA test style output and end condition used by the legacy scoreboard.
    always @(posedge i_clk) begin
        if (!i_reset) begin
            cycle_cnt <= 32'd0;
        end else begin
            cycle_cnt <= cycle_cnt + 1'b1;

            // Legacy ISA character output comes from peripheral LEDR[7:0].
            if (o_pc_debug == 32'h0000_0018) begin
                $write("%c", peri_io_ledr[7:0]);
            end

            if (o_pc_debug == 32'h0000_001C) begin
                $display("\nEND of ISA RV32I test");
                $display("Cycles = %0d", cycle_cnt);
                $finish;
            end

            if (cycle_cnt > 32'd500000) begin
                $fatal(1, "Timeout waiting for ISA test end marker (PC=0x1C)");
            end
        end
    end

endmodule