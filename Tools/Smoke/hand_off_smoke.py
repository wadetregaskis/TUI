#!/usr/bin/env python3
"""Handing the terminal to another program, `\\.handOffTerminal`, in a real PTY.

Runs `IdleProbe` in its `handoff` mode (one button, which hands the terminal
to a shell command and shows how the command ended) as a job of a shell-like
parent, as an app runs from a shell, and checks:

  1. What the command is handed: the frame at `.background` drawn first; then
     the mouse reports, bracketed paste and focus reports off, the cursor
     shown and the alternate screen left; and, as `stty -a` reads them in the
     command, canonical input, echo and signals on, ⌃C and ⌃Z the signal
     characters again. The command reads a line typed at it: nothing of the
     app's read it first. Taken back after: the alternate screen and the modes
     again, every line drawn again, the phase `.active`, and the command's
     exit status shown.
  2. ⌃C while the command runs (`sleep`): the line discipline sends SIGINT to
     the whole foreground group, which ends the command and not the app, nor
     shuts the app down once it is back. A resize meanwhile: the repaint is at
     the new size, down to its last row.
  3. ⌃Z while the command runs: the app and the command stop together, as a
     job does; continued (what `fg` sends), the command goes on, and once it
     ends the app takes the terminal back and does not suspend itself after,
     with no stop left pending.

Each run ends with ⌃Q, which quits with status 0.

Usage:  python3 Tools/Smoke/hand_off_smoke.py [path-to-IdleProbe]
Exits 0 when every case holds. Uses an isolated TUI_CONFIG_DIR, and no core
files (RLIMIT_CORE 0 in the child).
"""

import atexit
import faulthandler
import fcntl
import os
import re
import resource
import select
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import time

BINARY = sys.argv[1] if len(sys.argv) > 1 else "./.build/debug/IdleProbe"

ENTER_ALT = b"\x1b[?1049h"
EXIT_ALT = b"\x1b[?1049l"
SHOW_CURSOR = b"\x1b[?25h"
# Whichever tracking mode the scene asks for: 1000 clicks, 1002 drags, 1003 any motion.
MOUSE_ON = re.compile(rb"\x1b\[\?100[023]h")
MOUSE_OFF = b"\x1b[?1000l"
PASTE_ON = b"\x1b[?2004h"
PASTE_OFF = b"\x1b[?2004l"
FOCUS_ON = b"\x1b[?1004h"
FOCUS_OFF = b"\x1b[?1004l"

STRIPPED = (
    "TERM_PROGRAM", "TERM_PROGRAM_VERSION", "LC_TERMINAL", "LC_TERMINAL_VERSION",
    "TMUX", "TMUX_PANE", "TUI_TERM_PROGRAM",
)

failures = []

SCRATCH = tempfile.mkdtemp(prefix="tuikit-hand-off-smoke-")
atexit.register(shutil.rmtree, SCRATCH, ignore_errors=True)

# Says which line a stuck run was stuck on, and fails, rather than sitting out
# CI's step limit with its output still buffered.
faulthandler.dump_traceback_later(300, exit=True)


def check(condition, label):
    print(("ok   " if condition else "FAIL ") + label, flush=True)
    if not condition:
        failures.append(label)


class App:
    """IdleProbe's `handoff` mode running `command`, as a job in a process
    group of its own under a shell-like session leader: the terminal's
    foreground group, as a shell makes it. Not the session leader itself,
    whose group the kernel would never stop: a group with no parent outside it
    in the session is orphaned, and the terminal's ⌃Z is not delivered to an
    orphaned group."""

    def __init__(self, command, rows=30, columns=90):
        self.master, self.slave = os.openpty()
        self.resize(rows, columns)
        self.out = b""
        self.pending = b""
        self.pidfile = os.path.join(tempfile.mkdtemp(dir=SCRATCH), "pids")
        env = {k: v for k, v in os.environ.items() if k not in STRIPPED}
        env.update({
            "TERM": "xterm-256color",
            "LANG": "en_US.UTF-8",
            "TUI_CONFIG_DIR": tempfile.mkdtemp(dir=SCRATCH),
            "IDLE_PROBE_MODE": "handoff",
            "IDLE_PROBE_HANDOFF_COMMAND": command,
            "IDLE_PROBE_HANDOFF_PIDFILE": self.pidfile,
        })
        self.pid = os.fork()
        if self.pid == 0:
            try:
                os.close(self.master)
                os.setsid()
                fcntl.ioctl(self.slave, termios.TIOCSCTTY, 0)
                resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
                self.run_as_job(env)
            except Exception:
                pass
            os._exit(127)  # never in this script's code or its cleanup
        self.status = None

    def run_as_job(self, env):
        """In the forked child: the shell. Runs the app in a process group of
        its own, the foreground group, waits for it to end, and ends as it
        did. Never returns."""
        signal.signal(signal.SIGTTOU, signal.SIG_IGN)
        app = os.fork()
        if app == 0:
            try:
                os.setpgid(0, 0)
                os.tcsetpgrp(self.slave, os.getpid())
                signal.signal(signal.SIGTTOU, signal.SIG_DFL)
                for fd in (0, 1, 2):
                    os.dup2(self.slave, fd)
                if self.slave > 2:
                    os.close(self.slave)
                os.execve(BINARY, [BINARY], env)
            except Exception:
                pass
            os._exit(127)
        try:
            os.setpgid(app, app)
        except OSError:
            pass  # the job got there first
        _, status = os.waitpid(app, 0)
        if os.WIFSIGNALED(status):
            signal.signal(os.WTERMSIG(status), signal.SIG_DFL)
            os.kill(os.getpid(), os.WTERMSIG(status))
        os._exit(os.WEXITSTATUS(status) if os.WIFEXITED(status) else 1)

    def resize(self, rows, columns):
        """Sets the PTY's size, which signals the foreground group SIGWINCH."""
        fcntl.ioctl(self.slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, columns, 0, 0))
        self.rows = rows

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
        """A terminal's answers to the startup exchange."""
        while True:
            match = re.search(rb"\x1b\[[?>=<]?[0-9;]*[$ ]?[a-zA-Z@]", self.pending)
            if not match:
                return
            sequence = match.group(0)
            self.pending = self.pending[match.end():]
            if sequence == b"\x1b[6n":
                os.write(self.master, b"\x1b[%d;80R" % self.rows)
            elif sequence == b"\x1b[5n":
                os.write(self.master, b"\x1b[0n")
            elif sequence == b"\x1b[c":
                os.write(self.master, b"\x1b[?62;22c")

    def wait_for(self, needle, seconds, since=0):
        """Pumps until `needle` is in the output after `since`; whether it is."""
        deadline = time.time() + seconds
        while time.time() < deadline:
            if needle in self.out[since:]:
                return True
            self.pump(0.05)
        return needle in self.out[since:]

    def settle(self):
        """Until the first frame is up, and a little more."""
        self.wait_for(b"bottom row", 30.0)
        self.pump(0.5)

    def hand_off(self):
        """Presses the button, and waits for the command to say it is ready.
        Returns where the output stood at the press."""
        mark = len(self.out)
        os.write(self.master, b" ")
        check(self.wait_for(b"CHILD-READY", 15.0, mark), "the button hands the terminal to the command")
        return mark

    def running(self):
        done, status = os.waitpid(self.pid, os.WNOHANG)
        if done == self.pid:
            self.status = status
            return False
        return True

    def quit(self, label):
        """⌃Q, and the exit status: 0, at once."""
        os.write(self.master, b"\x11")
        deadline = time.time() + 15.0
        while time.time() < deadline and self.running():
            self.pump(0.05)
        check(self.status is not None and os.WIFEXITED(self.status) and os.WEXITSTATUS(self.status) == 0,
              label + ": ⌃Q quits with status 0")

    def kill(self):
        if self.status is None:
            try:
                os.killpg(self.pid, signal.SIGKILL)
            except OSError:
                pass
            try:
                os.kill(self.pid, signal.SIGKILL)
                os.waitpid(self.pid, 0)
            except OSError:
                pass
        for fd in (self.master, self.slave):
            try:
                os.close(fd)
            except OSError:
                pass

    def pids(self):
        """The app's process ID and the command's, as the probe writes them once
        the command has started, which may be after the command's first line."""
        deadline = time.time() + 5.0
        while time.time() < deadline:
            try:
                with open(self.pidfile) as handle:
                    app, command = handle.read().split()[:2]
                return int(app), int(command)
            except (OSError, ValueError):
                self.pump(0.05)
        return None, None


def stopped(pid):
    """Whether `pid` is stopped (`T`): from /proc on Linux, whose containers may
    have no `ps`, and from `ps` elsewhere."""
    if os.path.isdir("/proc/self"):
        try:
            with open("/proc/%d/stat" % pid) as handle:
                # The state follows the command's name, which is in parentheses.
                return handle.read().rsplit(")", 1)[1].split()[0] == "T"
        except (OSError, IndexError):
            return False
    result = subprocess.run(["ps", "-o", "stat=", "-p", str(pid)], capture_output=True, text=True)
    return result.stdout.strip().startswith("T")


def after(haystack, first, then):
    """Whether `then` appears in `haystack` after `first` does."""
    at = haystack.find(first)
    return at >= 0 and haystack.find(then, at + len(first)) >= 0


def handed_over_and_back():
    print("── 1. what the command gets, and the terminal taken back ──", flush=True)
    app = App("stty -a; echo CHILD-READY; read line; echo \"CHILD-GOT:$line\"")
    try:
        app.settle()
        check(MOUSE_ON.search(app.out) is not None, "the app reports the mouse before the hand-off")
        mark = app.hand_off()
        handed = app.out[mark:app.out.find(b"CHILD-READY", mark)]
        # The frame writes the cells that changed: "background" over "active".
        check(b"background" in handed and handed.find(b"background") < handed.find(EXIT_ALT),
              "a frame at .background is drawn before the terminal is handed over")
        for sequence, name in ((MOUSE_OFF, "mouse reports"), (PASTE_OFF, "bracketed paste"),
                               (FOCUS_OFF, "focus reports")):
            check(sequence in handed, "%s off before the command runs" % name)
        check(SHOW_CURSOR in handed and EXIT_ALT in handed, "the cursor shown and the main screen back")
        settings = handed[handed.find(EXIT_ALT):].decode("utf-8", "replace")
        for flag in ("icanon", "echo", "isig"):
            check(re.search(r"(?<![-\w])%s(?![\w])" % flag, settings) is not None,
                  "the command's terminal has %s on (stty -a)" % flag)
        check(re.search(r"intr = \^C", settings) is not None and re.search(r"susp = \^Z", settings) is not None,
              "⌃C and ⌃Z are signal characters again")

        os.write(app.master, b"hello\r")
        check(app.wait_for(b"CHILD-GOT:hello", 10.0, mark), "the command reads the line typed at it")
        check(app.wait_for(b"handoffs 1 exit 0", 15.0, mark), "the app takes the terminal back, the status shown")
        back = app.out[app.out.find(b"CHILD-GOT:hello", mark):]
        check(ENTER_ALT in back, "the alternate screen again")
        for sequence, name in ((PASTE_ON, "bracketed paste"), (FOCUS_ON, "focus reports")):
            check(after(back, ENTER_ALT, sequence), "%s on again" % name)
        check(MOUSE_ON.search(back, back.find(ENTER_ALT)) is not None, "mouse reports on again")
        check(after(back, ENTER_ALT, b"idle probe") and after(back, ENTER_ALT, b"bottom row"),
              "every line drawn again, the ones that did not change too")
        check(after(back, ENTER_ALT, b"phase active"), "the phase is .active again")
        app.pump(1.0)
        check(app.running(), "the app runs on")
        app.quit("1")
    finally:
        app.kill()


def interrupted_and_resized():
    print("── 2. ⌃C and a resize while the command runs ──", flush=True)
    app = App("echo CHILD-READY; exec sleep 30")
    try:
        app.settle()
        mark = app.hand_off()
        app.resize(40, 100)
        app.pump(0.3)
        os.write(app.master, b"\x03")
        check(app.wait_for(b"handoffs 1 signal 2", 15.0, mark), "⌃C ends the command (SIGINT)")
        back = app.out[app.out.find(ENTER_ALT, mark):]
        check(re.search(rb"\x1b\[40;\d+H", back) is not None and b"bottom row" in back,
              "the repaint is at the new size, down to its last row")
        app.pump(2.0)
        check(app.running(), "and not the app, which is not shut down after either")
        app.quit("2")
    finally:
        app.kill()


def stopped_with_the_command():
    print("── 3. ⌃Z while the command runs ──", flush=True)
    app = App("echo CHILD-READY; exec sleep 30")
    try:
        app.settle()
        mark = app.hand_off()
        app_pid, command_pid = app.pids()
        check(app_pid is not None, "the probe says who is who")
        if app_pid is None:
            return
        os.write(app.master, b"\x1a")
        deadline = time.time() + 5.0
        while time.time() < deadline and not (stopped(app_pid) and stopped(command_pid)):
            app.pump(0.1)
        check(stopped(app_pid) and stopped(command_pid), "⌃Z stops the app and the command together")
        # What `fg` does, the terminal's foreground being the job's already.
        os.killpg(app_pid, signal.SIGCONT)
        app.pump(0.5)
        check(not stopped(command_pid) and not stopped(app_pid), "continued, both run on")
        os.write(app.master, b"\x03")
        check(app.wait_for(b"handoffs 1 signal 2", 15.0, mark), "the command ends, and the app takes the terminal back")
        retaken = app.out.find(ENTER_ALT, mark)
        app.pump(2.0)
        check(not stopped(app_pid) and app.running(), "the app does not stop itself after: no suspend pending")
        check(EXIT_ALT not in app.out[retaken:], "nor hand the terminal back again")
        app.quit("3")
    finally:
        app.kill()


def main():
    if not os.path.exists(BINARY):
        print("no binary at %s" % BINARY)
        sys.exit(2)
    handed_over_and_back()
    interrupted_and_resized()
    stopped_with_the_command()
    if failures:
        print("\n%d check(s) failed" % len(failures))
        sys.exit(1)
    print("\nall checks passed")


if __name__ == "__main__":
    main()
