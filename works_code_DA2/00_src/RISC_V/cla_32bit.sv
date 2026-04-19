// =============================================================================
// Module : cla_32bit
// Description :
//   32-bit adder with carry-in/carry-out.
//   Uses Verilog '+' operator so Quartus maps to the dedicated ALM carry chain
//   on Cyclone V, which is ~3x faster than the previous 8-cascaded-cla_4bit
//   implementation routed through general LUTs.
//   Interface is unchanged — drop-in replacement, same I/O, same function.
// =============================================================================
module cla_32bit (
    input  logic [31:0] i_a,      // 32-bit input A
    input  logic [31:0] i_b,      // 32-bit input B
    input  logic        i_ci,     // Carry in (for subtraction support)
    output logic [31:0] o_s,      // 32-bit sum output
    output logic        o_co      // Carry out (for overflow detection)
);

    // Let the synthesizer use the Cyclone V dedicated carry chain.
    // Functionally identical to: 8 × cla_4bit cascaded with serial carry.
    assign {o_co, o_s} = {1'b0, i_a} + {1'b0, i_b} + {32'b0, i_ci};

endmodule
