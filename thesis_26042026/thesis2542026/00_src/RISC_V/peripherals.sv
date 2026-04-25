module peripherals (

    input i_clk,
    input i_reset,
    input logic [15:0] i_peri_addr, // Address low 16-bit of 0x1000_xxxx peripheral region
    input logic [31:0] i_data_in,
    input logic i_write_en,
    input logic [31:0] i_io_sw, // Switches input (không dùng ở đây)
   
    output logic [31:0] o_data_out,
    output logic [31:0] o_io_ledr, // LEDR output (required)
    output logic [31:0] o_io_lcd, // LCD output
    output logic [31:0] o_io_ledg, // LEDG output (required)
    output logic [6:0] o_io_hex0, o_io_hex1, o_io_hex2, o_io_hex3, o_io_hex4, o_io_hex5, o_io_hex6, o_io_hex7
);

    logic [6:0] seg7_HEX0, seg7_HEX1, seg7_HEX2, seg7_HEX3, seg7_HEX4, seg7_HEX5, seg7_HEX6, seg7_HEX7;

    SevenSegment ssc (
        .input_data(i_data_in),
        .HEX0(seg7_HEX0),
        .HEX1(seg7_HEX1),
        .HEX2(seg7_HEX2),
        .HEX3(seg7_HEX3),
        .HEX4(seg7_HEX4),
        .HEX5(seg7_HEX5),
        .HEX6(seg7_HEX6),
        .HEX7(seg7_HEX7)
    );

    //WRITE LOGIC 
    always_ff @(posedge i_clk or negedge i_reset) begin

        if (!i_reset) begin
            // Reset tất cả đầu ra về 0
            o_io_ledr <= 32'b0;
            o_io_lcd  <= 32'b0;
            o_io_ledg <= 32'b0;
            o_io_hex0 <= 7'b0; // Sửa: Gán 7-bit
            o_io_hex1 <= 7'b0;
            o_io_hex2 <= 7'b0;
            o_io_hex3 <= 7'b0;
            o_io_hex4 <= 7'b0;
            o_io_hex5 <= 7'b0;
            o_io_hex6 <= 7'b0;
            o_io_hex7 <= 7'b0;
        end 
        else if (i_write_en) begin
            // Exact register offsets per memory map.
            case (i_peri_addr)
                16'h0000: o_io_ledr <= i_data_in; // 0x1000_0000
                16'h0004: o_io_ledg <= i_data_in; // 0x1000_0004
                16'h0010: begin                  // 0x1000_0010 HEX0~HEX3
                    o_io_hex0 <= seg7_HEX0;
                    o_io_hex1 <= seg7_HEX1;
                    o_io_hex2 <= seg7_HEX2;
                    o_io_hex3 <= seg7_HEX3;
                end
                16'h0014: begin                  // 0x1000_0014 HEX4~HEX7
                    o_io_hex4 <= seg7_HEX4;
                    o_io_hex5 <= seg7_HEX5;
                    o_io_hex6 <= seg7_HEX6;
                    o_io_hex7 <= seg7_HEX7;
                end
                16'h0020: o_io_lcd <= i_data_in; // 0x1000_0020
                default: ;
            endcase
        end
    end

    //READ LOGIC
    always_comb begin
        o_data_out = 32'b0; // Mặc định trả về 0

        case (i_peri_addr)
            16'h0000: o_data_out = o_io_ledr; // 0x1000_0000
            16'h0004: o_data_out = o_io_ledg; // 0x1000_0004
            16'h0020: o_data_out = o_io_lcd;  // 0x1000_0020
            16'h0030: o_data_out = i_io_sw;   // 0x1000_0030 PERI_SWITCH
            16'h0034: o_data_out = i_io_sw;   // 0x1000_0034 PERI_KEY (shared input for now)
            default:  o_data_out = 32'b0;
        endcase

    end
endmodule