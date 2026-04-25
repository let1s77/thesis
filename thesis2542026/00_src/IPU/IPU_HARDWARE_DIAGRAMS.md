# IPU Hardware: Diagrams, Data Flow, and Examples

This document provides visual representations, detailed data flows, and concrete processing examples for the IPU haze removal hardware.

---

## 1. System Architecture Diagram

```
┌──────────────────────────────────────────────────────────────┐
│                        SoC Top Level                          │
│  (Single-Cycle RISC-V + Peripherals + IPU)                   │
└──────────────────────────────────────────────────────────────┘
                              │
                          APB Bus
                              │
         ┌────────────────────┴────────────────────┐
         │                                         │
    ┌────▼──────────────────────────────────────┐ │
    │   ipu_soc (APB Slave Wrapper)             │ │
    │ ┌──────────────────────────────────────┐ │ │
    │ │ ipu_control_logic (7-State FSM)      │ │ │
    │ │ - Orchestrates 5 processing phases   │ │ │
    │ │ - Manages APB registers              │ │ │
    │ │ - Generates IRQ on completion        │ │ │
    │ └──────────────────────────────────────┘ │ │
    │     │                       │             │ │
    │     ▼                       ▼             │ │
    │ ┌─────────────┐         ┌──────────────┐ │ │
    │ │ haze_removal│         │ img_in_bram  │ │ │
    │ │   _top      │◄─────────input RGB data │ │ │
    │ │ (main       │         └──────────────┘ │ │
    │ │ datapath    │                          │ │
    │ │ pipeline)   │         ┌──────────────┐ │ │
    │ │             │        │ img_out_bram │ │ │
    │ │ ├─ dark_    │        │              │ │ │
    │ │ │  channel  │ ──────▶│ output RGB   │ │ │
    │ │ │           │         └──────────────┘ │ │
    │ │ ├─ atm_     │                          │ │
    │ │ │  light    │         ┌──────────────┐ │ │
    │ │ │           │        │ img_tmp_bram │ │ │
    │ │ ├─ trans_   │        │ (transmission│ │ │
    │ │ │  est      │ ◄─────▶│  maps)       │ │ │
    │ │ │           │         └──────────────┘ │ │
    │ │ ├─ adc_     │                          │ │
    │ │ │  est      │                          │ │
    │ │ │           │                          │ │
    │ │ └─ fusion   │                          │ │
    │ │ (recovery)  │                          │ │
    │ └─────────────┘                          │ │
    │                                          │ │
    │ ┌──────────────────────────────────────┐ │ │
    │ │ frame_linear_counter                 │ │ │
    │ │ (coordinates: x, y, line_buf addr)   │ │ │
    │ └──────────────────────────────────────┘ │ │
    └──────────────────────────────────────────┘ │
         │                                        │
         └────────────────────────────────────────┘
```

---

## 2. FSM State Diagram

```
    ┌──────────────┐
    │              │
    │    IDLE      │◄─────────────────────┐
    │              │                      │
    └──────┬───────┘                      │
         │ (APB_CTRL[0]=1, START=1)      │
         │                              RECOVERY
         ▼                          Phase Complete
    ┌──────────────┐                      │
    │              │                      │
    │    LOAD      │ ──────────────────────
    │ (read BRAM)  │
    │              │
    └──────┬───────┘
         │ (~2048 cycles)
         ▼
    ┌──────────────┐
    │              │
    │    DARK      │─────────┐ (~2000 cycles)
    │ (dark        │         │
    │  channel &   │         │
    │  atm light)  │         │
    │              │         │
    └──────┬───────┘         │
         │ ◄────────────────┘
         ▼
    ┌──────────────┐
    │              │
    │    SKY       │─────────┐ (~500 cycles)
    │ (sky mask)   │         │
    │              │         │
    └──────┬───────┘         │
         │ ◄────────────────┘
         ▼
    ┌──────────────┐
    │              │
    │    TRANS     │─────────┐ (~3000 cycles)
    │ (coarse      │         │ (write ping buffer)
    │  transmission)          │
    │              │         │
    └──────┬───────┘         │
         │ ◄────────────────┘
         ▼
    ┌──────────────┐
    │              │
    │    ADC       │─────────┐ (~15000 cycles)
    │ (refined     │         │ (5-stage pipeline
    │  dark        │         │  read ping, write pong)
    │  channel &   │         │
    │  trans)      │         │
    │              │         │
    └──────┬───────┘         │
         │ ◄────────────────┘
         ▼
    ┌──────────────┐
    │              │
    │  RECOVERY    │─────────┐ (~3000 cycles)
    │ (final dehaze           │ (read pong,
    │  & output)  │         │ write output BRAM)
    │              │         │
    └──────┬───────┘         │
         │ ◄────────────────┘
         │ (IRQ asserted)
         └──────────────────────▶ DONE ──┐
                                  ▲      │
                                  └──────┘
```

---

## 3. Data Flow Diagram (Simplified)

```
Input RGB Frame (128×128 pixels, 8-bit per channel)
        │
        ▼
┌──────────────────────┐
│  GRAYSCALE           │ Convert RGB → Gray for sky detection
│  (avg of R/G/B)      │ Output: 8-bit grayscale
└──────────────────────┘
        │
        ├────────────────────┬──────────────────────┐
        │                    │                      │
        ▼                    ▼                      ▼
┌──────────────────┐ ┌──────────────────┐ ┌──────────────────┐
│ DARK CHANNEL     │ │ SKY RECOGNITION  │ │ ATMOSPHERIC LIGHT│
│ (min of RGB)     │ │ (grayscale-based)│ │ (top 0.1% pixels)│
│ Output: 8-bit    │ │ Output: mask     │ │ Output: 3× 8-bit │
└──────────────────┘ └──────────────────┘ │ (A_r,A_g,A_b)    │
        │                    │             └──────────────────┘
        │                    │                      │
        │                    ▼                      │
        │            ┌──────────────────┐           │
        │            │ TRANSMISSION EST │◄──────────┘
        │            │ (norm RGB by A,  │
        │            │  min & clamp)    │
        │            │ Output: 8-bit    │
        │            └──────────────────┘
        │                    │
        │                    ▼
        │      ┌─────────────────────────┐
        │      │ TRANSMISSION STORAGE    │
        │      │ (write coarse, read in  │
        │      │  ADC phase)             │
        │      └─────────────────────────┘
        │                    │
        ├────────────┬───────┴─────────┐
        │            │                 │
        │            ▼                 ▼
        │     ┌────────────────────────────────────┐
        │     │ ADC ESTIMATION (5-stage pipeline)  │
        │     │ 1. Line buffers (5×5 windows)     │
        │     │ 2. Pixel distance                 │
        │     │ 3. Path length                    │
        │     │ 4. r_limit computation            │
        │     │ 5. ASE-masked minimum            │
        │     │ Output: refined dark channel (8b) │
        └─────┘     └────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────────┐
                    │ TRANSMISSION FUSION │
                    │ (blend coarse/ADC,  │
                    │  apply sky mask)    │
                    │ Output: 8-bit final │
                    └─────────────────────┘
                              │
                              ▼
                    ┌─────────────────────┐
                    │ HAZE REMOVAL        │
                    │ J=(I-A)/t + A       │
                    │ Output: 24-bit RGB  │
                    └─────────────────────┘
                              │
                              ▼
                    Output Dehazed Frame
```

---

## 4. Detailed Example: Processing a Hazy Pixel

### Input Image Region
```
Hazy input region (5×5 patch):
┌────────────────────────────────────┐
│ R:180 G:180 B:180│ RGB-Hazy pixel  │
├────────────────────────────────────┤
│ Typical daylight, low visibility   │
│ Atmospheric light A ≈ (220, 220, 220)
└────────────────────────────────────┘
```

### Step 1: Dark Channel
```
Input pixel: R=180, G=180, B=180
Dark channel: min(180, 180, 180) = 180
(Very hazy → high dark channel value)
```

### Step 2: Atmospheric Light Estimation
```
Over 128×128 frame:
- Collect dark channel values
- Find top 0.1% brightest pixels (≈16 pixels)
- Average their original RGB:
  A_r ≈ 220
  A_g ≈ 220
  A_b ≈ 220
  (Daylight atmosphere)
```

### Step 3: Coarse Transmission Estimation
```
For pixel (R=180, G=180, B=180), A=(220, 220, 220):

1. Normalize by A:
   norm_r = (180 * invA_lut[220]) >> 16
          ≈ (180 * 0.8182) = 147.3 ≈ 147
   norm_g ≈ 147
   norm_b ≈ 147

2. Find minimum norm: min_norm = 147

3. Apply OMEGA (0xF3 ≈ 0.953):
   coarse_t = 255 - (OMEGA * 147) >> 8
            = 255 - (243 * 147) >> 8
            = 255 - 111
            = 144

4. Clamp to T_MIN=26:
   final_coarse_t = max(144, 26) = 144
   (Transmission ≈ 56% of light recovered)
```

### Step 4: Adaptive Dark Channel (ADC) Refinement
```
5×5 window around pixel:
┌──────────────────────────────┐
│ Dark_ch values in 5×5 region:│
│ ┌──────────────┐             │
│ │ 180 180 180  │             │
│ │ 180 175 180  │ (neighbor)  │
│ │ 180 180 180  │             │
│ │ 180 180 178  │             │
│ │ 180 180 180  │             │
│ └──────────────┘             │
│ Min in region: 175           │
└──────────────────────────────┘

ADC processing pipeline:
1. Pixel distance: dist = min(row, col, H-row, W-col)
   Example: dist = 30 pixels from edge

2. Path length: path = dist * LAMBDA ≈ 30 * 0.5 = 15

3. r_limit: r_limit = LAMBDA * path ≈ 0.5 * 15 = 7.5 ≈ 7

4. ASE-masked minimum in 5×5:
   valid_darks = [d for d in dark_region if d < r_limit]
   If r_limit=7 is too restrictive, use edge values
   adc_dark ≈ min_valid ≈ 175

5. ADC transmission:
   adc_t = 255 - (OMEGA * adc_dark) >> 8
         ≈ 255 - (243 * 175) >> 8
         ≈ 255 - 167
         ≈ 88
   Clamp: adc_t = max(88, 26) = 88
```

### Step 5: Transmission Fusion
```
Blend coarse_t (144) and adc_t (88) with sky mask:

Sky mask = 0 (not a sky pixel)
Final_t = blend(coarse_t=144, adc_t=88, sky_mask=0)
        ≈ mix toward stronger adc_t
        ≈ 100 (balanced)

Clamp: final_t = max(min(100, 255), 26) = 100
```

### Step 6: Haze Removal (Recovery)
```
Dehaze formula: J = (I - A) / t + A

For pixel (R=180, G=180, B=180):
  J_r = (180 - 220) / (100/255) + 220
      = (-40) / 0.392 + 220
      = -102 + 220
      = 118

Similarly J_g ≈ 118, J_b ≈ 118

Output: (118, 118, 118) — darker but clearer (dehazed)
```

### Result
```
Input (hazy):  RGB(180, 180, 180)  — Light gray, low visibility
Output (clear): RGB(118, 118, 118) — Medium gray, better detail
```

---

## 5. ADC 5-Stage Pipeline Diagram

```
Input: Original RGB frame + Coarse transmission
        │
        ▼
┌─────────────────────────────────────┐
│ Stage 1: Line Buffers (5×5)        │
│ - Buffer 5 rows of transmission    │
│ - Enable random access to 5×5      │
│ Latency: 0-4 cycles (warmup)       │
└─────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────┐
│ Stage 2: Pixel Distance            │
│ - dist = min(row, col, H-row, W-col)
│ Latency: 1 cycle per pixel        │
└─────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────┐
│ Stage 3: Path Length               │
│ - path = dist * scale_factor       │
│ Latency: 2 cycles (multiply)       │
└─────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────┐
│ Stage 4: r_limit Computation       │
│ - r_limit = LAMBDA * path          │
│ Latency: 2 cycles                  │
└─────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────┐
│ Stage 5: ASE-Masked Minimum        │
│ - Find min(5×5) constrained by     │
│   r_limit mask                     │
│ Latency: 4 cycles                  │
└─────────────────────────────────────┘
        │
        ▼
Output: Refined dark channel (8-bit)
```

---

## 6. Memory Access Patterns

### 6.1 Input BRAM Read Pattern (LOAD phase)
```
Sequential read, row-by-row:
┌─────────────────────────────────────────┐
│ img_in_bram[0]   ← Pixels 0, 1 (row 0)  │
│ img_in_bram[1]   ← Pixels 2, 3 (row 0)  │
│ ...                                      │
│ img_in_bram[63]  ← Pixels 126, 127 (row0)
│ img_in_bram[64]  ← Pixels 0, 1 (row 1)  │
│ ...                                      │
│ img_in_bram[8191]← Pixels 126, 127 (r127)
└─────────────────────────────────────────┘
Total: 128×128÷2 = 8192 BRAM addresses
```

### 6.2 Transmission Storage (Ping-Pong)
```
TRANS phase:        ADC phase:          RECOVERY phase:
Write coarse_t ─→  Read coarse_t ─→    Read adc_t
to ping buffer      from ping buffer    from pong buffer
                                        ↓
                    Compute adc_t ─→   Write to output
                    to pong buffer
```

### 6.3 Output BRAM Write Pattern (RECOVERY phase)
```
Sequential write, row-by-row:
┌─────────────────────────────────────────┐
│ img_out_bram[0]   ← Dehazed pixels 0,1  │
│ img_out_bram[1]   ← Dehazed pixels 2,3  │
│ ...                                      │
│ img_out_bram[8191]← Dehazed pixels 126,7│
└─────────────────────────────────────────┘
```

---

## 7. Timing Chart (128×128 Frame)

```
Time (µs)  Phase      Activity              Cycles   Notes
───────────────────────────────────────────────────────────
    0      LOAD       Read input BRAM      ~2,048   Sequential access
   20      DARK       Dark channel comp    ~2,000   Streaming reduction
   40      SKY        Sky mask (grayscale) ~500     Simple threshold
   45      TRANS      Coarse trans (5×5)   ~3,000   Write ping buffer
   75      ADC        5-stage pipeline     ~15,000  Warmup + steady-state
   225     RECOVERY   Dehaze + write out   ~3,000   Parallel compute
   255     DONE       IRQ asserted         —        Ready for next frame
───────────────────────────────────────────────────────────
```

---

## 8. Bit-Width Tracking Through Pipeline

```
Stage                   Data      Width    Notes
────────────────────────────────────────────────────────
Input RGB              RGB        24-bit   8-bit × 3
Dark channel           Value      8-bit    min(R,G,B)
Normalized (norm_c)    Value      16-bit   Fixed-point result
Min norm               Value       8-bit    min(3 channels)
Transmission map       Value       8-bit    0-255 (0→opaque, 255→clear)
invA_lut lookup        Reciprocal  32-bit   Q15.16 format
Path length            Scaled      32-bit   Q16.16 fixed-point
r_limit                Threshold   16-bit   Clipped value
ADC dark channel       Value       8-bit    Refined min
Final transmission     Value       8-bit    0-255 (clamped to T_MIN)
Dehazed RGB            RGB        24-bit   (I-A)/t + A, per-channel 8-bit
Output                 RGB        24-bit   Final result
────────────────────────────────────────────────────────
```

---

## 9. Simulation Checkpoint Values

### Test Case: Uniform Haze (180,180,180) over 128×128
```
Expected values at key checkpoints:

Dark channel min: 180 (across entire frame)
Atmospheric light A: ~(220, 220, 220)
Coarse transmission: ~100-120
ADC transmission: ~80-100
Final transmission: ~95-110
Dehazed output (sample pixel): ~(120, 120, 120)

Golden files:
- 07_golden_output/dark_channel_report.txt
- 07_golden_output/atmospheric_light_report.txt
- 07_golden_output/estimate_transmission_report.txt
- 07_golden_output/purple_integration_report.txt (full integration)
```

---

## 10. Register Map Diagram

```
┌─────────────────────────────────────┐
│ IPU APB Register Map (0x00-0x3C)    │
├─────────────────────────────────────┤
│ 0x00  APB_CTRL                      │
│       [1:0] = EN, START             │
│       [2]   = RESET                 │
│                                     │
│ 0x04  APB_STATUS                    │
│       [0]   = DONE                  │
│       [3:1] = FSM_STATE             │
│                                     │
│ 0x08  IMG_WIDTH  (default: 128)     │
│ 0x0C  IMG_HEIGHT (default: 128)     │
│ 0x10  IMG_STRIDE (default: 512 B)   │
│ 0x14  SRC_ADDR   (input buffer)     │
│ 0x18  DST_ADDR   (output buffer)    │
│ 0x1C  TMP_ADDR   (trans buffer)     │
│ 0x20  IRQ_EN     (enable interrupt) │
│                                     │
│ 0x24  OMEGA_Q8   (0xF3)             │
│ 0x28  LAMBDA_Q8  (0x80)             │
│ 0x2C  T_MIN      (26)               │
│ 0x30  Reserved                      │
│ 0x34  Reserved                      │
│ 0x38  Reserved                      │
│ 0x3C  Reserved                      │
└─────────────────────────────────────┘
```

---

## 11. Typical Software Control Flow

```c
// 1. Initialize
apb_write(0x14, img_in_base);    // SRC_ADDR
apb_write(0x18, img_out_base);   // DST_ADDR
apb_write(0x1C, tmp_base);       // TMP_ADDR
apb_write(0x08, 128);            // IMG_WIDTH
apb_write(0x0C, 128);            // IMG_HEIGHT
apb_write(0x10, 512);            // IMG_STRIDE

// 2. Set algorithm parameters
apb_write(0x24, 0xF3);           // OMEGA_Q8
apb_write(0x28, 0x80);           // LAMBDA_Q8
apb_write(0x2C, 26);             // T_MIN

// 3. Enable interrupt and start
apb_write(0x20, 0x1);            // IRQ_EN
apb_write(0x00, 0x3);            // START (EN | START)

// 4. Wait for completion
while ((apb_read(0x04) & 0x1) == 0);  // Poll DONE

// 5. Read output from img_out_base
for (int i = 0; i < 128*128; i++) {
    dehazed_rgb[i] = read_bram(img_out_base + i);
}
```

---

## References

- IPU Hardware Architecture: `IPU_HARDWARE_ARCHITECTURE.md`
- Software Implementation: `03_sw/haze_removal_top_sw.py`
- Testbench Examples: `01_sim/IPU/Testbench_*_tb.sv`
- Control Logic: `00_src/IPU/ipu_control_logic.sv`
