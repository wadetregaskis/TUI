#!/usr/bin/env python3
"""Progress and attention probe: does this terminal take an application's
progress report (OSC 9;4, ConEmu's), swallow every spelling TUI sends
without printing any of it, and — opt-in — post a desktop notification
(OSC 9)? And what does tmux pass on to the terminal it is drawn in?

TUI sends these (`TerminalHostState`; the Ghostty adoption study, C3 and
C6), only to a host documented to take them:

    ESC ] 9 ; 4 ; 1 ; <0-100> ESC \\    a value
    ESC ] 9 ; 4 ; 2 [; <0-100>] ESC \\  an error, with its value or without
    ESC ] 9 ; 4 ; 3 ESC \\              indeterminate
    ESC ] 9 ; 4 ; 4 [; <0-100>] ESC \\  paused, with its value or without
    ESC ] 9 ; 4 ; 0 ESC \\              no bar: on suspend, on exit, on a fatal signal
    ESC ] 9 ; <message> ESC \\          a notification
    BEL                                 attention, where no notification is taken

The bar is sent again every 5 s while it is shown, because Ghostty takes a bar
not updated for about 15 s for one its program left behind. See
Documentation/Terminals/Terminal compatibility survey.md, "Progress and
attention". This measures what that rests on.

Run INSIDE the terminal under test. Nothing here needs TUI built.

  python3 progress_probe.py                # measure; leaves no bar up
  python3 progress_probe.py --hold 20      # ...and hold a 50% bar up for 20 s
                                           #    first, to look at the tab
  python3 progress_probe.py --timeout 20   # set 50%, send nothing for 20 s,
                                           #    and see whether the bar is kept
  python3 progress_probe.py --notify       # also post ONE notification (OSC 9)
  python3 progress_probe.py --tmux-forwarding
                                           # run OUTSIDE tmux: what tmux sends
                                           #    its client (no terminal needed)

Writes JSON to $PROBE_OUT (default ./progress_probe.json) and prints a summary.

1. **Leak.** The cursor column (DSR 6) before and after each spelling above, on
   the primary and the alternate screen (TUI's). A column that moved means
   the host printed part of it. The notification's row only with `--notify`:
   on a host that takes it, it posts one, and a host may first ask the user
   whether it may.

2. **tmux's bar.** Inside tmux, which keeps a bar for each pane and reports it
   (`#{pane_pb_state}`, `#{pane_pb_progress}`, "can be set by application"),
   the bar tmux made of each spelling: whether it parses TUI's, the
   value-less ones included.

3. **Timeout** (`--timeout S`). A 50% bar, then nothing for S seconds: inside
   tmux, whether its bar is still there; elsewhere, for the eye (`--hold`'s
   look, at the end of the wait).

4. **What tmux passes on** (`--tmux-forwarding`, run outside tmux). This script
   plays the terminal: it runs a tmux of its own in a pseudo-terminal, as a
   client whose terminal has the `progressbar` feature (`tmux -T progressbar`)
   and as one without, runs itself in the pane with `--emit` to send every
   sequence above — the first one twice, as TUI sends a bar again to keep
   it up — and records what reached the client, and the features tmux lists
   for it (`#{client_termfeatures}`, which is how an app asks tmux whether a
   client draws a bar). Then a client with the feature attaches to a pane
   that put a bar up before it was there (`--emit-hold`): whether tmux hands
   it the bar it keeps.

What no sequence reports — whether the host draws the bar, and where, and
whether a notification appears — is for `--hold` and a look.
"""
import json, os, pty, re, select, struct, subprocess, sys, termios, time, tty, fcntl

import probe_stamp

ST = "\x1b\\"
BEL = "\x07"


def progress(state, value=None):
    """`ESC ] 9 ; 4 ; state [; value] ST`, as TUI spells it."""
    return f"\x1b]9;4;{state}" + ("" if value is None else f";{value}") + ST


def notification(message):
    """`ESC ] 9 ; message ST`, as TUI spells it."""
    return f"\x1b]9;{message}{ST}"


# (name, bytes, what, tmux's state and progress after it)
SPELLINGS = [
    ("value_50", progress(1, 50), "a value, 50%", ("normal", "50")),
    ("value_0", progress(1, 0), "a value, 0%", ("normal", "0")),
    ("value_100", progress(1, 100), "a value, 100%", ("normal", "100")),
    ("error_30", progress(2, 30), "an error at 30%", ("error", "30")),
    ("error_bare", progress(2), "an error, no value", ("error", None)),
    ("indeterminate", progress(3), "indeterminate", ("indeterminate", None)),
    ("paused_70", progress(4, 70), "paused at 70%", ("paused", "70")),
    ("paused_bare", progress(4), "paused, no value", ("paused", None)),
    ("none", progress(0), "no bar", ("hidden", None)),
]

NOTIFY_ROW = ("notify", notification(" tuikit progress_probe"), "a notification (OSC 9)", None)


def printable(sequence):
    return sequence.replace("\x1b", "<ESC>").replace("\x07", "<BEL>")


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


def tmux_bar():
    """The pane's bar as tmux keeps it — (state, progress) — or None outside tmux."""
    if not os.environ.get("TMUX"):
        return None
    shown = subprocess.run(
        ["tmux", "display-message", "-p", "#{pane_pb_state} #{pane_pb_progress}"],
        capture_output=True, text=True)
    if shown.returncode != 0:
        return None
    parts = shown.stdout.split()
    return (parts[0] if parts else "", parts[1] if len(parts) > 1 else None)


def leaks(fd, use_alt, rows):
    """Each sequence on a fresh row: whether the cursor moved, and tmux's bar after it."""
    results = {}
    if use_alt:
        os.write(fd, b"\x1b[?1049h")
    for name, sequence, what, expected in rows:
        os.write(fd, b"\r\x1b[2KAB")
        os.write(fd, sequence.encode())
        column = cursor_column(fd)
        result = {
            "what": what,
            "measured_column": column,
            "swallowed": None if column is None else column == 3,
            "bytes": printable(sequence),
        }
        bar = tmux_bar()
        if bar is not None:
            result["tmux_bar"] = {"state": bar[0], "progress": bar[1]}
            if expected is not None:
                state, value = expected
                result["tmux_parsed"] = bar[0] == state and (value is None or bar[1] == value)
        results[name] = result
    os.write(fd, (b"\r\x1b[2K" + progress(0).encode()))
    if use_alt:
        os.write(fd, b"\x1b[?1049l")
    return results


def timeout(fd, seconds):
    """A 50% bar, then nothing for `seconds`: tmux's bar before and after."""
    os.write(fd, progress(1, 50).encode())
    before = tmux_bar()
    time.sleep(seconds)
    after = tmux_bar()
    os.write(fd, progress(0).encode())
    return {
        "seconds": seconds,
        "tmux_bar_before": None if before is None else {"state": before[0], "progress": before[1]},
        "tmux_bar_after": None if after is None else {"state": after[0], "progress": after[1]},
    }


# --- What tmux passes on -----------------------------------------------------

EMIT_STEPS = [
    ("value_50", progress(1, 50)),
    # The same report again, as TUI's keep-alive sends it: does tmux pass a
    # repeat on, or only a change?
    ("value_50_again", progress(1, 50)),
    ("indeterminate", progress(3)),
    ("error_bare", progress(2)),
    ("paused_70", progress(4, 70)),
    ("none", progress(0)),
    ("notify", notification(" tuikit progress_probe")),
    ("bell", BEL),
]


def emit():
    """`--emit`: the pane's side of `--tmux-forwarding`. Each step, a pause, then out."""
    time.sleep(0.8)
    for name, sequence in EMIT_STEPS:
        os.write(1, sequence.encode())
        # A whole second before the repeat, as far apart as tmux's redraws
        # could want: a repeat it drops is not one it merged with the first.
        time.sleep(1.0 if name == "value_50" else 0.3)
    time.sleep(0.8)


def emit_hold():
    """`--emit-hold`: the pane's side of the late attach. A 50% bar, then a wait
    for a client to attach and be handed it."""
    os.write(1, progress(1, 50).encode())
    time.sleep(4)


PROGRESS_PATTERN = r"\x1b\]9;4;[^\x1b\x07]*(?:\x1b\\|\x07)"


def tmux_command(socket_name):
    """tmux on a server of the probe's own, with no configuration read."""
    return ["tmux", "-L", socket_name, "-f", "/dev/null"]


def tmux_environment():
    """The environment a tmux of the probe's own runs in: no TMUX, and a TERM
    tmux knows, so nothing of the terminal the probe runs in reaches it."""
    environment = {key: value for key, value in os.environ.items() if not key.startswith("TMUX")}
    environment["TERM"] = "xterm-256color"
    return environment


def run_client(socket_name, arguments, seconds, on_attached=None):
    """A tmux client of a pty we read, running `arguments`, for up to `seconds`
    or until it ends; `on_attached`, if given, is called once, half a second
    in, and its answer returned with what the client received."""
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
    child = subprocess.Popen(tmux_command(socket_name) + arguments, stdin=slave, stdout=slave, stderr=slave,
                             env=tmux_environment(), start_new_session=True)
    os.close(slave)
    received = b""
    asked = None
    start = time.time()
    try:
        while time.time() < start + seconds:
            if on_attached is not None and asked is None and time.time() > start + 0.5:
                asked = on_attached()
            if select.select([master], [], [], 0.1)[0]:
                try:
                    chunk = os.read(master, 65536)
                except OSError:
                    break
                if not chunk:
                    break
                received += chunk
            elif child.poll() is not None:
                break
    finally:
        subprocess.run(tmux_command(socket_name) + ["kill-server"], capture_output=True)
        if child.poll() is None:
            child.kill()
        child.wait()
        os.close(master)
    return received.decode("utf-8", "replace"), asked


def tmux_forwarding_run(features):
    """Run a tmux of our own as a client of a pty we read, with `features`
    (`-T`) or none, the pane running `--emit`; returns what the client got,
    and the features tmux lists for the client."""
    socket_name = f"tuikit-progress-{os.getpid()}-{'pb' if features else 'none'}"
    arguments = (["-T", features] if features else []) + [
        "new-session", "-x", "80", "-y", "24", f"{sys.executable} {os.path.abspath(__file__)} --emit"]

    def listed_features():
        listed = subprocess.run(tmux_command(socket_name) + ["list-clients", "-F", "#{client_termfeatures}"],
                                capture_output=True, text=True, env=tmux_environment())
        return listed.stdout.strip()

    text, client_termfeatures = run_client(socket_name, arguments, 15, on_attached=listed_features)
    progress_sequences = re.findall(PROGRESS_PATTERN, text)
    return {
        "client_features": features or "(none given)",
        "client_termfeatures": client_termfeatures,
        "progress_sequences": [printable(match) for match in progress_sequences],
        # The pane sent `value_50` twice running; how many reached the client.
        "value_50_reports_received": progress_sequences.count(progress(1, 50)),
        "notification_sequences": [printable(match) for match in
                                   re.findall(r"\x1b\]9;(?!4;)[^\x1b\x07]*(?:\x1b\\|\x07)", text)],
        # A BEL that ends no string sequence: drop every OSC/DCS/APC first.
        "bells": re.sub(r"\x1b[\]P_][^\x07\x1b]*(?:\x07|\x1b\\)", "", text).count(BEL),
    }


def tmux_late_attach_run():
    """A pane puts a bar up with no client attached (`--emit-hold`), then a
    client with the `progressbar` feature attaches: what reaches it."""
    socket_name = f"tuikit-progress-{os.getpid()}-late"
    subprocess.run(tmux_command(socket_name) + [
        "new-session", "-d", "-x", "80", "-y", "24", f"{sys.executable} {os.path.abspath(__file__)} --emit-hold"],
        capture_output=True, env=tmux_environment())
    time.sleep(1)
    text, _ = run_client(socket_name, ["-T", "progressbar", "attach"], 2)
    return {
        "pane_sent_before_any_client": printable(progress(1, 50)),
        "client_features": "progressbar",
        "progress_sequences": [printable(match) for match in re.findall(PROGRESS_PATTERN, text)],
    }


def tmux_forwarding():
    version = subprocess.run(["tmux", "-V"], capture_output=True, text=True).stdout.strip()
    record = {
        "probe": "progress_probe --tmux-forwarding",
        "measured": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "tmux": version,
        "emitted_in_the_pane": [{"name": name, "bytes": printable(sequence)} for name, sequence in EMIT_STEPS],
        "runs": [tmux_forwarding_run("progressbar"), tmux_forwarding_run(None)],
        "late_attach": tmux_late_attach_run(),
    }
    out_path = os.environ.get("PROBE_OUT", "progress_probe_tmux_forwarding.json")
    with open(out_path, "w") as f:
        json.dump(record, f, indent=2, ensure_ascii=False)
    for run in record["runs"]:
        print(f"client features {run['client_features']} (tmux lists {run['client_termfeatures']!r}):")
        print(f"  progress  {run['progress_sequences']}")
        print(f"  a report sent twice running reached it {run['value_50_reports_received']} time(s)")
        print(f"  notify    {run['notification_sequences']}")
        print(f"  bells     {run['bells']}")
    late = record["late_attach"]
    print(f"late attach, client features progressbar:\n  progress  {late['progress_sequences']}")


# --- In the terminal under test ---------------------------------------------

def main():
    if "--emit" in sys.argv:
        emit()
        return
    if "--emit-hold" in sys.argv:
        emit_hold()
        return
    if "--tmux-forwarding" in sys.argv:
        tmux_forwarding()
        return
    hold = int(sys.argv[sys.argv.index("--hold") + 1]) if "--hold" in sys.argv else 0
    wait = int(sys.argv[sys.argv.index("--timeout") + 1]) if "--timeout" in sys.argv else 0
    rows = SPELLINGS + ([NOTIFY_ROW] if "--notify" in sys.argv else [])
    out_path = os.environ.get("PROBE_OUT", "progress_probe.json")
    fd = sys.stdin.fileno()
    if not os.isatty(fd):
        sys.exit("progress_probe: stdin is not a terminal — run this IN the terminal under test")

    old = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)
        stamp = probe_stamp.stamp(fd, "progress_probe", use_alt=False)
        leak = {"primary": leaks(fd, False, rows), "alternate": leaks(fd, True, SPELLINGS)}
        waited = timeout(fd, wait) if wait else None
        if hold:
            os.write(fd, progress(1, 50).encode())
            time.sleep(hold)
        os.write(fd, progress(0).encode())
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)

    record = dict(stamp)
    record.update({"leaks": leak, "timeout": waited, "notified": "--notify" in sys.argv})
    with open(out_path, "w") as f:
        json.dump(record, f, indent=2, ensure_ascii=False)

    for screen, results in leak.items():
        print(f"\r\n  {screen} screen\r")
        for name, result in results.items():
            column = result["measured_column"]
            state = ("no DSR answer" if column is None else "swallowed" if result["swallowed"]
                     else f"PRINTED — {column - 3} stray cells")
            bar = result.get("tmux_bar")
            tmux = "" if bar is None else f"   tmux: {bar['state']} {bar['progress'] or ''}"
            print(f"  {name:<14} {state}{tmux}\r")
    if waited:
        print(f"\r\n  timeout: {waited}\r")


if __name__ == "__main__":
    main()
