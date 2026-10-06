#!/usr/bin/env python3
"""Does SIGQUIT end a TUIkit app the way a quit does?

SIGQUIT is the user's quit key's signal (⌃\\ in a cooked terminal). TUIkit's
signal handler pays it as a QUIT, not as a crash: it writes what a normal quit
writes — the styling reset, every mode the app turned on turned off, the
cursor shown, and the alternate screen LEFT — puts the shell's termios back,
and ends the process by the signal's default action (the shell's "Quit: 3").
Never through the Swift runtime's crash reporter, which would print a
backtrace on the alternate screen and wait half a minute for a key.

Runs `IdleProbe` (the smallest TUIkit app) under a PTY that answers the
startup exchange, and checks:

  1. `kill -QUIT`: the process ends by SIGQUIT within seconds; after the
     signal the terminal is sent the input modes off, the cursor shown and
     the alternate screen left, in that order, and no crash report; and the
     PTY's termios is exactly what it was before the launch.

Usage:  python3 Tools/Smoke/quit_key_smoke.py [path-to-IdleProbe]
Exits 0 when every case holds. Uses an isolated TUIKIT_CONFIG_DIR, and no
core files (RLIMIT_CORE 0 in the child).
"""

import fcntl
import os
import re
import resource
import select
import signal
import struct
import sys
import tempfile
import termios
import time

BINARY = sys.argv[1] if len(sys.argv) > 1 else "./.build/debug/IdleProbe"

EXIT_ALT = b"\x1b[?1049l"
SHOW_CURSOR = b"\x1b[?25h"
FOCUS_REPORTS_OFF = b"\x1b[?1004l"

STRIPPED = (
    "TERM_PROGRAM", "TERM_PROGRAM_VERSION", "LC_TERMINAL", "LC_TERMINAL_VERSION",
    "TMUX", "TMUX_PANE", "TUIKIT_TERM_PROGRAM",
)

failures = []


def check(condition, label):
    print(("ok   " if condition else "FAIL ") + label)
    if not condition:
        failures.append(label)


class App:
    """The app on a PTY whose slave the harness keeps open, so the line
    discipline can be read before the launch and after the exit; and a
    terminal's answers to the startup exchange."""

    def __init__(self, env=None, setup=None):
        self.master, self.slave = os.openpty()
        fcntl.ioctl(self.slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
        if setup:
            attrs = termios.tcgetattr(self.slave)
            setup(attrs)
            termios.tcsetattr(self.slave, termios.TCSANOW, attrs)
        self.before = termios.tcgetattr(self.slave)
        self.out = b""
        self.pending = b""
        child_env = {k: v for k, v in os.environ.items() if k not in STRIPPED}
        child_env.update({
            "TERM": "xterm-256color",
            "LANG": "en_US.UTF-8",
            "TUIKIT_CONFIG_DIR": tempfile.mkdtemp(prefix="tuikit-quit-smoke-"),
        })
        child_env.update(env or {})
        self.pid = os.fork()
        if self.pid == 0:
            os.close(self.master)
            os.setsid()
            fcntl.ioctl(self.slave, termios.TIOCSCTTY, 0)
            for fd in (0, 1, 2):
                os.dup2(self.slave, fd)
            if self.slave > 2:
                os.close(self.slave)
            resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
            os.execve(BINARY, [BINARY], child_env)
        self.status = None

    def pump(self, seconds):
        until = time.time() + seconds
        while time.time() < until:
            readable, _, _ = select.select([self.master], [], [], 0.05)
            if not readable:
                continue
            try:
                data = os.read(self.master, 65536)
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
                os.write(self.master, b"\x1b[24;80R")
            elif sequence == b"\x1b[5n":
                os.write(self.master, b"\x1b[0n")
            elif sequence == b"\x1b[c":
                os.write(self.master, b"\x1b[?62;22c")

    def wait_for_exit(self, seconds):
        """The wait status once the process has ended, or None."""
        deadline = time.time() + seconds
        while time.time() < deadline:
            self.pump(0.05)
            done, status = os.waitpid(self.pid, os.WNOHANG)
            if done == self.pid:
                self.status = status
                return status
        return None

    def termios_now(self):
        return termios.tcgetattr(self.master)

    def finish(self):
        if self.status is None:
            try:
                os.kill(self.pid, signal.SIGKILL)
                os.waitpid(self.pid, 0)
            except (OSError, ChildProcessError):
                pass
        os.close(self.master)
        os.close(self.slave)


def ended_by_sigquit(status):
    return status is not None and os.WIFSIGNALED(status) and os.WTERMSIG(status) == signal.SIGQUIT


def check_quit(app, mark, name):
    """The checks every quit by SIGQUIT has to pass."""
    status = app.wait_for_exit(5.0)
    check(ended_by_sigquit(status), name + ": the process ends by SIGQUIT")
    tail = app.out[mark:]
    order = [tail.find(FOCUS_REPORTS_OFF), tail.find(SHOW_CURSOR), tail.rfind(EXIT_ALT)]
    check(-1 not in order and order == sorted(order),
          name + ": the input modes off, the cursor shown, the alternate screen left, in order")
    check(b"crashed" not in tail and b"Backtrac" not in tail, name + ": no crash report")
    check(app.termios_now() == app.before, name + ": the termios is exactly what it was before the launch")


# 1. kill -QUIT.
app = App()
app.pump(2.0)
mark = len(app.out)
os.kill(app.pid, signal.SIGQUIT)
check_quit(app, mark, "kill -QUIT")
app.finish()

if failures:
    print(f"\n{len(failures)} failure(s)")
    sys.exit(1)
print("\nall checks passed")
