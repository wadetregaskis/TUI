#!/usr/bin/env python3
"""PTY check for BUGS13-POINTER-LEAVE: hover a help view in the Example app,
wait for its help, send a focus-out report (ESC [ O), and check the help goes
and stays gone; then focus-in and a move bring it back."""
import os, pty, select, sys, time, re, tempfile, struct, fcntl, termios
import pyte

binary = sys.argv[1]
cols, rows = 100, 40
helps = [l.split('"page.help.coverageHelp": ')[1].strip().rstrip(',').strip('"')
         for l in open(sys.argv[2]).read().splitlines() if '"page.help.coverageHelp"' in l]
config = tempfile.mkdtemp()
screen = pyte.Screen(cols, rows)
stream = pyte.ByteStream(screen)
pid, fd = pty.fork()
if pid == 0:
    env = dict(os.environ, TUI_CONFIG_DIR=config, TERM="xterm-256color", COLORTERM="truecolor")
    os.execve(binary, [binary, "--page", "help"], env)
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))

def pump(seconds):
    end = time.time() + seconds
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try:
                data = os.read(fd, 65536)
            except OSError:
                return
            # Answer nothing; pyte cannot parse colon sub-parameters, strip them.
            stream.feed(re.sub(rb"\x1b\[[0-9;:]*:[0-9;:]*m", b"", data))

def lines():
    return [screen.display[i] for i in range(rows)]

def shows_help():
    return any(h in line for line in lines() for h in helps)

pump(4.0)
target = None
for y, line in enumerate(lines()):
    if "87%" in line:
        target = (line.index("87%"), y)
if target is None:
    print("FAIL: coverage row not found"); print("\n".join(lines())); sys.exit(2)
x, y = target
os.write(fd, f"\x1b[<35;{x+1};{y+1}M".encode())   # motion, no button
pump(2.0)
before = shows_help()
os.write(fd, b"\x1b[O")                           # focus out
pump(1.5)
after = shows_help()
os.write(fd, b"\x1b[I")                           # focus in
pump(0.5)
still = shows_help()
os.write(fd, f"\x1b[<35;{x+2};{y+1}M".encode())
pump(2.0)
back = shows_help()
os.write(fd, b"q")
pump(0.5)
os.kill(pid, 9)
print(f"help before={before} after-focus-out={after} after-focus-in={still} after-move={back}")
sys.exit(0 if (before and not after and not still and back) else 1)
