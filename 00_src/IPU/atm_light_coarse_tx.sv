//==============================================================================
// Module: atm_light_coarse_tx
// Description: Coarse Transmission Map and Atmospheric Light Estimation
//              Pipeline
//
// Dataflow (2-pass architecture):
//   Pass 1: i_color -> dark_channel -> atmospheric_light -> latch A_R/A_G/A_B
//   Pass 2: i_color -> dark_channel -> sky_recognition
//                   -> estimate_transmission (using A from pass 1)
//                   -> bank_pingpong_stream (write)
//           swap -> bank read -> o_rd_data
//
// Sub-modules:
//   - grayscale          : RGB -> gray (for sky_recognition)
//   - dark_channel       : RGB -> min(R,G,B) (simple mode, no spatial filter)
//   - atmospheric_light  : frame scan -> find A (needs frame_start/end)
//   - sky_recognition    : gray/dark_ch > A0 -> sky flag
//   - estimate_transmission : coarse transmission map
//   - bank_pingpong_stream  : double-buffered BRAM storage
//
// Control signals are driven by testbench or outer control logic.
// This is a structural wrapper for integration verification.
//==============================================================================

module atm_light_coarse_tx #(
    parameter int IMG_WIDTH  = 128,
    parameter int IMG_HEIGHT = 128,
    parameter int ADDR_WIDTH = 14,   // ceil(log2(128*128)) = 14

    // estimate_transmission params
    parameter logic [7:0] OMEGA_Q8 = 8'hFF,
    parameter logic [7:0] T_MIN    = 8'd15
)(
    input  logic        clk,
    input  logic        rst_n,

    // ---- Pixel input stream ----
    input  logic        i_valid,
    input  logic [23:0] i_color,

    // ---- Frame control (for atmospheric_light) ----
    input  logic        i_frame_start,
    input  logic        i_frame_end,

    // ---- Sky recognition config ----
    input  logic [7:0]  i_A0,          // sky threshold
    input  logic        i_use_dark,    // 0: use gray, 1: use dark_ch

    // ---- Estimate transmission config ----
    input  logic        i_use_sky,
    input  logic [7:0]  i_t_sky,

    // ---- Bank ping-pong control ----
    input  logic        i_bank_swap,
    input  logic        i_bank_wr_clear,
    input  logic        i_bank_rd_clear,
    input  logic        i_bank_rd_en,

    // ---- Atmospheric light output (valid after pass 1 frame_end) ----
    output logic [7:0]  o_A_R,
    output logic [7:0]  o_A_G,
    output logic [7:0]  o_A_B,
    output logic        o_A_valid,

    // ---- Dark channel output (direct) ----
    output logic        o_dark_valid,
    output logic [7:0]  o_dark_ch,

    // ---- Sky recognition output ----
    output logic        o_sky_valid,
    output logic        o_sky,

    // ---- Estimate transmission output ----
    output logic        o_tx_valid,
    output logic [7:0]  o_tx,

    // ---- Bank read output ----
    output logic [7:0]            o_bank_rd_data,
    output logic [ADDR_WIDTH-1:0] o_bank_rd_addr,
    output logic                  o_bank_wr_sel,
    output logic                  o_bank_rd_sel
);

    // ================================================================
    // Pipeline Alignment Delay Registers
    // ================================================================
    // dark_channel SIMPLE_MODE has o_valid hardwired to 1 (always high).
    // We must track valid ourselves.
    //
    // dark_channel + grayscale: 1-cycle latency (registered outputs)
    //   -> valid_dc aligns with dark_ch/gray output
    //   -> i_color_d1 aligns RGB with dark_ch/gray output
    // sky_recognition: +1 cycle latency
    //   -> i_color_d2 aligns RGB with sky output
    //
    // Timeline:
    //   Cycle N  : i_valid, i_color[N]
    //   Cycle N+1: valid_dc, dark_ch[N], gray[N], i_color_d1[N]
    //   Cycle N+2: sky_valid, sky[N], i_color_d2[N]
    // ================================================================
    logic [23:0] i_color_d1, i_color_d2;
    logic        valid_dc;
    logic        frame_end_d1;
    logic        frame_end_d2;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            i_color_d1 <= '0;
            i_color_d2 <= '0;
            valid_dc   <= 1'b0;
            frame_end_d1   <= 1'b0;
            frame_end_d2   <= 1'b0;
        end else begin
            valid_dc   <= i_valid;
            i_color_d1 <= i_color;
            i_color_d2 <= i_color_d1;
            frame_end_d1   <= i_frame_end;
            frame_end_d2   <= frame_end_d1;
        end
    end

    logic [7:0] gray_out;

    grayscale u_grayscale (
        .clk   (clk),
        .rst_n (rst_n),
        .mode  (2'b10),
        .color (i_color),
        .gray  (gray_out)
    );

    logic dc_valid_unused;
    dark_channel #(
        .IMG_WIDTH             (IMG_WIDTH),
        .ENABLE_SPATIAL_FILTER (0)
    ) u_dark_channel (
        .i_clk     (clk),
        .i_rst_n   (rst_n),
        .i_valid   (i_valid),
        .i_color   (i_color),
        .o_valid   (dc_valid_unused),
        .o_dark_ch (o_dark_ch)
    );

    assign o_dark_valid = valid_dc;

    atmospheric_light u_atm_light (
        .i_clk         (clk),
        .i_rst_n       (rst_n),
        .i_frame_start (i_frame_start),
        .i_frame_end   (frame_end_d2),
        .i_valid       (valid_dc),
        .i_rgb         (i_color_d1),
        .i_dark_ch     (o_dark_ch),
        .o_A_R         (o_A_R),
        .o_A_G         (o_A_G),
        .o_A_B         (o_A_B),
        .o_valid       (o_A_valid)
    );

    sky_recognition u_sky_recog (
        .i_clk      (clk),
        .i_rst_n    (rst_n),
        .i_valid    (valid_dc),
        .i_gray     (gray_out),
        .i_dark_ch  (o_dark_ch),
        .i_A0       (i_A0),
        .i_use_dark (i_use_dark),
        .o_valid    (o_sky_valid),
        .o_sky      (o_sky),
        .o_sky_bw   ()
    );

    estimate_transmission #(
        .IMG_WIDTH             (IMG_WIDTH),
        .ENABLE_SPATIAL_FILTER (1'b0),
        .OMEGA_Q8              (OMEGA_Q8),
        .T_MIN                 (T_MIN)
    ) u_est_tx (
        .clk       (clk),
        .rst_n     (rst_n),
        .i_valid   (o_sky_valid),
        .i_color   (i_color_d2),
        .i_A_r     (o_A_R),
        .i_A_g     (o_A_G),
        .i_A_b     (o_A_B),
        .i_sky     (o_sky),
        .i_use_sky (i_use_sky),
        .i_t_sky   (i_t_sky),
        .o_valid   (o_tx_valid),
        .o_t       (o_tx)
    );

    bank_pingpong_stream #(
        .DATA_WIDTH (8),
        .IMG_WIDTH  (IMG_WIDTH),
        .IMG_HEIGHT (IMG_HEIGHT),
        .ADDR_WIDTH (ADDR_WIDTH)
    ) u_bank_tx (
        .clk           (clk),
        .rst_n         (rst_n),
        .i_swap        (i_bank_swap),
        .i_wr_clear    (i_bank_wr_clear),
        .i_wr_valid    (o_tx_valid),
        .i_wr_data     (o_tx),
        .i_rd_clear    (i_bank_rd_clear),
        .i_rd_en       (i_bank_rd_en),
        .o_rd_data     (o_bank_rd_data),
        .o_rd_addr     (o_bank_rd_addr),
        .o_rd_row      (),
        .o_rd_col      (),
        .o_at_top      (),
        .o_at_bottom   (),
        .o_at_left     (),
        .o_at_right    (),
        .o_wr_bank_sel (o_bank_wr_sel),
        .o_rd_bank_sel (o_bank_rd_sel)
    );

endmodule
