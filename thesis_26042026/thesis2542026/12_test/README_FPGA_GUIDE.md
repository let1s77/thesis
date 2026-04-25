# FPGA Demo Guide — Haze Removal SoC (DE10-Standard)

Tài liệu hướng dẫn sử dụng board DE10-Standard để chạy demo pipeline:
**CPU (RISC-V) → APB → IPU (Dark-Channel Dehaze) → img_out_bram → VGA**

---

## 1. Nút nhấn (KEY)

| Nút | Chức năng |
|-----|-----------|
| **KEY[0]** | **Reset toàn bộ SoC** (active-low, nhấn giữ = reset, thả = chạy lại từ đầu) |
| KEY[1] | Không dùng trong firmware hiện tại |
| KEY[2] | Không dùng trong firmware hiện tại |
| KEY[3] | Không dùng trong firmware hiện tại |

> Khi cấp nguồn hoặc vừa program FPGA xong, nhấn **KEY[0]** một lần để khởi động firmware.

---

## 2. Công tắc (SW)

| Switch | Chức năng |
|--------|-----------|
| SW[9:0] | Đọc được bởi CPU tại địa chỉ `0x1000_0030` |
| | Firmware hiện tại (`vga_dehaze_fulltest.s`) **không dùng** switch |
| | Có thể dùng cho firmware tương lai (ví dụ: chọn ảnh, chế độ debug) |

---

## 3. LED Đỏ (LEDR) — Trạng thái chính

> **Chỉ LEDR[9:0] có trên DE10-Standard** (10 LED vật lý). CPU ghi 32-bit nhưng chỉ 10 bit thấp nhất hiển thị.

| Giá trị LEDR | Ý nghĩa |
|-------------|---------|
| `0000000000` (tắt) | Đang khởi động (Stage 0) |
| `0000000001` (bit0) | **LỖI: IPU ID không khớp** — ID register trả về sai, kiểm tra kết nối APB |
| `0000000011` (bit1:0) | **LỖI: Cấu hình IPU thất bại** — readback verify sai |
| `0000000111` (bit2:0) | **LỖI: IPU timeout** — IPU không báo done sau 2 triệu cycles (~40ms @ 50MHz) |
| `0000001xxx` | Số pixel spot-check bị lỗi (1–7) — IPU chạy xong nhưng output bất thường |
| `1111111111` (tất cả sáng) | ✅ **THÀNH CÔNG** — IPU done, 8/8 pixel spot-check qua, VGA đang stream ảnh |

---

## 4. LED Xanh (LEDG) — Tiến trình boot

> ⚠️ **DE10-Standard KHÔNG có LEDG vật lý.** Các tín hiệu này không thể quan sát trực tiếp trên board.
> Dùng **SignalTap** hoặc **testbench** để đọc nếu cần debug tiến trình.

| Giá trị LEDG (logic) | Ý nghĩa |
|----------------------|---------|
| `00000001` | Stage 0: Firmware đang boot |
| `00000011` | Stage 1: IPU ID = `0x49505531` ✓ |
| `00000111` | Stage 2: IPU STATUS = IDLE ✓ |
| `00001111` | Stage 3: Tất cả IPU registers đã config và verify ✓ |
| `00011111` | Stage 4: IPU đã được trigger, đang xử lý ảnh |
| `1111111111` (all) | Stage 8: Tất cả spot-check PASS |
| `0000 0xxx` | Stage 8 fail: số lượng pixel PASS (0–7) |

---

## 5. Màn hình 7-Segment (HEX)

**Cách hoạt động:** CPU ghi 32-bit vào địa chỉ `0x1000_0010` → hiển thị 8 chữ số hex trên HEX7..HEX0.
Mỗi nibble 4-bit của giá trị 32-bit → 1 ký tự hex (0–F).

| Địa chỉ | Điều khiển |
|---------|-----------|
| `0x1000_0010` | HEX3, HEX2, HEX1, HEX0 (nibble [15:0] của giá trị ghi) |
| `0x1000_0014` | HEX7, HEX6, HEX5, HEX4 (nibble [31:16] của giá trị ghi) |

**Ví dụ:** `sw reg, 0x1000_0010` với `reg = 0x0000_ABCD`:
```
HEX3 = A,  HEX2 = B,  HEX1 = C,  HEX0 = D
```

> **Firmware `vga_dehaze_fulltest.s` hiện tại KHÔNG ghi HEX.** Tất cả 6 màn hình giữ nguyên giá trị cũ sau reset.
> Nếu muốn hiển thị PC debug hoặc fail count lên HEX, cần thêm lệnh `sw` trong ASM.

---

## 6. Đầu ra VGA

| Thông số | Giá trị |
|---------|---------|
| Chuẩn | VGA 640×480 @ 60 Hz |
| Pixel clock | 25 MHz (PLL từ CLOCK_50 ÷ 2) |
| Connector | DB-15 (J9 trên board) |
| DAC | ADV7123, 8-bit mỗi kênh R/G/B |
| Ảnh hiển thị | 128×128 pixel, **căn giữa màn hình** |
| Vị trí ảnh | X: pixel 256–383, Y: pixel 176–303 (trong vùng active 640×480) |
| Viền | Màu đen (blank) |

**Ảnh hiển thị trên VGA là:** ảnh **ĐÃ DEHAZE** từ `img_out_bram`.
VGA hardware tự động quét bộ nhớ liên tục — CPU chỉ cần ở vòng lặp vô tận sau khi IPU done.

---

## 7. Ảnh lưu ở đâu?

### Ảnh đầu vào (Input Image)
```
Bộ nhớ FPGA:  IMG_IN_BUF  @ 0x0001_0000  (64 KB, 16384 words × 32-bit)
```
- Được **nạp sẵn lúc synthesis** qua `$readmemh` — không thể thay đổi lúc runtime
- Định dạng mỗi word: `{pad[31:24], B[23:16], G[15:8], R[7:0]}`
- **File hex nguồn:** `06_FGPA_Imple/script/gen_image_hex.py` → convert từ BMP/PNG

### Ảnh đầu ra (Output Image)
```
Bộ nhớ FPGA:  IMG_OUT_BUF @ 0x0004_0000  (64 KB, 16384 words × 32-bit)
```
- Được **IPU ghi** sau khi xử lý xong
- VGA controller đọc từ đây để hiển thị lên màn hình
- Không tự lưu ra file — cần SignalTap hoặc testbench để capture

### Bộ nhớ tạm (Temp Buffer)
```
Bộ nhớ FPGA:  IMG_TMP_BUF @ 0x0007_0000  (64 KB)
```
- IPU dùng nội bộ trong quá trình tính toán (dark channel, transmission map...)
- Không cần quan tâm khi sử dụng bình thường

---

## 8. Quy trình nạp ảnh mới lên FPGA

```
Bước 1: Chuẩn bị ảnh BMP (128×128 pixel, 24-bit color RGB)
         Đặt vào: 06_FGPA_Imple/images/<tên_ảnh>.bmp

         ✔ Đã có sẵn:  06_FGPA_Imple/images/soc_input_128.bmp
                        (128×128 px, RGB, 49206 bytes — ảnh cityscape có sương)
         Nguồn gốc:    01_sim/soc/Testbench_SOC/sim/image_test/soc_input_128.bmp

Bước 2: Convert BMP → hex (định dạng $readmemh, 32-bit/pixel = {pad,B,G,R})
         python 06_FGPA_Imple/script/gen_image_hex.py \
                06_FGPA_Imple/images/soc_input_128.bmp \
                -o 06_FGPA_Imple/images/soc_input_128.hex

Bước 3: Cập nhật INIT_FILE trong img_in_bram
         Sửa parameter INIT_FILE trong file BRAM của img_in_bram
         trỏ tới <tên_ảnh>.hex

Bước 4: Re-synthesize Quartus
         Mở 06_FGPA_Imple/thesis/thesis_v1.qpf
         Processing → Start Compilation (Ctrl+L)

Bước 5: Program FPGA
         Tools → Programmer → Program (hoặc dùng .sof file)

Bước 6: Nhấn KEY[0] để reset và chạy firmware
         Quan sát LEDR → chờ tất cả LEDR sáng = VGA ready
```

---

## 9. Debug — Đọc Program Counter

| Signal | Mô tả |
|--------|-------|
| `PC_debug[31:0]` | PC hiện tại của RISC-V CPU |

Cách xem: dùng **Quartus SignalTap II**:
1. Thêm node `wrapper:wrapper_inst|PC_debug[31:0]` vào SignalTap
2. Trigger khi `LEDR[0]` thay đổi
3. Chạy và quan sát PC để xác định CPU đang chạy đến đâu

---

## 10. Các lỗi thường gặp

| Triệu chứng | Nguyên nhân có thể | Cách xử lý |
|-------------|-------------------|-----------|
| LEDR không sáng gì | Firmware không chạy | Nhấn KEY[0] để reset |
| LEDR[0] = 1, bị kẹt | IPU ID sai | Kiểm tra kết nối APB, rebuild project |
| LEDR[1:0] = 11, bị kẹt | Config IPU sai | Kiểm tra BRAM init, địa chỉ |
| LEDR[2:0] = 111, timeout | IPU không phản hồi | Kiểm tra IPU source files, rebuild |
| Màn hình đen hoàn toàn | VGA clock sai / ảnh all-zero | Kiểm tra PLL lock, ảnh input |
| Màn hình có hình nhưng sai màu | Thứ tự R/G/B ngược | Kiểm tra `vga_rd_data` mapping trong `wrapper.sv` |
| LEDR sáng hết nhưng màn hình đen | BRAM output lệch 1 cycle | Thêm register stage cho `vga_rd_addr` |

---

## 11. Memory Map tóm tắt

```
0x0000_0000  BOOT_MEM      (64 KB) — Instruction + Data memory (RISC-V)
0x0001_0000  IMG_IN_BUF    (64 KB) — Ảnh input (pre-loaded lúc synthesis)
0x0004_0000  IMG_OUT_BUF   (64 KB) — Ảnh output sau dehaze (VGA đọc từ đây)
0x0007_0000  IMG_TMP_BUF   (64 KB) — Scratch buffer của IPU

0x1000_0000  LEDR          — Ghi: điều khiển LED đỏ | Đọc: giá trị hiện tại
0x1000_0004  LEDG          — Ghi: điều khiển LED xanh (không có trên DE10-Std)
0x1000_0010  HEX0~HEX3     — Ghi 32-bit → hiển thị hex [15:0] lên HEX3..HEX0
0x1000_0014  HEX4~HEX7     — Ghi 32-bit → hiển thị hex [31:16] lên HEX7..HEX4
0x1000_0020  LCD            — Không dùng trên DE10-Standard
0x1000_0030  SWITCH (read) — Đọc: giá trị SW[9:0]
0x1000_0034  KEY (read)    — Đọc: giá trị SW[9:0] (dùng chung với SWITCH)

0x1002_0000  IPU_BASE
  +0x00  CTRL        [EN=bit0, START=bit1, SOFT_RST=bit2]
  +0x04  STATUS      [IDLE=bit0, BUSY=bit1, DONE=bit2]
  +0x08  SRC_ADDR    = 0x0001_0000
  +0x0C  DST_ADDR    = 0x0004_0000
  +0x10  TMP_ADDR    = 0x0007_0000
  +0x14  IMG_WIDTH   = 128
  +0x18  IMG_HEIGHT  = 128
  +0x1C  IMG_STRIDE  = 512 (= 128 × 4 bytes/pixel)
  +0x30  IRQ_EN      [bit0 = enable DONE IRQ]
  +0x34  IRQ_STATUS  [bit0 = DONE flag, W1C]
  +0x3C  ID          = 0x49505531 ("IPU1")
```
