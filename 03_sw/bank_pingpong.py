"""
Bank Ping-Pong Stream - Python Reference Model
================================================
Test strategy:
    Phase 1: Write N pixels into BANK (via i_wr_valid stream)
    Phase 2: Swap banks
    Phase 3: Read back N pixels (via i_rd_en stream)
    Compare: read data must match written data in order

Also verifies:
    - frame_linear_counter: row/col/boundary flags
    - Ping-pong swap: write to one bank, read from the other

Uses small image (4x4 = 16 pixels) for fast simulation.
"""

from pathlib import Path

# =============================================================================
# Constants (matching testbench)
# =============================================================================
IMG_WIDTH  = 4
IMG_HEIGHT = 4
NUM_PIXELS = IMG_WIDTH * IMG_HEIGHT  # 16


# =============================================================================
# Test Pattern Generation
# =============================================================================
def generate_write_data():
    """Generate deterministic 8-bit write data for each pixel address."""
    data = []
    for i in range(NUM_PIXELS):
        # Use a pattern that's easy to verify: (addr * 13 + 7) mod 256
        val = ((i * 13) + 7) & 0xFF
        data.append(val)
    return data


def compute_position_info(addr):
    """Compute row, col, boundary flags for a given linear address."""
    row = addr // IMG_WIDTH
    col = addr % IMG_WIDTH

    at_top    = 1 if row == 0 else 0
    at_bottom = 1 if row == IMG_HEIGHT - 1 else 0
    at_left   = 1 if col == 0 else 0
    at_right  = 1 if col == IMG_WIDTH - 1 else 0

    return row, col, at_top, at_bottom, at_left, at_right


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

    wr_data_file = pattern_dir / "pattern_bank_wr_data.hex"
    golden_rd    = golden_dir  / "golden_bank_rd_data.hex"
    golden_pos   = golden_dir  / "golden_bank_position.txt"
    report_file  = golden_dir  / "bank_pingpong_report.txt"

    write_data = generate_write_data()

    print("=" * 70)
    print("BANK PING-PONG STREAM - GOLDEN FILE GENERATION")
    print("=" * 70)
    print(f"Image size: {IMG_WIDTH}x{IMG_HEIGHT} = {NUM_PIXELS} pixels")
    print(f"Write data: {wr_data_file}")
    print(f"Golden read: {golden_rd}")
    print("-" * 70)

    # Write data pattern file (this is what TB writes, then expects to read back)
    with open(wr_data_file, 'w') as f:
        f.write(f"// Bank write data pattern (8-bit), {NUM_PIXELS} entries\n")
        for i, val in enumerate(write_data):
            row, col, at_top, at_bottom, at_left, at_right = compute_position_info(i)
            f.write(f"{val:02X}  // [{i:02d}] row={row} col={col}\n")

    # Golden read-back file (same as write data — ping-pong should preserve order)
    with open(golden_rd, 'w') as f:
        f.write(f"// Golden bank readback (8-bit), {NUM_PIXELS} entries\n")
        f.write("// Must match write data after swap\n")
        for i, val in enumerate(write_data):
            f.write(f"{val:02X}  // [{i:02d}]\n")

    # Position info golden (for TB to check boundary flags)
    with open(golden_pos, 'w') as f:
        f.write(f"// Position golden: addr row col at_top at_bottom at_left at_right\n")
        f.write(f"// IMG_WIDTH={IMG_WIDTH}, IMG_HEIGHT={IMG_HEIGHT}\n")
        for i in range(NUM_PIXELS):
            row, col, at_top, at_bottom, at_left, at_right = compute_position_info(i)
            f.write(f"{i:02d} {row} {col} {at_top} {at_bottom} {at_left} {at_right}\n")

    # Report
    with open(report_file, 'w') as f:
        f.write("=" * 70 + "\n")
        f.write("BANK PING-PONG STREAM REPORT\n")
        f.write("=" * 70 + "\n")
        f.write(f"Image: {IMG_WIDTH}x{IMG_HEIGHT} = {NUM_PIXELS} pixels\n")
        f.write(f"DATA_WIDTH: 8, ADDR_WIDTH: {(NUM_PIXELS-1).bit_length()}\n")
        f.write("=" * 70 + "\n\n")

        f.write("Write data -> Swap -> Read back (must match)\n\n")
        for i, val in enumerate(write_data):
            row, col, at_top, at_bottom, at_left, at_right = compute_position_info(i)
            flags = []
            if at_top:    flags.append("TOP")
            if at_bottom: flags.append("BOT")
            if at_left:   flags.append("LEFT")
            if at_right:  flags.append("RIGHT")
            flag_str = ",".join(flags) if flags else "-"
            f.write(f"  [{i:02d}] data=0x{val:02X} ({val:3d})  "
                    f"row={row} col={col}  flags={flag_str}\n")

    print(f"[OK] {wr_data_file.name}")
    print(f"[OK] {golden_rd.name}")
    print(f"[OK] {golden_pos.name}")
    print(f"[OK] {report_file.name}")
    print("=" * 70)
    print(">>> BANK PING-PONG FILES GENERATED SUCCESSFULLY! <<<")
    print("=" * 70)


if __name__ == "__main__":
    generate_files()
