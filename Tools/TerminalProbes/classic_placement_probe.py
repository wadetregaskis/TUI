#!/usr/bin/env python3
"""Does this terminal draw a Kitty CLASSIC placement the way `Image` needs it?

The questions of `Terminal graphics protocols.md` §12.4, and what the startup
handshake asks (`TerminalGraphicsQuery`). Two halves.

Numbers, written to $PROBE_OUT (the cursor by CPR, the replies as they came):

  moved_by_transmit  a quiet `a=t` moved the cursor: the host PRINTS APC
  virtual            the reply to `a=p,U=1,q=0`, and whether the cursor moved.
                     A host that does not know `U` draws at the cursor and moves
                     it, whatever it answers: source-read on Konsole and WezTerm
  classic            the reply to `a=p,q=0` with no `C`, and whether it moved.
                     Moved is the evidence on a host that never answers a
                     placement (source-read on WezTerm)
  c1_on_last_row     a placement on the last row with `C=1`: the cursor stayed,
                     and row 1 is still row 1 (read it off the card)

The card, one ramp 20 x 8 cells in each panel, on a blue field:

  A  whole: `c=20,r=8,C=1,z=1`
  B  two crops tiled, left half and right half: is the source rectangle honoured,
     and does a seam show? It should look exactly like A
  C  as A, then spaces written over its left half AFTER it: on a host that
     keeps images in its cells the picture has a hole; otherwise it is whole
  D  placed at 10 x 4, then again by the same (i, p) at 20 x 8: fills, as A?
  E  placed, deleted by placement (`d=i`): empty, and the pixels are kept
  F  as E, then placed again: drawn with no second transmit?

    python3 Tools/TerminalProbes/classic_placement_probe.py

Holds the card for 45 seconds on the alternate screen, then leaves.
"""
import json
import os
import sys
import termios
import time
import tty

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import probe_stamp  # noqa: E402
from placement_probe import ask, cursor, ramp_image, transmit  # noqa: E402

COLUMNS, ROWS = 20, 8
WIDTH, HEIGHT = 160, 128
IDS = {name: 3100 + index for index, name in enumerate("ABCDEFG")}
ONE_PIXEL_VIRTUAL, ONE_PIXEL_CLASSIC = 3201, 3202
PANELS = {"A": (2, 1), "B": (2, 25), "C": (2, 49), "D": (12, 1), "E": (12, 25), "F": (12, 49)}


def apc(keys):
    return f"\x1b_G{keys}\x1b\\"


def place(image_id, placement, columns=COLUMNS, rows=ROWS, crop=None):
    source = f"x={crop[0]},y={crop[1]},w={crop[2]},h={crop[3]}," if crop else ""
    return apc(f"a=p,i={image_id},p={placement},{source}c={columns},r={rows},C=1,z=1,q=2")


def one_pixel(image_id):
    return apc(f"a=t,q=2,f=32,t=d,s=1,v=1,i={image_id};AAAAAA==")


def moved(before, after):
    return None if before is None or after is None else before != after


def handshake(fd):
    """What the startup handshake would see, one step at a time."""
    os.write(fd, b"\x1b[3;3H")
    start = cursor(fd)
    os.write(fd, (one_pixel(ONE_PIXEL_VIRTUAL) + one_pixel(ONE_PIXEL_CLASSIC)).encode())
    after_transmit = cursor(fd)
    reply = ask(fd, apc(f"a=p,U=1,q=0,i={ONE_PIXEL_VIRTUAL},c=1,r=1").encode())
    after_virtual = cursor(fd)
    classic_reply = ask(fd, apc(f"a=p,q=0,i={ONE_PIXEL_CLASSIC},p=1,c=1,r=1,z=1").encode())
    after_classic = cursor(fd)
    os.write(fd, (apc(f"a=d,d=I,q=2,i={ONE_PIXEL_VIRTUAL}") + apc(f"a=d,d=I,q=2,i={ONE_PIXEL_CLASSIC}")).encode())
    return {
        "moved_by_transmit": moved(start, after_transmit),
        "virtual": {"reply": repr(reply), "moved": moved(after_transmit, after_virtual)},
        "classic": {
            "reply": repr(classic_reply),
            "moved": moved(after_virtual, after_classic),
            "positions": [after_virtual, after_classic],
        },
    }


def last_row(fd):
    """A `C=1` placement on the last row: does it scroll? Read row 1 on the card too."""
    os.write(fd, b"\x1b[999;1H")
    bottom = cursor(fd)
    os.write(fd, one_pixel(ONE_PIXEL_CLASSIC).encode())
    os.write(fd, apc(f"a=p,i={ONE_PIXEL_CLASSIC},p=2,c=4,r=3,C=1,z=1,q=2").encode())
    after = cursor(fd)
    return {"bottom": bottom, "after": after, "stayed": bottom == after}


def card(fd):
    image = ramp_image(WIDTH, HEIGHT)
    out = ["\x1b[48;5;21m\x1b[2J\x1b[H"]
    out.append("row 1: if this line is not on the top row, the last-row placement scrolled\x1b[K")
    for name, (row, column) in PANELS.items():
        out.append(f"\x1b[{row - 1};{column}H{name}")
        for offset in range(ROWS):
            out.append(f"\x1b[{row + offset};{column}H" + " " * COLUMNS)
    for image_id in IDS.values():
        out.append(transmit(image, image_id, WIDTH, HEIGHT).replace("q=0", "q=2"))

    def at(name):
        row, column = PANELS[name]
        return f"\x1b[{row};{column}H"

    out += [at("A"), place(IDS["A"], 1)]
    out += [at("B"), place(IDS["B"], 1, COLUMNS // 2, ROWS, (0, 0, WIDTH // 2, HEIGHT))]
    row, column = PANELS["B"]
    out += [f"\x1b[{row};{column + COLUMNS // 2}H", place(IDS["B"], 2, COLUMNS // 2, ROWS, (WIDTH // 2, 0, WIDTH // 2, HEIGHT))]
    out += [at("C"), place(IDS["C"], 1)]
    row, column = PANELS["C"]
    for offset in range(ROWS):
        out.append(f"\x1b[{row + offset};{column}H" + " " * (COLUMNS // 2))
    out += [at("D"), place(IDS["D"], 1, COLUMNS // 2, ROWS // 2), place(IDS["D"], 1)]
    out += [at("E"), place(IDS["E"], 1), apc(f"a=d,d=i,i={IDS['E']},p=1,q=2")]
    out += [at("F"), place(IDS["F"], 1), apc(f"a=d,d=i,i={IDS['F']},p=1,q=2"), place(IDS["F"], 1)]
    os.write(fd, "".join(out).encode())


def card_two(fd):
    """Second card, `PROBE_CARD=2`: the crop's other spellings, what cells do to a
    placement, and `z`. One ramp 20 x 8 in each panel unless it says otherwise:

      G  `x,y,w,h` with no `c,r`: the middle quarter at its native 80 x 64 px
      H  `x,y,w,h` with `a=T`, a second transmission placed at once
      I  placed, then `ESC[2K` on each of its rows: is it still drawn?
      J  placed BEFORE this card's `ESC[2J`, placed again after it, no second
         transmit: did the image outlive the erase?
      K  `z=-1` over this blue field: drawn, or hidden by the field?
      L  `z=-1` over cells of the terminal's default field
      M  `z=1`, then TEXT over its first rows: is the text above the picture?
    """
    image = ramp_image(WIDTH, HEIGHT)
    panels = {"G": (2, 1), "H": (2, 25), "I": (2, 49), "J": (12, 1), "K": (12, 25), "L": (12, 49), "M": (22, 1)}
    ids = {name: 3300 + index for index, name in enumerate(panels)}
    os.write(fd, transmit(image, ids["J"], WIDTH, HEIGHT).replace("q=0", "q=2").encode())
    os.write(fd, (f"\x1b[{panels['J'][0]};{panels['J'][1]}H" + place(ids["J"], 1)).encode())
    out = ["\x1b[48;5;21m\x1b[2J\x1b[H"]
    for name, (row, column) in panels.items():
        out.append(f"\x1b[{row - 1};{column}H{name}")
        if name != "J":
            out.append(transmit(image, ids[name], WIDTH, HEIGHT).replace("q=0", "q=2"))

    def at(name):
        row, column = panels[name]
        return f"\x1b[{row};{column}H"

    out += [at("G"), apc(f"a=p,i={ids['G']},p=1,x=40,y=32,w=80,h=64,C=1,z=1,q=2")]
    row, column = panels["H"]
    payload = transmit(image, ids["H"] + 50, WIDTH, HEIGHT).replace("q=0", "q=2").replace("a=t", "a=T,x=40,y=32,w=80,h=64,C=1,z=1", 1)
    out += [at("H"), payload]
    out += [at("I"), place(ids["I"], 1)]
    row, _ = panels["I"]
    for offset in range(ROWS):
        out.append(f"\x1b[{row + offset};49H\x1b[2K")
    out += [at("J"), place(ids["J"], 1)]
    out += [at("K"), apc(f"a=p,i={ids['K']},p=1,c={COLUMNS},r={ROWS},C=1,z=-1,q=2")]
    row, column = panels["L"]
    for offset in range(ROWS):
        out.append(f"\x1b[{row + offset};{column}H\x1b[49m" + " " * COLUMNS + "\x1b[48;5;21m")
    out += [at("L"), apc(f"a=p,i={ids['L']},p=1,c={COLUMNS},r={ROWS},C=1,z=-1,q=2")]
    out += [at("M"), place(ids["M"], 1, COLUMNS, 3), at("M"), "TEXT over z=1"]
    os.write(fd, "".join(out).encode())


def main():
    fd = sys.stdin.fileno()
    if not os.isatty(fd):
        sys.exit("classic_placement_probe: run this IN the terminal under test")
    old = termios.tcgetattr(fd)
    record = {}
    try:
        tty.setraw(fd)
        record["stamp"] = probe_stamp.stamp(fd, "classic_placement_probe", use_alt=False)
        os.write(fd, b"\x1b[?1049h\x1b[2J")
        record["handshake"] = handshake(fd)
        if os.environ.get("PROBE_CARD") == "2":
            card_two(fd)
        else:
            card(fd)
            record["c1_on_last_row"] = last_row(fd)
        with open(os.environ.get("PROBE_OUT", "classic_placement_probe.json"), "w") as out:
            json.dump(record, out, indent=2, ensure_ascii=False)
        time.sleep(float(os.environ.get("PROBE_HOLD", "45")))
    finally:
        os.write(fd, b"\x1b[0m\x1b[2J" + "".join(apc(f"a=d,d=I,q=2,i={i}") for i in IDS.values()).encode() + b"\x1b[?1049l")
        termios.tcsetattr(fd, termios.TCSADRAIN, old)


if __name__ == "__main__":
    main()
