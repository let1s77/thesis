//==============================================================================
// Module: haze_removal_top
// Description:
//   Interface-only wrapper for haze removal pipeline.
//   All implementation logic is moved to haze_removal_core.
//==============================================================================

module haze_removal_top #(
    parameter int IMG_WIDTH  = 128,
    parameter int IMG_HEIGHT = 128,
    parameter int ADDR_WIDTH = 14,
    parameter int ADC_PICK_INDEX = 1,
    parameter logic [7:0] OMEGA_Q8 = 8'd255,
    parameter logic [7:0] T_MIN    = 8'd15,
    parameter logic [7:0] LAMBDA_Q8 = 8'd51
)(
    input  logic        clk,
    input  logic        rst_n,

    input  logic        i_src_valid,
    input  logic        i_src_frame_start,
    input  logic        i_src_frame_end,
    input  logic [23:0] i_src_rgb,

    input  logic        dark_enable,
    input  logic        sky_enable,
    input  logic        trans_enable,
    input  logic        adc_enable,
    input  logic        recovery_enable,

    input  logic        bank_swap,
    input  logic        bank_wr_clear,
    input  logic        bank_rd_clear,
    input  logic        bank_rd_en,

    output logic        dark_done,
    output logic        sky_done,
    output logic        trans_done,
    output logic        adc_done,
    output logic        recovery_done,

    output logic        post_frame_vsync,
    output logic        post_frame_href,
    output logic        post_frame_clken,
    output logic [23:0] post_img
);

    haze_removal_core #(
        .IMG_WIDTH(IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT),
        .ADDR_WIDTH(ADDR_WIDTH),
        .ADC_PICK_INDEX(ADC_PICK_INDEX),
        .OMEGA_Q8(OMEGA_Q8),
        .T_MIN(T_MIN),
        .LAMBDA_Q8(LAMBDA_Q8)
    ) u_core (
        .clk(clk),
        .rst_n(rst_n),
        .i_src_valid(i_src_valid),
        .i_src_frame_start(i_src_frame_start),
        .i_src_frame_end(i_src_frame_end),
        .i_src_rgb(i_src_rgb),
        .dark_enable(dark_enable),
        .sky_enable(sky_enable),
        .trans_enable(trans_enable),
        .adc_enable(adc_enable),
        .recovery_enable(recovery_enable),
        .bank_swap(bank_swap),
        .bank_wr_clear(bank_wr_clear),
        .bank_rd_clear(bank_rd_clear),
        .bank_rd_en(bank_rd_en),
        .dark_done(dark_done),
        .sky_done(sky_done),
        .trans_done(trans_done),
        .adc_done(adc_done),
        .recovery_done(recovery_done),
        .post_frame_vsync(post_frame_vsync),
        .post_frame_href(post_frame_href),
        .post_frame_clken(post_frame_clken),
        .post_img(post_img)
    );

endmodule
