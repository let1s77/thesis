#!/usr/bin/env python3
"""Export per-case phase HEX dumps to viewable BMP images.

Input folder default:
    01_sim/IPU/Testbench_HAZE_REMOVAL_TOP/sim/output
Output folder default:
    01_sim/IPU/Testbench_HAZE_REMOVAL_TOP/sim/image
"""

from __future__ import annotations

import argparse
import math
from pathlib import Path
from typing import List, Sequence, Tuple

DEFAULT_FRAME_W = 128
DEFAULT_FRAME_H = 128
NUM_CASES = 20


def read_hex_lines(file_path: Path) -> List[int]:
    if not file_path.exists():
        return []
    vals: List[int] = []
    for line in file_path.read_text().splitlines():
        s = line.strip()
        if not s:
            continue
        vals.append(int(s, 16))
    return vals


def pick_existing(in_dir: Path, candidates: Sequence[str]) -> Path:
    for name in candidates:
        p = in_dir / name
        if p.exists():
            return p
    return in_dir / candidates[0]


def case_file(in_dir: Path, case_id: int, suffix: str) -> Path:
    # Support all historical dump naming variants:
    # case_00_xxx, case_0_xxx, case_ 0_xxx (space padded by %2d style).
    cands = (
        f"case_{case_id:02d}_{suffix}",
        f"case_{case_id}_{suffix}",
        f"case_{case_id:2d}_{suffix}",
    )
    return pick_existing(in_dir, cands)


def infer_dims(pixel_count: int, width: int, height: int) -> Tuple[int, int]:
    if width > 0 and height > 0:
        if width * height > pixel_count:
            raise ValueError(
                f"Requested size {width}x{height} exceeds pixel count {pixel_count}"
            )
        return width, height

    if pixel_count == DEFAULT_FRAME_W * DEFAULT_FRAME_H:
        return DEFAULT_FRAME_W, DEFAULT_FRAME_H

    side = int(math.isqrt(pixel_count))
    if side * side == pixel_count:
        return side, side

    raise ValueError(
        f"Cannot infer dimensions from pixel count {pixel_count}. "
        "Use --width and --height."
    )


def rgb24_to_tuples(pixels: Sequence[int], count: int) -> List[Tuple[int, int, int]]:
    out: List[Tuple[int, int, int]] = []
    for rgb in pixels[:count]:
        r = (rgb >> 16) & 0xFF
        g = (rgb >> 8) & 0xFF
        b = rgb & 0xFF
        out.append((r, g, b))
    return out


def gray_to_tuples(pixels: Sequence[int], count: int) -> List[Tuple[int, int, int]]:
    out: List[Tuple[int, int, int]] = []
    for g in pixels[:count]:
        v = g & 0xFF
        out.append((v, v, v))
    return out


def write_bmp_rgb24(
    file_path: Path, rgb_pixels: Sequence[Tuple[int, int, int]], w: int, h: int
) -> None:
    total = w * h
    if len(rgb_pixels) < total:
        raise ValueError(f"Not enough pixels for {file_path.name}: {len(rgb_pixels)}")

    row_bytes = w * 3
    pad = (4 - (row_bytes % 4)) % 4
    stride = row_bytes + pad
    img_size = stride * h
    file_size = 14 + 40 + img_size

    with file_path.open("wb") as f:
        # BMP file header (14 bytes)
        f.write(b"BM")
        f.write(file_size.to_bytes(4, "little"))
        f.write((0).to_bytes(2, "little"))
        f.write((0).to_bytes(2, "little"))
        f.write((14 + 40).to_bytes(4, "little"))

        # DIB header BITMAPINFOHEADER (40 bytes)
        f.write((40).to_bytes(4, "little"))
        f.write(w.to_bytes(4, "little", signed=True))
        f.write(h.to_bytes(4, "little", signed=True))
        f.write((1).to_bytes(2, "little"))   # planes
        f.write((24).to_bytes(2, "little"))  # bpp
        f.write((0).to_bytes(4, "little"))   # compression
        f.write(img_size.to_bytes(4, "little"))
        f.write((2835).to_bytes(4, "little", signed=True))
        f.write((2835).to_bytes(4, "little", signed=True))
        f.write((0).to_bytes(4, "little"))
        f.write((0).to_bytes(4, "little"))

        # Pixel array, bottom-up, BGR order
        pad_bytes = b"\x00" * pad
        for y in range(h - 1, -1, -1):
            row = rgb_pixels[y * w : (y + 1) * w]
            for r, g, b in row:
                f.write(bytes((b & 0xFF, g & 0xFF, r & 0xFF)))
            if pad:
                f.write(pad_bytes)


def export_case(case_id: int, in_dir: Path, out_dir: Path, width: int, height: int) -> None:
    # Inputs from phase-dump TB
    f_src = case_file(in_dir, case_id, "src_rgb.hex")
    f_dark = case_file(in_dir, case_id, "dark_u8.hex")
    f_sky = case_file(in_dir, case_id, "sky_u8.hex")
    f_tx = case_file(in_dir, case_id, "tx_u8.hex")
    f_tx_bank = case_file(in_dir, case_id, "tx_bank_u8.hex")
    f_rec = case_file(in_dir, case_id, "recovery_rgb.hex")

    src = read_hex_lines(f_src)
    dark = read_hex_lines(f_dark)
    sky = read_hex_lines(f_sky)
    tx = read_hex_lines(f_tx)
    tx_bank = read_hex_lines(f_tx_bank)
    rec = read_hex_lines(f_rec)

    # Skip silently if this case does not exist in dump folder.
    if not (src or dark or sky or tx or tx_bank or rec):
        return

    case_out = out_dir / f"case_{case_id:02d}"
    case_out.mkdir(parents=True, exist_ok=True)

    counts = [len(v) for v in (src, dark, sky, tx, tx_bank, rec) if v]
    px_count = max(counts) if counts else 0
    if px_count == 0:
        return
    w, h = infer_dims(px_count, width, height)
    total = w * h

    if len(src) >= total:
        write_bmp_rgb24(case_out / "01_src.bmp", rgb24_to_tuples(src, total), w, h)
    if len(dark) >= total:
        write_bmp_rgb24(case_out / "02_dark.bmp", gray_to_tuples(dark, total), w, h)
    if len(sky) >= total:
        write_bmp_rgb24(case_out / "03_sky.bmp", gray_to_tuples(sky, total), w, h)
    if len(tx) >= total:
        write_bmp_rgb24(case_out / "04_tx_core.bmp", gray_to_tuples(tx, total), w, h)
    if len(tx_bank) >= total:
        write_bmp_rgb24(
            case_out / "05_tx_bank_read.bmp",
            gray_to_tuples(tx_bank, total),
            w,
            h,
        )
    if len(rec) >= total:
        write_bmp_rgb24(case_out / "06_recovery.bmp", rgb24_to_tuples(rec, total), w, h)


def main() -> None:
    parser = argparse.ArgumentParser(description="Export HAZE_REMOVAL_TOP phase dumps to BMP images")
    parser.add_argument(
        "--input",
        type=Path,
        default=Path("01_sim/IPU/Testbench_HAZE_REMOVAL_TOP/sim/output"),
        help="Folder containing phase dump hex files",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("01_sim/IPU/Testbench_HAZE_REMOVAL_TOP/sim/image"),
        help="Folder to write BMP images",
    )
    parser.add_argument("--cases", type=int, default=NUM_CASES, help="Number of cases to export")
    parser.add_argument(
        "--width",
        type=int,
        default=0,
        help="Image width override (0 means auto-detect)",
    )
    parser.add_argument(
        "--height",
        type=int,
        default=0,
        help="Image height override (0 means auto-detect)",
    )
    args = parser.parse_args()

    args.output.mkdir(parents=True, exist_ok=True)

    for case_id in range(args.cases):
        export_case(case_id, args.input, args.output, args.width, args.height)

    print(f"Done. Images exported to: {args.output}")


if __name__ == "__main__":
    main()
