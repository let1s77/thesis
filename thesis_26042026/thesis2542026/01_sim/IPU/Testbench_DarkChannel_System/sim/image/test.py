from PIL import Image
import os
import numpy as np

# Get the directory where this script is located
script_dir = os.path.dirname(os.path.abspath(__file__))

size = 128

def convert_to_test_bmp(input_image, output_name='47_hazy.bmp'):
    """Convert any image to 128x128 BMP for testing"""
    img_path = os.path.join(script_dir, input_image)
    output_path = os.path.join(script_dir, output_name)
    
    img = Image.open(img_path)
    img = img.resize((size, size))
    img = img.convert('RGB')
    img.save(output_path, 'BMP')
    img.close()
    
    print(f"Successfully converted {img_path} to {output_path}")

def generate_dark_channel_golden(input_bmp, output_dat):
    """Generate golden data for dark channel (min(R,G,B) per pixel)"""
    img_path = os.path.join(script_dir, input_bmp)
    output_path = output_dat if os.path.isabs(output_dat) else os.path.join(script_dir, output_dat)
    
    img = Image.open(img_path)
    img = img.convert('RGB')
    img_array = np.array(img)
    
    # Dark channel = min(R, G, B) for each pixel
    dark_channel = np.min(img_array, axis=2)
    
    # Write to .dat file in hex format
    with open(output_path, 'w') as f:
        for row in dark_channel:
            for pixel in row:
                f.write(f"{pixel:02x}\n")
    
    print(f"Golden data saved to: {output_path}")
    
    # Also save as grayscale image for visualization
    dark_img_path = os.path.join(script_dir, f"dark_{os.path.basename(input_bmp)}")
    dark_img = Image.fromarray(dark_channel)
    dark_img.save(dark_img_path)
    print(f"Dark channel preview saved to: {dark_img_path}")

# Default behavior: convert mansion image
if __name__ == "__main__":
    img_path = os.path.join(script_dir, '47_hazy.png')
    output_path = os.path.join(script_dir, '47_hazy.bmp')
    
    if os.path.exists(img_path):
        img = Image.open(img_path)
        img = img.resize((size, size))
        img = img.convert('RGB')
        img.save(output_path, 'BMP')
        img.close()
        print(f"Successfully converted {img_path} to {output_path}")
    else:
        print(f"Default image not found: {img_path}")
        print("Available functions:")
        print("  convert_to_test_bmp(input_image, output_name)")
        print("  generate_dark_channel_golden(input_bmp, output_dat)")

