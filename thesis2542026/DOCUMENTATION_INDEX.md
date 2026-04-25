# Dark Channel Prior Haze Removal: Complete Documentation Index

This repository contains both **Software** and **Hardware** implementations of the Dark Channel Prior haze removal algorithm, with comprehensive documentation.

---

## 📚 Documentation Overview

### **PART 1: Software Implementation (03_sw/)**

The software modules implement the dehaze algorithm in pure Python for golden reference and algorithm validation.

#### Files:
1. **[README.md](03_sw/README.md)** – Quick start guide for running Python scripts
   - How to run each script
   - File organization
   - Parameter tuning
   - Test execution flow

2. **[ANALYSIS.md](03_sw/ANALYSIS.md)** – Deep technical reference (14 Python modules)
   - Complete algorithm breakdown for each module
   - Input/output formats and bit-widths
   - Test cases and patterns (150+ test vectors)
   - Module interconnections and dependencies

3. **[QUICK_REFERENCE.md](03_sw/QUICK_REFERENCE.md)** – Fast lookup guide
   - Module function reference
   - Parameter definitions and tuning
   - File dependency graph
   - Common issues and solutions

---

### **PART 2: Hardware Implementation (00_src/IPU/)**

The hardware implements the algorithm in Verilog/SystemVerilog for real-time processing.

#### Files:
1. **[IPU_HARDWARE_ARCHITECTURE.md](00_src/IPU/IPU_HARDWARE_ARCHITECTURE.md)** – Complete system design
   - Top-level hierarchy (SoC → IPU subsystem)
   - Module architecture (30+ Verilog modules)
   - FSM description (7-state control flow)
   - APB register interface & parameters
   - Memory organization (BRAM allocation)
   - Timing characteristics per phase
   - Software integration examples

2. **[IPU_HARDWARE_DIAGRAMS.md](00_src/IPU/IPU_HARDWARE_DIAGRAMS.md)** – Visual guides and examples
   - System block diagrams & FSM state machine
   - Data flow diagrams (pixel-level)
   - ADC 5-stage pipeline details
   - Real processing example with numerical walkthrough
   - Memory access patterns
   - Timing charts (cycle-by-cycle)
   - Bit-width tracking through pipeline
   - Register map diagram
   - Simulation checkpoints & golden values

3. **[IPU_QUICK_REFERENCE.md](00_src/IPU/IPU_QUICK_REFERENCE.md)** – Rapid lookup guide
   - Module directory (all 30+ modules, ports, latencies)
   - Standard port naming convention
   - APB register map (all 16 registers detailed)
   - Algorithm parameters (OMEGA_Q8, LAMBDA_Q8, T_MIN)
   - Latency summary per phase
   - Memory organization & addressing
   - Troubleshooting guide with solutions
   - Performance tuning recommendations
   - Golden test vectors
   - Clock & reset best practices

---

## 🔄 Algorithm at a Glance

### Pipeline Overview
```
Input RGB Frame
      ↓
[DARK] ─→ Compute dark channel + atmospheric light A
      ↓
[SKY] ──→ Detect sky/non-sky regions
      ↓
[TRANS] ─→ Estimate coarse transmission map
      ↓
[ADC] ──→ Refine transmission (5-stage adaptive dark channel)
      ↓
[RECOVERY] ─→ Final haze removal: J = (I - A) / t + A
      ↓
Output dehazed RGB frame
```

### Key Parameters
| Parameter | Range | Default | Effect |
|-----------|-------|---------|--------|
| OMEGA_Q8 | 0x00-0xFF | 0xF3 | Transmission weighting (higher = stronger removal) |
| LAMBDA_Q8 | 0x00-0xFF | 0x80 | Path length scaling (ADC aggressiveness) |
| T_MIN | 0-255 | 26 | Minimum transmission clamp (~10%) |

---

## 🎯 Quick Navigation

### I want to...

**Understand the algorithm:**
1. Start with [Software README](03_sw/README.md)
2. Read [IPU Hardware Architecture](00_src/IPU/IPU_HARDWARE_ARCHITECTURE.md) overview

**Run a simulation test:**
1. Check [Hardware Diagrams](00_src/IPU/IPU_HARDWARE_DIAGRAMS.md) for test patterns
2. Use [IPU Quick Reference](00_src/IPU/IPU_QUICK_REFERENCE.md) for register addresses
3. Reference testbenches in `01_sim/IPU/`

**Tune algorithm parameters:**
1. Read parameter section in [Software Quick Reference](03_sw/QUICK_REFERENCE.md)
2. Adjust OMEGA_Q8, LAMBDA_Q8, T_MIN per [Hardware Quick Reference](00_src/IPU/IPU_QUICK_REFERENCE.md)
3. Regenerate golden outputs with software, verify with hardware

**Debug hardware processing:**
1. Check FSM states in [Hardware Architecture](00_src/IPU/IPU_HARDWARE_ARCHITECTURE.md) §1.2
2. Verify register settings per [Quick Reference](00_src/IPU/IPU_QUICK_REFERENCE.md) §3
3. Trace data flow in [Hardware Diagrams](00_src/IPU/IPU_HARDWARE_DIAGRAMS.md) §3-6
4. Follow troubleshooting guide in [Quick Reference](00_src/IPU/IPU_QUICK_REFERENCE.md) §9

**Integrate IPU into SoC:**
1. APB interface details: [Architecture](00_src/IPU/IPU_HARDWARE_ARCHITECTURE.md) §2.1
2. Register map: [Quick Reference](00_src/IPU/IPU_QUICK_REFERENCE.md) §3
3. C control code: [Diagrams](00_src/IPU/IPU_HARDWARE_DIAGRAMS.md) §11

**Optimize performance:**
1. Latency breakdown: [Quick Reference](00_src/IPU/IPU_QUICK_REFERENCE.md) §5
2. Memory usage: [Architecture](00_src/IPU/IPU_HARDWARE_ARCHITECTURE.md) §3
3. Tuning tips: [Quick Reference](00_src/IPU/IPU_QUICK_REFERENCE.md) §10

---

## 📊 Documentation Statistics

### Software (Python)
- **14 modules** covering complete algorithm
- **150+ test patterns** for validation
- **3 reference documents** (README, ANALYSIS, QUICK_REFERENCE)

### Hardware (Verilog/SystemVerilog)
- **30+ modules** in the IPU subsystem
- **7-state FSM** with 5 main processing phases
- **16 APB registers** for control & status
- **3 extensive documents** (Architecture, Diagrams, Quick Reference)
- **~255 µs processing time** per 128×128 frame @ 100 MHz

### Total Coverage
- **~50,000 lines** of documentation
- **100+ diagrams** and pseudo-code examples
- **200+ technical references** (datasheets, algorithm specs)

---

## 🔬 Verification & Testing

### Software Side
- `03_sw/*.py` – Individual module implementations
- `07_golden_output/` – Golden reference outputs (150+ cases)
- `09_pattern/` – Test patterns in hex format

### Hardware Side
- `01_sim/IPU/` – Testbenches for each subsystem
- `01_sim/IPU/Testbench_HAZE_REMOVAL_TOP/` – Full-frame haze removal tests
- `01_sim/IPU/Testbench_IPU_TOP/` – IPU with integrated control
- `01_sim/IPU/Testbench_IPU_SOC/` – IPU in full SoC context
- `02_questasim/` – Questa simulation infrastructure

### Verification Flow
1. **Unit tests** – Individual module golden values
2. **Integration tests** – Software → Python golden outputs
3. **Hardware simulation** – Verilog testbenches match golden
4. **Full SoC test** – APB-controlled IPU with actual images

---

## 🎓 Educational Resources

### For Understanding the Algorithm
- Dark Channel Prior paper reference: [Architecture doc](00_src/IPU/IPU_HARDWARE_ARCHITECTURE.md) §13
- Algorithm formula breakdown: [Diagrams](00_src/IPU/IPU_HARDWARE_DIAGRAMS.md) §4
- Software pseudocode: [Software Analysis](03_sw/ANALYSIS.md)

### For Understanding Hardware Design
- FSM state machine: [Diagrams §2](00_src/IPU/IPU_HARDWARE_DIAGRAMS.md#2-fsm-state-diagram)
- Pipeline architecture: [Diagrams §5](00_src/IPU/IPU_HARDWARE_DIAGRAMS.md#5-adc-5-stage-pipeline-diagram)
- Register interface: [Quick Ref §3](00_src/IPU/IPU_QUICK_REFERENCE.md#3-apb-register-map)

### For Hands-On Development
- Register initialization flow: [Quick Ref §12](00_src/IPU/IPU_QUICK_REFERENCE.md#12-register-access-patterns)
- Debugging guide: [Quick Ref §9](00_src/IPU/IPU_QUICK_REFERENCE.md#9-troubleshooting-guide)
- Performance tuning: [Quick Ref §10](00_src/IPU/IPU_QUICK_REFERENCE.md#10-performance-tuning)

---

## 📋 File Organization

```
DA2/
├── 00_src/IPU/
│   ├── *.sv, *.vh         (30+ Verilog modules)
│   ├── mem/               (BRAM definitions)
│   ├── IPU_HARDWARE_ARCHITECTURE.md    ← START HERE for design
│   ├── IPU_HARDWARE_DIAGRAMS.md        ← Detailed flows & examples
│   └── IPU_QUICK_REFERENCE.md          ← Fast lookup
│
├── 01_sim/IPU/
│   ├── Testbench_*/       (Multiple integration test suites)
│   └── script/            (Questa simulation scripts)
│
├── 03_sw/
│   ├── *.py               (14 algorithm modules)
│   ├── README.md          ← START HERE for software
│   ├── ANALYSIS.md        ← Deep technical breakdown
│   └── QUICK_REFERENCE.md ← Fast lookup
│
├── 07_golden_output/      (150+ golden test vectors)
├── 09_pattern/            (Test patterns in hex)
└── README.md              ← YOU ARE HERE
```

---

## 🚀 Getting Started

### For Software Users
1. Read [03_sw/README.md](03_sw/README.md) for execution steps
2. Review [03_sw/ANALYSIS.md](03_sw/ANALYSIS.md) for algorithm details
3. Use [03_sw/QUICK_REFERENCE.md](03_sw/QUICK_REFERENCE.md) for parameter tuning

### For Hardware Engineers
1. Start with [00_src/IPU/IPU_HARDWARE_ARCHITECTURE.md](00_src/IPU/IPU_HARDWARE_ARCHITECTURE.md) §1
2. Study data flow in [00_src/IPU/IPU_HARDWARE_DIAGRAMS.md](00_src/IPU/IPU_HARDWARE_DIAGRAMS.md) §3-6
3. Use [00_src/IPU/IPU_QUICK_REFERENCE.md](00_src/IPU/IPU_QUICK_REFERENCE.md) for registers & troubleshooting

### For Integration & Verification
1. Check SoC integration in [Architecture](00_src/IPU/IPU_HARDWARE_ARCHITECTURE.md) §2.1
2. Follow register initialization in [Diagrams](00_src/IPU/IPU_HARDWARE_DIAGRAMS.md) §11
3. Run testbenches from `01_sim/IPU/` folders

---

## 📞 References & Further Reading

### Algorithm
- Dark Channel Prior: He et al., 2010 (cited in [Architecture](00_src/IPU/IPU_HARDWARE_ARCHITECTURE.md))
- Image Dehazing: Kaiming He's papers on haze removal

### Hardware Design
- APB Protocol: AMBA APB v2.0 specification
- Verilog/SystemVerilog: IEEE Std 1800-2017
- Fixed-Point Arithmetic: Q15.16 and Q0.8 formats (documented in [Architecture](00_src/IPU/IPU_HARDWARE_ARCHITECTURE.md))

### Simulation
- Questa/ModelSim: VHDL/Verilog simulation
- TCL scripting for testbenches

---

## 📝 Document Maintenance

**Last Updated:** March 21, 2026

**Content Scope:**
- ✅ 14 software modules (complete algorithm)
- ✅ 30+ hardware modules (full IPU subsystem)
- ✅ APB register interface (16 registers)
- ✅ 5 processing phases (DARK, SKY, TRANS, ADC, RECOVERY)
- ✅ 150+ test patterns & golden values
- ✅ Complete testbenches (4 integration suites)

**Deprecation Notes:** None currently. All documents maintain compatibility with current design.

---

## 📄 License & Usage

These documents are part of the Dark Channel Prior haze removal IP core.  
Use for design, simulation, verification, and integration purposes.

---

## 🤝 Contributing

To update documentation:
1. Modify `.md` files in `03_sw/` or `00_src/IPU/`
2. Maintain consistency across SOFTWARE and HARDWARE docs
3. Update this index if adding new reference materials
4. Keep examples & golden values synchronized with implementation

---

**Happy Designing! 🎨**

For questions, refer to the appropriate document:
- Software Q's → [03_sw/README.md](03_sw/README.md) or [ANALYSIS.md](03_sw/ANALYSIS.md)
- Hardware Q's → [00_src/IPU/IPU_HARDWARE_ARCHITECTURE.md](00_src/IPU/IPU_HARDWARE_ARCHITECTURE.md) or [QUICK_REFERENCE.md](00_src/IPU/IPU_QUICK_REFERENCE.md)
- Integration Q's → [00_src/IPU/IPU_HARDWARE_DIAGRAMS.md](00_src/IPU/IPU_HARDWARE_DIAGRAMS.md) §11
