#!/usr/bin/env python3
"""Prints a card for whether this terminal draws SGR 2 (faint) as anything.

TUI draws a disabled control and a text field's prompt with faint (SGR 2) where
colour is unavailable or not trusted (`NO_COLOR`, `.noColor` depth), and as the
legible fallback for a translucent ink a palette can't show. If a host ignores
SGR 2, a disabled button and an enabled one look the same there: that is what
this card asks.

Each row draws the same word plain and then faint, side by side, in one colour:
the default foreground, a named colour, a 256-colour index, a 24-bit colour,
over a coloured background, and with bold (some hosts make bold and faint one
attribute, and SGR 22 resets both). The last rows draw a button as TUI does,
enabled and then disabled, at no colour. A host supports faint if the right
column is visibly dimmer than the left in every row.

Run INSIDE the terminal under test and record what you saw in
Documentation/Terminals/Terminal compatibility survey.md.
"""
import os
import sys
import time

CSI = "\x1b["
RESET = CSI + "0m"
WORD = "Faintness ████"


def row(label, style):
    plain = f"{CSI}{style}m{WORD}{RESET}" if style else WORD
    faint = f"{CSI}{style};2m{WORD}{RESET}" if style else f"{CSI}2m{WORD}{RESET}"
    return f"  {label:22s} {plain}    {faint}"


def card():
    lines = ["", f"  {'':22s} {'plain':18s}{'faint (SGR 2)'}", ""]
    lines.append(row("default foreground", ""))
    lines.append(row("named red (31)", "31"))
    lines.append(row("bright blue (94)", "94"))
    lines.append(row("256-colour 208", "38;5;208"))
    lines.append(row("24-bit 40;160;90", "38;2;40;160;90"))
    lines.append(row("on blue background", "44"))
    lines.append(row("bold", "1"))
    lines.append("")
    lines.append("  Other attributes a disabled control could use where faint shows nothing:")
    lines.append(f"    plain [ Save ]   italic {CSI}3m[ Save ]{RESET}   faint italic {CSI}2;3m[ Save ]{RESET}"
                 f"   strike {CSI}9m[ Save ]{RESET}   dotted {CSI}4:4m[ Save ]{RESET}")
    lines.append("")
    lines.append("  A button at no colour, as TUI draws it:")
    lines.append(f"    enabled   [ Save ]      disabled  {CSI}2m[ Save ]{RESET}")
    lines.append(f"    focused   {CSI}7m[ Save ]{RESET}      focused, disabled  {CSI}2;7m[ Save ]{RESET}")
    lines.append("")
    lines.append(f"  TERM_PROGRAM={os.environ.get('TERM_PROGRAM', '?')} TERM={os.environ.get('TERM', '?')}")
    return "\n".join(lines)


if __name__ == "__main__":
    sys.stdout.write(CSI + "2J" + CSI + "H" + card() + "\n")
    sys.stdout.flush()
    time.sleep(float(sys.argv[1]) if len(sys.argv) > 1 else 600)
