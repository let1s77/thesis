# Quick Reference Guide - Python SW Module Interconnections

## Module Execution Dependency Graph

```
STAGE 0: PREPROCESSING
┌──────────────────────────────────┐
│ INPUT: RGB Image (5x5 frame)     │
│        25 pixels × 3 channels    │
└─────────────┬────────────────────┘
              │
       ┌──────┴─────────────────────────┐
       │                                 │
       ▼                                 ▼
   ┌────────────┐             ┌────────────────┐
   │dark_ch[25] │             │gray_list[25]   │
   │min(R,G,B)  │             │(5R+9G+2B)/16   │
   │            │             │                │
   │ 8-bit out  │             │ 8-bit out      │
   └──────┬─────┘             └────────┬───────┘
          │                           │
          └───────────────┬───────────┘
                          │
          ┌───────────────┴────────────────────┐
          │                                     │
          ▼                                     ▼
    ┌─────────────────┐          ┌──────────────────────┐
    │atmospheric_light│          │sky_recognition      │
    │ (A_R,A_G,A_B)  │          │ sky[25] = 0 or 1     │
    │                 │          │                      │
    │Select max dark  │          │ src_val = dark or    │
    │+ intensity      │          │         gray         │
    │tie-break        │          │ sky = (src_val>A0)   │
    └────────┬────────┘          └──────────┬───────────┘
             │                              │
             │        A (3×8-bit)           │
             └──────────────┬───────────────┘
                            │

STAGE 1: COARSE TRANSMISSION
   ┌────────────────────────────────────────────┐
   │  estimate_transmission                     │
   │  ├─ Normalize: norm_c = (pix_c×inv_A)>>16  │
   │  ├─ Min: min_norm = min(norm_r,g,b)        │
   │  ├─ Omega: scaled = (OMEGA×min_norm)>>8    │
   │  └─ Output: t = 255 - scaled (8-bit)       │
   │                                            │
   │  Input:  RGB, Sky, A from previous stage  │
   │  Output: t_list[25] (transmission map)     │
   └────────────────┬───────────────────────────┘
                    │
         t_list (25×8-bit)
                    │
       ┌────────────▼───────────────────┐
       │                                 │
       ▼                                 ▼
   ┌──────────────────────┐    ┌─────────────────────┐
   │ STAGE 2a: ADC        │    │ STAGE 2b: t_compute │
   │(Adaptive Dark Channel)   │ (Recovery)          │
   │                          │                     │
   │ Input: t_list[25]   │    │ Input: adc_dark     │
   │ ├─pixel_distance    │    │        A, src_RGB   │
   │ ├─path_length       │    │                     │
   │ ├─rlimit (√)        │    │ Output: tx_raw      │
   │ └─ase_masked_min    │    │         tx_used     │
   │ Output: adc_dark    │    │         RGB_out     │
   │         (8-bit)     │    │                     │
   └──────────┬──────────┘    └─────────┬───────────┘
              │                         │
              │ adc_dark (8-bit)        │ RGB_out (24-bit)
              │                         │
              └──────────┬──────────────┘
                         │
                         ▼
            ┌─────────────────────────┐
            │ OUTPUT: Dehazed RGB     │
            │ (Center pixel recovered)│
            └─────────────────────────┘
```

## File Execution Sequence

### For Complete E2E Testing
```
1. haze_removal_top_sw.py
   └─ Generates: pattern_haze_removal_top_input.hex
                 golden_haze_removal_top.hex
                 golden_haze_removal_top_A.hex
                 golden_haze_removal_top_adc.hex
                 golden_haze_removal_top_tx5x5.hex
                 haze_removal_top_cases.csv
```

### For Modular Testing
```
2. dark_channel.py
   └─ Generates: pattern_dark_channel.hex
                 golden_dark_channel.hex
                 dark_channel_report.txt

3. grayscale.py
   └─ Generates: pattern_grayscale.hex
                 golden_grayscale.hex (×3 modes)
                 grayscale_report.txt

4. atmospheric_light.py
   └─ Generates: pattern_atmospheric_light.hex
                 golden_atmospheric_light.hex
                 atmospheric_light_report.txt

5. sky_recognition.py
   └─ Generates: pattern_sky_gray.hex
                 pattern_sky_darkch.hex
                 pattern_sky_usedark.hex
                 pattern_sky_a0.hex
                 golden_sky_recognition.hex
                 golden_sky_bw.hex
                 sky_recognition_report.txt

6. estimate_transmission.py
   └─ Generates: rgb.hex
                 sky.hex
                 t_golden.hex
                 estimate_transmission_report.txt

7. adc_estimation_top.py
   └─ Generates: adc_case_XX_gray.hex (×20)
                 adc_case_XX_mc.hex (×20)
                 adc_case_XX_golden.txt (×20)
                 adc_summary.csv

8. t_compute_fuse_sw.py
   └─ Generates: t_compute_fuse_input.hex
                 t_compute_fuse_golden.hex
                 t_compute_fuse_cases.csv
                 t_compute_fuse_case_table.md

9. bank_pingpong.py
   └─ Generates: pattern_bank_wr_data.hex
                 golden_bank_rd_data.hex
                 golden_bank_position.txt
                 bank_pingpong_report.txt

10. gen_invA_lut_q16.py
    └─ Generates: invA_lut_q16.sv
```

---

## Data Flow: From Input to Output

### Example: Single 5×5 Frame Through Full Pipeline

```
INPUT FRAME (5×5 RGB):
┌─────────────────────────────┐
│ (R1,G1,B1)  (R2,G2,B2) ...  │
│ (R6,G6,B6)  (R7,G7,B7) ...  │  Center = (R13,G13,B13)
│ ...          (R13,...) ...  │
└─────────────────────────────┘

STEP 1: Dark Channel (parallel)
   dark[i] = min(R[i], G[i], B[i]) for i=1..25
   
   Example: dark[13] = min(R13, G13, B13) = 140

STEP 2a: Atmospheric Light (sequential scan)
   1. Find i_max where dark[i_max] = max(dark[1..25])
   2. Tie-break: if tie, select max(R[i]+G[i]+B[i])
   3. Return A = (R[i_max], G[i_max], B[i_max])
   
   Example: A = (190, 200, 210)

STEP 2b: Grayscale (parallel)
   gray[i] = (5×R[i] + 9×G[i] + 2×B[i]) >> 4
   
   Example: gray[13] = (5×120 + 9×110 + 2×100) >> 4 = 128

STEP 3: Sky Recognition (parallel)
   sky[i] = (gray[i] > 150) ? 1 : 0
   
   Example: sky[13] = (128 > 150) ? 1 : 0 = 0 (non-sky)

STEP 4: Coarse Transmission (parallel, using A from step 2a)
   For each pixel i:
     norm_r[i] = saturate((R[i] × inv_lut[A_R]) >> 16)
     norm_g[i] = saturate((G[i] × inv_lut[A_G]) >> 16)
     norm_b[i] = saturate((B[i] × inv_lut[A_B]) >> 16)
     min_norm[i] = min(norm_r, norm_g, norm_b)
     scaled[i] = (OMEGA_Q8 × min_norm[i]) >> 8
     t[i] = max(255 - scaled[i], T_MIN)
   
   Example for center pixel (13):
     min_norm[13] ≈ 85
     scaled[13] = (243 × 85) >> 8 ≈ 81
     t[13] = max(255 - 81, 26) = 174

STEP 5: ADC Estimation (center of 5×5, uses t[1..25] as input)
   5a. Compute pixel_distance[i]:
       dp[i] = sum of |gray differences| along path from center
   
   5b. Compute path_length[i]:
       dl[i] = spatial_dist[i] + (LAMBDA_Q8 × dp[i]) >> 8
   
   5c. Compute rlimit:
       rlimit = (sum(dl[1..25]) × 41) >> 10  [≈ mean]
   
   5d. Create ASE mask & find minimum:
       mask[i] = (i==center) ? 1 : (dl[i] <= rlimit) ? 1 : 0
       adc_dark = min(t[i] for all i where mask[i]==1)
   
   Example: adc_dark = 160 (slightly lower than coarse t[13]=174)

STEP 6: Transmission Computation (using adc_dark from step 5)
   tx_raw = 255 - floor((adc_dark × MODIFICATION) / A_R)
   tx_used = max(tx_raw, TX_MIN)
   
   Example: tx_raw = 255 - floor((160 × 255) / 190) ≈ 156
            tx_used = max(156, 15) = 156

STEP 7: Dehaze Recovery (per-channel)
   For each channel c in {R, G, B}:
     temp = ((src[c] - A[c]) << 8) + A[c] × tx_used
     out[c] = floor(temp / tx_used)
   
   Example for center (R13=120, A_R=190):
     temp = ((120 - 190) << 8) + 190 × 156
          = (-70 << 8) + 29640
          = -17920 + 29640 = 11720
     out_R = floor(11720 / 156) ≈ 75

OUTPUT:
   (R_out, G_out, B_out) = (75, ..., ...) [Dehazed RGB]
```

---

## Quick Lookup: Module → File → Key Constants

| Module | Script | Entry Function | Key Constants | Output |
|--------|--------|-----------------|----------------|--------|
| **Dark Channel** | dark_channel.py | `compute_dark_channel_pixel(r,g,b)` | None | min(R,G,B) |
| **Grayscale** | grayscale.py | `rgb_to_gray_fixed_point(r,g,b,mode)` | mode (0/1/2) | 8-bit gray |
| **Atmospheric Light** | atmospheric_light.py | `estimate_atmospheric_light_pixel(r,g,b,dark)` | DARK_THRESHOLD=128 | (A_R, A_G, A_B) |
| **Sky Recognition** | sky_recognition.py | `sky_recognition_pixel(gray,dark,A0,use_dark)` | A0=150, USE_DARK=0 | 1-bit sky |
| **Transmission** | estimate_transmission.py | `estimate_transmission_pixel(r,g,b,sky,A_r,A_g,A_b)` | OMEGA_Q8=243, T_MIN=26, T_SKY=255 | 8-bit t |
| **ADC (Pixel Dist)** | adc_subblock_hexgen.py | `hw_pixel_distance(gray[25])` | Path generation | 25×9-bit dp |
| **ADC (Path Len)** | adc_subblock_hexgen.py | `hw_path_length(dp[25],lambda_q8)` | lambda_q8=51, SPATIAL_TABLE | 25×10-bit dl |
| **ADC (RLimit)** | adc_subblock_hexgen.py | `hw_rlimit(dl[25])` | Divide by 25 via ×41>>10 | 10-bit rlimit |
| **ADC (ASE+Min)** | adc_subblock_hexgen.py | `hw_ase_masked_min(rlimit,dl,mc)` | Mask generation | 8-bit adc |
| **T Compute** | t_compute_fuse_sw.py | `tx_get(dark,A)` + `haze_remove_channel(src,A,tx)` | MODIFICATION=255, TX_MIN=15 | 8-bit tx + 8-bit out |
| **LUT Gen** | gen_invA_lut_q16.py | `gen_lut()` → `emit_sv()` | Q16 format | 256×24-bit SV array |
| **Bank Test** | bank_pingpong.py | `generate_write_data()` | IMG_WIDTH=4, HEIGHT=4 | Swap verification |

---

## Bit-Width Tracking Through Pipeline

```
Input Frame:
  RGB:          3 × 8-bit = 24-bit per pixel
  
After Dark Channel:
  dark:         8-bit per pixel
  
After Grayscale:
  gray:         8-bit per pixel
  
Atmospheric Light:
  A_R, A_G, A_B: 3 × 8-bit = 24-bit
  
After Transmission Estimation:
  t:            8-bit per pixel (clamped to [26, 255])
  
ADC Sub-blocks:
  pixel_distance: 25 × 9-bit (max ~300 per path)
  path_length:    25 × 10-bit (max ~2000 per position)
  rlimit:         10-bit (mean of path_lengths)
  ase_masked_min: 8-bit (minimum of selected t values)
  
Final Recovery:
  tx_raw:       8-bit
  tx_used:      8-bit (clamped to T_MIN)
  Output RGB:   3 × 8-bit per pixel = 24-bit
  
Hex Files:
  Input word:   1-3 bytes depending on module
  Output word:  1-3 bytes depending on module
```

---

## Test Pattern Organization

### Generation Commands (Recommended Order)

```bash
# Phase 1: Individual modules
python dark_channel.py              # ~21 patterns
python grayscale.py                 # ~48 outputs (16 cases × 3 modes)
python atmospheric_light.py         # ~20 patterns
python sky_recognition.py           # ~20 patterns × 2 modes
python estimate_transmission.py     # ~20 patterns

# Phase 2: ADC sub-blocks
python adc_sub_block.py             # Traces all 20 cases
python adc_subblock_hexgen.py       # Separate hex per sub-block
python adc_estimation_top.py        # Full ADC pipeline

# Phase 3: Recovery & utility
python t_compute_fuse_sw.py         # ~20 patterns → outputs
python bank_pingpong.py             # Memory test (16 pixels)
python gen_invA_lut_q16.py          # RecIP LUT (SV output)

# Phase 4: Integration
python purple_block_integration.py  # 2-pass architecture (16 pixels)
python haze_removal_top_sw.py       # E2E complete test (~20 cases)
```

### Output Directory Structure
```
09_pattern/
├── pattern_dark_channel.hex
├── pattern_grayscale.hex
├── pattern_atmospheric_light.hex
├── pattern_sky_*.hex (4 files)
├── rgb.hex, sky.hex
├── pattern_bank_wr_data.hex
├── pattern_haze_removal_top_input.hex
├── pattern_haze_removal_top_rgb5x5.hex
├── adc_case_XX_gray.hex (×20)
├── adc_case_XX_mc.hex (×20)
├── t_compute_fuse_input.hex
└── invA_lut_q16.sv

07_golden_output/
├── dark_channel_report.txt
├── golden_dark_channel.hex
├── grayscale_report.txt
├── golden_grayscale.hex
├── atmospheric_light_report.txt
├── golden_atmospheric_light.hex
├── sky_recognition_report.txt
├── golden_sky_recognition.hex
├── golden_sky_bw.hex
├── estimate_transmission_report.txt
├── t_golden.hex
├── adc_case_XX_golden.txt (×20)
├── adc_summary.csv
├── golden_ase_adc.hex
├── t_compute_fuse_cases.csv
├── t_compute_fuse_case_table.md
├── t_compute_fuse_golden.hex
├── golden_bank_rd_data.hex
├── golden_bank_position.txt
├── bank_pingpong_report.txt
├── haze_removal_top_cases.csv
└── golden_haze_removal_top*.hex (×5)
```

---

## Common Issues & Solutions

| Problem | Check | Solution |
|---------|-------|----------|
| Pattern/golden mismatch | Bit-width (8-bit vs 16-bit?) | Verify input range, ensure integer arithmetic |
| Transmission values out of range | T_MIN/T_MAX clamping | Check T_MIN=26, T_SKY=255 |
| ADC vastly different from coarse tx | Path generation order | Verify diagonal-first rule, spatial table |
| Sky detection inverted | USE_DARK flag | Check USE_DARK=0 (default: gray) |
| Grayscale rounding errors | Rounding mode mismatch | Use mode=2 (round-to-even) |
| Atmospheric light wrong | Tie-break logic | Check intensity = R+G+B |

---

## Parameter Tuning Guide

### For Stronger Dehaze
```python
MODIFICATION_VALUE = 255       # (currently 255, already strong)
TX_MIN = 15                     # (lower = stronger, currently 15)
OMEGA_Q8 = 200                  # (lower = stronger, currently 243)
```

### For Lighter/Softer Dehaze
```python
MODIFICATION_VALUE = 200        # Reduce from 255
TX_MIN = 50                      # Increase from 15
OMEGA_Q8 = 245                   # Increase from 243 (toward 1.0)
```

### For Better Sky Handling
```python
USE_SKY = 1                      # Enable sky override
A0 = 160                         # Increase from 150 (more sky detection)
T_SKY = 255                      # Keep at max transmission
```

### For Better Haze Estimation
```python
LAMBDA = 0.3                     # Increase from 0.2 (context weighting)
DARK_THRESHOLD = 120             # Lower from 128 (easier A estimation)
```

---

## References

- **Full Analysis**: See `ANALYSIS.md`
- **User Guide**: See `README.md`
- **Original Algorithm**: He et al., "Single Image Haze Removal Using Dark Channel Prior", CVPR 2009

---

**Quick Reference v1.0**  
*Last Updated: March 2026*  
*Framework: Dark Channel Prior Haze Removal with Adaptive Dark Channel*

