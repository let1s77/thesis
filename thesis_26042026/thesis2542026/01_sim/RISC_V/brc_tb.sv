// =========================================================
// BRC TESTBENCH - Test Branch Comparator Module
// Test tất cả 6 branch instructions với instruction từ brc.hex
// =========================================================
// Test coverage:
//   - beq  (Branch if Equal)
//   - bne  (Branch if Not Equal)
//   - blt  (Branch if Less Than - signed)
//   - bge  (Branch if Greater or Equal - signed)
//   - bltu (Branch if Less Than - unsigned)
//   - bgeu (Branch if Greater or Equal - unsigned)
// =========================================================

`timescale 1ns/1ps

module brc_tb;

    // =========================================================
    // Signal Declarations
    // =========================================================
    logic [31:0] i_rs1_data;      // BRC operand A
    logic [31:0] i_rs2_data;      // BRC operand B
    logic        i_br_un;         // Unsigned compare flag
    logic        o_br_equal;      // Branch equal output
    logic        o_br_less;       // Branch less than output
    
    // Expected values
    logic        expected_equal;
    logic        expected_less;
    
    // Test Statistics
    int test_num = 0;             // Test counter
    int pass_count = 0;           // Số test PASS
    int fail_count = 0;           // Số test FAIL
    int failed_tests[100];        // Array lưu số test bị fail
    int fail_idx = 0;             // Index cho array failed_tests
    
    // Instruction tracking
    logic [31:0] instruction;     // Current instruction being tested
    logic [31:0] hex_file[0:255]; // Array chứa instructions từ brc.hex
    
    // =========================================================
    // DUT (Device Under Test) - BRC Module
    // =========================================================
    brc dut (
        .i_rs1_data(i_rs1_data),
        .i_rs2_data(i_rs2_data),
        .i_br_un(i_br_un),
        .o_br_equal(o_br_equal),
        .o_br_less(o_br_less)
    );

    // =========================================================
    // Task: Check BRC outputs với instruction tracking
    // =========================================================
    task check_brc(
        input string test_name, 
        input logic exp_equal, 
        input logic exp_less,
        input [31:0] instr,
        input int hex_idx
    );
        logic [6:0] opcode;
        logic [2:0] funct3;
        logic [4:0] rs1, rs2;
        string instr_name;
        
        test_num++;
        instruction = instr;
        
        // Decode instruction
        opcode = instruction[6:0];
        funct3 = instruction[14:12];
        rs1 = instruction[19:15];
        rs2 = instruction[24:20];
        
        // Determine instruction name
        if (opcode == 7'b1100011) begin
            case(funct3)
                3'b000: instr_name = "beq";
                3'b001: instr_name = "bne";
                3'b100: instr_name = "blt";
                3'b101: instr_name = "bge";
                3'b110: instr_name = "bltu";
                3'b111: instr_name = "bgeu";
                default: instr_name = "unknown";
            endcase
        end else begin
            instr_name = "not_branch";
        end
        
        #1; // Wait for combinational logic
        
        if ((o_br_equal === exp_equal) && (o_br_less === exp_less)) begin
            $display("[%0t] [PASS] Test %0d: %s", $time, test_num, test_name);
            $display("        Instruction (Machine Code): 0x%08h", instruction);
            $display("        Instruction (Decoded):      %s x%0d, x%0d (opcode=0x%02h, funct3=0x%01h) [hex_index=%0d]", 
                     instr_name, rs1, rs2, opcode, funct3, hex_idx);
            $display("        Inputs:");
            $display("          - rs1_data = 0x%08h (decimal: %0d, signed: %0d)", 
                     i_rs1_data, i_rs1_data, $signed(i_rs1_data));
            $display("          - rs2_data = 0x%08h (decimal: %0d, signed: %0d)", 
                     i_rs2_data, i_rs2_data, $signed(i_rs2_data));
            $display("          - br_un    = %0b (%s)", i_br_un, i_br_un ? "UNSIGNED" : "SIGNED");
            $display("        Expected Outputs:");
            $display("          - br_equal = %0b", exp_equal);
            $display("          - br_less  = %0b", exp_less);
            $display("        Actual Outputs:");
            $display("          - br_equal = %0b ✓ (MATCH)", o_br_equal);
            $display("          - br_less  = %0b ✓ (MATCH)", o_br_less);
            pass_count++;
        end else begin
            $display("[%0t] [FAIL] Test %0d: %s", $time, test_num, test_name);
            $display("        Instruction (Machine Code): 0x%08h", instruction);
            $display("        Instruction (Decoded):      %s x%0d, x%0d (opcode=0x%02h, funct3=0x%01h) [hex_index=%0d]", 
                     instr_name, rs1, rs2, opcode, funct3, hex_idx);
            $display("        Inputs:");
            $display("          - rs1_data = 0x%08h (decimal: %0d, signed: %0d)", 
                     i_rs1_data, i_rs1_data, $signed(i_rs1_data));
            $display("          - rs2_data = 0x%08h (decimal: %0d, signed: %0d)", 
                     i_rs2_data, i_rs2_data, $signed(i_rs2_data));
            $display("          - br_un    = %0b (%s)", i_br_un, i_br_un ? "UNSIGNED" : "SIGNED");
            $display("        Expected Outputs:");
            $display("          - br_equal = %0b", exp_equal);
            $display("          - br_less  = %0b", exp_less);
            $display("        Actual Outputs (MISMATCH):");
            if (o_br_equal !== exp_equal) begin
                $display("          - br_equal = %0b ✗ (Expected: %0b)", o_br_equal, exp_equal);
            end else begin
                $display("          - br_equal = %0b ✓ (MATCH)", o_br_equal);
            end
            if (o_br_less !== exp_less) begin
                $display("          - br_less  = %0b ✗ (Expected: %0b)", o_br_less, exp_less);
            end else begin
                $display("          - br_less  = %0b ✓ (MATCH)", o_br_less);
            end
            failed_tests[fail_idx] = test_num;
            fail_idx++;
            fail_count++;
        end
        $display("");
    endtask

    // =========================================================
    // Main Test Sequence
    // =========================================================
    initial begin
        // Initialize hex_file array (simplified - will be loaded from brc.hex)
        // Note: These are example instructions - actual hex file may differ
        
        $display("========================================");
        $display("   BRC Module Verification Testbench");
        $display("   Testing Branch Comparator");
        $display("========================================");
        $display("");
        
        // =====================================================
        // SECTION 1: BEQ - Branch if Equal (funct3 = 0x0)
        // =====================================================
        $display("--- Testing BEQ - Branch if Equal ---");
        
        // Test 1: beq x1, x1 (100 == 100) - Should set br_equal=1
        i_rs1_data = 32'h00000064;    // x1 = 100
        i_rs2_data = 32'h00000064;    // x1 = 100
        i_br_un = 1'b0;               // Don't care for equal
        expected_equal = 1'b1;         // Equal
        expected_less = 1'b0;          // Not less (equal)
        instruction = 32'h00108463;    // beq x1, x1, offset
        check_brc("beq x1, x1 (100 == 100)", expected_equal, expected_less, instruction, 0);
        
        // Test 2: beq x1, x2 (100 != 50) - Should set br_equal=0
        i_rs1_data = 32'h00000064;    // x1 = 100
        i_rs2_data = 32'h00000032;    // x2 = 50
        i_br_un = 1'b0;
        expected_equal = 1'b0;         // Not equal
        expected_less = 1'b0;          // 100 > 50
        instruction = 32'h00208463;    // beq x1, x2, offset
        check_brc("beq x1, x2 (100 != 50)", expected_equal, expected_less, instruction, 1);
        
        // =====================================================
        // SECTION 2: BNE - Branch if Not Equal (funct3 = 0x1)
        // =====================================================
        $display("--- Testing BNE - Branch if Not Equal ---");
        
        // Test 3: bne x1, x2 (100 != 50) - Should set br_equal=0
        i_rs1_data = 32'h00000064;    // x1 = 100
        i_rs2_data = 32'h00000032;    // x2 = 50
        i_br_un = 1'b0;
        expected_equal = 1'b0;         // Not equal
        expected_less = 1'b0;          // 100 > 50
        instruction = 32'h00209463;    // bne x1, x2, offset
        check_brc("bne x1, x2 (100 != 50)", expected_equal, expected_less, instruction, 2);
        
        // Test 4: bne x1, x1 (100 == 100) - Should set br_equal=1
        i_rs1_data = 32'h00000064;    // x1 = 100
        i_rs2_data = 32'h00000064;    // x1 = 100
        i_br_un = 1'b0;
        expected_equal = 1'b1;         // Equal
        expected_less = 1'b0;          // Not less
        instruction = 32'h00109463;    // bne x1, x1, offset
        check_brc("bne x1, x1 (100 == 100)", expected_equal, expected_less, instruction, 3);
        
        // =====================================================
        // SECTION 3: BLT - Branch if Less Than (signed) (funct3 = 0x4)
        // =====================================================
        $display("--- Testing BLT - Branch if Less Than (Signed) ---");
        
        // Test 5: blt x2, x1 (50 < 100) - Positive < Positive
        i_rs1_data = 32'h00000032;    // x2 = 50
        i_rs2_data = 32'h00000064;    // x1 = 100
        i_br_un = 1'b0;               // Signed
        expected_equal = 1'b0;         // Not equal
        expected_less = 1'b1;          // 50 < 100
        instruction = 32'h00114463;    // blt x2, x1, offset
        check_brc("blt x2, x1 (50 < 100, signed)", expected_equal, expected_less, instruction, 4);
        
        // Test 6: blt x1, x2 (100 >= 50) - Should NOT be less
        i_rs1_data = 32'h00000064;    // x1 = 100
        i_rs2_data = 32'h00000032;    // x2 = 50
        i_br_un = 1'b0;
        expected_equal = 1'b0;         // Not equal
        expected_less = 1'b0;          // 100 >= 50
        instruction = 32'h0020C463;    // blt x1, x2, offset
        check_brc("blt x1, x2 (100 >= 50, signed)", expected_equal, expected_less, instruction, 5);
        
        // Test 7: blt x3, x2 (-30 < 50) - Negative < Positive
        i_rs1_data = 32'hFFFFFFE2;    // x3 = -30
        i_rs2_data = 32'h00000032;    // x2 = 50
        i_br_un = 1'b0;               // Signed
        expected_equal = 1'b0;         // Not equal
        expected_less = 1'b1;          // -30 < 50 (signed)
        instruction = 32'h00214463;    // blt x3, x2, offset
        check_brc("blt x3, x2 (-30 < 50, signed)", expected_equal, expected_less, instruction, 6);
        
        // Test 8: blt x3, x4 (-30 < -10) - Negative < Negative
        i_rs1_data = 32'hFFFFFFE2;    // x3 = -30
        i_rs2_data = 32'hFFFFFFF6;    // x4 = -10
        i_br_un = 1'b0;               // Signed
        expected_equal = 1'b0;         // Not equal
        expected_less = 1'b1;          // -30 < -10 (signed)
        instruction = 32'h00418463;    // blt x3, x4, offset
        check_brc("blt x3, x4 (-30 < -10, signed)", expected_equal, expected_less, instruction, 7);
        
        // Test 9: blt x1, x1 (100 == 100) - Equal values
        i_rs1_data = 32'h00000064;    // x1 = 100
        i_rs2_data = 32'h00000064;    // x1 = 100
        i_br_un = 1'b0;
        expected_equal = 1'b1;         // Equal
        expected_less = 1'b0;          // Not less (equal)
        instruction = 32'h0010C463;    // blt x1, x1, offset
        check_brc("blt x1, x1 (100 == 100, signed)", expected_equal, expected_less, instruction, 8);
        
        // =====================================================
        // SECTION 4: BGE - Branch if Greater or Equal (signed) (funct3 = 0x5)
        // =====================================================
        $display("--- Testing BGE - Branch if Greater or Equal (Signed) ---");
        
        // Test 10: bge x1, x2 (100 >= 50)
        i_rs1_data = 32'h00000064;    // x1 = 100
        i_rs2_data = 32'h00000032;    // x2 = 50
        i_br_un = 1'b0;               // Signed
        expected_equal = 1'b0;         // Not equal
        expected_less = 1'b0;          // 100 >= 50
        instruction = 32'h0020D463;    // bge x1, x2, offset
        check_brc("bge x1, x2 (100 >= 50, signed)", expected_equal, expected_less, instruction, 9);
        
        // Test 11: bge x2, x1 (50 < 100)
        i_rs1_data = 32'h00000032;    // x2 = 50
        i_rs2_data = 32'h00000064;    // x1 = 100
        i_br_un = 1'b0;
        expected_equal = 1'b0;         // Not equal
        expected_less = 1'b1;          // 50 < 100
        instruction = 32'h00115463;    // bge x2, x1, offset
        check_brc("bge x2, x1 (50 < 100, signed)", expected_equal, expected_less, instruction, 10);
        
        // Test 12: bge x2, x3 (50 >= -30)
        i_rs1_data = 32'h00000032;    // x2 = 50
        i_rs2_data = 32'hFFFFFFE2;    // x3 = -30
        i_br_un = 1'b0;               // Signed
        expected_equal = 1'b0;         // Not equal
        expected_less = 1'b0;          // 50 >= -30 (signed)
        instruction = 32'h00315463;    // bge x2, x3, offset
        check_brc("bge x2, x3 (50 >= -30, signed)", expected_equal, expected_less, instruction, 11);
        
        // Test 13: bge x4, x3 (-10 >= -30)
        i_rs1_data = 32'hFFFFFFF6;    // x4 = -10
        i_rs2_data = 32'hFFFFFFE2;    // x3 = -30
        i_br_un = 1'b0;               // Signed
        expected_equal = 1'b0;         // Not equal
        expected_less = 1'b0;          // -10 >= -30 (signed)
        instruction = 32'h00325463;    // bge x4, x3, offset
        check_brc("bge x4, x3 (-10 >= -30, signed)", expected_equal, expected_less, instruction, 12);
        
        // Test 14: bge x1, x1 (100 >= 100)
        i_rs1_data = 32'h00000064;    // x1 = 100
        i_rs2_data = 32'h00000064;    // x1 = 100
        i_br_un = 1'b0;
        expected_equal = 1'b1;         // Equal
        expected_less = 1'b0;          // Not less
        instruction = 32'h0010D463;    // bge x1, x1, offset
        check_brc("bge x1, x1 (100 >= 100, signed)", expected_equal, expected_less, instruction, 13);
        
        // =====================================================
        // SECTION 5: BLTU - Branch if Less Than Unsigned (funct3 = 0x6)
        // =====================================================
        $display("--- Testing BLTU - Branch if Less Than (Unsigned) ---");
        
        // Test 15: bltu x6, x5 (50 < 4294967266 unsigned)
        i_rs1_data = 32'h00000032;    // x6 = 50
        i_rs2_data = 32'hFFFFFFE2;    // x5 = 0xFFFFFFE2 (large unsigned)
        i_br_un = 1'b1;               // Unsigned
        expected_equal = 1'b0;         // Not equal
        expected_less = 1'b1;          // 50 < 4294967266 (unsigned)
        instruction = 32'h00536463;    // bltu x6, x5, offset
        check_brc("bltu x6, x5 (50 < 4294967266, unsigned)", expected_equal, expected_less, instruction, 14);
        
        // Test 16: bltu x5, x6 (4294967266 >= 50 unsigned)
        i_rs1_data = 32'hFFFFFFE2;    // x5 = 0xFFFFFFE2
        i_rs2_data = 32'h00000032;    // x6 = 50
        i_br_un = 1'b1;               // Unsigned
        expected_equal = 1'b0;         // Not equal
        expected_less = 1'b0;          // 4294967266 >= 50 (unsigned)
        instruction = 32'h0062E463;    // bltu x5, x6, offset
        check_brc("bltu x5, x6 (4294967266 >= 50, unsigned)", expected_equal, expected_less, instruction, 15);
        
        // Test 17: bltu x2, x1 (50 < 100 unsigned)
        i_rs1_data = 32'h00000032;    // x2 = 50
        i_rs2_data = 32'h00000064;    // x1 = 100
        i_br_un = 1'b1;               // Unsigned
        expected_equal = 1'b0;         // Not equal
        expected_less = 1'b1;          // 50 < 100 (unsigned)
        instruction = 32'h00116463;    // bltu x2, x1, offset
        check_brc("bltu x2, x1 (50 < 100, unsigned)", expected_equal, expected_less, instruction, 16);
        
        // Test 18: bltu x1, x1 (100 == 100 unsigned)
        i_rs1_data = 32'h00000064;    // x1 = 100
        i_rs2_data = 32'h00000064;    // x1 = 100
        i_br_un = 1'b1;               // Unsigned
        expected_equal = 1'b1;         // Equal
        expected_less = 1'b0;          // Not less (equal)
        instruction = 32'h0010E463;    // bltu x1, x1, offset
        check_brc("bltu x1, x1 (100 == 100, unsigned)", expected_equal, expected_less, instruction, 17);
        
        // =====================================================
        // SECTION 6: BGEU - Branch if Greater or Equal Unsigned (funct3 = 0x7)
        // =====================================================
        $display("--- Testing BGEU - Branch if Greater or Equal (Unsigned) ---");
        
        // Test 19: bgeu x5, x6 (4294967266 >= 50 unsigned)
        i_rs1_data = 32'hFFFFFFE2;    // x5 = 0xFFFFFFE2
        i_rs2_data = 32'h00000032;    // x6 = 50
        i_br_un = 1'b1;               // Unsigned
        expected_equal = 1'b0;         // Not equal
        expected_less = 1'b0;          // 4294967266 >= 50 (unsigned)
        instruction = 32'h0062F463;    // bgeu x5, x6, offset
        check_brc("bgeu x5, x6 (4294967266 >= 50, unsigned)", expected_equal, expected_less, instruction, 18);
        
        // Test 20: bgeu x6, x5 (50 < 4294967266 unsigned)
        i_rs1_data = 32'h00000032;    // x6 = 50
        i_rs2_data = 32'hFFFFFFE2;    // x5 = 0xFFFFFFE2
        i_br_un = 1'b1;               // Unsigned
        expected_equal = 1'b0;         // Not equal
        expected_less = 1'b1;          // 50 < 4294967266 (unsigned)
        instruction = 32'h00537463;    // bgeu x6, x5, offset
        check_brc("bgeu x6, x5 (50 < 4294967266, unsigned)", expected_equal, expected_less, instruction, 19);
        
        // Test 21: bgeu x1, x2 (100 >= 50 unsigned)
        i_rs1_data = 32'h00000064;    // x1 = 100
        i_rs2_data = 32'h00000032;    // x2 = 50
        i_br_un = 1'b1;               // Unsigned
        expected_equal = 1'b0;         // Not equal
        expected_less = 1'b0;          // 100 >= 50 (unsigned)
        instruction = 32'h0020F463;    // bgeu x1, x2, offset
        check_brc("bgeu x1, x2 (100 >= 50, unsigned)", expected_equal, expected_less, instruction, 20);
        
        // Test 22: bgeu x1, x1 (100 >= 100 unsigned)
        i_rs1_data = 32'h00000064;    // x1 = 100
        i_rs2_data = 32'h00000064;    // x1 = 100
        i_br_un = 1'b1;               // Unsigned
        expected_equal = 1'b1;         // Equal
        expected_less = 1'b0;          // Not less
        instruction = 32'h0010F463;    // bgeu x1, x1, offset
        check_brc("bgeu x1, x1 (100 >= 100, unsigned)", expected_equal, expected_less, instruction, 21);
        
        // =====================================================
        // Summary
        // =====================================================
        $display("========================================");
        $display("   Verification Summary");
        $display("========================================");
        $display("Total Tests: %0d", test_num);
        $display("Passed:      %0d", pass_count);
        $display("Failed:      %0d", fail_count);
        
        if (fail_count == 0) begin
            $display("\n*** ALL TESTS PASSED! ***\n");
            $display("✓ Perfect Score!");
            $display("✓ BRC module working correctly!");
        end else begin
            $display("\n*** SOME TESTS FAILED! ***\n");
            $display("✗ HAVE %0d TESTS FAILED at TEST:", fail_count);
            for (int i = 0; i < fail_idx; i++) begin
                $display("   - Test %0d", failed_tests[i]);
            end
        end
        
        $finish;
    end

endmodule
