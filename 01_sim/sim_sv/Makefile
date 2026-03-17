## =============================================================
## IPU Testbench Makefile (SystemVerilog - non-UVM)
## Location: 01_sim/IPU/Makefile
##
## All vlog/vsim commands execute from 01_sim/ (parent dir)
## so that `include and $readmemh paths resolve correctly:
##   `include "../00_src/IPU/X.sv"  -->  00_src/IPU/X.sv
##   $readmemh("../09_pattern/X")   -->  09_pattern/X
##
## Usage:
##   make TEST=dark_channel
##   make TEST=atmospheric_light
##   make TEST=estimate_transmission
##   make TEST=dark_channel run        # simulate only (skip compile)
##   make wave TEST=dark_channel       # open waveform
##   make gen_pattern                  # generate hex files via Python
##   make clean
##   make help
## =============================================================

#---------------------------------------------------------------
# Test Selection (default: dark_channel)
# Options: dark_channel | atmospheric_light | estimate_transmission
#---------------------------------------------------------------
TEST ?= dark_channel

#---------------------------------------------------------------
# Path Setup
# All tool commands prefixed with $(RUN) to cd into 01_sim/
#---------------------------------------------------------------
RUN      = cd .. &&
WORK_LIB = IPU/work
LOG_DIR  = IPU/log

#---------------------------------------------------------------
# TB file + Top module mapping (paths relative to 01_sim/)
#---------------------------------------------------------------
TB_dark_channel              = IPU/dark_channel_tb_v2.sv
TOP_dark_channel             = dark_channel_tb

TB_atmospheric_light         = IPU/atmospheric_light_tb_v2.sv
TOP_atmospheric_light        = atmospheric_light_tb

TB_estimate_transmission     = IPU/estimate_tranmission_tb.sv
TOP_estimate_transmission    = tb_estimate_transmission

TB_FILE = $(TB_$(TEST))
TB_TOP  = $(TOP_$(TEST))

#---------------------------------------------------------------
# Tool Flags
#---------------------------------------------------------------
VLOG_FLAGS = -timescale "1ns/10ps" \
             -suppress 2181 \
             +acc=rnb

VSIM_FLAGS = -c $(TB_TOP) \
             -voptargs=+acc \
             -do "log -r /*; run -all; quit -f;" \
             -l $(LOG_DIR)/$(TEST).log

#---------------------------------------------------------------
# Targets
#---------------------------------------------------------------
.PHONY: all build run vlib wave gen_pattern clean help

all: build run

vlib:
	@mkdir -p log
	@$(RUN) vlib $(WORK_LIB) 2>/dev/null; true
	@$(RUN) vmap work $(WORK_LIB)

build: vlib
	$(RUN) vlog $(VLOG_FLAGS) $(TB_FILE)

run:
	$(RUN) vsim $(VSIM_FLAGS)
	@echo ""
	@echo ">>> Log saved: log/$(TEST).log"

wave:
	$(RUN) vsim -i -view $(LOG_DIR)/$(TEST).wlf \
		-do "add wave $(TB_TOP)/*;" &

gen_pattern:
	cd ../../03_sw && python dark_channel.py
	cd ../../03_sw && python atmospheric_light.py
	cd ../../03_sw && python estimate_transmission.py

clean:
	rm -rf work log
	rm -f transcript *.wlf *.ini *.log *.ucdb *.trace
	$(RUN) rm -f modelsim.ini transcript *.wlf

help:
	@echo "=============================================="
	@echo " IPU Testbench Makefile (SystemVerilog)"
	@echo "=============================================="
	@echo ""
	@echo "Usage: make TEST=<testname> [target]"
	@echo ""
	@echo "Available tests:"
	@echo "  dark_channel           Dark Channel Prior (min RGB)"
	@echo "  atmospheric_light      Atmospheric Light Estimation"
	@echo "  estimate_transmission  Transmission Map Estimation"
	@echo ""
	@echo "Targets:"
	@echo "  all   (default)  build + run"
	@echo "  build            compile RTL + TB"
	@echo "  run              simulate only"
	@echo "  wave             open waveform viewer"
	@echo "  gen_pattern      generate hex files from Python"
	@echo "  clean            remove generated files"
	@echo "  help             show this message"
	@echo ""
	@echo "Examples:"
	@echo "  make TEST=dark_channel"
	@echo "  make TEST=atmospheric_light"
	@echo "  make TEST=estimate_transmission"
	@echo "  make gen_pattern"
