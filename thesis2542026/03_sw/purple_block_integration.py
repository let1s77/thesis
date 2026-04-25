"""
Purple Block Integration - Python Reference Model
====================================================
E2E pipeline: dark_channel -> atmospheric_light -> sky_recognition
              -> estimate_transmission -> bank readback

2-pass architecture:
  Pass 1: Stream frame -> dark_channel -> atmospheric_light -> latch A
  Pass 2: Stream frame -> dark_channel -> grayscale -> sky_recognition
                       -> estimate_transmission (using A from pass 1)
                       -> bank write

Test configuration:
  IMG_WIDTH  = 4, IMG_HEIGHT = 4 (16 pixels)
  A0         = 150  (sky threshold)
  use_dark   = 0    (compare gray for sky recognition)
  use_sky    = 1    (enable sky override in estimate_transmission)
  t_sky      = 255  (sky pixels get max transmission)
  OMEGA_Q8   = 0xFF (255) - stronger dehaze
  T_MIN      = 15 - lower min transmission
  grayscale mode = 2 (round-to-even)
"""

from pathlib import Path

# =============================================================================
# Constants (matching atm_light_coarse_tx testbench)
# =============================================================================
IMG_WIDTH  = 4
IMG_HEIGHT = 4
NUM_PIXELS = IMG_WIDTH * IMG_HEIGHT

A0       = 150
USE_DARK = 0
USE_SKY  = 1
T_SKY    = 255
OMEGA_Q8 = 0xFF   # 255 - stronger dehaze effect
T_MIN    = 15     # Lower minimum transmission for stronger dehaze

# =============================================================================
# Test Image (4x4 = 16 pixels)
# Designed to exercise: sky vs non-sky, various haze levels, tie-break in A
# Format: (R, G, B)
# =============================================================================
TEST_IMAGE = [
    (150, 160, 170),  # [00] dark=150, gray>150 -> sky
    (100, 120,  80),  # [01] dark=80,  gray<150 -> non-sky
    (200, 210, 220),  # [02] dark=200, highest dark_ch -> becomes A
    ( 50,  60,  45),  # [03] dark=45,  gray<150 -> non-sky
    (180, 190, 195),  # [04] dark=180, gray>150 -> sky
    ( 30,  40,  50),  # [05] dark=30,  gray<150 -> non-sky
    (160, 165, 170),  # [06] dark=160, gray>150 -> sky
    ( 70,  85,  90),  # [07] dark=70,  gray<150 -> non-sky
    (140, 148, 155),  # [08] dark=140, gray~146 -> non-sky (borderline)
    (152, 158, 165),  # [09] dark=152, gray>150 -> sky
    ( 10,  20,  15),  # [10] dark=10,  gray<150 -> non-sky
    (200, 200, 200),  # [11] dark=200, tie with [02], lower intensity -> loses
    (110, 115, 120),  # [12] dark=110, gray<150 -> non-sky
    (170, 175, 180),  # [13] dark=170, gray>150 -> sky
    (  0,   0,   0),  # [14] dark=0,   gray=0   -> non-sky
    ( 90,  95, 100),  # [15] dark=90,  gray<150 -> non-sky
]


# =============================================================================
# Algorithm Functions (matching RTL bit-exact)
# =============================================================================

def compute_dark_channel(r, g, b):
    """min(R, G, B) -- dark_channel.sv src_min"""
    return min(r, g, b)


def compute_grayscale(r, g, b, mode=2):
    """
    Grayscale conversion matching grayscale.sv (mode=2: round-to-even).
    gray = (5*R + 9*G + 2*B) / 16 with rounding.
    """
    sum_val = 5 * r + 9 * g + 2 * b
    integer_part = (sum_val >> 4) & 0xFF
    fraction_part = sum_val & 0xF

    if mode == 0:  # round up
        return (integer_part + 1) & 0xFF if fraction_part > 0 else integer_part
    elif mode == 1:  # round down
        return integer_part
    else:  # mode 2: round to even
        if fraction_part > 8:
            return (integer_part + 1) & 0xFF
        elif fraction_part < 8:
            return integer_part
        else:  # fraction == 8: round to nearest even
            if (integer_part & 1) == 0:
                return integer_part
            else:
                return (integer_part + 1) & 0xFF


def atmospheric_light_frame(pixels):
    """
    Scan all pixels, find pixel with max dark_ch.
    Tie-break: higher intensity (R+G+B).
    Returns (A_R, A_G, A_B).
    Matches atmospheric_light.sv frame_start -> valid stream -> frame_end.
    """
    max_dark = 0
    max_intensity = 0
    A_R, A_G, A_B = 0, 0, 0

    for r, g, b in pixels:
        dark = compute_dark_channel(r, g, b)
        intensity = r + g + b
        if dark > max_dark or (dark == max_dark and intensity > max_intensity):
            max_dark = dark
            max_intensity = intensity
            A_R, A_G, A_B = r, g, b

    return A_R, A_G, A_B


def sky_recognition_pixel(gray, dark_ch, A0=A0, use_dark=USE_DARK):
    """
    Sky detection: src_val = dark_ch if use_dark else gray.
    sky = 1 if src_val > A0 else 0.
    Matches sky_recognition.sv.
    """
    src_val = dark_ch if use_dark else gray
    return 1 if src_val > A0 else 0


def build_inv_lut_q16():
    """Reciprocal LUT: inv[i] = floor((255 << 16) / i). Matches invA_lut_q16.sv."""
    lut = [0] * 256
    lut[0] = 0xFFFFFF
    for i in range(1, 256):
        lut[i] = (255 << 16) // i
    return lut

INV_LUT = build_inv_lut_q16()


def norm_channel(pix, inv_q16):
    """
    Normalize: result = saturate((pix * inv_q16) >> 16, 8-bit).
    Matches norm_channel_q16.sv.
    """
    mul_q = pix * inv_q16
    q16 = (mul_q >> 16) & 0xFFFF
    return 0xFF if (q16 >> 8) != 0 else (q16 & 0xFF)


def omega_clamp(min_norm, omega_q8=OMEGA_Q8, t_min=T_MIN):
    """
    t = 255 - ((omega_q8 * min_norm) >> 8), clamped to t_min.
    Matches omega_clamp_t.sv.
    """
    x_scaled = (min_norm * omega_q8) >> 8
    t_raw = 255 - (x_scaled & 0xFF)
    return max(t_raw, t_min) & 0xFF


def estimate_transmission_pixel(r, g, b, sky, A_R, A_G, A_B,
                                 use_sky=USE_SKY, t_sky=T_SKY):
    """
    Compute coarse transmission for one pixel.
    If use_sky and sky, output t_sky.
    Else: normalize -> min3 -> omega_clamp.
    Matches estimate_transmission.sv (ENABLE_SPATIAL_FILTER=0).
    """
    if use_sky and sky:
        return t_sky

    inv_r = INV_LUT[A_R]
    inv_g = INV_LUT[A_G]
    inv_b = INV_LUT[A_B]

    n_r = norm_channel(r, inv_r)
    n_g = norm_channel(g, inv_g)
    n_b = norm_channel(b, inv_b)

    min_n = min(n_r, n_g, n_b)
    return omega_clamp(min_n)


# =============================================================================
# Full Pipeline Computation
# =============================================================================

def run_pipeline(pixels):
    """
    Run the complete purple block pipeline.
    Returns dict with all intermediate + final results.
    """
    N = len(pixels)
    results = {
        'pixels':    pixels,
        'dark_ch':   [],
        'gray':      [],
        'A_R': 0, 'A_G': 0, 'A_B': 0,
        'sky':       [],
        'tx':        [],
    }

    # --- Pass 1: dark_channel + atmospheric_light ---
    for r, g, b in pixels:
        results['dark_ch'].append(compute_dark_channel(r, g, b))
        results['gray'].append(compute_grayscale(r, g, b))

    A_R, A_G, A_B = atmospheric_light_frame(pixels)
    results['A_R'] = A_R
    results['A_G'] = A_G
    results['A_B'] = A_B

    # --- Pass 2: sky_recognition + estimate_transmission ---
    for i, (r, g, b) in enumerate(pixels):
        dark = results['dark_ch'][i]
        gray = results['gray'][i]
        sky  = sky_recognition_pixel(gray, dark)
        tx   = estimate_transmission_pixel(r, g, b, sky, A_R, A_G, A_B)
        results['sky'].append(sky)
        results['tx'].append(tx)

    return results


# =============================================================================
# File Generation
# =============================================================================

def generate_files():
    base_dir   = Path(__file__).parent.parent
    pat_dir    = base_dir / "09_pattern"
    gold_dir   = base_dir / "07_golden_output"
    pat_dir.mkdir(parents=True, exist_ok=True)
    gold_dir.mkdir(parents=True, exist_ok=True)

    # Run pipeline
    res = run_pipeline(TEST_IMAGE)

    # ---- Input pattern: RGB (24-bit hex) ----
    with open(pat_dir / "pattern_purple_rgb.hex", 'w') as f:
        f.write("// Purple block integration RGB input\n")
        f.write("// Format: BBGGRR (24-bit)\n")
        for i, (r, g, b) in enumerate(TEST_IMAGE):
            val = (b << 16) | (g << 8) | r
            f.write(f"{val:06X}  // [{i:02d}] R={r:3d} G={g:3d} B={b:3d}\n")

    # ---- Golden: atmospheric light (single line) ----
    with open(gold_dir / "golden_purple_A.hex", 'w') as f:
        f.write("// Atmospheric Light: BB_GG_RR\n")
        A_val = (res['A_B'] << 16) | (res['A_G'] << 8) | res['A_R']
        f.write(f"{A_val:06X}  // A_R={res['A_R']} A_G={res['A_G']} A_B={res['A_B']}\n")

    # ---- Golden: dark channel per pixel ----
    with open(gold_dir / "golden_purple_dark_ch.hex", 'w') as f:
        f.write("// Dark channel per pixel (8-bit)\n")
        for i, dc in enumerate(res['dark_ch']):
            f.write(f"{dc:02X}  // [{i:02d}] dark={dc:3d}\n")

    # ---- Golden: gray per pixel ----
    with open(gold_dir / "golden_purple_gray.hex", 'w') as f:
        f.write("// Grayscale per pixel (8-bit, mode=round-to-even)\n")
        for i, g in enumerate(res['gray']):
            f.write(f"{g:02X}  // [{i:02d}] gray={g:3d}\n")

    # ---- Golden: sky flag per pixel ----
    with open(gold_dir / "golden_purple_sky.hex", 'w') as f:
        f.write("// Sky flag per pixel (1-bit)\n")
        for i, s in enumerate(res['sky']):
            f.write(f"{s:01X}  // [{i:02d}] sky={s}\n")

    # ---- Golden: transmission per pixel (final output) ----
    with open(gold_dir / "golden_purple_tx.hex", 'w') as f:
        f.write("// Transmission per pixel (8-bit)\n")
        f.write(f"// A=({res['A_R']},{res['A_G']},{res['A_B']})\n")
        f.write(f"// OMEGA=0x{OMEGA_Q8:02X}, T_MIN={T_MIN}\n")
        f.write(f"// use_sky={USE_SKY}, t_sky={T_SKY}\n")
        for i, t in enumerate(res['tx']):
            f.write(f"{t:02X}  // [{i:02d}] tx={t:3d} sky={res['sky'][i]}\n")

    # ---- Detailed report ----
    rpt = gold_dir / "purple_integration_report.txt"
    with open(rpt, 'w') as f:
        f.write("=" * 72 + "\n")
        f.write("PURPLE BLOCK INTEGRATION REPORT\n")
        f.write("=" * 72 + "\n")
        f.write(f"Image: {IMG_WIDTH}x{IMG_HEIGHT} = {NUM_PIXELS} pixels\n")
        f.write(f"A0={A0}, use_dark={USE_DARK}, use_sky={USE_SKY}, "
                f"t_sky={T_SKY}\n")
        f.write(f"OMEGA_Q8=0x{OMEGA_Q8:02X}, T_MIN={T_MIN}\n")
        f.write(f"Atmospheric Light: A_R={res['A_R']}, A_G={res['A_G']}, "
                f"A_B={res['A_B']}\n")
        f.write("=" * 72 + "\n\n")

        for i, (r, g, b) in enumerate(TEST_IMAGE):
            dc   = res['dark_ch'][i]
            gray = res['gray'][i]
            sky  = res['sky'][i]
            tx   = res['tx'][i]
            f.write(f"[{i:02d}] RGB=({r:3d},{g:3d},{b:3d})  "
                    f"dark={dc:3d}  gray={gray:3d}  "
                    f"sky={sky}  tx={tx:3d} (0x{tx:02X})\n")

    print("=" * 72)
    print("PURPLE BLOCK INTEGRATION - GOLDEN FILES GENERATED")
    print("=" * 72)
    print(f"Atmospheric Light: A_R={res['A_R']}, A_G={res['A_G']}, "
          f"A_B={res['A_B']}")
    print("-" * 72)
    for i, (r, g, b) in enumerate(TEST_IMAGE):
        dc   = res['dark_ch'][i]
        gray = res['gray'][i]
        sky  = res['sky'][i]
        tx   = res['tx'][i]
        sky_str = "SKY " if sky else "    "
        print(f"  [{i:02d}] RGB=({r:3d},{g:3d},{b:3d}) "
              f"dark={dc:3d} gray={gray:3d} {sky_str} tx={tx:3d}")
    print("=" * 72)


if __name__ == "__main__":
    generate_files()
