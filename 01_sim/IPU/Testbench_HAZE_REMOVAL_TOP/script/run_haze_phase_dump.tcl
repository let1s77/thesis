onerror { quit -f }

if {[info exists ::env(DUMP_DIR)]} {
    set dump_dir $::env(DUMP_DIR)
} else {
    set dump_dir "../01_sim/IPU/Testbench_HAZE_REMOVAL_TOP/sim/output"
}

if {[info exists ::env(PATTERN_FILE)]} {
    set pattern_file $::env(PATTERN_FILE)
} else {
    set pattern_file "../09_pattern/pattern_haze_removal_top_rgb5x5.hex"
}

vlib work
vmap work work

set SRC_DIR "../00_src/IPU"
set TB_DIR  "../01_sim/IPU/Testbench_HAZE_REMOVAL_TOP/sim"

vlog +acc +define+SIM_MODE \
    $SRC_DIR/min3_u8.sv \
    $SRC_DIR/dark_channel.sv \
    $SRC_DIR/atmospheric_light.sv \
    $SRC_DIR/bank_bram.sv \
    $SRC_DIR/bank_pingpong_stream.sv \
    $SRC_DIR/estimate_transmission.sv \
    $SRC_DIR/adc_pixel_distance.sv \
    $SRC_DIR/adc_path_length.sv \
    $SRC_DIR/adc_rlimit_compute.sv \
    $SRC_DIR/adc_ase_masked_min.sv \
    $SRC_DIR/adc_line_buffer_5x5.sv \
    $SRC_DIR/adc_estimation.sv \
    $SRC_DIR/frame_linear_counter.sv \
    $SRC_DIR/invA_lut_q16.sv \
    $SRC_DIR/omega_clamp_t.sv \
    $SRC_DIR/norm_channel_q16.sv \
    $SRC_DIR/ipu_control_logic.sv \
    $SRC_DIR/grayscale.sv \
    $SRC_DIR/t_computing.sv \
    $SRC_DIR/fusing.sv \
    $SRC_DIR/t_compute_fuse.sv \
    $SRC_DIR/atm_light_coarse_tx.sv \
    $SRC_DIR/haze_removal_core.sv \
    $SRC_DIR/haze_removal_top.sv \
    $TB_DIR/haze_removal_top_phase_tb.sv

vsim -c haze_removal_top_phase_tb +PATTERN_FILE=$pattern_file +DUMP_DIR=$dump_dir -do "run -all; quit -f"

