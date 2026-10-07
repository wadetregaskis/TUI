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
  python3 clipboard_probe.py --clobber      # run even though the clipboard
                                            #    holds what cannot be put back

Writes JSON to $PROBE_OUT (default ./clipboard_probe.json) and prints a
summary. `PROBE_ALT=1` runs on the alternate screen, where TUIkit draws.

**Self-verifying where it can be.** On the machine whose clipboard the
terminal writes, the read-back is `pbpaste` (macOS), `wl-paste` (Wayland), or
`xclip`/`xsel` (X11), so no person is needed. Over ssh the clipboard written is
the user's, on the far side: `--manual` writes the nonce and asks for it to be
pasted back.

**The clipboard is put back.** Its contents are saved before the first write
and restored however the run ends — an interrupted `--manual` prompt, a helper
that fails — where a helper can write it (never in `--manual`). A helper puts
back TEXT only, so a clipboard holding anything else (a picture, files, rich
text: `osascript`'s `clipboard info`, `wl-paste --list-types` or xclip's
`TARGETS` say what it holds) stops the run before anything is written, unless
`--clobber` says it may be lost. Text copied from Safari, Notes or TextEdit is
rich text too: copy plain text first (`printf probe | pbcopy`, `wl-copy`,
`xclip -selection clipboard`), which the run then puts back whole. Where the
types cannot be listed (`xsel`) the run stops whatever is copied, plain text
included: install a helper that lists them (`xclip`, or `wl-clipboard` on
Wayland), or pass `--clobber`. An empty X11 or Wayland clipboard, whose lister
says nothing is copied, is listed as empty.

1. **Leak.** The cursor column (DSR 6) before and after an OSC 52 write, as
   `hyperlink_probe.py` asks it of OSC 8. A column that moved means the host
   printed part of the sequence. Every host the compatibility doc measured
   swallows unknown OSC numbers, so this is expected clean everywhere. It
   needs no reader, so it is taken wherever its write is allowed: put back
   (a text clipboard here), or accepted (`--manual`, `--clobber`) — over ssh
   without `--manual` too, with `--clobber`, though nothing here can read the
   clipboard it writes or put it back.

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


# What a lister says, on its error stream and with a failing exit, when the
# clipboard holds nothing at all: an empty clipboard, not one whose types
# cannot be listed. wl-paste says "Nothing is copied" (wl-clipboard 2; "No
# selection" before), and xclip that no owner offers TARGETS.
WAYLAND_EMPTY = re.compile(r"Nothing is copied|No selection")
XCLIP_EMPTY = re.compile(r"target TARGETS not available")


def type_lister():
    """argv that lists the types this machine's clipboard holds, how to read
    its output into names, and the error a failing listing gives for an empty
    clipboard — or (None, None, None) where nothing can list them."""
    if sys.platform == "darwin":
        return ["osascript", "-e", "clipboard info"], parse_clipboard_info, None
    if os.environ.get("WAYLAND_DISPLAY") and shutil.which("wl-paste"):
        return ["wl-paste", "--list-types"], str.split, WAYLAND_EMPTY
    if os.environ.get("DISPLAY") and shutil.which("xclip"):
        return ["xclip", "-selection", "clipboard", "-t", "TARGETS", "-o"], str.split, XCLIP_EMPTY
    return None, None, None


def parse_clipboard_info(output):
    """The type names in `osascript -e 'clipboard info'`, which pairs each
    with its size: `«class utf8», 5, «class ut16», 12, string, 5`."""
    parts = [part.strip() for part in output.strip().split(", ") if part.strip()]
    return parts[0::2]


# Types a text helper's write puts back as they were. Anything else — a
# picture, a file list, RTF — would be replaced by text.
MAC_TEXT_TYPES = {"«class utf8»", "«class ut16»", "string", "Unicode text"}
X_TEXT_TARGETS = {"UTF8_STRING", "STRING", "TEXT", "COMPOUND_TEXT"}
# What X11 lists beside the data, which is not data.
X_META_TARGETS = {"TARGETS", "TIMESTAMP", "MULTIPLE", "SAVE_TARGETS", "DELETE", "INCR"}


# Rich text: a clipboard holding one beside its plain text loses its
# formatting when only the text is put back.
RICH_TEXT_TYPES = {"«class RTF »", "«class HTML»", "«class rtfd»", "text/html", "text/rtf", "application/rtf"}


def holds_only_text(types):
    """Whether a clipboard holding `types` is put back whole by writing its text."""
    for name in types:
        if name in MAC_TEXT_TYPES or name in X_TEXT_TARGETS or name in X_META_TARGETS:
            continue
        if name.startswith("text/plain"):
            continue
        return False
    return True


class Clipboard:
    """Reads (and restores) the clipboard the terminal writes, by helper or by hand."""

    def __init__(self, fd, manual, helpers=None, lister=None):
        self.fd = fd
        self.manual = manual
        if manual:
            self.read_argv, self.write_argv = None, None
        else:
            self.read_argv, self.write_argv = helpers or local_helpers()
        listing = (None, None, None) if manual else (lister or type_lister())
        # A lister given as (argv, parse) recognises no empty clipboard.
        self.list_argv, self.parse_types, self.empty_error = (tuple(listing) + (None,))[:3]
        self.saved = None
        self.held = None

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
            # Raw mode delivers Ctrl-C as a byte, not a signal: it still stops
            # the run, through the finally blocks that put things back.
            if b"\x03" in got:
                raise KeyboardInterrupt
        text = got.decode("utf-8", "replace")
        text = text.replace("\x1b[200~", "").replace("\x1b[201~", "")
        return text.rstrip("\r\n")

    def types(self):
        """The type names the clipboard holds, or None where they cannot be listed."""
        if self.list_argv is None:
            return None
        try:
            done = subprocess.run(self.list_argv, capture_output=True, timeout=5)
        except Exception:
            return None
        if done.returncode != 0:
            # An empty X11 or Wayland clipboard fails its listing, saying so.
            error = done.stderr.decode("utf-8", "replace")
            return [] if self.empty_error is not None and self.empty_error.search(error) else None
        return self.parse_types(done.stdout.decode("utf-8", "replace"))

    def save(self):
        """Saves the clipboard for ``restore``. False when it holds what a text
        helper cannot put back, or what it holds cannot be listed: nothing is
        saved then, and nothing should be written."""
        if self.read_argv is None or self.write_argv is None:
            return False
        self.held = self.types()
        if self.held is None or not holds_only_text(self.held):
            return False
        self.saved = self.read()
        return True

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


def plain_text_advice():
    """How to put plain text on this machine's clipboard, which the run can
    put back whole."""
    if sys.platform == "darwin":
        return "printf probe | pbcopy"
    if os.environ.get("WAYLAND_DISPLAY"):
        return "printf probe | wl-copy"
    return "printf probe | xclip -selection clipboard"


def refusal_advice(held):
    """What a refused run says to do: copy plain text first, and how — rich
    text copied from an app is refused too, its formatting being what writing
    its text back would lose. Where the types cannot be listed (`held` is
    None), no copy helps: the helper that lists them does."""
    if held is None:
        return None, ("install a helper that lists what the clipboard holds (xclip, or wl-clipboard on "
                      "Wayland), or pass --clobber")
    rich = any(name in RICH_TEXT_TYPES for name in held)
    what = "rich text, whose formatting writing its text back would lose" if rich else None
    lead = f"the clipboard holds {what}" if what else None
    return lead, f"copy plain text first ({plain_text_advice()}), or pass --clobber"


def preserving(board, clobber, writes):
    """Runs `writes` — everything that may write the clipboard — with the
    clipboard saved first and put back however they end, an exception or an
    interrupt included. Returns (ran, restored, refusal): a clipboard holding
    what a text helper cannot put back is not written at all unless
    `clobber`, and `refusal` says what it holds."""
    if not board.manual and not board.save() and not clobber:
        held = ", ".join(board.held) if board.held is not None else "types that cannot be listed"
        lead, advice = refusal_advice(board.held)
        lead = lead or f"the clipboard holds {held}, which writing its text back would lose"
        return False, False, f"{lead}: {advice}"
    try:
        writes()
    finally:
        restored = board.restore()
    return True, restored, None


def run_writes(board, clobber, writes, leak):
    """Runs the steps that write the clipboard as far as they may, and returns
    what to record of it.

    Where a helper can read the clipboard, every step runs with it saved and
    put back (``preserving``). Where none can, only the leak check, which
    needs no reader — and only with `--clobber`, as its write lands on a
    clipboard nothing here can put back."""
    if not board.readable:
        if clobber:
            leak()
            return {"note": ("no helper can read the clipboard the terminal writes: the leak check "
                             "alone ran, and its write was not put back; run with --manual for the rest")}
        return {"note": ("no helper can read this machine's clipboard: run with --manual, or on the "
                         "machine the terminal runs on; --clobber takes the leak check alone, its "
                         "write not put back")}
    ran, restored, refusal = preserving(board, clobber, writes)
    out = {"restored": restored}
    if not ran:
        out["note"] = refusal
    return out


def main():
    use_alt = os.environ.get("PROBE_ALT") == "1"
    out_path = os.environ.get("PROBE_OUT", "clipboard_probe.json")
    args = sys.argv[1:]
    manual = "--manual" in args
    want_destructive = "--destructive" in args
    clobber = "--clobber" in args
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    tty.setraw(fd)
    result = {}
    board = Clipboard(fd, manual)

    def writes():
        # Every step from here writes the clipboard: the leak check's OSC 52
        # too, so the clipboard is saved before it.
        result["leak"] = leak_check(fd)
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

    try:
        if use_alt:
            os.write(fd, b"\x1b[?1049h")
        if manual:
            os.write(fd, b"\x1b[?2004h")
        result["stamp"] = probe_stamp.stamp(fd, "clipboard_probe", use_alt)
        result["remote"] = {k: os.environ.get(k) for k in ("SSH_CONNECTION", "SSH_CLIENT", "SSH_TTY")
                            if os.environ.get(k)}
        result["read_back"] = "by hand" if manual else (" ".join(board.read_argv) if board.read_argv else None)
        result["identity"] = identity(fd)
        def leak():
            result["leak"] = leak_check(fd)

        result.update(run_writes(board, clobber, writes, leak))
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
    leak = result.get("leak")
    if leak:
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
    if "restored" in result:
        print(f"  clipboard put back: {result['restored']}")
    if result.get("note"):
        print(f"  {result['note']}")
    print(f"  written to {os.path.abspath(out_path)}")


if __name__ == "__main__":
    main()
