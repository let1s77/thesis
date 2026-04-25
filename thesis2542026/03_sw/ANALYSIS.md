# Dark Channel Prior Haze Removal - Python Reference Model Analysis

## Executive Summary

This directory contains a complete Python reference implementation of the Dark Channel Prior haze removal algorithm from the paper "Single Image Haze Removal Using Dark Channel Prior" (He et al., CVPR 2009). The implementation is designed to match hardware (RTL) bit-exactly and is used for:

- **Golden file generation** for hardware testbenches
- **Algorithm validation** before RTL implementation
- **Hardware-software co-verification** with known correct outputs
- **Individual sub-block testing** with comprehensive test vectors

---

## Overall Workflow Pipeline

### High-Level E2E Flow

```
Input Image (5x5 RGB Frame)
    ↓
[Stage 1: Dark Channel & Analysis]
    ├─→ dark_channel.py: compute min(R,G,B) per pixel
    ├─→ grayscale.py: compute weighted gray = 5R + 9G + 2B (fixed-point)
    ├─→ atmospheric_light.py: find brightest dark pixel → Atmospheric Light A
    └─→ sky_recognition.py: identify sky pixels (gray/dark > threshold)
    ↓
[Stage 2: Coarse Transmission Estimation]
    ├─→ estimate_transmission.py:
    │   ├─ Normalize each channel: norm = (pixel × inv_A_q16) >> 16
    │   ├─ Find minimum normalized: min_norm = min(norm_r, norm_g, norm_b)
    │   ├─ Apply omega: t = 255 - ((OMEGA_Q8 × min_norm) >> 8)
    │   └─ Clamp: t = max(t, T_MIN)
    ↓
[Stage 3: ADC Estimation (Adaptive Dark Channel)]
    ├─→ adc_estimation_top.py runs 4 sub-blocks in sequence:
    │   ├─ pixel_distance.py: |gray(a) - gray(b)| for path edges
    │   ├─ path_length.py: L = spatial_distance + λ × pixel_distance
    │   ├─ rlimit.py: mean(path_lengths) → radius limit
    │   └─ ase_masked_min.py: adaptive spatial extent → minimum within mask
    ↓
[Stage 4: Recovery (Dehazed Output)]
    └─→ t_compute_fuse_sw.py:
        ├─ Compute final transmission: tx = 255 - (dark × MODIFICATION) / A
        ├─ Apply dehaze formula per channel: out = (src - A) / tx + A
        └─ Output RGB dehazed pixel
```

### Architecture Modes

**2-Pass Architecture** (purple_block_integration.py):
- **Pass 1**: Frame → dark_channel → atmospheric_light → latch A
- **Pass 2**: Frame → dark_channel → grayscale → sky_recognition → estimate_transmission (using A) → bank write

**Single-Frame Processing** (haze_removal_top_sw.py):
- 5x5 window with center pixel focus
- All stages (0-3) in one framework for regression testing
- Generates test cases covering dark channel, atmospheric light, transmission, and dehaze output

---

## Module-by-Module Analysis

### 1. **dark_channel.py** — Dark Channel Prior Foundation

**Purpose**: Compute dark channel prior for haze detection  
**Algorithm Reference**: J^dark(x) = min_{C∈{R,G,B}} ( min_{Y∈Ω(x)} J^C(Y) )

#### Entry Point
```python
def compute_dark_channel_pixel(r: int, g: int, b: int) -> int:
    return min(r, g, b)
```

#### Input/Output
- **Input**: RGB triple (0-255 each)
- **Output**: 8-bit dark channel value (0-255)
- **Computational Complexity**: O(1) per pixel

#### Algorithm Steps
1. Compare all three channels
2. Return minimum value
3. For full image: apply local min-filter with patch size (typically 15×15)

#### Hardware Implementation Details
- **Latency**: 1 cycle
- **Throughput**: 1 pixel/cycle
- **Precision**: 8-bit integer arithmetic

#### Test Patterns (21 cases)
- **White (255,255,255)** → 255 (no info)
- **Black (0,0,0)** → 0
- **Hazy scenes** (240,240,116)→116, (150,160,140)→140
- **Natural scenes** (97,204,98)→97, (181,71,16)→16
- **Pure colors** R, G, B channels → their minimum

#### File Generation
```
09_pattern/pattern_dark_channel.hex    → 24-bit RGB inputs
07_golden_output/golden_dark_channel.hex → 8-bit dark outputs
07_golden_output/dark_channel_report.txt → detailed analysis
```

---

### 2. **grayscale.py** — RGB to Grayscale Conversion

**Purpose**: Convert RGB to grayscale using fixed-point Q8.4 arithmetic  
**Formula**: `Gray = 5R/16 + 9G/16 + 2B/16` (coefficients optimized for human perception)

#### Entry Point
```python
def rgb_to_gray_fixed_point(r: int, g: int, b: int, mode: int = 2) -> tuple[int, float]:
    # mode: 0=round_up, 1=round_down, 2=round_to_even (banker's rounding)
```

#### Input/Output
- **Input**: RGB triple (8-bit each)
- **Output**: Grayscale 8-bit value + floating-point reference
- **Modes**: 3 rounding strategies for hardware trade-offs

#### Algorithm Steps
1. Shift RGB left by 4 bits (Q8.4 fixed-point)
2. Apply fractional coefficients:
   - r_scaled = R × (5/16) = (R >> 2) + (R >> 4)
   - g_scaled = G × (9/16) = (G >> 1) + (G >> 4)
   - b_scaled = B × (2/16) = B >> 3
3. Sum: sum = r_scaled + g_scaled + b_scaled
4. Extract integer [11:4] and fraction [3:0]
5. Apply rounding based on mode

#### Hardware Parameters
- **Rounding Latency**: Mode 0/1 = 1 cycle, Mode 2 = 2 cycles (comparator)
- **Data Width**: 8-bit input, 8-bit output
- **Precision Loss**: < 1 LSB with round-to-even

#### Test Patterns (16 cases)
- **White, Black, Gray levels** (0%, 25%, 50%, 75%)
- **Pure colors** R(255,0,0)→40, G(0,255,0)→183, B(0,0,255)→33
- **Natural scenes** Haze(240,240,116)→176, Veg(97,204,98)→166

#### File Generation
```
09_pattern/pattern_grayscale.hex     → 24-bit RGB pattern
07_golden_output/golden_grayscale.hex → 8-bit gray (3×16 = 48 entries for 3 modes)
07_golden_output/grayscale_report.txt → per-mode comparison
```

---

### 3. **atmospheric_light.py** — Atmospheric Light Estimation

**Purpose**: Identify pixel with highest dark channel value as atmospheric light source  
**Algorithm**: Select top 0.1% brightest pixels in dark channel, then pick highest RGB intensity among them

#### Entry Point
```python
def estimate_atmospheric_light_pixel(r: int, g: int, b: int, dark_value: int) -> tuple[int, int, int]:
    if dark_value > 128:
        return r, g, b  # Likely haze → use RGB as A
    else:
        return (max_val if r==max_val else r, ...)  # Fallback
```

#### Input/Output
- **Input**: RGB triple + dark_channel value (all 8-bit)
- **Output**: (A_R, A_G, A_B) atmospheric light components (each 8-bit)
- **Non-linear**: Depends on dark_channel threshold

#### Algorithm Steps (Frame Level)
1. Flatten dark channel map
2. Sort indices by dark value
3. Extract top 0.1% brightest pixels (by dark channel)
4. Among those, find pixel with max RGB intensity: `R + G + B`
5. Return that pixel's RGB as atmospheric light

#### Hardware Considerations
- **Frame Latency**: ~25-50 cycles (25×25 image scan)
- **Window Size**: User-configurable, default 25 pixels for single-pixel mode
- **Threshold**: DARK_THRESHOLD = 128 (configurable for haze density)

#### Test Patterns (20 cases)
- **High haze** (255,255,255) d=255 → 255,255,255
- **Medium haze** (220,230,235) d=220 → 220,230,235
- **Low haze** (60,70,75) d=60 → variable
- **Color-biased** (255,200,180), (180,200,255) → different atmospheres

#### File Generation
```
09_pattern/pattern_atmospheric_light.hex → 32-bit (dark[31:24] | RGB[23:0])
07_golden_output/golden_atmospheric_light.hex → 24-bit (A_B[23:16] | A_G[15:8] | A_R[7:0])
07_golden_output/atmospheric_light_report.txt → threshold + haze classification
```

---

### 4. **sky_recognition.py** — Sky/Non-Sky Pixel Classification

**Purpose**: Identify sky pixels to apply special transmission handling  
**Algorithm**: Compare grayscale (or dark_ch) against threshold A0

#### Entry Point
```python
def sky_recognition_pixel(gray: int, dark_ch: int, A0: int = 150, 
                          use_dark: int = 0) -> tuple[int, int]:
    src_val = dark_ch if use_dark else gray
    sky = 1 if src_val > A0 else 0
    sky_bw = 0xFF if sky else 0x00
    return sky, sky_bw
```

#### Input/Output
- **Input**: 
  - Grayscale value (8-bit)
  - Dark channel value (8-bit)
  - A0 threshold (8-bit, default 150)
  - use_dark flag (1-bit, 0=gray, 1=dark_ch)
- **Output**: 
  - sky flag (1-bit binary)
  - sky_bw (8-bit: 0xFF or 0x00)

#### Algorithm Steps
1. Select source: src_val = gray OR dark_ch (based on use_dark)
2. Compare with threshold: sky = (src_val > A0) ? 1 : 0
3. Convert to 8-bit: sky_bw = sky ? 0xFF : 0x00

#### Hardware Parameters
- **Latency**: 1 cycle (combinational logic)
- **Area**: Minimal (comparator + mux)
- **Configurable A0**: Default 150 for typical scenes

#### Test Patterns (20 cases, both modes)
- **use_dark=0** (gray comparison):
  - Gray < 150 → non-sky: (50,30), (100,60), (128,100)
  - Gray = 150 → non-sky (not >)
  - Gray > 150 → sky: (180,120), (200,160), (255,200)
- **use_dark=1** (dark_ch comparison):
  - dark_ch < 150 → non-sky: (200,0), (100,149)
  - dark_ch > 150 → sky: (220,151), (50,255)

#### File Generation
```
09_pattern/pattern_sky_gray.hex      → 8-bit grayscale values
09_pattern/pattern_sky_darkch.hex    → 8-bit dark channel values
09_pattern/pattern_sky_usedark.hex   → 1-bit use_dark flag
09_pattern/pattern_sky_a0.hex        → 8-bit A0 threshold
07_golden_output/golden_sky_recognition.hex → 1-bit sky output
07_golden_output/golden_sky_bw.hex   → 8-bit sky_bw output
07_golden_output/sky_recognition_report.txt → boundary analysis
```

---

### 5. **estimate_transmission.py** — Coarse Transmission Estimation

**Purpose**: Compute atmospheric transmission map using dark channel  
**Key Equation**: `t = max(255 - (ω × min_norm), T_MIN)` where ω ≈ 0.95

#### Entry Point
```python
def estimate_transmission_pixel(r: int, g: int, b: int, sky: int = 0,
                                A_r: int = 200, A_g: int = 200, A_b: int = 200) -> tuple[int, dict]:
    # Sky override: if sky flag, return T_SKY=255
    # Else: normalize channels, find min, apply omega, clamp to T_MIN=26
```

#### Input/Output
- **Input**: 
  - RGB pixel (3×8-bit)
  - Sky flag (1-bit)
  - A_r, A_g, A_b atmosphere per-channel (3×8-bit)
- **Output**: Transmission value (8-bit, 0-255)
- **Debug**: Intermediate normalized values

#### Algorithm Steps

1. **Channel Normalization** (per channel c ∈ {R,G,B}):
   ```
   inv_A_c_q16 = INV_LUT[A_c]  ; Q16 reciprocal: floor((255 << 16) / A_c)
   mul_q = pixel_c × inv_A_c_q16
   q16 = (mul_q >> 16) & 0xFFFF
   norm_c = saturate(q16, 8-bit) = (q16 >> 8) ? 0xFF : (q16 & 0xFF)
   ```

2. **Minimum Normalized Channel**:
   ```
   min_norm = min(norm_r, norm_g, norm_b)
   ```

3. **Omega Scaling** (Q0.8 fixed-point, OMEGA_Q8=243):
   ```
   x_scaled = (OMEGA_Q8 × min_norm) >> 8
   t_raw = 255 - (x_scaled & 0xFF)
   ```

4. **Clamp to Minimum Transmission**:
   ```
   t_final = max(t_raw, T_MIN) ; T_MIN=26 (typical)
   ```

5. **Sky Override** (optional):
   ```
   if (USE_SKY && sky) then t_final = T_SKY = 255
   ```

#### Hardware Parameters
- **Reciprocal LUT**: Pre-computed 256×24-bit Q16 values
- **Latency**: 3 cycles (normalization pipeline)
- **OMEGA_Q8**: 0xF3 (243) ≈ 0.95 in Q0.8 format
- **T_MIN**: 26 (prevents excessive enhancement)
- **T_SKY**: 255 (max transmission for sky)

#### Test Patterns (20 cases)
- **Corner cases**: Black (0,0,0), White (255,255,255), Pure R/G/B
- **Gray levels**: 50, 100, 150, 200
- **Hazy pixels** (low contrast): (180,190,195), (170,175,180)
- **Clear pixels** (high contrast): (30,50,70), (80,60,40), (40,80,120)

#### File Generation
```
09_pattern/rgb.hex         → 24-bit RGB inputs
09_pattern/sky.hex         → 1-bit sky flags
07_golden_output/t_golden.hex → 8-bit transmission outputs
07_golden_output/estimate_transmission_report.txt → per-case breakdown
```

---

### 6. **adc_estimation_top.py** — Adaptive Dark Channel (ADC) Estimation

**Purpose**: Refine transmission using spatial filtering via adaptive dark channel  
**Strategy**: Build distance paths from center, weight by pixel gradients, compute adaptive mask

#### Entry Point
```python
def adc_estimation_top(gray5x5: List[int], mc5x5: List[int], lambd: float = 0.2) -> dict:
    # gray5x5: 25-element flattened 5×5 window
    # mc5x5: 25-element medium-domain (typically transmission map)
    # Returns: {pixel_distances, path_lengths, rlimit, ase_mask, adc}
```

#### Sub-Blocks

##### 6a. **pixel_distance** Sub-Block
- **Input**: gray5x5 (25×8-bit)
- **Output**: dp[25] where each dp[i] = sum of |gray differences| along path from center to i
- **Algorithm**: 
  ```
  For each position p:
    path = generate_path_to(p)  ; diagonal first, then V/H
    dp[p] = Σ |gray[a] - gray[b]| for consecutive (a,b) in path
  ```
- **Path Generation**: Diagonal movement prioritized (move to (±1,±1) first), then straight

##### 6b. **path_length** Sub-Block
- **Input**: dp[25] (25×9-bit), lambda_q8=51
- **Output**: dl[25] where each dl[i] = spatial_dist + (lambda_q8 × dp[i]) >> 8
- **Algorithm**:
  ```
  For each position p:
    spatial[p] = SPATIAL_TABLE[p]  ; precomputed distance (0-4)
    prod = lambda_q8 × dp[p]
    lambda_dp = prod >> 8
    dl[p] = spatial[p] + lambda_dp
  ```
- **Spatial Table**: Distance from center (0 at (2,2), 1 for V/H neighbors, 2 for diagonal, etc.)

##### 6c. **rlimit** Sub-Block
- **Input**: dl[25] (25×10-bit)
- **Output**: rlimit (10-bit), computed as mean(dl) scaled by 41/1024
- **Algorithm**:
  ```
  sum_dl = Σ dl[i] for all i
  rlimit = (sum_dl × 41) >> 10  ; integer approximation of /25
  ```
- **Purpose**: Dynamic threshold for adaptive mask

##### 6d. **ase_masked_min** Sub-Block
- **Input**: 
  - rlimit (10-bit threshold)
  - dl[25] (25×10-bit distances)
  - mc5x5 (25×8-bit data to filter, e.g., transmission)
- **Output**: adc (8-bit minimum value within adaptive spatial extent)
- **Algorithm**:
  ```
  ase_mask[i] = (i == CENTER) ? 1 : (dl[i] <= rlimit) ? 1 : 0
  adc = min( mc5x5[i] for all i where ase_mask[i] == 1 )
  ```
- **Purpose**: Adaptive spatial extent + minimum filter

#### Hardware Pipeline
- **Stages**: 4 sequential sub-blocks
- **Total Latency**: ~15-20 cycles (includes memory access)
- **Window Size**: Fixed 5×5

#### Test Patterns (20 cases, 5×5 windows)

1. **flat_uniform**: gray=100×25, mc=50×25 → adc=50
2. **center_dark_flat**: gray=120×25 with center=120, mc varies → mask includes center
3. **horizontal_edge**: Two regions separated by edge → path lengths vary
4. **vertical_edge**: Top vs bottom → directional filtering
5. **diag_edge_main**: Gradient along diagonal → distance-based masking
6. **cross_structure**: Cross pattern → multiple path endpoints
7. **center_bright_island**: Bright center surrounded by dark → large gradients narrow mask
8. **noisy_small_variation**: Small random variations → tight mask
9. **ramp_horizontal/vertical**: Linear gradients → monotonic path lengths
10. **checkerboard_soft**: Alternating pattern → complex gradients
11. **corner_dark_***: Corners darker/brighter → validation of edge pixels
12. **ring_structure**: Ring within field → annular adaptive extent
13. **left_right_two_regions**: Sharp vertical boundary → mask adaptation
14. **top_bottom_two_regions**: Sharp horizontal boundary → similar
15-20. **center_valley, random_like_***: Various natural patterns

#### File Generation
```
09_pattern/adc_case_XX_gray.hex    → 25×8-bit gray patterns
09_pattern/adc_case_XX_mc.hex      → 25×8-bit mc patterns
07_golden_output/adc_case_XX_golden.txt → all intermediate results + final ADC
09_pattern/adc_summary.csv         → summary of all 20 cases
```

---

### 7. **t_compute_fuse_sw.py** — Transmission Computation & Dehaze Recovery

**Purpose**: Final transmission refinement using ADC dark channel, then recover dehazed RGB

#### Entry Point
```python
def run_case(c: Case) -> dict:
    tx_raw = tx_get(c.dark, c.A)       # 255 - (dark × MODIFICATION) / A
    tx_clamped = max(tx_raw, TX_MIN)   # Clamp to minimum
    out_r = haze_remove_channel(c.src_r, c.A, tx_raw)
    out_g = haze_remove_channel(c.src_g, c.A, tx_raw)
    out_b = haze_remove_channel(c.src_b, c.A, tx_raw)
    return {case_id, input_hex (48-bit), golden_hex (40-bit), ...}
```

#### Input/Output
- **Input**:
  - dark (8-bit ADC dark value from previous stage)
  - A (8-bit atmospheric light)
  - src_r, src_g, src_b (3×8-bit source pixel RGB)
  - case_id (8-bit test case identifier)
- **Output**:
  - tx_raw (8-bit coarse transmission)
  - tx_used (8-bit clamped transmission)
  - out_r, out_g, out_b (3×8-bit dehazed RGB)

#### Algorithm Steps

1. **Transmission Computation**:
   ```
   modify_A = dark × MODIFICATION_VALUE  ; MODIFICATION_VALUE=255 (or 243)
   tx_raw = 255 - floor(modify_A / A)
   tx_raw = tx_raw & 0xFF  ; clamp to 8-bit
   ```

2. **Transmission Clamping**:
   ```
   tx_value = max(tx_raw, TX_MIN)  ; TX_MIN=15 (stronger dehaze)
   ```

3. **Per-Channel Dehaze Recovery**:
   ```
   For each channel (R, G, B):
     temp = ((src - A) << 8) + A × tx_value
     out = floor(temp / tx_value)
     out = out & 0xFF  ; clamp to 8-bit
   ```
   - **Formula Derivation**: Original haze model I = J×t + A×(1-t)
   - **Inverse**: J = (I - A) / t + A

#### Hardware Parameters
- **MODIFICATION_VALUE**: 255 (1.0 × 256) for standard dehaze, 243 for softer effect
- **TX_MIN**: 15-26 (trade-off between contrast and noise)
- **Bit Width**: Internal 9-bit arithmetic for temp, 8-bit output

#### Test Patterns (20 cases)

| Case ID | Name | Dark | A | RGB | Purpose |
|---------|------|------|----|-----|---------|
| 0 | clear_scene_nominal | 20 | 220 | (180,170,160) | Baseline |
| 1 | light_haze_midtones | 60 | 210 | (150,140,130) | Low haze |
| 2 | moderate_haze | 100 | 200 | (160,145,120) | Medium case |
| 3 | heavy_haze_low_tx | 170 | 190 | (180,160,140) | Low transmission |
| 4 | very_dark_pixel | 15 | 200 | (20,18,16) | Low intensity |
| 5 | bright_pixel_close_to_A | 180 | 220 | (215,210,205) | Near atmosphere |
| 6-8 | color_dominant (R/G/B) | 90/95/90 | 205 | Various | Per-channel emphasis |
| 9 | dark_equals_A | 180 | 180 | (150,145,140) | Division boundary |
| 10 | dark_near_A | 199 | 200 | (180,170,160) | Limit case |
| 11 | minimum_tx_clamp_case | 210 | 220 | (190,180,170) | TX_MIN active |
| 12 | low_A_value | 30 | 64 | (90,85,80) | Division challenge |
| 13 | high_A_value | 40 | 250 | (200,195,190) | Large A |
| 14 | flat_gray | 100 | 180 | (128,128,128) | Neutral |
| 15-17 | src_below/equal/above_A | 80/70/70 | 160/150/150 | Various | Boundary cases |
| 18 | near_black_haze | 10 | 120 | (8,8,8) | Nearly invisible |
| 19 | near_white_haze | 180 | 230 | (250,248,246) | Very bright |

#### File Generation
```
09_pattern/t_compute_fuse_input.hex     → 48-bit (dark[47:40] | A[39:32] | RGB[31:8] | ID[7:0])
07_golden_output/t_compute_fuse_golden.hex → 40-bit (tx_raw[39:32] | RGB_out[31:8] | ID[7:0])
07_golden_output/t_compute_fuse_cases.csv → full table with hex, values, names
07_golden_output/t_compute_fuse_case_table.md → markdown reference
```

---

### 8. **bank_pingpong.py** — Memory Bank Ping-Pong Verification

**Purpose**: Test dual-port memory swap mechanism for streaming architecture

#### Entry Point
```python
def generate_write_data() -> List[int]:
    # Generate deterministic test data: (addr × 13 + 7) & 0xFF
```

#### Input/Output
- **Input**: Linear addresses (0-15 for 4×4 image)
- **Output**: Position info (row, col, boundary flags)
- **Data Width**: 8-bit per pixel

#### Algorithm
1. **Write Phase**: Stream write_data to BANK_A at addresses 0-15
2. **Swap Phase**: Toggle bank pointers (BANK_A ↔ BANK_B)
3. **Read Phase**: Stream read from BANK_B, should get back write_data in order
4. **Verify**: Compare read_data == write_data

#### Position Computation
```python
row = addr // IMG_WIDTH
col = addr % IMG_WIDTH
at_top = (row == 0)
at_bottom = (row == IMG_HEIGHT - 1)
at_left = (col == 0)
at_right = (col == IMG_WIDTH - 1)
```

#### Test Image
- **Size**: 4×4 = 16 pixels
- **Pattern**: Deterministic (addr × 13 + 7) & 0xFF
- **Purpose**: Verify ping-pong doesn't corrupt order or values

#### File Generation
```
09_pattern/pattern_bank_wr_data.hex    → 16×8-bit write pattern
07_golden_output/golden_bank_rd_data.hex → 16×8-bit expected readback
07_golden_output/golden_bank_position.txt → boundary flags per address
07_golden_output/bank_pingpong_report.txt → detailed flow description
```

---

### 9. **adc_subblock_hexgen.py** — ADC Sub-Block Hex File Generation

**Purpose**: Generate $readmemh-compatible hex files for each ADC sub-block testbench independently

#### Reuses
- Same spatial table, path generation, and 20 testcases as adc_sub_block.py
- Hardware-matching integer arithmetic (no floating-point)

#### Output Files

**For pixel_distance:**
```
pattern_pixel_distance.hex   → 25×8-bit gray per case
golden_pixel_distance.hex    → 25×9-bit dp (edge sum) per case
```

**For path_length:**
```
pattern_path_length.hex      → 25×9-bit dp per case
golden_path_length.hex       → 25×10-bit dl per case
```

**For rlimit:**
```
pattern_rlimit.hex           → 25×10-bit dl per case
golden_rlimit.hex            → 1×10-bit rlimit per case
golden_rlimit_dl.hex         → 25×10-bit dl pass-through per case
```

**For ASE mask + min filter:**
```
pattern_ase_rlimit.hex       → 1×10-bit rlimit per case
pattern_ase_dl.hex           → 25×10-bit dl per case
pattern_ase_mc.hex           → 25×8-bit MC (input to filter) per case
golden_ase_adc.hex           → 1×8-bit ADC (filtered min) per case
```

---

### 10. **adc_sub_block.py** — Individual ADC Sub-Block Testcases

**Purpose**: Provide detailed per-sub-block test vectors and reference calculations

#### Features
- **20 carefully crafted test cases** with varied spatial patterns
- **Path generation logic** (diagonal-first for hardware efficiency)
- **Fixed-point arithmetic** matching RTL (no floating-point)
- **Configurable lambda** parameter (default 0.2 ≈ 51 in Q8 format)

#### Test Case Categories

1. **Uniform Patterns**
   - flat_uniform: All constant → rlimit=0, all pixels in mask
   
2. **Center Variations**
   - center_dark_flat: Center different → path lengths vary
   - center_bright_island: Bright center → tight mask
   - center_valley: Valley center → larger mask
   
3. **Edge Structures**
   - horizontal_edge: Top vs bottom boundary
   - vertical_edge: Left vs right boundary
   - diag_edge_main: Main diagonal (↘)
   - diag_edge_anti: Anti-diagonal (↙)
   
4. **Pattern Recognition**
   - cross_structure: + pattern center
   - ring_structure: Concentric rings
   - checkerboard_soft: Alternating pattern
   - left_right_two_regions: Sharp vertical split
   - top_bottom_two_regions: Sharp horizontal split
   
5. **Gradients**
   - ramp_horizontal: Linear gradient left→right
   - ramp_vertical: Linear gradient top→bottom
   
6. **Corners**
   - corner_dark_tl: Top-left darker
   - corner_dark_br: Bottom-right darker
   
7. **Noise**
   - noisy_small_variation: ±3 variations
   
8. **Complex Scenes**
   - random_like_1, random_like_2: Realistic variation

---

### 11. **adc_estimation_top.py** — Full ADC Pipeline (Top Module)

**Purpose**: Complete reference model for ADC estimation sub-blocks operating in sequence

#### Main Flow
```python
def adc_estimation_top(gray5x5: List[int], mc5x5: List[int], lambd: float = 0.2) -> dict:
    dp_dict = pixel_distance_calc(gray5x5, PATHS)
    lengths, meta = path_length_calc(dp_dict, lambd)
    rlimit = rlimit_calc(lengths)
    ase_mask = ase_mask_gen(lengths, rlimit)
    adc = adaptive_min_filter(mc5x5, ase_mask)
```

#### Output Structure
```python
{
    "pixel_distances": dp_dict,     # per-position edge sums
    "path_lengths": lengths,        # per-position weighted distance
    "path_meta": meta,              # detailed (d8, dp, term) per edge
    "rlimit": rlimit,               # mean threshold
    "ase_mask": ase_mask,           # 25-bit mask (1=in extent, 0=out)
    "adc": adc,                     # minimum within extent
}
```

---

### 12. **purple_block_integration.py** — E2E 2-Pass Pipeline

**Purpose**: Complete integration test of dark_channel → atmospheric_light → grayscale → sky → transmission stages

#### Test Image
- **Size**: 4×4 = 16 pixels
- **Design**: Exercises sky vs non-sky, multiple haze levels, tie-break logic

#### 2-Pass Architecture
```
Pass 1:
  Frame → dark_channel → atmospheric_light → latch A_R, A_G, A_B

Pass 2:
  Frame → dark_channel → grayscale → sky_recognition → estimate_transmission
          (using A from Pass 1) → output tx map
```

#### Pipeline Steps
1. Compute dark channel for all 16 pixels
2. Find atmospheric light (max dark with intensity tie-break)
3. Re-scan for grayscale, sky detection, transmission estimation
4. Generate output hex files for testbench

#### File Generation
```
Pattern files: gray, rgb, sky, transmission per pixel
Golden files: A (RGB), sky (1-bit), tx (8-bit per pixel)
Report: Summary of all pipeline stages
```

---

### 13. **gen_invA_lut_q16.py** — Reciprocal LUT Generator

**Purpose**: Pre-compute fixed-point reciprocals for fast channel normalization in transmission estimation

#### Algorithm
```python
for A in range(256):
    inv_A_q16[A] = floor((255 << 16) / A)  # Fixed-point Q16 reciprocal
inv_A_q16[0] = 0xFFFFFF  # Handle divide-by-zero
```

#### Output Format
- **Array**: 256 entries × 24-bit (Q16.0 format)
- **Range**: 0xFFFFFF (A=1) down to 0x0100 (A=255)
- **Usage**: `norm = (pixel × inv_A_q16[A]) >> 16`

#### File Generation
```
09_pattern/invA_lut_q16.sv → SystemVerilog localparam array
```

---

### 14. **haze_removal_top_sw.py** — Complete E2E Integration Test

**Purpose**: Master reference model combining ALL stages: dark_channel → atmospheric_light → grayscale → sky_recognition → estimate_transmission → ADC → dehaze recovery

#### Entry Point
```python
def run_case(c: HazeTopCase) -> dict:
    # Stage 1: Dark channel + Atmospheric light
    dark_list = [compute_dark_channel(r, g, b) for r, g, b in c.rgb5x5]
    gray_list = [compute_grayscale(r, g, b) for r, g, b in c.rgb5x5]
    a_r, a_g, a_b = atmospheric_light_frame(c.rgb5x5)
    
    # Stage 2: Sky recognition + Coarse transmission
    sky_list, tx_list = [], []
    for r, g, b in c.rgb5x5:
        sky = sky_recognition_pixel(gray_list[i], dark_list[i])
        tx = estimate_transmission_pixel(r, g, b, sky, a_r, a_g, a_b)
        sky_list.append(sky)
        tx_list.append(tx)
    
    # Stage 3: ADC estimation
    dp = hw_pixel_distance(tx_list)
    dl = hw_path_length(dp, lambda_q8=51)
    rlimit = hw_rlimit(dl)
    adc_dark = hw_ase_masked_min(rlimit, dl, tx_list)
    
    # Stage 4: Recovery (t_compute_fuse)
    tx_raw = tx_get(adc_dark, a_r)
    tx_used = max(tx_raw, T_MIN)
    out_r = haze_remove_channel(center_r, a_r, tx_raw)
    out_g = haze_remove_channel(center_g, a_r, tx_raw)
    out_b = haze_remove_channel(center_b, a_r, tx_raw)
```

#### Input/Output
- **Input**: 5×5 RGB frame (25 pixels × 3 channels)
- **Output**: 
  - Intermediate: A (RGB), dark_ch (25), gray (25), sky (25), tx (25)
  - Final: Dehazed RGB (center pixel only)

#### Constants
- A0=150, USE_DARK=0, USE_SKY=1, T_SKY=255
- OMEGA_Q8=243, T_MIN=26
- LAMBDA=0.2 (λ in ADC)
- MODIFICATION_VALUE=243

#### File Generation
```
09_pattern/pattern_haze_removal_top_input.hex → 80-bit compact input
09_pattern/pattern_haze_removal_top_rgb5x5.hex → 25×24-bit RGB frames
07_golden_output/golden_haze_removal_top.hex → 48-bit output per case
07_golden_output/golden_haze_removal_top_A.hex → 24-bit atmospheric light
07_golden_output/golden_haze_removal_top_adc.hex → 8-bit ADC dark
07_golden_output/golden_haze_removal_top_tx5x5.hex → 25×8-bit transmission map
07_golden_output/haze_removal_top_cases.csv → Complete case table
```

---

## Interconnection Matrix

```
┌─────────────────────────────────────────────────────────────┐
│ INPUT: RGB Image Frame                                      │
└────────────────┬────────────────────────────────────────────┘
                 │
        ┌────────▼────────┐
        │  dark_channel   │ → min(R,G,B) per pixel
        └────────┬────────┘
                 │
        ┌────────▼─────────┐
        │  grayscale       │ → 5R+9G+2B using Q8.4
        └────────┬─────────┘
                 │
        ┌────────┴──────────┐
        │                   │
   ┌────▼──────┐    ┌──────▼────┐
   │atmospheric│    │   sky      │
   │_light     │    │_recognition│
   │(A_R,A_G,  │    │(sky_flag)  │
   │A_B)       │    │            │
   └────┬──────┘    └──────┬─────┘
        │                  │
        └────────┬─────────┘
                 │
        ┌────────▼──────────────────┐
        │estimate_transmission      │ → Uses A, normalization, omega scaling
        └────────┬──────────────────┘
                 │ (24-bit tx per pixel)
        ┌────────▼──────────────────┐
        │ adc_estimation_top        │
        │  ├─ pixel_distance        │
        │  ├─ path_length           │
        │  ├─ rlimit                │
        │  └─ ase_masked_min        │
        └────────┬──────────────────┘
                 │ (adc_dark)
        ┌────────▼──────────────────┐
        │ t_compute_fuse            │ → Dehaze recovery
        │ (tx computation +         │
        │  per-channel recovery)    │
        └────────┬──────────────────┘
                 │
        ┌────────▼────────┐
        │ OUTPUT: Dehazed │
        │ RGB Pixel       │
        └─────────────────┘
```

### Data Flow Dependencies
- `dark_channel` → feeds `atmospheric_light`, `sky_recognition`, `adc_estimation`
- `grayscale` → feeds `sky_recognition`
- `atmospheric_light` → feeds `estimate_transmission`, `t_compute_fuse`
- `sky_recognition` → feeds `estimate_transmission`
- `estimate_transmission` → feeds `adc_estimation` (as mc input)
- `adc_estimation` → feeds `t_compute_fuse` (as dark input)

---

## Test Generation Strategy

### Golden File Organization
All golden files are in `07_golden_output/`:
```
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
├── adc_case_XX_golden.txt (20 cases)
├── adc_summary.csv
├── golden_ase_adc.hex
├── t_compute_fuse_cases.csv
├── t_compute_fuse_case_table.md
├── t_compute_fuse_golden.hex
├── golden_bank_rd_data.hex
├── golden_bank_position.txt
├── haze_removal_top_cases.csv
└── golden_haze_removal_top*.hex (multiple variants)
```

### Pattern File Organization
All patterns are in `09_pattern/`:
```
├── pattern_dark_channel.hex
├── pattern_grayscale.hex
├── pattern_atmospheric_light.hex
├── pattern_sky_*.hex (gray, darkch, usedark, a0)
├── rgb.hex, sky.hex (for transmission)
├── pattern_bank_wr_data.hex
├── pattern_haze_removal_top_input.hex
├── pattern_haze_removal_top_rgb5x5.hex
├── adc_case_XX_gray.hex (20 cases)
├── adc_case_XX_mc.hex (20 cases)
├── adc_summary.csv
├── t_compute_fuse_input.hex
├── invA_lut_q16.sv
└── ... (other sub-block patterns)
```

---

## Execution & File Generation

### Running Individual Generators
```bash
python dark_channel.py           # Generates pattern + golden + report
python grayscale.py              # 16 test cases × 3 rounding modes
python atmospheric_light.py      # 20 test cases with haze classification
python sky_recognition.py        # 20 cases with boundary testing
python estimate_transmission.py  # 20 cases with normalization traces
python t_compute_fuse_sw.py      # 20 cases with dehaze details
python bank_pingpong.py          # 4×4 image ping-pong test
python gen_invA_lut_q16.py       # 256-entry reciprocal LUT
python adc_estimation_top.py     # 20 cases full ADC pipeline
python adc_sub_block.py          # Detailed sub-block traces
python adc_subblock_hexgen.py    # $readmemh hex files per sub-block
python purple_block_integration.py  # 2-pass architecture test
python haze_removal_top_sw.py    # Complete E2E regression
```

### Total Test Coverage
- **dark_channel**: 21 patterns
- **grayscale**: 16 patterns × 3 modes = 48 outputs
- **atmospheric_light**: 20 patterns
- **sky_recognition**: 20 patterns × 2 input paths = 40 patterns
- **estimate_transmission**: 20 patterns
- **t_compute_fuse**: 20 patterns
- **adc_estimation**: 20 test cases (5×5 windows)
- **bank_pingpong**: 16 pixels (4×4)
- **haze_removal_top**: ~20 comprehensive cases
- **Total unique test cases**: **150+** covering algorithm boundaries, realistic scenes, and edge cases

---

## Precision & Bit-Width Summary

| Module | Input Width | Output Width | Latency | Key Operations |
|--------|-------------|--------------|---------|------------------|
| dark_channel | 24 (RGB) | 8 | 1 | min(3) |
| grayscale | 24 (RGB) | 8 | 1-2 | Q8.4 scaling + rounding |
| atmospheric_light | 32 (RGB+dark) | 24 (RGB) | ~25 | max & tie-break |
| sky_recognition | 16 (gray+dark) | 8 | 1 | compare + mux |
| estimate_transmission | 32 (RGB+sky) | 8 | 3 | norm + omega + clamp |
| adc pixel_distance | 200 (25×8 gray) | 225 (25×9 dp) | 5 | path edge sums |
| adc path_length | 225 (25×9 dp) | 250 (25×10 dl) | 3 | spatial + lambda×dp |
| adc rlimit | 250 (25×10 dl) | 10 | 2 | sum >> 10 |
| adc ase_masked_min | 250 (dl) + 200 (mc) | 8 (adc) | 2 | mask + min |
| t_compute_fuse | 48 (dark+A+RGB) | 40 (tx+RGB) | 2 | division + recovery |
| gen_invA_lut | - | 6144 (256×24) | 0 | precompute reciprocals |

---

## References

1. **Original Paper**: He, K., Sun, J., Tang, X. (2009). "Single Image Haze Removal Using Dark Channel Prior." *IEEE Conference on Computer Vision and Pattern Recognition (CVPR)*.

2. **Algorithm Overview**:
   - Dark channel: J^dark(x) = min_{c∈{R,G,B}} min_{y∈Ω(x)} J^c(y)
   - Atmospheric light: A = argmax_{pixel} {dark_channel(pixel)}
   - Transmission: t = 1 - ω × (J/A)_min
   - Recovered image: J = (I - A) / t + A

3. **Hardware Architecture**:
   - 4-stage pipeline: dark_ch → A_est → tx_est → dehaze
   - Optional 2-pass for streaming (Pass 1 latch A, Pass 2 process)
   - Adaptive dark channel for refined transmission

---

## Summary

This Python reference implementation provides:

✅ **Complete algorithm coverage** – All stages from dark channel to final dehaze  
✅ **Bit-exact hardware matching** – Integer arithmetic, fixed-point precision  
✅ **Comprehensive test vectors** – 150+ patterns covering boundaries and realistic scenes  
✅ **Golden files for RTL verification** – Hex patterns + reports in standard formats  
✅ **Modular design** – Each stage independently testable and documented  
✅ **Hardware-friendly parameters** – Q-formats, bit-widths, latencies pre-calculated  

**Key directories**:
- `03_sw/` – This reference model (Python)
- `09_pattern/` – Generated test patterns (hex/CSV)
- `07_golden_output/` – Golden outputs + reports (hex/TXT/CSV)
- `00_src/` – RTL implementation (SystemVerilog)
- `01_sim/` – Testbenches using golden files

---

*Analysis generated: March 2026*  
*Framework: Dark Channel Prior Haze Removal v2.0*
