#!/usr/bin/env python3
"""Measures hardware scrolling (`TUI_SCROLL_OUTPUT`) on real frames.

    scroll_output.py sessions --stress BIN [--sessions a b] [--steps 400]
                              [--cols 120] [--rows 40] [--host ghostty] [--out x.json]
    scroll_output.py pages    --example BIN [--pages -,=,s] [--cols 120] [--rows 40]
                              [--host ghostty] [--out x.json]
    scroll_output.py oracle   --stress BIN [--sessions a b] [--steps 150]
    scroll_output.py allocs   --stress BIN --dylib alloc_count.dylib --sessions a b

`sessions` plays each `Stress` session once per level (`off`, `exact`, `residue`,
`margins`). A session is the real render loop with the same script each time, so
its steps line up, and for each it reports:

- **The bytes** of each level, from the writer itself.
- **The census** (`TUI_SCROLL_CENSUS`): how many frames changed enough rows to
  be looked at, and what each level found to do with them.
- **The differential.** Every level's stream is played through the screen model
  below, step by step, and each screen compared with `off`'s at the same step:
  paint is the truth, and `off` rewrites what changed in place. A cell that differs
  is a level that moved something it did not repair. It compares what a cell
  PAINTS: a blank cell's foreground is nobody's business.

`pages` drives `Example` through a PTY, one page at a time: arrow keys, page keys
and wheel notches, and the same census. It says what fraction of the pages' frames
could benefit, and how wide their bands are. `--answer-fence` is always on.

`oracle` searches every shift over a session's frames for the most a shift could
have saved, and sets the planner's plans beside it: all a hint from the pipeline
could add is the gap between the two.

`allocs` counts every `malloc` of a session under each level, with a small
interposer (`Tools/Profiling/AllocCount`): a count of work, comparable on a busy
machine, where timings are not. No timing comes out of this tool on purpose.

The model is deliberately not pyte: it has no SU or SD, and the point is scroll
regions. Only the standard library.
"""
import argparse
import json
import os
import pty
import re
import select
import struct
import subprocess
import sys
import tempfile
import time
import unicodedata

import fcntl
import termios

LEVELS = ("off", "exact", "residue", "margins")
DEFAULT_SESSIONS = (
    "editor", "inbox", "log", "settings", "chat", "notes", "playlist", "jobs", "processes",
    "menus", "themes", "glides",
)

CSI = re.compile(r"\x1b\[([0-?]*)([ -/]*)([@-~])")


class Screen:
    """Rows of (text, style) cells. A wide glyph's second cell holds "". Enough of
    a VT for what the writer sends: moves, SGR, erases with the pen's background,
    regions, margins, SU, SD, IL, DL, ECH, DCH."""

    def __init__(self, cols, rows):
        self.cols, self.rows = cols, rows
        self.style = Style()
        self.grid = [[(" ", Style.BLANK)] * cols for _ in range(rows)]
        self.x = self.y = 0
        self.top, self.bottom = 0, rows - 1
        self.left, self.right = 0, cols - 1
        self.lrm = False
        self.saved = (0, 0)

    def blank(self):
        return (" ", self.style.key())

    def feed(self, data):
        text = data.decode("utf-8", "surrogatepass")
        at = 0
        length = len(text)
        while at < length:
            ch = text[at]
            if ch == "\x1b":
                match = CSI.match(text, at)
                if match:
                    self.csi(match.group(1), match.group(2), match.group(3))
                    at = match.end()
                    continue
                if text[at + 1:at + 2] in ("]", "_", "P", "^", "X"):
                    end = text.find("\x1b\\", at)
                    bel = text.find("\x07", at)
                    stop = min(p for p in (end + 2 if end >= 0 else length, bel + 1 if bel >= 0 else length))
                    at = stop
                    continue
                self.esc(text[at + 1:at + 2])
                at += 2
                continue
            if ch < " " or ch == "\x7f":
                at += 1
                continue
            self.put(ch)
            at += 1

    def esc(self, final):
        if final == "7":
            self.saved = (self.x, self.y)
        elif final == "8":
            self.x, self.y = self.saved

    def put(self, ch):
        kind = unicodedata.category(ch)
        if kind in ("Mn", "Me", "Cf") or ch == "️" or ch == "︎":
            # Combines with what is to the left.
            x = self.x - 1
            if x >= 0:
                if self.grid[self.y][x][0] == "" and x > 0:
                    x -= 1
                cell = self.grid[self.y][x]
                self.grid[self.y][x] = (cell[0] + ch, cell[1])
            return
        wide = unicodedata.east_asian_width(ch) in ("W", "F")
        width = 2 if wide else 1
        if self.x >= self.cols:
            self.x = self.cols - 1
        self.grid[self.y][self.x] = (ch, self.style.key())
        if wide and self.x + 1 < self.cols:
            self.grid[self.y][self.x + 1] = ("", self.style.key())
        self.x = min(self.cols, self.x + width)

    def scroll(self, by):
        """Up when positive, inside the region and margins, exposed cells blank
        in the pen's background."""
        top, bottom, left, right = self.top, self.bottom, self.left, self.right
        height = bottom - top + 1
        by = max(-height, min(height, by))
        blank = self.blank()
        rows = list(range(top, bottom + 1)) if by > 0 else list(range(bottom, top - 1, -1))
        for row in rows:
            source = row + by
            if top <= source <= bottom:
                self.grid[row][left:right + 1] = self.grid[source][left:right + 1]
            else:
                self.grid[row][left:right + 1] = [blank] * (right - left + 1)

    def csi(self, params, intermediate, final):
        if intermediate:
            return
        private = params[:1] in ("?", ">", "<", "=")
        fields = params[1:].split(";") if private else params.split(";")

        def number(index, default=1):
            if index < len(fields) and fields[index].split(":")[0]:
                value = int(fields[index].split(":")[0])
                return value if value else default
            return default

        if final == "m":
            if not private:
                self.style.apply(params)
        elif final == "H" or final == "f":
            self.y = min(self.rows - 1, number(0) - 1)
            self.x = min(self.cols - 1, number(1) - 1)
        elif final == "G":
            self.x = min(self.cols - 1, number(0) - 1)
        elif final == "d":
            self.y = min(self.rows - 1, number(0) - 1)
        elif final == "C":
            self.x = min(self.cols - 1, self.x + number(0))
        elif final == "D":
            self.x = max(0, self.x - number(0))
        elif final == "A":
            self.y = max(0, self.y - number(0))
        elif final == "B":
            self.y = min(self.rows - 1, self.y + number(0))
        elif final == "K":
            mode = number(0, 0) if params else 0
            start, stop = {0: (self.x, self.cols), 1: (0, self.x + 1), 2: (0, self.cols)}[mode]
            self.grid[self.y][start:stop] = [self.blank()] * (stop - start)
        elif final == "J":
            mode = number(0, 0) if params else 0
            if mode == 2:
                self.grid = [[self.blank()] * self.cols for _ in range(self.rows)]
        elif final == "X":
            count = number(0)
            stop = min(self.cols, self.x + count)
            self.grid[self.y][self.x:stop] = [self.blank()] * (stop - self.x)
        elif final == "P":
            count = number(0)
            row = self.grid[self.y]
            self.grid[self.y] = row[:self.x] + row[self.x + count:] + [self.blank()] * count
        elif final == "r" and not private:
            self.top = number(0) - 1
            self.bottom = (number(1, self.rows) or self.rows) - 1
            self.x = self.y = 0
        elif final == "s" and not private:
            if self.lrm:
                self.left = number(0) - 1
                self.right = number(1, self.cols) - 1
                self.x = self.y = 0
            else:
                self.saved = (self.x, self.y)
        elif final in ("h", "l") and private and "69" in fields:
            self.lrm = final == "h"
            if not self.lrm:
                self.left, self.right = 0, self.cols - 1
        elif final == "S":
            self.scroll(number(0))
        elif final == "T":
            self.scroll(-number(0))

    def painted(self):
        return [[Style.painted(cell) for cell in row] for row in self.grid]


class Style:
    """The pen: colours and attributes, as a hashable key."""

    BLANK = (None, None, frozenset(), None)

    def __init__(self):
        self.fg = self.bg = self.ul = None
        self.attrs = set()

    def key(self):
        return (self.fg, self.bg, frozenset(self.attrs), self.ul)

    @staticmethod
    def painted(cell):
        text, (fg, bg, attrs, ul) = cell
        if text.strip(" "):
            return (text, fg, bg, attrs, ul)
        visible = attrs & {"4", "7", "9", "53", "5"}
        return (" ", fg if visible else None, bg, visible, ul if "4" in visible else None)

    def apply(self, params):
        fields = params.split(";") if params else ["0"]
        index = 0
        while index < len(fields):
            field = fields[index]
            head = field.split(":")[0]
            code = int(head) if head else 0
            if code == 0:
                self.__init__()
            elif code in (38, 48, 58):
                value, consumed = self.colour(fields, index, field)
                index += consumed
                if code == 38:
                    self.fg = value
                elif code == 48:
                    self.bg = value
                else:
                    self.ul = value
            elif 30 <= code <= 37 or 90 <= code <= 97:
                self.fg = f"i{code}"
            elif code == 39:
                self.fg = None
            elif 40 <= code <= 47 or 100 <= code <= 107:
                self.bg = f"i{code - 10}"
            elif code == 49:
                self.bg = None
            elif code == 59:
                self.ul = None
            elif code == 22:
                self.attrs -= {"1", "2"}
            elif code in (21, 24):
                self.attrs.discard("4")
            elif 23 <= code <= 29:
                self.attrs.discard(str(code - 20))
            elif code == 55:
                self.attrs.discard("53")
            else:
                self.attrs.add(field if code == 4 else str(code))
            index += 1

    @staticmethod
    def colour(fields, index, field):
        if ":" in field:
            return field, 0
        kind = fields[index + 1] if index + 1 < len(fields) else ""
        if kind == "5":
            return "5;" + fields[index + 2], 2
        if kind == "2":
            return "2;" + ";".join(fields[index + 2:index + 5]), 4
        return None, 0


# A step's keys can print a newline, so a line at a time will not do.
TRACE = re.compile(
    r"^#scroll\t(?P<census>[^\n]*)$"
    r"|^  step (?P<step>\d+): (?P<action>\S+)(?: to (?P<cols>\d+)x(?P<rows>\d+))?.*? — [\d.]+ µs, (?P<bytes>\d+) bytes$",
    re.MULTILINE | re.DOTALL)


def play_session(stress, session, level, steps, cols, rows, host, census=True, extra_env=None):
    with tempfile.TemporaryDirectory() as work:
        stream = os.path.join(work, "stream")
        env = dict(os.environ, TERM="xterm-256color", TERM_PROGRAM=host, TUI_SCROLL_OUTPUT=level,
                   TUI_HEADLESS_STREAM=stream, TUI_CONFIG_DIR=os.path.join(work, "config"))
        env.pop("TMUX", None)
        if census:
            env["TUI_SCROLL_CENSUS"] = "-"
        env.update(extra_env or {})
        run = subprocess.run(
            [stress, "--session", session, "--steps", str(steps), "--cols", str(cols), "--rows", str(rows), "--trace"],
            env=env, capture_output=True, text=True, errors="replace", timeout=1800, cwd=work)
        with open(stream, "rb") as handle:
            data = handle.read()
    steps_seen, census_rows = [], []
    pending = []
    for match in TRACE.finditer(run.stdout):
        if match.group("census") is not None:
            pending.append(match.group("census").split("\t"))
            continue
        step, action = int(match.group("step")), match.group("action")
        size = (int(match.group("cols")), int(match.group("rows"))) if match.group("cols") else None
        steps_seen.append({"step": step, "action": action, "bytes": int(match.group("bytes")), "size": size})
        census_rows.extend((step, action, row) for row in pending)
        pending = []
    return {"data": data, "steps": steps_seen, "census": census_rows, "status": run.returncode, "stderr": run.stderr[-400:],
            "tail": run.stdout[-300:]}


def plan_fields(field):
    if field == "-":
        return None
    rows, by, columns, saving = field.split(":")
    top, bottom = rows.split("-")
    narrow = None if columns == "full" else tuple(int(v) for v in columns.split("-"))
    return {"top": int(top), "bottom": int(bottom), "by": int(by), "columns": narrow, "saving": int(saving)}


def census_summary(rows, cols):
    """What each level found, across the frames the census saw."""
    out = {"looked_at": len(rows)}
    for index, level in ((9, "exact"), (10, "residue"), (11, "margins")):
        plans = [plan_fields(row[2][index]) for row in rows]
        plans = [p for p in plans if p]
        out[level] = {
            "frames": len(plans),
            "saving": sum(p["saving"] for p in plans),
            "narrow": sum(1 for p in plans if p["columns"]),
        }
        if plans:
            widths = sorted((p["columns"][1] - p["columns"][0]) if p["columns"] else cols for p in plans)
            out[level]["median_width"] = widths[len(widths) // 2]
    return out


def differential(base, other, cols, rows):
    """The first step whose screen differs, or None."""
    a, b = Screen(cols, rows), Screen(cols, rows)
    # The open frame comes before step 0.
    open_a = len(base["data"]) - sum(s["bytes"] for s in base["steps"])
    open_b = len(other["data"]) - sum(s["bytes"] for s in other["steps"])
    a.feed(base["data"][:open_a])
    b.feed(other["data"][:open_b])
    at_a, at_b = open_a, open_b
    compared = 0
    for step_a, step_b in zip(base["steps"], other["steps"]):
        if step_a.get("size"):
            # A resize drops the writer's picture of the screen: what follows
            # is a whole repaint, on either side, so a fresh grid models it.
            cols, rows = step_a["size"]
            a, b = Screen(cols, rows), Screen(cols, rows)
        a.feed(base["data"][at_a:at_a + step_a["bytes"]])
        b.feed(other["data"][at_b:at_b + step_b["bytes"]])
        at_a += step_a["bytes"]
        at_b += step_b["bytes"]
        compared += 1
        if a.top != 0 or a.bottom != rows - 1:
            return {"step": step_a["step"], "note": "base region left set"}
        if b.top != 0 or b.bottom != rows - 1 or b.lrm:
            return {"step": step_b["step"], "note": "region or margins left set"}
        pa, pb = a.painted(), b.painted()
        if pa != pb:
            for y in range(rows):
                if pa[y] != pb[y]:
                    x = next(i for i in range(cols) if pa[y][i] != pb[y][i])
                    return {"step": step_a["step"], "action": step_a["action"], "row": y, "col": x,
                            "base": repr(pa[y][x]), "other": repr(pb[y][x]), "compared": compared}
    return {"compared": compared}


def sessions(args):
    results = []
    print(f"{'session':<12}{'frames':>7}{'looked':>7}{'off B':>10} | {'exact':>16} | {'residue':>16} | {'margins':>16} | differential")
    for session in args.sessions:
        played = {}
        for level in LEVELS:
            played[level] = play_session(args.stress, session, level, args.steps, args.cols, args.rows, args.host)
        base = played["off"]
        frames = len(base["steps"])
        looked = census_summary(base["census"], args.cols)
        total_off = len(base["data"])
        row = {"session": session, "frames": frames, "off_bytes": total_off, "census": looked, "levels": {}}
        cells = []
        verdicts = []
        for level in LEVELS[1:]:
            this = played[level]
            bytes_here = len(this["data"])
            verdict = differential(base, this, args.cols, args.rows)
            pairs = list(zip(base["steps"], this["steps"]))
            row["levels"][level] = {
                "bytes": bytes_here, "differential": verdict,
                "frames_saved": sum(1 for a, b in pairs if b["bytes"] < a["bytes"]),
                "frames_lost": sum(1 for a, b in pairs if b["bytes"] > a["bytes"]),
                "bytes_lost": sum(b["bytes"] - a["bytes"] for a, b in pairs if b["bytes"] > a["bytes"]),
            }
            cells.append(f"{bytes_here:>9} {100 * (bytes_here - total_off) / max(1, total_off):+5.1f}%")
            verdicts.append("ok" if "step" not in verdict else f"{level}@{verdict['step']}")
        print(f"{session:<12}{frames:>7}{looked['looked_at']:>7}{total_off:>10} | " + " | ".join(cells) + " | " + ",".join(verdicts))
        for level in LEVELS[1:]:
            info = row["levels"][level]
            print(f"    {level:<8} moved on {info['frames_saved']} frames; {info['frames_lost']} frames cost more, "
                  f"{info['bytes_lost']} bytes; census est. saving {looked[level]['saving']} on {looked[level]['frames']} frames, "
                  f"{looked[level]['narrow']} narrow")
        for level in LEVELS[1:]:
            verdict = row["levels"][level]["differential"]
            if "step" in verdict:
                print("    ", level, verdict)
        # Per action: where the bytes went, and where they stopped going.
        actions = {}
        for level in ("off", args.detail):
            for step in played[level]["steps"]:
                actions.setdefault(step["action"], {"count": 0, "off": 0, args.detail: 0})
                actions[step["action"]][level] += step["bytes"]
                if level == "off":
                    actions[step["action"]]["count"] += 1
        row["actions"] = actions
        results.append(row)
    if args.out:
        with open(args.out, "w") as handle:
            json.dump({"cols": args.cols, "rows": args.rows, "host": args.host, "steps": args.steps,
                       "date": time.strftime("%Y-%m-%d"), "sessions": results}, handle, indent=1)
            handle.write("\n")


# --- Pages of Example, through a PTY ----------------------------------------

ESC = b"\x1b"
DOWN, UP = ESC + b"[B", ESC + b"[A"
PGDN, PGUP = ESC + b"[6~", ESC + b"[5~"


def wheel(button, col, row):
    return ESC + b"[<%d;%d;%dM" % (button, col, row)


def drive_page(example, page_key, level, cols, rows, host, dump_path=None):
    """One process, one page: the keys and the wheel. Returns bytes and census."""
    with tempfile.TemporaryDirectory() as work:
        census_path = os.path.join(work, "census")
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
        pid = os.fork()
        if pid == 0:
            os.close(master)
            os.setsid()
            fcntl.ioctl(slave, getattr(termios, "TIOCSCTTY", 0x20007461), 0)
            for fd in (0, 1, 2):
                os.dup2(slave, fd)
            env = dict(os.environ, TERM="xterm-256color", TERM_PROGRAM=host, COLUMNS=str(cols), LINES=str(rows),
                       TUI_CONFIG_DIR=os.path.join(work, "config"), TUI_SCROLL_OUTPUT=level,
                       TUI_SCROLL_CENSUS=census_path)
            env.pop("TMUX", None)
            os.execve(example, [example], env)
        os.close(slave)
        sizes = {"bytes": 0}
        buffered = bytearray()
        dump = open(dump_path, "wb") if dump_path else None

        def pump(seconds, quiet=None):
            """Reads for `seconds`, or until `quiet` seconds pass with nothing new."""
            end = time.monotonic() + seconds
            last = time.monotonic()
            while time.monotonic() < end:
                if quiet is not None and time.monotonic() - last > quiet:
                    return
                if select.select([master], [], [], 0.005)[0]:
                    try:
                        data = os.read(master, 65536)
                    except OSError:
                        return
                    if not data:
                        return
                    last = time.monotonic()
                    sizes["bytes"] += len(data)
                    if dump:
                        dump.write(data)
                    buffered.extend(data)
                    # Answer the status fences, as a terminal does.
                    while b"\x1b[5n" in buffered:
                        buffered[:] = buffered[buffered.index(b"\x1b[5n") + 4:]
                        os.write(master, b"\x1b[0n")
                    if len(buffered) > 16:
                        del buffered[:-16]

        # Up, and past whatever a page does when it arrives; then each input is
        # answered before the next, so two runs show the same frames unless the
        # page animates by the clock.
        deadline = time.monotonic() + 15
        while sizes["bytes"] < 2000 and time.monotonic() < deadline:
            pump(0.1)
        pump(3.0, quiet=0.5)
        os.write(master, page_key.encode())
        pump(1.5, quiet=0.3)
        opened = sizes["bytes"]
        script = [DOWN] * 20 + [UP] * 10 + [PGDN] * 4 + [PGUP] * 4
        col, row = cols // 2, rows // 2
        script += [wheel(65, col, row)] * 12 + [wheel(64, col, row)] * 12
        for step in script:
            os.write(master, step)
            pump(0.25, quiet=0.04)
        pump(0.1)
        used = sizes["bytes"] - opened
        if dump:
            dump.close()
        try:
            os.kill(pid, 9)
            os.waitpid(pid, 0)
        except OSError:
            pass
        os.close(master)
        census = []
        if os.path.exists(census_path):
            with open(census_path) as handle:
                census = [("?", "?", line.rstrip("\n").split("\t")[1:]) for line in handle]
    return used, census, len(script)


def pages(args):
    """Each page once, at `off`: the census says what each level would have saved
    on those very frames, so timing cannot make two runs of a page incomparable,
    and an animated page needs no two runs to agree."""
    results = []
    print(f"{'page':<7}{'frames looked at':>17}{'off B':>10} | {'exact':>16} | {'residue':>16} | {'margins':>16} | width")
    for key in args.pages:
        dump = f"{args.dump}-{ord(key):02x}.ansi" if args.dump else None
        # A run that the page never answered says nothing: a key that lands
        # during the startup exchanges goes astray. Try again before believing it.
        for _ in range(3):
            off_bytes, census, inputs = drive_page(args.example, key, "off", args.cols, args.rows, args.host, dump)
            if off_bytes:
                break
        summary = census_summary(census, args.cols)
        results.append({"page": key, "inputs": inputs, "census": summary, "off": off_bytes})
        cells = [f"{summary[level]['frames']:>4} {100 * summary[level]['saving'] / max(1, off_bytes):5.1f}% saved"
                 for level in ("exact", "residue", "margins")]
        print(f"{key!r:<7}{summary['looked_at']:>17}{off_bytes:>10} | " + " | ".join(cells)
              + f" | {summary['margins'].get('median_width', 0)}")
    total = sum(r["off"] for r in results)
    for level in ("exact", "residue", "margins"):
        saved = sum(r["census"][level]["saving"] for r in results)
        frames = sum(r["census"][level]["frames"] for r in results)
        print(f"all pages, {level}: {frames} frames moved, {saved:,} of {total:,} bytes saved ({100 * saved / max(1, total):.1f}%)")
    if args.out:
        with open(args.out, "w") as handle:
            json.dump({"cols": args.cols, "rows": args.rows, "host": args.host,
                       "date": time.strftime("%Y-%m-%d"), "pages": results}, handle, indent=1)
            handle.write("\n")


def allocs(args):
    print(f"{'session':<12}" + "".join(f"{level:>12}" for level in LEVELS) + "   mallocs over the whole run")
    results = []
    for session in args.sessions:
        counts = {}
        for level in LEVELS:
            with tempfile.TemporaryDirectory() as work:
                path = os.path.join(work, "count")
                env = dict(os.environ, TERM="xterm-256color", TERM_PROGRAM=args.host, TUI_SCROLL_OUTPUT=level,
                           DYLD_INSERT_LIBRARIES=args.dylib, ALLOC_COUNT_FILE=path,
                           TUI_CONFIG_DIR=os.path.join(work, "config"))
                subprocess.run([args.stress, "--session", session, "--steps", str(args.steps),
                                "--cols", str(args.cols), "--rows", str(args.rows)],
                               env=env, capture_output=True, timeout=1800)
                with open(path) as handle:
                    counts[level] = int(handle.read().strip())
        results.append({"session": session, "steps": args.steps, **counts})
        print(f"{session:<12}" + "".join(f"{counts[level]:>12}" for level in LEVELS))
    if args.out:
        with open(args.out, "w") as handle:
            json.dump(results, handle, indent=1)
            handle.write("\n")


# --- The oracle: what no hint could beat ------------------------------------

def row_cost(new, old, lower, upper, gap=8):
    """About what the cell diff writes for `new` over `old` in these columns."""
    bytes_, last = 0, None
    for x in range(lower, upper):
        if new[x] != old[x]:
            if last is None or x - last > gap + 1:
                bytes_ += 8 + 1
            else:
                bytes_ += x - last
            last = x
    return bytes_


def best_plan(before, after, cols, rows, by):
    """The best band for this shift, by search: the columns that gain most, then
    the rows that gain most in them. `(saving, top, bottom, left, right)`."""
    span = range(rows)
    sources = [(i, i + by) for i in span if 0 <= i + by < rows]
    gains = [0] * cols
    for i, j in sources:
        new, here, there = after[i], before[i], before[j]
        for x in range(cols):
            value = new[x]
            gains[x] += (value != here[x]) - (value != there[x])
    # Kadane over the columns.
    best = (0, 0, 0)
    total, start = 0, 0
    for x in range(cols):
        if total <= 0:
            total, start = 0, x
        total += gains[x]
        if total > best[0]:
            best = (total, start, x + 1)
    _, left, right = best
    if right <= left:
        return None

    def over(lower, upper):
        result, run, first = None, 0, 0
        for i in span:
            j = i + by
            if not 0 <= j < rows:
                run, first = 0, i + 1
                continue
            if run <= 0:
                run, first = 0, i
            run += row_cost(after[i], before[i], lower, upper) - row_cost(after[i], before[j], lower, upper)
            if run > (result[0] if result else 0):
                result = (run, first, i)
        if not result:
            return None
        saving, a, b = result
        exposed = range(b + 1, b + by + 1) if by > 0 else range(a + by, a)
        for i in exposed:
            saving -= (upper - lower + 8) - row_cost(after[i], before[i], lower, upper)
        return (saving - 40, a, b, lower, upper)

    return over(left, right)


def oracle(args):
    """What the planner found, against a search of every shift over the same
    frames, priced alike. A hint from the pipeline could at best tell the writer
    what this search finds, so the gap between the two is all a hint could add."""
    print(f"{'session':<12}{'frames':>7}{'searched':>9}{'found':>7}{'planner':>9}{'missed':>7}  "
          f"{'search saves':>13}{'planner saves':>14}{'captured':>9}")
    results = []
    for session in args.sessions:
        run = play_session(args.stress, session, "off", args.steps, args.cols, args.rows, args.host)
        data = run["data"]
        at = len(data) - sum(step["bytes"] for step in run["steps"])
        screen = Screen(args.cols, args.rows)
        screen.feed(data[:at])
        cols, rows = args.cols, args.rows
        by_step = {}
        for step, _, row in run["census"]:
            by_step[step] = row
        identities = {}

        def identify(painted):
            return [[identities.setdefault(cell, len(identities)) for cell in row] for row in painted]

        before = identify(screen.painted())
        searched = found = planned = missed = 0
        search_saving = planner_saving = 0
        missed_actions = {}
        for step in run["steps"]:
            if step.get("size"):
                cols, rows = step["size"]
                screen = Screen(cols, rows)
                screen.feed(data[at:at + step["bytes"]])
                at += step["bytes"]
                before = identify(screen.painted())
                continue
            screen.feed(data[at:at + step["bytes"]])
            at += step["bytes"]
            after = identify(screen.painted())
            changed = [i for i in range(rows) if before[i] != after[i]]
            census = by_step.get(step["step"])
            plan = plan_fields(census[11]) if census else None
            if len(changed) >= 3:
                searched += 1
                best = None
                # Only the shifts some row's text supports: a shift with none
                # gains nothing, and a row is a hundred cells.
                texts = {}
                for j in changed:
                    texts.setdefault(tuple(before[j]), []).append(j)
                candidates = set(range(-args.reach, args.reach + 1)) - {0}
                for by in sorted(candidates):
                    if abs(by) >= rows:
                        continue
                    result = best_plan(before, after, cols, rows, by)
                    if result and (best is None or result[0] > best[0]):
                        best = result
                if best and best[0] >= 64:
                    found += 1
                    search_saving += best[0]
                    if not plan:
                        missed += 1
                        missed_actions[step["action"]] = missed_actions.get(step["action"], 0) + best[0]
                if plan:
                    planned += 1
                    lower, upper = plan["columns"] or (0, cols)
                    saving = 0
                    by = plan["by"]
                    for i in range(plan["top"], plan["bottom"] + 1):
                        j = i + by
                        if plan["top"] <= j <= plan["bottom"]:
                            saving += row_cost(after[i], before[i], lower, upper) - row_cost(after[i], before[j], lower, upper)
                        else:
                            saving -= (upper - lower + 8) - row_cost(after[i], before[i], lower, upper)
                    planner_saving += saving - 40
            before = after
        results.append({"session": session, "frames": len(run["steps"]), "searched": searched, "found": found,
                        "planned": planned, "missed": missed, "search_saving": search_saving,
                        "planner_saving": planner_saving, "missed_by_action": missed_actions})
        print(f"{session:<12}{len(run['steps']):>7}{searched:>9}{found:>7}{planned:>9}{missed:>7}  "
              f"{search_saving:>13,}{planner_saving:>14,}{100 * planner_saving / max(1, search_saving):>8.0f}%  {missed_actions}"[:170])
    if args.out:
        with open(args.out, "w") as handle:
            json.dump(results, handle, indent=1)
            handle.write("\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="mode", required=True)
    s = sub.add_parser("sessions")
    s.add_argument("--stress", required=True)
    s.add_argument("--sessions", nargs="+", default=list(DEFAULT_SESSIONS))
    s.add_argument("--steps", type=int, default=400)
    s.add_argument("--cols", type=int, default=120)
    s.add_argument("--rows", type=int, default=40)
    s.add_argument("--host", default="ghostty")
    s.add_argument("--detail", default="margins", choices=LEVELS[1:])
    s.add_argument("--out")
    p = sub.add_parser("pages")
    p.add_argument("--example", required=True)
    p.add_argument("--pages", nargs="+", default=list("1234567890-=s[];'./`mtevfplrk"))
    p.add_argument("--cols", type=int, default=120)
    p.add_argument("--rows", type=int, default=40)
    p.add_argument("--host", default="ghostty")
    p.add_argument("--out")
    p.add_argument("--dump", help="write the off arm's stream to DUMP-<key>.ansi")
    o = sub.add_parser("oracle")
    o.add_argument("--stress", required=True)
    o.add_argument("--sessions", nargs="+", default=["inbox", "log", "chat", "playlist", "processes", "editor"])
    o.add_argument("--steps", type=int, default=150)
    o.add_argument("--cols", type=int, default=120)
    o.add_argument("--rows", type=int, default=40)
    o.add_argument("--host", default="ghostty")
    o.add_argument("--reach", type=int, default=12, help="the largest shift searched")
    o.add_argument("--out")
    a = sub.add_parser("allocs")
    a.add_argument("--stress", required=True)
    a.add_argument("--dylib", required=True)
    a.add_argument("--sessions", nargs="+", default=["inbox", "log", "settings", "processes", "editor"])
    a.add_argument("--steps", type=int, default=400)
    a.add_argument("--cols", type=int, default=120)
    a.add_argument("--rows", type=int, default=40)
    a.add_argument("--host", default="ghostty")
    a.add_argument("--out")
    args = parser.parse_args()
    {"sessions": sessions, "pages": pages, "allocs": allocs, "oracle": oracle}[args.mode](args)


if __name__ == "__main__":
    main()
