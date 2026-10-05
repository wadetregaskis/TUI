#!/usr/bin/env python3
"""OSC 52 clipboard-write probe: does this terminal put an application's OSC 52
on the clipboard, how large a copy does it take, what does an empty or
malformed payload do to the clipboard, and does it say so in its Device
Attributes?

TUIkit copies through OSC 52 where a terminal is known to write it, and through
the system clipboard helper only when the terminal is on this machine (see
`ClipboardWriter` and Documentation/Terminal-compatibility.md, "OSC 52
clipboard writes"). This measures what that table rests on.

Run INSIDE the terminal under test. Nothing here needs TUIkit built.

  python3 clipboard_probe.py                # leak, identity, write, ceiling
  python3 clipboard_probe.py --destructive  # ...and the empty and malformed
                                            #    payloads, which may CLEAR it
  python3 clipboard_probe.py --manual       # no helper to read the clipboard
                                            #    back (ssh): paste when asked

Writes JSON to $PROBE_OUT (default ./clipboard_probe.json) and prints a
summary. `PROBE_ALT=1` runs on the alternate screen, where TUIkit draws.

**Self-verifying where it can be.** On the machine whose clipboard the
terminal writes, the read-back is `pbpaste` (macOS), `wl-paste` (Wayland), or
`xclip`/`xsel` (X11), so no person is needed. Over ssh the clipboard written is
the user's, on the far side: `--manual` writes the nonce and asks for it to be
pasted back. The clipboard's contents before the run are restored at the end
where a helper can write it (never in `--manual`).

1. **Leak.** The cursor column (DSR 6) before and after an OSC 52 write, as
   `hyperlink_probe.py` asks it of OSC 8. A column that moved means the host
   printed part of the sequence. Every host the compatibility doc measured
   swallows unknown OSC numbers, so this is expected clean everywhere.

2. **Identity.** XTVERSION, DA1 and DA2, DSR-fenced. Whether `52` is among
   DA1's parameters is recorded on its own: TUIkit lets DA1 *add* a terminal to
   its table, never take one off (Ghostty writes by default and its DA1 has no
   52). Run iTerm2 twice, with "Applications in terminal may access clipboard"
   (Settings > General > Selection) on and off: if DA1's 52 follows the
   setting, the setting is detectable, which nothing else here can tell.

3. **Write.** A fresh nonce as `ESC ] 52 ; c ; <base64> ESC \`, the exact
   spelling TUIkit sends, then the read-back. Also the BEL terminator, and the
   empty selector (`ESC ] 52 ; ; …`): xterm reads that as `s0`, Ghostty as `c`,
   which is why TUIkit spells `c`.

4. **Ceiling.** Payloads of 1 KiB to 1 MiB of text, each a fresh nonce: the
   largest that arrives whole. Ghostty documents no limit; tmux and some hosts
   are reported to cut long sequences.

5. **Destructive** (`--destructive`). A sentinel is copied, then an empty
   payload (`ESC ] 52 ; c ; ESC \`), then a sentinel again and a payload that
   is not base64 (`!!!!`). Ghostty's documentation says the second CLEARS the
   clipboard: "If d is neither a valid Base64-encoded string or the character
   ?, all clipboards listed in t are cleared." TUIkit never sends either.

6. **tmux.** `tmux -V`, `set-clipboard`, `allow-passthrough`, and whether tmux
   kept the write as a paste buffer (`show-buffer`), which is what
   `set-clipboard on` does; `external`, the default, ignores an application's
   OSC 52. Run it in a pane with each setting, inside Ghostty and inside
   iTerm2: whether tmux forwards the write to the outer terminal is the
   read-back's answer.

TUIkit never asks the terminal to READ the clipboard (`?`): Ghostty asks the
user first by default, and the reply arrives in the input stream. Paste stays
the terminal's own, through bracketed paste.
"""
import base64, json, os, re, secrets, select, shutil, subprocess, sys, termios, time, tty

import probe_stamp

TIMEOUT = 1.0
STATUS_FENCE = b"\x1b[5n"
STATUS_REPLY = re.compile(rb"\x1b\[0n")
ST = b"\x1b\\"
BEL = b"\x07"
SETTLE = 0.3  # seconds a host gets to hand the write to its pasteboard
CEILING_KIB = [1, 8, 64, 100, 256, 512, 1024]


def read_until(fd, pattern, timeout=TIMEOUT):
    """Bytes read until `pattern` matches, or the timeout passes."""
    buf = b""
    deadline = time.monotonic() + timeout
    while not pattern.search(buf):
        left = deadline - time.monotonic()
        if left <= 0 or not select.select([fd], [], [], left)[0]:
            break
        buf += os.read(fd, 65536)
    return buf


def fence(fd, timeout=TIMEOUT):
    """Waits until the host has consumed everything written so far."""
    os.write(fd, STATUS_FENCE)
    return STATUS_REPLY.search(read_until(fd, STATUS_REPLY, timeout)) is not None


def cursor(fd):
    """(row, column) from DSR 6, or None."""
    os.write(fd, b"\x1b[6n")
    got = read_until(fd, re.compile(rb"\x1b\[(\d+);(\d+)R"))
    match = re.search(rb"\x1b\[(\d+);(\d+)R", got)
    return (int(match.group(1)), int(match.group(2))) if match else None


def osc52(text, selector=b"c", terminator=ST):
    """The write TUIkit sends: one selector, unwrapped base64, ST."""
    payload = base64.b64encode(text.encode("utf-8"))
    return b"\x1b]52;" + selector + b";" + payload + terminator


# MARK: - Reading the clipboard back


def local_helpers():
    """(read argv, write argv) for this machine's clipboard, or (None, None)."""
    if sys.platform == "darwin":
        return ["pbpaste"], ["pbcopy"]
    if os.environ.get("WAYLAND_DISPLAY") and shutil.which("wl-paste"):
        return ["wl-paste", "--no-newline"], ["wl-copy"]
    if os.environ.get("DISPLAY"):
        if shutil.which("xclip"):
            return ["xclip", "-selection", "clipboard", "-o"], ["xclip", "-selection", "clipboard"]
        if shutil.which("xsel"):
            return ["xsel", "--clipboard", "--output"], ["xsel", "--clipboard", "--input"]
    return None, None


class Clipboard:
    """Reads (and restores) the clipboard the terminal writes, by helper or by hand."""

    def __init__(self, fd, manual):
        self.fd = fd
        self.manual = manual
        self.read_argv, self.write_argv = (None, None) if manual else local_helpers()
        self.saved = None

    @property
    def readable(self):
        return self.manual or self.read_argv is not None

    def read(self, label=""):
        if self.read_argv is not None:
            try:
                return subprocess.run(self.read_argv, capture_output=True, timeout=5).stdout.decode(
                    "utf-8", "replace")
            except Exception as error:
                return f"(helper failed: {error})"
        if self.manual:
            return self.ask(label)
        return None

    def ask(self, label):
        """Asks a person to paste the clipboard and press Return."""
        os.write(self.fd, f"\r\n[{label}] Paste the clipboard now (bracketed), then Return: ".encode())
        got = b""
        while not got.endswith(b"\r") and not got.endswith(b"\n"):
            if not select.select([self.fd], [], [], 120)[0]:
                break
            got += os.read(self.fd, 65536)
        text = got.decode("utf-8", "replace")
        text = text.replace("\x1b[200~", "").replace("\x1b[201~", "")
        return text.rstrip("\r\n")

    def save(self):
        if self.read_argv is not None and self.write_argv is not None:
            self.saved = self.read()

    def restore(self):
        if self.saved is None or self.write_argv is None:
            return False
        try:
            subprocess.run(self.write_argv, input=self.saved.encode("utf-8"), timeout=5)
            return True
        except Exception:
            return False


def write_and_read(fd, board, text, label, **spelling):
    """Writes `text` by OSC 52 and reports whether the clipboard then holds it."""
    os.write(fd, osc52(text, **spelling))
    fenced = fence(fd, timeout=5)
    time.sleep(SETTLE)
    got = board.read(label)
    return {
        "fenced": fenced,
        "arrived": got == text if got is not None else None,
        "read_length": len(got) if got is not None else None,
    }


def nonce(prefix="tuikit-osc52"):
    return f"{prefix}-{secrets.token_hex(6)}"


# MARK: - Steps


def leak_check(fd):
    os.write(fd, b"\r\n")
    before = cursor(fd)
    os.write(fd, osc52(nonce("leak")))
    after = cursor(fd)
    return {"before": before, "after": after, "clean": before is not None and before == after}


def identity(fd):
    os.write(fd, b"\x1b[>0q\x1b[c\x1b[>c" + STATUS_FENCE)
    got = read_until(fd, STATUS_REPLY)
    version = re.search(rb"\x1bP>\|(.*?)\x1b\\", got)
    da1 = re.search(rb"\x1b\[\?([\d;]*)c", got)
    da2 = re.search(rb"\x1b\[>([\d;]*)c", got)
    da1_params = da1.group(1).decode().split(";") if da1 else None
    return {
        "xtversion": version.group(1).decode("utf-8", "replace") if version else None,
        "da1": da1.group(0).decode("latin-1") if da1 else None,
        "da1_has_52": ("52" in da1_params) if da1_params is not None else None,
        "da2": da2.group(0).decode("latin-1") if da2 else None,
    }


def ceiling(fd, board):
    sizes = {}
    largest = None
    for kib in CEILING_KIB:
        head = nonce(f"ceiling-{kib}k")
        text = (head + "-" + "x" * (kib * 1024))[: kib * 1024]
        result = write_and_read(fd, board, text, f"{kib} KiB")
        result["base64_bytes"] = len(base64.b64encode(text.encode()))
        sizes[f"{kib}KiB"] = result
        if result["arrived"]:
            largest = kib
        elif result["arrived"] is False:
            break
    return {"sizes": sizes, "largest_intact_kib": largest}


def destructive(fd, board):
    out = {}
    for name, sequence in [
        ("empty_payload", b"\x1b]52;c;" + ST),
        ("invalid_base64", b"\x1b]52;c;!!!!" + ST),
    ]:
        sentinel = nonce("sentinel")
        write_and_read(fd, board, sentinel, f"sentinel before {name}")
        os.write(fd, sequence)
        fence(fd)
        time.sleep(SETTLE)
        got = board.read(f"after {name}")
        out[name] = {
            "clipboard_after": "unchanged" if got == sentinel else ("cleared" if got == "" else "changed"),
            "read": got if got is None or len(got) < 80 else got[:80] + "…",
        }
    return out


def tmux_state(written):
    if not os.environ.get("TMUX"):
        return None

    def ask(*argv):
        try:
            return subprocess.run(["tmux", *argv], capture_output=True, text=True, timeout=5).stdout.strip()
        except Exception:
            return None

    return {
        "version": ask("-V"),
        "set_clipboard": ask("show-options", "-gv", "set-clipboard"),
        "allow_passthrough": ask("show-options", "-pv", "allow-passthrough") or ask(
            "show-options", "-gv", "allow-passthrough"),
        "client_termtype": ask("display-message", "-p", "#{client_termtype}"),
        "client_features": ask("display-message", "-p", "#{client_termfeatures}"),
        "buffer_holds_last_write": ask("show-buffer") == written if written else None,
    }


def main():
    use_alt = os.environ.get("PROBE_ALT") == "1"
    out_path = os.environ.get("PROBE_OUT", "clipboard_probe.json")
    args = sys.argv[1:]
    manual = "--manual" in args
    want_destructive = "--destructive" in args
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    tty.setraw(fd)
    result = {}
    board = Clipboard(fd, manual)
    try:
        if use_alt:
            os.write(fd, b"\x1b[?1049h")
        if manual:
            os.write(fd, b"\x1b[?2004h")
        result["stamp"] = probe_stamp.stamp(fd, "clipboard_probe", use_alt)
        result["remote"] = {k: os.environ.get(k) for k in ("SSH_CONNECTION", "SSH_CLIENT", "SSH_TTY")
                            if os.environ.get(k)}
        result["read_back"] = "by hand" if manual else (" ".join(board.read_argv) if board.read_argv else None)
        result["leak"] = leak_check(fd)
        result["identity"] = identity(fd)
        if not board.readable:
            result["note"] = ("no helper can read this machine's clipboard: run with --manual, "
                              "or on the machine the terminal runs on")
        else:
            board.save()
            last = nonce()
            result["write_st"] = write_and_read(fd, board, last, "ST")
            # Before the next write replaces tmux's newest buffer.
            result["tmux"] = tmux_state(last)
            bel = nonce("bel")
            result["write_bel"] = write_and_read(fd, board, bel, "BEL", terminator=BEL)
            empty_selector = nonce("empty-selector")
            result["write_empty_selector"] = write_and_read(
                fd, board, empty_selector, "empty selector", selector=b"")
            if not manual:
                result["ceiling"] = ceiling(fd, board)
            if want_destructive:
                result["destructive"] = destructive(fd, board)
            result["restored"] = board.restore()
    finally:
        if manual:
            os.write(fd, b"\x1b[?2004l")
        if use_alt:
            os.write(fd, b"\x1b[?1049l")
        termios.tcsetattr(fd, termios.TCSADRAIN, old)

    with open(out_path, "w") as handle:
        json.dump(result, handle, indent=1, ensure_ascii=False)
    env = result["stamp"]["env"]
    print(f"{env.get('TERM_PROGRAM', '?')} {env.get('TERM_PROGRAM_VERSION', '')} "
          f"on the {'alternate' if use_alt else 'primary'} screen"
          + (" over ssh" if result["remote"] else ""))
    leak = result["leak"]
    print(f"  OSC 52 printed nothing: {leak['clean']} (cursor {leak['before']} -> {leak['after']})")
    ident = result["identity"]
    print(f"  XTVERSION: {ident['xtversion'] or '(silent)'}   DA1: {ident['da1']!r}   52 in DA1: {ident['da1_has_52']}")
    if "write_st" in result:
        print(f"  ESC ] 52 ; c ; … ST reached the clipboard: {result['write_st']['arrived']}")
        print(f"  … with BEL: {result['write_bel']['arrived']}   with an empty selector: "
              f"{result['write_empty_selector']['arrived']}")
    if result.get("ceiling"):
        print(f"  largest copy intact: {result['ceiling']['largest_intact_kib']} KiB")
    if result.get("destructive"):
        for name, outcome in result["destructive"].items():
            print(f"  {name.replace('_', ' ')}: clipboard {outcome['clipboard_after']}")
    if result.get("tmux"):
        tmux = result["tmux"]
        print(f"  inside {tmux['version']}: set-clipboard {tmux['set_clipboard']}, "
              f"buffer kept the write: {tmux['buffer_holds_last_write']}")
    if result.get("note"):
        print(f"  {result['note']}")
    print(f"  written to {os.path.abspath(out_path)}")


if __name__ == "__main__":
    main()
