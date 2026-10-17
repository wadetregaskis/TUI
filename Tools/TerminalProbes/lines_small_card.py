#!/usr/bin/env python3
"""Prints a card of the candidate one-row looks for a button under an
appearance of lines (`.rounded`, the default) — FB14: something other than
`( Save )`, with no background fill.

Each candidate is drawn as a button would draw it at `.small` (caps, no
padding) and `.regular` (caps and a blank either side), alone and in a row of
three with the middle one focused (its label in the accent, bold, as a
focused button's breath peaks). The line colour is a mid grey, the label the
terminal's foreground: what `.rounded` draws on a page.

    current     ( Save )        parentheses, the shipped look
    1 bars      │ Save │        the appearance's vertical line
    2a corners  ╭ Save ╮        the rounded box's top corners
    2b corners  ⌜ Save ⌟        quine corners
    3 underline  Save           the padded label underlined (SGR 4), the
                                line in the border colour (SGR 58) where the
                                terminal colours underlines
    4 brackets  [ Save ]        the TUI tradition (dialog, whiptail)
    5 eighths   ▕Save▏          eighth blocks hugging the label

Run it in each terminal (`python3 lines_small_card.py`) and compare. The
eighth blocks (5) were dropped once for advance problems: a row of them that
does not line up with the rows above is that problem again.
"""

import sys

ESC = "\x1b"
RESET = f"{ESC}[0m"
LINE = f"{ESC}[38;5;244m"
FOCUS = f"{ESC}[38;5;46;1m"
UNDERLINE_COLOUR = f"{ESC}[58;5;244m"

CANDIDATES = [
    ("current", "(", ")", False),
    ("1 bars", "│", "│", False),
    ("2a corners", "╭", "╮", False),
    ("2b corners", "⌜", "⌟", False),
    ("3 underline", "", "", True),
    ("4 brackets", "[", "]", False),
    ("5 eighths", "▕", "▏", False),
]


def button(label: str, opening: str, closing: str, underline: bool, padded: bool, focused: bool) -> str:
    ink = FOCUS if focused else ""
    pad = " " if padded else ""
    if underline:
        # The whole padded label underlined, in the line colour where SGR 58
        # is honoured; no caps.
        return f"{ESC}[4m{UNDERLINE_COLOUR}{ink}{pad}{label}{pad}{RESET}"
    return f"{LINE}{opening}{RESET}{ink}{pad}{label}{pad}{RESET}{LINE}{closing}{RESET}"


def row(opening: str, closing: str, underline: bool, padded: bool) -> str:
    parts = [
        button(label, opening, closing, underline, padded, focused=(label == "Save"))
        for label in ("Cancel", "Save", "Delete")
    ]
    return "  ".join(parts)


def main() -> None:
    out = [f"{ESC}[2J{ESC}[H", " FB14: one-row buttons under an appearance of lines\r\n\r\n"]
    out.append(f" {'':<12}{'small':<10}{'regular':<12}a row, Save focused (regular)\r\n")
    for name, opening, closing, underline in CANDIDATES:
        small = button("Save", opening, closing, underline, padded=False, focused=False)
        regular = button("Save", opening, closing, underline, padded=True, focused=False)
        small_cells = len("Save") + (0 if underline else 2)
        regular_cells = small_cells + 2
        out.append(
            f" {name:<12}{small}{' ' * (10 - small_cells)}{regular}{' ' * (12 - regular_cells)}"
            f"{row(opening, closing, underline, padded=True)}\r\n\r\n")
    sys.stdout.write("".join(out))
    sys.stdout.flush()


if __name__ == "__main__":
    main()
