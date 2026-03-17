module lsu #(
    parameter DEPTH =  2048 // Depth of the memory, default is 16384
)(
    input logic i_clk, i_reset,
    input logic i_lsu_wren,
    input logic [3:0] i_byte_num, 
    input logic [31:0] i_st_data,
    input logic [31:0] i_lsu_addr,
    input logic [31:0] i_io_sw, 
    output logic [31:0] o_ld_data,
    output logic [31:0] o_io_ledr, // LEDR output
    output logic [31:0] o_io_ledg,
    output logic [31:0] o_io_lcd, // LCD output
    output logic [6:0] o_io_hex0, o_io_hex1, o_io_hex2, o_io_hex3, o_io_hex4, o_io_hex5, o_io_hex6, o_io_hex7
);

    logic [3:0] byte_mask;        
    logic [31:0] mem_rdata; //data from memory
    logic [31:0] mem_rdata_next; //for misaligned
    logic [31:0] io_rdata; 
    logic [31:0] sw_reg;   // store switch input
    logic [1:0]  addr_off; // address offset
    logic [31:0] rdata_shift; // shifted read data
    logic [31:0] wdata_shift; // shifted write data
    logic [63:0] mem_double; //  64-bit for misaligned access

	logic is_mem, is_peri, is_sw;


	// Memory: 0x0000_0000 - 0x0000_7FFF
	// I/O:    0x1000_xxxx
	// Switch: 0x1001_xxxx

	// Use XOR and NOR reduction to check equality without == operator
	assign is_mem  = ~(| (i_lsu_addr[31:16] ^ 16'h0000));  // XOR will be all 0s if equal, then NOR reduction
	assign is_peri = ~(| (i_lsu_addr[31:16] ^ 16'h1000));
	assign is_sw   = ~(| (i_lsu_addr[31:16] ^ 16'h1001));
    assign addr_off = i_lsu_addr[1:0];

    memory #(.DEPTH(DEPTH)
    //       .MEM_FILE(MEM_FILE)
     ) mem(
        .i_clk(i_clk),
        .i_reset(i_reset),
        .i_addr(i_lsu_addr[$clog2(DEPTH)-1:0]), 
        .i_wdata(wdata_shift),
        .i_bmask(byte_mask),
        .i_wren(i_lsu_wren & is_mem),
        .o_rdata(mem_rdata),
        .o_rdata_next(mem_rdata_next)
     );

    peripherals peripherals(
        .i_clk(i_clk),
        .i_reset(i_reset),
        .i_peri_addr(i_lsu_addr[15:0]), 
        .i_data_in(i_st_data),
        .i_write_en(i_lsu_wren & is_peri),
        .i_io_sw(i_io_sw),
        .o_data_out(io_rdata),
        .o_io_ledr(o_io_ledr),
        .o_io_ledg(o_io_ledg),
        .o_io_lcd(o_io_lcd),
        .o_io_hex0(o_io_hex0), 
        .o_io_hex1(o_io_hex1), 
        .o_io_hex2(o_io_hex2), 
        .o_io_hex3(o_io_hex3), 
        .o_io_hex4(o_io_hex4), 
        .o_io_hex5(o_io_hex5),  
        .o_io_hex6(o_io_hex6), 
        .o_io_hex7(o_io_hex7)
    );

    always_ff @(posedge i_clk or negedge i_reset) begin
        if (!i_reset) begin
            sw_reg <= 32'h0;  
        end else begin
            sw_reg <= i_io_sw;   
        end
    end

    //trade off bewteen byte_num and byte_mask
    always_comb begin
        case (i_byte_num)
            4'b0001: begin // store byte
                case(addr_off)
                    2'b00: begin
                        wdata_shift = {24'b0, i_st_data[7:0]};
                        byte_mask = 4'b0001;
                    end

                    2'b01: begin
                        // Ghi vào byte 1: data[7:0] vào vị trí byte 1
                        wdata_shift = {16'b0, i_st_data[7:0], 8'b0};
                        byte_mask = 4'b0010;
                    end

                    2'b10: begin
                        // Ghi vào byte 2: data[7:0] vào vị trí byte 2
                        wdata_shift = {8'b0, i_st_data[7:0], 16'b0};
                        byte_mask = 4'b0100;
                    end

                    2'b11: begin
                        // Ghi vào byte 3: data[7:0] vào vị trí byte 3
                        wdata_shift = {i_st_data[7:0], 24'b0};
                        byte_mask   = 4'b1000;
                    end
                    default: begin
                        wdata_shift = 32'b0;
                    end
                endcase
            end

            4'b0011: begin //store half word
                case(addr_off)
                    2'b00: begin
                        wdata_shift = {16'b0, i_st_data[15:0]};
                        byte_mask = 4'b0011;
                    end

                    2'b01: begin //misaligned
                        wdata_shift = {8'b0, i_st_data[15:0], 8'b0};
                        byte_mask = 4'b0110;
                    end

                    2'b10: begin
                        wdata_shift = {i_st_data[15:0], 16'b0};
                        byte_mask = 4'b1100;
                    end

                    2'b11: begin
                        wdata_shift = {i_st_data[7:0], 24'b0};
                        byte_mask   = 4'b1000;
                    end
                    default: begin
                        wdata_shift = 32'b0;
                        byte_mask = 4'b0000;
                    end
                endcase
            end

            4'b1111: begin
                wdata_shift = i_st_data;
                byte_mask = 4'b1111; // sw
            end

            default: begin
                wdata_shift = 32'b0;
                byte_mask = 4'b0000;
            end
        endcase
    end

//select mem and peri
    always_comb begin
        // Combine two words for misaligned access
        mem_double = {mem_rdata_next, mem_rdata};
        
        if (is_mem) begin
            // Shift based on address offset to get aligned data
            rdata_shift = (mem_double >> (8 * addr_off));
        end else if (is_peri) begin
            rdata_shift = io_rdata;
        end else if (is_sw) begin
            rdata_shift = sw_reg;
        end else begin
            rdata_shift = 32'b0; // Địa chỉ không hợp lệ
        end

        case (i_byte_num)
            4'b0001: begin // load byte - sign extended
                o_ld_data = {{24{rdata_shift[7]}}, rdata_shift[7:0]};
            end

            4'b0011: begin // load half word - sign extended
                o_ld_data = {{16{rdata_shift[15]}}, rdata_shift[15:0]};
            end

            4'b0100: begin // lbu - zero extended
                o_ld_data = {24'b0, rdata_shift[7:0]};
            end

            4'b0101: begin // lhu - zero extended
                o_ld_data = {16'b0, rdata_shift[15:0]};
            end
        
            4'b1111: begin // lw
                o_ld_data = rdata_shift;
            end

            default: o_ld_data = 32'b0;

        endcase
    end

endmodule

