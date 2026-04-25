"""
Grayscale Conversion - Python Reference Model
==============================================
Formula: Gray = 0.3125*R + 0.5625*G + 0.125*B (5/16*R + 9/16*G + 2/16*B)

Rounding Modes:
    - Mode 0: Round up
    - Mode 1: Round down  
    - Mode 2: Round to even (banker's rounding)

Author: Reference implementation for hardware verification
"""

import numpy as np
from pathlib import Path

# =============================================================================
# Constants
# =============================================================================
COEFF_R = 5 / 16  # 0.3125
COEFF_G = 9 / 16  # 0.5625
COEFF_B = 2 / 16  # 0.125

MODE_NAMES = ["Round Up", "Round Down", "Round to Even"]

# =============================================================================
# Core Algorithm
# =============================================================================
def rgb_to_gray_fixed_point(r: int, g: int, b: int, mode: int = 2) -> tuple[int, float]:
    """
    Convert RGB to grayscale using fixed-point Q8.4 arithmetic.
    
    Args:
        r, g, b: RGB values (0-255)
        mode: 0=round up, 1=round down, 2=round to even
    
    Returns:
        (gray_value, gray_float): Integer result and floating reference
    """
    # Q8.4 format: shift left 4 bits
    r_fp, g_fp, b_fp = r << 4, g << 4, b << 4
    
    # Apply coefficients: R*5/16, G*9/16, B*2/16
    mult_r = (r_fp >> 2) + (r_fp >> 4)  # R * (4+1)/16
    mult_g = (g_fp >> 1) + (g_fp >> 4)  # G * (8+1)/16
    mult_b = b_fp >> 3                   # B * 1/8
    
    sum_fp = mult_r + mult_g + mult_b
    
    # Extract integer [11:4] and fraction [3:0]
    integer_part = (sum_fp >> 4) & 0xFF
    fraction_part = sum_fp & 0x0F
    
    # Apply rounding
    if mode == 0:  # Round up
        gray = integer_part + 1 if fraction_part > 0 else integer_part
    elif mode == 1:  # Round down
        gray = integer_part
    else:  # Round to even
        if fraction_part > 8:
            gray = integer_part + 1
        elif fraction_part < 8:
            gray = integer_part
        else:
            gray = integer_part + 1 if integer_part & 1 else integer_part
    
    return gray & 0xFF, sum_fp / 16.0


# =============================================================================
# Test Patterns
# =============================================================================
TEST_PATTERNS = [
    (255, 255, 255, "White"),
    (0, 0, 0, "Black"),
    (255, 0, 0, "Pure Red"),
    (0, 255, 0, "Pure Green"),
    (0, 0, 255, "Pure Blue"),
    (128, 128, 128, "Gray 50%"),
    (64, 64, 64, "Gray 25%"),
    (192, 192, 192, "Gray 75%"),
    (255, 128, 64, "Warm tone"),
    (64, 128, 255, "Cool tone"),
    (240, 240, 116, "Light hazy"),
    (97, 204, 98, "Green vegetation"),
    (181, 71, 16, "Brown/orange"),
    (142, 244, 154, "Teal"),
    (226, 208, 124, "Sunset"),
    (100, 100, 100, "Mid gray"),
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
    
    pattern_file = pattern_dir / "pattern_grayscale.hex"
    golden_file = golden_dir / "golden_grayscale.hex"
    report_file = golden_dir / "grayscale_report.txt"
    
    print("=" * 70)
    print("GRAYSCALE CONVERSION - GOLDEN FILE GENERATION")
    print("=" * 70)
    print(f"Patterns: {len(TEST_PATTERNS)}")
    print(f"Pattern output: {pattern_file}")
    print(f"Golden output:  {golden_file}")
    print("-" * 70)
    
    # Write pattern file
    with open(pattern_file, 'w') as f:
        f.write("// RGB Pattern Input (24-bit: [23:16]=B, [15:8]=G, [7:0]=R)\n")
        for i, (r, g, b, desc) in enumerate(TEST_PATTERNS):
            rgb_hex = (b << 16) | (g << 8) | r
            f.write(f"{rgb_hex:06X}  // [{i:02d}] R={r:3d}, G={g:3d}, B={b:3d} - {desc}\n")
    
    # Write golden output file
    with open(golden_file, 'w') as f:
        f.write("// Golden Grayscale Output (8-bit)\n")
        f.write("// Format: 3 values per pattern (Mode 0, 1, 2)\n\n")
        
        for i, (r, g, b, desc) in enumerate(TEST_PATTERNS):
            f.write(f"// [{i:02d}] RGB=({r:3d},{g:3d},{b:3d}) - {desc}\n")
            for mode in range(3):
                gray, gray_f = rgb_to_gray_fixed_point(r, g, b, mode)
                f.write(f"{gray:02X}  // Mode{mode}: {gray:3d} (float={gray_f:.4f})\n")
            f.write("\n")
    
    # Write detailed report
    with open(report_file, 'w') as f:
        f.write("=" * 70 + "\n")
        f.write("GRAYSCALE CONVERSION REPORT\n")
        f.write("=" * 70 + "\n")
        f.write(f"Formula: Gray = {COEFF_R}*R + {COEFF_G}*G + {COEFF_B}*B\n")
        f.write(f"Format:  Q8.4 fixed-point\n")
        f.write("=" * 70 + "\n\n")
        
        for i, (r, g, b, desc) in enumerate(TEST_PATTERNS):
            f.write(f"[{i:02d}] {desc}: RGB=({r:3d},{g:3d},{b:3d})\n")
            for mode in range(3):
                gray, gray_f = rgb_to_gray_fixed_point(r, g, b, mode)
                f.write(f"     Mode {mode} ({MODE_NAMES[mode]:15s}): {gray:3d} (0x{gray:02X})\n")
            f.write("\n")
    
    print(f"[OK] {pattern_file.name}")
    print(f"[OK] {golden_file.name}")
    print(f"[OK] {report_file.name}")
    print("=" * 70)
    print(">>> GRAYSCALE FILES GENERATED SUCCESSFULLY! <<<")
    print("=" * 70)


# =============================================================================
# Demo
# =============================================================================
def demo():
    """Demonstrate grayscale conversion."""
    print("\n" + "=" * 70)
    print("DEMO: Grayscale Conversion")
    print("=" * 70)
    
    for r, g, b, desc in TEST_PATTERNS[:5]:
        print(f"\n{desc}: RGB=({r:3d},{g:3d},{b:3d})")
        for mode in range(3):
            gray, gray_f = rgb_to_gray_fixed_point(r, g, b, mode)
            print(f"  Mode {mode}: {gray:3d} ({gray_f:.4f})")


if __name__ == "__main__":
    generate_files()
    demo()
