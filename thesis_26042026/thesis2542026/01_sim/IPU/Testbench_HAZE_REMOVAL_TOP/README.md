# Testbench_HAZE_REMOVAL_TOP

Standalone testbench package for `haze_removal_top` with per-phase dump and image export.

## Folder Layout

- `sim/haze_removal_top_phase_tb.sv`: phase dump testbench (20 cases, 5x5 each)
- `script/run_haze_phase_dump.tcl`: Questa compile/run script
- `script/export_phase_images.py`: convert phase dump HEX files to PPM/PGM images
- `sim/output/`: raw dump outputs per case
- `sim/image/`: exported images grouped by case

## What Is Dumped Per Case

From simulation, for each `case_xx`:

- `case_xx_src_rgb.hex`: input source RGB (24-bit)
- `case_xx_dark_u8.hex`: dark channel map
- `case_xx_sky_u8.hex`: sky mask map (0/255)
- `case_xx_tx_u8.hex`: transmission map from TX core
- `case_xx_tx_bank_u8.hex`: transmission map observed from bank read path
- `case_xx_recovery_rgb.hex`: final recovery RGB output (24-bit)
- `case_xx_adc_info.txt`: atmospheric light and ADC debug info

## Run Simulation (Questa)

From workspace root:

```tcl
vsim -c -do "do 01_sim/IPU/Testbench_HAZE_REMOVAL_TOP/script/run_haze_phase_dump.tcl"
```

Optional environment overrides before running:

- `PATTERN_FILE`: path to pattern file (default: `../09_pattern/pattern_haze_removal_top_rgb5x5.hex` from Questa working dir)
- `DUMP_DIR`: output dump folder (default: `../01_sim/IPU/Testbench_HAZE_REMOVAL_TOP/sim/output`)

## Export Images

From workspace root:

```bash
python 01_sim/IPU/Testbench_HAZE_REMOVAL_TOP/script/export_phase_images.py
```

Optional arguments:

```bash
python 01_sim/IPU/Testbench_HAZE_REMOVAL_TOP/script/export_phase_images.py --input 01_sim/IPU/Testbench_HAZE_REMOVAL_TOP/sim/output --output 01_sim/IPU/Testbench_HAZE_REMOVAL_TOP/sim/image --cases 20
```

## Output Images Per Case

For each case folder in `sim/image/case_xx/`:

- `01_src.ppm`
- `02_dark.pgm`
- `03_sky.pgm`
- `04_tx_core.pgm`
- `05_tx_bank_read.pgm`
- `06_recovery.ppm`

You can open `.ppm/.pgm` directly in many image viewers and tools, or convert them to PNG using external utilities if needed.
