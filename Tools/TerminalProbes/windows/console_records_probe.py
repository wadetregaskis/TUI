#!/usr/bin/env python3
"""What the Windows console hands a program, record by record, while mouse
reporting is on: run through `run.py` (or `drive.py`), inside the terminal under
test.

    python Tools/TerminalProbes/windows/drive.py --host conhost windows/console_records_probe.py out.log

Sets raw mode as TUI does (`termios.py` beside this, `ConsoleModes.raw`), turns
on mouse reporting as TUI does (`CSI ? 1002 h`, `CSI ? 1006 h`, and XTSHIFTESCAPE
`CSI > 1 s`), then reads the console's input records with `ReadConsoleInputW` —
what TUI's `ConsoleInput` reads — and logs each one: a key record's direction,
virtual key, character and control-key state (Shift, Ctrl, Alt and the locks); a
mouse record's position, buttons, flags and state; a size, focus or menu record
by its type. A key-down record's characters are also gathered, so a mouse report
the console encoded as characters is logged whole beside the records that carried
it.

The question it was written for (2026-11-19): conhost reports a Shift-click as a
plain click, its Shift bit dropped from the SGR report. Do the records that carry
the report, or the Shift key's own records around them, say Shift was down?

`q` ends it; so does two minutes with nothing. Writes to $PROBE_OUT (default
./console_records_probe.log).
"""
import ctypes
import os
import sys
import termios
import time
from ctypes import wintypes

kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

KEY_EVENT, MOUSE_EVENT, WINDOW_BUFFER_SIZE_EVENT, MENU_EVENT, FOCUS_EVENT = 0x1, 0x2, 0x4, 0x8, 0x10
STATES = [(0x0010, "shift"), (0x0008, "lctrl"), (0x0004, "rctrl"), (0x0002, "lalt"), (0x0001, "ralt"),
          (0x0080, "caps"), (0x0020, "num"), (0x0040, "scroll"), (0x0100, "enhanced")]
MOUSE_FLAGS = [(0x1, "moved"), (0x2, "double"), (0x4, "wheel"), (0x8, "hwheel")]


class COORD(ctypes.Structure):
    _fields_ = [("X", wintypes.SHORT), ("Y", wintypes.SHORT)]


class KEY_EVENT_RECORD(ctypes.Structure):
    _fields_ = [("bKeyDown", wintypes.BOOL), ("wRepeatCount", wintypes.WORD), ("wVirtualKeyCode", wintypes.WORD),
                ("wVirtualScanCode", wintypes.WORD), ("UnicodeChar", wintypes.WCHAR),
                ("dwControlKeyState", wintypes.DWORD)]


class MOUSE_EVENT_RECORD(ctypes.Structure):
    _fields_ = [("dwMousePosition", COORD), ("dwButtonState", wintypes.DWORD),
                ("dwControlKeyState", wintypes.DWORD), ("dwEventFlags", wintypes.DWORD)]


class _EVENT(ctypes.Union):
    _fields_ = [("KeyEvent", KEY_EVENT_RECORD), ("MouseEvent", MOUSE_EVENT_RECORD), ("_pad", ctypes.c_byte * 16)]


class INPUT_RECORD(ctypes.Structure):
    _fields_ = [("EventType", wintypes.WORD), ("Event", _EVENT)]


kernel32.ReadConsoleInputW.argtypes = [wintypes.HANDLE, ctypes.POINTER(INPUT_RECORD), wintypes.DWORD,
                                       ctypes.POINTER(wintypes.DWORD)]
kernel32.WaitForSingleObject.argtypes = [wintypes.HANDLE, wintypes.DWORD]
kernel32.WaitForSingleObject.restype = wintypes.DWORD


def names(value, table):
    return "+".join(name for bit, name in table if value & bit) or "-"


def shown(text):
    return "".join("<ESC>" if c == "\x1b" else (f"<{ord(c):02X}>" if ord(c) < 0x20 else c) for c in text)


def main():
    import msvcrt
    out = open(os.environ.get("PROBE_OUT", "console_records_probe.log"), "a", encoding="utf-8", buffering=1)
    fd = sys.stdin.fileno()
    handle = msvcrt.get_osfhandle(fd)
    saved = termios.tcgetattr(fd)
    termios.setraw(fd)
    os.write(1, b"\x1b[2J\x1b[H  CONSOLE RECORDS PROBE - aim events here ('q' quits)\r\n")
    os.write(1, b"\x1b[?1000h\x1b[?1002h\x1b[?1006h\x1b[>1s")
    out.write(f"--- start {time.strftime('%Y-%m-%d %H:%M:%S')} WT_SESSION={'WT_SESSION' in os.environ} ---\n")
    record, count = INPUT_RECORD(), wintypes.DWORD()
    text, last = "", time.monotonic()
    try:
        while time.monotonic() - last < 120:
            if kernel32.WaitForSingleObject(handle, 1000) != 0:
                if text:
                    out.write(f"    text {shown(text)}\n")
                    text = ""
                continue
            if not kernel32.ReadConsoleInputW(handle, ctypes.byref(record), 1, ctypes.byref(count)) or not count.value:
                continue
            last = time.monotonic()
            kind = record.EventType
            if kind == KEY_EVENT:
                key = record.Event.KeyEvent
                char = key.UnicodeChar
                out.write(f"key {'down' if key.bKeyDown else 'up  '} vk=0x{key.wVirtualKeyCode:02X} "
                          f"scan=0x{key.wVirtualScanCode:02X} char={shown(char) if char != chr(0) else '-'} "
                          f"repeat={key.wRepeatCount} state={names(key.dwControlKeyState, STATES)}\n")
                if key.bKeyDown and char != "\0":
                    text += char
                    if char == "q" and not text.startswith("\x1b"):
                        break
                    if char.isalpha() and text.startswith("\x1b[<"):
                        out.write(f"    text {shown(text)}\n")
                        text = ""
            elif kind == MOUSE_EVENT:
                mouse = record.Event.MouseEvent
                out.write(f"mouse x={mouse.dwMousePosition.X} y={mouse.dwMousePosition.Y} "
                          f"buttons=0x{mouse.dwButtonState:08X} flags={names(mouse.dwEventFlags, MOUSE_FLAGS)} "
                          f"state={names(mouse.dwControlKeyState, STATES)}\n")
            else:
                out.write({WINDOW_BUFFER_SIZE_EVENT: "size\n", MENU_EVENT: "menu\n",
                           FOCUS_EVENT: "focus\n"}.get(kind, f"record type {kind}\n"))
    finally:
        os.write(1, b"\x1b[?1006l\x1b[?1002l\x1b[?1000l\x1b[>0s")
        termios.tcsetattr(fd, termios.TCSADRAIN, saved)
        out.write("--- end ---\n")
        out.close()


if __name__ == "__main__":
    main()
