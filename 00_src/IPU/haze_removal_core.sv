//==============================================================================
// Module: haze_removal_top
// Description:
//   Hierarchical datapath wrapper for the IPU pipeline.
//
//   Intended hierarchy:
//     haze_removal_top
//       - atm_light_coarse_tx : dark / sky / coarse transmission + tx bank
//       - adc_estimation      : adaptive dark channel from tx bank
//       - t_compute_fuse      : final recovery arithmetic
//
// Notes:
// - This file is a structural skeleton for stage-based integration.
// - For full-frame mode, recovery consumes a per-pixel ADC frame buffer.
// - For tiny debug mode (e.g. 5x5), legacy single-pixel hold behavior is kept
//   for backward compatibility with small-pattern bring-up.
//==============================================================================

module haze_removal_core #(
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

    localparam int FramePixels = IMG_WIDTH * IMG_HEIGHT;
    localparam int AdcFeedPixels = FramePixels + 1;
    localparam int AdcValidPixels = ((IMG_WIDTH > 4) && (IMG_HEIGHT > 4))
                                  ? ((IMG_WIDTH - 4) * (IMG_HEIGHT - 4)) : 1;
    localparam bit UseAdcFrameMap = (FramePixels > 64);
    localparam logic [7:0] RecoveryTxMin = 8'd73;
    localparam int SharpNum = 5;
    localparam int SharpShift = 6;
    localparam int DenseHazeTh = 117;
    localparam int DenseHazeSub = 8;

    logic [7:0] purple_A_r;
    logic [7:0] purple_A_g;
    logic [7:0] purple_A_b;
    logic [7:0] purple_A_max;
    logic       purple_A_valid;
    logic       purple_dark_valid;
    logic [7:0] purple_dark_ch;
    logic       purple_sky_valid;
    logic       purple_sky;
    logic       purple_tx_valid;
    logic [7:0] purple_tx;
    logic [7:0] bank_rd_data;
    logic [ADDR_WIDTH-1:0] bank_rd_addr;
    logic bank_wr_sel;
    logic bank_rd_sel;

    logic       adc_out_valid;
    logic [7:0] adc_out_pix;
    logic [7:0] adc_in_pix;
    logic       adc_done_pulse;
    logic [7:0] adc_dark_hold;
    logic [7:0] adc_dark_raw_for_recovery;
    logic [7:0] adc_dark_for_recovery;
    logic [7:0] adc_min_pix;
    logic [7:0] adc_max_pix;
    logic       adc_rst_n;
    logic       adc_in_valid;
    logic       adc_enable_d;
    integer     adc_in_count;
    integer     adc_out_index;
    integer     adc_latched_index;
    integer     adc_store_count;
    integer     tx_store_count;
    integer     recovery_pix_index;

    logic [7:0] adc_frame_map [FramePixels];
    logic [7:0] tx_frame_map [FramePixels];

    logic       rec_valid;
    logic [7:0] rec_tx_used;
    logic [7:0] rec_r;
    logic [7:0] rec_g;
    logic [7:0] rec_b;

    logic [7:0] tx_for_recovery;
    logic [7:0] tx_adc_for_recovery;
    logic [7:0] tx_hybrid_for_recovery;
    logic       fuse_valid_direct;
    logic [7:0] fuse_tx_used_direct;
    logic [7:0] fuse_r_direct;
    logic [7:0] fuse_g_direct;
    logic [7:0] fuse_b_direct;

    logic       tcf_valid;
    logic [7:0] tcf_tx_raw;
    logic [7:0] tcf_tx_used;
    logic [7:0] tcf_r;
    logic [7:0] tcf_g;
    logic [7:0] tcf_b;

    logic recovery_vsync_d1;
    logic recovery_vsync_d2;
    logic recovery_href_d1;
    logic recovery_href_d2;
    logic recovery_clken_d1;
    logic recovery_clken_d2;
    logic rec_vsync_aligned;
    logic rec_href_aligned;
    logic rec_clken_aligned;
    logic [7:0] rec_src_r_d1;
    logic [7:0] rec_src_g_d1;
    logic [7:0] rec_src_b_d1;
    logic [7:0] rec_r_post;
    logic [7:0] rec_g_post;
    logic [7:0] rec_b_post;
    logic [7:0] rec_r_tone;
    logic [7:0] rec_g_tone;
    logic [7:0] rec_b_tone;
    logic [4:0] rec_w_rec;
    logic [4:0] rec_w_src;

    logic sky_enable_d;
    logic bank_rd_en_d1;
    logic [7:0] bank_rd_data_hold;
    logic adc_seen;

    integer trans_count;
    integer recovery_count;

    assign adc_rst_n = rst_n && adc_enable;

    atm_light_coarse_tx #(
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT),
        .ADDR_WIDTH(ADDR_WIDTH),
        .OMEGA_Q8  (OMEGA_Q8),
        .T_MIN     (T_MIN)
    ) u_atm_light_coarse_tx (
        .clk            (clk),
        .rst_n          (rst_n),
        .i_valid        ((dark_enable || trans_enable) ? i_src_valid : 1'b0),
        .i_color        (i_src_rgb),
        .i_frame_start  (dark_enable ? i_src_frame_start : 1'b0),
        .i_frame_end    (dark_enable ? i_src_frame_end   : 1'b0),
        .i_A0           (8'd150),
        .i_use_dark     (1'b0),
        .i_use_sky      (1'b1),
        .i_t_sky        (8'd255),
        .i_bank_swap    (bank_swap),
        .i_bank_wr_clear(bank_wr_clear),
        .i_bank_rd_clear(bank_rd_clear),
        .i_bank_rd_en   (bank_rd_en),
        .o_A_R          (purple_A_r),
        .o_A_G          (purple_A_g),
        .o_A_B          (purple_A_b),
        .o_A_valid      (purple_A_valid),
        .o_dark_valid   (purple_dark_valid),
        .o_dark_ch      (purple_dark_ch),
        .o_sky_valid    (purple_sky_valid),
        .o_sky          (purple_sky),
        .o_tx_valid     (purple_tx_valid),
        .o_tx           (purple_tx),
        .o_bank_rd_data (bank_rd_data),
        .o_bank_rd_addr (bank_rd_addr),
        .o_bank_wr_sel  (bank_wr_sel),
        .o_bank_rd_sel  (bank_rd_sel)
    );

    adc_estimation #(
        .IMG_WIDTH  (IMG_WIDTH),
        .IMG_HEIGHT (IMG_HEIGHT),
        .LAMBDA_Q8  (LAMBDA_Q8)
    ) u_adc_estimation (
        .clk          (clk),
        .rst_n        (adc_rst_n),
        .i_enable     (adc_enable),
        .i_gray_valid (adc_in_valid),
        .i_gray_pix   (adc_in_pix),
        .i_mc_valid   (adc_in_valid),
        .i_mc_pix     (adc_in_pix),
        .o_valid      (adc_out_valid),
        .o_adc_pix    (adc_out_pix),
        .o_done       (adc_done_pulse)
    );

    t_compute_fuse #(
        .OMEGA_Q8      (OMEGA_Q8),
        .TX_MIN        (T_MIN),
        .TX_WHEN_A_ZERO(T_MIN)
    ) u_t_compute_fuse (
        .clk      (clk),
        .rst_n    (rst_n),
        .i_valid  (recovery_enable && i_src_valid),
        .i_dark   (adc_dark_for_recovery),
        .i_A      (purple_A_max),
        .i_A_r    (purple_A_r),
        .i_A_g    (purple_A_g),
        .i_A_b    (purple_A_b),
        // Bus is BGR: [23:16]=B, [15:8]=G, [7:0]=R
        .i_src_r  (i_src_rgb[7:0]),
        .i_src_g  (i_src_rgb[15:8]),
        .i_src_b  (i_src_rgb[23:16]),
        .o_valid  (tcf_valid),
        .o_tx_raw (tcf_tx_raw),
        .o_tx_used(tcf_tx_used),
        .o_out_r  (tcf_r),
        .o_out_g  (tcf_g),
        .o_out_b  (tcf_b)
    );

    // Full-frame recovery path: use transmission map captured from TX bank directly.
    fusing #(
        .TX_MIN(T_MIN)
    ) u_fusing_direct (
        .clk      (clk),
        .rst_n    (rst_n),
        .i_valid  (recovery_enable && i_src_valid),
        .i_tx_raw (tx_hybrid_for_recovery),
        .i_A_r    (purple_A_r),
        .i_A_g    (purple_A_g),
        .i_A_b    (purple_A_b),
        .i_src_r  (i_src_rgb[7:0]),
        .i_src_g  (i_src_rgb[15:8]),
        .i_src_b  (i_src_rgb[23:16]),
        .o_valid  (fuse_valid_direct),
        .o_tx_used(fuse_tx_used_direct),
        .o_out_r  (fuse_r_direct),
        .o_out_g  (fuse_g_direct),
        .o_out_b  (fuse_b_direct)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            adc_dark_hold      <= 8'd0;
            adc_min_pix        <= 8'hFF;
            adc_max_pix        <= 8'h00;
            sky_enable_d       <= 1'b0;
            trans_count        <= 0;
            recovery_count     <= 0;
            adc_seen           <= 1'b0;
            adc_enable_d       <= 1'b0;
            adc_in_count       <= 0;
            adc_out_index      <= 0;
            adc_latched_index  <= 0;
            adc_store_count    <= 0;
            tx_store_count     <= 0;
            recovery_pix_index <= 0;
            dark_done          <= 1'b0;
            sky_done           <= 1'b0;
            trans_done         <= 1'b0;
            adc_done           <= 1'b0;
            recovery_done      <= 1'b0;
            recovery_vsync_d1  <= 1'b0;
            recovery_vsync_d2  <= 1'b0;
            recovery_href_d1   <= 1'b0;
            recovery_href_d2   <= 1'b0;
            recovery_clken_d1  <= 1'b0;
            recovery_clken_d2  <= 1'b0;
            bank_rd_en_d1      <= 1'b0;
            bank_rd_data_hold  <= 8'd0;
            rec_src_r_d1       <= 8'd0;
            rec_src_g_d1       <= 8'd0;
            rec_src_b_d1       <= 8'd0;
        end else begin
            bank_rd_en_d1 <= bank_rd_en && adc_enable;
            adc_enable_d  <= adc_enable;

            if (bank_rd_en_d1) begin
                bank_rd_data_hold <= bank_rd_data;
            end

            if (!adc_enable) begin
                adc_in_count <= 0;
            end else if (!adc_enable_d) begin
                adc_in_count <= 0;
            end else if (bank_rd_en_d1 && (adc_in_count < AdcFeedPixels)) begin
                adc_in_count <= adc_in_count + 1;
            end

            if (!adc_enable) begin
                adc_seen <= 1'b0;
            end

            // Start-of-ADC phase: clear counters/range once so captured maps
            // remain valid through recovery after adc_enable deasserts.
            if (adc_enable && !adc_enable_d) begin
                adc_out_index <= 0;
                adc_store_count <= 0;
                tx_store_count <= 0;
                adc_min_pix <= 8'hFF;
                adc_max_pix <= 8'h00;
            end

            if (adc_enable && adc_out_valid) begin
                if (!adc_seen && (adc_out_index == ADC_PICK_INDEX)) begin
                    adc_dark_hold <= adc_out_pix;
                    adc_seen      <= 1'b1;
                    adc_latched_index <= adc_out_index;
                end
                if (adc_store_count < FramePixels) begin
                    adc_frame_map[adc_store_count] <= adc_out_pix;
                    adc_store_count <= adc_store_count + 1;
                end
                if (adc_out_pix < adc_min_pix) begin
                    adc_min_pix <= adc_out_pix;
                end
                if (adc_out_pix > adc_max_pix) begin
                    adc_max_pix <= adc_out_pix;
                end
                adc_out_index <= adc_out_index + 1;
            end

            if (adc_in_valid && (tx_store_count < FramePixels)) begin
                tx_frame_map[tx_store_count] <= adc_in_pix;
                tx_store_count <= tx_store_count + 1;
            end

            if (!recovery_enable) begin
                recovery_pix_index <= 0;
            end else if (i_src_valid && (recovery_pix_index < FramePixels - 1)) begin
                recovery_pix_index <= recovery_pix_index + 1;
            end

            sky_enable_d  <= sky_enable;
            dark_done     <= dark_enable && purple_A_valid;
            sky_done      <= sky_enable && !sky_enable_d;
            // In system mode, finish ADC phase only after TX feed is fully
            // consumed so recovery uses a complete tx_frame_map.
            adc_done      <= adc_enable && (adc_in_count >= AdcFeedPixels);
            trans_done    <= 1'b0;
            recovery_done <= 1'b0;

            if (!trans_enable) begin
                trans_count <= 0;
            end else if (purple_tx_valid) begin
                if (trans_count == FramePixels - 1) begin
                    trans_done  <= 1'b1;
                    trans_count <= 0;
                end else begin
                    trans_count <= trans_count + 1;
                end
            end

            if (!recovery_enable) begin
                recovery_count <= 0;
            end else if (rec_valid) begin
                if (recovery_count == FramePixels - 1) begin
                    recovery_done  <= 1'b1;
                    recovery_count <= 0;
                end else begin
                    recovery_count <= recovery_count + 1;
                end
            end

            recovery_vsync_d1 <= recovery_enable && i_src_frame_start;
            recovery_vsync_d2 <= recovery_vsync_d1;
            recovery_href_d1  <= recovery_enable && i_src_valid;
            recovery_href_d2  <= recovery_href_d1;
            recovery_clken_d1 <= recovery_enable && i_src_valid;
            recovery_clken_d2 <= recovery_clken_d1;

            if (recovery_enable && i_src_valid) begin
                rec_src_r_d1 <= i_src_rgb[7:0];
                rec_src_g_d1 <= i_src_rgb[15:8];
                rec_src_b_d1 <= i_src_rgb[23:16];
            end
        end
    end

    assign adc_in_valid = bank_rd_en_d1 && (adc_in_count < AdcFeedPixels);
    assign adc_in_pix   = (adc_in_count < FramePixels) ? bank_rd_data : bank_rd_data_hold;
    assign purple_A_max = (purple_A_r >= purple_A_g)
                          ? ((purple_A_r >= purple_A_b) ? purple_A_r : purple_A_b)
                          : ((purple_A_g >= purple_A_b) ? purple_A_g : purple_A_b);

    always_comb begin
        integer row;
        integer col;
        integer row_i;
        integer col_i;
        integer map_idx;
        integer src_idx;
        integer head_pad;
        integer range_adc;
        integer norm_adc;
        integer blend_adc;

        adc_dark_raw_for_recovery = adc_dark_hold;
        adc_dark_for_recovery = adc_dark_hold;

        if (UseAdcFrameMap) begin
            if (adc_store_count > 0) begin
                map_idx = recovery_pix_index;
                if (map_idx < 0) begin
                    map_idx = 0;
                end else if (map_idx >= FramePixels) begin
                    map_idx = FramePixels - 1;
                end

                // Border interpolation by clamping to nearest inner pixel.
                row = map_idx / IMG_WIDTH;
                col = map_idx % IMG_WIDTH;

                if (IMG_HEIGHT > 2) begin
                    if (row < 1) begin
                        row_i = 1;
                    end else if (row > IMG_HEIGHT - 2) begin
                        row_i = IMG_HEIGHT - 2;
                    end else begin
                        row_i = row;
                    end
                end else begin
                    row_i = row;
                end

                if (IMG_WIDTH > 2) begin
                    if (col < 1) begin
                        col_i = 1;
                    end else if (col > IMG_WIDTH - 2) begin
                        col_i = IMG_WIDTH - 2;
                    end else begin
                        col_i = col;
                    end
                end else begin
                    col_i = col;
                end

                map_idx = row_i * IMG_WIDTH + col_i;

                // Re-distribute compact ADC stream to full frame.
                head_pad = (FramePixels - adc_store_count) / 2;
                src_idx = map_idx - head_pad;

                if (src_idx < 0) begin
                    src_idx = 0;
                end else if (src_idx >= adc_store_count) begin
                    src_idx = adc_store_count - 1;
                end

                adc_dark_raw_for_recovery = adc_frame_map[src_idx];

                // Stretch ADC dynamic range so adc_used map is informative and
                // contributes spatially to recovery instead of looking flat.
                range_adc = adc_max_pix - adc_min_pix;
                if (range_adc >= 8) begin
                    norm_adc = ((adc_dark_raw_for_recovery - adc_min_pix) * 255) / range_adc;
                    if (norm_adc < 0) begin
                        norm_adc = 0;
                    end else if (norm_adc > 255) begin
                        norm_adc = 255;
                    end

                    // Blend normalized/raw ADC to avoid over-amplifying noise.
                    blend_adc = ((norm_adc * 3) + adc_dark_raw_for_recovery) >> 2;
                    if (blend_adc < 0) begin
                        adc_dark_for_recovery = 8'd0;
                    end else if (blend_adc > 255) begin
                        adc_dark_for_recovery = 8'd255;
                    end else begin
                        adc_dark_for_recovery = blend_adc[7:0];
                    end
                end else begin
                    adc_dark_for_recovery = adc_dark_raw_for_recovery;
                end
            end
        end
    end

    always_comb begin
        integer row;
        integer col;
        integer row_i;
        integer col_i;
        integer idx;

        tx_for_recovery = 8'd255;

        if (tx_store_count > 0) begin
            idx = recovery_pix_index;
            if (idx < 0) begin
                idx = 0;
            end else if (idx >= FramePixels) begin
                idx = FramePixels - 1;
            end

            row = idx / IMG_WIDTH;
            col = idx % IMG_WIDTH;

            if (IMG_HEIGHT > 2) begin
                if (row < 1) row_i = 1;
                else if (row > IMG_HEIGHT - 2) row_i = IMG_HEIGHT - 2;
                else row_i = row;
            end else begin
                row_i = row;
            end

            if (IMG_WIDTH > 2) begin
                if (col < 1) col_i = 1;
                else if (col > IMG_WIDTH - 2) col_i = IMG_WIDTH - 2;
                else col_i = col;
            end else begin
                col_i = col;
            end

            idx = row_i * IMG_WIDTH + col_i;
            if (idx >= tx_store_count) begin
                idx = tx_store_count - 1;
            end
            tx_for_recovery = tx_frame_map[idx];
        end
    end

    // Compute tx from ADC dark estimate (same intent as t_computing) and blend
    // with tx-bank to recover stronger dehaze while avoiding color artifacts.
    always_comb begin
        integer q;
        integer tx_tmp;
        integer tx_mix;
        integer tx_aggr;

        tx_adc_for_recovery = 8'd255;
        tx_hybrid_for_recovery = tx_for_recovery;

        if (purple_A_max == 8'd0) begin
            tx_adc_for_recovery = T_MIN;
        end else begin
            q = (adc_dark_for_recovery * OMEGA_Q8) / purple_A_max;
            if (q > 255) begin
                q = 255;
            end
            tx_tmp = 255 - q;
            if (tx_tmp < T_MIN) begin
                tx_adc_for_recovery = T_MIN;
            end else if (tx_tmp > 255) begin
                tx_adc_for_recovery = 8'd255;
            end else begin
                tx_adc_for_recovery = tx_tmp[7:0];
            end
        end

        // Bias hybrid tx toward ADC-derived tx to restore stronger dehaze,
        // while still anchored by bank tx for stability.
           tx_mix = ({3'b000, tx_for_recovery}
               + ({3'b000, tx_adc_for_recovery} << 2)
               + ({3'b000, tx_adc_for_recovery} << 1)
               + {3'b000, tx_adc_for_recovery}) >> 3;
        // If ADC-derived tx indicates significantly heavier haze than tx-bank,
        // bias one more step toward ADC tx for stronger cleanup.
        tx_aggr = tx_mix;
        if ((tx_adc_for_recovery + 8) < tx_for_recovery) begin
            tx_aggr = (tx_mix + tx_adc_for_recovery) >> 1;
        end

        // Extra selective dehaze for dense haze bands only.
        if (tx_aggr < DenseHazeTh) begin
            tx_aggr = tx_aggr - DenseHazeSub;
        end

        if (tx_aggr < RecoveryTxMin) begin
            tx_hybrid_for_recovery = RecoveryTxMin;
        end else if (tx_aggr > 255) begin
            tx_hybrid_for_recovery = 8'd255;
        end else begin
            tx_hybrid_for_recovery = tx_aggr[7:0];
        end
    end

    assign rec_valid = UseAdcFrameMap ? fuse_valid_direct : tcf_valid;
    assign rec_tx_used = UseAdcFrameMap ? fuse_tx_used_direct : tcf_tx_used;
    assign rec_r = UseAdcFrameMap ? fuse_r_direct : tcf_r;
    assign rec_g = UseAdcFrameMap ? fuse_g_direct : tcf_g;
    assign rec_b = UseAdcFrameMap ? fuse_b_direct : tcf_b;

    always_comb begin
        integer sum_r;
        integer sum_g;
        integer sum_b;
        integer denom;
        integer lift;
        integer out_r;
        integer out_g;
        integer out_b;

        rec_w_rec = 5'd7;
        rec_w_src = 5'd1;

        if (UseAdcFrameMap) begin
            // Adaptive blend by transmission: stronger dehaze in heavy haze,
            // softer blend in clearer regions for color stability.
            if (rec_tx_used <= 8'd96) begin
                rec_w_rec = 5'd15;  // heavy haze: 15:1
                rec_w_src = 5'd1;
            end else if (rec_tx_used <= 8'd160) begin
                rec_w_rec = 5'd12;  // medium haze: 12:1
                rec_w_src = 5'd1;
            end else begin
                rec_w_rec = 5'd6;   // clear sky: 6:2
                rec_w_src = 5'd2;
            end

            denom = rec_w_rec + rec_w_src;
            sum_r = (rec_r * rec_w_rec) + (rec_src_r_d1 * rec_w_src);
            sum_g = (rec_g * rec_w_rec) + (rec_src_g_d1 * rec_w_src);
            sum_b = (rec_b * rec_w_rec) + (rec_src_b_d1 * rec_w_src);

            // Small luminance compensation for natural look (avoid overly dark output).
            lift = (255 - rec_tx_used) >> 5;
            if (lift < 0) begin
                lift = 0;
            end else if (lift > 13) begin
                lift = 13;
            end

            // Mild global lift keeps scene from becoming too dark after
            // stronger dehaze weighting.
            out_r = (sum_r / denom) + lift + 8;
            out_g = (sum_g / denom) + lift + 8;
            out_b = (sum_b / denom) + lift + 8;

            if (out_r > 255) out_r = 255;
            if (out_g > 255) out_g = 255;
            if (out_b > 255) out_b = 255;
            if (out_r < 0) out_r = 0;
            if (out_g < 0) out_g = 0;
            if (out_b < 0) out_b = 0;

            rec_r_post = out_r[7:0];
            rec_g_post = out_g[7:0];
            rec_b_post = out_b[7:0];
        end else begin
            rec_r_post = rec_r;
            rec_g_post = rec_g;
            rec_b_post = rec_b;
        end
    end

    always_comb begin
        integer haze_boost;
        integer tone_r;
        integer tone_g;
        integer tone_b;
        integer detail_r;
        integer detail_g;
        integer detail_b;
        integer purple_floor_g;
        integer purple_drop_b;

        // Adaptive post-tone: warm slightly in heavy haze regions to move output
        // closer to natural city-scene colors while keeping sky/clear zones stable.
        haze_boost = (255 - rec_tx_used) >> 4;
        if (haze_boost < 0) begin
            haze_boost = 0;
        end else if (haze_boost > 15) begin
            haze_boost = 15;
        end

        tone_r = rec_r_post + haze_boost;
        tone_g = rec_g_post + (haze_boost >> 3);
        tone_b = rec_b_post - (haze_boost >> 3);

        if (tone_r > 255) tone_r = 255;
        if (tone_g > 255) tone_g = 255;
        if (tone_b > 255) tone_b = 255;
        if (tone_r < 0) tone_r = 0;
        if (tone_g < 0) tone_g = 0;
        if (tone_b < 0) tone_b = 0;

        // Extra anti-purple guard: lift G and suppress B when purple tint appears.
        if ((tone_r > 132) && (tone_b > 132) && (tone_g + 12 < tone_r)
                && (tone_g + 8 < tone_b)) begin
            purple_floor_g = ((tone_r + tone_b) >> 1) - 6;
            if (purple_floor_g > tone_g) begin
                tone_g = purple_floor_g;
            end

            purple_drop_b = ((tone_b - tone_g) >> 1);
            if (purple_drop_b > 0) begin
                tone_b = tone_b - purple_drop_b;
            end

            if (tone_b > tone_g + 12) begin
                tone_b = tone_g + 12;
            end
        end

        // Subtle detail boost only: use recovered-vs-source residue with low gain.
        detail_r = (tone_r - rec_src_r_d1);
        detail_g = (tone_g - rec_src_g_d1);
        detail_b = (tone_b - rec_src_b_d1);

        tone_r = tone_r + ((detail_r * SharpNum) >>> SharpShift);
        tone_g = tone_g + ((detail_g * SharpNum) >>> SharpShift);
        tone_b = tone_b + ((detail_b * SharpNum) >>> SharpShift);

        if (tone_r > 255) tone_r = 255;
        if (tone_r < 0) tone_r = 0;
        if (tone_g > 255) tone_g = 255;
        if (tone_g < 0) tone_g = 0;
        if (tone_b > 255) tone_b = 255;
        if (tone_b < 0) tone_b = 0;

        rec_r_tone = tone_r[7:0];
        rec_g_tone = tone_g[7:0];
        rec_b_tone = tone_b[7:0];
    end

    assign rec_vsync_aligned = UseAdcFrameMap ? recovery_vsync_d1 : recovery_vsync_d2;
    assign rec_href_aligned  = UseAdcFrameMap ? recovery_href_d1  : recovery_href_d2;
    assign rec_clken_aligned = UseAdcFrameMap ? recovery_clken_d1 : recovery_clken_d2;

    assign post_frame_vsync = rec_vsync_aligned;
    assign post_frame_href  = rec_valid && rec_href_aligned;
    assign post_frame_clken = rec_valid && rec_clken_aligned;
    assign post_img         = {rec_r_tone, rec_g_tone, rec_b_tone};

endmodule

