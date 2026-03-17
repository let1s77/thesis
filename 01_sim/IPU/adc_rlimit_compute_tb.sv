//==============================================================================
// Testbench: adc_rlimit_compute_tb
// Description: Unit test cho adc_rlimit_compute module
//
// Test Strategy:
//   - Load 20 test cases (25 d_lambda each) tu hex file
//   - Drive 25 dl inputs, verify:
//     (a) o_rlimit = (sum * 41) >> 10
//     (b) dl_d pass-through = dl delayed 2 cycles
//
// Pattern format (16-bit per value, 25 per case):
//   d_lambda [9:0] zero-padded to 16-bit
//
// Golden rlimit (16-bit, 1 per case):
//   r_limit [9:0] zero-padded to 16-bit
//
// Golden dl (16-bit per value, 25 per case):
//   dl pass-through (same as input, delayed 2 cycles)
//==============================================================================

`timescale 1ns/10ps
`define CYCLE 10.0
`define NUM_PATTERNS 20

`ifdef SYN
    `include "adc_rlimit_compute_syn.sv"
`else
    `include "../00_src/IPU/adc_rlimit_compute.sv"
`endif

module adc_rlimit_compute_tb;

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
    logic [9:0] dlin    [0:24];  // d_lambda inputs
    logic [9:0] dld_out [0:24];  // delayed d_lambda outputs
    logic [9:0] rlimit_out;

    //==========================================================================
    // Pattern / Golden memories
    //==========================================================================
    reg [15:0] pat_mem    [0:`NUM_PATTERNS*25-1];   // dl (10-bit in 16-bit)
    reg [15:0] gld_rlimit [0:`NUM_PATTERNS-1];      // rlimit (10-bit in 16-bit)
    reg [15:0] gld_dl     [0:`NUM_PATTERNS*25-1];   // dl pass-through

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
    adc_rlimit_compute dut (
        .clk     (clk),
        .rst_n   (rst_n),
        .i_valid (i_valid),
        // dl inputs
        .dl00(dlin[0]),  .dl01(dlin[1]),  .dl02(dlin[2]),  .dl03(dlin[3]),  .dl04(dlin[4]),
        .dl10(dlin[5]),  .dl11(dlin[6]),  .dl12(dlin[7]),  .dl13(dlin[8]),  .dl14(dlin[9]),
        .dl20(dlin[10]), .dl21(dlin[11]), .dl22(dlin[12]), .dl23(dlin[13]), .dl24(dlin[14]),
        .dl30(dlin[15]), .dl31(dlin[16]), .dl32(dlin[17]), .dl33(dlin[18]), .dl34(dlin[19]),
        .dl40(dlin[20]), .dl41(dlin[21]), .dl42(dlin[22]), .dl43(dlin[23]), .dl44(dlin[24]),
        // dl delayed outputs
        .dl_d00(dld_out[0]),  .dl_d01(dld_out[1]),  .dl_d02(dld_out[2]),  .dl_d03(dld_out[3]),  .dl_d04(dld_out[4]),
        .dl_d10(dld_out[5]),  .dl_d11(dld_out[6]),  .dl_d12(dld_out[7]),  .dl_d13(dld_out[8]),  .dl_d14(dld_out[9]),
        .dl_d20(dld_out[10]), .dl_d21(dld_out[11]), .dl_d22(dld_out[12]), .dl_d23(dld_out[13]), .dl_d24(dld_out[14]),
        .dl_d30(dld_out[15]), .dl_d31(dld_out[16]), .dl_d32(dld_out[17]), .dl_d33(dld_out[18]), .dl_d34(dld_out[19]),
        .dl_d40(dld_out[20]), .dl_d41(dld_out[21]), .dl_d42(dld_out[22]), .dl_d43(dld_out[23]), .dl_d44(dld_out[24]),
        // rlimit
        .o_rlimit(rlimit_out),
        .o_valid (o_valid)
    );

    //==========================================================================
    // Main Test Sequence
    //==========================================================================
    initial begin
        clk = 0;

        $readmemh("../09_pattern/pattern_rlimit.hex", pat_mem);
        $readmemh("../07_golden_output/golden_rlimit.hex", gld_rlimit);
        $readmemh("../07_golden_output/golden_rlimit_dl.hex", gld_dl);

        err     = 0;
        rst_n   = 0;
        i_valid = 0;
        for (j = 0; j < 25; j++) dlin[j] = 10'd0;

        #(`CYCLE*3);
        rst_n = 1;
        @(posedge clk);

        $display("\n");
        $display("================================================================");
        $display("        ADC R-Limit Compute - RTL Testbench");
        $display("================================================================");
        $display("Total test cases : %0d  (25 dl + 1 rlimit per case)", `NUM_PATTERNS);
        $display("Pipeline stages  : 2");
        $display("================================================================\n");

        for (i = 0; i < `NUM_PATTERNS; i = i + 1) begin
            base = i * 25;

            // Drive 25 d_lambda inputs
            @(posedge clk);
            i_valid <= 1;
            for (j = 0; j < 25; j++) dlin[j] <= pat_mem[base + j][9:0];

            @(posedge clk);
            i_valid <= 0;

            // 2 pipeline stages -> wait 2 more cycles
            @(posedge clk);   // stage 1 done
            @(posedge clk);   // stage 2 done, output readable

            // --- Compare ---
            case_err = 0;
            $display("----------- Case %2d: %-24s -----------", i, case_names[i]);

            if (o_valid !== 1'b1) begin
                $display("  ERROR: o_valid not asserted!");
                case_err = case_err + 1;
            end

            // Check r_limit
            if (rlimit_out !== gld_rlimit[i][9:0]) begin
                $display("  r_limit: Got=%3d  Exp=%3d  MISMATCH",
                         rlimit_out, gld_rlimit[i][9:0]);
                case_err = case_err + 1;
            end else begin
                $display("  r_limit = %3d  OK", rlimit_out);
            end

            // Check dl pass-through
            for (j = 0; j < 25; j++) begin
                if (dld_out[j] !== gld_dl[base + j][9:0]) begin
                    $display("  dl_d[%0d][%0d] Got=%3d  Exp=%3d  MISMATCH",
                             j / 5, j % 5, dld_out[j], gld_dl[base + j][9:0]);
                    case_err = case_err + 1;
                end
            end

            if (case_err == 0)
                $display("  rlimit + 25 dl pass-through MATCH  -> PASS");
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
            $display("    **  R-Limit Compute SYN       **");
        `else
            $display("    ********************************");
            $display("    **  R-Limit Compute RTL       **");
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
            $display("    **  R-Limit Compute SYN       **");
        `else
            $display("    ********************************");
            $display("    **  R-Limit Compute RTL       **");
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
        initial $sdf_annotate("adc_rlimit_compute_syn.sdf", dut);
    `endif

    `ifdef FSDB
        initial begin
            $fsdbDumpfile("adc_rlimit_compute.fsdb");
            $fsdbDumpvars("+struct", "+mda", adc_rlimit_compute_tb);
        end
    `endif

    `ifdef VCD
        initial begin
            $dumpfile("adc_rlimit_compute.vcd");
            $dumpvars(0, adc_rlimit_compute_tb);
        end
    `endif

endmodule
