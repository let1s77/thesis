`include "ipu_addr_map.vh"

module ipu_top (
    input               clk,
    input               rst_n,

    // Simplified register write interface
    input               reg_wr_en,
    input               reg_rd_en,
    input      [31:0]   reg_addr,
    input      [31:0]   reg_wdata,
    output reg [31:0]   reg_rdata,

    // Simplified system access to IMG_IN BRAM
    input               img_in_sys_en,
    input               img_in_sys_we,
    input      [15:0]   img_in_sys_addr,
    input      [31:0]   img_in_sys_wdata,
    output     [31:0]   img_in_sys_rdata,

    // Simplified system access to IMG_OUT BRAM
    input               img_out_sys_en,
    input               img_out_sys_we,
    input      [15:0]   img_out_sys_addr,
    input      [31:0]   img_out_sys_wdata,
    output     [31:0]   img_out_sys_rdata,

    // IRQ
    output              ipu_irq
);

    // -------------------------------------------------------------------------
    // IPU registers
    // -------------------------------------------------------------------------
    reg [31:0] r_ipu_ctrl;
    reg [31:0] r_ipu_status;
    reg [31:0] r_ipu_src_addr;
    reg [31:0] r_ipu_dst_addr;
    reg [31:0] r_ipu_tmp_addr;
    reg [31:0] r_ipu_img_width;
    reg [31:0] r_ipu_img_height;
    reg [31:0] r_ipu_img_stride;
    reg [31:0] r_ipu_img_format;
    reg [31:0] r_ipu_param_0;
    reg [31:0] r_ipu_param_1;
    reg [31:0] r_ipu_param_2;
    reg [31:0] r_ipu_irq_en;
    reg [31:0] r_ipu_irq_status;
    reg [31:0] r_ipu_debug;
    reg [31:0] r_ipu_id;

    wire ipu_en    = r_ipu_ctrl[`IPU_CTRL_EN_BIT];
    wire ipu_start = r_ipu_ctrl[`IPU_CTRL_START_BIT];
    wire cont_mode = r_ipu_ctrl[`IPU_CTRL_CONT_MODE_BIT];

    // -------------------------------------------------------------------------
    // Reader / writer / control signals
    // -------------------------------------------------------------------------
    wire        reader_start;
    wire        reader_busy;
    wire        reader_done;
    wire        writer_start;
    wire        writer_busy;
    wire        writer_done;

    wire        idle;
    wire        busy;
    wire        done;
    wire        error;
    wire [3:0]  fsm_state;

    wire        pre_frame_vsync;
    wire        pre_frame_href;
    wire        pre_frame_clken;
    wire        pre_frame_end;
    wire [23:0] pre_img;

    wire        post_frame_vsync;
    wire        post_frame_href;
    wire        post_frame_clken;
    wire [23:0] post_img;

    wire        in_bram_en;
    wire [15:0] in_bram_addr;
    wire [31:0] in_bram_rdata;

    wire        out_bram_we;
    wire [15:0] out_bram_addr;
    wire [31:0] out_bram_wdata;

    wire        dark_enable;
    wire        sky_enable;
    wire        trans_enable;
    wire        adc_enable;
    wire        recovery_enable;

    wire        bank_swap;
    wire        bank_wr_clear;
    wire        bank_rd_clear;
    wire        bank_rd_en;

    wire        dark_done;
    wire        sky_done;
    wire        trans_done;
    wire        adc_done;
    wire        recovery_done;

    // -------------------------------------------------------------------------
    // Register write
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_ipu_ctrl       <= 32'd0;
            r_ipu_status     <= 32'd0;
            r_ipu_src_addr   <= `IMG_IN_BUF_BASE;
            r_ipu_dst_addr   <= `IMG_OUT_BUF_BASE;
            r_ipu_tmp_addr   <= `IMG_TMP_BUF_BASE;
            r_ipu_img_width  <= 32'd128;
            r_ipu_img_height <= 32'd128;
            r_ipu_img_stride <= 32'd512;
            r_ipu_img_format <= 32'd1;
            r_ipu_param_0    <= 32'd0;
            r_ipu_param_1    <= 32'd0;
            r_ipu_param_2    <= 32'd0;
            r_ipu_irq_en     <= 32'd0;
            r_ipu_irq_status <= 32'd0;
            r_ipu_debug      <= 32'd0;
            r_ipu_id         <= 32'h4950_5531; // "IPU1"
        end else begin
            r_ipu_status[`IPU_STATUS_IDLE_BIT]  <= idle;
            r_ipu_status[`IPU_STATUS_BUSY_BIT]  <= busy;
            r_ipu_status[`IPU_STATUS_DONE_BIT]  <= done;
            r_ipu_status[`IPU_STATUS_ERROR_BIT] <= error;
            r_ipu_debug[3:0]                    <= fsm_state;

            if (done)
                r_ipu_irq_status[0] <= 1'b1;

            if (reg_wr_en) begin
                case (reg_addr)
                    `IPU_CTRL:       r_ipu_ctrl       <= reg_wdata;
                    `IPU_SRC_ADDR:   r_ipu_src_addr   <= reg_wdata;
                    `IPU_DST_ADDR:   r_ipu_dst_addr   <= reg_wdata;
                    `IPU_TMP_ADDR:   r_ipu_tmp_addr   <= reg_wdata;
                    `IPU_IMG_WIDTH:  r_ipu_img_width  <= reg_wdata;
                    `IPU_IMG_HEIGHT: r_ipu_img_height <= reg_wdata;
                    `IPU_IMG_STRIDE: r_ipu_img_stride <= reg_wdata;
                    `IPU_IMG_FORMAT: r_ipu_img_format <= reg_wdata;
                    `IPU_PARAM_0:    r_ipu_param_0    <= reg_wdata;
                    `IPU_PARAM_1:    r_ipu_param_1    <= reg_wdata;
                    `IPU_PARAM_2:    r_ipu_param_2    <= reg_wdata;
                    `IPU_IRQ_EN:     r_ipu_irq_en     <= reg_wdata;
                    `IPU_IRQ_STATUS: r_ipu_irq_status <= r_ipu_irq_status & ~reg_wdata; // W1C
                    default: ;
                endcase
            end
        end
    end

    // -------------------------------------------------------------------------
    // Register read
    // -------------------------------------------------------------------------
    always_comb begin
        reg_rdata = 32'd0;
        if (reg_rd_en) begin
            case (reg_addr)
                `IPU_CTRL:       reg_rdata = r_ipu_ctrl;
                `IPU_STATUS:     reg_rdata = r_ipu_status;
                `IPU_SRC_ADDR:   reg_rdata = r_ipu_src_addr;
                `IPU_DST_ADDR:   reg_rdata = r_ipu_dst_addr;
                `IPU_TMP_ADDR:   reg_rdata = r_ipu_tmp_addr;
                `IPU_IMG_WIDTH:  reg_rdata = r_ipu_img_width;
                `IPU_IMG_HEIGHT: reg_rdata = r_ipu_img_height;
                `IPU_IMG_STRIDE: reg_rdata = r_ipu_img_stride;
                `IPU_IMG_FORMAT: reg_rdata = r_ipu_img_format;
                `IPU_PARAM_0:    reg_rdata = r_ipu_param_0;
                `IPU_PARAM_1:    reg_rdata = r_ipu_param_1;
                `IPU_PARAM_2:    reg_rdata = r_ipu_param_2;
                `IPU_IRQ_EN:     reg_rdata = r_ipu_irq_en;
                `IPU_IRQ_STATUS: reg_rdata = r_ipu_irq_status;
                `IPU_DEBUG:      reg_rdata = r_ipu_debug;
                `IPU_ID:         reg_rdata = r_ipu_id;
                default:         reg_rdata = 32'd0;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Global BRAMs
    // -------------------------------------------------------------------------
    img_in_bram u_img_in_bram (
        .clk       (clk),
        .sys_en    (img_in_sys_en),
        .sys_we    (img_in_sys_we),
        .sys_addr  (img_in_sys_addr),
        .sys_wdata (img_in_sys_wdata),
        .sys_rdata (img_in_sys_rdata),
        .ipu_en    (in_bram_en),
        .ipu_addr  (in_bram_addr),
        .ipu_rdata (in_bram_rdata)
    );

    img_out_bram u_img_out_bram (
        .clk       (clk),
        .sys_en    (img_out_sys_en),
        .sys_we    (img_out_sys_we),
        .sys_addr  (img_out_sys_addr),
        .sys_wdata (img_out_sys_wdata),
        .sys_rdata (img_out_sys_rdata),
        .ipu_we    (out_bram_we),
        .ipu_addr  (out_bram_addr),
        .ipu_wdata (out_bram_wdata)
    );

    // -------------------------------------------------------------------------
    // Control logic
    // -------------------------------------------------------------------------
    ipu_control_logic u_ipu_control_logic (
        .clk            (clk),
        .rst_n          (rst_n),
        .ipu_en         (ipu_en),
        .ipu_start      (ipu_start),
        .cont_mode      (cont_mode),
        .reader_busy    (reader_busy),
        .reader_done    (reader_done),
        .writer_busy    (writer_busy),
        .writer_done    (writer_done),
        .dark_done      (dark_done),
        .sky_done       (sky_done),
        .trans_done     (trans_done),
        .adc_done       (adc_done),
        .recovery_done  (recovery_done),
        .reader_start   (reader_start),
        .writer_start   (writer_start),
        .dark_enable    (dark_enable),
        .sky_enable     (sky_enable),
        .trans_enable   (trans_enable),
        .adc_enable     (adc_enable),
        .recovery_enable(recovery_enable),
        .bank_swap      (bank_swap),
        .bank_wr_clear  (bank_wr_clear),
        .bank_rd_clear  (bank_rd_clear),
        .bank_rd_en     (bank_rd_en),
        .idle           (idle),
        .busy           (busy),
        .done           (done),
        .error          (error),
        .fsm_state      (fsm_state)
    );

    // -------------------------------------------------------------------------
    // Reader
    // -------------------------------------------------------------------------
    ipu_bram_reader u_ipu_bram_reader (
        .clk             (clk),
        .rst_n           (rst_n),
        .start           (reader_start),
        .base_addr       (r_ipu_src_addr),
        .img_width       (r_ipu_img_width[15:0]),
        .img_height      (r_ipu_img_height[15:0]),
        .img_stride      (r_ipu_img_stride[15:0]),
        .busy            (reader_busy),
        .frame_done      (reader_done),
        .bram_en         (in_bram_en),
        .bram_addr       (in_bram_addr),
        .bram_rdata      (in_bram_rdata),
        .pre_frame_vsync (pre_frame_vsync),
        .pre_frame_href  (pre_frame_href),
        .pre_frame_clken (pre_frame_clken),
        .pre_frame_end   (pre_frame_end),
        .pre_img         (pre_img)
    );

    // -------------------------------------------------------------------------
    // Stage-based haze removal hierarchy
    // -------------------------------------------------------------------------
    haze_removal_top u_haze_removal_top (
        .clk              (clk),
        .rst_n            (rst_n),
        .i_src_valid      (pre_frame_clken),
        .i_src_frame_start(pre_frame_vsync),
        .i_src_frame_end  (pre_frame_end),
        .i_src_rgb        (pre_img),
        .dark_enable      (dark_enable),
        .sky_enable       (sky_enable),
        .trans_enable     (trans_enable),
        .adc_enable       (adc_enable),
        .recovery_enable  (recovery_enable),
        .bank_swap        (bank_swap),
        .bank_wr_clear    (bank_wr_clear),
        .bank_rd_clear    (bank_rd_clear),
        .bank_rd_en       (bank_rd_en),
        .dark_done        (dark_done),
        .sky_done         (sky_done),
        .trans_done       (trans_done),
        .adc_done         (adc_done),
        .recovery_done    (recovery_done),
        .post_frame_vsync (post_frame_vsync),
        .post_frame_href  (post_frame_href),
        .post_frame_clken (post_frame_clken),
        .post_img         (post_img)
    );

    // -------------------------------------------------------------------------
    // Writer
    // -------------------------------------------------------------------------
    ipu_bram_writer u_ipu_bram_writer (
        .clk              (clk),
        .rst_n            (rst_n),
        .start            (writer_start),
        .base_addr        (r_ipu_dst_addr),
        .img_width        (r_ipu_img_width[15:0]),
        .img_height       (r_ipu_img_height[15:0]),
        .img_stride       (r_ipu_img_stride[15:0]),
        .busy             (writer_busy),
        .frame_done       (writer_done),
        .post_frame_vsync (post_frame_vsync),
        .post_frame_href  (post_frame_href),
        .post_frame_clken (post_frame_clken),
        .post_img         (post_img),
        .bram_we          (out_bram_we),
        .bram_addr        (out_bram_addr),
        .bram_wdata       (out_bram_wdata)
    );

    assign ipu_irq = r_ipu_irq_en[0] & r_ipu_irq_status[0];

endmodule
