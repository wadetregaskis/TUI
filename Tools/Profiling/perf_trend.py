#!/usr/bin/env python3
"""
Keep the timed sweep's readings across commits: a CSV in the working notes,
one row per scenario per run, and a report of how each has moved.

    Tools/Profiling/perf_trend.py LOG [--sha SHA] [--csv F]   # append LOG's rows
    Tools/Profiling/perf_trend.py --report [--last N] [--csv F]

LOG is what `ab_bench.py` printed, saved to a file:

    Tools/Profiling/ab_bench.py OLD NEW --cases timed | tee ab.log
    Tools/Profiling/perf_trend.py ab.log --sha "$(git rev-parse --short=9 HEAD)"

Nothing is run again: the rows are read off the log. Each is the NEW binary's
reading of one scenario (a perf case is `session/case:<id>`): its median µs
per frame, the 95% interval of its change against the run's base, and its
peak RSS, with the commit it was built from, this machine's name, the load
the run started at, and the metric (`cpu` or `wall`, `-cold` for `--cold`).

The owner's A-PERFCASE-3 (2026-11-14): the counts' trend is the git history of
`Sources/Stress/Cases/RecordedCounts.txt`, and the timing trend is this CSV in
the working notes, never in the repository, as `.trace` bundles are not.

Where the CSV is: `--csv`, else `$TUI_PERF_TREND_CSV`, else
`~/Documents/TUIkit-session-notes/perf/trend.csv` when that folder exists.
With none of them it writes nothing and says where it would have.

The report prints, per scenario and metric, the last N rows and the change of
the latest median from the first of them, beside the widest interval
half-width among them. That interval is a paired A/B's, from one sitting; two
readings from different days are not paired, and differ by more. So a change
past it is a reason to A/B the two commits, not a finding on its own.

Only the standard library, like the rest of this directory.
"""

import argparse
import csv
import datetime
import os
import re
import socket
import subprocess
import sys

COLUMNS = ["date", "sha", "host", "load", "metric", "scenario", "iterations",
           "median_us", "ci_low_pct", "ci_high_pct", "rss_mb"]

ENVIRONMENT_VARIABLE = "TUI_PERF_TREND_CSV"
DEFAULT_CSV = os.path.expanduser("~/Documents/TUIkit-session-notes/perf/trend.csv")

# `ab_bench.py`'s lines, as it prints them:
#   load 1.23 · busiest: …
#   metric=cpu-per-frame  reps=10  target=4.5s/run  order randomised per rep  COLD (…)
#   <scenario> <iters> <old µs> <new µs> <change>% <low>% <high>%  <verdict>[  ram A->BMB +d][  rows …]
LOAD_RE = re.compile(r"^load (\S+) ")
METRIC_RE = re.compile(r"^metric=(cpu|wall)-per-frame")
FALLBACK_RE = re.compile(r"predates cpu-per-frame")
ROW_RE = re.compile(
    r"^(?P<scenario>\S+)\s+(?P<iterations>\d+)\s+(?P<old>[\d.]+)\s+(?P<new>[\d.]+)\s+"
    r"(?P<change>[+-][\d.]+)%\s+(?P<low>[+-][\d.]+)%\s+(?P<high>[+-][\d.]+)%\s+"
    r"(?P<verdict>faster|slower|indistinguishable)"
    r"(?:\s+ram (?P<old_rss>[\d.]+)->(?P<new_rss>[\d.]+)MB)?")


def parse_ab_bench(text):
    """The run's load and metric, and a row per scenario, from `ab_bench.py`'s
    output: `(load, metric, rows)`, each row a dict of the columns it fills.
    `load` is `None` when the log has no load line."""
    load, metric, cold, fallback = None, None, False, False
    rows = []
    for line in text.splitlines():
        if match := LOAD_RE.match(line):
            load = match.group(1)
        elif match := METRIC_RE.match(line):
            metric = match.group(1)
            cold = "COLD" in line
        elif FALLBACK_RE.search(line):
            fallback = True
        elif match := ROW_RE.match(line):
            rows.append({
                "scenario": match["scenario"],
                "iterations": match["iterations"],
                "median_us": match["new"],
                "ci_low_pct": match["low"],
                "ci_high_pct": match["high"],
                "rss_mb": match["new_rss"] or "",
            })
    # A binary from before `cpu-per-frame` makes `ab_bench.py` fall back to the
    # wall clock after printing `metric=cpu`: those readings are wall time.
    name = ("wall" if fallback else metric or "cpu") + ("-cold" if cold else "")
    return load, name, rows


def csv_path(explicit, environment=None, default=None):
    """The CSV to use, or `None`: `--csv`, then the environment variable,
    then the working notes' file when its folder exists."""
    environment = os.environ if environment is None else environment
    default = default or DEFAULT_CSV
    if explicit:
        return explicit
    if environment.get(ENVIRONMENT_VARIABLE):
        return environment[ENVIRONMENT_VARIABLE]
    if os.path.isdir(os.path.dirname(default)):
        return default
    return None


def read_rows(path):
    """The CSV's rows, oldest first; none when there is no file."""
    if not os.path.exists(path):
        return []
    with open(path, newline="", encoding="utf-8") as file:
        return list(csv.DictReader(file))


def append(path, rows):
    """Appends `rows` to the CSV at `path`, writing its header first if the
    file is new, and leaving out any row it already holds (a log appended
    twice); the rows appended."""
    def key(row):
        return tuple(row.get(column, "") for column in ("sha", "metric", "scenario", "median_us",
                                                         "ci_low_pct", "ci_high_pct"))
    held = {key(row) for row in read_rows(path)}
    fresh = [row for row in rows if key(row) not in held]
    is_new = not os.path.exists(path) or os.path.getsize(path) == 0
    with open(path, "a", newline="", encoding="utf-8") as file:
        writer = csv.DictWriter(file, fieldnames=COLUMNS)
        if is_new:
            writer.writeheader()
        for row in fresh:
            writer.writerow({column: row.get(column, "") for column in COLUMNS})
    return fresh


def report(rows, last=5):
    """Per scenario and metric, in the order each first appears: the last
    `last` rows, and the change of the latest median from the first of them
    beside the widest interval half-width among them. The text, as lines."""
    groups = {}
    for row in rows:
        groups.setdefault((row["scenario"], row["metric"]), []).append(row)
    lines = []
    for (scenario, metric), group in groups.items():
        shown = group[-last:]
        lines.append(f"{scenario}  ({metric})")
        for row in shown:
            ci = f"[{row['ci_low_pct']}%, {row['ci_high_pct']}%]" if row["ci_low_pct"] else ""
            rss = f"{row['rss_mb']} MB" if row["rss_mb"] else ""
            lines.append(f"  {row['date']:<16}  {row['sha']:<10}  load {row['load']:<5}  "
                         f"{float(row['median_us']):>10.1f} µs  {ci:<18}  {rss}".rstrip())
        if len(shown) < 2:
            lines.append("  one reading: no change yet")
            continue
        first, latest = float(shown[0]["median_us"]), float(shown[-1]["median_us"])
        change = (latest / first - 1) * 100 if first else float("nan")
        widths = [(float(row["ci_high_pct"]) - float(row["ci_low_pct"])) / 2
                  for row in shown if row["ci_low_pct"] and row["ci_high_pct"]]
        if widths:
            noise = max(widths)
            beyond = "beyond" if abs(change) > noise else "within"
            lines.append(f"  change from the first: {change:+.1f}%  ({beyond} its widest interval, "
                         f"±{noise:.1f}%)")
        else:
            lines.append(f"  change from the first: {change:+.1f}%")
    return lines


def head_sha():
    """The checkout's HEAD, short, or `None` outside a checkout."""
    try:
        return subprocess.run(["git", "rev-parse", "--short=9", "HEAD"], capture_output=True,
                              text=True, check=True,
                              cwd=os.path.dirname(os.path.abspath(__file__))).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return None


def main(argv=None):
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("log", nargs="?", help="a saved `ab_bench.py` output to append")
    parser.add_argument("--csv", default=None,
                        help=f"the CSV (default: ${ENVIRONMENT_VARIABLE}, else {DEFAULT_CSV} "
                             "when its folder exists)")
    parser.add_argument("--sha", default=None,
                        help="the commit the NEW binary was built from (default: this "
                             "checkout's HEAD)")
    parser.add_argument("--host", default=None, help="the machine (default: this one's name)")
    parser.add_argument("--report", action="store_true",
                        help="print the last rows per scenario and how far each has moved")
    parser.add_argument("--last", type=int, default=5, help="rows per scenario in --report")
    args = parser.parse_args(argv)

    path = csv_path(args.csv)
    if path is None:
        print(f"no trend CSV: {os.path.dirname(DEFAULT_CSV)} does not exist. Pass --csv F or set "
              f"{ENVIRONMENT_VARIABLE}; nothing was written.")
        return 2

    if args.report:
        rows = read_rows(path)
        if not rows:
            print(f"{path}: no readings yet")
            return 1
        print("\n".join(report(rows, max(1, args.last))))
        return 0

    if not args.log:
        parser.error("give a saved ab_bench.py output to append, or --report")
    with open(args.log, encoding="utf-8") as file:
        load, metric, rows = parse_ab_bench(file.read())
    if not rows:
        print(f"{args.log}: no ab_bench.py result rows in it; nothing was written.")
        return 1
    sha = args.sha or head_sha()
    if not sha:
        print("no --sha, and not in a git checkout: say which commit the NEW binary was built from")
        return 1
    # The log's own time: when the run finished, which an append made later
    # would otherwise misdate.
    finished = datetime.datetime.fromtimestamp(os.path.getmtime(args.log))
    stamp = {
        "date": finished.strftime("%Y-%m-%dT%H:%M"),
        "sha": sha,
        "host": args.host or socket.gethostname().split(".")[0],
        "load": load or "",
        "metric": metric,
    }
    appended = append(path, [dict(row, **stamp) for row in rows])
    skipped = len(rows) - len(appended)
    note = f" ({skipped} already there)" if skipped else ""
    print(f"appended {len(appended)} rows to {path} at {sha}, {metric}{note}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
