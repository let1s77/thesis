`timescale 1ns/1ps
`include "ipu_addr_map_soc.vh"

module soc_128_tb;

    localparam int ImgWidth  = 128;
    localparam int ImgHeight = 128;
    localparam int NumPixels = ImgWidth * ImgHeight;
    localparam int HalfClk   = 5;

    logic clk;
    logic rst_n;

    logic [31:0] i_io_sw;
    logic [31:0] o_io_ledr;
    logic [31:0] o_io_ledg;
    logic [31:0] o_io_lcd;
    logic [6:0]  o_io_hex0, o_io_hex1, o_io_hex2, o_io_hex3;
    logic [6:0]  o_io_hex4, o_io_hex5, o_io_hex6, o_io_hex7;
    logic [31:0] o_pc_debug;
    logic        o_insn_vld;
    logic        o_ipu_irq;

    logic        tb_reg_wr_en;
    logic        tb_reg_rd_en;
    logic [31:0] tb_reg_addr;
    logic [31:0] tb_reg_wdata;

    logic [23:0] rgb_mem [NumPixels];
    logic [7:0]  bmp_header [54];
    logic [23:0] cap_recovery [NumPixels];

    // VGA port signals (driven by TB to exercise soc_top VGA read interface)
    logic        vga_rd_en;
    logic [15:0] vga_rd_addr;
    logic [31:0] vga_rd_data;

    integer fp_in;
    integer obmp;
    integer timeout;
    integer pix;
    logic [7:0] rd_byte;

    string img_input;
    string out_dir;
    string img_arg;
    string out_arg;
    byte out_last_ch;

    task automatic log_start(input string test_name);
    begin
        $display("<at time %0t ns> [START] %s", $time, test_name);
    end
    endtask

    initial clk = 1'b0;
    always #HalfClk clk = ~clk;

    soc_top dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .i_io_sw  (i_io_sw),
        .o_io_ledr(o_io_ledr),
        .o_io_ledg(o_io_ledg),
        .o_io_lcd (o_io_lcd),
        .o_io_hex0(o_io_hex0), .o_io_hex1(o_io_hex1),
        .o_io_hex2(o_io_hex2), .o_io_hex3(o_io_hex3),
        .o_io_hex4(o_io_hex4), .o_io_hex5(o_io_hex5),
        .o_io_hex6(o_io_hex6), .o_io_hex7(o_io_hex7),
        .o_pc_debug(o_pc_debug),
        .o_insn_vld(o_insn_vld),
        .o_ipu_irq(o_ipu_irq),
        .vga_rd_en  (vga_rd_en),
        .vga_rd_addr(vga_rd_addr),
        .vga_rd_data(vga_rd_data)
    );

    // Default VGA port to idle
    initial begin
        vga_rd_en   = 1'b0;
        vga_rd_addr = 16'd0;
    end

    initial begin
        // Bypass APB path from CPU for controlled IPU programming in SoC TB.
        force dut.reg_wr_en = tb_reg_wr_en;
        force dut.reg_rd_en = tb_reg_rd_en;
        force dut.reg_addr  = tb_reg_addr;
        force dut.reg_wdata = tb_reg_wdata;
    end

    task automatic clear_controls;
    begin
        i_io_sw     = 32'd0;
        tb_reg_wr_en = 1'b0;
        tb_reg_rd_en = 1'b0;
        tb_reg_addr  = 32'd0;
        tb_reg_wdata = 32'd0;
    end
    endtask

    task automatic reset_dut;
    begin
        rst_n = 1'b0;
        clear_controls();
        repeat (8) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
    end
    endtask

    task automatic reg_write(input logic [31:0] addr, input logic [31:0] data);
    begin
        @(posedge clk);
        tb_reg_wr_en <= 1'b1;
        tb_reg_addr  <= addr;
        tb_reg_wdata <= data;
        @(posedge clk);
        tb_reg_wr_en <= 1'b0;
        tb_reg_addr  <= 32'd0;
        tb_reg_wdata <= 32'd0;
    end
    endtask

    task automatic load_bmp;
    begin
        fp_in = $fopen(img_input, "rb");
        if (!fp_in) $fatal(1, "Cannot open input BMP: %s", img_input);

        for (pix = 0; pix < 54; pix = pix + 1) begin
            bmp_header[pix] = $fgetc(fp_in);
        end

        for (pix = 0; pix < NumPixels * 3; pix = pix + 1) begin
            rd_byte = $fgetc(fp_in);
            case (pix % 3)
                0: rgb_mem[pix/3][23:16] = rd_byte; // B
                1: rgb_mem[pix/3][15:8]  = rd_byte; // G
                2: rgb_mem[pix/3][7:0]   = rd_byte; // R
                default: ;
            endcase
        end

        $fclose(fp_in);
    end
    endtask

    task automatic preload_img_in_bram;
    begin
        for (pix = 0; pix < NumPixels; pix = pix + 1) begin
            dut.u_img_in_bram.mem[pix] = {8'h00, rgb_mem[pix]};
        end
    end
    endtask

    task automatic capture_img_out_bram;
    begin
        for (pix = 0; pix < NumPixels; pix = pix + 1) begin
            cap_recovery[pix] = dut.u_img_out_bram.mem[pix][23:0];
        end
    end
    endtask

    // VGA port readback verification: drive vga_rd_en/addr and check vga_rd_data
    // matches the pixel already captured from img_out_bram.
    // img_out_bram stores each pixel as {pad8, post_img[23:0]} = {0x00, R, G, B}.
    // soc_top has 1 pipeline register before Port B + 1 BRAM output register = 3-cycle latency.
    // vga_rd_data[23:0] should equal cap_recovery[p] = mem[p][23:0] directly.
    task automatic verify_vga_port;
        integer p;
        logic [31:0] expected_word;
        logic [31:0] got_word;
        integer mismatch_count;
    begin
        mismatch_count = 0;
        vga_rd_en = 1'b1;
        // Sample 16 evenly spaced pixels across the frame
        for (p = 0; p < NumPixels; p = p + (NumPixels / 16)) begin
            vga_rd_addr = p[15:0];
            @(posedge clk);  // soc_top pipeline register latches addr
            @(posedge clk);  // BRAM output register latches mem[addr]
            @(posedge clk);  // data fully settled on vga_rd_data
            got_word = vga_rd_data;
            // vga_rd_data = mem[p] = {8'h00, cap_recovery[p][23:16], [15:8], [7:0]}
            expected_word = {8'h00, cap_recovery[p]};
            if (got_word[23:0] !== expected_word[23:0]) begin
                $display("  VGA_CHK MISMATCH pix=%0d: vga_rd_data=0x%06h expected=0x%06h",
                         p, got_word[23:0], expected_word[23:0]);
                mismatch_count = mismatch_count + 1;
            end
        end
        vga_rd_en = 1'b0;
        if (mismatch_count == 0)
            $display("  VGA port readback: PASS (16 pixels checked)");
        else
            $display("  VGA port readback: WARN %0d/16 mismatches", mismatch_count);
    end
    endtask

    task automatic save_input_bmp(input string name);
    begin
        obmp = $fopen({out_dir, name}, "wb");
        if (!obmp) $fatal(1, "Cannot open output BMP: %s%s", out_dir, name);

        for (pix = 0; pix < 54; pix = pix + 1) begin
            $fwrite(obmp, "%c", bmp_header[pix]);
        end

        for (pix = 0; pix < NumPixels; pix = pix + 1) begin
            $fwrite(obmp, "%c", rgb_mem[pix][23:16]);
            $fwrite(obmp, "%c", rgb_mem[pix][15:8]);
            $fwrite(obmp, "%c", rgb_mem[pix][7:0]);
        end

        $fclose(obmp);
        $display("  Saved: %s%s", out_dir, name);
    end
    endtask

    task automatic save_output_bmp(input string name, input logic [23:0] map [NumPixels]);
    begin
        obmp = $fopen({out_dir, name}, "wb");
        if (!obmp) $fatal(1, "Cannot open output BMP: %s%s", out_dir, name);

        for (pix = 0; pix < 54; pix = pix + 1) begin
            $fwrite(obmp, "%c", bmp_header[pix]);
        end

        for (pix = 0; pix < NumPixels; pix = pix + 1) begin
            // Convert RGB-like packed output to BMP BGR byte order.
            $fwrite(obmp, "%c", map[pix][7:0]);
            $fwrite(obmp, "%c", map[pix][15:8]);
            $fwrite(obmp, "%c", map[pix][23:16]);
        end

        $fclose(obmp);
        $display("  Saved: %s%s", out_dir, name);
    end
    endtask

    initial begin
        img_input = "01_sim/IPU/Testbench_DarkChannel_System/sim/image/test_128.bmp";
        out_dir   = "01_sim/soc/Testbench_SOC/sim/image_test/";

        if ($value$plusargs("IMG_IN=%s", img_arg)) img_input = img_arg;
        if ($value$plusargs("OUT_DIR=%s", out_arg)) out_dir = out_arg;

        if (out_dir.len() > 0) begin
            out_last_ch = out_dir.getc(out_dir.len() - 1);
            if ((out_last_ch != "/") && (out_last_ch != 8'h5C)) out_dir = {out_dir, "/"};
        end

        $display("==========================================================");
        $display("  SOC TOP TEST (BMP before/after)");
        $display("==========================================================");
        $display("Input BMP : %s", img_input);
        $display("Output dir: %s", out_dir);

        log_start("Load BMP and reset SOC");
        load_bmp();
        reset_dut();

        log_start("Preload image BRAM and program IPU regs");
        preload_img_in_bram();

        reg_write(`IPU_SRC_ADDR,   `IMG_IN_BUF_BASE);
        reg_write(`IPU_DST_ADDR,   `IMG_OUT_BUF_BASE);
        reg_write(`IPU_TMP_ADDR,   `IMG_TMP_BUF_BASE);
        reg_write(`IPU_IMG_WIDTH,  ImgWidth);
        reg_write(`IPU_IMG_HEIGHT, ImgHeight);
        reg_write(`IPU_IMG_STRIDE, ImgWidth * 4);
        reg_write(`IPU_IRQ_EN, 32'h1);

        reg_write(`IPU_CTRL, 32'h3);
        reg_write(`IPU_CTRL, 32'h1);

        log_start("Run SOC until IPU IRQ done");
        timeout = 0;
        while (!o_ipu_irq && (timeout < (NumPixels * 80))) begin
            @(posedge clk);
            timeout = timeout + 1;
        end

        if (!o_ipu_irq) begin
            $fatal(1, "Timeout waiting for o_ipu_irq");
        end

        log_start("Capture and save SOC output BMP");
        capture_img_out_bram();
        save_input_bmp("soc_input_128.bmp");
        save_output_bmp("soc_output_128.bmp", cap_recovery);

        log_start("VGA port readback verify");
        verify_vga_port();

        $display("SOC image compare done.");
        $finish;
    end

endmodule
