# 1. Tạo thư viện work ngay tại 02_questasim/
vlib work
vmap work work

# 2. Compile RTL (đường dẫn tương đối từ 02_questasim/)
vlog ../00_src/IPU/invA_lut_q16.sv
vlog ../00_src/IPU/norm_channel_q16.sv
vlog ../00_src/IPU/min3_u8.sv
vlog ../00_src/IPU/omega_clamp_t.sv
vlog ../00_src/IPU/search_block_min.sv
vlog ../00_src/IPU/spatial_min3x3.sv
vlog ../00_src/IPU/estimate_transmission.sv

# 3. Compile TB
vlog ../01_sim/IPU/estimate_tranmission_tb.sv

# 4. Optimize (vopt) rồi simulate
vopt tb_estimate_transmission -o tb_opt +acc
vsim -c tb_opt -do "run -all; quit" | tee log/sim_estimate_transmission.log