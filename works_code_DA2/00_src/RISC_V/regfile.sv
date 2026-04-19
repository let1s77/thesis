module regfile(
    input logic i_clk,                  
    input logic i_reset,                
    input logic [4:0] i_rs1_addr,       
    input logic [4:0] i_rs2_addr,       
    input logic [4:0] i_rd_addr,        
    input logic [31:0] i_rd_data,       
    input logic i_rd_wren,
    output logic [31:0] o_rs1_data,     
    output logic [31:0] o_rs2_data      
);
    
    logic [31:0] registers [0:31];

 
    always_comb begin
        o_rs1_data = (|i_rs1_addr) ? registers[i_rs1_addr] : 32'h0;
        o_rs2_data = (|i_rs2_addr) ? registers[i_rs2_addr] : 32'h0;
    end

    // đồng bộ ở cạnh xuống của xung nhịp phù hợp cho kiến trúc single cycle
    always @(negedge i_clk or negedge i_reset) begin
        if (!i_reset) begin
            registers <= '{32{32'h0}}; // Reset tất cả thanh ghi về 0
        end
        else if (i_rd_wren && (| i_rd_addr)) begin 
            registers[i_rd_addr] <= i_rd_data; // Ghi dữ liệu vào thanh ghi
        end
    end

endmodule