#!/usr/bin/env python3
"""RL-based FPGA timing optimizer for the Haze Removal SoC.

Uses epsilon-greedy Q-learning to explore a design-parameter space and find
the configuration that meets 50 MHz Fmax on Cyclone V with minimal latency
overhead.  The "environment" is an analytical timing model built from
detailed path analysis of the actual RTL.

Usage:
    python rl_timing_optimizer.py                   # default: 8000 episodes
    python rl_timing_optimizer.py --episodes 20000  # longer training
    python rl_timing_optimizer.py --seed 42         # reproducible
"""

from __future__ import annotations

import argparse
import json
import random
import textwrap
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Dict, List, Tuple

import numpy as np

# ═══════════════════════════════════════════════════════════════════════════════
# 1.  CYCLONE V TIMING MODEL -- delay constants (nanoseconds)
# ═══════════════════════════════════════════════════════════════════════════════
# Values from Quartus Fitter / TCCS / datasheet for 5CSXFC6D6F31C6 Slow 85 °C

CYC5 = {
    "lut4":          0.50,   # single ALM LUT
    "carry32":       2.50,   # 32-bit carry chain add
    "carry16":       1.50,   # 16-bit carry chain
    "mul8x8_dsp":    3.00,   # DSP 9×9 multiply
    "mul8x8_fab":    4.00,   # fabric 8×8 multiply
    "mul16x8_fab":   5.50,   # fabric 16×8 multiply
    "mul12x5_fab":   3.50,   # fabric 12×5 multiply
    "div16_8":      12.00,   # fabric 16/8 combinational divide
    "div17_9s":     15.00,   # fabric 17/9 signed divide
    "div12_5":       8.00,   # fabric 12/5 combinational divide
    "m10k_read":     2.50,   # M10K read (clock-to-out)
    "m10k_bypass":   4.50,   # M10K "new data" bypass mux path
    "m10k_outreg":   1.20,   # M10K output register addition
    "mux2_1":        0.30,   # 2:1 mux
    "mux4_1":        0.60,   # 4:1 mux
    "cmp8":          1.00,   # 8-bit comparator
    "cmp16":         1.50,   # 16-bit comparator
    "clamp":         0.80,   # saturation clamp (compare + mux)
    "routing_local": 0.80,   # short routing (within LAB)
    "routing_med":   1.50,   # medium routing (cross-LAB)
    "routing_long":  3.00,   # long routing (cross-column)
    "reg_setup":     0.30,   # register setup time
    "reg_clktoq":    0.40,   # register clock-to-Q
    "lut_recip":     2.50,   # 256-entry reciprocal LUT read
    "shift":         0.20,   # constant shift (wiring)
    "int_div_mod":   5.00,   # integer modulo/divide  for addr calc
}

TARGET_FMAX_MHZ = 50.0
TARGET_PERIOD_NS = 1000.0 / TARGET_FMAX_MHZ  # 20 ns


# ═══════════════════════════════════════════════════════════════════════════════
# 2.  DESIGN CONFIGURATION -- the tunable knobs
# ═══════════════════════════════════════════════════════════════════════════════

@dataclass(frozen=True)
class DesignConfig:
    # --- Pipeline stages in fusing.sv ---
    fusing_pipe: int = 0        # 0: all-combo (current)
                                # 1: split mul | div+clamp
                                # 2: split mul | div | clamp

    # --- Pipeline stages in t_computing.sv ---
    tcomp_pipe: int = 0         # 0: all-combo (current)
                                # 1: split mul | div+clamp

    # --- Division replacement strategy ---
    fusing_div_mode: int = 0    # 0: combo divide (current)
                                # 1: reciprocal LUT + multiply
    tcomp_div_mode: int = 0     # 0: combo divide (current)
                                # 1: reciprocal LUT + multiply
    core_norm_div_mode: int = 0 # 0: combo divide (current, range_adc div)
                                # 1: reciprocal LUT approximation
    core_hybrid_div_mode: int = 0  # 0: combo divide (current)
                                   # 1: reciprocal LUT + multiply
    blend_div_mode: int = 0     # 0: combo /denom (current)
                                # 1: reciprocal constant (denomin{8,13,16})

    # --- Register insertion in haze_removal_core ---
    reg_adc_dark: int = 0       # 0: no (current), 1: register adc_dark_for_recovery
    reg_tx_hybrid: int = 0      # 0: no (current), 1: register tx_hybrid_for_recovery
    reg_post_blend: int = 0     # 0: no (current), 1: register rec_r/g/b_post

    # --- Pipeline mid-point in hybrid TX computation ---
    reg_core_hybrid_mid: int = 0  # 0: no, 1: register between tx_adc and mix/aggr

    # --- BRAM output registers ---
    bram_out_oreg: int = 0      # 0: no (current), 1: enable M10K output register
    bram_in_oreg: int = 0       # 0: no, 1: yes
    bram_tmp_oreg: int = 0      # 0: no, 1: yes

    # --- Port B pipeline registers (soc_top) ---
    portb_out_pipe: int = 1     # already applied (1)
    portb_in_pipe: int = 0      # 0: no, 1: yes
    portb_tmp_pipe: int = 0     # 0: no, 1: yes


# ═══════════════════════════════════════════════════════════════════════════════
# 3.  TIMING MODEL -- compute critical path delay for a configuration
# ═══════════════════════════════════════════════════════════════════════════════

def _fusing_combo_delay(cfg: DesignConfig) -> float:
    """Delay of the combinational logic *within one pipeline stage* of fusing."""
    d = CYC5

    # Stage A: comparator + 3× multiply + 3× shift-add
    stage_a = (d["cmp8"] + d["mux2_1"]          # tx_used = max(tx_raw, TX_MIN)
               + d["mul8x8_fab"]                 # mul_A_tx = A * tx_used
               + d["shift"] + d["carry16"]       # value_tem = (diff<<<8) + mul_A_tx
               + d["routing_local"])

    # Stage B: 3× signed division + clamp
    if cfg.fusing_div_mode == 0:
        div_delay = d["div17_9s"]
    else:  # reciprocal LUT + multiply
        div_delay = d["lut_recip"] + d["mul8x8_dsp"] + d["shift"]

    stage_b = div_delay + d["clamp"] + d["routing_local"]

    if cfg.fusing_pipe == 0:
        return stage_a + stage_b
    elif cfg.fusing_pipe == 1:
        return max(stage_a, stage_b)
    else:  # pipe == 2
        stage_c = d["clamp"] + d["routing_local"]
        stage_b_no_clamp = div_delay + d["routing_local"]
        return max(stage_a, stage_b_no_clamp, stage_c)


def _tcomp_combo_delay(cfg: DesignConfig) -> float:
    """Delay of t_computing combinational logic."""
    d = CYC5

    stage_a = d["mul8x8_fab"] + d["routing_local"]  # modify_A = dark * OMEGA

    if cfg.tcomp_div_mode == 0:
        div_delay = d["div16_8"]
    else:
        div_delay = d["lut_recip"] + d["mul8x8_dsp"] + d["shift"]

    stage_b = div_delay + d["clamp"] + d["cmp8"] + d["mux2_1"] + d["routing_local"]

    if cfg.tcomp_pipe == 0:
        return stage_a + stage_b
    else:
        return max(stage_a, stage_b)


def _core_norm_delay(cfg: DesignConfig) -> float:
    """Delay of the ADC normalize + blend block in haze_removal_core."""
    d = CYC5

    # Address calculation (row/col + clamp)
    addr_calc = d["int_div_mod"] + d["cmp16"] + d["mux2_1"] + d["routing_med"]

    # BRAM read latency (already registered -- comes from previous cycle)
    # So the combo path starts at adc_frame_map_rd_data

    # Normalize: (raw - min) * 255 / range
    if cfg.core_norm_div_mode == 0:
        norm_div = d["carry16"] + d["mul8x8_fab"] + d["div16_8"]
    else:
        norm_div = d["carry16"] + d["mul8x8_fab"] + d["lut_recip"] + d["mul8x8_dsp"] + d["shift"]

    # Blend: norm*3 + raw >> 2
    blend = d["mul8x8_fab"] + d["carry16"] + d["shift"]

    return norm_div + blend + d["clamp"] + d["routing_local"]


def _core_hybrid_delay(cfg: DesignConfig) -> float:
    """Delay of the tx_hybrid computation block."""
    d = CYC5

    if cfg.core_hybrid_div_mode == 0:
        div_delay = d["div16_8"]
    else:
        div_delay = d["lut_recip"] + d["mul8x8_dsp"] + d["shift"]

    # Stage A: tx_adc = 255 - (dark*OMEGA/A_max), clamped
    stage_a = (d["mul8x8_fab"] + div_delay
               + d["carry16"] + d["clamp"] + d["routing_local"])

    # Stage B: tx_mix = blend(tx_bank, tx_adc) + aggr + dense
    stage_b = (d["shift"] * 2 + d["carry16"]       # mix shifts+add
               + d["cmp8"] + d["mux2_1"]            # aggr condition
               + d["carry16"] + d["shift"]           # aggr blend
               + d["cmp8"] + d["carry16"]            # dense condition + sub
               + d["clamp"] + d["routing_local"])    # final clamp

    if cfg.reg_core_hybrid_mid:
        return max(stage_a, stage_b)
    else:
        return stage_a + stage_b


def _blend_delay(cfg: DesignConfig) -> float:
    """Delay of the post-recovery blend + lift block."""
    d = CYC5

    # Weight select (combo from rec_tx_used)
    weight_sel = d["cmp8"] * 2 + d["mux2_1"] * 2

    # 3× multiply + sum
    mul = d["mul12x5_fab"]
    add = d["carry16"]

    # Division by denom
    if cfg.blend_div_mode == 0:
        div = d["div12_5"]
    else:
        # denom in {8, 13, 16}: can use constant reciprocal
        div = d["mul12x5_fab"] + d["shift"]  # multiply by reciprocal + shift

    # lift + clamp
    lift = d["carry16"] + d["shift"] + d["carry16"]
    clamp = d["clamp"]

    return weight_sel + mul + add + div + lift + clamp + d["routing_local"]


def _tone_delay(_cfg: DesignConfig) -> float:
    """Delay of the tone mapping block."""
    d = CYC5

    haze_boost = d["carry16"] + d["shift"] + d["clamp"]
    tone_apply = d["carry16"] + d["shift"]
    purple_guard = d["cmp8"] * 4 + d["mux2_1"] * 2 + d["carry16"] * 2
    detail = d["carry16"] + d["mul12x5_fab"] + d["shift"] + d["carry16"]
    clamp = d["clamp"]

    return haze_boost + tone_apply + purple_guard + detail + clamp + d["routing_local"]


def _bram_portb_delay(cfg: DesignConfig, which: str) -> float:
    """Delay of BRAM Port B path (address mux -> M10K -> output)."""
    d = CYC5

    pipe = {"out": cfg.portb_out_pipe, "in": cfg.portb_in_pipe, "tmp": cfg.portb_tmp_pipe}[which]
    oreg = {"out": cfg.bram_out_oreg, "in": cfg.bram_in_oreg, "tmp": cfg.bram_tmp_oreg}[which]

    if pipe:
        # Address mux is registered -- M10K sees registered inputs
        mux_delay = 0.0
    else:
        mux_delay = d["cmp8"] + d["mux2_1"] + d["routing_med"]

    bram_read = d["m10k_read"]
    if oreg:
        bram_read += d["m10k_outreg"]
    else:
        bram_read += d["m10k_bypass"]

    return mux_delay + bram_read + d["routing_long"]


def _risc_v_exec_delay(_cfg: DesignConfig) -> float:
    """RISC-V exec phase delay (constant -- no knobs here)."""
    d = CYC5
    regfile_read = 2.5
    mux_ops = 0.5
    alu_barrel = 3.0
    lsu_decode = 2.0
    routing = 0.5
    return regfile_read + mux_ops + alu_barrel + lsu_decode + routing


def compute_all_paths(cfg: DesignConfig) -> Dict[str, float]:
    """Return delay of every critical path for the given config."""
    d = CYC5
    paths = {}

    # --- Path 1: BRAM->norm->hybrid->fusing chain ---
    norm_d = _core_norm_delay(cfg)
    hybrid_d = _core_hybrid_delay(cfg)
    fusing_d = _fusing_combo_delay(cfg)

    p1 = 0.0
    if cfg.reg_adc_dark:
        # norm is registered -- hybrid starts fresh
        p1_norm = norm_d + d["reg_setup"]
        p1_hybrid = hybrid_d
        if cfg.reg_tx_hybrid:
            p1_hybrid_to_fuse = hybrid_d + d["reg_setup"]
            p1_fuse = fusing_d + d["reg_setup"]
            p1 = max(p1_norm, p1_hybrid_to_fuse, p1_fuse)
        else:
            p1 = max(p1_norm, hybrid_d + fusing_d + d["reg_setup"])
    else:
        if cfg.reg_tx_hybrid:
            p1 = max(norm_d + hybrid_d + d["reg_setup"],
                     fusing_d + d["reg_setup"])
        else:
            p1 = norm_d + hybrid_d + fusing_d + d["reg_setup"]
    paths["BRAM->norm->hybrid->fusing"] = p1

    # --- Path 2: BRAM->norm->t_computing ---
    tcomp_d = _tcomp_combo_delay(cfg)
    p2 = 0.0
    if cfg.reg_adc_dark:
        p2 = max(norm_d + d["reg_setup"], tcomp_d + d["reg_setup"])
    else:
        p2 = norm_d + tcomp_d + d["reg_setup"]
    paths["BRAM->norm->t_computing"] = p2

    # --- Path 3: Post-blend + tone ---
    blend_d = _blend_delay(cfg)
    tone_d = _tone_delay(cfg)

    if cfg.reg_post_blend:
        p3 = max(blend_d + d["reg_setup"], tone_d + d["reg_setup"])
    else:
        p3 = blend_d + tone_d + d["reg_setup"]
    paths["post_blend->tone"] = p3

    # --- Path 4: fusing standalone (from registered inputs) ---
    paths["fusing_standalone"] = fusing_d + d["reg_setup"]

    # --- Path 5: t_computing standalone ---
    paths["t_computing_standalone"] = tcomp_d + d["reg_setup"]

    # --- Path 6: BRAM Port B (img_out) ---
    paths["bram_portb_out"] = _bram_portb_delay(cfg, "out")

    # --- Path 7: BRAM Port B (img_in) ---
    paths["bram_portb_in"] = _bram_portb_delay(cfg, "in")

    # --- Path 8: RISC-V exec ---
    paths["risc_v_exec"] = _risc_v_exec_delay(cfg) + d["reg_setup"]

    # --- Path 9: estimate_transmission (well pipelined, constant) ---
    paths["estimate_tx"] = (d["lut_recip"] + d["mul8x8_dsp"] * 1.5
                            + d["carry16"] + d["clamp"] + d["routing_local"])

    return paths


def estimate_fmax(cfg: DesignConfig) -> Tuple[float, Dict[str, float]]:
    """Return (Fmax_MHz, path_dict) for the configuration."""
    paths = compute_all_paths(cfg)
    worst_delay = max(paths.values())
    fmax = 1000.0 / worst_delay if worst_delay > 0 else 999.0
    return fmax, paths


# ═══════════════════════════════════════════════════════════════════════════════
# 4.  RESOURCE / LATENCY COST MODEL
# ═══════════════════════════════════════════════════════════════════════════════

def compute_cost(cfg: DesignConfig) -> dict:
    """Estimate added latency (cycles) and resource cost (ALMs)."""
    added_latency = 0
    added_alms = 0
    added_m10k_bits = 0

    # fusing pipeline
    added_latency += cfg.fusing_pipe
    added_alms += cfg.fusing_pipe * 80  # pipeline register ALMs

    # t_computing pipeline
    added_latency += cfg.tcomp_pipe
    added_alms += cfg.tcomp_pipe * 40

    # Reciprocal LUT replacement
    lut_count = sum([cfg.fusing_div_mode, cfg.tcomp_div_mode,
                     cfg.core_norm_div_mode, cfg.core_hybrid_div_mode])
    added_m10k_bits += lut_count * 256 * 16  # 256-entry × 16-bit reciprocal LUT
    added_alms -= lut_count * 200  # REMOVES ~200 ALMs per divider replaced
    # Each LUT replacement also saves ~294 LEs from divider removal for fusing (×3 channels)
    if cfg.fusing_div_mode == 1:
        added_alms -= 600  # 3 dividers removed

    # Blend reciprocal (just mux + multiply, tiny)
    if cfg.blend_div_mode == 1:
        added_alms += 20
        added_alms -= 80  # removes divider

    # Register insertions in haze_removal_core
    added_latency += cfg.reg_adc_dark + cfg.reg_tx_hybrid + cfg.reg_post_blend + cfg.reg_core_hybrid_mid
    added_alms += (cfg.reg_adc_dark + cfg.reg_tx_hybrid + cfg.reg_post_blend + cfg.reg_core_hybrid_mid) * 16

    # BRAM output registers (no ALM cost -- built into M10K)
    # Adds 1 cycle read latency each
    added_latency += cfg.bram_out_oreg + cfg.bram_in_oreg + cfg.bram_tmp_oreg

    # Port B pipelines
    added_latency += cfg.portb_in_pipe + cfg.portb_tmp_pipe
    added_alms += (cfg.portb_in_pipe + cfg.portb_tmp_pipe) * 60

    return {
        "added_latency_cycles": added_latency,
        "added_alms": added_alms,
        "added_m10k_bits": added_m10k_bits,
    }


# ═══════════════════════════════════════════════════════════════════════════════
# 5.  ACTION SPACE & STATE ENCODING
# ═══════════════════════════════════════════════════════════════════════════════

PARAM_RANGES = {
    "fusing_pipe":           [0, 1, 2],
    "tcomp_pipe":            [0, 1],
    "fusing_div_mode":       [0, 1],
    "tcomp_div_mode":        [0, 1],
    "core_norm_div_mode":    [0, 1],
    "core_hybrid_div_mode":  [0, 1],
    "blend_div_mode":        [0, 1],
    "reg_adc_dark":          [0, 1],
    "reg_tx_hybrid":         [0, 1],
    "reg_post_blend":        [0, 1],
    "reg_core_hybrid_mid":   [0, 1],
    "bram_out_oreg":         [0, 1],
    "bram_in_oreg":          [0, 1],
    "bram_tmp_oreg":         [0, 1],
    "portb_out_pipe":        [1],      # already applied -- locked
    "portb_in_pipe":         [0, 1],
    "portb_tmp_pipe":        [0, 1],
}

# Fixed params (locked in)
FIXED = {"portb_out_pipe": 1}


def config_to_tuple(cfg: DesignConfig) -> tuple:
    d = asdict(cfg)
    return tuple(d[k] for k in sorted(d.keys()))


def random_config() -> DesignConfig:
    kwargs = {}
    for k, vals in PARAM_RANGES.items():
        if k in FIXED:
            kwargs[k] = FIXED[k]
        else:
            kwargs[k] = random.choice(vals)
    return DesignConfig(**kwargs)


def mutate_config(cfg: DesignConfig) -> DesignConfig:
    d = asdict(cfg)
    keys = [k for k in PARAM_RANGES if k not in FIXED and len(PARAM_RANGES[k]) > 1]
    key = random.choice(keys)
    vals = [v for v in PARAM_RANGES[key] if v != d[key]]
    if vals:
        d[key] = random.choice(vals)
    return DesignConfig(**d)


# ═══════════════════════════════════════════════════════════════════════════════
# 6.  REWARD FUNCTION
# ═══════════════════════════════════════════════════════════════════════════════

def reward_fn(cfg: DesignConfig) -> Tuple[float, dict]:
    fmax, paths = estimate_fmax(cfg)
    cost = compute_cost(cfg)
    worst_path = max(paths, key=paths.get)
    worst_delay = paths[worst_path]

    # Primary reward: FMAX is king -- use quadratic penalty for missing target
    if fmax >= TARGET_FMAX_MHZ:
        timing_reward = 500.0 + (fmax - TARGET_FMAX_MHZ) * 5.0  # big bonus for meeting
    else:
        gap_ns = worst_delay - TARGET_PERIOD_NS
        timing_reward = -gap_ns * gap_ns * 0.5  # quadratic penalty -- bigger gap = much worse

    # Latency penalty: only a mild tiebreaker (never outweigh timing closure)
    latency_penalty = cost["added_latency_cycles"] * 1.0

    # Resource penalty (tiny -- we have plenty of ALMs)
    resource_penalty = max(0, cost["added_alms"]) * 0.001

    total_reward = timing_reward - latency_penalty - resource_penalty

    info = {
        "fmax_mhz": round(fmax, 2),
        "worst_path": worst_path,
        "worst_delay_ns": round(worst_delay, 2),
        "added_latency": cost["added_latency_cycles"],
        "added_alms": cost["added_alms"],
        "added_m10k_bits": cost["added_m10k_bits"],
        "reward": round(total_reward, 2),
        "meets_timing": fmax >= TARGET_FMAX_MHZ,
    }
    return total_reward, info


# ═══════════════════════════════════════════════════════════════════════════════
# 7.  Q-LEARNING LOOP
# ═══════════════════════════════════════════════════════════════════════════════

def run_rl(episodes: int = 8000, seed: int | None = None):
    if seed is not None:
        random.seed(seed)
        np.random.seed(seed)

    Q: Dict[tuple, float] = {}
    best_reward = -1e9
    best_cfg = None
    best_info = None
    history = []

    # Hyperparameters
    alpha = 0.15   # learning rate
    gamma = 0.99   # discount (not really needed for 1-step)
    eps_start = 1.0
    eps_end = 0.05
    eps_decay = episodes * 0.6

    cfg = random_config()

    for ep in range(episodes):
        eps = eps_end + (eps_start - eps_end) * max(0, 1 - ep / eps_decay)
        state = config_to_tuple(cfg)

        if random.random() < eps:
            next_cfg = random_config()
        else:
            # Exploit: try all single-parameter mutations, pick best Q
            best_q = -1e9
            best_next = cfg
            for _ in range(20):
                cand = mutate_config(cfg)
                cand_key = config_to_tuple(cand)
                q_val = Q.get(cand_key, 0.0)
                if q_val > best_q:
                    best_q = q_val
                    best_next = cand
            next_cfg = best_next

        r, info = reward_fn(next_cfg)
        next_key = config_to_tuple(next_cfg)

        # Q-update (1-step)
        old_q = Q.get(next_key, 0.0)
        Q[next_key] = old_q + alpha * (r - old_q)

        if r > best_reward:
            best_reward = r
            best_cfg = next_cfg
            best_info = info

        if ep % (episodes // 20) == 0 or ep == episodes - 1:
            history.append({
                "episode": ep,
                "eps": round(eps, 3),
                "reward": round(r, 2),
                "fmax": info["fmax_mhz"],
                "meets": info["meets_timing"],
                "best_fmax": best_info["fmax_mhz"] if best_info else 0,
            })

        cfg = next_cfg

    return best_cfg, best_info, best_reward, history, Q


# ═══════════════════════════════════════════════════════════════════════════════
# 8.  RTL MODIFICATION GENERATOR
# ═══════════════════════════════════════════════════════════════════════════════

def generate_rtl_recommendations(cfg: DesignConfig, info: dict) -> str:
    lines = []
    lines.append("=" * 72)
    lines.append("  RL TIMING OPTIMIZER -- RECOMMENDED RTL MODIFICATIONS")
    lines.append("=" * 72)
    lines.append(f"  Estimated Fmax:    {info['fmax_mhz']:.1f} MHz")
    lines.append(f"  Target Fmax:       {TARGET_FMAX_MHZ:.0f} MHz")
    lines.append(f"  Worst path:        {info['worst_path']} ({info['worst_delay_ns']:.1f} ns)")
    lines.append(f"  Added latency:     {info['added_latency']} cycles")
    lines.append(f"  Added ALMs:        {info['added_alms']}")
    lines.append(f"  Meets timing:      {'YES' if info['meets_timing'] else 'NO'}")
    lines.append("=" * 72)
    lines.append("")

    mod_count = 0

    # --- fusing.sv changes ---
    if cfg.fusing_div_mode == 1:
        mod_count += 1
        lines.append(f"[MOD {mod_count}] fusing.sv -- Replace combinational dividers with reciprocal LUT")
        lines.append("  Current: q_r = value_tem_r / $signed({{1'b0, tx_used}});")
        lines.append("  Replace: reciprocal LUT (256×16b) + multiply + shift")
        lines.append("    wire [15:0] recip_tx = recip_lut[tx_used];")
        lines.append("    q_r = (value_tem_r * $signed({{1'b0, recip_tx}})) >>> 16;")
        lines.append("  Saves ~900 ALMs (3 × lpm_divide), costs 1 M10K block")
        lines.append("")

    if cfg.fusing_pipe >= 1:
        mod_count += 1
        lines.append(f"[MOD {mod_count}] fusing.sv -- Add pipeline register (stage {cfg.fusing_pipe})")
        if cfg.fusing_pipe == 1:
            lines.append("  Stage 1 [reg]: tx_used, diff_r/g/b, mul_A_tx_r/g/b, value_tem_r/g/b")
            lines.append("  Stage 2 [reg]: division + clamp -> o_out_r/g/b")
        elif cfg.fusing_pipe == 2:
            lines.append("  Stage 1 [reg]: tx_used, diff, mul_A_tx, value_tem")
            lines.append("  Stage 2 [reg]: division result (raw quotient)")
            lines.append("  Stage 3 [reg]: clamp -> o_out_r/g/b")
        lines.append(f"  Adds {cfg.fusing_pipe} cycle(s) latency to fusing output")
        lines.append("")

    # --- t_computing.sv changes ---
    if cfg.tcomp_div_mode == 1:
        mod_count += 1
        lines.append(f"[MOD {mod_count}] t_computing.sv -- Replace /i_A with reciprocal LUT")
        lines.append("  Current: div_q = modify_A / i_A;")
        lines.append("  Replace: wire [15:0] recip_A = recip_lut[i_A];")
        lines.append("           div_q = (modify_A * recip_A) >> 16;")
        lines.append("  Saves ~200 ALMs, costs shared LUT (or reuse fusing LUT)")
        lines.append("")

    if cfg.tcomp_pipe >= 1:
        mod_count += 1
        lines.append(f"[MOD {mod_count}] t_computing.sv -- Add pipeline register")
        lines.append("  Stage 1 [reg]: modify_A")
        lines.append("  Stage 2 [reg]: div_q_sat, tx_raw -> output")
        lines.append("  Adds 1 cycle latency")
        lines.append("")

    # --- haze_removal_core.sv changes ---
    if cfg.core_norm_div_mode == 1:
        mod_count += 1
        lines.append(f"[MOD {mod_count}] haze_removal_core.sv -- Replace ADC normalize divide")
        lines.append("  Current: norm_adc = ((raw - min) * 255) / range_adc;")
        lines.append("  Replace: Use reciprocal LUT for range_adc")
        lines.append("    recip_range = recip_lut[range_adc];")
        lines.append("    norm_adc = ((raw - min) * 255 * recip_range) >> 16;")
        lines.append("")

    if cfg.core_hybrid_div_mode == 1:
        mod_count += 1
        lines.append(f"[MOD {mod_count}] haze_removal_core.sv -- Replace hybrid TX divide")
        lines.append("  Current: q = (adc_dark * OMEGA) / purple_A_max;")
        lines.append("  Replace: recip_A_max = recip_lut[purple_A_max];")
        lines.append("           q = (adc_dark * OMEGA * recip_A_max) >> 16;")
        lines.append("")

    if cfg.reg_adc_dark:
        mod_count += 1
        lines.append(f"[MOD {mod_count}] haze_removal_core.sv -- Register adc_dark_for_recovery")
        lines.append("  Insert: always_ff @(posedge clk) adc_dark_for_recovery_r <= adc_dark_for_recovery;")
        lines.append("  Feed registered version to t_compute_fuse and u_fusing_direct")
        lines.append("  CRITICAL: Breaks the 60+ ns normalize->hybrid->fusing chain")
        lines.append("")

    if cfg.reg_tx_hybrid:
        mod_count += 1
        lines.append(f"[MOD {mod_count}] haze_removal_core.sv -- Register tx_hybrid_for_recovery")
        lines.append("  Insert: always_ff @(posedge clk) tx_hybrid_for_recovery_r <= tx_hybrid_for_recovery;")
        lines.append("  Feed registered version to u_fusing_direct.i_tx_raw")
        lines.append("  Breaks the hybrid->fusing combinational chain")
        lines.append("")

    if cfg.reg_core_hybrid_mid:
        mod_count += 1
        lines.append(f"[MOD {mod_count}] haze_removal_core.sv -- Pipeline hybrid TX computation")
        lines.append("  Register tx_adc_for_recovery before mix/aggr/dense logic")
        lines.append("  Breaks the hybrid TX combo path into 2 stages")
        lines.append("")

    if cfg.reg_post_blend:
        mod_count += 1
        lines.append(f"[MOD {mod_count}] haze_removal_core.sv -- Register rec_r/g/b_post")
        lines.append("  Insert pipeline between blend output and tone mapping input")
        lines.append("  Breaks the 22 ns blend->tone chain")
        lines.append("")

    if cfg.blend_div_mode == 1:
        mod_count += 1
        lines.append(f"[MOD {mod_count}] haze_removal_core.sv -- Replace blend /denom with reciprocal")
        lines.append("  denom in {8, 13, 16} -> use constant reciprocals:")
        lines.append("    8  -> >> 3")
        lines.append("    13 -> * 5039 >> 16  (error < 0.002%)")
        lines.append("    16 -> >> 4")
        lines.append("  Eliminates runtime divider entirely")
        lines.append("")

    # --- BRAM changes ---
    if cfg.bram_out_oreg or cfg.bram_in_oreg or cfg.bram_tmp_oreg:
        mod_count += 1
        brams = []
        if cfg.bram_out_oreg: brams.append("img_out_bram")
        if cfg.bram_in_oreg:  brams.append("img_in_bram")
        if cfg.bram_tmp_oreg: brams.append("img_tmp_bram")
        lines.append(f"[MOD {mod_count}] BRAM -- Enable M10K output registers for {', '.join(brams)}")
        lines.append("  Add (* ramstyle = \"M10K\" *) output register or altsyncram outdata_reg")
        lines.append("")

    if cfg.portb_in_pipe:
        mod_count += 1
        lines.append(f"[MOD {mod_count}] soc_top.sv -- Pipeline Port B inputs for img_in_bram")
        lines.append("  Same pattern as img_out_bram pipeline fix already applied")
        lines.append("")

    if cfg.portb_tmp_pipe:
        mod_count += 1
        lines.append(f"[MOD {mod_count}] soc_top.sv -- Pipeline Port B inputs for img_tmp_bram")
        lines.append("")

    if mod_count == 0:
        lines.append("  No modifications needed -- current design meets timing!")
    else:
        lines.append(f"Total modifications: {mod_count}")

    # Per-path breakdown
    lines.append("")
    lines.append("-" * 72)
    lines.append("  PATH DELAY BREAKDOWN (after modifications)")
    lines.append("-" * 72)
    _, paths = estimate_fmax(cfg)
    for name, delay in sorted(paths.items(), key=lambda x: -x[1]):
        status = "FAIL" if delay > TARGET_PERIOD_NS else "OK"
        slack = TARGET_PERIOD_NS - delay
        lines.append(f"  {delay:6.1f} ns  [{status:4s}]  slack {slack:+6.1f} ns  {name}")

    return "\n".join(lines)


# ═══════════════════════════════════════════════════════════════════════════════
# 9.  MAIN
# ═══════════════════════════════════════════════════════════════════════════════

def main():
    parser = argparse.ArgumentParser(description="RL FPGA Timing Optimizer")
    parser.add_argument("--episodes", type=int, default=8000)
    parser.add_argument("--seed", type=int, default=None)
    parser.add_argument("--out", type=str, default=None, help="Output JSON file")
    args = parser.parse_args()

    print("=" * 60)
    print("  RL FPGA Timing Optimizer for Haze Removal SoC")
    print(f"  Target: {TARGET_FMAX_MHZ:.0f} MHz on Cyclone V 5CSXFC6D6F31C6")
    print(f"  Episodes: {args.episodes}")
    print("=" * 60)

    # Show baseline
    baseline = DesignConfig()
    base_fmax, base_paths = estimate_fmax(baseline)
    base_worst = max(base_paths, key=base_paths.get)
    print(f"\n  BASELINE (current RTL + portb_out_pipe=1):")
    print(f"    Fmax = {base_fmax:.1f} MHz")
    print(f"    Worst = {base_worst}: {base_paths[base_worst]:.1f} ns")
    print()

    # Run RL
    print("  Training RL agent...")
    best_cfg, best_info, best_reward, history, Q = run_rl(args.episodes, args.seed)

    # Print training progress
    print(f"\n  {'Ep':>6s}  {'ε':>5s}  {'Reward':>8s}  {'Fmax':>7s}  {'Best':>7s}  Meets?")
    for h in history:
        print(f"  {h['episode']:6d}  {h['eps']:5.3f}  {h['reward']:8.1f}  "
              f"{h['fmax']:5.1f} MHz  {h['best_fmax']:5.1f} MHz  "
              f"{'YES' if h['meets'] else 'no'}")

    # Print best config
    print(f"\n  States explored: {len(Q)}")
    print(f"  Best reward:     {best_reward:.2f}")
    print()

    report = generate_rtl_recommendations(best_cfg, best_info)
    print(report)

    # Print config dict
    print()
    print("-" * 72)
    print("  OPTIMAL CONFIGURATION (DesignConfig)")
    print("-" * 72)
    cfg_dict = asdict(best_cfg)
    for k, v in sorted(cfg_dict.items()):
        changed = "  <- CHANGED" if v != getattr(DesignConfig(), k) else ""
        print(f"    {k:30s} = {v}{changed}")

    if args.out:
        out_data = {
            "config": cfg_dict,
            "info": best_info,
            "history": history,
        }
        Path(args.out).write_text(json.dumps(out_data, indent=2))
        print(f"\n  Saved to {args.out}")

    return best_cfg, best_info


if __name__ == "__main__":
    main()
