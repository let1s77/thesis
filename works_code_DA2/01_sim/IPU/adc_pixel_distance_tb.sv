//==============================================================================
// Testbench: adc_pixel_distance_tb
// Description: Unit test cho adc_pixel_distance module
//
// Test Strategy:
//   - Load 20 test cases (25 gray pixels each) tu hex file
//   - Drive 5x5 gray window, verify 25 dp_total outputs
//   - Compare ket qua voi golden (integer-matched to RTL)
//
// Pattern format (8-bit per value, 25 consecutive per case):
//   gray pixels row-major: p00,p01,...,p44
//
// Golden format (16-bit per value, 25 consecutive per case):
//   dp_total (9-bit) zero-padded to 16-bit
//==============================================================================

`timescale 1ns/10ps
`define CYCLE 10.0
`define NUM_PATTERNS 20

`ifdef SYN
    `include "adc_pixel_distance_syn.sv"
`else
    `include "../00_src/IPU/adc_pixel_distance.sv"
`endif

module adc_pixel_distance_tb;

    //==========================================================================
    // Clock Generation
    //==========================================================================
    bit clk;
    always #(`CYCLE/2) clk = ~clk;

    //==========================================================================
    // DUT Signals
    //==========================================================================
    logic       rst_n;
    logic       i_valid;
    logic       o_valid;
    logic [7:0] pin   [0:24];   // 5x5 gray window (row-major)
    logic [8:0] dpout [0:24];   // 5x5 dp_total output

    //==========================================================================
    // Pattern / Golden memories
    //==========================================================================
    reg [7:0]  pat_mem [0:`NUM_PATTERNS*25-1];
    reg [15:0] gld_mem [0:`NUM_PATTERNS*25-1];

    integer i, j, base, err, case_err;

    //==========================================================================
    // Case names
    //==========================================================================
    string case_names [0:19] = '{
        "flat_uniform",           "center_dark_flat",
        "horizontal_edge",        "vertical_edge",
        "diag_edge_main",         "diag_edge_anti",
        "cross_structure",        "center_bright_island",
        "noisy_small_variation",  "ramp_horizontal",
        "ramp_vertical",          "checkerboard_soft",
        "corner_dark_tl",         "corner_dark_br",
        "ring_structure",         "left_right_two_regions",
        "top_bottom_two_regions", "center_valley",
        "random_like_1",          "random_like_2"
    };

    //==========================================================================
    // DUT Instance
    //==========================================================================
    adc_pixel_distance dut (
        .clk     (clk),
        .rst_n   (rst_n),
        .i_valid (i_valid),
        // Row 0
        .p00(pin[0]),  .p01(pin[1]),  .p02(pin[2]),  .p03(pin[3]),  .p04(pin[4]),
        // Row 1
        .p10(pin[5]),  .p11(pin[6]),  .p12(pin[7]),  .p13(pin[8]),  .p14(pin[9]),
        // Row 2
        .p20(pin[10]), .p21(pin[11]), .p22(pin[12]), .p23(pin[13]), .p24(pin[14]),
        // Row 3
        .p30(pin[15]), .p31(pin[16]), .p32(pin[17]), .p33(pin[18]), .p34(pin[19]),
        // Row 4
        .p40(pin[20]), .p41(pin[21]), .p42(pin[22]), .p43(pin[23]), .p44(pin[24]),
        // dp outputs
        .dp00(dpout[0]),  .dp01(dpout[1]),  .dp02(dpout[2]),  .dp03(dpout[3]),  .dp04(dpout[4]),
        .dp10(dpout[5]),  .dp11(dpout[6]),  .dp12(dpout[7]),  .dp13(dpout[8]),  .dp14(dpout[9]),
        .dp20(dpout[10]), .dp21(dpout[11]), .dp22(dpout[12]), .dp23(dpout[13]), .dp24(dpout[14]),
        .dp30(dpout[15]), .dp31(dpout[16]), .dp32(dpout[17]), .dp33(dpout[18]), .dp34(dpout[19]),
        .dp40(dpout[20]), .dp41(dpout[21]), .dp42(dpout[22]), .dp43(dpout[23]), .dp44(dpout[24]),
        .o_valid (o_valid)
    );

    //==========================================================================
    // Main Test Sequence
    //==========================================================================
    initial begin
        clk = 0;

        // Load pattern and golden
        $readmemh("../09_pattern/pattern_pixel_distance.hex", pat_mem);
        $readmemh("../07_golden_output/golden_pixel_distance.hex", gld_mem);

        // Initialize
        err     = 0;
        rst_n   = 0;
        i_valid = 0;
        for (j = 0; j < 25; j++) pin[j] = 8'd0;

        // Reset
        #(`CYCLE*3);
        rst_n = 1;
        @(posedge clk);

        $display("\n");
        $display("================================================================");
        $display("        ADC Pixel Distance - RTL Testbench");
        $display("================================================================");
        $display("Total test cases : %0d  (25 values per case)", `NUM_PATTERNS);
        $display("Pipeline stages  : 1");
        $display("================================================================\n");

        for (i = 0; i < `NUM_PATTERNS; i = i + 1) begin
            base = i * 25;

            // Drive 5x5 gray window
            @(posedge clk);
            i_valid <= 1;
            for (j = 0; j < 25; j++) pin[j] <= pat_mem[base + j];

            @(posedge clk);
            i_valid <= 0;

            // 1 pipeline stage -> output available next cycle
            @(posedge clk);

            // --- Compare ---
            case_err = 0;
            $display("----------- Case %2d: %-24s -----------", i, case_names[i]);

            if (o_valid !== 1'b1) begin
                $display("  ERROR: o_valid not asserted!");
                case_err = case_err + 1;
            end

            for (j = 0; j < 25; j++) begin
                if (dpout[j] !== gld_mem[base + j][8:0]) begin
                    $display("  [%0d][%0d] Got=%3d  Exp=%3d  MISMATCH",
                             j / 5, j % 5, dpout[j], gld_mem[base + j][8:0]);
                    case_err = case_err + 1;
                end
            end

            if (case_err == 0)
                $display("  All 25 dp_total MATCH  -> PASS");
            else begin
                $display("  Result: FAIL (%0d errors)", case_err);
                err = err + case_err;
            end
            $display("");
        end

        // ---- Final Summary ----
        #(`CYCLE*2);
        $display("\n");
        $display("========================================");
        $display("        SIMULATION SUMMARY              ");
        $display("========================================");

        if (err === 0) begin
        `ifdef SYN
            $display("    ********************************");
            $display("    **  Pixel Distance SYN        **");
        `else
            $display("    ********************************");
            $display("    **  Pixel Distance RTL        **");
        `endif
            $display("    ********************************");
            $display("    **                            **       |\\__||  ");
            $display("    **  Congratulations !!        **      / O.O  | ");
            $display("    **                            **    /_____   | ");
            $display("    **  SIMULATION PASS !!        **   /^ ^ ^ \\\\  |");
            $display("    **                            **  |^ ^ ^ ^ |w| ");
            $display("    ********************************   \\m___m__|_|");
            $display("    All %0d cases passed!", `NUM_PATTERNS);
            $display("\n");
        end
        else begin
        `ifdef SYN
            $display("    ********************************");
            $display("    **  Pixel Distance SYN        **");
        `else
            $display("    ********************************");
            $display("    **  Pixel Distance RTL        **");
        `endif
            $display("    ********************************");
            $display("    **                            **       |\\__||  ");
            $display("    **  OOPS!!                    **      / X,X  | ");
            $display("    **                            **    /_____   | ");
            $display("    **  SIMULATION Failed!!       **   /^ ^ ^ \\\\  |");
            $display("    **                            **  |^ ^ ^ ^ |w| ");
            $display("    ********************************   \\m___m__|_|");
            $display("    Totally has %0d errors", err);
            $display("\n");
        end

        $finish;
    end

    `ifdef SYN
        initial $sdf_annotate("adc_pixel_distance_syn.sdf", dut);
    `endif

    `ifdef FSDB
        initial begin
            $fsdbDumpfile("adc_pixel_distance.fsdb");
            $fsdbDumpvars("+struct", "+mda", adc_pixel_distance_tb);
        end
    `endif

    `ifdef VCD
        initial begin
            $dumpfile("adc_pixel_distance.vcd");
            $dumpvars(0, adc_pixel_distance_tb);
        end
    `endif

endmodule
