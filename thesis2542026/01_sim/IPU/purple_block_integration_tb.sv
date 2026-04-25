//==============================================================================
// Testbench: purple_block_integration_tb
// Description: Integration test for atm_light_coarse_tx
//
// 2-pass flow:
//   Pass 1: stream all pixels -> dark_channel -> atmospheric_light -> A
//   Pass 2: stream all pixels -> dark_channel + grayscale -> sky_recognition
//            -> estimate_transmission -> bank write -> swap -> bank read
//
// Verification:
//   - Compare A_R/A_G/A_B after pass 1 (golden: golden_purple_A.hex)
//   - Compare dark_ch per pixel pass 1 & 2 (golden: golden_purple_dark_ch.hex)
//   - Compare grayscale per pixel pass 2 (golden: golden_purple_gray.hex)
//   - Compare sky recognition per pixel pass 2 (golden: golden_purple_sky.hex)
//   - Compare transmission inline pass 2 (golden: golden_purple_tx.hex)
//   - Compare transmission after bank readback (golden: golden_purple_tx.hex)
//
// Parameters: IMG_WIDTH=4, IMG_HEIGHT=4, 16 pixels
//==============================================================================

`timescale 1ns/1ps

module purple_block_integration_tb;

    // ========================================================================
    // Parameters
    // ========================================================================
    localparam int IMG_WIDTH  = 4;
    localparam int IMG_HEIGHT = 4;
    localparam int NUM_PIXELS = IMG_WIDTH * IMG_HEIGHT;  // 16
    localparam int ADDR_WIDTH = 4;   // ceil(log2(16)) = 4

    localparam logic [7:0] OMEGA_Q8 = 8'hFF;
    localparam logic [7:0] T_MIN    = 8'd15;

    // Sky recognition config
    localparam logic [7:0] SKY_A0    = 8'd150;
    localparam logic       USE_DARK  = 1'b0;
    localparam logic       USE_SKY   = 1'b1;
    localparam logic [7:0] T_SKY     = 8'd255;

    // Clock
    localparam HALF_CLK = 5;

    // ========================================================================
    // Signals
    // ========================================================================
    logic        clk, rst_n;
    logic        i_valid;
    logic [23:0] i_color;
    logic        i_frame_start, i_frame_end;
    logic        i_bank_swap, i_bank_wr_clear, i_bank_rd_clear, i_bank_rd_en;

    // Outputs from DUT
    logic [7:0]  o_A_R, o_A_G, o_A_B;
    logic        o_A_valid;
    logic        o_dark_valid;
    logic [7:0]  o_dark_ch;
    logic        o_sky_valid, o_sky;
    logic        o_tx_valid;
    logic [7:0]  o_tx;
    logic [7:0]           o_bank_rd_data;
    logic [ADDR_WIDTH-1:0] o_bank_rd_addr;
    logic                 o_bank_wr_sel, o_bank_rd_sel;

    // ========================================================================
    // DUT
    // ========================================================================
    atm_light_coarse_tx #(
        .IMG_WIDTH  (IMG_WIDTH),
        .IMG_HEIGHT (IMG_HEIGHT),
        .ADDR_WIDTH (ADDR_WIDTH),
        .OMEGA_Q8   (OMEGA_Q8),
        .T_MIN      (T_MIN)
    ) DUT (
        .clk            (clk),
        .rst_n          (rst_n),
        .i_valid        (i_valid),
        .i_color        (i_color),
        .i_frame_start  (i_frame_start),
        .i_frame_end    (i_frame_end),
        .i_A0           (SKY_A0),
        .i_use_dark     (USE_DARK),
        .i_use_sky      (USE_SKY),
        .i_t_sky        (T_SKY),
        .i_bank_swap    (i_bank_swap),
        .i_bank_wr_clear(i_bank_wr_clear),
        .i_bank_rd_clear(i_bank_rd_clear),
        .i_bank_rd_en   (i_bank_rd_en),
        .o_A_R          (o_A_R),
        .o_A_G          (o_A_G),
        .o_A_B          (o_A_B),
        .o_A_valid      (o_A_valid),
        .o_dark_valid   (o_dark_valid),
        .o_dark_ch      (o_dark_ch),
        .o_sky_valid    (o_sky_valid),
        .o_sky          (o_sky),
        .o_tx_valid     (o_tx_valid),
        .o_tx           (o_tx),
        .o_bank_rd_data (o_bank_rd_data),
        .o_bank_rd_addr (o_bank_rd_addr),
        .o_bank_wr_sel  (o_bank_wr_sel),
        .o_bank_rd_sel  (o_bank_rd_sel)
    );

    // ========================================================================
    // Golden Data
    // ========================================================================
    logic [23:0] rgb_mem     [0:NUM_PIXELS-1];
    logic [7:0]  gold_dc     [0:NUM_PIXELS-1];
    logic [7:0]  gold_tx     [0:NUM_PIXELS-1];
    logic [23:0] gold_A_mem  [0:0];   // single-entry array for $readmemh
    logic [7:0]  gold_gray   [0:NUM_PIXELS-1];
    logic [7:0]  gold_sky    [0:NUM_PIXELS-1];

    initial begin
        $readmemh("../09_pattern/pattern_purple_rgb.hex",          rgb_mem);
        $readmemh("../07_golden_output/golden_purple_dark_ch.hex", gold_dc);
        $readmemh("../07_golden_output/golden_purple_tx.hex",      gold_tx);
        $readmemh("../07_golden_output/golden_purple_A.hex",       gold_A_mem);
        $readmemh("../07_golden_output/golden_purple_gray.hex",    gold_gray);
        $readmemh("../07_golden_output/golden_purple_sky.hex",     gold_sky);
    end

    // ========================================================================
    // Clock Generation
    // ========================================================================
    initial clk = 0;
    always #HALF_CLK clk = ~clk;

    // ========================================================================
    // Scoreboard Counters
    // ========================================================================
    int pass1_dc_cnt,  pass1_dc_err;
    int gray_cnt,      gray_err;
    int sky_cnt,       sky_err;
    int tx_inline_cnt, tx_inline_err;
    int pass2_dc_cnt,  pass2_dc_err;
    int pass2_tx_cnt,  pass2_tx_err;
    int bank_rd_cnt,   bank_rd_err;
    int total_err;

    // Phase tracking
    logic pass2_active = 0;

    // ========================================================================
    // Tasks
    // ========================================================================
    task automatic reset_dut();
        rst_n          <= 0;
        i_valid        <= 0;
        i_color        <= '0;
        i_frame_start  <= 0;
        i_frame_end    <= 0;
        i_bank_swap    <= 0;
        i_bank_wr_clear<= 0;
        i_bank_rd_clear<= 0;
        i_bank_rd_en   <= 0;
        repeat (5) @(posedge clk);
        rst_n <= 1;
        @(posedge clk);
    endtask

    task automatic drive_pixel(input logic [23:0] color);
        @(posedge clk);
        i_valid <= 1;
        i_color <= color;
    endtask

    task automatic idle_pixel();
        @(posedge clk);
        i_valid <= 0;
        i_color <= '0;
    endtask

    // ========================================================================
    // Main Test
    // ========================================================================
    initial begin
        $display("==========================================================");
        $display("  PURPLE BLOCK INTEGRATION TEST");
        $display("  Image: %0dx%0d = %0d pixels", IMG_WIDTH, IMG_HEIGHT, NUM_PIXELS);
        $display("==========================================================");

        pass1_dc_cnt = 0; pass1_dc_err = 0;
        gray_cnt     = 0; gray_err     = 0;
        sky_cnt      = 0; sky_err      = 0;
        tx_inline_cnt= 0; tx_inline_err= 0;
        pass2_dc_cnt = 0; pass2_dc_err = 0;
        pass2_tx_cnt = 0; pass2_tx_err = 0;
        bank_rd_cnt  = 0; bank_rd_err  = 0;

        // ---- Reset ----
        reset_dut();

        // ================================================================
        // PASS 1: Stream frame for atmospheric_light
        // ================================================================
        $display("\n--- PASS 1: Atmospheric Light Estimation ---");

        // Pulse frame_start (before first pixel)
        @(posedge clk);
        i_frame_start <= 1;
        @(posedge clk);
        i_frame_start <= 0;

        // Stream all pixels
        for (int i = 0; i < NUM_PIXELS; i++) begin
            drive_pixel(rgb_mem[i]);
        end

        // Deassert valid, wait for last dark_ch to propagate
        idle_pixel();
        // dark_channel latency = 1 cycle, so wait 1 more cycle
        @(posedge clk);

        // Pulse frame_end
        @(posedge clk);
        i_frame_end <= 1;
        @(posedge clk);
        i_frame_end <= 0;

        // Wait for o_A_valid
        repeat (3) @(posedge clk);
        #1;

        // Check atmospheric light
        if (o_A_valid) begin
            logic [7:0] exp_A_R, exp_A_G, exp_A_B;
            exp_A_R = gold_A_mem[0][7:0];
            exp_A_G = gold_A_mem[0][15:8];
            exp_A_B = gold_A_mem[0][23:16];
            if (o_A_R !== exp_A_R || o_A_G !== exp_A_G || o_A_B !== exp_A_B) begin
                $display("  [FAIL] A: got (%0d,%0d,%0d), exp (%0d,%0d,%0d)",
                          o_A_R, o_A_G, o_A_B, exp_A_R, exp_A_G, exp_A_B);
                pass1_dc_err++;
            end else begin
                $display("  [PASS] Atmospheric Light: A_R=%0d, A_G=%0d, A_B=%0d",
                          o_A_R, o_A_G, o_A_B);
            end
        end else begin
            $display("  [FAIL] o_A_valid not asserted after frame_end!");
            pass1_dc_err++;
        end

        // ================================================================
        // PASS 2: Stream frame for estimate_transmission
        // A values are now latched in atmospheric_light block and stable
        // ================================================================
        $display("\n--- PASS 2: Transmission Estimation ---");

        // Clear bank write counter before pass 2
        @(posedge clk);
        i_bank_wr_clear <= 1;
        @(posedge clk);
        i_bank_wr_clear <= 0;
        @(posedge clk);

        // Activate pass 2 monitors
        pass2_active = 1;

        // Stream all pixels
        for (int i = 0; i < NUM_PIXELS; i++) begin
            drive_pixel(rgb_mem[i]);
        end

        // Deassert valid, wait for pipeline to drain
        idle_pixel();
        // Pipeline latency: dark_ch(1) + sky(1) + est_tx(2) = 4 cycles
        repeat (6) @(posedge clk);

        // Deactivate pass 2 monitors
        pass2_active = 0;

        // ---- Pass 2 Inline Summary ----
        $display("  Dark ch  (pass2): %0d checked, %0d errors", pass2_dc_cnt, pass2_dc_err);
        $display("  Grayscale(pass2): %0d checked, %0d errors", gray_cnt,     gray_err);
        $display("  Sky recog(pass2): %0d checked, %0d errors", sky_cnt,      sky_err);
        $display("  Tx inline(pass2): %0d checked, %0d errors", tx_inline_cnt,tx_inline_err);

        // ================================================================
        // BANK READBACK
        // ================================================================
        $display("\n--- BANK READBACK ---");

        // Swap banks: written bank becomes read bank
        @(posedge clk);
        i_bank_swap <= 1;
        @(posedge clk);
        i_bank_swap <= 0;

        // Clear read counter
        @(posedge clk);
        i_bank_rd_clear <= 1;
        @(posedge clk);
        i_bank_rd_clear <= 0;
        @(posedge clk);

        // Read all pixels
        for (int i = 0; i < NUM_PIXELS; i++) begin
            @(posedge clk);
            i_bank_rd_en <= 1;
        end
        @(posedge clk);
        i_bank_rd_en <= 0;
        // BRAM read latency: 1 cycle after rd_en
        @(posedge clk);

        $display("\n--- RESULTS ---");

        // ================================================================
        // FINAL REPORT
        // ================================================================
        total_err = pass1_dc_err + gray_err + sky_err
                  + tx_inline_err + pass2_dc_err + bank_rd_err;

        $display("\n==========================================================");
        $display("  SUMMARY");
        $display("  -------");
        $display("  Pass1 Dark Ch : %0d checked, %0d errors", pass1_dc_cnt, pass1_dc_err);
        $display("  Pass2 Dark Ch : %0d checked, %0d errors", pass2_dc_cnt, pass2_dc_err);
        $display("  Grayscale     : %0d checked, %0d errors", gray_cnt,     gray_err);
        $display("  Sky Recog     : %0d checked, %0d errors", sky_cnt,      sky_err);
        $display("  Tx Inline     : %0d checked, %0d errors", tx_inline_cnt,tx_inline_err);
        $display("  Bank Readback : %0d checked, %0d errors", bank_rd_cnt,  bank_rd_err);
        $display("  ------------------------------------------");
        if (total_err == 0)
            $display("  ALL CHECKS PASSED!");
        else
            $display("  TOTAL ERRORS: %0d", total_err);
        $display("==========================================================");

        $finish;
    end

    // ========================================================================
    // Monitor: Dark Channel (Pass 1 only)
    // ========================================================================
    int dc_idx = 0;
    always @(posedge clk) begin
        #1;
        if (!pass2_active && o_dark_valid) begin
            if (dc_idx < NUM_PIXELS) begin
                pass1_dc_cnt++;
                if (o_dark_ch !== gold_dc[dc_idx]) begin
                    $display("  [FAIL] dark_ch[%0d]: got 0x%02X, exp 0x%02X",
                              dc_idx, o_dark_ch, gold_dc[dc_idx]);
                    pass1_dc_err++;
                end
                dc_idx++;
            end
        end
    end

    // ========================================================================
    // Monitor: Grayscale (pass 2, hierarchical access to DUT.gray_out)
    // Latency: same as dark_ch (1 cycle)
    // ========================================================================
    int gray_idx = 0;
    always @(posedge clk) begin
        #1;
        if (pass2_active && o_dark_valid && gray_idx < NUM_PIXELS) begin
            gray_cnt++;
            if (DUT.gray_out !== gold_gray[gray_idx]) begin
                $display("  [FAIL] gray[%0d]: got 0x%02X, exp 0x%02X",
                          gray_idx, DUT.gray_out, gold_gray[gray_idx]);
                gray_err++;
            end else begin
                $display("  [PASS] gray[%0d]: 0x%02X", gray_idx, DUT.gray_out);
            end
            gray_idx++;
        end
    end

    // ========================================================================
    // Monitor: Sky Recognition (pass 2)
    // Latency: dark_ch(1) + sky(1) = 2 cycles from i_valid
    // ========================================================================
    int sky_idx = 0;
    always @(posedge clk) begin
        #1;
        if (pass2_active && o_sky_valid && sky_idx < NUM_PIXELS) begin
            sky_cnt++;
            if (o_sky !== gold_sky[sky_idx][0]) begin
                $display("  [FAIL] sky[%0d]: got %0b, exp %0b",
                          sky_idx, o_sky, gold_sky[sky_idx][0]);
                sky_err++;
            end else begin
                $display("  [PASS] sky[%0d]: %0b", sky_idx, o_sky);
            end
            sky_idx++;
        end
    end

    // ========================================================================
    // Monitor: Dark Channel (pass 2, verify consistency)
    // ========================================================================
    int pass2_dc_idx = 0;
    always @(posedge clk) begin
        #1;
        if (pass2_active && o_dark_valid && pass2_dc_idx < NUM_PIXELS) begin
            pass2_dc_cnt++;
            if (o_dark_ch !== gold_dc[pass2_dc_idx]) begin
                $display("  [FAIL] dark_ch_p2[%0d]: got 0x%02X, exp 0x%02X",
                          pass2_dc_idx, o_dark_ch, gold_dc[pass2_dc_idx]);
                pass2_dc_err++;
            end
            pass2_dc_idx++;
        end
    end

    // ========================================================================
    // Monitor: Transmission Inline (pass 2, direct o_tx check)
    // Latency: dark_ch(1) + sky(1) + est_tx(2) = 4 cycles from i_valid
    // ========================================================================
    int tx_idx = 0;
    always @(posedge clk) begin
        #1;
        if (pass2_active && o_tx_valid && tx_idx < NUM_PIXELS) begin
            tx_inline_cnt++;
            if (o_tx !== gold_tx[tx_idx]) begin
                $display("  [FAIL] tx_inline[%0d]: got 0x%02X, exp 0x%02X",
                          tx_idx, o_tx, gold_tx[tx_idx]);
                tx_inline_err++;
            end else begin
                $display("  [PASS] tx_inline[%0d]: 0x%02X", tx_idx, o_tx);
            end
            tx_idx++;
        end
    end

    // ========================================================================
    // Monitor: Bank Readback (compare with golden tx)
    // ========================================================================
    int rd_phase = 0;  // set to 1 when bank readback starts
    int rd_idx   = 0;

    // Detect swap to mark readback phase start
    always @(posedge clk) begin
        if (i_bank_swap)
            rd_phase <= 1;
    end

    // Compare on read
    always @(posedge clk) begin
        #1;
        if (rd_phase && i_bank_rd_en) begin
            // Data available 1 cycle after rd_en (BRAM latency)
        end
    end

    // Capture read data with 1-cycle BRAM latency
    logic bank_rd_en_d1;
    always_ff @(posedge clk) bank_rd_en_d1 <= i_bank_rd_en;

    always @(posedge clk) begin
        #1;
        if (rd_phase && bank_rd_en_d1 && rd_idx < NUM_PIXELS) begin
            bank_rd_cnt++;
            if (o_bank_rd_data !== gold_tx[rd_idx]) begin
                $display("  [FAIL] tx[%0d]: bank_rd=0x%02X, exp=0x%02X",
                          rd_idx, o_bank_rd_data, gold_tx[rd_idx]);
                bank_rd_err++;
            end else begin
                $display("  [PASS] tx[%0d]: 0x%02X", rd_idx, o_bank_rd_data);
            end
            rd_idx++;
        end
    end

    // ========================================================================
    // Timeout
    // ========================================================================
    initial begin
        #100000;
        $display("TIMEOUT!");
        $finish;
    end

endmodule
