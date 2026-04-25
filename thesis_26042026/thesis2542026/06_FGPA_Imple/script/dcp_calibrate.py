#!/usr/bin/env python3
"""
Dark Channel Prior (DCP) Dehazing – Parameter Calibration Script  (numpy)
==========================================================================
Applies DCP dehazing to soc_input_128.bmp (image_47), tunes parameters to
best match soc_output_128.bmp (golden reference from simulation), then saves
the calibrated output BMP + generates soc_dehazed_128.hex for FPGA BRAM.

Usage:
    python dcp_calibrate.py               # grid-search + save
    python dcp_calibrate.py --no-search   # use hardcoded params
    python dcp_calibrate.py --show-psnr   # print PSNR table during search

Outputs:
    ../images/soc_dehazed_128.bmp   -- software-dehazed result (calibrated)
    ../images/soc_dehazed_128.hex   -- hex ready for img_in_bram $readmemh
"""

import argparse
import math
import os
import struct
from pathlib import Path

import numpy as np

SCRIPT_DIR = Path(__file__).resolve().parent
IMAGES_DIR = SCRIPT_DIR.parent / "images"
SIM_DIR    = Path(__file__).resolve().parents[2] / \
             "01_sim" / "soc" / "Testbench_SOC" / "sim" / "image_47"

INPUT_BMP  = SIM_DIR  / "soc_input_128.bmp"
GOLDEN_BMP = SIM_DIR  / "soc_output_128.bmp"
OUT_BMP    = IMAGES_DIR / "soc_dehazed_128.bmp"
OUT_HEX    = IMAGES_DIR / "soc_dehazed_128.hex"

W = H = 128
DEPTH = W * H   # 16384 words

# ─────────────────────────────────────────────
#  BMP I/O  (stdlib only, bottom-up aware)
# ─────────────────────────────────────────────

def load_bmp_np(path) -> np.ndarray:
    """Load 24-bit BMP → float32 array (H, W, 3)  channels = R, G, B."""
    with open(path, "rb") as f:
        raw = f.read()
    if raw[0:2] != b"BM":
        raise ValueError(f"Not a BMP: {path}")
    data_off  = struct.unpack_from("<I", raw, 10)[0]
    bmp_w     = struct.unpack_from("<i", raw, 18)[0]
    bmp_h     = struct.unpack_from("<i", raw, 22)[0]
    bpp       = struct.unpack_from("<H", raw, 28)[0]
    if bpp != 24:
        raise ValueError(f"Only 24-bit BMP supported (got {bpp})")

    bottom_up  = bmp_h > 0
    bmp_h      = abs(bmp_h)
    row_stride = ((bmp_w * 3 + 3) // 4) * 4

    rows = [raw[data_off + y * row_stride: data_off + y * row_stride + bmp_w * 3]
            for y in range(bmp_h)]
    if bottom_up:
        rows = rows[::-1]

    img = np.zeros((min(bmp_h, H), min(bmp_w, W), 3), dtype=np.float32)
    for y, row in enumerate(rows[:H]):
        for x in range(min(bmp_w, W)):
            b = row[x * 3]
            g = row[x * 3 + 1]
            r = row[x * 3 + 2]
            img[y, x] = (r, g, b)
    return img                # float32, range [0, 255]


def save_bmp_np(path, img: np.ndarray):
    """Save float32/uint8 (H,W,3) RGB array to 24-bit bottom-up BMP."""
    arr = np.clip(img, 0, 255).astype(np.uint8)
    row_stride = ((W * 3 + 3) // 4) * 4
    pad = row_stride - W * 3
    pixel_data = bytearray()
    for y in range(H - 1, -1, -1):          # BMP: bottom row first
        for x in range(W):
            r, g, b = arr[y, x]
            pixel_data += bytes([b, g, r])   # BMP stores BGR
        pixel_data += b'\x00' * pad
    file_size = 54 + len(pixel_data)
    header = struct.pack("<2sIHHI", b"BM", file_size, 0, 0, 54)
    dib    = struct.pack("<IiiHHIIiiII", 40, W, H, 1, 24, 0,
                         len(pixel_data), 2835, 2835, 0, 0)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(header + dib + pixel_data)


def bmp_to_hex(path_bmp, path_hex):
    """Convert BMP → $readmemh hex (00BBGGRR, no 0x prefix)."""
    img = load_bmp_np(path_bmp).astype(np.uint8)
    R = img[:, :, 0].flatten()
    G = img[:, :, 1].flatten()
    B = img[:, :, 2].flatten()
    words = (B.astype(np.uint32) << 16) | (G.astype(np.uint32) << 8) | R.astype(np.uint32)
    lines = [f"{w:08X}" for w in words[:DEPTH]]
    while len(lines) < DEPTH:
        lines.append("00000000")
    with open(path_hex, "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"  [hex] {path_hex}  ({DEPTH} words)")


# ─────────────────────────────────────────────
#  DCP Core  (vectorized numpy)
# ─────────────────────────────────────────────

def dark_channel_np(img: np.ndarray, patch: int) -> np.ndarray:
    """Fast dark channel using sliding window min.  Returns (H, W) float32."""
    # Per-pixel minimum across RGB channels
    dark = img.min(axis=2)                              # (H, W)
    half = patch // 2
    # Pad with 255 (large value) so border pixels don't pull down the min
    padded = np.pad(dark, half, mode='edge')            # (H+2h, W+2h)
    # Build sliding window view: shape (H, W, patch, patch)
    from numpy.lib.stride_tricks import sliding_window_view
    windows = sliding_window_view(padded, (patch, patch))   # (H, W, p, p)
    return windows.min(axis=(2, 3))                     # (H, W)


def estimate_atmosphere_np(img: np.ndarray, dc: np.ndarray):
    """Top-0.1% dark-channel pixels → atmospheric light [R, G, B]."""
    n_top   = max(1, int(0.001 * H * W))
    flat_dc = dc.flatten()
    indices = np.argpartition(flat_dc, -n_top)[-n_top:]
    flat_img = img.reshape(-1, 3)
    candidates = flat_img[indices]                  # (n_top, 3)
    return candidates.max(axis=0)                   # (3,) = [Ar, Ag, Ab]


def estimate_transmission_np(img: np.ndarray, A: np.ndarray,
                              omega: float, patch: int) -> np.ndarray:
    """t(x) = 1 - omega * DC(I/A),  returns (H, W) float32."""
    A_safe = np.maximum(A, 1.0)
    norm   = img / A_safe[None, None, :]            # (H, W, 3)
    norm   = np.clip(norm * 255.0, 0, 255)          # scale to [0,255] for DC
    dc     = dark_channel_np(norm, patch)           # (H, W) in [0,255]
    return np.clip(1.0 - omega * (dc / 255.0), 0, 1)


def box_filter_np(t: np.ndarray, radius: int) -> np.ndarray:
    """Average (box) blur of transmission map."""
    from numpy.lib.stride_tricks import sliding_window_view
    padded = np.pad(t, radius, mode='edge')
    win    = sliding_window_view(padded, (2 * radius + 1, 2 * radius + 1))
    return win.mean(axis=(2, 3))


def recover_scene_np(img: np.ndarray, t: np.ndarray,
                     A: np.ndarray, t_min: float) -> np.ndarray:
    """J = (I - A) / max(t, t_min) + A, clipped to [0, 255]."""
    t_clamped = np.maximum(t[:, :, None], t_min)   # (H, W, 1)
    J = (img - A[None, None, :]) / t_clamped + A[None, None, :]
    return np.clip(J, 0, 255)


def dehaze_np(img: np.ndarray, patch=15, omega=0.95,
              t_min=0.10, refine_radius=0) -> np.ndarray:
    """Full DCP pipeline on float32 (H, W, 3) image."""
    dc = dark_channel_np(img / 255.0 * 255.0, patch)   # work in [0,255]
    A  = estimate_atmosphere_np(img, dc)
    t  = estimate_transmission_np(img, A, omega, patch)
    if refine_radius > 0:
        t = box_filter_np(t, refine_radius)
    return recover_scene_np(img, t, A, t_min)


# ─────────────────────────────────────────────
#  Quality Metrics  (numpy)
# ─────────────────────────────────────────────

def psnr_np(a: np.ndarray, b: np.ndarray) -> float:
    mse = float(np.mean((a.astype(np.float64) - b.astype(np.float64)) ** 2))
    return float('inf') if mse == 0 else 10 * math.log10(255 ** 2 / mse)


def mae_np(a: np.ndarray, b: np.ndarray) -> float:
    return float(np.mean(np.abs(a.astype(np.float64) - b.astype(np.float64))))


# ─────────────────────────────────────────────
#  Parameter Grid Search
# ─────────────────────────────────────────────

PATCH_SIZES  = [7, 11, 15, 19]
OMEGAS       = [0.75, 0.80, 0.85, 0.90, 0.95, 0.98]
T_MINS       = [0.05, 0.10, 0.15, 0.20]
REFINE_RADII = [0, 4, 8]


def grid_search(img_in: np.ndarray, img_gold: np.ndarray,
                show_psnr=False):
    """Return (best_params, best_psnr, best_output_image)."""
    best_psnr   = -1.0
    best_params = None
    best_out    = None

    total = len(PATCH_SIZES) * len(OMEGAS) * len(T_MINS) * len(REFINE_RADII)
    done  = 0

    for patch in PATCH_SIZES:
        for omega in OMEGAS:
            # Pre-compute transmission once per (patch, omega) — shared across t_min / refine
            dc = dark_channel_np(img_in, patch)
            A  = estimate_atmosphere_np(img_in, dc)
            # img_in / A → values in [0, 1]; dc_norm also in [0, 1] → use directly
            dc_norm = dark_channel_np(img_in / np.maximum(A, 1.0)[None, None, :], patch)
            t_base  = np.clip(1.0 - omega * dc_norm, 0, 1)   # dc_norm in [0,1]

            t_variants = {0: t_base}
            for r in REFINE_RADII:
                if r > 0:
                    t_variants[r] = box_filter_np(t_base, r)

            for t_min in T_MINS:
                for radius in REFINE_RADII:
                    out = recover_scene_np(img_in, t_variants[radius], A, t_min)
                    p   = psnr_np(out, img_gold)
                    done += 1
                    if show_psnr:
                        print(f"  patch={patch:2d} omega={omega:.2f} t_min={t_min:.2f} "
                              f"refine={radius:2d}  PSNR={p:.2f} dB  [{done}/{total}]")
                    if p > best_psnr:
                        best_psnr   = p
                        best_params = (patch, omega, t_min, radius)
                        best_out    = out.copy()

    return best_params, best_psnr, best_out


# ─────────────────────────────────────────────
#  Main
# ─────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(description="DCP dehazing calibration (numpy)")
    ap.add_argument("--no-search",  action="store_true",
                    help="Skip grid search, use hardcoded params")
    ap.add_argument("--show-psnr",  action="store_true",
                    help="Print PSNR for each parameter combination")
    ap.add_argument("--patch",  type=int,   default=15)
    ap.add_argument("--omega",  type=float, default=0.95)
    ap.add_argument("--t-min",  type=float, default=0.10)
    ap.add_argument("--refine", type=int,   default=0)
    args = ap.parse_args()

    print("=" * 62)
    print("  DCP Dehazing Calibration  [numpy accelerated]")
    print("=" * 62)

    print(f"\n[1] Loading input  : {INPUT_BMP}")
    img_in   = load_bmp_np(INPUT_BMP)
    print(f"    {img_in.shape}  dtype={img_in.dtype}  range=[{img_in.min():.0f},{img_in.max():.0f}]")

    print(f"[2] Loading golden : {GOLDEN_BMP}")
    img_gold = load_bmp_np(GOLDEN_BMP)
    print(f"    {img_gold.shape}  dtype={img_gold.dtype}  range=[{img_gold.min():.0f},{img_gold.max():.0f}]")

    if args.no_search:
        patch  = args.patch
        omega  = args.omega
        t_min  = args.t_min
        radius = args.refine
        print(f"\n[3] Fixed params: patch={patch} omega={omega} "
              f"t_min={t_min} refine={radius}")
        out = dehaze_np(img_in, patch, omega, t_min, radius)
        p   = psnr_np(out, img_gold)
        m   = mae_np (out, img_gold)
        print(f"    PSNR = {p:.2f} dB   MAE = {m:.2f}")
    else:
        total = len(PATCH_SIZES) * len(OMEGAS) * len(T_MINS) * len(REFINE_RADII)
        print(f"\n[3] Grid search  ({total} combos × 4 params)  …")
        (patch, omega, t_min, radius), best_p, out = \
            grid_search(img_in, img_gold, show_psnr=args.show_psnr)
        p = best_p
        m = mae_np(out, img_gold)
        print(f"\n  ★ Best params → patch={patch}  omega={omega}  "
              f"t_min={t_min}  refine={radius}")
        print(f"  ★ PSNR = {p:.2f} dB   MAE = {m:.2f}")

    # Baseline comparison
    p_raw = psnr_np(img_in, img_gold)
    m_raw = mae_np (img_in, img_gold)
    print(f"\n  Baseline  (hazy input vs golden) : PSNR={p_raw:.2f} dB  MAE={m_raw:.2f}")
    print(f"  Improvement                      : ΔPSNR=+{p-p_raw:.2f} dB  ΔMAE=-{m_raw-m:.2f}")

    # Save
    IMAGES_DIR.mkdir(exist_ok=True)
    print(f"\n[4] Saving dehazed BMP  : {OUT_BMP}")
    save_bmp_np(str(OUT_BMP), out)

    print(f"[5] Generating hex file : {OUT_HEX}")
    bmp_to_hex(str(OUT_BMP), str(OUT_HEX))

    print("\n[DONE]")
    print(f"  input            : {INPUT_BMP.name}   (image_47 hazy)")
    print(f"  golden reference : {GOLDEN_BMP.name}  (simulation DCP)")
    print(f"  SW dehazed BMP   : {OUT_BMP}")
    print(f"  FPGA BRAM hex    : {OUT_HEX}")
    print(f"  PSNR vs golden   = {p:.2f} dB")
    print(f"  MAE  vs golden   = {m:.2f} px/channel")
    print()
    print("  To pre-load SW-dehazed image into FPGA, update INIT_FILE:")
    print(f"    .INIT_FILE(\"../../06_FGPA_Imple/images/{OUT_HEX.name}\")")


if __name__ == "__main__":
    main()

