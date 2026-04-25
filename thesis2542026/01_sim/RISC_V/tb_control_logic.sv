`timescale 1ns / 1ps

module tb_control_logic;

    // ========================================
    // Signals
    // ========================================
    logic [31:0] i_instr;
    logic i_br_equal;
    logic i_br_less;
    
    // Outputs
    logic [3:0] o_alu_op;
    logic [2:0] o_imm_sel;
    logic [3:0] o_byte_num;
    logic o_insn_vld;
    logic [1:0] o_wb_sel;
    logic o_opa_sel;
    logic o_opb_sel;
    logic o_pc_sel;
    logic o_rd_wren;
    logic o_lsu_wren;
    logic o_br_un;
    
    // Expected values
    logic [3:0] exp_alu_op;
    logic [2:0] exp_imm_sel;
    logic [3:0] exp_byte_num;
    logic exp_insn_vld;
    logic [1:0] exp_wb_sel;
    logic exp_opa_sel;
    logic exp_opb_sel;
    logic exp_pc_sel;
    logic exp_rd_wren;
    logic exp_lsu_wren;
    logic exp_br_un;
    
    // Test counters
    int test_num = 0;
    int pass_count = 0;
    int fail_count = 0;
    int failed_tests[1000];  // Array to store failed test numbers
    int fail_idx = 0;        // Index for failed_tests array
    
    // Test case storage for table display
    typedef struct {
        int test_id;
        string test_name;
        logic [31:0] instr;
        string result;
    } test_case_t;
    
    test_case_t test_cases[100];
    int test_case_count = 0;
    
    // ========================================
    // Instantiate DUT
    // ========================================
    control_logic dut (
        .i_instr(i_instr),
        .i_br_equal(i_br_equal),
        .i_br_less(i_br_less),
        .o_alu_op(o_alu_op),
        .o_imm_sel(o_imm_sel),
        .o_byte_num(o_byte_num),
        .o_insn_vld(o_insn_vld),
        .o_wb_sel(o_wb_sel),
        .o_opa_sel(o_opa_sel),
        .o_opb_sel(o_opb_sel),
        .o_pc_sel(o_pc_sel),
        .o_rd_wren(o_rd_wren),
        .o_lsu_wren(o_lsu_wren),
        .o_br_un(o_br_un)
    );
    
    // ========================================
    // Helper Task: Check Results
    // ========================================
    task check_result(input string test_name);
        test_num++;
        
        if (o_alu_op === exp_alu_op &&
            o_imm_sel === exp_imm_sel &&
            o_byte_num === exp_byte_num &&
            o_insn_vld === exp_insn_vld &&
            o_wb_sel === exp_wb_sel &&
            o_opa_sel === exp_opa_sel &&
            o_opb_sel === exp_opb_sel &&
            o_pc_sel === exp_pc_sel &&
            o_rd_wren === exp_rd_wren &&
            o_lsu_wren === exp_lsu_wren &&
            o_br_un === exp_br_un) begin
            
            $display("[%0t ns] [PASS] Test %0d: %s", $time, test_num, test_name);
            
            // Store test case for table
            test_cases[test_case_count].test_id = test_num;
            test_cases[test_case_count].test_name = test_name;
            test_cases[test_case_count].instr = i_instr;
            test_cases[test_case_count].result = "PASS";
            test_case_count++;
            
            pass_count++;
        end else begin
            $display("[%0t ns] [FAIL] Test %0d: %s", $time, test_num, test_name);
            $display("       Instruction: 0x%08h", i_instr);
            
            if (o_alu_op !== exp_alu_op)
                $display("       o_alu_op:    Expected 4'b%04b, Got 4'b%04b", exp_alu_op, o_alu_op);
            if (o_imm_sel !== exp_imm_sel)
                $display("       o_imm_sel:   Expected 3'b%03b, Got 3'b%03b", exp_imm_sel, o_imm_sel);
            if (o_byte_num !== exp_byte_num)
                $display("       o_byte_num:  Expected 4'b%04b, Got 4'b%04b", exp_byte_num, o_byte_num);
            if (o_insn_vld !== exp_insn_vld)
                $display("       o_insn_vld:  Expected %0b, Got %0b", exp_insn_vld, o_insn_vld);
            if (o_wb_sel !== exp_wb_sel)
                $display("       o_wb_sel:    Expected 2'b%02b, Got 2'b%02b", exp_wb_sel, o_wb_sel);
            if (o_opa_sel !== exp_opa_sel)
                $display("       o_opa_sel:   Expected %0b, Got %0b", exp_opa_sel, o_opa_sel);
            if (o_opb_sel !== exp_opb_sel)
                $display("       o_opb_sel:   Expected %0b, Got %0b", exp_opb_sel, o_opb_sel);
            if (o_pc_sel !== exp_pc_sel)
                $display("       o_pc_sel:    Expected %0b, Got %0b", exp_pc_sel, o_pc_sel);
            if (o_rd_wren !== exp_rd_wren)
                $display("       o_rd_wren:   Expected %0b, Got %0b", exp_rd_wren, o_rd_wren);
            if (o_lsu_wren !== exp_lsu_wren)
                $display("       o_lsu_wren:  Expected %0b, Got %0b", exp_lsu_wren, o_lsu_wren);
            if (o_br_un !== exp_br_un)
                $display("       o_br_un:     Expected %0b, Got %0b", exp_br_un, o_br_un);
            
            // Store test case for table
            test_cases[test_case_count].test_id = test_num;
            test_cases[test_case_count].test_name = test_name;
            test_cases[test_case_count].instr = i_instr;
            test_cases[test_case_count].result = "FAIL";
            test_case_count++;
            
            failed_tests[fail_idx] = test_num;  // Store failed test number
            fail_idx++;
            fail_count++;
        end
    endtask
    
    // ========================================
    // Helper Task: Set Expected Values
    // ========================================
    task set_expected(
        input [3:0] alu_op,
        input [2:0] imm_sel,
        input [3:0] byte_num,
        input insn_vld,
        input [1:0] wb_sel,
        input opa_sel,
        input opb_sel,
        input pc_sel,
        input rd_wren,
        input lsu_wren,
        input br_un
    );
        exp_alu_op = alu_op;
        exp_imm_sel = imm_sel;
        exp_byte_num = byte_num;
        exp_insn_vld = insn_vld;
        exp_wb_sel = wb_sel;
        exp_opa_sel = opa_sel;
        exp_opb_sel = opb_sel;
        exp_pc_sel = pc_sel;
        exp_rd_wren = rd_wren;
        exp_lsu_wren = lsu_wren;
        exp_br_un = br_un;
    endtask
    
    // ========================================
    // Test Sequence
    // ========================================
    initial begin
        $display("#############################################################");
        $display("#     Control Logic Comprehensive Verification Testbench    #");
        $display("#############################################################");
        $display("");
        
        // Initialize branch signals
        i_br_equal = 0;
        i_br_less = 0;
        
        // ========================================
        // R-TYPE INSTRUCTIONS
        // ========================================
        $display("##############################################################");
        $display("#  R-TYPE INSTRUCTIONS (Register-Register operations)         #");
        $display("##############################################################");
        
        // Test 1: ADD x1, x2, x3
        i_instr = 32'h003100B3;  // add x1, x2, x3
        set_expected(
            .alu_op(4'b0000),    // ADD
            .imm_sel(3'b000),    // Don't care
            .byte_num(4'b0000),  // Don't care
            .insn_vld(1'b1),     // Valid
            .wb_sel(2'b01),      // WB from ALU
            .opa_sel(1'b0),      // OpA = rs1
            .opb_sel(1'b0),      // OpB = rs2
            .pc_sel(1'b0),       // PC+4
            .rd_wren(1'b1),      // Write to rd
            .lsu_wren(1'b0),     // No memory write
            .br_un(1'b0)         // Don't care
        );
        #10; check_result("R-Type: ADD x1, x2, x3");
        
        // Test 2: SUB x4, x5, x6
        i_instr = 32'h406282B3;  // sub x5, x5, x6
        set_expected(4'b0001, 3'b000, 4'b0000, 1'b1, 2'b01, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0);
        #10; check_result("R-Type: SUB x5, x5, x6");
        
        // Test 3: SLL x1, x2, x3
        i_instr = 32'h003110B3;  // sll x1, x2, x3
        set_expected(4'b0010, 3'b000, 4'b0000, 1'b1, 2'b01, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0);
        #10; check_result("R-Type: SLL x1, x2, x3");
        
        // Test 4: SLT x1, x2, x3
        i_instr = 32'h003120B3;  // slt x1, x2, x3
        set_expected(4'b0011, 3'b000, 4'b0000, 1'b1, 2'b01, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0);
        #10; check_result("R-Type: SLT x1, x2, x3");
        
        // Test 5: SLTU x1, x2, x3
        i_instr = 32'h003130B3;  // sltu x1, x2, x3
        set_expected(4'b0100, 3'b000, 4'b0000, 1'b1, 2'b01, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0);
        #10; check_result("R-Type: SLTU x1, x2, x3");
        
        // Test 6: XOR x1, x2, x3
        i_instr = 32'h003140B3;  // xor x1, x2, x3
        set_expected(4'b0101, 3'b000, 4'b0000, 1'b1, 2'b01, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0);
        #10; check_result("R-Type: XOR x1, x2, x3");
        
        // Test 7: SRL x1, x2, x3
        i_instr = 32'h003150B3;  // srl x1, x2, x3
        set_expected(4'b0110, 3'b000, 4'b0000, 1'b1, 2'b01, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0);
        #10; check_result("R-Type: SRL x1, x2, x3");
        
        // Test 8: SRA x1, x2, x3
        i_instr = 32'h403150B3;  // sra x1, x2, x3
        set_expected(4'b0111, 3'b000, 4'b0000, 1'b1, 2'b01, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0);
        #10; check_result("R-Type: SRA x1, x2, x3");
        
        // Test 9: OR x1, x2, x3
        i_instr = 32'h003160B3;  // or x1, x2, x3
        set_expected(4'b1000, 3'b000, 4'b0000, 1'b1, 2'b01, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0);
        #10; check_result("R-Type: OR x1, x2, x3");
        
        // Test 10: AND x1, x2, x3
        i_instr = 32'h003170B3;  // and x1, x2, x3
        set_expected(4'b1001, 3'b000, 4'b0000, 1'b1, 2'b01, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0);
        #10; check_result("R-Type: AND x1, x2, x3");
        
        // ========================================
        // I-TYPE ARITHMETIC INSTRUCTIONS
        // ========================================
        $display("");
        $display("#############################################################");
        $display("##  I-TYPE ARITHMETIC (Register-Immediate operations)      ##");
        $display("#############################################################");
        
        // Test 11: ADDI x1, x2, 100
        i_instr = 32'h06410093;  // addi x1, x2, 100
        set_expected(4'b0000, 3'b000, 4'b0000, 1'b1, 2'b01, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0);
        #10; check_result("I-Type: ADDI x1, x2, 100");
        
        // Test 12: SLTI x1, x2, 42
        i_instr = 32'h02A12093;  // slti x1, x2, 42
        set_expected(4'b0011, 3'b000, 4'b0000, 1'b1, 2'b01, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0);
        #10; check_result("I-Type: SLTI x1, x2, 42");
        
        // Test 13: SLTIU x1, x2, 200
        i_instr = 32'h0C813093;  // sltiu x1, x2, 200
        set_expected(4'b0100, 3'b000, 4'b0000, 1'b1, 2'b01, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0);
        #10; check_result("I-Type: SLTIU x1, x2, 200");
        
        // Test 14: XORI x1, x2, 0xFF
        i_instr = 32'h0FF14093;  // xori x1, x2, 0xFF
        set_expected(4'b0101, 3'b000, 4'b0000, 1'b1, 2'b01, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0);
        #10; check_result("I-Type: XORI x1, x2, 0xFF");
        
        // Test 15: ORI x1, x2, 0x1F
        i_instr = 32'h01F16093;  // ori x1, x2, 0x1F
        set_expected(4'b1000, 3'b000, 4'b0000, 1'b1, 2'b01, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0);
        #10; check_result("I-Type: ORI x1, x2, 0x1F");
        
        // Test 16: ANDI x1, x2, 0x3F
        i_instr = 32'h03F17093;  // andi x1, x2, 0x3F
        set_expected(4'b1001, 3'b000, 4'b0000, 1'b1, 2'b01, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0);
        #10; check_result("I-Type: ANDI x1, x2, 0x3F");
        
        // Test 17: SLLI x1, x2, 5
        i_instr = 32'h00511093;  // slli x1, x2, 5
        set_expected(4'b0010, 3'b000, 4'b0000, 1'b1, 2'b01, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0);
        #10; check_result("I-Type: SLLI x1, x2, 5");
        
        // Test 18: SRLI x1, x2, 10
        i_instr = 32'h00A15093;  // srli x1, x2, 10
        set_expected(4'b0110, 3'b000, 4'b0000, 1'b1, 2'b01, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0);
        #10; check_result("I-Type: SRLI x1, x2, 10");
        
        // Test 19: SRAI x1, x2, 10
        i_instr = 32'h40A15093;  // srai x1, x2, 10
        set_expected(4'b0111, 3'b000, 4'b0000, 1'b1, 2'b01, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0);
        #10; check_result("I-Type: SRAI x1, x2, 10");
        
        // ========================================
        // I-TYPE LOAD INSTRUCTIONS
        // ========================================
        $display("");
        $display("#############################################################");
        $display("##  I-TYPE LOAD (Load from memory)                             ##");
        $display("#############################################################");
        
        // Test 20: LW x2, 100(x1)
        i_instr = 32'h0640A103;  // lw x2, 100(x1)
        set_expected(4'b0000, 3'b000, 4'b1111, 1'b1, 2'b10, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0);
        #10; check_result("I-Type: LW x2, 100(x1)");
        
        // Test 21: LH x3, 50(x2)
        i_instr = 32'h03211183;  // lh x3, 50(x2)
        set_expected(4'b0000, 3'b000, 4'b0011, 1'b1, 2'b10, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0);
        #10; check_result("I-Type: LH x3, 50(x2)");
        
        // Test 22: LB x4, 25(x3)
        i_instr = 32'h01918203;  // lb x4, 25(x3)
        set_expected(4'b0000, 3'b000, 4'b0001, 1'b1, 2'b10, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0);
        #10; check_result("I-Type: LB x4, 25(x3)");
        
        // Test 23: LBU x5, 255(x4)
        i_instr = 32'h0FF24283;  // lbu x5, 255(x4)
        set_expected(4'b0000, 3'b000, 4'b0100, 1'b1, 2'b10, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0);
        #10; check_result("I-Type: LBU x5, 255(x4)");
        
        // Test 24: LHU x6, 1024(x5)
        i_instr = 32'h4002D303;  // lhu x6, 1024(x5)
        set_expected(4'b0000, 3'b000, 4'b0101, 1'b1, 2'b10, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0);
        #10; check_result("I-Type: LHU x6, 1024(x5)");
        
        // ========================================
        // S-TYPE STORE INSTRUCTIONS
        // ========================================
        $display("");
        $display("#############################################################");
        $display("##  S-TYPE STORE (Store to memory)                             ##");
        $display("#############################################################");
        
        // Test 25: SW x5, 12(x2)
        i_instr = 32'h00512623;  // sw x5, 12(x2)
        set_expected(4'b0000, 3'b001, 4'b1111, 1'b1, 2'b00, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0);
        #10; check_result("S-Type: SW x5, 12(x2)");
        
        // Test 26: SH x3, -4(x1)
        i_instr = 32'hFE309E23;  // sh x3, -4(x1)
        set_expected(4'b0000, 3'b001, 4'b0011, 1'b1, 2'b00, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0);
        #10; check_result("S-Type: SH x3, -4(x1)");
        
        // Test 27: SB x7, 31(x4)
        i_instr = 32'h00720FA3;  // sb x7, 31(x4)
        set_expected(4'b0000, 3'b001, 4'b0001, 1'b1, 2'b00, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0);
        #10; check_result("S-Type: SB x7, 31(x4)");
        
        // ========================================
        // B-TYPE BRANCH INSTRUCTIONS
        // ========================================
        $display("");
        $display("#############################################################");
        $display("##  B-TYPE BRANCH (Conditional jumps)                          ##");
        $display("#############################################################");
        
        // Test 28: BEQ - Branch taken (equal)
        i_instr = 32'h00208463;  // beq x1, x2, 8
        i_br_equal = 1'b1;
        i_br_less = 1'b0;
        set_expected(4'b0000, 3'b010, 4'b0000, 1'b1, 2'b01, 1'b1, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0);
        #10; check_result("B-Type: BEQ taken (equal)");
        
        // Test 29: BEQ - Branch not taken (not equal)
        i_instr = 32'h00208463;  // beq x1, x2, 8
        i_br_equal = 1'b0;
        i_br_less = 1'b0;
        set_expected(4'b0000, 3'b010, 4'b0000, 1'b1, 2'b01, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0);
        #10; check_result("B-Type: BEQ not taken");
        
        // Test 30: BNE - Branch taken (not equal)
        i_instr = 32'h00419863;  // bne x3, x4, 16
        i_br_equal = 1'b0;
        i_br_less = 1'b0;
        set_expected(4'b0000, 3'b010, 4'b0000, 1'b1, 2'b01, 1'b1, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0);
        #10; check_result("B-Type: BNE taken (not equal)");
        
        // Test 31: BNE - Branch not taken (equal)
        i_instr = 32'h00419863;  // bne x3, x4, 16
        i_br_equal = 1'b1;
        i_br_less = 1'b0;
        set_expected(4'b0000, 3'b010, 4'b0000, 1'b1, 2'b01, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0);
        #10; check_result("B-Type: BNE not taken (equal)");
        
        // Test 32: BLT - Branch taken (less than, signed)
        i_instr = 32'h0262C063;  // blt x5, x6, 32
        i_br_equal = 1'b0;
        i_br_less = 1'b1;
        set_expected(4'b0000, 3'b010, 4'b0000, 1'b1, 2'b01, 1'b1, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0);
        #10; check_result("B-Type: BLT taken (less)");
        
        // Test 33: BLT - Branch not taken
        i_instr = 32'h0262C063;  // blt x5, x6, 32
        i_br_equal = 1'b0;
        i_br_less = 1'b0;
        set_expected(4'b0000, 3'b010, 4'b0000, 1'b1, 2'b01, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0);
        #10; check_result("B-Type: BLT not taken");
        
        // Test 34: BGE - Branch taken (greater or equal, signed)
        i_instr = 32'h0483D063;  // bge x7, x8, 64
        i_br_equal = 1'b1;
        i_br_less = 1'b0;
        set_expected(4'b0000, 3'b010, 4'b0000, 1'b1, 2'b01, 1'b1, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0);
        #10; check_result("B-Type: BGE taken (equal)");
        
        // Test 35: BGE - Branch taken (greater)
        i_instr = 32'h0483D063;  // bge x7, x8, 64
        i_br_equal = 1'b0;
        i_br_less = 1'b0;
        set_expected(4'b0000, 3'b010, 4'b0000, 1'b1, 2'b01, 1'b1, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0);
        #10; check_result("B-Type: BGE taken (greater)");
        
        // Test 36: BGE - Branch not taken (less)
        i_instr = 32'h0483D063;  // bge x7, x8, 64
        i_br_equal = 1'b0;
        i_br_less = 1'b1;
        set_expected(4'b0000, 3'b010, 4'b0000, 1'b1, 2'b01, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0);
        #10; check_result("B-Type: BGE not taken (less)");
        
        // Test 37: BLTU - Branch taken (less than, unsigned)
        i_instr = 32'h06A4E263;  // bltu x9, x10, 100
        i_br_equal = 1'b0;
        i_br_less = 1'b1;
        set_expected(4'b0000, 3'b010, 4'b0000, 1'b1, 2'b01, 1'b1, 1'b1, 1'b1, 1'b0, 1'b0, 1'b1);
        #10; check_result("B-Type: BLTU taken (unsigned)");
        
        // Test 38: BGEU - Branch taken (greater or equal, unsigned)
        i_instr = 32'h0CC5F463;  // bgeu x11, x12, 200
        i_br_equal = 1'b1;
        i_br_less = 1'b0;
        set_expected(4'b0000, 3'b010, 4'b0000, 1'b1, 2'b01, 1'b1, 1'b1, 1'b1, 1'b0, 1'b0, 1'b1);
        #10; check_result("B-Type: BGEU taken (unsigned)");
        
        // ========================================
        // U-TYPE INSTRUCTIONS
        // ========================================
        $display("");
        $display("#############################################################");
        $display("##  U-TYPE (Upper immediate)                                   ##");
        $display("#############################################################");
        
        // Test 39: LUI x10, 0x12345
        i_instr = 32'h12345537;  // lui x10, 0x12345
        set_expected(4'b1111, 3'b011, 4'b0000, 1'b1, 2'b01, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0);
        #10; check_result("U-Type: LUI x10, 0x12345");
        
        // Test 40: AUIPC x5, 0xABCDE
        i_instr = 32'hABCDE297;  // auipc x5, 0xABCDE
        set_expected(4'b0000, 3'b011, 4'b0000, 1'b1, 2'b01, 1'b1, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0);
        #10; check_result("U-Type: AUIPC x5, 0xABCDE");
        
        // ========================================
        // J-TYPE JAL INSTRUCTION
        // ========================================
        $display("");
        $display("#############################################################");
        $display("##  J-TYPE JAL (Jump and Link)                                 ##");
        $display("#############################################################");
        
        // Test 41: JAL x1, 100
        i_instr = 32'h064000EF;  // jal x1, 100
        set_expected(4'b0000, 3'b100, 4'b0000, 1'b1, 2'b00, 1'b1, 1'b1, 1'b1, 1'b1, 1'b0, 1'b0);
        #10; check_result("J-Type: JAL x1, 100");
        
        // ========================================
        // I-TYPE JALR INSTRUCTION
        // ========================================
        $display("");
        $display("#############################################################");
        $display("##  I-TYPE JALR (Jump and Link Register)                       ##");
        $display("#############################################################");
        
        // Test 42: JALR x1, 8(x2)
        i_instr = 32'h008100E7;  // jalr x1, 8(x2)
        set_expected(4'b0000, 3'b000, 4'b0000, 1'b1, 2'b00, 1'b0, 1'b1, 1'b1, 1'b1, 1'b0, 1'b0);
        #10; check_result("I-Type: JALR x1, 8(x2)");
        
        // ========================================
        // INVALID/DEFAULT INSTRUCTION
        // ========================================
        $display("");
        $display("#############################################################");
        $display("##  INVALID INSTRUCTIONS (Default case)                        ##");
        $display("#############################################################");
        
        // Test 43: Invalid opcode
        i_instr = 32'h00000000;  // All zeros
        set_expected(4'b0000, 3'b000, 4'b0000, 1'b0, 2'b00, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
        #10; check_result("Invalid: All zeros");
        
        // Test 44: Invalid opcode
        i_instr = 32'hFFFFFFFF;  // All ones
        set_expected(4'b0000, 3'b000, 4'b0000, 1'b0, 2'b00, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
        #10; check_result("Invalid: All ones");
        
        // Test 45: Invalid opcode
        i_instr = 32'h12345678;  // Random invalid
        set_expected(4'b0000, 3'b000, 4'b0000, 1'b0, 2'b00, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
        #10; check_result("Invalid: Random");
        
        // ========================================
        // TABLE SUMMARY FOR REPORT
        // ========================================
        $display("");
        $display("##############################################################");
        $display("##              TABLE SUMMARY FOR REPORT                     ##");
        $display("##############################################################");
        $display("");
        $display("# ====================================================================================================");
        $display("# Test | Instruction Type & Description                              | Instruction | Result       |");
        $display("# -----|----------------------------------------------------------------------|------------|--------------|");
        
        for (int i = 0; i < test_case_count; i++) begin
            $display("# %4d | %-68s | 0x%08h | %-12s |",
                     test_cases[i].test_id,
                     test_cases[i].test_name,
                     test_cases[i].instr,
                     test_cases[i].result);
        end
        
        $display("# ====================================================================================================");
        $display("");
        
        // ========================================
        // SUMMARY
        // ========================================
        $display("");
        $display("#############################################################");
        $display("##                    VERIFICATION SUMMARY                      ##");
        $display("#############################################################");
        $display("##  Total Tests:  %3d                                           ##", test_num);
        $display("##  Passed:       %3d                                           ##", pass_count);
        $display("##  Failed:       %3d                                           ##", fail_count);
        $display("#############################################################");
        
        if (fail_count == 0) begin
            $display("##                   ALL TESTS PASSED!                     ##");
        end else begin
            $display("##                   TESTS FAILED!                         ##");
            $display("##  Failed test numbers:                                   ##");
            for (int i = 0; i < fail_idx; i++) begin
                $display("##    - Test %0d", failed_tests[i]);
            end
        end

        $display("#############################################################");
        $display("");
        
        $finish;
    end

endmodule
