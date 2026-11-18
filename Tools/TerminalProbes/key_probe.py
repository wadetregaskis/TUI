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
Documentation/Historical/Presentation and windows/Sheets - sizes, detents, live sheets and the page behind.md (its appendix's §4) and
Documentation/Terminals/Terminal compatibility survey.md, "Keys a sheet's grabber uses" —
and the menu bar's (F10, and ⌥F for Alt with a title's first letter) — see the
survey's "The menu bar's keys". On a Mac keyboard F10 is the mute key unless fn is
held or System Settings → Keyboard says to use F1, F2, etc. as standard function
keys, so it asks for F10 twice, without fn and with it: record that setting. And
⇧F1, which shows help at the lowest priority (B-HELP-2). And F1 and ⌃F1, for the
list of keyboard shortcuts: F1 alone, without fn and with it, and ⌃F1 with fn,
which macOS keeps for "Turn keyboard access on or off" unless that shortcut is
off, and which no terminal should then see (the survey's "The list of keyboard
shortcuts' key").

`PROBE_KEYS` asks only the keys it names, by the ids in KEYS, comma-separated —
`PROBE_KEYS=f10,fn_f10,shift_f1` for the menu bar's and help's keys alone, and
`PROBE_KEYS=f1,fn_f1,shift_f1,ctrl_f1` for the list of shortcuts' alone, and
`PROBE_KEYS=f2,fn_f2,ctrl_comma` for the settings panel's.

`PROBE_KITTY=<flags>` pushes the kitty keyboard protocol's flags first (`CSI >
flags u`, popped at the end), so a host that speaks it is read in its encoding:
`PROBE_KITTY=31` asks for what TUI asks for (`KittyKeyboardFlags.requested`).
A release report, and a modifier or lock key's own report, are dropped and the
wait goes on, so each prompt records the key's press.

Run INSIDE the terminal under test, from its DEFAULT profile, once on each
screen: TUI draws on the alternate screen (`PROBE_ALT=1`), and a host's
scrollback keys can behave differently there from the primary screen, where
there is a buffer to scroll. Press each key once when asked; a prompt gives up
after `PROBE_WAIT` seconds (default 6) and records nothing arrived. Ctrl-C
ends the run early. Writes JSON to $PROBE_OUT (default ./key_probe.json), with
the shared provenance stamp, and prints a summary.
"""
import json, os, re, select, sys, termios, time, tty

import probe_stamp

WAIT = float(os.environ.get("PROBE_WAIT", "6"))
KITTY = int(os.environ.get("PROBE_KITTY", "0"))
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
    ("f10", "F10 alone, without fn"),
    ("fn_f10", "fn-F10 (hold fn)"),
    ("shift_f1", "⇧F1 Shift-F1 (with fn if F1 alone dims the screen)"),
    ("option_f", "⌥F Option-F"),
    ("f1", "F1 alone, without fn"),
    ("fn_f1", "fn-F1 (hold fn)"),
    ("ctrl_f1", "⌃F1 Control-F1 (with fn if F1 alone dims the screen)"),
    ("f2", "F2 alone, without fn"),
    ("fn_f2", "fn-F2 (hold fn)"),
    ("ctrl_comma", "⌃, Control-comma"),
]

# The legacy spellings each could arrive as, in the xterm family's grammar.
FINALS = {"A": "up", "B": "down", "C": "right", "D": "left", "H": "home", "F": "end",
          "P": "f1", "Q": "f2", "R": "f3", "S": "f4"}
TILDES = {1: "home", 7: "home", 4: "end", 8: "end", 5: "page_up", 6: "page_down",
          11: "f1", 12: "f2", 13: "f3", 14: "f4", 21: "f10", 23: "f11", 24: "f12"}
# SS3 P to S are F1 to F4 in the normal mode; SS3 A to D are the arrows only in
# the cursor keys' application mode.
SS3_FUNCTION_KEYS = "PQRS"
MODIFIERS = {2: "shift", 3: "option", 4: "shift+option", 5: "control", 6: "shift+control",
             7: "option+control", 8: "shift+option+control"}


def render(raw):
    return "".join(
        "<ESC>" if b == 0x1B else (f"<{b:02X}>" if b < 0x20 or b == 0x7F else chr(b))
        for b in raw)


# The kitty protocol's modifier bits, after its offset of one.
KITTY_MODIFIERS = ["shift", "option", "control", "super", "hyper", "meta", "caps_lock", "num_lock"]
# Its functional keys' code points, for those the probe asks for or may meet.
KITTY_KEYS = {9: "tab", 13: "return", 27: "escape", 127: "backspace", 57358: "caps_lock",
              57359: "scroll_lock", 57360: "num_lock"}
KITTY_REPORT = re.compile(r"\[([\d:;]*)([u~A-DFHPQRS])")


def kitty_report(text):
    """A kitty report's (key code or tilde number, modifier bits, event type,
    final) — or None for a sequence of another shape."""
    match = KITTY_REPORT.fullmatch(text)
    if not match:
        return None
    fields = match.group(1).split(";") if match.group(1) else []
    key = fields[0].split(":")[0] if fields else ""
    mods = fields[1].split(":") if len(fields) > 1 else ["1"]
    return (int(key) if key.isdigit() else 1, int(mods[0] or "1") - 1,
            int(mods[1]) if len(mods) > 1 and mods[1].isdigit() else 1, match.group(2))


def kitty_name(text):
    """A kitty report's name, or None."""
    report = kitty_report(text)
    if report is None:
        return None
    key, bits, event, final = report
    if final == "u":
        name = KITTY_KEYS.get(key) or (chr(key) if 32 < key < 57344 else f"key {key}")
    elif final == "~":
        name = TILDES.get(key) or f"~{key}"
    else:
        name = FINALS[final]
    mods = [m for i, m in enumerate(KITTY_MODIFIERS) if bits & (1 << i)]
    events = {2: " (repeat)", 3: " (release)"}
    return "+".join(mods + [name]) + events.get(event, "")


def kitty_noise(match):
    """Whether a report is one the probe drops: a release, or a modifier or
    lock key's own (57441 to 57452, and Caps, Scroll and Num Lock)."""
    report = kitty_report(match.group(0).decode("latin-1"))
    if report is None:
        return False
    key, _, event, final = report
    return event == 3 or (final == "u" and (57441 <= key <= 57452 or 57358 <= key <= 57360))


KITTY_SEQUENCE = re.compile(rb"\[[\d:;]*[u~A-DFHPQRS]")


def decode(raw):
    """A key sequence's name — the kitty protocol's where it was pushed, else
    the legacy spellings' — or None."""
    text = raw.decode("latin-1")
    if KITTY and (name := kitty_name(text)):
        return name
    if len(text) == 2 and text[0] == "\x1b" and text[1].isalpha():
        return "option+" + text[1]
    prefix = ""
    if text.startswith("\x1b\x1b"):
        prefix, text = "option+", text[1:]
    if text.startswith("\x1bO") and len(text) == 3 and text[2] in FINALS:
        mode = "" if text[2] in SS3_FUNCTION_KEYS else " (application mode)"
        return prefix + FINALS[text[2]] + mode
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


# An SGR mouse report. The probe asks for no mouse reporting, but the Windows
# console's raw mode (TUI's, which `windows/termios.py` copies) takes mouse input,
# and Windows Terminal then reports the pointer's motion unasked: a report is
# never a key, so it is dropped and the wait goes on.
MOUSE_REPORT = re.compile(rb"\x1b\[<\d+;\d+;\d+[Mm]")


def read_key(fd):
    """The bytes of one key, or b"" when nothing arrived within the wait."""
    give_up = time.monotonic() + WAIT
    while (left := give_up - time.monotonic()) > 0 and select.select([fd], [], [], left)[0]:
        raw = os.read(fd, 64)
        deadline = time.monotonic() + TAIL
        while (left := deadline - time.monotonic()) > 0 and select.select([fd], [], [], left)[0]:
            raw += os.read(fd, 64)
        raw = MOUSE_REPORT.sub(b"", raw)
        if KITTY:
            raw = KITTY_SEQUENCE.sub(lambda m: b"" if kitty_noise(m) else m.group(0), raw)
        if raw:
            return raw
    return b""


def main():
    use_alt = os.environ.get("PROBE_ALT") == "1"
    out_path = os.environ.get("PROBE_OUT", "key_probe.json")
    wanted = [k for k in os.environ.get("PROBE_KEYS", "").split(",") if k]
    unknown = set(wanted) - {key for key, _ in KEYS}
    if unknown:
        sys.exit(f"PROBE_KEYS names keys this probe does not ask: {', '.join(sorted(unknown))}")
    keys = [(key, label) for key, label in KEYS if not wanted or key in wanted]
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    tty.setraw(fd)
    result = {"keys": {}}
    try:
        if use_alt:
            os.write(fd, b"\x1b[?1049h")
        result["stamp"] = probe_stamp.stamp(fd, "key_probe", use_alt)
        result["kitty_flags"] = KITTY
        if KITTY:
            os.write(fd, f"[>{KITTY}u".encode())
        os.write(fd, b"\x1b[2J\x1b[H")
        for key, label in keys:
            os.write(fd, f"\r\nPress {label} once (waiting {WAIT:g} s; Ctrl-C ends): ".encode())
            raw = read_key(fd)
            if raw == b"\x03":
                break
            result["keys"][key] = {
                "raw": render(raw), "decoded": decode(raw) if raw else None, "arrived": bool(raw)}
            os.write(fd, (render(raw) or "(nothing)").encode())
    finally:
        if KITTY:
            os.write(fd, b"[<u")
        if use_alt:
            os.write(fd, b"\x1b[?1049l")
        termios.tcsetattr(fd, termios.TCSADRAIN, old)

    result["mission_control_shortcuts"] = "fill in by hand: on or off in System Settings"
    result["f_keys_standard"] = "fill in by hand: F10 or fn-F10 pressed, and the standard-function-keys setting"
    with open(out_path, "w") as handle:
        json.dump(result, handle, indent=1, ensure_ascii=False)
    env = result["stamp"]["env"]
    print(f"{env.get('TERM_PROGRAM', '?')} {env.get('TERM_PROGRAM_VERSION', '')} "
          f"on the {'alternate' if use_alt else 'primary'} screen"
          + (f", kitty flags {KITTY}" if KITTY else ""))
    for key, label in keys:
        reading = result["keys"].get(key)
        if reading is None:
            continue
        shown = reading["raw"] or "NOTHING ARRIVED"
        print(f"  {label:32} {shown:16} {reading['decoded'] or ''}")
    print(f"  written to {os.path.abspath(out_path)}")


if __name__ == "__main__":
    main()
