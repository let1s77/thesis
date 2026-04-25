 // memory size: 128*128 * 24-bit

module ROM(
    input             CLK,
    input             REN,
    input      [13:0] A,
    output reg [23:0] Q
);

reg [23:0] mem [((1<<14) - 1) : 0];

always @(posedge CLK) begin
    if (REN)
        Q <= mem[A];
    else
        Q <= 'd0;
        //Q <= 'dz;
end

endmodule
