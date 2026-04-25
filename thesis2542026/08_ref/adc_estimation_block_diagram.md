# ADC Estimation — Workflow & Block Diagram

## 1. Tổng quan (Overview)

Khối **`adc_estimation`** thực hiện thuật toán **Adaptive Dark Channel (ADC)** dựa trên phương pháp lọc min thích nghi sử dụng **Adaptive Structuring Element (ASE)** — tham khảo từ bài báo *"Efficient Dehazing Method"* (IEEE Access, 2019).

- **Mục đích:** Ước lượng Adaptive Dark Channel cho từng pixel, thay thế bộ lọc min cố định (fixed 5×5) bằng bộ lọc min thích nghi dựa trên cấu trúc cạnh (edge-aware) của ảnh.
- **Window size:** 5×5 (bán kính r = 2), cố định.
- **Hai luồng dữ liệu đầu vào:**
  - **Gray** (grayscale): Dùng làm "pilot" để tính ASE.
  - **MC** (Minimum Channel): Dùng làm data cho bộ lọc min thích nghi.

**Source files:**

| File | Vai trò |
|------|---------|
| `adc_estimation.sv` | Top wrapper, kết nối pipeline |
| `adc_line_buffer_5x5.sv` | Line buffer tạo cửa sổ 5×5 |
| `adc_pixel_distance.sv` | Tính khoảng cách pixel (edge-based) |
| `adc_path_length.sv` | Tính path length $d_\lambda$ |
| `adc_rlimit_compute.sv` | Tính ngưỡng $r\_limit$ (mean) |
| `adc_ase_masked_min.sv` | So sánh ASE mask + lọc min |

**Python reference:** `adc_estimation_top.py` → hàm `adc_estimation_top(gray5x5, mc5x5, lambd)`

---

## 2. Block Diagram (Text-based)

```
                    ┌─────────────────────────────────────────────────────────┐
                    │                   adc_estimation (TOP)                  │
                    │                                                         │
  i_gray_pix ──►   │  ┌──────────────────┐                                   │
  i_gray_valid ──►  │  │  Line Buffer 5×5 │──► gray_win[5×5] ──┐             │
                    │  │  (u_line_buf_gray)│     gray_win_valid  │             │
                    │  └──────────────────┘                      │             │
                    │                                            ▼             │
                    │                                ┌───────────────────┐     │
                    │                                │  Pixel Distance   │     │
                    │                                │  (u_pixel_dist)   │     │
                    │                                │  1 cycle latency  │     │
                    │                                └────────┬──────────┘     │
                    │                                         │ dp[5×5] (9b)  │
                    │                                         ▼               │
                    │                                ┌───────────────────┐     │
                    │                                │   Path Length     │     │
                    │                                │  (u_path_len)     │     │
                    │                                │  1 cycle latency  │     │
                    │                                └────────┬──────────┘     │
                    │                                         │ dl[5×5] (10b) │
                    │                                         ▼               │
                    │                                ┌───────────────────┐     │
                    │                                │  R-Limit Compute  │     │
                    │                                │  (u_rlimit)       │     │
                    │                                │  2 cycle latency  │     │
                    │                                └───┬─────────┬────┘     │
                    │                                    │         │          │
                    │                          rl_dl[5×5]│  rlimit │          │
                    │                            (10b)   │  (10b)  │          │
                    │                                    ▼         ▼          │
  i_mc_pix ──►     │  ┌──────────────────┐    ┌─────────────────────────┐    │
  i_mc_valid ──►    │  │  Line Buffer 5×5 │    │   ASE Masked Min       │    │
                    │  │  (u_line_buf_mc)  │    │   (u_masked_min)       │    │
                    │  └────────┬─────────┘    │   1 cycle latency      │    │
                    │           │               └───────────┬────────────┘    │
                    │           │ mc_win[5×5]               │                │
                    │           ▼                            │                │
                    │  ┌──────────────────┐                 │                │
                    │  │  MC Delay Chain   │──► mc_d4[5×5]──┘                │
                    │  │  4-stage pipeline │                                  │
                    │  └──────────────────┘              ▼                   │
                    │                              ┌──────────┐              │
                    │                              │ Out Count │              │
                    │                              │ + o_done  │              │
                    │                              └────┬─────┘              │
                    │                                   │                    │
                    └───────────────────────────────────┼────────────────────┘
                                                        ▼
                                              o_adc_pix [7:0]
                                              o_valid
                                              o_done
```

---

## 3. Chi tiết từng Stage

### Stage 0: Line Buffer 5×5 (`adc_line_buffer_5x5`)

**Số lượng:** 2 instance (1 cho Gray, 1 cho MC).

**Chức năng:** Nhận luồng pixel streaming (1 pixel/cycle), xây dựng cửa sổ trượt 5×5.

**Cấu trúc bên trong:**
- **4 line buffer** (RAM nhỏ): Lưu 4 hàng trước đó.
- **Cascade shift:** `buf0 ← buf1 ← buf2 ← buf3 ← i_pix`
- **5×5 shift register array:** Dịch ngang cho tất cả 5 hàng đồng thời.
- **Column counter:** Đếm vị trí trong hàng (0 → IMG_WIDTH−1).

**Output:** 25 pixel (8-bit mỗi pixel): `p[row][col]` với p[2][2] là center.

**Valid logic:** `o_valid` được assert sau khi đã nhận đủ `2×IMG_WIDTH + 3` pixel.

**Latency:** 2×IMG_WIDTH + 3 cycles (fill time).

---

### Stage 1: Pixel Distance (`adc_pixel_distance`)

**Chức năng:** Tính tổng khoảng cách cạnh (edge-based distance) dọc theo đường đi cố định từ center(2,2) đến mỗi vị trí trong cửa sổ 5×5.

**Thuật toán:**

Đường đi cố định từ center đến target: *đi chéo trước, rồi dọc, rồi ngang.*

1. **Inner ring (1-step)** — 8 neighbor trực tiếp (p11, p12, p13, p21, p23, p31, p32, p33):

$$dp(i,j) = |gray_{center} - gray_{neighbor}|$$

2. **Outer ring (2-step)** — 16 pixel ở rìa ngoài:

$$dp(i,j) = |gray_{center} - gray_{mid}| + |gray_{mid} - gray_{target}|$$

   Ví dụ:
   - `dp(0,0) = |p22 − p11| + |p11 − p00|`
   - `dp(0,1) = |p22 − p11| + |p11 − p01|`
   - `dp(0,4) = |p22 − p13| + |p13 − p04|`

3. **Center (2,2):** `dp = 0`

**Output:** 25 giá trị `dp_total` (9-bit, max 510).

**Latency:** 1 cycle (register output).

---

### Stage 2: Path Length (`adc_path_length`)

**Chức năng:** Tính $d_\lambda$ — khoảng cách path có trọng số, kết hợp khoảng cách không gian (spatial D8) và khoảng cách pixel.

**Công thức chính:**

$$d_\lambda(i,j) = \text{spatial}(i,j) + \lambda \cdot dp\_total(i,j)$$

Trong đó:
- $\lambda = \text{LAMBDA\_Q8} / 256$ (default: 51/256 ≈ 0.2)
- $\text{spatial}(i,j)$ sử dụng Chebyshev distance (D8 metric) × 2:

```
Spatial distance table (D8 × 2 cho diagonal):
    4  3  2  3  4
    3  2  1  2  3
    2  1  0  1  2
    3  2  1  2  3
    4  3  2  3  4
```

**Phép nhân hardware-friendly:**

$$\lambda \cdot dp = (\text{LAMBDA\_Q8} \times dp\_total) \gg 8$$

**Output:** 25 giá trị $d_\lambda$ (10-bit, max ~106).

**Latency:** 1 cycle (register output).

---

### Stage 3–4: R-Limit Compute (`adc_rlimit_compute`)

**Chức năng:** Tính ngưỡng $r\_limit$ = trung bình cộng của toàn bộ 25 giá trị $d_\lambda$.

**Pipeline 2 stage:**

| Sub-stage | Thao tác |
|-----------|----------|
| **S1** (cycle 1) | Cộng 25 giá trị `dl` bằng adder tree → `sum_total` (15-bit). Delay `dl[5×5]` 1 cycle. |
| **S2** (cycle 2) | Chia cho 25 bằng phép nhân dịch: `rlimit = (sum_total × 41) >> 10`. Delay `dl[5×5]` thêm 1 cycle. |

**Phép chia hardware-friendly:**

$$r\_limit = \left\lfloor \frac{\text{sum\_total} \times 41}{1024} \right\rfloor$$

(vì $41/1024 \approx 1/24.97 \approx 1/25$)

**Output:**
- `o_rlimit` (10-bit): Ngưỡng r_limit.
- `dl_d[5×5]` (10-bit × 25): Giá trị $d_\lambda$ đã delay 2 cycle, đồng bộ với `o_rlimit`.

**Latency:** 2 cycles.

---

### MC Window Delay Chain (4 cycles)

**Vấn đề:** MC window được tạo đồng thời với Gray window, nhưng kết quả rlimit đến chậm hơn 4 cycles so với window output.

**Pipeline latency cần bù:**

```
pixel_distance (1) + path_length (1) + rlimit (2) = 4 cycles
```

**Giải pháp:** MC window `mw[5×5]` (25×8-bit) được đưa qua 4 tầng delay flip-flop:

```
mw → mc_d1 → mc_d2 → mc_d3 → mc_d4
      (T+1)    (T+2)   (T+3)   (T+4)
```

Mỗi tầng delay gated bởi valid signal tương ứng:
- Stage 1: `mc_win_valid`
- Stage 2: `pdist_valid`
- Stage 3: `path_valid`
- Stage 4: `path_valid_d1`

→ `mc_d4[5×5]` aligned với `rlimit_valid`.

---

### Stage 5: ASE Masked Min (`adc_ase_masked_min`)

**Chức năng:** So sánh $d_\lambda$ với $r\_limit$ để tạo ASE mask, sau đó tìm min trong MC window chỉ với các pixel thuộc ASE.

**3 bước combinational + 1 register:**

1. **ASE Mask Generation:**

$$\text{mask}[i][j] = \begin{cases} 1 & \text{if } d_\lambda[i][j] \leq r\_limit \\ 0 & \text{otherwise} \end{cases}$$

   Center pixel (2,2) luôn có mask = 1 (vì $d_\lambda[2][2] = 0$, luôn ≤ $r\_limit$).

2. **Masked pixel values:**

$$\text{val}[i][j] = \begin{cases} pw[i][j] & \text{if mask}[i][j] = 1 \\ 255 & \text{if mask}[i][j] = 0 \end{cases}$$

   (255 = giá trị max 8-bit, không ảnh hưởng phép min)

3. **Min tree:**
   - Min từng hàng (5 pixel → 1 min, 4 comparator/hàng)
   - Min giữa 5 hàng (4 comparator)
   - **Tổng cộng:** 24 comparator

4. **Register output:** `o_adc` (8-bit), `o_valid`.

**Latency:** 1 cycle.

---

### Output Counter + Frame Done

- Bộ đếm `out_count` đếm số pixel output.
- Khi `out_count == FRAME_PIXELS − 1`, phát xung `o_done` (1 cycle).
- Reset khi `i_enable = 0`.

---

## 4. Pipeline Timing Summary

```
Cycle:  -N   ...  0     1     2     3     4     5
        ─────────┬─────┬─────┬─────┬─────┬─────┬─────
Gray stream:     │ Line Buffer fill (2N+3 cycles)    │
                 └──────────────────────────┬────────┘
                                            ▼
                                      gray_win_valid
                                            │
Stage 1: pixel_distance                    [1 clk]
                                            │
Stage 2: path_length                       [1 clk]
                                            │
Stage 3-4: rlimit_compute                 [2 clk]
                                            │
Stage 5: ase_masked_min                    [1 clk]
                                            │
                                            ▼
                                      o_valid / o_adc_pix
```

| Stage | Module | Latency | Output Width |
|-------|--------|---------|--------------|
| 0 | `adc_line_buffer_5x5` (×2) | 2N+3 cycles | 25×8b (window) |
| 1 | `adc_pixel_distance` | 1 cycle | 25×9b (dp_total) |
| 2 | `adc_path_length` | 1 cycle | 25×10b (d_lambda) |
| 3–4 | `adc_rlimit_compute` | 2 cycles | 10b (rlimit) + 25×10b (dl delayed) |
| — | MC delay chain | 4 cycles (parallel) | 25×8b (mc_d4) |
| 5 | `adc_ase_masked_min` | 1 cycle | 8b (adc_pix) |
| **Total** | **First valid output** | **2N + 8 cycles** | — |

Với IMG_WIDTH = 128: **Total initial latency = 259 cycles**.

Sau đó: **1 pixel output per clock** (throughput = 1 px/clk).

---

## 5. Sơ đồ luồng dữ liệu (Data Flow Diagram)

```
╔═══════════════════════════════════════════════════════════════════╗
║                    GRAY STREAM PATH                              ║
║                                                                   ║
║   i_gray_pix ──► [Line Buf 5×5] ──► gray_win[25×8b]             ║
║                        │                                          ║
║                        ▼                                          ║
║              [Pixel Distance]                                     ║
║              dp[i][j] = Σ|edge diffs| along path                 ║
║                        │  (25 × 9-bit)                           ║
║                        ▼                                          ║
║              [Path Length]                                         ║
║              dl[i][j] = spatial + λ × dp[i][j]                   ║
║                        │  (25 × 10-bit)                          ║
║                        ▼                                          ║
║              [R-Limit Compute]                                    ║
║              rlimit = mean(dl[5×5]) ≈ (Σdl × 41) >> 10          ║
║                   │            │                                  ║
║             rlimit(10b)   dl_delayed(25×10b)                     ║
║                   │            │                                  ║
╠═══════════════════╪════════════╪══════════════════════════════════╣
║                   │            │    MC STREAM PATH                ║
║                   │            │                                  ║
║   i_mc_pix ──► [Line Buf 5×5] ──► mc_win[25×8b]                 ║
║                                       │                           ║
║                              [4-stage Delay]                      ║
║                                       │                           ║
║                              mc_d4[25×8b]                        ║
║                                       │                           ║
╠═══════════════════╪════════════╪══════╪══════════════════════════╣
║                   ▼            ▼      ▼                           ║
║              ┌──────────────────────────────┐                     ║
║              │     ASE Masked Min           │                     ║
║              │  1) mask = (dl <= rlimit)    │                     ║
║              │  2) val = mask ? mc : 0xFF   │                     ║
║              │  3) adc = min(val[5×5])      │                     ║
║              └──────────────┬───────────────┘                     ║
║                             ▼                                     ║
║                      o_adc_pix [7:0]                             ║
╚═══════════════════════════════════════════════════════════════════╝
```

---

## 6. Parameters

| Parameter | Default | Mô tả |
|-----------|---------|-------|
| `IMG_WIDTH` | 128 | Chiều rộng ảnh (pixel) |
| `IMG_HEIGHT` | 128 | Chiều cao ảnh (pixel) |
| `LAMBDA_Q8` | 51 (≈0.2) | Hệ số lambda dạng Q0.8 fixed-point |

---

## 7. I/O Port Summary

| Port | Width | Dir | Mô tả |
|------|-------|-----|-------|
| `clk` | 1 | In | Clock |
| `rst_n` | 1 | In | Active-low reset |
| `i_enable` | 1 | In | Enable module (từ `ipu_control_logic`) |
| `i_gray_valid` | 1 | In | Gray pixel valid |
| `i_gray_pix` | 8 | In | Gray pixel data |
| `i_mc_valid` | 1 | In | MC pixel valid |
| `i_mc_pix` | 8 | In | MC pixel data |
| `o_valid` | 1 | Out | Output pixel valid |
| `o_adc_pix` | 8 | Out | ADC output pixel |
| `o_done` | 1 | Out | Frame done pulse (1 cycle) |

---

## 8. Tích hợp trong hệ thống (Integration)

Trong `ipu_top.sv`:

```
bank_pingpong_read ──► [adc_estimation] ──► t_computing stage
                            ▲
                      adc_enable (from ipu_control_logic)
```

- **Input:** MC stream từ bank_pingpong + Gray stream.
- **Output:** ADC stream + done pulse → gửi tới bước estimate transmission tiếp theo.
- **Control:** `adc_enable` từ `ipu_control_logic.sv`.

---

## 9. Tóm tắt thuật toán (Algorithm Summary)

```
Cho mỗi pixel center (2,2) trong cửa sổ 5×5:

1. Xây dựng 2 cửa sổ 5×5: Gray + MC
2. Tính dp_total cho mỗi vị trí (i,j):
     dp = Σ |gray[edge_a] - gray[edge_b]| dọc theo đường đi cố định
3. Tính d_lambda:
     d_λ(i,j) = spatial_D8(i,j) + λ × dp_total(i,j)
4. Tính r_limit:
     r_limit = mean( d_λ[toàn bộ 25 vị trí] )
5. Tạo ASE mask:
     mask(i,j) = 1 nếu d_λ(i,j) ≤ r_limit, ngược lại 0
6. Lọc min thích nghi:
     ADC = min{ MC(i,j) | mask(i,j) = 1 }
```

**Ý nghĩa:** Vùng ảnh phẳng → ASE lớn → lọc mạnh. Vùng ảnh có cạnh → ASE co lại → bảo toàn cạnh.
