# IPU Hardware Architecture: Dark Channel Prior Haze Removal

This document describes the complete hardware implementation of the Dark Channel Prior algorithm in the IPU (Image Processing Unit) subsystem.

---

## 1. System Overview

### 1.1 Top-Level Hierarchy
```
soc_top (APB bus master)
  └─ ipu_soc (APB slave wrapper)
      ├─ ipu_control_logic (FSM controller)
      ├─ haze_removal_top (main datapath)
      │   ├─ haze_removal_core
      │   ├─ dark_channel pipeline
      │   ├─ atmospheric_light
      │   ├─ estimate_transmission
      │   ├─ adc_estimation (5-stage)
      │   └─ t_compute_fuse (recovery)
      ├─ img_in_bram (input buffer)
      ├─ img_out_bram (output buffer)
      ├─ img_tmp_bram (transmission storage)
      └─ frame_linear_counter
```

### 1.2 Processing Flow

**Phase 1: DARK (Coarse Dark Channel)**
- Input: 128×128 or configurable RGB frame
- Process: Dark channel prior (min of R/G/B channels)
- Output: Dark channel matrix, atmospheric light A

**Phase 2: SKY (Sky Detection)**
- Input: Dark channel, grayscale image
- Process: Sky mask computation
- Output: Sky mask stored in transmission bank

**Phase 3: TRANS (Transmission Map)**
- Input: Atmospheric light A, sky mask
- Process: Coarse transmission via 5×5 minimum filter
- Output: Coarse transmission stored in ping-pong BRAM

**Phase 4: ADC (Adaptive Dark Channel)**
- Input: Original RGB, coarse transmission
- Process: 5-stage pipeline (pixel distance, path length, r-limit, ASE-masked min)
- Output: Refined transmission map

**Phase 5: RECOVERY (Dehazed Output)**
- Input: Original RGB, final transmission, atmospheric light A
- Process: Haze removal fusion formula
- Output: Dehazed RGB frame

---

## 2. Module Architecture Details

### 2.1 Control Logic (`ipu_control_logic.sv`)
**Purpose:** FSM-based orchestration of processing phases

**Ports:**
- Input: CLK, RST_n, APB control signals (reg_wr_en, reg_addr, reg_wdata)
- Output: FSM state, phase control signals, frame counter, IRQ

**FSM States:**
1. IDLE – Wait for APB_CTRL=1 (EN + START bits)
2. LOAD – Load frame from input BRAM into haze_removal_top
3. DARK – Compute dark channel & atmospheric light (latency: ~2000 cycles for 128×128)
4. SKY – Compute sky mask (latency: ~500 cycles)
5. TRANS – Compute coarse transmission (latency: ~3000 cycles)
6. ADC – Run 5-stage ADC pipeline (latency: ~15000 cycles)
7. RECOVERY – Final dehaze & write to output BRAM (latency: ~3000 cycles)
8. DONE – Assert IRQ, return to IDLE

**Key Registers (APB offset):**
- 0x00: APB_CTRL (EN, START, RESET bits)
- 0x04: APB_STATUS (DONE flag, FSM state)
- 0x08: IMG_WIDTH (default: 128)
- 0x0C: IMG_HEIGHT (default: 128)
- 0x10: IMG_STRIDE (default: 512 bytes = 128×4)
- 0x14: SRC_ADDR (input buffer base)
- 0x18: DST_ADDR (output buffer base)
- 0x1C: TMP_ADDR (transmission buffer base)
- 0x20-0x3C: Parameter tuning (OMEGA_Q8, LAMBDA_Q8, T_MIN, etc.)

---

### 2.2 Dark Channel Computation Pipeline

**Modules:**
- `dark_channel.sv` – Main dark channel controller
- `src_min.sv` – Min reduction over large regions
- `search_block_min.sv` – Hierarchical search for min pixel

**Algorithm:** For each pixel, compute min(R, G, B) over window
- Window size: typically 15×15 (must be odd)
- Hardware approach: Streaming with line buffers

**Latency:** ~2000 cycles for 128×128 at 1-pixel/cycle throughput

**Output Precision:** 8-bit unsigned (0-255)

---

### 2.3 Atmospheric Light Computation

**Module:** `atmospheric_light.sv`

**Algorithm:**
1. From dark channel, find top 0.1% brightest pixels
2. Average their RGB values to get A (atmospheric light)
3. Compute A per-channel (R, G, B)

**Inputs:**
- Dark channel matrix (8-bit/pixel)
- Original RGB frame

**Outputs:**
- A_r, A_g, A_b (8-bit each, typically 200-230 for daylight)

**Latency:** ~500 cycles

---

### 2.4 Transmission Estimation

**Primary Module:** `estimate_transmission.sv`

**Sub-modules:**
- `norm_channel_q16.sv` – Normalize channels by A
- `min3_u8.sv` – Minimum of 3 values
- `invA_lut_q16.sv` – Reciprocal lookup table (16-bit Q15.16)
- `omega_clamp_t.sv` – Clamp with OMEGA weighting

**Algorithm:**
```
For each pixel RGB:
  norm_r = (R * invA[A_r]) >> 16  // Normalized w.r.t. A
  norm_g = (G * invA[A_g]) >> 16
  norm_b = (B * invA[A_b]) >> 16
  min_norm = min(norm_r, norm_g, norm_b)
  t = 255 - (OMEGA_Q8 * min_norm) >> 8
  if t < T_MIN: t = T_MIN  // Clamp to preserve contrast
```

**Parameters:**
- OMEGA_Q8: Weighting factor (default: 0xF3 ≈ 0.95)
- T_MIN: Minimum transmission (default: 26, ~10% transmission)

**Latency:** 3-4 cycles per pixel

**Output Precision:** 8-bit (0-255)

---

### 2.5 Adaptive Dark Channel (ADC) Estimation

**Main Module:** `adc_estimation.sv`

**5-Stage Sub-pipeline:**

**Stage 1: Line Buffers** (`adc_line_buffer_5x5.sv`)
- Buffers 5 rows of transmission map
- Enables 5×5 window lookups

**Stage 2: Pixel Distance** (`adc_pixel_distance.sv`)
- Computes distance from pixel to frame edges
- Distance = min(row, col, height-row, width-col)
- Output: 16-bit distance value

**Stage 3: Path Length** (`adc_path_length.sv`)
- Depth simulation: how far light travels through haze
- Formula: path_len = distance * scale_factor
- Output: 32-bit scaled path length Q16.16

**Stage 4: r_limit Threshold** (`adc_rlimit_compute.sv`)
- Based on path length, compute max allowed dark value
- r_limit = LAMBDA_Q8 * path_len (Q0.8 format)
- Output: 16-bit r-limit threshold

**Stage 5: ASE-Masked Minimum** (`adc_ase_masked_min.sv`)
- Apply Angle-Sensitive Estimation mask
- Find minimum in 5×5 window, constrained by r_limit
- Output: Refined dark channel value

**Total ADC Latency:** ~15000 cycles (includes 5-stage warmup + pixel throughput)

---

### 2.6 Transmission Fusion & Recovery

**Module:** `t_compute_fuse.sv`

**Sub-modules:**
- `t_computing.sv` – Final transmission map computation
- `fusing.sv` – Haze removal fusion

**Algorithm:**
```
Fusion Stage (for each pixel):
  final_t = combine(coarse_trans, adc_trans, sky_mask)
  J = (I - A) / final_t + A  // Dehaze formula
```

**Implements:**
- In sky regions: transmission = sky_t (specific value)
- In non-sky: blend coarse & ADC transmissions
- Clamp transmission to [T_MIN, 255]

**Latency:** ~3000 cycles

**Output:** 24-bit RGB dehazed image (8-bit per channel)

---

## 3. Memory Organization

### 3.1 External BRAMs

**Input Image Buffer** (`img_in_bram.v`)
- Depth: 0x4000 (16384 addresses)
- Width: 32-bit (2 pixels of RGB packed)
- Stores: Input 128×128 image (1 frame = 16,384 pixels)
- Access: Dual-port (read/write simultaneous)

**Output Image Buffer** (`img_out_bram.v`)
- Same config as input
- Stores: Dehazed output frame

**Temporary Buffer** (`img_tmp_bram.v`)
- Same config
- Stores: Transmission maps (coarse + ADC refined)
- Ping-Pong mode: Alternates between coarse & ADC writes

### 3.2 Internal BRAM (in `bank_pingpong_stream.sv`)

**Transmission Bank:**
- 2-port BRAM arrays for ping-pong (coarse & refined transmission)
- Streaming read during ADC & recovery phases

**Typical Size:** 128×32 entries (for 128×128 image)

### 3.3 Look-Up Tables (LUT)

**invA_lut_q16.sv:**
- 256-entry LUT: Reciprocal of atmospheric light values
- Format: Q15.16 (32-bit signed fixed-point)
- Maps: A_value [0-255] → 1/A in fixed-point

---

## 4. Data Flow & Synchronization

### 4.1 Pixel Data Paths

```
Input BRAM ──→ Grayscale ──→ Dark Channel ──→ Atmospheric Light
                                   │                    │
                                   └────────────────────┴─→ Estimate Trans (coarse)
                                                            │
Input BRAM ──────────────────────────────────────────→ ADC Refinement
                                                            │
All paths ─────────────────────────────────────────→ Fusion & Recovery
                                                            │
                                                      Output BRAM
```

### 4.2 Storage & Retrieval Pattern

**Coarse Transmission Storage:**
- Write during TRANS phase (phase 3)
- Read during ADC phase (phase 4) for comparison
- Read again during RECOVERY phase (phase 5)

**Ping-Pong BRAM:**
- Ping buffer: coarse transmission (read-only in ADC phase)
- Pong buffer: ADC refined transmission (write during phase 4, read during phase 5)

---

## 5. Timing Characteristics

### 5.1 Phase Latencies (128×128 frame @ 100 MHz)

| Phase | Activity | Cycles | Time |
|-------|----------|--------|------|
| LOAD | Read input from BRAM | 2,048 | 20.48 µs |
| DARK | Dark channel computation | 2,000 | 20.00 µs |
| SKY | Sky mask generation | 500 | 5.00 µs |
| TRANS | Coarse transmission | 3,000 | 30.00 µs |
| ADC | 5-stage pipeline | 15,000 | 150.00 µs |
| RECOVERY | Dehaze fusion + write | 3,000 | 30.00 µs |
| **TOTAL** | Complete frame | ~25,500 | **255 µs** |

### 5.2 Throughput

- **Steady-state:** 1 pixel/cycle (after pipeline warmup)
- **Aggregate:** ~128×128 pixels in 255 µs = 256K pixels/sec

### 5.3 Clock Domain

- Single clock domain (100 MHz typical)
- All modules synchronous (no CDC needed)

---

## 6. Module I/O Port Summary

### 6.1 Standard Port Naming

**Input Prefix:** `i_` (input data/control)  
**Output Prefix:** `o_` (output data)  
**Control Prefix:** `ctrl_` (FSM/enable signals)  
**Status Prefix:** `stat_` (status flags)

### 6.2 Common Port Widths

| Signal | Width | Purpose |
|--------|-------|---------|
| RGB | 24-bit | 8R + 8G + 8B |
| Pixel addr | 16-bit | Up to 65536 pixels |
| Dark channel | 8-bit | Min of R/G/B |
| Transmission | 8-bit | 0-255 mapped |
| A_r/A_g/A_b | 8-bit | Atmospheric light |
| Reciprocal (invA) | 32-bit | Q15.16 fixed-point |

---

## 7. Clock & Reset

- **CLK:** 100 MHz (typical, configurable)
- **RST_n:** Asynchronous active-low reset
  - Clears all state machines
  - Resets BRAM pointers
  - Clears interrupt flags

---

## 8. Parameter Tuning

### 8.1 Algorithm Parameters

**OMEGA_Q8** (Transmission weighting)
- Range: 0x00-0xFF (0.0-1.0 in decimal)
- Default: 0xF3 (~0.953)
- Effect: Higher = stronger haze removal, more local contrast

**LAMBDA_Q8** (Path length scaling)
- Range: 0x00-0xFF
- Default: 0x80 (~0.5)
- Effect: Controls adaptive dark channel aggressiveness

**T_MIN** (Minimum transmission)
- Range: 0-255
- Default: 26 (~10% transmission)
- Effect: Lower = more aggressive, risk of artifacts; higher = preserve details

### 8.2 Register Access

All parameters accessible via APB registers (0x20-0x3C)

```
reg[0x20] = OMEGA_Q8
reg[0x24] = LAMBDA_Q8
reg[0x28] = T_MIN
reg[0x2C] = reserved
...
```

---

## 9. Interrupt & Status

### 9.1 Interrupt (IRQ)

- **Trigger:** FSM reaches DONE state (after RECOVERY phase complete)
- **Clear:** Write APB_CTRL with START bit = 0, or perform hardware reset
- **Type:** Level-triggered (remains asserted until next frame starts)

### 9.2 Status Register

- **Bit[0]:** DONE flag (1 = processing complete)
- **Bit[3:1]:** Current FSM state (0=IDLE, 1=LOAD, ..., 7=DONE)
- **Bit[7:4]:** Reserved

---

## 10. Software Integration Example

```verilog
// Example C-style pseudocode for APB control

void process_frame(uint32_t img_in_addr, uint32_t img_out_addr) {
    // Set addresses
    apb_write(IPU_SRC_ADDR,  img_in_addr);
    apb_write(IPU_DST_ADDR,  img_out_addr);
    apb_write(IPU_TMP_ADDR,  tmp_buffer_addr);
    
    // Set frame size
    apb_write(IPU_IMG_WIDTH,  128);
    apb_write(IPU_IMG_HEIGHT, 128);
    apb_write(IPU_IMG_STRIDE, 512);  // bytes per row
    
    // Set parameters
    apb_write(IPU_OMEGA_Q8,  0xF3);
    apb_write(IPU_LAMBDA_Q8, 0x80);
    apb_write(IPU_T_MIN,     26);
    
    // Enable IRQ
    apb_write(IPU_IRQ_EN, 0x1);
    
    // Start processing (EN=1, START=1)
    apb_write(IPU_CTRL, 0x3);
    
    // Wait for interrupt or poll status
    while (!(apb_read(IPU_STATUS) & 0x1));  // Poll DONE bit
    
    // Processing complete; read output from img_out_addr
}
```

---

## 11. Test & Verification

### 11.1 Testbench Patterns

Software generates 128×128 test images with known content:
- **Uniform hazy regions** – Validates constant transmission handling
- **Mixed content** – Tests distinct sky/ground transitions
- **Edge cases** – Very hazy (low visibility), nearly clear skies

Golden outputs available in `07_golden_output/` directory.

### 11.2 Simulation Checks

1. **Bit-width preservation** – Verify no data corruption through pipeline
2. **Latency matching** – Confirm cycle counts align with specs
3. **BRAM read/write ordering** – Avoid race conditions
4. **State machine transitions** – Ensure correct FSM progression
5. **Output correctness** – Compare against software golden results

---

## 12. Performance Metrics

| Metric | Value |
|--------|-------|
| Frame size (typical) | 128×128 pixels |
| Processing time | ~250 µs |
| Power (estimated) | 50-100 mW @ 100 MHz |
| Area (silicon) | ~1.5 mm² (typical 28nm) |
| Throughput | 1 frame per ~250 µs |
| Memory footprint | ~3 MB BRAM equivalent |

---

## 13. Known Limitations & Future Enhancements

### 13.1 Current Limitations

1. **Fixed frame size:** Requires IMG_WIDTH/HEIGHT to be same for all phases
2. **Single clock domain:** No multi-rate processing
3. **No streaming output:** Must wait for full frame completion
4. **Limited parallelism:** 1 pixel/cycle in steady state

### 13.2 Potential Enhancements

1. **Variable frame sizes** via configurable strides
2. **Streaming input/output** for real-time video
3. **Parallel pipelines** for higher throughput (e.g., 8 pixels/cycle)
4. **Fixed-point precision tuning** for different image content

---

## References

- Dark Channel Prior Algorithm: He et al., 2010
- Software implementation: `03_sw/haze_removal_top_sw.py`
- Hardware test benches: `01_sim/IPU/`
- Register map details: `ipu_addr_map.vh`
