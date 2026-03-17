`timescale 1ns / 1ps

module tb_immgen;

    // Signals
    logic [31:0] i_instr;
    logic [2:0] i_imm_sel;
    logic [31:0] o_immgen;
    logic [31:0] expected;
    
    // Instantiate DUT (Device Under Test)
    ImmGen dut (
        .i_instr(i_instr),
        .i_imm_sel(i_imm_sel),
        .o_immgen(o_immgen)
    );
    
    // Test counter
    int test_num = 0;
    int pass_count = 0;
    int fail_count = 0;
    
    // Task to check result
    task check_result(input string test_name, input [31:0] exp);
        test_num++;
        if (o_immgen === exp) begin
            $display("[PASS] Test %0d: %s", test_num, test_name);
            $display("       Input: 0x%08h, Sel: %0d, Output: 0x%08h (Expected: 0x%08h)", 
                     i_instr, i_imm_sel, o_immgen, exp);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: %s", test_num, test_name);
            $display("       Input: 0x%08h, Sel: %0d, Output: 0x%08h (Expected: 0x%08h)", 
                     i_instr, i_imm_sel, o_immgen, exp);
            fail_count++;
        end
        $display("");
    endtask
    
    initial begin
        $display("========================================");
        $display("  ImmGen Verification Testbench");
        $display("========================================");
        $display("");
        
        // ========================================
        // Test I-Type (i_imm_sel = 3'b000)
        // ========================================
        $display("--- Testing I-Type Instructions ---");
        
        // Test 1: ADDI x5, x5, 12 (positive immediate)
        i_instr = 32'h00C28293;  // addi x5, x5, 12
        i_imm_sel = 3'b000;
        expected = 32'h0000000C;
        #10;
        check_result("I-Type: addi x5, x5, 12", expected);
        
        // Test 2: ADDI x1, x0, -1 (negative immediate)
        i_instr = 32'hFFF00093;  // addi x1, x0, -1
        i_imm_sel = 3'b000;
        expected = 32'hFFFFFFFF;
        #10;
        check_result("I-Type: addi x1, x0, -1", expected);
        
        // Test 3: LW x2, 100(x1) (load with offset)
        i_instr = 32'h06402103;  // lw x2, 100(x1)
        i_imm_sel = 3'b000;
        expected = 32'h00000064;
        #10;
        check_result("I-Type: lw x2, 100(x1)", expected);
        
        // Test 4: ADDI with max positive (2047)
        i_instr = 32'h7FF00093;  // addi x1, x0, 2047
        i_imm_sel = 3'b000;
        expected = 32'h000007FF;
        #10;
        check_result("I-Type: addi x1, x0, 2047", expected);
        
        // Test 5: ADDI with min negative (-2048)
        i_instr = 32'h80000093;  // addi x1, x0, -2048
        i_imm_sel = 3'b000;
        expected = 32'hFFFFF800;
        #10;
        check_result("I-Type: addi x1, x0, -2048", expected);
        
        // ========================================
        // Test S-Type (i_imm_sel = 3'b001)
        // ========================================
        $display("--- Testing S-Type Instructions ---");
        
        // Test 6: SW x5, 12(x2)
        i_instr = 32'h00512623;  // sw x5, 12(x2)
        i_imm_sel = 3'b001;
        expected = 32'h0000000C;
        #10;
        check_result("S-Type: sw x5, 12(x2)", expected);
        
        // Test 7: SH x3, -4(x1) (negative offset)
        i_instr = 32'hFE309E23;  // sh x3, -4(x1)
        i_imm_sel = 3'b001;
        expected = 32'hFFFFFFFC;
        #10;
        check_result("S-Type: sh x3, -4(x1)", expected);
        
        // Test 8: SB x7, 31(x4)
        i_instr = 32'h00720FA3;  // sb x7, 31(x4)
        i_imm_sel = 3'b001;
        expected = 32'h0000001F;
        #10;
        check_result("S-Type: sb x7, 31(x4)", expected);
        
        // ========================================
        // Test B-Type (i_imm_sel = 3'b010)
        // ========================================
        $display("--- Testing B-Type Instructions ---");
        
        // Test 9: BEQ x1, x2, 8
        i_instr = 32'h00208463;  // beq x1, x2, 8
        i_imm_sel = 3'b010;
        expected = 32'h00000008;
        #10;
        check_result("B-Type: beq x1, x2, 8", expected);
        
        // Test 10: BNE x3, x4, -4
        i_instr = 32'hFE419EE3;  // bne x3, x4, -4
        i_imm_sel = 3'b010;
        expected = 32'hFFFFFFFC;
        #10;
        check_result("B-Type: bne x3, x4, -4", expected);
        
        // Test 11: BLT x5, x6, 16
        i_instr = 32'h0062C863;  // blt x5, x6, 16
        i_imm_sel = 3'b010;
        expected = 32'h00000010;
        #10;
        check_result("B-Type: blt x5, x6, 16", expected);
        
        // Test 12: BGE x1, x2, 100
        i_instr = 32'h0620D263;  // bge x1, x2, 100
        i_imm_sel = 3'b010;
        expected = 32'h00000064;
        #10;
        check_result("B-Type: bge x1, x2, 100", expected);
        
        // ========================================
        // Test U-Type (i_imm_sel = 3'b011)
        // ========================================
        $display("--- Testing U-Type Instructions ---");
        
        // Test 13: LUI x10, 0x12345
        i_instr = 32'h12345537;  // lui x10, 0x12345
        i_imm_sel = 3'b011;
        expected = 32'h12345000;
        #10;
        check_result("U-Type: lui x10, 0x12345", expected);
        
        // Test 14: AUIPC x5, 0xABCDE
        i_instr = 32'hABCDE297;  // auipc x5, 0xABCDE
        i_imm_sel = 3'b011;
        expected = 32'hABCDE000;
        #10;
        check_result("U-Type: auipc x5, 0xABCDE", expected);
        
        // Test 15: LUI x1, 0xFFFFF (negative)
        i_instr = 32'hFFFFF0B7;  // lui x1, 0xFFFFF
        i_imm_sel = 3'b011;
        expected = 32'hFFFFF000;
        #10;
        check_result("U-Type: lui x1, 0xFFFFF", expected);
        
        // ========================================
        // Test J-Type (i_imm_sel = 3'b100)
        // ========================================
        $display("--- Testing J-Type Instructions ---");
        
        // Test 16: JAL x1, 8
        i_instr = 32'h008000EF;  // jal x1, 8
        i_imm_sel = 3'b100;
        expected = 32'h00000008;
        #10;
        check_result("J-Type: jal x1, 8", expected);
        
        // Test 17: JAL x0, -4
        i_instr = 32'hFFDFF06F;  // jal x0, -4
        i_imm_sel = 3'b100;
        expected = 32'hFFFFFFFC;
        #10;
        check_result("J-Type: jal x0, -4", expected);
        
        // Test 18: JAL x5, 100
        i_instr = 32'h064002EF;  // jal x5, 100
        i_imm_sel = 3'b100;
        expected = 32'h00000064;
        #10;
        check_result("J-Type: jal x5, 100", expected);
        
        // Test 19: JAL with large offset (1048574)
        i_instr = 32'h7FFFF2EF;  // jal x5, 1048574
        i_imm_sel = 3'b100;
        expected = 32'h000FFFFE;
        #10;
        check_result("J-Type: jal x5, 1048574", expected);
        
        // ========================================
        // Test Default Case
        // ========================================
        $display("--- Testing Default Case ---");
        
        // Test 20: Invalid select
        i_instr = 32'h12345678;
        i_imm_sel = 3'b111;  // Invalid
        expected = 32'h00000000;
        #10;
        check_result("Default: Invalid select 3'b111", expected);
        
        // ========================================
        // Edge Cases
        // ========================================
        $display("--- Testing Edge Cases ---");
        
        // Test 21: All zeros instruction (I-Type)
        i_instr = 32'h00000000;
        i_imm_sel = 3'b000;
        expected = 32'h00000000;
        #10;
        check_result("Edge: All zeros (I-Type)", expected);
        
        // Test 22: All ones instruction (I-Type)
        i_instr = 32'hFFFFFFFF;
        i_imm_sel = 3'b000;
        expected = 32'hFFFFFFFF;
        #10;
        check_result("Edge: All ones (I-Type)", expected);
        
        // Test 23: All ones (U-Type)
        i_instr = 32'hFFFFFFFF;
        i_imm_sel = 3'b011;
        expected = 32'hFFFFF000;
        #10;
        check_result("Edge: All ones (U-Type)", expected);
        
        // ========================================
        // Summary
        // ========================================
        $display("========================================");
        $display("  Verification Summary");
        $display("========================================");
        $display("Total Tests: %0d", test_num);
        $display("Passed:      %0d", pass_count);
        $display("Failed:      %0d", fail_count);
        
        if (fail_count == 0) begin
            $display("\n*** ALL TESTS PASSED! ***\n");
        end else begin
            $display("\n*** SOME TESTS FAILED! ***\n");
        end
        
        $finish;
    end

endmodule
