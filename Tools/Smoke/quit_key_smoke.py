#!/usr/bin/env python3
"""Does the user's quit key, ⌃\\, end a TUIkit app the way a quit does —
even when the app hangs — while ⌃C, ⌃Z, ⌃Y and ⌃T stay keys?

Raw mode keeps the line discipline's signals on with every signal character
but the quit key turned off (`Terminal.rawModeAttributes(from:)`), so the
DRIVER turns ⌃\\ (0x1C) into SIGQUIT before the app reads a byte, as in a
shell. TUIkit's signal handler pays SIGQUIT as a QUIT, not as a crash: it
writes what a normal quit writes — the styling reset, every mode the app
turned on turned off, the cursor shown, and the alternate screen LEFT — puts
the shell's termios back, and ends the process by the signal's default action
(the shell's "Quit: 3"). Never through the Swift runtime's crash reporter,
which would print a backtrace on the alternate screen and wait half a minute
for a key.

Runs `IdleProbe` (the smallest TUIkit app; its `keys` mode shows every key it
hears, its `hang` mode blocks its main thread once on screen) under a PTY
that answers the startup exchange, and checks:

  1. `kill -QUIT`: the process ends by SIGQUIT within seconds; after the
     signal the terminal is sent the input modes off, the cursor shown and
     the alternate screen left, in that order, and no crash report; and the
     PTY's termios is exactly what it was before the launch.
  2. While it runs, the PTY's termios: signals on, canonical input, echo and
     the extensions off, ⌃C and ⌃Z (and on Darwin ⌃Y and ⌃T) turned off as
     signal characters, the quit key ⌃\\.
  3. ⌃C, ⌃Z, ⌃Y and ⌃T arrive as KEYS: the app shows each, and is neither
     stopped nor ended.
  4. ⌃\\ ends it by SIGQUIT, as `kill -QUIT` does (the checks of 1).
  4b. A bracketed paste holding 0x1C: the driver reads pasted bytes too, so
     it ends the app as ⌃\\ does, as it would a shell.
  5. A hung main thread: ⌃\\ still ends it, the same way.
  6. A user who turned the quit key off (`stty quit undef`) before the
     launch: ⌃\\ ends nothing and arrives as a key; `q` quits, and the
     termios comes back exactly, the quit key still off.
  7. A suspend (SIGTSTP) and resume (SIGCONT): the termios while stopped is
     the one from before the launch, raw again after the resume, and ⌃\\
     then quits as in 4.
  9. (run before 8) An app that binds ⌃4, which some terminals send ⌃\\'s
     byte for, or ⌃\\ itself: the driver's quit is masked while it
     runs, signals still on, and 0x1C runs the binding; the termios comes
     back exactly at the quit. One that binds ⌃⌥\\, which masks it without
     taking 0x1C: the unclaimed byte quits by SIGQUIT, as in 4.
  8. A terminal that speaks the kitty keyboard protocol sends ⌃\\ as a key
     report (`CSI 92;5u`), never as the byte the driver acts on: the app
     raises SIGQUIT itself, and quits as in 4, the flags popped on the way,
     and a child in its process group ends with it, as the driver's ⌃\\
     ends one in 4. With the quit key turned off, the report is an ordinary
     key; with a ⌃\\ shortcut of the app's, the report runs it and quits
     nothing (8b).

  10. The stall watchdog, under the kitty protocol: a hung app with no key
     pressed pops nothing; the report of ⌃\ left unread pops the flags
     within about two seconds, and the driver's byte then quits it as in 4.
     A slow frame (IdleProbe's stall key) pops them too, the loop pushes
     them back, and a report sent before the pop and a byte after it both
     read. With a ⌃\ binding, which masks the quit key, nothing is popped.

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

    def __init__(self, env=None, setup=None, kitty=False, job=False):
        self.kitty = kitty
        self.stack = []
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
            resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
            if job:
                self.run_as_job(child_env)
            for fd in (0, 1, 2):
                os.dup2(self.slave, fd)
            if self.slave > 2:
                os.close(self.slave)
            os.execve(BINARY, [BINARY], child_env)
        self.status = None

    def run_as_job(self, child_env):
        """In the forked child: be the session leader a shell is, and run the
        app as a job in a process group of its own, the terminal's foreground
        group, so the app is not the session leader. When a session leader
        exits, the kernel hangs up its terminal's foreground group, which
        would end a child the app started whatever the quit key signalled.
        Like a shell, take the foreground back once the job ends, then end as
        it did. Never returns."""
        signal.signal(signal.SIGTTOU, signal.SIG_IGN)
        app = os.fork()
        if app == 0:
            os.setpgid(0, 0)
            os.tcsetpgrp(self.slave, os.getpid())
            signal.signal(signal.SIGTTOU, signal.SIG_DFL)
            for fd in (0, 1, 2):
                os.dup2(self.slave, fd)
            if self.slave > 2:
                os.close(self.slave)
            os.execve(BINARY, [BINARY], child_env)
        try:
            os.setpgid(app, app)
        except OSError:
            pass  # the job got there first
        _, status = os.waitpid(app, 0)
        os.tcsetpgrp(self.slave, os.getpgrp())
        if os.WIFSIGNALED(status):
            signal.signal(os.WTERMSIG(status), signal.SIG_DFL)
            os.kill(os.getpid(), os.WTERMSIG(status))
        os._exit(os.WEXITSTATUS(status) if os.WIFEXITED(status) else 1)

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
            elif self.kitty and sequence == b"\x1b[?u":
                os.write(self.master, b"\x1b[?%du" % (self.stack[-1] if self.stack else 0))
            elif self.kitty and re.fullmatch(rb"\x1b\[>[0-9]+u", sequence):
                self.stack.append(int(sequence[3:-1]))
            elif self.kitty and sequence == b"\x1b[<u" and self.stack:
                self.stack.pop()

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


# `_POSIX_VDISABLE` for a terminal, and Darwin's two extra signal characters
# (Python's termios module has no names for them).
DISABLED = None
DARWIN = sys.platform == "darwin"
VDSUSP, VSTATUS = 11, 18


def cc(attrs, index):
    value = attrs[6][index]
    return value[0] if isinstance(value, bytes) else value


def is_raw(attrs):
    lflag = attrs[3]
    ok = bool(lflag & termios.ISIG) and not lflag & (termios.ICANON | termios.ECHO | termios.IEXTEN)
    ok = ok and cc(attrs, termios.VINTR) == DISABLED and cc(attrs, termios.VSUSP) == DISABLED
    if DARWIN:
        ok = ok and cc(attrs, VDSUSP) == DISABLED and cc(attrs, VSTATUS) == DISABLED
    return ok and cc(attrs, termios.VQUIT) == 0x1C


def running(app):
    """Neither stopped nor ended."""
    done, _ = os.waitpid(app.pid, os.WNOHANG | os.WUNTRACED)
    return done == 0


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


def spawn_child_file():
    """A path for IdleProbe to write its child's process ID to."""
    handle, path = tempfile.mkstemp(prefix="tuikit-quit-smoke-child-")
    os.close(handle)
    os.unlink(path)
    return path


def child_of(path, app):
    """IdleProbe's process ID and its child's, once it has written them, or
    (None, None)."""
    deadline = time.time() + 3.0
    while time.time() < deadline:
        try:
            with open(path) as handle:
                fields = handle.read().split()
            if len(fields) == 2:
                return int(fields[0]), int(fields[1])
        except (OSError, ValueError):
            pass
        app.pump(0.1)
    return None, None


def child_ends(pid, seconds):
    """Whether process `pid` is gone within `seconds`; killed if it is not."""
    deadline = time.time() + seconds
    while time.time() < deadline:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return True
        time.sleep(0.05)
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        return True
    return False


def check_child_in_group(probe, child, app, name):
    """The child shares the app's process group, which is a job's: not the
    session leader's, whose exit would hang the child up anyway."""
    try:
        ok = os.getpgid(child) == os.getpgid(probe) == probe and os.getpgid(app.pid) != probe
    except (OSError, TypeError):
        ok = False
    check(ok, name + ": the app runs as a job, its child in its process group")


# 1. kill -QUIT.
app = App()
app.pump(2.0)
mark = len(app.out)
os.kill(app.pid, signal.SIGQUIT)
check_quit(app, mark, "kill -QUIT")
app.finish()

# 2–4. The termios, the keys, and ⌃\.
child_file = spawn_child_file()
app = App(env={"IDLE_PROBE_MODE": "keys", "IDLE_PROBE_CHILD_PIDFILE": child_file}, job=True)
DISABLED = os.fpathconf(app.slave, "PC_VDISABLE")
app.pump(2.0)
probe, child = child_of(child_file, app)
check_child_in_group(probe, child, app, "⌃\\")
check(is_raw(app.termios_now()), "running: signals on with only the quit key, ⌃\\, live")
for byte, name in ((b"\x03", "ctrl-c"), (b"\x1a", "ctrl-z"), (b"\x19", "ctrl-y"), (b"\x14", "ctrl-t")):
    os.write(app.master, byte)
    app.pump(0.6)
    check(("key " + name).encode() in app.out and running(app), name + " arrives as a key, and raises no signal")
mark = len(app.out)
os.write(app.master, b"\x1c")
check_quit(app, mark, "⌃\\")
check(child is not None and child_ends(child, 3.0), "⌃\\: the driver ends the app's child with it")
app.finish()

# 4b. A paste holding the quit key's byte.
app = App(env={"IDLE_PROBE_MODE": "keys"})
app.pump(2.0)
mark = len(app.out)
os.write(app.master, b"\x1b[200~pasted \x1c text\x1b[201~")
check_quit(app, mark, "a paste holding 0x1C")
app.finish()

# 5. A hung main thread.
app = App(env={"IDLE_PROBE_MODE": "hang"})
app.pump(2.5)
check(b"hanging" in app.out and running(app), "hang: on screen, and hung")
mark = len(app.out)
os.write(app.master, b"\x1c")
check_quit(app, mark, "hung, ⌃\\")
app.finish()


# 6. The user's own stty: quit undefined.
def quit_undefined(attrs):
    attrs[6][termios.VQUIT] = bytes([DISABLED])


app = App(env={"IDLE_PROBE_MODE": "keys"}, setup=quit_undefined)
app.pump(2.0)
os.write(app.master, b"\x1c")
app.pump(1.5)
check(running(app) and b"key ctrl-\\" in app.out, "stty quit undef: ⌃\\ ends nothing, and arrives as a key")
os.write(app.master, b"q")
status = app.wait_for_exit(5.0)
check(status is not None and os.WIFEXITED(status), "stty quit undef: q quits")
check(app.termios_now() == app.before and cc(app.before, termios.VQUIT) == DISABLED,
      "stty quit undef: the termios comes back exactly, the quit key still off")
app.finish()

# 7. A suspend and resume.
app = App(env={"IDLE_PROBE_MODE": "keys"})
app.pump(2.0)
os.kill(app.pid, signal.SIGTSTP)
stopped = False
deadline = time.time() + 5.0
while time.time() < deadline and not stopped:
    app.pump(0.1)
    done, status = os.waitpid(app.pid, os.WNOHANG | os.WUNTRACED)
    stopped = done == app.pid and os.WIFSTOPPED(status)
check(stopped, "suspend: SIGTSTP stops it")
check(app.termios_now() == app.before, "suspend: the termios while stopped is the one from before the launch")
os.kill(app.pid, signal.SIGCONT)
app.pump(1.5)
check(is_raw(app.termios_now()) and running(app), "resume: raw again, the quit key live")
mark = len(app.out)
os.write(app.master, b"\x1c")
check_quit(app, mark, "after a resume, ⌃\\")
app.finish()

# 9. The app binds a chord the quit key's byte could be (the owner's rule,
# 2026-10-06): the driver's quit is masked, so the byte reaches the app.
def quit_key_of(attrs):
    return cc(attrs, termios.VQUIT)


for bound, ran in (("4", b"key ran ctrl-4"), ("\\", b"key ran ctrl-\\")):
    name = "⌃" + bound + " bound"
    app = App(env={"IDLE_PROBE_MODE": "keys", "IDLE_PROBE_SHORTCUTS": bound})
    app.pump(2.0)
    running_attrs = app.termios_now()
    check(quit_key_of(running_attrs) == DISABLED and bool(running_attrs[3] & termios.ISIG),
          name + ": the quit key masked, signals still on")
    os.write(app.master, b"\x1c")
    app.pump(1.0)
    check(ran in app.out and running(app), name + ": 0x1C runs the binding, and quits nothing")
    os.write(app.master, b"q")
    status = app.wait_for_exit(5.0)
    check(status is not None and os.WIFEXITED(status) and app.termios_now() == app.before,
          name + ": q quits, and the termios comes back exactly, the quit key live")
    app.finish()

# A binding that masks the quit key and does not take the byte itself (⌃⌥\):
# the unclaimed byte quits by SIGQUIT, as the driver's would have.
app = App(env={"IDLE_PROBE_MODE": "keys", "IDLE_PROBE_SHORTCUTS": "M-\\"})
app.pump(2.0)
check(quit_key_of(app.termios_now()) == DISABLED, "⌃⌥\\ bound: the quit key masked")
mark = len(app.out)
os.write(app.master, b"\x1c")
check_quit(app, mark, "⌃⌥\\ bound, unclaimed 0x1C")
app.finish()

# 8. The kitty keyboard protocol.
child_file = spawn_child_file()
app = App(env={"IDLE_PROBE_MODE": "keys", "IDLE_PROBE_CHILD_PIDFILE": child_file}, kitty=True, job=True)
app.pump(3.0)
check(app.stack == [31], "kitty: the flags are pushed")
probe, child = child_of(child_file, app)
check_child_in_group(probe, child, app, "kitty")
mark = len(app.out)
# A key in the same read as the report: the thread that sent the signal goes
# no further (on Linux the handler may run on another thread after `kill`
# returns, and the batch would go on), so the key after it is never shown.
os.write(app.master, b"\x1b[92;5u\x1b[98u")
check_quit(app, mark, "kitty, ⌃\\ as a report")
check(b"\x1b[<u" in app.out[mark:] and app.stack == [], "kitty, ⌃\\ as a report: the flags popped")
check(b"key b" not in app.out[mark:], "kitty, ⌃\\ as a report: a key read with it does nothing more")
check(child is not None and child_ends(child, 3.0),
      "kitty, ⌃\\ as a report: the app's child ends with it, as the driver's ⌃\\ ends it")
app.finish()

app = App(env={"IDLE_PROBE_MODE": "keys"}, kitty=True, setup=quit_undefined)
app.pump(3.0)
os.write(app.master, b"\x1b[92;5u")
app.pump(1.0)
check(b"key ctrl-\\" in app.out and running(app), "kitty, stty quit undef: the report is an ordinary key")
app.finish()

# 8b. The app's own ⌃\ wins over the quit (the owner's rule, 2026-10-06).
app = App(env={"IDLE_PROBE_MODE": "keys", "IDLE_PROBE_SHORTCUTS": "\\"}, kitty=True)
app.pump(3.0)
os.write(app.master, b"\x1b[92;5u")
app.pump(1.0)
check(b"key ran ctrl-\\" in app.out and running(app), "kitty, ⌃\\ bound: the report runs the binding, and quits nothing")
app.finish()

# 10. The stall watchdog: under the kitty protocol ⌃\ is a report only a
# running loop reads, so a thread pops the flags when input waits unread.
app = App(env={"IDLE_PROBE_MODE": "hang"}, kitty=True)
app.pump(3.5)
check(app.stack == [31] and b"\x1b[<u" not in app.out and running(app),
      "kitty, hung, no key pressed: nothing popped")
mark = len(app.out)
os.write(app.master, b"\x1b[92;5u")
app.pump(2.5)
check(b"\x1b[<u" in app.out[mark:] and app.stack == [] and running(app),
      "kitty, hung: input left unread pops the flags, and the report alone quits nothing")
mark = len(app.out)
os.write(app.master, b"\x1c")
check_quit(app, mark, "kitty, hung, then ⌃\\ as the driver's byte")
app.finish()

# A slow frame trips it too; the loop pushes the flags back, and the keys
# sent between, in both encodings, read right.
app = App(env={"IDLE_PROBE_MODE": "keys", "IDLE_PROBE_STALL_KEY": "s"}, kitty=True)
app.pump(3.0)
mark = len(app.out)
os.write(app.master, b"s")
app.pump(0.3)
os.write(app.master, b"\x1b[98u")
app.pump(2.2)
popped_at = app.out.find(b"\x1b[<u", mark)
check(popped_at >= 0 and app.stack == [], "kitty, a slow frame: input left unread pops the flags")
os.write(app.master, b"c")
app.pump(3.0)
check(popped_at >= 0 and b"\x1b[>31u" in app.out[popped_at:] and app.stack == [31],
      "kitty, a slow frame: the loop pushes them back when it reads again")
check(b"key b" in app.out and b"key c" in app.out and running(app),
      "kitty, a slow frame: a report from before the pop and a byte from after it both read")
os.write(app.master, b"q")
status = app.wait_for_exit(5.0)
check(status is not None and os.WIFEXITED(status) and app.stack == [] and app.termios_now() == app.before,
      "kitty, a slow frame: q quits, the flags popped once, the termios exact")
app.finish()

# Masked for a ⌃\ binding of the app's, the driver could not quit on the byte:
# the watchdog stays disarmed, and the flags stay pushed through a stall.
app = App(env={"IDLE_PROBE_MODE": "keys", "IDLE_PROBE_STALL_KEY": "s", "IDLE_PROBE_SHORTCUTS": "\\"}, kitty=True)
app.pump(3.0)
mark = len(app.out)
os.write(app.master, b"s")
app.pump(0.3)
os.write(app.master, b"\x1b[98u")
app.pump(4.0)
check(b"\x1b[<u" not in app.out[mark:] and app.stack == [31] and b"key b" in app.out,
      "kitty, ⌃\\ bound: a stall pops nothing")
app.finish()

# Bound to ⌃4, the driver keeps the quit under the protocol, where ⌃4 arrives
# as itself; but a pop would put the terminal in its legacy encoding, where
# ⌃4 may be ⌃\'s 0x1C, and the driver would quit the app on the binding's key
# during a slow frame. So no watchdog: the flags stay pushed through a stall.
app = App(env={"IDLE_PROBE_MODE": "keys", "IDLE_PROBE_STALL_KEY": "s", "IDLE_PROBE_SHORTCUTS": "4"}, kitty=True)
app.pump(3.0)
check(quit_key_of(app.termios_now()) == 0x1C, "kitty, ⌃4 bound: the driver keeps the quit key")
mark = len(app.out)
os.write(app.master, b"s")
app.pump(0.3)
os.write(app.master, b"\x1b[52;5u")
app.pump(4.0)
check(b"\x1b[<u" not in app.out[mark:] and app.stack == [31] and b"key ran ctrl-4" in app.out and running(app),
      "kitty, ⌃4 bound: a stall pops nothing, and the report runs the binding")
app.finish()

if failures:
    print(f"\n{len(failures)} failure(s)")
    sys.exit(1)
print("\nall checks passed")
