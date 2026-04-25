onerror { quit -f }

if {[info exists ::env(LOG_DIR)]} {
    set log_dir $::env(LOG_DIR)
} else {
    set log_dir "../01_sim/IPU/Testbench_HAZE_REMOVAL_TOP/log"
}

file mkdir $log_dir
set ts [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]
set log_file [file join $log_dir "haze_top_128_${ts}.log"]

transcript file $log_file
transcript on

puts "HAZE_REMOVAL_TOP automation"
puts "Log file: $log_file"

if {[info exists ::env(IMG_IN)]} {
    set img_in $::env(IMG_IN)
} else {
    set img_in "../01_sim/IPU/Testbench_DarkChannel_System/sim/image/test_128.bmp"
}

if {[info exists ::env(OUT_DIR)]} {
    set out_dir $::env(OUT_DIR)
} else {
    set out_dir "../01_sim/IPU/Testbench_HAZE_REMOVAL_TOP/sim/image/"
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
    $TB_DIR/haze_removal_top_128_tb.sv

vsim -c haze_removal_top_128_tb +IMG_IN=$img_in +OUT_DIR=$out_dir -do "run -all; quit -f"

