#!/usr/bin/env python3
import argparse
import glob
import json
import os
import re
import subprocess
import time
from collections import Counter

PATTERNS = {
    "error": re.compile(r"\bError(?:\s*\(\d+\))?:", re.IGNORECASE),
    "critical_warning": re.compile(r"\bCritical\s+Warning(?:\s*\(\d+\))?:", re.IGNORECASE),
    "warning": re.compile(r"\bWarning(?:\s*\(\d+\))?:", re.IGNORECASE),
}

QMSG_PATTERNS = {
    "error": re.compile(r'\{\s*"Error"', re.IGNORECASE),
    "critical_warning": re.compile(r'\{\s*"Critical Warning"', re.IGNORECASE),
    "warning": re.compile(r'\{\s*"Warning"', re.IGNORECASE),
}

SUMMARY_RE = re.compile(
    r"unsuccessful\.\s*(\d+)\s+error[s]?,\s*(\d+)\s+warning[s]?",
    re.IGNORECASE,
)


def read_text(path):
    if not path or not os.path.exists(path):
        return ""
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        return f.read()


def latest_log(default_glob):
    files = glob.glob(default_glob)
    if not files:
        return None
    files.sort(key=os.path.getmtime, reverse=True)
    return files[0]


def count_messages(text):
    counts = Counter()
    for line in text.splitlines():
        if PATTERNS["error"].search(line):
            counts["error"] += 1
        if PATTERNS["critical_warning"].search(line):
            counts["critical_warning"] += 1
        if PATTERNS["warning"].search(line):
            counts["warning"] += 1
    return counts


def count_qmsg_messages(text):
    counts = Counter()
    for line in text.splitlines():
        if QMSG_PATTERNS["error"].search(line):
            counts["error"] += 1
        if QMSG_PATTERNS["critical_warning"].search(line):
            counts["critical_warning"] += 1
        if QMSG_PATTERNS["warning"].search(line):
            counts["warning"] += 1
    return counts


def extract_summary(text):
    m = SUMMARY_RE.search(text)
    if not m:
        return None
    return {"errors": int(m.group(1)), "warnings": int(m.group(2))}


def is_quartus_map_running():
    try:
        if os.name == "nt":
            proc = subprocess.run(
                ["tasklist", "/FI", "IMAGENAME eq quartus_map.exe"],
                capture_output=True,
                text=True,
                check=False,
            )
            out = (proc.stdout or "") + (proc.stderr or "")
            return "quartus_map.exe" in out.lower()
        proc = subprocess.run(
            ["ps", "-A"],
            capture_output=True,
            text=True,
            check=False,
        )
        out = (proc.stdout or "") + (proc.stderr or "")
        return "quartus_map" in out
    except Exception:
        return False


def main():
    parser = argparse.ArgumentParser(description="Parse Quartus log/report and print compact status.")
    parser.add_argument("--log", default=None, help="Path to Quartus command log")
    parser.add_argument("--report-dir", default="../06_FGPA_Imple/thesis/output_files", help="Quartus output_files directory")
    parser.add_argument("--revision", default="thesis_v1", help="Quartus revision name")
    parser.add_argument("--write-json", default=None, help="Write parsed status to JSON file")
    parser.add_argument("--watch", action="store_true", help="Watch mode: refresh status periodically")
    parser.add_argument("--interval", type=float, default=2.0, help="Watch polling interval (seconds)")
    args = parser.parse_args()

    script_dir = os.path.dirname(os.path.abspath(__file__))

    def build_status():
        log_path = args.log
        if not log_path:
            log_path = latest_log(os.path.join(script_dir, "log", "quartus_*.log"))

        report_dir = args.report_dir
        if not os.path.isabs(report_dir):
            report_dir = os.path.abspath(os.path.join(script_dir, report_dir))

        map_rpt = os.path.join(report_dir, f"{args.revision}.map.rpt")
        flow_rpt = os.path.join(report_dir, f"{args.revision}.flow.rpt")
        qmsg = os.path.abspath(os.path.join(report_dir, "..", "db", f"{args.revision}.map.qmsg"))

        log_text = read_text(log_path)
        map_text = read_text(map_rpt)
        flow_text = read_text(flow_rpt)
        qmsg_text = read_text(qmsg)

        log_counts = count_messages(log_text)
        map_counts = count_messages(map_text)
        qmsg_counts = count_qmsg_messages(qmsg_text)

        summary = extract_summary(log_text) or extract_summary(map_text) or extract_summary(flow_text)
        qmsg_started = '"IQEXE_START_BANNER_TIME"' in qmsg_text
        qmsg_finished = '"IQEXE_END_BANNER_TIME"' in qmsg_text
        in_progress = (qmsg_started and not qmsg_finished and is_quartus_map_running())

        return {
            "log": log_path,
            "map_report": map_rpt if os.path.exists(map_rpt) else None,
            "flow_report": flow_rpt if os.path.exists(flow_rpt) else None,
            "qmsg": qmsg if os.path.exists(qmsg) else None,
            "log_counts": dict(log_counts),
            "map_counts": dict(map_counts),
            "qmsg_counts": dict(qmsg_counts),
            "summary": summary,
            "in_progress": in_progress,
            "success": bool(summary and summary["errors"] == 0 and not in_progress),
        }

    def print_status(status):
        log_counts = status["log_counts"]
        summary = status["summary"]
        print("=== Quartus Status ===")
        print(f"log: {status['log']}")
        print(f"map report: {status['map_report']}")
        print(f"flow report: {status['flow_report']}")
        print(f"qmsg: {status.get('qmsg')}")
        print(f"in_progress: {status.get('in_progress')}" )
        if summary:
            print(f"summary: errors={summary['errors']}, warnings={summary['warnings']}")
        else:
            print("summary: not found in logs/reports")
        print(
            "log counts: "
            f"error={log_counts.get('error', 0)}, "
            f"critical_warning={log_counts.get('critical_warning', 0)}, "
            f"warning={log_counts.get('warning', 0)}"
        )
        qc = status.get("qmsg_counts", {})
        print(
            "qmsg counts: "
            f"error={qc.get('error', 0)}, "
            f"critical_warning={qc.get('critical_warning', 0)}, "
            f"warning={qc.get('warning', 0)}"
        )

    if args.watch:
        try:
            while True:
                status = build_status()
                os.system("cls" if os.name == "nt" else "clear")
                print_status(status)
                if status["summary"]:
                    print("watch: summary detected, stopping.")
                    break
                print(f"watch: refresh every {args.interval:.1f}s (Ctrl+C to stop)")
                time.sleep(args.interval)
        except KeyboardInterrupt:
            pass
    else:
        status = build_status()
        print_status(status)

    if args.write_json:
        out = args.write_json
        if not os.path.isabs(out):
            out = os.path.abspath(os.path.join(script_dir, out))
        with open(out, "w", encoding="utf-8") as f:
            json.dump(status, f, indent=2)
        print(f"json: {out}")


if __name__ == "__main__":
    main()
