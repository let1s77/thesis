"""
Estimate Transmission - Python Reference Model
================================================
Algorithm:
    1. Normalize each channel: norm_c = saturate((pixel_c * inv_A_c_q16) >> 16)
    2. Find minimum normalized channel: min_norm = min(norm_r, norm_g, norm_b)
    3. Apply omega: t = 255 - ((OMEGA_Q8 * min_norm) >> 8)
    4. Clamp to T_MIN: t = max(t, T_MIN)

Hardware Parameters (from testbench):
    - OMEGA_Q8 = 0xF3 (243) ~0.95 in Q0.8
    - T_MIN = 26
    - A_R = A_G = A_B = 200
    - ENABLE_SPATIAL_FILTER = 0 (simple mode)

Reference: "Single Image Haze Removal Using Dark Channel Prior" - He et al., CVPR 2009
"""

import numpy as np
from pathlib import Path

# Reuse dark_channel function for min(R,G,B) computation
from dark_channel import compute_dark_channel_pixel

# =============================================================================
# Constants (matching testbench)
# =============================================================================
OMEGA_Q8 = 0xF3  # 243 in Q0.8 format (~0.95)
T_MIN = 26
A_R = 200
A_G = 200
A_B = 200

# =============================================================================
# Reciprocal LUT (Q16 format)
# =============================================================================
def build_invA_lut_q16():
    """Generate reciprocal LUT: inv_A[i] = floor((255 << 16) / i)"""
    lut = [0] * 256
    lut[0] = 0xFFFFFF  # Max value for divide-by-zero
    for i in range(1, 256):
        lut[i] = (255 << 16) // i
    return lut

# Pre-compute LUT
INV_A_LUT = build_invA_lut_q16()

# =============================================================================
# Core Algorithm  
# =============================================================================
def norm_channel(pix: int, inv_A_q16: int) -> int:
    """
    Normalize channel using Q16 reciprocal.
    
    Args:
        pix: 8-bit pixel value (0-255)
        inv_A_q16: 24-bit Q16 reciprocal
    
    Returns:
        Normalized value, saturated to 255
    """
    mul_q = pix * inv_A_q16
    q16 = (mul_q >> 16) & 0xFFFF
    
    # Saturate if upper bits are non-zero
    return 0xFF if (q16 >> 8) != 0 else (q16 & 0xFF)


def omega_clamp_t(min_norm: int, omega_q8: int = OMEGA_Q8, t_min: int = T_MIN) -> int:
    """
    Apply omega scaling and clamp: t = 255 - ((omega_q8 * min_norm) >> 8)
    
    Args:
        min_norm: Minimum normalized channel value
        omega_q8: Omega parameter in Q0.8 (default 243)
        t_min: Minimum transmission threshold (default 26)
    
    Returns:
        Clamped transmission value
    """
    omega_mul = min_norm * omega_q8
    x_scaled = (omega_mul >> 8) & 0xFF
    
    t_raw = 255 - x_scaled
    
    # Clamp to t_min
    return max(t_raw, t_min) & 0xFF


def estimate_transmission_pixel(r: int, g: int, b: int, sky: int = 0,
                                 A_r: int = A_R, A_g: int = A_G, A_b: int = A_B) -> tuple[int, dict]:
    """
    Estimate transmission for a single pixel (hardware testing).
    
    Args:
        r, g, b: RGB values (0-255)
        sky: Sky flag (0 or 1)
        A_r, A_g, A_b: Atmospheric light per channel
    
    Returns:
        (t, debug_info): Transmission value and intermediate results
    """
    # Get reciprocal LUT values
    inv_r = INV_A_LUT[A_r]
    inv_g = INV_A_LUT[A_g]
    inv_b = INV_A_LUT[A_b]
    
    # Normalize each channel
    norm_r = norm_channel(r, inv_r)
    norm_g = norm_channel(g, inv_g)
    norm_b = norm_channel(b, inv_b)
    
    # Find minimum (can reuse compute_dark_channel_pixel for min operation)
    min_norm = min(norm_r, norm_g, norm_b)
    
    # Apply omega and clamp
    t = omega_clamp_t(min_norm)
    
    # Debug info
    debug = {
        'norm': (norm_r, norm_g, norm_b),
        'min_norm': min_norm,
        't': t
    }
    
    return t, debug


# =============================================================================
# Test Patterns
# =============================================================================
TEST_PATTERNS = [
    # (R, G, B, Sky, description)
    # Corner cases
    (0, 0, 0, 0, "Black - No haze"),
    (255, 255, 255, 0, "White - Max haze"),
    (255, 0, 0, 0, "Pure Red"),
    (0, 255, 0, 0, "Pure Green"),
    (0, 0, 255, 0, "Pure Blue"),
    
    # Gray levels
    (50, 50, 50, 0, "Dark gray"),
    (100, 100, 100, 0, "Medium gray"),
    (150, 150, 150, 0, "Light gray"),
    (200, 200, 200, 0, "Very light gray (same as A)"),
    (128, 128, 128, 0, "Mid gray"),
    
    # Hazy pixels (low contrast)
    (180, 190, 195, 0, "Light hazy blue-ish"),
    (170, 175, 180, 0, "Medium hazy"),
    (160, 165, 170, 0, "Slightly hazy"),
    (190, 195, 198, 1, "Very hazy - Sky"),
    (185, 190, 195, 1, "Hazy sky-like"),
    
    # Clear pixels (high contrast)
    (30, 50, 70, 0, "Dark blue-ish (good contrast)"),
    (80, 60, 40, 0, "Brown-ish"),
    (120, 90, 60, 0, "Warm tone"),
    (40, 80, 120, 0, "Cool tone"),
    (60, 130, 90, 0, "Green-ish nature"),
]


# =============================================================================
# File Generation
# =============================================================================
def generate_files():
    """Generate pattern and golden output files."""
    # Setup paths
    base_dir = Path(__file__).parent.parent
    pattern_dir = base_dir / "09_pattern"
    golden_dir = base_dir / "07_golden_output"
    
    pattern_dir.mkdir(parents=True, exist_ok=True)
    golden_dir.mkdir(parents=True, exist_ok=True)
    
    rgb_file = pattern_dir / "rgb.hex"
    sky_file = pattern_dir / "sky.hex"
    golden_file = golden_dir / "t_golden.hex"
    report_file = golden_dir / "estimate_transmission_report.txt"
    
    print("=" * 70)
    print("ESTIMATE TRANSMISSION - GOLDEN FILE GENERATION")
    print("=" * 70)
    print(f"Patterns: {len(TEST_PATTERNS)}")
    print(f"Parameters:")
    print(f"  A_R, A_G, A_B = {A_R}, {A_G}, {A_B}")
    print(f"  OMEGA_Q8 = 0x{OMEGA_Q8:02X} ({OMEGA_Q8}) ~= {OMEGA_Q8/256:.4f}")
    print(f"  T_MIN = {T_MIN}")
    print(f"Output files:")
    print(f"  RGB pattern:  {rgb_file}")
    print(f"  Sky pattern:  {sky_file}")
    print(f"  Golden:       {golden_file}")
    print(f"  Report:       {report_file}")
    print("-" * 70)
    
    # Write RGB pattern file
    with open(rgb_file, 'w') as f:
        f.write("// RGB Pattern Input (24-bit: [23:16]=B, [15:8]=G, [7:0]=R)\n")
        for i, (r, g, b, sky, desc) in enumerate(TEST_PATTERNS):
            rgb_hex = (b << 16) | (g << 8) | r
            f.write(f"{rgb_hex:06X}  // [{i:02d}] R={r:3d}, G={g:3d}, B={b:3d} - {desc}\n")
    
    # Write sky pattern file (binary format)
    with open(sky_file, 'w') as f:
        f.write("// Sky Flag Input (1-bit per pattern)\n")
        for i, (r, g, b, sky, desc) in enumerate(TEST_PATTERNS):
            f.write(f"{sky}  // [{i:02d}] {desc}\n")
    
    # Write golden output file
    with open(golden_file, 'w') as f:
        f.write("// Golden Transmission Output (8-bit)\n")
        f.write(f"// Parameters: A_RGB=({A_R},{A_G},{A_B}), OMEGA_Q8=0x{OMEGA_Q8:02X}, T_MIN={T_MIN}\n")
        f.write("// Algorithm: t = clamp(255 - ((OMEGA * min_norm) >> 8), T_MIN)\n\n")
        
        for i, (r, g, b, sky, desc) in enumerate(TEST_PATTERNS):
            t, debug = estimate_transmission_pixel(r, g, b, sky)
            f.write(f"// [{i:02d}] RGB=({r:3d},{g:3d},{b:3d}) - {desc}\n")
            f.write(f"{t:02X}  // t={t:3d}, min_norm={debug['min_norm']:3d}\n\n")
    
    # Write detailed report
    with open(report_file, 'w') as f:
        f.write("=" * 70 + "\n")
        f.write("ESTIMATE TRANSMISSION REPORT\n")
        f.write("=" * 70 + "\n")
        f.write("Algorithm:\n")
        f.write("  1. norm_c = saturate((pixel_c * inv_A_c) >> 16)\n")
        f.write("  2. min_norm = min(norm_r, norm_g, norm_b)\n")
        f.write(f"  3. t = 255 - ((OMEGA_Q8 * min_norm) >> 8)\n")
        f.write(f"  4. t = clamp(t, T_MIN)\n\n")
        f.write("Parameters:\n")
        f.write(f"  Atmospheric Light: A_R={A_R}, A_G={A_G}, A_B={A_B}\n")
        f.write(f"  OMEGA_Q8 = 0x{OMEGA_Q8:02X} ({OMEGA_Q8}) ~= {OMEGA_Q8/256:.4f}\n")
        f.write(f"  T_MIN = {T_MIN}\n")
        f.write("=" * 70 + "\n\n")
        
        for i, (r, g, b, sky, desc) in enumerate(TEST_PATTERNS):
            t, debug = estimate_transmission_pixel(r, g, b, sky)
            norm_r, norm_g, norm_b = debug['norm']
            
            f.write(f"[{i:02d}] {desc}\n")
            f.write(f"     RGB:       ({r:3d}, {g:3d}, {b:3d})\n")
            f.write(f"     Normalized: ({norm_r:3d}, {norm_g:3d}, {norm_b:3d})\n")
            f.write(f"     Min Norm:   {debug['min_norm']:3d}\n")
            f.write(f"     Trans (t):  {t:3d} (0x{t:02X})\n")
            f.write(f"     Sky:        {sky}\n\n")
    
    print("\n✓ Files generated successfully!")
    print(f"\nSummary:")
    print(f"  Total patterns: {len(TEST_PATTERNS)}")
    print(f"  RGB patterns written to: {rgb_file}")
    print(f"  Sky patterns written to: {sky_file}")
    print(f"  Golden output written to: {golden_file}")
    print(f"  Detailed report written to: {report_file}")


# =============================================================================
# Main
# =============================================================================
if __name__ == "__main__":
    generate_files()

