#!/usr/bin/env python3
"""
Frame-by-frame parity of two prebuilt `Stress` binaries.

    Tools/Profiling/frame_parity.py OLD NEW [--scenarios a b/c session/d ...]
                                    [--iterations N] [--cols C] [--rows R] [--scale S]

Runs each scenario on both binaries with `--bench --frame-checksums`, which
prints every frame's content checksum (a session's: every step's screen), and
compares them frame by frame. Prints one line per scenario, and for one that
differs, the first frame that does. Exits 1 if any scenario differs or either
binary fails to run it.

What it is for: a change that must draw exactly what it drew before — a
refactor on a hot path, or SCROLL-FIT's P1, which moved the scroll position
into the scroll view and changed no output
(`Documentation/Historical/Scrolling/SCROLL-FIT design.md`, gate 4). The suite
pins what its tests look at; this compares every frame of scenes the tests do
not draw, at sizes they do not use, under the writes and input the scenarios
make. `ab_bench.py` times two builds; this says whether they draw alike.

With no `--scenarios`, every scenario the old binary lists, every variant of
each, and every session. A `scenario/variant` runs that variant; a session is
`session/<id>`. Only the standard library, like the rest of this directory.
"""
import argparse
import re
import subprocess
import sys

FRAME_RE = re.compile(r"^frame (\d+) checksum=(-?\d+)$", re.MULTILINE)


def listed_scenarios(binary):
    """Every scenario id, from the binary's own usage text."""
    out = subprocess.run([binary, "--help"], capture_output=True, text=True).stdout
    lines = out.splitlines()
    for i, line in enumerate(lines):
        if line.strip().startswith("Scenario ids"):
            return [s.strip() for s in lines[i + 1].split(",") if s.strip()]
    return []


def listed_variants(binary):
    """`{scenario: [variant, ...]}`, from `Stress --variants`."""
    out = subprocess.run([binary, "--variants"], capture_output=True, text=True).stdout
    found, current = {}, None
    for line in out.splitlines():
        if not line.startswith(" "):
            current = line.split(" ")[0] if line.strip() else None
            if current:
                found[current] = []
        elif current and line.startswith("    "):
            found[current].append(line.split()[0])
    return found


def listed_sessions(binary):
    """Every session id, from `Stress --sessions` (ids start a line)."""
    out = subprocess.run([binary, "--sessions"], capture_output=True, text=True).stdout
    return [line.split()[0] for line in out.splitlines() if line and not line[0].isspace()]


def every_case(binary):
    cases = []
    variants = listed_variants(binary)
    for scenario in listed_scenarios(binary):
        if variants.get(scenario):
            cases += [f"{scenario}/{variant}" for variant in variants[scenario]]
        else:
            cases.append(scenario)
    return cases + [f"session/{session}" for session in listed_sessions(binary)]


def checksums(binary, case, iterations, cols, rows, scale):
    """Every frame's checksum, in order, or raises with the run's output."""
    scenario, _, variant = case.partition("/")
    if scenario == "session":
        scenario, variant = case, ""
    command = [binary, "--bench", "--frame-checksums", "--scenario", scenario,
               "--iterations", str(iterations), "--cols", str(cols), "--rows", str(rows),
               "--scale", str(scale)] + (["--variant", variant] if variant else [])
    result = subprocess.run(command, capture_output=True, text=True)
    frames = [int(value) for _, value in FRAME_RE.findall(result.stdout)]
    if result.returncode != 0 or len(frames) != iterations:
        raise RuntimeError(
            f"{binary} {case}: exit {result.returncode}, {len(frames)}/{iterations} frames\n"
            + result.stdout[-2000:] + result.stderr[-2000:])
    return frames


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("old")
    parser.add_argument("new")
    parser.add_argument("--scenarios", nargs="*", help="cases to compare (default: every one)")
    parser.add_argument("--iterations", type=int, default=120)
    parser.add_argument("--cols", type=int, default=120)
    parser.add_argument("--rows", type=int, default=40)
    parser.add_argument("--scale", type=int, default=1)
    args = parser.parse_args()

    cases = args.scenarios or every_case(args.old)
    failures = 0
    for case in cases:
        try:
            old = checksums(args.old, case, args.iterations, args.cols, args.rows, args.scale)
            new = checksums(args.new, case, args.iterations, args.cols, args.rows, args.scale)
        except RuntimeError as error:
            failures += 1
            print(f"ERROR  {case}: {error}")
            continue
        first = next((i for i, (a, b) in enumerate(zip(old, new)) if a != b), None)
        if first is None:
            print(f"same   {case} ({len(old)} frames)")
        else:
            failures += 1
            differing = sum(1 for a, b in zip(old, new) if a != b)
            print(f"DIFFER {case}: first at frame {first}, {differing}/{len(old)} frames differ")
        sys.stdout.flush()
    print(f"{len(cases) - failures}/{len(cases)} cases draw alike at {args.cols}x{args.rows}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
