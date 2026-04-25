# ======================================================================
# script_for_t_compute_fuse.tcl
# Run from: 02_questasim/
# Usage:    do ../01_sim/IPU/script/script_for_t_compute_fuse.tcl
# ======================================================================

file mkdir log

vlib work
vmap work work

vlog ../00_src/IPU/t_computing.sv
vlog ../00_src/IPU/fusing.sv
vlog ../00_src/IPU/t_compute_fuse.sv
vlog ../01_sim/IPU/t_compute_fuse_tb.sv

vopt t_compute_fuse_tb -o tb_opt +acc
vsim -c tb_opt -l log/sim_t_compute_fuse.log -do "run -all; quit" | tee log/sim_t_compute_fuse.log
