//==============================================================================
// Module: AHB_slave_interface
// Description: AHB Slave Interface for AHB-APB Bridge
//              - Pipeline logic for address, data and control signals
//              - Valid signal generation
//              - Peripheral select (tempselx) logic
//==============================================================================

module AHB_slave_interface (
    // Clock and Reset
    input  logic        Hclk,
    input  logic        Hresetn,
    
    // AHB Inputs
    input  logic        Hwrite,
    input  logic        Hreadyin,
    input  logic [1:0]  Htrans,
    input  logic [31:0] Haddr,
    input  logic [31:0] Hwdata,
    
    // APB Input
    input  logic [31:0] Prdata,
    
    // Outputs to APB FSM Controller
    output logic        valid,
    output logic [31:0] Haddr1,
    output logic [31:0] Haddr2,
    output logic [31:0] Hwdata1,
    output logic [31:0] Hwdata2,
    output logic [31:0] Hrdata,
    output logic        Hwritereg,
    output logic [2:0]  tempselx,
    
    // AHB Response
    output logic [1:0]  Hresp
);

    //==========================================================================
    // Pipeline Logic for Address
    //==========================================================================
    always_ff @(posedge Hclk or negedge Hresetn) begin
        if (~Hresetn) begin
            Haddr1 <= 32'h0;
            Haddr2 <= 32'h0;
        end
        else begin
            Haddr1 <= Haddr;
            Haddr2 <= Haddr1;
        end
    end

    //==========================================================================
    // Pipeline Logic for Write Data
    //==========================================================================
    always_ff @(posedge Hclk or negedge Hresetn) begin
        if (~Hresetn) begin
            Hwdata1 <= 32'h0;
            Hwdata2 <= 32'h0;
        end
        else begin
            Hwdata1 <= Hwdata;
            Hwdata2 <= Hwdata1;
        end
    end

    //==========================================================================
    // Pipeline Logic for Write Control Signal
    //==========================================================================
    always_ff @(posedge Hclk or negedge Hresetn) begin
        if (~Hresetn)
            Hwritereg <= 1'b0;
        else
            Hwritereg <= Hwrite;
    end

    //==========================================================================
    // Valid Signal Generation
    // Valid when:
    //   - Reset is inactive
    //   - Hreadyin is high
    //   - Address is in valid range (0x8000_0000 to 0x8C00_0000)
    //   - Transfer type is SEQ (2'b11) or NONSEQ (2'b10)
    //==========================================================================
    always_comb begin
        valid = 1'b0;
        if (Hresetn && Hreadyin && 
            (Haddr >= 32'h8000_0000 && Haddr < 32'h8C00_0000) && 
            (Htrans == 2'b10 || Htrans == 2'b11)) begin
            valid = 1'b1;
        end
    end

    //==========================================================================
    // Peripheral Select (tempselx) Logic
    // Address Mapping:
    //   - 0x8000_0000 - 0x83FF_FFFF: Slave 1 (tempselx = 3'b001)
    //   - 0x8400_0000 - 0x87FF_FFFF: Slave 2 (tempselx = 3'b010)
    //   - 0x8800_0000 - 0x8BFF_FFFF: Slave 3 (tempselx = 3'b100)
    //==========================================================================
    always_comb begin
        tempselx = 3'b000;
        if (Hresetn) begin
            if (Haddr >= 32'h8000_0000 && Haddr < 32'h8400_0000)
                tempselx = 3'b001;
            else if (Haddr >= 32'h8400_0000 && Haddr < 32'h8800_0000)
                tempselx = 3'b010;
            else if (Haddr >= 32'h8800_0000 && Haddr < 32'h8C00_0000)
                tempselx = 3'b100;
        end
    end

    //==========================================================================
    // Read Data and Response
    //==========================================================================
    assign Hrdata = Prdata;
    assign Hresp  = 2'b00;  // OKAY response

endmodule
