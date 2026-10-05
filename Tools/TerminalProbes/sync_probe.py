#!/usr/bin/env python3
"""Synchronized output (DEC mode 2026) probe: is the pair TUIkit wraps a
multi-row frame in harmless here, does the terminal say it implements the
mode, and how long does it hold a display nobody lets go of?

TUIkit sends `CSI ? 2026 h` before a frame that writes more than one row and
`CSI ? 2026 l` after it, to every host, without asking (see
`Terminal.beginSynchronizedUpdate()` and Documentation/Terminal-compatibility.md,
"Synchronized output (mode 2026)"). This measures what that rests on.

Run INSIDE the terminal under test; nothing here needs TUIkit built.

  python3 sync_probe.py                 # the leak check and the mode survey
  python3 sync_probe.py --hold-timeout  # ...then a hold left open, by eye

Writes JSON to $PROBE_OUT (default ./sync_probe.json) and prints a summary.
`PROBE_ALT=1` runs on the alternate screen, where TUIkit draws.

1. **Leak.** The cursor column (DSR 6, `CSI 6 n`) before and after the pair,
   with nothing between them. A column that moved means the terminal printed
   part of a sequence it should have consumed: the method that found Apple
   Terminal's `?`-plus-intermediate leak (Terminal-compatibility.md, "Asking
   the terminal — Device Attributes"). Expected clean everywhere: the shape is
   a `?` and no intermediate.

2. **Survey.** DECRQM `CSI ? 2026 $ p`, fenced by `CSI 5 n`. DECRQM is the one
   shape Apple Terminal prints (its final `p` lands on the screen), so it is
   asked only of a host that identifies itself: one whose `TERM_PROGRAM` names
   a host other than Apple Terminal, or that answers XTVERSION (`CSI > 0 q`),
   which Apple Terminal never does. Under tmux the answer is tmux's, about the
   pane, which says nothing of whether the outer terminal is held.
   Answers: 0 not recognised, 1 set, 2 reset, 3 permanently set,
   4 permanently reset.

3. **Hold timeout** (`--hold-timeout`, by eye or by screen recording). Sends
   the begin marker and never the end, then rewrites one line with the time
   since the marker every 50 ms for 8 seconds. A terminal that holds forever
   shows the line only when the probe lets go at the end (`--hold-timeout`
   always does). One with a timeout shows it frozen at its first value, then
   jumping: the first value seen is the timeout. Ghostty's source says 1000 ms
   (`sync_reset_ms`). A terminal that ignores the mode shows it counting from
   0. Record what you see in the JSON's `hold_timeout_observed_ms` by hand.

tmux is recorded (`$TMUX`, `tmux -V`). Run it once in a tmux 3.7c pane inside
Ghostty and inside iTerm2 too: whether tmux carries a pane's hold to its
client is the open question, and only the hold-timeout run, watched, says.
"""
import json, os, re, select, subprocess, sys, termios, time, tty

import probe_stamp

TIMEOUT = 1.0
BEGIN = b"\x1b[?2026h"
END = b"\x1b[?2026l"
STATUS_FENCE = b"\x1b[5n"
STATUS_REPLY = re.compile(rb"\x1b\[0n")

# Hosts that name themselves in TERM_PROGRAM and are known to swallow DECRQM.
_DECRQM_SAFE_TERM_PROGRAMS = {"iTerm.app", "ghostty", "WarpTerminal", "tmux", "WezTerm", "vscode"}


def read_until(fd, pattern, timeout=TIMEOUT):
    """Bytes read until `pattern` matches, or the timeout passes."""
    buf = b""
    deadline = time.monotonic() + timeout
    while not pattern.search(buf):
        left = deadline - time.monotonic()
        if left <= 0 or not select.select([fd], [], [], left)[0]:
            break
        buf += os.read(fd, 4096)
    return buf


def cursor(fd):
    """(row, column) from DSR 6, or None."""
    os.write(fd, b"\x1b[6n")
    got = read_until(fd, re.compile(rb"\x1b\[(\d+);(\d+)R"))
    match = re.search(rb"\x1b\[(\d+);(\d+)R", got)
    return (int(match.group(1)), int(match.group(2))) if match else None


def leak_check(fd):
    os.write(fd, b"\r\n")
    before = cursor(fd)
    os.write(fd, BEGIN + END)
    after = cursor(fd)
    return {
        "before": before, "after": after,
        "clean": before is not None and before == after,
    }


def xtversion(fd):
    os.write(fd, b"\x1b[>0q" + STATUS_FENCE)
    got = read_until(fd, STATUS_REPLY)
    match = re.search(rb"\x1bP>\|(.*?)\x1b\\", got)
    return match.group(1).decode("utf-8", "replace") if match else None


def decrqm(fd, mode):
    os.write(fd, b"\x1b[?%d$p" % mode + STATUS_FENCE)
    got = read_until(fd, STATUS_REPLY)
    match = re.search(rb"\x1b\[\?%d;(\d+)\$y" % mode, got)
    if not match:
        return None
    value = int(match.group(1))
    return {0: "not recognised", 1: "set", 2: "reset",
            3: "permanently set", 4: "permanently reset"}.get(value, value)


def tmux_version():
    if not os.environ.get("TMUX"):
        return None
    try:
        return subprocess.run(["tmux", "-V"], capture_output=True, text=True,
                              timeout=5).stdout.strip() or None
    except Exception:
        return None


def hold_timeout(fd, seconds=8.0):
    """Begin a hold, never end it, and count; let go at the end."""
    os.write(fd, b"\x1b[2J\x1b[H" + b"Watch the counter below. The first value you see is the hold's timeout.\r\n")
    os.write(fd, BEGIN)
    start = time.monotonic()
    while (elapsed := time.monotonic() - start) < seconds:
        os.write(fd, b"\x1b[3;1H\x1b[2K%6d ms since the hold began" % int(elapsed * 1000))
        time.sleep(0.05)
    os.write(fd, END + b"\x1b[5;1HLet go (end marker sent). Note the first value you saw.\r\n")


def main():
    use_alt = os.environ.get("PROBE_ALT") == "1"
    out_path = os.environ.get("PROBE_OUT", "sync_probe.json")
    want_hold = "--hold-timeout" in sys.argv[1:]
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    tty.setraw(fd)
    result = {}
    try:
        if use_alt:
            os.write(fd, b"\x1b[?1049h")
        result["stamp"] = probe_stamp.stamp(fd, "sync_probe", use_alt)
        result["leak"] = leak_check(fd)
        version = xtversion(fd)
        result["xtversion"] = version
        program = os.environ.get("TERM_PROGRAM")
        identified = version is not None or program in _DECRQM_SAFE_TERM_PROGRAMS
        if program == "Apple_Terminal":
            identified = False
        result["decrqm_2026"] = decrqm(fd, 2026) if identified else (
            "not asked (Apple Terminal, or a host that did not identify itself, "
            "may print DECRQM's final byte)")
        result["tmux"] = tmux_version()
        if want_hold:
            hold_timeout(fd)
            result["hold_timeout_observed_ms"] = "fill in by hand: the first counter value seen"
    finally:
        # Let go, whatever happened: a probe must not leave the display held.
        os.write(fd, END)
        if use_alt:
            os.write(fd, b"\x1b[?1049l")
        termios.tcsetattr(fd, termios.TCSADRAIN, old)

    with open(out_path, "w") as handle:
        json.dump(result, handle, indent=1, ensure_ascii=False)
    env = result["stamp"]["env"]
    print(f"{env.get('TERM_PROGRAM', '?')} {env.get('TERM_PROGRAM_VERSION', '')} "
          f"on the {'alternate' if use_alt else 'primary'} screen")
    leak = result["leak"]
    print(f"  ?2026h ?2026l printed nothing: {leak['clean']} "
          f"(cursor {leak['before']} -> {leak['after']})")
    print(f"  XTVERSION: {result['xtversion'] or '(silent)'}")
    print(f"  DECRQM ?2026: {result['decrqm_2026']}")
    if result["tmux"]:
        print(f"  inside {result['tmux']}: the answer above is the pane's, not the outer terminal's")
    print(f"  written to {os.path.abspath(out_path)}")


if __name__ == "__main__":
    main()
