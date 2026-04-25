# t_compute-fusing software reference

This package is a software reference model for the current RTL behavior of the transmission-computing and haze-removal/fusing path built from:

- `tx_get.v`
- `haze_removal_cal.v`

It generates directed test patterns and golden output files for verification.

## Scope

The model covers the arithmetic already present in the RTL:

1. **Transmission computing** (`tx_get`)
2. **Dehaze / fusing** (`haze_removal_cal`)

It does **not** model `dark_channel`, `calculate_A`, or timing alignment. Those are treated as already-produced inputs:

- `dark` = dark-channel pixel
- `A` = atmospheric light value
- `src_rgb` = aligned source RGB pixel

## Algorithm used

### 1) Transmission computing

From `tx_get.v`:

- `modification_value = 243` which approximates `0.95 * 256`
- `modify_A = dark * 243`
- `tx_raw = 255 - (modify_A / A)`

The RTL uses integer arithmetic. The software model matches that behavior.

Equivalent form:

```text
 tx_raw = 255 - floor_toward_zero((243 * dark) / A)
```

The output of this block is stored as 8-bit.

### 2) Fusing / haze removal

From `haze_removal_cal.v`:

- `tx_min = 26`
- `tx_used = max(tx_raw, tx_min)`
- for each color channel:

```text
value_tem = ((src - A) << 8) + A * tx_used
out       = value_tem / tx_used
```

The RTL uses **signed division** and then only keeps the low 8 bits at the output.
The Python model matches this by:

- using truncation toward zero for signed division
- applying `& 0xFF` at the end of each output channel

## Important RTL-matching notes

### Signed division

Python `//` is not a good match for Verilog signed division because Python floors toward negative infinity.
The model therefore uses:

```python
int(a / b)
```

which truncates toward zero and matches the intent of Verilog signed division for these test values.

### 8-bit output behavior

The RTL finally exposes only `[7:0]` of the channel result. That means the software golden model also keeps only the low 8 bits:

```python
out = q & 0xFF
```

So this package is meant to match the **current RTL behavior**, not a separately saturated image-processing model.

## Files

### `t_compute_fuse_sw.py`
Python reference model and pattern generator.

### `t_compute_fuse_input.hex`
Input patterns, one case per line.

Input word format, 48-bit packed:

```text
[47:40] dark
[39:32] A
[31:24] src_r
[23:16] src_g
[15: 8] src_b
[ 7: 0] case_id
```

### `t_compute_fuse_golden.hex`
Golden outputs, one case per line.

Golden word format, 40-bit packed:

```text
[39:32] tx_raw
[31:24] out_r
[23:16] out_g
[15: 8] out_b
[ 7: 0] case_id
```

### `t_compute_fuse_cases.csv`
Human-readable table of all 20 cases and results.

### `t_compute_fuse_case_table.md`
Markdown summary table for quick inspection.

## Directed cases included

The 20 generated cases cover:

- clear / light / moderate / heavy haze
- dark close to `A`
- low transmission and clamp-to-`tx_min`
- dark / bright pixels
- RGB-dominant colors
- `src < A`, `src = A`, `src > A`
- low `A` and high `A`
- near-black and near-white cases

## How to run

From the same folder:

```bash
python3 t_compute_fuse_sw.py
```

The script regenerates all `.hex`, `.csv`, and `.md` files.

## Suggested RTL testbench usage

A simple pixel-level verification flow can be:

1. Read one line from `t_compute_fuse_input.hex`
2. Unpack `dark`, `A`, `src_r`, `src_g`, `src_b`
3. Drive:
   - `tx_get` with `dark`, `A`
   - `haze_removal_cal` with aligned `src_rgb`, `tx_raw`, `A`
4. Compare against one line from `t_compute_fuse_golden.hex`

## Recommended next step

After this pixel-level reference passes, extend to a small streaming testbench by adding:

- `valid` / `href` / `vsync`
- latency compensation
- optional frame-based test images

