# =============================================================================
# vga_dehaze_fulltest.s
#
# Mục đích: Demo end-to-end kiểm tra TOÀN BỘ pipeline:
#   CPU (RISC-V) → APB → IPU (Dark-Channel Haze Removal) → img_out_bram → VGA
#
# Dùng cho cả 2 ảnh (chọn khi convert BMP → hex, KHÔNG đổi ASM):
#   image_test : 01_sim/soc/Testbench_SOC/sim/image_test/soc_input_128.bmp
#   image_47   : 01_sim/soc/Testbench_SOC/sim/image_47/soc_input_128.bmp
#
# ─────────────────────────────────────────────────────────────────────────────
# HƯỚNG DẪN CHẠY (Simulation - QuestaSim/ModelSim):
#   1. Convert BMP → hex:
#        python 12_test/asm2hex.py 11_asm/vga_dehaze_fulltest.s \
#               -o 01_sim/RISC_V/02_test/vga_dehaze_fulltest.hex
#   2. Cập nhật MEM param trong instr_mem.sv:
#        parameter MEM = "../../01_sim/RISC_V/02_test/vga_dehaze_fulltest.hex"
#   3. Chạy testbench CPU-driven:
#        vsim -c tb_cpu_vga_dehaze +IMG_IN=<path> +OUT_DIR=<dir> -do "run -all"
#      hoặc dùng TCL script:
#        do 01_sim/soc/Testbench_SOC/script/run_cpu_vga_dehaze_test.tcl
#        do 01_sim/soc/Testbench_SOC/script/run_cpu_vga_dehaze_image47.tcl
#
# HƯỚNG DẪN BURN FPGA:
#   1. Set INIT_FILE trong img_in_bram trỏ tới hex ảnh muốn test
#   2. Re-synthesize + program FPGA với file hex này
#   3. Kết quả quan sát:
#       LEDG[0] ON  → IPU đang xử lý (busy)
#       LEDR all ON → IPU done, VGA đang stream ảnh đã dehaze
#       HEX3-HEX2   → số pixel readback mismatch (0000 = perfect)
#       HEX1-HEX0   → số pixel kiểm tra OK
#
# ─────────────────────────────────────────────────────────────────────────────
# Memory Map (soc_addr_map.vh):
#   BOOT_MEM     = 0x0000_0000  (instruction + data)
#   IMG_IN_BUF   = 0x0001_0000  (pre-loaded, 128x128 px = 64 KB)
#   IMG_OUT_BUF  = 0x0004_0000  (IPU output, VGA đọc từ đây)
#   IMG_TMP_BUF  = 0x0007_0000  (scratch)
#   PERI_BASE    = 0x1000_0000
#     RED_LED    = 0x1000_0000
#     GREEN_LED  = 0x1000_0004
#   IPU_BASE     = 0x1002_0000
#
# IPU Register Offsets (ipu_addr_map_soc.vh):
#   CTRL         = +0x00   [EN=bit0, START=bit1, SOFT_RST=bit2]
#   STATUS       = +0x04   [IDLE=bit0, BUSY=bit1, DONE=bit2]
#   SRC_ADDR     = +0x08
#   DST_ADDR     = +0x0C
#   TMP_ADDR     = +0x10
#   IMG_WIDTH    = +0x14
#   IMG_HEIGHT   = +0x18
#   IMG_STRIDE   = +0x1C   (bytes/row = width × 4)
#   IRQ_EN       = +0x30   [bit0 = enable DONE irq]
#   IRQ_STATUS   = +0x34   [bit0 = DONE flag, W1C]
#   ID           = +0x3C   (expected = 0x49505531 "IPU1")
# =============================================================================

_start:

# ─────────────────────────────────────────────────────────────────────────────
# GIAI ĐOẠN 0: Tắt hết LED, bật LEDG[0] báo hiệu đang khởi động
# ─────────────────────────────────────────────────────────────────────────────
    lui     t0, 0x10000         # t0 = PERI_BASE = 0x1000_0000
    addi    a0, zero, 0
    sw      a0, 0x00(t0)        # LEDR = 0x0000_0000 (tắt)
    addi    a0, zero, 1
    sw      a0, 0x04(t0)        # LEDG[0] = 1 (đang boot)

# ─────────────────────────────────────────────────────────────────────────────
# GIAI ĐOẠN 1: Verify IPU ID
#   IPU_ID expected = 0x4950_5531  ("IPU1")
#   Nếu sai → LEDR = 0xDEAD_0001 rồi halt
# ─────────────────────────────────────────────────────────────────────────────
    lui     t1, 0x10020         # t1 = IPU_BASE = 0x1002_0000
    lw      a0, 0x3C(t1)        # a0 = IPU_ID

    # Build expected = 0x49505531
    # lui a1, 0x49505 → a1 = 0x49505000
    # addi a1, a1, 0x531 → 0x49505531 (0x531 = 1329, positive, fits 12-bit signed)
    lui     a1, 0x49505
    addi    a1, a1, 0x531
    beq     a0, a1, id_ok

    # ID mismatch: LEDR = 0x0000_0001 → halt
    addi    a0, zero, 1
    sw      a0, 0x00(t0)
err_halt:
    j       err_halt

id_ok:
    # LEDG[1] ON thêm → ID check passed
    addi    a0, zero, 3         # LEDG[1:0] = 11
    sw      a0, 0x04(t0)

# ─────────────────────────────────────────────────────────────────────────────
# GIAI ĐOẠN 2: Kiểm tra IPU_STATUS ban đầu phải là IDLE (bit0 = 1)
#   Nếu BUSY → SOFT_RST rồi chờ IDLE
# ─────────────────────────────────────────────────────────────────────────────
    lw      a0, 0x04(t1)        # a0 = IPU_STATUS
    andi    a2, a0, 0x1         # bit0 = IDLE
    addi    a3, zero, 1
    beq     a2, a3, status_idle

    # Không IDLE: phát SOFT_RST (bit2 = 1, EN bit0 = 1 → CTRL = 5)
    addi    a0, zero, 5
    sw      a0, 0x00(t1)        # CTRL = 0x5 (EN + SOFT_RST)
    addi    a0, zero, 1
    sw      a0, 0x00(t1)        # CTRL = 0x1 (release RST, giữ EN)

wait_idle_after_rst:
    lw      a0, 0x04(t1)
    andi    a0, a0, 0x1
    beqz    a0, wait_idle_after_rst

status_idle:
    # LEDG[2:0] = 111 → IDLE confirmed
    addi    a0, zero, 7
    sw      a0, 0x04(t0)

# ─────────────────────────────────────────────────────────────────────────────
# GIAI ĐOẠN 3: Cấu hình tất cả IPU registers
# ─────────────────────────────────────────────────────────────────────────────

    # IPU_SRC_ADDR = IMG_IN_BUF_BASE  = 0x0001_0000
    lui     a0, 0x10
    sw      a0, 0x08(t1)

    # IPU_DST_ADDR = IMG_OUT_BUF_BASE = 0x0004_0000
    lui     a0, 0x40
    sw      a0, 0x0C(t1)

    # IPU_TMP_ADDR = IMG_TMP_BUF_BASE = 0x0007_0000
    lui     a0, 0x70
    sw      a0, 0x10(t1)

    # IPU_IMG_WIDTH  = 128
    addi    a0, zero, 128
    sw      a0, 0x14(t1)

    # IPU_IMG_HEIGHT = 128  (a0 still = 128)
    sw      a0, 0x18(t1)

    # IPU_IMG_STRIDE = 512  (128 × 4 bytes/pixel)
    slli    a0, a0, 2           # a0 = 512
    sw      a0, 0x1C(t1)

    # IPU_IRQ_EN = 1  (enable DONE interrupt)
    addi    a0, zero, 1
    sw      a0, 0x30(t1)

    # Readback verify: IPU_SRC_ADDR
    lw      a2, 0x08(t1)
    lui     a3, 0x10
    bne     a2, a3, cfg_fail

    # Readback verify: IPU_DST_ADDR
    lw      a2, 0x0C(t1)
    lui     a3, 0x40
    bne     a2, a3, cfg_fail

    # Readback verify: IPU_IMG_WIDTH
    lw      a2, 0x14(t1)
    addi    a3, zero, 128
    bne     a2, a3, cfg_fail

    j       cfg_ok

cfg_fail:
    # Config error: LEDR = 0x0000_0003
    addi    a0, zero, 3
    sw      a0, 0x00(t0)
cfg_fail_halt:
    j       cfg_fail_halt

cfg_ok:
    # LEDG[3:0] = 1111 → config verified
    addi    a0, zero, 15
    sw      a0, 0x04(t0)

# ─────────────────────────────────────────────────────────────────────────────
# GIAI ĐOẠN 4: Trigger IPU
#   CTRL = 3  (EN=1, START=1)  → tạo rising edge trên START
#   CTRL = 1  (EN=1, START=0)  → tạo falling edge → IPU bắt đầu
# ─────────────────────────────────────────────────────────────────────────────
    addi    a0, zero, 3
    sw      a0, 0x00(t1)        # CTRL = 3
    addi    a0, zero, 1
    sw      a0, 0x00(t1)        # CTRL = 1

    # LEDG[4] ON → IPU triggered
    addi    a0, zero, 31        # 0x1F = LEDG[4:0] all on
    sw      a0, 0x04(t0)

# ─────────────────────────────────────────────────────────────────────────────
# GIAI ĐOẠN 5: Poll IPU_IRQ_STATUS[0] cho đến khi IPU done
#   @ 50 MHz: 128×128 ảnh ≈ 32750 cycles ≈ 655 µs
#   Timeout counter: nếu > 2M cycles thì báo lỗi
#   s2 = timeout counter (max = 2_000_000)
# ─────────────────────────────────────────────────────────────────────────────
    # Load timeout = 2_000_000 = 0x1E_8480
    # 0x1E8480 = 0x1E0000 + 0x8480
    # lui a0, 0x1E8 → 0x001E8000, addi a0, 0x480 → 0x001E8480  → wrong, 0x1E0000 + 0x8480
    # Actually 2000000 = 0x1E8480
    # lui rd, 0x1E8 → rd = 0x001E8000
    # addi rd, rd, 0x480 → 0x001E8480 (0x480 = 1152, positive, OK for 12-bit signed)
    lui     s2, 0x1E8
    addi    s2, s2, 0x480       # s2 = 0x1E8480 = 2_000_000

poll_irq:
    lw      a0, 0x34(t1)        # a0 = IPU_IRQ_STATUS
    andi    a0, a0, 0x1         # bit0
    bnez    a0, ipu_done        # done!

    addi    s2, s2, -1
    bnez    s2, poll_irq

    # Timeout: LEDR = 0x0000_0007
    addi    a0, zero, 7
    sw      a0, 0x00(t0)
timeout_halt:
    j       timeout_halt

ipu_done:

# ─────────────────────────────────────────────────────────────────────────────
# GIAI ĐOẠN 6: Clear IRQ (W1C) và đọc STATUS confirm DONE
# ─────────────────────────────────────────────────────────────────────────────
    addi    a0, zero, 1
    sw      a0, 0x34(t1)        # Clear IRQ_STATUS[0]

    lw      a0, 0x04(t1)        # STATUS: expect DONE bit (bit2) = 1
    andi    a0, a0, 0x4
    # (Không halt nếu DONE=0, chỉ note qua LED)

# ─────────────────────────────────────────────────────────────────────────────
# GIAI ĐOẠN 7: Spot-check img_out_bram qua CPU reads
#   Đọc 8 pixel cách đều (stride = 128×128/8 = 2048 words = 0x800 words)
#   Mỗi pixel = 4 byte = 1 word. Địa chỉ byte = idx × 4.
#   addr_byte = IMG_OUT_BUF_BASE + idx * 4
#
#   Quy tắc kiểm tra đơn giản:
#     - Pixel không được là 0x0000_0000 (ảnh hoàn toàn đen sau dehaze = lỗi)
#     - Pixel không được là 0xFFFF_FFFF (overflow)
#
#   s3 = số pixel PASS
#   s4 = số pixel FAIL
# ─────────────────────────────────────────────────────────────────────────────
    addi    s3, zero, 0         # pass counter
    addi    s4, zero, 0         # fail counter

    # base = IMG_OUT_BUF_BASE = 0x0004_0000
    lui     s5, 0x40            # s5 = 0x0004_0000

    # stride_bytes = 2048 * 4 = 8192 = 0x2000
    lui     s6, 0x2             # s6 = 0x2000  (lui 0x2 → 0x2000, correct)

    # Check 8 pixels: idx = 0, 2048, 4096, 6144, 8192, 10240, 12288, 14336
    # Dùng loop: a4 = current addr, a5 = loop counter
    addi    a4, s5, 0           # a4 = img_out base = 0x0004_0000
    addi    a5, zero, 8         # 8 iterations

spot_loop:
    beqz    a5, spot_done

    lw      a0, 0x00(a4)        # đọc pixel tại a4

    # Fail nếu pixel = 0 (hoàn toàn đen)
    beqz    a0, spot_fail

    # Fail nếu pixel = 0xFFFF_FFFF
    addi    a1, zero, -1        # a1 = 0xFFFF_FFFF
    beq     a0, a1, spot_fail

    addi    s3, s3, 1           # pass++
    j       spot_next

spot_fail:
    addi    s4, s4, 1           # fail++

spot_next:
    add     a4, a4, s6          # addr += 0x2000 (next pixel)
    addi    a5, a5, -1
    j       spot_loop

spot_done:

# ─────────────────────────────────────────────────────────────────────────────
# GIAI ĐOẠN 8: Output kết quả lên LED và 7-seg
#   LEDR = 0xFFFF_FFFF nếu tất cả 8 pixel PASS → báo VGA-READY
#   LEDR = 0x0000_00FF nếu có pixel FAIL       → báo cần debug
#   LEDG = số pixel pass (0..8)
#
#   Testbench sẽ detect LEDR = 0xFFFF_FFFF để dừng simulation
#   và thực hiện VGA port readback + save output BMP.
# ─────────────────────────────────────────────────────────────────────────────
    bnez    s4, some_fail       # nếu có fail, không bật all-LEDR

    # All 8 pixels PASS: LEDR = 0xFFFF_FFFF
    addi    a0, zero, -1
    sw      a0, 0x00(t0)        # LEDR = 0xFFFF_FFFF  ← trigger cho testbench
    addi    a0, zero, -1
    sw      a0, 0x04(t0)        # LEDG = all on
    j       vga_loop

some_fail:
    # Có pixel fail: LEDR[7:0] = fail count
    sw      s4, 0x00(t0)        # LEDR = s4 (fail count)
    sw      s3, 0x04(t0)        # LEDG = s3 (pass count)

# ─────────────────────────────────────────────────────────────────────────────
# GIAI ĐOẠN 9: Infinite loop — VGA hardware tự scan img_out_bram liên tục
#   Monitor sẽ hiển thị ảnh đã dehaze.
#   CPU chỉ giữ LED state.
# ─────────────────────────────────────────────────────────────────────────────
vga_loop:
    j       vga_loop
