#!/usr/bin/env python3
"""Kitty keyboard protocol EVENT probe: with the flags TUI pushes, what
does each key the user presses actually send?

Pushes `CSI > 31 u` (all five enhancements, as TUI asks for them), asks
what the terminal took, then logs every read raw and decoded, until Ctrl-C
(in any encoding) or two minutes of silence. Pops the flags on the way out,
including on an exception.

The decoder here is written from the specification
(<https://sw.kovidgoyal.net/kitty/keyboard-protocol/>), independently of
TUI's `KittyKeyDecoder`, so a disagreement between the two is worth a
look: the log is the ground truth, and both decoders are claims about it.

The keys worth pressing, and why, are listed in
Documentation/Terminals/Terminal compatibility survey.md, "The kitty keyboard protocol" → "To
measure, per host". Record the terminal's version and Option-key setting with
the log.

Run INSIDE the terminal under test. Writes to $PROBE_OUT (default
./keyboard_events_probe.log), appending; prints each decoded event as it comes.
`PROBE_ALT=1` runs on the alternate screen, as TUI does.
"""
import os, re, select, signal, sys, termios, time, tty

REQUESTED = 31
IDLE_LIMIT = 120.0

MODIFIERS = [(1, "shift"), (2, "alt"), (4, "ctrl"), (8, "super"), (16, "hyper"),
             (32, "meta"), (64, "caps_lock"), (128, "num_lock")]
EVENTS = {1: "press", 2: "repeat", 3: "release"}
FUNCTIONAL = {
    27: "ESCAPE", 13: "ENTER", 9: "TAB", 127: "BACKSPACE", 57358: "CAPS_LOCK",
    57359: "SCROLL_LOCK", 57360: "NUM_LOCK", 57361: "PRINT_SCREEN", 57362: "PAUSE",
    57363: "MENU", 57414: "KP_ENTER", 57441: "LEFT_SHIFT", 57442: "LEFT_CONTROL",
    57443: "LEFT_ALT", 57444: "LEFT_SUPER", 57445: "LEFT_HYPER", 57446: "LEFT_META",
    57447: "RIGHT_SHIFT", 57448: "RIGHT_CONTROL", 57449: "RIGHT_ALT",
    57450: "RIGHT_SUPER", 57451: "RIGHT_HYPER", 57452: "RIGHT_META",
    57453: "ISO_LEVEL3_SHIFT", 57454: "ISO_LEVEL5_SHIFT",
}
for n in range(10):
    FUNCTIONAL[57399 + n] = f"KP_{n}"
for n, name in enumerate(["DECIMAL", "DIVIDE", "MULTIPLY", "SUBTRACT", "ADD"]):
    FUNCTIONAL[57409 + n] = f"KP_{name}"
for n, name in enumerate(["EQUAL", "SEPARATOR", "LEFT", "RIGHT", "UP", "DOWN", "PAGE_UP",
                          "PAGE_DOWN", "HOME", "END", "INSERT", "DELETE", "BEGIN"]):
    FUNCTIONAL[57415 + n] = f"KP_{name}"
for n in range(23):
    FUNCTIONAL[57376 + n] = f"F{13 + n}"
LETTERS = {"A": "UP", "B": "DOWN", "C": "RIGHT", "D": "LEFT", "E": "KP_BEGIN", "F": "END",
           "H": "HOME", "P": "F1", "Q": "F2", "S": "F4"}
TILDES = {2: "INSERT", 3: "DELETE", 5: "PAGE_UP", 6: "PAGE_DOWN", 7: "HOME", 8: "END",
          11: "F1", 12: "F2", 13: "F3", 14: "F4", 15: "F5", 17: "F6", 18: "F7", 19: "F8",
          20: "F9", 21: "F10", 23: "F11", 24: "F12", 200: "PASTE_START", 201: "PASTE_END"}


def render(raw):
    return "".join(
        "<ESC>" if b == 0x1B else (f"<{b:02X}>" if b < 0x20 or b == 0x7F else chr(b))
        for b in raw)


def key_name(code):
    if code in FUNCTIONAL:
        return FUNCTIONAL[code]
    try:
        return repr(chr(code))
    except (ValueError, OverflowError):
        return f"<{code}>"


def describe_modifiers(value):
    bits = (value or 1) - 1
    return "+".join(name for bit, name in MODIFIERS if bits & bit) or "none"


def split(field):
    return [int(part) if part else None for part in field.split(":")]


def decode_csi(body, final):
    """One CSI key report, described; None when it is not one."""
    if body[:1] in ("?", "<", ">", "="):
        return None
    fields = body.split(";") if body else [""]
    try:
        parsed = [split(field) for field in fields]
    except ValueError:
        return None
    mods = parsed[1] if len(parsed) > 1 else []
    modifiers = describe_modifiers(mods[0] if mods else None)
    event_type = mods[1] if len(mods) > 1 and mods[1] else 1
    event = EVENTS.get(event_type, f"<{event_type}>")
    if final == "u":
        keys = parsed[0]
        code = keys[0] or 0
        out = f"key={key_name(code)}"
        if len(keys) > 1 and keys[1]:
            out += f" shifted={key_name(keys[1])}"
        if len(keys) > 2 and keys[2]:
            out += f" base={key_name(keys[2])}"
        if len(parsed) > 2:
            try:
                out += " text=" + repr("".join(chr(c) for c in parsed[2] if c))
            except (ValueError, OverflowError):
                out += " text=<invalid>"
    elif final == "~":
        number = parsed[0][0]
        out = f"key={TILDES.get(number, f'~{number}')}"
    elif final in LETTERS:
        out = f"key={LETTERS[final]}"
    else:
        return None
    return f"{out} mods={modifiers} event={event}"


def decode(data):
    """Describes each piece of one read."""
    pieces, index = [], 0
    text = data.decode("utf-8", errors="replace")
    pattern = re.compile(r"\x1b\[([0-9:;?<>=]*)([A-Za-z~])|\x1bO([A-Za-z])|\x1b(.)?|(.)", re.S)
    for match in pattern.finditer(text):
        if match.group(2):
            described = decode_csi(match.group(1), match.group(2))
            pieces.append(described or f"CSI {match.group(1)}{match.group(2)} (not a key report)")
        elif match.group(3):
            pieces.append(f"legacy SS3 {match.group(3)}")
        elif match.group(0).startswith("\x1b"):
            pieces.append(f"legacy ESC {render(match.group(4).encode()) if match.group(4) else '(alone)'}")
        else:
            char = match.group(5)
            pieces.append(f"legacy byte {render(char.encode())}" if ord(char) < 0x20 or ord(char) == 0x7F
                          else f"plain text {char!r}")
    return pieces


def is_ctrl_c(data):
    return data == b"\x03" or re.search(rb"\x1b\[99;5(:1)?u", data) is not None


def main():
    use_alt = os.environ.get("PROBE_ALT") == "1"
    out_path = os.environ.get("PROBE_OUT", "keyboard_events_probe.log")
    log = open(out_path, "a", buffering=1)
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    pushed = False

    def restore(*_):
        if pushed:
            os.write(fd, b"\x1b[<u")
        if use_alt:
            os.write(fd, b"\x1b[?1049l")
        termios.tcsetattr(fd, termios.TCSADRAIN, old)

    def on_term(*_):
        restore()
        sys.exit(1)

    signal.signal(signal.SIGTERM, on_term)
    tty.setraw(fd)
    try:
        if use_alt:
            os.write(fd, b"\x1b[?1049h\x1b[H\x1b[2J")
        os.write(fd, b"\x1b[>%du" % REQUESTED)
        pushed = True
        os.write(fd, b"\x1b[?u\x1b[c")
        reply = b""
        while select.select([fd], [], [], 1.5)[0]:
            reply += os.read(fd, 4096)
            if re.search(rb"\x1b\[\?[0-9;]*c", reply):
                break
        env = {k: os.environ.get(k) for k in ("TERM", "TERM_PROGRAM", "TERM_PROGRAM_VERSION")}
        log.write(f"--- start {time.strftime('%Y-%m-%d %H:%M:%S')} {env} "
                  f"screen={'alternate' if use_alt else 'primary'} pushed={REQUESTED} "
                  f"reply={render(reply)} ---\n")
        os.write(fd, f"pushed {REQUESTED}; terminal says: {render(reply)}\r\n"
                     f"press keys; Ctrl-C ends (log: {os.path.abspath(out_path)})\r\n".encode())
        last = time.time()
        while time.time() - last < IDLE_LIMIT:
            if not select.select([fd], [], [], 1.0)[0]:
                continue
            data = os.read(fd, 4096)
            if not data:
                break
            last = time.time()
            pieces = decode(data)
            log.write(f"{render(data)}\n")
            for piece in pieces:
                log.write(f"    {piece}\n")
                os.write(fd, f"{piece}\r\n".encode())
            if is_ctrl_c(data):
                break
    finally:
        restore()
        log.write("--- end ---\n")
        log.close()


if __name__ == "__main__":
    main()
