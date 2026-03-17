#!/usr/bin/env python3
"""Rebuild/visualize 128x128 haze maps from TB BMP outputs.

Why this script:
- `haze_adc_128.bmp` stores only valid ADC stream samples first, then zeros.
- Visual result can look wrong/blank without data relayout + contrast stretch.

This tool:
1) reads 24-bit BMP grayscale maps,
2) rebuilds full 128x128 ADC map from compact valid stream,
3) applies border interpolation,
4) writes rebuilt BMPs and visualization-stretched BMPs.
"""

from __future__ import annotations

import argparse
import struct
from pathlib import Path
from typing import List, Sequence, Tuple

W = 128
H = 128
N = W * H


def read_bmp_gray(path: Path) -> Tuple[List[int], bytes]:
    data = path.read_bytes()
    if data[0:2] != b"BM":
        raise ValueError(f"Not a BMP file: {path}")

    off = struct.unpack_from("<I", data, 10)[0]
    dib_size = struct.unpack_from("<I", data, 14)[0]
    if dib_size < 40:
        raise ValueError(f"Unsupported BMP DIB size: {dib_size}")

    w = struct.unpack_from("<i", data, 18)[0]
    h = struct.unpack_from("<i", data, 22)[0]
    bpp = struct.unpack_from("<H", data, 28)[0]
    if bpp != 24:
        raise ValueError(f"Only 24bpp BMP supported, got {bpp} at {path}")
    if abs(w) != W or abs(h) != H:
        raise ValueError(f"Expected {W}x{H}, got {w}x{h} for {path}")

    row_stride = ((abs(w) * 3 + 3) // 4) * 4
    px = data[off : off + row_stride * abs(h)]

    out = [0] * (abs(w) * abs(h))
    for row in range(abs(h)):
        for col in range(abs(w)):
            b = px[row * row_stride + col * 3 + 0]
            out[row * abs(w) + col] = b

    return out, data[:off]


def write_bmp_gray(path: Path, values: Sequence[int], header_prefix: bytes) -> None:
    if len(values) != N:
        raise ValueError(f"Expected {N} values, got {len(values)} for {path}")

    row_stride = ((W * 3 + 3) // 4) * 4
    pad = row_stride - W * 3
    px = bytearray()
    for row in range(H):
        base = row * W
        for col in range(W):
            v = max(0, min(255, int(values[base + col])))
            px.extend((v, v, v))
        if pad:
            px.extend(b"\x00" * pad)

    path.write_bytes(header_prefix + px)


def relayout_adc_stream(stream_map: Sequence[int], valid_count: int) -> List[int]:
    valid = max(1, min(valid_count, N))
    stream = list(stream_map[:valid])

    miss = N - valid
    head = miss // 2
    # tail is implicit from clamping

    full = [0] * N
    for k in range(N):
        src = k - head
        if src < 0:
            full[k] = stream[0]
        elif src >= valid:
            full[k] = stream[-1]
        else:
            full[k] = stream[src]

    # Border interpolation/replication on 2D grid.
    for r in range(H):
        full[r * W + 0] = full[r * W + 1]
        full[r * W + (W - 1)] = full[r * W + (W - 2)]
    for c in range(W):
        full[c] = full[W + c]
        full[(H - 1) * W + c] = full[(H - 2) * W + c]

    return full


def stretch_u8(vals: Sequence[int], lo_pct: float = 1.0, hi_pct: float = 99.0) -> List[int]:
    arr = sorted(int(v) for v in vals)
    n = len(arr)
    lo_i = max(0, min(n - 1, int((lo_pct / 100.0) * (n - 1))))
    hi_i = max(0, min(n - 1, int((hi_pct / 100.0) * (n - 1))))
    lo = arr[lo_i]
    hi = arr[hi_i]
    if hi <= lo:
        return [int(v) for v in vals]

    out = []
    scale = 255.0 / float(hi - lo)
    for v in vals:
        x = int(round((int(v) - lo) * scale))
        if x < 0:
            x = 0
        elif x > 255:
            x = 255
        out.append(x)
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description="Rebuild and visualize haze ADC maps at 128x128")
    ap.add_argument(
        "--image-dir",
        type=Path,
        default=Path("01_sim/IPU/Testbench_HAZE_REMOVAL_TOP/sim/image"),
        help="Directory containing haze_*_128.bmp outputs",
    )
    ap.add_argument(
        "--valid-adc-count",
        type=int,
        default=15869,
        help="Valid sample count in haze_adc_128.bmp stream",
    )
    args = ap.parse_args()

    img_dir = args.image_dir
    adc_bmp = img_dir / "haze_adc_128.bmp"
    adc_used_bmp = img_dir / "haze_adc_used_128.bmp"

    adc_vals, hdr = read_bmp_gray(adc_bmp)
    adc_used_vals, hdr2 = read_bmp_gray(adc_used_bmp)

    adc_relayout = relayout_adc_stream(adc_vals, args.valid_adc_count)
    adc_relayout_vis = stretch_u8(adc_relayout, 1.0, 99.0)
    adc_used_vis = stretch_u8(adc_used_vals, 1.0, 99.0)

    write_bmp_gray(img_dir / "haze_adc_relayout_128.bmp", adc_relayout, hdr)
    write_bmp_gray(img_dir / "haze_adc_relayout_vis_128.bmp", adc_relayout_vis, hdr)
    write_bmp_gray(img_dir / "haze_adc_used_vis_128.bmp", adc_used_vis, hdr2)

    print("Done.")
    print(f"  Source      : {adc_bmp}")
    print(f"  Source used : {adc_used_bmp}")
    print(f"  Output      : {img_dir / 'haze_adc_relayout_128.bmp'}")
    print(f"  Output vis  : {img_dir / 'haze_adc_relayout_vis_128.bmp'}")
    print(f"  Output vis2 : {img_dir / 'haze_adc_used_vis_128.bmp'}")


if __name__ == "__main__":
    main()
