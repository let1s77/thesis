module ipu_bram_reader (
    input               clk,
    input               rst_n,
    input               start,
    input      [31:0]   base_addr,
    input      [15:0]   img_width,
    input      [15:0]   img_height,
    input      [15:0]   img_stride,   // byte stride
    output reg          busy,
    output reg          frame_done,

    // BRAM read port
    output reg          bram_en,
    output reg [15:0]   bram_addr,
    input      [31:0]   bram_rdata,

    // Stream output to haze_removal_top
    output reg          pre_frame_vsync,
    output reg          pre_frame_href,
    output reg          pre_frame_clken,
    output reg          pre_frame_end,
    output reg [23:0]   pre_img
);

    reg         running;
    reg [15:0]  x_cnt;
    reg [15:0]  y_cnt;
    reg [15:0]  row_word_stride;
    reg [15:0]  pixel_word_offset;
    reg [15:0]  base_word_addr;
    reg         pending_valid;
    reg [15:0]  pending_x;
    reg [15:0]  pending_y;
    reg         start_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            running           <= 1'b0;
            busy              <= 1'b0;
            frame_done        <= 1'b0;
            bram_en           <= 1'b0;
            bram_addr         <= 16'd0;
            pre_frame_vsync   <= 1'b0;
            pre_frame_href    <= 1'b0;
            pre_frame_clken   <= 1'b0;
            pre_frame_end     <= 1'b0;
            pre_img           <= 24'd0;
            x_cnt             <= 16'd0;
            y_cnt             <= 16'd0;
            row_word_stride   <= 16'd0;
            pixel_word_offset <= 16'd0;
            base_word_addr    <= 16'd0;
            pending_valid     <= 1'b0;
            pending_x         <= 16'd0;
            pending_y         <= 16'd0;
            start_d           <= 1'b0;
        end else begin
            start_d        <= start;
            frame_done     <= 1'b0;
            pre_frame_vsync<= 1'b0;
            pre_frame_href <= 1'b0;
            pre_frame_clken<= 1'b0;
            pre_frame_end  <= 1'b0;
            bram_en        <= 1'b0;

            if (pending_valid) begin
                pre_frame_href  <= 1'b1;
                pre_frame_clken <= 1'b1;
                pre_img         <= bram_rdata[23:0];

                if ((pending_x == 16'd0) && (pending_y == 16'd0))
                    pre_frame_vsync <= 1'b1;

                if ((pending_x == (img_width - 1'b1)) && (pending_y == (img_height - 1'b1))) begin
                    pre_frame_end <= 1'b1;
                    frame_done    <= 1'b1;
                    busy          <= 1'b0;
                end
            end

            pending_valid <= 1'b0;

            if (start && !start_d && !running) begin
                running         <= 1'b1;
                busy            <= 1'b1;
                x_cnt           <= 16'd0;
                y_cnt           <= 16'd0;
                pixel_word_offset <= 16'd0;
                base_word_addr  <= base_addr[17:2]; // 32-bit word address
                row_word_stride <= img_stride[15:2];
            end else if (running) begin
                bram_en         <= 1'b1;
                bram_addr       <= base_word_addr + (y_cnt * row_word_stride) + x_cnt;

                pending_valid   <= 1'b1;
                pending_x       <= x_cnt;
                pending_y       <= y_cnt;

                if (x_cnt == (img_width - 1'b1)) begin
                    x_cnt <= 16'd0;
                    if (y_cnt == (img_height - 1'b1)) begin
                        y_cnt      <= 16'd0;
                        running    <= 1'b0;
                    end else begin
                        y_cnt <= y_cnt + 1'b1;
                    end
                end else begin
                    x_cnt <= x_cnt + 1'b1;
                end
            end
        end
    end

endmodule
