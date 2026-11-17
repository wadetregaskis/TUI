"""`tty.setraw`, over the Windows console's modes: see `termios.py` beside it."""
from termios import setraw  # noqa: F401  (this directory's termios, by run.py's path)


def setcbreak(fd, when=None):
    setraw(fd)
