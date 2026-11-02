#!/usr/bin/env python3
"""Runs a command as if this terminal had no Kitty graphics, and counts its bytes.

iTerm2 3.7.6 has no setting to turn its Kitty graphics off (none in its binary's
strings, 2026-11-02), and a host without them is what Sixel is for. So this sits on
the wire, as the terminal would: every APC the command writes is dropped, so no reply
comes, and the command's own handshake finds no Kitty and DA1's 4, by itself. Nothing
in the terminal's settings changes.

    python3 Tools/TerminalProbes/no_kitty_proxy.py -- COMMAND ARGUMENTS…

$PROXY_LOG   one JSON line a held frame (`?2026h` to `?2026l`): its bytes, how many
             of them are Sixel (DCS … q), and how many DCS, and at the end a total
$PROXY_KEYS  a file polled for keys to type at the command: its bytes go in once,
             each time it appears, and it is removed
$PROXY_KEEP_APC=1  counts and passes APCs on: the same bytes on any host, for a
             byte comparison with and without a path
"""
import fcntl
import json
import os
import select
import signal
import struct
import sys
import termios
import time
import tty

ESC = 0x1B


class Filter:
    """Drops APC strings; counts held frames. Bytes can split anywhere."""

    def __init__(self, keep_apc, log):
        self.keep_apc = keep_apc
        self.log = log
        self.state = "text"
        self.frame = {"bytes": 0, "sixel": 0, "dcs": 0, "apc": 0}
        self.total = dict(self.frame)
        self.tail = bytearray()
        self.started = time.time()
        self.dcs_is_sixel = False
        self.dcs_seen = 0

    def feed(self, data):
        out = bytearray()
        for byte in data:
            self.frame["bytes"] += 1
            if self.state == "esc":
                if byte == 0x5F:  # _ : APC
                    self.state = "apc"
                    self.frame["apc"] += 1
                    if self.keep_apc:
                        out += bytes([ESC, byte])
                    continue
                if byte == 0x50:  # P : DCS
                    self.state = "dcs"
                    self.dcs_is_sixel = False
                    self.dcs_seen = 0
                    self.frame["dcs"] += 1
                else:
                    self.state = "csi" if byte == 0x5B else "text"
                    self.tail = bytearray()
                out += bytes([ESC, byte])
                continue
            if self.state == "apc":
                if self.keep_apc:
                    out.append(byte)
                if byte == ESC:
                    self.state = "apc_esc"
                continue
            if self.state == "apc_esc":
                if self.keep_apc:
                    out.append(byte)
                self.state = "text" if byte == 0x5C else "apc"
                continue
            if self.state == "dcs":
                out.append(byte)
                self.dcs_seen += 1
                if byte == 0x71 and self.dcs_seen < 16:  # q
                    self.dcs_is_sixel = True
                if self.dcs_is_sixel:
                    self.frame["sixel"] += 1
                if byte == ESC:
                    self.state = "dcs_esc"
                continue
            if self.state == "dcs_esc":
                out.append(byte)
                self.state = "text" if byte == 0x5C else "dcs"
                continue
            if self.state == "csi":
                out.append(byte)
                self.tail.append(byte)
                if 0x40 <= byte <= 0x7E:
                    if bytes(self.tail) == b"?2026l":
                        self.end_frame()
                    self.state = "text"
                continue
            if byte == ESC:
                self.state = "esc"
                continue
            out.append(byte)
        return bytes(out)

    def end_frame(self):
        for key, value in self.frame.items():
            self.total[key] += value
        if self.log:
            self.log.write(json.dumps({"t": round(time.time() - self.started, 3), **self.frame}) + "\n")
            self.log.flush()
        self.frame = {"bytes": 0, "sixel": 0, "dcs": 0, "apc": 0}

    def finish(self):
        self.end_frame()
        if self.log:
            self.log.write(json.dumps({"total": self.total}) + "\n")
            self.log.close()


def set_size(fd):
    size = fcntl.ioctl(sys.stdin.fileno(), termios.TIOCGWINSZ, struct.pack("HHHH", 0, 0, 0, 0))
    fcntl.ioctl(fd, termios.TIOCSWINSZ, size)


def main():
    arguments = sys.argv[1:]
    if arguments[:1] == ["--"]:
        arguments = arguments[1:]
    if not arguments:
        sys.exit(__doc__)
    log_path = os.environ.get("PROXY_LOG")
    keys_path = os.environ.get("PROXY_KEYS")
    pid, fd = os.forkpty()
    if pid == 0:
        os.execvp(arguments[0], arguments)
    set_size(fd)
    signal.signal(signal.SIGWINCH, lambda *_: (set_size(fd), os.kill(pid, signal.SIGWINCH)))
    filter_ = Filter(os.environ.get("PROXY_KEEP_APC") == "1", open(log_path, "w") if log_path else None)
    stdin = sys.stdin.fileno()
    saved = termios.tcgetattr(stdin)
    tty.setraw(stdin)
    try:
        while True:
            try:
                ready, _, _ = select.select([fd, stdin], [], [], 0.1)
            except InterruptedError:
                continue
            if fd in ready:
                try:
                    data = os.read(fd, 1 << 16)
                except OSError:
                    break
                if not data:
                    break
                out = filter_.feed(data)
                while out:
                    written = os.write(sys.stdout.fileno(), out)
                    out = out[written:]
            if stdin in ready:
                os.write(fd, os.read(stdin, 4096))
            if keys_path and os.path.exists(keys_path):
                with open(keys_path, "rb") as keys:
                    os.write(fd, keys.read())
                os.remove(keys_path)
    finally:
        filter_.finish()
        termios.tcsetattr(stdin, termios.TCSADRAIN, saved)


if __name__ == "__main__":
    main()
