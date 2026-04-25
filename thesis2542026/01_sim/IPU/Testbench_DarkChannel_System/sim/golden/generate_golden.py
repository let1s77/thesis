"""
Generate golden data for Dark Channel Prior verification.
This script creates .dat files containing expected dark channel values
for comparison in the SystemVerilog testbench.
"""

from PIL import Image
import numpy as np
import os

# Get the directory where this script is located
script_dir = os.path.dirname(os.path.abspath(__file__))
golden_dir = os.path.join(script_dir, '..', 'golden')

def compute_dark_channel(img_path, output_dat, window_size=1):
    """
    Compute the dark channel prior for an image.
    
    Args:
        img_path: Path to input BMP image
        output_dat: Path to output .dat file (hex format)
        window_size: Window size for spatial filter (1 = simple min(R,G,B))
    """
    img = Image.open(img_path)
    img = img.convert('RGB')
    img_array = np.array(img, dtype=np.uint8)
    
    # Compute min(R, G, B) for each pixel
    pixel_min = np.min(img_array, axis=2)
    
    if window_size > 1:
        # Apply spatial minimum filter with window_size x window_size
        from scipy.ndimage import minimum_filter
        dark_channel = minimum_filter(pixel_min, size=window_size)
    else:
        dark_channel = pixel_min
    
    # Write to .dat file in hex format (row by row)
    with open(output_dat, 'w') as f:
        for row in dark_channel:
            for pixel in row:
                f.write(f"{pixel:02x}\n")
    
    print(f"Golden data saved to: {output_dat}")
    
    # Save visualization
    vis_path = output_dat.replace('.dat', '.bmp')
    dark_img = Image.fromarray(dark_channel)
    dark_img.save(vis_path)
    print(f"Visualization saved to: {vis_path}")

def generate_all_golden():
    """Generate golden data for all test patterns."""
    
    image_dir = os.path.join(script_dir, '..', 'image')
    
    # Pattern 1: Tux
    tux_path = os.path.join(image_dir, 'Tux.bmp')
    if os.path.exists(tux_path):
        compute_dark_channel(
            tux_path, 
            os.path.join(golden_dir, 'G1', 'dark_Tux_Golden.dat')
        )
    
    # Pattern 2: Little-Mole
    lm_path = os.path.join(image_dir, 'Little-Mole.bmp')
    if os.path.exists(lm_path):
        compute_dark_channel(
            lm_path,
            os.path.join(golden_dir, 'G2', 'dark_LM_Golden.dat')
        )
    
    print("\nGolden data generation complete!")

if __name__ == "__main__":
    print("=== Dark Channel Golden Data Generator ===\n")
    
    # Check for test.bmp and generate golden for it
    test_path = os.path.join(script_dir, '..', 'image', 'test.bmp')
    if os.path.exists(test_path):
        print(f"Found test.bmp, generating golden data...")
        compute_dark_channel(
            test_path,
            os.path.join(script_dir, 'test_golden.dat')
        )
    
    # Generate all standard patterns
    generate_all_golden()
