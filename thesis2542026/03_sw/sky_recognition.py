"""
Sky Recognition - Python Reference Model
==========================================
Algorithm:
    src_val = dark_ch if use_dark else gray
    sky     = 1 if src_val > A0 else 0
    sky_bw  = 0xFF if sky else 0x00

Hardware Parameters (from testbench):
    - A0 = 150 (threshold)
    - use_dark = 0 => compare gray value
    - use_dark = 1 => compare dark_ch value

Latency: 1 cycle (registered output)
"""

from pathlib import Path


# =============================================================================
# Constants (matching testbench)
# =============================================================================
A0 = 150
USE_DARK = 0  # default mode


# =============================================================================
# Core Algorithm
# =============================================================================
def sky_recognition_pixel(gray: int, dark_ch: int, A0: int = A0,
                          use_dark: int = USE_DARK) -> tuple[int, int]:
    """
    Determine if a pixel is sky or non-sky.

    Args:
        gray:     8-bit grayscale value (0-255)
        dark_ch:  8-bit dark channel value (0-255)
        A0:       8-bit recognition threshold
        use_dark: 0 = compare gray, 1 = compare dark_ch

    Returns:
        (sky, sky_bw): sky flag (0/1) and sky_bw (0x00/0xFF)
    """
    src_val = dark_ch if use_dark else gray
    sky = 1 if src_val > A0 else 0
    sky_bw = 0xFF if sky else 0x00
    return sky, sky_bw


# =============================================================================
# Test Patterns
# =============================================================================
# (gray, dark_ch, use_dark, A0, description)
TEST_PATTERNS = [
    # --- use_dark=0: compare gray ---
    # Boundary around A0=150
    (  0,   0, 0, 150, "Black - gray=0 < A0"),
    (149,  50, 0, 150, "gray=149, just below A0"),
    (150,  80, 0, 150, "gray=150, equal A0 (not >)"),
    (151, 100, 0, 150, "gray=151, just above A0 => sky"),
    (255, 200, 0, 150, "White - gray=255 >> A0 => sky"),

    # Various gray levels
    ( 50,  30, 0, 150, "Dark pixel - non-sky"),
    (100,  60, 0, 150, "Medium dark - non-sky"),
    (180, 120, 0, 150, "Bright - sky"),
    (200, 160, 0, 150, "Very bright - sky"),
    (128, 100, 0, 150, "Mid gray - non-sky"),

    # --- use_dark=1: compare dark_ch ---
    # Boundary around A0=150
    (200,   0, 1, 150, "dark_ch=0 << A0 - non-sky"),
    (100, 149, 1, 150, "dark_ch=149, just below A0"),
    (180, 150, 1, 150, "dark_ch=150, equal A0 (not >)"),
    (220, 151, 1, 150, "dark_ch=151, just above => sky"),
    ( 50, 255, 1, 150, "dark_ch=255 >> A0 => sky"),

    # Various dark_ch levels
    (200,  80, 1, 150, "dark_ch=80 - non-sky"),
    (180, 130, 1, 150, "dark_ch=130 - non-sky"),
    (160, 180, 1, 150, "dark_ch=180 - sky"),
    (140, 200, 1, 150, "dark_ch=200 - sky"),
    (120, 100, 1, 150, "dark_ch=100 - non-sky"),
]


# =============================================================================
# File Generation
# =============================================================================
def generate_files():
    """Generate pattern and golden output files."""
    base_dir = Path(__file__).parent.parent
    pattern_dir = base_dir / "09_pattern"
    golden_dir = base_dir / "07_golden_output"

    pattern_dir.mkdir(parents=True, exist_ok=True)
    golden_dir.mkdir(parents=True, exist_ok=True)

    gray_file     = pattern_dir / "pattern_sky_gray.hex"
    darkch_file   = pattern_dir / "pattern_sky_darkch.hex"
    usedark_file  = pattern_dir / "pattern_sky_usedark.hex"
    a0_file       = pattern_dir / "pattern_sky_a0.hex"
    golden_sky    = golden_dir  / "golden_sky_recognition.hex"
    golden_skybw  = golden_dir  / "golden_sky_bw.hex"
    report_file   = golden_dir  / "sky_recognition_report.txt"

    print("=" * 70)
    print("SKY RECOGNITION - GOLDEN FILE GENERATION")
    print("=" * 70)
    print(f"Patterns: {len(TEST_PATTERNS)}")
    print(f"Pattern gray:     {gray_file}")
    print(f"Pattern dark_ch:  {darkch_file}")
    print(f"Pattern use_dark: {usedark_file}")
    print(f"Pattern A0:       {a0_file}")
    print(f"Golden sky:       {golden_sky}")
    print(f"Golden sky_bw:    {golden_skybw}")
    print("-" * 70)

    with open(gray_file, 'w') as fg, \
         open(darkch_file, 'w') as fd, \
         open(usedark_file, 'w') as fu, \
         open(a0_file, 'w') as fa, \
         open(golden_sky, 'w') as gs, \
         open(golden_skybw, 'w') as gb:

        fg.write("// Gray input (8-bit)\n")
        fd.write("// Dark channel input (8-bit)\n")
        fu.write("// use_dark flag (1-bit binary)\n")
        fa.write("// A0 threshold (8-bit)\n")
        gs.write("// Golden sky output (1-bit binary)\n")
        gb.write("// Golden sky_bw output (8-bit)\n")

        for i, (gray, dark_ch, use_dark, a0, desc) in enumerate(TEST_PATTERNS):
            sky, sky_bw = sky_recognition_pixel(gray, dark_ch, a0, use_dark)

            fg.write(f"{gray:02X}  // [{i:02d}] {desc}\n")
            fd.write(f"{dark_ch:02X}  // [{i:02d}] {desc}\n")
            fu.write(f"{use_dark:01b}  // [{i:02d}] {desc}\n")
            fa.write(f"{a0:02X}  // [{i:02d}] {desc}\n")
            gs.write(f"{sky:01b}  // [{i:02d}] {desc}\n")
            gb.write(f"{sky_bw:02X}  // [{i:02d}] {desc}\n")

    # Write report
    with open(report_file, 'w') as f:
        f.write("=" * 70 + "\n")
        f.write("SKY RECOGNITION REPORT\n")
        f.write("=" * 70 + "\n")
        f.write("Algorithm: src_val = dark_ch if use_dark else gray\n")
        f.write("           sky = 1 if src_val > A0 else 0\n")
        f.write("=" * 70 + "\n\n")

        for i, (gray, dark_ch, use_dark, a0, desc) in enumerate(TEST_PATTERNS):
            sky, sky_bw = sky_recognition_pixel(gray, dark_ch, a0, use_dark)
            src_val = dark_ch if use_dark else gray

            f.write(f"[{i:02d}] {desc}\n")
            f.write(f"     gray={gray:3d}, dark_ch={dark_ch:3d}, "
                    f"use_dark={use_dark}, A0={a0:3d}\n")
            f.write(f"     src_val={src_val:3d}, sky={sky}, sky_bw=0x{sky_bw:02X}\n\n")

    print(f"[OK] {gray_file.name}")
    print(f"[OK] {darkch_file.name}")
    print(f"[OK] {usedark_file.name}")
    print(f"[OK] {a0_file.name}")
    print(f"[OK] {golden_sky.name}")
    print(f"[OK] {golden_skybw.name}")
    print(f"[OK] {report_file.name}")
    print("=" * 70)
    print(">>> SKY RECOGNITION FILES GENERATED SUCCESSFULLY! <<<")
    print("=" * 70)


if __name__ == "__main__":
    generate_files()
