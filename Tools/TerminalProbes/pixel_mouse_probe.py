#!/usr/bin/env python3
"""What a terminal's SGR-Pixels mouse mode (`?1016`) really reports.

The half that runs INSIDE the terminal; `pixel_mouse_driver.swift` is the half
that opens the terminal and posts the clicks, so the same physical point is
clicked once in cell mode and once in pixel mode and the two reports can be
laid side by side. Run the driver, not this (its header says how).

What is asked and recorded (JSON at $PROBE_OUT):

- DECRQM for 1006 and 1016, before anything is set and after each change, so
  the answers say whether the two are one setting;
- `TIOCGWINSZ`, `CSI 14 t` (the text area) and `CSI 16 t` (the cell): the
  candidates for the unit a pixel report is in;
- every report of each phase:
  * `cells`   `?1000h ?1006h`, clicked
  * `pixels`  the same, `?1016h` on top, the same points clicked
  * `motion-cells`, `motion-pixels`  `?1003h` in each encoding, the pointer
    moved a point at a time: how many reports a move costs
  * `reset`   `?1016l` with nothing else sent, clicked: what encoding `?1016l`
    leaves behind
  * `resend`  `?1016h ?1006h`, clicked: whether re-sending `?1006h` drops pixels

`--analyze RESULT.json` prints what the record says: the fit of pixel reports
against points, and how often the whole cell worked out from a pixel report
disagrees with the terminal's own cell report for each candidate cell size.
"""
import fcntl
import json
import math
import os
import re
import select
import struct
import sys
import termios
import time
import tty

ESC = b"\x1b"
REPORT = re.compile(rb"\x1b\[<(\d+);(\d+);(\d+)([Mm])")
LEGACY = re.compile(rb"\x1b\[M(.)(.)(.)", re.S)


def analyze(path):
    record = json.load(open(path))
    print(record.get("host"), record.get("grid"), "ioctl", record.get("ioctl"))
    print("  14t", record.get("text_area"), "16t", record.get("cell"))
    for key, value in record.get("decrqm", {}).items():
        print(f"  DECRQM {key}: {value}")
    points = record.get("points", [])
    clicks = record.get("clicks", {})

    def press_after(name):
        """The press each click made, or None: by time, so one lost shifts nothing."""
        reports = [r for r in record["phases"].get(name, []) if r[3] == "M" and r[0] < 32]
        found = []
        for index, posted in enumerate(clicks.get(name, [])):
            following = clicks[name][index + 1] if index + 1 < len(clicks[name]) else posted + 1
            found.append(next((r for r in reports if posted <= r[4] < following), None))
        return found

    pairs = [
        (points[i], c, p)
        for i, (c, p) in enumerate(zip(press_after("cells"), press_after("pixels")))
        if c is not None and p is not None
    ]
    print(f"  clicks answered in both modes: {len(pairs)} of {len(points)}")
    for name in ("reset", "resend"):
        print(f"  {name}: {record['phases'].get(name, [])[:4]} legacy={record['phases'].get(name + '-legacy', 0)}")
    for name in ("motion-cells", "motion-pixels"):
        print(f"  {name}: {len(record['phases'].get(name, []))} reports")
    count = len(pairs)
    if count < 2:
        print("  too few to fit")
        return
    for axis, label in ((1, "x"), (2, "y")):
        xs = [pair[0][axis - 1] for pair in pairs]
        ys = [pair[2][axis] for pair in pairs]
        mean_x, mean_y = sum(xs) / count, sum(ys) / count
        spread = sum((x - mean_x) ** 2 for x in xs)
        slope = sum((x - mean_x) * (y - mean_y) for x, y in zip(xs, ys)) / spread
        worst = max(abs(y - (mean_y + slope * (x - mean_x))) for x, y in zip(xs, ys))
        print(f"  {label}: report = {slope:.3f} * point + {mean_y - slope * mean_x:.2f} (worst residual {worst:.2f})")
    grid = record["grid"]
    candidates = {}
    if record.get("ioctl"):
        candidates["ioctl"] = (record["ioctl"][2] / grid[0], record["ioctl"][3] / grid[1])
    if record.get("text_area"):
        candidates["14t"] = (record["text_area"][1] / grid[0], record["text_area"][0] / grid[1])
    if record.get("cell"):
        candidates["16t"] = (record["cell"][1], record["cell"][0])
    for name, (width, height) in candidates.items():
        for origin in (0, 1):
            wrong = 0
            drift = []
            for _, cell, pixel in pairs:
                across, down = (pixel[1] - origin) / width, (pixel[2] - origin) / height
                if (math.floor(across), math.floor(down)) != (cell[1] - 1, cell[2] - 1):
                    wrong += 1
                drift.append((across - (cell[1] - 1), down - (cell[2] - 1)))
            print(
                f"  cell {name} {width:.3f}x{height:.3f}, reports from {origin}: wrong {wrong}/{count};"
                f" fraction x {min(d[0] for d in drift):.2f}..{max(d[0] for d in drift):.2f}"
                f" y {min(d[1] for d in drift):.2f}..{max(d[1] for d in drift):.2f}")


def main():
    out_path, ctl = os.environ["PROBE_OUT"], os.environ["PROBE_CTL"]
    fd = os.open("/dev/tty", os.O_RDWR)
    saved = termios.tcgetattr(fd)
    tty.setraw(fd)

    def write(data):
        os.write(fd, data)

    def exchange(request, timeout=1.0):
        """`request`, fenced with a status report, and what came back."""
        write(request + ESC + b"[5n")
        collected = b""
        deadline = time.time() + timeout
        while b"\x1b[0n" not in collected and time.time() < deadline:
            ready, _, _ = select.select([fd], [], [], 0.05)
            if ready:
                collected += os.read(fd, 4096)
        return collected

    def mode(number):
        answer = exchange(ESC + b"[?%d$p" % number)
        match = re.search(rb"\x1b\[\?%d;(\d+)\$y" % number, answer)
        return int(match.group(1)) if match else None

    record = {
        "host": f"{os.environ.get('TERM_PROGRAM', '?')} {os.environ.get('TERM_PROGRAM_VERSION', '')}",
        "term": os.environ.get("TERM"),
        "decrqm": {},
        "phases": {},
    }
    packed = fcntl.ioctl(fd, termios.TIOCGWINSZ, b"\0" * 8)
    rows, cols, xpixel, ypixel = struct.unpack("HHHH", packed)
    record["grid"] = [cols, rows]
    record["ioctl"] = [cols, rows, xpixel, ypixel]
    answer = exchange(ESC + b"[14t")
    match = re.search(rb"\x1b\[4;(\d+);(\d+)t", answer)
    record["text_area"] = [int(match.group(1)), int(match.group(2))] if match else None
    answer = exchange(ESC + b"[16t")
    match = re.search(rb"\x1b\[6;(\d+);(\d+)t", answer)
    record["cell"] = [int(match.group(1)), int(match.group(2))] if match else None
    record["decrqm"]["1006 at start"] = mode(1006)
    record["decrqm"]["1016 at start"] = mode(1016)

    write(ESC + b"[2J" + ESC + b"[H" + b"pixel mouse probe: hands off, the driver clicks here\r\n")
    open(os.path.join(ctl, "ready"), "w").close()

    def wait_for(name):
        path = os.path.join(ctl, name)
        deadline = time.time() + 45
        while not os.path.exists(path):
            if time.time() > deadline:
                raise TimeoutError(name)
            time.sleep(0.02)

    def collect(name):
        """Reports until the driver says `name` is over."""
        reports = []
        legacy = 0
        end = os.path.join(ctl, f"end-{name}")
        ending = None
        while ending is None or time.time() < ending:
            if ending is None and os.path.exists(end):
                ending = time.time() + 0.2
            ready, _, _ = select.select([fd], [], [], 0.02)
            if not ready:
                continue
            data = os.read(fd, 8192)
            now = time.time()
            for match in REPORT.finditer(data):
                button, x, y, final = match.groups()
                reports.append([int(button), int(x), int(y), final.decode(), now])
            legacy += len(LEGACY.findall(data))
        record["phases"][name] = reports
        record["phases"][f"{name}-legacy"] = legacy
        open(os.path.join(ctl, f"ack-{name}"), "w").close()

    def phase(name, setup):
        wait_for(f"begin-{name}")
        write(setup)
        time.sleep(0.05)
        record["decrqm"][f"1006 in {name}"] = mode(1006)
        record["decrqm"][f"1016 in {name}"] = mode(1016)
        open(os.path.join(ctl, f"go-{name}"), "w").close()
        collect(name)

    try:
        phase("cells", ESC + b"[?1000h" + ESC + b"[?1006h")
        phase("pixels", ESC + b"[?1016h")
        phase("motion-cells", ESC + b"[?1016l" + ESC + b"[?1006h" + ESC + b"[?1003h")
        phase("motion-pixels", ESC + b"[?1016h")
        phase("reset", ESC + b"[?1003l" + ESC + b"[?1000h" + ESC + b"[?1016l")
        phase("resend", ESC + b"[?1016h" + ESC + b"[?1006h")
    finally:
        write(ESC + b"[?1016l" + ESC + b"[?1006l" + ESC + b"[?1003l" + ESC + b"[?1000l")
        termios.tcsetattr(fd, termios.TCSADRAIN, saved)
        json.dump(record, open(out_path, "w"), indent=1)


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--analyze":
        analyze(sys.argv[2])
    else:
        main()
