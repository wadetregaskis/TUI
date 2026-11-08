#!/usr/bin/env python3
"""
Which caches keep growing over a long session — named by table, not seen as a
rising total.

    Tools/Profiling/cache_growth.py STRESS [--sessions inbox log] [--steps 3000] [--every 25]

Plays each session for `--steps` steps with `Stress --session ID --cache-sizes
EVERY`, which prints every cache's entry count (the render cache's tables, the
state storage's, the lifecycle manager's: `HeadlessApp.cacheEntryCounts`) every
EVERY steps. Then, per table:

- The first `--warmup` of the samples (20% by default) are dropped: a page
  filling its caches as it opens is not growth.
- A least-squares line is fitted to the LAST HALF of the rest. A table whose
  line rises by more than `--min-growth` percent of its mean over that half,
  and by more than `--min-entries`, is reported as growing. One that rose and
  then levelled off — a plateau, however high — fits a flat line there and is
  not. Its floor and its peaks must both climb too, from the first half to the
  last quarter: a cache trimmed now and then is a sawtooth (the measure memo
  swings between about 70 and 385 entries on `log`), whose line can slope up
  over a stretch that ends high while its floor stays put. What a table keeps
  for good lifts its floor.

A bounded cache that is merely big is not growth, but a person reading the
report may still want it: the largest tables at the end are printed too.

Steps, not time, so a busy machine gives the same answer. Not a CI gate — it
says which table to look at, and a session that legitimately accumulates
(`accumulate` adds rows on purpose) will show what it accumulates. A release
build of Stress plays a few thousand steps in seconds; a debug one in minutes.

Only the standard library, like the rest of this directory.
"""
import argparse
import os
import subprocess
import sys
import tempfile

LINE_PREFIX = "cache-sizes "


def samples(binary, session, args):
    """{table: [(step, count), …]} from one run of `session`."""
    env = dict(os.environ)
    env.setdefault("TUI_CONFIG_DIR", tempfile.mkdtemp(prefix="cache-growth-config-"))
    out = subprocess.run(
        [binary, "--session", session, "--steps", str(args.steps), "--cache-sizes", str(args.every),
         "--cols", str(args.cols), "--rows", str(args.rows)],
        capture_output=True, text=True, env=env).stdout
    series = {}
    for line in out.splitlines():
        if not line.startswith(LINE_PREFIX):
            continue
        fields = dict(field.split("=", 1) for field in line[len(LINE_PREFIX):].split())
        step = int(fields.pop("step"))
        for name, count in fields.items():
            series.setdefault(name, []).append((step, int(count)))
    return series


def slope(points):
    """Least-squares slope of `points`, entries per step."""
    n = len(points)
    mean_x = sum(x for x, _ in points) / n
    mean_y = sum(y for _, y in points) / n
    spread = sum((x - mean_x) ** 2 for x, _ in points)
    return 0.0 if spread == 0 else sum((x - mean_x) * (y - mean_y) for x, y in points) / spread


def verdict(points, args):
    """(growing, growth over the last half, entries per step, mean there) of one table's samples."""
    kept = points[int(len(points) * args.warmup):]
    half = kept[len(kept) // 2:]
    if len(half) < 3:
        return False, 0.0, 0.0, 0.0
    mean = sum(y for _, y in half) / len(half)
    rate = slope(half)
    growth = rate * (half[-1][0] - half[0][0])
    early = [y for _, y in kept[:len(kept) // 2]]
    late = [y for _, y in kept[len(kept) * 3 // 4:]]
    enough = max(args.min_entries, args.min_growth / 100 * max(max(early), 1))
    # And both its floor and its peaks climb, from the first half to the last
    # quarter. A cache trimmed now and then is a sawtooth: its fitted line can
    # slope up over a stretch that happens to end high while its floor stays put
    # (the measure memo, 70 to 385 entries and back every few steps on `log`).
    # What it keeps for good lifts the floor.
    floor_rises = min(late) - min(early) > enough
    peak_rises = max(late) - max(early) > enough
    growing = growth > enough and floor_rises and peak_rises
    return growing, growth, rate, mean


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[1].strip(),
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("binary", help="a Stress binary (release, for long runs)")
    ap.add_argument("--sessions", nargs="+", default=None, help="session ids (default: every one)")
    ap.add_argument("--steps", type=int, default=3000)
    ap.add_argument("--every", type=int, default=25, help="steps between samples")
    ap.add_argument("--cols", type=int, default=120)
    ap.add_argument("--rows", type=int, default=40)
    ap.add_argument("--warmup", type=float, default=0.2, help="fraction of samples dropped first")
    ap.add_argument("--min-growth", type=float, default=5.0,
                    help="percent of its mean a table must grow over the last half (default 5)")
    ap.add_argument("--min-entries", type=float, default=2.0,
                    help="entries a table must grow by over the last half (default 2)")
    ap.add_argument("--largest", type=int, default=5, help="how many of the largest tables to list")
    args = ap.parse_args()

    sessions = args.sessions
    if not sessions:
        listed = subprocess.run([args.binary, "--sessions"], capture_output=True, text=True).stdout
        sessions = [line.split()[0] for line in listed.splitlines() if line and not line[0].isspace()]

    flagged = 0
    for session in sessions:
        series = samples(args.binary, session, args)
        if not series:
            print(f"{session}: no samples — does this Stress know --cache-sizes?")
            continue
        growing = []
        for name, points in series.items():
            grows, growth, rate, mean = verdict(points, args)
            if grows:
                growing.append((growth, name, rate, mean, points[-1][1]))
        largest = sorted(((points[-1][1], name) for name, points in series.items()), reverse=True)
        print(f"{session}: {len(series)} tables, {len(next(iter(series.values())))} samples")
        for growth, name, rate, mean, final in sorted(growing, reverse=True):
            print(f"  GROWING {name}: +{growth:.0f} over the last half ({rate * 1000:.1f} per 1000 steps), "
                  f"mean {mean:.0f}, {final} at the end")
        flagged += len(growing)
        print("  largest at the end: " + ", ".join(f"{name}={count}" for count, name in largest[:args.largest]))
    print(f"cache-growth: {flagged} growing table{'s' if flagged != 1 else ''} in {len(sessions)} sessions")
    return 0


if __name__ == "__main__":
    sys.exit(main())
