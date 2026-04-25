#!/usr/bin/env python3
"""Convert a BMP/PNG image to $readmemh hex files for FPGA BRAM initialization.

Generates hex files for img_in_bram (and optionally img_out_bram).
Each line = one 32-bit word: 00BBGGRR (pad=0, B[7:0], G[7:0], R[7:0]).

The hex file can be loaded by instr_mem-style $readmemh or by Quartus MIF.

Usage:
    python gen_image_hex.py input.bmp
    python gen_image_hex.py input.png -o img_in.hex
    python gen_image_hex.py input.bmp --width 128 --height 128 --mif
"""

import argparse
import os
import struct
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent


def load_bmp_pixels(path: str, width: int, height: int) -> list[int]:
    """Load 24-bit BMP and return list of 32-bit words {00, B, G, R}."""
    with open(path, "rb") as f:
        header = f.read(54)
        if len(header) < 54 or header[0:2] != b"BM":
            raise ValueError(f"Not a valid BMP file: {path}")

        data_offset = struct.unpack_from("<I", header, 10)[0]
        bmp_w = struct.unpack_from("<i", header, 18)[0]
        bmp_h = struct.unpack_from("<i", header, 22)[0]
        bpp = struct.unpack_from("<H", header, 28)[0]

        if bpp != 24:
            raise ValueError(f"Only 24-bit BMP supported, got {bpp}-bit")

        if bmp_w != width or abs(bmp_h) != height:
            print(f"WARNING: BMP is {bmp_w}x{abs(bmp_h)}, expected {width}x{height}")

        f.seek(data_offset)
        row_size = ((bmp_w * 3 + 3) // 4) * 4  # BMP rows are 4-byte aligned
        bottom_up = bmp_h > 0

        rows = []
        for _ in range(abs(bmp_h)):
            row_data = f.read(row_size)
            rows.append(row_data)

        if bottom_up:
            rows.reverse()

    pixels = []
    for row_data in rows[:height]:
        for col in range(min(bmp_w, width)):
            b = row_data[col * 3]
            g = row_data[col * 3 + 1]
            r = row_data[col * 3 + 2]
            word = (b << 16) | (g << 8) | r  # {00, B, G, R}
            pixels.append(word)
        # pad if bmp_w < width
        for _ in range(max(0, width - bmp_w)):
            pixels.append(0)

    # pad if bmp_h < height
    while len(pixels) < width * height:
        pixels.append(0)

    return pixels[:width * height]


def load_png_pixels(path: str, width: int, height: int) -> list[int]:
    """Load PNG/JPEG via PIL and return list of 32-bit words {00, B, G, R}."""
    try:
        from PIL import Image
    except ImportError:
        print("ERROR: Pillow required for PNG/JPEG. Install: pip install Pillow")
        sys.exit(1)

    img = Image.open(path).convert("RGB")
    if img.width != width or img.height != height:
        print(f"WARNING: Image is {img.width}x{img.height}, resizing to {width}x{height}")
        img = img.resize((width, height), Image.LANCZOS)

    pixels = []
    for y in range(height):
        for x in range(width):
            r, g, b = img.getpixel((x, y))
            word = (b << 16) | (g << 8) | r  # {00, B, G, R}
            pixels.append(word)
    return pixels


def load_image(path: str, width: int, height: int) -> list[int]:
    ext = os.path.splitext(path)[1].lower()
    if ext == ".bmp":
        return load_bmp_pixels(path, width, height)
    else:
        return load_png_pixels(path, width, height)


def write_hex(pixels: list[int], out_path: str) -> None:
    """Write $readmemh-compatible hex file. One 32-bit word per line."""
    with open(out_path, "w") as f:
        for word in pixels:
            f.write(f"{word:08X}\n")
    print(f"  HEX: {out_path}  ({len(pixels)} words)")


def write_mif(pixels: list[int], out_path: str, data_width: int = 32) -> None:
    """Write Quartus MIF (Memory Initialization File)."""
    depth = len(pixels)
    with open(out_path, "w") as f:
        f.write(f"DEPTH = {depth};\n")
        f.write(f"WIDTH = {data_width};\n")
        f.write("ADDRESS_RADIX = HEX;\n")
        f.write("DATA_RADIX = HEX;\n")
        f.write("CONTENT\nBEGIN\n")
        for addr, word in enumerate(pixels):
            f.write(f"  {addr:04X} : {word:08X};\n")
        f.write("END;\n")
    print(f"  MIF: {out_path}  ({depth} words)")


def main():
    parser = argparse.ArgumentParser(
        description="Convert image to FPGA BRAM hex/MIF for $readmemh initialization."
    )
    parser.add_argument("input", help="Input image (BMP 24-bit, PNG, JPEG)")
    parser.add_argument("-o", "--output", default=None, help="Output hex file path")
    parser.add_argument("--width", type=int, default=128, help="Image width (default 128)")
    parser.add_argument("--height", type=int, default=128, help="Image height (default 128)")
    parser.add_argument("--mif", action="store_true", help="Also generate Quartus MIF file")
    parser.add_argument(
        "--out-dir", default=None,
        help="Output directory (default: same as input)"
    )
    args = parser.parse_args()

    input_path = os.path.abspath(args.input)
    if not os.path.isfile(input_path):
        print(f"ERROR: File not found: {input_path}")
        sys.exit(1)

    pixels = load_image(input_path, args.width, args.height)
    print(f"Loaded: {input_path}  ({args.width}x{args.height} = {len(pixels)} pixels)")
    print(f"  Pixel format: 32-bit {{00, B[7:0], G[7:0], R[7:0]}}")

    # Determine output path
    if args.output:
        hex_path = os.path.abspath(args.output)
    else:
        base = os.path.splitext(os.path.basename(input_path))[0]
        out_dir = args.out_dir or os.path.dirname(input_path)
        hex_path = os.path.join(out_dir, f"{base}.hex")

    write_hex(pixels, hex_path)

    if args.mif:
        mif_path = os.path.splitext(hex_path)[0] + ".mif"
        write_mif(pixels, mif_path)

    print("Done.")


if __name__ == "__main__":
    main()
