//==============================================================================
// Testbench: purple_system_tb
// Description: System-level testbench for Purple Block Integration
//              Reads a real BMP image (128x128), runs through the full
//              2-pass pipeline, and generates output BMP images for:
//                - Dark Channel
//                - Grayscale
//                - Sky Recognition (binary mask)
//                - Transmission Map (from bank readback)
//
// 2-pass flow:
//   Pass 1: stream all pixels -> dark_channel -> atmospheric_light -> A
//   Pass 2: stream all pixels -> dark_channel + grayscale -> sky_recognition
//            -> estimate_transmission -> bank write -> swap -> bank read
//
// Run from: 02_questasim/
//   vsim -c -do "../01_sim/IPU/script/script_for_purple_system.tcl"
//==============================================================================

`timescale 1ns/1ps

module purple_system_tb;

    // ========================================================================
    // Parameters
    // ========================================================================
    localparam int IMG_WIDTH  = 128;
    localparam int IMG_HEIGHT = 128;
    localparam int NUM_PIXELS = IMG_WIDTH * IMG_HEIGHT;  // 16384
    localparam int ADDR_WIDTH = 14;

    localparam logic [7:0] OMEGA_Q8 = 8'hF3;   // ~0.95
    localparam logic [7:0] T_MIN    = 8'd26;    // ~0.10

    localparam logic [7:0] SKY_A0    = 8'd150;
    localparam logic       USE_DARK  = 1'b0;    // use grayscale for sky detection
    localparam logic       USE_SKY   = 1'b1;    // enable sky-aware transmission
    localparam logic [7:0] T_SKY     = 8'd255;  // sky pixels -> t = 255

    localparam HALF_CLK = 5;  // 100MHz

    // ========================================================================
    // I/O Paths (relative to 02_questasim/)
    // ========================================================================
    string img_input = "../01_sim/IPU/Testbench_DarkChannel_System/sim/image/test_128.bmp";
    string out_dir   = "../01_sim/IPU/Testbench_Purple_Block_Integration/sim/image/";

    // ========================================================================
    // Signals
    // ========================================================================
    logic        clk, rst_n;
    logic        i_valid;
    logic [23:0] i_color;
    logic        i_frame_start, i_frame_end;
    logic        i_bank_swap, i_bank_wr_clear, i_bank_rd_clear, i_bank_rd_en;

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
    // Storage
    // ========================================================================
    logic [23:0] rgb_mem    [0:NUM_PIXELS-1];   // Input image from BMP
    logic [7:0]  bmp_header [0:53];             // BMP 54-byte header

    logic [7:0]  cap_dark   [0:NUM_PIXELS-1];   // Dark channel capture
    logic [7:0]  cap_gray   [0:NUM_PIXELS-1];   // Grayscale capture
    logic [7:0]  cap_sky    [0:NUM_PIXELS-1];   // Sky mask (0 or 255)
    logic [7:0]  cap_tx     [0:NUM_PIXELS-1];   // Transmission map capture

    // ========================================================================
    // Clock
    // ========================================================================
    initial clk = 0;
    always #HALF_CLK clk = ~clk;

    // ========================================================================
    // Load BMP Image
    // ========================================================================
    integer fp_in;
    logic [7:0] rd_byte;

    initial begin
        fp_in = $fopen(img_input, "rb");
        if (!fp_in) begin
            $display("ERROR: Cannot open %s", img_input);
            $finish;
        end
        // Read 54-byte BMP header
        for (int i = 0; i < 54; i++)
            bmp_header[i] = $fgetc(fp_in);
        // Read BGR pixel data
        for (int i = 0; i < NUM_PIXELS * 3; i++) begin
            rd_byte = $fgetc(fp_in);
            case (i % 3)
                0: rgb_mem[i/3][23:16] = rd_byte;  // Blue
                1: rgb_mem[i/3][15:8]  = rd_byte;  // Green
                2: rgb_mem[i/3][7:0]   = rd_byte;  // Red
            endcase
        end
        $fclose(fp_in);

        $display("Loaded %0d pixels from %s", NUM_PIXELS, img_input);
        for (int j = 0; j < 5; j++)
            $display("  RGB[%0d]: R=%h G=%h B=%h",
                     j, rgb_mem[j][7:0], rgb_mem[j][15:8], rgb_mem[j][23:16]);
    end

    // ========================================================================
    // Tasks
    // ========================================================================
    task automatic reset_dut();
        rst_n           <= 0;
        i_valid         <= 0;
        i_color         <= '0;
        i_frame_start   <= 0;
        i_frame_end     <= 0;
        i_bank_swap     <= 0;
        i_bank_wr_clear <= 0;
        i_bank_rd_clear <= 0;
        i_bank_rd_en    <= 0;
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
    // Write grayscale BMP (same 8-bit value to B,G,R channels)
    // Directly accesses module-level arrays for Questa compatibility
    // ========================================================================
    task plot_images;
        integer obmp;

        // ---- Dark Channel ----
        obmp = $fopen({out_dir, "purple_dark_128.bmp"}, "wb");
        for (int i = 0; i < 54; i++) $fwrite(obmp, "%c", bmp_header[i]);
        for (int i = 0; i < NUM_PIXELS; i++) begin
            $fwrite(obmp, "%c", cap_dark[i]);
            $fwrite(obmp, "%c", cap_dark[i]);
            $fwrite(obmp, "%c", cap_dark[i]);
        end
        $fclose(obmp);
        $display("  Saved: purple_dark_128.bmp");

        // ---- Grayscale ----
        obmp = $fopen({out_dir, "purple_gray_128.bmp"}, "wb");
        for (int i = 0; i < 54; i++) $fwrite(obmp, "%c", bmp_header[i]);
        for (int i = 0; i < NUM_PIXELS; i++) begin
            $fwrite(obmp, "%c", cap_gray[i]);
            $fwrite(obmp, "%c", cap_gray[i]);
            $fwrite(obmp, "%c", cap_gray[i]);
        end
        $fclose(obmp);
        $display("  Saved: purple_gray_128.bmp");

        // ---- Sky Recognition (binary: 0=black, 255=white) ----
        obmp = $fopen({out_dir, "purple_sky_128.bmp"}, "wb");
        for (int i = 0; i < 54; i++) $fwrite(obmp, "%c", bmp_header[i]);
        for (int i = 0; i < NUM_PIXELS; i++) begin
            $fwrite(obmp, "%c", cap_sky[i]);
            $fwrite(obmp, "%c", cap_sky[i]);
            $fwrite(obmp, "%c", cap_sky[i]);
        end
        $fclose(obmp);
        $display("  Saved: purple_sky_128.bmp");

        // ---- Transmission Map ----
        obmp = $fopen({out_dir, "purple_tx_128.bmp"}, "wb");
        for (int i = 0; i < 54; i++) $fwrite(obmp, "%c", bmp_header[i]);
        for (int i = 0; i < NUM_PIXELS; i++) begin
            $fwrite(obmp, "%c", cap_tx[i]);
            $fwrite(obmp, "%c", cap_tx[i]);
            $fwrite(obmp, "%c", cap_tx[i]);
        end
        $fclose(obmp);
        $display("  Saved: purple_tx_128.bmp");
    endtask

    // ========================================================================
    // Phase Tracking
    // ========================================================================
    logic pass2_active = 0;

    // ========================================================================
    // Main Test Flow
    // ========================================================================
    initial begin
        $display("==========================================================");
        $display("  PURPLE BLOCK SYSTEM TEST (128x128 BMP)");
        $display("  OMEGA=0x%02X  T_MIN=%0d  A0=%0d  USE_SKY=%0b",
                  OMEGA_Q8, T_MIN, SKY_A0, USE_SKY);
        $display("==========================================================");

        reset_dut();

        // ================================================================
        // PASS 1: Atmospheric Light Estimation
        // ================================================================
        $display("\n--- PASS 1: Atmospheric Light ---");

        @(posedge clk);
        i_frame_start <= 1;
        @(posedge clk);
        i_frame_start <= 0;

        for (int i = 0; i < NUM_PIXELS; i++)
            drive_pixel(rgb_mem[i]);

        idle_pixel();
        @(posedge clk);

        // Pulse frame_end
        @(posedge clk);
        i_frame_end <= 1;
        @(posedge clk);
        i_frame_end <= 0;

        // Wait for A_valid
        repeat (5) @(posedge clk);
        #1;

        if (o_A_valid)
            $display("  Atmospheric Light: A_R=%0d  A_G=%0d  A_B=%0d",
                      o_A_R, o_A_G, o_A_B);
        else begin
            $display("  ERROR: o_A_valid not asserted after frame_end!");
            $finish;
        end

        // ================================================================
        // PASS 2: Full pipeline (dark + gray + sky + tx + bank write)
        // ================================================================
        $display("\n--- PASS 2: Dark/Gray/Sky/Transmission ---");

        @(posedge clk);
        i_bank_wr_clear <= 1;
        @(posedge clk);
        i_bank_wr_clear <= 0;
        @(posedge clk);

        pass2_active = 1;

        for (int i = 0; i < NUM_PIXELS; i++)
            drive_pixel(rgb_mem[i]);

        idle_pixel();
        // Pipeline latency: dark_ch(1) + sky(1) + est_tx(2) = 4 + margin
        repeat (10) @(posedge clk);

        pass2_active = 0;

        $display("  Dark ch  captured: %0d / %0d pixels", dark_idx, NUM_PIXELS);
        $display("  Grayscale captured: %0d / %0d pixels", gray_idx, NUM_PIXELS);
        $display("  Sky       captured: %0d / %0d pixels", sky_idx,  NUM_PIXELS);
        $display("  Tx inline captured: %0d / %0d pixels", tx_idx,   NUM_PIXELS);

        // ================================================================
        // BANK READBACK: Read transmission from ping-pong bank
        // ================================================================
        $display("\n--- BANK READBACK ---");

        @(posedge clk);
        i_bank_swap <= 1;
        @(posedge clk);
        i_bank_swap <= 0;

        @(posedge clk);
        i_bank_rd_clear <= 1;
        @(posedge clk);
        i_bank_rd_clear <= 0;
        @(posedge clk);

        for (int i = 0; i < NUM_PIXELS; i++) begin
            @(posedge clk);
            i_bank_rd_en <= 1;
        end
        @(posedge clk);
        i_bank_rd_en <= 0;
        @(posedge clk);

        $display("  Bank readback: %0d pixels, %0d mismatches vs inline", rd_idx, rd_err);

        // ================================================================
        // GENERATE OUTPUT BMP IMAGES
        // ================================================================
        $display("\n--- GENERATING OUTPUT IMAGES ---");
        plot_images();

        // ================================================================
        // SUMMARY
        // ================================================================
        $display("\n==========================================================");
        $display("  PURPLE BLOCK SYSTEM TEST COMPLETE");
        $display("  Atmospheric Light: A = (%0d, %0d, %0d)", o_A_R, o_A_G, o_A_B);
        $display("  Output images saved to:");
        $display("    - purple_dark_128.bmp (dark channel)");
        $display("    - purple_gray_128.bmp (grayscale)");
        $display("    - purple_sky_128.bmp  (sky mask: white=sky, black=ground)");
        $display("    - purple_tx_128.bmp   (transmission: bright=clear, dark=haze)");
        $display("==========================================================");

        $finish;
    end

    // ========================================================================
    // Monitor: Dark Channel (pass 2)
    // ========================================================================
    int dark_idx = 0;
    always @(posedge clk) begin
        #1;
        if (pass2_active && o_dark_valid && dark_idx < NUM_PIXELS) begin
            cap_dark[dark_idx] = o_dark_ch;
            dark_idx++;
        end
    end

    // ========================================================================
    // Monitor: Grayscale (pass 2, hierarchical access to DUT.gray_out)
    // ========================================================================
    int gray_idx = 0;
    always @(posedge clk) begin
        #1;
        if (pass2_active && o_dark_valid && gray_idx < NUM_PIXELS) begin
            cap_gray[gray_idx] = DUT.gray_out;
            gray_idx++;
        end
    end

    // ========================================================================
    // Monitor: Sky Recognition (pass 2)
    //   o_sky = 1 -> white (255) = sky pixel
    //   o_sky = 0 -> black (0)   = ground pixel
    // ========================================================================
    int sky_idx = 0;
    always @(posedge clk) begin
        #1;
        if (pass2_active && o_sky_valid && sky_idx < NUM_PIXELS) begin
            cap_sky[sky_idx] = o_sky ? 8'd255 : 8'd0;
            sky_idx++;
        end
    end

    // ========================================================================
    // Monitor: Transmission inline (pass 2, direct o_tx)
    // ========================================================================
    int tx_idx = 0;
    always @(posedge clk) begin
        #1;
        if (pass2_active && o_tx_valid && tx_idx < NUM_PIXELS) begin
            cap_tx[tx_idx] = o_tx;
            tx_idx++;
        end
    end

    // ========================================================================
    // Monitor: Bank Readback (compare with inline tx for consistency)
    // ========================================================================
    int rd_phase = 0;
    int rd_idx   = 0;
    int rd_err   = 0;

    always @(posedge clk) begin
        if (i_bank_swap) rd_phase <= 1;
    end

    logic bank_rd_en_d1;
    always_ff @(posedge clk) bank_rd_en_d1 <= i_bank_rd_en;

    always @(posedge clk) begin
        #1;
        if (rd_phase && bank_rd_en_d1 && rd_idx < NUM_PIXELS) begin
            if (o_bank_rd_data !== cap_tx[rd_idx]) begin
                if (rd_err < 10)
                    $display("  [MISMATCH] tx[%0d]: bank=0x%02X inline=0x%02X",
                              rd_idx, o_bank_rd_data, cap_tx[rd_idx]);
                rd_err++;
            end
            rd_idx++;
        end
    end

    // ========================================================================
    // Timeout
    // ========================================================================
    initial begin
        #50000000;
        $display("TIMEOUT!");
        $finish;
    end

endmodule
