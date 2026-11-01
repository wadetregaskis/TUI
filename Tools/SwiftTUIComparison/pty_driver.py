"""Runs one program on a pseudo-terminal this script controls, and reads what it costs.

The terminal end answers the queries a real terminal would (as Ghostty does), so a framework takes the path it takes
in use. Costs come from the process itself: `proc_pid_rusage` for CPU, wakeups and memory, and `alloccount.c`, loaded
into the program with DYLD_INSERT_LIBRARIES, for allocations. macOS only.
"""
import ctypes
import fcntl
import mmap
import os
import pty
import re
import select
import signal
import struct
import termios
import time

SYNC_BEGIN = b'\x1b[?2026h'
SYNC_END = b'\x1b[?2026l'

_FIELDS = ['user', 'system', 'pkg_idle_wkups', 'interrupt_wkups', 'pageins', 'wired', 'resident', 'footprint',
           'start_abs', 'exit_abs', 'child_user', 'child_system', 'child_idle_wk', 'child_int_wk', 'child_pageins',
           'child_elapsed', 'diskread', 'diskwrite', 'qos_default', 'qos_maint', 'qos_bg', 'qos_util', 'qos_legacy',
           'qos_ui', 'qos_uint', 'billed_sys', 'serviced_sys', 'logical_writes', 'lifetime_max_footprint',
           'instructions', 'cycles', 'billed_energy', 'serviced_energy', 'interval_max_footprint', 'runnable']


class _RUsage(ctypes.Structure):
    _fields_ = ([('uuid', ctypes.c_ubyte * 16)] + [(f, ctypes.c_uint64) for f in _FIELDS]
                + [('reserved', ctypes.c_uint64 * 12)])


class _Timebase(ctypes.Structure):
    _fields_ = [('numer', ctypes.c_uint32), ('denom', ctypes.c_uint32)]


_libc = ctypes.CDLL('/usr/lib/libSystem.B.dylib', use_errno=True)
_timebase = _Timebase()
_libc.mach_timebase_info(ctypes.byref(_timebase))
# The user and system times are in mach ticks on Apple silicon, not nanoseconds (a 1 s spin read 1.04 s this way).
_TICK_NS = _timebase.numer / _timebase.denom
_RUSAGE_INFO_V4 = 4


def rusage(pid):
    """The process's counters, or None once it has gone."""
    info = _RUsage()
    if _libc.proc_pid_rusage(pid, _RUSAGE_INFO_V4, ctypes.byref(info)) != 0:
        return None
    counters = {f: getattr(info, f) for f in _FIELDS}
    counters['cpu_ns'] = (counters['user'] + counters['system']) * _TICK_NS
    return counters


_QUERY = re.compile(
    rb'\x1b\[(?P<da1>0?c)|\x1b\[>(?P<da2>0?c)|\x1b\[>(?P<xtver>0?q)|\x1b\[(?P<dsr>5n)|\x1b\[(?P<cpr>\??6n)|'
    rb'\x1b\[\?(?P<kbd>u)|\x1b\[\?(?P<decrqm>\d+)\$p|\x1b\](?P<osc>1[0-2]);\?(?:\x07|\x1b\\)|'
    rb'\x1b\[(?P<window>1[468])t')


def _answer(match, rows, cols):
    """What a terminal says back. Modes answer "known and reset": synchronized output is there to be turned on."""
    if match.group('da1') is not None:
        return b'\x1b[?62;22;52c'
    if match.group('da2') is not None:
        return b'\x1b[>1;10;0c'
    if match.group('xtver') is not None:
        return b'\x1bP>|ghostty 1.2.0\x1b\\'
    if match.group('dsr') is not None:
        return b'\x1b[0n'
    if match.group('cpr') is not None:
        return b'\x1b[1;1R'
    if match.group('kbd') is not None:
        return b'\x1b[?0u'
    if match.group('decrqm') is not None:
        return b'\x1b[?%d;2$y' % int(match.group('decrqm'))
    if match.group('osc') is not None:
        number = match.group('osc')
        return b'\x1b]' + number + (b';rgb:e0e0/e0e0/e0e0\x1b\\' if number == b'10' else b';rgb:1c1c/1c1c/1c1c\x1b\\')
    if match.group('window') is not None:
        which = match.group('window')
        if which == b'14':
            return b'\x1b[4;%d;%dt' % (rows * 20, cols * 10)
        if which == b'16':
            return b'\x1b[6;20;10t'
        return b'\x1b[8;%d;%dt' % (rows, cols)
    return b''


class App:
    """One running program. `pump` reads its output and answers its queries; `rusage` adds the allocation counts."""

    def __init__(self, path, work_dir, alloc_dylib, env=None, rows=50, cols=200):
        self.rows, self.cols = rows, cols
        home = os.path.join(work_dir, 'home')
        environment = {'PATH': os.environ['PATH'], 'HOME': home, 'TERM': 'xterm-256color', 'COLORTERM': 'truecolor',
                       'TERM_PROGRAM': 'ghostty', 'LANG': 'en_US.UTF-8',
                       'TUI_CONFIG_DIR': os.path.join(home, 'tui-config'), 'SWIFTTUI_COMPANION': 'off'}
        os.makedirs(environment['TUI_CONFIG_DIR'], exist_ok=True)
        self._alloc_path = os.path.join(work_dir, f'alloc-count-{os.getpid()}-{time.monotonic_ns()}')
        with open(self._alloc_path, 'wb') as out:
            out.write(b'\0' * 4096)
        self._alloc_file = open(self._alloc_path, 'r+b')
        self._alloc_map = mmap.mmap(self._alloc_file.fileno(), 4096)
        environment['DYLD_INSERT_LIBRARIES'] = alloc_dylib
        environment['ALLOC_COUNT_FILE'] = self._alloc_path
        environment.update(env or {})
        environment = {k: v for k, v in environment.items() if v is not None}
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', rows, cols, cols * 10, rows * 20))
        pid = os.fork()
        if pid == 0:
            os.setsid()
            fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
            os.dup2(slave, 0)
            os.dup2(slave, 1)
            # Stderr stays off the terminal: a framework's diagnostics would count as frame bytes.
            os.dup2(os.open('/dev/null', os.O_WRONLY), 2)
            os.close(master)
            os.execve(path, [path], environment)
        os.close(slave)
        self.pid, self.fd = pid, master
        self.spawned_at = time.perf_counter()
        fcntl.fcntl(master, fcntl.F_SETFL, fcntl.fcntl(master, fcntl.F_GETFL) | os.O_NONBLOCK)
        self._tail = b''
        self.total = 0
        self.transcript = bytearray()
        self.keep = False
        self.alive = True
        self.exit_status = None

    def write(self, data):
        try:
            os.write(self.fd, data)
        except OSError:
            self.alive = False

    def _handle(self, data):
        if self.keep:
            self.transcript += data
        self.total += len(data)
        buffer = self._tail + data
        for match in _QUERY.finditer(buffer):
            # A query straddling two reads is found once: only those ending past the old tail count.
            if match.end() <= len(self._tail):
                continue
            reply = _answer(match, self.rows, self.cols)
            if reply:
                self.write(reply)
        self._tail = buffer[-32:]

    def pump(self, timeout):
        """One read of up to `timeout` seconds: None when nothing came, b'' at the end, else (time, data)."""
        ready, _, _ = select.select([self.fd], [], [], timeout)
        if not ready:
            return None
        try:
            data = os.read(self.fd, 1 << 18)
        except BlockingIOError:
            return None
        except OSError:
            self.alive = False
            return b''
        if not data:
            self.alive = False
            return b''
        now = time.perf_counter()
        self._handle(data)
        return now, data

    def drain(self, seconds):
        end = time.perf_counter() + seconds
        while time.perf_counter() < end:
            self.pump(0.02)

    def wait_quiet(self, quiet, limit):
        """Read until `quiet` seconds of silence, or `limit`. A framework that keeps painting just reaches the limit."""
        start = time.perf_counter()
        last = start
        while True:
            now = time.perf_counter()
            if now - start > limit or now - last > quiet:
                return
            got = self.pump(0.01)
            if got == b'':
                return
            if got:
                last = got[0]

    def wait_for(self, needle, limit):
        """Read until `needle` appears in the output: the time it arrived, or None."""
        start = time.perf_counter()
        window = b''
        while time.perf_counter() - start < limit:
            got = self.pump(0.02)
            if got is None:
                continue
            if got == b'':
                return None
            window = (window + got[1])[-(1 << 16):]
            if needle in window:
                return got[0]
        return None

    def rusage(self):
        counters = rusage(self.pid)
        if counters is not None:
            counters['allocs'], counters['frees'], counters['alloc_bytes'] = struct.unpack('QQQ', self._alloc_map[:24])
        return counters

    def death(self):
        """How the program ended, if it has: a description, or None while it runs."""
        # The terminal closing comes a moment before the exit can be collected, longer if a signal handler is restoring it.
        deadline = time.time() + (5.0 if not self.alive else 0.0)
        while self.exit_status is None:
            pid, status = os.waitpid(self.pid, os.WNOHANG)
            if pid != 0:
                self.exit_status = status
            elif time.time() >= deadline:
                return None
            else:
                time.sleep(0.05)
        if os.WIFSIGNALED(self.exit_status):
            return f'died, signal {os.WTERMSIG(self.exit_status)}'
        return f'exited, status {os.WEXITSTATUS(self.exit_status)}'

    def stop(self):
        """End the program; returns its last counters, or None if it had gone."""
        final = self.rusage() if self.exit_status is None else None
        if self.exit_status is None:
            try:
                os.kill(self.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            start = time.time()
            while time.time() - start < 2 and self.exit_status is None:
                self.pump(0.02)
                self.death()
            if self.exit_status is None:
                try:
                    os.kill(self.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                _, self.exit_status = os.waitpid(self.pid, 0)
        try:
            os.close(self.fd)
        except OSError:
            pass
        self._alloc_map.close()
        self._alloc_file.close()
        os.unlink(self._alloc_path)
        return final


def marker(n):
    """The same 8 letters `marker(_:)` in Benchmark/Common.swift draws for `n`: all 8 differ from those of n ± 1, so a
    writer diffing cells has to send them all, and they can be found verbatim in the output."""
    letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    return ''.join(letters[(n + position * 3) % 26] for position in range(8))


def quantiles(values):
    """The median, the 95th percentile and the largest of a list, or None for an empty one."""
    if not values:
        return None
    ordered = sorted(values)
    at = lambda fraction: ordered[min(len(ordered) - 1, int(fraction * (len(ordered) - 1) + 0.5))]
    return {'med': at(0.5), 'p95': at(0.95), 'max': ordered[-1]}
