#!/usr/bin/env python3
"""Parse ALL Quartus compilation stages and produce a unified status report.

Scans the Quartus output_files directory for map/fit/asm/sta reports.
Prints a table of errors, critical warnings, and warnings per stage,
plus FMAX from STA if available, resource usage from fitter, and overall
success/failure.

Usage:
    python update_status.py
    python update_status.py --report-dir ../thesis/output_files
    python update_status.py --write-json status.json
"""

import argparse
import json
import os
import re
import sys
from collections import OrderedDict
from datetime import datetime

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_REPORT_DIR = os.path.normpath(
    os.path.join(SCRIPT_DIR, "..", "thesis", "output_files")
)
DEFAULT_REVISION = "thesis_v1"

# ---------------------------------------------------------------------------
# Regex helpers
# ---------------------------------------------------------------------------
RE_ERROR = re.compile(r"\bError(?:\s*\(\d+\))?:", re.IGNORECASE)
RE_CRIT  = re.compile(r"\bCritical\s+Warning(?:\s*\(\d+\))?:", re.IGNORECASE)
RE_WARN  = re.compile(r"\bWarning(?:\s*\(\d+\))?:", re.IGNORECASE)

RE_SUMMARY = re.compile(
    r"(successful|unsuccessful)\.\s*(\d+)\s+error[s]?,\s*(\d+)\s+warning[s]?",
    re.IGNORECASE,
)

# Fitter resource usage
RE_ALM = re.compile(
    r";\s*Logic utilization\s*\(in ALMs\)\s*;\s*([\d,]+)\s*/\s*([\d,]+)", re.IGNORECASE
)
RE_REG = re.compile(
    r";\s*Total registers\s*;\s*([\d,]+)", re.IGNORECASE
)
RE_M10K = re.compile(
    r";\s*Total block memory bits\s*;\s*([\d,]+)\s*/\s*([\d,]+)", re.IGNORECASE
)
RE_DSP = re.compile(
    r";\s*Total DSP Blocks\s*;\s*([\d,]+)\s*/\s*([\d,]+)", re.IGNORECASE
)
RE_PLL = re.compile(
    r";\s*Total PLLs\s*;\s*([\d,]+)\s*/\s*([\d,]+)", re.IGNORECASE
)

# STA Fmax — matches table rows: ; 5.39 MHz ; 5.39 MHz ; CLOCK_50 ; ;
RE_FMAX_ROW = re.compile(
    r";\s*([\d.]+)\s+MHz\s*;\s*[\d.]+\s+MHz\s*;\s*(\S+)\s*;",
)
# Section header: "Slow 1100mV 85C Model Fmax Summary"
RE_FMAX_SECTION = re.compile(
    r"(Slow\s+\d+\s*mV\s+\S+)\s+Model\s+Fmax\s+Summary", re.IGNORECASE
)

STAGES = ["map", "fit", "asm", "sta"]


def read_text(path: str) -> str:
    if not path or not os.path.isfile(path):
        return ""
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        return f.read()


def count_messages(text: str) -> dict:
    errors = crits = warns = 0
    for line in text.splitlines():
        if RE_ERROR.search(line):
            errors += 1
        if RE_CRIT.search(line):
            crits += 1
        if RE_WARN.search(line):
            warns += 1
    return {"error": errors, "critical_warning": crits, "warning": warns}


def extract_summary(text: str) -> dict | None:
    m = RE_SUMMARY.search(text)
    if not m:
        return None
    return {
        "result": m.group(1).lower(),
        "errors": int(m.group(2)),
        "warnings": int(m.group(3)),
    }


def _decom(s: str) -> int:
    return int(s.replace(",", ""))


def extract_resources(text: str) -> dict:
    res = {}
    m = RE_ALM.search(text)
    if m:
        res["alm_used"] = _decom(m.group(1))
        res["alm_total"] = _decom(m.group(2))
    m = RE_REG.search(text)
    if m:
        res["registers"] = _decom(m.group(1))
    m = RE_M10K.search(text)
    if m:
        res["m10k_bits_used"] = _decom(m.group(1))
        res["m10k_bits_total"] = _decom(m.group(2))
    m = RE_DSP.search(text)
    if m:
        res["dsp_used"] = _decom(m.group(1))
        res["dsp_total"] = _decom(m.group(2))
    m = RE_PLL.search(text)
    if m:
        res["pll_used"] = _decom(m.group(1))
        res["pll_total"] = _decom(m.group(2))
    return res


def extract_fmax(text: str) -> list:
    """Return list of {corner, clock, fmax_mhz} from STA Fmax Summary tables."""
    clocks = []
    current_corner = ""
    for line in text.splitlines():
        ms = RE_FMAX_SECTION.search(line)
        if ms:
            current_corner = ms.group(1).strip()
        m = RE_FMAX_ROW.search(line)
        if m:
            clocks.append({
                "corner": current_corner,
                "fmax_mhz": float(m.group(1)),
                "clock": m.group(2),
            })
    return clocks


def build_status(report_dir: str, revision: str) -> dict:
    stage_status = OrderedDict()
    overall_success = True

    for stage in STAGES:
        rpt_path = os.path.join(report_dir, f"{revision}.{stage}.rpt")
        text = read_text(rpt_path)
        if not text:
            stage_status[stage] = {"exists": False}
            continue

        counts = count_messages(text)
        summary = extract_summary(text)
        entry = {
            "exists": True,
            "report": rpt_path,
            "counts": counts,
            "summary": summary,
        }

        if stage == "fit":
            entry["resources"] = extract_resources(text)
        if stage == "sta":
            entry["fmax"] = extract_fmax(text)

        if summary and summary["errors"] > 0:
            overall_success = False
        if not summary:
            overall_success = False

        stage_status[stage] = entry

    return {
        "revision": revision,
        "report_dir": report_dir,
        "timestamp": datetime.now().isoformat(timespec="seconds"),
        "stages": stage_status,
        "overall_success": overall_success,
    }


def print_status(status: dict) -> None:
    print("=" * 65)
    print(f"  Quartus Compilation Status — {status['revision']}")
    print(f"  Report dir: {status['report_dir']}")
    print(f"  Timestamp : {status['timestamp']}")
    print("=" * 65)

    hdr = f"{'Stage':<6} {'Result':<14} {'Errors':>6} {'CritWarn':>8} {'Warns':>6}"
    print(hdr)
    print("-" * len(hdr))

    for stage, info in status["stages"].items():
        if not info.get("exists"):
            print(f"{stage:<6} {'— not found —':<14}")
            continue
        s = info.get("summary")
        result = s["result"] if s else "?"
        e = info["counts"]["error"]
        c = info["counts"]["critical_warning"]
        w = info["counts"]["warning"]
        print(f"{stage:<6} {result:<14} {e:>6} {c:>8} {w:>6}")

    # Resources (from fitter)
    fit = status["stages"].get("fit", {})
    res = fit.get("resources", {})
    if res:
        print()
        print("Resource Usage:")
        if "alm_used" in res:
            pct = 100.0 * res["alm_used"] / res["alm_total"] if res["alm_total"] else 0
            print(f"  ALMs       : {res['alm_used']:>8,} / {res['alm_total']:>8,}  ({pct:.1f}%)")
        if "registers" in res:
            print(f"  Registers  : {res['registers']:>8,}")
        if "m10k_bits_used" in res:
            pct = 100.0 * res["m10k_bits_used"] / res["m10k_bits_total"] if res["m10k_bits_total"] else 0
            print(f"  M10K bits  : {res['m10k_bits_used']:>8,} / {res['m10k_bits_total']:>8,}  ({pct:.1f}%)")
        if "dsp_used" in res:
            print(f"  DSP blocks : {res['dsp_used']:>8,} / {res['dsp_total']:>8,}")
        if "pll_used" in res:
            print(f"  PLLs       : {res['pll_used']:>8,} / {res['pll_total']:>8,}")

    # Fmax (from STA)
    sta = status["stages"].get("sta", {})
    fmax_list = sta.get("fmax", [])
    if fmax_list:
        print()
        print("Fmax Summary:")
        for entry in fmax_list:
            corner = entry.get('corner', '')
            print(f"  [{corner}]  {entry['clock']:<20s}  {entry['fmax_mhz']:.2f} MHz")

    print()
    if status["overall_success"]:
        print(">>> OVERALL: SUCCESS <<<")
    else:
        print(">>> OVERALL: FAILED  <<<")
    print()


def main():
    parser = argparse.ArgumentParser(
        description="Unified Quartus compilation status parser."
    )
    parser.add_argument(
        "--report-dir", default=DEFAULT_REPORT_DIR,
        help="Quartus output_files directory",
    )
    parser.add_argument(
        "--revision", default=DEFAULT_REVISION,
        help="Quartus revision name",
    )
    parser.add_argument(
        "--write-json", default=None,
        help="Write status to JSON file",
    )
    args = parser.parse_args()

    report_dir = args.report_dir
    if not os.path.isabs(report_dir):
        report_dir = os.path.normpath(os.path.join(SCRIPT_DIR, report_dir))

    status = build_status(report_dir, args.revision)
    print_status(status)

    if args.write_json:
        out_path = args.write_json
        if not os.path.isabs(out_path):
            out_path = os.path.normpath(os.path.join(SCRIPT_DIR, out_path))
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(status, f, indent=2, ensure_ascii=False)
        print(f"JSON written to: {out_path}")


if __name__ == "__main__":
    main()
