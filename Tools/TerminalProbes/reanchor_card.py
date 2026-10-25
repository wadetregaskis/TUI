#!/usr/bin/env python3
"""Does anything put a row back on the grid after text a terminal shaped?

Apple Terminal draws Devanagari (and the other scripts it shapes) at the
font's own proportional advance and paints everything after it on the row —
absolutely addressed text included — that much left of its cell. This card
asks which emissions, if any, re-anchor the row: one variant per row, each
ending in a four-cell magenta marker whose column says where the row's
follower was drawn.

## Running it

Inside the terminal under test, from `Tools/TerminalProbes`:

    python3 reanchor_card.py                       # holds the card PROBE_HOLD seconds (default 8)
    PROBE_SYNC=/tmp/card python3 reanchor_card.py  # writes /tmp/card.ready, waits for /tmp/card.done

Capture the window while it holds (`screencapture -x -o -l <window id> shot.png`
films the window even from behind other windows), then:

    python3 reanchor_card.py --read shot.png

which finds the green calibration cell (row 1, column 1) and prints each
variant's marker column against the column it was aimed at. A marker at a
FRACTIONAL column is the shaped text's own advance showing through.
"""
import os
import sys
import termios
import time
import tty

MARKER = "\x1b[48;5;201m    \x1b[0m"
CALIBRATION = "\x1b[48;5;46m  \x1b[0m"

HINDI = "हिन्दी"           # हि + न्दी: advance 5
NAMASTE = "नमस्ते"         # न + म + स्ते: advance 4
DUNIYA = "दुनिया"          # दु + नि + या: advance 5
SANSKRIT = "संस्कृत"       # advance 4; Apple Terminal 455.1 drew no त


def surgery(cells):
    """Apple Terminal's flag repair (`CUB DCH CUF`), `cells` wide."""
    return f"\x1b[{cells}D\x1b[{cells}P\x1b[{cells}C"


# (name, emission, the column the marker is aimed at)
VARIANTS = [
    ("control: a, CHA 20", "a\x1b[20G" + MARKER, 20),
    ("hindi, CHA 20", HINDI + "\x1b[20G" + MARKER, 20),
    ("hindi, CUP 20", HINDI + "\x1b[{row};20H" + MARKER, 20),
    ("hindi, CR then CHA 20", HINDI + "\r\x1b[20G" + MARKER, 20),
    ("hindi, EL then CHA 20", HINDI + "\x1b[K\x1b[20G" + MARKER, 20),
    ("hindi, HT HT", HINDI + "\t\t" + MARKER, 17),
    ("hindi, SGR'd space, CHA 20", HINDI + "\x1b[38;5;1m \x1b[0m\x1b[20G" + MARKER, 20),
    ("hindi, U+3000, CHA 20", HINDI + "　\x1b[20G" + MARKER, 20),
    ("hindi, box glyph, CHA 20", HINDI + "│\x1b[20G" + MARKER, 20),
    ("hindi on a background, CHA 20", "\x1b[48;5;250m" + HINDI + "\x1b[0m\x1b[20G" + MARKER, 20),
    ("namaste, CHA 20", NAMASTE + "\x1b[20G" + MARKER, 20),
    ("namaste duniya, CHA 30", NAMASTE + " " + DUNIYA + "\x1b[30G" + MARKER, 30),
    ("sanskrit, CHA 20", SANSKRIT + "\x1b[20G" + MARKER, 20),
    ("hindi, surgery 1 after न्दी", "हि" + "न्दी" + surgery(1) + MARKER, 6),
    ("namaste, surgery 2 after स्ते", "नम" + "स्ते" + surgery(2) + MARKER, 5),
]


def draw():
    fd = os.open("/dev/tty", os.O_RDWR)
    saved = termios.tcgetattr(fd)
    tty.setraw(fd)
    try:
        os.write(fd, b"\x1b[?1049h\x1b[2J\x1b[?25l")
        for index, (_, emission, _) in enumerate(VARIANTS):
            row = index + 2
            os.write(fd, f"\x1b[{row};1H".encode() + emission.replace("{row}", str(row)).encode())
        os.write(fd, b"\x1b[1;1H" + CALIBRATION.encode())
        sync = os.environ.get("PROBE_SYNC")
        if sync:
            open(sync + ".ready", "w").close()
            deadline = time.time() + 120
            while not os.path.exists(sync + ".done") and time.time() < deadline:
                time.sleep(0.2)
        else:
            time.sleep(int(os.environ.get("PROBE_HOLD", "8")))
        os.write(fd, b"\x1b[?25h\x1b[?1049l")
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, saved)
        os.close(fd)


def read(path):
    from PIL import Image  # only the reading half needs Pillow

    image = Image.open(path).convert("RGB")
    width, height = image.size

    def is_green(pixel):
        return pixel[1] > 220 and pixel[0] < 60 and pixel[2] < 60

    def is_magenta(pixel):
        return pixel[0] > 200 and pixel[1] < 60 and pixel[2] > 200

    # The calibration cell: its top-left corner and its width are a cell's.
    origin = next(((x, y) for y in range(height) for x in range(width) if is_green(image.getpixel((x, y)))), None)
    if origin is None:
        raise SystemExit("no calibration cell in the shot")
    x0, y0 = origin
    right = x0
    while right < width and is_green(image.getpixel((right, y0 + 2))):
        right += 1
    cell_width = (right - x0) / 2
    bottom = y0
    while bottom < height and is_green(image.getpixel((x0 + 1, bottom))):
        bottom += 1
    cell_height = bottom - y0
    for index, (name, _, aimed) in enumerate(VARIANTS):
        y = int(y0 + (index + 1) * cell_height + cell_height / 2)
        columns = [x for x in range(width) if is_magenta(image.getpixel((x, y)))]
        landed = (columns[0] - x0) / cell_width + 1 if columns else None
        shown = f"{landed:.2f}" if landed is not None else "none"
        print(f"{name:34} aimed {aimed:3}  drawn at {shown}")


if __name__ == "__main__":
    if "--read" in sys.argv:
        read(sys.argv[sys.argv.index("--read") + 1])
    else:
        draw()
