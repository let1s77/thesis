#!/usr/bin/env python3
import argparse
import csv
from pathlib import Path
from typing import Dict, List, Tuple

# ============================================================================
# ADC Estimation reference model
# ----------------------------------------------------------------------------
# Output:
#   09_pattern/adc_case_XX_gray.hex
#   09_pattern/adc_case_XX_mc.hex
#   07_golden_output/adc_case_XX_golden.txt
#   09_pattern/adc_summary.csv
#
# Window size fixed: 5x5 (r = 2)
# Center pixel: (2,2)
#
# Flow:
#   gray(5x5) -> pixel_distance -> path_length -> rlimit -> ASE mask
#   mc(5x5)   -> adaptive min filter using ASE -> ADC
# ============================================================================

CENTER = (2, 2)
ALL_COORDS = [(r, c) for r in range(5) for c in range(5)]


def idx(rc: Tuple[int, int]) -> int:
    return rc[0] * 5 + rc[1]


# ----------------------------------------------------------------------------
# Fixed path generator
# Hardware-friendly simplification:
#   move diagonally first, then vertical, then horizontal
# ----------------------------------------------------------------------------
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


# ----------------------------------------------------------------------------
# Sub-block 1: pixel distance
# dp = |gray(a) - gray(b)| for every edge in the path
# ----------------------------------------------------------------------------
def pixel_distance_calc(
    gray5x5: List[int],
    paths: Dict[Tuple[int, int], List[Tuple[int, int]]]
) -> Dict[Tuple[int, int], List[int]]:
    out = {}
    for target, path in paths.items():
        dps = []
        for a, b in zip(path[:-1], path[1:]):
            va = gray5x5[idx(a)]
            vb = gray5x5[idx(b)]
            dps.append(abs(va - vb))
        out[target] = dps
    return out


# ----------------------------------------------------------------------------
# Sub-block 2: path length
# L(path) = sum(D8 + lambda * dp)
# D8 = 1 for HV step, 2 for diagonal step
# ----------------------------------------------------------------------------
def path_length_calc(
    dp_dict: Dict[Tuple[int, int], List[int]],
    lambd: float
):
    lengths = {}
    meta = {}

    for target, dps in dp_dict.items():
        path = PATHS[target]
        terms = []
        total = 0.0

        for (a, b), dp in zip(zip(path[:-1], path[1:]), dps):
            dr = abs(a[0] - b[0])
            dc = abs(a[1] - b[1])
            d8 = 2 if (dr == 1 and dc == 1) else 1
            term = d8 + lambd * dp
            terms.append((d8, dp, term))
            total += term

        lengths[target] = total
        meta[target] = terms

    return lengths, meta


# ----------------------------------------------------------------------------
# Sub-block 3: rlimit
# rlimit = mean(all adaptive distances in Omega_k, including center=0)
# M = 25
# ----------------------------------------------------------------------------
def rlimit_calc(lengths: Dict[Tuple[int, int], float]) -> float:
    total = 0.0
    for rc in ALL_COORDS:
        if rc == CENTER:
            continue
        total += lengths[rc]
    return total / 25.0


# ----------------------------------------------------------------------------
# Sub-block 4: ASE mask generation
# ASE(y)=1 if d_lambda(center,y) <= rlimit
# center is always included
# ----------------------------------------------------------------------------
def ase_mask_gen(
    lengths: Dict[Tuple[int, int], float],
    rlimit: float
) -> List[int]:
    mask = []
    for rc in ALL_COORDS:
        if rc == CENTER:
            mask.append(1)
        else:
            mask.append(1 if lengths[rc] <= rlimit else 0)
    return mask


# ----------------------------------------------------------------------------
# Sub-block 5: adaptive min filter
# ADC = min( MC(y) for y in ASE )
# ----------------------------------------------------------------------------
def adaptive_min_filter(mc5x5: List[int], ase_mask: List[int]) -> int:
    vals = [mc for mc, m in zip(mc5x5, ase_mask) if m == 1]
    return min(vals)


# ----------------------------------------------------------------------------
# Top reference model
# ----------------------------------------------------------------------------
def adc_estimation_top(gray5x5: List[int], mc5x5: List[int], lambd: float = 0.2):
    dp_dict = pixel_distance_calc(gray5x5, PATHS)
    lengths, meta = path_length_calc(dp_dict, lambd)
    rlimit = rlimit_calc(lengths)
    ase_mask = ase_mask_gen(lengths, rlimit)
    adc = adaptive_min_filter(mc5x5, ase_mask)

    return {
        "pixel_distances": dp_dict,
        "path_lengths": lengths,
        "path_meta": meta,
        "rlimit": rlimit,
        "ase_mask": ase_mask,
        "adc": adc,
    }


# ============================================================================
# 20 testcases
# Each testcase:
#   gray 5x5
#   mc   5x5
# ============================================================================
def make_case_from_rows(name: str, gray_rows: List[List[int]], mc_rows: List[List[int]]):
    gray = [v for row in gray_rows for v in row]
    mc = [v for row in mc_rows for v in row]
    return (name, gray, mc)


TESTCASES = [
    make_case_from_rows("flat_uniform", [[100]*5 for _ in range(5)], [[50]*5 for _ in range(5)]),
    make_case_from_rows("center_dark_flat", [[120]*5 for _ in range(5)],
                        [[80,80,80,80,80],[80,80,80,80,80],[80,80,10,80,80],[80,80,80,80,80],[80,80,80,80,80]]),
    make_case_from_rows("horizontal_edge", [[40]*5,[40]*5,[40]*5,[200]*5,[200]*5],
                        [[90,88,86,84,82],[90,88,86,84,82],[90,88,86,84,82],[40,38,36,34,32],[40,38,36,34,32]]),
    make_case_from_rows("vertical_edge", [[30,30,120,220,220]]*5,
                        [[100,95,70,50,45]]*5),
    make_case_from_rows("diag_edge_main",
                        [[20,20,20,20,20],[20,20,20,20,200],[20,20,20,200,200],[20,20,200,200,200],[20,200,200,200,200]],
                        [[99,98,97,96,95],[98,90,89,88,20],[97,89,80,22,21],[96,88,24,23,22],[95,26,25,24,23]]),
    make_case_from_rows("diag_edge_anti",
                        [[200,200,200,200,20],[200,200,200,20,20],[200,200,20,20,20],[200,20,20,20,20],[20,20,20,20,20]],
                        [[10,11,12,13,80],[11,12,13,81,82],[12,13,83,84,85],[13,86,87,88,89],[90,91,92,93,94]]),
    make_case_from_rows("cross_structure",
                        [[100,100,180,100,100],[100,100,180,100,100],[180,180,180,180,180],[100,100,180,100,100],[100,100,180,100,100]],
                        [[70,70,20,70,70],[70,70,20,70,70],[20,20,10,20,20],[70,70,20,70,70],[70,70,20,70,70]]),
    make_case_from_rows("center_bright_island",
                        [[50,50,50,50,50],[50,90,90,90,50],[50,90,200,90,50],[50,90,90,90,50],[50,50,50,50,50]],
                        [[80,79,78,77,76],[79,60,59,58,75],[78,59,20,57,74],[77,58,57,56,73],[76,75,74,73,72]]),
    make_case_from_rows("noisy_small_variation",
                        [[100,102,99,101,98],[101,100,103,98,99],[99,101,100,102,100],[98,99,101,100,103],[100,98,99,101,100]],
                        [[55,53,57,54,56],[54,52,58,55,53],[56,57,50,54,55],[53,55,56,52,54],[55,54,53,56,51]]),
    make_case_from_rows("ramp_horizontal",
                        [[10,40,70,100,130]]*5,
                        [[120,110,100,90,80],[119,109,99,89,79],[118,108,20,88,78],[117,107,97,87,77],[116,106,96,86,76]]),
    make_case_from_rows("ramp_vertical",
                        [[10]*5,[40]*5,[70]*5,[100]*5,[130]*5],
                        [[120,119,118,117,116],[110,109,108,107,106],[100,99,20,97,96],[90,89,88,87,86],[80,79,78,77,76]]),
    make_case_from_rows("checkerboard_soft",
                        [[80,120,80,120,80],[120,80,120,80,120],[80,120,80,120,80],[120,80,120,80,120],[80,120,80,120,80]],
                        [[60,65,60,65,60],[65,55,65,55,65],[60,65,10,65,60],[65,55,65,55,65],[60,65,60,65,60]]),
    make_case_from_rows("corner_dark_tl",
                        [[30,40,50,60,70],[40,50,60,70,80],[50,60,70,80,90],[60,70,80,90,100],[70,80,90,100,110]],
                        [[5,90,91,92,93],[90,91,92,93,94],[91,92,50,94,95],[92,93,94,95,96],[93,94,95,96,97]]),
    make_case_from_rows("corner_dark_br",
                        [[110,100,90,80,70],[100,90,80,70,60],[90,80,70,60,50],[80,70,60,50,40],[70,60,50,40,30]],
                        [[97,96,95,94,93],[96,95,94,93,92],[95,94,50,92,91],[94,93,92,91,90],[93,92,91,90,5]]),
    make_case_from_rows("ring_structure",
                        [[180,180,180,180,180],[180,60,60,60,180],[180,60,30,60,180],[180,60,60,60,180],[180,180,180,180,180]],
                        [[90,89,88,87,86],[89,40,39,38,85],[88,39,15,37,84],[87,38,37,36,83],[86,85,84,83,82]]),
    make_case_from_rows("left_right_two_regions",
                        [[20,20,20,200,200],[20,20,20,200,200],[20,20,20,200,200],[20,20,20,200,200],[20,20,20,200,200]],
                        [[30,31,32,90,91],[29,28,27,89,88],[26,25,24,87,86],[23,22,21,85,84],[20,19,18,83,82]]),
    make_case_from_rows("top_bottom_two_regions",
                        [[20]*5,[20]*5,[100]*5,[200]*5,[200]*5],
                        [[70,69,68,67,66],[65,64,63,62,61],[60,59,10,58,57],[56,55,54,53,52],[51,50,49,48,47]]),
    make_case_from_rows("center_valley",
                        [[150,150,150,150,150],[150,100,100,100,150],[150,100,20,100,150],[150,100,100,100,150],[150,150,150,150,150]],
                        [[90,88,86,84,82],[88,40,39,38,80],[86,39,5,37,78],[84,38,37,36,76],[82,80,78,76,74]]),
    make_case_from_rows("random_like_1",
                        [[73,91,88,45,20],[65,77,82,49,25],[61,80,95,52,27],[58,75,83,50,29],[55,70,79,48,30]],
                        [[60,58,56,54,52],[57,55,53,51,49],[54,52,11,48,46],[51,49,47,45,43],[48,46,44,42,40]]),
    make_case_from_rows("random_like_2",
                        [[200,180,160,140,120],[180,170,150,130,110],[160,150,145,125,105],[140,130,120,115,95],[120,110,100,90,80]],
                        [[99,95,91,87,83],[94,90,86,82,78],[89,85,30,77,73],[84,80,76,72,68],[79,75,71,67,63]]),
]


def append_section(buf: list, tag: str, name: str, lines):
    """Append a commented section header + data lines to a buffer."""
    buf.append(f"# ---- [{tag}] {name} ----")
    for line in lines:
        buf.append(str(line))
    buf.append("")  # blank separator


def write_combined(path: Path, buf: list):
    """Write all sections into one combined file."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        for line in buf:
            f.write(line + "\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lambda_val", type=float, default=0.2)
    ap.add_argument("--pattern_dir", type=str, default="09_pattern")
    ap.add_argument("--golden_dir", type=str, default="07_golden_output")
    args = ap.parse_args()

    pattern_dir = Path(args.pattern_dir)
    golden_dir = Path(args.golden_dir)

    summary_rows = []

    # Combined buffers — one file each instead of 20
    buf_gray   = []
    buf_mc     = []
    buf_golden = []

    for case_id, (name, gray, mc) in enumerate(TESTCASES):
        tag = f"adc_case_{case_id:02d}"
        result = adc_estimation_top(gray, mc, lambd=args.lambda_val)

        # --- gray pattern ---
        append_section(buf_gray, tag, name,
                       [f"{v & 0xFF:02X}" for v in gray])

        # --- mc pattern ---
        append_section(buf_mc, tag, name,
                       [f"{v & 0xFF:02X}" for v in mc])

        # --- golden output (all sub-block results) ---
        golden_lines = []
        golden_lines.append(f"# ADC Estimation golden for case: {name}")
        golden_lines.append("# 5x5 row-major window")
        golden_lines.append("")

        golden_lines.append("[PIXEL_DISTANCES]")
        for rc in ALL_COORDS:
            if rc == CENTER:
                continue
            dps = result["pixel_distances"][rc]
            golden_lines.append(
                f"target={rc}: " + ",".join(str(x) for x in dps))

        golden_lines.append("")
        golden_lines.append("[PATH_LENGTHS]")
        for rc in ALL_COORDS:
            if rc == CENTER:
                continue
            golden_lines.append(
                f"target={rc}: {result['path_lengths'][rc]:.4f}")

        golden_lines.append("")
        golden_lines.append(f"[RLIMIT]")
        golden_lines.append(f"{result['rlimit']:.4f}")

        golden_lines.append("")
        golden_lines.append("[ASE_MASK_5x5_ROW_MAJOR]")
        mask = result["ase_mask"]
        for r in range(5):
            row = mask[r*5:(r+1)*5]
            golden_lines.append(" ".join(str(x) for x in row))

        golden_lines.append("")
        golden_lines.append("[ADC]")
        golden_lines.append(f"{result['adc']:02X}")

        append_section(buf_golden, tag, name, golden_lines)

        summary_rows.append({
            "case_id": case_id,
            "name": name,
            "lambda": args.lambda_val,
            "rlimit": f"{result['rlimit']:.4f}",
            "adc_hex": f"{result['adc']:02X}",
            "adc_dec": result['adc'],
        })

    # Write one combined file each
    write_combined(pattern_dir / "adc_all_gray.hex",      buf_gray)
    write_combined(pattern_dir / "adc_all_mc.hex",        buf_mc)
    write_combined(golden_dir  / "adc_all_golden.txt",    buf_golden)

    # Summary CSV
    summary_path = pattern_dir / "adc_summary.csv"
    summary_path.parent.mkdir(parents=True, exist_ok=True)
    with open(summary_path, "w", newline="") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=["case_id", "name", "lambda",
                        "rlimit", "adc_hex", "adc_dec"]
        )
        writer.writeheader()
        writer.writerows(summary_rows)

    print("[OK] Generated ADC estimation vectors "
          "(1 combined file per category)")
    print(f"pattern_dir = {pattern_dir}")
    print(f"golden_dir  = {golden_dir}")
    print(f"summary     = {summary_path}")
    print(f"total_cases = {len(TESTCASES)}")


if __name__ == "__main__":
    main()