#!/usr/bin/env python3
"""
Compare the WORK two builds of `Stress` do, scenario by scenario: counts, not
times, so the answer is the same on a loaded machine as on a quiet one.

    Tools/Profiling/ab_counters.py OLD NEW [--scenarios a b session/inbox] [--threshold 1]
    Tools/Profiling/ab_counters.py main WORKTREE --allocs        # builds both first

OLD and NEW are each a `Stress` binary, a git revision, or `WORKTREE` (the
working tree as it is). A revision is built in a temporary checkout of its own,
`swift build -c release --product Stress`, and the checkout and its build are
deleted once the binary is copied out; `WORKTREE` builds into this checkout's
own `.build`. A release build of Stress takes a few GB of disk while it lasts:
check `df -h` first. `TUI_RUN_WRAPPER` prefixes each build, as in
`Tools/Dev/quick.py` (a machine-wide build slot, say).

What it compares. Every count the harness prints for a scenario, read off its
output rather than listed here, so a counter added to `Stress` is compared the
day it is printed:

- `--bench --scenario X` (a fixed `--iterations`, the same for both): the
  measure memo's hits and lookups, the value memos' hits, lookups and stores,
  rows composed and served, cell values (calls into the app's closures), the
  per-pass memos, the effects' extra walks, what the last frame's prune kept.
- `--session ID` (`session/ID`, a fixed `--steps`): bytes written per step and
  per action, the memoized rows, the observation census (`--census`), the
  re-check, the environment stamps.
- With `--allocs`, every allocation the process makes, counted by
  `AllocCount/alloc_count.c` (macOS only).

Times, memory sizes, percentages and per-step rates are left out: the first
two are what this tool exists to avoid, and the others are derived from counts
already compared. The bench's `checksum` is compared for equality only: it
hashes what was drawn, so a difference says the two builds drew different
pictures, which a counter comparison should be read beside.

A tool for a person deciding about a change, NOT a gate: nothing is checked in
and nothing fails on a difference. Counts can differ for good reasons (a memo
that now serves more), so the output says what moved and by how much, and the
reader says whether that was the point.

Only the standard library, like the rest of this directory.
"""
import argparse
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ab_bench import runnable_by_both, scenario_ids  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ALLOC_SOURCE = os.path.join(REPO, "Tools", "Profiling", "AllocCount", "alloc_count.c")

# A number, its unit if it has one, and whether it is the value of `key=`.
NUMBER_RE = re.compile(r"(?P<key>[A-Za-z][\w\-/ ]*?=)?(?P<value>-?\d+(?:\.\d+)?)(?P<unit>µs|ms|MB|KB|GB|%|s\b)?")
WORD_RE = re.compile(r"[A-Za-z][\w\-/]*")
# Lines that are all times or memory, whatever their numbers' units.
SKIPPED_LINE_PREFIXES = ("total=", "per-frame=", "cpu-per-frame=", "rss-", "footprint-")
ACTION_HEADER_RE = re.compile(r"^action\s+steps\s+mean")
CHECKSUM_RE = re.compile(r"checksum=(-?\d+)")
# Words that never name a count: "0 of them repainted" is a count of repainted.
STOPWORDS = {"of", "a", "an", "the", "them", "to", "per", "at", "in", "from", "by"}


def counters(output):
    """Every count in one harness run's output, by a label made from its line.

    The label is the line's lead-in (what comes before its first `:`, if any)
    and the word that names the number: the word after it ("907 hits"), or,
    where none follows, the word before it ("armed 63"), or the `key=` it is the
    value of. Numbers with a unit of time, memory or percent, numbers in
    parentheses (rates derived from counts already read) and the run's header
    are left out.
    """
    found = {}
    in_table = False
    for raw in output.splitlines():
        line = raw.strip()
        if not line or line.startswith(("bench ", "selfcheck")) or line.startswith(SKIPPED_LINE_PREFIXES):
            in_table = False
            continue
        if ACTION_HEADER_RE.match(line):
            in_table = True
            continue
        if in_table:
            fields = line.split()
            if len(fields) == 7 and all(re.fullmatch(r"-?\d+(\.\d+)?", f) for f in fields[1:]):
                found[f"action {fields[0]}: steps"] = float(fields[1])
                found[f"action {fields[0]}: bytes/step"] = float(fields[6])
                continue
            in_table = False
        # A line can hold several sections, `a: 1 x; b: 2 y`, each with a lead
        # of its own; a section without one takes the line's, and a line without
        # any colon is led by its first word ("body-render armed 63, …").
        first_word = WORD_RE.match(line)
        line_lead = ""
        for index, section in enumerate(line.split(";")):
            lead, colon, rest = section.partition(":")
            if colon and not re.search(r"\d", lead):
                lead = lead.strip()
            else:
                rest = section
                lead = line_lead if index else (first_word.group(0) if first_word else "")
            if index == 0:
                line_lead = lead
            for match in NUMBER_RE.finditer(rest):
                label = counter_label(lead, rest, match)
                if label is None:
                    continue
                unique, n = label, 1
                while unique in found:
                    n += 1
                    unique = f"{label} #{n}"
                found[unique] = float(match.group("value"))
    return found


def counter_label(lead, text, match):
    """The label of the number `match` found in `text`, or `None` to leave it out."""
    if match.group("unit"):
        return None
    start = match.start("value")
    if text[:start].rstrip().endswith("("):
        return None
    if match.group("key"):
        name = match.group("key").rstrip("=").strip()
        if name == "checksum":
            return None
    else:
        rest = text[match.end():]
        following = [word for word in WORD_RE.findall(rest) if word not in STOPWORDS]
        before = WORD_RE.findall(text[:start])
        if WORD_RE.match(rest.lstrip()) and following:
            name = following[0]
        else:
            name = before[-1] if before else "value"
    return f"{lead}: {name}" if lead and lead != name else name


def run_counts(binary, scenario, args, alloc_lib):
    """(counters, checksum) of one run of `scenario` by `binary`."""
    base, _, variant = scenario.partition("/")
    if base == "session":
        command = [binary, "--session", variant, "--steps", str(args.steps), "--census"]
    else:
        command = [binary, "--bench", "--scenario", base, "--iterations", str(args.iterations)]
        if variant:
            command += ["--variant", variant]
    command += ["--cols", str(args.cols), "--rows", str(args.rows)]
    env = dict(os.environ)
    env.setdefault("TUI_CONFIG_DIR", tempfile.mkdtemp(prefix="ab-counters-config-"))
    count_file = None
    if alloc_lib:
        count_file = tempfile.NamedTemporaryFile(prefix="ab-counters-allocs-", delete=False).name
        env["DYLD_INSERT_LIBRARIES"] = alloc_lib
        env["ALLOC_COUNT_FILE"] = count_file
    result = subprocess.run(command, capture_output=True, text=True, env=env)
    if result.returncode != 0 and base != "session":
        raise RuntimeError(f"{' '.join(command)} exited {result.returncode}:\n{result.stdout}{result.stderr}")
    found = counters(result.stdout)
    if count_file:
        with open(count_file) as handle:
            text = handle.read().strip()
        os.unlink(count_file)
        if text:
            found["allocations (whole process)"] = float(text.split()[0])
    checksum = CHECKSUM_RE.search(result.stdout)
    return found, checksum.group(1) if checksum else None


def wrapped(command):
    wrapper = os.environ.get("TUI_RUN_WRAPPER")
    return shlex.split(wrapper) + command if wrapper else command


def build_stress(source, scratch, into):
    """Builds Stress in release from `source`, copies it to `into`, returns its path."""
    command = ["swift", "build", "-c", "release", "--product", "Stress"]
    if scratch:
        command += ["--scratch-path", scratch]
    print(f"ab-counters: building Stress in {source} …", flush=True)
    subprocess.run(wrapped(command), cwd=source, check=True)
    bin_dir = subprocess.run(command[:4] + command[6:] + ["--show-bin-path"], cwd=source,
                             capture_output=True, text=True, check=True).stdout.strip()
    target = os.path.join(into, "Stress")
    # A copy, never over an existing signed binary in place: a new file.
    shutil.copy2(os.path.join(bin_dir, "Stress"), target)
    return target


def resolve(spec, workdir, label):
    """A runnable Stress binary for `spec`: itself, the working tree's, or a revision's."""
    if os.path.isfile(spec) and os.access(spec, os.X_OK):
        return spec
    into = os.path.join(workdir, label)
    os.makedirs(into)
    if spec == "WORKTREE":
        return build_stress(REPO, None, into)
    revision = subprocess.run(["git", "rev-parse", "--verify", spec + "^{commit}"], cwd=REPO,
                              capture_output=True, text=True)
    if revision.returncode != 0:
        sys.exit(f"ab-counters: {spec!r} is neither an executable, WORKTREE, nor a git revision")
    checkout = os.path.join(workdir, label + "-src")
    subprocess.run(["git", "worktree", "add", "--detach", "--quiet", checkout, revision.stdout.strip()],
                   cwd=REPO, check=True)
    try:
        return build_stress(checkout, os.path.join(workdir, label + "-build"), into)
    finally:
        subprocess.run(["git", "worktree", "remove", "--force", checkout], cwd=REPO)
        shutil.rmtree(os.path.join(workdir, label + "-build"), ignore_errors=True)


def alloc_library(workdir):
    """The allocation counter, compiled for this run; `None` off macOS."""
    if sys.platform != "darwin":
        print("ab-counters: --allocs counts with DYLD_INSERT_LIBRARIES, macOS only; skipped")
        return None
    library = os.path.join(workdir, "alloc_count.dylib")
    subprocess.run(["clang", "-dynamiclib", "-O2", "-o", library, ALLOC_SOURCE], check=True)
    return library


def moved(old, new, threshold, minimum):
    """Whether `old` → `new` is a difference worth printing."""
    change = abs(new - old)
    if change <= minimum:
        return False
    return change > threshold / 100 * max(abs(old), 1)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[1].strip(),
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("old", help="a Stress binary, a git revision, or WORKTREE")
    ap.add_argument("new", help="a Stress binary, a git revision, or WORKTREE")
    ap.add_argument("--scenarios", nargs="+", default=None,
                    help="scenario ids, `scenario/variant`, or `session/<id>` "
                         "(default: every scenario the new binary lists, and every session)")
    ap.add_argument("--iterations", type=int, default=60, help="frames per bench run (default 60)")
    ap.add_argument("--steps", type=int, default=120, help="steps per session run (default 120)")
    ap.add_argument("--cols", type=int, default=120)
    ap.add_argument("--rows", type=int, default=40)
    ap.add_argument("--threshold", type=float, default=1.0,
                    help="print a count that moved by more than this percent (default 1)")
    ap.add_argument("--min", type=float, default=0.0,
                    help="and by more than this much in absolute terms (default 0)")
    ap.add_argument("--allocs", action="store_true", help="also count allocations (macOS)")
    ap.add_argument("--all", action="store_true", help="print every count, moved or not")
    args = ap.parse_args()

    workdir = tempfile.mkdtemp(prefix="ab-counters-")
    try:
        old = resolve(args.old, workdir, "old")
        new = resolve(args.new, workdir, "new")
        alloc_lib = alloc_library(workdir) if args.allocs else None
        if args.scenarios:
            scenarios = args.scenarios
        else:
            listed = subprocess.run([new, "--sessions"], capture_output=True, text=True).stdout
            sessions = [line.split()[0] for line in listed.splitlines() if line and not line[0].isspace()]
            scenarios = scenario_ids(new) + [f"session/{s}" for s in sessions]
        scenarios, missing = runnable_by_both(scenarios, old, new)
        for scenario in missing:
            print(f"ab-counters: {scenario}: not in both binaries, skipped")

        quiet = 0
        for scenario in scenarios:
            try:
                (before, old_sum), (after, new_sum) = (run_counts(b, scenario, args, alloc_lib)
                                                       for b in (old, new))
            except RuntimeError as error:
                print(f"{scenario}: {error}")
                continue
            lines = []
            moved_any = old_sum != new_sum
            for label in sorted(set(before) | set(after)):
                a, b = before.get(label), after.get(label)
                if a is None or b is None:
                    moved_any = True
                    lines.append(f"  {label}: {'only in new' if a is None else 'only in old'}")
                elif moved(a, b, args.threshold, args.min) or args.all:
                    moved_any = moved_any or moved(a, b, args.threshold, args.min)
                    change = (b - a) / max(abs(a), 1) * 100
                    lines.append(f"  {label}: {a:g} → {b:g} ({change:+.1f}%)")
            if old_sum != new_sum:
                lines.append(f"  checksum: {old_sum} → {new_sum} (they drew different pictures)")
            if lines:
                print(scenario)
                print("\n".join(lines))
            if not moved_any:
                quiet += 1
        print(f"ab-counters: {len(scenarios)} scenarios, {quiet} with no count moved past "
              f"{args.threshold:g}%")
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


if __name__ == "__main__":
    main()
