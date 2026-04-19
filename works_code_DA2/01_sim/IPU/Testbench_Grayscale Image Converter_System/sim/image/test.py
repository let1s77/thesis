from PIL import Image
import os

# Get the directory where this script is located
script_dir = os.path.dirname(os.path.abspath(__file__))

size = 128
img_path = os.path.join(script_dir, 'Failure-on-aerialtop-and-cityscapebottom-Left-to-Right-Input-image-dehazed-image.png')
output_path = os.path.join(script_dir, f'test_{size}.bmp')

img = Image.open(img_path)
img = img.resize((size, size))
img.save(output_path, 'BMP')
img.close()

print(f"Successfully converted {img_path} to {output_path}")

