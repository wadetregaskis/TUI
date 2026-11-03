#!/usr/bin/env python3
"""Does this terminal PLAY a Kitty graphics animation, or only say it will?

The protocol's animation commands (`a=f` adds a frame, `a=a` drives playback) let
the terminal play a picture by itself. A reply proves nothing: the survey has a
beta that acknowledged and drew nothing. So this asks and answers, then draws a
card to be looked at. Replies go to $PROBE_OUT, the card to the screen.

Numbers, written to $PROBE_OUT:

  features     the replies to the feature queries (`a=q,e=f`, `e=a`, `e=c`, kitty
               0.50 on). A host that does not know them answers a plain query
               with no `e`, or nothing. A key missing from a reply is not supported
  frame        the reply to `a=f` adding a frame, spoken aloud (`q=0`)
  control      the replies to `a=a` selecting a frame, setting a gap, and running
  compose      the reply to `a=c`
  moved        whether any of them moved the cursor

The card, on a blue field that a transparent pixel shows, each panel 16 x 6 cells.
Frames are solid colours: 1 RED, 2 GREEN, 3 WHITE, 4 YELLOW.

  A  client driven: `a=a,c=3` once. WHITE if it obeyed, RED if not
  B  terminal driven: `s=3`, 500 ms a frame, for ever. Should cycle R G W Y
  C  as B, placed by a Unicode placeholder (what `Image` draws with)
  D  `v=2`: one pass of the loop, then stays. Should end on YELLOW and stay
  E  stopped: run, then `s=1` straight away. Should hold, not cycle
  F  disposal: frame 1 a red block top-left and the rest transparent, frame 2 a
     white block bottom-right, sent with `X=1` over a clear canvas. Must NEVER
     show both blocks: the blue shows through the corner that is not drawn
  G  disposal the other way: frame 2 with `c=1` and the default alpha blend, which
     SHOULD show both blocks, as GIF's "do not dispose" asks
  H  a fast one: 50 ms a frame, 8 frames of a bar moving along; judge it by eye

    python3 Tools/TerminalProbes/animation_probe.py

Holds the card for $PROBE_HOLD seconds (default 60) on the alternate screen, then
leaves, deleting what it sent. Screenshot at least twice, 700 ms or more apart.
"""
import base64
import json
import os
import sys
import termios
import time
import tty

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import probe_stamp  # noqa: E402
from placement_probe import ask, cursor, placeholder_rows  # noqa: E402

COLUMNS, ROWS = 16, 6
WIDTH, HEIGHT = 64, 48
PANELS = {
    "A": (2, 1), "B": (2, 19), "C": (2, 37), "D": (2, 55),
    "E": (10, 1), "F": (10, 19), "G": (10, 37), "H": (10, 55),
}
IDS = {name: 3400 + index for index, name in enumerate(PANELS)}
QUERY_ID = 3499
RED, GREEN, WHITE, YELLOW = (255, 0, 0, 255), (0, 255, 0, 255), (255, 255, 255, 255), (255, 255, 0, 255)
CLEAR = (0, 0, 0, 0)


def apc(keys, payload=""):
    return f"\x1b_G{keys}{';' + payload if payload else ''}\x1b\\"


def solid(colour):
    return bytes(colour) * (WIDTH * HEIGHT)


def block(colour, left, top, right, bottom):
    """A `colour` rectangle on a clear picture."""
    rows = []
    for y in range(HEIGHT):
        for x in range(WIDTH):
            rows.append(bytes(colour if left <= x < right and top <= y < bottom else CLEAR))
    return b"".join(rows)


def chunks(action, pixels, chunk=4096):
    """`action` and its pixels in the protocol's chunks. Each continuation of an
    `a=f` must say `a=f` again, as the protocol has it."""
    encoded = base64.standard_b64encode(pixels).decode()
    parts = [encoded[i:i + chunk] for i in range(0, len(encoded), chunk)] or [""]
    out = []
    for index, part in enumerate(parts):
        more = 1 if index < len(parts) - 1 else 0
        if index == 0:
            out.append(apc(f"{action},m={more}", part))
        else:
            keys = "a=f," if action.startswith("a=f") else ""
            out.append(apc(f"{keys}q=2,m={more}", part))
    return "".join(out)


def root(image_id, pixels):
    return chunks(f"a=t,t=d,f=32,s={WIDTH},v={HEIGHT},i={image_id},q=2", pixels)


def frame(image_id, pixels, gap=500, extra="", quiet=2):
    return chunks(f"a=f,t=d,f=32,s={WIDTH},v={HEIGHT},i={image_id},z={gap},q={quiet}{extra}", pixels)


def place_classic(image_id):
    return apc(f"a=p,i={image_id},p=1,c={COLUMNS},r={ROWS},C=1,z=1,q=2")


def cycle(image_id, gap=500):
    """The four colours, each showing for `gap`. The root frame's gap has to be set
    by a control: it is sent with no `z`."""
    return (
        root(image_id, solid(RED))
        + frame(image_id, solid(GREEN), gap)
        + frame(image_id, solid(WHITE), gap)
        + frame(image_id, solid(YELLOW), gap)
        + apc(f"a=a,i={image_id},r=1,z={gap},q=2")
    )


def replies(fd):
    """The questions, one at a time, each with its reply."""
    before = cursor(fd)
    result = {"features": {}}
    for feature in "fac":
        keys = f"a=q,i={QUERY_ID},e={feature}"
        if feature == "f":
            keys += ",r=1,X=1,c=1"
        elif feature == "a":
            keys += ",s=3,v=1,c=1,r=1,z=40"
        result["features"][feature] = repr(ask(fd, apc(keys).encode()))
    os.write(fd, root(QUERY_ID, solid(RED)).encode())
    # One chunk, 4 x 4: only the last chunk of a transmission is answered, and that
    # is `q=2` here, which would make a host that answers look silent.
    little = apc(f"a=f,t=d,f=32,s=4,v=4,i={QUERY_ID},z=100,q=0", base64.standard_b64encode(bytes(GREEN) * 16).decode())
    result["frame"] = repr(ask(fd, little.encode()))
    result["control"] = {
        "select": repr(ask(fd, apc(f"a=a,i={QUERY_ID},c=2,q=0").encode())),
        "gap": repr(ask(fd, apc(f"a=a,i={QUERY_ID},r=1,z=100,q=0").encode())),
        "run": repr(ask(fd, apc(f"a=a,i={QUERY_ID},s=3,v=1,q=0").encode())),
        "stop": repr(ask(fd, apc(f"a=a,i={QUERY_ID},s=1,q=0").encode())),
    }
    result["compose"] = repr(ask(fd, apc(f"a=c,i={QUERY_ID},r=1,c=2,q=0").encode()))
    os.write(fd, apc(f"a=d,d=I,i={QUERY_ID},q=2").encode())
    result["moved"] = cursor(fd) != before
    return result


def card(fd):
    out = ["\x1b[48;5;21m\x1b[2J\x1b[H"]
    for name, (row, column) in PANELS.items():
        out.append(f"\x1b[{row - 1};{column}H{name}")
        for offset in range(ROWS):
            out.append(f"\x1b[{row + offset};{column}H" + " " * COLUMNS)

    def at(name):
        row, column = PANELS[name]
        return f"\x1b[{row};{column}H"

    # A: client driven.
    out += [cycle(IDS["A"]), at("A"), place_classic(IDS["A"]), apc(f"a=a,i={IDS['A']},c=3,q=2")]
    # B: terminal driven.
    out += [cycle(IDS["B"]), at("B"), place_classic(IDS["B"]), apc(f"a=a,i={IDS['B']},s=3,v=1,q=2")]
    # C: the same by placeholder.
    out += [cycle(IDS["C"]), apc(f"a=p,U=1,i={IDS['C']},c={COLUMNS},r={ROWS},q=2")]
    row, column = PANELS["C"]
    for offset, line in enumerate(placeholder_rows(IDS["C"], COLUMNS, ROWS)):
        out.append(f"\x1b[{row + offset};{column}H{line}\x1b[39m\x1b[48;5;21m")
    out.append(apc(f"a=a,i={IDS['C']},s=3,v=1,q=2"))
    # D: one pass.
    out += [cycle(IDS["D"]), at("D"), place_classic(IDS["D"]), apc(f"a=a,i={IDS['D']},s=3,v=2,q=2")]
    # E: run, then stop.
    out += [
        cycle(IDS["E"]), at("E"), place_classic(IDS["E"]),
        apc(f"a=a,i={IDS['E']},s=3,v=1,q=2"), apc(f"a=a,i={IDS['E']},s=1,q=2"),
    ]
    half = (WIDTH // 2, HEIGHT // 2)
    corner_one = block(RED, 0, 0, *half)
    corner_two = block(WHITE, half[0], half[1], WIDTH, HEIGHT)
    # F: replaced, the canvas clear: only ever one block.
    out += [
        root(IDS["F"], corner_one),
        frame(IDS["F"], corner_two, 500, ",X=1"),
        apc(f"a=a,i={IDS['F']},r=1,z=500,q=2"),
        at("F"), place_classic(IDS["F"]), apc(f"a=a,i={IDS['F']},s=3,v=1,q=2"),
    ]
    # G: blended over frame 1: both blocks, on frame 2.
    out += [
        root(IDS["G"], corner_one),
        frame(IDS["G"], corner_two, 500, ",c=1"),
        apc(f"a=a,i={IDS['G']},r=1,z=500,q=2"),
        at("G"), place_classic(IDS["G"]), apc(f"a=a,i={IDS['G']},s=3,v=1,q=2"),
    ]
    # H: a bar moving along at 50 ms a frame.
    steps = 8
    width = WIDTH // steps
    out.append(root(IDS["H"], block(YELLOW, 0, 0, width, HEIGHT)))
    for step in range(1, steps):
        out.append(frame(IDS["H"], block(YELLOW, step * width, 0, (step + 1) * width, HEIGHT), 50, ",X=1"))
    out += [
        apc(f"a=a,i={IDS['H']},r=1,z=50,q=2"),
        at("H"), place_classic(IDS["H"]), apc(f"a=a,i={IDS['H']},s=3,v=1,q=2"),
        "\x1b[18;1H\x1b[0mCard up. Panels: see animation_probe.py\x1b[K",
    ]
    os.write(fd, "".join(out).encode())


def card_on_tty(path):
    """The card alone, written to another window's terminal as a program's output
    would be: for a window a capture tool can see that nothing can be launched in.
    Nothing is typed there and nothing runs there; no question is asked, since the
    replies would go to whatever is reading that terminal."""
    fd = os.open(path, os.O_WRONLY | os.O_NOCTTY)
    os.write(fd, b"\x1b[?1049h\x1b[?25l\x1b[H")
    try:
        card(fd)
        time.sleep(float(os.environ.get("PROBE_HOLD", "60")))
    finally:
        deletes = "".join(apc(f"a=d,d=I,i={image_id},q=2") for image_id in IDS.values())
        os.write(fd, (deletes + "\x1b[0m\x1b[?25h\x1b[?1049l").encode())
        os.close(fd)


def main():
    if os.environ.get("PROBE_TTY"):
        return card_on_tty(os.environ["PROBE_TTY"])
    fd = sys.stdin.fileno()
    if not os.isatty(fd):
        sys.exit("animation_probe: run this IN the terminal under test")
    old = termios.tcgetattr(fd)
    tty.setraw(fd)
    os.write(fd, b"\x1b[?1049h\x1b[?25l\x1b[H")
    try:
        result = {"stamp": probe_stamp.stamp(fd, "animation_probe", use_alt=True)}
        result.update(replies(fd))
        result["card_at"] = time.time()
        card(fd)
        path = os.environ.get("PROBE_OUT", "animation_probe.json")
        with open(path, "w") as out:
            json.dump(result, out, indent=2, default=str)
        time.sleep(float(os.environ.get("PROBE_HOLD", "60")))
    finally:
        deletes = "".join(apc(f"a=d,d=I,i={image_id},q=2") for image_id in IDS.values())
        os.write(fd, (deletes + "\x1b[0m\x1b[?25h\x1b[?1049l").encode())
        termios.tcsetattr(fd, termios.TCSADRAIN, old)


if __name__ == "__main__":
    main()
