`timescale 1ns / 1ns

module single_cycle_tb;

    // Declare signals for top-level ports of singlecycle
    logic i_clk;
    logic i_reset;
    logic [31:0] i_io_sw;
    logic [31:0] o_io_ledr;
    logic [31:0] o_io_ledg;
    logic [31:0] o_io_lcd;
    logic [6:0] o_io_hex0, o_io_hex1, o_io_hex2, o_io_hex3;
    logic [6:0] o_io_hex4, o_io_hex5, o_io_hex6, o_io_hex7;
    logic [31:0] o_pc_debug;
    logic o_insn_vld;  // Missing signal!

    // Instantiate singlecycle
    single_cycle dut (
        .i_clk(i_clk),
        .i_reset(i_reset),
        .i_io_sw(i_io_sw),
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
        .o_io_hex7(o_io_hex7),
        .o_pc_debug(o_pc_debug),
        .o_insn_vld(o_insn_vld)  // Add missing port!
    );

    // Generate clock
    initial begin
        i_clk = 0;
        forever #5 i_clk = ~i_clk; // Clock period = 10ns
    end

    // Initial reset and setup
    initial begin
        i_reset = 0; // Start with reset asserted (active-low)
        i_io_sw = 32'd10;
        #15; // Wait for 15ns
        i_reset = 1; // Deassert reset (active-low)
    end

    // Display PC, Instruction, o_pc_sel, and register values on each clock cycle
    always @(posedge i_clk) begin
        if (i_reset) begin // Only display after reset is deasserted
            $display("=== Cycle at Time=%0t ===", $time);
            $display("PC = %h", o_pc_debug);
            $display("Instruction = %h, Opcode = %b, Funct3 = %b", dut.i_instr, dut.i_instr[6:0], dut.i_instr[14:12]);
            $display("o_insn_vld = %b (Instruction Valid)", o_insn_vld);
            $display("o_pc_sel = %b", dut.control_logic.o_pc_sel);
            $display("o_wb_sel = %b, o_wb_data = %h", dut.o_wb_sel, dut.o_wb_data);
            $display("o_alu_data = %h, o_alu_op = %h", dut.o_alu_data, dut.o_alu_op);
            $display("o_opa_sel = %b, o_opb_sel = %b", dut.o_opa_sel, dut.o_opb_sel);
            $display("i_op_a = %h, i_op_b = %h", dut.i_op_a, dut.i_op_b);
            $display("o_immgen = %h, o_imm_sel = %h", dut.o_immgen, dut.o_imm_sel);
            $display("i_br_equal = %b, i_br_less = %b, o_br_un = %b", dut.i_br_equal, dut.i_br_less, dut.o_br_un);
            $display("RegFile write enable (o_rd_wren) = %b", dut.o_rd_wren);
            $display("RegFile write address (rd) = %h", dut.i_instr[11:7]);
            $display("RegFile read addresses rs1=%h, rs2=%h", dut.i_instr[19:15], dut.i_instr[24:20]);
            $display("RegFile read data rs1_data=%h, rs2_data=%h", dut.o_rs1_data, dut.o_rs2_data);
            $display("LSU data (o_ld_data) = %h", dut.o_ld_data);
            $display("LSU address (i_lsu_addr) = %h, byte_num = %b, mem_i_bmask = %b", dut.lsu.i_lsu_addr, dut.lsu.i_byte_num, dut.lsu.mem.i_bmask);
            $display("LSU write enable (i_lsu_wren) = %b, mem enable = %b", dut.lsu.i_lsu_wren, dut.lsu.mem.i_wren);
            $display("LSU store data (i_st_data) = %h", dut.lsu.i_st_data);
            $display("Mem data  = %h", dut.lsu.mem.o_rdata);
            $display("RegFile write data (o_wb_data) = %h", dut.o_wb_data);
            $display("I/O: LEDR=%h, LEDG=%h, LCD=%h", o_io_ledr, o_io_ledg, o_io_lcd);
            $display("I/O: SW=%h", i_io_sw);
            $display("Registers:");
            for (int i = 0; i < 31;) begin
                $display("  x%0d = %h, x%0d = %h, x%0d = %h, x%0d = %h, x%0d = %h", 
                    i, dut.regfile.registers[i],
                    i+1, dut.regfile.registers[i+1],
                    i+2, dut.regfile.registers[i+2],
                    i+3, dut.regfile.registers[i+3],
                    i+4, dut.regfile.registers[i+4]);
                i = i + 5; // Increment by 5 to display next set of registers
            end
            $display("");
        end
    end

    // Run simulation for a certain time
    initial #5000 $finish;
endmodule