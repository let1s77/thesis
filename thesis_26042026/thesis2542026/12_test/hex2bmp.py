#!/usr/bin/env python3
"""
hex2bmp.py  —  BRAM hex → BMP viewer / converter
==================================================
Chuyển đổi BRAM hex file (định dạng $readmemh, 00BBGGRR mỗi dòng)
thành file BMP để xem ảnh trực quan.

Có thể dùng để xem:
  • soc_input_128.hex   → ảnh input hazy (trước dehaze)
  • soc_dehazed_128.hex → ảnh SW-dehazed (calib từ golden)
  • sim_output.hex      → output từ simulation ModelSim
  • signaltap_dump.hex  → dump từ SignalTap JTAG (xem bên dưới)

Cách lấy ảnh từ FPGA:
  ┌─────────────────────────────────────────────────────────┐
  │  Đường 1 (đơn giản): Hex file đã có sẵn                 │
  │    python hex2bmp.py ../06_FGPA_Imple/images/soc_dehazed_128.hex │
  │                                                          │
  │  Đường 2 (simulation): ModelSim dump img_out_bram       │
  │    → testbench đã có, output là soc_output_128.bmp      │
  │                                                          │
  │  Đường 3 (FPGA hardware): SignalTap JTAG                 │
  │    → Xem hướng dẫn --help-jtag                          │
  └─────────────────────────────────────────────────────────┘

Cách dùng:
  python hex2bmp.py input.hex
  python hex2bmp.py input.hex -o output.bmp
  python hex2bmp.py input.hex --width 128 --height 128
  python hex2bmp.py ../06_FGPA_Imple/images/soc_input_128.hex -o result/input.bmp
  python hex2bmp.py ../06_FGPA_Imple/images/soc_dehazed_128.hex -o result/dehazed.bmp
  python hex2bmp.py --compare ../06_FGPA_Imple/images/soc_input_128.hex ../06_FGPA_Imple/images/soc_dehazed_128.hex
  python hex2bmp.py --help-jtag
"""

import argparse
import math
import os
import struct
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
RESULT_DIR = SCRIPT_DIR / "result"

W_DEFAULT = 128
H_DEFAULT = 128
DEPTH     = W_DEFAULT * H_DEFAULT  # 16384

# ─────────────────────────────────────────────
#  Hex → pixels
# ─────────────────────────────────────────────

def load_hex(path, width=W_DEFAULT, height=H_DEFAULT):
    """Load $readmemh BRAM hex (00BBGGRR per line) → (R, G, B) uint8 arrays."""
    words = []
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("//") or line.startswith("#"):
                continue
            # Strip possible 0x prefix
            line = line.lstrip("0x").lstrip("0X")
            if line:
                words.append(int(line, 16) & 0xFFFFFFFF)

    n = width * height
    R, G, B = [], [], []
    for i in range(n):
        w = words[i] if i < len(words) else 0
        R.append((w >>  0) & 0xFF)   # bits [7:0]
        G.append((w >>  8) & 0xFF)   # bits [15:8]
        B.append((w >> 16) & 0xFF)   # bits [23:16]
        # bits [31:24] = padding/ignored

    return R, G, B, width, height


# ─────────────────────────────────────────────
#  Pixels → BMP (24-bit, bottom-up)
# ─────────────────────────────────────────────

def save_bmp(path, R, G, B, width, height):
    row_stride = ((width * 3 + 3) // 4) * 4
    pad        = row_stride - width * 3
    pixel_data = bytearray()

    # BMP stores rows bottom-up
    for y in range(height - 1, -1, -1):
        for x in range(width):
            idx = y * width + x
            pixel_data += bytes([B[idx], G[idx], R[idx]])
        pixel_data += b'\x00' * pad

    file_size = 54 + len(pixel_data)
    header = struct.pack("<2sIHHI", b"BM", file_size, 0, 0, 54)
    dib    = struct.pack("<IiiHHIIiiII", 40, width, height, 1, 24, 0,
                         len(pixel_data), 2835, 2835, 0, 0)
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "wb") as f:
        f.write(header + dib + pixel_data)


# ─────────────────────────────────────────────
#  Load BMP (để compare)
# ─────────────────────────────────────────────

def load_bmp(path):
    with open(path, "rb") as f:
        raw = f.read()
    if raw[0:2] != b"BM":
        raise ValueError(f"Not a BMP: {path}")
    data_off  = struct.unpack_from("<I", raw, 10)[0]
    bmp_w     = struct.unpack_from("<i", raw, 18)[0]
    bmp_h     = struct.unpack_from("<i", raw, 22)[0]
    bottom_up = bmp_h > 0
    bmp_h     = abs(bmp_h)
    stride    = ((bmp_w * 3 + 3) // 4) * 4
    rows = [raw[data_off + y * stride: data_off + y * stride + bmp_w * 3]
            for y in range(bmp_h)]
    if bottom_up:
        rows = rows[::-1]
    R, G, B = [], [], []
    for row in rows:
        for x in range(bmp_w):
            b = row[x * 3]; g = row[x * 3 + 1]; r = row[x * 3 + 2]
            R.append(r); G.append(g); B.append(b)
    return R, G, B, bmp_w, bmp_h


def psnr(R1, G1, B1, R2, G2, B2):
    n = min(len(R1), len(R2))
    mse = sum((R1[i]-R2[i])**2 + (G1[i]-G2[i])**2 + (B1[i]-B2[i])**2
              for i in range(n)) / (3 * n)
    return float('inf') if mse == 0 else 10 * math.log10(255**2 / mse)

def mae(R1, G1, B1, R2, G2, B2):
    n = min(len(R1), len(R2))
    return sum(abs(R1[i]-R2[i])+abs(G1[i]-G2[i])+abs(B1[i]-B2[i])
               for i in range(n)) / (3 * n)


# ─────────────────────────────────────────────
#  Side-by-side comparison BMP
# ─────────────────────────────────────────────

def make_comparison_bmp(path, imgs, labels=None, gap=4):
    """Create side-by-side BMP of multiple images."""
    n      = len(imgs)
    W      = imgs[0][3]
    H      = imgs[0][4]
    total_w = W * n + gap * (n - 1)
    R_out, G_out, B_out = [], [], []

    for y in range(H):
        for idx, (Ri, Gi, Bi, w, h) in enumerate(imgs):
            for x in range(W):
                pi = y * W + x
                R_out.append(Ri[pi] if pi < len(Ri) else 0)
                G_out.append(Gi[pi] if pi < len(Gi) else 0)
                B_out.append(Bi[pi] if pi < len(Bi) else 0)
            if idx < n - 1:   # gap columns
                for _ in range(gap):
                    R_out.append(128); G_out.append(128); B_out.append(128)

    save_bmp(path, R_out, G_out, B_out, total_w, H)


# ─────────────────────────────────────────────
#  JTAG / SignalTap help text
# ─────────────────────────────────────────────

JTAG_HELP = """
══════════════════════════════════════════════════════════════
  Cách lấy ảnh từ FPGA hardware  (3 phương pháp)
══════════════════════════════════════════════════════════════

──────────────────────────────────────────────────
  Phương pháp A: In-System Memory Editor (đơn giản nhất)
──────────────────────────────────────────────────
  1. Quartus → Tools → In-System Memory Content Editor
  2. JTAG chain: chọn DE10-Standard
  3. Chọn instance "u_img_out_bram" (hoặc tên trong SoC)
  4. File → Export → xuất thành .mif hoặc .hex
  5. Convert: python hex2bmp.py exported_dump.hex -o out.bmp

  Lưu ý: Cần file .sof đang chạy trên FPGA có debug symbols.

──────────────────────────────────────────────────
  Phương pháp B: SignalTap Logic Analyzer
──────────────────────────────────────────────────
  1. Quartus → Tools → SignalTap II Logic Analyzer
  2. Add signals: img_out_bram.mem[0..16383]
  3. Set trigger: bất kỳ (manual)
  4. Run analysis → Export data → .csv hoặc .hex
  5. Convert: python hex2bmp.py signaltap_out.hex -o out.bmp

──────────────────────────────────────────────────
  Phương pháp C: Thêm UART readback (cần re-synthesize)
──────────────────────────────────────────────────
  Thêm UART TX peripheral vào SoC:
    • APB slave tại 0x1003_0000
    • CPU chạy ASM: đọc img_out_bram từng word → ghi UART TX
    • PC dùng script: python uart_capture.py --port COM3 -o out.hex
    • Convert: python hex2bmp.py out.hex -o out.bmp

  Script ASM dump qua UART:
    lui   t0, 0x40000      # IMG_OUT_BUF_BASE = 0x0004_0000
    lui   t1, 0x10030      # UART_TX_BASE = 0x1003_0000
    li    t2, 16384        # 128*128 words
    li    t3, 0
  uart_loop:
    lw    a0, 0(t0)        # đọc pixel
    sw    a0, 0(t1)        # ghi ra UART TX data
    # poll TX ready tại 0x1003_0004
    addi  t0, t0, 4
    addi  t3, t3, 1
    blt   t3, t2, uart_loop

══════════════════════════════════════════════════════════════
  Trước mắt (không cần FPGA hardware):
══════════════════════════════════════════════════════════════
  python hex2bmp.py ../06_FGPA_Imple/images/soc_input_128.hex   \\
      -o result/input_hazy.bmp
  python hex2bmp.py ../06_FGPA_Imple/images/soc_dehazed_128.hex \\
      -o result/dehazed_sw.bmp
  python hex2bmp.py --compare \\
      ../06_FGPA_Imple/images/soc_input_128.hex \\
      ../06_FGPA_Imple/images/soc_dehazed_128.hex
"""


# ─────────────────────────────────────────────
#  Main
# ─────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(
        description="BRAM hex → BMP converter / image viewer",
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("hex_files", nargs="*", metavar="HEX",
                    help="Input hex file(s)")
    ap.add_argument("-o", "--output",  default=None,
                    help="Output BMP path (auto-named if omitted)")
    ap.add_argument("--width",   type=int, default=W_DEFAULT)
    ap.add_argument("--height",  type=int, default=H_DEFAULT)
    ap.add_argument("--compare", action="store_true",
                    help="Compare multiple hex files side-by-side")
    ap.add_argument("--bmp",     nargs="+", metavar="BMP",
                    help="Compare BMP files (instead of hex)")
    ap.add_argument("--psnr",    action="store_true",
                    help="Print PSNR/MAE between first and second file")
    ap.add_argument("--help-jtag", action="store_true",
                    help="Show FPGA hardware capture guide")
    args = ap.parse_args()

    if args.help_jtag:
        print(JTAG_HELP)
        return

    RESULT_DIR.mkdir(exist_ok=True)

    # ── Compare mode ──────────────────────────────
    if args.compare or (len(args.hex_files) > 1 and not args.output):
        files = args.hex_files
        if not files:
            ap.error("--compare cần ít nhất 2 file hex")

        imgs  = []
        names = []
        for fp in files:
            R, G, B, w, h = load_hex(fp, args.width, args.height)
            imgs.append((R, G, B, w, h))
            names.append(Path(fp).stem)
            print(f"  Loaded: {fp}  ({w}×{h}, {w*h} words)")

        out_path = args.output or str(RESULT_DIR / ("compare_" + "_vs_".join(names) + ".bmp"))
        make_comparison_bmp(out_path, imgs, names)
        print(f"\n  [OK] Side-by-side → {out_path}")

        if len(imgs) == 2:
            R1,G1,B1,_,_ = imgs[0]; R2,G2,B2,_,_ = imgs[1]
            p = psnr(R1,G1,B1,R2,G2,B2)
            m = mae (R1,G1,B1,R2,G2,B2)
            print(f"  PSNR ({names[0]} vs {names[1]}) = {p:.2f} dB")
            print(f"  MAE  ({names[0]} vs {names[1]}) = {m:.2f} px/ch")
        return

    # ── BMP compare mode ─────────────────────────
    if args.bmp:
        imgs, names = [], []
        for fp in args.bmp:
            R, G, B, w, h = load_bmp(fp)
            imgs.append((R, G, B, w, h))
            names.append(Path(fp).stem)
            print(f"  Loaded BMP: {fp}  ({w}×{h})")
        out_path = args.output or str(RESULT_DIR / ("compare_" + "_vs_".join(names) + ".bmp"))
        make_comparison_bmp(out_path, imgs, names)
        print(f"\n  [OK] Side-by-side → {out_path}")
        if len(imgs) == 2:
            R1,G1,B1,_,_ = imgs[0]; R2,G2,B2,_,_ = imgs[1]
            p = psnr(R1,G1,B1,R2,G2,B2); m = mae(R1,G1,B1,R2,G2,B2)
            print(f"  PSNR = {p:.2f} dB   MAE = {m:.2f} px/ch")
        return

    # ── Single file mode ─────────────────────────
    if not args.hex_files:
        # Default: convert both standard files
        defaults = [
            SCRIPT_DIR.parent / "06_FGPA_Imple" / "images" / "soc_input_128.hex",
            SCRIPT_DIR.parent / "06_FGPA_Imple" / "images" / "soc_dehazed_128.hex",
        ]
        found = [str(p) for p in defaults if p.exists()]
        if not found:
            ap.print_help()
            return
        args.hex_files = found
        print("  [auto] Converting default hex files ...\n")

    for hex_path in args.hex_files:
        stem     = Path(hex_path).stem
        out_path = args.output or str(RESULT_DIR / (stem + ".bmp"))

        print(f"  Converting: {hex_path}")
        R, G, B, w, h = load_hex(hex_path, args.width, args.height)
        save_bmp(out_path, R, G, B, w, h)

        # Quick stats
        avg_r = sum(R) / len(R)
        avg_g = sum(G) / len(G)
        avg_b = sum(B) / len(B)
        print(f"  → {out_path}")
        print(f"     Size  : {w}×{h}  ({w*h} pixels)")
        print(f"     Avg   : R={avg_r:.0f}  G={avg_g:.0f}  B={avg_b:.0f}")
        print()

    # PSNR between first two files if requested
    if args.psnr and len(args.hex_files) >= 2:
        R1,G1,B1,_,_ = load_hex(args.hex_files[0], args.width, args.height)
        R2,G2,B2,_,_ = load_hex(args.hex_files[1], args.width, args.height)
        p = psnr(R1,G1,B1,R2,G2,B2); m = mae(R1,G1,B1,R2,G2,B2)
        print(f"  PSNR = {p:.2f} dB   MAE = {m:.2f} px/ch")


if __name__ == "__main__":
    main()
