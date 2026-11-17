#!/usr/bin/env python3
"""Runs a probe inside a Windows terminal and waits for its record:

    python Tools/TerminalProbes/windows/drive.py --host wt identity_probe.py out.json [arguments]

`--env NAME=VALUE` (repeatable) sets a variable for the probe, `PROBE_ALT=1` say:
in the window itself, as a new Windows Terminal window has the running Terminal's
environment rather than this process's.

`--host wt` starts it in a new Windows Terminal window (`wt.exe -w new`),
`--host conhost` in a window of the classic console host (`conhost.exe`), which
Windows Terminal does not stand in for when it is started by name. The probe runs
through `probe.cmd` and `run.py` beside this file; the record goes where `out.json`
says, its errors to `out.json.stderr.txt`. Exits with the probe's status, or 124
when it did not finish within `--timeout` seconds.

PROBE_PYTHON is passed on (default: this Python), so the probe runs under the same
interpreter as this script.
"""
import argparse
import os
import shutil
import subprocess
import sys
import time

here = os.path.dirname(os.path.abspath(__file__))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", choices=["wt", "conhost"], default="wt")
    parser.add_argument("--timeout", type=float, default=120)
    parser.add_argument("--env", action="append", default=[], metavar="NAME=VALUE")
    parser.add_argument("probe")
    parser.add_argument("record")
    parser.add_argument("arguments", nargs=argparse.REMAINDER)
    args = parser.parse_args()

    record = os.path.abspath(args.record)
    for leftover in (record, record + ".done", record + ".stderr.txt"):
        if os.path.exists(leftover):
            os.remove(leftover)
    # The variables, and the probe, in a script of their own beside the record,
    # run in the window.
    script = record + ".cmd"
    lines = ["@echo off", f'set "PROBE_PYTHON={os.environ.get("PROBE_PYTHON", sys.executable)}"']
    lines += [f'set "{assignment}"' for assignment in args.env]
    quoted = " ".join(f'"{a}"' for a in [args.probe, record] + args.arguments)
    lines.append(f'call "{os.path.join(here, "probe.cmd")}" {quoted}')
    with open(script, "w", encoding="utf-8", newline="\r\n") as out:
        out.write("\n".join(lines) + "\n")
    command = ["cmd.exe", "/c", script]
    if args.host == "wt":
        wt = shutil.which("wt.exe") or os.path.expandvars(r"%LOCALAPPDATA%\Microsoft\WindowsApps\wt.exe")
        subprocess.Popen([wt, "-w", "new", "--title", "probe"] + command)
    else:
        subprocess.Popen(["conhost.exe"] + command)

    deadline = time.monotonic() + args.timeout
    while time.monotonic() < deadline:
        if os.path.exists(record + ".done"):
            time.sleep(0.2)
            with open(record + ".done", encoding="utf-8") as done:
                status = int(done.read().strip() or 0)
            errors = record + ".stderr.txt"
            if os.path.exists(errors) and os.path.getsize(errors):
                with open(errors, encoding="utf-8", errors="replace") as text:
                    sys.stderr.write(text.read())
            return status
        time.sleep(0.25)
    sys.stderr.write(f"drive.py: {args.probe} did not finish within {args.timeout:.0f} s\n")
    return 124


if __name__ == "__main__":
    sys.exit(main())
