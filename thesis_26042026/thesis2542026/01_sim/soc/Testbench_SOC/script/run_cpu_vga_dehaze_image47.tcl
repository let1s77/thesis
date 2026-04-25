# =============================================================================
# run_cpu_vga_dehaze_image47.tcl
#
# QuestaSim script: CPU-driven IPU dehaze + VGA verification
# Image: image_47 (hazy outdoor)
#   Input : 01_sim/soc/Testbench_SOC/sim/image_47/soc_input_128.bmp
#   Output: 01_sim/soc/Testbench_SOC/sim/image_47/cpu_dehazed_128.bmp
#
# Cách chạy (từ thư mục gốc thesis2542026/):
#   vsim -do "do 01_sim/soc/Testbench_SOC/script/run_cpu_vga_dehaze_image47.tcl"
# =============================================================================

onerror { quit -f }

# ─────────────────────────────────────────────────────────────────────────────
# Logging
# ─────────────────────────────────────────────────────────────────────────────
if {[info exists ::env(LOG_DIR)]} {
    set log_dir $::env(LOG_DIR)
} else {
    set log_dir "01_sim/soc/Testbench_SOC/log"
}
file mkdir $log_dir
set ts       [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]
set log_file [file join $log_dir "cpu_vga_dehaze_image47_${ts}.log"]
transcript file $log_file
transcript on

puts "============================================================"
puts " CPU-Driven VGA Dehaze Test  —  image_47"
puts " Log: $log_file"
puts "============================================================"

# ─────────────────────────────────────────────────────────────────────────────
# Đường dẫn
# ─────────────────────────────────────────────────────────────────────────────
set proj_root [file normalize [pwd]]

set img_in  "01_sim/soc/Testbench_SOC/sim/image_47/soc_input_128.bmp"
set out_dir "01_sim/soc/Testbench_SOC/sim/image_47/"

if {[info exists ::env(IMG_IN)]}  { set img_in  $::env(IMG_IN)  }
if {[info exists ::env(OUT_DIR)]} { set out_dir $::env(OUT_DIR) }

file mkdir $out_dir

# ─────────────────────────────────────────────────────────────────────────────
# Bước 1: Compile ASM → hex  (dùng asm2hex.py)
# ─────────────────────────────────────────────────────────────────────────────
set asm_src  "11_asm/vga_dehaze_fulltest.s"
set hex_out  "01_sim/RISC_V/02_test/vga_dehaze_fulltest.hex"
set hex_abs  [file normalize $hex_out]

puts "\[STEP 1] Assembling: $asm_src → $hex_out"
file mkdir [file dirname $hex_abs]
set asm_result [catch {exec python 12_test/asm2hex.py $asm_src -o $hex_out} asm_msg]
if {$asm_result != 0} {
    puts "ERROR: asm2hex.py failed:\n$asm_msg"
    quit -f
}
puts "Assembly OK: $hex_abs"

# ─────────────────────────────────────────────────────────────────────────────
# Bước 2: Compile design
# ─────────────────────────────────────────────────────────────────────────────
puts "\[STEP 2] Compiling design..."

set SRC_RV  [file join $proj_root 00_src RISC_V]
set SRC_SOC [file join $proj_root 00_src soc]
set SRC_IPU [file join $proj_root 00_src IPU]
set SRC_MEM [file join $proj_root 00_src IPU mem]
set TB_SIM  [file join $proj_root 01_sim soc Testbench_SOC sim]

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
    [file join $SRC_MEM img_tmp_bram.v] \
    [file join $SRC_MEM ipu_bram_reader.v] \
    [file join $SRC_MEM ipu_bram_writer.v] \
    [file join $SRC_IPU ipu_core.sv] \
    [file join $SRC_IPU ipu_soc.sv] \
    [file join $SRC_SOC soc_top.sv] \
    [file join $TB_SIM tb_cpu_vga_dehaze.sv]

# ─────────────────────────────────────────────────────────────────────────────
# Bước 3: Elaborate + Simulate
# ─────────────────────────────────────────────────────────────────────────────
puts "\[STEP 3] Simulating with CPU running vga_dehaze_fulltest.hex..."
puts "         IMEM hex: $hex_abs"

vsim -c tb_cpu_vga_dehaze \
    -g "/tb_cpu_vga_dehaze/dut/u_single_cycle/instr_mem_inst/MEM=$hex_abs" \
    +IMG_IN=$img_in \
    +OUT_DIR=$out_dir \
    -do "run -all; quit -f"

puts "============================================================"
puts " DONE. Output: ${out_dir}cpu_dehazed_128.bmp"
puts "============================================================"
