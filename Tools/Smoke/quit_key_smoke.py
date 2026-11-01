#!/usr/bin/env python3
"""The ways of quitting a TUI app from the keyboard: ⌃Q at once, ⌃C and ⌃\\
asking first, ⌃\\ quitting a hung app whatever else; and SIGQUIT, a quit and
not a crash.

By default a running app takes ⌃\\ from the driver (raw mode masks the quit key
once the first frame is up), so the first one can ask before anything has
happened, the app's children included. If the loop doesn't read it within two
seconds, a thread of its own does, and sends SIGQUIT as the driver would have.
SIGQUIT's handler pays it as a QUIT: it writes what a normal quit writes (the
styling reset, every mode the app turned on turned off, the cursor shown, and
the alternate screen LEFT), puts the shell's termios back, and ends the process
by the signal's default action (the shell's "Quit: 3"). Never through the Swift
runtime's crash reporter, which would print a backtrace on the alternate screen
and wait half a minute for a key.

Under `.quitConfirmation(.whenWarned)` with no warning active the driver keeps
the key, as in a shell, and the stall watchdog stands by for the kitty keyboard
protocol, as it always did.

Runs `IdleProbe` (the smallest TUI app; its `keys` mode shows every key it
hears, its `hang` mode blocks its main thread once on screen) under a PTY
that answers the startup exchange, and checks:

  1. `kill -QUIT`: the process ends by SIGQUIT within seconds, with no dialog,
     whatever warnings the app states; after the signal the terminal is sent the
     input modes off, the cursor shown and the alternate screen left, in that
     order, and no crash report; and the PTY's termios is exactly what it was
     before the launch.
  2. While it runs, the PTY's termios: signals on, canonical input, echo and
     the extensions off, flow control off, ⌃C and ⌃Z (and on Darwin ⌃Y and ⌃T)
     turned off as signal characters, and the quit key given up.
  3. ⌃C, ⌃Z, ⌃Y and ⌃T arrive as KEYS: the app shows each, and is neither
     stopped nor ended. ⌃C, which nothing takes, then asks; Escape stays.
  4. ⌃\\: the first asks, ending nothing, the app's child left alone; a second
     while it is up ends it by SIGQUIT (the checks of 1), and the child with it.
     A second ⌃C quits too, with status 0. The dialog's keys: Return stays, Tab
     and Return quits with status 0.
  4b. A bracketed paste holding 0x1C: text, while the app has the key; and a
     quit, as in a shell, while the driver does.
  5. A hung main thread: one ⌃\\ ends it. Other keys at a hung app don't, and a
     ⌃\\ after them does at once. A slow frame: keys typed through it read in
     order; a ⌃\\ through it quits.
  6. A user who turned the quit key off (`stty quit undef`) before the
     launch: ⌃\\ ends nothing and arrives as a key; ⌃Q quits, and the
     termios comes back exactly, the quit key still off.
  7. A suspend (SIGTSTP) and resume (SIGCONT): the termios while stopped is
     the one from before the launch, raw again after the resume, and ⌃\\
     then asks and quits as in 4.
  9. (run before 8) An app that binds ⌃4, which some terminals send ⌃\\'s
     byte for, or ⌃\\ itself: 0x1C runs the binding and asks nothing; the
     termios comes back exactly at the quit. One that binds ⌃⌥\\, which masks it
     without taking 0x1C: the unclaimed byte asks, as in 4. `.whenWarned`: the
     driver keeps the key, ⌃\\ ends it and its child at once, and ⌃C quits at once.
 11. ⌃Q: at once, status 0, no dialog; asks under `.always`, and with a
     warning active, where the dialog names it, and only ⌃\\ quits past it.
  8. A terminal that speaks the kitty keyboard protocol sends ⌃\\ as a key
     report (`CSI 92;5u`), never as the byte the driver acts on: the first asks
     and the second quits as in 4, the flags popped on the way, and a child in
     its process group ends with it. ⌃Q as a report quits. A hung app's report
     is read for it, and quits. With the quit key turned off, the report is
     an ordinary key; with a ⌃\\ shortcut of the app's, the report runs it and
     quits nothing (8b).
 10. The stall watchdog, under the kitty protocol and `.whenWarned`: a hung app
     with no key pressed pops nothing; the report of ⌃\\ left unread pops the flags
     within about two seconds, and the driver's byte then quits it as in 4.
     A slow frame (IdleProbe's stall key) pops them too, the loop pushes
     them back, and a report sent before the pop and a byte after it both
     read. With a ⌃\\ binding, which masks the quit key, nothing is popped, and
     with the quit key asking first, nothing needs to be.

Usage:  python3 Tools/Smoke/quit_key_smoke.py [path-to-IdleProbe]
Exits 0 when every case holds. Uses an isolated TUI_CONFIG_DIR, and no
core files (RLIMIT_CORE 0 in the child).
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
    "TMUX", "TMUX_PANE", "TUI_TERM_PROGRAM",
)

failures = []

# Every child's config directory, and the file IdleProbe writes its child's
# process ID to, under one directory of this run's own that atexit removes: it
# runs on the SystemExit at the end, and on an exception, too. A forked child
# never runs it: it execs, or, as a job's shell, ends by os._exit or a signal,
# and ends by os._exit if exec fails.
SCRATCH = tempfile.mkdtemp(prefix="tuikit-quit-smoke-")
atexit.register(shutil.rmtree, SCRATCH, ignore_errors=True)


# macOS 26's Swift 6.4 lane sat here until its 20-minute step limit, once, and showed
# nothing, its output still buffered. This says which line it was stuck on, and fails.
faulthandler.dump_traceback_later(420, exit=True)


def check(condition, label):
    print(("ok   " if condition else "FAIL ") + label, flush=True)
    if not condition:
        failures.append(label)


class App:
    """The app on a PTY whose slave the harness keeps open, so the line
    discipline can be read before the launch and after the exit; and a
    terminal's answers to the startup exchange."""

    def __init__(self, env=None, setup=None, kitty=False, job=False):
        self.kitty = kitty
        self.hangs = (env or {}).get("IDLE_PROBE_MODE") == "hang"
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
            "TUI_CONFIG_DIR": tempfile.mkdtemp(dir=SCRATCH),
        })
        child_env.update(env or {})
        self.pid = os.fork()
        if self.pid == 0:
            try:
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
            except Exception:
                pass
            os._exit(127)  # exec failed: end here, never in this script's code or its cleanup
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
            try:
                os.setpgid(0, 0)
                os.tcsetpgrp(self.slave, os.getpid())
                signal.signal(signal.SIGTTOU, signal.SIG_DFL)
                for fd in (0, 1, 2):
                    os.dup2(self.slave, fd)
                if self.slave > 2:
                    os.close(self.slave)
                os.execve(BINARY, [BINARY], child_env)
            except Exception:
                pass
            os._exit(127)  # exec failed: end here, never in this script's code or its cleanup
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

    def settle(self):
        """Pumps until the app has drawn its first frame, and a little more,
        which by then has given up the quit key: launching a debug build on a busy
        machine takes as long as it takes. In `hang` mode, on until the main
        thread has stopped."""
        deadline = time.time() + 30.0
        while time.time() < deadline and b"idle probe" not in self.out:
            self.pump(0.1)
        self.pump(1.5 if self.hangs else 0.3)

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
            # Reading while it dies: a session leader's exit waits for its terminal's
            # output to drain, so a blocking wait here hangs on any byte it left unread.
            try:
                os.kill(self.pid, signal.SIGKILL)
                self.wait_for_exit(20.0)
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
    ok = ok and not attrs[0] & termios.IXON
    ok = ok and cc(attrs, termios.VINTR) == DISABLED and cc(attrs, termios.VSUSP) == DISABLED
    if DARWIN:
        ok = ok and cc(attrs, VDSUSP) == DISABLED and cc(attrs, VSTATUS) == DISABLED
    return ok


def quit_key_of(attrs):
    return cc(attrs, termios.VQUIT)


def running(app):
    """Neither stopped nor ended."""
    done, _ = os.waitpid(app.pid, os.WNOHANG | os.WUNTRACED)
    return done == 0


def ended_by_sigquit(status):
    return status is not None and os.WIFSIGNALED(status) and os.WTERMSIG(status) == signal.SIGQUIT


def check_quit(app, mark, name):
    """The checks every quit by SIGQUIT has to pass."""
    status = app.wait_for_exit(20.0)
    check(ended_by_sigquit(status), name + ": the process ends by SIGQUIT")
    tail = app.out[mark:]
    order = [tail.find(FOCUS_REPORTS_OFF), tail.find(SHOW_CURSOR), tail.rfind(EXIT_ALT)]
    check(-1 not in order and order == sorted(order),
          name + ": the input modes off, the cursor shown, the alternate screen left, in order")
    check(b"crashed" not in tail and b"Backtrac" not in tail, name + ": no crash report")
    check(app.termios_now() == app.before, name + ": the termios is exactly what it was before the launch")


def spawn_child_file():
    """A path for IdleProbe to write its child's process ID to."""
    handle, path = tempfile.mkstemp(prefix="child-", dir=SCRATCH)
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


def is_zombie(pid):
    """Whether `pid` has ended and is only waiting to be reaped. The app's child is
    orphaned when the app ends, and in CI's Linux containers process 1 is not an
    init that reaps it, so signal 0 goes on finding it. Linux only: launchd reaps."""
    try:
        with open(f"/proc/{pid}/stat") as handle:
            # The state follows the command, which is in parentheses and may hold spaces.
            return handle.read().rpartition(")")[2].split()[0] == "Z"
    except (OSError, IndexError):
        return False


def child_ends(pid, seconds):
    """Whether process `pid` is gone within `seconds`; killed if it is not."""
    deadline = time.time() + seconds
    while time.time() < deadline:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return True
        if is_zombie(pid):
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


WHEN_WARNED = {"IDLE_PROBE_QUIT_CONFIRMATION": "whenWarned"}
QUIT_TITLE = b"Quit IdleProbe?"


def visible(data):
    """`data` without its escape sequences, as far as it matters for a phrase
    drawn in one run."""
    return re.sub(rb"\x1b\[[0-9;:?<>=]*[ -/]*[@-~]", b"", data)


def asks(app, mark):
    """Whether the quit dialog has been drawn since `mark`."""
    return QUIT_TITLE in visible(app.out[mark:])


def quit_cleanly(app, name):
    """⌃Q quits at once: status 0, the termios back."""
    os.write(app.master, b"\x11")
    status = app.wait_for_exit(20.0)
    check(status is not None and os.WIFEXITED(status) and os.WEXITSTATUS(status) == 0,
          name + ": ⌃Q quits, with status 0")
    check(app.termios_now() == app.before, name + ": the termios is back")


# 1. kill -QUIT: from outside, no dialog, whatever the app has said.
for env, name in (({}, "kill -QUIT"),
                  ({"IDLE_PROBE_QUIT_WARNING": "Uploading"}, "kill -QUIT, with a warning active")):
    app = App(env=env)
    app.settle()
    mark = len(app.out)
    os.kill(app.pid, signal.SIGQUIT)
    check_quit(app, mark, name)
    check(not asks(app, mark), name + ": no dialog")
    app.finish()

# 2–4. The termios, the keys, and ⌃\ with its dialog.
child_file = spawn_child_file()
app = App(env={"IDLE_PROBE_MODE": "keys", "IDLE_PROBE_CHILD_PIDFILE": child_file}, job=True)
DISABLED = os.fpathconf(app.slave, "PC_VDISABLE")
app.settle()
probe, child = child_of(child_file, app)
check_child_in_group(probe, child, app, "⌃\\")
check(is_raw(app.termios_now()) and quit_key_of(app.termios_now()) == DISABLED,
      "running: signals on, with the quit key given up to ask first")
check(not app.termios_now()[0] & termios.IXON, "running: flow control off, so ⌃Q is a key rather than XON")
for byte, name in ((b"\x1a", "ctrl-z"), (b"\x19", "ctrl-y"), (b"\x14", "ctrl-t")):
    os.write(app.master, byte)
    app.pump(0.6)
    check(("key " + name).encode() in app.out and running(app), name + " arrives as a key, and raises no signal")

# ⌃C: heard as a key, and then it asks, as nothing took it.
mark = len(app.out)
os.write(app.master, b"\x03")
app.pump(0.6)
check(b"key ctrl-c" in app.out and running(app), "ctrl-c arrives as a key, and raises no signal")
check(asks(app, mark), "ctrl-c: nothing takes it, so it asks")
# Escape stays.
mark = len(app.out)
os.write(app.master, b"\x1b")
app.pump(0.8)
check(running(app) and QUIT_TITLE not in visible(app.out[mark:]), "the dialog: Escape stays")

# ⌃\: the first asks, and touches nobody.
mark = len(app.out)
os.write(app.master, b"\x1c")
app.pump(0.6)
check(asks(app, mark), "⌃\\ on a responsive app: it asks")
check(running(app), "⌃\\ on a responsive app: nothing ends")
try:
    os.kill(child, 0)
    child_alive = True
except (OSError, TypeError):
    child_alive = False
check(child_alive, "⌃\\ on a responsive app: the app's child is left alone while it asks")
# The second, while it is up, quits at once.
mark = len(app.out)
os.write(app.master, b"\x1c")
check_quit(app, mark, "a second ⌃\\")
check(child is not None and child_ends(child, 3.0), "a second ⌃\\: the app's child ends with it")
app.finish()

# A second ⌃C while it is up: an ordinary quit, with status 0.
app = App(env={"IDLE_PROBE_MODE": "keys"})
app.settle()
mark = len(app.out)
os.write(app.master, b"\x03")
app.pump(0.6)
check(asks(app, mark) and b"again to quit" in visible(app.out[mark:]), "⌃C: it asks, and says a second ⌃C quits")
os.write(app.master, b"\x03")
status = app.wait_for_exit(20.0)
check(status is not None and os.WIFEXITED(status) and os.WEXITSTATUS(status) == 0,
      "a second ⌃C: an ordinary quit, with status 0")
app.finish()

# The dialog's own keys: Return stays, Tab and Return quits.
app = App(env={"IDLE_PROBE_MODE": "keys"})
app.settle()
os.write(app.master, b"\x03")
app.pump(0.5)
mark = len(app.out)
os.write(app.master, b"\r")
app.pump(0.8)
check(running(app) and QUIT_TITLE not in visible(app.out[mark:]), "the dialog: Return stays")
mark = len(app.out)
os.write(app.master, b"\x03")
app.pump(0.5)
check(asks(app, mark), "the dialog comes back on another ⌃C")
os.write(app.master, b"\t")
app.pump(0.3)
os.write(app.master, b"\r")
status = app.wait_for_exit(20.0)
check(status is not None and os.WIFEXITED(status) and os.WEXITSTATUS(status) == 0,
      "the dialog: Tab and Return quits, an ordinary quit with status 0")
check(app.termios_now() == app.before, "the dialog's quit: the termios is back")
check(EXIT_ALT in app.out[mark:], "the dialog's quit: the alternate screen left")
app.finish()

# 4b. A bracketed paste holding the quit key's byte: text, while the app reads the
# key; and the driver's, as in a shell, while the driver does.
app = App(env={"IDLE_PROBE_MODE": "keys"})
app.settle()
os.write(app.master, b"\x1b[200~pasted \x1c text\x1b[201~")
app.pump(1.0)
check(running(app) and not asks(app, 0), "a paste holding 0x1C: nothing happens")
app.finish()
app = App(env={"IDLE_PROBE_MODE": "keys", **WHEN_WARNED})
app.settle()
mark = len(app.out)
os.write(app.master, b"\x1b[200~pasted \x1c text\x1b[201~")
check_quit(app, mark, "whenWarned: a paste holding 0x1C")
app.finish()

# 5. A hung main thread: one ⌃\ ends it, about two seconds later, with the terminal back.
for env, name in (({}, "hung, ⌃\\"), (WHEN_WARNED, "whenWarned: hung, ⌃\\")):
    app = App(env={"IDLE_PROBE_MODE": "hang", **env})
    app.settle()
    check(b"hanging" in app.out and running(app), name + ": on screen, and hung")
    mark = len(app.out)
    os.write(app.master, b"\x1c")
    check_quit(app, mark, name)
    app.finish()

# A hang's other keys don't end it, and ⌃\ after them still does.
app = App(env={"IDLE_PROBE_MODE": "hang"})
app.settle()
os.write(app.master, b"abc")
app.pump(2.0)
check(running(app), "hung, other keys: nothing ends")
mark = len(app.out)
os.write(app.master, b"\x1c")
check_quit(app, mark, "hung, then ⌃\\")
app.finish()

# A slow frame: what was typed through it is read in order, and asks nothing.
app = App(env={"IDLE_PROBE_MODE": "keys", "IDLE_PROBE_STALL_KEY": "s"})
app.settle()
os.write(app.master, b"s")
app.pump(0.2)
os.write(app.master, b"a")
app.pump(2.3)  # past the watch's grace: the bytes are read for the loop
os.write(app.master, b"b")
app.pump(3.0)
check(running(app), "a slow frame: it goes on")
found_a, found_b = app.out.find(b"key a"), app.out.find(b"key b")
check(0 <= found_a < found_b, "a slow frame: keys from before and after the watch read them arrive, in order")
os.write(app.master, b"c")
app.pump(0.6)
check(b"key c" in app.out, "a slow frame: the loop hears keys after it")
quit_cleanly(app, "a slow frame")
app.finish()

# …and ⌃\ through one quits: the loop has not acknowledged it.
app = App(env={"IDLE_PROBE_MODE": "keys", "IDLE_PROBE_STALL_KEY": "s"})
app.settle()
os.write(app.master, b"s")
app.pump(0.2)
mark = len(app.out)
os.write(app.master, b"\x1c")
check_quit(app, mark, "a slow frame, ⌃\\")
app.finish()


# 6. The user's own stty: quit undefined.
def quit_undefined(attrs):
    attrs[6][termios.VQUIT] = bytes([DISABLED])


app = App(env={"IDLE_PROBE_MODE": "keys"}, setup=quit_undefined)
app.settle()
os.write(app.master, b"\x1c")
app.pump(1.5)
check(running(app) and b"key ctrl-\\" in app.out and not asks(app, 0),
      "stty quit undef: ⌃\\ ends nothing, asks nothing, and arrives as a key")
quit_cleanly(app, "stty quit undef")
check(cc(app.before, termios.VQUIT) == DISABLED, "stty quit undef: still off")
app.finish()

# 7. A suspend and resume.
app = App(env={"IDLE_PROBE_MODE": "keys"})
app.settle()
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
check(is_raw(app.termios_now()) and running(app), "resume: raw again")
mark = len(app.out)
os.write(app.master, b"\x1c")
app.pump(0.6)
check(asks(app, mark) and running(app), "after a resume, ⌃\\: it asks")
mark = len(app.out)
os.write(app.master, b"\x1c")
check_quit(app, mark, "after a resume, a second ⌃\\")
app.finish()

# 9. The app binds a chord the quit key's byte could be (the owner's rule,
# 2026-10-06): the driver's quit is masked, so the byte reaches the app, whose
# binding wins over the question too.
for bound, ran in (("4", b"key ran ctrl-4"), ("\\", b"key ran ctrl-\\")):
    name = "⌃" + bound + " bound"
    app = App(env={"IDLE_PROBE_MODE": "keys", "IDLE_PROBE_SHORTCUTS": bound})
    app.settle()
    running_attrs = app.termios_now()
    check(quit_key_of(running_attrs) == DISABLED and bool(running_attrs[3] & termios.ISIG),
          name + ": the quit key masked, signals still on")
    os.write(app.master, b"\x1c")
    app.pump(1.0)
    check(ran in app.out and running(app) and not asks(app, 0), name + ": 0x1C runs the binding, and asks nothing")
    quit_cleanly(app, name)
    app.finish()

# A binding that masks the quit key and does not take the byte itself (⌃⌥\):
# the unclaimed byte asks, and a second quits as the driver's would have.
app = App(env={"IDLE_PROBE_MODE": "keys", "IDLE_PROBE_SHORTCUTS": "M-\\"})
app.settle()
check(quit_key_of(app.termios_now()) == DISABLED, "⌃⌥\\ bound: the quit key masked")
mark = len(app.out)
os.write(app.master, b"\x1c")
app.pump(0.6)
check(asks(app, mark) and running(app), "⌃⌥\\ bound, unclaimed 0x1C: it asks")
mark = len(app.out)
os.write(app.master, b"\x1c")
check_quit(app, mark, "⌃⌥\\ bound, a second unclaimed 0x1C")
app.finish()

# Under `whenWarned` with no warning: the driver has the key, as in a shell.
child_file = spawn_child_file()
app = App(env={"IDLE_PROBE_MODE": "keys", "IDLE_PROBE_CHILD_PIDFILE": child_file, **WHEN_WARNED}, job=True)
app.settle()
probe, child = child_of(child_file, app)
check(quit_key_of(app.termios_now()) == 0x1C, "whenWarned: the driver keeps the quit key")
mark = len(app.out)
os.write(app.master, b"\x1c")
check_quit(app, mark, "whenWarned, ⌃\\")
check(child is not None and child_ends(child, 3.0), "whenWarned, ⌃\\: the driver ends the app's child with it")
app.finish()

app = App(env={"IDLE_PROBE_MODE": "keys", **WHEN_WARNED})
app.settle()
os.write(app.master, b"\x03")
status = app.wait_for_exit(20.0)
check(status is not None and os.WIFEXITED(status) and os.WEXITSTATUS(status) == 0, "whenWarned, ⌃C: quits at once")
app.finish()

# 11. ⌃Q: at once, unless something says otherwise.
app = App(env={"IDLE_PROBE_MODE": "keys"})
app.settle()
quit_cleanly(app, "⌃Q")
check(not asks(app, 0), "⌃Q: no dialog")
app.finish()

app = App(env={"IDLE_PROBE_MODE": "keys", "IDLE_PROBE_QUIT_CONFIRMATION": "always"})
app.settle()
os.write(app.master, b"\x11")
app.pump(0.6)
check(asks(app, 0) and running(app), ".always: ⌃Q asks")
app.finish()

app = App(env={"IDLE_PROBE_MODE": "keys", "IDLE_PROBE_QUIT_WARNING": "Uploading 6 photos"})
app.settle()
os.write(app.master, b"\x11")
app.pump(0.6)
check(asks(app, 0) and running(app), "a warning active: ⌃Q asks")
check(b"Uploading 6 photos" in visible(app.out), "a warning active: the dialog names it")
os.write(app.master, b"\x11")
app.pump(0.6)
check(running(app), "a warning active: ⌃Q again does not quit past the dialog")
mark = len(app.out)
os.write(app.master, b"\x1c")
check_quit(app, mark, "a warning active: ⌃\\ while it is up")
app.finish()

app = App(env={"IDLE_PROBE_MODE": "keys", "IDLE_PROBE_QUIT_WARNING": "Uploading", **WHEN_WARNED})
app.settle()
check(quit_key_of(app.termios_now()) == DISABLED, "whenWarned, a warning active: the quit key given up to ask first")
os.write(app.master, b"\x03")
app.pump(0.6)
check(asks(app, 0) and running(app), "whenWarned, a warning active: ⌃C asks")
app.finish()

# 8. The kitty keyboard protocol.
child_file = spawn_child_file()
app = App(env={"IDLE_PROBE_MODE": "keys", "IDLE_PROBE_CHILD_PIDFILE": child_file}, kitty=True, job=True)
app.settle()
check(app.stack == [31], "kitty: the flags are pushed")
probe, child = child_of(child_file, app)
check_child_in_group(probe, child, app, "kitty")
mark = len(app.out)
os.write(app.master, b"\x1b[92;5u")
app.pump(0.6)
check(asks(app, mark) and running(app), "kitty, ⌃\\ as a report: it asks")
mark = len(app.out)
# A key in the same read as the report: the thread that sent the signal goes
# no further (on Linux the handler may run on another thread after `kill`
# returns, and the batch would go on), so the key after it is never shown.
os.write(app.master, b"\x1b[92;5u\x1b[98u")
check_quit(app, mark, "kitty, a second ⌃\\ as a report")
check(b"\x1b[<u" in app.out[mark:] and app.stack == [], "kitty, a second ⌃\\ as a report: the flags popped")
check(b"key b" not in app.out[mark:], "kitty, a second ⌃\\ as a report: a key read with it does nothing more")
check(child is not None and child_ends(child, 3.0),
      "kitty, a second ⌃\\ as a report: the app's child ends with it, as the driver's ⌃\\ ends it")
app.finish()

# ⌃Q, as a report.
app = App(env={"IDLE_PROBE_MODE": "keys"}, kitty=True)
app.settle()
os.write(app.master, b"\x1b[113;5u")
status = app.wait_for_exit(20.0)
check(status is not None and os.WIFEXITED(status) and os.WEXITSTATUS(status) == 0 and app.stack == [],
      "kitty, ⌃Q as a report: quits, the flags popped")
app.finish()

# A hung app reads no report: the watch reads it for the loop.
app = App(env={"IDLE_PROBE_MODE": "hang"}, kitty=True)
app.settle()
check(app.stack == [31] and b"\x1b[<u" not in app.out and running(app),
      "kitty, hung, no key pressed: nothing popped")
mark = len(app.out)
os.write(app.master, b"\x1b[92;5u")
check_quit(app, mark, "kitty, hung, ⌃\\ as a report")
check(app.stack == [], "kitty, hung, ⌃\\ as a report: the flags popped on the way")
app.finish()

app = App(env={"IDLE_PROBE_MODE": "keys"}, kitty=True, setup=quit_undefined)
app.settle()
os.write(app.master, b"\x1b[92;5u")
app.pump(1.0)
check(b"key ctrl-\\" in app.out and running(app), "kitty, stty quit undef: the report is an ordinary key")
app.finish()

# 8b. The app's own ⌃\ wins over the quit (the owner's rule, 2026-10-06).
app = App(env={"IDLE_PROBE_MODE": "keys", "IDLE_PROBE_SHORTCUTS": "\\"}, kitty=True)
app.settle()
os.write(app.master, b"\x1b[92;5u")
app.pump(1.0)
check(b"key ran ctrl-\\" in app.out and running(app) and not asks(app, 0),
      "kitty, ⌃\\ bound: the report runs the binding, and quits nothing")
app.finish()

# 10. The stall watchdog, where the driver keeps the quit key (`whenWarned`):
# under the kitty keyboard protocol ⌃\ is a report only a running loop reads, so
# a thread pops the flags when input waits unread.
app = App(env={"IDLE_PROBE_MODE": "hang", **WHEN_WARNED}, kitty=True)
app.settle()
check(app.stack == [31] and b"\x1b[<u" not in app.out and running(app),
      "whenWarned, kitty, hung, no key pressed: nothing popped")
mark = len(app.out)
os.write(app.master, b"\x1b[92;5u")
app.pump(2.5)
check(b"\x1b[<u" in app.out[mark:] and app.stack == [] and running(app),
      "whenWarned, kitty, hung: input left unread pops the flags, and the report alone quits nothing")
mark = len(app.out)
os.write(app.master, b"\x1c")
check_quit(app, mark, "whenWarned, kitty, hung, then ⌃\\ as the driver's byte")
app.finish()

# A slow frame trips it too; the loop pushes the flags back, and the keys
# sent between, in both encodings, read right.
app = App(env={"IDLE_PROBE_MODE": "keys", "IDLE_PROBE_STALL_KEY": "s", **WHEN_WARNED}, kitty=True)
app.settle()
mark = len(app.out)
os.write(app.master, b"s")
app.pump(0.3)
os.write(app.master, b"\x1b[98u")
app.pump(2.2)
popped_at = app.out.find(b"\x1b[<u", mark)
check(popped_at >= 0 and app.stack == [], "whenWarned, kitty, a slow frame: input left unread pops the flags")
os.write(app.master, b"c")
app.pump(3.0)
check(popped_at >= 0 and b"\x1b[>31u" in app.out[popped_at:] and app.stack == [31],
      "whenWarned, kitty, a slow frame: the loop pushes them back when it reads again")
check(b"key b" in app.out and b"key c" in app.out and running(app),
      "whenWarned, kitty, a slow frame: a report from before the pop and a byte from after it both read")
os.write(app.master, b"\x11")
status = app.wait_for_exit(20.0)
check(status is not None and os.WIFEXITED(status) and app.stack == [] and app.termios_now() == app.before,
      "whenWarned, kitty, a slow frame: ⌃Q quits, the flags popped once, the termios exact")
app.finish()

# With the quit key asking first, nothing is popped: the watch needs no driver.
app = App(env={"IDLE_PROBE_MODE": "keys", "IDLE_PROBE_STALL_KEY": "s"}, kitty=True)
app.settle()
mark = len(app.out)
os.write(app.master, b"s")
app.pump(0.3)
os.write(app.master, b"\x1b[98u")
app.pump(4.0)
check(b"\x1b[<u" not in app.out[mark:] and app.stack == [31] and b"key b" in app.out,
      "kitty, a slow frame: nothing popped, and the report read by the loop")
app.finish()

# Masked for a ⌃\ binding of the app's, the driver could not quit on the byte:
# the watchdog stays disarmed, and the flags stay pushed through a stall.
app = App(env={"IDLE_PROBE_MODE": "keys", "IDLE_PROBE_STALL_KEY": "s", "IDLE_PROBE_SHORTCUTS": "\\", **WHEN_WARNED}, kitty=True)
app.settle()
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
app = App(env={"IDLE_PROBE_MODE": "keys", "IDLE_PROBE_STALL_KEY": "s", "IDLE_PROBE_SHORTCUTS": "4", **WHEN_WARNED}, kitty=True)
app.settle()
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
