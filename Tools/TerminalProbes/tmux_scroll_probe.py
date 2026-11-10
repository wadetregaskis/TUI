#!/usr/bin/env python3
"""What tmux sends its CLIENT when an app in a pane scrolls a band.

tmux keeps the grid and re-emits what it needs, so the bytes that matter over
ssh are the ones tmux writes to the terminal it is attached to, not what the app
wrote to tmux. This script plays that terminal on a pty, and runs an app in a
pane which shows the same notches two ways: rewriting every row of dissimilar
text, or moving the band (`CSI r` + `CSI n S`) and writing what it exposes. It
counts the bytes each notch costs at the client, per layout: the pane alone, a
pane beside another (not full width, so tmux cannot use a plain region), and a
pane above another (full width, shorter). No GUI, so it runs anywhere tmux does.

    python3 tmux_scroll_probe.py [--tmux tmux] [--cols 120] [--rows 40] [--out x.json]

The verdict on correctness is the tmux socket's own: `capture-pane -p` after the
notches, compared with what the document says the pane should show.
"""
import argparse
import fcntl
import json
import os
import pty
import random
import re
import select
import struct
import subprocess
import sys
import tempfile
import termios
import time

APP = r'''
import os, random, sys, time, re
mode, notches, by, ctl = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
cols, rows = os.get_terminal_size()
rng = random.Random(20261101)
doc = ["".join(rng.choice("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ") for _ in range(cols)) for _ in range(400)]
out = os.fdopen(os.dup(1), "wb", buffering=0)
sgr = "\x1b[38;5;252;48;5;235m"
kind, _, flag = mode.partition("-")
sync = "nosync" not in flag
open_hold, close_hold = ("\x1b[?2026h", "\x1b[?2026l") if sync else ("", "")
pen_in_force = sgr if "pen" in flag else "\x1b[0m"
def full(top):
    return (open_hold + sgr + "".join(f"\x1b[{r+1};1H" + doc[(top + r) % 400] for r in range(rows)) + "\x1b[0m" + close_hold).encode()
def region(top):
    parts = [open_hold, pen_in_force, f"\x1b[1;{rows}r\x1b[{by}S\x1b[r", sgr]
    for r in range(rows - by, rows):
        parts.append(f"\x1b[{r+1};1H" + doc[(top + r) % 400])
    parts.append("\x1b[0m" + close_hold)
    return "".join(parts).encode()
def cell(n):
    return (open_hold + f"\x1b[3;5H{sgr}{'abcdefgh'[n % 8]}\x1b[0m" + close_hold).encode()
out.write(b"\x1b[?1049h\x1b[?25l")
out.write(full(0))
def wait(token):
    while not os.path.exists(ctl + "." + token):
        time.sleep(0.01)
open(ctl + ".ready", "w").close()
wait("go")
top = 0
for n in range(notches):
    top += by
    out.write(full(top) if kind == "whole" else region(top) if kind == "region" else cell(n))
    time.sleep(0.12)
open(ctl + ".finished", "w").close()
wait("quit")
out.write(b"\x1b[?25h\x1b[?1049l")
if kind != "cell":
    expected = [doc[(top + r) % 400] for r in range(rows)]
    with open(ctl + ".expected", "w") as handle:
        handle.write("\n".join(expected))
'''


# `-nosync` drops the 2026 pair the app would wrap a frame in; `-pen` leaves a
# background in force across the scroll, which tmux asks the terminal to fill.
MODES = ("whole", "region", "cell", "whole-nosync", "region-nosync", "region-nosync,pen", "cell-nosync")


def run_case(tmux, layout, mode, cols, rows, notches, by, work):
    socket = f"scrollprobe{os.getpid()}"
    ctl = os.path.join(work, f"{layout}-{mode}")
    app = os.path.join(work, "app.py")
    with open(app, "w") as handle:
        handle.write(APP)
    command = f"exec /usr/bin/python3 {app} {mode} {notches} {by} {ctl}"
    env = dict(os.environ, TERM="xterm-256color")
    env.pop("TMUX", None)
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
    pid = os.fork()
    if pid == 0:
        os.close(master)
        os.setsid()
        fcntl.ioctl(slave, getattr(termios, "TIOCSCTTY", 0x20007461), 0)
        for fd in (0, 1, 2):
            os.dup2(slave, fd)
        argv = [tmux, "-L", socket, "-f", "/dev/null", "new-session"]
        if layout == "alone":
            argv += [command]
        elif layout == "beside":
            argv += ["sleep 1000", ";", "split-window", "-h", command]
        elif layout == "above":
            argv += ["sleep 1000", ";", "split-window", "-v", command]
        os.execvpe(tmux, argv, env)
    os.close(slave)

    received = bytearray()

    def pump(seconds):
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            if select.select([master], [], [], 0.02)[0]:
                try:
                    data = os.read(master, 65536)
                except OSError:
                    return
                if not data:
                    return
                received.extend(data)

    deadline = time.monotonic() + 15
    while not os.path.exists(ctl + ".ready") and time.monotonic() < deadline:
        pump(0.05)
    pump(1.0)
    before = len(received)
    open(ctl + ".go", "w").close()
    deadline = time.monotonic() + 60
    while not os.path.exists(ctl + ".finished") and time.monotonic() < deadline:
        pump(0.05)
    pump(0.5)
    stream = bytes(received[before:])
    captured = subprocess.run([tmux, "-L", socket, "capture-pane", "-p"], capture_output=True, text=True).stdout
    open(ctl + ".quit", "w").close()
    pump(0.3)
    subprocess.run([tmux, "-L", socket, "kill-server"], capture_output=True)
    try:
        os.kill(pid, 9)
        os.waitpid(pid, 0)
    except OSError:
        pass
    os.close(master)
    finals = {}
    for match in re.finditer(rb"\x1b\[([0-?]*)[ -/]*([@-~])", stream):
        key = match.group(2).decode()
        if match.group(2) == b"h" or match.group(2) == b"l":
            key = match.group(1).decode() + key
        finals[key] = finals.get(key, 0) + 1
    time.sleep(0.2)
    correct = None
    if os.path.exists(ctl + ".expected"):
        with open(ctl + ".expected") as handle:
            want = handle.read().splitlines()
        got = [line for line in captured.splitlines()]
        correct = want == got[:len(want)]
    return {
        "layout": layout, "mode": mode, "bytes_per_notch": len(stream) / notches,
        "finals": dict(sorted(finals.items(), key=lambda kv: -kv[1])[:10]),
        "held": b"\x1b[?2026h" in stream, "pane_matches_document": correct,
    }


def run_app(tmux, binary, env_extra, cols, rows, page, work):
    """A real TUI app in a pane: what tmux sends its client for an idle page, and
    for a held key and a wheel on that page, under `env_extra`."""
    socket = f"scrollprobeapp{os.getpid()}"
    exports = " ".join(f"{key}={value}" for key, value in env_extra.items())
    config = os.path.join(work, "config")
    command = f"env TUI_CONFIG_DIR={config} {exports} {binary}"
    env = dict(os.environ, TERM="xterm-256color")
    env.pop("TMUX", None)
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
    pid = os.fork()
    if pid == 0:
        os.close(master)
        os.setsid()
        fcntl.ioctl(slave, getattr(termios, "TIOCSCTTY", 0x20007461), 0)
        for fd in (0, 1, 2):
            os.dup2(slave, fd)
        os.execvpe(tmux, [tmux, "-L", socket, "-f", "/dev/null", "new-session", command], env)
    os.close(slave)
    received = {"count": 0}

    def pump(seconds):
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            if select.select([master], [], [], 0.02)[0]:
                try:
                    data = os.read(master, 65536)
                except OSError:
                    return
                if not data:
                    return
                received["count"] += len(data)

    pump(3.0)
    os.write(master, page.encode())
    pump(1.5)
    before = received["count"]
    pump(5.0)
    idle = received["count"] - before
    before = received["count"]
    for _ in range(30):
        os.write(master, b"\x1b[B")
        pump(0.05)
    pump(0.3)
    keys = (received["count"] - before) / 30
    subprocess.run([tmux, "-L", socket, "kill-server"], capture_output=True)
    try:
        os.kill(pid, 9)
        os.waitpid(pid, 0)
    except OSError:
        pass
    os.close(master)
    return {"env": env_extra, "idle_bytes_per_second": idle / 5.0, "bytes_per_down_key": keys}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--tmux", default="tmux")
    parser.add_argument("--cols", type=int, default=120)
    parser.add_argument("--rows", type=int, default=40)
    parser.add_argument("--notches", type=int, default=12)
    parser.add_argument("--by", type=int, default=3)
    parser.add_argument("--out")
    parser.add_argument("--app", help="also measure this TUI app in a pane, holds on and off")
    parser.add_argument("--page", default="-", help="the key that opens the page to sit on")
    args = parser.parse_args()
    version = subprocess.run([args.tmux, "-V"], capture_output=True, text=True).stdout.strip()
    rows = []
    with tempfile.TemporaryDirectory() as work:
        for layout in ("alone", "above", "beside"):
            for mode in MODES:
                row = run_case(args.tmux, layout, mode, args.cols, args.rows, args.notches, args.by, work)
                rows.append(row)
                print(f"{layout:<8} {mode:<7} {row['bytes_per_notch']:9.0f} B/notch  held={row['held']}  "
                      f"pane ok={row['pane_matches_document']}  {row['finals']}")
    apps = []
    if args.app:
        with tempfile.TemporaryDirectory() as work:
            # As shipped (no hold under tmux, scrolling at `exact` since 2026-11-09),
            # scrolling off, and the hold asked for anyway: what it costs at the client.
            for extra in ({}, {"TUI_SCROLL_OUTPUT": "off"}, {"TUI_SYNCHRONIZED_OUTPUT": "1"}):
                result = run_app(args.tmux, args.app, extra, args.cols, args.rows, args.page, work)
                apps.append(result)
                print(f"app {extra or 'as shipped'}: idle {result['idle_bytes_per_second']:.0f} B/s, "
                      f"Down key {result['bytes_per_down_key']:.0f} B")
    if args.out:
        with open(args.out, "w") as handle:
            json.dump({"tmux": version, "apps": apps, "cols": args.cols, "rows": args.rows, "by": args.by,
                       "date": time.strftime("%Y-%m-%d"), "cases": rows}, handle, indent=1)
            handle.write("\n")
    print(version)
    return 0


if __name__ == "__main__":
    sys.exit(main())
