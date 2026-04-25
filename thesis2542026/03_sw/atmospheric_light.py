"""
Atmospheric Light Estimation - Python Reference Model
======================================================
Algorithm:
    1. Find top 0.1% brightest pixels in dark channel
    2. Among those, select pixel with highest RGB intensity
    3. Return RGB values as atmospheric light A

For single pixel testing: If dark_value > threshold, use pixel as A

Reference: "Single Image Haze Removal Using Dark Channel Prior" - He et al., CVPR 2009
"""

import numpy as np
from pathlib import Path

# =============================================================================
# Constants
# =============================================================================
DARK_THRESHOLD = 128  # Threshold for atmospheric light estimation

# =============================================================================
# Core Algorithm
# =============================================================================
def estimate_atmospheric_light_pixel(r: int, g: int, b: int, dark_value: int) -> tuple[int, int, int]:
    """
    Estimate atmospheric light for single pixel (hardware testing).
    
    Args:
        r, g, b: RGB values (0-255)
        dark_value: Dark channel value (0-255)
    
    Returns:
        (A_R, A_G, A_B): Atmospheric light components
    """
    if dark_value > DARK_THRESHOLD:
        # Bright in dark channel = likely hazy region -> use as atmospheric light
        return r, g, b
    else:
        # Use max channel value as estimate
        max_val = max(r, g, b)
        return (
            max_val if r == max_val else r,
            max_val if g == max_val else g,
            max_val if b == max_val else b
        )


def estimate_atmospheric_light_image(img: np.ndarray, dark_channel: np.ndarray, 
                                      top_percent: float = 0.001) -> np.ndarray:
    """
    Estimate atmospheric light from full image.
    
    Args:
        img: RGB image (H x W x 3)
        dark_channel: Dark channel (H x W)
        top_percent: Top percentage of bright pixels (default 0.1%)
    
    Returns:
        A: Atmospheric light [A_R, A_G, A_B]
    """
    h, w, _ = img.shape
    num_top = max(1, int(h * w * top_percent))
    
    # Get indices of top bright pixels in dark channel
    indices = np.argsort(dark_channel.flatten())[-num_top:]
    y_coords, x_coords = indices // w, indices % w
    
    # Find pixel with maximum intensity
    max_intensity = 0
    A = np.zeros(3, dtype=np.uint8)
    
    for y, x in zip(y_coords, x_coords):
        intensity = int(img[y, x].sum())
        if intensity > max_intensity:
            max_intensity = intensity
            A = img[y, x].copy()
    
    return A


# =============================================================================
# Test Patterns
# =============================================================================
TEST_PATTERNS = [
    # (R, G, B, Dark, description)
    # High haze (bright dark channel)
    (255, 255, 255, 255, "Pure white - Max haze"),
    (240, 245, 250, 240, "Very bright sky"),
    (220, 230, 235, 220, "Bright hazy sky"),
    (200, 210, 215, 200, "Medium hazy"),
    (180, 190, 195, 180, "Light haze"),
    
    # Medium haze
    (160, 170, 175, 160, "Slight haze"),
    (128, 135, 140, 128, "Gray haze"),
    
    # Low haze (dark in dark channel)
    (100, 110, 115, 100, "Weak haze"),
    (80, 90, 95, 80, "Very weak haze"),
    (60, 70, 75, 60, "Minimal haze"),
    
    # Color-biased atmospheric light
    (255, 200, 180, 180, "Warm atmospheric"),
    (180, 200, 255, 180, "Cool atmospheric"),
    (255, 220, 200, 200, "Sunset light"),
    (200, 220, 255, 200, "Sky light"),
    
    # Edge cases
    (0, 0, 0, 0, "Black - No light"),
    (255, 0, 0, 0, "Pure red"),
    (0, 255, 0, 0, "Pure green"),
    (0, 0, 255, 0, "Pure blue"),
    
    # Typical scenarios
    (150, 160, 165, 150, "Typical hazy day"),
    (190, 200, 210, 190, "Dense fog"),
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
    
    pattern_file = pattern_dir / "pattern_atmospheric_light.hex"
    golden_file = golden_dir / "golden_atmospheric_light.hex"
    report_file = golden_dir / "atmospheric_light_report.txt"
    
    print("=" * 70)
    print("ATMOSPHERIC LIGHT - GOLDEN FILE GENERATION")
    print("=" * 70)
    print(f"Patterns: {len(TEST_PATTERNS)}")
    print(f"Pattern output: {pattern_file}")
    print(f"Golden output:  {golden_file}")
    print("-" * 70)
    
    # Write pattern file (RGB + Dark Channel = 32-bit)
    with open(pattern_file, 'w') as f:
        f.write("// Pattern: [31:24]=Dark, [23:16]=B, [15:8]=G, [7:0]=R\n")
        for i, (r, g, b, dark, desc) in enumerate(TEST_PATTERNS):
            combined = (dark << 24) | (b << 16) | (g << 8) | r
            f.write(f"{combined:08X}  // [{i:02d}] RGB=({r:3d},{g:3d},{b:3d}), D={dark:3d} - {desc}\n")
    
    # Write golden output file
    with open(golden_file, 'w') as f:
        f.write("// Golden Atmospheric Light Output (24-bit: [23:16]=A_B, [15:8]=A_G, [7:0]=A_R)\n\n")
        
        for i, (r, g, b, dark, desc) in enumerate(TEST_PATTERNS):
            A_R, A_G, A_B = estimate_atmospheric_light_pixel(r, g, b, dark)
            A_combined = (A_B << 16) | (A_G << 8) | A_R
            
            f.write(f"// [{i:02d}] RGB=({r:3d},{g:3d},{b:3d}), D={dark:3d} - {desc}\n")
            f.write(f"{A_combined:06X}  // A=({A_R:3d},{A_G:3d},{A_B:3d})\n\n")
    
    # Write detailed report
    with open(report_file, 'w') as f:
        f.write("=" * 70 + "\n")
        f.write("ATMOSPHERIC LIGHT ESTIMATION REPORT\n")
        f.write("=" * 70 + "\n")
        f.write(f"Threshold: {DARK_THRESHOLD}\n")
        f.write("Algorithm: dark > threshold -> A = RGB, else A based on max channel\n")
        f.write("=" * 70 + "\n\n")
        
        for i, (r, g, b, dark, desc) in enumerate(TEST_PATTERNS):
            A_R, A_G, A_B = estimate_atmospheric_light_pixel(r, g, b, dark)
            
            # Haze level classification
            if dark > 200:
                haze = "Very Heavy"
            elif dark > 150:
                haze = "Heavy"
            elif dark > 100:
                haze = "Medium"
            elif dark > 50:
                haze = "Light"
            else:
                haze = "Minimal"
            
            f.write(f"[{i:02d}] {desc}\n")
            f.write(f"     Input:  RGB=({r:3d},{g:3d},{b:3d}), Dark={dark:3d}\n")
            f.write(f"     Output: A=({A_R:3d},{A_G:3d},{A_B:3d})\n")
            f.write(f"     Haze:   {haze}\n\n")
    
    print(f"[OK] {pattern_file.name}")
    print(f"[OK] {golden_file.name}")
    print(f"[OK] {report_file.name}")
    print("=" * 70)
    print(">>> ATMOSPHERIC LIGHT FILES GENERATED SUCCESSFULLY! <<<")
    print("=" * 70)


# =============================================================================
# Demo
# =============================================================================
def demo():
    """Demonstrate atmospheric light estimation."""
    print("\n" + "=" * 70)
    print("DEMO: Atmospheric Light Estimation")
    print("=" * 70)
    
    for r, g, b, dark, desc in TEST_PATTERNS[:8]:
        A = estimate_atmospheric_light_pixel(r, g, b, dark)
        print(f"{desc:20s}: RGB=({r:3d},{g:3d},{b:3d}), D={dark:3d} -> A={A}")


if __name__ == "__main__":
    generate_files()
    demo()
