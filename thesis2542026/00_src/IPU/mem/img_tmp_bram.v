module img_tmp_bram #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 16,
    parameter DEPTH      = 16'd16384  // 128x128 pixels
)(
    input                           clk,
    // Port A: system / CPU / testbench access
    input                           sys_en,
    input                           sys_we,
    input      [ADDR_WIDTH-1:0]     sys_addr,
    input      [DATA_WIDTH-1:0]     sys_wdata,
    output reg [DATA_WIDTH-1:0]     sys_rdata,
    // Port B: IPU read/write access
    input                           ipu_en,
    input                           ipu_we,
    input      [ADDR_WIDTH-1:0]     ipu_addr,
    input      [DATA_WIDTH-1:0]     ipu_wdata,
    output reg [DATA_WIDTH-1:0]     ipu_rdata
);

(* ramstyle = "M10K, no_rw_check" *) reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
localparam integer INIT_CHUNK = 4096;
integer i;
integer j;
`ifndef SYNTHESIS
initial begin
    for(i = 0; i < DEPTH; i = i + INIT_CHUNK) begin
        for (j = 0; (j < INIT_CHUNK) && ((i + j) < DEPTH); j = j + 1)
            mem[i + j] = {DATA_WIDTH{1'b0}};
    end
end
`endif

// True dual-port RAM: reads gated by enable to match M10K port clock-enable.
// When en=0 the port is idle and output holds previous value (M10K hardware).
// When en=1, we=0: synchronous read.  When en=1, we=1: synchronous write.
always @(posedge clk) begin
    if (sys_en) begin
        if (sys_we)
            mem[sys_addr] <= sys_wdata;
        sys_rdata <= mem[sys_addr];
    end
end

always @(posedge clk) begin
    if (ipu_en) begin
        if (ipu_we)
            mem[ipu_addr] <= ipu_wdata;
        ipu_rdata <= mem[ipu_addr];
    end
end

endmodule
