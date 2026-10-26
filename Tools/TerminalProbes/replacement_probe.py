#!/usr/bin/env python3
"""Does a second virtual placement of an image, at another size, move it?

TUI resizes a picture that is already in the terminal by placing it again at
the new size (`a=p,U=1` with the new `c` and `r`), and draws the new box's
placeholder cells. Five panels, each the same ramp image drawn in a box of
20 x 10 cells:

  A. placed at 10 x 5, then placed again at 20 x 10 — a second `a=p` alone
  B. the same, with the image's placements deleted between (`a=d,d=i`, lower
     case: the pixels are kept)
  C. placed once, at 20 x 10 — the reference
  D. placed with a placement id (`p=1`) at 10 x 5, then again with `p=1` at
     20 x 10 — which the protocol says replaces it — and the cells naming
     placement 1 in their underline colour
  E. as D, the cells naming no placement

Read: does each panel fill its box as C does? Measured 2026-10-26:

  Ghostty 1.3.1  A no (its first placement's 10 x 5, in the corner)  B yes  D yes  E yes
  iTerm2 3.7.6   A yes  B NOTHING drawn  D yes  E yes
  kitty 0.49.1   not measured (no OpenGL 3.3 in the VM it was run from)

E is the only spelling both draw, so every virtual placement TUI makes names
placement 1 (`KittyGraphics.placement(id:columns:rows:)`), and a resize is a
second placement, which replaces it.

    python3 Tools/TerminalProbes/replacement_probe.py

Needs a terminal that draws Kitty Unicode placeholders (Ghostty, kitty,
iTerm2). Holds the screen for 30 seconds.
"""
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from placement_probe import placeholder_rows, ramp_image, transmit  # noqa: E402

WIDTH, HEIGHT = 120, 60
IDS = {"A": 2901, "B": 2902, "C": 2903, "D": 2904, "E": 2905}


def place(image_id, columns, rows, placement=None):
    """A virtual placement, quietly: no reply to echo onto the card."""
    named = f",p={placement}" if placement else ""
    return f"\x1b_Ga=p,U=1,i={image_id}{named},c={columns},r={rows},q=2\x1b\\"


def main():
    image = ramp_image(WIDTH, HEIGHT)
    out = ["\x1b[2J\x1b[H"]
    for image_id in IDS.values():
        out.append(transmit(image, image_id, WIDTH, HEIGHT).replace("q=0", "q=2"))
    out += [place(IDS["A"], 10, 5), place(IDS["A"], 20, 10)]
    out += [place(IDS["B"], 10, 5), f"\x1b_Ga=d,d=i,i={IDS['B']},q=2\x1b\\", place(IDS["B"], 20, 10)]
    out += [place(IDS["C"], 20, 10)]
    for name in ("D", "E"):
        out += [place(IDS[name], 10, 5, placement=1), place(IDS[name], 20, 10, placement=1)]
    out.append("\x1b[1;1HA: placed 10x5, then 20x10   B: same, placements deleted between   C: placed 20x10 once")
    out.append("\x1b[14;1HD: p=1 twice, cells name p=1   E: p=1 twice, cells name none")
    rows = {name: placeholder_rows(image_id, 20, 10) for name, image_id in IDS.items()}
    # D's cells name placement 1: the underline colour carries a placement id.
    rows["D"] = ["\x1b[58;5;1m" + line + "\x1b[59m" for line in rows["D"]]
    for row in range(10):
        out.append(f"\x1b[{row + 3};1H{rows['A'][row]}\x1b[{row + 3};35H{rows['B'][row]}\x1b[{row + 3};70H{rows['C'][row]}")
        out.append(f"\x1b[{row + 16};1H{rows['D'][row]}\x1b[{row + 16};35H{rows['E'][row]}")
    out.append("\x1b[27;1H")
    sys.stdout.write("".join(out))
    sys.stdout.flush()
    time.sleep(30)


if __name__ == "__main__":
    main()
