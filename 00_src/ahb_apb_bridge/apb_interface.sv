//==============================================================================
// Module: APB_Interface
// Description: APB Interface Module (for simulation/testbench)
//              - Pass-through signals to APB slave
//              - Generate random read data for testing
//==============================================================================

module APB_Interface (
    // APB Inputs (from Bridge)
    input  logic        Pwrite,
    input  logic        Penable,
    input  logic [2:0]  Pselx,
    input  logic [31:0] Paddr,
    input  logic [31:0] Pwdata,
    
    // APB Outputs (to APB Slave)
    output logic        Pwriteout,
    output logic        Penableout,
    output logic [2:0]  Pselxout,
    output logic [31:0] Paddrout,
    output logic [31:0] Pwdataout,
    
    // Read Data (from APB Slave)
    output logic [31:0] Prdata
);

    //==========================================================================
    // Pass-through Signals
    //==========================================================================
    assign Penableout = Penable;
    assign Pselxout   = Pselx;
    assign Pwriteout  = Pwrite;
    assign Paddrout   = Paddr;
    assign Pwdataout  = Pwdata;

    //==========================================================================
    // Read Data Generation (for simulation)
    //==========================================================================
    always_comb begin
        if (~Pwrite && Penable)
            Prdata = ($random) % 256;
        else
            Prdata = 32'h0;
    end

endmodule
