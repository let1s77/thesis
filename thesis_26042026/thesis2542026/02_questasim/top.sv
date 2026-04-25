///////////////////////////////////////////////////                   
//   Author: DA2 Project                         // 
//   Project: Dark Channel Image Processor       //
//   Description: Top module for dark channel    //
//                processing system              //
///////////////////////////////////////////////////

// Include paths relative to 02_questasim/ folder
`include "../01_sim/IPU/Testbench_DarkChannel_System/src/dark_channel.sv"
`include "../01_sim/IPU/Testbench_DarkChannel_System/src/src_min.sv"

module top(
    input               i_clk,
    input               i_rst_n,
    output reg          o_dark_done,

    // ROM interface (input image)
    output reg          o_rom_en,
    output reg  [13:0]  o_rom_addr,
    input       [23:0]  i_rom_data,

    // RAM interface (output dark channel)
    output reg          o_ram_ren,
    output reg          o_ram_wen,
    output reg  [13:0]  o_ram_addr,
    output reg  [7:0]   o_ram_data,
    input       [7:0]   i_ram_data
);

    // State encoding
    localparam IDLE = 2'b00;
    localparam PROC = 2'b01;  // Processing dark channel
    localparam DONE = 2'b10;

    // Internal registers
    reg [1:0]  state;
    reg [14:0] pixel_cnt;  // Extended to handle 128*128 + pipeline delay

    // Dark channel output
    wire [7:0] dark_ch_o;

    // Instantiate dark channel module (Simple mode)
    dark_channel #(
        .ENABLE_SPATIAL_FILTER(0)
    ) dark_inst (
        .i_clk       (i_clk),
        .i_rst_n     (i_rst_n),
        .i_valid     (1'b1),
        .i_color     (i_rom_data),
        .o_valid     (),
        .o_dark_ch   (dark_ch_o)
    );

    // Total pixels
    localparam TOTAL_PIXELS = 128 * 128;
    // Pipeline latency: ROM(1) + src_min(1) = 2 cycles
    localparam PIPE_LATENCY = 2;

    // FSM - State transition
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            state <= IDLE;
        end else begin
            case (state)
                IDLE: state <= PROC;
                PROC: state <= o_dark_done ? DONE : PROC;
                DONE: state <= DONE;
                default: state <= IDLE;
            endcase
        end
    end

    // Control logic
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            pixel_cnt    <= 15'd0;
            o_rom_addr   <= 14'd0;
            o_ram_addr   <= 14'd0;
            o_dark_done  <= 1'b0;
            o_rom_en     <= 1'b0;
            o_ram_wen    <= 1'b0;
            o_ram_ren    <= 1'b0;
            o_ram_data   <= 8'd0;
        end else begin
            case (state)
                IDLE: begin
                    pixel_cnt    <= 15'd0;
                    o_rom_addr   <= 14'd0;
                    o_ram_addr   <= 14'd0;
                    o_dark_done  <= 1'b0;
                    o_rom_en     <= 1'b1;  // Enable ROM read
                    o_ram_wen    <= 1'b0;
                    o_ram_ren    <= 1'b0;
                end

                PROC: begin
                    pixel_cnt <= pixel_cnt + 1;
                    
                    // Stage 1: Read from ROM (until all pixels read)
                    if (pixel_cnt < TOTAL_PIXELS) begin
                        o_rom_en   <= 1'b1;
                        o_rom_addr <= pixel_cnt[13:0];
                    end else begin
                        o_rom_en <= 1'b0;
                    end

                    // Stage 2: Write to RAM (after pipeline latency)
                    if (pixel_cnt >= PIPE_LATENCY && pixel_cnt < TOTAL_PIXELS + PIPE_LATENCY) begin
                        o_ram_wen  <= 1'b1;
                        o_ram_addr <= pixel_cnt[13:0] - PIPE_LATENCY;
                        o_ram_data <= dark_ch_o;
                    end else begin
                        o_ram_wen <= 1'b0;
                    end

                    // Done when all pixels written
                    if (pixel_cnt == TOTAL_PIXELS + PIPE_LATENCY) begin
                        o_dark_done <= 1'b1;
                    end
                end

                DONE: begin
                    o_ram_wen    <= 1'b0;
                    o_rom_en     <= 1'b0;
                    o_dark_done  <= 1'b1;
                end
            endcase
        end
    end

endmodule

