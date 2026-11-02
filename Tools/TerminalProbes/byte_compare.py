#!/usr/bin/env python3
"""Do two builds of an app write the same bytes to a terminal? For a claim that a
host pays nothing for a path it does not take.

Runs each binary on a pty that answers as a plain terminal would (DA1 with no Sixel,
DSR, CPR; nothing to Kitty's questions), types the same keys at the same times, and
compares the distinct held frames (`?2026h` to `?2026l`). Distinct, because how many
times an idle frame repeats depends on the clock. And with the numbers of each colour
taken out, because a focus ring's breath depends on it too: the frames compared say
which cells were written with which text, escapes and picture data.

An old build against itself is the control: what differs there is the clock.

    python3 Tools/TerminalProbes/byte_compare.py OLD NEW [--page images] [--keys pppp]
"""
import argparse
import hashlib
import os
import re
import select
import struct
import fcntl
import termios
import time

HOLD_ON = b"\x1b[?2026h"
HOLD_OFF = b"\x1b[?2026l"
COLOUR = re.compile(rb"(?:38|48|58);(?:5;\d+|2;\d+;\d+)")


def capture(binary, page, keys, env_extra):
    pid, fd = os.forkpty()
    if pid == 0:
        os.environ.update(env_extra)
        os.chdir(os.path.dirname(os.path.abspath(binary)))
        os.execv(binary, [binary, "--page", page])
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 1000, 600))
    out = bytearray()
    asked = 0
    started = time.time()
    typed = False
    quit_sent = False
    while time.time() - started < 12:
        ready, _, _ = select.select([fd], [], [], 0.05)
        if ready:
            try:
                data = os.read(fd, 1 << 16)
            except OSError:
                break
            if not data:
                break
            out += data
            tail = bytes(out[asked:])
            asked = len(out)
            for _ in range(tail.count(b"\x1b[c")):
                os.write(fd, b"\x1b[?62;22c")
            for _ in range(tail.count(b"\x1b[5n")):
                os.write(fd, b"\x1b[0n")
            for _ in range(tail.count(b"\x1b[6n")):
                os.write(fd, b"\x1b[1;1R")
        elapsed = time.time() - started
        if not typed and elapsed > 3:
            typed = True
            os.write(fd, keys.encode())
        if not quit_sent and elapsed > 8:
            quit_sent = True
            os.write(fd, b"\x11")
    try:
        os.close(fd)
        os.waitpid(pid, 0)
    except OSError:
        pass
    return bytes(out)


def frames(data):
    found = {}
    start = 0
    while True:
        begin = data.find(HOLD_ON, start)
        if begin < 0:
            break
        end = data.find(HOLD_OFF, begin)
        if end < 0:
            break
        frame = data[begin:end]
        found[hashlib.sha256(COLOUR.sub(b"C", frame)).hexdigest()] = frame
        start = end + len(HOLD_OFF)
    return found


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("old")
    parser.add_argument("new")
    parser.add_argument("--page", default="images")
    parser.add_argument("--keys", default="pppp")
    arguments = parser.parse_args()
    environment = {"TERM": "xterm-256color", "TERM_PROGRAM": "byte-compare", "TUI_CONFIG_DIR": "/tmp/tui-byte-compare"}
    for graphics in (None, "1", "0"):
        extra = dict(environment)
        if graphics:
            extra["TUI_GRAPHICS"] = graphics
        old = capture(arguments.old, arguments.page, arguments.keys, extra)
        new = capture(arguments.new, arguments.page, arguments.keys, extra)
        old_frames, new_frames = frames(old), frames(new)
        only_old = [len(old_frames[key]) for key in old_frames.keys() - new_frames.keys()]
        only_new = [len(new_frames[key]) for key in new_frames.keys() - old_frames.keys()]
        print(
            f"TUI_GRAPHICS={graphics}: bytes {len(old)} -> {len(new)}; distinct frames "
            f"{len(old_frames)} -> {len(new_frames)}; only in old {sorted(only_old)[:6]}, only in new {sorted(only_new)[:6]}")


if __name__ == "__main__":
    main()
