//==============================================================================
// Testbench: t_compute_fuse_tb
// Description:
//   Self-checking testbench for t_compute_fuse top.
//
// Pattern file (48-bit per case):
//   [47:40] dark
//   [39:32] A
//   [31:24] src_r
//   [23:16] src_g
//   [15: 8] src_b
//   [ 7: 0] case_id
//
// Golden file (40-bit per case):
//   [39:32] tx_raw
//   [31:24] out_r
//   [23:16] out_g
//   [15: 8] out_b
//   [ 7: 0] case_id
//==============================================================================

`timescale 1ns/10ps
`define CYCLE 10.0
`define NUM_PATTERNS 20

`ifdef SYN
    `include "t_compute_fuse_syn.sv"
`else
    `include "../00_src/IPU/t_computing.sv"
    `include "../00_src/IPU/fusing.sv"
    `include "../00_src/IPU/t_compute_fuse.sv"
`endif

module t_compute_fuse_tb;

    bit clk;
    always #(`CYCLE/2) clk = ~clk;

    logic       rst_n;
    logic       i_valid;
    logic [7:0] i_dark;
    logic [7:0] i_A;
    logic [7:0] i_src_r;
    logic [7:0] i_src_g;
    logic [7:0] i_src_b;

    logic       o_valid;
    logic [7:0] o_tx_raw;
    logic [7:0] o_tx_used;
    logic [7:0] o_out_r;
    logic [7:0] o_out_g;
    logic [7:0] o_out_b;

    reg [47:0] pat_mem [`NUM_PATTERNS];
    reg [39:0] gld_mem [`NUM_PATTERNS];

    logic [7:0] exp_tx_raw;
    logic [7:0] exp_out_r;
    logic [7:0] exp_out_g;
    logic [7:0] exp_out_b;
    logic [7:0] exp_case_id;

    logic [7:0] in_case_id;
    logic [7:0] exp_tx_used;

    integer i;
    integer err;
    integer case_err;

    t_compute_fuse #(
        .OMEGA_Q8(8'd255),
        .TX_MIN(8'd15),
        .TX_WHEN_A_ZERO(8'd15)
    ) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .i_valid  (i_valid),
        .i_dark   (i_dark),
        .i_A      (i_A),
        .i_src_r  (i_src_r),
        .i_src_g  (i_src_g),
        .i_src_b  (i_src_b),
        .o_valid  (o_valid),
        .o_tx_raw (o_tx_raw),
        .o_tx_used(o_tx_used),
        .o_out_r  (o_out_r),
        .o_out_g  (o_out_g),
        .o_out_b  (o_out_b)
    );

    initial begin
        clk = 0;

        $readmemh("../09_pattern/t_compute_fuse_input.hex",  pat_mem);
        $readmemh("../07_golden_output/t_compute_fuse_golden.hex", gld_mem);

        rst_n   = 0;
        i_valid = 0;
        i_dark  = 8'd0;
        i_A     = 8'd0;
        i_src_r = 8'd0;
        i_src_g = 8'd0;
        i_src_b = 8'd0;

        err = 0;

        #(`CYCLE*3);
        rst_n = 1;
        @(posedge clk);

        $display("\n");
        $display("================================================================");
        $display("        t_compute_fuse - RTL Testbench");
        $display("================================================================");
        $display("Total test cases : %0d", `NUM_PATTERNS);
        $display("Pipeline latency : 2 cycles");
        $display("================================================================\n");

        for (i = 0; i < `NUM_PATTERNS; i = i + 1) begin
            // unpack pattern
            i_dark    = pat_mem[i][47:40];
            i_A       = pat_mem[i][39:32];
            i_src_r   = pat_mem[i][31:24];
            i_src_g   = pat_mem[i][23:16];
            i_src_b   = pat_mem[i][15:8];
            in_case_id = pat_mem[i][7:0];

            // unpack golden
            exp_tx_raw  = gld_mem[i][39:32];
            exp_out_r   = gld_mem[i][31:24];
            exp_out_g   = gld_mem[i][23:16];
            exp_out_b   = gld_mem[i][15:8];
            exp_case_id = gld_mem[i][7:0];
            exp_tx_used = (gld_mem[i][39:32] < 8'd15) ? 8'd15 : gld_mem[i][39:32];

            // case id consistency check
            case_err = 0;
            if (in_case_id !== exp_case_id) begin
                $display("Case %0d ERROR: case_id mismatch between pattern(%0d) and golden(%0d)",
                         i, in_case_id, exp_case_id);
                case_err = case_err + 1;
            end

            // drive 1 pulse valid
            @(posedge clk);
            i_valid <= 1'b1;

            @(posedge clk);
            i_valid <= 1'b0;

            // wait pipeline output
            @(posedge clk);
            @(posedge clk);

            $display("----------- Case %2d (id=%0d) -----------", i, exp_case_id);
            $display("  IN : dark=%3d A=%3d src=(%3d,%3d,%3d)",
                     i_dark, i_A, i_src_r, i_src_g, i_src_b);
            $display("  OUT: tx_raw=%3d tx_used=%3d rgb=(%3d,%3d,%3d) o_valid=%0d",
                     o_tx_raw, o_tx_used, o_out_r, o_out_g, o_out_b, o_valid);
            $display("  EXP: tx_raw=%3d tx_used=%3d rgb=(%3d,%3d,%3d)",
                     exp_tx_raw, exp_tx_used, exp_out_r, exp_out_g, exp_out_b);

            if (o_valid !== 1'b1) begin
                $display("  ERROR: o_valid not asserted");
                case_err = case_err + 1;
            end
            if (o_tx_raw !== exp_tx_raw) begin
                $display("  ERROR: tx_raw mismatch");
                case_err = case_err + 1;
            end
            if (o_tx_used !== exp_tx_used) begin
                $display("  ERROR: tx_used mismatch");
                case_err = case_err + 1;
            end
            if (o_out_r !== exp_out_r) begin
                $display("  ERROR: out_r mismatch");
                case_err = case_err + 1;
            end
            if (o_out_g !== exp_out_g) begin
                $display("  ERROR: out_g mismatch");
                case_err = case_err + 1;
            end
            if (o_out_b !== exp_out_b) begin
                $display("  ERROR: out_b mismatch");
                case_err = case_err + 1;
            end

            if (case_err == 0) begin
                $display("  Result: PASS\n");
            end else begin
                $display("  Result: FAIL (%0d errors)\n", case_err);
                err = err + case_err;
            end
        end

        #(`CYCLE*2);
        $display("========================================");
        $display("        SIMULATION SUMMARY              ");
        $display("========================================");
        if (err == 0) begin
            $display("All %0d cases passed!", `NUM_PATTERNS);
        end else begin
            $display("Total errors: %0d", err);
        end

        $finish;
    end

    `ifdef SYN
        initial $sdf_annotate("t_compute_fuse_syn.sdf", dut);
    `endif

    `ifdef FSDB
        initial begin
            $fsdbDumpfile("t_compute_fuse.fsdb");
            $fsdbDumpvars("+struct", "+mda", t_compute_fuse_tb);
        end
    `endif

    `ifdef VCD
        initial begin
            $dumpfile("t_compute_fuse.vcd");
            $dumpvars(0, t_compute_fuse_tb);
        end
    `endif

endmodule
