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
    localparam int FrameAddrWidth = $clog2(FramePixels);
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
    logic [FrameAddrWidth:0] adc_in_count;
    logic [FrameAddrWidth:0] adc_out_index;
    logic [FrameAddrWidth:0] adc_latched_index;
    logic [FrameAddrWidth:0] adc_store_count;
    logic [FrameAddrWidth:0] tx_store_count;
    logic [FrameAddrWidth:0] recovery_pix_index;

    logic                     adc_frame_map_wr_en;
    logic [FrameAddrWidth-1:0] adc_frame_map_wr_addr;
    logic [7:0]               adc_frame_map_wr_data;
    logic                     adc_frame_map_rd_en;
    logic [FrameAddrWidth-1:0] adc_frame_map_rd_addr;
    logic [7:0]               adc_frame_map_rd_data;

    logic                     tx_frame_map_wr_en;
    logic [FrameAddrWidth-1:0] tx_frame_map_wr_addr;
    logic [7:0]               tx_frame_map_wr_data;
    logic                     tx_frame_map_rd_en;
    logic [FrameAddrWidth-1:0] tx_frame_map_rd_addr;
    logic [7:0]               tx_frame_map_rd_data;

    logic       rec_valid;
    logic [7:0] rec_tx_used;
    logic [7:0] rec_r;
    logic [7:0] rec_g;
    logic [7:0] rec_b;

    logic [7:0] tx_for_recovery;
    logic [7:0] tx_adc_for_recovery;
    logic [7:0] tx_hybrid_for_recovery;

    // RL-opt pipeline registers: break long combinational chains
    logic [7:0] adc_dark_for_recovery_r;   // registered adc_dark_for_recovery
    logic [7:0] tx_adc_for_recovery_r;     // registered tx_adc (hybrid mid-pipe)
    logic [7:0] tx_for_recovery_r;         // registered tx_for_recovery (hybrid mid-pipe)
    logic [7:0] tx_hybrid_for_recovery_r;  // registered tx_hybrid_for_recovery
    logic [7:0] rec_r_post_r, rec_g_post_r, rec_b_post_r;  // registered blend output
    logic [7:0] rec_tx_used_r;             // registered rec_tx_used for tone
    logic [7:0] rec_src_r_d2, rec_src_g_d2, rec_src_b_d2;
    logic [7:0] rec_src_r_d3, rec_src_g_d3, rec_src_b_d3;
    logic [7:0] rec_src_r_d4, rec_src_g_d4, rec_src_b_d4;

    // Reciprocal LUTs for replacing combinational dividers
    logic [15:0] recip_range_adc;
    logic [15:0] recip_A_max;

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
    logic recovery_vsync_d3;
    logic recovery_vsync_d4;
    logic recovery_vsync_d5;  // pipeline opt: fusing/t_computing 2-stage
    logic recovery_href_d1;
    logic recovery_href_d2;
    logic recovery_href_d3;
    logic recovery_href_d4;
    logic recovery_href_d5;
    logic recovery_clken_d1;
    logic recovery_clken_d2;
    logic recovery_clken_d3;
    logic recovery_clken_d4;
    logic recovery_clken_d5;
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

    logic [FrameAddrWidth:0] trans_count;
    logic [FrameAddrWidth:0] recovery_count;
    logic rec_valid_d1;  // forward declaration for recovery_count alignment

    assign adc_rst_n = rst_n && adc_enable;

    // Reciprocal LUT for normalize divide (range_adc) and hybrid TX divide (A_max)
    // Declared as wires driven by always_comb; LUT instances below.
    logic [7:0] range_adc_val;   // driven from normalize always_comb
    logic [7:0] A_max_val;       // = purple_A_max
    assign A_max_val = purple_A_max;
    recip_lut_q16 u_recip_range (.i_val(range_adc_val), .o_recip_q16(recip_range_adc));
    recip_lut_q16 u_recip_Amax  (.i_val(A_max_val),     .o_recip_q16(recip_A_max));

    bank_bram #(
        .DATA_WIDTH(8),
        .ADDR_WIDTH(FrameAddrWidth)
    ) u_adc_frame_map (
        .clk     (clk),
        .wr_en   (adc_frame_map_wr_en),
        .wr_addr (adc_frame_map_wr_addr),
        .wr_data (adc_frame_map_wr_data),
        .rd_en   (adc_frame_map_rd_en),
        .rd_addr (adc_frame_map_rd_addr),
        .rd_data (adc_frame_map_rd_data)
    );

    bank_bram #(
        .DATA_WIDTH(8),
        .ADDR_WIDTH(FrameAddrWidth)
    ) u_tx_frame_map (
        .clk     (clk),
        .wr_en   (tx_frame_map_wr_en),
        .wr_addr (tx_frame_map_wr_addr),
        .wr_data (tx_frame_map_wr_data),
        .rd_en   (tx_frame_map_rd_en),
        .rd_addr (tx_frame_map_rd_addr),
        .rd_data (tx_frame_map_rd_data)
    );

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

    // RL-opt: delay valid/src by 1 cycle to match adc_dark_for_recovery_r
    logic tcf_valid_d1;
    logic [23:0] tcf_src_d1;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tcf_valid_d1 <= 1'b0;
            tcf_src_d1   <= 24'd0;
        end else begin
            tcf_valid_d1 <= recovery_enable && i_src_valid;
            tcf_src_d1   <= i_src_rgb;
        end
    end

    t_compute_fuse #(
        .OMEGA_Q8      (OMEGA_Q8),
        .TX_MIN        (T_MIN),
        .TX_WHEN_A_ZERO(T_MIN)
    ) u_t_compute_fuse (
        .clk      (clk),
        .rst_n    (rst_n),
        .i_valid  (tcf_valid_d1),
        .i_dark   (adc_dark_for_recovery_r),
        .i_A      (purple_A_max),
        .i_A_r    (purple_A_r),
        .i_A_g    (purple_A_g),
        .i_A_b    (purple_A_b),
        .i_src_r  (tcf_src_d1[7:0]),
        .i_src_g  (tcf_src_d1[15:8]),
        .i_src_b  (tcf_src_d1[23:16]),
        .o_valid  (tcf_valid),
        .o_tx_raw (tcf_tx_raw),
        .o_tx_used(tcf_tx_used),
        .o_out_r  (tcf_r),
        .o_out_g  (tcf_g),
        .o_out_b  (tcf_b)
    );

    // Full-frame recovery path: use transmission map captured from TX bank directly.
    // RL-opt: valid must be delayed 2 cycles to match tx_hybrid_for_recovery_r pipeline
    logic fuse_direct_valid_d1, fuse_direct_valid_d2;
    logic fuse_direct_src_valid_d1;
    logic [23:0] fuse_direct_src_d1, fuse_direct_src_d2;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fuse_direct_valid_d1 <= 1'b0;
            fuse_direct_valid_d2 <= 1'b0;
            fuse_direct_src_d1   <= 24'd0;
            fuse_direct_src_d2   <= 24'd0;
        end else begin
            fuse_direct_valid_d1 <= recovery_enable && i_src_valid;
            fuse_direct_valid_d2 <= fuse_direct_valid_d1;
            fuse_direct_src_d1   <= i_src_rgb;
            fuse_direct_src_d2   <= fuse_direct_src_d1;
        end
    end

    fusing #(
        .TX_MIN(T_MIN)
    ) u_fusing_direct (
        .clk      (clk),
        .rst_n    (rst_n),
        .i_valid  (fuse_direct_valid_d2),
        .i_tx_raw (tx_hybrid_for_recovery_r),
        .i_A_r    (purple_A_r),
        .i_A_g    (purple_A_g),
        .i_A_b    (purple_A_b),
        .i_src_r  (fuse_direct_src_d2[7:0]),
        .i_src_g  (fuse_direct_src_d2[15:8]),
        .i_src_b  (fuse_direct_src_d2[23:16]),
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
            recovery_vsync_d3  <= 1'b0;
            recovery_vsync_d4  <= 1'b0;
            recovery_vsync_d5  <= 1'b0;
            recovery_href_d1   <= 1'b0;
            recovery_href_d2   <= 1'b0;
            recovery_href_d3   <= 1'b0;
            recovery_href_d4   <= 1'b0;
            recovery_href_d5   <= 1'b0;
            recovery_clken_d1  <= 1'b0;
            recovery_clken_d2  <= 1'b0;
            recovery_clken_d3  <= 1'b0;
            recovery_clken_d4  <= 1'b0;
            recovery_clken_d5  <= 1'b0;
            bank_rd_en_d1      <= 1'b0;
            bank_rd_data_hold  <= 8'd0;
            rec_src_r_d1       <= 8'd0;
            rec_src_g_d1       <= 8'd0;
            rec_src_b_d1       <= 8'd0;
            rec_src_r_d3       <= 8'd0;
            rec_src_g_d3       <= 8'd0;
            rec_src_b_d3       <= 8'd0;
            rec_src_r_d4       <= 8'd0;
            rec_src_g_d4       <= 8'd0;
            rec_src_b_d4       <= 8'd0;
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
                if (adc_store_count < FramePixels)
                    adc_store_count <= adc_store_count + 1;
                if (adc_out_pix < adc_min_pix) begin
                    adc_min_pix <= adc_out_pix;
                end
                if (adc_out_pix > adc_max_pix) begin
                    adc_max_pix <= adc_out_pix;
                end
                adc_out_index <= adc_out_index + 1;
            end

            if (adc_in_valid && (tx_store_count < FramePixels)) begin
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
            end else if (UseAdcFrameMap ? rec_valid_d1 : rec_valid) begin
                if (recovery_count == FramePixels - 1) begin
                    recovery_done  <= 1'b1;
                    recovery_count <= 0;
                end else begin
                    recovery_count <= recovery_count + 1;
                end
            end

            recovery_vsync_d1 <= recovery_enable && i_src_frame_start;
            recovery_vsync_d2 <= recovery_vsync_d1;
            recovery_vsync_d3 <= recovery_vsync_d2;
            recovery_vsync_d4 <= recovery_vsync_d3;
            recovery_vsync_d5 <= recovery_vsync_d4;
            recovery_href_d1  <= recovery_enable && i_src_valid;
            recovery_href_d2  <= recovery_href_d1;
            recovery_href_d3  <= recovery_href_d2;
            recovery_href_d4  <= recovery_href_d3;
            recovery_href_d5  <= recovery_href_d4;
            recovery_clken_d1 <= recovery_enable && i_src_valid;
            recovery_clken_d2 <= recovery_clken_d1;
            recovery_clken_d3 <= recovery_clken_d2;
            recovery_clken_d4 <= recovery_clken_d3;
            recovery_clken_d5 <= recovery_clken_d4;

            if (recovery_enable && i_src_valid) begin
                rec_src_r_d1 <= i_src_rgb[7:0];
                rec_src_g_d1 <= i_src_rgb[15:8];
                rec_src_b_d1 <= i_src_rgb[23:16];
            end

            // RL-opt pipeline registers: break critical combinational paths
            adc_dark_for_recovery_r  <= adc_dark_for_recovery;
            tx_adc_for_recovery_r    <= tx_adc_for_recovery;
            tx_for_recovery_r        <= tx_for_recovery;
            tx_hybrid_for_recovery_r <= tx_hybrid_for_recovery;
            rec_r_post_r    <= rec_r_post;
            rec_g_post_r    <= rec_g_post;
            rec_b_post_r    <= rec_b_post;
            rec_tx_used_r   <= rec_tx_used;
            rec_src_r_d2    <= rec_src_r_d1;
            rec_src_g_d2    <= rec_src_g_d1;
            rec_src_b_d2    <= rec_src_b_d1;
            rec_src_r_d3    <= rec_src_r_d2;
            rec_src_g_d3    <= rec_src_g_d2;
            rec_src_b_d3    <= rec_src_b_d2;
            rec_src_r_d4    <= rec_src_r_d3;
            rec_src_g_d4    <= rec_src_g_d3;
            rec_src_b_d4    <= rec_src_b_d3;
        end
    end

    assign adc_in_valid = bank_rd_en_d1 && (adc_in_count < AdcFeedPixels);
    assign adc_in_pix   = (adc_in_count < FramePixels) ? bank_rd_data : bank_rd_data_hold;
    assign adc_frame_map_wr_en   = adc_enable && adc_out_valid && (adc_store_count < FramePixels);
    assign adc_frame_map_wr_addr = adc_store_count[FrameAddrWidth-1:0];
    assign adc_frame_map_wr_data = adc_out_pix;
    assign tx_frame_map_wr_en     = adc_in_valid && (tx_store_count < FramePixels);
    assign tx_frame_map_wr_addr   = tx_store_count[FrameAddrWidth-1:0];
    assign tx_frame_map_wr_data   = adc_in_pix;
    assign adc_frame_map_rd_en    = recovery_enable && i_src_valid && (adc_store_count > 0);
    assign tx_frame_map_rd_en     = recovery_enable && i_src_valid && (tx_store_count > 0);
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

        adc_frame_map_rd_addr = '0;
        adc_dark_raw_for_recovery = adc_dark_hold;
        adc_dark_for_recovery = adc_dark_hold;
        range_adc_val = 8'd1;  // default: drive reciprocal LUT input

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

                adc_frame_map_rd_addr = src_idx[FrameAddrWidth-1:0];
                adc_dark_raw_for_recovery = adc_frame_map_rd_data;

                // Stretch ADC dynamic range so adc_used map is informative and
                // contributes spatially to recovery instead of looking flat.
                range_adc = adc_max_pix - adc_min_pix;
                range_adc_val = range_adc[7:0];  // drive reciprocal LUT
                if (range_adc >= 8) begin
                    // RL-opt: replace /range_adc with reciprocal LUT multiply
                    norm_adc = (((adc_dark_raw_for_recovery - adc_min_pix) * 255)
                                * recip_range_adc) >> 16;
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

        tx_frame_map_rd_addr = '0;
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
            tx_frame_map_rd_addr = idx[FrameAddrWidth-1:0];
            tx_for_recovery = tx_frame_map_rd_data;
        end
    end

    // Compute tx from ADC dark estimate (same intent as t_computing) and blend
    // with tx-bank to recover stronger dehaze while avoiding color artifacts.
    // RL-opt: split into 2 stages with pipeline register in between.
    //   Stage A (combo): tx_adc_for_recovery (using reciprocal LUT instead of divide)
    //   Pipeline: tx_adc_for_recovery_r, tx_for_recovery_r
    //   Stage B (combo): tx_mix -> tx_aggr -> tx_hybrid_for_recovery
    always_comb begin
        integer q;
        integer tx_tmp;

        tx_adc_for_recovery = 8'd255;

        if (purple_A_max == 8'd0) begin
            tx_adc_for_recovery = T_MIN;
        end else begin
            // RL-opt: use REGISTERED adc_dark to break ADC_norm→TX cascade.
            // adc_dark_for_recovery_r is 1 cycle behind adc_dark_for_recovery.
            q = (adc_dark_for_recovery_r * OMEGA_Q8 * recip_A_max) >> 16;
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
    end

    // Stage B: mix/aggr/dense — uses pipeline-registered tx_adc and tx_for_recovery
    always_comb begin
        integer tx_mix;
        integer tx_aggr;

        tx_hybrid_for_recovery = tx_for_recovery_r;

        // Bias hybrid tx toward ADC-derived tx to restore stronger dehaze,
        // while still anchored by bank tx for stability.
           tx_mix = ({3'b000, tx_for_recovery_r}
               + ({3'b000, tx_adc_for_recovery_r} << 2)
               + ({3'b000, tx_adc_for_recovery_r} << 1)
               + {3'b000, tx_adc_for_recovery_r}) >> 3;
        // If ADC-derived tx indicates significantly heavier haze than tx-bank,
        // bias one more step toward ADC tx for stronger cleanup.
        tx_aggr = tx_mix;
        if ((tx_adc_for_recovery_r + 8) < tx_for_recovery_r) begin
            tx_aggr = (tx_mix + tx_adc_for_recovery_r) >> 1;
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
    // RL-opt: delay rec_valid by 1 cycle to match post-blend pipeline register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rec_valid_d1 <= 1'b0;
        else
            rec_valid_d1 <= rec_valid;
    end
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

            // RL-opt: replace /denom with constant reciprocals.
            // denom in {8, 13, 16}:
            //   8  -> >> 3
            //   13 -> * 5039 >> 16  (exact: 65536/13 = 5041.23, use 5039 for floor match)
            //   16 -> >> 4
            if (denom == 16) begin
                out_r = (sum_r >> 4) + lift + 8;
                out_g = (sum_g >> 4) + lift + 8;
                out_b = (sum_b >> 4) + lift + 8;
            end else if (denom == 13) begin
                out_r = ((sum_r * 5039) >> 16) + lift + 8;
                out_g = ((sum_g * 5039) >> 16) + lift + 8;
                out_b = ((sum_b * 5039) >> 16) + lift + 8;
            end else begin // denom == 8
                out_r = (sum_r >> 3) + lift + 8;
                out_g = (sum_g >> 3) + lift + 8;
                out_b = (sum_b >> 3) + lift + 8;
            end

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

        // RL-opt: use pipeline-registered blend output (rec_r_post_r) and
        // registered tx_used/src for tone mapping — breaks blend->tone chain.
        // Adaptive post-tone: warm slightly in heavy haze regions to move output
        // closer to natural city-scene colors while keeping sky/clear zones stable.
        haze_boost = (255 - rec_tx_used_r) >> 4;
        if (haze_boost < 0) begin
            haze_boost = 0;
        end else if (haze_boost > 15) begin
            haze_boost = 15;
        end

        tone_r = rec_r_post_r + haze_boost;
        tone_g = rec_g_post_r + (haze_boost >> 3);
        tone_b = rec_b_post_r - (haze_boost >> 3);

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
        // Pipeline opt: use d3 for UseAdcFrameMap, d4 for non-UseAdcFrameMap
        // to maintain same relative alignment to the output valid.
        detail_r = UseAdcFrameMap ? (tone_r - rec_src_r_d3) : (tone_r - rec_src_r_d4);
        detail_g = UseAdcFrameMap ? (tone_g - rec_src_g_d3) : (tone_g - rec_src_g_d4);
        detail_b = UseAdcFrameMap ? (tone_b - rec_src_b_d3) : (tone_b - rec_src_b_d4);

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

    // Pipeline opt: fusing/t_computing now 2-stage each.
    // UseAdcFrameMap: d2(pre-fusing) + 2(fusing) + 1(rec_valid_d1) = 5 cycles. Use d5.
    // Non-UseAdcFrameMap: d1(tcf) + 2(t_computing) + 2(fusing) = 5 cycles. Use d5 with rec_valid.
    assign rec_vsync_aligned = UseAdcFrameMap ? recovery_vsync_d5 : recovery_vsync_d5;
    assign rec_href_aligned  = UseAdcFrameMap ? recovery_href_d5  : recovery_href_d5;
    assign rec_clken_aligned = UseAdcFrameMap ? recovery_clken_d5 : recovery_clken_d5;

    assign post_frame_vsync = rec_vsync_aligned;
    // RL-opt: use delayed valid for UseAdcFrameMap (matches post-blend pipeline)
    assign post_frame_href  = (UseAdcFrameMap ? rec_valid_d1 : rec_valid) && rec_href_aligned;
    assign post_frame_clken = (UseAdcFrameMap ? rec_valid_d1 : rec_valid) && rec_clken_aligned;
    assign post_img         = {rec_r_tone, rec_g_tone, rec_b_tone};


endmodule

