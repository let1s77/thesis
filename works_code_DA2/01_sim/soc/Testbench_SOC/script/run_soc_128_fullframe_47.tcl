onerror { quit -f }

if {[info exists ::env(IMG_IN)]} {
    set img_in $::env(IMG_IN)
} else {
    set img_in "01_sim/IPU/Testbench_DarkChannel_System/sim/image/47_hazy.bmp"
}

if {[info exists ::env(OUT_DIR)]} {
    set out_dir $::env(OUT_DIR)
} else {
    set out_dir "01_sim/soc/Testbench_SOC/sim/image_47/"
}

set proj_root [file normalize [pwd]]

set SRC_RV  [file join $proj_root 00_src RISC_V]
set SRC_SOC [file join $proj_root 00_src soc]
set SRC_IPU [file join $proj_root 00_src IPU]
set SRC_MEM [file join $proj_root 00_src IPU mem]
set TB_SIM  [file join $proj_root 01_sim soc Testbench_SOC sim]

file mkdir $out_dir

vlib work
vmap work work

vlog +acc +define+SIM_MODE \
    +incdir+$SRC_RV +incdir+$SRC_SOC +incdir+$SRC_IPU +incdir+$SRC_MEM \
    [file join $SRC_RV fa.sv] \
    [file join $SRC_RV cla_4bit.sv] \
    [file join $SRC_RV cla_32bit.sv] \
    [file join $SRC_RV alu.sv] \
    [file join $SRC_RV brc.sv] \
    [file join $SRC_RV control_logic.sv] \
    [file join $SRC_RV immgen.sv] \
    [file join $SRC_RV instr_mem.sv] \
    [file join $SRC_RV memory.sv] \
    [file join $SRC_RV mux2.sv] \
    [file join $SRC_RV mux3.sv] \
    [file join $SRC_RV pc.sv] \
    [file join $SRC_RV PCplus4.sv] \
    [file join $SRC_RV regfile.sv] \
    [file join $SRC_RV SevenSegment.sv] \
    [file join $SRC_RV peripherals.sv] \
    [file join $SRC_RV lsu_v1.sv] \
    [file join $SRC_RV single_cycle.sv] \
    [file join $SRC_SOC peri_apb_wrapper.sv] \
    [file join $SRC_SOC ipu_apb_wrapper.sv] \
    [file join $SRC_IPU src_min.sv] \
    [file join $SRC_IPU search_block_min.sv] \
    [file join $SRC_IPU sky_recognition.sv] \
    [file join $SRC_IPU min3_u8.sv] \
    [file join $SRC_IPU dark_channel.sv] \
    [file join $SRC_IPU atmospheric_light.sv] \
    [file join $SRC_IPU bank_bram.sv] \
    [file join $SRC_IPU bank_pingpong_stream.sv] \
    [file join $SRC_IPU estimate_transmission.sv] \
    [file join $SRC_IPU adc_pixel_distance.sv] \
    [file join $SRC_IPU adc_path_length.sv] \
    [file join $SRC_IPU adc_rlimit_compute.sv] \
    [file join $SRC_IPU adc_ase_masked_min.sv] \
    [file join $SRC_IPU adc_line_buffer_5x5.sv] \
    [file join $SRC_IPU adc_estimation.sv] \
    [file join $SRC_IPU frame_linear_counter.sv] \
    [file join $SRC_IPU invA_lut_q16.sv] \
    [file join $SRC_IPU omega_clamp_t.sv] \
    [file join $SRC_IPU norm_channel_q16.sv] \
    [file join $SRC_IPU ipu_control_logic.sv] \
    [file join $SRC_IPU grayscale.sv] \
    [file join $SRC_IPU t_computing.sv] \
    [file join $SRC_IPU recip_lut_q16.sv] \
    [file join $SRC_IPU fusing.sv] \
    [file join $SRC_IPU t_compute_fuse.sv] \
    [file join $SRC_IPU atm_light_coarse_tx.sv] \
    [file join $SRC_IPU haze_removal_core.sv] \
    [file join $SRC_IPU haze_removal_top.sv] \
    [file join $SRC_MEM img_in_bram.v] \
    [file join $SRC_MEM img_out_bram.v] \
    [file join $SRC_MEM ipu_bram_reader.v] \
    [file join $SRC_MEM ipu_bram_writer.v] \
    [file join $SRC_IPU ipu_soc.sv] \
    [file join $SRC_SOC soc_top.sv] \
    [file join $TB_SIM soc_128_tb.sv]

vsim -c soc_128_tb +IMG_IN=$img_in +OUT_DIR=$out_dir -do "run -all; quit -f"
