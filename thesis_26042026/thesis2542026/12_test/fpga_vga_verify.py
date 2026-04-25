#!/usr/bin/env python3
"""
fpga_vga_verify.py — Verify FPGA Haze Removal qua VGA Output BMP
=================================================================
Đọc ảnh INPUT (hazy) và OUTPUT (dehazed từ simulation / FPGA),
phân tích chất lượng dehaze và in kết quả theo format chuẩn.

Cách dùng:
  python fpga_vga_verify.py                        # image_test (mặc định)
  python fpga_vga_verify.py --image 47             # image_47
  python fpga_vga_verify.py --in in.bmp --out out.bmp   # custom path
  python fpga_vga_verify.py --selftest             # offline, không cần file BMP
  python fpga_vga_verify.py --hex-dump             # thêm pixel hex dump

Flow:
  ┌──────────────────┐    img_in_bram    ┌──────────────┐
  │  input.bmp       │ ─── 128×128 ───→  │  FPGA / IPU  │
  │  (hazy image)    │                   │  (dehaze HW) │
  └──────────────────┘                   └──────┬───────┘
                                                 │ img_out_bram
                                          ┌──────▼───────┐
                                          │  VGA display │
                                          │  + save BMP  │ ← cpu_dehazed_128.bmp
                                          └──────────────┘
"""

import argparse
import os
import sys
import datetime

# Fix Windows console encoding
if sys.stdout.encoding and sys.stdout.encoding.lower() not in ('utf-8', 'utf8'):
    try:
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
        sys.stderr.reconfigure(encoding='utf-8', errors='replace')
    except AttributeError:
        pass

try:
    from PIL import Image
    import PIL
except ImportError:
    Image = None

try:
    import numpy as np
except ImportError:
    np = None

try:
    from colorama import Fore, Style, init as colorama_init
    colorama_init()
except ImportError:
    class Fore:
        GREEN = RED = YELLOW = CYAN = MAGENTA = WHITE = BLUE = RESET = ""
    class Style:
        BRIGHT = DIM = RESET_ALL = ""

# ============================================================
#  SoC Metadata
# ============================================================
SOC_INFO = {
    "Device"    : "Intel Cyclone V  5CSXFC6D6F31C6",
    "Board"     : "Terasic DE10-Standard",
    "Clock"     : "50 MHz  (Fmax measured: 27.13 MHz)",
    "CPU"       : "RISC-V RV32I, single-cycle",
    "Bus"       : "APB4 (CPU → IPU)",
    "Accelerator": "IPU — Dark-Channel Prior Haze Removal",
    "Output"    : "VGA 640×480 @ 60 Hz (25 MHz pixel clock, PLL)",
    "Image"     : "128×128 px, centered in 640×480 active area",
}

# ============================================================
#  Default image paths (relative to project root)
# ============================================================
_PROJ_ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))

IMAGE_SETS = {
    "test": {
        "input" : os.path.join(_PROJ_ROOT, "01_sim", "soc", "Testbench_SOC", "sim", "image_test", "soc_input_128.bmp"),
        "output": os.path.join(_PROJ_ROOT, "01_sim", "soc", "Testbench_SOC", "sim", "image_test", "cpu_dehazed_128.bmp"),
        "label" : "image_test (cityscape)",
    },
    "47": {
        "input" : os.path.join(_PROJ_ROOT, "01_sim", "soc", "Testbench_SOC", "sim", "image_47", "soc_input_128.bmp"),
        "output": os.path.join(_PROJ_ROOT, "01_sim", "soc", "Testbench_SOC", "sim", "image_47", "cpu_dehazed_128.bmp"),
        "label" : "image_47",
    },
}

# ============================================================
#  IPU / VGA Timing Constants
# ============================================================
CLK_MHZ        = 50.0
IMG_W, IMG_H   = 128, 128
PIXELS         = IMG_W * IMG_H          # 16384
BYTES_PER_PX   = 4                      # {pad, B, G, R}
IMG_BYTES      = PIXELS * BYTES_PER_PX  # 65536

# IPU processing estimate (from simulation: ~32750 cycles @ 50 MHz = ~655 µs)
IPU_CYCLES_EST = 32750
IPU_TIME_MS    = IPU_CYCLES_EST / CLK_MHZ / 1000.0

# VGA timing (640×480 @ 60 Hz)
VGA_H_TOTAL    = 800
VGA_V_TOTAL    = 525
VGA_PIXEL_CLK  = 25e6                   # Hz
VGA_FRAME_MS   = VGA_H_TOTAL * VGA_V_TOTAL / VGA_PIXEL_CLK * 1000.0  # ~16.7 ms
VGA_FRAME_HZ   = 1000.0 / VGA_FRAME_MS

# ============================================================
#  Helpers — same visual style as fpga_format_uart.py
# ============================================================
def _W(n=60): return "═" * n
def _w(n=60): return "─" * n

def _pf(ok, label):
    if ok:
        print(f"  {Fore.GREEN}✔  {label}{Style.RESET_ALL}")
    else:
        print(f"  {Fore.RED}✘  {label}{Style.RESET_ALL}")


def pixel_hex_dump(pixels_rgb, cols=8, expected_rgb=None, start_label=""):
    """
    Hex dump của pixel data (list of (R,G,B) tuples).
    Format mỗi pixel: RRGGBB  — tô màu xanh nếu khớp, đỏ nếu khác.
    """
    lines = []
    for i in range(0, len(pixels_rgb), cols):
        chunk     = pixels_rgb[i:i+cols]
        exp_chunk = expected_rgb[i:i+cols] if expected_rgb else None
        parts = []
        for j, (r, g, b) in enumerate(chunk):
            s = f"{r:02x}{g:02x}{b:02x}"
            if exp_chunk is not None:
                er, eg, eb = exp_chunk[j] if j < len(exp_chunk) else (0,0,0)
                if (r, g, b) != (er, eg, eb):
                    s = f"{Fore.RED}{s}{Style.RESET_ALL}"
                else:
                    s = f"{Fore.GREEN}{s}{Style.RESET_ALL}"
            parts.append(s)
        label = f"{start_label}{i:04d}" if start_label else f"{i:04d}"
        lines.append(f"    px[{label}]:  " + "  ".join(parts))
    return "\n".join(lines)


def load_bmp_rgb(path):
    """Load BMP → list of (R,G,B) tuples. Returns (pixels, width, height) or None."""
    if Image is None:
        print(f"{Fore.RED}  ERROR: Pillow chưa cài — pip install Pillow{Style.RESET_ALL}")
        return None
    try:
        img = Image.open(path).convert("RGB")
        w, h = img.size
        pixels = list(img.getdata())
        return pixels, w, h
    except FileNotFoundError:
        return None
    except Exception as e:
        print(f"{Fore.RED}  ERROR: Không đọc được {path}: {e}{Style.RESET_ALL}")
        return None


# ============================================================
#  Metrics
# ============================================================
def mean_brightness(pixels):
    """Mean luminance (0–255) from RGB pixel list."""
    total = sum(0.299*r + 0.587*g + 0.114*b for r,g,b in pixels)
    return total / len(pixels)


def dark_channel_mean(pixels, patch=15):
    """
    Approximate dark channel mean.
    dark_channel(p) = min over patch of min(R,G,B).
    For simplicity: compute per-pixel min(R,G,B) then mean.
    Full patch min would need numpy reshape — skip if no numpy.
    """
    if np is not None:
        arr = np.array(pixels, dtype=np.float32).reshape(IMG_H, IMG_W, 3)
        dark_px = arr.min(axis=2)  # per-pixel dark (W×H)
        # Patch min via min-pooling (approximate with uniform kernel)
        from scipy.ndimage import minimum_filter
        try:
            dark_ch = minimum_filter(dark_px, size=patch)
        except ImportError:
            dark_ch = dark_px
        return float(dark_ch.mean())
    else:
        return sum(min(r,g,b) for r,g,b in pixels) / len(pixels)


def psnr(img_a, img_b):
    """PSNR between two pixel lists. Returns dB or None if identical."""
    if np is None:
        mse = sum((a[c]-b[c])**2 for a,b in zip(img_a,img_b) for c in range(3))
        mse /= (len(img_a)*3)
    else:
        a = np.array(img_a, dtype=np.float64)
        b = np.array(img_b, dtype=np.float64)
        mse = float(np.mean((a-b)**2))
    if mse == 0:
        return None  # identical
    import math
    return 20 * math.log10(255.0) - 10 * math.log10(mse)


def pixel_diff_stats(img_a, img_b, threshold=5):
    """
    Đếm pixel thay đổi đáng kể (per-channel diff > threshold).
    Returns (changed_count, total, max_diff)
    """
    changed = 0
    max_d   = 0
    for (r1,g1,b1),(r2,g2,b2) in zip(img_a, img_b):
        d = max(abs(r1-r2), abs(g1-g2), abs(b1-b2))
        if d > threshold: changed += 1
        if d > max_d: max_d = d
    return changed, len(img_a), max_d


# ============================================================
#  Core verification function
# ============================================================
def verify_vga_output(in_path, out_path, set_label="", show_hex=False):
    """
    Verify VGA dehaze output.
    Mirrors send_and_verify() flow từ fpga_format_uart.py.
    """
    ts = datetime.datetime.now().strftime("%Y-%m-%d  %H:%M:%S")

    # ── Header ─────────────────────────────────────────────────
    print(f"\n{Fore.CYAN}{_W()}{Style.RESET_ALL}")
    print(f"{Fore.CYAN}{Style.BRIGHT}  Dark-Channel Prior Haze Removal — VGA Output Verify{Style.RESET_ALL}")
    print(f"{Fore.CYAN}  Image Set  : {set_label}{Style.RESET_ALL}")
    print(f"{Fore.CYAN}  Timestamp  : {ts}{Style.RESET_ALL}")
    print(f"{Fore.CYAN}{_W()}{Style.RESET_ALL}")

    # ── SoC Info ───────────────────────────────────────────────
    print(f"\n{Style.BRIGHT}  SoC / Hardware:{Style.RESET_ALL}")
    for k, v in SOC_INFO.items():
        print(f"    {k:<14}: {v}")

    # ── VGA Timing ─────────────────────────────────────────────
    print(f"\n{Style.BRIGHT}  VGA Timing (640×480 @ 60 Hz):{Style.RESET_ALL}")
    print(f"    Pixel clock    : {VGA_PIXEL_CLK/1e6:.0f} MHz  (PLL: CLOCK_50 ÷ 2)")
    print(f"    H total        : {VGA_H_TOTAL} clocks  ({VGA_H_TOTAL/VGA_PIXEL_CLK*1e6:.1f} µs/line)")
    print(f"    V total        : {VGA_V_TOTAL} lines")
    print(f"    Frame period   : {VGA_FRAME_MS:.3f} ms  ({VGA_FRAME_HZ:.2f} Hz refresh)")
    print(f"    Image region   : px[256..383] × line[176..303]  (centered 128×128)")
    print(f"    BRAM read port : vga_rd_addr[14:0] = {{row[6:0], col[6:0]}}")
    print(f"    Pixel format   : 32-bit word = {{pad[31:24], B[23:16], G[15:8], R[7:0]}}")

    # ── Bước 1: Load input (hazy) ──────────────────────────────
    print(f"\n{_w()}")
    print(f"{Fore.YELLOW}  [BƯỚC 1]  Đọc ảnh INPUT (hazy) → img_in_bram{Style.RESET_ALL}")
    print(f"  {Style.DIM}(pre-loaded lúc synthesis qua $readmemh){Style.RESET_ALL}")
    print(f"  Path: {Style.DIM}{in_path}{Style.RESET_ALL}")

    in_result = load_bmp_rgb(in_path)
    if in_result is None:
        print(f"  {Fore.RED}✘  Không tìm thấy file input BMP{Style.RESET_ALL}")
        print(f"     → Chạy simulation trước: do script/run_cpu_vga_dehaze_test.tcl")
        return False
    in_pixels, in_w, in_h = in_result
    in_size_kb = in_w * in_h * 3 / 1024
    print(f"  {Fore.GREEN}✔  Đọc thành công: {in_w}×{in_h} px,  {in_size_kb:.1f} KB{Style.RESET_ALL}")
    print(f"  BRAM capacity used: {in_w*in_h*4/1024:.0f} KB / 64 KB  ({in_w*in_h*4*100//65536}%)")

    if show_hex:
        print(f"\n  Pixel hex dump — 8 pixels đầu (RRGGBB):")
        print(pixel_hex_dump(in_pixels[:16], cols=8))

    # ── Bước 2: IPU Processing ─────────────────────────────────
    print(f"\n{_w()}")
    print(f"{Fore.YELLOW}  [BƯỚC 2]  IPU Processing (Dark-Channel Prior){Style.RESET_ALL}")
    print(f"  {Style.DIM}CPU trigger: CTRL=0x3 → CTRL=0x1, poll IRQ_STATUS{Style.RESET_ALL}")
    print(f"    Ảnh          : {IMG_W}×{IMG_H} = {PIXELS:,} pixels,  {IMG_BYTES//1024} KB")
    print(f"    IPU ước tính : ~{IPU_CYCLES_EST:,} cycles  @{CLK_MHZ:.0f}MHz ≈ {IPU_TIME_MS*1000:.0f} µs")
    print(f"    Throughput   : {PIXELS/IPU_TIME_MS*1000/1e6:.2f} Mpx/s")
    print(f"    {Style.DIM}(giá trị từ QuestaSim simulation, FPGA thực tế tương tự){Style.RESET_ALL}")

    # ── Bước 3: Load output (dehazed) ─────────────────────────
    print(f"\n{_w()}")
    print(f"{Fore.YELLOW}  [BƯỚC 3]  Đọc ảnh OUTPUT (dehazed) ← img_out_bram → VGA{Style.RESET_ALL}")
    print(f"  {Style.DIM}(VGA controller quét img_out_bram liên tục sau khi IPU done){Style.RESET_ALL}")
    print(f"  Path: {Style.DIM}{out_path}{Style.RESET_ALL}")

    out_result = load_bmp_rgb(out_path)
    if out_result is None:
        print(f"  {Fore.RED}✘  Không tìm thấy file output BMP{Style.RESET_ALL}")
        print(f"     → Testbench lưu file này sau khi detect LEDR=0xFFFFFFFF")
        print(f"     → Chạy: do script/run_cpu_vga_dehaze_test.tcl")
        return False
    out_pixels, out_w, out_h = out_result
    print(f"  {Fore.GREEN}✔  Đọc thành công: {out_w}×{out_h} px{Style.RESET_ALL}")

    if in_w != out_w or in_h != out_h:
        print(f"  {Fore.RED}✘  Kích thước không khớp: input {in_w}×{in_h} vs output {out_w}×{out_h}{Style.RESET_ALL}")
        return False

    if show_hex:
        print(f"\n  Pixel hex dump — 8 pixels đầu của OUTPUT (RRGGBB):")
        print(pixel_hex_dump(out_pixels[:16], cols=8, expected_rgb=in_pixels[:16]))
        print(f"  {Style.DIM}(đỏ = khác input, xanh = giữ nguyên){Style.RESET_ALL}")

    # ── Bước 4: Quality Analysis ───────────────────────────────
    print(f"\n{_w()}")
    print(f"{Style.BRIGHT}  [BƯỚC 4]  Phân Tích Chất Lượng Dehaze:{Style.RESET_ALL}")

    in_bright  = mean_brightness(in_pixels)
    out_bright = mean_brightness(out_pixels)
    bright_delta = out_bright - in_bright
    bright_pct   = bright_delta / max(in_bright, 1e-6) * 100

    in_dark  = dark_channel_mean(in_pixels)
    out_dark = dark_channel_mean(out_pixels)
    dark_delta = in_dark - out_dark  # positive = reduction (good)
    dark_pct   = dark_delta / max(in_dark, 1e-6) * 100

    psnr_val = psnr(in_pixels, out_pixels)
    changed, total, max_diff = pixel_diff_stats(in_pixels, out_pixels, threshold=5)
    change_pct = changed / total * 100

    # Sanity checks
    all_black = all(r==0 and g==0 and b==0 for r,g,b in out_pixels)
    all_white = all(r==255 and g==255 and b==255 for r,g,b in out_pixels)
    identical = (in_pixels == out_pixels)

    col_bright = Fore.GREEN if bright_delta > 1 else (Fore.YELLOW if bright_delta >= 0 else Fore.RED)
    col_dark   = Fore.GREEN if dark_delta   > 1 else (Fore.YELLOW if dark_delta >= 0 else Fore.RED)
    col_change = Fore.GREEN if change_pct  > 5 else (Fore.YELLOW if change_pct > 0 else Fore.RED)

    print(f"\n    {'Metrik':<30} {'Input (hazy)':<18} {'Output (dehazed)':<18} {'Delta'}")
    print(f"    {_w(70)}")
    print(f"    {'Mean brightness':<30} {in_bright:<18.2f} {col_bright}{out_bright:<18.2f}{Style.RESET_ALL} "
          f"{col_bright}{bright_delta:+.2f}  ({bright_pct:+.1f}%){Style.RESET_ALL}")
    print(f"    {'Dark channel mean':<30} {in_dark:<18.2f} {col_dark}{out_dark:<18.2f}{Style.RESET_ALL} "
          f"{col_dark}{-dark_delta:+.2f}  ({-dark_pct:+.1f}%){Style.RESET_ALL}")
    if psnr_val is not None:
        print(f"    {'PSNR (vs input)':<30} {'N/A':<18} {psnr_val:<18.2f} {'(dB — thấp = thay đổi nhiều)'}")
    else:
        print(f"    {'PSNR (vs input)':<30} {'N/A':<18} {'∞ (identical)':<18}")
    print(f"    {'Pixels changed (>5 LSB)':<30} {col_change}{changed:,} / {total:,}  ({change_pct:.1f}%){Style.RESET_ALL}  "
          f"Max diff: {max_diff}")

    # ── Bước 5: Sanity checks ──────────────────────────────────
    print(f"\n{_w()}")
    print(f"{Style.BRIGHT}  [BƯỚC 5]  Kiểm Tra Tính Hợp Lệ:{Style.RESET_ALL}")

    ok_not_black   = not all_black
    ok_not_white   = not all_white
    ok_not_ident   = not identical
    ok_brighter    = bright_delta > 0
    ok_dark_reduce = dark_delta   > 0
    ok_changed     = change_pct   > 1.0

    _pf(ok_not_black,   f"Output không phải all-black  (IPU không crash)")
    _pf(ok_not_white,   f"Output không phải all-white  (không overflow)")
    _pf(ok_not_ident,   f"Output KHÁC input            (IPU thực sự xử lý, {changed:,} px thay đổi)")
    _pf(ok_brighter,    f"Brightness tăng              ({in_bright:.1f} → {out_bright:.1f},  delta={bright_delta:+.2f})")
    _pf(ok_dark_reduce, f"Dark channel giảm            ({in_dark:.1f} → {out_dark:.1f},  reduced={dark_delta:.2f})")
    _pf(ok_changed,     f"Tỷ lệ pixel thay đổi > 1%   ({change_pct:.1f}% = {changed:,}/{total:,} px)")

    # ── Timing Summary ─────────────────────────────────────────
    print(f"\n{_w()}")
    print(f"{Style.BRIGHT}  Hiệu năng:{Style.RESET_ALL}")
    print(f"    IPU xử lý ảnh  : {Fore.MAGENTA}~{IPU_TIME_MS*1000:.0f} µs{Style.RESET_ALL}  "
          f"({Fore.MAGENTA}~{IPU_CYCLES_EST:,} cycles @{CLK_MHZ:.0f}MHz{Style.RESET_ALL})")
    print(f"    VGA frame time : {Fore.BLUE}{VGA_FRAME_MS:.3f} ms{Style.RESET_ALL}  "
          f"({Fore.BLUE}{VGA_FRAME_HZ:.2f} Hz refresh{Style.RESET_ALL})")
    print(f"    IPU / frame    : {Fore.BLUE}{IPU_TIME_MS / VGA_FRAME_MS * 100:.1f}%{Style.RESET_ALL}  "
          f"({Style.DIM}IPU xử lý xong trong {IPU_TIME_MS/VGA_FRAME_MS:.2f} frame{Style.RESET_ALL})")
    pixels_per_sec = PIXELS / (IPU_TIME_MS / 1000)
    print(f"    Throughput IPU : {Fore.MAGENTA}{pixels_per_sec/1e6:.2f} Mpx/s{Style.RESET_ALL}  "
          f"({pixels_per_sec*3/1e6:.1f} MB/s pixel data)")

    # ── Final Verdict ──────────────────────────────────────────
    all_pass = ok_not_black and ok_not_white and ok_not_ident and ok_changed

    print(f"\n{_W()}")
    if all_pass:
        print(f"{Fore.GREEN}{Style.BRIGHT}"
              f"  ✔  PASS  —  IPU dehaze thành công, VGA output hợp lệ"
              f"{Style.RESET_ALL}")
        if ok_brighter and ok_dark_reduce:
            print(f"{Fore.GREEN}  ⇒  Ảnh sáng hơn +{bright_pct:.1f}%, dark channel giảm {dark_pct:.1f}%"
                  f" — kết quả đúng kỳ vọng của Dark-Channel Prior.{Style.RESET_ALL}")
        else:
            print(f"{Fore.YELLOW}  ⚠  Output hợp lệ nhưng metrics brightness/dark channel chưa như kỳ vọng."
                  f" Kiểm tra IPU algorithm.{Style.RESET_ALL}")
    else:
        print(f"{Fore.RED}{Style.BRIGHT}"
              f"  ✘  FAIL  —  VGA output không hợp lệ"
              f"{Style.RESET_ALL}")
        if all_black:
            print(f"{Fore.RED}  ⇒  ALL BLACK: IPU chưa ghi vào img_out_bram. Kiểm tra CTRL trigger.{Style.RESET_ALL}")
        if all_white:
            print(f"{Fore.RED}  ⇒  ALL WHITE: Dữ liệu overflow hoặc BRAM init sai.{Style.RESET_ALL}")
        if identical:
            print(f"{Fore.RED}  ⇒  IDENTICAL: IPU bypass hoàn toàn. Kiểm tra SRC/DST ADDR config.{Style.RESET_ALL}")
    print(_W())

    return all_pass


# ============================================================
#  Selftest — không cần file BMP thực
# ============================================================
def selftest():
    """
    Selftest offline: tạo synthetic hazy/dehazed image bằng Pillow/numpy,
    chạy verify_vga_output() với dữ liệu giả để kiểm tra toàn bộ pipeline phân tích.
    """
    import tempfile
    import random

    ts = datetime.datetime.now().strftime("%Y-%m-%d  %H:%M:%S")
    print(f"\n{Fore.CYAN}{_W()}{Style.RESET_ALL}")
    print(f"{Fore.CYAN}{Style.BRIGHT}  VGA Dehaze Verify — Offline Selftest (không cần FPGA){Style.RESET_ALL}")
    print(f"{Fore.CYAN}  Timestamp : {ts}{Style.RESET_ALL}")
    print(f"{Fore.CYAN}  Mock      : Synthetic 128×128 BMP — hazy → dehazed{Style.RESET_ALL}")
    print(f"{Fore.CYAN}{_W()}{Style.RESET_ALL}")

    if Image is None:
        print(f"{Fore.RED}  ERROR: Pillow chưa cài. pip install Pillow{Style.RESET_ALL}")
        return False

    W, H = 128, 128
    tmpdir = tempfile.mkdtemp()
    in_path  = os.path.join(tmpdir, "mock_input.bmp")
    out_path = os.path.join(tmpdir, "mock_output.bmp")

    # Generate synthetic hazy image: low contrast, grayish
    random.seed(42)
    in_pixels = []
    for _ in range(W * H):
        base = random.randint(80, 180)
        r = max(0, min(255, base + random.randint(-20, 20) + 40))  # haze = add gray bias
        g = max(0, min(255, base + random.randint(-20, 20) + 40))
        b = max(0, min(255, base + random.randint(-20, 20) + 60))  # blue haze
        in_pixels.append((r, g, b))

    # Simulate dehaze: increase contrast, reduce gray bias (dark channel removal)
    out_pixels = []
    for r, g, b in in_pixels:
        dc = min(r, g, b)              # dark channel per pixel
        t  = 1.0 - 0.85 * dc / 255.0  # estimated transmission
        r2 = int(min(255, (r - dc) / max(t, 0.1) + 10))
        g2 = int(min(255, (g - dc) / max(t, 0.1) + 10))
        b2 = int(min(255, (b - dc) / max(t, 0.1) + 5))
        out_pixels.append((r2, g2, b2))

    img_in  = Image.new("RGB", (W, H))
    img_in.putdata(in_pixels)
    img_in.save(in_path)

    img_out = Image.new("RGB", (W, H))
    img_out.putdata(out_pixels)
    img_out.save(out_path)

    print(f"\n  {Style.BRIGHT}Mock data tạo tại:{Style.RESET_ALL}")
    print(f"    Input  : {in_path}")
    print(f"    Output : {out_path}")

    ok = verify_vga_output(in_path, out_path, set_label="SELFTEST (synthetic mock)", show_hex=True)

    # Cleanup
    try:
        os.remove(in_path)
        os.remove(out_path)
        os.rmdir(tmpdir)
    except OSError:
        pass

    return ok


# ============================================================
#  Main
# ============================================================
def main():
    parser = argparse.ArgumentParser(
        description="FPGA VGA Verify — Haze Removal output analysis",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Ví dụ:
  python fpga_vga_verify.py                          # image_test (mặc định)
  python fpga_vga_verify.py --image 47               # image_47
  python fpga_vga_verify.py --in a.bmp --out b.bmp  # custom paths
  python fpga_vga_verify.py --selftest               # offline test
  python fpga_vga_verify.py --hex-dump               # thêm pixel hex dump
        """,
    )
    parser.add_argument("--image", "-i", default="test",
                        choices=list(IMAGE_SETS.keys()) + ["test"],
                        help="Bộ ảnh: 'test' (mặc định) hoặc '47'")
    parser.add_argument("--in",  dest="in_path",  default=None,
                        help="Custom path ảnh input (BMP)")
    parser.add_argument("--out", dest="out_path", default=None,
                        help="Custom path ảnh output / dehazed (BMP)")
    parser.add_argument("--selftest", action="store_true",
                        help="Chạy selftest offline (không cần file BMP)")
    parser.add_argument("--hex-dump", action="store_true",
                        help="Hiển thị pixel hex dump (16 pixels đầu)")
    args = parser.parse_args()

    # --- Selftest ---
    if args.selftest:
        ok = selftest()
        sys.exit(0 if ok else 1)

    # --- Xác định paths ---
    if args.in_path and args.out_path:
        in_path  = os.path.abspath(args.in_path)
        out_path = os.path.abspath(args.out_path)
        label    = f"custom ({os.path.basename(in_path)})"
    else:
        img_key  = args.image if args.image in IMAGE_SETS else "test"
        cfg      = IMAGE_SETS[img_key]
        in_path  = cfg["input"]
        out_path = cfg["output"]
        label    = cfg["label"]

    # --- Check Pillow ---
    if Image is None:
        print(f"{Fore.RED}ERROR: Pillow chưa cài. pip install Pillow{Style.RESET_ALL}")
        sys.exit(1)

    ok = verify_vga_output(in_path, out_path, set_label=label, show_hex=args.hex_dump)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
