`timescale 1ns/1ps
`include "ipu_addr_map_soc.vh"

// =============================================================================
// Module : tb_cpu_vga_dehaze
// Description:
//   Testbench CPU-driven: RISC-V chạy vga_dehaze_fulltest.hex nạp vào instr_mem,
//   lập trình IPU qua APB, chờ đến khi LEDR = 0xFFFF_FFFF (CPU signal done),
//   sau đó TB giả lập VGA scan toàn frame từ img_out_bram và lưu output BMP.
//
// Khác với soc_128_tb.sv (dùng force để bypass CPU):
//   - KHÔNG force reg_wr_en / reg_rd_en / reg_addr / reg_wdata
//   - CPU thực sự chạy ASM code và lập trình IPU qua APB bus
//   - Testbench chỉ preload img_in_bram và chờ signal từ CPU
//
// Cách chạy:
//   vsim -c tb_cpu_vga_dehaze \
//     +IMG_IN=01_sim/soc/Testbench_SOC/sim/image_test/soc_input_128.bmp \
//     +OUT_DIR=01_sim/soc/Testbench_SOC/sim/image_test/
//   hoặc dùng TCL:
//     do 01_sim/soc/Testbench_SOC/script/run_cpu_vga_dehaze_test.tcl
//     do 01_sim/soc/Testbench_SOC/script/run_cpu_vga_dehaze_image47.tcl
// =============================================================================

module tb_cpu_vga_dehaze;

    // ─────────────────────────────────────────────────────────────────────────
    // Parameters
    // ─────────────────────────────────────────────────────────────────────────
    localparam int ImgWidth  = 128;
    localparam int ImgHeight = 128;
    localparam int NumPixels = ImgWidth * ImgHeight;  // 16384
    localparam int HalfClk   = 5;                     // 100 MHz → 10 ns period

    // Timeout: mỗi pixel mất ~50 cycles IPU + ~10 cycles APB overhead per reg
    // 128×128 × 50 + margin = ~1_000_000 cycles. Đặt 5M cho dư.
    localparam int TIMEOUT_CYCLES = 5_000_000;

    // ─────────────────────────────────────────────────────────────────────────
    // DUT signals
    // ─────────────────────────────────────────────────────────────────────────
    logic        clk;
    logic        rst_n;

    logic [31:0] i_io_sw;
    logic [31:0] o_io_ledr;
    logic [31:0] o_io_ledg;
    logic [31:0] o_io_lcd;
    logic [6:0]  o_io_hex0, o_io_hex1, o_io_hex2, o_io_hex3;
    logic [6:0]  o_io_hex4, o_io_hex5, o_io_hex6, o_io_hex7;
    logic [31:0] o_pc_debug;
    logic        o_insn_vld;
    logic        o_ipu_irq;

    // VGA read port
    logic        vga_rd_en;
    logic [15:0] vga_rd_addr;
    logic [31:0] vga_rd_data;

    // ─────────────────────────────────────────────────────────────────────────
    // TB internal state
    // ─────────────────────────────────────────────────────────────────────────
    logic [23:0] rgb_mem       [NumPixels];   // input image (BGR packed from BMP)
    logic [7:0]  bmp_header    [54];           // BMP file header (54 bytes)
    logic [23:0] cap_recovery  [NumPixels];   // captured dehazed output

    integer      fp_in, obmp;
    integer      timeout_cnt;
    integer      pix;
    logic  [7:0] rd_byte;

    string img_input;
    string out_dir;
    string img_arg;
    string out_arg;
    byte   out_last_ch;

    // ─────────────────────────────────────────────────────────────────────────
    // Clock
    // ─────────────────────────────────────────────────────────────────────────
    initial clk = 1'b0;
    always #HalfClk clk = ~clk;

    // ─────────────────────────────────────────────────────────────────────────
    // DUT
    // ─────────────────────────────────────────────────────────────────────────
    soc_top dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .i_io_sw    (i_io_sw),
        .o_io_ledr  (o_io_ledr),
        .o_io_ledg  (o_io_ledg),
        .o_io_lcd   (o_io_lcd),
        .o_io_hex0  (o_io_hex0), .o_io_hex1 (o_io_hex1),
        .o_io_hex2  (o_io_hex2), .o_io_hex3 (o_io_hex3),
        .o_io_hex4  (o_io_hex4), .o_io_hex5 (o_io_hex5),
        .o_io_hex6  (o_io_hex6), .o_io_hex7 (o_io_hex7),
        .o_pc_debug (o_pc_debug),
        .o_insn_vld (o_insn_vld),
        .o_ipu_irq  (o_ipu_irq),
        .vga_rd_en  (vga_rd_en),
        .vga_rd_addr(vga_rd_addr),
        .vga_rd_data(vga_rd_data)
    );

    // Default VGA port to idle
    initial begin
        vga_rd_en   = 1'b0;
        vga_rd_addr = 16'd0;
        i_io_sw     = 32'd0;
    end

    // ─────────────────────────────────────────────────────────────────────────
    // Tasks
    // ─────────────────────────────────────────────────────────────────────────

    // Đọc BMP 24-bit (54-byte header + pixel data BGR order)
    task automatic load_bmp;
    begin
        fp_in = $fopen(img_input, "rb");
        if (!fp_in) $fatal(1, "[TB] Cannot open input BMP: %s", img_input);

        for (pix = 0; pix < 54; pix = pix + 1)
            bmp_header[pix] = $fgetc(fp_in);

        for (pix = 0; pix < NumPixels * 3; pix = pix + 1) begin
            rd_byte = $fgetc(fp_in);
            case (pix % 3)
                0: rgb_mem[pix/3][23:16] = rd_byte;  // B
                1: rgb_mem[pix/3][15:8]  = rd_byte;  // G
                2: rgb_mem[pix/3][7:0]   = rd_byte;  // R
                default: ;
            endcase
        end
        $fclose(fp_in);
        $display("[TB] BMP loaded: %s", img_input);
    end
    endtask

    // Preload img_in_bram (Port A sys interface) với ảnh BMP đã đọc.
    // Format: {8'h00, R[7:0], G[7:0], B[7:0]} = {pad, RGB}
    task automatic preload_img_in_bram;
    begin
        for (pix = 0; pix < NumPixels; pix = pix + 1)
            dut.u_img_in_bram.mem[pix] = {8'h00, rgb_mem[pix]};
        $display("[TB] img_in_bram preloaded (%0d pixels)", NumPixels);
    end
    endtask

    // Reset DUT: 8 cycles low, 1 cycle high
    task automatic reset_dut;
    begin
        rst_n = 1'b0;
        repeat (8) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        $display("[TB] DUT reset complete");
    end
    endtask

    // Capture kết quả từ img_out_bram sau khi IPU done
    task automatic capture_img_out_bram;
    begin
        for (pix = 0; pix < NumPixels; pix = pix + 1)
            cap_recovery[pix] = dut.u_img_out_bram.mem[pix][23:0];
    end
    endtask

    // Giả lập VGA scan toàn frame: đọc từng pixel qua vga_rd port
    // Kiểm tra dữ liệu khớp với cap_recovery đã capture.
    // Độ trễ BRAM = 2 clock cycles (1 pipeline reg + 1 BRAM output reg).
    task automatic vga_fullframe_scan;
        integer p;
        logic [31:0] got;
        logic [31:0] exp;
        integer mismatch;
    begin
        mismatch   = 0;
        vga_rd_en  = 1'b1;

        $display("[TB] VGA full-frame scan started (%0d pixels)...", NumPixels);

        for (p = 0; p < NumPixels; p = p + 1) begin
            vga_rd_addr = p[15:0];
            @(posedge clk);   // pipeline reg latches addr
            @(posedge clk);   // BRAM output register latches data
            @(posedge clk);   // settle
            got = vga_rd_data;
            exp = {8'h00, cap_recovery[p]};

            if (got[23:0] !== exp[23:0]) begin
                if (mismatch < 10)   // log chỉ 10 lỗi đầu
                    $display("  [VGA_MISMATCH] pix=%0d  got=0x%06h  exp=0x%06h",
                             p, got[23:0], exp[23:0]);
                mismatch = mismatch + 1;
            end
        end

        vga_rd_en = 1'b0;

        if (mismatch == 0)
            $display("[TB] VGA full-frame scan: PASS (all %0d pixels OK)", NumPixels);
        else
            $display("[TB] VGA full-frame scan: FAIL (%0d/%0d mismatches)", mismatch, NumPixels);
    end
    endtask

    // Lưu ảnh input BMP (để so sánh before/after)
    task automatic save_input_bmp(input string name);
    begin
        obmp = $fopen({out_dir, name}, "wb");
        if (!obmp) $fatal(1, "[TB] Cannot write: %s%s", out_dir, name);
        for (pix = 0; pix < 54; pix = pix + 1)
            $fwrite(obmp, "%c", bmp_header[pix]);
        for (pix = 0; pix < NumPixels; pix = pix + 1) begin
            $fwrite(obmp, "%c", rgb_mem[pix][23:16]);  // B
            $fwrite(obmp, "%c", rgb_mem[pix][15:8]);   // G
            $fwrite(obmp, "%c", rgb_mem[pix][7:0]);    // R
        end
        $fclose(obmp);
        $display("[TB] Saved input BMP: %s%s", out_dir, name);
    end
    endtask

    // Lưu ảnh output BMP (dehazed) từ img_out_bram
    // img_out_bram stores {pad8, B[7:0], G[7:0], R[7:0]}
    // (IPU writes R to [7:0], G to [15:8], B to [23:16] — same as input packing)
    task automatic save_output_bmp(input string name);
    begin
        obmp = $fopen({out_dir, name}, "wb");
        if (!obmp) $fatal(1, "[TB] Cannot write: %s%s", out_dir, name);
        for (pix = 0; pix < 54; pix = pix + 1)
            $fwrite(obmp, "%c", bmp_header[pix]);
        for (pix = 0; pix < NumPixels; pix = pix + 1) begin
            // BMP BGR byte order: write B, G, R
            $fwrite(obmp, "%c", cap_recovery[pix][7:0]);   // B
            $fwrite(obmp, "%c", cap_recovery[pix][15:8]);  // G
            $fwrite(obmp, "%c", cap_recovery[pix][23:16]); // R
        end
        $fclose(obmp);
        $display("[TB] Saved dehazed BMP: %s%s", out_dir, name);
    end
    endtask

    // ─────────────────────────────────────────────────────────────────────────
    // Main test flow
    // ─────────────────────────────────────────────────────────────────────────
    initial begin
        // Đọc tham số dòng lệnh
        img_input = "01_sim/soc/Testbench_SOC/sim/image_test/soc_input_128.bmp";
        out_dir   = "01_sim/soc/Testbench_SOC/sim/image_test/";

        if ($value$plusargs("IMG_IN=%s",  img_arg)) img_input = img_arg;
        if ($value$plusargs("OUT_DIR=%s", out_arg)) out_dir   = out_arg;

        // Đảm bảo out_dir kết thúc bằng '/'
        if (out_dir.len() > 0) begin
            out_last_ch = out_dir.getc(out_dir.len() - 1);
            if ((out_last_ch != "/") && (out_last_ch != 8'h5C))
                out_dir = {out_dir, "/"};
        end

        $display("================================================================");
        $display("  TB_CPU_VGA_DEHAZE — End-to-End CPU + IPU + VGA Test");
        $display("================================================================");
        $display("  Input BMP : %s", img_input);
        $display("  Output dir: %s", out_dir);
        $display("  Image size: %0dx%0d pixels", ImgWidth, ImgHeight);

        // ── Bước 1: Load BMP, reset, preload BRAM ──────────────────────────
        $display("\n[STEP 1] Load BMP + Reset + Preload img_in_bram");
        load_bmp();
        reset_dut();
        preload_img_in_bram();
        save_input_bmp("cpu_input_128.bmp");

        // ── Bước 2: CPU tự chạy ASM (vga_dehaze_fulltest.hex) ─────────────
        // CPU sẽ:
        //   - Verify IPU_ID
        //   - Configure tất cả IPU registers qua APB
        //   - Trigger IPU
        //   - Poll IRQ_STATUS
        //   - Spot-check img_out pixels
        //   - Set LEDR = 0xFFFF_FFFF khi hoàn thành
        $display("\n[STEP 2] CPU running ASM (vga_dehaze_fulltest.hex)...");
        $display("  Waiting for o_io_ledr == 0xFFFFFFFF or timeout (%0d cycles)",
                 TIMEOUT_CYCLES);

        timeout_cnt = 0;
        while ((o_io_ledr !== 32'hFFFF_FFFF) && (timeout_cnt < TIMEOUT_CYCLES)) begin
            @(posedge clk);
            timeout_cnt = timeout_cnt + 1;

            // Hiển thị progress mỗi 500K cycles
            if ((timeout_cnt % 500_000) == 0)
                $display("  ... %0d cycles elapsed  PC=0x%08h  LEDR=0x%08h  LEDG=0x%08h",
                         timeout_cnt, o_pc_debug, o_io_ledr, o_io_ledg);
        end

        if (o_io_ledr !== 32'hFFFF_FFFF) begin
            $display("[FAIL] Timeout! CPU did not signal done after %0d cycles.", TIMEOUT_CYCLES);
            $display("       Last PC   = 0x%08h", o_pc_debug);
            $display("       Last LEDR = 0x%08h  (expected 0xFFFFFFFF)", o_io_ledr);
            $display("       Last LEDG = 0x%08h", o_io_ledg);
            $display("       IRQ signal= %0b", o_ipu_irq);
            $finish;
        end

        $display("[PASS] CPU done! LEDR=0xFFFFFFFF at cycle %0d", timeout_cnt);
        $display("       LEDG spot-check pass count = %0d / 8", o_io_ledg[3:0]);

        // ── Bước 3: Capture img_out_bram ──────────────────────────────────
        $display("\n[STEP 3] Capture img_out_bram → dehazed pixels");
        capture_img_out_bram();

        // ── Bước 4: VGA full-frame scan verification ───────────────────────
        $display("\n[STEP 4] VGA port full-frame scan (hardware readback)");
        vga_fullframe_scan();

        // ── Bước 5: Lưu output BMP ────────────────────────────────────────
        $display("\n[STEP 5] Save output BMP");
        save_output_bmp("cpu_dehazed_128.bmp");

        $display("\n================================================================");
        $display("  TEST COMPLETE");
        $display("  Input  → %scpu_input_128.bmp",  out_dir);
        $display("  Output → %scpu_dehazed_128.bmp", out_dir);
        $display("================================================================");
        $finish;
    end

    // ─────────────────────────────────────────────────────────────────────────
    // Watchdog: kill sim nếu CPU bị stuck tại vị trí bất thường
    // ─────────────────────────────────────────────────────────────────────────
    initial begin
        // Hard limit: 10M cycles
        repeat (10_000_000) @(posedge clk);
        $display("[WATCHDOG] Hard timeout at 10M cycles — simulation killed.");
        $display("           PC = 0x%08h  LEDR = 0x%08h", o_pc_debug, o_io_ledr);
        $finish;
    end

endmodule
