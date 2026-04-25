module atmospheric_light(
    input  logic        i_clk,
    input  logic        i_rst_n,
    input  logic        i_frame_start,
    input  logic        i_frame_end,
    input  logic        i_valid,
    input  logic [23:0] i_rgb,
    input  logic [7:0]  i_dark_ch,
    
    output logic [7:0]  o_A_R,
    output logic [7:0]  o_A_G,
    output logic [7:0]  o_A_B,
    output logic        o_valid
);

    //==========================================================================
    // Internal Registers
    //==========================================================================
    logic [7:0]  max_dark_reg;        // Max dark channel found so far
    logic [15:0] max_intensity_reg;   // Intensity of pixel with max dark_ch (tie-breaker)
    logic [7:0]  A_R_reg, A_G_reg, A_B_reg;  // Best atmospheric light candidate
    
    //==========================================================================
    // Combinational: Current pixel intensity (R + G + B)
    //==========================================================================
    logic [15:0] current_intensity;
    assign current_intensity = {8'd0, i_rgb[7:0]} + {8'd0, i_rgb[15:8]} + {8'd0, i_rgb[23:16]};

    //==========================================================================
    // Frame Accumulator Logic
    // Tìm pixel có dark_ch cao nhất, tie-break bằng intensity
    //==========================================================================
    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            max_dark_reg      <= 8'd0;
            max_intensity_reg <= 16'd0;
            A_R_reg           <= 8'd0;
            A_G_reg           <= 8'd0;
            A_B_reg           <= 8'd0;
        end 
        else if (i_frame_start) begin
            // Reset accumulator cho frame mới
            max_dark_reg      <= 8'd0;
            max_intensity_reg <= 16'd0;
            A_R_reg           <= 8'd0;
            A_G_reg           <= 8'd0;
            A_B_reg           <= 8'd0;
        end
        else if (i_valid) begin
            // So sánh và cập nhật nếu:
            // 1. dark_ch > max hiện tại, HOẶC
            // 2. dark_ch == max nhưng intensity > max_intensity (tie-breaker)
            if ((i_dark_ch > max_dark_reg) || 
                (i_dark_ch == max_dark_reg && current_intensity > max_intensity_reg)) begin
                max_dark_reg      <= i_dark_ch;
                max_intensity_reg <= current_intensity; 
                A_R_reg           <= i_rgb[7:0];
                A_G_reg           <= i_rgb[15:8];
                A_B_reg           <= i_rgb[23:16];
            end
        end
    end

    //==========================================================================
    // Output Logic
    // Output A khi frame kết thúc
    //==========================================================================
    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            o_A_R   <= 8'd0;
            o_A_G   <= 8'd0;
            o_A_B   <= 8'd0;
            o_valid <= 1'b0;
        end
        else if (i_frame_end) begin
            // Latch kết quả cuối cùng
            o_A_R   <= A_R_reg;
            o_A_G   <= A_G_reg;
            o_A_B   <= A_B_reg;
            o_valid <= 1'b1;
        end
        else if (i_frame_start) begin
            // Clear output khi frame mới bắt đầu
            o_valid <= 1'b0;
        end
    end

endmodule