module peripherals (

    input i_clk,
    input i_reset,
    input logic [15:0] i_peri_addr, // Address input (from 0x1000_0000 to 0x1000_FFFF)
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
            // địa chỉ I/O dựa trên các bit cao
            // i_peri_addr là 16 bit thấp của địa chỉ 
            case (i_peri_addr[15:12])

                4'h0: // Địa chỉ 0x1000_0xxx
                    o_io_ledr <= i_data_in;

                4'h1: // Địa chỉ 0x1000_1xxx
                    o_io_ledg <= i_data_in;

                4'h2:  begin // Địa chỉ 0x1000_2xxx (Ghi vào HEX 3-0)

                    o_io_hex0 <= seg7_HEX0;
                    o_io_hex1 <= seg7_HEX1;
                    o_io_hex2 <= seg7_HEX2;
                    o_io_hex3 <= seg7_HEX3;
                end
                4'h3: begin // Địa chỉ 0x1000_3xxx (Ghi vào HEX 7-4)

                    o_io_hex4 <= seg7_HEX4; 
                    o_io_hex5 <= seg7_HEX5;
                    o_io_hex6 <= seg7_HEX6;
                    o_io_hex7 <= seg7_HEX7;
                end

                4'h4: // Địa chỉ 0x1000_4xxx
                    o_io_lcd <= i_data_in;

                default:  ; // Bỏ qua các địa chỉ Reserved (0x1000_5xxx...)
            endcase
        end
    end

    //READ LOGIC
    always_comb begin
        o_data_out = 32'b0; // Mặc định trả về 0

        case (i_peri_addr[15:12])
            4'h0: // Đọc từ 0x1000_0xxx
                o_data_out = o_io_ledr; // Đọc lại giá trị đã ghi

            4'h1: // Đọc từ 0x1000_1xxx
                o_data_out = o_io_ledg; // Đọc lại giá trị đã ghi

            4'h4: // Đọc từ 0x1000_4xxx
                o_data_out = o_io_lcd; // Đọc lại giá trị đã ghi
            default:
                o_data_out = 32'b0;
        endcase

    end
endmodule