#!/usr/bin/env python3
"""What a TUI app does with no terminal to draw on, and what `renderOnce`
writes where it goes. Against `IdleProbe`, the smallest app.

With no terminal:

  1. stdout a pipe, stdin a terminal: one line on stderr naming stdout, status 1
     within a second or two, and no byte in the pipe. (It used to sit there
     writing the alternate screen into the pipe until killed.)
  2. stdin `/dev/null`, a file or a pipe at end of file, stdout a terminal: the
     same, naming stdin, and no byte to the terminal.
  3. Neither a terminal: the same, naming both.
  4. `TERM=dumb` on a terminal: the same, naming TERM, and no escape code.
  5. A pipe or a file: `runWithoutTerminal` is asked (`IDLE_PROBE_NO_TERMINAL`),
     told what stdin and stdout are, can draw a view once, and its status is
     the process's.
  6. `Outcome.drawOnControllingTerminal`: stdin and stdout piped, a controlling
     terminal to draw on. The first line of stdin arrives, the answer goes down
     the pipe, the app draws on the terminal, and ⌃Q quits it with status 0.
     With no controlling terminal, it says so rather than hang.
  7. A terminal for both: it runs, untouched by any of this.

Then `renderOnce`, through the probe's report:

  8. Down a pipe: plain text, nothing moved, a newline at the end.
  9. `TUI_FORCE_ESCAPES=1` and `FORCE_COLOR=1` down a pipe: the escape sequences.
 10. On a terminal: from the line the cursor is on (no `CSI H`, no alternate
     screen), the shell's earlier output untouched, ending on the next line.

Usage:  python3 Tools/Smoke/no_terminal_smoke.py [path-to-IdleProbe]
Exits 0 when every case holds. Uses an isolated TUI_CONFIG_DIR.
"""

import atexit
import fcntl
import os
import re
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
ALT_SCREEN = b"\x1b[?1049"
ANY_ESCAPE = b"\x1b"

SCRATCH = tempfile.mkdtemp(prefix="tuikit-no-terminal-smoke-")
atexit.register(shutil.rmtree, SCRATCH, ignore_errors=True)

failures = []


def check(condition, label):
    print(("ok   " if condition else "FAIL ") + label)
    if not condition:
        failures.append(label)


def environment(**extra):
    env = {k: v for k, v in os.environ.items() if not k.startswith(("TERM_PROGRAM", "TMUX", "IDLE_PROBE"))}
    env.update({
        "TERM": "xterm-256color",
        "LANG": "en_US.UTF-8",
        "TUI_CONFIG_DIR": tempfile.mkdtemp(dir=SCRATCH),
    })
    for name in ("NO_COLOR", "FORCE_COLOR", "TUI_FORCE_ESCAPES"):
        env.pop(name, None)
    env.update(extra)
    return env


def become_session_leader_of(slave):
    """In a child: make `slave` the controlling terminal."""
    os.setsid()
    fcntl.ioctl(slave, termios.TIOCSCTTY, 0)


def pty_pair():
    master, slave = os.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
    return master, slave


def drain(master, seconds):
    out = b""
    until = time.time() + seconds
    while time.time() < until:
        ready, _, _ = select.select([master], [], [], 0.05)
        if not ready:
            continue
        try:
            data = os.read(master, 65536)
        except OSError:
            break
        if not data:
            break
        out += data
    return out


def run(env, stdin, stdout, stderr=subprocess.PIPE, timeout=8.0, preexec=None):
    """Runs the app to its end. Returns (status, stdout bytes, stderr text, seconds),
    the status None where it had to be killed."""
    started = time.time()
    process = subprocess.Popen(
        [BINARY], stdin=stdin, stdout=stdout, stderr=stderr, env=env, preexec_fn=preexec,
        start_new_session=preexec is None)
    try:
        out, err = process.communicate(timeout=timeout)
        return process.returncode, out or b"", (err or b"").decode(errors="replace"), time.time() - started
    except subprocess.TimeoutExpired:
        process.kill()
        out, err = process.communicate()
        return None, out or b"", (err or b"").decode(errors="replace"), time.time() - started


def one_line(text):
    return text.endswith("\n") and "\n" not in text[:-1] and text.count("\n") == 1


# 1. stdout a pipe, stdin a terminal.
master, slave = pty_pair()
status, out, err, seconds = run(environment(), slave, subprocess.PIPE)
check(status == 1, f"stdout a pipe: status 1 (got {status}, after {seconds:.1f} s)")
check(out == b"", f"stdout a pipe: not one byte down it (got {out[:40]!r})")
check(one_line(err) and "standard output" in err and "IdleProbe" in err, f"stdout a pipe: one line naming it: {err!r}")
check(drain(master, 0.2) == b"", "stdout a pipe: nothing to the terminal either")
os.close(master)
os.close(slave)

# 2. stdin not a terminal, stdout a terminal.
master, slave = pty_pair()
for name, stdin in (("/dev/null", subprocess.DEVNULL), ("an empty pipe", "pipe"), ("a file", "file")):
    if stdin == "pipe":
        read_end, write_end = os.pipe()
        os.close(write_end)
        stdin = read_end
    elif stdin == "file":
        path = os.path.join(SCRATCH, "input.txt")
        with open(path, "w") as handle:
            handle.write("data\n")
        stdin = os.open(path, os.O_RDONLY)
    status, _, err, seconds = run(environment(), stdin, slave)
    check(status == 1, f"stdin {name}: status 1 (got {status}, after {seconds:.1f} s)")
    check(one_line(err) and "standard input" in err, f"stdin {name}: one line naming it: {err!r}")
    check(drain(master, 0.2) == b"", f"stdin {name}: no byte to the terminal")
os.close(master)
os.close(slave)

# 3. Neither.
status, out, err, seconds = run(environment(), subprocess.DEVNULL, subprocess.PIPE)
check(status == 1 and out == b"", f"neither a terminal: status 1 and nothing written (got {status}, {out[:40]!r})")
check(one_line(err) and "input and output" in err, f"neither a terminal: one line naming both: {err!r}")

# 4. TERM=dumb on a terminal.
master, slave = pty_pair()
status, _, err, seconds = run(environment(TERM="dumb"), slave, slave)
check(status == 1, f"TERM=dumb: status 1 (got {status}, after {seconds:.1f} s)")
check(one_line(err) and "TERM" in err, f"TERM=dumb: one line naming TERM: {err!r}")
check(drain(master, 0.2) == b"", "TERM=dumb: no escape code to the terminal")
os.close(master)
os.close(slave)

# 5. An app with something to do instead.
status, out, err, _ = run(environment(IDLE_PROBE_NO_TERMINAL="report"), subprocess.DEVNULL, subprocess.PIPE)
check(status == 7, f"report: the app's status is the process's (got {status})")
check(b"input device, output pipe" in out, f"report: told what stdin and stdout are: {out[:60]!r}")
check(err == "", f"report: nothing on stderr: {err!r}")

# 8. renderOnce down a pipe: read off the same run.
check(out.endswith(b"second row\n"), f"renderOnce to a pipe: ends with a newline: {out[-30:]!r}")
check(out.startswith(b"input device"), f"renderOnce to a pipe: what the program printed first is first: {out[:30]!r}")
check(ANY_ESCAPE not in out, f"renderOnce to a pipe: plain text: {out!r}")
check(b"idle probe \xe2\x80\x94 report\n" in out, f"renderOnce to a pipe: no trailing spaces: {out!r}")

path = os.path.join(SCRATCH, "report.txt")
with open(path, "wb") as handle:
    status, _, _, _ = run(environment(IDLE_PROBE_NO_TERMINAL="report"), subprocess.DEVNULL, handle)
with open(path, "rb") as handle:
    written = handle.read()
check(status == 7 and b"input device, output file" in written and ANY_ESCAPE not in written,
      f"report to a file: told so, and plain text: {written[:60]!r}")

# 9. The escape sequences, asked for.
for name, value in (("TUI_FORCE_ESCAPES", "1"), ("FORCE_COLOR", "1")):
    status, out, _, _ = run(environment(IDLE_PROBE_NO_TERMINAL="report", **{name: value}), subprocess.DEVNULL, subprocess.PIPE)
    check(status == 7 and b"\x1b[" in out and b"\x1b[1;1H" not in out,
          f"{name}=1 down a pipe: the styling, and no cursor move: {out[-40:]!r}")

# 10. renderOnce on a terminal, from the line the cursor is on. Stdin is a pipe,
# so the app has no terminal to run on and reports.
master, slave = pty_pair()
env = environment(IDLE_PROBE_NO_TERMINAL="report")
process = subprocess.Popen([BINARY], stdin=subprocess.DEVNULL, stdout=slave, stderr=slave, env=env)
out = drain(master, 1.5)
process.wait(timeout=5)
tail = drain(master, 0.2)
out += tail
check(process.returncode == 7, f"renderOnce on a terminal: the status (got {process.returncode})")
check(ALT_SCREEN not in out, "renderOnce on a terminal: no alternate screen")
check(re.search(rb"\x1b\[\d*;?\d*H", out) is None, f"renderOnce on a terminal: no cursor move: {out!r}")
check(b"\x1b[" in out, "renderOnce on a terminal: styled")
check(out.endswith(b"\r\n"), f"renderOnce on a terminal: ends on the next line: {out[-20:]!r}")
os.close(master)
os.close(slave)

# 6. Drawing on the controlling terminal, in a pipeline.
master, slave = pty_pair()
in_read, in_write = os.pipe()
out_read, out_write = os.pipe()
os.write(in_write, b"a line of data\n")
env = environment(IDLE_PROBE_NO_TERMINAL="tty")
pid = os.fork()
if pid == 0:
    try:
        os.close(master)
        become_session_leader_of(slave)
        os.dup2(in_read, 0)
        os.dup2(out_write, 1)
        os.dup2(slave, 2)
        os.execve(BINARY, [BINARY], env)
    except Exception:
        pass
    os._exit(127)
os.close(out_write)
os.close(in_read)
screen = drain(master, 3.0)
check(ALT_SCREEN in screen, "controlling terminal: the app draws on it")
try:
    os.write(master, b"\x11")
except OSError:
    pass
screen += drain(master, 1.0)
deadline = time.time() + 5
status = None
while time.time() < deadline and status is None:
    done, wait_status = os.waitpid(pid, os.WNOHANG)
    if done == pid:
        status = wait_status
    else:
        time.sleep(0.05)
if status is None:
    os.kill(pid, signal.SIGKILL)
    os.waitpid(pid, 0)
check(status is not None and os.WIFEXITED(status) and os.WEXITSTATUS(status) == 0,
      f"controlling terminal: ⌃Q quits with status 0 (got {status})")
piped = os.read(out_read, 4096)
check(piped == b"from stdin: a line of data\n", f"controlling terminal: stdin's data, and its answer down the pipe: {piped!r}")
check(ALT_SCREEN + b"l" in screen, "controlling terminal: the alternate screen left")
os.close(master)
os.close(slave)
os.close(in_write)
os.close(out_read)

# With none, the app is told, and may say so itself.
status, out, _, _ = run(environment(IDLE_PROBE_NO_TERMINAL="tty"), subprocess.DEVNULL, subprocess.PIPE)
check(status == 8 and b"no controlling terminal" in out, f"no controlling terminal: the app is told (got {status}, {out!r})")

# 7. A terminal for both.
master, slave = pty_pair()
pid = os.fork()
if pid == 0:
    try:
        os.close(master)
        become_session_leader_of(slave)
        for fd in (0, 1, 2):
            os.dup2(slave, fd)
        os.execve(BINARY, [BINARY], environment(IDLE_PROBE_NO_TERMINAL="report"))
    except Exception:
        pass
    os._exit(127)
screen = drain(master, 2.5)
check(ALT_SCREEN + b"h" in screen and b"report" not in screen, "a terminal for both: it runs, and is not asked")
os.write(master, b"\x11")
screen += drain(master, 1.0)
deadline = time.time() + 5
status = None
while time.time() < deadline and status is None:
    done, wait_status = os.waitpid(pid, os.WNOHANG)
    if done == pid:
        status = wait_status
    else:
        time.sleep(0.05)
if status is None:
    os.kill(pid, signal.SIGKILL)
    os.waitpid(pid, 0)
check(status is not None and os.WIFEXITED(status) and os.WEXITSTATUS(status) == 0, "a terminal for both: ⌃Q quits")
os.close(master)
os.close(slave)

if failures:
    print(f"\n{len(failures)} failure(s)")
    sys.exit(1)
print("\nall checks passed")
