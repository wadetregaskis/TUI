#!/usr/bin/env python3
"""Run a console program under a Windows pseudo console (ConPTY), as the
POSIX smoke tests run one under a `pty`: write keys to it, read what it draws,
resize it, and see how it ends.

Windows only, and only the standard library (ctypes): the POSIX smoke tests'
`pty`, `termios` and `fcntl` do not exist there. What the program writes comes
back as the pseudo console re-renders it — conhost redraws its own screen
buffer as escape sequences — so `Screen` keeps a grid of what is shown, enough
to find text on it; pyte, which the POSIX scripts use, is not needed.

As a library:

    from conpty import PseudoConsole
    with PseudoConsole([exe], cols=120, rows=40, env=env) as console:
        console.wait_for("Select a Demo")
        console.send("\\r")
        print(console.screen.text())

As a script, a walk: `conpty.py <exe> [keys...]`, each key one of the names in
KEYS, `wait<seconds>`, or literal text; prints the screen after each, and the
exit code at the end.
"""
import ctypes
import os
import re
import subprocess
import sys
import threading
import time
from ctypes import wintypes

if sys.platform != "win32":
    raise SystemExit("conpty.py drives a Windows pseudo console; on POSIX use the pty scripts")

kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

HPCON = wintypes.HANDLE
PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE = 0x00020016
EXTENDED_STARTUPINFO_PRESENT = 0x00080000
CREATE_UNICODE_ENVIRONMENT = 0x00000400
WAIT_TIMEOUT = 0x102
STILL_ACTIVE = 259
STARTF_USESTDHANDLES = 0x00000100


class COORD(ctypes.Structure):
    _fields_ = [("X", wintypes.SHORT), ("Y", wintypes.SHORT)]


class STARTUPINFOW(ctypes.Structure):
    _fields_ = [
        ("cb", wintypes.DWORD), ("lpReserved", wintypes.LPWSTR), ("lpDesktop", wintypes.LPWSTR),
        ("lpTitle", wintypes.LPWSTR), ("dwX", wintypes.DWORD), ("dwY", wintypes.DWORD),
        ("dwXSize", wintypes.DWORD), ("dwYSize", wintypes.DWORD), ("dwXCountChars", wintypes.DWORD),
        ("dwYCountChars", wintypes.DWORD), ("dwFillAttribute", wintypes.DWORD), ("dwFlags", wintypes.DWORD),
        ("wShowWindow", wintypes.WORD), ("cbReserved2", wintypes.WORD), ("lpReserved2", ctypes.c_void_p),
        ("hStdInput", wintypes.HANDLE), ("hStdOutput", wintypes.HANDLE), ("hStdError", wintypes.HANDLE),
    ]


class STARTUPINFOEXW(ctypes.Structure):
    _fields_ = [("StartupInfo", STARTUPINFOW), ("lpAttributeList", ctypes.c_void_p)]


class PROCESS_INFORMATION(ctypes.Structure):
    _fields_ = [
        ("hProcess", wintypes.HANDLE), ("hThread", wintypes.HANDLE),
        ("dwProcessId", wintypes.DWORD), ("dwThreadId", wintypes.DWORD),
    ]


kernel32.CreatePseudoConsole.argtypes = [COORD, wintypes.HANDLE, wintypes.HANDLE, wintypes.DWORD, ctypes.POINTER(HPCON)]
kernel32.CreatePseudoConsole.restype = ctypes.c_long
kernel32.ResizePseudoConsole.argtypes = [HPCON, COORD]
kernel32.ResizePseudoConsole.restype = ctypes.c_long
kernel32.ClosePseudoConsole.argtypes = [HPCON]
kernel32.CreatePipe.argtypes = [ctypes.POINTER(wintypes.HANDLE), ctypes.POINTER(wintypes.HANDLE), ctypes.c_void_p, wintypes.DWORD]
kernel32.InitializeProcThreadAttributeList.argtypes = [ctypes.c_void_p, wintypes.DWORD, wintypes.DWORD, ctypes.POINTER(ctypes.c_size_t)]
kernel32.UpdateProcThreadAttribute.argtypes = [ctypes.c_void_p, wintypes.DWORD, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_void_p]
kernel32.CreateProcessW.argtypes = [
    wintypes.LPCWSTR, wintypes.LPWSTR, ctypes.c_void_p, ctypes.c_void_p, wintypes.BOOL, wintypes.DWORD,
    ctypes.c_void_p, wintypes.LPCWSTR, ctypes.POINTER(STARTUPINFOW), ctypes.POINTER(PROCESS_INFORMATION),
]
kernel32.ReadFile.argtypes = [wintypes.HANDLE, ctypes.c_void_p, wintypes.DWORD, ctypes.POINTER(wintypes.DWORD), ctypes.c_void_p]
kernel32.WriteFile.argtypes = [wintypes.HANDLE, ctypes.c_void_p, wintypes.DWORD, ctypes.POINTER(wintypes.DWORD), ctypes.c_void_p]
kernel32.GetExitCodeProcess.argtypes = [wintypes.HANDLE, ctypes.POINTER(wintypes.DWORD)]
kernel32.WaitForSingleObject.argtypes = [wintypes.HANDLE, wintypes.DWORD]
kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
kernel32.GenerateConsoleCtrlEvent.argtypes = [wintypes.DWORD, wintypes.DWORD]
kernel32.TerminateProcess.argtypes = [wintypes.HANDLE, wintypes.UINT]

# The keys as a terminal sends them in its normal (not application) modes.
KEYS = {
    "down": "\x1b[B", "up": "\x1b[A", "left": "\x1b[D", "right": "\x1b[C",
    "enter": "\r", "esc": "\x1b", "tab": "\t", "space": " ", "backspace": "\x7f",
    "ctrl-c": "\x03", "ctrl-q": "\x11", "ctrl-backslash": "\x1c", "ctrl-z": "\x1a",
}


class Screen:
    """The grid a terminal would show for what the pseudo console writes: the
    printable text at the cursor, and the sequences conhost's renderer uses to
    move it and clear with. Everything else (colours, modes, titles) is read
    and dropped. One cell per character: wide characters are not modelled, so
    a row with emoji on it is shifted after them."""

    CSI = re.compile(r"\x1b\[([0-9;?<>=]*)([ -/]*)([@-~])")
    STRING = re.compile(r"\x1b[\]P_^X].*?(\x07|\x1b\\)", re.S)

    def __init__(self, cols, rows):
        self.cols, self.rows = cols, rows
        self.grid = [[" "] * cols for _ in range(rows)]
        self.x = self.y = 0
        self.pending = ""

    def resize(self, cols, rows):
        grid = [[" "] * cols for _ in range(rows)]
        for y in range(min(rows, self.rows)):
            for x in range(min(cols, self.cols)):
                grid[y][x] = self.grid[y][x]
        self.grid, self.cols, self.rows = grid, cols, rows
        self.x, self.y = min(self.x, cols - 1), min(self.y, rows - 1)

    def feed(self, text):
        data = self.pending + text
        self.pending = ""
        i = 0
        while i < len(data):
            c = data[i]
            if c == "\x1b":
                m = self.CSI.match(data, i)
                if m:
                    self.csi(m.group(1), m.group(3))
                    i = m.end()
                    continue
                m = self.STRING.match(data, i)
                if m:
                    i = m.end()
                    continue
                if i + 1 >= len(data) or (data[i + 1] in "[]P_^X"):
                    self.pending = data[i:]  # a sequence cut by the read
                    return
                i += 2  # ESC and one byte: ESC 7, ESC 8, ESC =, …
                continue
            if c == "\r":
                self.x = 0
            elif c == "\n":
                self.y = min(self.y + 1, self.rows - 1)
            elif c == "\b":
                self.x = max(0, self.x - 1)
            elif c >= " ":
                if self.x >= self.cols:
                    self.x, self.y = 0, min(self.y + 1, self.rows - 1)
                self.grid[self.y][self.x] = c
                self.x += 1
            i += 1

    def csi(self, params, final):
        numbers = [int(p) if p.isdigit() else 0 for p in params.lstrip("?").split(";")] if params else []

        def n(index, default=1):
            return numbers[index] if len(numbers) > index and numbers[index] else default

        if final in "Hf":
            self.y, self.x = min(n(0) - 1, self.rows - 1), min(n(1) - 1, self.cols - 1)
        elif final == "A":
            self.y = max(0, self.y - n(0))
        elif final == "B":
            self.y = min(self.rows - 1, self.y + n(0))
        elif final == "C":
            self.x = min(self.cols - 1, self.x + n(0))
        elif final == "D":
            self.x = max(0, self.x - n(0))
        elif final == "G":
            self.x = min(n(0) - 1, self.cols - 1)
        elif final == "d":
            self.y = min(n(0) - 1, self.rows - 1)
        elif final == "X":
            for x in range(self.x, min(self.cols, self.x + n(0))):
                self.grid[self.y][x] = " "
        elif final == "K":
            mode = n(0, 0)
            span = range(self.x, self.cols) if mode == 0 else range(0, self.x + 1) if mode == 1 else range(self.cols)
            for x in span:
                self.grid[self.y][x] = " "
        elif final == "J":
            mode = n(0, 0)
            rows = range(self.y + 1, self.rows) if mode == 0 else range(0, self.y) if mode == 1 else range(self.rows)
            if mode == 0:
                self.csi("", "K")
            for y in rows:
                self.grid[y] = [" "] * self.cols

    def text(self):
        return "\n".join("".join(row).rstrip() for row in self.grid)


class PseudoConsole:
    """A program running in a pseudo console of `cols` by `rows`."""

    def __init__(self, argv, cols=120, rows=40, env=None, cwd=None):
        self.screen = Screen(cols, rows)
        self.raw = bytearray()
        self._lock = threading.Lock()
        self._changed = threading.Event()

        in_read, in_write = wintypes.HANDLE(), wintypes.HANDLE()
        out_read, out_write = wintypes.HANDLE(), wintypes.HANDLE()
        if not kernel32.CreatePipe(ctypes.byref(in_read), ctypes.byref(in_write), None, 0):
            raise ctypes.WinError(ctypes.get_last_error())
        if not kernel32.CreatePipe(ctypes.byref(out_read), ctypes.byref(out_write), None, 0):
            raise ctypes.WinError(ctypes.get_last_error())
        self.console = HPCON()
        result = kernel32.CreatePseudoConsole(COORD(cols, rows), in_read, out_write, 0, ctypes.byref(self.console))
        if result != 0:
            raise OSError(f"CreatePseudoConsole failed: {result:#x}")
        # The pseudo console holds its own copies of its ends.
        kernel32.CloseHandle(in_read)
        kernel32.CloseHandle(out_write)
        self._in, self._out = in_write, out_read

        size = ctypes.c_size_t()
        kernel32.InitializeProcThreadAttributeList(None, 1, 0, ctypes.byref(size))
        self._attributes = ctypes.create_string_buffer(size.value)
        if not kernel32.InitializeProcThreadAttributeList(self._attributes, 1, 0, ctypes.byref(size)):
            raise ctypes.WinError(ctypes.get_last_error())
        if not kernel32.UpdateProcThreadAttribute(
            self._attributes, 0, PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE, self.console,
            ctypes.sizeof(HPCON), None, None
        ):
            raise ctypes.WinError(ctypes.get_last_error())
        startup = STARTUPINFOEXW()
        startup.StartupInfo.cb = ctypes.sizeof(STARTUPINFOEXW)
        # No standard handles of ours: a child that inherits a redirected one (a
        # pipe, under a CI runner or a shell's pipeline) reads and writes that
        # rather than its console. Null ones are its console's.
        startup.StartupInfo.dwFlags = STARTF_USESTDHANDLES
        startup.lpAttributeList = ctypes.cast(self._attributes, ctypes.c_void_p)

        block = None
        if env is not None:
            block = ctypes.create_unicode_buffer("".join(f"{k}={v}\0" for k, v in sorted(env.items())) + "\0")
        self.process = PROCESS_INFORMATION()
        command = ctypes.create_unicode_buffer(subprocess.list2cmdline(argv))
        if not kernel32.CreateProcessW(
            None, command, None, None, False, EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT,
            block, cwd, ctypes.byref(startup.StartupInfo), ctypes.byref(self.process)
        ):
            raise ctypes.WinError(ctypes.get_last_error())

        self._reader = threading.Thread(target=self._read, daemon=True)
        self._reader.start()

    def _read(self):
        buffer = ctypes.create_string_buffer(65536)
        decoder = __import__("codecs").getincrementaldecoder("utf-8")("replace")
        while True:
            count = wintypes.DWORD()
            if not kernel32.ReadFile(self._out, buffer, len(buffer), ctypes.byref(count), None) or count.value == 0:
                return
            data = buffer.raw[: count.value]
            with self._lock:
                self.raw += data
                self.screen.feed(decoder.decode(data))
            self._changed.set()

    def send(self, text):
        """Writes `text` to the program's input, as typed."""
        data = text.encode("utf-8")
        written = wintypes.DWORD()
        kernel32.WriteFile(self._in, data, len(data), ctypes.byref(written), None)

    def key(self, name):
        self.send(KEYS[name])

    def resize(self, cols, rows):
        kernel32.ResizePseudoConsole(self.console, COORD(cols, rows))
        with self._lock:
            self.screen.resize(cols, rows)

    def text(self):
        with self._lock:
            return self.screen.text()

    def wait_for(self, needle, timeout=15.0):
        """Waits until `needle` (a string or a compiled pattern) is on screen."""
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            shown = self.text()
            if (needle.search(shown) if hasattr(needle, "search") else needle in shown):
                return True
            if self.exit_code() is not None:
                return False
            self._changed.wait(0.1)
            self._changed.clear()
        return False

    def settle(self, quiet=0.5, timeout=10.0):
        """Waits until nothing has been drawn for `quiet` seconds."""
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            self._changed.clear()
            if not self._changed.wait(quiet):
                return True
        return False

    def exit_code(self):
        """The program's exit code, or None while it runs."""
        code = wintypes.DWORD()
        kernel32.GetExitCodeProcess(self.process.hProcess, ctypes.byref(code))
        return None if code.value == STILL_ACTIVE else code.value

    def wait_exit(self, timeout=10.0):
        kernel32.WaitForSingleObject(self.process.hProcess, int(timeout * 1000))
        return self.exit_code()

    def close(self):
        if self.exit_code() is None:
            kernel32.TerminateProcess(self.process.hProcess, 1)
        kernel32.ClosePseudoConsole(self.console)
        kernel32.CloseHandle(self._in)
        kernel32.CloseHandle(self.process.hProcess)
        kernel32.CloseHandle(self.process.hThread)

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    sys.stdout.reconfigure(encoding="utf-8")
    env = dict(os.environ)
    env.setdefault("TUI_CONFIG_DIR", os.path.join(os.environ.get("TEMP", "."), "tui-smoke-config"))
    with PseudoConsole([os.path.abspath(sys.argv[1])], env=env) as console:
        console.settle(quiet=1.0, timeout=20.0)
        print(console.text())
        for step in sys.argv[2:]:
            if step.startswith("wait"):
                time.sleep(float(step[4:]))
            elif step in KEYS:
                console.key(step)
            else:
                console.send(step)
            console.settle()
            print(f"\n=== after {step!r} (exit code {console.exit_code()}) ===")
            print(console.text())
        print(f"\nexit code: {console.wait_exit(3.0)}")


if __name__ == "__main__":
    main()
