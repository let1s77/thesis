//==============================================================================
// Testbench: adc_path_length_tb
// Description: Unit test cho adc_path_length module
//
// Test Strategy:
//   - Load 20 test cases (25 dp_total each) tu hex file
//   - Drive 25 dp inputs, verify 25 d_lambda outputs
//   - LAMBDA_Q8 = 51 (lambda ~ 0.2)
//
// Pattern format (16-bit per value, 25 per case):
//   dp_total [8:0] zero-padded to 16-bit
//
// Golden format (16-bit per value, 25 per case):
//   d_lambda [9:0] zero-padded to 16-bit
//==============================================================================

`timescale 1ns/10ps
`define CYCLE 10.0
`define NUM_PATTERNS 20

`ifdef SYN
    `include "adc_path_length_syn.sv"
`else
    `include "../00_src/IPU/adc_path_length.sv"
`endif

module adc_path_length_tb;

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
    logic [8:0] dpin  [0:24];   // dp_total inputs
    logic [9:0] dlout [0:24];   // d_lambda outputs

    //==========================================================================
    // Pattern / Golden memories
    //==========================================================================
    reg [15:0] pat_mem [0:`NUM_PATTERNS*25-1];   // dp_total (9-bit in 16-bit)
    reg [15:0] gld_mem [0:`NUM_PATTERNS*25-1];   // d_lambda (10-bit in 16-bit)

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
    // DUT Instance (LAMBDA_Q8 = 51)
    //==========================================================================
    adc_path_length #(.LAMBDA_Q8(8'd51)) dut (
        .clk     (clk),
        .rst_n   (rst_n),
        .i_valid (i_valid),
        // dp inputs
        .dp00(dpin[0]),  .dp01(dpin[1]),  .dp02(dpin[2]),  .dp03(dpin[3]),  .dp04(dpin[4]),
        .dp10(dpin[5]),  .dp11(dpin[6]),  .dp12(dpin[7]),  .dp13(dpin[8]),  .dp14(dpin[9]),
        .dp20(dpin[10]), .dp21(dpin[11]), .dp22(dpin[12]), .dp23(dpin[13]), .dp24(dpin[14]),
        .dp30(dpin[15]), .dp31(dpin[16]), .dp32(dpin[17]), .dp33(dpin[18]), .dp34(dpin[19]),
        .dp40(dpin[20]), .dp41(dpin[21]), .dp42(dpin[22]), .dp43(dpin[23]), .dp44(dpin[24]),
        // dl outputs
        .dl00(dlout[0]),  .dl01(dlout[1]),  .dl02(dlout[2]),  .dl03(dlout[3]),  .dl04(dlout[4]),
        .dl10(dlout[5]),  .dl11(dlout[6]),  .dl12(dlout[7]),  .dl13(dlout[8]),  .dl14(dlout[9]),
        .dl20(dlout[10]), .dl21(dlout[11]), .dl22(dlout[12]), .dl23(dlout[13]), .dl24(dlout[14]),
        .dl30(dlout[15]), .dl31(dlout[16]), .dl32(dlout[17]), .dl33(dlout[18]), .dl34(dlout[19]),
        .dl40(dlout[20]), .dl41(dlout[21]), .dl42(dlout[22]), .dl43(dlout[23]), .dl44(dlout[24]),
        .o_valid (o_valid)
    );

    //==========================================================================
    // Main Test Sequence
    //==========================================================================
    initial begin
        clk = 0;

        $readmemh("../09_pattern/pattern_path_length.hex", pat_mem);
        $readmemh("../07_golden_output/golden_path_length.hex", gld_mem);

        err     = 0;
        rst_n   = 0;
        i_valid = 0;
        for (j = 0; j < 25; j++) dpin[j] = 9'd0;

        #(`CYCLE*3);
        rst_n = 1;
        @(posedge clk);

        $display("\n");
        $display("================================================================");
        $display("        ADC Path Length - RTL Testbench");
        $display("================================================================");
        $display("Total test cases : %0d  (25 values per case)", `NUM_PATTERNS);
        $display("LAMBDA_Q8        : 51  (lambda ~ 0.2)");
        $display("Pipeline stages  : 1");
        $display("================================================================\n");

        for (i = 0; i < `NUM_PATTERNS; i = i + 1) begin
            base = i * 25;

            @(posedge clk);
            i_valid <= 1;
            for (j = 0; j < 25; j++) dpin[j] <= pat_mem[base + j][8:0];

            @(posedge clk);
            i_valid <= 0;

            // 1 pipeline stage
            @(posedge clk);

            case_err = 0;
            $display("----------- Case %2d: %-24s -----------", i, case_names[i]);

            if (o_valid !== 1'b1) begin
                $display("  ERROR: o_valid not asserted!");
                case_err = case_err + 1;
            end

            for (j = 0; j < 25; j++) begin
                if (dlout[j] !== gld_mem[base + j][9:0]) begin
                    $display("  [%0d][%0d] Got=%3d  Exp=%3d  MISMATCH",
                             j / 5, j % 5, dlout[j], gld_mem[base + j][9:0]);
                    case_err = case_err + 1;
                end
            end

            if (case_err == 0)
                $display("  All 25 d_lambda MATCH  -> PASS");
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
            $display("    **  Path Length SYN            **");
        `else
            $display("    ********************************");
            $display("    **  Path Length RTL            **");
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
            $display("    **  Path Length SYN            **");
        `else
            $display("    ********************************");
            $display("    **  Path Length RTL            **");
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
        initial $sdf_annotate("adc_path_length_syn.sdf", dut);
    `endif

    `ifdef FSDB
        initial begin
            $fsdbDumpfile("adc_path_length.fsdb");
            $fsdbDumpvars("+struct", "+mda", adc_path_length_tb);
        end
    `endif

    `ifdef VCD
        initial begin
            $dumpfile("adc_path_length.vcd");
            $dumpvars(0, adc_path_length_tb);
        end
    `endif

endmodule
