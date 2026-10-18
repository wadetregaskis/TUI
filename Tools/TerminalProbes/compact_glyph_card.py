#!/usr/bin/env python3
"""E19: candidate one-cell bracket pairs for a compact button, as a button
draws them. Every row ends in `|` at the same column when every glyph
advances one cell; a row whose `|` is out of line has a glyph that does not."""
import unicodedata
ESC = "\x1b"
RESET = f"{ESC}[0m"
LINE = f"{ESC}[38;5;244m"
FOCUS = f"{ESC}[38;5;46;1m"
PAIRS = [("()", "paren"), ("⦇⦈", "image brkt"), ("⦉⦊", "binding brkt"), ("❲❳", "lt tortoise"),
         ("〔〕", "tortoise"), ("⦅⦆", "white paren"), ("❪❫", "flat paren"), ("❨❩", "med paren"),
         ("「」", "corner"), ("『』", "wh corner"), ("⟦⟧", "wh square"), ("⟨⟩", "angle"),
         ("⟮⟯", "flat math"), ("⸨⸩", "dbl paren"), ("［］", "fw square")]
print("E19 compact brackets: all | must line up")
for pair, name in PAIRS:
    l, r = pair[0], pair[1]
    eaw = unicodedata.east_asian_width(l)
    b = lambda w, f=False: f"{LINE}{l}{RESET}{FOCUS if f else ''}{w}{RESET}{LINE}{r}{RESET}"
    print(f"{pair} {name:<12}{eaw:<3}{b('Save')} {b('Save', True)} {LINE}{l}{RESET} Save {LINE}{r}{RESET} {b('Cut')} {b('Copy', True)} {b('Paste')}|")
print(f"{'':<20}" + "1234567890" * 4 + "1234|")
