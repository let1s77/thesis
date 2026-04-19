"""
Dark Channel Prior - Python Reference Model
=============================================
Algorithm: Dark Channel J^dark(x) = min_c∈{R,G,B}(min_y∈Ω(x)(J^c(y)))

For single pixel: dark_channel = min(R, G, B)

Reference: "Single Image Haze Removal Using Dark Channel Prior" - He et al., CVPR 2009
"""

import numpy as np
from pathlib import Path

# =============================================================================
# Core Algorithm
# =============================================================================
def compute_dark_channel_pixel(r: int, g: int, b: int) -> int:
    """
    Compute dark channel for single pixel.
    
    Args:
        r, g, b: RGB values (0-255)
    
    Returns:
        dark_channel: min(R, G, B)
    """
    return min(r, g, b)


def compute_dark_channel_image(img: np.ndarray, patch_size: int = 15) -> np.ndarray:
    """
    Compute dark channel for full image with local patch.
    
    Args:
        img: RGB image (H x W x 3), values 0-255
        patch_size: Local patch size (default 15x15)
    
    Returns:
        dark_channel: (H x W), values 0-255
    """
    # Min across RGB channels
    min_channel = np.min(img, axis=2).astype(np.float32)
    
    # Min filter with local patch
    h, w = min_channel.shape
    pad = patch_size // 2
    padded = np.pad(min_channel, pad, mode='edge')
    
    dark_channel = np.zeros_like(min_channel)
    for i in range(h):
        for j in range(w):
            dark_channel[i, j] = np.min(padded[i:i+patch_size, j:j+patch_size])
    
    return dark_channel.astype(np.uint8)


# =============================================================================
# Test Patterns  
# =============================================================================
TEST_PATTERNS = [
    # (R, G, B, description)
    (255, 255, 255, "White - No haze info"),
    (128, 128, 128, "Gray - Uniform"),
    (64, 64, 64, "Dark gray"),
    (0, 0, 0, "Black"),
    
    # Hazy scenes
    (240, 240, 116, "Light hazy sky"),
    (200, 210, 180, "Light atmospheric"),
    (150, 160, 140, "Medium haze"),
    (100, 110, 90, "Heavy haze"),
    (50, 55, 45, "Very heavy haze"),
    
    # Natural scenes
    (97, 204, 98, "Green vegetation"),
    (19, 72, 7, "Dark vegetation"),
    (181, 71, 16, "Brown/orange"),
    (142, 244, 154, "Teal sky"),
    (226, 208, 124, "Sunset"),
    
    # Pure colors
    (255, 0, 0, "Pure red"),
    (0, 255, 0, "Pure green"),
    (0, 0, 255, "Pure blue"),
    (255, 255, 0, "Yellow"),
    (0, 255, 255, "Cyan"),
    (255, 0, 255, "Magenta"),
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
    
    pattern_file = pattern_dir / "pattern_dark_channel.hex"
    golden_file = golden_dir / "golden_dark_channel.hex"
    report_file = golden_dir / "dark_channel_report.txt"
    
    print("=" * 70)
    print("DARK CHANNEL PRIOR - GOLDEN FILE GENERATION")
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
        f.write("// Golden Dark Channel Output (8-bit)\n")
        f.write("// Dark Channel = min(R, G, B)\n\n")
        
        for i, (r, g, b, desc) in enumerate(TEST_PATTERNS):
            dark = compute_dark_channel_pixel(r, g, b)
            f.write(f"// [{i:02d}] RGB=({r:3d},{g:3d},{b:3d}) - {desc}\n")
            f.write(f"{dark:02X}  // dark={dark:3d}\n\n")
    
    # Write detailed report
    with open(report_file, 'w') as f:
        f.write("=" * 70 + "\n")
        f.write("DARK CHANNEL PRIOR REPORT\n")
        f.write("=" * 70 + "\n")
        f.write("Algorithm: dark_channel = min(R, G, B)\n")
        f.write("=" * 70 + "\n\n")
        
        for i, (r, g, b, desc) in enumerate(TEST_PATTERNS):
            dark = compute_dark_channel_pixel(r, g, b)
            max_rgb = max(r, g, b)
            haze_indicator = max_rgb - dark
            
            f.write(f"[{i:02d}] {desc}\n")
            f.write(f"     RGB:    ({r:3d}, {g:3d}, {b:3d})\n")
            f.write(f"     Dark:   {dark:3d} (0x{dark:02X})\n")
            f.write(f"     Max:    {max_rgb:3d}\n")
            f.write(f"     Spread: {haze_indicator:3d} (lower = more haze)\n\n")
    
    print(f"[OK] {pattern_file.name}")
    print(f"[OK] {golden_file.name}")
    print(f"[OK] {report_file.name}")
    print("=" * 70)
    print(">>> DARK CHANNEL FILES GENERATED SUCCESSFULLY! <<<")
    print("=" * 70)


# =============================================================================
# Demo
# =============================================================================
def demo():
    """Demonstrate dark channel computation."""
    print("\n" + "=" * 70)
    print("DEMO: Dark Channel Prior")
    print("=" * 70)
    
    for r, g, b, desc in TEST_PATTERNS[:8]:
        dark = compute_dark_channel_pixel(r, g, b)
        print(f"{desc:20s}: RGB=({r:3d},{g:3d},{b:3d}) -> Dark={dark:3d}")


if __name__ == "__main__":
    generate_files()
    demo()
