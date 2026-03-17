# ==============================================================================
# Script: script_for_purple_system.tcl
# Description: Compile & run Purple Block Integration System Test (128x128 BMP)
# Run from: 02_questasim/
#   vsim -c -do "../01_sim/IPU/script/script_for_purple_system.tcl"
# ==============================================================================

# 1. Create work library
vlib work
vmap work work

# 2. Create output image directory (if not exists)
file mkdir "../01_sim/IPU/Testbench_Purple_Block_Integration/sim/image"

# 3. Compile all RTL sub-modules (same order as script_purple_integration.tcl)
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

# 4. Compile testbench
vlog -sv "../01_sim/IPU/Testbench_Purple_Block_Integration/sim/testbench.sv"

# 5. Optimize and simulate
vopt purple_system_tb -o tb_purple_sys_opt +acc
vsim -c tb_purple_sys_opt -do "run -all; quit" | tee log/sim_purple_system_128.log
