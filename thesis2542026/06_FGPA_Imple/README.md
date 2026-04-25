# DE10-Standard Wrapper Guide

Tài liệu này mô tả file [wrapper.sv](wrapper.sv) dùng cho board DE10-Standard và cách các nút, switch, LED, HEX, LCD được ánh xạ vào hệ thống `soc_top`.

## 1. Vai trò của wrapper

`wrapper.sv` là top-level cho Quartus khi synthesis lên FPGA DE10-Standard. Nhiệm vụ của nó là:

- Nhận clock 50 MHz từ board tại `CLOCK_50`.
- Nhận reset từ nút `KEY[0]`.
- Đưa `SW[17:0]` vào bus input của SoC.
- Xuất các tín hiệu quan sát ra `LEDR`, `LEDG`, `HEX0` đến `HEX7`, và LCD.
- Instantiate trực tiếp `soc_top` để chạy toàn bộ hệ thống RISC-V + IPU + APB4.

Wrapper không tự xử lý thuật toán IPU. Tất cả logic xử lý nằm trong `soc_top` và các module con của nó.

## 2. Luồng kết nối chính

Luồng top-level hiện tại là:

`CLOCK_50`, `SW`, `KEY` -> `wrapper` -> `soc_top` -> `single_cycle`, `peri_apb_wrapper`, `ipu_apb_wrapper`, `ipu_core`, các BRAM chia sẻ.

Trong thiết kế hiện tại:

- `wrapper` chỉ làm nhiệm vụ ghép chân board với SoC.
- `soc_top` là nơi nối bus APB4, RISC-V, IPU và bộ nhớ đệm ảnh.
- `ipu_core` là khối xử lý ảnh chính.

## 3. Các nút bấm và switch

### `KEY[0]` - Reset

Đây là nút reset chính của hệ thống.

- Tín hiệu reset trên DE10-Standard là active-low.
- Khi nhấn `KEY[0]`, hệ thống bị reset.
- Wrapper hiện dùng cơ chế đồng bộ hóa reset kiểu `async assert, sync release` để tránh lỗi metastability.

### `KEY[1]`, `KEY[2]`, `KEY[3]`

Trong wrapper hiện tại, ba nút này chưa được nối vào chức năng riêng.

- Chúng có thể được dùng sau này cho debug hoặc mở rộng điều khiển.
- Ở phiên bản hiện tại, chúng không ảnh hưởng trực tiếp tới `soc_top`.

### `SW[17:0]` - Input tổng quát cho SoC

18 switch được đưa vào bus 32-bit `i_io_sw` của `soc_top`.

- `SW[17:0]` được zero-extend thành 32-bit.
- SoC bên trong có thể đọc các switch này qua module `single_cycle` hoặc peripheral logic.
- Tùy chương trình RISC-V và map peripheral, switch có thể được dùng làm input điều khiển thử nghiệm, chọn chế độ, hoặc các giá trị debug.

Nói ngắn gọn: wrapper không gán ý nghĩa cứng cho từng switch, mà chỉ đưa toàn bộ sang SoC để phần mềm/logic bên trong dùng.

## 4. Các đầu ra quan sát

### `LEDR[17:0]`

Đây là dải LED đỏ để hiển thị trạng thái debug hoặc dữ liệu từ SoC.

- Được lấy từ `o_io_ledr[17:0]`.
- Có thể dùng để hiện trạng thái pipeline, cờ hoàn thành, lỗi, hoặc dữ liệu kiểm tra.

### `LEDG[8:0]`

Đây là dải LED xanh.

- Được lấy từ `o_io_ledg[8:0]`.
- Thường dùng để báo trạng thái hoạt động tốt, done, hoặc tín hiệu điều khiển ngắn.

### `HEX0` đến `HEX7`

8 LED 7 đoạn dùng để hiển thị giá trị số hoặc mã trạng thái.

- `HEX0` đến `HEX7` lấy trực tiếp từ `soc_top`.
- Có thể dùng để hiển thị PC debug, mã lỗi, trạng thái FSM, hoặc dữ liệu test.

### LCD

Wrapper xuất các tín hiệu sau ra LCD:

- `LCD_DATA[7:0]`
- `LCD_RW`
- `LCD_EN`
- `LCD_RS`
- `LCD_ON`
- `LCD_BLON`

Trong thiết kế hiện tại:

- `LCD_ON` luôn được giữ ở mức `1`.
- `LCD_BLON` luôn được giữ ở mức `1`.
- Điều này có nghĩa là LCD luôn bật nguồn và bật đèn nền.

## 5. Debug output

### `PC_debug`

Đây là output debug của SoC, thường dùng để quan sát chương trình RISC-V đang chạy.

- Kết nối từ `soc_top` ra ngoài wrapper.
- Hữu ích khi test boot, APB access, hoặc theo dõi luồng lệnh.

## 6. Các tín hiệu nội bộ không đưa ra chân board

`soc_top` còn có các output nội bộ khác như:

- `o_insn_vld`
- `o_ipu_irq`

Trong wrapper hiện tại, hai tín hiệu này chưa được nối ra pin board.

- `o_insn_vld` có thể dùng cho debug hoặc trigger logic sau này.
- `o_ipu_irq` báo IPU hoàn tất xử lý, nhưng hiện chỉ tồn tại bên trong SoC.

Nếu cần, có thể mở rộng wrapper sau này để đưa chúng ra LED hoặc chân debug riêng.

## 7. Cách dùng khi synthesis trên Quartus

Khi tạo top-level cho Quartus, hãy chọn:

- `wrapper.sv` làm top entity.
- Gán chân theo file pin assignment của DE10-Standard.
- Đảm bảo `CLOCK_50`, `KEY[0]`, `SW[17:0]`, `LEDR[17:0]`, `LEDG[8:0]`, `HEX0` đến `HEX7`, và LCD đúng chuẩn board.

## 8. Ý nghĩa thực tế khi test hệ thống

Trong quá trình chạy FPGA:

- Dùng `KEY[0]` để reset hệ thống.
- Dùng `SW[17:0]` để đưa dữ liệu thử nghiệm hoặc bit điều khiển vào SoC.
- Quan sát `HEX`, `LEDR`, `LEDG`, và LCD để biết trạng thái hệ thống.
- Quan sát `PC_debug` nếu cần theo dõi chương trình RISC-V.

## 9. Ghi chú quan trọng

- Wrapper không thay đổi thuật toán IPU.
- Wrapper chỉ là lớp ghép chân board với `soc_top`.
- Nếu muốn đổi hành vi nút bấm hoặc LED, cần chỉnh trong `soc_top` hoặc peripheral logic, không phải ở wrapper.
