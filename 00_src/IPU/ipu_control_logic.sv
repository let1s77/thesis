//==============================================================================
// Module: ipu_control_logic
// Description:
//   Stage-based FSM controller for the IPU hierarchy:
//     IDLE -> LOAD -> DARK -> SKY -> TRANS -> ADC -> RECOVERY -> DONE
//
// Notes:
// - This controller matches the stage-oriented architecture from the Excel
//   schedule and relies on explicit done pulses from the datapath wrapper.
// - Global BRAM reader is reused for DARK / TRANS / RECOVERY source-frame scans.
// - BANK control is still exposed because atm_light_coarse_tx keeps the tx
//   ping-pong bank.
//==============================================================================

module ipu_control_logic #(
    parameter int IMG_WIDTH  = 128,
    parameter int IMG_HEIGHT = 128
)(
    input  logic clk,
    input  logic rst_n,
    input  logic ipu_en,
    input  logic ipu_start,
    input  logic cont_mode,
    input  logic reader_busy,
    input  logic reader_done,
    input  logic writer_busy,
    input  logic writer_done,
    input  logic dark_done,
    input  logic sky_done,
    input  logic trans_done,
    input  logic adc_done,
    input  logic recovery_done,
    output logic reader_start,
    output logic writer_start,
    output logic dark_enable,
    output logic sky_enable,
    output logic trans_enable,
    output logic adc_enable,
    output logic recovery_enable,
    output logic bank_swap,
    output logic bank_wr_clear,
    output logic bank_rd_clear,
    output logic bank_rd_en,
    output logic idle,
    output logic busy,
    output logic done,
    output logic error,
    output logic [3:0] fsm_state
);

    typedef enum logic [3:0] {
        S_IDLE     = 4'd0,
        S_LOAD     = 4'd1,
        S_DARK     = 4'd2,
        S_SKY      = 4'd3,
        S_TRANS    = 4'd4,
        S_ADC      = 4'd5,
        S_RECOVERY = 4'd6,
        S_DONE     = 4'd7
    } state_t;

    state_t state_c, state_n;
    state_t state_prev;

    logic enter_load;
    logic enter_dark;
    logic enter_trans;
    logic enter_adc;
    logic enter_recovery;
    logic enter_adc_d1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_c       <= S_IDLE;
            state_prev    <= S_IDLE;
            enter_adc_d1  <= 1'b0;
        end else begin
            state_prev    <= state_c;
            state_c       <= state_n;
            enter_adc_d1  <= enter_adc;
        end
    end

    always_comb begin
        state_n = state_c;

        unique case (state_c)
            S_IDLE: begin
                if (ipu_en && ipu_start)
                    state_n = S_LOAD;
            end

            S_LOAD: begin
                state_n = S_DARK;
            end

            S_DARK: begin
                if (reader_done)
                    state_n = S_SKY;
            end

            S_SKY: begin
                if (sky_done)
                    state_n = S_TRANS;
            end

            S_TRANS: begin
                if (reader_done)
                    state_n = S_ADC;
            end

            S_ADC: begin
                if (adc_done)
                    state_n = S_RECOVERY;
            end

            S_RECOVERY: begin
                if (recovery_done && writer_done)
                    state_n = S_DONE;
            end

            S_DONE: begin
                if (cont_mode && ipu_en)
                    state_n = S_LOAD;
                else
                    state_n = S_IDLE;
            end

            default: begin
                state_n = S_IDLE;
            end
        endcase
    end

    always_comb begin
        enter_load     = (state_c == S_LOAD)     && (state_prev != S_LOAD);
        enter_dark     = (state_c == S_DARK)     && (state_prev != S_DARK);
        enter_trans    = (state_c == S_TRANS)    && (state_prev != S_TRANS);
        enter_adc      = (state_c == S_ADC)      && (state_prev != S_ADC);
        enter_recovery = (state_c == S_RECOVERY) && (state_prev != S_RECOVERY);
    end

    always_comb begin
        reader_start     = 1'b0;
        writer_start     = 1'b0;
        dark_enable      = 1'b0;
        sky_enable       = 1'b0;
        trans_enable     = 1'b0;
        adc_enable       = 1'b0;
        recovery_enable  = 1'b0;
        bank_swap        = 1'b0;
        bank_wr_clear    = 1'b0;
        bank_rd_clear    = 1'b0;
        bank_rd_en       = 1'b0;
        idle             = 1'b0;
        busy             = 1'b0;
        done             = 1'b0;
        error            = 1'b0;
        fsm_state        = state_c;

        unique case (state_c)
            S_IDLE: begin
                idle = 1'b1;
            end

            S_LOAD: begin
                busy          = 1'b1;
                bank_wr_clear = 1'b1;
                bank_rd_clear = 1'b1;
            end

            S_DARK: begin
                busy         = 1'b1;
                dark_enable  = 1'b1;
                reader_start = enter_dark;
            end

            S_SKY: begin
                busy       = 1'b1;
                sky_enable = 1'b1;
            end

            S_TRANS: begin
                busy          = 1'b1;
                trans_enable  = 1'b1;
                reader_start  = enter_trans;
                bank_wr_clear = enter_trans;
            end

            S_ADC: begin
                busy          = 1'b1;
                adc_enable    = 1'b1;
                bank_swap     = enter_adc;
                bank_rd_clear = enter_adc || enter_adc_d1;
                bank_rd_en    = !enter_adc;
            end

            S_RECOVERY: begin
                busy            = 1'b1;
                recovery_enable = 1'b1;
                reader_start    = enter_recovery;
                writer_start    = enter_recovery;
            end

            S_DONE: begin
                done = 1'b1;
            end

            default: begin
                error = 1'b1;
            end
        endcase
    end

endmodule
