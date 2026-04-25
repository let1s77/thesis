`timescale 1ns/10ps
`define CYCLE 10.0  // 100MHz clock

`ifdef SYN
    `include "/usr/cad/CBDK/Nangate45/2010.12/Front_End/Verilog/NangateOpenCellLibrary.v"
    `include "dark_channel_syn.sv"
`else
    `include "../00_src/dark_channel.sv"
    `include "../00_src/src_min.sv"
    `include "../00_src/search_block_min.sv"
`endif


module dark_channel_tb;
    
    // Clock generation
    bit clk;
    always #(`CYCLE/2) clk = ~clk;
    
    // Interface instantiation
    dark_channel_if vif(clk);
    
    // Pattern and golden data
    reg [23:0] pattern [0:19];  // 20 test patterns
    reg [7:0]  golden  [0:19];  // 20 golden outputs
    integer i, err;

    // Instantiate DUT in Simple Mode (ENABLE_SPATIAL_FILTER = 0)
    // This mode computes only min(R,G,B) per pixel - matches golden output
    dark_channel #(
        .ENABLE_SPATIAL_FILTER(0)  // Simple mode for testbench
    ) dut (
        .i_clk      (clk),
        .i_rst_n    (vif.rst_n),
        .i_valid    (1'b0),          // Not used in simple mode
        .i_color    (vif.color),
        .o_valid    (),              // Not used in simple mode
        .o_dark_ch  (vif.dark_ch)
    );

    // Main test procedure
    initial begin
        // Memory initialization
        $readmemh("../07_golden_output/pattern_dark_channel.hex", pattern);
        $readmemh("../07_golden_output/golden_dark_channel.hex", golden);
        
        err = 0;
        vif.rst_n = 0;
        vif.cb.color <= 24'h0;
        
        // Reset sequence
        #(`CYCLE*2);
        vif.rst_n = 1;
        @(vif.cb); // Wait one cycle after reset
        
        $display("\n");
        $display("================================================================");
        $display("        Dark Channel Prior - RTL Testbench");
        $display("================================================================");
        $display("Total test patterns: 20");
        $display("Algorithm: dark_ch = min(R, G, B)");
        $display("================================================================\n");
        
        // Test all patterns
        for(i=0; i<20; i=i+1) begin
            // Apply input at clocking block
            @(vif.cb);
            vif.cb.color <= pattern[i];
            
            // Wait for DUT to process
            // src_min has 1 cycle latency, need 2 cycles total
            @(vif.cb);  // Cycle 1: Input sampled by DUT
            @(vif.cb);  // Cycle 2: Output propagated through src_min register
            
            // Check result
            $display("----------- Pattern %2d: RGB = %06h -----------", i+1, pattern[i]);
            $display("  R=%3d, G=%3d, B=%3d", pattern[i][7:0], pattern[i][15:8], pattern[i][23:16]);
            $display("  Dark Channel Output: %3d (0x%02h)", vif.cb.dark_ch, vif.cb.dark_ch);
            $display("  Golden Expected:     %3d (0x%02h)", golden[i], golden[i]);
            
            if(vif.cb.dark_ch === golden[i]) begin
                $display("  Result: PASS ✓");
            end
            else begin
                $display("  Result: FAIL ✗");
                $display("  ERROR: Mismatch! Got %d, expected %d", vif.cb.dark_ch, golden[i]);
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
            $display("        ****************************               ");
            $display("        **  Dark Channel - SYN   **               ");
        `else
            $display("        ****************************               ");
            $display("        **  Dark Channel - RTL   **               ");
        `endif
            $display("        ****************************               ");
            $display("        **                        **       |\__||  ");
            $display("        **  Congratulations !!    **      / O.O  | ");
            $display("        **                        **    /_____   | ");
            $display("        **  SIMULATION PASS !!    **   /^ ^ ^ \\  |");
            $display("        **                        **  |^ ^ ^ ^ |w| ");
            $display("        ****************************   \\m___m__|_|");
            $display("        All 20 patterns passed!");
            $display("\n");
        end
        else begin
        `ifdef SYN
            $display("        ****************************               ");
            $display("        **  Dark Channel - SYN   **               ");
        `else
            $display("        ****************************               ");
            $display("        **  Dark Channel - RTL   **               ");
        `endif
            $display("        ****************************               ");
            $display("        **                        **       |\__||  ");
            $display("        **  OOPS!!                **      / X,X  | ");
            $display("        **                        **    /_____   | ");
            $display("        **  SIMULATION Failed!!   **   /^ ^ ^ \\  |");
            $display("        **                        **  |^ ^ ^ ^ |w| ");
            $display("        ****************************   \\m___m__|_|");
            $display("         Totally has %d errors                     ", err); 
            $display("\n");
        end
        
        $finish;
    end
    
    `ifdef SYN
        initial $sdf_annotate("dark_channel_syn.sdf", dut);
    `endif

    `ifdef FSDB
        initial begin
            $fsdbDumpfile("dark_channel.fsdb");
            $fsdbDumpvars("+struct", "+mda", dut);
        end
    `endif
    
    `ifdef VCD
        initial begin
            $dumpfile("dark_channel.vcd");
            $dumpvars(0, dark_channel_tb);
        end
    `endif
  
endmodule
