# ==============================================================================
# script_for_adc_sub.tcl
# Run from: 02_questasim/
# Usage:    do ../01_sim/IPU/script/script_for_adc_sub.tcl
#
# ADC Estimation sub-block testbenches (bottom-up order)
# Uncomment the section you want to run.
# ==============================================================================

vlib work
vmap work work

# ======================================================================
# [1] adc_pixel_distance_tb  (Stage 1 — no dependency)
# ======================================================================
# vlog ../00_src/IPU/adc_pixel_distance.sv
# vlog ../01_sim/IPU/adc_pixel_distance_tb.sv
# vopt adc_pixel_distance_tb -o tb_opt +acc
# vsim -c tb_opt -do "run -all; quit" | tee log/sim_adc_pixel_distance.log

# ======================================================================
# [2] adc_path_length_tb  (Stage 2 — depends on pixel_distance output)
# ======================================================================
# vlog ../00_src/IPU/adc_path_length.sv
# vlog ../01_sim/IPU/adc_path_length_tb.sv
# vopt adc_path_length_tb -o tb_opt +acc
# vsim -c tb_opt -do "run -all; quit" | tee log/sim_adc_path_length.log

# ======================================================================
# [3] adc_rlimit_compute_tb  (Stage 3-4 — depends on path_length output)
# ======================================================================
# vlog ../00_src/IPU/adc_rlimit_compute.sv
# vlog ../01_sim/IPU/adc_rlimit_compute_tb.sv
# vopt adc_rlimit_compute_tb -o tb_opt +acc
# vsim -c tb_opt -do "run -all; quit" | tee log/sim_adc_rlimit_compute.log  

# ======================================================================
# [4] adc_ase_masked_min_tb  (Stage 5 — depends on rlimit + dl + mc)
# ======================================================================
# vlog ../00_src/IPU/adc_ase_masked_min.sv
# vlog ../01_sim/IPU/adc_ase_masked_min_tb.sv
# vopt adc_ase_masked_min_tb -o tb_opt +acc
# vsim -c tb_opt -do "run -all; quit" | tee log/sim_adc_ase_masked_min.log

# ======================================================================
# [5] adc_estimation_tb  (Top-level integration — full pipeline)
#     IMG_WIDTH=5, IMG_HEIGHT=5 → 25 pixels/frame → 1 ADC output/frame
#     Reuses sub-block patterns: gray from pixel_distance, mc from ase
# ======================================================================
# vlog ../00_src/IPU/adc_line_buffer_5x5.sv
# vlog ../00_src/IPU/adc_pixel_distance.sv
# vlog ../00_src/IPU/adc_path_length.sv
# vlog ../00_src/IPU/adc_rlimit_compute.sv
# vlog ../00_src/IPU/adc_ase_masked_min.sv
# vlog ../00_src/IPU/adc_estimation.sv
# vlog ../01_sim/IPU/adc_estimation_tb.sv
# vopt adc_estimation_tb -o tb_opt +acc
# vsim -c tb_opt -do "run -all; quit" | tee log/sim_adc_estimation.log
