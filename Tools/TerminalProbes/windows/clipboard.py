#!/usr/bin/env python3
"""This machine's clipboard on Windows, for `clipboard_probe.py`, as `pbpaste`,
`pbcopy` and `osascript -e 'clipboard info'` are on macOS:

    python clipboard.py read     # its text on standard output, exactly (UTF-8)
    python clipboard.py write    # standard input (UTF-8) as its text
    python clipboard.py list     # the names of the formats it holds, one a line

Through the Win32 clipboard API (`CF_UNICODETEXT`), so nothing is added or taken
away: PowerShell's `Get-Clipboard` ends what it prints with a line break. Exits 1
when the clipboard cannot be opened; `read` of a clipboard with no text prints
nothing.
"""
import ctypes
import sys
import time
from ctypes import wintypes

user32 = ctypes.WinDLL("user32", use_last_error=True)
kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
user32.OpenClipboard.argtypes = [wintypes.HWND]
user32.GetClipboardData.restype = wintypes.HANDLE
user32.GetClipboardData.argtypes = [wintypes.UINT]
user32.SetClipboardData.argtypes = [wintypes.UINT, wintypes.HANDLE]
user32.SetClipboardData.restype = wintypes.HANDLE
user32.EnumClipboardFormats.argtypes = [wintypes.UINT]
user32.EnumClipboardFormats.restype = wintypes.UINT
user32.GetClipboardFormatNameW.argtypes = [wintypes.UINT, wintypes.LPWSTR, ctypes.c_int]
kernel32.GlobalLock.argtypes = [wintypes.HGLOBAL]
kernel32.GlobalLock.restype = ctypes.c_void_p
kernel32.GlobalUnlock.argtypes = [wintypes.HGLOBAL]
kernel32.GlobalAlloc.argtypes = [wintypes.UINT, ctypes.c_size_t]
kernel32.GlobalAlloc.restype = wintypes.HGLOBAL

CF_UNICODETEXT = 13
GMEM_MOVEABLE = 0x0002
STANDARD = {1: "CF_TEXT", 2: "CF_BITMAP", 7: "CF_OEMTEXT", 8: "CF_DIB", 13: "CF_UNICODETEXT",
            15: "CF_HDROP", 16: "CF_LOCALE", 17: "CF_DIBV5"}


def opened():
    for _ in range(20):
        if user32.OpenClipboard(None):
            return True
        time.sleep(0.05)
    return False


def read():
    handle = user32.GetClipboardData(CF_UNICODETEXT)
    if not handle:
        return
    pointer = kernel32.GlobalLock(handle)
    try:
        text = ctypes.wstring_at(pointer)
    finally:
        kernel32.GlobalUnlock(handle)
    sys.stdout.buffer.write(text.encode("utf-8"))


def write():
    text = sys.stdin.buffer.read().decode("utf-8")
    data = ctypes.create_unicode_buffer(text)
    size = ctypes.sizeof(data)
    memory = kernel32.GlobalAlloc(GMEM_MOVEABLE, size)
    pointer = kernel32.GlobalLock(memory)
    ctypes.memmove(pointer, data, size)
    kernel32.GlobalUnlock(memory)
    user32.EmptyClipboard()
    if not user32.SetClipboardData(CF_UNICODETEXT, memory):
        raise SystemExit(1)


def formats():
    names, format_id = [], 0
    while True:
        format_id = user32.EnumClipboardFormats(format_id)
        if not format_id:
            break
        buffer = ctypes.create_unicode_buffer(256)
        if user32.GetClipboardFormatNameW(format_id, buffer, 256):
            names.append(buffer.value)
        else:
            names.append(STANDARD.get(format_id, f"#{format_id}"))
    sys.stdout.write("\n".join(names))


def main():
    action = sys.argv[1] if len(sys.argv) > 1 else "read"
    if not opened():
        raise SystemExit(1)
    try:
        {"read": read, "write": write, "list": formats}[action]()
    finally:
        user32.CloseClipboard()


if __name__ == "__main__":
    main()
