module SevenSegment (
    input  [31:0] input_data,
    output logic [6:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5, HEX6, HEX7
);

    logic [3:0] data0, data1, data2, data3, data4, data5, data6, data7;

    localparam logic [6:0] seven_segment [0:15] = '{
        7'b1000000, // 0
        7'b1111001, // 1
        7'b0100100, // 2
        7'b0110000, // 3
        7'b0011001, // 4
        7'b0010010, // 5
        7'b0000010, // 6
        7'b1111000, // 7
        7'b0000000, // 8
        7'b0010000, // 9
        7'b0001000, // A
        7'b0000011, // B
        7'b1000110, // C
        7'b0100001, // D
        7'b0000110, // E
        7'b0001110  // F
    };

    assign {data7, data6, data5, data4, data3, data2, data1, data0} = input_data;

    assign HEX0 = seven_segment[data0];
    assign HEX1 = seven_segment[data1];
    assign HEX2 = seven_segment[data2];
    assign HEX3 = seven_segment[data3];
    assign HEX4 = seven_segment[data4];
    assign HEX5 = seven_segment[data5];
    assign HEX6 = seven_segment[data6];
    assign HEX7 = seven_segment[data7];
    
endmodule