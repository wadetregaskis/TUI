#!/usr/bin/env python3
"""Hairline probe: can a Kitty graphics CLASSIC placement draw a thin line
exactly on the boundary between two text rows, on this host?

Every separator TUIkit draws today costs a whole row: `.listRowSeparator`
puts a faint `─` rule on a line of its own. A line one or two pixels thick on
the boundary between two rows would cost none. The research behind this probe
(2026-10-08, kept outside the repository; this docstring restates the plan
and the kill criteria it set) found one way to draw it, and it is not the
Unicode placeholders TUIkit uses for pictures, whose cells hold no text. It
is a CLASSIC placement, drawn at the cursor and outside the cell grid: at
`Y=0` on the lower row (the top edge of that row), cropped with `x,y,w,h`
from one shared strip per colour, with `C=1` so the cursor stays put, always
with a placement id, and at `z=-1` (above the cell's background, under its
glyphs). TUIkit has never emitted a classic placement, and no host has been
measured drawing one. This measures that.

Run INSIDE the terminal under test; nothing here needs TUIkit built.

  python3 hairline_probe.py          # automatic checks, then a card per
                                     #   question that a person answers by key
  python3 hairline_probe.py --auto   # the automatic checks alone: no card
                                     #   asks anything, no key is read

Writes JSON to $PROBE_OUT, by default `data/<host>-<version>-hairline.json`
beside this script, with the host named as the committed records name it
(`ghostty-1.3.1`, `iterm2-3.6.11`, `warpterminal-v0…`, from TERM_PROGRAM and
its version; a host that sets none, such as kitty, by its XTVERSION reply,
which also wins over a TERM_PROGRAM naming another program, since that one
was inherited from the terminal the host was started in). Only a run a person
answered to the end replaces a record that holds a person's answers. Any
other run goes beside it: one that was stopped as
`<host>-<version>-hairline-aborted.json`, and one run `--auto` or left
unanswered as `<host>-<version>-hairline-auto.json`. Then prints a summary. A
run that stops early still writes its record, with `aborted` saying why, and
exits 1.

It runs on the ALTERNATE screen throughout, where TUIkit draws. kitty and
Ghostty keep one image store per screen, so a strip sent on the primary
screen is not there to place on the alternate one (Q8 measures exactly that).
It refuses Apple Terminal, which prints APC payloads as text. On a host that
does not answer the protocol's `a=q` query (tmux 3.7c was measured silent) it
sends no graphics at all and shows only the Q10 card.

**Never trust an `OK` alone.** The xterm.js image addon's beta acknowledges a
placement and was measured drawing nothing, and iTerm2 3.6.11 answered `OK`
to a placement whose two-mark placeholder cells it never drew
(Terminal-compatibility.md: xterm.js's "Graphics" section, and "What each
host advertises"). So before Q1 the probe places an id it never sent, which
must answer `ENOENT`; a host that answers `OK` there leaves every automatic
OK-against-ENOENT reading (Q6's, Q8's) null. And every automatic reading that
is about pixels is paired with a card: a yes/no question a person answers
with a key (`y`, `n`, or `s` for "can't tell"; Q9's keys are its own, and Q7
adds `r` to run its animation again). Ctrl-C stops the run at any point,
`--auto` included, and `q` at any card or during Q7's animation (a `q` typed
between cards is seen at the next one); the record keeps what was answered.
The automatic readings use `q=0` and are fenced by DSR, so a silent host
reads as `silent` and never hangs the probe. A fence that times out (iTerm2
has missed a one-second one after a graphics payload) leaves its replies on
their way, to be read as the next reading's; so it is followed by a resync
(DA1, a fence no reading uses, everything before its answer discarded). The
record lists each missed fence; while the probe cannot get back in step, the
commands still go out but no reply is read, and each reading says `not read:
out of step`. A question unanswered for ten minutes (two for the first card)
turns the rest of the run automatic, so a run that nobody watches still ends.

The questions (the research's Q1-Q10; Q1 and Q2 share a card):

Q1  Is a classic placement acknowledged, and drawn?  SENDS the strip
    (`a=t,f=24,s=W,v=t,q=0`, W at least 2048 and at least the window's
    pixel width, t the line's thickness), then `CUP` and
    `a=p,i,p=1,x=0,y=0,w,h=t,C=1,z=-1,q=0` on the lower of two marked rows.
    READS the replies to both: `OK`, `EINVAL`, `ENOENT`, another code, or
    `silent`. CARD: is a thin line visible; is it exactly on the boundary
    between the ▲ and ▼ rows; does it run from bar to bar (▕ ▏)?
Q2  Does `C=1` hold the cursor?  READS DSR before and after that placement;
    the same cell is a pass. No card: the cursor report is the answer.
Q3  What is the pixel unit?  COARSE, automatic: a `C=0` placement 10 cells
    wide by each available measure of a cell (TIOCGWINSZ's
    ws_xpixel // ws_col; `CSI 14 t` over `CSI 18 t`; `CSI 16 t`), DSR before
    and after. An advance of 10 means that measure is the placement's unit;
    20 or 5 is a 2x error (points against device pixels). Rounding up to
    whole cells hides anything finer. When only `CSI 14 t`'s or `CSI 16 t`'s
    measure is the unit, every line after Q3 is cropped by that measure (the
    research's plan change, applied in the probe) and the record says so.
    FINE, by card: lines from column 1 across a run that ends four columns
    short of the window's edge, so that a line too long shows past its end
    instead of being clipped by the edge of the grid, each under a bar ▏
    at the run's end. One line per distinct width: `ws_xpixel x run //
    ws_col` (the formula the design uses), `run x (ws_xpixel // ws_col)`
    (TUIkit's integer cell width), and the `CSI 14 t` and `CSI 16 t`
    equivalents. The person says which ends exactly at its bar. Records
    ws_xpixel, ws_col and the three XTWINOPS replies.
Q4  Is the line on the boundary, in the right layer?  CARD: four bands (the
    default background, a grey fill, a stripe and a selection colour), each
    a row of `gjpqy` over a row of `│┼█▀ ÉÅ 😀`, with a line along the top of
    the lower row in three columns: `z=-1`, `z=+1` and `z=-1073741825`
    (below INT32_MIN/2, so under painted cells), each ending at a bar ▏ so
    that a line wider than its column shows. The placements' replies are
    recorded. A host that follows the spec draws `z=-1` on every band and
    under the glyphs, `z=+1` over the glyphs, and the third on the default
    band only.
Q5  Do rewrites keep it?  CARD: lines under four rows; then row B is
    rewritten after `ESC[2K` (the way every whole-line rewrite TUIkit sends
    opens), row C is written over without erasing (the span diff), and row D
    is erased with ECH and written. Row A is left alone. WezTerm's source
    says B loses its line.
Q6  Delete and re-place.  SENDS two placements of one strip, deletes one by
    `a=d,d=i,i,p` (lowercase: the placement only), and places it again
    without re-sending the strip; then deletes both and places one again
    (the strip had no placement in between, and kitty evicts such images
    first under quota pressure). Then an uppercase `d=I` on a scratch image
    and a placement of it, which should answer `ENOENT` (the data freed:
    TUIkit's cleanup path). READS every reply; `OK` on a re-place means the
    data was kept. CARD: both lines shown; line 1 gone and line 2 kept;
    line 1 back; line 1 back again; line 2 still gone.
Q7  Flicker and tearing on moves.  READS DECRQM `?2026` and the
    `?2026h ?2026l` leak check through `sync_probe.py`'s own helpers, asking
    DECRQM only where its rule says that is safe. CARD: two coloured rows,
    with the line on their seam, move down 30 rows and back at 60 Hz,
    re-placing the same `(i, p)` each frame (`q=2`, the text first, then the
    placement), once without mode 2026 and once with every frame inside
    `?2026h ... ?2026l`. The person says whether the line stayed on the seam;
    `r` runs it again.
Q8  ED 2 and the alternate screen.  (a) A line is placed, the screen is
    cleared with `ESC[2J`, and the line is placed again by id without
    re-sending: `ENOENT` means ED 2 freed the strip. (b) A line is placed,
    `?1049l` shows the primary screen, `?1049h` returns, and the line is
    placed again by id; then the strip is sent again and placed (`OK` is the
    control). (c) The store: a small image is sent on the PRIMARY screen and
    looked up from the alternate one, then from the primary again, each
    lookup a 1x1 pixel placement (an `a=q` would re-create the image it asks
    about). `OK` on the alternate screen means one store for both; `ENOENT`
    there and `OK` back on the primary means a store per screen; `ENOENT` on
    both means freed. CARDS: is the line still visible after ED 2; was it on
    the primary screen after `?1049l` (iTerm2 may keep it; the probe writes
    nothing there, and asks once it is back); after coming back; after the
    re-send.
Q9  Resize (optional).  CARD: the person resizes the window and says whether
    the line stayed on its boundary, moved, or went (`y`, `m`, `g`; `s`
    skips it). The size before and after is recorded.
Q10 The fallback without graphics.  CARD, shown on every host with or
    without graphics: SGR 4 with an underline colour (`58;2;r;g;b`, and the
    colon form `4:1` + `58:2::r:g:b`), plain SGR 4, and SGR 53 (overline)
    for comparison. Is the underline grey, is it near the row boundary, and
    is an overline drawn?

What ends the idea (the research's kill criteria). A record carries this
host's half of each in `criteria.kill_inputs`: true, false, or null for not
judged.

1. Ghostty AND iTerm2 both fail Q1 or Q4, or neither can remove a line by
   (i, p) in Q6. Q4 fails when the line is off the boundary or shows in
   neither layer; Q6 passes only when both lines were shown first, so a
   host that keeps one placement per image cannot pass by removing nothing.
2. Q7 shows flicker or tearing against the text on both hosts with mode
   2026 on. That ends scrolling lists; static ones would remain.

What changes the plan instead (`criteria.plan_changes`): Q5 loses the line
on a rewrite (re-place per rewritten row, as WezTerm needs anyway), judged
only when the untouched control row kept its line; Q3 shows a unit no
query reveals (exclude that host); Q4 hides `z=-1` under fills (`z=+1` on
that host, which needs an identity for it); Q8 shows lines surviving ED 2
or `?1049l` (cleanup must delete them all, which the design does). What a
control says cannot be judged goes in `criteria.unjudged`.

Choices the research leaves to TUIkit, taken here as the simplest that
works, so that a reading means one thing:

- **Thickness**: `max(1, cell height // 17)` px, with the cell height from
  TIOCGWINSZ in integer division as TUIkit computes it: 2 px at Ghostty's
  34, 1 px at 16. The strip is that tall.
- **Crop width**: `ws_xpixel x columns // ws_col`, rounded DOWN, so a line
  is never wider than its run and at most one pixel short; after Q3, the
  same rule by `CSI 14 t`'s or `CSI 16 t`'s measure where only that one is
  the unit. A host that reports no pixel size gets TUIkit's default
  8-pixel cell.
- **One strip, one colour, raw RGB** (`f=24`, no `o=z`): a line is opaque,
  so alpha buys nothing, and deflate is `graphics_compression_probe.py`'s
  question. The colour is a vivid one nobody can miss, not
  `palette.border`. It is sent by `placement_probe.transmit`, as that probe
  sends its pictures.
- **The strip is re-sent on every card.** Each card deletes the previous
  card's lines, which leaves the strip with no placement, and the design's
  eviction rule is to re-send a strip in that state. Only Q6 places again
  without re-sending, because that is its question.
- **Cards clear with `CSI H` + `CSI J`, never `CSI 2 J`**, after deleting
  the previous card's placements by id: ED 2 is Q8's subject.
- **`X` and `Y` are left out.** Both default to 0, the cell's top-left
  corner, which is where the design puts the line.
- **Image ids** 0xFFFFF0-0xFFFFF4, beside TUIkit's handshake ids at the top
  of the 24-bit range. TUIkit's store counts up from 1 and wraps just below
  the handshake's ids, so a real hairline layer must reserve a range of its
  own; the probe only keeps out of the way.
- **Q7's frames** write the text first and the placement after it, both
  inside the hold when there is one, which is the order the design's writer
  would use.

Every exit restores the terminal, including an exception or a signal (TERM,
HUP, INT, QUIT). It ends any open string, closes a chunked transmit a signal
cut short, ends any synchronized-update hold, deletes every image the probe
sent (`d=I`, so the data goes too) on the alternate screen and then on the
primary, leaves the alternate screen, shows the cursor, swallows late
replies, and puts the tty mode back. It gives a terminal that has stopped
reading three seconds, then puts the tty mode back regardless. A run stopped
during Q8's visit to the primary screen may leave an image in the alternate
screen's store, until the next program to enter that screen clears it.
"""
import argparse, fcntl, json, os, re, select, signal, struct, sys, termios, textwrap, time, tty

import placement_probe
import probe_stamp
import sync_probe

HERE = os.path.dirname(os.path.abspath(__file__))

# A graphics command can outlast a one-second fence (iTerm2, measured).
IMAGE_TIMEOUT = placement_probe.IMAGE_TIMEOUT
QUERY_TIMEOUT = placement_probe.FENCE_TIMEOUT
ANSWER_TIMEOUT = 600.0
RESTORE_SECONDS = 3.0  # the most the restore waits on a terminal that has stopped reading
WELCOME_TIMEOUT = 120.0
FRAME = 1 / 60
PROMPT_ROWS = 4
DEFAULT_CELL = (8, 16)  # TerminalCellGeometry's default, where no pixel size is reported

MAXIMUM_ID = 0xFFFFFF
STRIP_ID = MAXIMUM_ID - 15
SCRATCH_ID = MAXIMUM_ID - 14
STORE_ID = MAXIMUM_ID - 13
QUERY_ID = MAXIMUM_ID - 12
NEVER_SENT_ID = MAXIMUM_ID - 11  # placed once, never transmitted: the negative control
PROBE_IDS = (STRIP_ID, SCRATCH_ID, STORE_ID, QUERY_ID, NEVER_SENT_ID)

Z_UNDER_TEXT = -1
Z_OVER_TEXT = 1                          # never 0: iTerm2 draws z=0 under text
Z_UNDER_FILLS = -(2 ** 31) // 2 - 1      # below INT32_MIN/2: under painted cells

LINE = (230, 30, 160)
INK = (240, 240, 240)
GREY_FILL = (70, 70, 70)
STRIPE_FILL = (38, 54, 78)
SELECTION_FILL = (40, 90, 170)
SEAM_UPPER = (70, 60, 120)
SEAM_LOWER = (40, 110, 70)
UNDERLINE_GREY = (150, 150, 160)  # each above 107, so a host misreading 58;2 as SGR codes ignores them

RESET = b"\x1b[0m"
# An empty final chunk: closes a chunked transmit a signal cut short, which a
# host would otherwise complete with the next program's first image. q=2
# keeps it quiet where the load it closes fails.
CLOSE_LOAD = b"\x1b_Gm=0,q=2;\x1b\\"
BOLD = b"\x1b[1m"
DIM = b"\x1b[2m"
ST = b"\x1b\\"

YES_NO = (("y", "yes"), ("n", "no"), ("s", "can't tell"))
REFUSED_HOSTS = {
    "Apple_Terminal": "Apple Terminal prints APC payloads as text "
                      "(Terminal-compatibility.md, \"What each host advertises\")",
}
# What a host's reply to a graphics command looks like: `ESC _ G keys ; message ESC \`.
REPLY = re.compile(rb"\x1b_G([^;\x1b]*);([^\x1b]*)\x1b\\")
# DA1's answer: the resync fence, a kind no reading uses (they fence with DSR 6,
# sync_probe with DSR 5), so an answer to it is never taken for theirs.
RESYNC = b"\x1b[c"
RESYNC_REPLY = re.compile(rb"\x1b\[\?[0-9;]*c")
OUT_OF_STEP = "not read: out of step"  # a reading skipped after a missed fence
# Terminal replies and key sequences mixed into what a person types.
NOISE = re.compile(rb"\x1b(?:\[[0-?]*[ -/]*[@-~]|[P_\]^X][^\x1b\x07]*(?:\x1b\\|\x07)?|[\x20-\x7e])?", re.S)


class Aborted(Exception):
    """The run was stopped: `q`, or a signal (Ctrl-C and Ctrl-\\ among them)."""


# MARK: - Escapes

def cup(row, column):
    return b"\x1b[%d;%dH" % (row, column)


def background(rgb):
    return b"\x1b[48;2;%d;%d;%dm" % tuple(rgb)


def foreground(rgb):
    return b"\x1b[38;2;%d;%d;%dm" % tuple(rgb)


def graphics(keys, payload=b""):
    return b"\x1b_G" + keys.encode("ascii") + (b";" + payload if payload else b"") + ST


def query():
    """`a=q`: the protocol's own handshake, one pixel under QUERY_ID."""
    return graphics("i=%d,s=1,v=1,a=q,t=d,f=24" % QUERY_ID, b"AAAA")


def transmit(pixels, image_id, width, height):
    """`a=t`: RGB `pixels` into the store under `image_id`, chunked, `q=0`."""
    return placement_probe.transmit(pixels, image_id, width, height).encode("ascii")


def place(image_id, placement_id, width, height, z=Z_UNDER_TEXT, hold_cursor=True, quiet=False):
    """A CLASSIC placement at the cursor: the image's top-left `width` x
    `height` pixels, at native size, from the cell's top-left corner. No `c`
    or `r`: with both, hosts disagree on letterboxing against stretching."""
    keys = "a=p,i=%d,p=%d,x=0,y=0,w=%d,h=%d" % (image_id, placement_id, width, height)
    if hold_cursor:
        keys += ",C=1"
    return graphics(keys + ",z=%d,q=%d" % (z, 2 if quiet else 0))


def delete(image_id, placement_id=None, free=False, quiet=True):
    """`d=i` deletes placements and keeps the data; `d=I` frees the data too."""
    keys = "a=d,d=%s,i=%d" % ("I" if free else "i", image_id)
    if placement_id is not None:
        keys += ",p=%d" % placement_id
    return graphics(keys + ",q=%d" % (2 if quiet else 0))


# MARK: - Replies

def replies(raw):
    """Every graphics reply in `raw`, as (keys, message); none for a
    reading that was not taken (None, or OUT_OF_STEP)."""
    found = []
    for keys, message in REPLY.findall(raw if isinstance(raw, bytes) else b""):
        fields = dict(pair.partition("=")[::2] for pair in keys.decode("latin-1").split(",") if pair)
        found.append((fields, message.decode("utf-8", "replace")))
    return found


def status(raw, image_id=None, placement_id=None):
    """The reply about (`image_id`, `placement_id`) as its code (`OK`,
    `ENOENT`, `EINVAL`, or whatever else the host names); `silent` when the
    fence came back with no reply; `no fence` when even the fence timed out.

    Every line shares one image id, so for a placement a reply that carries
    its `p` is the one. A reply with no `p` (a host may leave it out) is
    taken only when it is the one reply before the fence: otherwise it may
    be another command's about the same image, a transmit's late `OK`."""
    if raw is OUT_OF_STEP:
        return OUT_OF_STEP
    if raw is None:
        return "no fence"
    found = replies(raw)
    mine = [(fields, message) for fields, message in found
            if image_id is None or fields.get("i") == str(image_id)]
    if placement_id is not None:
        matching = [message for fields, message in mine if fields.get("p") == str(placement_id)]
        if not matching and len(found) == 1 and "p" not in found[0][0]:
            matching = [message for _, message in mine]
    else:
        matching = ([message for fields, message in mine if "p" not in fields]
                    or [message for _, message in mine])
    if not matching:
        return "silent"
    return matching[-1].split(":")[0].strip() or "empty"


def verdict(code, true_code, false_code):
    return True if code == true_code else False if code == false_code else None


# MARK: - Geometry

def winsize(fd):
    try:
        packed = fcntl.ioctl(fd, termios.TIOCGWINSZ, struct.pack("HHHH", 0, 0, 0, 0))
    except OSError:
        return {"rows": 24, "columns": 80, "xpixel": 0, "ypixel": 0}
    rows, columns, xpixel, ypixel = struct.unpack("HHHH", packed)
    return {"rows": rows or 24, "columns": columns or 80, "xpixel": xpixel, "ypixel": ypixel}


def xtwinops(raw):
    """`CSI 14 t` (text area, pixels), `CSI 16 t` (cell, pixels) and
    `CSI 18 t` (text area, cells), each as [height, width] or None."""
    def answer(code):
        match = re.search(rb"\x1b\[%d;(\d+);(\d+)t" % code, raw if isinstance(raw, bytes) else b"")
        return [int(match.group(1)), int(match.group(2))] if match else None
    return {"csi_14t_text_area_px": answer(4), "csi_16t_cell_px": answer(6),
            "csi_18t_text_area_cells": answer(8)}


CROP_RULES = {
    "ioctl": "ws_xpixel * columns // ws_col",
    "csi_14t": "CSI 14 t width * columns // CSI 18 t columns",
    "csi_16t": "CSI 16 t cell width * columns",
}


def crop_width(geometry, columns, windows=None, unit="ioctl"):
    """Pixels for `columns` cells, by the measure of a cell `unit` names:
    TIOCGWINSZ's (ws_xpixel x columns // ws_col, the design's rule),
    `CSI 14 t`'s or `CSI 16 t`'s, falling back to TIOCGWINSZ's when that
    measure was not answered. Multiplying first keeps a fractional cell
    width (iTerm2's) from losing a fraction of a pixel per column, which
    across 120 columns is ~30 px short."""
    windows = windows or {}
    if unit == "csi_16t":
        cell = windows.get("csi_16t_cell_px")
        if cell and cell[1]:
            return cell[1] * columns
    elif unit == "csi_14t":
        area, cells = windows.get("csi_14t_text_area_px"), windows.get("csi_18t_text_area_cells")
        across = (cells[1] if cells else 0) or geometry["columns"]
        if area and area[1] and across:
            return area[1] * columns // across
    if geometry["xpixel"] and geometry["columns"]:
        return geometry["xpixel"] * columns // geometry["columns"]
    return columns * DEFAULT_CELL[0]


def fine_variants(geometry, windows, run):
    """Q3's fine lines: (letter, rule, width) for a run of `run` cells by
    each measure of a cell, leaving out a width an earlier rule gave."""
    candidates = []
    xpixel, columns = geometry["xpixel"], geometry["columns"]
    if xpixel and columns:
        candidates.append(("ws_xpixel x %d // ws_col" % run, crop_width(geometry, run)))
        candidates.append(("%d x (ws_xpixel // ws_col)" % run, run * (xpixel // columns)))
    if windows.get("csi_14t_text_area_px"):
        candidates.append(("CSI 14 t width x %d // columns" % run,
                           crop_width(geometry, run, windows, "csi_14t")))
    cell = windows.get("csi_16t_cell_px")
    if cell and cell[1]:
        candidates.append(("%d x the CSI 16 t cell" % run, crop_width(geometry, run, windows, "csi_16t")))
    variants, seen = [], set()
    for rule, width in candidates:
        if width and width not in seen:
            seen.add(width)
            variants.append(("ABCD"[len(variants)], rule, width))
    return variants


def line_thickness(geometry):
    if geometry["ypixel"] and geometry["rows"]:
        cell_height = geometry["ypixel"] // geometry["rows"]
    else:
        cell_height = DEFAULT_CELL[1]
    return max(1, cell_height // 17)


def cell_widths(geometry, windows):
    """Every available measure of a cell's width, by its source."""
    widths = {}
    if geometry["xpixel"] and geometry["columns"]:
        widths["ioctl"] = geometry["xpixel"] // geometry["columns"]
    area, cells = windows.get("csi_14t_text_area_px"), windows.get("csi_18t_text_area_cells")
    columns = (cells[1] if cells else 0) or geometry["columns"]
    if area and area[1] and columns:
        widths["csi_14t"] = area[1] / columns
    cell = windows.get("csi_16t_cell_px")
    if cell and cell[1]:
        widths["csi_16t"] = cell[1]
    return widths


def unit_reading(advance, expected=10):
    if advance is None:
        return "no cursor report"
    if advance == 0:
        return "the cursor did not move: C=0 ignored, or the placement refused"
    ratio = advance / expected
    if 0.85 <= ratio <= 1.15:
        return "same unit"
    if 1.7 <= ratio <= 2.3:
        return "the placement's pixel is half this measure's (points against device pixels?)"
    if 0.4 <= ratio <= 0.6:
        return "the placement's pixel is twice this measure's"
    return "%.2fx: unexplained" % ratio


def unit_source(coarse):
    """Which measure of a cell is the placement's unit: TIOCGWINSZ when it
    is, another query when only that one is, None when none is, and
    "unmeasured" when no advance was read at all."""
    if not any(entry.get("advance") for entry in coarse.values()):
        return "unmeasured"
    same = [source for source, entry in coarse.items() if entry.get("reading") == "same unit"]
    if "ioctl" in same:
        return "ioctl"
    return same[0] if same else None


# MARK: - Readings

STORE_MEANINGS = {
    "shared": "one store for both screens: an image sent on the primary is found on the alternate",
    "per_screen": "a store per screen: the image stayed in the primary's store",
    "freed_by_switch": "the switch freed it: found on neither screen",
    "unclear": "no clear answer: see the replies",
    "untrusted": "the host answered OK for an id never sent, so no OK here means the data is there",
}
ACKNOWLEDGES_EVERYTHING = "the host answered OK for an id never sent: no OK or ENOENT here is evidence"


def acknowledges_everything(control):
    """Whether the negative control, a placement of an id never sent, was
    answered OK: then an OK says nothing, and neither does its absence."""
    return (control or {}).get("status") == "OK"


def q6_readings(auto, control=None):
    def code(key):
        return (auto.get(key) or {}).get("status")
    if acknowledges_everything(control):
        return {"lowercase_delete_keeps_data": None, "data_kept_with_no_placement": None,
                "uppercase_delete_frees": None, "unjudged": ACKNOWLEDGES_EVERYTHING}
    return {
        "lowercase_delete_keeps_data": verdict(code("replace_1"), "OK", "ENOENT"),
        "data_kept_with_no_placement": verdict(code("replace_1_after_none_left"), "OK", "ENOENT"),
        "uppercase_delete_frees": verdict(code("scratch_place_after_free"), "ENOENT", "OK"),
    }


def q8_readings(auto, control=None):
    def code(key):
        return (auto.get(key) or {}).get("status")
    if acknowledges_everything(control):
        return {"store": "untrusted", "store_meaning": STORE_MEANINGS["untrusted"],
                "ed2_keeps_data": None, "screen_round_trip_keeps_data": None,
                "unjudged": ACKNOWLEDGES_EVERYTHING}
    on_alternate, on_primary = code("store_lookup_on_alternate"), code("store_lookup_on_primary")
    if on_alternate == "OK":
        store = "shared"
    elif on_alternate == "ENOENT" and on_primary == "OK":
        store = "per_screen"
    elif on_alternate == "ENOENT" and on_primary == "ENOENT":
        store = "freed_by_switch"
    else:
        store = "unclear"
    return {
        "store": store,
        "store_meaning": STORE_MEANINGS[store],
        "ed2_keeps_data": verdict(code("ed2_replace"), "OK", "ENOENT"),
        "screen_round_trip_keeps_data": verdict(code("switch_replace"), "OK", "ENOENT"),
    }


def all_of(*values):
    """False if any is False, None if any is unknown, else True."""
    if any(value is False for value in values):
        return False
    if any(value is None for value in values):
        return None
    return True


def any_of(*values):
    """True if any is True, None if any is unknown, else False."""
    if any(value is True for value in values):
        return True
    if any(value is None for value in values):
        return None
    return False


def criteria(questions, control=None):
    """This host's half of each kill criterion, and the plan changes its
    answers call for. `control` is the reply to the placement of an id
    never sent."""
    def auto(name, key):
        entry = questions.get(name, {}).get("auto")
        return entry.get(key) if isinstance(entry, dict) else None

    def code(name, key):
        value = auto(name, key)
        return value.get("status") if isinstance(value, dict) else None

    def yes(name, key):
        human = questions.get(name, {}).get("human")
        answer = (human.get(key) or {}).get("answer") if isinstance(human, dict) else None
        return {"yes": True, "no": False}.get(answer)

    placed = code("Q1", "place")
    acknowledged = None if placed in (None, "no fence", OUT_OF_STEP) else placed == "OK"  # not read at all
    kill_inputs = {
        "q1_placed_and_drawn": all_of(acknowledged,
                                      yes("Q1", "visible"), yes("Q1", "on_boundary")),
        # The kill is a line that is off the boundary, or drawn in neither
        # layer. z=-1 hidden under the fills with z=+1 showing is a plan
        # change (below), not a failure.
        "q4_on_boundary_in_a_layer_that_shows": all_of(
            yes("Q4", "on_boundary"),
            any_of(yes("Q4", "under_text_on_every_band"), yes("Q4", "over_text_crosses_glyphs"))),
        # Both lines first, or a host that keeps one placement per image (so
        # that placing line 2 replaced line 1) would pass by removing nothing.
        "q6_removed_by_id": all_of(yes("Q6", "both_shown"), yes("Q6", "one_removed")),
        "q7_steady_with_2026": yes("Q7", "steady_with_2026"),
    }
    changes = []
    unjudged = []
    lost = [rewrite for letter, rewrite in (("B", "ESC[2K"), ("C", "writing over it"), ("D", "ECH"))
            if yes("Q5", "kept_" + letter) is False]
    if yes("Q5", "kept_A"):
        for rewrite in lost:
            changes.append("Q5: %s loses the line here: re-place after every such rewrite "
                           "of a marked row (~55 B each)" % rewrite)
    elif lost:
        unjudged.append("Q5: the control row A kept no line (or was not answered), so a line "
                        "missing from B, C or D says nothing about the rewrites")
    source = auto("Q3", "unit_revealed_by")
    if auto("Q3", "coarse") and source is None:
        changes.append("Q3: no query reveals this host's placement unit: exclude it")
    elif source not in (None, "ioctl", "unmeasured"):
        changes.append("Q3: the placement unit is %s's, not TIOCGWINSZ's: compute the crop "
                       "from it here" % source)
    if yes("Q4", "under_text_on_every_band") is False and yes("Q4", "over_text_crosses_glyphs"):
        changes.append("Q4: z=-1 does not show over every fill here and z=+1 does: z=+1 on "
                       "this host, which needs an identity for it")
    if yes("Q8", "visible_after_ed2") or yes("Q8", "visible_on_primary") or yes("Q8", "visible_after_return"):
        changes.append("Q8: lines outlive ESC[2J or the screen switch here: cleanup must "
                       "delete every line by id (the design does)")
    held = auto("Q2", "held")
    coarse = auto("Q3", "coarse") or {}
    if held and coarse and all(entry.get("advance") == 0 for entry in coarse.values()):
        # C=0 did not move the cursor either: this host moves it for no
        # placement, so a cursor that stayed put says nothing about C=1.
        held = None
        unjudged.append("Q2: no placement moved the cursor here, C=0 included, so C=1 "
                        "holding it is untested")
    return {
        "kill_inputs": kill_inputs,
        "kills_need": "Ghostty AND iTerm2 both failing Q1 or Q4, or neither passing Q6; "
                      "or both failing Q7 with mode 2026 on",
        "plan_changes": changes,
        "unjudged": unjudged,
        "q3_widths_ending_at_the_bar": [
            "%s (%s)" % (letter, ((auto("Q3", "fine_widths") or {}).get(letter) or {}).get("rule"))
            for letter in "ABCD" if yes("Q3", "ends_at_bar_" + letter)],
        "auto_signals": {
            "q1_acknowledged": acknowledged,
            "acknowledges_everything": None if control is None else acknowledges_everything(control),
            "q2_cursor_held": held,
            "q3_unit_revealed_by": source,
            "q6": auto("Q6", "readings"),
            "q7_decrqm_2026": auto("Q7", "decrqm_2026"),
            "q8": auto("Q8", "readings"),
        },
    }


# MARK: - Naming the record

_PROGRAM_NAMES = {"iTerm.app": "iterm2", "Apple_Terminal": "apple-terminal"}


def same_program(one, other):
    """Whether two names are one program's: `iterm2` and `iTerm2`, or
    `warpterminal` and `Warp`, one a prefix of the other once only letters
    and digits are left."""
    one, other = (re.sub(r"[^a-z0-9]", "", (name or "").lower()) for name in (one, other))
    return one.startswith(other) or other.startswith(one)


def host_identity(env, xtversion=None):
    """(`<host>-<version>`, where the name came from), spelled as the
    committed records spell it: TERM_PROGRAM and its version, then
    LC_TERMINAL (iTerm2 over ssh), then the XTVERSION reply (`kitty(0.42.1)`,
    `WezTerm 2024…`), then TERM. A variable naming a different program from
    the XTVERSION reply was inherited (kitty started from an iTerm2 shell
    keeps TERM_PROGRAM=iTerm.app), so the reply names the host then."""
    answered = None
    if xtversion:
        match = re.match(r"\s*([^\s(]+)[\s(]*([^\s)]*)", xtversion)
        answered = (match.group(1), match.group(2)) if match else (xtversion, None)
    variable = next((key for key in ("TERM_PROGRAM", "LC_TERMINAL") if env.get(key)), None)
    if variable:
        name = _PROGRAM_NAMES.get(env[variable], env[variable])
        version = env.get(variable + "_VERSION")
        source = variable
        if answered and not same_program(name, answered[0]):
            (name, version), source = answered, "XTVERSION, over an inherited %s=%s" % (variable, env[variable])
    elif answered:
        (name, version), source = answered, "XTVERSION"
    else:
        name, version, source = env.get("TERM") or "unknown-terminal", None, "TERM"
    name = re.sub(r"[^a-z0-9.]+", "-", name.lower()).strip("-") or "unknown-terminal"
    version = re.sub(r"[^A-Za-z0-9._-]+", "-", version or "").strip("-") or "unknown-version"
    return "%s-%s" % (name, version), source


def host_slug(env, xtversion=None):
    return host_identity(env, xtversion)[0]


def holds_person_answers(record):
    """Whether any question in `record` carries an answer a person gave."""
    return any(isinstance(entry, dict) and isinstance(entry.get("human"), dict) and entry["human"]
               for entry in (record.get("questions") or {}).values())


def file_holds_person_answers(path):
    try:
        with open(path) as handle:
            return holds_person_answers(json.load(handle))
    except (OSError, ValueError, AttributeError):
        return False


def answered_in_full(record):
    """A run a person answered to the end: interactive, never stopped, never
    gone automatic."""
    return (record.get("mode") == "interactive" and not record.get("aborted")
            and not record.get("went_automatic_at"))


def default_out_path(record, directory=None):
    """`data/<host>-hairline.json`. A run that was not answered to the end
    never replaces a record that holds a person's answers, whatever its
    flags: it goes beside it, as `<host>-hairline-aborted.json` when it was
    stopped and `<host>-hairline-auto.json` otherwise (an `--auto` run, or
    one whose questions went unanswered, at the welcome card or later)."""
    directory = directory or os.path.join(HERE, "data")
    path = os.path.join(directory, record["host"] + "-hairline.json")
    if answered_in_full(record) or not file_holds_person_answers(path):
        return path
    suffix = "-hairline-aborted.json" if record.get("aborted") else "-hairline-auto.json"
    return os.path.join(directory, record["host"] + suffix)


def write_by(fd, data, deadline):
    """Write all of `data` unless `deadline` (monotonic) passes first;
    whether all of it went. Non-blocking for the call, so a terminal that
    has stopped reading cannot hold the caller."""
    flags = fcntl.fcntl(fd, fcntl.F_GETFL)
    fcntl.fcntl(fd, fcntl.F_SETFL, flags | os.O_NONBLOCK)
    try:
        view = memoryview(data)
        while view:
            left = deadline - time.monotonic()
            if left <= 0 or not select.select([], [fd], [], left)[1]:
                return False
            try:
                view = view[os.write(fd, view):]
            except BlockingIOError:
                pass
        return True
    finally:
        fcntl.fcntl(fd, fcntl.F_SETFL, flags)


# MARK: - Keys

def drain(fd, wait=0.05):
    """Discard whatever is waiting on stdin (late replies, type-ahead), but
    stop the run if a `q` or Ctrl-C was typed in it: a person who pressed
    `q` during an automatic stretch meant it. Read whole before it is
    sifted, so a reply split across two reads is still a reply."""
    got = b""
    while select.select([fd], [], [], wait)[0]:
        data = os.read(fd, 4096)
        if not data:
            break
        got += data
    typed = NOISE.sub(b"", got)
    if b"\x03" in typed or b"q" in typed:
        raise Aborted("quit key")


def read_choice(fd, keys, timeout):
    """The first key pressed that is one of `keys` (any key, for None), or
    None after `timeout` seconds. Terminal replies are ignored. `q` and
    Ctrl-C, which raw mode delivers as a byte, stop the run."""
    deadline = time.monotonic() + timeout
    while True:
        left = deadline - time.monotonic()
        if left <= 0 or not select.select([fd], [], [], left)[0]:
            return None
        data = os.read(fd, 4096)
        if not data:
            return None
        for byte in NOISE.sub(b"", data):
            if byte in (0x03, ord("q")):
                raise Aborted("quit key")
            key = chr(byte).lower()
            if keys is None or key in keys:
                return key


def stop_requested(fd):
    """Raise Aborted if `q` or Ctrl-C is waiting; discard anything else."""
    if select.select([fd], [], [], 0)[0]:
        data = NOISE.sub(b"", os.read(fd, 4096))
        if b"\x03" in data or b"q" in data:
            raise Aborted("quit key")


def legend(choices):
    return "   ".join("[%s] %s" % choice for choice in choices) + "      q quits"


def pad(text, cells):
    return text[:cells] + " " * max(0, cells - len(text))


# MARK: - The probe

class Probe:
    def __init__(self, fd, auto):
        self.fd = fd
        self.auto = auto
        self.started_auto = auto
        self.went_automatic = None
        self.aborted = None
        self.signalled = None
        self.current = "start"
        self.out_of_step = False     # a missed fence's replies may still be queued
        self.resyncs_unanswered = 0  # resync fences sent and not yet answered
        self.missed_fences = []
        self.on_alternate = False
        self.loading = False  # a chunked transmit is being written
        self.graphics_answered = False
        self.control = None
        self.strip_stale = True
        self.header = {}
        self.questions = {}
        self.windows = {}
        self.cell_widths = {}
        self.geometry = winsize(fd)
        self.rows, self.columns = self.geometry["rows"], self.geometry["columns"]
        self.thickness = line_thickness(self.geometry)
        self.strip_width = 2048
        self.crop_unit = "ioctl"
        self.subtitle = ""

    # Output.

    def write(self, *chunks):
        data = memoryview(b"".join(chunks))
        while data:
            data = data[os.write(self.fd, data):]

    def text(self, row, column, text, style=b""):
        """`text` at (row, column), cut at the right edge so nothing wraps."""
        room = max(0, self.columns - column + 1)
        self.write(cup(row, column), style, text[:room].encode("utf-8"), RESET)

    def checkpoint(self):
        """Stop here if a signal asked to stop and its Aborted was lost (a
        library's `except Exception` can swallow it)."""
        if self.signalled is not None:
            raise Aborted(self.signalled)

    def settle(self):
        """Before a reading: if a missed fence may have left its replies
        queued, resync first, so the reading reads its own. True when the
        probe is in step with the host's replies."""
        self.checkpoint()
        if self.out_of_step:
            self.resync(None, QUERY_TIMEOUT)
        return not self.out_of_step

    def resync(self, why, timeout=IMAGE_TIMEOUT):
        """After a fence that never came back, its late replies and its DSR
        are still on their way, and the next reading would take them for its
        own (and every reading after it the one before's). Send DA1 and
        discard everything up to its answer, counting answers to any earlier
        resync that went unanswered, so one of those is not taken for this."""
        self.resyncs_unanswered += 1
        os.write(self.fd, RESYNC)
        got = b""
        deadline = time.monotonic() + timeout
        while len(RESYNC_REPLY.findall(got)) < self.resyncs_unanswered:
            left = deadline - time.monotonic()
            if left <= 0 or not select.select([self.fd], [], [], left)[0]:
                break
            got += os.read(self.fd, 4096)
        self.resyncs_unanswered = max(0, self.resyncs_unanswered - len(RESYNC_REPLY.findall(got)))
        self.out_of_step = self.resyncs_unanswered > 0
        if why is not None:  # a fence missed, not another try before a reading
            self.missed_fences.append({"during": self.current, "why": why, "resyncs": 0})
        missed = self.missed_fences[-1]
        missed["resyncs"] += 1
        missed["in_step_after"] = not self.out_of_step
        if not self.out_of_step:
            missed["in_step_again_by"] = self.current

    def ask(self, command, timeout=IMAGE_TIMEOUT):
        """`command` fenced by DSR (placement_probe.ask): what came back
        before the fence, or None when the fence never did. Out of step, the
        command still goes out (a card may be drawing with it) but nothing
        is read, which would be an earlier command's reply, and the answer
        is OUT_OF_STEP. Reading nothing also leaves the resync's answers to
        the resync to count."""
        if not self.settle():
            self.write(command)
            return OUT_OF_STEP
        raw = placement_probe.ask(self.fd, command, timeout)
        if raw is None:
            self.resync("a fence that never came back")
        return raw

    def cursor(self):
        """DSR: (row, column), or None when it was not answered or not asked
        (out of step)."""
        if not self.settle():
            return None
        position = placement_probe.cursor(self.fd, IMAGE_TIMEOUT)
        if position is None:
            self.resync("a cursor report that never came")
        return position

    def exchange(self, command, image_id, placement_id=None):
        raw = self.ask(command)
        return {"reply": OUT_OF_STEP if raw is OUT_OF_STEP else placement_probe.render(raw),
                "status": status(raw, image_id, placement_id)}

    # Screens.

    def enter_alternate(self):
        # The flag first: a signal between the two must still leave the
        # restore sending ?1049l (harmless if the switch never went out).
        self.on_alternate = True
        self.strip_stale = True
        self.write(b"\x1b[?1049h\x1b[?25l\x1b[H")

    def leave_alternate(self):
        self.write(b"\x1b[?1049l")  # the flag after, for the same reason
        self.on_alternate = False
        self.strip_stale = True

    def measure_geometry(self):
        self.geometry = winsize(self.fd)
        self.rows, self.columns = self.geometry["rows"], self.geometry["columns"]
        self.windows = xtwinops(self.ask(b"\x1b[14t\x1b[16t\x1b[18t", QUERY_TIMEOUT))
        self.cell_widths = cell_widths(self.geometry, self.windows)
        self.thickness = line_thickness(self.geometry)
        area = self.windows["csi_14t_text_area_px"]
        self.strip_width = max([2048, self.geometry["xpixel"], area[1] if area else 0]
                               + [crop_width(self.geometry, self.columns, self.windows, unit)
                                  for unit in CROP_RULES]
                               + [int(round(10 * width)) + 1 for width in self.cell_widths.values()])
        self.subtitle = "%s   %dx%d cells   ws_xpixel %d   line %d px, z=-1 unless named" % (
            self.header.get("host"), self.columns, self.rows, self.geometry["xpixel"], self.thickness)

    # The strip and its lines.

    def ensure_strip(self):
        """Send the strip unless it is in the store with a placement; the
        reply, or None when nothing was sent."""
        if not self.strip_stale:
            return None
        pixels = bytes(LINE) * (self.strip_width * self.thickness)
        reply = self.send_image(pixels, STRIP_ID, self.strip_width, self.thickness)
        self.strip_stale = False
        return reply

    def send_image(self, pixels, image_id, width, height):
        """`a=t` of `pixels` under `image_id`, then its reply, fenced. While
        the chunks are being written, and only then, the restore knows a
        chunked load may be left open."""
        self.settle()
        self.loading = True
        self.write(transmit(pixels, image_id, width, height))
        self.loading = False
        return self.exchange(b"", image_id)

    def crop(self, columns):
        """Pixels for `columns` cells, by TIOCGWINSZ's measure until Q3 finds
        that another one is the placement's unit."""
        return crop_width(self.geometry, columns, self.windows, self.crop_unit)

    def line(self, row, column, columns, placement_id, z=Z_UNDER_TEXT, width=None, quiet=False):
        """A line along the TOP edge of `row`, from `column` across `columns`
        cells (or `width` pixels); the reply, unless `quiet`."""
        command = cup(row, column) + place(STRIP_ID, placement_id, width or self.crop(columns),
                                           self.thickness, z=z, quiet=quiet)
        if quiet:
            self.write(command)
            return None
        return self.exchange(command, STRIP_ID, placement_id)

    def span(self, first):
        return max(8, min(40, self.columns - first - 1))

    # Cards.

    def card(self, number, title, *lines):
        """A clean screen: the last card's lines deleted by id, the text
        erased from the home position (never ED 2, which is Q8's subject)."""
        self.checkpoint()
        if self.graphics_answered:
            self.write(delete(STRIP_ID))
            self.strip_stale = True
        self.write(RESET, b"\x1b[H\x1b[J")
        self.text(1, 2, "hairline probe  %s  %s" % (number, title), BOLD)
        self.text(2, 2, self.subtitle, DIM)
        for index, line in enumerate(lines):
            self.text(4 + index, 2, line)

    def pair(self, upper, first, span, above="▲ above", below="▼ below"):
        """Two labelled rows with bars at the run's ends: ▕ ends on the left
        edge of `first`, ▏ starts on the right edge of the run's last cell."""
        for row, label in ((upper, above), (upper + 1, below)):
            self.text(row, 2, label)
            self.text(row, first - 1, "▕")
            self.text(row, first + span, "▏")

    def prompt(self, question=None, choices=YES_NO):
        top = self.rows - PROMPT_ROWS + 1
        self.write(*[cup(top + offset, 1) + b"\x1b[2K" for offset in range(PROMPT_ROWS)])
        if question is None:
            return
        for offset, line in enumerate(textwrap.wrap(question, max(20, self.columns - 4))[:PROMPT_ROWS - 1]):
            self.text(top + offset, 3, line, BOLD)
        self.text(self.rows, 3, legend(choices), DIM)

    def section(self, name, what):
        self.current = name
        entry = {"what": what, "auto": {}, "human": {}}
        self.questions[name] = entry
        return entry

    def go_automatic(self, where):
        self.auto = True
        self.went_automatic = where

    def human(self, entry, key, question, choices=YES_NO):
        """Ask a person; record and return the answer. Nothing in --auto."""
        if self.auto:
            return None
        self.prompt(question, choices)
        drain(self.fd)
        pressed = read_choice(self.fd, [key_ for key_, _ in choices], ANSWER_TIMEOUT)
        self.prompt(None)
        if pressed is None:
            self.go_automatic("%s %s" % (next(name for name, value in self.questions.items()
                                              if value is entry), key))
            answer = "no answer within %d s" % ANSWER_TIMEOUT
        else:
            answer = dict(choices)[pressed]
        entry["human"][key] = {"question": question, "answer": answer}
        return answer

    def wait_for_key(self, where, timeout=ANSWER_TIMEOUT):
        if self.auto:
            return
        drain(self.fd)
        if read_choice(self.fd, None, timeout) is None:
            self.go_automatic(where)

    # The run.

    def run(self):
        self.enter_alternate()
        self.header["stamp"] = probe_stamp.stamp(self.fd, "hairline_probe", use_alt=True)
        self.header["xtversion"] = sync_probe.xtversion(self.fd)
        self.header["host"], self.header["host_named_from"] = host_identity(
            self.header["stamp"]["env"], self.header["xtversion"])
        # DECSC, the query, DECRC and erase-below, as TUIkit's handshake asks
        # it: whatever a host that prints APC printed is wiped at once.
        raw = self.ask(b"\x1b7" + query() + b"\x1b8\x1b[J")
        self.header["graphics_query"] = {"reply": placement_probe.render(raw),
                                         "status": status(raw, QUERY_ID)}
        self.graphics_answered = bool(replies(raw))
        self.welcome()
        self.measure_geometry()
        self.header["geometry"] = dict(self.geometry, xtwinops=self.windows, cell_widths=self.cell_widths)
        if self.graphics_answered:
            # The negative control: a placement of an id nothing was ever
            # sent under must answer ENOENT. A host that answers OK (the
            # xterm.js beta acknowledges placements it never draws) makes
            # every OK-against-ENOENT reading below worthless.
            self.write(RESET, b"\x1b[H\x1b[J")
            self.control = self.exchange(cup(self.rows, 1) + place(NEVER_SENT_ID, 1, 1, 1),
                                         NEVER_SENT_ID, 1)
            self.header["acknowledgement_control"] = dict(
                self.control, placed="an id never sent (%d)" % NEVER_SENT_ID, expected="ENOENT",
                acknowledges_everything=acknowledges_everything(self.control))
            for step in (self.q1_q2, self.q3, self.q4, self.q5, self.q6, self.q7, self.q8, self.q9):
                step()
        else:
            for name in ("Q1", "Q2", "Q3", "Q4", "Q5", "Q6", "Q7", "Q8", "Q9"):
                entry = self.section(name, "skipped: no reply to a=q, so no graphics were sent")
                entry["human"] = "not asked: no graphics"
            self.questions["Q1"]["auto"]["place"] = {"reply": None, "status": "not sent"}
        self.q10()

    def welcome(self):
        if self.auto:
            return
        self.card("0/9", "thin lines between text rows, with the Kitty graphics protocol",
                  "Each card draws something and asks about it at the bottom of the screen.",
                  "Answer with a key: y yes, n no, s can't tell. q or Ctrl-C stops the run,",
                  "and what was answered is kept. Look closely: a line is one or two pixels thick.",
                  "",
                  "The graphics query (a=q) answered: %s." % self.header["graphics_query"]["status"]
                  if self.graphics_answered else
                  "No answer to the graphics query (a=q): only the last card, a fallback, is shown.")
        if self.rows < 30 or self.columns < 80:
            self.text(11, 2, "This window is %dx%d. At least 80x30 shows every card whole: "
                             "resize it now if you can." % (self.columns, self.rows), BOLD)
        self.text(13, 2, "Press any key to begin.")
        self.wait_for_key("the welcome card", WELCOME_TIMEOUT)

    def q1_q2(self):
        q1 = self.section("Q1", "Is a classic placement acknowledged, and drawn on the row boundary?")
        q2 = self.section("Q2", "Does C=1 leave the cursor where it was?")
        q2["human"] = "no card: the cursor report is the answer"
        upper, first = 8, 11
        lower, span = upper + 1, self.span(first)
        self.card("1/9", "Q1 + Q2: one classic placement, and C=1",
                  "One line is placed along the TOP edge of the ▼ row, under the text (z=-1),",
                  "from the bar ▕ on the left to the bar ▏ on the right.")
        self.pair(upper, first, span)
        self.text(upper, first + 1, "the line belongs under this row"[:span - 2])
        self.text(lower, first + 1, "and over this one"[:span - 2])
        q1["auto"]["transmit"] = self.ensure_strip()
        self.write(cup(lower, first))
        before = self.cursor()
        q1["auto"]["place"] = self.line(lower, first, span, 1)
        after = self.cursor()
        # A refused placement leaves the cursor where it was too: only a
        # placement the host took says anything about C=1.
        taken = (q1["auto"]["place"] or {}).get("status") == "OK"
        q2["auto"] = {"cursor_before": before, "cursor_after": after,
                      "held": None if not (taken and before and after) else tuple(before) == tuple(after)}
        self.human(q1, "visible", "Is there a thin coloured line near the rows marked ▲ and ▼?")
        self.human(q1, "on_boundary", "Is it exactly on the boundary between rows %d (▲) and %d (▼): "
                   "along the top edge of the ▼ row, not through the middle of either row?" % (upper, lower))
        self.human(q1, "ends", "Does it start at the bar ▕ (the left edge of column %d) and end at "
                   "the bar ▏ (the right edge of column %d), within a pixel or two at each end?"
                   % (first, first + span - 1))

    def q3(self):
        q3 = self.section("Q3", "What is the placement's pixel unit, to the pixel?")
        self.card("2/9", "Q3: the pixel unit, coarse",
                  "Lines 10 cells wide by each measure of a cell, placed with C=0 so the "
                  "cursor's advance can be read back.")
        q3["auto"]["transmit"] = self.ensure_strip()
        coarse = {}
        for index, (source, cell_width) in enumerate(sorted(self.cell_widths.items())):
            row, width, placement = 7 + index, int(round(10 * cell_width)), 31 + index
            self.write(cup(row, 1))
            before = self.cursor()
            reply = self.exchange(cup(row, 1) + place(STRIP_ID, placement, width, self.thickness,
                                                      hold_cursor=False), STRIP_ID, placement)
            after = self.cursor()
            self.write(delete(STRIP_ID, placement))
            advance = after[1] - before[1] if before and after else None
            coarse[source] = {"cell_width": cell_width, "width_px": width, "status": reply["status"],
                              "reply": reply["reply"], "cursor_before": before, "cursor_after": after,
                              "advance": advance, "reading": unit_reading(advance)}
        q3["auto"]["coarse"] = coarse
        source = q3["auto"]["unit_revealed_by"] = unit_source(coarse)
        # The plan change "the unit is CSI 14 t's or 16 t's: compute the crop
        # from it", applied here, so that Q4's columns are as wide as drawn.
        if source in ("csi_14t", "csi_16t"):
            self.crop_unit = source
        q3["auto"]["crop_from_here_on"] = {"unit": self.crop_unit, "rule": CROP_RULES[self.crop_unit]}
        # Fine: lines that end a few columns short of the window's edge, so
        # that a line too long shows past its bar instead of being clipped
        # by the edge of the grid and looking right.
        run = max(10, self.columns - 4)
        variants = fine_variants(self.geometry, self.windows, run)
        q3["auto"]["fine_run_columns"] = run
        q3["auto"]["fine_widths"] = {letter: {"rule": rule, "width_px": width}
                                     for letter, rule, width in variants}
        if self.auto or not variants:
            return
        self.card("2/9", "Q3: which width ends exactly at its bar?",
                  "Each line runs from column 1 along the top of the row under its label, %d cells "
                  "long." % run,
                  "The bar ▏ above its end marks the right edge of column %d: the end of the run." % run)
        q3["auto"]["fine_transmit"] = self.ensure_strip()
        for index, (letter, rule, width) in enumerate(variants):
            upper = 8 + 3 * index
            self.text(upper, 2, ("%s  %s = %d px" % (letter, rule, width))[:run - 2])
            self.text(upper, run + 1, "▏")
            q3["auto"]["fine_" + letter] = self.line(upper + 1, 1, run, 34 + index, width=width)
        for letter, rule, _ in variants:
            self.human(q3, "ends_at_bar_" + letter, "Line %s (%s): does its right end line up with "
                       "the left edge of the bar ▏ above it, neither short of it nor past it?"
                       % (letter, rule))

    def q4(self):
        q4 = self.section("Q4", "Is the line on the boundary, and in the right layer?")
        self.card("3/9", "Q4: which layer the line is drawn in",
                  "Each band: descenders on its upper row, glyphs reaching the top of the cell on",
                  "its lower row, and a line along the boundary between them, in three z columns.",
                  "Each column's line ends at the bar ▏ after it.")
        self.ensure_strip()
        group = max(11, min(16, (self.columns - 14) // 3 - 2))
        layers = (("z=-1", Z_UNDER_TEXT), ("z=+1", Z_OVER_TEXT), ("z<INT32_MIN/2", Z_UNDER_FILLS))
        starts = [14 + index * (group + 2) for index in range(len(layers))]
        for (label, _), start in zip(layers, starts):
            self.text(7, start, label, BOLD)
        bands = (("default", None), ("grey fill", GREY_FILL), ("stripe", STRIPE_FILL),
                 ("selection", SELECTION_FILL))
        placements = {}
        placement = 41
        for index, (band, fill) in enumerate(bands):
            upper = 8 + 3 * index
            self.text(upper + 1, 2, band)
            style = background(fill) + foreground(INK) if fill else b""
            for (label, z), start in zip(layers, starts):
                self.text(upper, start, pad("gjpqy gjpqy", group), style)
                self.text(upper + 1, start, "│┼█▀ ÉÅ 😀" + " " * (group - 10), style)  # 10 cells
                # Where this column's line must end: a line that runs on
                # into the next column (a unit Q3 could not name) shows it.
                self.text(upper, start + group, "▏")
                placements["%s, %s" % (band, label)] = self.line(upper + 1, start, group, placement, z=z)
                placement += 1
        q4["auto"]["placements"] = placements
        q4["auto"]["crop"] = {"unit": self.crop_unit, "column_cells": group,
                              "column_px": self.crop(group)}
        self.human(q4, "under_text_on_every_band", "Column z=-1: is the line visible on all four "
                   "bands (default, grey fill, stripe, selection)?")
        self.human(q4, "glyphs_over_line", "Column z=-1: where │ ┼ █ ▀ (and É Å 😀, if they reach "
                   "the top of the cell) meet the line, do they draw OVER it?")
        self.human(q4, "over_text_crosses_glyphs", "Column z=+1: is the line drawn OVER those "
                   "glyphs, visible across │ ┼ █ ▀?")
        self.human(q4, "under_fills_default_only", "Column z<INT32_MIN/2: is the line visible on "
                   "the default band ONLY, hidden under the three painted bands?")
        self.human(q4, "on_boundary", "Wherever a line shows, is it on the boundary between its "
                   "band's two rows: below the descenders of gjpqy, along the top of the lower row?")

    def q5(self):
        q5 = self.section("Q5", "Do rewrites of the row the line sits on keep it?")
        self.card("4/9", "Q5: rewriting the row under the line",
                  "Four lines are placed; then rows B, C and D are rewritten the ways TUIkit "
                  "rewrites a row.")
        self.ensure_strip()
        first = 5
        span = self.span(first)
        fill = background(GREY_FILL) + foreground(INK)

        def written(text):
            return fill + pad(text, span).encode("utf-8") + RESET

        cases = (
            ("A", "left alone (the control)", None),
            ("B", "ESC[2K, then written again",
             lambda row: cup(row, 1) + b"\x1b[2K" + cup(row, first) + written(" rewritten after ESC[2K")),
            ("C", "written over, nothing erased",
             lambda row: cup(row, first) + written(" written over the line")),
            ("D", "ECH, then written",
             lambda row: cup(row, first) + b"\x1b[%dX" % span + fill + b" after ECH" + RESET),
        )
        for index, (letter, what, _) in enumerate(cases):
            upper = 7 + 3 * index
            self.text(upper, 2, "%s  the line under this row: %s" % (letter, what))
            self.write(cup(upper + 1, first), written(" the row as first drawn"))
            q5["auto"][letter] = self.line(upper + 1, first, span, 61 + index)
        self.ask(b"")  # fenced: every line is placed before any row is rewritten
        time.sleep(0.3)
        for index, (_, _, rewrite) in enumerate(cases):
            if rewrite:
                self.write(rewrite(8 + 3 * index))
        self.ask(b"")
        for letter, what, _ in cases:
            self.human(q5, "kept_" + letter, "Row %s (%s): is its line still there, along the top "
                       "edge of the grey row?" % (letter, what))

    def q6(self):
        q6 = self.section("Q6", "Can one line be deleted by (i, p), and placed again without "
                                "re-sending the strip?")
        auto = q6["auto"]
        self.card("5/9", "Q6: delete one line by (i, p), then place it again",
                  "Two placements of the same strip: line 1 and line 2.")
        auto["transmit"] = self.ensure_strip()
        first = 11
        span = self.span(first)
        rows = {1: 8, 2: 11}
        for number, row in rows.items():
            self.pair(row - 1, first, span, "", "line %d" % number)
        auto["place_1"] = self.line(rows[1], first, span, 71)
        auto["place_2"] = self.line(rows[2], first, span, 72)
        self.human(q6, "both_shown", "Are there two lines: line 1 (between rows %d and %d) and "
                   "line 2 (between rows %d and %d)?" % (rows[1] - 1, rows[1], rows[2] - 1, rows[2]))
        auto["delete_1"] = self.exchange(delete(STRIP_ID, 71, quiet=False), STRIP_ID, 71)
        self.human(q6, "one_removed", "Line 1 was deleted by its (i, p). Has line 1 gone, with "
                   "line 2 still there?")
        auto["replace_1"] = self.line(rows[1], first, span, 71)
        self.human(q6, "replaced", "Line 1 was placed again without re-sending the strip. Is it "
                   "back, in the same place?")
        self.write(delete(STRIP_ID, 71), delete(STRIP_ID, 72))
        self.ask(b"")
        auto["replace_1_after_none_left"] = self.line(rows[1], first, span, 71)
        self.human(q6, "replaced_after_none_left", "Both lines were deleted, leaving the strip "
                   "with no placement; then line 1 was placed again without re-sending it. Is "
                   "line 1 back?")
        self.human(q6, "line_2_still_gone", "And is line 2 still gone?")
        # The cleanup path: d=I frees the data, so a placement must fail.
        corner = cup(self.rows - PROMPT_ROWS, 1)
        auto["scratch_transmit"] = self.send_image(bytes(LINE) * 4, SCRATCH_ID, 4, 1)
        auto["scratch_place"] = self.exchange(corner + place(SCRATCH_ID, 1, 1, 1), SCRATCH_ID, 1)
        auto["scratch_free"] = self.exchange(delete(SCRATCH_ID, free=True, quiet=False), SCRATCH_ID)
        auto["scratch_place_after_free"] = self.exchange(corner + place(SCRATCH_ID, 1, 1, 1), SCRATCH_ID, 1)
        self.write(delete(SCRATCH_ID, free=True))
        auto["readings"] = q6_readings(auto, self.control)

    def q7(self):
        q7 = self.section("Q7", "Does a line re-placed every frame flicker or tear against its "
                                "text, with and without mode 2026?")
        top, first = 7, 11
        span = self.span(first)
        travel = max(3, min(30, self.rows - PROMPT_ROWS - top - 1))
        self.card("6/9", "Q7: a line moving with its text",
                  "Two coloured rows, with the line on their seam, move down %d rows and back, "
                  "three times, at 60 Hz." % travel)
        # sync_probe's own rule for asking DECRQM: only of a host that names itself.
        program = self.header["stamp"]["env"].get("TERM_PROGRAM")
        identified = (self.header["xtversion"] is not None
                      or program in sync_probe._DECRQM_SAFE_TERM_PROGRAMS)
        if not self.settle():  # sync_probe's helpers read the replies directly
            q7["auto"]["decrqm_2026"] = q7["auto"]["leak"] = OUT_OF_STEP
        else:
            q7["auto"]["decrqm_2026"] = sync_probe.decrqm(self.fd, 2026) if identified else (
                "not asked (a host that did not identify itself may print DECRQM's final byte)")
            self.write(cup(self.rows - PROMPT_ROWS, 1))
            q7["auto"]["leak"] = sync_probe.leak_check(self.fd)
        q7["auto"]["travel_rows"] = travel
        q7["auto"]["frame_seconds"] = round(FRAME, 4)
        for synchronised, key, label in ((False, "steady_without_2026", "WITHOUT"),
                                         (True, "steady_with_2026", "WITH")):
            while not self.auto:
                self.text(5, 2, pad("Next: %s mode 2026. Watch the line on the seam between the "
                                    "two coloured rows." % label, self.columns - 2), BOLD)
                time.sleep(1.5)
                self.ensure_strip()
                self.motion(synchronised, top, travel, first, span)
                answer = self.human(q7, key, "%s mode 2026: did the line stay on the seam between "
                                    "the two coloured rows at every step, with no flicker, gap or "
                                    "tearing?" % label.capitalize(),
                                    YES_NO + (("r", "run it again"),))
                if answer != "run it again":
                    break

    def motion(self, synchronised, top, travel, first, span):
        """Down `travel` rows and back, three times, one frame per row:
        the text first, then the same (i, p) placed again on the seam."""
        upper_text = pad("  the line should stay on this seam", span).encode("utf-8")
        lower_text = pad("  between these two coloured rows", span).encode("utf-8")
        blank = b" " * span
        path = (list(range(travel)) + list(range(travel - 2, 0, -1))) * 3
        previous = None
        deadline = time.monotonic()
        for step in path:
            row = top + step
            frame = [sync_probe.BEGIN] if synchronised else []
            if previous is not None:
                for stale in {previous, previous + 1} - {row, row + 1}:
                    frame += [cup(stale, first), blank]
            frame += [cup(row, first), background(SEAM_UPPER), foreground(INK), upper_text, RESET,
                      cup(row + 1, first), background(SEAM_LOWER), foreground(INK), lower_text, RESET,
                      cup(row + 1, first),
                      place(STRIP_ID, 80, self.crop(span), self.thickness, quiet=True)]
            if synchronised:
                frame.append(sync_probe.END)
            self.write(*frame)
            previous = row
            stop_requested(self.fd)
            deadline += FRAME
            time.sleep(max(0.0, deadline - time.monotonic()))
        self.write(delete(STRIP_ID, 80), cup(previous, first), blank, cup(previous + 1, first), blank)
        self.strip_stale = True

    def q8(self):
        q8 = self.section("Q8", "What do ESC[2J and the alternate-screen switch do to a line and "
                                "its strip?")
        auto = q8["auto"]
        upper, first = 8, 11
        lower, span = upper + 1, self.span(first)
        where = "between rows %d and %d" % (upper, lower)

        # (a) ED 2.
        self.card("7/9", "Q8a: ESC[2J",
                  "A line is placed %s; then the screen is cleared with ESC[2J." % where)
        auto["ed2_transmit"] = self.ensure_strip()
        self.pair(upper, first, span)
        auto["ed2_place"] = self.line(lower, first, span, 91)
        self.ask(b"")
        if not self.auto:
            time.sleep(1.0)
        self.write(b"\x1b[2J")
        self.strip_stale = True
        self.text(1, 2, "hairline probe  7/9  Q8a: the screen was just cleared with ESC[2J", BOLD)
        self.pair(upper, first, span)  # text only, drawn again so the place can be found
        self.human(q8, "visible_after_ed2", "Is a thin coloured line still visible %s, where one "
                   "was placed before the clear?" % where)
        auto["ed2_replace"] = self.line(lower, first, span, 91)
        self.write(delete(STRIP_ID, 91))

        # (b) ?1049l, then ?1049h.
        self.card("7/9", "Q8b: ?1049l and ?1049h",
                  "A line is placed %s; then the probe shows your primary screen, and comes back." % where)
        auto["switch_transmit"] = self.ensure_strip()
        self.pair(upper, first, span)
        auto["switch_place"] = self.line(lower, first, span, 92)
        if not self.auto:
            # Nothing is written on the primary screen: it would stay in the
            # shell's scrollback, and near the bottom it would scroll the
            # screen before the person looked. So the question comes after.
            self.text(5, 2, "Next: your primary screen, until you press a key again.", BOLD)
            self.text(6, 2, "Look for a thin coloured line anywhere on it; the question comes "
                            "when you are back.", BOLD)
            self.text(7, 2, "Press any key to go there.")
            self.wait_for_key("Q8 going to the primary screen")
        self.leave_alternate()
        self.wait_for_key("Q8 on the primary screen")
        self.enter_alternate()
        self.text(1, 2, "hairline probe  7/9  Q8b: back on the alternate screen (?1049l, then ?1049h)", BOLD)
        self.pair(upper, first, span)
        self.human(q8, "visible_on_primary", "On your primary screen just now (?1049l): was a thin "
                   "coloured line visible anywhere on it?")
        self.human(q8, "visible_after_return", "Is the line placed before the switch visible "
                   "%s now?" % where)
        auto["switch_replace"] = self.line(lower, first, span, 92)
        auto["switch_retransmit"] = self.ensure_strip()
        auto["switch_place_after_retransmit"] = self.line(lower, first, span, 92)
        self.human(q8, "visible_after_resend", "The strip was sent again and the line placed "
                   "again. Is there a line %s now?" % where)

        # (c) One store, or one per screen? Looked up by a 1x1 placement:
        # `a=q` would re-create the image it asks about.
        self.card("7/9", "Q8c: one image store, or one per screen?",
                  "Automatic: the screen switches four times.")
        self.ask(b"")
        self.leave_alternate()
        auto["store_transmit_on_primary"] = self.send_image(bytes(LINE) * 4, STORE_ID, 4, 1)
        self.enter_alternate()
        auto["store_lookup_on_alternate"] = self.exchange(
            cup(self.rows, 1) + place(STORE_ID, 1, 1, 1), STORE_ID, 1)
        self.write(delete(STORE_ID, 1))
        self.leave_alternate()
        auto["store_lookup_on_primary"] = self.exchange(place(STORE_ID, 1, 1, 1), STORE_ID, 1)
        self.write(delete(STORE_ID, free=True))
        self.enter_alternate()
        auto["readings"] = q8_readings(auto, self.control)

    def q9(self):
        q9 = self.section("Q9", "Where does the line go when the window is resized?")
        if self.auto:
            return
        upper, first = 8, 11
        span = self.span(first)
        self.card("8/9", "Q9 (optional): resize the window",
                  "Resize the window now, narrower and then wider again, and watch the line.",
                  "Or press s to skip it without resizing.")
        q9["auto"]["transmit"] = self.ensure_strip()
        self.pair(upper, first, span)
        q9["auto"]["place"] = self.line(upper + 1, first, span, 95)
        q9["auto"]["size_before"] = winsize(self.fd)
        self.human(q9, "after_resize", "After resizing: where is the line that was between the ▲ "
                   "and ▼ rows? (s if you did not resize)",
                   (("y", "on the boundary"), ("m", "moved"), ("g", "gone"), ("s", "skipped")))
        q9["auto"]["size_after"] = winsize(self.fd)
        self.measure_geometry()  # XTWINOPS too: Q10's line is cropped by the same unit

    def q10(self):
        q10 = self.section("Q10", "Without graphics: can an underline in a colour of its own "
                                  "(SGR 4 + 58) stand in for the line?")
        if self.auto:
            return
        self.card("9/9", "Q10: the fallback without graphics",
                  "Rows A, B and D are underlined; in C, the lower row is overlined (SGR 53).")
        span = self.span(4)
        grey = ("%d;%d;%d" % UNDERLINE_GREY).encode("ascii")
        cases = (
            ("A", "SGR 4 + 58;2;" + grey.decode(), b"\x1b[4;58;2;%bm" % grey, b""),
            ("B", "SGR 4:1 + 58:2::" + grey.decode().replace(";", ":"),
             b"\x1b[4:1m\x1b[58:2::%bm" % grey.replace(b";", b":"), b""),
            ("C", "SGR 53 on the row below", b"", b"\x1b[53m"),
            ("D", "SGR 4 alone (the control)", b"\x1b[4m", b""),
        )
        for index, (letter, what, upper_style, lower_style) in enumerate(cases):
            upper = 6 + 3 * index
            self.text(upper, 2, letter)
            self.text(upper, 4, pad(" %s: this row" % what, span), upper_style)
            self.text(upper + 1, 4, pad(" the row below", span), lower_style)
        if self.graphics_answered:
            upper = 6 + 3 * len(cases)
            self.text(upper, 2, "E")
            self.text(upper, 4, pad(" a Kitty line along the top of the row below, to compare", span))
            self.text(upper + 1, 4, pad(" the row below", span))
            q10["auto"]["transmit"] = self.ensure_strip()
            q10["auto"]["reference_line"] = self.line(upper + 1, 4, span, 99)
        self.human(q10, "a_grey", "Row A (%s): is the underline GREY, a different colour from "
                   "the row's text?" % cases[0][1])
        self.human(q10, "b_grey", "Row B (%s, the colon form): is the underline GREY, a different "
                   "colour from the row's text?" % cases[1][1])
        self.human(q10, "near_boundary", "Rows A and B: is the underline at the very bottom of its "
                   "row, within a couple of pixels of the row below?"
                   + (" (Row E's line is on the boundary itself.)" if self.graphics_answered else ""))
        self.human(q10, "overline", "Row C: is there a line along the TOP edge of the lower row?")
        self.human(q10, "stray", "Did any row show stray characters, faint text, or styling "
                   "nobody asked for (58 misread as other SGR codes)?")

    # Leaving.

    def restore(self):
        """Put the terminal back, whatever state the run stopped in. Never
        raises, and gives up after RESTORE_SECONDS: every write has that
        deadline, so a terminal that has stopped reading cannot hold the
        probe (and its raw mode) for good."""
        steps = [ST + (CLOSE_LOAD if self.loading else b"") + sync_probe.END + RESET + b"\x1b[?25h"]
        deletions = b"".join(delete(image_id, free=True) for image_id in PROBE_IDS)
        if self.on_alternate:
            if self.graphics_answered:
                steps.append(deletions)
            steps.append(b"\x1b[?1049l")
        if self.graphics_answered:
            steps.append(deletions)
        deadline = time.monotonic() + RESTORE_SECONDS
        try:
            if not write_by(self.fd, b"".join(steps) + b"\x1b[6n", deadline):
                return
            self.on_alternate = self.loading = False
            # Swallow late replies so they are not typed into the shell.
            got = b""
            while select.select([self.fd], [], [], max(0.0, min(0.5, deadline - time.monotonic())))[0]:
                got += os.read(self.fd, 4096)
                if re.search(rb"\x1b\[\d+;\d+R", got):
                    break
        except OSError:
            pass

    def finish(self):
        reason = ("--auto" if self.started_auto else
                  "the run went automatic at %s" % self.went_automatic if self.went_automatic else
                  "no card asks this")
        for entry in self.questions.values():
            if entry.get("human") == {}:
                entry["human"] = "not asked (%s)" % reason
        record = dict(self.header.get("stamp") or {"probe": "hairline_probe"})
        record.update({
            "mode": "auto" if self.started_auto else "interactive",
            "went_automatic_at": self.went_automatic,
            "aborted": self.aborted,
            "host": self.header.get("host") or host_slug(dict(os.environ)),
            "host_named_from": self.header.get("host_named_from") or "environment (stopped before XTVERSION)",
            "xtversion": self.header.get("xtversion"),
            "geometry": self.header.get("geometry"),
            "line": {
                "rgb": list(LINE),
                "thickness_px": self.thickness,
                "crop_rule": CROP_RULES[self.crop_unit],
                "crop_unit": self.crop_unit,
                "strip": {"id": STRIP_ID, "width_px": self.strip_width, "height_px": self.thickness,
                          "format": "f=24 (RGB), raw"},
                "ids": {"strip": STRIP_ID, "scratch": SCRATCH_ID, "store": STORE_ID, "query": QUERY_ID,
                        "never_sent": NEVER_SENT_ID},
            },
            "graphics_query": self.header.get("graphics_query"),
            "acknowledgement_control": self.header.get("acknowledgement_control"),
            "missed_fences": self.missed_fences,
            "questions": self.questions,
            "criteria": criteria(self.questions, self.control),
        })
        return record


# MARK: - The record

def write_record(path, record):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "w") as handle:
        json.dump(record, handle, indent=2, ensure_ascii=False)


def auto_lines(auto):
    """The automatic readings worth a line of the summary."""
    if not isinstance(auto, dict):
        return
    for key, value in auto.items():
        if isinstance(value, dict) and "status" in value:
            yield key, value["status"]
        elif key == "coarse":
            for source, entry in value.items():
                yield ("advance at %s px (%s)" % (entry["width_px"], source),
                       "%s, %s" % (entry["advance"], entry["reading"]))
        elif key == "leak" and isinstance(value, dict):
            yield "?2026h ?2026l printed nothing", value.get("clean")
        elif key == "readings":
            for name, reading in value.items():
                yield name, reading
        elif isinstance(value, dict):
            codes = sorted({entry["status"] for entry in value.values()
                            if isinstance(entry, dict) and "status" in entry})
            if codes:
                yield key, ", ".join(codes)
        elif not isinstance(value, (list, tuple)):
            yield key, value


def summary_lines(record, path):
    stopped = ", stopped: %s" % record["aborted"] if record.get("aborted") else ""
    lines = ["", "  hairline probe: %s, %s run%s" % (record.get("host"), record.get("mode"), stopped),
             "  graphics query (a=q): %s" % (record.get("graphics_query") or {}).get("status")]
    for missed in record.get("missed_fences") or []:
        lines.append("  missed fence in %s (%s): %s" % (
            missed["during"], missed["why"],
            "in step again by %s" % missed["in_step_again_by"] if missed.get("in_step_again_by")
            else "never in step again: every later reading was skipped"))
    control = record.get("acknowledgement_control")
    if control:
        lines.append("  placement of an id never sent (ENOENT expected): %s" % control.get("status"))
    for name, entry in record.get("questions", {}).items():
        lines.append("  %-4s %s" % (name, entry.get("what")))
        for key, value in auto_lines(entry.get("auto")):
            lines.append("         %s: %s" % (key, value))
        human = entry.get("human")
        if isinstance(human, dict):
            for key, value in human.items():
                lines.append("         person, %s: %s" % (key, value.get("answer")))
        elif human:
            lines.append("         person: %s" % human)
    found = record.get("criteria") or {}
    lines.append("  kill inputs: " + ", ".join(
        "%s=%s" % item for item in (found.get("kill_inputs") or {}).items()))
    for change in found.get("plan_changes") or []:
        lines.append("  plan change: " + change)
    for note in found.get("unjudged") or []:
        lines.append("  unjudged: " + note)
    lines.append("  written to %s" % os.path.abspath(path))
    return lines


def parse_arguments(argv=None):
    parser = argparse.ArgumentParser(
        description="Kitty graphics hairline probe: can a classic placement draw a thin line on a "
                    "row boundary here?")
    parser.add_argument("--auto", action="store_true",
                        help="the automatic checks only: no card asks anything and no key is read "
                             "(for unattended runs)")
    return parser.parse_args(argv)


def main(argv=None):
    arguments = parse_arguments(argv)
    fd = sys.stdin.fileno()
    if not os.isatty(fd):
        sys.exit("hairline_probe: stdin is not a terminal; run this IN the terminal under test")
    refusal = REFUSED_HOSTS.get(os.environ.get("TERM_PROGRAM"))
    if refusal:
        sys.exit("hairline_probe: not run here: " + refusal)

    old = termios.tcgetattr(fd)
    probe = Probe(fd, arguments.auto)

    def on_signal(number, _frame):
        # Only the first signal stops the run. A second one, from a person
        # pressing Ctrl-C twice or a TERM after an INT, would otherwise
        # raise again inside the restore, or before it had begun, and leave
        # the terminal raw and the record unwritten. One swallowed by a
        # library's `except Exception` resurfaces at the next card or fence.
        if probe.signalled is None:
            probe.signalled = signal.Signals(number).name
            raise Aborted(probe.signalled)

    watched = (signal.SIGTERM, signal.SIGHUP, signal.SIGINT, signal.SIGQUIT)
    handlers = {number: signal.signal(number, on_signal) for number in watched}
    # Ctrl-Z would stop the probe with the terminal raw and on the alternate
    # screen; it is ignored until the terminal is put back.
    handlers[signal.SIGTSTP] = signal.signal(signal.SIGTSTP, signal.SIG_IGN)
    failure = None
    try:
        tty.setraw(fd)
        # Raw mode clears ISIG, which made Ctrl-C a byte the probe saw only
        # at a prompt, and never in --auto. With ISIG back, Ctrl-C and
        # Ctrl-\ raise SIGINT and SIGQUIT, which on_signal turns into
        # Aborted, at any point: inside a fence, in an animation, in --auto.
        # NOFLSH keeps the tty from flushing its queues on that signal. A
        # flush can discard a key that `select` has just reported, and the
        # read after it then blocks for good: the likely cause of a hang in
        # a read seen once on a pty, with a Ctrl-C at a card.
        attributes = termios.tcgetattr(fd)
        attributes[3] |= termios.ISIG | termios.NOFLSH
        termios.tcsetattr(fd, termios.TCSANOW, attributes)
        probe.run()
    except Aborted as stop:
        probe.aborted = str(stop)
    except Exception as error:  # noqa: BLE001 — recorded, then raised again below
        probe.aborted = "error: %r" % error
        failure = error
    finally:
        # No signal may cut the restore, or the record, short.
        for number in watched:
            signal.signal(number, signal.SIG_IGN)
        probe.restore()
        try:
            # TCSANOW: TCSADRAIN waits for the output to be read, which a
            # terminal that has stopped reading never does.
            termios.tcsetattr(fd, termios.TCSANOW, old)
        except termios.error:
            pass

    try:
        record = probe.finish()
        path = os.environ.get("PROBE_OUT") or default_out_path(record)
        write_record(path, record)
    finally:
        # Before the summary: on a terminal that has stopped reading, the
        # print blocks, and the terminal's own TERM must still end it.
        for number, handler in handlers.items():
            signal.signal(number, handler)
    print("\n".join(summary_lines(record, path)))
    if failure is not None:
        raise failure
    if probe.aborted:
        sys.exit(1)  # the record is written, and incomplete


if __name__ == "__main__":
    main()
