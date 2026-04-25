# 03_sw - Dark Channel Prior Haze Removal Software Reference

## Quick Start

```bash
cd 03_sw

# Generate all golden files and test patterns
python haze_removal_top_sw.py      # E2E comprehensive test
python adc_estimation_top.py       # ADC sub-blocks test
python dark_channel.py              # Dark channel only
python grayscale.py                 # Grayscale conversion
python atmospheric_light.py         # Atmospheric light estimation
python sky_recognition.py           # Sky detection
python estimate_transmission.py     # Transmission map
python t_compute_fuse_sw.py        # Dehaze recovery
python bank_pingpong.py             # Memory test
python gen_invA_lut_q16.py         # Reciprocal LUT generation
```

**Output directories**:
- `../09_pattern/` – Test pattern hex files (for RTL testbenches)
- `../07_golden_output/` – Expected outputs + detailed reports

---

## What Does Each Script Do?

### 1. Core Algorithm Modules (Individual Testing)

#### `dark_channel.py`
**Computes**: min(R, G, B) per pixel  
**Test cases**: 21 patterns (white, black, haze, nature, colors)  
**Outputs**: 
- `pattern_dark_channel.hex` (RGB inputs)
- `golden_dark_channel.hex` (min values)
- `dark_channel_report.txt` (analysis)

```python
dark = min(255, 0, 128)  # Example: (R,G,B) = (255,0,128) → dark=0
```

---

#### `grayscale.py`
**Computes**: Weighted grayscale = (5R + 9G + 2B) / 16  
**Fixed-point**: Q8.4 with 3 rounding modes (up, down, to-even)  
**Test cases**: 16 patterns × 3 modes (48 golden outputs)  
**Outputs**:
- `pattern_grayscale.hex` (RGB inputs)
- `golden_grayscale.hex` (gray values for each mode)
- `grayscale_report.txt` (per-mode comparison)

```python
gray = (5*255 + 9*255 + 2*255) / 16  # All white → gray=255
gray = (5*97 + 9*204 + 2*98) / 16    # Green veg → gray~166
```

---

#### `atmospheric_light.py`
**Computes**: Brightest haze indicator → Atmospheric light A = (A_R, A_G, A_B)  
**Algorithm**: 
1. Find pixel with max dark_channel value
2. Tie-break: select highest total intensity (R+G+B)
3. Return that pixel's RGB as atmospheric light  

**Test cases**: 20 patterns covering light haze to fog  
**Outputs**:
- `pattern_atmospheric_light.hex` (RGB + dark as input)
- `golden_atmospheric_light.hex` (A_R, A_G, A_B output)
- `atmospheric_light_report.txt` (haze classification)

```python
# Input: pixel RGB=(200,210,215), dark=200
# Output: A=(200,210,215) because dark>threshold
# This RGB is the "atmospheric veil" to remove
```

---

#### `sky_recognition.py`
**Computes**: Boolean sky/non-sky flag per pixel  
**Algorithm**: 
```
src_value = dark_channel if use_dark else grayscale
sky = 1 if src_value > A0 else 0
```
**Parameters**: A0=150 (threshold), use_dark=0 (default: compare gray)  
**Test cases**: 20 patterns in both modes  
**Outputs**:
- `pattern_sky_gray.hex`, `pattern_sky_darkch.hex`, `pattern_sky_usedark.hex`, `pattern_sky_a0.hex` (inputs)
- `golden_sky_recognition.hex`, `golden_sky_bw.hex` (outputs: 1-bit flag, 8-bit white)
- `sky_recognition_report.txt` (boundary analysis)

```python
# Input: gray=200, A0=150
# 200 > 150 → sky=1, sky_bw=0xFF (sky pixel, apply max transmission)
# Input: gray=100
# 100 < 150 → sky=0, sky_bw=0x00 (non-sky, compute normally)
```

---

#### `estimate_transmission.py`
**Computes**: Coarse transmission map t ∈ [26, 255]  
**Algorithm**: 
1. Normalize each RGB channel using reciprocal LUT: `norm_c = (pixel_c × inv_A_c_Q16) >> 16`
2. Find minimum: `min_norm = min(norm_r, norm_g, norm_b)`
3. Apply omega scaling: `t_scaled = (OMEGA_Q8 × min_norm) >> 8` where OMEGA_Q8≈0.95
4. Compute transmission: `t = 255 - t_scaled`
5. Clamp to minimum: `t = max(t, T_MIN)` where T_MIN=26
6. Sky override (optional): `if sky: t = 255` (max transmission for sky)

**Key parameters**:
- OMEGA_Q8 = 0xF3 (243) = 0.95 in Q0.8 format
- T_MIN = 26 (prevents over-enhancement)
- T_SKY = 255 (sky gets maximum transmission)
- Reciprocal LUT: 256 × 24-bit Q16 values

**Test cases**: 20 patterns (from black to white, all colors, various haze levels)  
**Outputs**:
- `rgb.hex` (RGB patterns)
- `sky.hex` (sky flags)
- `t_golden.hex` (transmission outputs)
- `estimate_transmission_report.txt` (detailed trace)

```python
# Input: pixel=(30,50,70), A=(200,200,200)
# norm_r = (30 × inv_lut[200]) >> 16 ≈ 38
# norm_g = (50 × inv_lut[200]) >> 16 ≈ 64
# norm_b = (70 × inv_lut[200]) >> 16 ≈ 89
# min_norm = 38
# t_scaled = (243 × 38) >> 8 = 36
# t = 255 - 36 = 219 → output transmission is high (clear pixel)
```

---

### 2. Adaptive Dark Channel (ADC) Estimation

#### `adc_estimation_top.py`
**Computes**: Refined dark channel using spatial weighting  
**Pipeline**: 4 sequential sub-blocks for 5×5 window

**Sub-block 1: pixel_distance**
- Input: 25×8-bit grayscale window
- Output: 25×9-bit distance values
- Algorithm: Sum of absolute differences along path from center to each pixel

**Sub-block 2: path_length**
- Input: 25×9-bit distances, lambda_q8=51
- Output: 25×10-bit weighted path lengths
- Algorithm: `path_length[i] = spatial_distance[i] + (lambda_q8 × pixel_distance[i]) >> 8`

**Sub-block 3: rlimit**
- Input: 25×10-bit path lengths
- Output: 10-bit radius limit (threshold)
- Algorithm: Mean of all path lengths (uses fixed-point multiply by 41, divide by 1024)

**Sub-block 4: ase_masked_min (Adaptive Spatial Extent)**
- Input: rlimit threshold, path_lengths, MC values (25×8-bit, typically transmission)
- Output: 8-bit minimum value within adaptive mask
- Algorithm: 
  1. Create binary mask: `mask[i] = (path_length[i] <= rlimit) ? 1 : 0` (center always included)
  2. Find minimum: `adc = min(mc[i] for i where mask[i]==1)`

**Test cases**: 20 diverse 5×5 windows (flat, edges, patterns, noise, gradients, etc.)  
**Outputs**:
- `adc_case_XX_gray.hex` (25×8-bit gray patterns)
- `adc_case_XX_mc.hex` (25×8-bit MC patterns)
- `adc_case_XX_golden.txt` (full trace with all sub-block outputs)
- `adc_summary.csv` (summary of all cases)

```
Execution example:
Input: 5×5 window of grayscale values
  100 100 180 100 100
  100 100 180 100 100
  180 180 180 180 180
  100 100 180 100 100
  100 100 180 100 100

Step 1: Compute pixel_distance[i]
  → Sum |gray differences| along path from center (2,2) to each edge

Step 2: Compute path_length[i]  
  → spatial_distance + weighted pixel_distance

Step 3: Compute rlimit
  → mean of path_lengths ≈ 10-15 (depends on variance)

Step 4: Generate ase_mask
  → Pixels within rlimit get mask=1 (spatial extent ~7-12 pixels)

Step 5: Compute ADC
  → Minimum of MC values where mask==1
```

---

#### `adc_sub_block.py`
**Detailed version**: 20 test cases with per-sub-block output details  
**Reuses**: Same testcases, path generation, spatial table as adc_estimation_top  
**Writes**: Detailed CSV traces for verification

---

#### `adc_subblock_hexgen.py`
**Generates**: $readmemh-compatible hex files for individual sub-block testbenches  
**Outputs** (per sub-block):
- `pattern_pixel_distance.hex` → 25×8-bit gray inputs
- `golden_pixel_distance.hex` → 25×9-bit outputs
- `pattern_path_length.hex` → 25×9-bit dp inputs
- `golden_path_length.hex` → 25×10-bit outputs
- `pattern_rlimit.hex` → 25×10-bit dl inputs
- `golden_rlimit.hex` → 1×10-bit output + pass-through
- `pattern_ase_*.hex` (rlimit, dl, mc) → 3 inputs for ASE mask filter
- `golden_ase_adc.hex` → 1×8-bit minimum output

---

### 3. Final Stages

#### `t_compute_fuse_sw.py`
**Computes**: Final transmission from ADC dark channel, then dehaze recovery  
**Algorithm**:
1. **Transmission computation**: `tx_raw = 255 - floor(dark × MODIFICATION / A)`
2. **Transmission clamping**: `tx_used = max(tx_raw, TX_MIN)` where TX_MIN=15
3. **Per-channel dehaze**: 
   ```
   for each channel c in {R, G, B}:
     temp = ((src_c - A) << 8) + A × tx_used
     out_c = floor(temp / tx_used)
   ```

**Key parameters**:
- MODIFICATION_VALUE = 255 (or 243 for softer dehaze)
- TX_MIN = 15 (lower = stronger dehaze)
- Formula basis: Haze model `I = J×t + A×(1-t)` → inverse `J = (I-A)/t + A`

**Test cases**: 20 designed for boundary conditions (dark=A, src<A, src=A, src>A, etc.)  
**Outputs**:
- `t_compute_fuse_input.hex` (48-bit compound input)
- `t_compute_fuse_golden.hex` (40-bit compound output)
- `t_compute_fuse_cases.csv` (detailed case table)
- `t_compute_fuse_case_table.md` (markdown reference)

```python
# Case: dark=100, A=200, src_r=160
# tx_raw = 255 - (100 × 255) / 200 = 255 - 127 = 128
# tx_used = max(128, 15) = 128
# out_r = floor(((160 - 200) << 8) + 200 × 128) / 128)
#      = floor((-40 << 8) + 25600) / 128
#      = floor(-10240 + 25600) / 128
#      = floor(15360 / 128)
#      = 120
```

---

#### `haze_removal_top_sw.py`
**Master integration test**: Combines ALL stages in one comprehensive framework  
**Flow**:
1. Input: 5×5 RGB frame (25 pixels)
2. Compute dark channel for all 25 pixels
3. Find atmospheric light A from max dark (with intensity tie-break)
4. Compute grayscale for all 25 pixels
5. Sky recognition for all 25 pixels
6. Coarse transmission estimation for all 25 pixels
7. ADC estimation using transmission as input
8. Dehaze recovery using center pixel + A + adc_dark

**Test cases**: ~20 comprehensive end-to-end scenarios  
**Outputs**:
- `pattern_haze_removal_top_input.hex` (compact 80-bit input per case)
- `pattern_haze_removal_top_rgb5x5.hex` (25×24-bit full frame per case)
- `golden_haze_removal_top.hex` (48-bit output per case)
- `golden_haze_removal_top_A.hex` (24-bit atmospheric light per case)
- `golden_haze_removal_top_adc.hex` (8-bit ADC dark per case)
- `golden_haze_removal_top_tx5x5.hex` (25×8-bit transmission map per case)
- `haze_removal_top_cases.csv` (complete case summary)

---

### 4. Utility & Memory Tests

#### `bank_pingpong.py`
**Purpose**: Verify dual-port memory swap mechanism  
**Test**: Write 4×4 image to BANK_A, swap, read from BANK_B  
**Verification**: Read data matches write data in order  

**Outputs**:
- `pattern_bank_wr_data.hex` (16×8-bit write pattern)
- `golden_bank_rd_data.hex` (16×8-bit expected readback)
- `golden_bank_position.txt` (boundary flags: row, col, at_top, at_bottom, at_left, at_right)
- `bank_pingpong_report.txt` (detailed flow)

```
Write phase:
  addr=0:  data=0x07   [row=0, col=0, flags=TOP,LEFT]
  addr=1:  data=0x1A   [row=0, col=1, flags=TOP]
  ... (16 pixels)

Swap banks

Read phase:
  addr=0:  expect=0x07
  addr=1:  expect=0x1A
  ... (must match write phase)
```

---

#### `gen_invA_lut_q16.py`
**Generates**: Pre-computed reciprocal lookup table for transmission estimation  
**Formula**: `inv_A_q16[A] = floor((255 << 16) / A)` for A ∈ [0, 255]  
**Special case**: `inv_A_q16[0] = 0xFFFFFF` (divide-by-zero handler)  
**Output**: `invA_lut_q16.sv` (SystemVerilog localparam array)

```python
# Example values:
inv_A_q16[1]   = 255 << 16 = 0xFFFFFF (when A=1, output all 1s)
inv_A_q16[255] = (255 << 16) / 255 = 0x0100 (when A=255, divide by max)
inv_A_q16[200] = (255 << 16) / 200 = 0x0147 (typical atmospheric light)
```

---

#### `purple_block_integration.py`
**Tests**: 2-pass architecture for streaming systems  
**Pass 1**: Frame → dark_channel → atmospheric_light → latch A  
**Pass 2**: Frame → dark_channel → grayscale → sky → transmission (using A from Pass 1)  

**Test image**: 4×4 (16 pixels) with mixed sky/non-sky, varied haze  
**Outputs**: Hex patterns + golden files for both passes

---

## File Organization

### Pattern Files (09_pattern/)
```
pattern_*.hex        → Input stimuli for each module
```
- Hex format: Each line is one value (8-bit or multi-bit)
- Comments mark pattern boundaries and case names
- Used by RTL testbenches via $readmemh

### Golden Files (07_golden_output/)
```
golden_*.hex         → Expected outputs for each module
*_report.txt         → Detailed analysis (case-by-case breakdown)
*_cases.csv          → Table format (easy for comparison)
*_case_table.md      → Markdown reference (human-readable)
```

---

## Parameter Matrix

| Parameter | Value | Range | Purpose |
|-----------|-------|-------|---------|
| A0 | 150 | 0-255 | Sky recognition threshold |
| USE_DARK | 0 | 0-1 | Use dark_ch (1) or gray (0) for sky detection |
| USE_SKY | 1 | 0-1 | Enable sky override in transmission |
| T_SKY | 255 | 0-255 | Transmission for sky pixels |
| OMEGA_Q8 | 243 | 0-255 | Omega in Q0.8 format (~0.95) |
| T_MIN | 26 | 0-255 | Minimum transmission (clamp) |
| TX_MIN (t_compute) | 15 | 0-255 | Lower minimum for final transmission |
| LAMBDA | 0.2 | 0-1 | Weight for pixel distance in ADC path length |
| MODIFICATION_VALUE | 255 | 0-255 | Scaling for final transmission (1.0 × 256) |
| DARK_THRESHOLD | 128 | 0-255 | Threshold for atmospheric light estimation |

---

## Typical Execution & Integration

### For Developers

**Running specific module tests**:
```bash
python dark_channel.py              # Single module
python grayscale.py
python estimate_transmission.py
```

**Running integration tests**:
```bash
python haze_removal_top_sw.py       # Full pipeline
python purple_block_integration.py  # 2-pass mode
```

**Verifying sub-block outputs**:
```bash
python adc_sub_block.py  # Detailed ADC traces
python adc_subblock_hexgen.py  # Split $readmemh files
```

### For Verification Engineers

**Generate baseline patterns**:
```bash
python haze_removal_top_sw.py  # Creates all 09_pattern/ and 07_golden_output/ files
```

**RTL Testbench Flow**:
1. Load patterns from `09_pattern/pattern_*.hex` using `$readmemh`
2. Apply patterns to RTL module
3. Compare outputs with `07_golden_output/golden_*.hex`
4. Generate detailed reports from `07_golden_output/*_report.txt`

### For Algorithm Research

**Customizing parameters**:
```python
# Edit constants in each module, e.g., in estimate_transmission.py:
OMEGA_Q8 = 200  # Adjust dehaze strength
T_MIN = 20      # Change minimum transmission
```

Then rerun to generate new golden files.

---

## Test Coverage Summary

| Module | Test Cases | Patterns | Coverage |
|--------|-----------|----------|----------|
| dark_channel | 21 | Haze, nature, colors, extremes | Boundary (0/255) + typical |
| grayscale | 16 | + 3 modes | Color distribution + rounding effects |
| atmospheric_light | 20 | Light/medium/heavy haze | Threshold behavior + tie-break |
| sky_recognition | 20 | Gray/dark_ch both | Boundary (A0±1) + extremes |
| estimate_transmission | 20 | Gray/color/haze patterns | Normalization + omega scaling |
| adc_estimation | 20 | Structured + random | Edge detection + adaptive masking |
| t_compute_fuse | 20 | Clear/haze/extreme | Transmission division + clamping |
| bank_pingpong | 1 | 4×4 image | Memory swap correctness |
| haze_removal_top | 20+ | E2E scenarios | Pipeline integration |

**Total**: 150+ distinct test patterns with bit-exact golden outputs

---

## Debugging & Verification

### Checking Intermediate Values

Each `*_report.txt` file provides:
- **Per-case breakdown**: Input → algorithm steps → output
- **Intermediate values**: Partially computed results for tracing
- **Classification**: Haze level, color distribution, etc.
- **Error analysis**: Clipping, overflow conditions

### Common Issues

**Q: Output doesn't match golden?**  
A: Check:
1. Input bit-width (ensure 8-bit RGB, not floats)
2. Fixed-point format (Q8.4 for grayscale, Q16 for reciprocals)
3. Rounding mode (dark_channel=truncate, grayscale=configurable)
4. Clipping ranges (transmission ∈ [T_MIN, 255])

**Q: ADC results vary between passes?**  
A: ADC is deterministic; verify:
1. Path generation (diagonal-first rule)
2. Spatial table values (0-4 distance grid)
3. Lambda parameter (should match RTL)

**Q: Sky detection flags incorrect?**  
A: Check:
1. USE_DARK parameter (0=gray, 1=dark_ch)
2. A0 threshold value (150 default)
3. Comparison operator (strictly > not ≥)

---

## References & Further Reading

1. **Dark Channel Prior Paper**: He, K., Sun, J., Tang, X. (2009). *Single Image Haze Removal Using Dark Channel Prior.* CVPR.

2. **Algorithm Details** (See `ANALYSIS.md` for complete module documentation)

3. **RTL Integration** (See `00_src/` for SystemVerilog implementation)

4. **Testbenches** (See `01_sim/` for test environments using these golden files)

---

## File Manifest

### Main Scripts (Run These)
- `haze_removal_top_sw.py` – E2E integration (recommended starting point)
- `adc_estimation_top.py` – ADC pipeline test
- `dark_channel.py` – Dark channel only
- `grayscale.py` – Grayscale conversion
- `atmospheric_light.py` – Haze source estimation
- `sky_recognition.py` – Sky pixel detection
- `estimate_transmission.py` – Transmission map
- `t_compute_fuse_sw.py` – Dehaze recovery
- `bank_pingpong.py` – Memory test
- `gen_invA_lut_q16.py` – Reciprocal LUT

### Supporting Scripts
- `adc_sub_block.py` – Detailed ADC traces
- `adc_subblock_hexgen.py` – Sub-block hex generation
- `purple_block_integration.py` – 2-pass architecture test

### Documentation
- `ANALYSIS.md` – Complete technical analysis (this file)
- `README_t_compute_fuse_sw.md` – Dehaze recovery details (auto-generated)

---

**Latest Update**: March 2026  
**Framework**: Dark Channel Prior v2.0 with ADC refinement  
**Status**: Production-ready, bit-exact with baseline RTL

