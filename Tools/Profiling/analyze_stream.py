#!/usr/bin/env python3
"""
Attribute the bytes a TUIkit app wrote to a terminal.

`drive.py --dump OUT.ansi` captures the raw stream; this splits it into the
three things it can be — styling (SGR), positioning and erasing (other CSI),
and the cells themselves — and reports how much of the styling was NECESSARY,
by replaying the stream through a minimal terminal model and asking, at each
SGR, whether the state it establishes differs from the state already in force.

The necessary figure is a FLOOR, not a target: it assumes an oracle that knows
the terminal's state everywhere, which the renderer does not (a span writing
into a row it did not write last frame cannot know what is under it). The gap
between emitted and necessary is what the render path could in principle
close.

Two further analyses estimate output changes before anybody builds them
(Documentation/Ghostty-VT-adoption.md, O2 and O3):

  --runs   The four byte trims of O3, each counted against today's stream:
           the padding after a whole-line row's `ESC[2K` (trailing blanks
           that show only the background the erase painted), blank runs a
           `CSI n X` could erase, cursor moves a `CSI n C` could replace, and
           the `;1` of a column-1 `CSI r;1 H`. Each figure is what that trim
           alone would save; they overlap, so they do not add up.
  --shift  O2's hardware-scroll estimate. Replays the stream through pyte,
           step by step (the markers `drive.py --dump` writes beside the
           stream), and asks of each step whether a band of rows moved by k
           whole rows. Where one did, it counts the bytes that step spent on
           the band, less the rows a scroll would expose and the ~20 bytes the
           region and the scroll cost: what `CSI a;b r` + `CSI k S` + `CSI r`
           would have saved. Twice: with bands of rows that moved exactly,
           and with rows allowed `--residue` differing cells (a scroll
           view's own indicator column), repainted after the shift.

Usage:
    analyze_stream.py [--runs] [--shift [--residue N]] [--steps FILE] OUT.ansi [OUT2.ansi ...]
"""
import argparse
import json
import os
import re
import sys

CSI = re.compile(rb"\x1b\[([0-?]*)([ -/]*)([@-~])")

# One token of the stream: a CSI sequence; a string sequence (OSC, DCS, APC,
# PM, SOS) up to BEL or ST; any other two-byte escape; or a run of text. Text
# stops at ESC and at the C0 controls, which move the cursor on their own.
TOKEN = re.compile(
    rb"(?P<csi>\x1b\[[0-?]*[ -/]*[@-~])"
    rb"|(?P<string>\x1b[\]P_^X].*?(?:\x07|\x1b\\))"
    rb"|(?P<esc>\x1b[\x20-\x7e])"
    rb"|(?P<control>[\x00-\x1a\x1c-\x1f])"
    rb"|(?P<text>[^\x00-\x1f]+)",
    re.S)

# The CSI finals that put the cursor somewhere: their bytes belong to the row
# they arrive on, not the one they leave.
CURSOR_MOVES = frozenset(b"HfABCDEFGd")


def read_stream(path):
    with open(path, "rb") as handle:
        return handle.read()


def analyse(path):
    data = read_stream(path)
    sgr_bytes = sgr_count = other_bytes = other_count = 0
    redundant_bytes = redundant_count = 0
    state = None  # the parameter list in force, as the terminal sees it
    for match in CSI.finditer(data):
        length = len(match.group(0))
        if match.group(3) == b"m":
            sgr_bytes += length
            sgr_count += 1
            params = match.group(1)
            netted = net(state, params)
            if netted == state:
                redundant_bytes += length
                redundant_count += 1
            state = netted
        else:
            other_bytes += length
            other_count += 1
    escape_bytes = sgr_bytes + other_bytes
    cells = len(data) - escape_bytes
    print(f"{path}")
    print(f"  total          {len(data):>10,}")
    print(f"  cells          {cells:>10,}  ({100*cells/len(data):5.1f}%)")
    print(f"  SGR            {sgr_bytes:>10,}  ({100*sgr_bytes/len(data):5.1f}%)  "
          f"{sgr_count:,} escapes")
    print(f"    of which redundant {redundant_bytes:>6,}  "
          f"({100*redundant_bytes/max(1,sgr_bytes):5.1f}% of SGR)  {redundant_count:,} escapes")
    print(f"  cursor/erase   {other_bytes:>10,}  ({100*other_bytes/len(data):5.1f}%)  "
          f"{other_count:,} escapes")
    return len(data), sgr_bytes, redundant_bytes


def net(state, params):
    """The parameter set a terminal would be left in. Deliberately crude — it
    models a reset and otherwise accumulates — because the question here is
    'did this escape change anything', not 'what exactly does it mean'."""
    codes = params.split(b";") if params else [b"0"]
    if state is None:
        state = {}
    else:
        state = dict(state)
    index = 0
    while index < len(codes):
        code = codes[index] or b"0"
        if code == b"0":
            state = {}
        elif code in (b"38", b"48"):
            span = 3 if index + 1 < len(codes) and codes[index + 1] == b"5" else 5
            state["fg" if code == b"38" else "bg"] = b";".join(codes[index:index + span])
            index += span
            continue
        elif code == b"39":
            state.pop("fg", None)
        elif code == b"49":
            state.pop("bg", None)
        elif code.isdigit() and 30 <= int(code) <= 37 or code.isdigit() and 90 <= int(code) <= 97:
            state["fg"] = code
        elif code.isdigit() and 40 <= int(code) <= 47 or code.isdigit() and 100 <= int(code) <= 107:
            state["bg"] = code
        elif code in (b"22", b"23", b"24", b"25", b"27", b"28", b"29", b"21"):
            for on in {b"22": (b"1", b"2"), b"23": (b"3",), b"24": (b"4",),
                       b"25": (b"5", b"6"), b"27": (b"7",), b"28": (b"8",),
                       b"29": (b"9",), b"21": (b"1",)}[code]:
                state.pop(on, None)
        else:
            state[code] = True
        index += 1
    return state


def tokens(data):
    """The stream as `(kind, bytes, params, final)` tuples, in order. `params`
    and `final` are set for a CSI only. A lone ESC at the very end, or any byte
    no rule takes, comes back as text so nothing is lost from the count."""
    position = 0
    for match in TOKEN.finditer(data):
        if match.start() != position:
            yield ("text", data[position:match.start()], None, None)
        kind = match.lastgroup
        raw = match.group(0)
        if kind == "csi":
            inner = CSI.match(raw)
            yield ("csi", raw, inner.group(1), inner.group(3)[0])
        else:
            yield (kind, raw, None, None)
        position = match.end()
    if position != len(data):
        yield ("text", data[position:], None, None)


def cup_target(params):
    """The 1-based (row, column) a `CSI row;column H` names; missing or empty
    fields are 1, as the terminal reads them."""
    fields = params.split(b";") if params else []
    row = int(fields[0]) if len(fields) > 0 and fields[0].isdigit() else 1
    column = int(fields[1]) if len(fields) > 1 and fields[1].isdigit() else 1
    return row, column


def cell_width(text):
    """How many cells `text` advances the cursor. The span path writes only
    rows of single-cell scalars, but whole-line rows reach here too, so a wide
    or zero-width scalar is counted as the terminal would count it where
    `wcwidth` is installed (pyte brings it), and as one cell where it is not."""
    decoded = text.decode("utf-8", errors="replace")
    try:
        from wcwidth import wcwidth
    except ImportError:
        return len(decoded)
    return sum(max(0, wcwidth(scalar)) for scalar in decoded)


def only_background(state):
    """Whether an SGR state paints a blank as the background alone, so an
    erase (which fills with the background under BCE) draws the same cells.
    An underline, a reverse or a strike shows on a space; a foreground does
    not."""
    return all(key in ("fg", "bg") or key in (b"1", b"2", b"3") for key in (state or {}))


def blank_matches_erase(blank_state, erase_state):
    """Whether a blank drawn in `blank_state` shows exactly what an erase
    issued in `erase_state` left in its cell: the erase's background and
    nothing else. Same state as far as a space can show it — a foreground, a
    bold or an italic is invisible on one, so those may differ; a background,
    a reverse, an underline or a strike may not. An erase issued with any of
    those last three in force is one whose fill differs by terminal, so
    nothing is matched against it."""
    erase_state = erase_state or {}
    blank_state = blank_state or {}
    return (only_background(erase_state) and only_background(blank_state)
            and blank_state.get("bg") == erase_state.get("bg"))


def runs(path):
    """O3: what each of the four trims would save on this stream, alone."""
    data = read_stream(path)
    padding = padding_rows = 0
    erasable = erasable_spans = 0
    forward = forward_moves = 0
    default_column = default_moves = 0

    state = {}
    row = column = None  # where the cursor is, when known
    segment = None  # the row being written since the last cursor move

    def close(segment):
        nonlocal padding, padding_rows, erasable, erasable_spans
        if not segment or not segment["text"]:
            return
        if segment["whole_line"]:
            # The row opened with `ESC[2K`, which painted every cell in the
            # background in force AT THE ERASE, and nothing else. A trailing
            # blank is padding only where it shows exactly that; one drawn in
            # another background, or reversed — a selected row's highlight
            # running to the edge, a status bar — is the row's content, and
            # trimming it would drop what it draws. So the walk back from the
            # row's end stops at the first chunk that shows something else.
            redundant = 0
            for chunk, chunk_state in reversed(segment["text"]):
                if not blank_matches_erase(chunk_state, segment["erase_state"]):
                    break
                stripped = chunk.rstrip(b" ")
                redundant += len(chunk) - len(stripped)
                if stripped:
                    break
            if redundant:
                padding += redundant
                padding_rows += 1
            return
        # The trailing blanks of the span's text, and whether every one of them
        # was written in a state an erase reproduces.
        trailing = 0
        plain = True
        for chunk, chunk_state in reversed(segment["text"]):
            stripped = chunk.rstrip(b" ")
            trailing += len(chunk) - len(stripped)
            plain = plain and only_background(chunk_state)
            if stripped:
                break
        if not trailing:
            return
        if plain and trailing >= 5:
            erasable += trailing - len(f"\x1b[{trailing}X")
            erasable_spans += 1

    for kind, raw, params, final in tokens(data):
        if kind == "csi" and final == ord("m"):
            state = net(state, params)
            continue
        if kind == "csi" and final == ord("K") and params == b"2" and segment is not None:
            segment["whole_line"] = True
            segment["erase_state"] = state  # what the erase painted with
            continue
        if kind == "csi" and final in (ord("H"), ord("f")):
            close(segment)
            target_row, target_column = cup_target(params)
            if row == target_row and column is not None and target_column >= column:
                # The second or later span on a row whose cursor column is
                # known: CUF says the same in fewer bytes, or nothing at all.
                distance = target_column - column
                replacement = len(f"\x1b[{distance}C") if distance else 0
                if replacement < len(raw):
                    forward += len(raw) - replacement
                    forward_moves += 1
            if target_column == 1:
                shortest = b"\x1b[H" if target_row == 1 else f"\x1b[{target_row}H".encode()
                if len(shortest) < len(raw):
                    default_column += len(raw) - len(shortest)
                    default_moves += 1
            row, column = target_row, target_column
            segment = {"whole_line": False, "text": []}
            continue
        if kind == "csi" and final == ord("C"):
            if column is not None:
                column += int(params) if params and params.isdigit() else 1
            continue
        if kind == "csi" and final == ord("D"):
            if column is not None:
                column -= int(params) if params and params.isdigit() else 1
            continue
        if kind == "text":
            if column is not None:
                column += cell_width(raw)
            if segment is not None:
                segment["text"].append((raw, state))
            continue
        if kind == "string":
            continue  # an OSC 8 link or a graphics command: no cells
        # Anything else that may move the cursor, or that this walk does not
        # model, makes the position unknown until the next absolute move.
        if kind == "csi" and (final in CURSOR_MOVES or final in b"rJ"):
            row = column = None
        elif kind in ("esc", "control"):
            row = column = None
    close(segment)

    total = max(1, len(data))
    print(f"  O3 trims — each alone, against today's stream (they overlap; do not add)")
    print(f"    padding after EL      {padding:>9,}  ({100*padding/total:5.1f}%)  "
          f"{padding_rows:,} whole-line rows")
    print(f"    ECH for blank runs    {erasable:>9,}  ({100*erasable/total:5.1f}%)  "
          f"{erasable_spans:,} spans ending in 5+ blanks")
    print(f"    CUF between spans     {forward:>9,}  ({100*forward/total:5.1f}%)  "
          f"{forward_moves:,} moves")
    print(f"    default CUP column    {default_column:>9,}  ({100*default_column/total:5.1f}%)  "
          f"{default_moves:,} moves")
    return {"padding": padding, "erasable": erasable, "forward": forward,
            "default_column": default_column}


def load_steps(path):
    with open(path) as handle:
        return json.load(handle)


def row_snapshot(screen, y):
    """Row `y` of a pyte screen, every cell with its attributes, so two rows
    compare equal only where a terminal would show the same thing."""
    line = screen.buffer[y]
    return tuple(line[x] for x in range(screen.columns))


def paint_cost(row, y):
    """Bytes a writer would spend painting `row` at 1-based row `y` over the
    blank line a scroll leaves: per run of cells that are not blank, a move,
    an SGR and the cells.

    "Blank" is a space in the row's own background, the colour of its last
    cell: a scroll fills what it exposes with the background in force, which
    the writer can set before it, so those cells cost nothing. The rest is
    priced as the span path writes it. An estimate in TUIkit's own spelling,
    on the generous side, not a promise about a future writer."""
    background = row[-1].bg if row else "default"

    def blank(cell):
        return (cell.data == " " and cell.bg == background
                and not (cell.reverse or cell.underscore or cell.strikethrough))

    cost = 0
    x = 0
    while x < len(row):
        if blank(row[x]):
            x += 1
            continue
        start = x
        while x < len(row) and not blank(row[x]):
            x += 1
        cost += (len(f"\x1b[{y};{start + 1}H") + sgr_cost(row[start])
                 + sum(len(cell.data.encode("utf-8")) for cell in row[start:x]))
    return cost


def sgr_cost(cell):
    """The length of an SGR that states `cell`'s attributes, from a reset."""
    parts = ["0"]
    for flag, code in ((cell.bold, "1"), (cell.italics, "3"), (cell.underscore, "4"),
                       (cell.reverse, "7"), (cell.strikethrough, "9")):
        if flag:
            parts.append(code)
    for colour, base in ((cell.fg, "38"), (cell.bg, "48")):
        if colour == "default":
            continue
        if len(colour) == 6 and all(c in "0123456789abcdefABCDEF" for c in colour):
            parts.append(f"{base};2;{int(colour[0:2], 16)};{int(colour[2:4], 16)};{int(colour[4:6], 16)}")
        else:
            parts.append("31" if base == "38" else "41")  # a named colour: two digits
    return len("\x1b[" + ";".join(parts) + "m")


# The cheapest band a scroll is worth trying on, and what the scroll costs
# beyond the rows: `CSI a;b r`, `CSI k S` and `CSI r`, for two-digit rows.
MINIMUM_BAND = 4
SCROLL_OVERHEAD = len("\x1b[10;40r") + len("\x1b[3S") + len("\x1b[r")

# How many cells a row may differ from its shifted source and still ride the
# shift, its residue repainted after: a scroll indicator's arrow and thumb, a
# focus mark. Enough for those, few enough that a row that merely resembles
# its neighbour does not count as moved.
DEFAULT_RESIDUE = 4


def residue_cost(new_row, old_row, y):
    """Bytes to repaint, once a shift has moved `old_row` to row `y` (1-based),
    the cells of `new_row` it does not already show: per run of differing
    cells, a move, an SGR and the cells. A scroll indicator's thumb, a focus
    mark: what O2 calls the residue the ordinary diff writes after the shift."""
    cost = 0
    x = 0
    columns = len(new_row)
    while x < columns:
        if new_row[x] == old_row[x]:
            x += 1
            continue
        start = x
        while x < columns and new_row[x] != old_row[x]:
            x += 1
        cost += (len(f"\x1b[{y};{start + 1}H") + sgr_cost(new_row[start])
                 + sum(len(cell.data.encode("utf-8")) for cell in new_row[start:x]))
    return cost


def best_shift(before, after, before_rows, after_rows, spent, residue=0):
    """The most a single band shift could have saved between two screens.

    `before` and `after` identify each row's content (equal ids, equal rows),
    `before_rows` and `after_rows` are the rows themselves, and `spent` the
    bytes the step wrote on each row. A row RIDES a shift of k when its
    source k rows away equals it, or differs from it in at most `residue`
    cells, which are then repainted after the shift (`residue_cost`). Returns
    `(saved, k, top, bottom)` for the best positive saving, with `top` and
    `bottom` 1-based, or `None`. A positive `k` is content moving UP
    (`CSI k S`): new row `i` is old row `i + k`.

    Only shifts that moved at least one row exactly are tried: a band with no
    exact row in it is not a scroll anybody would recognise, and the residue
    comparison is cell by cell, so trying every k on every row would make a
    tour take minutes.
    """
    rows = len(after)
    candidates = sorted({j - i for i in range(rows) for j in range(rows)
                         if i != j and abs(j - i) <= rows // 2
                         and after[i] == before[j] and after[i] != before[i]})
    best = None
    for k in candidates:
        rides = [False] * rows
        cost = [0] * rows
        for i in range(rows):
            j = i + k
            if not 0 <= j < rows:
                continue
            if after[i] == before[j]:
                rides[i] = True
            elif residue and sum(1 for new, old in zip(after_rows[i], before_rows[j])
                                 if new != old) <= residue:
                rides[i] = True
                cost[i] = residue_cost(after_rows[i], before_rows[j], i + 1)
        i = 0
        while i < rows:
            if not rides[i]:
                i += 1
                continue
            start = i
            while i < rows and rides[i]:
                i += 1
            end = i - 1  # the band is [start, end], in new-screen rows
            if end - start + 1 < MINIMUM_BAND:
                continue
            saved = sum(spent[row] - cost[row] for row in range(start, end + 1))
            # The rows the scroll exposes inside its region must be painted
            # whole; whatever the step already spent on them is spent anyway.
            exposed = range(end + 1, end + 1 + k) if k > 0 else range(start + k, start)
            for row in exposed:
                saved -= max(0, paint_cost(after_rows[row], row + 1) - spent[row])
            saved -= SCROLL_OVERHEAD
            if saved > 0 and (best is None or saved > best[0]):
                top, bottom = (start, end + k) if k > 0 else (start + k, end)
                best = (saved, k, top + 1, bottom + 1)
    return best


def shift(path, steps_file, residue=DEFAULT_RESIDUE):
    """O2: per step, what one hardware-scrolled band would have saved, twice:
    with bands of rows that moved exactly, and with rows allowed `residue`
    differing cells, repainted after the shift."""
    try:
        import pyte
    except ImportError:
        raise SystemExit("--shift needs pyte (pip3 install --user pyte)")
    if not os.path.exists(steps_file):
        raise SystemExit(f"--shift needs the step markers drive.py writes: {steps_file} is missing")
    markers = load_steps(steps_file)
    rows, columns = markers["rows"], markers["cols"]
    data = read_stream(path)
    offsets = [step["offset"] for step in markers["steps"]] + [len(data)]

    screen = pyte.Screen(columns, rows)
    stream = pyte.ByteStream(screen)
    # Rows compared by id first: a row is ~a hundred cells, and the search
    # compares every row against every other.
    ids = {}

    def identify(rows_now):
        return [ids.setdefault(row, len(ids)) for row in rows_now]

    before_rows = [row_snapshot(screen, y) for y in range(rows)]
    before = identify(before_rows)

    total_bytes = 0
    # Per variant: bytes saved, steps that paid, shifts used, best steps.
    variants = {0: [0, 0, {}, []], residue: [0, 0, {}, []]}
    for index in range(len(offsets) - 1):
        segment = data[offsets[index]:offsets[index + 1]]
        spent = [0] * rows
        for kind, raw, params, final in tokens(segment):
            before_row = screen.cursor.y
            stream.feed(raw)
            if kind == "csi" and final in CURSOR_MOVES:
                spent[min(rows - 1, screen.cursor.y)] += len(raw)
            else:
                spent[min(rows - 1, before_row)] += len(raw)
        after_rows = [row_snapshot(screen, y) for y in range(rows)]
        after = identify(after_rows)
        total_bytes += len(segment)
        for limit, tally in variants.items():
            best = best_shift(before, after, before_rows, after_rows, spent, residue=limit)
            if best:
                saved, k, top, bottom = best
                tally[0] += saved
                tally[1] += 1
                tally[2][k] = tally[2].get(k, 0) + 1
                tally[3].append((saved, len(segment), index, k, top, bottom))
        before, before_rows = after, after_rows

    steps = len(offsets) - 1
    print(f"  O2 band shift — {steps:,} steps at {columns}x{rows}")
    print(f"    bytes written         {total_bytes:>9,}")
    for limit, (saved_total, paying, shifts, biggest) in variants.items():
        label = "exact bands" if limit == 0 else f"with {limit}-cell residue"
        print(f"    {label:<21} {saved_total:>9,}  ({100*saved_total/max(1,total_bytes):5.1f}%)  "
              f"saved, on {paying:,} of {steps:,} steps")
        if shifts:
            common = ", ".join(f"k={k}: {count}" for k, count in
                               sorted(shifts.items(), key=lambda item: -item[1])[:6])
            print(f"      shifts used         {common}")
            # The steps that pay most, so a reader can check one by eye: the
            # step index matches the markers file, which names the input sent.
            for saved, spent_total, index, k, top, bottom in sorted(biggest, reverse=True)[:3]:
                step = markers["steps"][index]
                print(f"      step {index} ({step['input'] or 'pause'}): {saved:,} of {spent_total:,} "
                      f"bytes, k={k} over rows {top}-{bottom}")
    return total_bytes, variants[0][0], variants[residue][0]


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("streams", nargs="+", help="streams captured by drive.py --dump")
    parser.add_argument("--runs", action="store_true", help="O3: the four byte trims")
    parser.add_argument("--shift", action="store_true",
                        help="O2: what hardware-scrolled bands would save (needs pyte "
                             "and the .steps.json drive.py writes)")
    parser.add_argument("--residue", type=int, default=DEFAULT_RESIDUE,
                        help="--shift: cells a row may differ from its shifted source and "
                             f"still ride the shift (default {DEFAULT_RESIDUE})")
    parser.add_argument("--steps", default=None,
                        help="the step markers, when not STREAM.steps.json (one stream only)")
    args = parser.parse_args()
    if args.steps and len(args.streams) != 1:
        parser.error("--steps names the markers of ONE stream")
    for path in args.streams:
        analyse(path)
        if args.runs:
            runs(path)
        if args.shift:
            shift(path, args.steps or path + ".steps.json", residue=args.residue)


if __name__ == "__main__":
    main()
