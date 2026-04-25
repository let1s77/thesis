#!/usr/bin/env python3
from dataclasses import dataclass, asdict
from pathlib import Path
import csv
from typing import List, Tuple

from adc_estimation_top import TESTCASES as ADC_TESTCASES, adc_estimation_top
from adc_subblock_hexgen import (
    hw_pixel_distance,
    hw_path_length,
    hw_rlimit,
    hw_ase_masked_min,
)


# -----------------------------------------------------------------------------
# Parameters aligned with current RTL/software blocks
# -----------------------------------------------------------------------------
A0 = 150
USE_DARK = 0
USE_SKY = 1
T_SKY = 255
OMEGA_Q8 = 243
T_MIN = 26
LAMBDA = 0.2
MODIFICATION_VALUE = 243


@dataclass
class HazeTopCase:
    case_id: int
    name: str
    rgb5x5: List[Tuple[int, int, int]]  # (R,G,B), row-major 25 pixels


def clamp8(v: int) -> int:
    if v < 0:
        return 0
    if v > 255:
        return 255
    return v


def compute_dark_channel(r: int, g: int, b: int) -> int:
    return min(r, g, b)


def compute_grayscale(r: int, g: int, b: int, mode: int = 2) -> int:
    sum_val = 5 * r + 9 * g + 2 * b
    integer_part = (sum_val >> 4) & 0xFF
    fraction_part = sum_val & 0xF

    if mode == 0:
        return (integer_part + 1) & 0xFF if fraction_part > 0 else integer_part
    if mode == 1:
        return integer_part

    if fraction_part > 8:
        return (integer_part + 1) & 0xFF
    if fraction_part < 8:
        return integer_part
    return integer_part if (integer_part & 1) == 0 else (integer_part + 1) & 0xFF


def atmospheric_light_frame(pixels: List[Tuple[int, int, int]]) -> Tuple[int, int, int]:
    max_dark = 0
    max_intensity = 0
    a_r, a_g, a_b = 0, 0, 0

    for r, g, b in pixels:
        dark = compute_dark_channel(r, g, b)
        intensity = r + g + b
        if dark > max_dark or (dark == max_dark and intensity > max_intensity):
            max_dark = dark
            max_intensity = intensity
            a_r, a_g, a_b = r, g, b

    return a_r, a_g, a_b


def sky_recognition_pixel(gray: int, dark_ch: int) -> int:
    src_val = dark_ch if USE_DARK else gray
    return 1 if src_val > A0 else 0


def build_inv_lut_q16() -> List[int]:
    lut = [0] * 256
    lut[0] = 0xFFFFFF
    for i in range(1, 256):
        lut[i] = (255 << 16) // i
    return lut


INV_LUT = build_inv_lut_q16()


def norm_channel(pix: int, inv_q16: int) -> int:
    mul_q = pix * inv_q16
    q16 = (mul_q >> 16) & 0xFFFF
    return 0xFF if (q16 >> 8) != 0 else (q16 & 0xFF)


def omega_clamp(min_norm: int) -> int:
    x_scaled = (min_norm * OMEGA_Q8) >> 8
    t_raw = 255 - (x_scaled & 0xFF)
    return max(t_raw, T_MIN) & 0xFF


def estimate_transmission_pixel(r: int, g: int, b: int, sky: int,
                                a_r: int, a_g: int, a_b: int) -> int:
    if USE_SKY and sky:
        return T_SKY

    inv_r = INV_LUT[a_r]
    inv_g = INV_LUT[a_g]
    inv_b = INV_LUT[a_b]

    n_r = norm_channel(r, inv_r)
    n_g = norm_channel(g, inv_g)
    n_b = norm_channel(b, inv_b)

    min_n = min(n_r, n_g, n_b)
    return omega_clamp(min_n)


def trunc_div(a: int, b: int) -> int:
    if b == 0:
        raise ZeroDivisionError("Division by zero")
    return int(a / b)


def tx_get(dark: int, a: int) -> int:
    modify_a = dark * MODIFICATION_VALUE
    tx = 255 - trunc_div(modify_a, a)
    return tx & 0xFF


def haze_remove_channel(src: int, a: int, tx_in: int) -> int:
    tx_value = tx_in if tx_in >= T_MIN else T_MIN
    value_tem = ((src - a) << 8) + a * tx_value
    q = trunc_div(value_tem, tx_value)
    return q & 0xFF


def gray_to_rgb_frame(gray5x5: List[int], phase: int) -> List[Tuple[int, int, int]]:
    out = []
    for i, g in enumerate(gray5x5):
        # Build deterministic channel offsets so A-selection and sky/tx are exercised.
        d0 = (i + phase) % 7
        d1 = ((i * 3) + phase) % 11
        r = clamp8(g + 8 + d0)
        gc = clamp8(g)
        b = clamp8(g - 8 + d1)
        out.append((r, gc, b))
    return out


def build_cases() -> List[HazeTopCase]:
    cases: List[HazeTopCase] = []
    for case_id, (name, gray5x5, _mc5x5_unused) in enumerate(ADC_TESTCASES):
        rgb5x5 = gray_to_rgb_frame(gray5x5, phase=case_id)
        cases.append(HazeTopCase(case_id=case_id, name=name, rgb5x5=rgb5x5))
    return cases


def run_case(c: HazeTopCase):
    # Stage DARK + SKY + TRANS on 5x5 frame
    dark_list = [compute_dark_channel(r, g, b) for r, g, b in c.rgb5x5]
    gray_list = [compute_grayscale(r, g, b) for r, g, b in c.rgb5x5]
    a_r, a_g, a_b = atmospheric_light_frame(c.rgb5x5)

    sky_list = []
    tx_list = []
    for i, (r, g, b) in enumerate(c.rgb5x5):
        sky = sky_recognition_pixel(gray_list[i], dark_list[i])
        tx = estimate_transmission_pixel(r, g, b, sky, a_r, a_g, a_b)
        sky_list.append(sky)
        tx_list.append(tx)

    # Stage ADC: RTL currently feeds bank tx stream to both gray and mc inputs.
    dp = hw_pixel_distance(tx_list)
    dl = hw_path_length(dp, lambda_q8=51)
    rlimit = hw_rlimit(dl)
    adc_dark = hw_ase_masked_min(rlimit, dl, tx_list) & 0xFF

    # Stage RECOVERY (t_compute_fuse): use center RGB and A_R (matches RTL skeleton)
    center_r, center_g, center_b = c.rgb5x5[12]
    tx_raw = tx_get(adc_dark, a_r)
    tx_used = tx_raw if tx_raw >= T_MIN else T_MIN
    out_r = haze_remove_channel(center_r, a_r, tx_raw)
    out_g = haze_remove_channel(center_g, a_r, tx_raw)
    out_b = haze_remove_channel(center_b, a_r, tx_raw)

    # Packed words for simple TB checking
    # input_word: [79:72]case [71:64]A_R [63:56]ADC_dark [55:48]src_r [47:40]src_g [39:32]src_b [31:0]reserved
    input_word = (
        ((c.case_id & 0xFF) << 72)
        | ((a_r & 0xFF) << 64)
        | ((adc_dark & 0xFF) << 56)
        | ((center_r & 0xFF) << 48)
        | ((center_g & 0xFF) << 40)
        | ((center_b & 0xFF) << 32)
    )

    # golden_word: [47:40]case [39:32]tx_raw [31:24]tx_used [23:16]out_r [15:8]out_g [7:0]out_b
    golden_word = (
        ((c.case_id & 0xFF) << 40)
        | ((tx_raw & 0xFF) << 32)
        | ((tx_used & 0xFF) << 24)
        | ((out_r & 0xFF) << 16)
        | ((out_g & 0xFF) << 8)
        | (out_b & 0xFF)
    )

    return {
        "case_id": c.case_id,
        "name": c.name,
        "A_R": a_r,
        "A_G": a_g,
        "A_B": a_b,
        "adc_dark": adc_dark,
        "tx_raw": tx_raw,
        "tx_used": tx_used,
        "src_r": center_r,
        "src_g": center_g,
        "src_b": center_b,
        "out_r": out_r,
        "out_g": out_g,
        "out_b": out_b,
        "input_hex": f"{input_word:020X}",
        "golden_hex": f"{golden_word:012X}",
        "rgb5x5": c.rgb5x5,
        "tx5x5": tx_list,
        "sky5x5": sky_list,
    }


def write_outputs(pattern_dir: Path, golden_dir: Path):
    pattern_dir.mkdir(parents=True, exist_ok=True)
    golden_dir.mkdir(parents=True, exist_ok=True)

    rows = [run_case(c) for c in build_cases()]

    # 1) Top-level compact pattern (one line per case)
    with open(pattern_dir / "pattern_haze_removal_top_input.hex", "w") as f:
        for r in rows:
            f.write(r["input_hex"] + "\n")

    # 2) Frame-level RGB pattern (25 lines per case)
    with open(pattern_dir / "pattern_haze_removal_top_rgb5x5.hex", "w") as f:
        for r in rows:
            f.write(f"// case_{r['case_id']:02d} {r['name']}\n")
            for (rr, gg, bb) in r["rgb5x5"]:
                f.write(f"{((bb & 0xFF) << 16 | (gg & 0xFF) << 8 | (rr & 0xFF)):06X}\n")
            f.write("\n")

    # 3) Final golden (one line per case)
    with open(golden_dir / "golden_haze_removal_top.hex", "w") as f:
        for r in rows:
            f.write(r["golden_hex"] + "\n")

    # 4) Intermediate golden: atmospheric light, adc_dark, tx map
    with open(golden_dir / "golden_haze_removal_top_A.hex", "w") as f:
        for r in rows:
            f.write(f"{((r['A_B'] & 0xFF) << 16 | (r['A_G'] & 0xFF) << 8 | (r['A_R'] & 0xFF)):06X}\n")

    with open(golden_dir / "golden_haze_removal_top_adc.hex", "w") as f:
        for r in rows:
            f.write(f"{r['adc_dark'] & 0xFF:02X}\n")

    with open(golden_dir / "golden_haze_removal_top_tx5x5.hex", "w") as f:
        for r in rows:
            f.write(f"// case_{r['case_id']:02d} {r['name']}\n")
            for tx in r["tx5x5"]:
                f.write(f"{tx & 0xFF:02X}\n")
            f.write("\n")

    with open(golden_dir / "haze_removal_top_cases.csv", "w", newline="") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=[
                "case_id", "name", "A_R", "A_G", "A_B", "adc_dark",
                "tx_raw", "tx_used", "src_r", "src_g", "src_b",
                "out_r", "out_g", "out_b", "input_hex", "golden_hex",
            ],
        )
        writer.writeheader()
        for r in rows:
            out = {k: r[k] for k in writer.fieldnames}
            writer.writerow(out)

    return rows


def main():
    repo_root = Path(__file__).resolve().parents[1]
    pattern_dir = repo_root / "09_pattern"
    golden_dir = repo_root / "07_golden_output"

    rows = write_outputs(pattern_dir, golden_dir)

    print(f"Generated {len(rows)} haze_removal_top cases")
    print(f"Pattern file : {pattern_dir / 'pattern_haze_removal_top_input.hex'}")
    print(f"Pattern file : {pattern_dir / 'pattern_haze_removal_top_rgb5x5.hex'}")
    print(f"Golden file  : {golden_dir / 'golden_haze_removal_top.hex'}")
    print("--- Dump (input_hex -> golden_hex) ---")
    for r in rows:
        print(f"case {r['case_id']:02d}: {r['input_hex']} -> {r['golden_hex']}")


if __name__ == "__main__":
    main()
