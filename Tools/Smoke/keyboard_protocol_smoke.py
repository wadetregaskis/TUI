#!/usr/bin/env python3
"""Does the app turn the kitty keyboard protocol on where — and ONLY where —
the terminal speaks it, and turn it off again on every way out?

The protocol's "report all keys as escape codes" enhancement makes EVERY key
an escape code, Return and the letters included, so a shell left with the
flags pushed cannot even be typed `reset` at. The pop therefore has to happen
on every exit the process survives (a quit, a suspend) and on the deaths it
does not (a trap, an abort), and the push has to come back on resume.

Runs the real binary under a PTY that plays a terminal: it answers DSR, DA1,
the colour fence and, when the case says the terminal speaks the protocol,
`CSI ? u` with the flags it holds, tracking `CSI > flags u` and `CSI < u` on a
stack as the specification says. Cases:

  1. A terminal that speaks it: the flags are pushed, a key sent as a `CSI u`
     report works (`q` quits), and the flags are popped before the alternate
     screen is left.
  2. A terminal that does not: nothing is pushed or popped, and the one
     question rode on the colour exchange rather than costing a round trip.
  3. Ctrl-Z, sent as its report, is the app's undo (the default), and with
     nothing to undo does nothing; SIGTSTP, what an unbound Ctrl-Z is
     re-raised as: popped before the stop, pushed again on SIGCONT; the app
     still quits.
  4. SIGABRT after the push: the flags are popped on the way down, and the
     shell's line discipline (echo, canonical input) is put back.
  5. SIGHUP and SIGUSR1, which terminate by default and nothing in TUI
     handles, and SIGTERM, which the run loop turns into an orderly
     shutdown: each pops the flags and puts the line discipline back. A
     terminal that does not speak the protocol gets its line discipline back
     from SIGHUP too.

Usage:  python3 Tools/Smoke/keyboard_protocol_smoke.py [path-to-binary]
Exits 0 when every case holds. Uses an isolated TUIKIT_CONFIG_DIR.
"""

import atexit
import os
import pty
import re
import select
import shutil
import signal
import sys
import tempfile
import termios
import time

BINARY = sys.argv[1] if len(sys.argv) > 1 else "./.build/debug/Example"

QUERY = b"\x1b[?u"
POP = b"\x1b[<u"
EXIT_ALT = b"\x1b[?1049l"
ENTER_ALT = b"\x1b[?1049h"

STRIPPED = (
    "TERM_PROGRAM", "TERM_PROGRAM_VERSION", "LC_TERMINAL", "LC_TERMINAL_VERSION",
    "TMUX", "TMUX_PANE", "TUIKIT_TERM_PROGRAM",
)

failures = []

# Every child's config directory, under one of this run's own that atexit
# removes: it runs on the SystemExit at the end, and on an exception, too. The
# forked child never runs it: it execs, or ends by os._exit if exec fails.
SCRATCH = tempfile.mkdtemp(prefix="tuikit-kkp-smoke-")
atexit.register(shutil.rmtree, SCRATCH, ignore_errors=True)


def check(condition, label):
    print(("ok   " if condition else "FAIL ") + label)
    if not condition:
        failures.append(label)


class FakeTerminal:
    """The child under a PTY, and a terminal's answers to what it asks."""

    def __init__(self, speaks_protocol, env=None):
        self.speaks = speaks_protocol
        self.stack = []
        self.out = b""
        self.pending = b""
        config = tempfile.mkdtemp(dir=SCRATCH)
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            try:
                for sig in (signal.SIGHUP, signal.SIGTERM, signal.SIGUSR1, signal.SIGUSR2, signal.SIGINT):
                    signal.signal(sig, signal.SIG_DFL)
                for key in STRIPPED:
                    os.environ.pop(key, None)
                os.environ["TERM"] = "xterm-256color"
                os.environ["LANG"] = "en_US.UTF-8"
                os.environ["TUIKIT_CONFIG_DIR"] = config
                os.environ.update(env or {})
                os.execv(BINARY, [BINARY])
            except Exception:
                pass
            os._exit(127)  # exec failed: end here, never in this script's code or its cleanup

    def pump(self, seconds):
        until = time.time() + seconds
        while time.time() < until:
            readable, _, _ = select.select([self.fd], [], [], 0.05)
            if not readable:
                continue
            try:
                data = os.read(self.fd, 65536)
            except OSError:
                return
            if not data:
                return
            self.out += data
            self.pending += data
            self.answer()

    def answer(self):
        while True:
            match = re.search(rb"\x1b\[[?>=<]?[0-9;]*[$ ]?[a-zA-Z@]", self.pending)
            if not match:
                return
            sequence = match.group(0)
            self.pending = self.pending[match.end():]
            if sequence == b"\x1b[6n":
                os.write(self.fd, b"\x1b[24;80R")
            elif sequence == b"\x1b[5n":
                os.write(self.fd, b"\x1b[0n")
            elif sequence == b"\x1b[c":
                os.write(self.fd, b"\x1b[?62;22c")
            elif self.speaks and sequence == QUERY:
                os.write(self.fd, b"\x1b[?%du" % (self.stack[-1] if self.stack else 0))
            elif self.speaks and re.fullmatch(rb"\x1b\[>[0-9]+u", sequence):
                self.stack.append(int(sequence[3:-1]))
            elif self.speaks and sequence == POP and self.stack:
                self.stack.pop()

    def send(self, data):
        os.write(self.fd, data)

    def finish(self):
        try:
            os.kill(self.pid, signal.SIGKILL)
        except OSError:
            pass
        try:
            os.waitpid(self.pid, 0)
        except ChildProcessError:
            pass


def q_report():
    return b"\x1b[113;;113u"


def line_discipline_restored(term):
    """Whether the PTY is back in the cooked mode a shell reads lines in:
    echo and canonical input on, which raw mode turns off."""
    try:
        attrs = termios.tcgetattr(term.fd)
    except termios.error:
        return False
    return bool(attrs[3] & termios.ECHO) and bool(attrs[3] & termios.ICANON)


# 1. A terminal that speaks it.
term = FakeTerminal(speaks_protocol=True)
term.pump(3.0)
check(b"\x1b[>31u" in term.out, "speaks it: all five enhancements pushed")
check(term.stack == [31], "speaks it: one entry on the stack while running")
term.send(q_report())
term.pump(2.0)
tail = term.out[term.out.rfind(b"\x1b[>31u"):]
check(POP in tail, "speaks it: q, sent as a key report, quits and the flags are popped")
check(POP in tail and EXIT_ALT in tail and tail.index(POP) < tail.index(EXIT_ALT),
      "speaks it: popped before the alternate screen is left")
check(term.stack == [], "speaks it: the stack is back as the shell had it")
term.finish()

# 2. A terminal that does not.
term = FakeTerminal(speaks_protocol=False)
term.pump(3.0)
check(term.out.count(QUERY) == 1, "legacy: asked once")
check(QUERY + b"\x1b]10;?" in term.out and QUERY + b"\x1b[c" not in term.out,
      "legacy: asked on the colour exchange, with no round trip of its own")
check(re.search(rb"\x1b\[>[0-9]+u", term.out) is None, "legacy: nothing pushed")
term.send(b"q")
term.pump(2.0)
check(POP not in term.out, "legacy: nothing popped")
term.finish()

# 2b. A terminal that speaks it, with the user's opt-out set.
os.environ["TUIKIT_KEYBOARD_PROTOCOL"] = "0"
term = FakeTerminal(speaks_protocol=True)
del os.environ["TUIKIT_KEYBOARD_PROTOCOL"]
term.pump(3.0)
check(QUERY not in term.out, "opted out: not even asked")
term.send(b"q")
term.pump(2.0)
term.finish()

# 3. Suspend and resume. Ctrl-Z is the app's undo by default, so with
# nothing to undo its report does nothing; the suspend comes from SIGTSTP,
# which is what an unbound Ctrl-Z is re-raised as.
term = FakeTerminal(speaks_protocol=True)
term.pump(3.0)
term.send(b"\x1b[122;5u")  # Ctrl-Z, as its report


def wait_for_stop(term, seconds):
    deadline = time.time() + seconds
    while time.time() < deadline:
        term.pump(0.1)
        done, status = os.waitpid(term.pid, os.WNOHANG | os.WUNTRACED)
        if done == term.pid and os.WIFSTOPPED(status):
            return True
    return False


check(not wait_for_stop(term, 1.5) and term.stack == [31], "Ctrl-Z, sent as a key report, is undo: no stop")
mark = len(term.out)
os.kill(term.pid, signal.SIGTSTP)
check(wait_for_stop(term, 3.0), "suspend: SIGTSTP stops the process")
check(POP in term.out[mark:] and term.stack == [], "suspend: popped before the stop")
mark = len(term.out)
os.kill(term.pid, signal.SIGCONT)
term.pump(2.0)
check(b"\x1b[>31u" in term.out[mark:] and term.stack == [31], "resume: pushed again")
term.send(q_report())
term.pump(2.0)
check(term.stack == [], "resume: still quits, popping on the way")
term.finish()

# 4. A crash. The Swift runtime's backtracer, which runs after TUI's
# handler, would otherwise go interactive on a terminal — setting raw mode
# itself and waiting half a minute for a key — and the check is of TUI.
term = FakeTerminal(speaks_protocol=True, env={"SWIFT_BACKTRACE": "interactive=no"})
term.pump(3.0)
mark = len(term.out)
os.kill(term.pid, signal.SIGABRT)
term.pump(2.0)
check(POP in term.out[mark:] and term.stack == [], "abort: popped on the way down")
check(line_discipline_restored(term), "abort: the shell's line discipline is back")
term.finish()

# 5. The terminations: two nothing in TUI handles, and the orderly one.
for sig in (signal.SIGHUP, signal.SIGUSR1, signal.SIGTERM):
    name = signal.Signals(sig).name
    term = FakeTerminal(speaks_protocol=True)
    term.pump(3.0)
    mark = len(term.out)
    os.kill(term.pid, sig)
    term.pump(2.0)
    check(POP in term.out[mark:] and term.stack == [], name + ": popped on the way down")
    check(line_discipline_restored(term), name + ": the shell's line discipline is back")
    term.finish()

term = FakeTerminal(speaks_protocol=False)
term.pump(3.0)
os.kill(term.pid, signal.SIGHUP)
term.pump(2.0)
check(line_discipline_restored(term), "legacy, SIGHUP: the shell's line discipline is back")
term.finish()

sys.exit(1 if failures else 0)
