# ==============================================================================
# Script: script_for_test_grayscale.tcl
# Description: Compile & simulate Grayscale Image Converter testbench
#              với ảnh test_128.bmp (128x128)
#
# Chạy từ thư mục: 02_questasim/
#   vsim -c -do "../01_sim/IPU/script/script_for_test_grayscale.tcl"
#
# Lưu ý cấu trúc include (đường dẫn tương đối từ vị trí file):
#   testbench.sv  (in sim/)
#     `include "../src/ROM.v"
#     `include "../src/RAM.v"
#     `include "../src/top.v"
#               `include "../src/grayscale.v"
#
#   => Toàn bộ design được kéo vào 1 compilation unit qua testbench.sv
#      KHÔNG compile riêng từng file (sẽ bị lỗi module re-definition)
#   => Không define P1/P2/TEST => tự động dùng test_128.bmp (128x128)
#      Output: sim/image/gray_test_128.bmp
# ==============================================================================

# 1. Tạo thư viện work ngay tại 02_questasim/
vlib work
vmap work work

# 2. Compile toàn bộ qua testbench.sv
#    Dùng -sv vì testbench.sv dùng SystemVerilog (logic, typedef enum, ...)
#    +incdir giúp Questa tìm file khi `include dùng tên file đơn giản
vlog -sv "+incdir+../01_sim/IPU/Testbench_Grayscale Image Converter_System/src" \
         "../01_sim/IPU/Testbench_Grayscale Image Converter_System/sim/testbench.sv"

# 3. Optimize (top module tên là testfixture)
vopt testfixture -o tb_gray_opt +acc

# 4. Simulate & ghi log
vsim -c tb_gray_opt -do "run -all; quit" | tee log/sim_grayscale_128.log