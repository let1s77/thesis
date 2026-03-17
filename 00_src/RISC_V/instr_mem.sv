module instr_mem #(
    parameter DEPTH =  2048, // Depth of the memory, in bytes
    parameter MEM   = "../02_test/isa_4b.hex"
) ( 
    input  [31:0] i_imem_addr,
    output logic [31:0] o_instr
);

    logic [31:0] IMem [0:(DEPTH/4)-1];// thuc te
    initial begin
         $readmemh(MEM, IMem);
    end

    always_comb begin
        o_instr = IMem[i_imem_addr[$clog2(DEPTH)-1:2]];
    end
endmodule