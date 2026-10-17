#!/usr/bin/env python3
"""Prints a card for the double-width scrollbar's arrows: whether a terminal
draws the corner triangles `◢◣` and `◥◤` as one arrow across two cells.

A double-width scrollbar (`.scrollbarWidth(.double)`) needs an up and a down
arrow two cells wide. `▲▲` and `▼▼` are two arrows side by side; `◢◣` and `◥◤`
are ONE arrow, its two halves meeting at the seam — if the terminal fills each
half to its cell's edges. A terminal that draws the triangles from a font, at
the font's own size and baseline, leaves a gap at the seam, a step between the
halves, or ink outside the cell, and the arrow reads as two broken pieces.

## The measurement

Each pair is drawn in the scrollbar's own colours — the accent on a track of
dark grey — between two cells of solid magenta, three ways:

    ██◢◣██   the pair, as the scrollbar draws it
    ██◢ ██   the left half alone: its right edge must meet the cell's
    ██ ◣██   the right half alone: its left edge must meet the cell's

and again in double width (DECDWL), where a one-pixel seam is easy to see.

Read it as:
- **Good**: each half fills its cell to the shared edge, corner to corner, so
  the pair is one solid triangle with no seam, no step and no ink on the
  magenta. `█` FULL BLOCK and `▲▲` are the calibration rows.
- **Bad**: a vertical gap at the seam, halves of different heights, a
  triangle that stops short of the cell's top or bottom, or dark marks on a
  flank.

Run it in each terminal (`python3 scrollbar_arrow_card.py`) and record what each one
draws in `Documentation/Terminals/Terminal compatibility survey.md`.
"""

import sys

ESC = "\x1b"
MAGENTA = f"{ESC}[48;5;201m"
TRACK = f"{ESC}[48;5;238m"
ACCENT = f"{ESC}[38;5;46m"
RESET = f"{ESC}[0m"

ROWS = [
    ("full block (calibration)", "██"),
    ("up, two arrows", "▲▲"),
    ("up, one arrow", "◢◣"),
    ("up, left half", "◢ "),
    ("up, right half", " ◣"),
    ("down, two arrows", "▼▼"),
    ("down, one arrow", "◥◤"),
    ("down, left half", "◥ "),
    ("down, right half", " ◤"),
]


def flanked(pair: str) -> str:
    return f"{MAGENTA}  {TRACK}{ACCENT}{pair}{RESET}{MAGENTA}  {RESET}"


def main() -> None:
    out = [f"{ESC}[2J{ESC}[H", "Scrollbar arrow card — one row per candidate, magenta flanks\r\n\r\n"]
    for label, pair in ROWS:
        out.append(f" {flanked(pair)}  {label}\r\n")
    out.append("\r\nDouble width (DECDWL):\r\n")
    for label, pair in ROWS[1:3] + ROWS[5:7]:
        out.append(f"{ESC}#6 {flanked(pair)} {label}\r\n")
    out.append("\r\n")
    sys.stdout.write("".join(out))
    sys.stdout.flush()


if __name__ == "__main__":
    main()
