#!/usr/bin/env python3
"""Prints a card of a glass panel over a Kitty image, drawn four ways, for
choosing how TUI frosts a picture it does not draw (owner, 2026-10-26: "give
it a shot; review it in probes before the clips").

A Kitty image is cells naming an image the TERMINAL holds, so the pixels under
a translucent layer are not TUI's to blend: the opacity resolution reads a
placeholder cell's foreground as the image's id, not a colour. Each panel below
is the same photo with the same glass panel across it:

  A. COVERED — the panel's cells drawn opaque in the glass's tint: what any
     opaque layer does to an image, and the floor.
  B. BLOCKS — the cells under the panel drawn as half blocks of the frosted
     picture (blurred, tinted): what TUI can do from pixels it has, with no
     help from the terminal. Two colours a cell.
  C. DERIVED IMAGE — a second image transmitted once: the whole picture,
     blurred and tinted at full resolution. Cells under the panel name it
     instead of the original, with the same row and column, so it lines up
     exactly. A cell the panel writes text in cannot hold a picture, so it
     takes the frosted picture's average colour there.

  D. DERIVED, UNDER TEXT — C, but the text cells hold no field: the derived
     image, cropped to the glass, is laid UNDER the text as well, by a classic
     placement at z = -1 (kitty: below text, above cell fields) at the glass's
     top-left cell, the cursor left where it was (C=1).

Read: does C's glass read as frosted glass over the photo, and B's as a blocky
stand-in? Are C's text cells (solid fields) acceptable against the pixels
around them, or do they need B's blocks too (`--text-blocks`)? Does D lose
C's cell-shaped blocks behind the words?

Measured 2026-10-26: Ghostty 1.3.1 draws D exactly — the words on the frosted
picture, no blocks. iTerm2 3.7.6 refuses D's placement ("invalid payload");
its z order differs too (z=0 under text, z=-1 over a cell's fill: the
hairline probe). `ONLY=under` (comma-separated kinds) draws just those panels.

    python3 Tools/TerminalProbes/frost_over_image_card.py
    python3 Tools/TerminalProbes/frost_over_image_card.py --photo galago --tint light
    python3 Tools/TerminalProbes/frost_over_image_card.py --text-blocks

Needs a terminal that answers the Kitty placeholder query (Ghostty, iTerm2,
kitty) and Pillow.
"""
import argparse
import os
import sys

from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from placement_probe import cell, foreground, place, transmit  # noqa: E402

PHOTOS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "ScreenClips", "Photos")
E = "\x1b["

# Each panel's box, in cells, and the glass across it.
COLUMNS, ROWS = 36, 12
GLASS_TOP, GLASS_BOTTOM = 3, 9          # rows [3, 9)
GLASS_LEFT, GLASS_RIGHT = 3, 33         # columns [3, 33)
TEXT = {4: "  Fawn · Big Basin", 5: "  3 photos · 2 days ago", 7: "  ◀  Library     Share  ▶"}
# Pixels per cell: a terminal cell is about twice as tall as wide.
CELL_W, CELL_H = 12, 24
TINTS = {"dark": ((24, 26, 32), 0.45), "light": ((245, 246, 250), 0.40)}


def quiet(escapes):
    """The escapes with every reply suppressed (`q=2`): a card reads nothing
    back, and an unread `OK` lands on the screen as text."""
    return escapes.replace(",q=0", ",q=2")


def sgr_fg(rgb):
    return f"{E}38;2;{rgb[0]};{rgb[1]};{rgb[2]}m"


def sgr_bg(rgb):
    return f"{E}48;2;{rgb[0]};{rgb[1]};{rgb[2]}m"


def frosted(image, tint):
    """The picture as glass shows it: blurred over about a cell, then mixed
    toward the tint in encoded sRGB, as TUI's materials mix."""
    colour, amount = tint
    blurred = image.filter(ImageFilter.GaussianBlur(radius=CELL_W * 1.2))
    overlay = Image.new("RGB", image.size, colour)
    return Image.blend(blurred, overlay, amount)


def average(image, column, row, half=None):
    """The average colour of a cell of `image` — or of its top or bottom half."""
    top = row * CELL_H + (CELL_H // 2 if half == "bottom" else 0)
    bottom = (row + 1) * CELL_H - (CELL_H // 2 if half == "top" else 0)
    box = image.crop((column * CELL_W, top, (column + 1) * CELL_W, bottom)).resize((1, 1), Image.BOX)
    return box.getpixel((0, 0))


def under_glass(row, column):
    return GLASS_TOP <= row < GLASS_BOTTOM and GLASS_LEFT <= column < GLASS_RIGHT


def text_at(row, column):
    """The glass panel's character at a cell, or None where it writes none."""
    line = TEXT.get(row)
    if line is None:
        return None
    index = column - GLASS_LEFT
    if 0 <= index < len(line) and line[index] != " ":
        return line[index]
    return None


def panel_rows(kind, original_id, derived_id, image, glass, tint, text_blocks):
    rows = []
    ink = (250, 250, 250) if tint == TINTS["dark"] else (20, 22, 28)
    for row in range(ROWS):
        out = ""
        for column in range(COLUMNS):
            if not under_glass(row, column):
                out += foreground(original_id) + cell(row, column, original_id) + f"{E}39m"
                continue
            glyph = text_at(row, column)
            if kind == "covered":
                field = tint[0]
                out += sgr_bg(field) + sgr_fg(ink) + (glyph or " ") + f"{E}0m"
            elif kind == "blocks" or (glyph and text_blocks):
                if glyph:
                    out += sgr_bg(average(glass, column, row)) + sgr_fg(ink) + glyph + f"{E}0m"
                else:
                    top, bottom = average(glass, column, row, "top"), average(glass, column, row, "bottom")
                    out += sgr_fg(top) + sgr_bg(bottom) + "▀" + f"{E}0m"
            elif kind == "under":
                out += (sgr_fg(ink) + glyph + f"{E}39m") if glyph else " "
            else:  # derived
                if glyph:
                    out += sgr_bg(average(glass, column, row)) + sgr_fg(ink) + glyph + f"{E}0m"
                else:
                    out += foreground(derived_id) + cell(row, column, derived_id) + f"{E}39m"
        rows.append(out)
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--photo", default="fawn", help="a name in Tools/ScreenClips/Photos (no extension)")
    parser.add_argument("--tint", default="dark", choices=sorted(TINTS))
    parser.add_argument("--text-blocks", action="store_true", help="C's text cells as B draws them")
    parser.add_argument(
        "--derived-pixels", type=int, default=0,
        help="C's derived image at this many pixels across a cell (0: full resolution), for whether the "
        "terminal's own scaling smooths a tiny frosted copy")
    args = parser.parse_args()

    source = Image.open(os.path.join(PHOTOS, args.photo + ".webp")).convert("RGB")
    size = (COLUMNS * CELL_W, ROWS * CELL_H)
    # Cover the box, cropping the long side, as an Image with `.fill` does.
    scale = max(size[0] / source.width, size[1] / source.height)
    scaled = source.resize((round(source.width * scale), round(source.height * scale)), Image.LANCZOS)
    left, top = (scaled.width - size[0]) // 2, (scaled.height - size[1]) // 2
    image = scaled.crop((left, top, left + size[0], top + size[1]))
    tint = TINTS[args.tint]
    glass = frosted(image, tint)

    # Ids of this run's own: an id transmitted again replaces the picture under
    # every cell already naming it, so a second card would repaint the first.
    original_id = 0x5A0000 + (os.getpid() % 0x4000) * 2
    derived_id = original_id + 1
    out = sys.stdout
    out.write(quiet(transmit(image.tobytes(), original_id, *size) + place(original_id, COLUMNS, ROWS)))
    derived = glass
    if args.derived_pixels:
        small = (COLUMNS * args.derived_pixels, ROWS * args.derived_pixels * 2)
        derived = glass.resize(small, Image.BOX)
    out.write(quiet(transmit(derived.tobytes(), derived_id, *derived.size) + place(derived_id, COLUMNS, ROWS)))

    kinds = [("covered", "A. covered"), ("blocks", "B. blocks"), ("derived", "C. derived image"),
             ("under", "D. derived, under text")]
    if os.environ.get("ONLY"):
        kinds = [k for k in kinds if k[0] in os.environ["ONLY"].split(",")]
    panels = [panel_rows(kind, original_id, derived_id, image, glass, tint, args.text_blocks) for kind, _ in kinds]
    out.write("\n" + "  ".join(title.ljust(COLUMNS) for _, title in kinds) + "\n")
    for row in range(ROWS):
        out.write("  ".join(panel[row] for panel in panels) + f"{E}0m\n")
    # D's glass: the derived copy, cropped to the glass, laid UNDER the text by a
    # classic placement at z = -1 (kitty: below text, above cell fields), at the
    # glass's top-left cell, the cursor left where it was (C=1).
    names = [kind for kind, _ in kinds]
    if "under" in names:
        index = names.index("under")
        rows_up = ROWS - GLASS_TOP  # the cursor is on the line after the panels
        column = index * (COLUMNS + 2) + GLASS_LEFT + 1
        scale_x, scale_y = derived.size[0] / size[0], derived.size[1] / size[1]
        x, y = int(GLASS_LEFT * CELL_W * scale_x), int(GLASS_TOP * CELL_H * scale_y)
        w = int((GLASS_RIGHT - GLASS_LEFT) * CELL_W * scale_x)
        h = int((GLASS_BOTTOM - GLASS_TOP) * CELL_H * scale_y)
        out.write("\x1b7")  # save the cursor
        out.write(f"\x1b[{rows_up}A\x1b[{column}G")
        out.write(f"\x1b_Ga=p,i={derived_id},p=7,x={x},y={y},w={w},h={h},"
                  f"c={GLASS_RIGHT - GLASS_LEFT},r={GLASS_BOTTOM - GLASS_TOP},z=-1,C=1,q=2\x1b\\")
        out.write("\x1b8")  # and put it back
    detail = f", derived at {args.derived_pixels}px a cell ({derived.size[0]}x{derived.size[1]})" if args.derived_pixels else ""
    out.write(f"\n{args.photo}, {args.tint} glass{', text cells as blocks' if args.text_blocks else ''}{detail}\n")
    out.flush()


if __name__ == "__main__":
    main()
