#!/usr/bin/env python3
"""Run full 03_sw haze-removal flow on a real image and dump stage images.

Default input is image 47 from the IPU simulation folder.
Outputs are saved to 03_sw/image.
"""

from pathlib import Path
import argparse
import numpy as np
from PIL import Image
from PIL import ImageFilter

from dark_channel import compute_dark_channel_image
from atmospheric_light import estimate_atmospheric_light_image


# Match current software/RTL-oriented parameters
A0 = 150
USE_SKY = 1
T_SKY = 255
OMEGA_Q8 = 243
T_MIN_COARSE = 26
MODIFICATION_VALUE = 255
TX_MIN_RECOVERY = 15
ADC_PATCH = 5

# IPU haze_removal_core post parameters
RECOVERY_TX_MIN = 73
DENSE_HAZE_TH = 117
DENSE_HAZE_SUB = 8
SHARP_NUM = 5
SHARP_SHIFT = 6
DARK_GUARD_Y = 40
DARK_GUARD_MARGIN = 20
MID_DARK_Y1 = 64
MID_DARK_Y2 = 96
MID_DARK_Y3 = 128
MID_DARK_MARGIN1 = 12
MID_DARK_MARGIN2 = 18
MID_DARK_MARGIN3 = 28

# Hardware-like tone calibration and foliage denoise
POST_BIAS = 2
POST_LIFT_SHIFT = 6
POST_HAZE_SHIFT = 5
SHARP_NUM_DARK = 2
SHARP_NUM_BRIGHT = 3
FOLIAGE_Y_MAX = 120
FOLIAGE_G_MIN = 28
FOLIAGE_G_DOM = 10
OUTPUT_GAMMA = 1.25
CORNER_Y_START_RATIO = 0.72
CORNER_X_START_RATIO = 0.72
CORNER_NEUTRAL_SAT_MAX = 26
CORNER_Y_MAX = 165
CORNER_BLEND_ORIG = 2
CORNER_BLEND_SMOOTH = 5
CORNER_LIFT_CAP = 16
CORNER_FEATHER_RADIUS = 2
CORNER_SRC_BLEND = 2
CORNER_TONE_BLEND = 5


def clamp_u8(arr: np.ndarray) -> np.ndarray:
    return np.clip(arr, 0, 255).astype(np.uint8)


def rgb_to_gray_fixed(img_rgb: np.ndarray) -> np.ndarray:
    r = img_rgb[:, :, 0].astype(np.int32)
    g = img_rgb[:, :, 1].astype(np.int32)
    b = img_rgb[:, :, 2].astype(np.int32)

    s = 5 * r + 9 * g + 2 * b
    integer = (s >> 4) & 0xFF
    fraction = s & 0xF

    # round-to-even (mode=2) from grayscale.py
    gray = integer.copy()
    gray[fraction > 8] = (gray[fraction > 8] + 1) & 0xFF
    tie = fraction == 8
    gray[tie & ((gray & 1) == 1)] = (gray[tie & ((gray & 1) == 1)] + 1) & 0xFF
    return gray.astype(np.uint8)


def build_inv_lut_q16() -> np.ndarray:
    lut = np.zeros(256, dtype=np.int64)
    lut[0] = 0xFFFFFF
    for i in range(1, 256):
        lut[i] = (255 << 16) // i
    return lut


def estimate_transmission_map(
    img_rgb: np.ndarray,
    sky_mask: np.ndarray,
    a_rgb: np.ndarray,
) -> np.ndarray:
    lut = build_inv_lut_q16()
    a_r, a_g, a_b = [int(x) for x in a_rgb]

    r = img_rgb[:, :, 0].astype(np.int64)
    g = img_rgb[:, :, 1].astype(np.int64)
    b = img_rgb[:, :, 2].astype(np.int64)

    n_r = np.minimum((r * lut[a_r]) >> 16, 255)
    n_g = np.minimum((g * lut[a_g]) >> 16, 255)
    n_b = np.minimum((b * lut[a_b]) >> 16, 255)

    min_norm = np.minimum(np.minimum(n_r, n_g), n_b)
    t = 255 - ((OMEGA_Q8 * min_norm) >> 8)
    t = np.maximum(t, T_MIN_COARSE)

    if USE_SKY:
        t = np.where(sky_mask > 0, T_SKY, t)

    return clamp_u8(t)


def dehaze_map(img_rgb: np.ndarray, adc_dark_map: np.ndarray, a_scalar: int):
    a_scalar = max(int(a_scalar), 1)

    tx_raw = 255 - ((adc_dark_map.astype(np.int32) * MODIFICATION_VALUE) // a_scalar)
    tx_raw = np.clip(tx_raw, 0, 255).astype(np.int32)
    tx_used = np.maximum(tx_raw, TX_MIN_RECOVERY).astype(np.int32)

    src = img_rgb.astype(np.int32)
    num = ((src - a_scalar) << 8) + (a_scalar * tx_used[:, :, None])
    out = np.trunc(num / tx_used[:, :, None]).astype(np.int32)
    out = clamp_u8(out)

    return tx_raw.astype(np.uint8), tx_used.astype(np.uint8), out


def _clamp_to_inner_indices(h: int, w: int):
    yy, xx = np.indices((h, w))
    if h > 2:
        yy = np.clip(yy, 1, h - 2)
    if w > 2:
        xx = np.clip(xx, 1, w - 2)
    return yy, xx


def ipu_like_recovery(
    img_rgb: np.ndarray,
    tx_coarse: np.ndarray,
    adc_map: np.ndarray,
    a_rgb: np.ndarray,
):
    """Approximate IPU haze_removal_core full-frame recovery path."""
    h, w, _ = img_rgb.shape

    yy, xx = _clamp_to_inner_indices(h, w)
    tx_for_recovery = tx_coarse[yy, xx].astype(np.int32)
    adc_raw = adc_map[yy, xx].astype(np.int32)

    adc_min = int(adc_map.min())
    adc_max = int(adc_map.max())
    adc_dark_for_recovery = adc_raw.copy()
    adc_range = adc_max - adc_min

    if adc_range >= 8:
        norm_adc = ((adc_raw - adc_min) * 255) // adc_range
        norm_adc = np.clip(norm_adc, 0, 255)
        blend_adc = ((norm_adc * 3) + adc_raw) >> 2
        adc_dark_for_recovery = np.clip(blend_adc, 0, 255)

    a_r, a_g, a_b = [int(x) for x in a_rgb]
    a_max = max(a_r, a_g, a_b)

    if a_max == 0:
        tx_adc = np.full((h, w), T_MIN_COARSE, dtype=np.int32)
    else:
        q = (adc_dark_for_recovery * MODIFICATION_VALUE) // a_max
        q = np.clip(q, 0, 255)
        tx_adc = 255 - q
        tx_adc = np.clip(tx_adc, T_MIN_COARSE, 255)

    tx_mix = (tx_for_recovery + (tx_adc << 2) + (tx_adc << 1) + tx_adc) >> 3
    tx_aggr = tx_mix.copy()
    mask_heavier = (tx_adc + 8) < tx_for_recovery
    tx_aggr[mask_heavier] = (tx_mix[mask_heavier] + tx_adc[mask_heavier]) >> 1
    dense_mask = tx_aggr < DENSE_HAZE_TH
    tx_aggr[dense_mask] = tx_aggr[dense_mask] - DENSE_HAZE_SUB
    tx_hybrid = np.clip(tx_aggr, RECOVERY_TX_MIN, 255).astype(np.int32)

    tx_used = np.maximum(tx_hybrid, TX_MIN_RECOVERY).astype(np.int32)

    src = img_rgb.astype(np.int32)
    a_vec = np.array([a_r, a_g, a_b], dtype=np.int32)

    value_tem = ((src - a_vec) << 8) + (a_vec * tx_used[:, :, None])
    rec = np.trunc(value_tem / tx_used[:, :, None]).astype(np.int32)
    rec = np.clip(rec, 0, 255)

    rec_w_rec = np.where(tx_used <= 96, 15, np.where(tx_used <= 160, 12, 6)).astype(np.int32)
    rec_w_src = np.where(tx_used <= 160, 1, 2).astype(np.int32)
    denom = rec_w_rec + rec_w_src

    sum_rgb = rec * rec_w_rec[:, :, None] + src * rec_w_src[:, :, None]
    lift = ((255 - tx_used) >> POST_LIFT_SHIFT)
    lift = np.clip(lift, 0, 13)

    rec_post = (sum_rgb // denom[:, :, None]) + lift[:, :, None] + POST_BIAS
    rec_post = np.clip(rec_post, 0, 255).astype(np.int32)

    haze_boost = ((255 - tx_used) >> POST_HAZE_SHIFT)
    haze_boost = np.clip(haze_boost, 0, 15)

    tone = rec_post.copy()
    tone[:, :, 0] = tone[:, :, 0] + haze_boost
    tone[:, :, 1] = tone[:, :, 1] + (haze_boost >> 3)
    tone[:, :, 2] = tone[:, :, 2] - (haze_boost >> 3)
    tone = np.clip(tone, 0, 255)

    cond = (
        (tone[:, :, 0] > 132)
        & (tone[:, :, 2] > 132)
        & ((tone[:, :, 1] + 12) < tone[:, :, 0])
        & ((tone[:, :, 1] + 8) < tone[:, :, 2])
    )
    if np.any(cond):
        purple_floor_g = ((tone[:, :, 0] + tone[:, :, 2]) >> 1) - 6
        tone[:, :, 1] = np.where(cond & (purple_floor_g > tone[:, :, 1]), purple_floor_g, tone[:, :, 1])

        purple_drop_b = (tone[:, :, 2] - tone[:, :, 1]) >> 1
        tone[:, :, 2] = np.where(cond & (purple_drop_b > 0), tone[:, :, 2] - purple_drop_b, tone[:, :, 2])

        tone[:, :, 2] = np.where(
            cond & (tone[:, :, 2] > (tone[:, :, 1] + 12)),
            tone[:, :, 1] + 12,
            tone[:, :, 2],
        )

    src_y = (299 * src[:, :, 0] + 587 * src[:, :, 1] + 114 * src[:, :, 2]) // 1000
    detail = tone - src
    sharp_num = np.where(src_y < 100, SHARP_NUM_DARK, SHARP_NUM_BRIGHT)
    tone = tone + ((detail * sharp_num[:, :, None]) >> SHARP_SHIFT)
    # Guard dark regions: avoid bright artifact dots in near-black areas.
    dark_mask = src_y < DARK_GUARD_Y
    tone_cap = np.clip(src + DARK_GUARD_MARGIN, 0, 255)
    tone = np.where(dark_mask[:, :, None], np.minimum(tone, tone_cap), tone)

    # Additional adaptive anti-hotspot cap for dark/mid-dark source pixels.
    # This suppresses isolated white artifacts while keeping bright regions intact.
    max_lift = np.where(
        src_y < MID_DARK_Y1,
        MID_DARK_MARGIN1,
        np.where(
            src_y < MID_DARK_Y2,
            MID_DARK_MARGIN2,
            np.where(src_y < MID_DARK_Y3, MID_DARK_MARGIN3, 255),
        ),
    )
    tone_cap2 = np.clip(src + max_lift[:, :, None], 0, 255)
    tone = np.minimum(tone, tone_cap2)
    tone = np.clip(tone, 0, 255).astype(np.uint8)

    # Denoise foliage-like regions (dark green texture) to reduce salt-and-pepper artifacts.
    foliage_mask = (
        (src_y < FOLIAGE_Y_MAX)
        & (src[:, :, 1] > FOLIAGE_G_MIN)
        & ((src[:, :, 1] - src[:, :, 0]) > FOLIAGE_G_DOM)
        & ((src[:, :, 1] - src[:, :, 2]) > FOLIAGE_G_DOM)
    )
    if np.any(foliage_mask):
        median_img = np.array(Image.fromarray(tone, mode="RGB").filter(ImageFilter.MedianFilter(size=3)))
        tone = np.where(foliage_mask[:, :, None], median_img, tone)

    # Stronger cleanup for the bottom-right corner where foliage/neutral haze blocks tend to appear.
    yy2, xx2 = np.indices((h, w))
    corner_mask = (yy2 >= int(h * CORNER_Y_START_RATIO)) & (xx2 >= int(w * CORNER_X_START_RATIO))

    src_max = np.maximum(np.maximum(src[:, :, 0], src[:, :, 1]), src[:, :, 2])
    src_min = np.minimum(np.minimum(src[:, :, 0], src[:, :, 1]), src[:, :, 2])
    src_sat = src_max - src_min

    corner_noise_mask = corner_mask & (
        foliage_mask
        | ((src_y < CORNER_Y_MAX) & (src_sat <= CORNER_NEUTRAL_SAT_MAX))
    )

    if np.any(corner_noise_mask):
        smooth = np.array(
            Image.fromarray(tone, mode="RGB")
            .filter(ImageFilter.MedianFilter(size=5))
            .filter(ImageFilter.BoxBlur(radius=1))
        ).astype(np.int32)
        tone_i = tone.astype(np.int32)
        blended = (tone_i * CORNER_BLEND_ORIG + smooth * CORNER_BLEND_SMOOTH) // (CORNER_BLEND_ORIG + CORNER_BLEND_SMOOTH)
        blended = (blended * CORNER_TONE_BLEND + src * CORNER_SRC_BLEND) // (CORNER_TONE_BLEND + CORNER_SRC_BLEND)
        corner_cap = np.clip(src + CORNER_LIFT_CAP, 0, 255)
        blended = np.minimum(blended, corner_cap)

        mask_u8 = (corner_noise_mask.astype(np.uint8) * 255)
        alpha = np.array(
            Image.fromarray(mask_u8, mode="L").filter(ImageFilter.BoxBlur(radius=CORNER_FEATHER_RADIUS)),
            dtype=np.float32,
        ) / 255.0
        alpha = alpha[:, :, None]

        tone_f = tone.astype(np.float32)
        blend_f = blended.astype(np.float32)
        tone = np.clip(tone_f * (1.0 - alpha) + blend_f * alpha, 0, 255).astype(np.uint8)

    # Match hardware output brightness trend (Python path was consistently brighter).
    tone_f = tone.astype(np.float32) / 255.0
    tone = np.clip((tone_f ** OUTPUT_GAMMA) * 255.0 + 0.5, 0, 255).astype(np.uint8)

    return (
        adc_dark_for_recovery.astype(np.uint8),
        tx_adc.astype(np.uint8),
        tx_hybrid.astype(np.uint8),
        rec.astype(np.uint8),
        tone,
    )


def save_gray(path: Path, gray: np.ndarray):
    Image.fromarray(gray, mode="L").save(path)


def save_rgb(path: Path, rgb: np.ndarray):
    Image.fromarray(rgb, mode="RGB").save(path)


def main():
    repo_root = Path(__file__).resolve().parents[1]
    default_input = repo_root / "01_sim/IPU/Testbench_Grayscale Image Converter_System/sim/image/47_hazy.png"
    default_out = repo_root / "03_sw/image"

    parser = argparse.ArgumentParser(description="Run full 03_sw flow and dump stage images")
    parser.add_argument("--input", type=Path, default=default_input, help="Input image path")
    parser.add_argument("--outdir", type=Path, default=default_out, help="Output directory")
    parser.add_argument("--tag", type=str, default="47", help="Prefix tag for output filenames")
    args = parser.parse_args()

    in_path = args.input
    outdir = args.outdir
    tag = args.tag

    outdir.mkdir(parents=True, exist_ok=True)

    img = Image.open(in_path).convert("RGB")
    img_rgb = np.array(img, dtype=np.uint8)

    # Stage 0: input
    save_rgb(outdir / f"{tag}_stage0_input.png", img_rgb)

    # Stage 1: dark channel (patch min)
    dark = compute_dark_channel_image(img_rgb, patch_size=15)
    save_gray(outdir / f"{tag}_stage1_dark_channel.png", dark)

    # Stage 2: grayscale
    gray = rgb_to_gray_fixed(img_rgb)
    save_gray(outdir / f"{tag}_stage2_grayscale.png", gray)

    # Stage 3: atmospheric light (global)
    a_rgb = estimate_atmospheric_light_image(img_rgb, dark, top_percent=0.001)

    # Stage 4: sky mask
    sky = (gray > A0).astype(np.uint8) * 255
    save_gray(outdir / f"{tag}_stage3_sky_mask.png", sky)

    # Stage 5: coarse transmission
    tx_coarse = estimate_transmission_map(img_rgb, sky, a_rgb)
    save_gray(outdir / f"{tag}_stage4_transmission_coarse.png", tx_coarse)

    # Stage 6: ADC-dark approximation (local min on transmission)
    tx_rgb = np.stack([tx_coarse, tx_coarse, tx_coarse], axis=2)
    adc_dark = compute_dark_channel_image(tx_rgb, patch_size=ADC_PATCH)
    save_gray(outdir / f"{tag}_stage5_adc_dark.png", adc_dark)

    # Stage 7-10: IPU-like hybrid recovery path
    adc_used, tx_adc, tx_hybrid, rec_direct, out_rgb = ipu_like_recovery(img_rgb, tx_coarse, adc_dark, a_rgb)
    save_gray(outdir / f"{tag}_stage6_adc_used.png", adc_used)
    save_gray(outdir / f"{tag}_stage7_tx_adc.png", tx_adc)
    save_gray(outdir / f"{tag}_stage8_tx_hybrid.png", tx_hybrid)
    save_rgb(outdir / f"{tag}_stage9_recovery_direct.png", rec_direct)
    save_rgb(outdir / f"{tag}_stage10_dehazed_output.png", out_rgb)

    report_path = outdir / f"{tag}_flow_report.txt"
    with open(report_path, "w", encoding="ascii", errors="ignore") as f:
        f.write("Full flow run for 03_sw\n")
        f.write(f"input={in_path}\n")
        f.write(f"size={img_rgb.shape[1]}x{img_rgb.shape[0]}\n")
        f.write(f"A_rgb=({int(a_rgb[0])},{int(a_rgb[1])},{int(a_rgb[2])})\n")
        f.write(f"A0={A0}, OMEGA_Q8={OMEGA_Q8}, T_MIN_COARSE={T_MIN_COARSE}, MODIFICATION_VALUE={MODIFICATION_VALUE}\n")
        f.write(f"TX_MIN_RECOVERY={TX_MIN_RECOVERY}, RECOVERY_TX_MIN={RECOVERY_TX_MIN}, DENSE_HAZE_TH={DENSE_HAZE_TH}, DENSE_HAZE_SUB={DENSE_HAZE_SUB}\n")
        f.write("outputs:\n")
        f.write(f"- {tag}_stage0_input.png\n")
        f.write(f"- {tag}_stage1_dark_channel.png\n")
        f.write(f"- {tag}_stage2_grayscale.png\n")
        f.write(f"- {tag}_stage3_sky_mask.png\n")
        f.write(f"- {tag}_stage4_transmission_coarse.png\n")
        f.write(f"- {tag}_stage5_adc_dark.png\n")
        f.write(f"- {tag}_stage6_adc_used.png\n")
        f.write(f"- {tag}_stage7_tx_adc.png\n")
        f.write(f"- {tag}_stage8_tx_hybrid.png\n")
        f.write(f"- {tag}_stage9_recovery_direct.png\n")
        f.write(f"- {tag}_stage10_dehazed_output.png\n")

    print("Full flow completed")
    print(f"Input : {in_path}")
    print(f"Outdir: {outdir}")
    print(f"A_rgb : ({int(a_rgb[0])}, {int(a_rgb[1])}, {int(a_rgb[2])})")
    print(f"Saved : {report_path}")


if __name__ == "__main__":
    main()
