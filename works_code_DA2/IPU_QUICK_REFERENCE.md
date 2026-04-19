# IPU Hardware Architecture - Quick Reference Guide

## Module Quick Lookup Table

### Top-Level Integration
| Module | File | Purpose | Key Ports |
|--------|------|---------|-----------|
| ipu_soc | ipu_soc.sv | SoC wrapper, external BRAM management | reg_wr/rd*, img_in/out/tmp_* |
| ipu_top | ipu_top.sv | (Legacy) full IPU integration | Same as ipu_core |
| haze_removal_top | haze_removal_top.sv | Frame interface wrapper | i_src_valid, i_src_rgb, post_img |
| haze_removal_core | haze_removal_core.sv | Main datapath, 3-pass processing | dark_enable, trans_enable, recovery_enable |
| ipu_control_logic | ipu_control_logic.sv | 7-state FSM controller | dark_done, sky_done, trans_done, adc_done, recovery_done |

### First Pass: Dark Channel & Atmospheric Light
| Module | File | Latency | Input | Output |
|--------|------|---------|-------|--------|
| dark_channel | dark_channel.sv | 1 cycle | [23:0] RGB | [7:0] min(R,G,B) |
| grayscale | grayscale.sv | 1 cycle | [23:0] RGB | [7:0] gray (0.31R+0.56G+0.12B) |
| atmospheric_light | atmospheric_light.sv | Frame+1 | dark_ch stream | [8:0]×3 A_R/A_G/A_B |
| sky_recognition | sky_recognition.sv | 1 cycle (+prior stages) | gray/dark_ch | [0:0] is_sky |

### Second Pass: Transmission
| Module | File | Latency | Input | Output | Notes |
|--------|------|---------|-------|--------|-------|
| atm_light_coarse_tx | atm_light_coarse_tx.sv | 3+ cycles | i_color, i_A* | o_tx [7:0] | Integrates above modules |
| invA_lut_q16 | invA_lut_q16.sv | 0 (combinational) | [7:0] A | [23:0] Q16 inv | Precomputed 256-entry LUT |
| norm_channel_q16 | norm_channel_q16.sv | 0 (combinational) | [7:0] pixel, [23:0] inv_A | [7:0] norm | (pix*inv_A)>>16 |
| min3_u8 | min3_u8.sv | 0 (combinational) | [7:0]×3 | [7:0] min | Simple 3-input min |
| spatial_min3x3 | spatial_min3x3.sv | IMG_WIDTH+4 | pixel stream | [7:0] min | 3×3 filter (optional, not used) |
| omega_clamp_t | omega_clamp_t.sv | 0 (combinational) | [7:0] x | [7:0] t | 255-(OMEGA*x)>>8, clamp T_MIN |
| estimate_transmission | estimate_transmission.sv | ~2 cycles total | i_color, i_A* | [7:0] o_t | Full transmission module |

### Bank Storage
| Module | File | Depth | Width | Purpose |
|--------|------|-------|-------|---------|
| bank_bram | bank_bram.sv | 2^ADDR_WIDTH | 8-bit | Single BRAM block |
| bank_pingpong_stream | bank_pingpong_stream.sv | 2×IMG_WIDTH×IMG_HEIGHT | 8-bit | Dual-buffered TX storage + read/write counters |
| frame_linear_counter | frame_linear_counter.sv | N/A (counter) | N/A | Address + position generation |

### Third Pass: ADC Estimation (5-Stage Pipeline)
| Stage | Module | Latency | Input | Output |
|-------|--------|---------|-------|--------|
| 0 | adc_line_buffer_5x5 | 4*WIDTH+4 warmup | pixel stream | 5×5 window |
| 1 | adc_pixel_distance | 1 cycle | gray window | [8:0]×25 dp_total |
| 2 | adc_path_length | 1 cycle | dp values | [9:0]×25 d_lambda |
| 3-4 | adc_rlimit_compute | 2 cycles | d_lambda | [9:0] r_limit |
| 5 | adc_ase_masked_min | 1 cycle | MC window, r_limit | [7:0] adc |
| **TOTAL ADC** | adc_estimation.sv | 4*WIDTH+9 | gray + MC streams | [7:0] adc_pix |

### Recovery (Final Stage)
| Module | File | Latency | Input | Output |
|--------|------|---------|-------|--------|
| t_computing | t_computing.sv | 1 cycle | dark, A | tx_raw, tx_used |
| fusing | fusing.sv | 1 cycle | tx_raw, src, A | out_r/g/b |
| t_compute_fuse | t_compute_fuse.sv | 2 cycles | dark, src, A | final RGB |

---

## Port Name Conventions

### Naming Pattern
```
i_*      → Input signal
o_*      → Output signal
*_valid  → Data valid/enable signal
*_rsb_n  → Reset (active low, asynchronous)
clk      → Clock signal
*_clear  → Clear/reset counter
*_enable → Gate/enable signal
*_done   → Completion pulse
*_d*     → Delayed register (d1=1-cycle delay, d2=2-cycle, etc.)
```

### Standard Port Widths
| Name | Width | Format | Typical Load |
|------|-------|--------|--------------|
| RGB color | 24-bit | [23:16]=B, [15:8]=G, [7:0]=R (BGR) | Per-pixel |
| Single channel | 8-bit | U8 (unsigned byte) | Per-pixel feature |
| Address | 14-18 bit | Unsigned address pointer | Linear frame traversal |
| Q16 fixed-point | 24-bit | Fixed-point, upper 16 bits = integer part | Reciprocals |
| Q0.8 parameters | 8-bit | Fixed-point, upper 0 bits = integer part | Algorithm scaling |

---

## Algorithm Parameters

### Recommended Default Values

```verilog
// Transmission scaling (Q0.8 format)
OMEGA_Q8 = 8'd255        // ≈ 1.0 (aggressive dehaze)
          = 8'hF3        // 243 ≈ 0.95 (common value)
          
// Transmission minimum threshold
T_MIN = 8'd15            // ≈ 0.06 in [0..1] scale
      = 8'd26            // ≈ 0.10 (more conservative)

// Adaptive SE lambda parameter (Q0.8)
LAMBDA_Q8 = 8'd51        // ≈ 0.20 (about 1/5)
          = 8'd64        // ≈ 0.25 (exactly 1/4)

// Sky recognition threshold
A0 = 8'd150              // Dark channel threshold to classify sky

// Image dimensions (parametrizable)
IMG_WIDTH = 128          // Min supported
IMG_HEIGHT = 128
IMG_WIDTH = 512          // Max typical
IMG_HEIGHT = 512
IMG_WIDTH = 1024         // With sufficient BRAM

// Address width (automatically derived)
ADDR_WIDTH = log2(IMG_WIDTH * IMG_HEIGHT)
           = 14 (for 128×128)
           = 18 (for 512×512)
```

---

## Register Offsets & Bit Positions

### IPU_CTRL (0x00)
```
Bit 0: EN           - IPU enable (default: 0)
Bit 1: START        - Start frame processing (pulse, auto-clear)
Bit 2: CONT_MODE    - Continuous mode (default: 0)
Bits [31:3]: Reserved
```

### IPU_STATUS (0x04, Read-Only)
```
Bit 0: IDLE         - 1 when FSM in S_IDLE
Bit 1: BUSY         - 1 when FSM processing
Bit 2: DONE         - 1 when frame complete
Bit 3: ERROR        - 1 if fatal error detected
Bits [31:4]: Reserved
```

### IPU_IRQ_EN (0x30)
```
Bit 0: DONE_IRQ_EN  - Enable interrupt on frame done
Bits [31:1]: Reserved
```

### IPU_IRQ_STATUS (0x34, Write-1-to-Clear)
```
Bit 0: DONE_IRQ     - Frame done interrupt pending
Bits [31:1]: Reserved
```

### IPU_DEBUG (0x38, Read-Only)
```
Bits [3:0]: FSM_STATE
  0x0: S_IDLE
  0x1: S_LOAD
  0x2: S_DARK
  0x3: S_SKY
  0x4: S_TRANS
  0x5: S_ADC
  0x6: S_RECOVERY
  0x7: S_DONE
Bits [31:4]: Reserved
```

---

## Data Flow Connectivity Matrix

### Signals Flowing Between Major Blocks

```
Input Stream (ipu_control_logic → haze_removal_core):
  dark_enable       ──→ enable dark_channel stage
  sky_enable        ──→ enable sky recognition
  trans_enable      ──→ enable transmission calculation
  adc_enable        ──→ enable ADC estimation
  recovery_enable   ──→ enable final recovery
  bank_*_*          ──→ control bank ping-pong

Inter-Pipeline (within haze_removal_core):
  dark_ch           ─→ atmospheric_light (accumulator)
  dark_ch           ─→ sky_recognition (pilot)
  A_R/G/B           ─→ estimate_transmission (normalization)
  o_tx              ─→ bank_pingpong_stream (write)
  o_tx (from bank)  ─→ adc_estimation (as MC input)
  adc_pix           ─→ t_compute_fuse (as dark input)
  A_R/G/B           ─→ t_compute_fuse (fusing)
  i_src_rgb         ─→ t_compute_fuse (source pixel)

Output to System:
  done pulses       ←─ haze_removal_core
  post_img          ←─ final output (from recovery)
  ipu_irq           ←─ interrupt request (on done)
```

---

## Timing Quick Reference

### Minimum Cycle Counts (from START pulse)

| Milestone | Cycles | Notes |
|-----------|--------|-------|
| Reach S_DARK | 1 | Next cycle after START pulse |
| Complete dark_channel | IMG_WIDTH×IMG_HEIGHT | Streaming dark_ch output |
| Reach S_TRANS | +2-3 | After SKY stage |
| Complete transmission | IMG_WIDTH×IMG_HEIGHT | Write all TX values to bank |
| Reach S_ADC | +1 | Bank swap on first cycle |
| ADC warmup (first valid) | 4*IMG_WIDTH+9 | Line buffer fill + pipeline |
| Complete ADC | Variable | Depends on full window count |
| Reach S_RECOVERY | +1 | After ADC done |
| Complete recovery output | IMG_WIDTH×IMG_HEIGHT | Write all pixels to IMG_OUT |
| Reach S_DONE | +1 | After writer_done |
| **Total Minimum** | ~8*IMG_WIDTH+256 | For 128: ~1,300 cycles ≈ 13 µs @ 100MHz |

### Practical Frame Times (128×128 @ 100 MHz)
```
DARK stage:           16,384 cycles ≈ 163.8 µs
SKY stage:            ~5 cycles ≈ 0.05 µs
TRANS stage:          16,384 cycles ≈ 163.8 µs
ADC stage:            ~23,000 cycles ≈ 230 µs (warmup + processing)
RECOVERY stage:       16,384 cycles ≈ 163.8 µs
─────────────────────────────────────────────
Total per frame:      ~72,000 cycles ≈ 720 µs

@ 200 MHz:           360 µs per frame
@ 100 MHz:           720 µs per frame (~1.4 kfps)
```

---

## File Dependency Graph

```
haze_removal_core.sv
  ├─ atm_light_coarse_tx.sv
  │   ├─ dark_channel.sv
  │   │   └─ src_min.sv
  │   ├─ grayscale.sv
  │   ├─ atmospheric_light.sv
  │   ├─ sky_recognition.sv
  │   ├─ estimate_transmission.sv
  │   │   ├─ invA_lut_q16.sv
  │   │   ├─ norm_channel_q16.sv
  │   │   ├─ min3_u8.sv
  │   │   ├─ spatial_min3x3.sv
  │   │   │   └─ search_block_min.sv
  │   │   └─ omega_clamp_t.sv
  │   └─ bank_pingpong_stream.sv
  │       ├─ bank_bram.sv (×2)
  │       └─ frame_linear_counter.sv
  │
  ├─ adc_estimation.sv (5-stage pipeline)
  │   ├─ adc_line_buffer_5x5.sv (×2)
  │   ├─ adc_pixel_distance.sv
  │   ├─ adc_path_length.sv
  │   ├─ adc_rlimit_compute.sv
  │   └─ adc_ase_masked_min.sv
  │
  └─ t_compute_fuse.sv
      ├─ t_computing.sv
      └─ fusing.sv

ipu_soc.sv / ipu_top.sv
  ├─ haze_removal_core.sv (above)
  ├─ ipu_control_logic.sv
  ├─ img_in_bram.v (mem/)
  ├─ img_out_bram.v (mem/)
  ├─ img_tmp_bram.v (mem/)
  └─ ipu_addr_map.vh
```

---

## Software Integration Checklist

### Before Hardware Processing
- [ ] Load input image into IMG_IN BRAM (via system Port A)
- [ ] Set IPU_IMG_WIDTH, IPU_IMG_HEIGHT, IPU_IMG_STRIDE
- [ ] Optionally set PARAM_0, PARAM_1, PARAM_2 (reserved for future)
- [ ] Set correct IMG_FORMAT (0: RGB888, 1: BGR888)
- [ ] Enable IRQ if using interrupt-driven flow: IPU_IRQ_EN[0]=1

### During Processing
- [ ] Assert START in IPU_CTRL
- [ ] Monitor FSM state via IPU_DEBUG[3:0] (optional)
- [ ] Poll IPU_STATUS[2] (DONE) or wait for ipu_irq interrupt
- [ ] (Optional: Continuous mode) set IPU_CTRL[2]=1 before START

### After Processing
- [ ] Read output from IMG_OUT BRAM (via system Port A)
- [ ] Clear interrupt flag: IPU_IRQ_STATUS[0]=1 (W1C)
- [ ] Check IPU_STATUS[3] for error flag
- [ ] Optionally read IPU_DEBUG for diagnostic info

---

## Performance Optimization Tips

### For Maximum Throughput
1. **Continuous Mode**: Set IPU_CTRL[2]=1 before START
   - Avoids S_IDLE→S_LOAD overhead between frames
   - Saves ~1-2% total time

2. **Pipelined Register Access**: 
   - Load next frame's data while current completes
   - Use asynchronous FIFO between CPU and IPU

3. **Parameter Tuning**:
   - T_MIN: Lower → more aggressive (sharper), artifacts possible
   - OMEGA_Q8: Higher → stronger haze removal, conservation loss
   - LAMBDA_Q8: Tuning sweet spot ≈ 0.15-0.25

### For Low Power
1. **Image Size**: ADC overhead is 4*WIDTH terms
   - Smaller image → less line buffer depth → lower power
   - 64×64: ~100 mW
   - 128×128: ~150 mW
   - 512×512: ~400+ mW

2. **Frequency Scaling**: ADC latency increases linearly with pixel stream rate
   - Lower clock → proportionally fewer power

3. **Selective Stages**: Can disable ADC entirely (adc_enable=0)
   - Uses only coarse transmission (faster, less accurate)

---

## Common Issues & Solutions

### Issue: Output all zeros / black image
**Causes**:
- BRAM not loaded correctly (check write addresses)
- IPU_FSM not starting (START pulse too short)
- Wrong IMG_FORMAT setting

**Solution**:
- Verify BRAM data with external read before START
- Extend START pulse to 2+ cycles
- Confirm IMG_FORMAT matches actual input (BGR vs RGB)

### Issue: Excessive haze removal / artifacts
**Causes**:
- OMEGA_Q8 too large (>200)
- T_MIN too small (<10)
- Test image already mostly clear

**Solution**:
- Reduce OMEGA_Q8 to ~150-200
- Increase T_MIN to 30-50
- Test with known hazy image

### Issue: Slow processing / timeout
**Causes**:
- Large image size (ADC line buffer warmup can be 2K+ cycles)
- Polling interval too frequent (CPU cache thrashing)
- Clock too slow for continuous stream

**Solution**:
- Use larger IMG_WIDTH in parameters (better latency overlap)
- Poll at ~10-100 ms intervals
- Ensure clock ≥100 MHz for 128×128 real-time

### Issue: BRAM contention errors
**Causes**:
- System actively reading IMG_OUT while IPU writing
- Write pointer collision in bank_pingpong

**Solution**:
- Use dual-port BRAM (always available in ipu_soc)
- Never force read during S_RECOVERY (IPU owns IMG_OUT)

---

## Testing Commands (Simulation)

### Basic Testbench Flow
```verilog
// 1. Initialize
$display("Starting IPU test at %t", $time);
repeat(10) @(posedge clk);

// 2. Load test image
for (int i=0; i<NUM_PIXELS; i++) begin
  img_in_sys_en = 1;
  img_in_sys_we = 1;
  img_in_sys_addr = i;
  img_in_sys_wdata = test_pattern[i];
  @(posedge clk);
end
img_in_sys_en = 0;

// 3. Trigger IPU
reg_wr_en = 1;
reg_addr = `IPU_CTRL;
reg_wdata = 32'h0000_0003;  // EN=1, START=1
@(posedge clk);
reg_wr_en = 0;

// 4. Wait for completion
repeat(20000) @(posedge clk);  // Typical worst-case
if ((read_reg(`IPU_STATUS) & 'h04) == 0) begin
  $error("IPU did not complete!");
  $finish(1);
end

// 5. Compare output
img_out_sys_en = 1;
for (int i=0; i<NUM_PIXELS; i++) begin
  img_out_sys_addr = i;
  @(posedge clk);
  actual = img_out_sys_rdata;
  expected = golden[i];
  if (actual !== expected) begin
    $warning("Mismatch @ pixel %d: got %h, exp %h", i, actual, expected);
  end
end
```

---

**End of Quick Reference Guide**

