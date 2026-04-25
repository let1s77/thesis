#!/usr/bin/env python3
"""vga_scan_view.py — Visualize VGA dehaze output on terminal.

Reads two BMP files (input hazy + dehazed output) and renders them
side-by-side using block characters, with pixel statistics to confirm
the IPU haze-removal pipeline worked correctly.

Dependencies:
    pip install Pillow rich        (recommended — color side-by-side)
    pip install Pillow             (fallback — grayscale ASCII art)

Usage:
    # Compare both images in image_test folder
    python 12_test/vga_scan_view.py

    # Specify custom paths
    python 12_test/vga_scan_view.py \\
        --before 01_sim/soc/Testbench_SOC/sim/image_test/soc_input_128.bmp \\
        --after  01_sim/soc/Testbench_SOC/sim/image_test/cpu_dehazed_128.bmp

    # Use image_47
    python 12_test/vga_scan_view.py --image47

    # Only print stats, no render
    python 12_test/vga_scan_view.py --stats-only

    # Wider render (default: 64 chars per panel)
    python 12_test/vga_scan_view.py --width 96
"""

import argparse
import os
import sys
import struct
from pathlib import Path

# ─────────────────────────────────────────────────────────────────────────────
# Optional rich import — graceful fallback to ANSI escape codes
# ─────────────────────────────────────────────────────────────────────────────
try:
    from rich.console import Console
    from rich.columns import Columns
    from rich.text import Text
    from rich.panel import Panel
    from rich.table import Table
    RICH_AVAILABLE = True
except ImportError:
    RICH_AVAILABLE = False

try:
    from PIL import Image
    PIL_AVAILABLE = True
except ImportError:
    PIL_AVAILABLE = False
    print("ERROR: Pillow is required. Install with: pip install Pillow", file=sys.stderr)
    sys.exit(1)


# ─────────────────────────────────────────────────────────────────────────────
# Default paths (relative to project root thesis2542026/)
# ─────────────────────────────────────────────────────────────────────────────
_SIM_ROOT     = Path("01_sim/soc/Testbench_SOC/sim")
_DEFAULT_TEST = {
    "before": _SIM_ROOT / "image_test" / "soc_input_128.bmp",
    "after":  _SIM_ROOT / "image_test" / "cpu_dehazed_128.bmp",
    "label":  "image_test (cityscape)",
}
_DEFAULT_47 = {
    "before": _SIM_ROOT / "image_47" / "soc_input_128.bmp",
    "after":  _SIM_ROOT / "image_47" / "cpu_dehazed_128.bmp",
    "label":  "image_47 (outdoor hazy)",
}

# Unicode half-block: top pixel = fg color, bottom pixel = bg color.
# Using "█" (full block) with fg color is simpler and more compatible.
BLOCK = "█"

# ─────────────────────────────────────────────────────────────────────────────
# Image helpers
# ─────────────────────────────────────────────────────────────────────────────

def load_bmp(path: Path) -> Image.Image:
    """Load BMP and convert to RGB."""
    if not path.exists():
        print(f"ERROR: File not found: {path}", file=sys.stderr)
        sys.exit(1)
    return Image.open(path).convert("RGB")


def resize_for_terminal(img: Image.Image, max_w: int) -> Image.Image:
    """Resize image to fit max_w columns, accounting for char aspect ratio."""
    w = max_w
    # Terminal chars are ~2× taller than wide, so halve the height
    h = max(1, int(img.height * (w / img.width) * 0.5))
    return img.resize((w, h), Image.LANCZOS)


def compute_stats(img: Image.Image) -> dict:
    """Compute per-channel mean, std, and overall brightness."""
    import statistics
    pixels = list(img.getdata())
    r_vals = [p[0] for p in pixels]
    g_vals = [p[1] for p in pixels]
    b_vals = [p[2] for p in pixels]
    brightness = [(p[0] + p[1] + p[2]) / 3 for p in pixels]
    return {
        "mean_r":  sum(r_vals) / len(r_vals),
        "mean_g":  sum(g_vals) / len(g_vals),
        "mean_b":  sum(b_vals) / len(b_vals),
        "mean_br": sum(brightness) / len(brightness),
        "std_br":  statistics.stdev(brightness),
        "min_br":  min(brightness),
        "max_br":  max(brightness),
        "n_black": sum(1 for p in pixels if p[0] < 5 and p[1] < 5 and p[2] < 5),
        "n_white": sum(1 for p in pixels if p[0] > 250 and p[1] > 250 and p[2] > 250),
        "total":   len(pixels),
    }


def psnr(img_ref: Image.Image, img_out: Image.Image) -> float:
    """Compute PSNR between two same-size RGB images (in dB)."""
    import math
    ref = list(img_ref.resize(img_out.size).getdata())
    out = list(img_out.getdata())
    mse = sum(
        (int(r[0]) - int(o[0])) ** 2 +
        (int(r[1]) - int(o[1])) ** 2 +
        (int(r[2]) - int(o[2])) ** 2
        for r, o in zip(ref, out)
    ) / (3 * len(ref))
    if mse == 0:
        return float("inf")
    return 10 * math.log10(255 ** 2 / mse)


# ─────────────────────────────────────────────────────────────────────────────
# Render helpers
# ─────────────────────────────────────────────────────────────────────────────

def img_to_rich_text(img: Image.Image, max_w: int) -> "Text":
    """Convert PIL image → rich.Text with colored block chars."""
    small = resize_for_terminal(img, max_w)
    t = Text(no_wrap=True)
    for y in range(small.height):
        for x in range(small.width):
            r, g, b = small.getpixel((x, y))
            t.append(BLOCK, style=f"rgb({r},{g},{b})")
        t.append("\n")
    return t


def img_to_ansi(img: Image.Image, max_w: int) -> str:
    """Convert PIL image → ANSI escape code string (fallback)."""
    small = resize_for_terminal(img, max_w)
    lines = []
    for y in range(small.height):
        row = ""
        for x in range(small.width):
            r, g, b = small.getpixel((x, y))
            row += f"\x1b[38;2;{r};{g};{b}m{BLOCK}"
        row += "\x1b[0m"
        lines.append(row)
    return "\n".join(lines)


# ─────────────────────────────────────────────────────────────────────────────
# Print functions
# ─────────────────────────────────────────────────────────────────────────────

def print_stats_rich(console: "Console", label_before: str, label_after: str,
                     st_before: dict, st_after: dict, psnr_val: float) -> None:
    table = Table(title="Pixel Statistics", show_header=True, header_style="bold cyan")
    table.add_column("Metric",        style="bold")
    table.add_column(label_before,    justify="right")
    table.add_column(label_after,     justify="right")
    table.add_column("Delta",         justify="right")

    def fmt(v): return f"{v:.2f}"
    def delta(a, b, invert=False):
        d = b - a
        sign = "+" if d >= 0 else ""
        color = "green" if ((d > 0) != invert) else "red"
        return f"[{color}]{sign}{d:.2f}[/{color}]"

    table.add_row("Mean Brightness", fmt(st_before["mean_br"]), fmt(st_after["mean_br"]),
                  delta(st_before["mean_br"], st_after["mean_br"]))
    table.add_row("Brightness Std",  fmt(st_before["std_br"]),  fmt(st_after["std_br"]),
                  delta(st_before["std_br"], st_after["std_br"]))
    table.add_row("Mean R",          fmt(st_before["mean_r"]),  fmt(st_after["mean_r"]),
                  delta(st_before["mean_r"], st_after["mean_r"]))
    table.add_row("Mean G",          fmt(st_before["mean_g"]),  fmt(st_after["mean_g"]),
                  delta(st_before["mean_g"], st_after["mean_g"]))
    table.add_row("Mean B",          fmt(st_before["mean_b"]),  fmt(st_after["mean_b"]),
                  delta(st_before["mean_b"], st_after["mean_b"]))
    table.add_row("Black pixels",    str(st_before["n_black"]), str(st_after["n_black"]),
                  delta(st_before["n_black"], st_after["n_black"], invert=True))
    table.add_row("White pixels",    str(st_before["n_white"]), str(st_after["n_white"]),
                  delta(st_before["n_white"], st_after["n_white"], invert=True))

    psnr_str = f"{psnr_val:.2f} dB" if psnr_val != float("inf") else "∞ (identical)"
    table.add_row("PSNR (before→after)", "—", "—", psnr_str)

    console.print(table)

    # Verdict
    br_delta = st_after["mean_br"] - st_before["mean_br"]
    std_delta = st_after["std_br"] - st_before["std_br"]
    if br_delta > 5 and std_delta > 2:
        console.print("[bold green]✓ DEHAZE OK[/bold green]  "
                      "— brightness ↑ and contrast ↑ after IPU processing")
    elif st_after["n_black"] == st_after["total"]:
        console.print("[bold red]✗ OUTPUT ALL BLACK[/bold red]  "
                      "— IPU may not have run or img_out_bram is empty")
    elif psnr_val > 50:
        console.print("[bold yellow]⚠ Output almost identical to input[/bold yellow]  "
                      "— check if IPU was triggered correctly")
    else:
        console.print("[bold cyan]~ Output differs from input[/bold cyan]  "
                      "— verify visually if dehaze looks correct")


def print_stats_plain(st_before: dict, st_after: dict,
                      psnr_val: float, label_before: str, label_after: str) -> None:
    sep = "-" * 60
    print(sep)
    print(f"{'Metric':<22}  {label_before:>14}  {label_after:>14}  {'Delta':>8}")
    print(sep)
    rows = [
        ("Mean Brightness",  st_before["mean_br"], st_after["mean_br"]),
        ("Brightness Std",   st_before["std_br"],  st_after["std_br"]),
        ("Mean R",           st_before["mean_r"],  st_after["mean_r"]),
        ("Mean G",           st_before["mean_g"],  st_after["mean_g"]),
        ("Mean B",           st_before["mean_b"],  st_after["mean_b"]),
        ("Black pixels",     st_before["n_black"], st_after["n_black"]),
        ("White pixels",     st_before["n_white"], st_after["n_white"]),
    ]
    for name, a, b in rows:
        delta = b - a
        sign = "+" if delta >= 0 else ""
        print(f"{name:<22}  {a:>14.2f}  {b:>14.2f}  {sign}{delta:>7.2f}")
    psnr_str = f"{psnr_val:.2f} dB" if psnr_val != float("inf") else "inf"
    print(f"{'PSNR':<22}  {'—':>14}  {'—':>14}  {psnr_str:>8}")
    print(sep)


def render_rich(img_before: Image.Image, img_after: Image.Image,
                path_before: Path, path_after: Path,
                st_before: dict, st_after: dict,
                psnr_val: float, max_w: int) -> None:
    console = Console()

    console.print(f"\n[bold]Input (hazy)[/bold]  ←  [bold cyan]{path_before}[/bold cyan]")
    console.print(f"[bold]Output (dehazed)[/bold]  ←  [bold green]{path_after}[/bold green]\n")

    before_text = img_to_rich_text(img_before, max_w)
    after_text  = img_to_rich_text(img_after,  max_w)

    console.print(
        Columns(
            [
                Panel(before_text, title="[bold yellow]BEFORE  (hazy input)[/bold yellow]",
                      border_style="yellow"),
                Panel(after_text,  title="[bold green]AFTER   (dehazed output)[/bold green]",
                      border_style="green"),
            ],
            equal=True,
            expand=False,
        )
    )

    print_stats_rich(console, "Before", "After", st_before, st_after, psnr_val)


def render_ansi(img_before: Image.Image, img_after: Image.Image,
                path_before: Path, path_after: Path,
                st_before: dict, st_after: dict,
                psnr_val: float, max_w: int) -> None:
    half = max(max_w // 2, 20)
    b_lines = img_to_ansi(img_before, half).split("\n")
    a_lines = img_to_ansi(img_after,  half).split("\n")
    pad = max(len(b_lines), len(a_lines))
    b_lines += [""] * (pad - len(b_lines))
    a_lines += [""] * (pad - len(a_lines))

    header = f"{'BEFORE (hazy)':<{half * 2}}  {'AFTER (dehazed)':}"
    print(header)
    print("-" * (half * 4 + 2))
    for bl, al in zip(b_lines, a_lines):
        print(f"{bl}  {al}")
    print("\x1b[0m")
    print_stats_plain(st_before, st_after, psnr_val, "Before", "After")


# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Visualize VGA dehaze before/after on terminal with pixel stats."
    )
    parser.add_argument(
        "--before", type=Path, default=None,
        help="Path to hazy input BMP (default: sim/image_test/soc_input_128.bmp)"
    )
    parser.add_argument(
        "--after", type=Path, default=None,
        help="Path to dehazed output BMP (default: sim/image_test/cpu_dehazed_128.bmp)"
    )
    parser.add_argument(
        "--image47", action="store_true",
        help="Use image_47 paths instead of image_test"
    )
    parser.add_argument(
        "--width", type=int, default=64,
        help="Width (chars) per image panel (default: 64)"
    )
    parser.add_argument(
        "--stats-only", action="store_true",
        help="Print only pixel statistics, skip terminal render"
    )
    parser.add_argument(
        "--no-rich", action="store_true",
        help="Force fallback ANSI renderer even if rich is installed"
    )
    args = parser.parse_args()

    # Resolve default paths
    defaults = _DEFAULT_47 if args.image47 else _DEFAULT_TEST
    path_before = args.before if args.before else defaults["before"]
    path_after  = args.after  if args.after  else defaults["after"]
    label       = defaults["label"] if not (args.before or args.after) else str(path_before.parent)

    print(f"\n=== VGA Dehaze Scan Viewer  —  {label} ===")
    print(f"  Before : {path_before}")
    print(f"  After  : {path_after}\n")

    img_before = load_bmp(path_before)
    img_after  = load_bmp(path_after)

    print(f"  Image size: {img_before.width}×{img_before.height} pixels")

    # Compute stats
    st_before  = compute_stats(img_before)
    st_after   = compute_stats(img_after)
    psnr_val   = psnr(img_before, img_after)

    if args.stats_only:
        print_stats_plain(st_before, st_after, psnr_val, "Before", "After")
        return

    # Render
    use_rich = RICH_AVAILABLE and not args.no_rich
    if use_rich:
        render_rich(img_before, img_after, path_before, path_after,
                    st_before, st_after, psnr_val, args.width)
    else:
        if not RICH_AVAILABLE:
            print("(rich not installed — using ANSI fallback; install with: pip install rich)\n")
        render_ansi(img_before, img_after, path_before, path_after,
                    st_before, st_after, psnr_val, args.width)


if __name__ == "__main__":
    main()
