#!/usr/bin/env python3
"""Do two presses read in one batch see what the first one's action did?

The run loop reads every input event waiting before it draws. A `.disabled`
written by a button's action takes effect in the next frame, so a second press
in the same batch used to reach a button still enabled, and ran the action
twice. SwiftUI applies the write first (measured:
`Tools/SwiftUIProbes/Disabled between queued events`). So the loop stops reading
after a control's action, draws, and carries on from the same event.

This is the only place the real loop can be seen doing it: `drainTerminalEvents`
is reached by nothing a unit test can drive, and `HeadlessApp` does not share
it. Runs `IdleProbe`'s `presses` mode (one control whose action disables it, and
a log of what the app did) on a PTY, every press of a case written in ONE write
so they arrive together, and checks:

  1. Each way of activating a control, twice in one write: the action runs once.
     With the `.disabled` left off it runs twice, so one is not a lost press.
  2. A disabling write made first thing in a `Task`: the same.
  3. A frame comes between the action and whatever was read behind it, and every
     event still arrives, in order.
  4. Typing, arrow keys and a paste are not activations: they stay one batch.
  5. A key held down on a button that stays enabled, with frames slower than the
     repeat: no press is lost, and it stops acting soon after the release, rather
     than working through a backlog of presses a frame at a time.
  6. Under a low frame-rate cap: input arriving while a frame waits for the cap
     is not lost, and the wait does not spin.

Usage:  python3 Tools/Smoke/activation_batch_smoke.py [path-to-IdleProbe]
Exits 0 when every case holds. Uses an isolated TUI_CONFIG_DIR, and no
core files (RLIMIT_CORE 0 in the child).
"""

import atexit
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

STRIPPED = (
    "TERM_PROGRAM", "TERM_PROGRAM_VERSION", "LC_TERMINAL", "LC_TERMINAL_VERSION",
    "TMUX", "TMUX_PANE", "TUI_TERM_PROGRAM",
)

RETURN = b"\r"
SPACE = b" "
DOWN = b"\x1b[B"

# The button is on the probe's second row. SGR reports, 1-based.
PRESS = b"\x1b[<0;4;2M"
RELEASE = b"\x1b[<0;4;2m"
CLICK = PRESS + RELEASE

failures = []
SCRATCH = tempfile.mkdtemp(prefix="tui-activation-smoke-")
atexit.register(shutil.rmtree, SCRATCH, ignore_errors=True)


def check(condition, label):
    print(("ok   " if condition else "FAIL ") + label)
    if not condition:
        failures.append(label)


class App:
    """The probe on a PTY, answering the terminal's half of the startup
    exchange, its log read back as (time, line) pairs."""

    def __init__(self, control, gated=True, **env):
        self.log_path = tempfile.mktemp(dir=SCRATCH)
        self.master, slave = os.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
        self.pending = b""
        child_env = {k: v for k, v in os.environ.items() if k not in STRIPPED}
        child_env.update({
            "TERM": "xterm-256color",
            "LANG": "en_US.UTF-8",
            "TUI_CONFIG_DIR": tempfile.mkdtemp(dir=SCRATCH),
            "IDLE_PROBE_MODE": "presses",
            "IDLE_PROBE_CONTROL": control,
            "IDLE_PROBE_GATED": "1" if gated else "0",
            "IDLE_PROBE_LOG": self.log_path,
        })
        child_env.update(env)
        self.pid = os.fork()
        if self.pid == 0:
            try:
                os.close(self.master)
                os.setsid()
                fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
                resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
                for fd in (0, 1, 2):
                    os.dup2(slave, fd)
                if slave > 2:
                    os.close(slave)
                os.execve(BINARY, [BINARY], child_env)
            except Exception:
                pass
            os._exit(127)  # exec failed: end here, never in this script's code or its cleanup
        os.close(slave)
        # On screen once the first frame is in the log, and settled once frames
        # have stopped coming: the focus lands a frame or two after the first, and
        # a press before that reaches nothing.
        deadline = time.time() + 15
        seen, quiet_since = 0, None
        while time.time() < deadline:
            self.pump(0.05)
            count = len(self.log()) if os.path.exists(self.log_path) else 0
            if count != seen or not count:
                seen, quiet_since = count, time.time()
            elif time.time() - quiet_since >= 0.4:
                return

    def pump(self, seconds):
        until = time.time() + seconds
        while time.time() < until:
            readable, _, _ = select.select([self.master], [], [], 0.02)
            if not readable:
                continue
            try:
                data = os.read(self.master, 65536)
            except OSError:
                return
            if not data:
                return
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

    def send(self, data, settle=0.6):
        os.write(self.master, data)
        self.pump(settle)

    def log(self):
        pairs = []
        with open(self.log_path) as handle:
            for line in handle:
                when, _, what = line.rstrip("\n").partition(" ")
                pairs.append((float(when), what))
        return pairs

    def lines(self, since=0):
        return [what for _, what in self.log()][since:]

    def runs(self):
        return sum(1 for what in self.lines() if what.startswith("ran "))

    def finish(self):
        os.kill(self.pid, signal.SIGTERM)
        deadline = time.time() + 3
        while time.time() < deadline:
            self.pump(0.05)
            done, _ = os.waitpid(self.pid, os.WNOHANG)
            if done == self.pid:
                os.close(self.master)
                return
        os.kill(self.pid, signal.SIGKILL)
        os.waitpid(self.pid, 0)
        os.close(self.master)


# 1 and 2. (label, control, what comes before the two presses, one press, env)
#
# A Link and a menu have no run with the `.disabled` off. A Link takes the presses
# of one quick burst for one, as it has its own reason to (`Link`), and a menu's
# second Return opens the menu again rather than choosing anything.
PRESSES = [
    ("Return on a focused button", "button", b"", RETURN, {}),
    ("Space on a focused button", "button", b"", SPACE, {}),
    ("a click on a button", "button", b"", CLICK, {}),
    ("a keyboardShortcut", "shortcut", b"", b"\x13", {}),
    ("a default action's Return", "default", b"", RETURN, {}),
    ("Space on a toggle", "toggle", b"", SPACE, {}),
    ("a click on a toggle", "toggle", b"", CLICK, {}),
    ("a click on an onTapGesture", "tap", b"", CLICK, {}),
    ("Return on a Link", "link", b"", RETURN, {}),
    ("a click on a Link", "link", b"", CLICK, {}),
    ("Return in an onSubmit field", "submit", b"", RETURN, {}),
    ("a menu item's Return", "menu", RETURN, RETURN, {}),
    ("Return, the write in a Task", "button", b"", RETURN, {"IDLE_PROBE_TASK_WRITE": "1"}),
    ("a click, the write in a Task", "button", b"", CLICK, {"IDLE_PROBE_TASK_WRITE": "1"}),
]

for label, control, opening, press, env in PRESSES:
    if control not in ("menu", "link"):
        app = App(control, gated=False, **env)
        app.send(opening + press + press)
        check(app.runs() == 2, f"{label}: with no .disabled, two presses in one write run it twice ({app.runs()})")
        app.finish()
    app = App(control, **env)
    if opening:
        app.send(opening)
    app.send(press + press)
    check(app.runs() == 1, f"{label}: the action's .disabled stops the second press ({app.runs()})")
    app.finish()

# 3. Order, and a frame between.
app = App("button", gated=False)
start = len(app.lines())
app.send(b"a" + RETURN + b"b" + RETURN + b"c")
events = app.lines(start)
presses = [what for what in events if not what.startswith("body")]
# `key` is an ancestor's `onKeyEvent`, which hears a key before the focused control.
check(presses == ["key character(\"a\")", "key enter", "ran 1", "key character(\"b\")", "key enter", "ran 2",
                  "key character(\"c\")"],
      f"events behind an action all arrive, in order ({presses})")
first, second = events.index("ran 1"), events.index("key character(\"b\")")
check("body 0" in events[first:second], "a frame comes between an action and the event behind it")
app.finish()

# A menu opened and chosen from in one write: the Return that opens it gets a
# frame, so the next one finds the menu there.
app = App("menu")
app.send(RETURN + RETURN)
check(app.runs() == 1, f"Return Return opens a menu and chooses its item ({app.runs()})")
app.finish()

# Twenty activations behind one another, none lost.
app = App("button", gated=False)
app.send(RETURN * 20, settle=1.5)
check(app.runs() == 20, f"twenty presses in one write, every one runs ({app.runs()})")
app.finish()

# 4. Not activations: one batch, so a frame or two, however many events.
app = App("field")
before = len(app.lines())
text = b"abcdefghij" * 10
app.send(text)
frames = [what for what in app.lines(before) if what.startswith("body")]
check(frames and frames[-1] == "body 100", f"typing: every character arrives ({frames[-1:]})")
check(len(frames) <= 4, f"typing: a hundred characters in one write stay one batch ({len(frames)} frames)")
app.finish()

app = App("field")
before = len(app.lines())
app.send(b"\x1b[200~" + b"pasted words\rand a return" + b"\x1b[201~")
frames = [what for what in app.lines(before) if what.startswith("body")]
check(len(frames) <= 3, f"paste: a pasted text is one event ({len(frames)} frames)")
app.finish()

app = App("list")
before = len(app.lines())
app.send(DOWN * 60)
frames = [what for what in app.lines(before) if what.startswith("body")]
check(len(frames) <= 4, f"arrow keys: sixty in one write stay one batch ({len(frames)} frames)")
app.finish()

# 5. A held key on slow frames: 100 ms a frame against a repeat every 33 ms, three
# seconds of it. Stopping for a frame after every press, with nothing else, would
# finish six seconds after the release, a press at a time.
app = App("button", gated=False, IDLE_PROBE_FRAME_MS="100")
start = time.time()
count = 0
while time.time() - start < 3.0:
    os.write(app.master, RETURN)
    count += 1
    app.pump(max(0, start + count * 0.033 - time.time()))
released = time.time()
app.pump(4.0)
times = [when for when, what in app.log() if what.startswith("ran ")]
late = times[-1] - released if times else None
print(f"     held {count} presses over 3 s on 100 ms frames: {len(times)} ran, the last {late:.2f} s after the release")
check(len(times) == count, f"a held key on slow frames loses no press ({len(times)} of {count})")
# With no limit it was still acting four seconds after the release, so 1.5 s tells
# the two apart on a machine busy enough to stretch the frames.
check(late is not None and late < 1.5, f"a held key on slow frames stops soon after the release ({late:.2f} s)")
app.finish()

# 6. The frame-rate cap. At five frames a second the frames behind an action wait
# their turn, input keeps arriving while they do, and the wait neither spins nor
# loses it. (A byte left unread on the descriptor while the loop waits would wake
# the wait over and over: the read source is level-triggered.)
before = resource.getrusage(resource.RUSAGE_CHILDREN)
app = App("button", gated=False, IDLE_PROBE_MAX_FPS="5")
presses = 10
start = time.time()
for _ in range(presses):
    os.write(app.master, RETURN)
    app.pump(0.15)
app.pump(1.5)
log = app.log()
times = [when for when, what in log if what.startswith("ran ")]
frames = [when for when, what in log if what.startswith("body") and when >= start]
gaps = [later - earlier for earlier, later in zip(frames, frames[1:])]
app.finish()
after = resource.getrusage(resource.RUSAGE_CHILDREN)
cpu = (after.ru_utime + after.ru_stime) - (before.ru_utime + before.ru_stime)
print(f"     cap of 5 FPS: {len(times)} of {presses} ran, {len(frames)} frames, closest {min(gaps):.3f} s apart, "
      f"{cpu:.2f} s of CPU in all")
check(len(times) == presses, f"under a low cap, nothing is lost ({len(times)} of {presses})")
check(min(gaps) >= 0.18, f"under a low cap, the frames keep to it ({min(gaps):.3f} s apart at the closest)")
check(cpu < 1.0, f"under a low cap, the wait for the frame does not spin ({cpu:.2f} s of CPU in about 3 s)")

if failures:
    print(f"\n{len(failures)} failure(s)")
    sys.exit(1)
print("\nall checks passed")
