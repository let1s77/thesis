+incdir+${ASYNC_FIFO_VERIF_PATH}/sequences
+incdir+${ASYNC_FIFO_VERIF_PATH}/test_case
+incdir+${ASYNC_FIFO_VERIF_PATH}/tb

// Compilation VIP design (agent) list
-f ${ASYNC_FIFO_VIP_ROOT}/a_fifo_vip.f

// Compilation Environment
${ASYNC_FIFO_VERIF_PATH}/tb/env_pkg.sv
${ASYNC_FIFO_VERIF_PATH}/sequences/seq_pkg.sv
${ASYNC_FIFO_VERIF_PATH}/test_case/test_pkg.sv
${ASYNC_FIFO_VERIF_PATH}/tb/tb_top.sv

