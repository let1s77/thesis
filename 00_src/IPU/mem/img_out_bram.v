module img_out_bram #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 16,
    parameter DEPTH      = 16'd49152  // 192 KB / 4 bytes
)(
    input                           clk,
    // Port A: system / CPU / testbench access
    input                           sys_en,
    input                           sys_we,
    input      [ADDR_WIDTH-1:0]     sys_addr,
    input      [DATA_WIDTH-1:0]     sys_wdata,
    output reg [DATA_WIDTH-1:0]     sys_rdata,
    // Port B: IPU writer access
    input                           ipu_we,
    input      [ADDR_WIDTH-1:0]     ipu_addr,
    input      [DATA_WIDTH-1:0]     ipu_wdata
);

(* ram_style = "block" *) reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
integer i;
initial begin
    for(i = 0; i < DEPTH; i = i + 1) begin
        mem[i] = {DATA_WIDTH{1'b0}};
    end
end

always @(posedge clk) begin
    if (sys_en) begin
        if (sys_we && (sys_addr < DEPTH))
            mem[sys_addr] <= sys_wdata;
        if (sys_addr < DEPTH)
            sys_rdata <= mem[sys_addr];
        else
            sys_rdata <= {DATA_WIDTH{1'b0}};
    end
end

always @(posedge clk) begin
    if (ipu_we && (ipu_addr < DEPTH)) begin
        mem[ipu_addr] <= ipu_wdata;
    end
end

endmodule