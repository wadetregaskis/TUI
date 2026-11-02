#!/usr/bin/env python3
"""What a terminal does when told to move a band of rows, read off its pixels.

The question behind `FrameDiffWriter`'s hardware scrolling
(`Documentation/Performance/Scroll regions for output.md`): for each way of
moving a band — DECSTBM with SU/SD, IL/DL, IND at the bottom margin, DECSLRM
margins, DECCRA — does this host move exactly the cells it was told to, what
does it put in the rows it exposes, where does it leave the cursor, and what
happens to a Kitty placement or a compensated emoji row in the band?

Two halves, so that the terminal under test runs nothing but this:

  # In the terminal under test, launched by the driver below:
  python3 scroll_region_probe.py card --handshake DIR

  # Outside it, from an ordinary shell that may capture the screen:
  python3 scroll_region_probe.py drive --terminal ghostty --out data/x.json

`card` paints a known grid of colours on the alternate screen, applies one
operation, says so in DIR/state.json and waits for DIR/ack before the next.
`drive` launches the card through a `.command` file (never `-e` on Ghostty:
it prompts), captures the whole screen at each state with `screencapture`,
finds the grid by its key rows (magenta on top, cyan underneath) and classifies
every cell centre against each hypothesis the test states: paint is the truth,
and DSR and DECRQM are recorded beside it, never instead of it.

Colours come from the 256-colour cube, whose spellings no measured host remaps.
Row colours repeat every six rows and the fixed panes every three, so a shift
of two rows is unmistakable in either.

`cpu` feeds the same terminal two streams that show the same notches: one
writing every row of the band, one moving the band and writing what it exposes.
`drive --cpu` reads the terminal's own CPU time (`ps -o cputime=`) around each.
The numbers are indicative on a shared machine; the fence round-trip beside them
says how long the terminal's parser took to get through a notch.
"""
import argparse
import json
import os
import random
import re
import select
import shutil
import subprocess
import sys
import termios
import time
import tty

try:
    import probe_stamp
except ImportError:
    probe_stamp = None

# name -> (256-colour index, nominal RGB)
PALETTE = {
    "red": (196, (255, 0, 0)),
    "green": (46, (0, 255, 0)),
    "blue": (21, (0, 0, 255)),
    "yellow": (226, (255, 255, 0)),
    "orange": (208, (255, 135, 0)),
    "purple": (93, (135, 0, 255)),
    "white": (231, (255, 255, 255)),
    "grey": (244, (128, 128, 128)),
    "teal": (30, (0, 135, 135)),
    "magenta": (201, (255, 0, 255)),
    "cyan": (51, (0, 255, 255)),
    "black": (16, (0, 0, 0)),
    "pink": (218, (255, 175, 215)),
}
BAND = ["red", "green", "blue", "yellow", "orange", "purple"]
PANE = ["white", "grey", "teal"]
TOP, BOTTOM = 5, 14     # the region, 1-based inclusive
EXPOSED = "pink"        # the background in force when the band moves: BCE's colour


def bg(name):
    return f"\x1b[48;5;{PALETTE[name][0]}m"


def baseline_grid(cols, rows):
    """The grid before any operation, as colour names, row by row."""
    grid = []
    for row in range(rows):
        if row == 0:
            grid.append(["magenta"] * cols)
        elif row == rows - 1:
            grid.append(["cyan"] * cols)
        else:
            cells = []
            for col in range(cols):
                if col < 10:
                    cells.append(PANE[row % 3])
                elif col >= cols - 10:
                    cells.append(PANE[(row + 1) % 3])
                else:
                    cells.append(BAND[row % 6])
            grid.append(cells)
    return grid


def paint(out, grid):
    """Every row with its absolute move, as a frame's whole-line path does."""
    parts = ["\x1b[?25l", "\x1b[0m", "\x1b[r", "\x1b[?69l"]
    for row, cells in enumerate(grid):
        parts.append(f"\x1b[{row + 1};1H")
        run = None
        for name in cells:
            if name != run:
                parts.append(bg(name))
                run = name
            parts.append(" ")
    parts.append("\x1b[0m")
    out.write("".join(parts).encode())
    out.flush()


# The hypotheses: pure functions of the grid. `band` is 0-based and inclusive.
def shifted(grid, top, bottom, left, right, by, exposed):
    """`by` > 0 moves cells in rows `top...bottom`, columns `left...right`, UP."""
    moved = [list(r) for r in grid]
    height = bottom - top + 1
    for offset in range(height):
        row = top + offset
        source = row + by
        for col in range(left, right + 1):
            if top <= source <= bottom:
                moved[row][col] = grid[source][col]
            else:
                moved[row][col] = exposed
    return moved


def swapped_copy(base, top, bottom, left, right, rows, cols):
    """DECCRA with its destination read as (column, row): what iTerm2 3.7.6 looked like."""
    grid = [list(r) for r in base]
    dest_row, dest_col = left, top
    for row in range(top + 2, bottom + 1):
        for col in range(left, right + 1):
            y, x = dest_row + row - (top + 2), dest_col + col - left
            if 0 <= y < rows and 0 <= x < cols:
                grid[y][x] = base[row][col]
    return grid


def tests(cols, rows):
    """(name, bytes that do it, {hypothesis: grid}) for each operation."""
    base = baseline_grid(cols, rows)
    top, bottom = TOP - 1, BOTTOM - 1
    full = cols - 1
    left, right = 10, cols - 11
    park = f"\x1b[{rows - 1};1H"

    def hyps(by, l=0, r=full):
        return {
            "as told, exposed in the background in force (BCE)": shifted(base, top, bottom, l, r, by, EXPOSED),
            "as told, exposed in the default background": shifted(base, top, bottom, l, r, by, "default"),
            "the whole width moved instead, BCE": shifted(base, top, bottom, 0, full, by, EXPOSED),
            "the whole width moved instead, default": shifted(base, top, bottom, 0, full, by, "default"),
            "nothing moved": base,
        }

    pen = bg(EXPOSED)
    reset = "\x1b[0m"
    region = f"\x1b[{TOP};{BOTTOM}r"
    margins_on = f"\x1b[?69h\x1b[{left + 1};{right + 1}s"
    margins_off = "\x1b[?69l"
    yield ("SU 2 in DECSTBM", pen + region + "\x1b[2S" + "\x1b[r" + reset, hyps(2))
    yield ("SD 2 in DECSTBM", pen + region + "\x1b[2T" + "\x1b[r" + reset, hyps(-2))
    yield ("SU 2, DECSTBM still set after",
           pen + region + "\x1b[2S" + reset + f"\x1b[{rows};1H" + bg("cyan") + " " + reset + "\x1b[r",
           hyps(2))
    yield ("DL 2 at the region's top",
           pen + region + f"\x1b[{TOP};1H\x1b[2M" + "\x1b[r" + reset, hyps(2))
    yield ("IL 2 at the region's top",
           pen + region + f"\x1b[{TOP};1H\x1b[2L" + "\x1b[r" + reset, hyps(-2))
    yield ("IND twice at the bottom margin",
           pen + region + f"\x1b[{BOTTOM};1H\x1bD\x1bD" + "\x1b[r" + reset, hyps(2))
    yield ("RI twice at the top margin",
           pen + region + f"\x1b[{TOP};1H\x1bM\x1bM" + "\x1b[r" + reset, hyps(-2))
    yield ("SU 2 in DECSTBM + DECSLRM",
           pen + margins_on + region + "\x1b[2S" + "\x1b[r" + margins_off + reset, hyps(2, left, right))
    yield ("SD 2 in DECSTBM + DECSLRM",
           pen + margins_on + region + "\x1b[2T" + "\x1b[r" + margins_off + reset, hyps(-2, left, right))
    yield ("DL 2 in DECSTBM + DECSLRM",
           pen + margins_on + region + f"\x1b[{TOP};{left + 1}H\x1b[2M" + "\x1b[r" + margins_off + reset,
           hyps(2, left, right))
    # DECCRA leaves its source where the copy does not reach: the rows exposed
    # keep what they showed, which the writer would then repaint.
    copied = [list(r) for r in base]
    for row in range(top, bottom - 1):
        for col in range(left, right + 1):
            copied[row][col] = base[row + 2][col]
    yield ("DECCRA up 2",
           f"\x1b[{TOP + 2};{left + 1};{BOTTOM};{right + 1};1;{TOP};{left + 1};1$v",
           {"as told, source kept": copied, "nothing moved": base,
            "destination row and column swapped": swapped_copy(base, top, bottom, left, right, rows, cols)})
    yield ("SU 2 inside a held update (2026)",
           "\x1b[?2026h" + pen + region + "\x1b[2S" + "\x1b[r" + reset + "\x1b[?2026l", hyps(2))
    yield ("Absolute move with a region set",
           region + f"\x1b[{rows - 2};3H" + bg("black") + "  " + reset + "\x1b[r",
           {"as told": [[("black" if (y == rows - 3 and x in (2, 3)) else c) for x, c in enumerate(r)]
                        for y, r in enumerate(base)],
            "nothing moved": base})
    _ = park


class Card:
    def __init__(self, handshake):
        self.handshake = handshake
        self.index = 0
        self.fd = sys.stdin.fileno()
        self.out = os.fdopen(os.dup(sys.stdout.fileno()), "wb", buffering=0)
        self.results = []

    def say(self, payload):
        """Tell the driver the screen is ready, and wait for it to look."""
        self.out.flush()
        time.sleep(0.25)  # past a paint, and past any hold
        path = os.path.join(self.handshake, "state.json")
        with open(path + ".tmp", "w") as handle:
            json.dump(dict(payload, index=self.index), handle)
        os.rename(path + ".tmp", path)
        ack = os.path.join(self.handshake, f"ack-{self.index}")
        deadline = time.monotonic() + 30
        while not os.path.exists(ack) and time.monotonic() < deadline:
            time.sleep(0.05)
        self.index += 1

    def ask(self, query, pattern, timeout=0.5):
        self.out.write(query.encode())
        buf = b""
        deadline = time.monotonic() + timeout
        while not re.search(pattern, buf):
            left = deadline - time.monotonic()
            if left <= 0 or not select.select([self.fd], [], [], left)[0]:
                return None
            buf += os.read(self.fd, 4096)
        return buf

    def cursor(self):
        reply = self.ask("\x1b[6n", rb"\x1b\[(\d+);(\d+)R")
        if not reply:
            return None
        match = re.search(rb"\x1b\[(\d+);(\d+)R", reply)
        return int(match.group(1)), int(match.group(2))

    def mode(self, number):
        """DECRQM, never on Apple Terminal: its final byte prints there."""
        if os.environ.get("TERM_PROGRAM") == "Apple_Terminal":
            return "not asked"
        reply = self.ask(f"\x1b[?{number}$p\x1b[5n", rb"\x1b\[0n")
        if not reply:
            return None
        match = re.search(rb"\?%d;(\d)\$y" % number, reply)
        return int(match.group(1)) if match else "no reply"

    def run(self):
        cols, rows = os.get_terminal_size()
        modes = {"2026": self.mode(2026), "69": self.mode(69)}
        for name, sequence, hypotheses in tests(cols, rows):
            paint(self.out, baseline_grid(cols, rows))
            self.out.write(f"\x1b[{rows - 1};1H".encode())
            self.out.write(sequence.encode())
            after = self.cursor()
            self.say({"test": name, "cols": cols, "rows": rows, "cursor": after, "hypotheses": hypotheses})
        self.placements(cols, rows)
        self.placeholders(cols, rows)
        self.compensated(cols, rows)
        self.say({"test": "done", "cols": cols, "rows": rows, "modes": modes, "done": True,
                  "term_program": os.environ.get("TERM_PROGRAM"),
                  "version": os.environ.get("TERM_PROGRAM_VERSION")})

    def placements(self, cols, rows):
        """A Kitty classic placement of solid black pixels on rows 8-9, 11-20 wide."""
        base = baseline_grid(cols, rows)
        if os.environ.get("TERM_PROGRAM") == "Apple_Terminal":
            return
        for name, sequence in (("placement in a band, SU 2", "\x1b[2S"),
                               ("placement in a band, SD 2", "\x1b[2T")):
            paint(self.out, base)
            # f=24, 1x1 px, placed over c x r cells: the classic form HairlineLayer uses.
            image = "\x1b_Ga=T,f=24,s=1,v=1,i=4242,p=1,c=10,r=2,q=2;AAAA\x1b\\"
            self.out.write((f"\x1b[8;21H{image}").encode())
            self.out.write((bg(EXPOSED) + f"\x1b[{TOP};{BOTTOM}r" + sequence + "\x1b[r\x1b[0m").encode())
            by = 2 if "SU" in name else -2
            moved = shifted(base, TOP - 1, BOTTOM - 1, 0, cols - 1, by, EXPOSED)
            def painted(start):
                grid = [list(r) for r in moved]
                for row in (start, start + 1):
                    for col in range(20, 30):
                        grid[row][col] = "black"
                return grid
            self.say({"test": name, "cols": cols, "rows": rows, "cursor": None, "hypotheses": {
                "the picture moved with the band": painted(7 - by),
                "the picture stayed where it was placed": painted(7),
                "the picture went": moved,
            }})
            self.out.write(b"\x1b_Ga=d,d=I,i=4242,q=2\x1b\\")

    def placeholders(self, cols, rows):
        """A Kitty Unicode placeholder: the picture is text, so it should ride."""
        base = baseline_grid(cols, rows)
        if os.environ.get("TERM_PROGRAM") == "Apple_Terminal":
            return
        marks = ["\u0305", "\u030D", "\u030E", "\u0310", "\u0312", "\u033D", "\u033E", "\u033F", "\u0346", "\u034A"]
        image = 4243
        spell = f"\x1b[38;2;{(image >> 16) & 255};{(image >> 8) & 255};{image & 255}m"
        self.out.write(f"\x1b_Ga=T,U=1,f=24,s=1,v=1,i={image},c=10,r=2,q=2;AAAA\x1b\\".encode())
        paint(self.out, base)
        for row in (0, 1):
            cells = "".join("\U0010EEEE" + marks[row] + marks[col] for col in range(10))
            self.out.write((f"\x1b[{8 + row};21H" + spell + cells + "\x1b[0m").encode())
        self.out.write((bg(EXPOSED) + f"\x1b[{TOP};{BOTTOM}r" + "\x1b[2S" + "\x1b[r\x1b[0m").encode())
        moved = shifted(base, TOP - 1, BOTTOM - 1, 0, cols - 1, 2, EXPOSED)

        def painted(start):
            grid = [list(r) for r in moved]
            for row in (start, start + 1):
                for col in range(20, 30):
                    grid[row][col] = "black"
            return grid
        self.say({"test": "placeholder in a band, SU 2", "cols": cols, "rows": rows, "cursor": None, "hypotheses": {
            "the picture moved with the band": painted(5),
            "the picture stayed where it was placed": painted(7),
            "the picture went": moved,
        }})
        self.out.write(f"\x1b_Ga=d,d=I,i={image},q=2\x1b\\".encode())

    def compensated(self, cols, rows):
        """Does the row STORE travel with a scroll? Apple Terminal keeps three
        facts per row; a marker written after the scroll lands by the store."""
        apple = os.environ.get("TERM_PROGRAM") == "Apple_Terminal"
        # The treatments FrameDiffWriter's walk gives these on Apple Terminal:
        # VS-16 under-advancers erase and step; flags have store surgery.
        vs16 = "\x1b[2X⚙️\x1b[1C" if apple else "⚙️"
        flag = "\U0001F1FA\U0001F1F8\x1b[1D\x1b[1P\x1b[1C" if apple else "\U0001F1FA\U0001F1F8"
        base = baseline_grid(cols, rows)
        for name, by, sequence in (("marker after a scroll over emoji rows, SU 2", 2, "\x1b[2S"),
                                   ("marker with no scroll, emoji rows", 0, "")):
            paint(self.out, base)
            for row, glyph in ((8, vs16), (10, flag)):
                self.out.write((f"\x1b[{row};12H" + bg("black") + "ab" + glyph + "cd\x1b[0m").encode())
            self.out.write((bg(EXPOSED) + f"\x1b[{TOP};{BOTTOM}r" + sequence + "\x1b[r\x1b[0m").encode())
            for row in (8, 9, 10):
                self.out.write((f"\x1b[{row - by};40H" + bg("magenta") + " " + "\x1b[0m").encode())
            moved = shifted(base, TOP - 1, BOTTOM - 1, 0, cols - 1, by, EXPOSED) if by else base
            self.say({"test": name, "cols": cols, "rows": rows, "cursor": None, "markers": [row - by - 1 for row in (8, 9, 10)],
                      "hypotheses": {}, "moved": moved})


def card(args):
    fd = sys.stdin.fileno()
    saved = termios.tcgetattr(fd)
    tty.setraw(fd)
    sys.stdout.buffer.write(b"\x1b[?1049h\x1b[?25l")
    sys.stdout.buffer.flush()
    try:
        Card(args.handshake).run()
    finally:
        sys.stdout.buffer.write(b"\x1b[r\x1b[?69l\x1b[0m\x1b[?25h\x1b[?1049l")
        sys.stdout.buffer.flush()
        termios.tcsetattr(fd, termios.TCSADRAIN, saved)


# --- The CPU half -----------------------------------------------------------

def letters(rng, width):
    return "".join(rng.choice("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ") for _ in range(width))


def cpu_card(args):
    """Waits for a command in DIR/cmd.json, plays it, says done. Same notches both ways."""
    fd = sys.stdin.fileno()
    saved = termios.tcgetattr(fd)
    tty.setraw(fd)
    out = os.fdopen(os.dup(sys.stdout.fileno()), "wb", buffering=0)
    out.write(b"\x1b[?1049h\x1b[?25l")
    cols, rows = os.get_terminal_size()
    rng = random.Random(20261101)
    # A long document of dissimilar rows, as the Q14 (b) measurement used.
    document = [letters(rng, cols) for _ in range(400)]
    sgr = "\x1b[38;5;252;48;5;235m"
    status = os.path.join(args.handshake, "status.json")

    def fence():
        out.write(b"\x1b[5n")
        buf = b""
        deadline = time.monotonic() + 5
        while b"\x1b[0n" not in buf and time.monotonic() < deadline:
            if select.select([fd], [], [], 0.1)[0]:
                buf += os.read(fd, 4096)

    def whole(top_row, moved=None):
        parts = ["\x1b[?2026h", sgr]
        for row in range(rows):
            parts.append(f"\x1b[{row + 1};1H\x1b[2K")
            parts.append(document[(top_row + row) % len(document)])
        parts.append("\x1b[0m\x1b[?2026l")
        return "".join(parts).encode()

    def region(top_row, by):
        parts = ["\x1b[?2026h", sgr, f"\x1b[1;{rows}r\x1b[{by}S\x1b[r"]
        for row in range(rows - by, rows):
            parts.append(f"\x1b[{row + 1};1H\x1b[2K")
            parts.append(document[(top_row + row) % len(document)])
        parts.append("\x1b[0m\x1b[?2026l")
        return "".join(parts).encode()

    last = None
    out.write(whole(0))
    with open(status + ".tmp", "w") as handle:
        json.dump({"ready": True, "cols": cols, "rows": rows}, handle)
    os.rename(status + ".tmp", status)
    done = 0
    while True:
        command_path = os.path.join(args.handshake, f"cmd-{done}.json")
        deadline = time.monotonic() + 600
        while not os.path.exists(command_path) and time.monotonic() < deadline:
            time.sleep(0.02)
        if not os.path.exists(command_path):
            break
        with open(command_path) as handle:
            command = json.load(handle)
        if command["kind"] == "quit":
            break
        count, by, rate = command["notches"], command["by"], command["rate"]
        fenced = command.get("fenced", False)
        top_row = 0
        out.write(whole(0))
        fence()
        spent = []
        written = 0
        start = time.monotonic()
        for notch in range(count):
            top_row += by
            if command["kind"] == "whole":
                frame = whole(top_row)
            elif command["kind"] == "region":
                frame = region(top_row, by)
            else:
                frame = b""  # idle
            began = time.monotonic()
            out.write(frame)
            written += len(frame)
            if fenced:
                fence()
                spent.append(time.monotonic() - began)
            if rate:
                gap = start + (notch + 1) / rate - time.monotonic()
                if gap > 0:
                    time.sleep(gap)
        fence()
        elapsed = time.monotonic() - start
        spent.sort()
        with open(os.path.join(args.handshake, f"done-{done}.json.tmp"), "w") as handle:
            json.dump({"elapsed": elapsed, "bytes": written,
                       "p50_ms": spent[len(spent) // 2] * 1000 if spent else None}, handle)
        os.rename(os.path.join(args.handshake, f"done-{done}.json.tmp"),
                  os.path.join(args.handshake, f"done-{done}.json"))
        done += 1
    out.write(b"\x1b[r\x1b[0m\x1b[?25h\x1b[?1049l")
    termios.tcsetattr(fd, termios.TCSADRAIN, saved)


# --- The driver: launches, captures, reads ----------------------------------

APPS = {
    "apple": ("Terminal", "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal"),
    "iterm2": ("iTerm", "/Applications/iTerm.app/Contents/MacOS/iTerm2"),
    "ghostty": ("Ghostty", "/Applications/Ghostty.app/Contents/MacOS/ghostty"),
    "warp": ("Warp", "/Applications/Warp.app/Contents/MacOS/stable"),
    "kitty": ("kitty", "/opt/homebrew/bin/kitty"),
}


def launch(terminal, script_dir, inner):
    command = os.path.join(script_dir, f"scroll-{terminal}.command")
    with open(command, "w") as handle:
        handle.write("#!/bin/zsh\n" + inner + "\nexit 0\n")
    os.chmod(command, 0o755)
    if terminal == "ghostty":
        subprocess.run(["open", "-na", "/Applications/Ghostty.app", "--args",
                        f"--initial-command=direct:{command}",
                        "--quit-after-last-window-closed=true", "--window-save-state=never",
                        "--config-default-files=false"], check=True)
    elif terminal == "kitty":
        subprocess.run(["open", "-na", "/Applications/kitty.app", "--args", command], check=True)
    else:
        subprocess.run(["open", "-a", APPS[terminal][0], command], check=True)


def capture(path):
    subprocess.run(["screencapture", "-x", "-t", "png", path], check=True)


def nearest(pixel):
    best, distance = None, 1 << 30
    for name, (_, rgb) in PALETTE.items():
        d = sum((a - b) ** 2 for a, b in zip(pixel[:3], rgb))
        if d < distance:
            best, distance = name, d
    return best if distance < 18000 else "default"


def locate(image, cols, rows):
    """The grid's cell box, by its key rows: magenta on top, cyan underneath.
    The widest horizontal run of each, so a stray pixel cannot pass for one."""
    width, height = image.size
    pixels = image.load()

    def is_key(p, name):
        return sum((a - b) ** 2 for a, b in zip(p[:3], PALETTE[name][1])) < 9000

    def widest(name):
        # Coarse first: a key row is a whole row of the card, so sampling every
        # 8th pixel of every 8th line cannot miss one, and a Retina screen is
        # five million pixels Python would otherwise visit one by one.
        best = None
        for y in range(0, height, 8):
            run_start, x, longest = None, 0, (0, 0)
            while x < width:
                if is_key(pixels[x, y], name):
                    if run_start is None:
                        run_start = x
                else:
                    if run_start is not None and x - run_start > longest[0]:
                        longest = (x - run_start, run_start)
                    run_start = None
                x += 8
            if run_start is not None and width - run_start > longest[0]:
                longest = (width - run_start, run_start)
            if longest[0] > 200 and (best is None or longest[0] > best[0] + 8):
                best = (longest[0], longest[1], y)
        if best is None:
            return None
        # Then exact, along the one line found.
        _, start, y = best
        left = start
        while left > 0 and is_key(pixels[left - 1, y], name):
            left -= 1
        right = start
        while right + 1 < width and is_key(pixels[right + 1, y], name):
            right += 1
        return right + 1 - left, left, y

    top = widest("magenta")
    bottom = widest("cyan")
    if not top or not bottom:
        return None
    run, left, y_top = top
    # Another window over part of the top key row leaves the bottom one whole.
    if bottom[0] > run:
        run, left = bottom[0], bottom[1]
    # The top edge of the magenta row, and the bottom edge of the cyan one.
    y = y_top
    while y > 0 and is_key(pixels[left + run // 2, y - 1], "magenta"):
        y -= 1
    top_edge = y
    y = bottom[2]
    while y + 1 < height and is_key(pixels[left + run // 2, y + 1], "cyan"):
        y += 1
    bottom_edge = y + 1
    cell_h = (bottom_edge - top_edge) / rows
    # The key rows' colour runs on into the window's padding on a host that
    # paints it (iTerm2), so the width is measured between the two panes' edges
    # on row 2, ten cells in from each side, which no operation here touches.
    y = int(top_edge + 1.5 * cell_h)
    edges = [x for x in range(left + 1, left + run) if pixels[x, y][:3] != pixels[x - 1, y][:3]
             and sum((a - b) ** 2 for a, b in zip(pixels[x, y][:3], pixels[x - 1, y][:3])) > 9000]
    if len(edges) >= 2:
        cell_w = (edges[-1] - edges[0]) / (cols - 20)
        # Something covering part of the row is no reason to believe a tiny cell.
        if abs(cell_w - run / cols) < 0.1 * run / cols:
            return edges[0] - 10 * cell_w, top_edge, cell_w, cell_h
    return left, top_edge, run / cols, cell_h


def read_grid(path, cols, rows):
    from PIL import Image
    image = Image.open(path).convert("RGB")
    box = locate(image, cols, rows)
    if not box:
        return None, None
    left, top, cell_w, cell_h = box
    pixels = image.load()
    grid = []
    for row in range(rows):
        cells = []
        for col in range(cols):
            x = int(left + (col + 0.5) * cell_w)
            y = int(top + (row + 0.5) * cell_h)
            cells.append(nearest(pixels[x, y]))
        grid.append(cells)
    return grid, box


def verdict(grid, hypotheses):
    scores = {}
    total = sum(len(r) for r in grid)
    for name, expected in hypotheses.items():
        # "default" is whatever this profile's background is: dark, light or
        # neither, so it matches anything that is not one of the card's own.
        wrong = sum(1 for got, want in zip(grid, expected)
                    for a, b in zip(got, want)
                    if a != b and not (b == "default" and a in ("default", "black", "white", "grey")))
        scores[name] = wrong
    best = min(scores, key=scores.get) if scores else None
    return best, scores, total


def drive(args):
    script_dir = args.scratch
    os.makedirs(script_dir, exist_ok=True)
    hand = os.path.join(script_dir, f"hand-{args.terminal}")
    shutil.rmtree(hand, ignore_errors=True)
    os.makedirs(hand)
    probe = os.path.join(script_dir, "scroll_region_probe.py")
    shutil.copy(os.path.abspath(__file__), probe)
    here = os.path.dirname(os.path.abspath(__file__))
    if os.path.exists(os.path.join(here, "probe_stamp.py")):
        shutil.copy(os.path.join(here, "probe_stamp.py"), script_dir)
    launch(args.terminal, script_dir,
           f"exec /usr/bin/python3 {probe} card --handshake {hand} 2> {hand}/stderr.txt")
    results = []
    final = None
    index = 0
    deadline = time.monotonic() + args.timeout
    state_path = os.path.join(hand, "state.json")
    while time.monotonic() < deadline:
        if not os.path.exists(state_path):
            time.sleep(0.1)
            continue
        with open(state_path) as handle:
            state = json.load(handle)
        if state["index"] != index:
            time.sleep(0.05)
            continue
        if state.get("done"):
            final = state
            open(os.path.join(hand, f"ack-{index}"), "w").close()
            break
        shot = os.path.join(hand, f"shot-{index}.png")
        capture(shot)
        grid, box = read_grid(shot, state["cols"], state["rows"])
        entry = {"test": state["test"], "cursor_after": state.get("cursor")}
        if grid is None:
            entry["verdict"] = "grid not found on screen"
        elif state.get("markers"):
            found = []
            for row in state["markers"]:
                columns = [c for c, name in enumerate(grid[row]) if name == "magenta"]
                found.append({"row": row + 1, "marker_columns": [c + 1 for c in columns]})
            entry["verdict"] = found
        else:
            best, scores, total = verdict(grid, state["hypotheses"])
            entry["verdict"] = best
            entry["wrong_cells"] = scores
            entry["cells"] = total
            print(f"{state['test']:<44} {best}  (wrong {scores[best]}/{total})  cursor {state.get('cursor')}")
        results.append(entry)
        open(os.path.join(hand, f"ack-{index}"), "w").close()
        index += 1
    record = {
        "terminal": args.terminal,
        "program": final and final.get("term_program"),
        "version": final and final.get("version"),
        "modes": final and final.get("modes"),
        "date": time.strftime("%Y-%m-%d"),
        "results": results,
    }
    print(json.dumps({k: record[k] for k in ("terminal", "program", "version", "modes", "date")}))
    if args.out:
        with open(args.out, "w") as handle:
            json.dump(record, handle, indent=1)
            handle.write("\n")


def cputime(pids):
    total = 0.0
    for pid in pids:
        out = subprocess.run(["ps", "-o", "cputime=", "-p", str(pid)], capture_output=True, text=True).stdout.strip()
        if not out:
            continue
        secs = 0.0
        for part in out.split(":"):
            secs = secs * 60 + float(part)
        total += secs
    return total


def terminal_pids(terminal):
    needle = APPS[terminal][1]
    out = subprocess.run(["ps", "-axo", "pid=,comm="], capture_output=True, text=True).stdout
    return [int(line.split(None, 1)[0]) for line in out.splitlines() if needle in line]


def drive_cpu(args):
    script_dir = args.scratch
    os.makedirs(script_dir, exist_ok=True)
    hand = os.path.join(script_dir, f"cpu-{args.terminal}")
    shutil.rmtree(hand, ignore_errors=True)
    os.makedirs(hand)
    probe = os.path.join(script_dir, "scroll_region_probe.py")
    shutil.copy(os.path.abspath(__file__), probe)
    launch(args.terminal, script_dir,
           f"exec /usr/bin/python3 {probe} cpu --handshake {hand} 2> {hand}/stderr.txt")
    status = os.path.join(hand, "status.json")
    deadline = time.monotonic() + 30
    while not os.path.exists(status) and time.monotonic() < deadline:
        time.sleep(0.1)
    if not os.path.exists(status):
        raise SystemExit("the card never came up")
    with open(status) as handle:
        geometry = json.load(handle)
    pids = terminal_pids(args.terminal)
    print(f"{args.terminal} {geometry['cols']}x{geometry['rows']} pids {pids}")
    index = 0
    table = []

    def play(kind, notches, by, rate, fenced=False):
        nonlocal index
        before = cputime(pids)
        path = os.path.join(hand, f"cmd-{index}.json")
        with open(path + ".tmp", "w") as handle:
            json.dump({"kind": kind, "notches": notches, "by": by, "rate": rate, "fenced": fenced}, handle)
        os.rename(path + ".tmp", path)
        done = os.path.join(hand, f"done-{index}.json")
        limit = time.monotonic() + 120
        while not os.path.exists(done) and time.monotonic() < limit:
            time.sleep(0.05)
        with open(done) as handle:
            result = json.load(handle)
        after = cputime(pids)
        index += 1
        return dict(result, cpu=after - before)

    time.sleep(1.0)
    rounds = []
    for name, by, rate, notches in (("wheel 3 rows at 30/s", 3, 30, 300),
                                    ("held key 1 row at 30/s", 1, 30, 300),
                                    ("smooth 1 row at 120/s", 1, 120, 600)):
        for repeat in range(args.reps):
            idle = play("idle", notches, by, rate)
            for kind in ("whole", "region"):
                result = play(kind, notches, by, rate)
                table.append({"workload": name, "kind": kind, "repeat": repeat, "cpu_s": result["cpu"],
                              "idle_cpu_s": idle["cpu"], "bytes": result["bytes"], "elapsed_s": result["elapsed"]})
                print(f"{name:<26} {kind:<7} cpu {result['cpu']:6.2f} s  idle {idle['cpu']:5.2f} s  "
                      f"{result['bytes'] / notches:8.0f} B/notch  {result['elapsed']:5.1f} s")
    for kind in ("whole", "region"):
        result = play(kind, 200, 3, 0, fenced=True)
        table.append({"workload": "fenced, unpaced", "kind": kind, "p50_ms": result["p50_ms"], "elapsed_s": result["elapsed"],
                      "cpu_s": result["cpu"], "bytes": result["bytes"]})
        print(f"fenced, unpaced            {kind:<7} p50 {result['p50_ms']:.2f} ms  {result['elapsed']:.1f} s  cpu {result['cpu']:.2f} s")
    path = os.path.join(hand, f"cmd-{index}.json")
    with open(path, "w") as handle:
        json.dump({"kind": "quit"}, handle)
    if args.out:
        with open(args.out, "w") as handle:
            json.dump({"terminal": args.terminal, "geometry": geometry, "date": time.strftime("%Y-%m-%d"), "table": table},
                      handle, indent=1)
            handle.write("\n")


# --- The differential, on real paint ----------------------------------------

def replay_card(args):
    """Plays streams the driver names, stopping where it says, so that it can
    compare the same frame reached two ways on this terminal's own pixels."""
    fd = sys.stdin.fileno()
    saved = termios.tcgetattr(fd)
    tty.setraw(fd)
    out = os.fdopen(os.dup(sys.stdout.fileno()), "wb", buffering=0)
    out.write(b"\x1b[?1049h\x1b[?25l")
    cols, rows = os.get_terminal_size()
    paint(out, baseline_grid(cols, rows))
    time.sleep(0.3)
    status = os.path.join(args.handshake, "status.json")
    with open(status + ".tmp", "w") as handle:
        json.dump({"cols": cols, "rows": rows, "program": os.environ.get("TERM_PROGRAM"),
                   "version": os.environ.get("TERM_PROGRAM_VERSION")}, handle)
    os.rename(status + ".tmp", status)
    plan_path = os.path.join(args.handshake, "plan.json")
    deadline = time.monotonic() + 180
    while not os.path.exists(plan_path) and time.monotonic() < deadline:
        time.sleep(0.05)
    if os.path.exists(plan_path):
        with open(plan_path) as handle:
            plan = json.load(handle)
        for arm in plan["arms"]:
            with open(arm["stream"], "rb") as handle:
                data = handle.read()
            out.write(b"\x1b[0m\x1b[r\x1b[?69l\x1b[2J\x1b[H")
            offsets, stops = arm["offsets"], set(arm["stops"])
            for index in range(len(offsets) - 1):
                chunk = data[offsets[index]:offsets[index + 1]]
                # One write, held, as `Terminal.endFrame` sends a frame.
                if chunk:
                    out.write(b"\x1b[?2026h" + chunk + b"\x1b[?2026l")
                time.sleep(0.002)
                if index in stops:
                    time.sleep(0.35)
                    path = os.path.join(args.handshake, f"at-{arm['name']}-{index}")
                    open(path, "w").close()
                    ack = path + ".ack"
                    limit = time.monotonic() + 30
                    while not os.path.exists(ack) and time.monotonic() < limit:
                        time.sleep(0.02)
        open(os.path.join(args.handshake, "finished"), "w").close()
    out.write(b"\x1b[r\x1b[?69l\x1b[0m\x1b[?25h\x1b[?1049l")
    termios.tcsetattr(fd, termios.TCSADRAIN, saved)


def drive_replay(args):
    """Launches the player, generates each session's streams at that terminal's
    size, and compares the two arms' pixels at the same steps."""
    from PIL import Image, ImageChops
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Profiling"))
    import scroll_output

    script_dir = args.scratch
    hand = os.path.join(script_dir, f"replay-{args.terminal}")
    shutil.rmtree(hand, ignore_errors=True)
    os.makedirs(hand)
    probe = os.path.join(script_dir, "scroll_region_probe.py")
    shutil.copy(os.path.abspath(__file__), probe)
    launch(args.terminal, script_dir,
           f"exec /usr/bin/python3 {probe} replay --handshake {hand} 2> {hand}/stderr.txt")
    status_path = os.path.join(hand, "status.json")
    deadline = time.monotonic() + 30
    while not os.path.exists(status_path) and time.monotonic() < deadline:
        time.sleep(0.1)
    if not os.path.exists(status_path):
        raise SystemExit("the player never came up")
    with open(status_path) as handle:
        status = json.load(handle)
    cols, rows = status["cols"], status["rows"]
    shot = os.path.join(hand, "keys.png")
    capture(shot)
    image = Image.open(shot).convert("RGB")
    box = locate(image, cols, rows)
    if not box:
        raise SystemExit("could not find the player's window on screen")
    left, top, cell_w, cell_h = box
    crop = (int(left), int(top), int(left + cols * cell_w), int(top + rows * cell_h))
    host = status["program"] or "unidentified"

    arms = []
    expectations = []
    stops_by_arm = {}
    for session in args.sessions:
        played = {}
        for level in ("off", args.level):
            run = scroll_output.play_session(args.stress, session, level, args.steps, cols, rows, host, census=False)
            path = os.path.join(hand, f"{session}-{level}.stream")
            with open(path, "wb") as handle:
                handle.write(run["data"])
            opening = len(run["data"]) - sum(step["bytes"] for step in run["steps"])
            offsets = [0, opening]
            for step in run["steps"]:
                offsets.append(offsets[-1] + step["bytes"])
            played[level] = {"path": path, "offsets": offsets, "bytes": len(run["data"]), "steps": run["steps"]}
        # Stop mostly on the steps the two levels wrote differently: those moved a band.
        differing = [i + 1 for i, (a, b) in enumerate(zip(played["off"]["steps"], played[args.level]["steps"]))
                     if a["bytes"] != b["bytes"]]
        pick = differing[:: max(1, len(differing) // args.stops)][:args.stops]
        pick.append(len(played["off"]["offsets"]) - 2)
        for level in ("off", args.level):
            name = f"{session}-{level}"
            arms.append({"name": name, "stream": played[level]["path"], "offsets": played[level]["offsets"], "stops": pick})
        expectations.append({"session": session, "stops": pick, "moved_steps": len(differing),
                             "off_bytes": played["off"]["bytes"], "level_bytes": played[args.level]["bytes"]})
    path = os.path.join(hand, "plan.json")
    with open(path + ".tmp", "w") as handle:
        json.dump({"arms": arms}, handle)
    os.rename(path + ".tmp", path)

    deadline = time.monotonic() + args.timeout
    pending = [(arm["name"], stop) for arm in arms for stop in arm["stops"]]
    shots = {}
    for name, stop in pending:
        marker = os.path.join(hand, f"at-{name}-{stop}")
        while not os.path.exists(marker) and time.monotonic() < deadline:
            time.sleep(0.02)
        if not os.path.exists(marker):
            raise SystemExit(f"timed out waiting for {name} at {stop}")
        png = marker + ".png"
        capture(png)
        shots[(name, stop)] = png
        open(marker + ".ack", "w").close()
    report = []
    for expected in expectations:
        session = expected["session"]
        worst = 0
        differing_stops = []
        for stop in expected["stops"]:
            a = Image.open(shots[(f"{session}-off", stop)]).convert("RGB").crop(crop)
            b = Image.open(shots[(f"{session}-{args.level}", stop)]).convert("RGB").crop(crop)
            diff = ImageChops.difference(a, b).convert("L").point(lambda v: 255 if v > 24 else 0)
            count = sum(1 for v in diff.getdata() if v)
            worst = max(worst, count)
            if count:
                differing_stops.append((stop, count, diff.getbbox()))
                diff.save(os.path.join(hand, f"diff-{session}-{stop}.png"))
        line = dict(expected, stops_compared=len(expected["stops"]), differing_stops=differing_stops, worst_pixels=worst)
        report.append(line)
        print(f"{args.terminal:<8}{session:<10} {cols}x{rows}  moved steps {expected['moved_steps']:>4}  "
              f"bytes {expected['off_bytes']:>8} -> {expected['level_bytes']:>8}  "
              f"compared {len(expected['stops'])} stops, differing {len(differing_stops)}  worst {worst} px")
    if args.out:
        with open(args.out, "w") as handle:
            json.dump({"terminal": args.terminal, "program": status["program"], "version": status["version"],
                       "level": args.level, "cols": cols, "rows": rows, "date": time.strftime("%Y-%m-%d"),
                       "sessions": report}, handle, indent=1)
            handle.write("\n")


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="mode", required=True)
    c = sub.add_parser("card")
    c.add_argument("--handshake", required=True)
    r = sub.add_parser("replay")
    r.add_argument("--handshake", required=True)
    p = sub.add_parser("cpu")
    p.add_argument("--handshake", required=True)
    d = sub.add_parser("drive")
    d.add_argument("--terminal", required=True, choices=sorted(APPS))
    d.add_argument("--scratch", required=True)
    d.add_argument("--out")
    d.add_argument("--timeout", type=float, default=240)
    d.add_argument("--cpu", action="store_true")
    d.add_argument("--replay", action="store_true", help="the pixel differential: needs --stress")
    d.add_argument("--stress")
    d.add_argument("--sessions", nargs="+", default=["inbox", "log", "chat"])
    d.add_argument("--steps", type=int, default=200)
    d.add_argument("--stops", type=int, default=8)
    d.add_argument("--level", default="exact")
    d.add_argument("--reps", type=int, default=2)
    args = parser.parse_args()
    if args.mode == "card":
        card(args)
    elif args.mode == "cpu":
        cpu_card(args)
    elif args.mode == "replay":
        replay_card(args)
    elif args.replay:
        drive_replay(args)
    elif args.cpu:
        drive_cpu(args)
    else:
        drive(args)


if __name__ == "__main__":
    main()
