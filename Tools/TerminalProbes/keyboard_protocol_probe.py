#!/usr/bin/env python3
"""Kitty keyboard protocol SUPPORT probe: does this terminal answer, and which
of the flags TUIkit pushes does it take?

TUIkit asks every terminal but Apple Terminal at startup (see
`Terminal+KeyboardProtocol.swift`), and this asks the same questions the same
way, so its answer is what TUIkit would have been told:

1. `CSI ? u` (the current flags), fenced by `CSI c` (Primary Device
   Attributes). A DA1 answer with no `CSI ? flags u` before it means the
   terminal does not speak the protocol — the specification's own detection.
2. If it answered: push `CSI > 31 u` (all five enhancements, TUIkit's
   request), ask again, pop with `CSI < u`, ask a third time. The second answer
   is the flags the terminal took; the third should equal the first.

Pushed and popped on the PRIMARY screen unless `PROBE_ALT=1`, which does it
on the alternate screen, as TUIkit does: the specification keeps a stack per
screen, and a terminal could get one of them wrong.

Run INSIDE the terminal under test. Writes JSON to $PROBE_OUT (default
./keyboard_protocol_probe.json) and prints a one-screen summary. Safe on Apple
Terminal: `CSI ? u` has a `?` and no intermediate byte, the shape measured clean
there (Documentation/Terminal-compatibility.md, "Asking the terminal — Device
Attributes"); it is expected to answer only the fence.
"""
import json, os, re, select, sys, termios, tty

import probe_stamp

TIMEOUT = 1.5
QUERY = b"\x1b[?u\x1b[c"
REQUESTED = 31


def ask(fd):
    """Send the query and its fence; return (flags or None, raw bytes)."""
    os.write(fd, QUERY)
    buf = b""
    while select.select([fd], [], [], TIMEOUT)[0]:
        buf += os.read(fd, 4096)
        if re.search(rb"\x1b\[\?[0-9;]*c", buf):
            break
    match = re.search(rb"\x1b\[\?([0-9]+)u", buf)
    return (int(match.group(1)) if match else None), buf


def render(raw):
    return "".join(
        "<ESC>" if b == 0x1B else (f"<{b:02X}>" if b < 0x20 or b == 0x7F else chr(b)) for b in raw)


def names(flags):
    if flags is None:
        return "—"
    parts = [name for bit, name in [
        (1, "disambiguate"), (2, "event types"), (4, "alternate keys"),
        (8, "all keys as escapes"), (16, "associated text")] if flags & bit]
    return f"{flags} ({', '.join(parts) or 'none'})"


def main():
    use_alt = os.environ.get("PROBE_ALT") == "1"
    out_path = os.environ.get("PROBE_OUT", "keyboard_protocol_probe.json")
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    tty.setraw(fd)
    result = {}
    try:
        if use_alt:
            os.write(fd, b"\x1b[?1049h")
        result["stamp"] = probe_stamp.stamp(fd, "keyboard_protocol_probe", use_alt)
        before, raw = ask(fd)
        result["before"] = {"flags": before, "raw": render(raw)}
        result["speaks_protocol"] = before is not None
        if before is not None:
            os.write(fd, b"\x1b[>%du" % REQUESTED)
            pushed, raw = ask(fd)
            result["after_push"] = {"requested": REQUESTED, "flags": pushed, "raw": render(raw)}
            os.write(fd, b"\x1b[<u")
            popped, raw = ask(fd)
            result["after_pop"] = {"flags": popped, "raw": render(raw)}
    finally:
        if use_alt:
            os.write(fd, b"\x1b[?1049l")
        termios.tcsetattr(fd, termios.TCSADRAIN, old)

    with open(out_path, "w") as handle:
        json.dump(result, handle, indent=1, ensure_ascii=False)
    env = result["stamp"]["env"]
    print(f"{env.get('TERM_PROGRAM', '?')} {env.get('TERM_PROGRAM_VERSION', '')} "
          f"on the {'alternate' if use_alt else 'primary'} screen")
    print(f"  speaks the kitty keyboard protocol: {result['speaks_protocol']}")
    print(f"  flags before:      {names(result['before']['flags'])}")
    if result["speaks_protocol"]:
        print(f"  after pushing 31:  {names(result['after_push']['flags'])}")
        print(f"  after the pop:     {names(result['after_pop']['flags'])}")
    print(f"  written to {os.path.abspath(out_path)}")


if __name__ == "__main__":
    main()
