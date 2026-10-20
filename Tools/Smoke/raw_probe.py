#!/usr/bin/env python3
"""Drive a TUIkit app in a PTY and examine the bytes it ACTUALLY emitted.

`tui_walk.py` and `tui_screens.py` decode the child's output with `pyte` and
ask questions about the resulting screen. That is the right tool for almost
everything and the wrong one for anything involving an emoji-presentation
cluster: **pyte abandons the rest of a write at a U+FE0F**, because VS-16 is
width 0 with combining class 0 and matches none of its draw branches. A row
carrying ⚙️ ⚠️ ✂️ therefore looks truncated in a pyte dump whatever the app
sent, which has cost real time — twice — chasing a bug the harness invented.

**pyte has no APC parser either**, and that one is louder: given the Kitty
graphics protocol's `ESC _ G …; <base64> ESC \\`, it prints the payload into the
screen — so an image page dumped through `tui_walk.py` shows kilobytes of
base64 across the top and bottom rows and the placement command as text. That
is the harness, not the app: every real terminal either consumes the sequence
or (Apple Terminal) is never sent one. The rows BETWEEN are still trustworthy,
which is how the placeholder cells' alignment was checked.

This probe decodes nothing. It records the child's bytes verbatim and counts
patterns in them, which is what the questions below actually need:

  * did this cluster reach the terminal with its cursor compensation?
    (`Documentation/Terminals/Terminal compatibility survey.md` — a cluster whose painted width
    and cursor advance disagree needs ECH before and CUF after on Terminal.app,
    and an emission missing them shifts the rest of the row one cell.)
  * does an IDLE app write anything at all, and how much?
  * what did one animation tick cost, in bytes?

Two phases are timed separately, because the interesting bugs live in the
difference: `settle` covers the render the last keystroke provoked, and
`watch` covers what happens afterwards with no input at all — animation
replay, and nothing else.

Usage:
  raw_probe.py <binary> --keys "down*10,enter,tab*7,down*8,space"
               [--cluster ⚙️] [--settle 0.6] [--watch 2.5] [--out FILE]
               [--term-program Apple_Terminal] [--cols N] [--rows N]
               [--args "--page textInput"] [--blink]

`--term-program` forces the host TUIkit detects, so a compensation path can be
exercised from any terminal (including CI). `--cluster` turns the byte counts
into a verdict: exit 1 if any emission of it in the watch phase is missing the
compensation the built rows carry, 2 if the phase never carried it at all
(inconclusive — the keys did not reach the row you meant).

`--blink` times the watch phase instead, for a screen whose only motion is a
blinking caret (`Example --page textInput`, with F2 setting Blink): every
write there is the caret turning on or off, so the gaps between writes are the
blink's holds. A check of the formula cannot stand in for this one. The
irregular blink the owner reported (2026-09-12) held 709, 43 and 369 ms in
turn while every unit test of the timer passed: two defects in the live loop,
which only a timeline of what the app wrote showed. It judges the holds'
REGULARITY, not their length, so a slow runner cannot fail it: exit 1 if a
hold is under half the median or over half as long again, or the on and off
halves' means differ by over a fifth of it; 2 if the phase held under six
holds (inconclusive — the caret was not blinking).

The child runs with an isolated TUIKIT_CONFIG_DIR, never the real preferences.
"""
import argparse
import fcntl
import os
import pty
import select
import struct
import sys
import termios
import time

# The same vocabulary `tui_walk.py` accepts, so a key script can be moved
# between the two probes unchanged.
SEQUENCES = {
    "down": "\x1b[B", "up": "\x1b[A", "left": "\x1b[D", "right": "\x1b[C",
    "enter": "\r", "esc": "\x1b", "tab": "\t", "space": " ",
    "ctrl-v": "\x16", "ctrl-r": "\x12",
    "f1": "\x1bOP", "f2": "\x1bOQ", "f3": "\x1bOR",
}

# Erase Character, and Cursor Forward — what `withTerminalAppCursorCompensation`
# puts either side of an under-advancing cluster: erase the cells it claims in
# the current background, draw over the first, step past the last.
ECH = "\x1b[2X".encode()
CUF = "\x1b[1C".encode()


def parse_keys(script):
    """`"down*3,enter"` → the bytes to send, in order, one entry per press."""
    presses = []
    for token in script.split(","):
        token = token.strip()
        if not token:
            continue
        name, _, count = token.partition("*")
        if name not in SEQUENCES:
            raise SystemExit(f"unknown key {name!r}; known: {', '.join(sorted(SEQUENCES))}")
        presses += [SEQUENCES[name].encode()] * int(count or 1)
    return presses


class Child:
    """A TUIkit app on the other end of a PTY, and every byte it has sent."""

    def __init__(self, binary, cols, rows, term_program, arguments=()):
        self.all = bytearray()
        # Each read the watch phase took, and when: what `--blink` times.
        self.reads = []
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            try:
                os.environ["TUIKIT_CONFIG_DIR"] = os.path.join(
                    os.environ.get("TMPDIR", "/tmp"), "tuikit-raw-probe")
                os.environ["TERM"] = "xterm-256color"
                if term_program:
                    os.environ["TERM_PROGRAM"] = term_program
                os.execv(binary, [binary, *arguments])
            except Exception:
                pass
            os._exit(127)  # exec failed: end here, never in this script's code or its cleanup
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))

    def drain(self, seconds, timed=False):
        """Everything the child sends in `seconds`, also appended to `all`; with
        `timed`, each read is also noted in `reads` with when it arrived."""
        out = bytearray()
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            ready, _, _ = select.select([self.fd], [], [], 0.005 if timed else 0.05)
            if not ready:
                continue
            try:
                chunk = os.read(self.fd, 65536)
            except OSError:  # the child exited
                break
            if not chunk:  # end of file: the child exited
                break
            out += chunk
            if timed:
                self.reads.append((time.monotonic(), len(chunk)))
        self.all += out
        return bytes(out)

    def press(self, keys, gap):
        for key in keys:
            os.write(self.fd, key)
            self.drain(gap)

    def kill(self):
        try:
            os.kill(self.pid, 9)
        except ProcessLookupError:
            pass


def report(name, blob, cluster):
    counts = ""
    if cluster:
        emitted = blob.count(cluster)
        counts = (f", {emitted:3d} × {cluster.decode()}"
                  f" — {blob.count(cluster + CUF):3d} with CUF after,"
                  f" {blob.count(ECH + cluster):3d} with ECH before")
    print(f"{name:7s} {len(blob):7d} bytes{counts}")
    return blob.count(cluster) if cluster else 0


def blink_verdict(reads):
    """The holds between the writes `reads` timed, and whether they are regular.

    Reads closer than 30 ms are one write: a frame can arrive in more than one
    read, and no blink holds for 30 ms.
    """
    starts = []
    for when, _ in reads:
        if not starts or when - starts[-1][1] > 0.030:
            starts.append([when, when])
        else:
            starts[-1][1] = when
    holds = [(b[0] - a[0]) * 1000 for a, b in zip(starts, starts[1:])]
    print(f"blink   {len(starts)} writes, {len(holds)} holds (ms): "
          + " ".join(f"{hold:.0f}" for hold in holds))
    if len(holds) < 6:
        print("INCONCLUSIVE: under six holds — the caret was not blinking, or something else moved")
        return 2
    median = sorted(holds)[len(holds) // 2]
    odd, even = holds[0::2], holds[1::2]
    halves = abs(sum(odd) / len(odd) - sum(even) / len(even))
    outliers = [hold for hold in holds if hold < median * 0.5 or hold > median * 1.5]
    print(f"        median {median:.0f} ms, on/off halves {halves:.0f} ms apart")
    if outliers or halves > median * 0.2:
        print(f"FAIL: irregular blink — {len(outliers)} hold(s) outside half to one and a half "
              f"times the median, halves {halves:.0f} ms apart (at most {median * 0.2:.0f})")
        return 1
    print("PASS: a regular blink")
    return 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("binary")
    parser.add_argument("--keys", default="")
    parser.add_argument("--cluster", default=None,
                        help="a grapheme cluster to check the compensation of, e.g. ⚙️")
    parser.add_argument("--launch", type=float, default=1.5)
    parser.add_argument("--gap", type=float, default=0.15,
                        help="how long to let the app settle between keys")
    parser.add_argument("--settle", type=float, default=0.6)
    parser.add_argument("--watch", type=float, default=2.5)
    parser.add_argument("--cols", type=int, default=100)
    parser.add_argument("--rows", type=int, default=30)
    parser.add_argument("--term-program", default=None)
    parser.add_argument("--out", default=None, help="write the whole capture here")
    parser.add_argument("--args", default="",
                        help="arguments for the binary, split on spaces, e.g. \"--page textInput\"")
    parser.add_argument("--blink", action="store_true",
                        help="judge the watch phase's writes as a caret blink's timeline")
    args = parser.parse_args()

    cluster = args.cluster.encode() if args.cluster else None
    child = Child(args.binary, args.cols, args.rows, args.term_program, args.args.split())
    try:
        child.drain(args.launch)
        child.press(parse_keys(args.keys), args.gap)
        settle = child.drain(args.settle)
        watch = child.drain(args.watch, timed=args.blink)
    finally:
        child.kill()

    if args.out:
        with open(args.out, "wb") as handle:
            handle.write(bytes(child.all))

    report("settle", settle, cluster)
    emitted = report("watch", watch, cluster)
    if args.blink:
        return blink_verdict(child.reads)
    if not cluster:
        return 0
    print()
    if emitted == 0:
        print(f"INCONCLUSIVE: no {args.cluster} was emitted with no input pending; "
              "the keys did not reach the row you meant")
        return 2
    compensated = watch.count(cluster + CUF)
    if compensated == emitted:
        print(f"PASS: all {emitted} compensated")
        return 0
    print(f"FAIL: {emitted - compensated} of {emitted} uncompensated — "
          "the row will sit one cell left of where it belongs")
    return 1


sys.exit(main())
