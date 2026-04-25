#!/usr/bin/env python3
"""
fpga_verify.py — Script 1: Verify FPGA với RFC 8439 Test Vector
================================================================
Gửi plaintext CỐ ĐỊNH (RFC 8439) → nhận CT/TAG → verify tự động.
Không cần nhập gì — chạy 1 lệnh là xong.

Cách dùng:
  python fpga_verify.py --port COM3 --demo aead
  python fpga_verify.py --port COM3 --demo chacha
  python fpga_verify.py --port COM3 --demo aead_dma
  python fpga_verify.py --selftest          (không cần FPGA)
  python fpga_verify.py --list-ports

Flow:
  ┌──────────┐    UART 115200    ┌──────────────┐
  │  PC      │ ──── 64 bytes ──→ │  FPGA        │
  │  (script)│ ←─ 64 or 80B ─── │  (demo_*.hex)│
  └──────────┘                   └──────────────┘

  demo chacha:    PC gửi 64B → FPGA trả 64B CT
  demo aead:      PC gửi 64B → FPGA trả 80B (64B CT + 16B TAG)
  demo aead_dma:  PC gửi 64B → FPGA trả 80B (64B CT + 16B TAG)
"""

import argparse
import os
import sys
import time
import struct

# Fix Windows console encoding
if sys.stdout.encoding and sys.stdout.encoding.lower() not in ('utf-8', 'utf8'):
    try:
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
        sys.stderr.reconfigure(encoding='utf-8', errors='replace')
    except AttributeError:
        pass

import datetime

try:
    import serial
except ImportError:
    serial = None

try:
    from colorama import Fore, Style, init as colorama_init
    colorama_init()
except ImportError:
    class Fore:
        GREEN = RED = YELLOW = CYAN = MAGENTA = WHITE = BLUE = RESET = ""
    class Style:
        BRIGHT = DIM = RESET_ALL = ""

# ============================================================
#  RFC 8439 Test Vectors (cố định, không thay đổi)
# ============================================================

# Plaintext: "Ladies and Gentlemen of the class of '99: If I could offer you o"
PLAINTEXT = bytes([
    0x4c, 0x61, 0x64, 0x69, 0x65, 0x73, 0x20, 0x61,
    0x6e, 0x64, 0x20, 0x47, 0x65, 0x6e, 0x74, 0x6c,
    0x65, 0x6d, 0x65, 0x6e, 0x20, 0x6f, 0x66, 0x20,
    0x74, 0x68, 0x65, 0x20, 0x63, 0x6c, 0x61, 0x73,
    0x73, 0x20, 0x6f, 0x66, 0x20, 0x27, 0x39, 0x39,
    0x3a, 0x20, 0x49, 0x66, 0x20, 0x49, 0x20, 0x63,
    0x6f, 0x75, 0x6c, 0x64, 0x20, 0x6f, 0x66, 0x66,
    0x65, 0x72, 0x20, 0x79, 0x6f, 0x75, 0x20, 0x6f,
])

# ChaCha20-only expected CT (RFC 8439 §2.4.2)
CHACHA20_EXPECTED_CT = bytes([
    0x6e, 0x2e, 0x35, 0x9a, 0x25, 0x68, 0xf9, 0x80,
    0x41, 0xba, 0x07, 0x28, 0xdd, 0x0d, 0x69, 0x81,
    0xe9, 0x7e, 0x7a, 0xec, 0x1d, 0x43, 0x60, 0xc2,
    0x0a, 0x27, 0xaf, 0xcc, 0xfd, 0x9f, 0xae, 0x0b,
    0xf9, 0x1b, 0x65, 0xc5, 0x52, 0x47, 0x33, 0xab,
    0x8f, 0x59, 0x3d, 0xab, 0xcd, 0x62, 0xb3, 0x57,
    0x16, 0x39, 0xd6, 0x24, 0xe6, 0x51, 0x52, 0xab,
    0x8f, 0x53, 0x0c, 0x35, 0x9f, 0x08, 0x61, 0xd8,
])

# AEAD expected CT (RFC 8439 §2.8.2, first 64 bytes)
AEAD_EXPECTED_CT = bytes([
    0xd3, 0x1a, 0x8d, 0x34, 0x64, 0x8e, 0x60, 0xdb,
    0x7b, 0x86, 0xaf, 0xbc, 0x53, 0xef, 0x7e, 0xc2,
    0xa4, 0xad, 0xed, 0x51, 0x29, 0x6e, 0x08, 0xfe,
    0xa9, 0xe2, 0xb5, 0xa7, 0x36, 0xee, 0x62, 0xd6,
    0x3d, 0xbe, 0xa4, 0x5e, 0x8c, 0xa9, 0x67, 0x12,
    0x82, 0xfa, 0xfb, 0x69, 0xda, 0x92, 0x72, 0x8b,
    0x1a, 0x71, 0xde, 0x0a, 0x9e, 0x06, 0x0b, 0x29,
    0x05, 0xd6, 0xa5, 0xb6, 0x7e, 0xcd, 0x3b, 0x36,
])

# AEAD expected TAG (verified by QuestaSim + Python crypto lib)
AEAD_EXPECTED_TAG = bytes([
    0x57, 0x72, 0x8d, 0x89, 0x81, 0x1f, 0x44, 0xe3,
    0x44, 0x9f, 0x0d, 0x1c, 0x25, 0xa3, 0xe9, 0x5e,
])

# ============================================================
#  Helper Functions
# ============================================================

# ============================================================
#  SoC / FPGA Metadata (shown in banner)
# ============================================================
SOC_INFO = {
    "Device"    : "Intel Cyclone V  5CSXFC6D6F31C6",
    "Board"     : "Terasic DE10-Standard",
    "Clock"     : "50 MHz",
    "CPU"       : "RISC-V RV32I, 5-stage pipeline",
    "Bus"       : "TileLink-UL (2 masters / 6 slaves)",
    "Crypto"    : "ChaCha20-Poly1305 HW accelerators",
    "DMA"       : "2-channel DMA controller",
    "Interface" : "UART 115200 baud",
}

# ============================================================
#  RFC 8439 Crypto Parameters (shown in verify header)
# ============================================================
RFC_PARAMS = {
    "aead": {
        "key"  : "80 81 82 ... 9e 9f  (32 bytes)",
        "nonce": "07 00 00 00  40 41 42 43  44 45 46 47  (12 bytes)",
        "aad"  : "50 51 52 53  c0 c1 c2 c3  c4 c5 c6 c7  (12 bytes)",
        "ref"  : "RFC 8439 Section 2.8.2",
    },
    "chacha": {
        "key"  : "00 01 02 ... 1e 1f  (32 bytes)",
        "nonce": "00 00 00 00  00 00 00 4a  00 00 00 00  (12 bytes)",
        "aad"  : "N/A (stream cipher only)",
        "ref"  : "RFC 8439 Section 2.4.2",
    },
}


# ============================================================
#  Helpers
# ============================================================
def _W(n=60):  return "═" * n
def _w(n=60):  return "─" * n

def hex_dump(data, cols=16, expected=None):
    """Color-highlighted hex dump. If expected given, marks mismatches red."""
    lines = []
    for i in range(0, len(data), cols):
        chunk  = data[i:i+cols]
        exp_ch = expected[i:i+cols] if expected else None
        parts  = []
        for j, b in enumerate(chunk):
            s = f"{b:02x}"
            if exp_ch is not None:
                if j < len(exp_ch) and b != exp_ch[j]:
                    s = f"{Fore.RED}{s}{Style.RESET_ALL}"
                else:
                    s = f"{Fore.GREEN}{s}{Style.RESET_ALL}"
            parts.append(s)
        h = " ".join(parts)
        # ascii sidebar (no color)
        a = "".join(chr(b) if 32 <= b < 127 else "." for b in chunk)
        lines.append(f"    {i:04x}:  {h}   {Style.DIM}{a}{Style.RESET_ALL}")
    return "\n".join(lines)


def compare_and_print(expected, actual, label):
    """Print comparison result with color, return (ok, error_count)."""
    if len(expected) != len(actual):
        print(f"  {Fore.RED}{label}: LENGTH MISMATCH — expected {len(expected)}, got {len(actual)}{Style.RESET_ALL}")
        return False, len(expected)
    errors = [(i, e, a) for i, (e, a) in enumerate(zip(expected, actual)) if e != a]
    ok = len(errors) == 0
    if ok:
        print(f"  {Fore.GREEN}✔  {label}: {len(expected)}/{len(expected)} bytes khớp đúng RFC 8439{Style.RESET_ALL}")
    else:
        print(f"  {Fore.RED}✘  {label}: {len(errors)}/{len(expected)} bytes SAI{Style.RESET_ALL}")
        for i, e, a in errors[:6]:
            print(f"     Byte[{i:3d}]: expected {e:02x}, got {a:02x}")
        if len(errors) > 6:
            print(f"     ... và {len(errors)-6} lỗi khác")
    return ok, len(errors)


def open_serial(port, baud=115200):
    try:
        ser = serial.Serial(
            port=port, baudrate=baud,
            bytesize=serial.EIGHTBITS, parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            timeout=5.0, write_timeout=5.0,
        )
        ser.reset_input_buffer()
        ser.reset_output_buffer()
        return ser
    except serial.SerialException as e:
        print(f"{Fore.RED}ERROR: Không mở được {port}: {e}{Style.RESET_ALL}")
        print(f"  → Kiểm tra: cổng COM đúng chưa? FPGA đã nạp chương trình chưa?")
        sys.exit(1)


# ============================================================
#  Core: Send → Receive → Verify
# ============================================================

def send_and_verify(ser, mode):
    """
    Gửi plaintext RFC 8439 → nhận response → verify vs expected.
    mode: "chacha" | "aead" | "aead_dma"
    """
    CLK_MHZ = 50.0  # FPGA clock frequency

    if mode == "chacha":
        exp_ct   = CHACHA20_EXPECTED_CT
        exp_tag  = None
        rx_len   = 64
        rfc_ref  = "RFC 8439 §2.4.2"
        label    = "ChaCha20 Stream Cipher"
        dma_note = ""
        pkey     = "chacha"
    else:
        exp_ct   = AEAD_EXPECTED_CT
        exp_tag  = AEAD_EXPECTED_TAG
        rx_len   = 80
        rfc_ref  = "RFC 8439 §2.8.2"
        dma_note = " + DMA" if mode == "aead_dma" else " (CPU-only)"
        label    = f"ChaCha20-Poly1305 AEAD{dma_note}"
        pkey     = "aead"

    ts = datetime.datetime.now().strftime("%Y-%m-%d  %H:%M:%S")
    params = RFC_PARAMS[pkey]

    # ── Header ─────────────────────────────────────────────────
    print(f"\n{Fore.CYAN}{_W()}{Style.RESET_ALL}")
    print(f"{Fore.CYAN}  {Style.BRIGHT}{label}{Style.RESET_ALL}")
    print(f"{Fore.CYAN}  Reference  : {rfc_ref}{Style.RESET_ALL}")
    print(f"{Fore.CYAN}  Timestamp  : {ts}{Style.RESET_ALL}")
    print(f"{Fore.CYAN}{_W()}{Style.RESET_ALL}")

    # ── Crypto Parameters ──────────────────────────────────────
    print(f"\n{Style.BRIGHT}  Test Vector Parameters:{Style.RESET_ALL}")
    print(f"    Key   : {params['key']}")
    print(f"    Nonce : {params['nonce']}")
    print(f"    AAD   : {params['aad']}")
    print(f"    PT    : 64 bytes  — \"Ladies and Gentlemen of the class of '99...\"")

    # ── TX ─────────────────────────────────────────────────────
    print(f"\n{Fore.YELLOW}  [TX] Gửi 64 bytes plaintext → FPGA qua UART 115200:{Style.RESET_ALL}")
    print(hex_dump(PLAINTEXT))

    ser.reset_input_buffer()
    t_start = time.perf_counter()

    for byte in PLAINTEXT:
        ser.write(bytes([byte]))
        time.sleep(0.001)

    ser.flush()
    print(f"  {Style.DIM}→ Đã gửi, đang chờ FPGA xử lý...{Style.RESET_ALL}")

    # ── RX ─────────────────────────────────────────────────────
    response = bytearray()
    deadline = time.perf_counter() + 10.0
    while len(response) < rx_len:
        chunk = ser.read(rx_len - len(response))
        if chunk:
            response.extend(chunk)
        if time.perf_counter() > deadline:
            break

    t_end    = time.perf_counter()
    elapsed  = (t_end - t_start) * 1000.0

    if len(response) < rx_len:
        print(f"\n{Fore.RED}  ✘  TIMEOUT: chỉ nhận {len(response)}/{rx_len} bytes sau 10 giây{Style.RESET_ALL}")
        print(f"     → FPGA đã nạp đúng firmware? Đã nhấn reset sau khi nạp?")
        return False

    ct  = bytes(response[:64])
    tag = bytes(response[64:]) if rx_len > 64 else None

    # ── Display RX ─────────────────────────────────────────────
    print(f"\n{Fore.GREEN}  [RX] Nhận {len(response)} bytes trong {elapsed:.1f} ms:{Style.RESET_ALL}")
    print(f"\n  Ciphertext ({len(ct)} bytes) — so sánh với RFC 8439 expected:")
    print(hex_dump(ct, expected=exp_ct))

    if tag:
        print(f"\n  Authentication Tag ({len(tag)} bytes) — so sánh với RFC 8439 expected:")
        print(hex_dump(tag, expected=exp_tag))

    # ── Verify ─────────────────────────────────────────────────
    print(f"\n{Style.BRIGHT}  Kết quả xác minh:{Style.RESET_ALL}")
    ct_ok,  _ = compare_and_print(exp_ct, ct, "Ciphertext (64B)")
    tag_ok = True
    if exp_tag and tag:
        tag_ok, _ = compare_and_print(exp_tag, tag, "Auth Tag   (16B)")

    # ── Timing ─────────────────────────────────────────────────
    uart_tx_ms  = 64  * 10 / 115200 * 1000           # TX byte time
    uart_rx_ms  = rx_len * 10 / 115200 * 1000         # RX byte time
    send_dly_ms = 64 * 1.0                            # 1 ms/byte safety delay
    comm_ms     = uart_tx_ms + uart_rx_ms + send_dly_ms
    crypto_ms   = max(0.0, elapsed - comm_ms)
    throughput  = (64 / 1024) / (crypto_ms / 1000) if crypto_ms > 0 else 0  # KB/s
    clk_cycles  = int(crypto_ms * CLK_MHZ * 1000)    # cycles at 50 MHz

    print(f"\n{Style.BRIGHT}  Hiệu năng:{Style.RESET_ALL}")
    print(f"    Tổng thời gian end-to-end   : {Fore.MAGENTA}{elapsed:8.2f} ms{Style.RESET_ALL}")
    print(f"    UART TX (64B @ 115200)      : {Fore.BLUE}{uart_tx_ms:8.2f} ms{Style.RESET_ALL}")
    print(f"    UART RX ({rx_len}B @ 115200)      : {Fore.BLUE}{uart_rx_ms:8.2f} ms{Style.RESET_ALL}")
    print(f"    Byte-delay (TX safety)      : {Fore.BLUE}{send_dly_ms:8.2f} ms{Style.RESET_ALL}")
    print(f"    Ước tính thời gian crypto   : {Fore.MAGENTA}{crypto_ms:8.2f} ms{Style.RESET_ALL}")
    print(f"    Clock cycles crypto (50MHz) : {Fore.MAGENTA}{clk_cycles:,} cycles{Style.RESET_ALL}")
    print(f"    Throughput (plaintext)      : {Fore.MAGENTA}{throughput:.2f} KB/s{Style.RESET_ALL}")

    # ── Final verdict ──────────────────────────────────────────
    print(f"\n{_W()}")
    if ct_ok and tag_ok:
        print(f"{Fore.GREEN}{Style.BRIGHT}"
              f"  ✔  PASS  —  Kết quả khớp 100% với {rfc_ref}"
              f"{Style.RESET_ALL}")
    else:
        print(f"{Fore.RED}{Style.BRIGHT}"
              f"  ✘  FAIL  —  Kết quả KHÔNG khớp {rfc_ref}"
              f"{Style.RESET_ALL}")
    print(_W())

    return ct_ok and tag_ok


# ============================================================
#  Selftest (không cần FPGA)
# ============================================================

class CryptoMockSerial:
    """
    Mô phỏng FPGA crypto engine.
    - Nhận PT bytes qua write() (giống FPGA nhận qua UART)
    - Khi đủ 64 bytes: tính ChaCha20/AEAD bằng Python crypto lib
    - Trả CT(+TAG) qua read() (giống FPGA gửi lại)

    Khác với MockSerial đơn giản (pre-load cứng),
    CryptoMockSerial sẽ FAIL nếu TX bytes sai — đúng như FPGA thật.
    """
    def __init__(self, mode):
        self._mode = mode
        self._rx   = bytearray()
        self._tx   = bytearray()
        self._pos  = 0

    def write(self, data):
        self._rx.extend(data)
        if len(self._rx) >= 64 and not self._tx:
            # Đủ 64 bytes PT → tính crypto (giống FPGA hardware)
            ct, tag = _compute_expected_challenge(bytes(self._rx[:64]), self._mode)
            self._tx = bytearray(ct)
            if tag:
                self._tx.extend(tag)

    def flush(self): pass

    def read(self, n=1):
        end  = min(self._pos + n, len(self._tx))
        data = bytes(self._tx[self._pos:end])
        self._pos = end
        return data

    def reset_input_buffer(self):
        self._rx  = bytearray()
        self._tx  = bytearray()
        self._pos = 0

    def reset_output_buffer(self): pass
    def close(self): pass


def selftest():
    """
    Selftest chạy ĐÚNG các hàm send_and_verify() và send_and_verify_challenge()
    như khi chạy thật với FPGA, chỉ thay serial port bằng CryptoMockSerial.
    CryptoMockSerial tính crypto từ bytes nhận được — nếu script gửi sai PT,
    mock trả về sai CT → verify FAIL, giống FPGA thật.
    """
    import time as _time
    ts  = datetime.datetime.now().strftime("%Y-%m-%d  %H:%M:%S")
    print(f"\n{Fore.CYAN}{_W()}{Style.RESET_ALL}")
    print(f"{Fore.CYAN}{Style.BRIGHT}  RISC-V SoC — Offline Selftest (không cần FPGA){Style.RESET_ALL}")
    print(f"{Fore.CYAN}  Timestamp : {ts}{Style.RESET_ALL}")
    print(f"{Fore.CYAN}  Mock      : CryptoMockSerial — tính crypto thật từ PT nhận được{Style.RESET_ALL}")
    print(f"{Fore.CYAN}{_W()}{Style.RESET_ALL}")

    print(f"\n{Style.BRIGHT}  SoC Configuration:{Style.RESET_ALL}")
    for k, v in SOC_INFO.items():
        print(f"    {k:<12}: {v}")

    all_pass = True
    _orig_sleep = _time.sleep
    _time.sleep = lambda x: None   # tắt delay để selftest chạy nhanh

    # ── Part 1: Xác minh test vectors bằng Python crypto lib ───
    print(f"\n{_w()}")
    print(f"{Style.BRIGHT}  [1/3] Xác minh Test Vector — Python cryptography lib{Style.RESET_ALL}")
    print(f"{_w()}")
    try:
        from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305
        from cryptography.hazmat.primitives.ciphers import Cipher, algorithms

        key    = bytes(range(0x00, 0x20))
        nonce16 = struct.pack('<I', 1) + bytes([0,0,0,0, 0,0,0,0x4a, 0,0,0,0])
        enc = Cipher(algorithms.ChaCha20(key, nonce16), mode=None).encryptor()
        ct  = enc.update(PLAINTEXT) + enc.finalize()
        ok1 = ct == CHACHA20_EXPECTED_CT
        _pf(ok1, "ChaCha20 ciphertext (RFC 8439 §2.4.2)")

        aead   = ChaCha20Poly1305(bytes(range(0x80, 0xa0)))
        nonce  = bytes([0x07,0,0,0, 0x40,0x41,0x42,0x43, 0x44,0x45,0x46,0x47])
        aad    = bytes([0x50,0x51,0x52,0x53, 0xc0,0xc1,0xc2,0xc3, 0xc4,0xc5,0xc6,0xc7])
        ct_tag = aead.encrypt(nonce, PLAINTEXT, aad)
        ok2    = ct_tag[:-16] == AEAD_EXPECTED_CT
        ok3    = ct_tag[-16:] == AEAD_EXPECTED_TAG
        _pf(ok2, "AEAD ciphertext     (RFC 8439 §2.8.2)")
        _pf(ok3, "Poly1305 Auth Tag   (RFC 8439 §2.8.2)")
        if not (ok1 and ok2 and ok3):
            all_pass = False
    except ImportError:
        print(f"  {Fore.YELLOW}⚠  cryptography chưa cài — bỏ qua Part 1{Style.RESET_ALL}")

    # ── Part 2: RFC vector — gọi hàm send_and_verify() THẬT ───
    # CryptoMockSerial nhận PT, tính AEAD, trả CT+TAG
    # Giống hệt flow thật: nếu script gửi sai bytes → mock trả sai CT → FAIL
    print(f"\n{_w()}")
    print(f"{Style.BRIGHT}  [2/3] RFC 8439 Vector — send_and_verify() với CryptoMockSerial{Style.RESET_ALL}")
    print(f"  {Style.DIM}(hàm THẬT, mock tính crypto từ bytes nhận — giống FPGA){Style.RESET_ALL}")
    print(f"{_w()}")
    try:
        mock2 = CryptoMockSerial("aead_dma")
        ok_rfc = send_and_verify(mock2, "aead_dma")
        if not ok_rfc: all_pass = False
    except Exception as e:
        print(f"  {Fore.RED}✘  Lỗi Part 2: {e}{Style.RESET_ALL}")
        all_pass = False

    # ── Part 3: Random PT — gọi send_and_verify_challenge() THẬT ─
    # PT ngẫu nhiên → CryptoMockSerial tính đúng CT
    # send_and_verify_challenge tính độc lập → so sánh
    # Đây là test đầy đủ nhất: giống Challenge mode ngoài thực tế
    print(f"\n{_w()}")
    print(f"{Style.BRIGHT}  [3/3] Random PT — send_and_verify_challenge() với CryptoMockSerial{Style.RESET_ALL}")
    print(f"  {Style.DIM}(hàm THẬT, PT ngẫu nhiên, mock tính crypto — giống FPGA Challenge mode){Style.RESET_ALL}")
    print(f"{_w()}")
    try:
        mock3 = CryptoMockSerial("aead_dma")
        ok_ch = send_and_verify_challenge(mock3, "aead_dma")
        if not ok_ch: all_pass = False
    except Exception as e:
        print(f"  {Fore.RED}✘  Lỗi Part 3: {e}{Style.RESET_ALL}")
        all_pass = False

    _time.sleep = _orig_sleep   # khôi phục sleep

    # ── Summary ─────────────────────────────────────────────────
    print(f"\n{_W()}")
    if all_pass:
        print(f"{Fore.GREEN}{Style.BRIGHT}  ✔  SELFTEST PASSED — Tất cả test vectors đúng RFC 8439{Style.RESET_ALL}")
    else:
        print(f"{Fore.RED}{Style.BRIGHT}  ✘  SELFTEST FAILED — Có test vector sai{Style.RESET_ALL}")
    print(_W())
    return all_pass


def _pf(ok, label):
    """Print PASS/FAIL line."""
    if ok:
        print(f"  {Fore.GREEN}✔  {label}{Style.RESET_ALL}")
    else:
        print(f"  {Fore.RED}✘  {label}{Style.RESET_ALL}")


# ============================================================
#  Challenge Mode: random plaintext, Python verifies independently
# ============================================================

# Firmware-embedded key / nonce / AAD (same as hardcoded in demo_aead_dma.S)
_AEAD_KEY   = bytes(range(0x80, 0xa0))                                        # 32 bytes
_AEAD_NONCE = bytes([0x07,0,0,0, 0x40,0x41,0x42,0x43, 0x44,0x45,0x46,0x47]) # 12 bytes
_AEAD_AAD   = bytes([0x50,0x51,0x52,0x53, 0xc0,0xc1,0xc2,0xc3, 0xc4,0xc5,0xc6,0xc7])
_CC20_KEY   = bytes(range(0x00, 0x20))                                         # 32 bytes
_CC20_NONCE16 = struct.pack('<I', 1) + bytes([0,0,0,0, 0,0,0,0x4a, 0,0,0,0]) # 16 bytes


def _compute_expected_challenge(pt64, mode):
    """Compute CT (+TAG) using Python cryptography lib. Returns (ct, tag) or raises."""
    from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305
    from cryptography.hazmat.primitives.ciphers import Cipher, algorithms
    if mode == "chacha":
        enc = Cipher(algorithms.ChaCha20(_CC20_KEY, _CC20_NONCE16), mode=None).encryptor()
        ct  = enc.update(pt64) + enc.finalize()
        return ct, None
    else:
        aead   = ChaCha20Poly1305(_AEAD_KEY)
        ct_tag = aead.encrypt(_AEAD_NONCE, pt64, _AEAD_AAD)
        return ct_tag[:64], ct_tag[64:]


def send_and_verify_challenge(ser, mode):
    """
    Challenge Mode:
      1. Sinh 64 bytes plaintext NGAU NHIEN (os.urandom)
      2. Python tinh CT/TAG doc lap bang cryptography lib
      3. Gui PT len FPGA qua UART
      4. Nhan CT/TAG tu FPGA
      5. So sanh byte-by-byte
    => Chung minh FPGA THAT SU thuc hien ChaCha20-Poly1305
    """
    try:
        from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305
    except ImportError:
        print(f"{Fore.RED}  ERROR: Cần cài cryptography:  pip install cryptography{Style.RESET_ALL}")
        return False

    rx_len   = 64 if mode == "chacha" else 80
    rfc_ref  = "RFC 8439 §2.4.2" if mode == "chacha" else "RFC 8439 §2.8.2"
    dma_note = " + DMA" if mode == "aead_dma" else (" (CPU-only)" if mode == "aead" else "")
    algo     = "ChaCha20" if mode == "chacha" else f"ChaCha20-Poly1305 AEAD{dma_note}"
    ts       = datetime.datetime.now().strftime("%Y-%m-%d  %H:%M:%S")

    # ── Header ──────────────────────────────────────────────────────
    print(f"\n{Fore.MAGENTA}{_W()}{Style.RESET_ALL}")
    print(f"{Fore.MAGENTA}{Style.BRIGHT}  CHALLENGE MODE  —  {algo}{Style.RESET_ALL}")
    print(f"{Fore.MAGENTA}  Chứng minh FPGA thực sự thực thi {rfc_ref}{Style.RESET_ALL}")
    print(f"{Fore.MAGENTA}  Timestamp  : {ts}{Style.RESET_ALL}")
    print(f"{Fore.MAGENTA}{_W()}{Style.RESET_ALL}")

    # ── Bước 1: Sinh random plaintext ───────────────────────────────
    seed = int(time.time() * 1000) & 0xFFFFFFFF
    pt64 = os.urandom(64)

    print(f"\n{Style.BRIGHT}  [BƯỚC 1]  Sinh Plaintext Ngẫu Nhiên (os.urandom){Style.RESET_ALL}")
    print(f"  {Fore.YELLOW}Seed (ms epoch) : {seed}  — mỗi lần chạy KHÁC NHAU{Style.RESET_ALL}")
    print(f"  Plaintext (64 bytes ngẫu nhiên):")
    print(hex_dump(pt64))

    # ── Bước 2: Python tính expected ĐỘCL LẬP ───────────────────────
    print(f"\n{Style.BRIGHT}  [BƯỚC 2]  Python Tính CT Expected Độc Lập{Style.RESET_ALL}")
    print(f"  {Style.DIM}(dùng cryptography lib, KHÔNG liên quan đến FPGA){Style.RESET_ALL}")
    if mode == "chacha":
        print(f"  Thuật toán : ChaCha20  |  Key: 00 01 ... 1e 1f  |  Nonce: 00..4a..")
    else:
        print(f"  Thuật toán : ChaCha20-Poly1305  |  Key: 80 81 ... 9e 9f")
        print(f"  Nonce      : 07 00 00 00  40 41 42 43  44 45 46 47")
        print(f"  AAD        : 50 51 52 53  c0 c1 c2 c3  c4 c5 c6 c7")

    exp_ct, exp_tag = _compute_expected_challenge(pt64, mode)
    print(f"  Python expected CT ({len(exp_ct)}B):")
    print(hex_dump(exp_ct))
    if exp_tag:
        print(f"  Python expected TAG ({len(exp_tag)}B):")
        print(hex_dump(exp_tag))

    # ── Bước 3: Gửi lên FPGA ────────────────────────────────────────
    print(f"\n{Style.BRIGHT}  [BƯỚC 3]  Gửi 64 bytes → FPGA qua UART 115200{Style.RESET_ALL}")
    print(f"  {Fore.YELLOW}(plaintext ngẫu nhiên, firmware KHÔNG biết trước){Style.RESET_ALL}")

    ser.reset_input_buffer()
    t_start = time.perf_counter()

    for byte in pt64:
        ser.write(bytes([byte]))
        time.sleep(0.001)
    ser.flush()
    print(f"  {Style.DIM}→ Đã gửi xong, đang chờ FPGA xử lý...{Style.RESET_ALL}")

    # ── Bước 4: Nhận từ FPGA ────────────────────────────────────────
    response = bytearray()
    deadline = time.perf_counter() + 10.0
    while len(response) < rx_len:
        chunk = ser.read(rx_len - len(response))
        if chunk:
            response.extend(chunk)
        if time.perf_counter() > deadline:
            break

    t_end   = time.perf_counter()
    elapsed = (t_end - t_start) * 1000.0

    if len(response) < rx_len:
        print(f"\n{Fore.RED}  ✘  TIMEOUT: chỉ nhận {len(response)}/{rx_len} bytes sau 10s{Style.RESET_ALL}")
        return False

    fpga_ct  = bytes(response[:64])
    fpga_tag = bytes(response[64:]) if rx_len > 64 else None

    print(f"\n{Style.BRIGHT}  [BƯỚC 4]  FPGA Trả Về (nhận qua UART):{Style.RESET_ALL}")
    print(f"  {Fore.GREEN}Đã nhận {len(response)} bytes trong {elapsed:.1f} ms{Style.RESET_ALL}")
    print(f"  FPGA CT ({len(fpga_ct)}B) — màu xanh=khớp, đỏ=sai:")
    print(hex_dump(fpga_ct, expected=exp_ct))
    if fpga_tag:
        print(f"  FPGA TAG ({len(fpga_tag)}B):")
        print(hex_dump(fpga_tag, expected=exp_tag))

    # ── Bước 5: So sánh ─────────────────────────────────────────────
    print(f"\n{Style.BRIGHT}  [BƯỚC 5]  So Sánh Python vs FPGA (byte-by-byte):{Style.RESET_ALL}")
    ct_ok,  _  = compare_and_print(exp_ct,  fpga_ct,  "Ciphertext (64B)")
    tag_ok     = True
    if exp_tag and fpga_tag:
        tag_ok, _ = compare_and_print(exp_tag, fpga_tag, "Auth Tag   (16B)")

    # Timing
    uart_tx  = 64   * 10 / 115200 * 1000
    uart_rx  = rx_len * 10 / 115200 * 1000
    dly      = 64 * 1.0
    crypto   = max(0.0, elapsed - uart_tx - uart_rx - dly)
    print(f"\n  Thời gian end-to-end   : {Fore.MAGENTA}{elapsed:.2f} ms{Style.RESET_ALL}")
    print(f"  Ước tính crypto (FPGA) : {Fore.MAGENTA}{crypto:.2f} ms  @50MHz ≈ {int(crypto*50000):,} cycles{Style.RESET_ALL}")

    # ── Verdict ─────────────────────────────────────────────────────
    print(f"\n{_W()}")
    if ct_ok and tag_ok:
        print(f"{Fore.GREEN}{Style.BRIGHT}"
              f"  ✔  CHALLENGE PASSED"
              f"  —  Plaintext ngẫu nhiên, FPGA mã hóa đúng {rfc_ref}"
              f"{Style.RESET_ALL}")
        print(f"{Fore.GREEN}  ⇒  Không thể là dữ liệu giả: PT thay đổi mỗi lần chạy,"
              f" Python tính độc lập, kết quả khớp hoàn toàn.{Style.RESET_ALL}")
    else:
        print(f"{Fore.RED}{Style.BRIGHT}"
              f"  ✘  CHALLENGE FAILED  —  Kết quả KHÔNG khớp"
              f"{Style.RESET_ALL}")
    print(_W())
    return ct_ok and tag_ok


# ============================================================
#  Main
# ============================================================

def main():
    parser = argparse.ArgumentParser(
        description="FPGA Verify — RFC 8439 test vector verification",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Ví dụ:
  python fpga_verify.py --port COM3 --demo aead         # AEAD CPU-only
  python fpga_verify.py --port COM3 --demo aead_dma     # AEAD + DMA
  python fpga_verify.py --port COM3 --demo chacha       # ChaCha20 only
  python fpga_verify.py --selftest                       # Kiem tra offline
  python fpga_verify.py --list-ports                     # Liet ke COM ports
        """,
    )
    parser.add_argument("--port", "-p", default="COM3",
                        help="Cong COM (mac dinh: COM3)")
    parser.add_argument("--demo", "-d", default="aead",
                        choices=["chacha", "aead", "aead_dma"],
                        help="Che do demo (mac dinh: aead)")
    parser.add_argument("--baud", "-b", type=int, default=115200,
                        help="Baudrate (mac dinh: 115200)")
    parser.add_argument("--list-ports", action="store_true",
                        help="Liet ke cac cong COM co san")
    parser.add_argument("--selftest", action="store_true",
                        help="Chay selftest offline (khong can FPGA)")
    parser.add_argument("--challenge", action="store_true",
                        help="Challenge mode: random PT, Python verify doc lap (chung minh FPGA that su ma hoa)")
    args = parser.parse_args()

    # --- Selftest ---
    if args.selftest:
        ok = selftest()
        sys.exit(0 if ok else 1)

    # --- List ports ---
    if args.list_ports:
        if serial is None:
            print("ERROR: Can cai pyserial:  pip install pyserial")
            sys.exit(1)
        from serial.tools.list_ports import comports
        ports = comports()
        if not ports:
            print("Khong tim thay cong COM nao.")
        else:
            print(f"\nCac cong COM co san:")
            for p in ports:
                print(f"  {p.device:8s}  {p.description}")
        return

    # --- Check pyserial ---
    if serial is None:
        print("ERROR: Can cai pyserial:  pip install pyserial")
        sys.exit(1)

    # --- Challenge mode ---
    if args.challenge:
        ts = datetime.datetime.now().strftime("%Y-%m-%d  %H:%M:%S")
        print(f"\n{Fore.MAGENTA}{_W()}{Style.RESET_ALL}")
        print(f"{Fore.MAGENTA}{Style.BRIGHT}  RISC-V SoC — CHALLENGE MODE  (RFC 8439){Style.RESET_ALL}")
        print(f"{Fore.MAGENTA}  Timestamp : {ts}  |  Port: {args.port}  |  Mode: {args.demo}{Style.RESET_ALL}")
        print(f"{Fore.MAGENTA}{_W()}{Style.RESET_ALL}")
        print(f"\n{Style.BRIGHT}  SoC / Hardware:{Style.RESET_ALL}")
        for k, v in SOC_INFO.items():
            print(f"    {k:<12}: {v}")
        ser = open_serial(args.port, args.baud)
        print(f"\n  {Fore.GREEN}✔  Kết nối {args.port} thành công{Style.RESET_ALL}")
        try:
            send_and_verify_challenge(ser, args.demo)
        except KeyboardInterrupt:
            print(f"\n  {Fore.YELLOW}⚠  Đã hủy.{Style.RESET_ALL}")
        finally:
            ser.close()
            print(f"  {Style.DIM}Đã đóng {args.port}.{Style.RESET_ALL}")
        return

    # ── Main banner ─────────────────────────────────────────────
    ts = datetime.datetime.now().strftime("%Y-%m-%d  %H:%M:%S")
    print(f"\n{Fore.CYAN}{_W()}{Style.RESET_ALL}")
    print(f"{Fore.CYAN}{Style.BRIGHT}  RISC-V SoC — FPGA Verification  (RFC 8439){Style.RESET_ALL}")
    print(f"{Fore.CYAN}  Timestamp : {ts}{Style.RESET_ALL}")
    print(f"{Fore.CYAN}  Port      : {args.port}   Baud: {args.baud}   Mode: {args.demo}{Style.RESET_ALL}")
    print(f"{Fore.CYAN}{_W()}{Style.RESET_ALL}")
    print(f"\n{Style.BRIGHT}  SoC / Hardware:{Style.RESET_ALL}")
    for k, v in SOC_INFO.items():
        print(f"    {k:<12}: {v}")

    # ── Connect ─────────────────────────────────────────────────
    ser = open_serial(args.port, args.baud)
    print(f"\n  {Fore.GREEN}✔  Kết nối {args.port} thành công{Style.RESET_ALL}")

    try:
        ok = send_and_verify(ser, args.demo)
    except KeyboardInterrupt:
        print(f"\n  {Fore.YELLOW}⚠  Đã hủy bởi người dùng.{Style.RESET_ALL}")
    finally:
        ser.close()
        print(f"  {Style.DIM}Đã đóng {args.port}.{Style.RESET_ALL}")


if __name__ == "__main__":
    main()
