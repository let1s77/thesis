# IPU Control Logic Workflow

## 1. Mục đích

Khối `ipu_control_logic` là FSM điều phối pipeline IPU theo hướng stage-based.

FSM hiện tại đi theo flow:

```text
IDLE -> LOAD -> DARK -> SKY -> TRANS -> ADC -> RECOVERY -> DONE
```

Ý tưởng của khối này là:

- `ipu_top` lo phần integration hệ thống, BRAM global, register block
- `haze_removal_top` lo datapath thuật toán
- `ipu_control_logic` lo enable từng stage và quyết định khi nào chuyển phase

Khối này đang bám đúng tinh thần file Excel: mỗi state tương ứng một phase xử lý rõ ràng, không coi toàn bộ datapath là một black-box duy nhất nữa.

---

## 2. Module Summary

**File RTL:** `00_src/IPU/ipu_control_logic.sv`

**Module name:** `ipu_control_logic`

**Parameters:**

- `IMG_WIDTH`  = 128
- `IMG_HEIGHT` = 128

Lưu ý: trong version hiện tại, 2 parameter này mới mang tính cấu hình tổng quát; FSM chủ yếu chuyển state dựa trên các tín hiệu `*_done` từ datapath.

---

## 3. Input Signals

### Global control

| Signal | Width | Ý nghĩa |
|--------|-------|---------|
| `clk` | 1 | Clock hệ thống |
| `rst_n` | 1 | Reset active-low |
| `ipu_en` | 1 | Enable toàn bộ IPU |
| `ipu_start` | 1 | Lệnh start từ register/control path |
| `cont_mode` | 1 | Cho phép chạy lặp frame liên tiếp sau state `DONE` |

### Reader / Writer status

| Signal | Width | Ý nghĩa |
|--------|-------|---------|
| `reader_busy` | 1 | Reader đang hoạt động |
| `reader_done` | 1 | Reader hoàn tất đọc 1 frame |
| `writer_busy` | 1 | Writer đang hoạt động |
| `writer_done` | 1 | Writer hoàn tất ghi 1 frame |

Ghi chú: trong bản FSM hiện tại, `writer_done` có dùng trực tiếp ở state `RECOVERY`; `reader_busy`, `reader_done`, `writer_busy` hiện là tín hiệu trạng thái dự phòng/để mở rộng thêm về sau.

### Datapath done pulses

| Signal | Width | Ý nghĩa |
|--------|-------|---------|
| `dark_done` | 1 | Phase DARK hoàn tất |
| `sky_done` | 1 | Phase SKY hoàn tất |
| `trans_done` | 1 | Phase coarse transmission hoàn tất |
| `adc_done` | 1 | Phase ADC estimation hoàn tất |
| `recovery_done` | 1 | Phase recovery hoàn tất |

Đây là nhóm tín hiệu quan trọng nhất để FSM chuyển state đúng kiến trúc Excel.

---

## 4. Output Signals

### Start control cho global BRAM path

| Signal | Width | Ý nghĩa |
|--------|-------|---------|
| `reader_start` | 1 | Pulse start cho `ipu_bram_reader` |
| `writer_start` | 1 | Pulse start cho `ipu_bram_writer` |

### Enable cho từng stage của datapath

| Signal | Width | Ý nghĩa |
|--------|-------|---------|
| `dark_enable` | 1 | Enable phase DARK / atmospheric light scan |
| `sky_enable` | 1 | Enable phase SKY recognition |
| `trans_enable` | 1 | Enable phase coarse transmission estimation |
| `adc_enable` | 1 | Enable phase ADC estimation |
| `recovery_enable` | 1 | Enable phase final recovery / t_compute_fuse |

### Bank control

| Signal | Width | Ý nghĩa |
|--------|-------|---------|
| `bank_swap` | 1 | Swap bank đọc/ghi của tx ping-pong memory |
| `bank_wr_clear` | 1 | Clear write side của bank trước khi ghi frame mới |
| `bank_rd_clear` | 1 | Reset read pointer/address của bank |
| `bank_rd_en` | 1 | Enable read từ bank để feed sang `adc_estimation` |

### Status outputs

| Signal | Width | Ý nghĩa |
|--------|-------|---------|
| `idle` | 1 | FSM đang ở `IDLE` |
| `busy` | 1 | FSM đang xử lý một frame |
| `done` | 1 | FSM đã hoàn tất flow của frame hiện tại |
| `error` | 1 | Cờ lỗi logic/state bất thường |
| `fsm_state` | 4 | Giá trị state hiện tại của FSM |

---

## 5. State Encoding

| State | Mã | Vai trò |
|------|----|---------|
| `S_IDLE` | `4'd0` | Chờ `ipu_en` và `ipu_start` |
| `S_LOAD` | `4'd1` | Clear/reset bank trước khi vào pipeline |
| `S_DARK` | `4'd2` | Chạy phase dark channel + atmospheric light |
| `S_SKY` | `4'd3` | Chạy phase sky recognition |
| `S_TRANS` | `4'd4` | Chạy phase coarse transmission map |
| `S_ADC` | `4'd5` | Chạy phase adaptive dark channel estimation |
| `S_RECOVERY` | `4'd6` | Chạy phase final t_compute/fusing + writer |
| `S_DONE` | `4'd7` | Kết thúc frame hiện tại |

---

## 6. Workflow Chi Tiết

### State `IDLE`

Điều kiện vào:

- Sau reset
- Sau khi xong một frame và `cont_mode = 0`

Hoạt động:

- `idle = 1`
- Tất cả các `*_enable = 0`
- Không start reader/writer

Điều kiện chuyển state:

- Nếu `ipu_en && ipu_start` -> sang `LOAD`

---

### State `LOAD`

Mục tiêu:

- Chuẩn bị bank trước khi pipeline bắt đầu

Output chính:

- `busy = 1`
- `bank_wr_clear = 1`
- `bank_rd_clear = 1`

Điều kiện chuyển state:

- Tự động sang `DARK`

---

### State `DARK`

Mục tiêu:

- Chạy nhánh dark channel + atmospheric light estimation trên source frame

Output chính:

- `busy = 1`
- `dark_enable = 1`
- `reader_start = enter_dark`

Ghi chú:

- `reader_start` chỉ pulse ở lúc vừa bước vào state `DARK`
- Source frame được scan để tạo dark channel và tính atmospheric light

Điều kiện chuyển state:

- Nếu `dark_done = 1` -> sang `SKY`

---

### State `SKY`

Mục tiêu:

- Chạy nhận diện sky region

Output chính:

- `busy = 1`
- `sky_enable = 1`

Điều kiện chuyển state:

- Nếu `sky_done = 1` -> sang `TRANS`

---

### State `TRANS`

Mục tiêu:

- Tính coarse transmission map và ghi vào tx bank

Output chính:

- `busy = 1`
- `trans_enable = 1`
- `reader_start = enter_trans`
- `bank_wr_clear = enter_trans`

Ghi chú:

- Khi mới vào `TRANS`, bank write side được clear để bắt đầu ghi transmission map mới
- Reader được start lại để scan source frame cho pass coarse transmission

Điều kiện chuyển state:

- Nếu `trans_done = 1` -> sang `ADC`

---

### State `ADC`

Mục tiêu:

- Đọc coarse transmission từ bank và chạy `adc_estimation`

Output chính:

- `busy = 1`
- `adc_enable = 1`
- `bank_swap = enter_adc`
- `bank_rd_clear = enter_adc`
- `bank_rd_en = 1`

Ghi chú:

- `bank_swap` chỉ pulse lúc vừa bước vào state `ADC`
- Sau đó `bank_rd_en` giữ mức 1 để cho phép đọc transmission bank feed vào ADC

Điều kiện chuyển state:

- Nếu `adc_done = 1` -> sang `RECOVERY`

---

### State `RECOVERY`

Mục tiêu:

- Chạy final recovery (`t_compute_fuse`) và ghi kết quả ra output BRAM

Output chính:

- `busy = 1`
- `recovery_enable = 1`
- `reader_start = enter_recovery`
- `writer_start = enter_recovery`

Ghi chú:

- Reader được start lại để lấy source RGB cho recovery phase
- Writer được start đồng thời để ghi output image ra global output BRAM

Điều kiện chuyển state:

- Nếu `recovery_done && writer_done` -> sang `DONE`

---

### State `DONE`

Mục tiêu:

- Phát cờ hoàn thành frame

Output chính:

- `done = 1`

Điều kiện chuyển state:

- Nếu `cont_mode && ipu_en` -> quay lại `LOAD`
- Ngược lại -> về `IDLE`

---

## 7. State Transition Diagram

```text
IDLE
  |
  | ipu_en && ipu_start
  v
LOAD
  |
  v
DARK --dark_done--> SKY --sky_done--> TRANS --trans_done--> ADC --adc_done--> RECOVERY --(recovery_done && writer_done)--> DONE
                                                                                                                             |
                                                                                                                             |
                                                                                                          cont_mode && ipu_en |
                                                                                                                             v
                                                                                                                            LOAD

DONE --else--> IDLE
```

---

## 8. Signal Behavior Theo State

| State | reader_start | writer_start | dark_enable | sky_enable | trans_enable | adc_enable | recovery_enable | bank_swap | bank_wr_clear | bank_rd_clear | bank_rd_en |
|------|--------------|--------------|-------------|------------|--------------|------------|-----------------|-----------|---------------|---------------|------------|
| `IDLE` | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| `LOAD` | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 1 | 0 |
| `DARK` | pulse at entry | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| `SKY` | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| `TRANS` | pulse at entry | 0 | 0 | 0 | 1 | 0 | 0 | 0 | pulse at entry | 0 | 0 |
| `ADC` | 0 | 0 | 0 | 0 | 0 | 1 | 0 | pulse at entry | 0 | pulse at entry | 1 |
| `RECOVERY` | pulse at entry | pulse at entry | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 0 |
| `DONE` | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |

---

## 9. Mối Quan Hệ Với Datapath Hierarchy

Hierarchy mục tiêu:

```text
ipu_top
├─ global BRAM / reader / writer
├─ ipu_control_logic
└─ haze_removal_top
   ├─ atm_light_coarse_tx
   ├─ adc_estimation
   └─ t_compute_fuse
```

Trong đó:

- `DARK`, `SKY`, `TRANS` chủ yếu điều khiển `atm_light_coarse_tx`
- `ADC` điều khiển `adc_estimation`
- `RECOVERY` điều khiển `t_compute_fuse` + writer

---

## 10. Ghi Chú Quan Trọng

1. FSM này phụ thuộc vào các pulse `dark_done/sky_done/trans_done/adc_done/recovery_done` từ datapath wrapper. Nếu các pulse này không sạch hoặc không đúng 1 frame, FSM sẽ chuyển phase sai.
2. `writer_done` là điều kiện bắt buộc để thoát `RECOVERY`, nên writer phải được start đúng lúc và phát done đúng frame.
3. `reader_busy`, `reader_done`, `writer_busy` hiện chưa được dùng để chặn state transition; nếu muốn FSM robust hơn nữa, có thể bổ sung guard logic ở các state `DARK`, `TRANS`, `RECOVERY`.
4. `error` hiện chỉ bật nếu rơi vào nhánh `default` của FSM combinational decode; đây mới là mức bảo vệ cơ bản.

---

## 11. Kết Luận

`ipu_control_logic` hiện tại đã đúng theo hướng kiến trúc stage-based của file Excel:

- Có state rõ ràng cho từng phase
- Có control signal riêng cho từng stage
- Có bank control rõ ràng cho phase transmission/ADC
- Có tách riêng start reader/writer ở các phase cần dùng source frame hoặc ghi output

Điểm cốt lõi để hệ thống chạy ổn định trong thực tế là đảm bảo wrapper datapath phát đúng các tín hiệu:

- `dark_done`
- `sky_done`
- `trans_done`
- `adc_done`
- `recovery_done`

Nếu nhóm tín hiệu này ổn, FSM này sẽ chạy đúng flow mong muốn.