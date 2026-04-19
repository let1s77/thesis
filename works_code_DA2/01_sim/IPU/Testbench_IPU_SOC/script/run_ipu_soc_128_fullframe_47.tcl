onerror { quit -f }

if {[info exists ::env(IMG_IN)]} {
    set img_in $::env(IMG_IN)
} else {
    set img_in "../01_sim/IPU/Testbench_DarkChannel_System/sim/image/47_hazy.bmp"
}

if {[info exists ::env(GOLDEN_IN)]} {
    set golden_in $::env(GOLDEN_IN)
} else {
    set golden_in "../01_sim/IPU/Testbench_HAZE_REMOVAL_TOP/sim/image_47_hazy/haze_recovery_128.bmp"
}

if {[info exists ::env(OUT_DIR)]} {
    set out_dir $::env(OUT_DIR)
} else {
    set out_dir "../01_sim/IPU/Testbench_IPU_SOC/sim/image_47/"
}

vlib work
vmap work work

set SRC_DIR      "../00_src/IPU"
set SRC_MEM_DIR  "../00_src/IPU/mem"
set SRC_SOC_DIR  "../00_src/soc"
set TB_DIR       "../01_sim/IPU/Testbench_IPU_SOC/sim"

vlog +acc +define+SIM_MODE \
    +incdir+$SRC_DIR \
    +incdir+$SRC_MEM_DIR \
    +incdir+$SRC_SOC_DIR \
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
    $SRC_MEM_DIR/img_in_bram.v \
    $SRC_MEM_DIR/img_out_bram.v \
    $SRC_MEM_DIR/ipu_bram_reader.v \
    $SRC_MEM_DIR/ipu_bram_writer.v \
    $SRC_DIR/ipu_soc.sv \
    $TB_DIR/ipu_soc_128_tb.sv

vsim -c ipu_soc_128_tb +IMG_IN=$img_in +GOLDEN_IN=$golden_in +OUT_DIR=$out_dir -do "run -all; quit -f"
