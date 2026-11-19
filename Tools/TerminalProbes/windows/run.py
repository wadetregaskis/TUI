"""Runs a terminal probe on Windows, inside the terminal under test:

    python Tools/TerminalProbes/windows/run.py identity_probe.py [arguments]

Puts this directory's `termios` and `tty` — the console's modes standing in for
POSIX's — ahead of everything on the path, and the probes' own directory after
them (for `probe_stamp` and the rest), then runs the probe as `__main__`. The
probes themselves are unchanged. A probe that drives a pseudo-terminal of its own
(`pty`, `fcntl`) does not run here; one that runs inside the terminal and reads
its replies does.

`PROBE_OUT` names the record a probe writes, as on POSIX. The console's code page
is set to UTF-8 for the run, so what a probe prints is what it means.
`PROBE_MOUSE_INPUT=0` leaves the console's mouse input off, for a probe of keys
alone (`termios.setraw`). `console_records_probe.py` beside this is Windows's own:
it logs the console's input records themselves, not the bytes.
"""
import os
import runpy
import sys

here = os.path.dirname(os.path.abspath(__file__))
probes = os.path.dirname(here)
sys.path[:0] = [here, probes]
if len(sys.argv) < 2:
    raise SystemExit(__doc__)
probe = sys.argv[1]
if not os.path.isabs(probe) and not os.path.exists(probe):
    probe = os.path.join(probes, probe)
sys.argv = [probe] + sys.argv[2:]
sys.stdout.reconfigure(encoding="utf-8")
runpy.run_path(probe, run_name="__main__")
