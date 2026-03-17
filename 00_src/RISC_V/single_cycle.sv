module single_cycle (
    input  logic         i_clk     ,
    input  logic         i_reset   ,
    input  logic [31:0]  i_io_sw   ,
    output logic [31:0]  o_io_ledr ,
    output logic [31:0]  o_io_ledg ,
    output logic [31:0]  o_io_lcd  ,
    output logic [ 6:0]  o_io_hex0 ,
    output logic [ 6:0]  o_io_hex1 ,
    output logic [ 6:0]  o_io_hex2 ,
    output logic [ 6:0]  o_io_hex3 ,
    output logic [ 6:0]  o_io_hex4 ,
    output logic [ 6:0]  o_io_hex5 ,
    output logic [ 6:0]  o_io_hex6 ,
    output logic [ 6:0]  o_io_hex7 ,
    output logic [31:0]  o_pc_debug,
    output logic         o_insn_vld
);

    logic [31:0] pc_plus4;
    logic [31:0] i_pc_in, o_pc_out;
    logic o_pc_sel;

    logic [31:0] i_instr;

    logic [31:0] o_immgen;
    logic [2:0] o_imm_sel;

    logic [31:0] o_rs1_data, o_rs2_data;
    logic o_rd_wren;

    logic o_br_un, i_br_equal, i_br_less;

    logic o_opa_sel, o_opb_sel;
    logic [31:0] i_op_a, i_op_b;

    logic [3:0] o_alu_op;
    logic [31:0] o_alu_data;

    logic [3:0] o_byte_num;
    logic o_lsu_wren;
    logic [31:0] o_ld_data;

    logic [1:0] o_wb_sel;
    logic [31:0] o_wb_data;


    assign o_pc_debug = o_pc_out;

    PCplus4 PCplus4(
        .PCout(o_pc_out),
        .PCplus4(pc_plus4)
    );

    mux2 mux2_pc(
        .i_data1(pc_plus4),
        .i_data2(o_alu_data),
        .i_mux_sel(o_pc_sel),
        .o_data_out(i_pc_in)
    );

    pc pc(
        .i_clk(i_clk),
        .i_reset(i_reset),
        .i_pc_in(i_pc_in),
        .o_pc_out(o_pc_out)
    );

    instr_mem instr_mem_inst (
        .i_imem_addr(o_pc_out),
        .o_instr(i_instr)
    );

    ImmGen ImmGen(
        .i_instr(i_instr),
        .i_imm_sel(o_imm_sel),
        .o_immgen(o_immgen)
    );

    regfile regfile (
        .i_clk(i_clk),
        .i_reset(i_reset),
        .i_rs1_addr(i_instr[19:15]),
        .i_rs2_addr(i_instr[24:20]),
        .i_rd_addr(i_instr[11:7]),
        .i_rd_data(o_wb_data),
        .i_rd_wren(o_rd_wren),
        .o_rs1_data(o_rs1_data),
        .o_rs2_data(o_rs2_data)
    );

    brc brc(
        .i_rs1_data(o_rs1_data),
        .i_rs2_data(o_rs2_data),
        .i_br_un(o_br_un),
        .o_br_equal(i_br_equal),
        .o_br_less(i_br_less)
    );

    mux2 mux_opa(
        .i_data1(o_rs1_data),
        .i_data2(o_pc_out),
        .i_mux_sel(o_opa_sel),
        .o_data_out(i_op_a)
    );

    mux2 mux_opb(
        .i_data1(o_rs2_data),
        .i_data2(o_immgen),
        .i_mux_sel(o_opb_sel),
        .o_data_out(i_op_b)
    );

    alu alu(
        .i_op_a(i_op_a),
        .i_op_b(i_op_b),
        .i_alu_op(o_alu_op),
        .o_alu_data(o_alu_data)
    );

    lsu lsu (
        .i_clk(i_clk),
        .i_reset(i_reset),
        .i_lsu_wren(o_lsu_wren),
        .i_byte_num(o_byte_num),
        .i_st_data(o_rs2_data),
        .i_lsu_addr(o_alu_data),
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

    mux3 wb(
        .i_pc_out(pc_plus4), //pc+4 for jal/ jalr (test this if not o_pc_out) 00
        .i_alu_data(o_alu_data),  //01
        .i_ld_data(o_ld_data), //10
        .i_wb_sel(o_wb_sel),
        .o_wb_data(o_wb_data)
    );

    control_logic control_logic(
        .i_instr(i_instr),
        .i_br_equal(i_br_equal),
        .i_br_less(i_br_less),
        .o_alu_op(o_alu_op),
        .o_imm_sel(o_imm_sel),
        .o_byte_num(o_byte_num),
        .o_wb_sel(o_wb_sel),
        .o_opa_sel(o_opa_sel),
        .o_opb_sel(o_opb_sel),
        .o_pc_sel(o_pc_sel),
        .o_rd_wren(o_rd_wren),
        .o_br_un(o_br_un),
        .o_lsu_wren(o_lsu_wren),
        .o_insn_vld(o_insn_vld)
    );

endmodule