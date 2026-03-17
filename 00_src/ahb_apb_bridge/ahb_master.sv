//==============================================================================
// Module: AHB_Master
// Description: AHB Master Module (for testbench/simulation)
//              - Provides tasks for single read and write operations
//              - Generates AHB transactions
//==============================================================================

module AHB_Master (
    // Clock and Reset
    input  logic        Hclk,
    input  logic        Hresetn,
    
    // AHB Inputs (from Slave)
    input  logic        Hreadyout,
    input  logic [1:0]  Hresp,
    input  logic [31:0] Hrdata,
    
    // AHB Outputs (to Slave)
    output logic        Hwrite,
    output logic        Hreadyin,
    output logic [1:0]  Htrans,
    output logic [31:0] Hwdata,
    output logic [31:0] Haddr
);

    //==========================================================================
    // Internal Signals (for burst operations - not used in basic tasks)
    //==========================================================================
    logic [2:0] Hburst;
    logic [2:0] Hsize;

    //==========================================================================
    // Single Write Task
    // Performs a single write transaction to address 0x8000_0001
    //==========================================================================
    task single_write();
        begin
            @(posedge Hclk);
            #2;
            begin
                Hwrite   = 1'b1;
                Htrans   = 2'b10;      // NONSEQ
                Hsize    = 3'b000;     // Byte
                Hburst   = 3'b000;     // SINGLE
                Hreadyin = 1'b1;
                Haddr    = 32'h8000_0001;
            end
            
            @(posedge Hclk);
            #2;
            begin
                Htrans = 2'b00;        // IDLE
                Hwdata = 8'hA3;
            end
        end
    endtask

    //==========================================================================
    // Single Read Task
    // Performs a single read transaction from address 0x8000_00A2
    //==========================================================================
    task single_read();
        begin
            @(posedge Hclk);
            #2;
            begin
                Hwrite   = 1'b0;
                Htrans   = 2'b10;      // NONSEQ
                Hsize    = 3'b000;     // Byte
                Hburst   = 3'b000;     // SINGLE
                Hreadyin = 1'b1;
                Haddr    = 32'h8000_00A2;
            end
            
            @(posedge Hclk);
            #2;
            begin
                Htrans = 2'b00;        // IDLE
            end
        end
    endtask

    //==========================================================================
    // Parameterized Write Task
    //==========================================================================
    task write_data(input logic [31:0] addr, input logic [31:0] data);
        begin
            @(posedge Hclk);
            #2;
            begin
                Hwrite   = 1'b1;
                Htrans   = 2'b10;      // NONSEQ
                Hsize    = 3'b010;     // Word
                Hburst   = 3'b000;     // SINGLE
                Hreadyin = 1'b1;
                Haddr    = addr;
            end
            
            @(posedge Hclk);
            #2;
            begin
                Htrans = 2'b00;        // IDLE
                Hwdata = data;
            end
        end
    endtask

    //==========================================================================
    // Parameterized Read Task
    //==========================================================================
    task read_data(input logic [31:0] addr);
        begin
            @(posedge Hclk);
            #2;
            begin
                Hwrite   = 1'b0;
                Htrans   = 2'b10;      // NONSEQ
                Hsize    = 3'b010;     // Word
                Hburst   = 3'b000;     // SINGLE
                Hreadyin = 1'b1;
                Haddr    = addr;
            end
            
            @(posedge Hclk);
            #2;
            begin
                Htrans = 2'b00;        // IDLE
            end
        end
    endtask

endmodule
