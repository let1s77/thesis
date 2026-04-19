//==============================================================================
// Testbench: bank_pingpong_tb
// Description: Unit test cho bank_pingpong_stream module
//
// Test Strategy:
//   Phase 1: Write NUM_PIXELS data into bank (streaming)
//   Phase 2: Swap banks (i_swap pulse)
//   Phase 3: Read back NUM_PIXELS data (streaming)
//   Compare: o_rd_data must match written data in order
//   Also check: o_rd_row, o_rd_col, boundary flags
//
// Image: 4x4 = 16 pixels (small for fast sim)
// Read latency: 1 cycle (BRAM registered output)
//
// Pattern file:
//   09_pattern/pattern_bank_wr_data.hex  (8-bit write data)
// Golden file:
//   07_golden_output/golden_bank_rd_data.hex (8-bit expected readback)
//==============================================================================

`timescale 1ns/10ps
`define CYCLE 10.0

// Small image for testing
`define IMG_W       4
`define IMG_H       4
`define NUM_PIXELS  (`IMG_W * `IMG_H)
`define ADDR_W      4                   // ceil(log2(16)) = 4

`ifdef SYN
    `include "bank_pingpong_stream_syn.sv"
`else
    `include "../00_src/IPU/bank_pingpong_stream.sv"
    `include "../00_src/IPU/bank_bram.sv"
    `include "../00_src/IPU/frame_linear_counter.sv"
`endif

module bank_pingpong_tb;

    //==========================================================================
    // Clock Generation
    //==========================================================================
    bit clk;
    always #(`CYCLE/2) clk = ~clk;

    //==========================================================================
    // DUT Signals
    //==========================================================================
    logic        rst_n;
    logic        i_swap;
    logic        i_wr_clear;
    logic        i_wr_valid;
    logic [7:0]  i_wr_data;
    logic        i_rd_clear;
    logic        i_rd_en;
    logic [7:0]  o_rd_data;

    logic [`ADDR_W-1:0]            o_rd_addr;
    logic [$clog2(`IMG_H)-1:0]     o_rd_row;
    logic [$clog2(`IMG_W)-1:0]     o_rd_col;
    logic        o_at_top, o_at_bottom, o_at_left, o_at_right;
    logic        o_wr_bank_sel, o_rd_bank_sel;

    //==========================================================================
    // Pattern / Golden memories
    //==========================================================================
    reg [7:0]  wr_data_pat [0:`NUM_PIXELS-1];
    reg [7:0]  golden_rd   [0:`NUM_PIXELS-1];

    integer i, err;
    integer err_data, err_pos;

    // Captured position (blocking) before NBA increments counter
    logic [$clog2(`IMG_H)-1:0] cap_row;
    logic [$clog2(`IMG_W)-1:0] cap_col;
    logic cap_top, cap_bot, cap_left, cap_right;

    //==========================================================================
    // DUT Instance
    //==========================================================================
    bank_pingpong_stream #(
        .DATA_WIDTH (8),
        .IMG_WIDTH  (`IMG_W),
        .IMG_HEIGHT (`IMG_H),
        .ADDR_WIDTH (`ADDR_W)
    ) dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .i_swap        (i_swap),
        .i_wr_clear    (i_wr_clear),
        .i_wr_valid    (i_wr_valid),
        .i_wr_data     (i_wr_data),
        .i_rd_clear    (i_rd_clear),
        .i_rd_en       (i_rd_en),
        .o_rd_data     (o_rd_data),
        .o_rd_addr     (o_rd_addr),
        .o_rd_row      (o_rd_row),
        .o_rd_col      (o_rd_col),
        .o_at_top      (o_at_top),
        .o_at_bottom   (o_at_bottom),
        .o_at_left     (o_at_left),
        .o_at_right    (o_at_right),
        .o_wr_bank_sel (o_wr_bank_sel),
        .o_rd_bank_sel (o_rd_bank_sel)
    );

    //==========================================================================
    // Position golden computation (combinational)
    //==========================================================================
    logic [$clog2(`IMG_H)-1:0] exp_row;
    logic [$clog2(`IMG_W)-1:0] exp_col;
    logic exp_top, exp_bot, exp_left, exp_right;

    function automatic void calc_expected_pos(input int addr);
        exp_row   = addr / `IMG_W;
        exp_col   = addr % `IMG_W;
        exp_top   = (exp_row == 0);
        exp_bot   = (exp_row == `IMG_H - 1);
        exp_left  = (exp_col == 0);
        exp_right = (exp_col == `IMG_W - 1);
    endfunction

    //==========================================================================
    // Main Test Sequence
    //==========================================================================
    initial begin
        clk = 0;

        // Load files
        $readmemh("../09_pattern/pattern_bank_wr_data.hex",     wr_data_pat);
        $readmemh("../07_golden_output/golden_bank_rd_data.hex", golden_rd);

        // Initialize
        err      = 0;
        err_data = 0;
        err_pos  = 0;
        rst_n      = 0;
        i_swap     = 0;
        i_wr_clear = 0;
        i_wr_valid = 0;
        i_wr_data  = 8'h0;
        i_rd_clear = 0;
        i_rd_en    = 0;

        // Reset
        #(`CYCLE*3);
        rst_n = 1;
        @(posedge clk);

        $display("\n");
        $display("================================================================");
        $display("     Bank Ping-Pong Stream - RTL Testbench");
        $display("================================================================");
        $display("Image: %0dx%0d = %0d pixels", `IMG_W, `IMG_H, `NUM_PIXELS);
        $display("ADDR_WIDTH: %0d, DATA_WIDTH: 8", `ADDR_W);
        $display("Test: Write -> Swap -> Read -> Compare");
        $display("================================================================\n");

        // =============================================================
        // PHASE 1: Write all pixels into current bank
        // =============================================================
        $display("--- PHASE 1: Writing %0d pixels to BANK (bank_sel=%0d) ---\n",
                 `NUM_PIXELS, o_wr_bank_sel);

        // Clear write counter
        @(posedge clk);
        i_wr_clear <= 1'b1;
        @(posedge clk);
        i_wr_clear <= 1'b0;

        // Stream write data
        for (i = 0; i < `NUM_PIXELS; i = i + 1) begin
            @(posedge clk);
            i_wr_valid <= 1'b1;
            i_wr_data  <= wr_data_pat[i];
        end
        @(posedge clk);
        i_wr_valid <= 1'b0;
        i_wr_data  <= 8'h0;

        $display("  Write complete. %0d pixels written.\n", `NUM_PIXELS);

        // =============================================================
        // PHASE 2: Swap banks
        // =============================================================
        $display("--- PHASE 2: Swap banks ---\n");

        @(posedge clk);
        i_swap <= 1'b1;
        @(posedge clk);
        i_swap <= 1'b0;
        #1;

        $display("  Bank swapped. wr_bank_sel=%0d, rd_bank_sel=%0d\n",
                 o_wr_bank_sel, o_rd_bank_sel);

        // =============================================================
        // PHASE 3: Read back all pixels from swapped bank
        // =============================================================
        $display("--- PHASE 3: Reading %0d pixels from BANK (rd_bank_sel=%0d) ---\n",
                 `NUM_PIXELS, o_rd_bank_sel);

        // Clear read counter
        @(posedge clk);
        i_rd_clear <= 1'b1;
        @(posedge clk);
        i_rd_clear <= 1'b0;

        // Read stream: assert i_rd_en for NUM_PIXELS cycles
        // BRAM read latency = 1 cycle, so sample o_rd_data 1 cycle after i_rd_en
        for (i = 0; i < `NUM_PIXELS; i = i + 1) begin
            @(posedge clk);
            i_rd_en <= 1'b1;
        end
        @(posedge clk);
        i_rd_en <= 1'b0;

        // Wait for last BRAM output (1 cycle latency)
        @(posedge clk);

        // Done reading — now we need to check results
        // The data appeared 1 cycle after each i_rd_en

        $display("  Read complete.\n");

        // =============================================================
        // PHASE 3b: Re-read and verify with display
        // (read again with cycle-by-cycle checking)
        // =============================================================
        $display("--- PHASE 3b: Re-read and Verify ---\n");

        // Clear read counter for second pass
        @(posedge clk);
        i_rd_clear <= 1'b1;
        @(posedge clk);
        i_rd_clear <= 1'b0;
        @(posedge clk);

        for (i = 0; i < `NUM_PIXELS; i = i + 1) begin
            // Assert rd_en
            @(posedge clk);
            i_rd_en <= 1'b1;

            // At next posedge: DUT sees rd_en=1
            // Capture position with BLOCKING assignment BEFORE NBA fires
            // (addr_r is still = i at this moment, NBA will increment to i+1)
            @(posedge clk);
            cap_row   = o_rd_row;
            cap_col   = o_rd_col;
            cap_top   = o_at_top;
            cap_bot   = o_at_bottom;
            cap_left  = o_at_left;
            cap_right = o_at_right;

            i_rd_en <= 1'b0;
            #1;  // let NBA settle — o_rd_data now valid

            // Compute expected position for this address
            calc_expected_pos(i);

            // --- Check data ---
            $display("  [%2d] rd_data=0x%02h  golden=0x%02h  |  row=%0d col=%0d  top=%0d bot=%0d left=%0d right=%0d",
                     i, o_rd_data, golden_rd[i],
                     cap_row, cap_col, cap_top, cap_bot, cap_left, cap_right);

            if (o_rd_data !== golden_rd[i]) begin
                $display("       DATA MISMATCH: got 0x%02h, expected 0x%02h", o_rd_data, golden_rd[i]);
                err_data = err_data + 1;
            end

            // --- Check position (captured before NBA) ---
            if (cap_row !== exp_row || cap_col !== exp_col ||
                cap_top !== exp_top || cap_bot !== exp_bot ||
                cap_left !== exp_left || cap_right !== exp_right) begin
                $display("       POS MISMATCH: row=%0d(exp %0d) col=%0d(exp %0d) T=%0d(%0d) B=%0d(%0d) L=%0d(%0d) R=%0d(%0d)",
                         cap_row, exp_row, cap_col, exp_col,
                         cap_top, exp_top, cap_bot, exp_bot,
                         cap_left, exp_left, cap_right, exp_right);
                err_pos = err_pos + 1;
            end
        end

        err = err_data + err_pos;

        // =============================================================
        // Summary
        // =============================================================
        #(`CYCLE*2);
        $display("\n");
        $display("========================================");
        $display("        SIMULATION SUMMARY              ");
        $display("========================================");

        if (err === 0) begin
            $display("    ********************************");
            $display("    ** Bank Ping-Pong Stream RTL  **");
            $display("    ********************************");
            $display("    **                            **       |\\__||  ");
            $display("    **  Congratulations !!        **      / O.O  | ");
            $display("    **                            **    /_____   | ");
            $display("    **  SIMULATION PASS !!        **   /^ ^ ^ \\\\  |");
            $display("    **                            **  |^ ^ ^ ^ |w| ");
            $display("    ********************************   \\m___m__|_|");
            $display("    All %0d pixels verified!", `NUM_PIXELS);
            $display("      Data errors:     %0d", err_data);
            $display("      Position errors: %0d", err_pos);
            $display("\n");
        end
        else begin
            $display("    ********************************");
            $display("    ** Bank Ping-Pong Stream RTL  **");
            $display("    ********************************");
            $display("    **                            **       |\\__||  ");
            $display("    **  OOPS!!                    **      / X,X  | ");
            $display("    **                            **    /_____   | ");
            $display("    **  SIMULATION Failed!!       **   /^ ^ ^ \\\\  |");
            $display("    **                            **  |^ ^ ^ ^ |w| ");
            $display("    ********************************   \\m___m__|_|");
            $display("    Data errors:     %0d", err_data);
            $display("    Position errors: %0d", err_pos);
            $display("    Total errors:    %0d", err);
            $display("\n");
        end

        $finish;
    end

    `ifdef FSDB
        initial begin
            $fsdbDumpfile("bank_pingpong.fsdb");
            $fsdbDumpvars("+struct", "+mda", bank_pingpong_tb);
        end
    `endif

    `ifdef VCD
        initial begin
            $dumpfile("bank_pingpong.vcd");
            $dumpvars(0, bank_pingpong_tb);
        end
    `endif

endmodule
