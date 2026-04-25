`timescale 1ns/1ps
`include "ipu_addr_map_soc.vh"

module ipu_soc_128_tb;

    localparam int ImgWidth  = 128;
    localparam int ImgHeight = 128;
    localparam int NumPixels = ImgWidth * ImgHeight;
    localparam int HalfClk   = 5;
    localparam int AddrW     = 16;

    logic clk;
    logic rst_n;

    logic        reg_wr_en;
    logic        reg_rd_en;
    logic [31:0] reg_addr;
    logic [31:0] reg_wdata;
    logic [31:0] reg_rdata;

    logic        img_in_sys_en;
    logic        img_in_sys_we;
    logic [AddrW-1:0] img_in_sys_addr;
    logic [31:0] img_in_sys_wdata;
    logic [31:0] img_in_sys_rdata;

    logic        img_out_sys_en;
    logic        img_out_sys_we;
    logic [AddrW-1:0] img_out_sys_addr;
    logic [31:0] img_out_sys_wdata;
    logic [31:0] img_out_sys_rdata;

    logic        img_tmp_sys_en;
    logic        img_tmp_sys_we;
    logic [AddrW-1:0] img_tmp_sys_addr;
    logic [31:0] img_tmp_sys_wdata;
    logic [31:0] img_tmp_sys_rdata;

    logic ipu_irq;

    logic [23:0] src_rgb [NumPixels];
    logic [23:0] out_rgb [NumPixels];
    logic [23:0] golden_rgb [NumPixels];
    logic [7:0]  bmp_header [54];

    logic [7:0]  cap_dark [NumPixels];
    logic [7:0]  cap_sky [NumPixels];
    logic [7:0]  cap_tx_core [NumPixels];
    logic [7:0]  cap_tx_bank [NumPixels];
    logic [7:0]  cap_adc [NumPixels];
    logic [7:0]  cap_adc_used [NumPixels];
    logic [23:0] cap_recovery [NumPixels];

    integer fp_in;
    integer fp_golden;
    integer fp_out;
    integer pix;
    integer timeout;
    integer mismatch_cnt;
    integer max_abs;
    integer sum_abs;
    integer mae;
    integer diff_b;
    integer diff_g;
    integer diff_r;
    integer golden_max_mismatch_pct;
    integer golden_max_mae;
    integer mismatch_pct;
    integer rdval;
    integer sample_idx;
    integer dark_idx;
    integer sky_idx;
    integer tx_idx;
    integer tx_bank_idx;
    integer adc_idx;
    integer rec_used_idx;
    integer v;
    integer hist [256];
    integer cum;
    integer low_cut;
    integer high_cut;
    integer lo;
    integer hi;
    integer outv;
    logic [7:0] rd_byte;
    byte out_last_ch;

    string img_input;
    string golden_input;
    string out_dir;
    string img_arg;
    string golden_arg;
    string out_arg;

    bit has_golden;

    initial clk = 1'b0;
    always #HalfClk clk = ~clk;

    ipu_soc dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .reg_wr_en      (reg_wr_en),
        .reg_rd_en      (reg_rd_en),
        .reg_addr       (reg_addr),
        .reg_wdata      (reg_wdata),
        .reg_rdata      (reg_rdata),
        .img_in_sys_en  (img_in_sys_en),
        .img_in_sys_we  (img_in_sys_we),
        .img_in_sys_addr(img_in_sys_addr),
        .img_in_sys_wdata(img_in_sys_wdata),
        .img_in_sys_rdata(img_in_sys_rdata),
        .img_out_sys_en (img_out_sys_en),
        .img_out_sys_we (img_out_sys_we),
        .img_out_sys_addr(img_out_sys_addr),
        .img_out_sys_wdata(img_out_sys_wdata),
        .img_out_sys_rdata(img_out_sys_rdata),
        .img_tmp_sys_en (img_tmp_sys_en),
        .img_tmp_sys_we (img_tmp_sys_we),
        .img_tmp_sys_addr(img_tmp_sys_addr),
        .img_tmp_sys_wdata(img_tmp_sys_wdata),
        .img_tmp_sys_rdata(img_tmp_sys_rdata),
        .ipu_irq        (ipu_irq)
    );

    task automatic clear_controls;
    begin
        reg_wr_en        = 1'b0;
        reg_rd_en        = 1'b0;
        reg_addr         = 32'd0;
        reg_wdata        = 32'd0;

        img_in_sys_en    = 1'b0;
        img_in_sys_we    = 1'b0;
        img_in_sys_addr  = '0;
        img_in_sys_wdata = 32'd0;

        img_out_sys_en    = 1'b0;
        img_out_sys_we    = 1'b0;
        img_out_sys_addr  = '0;
        img_out_sys_wdata = 32'd0;

        img_tmp_sys_en    = 1'b0;
        img_tmp_sys_we    = 1'b0;
        img_tmp_sys_addr  = '0;
        img_tmp_sys_wdata = 32'd0;
    end
    endtask

    task automatic reset_dut;
    begin
        rst_n = 1'b0;
        clear_controls();
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
    end
    endtask

    task automatic reg_write(input logic [31:0] addr, input logic [31:0] data);
    begin
        @(posedge clk);
        reg_wr_en <= 1'b1;
        reg_addr  <= addr;
        reg_wdata <= data;
        @(posedge clk);
        reg_wr_en <= 1'b0;
        reg_addr  <= 32'd0;
        reg_wdata <= 32'd0;
    end
    endtask

    task automatic reg_read(input logic [31:0] addr, output logic [31:0] data);
    begin
        @(posedge clk);
        reg_rd_en <= 1'b1;
        reg_addr  <= addr;
        @(posedge clk);
        data = reg_rdata;
        reg_rd_en <= 1'b0;
        reg_addr  <= 32'd0;
    end
    endtask

    task automatic load_input_bmp;
    begin
        fp_in = $fopen(img_input, "rb");
        if (!fp_in) begin
            $fatal(1, "Cannot open input BMP: %s", img_input);
        end

        for (pix = 0; pix < 54; pix = pix + 1) begin
            bmp_header[pix] = $fgetc(fp_in);
        end

        for (pix = 0; pix < NumPixels * 3; pix = pix + 1) begin
            rd_byte = $fgetc(fp_in);
            case (pix % 3)
                0: src_rgb[pix/3][23:16] = rd_byte; // B
                1: src_rgb[pix/3][15:8]  = rd_byte; // G
                2: src_rgb[pix/3][7:0]   = rd_byte; // R
                default: ;
            endcase
        end

        $fclose(fp_in);
    end
    endtask

    task automatic load_golden_bmp;
    begin
        has_golden = 1'b0;
        fp_golden = $fopen(golden_input, "rb");
        if (!fp_golden) begin
            $display("WARN: Golden BMP not found: %s. Golden compare is skipped.", golden_input);
            disable load_golden_bmp;
        end

        has_golden = 1'b1;
        for (pix = 0; pix < 54; pix = pix + 1) begin
            rdval = $fgetc(fp_golden);
        end

        for (pix = 0; pix < NumPixels * 3; pix = pix + 1) begin
            rd_byte = $fgetc(fp_golden);
            case (pix % 3)
                // Recovery golden BMPs in this repo are dumped as R,G,B bytes.
                0: golden_rgb[pix/3][7:0]   = rd_byte;
                1: golden_rgb[pix/3][15:8]  = rd_byte;
                2: golden_rgb[pix/3][23:16] = rd_byte;
                default: ;
            endcase
        end

        $fclose(fp_golden);
    end
    endtask

    task automatic write_img_in_buf;
    begin
        for (pix = 0; pix < NumPixels; pix = pix + 1) begin
            @(posedge clk);
            img_in_sys_en    <= 1'b1;
            img_in_sys_we    <= 1'b1;
            img_in_sys_addr  <= pix[AddrW-1:0];
            img_in_sys_wdata <= {8'h00, src_rgb[pix]};
        end

        @(posedge clk);
        img_in_sys_en    <= 1'b0;
        img_in_sys_we    <= 1'b0;
        img_in_sys_addr  <= '0;
        img_in_sys_wdata <= 32'd0;
    end
    endtask

    task automatic sanity_check_img_in;
    begin
        // Verify a few probe points through Port A readback.
        for (sample_idx = 0; sample_idx < 4; sample_idx = sample_idx + 1) begin
            case (sample_idx)
                0: pix = 0;
                1: pix = 127;
                2: pix = (NumPixels/2);
                default: pix = NumPixels - 1;
            endcase

            @(posedge clk);
            img_in_sys_en   <= 1'b1;
            img_in_sys_we   <= 1'b0;
            img_in_sys_addr <= pix[AddrW-1:0];
            @(posedge clk);
            @(posedge clk);
            if (img_in_sys_rdata[23:0] !== src_rgb[pix]) begin
                $fatal(1, "IMG_IN sanity failed at idx=%0d exp=%h got=%h", pix, src_rgb[pix], img_in_sys_rdata[23:0]);
            end
        end

        @(posedge clk);
        img_in_sys_en   <= 1'b0;
        img_in_sys_we   <= 1'b0;
        img_in_sys_addr <= '0;
    end
    endtask

    task automatic read_img_out_buf;
    begin
        for (pix = 0; pix < NumPixels; pix = pix + 1) begin
            @(posedge clk);
            img_out_sys_en   <= 1'b1;
            img_out_sys_we   <= 1'b0;
            img_out_sys_addr <= pix[AddrW-1:0];
            @(posedge clk);
            @(posedge clk);
            out_rgb[pix] <= img_out_sys_rdata[23:0];
            cap_recovery[pix] <= img_out_sys_rdata[23:0];
        end

        @(posedge clk);
        img_out_sys_en   <= 1'b0;
        img_out_sys_we   <= 1'b0;
        img_out_sys_addr <= '0;
    end
    endtask

    task automatic save_gray_bmp(
        input string name,
        input logic [7:0] map [NumPixels],
        input bit use_robust_stretch
    );
    begin
        fp_out = $fopen({out_dir, name}, "wb");
        if (!fp_out) begin
            $fatal(1, "Cannot open output BMP: %s%s", out_dir, name);
        end

        for (pix = 0; pix < 54; pix = pix + 1) begin
            $fwrite(fp_out, "%c", bmp_header[pix]);
        end

        if (use_robust_stretch) begin
            for (v = 0; v < 256; v = v + 1) begin
                hist[v] = 0;
            end
            for (pix = 0; pix < NumPixels; pix = pix + 1) begin
                hist[map[pix]] = hist[map[pix]] + 1;
            end

            low_cut = NumPixels / 100;
            high_cut = NumPixels / 100;

            cum = 0;
            lo = 0;
            for (v = 0; v < 256; v = v + 1) begin
                cum = cum + hist[v];
                if (cum > low_cut) begin
                    lo = v;
                    v = 256;
                end
            end

            cum = 0;
            hi = 255;
            for (v = 255; v >= 0; v = v - 1) begin
                cum = cum + hist[v];
                if (cum > high_cut) begin
                    hi = v;
                    v = -1;
                end
            end

            if (hi <= lo) begin
                lo = 0;
                hi = 255;
            end

            for (pix = 0; pix < NumPixels; pix = pix + 1) begin
                v = map[pix];
                if (v <= lo) begin
                    outv = 0;
                end else if (v >= hi) begin
                    outv = 255;
                end else begin
                    outv = ((v - lo) * 255) / (hi - lo);
                end
                $fwrite(fp_out, "%c", outv[7:0]);
                $fwrite(fp_out, "%c", outv[7:0]);
                $fwrite(fp_out, "%c", outv[7:0]);
            end
        end else begin
            for (pix = 0; pix < NumPixels; pix = pix + 1) begin
                $fwrite(fp_out, "%c", map[pix]);
                $fwrite(fp_out, "%c", map[pix]);
                $fwrite(fp_out, "%c", map[pix]);
            end
        end

        $fclose(fp_out);
        $display("  Saved: %s%s", out_dir, name);
    end
    endtask

    task automatic save_rgb_bmp(input string name, input logic [23:0] map [NumPixels]);
    begin
        fp_out = $fopen({out_dir, name}, "wb");
        if (!fp_out) begin
            $fatal(1, "Cannot open output BMP: %s%s", out_dir, name);
        end

        for (pix = 0; pix < 54; pix = pix + 1) begin
            $fwrite(fp_out, "%c", bmp_header[pix]);
        end

        for (pix = 0; pix < NumPixels; pix = pix + 1) begin
            $fwrite(fp_out, "%c", map[pix][23:16]);
            $fwrite(fp_out, "%c", map[pix][15:8]);
            $fwrite(fp_out, "%c", map[pix][7:0]);
        end

        $fclose(fp_out);
        $display("  Saved: %s%s", out_dir, name);
    end
    endtask

    task automatic save_recovery_bmp(input string name, input logic [23:0] map [NumPixels]);
    begin
        fp_out = $fopen({out_dir, name}, "wb");
        if (!fp_out) begin
            $fatal(1, "Cannot open output BMP: %s%s", out_dir, name);
        end

        for (pix = 0; pix < 54; pix = pix + 1) begin
            $fwrite(fp_out, "%c", bmp_header[pix]);
        end

        for (pix = 0; pix < NumPixels; pix = pix + 1) begin
            $fwrite(fp_out, "%c", map[pix][7:0]);
            $fwrite(fp_out, "%c", map[pix][15:8]);
            $fwrite(fp_out, "%c", map[pix][23:16]);
        end

        $fclose(fp_out);
        $display("  Saved: %s%s", out_dir, name);
    end
    endtask

    task automatic compare_with_golden;
    begin
        if (!has_golden) begin
            disable compare_with_golden;
        end

        mismatch_cnt = 0;
        max_abs = 0;
        sum_abs = 0;

        for (pix = 0; pix < NumPixels; pix = pix + 1) begin
            diff_b = out_rgb[pix][23:16] - golden_rgb[pix][23:16];
            diff_g = out_rgb[pix][15:8]  - golden_rgb[pix][15:8];
            diff_r = out_rgb[pix][7:0]   - golden_rgb[pix][7:0];

            if (diff_b < 0) diff_b = -diff_b;
            if (diff_g < 0) diff_g = -diff_g;
            if (diff_r < 0) diff_r = -diff_r;

            sum_abs = sum_abs + diff_b + diff_g + diff_r;

            if (diff_b > max_abs) max_abs = diff_b;
            if (diff_g > max_abs) max_abs = diff_g;
            if (diff_r > max_abs) max_abs = diff_r;

            if ((diff_b > 8) || (diff_g > 8) || (diff_r > 8)) begin
                mismatch_cnt = mismatch_cnt + 1;
            end
        end

        mae = sum_abs / (NumPixels * 3);
        mismatch_pct = (mismatch_cnt * 100) / NumPixels;
        $display("Golden compare: mismatched pixels=%0d/%0d (%0d%%), MAE=%0d, MAX=%0d", mismatch_cnt, NumPixels, mismatch_pct, mae, max_abs);
        $display("Golden thresholds: mismatch<=%0d%%, MAE<=%0d", golden_max_mismatch_pct, golden_max_mae);

        if ((mismatch_pct > golden_max_mismatch_pct) || (mae > golden_max_mae)) begin
            $fatal(1, "Golden compare failed: thresholds exceeded");
        end
    end
    endtask

    always @(posedge clk) begin
        if (rst_n) begin
            if (dut.u_ipu_core.dark_enable && dut.u_ipu_core.u_haze_removal_top.u_core.purple_dark_valid
                    && (dark_idx < NumPixels)) begin
                cap_dark[dark_idx] <= dut.u_ipu_core.u_haze_removal_top.u_core.purple_dark_ch;
                dark_idx <= dark_idx + 1;
            end

            if (dut.u_ipu_core.trans_enable && dut.u_ipu_core.u_haze_removal_top.u_core.purple_sky_valid
                    && (sky_idx < NumPixels)) begin
                cap_sky[sky_idx] <= (dut.u_ipu_core.u_haze_removal_top.u_core.purple_sky ? 8'hFF : 8'h00);
                sky_idx <= sky_idx + 1;
            end

            if (dut.u_ipu_core.trans_enable && dut.u_ipu_core.u_haze_removal_top.u_core.purple_tx_valid
                    && (tx_idx < NumPixels)) begin
                cap_tx_core[tx_idx] <= dut.u_ipu_core.u_haze_removal_top.u_core.purple_tx;
                tx_idx <= tx_idx + 1;
            end

            if (dut.u_ipu_core.u_haze_removal_top.u_core.adc_in_valid && (tx_bank_idx < NumPixels)) begin
                cap_tx_bank[tx_bank_idx] <= dut.u_ipu_core.u_haze_removal_top.u_core.adc_in_pix;
                tx_bank_idx <= tx_bank_idx + 1;
            end

            if (dut.u_ipu_core.u_haze_removal_top.u_core.adc_out_valid && (adc_idx < NumPixels)) begin
                cap_adc[adc_idx] <= dut.u_ipu_core.u_haze_removal_top.u_core.adc_out_pix;
                adc_idx <= adc_idx + 1;
            end

            if (dut.u_ipu_core.post_frame_clken && (rec_used_idx < NumPixels)) begin
                cap_adc_used[rec_used_idx] <= dut.u_ipu_core.u_haze_removal_top.u_core.adc_dark_for_recovery;
                rec_used_idx <= rec_used_idx + 1;
            end
        end
    end

    initial begin
        img_input    = "../01_sim/IPU/Testbench_DarkChannel_System/sim/image/test_128.bmp";
        golden_input = "../01_sim/IPU/Testbench_HAZE_REMOVAL_TOP/sim/image_global_p_test/haze_recovery_128.bmp";
        out_dir      = "../01_sim/IPU/Testbench_IPU_SOC/sim/image/";
        golden_max_mismatch_pct = 60;
        golden_max_mae          = 25;

        if ($value$plusargs("IMG_IN=%s", img_arg)) begin
            img_input = img_arg;
        end
        if ($value$plusargs("GOLDEN_IN=%s", golden_arg)) begin
            golden_input = golden_arg;
        end
        if ($value$plusargs("OUT_DIR=%s", out_arg)) begin
            out_dir = out_arg;
        end
        void'($value$plusargs("GOLDEN_MAX_MISMATCH_PCT=%d", golden_max_mismatch_pct));
        void'($value$plusargs("GOLDEN_MAX_MAE=%d", golden_max_mae));
        if (out_dir.len() > 0) begin
            out_last_ch = out_dir.getc(out_dir.len() - 1);
            if ((out_last_ch != "/") && (out_last_ch != 8'h5C)) begin
                out_dir = {out_dir, "/"};
            end
        end

        $display("==========================================================");
        $display("  IPU_SOC FULL-FRAME TEST (128x128 BMP)");
        $display("==========================================================");
        $display("Input BMP : %s", img_input);
        $display("Golden BMP: %s", golden_input);
        $display("Output dir: %s", out_dir);

        for (pix = 0; pix < NumPixels; pix = pix + 1) begin
            src_rgb[pix] = 24'd0;
            out_rgb[pix] = 24'd0;
            golden_rgb[pix] = 24'd0;
            cap_dark[pix] = 8'd0;
            cap_sky[pix] = 8'd0;
            cap_tx_core[pix] = 8'd0;
            cap_tx_bank[pix] = 8'd0;
            cap_adc[pix] = 8'd0;
            cap_adc_used[pix] = 8'd0;
            cap_recovery[pix] = 24'd0;
        end

        dark_idx = 0;
        sky_idx = 0;
        tx_idx = 0;
        tx_bank_idx = 0;
        adc_idx = 0;
        rec_used_idx = 0;

        $display("<at time %0t ns> [START] Load input and golden BMP images", $time);
        load_input_bmp();
        load_golden_bmp();
        $display("<at time %0t ns> [START] Reset DUT", $time);
        reset_dut();

        // A) Register programming
        $display("<at time %0t ns> [START] Program IPU registers", $time);
        reg_write(`IPU_SRC_ADDR,  `IMG_IN_BUF_BASE);
        reg_write(`IPU_DST_ADDR,  `IMG_OUT_BUF_BASE);
        reg_write(`IPU_TMP_ADDR,  `IMG_TMP_BUF_BASE);
        reg_write(`IPU_IMG_WIDTH,  ImgWidth);
        reg_write(`IPU_IMG_HEIGHT, ImgHeight);
        reg_write(`IPU_IMG_STRIDE, ImgWidth * 4);
        reg_write(`IPU_IRQ_EN, 32'h1);

        // B) Input buffer write/read sanity
        $display("<at time %0t ns> [START] Write input image to buffer", $time);
        write_img_in_buf();
        sanity_check_img_in();

        // Optional TMP debug write/read smoke check (SoC spirit)
        @(posedge clk);
        img_tmp_sys_en    <= 1'b1;
        img_tmp_sys_we    <= 1'b1;
        img_tmp_sys_addr  <= 16'd0;
        img_tmp_sys_wdata <= 32'hCAFE_BABE;
        @(posedge clk);
        img_tmp_sys_we    <= 1'b0;
        @(posedge clk);
        @(posedge clk);
        if (img_tmp_sys_rdata !== 32'hCAFE_BABE) begin
            $fatal(1, "IMG_TMP smoke check failed");
        end
        img_tmp_sys_en <= 1'b0;

        // C) Start and wait done/IRQ
        $display("<at time %0t ns> [START] Run IPU processing until IRQ", $time);
        reg_write(`IPU_CTRL, 32'h3); // EN + START
        reg_write(`IPU_CTRL, 32'h1); // keep EN

        timeout = 0;
        while (!ipu_irq && (timeout < (NumPixels * 80))) begin
            @(posedge clk);
            timeout = timeout + 1;
        end

        if (!ipu_irq) begin
            $fatal(1, "ipu_irq timeout");
        end

        reg_read(`IPU_STATUS, reg_wdata);
        $display("IPU_STATUS = 0x%08h", reg_wdata);

        // D) Read output and compare golden
        read_img_out_buf();

        $display("  dark captured     : %0d pixels", dark_idx);
        $display("  sky captured      : %0d pixels", sky_idx);
        $display("  tx_core captured  : %0d pixels", tx_idx);
        $display("  tx_bank captured  : %0d pixels", tx_bank_idx);
        $display("  adc captured      : %0d pixels", adc_idx);
        $display("  adc_used captured : %0d pixels", rec_used_idx);

        if (tx_bank_idx > 0) begin
            for (pix = tx_bank_idx; pix < NumPixels; pix = pix + 1) begin
                cap_tx_bank[pix] = cap_tx_bank[tx_bank_idx - 1];
            end
        end

        if (adc_idx > 0) begin
            for (pix = adc_idx; pix < NumPixels; pix = pix + 1) begin
                cap_adc[pix] = cap_adc[adc_idx - 1];
            end
        end

        if (rec_used_idx > 0) begin
            for (pix = rec_used_idx; pix < NumPixels; pix = pix + 1) begin
                cap_adc_used[pix] = cap_adc_used[rec_used_idx - 1];
            end
        end

        $display("\n--- Saving BMP images ---");
        save_rgb_bmp("ipu_soc_src_128.bmp", src_rgb);
        save_gray_bmp("ipu_soc_dark_128.bmp", cap_dark, 1'b0);
        save_gray_bmp("ipu_soc_sky_128.bmp", cap_sky, 1'b0);
        save_gray_bmp("ipu_soc_tx_core_128.bmp", cap_tx_core, 1'b1);
        save_gray_bmp("ipu_soc_tx_bank_128.bmp", cap_tx_bank, 1'b1);
        save_gray_bmp("ipu_soc_adc_128.bmp", cap_adc, 1'b1);
        save_gray_bmp("ipu_soc_adc_used_128.bmp", cap_adc_used, 1'b1);
        save_recovery_bmp("ipu_soc_recovery_128.bmp", cap_recovery);

        save_gray_bmp("ipu_soc_tx_core_raw_128.bmp", cap_tx_core, 1'b0);
        save_gray_bmp("ipu_soc_tx_bank_raw_128.bmp", cap_tx_bank, 1'b0);
        save_gray_bmp("ipu_soc_adc_raw_128.bmp", cap_adc, 1'b0);
        save_gray_bmp("ipu_soc_adc_used_raw_128.bmp", cap_adc_used, 1'b0);

        compare_with_golden();

        $display("\nPASS: IPU_SOC test completed successfully.\n");
        $finish;
    end

endmodule
