#!/usr/bin/env python3
r"""What GNU screen and tmux pass on of an application's OSC 52 clipboard write.

Real keepers, measured against a SCRIPTED terminal: each keeper runs on a pty
whose master side this script plays (TERM=xterm-256color), a program in its
window writes one form of an OSC 52 write, and the script reads what the keeper
sends on to its terminal. This measures the keeper, not an emulator: whether a
terminal then writes the clipboard is `clipboard_probe.py`'s question, run in
that terminal. TUI's sequences are built exactly as `ClipboardSequence`
builds them (`Sources/TUIFoundation/App/ClipboardWriter.swift`).

  python3 keeper_passthrough_probe.py           # every case, both keepers
  python3 keeper_passthrough_probe.py screen    # one keeper
  PROBE_OUT=out.json python3 keeper_passthrough_probe.py

Cases, each with a fresh nonce payload:

  screen
    bare         OSC 52 as TUI sends it outside a keeper
    dcs-short    one DCS (`ESC P … ESC \`) around the write, BEL-terminated
    dcs-chunked  a 3 KiB write split into DCS strings of at most 256 bytes
    dcs-chunked-big  a 64 KiB write the same way
    dcs-whole-N  a write in ONE DCS of N bytes, for N in 252..4096: where screen
                 cuts it, which is the chunk limit to keep under

  tmux (a private server, `-f` a configuration of the case's own)
    bare-external     bare write, set-clipboard external (tmux's default)
    bare-on           bare write, set-clipboard on
    wrapped-off       `ESC P tmux; … ESC \` with allow-passthrough off (default)
    wrapped-on        the same with allow-passthrough on
    wrapped-on-big    a 64 KiB write the same way
    both-on           bare write with set-clipboard on AND allow-passthrough on:
                      how many writes reach the terminal

A case PASSES ON when the terminal receives `ESC ] 52 ; c ; <payload>` whole.
Writes JSON to $PROBE_OUT (default ./keeper_passthrough_probe.json) and prints
a summary. Needs `screen` and/or `tmux` on PATH; a missing one is skipped.
"""

import base64
import json
import os
import pty
import secrets
import select
import shutil
import subprocess
import sys
import tempfile
import time

ESC = "\x1b"
BEL = "\x07"
ST = ESC + "\\"


def payload(size):
    """A fresh nonce of `size` base64 characters (size a multiple of 4)."""
    raw = secrets.token_bytes(size // 4 * 3)
    return base64.b64encode(raw).decode()


def osc52(data, terminator=ST):
    return f"{ESC}]52;c;{data}{terminator}"


def screen_wrap(sequence, limit=256):
    """screen's DCS passthrough, chunked: each DCS string at most `limit`
    bytes including its `ESC P` and `ESC \\` (Chromium hterm's osc52.sh)."""
    room = limit - 4
    return "".join(f"{ESC}P{sequence[i:i + room]}{ST}" for i in range(0, len(sequence), room))


def tmux_wrap(sequence):
    """tmux's passthrough: `ESC P tmux;` the sequence with every ESC doubled, `ESC \\`."""
    return f"{ESC}Ptmux;{sequence.replace(ESC, ESC + ESC)}{ST}"


def run_on_pty(argv, env, seconds):
    """Runs `argv` on a fresh pty and returns everything it wrote to the
    terminal within `seconds`, answering nothing."""
    pid, fd = pty.fork()
    if pid == 0:
        os.execvpe(argv[0], argv, env)
    out = b""
    deadline = time.time() + seconds
    while time.time() < deadline:
        ready, _, _ = select.select([fd], [], [], 0.05)
        if ready:
            try:
                chunk = os.read(fd, 65536)
            except OSError:
                break
            if not chunk:
                break
            out += chunk
    try:
        os.kill(pid, 9)
    except ProcessLookupError:
        pass
    try:
        os.waitpid(pid, 0)
    except ChildProcessError:
        pass
    os.close(fd)
    return out


def writer_script(directory, text):
    """A program for the keeper's window that writes `text` to its terminal
    in one write, then waits for the keeper to pass it on."""
    path = os.path.join(directory, "write.py")
    data_path = os.path.join(directory, "write.bin")
    with open(data_path, "wb") as handle:
        handle.write(text.encode())
    with open(path, "w") as handle:
        handle.write(
            "import os, sys, time\n"
            f"data = open({data_path!r}, 'rb').read()\n"
            "time.sleep(0.5)\n"
            "os.write(1, data)\n"
            "time.sleep(2)\n")
    return path


def received(out, data):
    """How many times the terminal received the write of `data` whole, and
    what it received of OSC 52 at all."""
    whole = out.count(f"{ESC}]52;c;{data}".encode())
    starts = out.count(f"{ESC}]52;".encode())
    return whole, starts


def environment():
    env = {k: v for k, v in os.environ.items() if k not in ("TMUX", "TMUX_PANE", "STY", "WINDOW")}
    env["TERM"] = "xterm-256color"
    return env


def screen_cases():
    exe = shutil.which("screen")
    if not exe:
        return None
    version = subprocess.run([exe, "--version"], capture_output=True, text=True).stdout.strip()
    data = payload(64)
    big = payload(3072)
    huge = payload(65536)
    cases = [
        ("bare", data, osc52(data)),
        ("dcs-short", data, screen_wrap(osc52(data, BEL))),
        ("dcs-chunked", big, screen_wrap(osc52(big, BEL))),
        ("dcs-chunked-big", huge, screen_wrap(osc52(huge, BEL))),
    ]
    for size in (252, 256, 260, 300, 384, 512, 768, 1024, 4096):
        whole = payload(size - 12)
        cases.append((f"dcs-whole-{size}", whole, f"{ESC}P{osc52(whole, BEL)}{ST}"))
    results = []
    for name, data, text in cases:
        with tempfile.TemporaryDirectory() as directory:
            script = writer_script(directory, text)
            rc = os.path.join(directory, "screenrc")
            open(rc, "w").close()
            argv = [exe, "-c", rc, "-S", f"tuikit-probe-{os.getpid()}", sys.executable, script]
            out = run_on_pty(argv, environment(), 4)
        whole, starts = received(out, data)
        results.append({"case": name, "bytes": len(text), "passed_on_whole": whole, "osc52_starts": starts})
    return {"keeper": "screen", "version": version, "cases": results}


def tmux_cases():
    exe = shutil.which("tmux")
    if not exe:
        return None
    version = subprocess.run([exe, "-V"], capture_output=True, text=True).stdout.strip()
    data = payload(64)
    big = payload(65536)
    cases = [
        ("bare-external", data, osc52(data), {"set-clipboard": "external"}),
        ("bare-on", data, osc52(data), {"set-clipboard": "on"}),
        ("wrapped-off", data, tmux_wrap(osc52(data)), {"set-clipboard": "external"}),
        ("wrapped-on", data, tmux_wrap(osc52(data)), {"set-clipboard": "external", "allow-passthrough": "on"}),
        ("wrapped-on-big", big, tmux_wrap(osc52(big)), {"set-clipboard": "external", "allow-passthrough": "on"}),
        ("both-on", data, osc52(data), {"set-clipboard": "on", "allow-passthrough": "on"}),
    ]
    results = []
    for name, data, text, options in cases:
        with tempfile.TemporaryDirectory() as directory:
            script = writer_script(directory, text)
            conf = os.path.join(directory, "tmux.conf")
            with open(conf, "w") as handle:
                handle.write(f"set -s set-clipboard {options['set-clipboard']}\n")
                if "allow-passthrough" in options:
                    handle.write(f"set -gw allow-passthrough {options['allow-passthrough']}\n")
            socket = f"tuikit-probe-{os.getpid()}-{name}"
            argv = [exe, "-L", socket, "-f", conf, "new-session", f"{sys.executable} {script}"]
            out = run_on_pty(argv, environment(), 4)
            subprocess.run([exe, "-L", socket, "kill-server"], capture_output=True)
        whole, starts = received(out, data)
        results.append({
            "case": name, "options": options, "bytes": len(text), "passed_on_whole": whole,
            "osc52_starts": starts})
    return {"keeper": "tmux", "version": version, "cases": results}


def main():
    which = sys.argv[1:] or ["screen", "tmux"]
    report = {"date": time.strftime("%Y-%m-%d"), "uname": " ".join(os.uname()), "keepers": []}
    for keeper in which:
        result = {"screen": screen_cases, "tmux": tmux_cases}[keeper]()
        if result is None:
            print(f"{keeper}: not on PATH, skipped")
            continue
        report["keepers"].append(result)
        print(f"{keeper} ({result['version']})")
        for case in result["cases"]:
            verdict = "passes on" if case["passed_on_whole"] else "drops"
            print(f"  {case['case']:<16} {case['bytes']:>7} bytes  {verdict}"
                  f" (whole {case['passed_on_whole']}, OSC 52 starts {case['osc52_starts']})")
    path = os.environ.get("PROBE_OUT", "keeper_passthrough_probe.json")
    with open(path, "w") as handle:
        json.dump(report, handle, indent=2)
    print(f"wrote {path}")


if __name__ == "__main__":
    main()
