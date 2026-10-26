#!/usr/bin/env python3
"""Window-title probe: does this terminal take an application's window title
(OSC 2), keep a stack of titles (XTWINOPS 22 and 23, push and pop), report the
title back (XTWINOPS 21), and swallow every one of those sequences without
printing any of it?

TUI titles the terminal's window with the window in front's title
(`TerminalHostState`, refusal review P15): `ESC ] 2 ; title ESC \\` on a
change, the terminal's own title pushed with `CSI 22 ; 2 t` before the first,
and popped with `CSI 23 ; 2 t` on suspend, on exit and for a window with no
title. See Documentation/Terminals/Terminal compatibility survey.md, "The window
title". This measures what that rests on.

Run INSIDE the terminal under test. Nothing here needs TUI built.

  python3 title_probe.py            # measure, then put the title back
  python3 title_probe.py --hold 20  # ...and hold the probe's title up for 20 s
                                    #    first, to look at the tab and window

Writes JSON to $PROBE_OUT (default ./title_probe.json) and prints a summary.

1. **Leak.** The cursor column (DSR 6) before and after each sequence TUI
   sends — OSC 2 with ST and with BEL, the push, the pop, a pop with nothing
   pushed — and the report request, on the primary and the alternate screen
   (TUI's). A column that moved means the host printed part of it.

2. **Report.** `CSI 21 t`, fenced by `CSI 5 n` (every measured host answers
   DSR 5): the title as the host reports it, `OSC l title ST`, or nothing.
   Ghostty answers only with `title-report = true`; iTerm2 has a setting for
   it; a host that does not answer leaves steps 3 and 4 to the eye (`--hold`).
   Inside tmux, which answers none, the pane's title as tmux keeps it
   (`#{pane_title}`) stands in, prefixed `tmux pane_title:`.

3. **Set.** OSC 2 with a fresh nonce, then the report: whether the title is
   the window's, as reported.

4. **Stack.** The terminal's own title pushed first (so the run can put it
   back), a title set, pushed, another set, then popped: whether the first
   comes back. Last, the push from the start popped, which restores the
   terminal's own title on a host that keeps the stack — and then a pop with
   nothing pushed, for its leak. A host with no stack is left showing one of
   the probe's titles, until the shell's prompt sets its own.

What no sequence reports — whether the TAB shows the window title or the icon
name (OSC 1), and what tmux passes on to the outer terminal — is for `--hold`
and a look.
"""
import json, os, re, select, socket, subprocess, sys, termios, time, tty

import probe_stamp

ST = "\x1b\\"
BEL = "\x07"
PUSH = "\x1b[22;2t"
POP = "\x1b[23;2t"
REPORT = "\x1b[21t"


def set_title(title, terminator=ST):
    return f"\x1b]2;{title}{terminator}"


def cursor_column(fd):
    """DSR (`ESC[6n`) — the column the cursor is in, 1-based, or None."""
    os.write(fd, b"\x1b[6n")
    got = b""
    while select.select([fd], [], [], 1.5)[0]:
        got += os.read(fd, 1024)
        if got.endswith(b"R"):
            break
    else:
        return None
    try:
        body = got[got.rfind(b"\x1b[") + 2:-1]
        return int(body.split(b";")[1])
    except (IndexError, ValueError):
        return None


def reported_title(fd):
    """The title `CSI 21 t` reports, '' for an empty one, or None for no answer."""
    os.write(fd, (REPORT + "\x1b[5n").encode())
    got = b""
    deadline = time.time() + 2.0
    while time.time() < deadline and select.select([fd], [], [], 0.5)[0]:
        got += os.read(fd, 4096)
        if b"\x1b[0n" in got:
            break
    match = re.search(rb"\x1b\]l(.*?)(?:\x1b\\|\x07)", got, re.S)
    if match:
        return match.group(1).decode("utf-8", "replace")
    if os.environ.get("TMUX"):
        # tmux answers no report, but says what it made of the title: the
        # pane's, once the fence above shows it has read everything before.
        pane = subprocess.run(["tmux", "display-message", "-p", "#{pane_title}"],
                              capture_output=True, text=True)
        return f"tmux pane_title: {pane.stdout.strip()}" if pane.returncode == 0 else None
    return None


LEAK_ROWS = [
    ("osc2_st", set_title("tuikit-leak", ST), "OSC 2 ended by ST, as TUI sends it"),
    ("osc2_bel", set_title("tuikit-leak", BEL), "OSC 2 ended by BEL"),
    ("push", PUSH, "XTWINOPS 22;2: push the window title"),
    ("pop", POP, "XTWINOPS 23;2: pop it"),
    ("report", REPORT, "XTWINOPS 21: report the title (its answer read and dropped)"),
]


def leaks(fd, use_alt, rows=LEAK_ROWS):
    """Each sequence on a fresh row, and whether the cursor moved."""
    results = {}
    if use_alt:
        os.write(fd, b"\x1b[?1049h")
    for name, sequence, what in rows:
        os.write(fd, b"\r\x1b[2KAB")
        os.write(fd, sequence.encode())
        if name == "report":
            os.write(fd, b"\x1b[5n")
            got = b""
            while select.select([fd], [], [], 1.0)[0]:
                got += os.read(fd, 4096)
                if b"\x1b[0n" in got:
                    break
        column = cursor_column(fd)
        results[name] = {
            "what": what,
            "measured_column": column,
            "swallowed": None if column is None else column == 3,
            "bytes": sequence.replace("\x1b", "<ESC>").replace("\x07", "<BEL>"),
        }
    os.write(fd, b"\r\x1b[2K")
    if use_alt:
        os.write(fd, b"\x1b[?1049l")
    return results


def stack(fd, steps):
    """Set, push, set, pop: what the report says at each step."""
    nonce = f"{os.getpid()}-{int(time.time())}"
    first, second = f"tuikit-probe-A-{nonce}", f"tuikit-probe-B-{nonce}"
    os.write(fd, set_title(first).encode())
    steps["after_set"] = reported_title(fd)
    os.write(fd, PUSH.encode())
    os.write(fd, set_title(second).encode())
    steps["after_push_and_set"] = reported_title(fd)
    os.write(fd, POP.encode())
    steps["after_pop"] = reported_title(fd)
    return first, second


def main():
    hold = 0
    if "--hold" in sys.argv:
        hold = int(sys.argv[sys.argv.index("--hold") + 1])
    out_path = os.environ.get("PROBE_OUT", "title_probe.json")
    fd = sys.stdin.fileno()
    if not os.isatty(fd):
        sys.exit("title_probe: stdin is not a terminal — run this IN the terminal under test")

    old = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)
        stamp = probe_stamp.stamp(fd, "title_probe", use_alt=False)
        steps = {"before": reported_title(fd)}
        os.write(fd, PUSH.encode())                 # the terminal's own, put back at the end
        first, second = stack(fd, steps)
        leak = {"primary": leaks(fd, use_alt=False), "alternate": leaks(fd, use_alt=True)}
        if hold:
            os.write(fd, set_title(first).encode())
            time.sleep(hold)
        os.write(fd, POP.encode())                  # the terminal's own back
        steps["after_final_pop"] = reported_title(fd)
        # A pop with nothing pushed, last, where it cannot cost the run the
        # terminal's own title.
        leak["primary"].update(
            leaks(fd, use_alt=False, rows=[("pop_empty", POP, "a pop with nothing pushed")]))
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)

    answers = steps["after_set"] is not None

    def shows(title, wanted):
        return title is not None and title.endswith(wanted)

    verdict = {
        "reports_title": answers,
        "takes_osc2": None if not answers else shows(steps["after_set"], first),
        "keeps_stack": None if not answers else shows(steps["after_pop"], first),
        "restores_own": None if not answers or steps["before"] is None
        else steps["after_final_pop"] == steps["before"],
    }
    # A terminal's own title is often the machine's name (tmux's pane title
    # is, by default): kept out of a record that may be published.
    host = socket.gethostname()
    steps = {name: None if title is None else title.replace(host, "<hostname>")
             for name, title in steps.items()}
    record = dict(stamp)
    record.update({"leaks": leak, "titles": {"first": first, "second": second}, "steps": steps,
                   "verdict": verdict})
    with open(out_path, "w") as f:
        json.dump(record, f, indent=2, ensure_ascii=False)

    for screen, results in leak.items():
        print(f"\r\n  {screen} screen\r")
        for name, result in results.items():
            column = result["measured_column"]
            state = ("no DSR answer" if column is None else "swallowed" if result["swallowed"]
                     else f"PRINTED — {column - 3} stray cells")
            print(f"  {name:<10} {state}\r")
    print("\r\n  reports:\r")
    for name, title in steps.items():
        print(f"  {name:<20} {title!r}\r")
    print(f"\r\n  verdict: {verdict}\r")


if __name__ == "__main__":
    main()
