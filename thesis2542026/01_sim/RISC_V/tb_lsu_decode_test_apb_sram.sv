// =============================================================================
// Module : tb_lsu_decode
// Description :
//   Testbench cho lsu_decode_test.s
//   - Stub BRAM: rdata = 0xDEAD_0000 | word_addr (dễ nhận trên waveform)
//   - Stub APB : PREADY=1, PRDATA = 0x4950_5531 (IPU_ID "IPU1")
//   - Monitor  : sample signals sau mỗi cycle, check đúng zone
//   - Report   : in bảng PASS/FAIL ra console
//
// Waveform groups cần add vào ModelSim/QuestaSim:
//   Group "LSU decode" : is_mem, is_img_in, is_img_out, is_img_tmp,
//                        is_peri, is_ipu
//   Group "BRAM IMG_IN": img_in_sys_en, img_in_sys_we,
//                        img_in_sys_addr, img_in_sys_wdata
//   Group "BRAM IMG_OUT": img_out_sys_en, img_out_sys_we,
//                         img_out_sys_addr, img_out_sys_wdata
//   Group "APB4"        : PSEL, PENABLE, PWRITE, PADDR, PWDATA, PRDATA
// =============================================================================

`timescale 1ns/1ps

module tb_lsu_decode;

    // =========================================================================
    // Clock & Reset
    // =========================================================================
    localparam CLK_PERIOD = 10; // 100MHz

    logic        clk;
    logic        rst_n;

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // =========================================================================
    // DUT ports
    // =========================================================================
    logic [31:0] i_io_sw;
    logic [31:0] o_pc_debug;
    logic        o_insn_vld;

    // BRAM ports
    logic        img_in_sys_en,  img_in_sys_we;
    logic [15:0] img_in_sys_addr;
    logic [31:0] img_in_sys_wdata, img_in_sys_rdata;

    logic        img_out_sys_en, img_out_sys_we;
    logic [15:0] img_out_sys_addr;
    logic [31:0] img_out_sys_wdata, img_out_sys_rdata;

    logic        img_tmp_sys_en, img_tmp_sys_we;
    logic [15:0] img_tmp_sys_addr;
    logic [31:0] img_tmp_sys_wdata, img_tmp_sys_rdata;

    // APB4 ports (shared bus + split slave-select)
    logic        PSEL_peri, PSEL_ipu, PENABLE, PWRITE;
    logic [31:0] PADDR, PWDATA;
    logic [3:0]  PSTRB;
    logic [2:0]  PPROT;
    logic        PREADY_peri, PREADY_ipu;
    logic [31:0] PRDATA_peri, PRDATA_ipu;

    logic [31:0] peri_io_ledr, peri_io_ledg, peri_io_lcd;
    logic [6:0]  peri_io_hex0, peri_io_hex1, peri_io_hex2, peri_io_hex3;
    logic [6:0]  peri_io_hex4, peri_io_hex5, peri_io_hex6, peri_io_hex7;

    // =========================================================================
    // Stub responses
    // BRAM: trả về địa chỉ word để dễ verify trên waveform
    // APB : PRDATA = IPU_ID = 0x49505531
    // =========================================================================
    assign img_in_sys_rdata  = 32'hDEAD_0000 | {16'h0, img_in_sys_addr};
    assign img_out_sys_rdata = 32'hBEEF_0000 | {16'h0, img_out_sys_addr};
    assign img_tmp_sys_rdata = 32'hCAFE_0000 | {16'h0, img_tmp_sys_addr};

    assign PREADY_ipu = 1'b1;
    assign PRDATA_ipu = (PADDR == 32'h1002_003C) ? 32'h4950_5531 :  // IPU_ID (IPU Reg)
                        (PADDR == 32'h1002_0004) ? 32'h0000_0001 :  // IPU STATUS=IDLE
                        32'hA5A5_A5A5;

    peri_apb_wrapper u_peri_apb_wrapper (
        .PCLK      (clk),
        .PRESETn   (rst_n),
        .PSEL      (PSEL_peri),
        .PENABLE   (PENABLE),
        .PWRITE    (PWRITE),
        .PADDR     (PADDR),
        .PWDATA    (PWDATA),
        .PSTRB     (PSTRB),
        .PPROT     (PPROT),
        .PRDATA    (PRDATA_peri),
        .PREADY    (PREADY_peri),
        .PSLVERR   (),
        .i_io_sw   (i_io_sw),
        .o_io_ledr (peri_io_ledr),
        .o_io_ledg (peri_io_ledg),
        .o_io_lcd  (peri_io_lcd),
        .o_io_hex0 (peri_io_hex0),
        .o_io_hex1 (peri_io_hex1),
        .o_io_hex2 (peri_io_hex2),
        .o_io_hex3 (peri_io_hex3),
        .o_io_hex4 (peri_io_hex4),
        .o_io_hex5 (peri_io_hex5),
        .o_io_hex6 (peri_io_hex6),
        .o_io_hex7 (peri_io_hex7)
    );

    // =========================================================================
    // DUT instantiation
    // =========================================================================
    single_cycle dut (
        .i_clk            (clk),
        .i_reset          (rst_n),
        .i_io_sw          (i_io_sw),
        .o_pc_debug       (o_pc_debug),
        .o_insn_vld       (o_insn_vld),
        .img_in_sys_en    (img_in_sys_en),
        .img_in_sys_we    (img_in_sys_we),
        .img_in_sys_addr  (img_in_sys_addr),
        .img_in_sys_wdata (img_in_sys_wdata),
        .img_in_sys_rdata (img_in_sys_rdata),
        .img_out_sys_en   (img_out_sys_en),
        .img_out_sys_we   (img_out_sys_we),
        .img_out_sys_addr (img_out_sys_addr),
        .img_out_sys_wdata(img_out_sys_wdata),
        .img_out_sys_rdata(img_out_sys_rdata),
        .img_tmp_sys_en   (img_tmp_sys_en),
        .img_tmp_sys_we   (img_tmp_sys_we),
        .img_tmp_sys_addr (img_tmp_sys_addr),
        .img_tmp_sys_wdata(img_tmp_sys_wdata),
        .img_tmp_sys_rdata(img_tmp_sys_rdata),
        .PSEL_peri        (PSEL_peri),
        .PSEL_ipu         (PSEL_ipu),
        .PENABLE          (PENABLE),
        .PWRITE           (PWRITE),
        .PADDR            (PADDR),
        .PWDATA           (PWDATA),
        .PSTRB            (PSTRB),
        .PPROT            (PPROT),
        .PREADY_peri      (PREADY_peri),
        .PRDATA_peri      (PRDATA_peri),
        .PREADY_ipu       (PREADY_ipu),
        .PRDATA_ipu       (PRDATA_ipu)
    );

    // Use the dedicated LSU decode program for this test.
    defparam dut.instr_mem_inst.DEPTH = 8192;
    defparam dut.instr_mem_inst.MEM   = "../01_sim/RISC_V/02_test/lsu_decode_test_apb_sram_readmem.hex";

    // =========================================================================
    // Test tracking
    // =========================================================================
    integer pass_cnt, fail_cnt;

    // Mỗi test case:
    typedef struct {
        string   name;
        logic    result;  // 1=pass, 0=fail
    } test_result_t;

    // Dùng mảng để lưu kết quả
    string  test_names  [0:127];
    integer test_results[0:127];
    integer test_idx;

    // =========================================================================
    // Task: check một điều kiện, lưu kết quả
    // =========================================================================
    task automatic check(
        input string  name,
        input logic   cond
    );
        test_names  [test_idx] = name;
        test_results[test_idx] = cond ? 1 : 0;
        if (cond) pass_cnt++;
        else       fail_cnt++;
        test_idx++;
    endtask

    // =========================================================================
    // Task: đợi N cycles sau đó sample
    // =========================================================================
    task automatic wait_cycles(input integer n);
        repeat(n) @(posedge clk);
        #1; // nhỏ để tránh race với clock edge
    endtask

    task automatic log_start(input string test_name);
        $display("<at time %0t ns> [START] %s", $time, test_name);
    endtask

    // =========================================================================
    // Task: in bảng kết quả
    // =========================================================================
    task automatic print_table();
        integer i;
        $display("");
        $display("+------------------------------------------+--------+");
        $display("| LSU DECODE TEST RESULTS                  | RESULT |");
        $display("+------------------------------------------+--------+");
        for (i = 0; i < test_idx; i++) begin
            if (test_results[i] == 1)
                $display("| %-40s | PASS   |", test_names[i]);
            else
                $display("| %-40s | FAIL   |", test_names[i]);
        end
        $display("+------------------------------------------+--------+");
        $display("| Total: %-30d PASS: %-3d FAIL: %-3d |", 
                 test_idx, pass_cnt, fail_cnt);
        $display("+------------------------------------------+--------+");
        $display("");
        if (fail_cnt == 0)
            $display(">>> ALL TESTS PASSED <<<");
        else
            $display(">>> %0d TEST(S) FAILED <<<", fail_cnt);
        $display("");
    endtask

    // =========================================================================
    // Monitor: sample signals liên tục, check theo PC
    // =========================================================================
    // Địa chỉ instruction (PC) để nhận biết đang chạy zone nào
    // Dùng cách đơn giản hơn: monitor signal trực tiếp sau mỗi sw/lw

    // =========================================================================
    // Main test sequence
    // =========================================================================
    initial begin
        // --- Init ---
        i_io_sw  = 32'h0;
        rst_n    = 0;
        pass_cnt = 0;
        fail_cnt = 0;
        test_idx = 0;

        // Reset 4 cycles
        repeat(4) @(posedge clk);
        rst_n = 1;

        // Đợi CPU boot và chạy qua init instructions (~10 cycles)
        wait_cycles(10);

        // =====================================================================
        // ZONE 1: LOCAL MEM — 0x0000_0000
        // sw s0, 0(t0) — t0 = 0x0000_0000
        // =====================================================================
        // Đợi đến khi CPU chạy đến zone 1 (~20 cycles từ start)
        // Cách tiếp cận: poll cho đến khi thấy đúng signal

        // Poll chờ is_mem = 1 (zone 1 sw)
        log_start("LSU Zone 1 LOCAL_MEM decode checks");
        fork
            begin : timeout1
                repeat(200) @(posedge clk);
                $display("[TIMEOUT] Zone 1 not reached");
                disable wait_zone1;
            end
            begin : wait_zone1
                @(negedge clk iff (dut.lsu.is_mem === 1'b1 &&
                                   dut.lsu.i_lsu_wren === 1'b1));
                disable timeout1;
            end
        join

        #1;
        // Sample và check Zone 1 write
        check("Zone1 LOCAL_MEM: is_mem=1 on sw",
              dut.lsu.is_mem === 1'b1);
        check("Zone1 LOCAL_MEM: is_img_in=0",
              dut.lsu.is_img_in === 1'b0);
        check("Zone1 LOCAL_MEM: is_ipu=0",
              dut.lsu.is_ipu === 1'b0);
          check("Zone1 LOCAL_MEM: PSEL_peri=0 & PSEL_ipu=0",
              (PSEL_peri === 1'b0) && (PSEL_ipu === 1'b0));
        check("Zone1 LOCAL_MEM: img_in_sys_en=0",
              img_in_sys_en === 1'b0);

        // =====================================================================
        // ZONE 2: IMG_IN — 0x0001_0000
        // =====================================================================
        log_start("LSU Zone 2 IMG_IN decode checks");
        fork
            begin : timeout2
                repeat(200) @(posedge clk);
                $display("[TIMEOUT] Zone 2 not reached");
                disable wait_zone2;
            end
            begin : wait_zone2
                @(negedge clk iff (dut.lsu.is_img_in === 1'b1 &&
                                   dut.lsu.i_lsu_wren === 1'b1 &&
                                   dut.lsu.i_lsu_addr == 32'h0001_0000));
                disable timeout2;
            end
        join

        #1;
        check("Zone2 IMG_IN: is_img_in=1 on sw",
              dut.lsu.is_img_in === 1'b1);
        check("Zone2 IMG_IN: img_in_sys_en=1",
              img_in_sys_en === 1'b1);
        check("Zone2 IMG_IN: img_in_sys_we=1 on sw",
              img_in_sys_we === 1'b1);
        check("Zone2 IMG_IN: is_img_out=0",
              dut.lsu.is_img_out === 1'b0);
          check("Zone2 IMG_IN: PSEL_peri=0 & PSEL_ipu=0",
              (PSEL_peri === 1'b0) && (PSEL_ipu === 1'b0));
        check("Zone2 IMG_IN: img_in_sys_addr==0",
              img_in_sys_addr === 16'h0000);
        check("Zone2 IMG_IN: img_in_sys_wdata==0xDEAD",
              img_in_sys_wdata[31:16] === 16'h0000); // lower 16 of 0xDEAD

        // Check lw (read) — we phải = 0
        fork
            begin : timeout2r
                repeat(100) @(posedge clk);
                disable wait_zone2r;
            end
            begin : wait_zone2r
                @(negedge clk iff (dut.lsu.is_img_in === 1'b1 &&
                                   dut.lsu.i_lsu_wren === 1'b0));
                disable timeout2r;
            end
        join
        #1;
        check("Zone2 IMG_IN: img_in_sys_we=0 on lw",
              img_in_sys_we === 1'b0);
        check("Zone2 IMG_IN: img_in_sys_en=1 on lw",
              img_in_sys_en === 1'b1);

        // =====================================================================
        // ZONE 3: IMG_OUT — 0x0004_0000
        // =====================================================================
        log_start("LSU Zone 3 IMG_OUT decode checks");
        fork
            begin : timeout3
                repeat(200) @(posedge clk);
                disable wait_zone3;
            end
            begin : wait_zone3
                @(negedge clk iff (dut.lsu.is_img_out === 1'b1 &&
                                   dut.lsu.i_lsu_wren === 1'b1 &&
                                   dut.lsu.i_lsu_addr == 32'h0004_0000));
                disable timeout3;
            end
        join
        #1;
        check("Zone3 IMG_OUT: is_img_out=1 on sw",
              dut.lsu.is_img_out === 1'b1);
        check("Zone3 IMG_OUT: img_out_sys_en=1",
              img_out_sys_en === 1'b1);
        check("Zone3 IMG_OUT: img_out_sys_we=1",
              img_out_sys_we === 1'b1);
        check("Zone3 IMG_OUT: is_img_in=0",
              dut.lsu.is_img_in === 1'b0);
          check("Zone3 IMG_OUT: PSEL_peri=0 & PSEL_ipu=0",
              (PSEL_peri === 1'b0) && (PSEL_ipu === 1'b0));

        // =====================================================================
        // ZONE 4: IMG_TMP — 0x0007_0000
        // =====================================================================
        log_start("LSU Zone 4 IMG_TMP decode checks");
        fork
            begin : timeout4
                repeat(200) @(posedge clk);
                disable wait_zone4;
            end
            begin : wait_zone4
                @(negedge clk iff (dut.lsu.is_img_tmp === 1'b1 &&
                                   dut.lsu.i_lsu_wren === 1'b1 &&
                                   dut.lsu.i_lsu_addr == 32'h0007_0000));
                disable timeout4;
            end
        join
        #1;
        check("Zone4 IMG_TMP: is_img_tmp=1 on sw",
              dut.lsu.is_img_tmp === 1'b1);
        check("Zone4 IMG_TMP: img_tmp_sys_en=1",
              img_tmp_sys_en === 1'b1);
        check("Zone4 IMG_TMP: img_tmp_sys_we=1",
              img_tmp_sys_we === 1'b1);
          check("Zone4 IMG_TMP: PSEL_peri=0 & PSEL_ipu=0",
              (PSEL_peri === 1'b0) && (PSEL_ipu === 1'b0));
        check("Zone4 IMG_TMP: img_in_sys_en=0",
              img_in_sys_en === 1'b0);

        // =====================================================================
        // ZONE 5: PERIPHERAL — 0x1000_0000
        // =====================================================================
        log_start("LSU Zone 5 PERIPHERAL APB checks");
        fork
            begin : timeout5
                repeat(200) @(posedge clk);
                disable wait_zone5;
            end
            begin : wait_zone5
                @(negedge clk iff (dut.lsu.is_peri === 1'b1 &&
                                   dut.lsu.i_lsu_wren === 1'b1 &&
                                   dut.lsu.i_lsu_addr == 32'h1000_0000));
                disable timeout5;
            end
        join
        #1;
        check("Zone5 PERI: is_peri=1 on sw",
              dut.lsu.is_peri === 1'b1);
          check("Zone5 PERI: PSEL_peri=1",
              PSEL_peri === 1'b1);
          check("Zone5 PERI: PSEL_ipu=0",
              PSEL_ipu === 1'b0);
        check("Zone5 PERI: PENABLE=1",
              PENABLE === 1'b1);
        check("Zone5 PERI: img_in_sys_en=0",
              img_in_sys_en === 1'b0);
        check("Zone5 PERI: is_ipu=0",
              dut.lsu.is_ipu === 1'b0);

        // =====================================================================
        // ZONE 6: IPU REG — 0x1002_0000 (lw IPU_ID)
        // =====================================================================
        log_start("LSU Zone 6 IPU APB checks");
        fork
            begin : timeout6r
                repeat(200) @(posedge clk);
                disable wait_zone6r;
            end
            begin : wait_zone6r
                @(negedge clk iff (dut.lsu.is_ipu === 1'b1 &&
                                   dut.lsu.i_lsu_wren === 1'b0 &&
                                   dut.lsu.i_lsu_addr == 32'h1002_003C));
                disable timeout6r;
            end
        join
        #1;
        check("Zone6 IPU READ: is_ipu=1",
              dut.lsu.is_ipu === 1'b1);
          check("Zone6 IPU READ: PSEL_ipu=1",
              PSEL_ipu === 1'b1);
          check("Zone6 IPU READ: PSEL_peri=0",
              PSEL_peri === 1'b0);
        check("Zone6 IPU READ: PENABLE=1",
              PENABLE === 1'b1);
        check("Zone6 IPU READ: PWRITE=0",
              PWRITE === 1'b0);
        check("Zone6 IPU READ: PADDR=0x1002003C",
              PADDR === 32'h1002_003C);
        check("Zone6 IPU READ: img_in_sys_en=0",
              img_in_sys_en === 1'b0);
        check("Zone6 IPU READ: img_out_sys_en=0",
              img_out_sys_en === 1'b0);

        // Zone 6 write: sw IPU_SRC_ADDR
        fork
            begin : timeout6w
                repeat(100) @(posedge clk);
                disable wait_zone6w;
            end
            begin : wait_zone6w
                @(negedge clk iff (dut.lsu.is_ipu === 1'b1 &&
                                   dut.lsu.i_lsu_wren === 1'b1 &&
                                   dut.lsu.i_lsu_addr == 32'h1002_0008));
                disable timeout6w;
            end
        join
        #1;
          check("Zone6 IPU WRITE: PSEL_ipu=1",
              PSEL_ipu === 1'b1);
        check("Zone6 IPU WRITE: PWRITE=1",
              PWRITE === 1'b1);
        check("Zone6 IPU WRITE: PADDR=0x10020008",
              PADDR === 32'h1002_0008);
        check("Zone6 IPU WRITE: PWDATA=0x00010000",
              PWDATA === 32'h0001_0000);
        check("Zone6 IPU WRITE: PSTRB=4'b1111",
              PSTRB === 4'b1111);
        check("Zone6 IPU WRITE: img_in_sys_en=0",
              img_in_sys_en === 1'b0);

        // =====================================================================
        // ZONE 7: Boundary 0x1002_1000 — PSEL phải = 0
        // =====================================================================
        log_start("LSU Zone 7 APB boundary checks");
        fork
            begin : timeout7
                repeat(500) @(posedge clk);
                $display("[TIMEOUT] Zone 7 not reached");
                disable wait_zone7;
            end
            begin : wait_zone7
                @(negedge clk iff (dut.lsu.i_lsu_addr == 32'h1002_1000 &&
                                   dut.lsu.i_lsu_wren == 1'b0));
                disable timeout7;
            end
        join
        #1;
          check("Zone7 BOUNDARY: PSEL_peri=0 & PSEL_ipu=0",
              (PSEL_peri === 1'b0) && (PSEL_ipu === 1'b0));

        // =====================================================================
        // ZONE 8: IMG_IN/OUT boundary
        // Check: addr 0x0003_FFFC → img_in, addr 0x0004_0000 → img_out
        // =====================================================================
        log_start("LSU Zone 8 IMG boundary checks");
        fork
            begin : timeout8a
                repeat(200) @(posedge clk);
                disable wait_zone8a;
            end
            begin : wait_zone8a
                // Chờ write vào cuối vùng IMG_IN
                @(negedge clk iff (dut.lsu.i_lsu_addr === 32'h0003_FFFC &&
                                   dut.lsu.i_lsu_wren === 1'b1));
                disable timeout8a;
            end
        join
        #1;
        check("Zone8 BOUNDARY 0x0003FFFC: is_img_in=1",
              dut.lsu.is_img_in === 1'b1);
        check("Zone8 BOUNDARY 0x0003FFFC: is_img_out=0",
              dut.lsu.is_img_out === 1'b0);

        fork
            begin : timeout8b
                repeat(50) @(posedge clk);
                disable wait_zone8b;
            end
            begin : wait_zone8b
                @(negedge clk iff (dut.lsu.i_lsu_addr === 32'h0004_0000 &&
                                   dut.lsu.i_lsu_wren === 1'b1));
                disable timeout8b;
            end
        join
        #1;
        check("Zone8 BOUNDARY 0x00040000: is_img_out=1",
              dut.lsu.is_img_out === 1'b1);
        check("Zone8 BOUNDARY 0x00040000: is_img_in=0",
              dut.lsu.is_img_in === 1'b0);

        // =====================================================================
        // Đợi LED_GREEN = 0xFF (done flag từ assembly)
        // =====================================================================
        log_start("LSU done flag wait");
        fork
            begin : timeout_done
                repeat(10000) @(posedge clk);
                $display("[WARN] Assembly did not reach 'done' within timeout");
                disable wait_done;
            end
            begin : wait_done
                // Check for LED write via APB (peripheral address 0x1000_0000 or 0x1000_0004)
                @(posedge clk iff (PSEL_peri === 1'b1 && PWRITE === 1'b1 && 
                                   (PADDR == 32'h1000_0000 || PADDR == 32'h1000_0004)));
                disable timeout_done;
            end
        join
                check("Assembly reached DONE (LED write via APB)",
                            (PSEL_peri === 1'b1 && PWRITE === 1'b1 && 
                             (PADDR == 32'h1000_0000 || PADDR == 32'h1000_0004)));

        // =====================================================================
        // Print table
        // =====================================================================
        print_table();

        // Waveform dump
        $display("Simulation complete at time %0t ns", $time);
        #100;
        $finish;
    end

    // =========================================================================
    // Waveform dump
    // =========================================================================
    initial begin
        $dumpfile("tb_lsu_decode.vcd");
        $dumpvars(0, tb_lsu_decode);
    end

    // =========================================================================
    // Timeout toàn bộ simulation
    // =========================================================================
    initial begin
        #500000;
        $display("[ERROR] Global simulation timeout!");
        $finish;
    end

endmodule