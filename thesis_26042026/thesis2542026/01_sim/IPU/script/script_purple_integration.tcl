# 1. Tao thu vien work
vlib work
vmap work work

# 2. Compile RTL (duong dan tuong doi tu 02_questasim/)
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

# 3. Compile TB
vlog -sv ../01_sim/IPU/purple_block_integration_tb.sv

# 4. Optimize roi simulate
vopt purple_block_integration_tb -o tb_opt +acc
vsim -c tb_opt -do "run -all; quit" | tee log/sim_purple_block_integration.log
