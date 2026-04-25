onerror { quit -f }

# Optional env override:
#   LOG_DIR : directory to store transcript logs
if {[info exists ::env(LOG_DIR)]} {
    set log_dir $::env(LOG_DIR)
} else {
    set log_dir "../01_sim/RISC_V/log"
}

file mkdir $log_dir
set ts [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]
set log_file [file join $log_dir "riscv_lsu_decode_apb_sram_${ts}.log"]

transcript file $log_file
transcript on

puts "RISC-V LSU decode APB/SRAM automation"
puts "Log file: $log_file"

vlib work
vmap work work

set SRC_DIR "../00_src/RISC_V"
set SOC_DIR "../00_src/soc"
set TB_DIR  "../01_sim/RISC_V"

vlog +acc \
    $SRC_DIR/fa.sv \
    $SRC_DIR/cla_4bit.sv \
    $SRC_DIR/cla_32bit.sv \
    $SRC_DIR/alu.sv \
    $SRC_DIR/brc.sv \
    $SRC_DIR/control_logic.sv \
    $SRC_DIR/immgen.sv \
    $SRC_DIR/instr_mem.sv \
    $SRC_DIR/memory.sv \
    $SRC_DIR/mux2.sv \
    $SRC_DIR/mux3.sv \
    $SRC_DIR/pc.sv \
    $SRC_DIR/PCplus4.sv \
    $SRC_DIR/regfile.sv \
    $SRC_DIR/SevenSegment.sv \
    $SRC_DIR/peripherals.sv \
    $SOC_DIR/peri_apb_wrapper.sv \
    $SRC_DIR/lsu_v1.sv \
    $SRC_DIR/single_cycle.sv \
    $TB_DIR/tb_lsu_decode_test_apb_sram.sv

vsim -c tb_lsu_decode -do "run -all; quit -f"
