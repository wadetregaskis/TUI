"""`termios`, as much of it as the probes use, over the Windows console's modes.

Windows has no termios: a console has modes on its input and output handles
instead (`GetConsoleMode`/`SetConsoleMode`). With virtual-terminal input on, the
console hands a program the bytes a POSIX terminal would send — keys, mouse
reports and the terminal's replies to queries — so a probe that reads replies
with `os.read` works unchanged once raw mode is set the console's way. That is
what this module and `tty.py` beside it do, for `run.py`, which puts them ahead
of the standard library's on the path.

It also teaches `select.select` to wait on the console, which the standard
library's cannot (it takes sockets only on Windows): every probe that reads a
reply with a timeout asks `select` first.

The attributes `tcgetattr` returns are opaque here: a probe saves them and hands
them back to `tcsetattr`, which is all the probes do with them.
"""
import ctypes
import msvcrt
import os
import select as _select
import time
from ctypes import wintypes

kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

TCSANOW, TCSADRAIN, TCSAFLUSH = 0, 1, 2
ISIG, NOFLSH = 0x1, 0x80

ENABLE_PROCESSED_INPUT = 0x0001
ENABLE_LINE_INPUT = 0x0002
ENABLE_ECHO_INPUT = 0x0004
ENABLE_WINDOW_INPUT = 0x0008
ENABLE_MOUSE_INPUT = 0x0010
ENABLE_QUICK_EDIT_MODE = 0x0040
ENABLE_EXTENDED_FLAGS = 0x0080
ENABLE_VIRTUAL_TERMINAL_INPUT = 0x0200
ENABLE_PROCESSED_OUTPUT = 0x0001
ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004
DISABLE_NEWLINE_AUTO_RETURN = 0x0008
CP_UTF8 = 65001
KEY_EVENT = 0x0001
WAIT_OBJECT_0 = 0


class error(Exception):
    pass


kernel32.GetStdHandle.restype = wintypes.HANDLE
kernel32.GetConsoleMode.argtypes = [wintypes.HANDLE, ctypes.POINTER(wintypes.DWORD)]
kernel32.SetConsoleMode.argtypes = [wintypes.HANDLE, wintypes.DWORD]
kernel32.WaitForSingleObject.argtypes = [wintypes.HANDLE, wintypes.DWORD]
kernel32.WaitForSingleObject.restype = wintypes.DWORD
kernel32.GetNumberOfConsoleInputEvents.argtypes = [wintypes.HANDLE, ctypes.POINTER(wintypes.DWORD)]


class KEY_EVENT_RECORD(ctypes.Structure):
    _fields_ = [
        ("bKeyDown", wintypes.BOOL), ("wRepeatCount", wintypes.WORD), ("wVirtualKeyCode", wintypes.WORD),
        ("wVirtualScanCode", wintypes.WORD), ("UnicodeChar", wintypes.WCHAR), ("dwControlKeyState", wintypes.DWORD),
    ]


class _EVENT(ctypes.Union):
    _fields_ = [("KeyEvent", KEY_EVENT_RECORD), ("_pad", ctypes.c_byte * 16)]


class INPUT_RECORD(ctypes.Structure):
    _fields_ = [("EventType", wintypes.WORD), ("Event", _EVENT)]


kernel32.PeekConsoleInputW.argtypes = [wintypes.HANDLE, ctypes.POINTER(INPUT_RECORD), wintypes.DWORD,
                                       ctypes.POINTER(wintypes.DWORD)]
kernel32.ReadConsoleInputW.argtypes = kernel32.PeekConsoleInputW.argtypes


def _handle(fd):
    return msvcrt.get_osfhandle(fd)


def _output_handle():
    return kernel32.GetStdHandle(wintypes.DWORD(-11 & 0xFFFFFFFF))


def _mode(handle):
    mode = wintypes.DWORD()
    if not kernel32.GetConsoleMode(handle, ctypes.byref(mode)):
        raise error(f"not a console (Windows error {ctypes.get_last_error()})")
    return mode.value


def tcgetattr(fd):
    """The console's modes and code pages as they are: opaque, for `tcsetattr`."""
    return (_mode(_handle(fd)), _mode(_output_handle()), kernel32.GetConsoleCP(), kernel32.GetConsoleOutputCP())


def tcsetattr(fd, when, attributes):
    """Puts back what `tcgetattr` returned. `when` is ignored: a console has no
    queue of output to drain, and input waiting is left as it is."""
    input_mode, output_mode, input_cp, output_cp = attributes
    kernel32.SetConsoleMode(_handle(fd), input_mode | ENABLE_EXTENDED_FLAGS)
    kernel32.SetConsoleMode(_output_handle(), output_mode)
    kernel32.SetConsoleCP(input_cp)
    kernel32.SetConsoleOutputCP(output_cp)


def setraw(fd):
    """Raw mode, the console's way: as TUI's `ConsoleModes.raw(from:)` sets it.

    `PROBE_MOUSE_INPUT=0` leaves the console's mouse input off, for a probe that
    wants keys alone: with it on, Windows Terminal reports the pointer's motion
    even where nothing turned mouse reporting on, and a moved pointer fills the
    record with reports."""
    input_mode, output_mode, _, _ = tcgetattr(fd)
    input_mode &= ~(ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT | ENABLE_PROCESSED_INPUT | ENABLE_QUICK_EDIT_MODE)
    input_mode |= ENABLE_VIRTUAL_TERMINAL_INPUT | ENABLE_WINDOW_INPUT
    if os.environ.get("PROBE_MOUSE_INPUT") == "0":
        input_mode &= ~ENABLE_MOUSE_INPUT
    else:
        input_mode |= ENABLE_MOUSE_INPUT
    output_mode |= ENABLE_PROCESSED_OUTPUT | ENABLE_VIRTUAL_TERMINAL_PROCESSING | DISABLE_NEWLINE_AUTO_RETURN
    kernel32.SetConsoleMode(_handle(fd), input_mode | ENABLE_EXTENDED_FLAGS)
    kernel32.SetConsoleMode(_output_handle(), output_mode)
    kernel32.SetConsoleCP(CP_UTF8)
    kernel32.SetConsoleOutputCP(CP_UTF8)


def _is_console(fd):
    try:
        _mode(_handle(fd))
        return True
    except (error, OSError):
        return False


def _console_has_bytes(handle):
    """Whether a read of the console would return now: a key-down record with a
    character is waiting. Records that carry no bytes — key-ups, focus, menu and
    size records — are taken off the queue, or a read would block on them."""
    count = wintypes.DWORD()
    record = INPUT_RECORD()
    while True:
        if not kernel32.GetNumberOfConsoleInputEvents(handle, ctypes.byref(count)) or count.value == 0:
            return False
        if not kernel32.PeekConsoleInputW(handle, ctypes.byref(record), 1, ctypes.byref(count)) or count.value == 0:
            return False
        key = record.Event.KeyEvent
        if record.EventType == KEY_EVENT and key.bKeyDown and key.UnicodeChar != "\0":
            return True
        kernel32.ReadConsoleInputW(handle, ctypes.byref(record), 1, ctypes.byref(count))


def _console_select(fd, timeout):
    handle = _handle(fd)
    deadline = None if timeout is None else time.monotonic() + timeout
    while True:
        if _console_has_bytes(handle):
            return True
        left = None if deadline is None else deadline - time.monotonic()
        if left is not None and left <= 0:
            return False
        wait = 0xFFFFFFFF if left is None else max(1, int(left * 1000))
        kernel32.WaitForSingleObject(handle, min(wait, 50))


_standard_select = _select.select


def _select_with_consoles(rlist, wlist, xlist, timeout=None):
    """`select.select`, which also waits on a console in `rlist`: the probes'
    one readable descriptor is standard input."""
    consoles = [f for f in rlist if isinstance(f, int) and _is_console(f)]
    if not consoles:
        return _standard_select(rlist, wlist, xlist, timeout)
    ready = [f for f in consoles if _console_select(f, timeout)]
    return ready, list(wlist), []


_select.select = _select_with_consoles

_standard_write = os.write


def _is_console_input(fd):
    """Whether `fd` is a console's input: only an input handle has events."""
    count = wintypes.DWORD()
    try:
        return bool(kernel32.GetNumberOfConsoleInputEvents(_handle(fd), ctypes.byref(count)))
    except OSError:
        return False


def _write_through_console(fd, data):
    """`os.write`, where a write to the console's input goes to its output: a
    POSIX terminal's descriptor reads and writes, and the probes write their
    queries to the one they read the replies from; a console's input handle
    cannot be written."""
    if _is_console_input(fd):
        fd = 1
    return _standard_write(fd, data)


os.write = _write_through_console

_standard_open = os.open


def _open_with_tty(path, flags, mode=0o777, *, dir_fd=None):
    """`os.open`, where `/dev/tty` — the controlling terminal, which some probes
    open rather than use standard input — is the console's input, duplicated, so
    closing it closes nothing of the process's."""
    if path == "/dev/tty" and _is_console_input(0):
        return os.dup(0)
    return _standard_open(path, flags, mode, dir_fd=dir_fd)


os.open = _open_with_tty


def _ttyname(fd):
    """`os.ttyname`, which Windows lacks: a console's name is `CON`."""
    if _is_console(fd):
        return "CON"
    raise OSError(f"{fd} is not a console")


if not hasattr(os, "ttyname"):
    os.ttyname = _ttyname

_standard_get_terminal_size = os.get_terminal_size


def _get_terminal_size(fd=1):
    """`os.get_terminal_size`, which on Windows takes only 0, 1 and 2: any
    console descriptor is asked as standard output, the window's size."""
    if _is_console_input(fd) or (fd not in (0, 1, 2) and _is_console(fd)):
        fd = 1
    return _standard_get_terminal_size(fd)


os.get_terminal_size = _get_terminal_size

# `SIGALRM` and `setitimer`, which Windows has neither of, for the probes that put
# a hard limit on themselves: the alarm is `SIGINT`'s handler slot, raised in the
# main thread by a timer thread (`_thread.interrupt_main`), which runs whatever
# handler the probe installed for `SIGALRM`.
import _thread
import signal as _signal
import threading as _threading

if not hasattr(_signal, "SIGALRM"):
    _signal.SIGALRM = _signal.SIGINT
    _signal.ITIMER_REAL = 0
    _alarm = {"timer": None}

    def _setitimer(which, seconds, interval=0.0):
        if _alarm["timer"] is not None:
            _alarm["timer"].cancel()
            _alarm["timer"] = None
        if seconds > 0:
            timer = _threading.Timer(seconds, _thread.interrupt_main, args=(_signal.SIGINT,))
            timer.daemon = True
            timer.start()
            _alarm["timer"] = timer
        return (0.0, 0.0)

    def _alarm_seconds(seconds):
        _setitimer(0, float(seconds))
        return 0

    _signal.setitimer = _setitimer
    _signal.alarm = _alarm_seconds

# The window-size request, which `fcntl.py` beside this answers from the console.
TIOCGWINSZ = 0x5413
TIOCSWINSZ = 0x5414
