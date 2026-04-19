// =============================================================================
// Module : single_cycle
// Description :
//   RISC-V single cycle processor.
//   Thêm ports mới cho LSU để kết nối BRAM frame buffers và IPU qua APB4.
//   Data path (PC/ALU/RegFile/BRC/ImmGen/mux) KHÔNG thay đổi.
// =============================================================================

module single_cycle (
    input  logic        i_clk,
    input  logic        i_reset,
    input  logic [31:0] i_io_sw,
    output logic [31:0] o_pc_debug,
    output logic        o_insn_vld,

    // -------------------------------------------------------------------------
    // IMG_IN_BUF BRAM — Port A (0x0001_0000 - 0x0003_FFFF)
    // -------------------------------------------------------------------------
    output logic        img_in_sys_en,
    output logic        img_in_sys_we,
    output logic [15:0] img_in_sys_addr,
    output logic [31:0] img_in_sys_wdata,
    input  logic [31:0] img_in_sys_rdata,

    // -------------------------------------------------------------------------
    // IMG_OUT_BUF BRAM — Port A (0x0004_0000 - 0x0006_FFFF)
    // -------------------------------------------------------------------------
    output logic        img_out_sys_en,
    output logic        img_out_sys_we,
    output logic [15:0] img_out_sys_addr,
    output logic [31:0] img_out_sys_wdata,
    input  logic [31:0] img_out_sys_rdata,

    // -------------------------------------------------------------------------
    // IMG_TMP_BUF BRAM — Port A (0x0007_0000 - 0x0009_FFFF)
    // -------------------------------------------------------------------------
    output logic        img_tmp_sys_en,
    output logic        img_tmp_sys_we,
    output logic [15:0] img_tmp_sys_addr,
    output logic [31:0] img_tmp_sys_wdata,
    input  logic [31:0] img_tmp_sys_rdata,

    // -------------------------------------------------------------------------
    // APB4 shared bus + separate PSEL to peripheral/IPU wrappers
    // -------------------------------------------------------------------------
    output logic        PSEL_peri,
    output logic        PSEL_ipu,
    output logic        PENABLE,
    output logic        PWRITE,
    output logic [31:0] PADDR,
    output logic [31:0] PWDATA,
    output logic [3:0]  PSTRB,
    output logic [2:0]  PPROT,
    input  logic        PREADY_peri,
    input  logic [31:0] PRDATA_peri,
    input  logic        PREADY_ipu,
    input  logic [31:0] PRDATA_ipu
);

    // =========================================================================
    // Internal wires — data path (không đổi)
    // =========================================================================
    logic [31:0] pc_plus4;
    logic [31:0] i_pc_in, o_pc_out;
    logic        o_pc_sel;

    logic [31:0] i_instr;
    logic [31:0] o_immgen;
    logic [2:0]  o_imm_sel;

    logic [31:0] o_rs1_data, o_rs2_data;
    logic        o_rd_wren;

    logic        o_br_un, i_br_equal, i_br_less;
    logic        o_opa_sel, o_opb_sel;
    logic [31:0] i_op_a, i_op_b;

    logic [3:0]  o_alu_op;
    logic [31:0] o_alu_data;

    logic [3:0]  o_byte_num;
    logic        o_lsu_wren;
    logic [31:0] o_ld_data;

    logic [1:0]  o_wb_sel;
    logic [31:0] o_wb_data;

    assign o_pc_debug = o_pc_out;

    // =========================================================================
    // 3-phase FSM: FETCH → EXEC → MEM_WB
    //   FETCH  : instruction memory reads (synchronous, 1-cycle latency)
    //   EXEC   : decode / ALU / store — memory writes fire on posedge
    //   MEM_WB : load data available — register writeback + PC update
    // Same program, same ISA behaviour, 3 CPI — golden output preserved.
    // =========================================================================
    typedef enum logic [1:0] {FETCH, EXEC, MEM_WB} cpu_state_t;
    cpu_state_t cpu_state;

    always_ff @(posedge i_clk or negedge i_reset) begin
        if (!i_reset) cpu_state <= FETCH;
        else case (cpu_state)
            FETCH:   cpu_state <= EXEC;
            EXEC:    cpu_state <= MEM_WB;
            MEM_WB:  cpu_state <= FETCH;
            default: cpu_state <= FETCH;
        endcase
    end

    // Stall PC during FETCH and EXEC — only advance in MEM_WB
    logic pc_stall;
    assign pc_stall = (cpu_state != MEM_WB);

    // Gate write-enables so stores only fire in EXEC,
    // and register writeback only fires in MEM_WB.
    logic lsu_wren_gated;
    logic rd_wren_gated;
    assign lsu_wren_gated = (cpu_state == EXEC)   ? o_lsu_wren : 1'b0;
    assign rd_wren_gated  = (cpu_state == MEM_WB)  ? o_rd_wren  : 1'b0;

    // =========================================================================
    // Data path — giữ nguyên hoàn toàn
    // =========================================================================
    PCplus4 PCplus4 (
        .PCout   (o_pc_out),
        .PCplus4 (pc_plus4)
    );

    mux2 mux2_pc (
        .i_data1    (pc_plus4),
        .i_data2    (o_alu_data),
        .i_mux_sel  (o_pc_sel),
        .o_data_out (i_pc_in)
    );

    pc pc (
        .i_clk   (i_clk),
        .i_reset (i_reset),
        .i_stall (pc_stall),
        .i_pc_in (i_pc_in),
        .o_pc_out(o_pc_out)
    );

    instr_mem instr_mem_inst (
        .clk         (i_clk),
        .i_imem_addr (o_pc_out),
        .o_instr     (i_instr)
    );

    ImmGen ImmGen (
        .i_instr  (i_instr),
        .i_imm_sel(o_imm_sel),
        .o_immgen (o_immgen)
    );

    regfile regfile (
        .i_clk     (i_clk),
        .i_reset   (i_reset),
        .i_rs1_addr(i_instr[19:15]),
        .i_rs2_addr(i_instr[24:20]),
        .i_rd_addr (i_instr[11:7]),
        .i_rd_data (o_wb_data),
        .i_rd_wren (rd_wren_gated),
        .o_rs1_data(o_rs1_data),
        .o_rs2_data(o_rs2_data)
    );

    brc brc (
        .i_rs1_data(o_rs1_data),
        .i_rs2_data(o_rs2_data),
        .i_br_un   (o_br_un),
        .o_br_equal(i_br_equal),
        .o_br_less (i_br_less)
    );

    mux2 mux_opa (
        .i_data1    (o_rs1_data),
        .i_data2    (o_pc_out),
        .i_mux_sel  (o_opa_sel),
        .o_data_out (i_op_a)
    );

    mux2 mux_opb (
        .i_data1    (o_rs2_data),
        .i_data2    (o_immgen),
        .i_mux_sel  (o_opb_sel),
        .o_data_out (i_op_b)
    );

    alu alu (
        .i_op_a    (i_op_a),
        .i_op_b    (i_op_b),
        .i_alu_op  (o_alu_op),
        .o_alu_data(o_alu_data)
    );

    // =========================================================================
    // LSU — thêm ports BRAM + APB4, data path ports giữ nguyên
    // =========================================================================
    lsu #(.DEPTH(16384)) lsu (
        // --- ports gốc (không đổi) ---
        .i_clk        (i_clk),
        .i_reset      (i_reset),
        .i_lsu_wren   (lsu_wren_gated),
        .i_byte_num   (o_byte_num),
        .i_st_data    (o_rs2_data),
        .i_lsu_addr   (o_alu_data),
        .i_io_sw      (i_io_sw),
        .o_ld_data    (o_ld_data),

        // --- ports mới: IMG_IN BRAM ---
        .img_in_sys_en   (img_in_sys_en),
        .img_in_sys_we   (img_in_sys_we),
        .img_in_sys_addr (img_in_sys_addr),
        .img_in_sys_wdata(img_in_sys_wdata),
        .img_in_sys_rdata(img_in_sys_rdata),

        // --- ports mới: IMG_OUT BRAM ---
        .img_out_sys_en   (img_out_sys_en),
        .img_out_sys_we   (img_out_sys_we),
        .img_out_sys_addr (img_out_sys_addr),
        .img_out_sys_wdata(img_out_sys_wdata),
        .img_out_sys_rdata(img_out_sys_rdata),

        // --- ports mới: IMG_TMP BRAM ---
        .img_tmp_sys_en   (img_tmp_sys_en),
        .img_tmp_sys_we   (img_tmp_sys_we),
        .img_tmp_sys_addr (img_tmp_sys_addr),
        .img_tmp_sys_wdata(img_tmp_sys_wdata),
        .img_tmp_sys_rdata(img_tmp_sys_rdata),

        // --- ports mới: APB4 shared + two selects ---
        .PSEL_peri  (PSEL_peri),
        .PSEL_ipu   (PSEL_ipu),
        .PENABLE    (PENABLE),
        .PWRITE     (PWRITE),
        .PADDR      (PADDR),
        .PWDATA     (PWDATA),
        .PSTRB      (PSTRB),
        .PPROT      (PPROT),
        .PREADY_peri(PREADY_peri),
        .PRDATA_peri(PRDATA_peri),
        .PREADY_ipu (PREADY_ipu),
        .PRDATA_ipu (PRDATA_ipu)
    );

    // =========================================================================
    // Writeback mux — không đổi
    // =========================================================================
    mux3 wb (
        .i_pc_out  (pc_plus4),
        .i_alu_data(o_alu_data),
        .i_ld_data (o_ld_data),
        .i_wb_sel  (o_wb_sel),
        .o_wb_data (o_wb_data)
    );

    control_logic control_logic (
        .i_instr   (i_instr),
        .i_br_equal(i_br_equal),
        .i_br_less (i_br_less),
        .o_alu_op  (o_alu_op),
        .o_imm_sel (o_imm_sel),
        .o_byte_num(o_byte_num),
        .o_wb_sel  (o_wb_sel),
        .o_opa_sel (o_opa_sel),
        .o_opb_sel (o_opb_sel),
        .o_pc_sel  (o_pc_sel),
        .o_rd_wren (o_rd_wren),
        .o_br_un   (o_br_un),
        .o_lsu_wren(o_lsu_wren),
        .o_insn_vld(o_insn_vld)
    );

endmodule