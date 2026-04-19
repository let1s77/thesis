import wave, struct, argparse

def read_wav_signed16_stereo(path):
    with wave.open(path, "rb") as w:
        ch = w.getnchannels()
        sw = w.getsampwidth()
        fs = w.getframerate()
        n  = w.getnframes()
        frames = w.readframes(n)
    if ch != 2:
        raise ValueError(f"Expected stereo (2 ch), got {ch}")
    if sw != 2:
        raise ValueError(f"Expected 16-bit, got {sw*8}-bit")
    # interleaved int16 LE: L0,R0,L1,R1,...
    ints = struct.unpack("<" + "h"*(len(frames)//2), frames)
    left  = ints[0::2]
    right = ints[1::2]
    return left, right, fs

def write_raw(path, s16_list):
    with open(path, "wb") as f:
        f.write(struct.pack("<" + "h"*len(s16_list), *s16_list))

def write_hex_lsb_first(path, s16_list):
    with open(path, "w") as f:
        # each sample -> 2 bytes (LSB first), spaced
        parts = []
        for s in s16_list:
            b = struct.pack("<h", s)
            parts.append(f"{b[0]:02x} {b[1]:02x}")
        f.write(" ".join(parts))

def write_hex_interleaved(path, left, right):
    with open(path, "w") as f:
        parts = []
        for L, R in zip(left, right):
            bl = struct.pack("<h", L)
            br = struct.pack("<h", R)
            # order = L then R, each LSB-first
            parts.append(f"{bl[0]:02x} {bl[1]:02x} {br[0]:02x} {br[1]:02x}")
        f.write(" ".join(parts))
###########################    FIX THE START ADDRESS      ###################################
def write_mif16(path, s16_list, start_addr=146130):
    with open(path, "w") as f:
        f.write(f"WIDTH=16;\nDEPTH={len(s16_list)};\n\nADDRESS_RADIX=UNS;\nDATA_RADIX=HEX;\n\nCONTENT BEGIN\n")
        for i, s in enumerate(s16_list):
            u = struct.unpack("<H", struct.pack("<h", s))[0]
            f.write(f"  {i + start_addr} : {u:04X};\n")
        f.write("END;\n")
###########################    FIX THE START ADDRESS      ###################################
def write_mif32_stereo(path, left, right, start_addr=146130):
    with open(path, "w") as f:
        depth = min(len(left), len(right))
        f.write(f"WIDTH=32;\nDEPTH={depth};\n\nADDRESS_RADIX=UNS;\nDATA_RADIX=HEX;\n\nCONTENT BEGIN\n")
        for i in range(depth):
            Lu = struct.unpack("<H", struct.pack("<h", left[i]))[0]
            Ru = struct.unpack("<H", struct.pack("<h", right[i]))[0]
            word = (Lu << 16) | Ru
            f.write(f"  {i + start_addr} : {word:08X};\n")
        f.write("END;\n")

def main():
    ap = argparse.ArgumentParser(description="Keep stereo: decode signed 16-bit PCM WAV (8 kHz) to FPGA-friendly stereo outputs.")
    ap.add_argument("wav", nargs="?", default="final.wav")
    ap.add_argument("--checkfs", type=int, default=8000, help="Warn if sample rate differs (default 8000)")
    ap.add_argument("--prefix", default="final_stereo", help="Output file prefix")
    args = ap.parse_args()

    left, right, fs = read_wav_signed16_stereo(args.wav)
    if fs != args.checkfs:
        print(f"[warn] WAV sample rate is {fs} Hz (expected {args.checkfs}). Make sure WM8731 is set accordingly.")

    # 1) Interleaved RAW (L,R,L,R,...) — same as WAV payload layout
    interleaved = [v for pair in zip(left, right) for v in pair]
    write_raw(f"{args.prefix}_interleaved.raw", interleaved)
    write_hex_interleaved(f"{args.prefix}_interleaved.txt", left, right)

    # 2) Per-channel RAW + HEX
    write_raw(f"{args.prefix}_left.raw", left)
    write_raw(f"{args.prefix}_right.raw", right)
    write_hex_lsb_first(f"{args.prefix}_left.txt", left)
    write_hex_lsb_first(f"{args.prefix}_right.txt", right)

    # 3) MIFs: separate 16-bit, and combined 32-bit (L:hi16 | R:lo16)
    write_mif16(f"{args.prefix}_left16.mif", left)
    write_mif16(f"{args.prefix}_right16.mif", right)
    write_mif32_stereo(f"{args.prefix}_stereo32.mif", left, right)

    print("Wrote:")
    print(f"  {args.prefix}_interleaved.raw  (L,R interleaved, int16 LE)")
    print(f"  {args.prefix}_interleaved.txt  (hex, LSB-first, L then R per frame)")
    print(f"  {args.prefix}_left.raw / {args.prefix}_right.raw")
    print(f"  {args.prefix}_left.txt / {args.prefix}_right.txt")
    print(f"  {args.prefix}_left16.mif / {args.prefix}_right16.mif")
    print(f"  {args.prefix}_stereo32.mif  (WIDTH=32, word = left<<16 | right)")
if __name__ == "__main__":
    main()
