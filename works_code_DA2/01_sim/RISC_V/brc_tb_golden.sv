// =========================================================
// BRC TESTBENCH - Golden Reference Model
// Sử dụng brc.hex như GOLDEN machine code
// Tự động decode và verify BRC outputs
// =========================================================

`timescale 1ns/1ps

module brc_tb_golden;

    // =========================================================
    // Signal Declarations
    // =========================================================
    logic [31:0] i_rs1_data;
    logic [31:0] i_rs2_data;
    logic        i_br_un;
    logic        o_br_equal;
    logic        o_br_less;
    
    // Register file simulation (x0 đến x31)
    logic [31:0] regs[0:31];
    
    // Expected values
    logic        expected_equal;
    logic        expected_less;
    
    // Test tracking
    int test_num = 0;
    int pass_count = 0;
    int fail_count = 0;
    int failed_tests[100];
    int fail_idx = 0;
    
    // Golden instruction memory
    logic [31:0] golden_imem[0:255];
    int instr_idx = 0;
    
    // Storage for table display - Updated to store actual test results
    typedef struct {
        int test_id;
        string test_name;
        logic [31:0] instr;
        logic [31:0] rs1_data;
        logic [31:0] rs2_data;
        logic br_un;
        logic exp_equal;
        logic exp_less;
        logic actual_equal;
        logic actual_less;
        string result;
    } test_case_t;
    
    test_case_t test_cases[100];
    int test_case_count = 0;
    
    // =========================================================
    // DUT - BRC Module
    // =========================================================
    brc dut (
        .i_rs1_data(i_rs1_data),
        .i_rs2_data(i_rs2_data),
        .i_br_un(i_br_un),
        .o_br_equal(o_br_equal),
        .o_br_less(o_br_less)
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
    // Task: Print table row for BRC
    // =========================================================
    task print_table_row_brc(
        input logic exp_equal,
        input logic exp_less,
        input [31:0] instr,
        input string instr_desc
    );
        string verdict;
        
        #1; // Wait for combinational logic
        
        if ((o_br_equal === exp_equal) && (o_br_less === exp_less)) begin
            verdict = "AS EXPECTED";
            pass_count++;
        end else begin
            verdict = "FAILED";
            failed_tests[fail_idx] = test_num;
            fail_idx++;
            fail_count++;
        end
        
        // Display format matching ALU table
        $display("# %4d | %-36s | %08h | %3d | %08h | %08h | %-12s |", 
                 test_num, instr_desc, instr, 0, i_rs1_data, i_rs2_data, verdict);
    endtask

    // =========================================================
    // Function: Compute Expected Outputs từ instruction
    // =========================================================
    function void compute_expected(
        input [31:0] rs1_val,
        input [31:0] rs2_val,
        input logic br_un,
        output logic exp_equal,
        output logic exp_less
    );
        // Compute equal
        exp_equal = (rs1_val == rs2_val);
        
        // Compute less
        if (br_un) begin
            // Unsigned comparison
            exp_less = (rs1_val < rs2_val);
        end else begin
            // Signed comparison
            exp_less = ($signed(rs1_val) < $signed(rs2_val));
        end
    endfunction

    // =========================================================
    // Task: Test một branch instruction từ golden memory
    // =========================================================
    task test_branch_instr(input int idx);
        logic [31:0] instruction;
        logic [6:0] opcode;
        logic [2:0] funct3;
        logic [4:0] rs1_addr, rs2_addr;
        logic [12:1] imm_b;
        logic signed [31:0] branch_offset;
        string instr_name;
        logic should_test;
        
        instruction = golden_imem[idx];
        
        // Decode instruction
        opcode = instruction[6:0];
        funct3 = instruction[14:12];
        rs1_addr = instruction[19:15];
        rs2_addr = instruction[24:20];
        
        // Decode branch offset (B-type immediate)
        imm_b = {instruction[31], instruction[7], instruction[30:25], instruction[11:8]};
        branch_offset = $signed({imm_b, 1'b0});
        
        // Check if this is a branch instruction
        should_test = (opcode == 7'b1100011);
        
        if (!should_test) return; // Skip non-branch instructions
        
        // Determine instruction name and br_un
        case(funct3)
            3'b000: begin instr_name = "beq";  i_br_un = 1'b0; end
            3'b001: begin instr_name = "bne";  i_br_un = 1'b0; end
            3'b100: begin instr_name = "blt";  i_br_un = 1'b0; end
            3'b101: begin instr_name = "bge";  i_br_un = 1'b0; end
            3'b110: begin instr_name = "bltu"; i_br_un = 1'b1; end
            3'b111: begin instr_name = "bgeu"; i_br_un = 1'b1; end
            default: begin instr_name = "unknown"; should_test = 1'b0; end
        endcase
        
        if (!should_test) return;
        
        test_num++;
        
        // Get register values
        i_rs1_data = regs[rs1_addr];
        i_rs2_data = regs[rs2_addr];
        
        // Compute expected outputs
        compute_expected(i_rs1_data, i_rs2_data, i_br_un, expected_equal, expected_less);
        
        #1; // Wait for combinational logic
        
        // Store test case for table display
        test_cases[test_case_count].test_id = test_num;
        test_cases[test_case_count].test_name = $sformatf("%s x%0d, x%0d, offset=%0d", instr_name, rs1_addr, rs2_addr, branch_offset);
        test_cases[test_case_count].instr = instruction;
        test_cases[test_case_count].rs1_data = i_rs1_data;
        test_cases[test_case_count].rs2_data = i_rs2_data;
        test_cases[test_case_count].br_un = i_br_un;
        test_cases[test_case_count].exp_equal = expected_equal;
        test_cases[test_case_count].exp_less = expected_less;
        test_cases[test_case_count].actual_equal = o_br_equal;
        test_cases[test_case_count].actual_less = o_br_less;
        
        // Check results
        if ((o_br_equal === expected_equal) && (o_br_less === expected_less)) begin
            $display("[%0t] [PASS] Test %0d", $time, test_num);
            $display("    Instruction:     0x%08h  (Golden from hex[%0d])", instruction, idx);
            $display("    ASM:             %s x%0d, x%0d, offset=%0d", instr_name, rs1_addr, rs2_addr, branch_offset);
            $display("    Branch Offset:   0x%08h (%0d bytes)", branch_offset, branch_offset);
            $display("    Input rs1:       0x%08h (x%0d)", i_rs1_data, rs1_addr);
            $display("    Input rs2:       0x%08h (x%0d)", i_rs2_data, rs2_addr);
            $display("    Input br_un:     0x%01h (%s)", i_br_un, i_br_un ? "unsigned" : "signed");
            $display("    Expected equal:  0x%01h", expected_equal);
            $display("    Expected less:   0x%01h", expected_less);
            $display("    Actual equal:    0x%01h (MATCH)", o_br_equal);
            $display("    Actual less:     0x%01h (MATCH)", o_br_less);
            test_cases[test_case_count].result = "PASS";
            pass_count++;
        end else begin
            $display("[%0t] [FAIL] Test %0d", $time, test_num);
            $display("    Instruction:     0x%08h  (Golden from hex[%0d])", instruction, idx);
            $display("    ASM:             %s x%0d, x%0d, offset=%0d", instr_name, rs1_addr, rs2_addr, branch_offset);
            $display("    Branch Offset:   0x%08h (%0d bytes)", branch_offset, branch_offset);
            $display("    Input rs1:       0x%08h (x%0d)", i_rs1_data, rs1_addr);
            $display("    Input rs2:       0x%08h (x%0d)", i_rs2_data, rs2_addr);
            $display("    Input br_un:     0x%01h (%s)", i_br_un, i_br_un ? "unsigned" : "signed");
            $display("    Expected equal:  0x%01h", expected_equal);
            $display("    Expected less:   0x%01h", expected_less);
            $display("    Actual equal:    0x%01h %s", o_br_equal, (o_br_equal === expected_equal) ? "(MATCH)" : "[MISMATCH]");
            $display("    Actual less:     0x%01h %s", o_br_less, (o_br_less === expected_less) ? "(MATCH)" : "[MISMATCH]");
            test_cases[test_case_count].result = "FAIL";
            failed_tests[fail_idx] = test_num;
            fail_idx++;
            fail_count++;
        end
        test_case_count++;
        $display("");
    endtask

    // =========================================================
    // Task: Execute non-branch instruction để update register state
    // =========================================================
    task execute_instruction(input int idx);
        logic [31:0] instruction;
        logic [6:0] opcode;
        logic [2:0] funct3;
        logic [4:0] rd, rs1_addr, rs2_addr;
        logic [11:0] imm_i;
        logic signed [31:0] imm_i_ext;
        
        instruction = golden_imem[idx];
        opcode = instruction[6:0];
        rd = instruction[11:7];
        funct3 = instruction[14:12];
        rs1_addr = instruction[19:15];
        rs2_addr = instruction[24:20];
        
        case(opcode)
            7'b0010011: begin // I-type (addi)
                imm_i = instruction[31:20];
                imm_i_ext = $signed(imm_i);
                if (rd != 0) begin
                    regs[rd] = regs[rs1_addr] + imm_i_ext;
                end
            end
            
            7'b0110011: begin // R-type (add, sub)
                if (rd != 0) begin
                    if (funct3 == 3'b000 && instruction[30] == 1'b0) begin // add
                        regs[rd] = regs[rs1_addr] + regs[rs2_addr];
                    end
                end
            end
            
            // Skip other instructions silently
            default: begin
            end
        endcase
    endtask

    // =========================================================
    // Main Test Sequence
    // =========================================================
    initial begin
        string hex_path;
        
        // Initialize register file
        for (int i = 0; i < 32; i++) begin
            regs[i] = 32'h0;
        end
        
        // Load golden instructions
        // QuestaSim working directory is usually project root
        hex_path = "../hex/brc_clean.hex";
        $readmemh(hex_path, golden_imem);
        
        $display("========================================");
        $display("   BRC Golden Reference Testbench");
        $display("   Using brc_clean.hex as Golden Model");
        $display("========================================");
        $display("[INFO] Loaded golden instructions from: %s", hex_path);
        $display("[INFO] First instruction: 0x%08h", golden_imem[0]);
        $display("");
        
        // Parse through golden instructions
        $display("[INFO] Parsing and testing branch instructions...");
        $display("");
        
        for (int i = 0; i < 141; i++) begin  // 141 instructions in brc.hex
            logic [31:0] instr;
            logic [6:0] opcode;
            
            instr = golden_imem[i];
            opcode = instr[6:0];
            
            if (opcode == 7'b1100011) begin
                // This is a branch instruction - test it
                test_branch_instr(i);
            end else begin
                // Execute non-branch instruction to update state (silently)
                execute_instruction(i);
            end
        end
        
        // Summary
        $display("========================================");
        $display("   Golden Reference Verification Summary");
        $display("========================================");
        $display("Total Branch Instructions Tested: %0d", test_num);
        $display("Passed:                           %0d", pass_count);
        $display("Failed:                           %0d", fail_count);
        
        if (fail_count == 0) begin
            $display("\n[PASS] ALL TESTS PASSED!");
            $display("[PASS] BRC module matches golden reference!");
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
        
        $display("# ========================================================================================================================================");
        $display("# Test | Branch Instruction                      | Instruction | rs1_data | rs2_data | br_un | Exp_eq | Exp_lt | Act_eq | Act_lt | Result |");
        $display("# -----|------------------------------------------|-------------|----------|----------|-------|--------|--------|--------|--------|--------|");
        
        for (int i = 0; i < test_case_count; i++) begin
            $display("# %4d | %-40s | 0x%08h | 0x%08h | 0x%08h | %5d | %6d | %6d | %6d | %6d | %-6s |",
                     test_cases[i].test_id,
                     test_cases[i].test_name,
                     test_cases[i].instr,
                     test_cases[i].rs1_data,
                     test_cases[i].rs2_data,
                     test_cases[i].br_un,
                     test_cases[i].exp_equal,
                     test_cases[i].exp_less,
                     test_cases[i].actual_equal,
                     test_cases[i].actual_less,
                     test_cases[i].result);
        end
        
        $display("# ========================================================================================================================================");
        
        $finish;
    end

endmodule
