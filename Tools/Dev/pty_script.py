#!/usr/bin/env python3
"""Run a TUI program in this terminal, and feed it scripted clicks and keys.

    Tools/Dev/pty_script.py [--wait 3] [--step 0.4] EVENTS -- PROGRAM [ARGS...]

EVENTS is a ';'-separated list, sent one per --step seconds after --wait:
    COL,ROW          a left click at that cell (1-based), as SGR mouse reports
    f6, tab, stab, enter, esc, up, down, left, right
    x:HEX            any bytes, in hex (x:1b5b31377e is F6)

The program's output goes to this terminal unchanged, so the terminal draws it, and what you type
still reaches it. It exists for checking a change in a real terminal when you can see the window
but not type into it, or click into it: an automation tier that allows screenshots but not keys,
or background clicks, which macOS hands to the terminal as a text selection rather than as a
mouse report. Put it in a `.command` file and `open -a Terminal` (or iTerm, Warp) that file; see
Tools/Dev/README.md, "Seeing it in a real terminal".
"""
import fcntl, os, pty, select, sys, termios, time, tty

KEYS = {"f6": "1b5b31377e", "tab": "09", "stab": "1b5b5a", "enter": "0d", "esc": "1b",
        "up": "1b5b41", "down": "1b5b42", "right": "1b5b43", "left": "1b5b44"}


def encode(event):
    if "," in event:
        col, row = event.split(",")
        return f"\x1b[<0;{col};{row}M\x1b[<0;{col};{row}m".encode()
    return bytes.fromhex(event[2:] if event.startswith("x:") else KEYS[event])


def main(argv):
    wait, step = 3.0, 0.4
    while argv and argv[0] in ("--wait", "--step"):
        if argv[0] == "--wait":
            wait = float(argv[1])
        else:
            step = float(argv[1])
        argv = argv[2:]
    if len(argv) < 3 or argv[1] != "--":
        sys.exit(__doc__)
    events = [encode(e) for e in argv[0].split(";") if e]
    pid, fd = pty.fork()
    if pid == 0:
        os.execvp(argv[2], argv[2:])
    fcntl.ioctl(fd, termios.TIOCSWINSZ, fcntl.ioctl(0, termios.TIOCGWINSZ, b"\0" * 8))
    saved = termios.tcgetattr(0)
    tty.setraw(0)
    due = time.monotonic() + wait
    try:
        while True:
            if events and time.monotonic() >= due:
                os.write(fd, events.pop(0))
                due += step
            ready, _, _ = select.select([fd, 0], [], [], 0.05)
            if fd in ready:
                try:
                    data = os.read(fd, 65536)
                except OSError:
                    break
                if not data:
                    break
                os.write(1, data)
            if 0 in ready:
                os.write(fd, os.read(0, 1024))
    finally:
        termios.tcsetattr(0, termios.TCSADRAIN, saved)


if __name__ == "__main__":
    main(sys.argv[1:])
