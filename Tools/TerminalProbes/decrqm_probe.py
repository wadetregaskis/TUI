#!/usr/bin/env python3
"""DECRQM survey: which of the DEC private modes TUI sets or asks about does the
terminal say it recognises, and in what state?

For each mode, `CSI ? Ps $ p` fenced by `CSI 5 n`; the answer is
`CSI ? Ps ; Pm $ y`, Pm 0 not recognised, 1 set, 2 reset, 3 permanently set,
4 permanently reset. A mode with no answer before the fence is recorded as
silent. The kitty keyboard protocol's query (`CSI ? u`) and XTVERSION ride along,
fenced the same way, as the two other questions TUI's start-up asks.

**Do not run this on Apple Terminal**, which prints DECRQM's final byte (Terminal
compatibility survey.md, "Asking the terminal — Device Attributes"): written for
hosts that parse it, Windows Terminal and conhost first (2026-11-16), where every
other probe that asks a mode declines to for a host that does not name itself.

Run INSIDE the terminal under test. `PROBE_ALT=1` asks on the alternate screen.
Writes JSON to $PROBE_OUT (default ./decrqm_probe.json).
"""
import json
import os
import re
import select
import sys
import termios
import tty

import probe_stamp

MODES = [
    (1, "DECCKM application cursor keys"),
    (7, "DECAWM autowrap"),
    (25, "DECTCEM cursor visible"),
    (1000, "mouse: press and release"),
    (1002, "mouse: button motion"),
    (1003, "mouse: any motion"),
    (1004, "focus reports"),
    (1006, "SGR mouse encoding"),
    (1016, "SGR-Pixels mouse encoding"),
    (1049, "alternate screen"),
    (2004, "bracketed paste"),
    (2026, "synchronized output"),
    (2027, "grapheme clustering"),
    (2031, "colour-palette update notifications"),
    (2048, "in-band resize reports"),
    (9001, "win32-input-mode"),
]

FENCE = b"\x1b[5n"
FENCE_REPLY = b"\x1b[0n"


def exchange(fd, query, timeout=1.5):
    """`query` and the fence; everything that came back before the fence's reply,
    or None when even the fence went unanswered."""
    os.write(fd, query + FENCE)
    buffer = b""
    while FENCE_REPLY not in buffer:
        ready, _, _ = select.select([fd], [], [], timeout)
        if not ready:
            return None
        buffer += os.read(fd, 1024)
    return buffer[: buffer.index(FENCE_REPLY)]


STATES = {0: "not recognised", 1: "set", 2: "reset", 3: "permanently set", 4: "permanently reset"}


def main():
    out_path = os.environ.get("PROBE_OUT", "decrqm_probe.json")
    use_alt = os.environ.get("PROBE_ALT") == "1"
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    record = {"modes": {}, "other": {}}
    try:
        tty.setraw(fd)
        if use_alt:
            os.write(fd, b"\x1b[?1049h")
        record["stamp"] = probe_stamp.stamp(fd, "decrqm_probe", use_alt)
        for mode, what in MODES:
            reply = exchange(fd, f"\x1b[?{mode}$p".encode())
            entry = {"what": what, "raw": None if reply is None else reply.decode("latin-1")}
            match = reply and re.search(rb"\x1b\[\?(\d+);(\d+)\$y", reply)
            if match and int(match.group(1)) == mode:
                entry["state"] = STATES.get(int(match.group(2)), f"unknown ({match.group(2).decode()})")
            else:
                entry["state"] = "silent" if reply is not None else "fence unanswered"
            record["modes"][str(mode)] = entry
        for name, query in [("kitty_keyboard", b"\x1b[?u"), ("xtversion", b"\x1b[>0q")]:
            reply = exchange(fd, query)
            record["other"][name] = None if reply is None else reply.decode("latin-1")
    finally:
        if use_alt:
            os.write(fd, b"\x1b[?1049l")
        termios.tcsetattr(fd, termios.TCSADRAIN, old)
    with open(out_path, "w", encoding="utf-8") as out:
        json.dump(record, out, indent=2, ensure_ascii=False)
    for mode, entry in record["modes"].items():
        print(f"?{mode:<5} {entry['state']:<18} {entry['what']}")
    for name, reply in record["other"].items():
        print(f"{name}: {reply!r}")


if __name__ == "__main__":
    main()
