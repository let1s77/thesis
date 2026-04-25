`timescale 1ns/1ps

module haze_removal_top_128_tb;

    localparam int ImgWidth  = 128;
    localparam int ImgHeight = 128;
    localparam int NumPixels = ImgWidth * ImgHeight;
    localparam int AdcWarmupSamples = ImgWidth * 4;
    localparam int AdcTargetPixels = NumPixels - AdcWarmupSamples;
    localparam int AddrWidth = 14;
    localparam int HalfClk   = 5;

    logic clk;
    logic rst_n;

    logic        i_src_valid;
    logic        i_src_frame_start;
    logic        i_src_frame_end;
    logic [23:0] i_src_rgb;

    logic        dark_enable;
    logic        sky_enable;
    logic        trans_enable;
    logic        adc_enable;
    logic        recovery_enable;

    logic        bank_swap;
    logic        bank_wr_clear;
    logic        bank_rd_clear;
    logic        bank_rd_en;

    logic        dark_done;
    logic        sky_done;
    logic        trans_done;
    logic        adc_done;
    logic        recovery_done;

    logic        post_frame_vsync;
    logic        post_frame_href;
    logic        post_frame_clken;
    logic [23:0] post_img;

    logic [23:0] rgb_mem [NumPixels];
    logic [7:0]  bmp_header [54];

    logic [7:0]  cap_dark [NumPixels];
    logic [7:0]  cap_sky [NumPixels];
    logic [7:0]  cap_tx_core [NumPixels];
    logic [7:0]  cap_tx_bank [NumPixels];
    logic [7:0]  cap_adc [NumPixels];
    logic [7:0]  cap_adc_used [NumPixels];
    logic [23:0] cap_recovery [NumPixels];

    integer dark_idx;
    integer sky_idx;
    integer tx_idx;
    integer tx_bank_idx;
    integer adc_idx;
    integer adc_seen_count;
    integer rec_idx;
    bit tx_bank_warmup_done;

    integer fp_in;
    integer obmp;
    integer timeout;
    integer pix;
    logic [7:0] rd_byte;

    string img_input;
    string out_dir;
    string img_arg;
    string out_arg;

    task automatic log_start(input string test_name);
    begin
        $display("<at time %0t ns> [START] %s", $time, test_name);
    end
    endtask

    initial clk = 1'b0;
    always #HalfClk clk = ~clk;

    haze_removal_top #(
        .IMG_WIDTH (ImgWidth),
        .IMG_HEIGHT(ImgHeight),
        .ADDR_WIDTH(AddrWidth)
    ) dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .i_src_valid      (i_src_valid),
        .i_src_frame_start(i_src_frame_start),
        .i_src_frame_end  (i_src_frame_end),
        .i_src_rgb        (i_src_rgb),
        .dark_enable      (dark_enable),
        .sky_enable       (sky_enable),
        .trans_enable     (trans_enable),
        .adc_enable       (adc_enable),
        .recovery_enable  (recovery_enable),
        .bank_swap        (bank_swap),
        .bank_wr_clear    (bank_wr_clear),
        .bank_rd_clear    (bank_rd_clear),
        .bank_rd_en       (bank_rd_en),
        .dark_done        (dark_done),
        .sky_done         (sky_done),
        .trans_done       (trans_done),
        .adc_done         (adc_done),
        .recovery_done    (recovery_done),
        .post_frame_vsync (post_frame_vsync),
        .post_frame_href  (post_frame_href),
        .post_frame_clken (post_frame_clken),
        .post_img         (post_img)
    );

    task automatic clear_controls;
    begin
        i_src_valid       = 1'b0;
        i_src_frame_start = 1'b0;
        i_src_frame_end   = 1'b0;
        i_src_rgb         = 24'd0;

        dark_enable       = 1'b0;
        sky_enable        = 1'b0;
        trans_enable      = 1'b0;
        adc_enable        = 1'b0;
        recovery_enable   = 1'b0;

        bank_swap         = 1'b0;
        bank_wr_clear     = 1'b0;
        bank_rd_clear     = 1'b0;
        bank_rd_en        = 1'b0;
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

    task automatic drive_frame;
    begin
        for (pix = 0; pix < NumPixels; pix = pix + 1) begin
            @(posedge clk);
            i_src_valid       <= 1'b1;
            i_src_frame_start <= (pix == 0);
            i_src_frame_end   <= (pix == NumPixels - 1);
            i_src_rgb         <= rgb_mem[pix];
        end

        @(posedge clk);
        i_src_valid       <= 1'b0;
        i_src_frame_start <= 1'b0;
        i_src_frame_end   <= 1'b0;
        i_src_rgb         <= 24'd0;
    end
    endtask

    task automatic load_bmp;
    begin
        fp_in = $fopen(img_input, "rb");
        if (!fp_in) begin
            $fatal(1, "Cannot open input BMP: %s", img_input);
        end

        for (pix = 0; pix < 54; pix = pix + 1) begin
            bmp_header[pix] = $fgetc(fp_in);
        end

        // For 128x128x24bpp, row stride is 384 bytes (no padding bytes).
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
    end
    endtask

    task automatic save_gray_bmp(
        input string name,
        input logic [7:0] map [NumPixels],
        input bit use_robust_stretch
    );
        integer hist [256];
        integer cum;
        integer low_cut;
        integer high_cut;
        integer lo;
        integer hi;
        integer v;
        integer outv;
    begin
        obmp = $fopen({out_dir, name}, "wb");
        if (!obmp) begin
            $fatal(1, "Cannot open output BMP: %s%s", out_dir, name);
        end

        for (pix = 0; pix < 54; pix = pix + 1) begin
            $fwrite(obmp, "%c", bmp_header[pix]);
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
                $fwrite(obmp, "%c", outv[7:0]);
                $fwrite(obmp, "%c", outv[7:0]);
                $fwrite(obmp, "%c", outv[7:0]);
            end
        end else begin
            for (pix = 0; pix < NumPixels; pix = pix + 1) begin
                $fwrite(obmp, "%c", map[pix]);
                $fwrite(obmp, "%c", map[pix]);
                $fwrite(obmp, "%c", map[pix]);
            end
        end

        $fclose(obmp);
        $display("  Saved: %s%s", out_dir, name);
    end
    endtask

    task automatic save_rgb_bmp(input string name, input logic [23:0] map [NumPixels]);
    begin
        obmp = $fopen({out_dir, name}, "wb");
        if (!obmp) begin
            $fatal(1, "Cannot open output BMP: %s%s", out_dir, name);
        end

        for (pix = 0; pix < 54; pix = pix + 1) begin
            $fwrite(obmp, "%c", bmp_header[pix]);
        end

        // map stores BGR in [23:16],[15:8],[7:0] for source image.
        for (pix = 0; pix < NumPixels; pix = pix + 1) begin
            $fwrite(obmp, "%c", map[pix][23:16]);
            $fwrite(obmp, "%c", map[pix][15:8]);
            $fwrite(obmp, "%c", map[pix][7:0]);
        end

        $fclose(obmp);
        $display("  Saved: %s%s", out_dir, name);
    end
    endtask

    task automatic save_recovery_bmp(input string name, input logic [23:0] map [NumPixels]);
    begin
        obmp = $fopen({out_dir, name}, "wb");
        if (!obmp) begin
            $fatal(1, "Cannot open output BMP: %s%s", out_dir, name);
        end

        for (pix = 0; pix < 54; pix = pix + 1) begin
            $fwrite(obmp, "%c", bmp_header[pix]);
        end

        // post_img is {R,G,B}; BMP needs byte order B,G,R.
        for (pix = 0; pix < NumPixels; pix = pix + 1) begin
            $fwrite(obmp, "%c", map[pix][7:0]);
            $fwrite(obmp, "%c", map[pix][15:8]);
            $fwrite(obmp, "%c", map[pix][23:16]);
        end

        $fclose(obmp);
        $display("  Saved: %s%s", out_dir, name);
    end
    endtask

    always @(posedge clk) begin
        if (rst_n) begin
            if (dark_enable && dut.u_core.purple_dark_valid && (dark_idx < NumPixels)) begin
                cap_dark[dark_idx] <= dut.u_core.purple_dark_ch;
                dark_idx <= dark_idx + 1;
            end

            if (trans_enable && dut.u_core.purple_sky_valid && (sky_idx < NumPixels)) begin
                cap_sky[sky_idx] <= (dut.u_core.purple_sky ? 8'hFF : 8'h00);
                sky_idx <= sky_idx + 1;
            end

            if (trans_enable && dut.u_core.purple_tx_valid && (tx_idx < NumPixels)) begin
                cap_tx_core[tx_idx] <= dut.u_core.purple_tx;
                tx_idx <= tx_idx + 1;
            end

            if (adc_enable && bank_rd_en) begin
                if (!tx_bank_warmup_done) begin
                    tx_bank_warmup_done <= 1'b1;
                end else if (tx_bank_idx < NumPixels) begin
                    cap_tx_bank[tx_bank_idx] <= dut.u_core.bank_rd_data;
                    tx_bank_idx <= tx_bank_idx + 1;
                end
            end

            if (adc_enable && dut.u_core.adc_out_valid) begin
                if ((adc_seen_count >= AdcWarmupSamples) && (adc_idx < AdcTargetPixels)) begin
                    cap_adc[adc_idx] <= dut.u_core.adc_out_pix;
                    adc_idx <= adc_idx + 1;
                end
                adc_seen_count <= adc_seen_count + 1;
            end

            if (recovery_enable && i_src_valid && (rec_idx < NumPixels)) begin
                cap_adc_used[rec_idx] <= dut.u_core.adc_dark_for_recovery;
            end

            if (recovery_enable && post_frame_clken && (rec_idx < NumPixels)) begin
                cap_recovery[rec_idx] <= post_img;
                rec_idx <= rec_idx + 1;
            end
        end
    end

    initial begin
        img_input = "../01_sim/IPU/Testbench_DarkChannel_System/sim/image/test_128.bmp";
        out_dir   = "../01_sim/IPU/Testbench_HAZE_REMOVAL_TOP/sim/image/";

        if ($value$plusargs("IMG_IN=%s", img_arg)) begin
            img_input = img_arg;
        end
        if ($value$plusargs("OUT_DIR=%s", out_arg)) begin
            out_dir = out_arg;
        end

        $display("==========================================================");
        $display("  HAZE_REMOVAL_TOP FULL-FRAME TEST (128x128 BMP)");
        $display("==========================================================");
        $display("Input BMP : %s", img_input);
        $display("Output dir: %s", out_dir);

        log_start("Load BMP and initialize buffers");
        load_bmp();

        for (pix = 0; pix < NumPixels; pix = pix + 1) begin
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
        adc_seen_count = 0;
        rec_idx = 0;
        tx_bank_warmup_done = 1'b0;

        reset_dut();

        // DARK phase
        log_start("Phase DARK");
        $display("\n--- Phase DARK ---");
        dark_enable <= 1'b1;
        fork
            begin
                drive_frame();
                repeat (4) @(posedge clk);
                dark_enable <= 1'b0;
            end
            begin
                timeout = 0;
                while (!dark_done && timeout < (NumPixels * 4)) begin
                    @(posedge clk);
                    timeout = timeout + 1;
                end
                if (!dark_done) begin
                    $fatal(1, "dark_done timeout");
                end
            end
        join
        $display("  dark captured: %0d pixels", dark_idx);

        // SKY pulse
        @(posedge clk);
        sky_enable <= 1'b1;
        @(posedge clk);
        sky_enable <= 1'b0;

        // TRANS phase
        log_start("Phase TRANS");
        $display("\n--- Phase TRANS ---");
        fork
            begin
                @(posedge clk);
                bank_wr_clear <= 1'b1;
                trans_enable <= 1'b1;
                @(posedge clk);
                bank_wr_clear <= 1'b0;
                drive_frame();
                repeat (4) @(posedge clk);
                trans_enable <= 1'b0;
            end
            begin
                timeout = 0;
                while (!trans_done && timeout < (NumPixels * 4)) begin
                    @(posedge clk);
                    timeout = timeout + 1;
                end
                if (!trans_done) begin
                    $fatal(1, "trans_done timeout");
                end
            end
        join
        $display("  sky captured     : %0d pixels", sky_idx);
        $display("  tx_core captured : %0d pixels", tx_idx);

        // ADC phase + tx bank read capture
        log_start("Phase ADC");
        $display("\n--- Phase ADC ---");
        @(posedge clk);
        adc_enable    <= 1'b1;
        bank_rd_en    <= 1'b0;
        bank_swap     <= 1'b1;
        bank_rd_clear <= 1'b1;

        @(posedge clk);
        bank_swap     <= 1'b0;
        bank_rd_en    <= 1'b1;
        bank_rd_clear <= 1'b1;

        @(posedge clk);
        bank_rd_clear <= 1'b0;

        timeout = 0;
         while (((tx_bank_idx < NumPixels) || (adc_idx < AdcTargetPixels)) &&
             (timeout < (NumPixels * 8))) begin
            @(posedge clk);
            timeout = timeout + 1;
        end

        adc_enable <= 1'b0;
        bank_rd_en <= 1'b0;

        $display("  tx_bank captured : %0d pixels", tx_bank_idx);
        $display("  adc captured     : %0d pixels", adc_idx);

        // Extend shortened ADC debug stream to full frame so visualization
        // has no black stripe caused by warm-up trimming.
        if (adc_idx > 0) begin
            for (pix = adc_idx; pix < NumPixels; pix = pix + 1) begin
                cap_adc[pix] = cap_adc[adc_idx - 1];
            end
        end

        // RECOVERY phase
        log_start("Phase RECOVERY");
        $display("\n--- Phase RECOVERY ---");
        recovery_enable <= 1'b1;
        fork
            begin
                drive_frame();
                repeat (4) @(posedge clk);
                recovery_enable <= 1'b0;
            end
            begin
                timeout = 0;
                while ((rec_idx < NumPixels) && (timeout < (NumPixels * 8))) begin
                    @(posedge clk);
                    timeout = timeout + 1;
                end
                if (rec_idx < NumPixels) begin
                    $display("WARN: recovery captured %0d/%0d pixels", rec_idx, NumPixels);
                end
            end
        join
        $display("  recovery captured: %0d pixels", rec_idx);

        // Save images like Purple Integration style
        log_start("Save output BMP images");
        $display("\n--- Saving BMP images ---");
        save_rgb_bmp("haze_src_128.bmp", rgb_mem);
        save_gray_bmp("haze_dark_128.bmp", cap_dark, 1'b0);
        save_gray_bmp("haze_sky_128.bmp", cap_sky, 1'b0);
        save_gray_bmp("haze_tx_core_128.bmp", cap_tx_core, 1'b1);
        save_gray_bmp("haze_tx_bank_128.bmp", cap_tx_bank, 1'b1);
        save_gray_bmp("haze_adc_128.bmp", cap_adc, 1'b1);
        save_gray_bmp("haze_adc_used_128.bmp", cap_adc_used, 1'b1);

        // Keep raw debug versions for algorithm-level inspection.
        save_gray_bmp("haze_tx_core_raw_128.bmp", cap_tx_core, 1'b0);
        save_gray_bmp("haze_tx_bank_raw_128.bmp", cap_tx_bank, 1'b0);
        save_gray_bmp("haze_adc_raw_128.bmp", cap_adc, 1'b0);
        save_gray_bmp("haze_adc_used_raw_128.bmp", cap_adc_used, 1'b0);
        save_recovery_bmp("haze_recovery_128.bmp", cap_recovery);

        $display("\nDone. Check images in: %s\n", out_dir);
        $finish;
    end

endmodule

