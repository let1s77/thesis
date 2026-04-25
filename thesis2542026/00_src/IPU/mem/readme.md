IPU BRAM Deploy Package
=======================

Muc tieu
--------
Ban nay trien khai "Cach 1: 2 BRAM doc lap" cho IPU:

1. IMG_IN_BUF  -> BRAM input toan cuc
2. IMG_OUT_BUF -> BRAM output toan cuc

IPU doc tu IMG_IN_BUF, dua stream vao haze_removal_top,
sau do ghi ket qua vao IMG_OUT_BUF.

Thanh phan file
---------------
1. ipu_addr_map.vh
   - Dinh nghia base address va register offsets theo memory mapping

2. img_in_bram.v
   - BRAM input
   - Port A: system / CPU / testbench
   - Port B: IPU reader

3. img_out_bram.v
   - BRAM output
   - Port A: system / CPU / testbench
   - Port B: IPU writer

4. ipu_bram_reader.v
   - Doc du lieu pixel tu IMG_IN_BUF
   - Chuyen thanh stream:
     pre_frame_vsync, pre_frame_href, pre_frame_clken, pre_img[23:0]

5. ipu_bram_writer.v
   - Nhan stream output tu haze_removal_top
   - Ghi vao IMG_OUT_BUF

6. ipu_control_logic.v
   - FSM dieu khien start / run / done

7. ipu_top_bram.v
   - Wrapper top-level cho:
     + register block
     + input BRAM
     + output BRAM
     + reader
     + haze_removal_top
     + writer

Gia tri mac dinh
----------------
- IPU_SRC_ADDR   = 0x0001_0000
- IPU_DST_ADDR   = 0x0004_0000
- IPU_TMP_ADDR   = 0x0007_0000
- IPU_IMG_WIDTH  = 128
- IPU_IMG_HEIGHT = 128
- IPU_IMG_STRIDE = 512
- IPU_IMG_FORMAT = 1

Luu y quan trong
----------------
1. Moi pixel duoc luu trong 1 word 32-bit:
   {8'h00, R, G, B}

2. Vi vay stride nen chia het cho 4 bytes.
   Gia tri khuyen dung:
   - 128x128: stride = 512
   - 256x256: stride = 1024

3. IMG_BUF_DEPTH_WORD = 49152 words
   Tuong ung 192 KB / buffer

4. Ban nay la ban de verify nhanh IPU voi BRAM local trong ipu_top.
   Ve kien truc cuoi cung, BRAM co the duoc dua len SoC_Top.

Cach tich hop co ban
--------------------
- Nap anh input vao img_in_bram qua cong sys_*
- Ghi cac thanh ghi IPU:
  + IPU_SRC_ADDR
  + IPU_DST_ADDR
  + IPU_IMG_WIDTH
  + IPU_IMG_HEIGHT
  + IPU_IMG_STRIDE
  + IPU_CTRL (set EN, START)
- Cho IPU chay
- Poll IPU_STATUS hoac IPU_IRQ_STATUS
- Doc ket qua tu img_out_bram qua cong sys_*

Huong nang cap sau nay
----------------------
1. Dua BRAM ra SoC_Top
2. Thay interface sys_* bang AHB-Lite / APB / memory bus
3. Giu nguyen haze_removal_top la stream processing core
4. Local BRAM cho t-computing / fusing van de ben trong datapath