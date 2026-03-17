`timescale 1ns/1ps
`define CYCLE 10.0
`define NUM_CASES 20
`define FRAME_PIXELS 25

module haze_removal_top_phase_tb;

    bit clk;
    always #(`CYCLE/2) clk = ~clk;

    logic        rst_n;

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

    reg [23:0] pat_rgb [`NUM_CASES*`FRAME_PIXELS];

    integer i;
    integer p;
    integer base;
    integer timeout;

    string pat_path;
    string pat_arg;
    string dump_root;
    string image_root;

    reg [23:0] src_rgb_map [`FRAME_PIXELS];
    reg [7:0]  dark_map    [`FRAME_PIXELS];
    reg [7:0]  sky_map     [`FRAME_PIXELS];
    reg [7:0]  tx_map      [`FRAME_PIXELS];
    reg [7:0]  tx_bank_map [`FRAME_PIXELS];
    reg [23:0] rec_rgb_map [`FRAME_PIXELS];

    reg [7:0] adc_stream [8];
    integer adc_stream_count;

    integer src_idx;
    integer dark_idx;
    integer sky_idx;
    integer tx_idx;
    integer tx_bank_idx;
    integer rec_idx;

    bit dark_mon_run;
    bit trans_mon_run;
    bit tx_bank_warmup_done;

    haze_removal_top #(
        .IMG_WIDTH (5),
        .IMG_HEIGHT(5),
        .ADDR_WIDTH(5)
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
        dark_enable        = 1'b0;
        sky_enable         = 1'b0;
        trans_enable       = 1'b0;
        adc_enable         = 1'b0;
        recovery_enable    = 1'b0;
        bank_swap          = 1'b0;
        bank_wr_clear      = 1'b0;
        bank_rd_clear      = 1'b0;
        bank_rd_en         = 1'b0;
        i_src_valid        = 1'b0;
        i_src_frame_start  = 1'b0;
        i_src_frame_end    = 1'b0;
        i_src_rgb          = 24'd0;
    end
    endtask

    task automatic drive_frame(input integer base_idx);
    begin
        for (p = 0; p < `FRAME_PIXELS; p = p + 1) begin
            @(posedge clk);
            i_src_valid       <= 1'b1;
            i_src_frame_start <= (p == 0);
            i_src_frame_end   <= (p == `FRAME_PIXELS-1);
            i_src_rgb         <= pat_rgb[base_idx + p];
        end

        @(posedge clk);
        i_src_valid       <= 1'b0;
        i_src_frame_start <= 1'b0;
        i_src_frame_end   <= 1'b0;
        i_src_rgb         <= 24'd0;
    end
    endtask

    task automatic resolve_existing_data_path(
        output string resolved,
        input  string preferred,
        input  string cand0,
        input  string cand1
    );
        integer f0;
    begin
        resolved = "";

        if (preferred != "") begin
            f0 = $fopen(preferred, "r");
            if (f0) begin
                resolved = preferred;
                $fclose(f0);
                return;
            end
        end

        f0 = $fopen(cand0, "r");
        if (f0) begin
            resolved = cand0;
            $fclose(f0);
            return;
        end

        f0 = $fopen(cand1, "r");
        if (f0) begin
            resolved = cand1;
            $fclose(f0);
            return;
        end
    end
    endtask

    task automatic dump_u8_map(input string file_path, input reg [7:0] map [`FRAME_PIXELS]);
        integer fd;
        integer k;
    begin
        fd = $fopen(file_path, "w");
        if (!fd) begin
            $display("WARN: cannot open %s", file_path);
            return;
        end
        for (k = 0; k < `FRAME_PIXELS; k = k + 1) begin
            $fwrite(fd, "%02X\n", map[k]);
        end
        $fclose(fd);
    end
    endtask

    task automatic dump_rgb_map(input string file_path, input reg [23:0] map [`FRAME_PIXELS]);
        integer fd;
        integer k;
    begin
        fd = $fopen(file_path, "w");
        if (!fd) begin
            $display("WARN: cannot open %s", file_path);
            return;
        end
        for (k = 0; k < `FRAME_PIXELS; k = k + 1) begin
            $fwrite(fd, "%06X\n", map[k]);
        end
        $fclose(fd);
    end
    endtask

    task automatic dump_case(input integer case_id);
        string f_src;
        string f_dark;
        string f_sky;
        string f_tx;
        string f_tx_bank;
        string f_rec;
        string f_meta;
        integer fd;
        integer k;
    begin
        f_src     = $sformatf("%s/case_%0d_src_rgb.hex", dump_root, case_id);
        f_dark    = $sformatf("%s/case_%0d_dark_u8.hex", dump_root, case_id);
        f_sky     = $sformatf("%s/case_%0d_sky_u8.hex", dump_root, case_id);
        f_tx      = $sformatf("%s/case_%0d_tx_u8.hex", dump_root, case_id);
        f_tx_bank = $sformatf("%s/case_%0d_tx_bank_u8.hex", dump_root, case_id);
        f_rec     = $sformatf("%s/case_%0d_recovery_rgb.hex", dump_root, case_id);
        f_meta    = $sformatf("%s/case_%0d_adc_info.txt", dump_root, case_id);

        dump_rgb_map(f_src, src_rgb_map);
        dump_u8_map(f_dark, dark_map);
        dump_u8_map(f_sky, sky_map);
        dump_u8_map(f_tx, tx_map);
        dump_u8_map(f_tx_bank, tx_bank_map);
        dump_rgb_map(f_rec, rec_rgb_map);

        fd = $fopen(f_meta, "w");
        if (!fd) begin
            $display("WARN: cannot open %s", f_meta);
            return;
        end
        $fwrite(fd, "case_id=%0d\n", case_id);
        $fwrite(fd, "A_rgb=%02X,%02X,%02X\n",
            dut.u_core.purple_A_r,
            dut.u_core.purple_A_g,
            dut.u_core.purple_A_b);
        $fwrite(fd, "adc_dark_hold=%02X\n", dut.u_core.adc_dark_hold);
        $fwrite(fd, "adc_latched_index=%0d\n", dut.u_core.adc_latched_index);
        $fwrite(fd, "adc_out_count=%0d\n", dut.u_core.adc_out_index);
        $fwrite(fd, "adc_stream_count=%0d\n", adc_stream_count);
        for (k = 0; k < adc_stream_count; k = k + 1) begin
            $fwrite(fd, "adc_stream[%0d]=%02X\n", k, adc_stream[k]);
        end
        $fclose(fd);
    end
    endtask

    initial begin
        clk = 1'b0;
        clear_controls();

        if (!$value$plusargs("PATTERN_FILE=%s", pat_arg)) pat_arg = "";
        if (!$value$plusargs("DUMP_DIR=%s", dump_root)) begin
            dump_root = "../01_sim/IPU/Testbench_HAZE_REMOVAL_TOP/sim/output";
        end

        resolve_existing_data_path(
            pat_path,
            pat_arg,
            "../09_pattern/pattern_haze_removal_top_rgb5x5.hex",
            "../../09_pattern/pattern_haze_removal_top_rgb5x5.hex"
        );

        if (pat_path == "") begin
            $fatal(1, "Cannot open haze_removal_top RGB pattern file");
        end

        image_root = "../01_sim/IPU/Testbench_HAZE_REMOVAL_TOP/sim/image";
        $display("Pattern file: %s", pat_path);
        $display("Dump dir    : %s", dump_root);
        $display("Image dir   : %s", image_root);
        $display("NOTE: This TB expects 24-bit RGB stream (6 hex digits per line)");
        $display("      and total %0d lines (%0d cases x %0d pixels).",
                 `NUM_CASES*`FRAME_PIXELS, `NUM_CASES, `FRAME_PIXELS);

        $readmemh(pat_path, pat_rgb);

        if ($isunknown(pat_rgb[0]) || $isunknown(pat_rgb[`NUM_CASES*`FRAME_PIXELS-1])) begin
            $display("ERROR: Pattern format/length mismatch for 24-bit RGB stream TB.");
            $display("  - Expected file example: pattern_haze_removal_top_rgb5x5.hex");
            $display("  - Wrong for this TB: packed-case line format (ex: 20 hex digits/line)");
            $display("  - Given +PATTERN_FILE: %s", pat_path);
            $fatal(1, "Invalid pattern file for haze_removal_top_phase_tb");
        end

        rst_n = 1'b0;
        #(`CYCLE*3);
        rst_n = 1'b1;

        for (i = 0; i < `NUM_CASES; i = i + 1) begin
            @(posedge clk);
            rst_n <= 1'b0;
            clear_controls();
            repeat (2) @(posedge clk);
            rst_n <= 1'b1;
            @(posedge clk);

            base = i * `FRAME_PIXELS;

            for (p = 0; p < `FRAME_PIXELS; p = p + 1) begin
                src_rgb_map[p] = {
                    pat_rgb[base+p][7:0],
                    pat_rgb[base+p][15:8],
                    pat_rgb[base+p][23:16]
                };
                dark_map[p]    = 8'd0;
                sky_map[p]     = 8'd0;
                tx_map[p]      = 8'd0;
                tx_bank_map[p] = 8'd0;
                rec_rgb_map[p] = 24'd0;
            end
            for (p = 0; p < 8; p = p + 1) adc_stream[p] = 8'd0;

            dark_idx = 0;
            sky_idx = 0;
            tx_idx = 0;
            tx_bank_idx = 0;
            rec_idx = 0;
            adc_stream_count = 0;
            tx_bank_warmup_done = 1'b0;

            // DARK phase
            dark_enable = 1'b1;
            dark_mon_run = 1'b1;
            fork
                begin
                    drive_frame(base);
                    repeat (4) @(posedge clk);
                    dark_enable = 1'b0;
                    dark_mon_run = 1'b0;
                end
                begin
                    timeout = 0;
                    while (!dark_done && timeout < 500) begin
                        @(posedge clk);
                        timeout = timeout + 1;
                    end
                end
                begin
                    while (dark_mon_run) begin
                        @(posedge clk);
                        if (dut.u_core.purple_dark_valid && dark_idx < `FRAME_PIXELS) begin
                            dark_map[dark_idx] = dut.u_core.purple_dark_ch;
                            dark_idx = dark_idx + 1;
                        end
                    end
                end
            join

            // SKY pulse
            @(posedge clk);
            sky_enable <= 1'b1;
            @(posedge clk);
            sky_enable <= 1'b0;

            // TRANS phase
            trans_enable = 1'b1;
            bank_wr_clear = 1'b1;
            trans_mon_run = 1'b1;
            fork
                begin
                    @(posedge clk);
                    bank_wr_clear = 1'b0;
                    drive_frame(base);
                    repeat (4) @(posedge clk);
                    trans_enable = 1'b0;
                    trans_mon_run = 1'b0;
                end
                begin
                    timeout = 0;
                    while (!trans_done && timeout < 900) begin
                        @(posedge clk);
                        timeout = timeout + 1;
                    end
                end
                begin
                    while (trans_mon_run) begin
                        @(posedge clk);
                        if (dut.u_core.purple_sky_valid && sky_idx < `FRAME_PIXELS) begin
                            sky_map[sky_idx] = dut.u_core.purple_sky ? 8'hFF : 8'h00;
                            sky_idx = sky_idx + 1;
                        end
                        if (dut.u_core.purple_tx_valid && tx_idx < `FRAME_PIXELS) begin
                            tx_map[tx_idx] = dut.u_core.purple_tx;
                            tx_idx = tx_idx + 1;
                        end
                    end
                end
            join

            // ADC phase
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
            while (!adc_done && timeout < 4000) begin
                @(posedge clk);
                timeout = timeout + 1;

                if (bank_rd_en) begin
                    if (!tx_bank_warmup_done) begin
                        tx_bank_warmup_done = 1'b1;
                    end else if (tx_bank_idx < `FRAME_PIXELS) begin
                        tx_bank_map[tx_bank_idx] = dut.u_core.bank_rd_data;
                        tx_bank_idx = tx_bank_idx + 1;
                    end
                end

                if (dut.u_core.adc_out_valid && adc_stream_count < 8) begin
                    adc_stream[adc_stream_count] = dut.u_core.adc_out_pix;
                    adc_stream_count = adc_stream_count + 1;
                end
            end

            adc_enable <= 1'b0;
            bank_rd_en <= 1'b0;

            // RECOVERY phase
            recovery_enable = 1'b1;
            fork
                begin
                    drive_frame(base);
                    repeat (4) @(posedge clk);
                    recovery_enable = 1'b0;
                end
                begin
                    timeout = 0;
                    while (rec_idx < `FRAME_PIXELS && timeout < 2000) begin
                        @(posedge clk);
                        timeout = timeout + 1;
                        if (post_frame_clken && rec_idx < `FRAME_PIXELS) begin
                            rec_rgb_map[rec_idx] = post_img;
                            rec_idx = rec_idx + 1;
                        end
                    end
                end
            join

            dump_case(i);
            $display("[DUMP] case=%0d saved to %s", i, dump_root);
        end

        $display("\nAll case dumps completed.\n");
        $display("HEX dumps saved at: %s", dump_root);
        $display("To export BMP images run:");
        $display("  python export_phase_images.py");
        $display("  --input %s", dump_root);
        $display("  --output %s", image_root);
        $finish;
    end

endmodule

