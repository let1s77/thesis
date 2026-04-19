## =============================================================================
## SDC file: soc_top.sdc
## DE10-Standard FPGA Timing Constraints
## Device : Cyclone V 5CSXFC6D6F31C6
## Clock  : 50 MHz (CLOCK_50) from on-board oscillator
## Design : wrapper → soc_top (RISC-V 3-phase FSM + IPU haze removal)
## =============================================================================
##
## Architecture notes:
##   - RISC-V CPU runs a 3-phase FSM: FETCH → EXEC → MEM_WB (3 CPI)
##   - Combinational critical path in EXEC phase:
##       instr_mem read → decode → regfile → ALU (CLA 32-bit) → LSU addr decode
##   - All I/O pins (SW, KEY, LEDR, HEX, LCD, PC_debug) are slow human-speed
##     signals — they do not need cycle-accurate timing.
##   - KEY[0] is async reset, double-FF synchronized in wrapper.sv.
## =============================================================================


#**************************************************************
# Time Information
#**************************************************************

set_time_format -unit ns -decimal_places 3


#**************************************************************
# Create Clock
#**************************************************************
## 50 MHz clock from oscillator on DE10-Standard board
create_clock -name {CLOCK_50} -period 20.000 -waveform { 0.000 10.000 } [get_ports {CLOCK_50}]


#**************************************************************
# Clock Uncertainty
#**************************************************************
## Let Quartus compute jitter/skew from the actual device model.
## This replaces manual set_clock_uncertainty and removes the
## incorrect set_clock_latency -source (which was double-counting delay).
derive_clock_uncertainty


#**************************************************************
# Fitter Overconstraint (Quartus Prime Timing Analyzer §2.3.7)
#**************************************************************
## During fitting (quartus_fit), add extra setup margin so the
## fitter works harder on placement & routing of critical paths.
## This does NOT affect signoff STA (quartus_sta) — the actual
## timing report stays at the true 50 MHz / 20ns constraint.
if { ![catch {set _exe $::TimingAnalyzerInfo(nameofexecutable)}] } {
    if { $_exe eq "quartus_fit" } {
        set_clock_uncertainty -setup -to [get_clocks {CLOCK_50}] -add 2.000
    }
}


#**************************************************************
# False Paths — Async Reset
#**************************************************************
## KEY[0] is an asynchronous active-low reset.
## The wrapper.sv double-FF synchronizer (rst_sync_ff) handles metastability.
## No setup/hold requirement on this path — pure false path.
set_false_path -from [get_ports {KEY[0]}]


#**************************************************************
# False Paths — Slow Human-Speed I/O
#**************************************************************
## All board I/O (switches, LEDs, HEX displays, LCD, debug) operate
## at human speed (<1 Hz change rate). Constraining these to 50 MHz
## wastes fitter effort and artificially inflates TNS.
## Mark them as false paths so the fitter focuses on internal logic.

# Switches — asynchronous inputs, latched by sw_reg FF in LSU
set_false_path -from [get_ports {SW[*]}]

# Push buttons (KEY[1..3]) — active-low, directly to i_io_sw
set_false_path -from [get_ports {KEY[1]}]
set_false_path -from [get_ports {KEY[2]}]
set_false_path -from [get_ports {KEY[3]}]

# LED outputs — visual indicators, no timing requirement
set_false_path -to [get_ports {LEDR[*]}]
set_false_path -to [get_ports {LEDG[*]}]

# 7-segment HEX displays — visual, no timing requirement
set_false_path -to [get_ports {HEX0[*]}]
set_false_path -to [get_ports {HEX1[*]}]
set_false_path -to [get_ports {HEX2[*]}]
set_false_path -to [get_ports {HEX3[*]}]
set_false_path -to [get_ports {HEX4[*]}]
set_false_path -to [get_ports {HEX5[*]}]
set_false_path -to [get_ports {HEX6[*]}]
set_false_path -to [get_ports {HEX7[*]}]

# LCD — slow peripheral, no timing requirement
set_false_path -to [get_ports {LCD_DATA[*]}]
set_false_path -to [get_ports {LCD_EN}]
set_false_path -to [get_ports {LCD_RS}]
set_false_path -to [get_ports {LCD_RW}]
set_false_path -to [get_ports {LCD_ON}]
set_false_path -to [get_ports {LCD_BLON}]

# PC debug output — diagnostic only, no timing requirement
set_false_path -to [get_ports {PC_debug[*]}]

# VGA outputs — driven by PLL-generated 25 MHz clock, separate domain
set_false_path -to [get_ports {VGA_R[*]}]
set_false_path -to [get_ports {VGA_G[*]}]
set_false_path -to [get_ports {VGA_B[*]}]
set_false_path -to [get_ports {VGA_CLK}]
set_false_path -to [get_ports {VGA_HS}]
set_false_path -to [get_ports {VGA_VS}]
set_false_path -to [get_ports {VGA_BLANK_N}]
set_false_path -to [get_ports {VGA_SYNC_N}]

