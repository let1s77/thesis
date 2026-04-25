`timescale 1ns/10ps
`define CYCLE 10.0  // 100MHz clock

`ifdef SYN
    `include "/usr/cad/CBDK/Nangate45/2010.12/Front_End/Verilog/NangateOpenCellLibrary.v"
    `include "estimate_transmission_syn.sv"
`else
    `include "../00_src/IPU/estimate_transmission.sv"
    `include "../00_src/IPU/invA_lut_q16.sv"
    `include "../00_src/IPU/norm_channel_q16.sv"
    `include "../00_src/IPU/min3_u8.sv"
    `include "../00_src/IPU/omega_clamp_t.sv"
    `include "../00_src/IPU/spatial_min3x3.sv"
    `include "../00_src/IPU/search_block_min.sv"
`endif

module tb_estimate_transmission;

    // ============================================================
    // Parameters for this TB
    // ============================================================
    localparam int IMG_WIDTH = 20;
    localparam bit ENABLE_SPATIAL_FILTER = 1'b0;

    localparam logic [7:0] A_R = 8'd200;
    localparam logic [7:0] A_G = 8'd200;
    localparam logic [7:0] A_B = 8'd200;

    localparam logic       USE_SKY = 1'b0;
    localparam logic [7:0] T_SKY   = 8'd102;

    localparam logic [7:0] OMEGA_Q8 = 8'hF3;
    localparam logic [7:0] T_MIN    = 8'd26;

    // ============================================================
    // Clock generation
    // ============================================================
    bit clk;
    always #(`CYCLE/2) clk = ~clk;

    // ============================================================
    // DUT I/O
    // ============================================================
    logic        rst_n;
    logic        i_valid;
    logic [23:0] i_color;

    logic [7:0]  i_A_r;
    logic [7:0]  i_A_g;
    logic [7:0]  i_A_b;

    logic        i_sky;
    logic        i_use_sky;
    logic [7:0]  i_t_sky;

    logic        o_valid;
    logic [7:0]  o_t;

    // ============================================================
    // Pattern / Golden memories
    // ============================================================
    reg [23:0] pattern [0:19];
    reg        sky_pat [0:19];
    reg [7:0]  golden  [0:19];

    integer i, err;

    // ============================================================
    // DUT
    // ============================================================
    estimate_transmission #(
        .IMG_WIDTH             (IMG_WIDTH),
        .ENABLE_SPATIAL_FILTER (ENABLE_SPATIAL_FILTER),
        .OMEGA_Q8              (OMEGA_Q8),
        .T_MIN                 (T_MIN)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),

        .i_valid    (i_valid),
        .i_color    (i_color),

        .i_A_r      (i_A_r),
        .i_A_g      (i_A_g),
        .i_A_b      (i_A_b),

        .i_sky      (i_sky),
        .i_use_sky  (i_use_sky),
        .i_t_sky    (i_t_sky),

        .o_valid    (o_valid),
        .o_t        (o_t)
    );

    // ============================================================
    // Main test procedure
    // ============================================================
    initial begin
        clk = 0;

        $readmemh("../09_pattern/rgb.hex",            pattern);
        $readmemb("../09_pattern/sky.hex",            sky_pat);
        $readmemh("../07_golden_output/t_golden.hex", golden);

        err     = 0;
        rst_n   = 0;
        i_valid = 0;
        i_color = 24'h0;
        i_sky   = 1'b0;

        i_A_r   = A_R;
        i_A_g   = A_G;
        i_A_b   = A_B;

        i_use_sky = USE_SKY;
        i_t_sky   = T_SKY;

        // Reset sequence
        #(`CYCLE*2);
        rst_n = 1;
        @(posedge clk); // wait one cycle after reset

        $display("\n");
        $display("================================================================");
        $display("        Estimate Transmission - RTL Testbench");
        $display("================================================================");
        $display("Total test patterns: 20");
        $display("Mode: ENABLE_SPATIAL_FILTER = 0");
        $display("Algorithm:");
        $display("  norm_c = sat8((pix_c * invA_q16) >> 16)");
        $display("  min_norm = min(norm_r, norm_g, norm_b)");
        $display("  t = 255 - ((OMEGA_Q8 * min_norm) >> 8)");
        $display("  clamp: t >= T_MIN");
        $display("================================================================\n");

        // ------------------------------------------------------------
        // Test all patterns
        // Latency simple mode:
        //   cycle 1: valid_s0 / min_norm_r
        //   cycle 2: o_valid / o_t
        // ------------------------------------------------------------
        $display("<at time %0t ns> [START] Run pattern tests (20 patterns)", $time);
        for(i=0; i<20; i=i+1) begin
            @(posedge clk);
            i_valid <= 1'b1;
            i_color <= pattern[i];
            i_sky   <= sky_pat[i];

            @(posedge clk);
            i_valid <= 1'b0;
            i_color <= 24'h0;
            i_sky   <= 1'b0;

            @(posedge clk);
            #1;  // let NBA settle — o_valid/o_t now valid

            $display("----------- Pattern %2d: RGB = %06h -----------", i+1, pattern[i]);
            $display("  R=%3d, G=%3d, B=%3d, SKY=%0d",
                      pattern[i][7:0], pattern[i][15:8], pattern[i][23:16], sky_pat[i]);
            $display("  o_valid = %0d", o_valid);
            $display("  Transmission Out: %3d (0x%02h)", o_t, o_t);
            $display("  Golden Expected : %3d (0x%02h)", golden[i], golden[i]);

            if(o_valid !== 1'b1) begin
                $display("  Result: FAIL ");
                $display("  ERROR: o_valid is not asserted when expected");
                err = err + 1;
            end
            else if(o_t === golden[i]) begin
                $display("  Result: PASS ");
            end
            else begin
                $display("  Result: FAIL ");
                $display("  ERROR: Mismatch! Got %d, expected %d", o_t, golden[i]);
                err = err + 1;
            end
            $display("");
        end

        // Final summary
        #(`CYCLE*2);
        $display("\n");
        $display("========================================");
        $display("        SIMULATION SUMMARY              ");
        $display("========================================");

        if(err === 0) begin
        `ifdef SYN
            $display("    ********************************");
            $display("    ** Estimate Transmission SYN  **");
        `else
            $display("    ********************************");
            $display("    ** Estimate Transmission RTL  **");
        `endif
            $display("    ********************************");
            $display("    **                            **       |\\__||  ");
            $display("    **  Congratulations !!        **      / O.O  | ");
            $display("    **                            **    /_____   | ");
            $display("    **  SIMULATION PASS !!        **   /^ ^ ^ \\\\  |");
            $display("    **                            **  |^ ^ ^ ^ |w| ");
            $display("    ********************************   \\m___m__|_|");
            $display("    All 20 patterns passed!");
            $display("\n");
        end
        else begin
        `ifdef SYN
            $display("    ********************************");
            $display("    ** Estimate Transmission SYN  **");
        `else
            $display("    ********************************");
            $display("    ** Estimate Transmission RTL  **");
        `endif
            $display("    ********************************");
            $display("    **                            **       |\\__||  ");
            $display("    **  OOPS!!                    **      / X,X  | ");
            $display("    **                            **    /_____   | ");
            $display("    **  SIMULATION Failed!!       **   /^ ^ ^ \\\\  |");
            $display("    **                            **  |^ ^ ^ ^ |w| ");
            $display("    ********************************   \\m___m__|_|");
            $display("    Totally has %d errors", err);
            $display("\n");
        end

        $finish;
    end

    `ifdef SYN
        initial $sdf_annotate("estimate_transmission_syn.sdf", dut);
    `endif

    `ifdef FSDB
        initial begin
            $fsdbDumpfile("estimate_transmission.fsdb");
            $fsdbDumpvars("+struct", "+mda", tb_estimate_transmission);
        end
    `endif

    `ifdef VCD
        initial begin
            $dumpfile("estimate_transmission.vcd");
            $dumpvars(0, tb_estimate_transmission);
        end
    `endif

endmodule