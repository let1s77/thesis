#!/usr/bin/env python3
"""
adc_subblock_hexgen.py

Generate $readmemh-compatible hex files for each ADC sub-block testbench.
Uses exact integer (RTL-matching) arithmetic — NO floating-point.

Output files:
  09_pattern/pattern_pixel_distance.hex   (25 x 8-bit gray per case)
  07_golden_output/golden_pixel_distance.hex (25 x 9-bit dp per case)

  09_pattern/pattern_path_length.hex      (25 x 9-bit dp per case)
  07_golden_output/golden_path_length.hex (25 x 10-bit dl per case)

  09_pattern/pattern_rlimit.hex           (25 x 10-bit dl per case)
  07_golden_output/golden_rlimit.hex      (1 x 10-bit rlimit per case)
  07_golden_output/golden_rlimit_dl.hex   (25 x 10-bit dl pass-through per case)

  09_pattern/pattern_ase_rlimit.hex       (1 x 10-bit rlimit per case)
  09_pattern/pattern_ase_dl.hex           (25 x 10-bit dl per case)
  09_pattern/pattern_ase_mc.hex           (25 x 8-bit MC per case)
  07_golden_output/golden_ase_adc.hex     (1 x 8-bit ADC per case)
"""
import argparse
from pathlib import Path
from typing import Dict, List, Tuple

# ============================================================================
# Same test infrastructure as adc_sub_block.py
# ============================================================================
CENTER = (2, 2)
ALL_COORDS = [(r, c) for r in range(5) for c in range(5)]

SPATIAL_TABLE = [
    4, 3, 2, 3, 4,
    3, 2, 1, 2, 3,
    2, 1, 0, 1, 2,
    3, 2, 1, 2, 3,
    4, 3, 2, 3, 4,
]


def idx(rc: Tuple[int, int]) -> int:
    return rc[0] * 5 + rc[1]


def generate_path_to(target: Tuple[int, int]) -> List[Tuple[int, int]]:
    cr, cc = CENTER
    tr, tc = target
    path = [(cr, cc)]
    r, c = cr, cc
    while r != tr and c != tc:
        r += 1 if tr > r else -1
        c += 1 if tc > c else -1
        path.append((r, c))
    while r != tr:
        r += 1 if tr > r else -1
        path.append((r, c))
    while c != tc:
        c += 1 if tc > c else -1
        path.append((r, c))
    return path


PATHS: Dict[Tuple[int, int], List[Tuple[int, int]]] = {
    rc: generate_path_to(rc) for rc in ALL_COORDS if rc != CENTER
}


# ============================================================================
# Hardware-matching integer sub-block functions
# ============================================================================
def hw_pixel_distance(gray: List[int]) -> List[int]:
    """Compute dp_total[25] using RTL edge-sum logic (integer)."""
    dp = [0] * 25
    center_val = gray[idx(CENTER)]

    for target, path in PATHS.items():
        total = 0
        for a, b in zip(path[:-1], path[1:]):
            va = gray[idx(a)]
            vb = gray[idx(b)]
            total += abs(va - vb)
        dp[idx(target)] = total

    dp[idx(CENTER)] = 0
    return dp


def hw_path_length(dp: List[int], lambda_q8: int = 51) -> List[int]:
    """Compute d_lambda[25] = spatial + (lambda_q8 * dp) >> 8 (integer)."""
    dl = [0] * 25
    for i in range(25):
        prod = lambda_q8 * dp[i]
        lambda_dp = prod >> 8
        dl[i] = SPATIAL_TABLE[i] + lambda_dp
    dl[idx(CENTER)] = 0
    return dl


def hw_rlimit(dl: List[int]) -> int:
    """Compute r_limit = (sum(dl) * 41) >> 10 (integer)."""
    s = sum(dl)
    return (s * 41) >> 10


def hw_ase_masked_min(rlimit: int, dl: List[int], mc: List[int]) -> int:
    """ASE mask + min filter (integer)."""
    min_val = 255
    for i in range(25):
        rc = ALL_COORDS[i]
        if rc == CENTER:
            in_ase = True
        else:
            in_ase = (dl[i] <= rlimit)
        if in_ase:
            if mc[i] < min_val:
                min_val = mc[i]
    return min_val


# ============================================================================
# 20 testcases (same as adc_sub_block.py)
# ============================================================================
def make_case(name, gray_rows, mc_rows):
    gray = [v for row in gray_rows for v in row]
    mc = [v for row in mc_rows for v in row]
    return (name, gray, mc)


TESTCASES = [
    make_case("flat_uniform", [[100]*5]*5, [[50]*5]*5),
    make_case("center_dark_flat", [[120]*5]*5,
              [[80]*5,[80]*5,[80,80,10,80,80],[80]*5,[80]*5]),
    make_case("horizontal_edge", [[40]*5,[40]*5,[40]*5,[200]*5,[200]*5],
              [[90,88,86,84,82]]*3+[[40,38,36,34,32]]*2),
    make_case("vertical_edge", [[30,30,120,220,220]]*5,
              [[100,95,70,50,45]]*5),
    make_case("diag_edge_main",
              [[20,20,20,20,20],[20,20,20,20,200],[20,20,20,200,200],
               [20,20,200,200,200],[20,200,200,200,200]],
              [[99,98,97,96,95],[98,90,89,88,20],[97,89,80,22,21],
               [96,88,24,23,22],[95,26,25,24,23]]),
    make_case("diag_edge_anti",
              [[200,200,200,200,20],[200,200,200,20,20],[200,200,20,20,20],
               [200,20,20,20,20],[20,20,20,20,20]],
              [[10,11,12,13,80],[11,12,13,81,82],[12,13,83,84,85],
               [13,86,87,88,89],[90,91,92,93,94]]),
    make_case("cross_structure",
              [[100,100,180,100,100],[100,100,180,100,100],
               [180,180,180,180,180],[100,100,180,100,100],[100,100,180,100,100]],
              [[70,70,20,70,70],[70,70,20,70,70],[20,20,10,20,20],
               [70,70,20,70,70],[70,70,20,70,70]]),
    make_case("center_bright_island",
              [[50,50,50,50,50],[50,90,90,90,50],[50,90,200,90,50],
               [50,90,90,90,50],[50,50,50,50,50]],
              [[80,79,78,77,76],[79,60,59,58,75],[78,59,20,57,74],
               [77,58,57,56,73],[76,75,74,73,72]]),
    make_case("noisy_small_variation",
              [[100,102,99,101,98],[101,100,103,98,99],[99,101,100,102,100],
               [98,99,101,100,103],[100,98,99,101,100]],
              [[55,53,57,54,56],[54,52,58,55,53],[56,57,50,54,55],
               [53,55,56,52,54],[55,54,53,56,51]]),
    make_case("ramp_horizontal", [[10,40,70,100,130]]*5,
              [[120,110,100,90,80],[119,109,99,89,79],[118,108,20,88,78],
               [117,107,97,87,77],[116,106,96,86,76]]),
    make_case("ramp_vertical", [[10]*5,[40]*5,[70]*5,[100]*5,[130]*5],
              [[120,119,118,117,116],[110,109,108,107,106],[100,99,20,97,96],
               [90,89,88,87,86],[80,79,78,77,76]]),
    make_case("checkerboard_soft",
              [[80,120,80,120,80],[120,80,120,80,120],[80,120,80,120,80],
               [120,80,120,80,120],[80,120,80,120,80]],
              [[60,65,60,65,60],[65,55,65,55,65],[60,65,10,65,60],
               [65,55,65,55,65],[60,65,60,65,60]]),
    make_case("corner_dark_tl",
              [[30,40,50,60,70],[40,50,60,70,80],[50,60,70,80,90],
               [60,70,80,90,100],[70,80,90,100,110]],
              [[5,90,91,92,93],[90,91,92,93,94],[91,92,50,94,95],
               [92,93,94,95,96],[93,94,95,96,97]]),
    make_case("corner_dark_br",
              [[110,100,90,80,70],[100,90,80,70,60],[90,80,70,60,50],
               [80,70,60,50,40],[70,60,50,40,30]],
              [[97,96,95,94,93],[96,95,94,93,92],[95,94,50,92,91],
               [94,93,92,91,90],[93,92,91,90,5]]),
    make_case("ring_structure",
              [[180,180,180,180,180],[180,60,60,60,180],[180,60,30,60,180],
               [180,60,60,60,180],[180,180,180,180,180]],
              [[90,89,88,87,86],[89,40,39,38,85],[88,39,15,37,84],
               [87,38,37,36,83],[86,85,84,83,82]]),
    make_case("left_right_two_regions",
              [[20,20,20,200,200],[20,20,20,200,200],[20,20,20,200,200],
               [20,20,20,200,200],[20,20,20,200,200]],
              [[30,31,32,90,91],[29,28,27,89,88],[26,25,24,87,86],
               [23,22,21,85,84],[20,19,18,83,82]]),
    make_case("top_bottom_two_regions",
              [[20]*5,[20]*5,[100]*5,[200]*5,[200]*5],
              [[70,69,68,67,66],[65,64,63,62,61],[60,59,10,58,57],
               [56,55,54,53,52],[51,50,49,48,47]]),
    make_case("center_valley",
              [[150,150,150,150,150],[150,100,100,100,150],[150,100,20,100,150],
               [150,100,100,100,150],[150,150,150,150,150]],
              [[90,88,86,84,82],[88,40,39,38,80],[86,39,5,37,78],
               [84,38,37,36,76],[82,80,78,76,74]]),
    make_case("random_like_1",
              [[73,91,88,45,20],[65,77,82,49,25],[61,80,95,52,27],
               [58,75,83,50,29],[55,70,79,48,30]],
              [[60,58,56,54,52],[57,55,53,51,49],[54,52,11,48,46],
               [51,49,47,45,43],[48,46,44,42,40]]),
    make_case("random_like_2",
              [[200,180,160,140,120],[180,170,150,130,110],[160,150,145,125,105],
               [140,130,120,115,95],[120,110,100,90,80]],
              [[99,95,91,87,83],[94,90,86,82,78],[89,85,30,77,73],
               [84,80,76,72,68],[79,75,71,67,63]]),
]

NUM_PATTERNS = len(TESTCASES)


# ============================================================================
# Hex file writers
# ============================================================================
def write_hex(path: Path, values: List[int], width: int):
    """Write $readmemh-compatible hex file.
    width: bit-width → determines hex digit count."""
    ndigits = (width + 3) // 4
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        for v in values:
            f.write(f"{v & ((1 << width) - 1):0{ndigits}X}\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lambda_q8", type=int, default=51)
    ap.add_argument("--pattern_dir", type=str, default="../09_pattern")
    ap.add_argument("--golden_dir",  type=str, default="../07_golden_output")
    args = ap.parse_args()

    pdir = Path(args.pattern_dir)
    gdir = Path(args.golden_dir)
    lam = args.lambda_q8

    # Collect all values across all test cases
    # pixel_distance
    all_pat_gray = []
    all_gld_dp   = []
    # path_length
    all_pat_dp   = []
    all_gld_dl   = []
    # rlimit
    all_pat_rl_dl = []
    all_gld_rlimit = []
    all_gld_rl_dl = []     # delayed dl (pass-through check)
    # ase_masked_min
    all_pat_ase_rlimit = []
    all_pat_ase_dl = []
    all_pat_ase_mc = []
    all_gld_ase_adc = []

    # Also collect case names for a report
    report_lines = []

    for case_id, (name, gray, mc) in enumerate(TESTCASES):
        dp = hw_pixel_distance(gray)
        dl = hw_path_length(dp, lam)
        rlimit = hw_rlimit(dl)
        adc = hw_ase_masked_min(rlimit, dl, mc)

        # pixel_distance: pattern=gray[25], golden=dp[25]
        all_pat_gray.extend(gray)
        all_gld_dp.extend(dp)

        # path_length: pattern=dp[25], golden=dl[25]
        all_pat_dp.extend(dp)
        all_gld_dl.extend(dl)

        # rlimit: pattern=dl[25], golden=rlimit(1) + dl[25] (pass-through)
        all_pat_rl_dl.extend(dl)
        all_gld_rlimit.append(rlimit)
        all_gld_rl_dl.extend(dl)

        # ase_masked_min: pattern=rlimit(1)+dl[25]+mc[25], golden=adc(1)
        all_pat_ase_rlimit.append(rlimit)
        all_pat_ase_dl.extend(dl)
        all_pat_ase_mc.extend(mc)
        all_gld_ase_adc.append(adc)

        report_lines.append(
            f"  case {case_id:2d} ({name:24s}): "
            f"rlimit={rlimit:3d}, adc=0x{adc:02X} ({adc:3d})"
        )

    # ----------------------------------------------------------------
    # Write hex files
    # ----------------------------------------------------------------
    # 1) pixel_distance
    write_hex(pdir / "pattern_pixel_distance.hex", all_pat_gray, 8)
    write_hex(gdir / "golden_pixel_distance.hex",  all_gld_dp,   16)

    # 2) path_length
    write_hex(pdir / "pattern_path_length.hex", all_pat_dp, 16)
    write_hex(gdir / "golden_path_length.hex",  all_gld_dl, 16)

    # 3) rlimit
    write_hex(pdir / "pattern_rlimit.hex",        all_pat_rl_dl,  16)
    write_hex(gdir / "golden_rlimit.hex",          all_gld_rlimit, 16)
    write_hex(gdir / "golden_rlimit_dl.hex",       all_gld_rl_dl,  16)

    # 4) ase_masked_min
    write_hex(pdir / "pattern_ase_rlimit.hex", all_pat_ase_rlimit, 16)
    write_hex(pdir / "pattern_ase_dl.hex",     all_pat_ase_dl,     16)
    write_hex(pdir / "pattern_ase_mc.hex",     all_pat_ase_mc,      8)
    write_hex(gdir / "golden_ase_adc.hex",     all_gld_ase_adc,     8)

    # ----------------------------------------------------------------
    # Summary
    # ----------------------------------------------------------------
    print(f"[OK] Generated $readmemh hex files for {NUM_PATTERNS} test cases")
    print(f"  pattern_dir = {pdir}")
    print(f"  golden_dir  = {gdir}")
    print(f"  LAMBDA_Q8   = {lam}")
    print()
    for l in report_lines:
        print(l)


if __name__ == "__main__":
    main()
