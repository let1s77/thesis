module memory #(
    parameter DEPTH    = 2048 // Depth of memory (in bytes) 
) (
    input i_clk,     
    input i_reset,   
    input [$clog2(DEPTH)-1:0] i_addr,    
    input [31:0] i_wdata,   
    input [3:0] i_bmask,   // Byte mask (1  enable, 0 disable)
    input i_wren,     
    output logic [31:0] o_rdata,
    output logic [31:0] o_rdata_next  // Next word for misaligned access
);

    localparam WORDS = DEPTH / 4;
    logic [$clog2(WORDS)-1:0] mem_addr;
    logic [$clog2(WORDS)-1:0] mem_addr_next;

    assign mem_addr      = i_addr[$clog2(DEPTH)-1:2];
    assign mem_addr_next = (mem_addr == (WORDS - 1)) ? mem_addr : (mem_addr + 1'b1);

    // =========================================================================
    // 4 separate 8-bit BRAMs — simple write-enable per byte lane
    // Quartus infers M10K for each (no byte-select on single array)
    // =========================================================================
    (* ramstyle = "M10K, no_rw_check" *) logic [7:0] mem_b0 [0:WORDS-1];
    (* ramstyle = "M10K, no_rw_check" *) logic [7:0] mem_b1 [0:WORDS-1];
    (* ramstyle = "M10K, no_rw_check" *) logic [7:0] mem_b2 [0:WORDS-1];
    (* ramstyle = "M10K, no_rw_check" *) logic [7:0] mem_b3 [0:WORDS-1];

    initial begin
        for (int i = 0; i < WORDS; i++) begin
            mem_b0[i] = 8'h00;
            mem_b1[i] = 8'h00;
            mem_b2[i] = 8'h00;
            mem_b3[i] = 8'h00;
        end
    end

    // Intermediate read registers
    logic [7:0] rd_b0, rd_b1, rd_b2, rd_b3;
    logic [7:0] rn_b0, rn_b1, rn_b2, rn_b3;

    // --- Byte 0 -------------------------------------------------------
    // Port A: write + read at mem_addr
    always @(posedge i_clk) begin
        if (i_wren & i_bmask[0])
            mem_b0[mem_addr] <= i_wdata[7:0];
        rd_b0 <= mem_b0[mem_addr];
    end
    // Port B: read only at mem_addr_next
    always @(posedge i_clk) begin
        rn_b0 <= mem_b0[mem_addr_next];
    end

    // --- Byte 1 -------------------------------------------------------
    always @(posedge i_clk) begin
        if (i_wren & i_bmask[1])
            mem_b1[mem_addr] <= i_wdata[15:8];
        rd_b1 <= mem_b1[mem_addr];
    end
    always @(posedge i_clk) begin
        rn_b1 <= mem_b1[mem_addr_next];
    end

    // --- Byte 2 -------------------------------------------------------
    always @(posedge i_clk) begin
        if (i_wren & i_bmask[2])
            mem_b2[mem_addr] <= i_wdata[23:16];
        rd_b2 <= mem_b2[mem_addr];
    end
    always @(posedge i_clk) begin
        rn_b2 <= mem_b2[mem_addr_next];
    end

    // --- Byte 3 -------------------------------------------------------
    always @(posedge i_clk) begin
        if (i_wren & i_bmask[3])
            mem_b3[mem_addr] <= i_wdata[31:24];
        rd_b3 <= mem_b3[mem_addr];
    end
    always @(posedge i_clk) begin
        rn_b3 <= mem_b3[mem_addr_next];
    end

    // Combine byte lanes — same timing as original
    assign o_rdata      = {rd_b3, rd_b2, rd_b1, rd_b0};
    assign o_rdata_next = {rn_b3, rn_b2, rn_b1, rn_b0};

endmodule
