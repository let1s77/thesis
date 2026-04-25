onerror { quit -f }

if {[info exists ::env(LOG_DIR)]} {
    set log_dir $::env(LOG_DIR)
} else {
    set log_dir "./01_sim/apb4/log"
}

file mkdir $log_dir
set ts [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]
set log_file [file join $log_dir "apb_basic_${ts}.log"]

transcript file $log_file
transcript on

puts "APB basic functional automation"
puts "Log file: $log_file"

vlib work
vmap work work

set APB_DIR "./00_src/apb_bus"
set TB_DIR  "./01_sim/apb4/tb"

vlog +acc \
    $APB_DIR/APB_Master.v \
    $APB_DIR/APB_Slave.v \
    $APB_DIR/APB_Wrapper.v \
    $TB_DIR/tb_apb_basic_func.v

vsim -c tb_apb_basic_func -do "run -all; quit -f"
