# IPU (Image Processing Unit) - Dark Channel Prior Haze Removal Hardware Architecture

**Comprehensive Hardware Design Document**  
**Target: Complete Dehaze Pipeline for 128×128 to 512×512 Images**

---

## 1. OVERALL SYSTEM ARCHITECTURE

### 1.1 Hierarchical Structure

```
┌─────────────────────────────────────────────────────────────────┐
│                      ipu_soc (SoC Wrapper)                      │
│  Contains: Register interface + External BRAM connections       │
├─────────────────────────────────────────────────────────────────┤
│                        ipu_core / ipu_top                       │
│        Interfaces: img_in_bram, img_out_bram, img_tmp_bram      │
├──────────────────────────┬──────────────────────────────────────┤
│  ipu_control_logic       │    haze_removal_top (Datapath)       │
│  (FSM: IDLE→LOAD→       │  ┌────────────────────────────────┐   │
│   DARK→SKY→TRANS→       │  │  atm_light_coarse_tx          │   │
│   ADC→RECOVERY→DONE)    │  │  ├─ dark_channel (min RGB)     │   │
│                         │  │  ├─ grayscale (RGB→gray)       │   │
│                         │  │  ├─ atmospheric_light (max)     │   │
│                         │  │  ├─ sky_recognition (threshold)│   │
│                         │  │  ├─ estimate_transmission (t)  │   │
│                         │  │  └─ bank_pingpong_stream (BRAM)│   │
│                         │  ├─ adc_estimation (5-stage pipeline)
│                         │  │  ├─ adc_line_buffer_5x5 ×2     │   │
│                         │  │  ├─ adc_pixel_distance         │   │
│                         │  │  ├─ adc_path_length            │   │
│                         │  │  ├─ adc_rlimit_compute         │   │
│                         │  │  └─ adc_ase_masked_min         │   │
│                         │  └─ t_compute_fuse (2-stage)       │   │
│                         │     ├─ t_computing                │   │
│                         │     └─ fusing                      │   │
│                         │  └─ Output mapping                 │   │
│                         └────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 Data Flow Stages

```
INPUT (i_src_rgb: 24-bit BGR @ i_src_valid)
  ↓
[DARK STAGE]
  dark_channel → min(R,G,B)
  ↓ (1 cycle latency)
[SKY STAGE]  
  grayscale → RGB to grayscale conversion
  atmospheric_light → scan frame, find max dark_ch → A_R, A_G, A_B
  sky_recognition → gray > threshold → sky_valid, sky_flag
  ↓ (2+ cycles latency)
[TRANSMISSION STAGE]
  estimate_transmission → compute t from dark_ch and A
  bank_pingpong_stream WRITE → store t in BRAM (ping-pong)
  ↓ (0 to 4 cycles + frame delay)
[ADC STAGE]
  bank_pingpong_stream READ → load transmission for neighbors
  adc_estimation:
    ├─ line_buffer_5x5 (grayscale & MC) → build 5×5 windows
    ├─ pixel_distance → dp_total along paths
    ├─ path_length → d_lambda = spatial + lambda*dp
    ├─ rlimit_compute → r_limit = mean(d_lambda)
    └─ ase_masked_min → min(MC within ASE) = ADC
  ↓ (4+ cycles per pixel through 5-stage pipeline)
[RECOVERY STAGE]
  t_compute_fuse:
    ├─ t_computing → tx = max(1 - (dark*omega/A), tx_min)
    └─ fusing → recover = (src - A)/(t_used) + A
  ↓
OUTPUT (post_img: 24-bit BGR @ post_frame_clken)
```

### 1.3 Clock & Reset

- **Single clock domain**: `clk` (typically 100-200 MHz)
- **Asynchronous reset**: `rst_n` (active low)
- No clock domain crossing within core architecture

---

## 2. TOP-LEVEL MODULES

### 2.1 ipu_soc

**File**: `ipu_soc.sv`

**Purpose**: SoC wrapper that manages BRAM instances external to the core and arbitrates system access.

**Parameters**:
- None (parametrization inherited from ipu_core)

**Ports**:

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | Input | 1 | System clock |
| `rst_n` | Input | 1 | Async reset (active low) |
| `reg_wr_en` | Input | 1 | Register write enable |
| `reg_rd_en` | Input | 1 | Register read enable |
| `reg_addr` | Input | 32 | Register address (APB/AHB) |
| `reg_wdata` | Input | 32 | Register write data |
| `reg_rdata` | Output | 32 | Register read data |
| `img_in_sys_en` | Input | 1 | IMG_IN BRAM enable (system side) |
| `img_in_sys_we` | Input | 1 | IMG_IN BRAM write enable (system) |
| `img_in_sys_addr` | Input | 16 | IMG_IN BRAM address (word address) |
| `img_in_sys_wdata` | Input | 32 | IMG_IN BRAM write data (32-bit) |
| `img_in_sys_rdata` | Output | 32 | IMG_IN BRAM read data |
| `img_out_sys_en` | Input | 1 | IMG_OUT BRAM enable (system side) |
| `img_out_sys_we` | Input | 1 | IMG_OUT BRAM write enable (system) |
| `img_out_sys_addr` | Input | 16 | IMG_OUT BRAM address |
| `img_out_sys_wdata` | Input | 32 | IMG_OUT BRAM write data |
| `img_out_sys_rdata` | Output | 32 | IMG_OUT BRAM read data |
| `img_tmp_sys_en` | Input | 1 | IMG_TMP BRAM enable (system side) |
| `img_tmp_sys_we` | Input | 1 | IMG_TMP BRAM write enable (system) |
| `img_tmp_sys_addr` | Input | 16 | IMG_TMP BRAM address |
| `img_tmp_sys_wdata` | Input | 32 | IMG_TMP BRAM write data |
| `img_tmp_sys_rdata` | Output | 32 | IMG_TMP BRAM read data |
| `ipu_irq` | Output | 1 | Interrupt request (frame done) |

**Architecture**: Dual-port block RAMs with:
- **Port A**: System (CPU) access for loading input frames and reading output
- **Port B**: IPU core access for streaming pixel processing

**Data Width**: 32-bit (4×8-bit pixels per word) → supports 4 pixels per cycle if interleaved

---

### 2.2 ipu_top / ipu_core

**File**: `ipu_top.sv` (legacy) → `ipu_soc.sv` (modern, moves BRAM outside)

**Parameters**:
```verilog
parameter int IMG_WIDTH  = 128,
parameter int IMG_HEIGHT = 128,
parameter int ADDR_WIDTH = 14
```

**Register Map** (via APB interface):

| Register | Addr | Bits | R/W | Description |
|----------|------|------|-----|-------------|
| `IPU_CTRL` | 0x00 | [0]: EN, [1]: START, [2]: CONT_MODE | RW | Control: enable, start frame, continuous mode |
| `IPU_STATUS` | 0x04 | [0]: IDLE, [1]: BUSY, [2]: DONE, [3]: ERROR | RO | Status flags |
| `IPU_SRC_ADDR` | 0x08 | [31:0] | RW | Source frame base address (IMG_IN BRAM) |
| `IPU_DST_ADDR` | 0x0C | [31:0] | RW | Destination frame base address (IMG_OUT BRAM) |
| `IPU_TMP_ADDR` | 0x10 | [31:0] | RW | Temporary buffer base address (IMG_TMP BRAM) |
| `IPU_IMG_WIDTH` | 0x14 | [31:0] | RW | Image width (pixels) |
| `IPU_IMG_HEIGHT` | 0x18 | [31:0] | RW | Image height (pixels) |
| `IPU_IMG_STRIDE` | 0x1C | [31:0] | RW | Image stride (bytes between rows) |
| `IPU_IMG_FORMAT` | 0x20 | [31:0] | RW | Image format (0: RGB888, 1: BGR888) |
| `IPU_PARAM_0` | 0x24 | [31:0] | RW | Reserved / algorithm parameters |
| `IPU_PARAM_1` | 0x28 | [31:0] | RW | Reserved / algorithm parameters |
| `IPU_PARAM_2` | 0x2C | [31:0] | RW | Reserved / algorithm parameters |
| `IPU_IRQ_EN` | 0x30 | [31:0] | RW | Interrupt enable mask |
| `IPU_IRQ_STATUS` | 0x34 | [0]: DONE_IRQ | RW | Interrupt status |
| `IPU_DEBUG` | 0x38 | [3:0]: FSM_STATE | RO | Debug: current FSM state |
| `IPU_ID` | 0x3C | 0x49505531 | RO | Chip ID ("IPU1") |

**Control Logic FSM States**:

```
State Machine: ipu_control_logic.sv
┌──────────────────────────────────────────────────────────────┐
│ S_IDLE (4'b0000)                                              │
│  → Wait for ipu_en=1 && ipu_start=1                           │
│  → Transition: enter_load → S_LOAD                            │
└──────────────────────────────────────────────────────────────┘
                           ↓
┌──────────────────────────────────────────────────────────────┐
│ S_LOAD (4'b0001)                                               │
│  Task: Clear banks, prepare for frame processing              │
│  Outputs: bank_wr_clear=1, bank_rd_clear=1                    │
│  Duration: 1 cycle                                             │
│  → Transition: automatic → S_DARK                             │
└──────────────────────────────────────────────────────────────┘
                           ↓
┌──────────────────────────────────────────────────────────────┐
│ S_DARK (4'b0010)                                               │
│  Task: stream input frame through dark_channel               │
│  Outputs: dark_enable=1, reader_start=1 (first entry)        │
│  Duration: IMG_WIDTH * IMG_HEIGHT cycles                     │
│  → Transition: reader_done=1 → S_SKY                         │
└──────────────────────────────────────────────────────────────┘
                           ↓
┌──────────────────────────────────────────────────────────────┐
│ S_SKY (4'b0011)                                                │
│  Task: sky_recognition (already pipelined, no reader needed)  │
│  Outputs: sky_enable=1                                        │
│  Duration: 2+ cycles (for atmospheric_light frame_end pulse)  │
│  → Transition: sky_done=1 → S_TRANS                          │
└──────────────────────────────────────────────────────────────┘
                           ↓
┌──────────────────────────────────────────────────────────────┐
│ S_TRANS (4'b0100)                                              │
│  Task: estimate_transmission (write TX to bank)               │
│  Outputs: trans_enable=1, reader_start=1 (re-read frame)     │
│  Actions: bank_wr_clear=1 (on enter), reader starts           │
│  Duration: IMG_WIDTH * IMG_HEIGHT cycles                      │
│  → Transition: reader_done=1 → S_ADC                         │
└──────────────────────────────────────────────────────────────┘
                           ↓
┌──────────────────────────────────────────────────────────────┐
│ S_ADC (4'b0101)                            [MAIN COMPUTE]    │
│  Task: adc_estimation (adaptive dark channel)                │
│  Outputs: adc_enable=1                                        │
│  Actions: bank_swap=1 (on enter), bank_rd_clear=1×2 cycles  │
│           bank_rd_en=1 after swap (neighbor TX data)          │
│  Duration: ADC pipeline ~20..50 cycles after TX written      │
│  → Transition: adc_done=1 → S_RECOVERY                       │
└──────────────────────────────────────────────────────────────┘
                           ↓
┌──────────────────────────────────────────────────────────────┐
│ S_RECOVERY (4'b0110)                    [FINAL SYNTHESIS]    │
│  Task: t_compute_fuse (transmission computation + fusion)    │
│  Outputs: recovery_enable=1, reader_start=1, writer_start=1  │
│  Duration: IMG_WIDTH * IMG_HEIGHT cycles                      │
│  → Transition: recovery_done=1 && writer_done=1 → S_DONE    │
└──────────────────────────────────────────────────────────────┘
                           ↓
┌──────────────────────────────────────────────────────────────┐
│ S_DONE (4'b0111)                                              │
│  Task: Assert done, optionally go to S_LOAD if cont_mode=1   │
│  Outputs: done=1, ipu_irq=1 (if irq_en[0]=1)                │
│  Duration: 1 cycle                                             │
│  → Transition: S_IDLE (or loop if continuous mode)            │
└──────────────────────────────────────────────────────────────┘
```

**Overall Processing Flow Timeline (128×128 image)**:
```
Cycle 0:       Set registers, assert START
Cycle 1-2:     S_LOAD: clear banks
Cycle 3:       S_DARK: reader starts reading input frame
Cycle 3-16387: dark_channel processes frame (16K ≈ 128×128)
Cycle 16388:   S_SKY: atmospheric_light finalizes A
Cycle 16389:   S_TRANS: reader starts 2nd pass, estimate_transmission writes TX
Cycle 16389-32767: bank_pingpong writes transmission map
Cycle 32768:   S_ADC: ADC pipeline processes 5×5 windows (with delays)
Cycle ~35000:  adc_done pulse
Cycle ~35001:  S_RECOVERY: t_compute_fuse reads ADC, final recovery
Cycle 35001-51385: output frame written to IMG_OUT BRAM
Cycle 51386:   S_DONE: assert done, ipu_irq
```

---

## 3. CORE PROCESSING PIPELINE MODULES

### 3.1 haze_removal_top / haze_removal_core

**File**: `haze_removal_top.sv`, `haze_removal_core.sv`

**Purpose**: Top-level datapath wrapper that instantiates all processing blocks and orchestrates data flow.

**Parameters**:
```verilog
parameter int IMG_WIDTH  = 128,           // Image width
parameter int IMG_HEIGHT = 128,           // Image height
parameter int ADDR_WIDTH = 14,            // log2(WIDTH*HEIGHT)
parameter int ADC_PICK_INDEX = 1,         // ADC bank selection
parameter logic [7:0] OMEGA_Q8 = 8'd255,  // Transmission scaling (Q0.8)
parameter logic [7:0] T_MIN    = 8'd15,   // Minimum transmission threshold
parameter logic [7:0] LAMBDA_Q8 = 8'd51   // Lambda parameter for ASE (Q0.8, ~0.2)
```

**Top-level Ports**:

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | Input | 1 | System clock |
| `rst_n` | Input | 1 | Async reset |
| `i_src_valid` | Input | 1 | Input RGB stream valid |
| `i_src_frame_start` | Input | 1 | Frame start pulse |
| `i_src_frame_end` | Input | 1 | Frame end pulse |
| `i_src_rgb` | Input | 24 | Input color (24-bit BGR) |
| `dark_enable` | Input | 1 | Enable dark channel stage |
| `sky_enable` | Input | 1 | Enable sky recognition stage |
| `trans_enable` | Input | 1 | Enable transmission stage |
| `adc_enable` | Input | 1 | Enable ADC estimation stage |
| `recovery_enable` | Input | 1 | Enable final recovery stage |
| `bank_swap` | Input | 1 | Swap TX bank ping-pong |
| `bank_wr_clear` | Input | 1 | Clear TX write counter |
| `bank_rd_clear` | Input | 1 | Clear TX read counter |
| `bank_rd_en` | Input | 1 | Enable TX bank read |
| `dark_done` | Output | 1 | Dark channel stage complete |
| `sky_done` | Output | 1 | Sky recognition stage complete |
| `trans_done` | Output | 1 | Transmission stage complete |
| `adc_done` | Output | 1 | ADC estimation stage complete |
| `recovery_done` | Output | 1 | Recovery stage complete |
| `post_frame_vsync` | Output | 1 | Output VSYNC (frame sync) |
| `post_frame_href` | Output | 1 | Output HREF (line sync) |
| `post_frame_clken` | Output | 1 | Output pixel clock enable |
| `post_img` | Output | 24 | Output color (24-bit BGR) |

**Sub-Module Instances**:
1. **atm_light_coarse_tx** — Dark channel, atmospheric light, sky recognition, coarse transmission
2. **adc_estimation** — Adaptive dark channel (5-stage pipeline)
3. **t_compute_fuse** — Final transmission + haze recovery

---

### 3.2 atm_light_coarse_tx

**File**: `atm_light_coarse_tx.sv`

**Purpose**: First-pass haze removal: compute atmospheric light, sky mask, and coarse transmission. Stores transmission in dual-port BRAM for ADC neighboring access.

**Parameters**:
```verilog
parameter int IMG_WIDTH  = 128,
parameter int IMG_HEIGHT = 128,
parameter int ADDR_WIDTH = 14,
parameter logic [7:0] OMEGA_Q8 = 8'hFF,
parameter logic [7:0] T_MIN    = 8'd15
```

**Input/Output Ports** (as shown in haze_removal_core instantiation):

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| `i_valid` | In | 1 | Pixel stream valid |
| `i_color` | In | 24 | Input RGB (BGR format) |
| `i_frame_start`, `i_frame_end` | In | 1 | Frame boundaries |
| `i_A0` | In | 8 | Sky recognition threshold |
| `i_use_dark` | In | 1 | Select dark_ch (1) or gray (0) for sky test |
| `i_use_sky` | In | 1 | Override transmission with i_t_sky if sky pixel |
| `i_t_sky` | In | 8 | Transmission value for sky regions |
| `i_bank_swap`, `i_bank_wr_clear`, `i_bank_rd_clear`, `i_bank_rd_en` | In | 1 | Bank control |
| `o_A_R`, `o_A_G`, `o_A_B` | Out | 8 | Atmospheric light RGB (results of Pass 1) |
| `o_A_valid` | Out | 1 | A valid (asserted after frame_end) |
| `o_dark_valid`, `o_dark_ch` | Out | 1,8 | Dark channel RGB min |
| `o_sky_valid`, `o_sky` | Out | 1,1 | Sky recognition result |
| `o_tx_valid`, `o_tx` | Out | 1,8 | Transmission (stored in bank) |
| `o_bank_rd_data`, `o_bank_rd_addr` | Out | 8,ADDR_WIDTH | Bank read port |
| `o_bank_wr_sel`, `o_bank_rd_sel` | Out | 1,1 | Bank selection (debug) |

**Sub-Module Pipeline**:

```
Cycle N    → Input stream: i_valid, i_color[N]
            ↓
Cycle N+1  → dark_channel (1-cycle latency)
            ↓
Cycle N+1  → grayscale (RGB → gray)
            ↓
Cycle N+2  → sky_recognition (compares gray/dark_ch > i_A0)
            ↓
Cycle N+2  → estimate_transmission (computes t from dark_ch, A)
            ↓
Cycle N+3  → bank_pingpong_stream (writes t to BRAM)
            ↓
Cycle +3   ← Output register: o_tx_valid, o_tx (and to bank)
```

**Sub-Modules**:
1. **dark_channel** (1-cycle)
2. **grayscale** (1-cycle)
3. **atmospheric_light** (frame-level, outputs A after frame_end)
4. **sky_recognition** (1-cycle after grayscale)
5. **estimate_transmission** (2-3 cycles)
6. **bank_pingpong_stream** (double-buffered TX storage)

---

### 3.3 adc_estimation

**File**: `adc_estimation.sv`

**Purpose**: Adaptive dark channel estimation using structuring element mask. 5-stage pipelined architecture matching Python algorithm.

**Parameters**:
```verilog
parameter int IMG_WIDTH  = 128,
parameter int IMG_HEIGHT = 128,
parameter logic [7:0] LAMBDA_Q8 = 8'd51  // λ ≈ 0.2 in Q0.8
```

**Ports**:

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `i_enable` | Input | 1 | ADC block enable |
| `i_gray_valid`, `i_gray_pix` | Input | 1,8 | Grayscale pilot stream |
| `i_mc_valid`, `i_mc_pix` | Input | 1,8 | Minimum channel (TX) stream |
| `o_valid`, `o_adc_pix` | Output | 1,8 | ADC output stream |
| `o_done` | Output | 1 | Frame complete pulse |

**5-Stage Pipeline Breakdown**:

```
Stage 0: Line Buffer (Latency: 4*WIDTH + 4 cycles for warmup)
  ├─ Input: Single-pixel stream (gray & MC)
  ├─ Output: 5×5 windows (25 pixels each)
  ├─ Internal: 4 line buffers per stream + 5-cycle shift registers
  └─ Valid: gray_win_valid, mc_win_valid (pipelined)

Stage 1: Pixel Distance (1-cycle pipeline)
  ├─ Input: 5×5 gray window
  ├─ Algorithm: dp_total = abs diff along fixed edge paths
  ├─ Output: 25 × [8:0] (9-bit dp per position, max 510)
  └─ Latency: 1 cycle from window input

Stage 2: Path Length (1-cycle pipeline)
  ├─ Input: 25 dp values
  ├─ Algorithm: d_lambda[i,j] = spatial_dist[i,j] + LAMBDA_Q8 * dp[i,j] / 256
  ├─ Output: 25 × [9:0] (10-bit d_lambda per position)
  ├─ Spatial table (D8 metric):
  │    4 3 2 3 4
  │    3 2 1 2 3
  │    2 1 0 1 2
  │    3 2 1 2 3
  │    4 3 2 3 4
  └─ Latency: 1 cycle

Stage 3-4: r_limit Computation (2-cycle pipeline, stage 3+4)
  ├─ Input: 25 d_lambda values
  ├─ Algorithm: r_limit = mean(d_lambda) = (sum_d_lambda * 41) >> 10
  │   (41/1024 ≈ 1/25, max error <1%)
  ├─ Stage 3: Adder tree sum (registers d_lambda)
  ├─ Stage 4: Multiply by 41, shift right 10
  ├─ Output: r_limit [9:0] + delayed d_lambda [9:0] (aligned)
  └─ Latency: 2 cycles total

Stage 5: ASE Masked Min (1-cycle combinational + register)
  ├─ Input: r_limit + d_lambda (from stage 4) + MC window (delayed to align)
  │   MC delay chain: 4 cycles (to align with rlimit from stages 1+2+3+4)
  ├─ Algorithm:
  │   mask[i,j] = (d_lambda[i,j] <= r_limit)
  │   adc = min(MC[i,j] where mask[i,j]==1, or 255 if masked out)
  ├─ Output: adc_pix [7:0] (single value per 5×5 window center)
  └─ Latency: 1 cycle
```

**Total ADC Pipeline Latency**:
- Line buffer warmup: 4*WIDTH cycles (to fill 4 lines + shift register)
- Processing path: 1 + 1 + 2 + 1 = **5 cycles** after window valid
- MC delay alignment: 4 cycles
- **Total: ~4*WIDTH + 9 cycles to first o_valid**
- For 128-pixel width: ~521 cycles

**Example Data Flow for One Pixel**:
```
Cycle 0:      i_gray_valid=1, i_gray_pix=gray[0]
Cycle 1-512:  Warm-up: filling line buffers
Cycle 513:    gray_win_valid=1 (first 5×5 window ready)
Cycle 514:    pdist_valid=1 (dp_total computed)
Cycle 515:    path_valid=1 (d_lambda computed)
Cycle 516-517: rlimit_valid=1 (r_limit computed in stage 4)
Cycle 517:    (MC window delayed to align: in = cycle 513, out = cycle 513+4=517)
Cycle 518:    o_valid=1, o_adc_pix = min(MC where d_lambda <= r_limit)
```

---

### 3.4 t_compute_fuse

**File**: `t_compute_fuse.sv` (wrapper), `t_computing.sv`, `fusing.sv`

**Purpose**: Final transmission estimation and haze recovery arithmetic.

**Parameters**:
```verilog
parameter logic [7:0] OMEGA_Q8       = 8'd255,
parameter logic [7:0] TX_MIN         = 8'd15,
parameter logic [7:0] TX_WHEN_A_ZERO = 8'd15
```

**Ports**:

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| `i_valid` | In | 1 | Pixel valid |
| `i_dark` | In | 8 | Dark channel (ADC) |
| `i_A` | In | 8 | Atmospheric light max(R,G,B) |
| `i_A_r`, `i_A_g`, `i_A_b` | In | 8 | Atmospheric light per channel |
| `i_src_r`, `i_src_g`, `i_src_b` | In | 8 | Source pixel RGB |
| `o_valid` | Out | 1 | Output valid |
| `o_tx_raw`, `o_tx_used` | Out | 8 | Transmission (raw and clamped) |
| `o_out_r`, `o_out_g`, `o_out_b` | Out | 8 | Recovered pixel RGB |

**Sub-Module Pipeline**:

#### Stage 1: t_computing (1-cycle latency)
```verilog
Inputs: i_dark, i_A, OMEGA_Q8, TX_MIN
Algorithm:
  modify_A = i_dark * OMEGA_Q8          // [8:0] × [7:0] → [15:0]
  if (i_A == 0)
    tx_raw = TX_WHEN_A_ZERO
  else
    div_q = modify_A / i_A              // 16-bit ÷ 8-bit → [8:0]
    tx_tmp = 255 - div_q_sat            // clamp div_q to [0:255]
    tx_raw = (tx_tmp < 0) ? 0 : tx_tmp
  tx_used = max(tx_raw, TX_MIN)

Latency: Combinational, registered output (1 cycle)
```

#### Stage 2: fusing (1-cycle latency)
```verilog
Inputs: i_tx_raw, i_A_*, i_src_*
Algorithm:
  tx_used = max(i_tx_raw, TX_MIN)
  
  For each channel (R, G, B):
    diff_c = i_src_c - i_A_c                  // signed [8:0]
    value_tem_c = (diff_c << 8) + i_A_c * tx_used    // signed [16:0]
    out_c = value_tem_c / tx_used            // signed division → [10:0]
    // Clamp to [0..255]
    if (out_c < 0)
      result = 0
    else if (out_c > 255)
      result = 255
    else
      result = out_c[7:0]

Latency: 1 cycle (registered output)
```

**Total t_compute_fuse Latency**: 2 cycles from i_valid to o_valid

---

## 4. DARK CHANNEL ESTIMATION MODULES

### 4.1 dark_channel

**File**: `dark_channel.sv`

**Purpose**: Compute minimum of (R, G, B) per pixel, optionally with 3×3 spatial filtering.

**Parameters**:
```verilog
parameter IMG_WIDTH = 512,
parameter ENABLE_SPATIAL_FILTER = 0  // 0: simple (1-cycle), 1: 3×3 filtered
```

**Mode 0 (Simple, Latency 1)**:
```
Input:  i_valid, i_color [23:16]=B, [15:8]=G, [7:0]=R
        ↓
Comb:   r = color[7:0], g = color[15:8], b = color[23:16]
        min_rgb = min(r, g, b)
        ↓
Output: o_valid (always 1), o_dark_ch = min_rgb (registered, 1-cycle latency)
```

**Mode 1 (Spatial Filtered, Latency ~4)**:
```
Uses line buffers + 3×3 search_block_min similar to dark_channel itself.
Output valid after 2*WIDTH + 3 cycles for initially populating line buffers.
Not used in current implementation (ENABLE_SPATIAL_FILTER=0).
```

---

### 4.2 src_min (Utility)

**File**: `src_min.sv`

**Purpose**: Pure combinational min(R, G, B) → 8-bit min, registered output.

```verilog
always_comb:
  r = i_color[7:0]
  g = i_color[15:8]
  b = i_color[23:16]
  min_rg = (r < g) ? r : g
  o_min_rgb_comb = (min_rg < b) ? min_rg : b

Registered: o_min_rgb ← o_min_rgb_comb (1-cycle latency)
```

---

### 4.3 search_block_min (Utility)

**File**: `search_block_min.sv`

**Purpose**: Compute minimum of 3×3 block (9 pixels) → single value.

**Algorithm**: Pipelined 3-stage min tree
```
Stage 0 (Comb):
  m1 = min(p11, p12, p13)
  m2 = min(p21, p22, p23)
  m3 = min(p31, p32, p33)

Stage 1 (Reg):
  m1_r ← m1, m2_r ← m2, m3_r ← m3

Stage 2 (Comb):
  final_min = min(m1_r, m2_r, m3_r)

Output: Registered final_min (2-cycle latency)
```

---

## 5. ATMOSPHERIC LIGHT & SKY RECOGNITION

### 5.1 atmospheric_light

**File**: `atmospheric_light.sv`

**Purpose**: Find brightest dark channel pixel across entire frame. Used as atmospheric light A.

**Algorithm**:
```
Frame accumulator:
  For each valid pixel during frame:
    if (dark_ch > max_dark_register) OR
       (dark_ch == max_dark_register AND intensity > max_intensity_register):
      Update: max_dark, max_intensity, A_R, A_G, A_B ← pixel RGB

  On i_frame_end:
    Latch final A into output registers
    o_valid ← 1 (remains 1 until i_frame_start)
    
  On i_frame_start:
    Clear accumulators (reset for next frame)
```

**Intensity Calculation**: intensity = R + G + B (16-bit)

**Latency**: Output valid on cycle after i_frame_end (register delay)

---

### 5.2 sky_recognition

**File**: `sky_recognition.sv`

**Purpose**: Classify pixels as sky (high value) or non-sky based on threshold.

**Algorithm**:
```verilog
Inputs: i_gray (or i_dark_ch if i_use_dark=1), i_A0 (threshold)

Combinational:
  src_val = i_use_dark ? i_dark_ch : i_gray
  is_sky = (src_val > i_A0)

Output: Registered is_sky (1-cycle latency)
        o_sky_bw = is_sky ? 8'hFF : 8'h00 (for visualization/debug)
```

Typically configured with **i_A0 = 150** (arbitrary threshold, can be tuned).

---

## 6. TRANSMISSION ESTIMATION PIPELINE

### 6.1 estimate_transmission

**File**: `estimate_transmission.sv`

**Purpose**: Compute coarse transmission map using dark channel prior formula.

**Algorithm**:
```
Inputs: i_color (RGB), i_A_r/g/b (atmospheric light), i_sky (sky flag)

Pipeline Stage 1 (Combinational → Registered):
  For each channel:
    inv_A_q16 = invA_lut_q16[i_A]           // Q16 reciprocal LUT
    norm_c[8:0] = (i_pix * inv_A_q16) >> 16 // normalized value
    min_norm = min(norm_r, norm_g, norm_b)  // minimum normalized channel

  Optionally apply 3×3 spatial filter to min_norm
  (ENABLE_SPATIAL_FILTER = 0 in current impl)

Pipeline Stage 2 (Combinational):
  x_scaled = min_norm
  t_scaled = 255 - (OMEGA_Q8 * x_scaled) >> 8
  t = max(t_scaled, T_MIN)

  If (i_use_sky && i_sky):
    t ← i_t_sky  // Override for sky pixels

Output: Registered (o_valid, o_t) – 1-cycle latency from min_norm_r
```

**Key Sub-Modules**:
1. **invA_lut_q16** (×3 instances) — LUT-based division
2. **norm_channel_q16** (×3 instances) — Multiply & shift
3. **min3_u8** — Find minimum of 3 values
4. **spatial_min3x3** (optional) — 3×3 filtering
5. **omega_clamp_t** — Final transmission computation

### 6.2 invA_lut_q16

**File**: `invA_lut_q16.sv`

**Purpose**: Precomputed lookup table for division: invA_q16 = floor((255 << 16) / A)

**Implementation**: 256-entry ROM

```verilog
// Physical interpretation:
// inv_A_q16 = 2^16 / A (in Q16 fixed point)
// For A=128: inv_A_q16 = 2^16/128 = 512
// For A=255: inv_A_q16 ≈ 257

LUT[0]   = 16711680  (2^24, handles A=0 avoiding division by zero)
LUT[1]   = 16711680  (saturated)
LUT[2]   = 8355840
LUT[128] = 512
LUT[255] = 65536
...
```

**Access Time**: Combinational (0 cycles)

### 6.3 norm_channel_q16

**File**: `norm_channel_q16.sv`

**Purpose**: Normalize 8-bit pixel by Q16 reciprocal.

```verilog
Algorithm:
  mul_q = i_pix * i_invA_q16           // [7:0] × [23:0] → [31:0]
  q16 = mul_q[31:16]                    // Extract Q16 (>> 16)
  
  if (q16[15:8] != 0)  // If MSB != 0, result > 255
    o_norm = 8'hFF     // Saturate to 255
  else
    o_norm = q16[7:0]  // Take low 8 bits
```

**Access Time**: Combinational (0 cycles)

### 6.4 min3_u8

**File**: `min3_u8.sv`

**Purpose**: Find minimum of 3 unsigned 8-bit values.

```verilog
Combinational:
  min_ab = (i_a < i_b) ? i_a : i_b
  o_min  = (min_ab < i_c) ? min_ab : i_c
```

**Access Time**: Combinational (0 cycles)

### 6.5 spatial_min3x3

**File**: `spatial_min3x3.sv`

**Purpose**: Apply 3×3 min filter to streaming pixel. Uses line buffers + 3×3 search_block_min.

**Latency**: Similar to dark_channel spatial mode
- Line buffer warmup: IMG_WIDTH cycles
- 3×3 window formation + min: ~4 cycles
- Total: **IMG_WIDTH + 4 cycles**

### 6.6 omega_clamp_t

**File**: `omega_clamp_t.sv`

**Purpose**: Final transmission calculation with omega scaling and minimum clamping.

```verilog
Parameters:
  OMEGA_Q8  = 8'hF3 (243 ≈ 0.95 in Q0.8, but can be any value)
  T_MIN     = 8'd26

Algorithm:
  omega_mul = i_x * OMEGA_Q8       // [7:0] × [7:0] → [15:0]
  x_scaled  = omega_mul[15:8]      // Shift right 8 (÷256 in Q0.8)
  t_raw     = 255 - x_scaled
  
  if (t_raw[8])  // if negative (MSB set in 9-bit result)
    o_t = T_MIN
  else if (t_raw[7:0] < T_MIN)
    o_t = T_MIN
  else
    o_t = t_raw[7:0]
```

**Access Time**: Combinational (0 cycles)

---

## 7. GRAYSCALE & UTILITY MODULES

### 7.1 grayscale

**File**: `grayscale.sv`

**Purpose**: Convert RGB to grayscale using weighted sum.

**Algorithm**:
```
Weights: R: 5/16 (0.3125), G: 9/16 (0.5625), B: 2/16 (0.125)

Hardware (Fixed-Point):
  red_fixed_point = red << 4
  green_fixed_point = green << 4
  blue_fixed_point = blue << 4
  
  mult_r = (red_fp >> 2) + (red_fp >> 4)     // 5/16 ≈ 4/16 + 1/16
  mult_g = (green_fp >> 1) + (green_fp >> 4) // 9/16 ≈ 8/16 + 1/16
  mult_b = blue_fp >> 3                       // 2/16 = 1/8
  
  sum = mult_r + mult_g + mult_b
  
  integer_part = sum[11:4]
  fraction_part = sum[3:0]
  
  Rounding modes (2'b00=up, 2'b01=down, 2'b10=to-even):
    mode 00 (round up):   if (frac > 0) result = int + 1 else result = int
    mode 01 (round down): result = int
    mode 10 (round even): if (frac > 0.5) result = int+1
                         else if (frac < 0.5) result = int
                         else (frac == 0.5): round to nearest even
```

**Typical Configuration**: mode = 2'b10 (round-to-even)

**Latency**: 1 cycle (registered output)

### 7.2 min3_u8, search_block_min (Already described in Section 4)

---

## 8. MEMORY ARCHITECTURE

### 8.1 External BRAMs

Three dual-port asynchronous BRAMs at SoC level:

#### **img_in_bram**
**File**: `mem/img_in_bram.v`

- **Capacity**: 192 KB (49152 × 32-bit words)
- **Data Width**: 32-bit (4 pixels if packed as ABCD or single pixel + padding)
- **Address Width**: 16-bit (64K address space)
- **Port A** (System/CPU):
  - Read/write access via APB/AHB
  - Used to load input frame from CPU/memory
- **Port B** (IPU Reader):
  - IPU read access only
  - Configured as streaming reader for dark_channel, transmission passes

#### **img_out_bram**
**File**: `mem/img_out_bram.v`

- **Capacity**: 192 KB
- **Data Width**: 32-bit
- **Address Width**: 16-bit
- **Port A** (System/CPU):
  - Read access for CPU to retrieve processed frame
  - System can read results after frame_done pulse
- **Port B** (IPU Writer):
  - IPU write-only access
  - Final output written by recovery stage

#### **img_tmp_bram**
**File**: `mem/img_tmp_bram.v` (not explicitly shown but referenced in ipu_soc)

- **Capacity**: TBD (same as others)
- **Purpose**: Temporary storage (possible use for intermediate results)
- **Ports**: Dual-port (System + IPU)

### 8.2 Internal Storage: bank_pingpong_stream

**File**: `bank_pingpong_stream.sv`

**Purpose**: Double-buffered transmission map storage for ADC neighbor access.

**Design**:
```
Parameters:
  DATA_WIDTH = 8 (per-pixel transmission values)
  IMG_WIDTH, IMG_HEIGHT = image dimensions
  ADDR_WIDTH = ceil(log2(WIDTH*HEIGHT))

Block RAM Banks:
  ┌──────────────────────────────────────────┐
  │ BANK 1 (bank_bram #0)  BANK 2 (bank_bram #1) │
  │ Size: IMG_WIDTH*IMG_HEIGHT × 8-bit       │
  └──────────────────────────────────────────┘

Write Path:
  Input stream (transmission values from estimate_transmission)
    → frame_linear_counter (generates write address 0..WIDTH*HEIGHT-1)
    → bank_pingpong_stream calculates which bank_sel=0 or 1
    → if bank_sel=0: write to BANK1, read from BANK2
    → if bank_sel=1: write to BANK2, read from BANK1

Read Path:
  On ADC stage startup:
    i_bank_swap pulse toggles bank selection
    frame_linear_counter (for ADC reads) generates read addresses
    ADC fetches neighboring transmission values for d_lambda computation

Read Position Information:
  o_rd_addr    — linear address [ADDR_WIDTH-1:0]
  o_rd_row     — current row [$clog2(IMG_HEIGHT)-1:0]
  o_rd_col     — current column [$clog2(IMG_WIDTH)-1:0]
  o_at_top, o_at_bottom, o_at_left, o_at_right — boundary flags
```

**Synchronization**:
- Write and read are **independent** with separate counters
- **Swap** (i_bank_swap) allows atomic switch between passes
- **Clear** signals reset counters for frame sync

### 8.3 Frame Linear Counter

**File**: `frame_linear_counter.sv`

**Purpose**: Generate linear address and position (row, col) for frame traversal.

```verilog
Parameters: IMG_WIDTH, IMG_HEIGHT, ADDR_WIDTH

Inputs:
  i_clear — reset counter to 0
  i_en    — increment if enabled

Outputs:
  o_addr  — linear address (row*WIDTH + col)
  o_row   — current row [0..HEIGHT-1]
  o_col   — current column [0..WIDTH-1]
  o_at_top, o_at_bottom, o_at_left, o_at_right — boundary flags

FSM:
  Address fills linearly: 0, 1, 2, ..., WIDTH*HEIGHT-1
  When col=WIDTH-1:
    col resets to 0
    row increments (wraps to 0 at row=HEIGHT-1)
  Address wraps to 0 after reaching WIDTH*HEIGHT-1
```

---

## 9. ADC ESTIMATION SUB-BLOCKS (DETAILED)

### 9.1 adc_line_buffer_5x5

**File**: `adc_line_buffer_5x5.sv`

**Purpose**: Build a 5×5 sliding window from 1-D streaming input.

**Design**:
```
4 Line Buffers:
  line_buf_0[WIDTH] → oldest row (row 0 of window)
  line_buf_1[WIDTH] → row 1
  line_buf_2[WIDTH] → row 2
  line_buf_3[WIDTH] → row 3
  (current input = row 4)

Column Counter:
  Counts pixels within each row (0..WIDTH-1)
  When col reaches WIDTH-1, resets and increments implicit row counter

Shift Registers (5 columns):
  p[0..4][0] ← p[0..4][1]    (shift left)
  p[0..4][1] ← p[0..4][2]
  ...
  p[0..4][4] ← new_col[0..4]

Warm-up Period:
  First valid window outputs after 2*WIDTH + 3 cycles
  This fills 2 rows (2*WIDTH) + 4-column shift register (3 additional cycles)
  Once warm, produces output every clock cycle (if i_valid continuous)
```

**Output Format**:
```
5×5 window (p[row][col]) where p[2][2] = center (current pixel)

p00 p01 p02 p03 p04
p10 p11 p12 p13 p14
p20 p21 p22 p23 p24
p30 p31 p32 p33 p34
p40 p41 p42 p43 p44
```

### 9.2 adc_pixel_distance

**File**: `adc_pixel_distance.sv`

**Purpose**: Compute total pixel distance (dp_total) along fixed paths from center p22 to each neighbor.

**Algorithm**:
```
Fixed Paths (from center to each of 24 neighbors):
  Diagonal-first approach ensures shortest/most-smooth paths
  
  Example:
    p22 → p11 → p00  (2-step diagonal path)
    p22 → p12 → p02  (vertical then diagonal)
    p22 → p22        (center, dp=0)

For 1-step neighbors (inner ring, 8 neighbors):
  dp = |p22 - neighbor|

For 2-step neighbors (outer ring, 16 neighbors):
  dp = |p22 - intermediate| + |intermediate - neighbor|
```

**Output**: 
- 25 × [8:0] values (one per position)
- Max value: ~510 (for 2 edges of 255 each)

**Latency**: 1 cycle (registered output)

### 9.3 adc_path_length

**File**: `adc_path_length.sv`

**Purpose**: Convert pixel distance (dp) to path distance (d_lambda) using fixed spatial distances and lambda weighting.

**Algorithm**:
```
d_lambda[i,j] = spatial_dist[i,j] + lambda * dp_total[i,j]

Spatial distance table (D8 chamfer distance from center):
    4 3 2 3 4
    3 2 1 2 3
    2 1 0 1 2
    3 2 1 2 3
    4 3 2 3 4

Lambda multiplication (Q0.8):
  lambda_dp_term = (LAMBDA_Q8 * dp_total) >> 8
  
  Example: LAMBDA_Q8=51 (≈0.2)
    If dp_total = 100:
      lambda_term = (51 * 100) >> 8 = 5100 >> 8 = 19
    d_lambda = spatial + 19

Maximum d_lambda:
  Max spatial = 4
  Max dp_term ≈ (255 * 510) >> 8 ≈ 507
  Practical max with LAMBDA_Q8=51: 4 + 101 ≈ 106 → fits in [9:0]
```

**Output**: 25 × [9:0] values

**Latency**: 1 cycle (registered output)

### 9.4 adc_rlimit_compute

**File**: `adc_rlimit_compute.sv`

**Purpose**: Compute r_limit (mean of d_lambda) using hardware-optimized fixed-point division.

**Algorithm**:
```
r_limit = mean(d_lambda) = (Σ d_lambda) / 25

Hardware Approximation:
  x / 25 ≈ (x * 41) >> 10
  41/1024 = 0.0400390625 ≈ 1/24.97 (error < 0.1%)

Pipeline (2 stages):
  Stage 1: Adder tree sums all 25 values (16-way parallel reduction)
    Produced: sum_total [14:0] (15-bit, max ≈ 25*106 = 2650)
    Also delays d_lambda by 1 cycle for alignment
    
  Stage 2: Multiply sum_total by 41, shift right 10
    prod = sum_total * 41 [20:0]
    rlimit = prod[20:10] [9:0]
    Also delays d_lambda by 1 more cycle
```

**Output**: 
- r_limit [9:0]
- delayed d_lambda [9:0] × 25 (for comparison in ase_masked_min)

**Latency**: 2 cycles total

### 9.5 adc_ase_masked_min

**File**: `adc_ase_masked_min.sv`

**Purpose**: Compute Adaptive Structuring Element (ASE) mask and extract minimum of masked pixels.

**Algorithm**:
```
ASE Mask Computation:
  For each position [i,j] in 5×5:
    mask[i,j] = (d_lambda[i,j] <= r_limit) ? 1 : 0
    (Center [2,2] always has d_lambda=0, always included)

Masked Value Selection:
  For each position [i,j]:
    masked[i,j] = mask[i,j] ? pixel[i,j] : 8'hFF
    (255 is neutral for min operation)

Final Output:
  adc = min(masked[0,0], masked[0,1], ..., masked[4,4])
      = min(pixel[i,j] for all [i,j] where d_lambda[i,j] <= r_limit)
```

**Combinational Min Tree**: Cascaded 2-input comparators to find global minimum

**Output**: Single 8-bit ADC value per 5×5 window

**Latency**: 1 cycle (registered output)

---

## 10. REGISTER & CONTROL INTERFACE

### 10.1 APB Register Map (ipu_top / ipu_core)

**Base Address Offsets** (from [ipu_addr_map.vh]()):

| Register | Offset | Bits | Access | Description |
|----------|--------|------|--------|-------------|
| `IPU_CTRL` | 0x00 | [0]: EN | RW | IPU enable |
| | | [1]: START | RW | Start frame processing |
| | | [2]: CONT_MODE | RW | Continuous mode |
| `IPU_STATUS` | 0x04 | [0]: IDLE | RO | FSM is idle |
| | | [1]: BUSY | RO | FSM is processing |
| | | [2]: DONE | RO | Frame processing done |
| | | [3]: ERROR | RO | Error occurred |
| `IPU_SRC_ADDR` | 0x08 | [31:0] | RW | Source BRAM address (IMG_IN) |
| `IPU_DST_ADDR` | 0x0C | [31:0] | RW | Destination BRAM address (IMG_OUT) |
| `IPU_TMP_ADDR` | 0x10 | [31:0] | RW | Temporary BRAM address (IMG_TMP) |
| `IPU_IMG_WIDTH` | 0x14 | [31:0] | RW | Image width in pixels (def: 128) |
| `IPU_IMG_HEIGHT` | 0x18 | [31:0] | RW | Image height in pixels (def: 128) |
| `IPU_IMG_STRIDE` | 0x1C | [31:0] | RW | Row-to-row byte offset (def: 512) |
| `IPU_IMG_FORMAT` | 0x20 | [1:0] | RW | 0: RGB888, 1: BGR888 |
| `IPU_PARAM_0` | 0x24 | [31:0] | RW | Algorithm parameter (reserved) |
| `IPU_PARAM_1` | 0x28 | [31:0] | RW | Algorithm parameter (reserved) |
| `IPU_PARAM_2` | 0x2C | [31:0] | RW | Algorithm parameter (reserved) |
| `IPU_IRQ_EN` | 0x30 | [0]: DONE_IRQ | RW | Enable frame-done interrupt |
| `IPU_IRQ_STATUS` | 0x34 | [0]: DONE | RW/1C | Interrupt status (W1C) |
| `IPU_DEBUG` | 0x38 | [3:0]: FSM_STATE | RO | Current FSM state |
| | | [7:4]: Reserved | RO | |
| `IPU_ID` | 0x3C | [31:0]: 0x49505531 | RO | Chip ID "IPU1" |

### 10.2 Typical Control Flow (Software)

```python
# Initialize IPU
write_reg(IPU_CTRL, 0x00)         # Disable before setup
write_reg(IPU_IMG_WIDTH, 128)     # Set image dimensions
write_reg(IPU_IMG_HEIGHT, 128)
write_reg(IPU_IMG_STRIDE, 512)    # 128*4 bytes per row (32-bit words)
write_reg(IPU_SRC_ADDR, 0x0000)   # IMG_IN BRAM offset
write_reg(IPU_DST_ADDR, 0x0000)   # IMG_OUT BRAM offset
write_reg(IPU_IRQ_EN, 0x0001)     # Enable done interrupt

# Load input image into IMG_IN BRAM via Port A
for pixel_idx in range(128*128):
  pixel = input_frame[pixel_idx]  # 24-bit BGR
  sys_addr = pixel_idx // 4       # 4 pixels per 32-bit word
  write_bram(IMG_IN, sys_addr, pixel)

# Trigger processing
write_reg(IPU_CTRL, 0x01)         # EN=1
write_reg(IPU_CTRL, 0x03)         # EN=1, START=1

# Wait for completion
while (read_reg(IPU_STATUS) & 0x02) == 0:  # Wait for BUSY
  pass
while (read_reg(IPU_STATUS) & 0x04) == 0:  # Wait for DONE
  pass

# Read output frame from IMG_OUT BRAM via Port A
for pixel_idx in range(128*128):
  sys_addr = pixel_idx // 4
  pixel = read_bram(IMG_OUT, sys_addr)
  output_frame[pixel_idx] = pixel
```

---

## 11. DATA BIT WIDTHS & PRECISION

### 11.1 Signal Bit Widths Through Pipeline

| Stage | Signal | Bit Width | Format | Notes |
|-------|--------|-----------|--------|-------|
| Input | RGB | [23:0] | 8.8.8 (RBG) | Per-pixel color |
| Dark Channel | dark_ch | [7:0] | U8 | min(R,G,B) |
| Atmospheric Light | A_R, A_G, A_B | [7:0] × 3 | U8 | Max dark_ch pixel |
| Grayscale | gray | [7:0] | U8 | 0.3125R + 0.5625G + 0.125B |
| Sky Flag | sky | [0:0] | Boolean | gray/dark_ch > i_A0 |
| Inverse A | inv_A_q16 | [23:0] | Q16 (fixed-point) | 2^16 / A |
| Normalized | norm_c | [7:0] | U8 | (pix × inv_A) >> 16 |
| Transmission | tx | [7:0] | U8 | 255 - (omega × norm) >> 8 |
| Dark Distance | dp | [8:0] | U9 | pixel path distance (max ~510) |
| Path Length | d_lambda | [9:0] | U10 | spatial + lambda×dp (max ~106) |
| r_limit | r_limit | [9:0] | U10 | mean(d_lambda) |
| ADC | adc_pix | [7:0] | U8 | min(tx where d_lambda <= r_limit) |
| Transmission Raw | tx_raw | [8:0] | U9 | 255 - (dark×omega/A) |
| Transmission Used | tx_used | [7:0] | U8 | max(tx_raw, T_MIN) |
| Output RGB | out_r/g/b | [7:0] × 3 | U8 | (src - A) / tx + A (clamped) |

### 11.2 Fixed-Point Arithmetic

**Q0.8 Format** (used for LAMBDA_Q8, OMEGA_Q8):
- Represents 0.0 to ~1.996
- Multiply by 256 to get integer value for hardware
- Example: LAMBDA_Q8 = 51 decimal → λ = 51/256 ≈ 0.199 ≈ 0.2

**Q16 Format** (for reciprocals):
- 24-bit: [23:0]
- Represents 0.0 to 65535.0
- Example: invA_q16 = 512 → 1/A ≈ 512/65536 ≈ 1/128

---

## 12. TIMING & THROUGHPUT

### 12.1 Latencies by Stage

| Stage | Latency (cycles) | Notes |
|-------|------------------|-------|
| dark_channel | 1 | Registered src_min output |
| grayscale | 1 | Registered weighted sum |
| atmospheric_light | frame event | Outputs after frame_end pulse |
| sky_recognition | 1 | After dark_channel |
| estimate_transmission | 3 | Reciprocal LUT + norm + spatial min + omega |
| bank_pingpong write | 0 | Combinational (async BRAM) |
| bank_pingpong read | 0 | Combinational (async BRAM) |
| **adc_line_buffer** | 4*WIDTH+4 | Warmup only (then 1 cycle per pixel) |
| **adc_pixel_distance** | 1 | Register output |
| **adc_path_length** | 1 | Register output |
| **adc_rlimit_compute** | 2 | Adder tree + multiplier |
| **adc_ase_masked_min** | 1 | Min tree + register |
| **ADC total** | 4*WIDTH+9 | After first warmup |
| t_computing | 1 | Division + register |
| fusing | 1 | Division + clamp + register |
| **t_compute_fuse total** | 2 | Series of t_computing → fusing |

### 12.2 Example Frame Processing Timeline (128×128)

```
Assume IMG_WIDTH=128, IMG_HEIGHT=128, total pixels = 16384

Clock Cycle | State | Operation | Duration |
─────────────┴───────┴───────────────┴──────────
0           | IDLE  | Waiting for START signal
1           | LOAD  | Clear banks, prepare
2           | DARK  | Reader active, dark_channel processes frame
2-16385     | DARK  | Streaming: 16384 pixels @ 1 per clock
16386       | SKY   | Atmospheric light finalizes A
16387       | TRANS | Reader re-activates for transmission computation
16387-32770 | TRANS | bank_pingpong writes TX values
32771       | ADC   | bank_swap, bank_rd_clear, ADC pipeline starts
32771+512   | ADC   | First 5×5 window ready (warmup: 4*128+4=516 cycles)
~33500-...  | ADC   | ADC processes pixels (sliding window)
~50000      | ADC   | adc_done pulse (depends on frame dimensions)
~50001      | RECOV | t_compute_fuse + writer active
~50001-66385| RECOV | Output written to IMG_OUT BRAM
66386       | DONE  | Assert done, ipu_irq
─────────────┬───────┬──────────────┬──────────
TOTAL TIME  | ~66K cycles ≈ 0.66 ms @ 100 MHz
```

### 12.3 Throughput

**Streaming pixel rate** (assuming continuous frames):
- Once ADC warmup completed, **1 pixel per clock after ~4WIDTH cycles**
- For 128×128: ~0.33 ms per frame after initialization
- **Theoretical max**: 100M pixels/sec @ 100 MHz

---

## 13. HARDWARE REQUIREMENTS

### 13.1 Block RAM Allocation

**External (SoC-level)**:
- IMG_IN:  192 KB (49K × 32-bit)
- IMG_OUT: 192 KB (49K × 32-bit)
- IMG_TMP: 192 KB (49K × 32-bit)
- **Total external**: ~576 KB

**Internal (Core-level)**:
- bank_pingpong (TX): 2 × (IMAGE_SIZE × 8-bit) 
  - For 128×128: 2 × 16K × 1B = 32 KB
  - For 256×256: 2 × 64K × 1B = 128 KB
  - For 512×512: 2 × 256K × 1B = 512 KB

**Total BRAM**: ~576 KB + (32-512 KB depending on image size)

### 13.2 LUT & Register Requirements

**LUTs**: Primarily used for:
- Comparators (min operations)
- Multiplexers (datapath muxing)
- Adders (arithmetic)
- Estimated: ~8K-15K LUTs for full pipeline (synthesis dependent)

**Registers**: 
- Pipelining flops: ~10K-20K (mostly in ADC stages)
- Line buffers (distributed RAM): ~16-256 KB (flexible)

### 13.3 Frequency & Power

**Target Frequency**: 100-200 MHz (typical embedded vision SoCs)

**Power Consumption** (estimated @ 128×128, 100 MHz):
- Digital core: 10-30 mW
- BRAM: 5-10 mW
- I/O: 2-5 mW
- **Typical total**: 20-50 mW

---

## 14. PYTHON ↔ HARDWARE MAPPING

### 14.1 Software Algorithm (Python Reference)

```python
def haze_removal_pipeline(img_rgb, params=None):
    """
    Full dehaze pipeline matching hardware implementation.
    
    Args:
        img_rgb: (H, W, 3) uint8 RGB image
        params: {omega_q8, t_min, lambda_q8, a0}
    
    Returns:
        recovered: (H, W, 3) uint8 dehazedr image
    """
    H, W = img_rgb.shape[:2]
    
    # Stage 1: Dark Channel Prior
    dark_ch = np.min(img_rgb, axis=2)  # Per-pixel min(R,G,B)
    
    # Stage 2: Atmospheric Light Estimation
    dark_ch_flat = dark_ch.flatten()
    max_dark_idx = np.argmax(dark_ch_flat)
    A_rgb = img_rgb.reshape(-1, 3)[max_dark_idx]  # Get A
    
    # Stage 3: Transmission Estimation (Coarse)
    A_max = np.max(A_rgb)
    inv_A = 255.0 / A_rgb  # Reciprocals
    norm = (img_rgb * inv_A).min(axis=2)  # Normalized channels min
    t_coarse = 1.0 - (0.95 * norm / 255)  # omega ≈ 255/256 ≈ 1
    t_coarse = np.maximum(t_coarse, 0.06)  # T_MIN ≈ 15/255 ≈ 0.06
    
    # Stage 4: Adaptive Dark Channel (ADC) Enhancement
    gray = (0.3125 * img_rgb[..., 2] +  # R weight
            0.5625 * img_rgb[..., 1] +  # G weight
            0.125 * img_rgb[..., 0])    # B weight
    
    adc = adaptive_dark_channel(gray, t_coarse, lambda=0.2)
    
    # Stage 5: Final Recovery
    t_final = np.maximum(adc, 0.06)  # Use ADC, ensure minimum
    recovered = np.clip((img_rgb - A_rgb) / np.maximum(t_final, 0.01) + A_rgb,
                        0, 255).astype(np.uint8)
    
    return recovered

def adaptive_dark_channel(gray, min_channel, lambda_param=0.2, window_size=5):
    """
    Compute adaptive dark channel using ASE (Adaptive Structuring Element).
    Corresponds to Python adc_estimation_top(...) → full ADC block.
    """
    H, W = gray.shape
    adc = np.zeros_like(min_channel, dtype=np.uint8)
    
    for i in range(2, H-2):
        for j in range(2, W-2):
            # Extract 5×5 windows
            gray_window = gray[i-2:i+3, j-2:j+3]  # [5,5]
            mc_window = min_channel[i-2:i+3, j-2:j+3]
            
            # Compute path distances and d_lambda
            dp_total = pixel_distance(gray_window)  # [5,5]
            d_lambda = spatial_dist + lambda_param * dp_total
            
            # Compute r_limit threshold
            r_limit = np.mean(d_lambda)
            
            # ASE mask and min
            mask = (d_lambda <= r_limit)
            adc[i, j] = np.min(mc_window[mask]) if np.any(mask) else 255
    
    return adc
```

### 14.2 Hardware Equivalent

| Python Code | Hardware Module | Format | Notes |
|-------------|-----------------|--------|-------|
| `np.min(..., axis=2)` | dark_channel.sv | U8 | min(R,G,B) |
| `argmax(dark_ch)` | atmospheric_light.sv | Accumulator | Streaming comparison |
| `img[max_idx]` | Register bank | U8×3 | Latched A values |
| `255 / A` | invA_lut_q16.sv | Q16 (24-bit) | LUT-based reciprocal |
| `img * inv_A` | norm_channel_q16.sv | U8 (8-bit) | Multiply shift >>16 |
| `1 - 0.95 * norm` | omega_clamp_t.sv | U8 | Transmission formula |
| `adc_estimation_top(...)` | adc_estimation.sv | U8 | Full 5-stage pipeline |
|  `+ spatial_dist` | adc_path_length.sv | U10 | Add D8 distances |
| `+ lambda * dp` | adc_path_length.sv | U10 | Multiply-shift lambda |
| `mean(d_lambda)` | adc_rlimit_compute.sv | U10 | Sum >> 10 |
| `min(masked)` | adc_ase_masked_min.sv | U8 | Min with mask |
| `(img - A) / t + A` | fusing.sv | U8×3 | Final recovery arithmetic |

---

## 15. TESTBENCH INTEGRATION

### 15.1 Required Test Vectors

1. **Input Test Patterns**:
   - Solid color (R, G, B)
   - Grayscale ramp
   - Checker pattern
   - Real hazy image samples (from paper or dataset)

2. **Software Golden Reference**:
   - Python implementation generates expected outputs
   - Compare hardware outputs pixel-by-pixel

3. **Register Access**:
   - APB testbench reads/writes all control registers
   - Verifies BRAM indirect access via registers

4. **Frame Synchronization**:
   - Multiple frame processing (verify continuous mode)
   - Check interrupt generation

### 15.2 Typical Testbench Flow

```verilog
// 1. Initialize
ipu_soc.rst_n = 1'b1;
wait_clocks(10);

// 2. Configure
write_reg(IPU_IMG_WIDTH, 128);
write_reg(IPU_IMG_HEIGHT, 128);

// 3. Load input image into IMG_IN BRAM
for i in 0..16383:
  sys_addr = i / 4;
  write_bram(img_in_bram, sys_addr, test_pixels[i]);

// 4. Trigger IPU
write_reg(IPU_CTRL, 0x03);  // EN=1, START=1

// 5. Monitor progress
while (read_reg(IPU_STATUS) & DONE) == 0:
  wait_clocks(1);
  print_progress(read_reg(IPU_DEBUG)[3:0]);

// 6. Read results
for i in 0..16383:
  sys_addr = i / 4;
  output[i] = read_bram(img_out_bram, sys_addr);

// 7. Compare with golden
for i in 0..16383:
  if (output[i] != golden[i]):
    error_count++;

assert(error_count < tolerance);
```

---

## 16. SUMMARY

### Core Architecture Overview

The IPU implements a **complete Dark Channel Prior haze removal pipeline** in hardware, organized as:

1. **Control Layer** (`ipu_control_logic`):
   - 7-state FSM orchestrating processing stages
   - APB register interface for software control

2. **Datapath Layer** (`haze_removal_core`):
   - **Pass 1** (DARK/SKY/TRANS): Atmospheric light + coarse transmission
   - **Pass 2** (ADC): 5-stage adaptive dark channel enhancement
   - **Pass 3** (RECOVERY): Final image synthesis

3. **Memory Layer**:
   - External BRAMs for input/output frame buffering (576 KB @ SoC level)
   - Internal dual-port transmission map (32-512 KB core-level)
   - Line buffers for 5×5 window formation (dynamic, distributed RAM)

4. **Key Innovations**:
   - **Streaming architecture**: All operations pipelined for continuous pixel processing
   - **Fixed-point arithmetic**: Eschews floating-point for DSP/LUT efficiency
   - **Parameterizable**: IMG_WIDTH/HEIGHT, OMEGA, T_MIN, LAMBDA all tunable
   - **Ping-pong buffering**: Allows overlapped transmission read/write between passes

### Performance Targets
- **Frame rate**: ~100 fps for 128×128 @ 100 MHz
- **Latency**: ~650 µs for 128×128 single frame
- **Power**: 20-50 mW typical
- **Area**: ~15K LUTs + BRAM (synthesis dependent)

This comprehensive hardware implementation enables real-time image dehazing suitable for embedded vision, autonomous vehicles, surveillance, and mobile imaging applications.

---

## 17. APPENDIX: FILE LISTING

### Source Files Organization

```
00_src/IPU/
├── Top-Level Wrappers
│   ├── haze_removal_top.sv           # Top-level frame interface
│   ├── haze_removal_core.sv          # Structural datapath wrapper
│   ├── ipu_top.sv                    # (Legacy) Full module integration
│   ├── ipu_soc.sv                    # (Modern) SoC with external BRAM
│   └── ipu_control_logic.sv          # 7-state FSM controller
│
├── Processing Pipeline Stages
│   ├── atm_light_coarse_tx.sv        # Pass 1: Dark/Sky/Transmission
│   ├── adc_estimation.sv             # Pass 2: Adaptive Dark Channel (5-stage)
│   └── t_compute_fuse.sv             # Pass 3: Recovery synthesis
│
├── Dark Channel Modules
│   ├── dark_channel.sv               # Min(R,G,B) per pixel
│   ├── src_min.sv                    # Combinational min of RGB
│   └── search_block_min.sv           # 3×3 block min reduction
│
├── Atmospheric Light & Sky
│   ├── atmospheric_light.sv          # Frame-level max dark_ch → A
│   └── sky_recognition.sv            # Threshold-based pixel classification
│
├── Transmission Estimation
│   ├── estimate_transmission.sv       # Coarse transmission formula
│   ├── invA_lut_q16.sv               # Reciprocal LUT (division)
│   ├── norm_channel_q16.sv           # Q16-based multiplication
│   ├── min3_u8.sv                    # Min of 3 values
│   ├── spatial_min3x3.sv             # 3×3 spatial filter
│   └── omega_clamp_t.sv              # Final transmission formula
│
├── Grayscale & Utilities
│   └── grayscale.sv                  # RGB → grayscale conversion
│
├── Adaptive Dark Channel Stages
│   ├── adc_line_buffer_5x5.sv        # Stage 0: Build 5×5 windows
│   ├── adc_pixel_distance.sv         # Stage 1: Path edge distances
│   ├── adc_path_length.sv            # Stage 2: d_lambda computation
│   ├── adc_rlimit_compute.sv         # Stages 3-4: r_limit threshold
│   └── adc_ase_masked_min.sv         # Stage 5: ASE mask + min
│
├── Storage & Memory Management
│   ├── bank_bram.sv                  # Single BRAM block (8-bit word)
│   ├── bank_pingpong_stream.sv       # Double-buffered TX storage
│   ├── frame_linear_counter.sv       # Address/position generation
│   ├── fifo_ram.sv                   # Generic FIFO (if used)
│   └── mem/
│       ├── img_in_bram.v             # Input frame BRAM (external)
│       ├── img_out_bram.v            # Output frame BRAM (external)
│       ├── ipu_bram_reader.v         # (Legacy) Reader interface
│       ├── ipu_bram_writer.v         # (Legacy) Writer interface
│       └── ipu_addr.vh               # Address mappings
│
├── Configuration & Addressing
│   ├── ipu_addr_map.vh               # Register address macro definitions
│   └── ipu_addr_map_soc.vh           # SoC-level address map
│
└── Misc & Legacy
    ├── error_diffusion.sv            # Floyd-Steinberg dithering (experimental)
    ├── RAM_o.sv, ROM_i.sv            # Generic memory templates
    └── README.md                      # Module documentation

```

---

**End of Hardware Architecture Document**

