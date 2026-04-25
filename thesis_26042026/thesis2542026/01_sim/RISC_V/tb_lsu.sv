`timescale 1ns / 1ps

module tb_lsu;

    // ========================================
    // Parameters
    // ========================================
    parameter DEPTH = 2048;  // 2KB memory
    parameter CLK_PERIOD = 10;  // 10ns clock period
    
    // ========================================
    // Signals
    // ========================================
    logic i_clk;
    logic i_reset;
    logic i_lsu_wren;
    logic [3:0] i_byte_num;
    logic [31:0] i_st_data;
    logic [31:0] i_lsu_addr;
    logic [31:0] i_io_sw;
    
    // Outputs
    logic [31:0] o_ld_data;
    logic [31:0] o_io_ledr;
    logic [31:0] o_io_ledg;
    logic [31:0] o_io_lcd;
    logic [6:0] o_io_hex0, o_io_hex1, o_io_hex2, o_io_hex3;
    logic [6:0] o_io_hex4, o_io_hex5, o_io_hex6, o_io_hex7;
    
    // Expected values
    logic [31:0] exp_ld_data;
    
    // Test counters
    int test_num = 0;
    int pass_count = 0;
    int fail_count = 0;
    
    // ========================================
    // Clock Generation
    // ========================================
    initial begin
        i_clk = 0;
        forever #(CLK_PERIOD/2) i_clk = ~i_clk;
    end
    
    // ========================================
    // DUT Instantiation
    // ========================================
    lsu #(
        .DEPTH(DEPTH),
        .MEM_FILE("memory_ctmt/dmem.hex")
    ) dut (
        .i_clk(i_clk),
        .i_reset(i_reset),
        .i_lsu_wren(i_lsu_wren),
        .i_byte_num(i_byte_num),
        .i_st_data(i_st_data),
        .i_lsu_addr(i_lsu_addr),
        .i_io_sw(i_io_sw),
        .o_ld_data(o_ld_data),
        .o_io_ledr(o_io_ledr),
        .o_io_ledg(o_io_ledg),
        .o_io_lcd(o_io_lcd),
        .o_io_hex0(o_io_hex0),
        .o_io_hex1(o_io_hex1),
        .o_io_hex2(o_io_hex2),
        .o_io_hex3(o_io_hex3),
        .o_io_hex4(o_io_hex4),
        .o_io_hex5(o_io_hex5),
        .o_io_hex6(o_io_hex6),
        .o_io_hex7(o_io_hex7)
    );
    
    // ========================================
    // Helper Task: Check Load Result
    // ========================================
    task check_load(input string test_name, input [31:0] expected);
        test_num++;
        
        if (o_ld_data === expected) begin
            $display("[PASS] Test %0d: %s", test_num, test_name);
            $display("       Address: 0x%08h, Data: 0x%08h", i_lsu_addr, o_ld_data);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: %s", test_num, test_name);
            $display("       Address: 0x%08h", i_lsu_addr);
            $display("       Expected: 0x%08h, Got: 0x%08h", expected, o_ld_data);
            fail_count++;
        end
    endtask
    
    // ========================================
    // Helper Task: Write Memory
    // ========================================
    task write_mem(
        input [31:0] addr,
        input [31:0] data,
        input [3:0] byte_num
    );
        @(posedge i_clk);
        i_lsu_addr = addr;
        i_st_data = data;
        i_byte_num = byte_num;
        i_lsu_wren = 1'b1;
        @(posedge i_clk);
        i_lsu_wren = 1'b0;
    endtask
    
    // ========================================
    // Helper Task: Read Memory
    // ========================================
    task read_mem(
        input [31:0] addr,
        input [3:0] byte_num
    );
        @(posedge i_clk);
        i_lsu_addr = addr;
        i_byte_num = byte_num;
        i_lsu_wren = 1'b0;
        @(posedge i_clk);
        @(posedge i_clk);  // Wait for read to complete
    endtask
    
    // ========================================
    // Test Sequence
    // ========================================
    initial begin
        $display("╔══════════════════════════════════════════════════════════════╗");
        $display("║          LSU (Load Store Unit) Verification Testbench       ║");
        $display("╚══════════════════════════════════════════════════════════════╝");
        $display("");
        
        // Initialize signals
        i_reset = 0;
        i_lsu_wren = 0;
        i_byte_num = 4'b0000;
        i_st_data = 32'h0;
        i_lsu_addr = 32'h0;
        i_io_sw = 32'h0;
        
        // Reset sequence
        #(CLK_PERIOD * 2);
        i_reset = 1;
        #(CLK_PERIOD * 2);
        
        // ========================================
        // STORE WORD (SW) TESTS
        // ========================================
        $display("╔══════════════════════════════════════════════════════════════╗");
        $display("║  STORE WORD (SW) - 32-bit Store Tests                       ║");
        $display("╚══════════════════════════════════════════════════════════════╝");
        
        // Test 1: SW aligned (offset 0)
        write_mem(32'h0000_0000, 32'hDEADBEEF, 4'b1111);
        read_mem(32'h0000_0000, 4'b1111);
        check_load("SW aligned addr 0x00: Store & Load 0xDEADBEEF", 32'hDEADBEEF);
        
        // Test 2: SW aligned (offset 0) - different address
        write_mem(32'h0000_0004, 32'h12345678, 4'b1111);
        read_mem(32'h0000_0004, 4'b1111);
        check_load("SW aligned addr 0x04: Store & Load 0x12345678", 32'h12345678);
        
        // Test 3: SW aligned (offset 0) - another address
        write_mem(32'h0000_0100, 32'hCAFEBABE, 4'b1111);
        read_mem(32'h0000_0100, 4'b1111);
        check_load("SW aligned addr 0x100: Store & Load 0xCAFEBABE", 32'hCAFEBABE);
        
        // Test 4: SW at address 0x200
        write_mem(32'h0000_0200, 32'hA5A5A5A5, 4'b1111);
        read_mem(32'h0000_0200, 4'b1111);
        check_load("SW aligned addr 0x200: Store & Load 0xA5A5A5A5", 32'hA5A5A5A5);
        
        // ========================================
        // STORE HALFWORD (SH) TESTS
        // ========================================
        $display("");
        $display("╔══════════════════════════════════════════════════════════════╗");
        $display("║  STORE HALFWORD (SH) - 16-bit Store Tests                   ║");
        $display("╚══════════════════════════════════════════════════════════════╝");
        
        // Test 5: SH aligned offset 0
        write_mem(32'h0000_0010, 32'h0000ABCD, 4'b0011);
        read_mem(32'h0000_0010, 4'b0011);
        check_load("SH offset 0: Store 0xABCD", 32'hFFFFABCD);  // Sign-extended
        
        // Test 6: SH aligned offset 2
        write_mem(32'h0000_0012, 32'h00001234, 4'b0011);
        read_mem(32'h0000_0012, 4'b0011);
        check_load("SH offset 2: Store 0x1234", 32'h00001234);  // Positive, sign-extend to same
        
        // Test 7: SH misaligned offset 1
        write_mem(32'h0000_0021, 32'h0000CAFE, 4'b0011);
        read_mem(32'h0000_0021, 4'b0011);
        check_load("SH offset 1 (misaligned): Store 0xCAFE", 32'hFFFFCAFE);
        
        // Test 8: SH offset 3 (edge case - cross boundary, only 1 byte stored)
        write_mem(32'h0000_0023, 32'h00005678, 4'b0011);
        read_mem(32'h0000_0023, 4'b0011);
        check_load("SH offset 3 (edge): Store 0x5678 (cross boundary)", 32'h00002378);
        
        // ========================================
        // STORE BYTE (SB) TESTS
        // ========================================
        $display("");
        $display("╔══════════════════════════════════════════════════════════════╗");
        $display("║  STORE BYTE (SB) - 8-bit Store Tests                        ║");
        $display("╚══════════════════════════════════════════════════════════════╝");
        
        // Test 9: SB offset 0
        write_mem(32'h0000_0030, 32'h000000AB, 4'b0001);
        read_mem(32'h0000_0030, 4'b0001);
        check_load("SB offset 0: Store 0xAB", 32'hFFFFFFAB);  // Sign-extended
        
        // Test 10: SB offset 1
        write_mem(32'h0000_0031, 32'h000000CD, 4'b0001);
        read_mem(32'h0000_0031, 4'b0001);
        check_load("SB offset 1: Store 0xCD", 32'hFFFFFFCD);
        
        // Test 11: SB offset 2
        write_mem(32'h0000_0032, 32'h000000EF, 4'b0001);
        read_mem(32'h0000_0032, 4'b0001);
        check_load("SB offset 2: Store 0xEF", 32'hFFFFFFEF);
        
        // Test 12: SB offset 3
        write_mem(32'h0000_0033, 32'h00000012, 4'b0001);
        read_mem(32'h0000_0033, 4'b0001);
        check_load("SB offset 3: Store 0x12", 32'h00000012);  // Positive
        
        // ========================================
        // LOAD WORD (LW) TESTS
        // ========================================
        $display("");
        $display("╔══════════════════════════════════════════════════════════════╗");
        $display("║  LOAD WORD (LW) - 32-bit Load Tests                         ║");
        $display("╚══════════════════════════════════════════════════════════════╝");
        
        // Setup: Write known values
        write_mem(32'h0000_0040, 32'hFFFFFFFF, 4'b1111);
        write_mem(32'h0000_0044, 32'h80000000, 4'b1111);
        write_mem(32'h0000_0048, 32'h7FFFFFFF, 4'b1111);
        write_mem(32'h0000_004C, 32'h00000000, 4'b1111);
        
        // Test 13-16: LW tests
        read_mem(32'h0000_0040, 4'b1111);
        check_load("LW: Load 0xFFFFFFFF", 32'hFFFFFFFF);
        
        read_mem(32'h0000_0044, 4'b1111);
        check_load("LW: Load 0x80000000", 32'h80000000);
        
        read_mem(32'h0000_0048, 4'b1111);
        check_load("LW: Load 0x7FFFFFFF", 32'h7FFFFFFF);
        
        read_mem(32'h0000_004C, 4'b1111);
        check_load("LW: Load 0x00000000", 32'h00000000);
        
        // ========================================
        // LOAD HALFWORD (LH) TESTS - Signed
        // ========================================
        $display("");
        $display("╔══════════════════════════════════════════════════════════════╗");
        $display("║  LOAD HALFWORD (LH) - 16-bit Signed Load Tests              ║");
        $display("╚══════════════════════════════════════════════════════════════╝");
        
        // Setup: Write test patterns
        write_mem(32'h0000_0050, 32'h1234ABCD, 4'b1111);
        write_mem(32'h0000_0054, 32'h8000FFFF, 4'b1111);
        write_mem(32'h0000_0058, 32'h7FFF0001, 4'b1111);
        
        // Test 17: LH offset 0 - negative value
        read_mem(32'h0000_0050, 4'b0011);
        check_load("LH offset 0: Load 0xABCD (sign-extended)", 32'hFFFFABCD);
        
        // Test 18: LH offset 2 - positive value
        read_mem(32'h0000_0052, 4'b0011);
        check_load("LH offset 2: Load 0x1234 (sign-extended)", 32'h00001234);
        
        // Test 19: LH offset 0 - all 1s
        read_mem(32'h0000_0054, 4'b0011);
        check_load("LH offset 0: Load 0xFFFF (sign-extended)", 32'hFFFFFFFF);
        
        // Test 20: LH offset 2 - most negative
        read_mem(32'h0000_0056, 4'b0011);
        check_load("LH offset 2: Load 0x8000 (sign-extended)", 32'hFFFF8000);
        
        // Test 21: LH offset 0 - small positive
        read_mem(32'h0000_0058, 4'b0011);
        check_load("LH offset 0: Load 0x0001", 32'h00000001);
        
        // Test 22: LH offset 2 - max positive
        read_mem(32'h0000_005A, 4'b0011);
        check_load("LH offset 2: Load 0x7FFF", 32'h00007FFF);
        
        // ========================================
        // LOAD HALFWORD UNSIGNED (LHU) TESTS
        // ========================================
        $display("");
        $display("╔══════════════════════════════════════════════════════════════╗");
        $display("║  LOAD HALFWORD UNSIGNED (LHU) - 16-bit Zero-Extended Tests  ║");
        $display("╚══════════════════════════════════════════════════════════════╝");
        
        // Test 23: LHU offset 0 - high bit set
        read_mem(32'h0000_0050, 4'b0101);
        check_load("LHU offset 0: Load 0xABCD (zero-extended)", 32'h0000ABCD);
        
        // Test 24: LHU offset 2
        read_mem(32'h0000_0052, 4'b0101);
        check_load("LHU offset 2: Load 0x1234 (zero-extended)", 32'h00001234);
        
        // Test 25: LHU offset 0 - all 1s
        read_mem(32'h0000_0054, 4'b0101);
        check_load("LHU offset 0: Load 0xFFFF (zero-extended)", 32'h0000FFFF);
        
        // Test 26: LHU offset 2 - 0x8000
        read_mem(32'h0000_0056, 4'b0101);
        check_load("LHU offset 2: Load 0x8000 (zero-extended)", 32'h00008000);
        
        // ========================================
        // LOAD BYTE (LB) TESTS - Signed
        // ========================================
        $display("");
        $display("╔══════════════════════════════════════════════════════════════╗");
        $display("║  LOAD BYTE (LB) - 8-bit Signed Load Tests                   ║");
        $display("╚══════════════════════════════════════════════════════════════╝");
        
        // Setup
        write_mem(32'h0000_0060, 32'h12345678, 4'b1111);
        write_mem(32'h0000_0064, 32'hABCDEF01, 4'b1111);
        write_mem(32'h0000_0068, 32'h80FF7F00, 4'b1111);
        
        // Test 27-30: LB all offsets
        read_mem(32'h0000_0060, 4'b0001);
        check_load("LB offset 0: Load 0x78 (sign-extended)", 32'h00000078);
        
        read_mem(32'h0000_0061, 4'b0001);
        check_load("LB offset 1: Load 0x56", 32'h00000056);
        
        read_mem(32'h0000_0062, 4'b0001);
        check_load("LB offset 2: Load 0x34", 32'h00000034);
        
        read_mem(32'h0000_0063, 4'b0001);
        check_load("LB offset 3: Load 0x12", 32'h00000012);
        
        // Test 31-34: LB negative values
        read_mem(32'h0000_0064, 4'b0001);
        check_load("LB offset 0: Load 0x01 (positive)", 32'h00000001);
        
        read_mem(32'h0000_0065, 4'b0001);
        check_load("LB offset 1: Load 0xEF (sign-extended)", 32'hFFFFFFEF);
        
        read_mem(32'h0000_0066, 4'b0001);
        check_load("LB offset 2: Load 0xCD (sign-extended)", 32'hFFFFFFCD);
        
        read_mem(32'h0000_0067, 4'b0001);
        check_load("LB offset 3: Load 0xAB (sign-extended)", 32'hFFFFFFAB);
        
        // Test 35-38: LB edge cases
        read_mem(32'h0000_0068, 4'b0001);
        check_load("LB offset 0: Load 0x00", 32'h00000000);
        
        read_mem(32'h0000_0069, 4'b0001);
        check_load("LB offset 1: Load 0x7F (max positive)", 32'h0000007F);
        
        read_mem(32'h0000_006A, 4'b0001);
        check_load("LB offset 2: Load 0xFF (sign-extended)", 32'hFFFFFFFF);
        
        read_mem(32'h0000_006B, 4'b0001);
        check_load("LB offset 3: Load 0x80 (most negative)", 32'hFFFFFF80);
        
        // ========================================
        // LOAD BYTE UNSIGNED (LBU) TESTS
        // ========================================
        $display("");
        $display("╔══════════════════════════════════════════════════════════════╗");
        $display("║  LOAD BYTE UNSIGNED (LBU) - 8-bit Zero-Extended Tests       ║");
        $display("╚══════════════════════════════════════════════════════════════╝");
        
        // Test 39-42: LBU
        read_mem(32'h0000_0064, 4'b0100);
        check_load("LBU offset 0: Load 0x01 (zero-extended)", 32'h00000001);
        
        read_mem(32'h0000_0065, 4'b0100);
        check_load("LBU offset 1: Load 0xEF (zero-extended)", 32'h000000EF);
        
        read_mem(32'h0000_0066, 4'b0100);
        check_load("LBU offset 2: Load 0xCD (zero-extended)", 32'h000000CD);
        
        read_mem(32'h0000_0067, 4'b0100);
        check_load("LBU offset 3: Load 0xAB (zero-extended)", 32'h000000AB);
        
        // Test 43-46: LBU edge cases
        read_mem(32'h0000_0068, 4'b0100);
        check_load("LBU offset 0: Load 0x00", 32'h00000000);
        
        read_mem(32'h0000_0069, 4'b0100);
        check_load("LBU offset 1: Load 0x7F", 32'h0000007F);
        
        read_mem(32'h0000_006A, 4'b0100);
        check_load("LBU offset 2: Load 0xFF (zero-extended)", 32'h000000FF);
        
        read_mem(32'h0000_006B, 4'b0100);
        check_load("LBU offset 3: Load 0x80 (zero-extended)", 32'h00000080);
        
        // ========================================
        // MISALIGNED ACCESS TESTS
        // ========================================
        $display("");
        $display("╔══════════════════════════════════════════════════════════════╗");
        $display("║  MISALIGNED ACCESS TESTS                                     ║");
        $display("╚══════════════════════════════════════════════════════════════╝");
        
        // Setup: Write known pattern
        write_mem(32'h0000_0070, 32'h01234567, 4'b1111);
        write_mem(32'h0000_0074, 32'h89ABCDEF, 4'b1111);
        
        // Test 47: LW misaligned offset 1
        read_mem(32'h0000_0071, 4'b1111);
        check_load("LW misaligned offset 1", 32'hEF012345);
        
        // Test 48: LW misaligned offset 2
        read_mem(32'h0000_0072, 4'b1111);
        check_load("LW misaligned offset 2", 32'hCDEF0123);
        
        // Test 49: LW misaligned offset 3
        read_mem(32'h0000_0073, 4'b1111);
        check_load("LW misaligned offset 3", 32'hABCDEF01);
        
        // Test 50: LH misaligned
        read_mem(32'h0000_0071, 4'b0011);
        check_load("LH misaligned offset 1", 32'h00002345);
        
        // ========================================
        // STORE-LOAD COHERENCY TESTS
        // ========================================
        $display("");
        $display("╔══════════════════════════════════════════════════════════════╗");
        $display("║  STORE-LOAD COHERENCY TESTS                                 ║");
        $display("╚══════════════════════════════════════════════════════════════╝");
        
        // Test 51: SB then LB same location
        write_mem(32'h0000_0080, 32'h000000AA, 4'b0001);
        read_mem(32'h0000_0080, 4'b0001);
        check_load("SB 0xAA then LB: Coherency check", 32'hFFFFFFAA);
        
        // Test 52: SH then LH same location
        write_mem(32'h0000_0084, 32'h0000BBCC, 4'b0011);
        read_mem(32'h0000_0084, 4'b0011);
        check_load("SH 0xBBCC then LH: Coherency check", 32'hFFFFBBCC);
        
        // Test 53: SW then LW same location
        write_mem(32'h0000_0088, 32'hDDEEFF00, 4'b1111);
        read_mem(32'h0000_0088, 4'b1111);
        check_load("SW 0xDDEEFF00 then LW: Coherency check", 32'hDDEEFF00);
        
        // Test 54: SW then LH (partial read)
        write_mem(32'h0000_008C, 32'h11223344, 4'b1111);
        read_mem(32'h0000_008C, 4'b0011);
        check_load("SW then LH lower: Read 0x3344", 32'h00003344);
        
        read_mem(32'h0000_008E, 4'b0011);
        check_load("SW then LH upper: Read 0x1122", 32'h00001122);
        
        // Test 55: SW then LB (byte reads)
        write_mem(32'h0000_0090, 32'h55667788, 4'b1111);
        read_mem(32'h0000_0090, 4'b0001);
        check_load("SW then LB byte 0: Read 0x88", 32'hFFFFFF88);
        
        read_mem(32'h0000_0091, 4'b0001);
        check_load("SW then LB byte 1: Read 0x77", 32'h00000077);
        
        read_mem(32'h0000_0092, 4'b0001);
        check_load("SW then LB byte 2: Read 0x66", 32'h00000066);
        
        read_mem(32'h0000_0093, 4'b0001);
        check_load("SW then LB byte 3: Read 0x55", 32'h00000055);
        
        // ========================================
        // PARTIAL WRITE TESTS
        // ========================================
        $display("");
        $display("╔══════════════════════════════════════════════════════════════╗");
        $display("║  PARTIAL WRITE TESTS (Byte Masking)                         ║");
        $display("╚══════════════════════════════════════════════════════════════╝");
        
        // Test 56: Write word, then overwrite with byte
        write_mem(32'h0000_00A0, 32'hFFFFFFFF, 4'b1111);
        write_mem(32'h0000_00A0, 32'h00000012, 4'b0001);
        read_mem(32'h0000_00A0, 4'b1111);
        check_load("Overwrite byte 0: Should be 0xFFFFFF12", 32'hFFFFFF12);
        
        // Test 57: Overwrite different bytes
        write_mem(32'h0000_00A4, 32'h00000000, 4'b1111);
        write_mem(32'h0000_00A4, 32'h000000AA, 4'b0001);  // byte 0
        write_mem(32'h0000_00A5, 32'h000000BB, 4'b0001);  // byte 1
        write_mem(32'h0000_00A6, 32'h000000CC, 4'b0001);  // byte 2
        write_mem(32'h0000_00A7, 32'h000000DD, 4'b0001);  // byte 3
        read_mem(32'h0000_00A4, 4'b1111);
        check_load("Write 4 bytes individually: 0xDDCCBBAA", 32'hDDCCBBAA);
        
        // Test 58: Overwrite with halfword
        write_mem(32'h0000_00A8, 32'hAAAAAAAA, 4'b1111);
        write_mem(32'h0000_00A8, 32'h00001234, 4'b0011);
        read_mem(32'h0000_00A8, 4'b1111);
        check_load("Overwrite lower halfword: 0xAAAA1234", 32'hAAAA1234);
        
        write_mem(32'h0000_00AA, 32'h00005678, 4'b0011);
        read_mem(32'h0000_00A8, 4'b1111);
        check_load("Overwrite upper halfword: 0x56781234", 32'h56781234);
        
        // ========================================
        // ZERO/MAX VALUE TESTS
        // ========================================
        $display("");
        $display("╔══════════════════════════════════════════════════════════════╗");
        $display("║  EDGE CASE TESTS (Zero, Max, Min values)                    ║");
        $display("╚══════════════════════════════════════════════════════════════╝");
        
        // Test 59: All zeros
        write_mem(32'h0000_00B0, 32'h00000000, 4'b1111);
        read_mem(32'h0000_00B0, 4'b1111);
        check_load("LW: All zeros", 32'h00000000);
        
        // Test 60: All ones
        write_mem(32'h0000_00B4, 32'hFFFFFFFF, 4'b1111);
        read_mem(32'h0000_00B4, 4'b1111);
        check_load("LW: All ones", 32'hFFFFFFFF);
        
        // Test 61: Alternating pattern
        write_mem(32'h0000_00B8, 32'hAAAAAAAA, 4'b1111);
        read_mem(32'h0000_00B8, 4'b1111);
        check_load("LW: Pattern 0xAAAAAAAA", 32'hAAAAAAAA);
        
        // Test 62: Another pattern
        write_mem(32'h0000_00BC, 32'h55555555, 4'b1111);
        read_mem(32'h0000_00BC, 4'b1111);
        check_load("LW: Pattern 0x55555555", 32'h55555555);
        
        // ========================================
        // MEMORY BOUNDARY TESTS
        // ========================================
        $display("");
        $display("╔══════════════════════════════════════════════════════════════╗");
        $display("║  MEMORY BOUNDARY TESTS                                       ║");
        $display("╚══════════════════════════════════════════════════════════════╝");
        
        // Test 63: Near end of memory
        write_mem(32'h0000_07F0, 32'hBEEFCAFE, 4'b1111);
        read_mem(32'h0000_07F0, 4'b1111);
        check_load("Near memory end: 0xBEEFCAFE", 32'hBEEFCAFE);
        
        // Test 64: Last word in memory
        write_mem(32'h0000_07FC, 32'hFACEB00C, 4'b1111);
        read_mem(32'h0000_07FC, 4'b1111);
        check_load("Last memory word: 0xFACEB00C", 32'hFACEB00C);
        
        // ========================================
        // SUMMARY
        // ========================================
        #(CLK_PERIOD * 5);
        
        $display("");
        $display("╔══════════════════════════════════════════════════════════════╗");
        $display("║                    VERIFICATION SUMMARY                      ║");
        $display("╠══════════════════════════════════════════════════════════════╣");
        $display("║  Total Tests:  %3d                                           ║", test_num);
        $display("║  Passed:       %3d                                           ║", pass_count);
        $display("║  Failed:       %3d                                           ║", fail_count);
        $display("╠══════════════════════════════════════════════════════════════╣");
        
        if (fail_count == 0) begin
            $display("║                  ✓ ALL TESTS PASSED! ✓                      ║");
        end else begin
            $display("║                  ✗ SOME TESTS FAILED! ✗                     ║");
        end
        
        $display("╚══════════════════════════════════════════════════════════════╝");
        $display("");
        
        $finish;
    end
    
    // Timeout watchdog
    initial begin
        #(CLK_PERIOD * 10000);
        $display("ERROR: Testbench timeout!");
        $finish;
    end

endmodule
