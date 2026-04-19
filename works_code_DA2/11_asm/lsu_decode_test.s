_start:
    #---------------------------------------------------------
    # LSU DECODE TEST
    # Mục tiêu: verify waveform thấy đúng signal assert
    # theo từng vùng địa chỉ
    #
    # Waveform cần quan sát:
    #   is_mem      → HIGH khi addr = 0x0000_xxxx
    #   is_img_in   → HIGH khi addr = 0x0001_xxxx
    #   is_img_out  → HIGH khi addr = 0x0004_xxxx
    #   is_img_tmp  → HIGH khi addr = 0x0007_xxxx
    #   is_peri     → HIGH khi addr = 0x1000_xxxx
    #   is_ipu      → HIGH khi addr = 0x1002_xxxx
    #
    #   PSEL/PENABLE/PWRITE → HIGH chỉ khi is_ipu = 1
    #   img_in_sys_en/we    → HIGH chỉ khi is_img_in = 1
    #   img_out_sys_en/we   → HIGH chỉ khi is_img_out = 1
    #   img_tmp_sys_en/we   → HIGH chỉ khi is_img_tmp = 1
    #---------------------------------------------------------
    lui     t0, 0x00000     # t0 = base local mem  = 0x0000_0000
    lui     t1, 0x00010     # t1 = IMG_IN_BASE     = 0x0001_0000
    lui     t2, 0x00040     # t2 = IMG_OUT_BASE    = 0x0004_0000
    lui     t3, 0x00070     # t3 = IMG_TMP_BASE    = 0x0007_0000
    lui     t4, 0x10000     # t4 = PERI_BASE       = 0x1000_0000
    lui     t5, 0x10020     # t5 = IPU_BASE        = 0x1002_0000

    li      s0, 0xDEAD      # pattern dễ nhận trên waveform
    li      s1, 0xBEEF      # pattern thứ 2
    li      s2, 0x1234      # pattern thứ 3

    #=========================================================
    # ZONE 1: LOCAL MEM — 0x0000_0000
    # Expect: is_mem=1, tất cả is_img_*/is_ipu = 0
    # PSEL=0, img_*_sys_en=0
    #=========================================================
    sw      s0, 0x00(t0)    # write → is_mem=1, is_mem_we=1
    lw      s3, 0x00(t0)    # read  → is_mem=1

    sw      s1, 0x04(t0)    # write địa chỉ khác trong cùng vùng
    lw      s3, 0x04(t0)    # read back

    #=========================================================
    # ZONE 2: IMG_IN_BUF — 0x0001_0000
    # Expect: is_img_in=1, img_in_sys_en=1
    #         sw → img_in_sys_we=1
    #         lw → img_in_sys_we=0
    #         PSEL=0
    #=========================================================
    sw      s0, 0x00(t1)    # write pixel[0] → img_in_sys_we=1
    sw      s1, 0x04(t1)    # write pixel[1]
    sw      s2, 0x08(t1)    # write pixel[2]
    lw      s3, 0x00(t1)    # read  pixel[0] → img_in_sys_we=0
    lw      s3, 0x04(t1)    # read  pixel[1]

    # Test địa chỉ cuối vùng IMG_IN (0x0003_FFFC)
    lui     t6, 0x00040
    addi    t6, t6, -4      # t6 = 0x0003_FFFC
    sw      s2, 0x00(t6)    # write cuối vùng → vẫn là img_in
    lw      s3, 0x00(t6)    # read cuối vùng

    #=========================================================
    # ZONE 3: IMG_OUT_BUF — 0x0004_0000
    # Expect: is_img_out=1, img_out_sys_en=1
    #         PSEL=0, img_in_sys_en=0
    #=========================================================
    sw      s0, 0x00(t2)    # write → img_out_sys_we=1
    sw      s1, 0x04(t2)
    lw      s3, 0x00(t2)    # read  → img_out_sys_we=0
    lw      s3, 0x04(t2)

    #=========================================================
    # ZONE 4: IMG_TMP_BUF — 0x0007_0000
    # Expect: is_img_tmp=1, img_tmp_sys_en=1
    #         PSEL=0
    #=========================================================
    sw      s0, 0x00(t3)    # write → img_tmp_sys_we=1
    sw      s1, 0x04(t3)
    lw      s3, 0x00(t3)    # read  → img_tmp_sys_we=0

    #=========================================================
    # ZONE 5: PERIPHERAL — 0x1000_0000
    # Expect: is_peri=1, PSEL=0, img_*_sys_en=0
    #=========================================================
    sw      s0, 0x00(t4)    # write LED_RED → is_peri=1, we=1
    lw      s3, 0x30(t4)    # read SWITCH   → is_peri=1, we=0

    #=========================================================
    # ZONE 6: IPU REGISTERS — 0x1002_0000
    # Expect: is_ipu=1
    #         PSEL=1, PENABLE=1
    #         sw → PWRITE=1, PADDR=addr, PWDATA=data
    #         lw → PWRITE=0, PRDATA forwarded
    #         img_*_sys_en=0
    #=========================================================

    # Đọc IPU_ID trước (safe read, không side effect)
    lw      s3, 0x3C(t5)    # PSEL=1 PENABLE=1 PWRITE=0 PADDR=0x1002003C

    # Ghi IPU_SRC_ADDR
    lui     s0, 0x10        # s0 = 0x0001_0000
    sw      s0, 0x08(t5)    # PSEL=1 PENABLE=1 PWRITE=1 PADDR=0x10020008

    # Readback IPU_SRC_ADDR
    lw      s3, 0x08(t5)    # PSEL=1 PENABLE=1 PWRITE=0

    # Ghi IPU_DST_ADDR
    lui     s0, 0x40        # s0 = 0x0004_0000
    sw      s0, 0x0C(t5)    # PWRITE=1 PADDR=0x1002000C

    # Ghi IPU_IMG_WIDTH = 128
    li      s0, 128
    sw      s0, 0x14(t5)    # PWRITE=1 PWDATA=128

    # Ghi IPU_IMG_HEIGHT = 128
    li      s0, 128
    sw      s0, 0x18(t5)    # PWRITE=1 PWDATA=128

    # Ghi IPU_IMG_STRIDE = 512
    li      s0, 512
    sw      s0, 0x1C(t5)    # PWRITE=1 PWDATA=512

    # Đọc IPU_STATUS
    lw      s3, 0x04(t5)    # PWRITE=0 — quan sát PRDATA

    #=========================================================
    # ZONE 7: Boundary test — địa chỉ ngay TRÊN vùng IPU
    # 0x1002_1000 — nằm ngoài IPU range
    # Expect: is_ipu=0, PSEL=0 → không có giao dịch APB
    #=========================================================
    lui     t6, 0x10021     # t6 = 0x1002_1000
    lw      s3, 0x00(t6)    # PSEL phải = 0 ở đây

    #=========================================================
    # ZONE 8: Boundary test — địa chỉ giữa IMG_IN và IMG_OUT
    # 0x0003_FFFC (cuối IMG_IN) vs 0x0004_0000 (đầu IMG_OUT)
    # Verify không bị overlap
    #=========================================================
    lui     t6, 0x00040
    addi    t6, t6, -4      # t6 = 0x0003_FFFC — vẫn trong IMG_IN
    sw      s2, 0x00(t6)    # img_in_sys_we=1, img_out_sys_we=0

    lui     t6, 0x00040     # t6 = 0x0004_0000 — đầu IMG_OUT
    sw      s2, 0x00(t6)    # img_out_sys_we=1, img_in_sys_we=0

    #=========================================================
    # DONE — ghi LED để biết test chạy xong
    #=========================================================
    lui     t4, 0x10000     # t4 = PERI_BASE
    li      s0, 0xFF
    sw      s0, 0x04(t4)    # LED_GREEN = 0xFF → test done

done:
    j       done
