#!/usr/bin/env python3
"""Legacy key probe: what does each key a TUI binding names actually send,
with no keyboard protocol pushed — and does it arrive at all?

Raw mode, no kitty flags, no mouse reporting: the encoding an app sees on a
host that does not speak the kitty keyboard protocol. It asks for each key in
turn and records what arrived within a window — the bytes and a decoding, or
NOTHING, which is an answer: a host that keeps a key for itself (a profile that
scrolls its buffer on a bare Page Up, Home or End) sends the app nothing, and
macOS takes ⌃↑ and ⌃↓ for Mission Control before any terminal sees them, unless
those shortcuts are turned off in System Settings → Keyboard → Keyboard
Shortcuts → Mission Control. Record whether they are.

The keys asked are a detented sheet's grabber's (↑ ↓, ↖ ↘ Home and End) and the
ones its design rejected or deferred (⇞ ⇟, ⌃↑ ⌃↓, ⇧↑, ⌥↑) — see
Documentation/Historical/Live sheets design study, A19 (2026-10-04).md §4 and
Documentation/Terminals/Terminal compatibility survey.md, "Keys a sheet's grabber uses" —
and the menu bar's (F10, and ⌥F for Alt with a title's first letter) — see the
survey's "The menu bar's keys". On a Mac keyboard F10 is the mute key unless fn is
held or System Settings → Keyboard says to use F1, F2, etc. as standard function
keys: record which was pressed, F10 or fn-F10, and that setting.

Run INSIDE the terminal under test, from its DEFAULT profile, once on each
screen: TUI draws on the alternate screen (`PROBE_ALT=1`), and a host's
scrollback keys can behave differently there from the primary screen, where
there is a buffer to scroll. Press each key once when asked; a prompt gives up
after `PROBE_WAIT` seconds (default 6) and records nothing arrived. Ctrl-C
ends the run early. Writes JSON to $PROBE_OUT (default ./key_probe.json), with
the shared provenance stamp, and prints a summary.
"""
import json, os, select, sys, termios, time, tty

import probe_stamp

WAIT = float(os.environ.get("PROBE_WAIT", "6"))
# After the first byte, how long the rest of a sequence may take to follow.
TAIL = 0.15

KEYS = [
    ("home", "↖ Home (fn-← on a laptop)"),
    ("end", "↘ End (fn-→ on a laptop)"),
    ("page_up", "⇞ Page Up (fn-↑ on a laptop)"),
    ("page_down", "⇟ Page Down (fn-↓ on a laptop)"),
    ("up", "↑"),
    ("down", "↓"),
    ("ctrl_up", "⌃↑ Control-Up"),
    ("ctrl_down", "⌃↓ Control-Down"),
    ("shift_up", "⇧↑ Shift-Up"),
    ("option_up", "⌥↑ Option-Up"),
    ("f10", "F10 (fn-F10 on a Mac keyboard)"),
    ("option_f", "⌥F Option-F"),
]

# The legacy spellings each could arrive as, in the xterm family's grammar.
FINALS = {"A": "up", "B": "down", "C": "right", "D": "left", "H": "home", "F": "end"}
TILDES = {1: "home", 7: "home", 4: "end", 8: "end", 5: "page_up", 6: "page_down", 21: "f10"}
MODIFIERS = {2: "shift", 3: "option", 4: "shift+option", 5: "control", 6: "shift+control",
             7: "option+control", 8: "shift+option+control"}


def render(raw):
    return "".join(
        "<ESC>" if b == 0x1B else (f"<{b:02X}>" if b < 0x20 or b == 0x7F else chr(b))
        for b in raw)


def decode(raw):
    """A legacy key sequence's name, or None."""
    text = raw.decode("latin-1")
    if len(text) == 2 and text[0] == "\x1b" and text[1].isalpha():
        return "option+" + text[1]
    prefix = ""
    if text.startswith("\x1b\x1b"):
        prefix, text = "option+", text[1:]
    if text.startswith("\x1bO") and len(text) == 3 and text[2] in FINALS:
        return prefix + FINALS[text[2]] + " (application mode)"
    if not text.startswith("\x1b[") or len(text) < 3:
        return None
    body, final = text[2:-1], text[-1]
    params = [int(part) if part.isdigit() else None for part in body.split(";")] if body else []
    modifier = MODIFIERS.get(params[1]) if len(params) > 1 else None
    if final in FINALS:
        name = FINALS[final]
    elif final == "~" and params and params[0] in TILDES:
        name = TILDES[params[0]]
    else:
        return None
    return prefix + (f"{modifier}+{name}" if modifier else name)


def read_key(fd):
    """The bytes of one key, or b"" when nothing arrived within the wait."""
    if not select.select([fd], [], [], WAIT)[0]:
        return b""
    raw = os.read(fd, 64)
    deadline = time.monotonic() + TAIL
    while (left := deadline - time.monotonic()) > 0 and select.select([fd], [], [], left)[0]:
        raw += os.read(fd, 64)
    return raw


def main():
    use_alt = os.environ.get("PROBE_ALT") == "1"
    out_path = os.environ.get("PROBE_OUT", "key_probe.json")
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    tty.setraw(fd)
    result = {"keys": {}}
    try:
        if use_alt:
            os.write(fd, b"\x1b[?1049h")
        result["stamp"] = probe_stamp.stamp(fd, "key_probe", use_alt)
        os.write(fd, b"\x1b[2J\x1b[H")
        for key, label in KEYS:
            os.write(fd, f"\r\nPress {label} once (waiting {WAIT:g} s; Ctrl-C ends): ".encode())
            raw = read_key(fd)
            if raw == b"\x03":
                break
            result["keys"][key] = {
                "raw": render(raw), "decoded": decode(raw) if raw else None, "arrived": bool(raw)}
            os.write(fd, (render(raw) or "(nothing)").encode())
    finally:
        if use_alt:
            os.write(fd, b"\x1b[?1049l")
        termios.tcsetattr(fd, termios.TCSADRAIN, old)

    result["mission_control_shortcuts"] = "fill in by hand: on or off in System Settings"
    result["f_keys_standard"] = "fill in by hand: F10 or fn-F10 pressed, and the standard-function-keys setting"
    with open(out_path, "w") as handle:
        json.dump(result, handle, indent=1, ensure_ascii=False)
    env = result["stamp"]["env"]
    print(f"{env.get('TERM_PROGRAM', '?')} {env.get('TERM_PROGRAM_VERSION', '')} "
          f"on the {'alternate' if use_alt else 'primary'} screen")
    for key, label in KEYS:
        reading = result["keys"].get(key)
        if reading is None:
            continue
        shown = reading["raw"] or "NOTHING ARRIVED"
        print(f"  {label:32} {shown:16} {reading['decoded'] or ''}")
    print(f"  written to {os.path.abspath(out_path)}")


if __name__ == "__main__":
    main()
