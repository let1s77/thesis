//==============================================================================
// Testbench: adc_ase_masked_min_tb
// Description: Unit test cho adc_ase_masked_min module
//
// Test Strategy:
//   - Load 20 test cases: rlimit + dl[25] + mc[25]
//   - Drive all inputs, verify o_adc output
//   - This is the final stage: ASE mask + min filter
//
// Pattern files:
//   pattern_ase_rlimit.hex : 16-bit, 1 per case  (r_limit)
//   pattern_ase_dl.hex     : 16-bit, 25 per case (d_lambda)
//   pattern_ase_mc.hex     : 8-bit,  25 per case (MC window pixels)
//
// Golden file:
//   golden_ase_adc.hex     : 8-bit,  1 per case  (ADC result)
//==============================================================================

`timescale 1ns/10ps
`define CYCLE 10.0
`define NUM_PATTERNS 20

`ifdef SYN
    `include "adc_ase_masked_min_syn.sv"
`else
    `include "../00_src/IPU/adc_ase_masked_min.sv"
`endif

module adc_ase_masked_min_tb;

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
    logic [9:0] rlimit_in;
    logic [9:0] dlin  [0:24];   // d_lambda inputs
    logic [7:0] mcin  [0:24];   // MC window pixel inputs
    logic [7:0] adc_out;

    //==========================================================================
    // Pattern / Golden memories
    //==========================================================================
    reg [15:0] pat_rlimit [0:`NUM_PATTERNS-1];       // rlimit (10-bit in 16-bit)
    reg [15:0] pat_dl     [0:`NUM_PATTERNS*25-1];    // dl (10-bit in 16-bit)
    reg [7:0]  pat_mc     [0:`NUM_PATTERNS*25-1];    // mc (8-bit)
    reg [7:0]  gld_adc    [0:`NUM_PATTERNS-1];       // adc (8-bit)

    integer i, j, base, err;

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
    adc_ase_masked_min dut (
        .clk     (clk),
        .rst_n   (rst_n),
        .i_valid (i_valid),
        .i_rlimit(rlimit_in),
        // dl inputs
        .dl00(dlin[0]),  .dl01(dlin[1]),  .dl02(dlin[2]),  .dl03(dlin[3]),  .dl04(dlin[4]),
        .dl10(dlin[5]),  .dl11(dlin[6]),  .dl12(dlin[7]),  .dl13(dlin[8]),  .dl14(dlin[9]),
        .dl20(dlin[10]), .dl21(dlin[11]), .dl22(dlin[12]), .dl23(dlin[13]), .dl24(dlin[14]),
        .dl30(dlin[15]), .dl31(dlin[16]), .dl32(dlin[17]), .dl33(dlin[18]), .dl34(dlin[19]),
        .dl40(dlin[20]), .dl41(dlin[21]), .dl42(dlin[22]), .dl43(dlin[23]), .dl44(dlin[24]),
        // pw (MC) inputs
        .pw00(mcin[0]),  .pw01(mcin[1]),  .pw02(mcin[2]),  .pw03(mcin[3]),  .pw04(mcin[4]),
        .pw10(mcin[5]),  .pw11(mcin[6]),  .pw12(mcin[7]),  .pw13(mcin[8]),  .pw14(mcin[9]),
        .pw20(mcin[10]), .pw21(mcin[11]), .pw22(mcin[12]), .pw23(mcin[13]), .pw24(mcin[14]),
        .pw30(mcin[15]), .pw31(mcin[16]), .pw32(mcin[17]), .pw33(mcin[18]), .pw34(mcin[19]),
        .pw40(mcin[20]), .pw41(mcin[21]), .pw42(mcin[22]), .pw43(mcin[23]), .pw44(mcin[24]),
        // output
        .o_adc   (adc_out),
        .o_valid (o_valid)
    );

    //==========================================================================
    // Main Test Sequence
    //==========================================================================
    initial begin
        clk = 0;

        $readmemh("../09_pattern/pattern_ase_rlimit.hex", pat_rlimit);
        $readmemh("../09_pattern/pattern_ase_dl.hex",     pat_dl);
        $readmemh("../09_pattern/pattern_ase_mc.hex",     pat_mc);
        $readmemh("../07_golden_output/golden_ase_adc.hex", gld_adc);

        err       = 0;
        rst_n     = 0;
        i_valid   = 0;
        rlimit_in = 10'd0;
        for (j = 0; j < 25; j++) begin
            dlin[j] = 10'd0;
            mcin[j] = 8'd0;
        end

        #(`CYCLE*3);
        rst_n = 1;
        @(posedge clk);

        $display("\n");
        $display("================================================================");
        $display("        ADC ASE Masked Min - RTL Testbench");
        $display("================================================================");
        $display("Total test cases : %0d", `NUM_PATTERNS);
        $display("Pipeline stages  : 1");
        $display("================================================================\n");

        for (i = 0; i < `NUM_PATTERNS; i = i + 1) begin
            base = i * 25;

            // Drive rlimit, dl[25], mc[25]
            @(posedge clk);
            i_valid   <= 1;
            rlimit_in <= pat_rlimit[i][9:0];
            for (j = 0; j < 25; j++) begin
                dlin[j] <= pat_dl[base + j][9:0];
                mcin[j] <= pat_mc[base + j];
            end

            @(posedge clk);
            i_valid <= 0;

            // 1 pipeline stage
            @(posedge clk);

            // --- Compare ---
            $display("----------- Case %2d: %-24s -----------", i, case_names[i]);
            $display("  r_limit = %3d", pat_rlimit[i][9:0]);
            $display("  Got: adc = %3d (0x%02X)  o_valid = %0d",
                     adc_out, adc_out, o_valid);
            $display("  Exp: adc = %3d (0x%02X)",
                     gld_adc[i], gld_adc[i]);

            if (o_valid !== 1'b1) begin
                $display("  ERROR: o_valid not asserted!");
                err = err + 1;
            end
            else if (adc_out === gld_adc[i]) begin
                $display("  Result: PASS");
            end
            else begin
                $display("  Result: FAIL  MISMATCH!");
                err = err + 1;
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
            $display("    **  ASE Masked Min SYN        **");
        `else
            $display("    ********************************");
            $display("    **  ASE Masked Min RTL        **");
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
            $display("    **  ASE Masked Min SYN        **");
        `else
            $display("    ********************************");
            $display("    **  ASE Masked Min RTL        **");
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
        initial $sdf_annotate("adc_ase_masked_min_syn.sdf", dut);
    `endif

    `ifdef FSDB
        initial begin
            $fsdbDumpfile("adc_ase_masked_min.fsdb");
            $fsdbDumpvars("+struct", "+mda", adc_ase_masked_min_tb);
        end
    `endif

    `ifdef VCD
        initial begin
            $dumpfile("adc_ase_masked_min.vcd");
            $dumpvars(0, adc_ase_masked_min_tb);
        end
    `endif

endmodule
