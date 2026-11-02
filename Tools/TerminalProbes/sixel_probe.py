#!/usr/bin/env python3
"""Can `Image` draw by Sixel on this terminal? `Terminal graphics protocols.md` §6.4.

The one answer that could kill it: does a written space erase Sixel pixels, and
how does a repair of one row behave? Numbers, written to $PROBE_OUT:

  da1            the reply, and whether it says 4
  xtsmgraphics   the reply to the registers and geometry questions, if any
  cell           the cell in pixels, by `CSI 16 t`, and `TIOCGWINSZ`'s
  cursor_after   where the cursor is after a picture away from any edge, with
                 no mode set, with DECSDM (`?80h`) and with `?8452h`
  held           how long half a megabyte took inside a `?2026` hold, by DSR

Then cards, one at a time, each waiting for `$PROBE_STEP.N` to appear so that it
can be looked at before the next (or for $PROBE_HOLD seconds). Each picture is a
ramp with a dark line on every cell boundary, so that a picture's size against
the cells can be read off. The field is blue.

Card 1, how pictures go away:

  A  whole: is it the size asked for? `|` marks the cell after its right edge
  B  spaces over its left half: top half with SGR reset, bottom half on blue
  C  `ECH` over its left half
  D  `ESC[K` from its middle, on its top half
  E  text over its middle, on a stated background
  F  P2=1 with holes, over text: does what is under show through the holes?
  G  a second picture, of one row, over its row 2, with no erase first
  H  spaces across its row 2, then that row's pixels again: the repair
  I  a picture not a whole number of bands tall (pixels past it unset), with
     text on the row below it, written first: is the text still there?

Card 2, what a picture is:

  J  two pictures, each defining register 1 differently: did the first change?
  K  pictures tiled by rows, each sent alone: does a seam show?
  L  scrolled up one row by a scroll region: did it go with its row?
  M  `ESC[2J` after: `M` here means the erase erased it (row checks below)
  N  half a megabyte inside `?2026`, then one row over it

Cards 3 to 5, the last row, one picture ending on the last row, under no mode,
DECSDM and `?8452h`: did the top row move? The record has the cursor.

    python3 Tools/TerminalProbes/sixel_probe.py          # all of it
    PROBE_DA1_ONLY=1 python3 Tools/TerminalProbes/sixel_probe.py
"""
import fcntl
import json
import os
import random
import select
import struct
import sys
import termios
import time
import tty

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import probe_stamp  # noqa: E402

BLUE = "\x1b[48;5;21m"
RESET = "\x1b[0m"


def read_reply(fd, until, timeout=1.5):
    """Bytes from the terminal until a byte in `until`, or the time runs out."""
    deadline = time.time() + timeout
    reply = b""
    while time.time() < deadline:
        ready, _, _ = select.select([fd], [], [], max(0, deadline - time.time()))
        if not ready:
            break
        reply += os.read(fd, 4096)
        if reply and reply[-1:] in until:
            break
    return reply.decode(errors="replace")


def ask(fd, query, until, timeout=1.5):
    os.write(fd, query.encode())
    return read_reply(fd, until, timeout)


def cursor(fd):
    reply = ask(fd, "\x1b[6n", b"R")
    try:
        row, column = reply.split("[")[-1].rstrip("R").split(";")
        return [int(row), int(column)]
    except ValueError:
        return None


def cell_size(fd):
    """The cell in Sixel pixels. `TIOCGWINSZ` first: iTerm2 3.7.6 on a Retina
    display answers `CSI 16 t` in points (7 x 17) and draws a Sixel pixel as a
    device pixel (14 x 34), which `TIOCGWINSZ` and `XTSMGRAPHICS` both report."""
    reply = ask(fd, "\x1b[16t", b"t")
    window = ask(fd, "\x1b[14t", b"t")
    winsize = struct.unpack("HHHH", fcntl.ioctl(fd, termios.TIOCGWINSZ, b"\0" * 8))
    rows, columns, xpixel, ypixel = winsize
    size = None
    if xpixel and ypixel:
        size = (xpixel // columns, ypixel // rows)
    else:
        try:
            _, height, width = reply.split("[")[-1].rstrip("t").split(";")
            size = (int(width), int(height))
        except ValueError:
            pass
    return {
        "csi16t": repr(reply), "csi14t": repr(window), "winsize": list(winsize),
        "size": size, "rows": rows, "columns": columns,
    }


def ramp(width, height, cell, seed=0):
    """width x height RGB pixels, a ramp, dark on every cell boundary."""
    cell_w, cell_h = cell
    pixels = []
    for y in range(height):
        for x in range(width):
            if x % cell_w == 0 or y % cell_h == 0:
                pixels.append((10, 10, 10))
            else:
                pixels.append(((x * 255 // max(1, width) + seed) % 256, y * 255 // max(1, height), 200 - seed % 150))
    return pixels


def sixel(pixels, width, height, p2=0, levels=4, holes=None, band_start=0):
    """A DCS: a colour cube of levels^3, per band, per colour, with `!n` runs."""
    quantise = lambda value: min(levels - 1, value * levels // 256)
    colours = {}
    indices = []
    for y in range(height):
        for x in range(width):
            if holes and holes(x, y):
                indices.append(-1)
                continue
            r, g, b = pixels[y * width + x]
            key = (quantise(r), quantise(g), quantise(b))
            indices.append(colours.setdefault(key, len(colours)))
    out = [f"\x1bP0;{p2};0q\"1;1;{width};{height}"]
    for key, register in colours.items():
        scaled = [component * 100 // (levels - 1) for component in key]
        out.append(f"#{register};2;{scaled[0]};{scaled[1]};{scaled[2]}")
    for top in range(band_start, height, 6):
        present = set()
        for y in range(top, min(top + 6, height)):
            present.update(i for i in indices[y * width:(y + 1) * width] if i >= 0)
        first = True
        for register in sorted(present):
            if not first:
                out.append("$")
            first = False
            out.append(f"#{register}")
            bits = []
            for x in range(width):
                value = 0
                for offset in range(6):
                    y = top + offset
                    if y < height and indices[y * width + x] == register:
                        value |= 1 << offset
                bits.append(value)
            run, count = bits[0], 0
            for value in bits + [None]:
                if value == run:
                    count += 1
                    continue
                glyph = chr(63 + run)
                out.append(f"!{count}{glyph}" if count > 3 else glyph * count)
                run, count = value, 1
        out.append("-")
    out.append("\x1b\\")
    return "".join(out)


def at(row, column):
    return f"\x1b[{row};{column}H"


def field(fd, title):
    os.write(fd, f"{RESET}{BLUE}\x1b[2J\x1b[H{title}\x1b[K".encode())


def wait_step(number):
    base = os.environ.get("PROBE_STEP")
    if not base:
        time.sleep(float(os.environ.get("PROBE_HOLD", "20")))
        return
    with open(f"{base}.ready", "w") as ready:
        ready.write(str(number))
    deadline = time.time() + 600
    while time.time() < deadline and not os.path.exists(f"{base}.{number}"):
        time.sleep(0.2)


class Panels:
    """Panels of `columns` x `rows` cells across the window."""

    def __init__(self, fd, cell, window, columns=18, rows=5):
        self.fd, self.cell, self.columns, self.rows = fd, cell, columns, rows
        self.width, self.height = columns * cell[0], rows * cell[1]
        self.pixels = ramp(self.width, self.height, cell)
        self.picture = sixel(self.pixels, self.width, self.height)
        self.per_row = max(1, (window["columns"] - 1) // (columns + 3))
        self.placed = 0

    def next(self, name):
        column = 1 + (self.placed % self.per_row) * (self.columns + 3)
        row = 2 + (self.placed // self.per_row) * (self.rows + 3)
        self.placed += 1
        os.write(self.fd, f"{at(row, column)}{name}{at(row + self.rows + 1, column)}{' ' * self.columns}".encode())
        for offset in range(self.rows):
            os.write(self.fd, f"{at(row + 1 + offset, column + self.columns)}|".encode())
        return row + 1, column

    def draw(self, row, column):
        os.write(self.fd, (at(row, column) + self.picture).encode())

    def row_of(self, index):
        top = index * self.cell[1] * self.width
        return self.pixels[top:top + self.cell[1] * self.width]


def card_one(fd, cell, window, record):
    field(fd, "Card 1")
    panels = Panels(fd, cell, window)
    half = panels.columns // 2

    row, column = panels.next("A whole")
    panels.draw(row, column)
    record["bytes"] = {"whole_picture": len(panels.picture)}

    row, column = panels.next("B spaces, left half")
    panels.draw(row, column)
    for offset in range(panels.rows):
        style = RESET if offset < panels.rows // 2 else BLUE
        os.write(fd, f"{at(row + offset, column)}{style}{' ' * half}{BLUE}".encode())

    row, column = panels.next("C ECH, left half")
    panels.draw(row, column)
    for offset in range(panels.rows):
        os.write(fd, f"{at(row + offset, column)}\x1b[{half}X".encode())

    row, column = panels.next("D EL from middle")
    panels.draw(row, column)
    for offset in range(panels.rows // 2):
        os.write(fd, f"{at(row + offset, column + half)}\x1b[K".encode())

    row, column = panels.next("E text over it")
    panels.draw(row, column)
    os.write(fd, f"{at(row + 2, column + 4)}\x1b[48;5;196mhello{BLUE}".encode())

    row, column = panels.next("F P2=1 with holes")
    for offset in range(panels.rows):
        os.write(fd, f"{at(row + offset, column)}{'xy' * half}".encode())
    holes = lambda x, y: (x // cell[0] + y // cell[1]) % 2 == 0
    os.write(fd, (at(row, column) + sixel(panels.pixels, panels.width, panels.height, p2=1, holes=holes)).encode())

    row, column = panels.next("G one row over it")
    panels.draw(row, column)
    other = ramp(panels.width, cell[1], cell, seed=120)
    os.write(fd, (at(row + 2, column) + sixel(other, panels.width, cell[1])).encode())

    row, column = panels.next("H row repaired")
    panels.draw(row, column)
    os.write(fd, f"{at(row + 2, column)}{' ' * panels.columns}".encode())
    repair = sixel(panels.row_of(2), panels.width, cell[1])
    record["bytes"]["one_row_repair"] = len(repair)
    os.write(fd, (at(row + 2, column) + repair).encode())

    row, column = panels.next("I text below intact?")
    os.write(fd, f"{at(row + 2, column)}{'below-below-below-'}".encode())
    height = cell[1] * 2
    pixels = ramp(panels.width, height, cell)
    os.write(fd, (at(row, column) + sixel(pixels, panels.width, height, p2=1)).encode())


def card_two(fd, cell, window, record):
    field(fd, "Card 2")
    panels = Panels(fd, cell, window)

    row, column = panels.next("J registers")
    width, height = panels.width // 2, panels.height
    first = f"\x1bP0;0;0q\"1;1;{width};{height}#1;2;100;0;0" + "".join(f"#1!{width}~-" for _ in range(height // 6)) + "\x1b\\"
    second = f"\x1bP0;0;0q\"1;1;{width};{height}#1;2;0;100;0" + "".join(f"#1!{width}~-" for _ in range(height // 6)) + "\x1b\\"
    os.write(fd, (at(row, column) + first + at(row, column + panels.columns // 2) + second).encode())

    row, column = panels.next("K tiled by rows")
    for offset in range(panels.rows):
        os.write(fd, (at(row + offset, column) + sixel(panels.row_of(offset), panels.width, cell[1])).encode())

    row, column = panels.next("L scrolled up 1")
    panels.draw(row, column)
    os.write(fd, f"\x1b[{row};{row + panels.rows - 1}r\x1b[1S\x1b[r".encode())

    row, column = panels.next("M erased by ED")
    panels.draw(row, column)
    # ED from the cursor to the end erases what follows, so this panel goes last
    # among those still looked at; everything below it is drawn afterwards.
    os.write(fd, f"{at(row, column)}\x1b[J".encode())

    row, column = panels.next("N half a MB in ?2026")
    rng = random.Random(4)
    big_w, big_h = 420, 400
    noise = [(rng.randrange(256), rng.randrange(256), rng.randrange(256)) for _ in range(big_w * big_h)]
    big = sixel(noise, big_w, big_h, levels=6)
    record["bytes"]["noise_picture"] = len(big)
    start = time.time()
    os.write(fd, ("\x1b[?2026h" + at(row, column) + big + "\x1b[?2026l").encode())
    record["held"] = {"position": cursor(fd), "seconds": round(time.time() - start, 3)}


def last_row_card(fd, cell, window, record, name, mode_on, mode_off):
    rows = window["rows"]
    field(fd, f"Top row: {name}: did this line move? ({rows} rows)")
    os.write(fd, f"{at(rows - 3, 40)}row -3{at(rows - 2, 40)}row -2{at(rows - 1, 40)}row -1{at(rows, 40)}last row".encode())
    width, height = 30 * cell[0], 3 * cell[1]
    picture = sixel(ramp(width, height, cell), width, height)
    os.write(fd, (mode_on + at(rows - 2, 2) + picture).encode())
    record["last_row"][name] = {"cursor": cursor(fd), "rows": rows}
    os.write(fd, mode_off.encode())


def main():
    fd = sys.stdin.fileno()
    if not os.isatty(fd):
        sys.exit("sixel_probe: run this IN the terminal under test")
    old = termios.tcgetattr(fd)
    record = {}
    try:
        tty.setraw(fd)
        record["stamp"] = probe_stamp.stamp(fd, "sixel_probe", use_alt=False)
        da1 = ask(fd, "\x1b[c", b"c")
        record["da1"] = {"reply": repr(da1), "says_4": "4" in da1.split("?")[-1].rstrip("c").split(";")}
        record["xtsmgraphics"] = {
            "registers": repr(ask(fd, "\x1b[?1;1;0S", b"S", 0.7)),
            "geometry": repr(ask(fd, "\x1b[?2;1;0S", b"S", 0.7)),
        }
        out_path = os.environ.get("PROBE_OUT", "sixel_probe.json")
        window = cell_size(fd)
        record["cell"] = window
        if os.environ.get("PROBE_DA1_ONLY") or not record["da1"]["says_4"]:
            with open(out_path, "w") as out:
                json.dump(record, out, indent=2, ensure_ascii=False)
            return
        cell = tuple(window["size"]) if window["size"] else (10, 20)
        os.write(fd, b"\x1b[?1049h\x1b[?25l")

        width, height = 8 * cell[0], 2 * cell[1]
        small = sixel(ramp(width, height, cell), width, height)
        record["cursor_after"] = {}
        for name, on, off in (
            ("no_mode", "", ""), ("decsdm", "\x1b[?80h", "\x1b[?80l"), ("right", "\x1b[?8452h", "\x1b[?8452l"),
        ):
            os.write(fd, (f"{RESET}\x1b[2J" + on + at(5, 5)).encode())
            start = cursor(fd)
            os.write(fd, small.encode())
            record["cursor_after"][name] = {"start": start, "after": cursor(fd)}
            os.write(fd, off.encode())

        def save():
            with open(out_path, "w") as out:
                json.dump(record, out, indent=2, ensure_ascii=False)

        card_one(fd, cell, window, record)
        save()
        wait_step(1)
        card_two(fd, cell, window, record)
        save()
        wait_step(2)
        record["last_row"] = {}
        for number, (name, on, off) in enumerate(
            (("no_mode", "", ""), ("decsdm", "\x1b[?80h", "\x1b[?80l"), ("right", "\x1b[?8452h", "\x1b[?8452l")),
            start=3,
        ):
            last_row_card(fd, cell, window, record, name, on, off)
            save()
            wait_step(number)
    finally:
        os.write(fd, b"\x1b[0m\x1b[2J\x1b[?25h\x1b[?1049l")
        termios.tcsetattr(fd, termios.TCSADRAIN, old)


if __name__ == "__main__":
    main()
