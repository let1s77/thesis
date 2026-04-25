# DE10-Standard FPGA Board Specifications

**Board:** Terasic DE10-Standard  
**FPGA:** Intel Altera Cyclone V (5CSXFC6D6F31C6)  
**Updated:** 2025-03-24

---

## Table of Contents
1. [Hardware Overview](#hardware-overview)
2. [Device Specifications](#device-specifications)
3. [Pin Configuration](#pin-configuration)
4. [I/O Mapping on DE10](#io-mapping-on-de10)
5. [Timing Specifications](#timing-specifications)
6. [Clock Specifications](#clock-specifications)
7. [Power Specifications](#power-specifications)
8. [Design Guidelines](#design-guidelines)
9. [SoC Integration Notes](#soc-integration-notes)

---

## Hardware Overview

### DE10-Standard Board Features:
- **FPGA Chip:** Cyclone V (5CSXFC6D6F31C6)
- **Logic Elements:** 110,600 LE
- **Embedded RAM:** 4,687 Kbits (586 M9K + 4 M144K blocks)
- **DSP Blocks:** 600 x 18-bit multiplier
- **Maximum Frequency:** 500+ MHz (varies with design complexity)
- **I/O Banks:** Multiple 3.3V-tolerant banks

### Key Components:
1. **FPGA** (main programmable logic)
2. **Memory:**
   - 64 MB SDRAM (x32 bus)
   - 8 MB Flash Altera IV chip
3. **Interfaces:**
   - USB Blaster II (JTAG programming + GPIO)
   - Ethernet (MAC 10/100)
   - RS-232 Serial port
4. **User I/O:**
   - 18 Slide switches (SW[17:0])
   - 4 Push buttons (KEY[3:0])
   - 18 Red LEDs (LEDR[17:0])
   - 9 Green LEDs (LEDG[8:0])
   - 8 x 7-segment displays (HEX0-HEX7)
   - 16x2 LCD display
5. **Oscillators:**
   - 50 MHz main clock (CLOCK_50)
   - 27 MHz video clock

---

## Device Specifications

### Cyclone V (5CSXFC6D6F31C6) Key Parameters:

| Parameter | Value | Unit | Notes |
|-----------|-------|------|-------|
| **Logic Elements** | 110,600 | LE | Equivalent to ~440K ASIC gates |
| **Embedded Memory** | 4,687 | Kbits | Organized as M9K and M144K blocks |
| **DSP Blocks** | 600 | units | 18x18 multipliers |
| **User I/O Pins** | 154 (max) | pins | Varies by package |
| **Package** | LFBGA484 | - | 23×23mm BGA |
| **Power Supply** | 1.1V (core) | V | 3.3V I/O banks |
| **Operating Temp** | 0 to 85 | °C | Commercial grade |

---

## Pin Configuration

### Main Clock & Reset:
```
CLOCK_50  → GPIO input (50 MHz oscillator)
KEY[0]    → GPIO input (active LOW async reset)
KEY[1:3]  → GPIO inputs (USER buttons)
```

### User I/O Banks:

| I/O Group | Pins | Voltage | Notes |
|-----------|------|---------|-------|
| **Switches** | SW[17:0] | 3.3V | 18x slide switches |
| **Keys** | KEY[3:0] | 3.3V | 4x push buttons, KEY[0]=RESET |
| **Red LEDs** | LEDR[17:0] | 3.3V | 18x red LED outputs |
| **Green LEDs** | LEDG[8:0] | 3.3V | 9x green LED outputs |
| **HEX Display** | HEX0[6:0] ... HEX7[6:0] | 3.3V | 8x 7-segment cathodes |
| **LCD** | LCD_DATA[7:0], control | 3.3V | 16x2 character display |

---

## I/O Mapping on DE10

### Quartus Pin Assignment Reference:

```verilog
// =================== CLOCKS & RESETS ===================
CLOCK_50      → AH16     // 50 MHz main oscillator
KEY[0]        → AE9      // RESET (active LOW)
KEY[1]        → AF9      // User button 1
KEY[2]        → AH6      // User button 2
KEY[3]        → AG5      // User button 3

// =================== SWITCHES ===================
// All on Bank 3B (3.3V)
SW[0]         → AE5
SW[1]         → AF6
SW[2]         → AG7
SW[3]         → AH7
SW[4]         → AJ7
SW[5]         → AH6      // NOTE: Also used for LCD_EN? Verify!
SW[6]         → AJ6
SW[7]         → AK6
SW[8]         → AL6
SW[9]         → AK7
SW[10]        → AL7
SW[11]        → AK8
SW[12]        → AL8
SW[13]        → AH11
SW[14]        → AI11
SW[15]        → AJ11
SW[16]        → AK11
SW[17]        → AL11

// =================== RED LEDs (LEDR) ===================
LEDR[0]       → AA1
LEDR[1]       → AB1
LEDR[2]       → AC1
LEDR[3]       → AD1
LEDR[4]       → AE1
LEDR[5]       → AF1
LEDR[6]       → AG1
LEDR[7]       → AH1
LEDR[8]       → AJ1
LEDR[9]       → AK1
LEDR[10]      → AL1
LEDR[11]      → AM1
LEDR[12]      → AN1
LEDR[13]      → AP1
LEDR[14]      → AQ1
LEDR[15]      → AR1
LEDR[16]      → AT1
LEDR[17]      → AU1

// =================== GREEN LEDs (LEDG) ===================
LEDG[0]       → AA2
LEDG[1]       → AB2
LEDG[2]       → AC2
LEDG[3]       → AD2
LEDG[4]       → AE2
LEDG[5]       → AF2
LEDG[6]       → AG2
LEDG[7]       → AH2
LEDG[8]       → AJ2

// =================== HEX DISPLAYS ===================
// Each HEX display has 7 segments (a,b,c,d,e,f,g)
HEX0[0]       → AE6      // Segment a
HEX0[1]       → AF6      // Segment b
HEX0[2]       → AG6      // Segment c
HEX0[3]       → AH6      // Segment d
HEX0[4]       → AJ6      // Segment e
HEX0[5]       → AK6      // Segment f
HEX0[6]       → AL6      // Segment g

// HEX1 through HEX7 follow similar pattern
// See design files for exact pinout

// =================== LCD DISPLAY ===================
LCD_DATA[0]   → AA2
LCD_DATA[1]   → AA1
LCD_DATA[2]   → AB2
LCD_DATA[3]   → AB1
LCD_DATA[4]   → AA3
LCD_DATA[5]   → AB3
LCD_DATA[6]   → AA4
LCD_DATA[7]   → AB4
LCD_EN        → AG2      // Enable
LCD_RS        → AH3      // Register Select
LCD_RW        → AH4      // Read/Write (typically tied to GND for write-only)
LCD_BLON      → AG3      // Backlight ON
LCD_ON        → AF4      // Display ON

```

**Note:** Pin assignments may vary between DE10 variants. Always verify with your Quartus TCL assignment file!

---

## Timing Specifications

### Cyclone V I/O Timing (typ. at 50 MHz):

| Parameter | Min | Typ | Max | Unit |
|-----------|-----|-----|-----|------|
| **tCO (Clock-to-Output)** | - | 6.5 | 8.0 | ns |
| **tSU (Setup Time)** | - | 2.5 | 4.0 | ns |
| **tH (Hold Time)** | 0.5 | 0.8 | 1.5 | ns |
| **tPD (Combinational Delay)** | - | 2-5 | 6-8 | ns |

### Data Paths (50 MHz FPGA-to-Board):

```
FPGA Output → Gate Delay (1-2ns) 
          → PCB Routing (2-3ns) 
          → Receiver Setup (0.5-1.0ns)
Total: ~4-6ns (max 8ns at board edge)
```

### Input Paths (Board-to-FPGA):

```
External Source → PCB Routing (2-4ns) 
            → Input Buffer (0.5-1.0ns) 
            → Synchronizer (if async) (10-20ns)
Total: ~12-24ns depending on sync requirements
```

---

## Clock Specifications

### CLOCK_50 (Main Oscillator):

| Parameter | Value | Notes |
|-----------|-------|-------|
| **Frequency** | 50 MHz ±50 ppm | Crystal oscillator on board |
| **Period** | 20 ns | Standard digital clock |
| **Duty Cycle** | 50% | Symmetric |
| **Rise/Fall Time** | ~1-2 ns | Fast rise time |
| **Jitter** | < 100 ps | Phase jitter, RMS |
| **Phase Noise** | < -100 dBc/Hz @ 1kHz | Typical quality |

### Recommended Constraints (SDC):

```tcl
# Primary clock declaration
create_clock -name {CLOCK_50} -period 20.000 \
    -waveform { 0.000 10.000 } [get_ports {CLOCK_50}]

# Clock uncertainty (setup + hold margin)
set_clock_uncertainty -setup 0.170 [get_clocks {CLOCK_50}]
set_clock_uncertainty -hold  0.030 [get_clocks {CLOCK_50}]
```

---

## Power Specifications

### DE10-Standard Power Requirements:

| Rail | Voltage | Typical Current | Max Current | Notes |
|------|---------|-----------------|-------------|-------|
| **VCORE** | 1.1V | 2-3 A | 5 A | FPGA core logic |
| **VCCIO** | 3.3V | 1-2 A | 4 A | I/O banks |
| **VCCINT** | 1.1V | 2-3 A | 5 A | Internal logic |
| **Total Board** | 5V | 2-4 A | 6 A | From USB or external PSU |

### Power Consumption Estimates:

- **Idle (no activity):** ~100 mW
- **Running 50 MHz full CPU:** ~500 mW - 1 W
- **Max utilization (all LE + DSP):** ~2-3 W

### Thermal:

- **Junction Temp Range:** 0°C to 85°C (commercial)
- **Typical dissipation:** 1-2 W at 50 MHz
- **Cooling:** Passive (heat from I/O buffers, not significant at 50 MHz)

---

## Design Guidelines

### Best Practices for FPGA on DE10:

#### 1. **Reset Handling:**
```verilog
// Double-FF synchronizer for async reset
reg [1:0] rst_sync_ff;
always @(posedge clk) 
  rst_sync_ff <= {rst_sync_ff[0], KEY[0]};
wire rst_n = rst_sync_ff[1];
```

#### 2. **Timing Constraints (.sdc):**
```tcl
# Input timing
set_input_delay -clock {CLOCK_50} -max 10 [get_ports {SW[*] KEY[*]}]
set_input_delay -clock {CLOCK_50} -min 4  [get_ports {SW[*] KEY[*]}]

# Output timing (account for PCB delays)
set_output_delay -clock {CLOCK_50} -max 12 [get_ports {LEDR[*] LEDG[*]}]
set_output_delay -clock {CLOCK_50} -min 3  [get_ports {LEDR[*] LEDG[*]}]

# False path for reset (async)
set_false_path -from [get_ports {KEY[0]}] \
               -to [get_registers {*rst_sync_ff*}]
```

#### 3. **Avoid Hold Violations:**
- **Set tight hold uncertainty** (0.03ns instead of 0.06ns)
- **Add input/output delays** to model PCB routing
- **Use double FF synchronizers** for async signals
- **Avoid combinational paths** to/from I/O without registers

#### 4. **BRAM Usage:**
- Use dual-port BRAM for CPU+IPU shared memory
- Clock all BRAM reading/writing with main clock
- Add 1-cycle pipelining if path timing is tight

#### 5. **APB Bus Timing:**
- 50 MHz APB clock = 20ns period
- Setup requirement: ~4ns before clock edge
- Hold requirement: ~0.5ns after clock edge
- Use registered inputs/outputs

---

## SoC Integration Notes

### soc_top Architecture on DE10:

```
┌─────────────────────────────────────────┐
│         FPGA (Cyclone V)                │
│  ┌───────────────────────────────────┐  │
│  │     wrapper.sv (Top Module)       │  │
│  └───────┬───────────────────────────┘  │
│          │                               │
│  ┌───────────────────────────────────┐  │
│  │  soc_top                          │  │
│  │ ┌──────────────┐                  │  │
│  │ │ single_cycle │ (RISC-V CPU)    │  │
│  │ │ + LSU        │                  │  │
│  │ └──────────────┘                  │  │
│  │ ┌──────────────┐                  │  │
│  │ │ APB4 Bus     │ (Peripherals)   │  │
│  │ │ Arbitration  │                  │  │
│  │ └──────────────┘                  │  │
│  │ ┌──────────────┐ ┌──────────────┐│  │
│  │ │ peri_apb_    │ │ ipu_apb_     ││  │
│  │ │ wrapper      │ │ wrapper      ││  │
│  │ │ (GPIO,HEX)   │ │ (IPU CTL)    ││  │
│  │ └──────────────┘ └──────────────┘│  │
│  │ ┌──────────────┐                  │  │
│  │ │ ipu_core     │ (Image Processing)│
│  │ └──────────────┘                  │  │
│  │ ┌──────────────┐                  │  │
│  │ │ 3x BRAM      │ (Shared Memory) │  │
│  │ │ img_in/out   │                  │  │
│  │ │ img_tmp      │                  │  │
│  │ └──────────────┘                  │  │
│  └───────────────────────────────────┘  │
│                                          │
│  I/O Connections:                        │
│  • CLOCK_50 → clk                       │
│  • KEY[0] → rst_n (via synchronizer)    │
│  • SW[17:0] → i_io_sw[31:0]             │
│  • HEX0-7, LEDR, LEDG, LCD → outputs   │
│  • PC_debug, ipu_irq → analysis         │
└─────────────────────────────────────────┘
```

### Key Design Parameters:

| Parameter | Value | Description |
|-----------|-------|-------------|
| **Clock Frequency** | 50 MHz | Main system clock |
| **APB Bus Width** | 32-bit | Data + address paths |
| **BRAM Depth** | 192 KB each | 3x dual-port BRAMs |
| **CPU Word Size** | 32-bit | RV32I ISA |
| **Reset Polarity** | Active LOW | KEY[0], rst_n |

### Important Signals:

```verilog
// Inputs from DE10 board
input         CLOCK_50       // 50 MHz clock
input  [17:0] SW             // Switches
input  [ 3:0] KEY            // Buttons (KEY[0]=reset)

// Outputs to DE10 board
output [31:0] PC_debug       // CPU Program Counter
output [ 6:0] HEX0-7         // 7-segment displays
output [17:0] LEDR           // Red LEDs
output [ 8:0] LEDG           // Green LEDs
output [11:0] LCD_*          // LCD control/data

// Internal (for future expansion)
// o_ipu_irq: IPU interrupt status
```

---

## Synthesis & Implementation Checklist

- [ ] Update `single_cycle.out.sdc` with board I/O delays
- [ ] Verify all pins assigned in Quartus
- [ ] Run timing analysis (Tools → Timing Analyzer)
- [ ] Check for hold violations (adjust clock uncertainty if needed)
- [ ] Simulate with wrapper.sv + soc_top testbench
- [ ] Configure BRAM initialization paths in Quartus
- [ ] Program device via USB Blaster II
- [ ] Verify I/O operation on hardware (LEDs, HEX, switches)

---

## References

1. **DE10-Standard User Manual** - Terasic  
   - Full pin-out and board schematics
   - Power delivery and thermal specs

2. **Cyclone V Device Datasheet** - Intel Altera  
   - Electrical characteristics
   - Timing parameters
   - I/O standards (LVCMOS, etc.)

3. **Quartus Prime User Guide** - Intel Altera  
   - SDC constraint syntax
   - Timing analysis workflow

4. **SoC Design Patterns**  
   - APB4 protocol (ARM AMBA specification)
   - Dual-port BRAM arbitration
   - Reset sequencing for digital design

---

**Revision History:**
- v1.0 (2025-03-24): Initial DE10-Standard specifications for soc_top integration

