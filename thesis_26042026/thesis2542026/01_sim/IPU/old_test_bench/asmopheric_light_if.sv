`timescale 1ns/10ps

interface atmospheric_light_if(input logic clk);
    logic        rst_n;
    logic        frame_start;
    logic        valid;
    logic [23:0] rgb_in;
    logic [7:0]  dark_ch;
    logic [7:0]  A_R, A_G, A_B;
    logic        o_valid;

    clocking cb @(posedge clk);
        default input #1ns output #1ns;
        output rst_n, frame_start, valid, rgb_in, dark_ch;
        input  A_R, A_G, A_B, o_valid;
    endclocking

    modport TB (clocking cb);
endinterface