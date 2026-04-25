module ipu_bram_writer (
    input               clk,
    input               rst_n,
    input               start,
    input      [31:0]   base_addr,
    input      [15:0]   img_width,
    input      [15:0]   img_height,
    input      [15:0]   img_stride,   // byte stride
    output reg          busy,
    output reg          frame_done,

    // Stream input from haze_removal_top
    input               post_frame_vsync,
    input               post_frame_href,
    input               post_frame_clken,
    input      [23:0]   post_img,

    // BRAM write port
    output reg          bram_we,
    output reg [15:0]   bram_addr,
    output reg [31:0]   bram_wdata
);

    reg         running;
    reg [15:0]  x_cnt;
    reg [15:0]  y_cnt;
    reg [15:0]  row_word_stride;
    reg [15:0]  base_word_addr;
    reg [15:0]  row_base_addr;
    reg         start_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            running         <= 1'b0;
            busy            <= 1'b0;
            frame_done      <= 1'b0;
            bram_we         <= 1'b0;
            bram_addr       <= 16'd0;
            bram_wdata      <= 32'd0;
            x_cnt           <= 16'd0;
            y_cnt           <= 16'd0;
            row_word_stride <= 16'd0;
            base_word_addr  <= 16'd0;
            row_base_addr   <= 16'd0;
            start_d         <= 1'b0;
        end else begin
            start_d     <= start;
            frame_done  <= 1'b0;
            bram_we     <= 1'b0;

            if (start && !start_d && !running) begin
                running         <= 1'b1;
                busy            <= 1'b1;
                x_cnt           <= 16'd0;
                y_cnt           <= 16'd0;
                base_word_addr  <= base_addr[17:2];
                row_word_stride <= img_stride[15:2];
                row_base_addr   <= base_addr[17:2];
            end else if (running) begin
                if (post_frame_href && post_frame_clken) begin
                    bram_we    <= 1'b1;
                    bram_addr  <= row_base_addr + x_cnt;
                    bram_wdata <= {8'h00, post_img};

                    if (x_cnt == (img_width - 1'b1)) begin
                        x_cnt <= 16'd0;
                        if (y_cnt == (img_height - 1'b1)) begin
                            y_cnt      <= 16'd0;
                            running    <= 1'b0;
                            busy       <= 1'b0;
                            frame_done <= 1'b1;
                            row_base_addr <= base_word_addr;
                        end else begin
                            y_cnt <= y_cnt + 1'b1;
                            row_base_addr <= row_base_addr + row_word_stride;
                        end
                    end else begin
                        x_cnt <= x_cnt + 1'b1;
                    end
                end
            end
        end
    end

endmodule