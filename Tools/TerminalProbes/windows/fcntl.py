"""`fcntl`, as much of it as the in-terminal probes use, on Windows: `ioctl` with
`TIOCGWINSZ`, answered from the console's window — rows and columns, and no
pixels, which a console does not report (TUI's `cellPixelSize()` is `nil` there
too). Anything else raises, as an `ioctl` the descriptor does not support would.
"""
import os
import struct

from termios import TIOCGWINSZ  # this directory's termios


def ioctl(fd, request, arg=0, mutate_flag=True):
    if request == TIOCGWINSZ:
        size = os.get_terminal_size(fd)
        packed = struct.pack("HHHH", size.lines, size.columns, 0, 0)
        if isinstance(arg, bytearray):
            arg[: len(packed)] = packed
            return 0
        return packed
    raise OSError(f"ioctl {request:#x} is not supported on a Windows console")


def fcntl(fd, cmd, arg=0):
    raise OSError("fcntl is not supported on a Windows console")


F_GETFL = 3
F_SETFL = 4
