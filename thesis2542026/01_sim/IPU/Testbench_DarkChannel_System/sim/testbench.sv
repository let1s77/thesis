///////////////////////////////////////////////////                   
//   Author: DA2 Project                         // 
//   Project: Dark Channel Image Processor       //
//   Description: System-level testbench for     //
//                dark channel prior processing  //
///////////////////////////////////////////////////

`timescale 1ns/10ps
`define CYCLE 10              // 100MHz clock
`define MAX_CYCLE 5000000     // Maximum simulation cycles

// Include paths relative to 02_questasim/ folder
`include "../01_sim/IPU/Testbench_DarkChannel_System/src/ROM.v"
`include "../01_sim/IPU/Testbench_DarkChannel_System/src/RAM.v"

`ifdef SYN
    `include "/usr/cad/CBDK/Nangate45/2010.12/Front_End/Verilog/NangateOpenCellLibrary.v"
    `include "../01_sim/IPU/Testbench_DarkChannel_System/syn/top_syn.v"
`else
    `include "../01_sim/IPU/Testbench_DarkChannel_System/src/top.sv"
`endif

module testbench();

    // Image size parameters
    localparam IMG_W = 128;
    localparam IMG_H = 128;
    localparam TOTAL_PIXELS = IMG_W * IMG_H;  // 16384

    // Signals
    logic        clk = 0;
    logic        rst_n = 0;
    logic        dark_DONE;
    logic        rom_en;
    logic [13:0] rom_addr;
    logic [23:0] rom_data;
    logic        ram_ren;
    logic        ram_wen;
    logic [13:0] ram_addr;
    logic [7:0]  ram_idata;
    logic [7:0]  ram_odata;

    // FSM states
    typedef enum logic [1:0] {
        RST_state, PROC_state, CHECK_state
    } fsm;
    fsm state = RST_state;

    // Clock generation
    always #(`CYCLE/2) clk = ~clk;

    // DUT instantiation
    top i_TOP(
        .i_clk       (clk),
        .i_rst_n     (rst_n),
        .o_dark_done (dark_DONE),
        .o_rom_en    (rom_en),
        .o_rom_addr  (rom_addr),
        .i_rom_data  (rom_data),
        .o_ram_ren   (ram_ren),
        .o_ram_wen   (ram_wen),
        .o_ram_addr  (ram_addr),
        .o_ram_data  (ram_idata),
        .i_ram_data  (ram_odata)
    );

    // ROM: Input RGB image
    ROM i_ROM (
        .i_clk  (clk),
        .i_ren  (rom_en),
        .i_addr (rom_addr),
        .o_data (rom_data)
    );

    // RAM: Output dark channel image
    RAM i_RAM (
        .i_clk  (clk),
        .i_ren  (ram_ren),
        .i_wen  (ram_wen),
        .i_addr (ram_addr),
        .i_data (ram_idata),
        .o_data (ram_odata)
    );

    //=========================================================================
    // Pattern definition
    // Note: Paths are relative to 02_questasim/ folder where simulation runs
    //=========================================================================
    `ifdef P1  // Tux image
        string pattern_name     = "../01_sim/Testbench_DarkChannel_System/sim/image/Tux.bmp";
        string dark_name        = "../01_sim/Testbench_DarkChannel_System/sim/image/dark_Tux.bmp";
        string dark_golden_name = "../01_sim/Testbench_DarkChannel_System/sim/golden/G1/dark_Tux_Golden.dat";
        integer verify_design   = 1;

    `elsif P2  // Little Mole
        string pattern_name     = "../01_sim/Testbench_DarkChannel_System/sim/image/Little-Mole.bmp";
        string dark_name        = "../01_sim/Testbench_DarkChannel_System/sim/image/dark_Little-Mole.bmp";
        string dark_golden_name = "../01_sim/Testbench_DarkChannel_System/sim/golden/G2/dark_LM_Golden.dat";
        integer verify_design   = 1;

    `elsif TEST // Custom test image (512x512)
        string pattern_name     = "../01_sim/IPU/Testbench_DarkChannel_System/sim/image/test.bmp";
        string dark_name        = "../01_sim/IPU/Testbench_DarkChannel_System/sim/image/dark_test.bmp";
        string dark_golden_name = "";
        integer verify_design   = 0;

    `else // Default - use test_128.bmp (128x128)
        string pattern_name     = "../01_sim/IPU/Testbench_DarkChannel_System/sim/image/test_128.bmp";
        string dark_name        = "../01_sim/IPU/Testbench_DarkChannel_System/sim/image/dark_test_128.bmp";
        string dark_golden_name = "";
        integer verify_design   = 0;
    `endif

    //=========================================================================
    // Variables
    //=========================================================================
    integer dark_error = -1;
    integer fp;
    logic [7:0] header [53:0];
    logic [7:0] read_img;
    logic [7:0] dark_golden [TOTAL_PIXELS-1 : 0];

    //=========================================================================
    // Load BMP image as pattern
    //=========================================================================
    initial begin
        `ifndef P1
            `ifndef P2
                `ifndef TEST
                    $display("Info: No pattern macro (P1, P2, TEST) defined. Using default test_128.bmp (128x128)");
                `endif
            `endif
        `endif

        fp = $fopen(pattern_name, "rb");
        if (!fp) begin
            $display("Error: Cannot open file: %s", pattern_name);
            $finish;
        end

        // Read BMP header (54 bytes)
        for (int i = 0; i < 54; i++) begin
            header[i] = $fgetc(fp);
        end

        // Read RGB image data
        for (int i = 0; i < TOTAL_PIXELS*3; i++) begin
            read_img = $fgetc(fp);
            case (i % 3)
                0: i_ROM.mem[i/3][23:16] = read_img; // Blue
                1: i_ROM.mem[i/3][15:8]  = read_img; // Green
                2: i_ROM.mem[i/3][7:0]   = read_img; // Red
                default: $display("Error: Invalid channel index!");
            endcase
        end
        $fclose(fp);

        // Debug: Print first few ROM values
        $display("\n=== Input Image Debug Info ===");
        for (int j = 0; j < 5; j++) begin
            $display("ROM[%0d]: R=%h, G=%h, B=%h", j,
                     i_ROM.mem[j][7:0], i_ROM.mem[j][15:8], i_ROM.mem[j][23:16]);
        end

        // Load golden data if available
        if (verify_design) begin
            $readmemh(dark_golden_name, dark_golden);
            $display("\n=== Golden Data Loaded ===");
            for (int k = 0; k < 5; k++) begin
                $display("Golden[%0d]: %h", k, dark_golden[k]);
            end
        end
    end

    //=========================================================================
    // Main FSM
    //=========================================================================
    always @(posedge clk) begin
        case (state)
            RST_state: begin
                #(`CYCLE/2) state <= PROC_state;
                #(`CYCLE/2) rst_n <= 1;
            end

            PROC_state: begin
                if (dark_DONE === 1) begin
                    state <= CHECK_state;
                    plot_dark();
                    if (verify_design) compare();
                end else begin
                    state <= PROC_state;
                end
            end

            CHECK_state: begin
                state <= RST_state;
            end

            default: begin
                state <= RST_state;
            end
        endcase
    end

    //=========================================================================
    // SDF annotation for synthesis
    //=========================================================================
    `ifdef SYN
        initial $sdf_annotate("../syn/top_syn.sdf", i_TOP);
    `endif

    //=========================================================================
    // Waveform generation
    //=========================================================================
    initial begin
        `ifdef FSDB
            $fsdbDumpfile("dark_channel.fsdb");
            $fsdbDumpvars;
        `elsif FSDB_ALL
            $fsdbDumpfile("dark_channel.fsdb");
            $fsdbDumpvars("+struct", "+mda", i_TOP);
            $fsdbDumpvars("+struct", "+mda", i_RAM);
        `endif
    end

    //=========================================================================
    // Timeout watchdog
    //=========================================================================
    initial begin
        #(`MAX_CYCLE);
        $display("\n");
        $display("================================================================");
        `ifdef SYN
            $display("        **  Dark Channel System - SYN  **");
        `else
            $display("        **  Dark Channel System - RTL  **");
        `endif
        $display("================================================================");
        $display("        **                        **       |\__||  ");
        $display("        **  OOPS!!                **      / X,X  | ");
        $display("        **                        **    /_____   | ");
        $display("        **  Timeout Reached!!     **   /^ ^ ^ \\  |");
        $display("        **                        **  |^ ^ ^ ^ |w| ");
        $display("================================================================");
        $display("\n!!! Reached maximum cycle number !!!");
        
        if (dark_error == -1) 
            $display("Error: dark_done signal was never asserted!");
        $finish;
    end

    //=========================================================================
    // Compare task
    //=========================================================================
    task compare;
        dark_error = 0;
        
        for (int i = 0; i < TOTAL_PIXELS; i++) begin
            if (dark_golden[i] !== i_RAM.mem[i]) begin
                if (dark_error <= 10) begin
                    $display("Mismatch at pixel[%d]: RAM=%h, Golden=%h", 
                             i, i_RAM.mem[i], dark_golden[i]);
                end
                dark_error++;
            end
        end

        if (dark_error > 10) 
            $display("Error: More than 10 mismatches found!");
        
        if (dark_error == 0) 
            $display("Dark Channel conversion is CORRECT!");

        // Print result
        if (dark_error == 0) begin
            $display("\n");
            $display("================================================================");
            `ifdef SYN
                $display("        **  Dark Channel System - SYN  **");
            `else
                $display("        **  Dark Channel System - RTL  **");
            `endif
            $display("================================================================");
            $display("        **                        **       |\__||  ");
            $display("        **  Congratulations !!    **      / O.O  | ");
            $display("        **                        **    /_____   | ");
            $display("        **  SIMULATION PASS!!     **   /^ ^ ^ \\  |");
            $display("        **                        **  |^ ^ ^ ^ |w| ");
            $display("================================================================");
            $display("\n");
            $finish;
        end else begin
            $display("\n");
            $display("================================================================");
            `ifdef SYN
                $display("        **  Dark Channel System - SYN  **");
            `else
                $display("        **  Dark Channel System - RTL  **");
            `endif
            $display("================================================================");
            $display("        **                        **       |\__||  ");
            $display("        **  OOPS!!                **      / X,X  | ");
            $display("        **                        **    /_____   | ");
            $display("        **  SIMULATION FAILED!!   **   /^ ^ ^ \\  |");
            $display("        **                        **  |^ ^ ^ ^ |w| ");
            $display("================================================================");
            $display("         Total errors: %d", dark_error);
            $display("\n");
            $finish;
        end
    endtask

    //=========================================================================
    // Plot dark channel image task
    //=========================================================================
    task plot_dark;
        integer obmp;

        $display("\nGenerating dark channel image...");

        obmp = $fopen(dark_name, "wb");
        
        // Write BMP header
        for (int i = 0; i < 54; i++) begin
            $fwrite(obmp, "%c", header[i]);
        end

        // Write grayscale image (dark channel is single channel)
        // BMP requires RGB, so write same value 3 times
        for (int i = 0; i < TOTAL_PIXELS; i++) begin
            $fwrite(obmp, "%c", i_RAM.mem[i]); // B
            $fwrite(obmp, "%c", i_RAM.mem[i]); // G
            $fwrite(obmp, "%c", i_RAM.mem[i]); // R
        end

        $fclose(obmp);
        $display("Dark channel image saved to: %s\n", dark_name);

        if (!verify_design) begin
            $display("Custom image '%s' processed successfully.\n", pattern_name);
            $finish;
        end
    endtask

endmodule
