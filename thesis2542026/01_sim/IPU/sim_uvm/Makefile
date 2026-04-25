## -------------------------------------------------------------
# This file created by Huy Nguyen
# Updated date: 01/09/2024
# Example run string: make TESTNAME={name_of_testcase} {optional}
#		     make run TESTNAME=a_fifo_base_test
## -------------------------------------------------------------
#
TB_NAME   ?=tb_top
TESTNAME  ?=a_fifo_base_test
VERBOSITY ?=UVM_HIGH
RUNARG    ?=
SEED      ?=1

ifeq ($(strip $(SEED)),random)
  SEED = $(shell /bin/date +%s)
endif

# -------------------------------------------------------------
# UVM debug options
# -------------------------------------------------------------
UVM_DEBUG = \
	+UVM_PHASE_TRACE \
	+UVM_OBJECTION_TRACE \
	+UVM_CONFIG_DB_TRACE
ifeq ($(strip $(SEED)),random)
  SEED = $(shell /bin/date +%s)
endif
##==============================================================

VLOG =  vlog \
        -timescale "1ns/1ps" \
        +define+UVM_NO_DPI \
        -mfcu \
        -suppress 2181 \
        +acc=rnb \
        +incdir+$(UVM_HOME)/src \
        $(UVM_HOME)/src/uvm.sv
		
VSIM =  vsim \
        -sv_seed ${SEED} \
        -voptargs=+acc \
        -assertdebug \
        -c ${TB_NAME}\
        -do "log -r /*;run -all;" \
        -l $(TESTNAME)_$(SEED).log	
##==============================================================

all: build run
build: 	vlib
	$(VLOG)  -f compile.f \
  	+define+UVM_OBJECT_MUST_HAVE_CONSTRUCTOR 
		
run:
	$(VSIM) +UVM_TESTNAME=$(TESTNAME) \
          +UVM_VERBOSITY=$(VERBOSITY) \
		  $(UVM_DEBUG) \
	    	${RUNARG} 
	-cp -f ${TESTNAME}_$(SEED).log ./log/
	-ln -sf ./log/${TESTNAME}_$(SEED).log run.log

vlib:
	mkdir -p log
	vlib work
	vmap work work

wave:
	vsim -i -view vsim.wlf -do "add wave vsim:/$(TB_NAME)/*;" &

clean: 
	rm -rf work
	rm -rf log
	rm -rf *.ini
	rm -rf *.log
	rm -rf *.trace
	rm -rf *.wlf
	rm -rf transcript
	rm -rf *.ucdb
