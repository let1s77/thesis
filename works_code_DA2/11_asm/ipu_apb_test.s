_start:
    #---------------------------------
    # Khởi tạo địa chỉ base
    #---------------------------------
    lui     t0, 0x10020         # t0 = IPU_BASE = 0x1002_0000
    lui     t1, 0x10000         # t1 = PERI_BASE = 0x1000_0000

    li      s0, 0               # s0 = fail counter (0 = all pass)

    #=================================================================
    # STEP 1: Đọc IPU_ID — verify APB read hoạt động
    # Expected = 0x49505531 ("IPU1")
    #=================================================================
    lw      a0, 0x3C(t0)        # a0 = IPU_ID

    lui     a1, 0x49505         # a1[31:12] = 0x49505
    addi    a1, a1, 0x531       # a1 = 0x49505531

    bne     a0, a1, fail_step1
    j       pass_step1
fail_step1:
    addi    s0, s0, 1
pass_step1:

    #=================================================================
    # STEP 2: Kiểm tra IPU_STATUS ban đầu = IDLE (bit0 = 1)
    #=================================================================
    lw      a0, 0x04(t0)        # a0 = IPU_STATUS
    andi    a0, a0, 0x1         # mask bit0 = IDLE

    li      a1, 1               # expected IDLE = 1
    bne     a0, a1, fail_step2
    j       pass_step2
fail_step2:
    addi    s0, s0, 1
pass_step2:

    #=================================================================
    # STEP 3: Ghi + readback IPU_SRC_ADDR = 0x0001_0000
    #=================================================================
    lui     a0, 0x10            # a0 = 0x0001_0000
    sw      a0, 0x08(t0)        # ghi IPU_SRC_ADDR

    lw      a1, 0x08(t0)        # readback
    bne     a0, a1, fail_step3
    j       pass_step3
fail_step3:
    addi    s0, s0, 1
pass_step3:

    #=================================================================
    # STEP 4: Ghi + readback IPU_DST_ADDR = 0x0004_0000
    #=================================================================
    lui     a0, 0x40            # a0 = 0x0004_0000
    sw      a0, 0x0C(t0)        # ghi IPU_DST_ADDR

    lw      a1, 0x0C(t0)        # readback
    bne     a0, a1, fail_step4
    j       pass_step4
fail_step4:
    addi    s0, s0, 1
pass_step4:

    #=================================================================
    # STEP 5: Ghi + readback IPU_TMP_ADDR = 0x0007_0000
    #=================================================================
    lui     a0, 0x70            # a0 = 0x0007_0000
    sw      a0, 0x10(t0)        # ghi IPU_TMP_ADDR

    lw      a1, 0x10(t0)        # readback
    bne     a0, a1, fail_step5
    j       pass_step5
fail_step5:
    addi    s0, s0, 1
pass_step5:

    #=================================================================
    # STEP 6: Ghi + readback IPU_IMG_WIDTH = 128
    #=================================================================
    li      a0, 128
    sw      a0, 0x14(t0)        # ghi IPU_IMG_WIDTH

    lw      a1, 0x14(t0)        # readback
    bne     a0, a1, fail_step6
    j       pass_step6
fail_step6:
    addi    s0, s0, 1
pass_step6:

    #=================================================================
    # STEP 7: Ghi + readback IPU_IMG_HEIGHT = 128
    #=================================================================
    li      a0, 128
    sw      a0, 0x18(t0)        # ghi IPU_IMG_HEIGHT

    lw      a1, 0x18(t0)        # readback
    bne     a0, a1, fail_step7
    j       pass_step7
fail_step7:
    addi    s0, s0, 1
pass_step7:

    #=================================================================
    # STEP 8: Ghi + readback IPU_IMG_STRIDE = 512
    # stride = 128 pixels * 4 bytes/pixel = 512 bytes
    #=================================================================
    li      a0, 512
    sw      a0, 0x1C(t0)        # ghi IPU_IMG_STRIDE

    lw      a1, 0x1C(t0)        # readback
    bne     a0, a1, fail_step8
    j       pass_step8
fail_step8:
    addi    s0, s0, 1
pass_step8:

    #=================================================================
    # STEP 9: Ghi IPU_CTRL = 0x1 (EN=1, START=0)
    # Enable trước, chưa trigger
    #=================================================================
    li      a0, 1               # bit0 = EN
    sw      a0, 0x00(t0)        # ghi IPU_CTRL

    lw      a1, 0x00(t0)        # readback
    bne     a0, a1, fail_step9
    j       pass_step9
fail_step9:
    addi    s0, s0, 1
pass_step9:

    #=================================================================
    # STEP 10: Ghi IPU_CTRL = 0x3 (EN=1, START=1)
    # Trigger IPU bắt đầu xử lý
    #=================================================================
    li      a0, 3               # bit0=EN, bit1=START
    sw      a0, 0x00(t0)        # ghi IPU_CTRL

    # Verify STATUS → BUSY (bit1 = 1)
    lw      a1, 0x04(t0)        # đọc IPU_STATUS
    andi    a1, a1, 0x2         # mask bit1 = BUSY
    li      a2, 2
    bne     a1, a2, fail_step10
    j       pass_step10
fail_step10:
    addi    s0, s0, 1
pass_step10:

    #=================================================================
    # STEP 11: Poll IPU_STATUS[DONE] — chờ IPU hoàn thành
    # DONE = bit2
    #=================================================================
poll_done:
    lw      a1, 0x04(t0)        # đọc IPU_STATUS
    andi    a1, a1, 0x4         # mask bit2 = DONE
    beqz    a1, poll_done       # DONE=0 → tiếp tục chờ

    li      a2, 4               # expected = bit2 set
    bne     a1, a2, fail_step11
    j       pass_step11
fail_step11:
    addi    s0, s0, 1
pass_step11:

    #=================================================================
    # STEP 12: Clear START bit
    #=================================================================
    li      a0, 1               # EN=1, START=0
    sw      a0, 0x00(t0)        # ghi IPU_CTRL

    #=================================================================
    # Hiển thị kết quả ra HEX + LED
    # s0 = 0  → all pass → HEX = 0xA0, LED_GREEN = 1
    # s0 != 0 → có fail  → HEX = số step fail, LED_RED = s0
    #=================================================================
    bnez    s0, show_fail

show_pass:
    li      a0, 0xA0            # pattern "A0" trên HEX0~1
    sw      a0, 0x10(t1)        # ghi HEX display
    li      a0, 1
    sw      a0, 0x04(t1)        # LED_GREEN = 1
    j       done

show_fail:
    sw      s0, 0x10(t1)        # HEX = số test fail
    sw      s0, 0x00(t1)        # LED_RED = số test fail

done:
    #---------------------------------
    # Dừng — infinite loop
    #---------------------------------
    j       done
