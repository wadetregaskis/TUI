"""Kills a measured program that passes a footprint limit.

A `Table` of 10,000 rows with no stated height reached a footprint of 25 GB on this tool's first run, on a 32 GB
machine shared with other builds. On by default. The killed run is recorded as an error, not lost.
"""
import os
import signal
import threading
import time

import pty_driver


class MemoryGuard:
    def __init__(self, limit_gb, interval=0.25):
        self.limit = limit_gb * 1e9
        self.interval = interval
        self.killed = {}
        self._watched = set()
        self._lock = threading.Lock()
        if self.limit > 0:
            threading.Thread(target=self._run, daemon=True).start()

    def watch(self, pid):
        with self._lock:
            self._watched.add(pid)

    def forget(self, pid):
        with self._lock:
            self._watched.discard(pid)

    def _run(self):
        while True:
            with self._lock:
                pids = list(self._watched)
            for pid in pids:
                counters = pty_driver.rusage(pid)
                if counters is not None and counters['footprint'] > self.limit:
                    self.killed[pid] = counters['footprint']
                    try:
                        os.kill(pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    self.forget(pid)
            time.sleep(self.interval)
