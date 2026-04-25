from dataclasses import dataclass, asdict
from pathlib import Path
import csv

MODIFICATION_VALUE = 255  # 1.0 * 256 - stronger dehaze effect
TX_MIN = 15  # Lower minimum transmission for stronger dehaze

@dataclass
class Case:
    case_id: int
    name: str
    dark: int
    A: int
    src_r: int
    src_g: int
    src_b: int


def trunc_div(a: int, b: int) -> int:
    if b == 0:
        raise ZeroDivisionError('Division by zero')
    return int(a / b)  # trunc toward zero, matching Verilog signed division


def tx_get(dark: int, A: int) -> int:
    modify_A = dark * MODIFICATION_VALUE
    tx = 255 - trunc_div(modify_A, A)
    return tx & 0xFF


def haze_remove_channel(src: int, A: int, tx_in: int) -> int:
    tx_value = tx_in if tx_in >= TX_MIN else TX_MIN
    value_tem = ((src - A) << 8) + A * tx_value
    q = trunc_div(value_tem, tx_value)
    return q & 0xFF


def run_case(c: Case):
    tx_raw = tx_get(c.dark, c.A)
    tx_clamped = tx_raw if tx_raw >= TX_MIN else TX_MIN
    out_r = haze_remove_channel(c.src_r, c.A, tx_raw)
    out_g = haze_remove_channel(c.src_g, c.A, tx_raw)
    out_b = haze_remove_channel(c.src_b, c.A, tx_raw)
    in_word = (
        ((c.dark & 0xFF) << 40)
        | ((c.A & 0xFF) << 32)
        | ((c.src_r & 0xFF) << 24)
        | ((c.src_g & 0xFF) << 16)
        | ((c.src_b & 0xFF) << 8)
        | (c.case_id & 0xFF)
    )
    golden_word = (
        ((tx_raw & 0xFF) << 32)
        | ((out_r & 0xFF) << 24)
        | ((out_g & 0xFF) << 16)
        | ((out_b & 0xFF) << 8)
        | (c.case_id & 0xFF)
    )
    return {
        **asdict(c),
        'tx_raw': tx_raw,
        'tx_used': tx_clamped,
        'out_r': out_r,
        'out_g': out_g,
        'out_b': out_b,
        'input_hex': f'{in_word:012X}',
        'golden_hex': f'{golden_word:010X}',
    }


def build_cases():
    return [
        Case(0,  'clear_scene_nominal',        20, 220, 180, 170, 160),
        Case(1,  'light_haze_midtones',        60, 210, 150, 140, 130),
        Case(2,  'moderate_haze',             100, 200, 160, 145, 120),
        Case(3,  'heavy_haze_low_tx',         170, 190, 180, 160, 140),
        Case(4,  'very_dark_pixel',            15, 200,  20,  18,  16),
        Case(5,  'bright_pixel_close_to_A',   180, 220, 215, 210, 205),
        Case(6,  'red_dominant',               90, 205, 220, 110, 100),
        Case(7,  'green_dominant',             95, 205, 100, 220, 110),
        Case(8,  'blue_dominant',              90, 205, 105, 110, 225),
        Case(9,  'dark_equals_A',             180, 180, 150, 145, 140),
        Case(10, 'dark_near_A',               199, 200, 180, 170, 160),
        Case(11, 'minimum_tx_clamp_case',     210, 220, 190, 180, 170),
        Case(12, 'low_A_value',                30,  64,  90,  85,  80),
        Case(13, 'high_A_value',               40, 250, 200, 195, 190),
        Case(14, 'flat_gray',                 100, 180, 128, 128, 128),
        Case(15, 'src_below_A',                80, 160, 120, 110, 100),
        Case(16, 'src_equal_A',                70, 150, 150, 150, 150),
        Case(17, 'src_above_A',                70, 150, 190, 180, 170),
        Case(18, 'near_black_haze',            10, 120,   8,   8,   8),
        Case(19, 'near_white_haze',           180, 230, 250, 248, 246),
    ]


def write_outputs(pattern_dir: Path, golden_dir: Path):
    pattern_dir.mkdir(parents=True, exist_ok=True)
    golden_dir.mkdir(parents=True, exist_ok=True)
    rows = [run_case(c) for c in build_cases()]

    with open(pattern_dir / 't_compute_fuse_input.hex', 'w') as f:
        for r in rows:
            f.write(r['input_hex'] + '\n')

    with open(golden_dir / 't_compute_fuse_golden.hex', 'w') as f:
        for r in rows:
            f.write(r['golden_hex'] + '\n')

    with open(golden_dir / 't_compute_fuse_cases.csv', 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)

    with open(golden_dir / 't_compute_fuse_case_table.md', 'w') as f:
        f.write('|id|name|dark|A|src_rgb|tx_raw|tx_used|out_rgb|input_hex|golden_hex|\n')
        f.write('|-:|---|---:|---:|---|---:|---:|---|---|---|\n')
        for r in rows:
            f.write(
                f"|{r['case_id']}|{r['name']}|{r['dark']}|{r['A']}|"
                f"({r['src_r']},{r['src_g']},{r['src_b']})|{r['tx_raw']}|{r['tx_used']}|"
                f"({r['out_r']},{r['out_g']},{r['out_b']})|{r['input_hex']}|{r['golden_hex']}|\n"
            )

    return rows


if __name__ == '__main__':
    repo_root = Path(__file__).resolve().parents[1]
    pattern_dir = repo_root / '09_pattern'
    golden_dir = repo_root / '07_golden_output'

    rows = write_outputs(pattern_dir, golden_dir)

    print(f'Generated {len(rows)} cases')
    print(f'Pattern file: {pattern_dir / "t_compute_fuse_input.hex"}')
    print(f'Golden file : {golden_dir / "t_compute_fuse_golden.hex"}')
    print('--- Dump (input_hex -> golden_hex) ---')
    for r in rows:
        print(f"case {r['case_id']:02d}: {r['input_hex']} -> {r['golden_hex']}")
