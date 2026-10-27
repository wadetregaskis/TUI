#!/usr/bin/env python3
"""A card for the mouse pointer's shape (OSC 22): hover each box and read
whether the pointer is what its label says; then quit, or suspend, and read
whether the shell gets its own pointer back.

TUI's `pointerStyle(_:)` sets the pointer's shape by name with
`ESC ] 22 ; name ESC \\` on the terminals documented to take it, and in each
one's names: CSS's `cursor` keywords on Ghostty, kitty and foot; the X11
cursor font's on xterm; iTerm2's own nineteen X11 names on iTerm2 (see
`Sources/TUITerminalHost/Rendering/TerminalPointerShapes.swift`). The shape
is drawn by the window system, not into the terminal's cells, so no probe can
read it back: a person has to look.

## The measurement

The card turns on any-motion mouse reporting (mode 1003, SGR 1006) and draws
one box per `PointerStyle`. As the pointer moves onto a box it sends that
box's name, in the naming scheme chosen; off every box, the scheme's "no
style" (`default` on Ghostty, which ignores an empty name in older releases;
empty elsewhere), as TUI does. The last line shows what was sent last.

Read it as:
- **Each box**: the pointer over it is the shape its label describes. A box
  whose name is `—` has no name in this scheme: the pointer there should be
  the terminal's own, NOT the shape of the box you came from.
- **Mode change** (`m`): flips the reporting mode 1003 -> 1002 -> 1003, as
  TUI does when the views asking for motion come and go, then sends the
  current box's name again. Note whether the shape was lost before the
  re-send (Ghostty's source resets it on every mode change).
- **Quit** (`q`): TUI's teardown: the empty name (every host's reset),
  then the mouse modes off, then the alternate screen left. Move the pointer
  over the shell afterwards: it should be the pointer the terminal shows
  there with no program running (an I-beam on most).
- **Quit, the alternatives** — to tell which reset a host needs: `1` sends
  only the mouse modes off; `2` sends the mouse modes off and then `default`
  (an arrow left behind would show that a name after the modes is wrong);
  `3` sends nothing at all (does leaving the alternate screen restore it?).
- **Suspend** (`z`): the same teardown as `q`, then a stop; type `fg` to come
  back. While stopped, the shell's pointer should be the terminal's own; once
  back, hover a box again and it should take its shape.

Run it in each terminal:

    python3 pointer_shape_card.py            # the names TUI would choose
    python3 pointer_shape_card.py --names css|x11|iterm2

and record what each one shows in
`Documentation/Terminals/Terminal compatibility survey.md`, "Pointer shapes
(OSC 22)": per box, right / wrong / the terminal's own; and for each way out,
whether the shell's pointer came back. Under tmux, run it inside a tmux pane
too (the hypothesis is that tmux drops OSC 22, so nothing changes).
"""

import os
import re
import signal
import sys
import termios
import tty

ESC = "\x1b"

# (label, CSS, X11 (xterm), iTerm2) — the tables of TerminalPointerShapes.swift.
SHAPES = [
    (".default", "default", "left_ptr", "arrow"),
    (".horizontalText", "text", "xterm", "xterm"),
    (".verticalText", "vertical-text", None, None),
    (".link", "pointer", "hand2", "hand2"),
    (".grabIdle", "grab", "hand1", None),
    (".grabActive", "grabbing", None, None),
    (".columnResize", "col-resize", "sb_h_double_arrow", "sb_h_double_arrow"),
    (".columnResize(.leading)", "w-resize", "sb_left_arrow", "sb_left_arrow"),
    (".columnResize(.trailing)", "e-resize", "sb_right_arrow", "sb_right_arrow"),
    (".rowResize", "row-resize", "sb_v_double_arrow", "sb_v_double_arrow"),
    (".rowResize(.up)", "n-resize", "sb_up_arrow", "sb_up_arrow"),
    (".rowResize(.down)", "s-resize", "sb_down_arrow", "based_arrow_down"),
    ("frame .top, both ways", "ns-resize", "sb_v_double_arrow", "sb_v_double_arrow"),
    ("frame .leading, out", "w-resize", "left_side", "sb_left_arrow"),
    ("frame .topLeading, out", "nw-resize", "top_left_corner", None),
    ("frame .topTrailing, both", "nesw-resize", "top_right_corner", None),
    ("frame .topLeading, both", "nwse-resize", "top_left_corner", None),
    (".rectSelection", "crosshair", "crosshair", "crosshair"),
    (".zoomIn", "zoom-in", None, None),
    (".zoomOut", "zoom-out", None, None),
]

SCHEMES = {"css": 1, "x11": 2, "iterm2": 3}

COLUMNS, BOX_WIDTH, BOX_HEIGHT, TOP = 3, 26, 3, 3


def detect_scheme(env):
    """The naming scheme TUI would choose here (PointerShapeHost.detect)."""
    program = env.get("TUI_TERM_PROGRAM") or env.get("TERM_PROGRAM", "")
    if program == "iTerm.app" or env.get("LC_TERMINAL") == "iTerm2":
        return "iterm2"
    if env.get("XTERM_VERSION") and program in ("", "xterm"):
        return "x11"
    return "css"


def osc22(name):
    return f"{ESC}]22;{name}{ESC}\\"


class Card:
    def __init__(self, scheme, unset):
        self.scheme = scheme
        self.column = SCHEMES[scheme]
        self.unset = unset
        self.current = None  # index of the box under the pointer
        self.last_sent = None
        self.mode = 1003
        self.saved = termios.tcgetattr(sys.stdin.fileno())

    def write(self, text):
        os.write(sys.stdout.fileno(), text.encode())

    def enter(self):
        tty.setraw(sys.stdin.fileno())
        self.write(f"{ESC}[?1049h{ESC}[?25l{ESC}[?{self.mode}h{ESC}[?1006h")
        self.draw()

    def leave(self, way):
        if way == "tuikit":
            self.write(osc22("") + f"{ESC}[?1006l{ESC}[?1003l{ESC}[?1002l{ESC}[?1000l")
        elif way == "modes-only":
            self.write(f"{ESC}[?1006l{ESC}[?1003l{ESC}[?1002l{ESC}[?1000l")
        elif way == "default-after":
            self.write(f"{ESC}[?1006l{ESC}[?1003l{ESC}[?1002l{ESC}[?1000l" + osc22("default"))
        self.write(f"{ESC}[?25h{ESC}[?1049l")
        termios.tcsetattr(sys.stdin.fileno(), termios.TCSAFLUSH, self.saved)

    def box_at(self, x, y):
        """The box under the 1-based cell (x, y), or None."""
        column, offset = divmod(x - 1, BOX_WIDTH)
        row, line = divmod(y - 1 - TOP, BOX_HEIGHT + 1)
        if y - 1 < TOP or column >= COLUMNS or offset >= BOX_WIDTH - 1 or line >= BOX_HEIGHT:
            return None
        index = row * COLUMNS + column
        return index if index < len(SHAPES) else None

    def name_for(self, index):
        return SHAPES[index][self.column] if index is not None else None

    def draw(self):
        out = [f"{ESC}[2J{ESC}[H"]
        out.append(f"Pointer shape card — names: {self.scheme}; no style: {self.unset!r}\r\n")
        out.append("Hover each box. q quit (TUI's way)  1/2/3 quit other ways  m mode change  z suspend\r\n")
        for index, shape in enumerate(SHAPES):
            row, column = divmod(index, COLUMNS)
            top = TOP + row * (BOX_HEIGHT + 1) + 1
            left = column * BOX_WIDTH + 1
            name = shape[self.column]
            lines = [shape[0], f"sends: {name}" if name else "sends: — (terminal's own)", ""]
            for offset, text in enumerate(lines):
                fill = f"{ESC}[48;5;{236 if (row + column) % 2 else 238}m"
                out.append(f"{ESC}[{top + offset};{left}H{fill}{text[:BOX_WIDTH - 2]:<{BOX_WIDTH - 1}}{ESC}[0m")
        self.write("".join(out))
        self.status()

    def status(self):
        rows = TOP + ((len(SHAPES) + COLUMNS - 1) // COLUMNS) * (BOX_HEIGHT + 1) + 2
        sent = "nothing yet" if self.last_sent is None else repr(self.last_sent)
        self.write(f"{ESC}[{rows};1H{ESC}[2Kmode {self.mode}; last sent: {sent}")

    def send_current(self):
        name = self.name_for(self.current)
        text = name if name is not None else self.unset
        self.write(osc22(text))
        self.last_sent = text
        self.status()

    def moved(self, x, y):
        index = self.box_at(x, y)
        if index != self.current:
            self.current = index
            self.send_current()

    def flip_mode(self):
        self.write(f"{ESC}[?1003l{ESC}[?1002h")
        self.write(f"{ESC}[?1002l{ESC}[?1003h")
        self.send_current()

    def suspend(self):
        self.leave("tuikit")
        self.write("Stopped. The shell's pointer should be the terminal's own. Type `fg` to come back.\r\n")
        os.kill(os.getpid(), signal.SIGSTOP)
        self.current = None
        self.last_sent = None
        self.enter()


MOUSE = re.compile(rb"\x1b\[<(\d+);(\d+);(\d+)([Mm])")


def main():
    args = sys.argv[1:]
    scheme = detect_scheme(os.environ)
    if "--names" in args:
        scheme = args[args.index("--names") + 1]
    if scheme not in SCHEMES:
        sys.exit(f"--names must be one of {', '.join(SCHEMES)}")
    ghostty = os.environ.get("TERM_PROGRAM") == "ghostty" or os.environ.get("TERM") == "xterm-ghostty"
    card = Card(scheme, "default" if ghostty else "")
    card.enter()
    way = "tuikit"
    keys_to_ways = {ord("q"): "tuikit", ord("1"): "modes-only", ord("2"): "default-after", ord("3"): "nothing"}
    try:
        pending = b""
        while way == "tuikit" or way is None:
            pending += os.read(sys.stdin.fileno(), 1024)
            keys = b""
            while (match := MOUSE.search(pending)) is not None:
                keys += pending[: match.start()]
                card.moved(int(match.group(2)), int(match.group(3)))
                pending = pending[match.end():]
            # A report cut off by the read waits for the rest of it.
            cut = pending.rfind(b"\x1b")
            keys, pending = (keys + pending[:cut], pending[cut:][-64:]) if cut >= 0 else (keys + pending, b"")
            way = None
            for key in keys:
                if key in keys_to_ways:
                    way = keys_to_ways[key]
                    break
                if key == ord("m"):
                    card.flip_mode()
                if key == ord("z"):
                    card.suspend()
            if way is not None:
                break
    finally:
        card.leave(way or "tuikit")
    print(f"Left by: {way}. Move the pointer over the shell now and note its shape.")


if __name__ == "__main__":
    main()
