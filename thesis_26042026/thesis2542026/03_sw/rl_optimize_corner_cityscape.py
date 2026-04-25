#!/usr/bin/env python3
"""RL-based local optimizer for noisy foliage/artifact region in cityscape output.

This script uses a lightweight epsilon-greedy Q-learning loop to tune local
post-filter parameters for the bottom-right ROI highlighted by the user.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import argparse
import random
import numpy as np
from PIL import Image, ImageFilter


@dataclass(frozen=True)
class Action:
    median_size: int
    blur_radius: int
    smooth_alpha: float
    src_pull: float
    lift_cap: int
    feather_radius: int


def to_gray(img: np.ndarray) -> np.ndarray:
    r = img[:, :, 0].astype(np.int32)
    g = img[:, :, 1].astype(np.int32)
    b = img[:, :, 2].astype(np.int32)
    return ((299 * r + 587 * g + 114 * b) // 1000).astype(np.int32)


def build_candidate(base: np.ndarray, src: np.ndarray, mask: np.ndarray, action: Action) -> np.ndarray:
    base_u8 = base.astype(np.uint8)
    pil = Image.fromarray(base_u8, mode="RGB")
    smooth = pil.filter(ImageFilter.MedianFilter(size=action.median_size))
    if action.blur_radius > 0:
        smooth = smooth.filter(ImageFilter.BoxBlur(radius=action.blur_radius))

    smooth_np = np.array(smooth).astype(np.float32)
    base_f = base.astype(np.float32)
    src_f = src.astype(np.float32)

    # Blend toward smooth image then pull a portion toward source to preserve structure.
    blend = base_f * (1.0 - action.smooth_alpha) + smooth_np * action.smooth_alpha
    blend = blend * (1.0 - action.src_pull) + src_f * action.src_pull

    # Cap local lift to suppress white block artifacts in dark foliage.
    cap = np.clip(src_f + float(action.lift_cap), 0.0, 255.0)
    blend = np.minimum(blend, cap)

    mask_u8 = (mask.astype(np.uint8) * 255)
    alpha = np.array(
        Image.fromarray(mask_u8, mode="L").filter(ImageFilter.BoxBlur(radius=action.feather_radius)),
        dtype=np.float32,
    ) / 255.0
    alpha = alpha[:, :, None]

    out = np.clip(base_f * (1.0 - alpha) + blend * alpha, 0.0, 255.0)
    return out.astype(np.uint8)


def score_candidate(base: np.ndarray, src: np.ndarray, cand: np.ndarray, mask: np.ndarray) -> tuple[float, dict]:
    g_base = to_gray(base)
    g_src = to_gray(src)
    g_cand = to_gray(cand)

    if not np.any(mask):
        return -1e9, {"note": "empty-mask"}

    # High-frequency energy proxy (lower is better for noise suppression).
    dx = np.abs(np.diff(g_cand, axis=1))
    dy = np.abs(np.diff(g_cand, axis=0))
    grad = (dx[:-1, :] + dy[:, :-1]) * 0.5
    m2 = mask[:-1, :-1]
    noise_energy = float(grad[m2].mean()) if np.any(m2) else 999.0

    # White/sparkle artifact proxy in dark ROI (lower is better).
    lift = g_cand - g_src
    sparkle = ((lift > 22) & mask).sum() / float(mask.sum())

    # Preserve structure by limiting divergence from base in masked region.
    delta_from_base = np.abs(cand.astype(np.int32) - base.astype(np.int32)).mean(axis=2)
    preserve_penalty = float(delta_from_base[mask].mean())

    # Reward: larger is better.
    reward = -(1.00 * noise_energy + 280.0 * sparkle + 0.20 * preserve_penalty)

    metrics = {
        "noise_energy": noise_energy,
        "sparkle_ratio": float(sparkle),
        "preserve_penalty": preserve_penalty,
        "reward": reward,
    }
    return reward, metrics


def build_roi_mask(src: np.ndarray, x_ratio: float, y_ratio: float) -> np.ndarray:
    h, w, _ = src.shape
    yy, xx = np.indices((h, w))

    roi = (xx >= int(w * x_ratio)) & (yy >= int(h * y_ratio))

    y = to_gray(src)
    r = src[:, :, 0].astype(np.int32)
    g = src[:, :, 1].astype(np.int32)
    b = src[:, :, 2].astype(np.int32)
    sat = np.maximum(np.maximum(r, g), b) - np.minimum(np.minimum(r, g), b)

    foliage_like = (y < 140) & (g > 28) & ((g - r) > 8) & ((g - b) > 8)
    neutral_block_like = (y < 170) & (sat < 30)

    mask = roi & (foliage_like | neutral_block_like)
    return mask


def main():
    parser = argparse.ArgumentParser(description="RL optimize noisy bottom-right cityscape region")
    parser.add_argument("--src", type=Path, required=True, help="Stage0/source image path")
    parser.add_argument("--base", type=Path, required=True, help="Current stage10 output path")
    parser.add_argument("--out", type=Path, required=True, help="Output path for RL-optimized image")
    parser.add_argument("--report", type=Path, required=True, help="Output report path")
    parser.add_argument("--mask-out", type=Path, required=True, help="Output debug mask image path")
    parser.add_argument("--episodes", type=int, default=180, help="Q-learning episodes")
    parser.add_argument("--seed", type=int, default=47, help="Random seed")
    parser.add_argument("--x-ratio", type=float, default=0.33, help="ROI x start ratio")
    parser.add_argument("--y-ratio", type=float, default=0.57, help="ROI y start ratio")
    args = parser.parse_args()

    random.seed(args.seed)
    np.random.seed(args.seed)

    src = np.array(Image.open(args.src).convert("RGB"), dtype=np.uint8)
    base = np.array(Image.open(args.base).convert("RGB"), dtype=np.uint8)

    if src.shape != base.shape:
        raise ValueError(f"Shape mismatch src={src.shape} base={base.shape}")

    mask = build_roi_mask(src, args.x_ratio, args.y_ratio)

    action_space: list[Action] = []
    for median_size in (3, 5):
        for blur_radius in (0, 1, 2):
            for smooth_alpha in (0.50, 0.65, 0.80, 0.90):
                for src_pull in (0.10, 0.20, 0.30):
                    for lift_cap in (10, 14, 18, 22):
                        for feather_radius in (1, 2, 3):
                            action_space.append(
                                Action(
                                    median_size=median_size,
                                    blur_radius=blur_radius,
                                    smooth_alpha=smooth_alpha,
                                    src_pull=src_pull,
                                    lift_cap=lift_cap,
                                    feather_radius=feather_radius,
                                )
                            )

    q_values = np.zeros(len(action_space), dtype=np.float64)
    counts = np.zeros(len(action_space), dtype=np.int32)

    epsilon = 0.35
    epsilon_min = 0.05
    epsilon_decay = (epsilon - epsilon_min) / max(args.episodes, 1)
    lr = 0.20

    baseline_reward, baseline_metrics = score_candidate(base, src, base, mask)

    best_reward = baseline_reward
    best_metrics = baseline_metrics
    best_action = None
    best_img = base.copy()

    for episode in range(args.episodes):
        if random.random() < epsilon:
            idx = random.randrange(len(action_space))
        else:
            idx = int(np.argmax(q_values))

        action = action_space[idx]
        cand = build_candidate(base, src, mask, action)
        reward, metrics = score_candidate(base, src, cand, mask)

        counts[idx] += 1
        q_values[idx] += lr * (reward - q_values[idx])

        if reward > best_reward:
            best_reward = reward
            best_metrics = metrics
            best_action = action
            best_img = cand

        epsilon = max(epsilon_min, epsilon - epsilon_decay)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.mask_out.parent.mkdir(parents=True, exist_ok=True)

    Image.fromarray(best_img, mode="RGB").save(args.out)
    Image.fromarray((mask.astype(np.uint8) * 255), mode="L").save(args.mask_out)

    with open(args.report, "w", encoding="ascii", errors="ignore") as f:
        f.write("RL corner optimization report\n")
        f.write(f"src={args.src}\n")
        f.write(f"base={args.base}\n")
        f.write(f"episodes={args.episodes}, seed={args.seed}\n")
        f.write(f"roi_ratios: x>={args.x_ratio}, y>={args.y_ratio}\n")
        f.write(f"mask_pixels={int(mask.sum())}\n")
        f.write("baseline_metrics:\n")
        for k, v in baseline_metrics.items():
            f.write(f"  {k}={v}\n")
        f.write("best_metrics:\n")
        for k, v in best_metrics.items():
            f.write(f"  {k}={v}\n")
        if best_action is None:
            f.write("best_action=baseline (no improvement)\n")
        else:
            f.write("best_action:\n")
            f.write(f"  median_size={best_action.median_size}\n")
            f.write(f"  blur_radius={best_action.blur_radius}\n")
            f.write(f"  smooth_alpha={best_action.smooth_alpha}\n")
            f.write(f"  src_pull={best_action.src_pull}\n")
            f.write(f"  lift_cap={best_action.lift_cap}\n")
            f.write(f"  feather_radius={best_action.feather_radius}\n")

    print("RL optimization done")
    print(f"Saved image: {args.out}")
    print(f"Saved mask : {args.mask_out}")
    print(f"Saved report: {args.report}")
    print(f"Baseline reward: {baseline_reward:.4f}")
    print(f"Best reward    : {best_reward:.4f}")
    if best_action is not None:
        print(f"Best action    : {best_action}")


if __name__ == "__main__":
    main()
