# gen_invA_lut_q16.py
# invA_q16 = floor((255<<16)/A), A=0 clamp -> 1

import os

def gen_lut():
    lut = []
    for A in range(256):
        denom = A if A != 0 else 1
        lut.append((255 << 16) // denom)
    return lut

def emit_sv(lut, per_line=8, file=None):
    print("  localparam logic [23:0] INV_A_Q16 [0:255] = '{", file=file)
    for i in range(0, 256, per_line):
        chunk = lut[i:i+per_line]
        parts = []
        for j, v in enumerate(chunk):
            idx = i + j
            comma = "," if idx != 255 else ""
            parts.append("24'd{}{}".format(v, comma))
        print("    " + " ".join(parts), file=file)
    print("  };", file=file)

if __name__ == "__main__":
    lut = gen_lut()
    
    # Get the directory of this script
    script_dir = os.path.dirname(os.path.abspath(__file__))
    # Go up one level and enter 09_pattern directory
    output_dir = os.path.join(os.path.dirname(script_dir), "09_pattern")
    
    # Create output directory if it doesn't exist
    os.makedirs(output_dir, exist_ok=True)
    
    # Define output file path
    output_file = os.path.join(output_dir, "invA_lut_q16.sv")
    
    # Write to file
    with open(output_file, 'w') as f:
        emit_sv(lut, file=f)
    
    # Print notification
    print(f"✓ DONE GENERATE LUT: {output_file}")
    print(f"✓ FOLDER output: {output_dir}")