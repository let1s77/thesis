# ======================================================================
# script_for_haze_removal_top.tcl
# Run from: 02_questasim/
# Usage:    do ../01_sim/IPU/script/script_for_haze_removal_top.tcl
# ======================================================================

set pat_hex "../09_pattern/pattern_haze_removal_top_rgb5x5.hex"
set gld_hex "../07_golden_output/golden_haze_removal_top.hex"

file mkdir log

vlib work
vmap work work

# Core blocks
vlog -sv ../00_src/IPU/grayscale.sv
vlog -sv ../00_src/IPU/src_min.sv
vlog -sv ../00_src/IPU/dark_channel.sv
vlog -sv ../00_src/IPU/atmospheric_light.sv
vlog -sv ../00_src/IPU/sky_recognition.sv
vlog -sv ../00_src/IPU/invA_lut_q16.sv
vlog -sv ../00_src/IPU/norm_channel_q16.sv
vlog -sv ../00_src/IPU/min3_u8.sv
vlog -sv ../00_src/IPU/omega_clamp_t.sv
vlog -sv ../00_src/IPU/spatial_min3x3.sv
vlog -sv ../00_src/IPU/estimate_transmission.sv
vlog -sv ../00_src/IPU/bank_bram.sv
vlog -sv ../00_src/IPU/frame_linear_counter.sv
vlog -sv ../00_src/IPU/bank_pingpong_stream.sv
vlog -sv ../00_src/IPU/atm_light_coarse_tx.sv

# ADC path
vlog -sv ../00_src/IPU/adc_line_buffer_5x5.sv
vlog -sv ../00_src/IPU/adc_pixel_distance.sv
vlog -sv ../00_src/IPU/adc_path_length.sv
vlog -sv ../00_src/IPU/adc_rlimit_compute.sv
vlog -sv ../00_src/IPU/adc_ase_masked_min.sv
vlog -sv ../00_src/IPU/adc_estimation.sv

# Recovery path
vlog -sv ../00_src/IPU/t_computing.sv
vlog -sv ../00_src/IPU/fusing.sv
vlog -sv ../00_src/IPU/t_compute_fuse.sv

# Top + TB
vlog -sv ../00_src/IPU/haze_removal_core.sv
vlog -sv ../00_src/IPU/haze_removal_top.sv
vlog -sv ../01_sim/IPU/haze_removal_top_tb.sv

vopt haze_removal_top_tb -o tb_opt +acc
vsim -c tb_opt \
    "+PATTERN_FILE=$pat_hex" \
    "+GOLDEN_FILE=$gld_hex" \
    -l log/sim_haze_removal_top.log \
    -do "run -all; quit"

