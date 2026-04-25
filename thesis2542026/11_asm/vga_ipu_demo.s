# =============================================================================
# vga_ipu_demo.s — FPGA demo: trigger IPU haze-removal + display via VGA
#
# File này dùng CHUNG cho cả 2 ảnh:
#   - image_test : 01_sim/soc/Testbench_SOC/sim/image_test/soc_input_128.bmp
#   - image_47   : 01_sim/soc/Testbench_SOC/sim/image_47/soc_input_128.bmp
#
# Sự khác biệt giữa 2 ảnh nằm ở file hex nạp vào img_in_bram lúc synthesis,
# KHÔNG phải ở ASM code (ASM hoàn toàn giống nhau).
#
# Prerequisites (trước khi burn FPGA):
#   1. Chạy bmp2bram_hex.py để convert BMP → hex:
#        python 03_sw/bmp2bram_hex.py \
#               01_sim/soc/Testbench_SOC/sim/image_test/soc_input_128.bmp \
#               -o 09_pattern/img_in_cityscape.hex
#      hoặc:
#        python 03_sw/bmp2bram_hex.py \
#               01_sim/soc/Testbench_SOC/sim/image_47/soc_input_128.bmp \
#               -o 09_pattern/img_in_image47.hex
#   2. Set parameter INIT_FILE trong img_in_bram (qua soc_top.sv) trỏ tới hex đó.
#   3. Convert ASM này sang hex:
#        python 12_test/asm2hex.py 11_asm/vga_ipu_demo.s \
#               -o 01_sim/RISC_V/02_test/vga_ipu_demo.hex
#   4. Cập nhật instr_mem.sv: parameter MEM = "...vga_ipu_demo.hex"
#   5. Re-synthesize + program FPGA.
#
# Flow runtime (trên FPGA):
#   1. CPU configure IPU registers qua APB (SRC/DST/TMP addr, width, height, stride, IRQ)
#   2. CPU trigger IPU: CTRL=3 → CTRL=1  (pulsed START)
#   3. CPU poll IPU_IRQ_STATUS[0] cho đến khi = 1 (IPU done)
#   4. CPU clear IRQ, bật toàn bộ LEDR báo hiệu xong
#   5. CPU loop vô hạn → VGA hardware tự đọc img_out_bram và hiển thị lên monitor
#
# Memory Map (soc_addr_map.vh):
#   IMG_IN_BUF   = 0x0001_0000  (pre-loaded hex vào BRAM lúc synthesis)
#   IMG_OUT_BUF  = 0x0004_0000  (IPU ghi output, VGA đọc từ đây)
#   IMG_TMP_BUF  = 0x0007_0000
#   IPU_BASE     = 0x1002_0000
#   PERI_BASE    = 0x1000_0000
#
# IPU Register offsets (ipu_addr_map_soc.vh):
#   CTRL         = +0x00   [EN=bit0, START=bit1]
#   STATUS       = +0x04   [IDLE=bit0, BUSY=bit1, DONE=bit2]
#   SRC_ADDR     = +0x08
#   DST_ADDR     = +0x0C
#   TMP_ADDR     = +0x10
#   IMG_WIDTH    = +0x14
#   IMG_HEIGHT   = +0x18
#   IMG_STRIDE   = +0x1C   (bytes per row = width * 4)
#   IRQ_EN       = +0x30   [bit0 = enable DONE irq]
#   IRQ_STATUS   = +0x34   [bit0 = done flag, write-1-to-clear]
# =============================================================================

_start:
    #----------------------------------------------------------
    # t0 = IPU_BASE = 0x1002_0000
    # lui rd, imm20: rd = imm20 << 12
    # 0x1002_0000 / 0x1000 = 0x10020
    #----------------------------------------------------------
    lui     t0, 0x10020

    #----------------------------------------------------------
    # IPU_SRC_ADDR [+0x08] = 0x0001_0000  (IMG_IN_BUF_BASE)
    # 0x0001_0000 / 0x1000 = 0x10
    #----------------------------------------------------------
    lui     a0, 0x10
    sw      a0, 0x08(t0)

    #----------------------------------------------------------
    # IPU_DST_ADDR [+0x0C] = 0x0004_0000  (IMG_OUT_BUF_BASE)
    # 0x0004_0000 / 0x1000 = 0x40
    #----------------------------------------------------------
    lui     a0, 0x40
    sw      a0, 0x0C(t0)

    #----------------------------------------------------------
    # IPU_TMP_ADDR [+0x10] = 0x0007_0000  (IMG_TMP_BUF_BASE)
    # 0x0007_0000 / 0x1000 = 0x70
    #----------------------------------------------------------
    lui     a0, 0x70
    sw      a0, 0x10(t0)

    #----------------------------------------------------------
    # IPU_IMG_WIDTH [+0x14] = 128 = 0x80
    #----------------------------------------------------------
    addi    a0, zero, 128
    sw      a0, 0x14(t0)

    #----------------------------------------------------------
    # IPU_IMG_HEIGHT [+0x18] = 128 = 0x80 (a0 still = 128)
    #----------------------------------------------------------
    sw      a0, 0x18(t0)

    #----------------------------------------------------------
    # IPU_IMG_STRIDE [+0x1C] = 512  (128 pixels * 4 bytes/pixel)
    # a0 = 128, slli a0, a0, 2 → a0 = 512
    #----------------------------------------------------------
    slli    a0, a0, 2
    sw      a0, 0x1C(t0)

    #----------------------------------------------------------
    # IPU_IRQ_EN [+0x30] = 1  (enable DONE flag)
    #----------------------------------------------------------
    addi    a0, zero, 1
    sw      a0, 0x30(t0)

    #----------------------------------------------------------
    # Trigger IPU: CTRL = 3 → EN=1, START=1
    #----------------------------------------------------------
    addi    a0, zero, 3
    sw      a0, 0x00(t0)

    #----------------------------------------------------------
    # CTRL = 1 → EN=1, START=0  (creates rising+falling pulse on START)
    #----------------------------------------------------------
    addi    a0, zero, 1
    sw      a0, 0x00(t0)

    #----------------------------------------------------------
    # Poll IPU_IRQ_STATUS [+0x34] bit0 cho đến khi = 1 (IPU done)
    # Mỗi vòng poll ~ 2 cycles (lw + beqz)
    # Tại 50 MHz: IPU xử lý 128x128 mất ~655 µs ≈ 32750 cycles
    #----------------------------------------------------------
wait_irq:
    lw      a1, 0x34(t0)
    beqz    a1, wait_irq

    #----------------------------------------------------------
    # Clear IRQ_STATUS: write 1 to acknowledge (W1C)
    #----------------------------------------------------------
    addi    a0, zero, 1
    sw      a0, 0x34(t0)

    #----------------------------------------------------------
    # Bật toàn bộ LEDR báo hiệu IPU done
    # PERI_RED_LED_ADDR = 0x1000_0000
    # t1 = 0x1000_0000,  a0 = 0xFFFF_FFFF (addi zero,-1 = -1 → 0xFFF...F)
    #----------------------------------------------------------
    lui     t1, 0x10000
    addi    a0, zero, -1
    sw      a0, 0x00(t1)

    #----------------------------------------------------------
    # Infinite loop — VGA hardware đọc img_out_bram liên tục
    # và hiển thị ảnh đã dehazing lên monitor.
    #----------------------------------------------------------
halt:
    j       halt
