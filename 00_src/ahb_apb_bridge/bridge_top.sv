//==============================================================================
// Module: Bridge_Top
// Description: AHB-APB Bridge Top Module
//              Instantiates AHB Slave Interface and APB FSM Controller
//==============================================================================

module Bridge_Top (
    // AHB Inputs
    input  logic        Hclk,
    input  logic        Hresetn,
    input  logic        Hwrite,
    input  logic        Hreadyin,
    input  logic [31:0] Hwdata,
    input  logic [31:0] Haddr,
    input  logic [1:0]  Htrans,
    
    // APB Input (from APB slave)
    input  logic [31:0] Prdata,
    
    // APB Outputs
    output logic        Penable,
    output logic        Pwrite,
    output logic [2:0]  Pselx,
    output logic [31:0] Paddr,
    output logic [31:0] Pwdata,
    
    // AHB Outputs
    output logic        Hreadyout,
    output logic [1:0]  Hresp,
    output logic [31:0] Hrdata
);

    //==========================================================================
    // Internal Signals
    //==========================================================================
    logic        valid;
    logic [31:0] Haddr1, Haddr2;
    logic [31:0] Hwdata1, Hwdata2;
    logic        Hwritereg;
    logic [2:0]  tempselx;

    //==========================================================================
    // Module Instantiations
    //==========================================================================
    
    // AHB Slave Interface
    AHB_slave_interface u_ahb_slave (
        .Hclk       (Hclk),
        .Hresetn    (Hresetn),
        .Hwrite     (Hwrite),
        .Hreadyin   (Hreadyin),
        .Htrans     (Htrans),
        .Haddr      (Haddr),
        .Hwdata     (Hwdata),
        .Prdata     (Prdata),
        .valid      (valid),
        .Haddr1     (Haddr1),
        .Haddr2     (Haddr2),
        .Hwdata1    (Hwdata1),
        .Hwdata2    (Hwdata2),
        .Hrdata     (Hrdata),
        .Hwritereg  (Hwritereg),
        .tempselx   (tempselx),
        .Hresp      (Hresp)
    );

    // APB FSM Controller
    APB_FSM_Controller u_apb_fsm (
        .Hclk       (Hclk),
        .Hresetn    (Hresetn),
        .valid      (valid),
        .Haddr1     (Haddr1),
        .Haddr2     (Haddr2),
        .Hwdata1    (Hwdata1),
        .Hwdata2    (Hwdata2),
        .Prdata     (Prdata),
        .Hwrite     (Hwrite),
        .Haddr      (Haddr),
        .Hwdata     (Hwdata),
        .Hwritereg  (Hwritereg),
        .tempselx   (tempselx),
        .Pwrite     (Pwrite),
        .Penable    (Penable),
        .Pselx      (Pselx),
        .Paddr      (Paddr),
        .Pwdata     (Pwdata),
        .Hreadyout  (Hreadyout)
    );

endmodule
