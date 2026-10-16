#!/usr/bin/env python3
"""Reduce interleaved bench samples to a results document, a log line per metric, and the trend table."""

import argparse
import glob
import json
import math
import os
import platform
import sys
from collections import defaultdict


REGRESSION_FAIL = 0.20
REGRESSION_WARN = 0.10


def percentile(sorted_values, fraction):
    count = len(sorted_values)
    rank = max(1, math.ceil(fraction * count))
    return sorted_values[rank - 1]


def median(sorted_values):
    count = len(sorted_values)
    mid = count // 2
    if count % 2:
        return sorted_values[mid]
    return (sorted_values[mid - 1] + sorted_values[mid]) / 2.0


def fmt_value(value, unit):
    if unit == "s":
        magnitude = abs(value)
        if magnitude < 1e-4:
            return "%.3fus" % (value * 1e6)
        if magnitude < 1.0:
            return "%.3fms" % (value * 1e3)
        return "%.3fs" % value
    if unit == "B":
        magnitude = abs(value)
        if magnitude >= 1048576.0:
            return "%.3fMB" % (value / 1048576.0)
        if magnitude >= 1024.0:
            return "%.3fKB" % (value / 1024.0)
        return "%.0fB" % value
    return str(value)


def fmt_delta(ratio):
    if ratio is None:
        return "n/a"
    return "%+.1f%%" % (ratio * 100.0)


def load_json(path):
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def judged(spec, stats):
    if spec["stat"] == "p95":
        return stats["p95"]
    return stats["median"]


def ratio(head, base):
    if base is None or head is None:
        return None
    if base == 0:
        return None if head != 0 else 0.0
    return (head - base) / float(base)


def summarize(rows):
    values = sorted(float(row["value"]) for row in rows)
    checksums = [str(row.get("checksum", "")) for row in rows]
    dirties = []
    for row in rows:
        extra = row.get("extra") or {}
        if "dirty" in extra and row.get("phase") == "sample":
            dirties.append(int(extra["dirty"]))
    return {
        "checksums": checksums,
        "dirty_median": median(sorted(dirties)) if dirties else None,
        "median": median(values),
        "p95": percentile(values, 0.95),
        "values": values,
    }


def metric_rows(samples, name):
    grouped = {"head": [], "base": []}
    for row in samples:
        if row.get("metric") != name:
            continue
        build = row.get("build", "head")
        if build in grouped:
            grouped[build].append(row)
    return grouped


def decide(spec, head, base, mode):
    reasons = []
    verdict = "pass"
    head_rows = [row for row in head["checksums"]]
    if len(set(head_rows)) > 1:
        verdict = "fail"
        reasons.append("determinism")
    if base is not None and len(set(base["checksums"])) > 1:
        verdict = "fail"
        if "determinism" not in reasons:
            reasons.append("determinism")
    head_stat = judged(spec, head)
    base_stat = judged(spec, base) if base is not None else None
    delta = ratio(head_stat, base_stat) if base is not None else None
    if base is None:
        if verdict != "fail":
            verdict = "warn"
        reasons.append("no-base")
    elif delta is None:
        if verdict != "fail":
            verdict = "warn"
        reasons.append("zero-base")
    elif delta > REGRESSION_FAIL:
        if mode == "gate":
            verdict = "fail"
        elif verdict != "fail":
            verdict = "warn"
        reasons.append("regression")
    elif delta >= REGRESSION_WARN:
        if verdict != "fail":
            verdict = "warn"
        reasons.append("regression")
    if head_stat > float(spec["budget"]):
        if verdict != "fail":
            verdict = "warn"
        reasons.append("budget")
    return verdict, reasons, delta, head_stat


def build_report(args, prepare, samples):
    catalog = prepare["metrics"]
    metrics = []
    worst = 0
    for spec in catalog:
        grouped = metric_rows(samples, spec["name"])
        head_samples = [row for row in grouped["head"] if row.get("phase") == "sample"]
        base_samples = [row for row in grouped["base"] if row.get("phase") == "sample"]
        if not head_samples:
            continue
        published = summarize(head_samples)
        published["checksums"] = [str(row.get("checksum", "")) for row in grouped["head"]]
        base_published = None
        if base_samples:
            base_published = summarize(base_samples)
            base_published["checksums"] = [str(row.get("checksum", "")) for row in grouped["base"]]
        verdict, reasons, delta, _stat = decide(spec, published, base_published, args.mode)
        if verdict == "fail" and "determinism" in reasons:
            worst = max(worst, 2)
        elif verdict == "fail":
            worst = max(worst, 1)
        entry = {
            "budget": spec["budget"],
            "checksum": published["checksums"][0] if len(set(published["checksums"])) == 1 else "",
            "delta": delta,
            "median": published["median"],
            "name": spec["name"],
            "p95": published["p95"],
            "reasons": reasons,
            "samples": published["values"],
            "stat": spec["stat"],
            "unit": spec["unit"],
            "verdict": verdict,
        }
        if published["dirty_median"] is not None:
            entry["dirty_median"] = published["dirty_median"]
        if base_published is not None:
            entry["base_median"] = base_published["median"]
            entry["base_p95"] = base_published["p95"]
        metrics.append(entry)
        line = "perf %s median=%s p95=%s delta=%s verdict=%s" % (
            spec["name"],
            fmt_value(published["median"], spec["unit"]),
            fmt_value(published["p95"], spec["unit"]),
            fmt_delta(delta),
            verdict,
        )
        print(line)
    if not metrics:
        raise SystemExit("no samples to reduce")
    report = {
        "absolute_budgets": "warn",
        "godot": args.godot,
        "metrics": metrics,
        "mode": args.mode,
        "profile": prepare.get("profile", args.profile),
        "runner": {
            "cpu": platform.processor(),
            "github_run_id": os.environ.get("GITHUB_RUN_ID", ""),
            "github_runner": os.environ.get("RUNNER_NAME", ""),
            "os": platform.platform(),
            "python": platform.python_version(),
        },
        "samples": prepare.get("samples"),
        "scale": prepare.get("scale", {}),
        "seed": prepare.get("seed"),
        "tag": args.tag,
        "warmups": prepare.get("warmups"),
        "wyrd": args.wyrd,
    }
    return report, worst


def write_summary(report, path):
    lines = [
        "### Wyrd perf %s" % report["profile"],
        "",
        "| metric | median | p95 | delta vs base | verdict |",
        "| --- | --- | --- | --- | --- |",
    ]
    for row in report["metrics"]:
        lines.append(
            "| `%s` | %s | %s | %s | %s |"
            % (
                row["name"],
                fmt_value(row["median"], row["unit"]),
                fmt_value(row["p95"], row["unit"]),
                fmt_delta(row["delta"]),
                row["verdict"],
            )
        )
    text = "\n".join(lines) + "\n"
    if path:
        existing = ""
        if os.path.exists(path):
            with open(path, "r", encoding="utf-8") as handle:
                existing = handle.read()
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(existing)
            if existing and not existing.endswith("\n"):
                handle.write("\n")
            handle.write(text)
    return None


def write_trend(results_dir, out_path):
    paths = sorted(glob.glob(os.path.join(results_dir, "*.json")))
    docs = []
    for path in paths:
        try:
            docs.append(load_json(path))
        except json.JSONDecodeError:
            continue
    names = []
    units = {}
    if docs:
        for row in docs[0].get("metrics", []):
            names.append(row["name"])
            units[row["name"]] = row.get("unit", "")
    else:
        # Catalog mirrored from bench/perf_scale.gd so an empty trend still lists the metrics.
        catalog = [
            ("compile.strict", "s"),
            ("tick.recheck", "s"),
            ("believes.own", "s"),
            ("believes.group", "s"),
            ("perceive.credibility", "s"),
            ("reputation.cached", "s"),
            ("reputation.cold", "s"),
            ("save.time", "s"),
            ("save.bytes", "B"),
            ("load.time", "s"),
            ("compact.time", "s"),
            ("memory.peak", "B"),
            ("memory.steady", "B"),
        ]
        names = [item[0] for item in catalog]
        units = {item[0]: item[1] for item in catalog}
    tags = []
    for doc in docs:
        tag = doc.get("tag") or ""
        if not tag:
            continue
        tags.append(tag)
    lines = ["# Bench trend", ""]
    if not docs:
        lines.append("No tag results are committed yet. The tag run writes `bench/results/<tag>.json` and regenerates this file.")
        lines.append("")
    lines.append("Medians. `tick.recheck` is the inner-tick p95, then the median of those samples. Absolute budgets warn until they are confirmed.")
    lines.append("")
    header = ["metric", "unit"] + tags
    lines.append("| " + " | ".join(header) + " |")
    lines.append("| " + " | ".join(["---"] * len(header)) + " |")
    for name in names:
        cells = [name, units.get(name, "")]
        for doc in docs:
            found = ""
            for row in doc.get("metrics", []):
                if row.get("name") == name:
                    found = fmt_value(float(row.get("median", 0.0)), row.get("unit", units.get(name, "")))
                    break
            cells.append(found)
        lines.append("| " + " | ".join(cells) + " |")
    lines.append("")
    text = "\n".join(lines)
    with open(out_path, "w", encoding="utf-8") as handle:
        handle.write(text)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--samples")
    parser.add_argument("--prepare")
    parser.add_argument("--mode", choices=("warn", "gate"), default="warn")
    parser.add_argument("--out")
    parser.add_argument("--summary")
    parser.add_argument("--tag", default="")
    parser.add_argument("--wyrd", default="")
    parser.add_argument("--godot", default="")
    parser.add_argument("--profile", default="")
    parser.add_argument("--write-trend", nargs=2, metavar=("RESULTS", "OUT"))
    args = parser.parse_args()
    if args.write_trend:
        write_trend(args.write_trend[0], args.write_trend[1])
        return 0
    if not args.samples or not args.prepare or not args.out:
        parser.error("--samples, --prepare, and --out are required")
    prepare = load_json(args.prepare)
    samples = []
    with open(args.samples, "r", encoding="utf-8") as handle:
        for line in handle:
            row = line.strip()
            if row:
                samples.append(json.loads(row))
    report, code = build_report(args, prepare, samples)
    with open(args.out, "w", encoding="utf-8") as handle:
        json.dump(report, handle, indent=2, sort_keys=True)
        handle.write("\n")
    if args.summary:
        write_summary(report, args.summary)
    return code


if __name__ == "__main__":
    sys.exit(main())
