# IPU Hardware Architecture - Detailed Diagrams & Examples

## Appendix A: Block Diagrams

### A.1 Complete Haze Removal Pipeline Block Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      PIXEL INPUT STREAM                                 │
│                    (i_src_rgb: 24-bit BGR)                             │
│                      @ i_src_valid clock                               │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │
                    ╔═══════════════════════╗
                    ║   DARK STAGE BLOCK   ║
                    ║  (1-cycle pipeline)   ║
                    ╠═══════════════════════╣
                    ║  dark_channel         ║ min(R, G, B)
                    ║  └─→ o_dark_ch [7:0]  ║
                    ╚═══════════════════════╝
                                │
                ┌───────────────┴────────────────┐
                │                                │
    ╔══════════════════════════════════════════╗         (FRAME LEVEL)
    ║    ATMOSPHERIC LIGHT ACCUMULATOR        ║
    ║    atmospheric_light.sv                 ║   Finds: max dark_ch
    ║    ├─ Per-frame max search               ║   → A = RGB of that pixel
    ║    └─ Outputs after frame_end pulse     ║
    ║       o_A_R, o_A_G, o_A_B [7:0]         ║
    ╚══════════════════════════════════════════╝
                │
    ┌───────────┴─────────────┬──────────────┐
    │                         │              │
┌──────────────────┐  ┌──────────────────┐   │
│  GRAYSCALE       │  │  SKY RECOGNITION │   │
│  grayscale.sv    │  │  sky_recognition │   │
│  (1-cycle)       │  │  (1-cycle after) │   │
│  0.31R+0.56G+0.1│  │  gray > A0?      │   │
│        2B        │  │  o_sky [0:0]     │   │
└──────────────────┘  └──────────────────┘   │
    │                         │               │
    └──────────┬──────────────┘               │
               │                             │
    ┌──────────────────────────────────────────┐
    │   TRANSMISSION ESTIMATION (PASS 1)      │
    │   estimate_transmission.sv               │
    │   ├─ invA_lut_q16 (×3): reciprocals     │
    │   ├─ norm_channel_q16 (×3): normalize   │
    │   ├─ min3_u8: find min normalized       │
    │   └─ omega_clamp_t: t = 255-(omega*min) │
    │   Output: o_tx [7:0] (coarse transmission)
    └────────┬─────────────────────────────────┘
             │
      ┌──────────────────────────┐
      │  TX BANK PING-PONG       │ (STORAGE)
      │  bank_pingpong_stream    │
      │  ├─ bank_bram (2×)       │ 
      │  ├─ frame_linear_counter │ (Write address)
      │  └─ Dual-port BRAM       │
      │     BANK1 WRITE          │ BANK2 READ
      │     ↕ (on swap)          │     ↕
      │     BANK2 WRITE          │ BANK1 READ
      └───┬──────────────────────┘
          │ (ADC reads neighbor TX values)
          │
     ┌────────────────────────────────────────────────────┐
     │                 ADC PIPELINE (PASS 2)              │
     │              adc_estimation.sv (5-stage)           │
     ├────────────────────────────────────────────────────┤
     │ Stage 0: Line Buffer Formation (4 rows deep)       │
     │ ├─ adc_line_buffer_5x5 (×2)                        │
     │ └─ Outputs 5×5 window every clock (after warmup)   │
     │                                                     │
     │ Stage 1: Pixel Distance (1-cycle)                  │
     │ ├─ adc_pixel_distance                              │
     │ └─ dp = edge distances along fixed paths           │
     │                                                     │
     │ Stage 2: Path Length (1-cycle)                     │
     │ ├─ adc_path_length                                 │
     │ └─ d_lambda = spatial + lambda × dp                │
     │                                                     │
     │ Stages 3-4: r_limit (2-cycle)                      │
     │ ├─ adc_rlimit_compute                              │
     │ ├─ r_limit = mean(d_lambda)                        │
     │ └─ Also delays d_lambda for alignment              │
     │                                                     │
     │ Stage 5: ASE Mask & Min (1-cycle)                  │
     │ ├─ adc_ase_masked_min                              │
     │ ├─ mask = (d_lambda <= r_limit)                    │
     │ └─ adc = min(MC where masked) [7:0]                │
     │                                                     │
     └─────────┬──────────────────────────────────────────┘
               │ o_adc_pix [7:0]
               │
        ┌──────────────────────────────────┐
        │  FINAL RECOVERY (PASS 3)         │
        │  t_compute_fuse.sv (2-cycle)     │
        │  ├─ t_computing:                 │
        │  │   tx = 255 - (dark*omega/A)   │
        │  │   tx_used = max(tx, T_MIN)    │
        │  │                               │
        │  └─ fusing:                      │
        │      out = (src - A) / tx + A    │
        │      (clamped to [0..255])       │
        └─────────┬──────────────────────────┘
                  │
            ┌─────────────────┐
            │  OUTPUT FRAME   │
            │  (post_img [23:0])
            │  post_frame_clken
            │  post_frame_vsync
            └─────────────────┘
```

### A.2 Control FSM State Diagram

```
                    ┌─────────────────────┐
                    │      S_IDLE         │
                    │   (wait for START)  │
                    └────────┬────────────┘
                             │ ipu_en && ipu_start
                             ↓
                    ┌─────────────────────┐
                    │      S_LOAD         │
                    │  (clear banks)      │
                    │  bank_wr_clear=1    │
                    │  bank_rd_clear=1    │
                    └────────┬────────────┘
                             │ (1 cycle auto)
                             ↓
        ┌──────────────────────────────────────────┐
        │          S_DARK                          │
        │  (Dark Channel Read, 128×128 cycles)     │
        │  Outputs:                                │
        │  ├─ dark_enable=1                        │
        │  ├─ reader_start=1 (pulse on enter)      │
        │  └─ reader reads full frame              │
        └────────┬─────────────────────────────────┘
                 │ reader_done=1
                 ↓
        ┌──────────────────────────────────────────┐
        │          S_SKY                           │
        │  (Sky Recognition & Atmospheric Light)   │
        │  Outputs:                                │
        │  ├─ sky_enable=1                         │
        │  └─ Processes already-computed data      │
        └────────┬─────────────────────────────────┘
                 │ sky_done=1
                 ↓
        ┌──────────────────────────────────────────┐
        │          S_TRANS                         │
        │  (Transmission Estimation & Bank Write)  │
        │  Outputs:                                │
        │  ├─ trans_enable=1                       │
        │  ├─ reader_start=1 (second pass)         │
        │  ├─ bank_wr_clear=1 (on enter)           │
        │  └─ reader reads frame again, bank writes│
        └────────┬─────────────────────────────────┘
                 │ reader_done=1
                 ↓
        ┌──────────────────────────────────────────┐
        │          S_ADC                    [MAIN] │
        │  (Adaptive Dark Channel Computation)     │
        │  Outputs:                                │
        │  ├─ adc_enable=1                         │
        │  ├─ bank_swap=1 (on enter, flip banks)   │
        │  ├─ bank_rd_clear=1 (2 cycles)           │
        │  ├─ bank_rd_en=1 (starts ADC read)       │
        │  └─ Computes ADC from stored TX values   │
        └────────┬─────────────────────────────────┘
                 │ adc_done=1
                 ↓
        ┌──────────────────────────────────────────┐
        │          S_RECOVERY                 [SYNTH]
        │  (Transmission Computation & Fusion)     │
        │  Outputs:                                │
        │  ├─ recovery_enable=1                    │
        │  ├─ reader_start=1 (third frame read)    │
        │  ├─ writer_start=1 (start output write)  │
        │  └─ Reads input, processes with ADC,     │
        │     writes recovered image               │
        └────────┬─────────────────────────────────┘
                 │ recovery_done && writer_done
                 ↓
        ┌──────────────────────────────────────────┐
        │          S_DONE                          │
        │  assert done=1, ipu_irq=1 (if enabled)   │
        └────────┬─────────────────────────────────┘
                 │
          ┌──────┴──────┐
          │             │
 (cont_mode=0)  (cont_mode=1)
          │             │
       S_IDLE        S_LOAD
```

### A.3 ADC 5-Stage Pipeline Data Flow

```
STAGE 0: LINE BUFFER (Latency: 4*WIDTH+4 cycles until first valid window)
┌──────────────────────────────────────────────────────────────────────┐
│  Streaming pixel input (gray, MC both in parallel):                 │
│  ├─ col_cnt: 0 → WIDTH-1 (increments each valid pixel)             │
│  ├─ line_buf[0..3]: Store 4 rows of history (depth=WIDTH)          │
│  └─ Shift all rows into 5-row shift registers (p[0..4][0..4])      │
│                                                                      │
│  Output: 5×5 window (25 pixels) with center at [2,2]               │
│  Data width: 25 × [7:0] = 200 bits (for gray window)               │
│  Valid flag: gray_win_valid, mc_win_valid                          │
└──────────────────────────────────────────────────────────────────────┘
                                    │ 4*WIDTH+4 cycle delay
                                    ↓
STAGE 1: PIXEL DISTANCE (Fixed-path edge sums)
┌──────────────────────────────────────────────────────────────────────┐
│  Input: 5×5 gray window (pilot for edge detection)                  │
│  Algorithm: Compute |p[i,j] - intermediate| + |intermediate - p22|  │
│  for each of 24 neighbor positions                                   │
│                                                                      │
│  Output: 25 × [8:0] dp values (dp[i,j] = edge distance sum)        │
│  Data width: 25 × 9 bits = 225 bits                                 │
│  Valid flag: pdist_valid                                            │
└──────────────────────────────────────────────────────────────────────┘
                                    │ 1 cycle
                                    ↓
STAGE 2: PATH LENGTH (Spatial + lambda weighting)
┌──────────────────────────────────────────────────────────────────────┐
│  Input: 25 × [8:0] dp values                                        │
│  Spatial distance table (D8 metric from center):                    │
│    4 3 2 3 4                                                        │
│    3 2 1 2 3                                                        │
│    2 1 0 1 2                                                        │
│    3 2 1 2 3                                                        │
│    4 3 2 3 4                                                        │
│                                                                      │
│  d_lambda[i,j] = spatial[i,j] + LAMBDA_Q8 * dp[i,j] / 256          │
│  Example: If LAMBDA_Q8 = 51 (≈ 0.2), dp = 100                      │
│           d_lambda = spatial + (51 * 100 >> 8) = spatial + 19      │
│                                                                      │
│  Output: 25 × [9:0] d_lambda values (max ~106)                     │
│  Data width: 25 × 10 bits = 250 bits                                │
└──────────────────────────────────────────────────────────────────────┘
                                    │ 1 cycle
                                    ↓
STAGES 3-4: r_limit COMPUTATION (Mean threshold, 2-cycle pipeline)

STAGE 3: SUM reduction (Adder tree)
┌──────────────────────────────────────────────────────────────────────┐
│  Input: 25 × [9:0] d_lambda values                                  │
│  Tree-based parallel summation: 13-level adder tree                 │
│  sum_total = Σ d_lambda[i,j] for all 25 positions                  │
│  Output: sum_total [14:0] (15-bit, max ≈ 2650)                      │
│  Also: Delay d_lambda by +1 cycle for alignment with rlimit         │
│  Registers both outputs at end of stage                             │
└──────────────────────────────────────────────────────────────────────┘

STAGE 4: MULTIPLY-SHIFT r_limit derivation
┌──────────────────────────────────────────────────────────────────────┐
│  Input: sum_total_r [14:0] (from stage 3 register)                  │
│  Algorithm: r_limit = (sum_total * 41) >> 10                        │
│            This approximates division by 25 (41/1024 ≈ 1/24.97)    │
│                                                                      │
│  prod = sum_total_r * 41 [20:0]                                     │
│  r_limit = prod[20:10] [9:0] (extract high 10 bits, shift >>10)     │
│                                                                      │
│  Output: r_limit [9:0] (10-bit, max ~101 with LAMBDA_Q8=51)        │
│  Also output: d_lambda delayed by +1 more cycle (now 4 cycles total)│
│  This aligns d_lambda with rlimit for position-wise comparison      │
└──────────────────────────────────────────────────────────────────────┘
                                    │ (2 cycle total for stages 3-4)
                                    ↓
STAGE 5: ASE MASK & MINIMUM (Final adaptive SE selection)
┌──────────────────────────────────────────────────────────────────────┐
│  Inputs:                                                             │
│  ├─ r_limit [9:0] (from stage 4)                                    │
│  ├─ d_lambda_delayed [9:0] × 25 (aligned from stage 4, 4 cycles)   │
│  └─ MC (minimum channel) window [7:0] × 25 (from line_buf, delayed) │
│                                                                      │
│  Algorithm:                                                         │
│  for i,j in 5×5:                                                    │
│    mask[i,j] = (d_lambda_delayed[i,j] <= r_limit) ? 1 : 0         │
│    masked_pixel[i,j] = mask[i,j] ? MC[i,j] : 255 (neutral for min) │
│                                                                      │
│  adc = min(masked_pixel[0,0], ..., masked_pixel[4,4])              │
│                                                                      │
│  Output: adc [7:0] (single value per window center)                 │
│          valid pulse                                                │
│                                                                      │
│  Latency: 1 cycle (combinational comparators + register output)     │
└──────────────────────────────────────────────────────────────────────┘

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
TOTAL ADC PIPELINE LATENCY:
  Warmup:      4*WIDTH + 4 cycles (line buffer warm-up)
  Processing:  1 + 1 + 2 + 1 = 5 cycles (after first valid window)
  Alignment:   4 cycles (MC window delayed to match rlimit timing)
  ─────────────────────────────────────────────────────
  First output valid:  4*WIDTH + 9 cycles
  
  For 128-pixel width: 4*128 + 9 = 521 cycles
```

---

## Appendix B: Detailed Module Timing Examples

### B.1 Dark Channel Pipeline Timing

```
Cycle | Input         | Processing        | Output
──────┼───────────────┼──────────────────┼──────────────────────────
  0   | i_color=RGB0  | Comb: min(R,G,B) | (internal, not output yet)
  1   | i_color=RGB1  | Comb: min(R,G,B) | dark_ch0 = min(RGB0) [reg]
  2   | i_color=RGB2  | Comb: min(R,G,B) | dark_ch1 = min(RGB1) [reg]
  3   | ...           | ...              | ...
  N   | i_color=RGBN  | Comb: min(R,G,B) | dark_chN-1 = min(RGBN-1)

Latency: 1 clock cycle from i_valid to output availability
Output valid signal: o_valid = 1 (constant, always ready)
```

### B.2 t_compute_fuse (2-Stage) Timing

```
Cycle | Stage 1 Input           | Stage 1 Compute | Stage 2 Process
──────┼─────────────────────────┼─────────────────┼──────────────────
  0   | i_valid=1               | ─               | ─
      | i_dark=ADC0, i_A=A_max  |                 |
      | i_A_r/g/b, i_src_r/g/b  |                 |
      |                         |                 |
  1   | i_valid=1               | Compute tx_raw  | ─
      | i_dark=ADC1 (new)       | = 255 -         | (stage 1 output
      |                         | (dark*omega/A)  |  latching)
      |                         | tx_used = clamp |
      |                         |                 |
  2   | i_valid=1               | Compute tx_raw  | Compute output =
      | i_dark=ADC2             | = 255 -         | (src-A)/tx+A
      |                         | (dark*omega/A)  | Clamp [0..255]
      |                         | tx_used = clamp | output_r/g/b [reg]
      |                         |                 |
  3   | i_valid=1               | Compute tx_raw  | Compute output
      | i_dark=ADC3             | ...             | (ADC[1] results)
      |                         |                 |
─────────────────────────────────────────────────────────────────────
o_valid latency: 2 cycles from i_valid assertion
```

### B.3 Atmospheric Light (Frame-Level) Timing

```
Pass 1: Dark Channel Scan (N pixels over N cycles, typically 128×128=16384)

Cycle | Input          | Processing           | Internal Register
──────┼────────────────┼──────────────────────┼───────────────────────
  0   | frame_start=1  | Reset accumulators   | max_dark=0, max_intens=0
      | color=pix0     | max_dark_compare     | A_r/g/b = 0
      |                |                      |
  1   | valid=1        | Compare dark_ch[0]   | Update if (dark>max_dark)
      | color=pix1     | with max_dark        |   or (dark==max && intens>max_intens)
      | dark_ch[0]=dc0 | intensities match    |
      |                |                      |
  2   | valid=1        | Compare dark_ch[1]   | Possibly update accumulators
      | color=pix2     |                      |
      | dark_ch[1]=dc1 |                      |
      |                |                      |
  ... | ...            | ...                  | ...
      |                |                      |
 N    | valid=1        | Compare dark_ch[N-1] | Final accumulators locked
      | frame_end=1    |                      |
      | color=pixN     |                      |
      |                |                      |
N+1    | frame_end_d1=1 | Latch A into output | o_A_R/G/B ← final values
      | (delayed 1)    | registers            | o_valid ← 1
      |                |                      |
N+2    | (frame_start   | Continue output      | A remains stable for recovery
      | for next frame)| latched              |

Latency from i_frame_end to o_A_valid: +1 cycle
A values remain valid until i_frame_start of next frame
Typical duration: ~16K cycles for 128×128 frame scan
```

---

## Appendix C: Data Flow Examples

### C.1 Example: 8×8 Test Image Processing

```
Input (8×8 hazy image, all pixels = {R=180, G=160, B=140}):
Every pixel is the same color, no spatial variation.

Stage 1: DARK CHANNEL
─────────────────────
Every pixel → min(180, 160, 140) = 140
dark_ch frame = all pixels [140]
o_valid pulse after first pixel (after 1 cycle)

Stage 2: ATMOSPHERIC LIGHT
──────────────────────────
Frame scan: all dark_ch values = 140 (tie)
Since all tied, select pixel with max intensity:
  intensity = 180 + 160 + 140 = 480 (same for all)
Choose first pixel encountered (or any, results identical)
A_R = 180, A_G = 160, A_B = 140
o_A_valid after frame_end + 1 cycle

Stage 3: TRANSMISSION ESTIMATION
────────────────────────────────
For every pixel {R=180, G=160, B=140} with A={180,160,140}:
  inv_A_q16[180] ≈ 181.9 (from LUT)
  inv_A_q16[160] ≈ 204.8
  inv_A_q16[140] ≈ 235.4
  
  norm_r = (180 * 181.9) >> 16 = 32742 >> 16 = 255 (saturate)
  norm_g = (160 * 204.8) >> 16 = 32768 >> 16 = 255 (saturate)
  norm_b = (140 * 235.4) >> 16 = 32956 >> 16 = 255 (saturate)
  
  min_norm = min(255, 255, 255) = 255
  
  t = 255 - (255 * 255) >> 8 = 255 - 255 = 0 (fully hazed)
  clamp: t = max(0, T_MIN) = T_MIN (e.g., 15 or 26)
  
Output: tx ≈ T_MIN (~0.06-0.10 in [0..1] scale)
Bank writes: all pixels tx = T_MIN

Stage 4: ADC ESTIMATION (5-stage pipeline)
──────────────────────────────────────────
Line buffer warmup: 4*8 + 4 = 36 cycles (to fill 4 rows + shift)
Processing starts @ cycle 37

For an 8×8, only center 4×4 region has valid 5×5 windows
Boundary pixels [0,0], [0,7], [7,0], [7,7] lack full neighborhoods

ADC example for pixel [3,3]:
  5×5 window (gray & MC) centered at [3,3]:
  All pixels: gray = 140, MC (tx) ≈ T_MIN ≈ 15..26 uniform
  
  dp_total (all edges identical distance): ~0 (uniform region)
  d_lambda: spatial + 0 = spatial values only
    Center [2,2]: d_lambda = 0
    Neighbors: d_lambda = 1..4 (depending on position)
  
  r_limit = mean(d_lambda) ≈ sum/25 ≈ 50/25 = 2 (approx)
  
  mask: all d_lambda <= 2? → Only pixels with d_lambda ≤ 2 included
    This includes center + some neighbors (typically inner 3×3)
  
  adc = min(MC values within mask) ≈ T_MIN (all TX values identical)

Output frame ADC values: [15..26] (depending on masking, but all similar)

Stage 5: RECOVERY (t_compute_fuse)
──────────────────────────────────
For output pixel [3,3]:
  i_dark = adc ≈ 26 (from ADC stage)
  i_A = {180, 160, 140}, A_max = 180
  i_src = {180, 160, 140} (input pixel)
  
  t_computing:
    modify_A = 26 * 255 = 6630
    tx_raw = 255 - (6630 / 180) = 255 - 36 = 219
    tx_used = max(219, T_MIN) = 219
  
  fusing (for each channel):
    R: diff = 180 - 180 = 0
       value_tem = (0 << 8) + 180 * 219 = 39420
       out_r = 39420 / 219 = 180
    G: diff = 160 - 160 = 0
       value_tem = (0 << 8) + 160 * 219 = 35040
       out_g = 35040 / 219 = 160
    B: diff = 140 - 140 = 0
       value_tem = (0 << 8) + 140 * 219 = 30660
       out_b = 30660 / 219 = 140
  
  recovered = {180, 160, 140} ≈ original input!
  Note: With ADC ≈ 26 (small dark channel), minimal dehaze effect

This example shows:
  - Uniform hazy region → small dark_ch → small ADC
  - Minimal recovery needed (already mostly dehazed or artifact of synthetic data)
  - Real images have spatial variation → larger ADC ranges → meaningful recovery
```

### C.2 Example: Real Hazy Region (Synthetic)

```
Input (8×8 region with haze gradient):
└─ Darker left side (less hazed), brighter right side (more hazed)
└─ Atmospheric light A ≈ {230, 220, 200} (bright, warm)
└- Dark channel left (clear): 30..60
└- Dark channel right (hazy): 100..180

Stage 1-2: Processing produces A ≈ {230, 220, 200}

Stage 3: TRANSMISSION (varying across region)
──────────────────────────────────────────────
Left pixels (dark_ch ≈ 30):
  min_norm ≈ 30/230 ≈ 0.13
  t ≈ 255 - (255 * 0.13) ≈ 255 - 33 = 222 (high transmission, clear)
  tx = max(222, T_MIN) ≈ 222

Center pixels (dark_ch ≈ 100):
  min_norm ≈ 100/230 ≈ 0.43
  t ≈ 255 - (255 * 0.43) ≈ 150
  tx ≈ 150

Right pixels (dark_ch ≈ 180):
  min_norm ≈ 180/230 ≈ 0.78
  t ≈ 255 - (255 * 0.78) ≈ 57
  tx = max(57, T_MIN) ≈ 57 (low transmission, very hazy)

TX bank now contains varying transmission map: [222, ..., 150, ..., 57, ...]

Stage 4: ADC ENHANCEMENT
───────────────────────
ADC uses transmission values from neighbors to improve dark channel

For hazy region (right, dark_ch ≈ 180, tx ≈ 57):
  Neighbors (left) have tx ≈ 222 (clearer)
  d_lambda will be small only for neighbors with low distance
  r_limit = mean(d_lambda) will be moderate
  
  Pixels with d_lambda ≤ r_limit: mostly neighbors (geometrically close)
  adc = min(neighbors' tx values) ≈ 150..222 (clearer than dark_ch=180)
  
Result: ADC ≈ 180-200 for initially hazed region (sharpened from 57)

Stage 5: RECOVERY
─────────────────
Using adc ≈ 180-200 instead of coarse tx ≈ 57:
  t_used ≈ max(180-200, T_MIN) = 180-200 (less aggressive)
  recovered ≈ (src - A) / 180 + A
  
  Effect: More conservative dehaze, preserves detail in clear regions
  Better than using coarse tx which would over-correct

Output: Spatially more consistent, natural-looking dehazed image
```

---

## Appendix D: Python-to-Hardware Correspondence Table

### D.1 Function Mapping

| Python Function | Hardware Module | Implementation | Latency |
|-----------------|-----------------|-----------------|---------|
| `np.min(img, axis=2)` | dark_channel + src_min | min(R,G,B) per pixel | 1 cycle |
| `np.argmax(dark_ch.flatten())` | atmospheric_light | Max accumulator | Frame duration + 1 |
| Loop pixel search for A | atmospheric_light | Registered max + tie-break | Frame |
| `1.0 / A` | invA_lut_q16 | 256-entry ROM LUT | 0 cycles (comb) |
| `img * inv_A` | norm_channel_q16 | Multiply + shift right 16 | 0 cycles (comb) |
| `(img*inv_A).min(axis=2)` | min3_u8 | 3-input min | 0 cycles (comb) |
| `1.0 - omega*norm` | omega_clamp_t | Multiply + sub + clamp | 0 cycles (comb) |
| `np.clip(t, T_MIN, 1)` | Part of estimate_transmission | Register + saturation | 1 cycle |
| `grayscale(img)` | grayscale | Weighted sum + round | 1 cycle |
| `gray > threshold` | sky_recognition | Comparator + register | 1 cycle |
| `adaptive_dark_channel(...)` | adc_estimation (full 5-stage) | Line buffer + 5 stages | 4*WIDTH + 9 cycles |
| Loop 5x5 window | adc_line_buffer_5x5 | 4 line buffers + shift regs | 4*WIDTH + 4 warmup |
| `pixel_distance(window)` | adc_pixel_distance | Fixed-path edge summing | 1 cycle |
| `d_lambda = spatial + lambda*dp` | adc_path_length | LUT + multiply-shift | 1 cycle |
| `r_limit = mean(d_lambda)` | adc_rlimit_compute | Adder tree + multiply-shift | 2 cycles |
| `mask = d_lambda <= r_limit` | adc_ase_masked_min | Comparators | 0 cycles (comb) |
| `min(mc[mask])` | adc_ase_masked_min | Min tree with masking | 0 cycles (comb) |
| `(src - A) / t + A` | fusing | Multiply-shift-divide + clamp | 1 cycle |

---

## Appendix E: Register Programming Guide

### E.1 Initialization Sequence

```c
// Initialize IPU for processing a 128×128 image
void ipu_initialize() {
    // 1. Write configuration
    write_reg(IPU_IMG_WIDTH,  128);      // Set image dimensions
    write_reg(IPU_IMG_HEIGHT, 128);
    write_reg(IPU_IMG_STRIDE, 512);      // 128*4 bytes (32-bit word stride)
    write_reg(IPU_IMG_FORMAT, 0x01);     // BGR888 format
    
    // 2. Set BRAM buffer addresses
    write_reg(IPU_SRC_ADDR, 0x0000);     // Input frame @ 0x0000
    write_reg(IPU_DST_ADDR, 0x0000);     // Output frame @ 0x0000 (or separate block)
    write_reg(IPU_TMP_ADDR, 0x0000);     // Temporary buffer (if needed)
    
    // 3. Enable interrupts
    write_reg(IPU_IRQ_EN, 0x0001);       // Enable DONE interrupt
    
    // 4. Clear any pending status
    write_reg(IPU_IRQ_STATUS, 0x0001);   // W1C: clear done flag
}

// Load input image into IMG_IN BRAM (Port A system access)
void ipu_load_image(uint8_t *image_data, int width, int height) {
    int stride = width * 4;  // Assuming 32-bit word packing
    int bram_addr = 0;
    
    for (int i = 0; i < width * height; i++) {
        // Pack pixels into 32-bit word (implementation-specific)
        uint32_t pixel_word = (image_data[4*i+0] << 0)  |
                             (image_data[4*i+1] << 8)  |
                             (image_data[4*i+2] << 16) |
                             (image_data[4*i+3] << 24);
        
        write_bram(IMG_IN, bram_addr++, pixel_word);
        
        if (bram_addr * 4 >= width * height * 3)
            break;
    }
}

// Start IPU processing
void ipu_start_frame() {
    write_reg(IPU_CTRL, 0x01);  // EN = 1
    write_reg(IPU_CTRL, 0x03);  // EN = 1, START = 1
}

// Wait for completion
void ipu_wait_done() {
    while ((read_reg(IPU_STATUS) & 0x04) == 0) {
        // Poll DONE bit (bit 2 of IPU_STATUS)
        // Or wait for interrupt
    }
}

// Read output image from IMG_OUT BRAM
void ipu_read_image(uint8_t *output_data, int width, int height) {
    int bram_addr = 0;
    int out_idx = 0;
    
    for (int i = 0; i < width * height; i++) {
        uint32_t pixel_word = read_bram(IMG_OUT, bram_addr++);
        
        // Unpack pixels from 32-bit word
        output_data[out_idx++] = (pixel_word >> 0) & 0xFF;
        output_data[out_idx++] = (pixel_word >> 8) & 0xFF;
        output_data[out_idx++] = (pixel_word >> 16) & 0xFF;
        // Byte 24-31 typically unused or padding
    }
}
```

### E.2 Continuous Mode Processing

```c
// Process multiple frames in continuous mode
void ipu_process_continuous(uint8_t **frames, int num_frames, uint8_t **outputs) {
    // Initialize once
    ipu_initialize();
    
    // Enable continuous mode
    write_reg(IPU_CTRL, 0x05);  // EN = 1, CONT_MODE = 1
    
    for (int frame_num = 0; frame_num < num_frames; frame_num++) {
        // Load next frame
        ipu_load_image(frames[frame_num], 128, 128);
        
        // Start processing
        if (frame_num == 0) {
            ipu_start_frame();
        }
        // In continuous mode, FSM automatically loops to S_LOAD after S_DONE
        
        // Wait for this frame to complete
        ipu_wait_done();
        
        // Read results
        ipu_read_image(outputs[frame_num], 128, 128);
        
        // Clear done flag for next frame
        write_reg(IPU_IRQ_STATUS, 0x0001);  // W1C
    }
    
    // Stop continuous mode
    write_reg(IPU_CTRL, 0x00);  // EN = 0, stop
}
```

---

## Appendix F: Verification Checksums

### F.1 Pixel-by-Pixel Computation Reference (Golden Test Vector)

**Test Input: Uniform {R=120, G=100, B=80}**

| Stage | Module | Intermediate | Value | Notes |
|-------|--------|--------------|-------|-------|
| 1 | dark_channel | dark_ch | 80 | min(120,100,80) |
| 2 | atmospheric_light | A_rgb | {120,100,80} | Trivial case: all same |
| 2 | grayscale | gray | 100 | 0.3125*120+0.5625*100+0.125*80 |
| 2 | sky_recognition | is_sky | 0 | 100 > 150? No |
| 3 | invA_lut_q16[120] | inv_A_q16 | 546 (approx) | 2^16 / 120 ≈ 546 |
| 3 | norm_channel | norm_r | 108 | (120*546)>>16 ≈ 108 |
| 3 | norm_channel | norm_g | 90 | (100*546)>>16 ≈ 90 (scaled by different A_g) |
| 3 | estimate_transmission | min_norm | ~85 | min(108,90,75) ≈ 75 |
| 3 | omega_clamp_t | tx | ~130 | 255 - (255*75/65536) ≈ 130 (depends on OMEGA) |
| 4 | adc_estimation | adc | ~80 | Depends on 5x5 neighborhood (center likely) |
| 5 | t_computing | tx_used | max(130, T_MIN) ≈ 130 | | 
| 5 | fusing | out_r | ~120 | (120-120)/130+120 = 120 |
| 5 | fusing | out_g | ~100 | (100-100)/130+100 = 100 |
| 5 | fusing | out_b | ~80 | (80-80)/130+80 = 80 |
| FINAL | recovered | output | {120,100,80} | Uniform input → minimal dehaze (already clear) |

---

**End of Supplementary Diagrams & Examples**

