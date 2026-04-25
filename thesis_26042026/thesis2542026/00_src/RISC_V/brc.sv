module brc (
    input  logic [31:0] i_rs1_data,     
    input  logic [31:0] i_rs2_data,     
    input  logic        i_br_un,      
    output logic        o_br_equal,      
    output logic        o_br_less      
);

    logic [31:0] tmp; // result of sub (rs1 - rs2)
    logic [31:0] rs2_b2; 
    logic carry;
    
    cla_32bit subtractor (
        .i_a(i_rs1_data),
        .i_b(rs2_b2),
        .i_ci(1'b1),        
        .o_s(tmp),         
        .o_co(carry)        
    );
    
    assign rs2_b2 = ~i_rs2_data;

    always_comb begin

        // compare =: xor each bit (if equal = 32'h0) -> or reduction: 32 bit to 1 bit, if all bit is 0 = 0, have 1 in any where = 1 => not equal
        o_br_equal = ~( | (i_rs1_data ^ i_rs2_data) );

        // compare <
        if (i_br_un) begin
            //unsigned
            o_br_less = ~carry; // if carry = 0 => o_br_less = 1 
            //if rs1 > rs2 then carry = 1 because no borrow
        end else begin
            //signed 
            if (i_rs1_data[31] ^ i_rs2_data[31]) begin
                o_br_less = i_rs1_data[31]; // if rs1 < 0, o_br_less = 1
            end else begin
                o_br_less = tmp[31]; // if rs1 >= 0, o_br_less = carry
            end
        end
    end

endmodule