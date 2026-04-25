module instr_mem #(
    parameter DEPTH =  8000, // Depth of the memory, in bytes (2000 words)
    parameter MEM   = "../../13_hex/vga_dehaze_fulltest.hex"
) ( 
    input  logic        clk,
    input  [31:0] i_imem_addr,
    output logic [31:0] o_instr
);

    localparam int WORDS = (DEPTH / 4);
    (* ramstyle = "M10K" *) logic [31:0] IMem [0:WORDS-1];
    logic [$clog2(WORDS)-1:0] imem_idx;
    initial begin
         $readmemh(MEM, IMem);
    end

    assign imem_idx = i_imem_addr[$clog2(DEPTH)-1:2];

    // Synchronous read — enables M10K block RAM inference
    always_ff @(posedge clk) begin
        o_instr <= IMem[imem_idx];
    end
endmodule