# IPU Hardware: Quick Reference Guide

Fast lookup for module ports, register addresses, parameters, and troubleshooting.

---

## 1. Module Directory

| Module | File | Purpose | Port Count |
|--------|------|---------|-----------|
| ipu_control_logic | ipu_control_logic.sv | FSM & APB interface | 15 |
| haze_removal_top | haze_removal_top.sv | Main datapath wrapper | 12 |
| haze_removal_core | haze_removal_core.sv | Core processing logic | 18 |
| dark_channel | dark_channel.sv | Dark channel prior | 8 |
| src_min | src_min.sv | Source image min filter | 6 |
| search_block_min | search_block_min.sv | Hierarchical min search | 5 |
| atmospheric_light | atmospheric_light.sv | A estimation | 9 |
| estimate_transmission | estimate_transmission.sv | Coarse t map | 10 |
| norm_channel_q16 | norm_channel_q16.sv | Channel normalization | 6 |
| invA_lut_q16 | invA_lut_q16.sv | Reciprocal LUT (256 entries) | 4 |
| omega_clamp_t | omega_clamp_t.sv | Transmission clamping | 5 |
| adc_estimation | adc_estimation.sv | ADC refinement | 16 |
| adc_line_buffer_5x5 | adc_line_buffer_5x5.sv | 5×5 line buffer | 8 |
| adc_pixel_distance | adc_pixel_distance.sv | Distance from edge | 7 |
| adc_path_length | adc_path_length.sv | Path length scaling | 6 |
| adc_rlimit_compute | adc_rlimit_compute.sv | r_limit threshold | 5 |
| adc_ase_masked_min | adc_ase_masked_min.sv | ASE-masked min filter | 9 |
| t_compute_fuse | t_compute_fuse.sv | Transmission fusion | 12 |
| t_computing | t_computing.sv | Final transmission | 8 |
| fusing | fusing.sv | Haze removal formula | 10 |
| grayscale | grayscale.sv | RGB→Gray conversion | 4 |
| sky_recognition | sky_recognition.sv | Sky mask generation | 5 |
| min3_u8 | min3_u8.sv | 3-value minimum | 4 |
| bank_bram | bank_bram.sv | Transmission buffer BRAM | 9 |
| bank_pingpong_stream | bank_pingpong_stream.sv | Ping-pong dual buffer | 11 |
| frame_linear_counter | frame_linear_counter.sv | Coordinate generation | 8 |
| img_in_bram | mem/img_in_bram.v | Input RGB buffer | 7 |
| img_out_bram | mem/img_out_bram.v | Output RGB buffer | 7 |
| img_tmp_bram | — (part of ipu_soc) | Transmission buffer | — |

---

## 2. Standard Port Naming Convention

### Prefix
- `i_` – Logic input
- `o_` – Logic output
- `clk`, `rst_n` – Clock & reset (always present)
- `ctrl_`, `stat_` – Control/status signals

### Common Widths
| Port Type | Width | Example |
|-----------|-------|---------|
| RGB triplet | 24-bit | `i_rgb[23:0]` (8R+8G+8B) |
| Single channel | 8-bit | `o_r[7:0]`, `o_g[7:0]`, `o_b[7:0]` |
| Pixel address | 16-bit | `i_pix_addr[15:0]` |
| Transmission | 8-bit | `o_trans[7:0]` (0-255) |
| Dark channel | 8-bit | `o_dark[7:0]` (0-255) |
| Fixed-point Q15.16 | 32-bit | `i_reciprocal[31:0]` |
| Fixed-point Q16.16 | 32-bit | `o_scaled[31:0]` |
| Control enable | 1-bit | `ctrl_enable` |
| Valid flag | 1-bit | `o_valid` |
| Ready flag | 1-bit | `o_ready` |

---

## 3. APB Register Map

| Offset | Name | Bits | Default | R/W | Description |
|--------|------|------|---------|-----|-------------|
| 0x00 | APB_CTRL | [31:0] | 0 | W | EN=0, START=1, RESET=2 bits |
| 0x04 | APB_STATUS | [31:0] | 0 | R | DONE=bit0, FSM_STATE=bits3:1 |
| 0x08 | IMG_WIDTH | [31:0] | 128 | W | Frame width in pixels |
| 0x0C | IMG_HEIGHT | [31:0] | 128 | W | Frame height in pixels |
| 0x10 | IMG_STRIDE | [31:0] | 512 | W | Row stride in bytes (usually W×4) |
| 0x14 | SRC_ADDR | [31:0] | 0 | W | Input buffer base address |
| 0x18 | DST_ADDR | [31:0] | 0 | W | Output buffer base address |
| 0x1C | TMP_ADDR | [31:0] | 0 | W | Transmission buffer base address |
| 0x20 | IRQ_EN | [0] | 0 | W | Enable completion interrupt |
| 0x24 | OMEGA_Q8 | [7:0] | 0xF3 | W | Transmission weighting (0-255 → 0.0-1.0) |
| 0x28 | LAMBDA_Q8 | [7:0] | 0x80 | W | Path length scaling (0-255 → 0.0-1.0) |
| 0x2C | T_MIN | [7:0] | 26 | W | Minimum transmission clamp |
| 0x30-0x3C | Reserved | — | — | — | Future parameters |

### Bit Fields Detail

**APB_CTRL (0x00):**
```
[31:3] Reserved
[2]    RESET (1=synchronous reset)
[1]    START (1=initiate processing)
[0]    EN    (1=enable IPU)
```

**APB_STATUS (0x04):**
```
[31:4] Reserved
[3:1]  FSM_STATE (0=IDLE, 1=LOAD, 2=DARK, 3=SKY, 4=TRANS, 5=ADC, 6=RECOVERY, 7=DONE)
[0]    DONE (1=processing complete, remains high until next START)
```

---

## 4. Algorithm Parameters

### OMEGA_Q8 (Transmission Weighting)
```
Register: 0x24
Format: Q0.8 (8-bit fixed-point)
Range: 0x00 (0.0) to 0xFF (0.996)
Default: 0xF3 (~0.953)
Usage: t = 255 - (OMEGA_Q8 * min_norm) >> 8
Effect:
  - Higher → stronger haze removal, more local contrast
  - Lower → weaker removal, more natural
Typical: 0xE0-0xFF
```

### LAMBDA_Q8 (Path Length Scaling)
```
Register: 0x28
Format: Q0.8 (8-bit fixed-point)
Range: 0x00 (0.0) to 0xFF (0.996)
Default: 0x80 (~0.5)
Usage: path_len = distance * LAMBDA_Q8
Effect:
  - Higher → more aggressive ADC (harder to satisfy r_limit)
  - Lower → softer ADC
Typical: 0x40-0xC0
```

### T_MIN (Minimum Transmission)
```
Register: 0x2C
Format: 8-bit unsigned integer
Range: 0-255
Default: 26 (~10% transmission, ~90% fog removal)
Usage: final_t = max(computed_t, T_MIN)
Effect:
  - Lower (≤10) → very aggressive, risk of artifacts
  - Default (26) → balanced
  - Higher (50+) → conservative, preserve details
Typical: 10-50
```

---

## 5. Latency Summary

| Phase | Cycles | Time @ 100MHz | Notes |
|-------|--------|---------------|-------|
| LOAD | 2,048 | 20.48 µs | Input BRAM read |
| DARK | 2,000 | 20.00 µs | Dark channel + atm light |
| SKY | 500 | 5.00 µs | Sky mask generation |
| TRANS | 3,000 | 30.00 µs | Coarse transmission write |
| ADC | 15,000 | 150.00 µs | 5-stage pipeline (warmup+processing) |
| RECOVERY | 3,000 | 30.00 µs | Dehaze + output BRAM write |
| **TOTAL** | **25,500** | **255 µs** | Per 128×128 frame |

---

## 6. Memory Organization

### BRAM Allocation (128×128 frame)

```
Input BRAM (img_in_bram):
  - Size: 16,384 × 32-bit = 64 KB
  - Content: 128×128 RGB (2 pixels per word)
  - Access: Read during LOAD, read during DARK
  
Output BRAM (img_out_bram):
  - Size: 16,384 × 32-bit = 64 KB
  - Content: Dehazed RGB (2 pixels per word)
  - Access: Write during RECOVERY
  
Transmission BRAM (img_tmp_bram):
  - Size: 16,384 × 32-bit = 64 KB
  - Content: Coarse & refined transmission maps
  - Access: Write TRANS, read ADC+RECOVERY (ping-pong)
  
Internal bank_pingpong_stream:
  - Dual BRAM: ping (coarse) + pong (ADC)
  - Size: 128×32 entries each (~512b each)
  - Purpose: Zero-contention transmission storage
```

### Address Layout
```
0x0000 – 0x3FFF: Input image (img_in_bram)
0x4000 – 0x7FFF: Output image (img_out_bram)
0x8000 – 0xBFFF: Transmission maps (img_tmp_bram)
```

---

## 7. Timing Characteristics

### Clock Domain
- Single clock: 100 MHz (typical, configurable)
- All modules synchronous
- No clock domain crossing

### Reset
- Async active-low `rst_n`
- Clears FSM, BRAM pointers, interrupt flags
- Assert for ≥2 clock cycles

### Interrupt
- Level-triggered (asserted in DONE phase, remains high)
- Cleared when APB_CTRL[1:0] changes (EN or START bit toggled)

---

## 8. Connectivity Matrix

### Data Dependencies

```
Module                Reads From              Writes To
─────────────────────────────────────────────────────────────
ipu_control_logic     APB registers           FSM control signals
dark_channel          Input BRAM              Dark channel values
atmospheric_light     Dark channel            A_r, A_g, A_b
sky_recognition       Grayscale               Sky mask
estimate_transmission Atm light, RGB          Coarse transmission
adc_estimation        Trans, RGB, coords      Refined transmission
t_compute_fuse        Coarse, ADC, sky        Final transmission
fusing                Final trans, RGB, A     Dehazed RGB
─────────────────────────────────────────────────────────────
```

---

## 9. Troubleshooting Guide

### Issue: FSM stuck in DARK phase

**Symptom:** Status register shows FSM_STATE=2, DONE=0, no progress

**Causes:**
1. Dark channel computation not completing
2. Line buffer stall (check input BRAM read)
3. Overflow in min reduction

**Solution:**
- Verify input BRAM contains valid data
- Check external clock frequency (should be 100 MHz)
- Reset and retry with smaller frame size (64×64)

### Issue: Output image all zeros

**Symptom:** img_out_bram contains only zeros after processing

**Causes:**
1. RECOVERY phase not executing (check FSM state)
2. Transmission=255 (completely clear), dehaze formula produces 0
3. Output BRAM write address incorrect

**Solution:**
- Verify DST_ADDR points to valid BRAM
- Check final transmission values (should be < 255 for dehaze effect)
- Confirm RECOVERY phase executes

### Issue: Output very dark or very light

**Symptom:** Dehazed image has extreme contrast

**Causes:**
1. T_MIN too low (≤5) → aggressive remnoval → artifacts
2. OMEGA_Q8 too high (0xFF) → over-sharpening
3. Atmospheric light estimation failed

**Solution:**
- Increase T_MIN to 30-50
- Reduce OMEGA_Q8 to 0xE0-0xF0
- Verify input image has clear sky regions

### Issue: Processing takes >500 µs per frame

**Symptom:** Frame latency exceeds expected 255 µs

**Causes:**
1. Clock running slower than 100 MHz
2. Frame size larger than 128×128 (e.g., 256×256)
3. FSM stuck in ADC phase (15000+ cycles)

**Solution:**
- Verify clock frequency with oscilloscope
- Check IMG_WIDTH/IMG_HEIGHT registers
- Debug ADC line buffer (check for deadlock)

---

## 10. Performance Tuning

### For Stronger Haze Removal
```
Increase OMEGA_Q8: 0xF3 → 0xF8
Decrease T_MIN: 26 → 15
Increase LAMBDA_Q8: 0x80 → 0xA0
```

### For Lighter, More Natural Results
```
Decrease OMEGA_Q8: 0xF3 → 0xE0
Increase T_MIN: 26 → 50
Decrease LAMBDA_Q8: 0x80 → 0x60
```

### For Faster Processing (experimental)
```
Note: These optimizations require hardware modification
- Reduce ADC pipeline stages (lose refinement quality)
- Skip sky detection (assume T_sky = T_min)
- Use 8-bit precision instead of Q16 (lose dynamic range)
```

---

## 11. Golden Test Vectors

### Test Pattern: Uniform Haze (180,180,180)

**Input:** 128×128 frame, all pixels RGB(180,180,180)

**Expected outputs:**
```
Dark channel: All 180
Atmospheric light A: ~(220, 220, 220)
Coarse transmission: ~110-120
ADC transmission: ~90-100
Final transmission: ~100-110
Dehazed pixel: ~RGB(115-125, 115-125, 115-125)

Acceptable delta margin: ±2 per channel
```

**Golden files:**
- `07_golden_output/haze_removal_top_cases.csv`
- `07_golden_output/golden_haze_removal_top.hex`

### Test Pattern: Mixed Content (varied RGB + sky)

**Input:** Top 30% sky (light blue), bottom 70% hazy landscape

**Expected behavior:**
```
Sky region (RGB~200,220,240):
  - Low dark channel (~100)
  - High transmission (~200)
  - Minimal color change (not dehazed)

Landscape (RGB~160,160,160):
  - Higher dark channel (~160)
  - Lower transmission (~80)
  - Stronger dehaze effect (→RGB~120,120,120)
```

---

## 12. Register Access Patterns

### Typical Initialization Sequence

```verilog
// 1. Set addresses (before EN)
apb_write(0x14, BASE_IN);    // SRC_ADDR
apb_write(0x18, BASE_OUT);   // DST_ADDR
apb_write(0x1C, BASE_TMP);   // TMP_ADDR

// 2. Set frame dimensions
apb_write(0x08, WIDTH);      // IMG_WIDTH
apb_write(0x0C, HEIGHT);     // IMG_HEIGHT
apb_write(0x10, STRIDE);     // IMG_STRIDE (typically WIDTH*4)

// 3. Set parameters (optional, can use defaults)
apb_write(0x24, 0xF3);       // OMEGA_Q8
apb_write(0x28, 0x80);       // LAMBDA_Q8
apb_write(0x2C, 26);         // T_MIN

// 4. Enable interrupt if needed
apb_write(0x20, 0x1);        // IRQ_EN

// 5. Start processing (EN=1, START=1)
apb_write(0x00, 0x3);        // APB_CTRL
```

### Status Polling Loop

```verilog
// Poll for completion
do {
    status = apb_read(0x04);  // APB_STATUS
    done = status & 0x1;
} while (!done);

// Optional: check final FSM state
fsm_state = (status >> 1) & 0x7;  // Should be 7 (DONE)
```

---

## 13. Clock & Reset Best Practices

- **Clock:** Always provide stable 100 MHz clock before assertions
- **Reset:** Assert `rst_n=0` for 2-5 cycles at startup
- **Timing:** Respect APB protocol (setup/hold times per spec)
- **Glitch-free:** Use synchronized reset deassertion logic

---

## References

- Full architecture: `IPU_HARDWARE_ARCHITECTURE.md`
- Data flow examples: `IPU_HARDWARE_DIAGRAMS.md`
- Testbench simulation: `01_sim/IPU/Testbench_*_tb.sv`
- Software reference: `03_sw/haze_removal_top_sw.py`
