// =========================================================
// ALU TESTBENCH - Golden Reference Model
// Su dung alu_clean.hex nhu GOLDEN machine code
// Tu dong decode va verify ALU outputs
// =========================================================

`timescale 1ns/1ps

module alu_tb_golden;

    // =========================================================
    // Signal Declarations
    // =========================================================
    logic [31:0] i_op_a;
    logic [31:0] i_op_b;
    logic [3:0]  i_alu_op;
    logic [31:0] o_alu_data;
    logic [31:0] expected;
    
    // Test Statistics
    int test_num = 0;
    int pass_count = 0;
    int fail_count = 0;
    int failed_tests[100];
    int fail_idx = 0;
    
    // Test case storage for table display
    typedef struct {
        int test_id;
        string test_name;
        logic [31:0] instr;
        logic [31:0] op_a;
        logic [31:0] op_b;
        logic [3:0] alu_op;
        logic [31:0] expected_val;
        logic [31:0] actual_val;
        string result;
    } test_case_t;
    
    test_case_t test_cases[100];
    int test_case_count = 0;
    
    // Golden instruction memory
    logic [31:0] golden_imem[0:255];
    
    // =========================================================
    // DUT - ALU Module
    // =========================================================
    alu dut (
        .i_op_a(i_op_a),
        .i_op_b(i_op_b),
        .i_alu_op(i_alu_op),
        .o_alu_data(o_alu_data)
    );

    // =========================================================
    // Task: Print table header
    // =========================================================
    task print_table_header();
        $display("# =====================================================================================================");
        $display("# Test | Instruction                          | i_instr  | Sel | o_immgen | Exp_immg | Verdict      |");
        $display("# -----|--------------------------------------|----------|-----|----------|----------|--------------|");
    endtask
    
    // =========================================================
    // Task: Print table row
    // =========================================================
    task print_table_row(
        input [31:0] exp,
        input [31:0] instr,
        input string instr_desc
    );
        string verdict;
        
        #1; // Wait for combinational logic
        
        if (o_alu_data === exp) begin
            verdict = "AS EXPECTED";
            pass_count++;
        end else begin
            verdict = "FAILED";
            failed_tests[fail_idx] = test_num;
            fail_idx++;
            fail_count++;
        end
        
        $display("# %4d | %-36s | %08h | %3d | %08h | %08h | %-12s |", 
                 test_num, instr_desc, instr, 0, o_alu_data, exp, verdict);
    endtask

    // =========================================================
    // Task: Check ALU output (Original detailed display)
    // =========================================================
    task check_alu(
        input string test_name,
        input [31:0] exp,
        input [31:0] instr,
        input int hex_idx
    );
        logic [6:0] opcode;
        logic [4:0] rd, rs1, rs2;
        logic [2:0] funct3;
        logic [6:0] funct7;
        string instr_type;
        string alu_op_name;
        
        test_num++;
        
        // Decode instruction
        opcode = instr[6:0];
        rd = instr[11:7];
        funct3 = instr[14:12];
        rs1 = instr[19:15];
        rs2 = instr[24:20];
        funct7 = instr[31:25];
        
        // Determine instruction type
        case(opcode)
            7'b0110011: instr_type = "R-type";
            7'b0010011: instr_type = "I-type";
            7'b0110111: instr_type = "U-type";
            default: instr_type = "Unknown";
        endcase
        
        // Decode ALU operation name
        case(i_alu_op)
            4'b0000: alu_op_name = "ADD";
            4'b0001: alu_op_name = "SUB";
            4'b0010: alu_op_name = "SLL";
            4'b0011: alu_op_name = "SLT";
            4'b0100: alu_op_name = "SLTU";
            4'b0101: alu_op_name = "XOR";
            4'b0110: alu_op_name = "SRL";
            4'b0111: alu_op_name = "SRA";
            4'b1000: alu_op_name = "OR";
            4'b1001: alu_op_name = "AND";
            4'b1111: alu_op_name = "LUI";
            default: alu_op_name = "UNKNOWN";
        endcase
        
        #1; // Wait for combinational logic
        
        // Store test case for table
        test_cases[test_case_count].test_id = test_num;
        test_cases[test_case_count].test_name = test_name;
        test_cases[test_case_count].instr = instr;
        test_cases[test_case_count].op_a = i_op_a;
        test_cases[test_case_count].op_b = i_op_b;
        test_cases[test_case_count].alu_op = i_alu_op;
        test_cases[test_case_count].expected_val = exp;
        test_cases[test_case_count].actual_val = o_alu_data;
        
        if (o_alu_data === exp) begin
            $display("[%0t] [PASS] Test %0d: %s", $time, test_num, test_name);
            $display("    Instruction:     0x%08h (Golden from hex[%0d])", instr, hex_idx);
            $display("    ASM:             %s (rd=x%0d, rs1=x%0d, rs2=x%0d, funct3=0x%01h)", 
                     instr_type, rd, rs1, rs2, funct3);
            $display("    ALU Operation:   %s (alu_op=0x%01h)", alu_op_name, i_alu_op);
            $display("    Input op_a:      0x%08h", i_op_a);
            $display("    Input op_b:      0x%08h", i_op_b);
            $display("    Expected Output:");
            $display("      - o_alu_data:  0x%08h", exp);
            $display("    Actual Output:");
            $display("      - o_alu_data:  0x%08h (MATCH)", o_alu_data);
            test_cases[test_case_count].result = "PASS";
            pass_count++;
        end else begin
            $display("[%0t] [FAIL] Test %0d: %s", $time, test_num, test_name);
            $display("    Instruction:     0x%08h (Golden from hex[%0d])", instr, hex_idx);
            $display("    ASM:             %s (rd=x%0d, rs1=x%0d, rs2=x%0d, funct3=0x%01h)", 
                     instr_type, rd, rs1, rs2, funct3);
            $display("    ALU Operation:   %s (alu_op=0x%01h)", alu_op_name, i_alu_op);
            $display("    Input op_a:      0x%08h", i_op_a);
            $display("    Input op_b:      0x%08h", i_op_b);
            $display("    Expected Output:");
            $display("      - o_alu_data:  0x%08h", exp);
            $display("    Actual Output:");
            $display("      - o_alu_data:  0x%08h [MISMATCH]", o_alu_data);
            $display("    Difference:      0x%08h", exp - o_alu_data);
            test_cases[test_case_count].result = "FAIL";
            failed_tests[fail_idx] = test_num;
            fail_idx++;
            fail_count++;
        end
        test_case_count++;
        $display("");
    endtask

    // =========================================================
    // Main Test Sequence
    // =========================================================
    initial begin
        string hex_path;
        
        // Load golden instructions
        hex_path = "../hex/alu_clean.hex";
        $readmemh(hex_path, golden_imem);
        
        $display("========================================");
        $display("   ALU Golden Reference Testbench");
        $display("   Using alu_clean.hex as Golden Model");
        $display("========================================");
        $display("[INFO] Loaded golden instructions from: %s", hex_path);
        $display("[INFO] First instruction: 0x%08h", golden_imem[0]);
        $display("");
        
        // =====================================================
        // SECTION 1: ADD Operations
        // =====================================================
        $display("--- Testing ADD Operations ---");
        
        i_op_a = 32'h00000064; i_op_b = 32'h00000032; i_alu_op = 4'b0000; expected = 32'h00000096;
        check_alu("ADD: 0x64 + 0x32 = 0x96", expected, golden_imem[8], 8);
        
        i_op_a = 32'h00000064; i_op_b = 32'h00000019; i_alu_op = 4'b0000; expected = 32'h0000007D;
        check_alu("ADD: 0x64 + 0x19 = 0x7D", expected, golden_imem[9], 9);
        
        i_op_a = 32'h00000064; i_op_b = 32'hFFFFFFE2; i_alu_op = 4'b0000; expected = 32'h00000046;
        check_alu("ADD: 0x64 + 0xFFFFFFE2 = 0x46", expected, golden_imem[10], 10);
        
        i_op_a = 32'h7FFFF000; i_op_b = 32'h000007FF; i_alu_op = 4'b0000; expected = 32'h7FFFF7FF;
        check_alu("ADD: 0x7FFFF000 + 0x7FF = 0x7FFFF7FF", expected, golden_imem[12], 12);
        
        i_op_a = 32'h7FFFF7FF; i_op_b = 32'h00000001; i_alu_op = 4'b0000; expected = 32'h7FFFF800;
        check_alu("ADD: 0x7FFFF7FF + 0x1 = 0x7FFFF800", expected, golden_imem[13], 13);
        
        // =====================================================
        // SECTION 2: SUB Operations
        // =====================================================
        $display("--- Testing SUB Operations ---");
        
        i_op_a = 32'h00000064; i_op_b = 32'h00000032; i_alu_op = 4'b0001; expected = 32'h00000032;
        check_alu("SUB: 0x64 - 0x32 = 0x32", expected, golden_imem[14], 14);
        
        i_op_a = 32'h00000032; i_op_b = 32'h00000064; i_alu_op = 4'b0001; expected = 32'hFFFFFFCE;
        check_alu("SUB: 0x32 - 0x64 = 0xFFFFFFCE", expected, golden_imem[15], 15);
        
        i_op_a = 32'h00000064; i_op_b = 32'hFFFFFFE2; i_alu_op = 4'b0001; expected = 32'h00000082;
        check_alu("SUB: 0x64 - 0xFFFFFFE2 = 0x82", expected, golden_imem[16], 16);
        
        // =====================================================
        // SECTION 3: SLL Operations
        // =====================================================
        $display("--- Testing SLL Operations ---");
        
        i_op_a = 32'h00000064; i_op_b = 32'h00000005; i_alu_op = 4'b0010; expected = 32'h00000C80;
        check_alu("SLL: 0x64 << 5 = 0xC80", expected, golden_imem[18], 18);
        
        i_op_a = 32'h00000064; i_op_b = 32'h00000003; i_alu_op = 4'b0010; expected = 32'h00000320;
        check_alu("SLL: 0x64 << 3 = 0x320", expected, golden_imem[19], 19);
        
        i_op_a = 32'h0000000F; i_op_b = 32'h00000010; i_alu_op = 4'b0010; expected = 32'h000F0000;
        check_alu("SLL: 0xF << 16 = 0xF0000", expected, golden_imem[20], 20);
        
        // =====================================================
        // SECTION 4: SLT Operations
        // =====================================================
        $display("--- Testing SLT Operations ---");
        
        i_op_a = 32'h00000032; i_op_b = 32'h00000064; i_alu_op = 4'b0011; expected = 32'h00000001;
        check_alu("SLT: 0x32 < 0x64 = 1 (signed)", expected, golden_imem[26], 26);
        
        i_op_a = 32'h00000064; i_op_b = 32'h00000032; i_alu_op = 4'b0011; expected = 32'h00000000;
        check_alu("SLT: 0x64 < 0x32 = 0 (signed)", expected, golden_imem[27], 27);
        
        i_op_a = 32'hFFFFFFE2; i_op_b = 32'h00000032; i_alu_op = 4'b0011; expected = 32'h00000001;
        check_alu("SLT: 0xFFFFFFE2 < 0x32 = 1 (signed)", expected, golden_imem[28], 28);
        
        // =====================================================
        // SECTION 5: SLTU Operations
        // =====================================================
        $display("--- Testing SLTU Operations ---");
        
        i_op_a = 32'h00000032; i_op_b = 32'h00000064; i_alu_op = 4'b0100; expected = 32'h00000001;
        check_alu("SLTU: 0x32 < 0x64 = 1 (unsigned)", expected, golden_imem[33], 33);
        
        i_op_a = 32'hFFFFFFE2; i_op_b = 32'h00000032; i_alu_op = 4'b0100; expected = 32'h00000000;
        check_alu("SLTU: 0xFFFFFFE2 < 0x32 = 0 (unsigned)", expected, golden_imem[34], 34);
        
        // =====================================================
        // SECTION 6: XOR Operations
        // =====================================================
        $display("--- Testing XOR Operations ---");
        
        i_op_a = 32'h00000064; i_op_b = 32'h00000032; i_alu_op = 4'b0101; expected = 32'h00000056;
        check_alu("XOR: 0x64 ^ 0x32 = 0x56", expected, golden_imem[36], 36);
        
        i_op_a = 32'h00000064; i_op_b = 32'h000000FF; i_alu_op = 4'b0101; expected = 32'h0000009B;
        check_alu("XOR: 0x64 ^ 0xFF = 0x9B", expected, golden_imem[37], 37);
        
        i_op_a = 32'h00000064; i_op_b = 32'h00000064; i_alu_op = 4'b0101; expected = 32'h00000000;
        check_alu("XOR: 0x64 ^ 0x64 = 0x0 (self-xor)", expected, golden_imem[39], 39);
        
        // =====================================================
        // SECTION 7: SRL Operations
        // =====================================================
        $display("--- Testing SRL Operations ---");
        
        i_op_a = 32'h00000064; i_op_b = 32'h00000004; i_alu_op = 4'b0110; expected = 32'h00000006;
        check_alu("SRL: 0x64 >> 4 = 0x6", expected, golden_imem[41], 41);
        
        i_op_a = 32'h12345678; i_op_b = 32'h0000000C; i_alu_op = 4'b0110; expected = 32'h00012345;
        check_alu("SRL: 0x12345678 >> 12 = 0x12345", expected, golden_imem[42], 42);
        
        // =====================================================
        // SECTION 8: SRA Operations
        // =====================================================
        $display("--- Testing SRA Operations ---");
        
        i_op_a = 32'hFFFFFFE2; i_op_b = 32'h00000004; i_alu_op = 4'b0111; expected = 32'hFFFFFFFE;
        check_alu("SRA: 0xFFFFFFE2 >> 4 = 0xFFFFFFFE (sign-extend)", expected, golden_imem[46], 46);
        
        i_op_a = 32'hFFFFFFE2; i_op_b = 32'h00000004; i_alu_op = 4'b0111; expected = 32'hFFFFFFFE;
        check_alu("SRA: 0xFFFFFFE2 >> 4 = 0xFFFFFFFE", expected, golden_imem[47], 47);
        
        // =====================================================
        // SECTION 9: OR Operations
        // =====================================================
        $display("--- Testing OR Operations ---");
        
        i_op_a = 32'h00000064; i_op_b = 32'h00000032; i_alu_op = 4'b1000; expected = 32'h00000076;
        check_alu("OR: 0x64 | 0x32 = 0x76", expected, golden_imem[51], 51);
        
        i_op_a = 32'h00000064; i_op_b = 32'h000000FF; i_alu_op = 4'b1000; expected = 32'h000000FF;
        check_alu("OR: 0x64 | 0xFF = 0xFF", expected, golden_imem[52], 52);
        
        i_op_a = 32'h00000064; i_op_b = 32'h00000064; i_alu_op = 4'b1000; expected = 32'h00000064;
        check_alu("OR: 0x64 | 0x64 = 0x64 (self-or)", expected, golden_imem[54], 54);
        
        // =====================================================
        // SECTION 10: AND Operations
        // =====================================================
        $display("--- Testing AND Operations ---");
        
        i_op_a = 32'h00000064; i_op_b = 32'h00000032; i_alu_op = 4'b1001; expected = 32'h00000020;
        check_alu("AND: 0x64 & 0x32 = 0x20", expected, golden_imem[55], 55);
        
        i_op_a = 32'h00000064; i_op_b = 32'h0000000F; i_alu_op = 4'b1001; expected = 32'h00000004;
        check_alu("AND: 0x64 & 0xF = 0x4 (bit mask)", expected, golden_imem[56], 56);
        
        i_op_a = 32'h00000064; i_op_b = 32'h00000000; i_alu_op = 4'b1001; expected = 32'h00000000;
        check_alu("AND: 0x64 & 0x0 = 0x0", expected, golden_imem[58], 58);
        
        // =====================================================
        // SECTION 11: LUI Operations
        // =====================================================
        $display("--- Testing LUI Operations ---");
        
        i_op_a = 32'h00000000; i_op_b = 32'hDEADB000; i_alu_op = 4'b1111; expected = 32'hDEADB000;
        check_alu("LUI: 0xDEADB000", expected, golden_imem[59], 59);
        
        i_op_a = 32'h00000000; i_op_b = 32'h12345000; i_alu_op = 4'b1111; expected = 32'h12345000;
        check_alu("LUI: 0x12345000", expected, golden_imem[60], 60);
        
        i_op_a = 32'h00000000; i_op_b = 32'hFFFFF000; i_alu_op = 4'b1111; expected = 32'hFFFFF000;
        check_alu("LUI: 0xFFFFF000", expected, golden_imem[61], 61);
        
        // =====================================================
        // SECTION 12: Edge Cases
        // =====================================================
        $display("--- Testing Edge Cases ---");
        
        i_op_a = 32'h00000064; i_op_b = 32'h00000000; i_alu_op = 4'b0000; expected = 32'h00000064;
        check_alu("Edge: ADD with zero", expected, golden_imem[62], 62);
        
        i_op_a = 32'h00000064; i_op_b = 32'h00000064; i_alu_op = 4'b0001; expected = 32'h00000000;
        check_alu("Edge: SUB same values", expected, golden_imem[63], 63);
        
        i_op_a = 32'h00000064; i_op_b = 32'h00000000; i_alu_op = 4'b0010; expected = 32'h00000064;
        check_alu("Edge: SLL by 0", expected, golden_imem[64], 64);
        
        i_op_a = 32'h00000064; i_op_b = 32'h00000000; i_alu_op = 4'b0110; expected = 32'h00000064;
        check_alu("Edge: SRL by 0", expected, golden_imem[65], 65);
        
        i_op_a = 32'h12345678; i_op_b = 32'hFFFFFFFF; i_alu_op = 4'b0101; expected = 32'hEDCBA987;
        check_alu("Edge: XOR with all ones (NOT)", expected, golden_imem[67], 67);
        
        // =====================================================
        // Summary
        // =====================================================
        $display("========================================");
        $display("   Golden Reference Verification Summary");
        $display("========================================");
        $display("Total Tests: %0d", test_num);
        $display("Passed:      %0d", pass_count);
        $display("Failed:      %0d", fail_count);
        
        if (fail_count == 0) begin
            $display("\n[PASS] ALL TESTS PASSED!");
            $display("[PASS] ALU module matches golden reference!");
            $display("[PASS] Perfect score: %0d/%0d", pass_count, test_num);
        end else begin
            $display("\n[FAIL] SOME TESTS FAILED!");
            $display("[FAIL] Failed %0d out of %0d tests", fail_count, test_num);
            $display("[FAIL] Failed test numbers:");
            for (int i = 0; i < fail_idx; i++) begin
                $display("   - Test %0d", failed_tests[i]);
            end
        end
        
        $display("========================================");
        
        // =====================================================
        // TABLE FORMAT FOR REPORT - Summary of all tests
        // =====================================================
        $display("\n\n========================================");
        $display("   TABLE FORMAT FOR REPORT");
        $display("========================================\n");
        
        $display("# ================================================================================================================");
        $display("# Test | Test Description                        | Instruction | op_a     | op_b     | Expected | Actual   | Result |");
        $display("# -----|------------------------------------------|-------------|----------|----------|----------|----------|--------|");
        
        for (int i = 0; i < test_case_count; i++) begin
            $display("# %4d | %-40s | 0x%08h | 0x%08h | 0x%08h | 0x%08h | 0x%08h | %-6s |",
                     test_cases[i].test_id,
                     test_cases[i].test_name,
                     test_cases[i].instr,
                     test_cases[i].op_a,
                     test_cases[i].op_b,
                     test_cases[i].expected_val,
                     test_cases[i].actual_val,
                     test_cases[i].result);
        end
        
        $display("# ================================================================================================================");
        
        $finish;
    end

endmodule
