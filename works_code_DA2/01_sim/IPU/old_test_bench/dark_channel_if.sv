`timescale 1ns/10ps

interface dark_channel_if(input logic clk);
    logic        rst_n;
    logic [23:0] color;
    logic [7:0]  dark_ch;

    // Clocking block for synchronization
    clocking cb @(posedge clk);
        default input #0ns output #0ns;  // No skew for clean sampling
        output color;
        input  dark_ch;
    endclocking

    // Modport for testbench
    modport TB (clocking cb, output rst_n);
    
endinterface