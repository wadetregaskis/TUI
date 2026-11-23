#!/usr/bin/env python3
"""Does a picture drawn by Unicode placeholders survive a screen switch?

TUI draws a picture as a virtual placement (`a=p,U=1,p=1`) and placeholder
cells naming its image, on the alternate screen. A ⌃Z, a hand-off to another
program and the recovery from an external stop all switch screens under it:

  (a) a ⌃Z or a hand-off leaves the alternate screen and comes back
      (`?1049l`, then `?1049h`), and the first frame after writes every row
      again;
  (b) the recovery from an external `SIGSTOP`, which handed nothing back,
      enters the alternate screen while already on it (`?1049h` alone).

The survey's Q8 measured a CLASSIC placement's strip across the round trip
(Ghostty 1.3.1 freed it, iTerm2 kept it). This asks the same of a picture
drawn the way `Image` draws one (hunt item H-58). Each step uses a fresh
image, placed and drawn first, so one step's answer cannot leak into the next:

  1. baseline: the picture placed and drawn, then the placement asked for again
     by id (`a=p`, which answers `OK` or `ENOENT`)
  2. (b): `?1049h` alone, the cells written again, LOOK; then the `a=p` ask,
     which places it again, LOOK again
  3. (a): `?1049l` (LOOK at the primary screen), `?1049h`, the cells written
     again, LOOK; then the `a=p` ask, LOOK again
  4. control: a new image sent and placed after the round trip, drawn

Read each LOOK as: the picture drawn, or not. "Not drawn before the ask, drawn
after" is a placement lost with the image kept; "`ENOENT`" is the image freed.
What TUI does after a retake depends only on the first look: it writes the
cells again and nothing else unless its image store forgets the picture.

    python3 Tools/TerminalProbes/screen_switch_picture_probe.py

Run INSIDE the terminal under test (Ghostty, kitty, iTerm2). Writes JSON to
$PROBE_OUT (default ./screen_switch_picture_probe.json). Each LOOK holds the
screen for $PROBE_HOLD seconds (default 4); with $PROBE_STEP_DIR set it holds
until a file named for the look (`look-2b-cells`, …) appears there, for a
driver that screenshots each look, or for 120 seconds.

Measured 2026-11-23 (macOS 15.8.3):

  Ghostty 1.4.0  every `a=p` OK, the round trip's too: the image kept. Not
                 looked at: `open -na` makes a second instance, which the
                 screenshot tool cannot reach
  iTerm2 3.7.7   every `a=p` OK; drawn at every look but the primary screen
  kitty 0.49.1   not measured (no OpenGL 3.3 in the VM it was run from)

See Terminal compatibility survey.md, "A placeholder picture across a screen
switch (Q8, H-58)".
"""
import json
import os
import sys
import termios
import time
import tty

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import probe_stamp  # noqa: E402
from placement_probe import ask, placeholder_rows, ramp_image, render, transmit  # noqa: E402

COLUMNS, ROWS = 20, 8
WIDTH, HEIGHT = 160, 136
IDS = {"baseline": 3101, "b": 3102, "a": 3103, "control": 3104}
STEP_TIMEOUT = 120


def place(image_id, quiet):
    """A virtual placement naming placement 1, as TUI's
    (`KittyGraphics.placement(id:columns:rows:)`); `q=0` asks for the reply."""
    return f"\x1b_Ga=p,U=1,i={image_id},p=1,c={COLUMNS},r={ROWS},q={2 if quiet else 0}\x1b\\"


def draw(image_id, label, column=1):
    """The label on row 1 and the picture's placeholder cells from row 3."""
    out = [f"\x1b[1;1H\x1b[2K{label}"]
    for row, line in enumerate(placeholder_rows(image_id, COLUMNS, ROWS)):
        out.append(f"\x1b[{row + 3};{column}H{line}")
    out.append(f"\x1b[{ROWS + 4};1H")
    return "".join(out)


def put(fd, text):
    os.write(fd, text.encode("utf-8"))


def look(name, record):
    """Holds the screen for a look, and notes when it was held."""
    record["looks"].append({"name": name, "at": time.time()})
    directory = os.environ.get("PROBE_STEP_DIR")
    if not directory:
        time.sleep(float(os.environ.get("PROBE_HOLD", "4")))
        return
    with open(os.path.join(directory, "ready"), "w") as handle:
        handle.write(name)
    gate = os.path.join(directory, f"look-{name}")
    deadline = time.time() + STEP_TIMEOUT
    while not os.path.exists(gate) and time.time() < deadline:
        time.sleep(0.1)


def setup(fd, image, name, label):
    """A fresh image, placed and drawn, and the placement asked for by id."""
    image_id = IDS[name]
    put(fd, transmit(image, image_id, WIDTH, HEIGHT).replace("q=0", "q=2"))
    put(fd, place(image_id, quiet=True))
    put(fd, draw(image_id, label))
    return render(ask(fd, place(image_id, quiet=False).encode("latin-1"), timeout=2.0))


def main():
    out_path = os.environ.get("PROBE_OUT", "screen_switch_picture_probe.json")
    fd = os.open("/dev/tty", os.O_RDWR)
    image = ramp_image(WIDTH, HEIGHT)
    record = {"looks": [], "replies": {}}
    old = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)
        record.update(probe_stamp.stamp(fd, "screen_switch_picture_probe", use_alt=True))
        put(fd, "\x1b[?1049h\x1b[2J\x1b[?25l")
        replies = record["replies"]

        replies["1_baseline"] = setup(fd, image, "baseline", "1: baseline, placed and drawn")
        look("1-baseline", record)

        replies["2b_before"] = setup(fd, image, "b", "2b: placed and drawn, before ?1049h alone")
        look("2b-before", record)
        put(fd, "\x1b[?1049h")
        put(fd, draw(IDS["b"], "2b: after ?1049h alone, cells written again (no a=p)"))
        look("2b-cells", record)
        replies["2b_after"] = render(ask(fd, place(IDS["b"], quiet=False).encode("latin-1"), timeout=2.0))
        put(fd, draw(IDS["b"], "2b: after ?1049h alone, then a=p by id: " + replies["2b_after"][:60]))
        look("2b-asked", record)

        put(fd, "\x1b[2J")
        replies["3a_before"] = setup(fd, image, "a", "3a: placed and drawn, before ?1049l ?1049h")
        look("3a-before", record)
        put(fd, "\x1b[?1049l")
        look("3a-primary", record)
        put(fd, "\x1b[?1049h")
        put(fd, draw(IDS["a"], "3a: after ?1049l ?1049h, cells written again (no a=p)"))
        look("3a-cells", record)
        replies["3a_after"] = render(ask(fd, place(IDS["a"], quiet=False).encode("latin-1"), timeout=2.0))
        put(fd, draw(IDS["a"], "3a: after the round trip, then a=p by id: " + replies["3a_after"][:60]))
        look("3a-asked", record)

        put(fd, "\x1b[2J")
        replies["4_control"] = setup(fd, image, "control", "4: control, a new image sent after the round trip")
        look("4-control", record)

        for image_id in IDS.values():
            put(fd, f"\x1b_Ga=d,d=I,i={image_id},q=2\x1b\\")
    finally:
        put(fd, "\x1b[?25h\x1b[?1049l")
        termios.tcsetattr(fd, termios.TCSADRAIN, old)
        os.close(fd)
    with open(out_path, "w") as handle:
        json.dump(record, handle, indent=2)
        handle.write("\n")
    print(json.dumps(record["replies"], indent=2))


if __name__ == "__main__":
    main()
