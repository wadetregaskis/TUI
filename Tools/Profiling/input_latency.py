#!/usr/bin/env python3
"""
Input-to-frame latency: how long after a key or a mouse event the frame showing
it is finished, as p50 / p95 / max per scenario.

    Tools/Profiling/input_latency.py BIN [--scenario list table scroll mouse] [--reps 3]
    Tools/Profiling/input_latency.py OLD NEW --scenario list --reps 6      # A/B
    Tools/Profiling/input_latency.py BIN --scenario list --gap 0.1         # one frame per input

A frame cost (`Stress --bench`, `ab_bench.py`) can stay flat while the frames
come later: a pacing mistake, one more walk per key, a wait in the wrong place.
This measures the whole loop instead — read, dispatch, render, diff, write —
in the real app (`Example`, or any app `drive.py` can drive) in a real PTY,
with the scenarios `drive.py` plays.

The oracle is the end of a synchronized update, `ESC [ ? 2026 l`, which the run
loop writes at the end of every frame that draws something (`RenderCycle.md`),
so a frame's end is in the byte stream itself; `TUI_SYNCHRONIZED_OUTPUT=1`
keeps it on. An input's latency is the time from writing it to the end of the
first frame read after it. Two limits follow, and the report should be read
with them:

- **Coalescing.** Inputs a scenario sends faster than frames finish share the
  next frame, and each is charged from its own write — which is what a user
  feels, under that input stream. `--gap S` spaces every input S seconds
  apart instead, so each gets a frame of its own.
- **Frames nobody asked for.** An animating page writes frames on its own, and
  one of those can end just after an input and be counted as its frame. Use
  the still scenarios (`list`, `table`, `scroll`, `mouse`) for latency; an
  input followed by no frame at all before the next is counted as `no frame`.

Several binaries are run in an order shuffled per rep, as `ab_bench.py` does,
so a trend in the machine is not charged to whichever ran second. Latency is
wall time, so it is only as good as the machine is quiet: compare medians over
several reps, and treat a difference smaller than the spread between reps as
none. A tool for a person, not a CI gate.

Only the standard library, like the rest of this directory.
"""
import argparse
import os
import pty
import random
import select
import signal
import statistics
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from drive import (BACK_TO_MENU, STATUS_REPLY, STATUS_REQUEST, build_scenario,  # noqa: E402
                   config_directory, login_tty_compat, set_winsize)

FRAME_END = b"\x1b[?2026l"
STILL_SCENARIOS = ["list", "table", "scroll", "mouse"]


class Session:
    """One run of `binary` in a PTY: reads its output, timestamped, and answers
    its status requests so its startup exchanges end at once."""

    def __init__(self, binary, rows, cols):
        master, slave = pty.openpty()
        set_winsize(slave, rows, cols)
        config = config_directory()
        pid = os.fork()
        if pid == 0:
            try:
                os.close(master)
                login_tty_compat(slave)
                env = dict(os.environ)
                env.pop("TMUX", None)
                env.update(TERM="xterm-256color", COLUMNS=str(cols), LINES=str(rows),
                           TUI_CONFIG_DIR=config, TUI_SYNCHRONIZED_OUTPUT="1")
                os.execve(binary, [binary], env)
            except Exception:
                pass
            os._exit(127)
        os.close(slave)
        self.pid, self.master = pid, master
        self.carry = b""
        self.frame_ends = []  # perf_counter time of each frame end read

    def read(self, until):
        """Read until `until` (a perf_counter time); False once the app is gone."""
        while True:
            left = until - time.perf_counter()
            ready, _, _ = select.select([self.master], [], [], max(0.0, left))
            if not ready:
                return True
            try:
                data = os.read(self.master, 65536)
            except OSError:
                return False
            if not data:
                return False
            now = time.perf_counter()
            seen = self.carry + data
            for _ in range(seen.count(STATUS_REQUEST)):
                os.write(self.master, STATUS_REPLY)
            self.frame_ends.extend([now] * seen.count(FRAME_END))
            self.carry = seen[-(max(len(FRAME_END), len(STATUS_REQUEST)) - 1):]

    def write(self, payload):
        os.write(self.master, payload)

    def quit(self):
        try:
            for delay, payload in BACK_TO_MENU + [(0.15, b"q")]:
                self.read(time.perf_counter() + delay)
                self.write(payload)
            deadline = time.perf_counter() + 1.5
            while time.perf_counter() < deadline:
                if os.waitpid(self.pid, os.WNOHANG)[0]:
                    break
                self.read(time.perf_counter() + 0.05)
            else:
                os.kill(self.pid, signal.SIGKILL)
                os.waitpid(self.pid, 0)
        except (OSError, ChildProcessError):
            pass
        os.close(self.master)


def measure(binary, scenario, args):
    """(latencies in ms, inputs with no frame) for one run of `scenario`."""
    session = Session(binary, args.rows, args.cols)
    session.read(time.perf_counter() + args.settle)
    steps = build_scenario(scenario, args.rows, args.cols)
    # The first step opens the scenario's page: its frame is the page arriving,
    # which `page_open.py` measures, not an input's latency.
    opening, steps = steps[0], steps[1:]
    session.read(time.perf_counter() + opening[0])
    session.write(opening[1])
    session.read(time.perf_counter() + args.settle)
    sent = []
    for delay, payload in steps:
        session.read(time.perf_counter() + (args.gap if args.gap is not None else delay))
        if payload:
            sent.append(time.perf_counter())
            session.write(payload)
    session.read(time.perf_counter() + args.settle)
    ends = session.frame_ends
    session.quit()
    latencies, missed = [], 0
    for index, at in enumerate(sent):
        following = sent[index + 1] if index + 1 < len(sent) else float("inf")
        frame = next((end for end in ends if end >= at), None)
        if frame is None or frame > following + args.settle:
            missed += 1
        else:
            latencies.append((frame - at) * 1000)
    return latencies, missed


def percentile(values, fraction):
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, int(round(fraction * (len(ordered) - 1))))]


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[1].strip(),
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("binaries", nargs="+", help="one app binary, or several to compare")
    ap.add_argument("--scenario", nargs="+", default=STILL_SCENARIOS,
                    help="drive.py scenarios (default: the still ones, %(default)s)")
    ap.add_argument("--reps", type=int, default=3, help="runs of each scenario per binary")
    ap.add_argument("--gap", type=float, default=None,
                    help="seconds between inputs, instead of the scenario's own cadence")
    ap.add_argument("--rows", type=int, default=50)
    ap.add_argument("--cols", type=int, default=160)
    ap.add_argument("--settle", type=float, default=0.6,
                    help="seconds to read before and after the inputs (default 0.6)")
    args = ap.parse_args()

    random.seed(20261107)
    for scenario in args.scenario:
        results = {binary: ([], 0, []) for binary in args.binaries}
        for _ in range(args.reps):
            order = list(args.binaries)
            random.shuffle(order)
            for binary in order:
                latencies, missed = measure(binary, scenario, args)
                pooled, missing, medians = results[binary]
                pooled.extend(latencies)
                if latencies:
                    medians.append(statistics.median(latencies))
                results[binary] = (pooled, missing + missed, medians)
        print(f"{scenario}{'' if args.gap is None else f' (gap {args.gap:g} s)'}:")
        for binary in args.binaries:
            pooled, missing, medians = results[binary]
            if not pooled:
                print(f"  {binary}: no frames read — is synchronized output reaching the PTY?")
                continue
            spread = f"{min(medians):.1f}–{max(medians):.1f}" if medians else "-"
            print(f"  {binary}: p50 {percentile(pooled, 0.5):.1f} ms  p95 {percentile(pooled, 0.95):.1f} ms  "
                  f"max {max(pooled):.1f} ms  ({len(pooled)} inputs, {missing} no frame; "
                  f"per-rep p50 {spread} ms)")


if __name__ == "__main__":
    main()
