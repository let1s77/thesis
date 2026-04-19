# ==============================================================================
# Script: script_for_test_img.tcl
# Description: Compile & simulate Dark Channel System testbench
#              với ảnh test_128.bmp (128x128)
#
# Chạy từ thư mục: 02_questasim/
#   vsim -c -do "../01_sim/IPU/script/script_for_test_img.tcl"
#
# Lưu ý cấu trúc include:
#   testbench.sv
#     `include ROM.v
#     `include RAM.v
#     `include top.sv
#               `include dark_channel.sv
#               `include src_min.sv
#
#   => Toàn bộ design được kéo vào 1 compilation unit qua testbench.sv
#      KHÔNG compile riêng từng file (sẽ bị lỗi module re-definition)
# ==============================================================================

# 1. Tạo thư viện work ngay tại 02_questasim/
vlib work
vmap work work

# 2. Compile toàn bộ qua testbench.sv (dùng SV vì top.sv & dark_channel.sv là SV)
#    Không define P1/P2 => tự động dùng test_128.bmp (128x128)
vlog -sv +incdir+../01_sim/IPU/Testbench_DarkChannel_System/src \
         ../01_sim/IPU/Testbench_DarkChannel_System/sim/testbench.sv

# 3. Optimize
vopt testbench -o tb_dark_opt +acc

# 4. Simulate & ghi log
vsim -c tb_dark_opt -do "run -all; quit" | tee log/sim_dark_channel_128.log