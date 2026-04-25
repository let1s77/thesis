#!/usr/bin/env python3
"""Verify input/output image correctness for FPGA haze removal pipeline.

Compares:
  1. Input BMP  vs original source image (bit-exact or PSNR)
  2. Output BMP vs golden reference (SHA256 or PSNR/SSIM)
  3. Visual side-by-side comparison (optional)

Also validates pixel format and shows statistics (min, max, mean per channel).

Usage:
    python verify_image.py --input soc_input_128.bmp --output soc_output_128.bmp
    python verify_image.py --output soc_output_128.bmp --golden-sha 05E53E87...
    python verify_image.py --output soc_output_128.bmp --golden golden.bmp --show
"""

import argparse
import hashlib
import math
import os
import struct
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent

# Golden SHA256 from verified testbench
GOLDEN_SHA256 = "05E53E87A1DC2F47CC6631F2FAF993169D42F7CD4DF6F7895F32928F886EA791"


def sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest().upper()


def load_bmp_rgb(path: str) -> tuple:
    """Load 24-bit BMP, return (width, height, pixels_rgb_list, header_bytes)."""
    with open(path, "rb") as f:
        header = f.read(54)
        if len(header) < 54 or header[:2] != b"BM":
            raise ValueError(f"Not a valid BMP: {path}")

        data_offset = struct.unpack_from("<I", header, 10)[0]
        w = struct.unpack_from("<i", header, 18)[0]
        h = struct.unpack_from("<i", header, 22)[0]
        bpp = struct.unpack_from("<H", header, 28)[0]

        if bpp != 24:
            raise ValueError(f"Only 24-bit BMP supported, got {bpp}")

        f.seek(data_offset)
        row_size = ((w * 3 + 3) // 4) * 4
        bottom_up = h > 0
        abs_h = abs(h)

        rows = []
        for _ in range(abs_h):
            rows.append(f.read(row_size))
        if bottom_up:
            rows.reverse()

    pixels = []
    for row in rows:
        for c in range(w):
            b = row[c * 3]
            g = row[c * 3 + 1]
            r = row[c * 3 + 2]
            pixels.append((r, g, b))

    return w, h, pixels, header


def channel_stats(pixels: list, ch: int, name: str) -> dict:
    vals = [p[ch] for p in pixels]
    return {
        "name": name,
        "min": min(vals),
        "max": max(vals),
        "mean": sum(vals) / len(vals),
    }


def print_image_info(label: str, path: str, w: int, h: int, pixels: list):
    print(f"\n--- {label}: {path} ---")
    print(f"  Size : {w} x {abs(h)}  ({len(pixels)} pixels)")
    for ch, name in enumerate(["Red", "Green", "Blue"]):
        s = channel_stats(pixels, ch, name)
        print(f"  {name:5s}: min={s['min']:3d}  max={s['max']:3d}  mean={s['mean']:.1f}")


def compute_psnr(pixels_a: list, pixels_b: list) -> float:
    """Compute PSNR between two pixel lists [(R,G,B), ...]."""
    if len(pixels_a) != len(pixels_b):
        return 0.0
    mse = 0.0
    n = len(pixels_a) * 3
    for a, b in zip(pixels_a, pixels_b):
        for i in range(3):
            d = float(a[i]) - float(b[i])
            mse += d * d
    mse /= n
    if mse == 0:
        return float("inf")
    return 10.0 * math.log10(255.0 * 255.0 / mse)


def compute_max_diff(pixels_a: list, pixels_b: list) -> int:
    """Max absolute difference across all channels."""
    max_d = 0
    for a, b in zip(pixels_a, pixels_b):
        for i in range(3):
            d = abs(a[i] - b[i])
            if d > max_d:
                max_d = d
    return max_d


def make_side_by_side(path_in: str | None, path_out: str, save_path: str):
    """Create side-by-side comparison image (requires Pillow)."""
    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError:
        print("  (Pillow not installed — skipping visual comparison)")
        return

    imgs = []
    labels = []

    if path_in and os.path.isfile(path_in):
        imgs.append(Image.open(path_in).convert("RGB"))
        labels.append("INPUT")

    if os.path.isfile(path_out):
        imgs.append(Image.open(path_out).convert("RGB"))
        labels.append("OUTPUT")

    if not imgs:
        return

    # Scale up small images for visibility
    scale = 3 if imgs[0].width <= 128 else 1
    gap = 20
    label_h = 30

    scaled = []
    for img in imgs:
        scaled.append(img.resize(
            (img.width * scale, img.height * scale), Image.NEAREST
        ))

    total_w = sum(s.width for s in scaled) + gap * (len(scaled) - 1)
    total_h = max(s.height for s in scaled) + label_h

    canvas = Image.new("RGB", (total_w, total_h), (40, 40, 40))
    draw = ImageDraw.Draw(canvas)

    x = 0
    for s, label in zip(scaled, labels):
        canvas.paste(s, (x, label_h))
        tw = draw.textlength(label)
        tx = x + (s.width - tw) // 2
        draw.text((tx, 5), label, fill=(255, 255, 255))
        x += s.width + gap

    canvas.save(save_path)
    print(f"  Side-by-side saved: {save_path}")


def main():
    parser = argparse.ArgumentParser(
        description="Verify FPGA haze removal input/output images."
    )
    parser.add_argument("--input", default=None, help="Input BMP from SOC testbench")
    parser.add_argument("--output", required=True, help="Output BMP from SOC testbench")
    parser.add_argument("--golden", default=None, help="Golden reference BMP for comparison")
    parser.add_argument(
        "--golden-sha", default=GOLDEN_SHA256,
        help=f"Expected SHA256 of output BMP (default: {GOLDEN_SHA256[:16]}...)"
    )
    parser.add_argument("--show", action="store_true", help="Generate side-by-side comparison PNG")
    parser.add_argument("--psnr-min", type=float, default=30.0, help="Minimum acceptable PSNR (dB)")
    args = parser.parse_args()

    all_pass = True

    # ---------------------------------------------------------------
    # 1. Input image analysis
    # ---------------------------------------------------------------
    if args.input and os.path.isfile(args.input):
        w, h, pix_in, _ = load_bmp_rgb(args.input)
        print_image_info("INPUT", args.input, w, h, pix_in)

        # Sanity: check not all black
        total = sum(sum(p) for p in pix_in)
        if total == 0:
            print("  WARNING: Input image is all black!")
            all_pass = False
        else:
            print("  [OK] Input image has non-zero pixel data")

    # ---------------------------------------------------------------
    # 2. Output image analysis
    # ---------------------------------------------------------------
    if not os.path.isfile(args.output):
        print(f"\nERROR: Output file not found: {args.output}")
        sys.exit(1)

    w, h, pix_out, _ = load_bmp_rgb(args.output)
    print_image_info("OUTPUT", args.output, w, h, pix_out)

    # Check not all black
    total = sum(sum(p) for p in pix_out)
    if total == 0:
        print("  WARNING: Output image is all black!")
        all_pass = False
    else:
        print("  [OK] Output image has non-zero pixel data")

    # ---------------------------------------------------------------
    # 3. SHA256 verification
    # ---------------------------------------------------------------
    output_sha = sha256_file(args.output)
    print(f"\n  SHA256: {output_sha}")
    if args.golden_sha:
        expected = args.golden_sha.upper()
        if output_sha == expected:
            print(f"  [OK] SHA256 MATCH — bit-identical to golden")
        else:
            print(f"  [FAIL] SHA256 MISMATCH")
            print(f"    Expected: {expected}")
            print(f"    Got:      {output_sha}")
            all_pass = False

    # ---------------------------------------------------------------
    # 4. Golden BMP comparison (if provided)
    # ---------------------------------------------------------------
    if args.golden and os.path.isfile(args.golden):
        w_g, h_g, pix_gold, _ = load_bmp_rgb(args.golden)
        print_image_info("GOLDEN", args.golden, w_g, h_g, pix_gold)

        if len(pix_out) == len(pix_gold):
            psnr = compute_psnr(pix_out, pix_gold)
            max_diff = compute_max_diff(pix_out, pix_gold)
            print(f"\n  PSNR vs golden : {psnr:.2f} dB")
            print(f"  Max pixel diff : {max_diff}")

            if psnr == float("inf"):
                print("  [OK] Bit-exact match with golden BMP")
            elif psnr >= args.psnr_min:
                print(f"  [OK] PSNR >= {args.psnr_min} dB threshold")
            else:
                print(f"  [FAIL] PSNR < {args.psnr_min} dB threshold")
                all_pass = False
        else:
            print(f"  [FAIL] Pixel count mismatch: output={len(pix_out)}, golden={len(pix_gold)}")
            all_pass = False

    # ---------------------------------------------------------------
    # 5. Input vs Output comparison
    # ---------------------------------------------------------------
    if args.input and os.path.isfile(args.input):
        if len(pix_in) == len(pix_out):
            psnr_io = compute_psnr(pix_in, pix_out)
            max_diff_io = compute_max_diff(pix_in, pix_out)
            print(f"\n  Input→Output PSNR     : {psnr_io:.2f} dB")
            print(f"  Input→Output max diff : {max_diff_io}")
            if psnr_io == float("inf"):
                print("  NOTE: Output = Input (no processing happened?)")
            elif max_diff_io > 0:
                print("  [OK] Output differs from input (processing occurred)")

    # ---------------------------------------------------------------
    # 6. Visual comparison
    # ---------------------------------------------------------------
    if args.show:
        save_path = os.path.splitext(args.output)[0] + "_comparison.png"
        make_side_by_side(args.input, args.output, save_path)

    # ---------------------------------------------------------------
    # Summary
    # ---------------------------------------------------------------
    print()
    print("=" * 50)
    if all_pass:
        print("  RESULT: ALL CHECKS PASSED")
    else:
        print("  RESULT: SOME CHECKS FAILED")
    print("=" * 50)

    sys.exit(0 if all_pass else 1)


if __name__ == "__main__":
    main()
