//==============================================================================
// Testbench: haze_removal_top_tb
// Description:
//   Top-level integration test for haze_removal_top using software-generated
//   5x5 RGB patterns and final golden outputs.
//
// Files:
//   Pattern RGB  : ../09_pattern/pattern_haze_removal_top_rgb5x5.hex
//   Golden final : ../07_golden_output/golden_haze_removal_top.hex
//
// Notes:
// - One test case = one 5x5 frame (25 pixels)
// - Compare recovery output at center pixel index (12) vs golden out RGB
//==============================================================================

`timescale 1ns/1ps
`define CYCLE 10.0
`define NUM_CASES 20
`define FRAME_PIXELS 25

module haze_removal_top_tb;

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
    reg [47:0] gld_final [`NUM_CASES];
    reg [7:0]  gld_tx5x5 [`NUM_CASES*`FRAME_PIXELS];
    reg [7:0]  gld_adc [`NUM_CASES];

    integer i;
    integer p;
    integer base;
    integer err;
    integer timeout;
    integer fd;

    integer rec_count;
    integer tx_cmp_idx;
    integer tx_mismatch_cnt;
    integer adc_obs_idx;
    integer adc_match_idx;
    bit     tx_first_mismatch_printed;
    bit     tx_cmp_warmup_done;
    bit x_seen;
    reg [7:0] cap_r;
    reg [7:0] cap_g;
    reg [7:0] cap_b;

    string pat_path;
    string gld_path;
    string gld_tx_path;
    string gld_adc_path;
    string pat_arg;
    string gld_arg;
    string gld_tx_arg;
    string gld_adc_arg;

    reg [7:0] exp_case_id;
    reg [7:0] exp_tx_raw;
    reg [7:0] exp_tx_used;
    reg [7:0] exp_r;
    reg [7:0] exp_g;
    reg [7:0] exp_b;

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

    task automatic wait_done_pulse(
        ref   logic sig,
        input integer max_cycles,
        output bit seen
    );
        integer cyc;
    begin
        seen = 1'b0;
        for (cyc = 0; cyc < max_cycles; cyc = cyc + 1) begin
            @(posedge clk);
            if (sig) begin
                seen = 1'b1;
                return;
            end
        end
    end
    endtask

    task automatic trace_first_x(input integer case_id, input string phase_name);
    begin
        if (x_seen) begin
            return;
        end

        if ($isunknown(dut.bank_rd_data) && bank_rd_en) begin
            $display("  X-TRACE case=%0d phase=%s sig=dut.bank_rd_data", case_id, phase_name);
            x_seen = 1'b1;
        end else if ($isunknown(dut.adc_out_pix) && dut.adc_out_valid) begin
            $display("  X-TRACE case=%0d phase=%s sig=dut.adc_out_pix", case_id, phase_name);
            x_seen = 1'b1;
        end else if ($isunknown(dut.adc_dark_hold)) begin
            $display("  X-TRACE case=%0d phase=%s sig=dut.adc_dark_hold", case_id, phase_name);
            x_seen = 1'b1;
        end else if ($isunknown(dut.purple_A_r)) begin
            $display("  X-TRACE case=%0d phase=%s sig=dut.purple_A_r", case_id, phase_name);
            x_seen = 1'b1;
        end else if ($isunknown(dut.u_t_compute_fuse.tx_raw_s1)) begin
            $display(
                "  X-TRACE case=%0d phase=%s sig=dut.u_t_compute_fuse.tx_raw_s1",
                case_id,
                phase_name
            );
            x_seen = 1'b1;
        end else if ($isunknown({dut.tcf_r, dut.tcf_g, dut.tcf_b}) && dut.tcf_valid) begin
            $display("  X-TRACE case=%0d phase=%s sig=dut.tcf_rgb", case_id, phase_name);
            x_seen = 1'b1;
        end else if ($isunknown(post_img) && post_frame_clken) begin
            $display("  X-TRACE case=%0d phase=%s sig=post_img", case_id, phase_name);
            x_seen = 1'b1;
        end
    end
    endtask

    task automatic resolve_existing_data_path(
        output string resolved,
        input  string preferred,
        input  string cand0,
        input  string cand1
    );
        integer f;
    begin
        resolved = "";

        if (preferred != "") begin
            f = $fopen(preferred, "r");
            if (f != 0) begin
                $fclose(f);
                resolved = preferred;
                return;
            end
        end

        f = $fopen(cand0, "r");
        if (f != 0) begin
            $fclose(f);
            resolved = cand0;
            return;
        end

        f = $fopen(cand1, "r");
        if (f != 0) begin
            $fclose(f);
            resolved = cand1;
            return;
        end
    end
    endtask

    initial begin
        clk = 1'b0;
        err = 0;

        pat_arg = "";
        gld_arg = "";
        gld_tx_arg = "";
        gld_adc_arg = "";
        void'($value$plusargs("PATTERN_FILE=%s", pat_arg));
        void'($value$plusargs("GOLDEN_FILE=%s", gld_arg));
        void'($value$plusargs("GOLDEN_TX_FILE=%s", gld_tx_arg));
        void'($value$plusargs("GOLDEN_ADC_FILE=%s", gld_adc_arg));

        resolve_existing_data_path(
            pat_path,
            pat_arg,
            "../09_pattern/pattern_haze_removal_top_rgb5x5.hex",
            "../../09_pattern/pattern_haze_removal_top_rgb5x5.hex"
        );
        resolve_existing_data_path(
            gld_path,
            gld_arg,
            "../07_golden_output/golden_haze_removal_top.hex",
            "../../07_golden_output/golden_haze_removal_top.hex"
        );
        resolve_existing_data_path(
            gld_tx_path,
            gld_tx_arg,
            "../07_golden_output/golden_haze_removal_top_tx5x5.hex",
            "../../07_golden_output/golden_haze_removal_top_tx5x5.hex"
        );
        resolve_existing_data_path(
            gld_adc_path,
            gld_adc_arg,
            "../07_golden_output/golden_haze_removal_top_adc.hex",
            "../../07_golden_output/golden_haze_removal_top_adc.hex"
        );

        $display("Pattern file: %s", pat_path);
        $display("Golden  file: %s", gld_path);
        $display("Golden tx5x5 : %s", gld_tx_path);
        $display("Golden adc   : %s", gld_adc_path);

        if (pat_path == "") begin
            $display("Tried pattern path from +PATTERN_FILE: %s", pat_arg);
            $display(
                "Tried pattern fallback 1: ../09_pattern/pattern_haze_removal_top_rgb5x5.hex"
            );
            $display(
                "Tried pattern fallback 2: ../../09_pattern/pattern_haze_removal_top_rgb5x5.hex"
            );
            $fatal(1, "Cannot open pattern file");
        end

        if (gld_path == "") begin
            $display("Tried golden path from +GOLDEN_FILE: %s", gld_arg);
            $display("Tried golden fallback 1: ../07_golden_output/golden_haze_removal_top.hex");
            $display(
                "Tried golden fallback 2: ../../07_golden_output/golden_haze_removal_top.hex"
            );
            $fatal(1, "Cannot open golden file");
        end

        if (gld_tx_path == "") begin
            $display("Tried tx5x5 path from +GOLDEN_TX_FILE: %s", gld_tx_arg);
            $display(
                "Tried tx5x5 fallback 1: ../07_golden_output/golden_haze_removal_top_tx5x5.hex"
            );
            $display(
                "Tried tx5x5 fallback 2: ../../07_golden_output/golden_haze_removal_top_tx5x5.hex"
            );
            $fatal(1, "Cannot open golden tx5x5 file");
        end

        if (gld_adc_path == "") begin
            $display("Tried adc path from +GOLDEN_ADC_FILE: %s", gld_adc_arg);
            $display(
                "Tried adc fallback 1: ../07_golden_output/golden_haze_removal_top_adc.hex"
            );
            $display(
                "Tried adc fallback 2: ../../07_golden_output/golden_haze_removal_top_adc.hex"
            );
            $fatal(1, "Cannot open golden adc file");
        end

        $readmemh(pat_path, pat_rgb);
        $readmemh(gld_path, gld_final);
        $readmemh(gld_tx_path, gld_tx5x5);
        $readmemh(gld_adc_path, gld_adc);

        rst_n = 1'b0;
        clear_controls();

        #(`CYCLE*3);
        rst_n = 1'b1;
        @(posedge clk);

        $display("\n============================================================");
        $display("  HAZE_REMOVAL_TOP TB (5x5 frame, %0d cases)", `NUM_CASES);
        $display("============================================================\n");
        $display("<at time %0t ns> [START] Load patterns and reset", $time);

        for (i = 0; i < `NUM_CASES; i = i + 1) begin
            bit dark_seen;
            bit trans_seen;

            // Clear internal pipeline/buffer states between cases.
            clear_controls();
            rst_n <= 1'b0;
            repeat (3) @(posedge clk);
            rst_n <= 1'b1;
            @(posedge clk);

            base = i * `FRAME_PIXELS;

            exp_case_id = gld_final[i][47:40];
            exp_tx_raw  = gld_final[i][39:32];
            exp_tx_used = gld_final[i][31:24];
            exp_r       = gld_final[i][23:16];
            exp_g       = gld_final[i][15:8];
            exp_b       = gld_final[i][7:0];

            $display(
                "[CASE %02d] exp_case_id=%0d tx_raw=0x%02X tx_used=0x%02X exp_rgb=(%0d,%0d,%0d)",
                i, exp_case_id, exp_tx_raw, exp_tx_used, exp_r, exp_g, exp_b
            );

            // --------------------------
            // Phase DARK
            // --------------------------
            dark_enable = 1'b1;
            fork
                begin
                    drive_frame(base);
                    // Keep enable a bit longer because o_A_valid can align near frame tail.
                    repeat (4) @(posedge clk);
                    dark_enable = 1'b0;
                end
                begin
                    wait_done_pulse(dark_done, 500, dark_seen);
                end
            join
            if (!dark_seen) begin
                $display("  ERROR: dark_done timeout");
                err = err + 1;
                continue;
            end

            // --------------------------
            // Phase SKY (pulse)
            // --------------------------
            @(posedge clk);
            sky_enable <= 1'b1;
            @(posedge clk);
            sky_enable <= 1'b0;

            // --------------------------
            // Phase TRANS
            // --------------------------
            fork
                begin
                    @(posedge clk);
                    bank_wr_clear <= 1'b1;
                    trans_enable  <= 1'b1;

                    @(posedge clk);
                    bank_wr_clear <= 1'b0;

                    drive_frame(base);
                    repeat (4) @(posedge clk);
                    trans_enable  <= 1'b0;
                end
                begin
                    wait_done_pulse(trans_done, 900, trans_seen);
                end
            join
            if (!trans_seen) begin
                $display("  ERROR: trans_done timeout");
                err = err + 1;
                continue;
            end

            // --------------------------
            // Phase ADC
            // --------------------------
            x_seen = 1'b0;
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

            tx_cmp_idx = 0;
            tx_mismatch_cnt = 0;
            tx_first_mismatch_printed = 1'b0;
            tx_cmp_warmup_done = 1'b0;
            adc_obs_idx = 0;
            adc_match_idx = -1;

            timeout = 0;
            while (!adc_done && timeout < 4000) begin
                @(posedge clk);
                timeout = timeout + 1;
                trace_first_x(i, "ADC");

                if (bank_rd_en) begin
                    // BRAM read is synchronous: ignore first cycle after rd_en starts.
                    if (!tx_cmp_warmup_done) begin
                        tx_cmp_warmup_done = 1'b1;
                    end else if (tx_cmp_idx < `FRAME_PIXELS) begin
                        if (dut.bank_rd_data !== gld_tx5x5[base + tx_cmp_idx]) begin
                            tx_mismatch_cnt = tx_mismatch_cnt + 1;
                            if (!tx_first_mismatch_printed) begin
                                $display(
                                    "  TRACE TX5x5: first mismatch idx=%0d got=0x%02X exp=0x%02X",
                                    tx_cmp_idx,
                                    dut.bank_rd_data,
                                    gld_tx5x5[base + tx_cmp_idx]
                                );
                                tx_first_mismatch_printed = 1'b1;
                            end
                        end
                        tx_cmp_idx = tx_cmp_idx + 1;
                    end
                end

                if (dut.adc_out_valid) begin
                    if (adc_obs_idx < 6) begin
                        $display(
                            "  TRACE ADC stream idx=%0d pix=0x%02X (golden=0x%02X)",
                            adc_obs_idx,
                            dut.adc_out_pix,
                            gld_adc[i]
                        );
                    end
                    if ((adc_match_idx < 0) && (dut.adc_out_pix == gld_adc[i])) begin
                        adc_match_idx = adc_obs_idx;
                    end
                    adc_obs_idx = adc_obs_idx + 1;
                end
            end

            if (tx_mismatch_cnt == 0) begin
                $display("  TRACE TX5x5: bank stream matched golden (%0d/25)", tx_cmp_idx);
            end else begin
                $display(
                    "  TRACE TX5x5: mismatches=%0d over %0d compared samples",
                    tx_mismatch_cnt,
                    tx_cmp_idx
                );
            end
            $display(
                "  TRACE ADC pick: pick_idx=%0d latched_idx=%0d out_count=%0d selected_adc=0x%02X first_match_idx=%0d",
                dut.ADC_PICK_INDEX,
                dut.adc_latched_index,
                dut.adc_out_index,
                dut.adc_dark_hold,
                adc_match_idx
            );

            adc_enable <= 1'b0;
            bank_rd_en <= 1'b0;

            if (!adc_done) begin
                $display("  ERROR: adc_done timeout");
                err = err + 1;
                continue;
            end

            // --------------------------
            // Phase RECOVERY
            // --------------------------
            recovery_enable = 1'b1;
            rec_count = 0;
            cap_r = 8'd0;
            cap_g = 8'd0;
            cap_b = 8'd0;

            fork
                begin
                    drive_frame(base);
                end
                begin
                    timeout = 0;
                    while (rec_count < `FRAME_PIXELS && timeout < 2000) begin
                        @(posedge clk);
                        timeout = timeout + 1;
                        trace_first_x(i, "RECOVERY");
                        if (post_frame_clken) begin
                            if (rec_count == 12) begin
                                cap_r = post_img[23:16];
                                cap_g = post_img[15:8];
                                cap_b = post_img[7:0];
                            end
                            rec_count = rec_count + 1;
                        end
                    end
                end
            join

            recovery_enable = 1'b0;

            if (rec_count < `FRAME_PIXELS) begin
                $display(
                    "  ERROR: recovery output timeout (captured %0d/%0d)",
                    rec_count,
                    `FRAME_PIXELS
                );
                err = err + 1;
                continue;
            end

            if ($isunknown({cap_r, cap_g, cap_b, exp_r, exp_g, exp_b})) begin
                $display("  ERROR: unknown X/Z detected in compare data");
                err = err + 1;
            end else if (cap_r !== exp_r || cap_g !== exp_g || cap_b !== exp_b) begin
                $display("  FAIL: center RGB mismatch got=(%0d,%0d,%0d) exp=(%0d,%0d,%0d)",
                         cap_r, cap_g, cap_b, exp_r, exp_g, exp_b);
                $display(
                    "  TRACE TOP: A_rgb=(%0d,%0d,%0d) adc_dark=%0d",
                    dut.purple_A_r,
                    dut.purple_A_g,
                    dut.purple_A_b,
                    dut.adc_dark_hold
                );
                $display(
                    "  TRACE ADC: out_index=%0d out_valid=%0b out_pix=0x%02X",
                    dut.adc_out_index,
                    dut.adc_out_valid,
                    dut.adc_out_pix
                );
                $display(
                    "  TRACE TCF: tx_raw=0x%02X tx_used=0x%02X out_rgb=(%0d,%0d,%0d)",
                    dut.tcf_tx_raw,
                    dut.tcf_tx_used,
                    dut.tcf_r,
                    dut.tcf_g,
                    dut.tcf_b
                );
                $display(
                    "  TRACE SRC(center): bus_BGR=(%0d,%0d,%0d) mapped_RGB=(%0d,%0d,%0d)",
                    pat_rgb[base+12][23:16],
                    pat_rgb[base+12][15:8],
                    pat_rgb[base+12][7:0],
                    pat_rgb[base+12][7:0],
                    pat_rgb[base+12][15:8],
                    pat_rgb[base+12][23:16]
                );
                err = err + 1;
            end else begin
                $display("  PASS: center RGB matched (%0d,%0d,%0d)", cap_r, cap_g, cap_b);
            end

            // small gap between cases
            repeat (6) @(posedge clk);
            clear_controls();
        end

        $display("\n============================================================");
        if (err == 0) begin
            $display("HAZE_REMOVAL_TOP TB PASS: all %0d cases passed", `NUM_CASES);
        end else begin
            $display("HAZE_REMOVAL_TOP TB FAIL: total errors = %0d", err);
        end
        $display("============================================================\n");

        $finish;
    end

    `ifdef VCD
    initial begin
        $dumpfile("haze_removal_top_tb.vcd");
        $dumpvars(0, haze_removal_top_tb);
    end
    `endif

endmodule
