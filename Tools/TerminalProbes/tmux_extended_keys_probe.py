#!/usr/bin/env python3
r"""What tmux's `extended-keys` hands an application that never asked for it.

A real tmux, measured against a SCRIPTED terminal, as `keeper_passthrough_probe.py`
measures its clipboard: tmux runs on a pty whose master side this script plays
(TERM=xterm-256color), with a private server and a configuration of the case's
own. A recorder in the pane puts its tty in raw mode, asks for nothing (no
`CSI > 4 ; n m`, no kitty flags: what a TUI app does), and writes down every
read. The script then types each key the way an outer terminal would send it and
reads back what reached the pane.

Each key is typed in three spellings, because what tmux receives depends on the
outer terminal, which this script is standing in for:

  modify   `CSI 27 ; mods ; code ~`, xterm's modifyOtherKeys (what tmux asks
           its terminal for when `terminal-features` has `extkeys`)
  csi-u    `CSI code ; mods u`, the fixterms / kitty shape
  legacy   the plain byte a terminal sends with no extended keys (CR, TAB,
           space): tmux cannot know a modifier was held

The cases are `extended-keys` off, on and always, with `extended-keys-format`
xterm and csi-u. The record also keeps what tmux asked the scripted terminal
for at attach (`CSI > 4 ; n m`, a kitty push), which says what an outer
terminal is expected to send it.

  python3 tmux_extended_keys_probe.py
  PROBE_OUT=out.json python3 tmux_extended_keys_probe.py

What this does NOT measure: what iTerm2, Ghostty or xterm send for a key when
tmux asks — that needs a person at the keyboard (`key_probe.py`, run inside tmux
in that terminal). Writes JSON to $PROBE_OUT (default
./tmux_extended_keys_probe.json) and prints a table. Needs `tmux` on PATH.
"""

import json
import os
import pty
import re
import select
import shutil
import subprocess
import sys
import tempfile
import time

ESC = "\x1b"

# The keys H-60 asks about, plus two Control chords that have a legacy byte of
# their own (whether tmux re-codes those decides whether ⌃Q still arrives as 0x11).
KEYS = [
    # name, xterm modifier code, key code, legacy bytes
    ("shift_return", 2, 13, "\r"),
    ("ctrl_return", 5, 13, "\r"),
    ("ctrl_tab", 5, 9, "\t"),
    ("shift_space", 2, 32, " "),
    ("ctrl_shift_a", 6, 65, "\x01"),
    ("ctrl_q", 5, 113, "\x11"),
]

SPELLINGS = {
    "modify": lambda mods, code, legacy: f"{ESC}[27;{mods};{code}~",
    "csi-u": lambda mods, code, legacy: f"{ESC}[{code};{mods}u",
    "legacy": lambda mods, code, legacy: legacy,
}

CASES = [
    ("off", None),
    ("on", "xterm"),
    ("always", "xterm"),
    ("always", "csi-u"),
]

# What tmux may ask of its terminal about keys.
REQUESTS = re.compile(rb"\x1b\[>4;?\d*m|\x1b\[[>=<]\d*(;\d+)?u|\x1b\[\?u")

RECORDER = r"""
import os, select, sys, termios, time, tty, json
out = sys.argv[1]
fd = sys.stdin.fileno()
old = termios.tcgetattr(fd)
tty.setraw(fd)
reads = []
end = time.time() + float(sys.argv[2])
try:
    os.write(1, b"ready")
    while time.time() < end:
        if select.select([fd], [], [], 0.05)[0]:
            reads.append([time.time(), os.read(fd, 256).decode("latin-1")])
            with open(out, "w") as handle:
                json.dump(reads, handle)
finally:
    termios.tcsetattr(fd, termios.TCSADRAIN, old)
"""


def render(text):
    return "".join("<ESC>" if c == ESC else (f"<{ord(c):02X}>" if ord(c) < 0x20 or ord(c) == 0x7F else c)
                   for c in text)


def environment():
    env = {k: v for k, v in os.environ.items() if k not in ("TMUX", "TMUX_PANE", "STY", "WINDOW")}
    env["TERM"] = "xterm-256color"
    return env


def drain(fd, seconds):
    out = b""
    deadline = time.time() + seconds
    while time.time() < deadline:
        if select.select([fd], [], [], 0.02)[0]:
            try:
                chunk = os.read(fd, 65536)
            except OSError:
                break
            if not chunk:
                break
            out += chunk
    return out


def run_case(exe, mode, fmt, directory):
    conf = os.path.join(directory, "tmux.conf")
    with open(conf, "w") as handle:
        handle.write(f"set -s extended-keys {mode}\n")
        if fmt:
            handle.write(f"set -s extended-keys-format {fmt}\n")
        handle.write("set -as terminal-features 'xterm*:extkeys'\n")
        handle.write("set -s escape-time 10\n")
    recorder = os.path.join(directory, "recorder.py")
    with open(recorder, "w") as handle:
        handle.write(RECORDER)
    record = os.path.join(directory, "reads.json")
    socket = f"tuikit-h60-{os.getpid()}-{mode}-{fmt}"
    sends = [(key, spelling, SPELLINGS[spelling](mods, code, legacy))
             for key, mods, code, legacy in KEYS for spelling in SPELLINGS]
    gap = 0.35
    lifetime = 3 + gap * (len(sends) + 2)
    argv = [exe, "-L", socket, "-f", conf, "new-session", "-x", "80", "-y", "24",
            f"{sys.executable} {recorder} {record} {lifetime}"]
    pid, fd = pty.fork()
    if pid == 0:
        os.execvpe(argv[0], argv, environment())
    attach = drain(fd, 3)
    stamps = []
    for key, spelling, text in sends:
        stamps.append((key, spelling, text, time.time()))
        os.write(fd, text.encode("latin-1"))
        attach += drain(fd, gap)
    attach += drain(fd, 0.5)
    subprocess.run([exe, "-L", socket, "kill-server"], capture_output=True)
    try:
        os.waitpid(pid, 0)
    except ChildProcessError:
        pass
    os.close(fd)
    try:
        with open(record) as handle:
            reads = json.load(handle)
    except (OSError, ValueError):
        reads = []
    results = []
    for index, (key, spelling, text, sent) in enumerate(stamps):
        until = stamps[index + 1][3] if index + 1 < len(stamps) else float("inf")
        got = "".join(data for at, data in reads if sent <= at < until)
        results.append({"key": key, "sent_as": spelling, "sent": render(text), "pane_received": render(got)})
    requests = sorted({render(m.group(0).decode("latin-1")) for m in REQUESTS.finditer(attach)})
    return {"extended-keys": mode, "extended-keys-format": fmt, "asked_terminal_for": requests,
            "keys": results}


def main():
    exe = shutil.which("tmux")
    if not exe:
        sys.exit("tmux is not on PATH")
    version = subprocess.run([exe, "-V"], capture_output=True, text=True).stdout.strip()
    report = {"date": time.strftime("%Y-%m-%d"), "uname": " ".join(os.uname()), "tmux": version, "cases": []}
    for mode, fmt in CASES:
        with tempfile.TemporaryDirectory() as directory:
            report["cases"].append(run_case(exe, mode, fmt, directory))
    print(version)
    for case in report["cases"]:
        print(f"\nextended-keys {case['extended-keys']}, format {case['extended-keys-format']};"
              f" asked the terminal for {', '.join(case['asked_terminal_for']) or 'nothing'}")
        for row in case["keys"]:
            print(f"  {row['key']:13} {row['sent_as']:7} {row['sent']:18} -> {row['pane_received'] or '(nothing)'}")
    path = os.environ.get("PROBE_OUT", "tmux_extended_keys_probe.json")
    with open(path, "w") as handle:
        json.dump(report, handle, indent=1)
    print(f"\nwrote {path}")


if __name__ == "__main__":
    main()
