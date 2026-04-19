`timescale 1ns/10ps
interface grayscale_if(input logic clk);
    logic        rst_n;
    logic [23:0] color;
    logic [1:0]  mode;
    logic [7:0]  gray;

    // Clocking block giúp đồng bộ hóa dữ liệu với cạnh clock, tránh lỗi timing 'x'
    clocking cb @(posedge clk);
        default input #0ns output #0ns;  // Remove skew for clean sampling
        output color, mode;
        input  gray;
    endclocking

    // Modport định nghĩa hướng tín hiệu đối với Testbench
    modport TB (clocking cb, output rst_n);
endinterface