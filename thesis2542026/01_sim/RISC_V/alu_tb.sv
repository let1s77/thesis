// =========================================================
// ALU TESTBENCH - Test với Instructions từ alu.hex
// Decode instructions và test ALU operations
// Style giống tb_immgen.sv
// =========================================================
// Instructions từ alu_demo_web_gen.s sẽ được decode:
//   - Extract operands từ instruction encoding
//   - Xác định ALU operation từ funct3/funct7
//   - So sánh actual vs expected results
// =========================================================

`timescale 1ns/1ps

module alu_tb;

    // =========================================================
    // Signal Declarations
    // =========================================================
    logic [31:0] i_op_a;          // ALU operand A
    logic [31:0] i_op_b;          // ALU operand B
    logic [3:0]  i_alu_op;        // ALU operation code
    logic [31:0] o_alu_data;      // ALU output
    logic [31:0] expected;        // Expected result
    
    // Test Statistics
    int test_num = 0;             // Test counter
    int pass_count = 0;           // Số test PASS
    int fail_count = 0;           // Số test FAIL
    int failed_tests[100];        // Array lưu số test bị fail
    int fail_idx = 0;             // Index cho array failed_tests
    
    // Instruction encoding tracking
    logic [31:0] expected_instr;  // Expected instruction encoding từ alu.hex
    logic [31:0] hex_file [0:71]; // Array chứa instructions từ alu.hex
    int instr_index = 0;          // Index để track instruction hiện tại

    // =========================================================
    // DUT (Device Under Test) - ALU Module
    // =========================================================
    alu dut (
        .i_op_a(i_op_a),
        .i_op_b(i_op_b),
        .i_alu_op(i_alu_op),
        .o_alu_data(o_alu_data)
    );

    // =========================================================
    // Task: Check với instruction encoding từ alu.hex
    // Enhanced with instruction decode and timestamp
    // =========================================================
    task check_with_instr(input string test_name, input [31:0] exp, input int hex_idx);
        logic [6:0] opcode;
        logic [4:0] rd, rs1, rs2;
        logic [2:0] funct3;
        logic [6:0] funct7;
        logic [31:0] imm_i;
        string instr_type;
        string alu_op_name;
        
        test_num++;
        expected_instr = hex_file[hex_idx];
        
        // Decode instruction fields
        opcode = expected_instr[6:0];
        rd = expected_instr[11:7];
        funct3 = expected_instr[14:12];
        rs1 = expected_instr[19:15];
        rs2 = expected_instr[24:20];
        funct7 = expected_instr[31:25];
        imm_i = {{20{expected_instr[31]}}, expected_instr[31:20]}; // Sign-extended I-type immediate
        
        // Determine instruction type
        case(opcode)
            7'b0110011: instr_type = "R-type";
            7'b0010011: instr_type = "I-type";
            7'b0110111: instr_type = "U-type (LUI)";
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
        
        #1; // Đợi combinational logic ổn định
        
        if (o_alu_data === exp) begin
            $display("[%0t] [PASS] at Test %0d: %s", $time, test_num, test_name);
            $display("       📄 Expected Instruction: 0x%08h (from alu.hex[%0d])", expected_instr, hex_idx);
            $display("          Decoded: %s | opcode=0x%02h, rd=x%0d, rs1=x%0d, rs2=x%0d, funct3=%03b, imm_i=0x%08h (%0d)", 
                     instr_type, opcode, rd, rs1, rs2, funct3, imm_i, $signed(imm_i));
            $display("       🔧 ALU Operation: %s (alu_op=%04b)", alu_op_name, i_alu_op);
            $display("       📥 Operands: op_a=0x%08h (%0d), op_b=0x%08h (%0d)", 
                     i_op_a, $signed(i_op_a), i_op_b, $signed(i_op_b));
            $display("       ✅ Result: 0x%08h (%0d) == Expected: 0x%08h (%0d)", 
                     o_alu_data, $signed(o_alu_data), exp, $signed(exp));
            pass_count++;
        end else begin
            $display("[%0t] [FAIL] at Test %0d: %s", $time, test_num, test_name);
            $display("       📄 Expected Instruction: 0x%08h (from alu.hex[%0d])", expected_instr, hex_idx);
            $display("          Decoded: %s | opcode=0x%02h, rd=x%0d, rs1=x%0d, rs2=x%0d, funct3=%03b, imm_i=0x%08h (%0d)", 
                     instr_type, opcode, rd, rs1, rs2, funct3, imm_i, $signed(imm_i));
            $display("       🔧 ALU Operation: %s (alu_op=%04b)", alu_op_name, i_alu_op);
            $display("       📥 Operands: op_a=0x%08h (%0d), op_b=0x%08h (%0d)", 
                     i_op_a, $signed(i_op_a), i_op_b, $signed(i_op_b));
            $display("       ❌ MISMATCH:");
            $display("          Actual ALU Output:   0x%08h (%0d)", o_alu_data, $signed(o_alu_data));
            $display("          Expected Result:     0x%08h (%0d)", exp, $signed(exp));
            $display("          Difference:          0x%08h (%0d)", exp - o_alu_data, $signed(exp - o_alu_data));
            $display("       💡 Check: ALU correct? Or Expected value wrong?");
            failed_tests[fail_idx] = test_num;
            fail_idx++;
            fail_count++;
        end
        $display("");
    endtask

    // =========================================================
    // Main Test Sequence - Dựa trên alu_demo_web_gen.s
    // =========================================================
    initial begin
        // Load instructions từ alu.hex vào array
        hex_file[0]  = 32'h06400093; // addi x1, x0, 100
        hex_file[1]  = 32'h03200113; // addi x2, x0, 50
        hex_file[2]  = 32'hFE200193; // addi x3, x0, -30
        hex_file[3]  = 32'h00F00213; // addi x4, x0, 15
        hex_file[4]  = 32'h123452B7; // lui x5, 0x12345
        hex_file[5]  = 32'h67828293; // addi x5, x5, 0x678
        hex_file[6]  = 32'hABCDE337; // lui x6, 0xABCDE
        hex_file[7]  = 32'hEDD30313; // addi x6, x6, -291
        hex_file[8]  = 32'h002083B3; // add x7, x1, x2
        hex_file[9]  = 32'h01908413; // addi x8, x1, 25
        hex_file[10] = 32'h003084B3; // add x9, x1, x3
        hex_file[11] = 32'h7FFFF537; // lui x10, 0x7FFFF
        hex_file[12] = 32'h7FF50513; // addi x10, x10, 0x7FF
        hex_file[13] = 32'h00150593; // addi x11, x10, 1
        hex_file[14] = 32'h40208633; // sub x12, x1, x2
        hex_file[15] = 32'h401106B3; // sub x13, x2, x1
        hex_file[16] = 32'h40308733; // sub x14, x1, x3
        hex_file[17] = 32'h00500793; // addi x15, x0, 5
        hex_file[18] = 32'h00F09833; // sll x16, x1, x15
        hex_file[19] = 32'h00309893; // slli x17, x1, 3
        hex_file[20] = 32'h01021913; // slli x18, x4, 16
        hex_file[21] = 32'h00109993; // slli x19, x1, 1
        hex_file[22] = 32'h00209A13; // slli x20, x1, 2
        hex_file[23] = 32'h00409A93; // slli x21, x1, 4
        hex_file[24] = 32'h00809B13; // slli x22, x1, 8
        hex_file[25] = 32'h01009B93; // slli x23, x1, 16
        hex_file[26] = 32'h00112C33; // slt x24, x2, x1
        hex_file[27] = 32'h0020ACB3; // slt x25, x1, x2
        hex_file[28] = 32'h0021AD33; // slt x26, x3, x2
        hex_file[29] = 32'h0C80AD93; // slti x27, x1, 200
        hex_file[30] = 32'hFF600E93; // addi x29, x0, -10
        hex_file[31] = 32'h003EAF33; // slt x30, x29, x3
        hex_file[32] = 32'h01D1AFB3; // slt x31, x3, x29
        hex_file[33] = 32'h001133B3; // sltu x7, x2, x1
        hex_file[34] = 32'h0021B433; // sltu x8, x3, x2
        hex_file[35] = 32'h0C80B493; // sltiu x9, x1, 200
        hex_file[36] = 32'h0020C5B3; // xor x11, x1, x2
        hex_file[37] = 32'h0FF0C613; // xori x12, x1, 0xFF
        hex_file[38] = 32'h0062C6B3; // xor x13, x5, x6
        hex_file[39] = 32'h0010C733; // xor x14, x1, x1
        hex_file[40] = 32'h00400813; // addi x16, x0, 4
        hex_file[41] = 32'h0100D8B3; // srl x17, x1, x16
        hex_file[42] = 32'h00C2D913; // srli x18, x5, 12
        hex_file[43] = 32'h00835993; // srli x19, x6, 8
        hex_file[44] = 32'h0012DA13; // srli x20, x5, 1
        hex_file[45] = 32'h0022DA93; // srli x21, x5, 2
        hex_file[46] = 32'h4101DCB3; // sra x25, x3, x16
        hex_file[47] = 32'h4041DD13; // srai x26, x3, 4
        hex_file[48] = 32'h40835D93; // srai x27, x6, 8
        hex_file[49] = 32'h0041DE13; // srli x28, x3, 4
        hex_file[50] = 32'h4041DE93; // srai x29, x3, 4
        hex_file[51] = 32'h0020EF33; // or x30, x1, x2
        hex_file[52] = 32'h0FF0EF93; // ori x31, x1, 0xFF
        hex_file[53] = 32'h0062E3B3; // or x7, x5, x6
        hex_file[54] = 32'h0010E4B3; // or x9, x1, x1
        hex_file[55] = 32'h0020F533; // and x10, x1, x2
        hex_file[56] = 32'h00F0F593; // andi x11, x1, 0x0F
        hex_file[57] = 32'h0062F633; // and x12, x5, x6
        hex_file[58] = 32'h0000F6B3; // and x13, x1, x0
        hex_file[59] = 32'hDEADB7B7; // lui x15, 0xDEADB
        hex_file[60] = 32'h12345837; // lui x16, 0x12345
        hex_file[61] = 32'hFFFFF8B7; // lui x17, 0xFFFFF
        hex_file[62] = 32'h00008933; // add x18, x1, x0
        hex_file[63] = 32'h401089B3; // sub x19, x1, x1
        hex_file[64] = 32'h00009A33; // sll x20, x1, x0
        hex_file[65] = 32'h0000DAB3; // srl x21, x1, x0
        hex_file[66] = 32'hFFF00B13; // addi x22, x0, -1
        hex_file[67] = 32'h0162CBB3; // xor x23, x5, x22
        hex_file[68] = 32'h0000006F; // j end_loop
        hex_file[69] = 32'h00A00893; // addi a7, x0, 10
        hex_file[70] = 32'h00000073; // ecall
        
        $display("========================================");
        $display("   ALU Verification Testbench");
        $display("   With Instruction Encoding Check");
        $display("========================================");
        $display("");
        
        // =====================================================
        // SECTION 1: ADD Operations (ALU_OP = 4'b0000)
        // Instruction: ADD rd, rs1, rs2
        // Encoding: 0x002083B3 = add x7, x1, x2
        // =====================================================
        $display("--- Testing ADD Operations (ALU_OP = 4'b0000) ---");
        
        // Test 1: add x7, x1, x2 => 0x64 + 0x32 = 0x96 (100 + 50 = 150)
        // Instruction encoding: 0x002083B3 = add x7, x1, x2
        i_op_a = 32'h00000064;    // x1 = 100
        i_op_b = 32'h00000032;    // x2 = 50
        i_alu_op = 4'b0000;       // ADD
        expected = 32'h00000096;  // 150
        check_with_instr("ADD: add x7, x1, x2 => 0x64 + 0x32 = 0x96", expected, 8);
        
        // Test 2: addi x8, x1, 25 => 0x64 + 0x19 = 0x7D (100 + 25 = 125)
        // Instruction: 0x01908413 = addi x8, x1, 25
        i_op_a = 32'h00000064;    // x1 = 100
        i_op_b = 32'h00000019;    // Immediate = 25
        i_alu_op = 4'b0000;       // ADD
        expected = 32'h0000007D;  // 125
        check_with_instr("ADD: addi x8, x1, 25 => 0x64 + 0x19 = 0x7D", expected, 9);
        
        // Test 3: add x9, x1, x3 => 0x64 + 0xFFFFFFE2 = 0x46 (100 + (-30) = 70)
        // x3 = -30 = 0xFFFFFFE2 (two's complement)
        // Instruction: 0x003084B3 = add x9, x1, x3
        i_op_a = 32'h00000064;    // x1 = 100
        i_op_b = 32'hFFFFFFE2;    // x3 = -30
        i_alu_op = 4'b0000;       // ADD
        expected = 32'h00000046;  // 70
        check_with_instr("ADD: add x9, x1, x3 => 0x64 + 0xFFFFFFE2 = 0x46", expected, 10);
        
        // Test 4: addi x10, x10, 0x7FF => 0x7FFFF000 + 0x7FF = 0x7FFFF7FF
        // Instruction: 0x7FF50513 = addi x10, x10, 0x7FF (immediate = 2047)
        // Note: Instruction encodes imm=0x7FF, NOT 0xFFF, so result is 0x7FFFF7FF
        i_op_a = 32'h7FFFF000;
        i_op_b = 32'h000007FF;    // Immediate from instruction = 0x7FF (2047)
        i_alu_op = 4'b0000;
        expected = 32'h7FFFF7FF;  // Corrected: 0x7FFFF000 + 0x7FF = 0x7FFFF7FF
        check_with_instr("ADD: 0x7FFFF000 + 0x7FF = 0x7FFFF7FF (instruction encoding)", expected, 12);
        
        // Test 5: addi x11, x10, 1 => Overflow test
        // Note: Previous test result is 0x7FFFF7FF, adding 1 gives 0x7FFFF800
        // If we wanted max int overflow: 0x7FFFFFFF + 1 = 0x80000000
        // Instruction: 0x00150593 = addi x11, x10, 1
        i_op_a = 32'h7FFFF7FF;    // Result from Test 4
        i_op_b = 32'h00000001;
        i_alu_op = 4'b0000;
        expected = 32'h7FFFF800;  // 0x7FFFF7FF + 1
        check_with_instr("ADD: 0x7FFFF7FF + 0x1 = 0x7FFFF800", expected, 13);
        
        // =====================================================
        // SECTION 2: SUB Operations (ALU_OP = 4'b0001)
        // Instruction: SUB rd, rs1, rs2
        // Encoding: 0x40208633 = sub x12, x1, x2
        // =====================================================
        $display("--- Testing SUB Operations (ALU_OP = 4'b0001) ---");
        
        // Test 6: sub x12, x1, x2 => 0x64 - 0x32 = 0x32 (100 - 50 = 50)
        // Instruction: 0x40208633 = sub x12, x1, x2
        i_op_a = 32'h00000064;    // x1 = 100
        i_op_b = 32'h00000032;    // x2 = 50
        i_alu_op = 4'b0001;       // SUB
        expected = 32'h00000032;  // 50
        check_with_instr("SUB: sub x12, x1, x2 => 0x64 - 0x32 = 0x32", expected, 14);
        
        // Test 7: sub x13, x2, x1 => 0x32 - 0x64 = 0xFFFFFFCE (50 - 100 = -50)
        // Instruction: 0x401106B3 = sub x13, x2, x1
        i_op_a = 32'h00000032;    // x2 = 50
        i_op_b = 32'h00000064;    // x1 = 100
        i_alu_op = 4'b0001;
        expected = 32'hFFFFFFCE;  // -50
        check_with_instr("SUB: sub x13, x2, x1 => 0x32 - 0x64 = 0xFFFFFFCE", expected, 15);
        
        // Test 8: sub x14, x1, x3 => 0x64 - 0xFFFFFFE2 = 0x82 (100 - (-30) = 130)
        // Instruction: 0x40308733 = sub x14, x1, x3
        i_op_a = 32'h00000064;    // x1 = 100
        i_op_b = 32'hFFFFFFE2;    // x3 = -30
        i_alu_op = 4'b0001;
        expected = 32'h00000082;  // 130
        check_with_instr("SUB: sub x14, x1, x3 => 0x64 - 0xFFFFFFE2 = 0x82", expected, 16);
        
        // =====================================================
        // SECTION 3: SLL/SLLI - Shift Left Logical (ALU_OP = 4'b0010)
        // Instruction: SLL rd, rs1, rs2 hoặc SLLI rd, rs1, shamt
        // Encoding: 0x00F717B3 = sll a5, a4, a5
        // =====================================================
        $display("--- Testing SLL/SLLI Operations (ALU_OP = 4'b0010) ---");
        
        // Test 9: sll x16, x1, x15 => 0x64 << 5 = 0xC80 (100 << 5 = 3200)
        // Instruction: 0x00F09833 = sll x16, x1, x15
        i_op_a = 32'h00000064;    // x1 = 100
        i_op_b = 32'h00000005;    // Shift amount = 5
        i_alu_op = 4'b0010;       // SLL
        expected = 32'h00000C80;  // 3200
        check_with_instr("SLL: sll x16, x1, x15 => 0x64 << 5 = 0xC80", expected, 18);
        
        // Test 10: slli x17, x1, 3 => 0x64 << 3 = 0x320 (100 << 3 = 800)
        // Instruction: 0x00309893 = slli x17, x1, 3
        i_op_a = 32'h00000064;    // x1 = 100
        i_op_b = 32'h00000003;    // Shift amount = 3
        i_alu_op = 4'b0010;
        expected = 32'h00000320;  // 800
        check_with_instr("SLL: slli x17, x1, 3 => 0x64 << 3 = 0x320", expected, 19);
        
        // Test 11: slli x18, x4, 16 => 0xF << 16 = 0xF0000 (15 << 16)
        // Instruction: 0x01021913 = slli x18, x4, 16
        i_op_a = 32'h0000000F;    // x4 = 15
        i_op_b = 32'h00000010;    // Shift amount = 16
        i_alu_op = 4'b0010;
        expected = 32'h000F0000;
        check_with_instr("SLL: slli x18, x4, 16 => 0xF << 16 = 0xF0000", expected, 20);
        
        // Test 12: Barrel shifter stage 1 - slli x19, x1, 1
        // Instruction: 0x00109993 = slli x19, x1, 1
        i_op_a = 32'h00000064;    // x1 = 100
        i_op_b = 32'h00000001;    // Shift by 1
        i_alu_op = 4'b0010;
        expected = 32'h000000C8;  // 200
        check_with_instr("SLL: slli x19, x1, 1 => 0x64 << 1 = 0xC8 (barrel stage 1)", expected, 21);
        
        // Test 13: Barrel shifter stage 2 - slli x20, x1, 2
        // Instruction: 0x00209A13 = slli x20, x1, 2
        i_op_a = 32'h00000064;
        i_op_b = 32'h00000002;    // Shift by 2
        i_alu_op = 4'b0010;
        expected = 32'h00000190;  // 400
        check_with_instr("SLL: slli x20, x1, 2 => 0x64 << 2 = 0x190 (barrel stage 2)", expected, 22);
        
        // Test 14: Barrel shifter stage 3 - slli x21, x1, 4
        // Instruction: 0x00409A93 = slli x21, x1, 4
        i_op_a = 32'h00000064;
        i_op_b = 32'h00000004;    // Shift by 4
        i_alu_op = 4'b0010;
        expected = 32'h00000640;  // 1600
        check_with_instr("SLL: slli x21, x1, 4 => 0x64 << 4 = 0x640 (barrel stage 3)", expected, 23);
        
        // Test 15: Barrel shifter stage 4 - slli x22, x1, 8
        // Instruction: 0x00809B13 = slli x22, x1, 8
        i_op_a = 32'h00000064;
        i_op_b = 32'h00000008;    // Shift by 8
        i_alu_op = 4'b0010;
        expected = 32'h00006400;  // 25600
        check_with_instr("SLL: slli x22, x1, 8 => 0x64 << 8 = 0x6400 (barrel stage 4)", expected, 24);
        
        // Test 16: Barrel shifter stage 5 - slli x23, x1, 16
        // Instruction: 0x01009B93 = slli x23, x1, 16
        i_op_a = 32'h00000064;
        i_op_b = 32'h00000010;    // Shift by 16
        i_alu_op = 4'b0010;
        expected = 32'h00640000;  // 6553600
        check_with_instr("SLL: slli x23, x1, 16 => 0x64 << 16 = 0x640000 (barrel stage 5)", expected, 25);
        
        // =====================================================
        // SECTION 4: SLT/SLTI - Set Less Than Signed (ALU_OP = 4'b0011)
        // Instruction: SLT rd, rs1, rs2
        // Encoding: 0x00F757B3 = slt a5, a4, a5
        // =====================================================
        $display("--- Testing SLT/SLTI Operations (ALU_OP = 4'b0011) ---");
        
        // Test 17: slt x24, x2, x1 => (0x32 < 0x64) = 1 signed
        // Instruction: 0x00112C33 = slt x24, x2, x1
        i_op_a = 32'h00000032;    // x2 = 50
        i_op_b = 32'h00000064;    // x1 = 100
        i_alu_op = 4'b0011;       // SLT
        expected = 32'h00000001;
        check_with_instr("SLT: slt x24, x2, x1 => (0x32 < 0x64) = 1 (signed)", expected, 26);
        
        // Test 18: slt x25, x1, x2 => (0x64 < 0x32) = 0 signed
        // Instruction: 0x0020ACB3 = slt x25, x1, x2
        i_op_a = 32'h00000064;    // x1 = 100
        i_op_b = 32'h00000032;    // x2 = 50
        i_alu_op = 4'b0011;
        expected = 32'h00000000;
        check_with_instr("SLT: slt x25, x1, x2 => (0x64 < 0x32) = 0 (signed)", expected, 27);
        
        // Test 19: slt x26, x3, x2 => (0xFFFFFFE2 < 0x32) = 1 signed (-30 < 50)
        // Instruction: 0x0021AD33 = slt x26, x3, x2
        i_op_a = 32'hFFFFFFE2;    // x3 = -30
        i_op_b = 32'h00000032;    // x2 = 50
        i_alu_op = 4'b0011;
        expected = 32'h00000001;
        check_with_instr("SLT: slt x26, x3, x2 => (0xFFFFFFE2 < 0x32) = 1 (signed)", expected, 28);
        
        // Test 20: slti x27, x1, 200 => (0x64 < 0xC8) = 1 (100 < 200)
        // Instruction: 0x0C80AD93 = slti x27, x1, 200
        i_op_a = 32'h00000064;    // x1 = 100
        i_op_b = 32'h000000C8;    // Immediate = 200
        i_alu_op = 4'b0011;
        expected = 32'h00000001;
        check_with_instr("SLT: slti x27, x1, 200 => (0x64 < 0xC8) = 1", expected, 29);
        
        // Test 21: slt x30, x29, x3 => (0xFFFFFFF6 < 0xFFFFFFE2) = 0 (-10 < -30)
        // Instruction: 0x003EAF33 = slt x30, x29, x3
        i_op_a = 32'hFFFFFFF6;    // x29 = -10
        i_op_b = 32'hFFFFFFE2;    // x3 = -30
        i_alu_op = 4'b0011;
        expected = 32'h00000000;
        check_with_instr("SLT: slt x30, x29, x3 => (0xFFFFFFF6 < 0xFFFFFFE2) = 0 (signed)", expected, 31);
        
        // Test 22: slt x31, x3, x29 => (0xFFFFFFE2 < 0xFFFFFFF6) = 1 (-30 < -10)
        // Instruction: 0x01D1AFB3 = slt x31, x3, x29
        i_op_a = 32'hFFFFFFE2;    // x3 = -30
        i_op_b = 32'hFFFFFFF6;    // x29 = -10
        i_alu_op = 4'b0011;
        expected = 32'h00000001;
        check_with_instr("SLT: slt x31, x3, x29 => (0xFFFFFFE2 < 0xFFFFFFF6) = 1 (signed)", expected, 32);
        
        // =====================================================
        // SECTION 5: SLTU/SLTIU - Set Less Than Unsigned (ALU_OP = 4'b0100)
        // Instruction: SLTU rd, rs1, rs2
        // =====================================================
        $display("--- Testing SLTU/SLTIU Operations (ALU_OP = 4'b0100) ---");
        
        // Test 23: sltu x7, x2, x1 => (0x32 < 0x64) = 1 unsigned
        // Instruction: 0x001133B3 = sltu x7, x2, x1
        i_op_a = 32'h00000032;    // x2 = 50
        i_op_b = 32'h00000064;    // x1 = 100
        i_alu_op = 4'b0100;       // SLTU
        expected = 32'h00000001;
        check_with_instr("SLTU: sltu x7, x2, x1 => (0x32 < 0x64) = 1 (unsigned)", expected, 33);
        
        // Test 24: sltu x8, x3, x2 => (0xFFFFFFE2 < 0x32) = 0 unsigned (4294967266 > 50)
        // Instruction: 0x0021B433 = sltu x8, x3, x2
        i_op_a = 32'hFFFFFFE2;    // x3 = -30 as unsigned = 4294967266
        i_op_b = 32'h00000032;    // x2 = 50
        i_alu_op = 4'b0100;
        expected = 32'h00000000;
        check_with_instr("SLTU: sltu x8, x3, x2 => (0xFFFFFFE2 < 0x32) = 0 (unsigned)", expected, 34);
        
        // Test 25: sltiu x9, x1, 200 => (0x64 < 0xC8) = 1 unsigned
        // Instruction: 0x0C80B493 = sltiu x9, x1, 200
        i_op_a = 32'h00000064;    // x1 = 100
        i_op_b = 32'h000000C8;    // Immediate = 200
        i_alu_op = 4'b0100;
        expected = 32'h00000001;
        check_with_instr("SLTU: sltiu x9, x1, 200 => (0x64 < 0xC8) = 1 (unsigned)", expected, 35);
        
        // =====================================================
        // SECTION 6: XOR/XORI - XOR Operations (ALU_OP = 4'b0101)
        // Instruction: XOR rd, rs1, rs2
        // Encoding: 0x00F747B3 = xor a5, a4, a5
        // =====================================================
        $display("--- Testing XOR/XORI Operations (ALU_OP = 4'b0101) ---");
        
        // Test 26: xor x11, x1, x2 => 0x64 ^ 0x32 = 0x56
        // 0110_0100 ^ 0011_0010 = 0101_0110
        // Instruction: 0x0020C5B3 = xor x11, x1, x2
        i_op_a = 32'h00000064;    // x1 = 100 = 0x64
        i_op_b = 32'h00000032;    // x2 = 50 = 0x32
        i_alu_op = 4'b0101;       // XOR
        expected = 32'h00000056;  // 0x56 = 86
        check_with_instr("XOR: xor x11, x1, x2 => 0x64 ^ 0x32 = 0x56", expected, 36);
        
        // Test 27: xori x12, x1, 0xFF => 0x64 ^ 0xFF = 0x9B
        // Instruction: 0x0FF0C613 = xori x12, x1, 0xFF
        i_op_a = 32'h00000064;    // x1 = 100
        i_op_b = 32'h000000FF;    // Immediate = 0xFF
        i_alu_op = 4'b0101;
        expected = 32'h0000009B;  // 0x9B = 155
        check_with_instr("XOR: xori x12, x1, 0xFF => 0x64 ^ 0xFF = 0x9B", expected, 37);
        
        // Test 28: xor x13, x5, x6 => 0x12345678 ^ 0xABCDDEDD = 0xB9F988A5
        // Instruction: 0x0062C6B3 = xor x13, x5, x6
        i_op_a = 32'h12345678;    // x5
        i_op_b = 32'hABCDDEDD;    // x6
        i_alu_op = 4'b0101;
        expected = 32'hB9F988A5;
        check_with_instr("XOR: xor x13, x5, x6 => 0x12345678 ^ 0xABCDDEDD = 0xB9F988A5", expected, 38);
        
        // Test 29: xor x14, x1, x1 => Self-XOR = 0
        // Instruction: 0x0010C733 = xor x14, x1, x1
        i_op_a = 32'h00000064;
        i_op_b = 32'h00000064;
        i_alu_op = 4'b0101;
        expected = 32'h00000000;
        check_with_instr("XOR: xor x14, x1, x1 => Self-XOR = 0x00000000", expected, 39);
        
        // =====================================================
        // SECTION 7: SRL/SRLI - Shift Right Logical (ALU_OP = 4'b0110)
        // Instruction: SRL rd, rs1, rs2
        // Encoding: 0x00F757B3 = srl a5, a4, a5
        // =====================================================
        $display("--- Testing SRL/SRLI Operations (ALU_OP = 4'b0110) ---");
        
        // Test 30: srl x17, x1, x16 => 0x64 >> 4 = 0x6 (100 >> 4 = 6)
        // Instruction: 0x0100D8B3 = srl x17, x1, x16
        i_op_a = 32'h00000064;    // x1 = 100
        i_op_b = 32'h00000004;    // Shift amount = 4
        i_alu_op = 4'b0110;       // SRL
        expected = 32'h00000006;  // 6
        check_with_instr("SRL: srl x17, x1, x16 => 0x64 >> 4 = 0x6", expected, 41);
        
        // Test 31: srli x18, x5, 12 => 0x12345678 >> 12 = 0x00012345
        // Instruction: 0x00C2D913 = srli x18, x5, 12
        i_op_a = 32'h12345678;    // x5
        i_op_b = 32'h0000000C;    // Shift amount = 12
        i_alu_op = 4'b0110;
        expected = 32'h00012345;
        check_with_instr("SRL: srli x18, x5, 12 => 0x12345678 >> 12 = 0x00012345", expected, 42);
        
        // Test 32: srli x19, x6, 8 => 0xABCDDEDD >> 8 = 0x00ABCDDE
        // Instruction: 0x00835993 = srli x19, x6, 8
        i_op_a = 32'hABCDDEDD;    // x6
        i_op_b = 32'h00000008;    // Shift amount = 8
        i_alu_op = 4'b0110;
        expected = 32'h00ABCDDE;
        check_with_instr("SRL: srli x19, x6, 8 => 0xABCDDEDD >> 8 = 0x00ABCDDE", expected, 43);
        
        // Test 33: srli x20, x5, 1 => Barrel stage 1
        // Instruction: 0x0012DA13 = srli x20, x5, 1
        i_op_a = 32'h12345678;
        i_op_b = 32'h00000001;
        i_alu_op = 4'b0110;
        expected = 32'h091A2B3C;
        check_with_instr("SRL: srli x20, x5, 1 => 0x12345678 >> 1 = 0x091A2B3C (barrel stage 1)", expected, 44);
        
        // Test 34: srli x21, x5, 2 => Barrel stage 2
        // Instruction: 0x0022DA93 = srli x21, x5, 2
        i_op_a = 32'h12345678;
        i_op_b = 32'h00000002;
        i_alu_op = 4'b0110;
        expected = 32'h048D159E;
        check_with_instr("SRL: srli x21, x5, 2 => 0x12345678 >> 2 = 0x048D159E (barrel stage 2)", expected, 45);
        
        // =====================================================
        // SECTION 8: SRA/SRAI - Shift Right Arithmetic (ALU_OP = 4'b0111)
        // Instruction: SRA rd, rs1, rs2
        // Encoding: 0x40F757B3 = sra a5, a4, a5
        // =====================================================
        $display("--- Testing SRA/SRAI Operations (ALU_OP = 4'b0111) ---");
        
        // Test 35: sra x25, x3, x16 => 0xFFFFFFE2 >> 4 = 0xFFFFFFFE (sign extend)
        // -30 >> 4 = -2
        // Instruction: 0x4101DCB3 = sra x25, x3, x16
        i_op_a = 32'hFFFFFFE2;    // x3 = -30
        i_op_b = 32'h00000004;    // Shift amount = 4
        i_alu_op = 4'b0111;       // SRA
        expected = 32'hFFFFFFFE;  // -2
        check_with_instr("SRA: sra x25, x3, x16 => 0xFFFFFFE2 >> 4 = 0xFFFFFFFE (sign extend)", expected, 46);
        
        // Test 36: srai x26, x3, 4 => 0xFFFFFFE2 >> 4 = 0xFFFFFFFE
        // Instruction: 0x4041DD13 = srai x26, x3, 4
        i_op_a = 32'hFFFFFFE2;    // x3 = -30
        i_op_b = 32'h00000004;
        i_alu_op = 4'b0111;
        expected = 32'hFFFFFFFE;
        check_with_instr("SRA: srai x26, x3, 4 => 0xFFFFFFE2 >> 4 = 0xFFFFFFFE", expected, 47);
        
        // Test 37: srai x27, x6, 8 => 0xABCDDEDD >> 8 = 0xFFABCDDE (sign extend)
        // Instruction: 0x40835D93 = srai x27, x6, 8
        i_op_a = 32'hABCDDEDD;    // x6 (MSB = 1, negative)
        i_op_b = 32'h00000008;
        i_alu_op = 4'b0111;
        expected = 32'hFFABCDDE;  // Sign extended
        check_with_instr("SRA: srai x27, x6, 8 => 0xABCDDEDD >> 8 = 0xFFABCDDE (sign extend)", expected, 48);
        
        // Test 38: Compare SRL vs SRA - srli x28, x3, 4 (logical - zero fill)
        // Instruction: 0x0041DE13 = srli x28, x3, 4
        i_op_a = 32'hFFFFFFE2;    // x3 = -30
        i_op_b = 32'h00000004;
        i_alu_op = 4'b0110;       // SRL (zero fill)
        expected = 32'h0FFFFFFE;
        check_with_instr("SRL vs SRA: srli x28, x3, 4 => 0xFFFFFFE2 >> 4 (zero fill) = 0x0FFFFFFE", expected, 49);
        
        // Test 39: srai x29, x3, 4 (arithmetic - sign fill)
        // Instruction: 0x4041DE93 = srai x29, x3, 4
        i_op_a = 32'hFFFFFFE2;
        i_op_b = 32'h00000004;
        i_alu_op = 4'b0111;       // SRA (sign fill)
        expected = 32'hFFFFFFFE;
        check_with_instr("SRL vs SRA: srai x29, x3, 4 => 0xFFFFFFE2 >> 4 (sign fill) = 0xFFFFFFFE", expected, 50);
        
        // =====================================================
        // SECTION 9: OR/ORI - OR Operations (ALU_OP = 4'b1000)
        // Instruction: OR rd, rs1, rs2
        // Encoding: 0x00F767B3 = or a5, a4, a5
        // =====================================================
        $display("--- Testing OR/ORI Operations (ALU_OP = 4'b1000) ---");
        
        // Test 40: or x30, x1, x2 => 0x64 | 0x32 = 0x76
        // 0110_0100 | 0011_0010 = 0111_0110
        // Instruction: 0x0020EF33 = or x30, x1, x2
        i_op_a = 32'h00000064;    // x1 = 100 = 0x64
        i_op_b = 32'h00000032;    // x2 = 50 = 0x32
        i_alu_op = 4'b1000;       // OR
        expected = 32'h00000076;  // 0x76 = 118
        check_with_instr("OR: or x30, x1, x2 => 0x64 | 0x32 = 0x76", expected, 51);
        
        // Test 41: ori x31, x1, 0xFF => 0x64 | 0xFF = 0xFF
        // Instruction: 0x0FF0EF93 = ori x31, x1, 0xFF
        i_op_a = 32'h00000064;    // x1 = 100
        i_op_b = 32'h000000FF;    // Immediate = 0xFF
        i_alu_op = 4'b1000;
        expected = 32'h000000FF;
        check_with_instr("OR: ori x31, x1, 0xFF => 0x64 | 0xFF = 0xFF", expected, 52);
        
        // Test 42: or x7, x5, x6 => 0x12345678 | 0xABCDDEDD = 0xBBFDDEFD
        // Instruction: 0x0062E3B3 = or x7, x5, x6
        // Calculation: 0x12345678 | 0xABCDDEDD = 0xBBFDDEFD (NOT 0xBBFDFEFD!)
        i_op_a = 32'h12345678;    // x5
        i_op_b = 32'hABCDDEDD;    // x6
        i_alu_op = 4'b1000;
        expected = 32'hBBFDDEFD;  // Fixed: Correct OR result
        check_with_instr("OR: or x7, x5, x6 => 0x12345678 | 0xABCDDEDD = 0xBBFDDEFD", expected, 53);
        
        // Test 43: or x9, x1, x1 => Self-OR
        // Instruction: 0x0010E4B3 = or x9, x1, x1
        i_op_a = 32'h00000064;
        i_op_b = 32'h00000064;
        i_alu_op = 4'b1000;
        expected = 32'h00000064;
        check_with_instr("OR: or x9, x1, x1 => Self-OR = 0x64", expected, 54);
        
        // =====================================================
        // SECTION 10: AND/ANDI - AND Operations (ALU_OP = 4'b1001)
        // Instruction: AND rd, rs1, rs2
        // Encoding: 0x00F777B3 = and a5, a4, a5
        // =====================================================
        $display("--- Testing AND/ANDI Operations (ALU_OP = 4'b1001) ---");
        
        // Test 44: and x10, x1, x2 => 0x64 & 0x32 = 0x20
        // 0110_0100 & 0011_0010 = 0010_0000
        // Instruction: 0x0020F533 = and x10, x1, x2
        i_op_a = 32'h00000064;    // x1 = 100 = 0x64
        i_op_b = 32'h00000032;    // x2 = 50 = 0x32
        i_alu_op = 4'b1001;       // AND
        expected = 32'h00000020;  // 0x20 = 32
        check_with_instr("AND: and x10, x1, x2 => 0x64 & 0x32 = 0x20", expected, 55);
        
        // Test 45: andi x11, x1, 0x0F => 0x64 & 0x0F = 0x04 (bit mask)
        // Instruction: 0x00F0F593 = andi x11, x1, 0x0F
        i_op_a = 32'h00000064;    // x1 = 100
        i_op_b = 32'h0000000F;    // Immediate = 0x0F
        i_alu_op = 4'b1001;
        expected = 32'h00000004;  // 0x04 = 4
        check_with_instr("AND: andi x11, x1, 0x0F => 0x64 & 0x0F = 0x04 (bit mask)", expected, 56);
        
        // Test 46: and x12, x5, x6 => 0x12345678 & 0xABCDDEDD = 0x02045658
        // Instruction: 0x0062F633 = and x12, x5, x6
        i_op_a = 32'h12345678;    // x5
        i_op_b = 32'hABCDDEDD;    // x6
        i_alu_op = 4'b1001;
        expected = 32'h02045658;
        check_with_instr("AND: and x12, x5, x6 => 0x12345678 & 0xABCDDEDD = 0x02045658", expected, 57);
        
        // Test 47: and x13, x1, x0 => AND with zero
        // Instruction: 0x0000F6B3 = and x13, x1, x0
        i_op_a = 32'h00000064;
        i_op_b = 32'h00000000;
        i_alu_op = 4'b1001;
        expected = 32'h00000000;
        check_with_instr("AND: and x13, x1, x0 => 0x64 & 0x0 = 0x0", expected, 58);
        
        // =====================================================
        // SECTION 11: LUI - Load Upper Immediate (ALU_OP = 4'b1111)
        // Instruction: LUI rd, imm
        // Encoding: 0xDEADB7B7 = lui a5, 0xDEADB
        // =====================================================
        $display("--- Testing LUI Operation (ALU_OP = 4'b1111) ---");
        
        // Test 48: lui x15, 0xDEADB => 0xDEADB000
        // Instruction: 0xDEADB7B7 = lui x15, 0xDEADB
        i_op_a = 32'h00000000;    // LUI không dùng op_a
        i_op_b = 32'hDEADB000;    // Upper 20 bits
        i_alu_op = 4'b1111;       // LUI
        expected = 32'hDEADB000;
        check_with_instr("LUI: lui x15, 0xDEADB => 0xDEADB000", expected, 59);
        
        // Test 49: lui x16, 0x12345 => 0x12345000
        // Instruction: 0x12345837 = lui x16, 0x12345
        i_op_a = 32'h00000000;
        i_op_b = 32'h12345000;
        i_alu_op = 4'b1111;
        expected = 32'h12345000;
        check_with_instr("LUI: lui x16, 0x12345 => 0x12345000", expected, 60);
        
        // Test 50: lui x17, 0xFFFFF => 0xFFFFF000 (negative)
        // Instruction: 0xFFFFF8B7 = lui x17, 0xFFFFF
        i_op_a = 32'h00000000;
        i_op_b = 32'hFFFFF000;
        i_alu_op = 4'b1111;
        expected = 32'hFFFFF000;
        check_with_instr("LUI: lui x17, 0xFFFFF => 0xFFFFF000 (negative)", expected, 61);
        
        // =====================================================
        // SECTION 12: Edge Cases
        // =====================================================
        $display("--- Testing Edge Cases ---");
        
        // Test 51: ADD with zero
        // Instruction: 0x00008933 = add x18, x1, x0
        i_op_a = 32'h00000064;    // x1 = 100
        i_op_b = 32'h00000000;
        i_alu_op = 4'b0000;
        expected = 32'h00000064;
        check_with_instr("Edge: ADD with zero => 0x64 + 0x0 = 0x64", expected, 62);
        
        // Test 52: SUB same values
        // Instruction: 0x401089B3 = sub x19, x1, x1
        i_op_a = 32'h00000064;
        i_op_b = 32'h00000064;
        i_alu_op = 4'b0001;
        expected = 32'h00000000;
        check_with_instr("Edge: SUB same values => 0x64 - 0x64 = 0x0", expected, 63);
        
        // Test 53: SLL by 0
        // Instruction: 0x00009A33 = sll x20, x1, x0
        i_op_a = 32'h00000064;
        i_op_b = 32'h00000000;
        i_alu_op = 4'b0010;
        expected = 32'h00000064;
        check_with_instr("Edge: SLL by 0 => 0x64 << 0 = 0x64", expected, 64);
        
        // Test 54: SRL by 0
        // Instruction: 0x0000DAB3 = srl x21, x1, x0
        i_op_a = 32'h00000064;
        i_op_b = 32'h00000000;
        i_alu_op = 4'b0110;
        expected = 32'h00000064;
        check_with_instr("Edge: SRL by 0 => 0x64 >> 0 = 0x64", expected, 65);
        
        // Test 55: XOR with all ones (NOT operation)
        // Instruction: 0x0162CBB3 = xor x23, x5, x22
        i_op_a = 32'h12345678;
        i_op_b = 32'hFFFFFFFF;
        i_alu_op = 4'b0101;
        expected = 32'hEDCBA987;
        check_with_instr("Edge: XOR with all ones => 0x12345678 ^ 0xFFFFFFFF = 0xEDCBA987 (NOT)", expected, 67);
        
        // =====================================================
        // Summary - Tổng kết kết quả
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
