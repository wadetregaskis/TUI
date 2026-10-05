#!/usr/bin/env python3
"""
Tests for `analyze_stream.py`'s two estimates, `--runs` (O3's byte trims) and
`--shift` (O2's hardware scroll), on streams small enough to count by hand.

    python3 Tools/Profiling/test_analyze_stream.py

No build and no PTY: the streams are written here in TUIkit's own spellings
(`ESC[r;cH`, `ESC[2K`, a row's padding), so each expected number is a sum a
reader can redo. `--shift` needs pyte, and its tests are skipped without it.
"""

import contextlib
import io
import json
import os
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import analyze_stream  # noqa: E402

try:
    import pyte  # noqa: F401
    HAVE_PYTE = True
except ImportError:
    HAVE_PYTE = False

ESC = "\x1b"


def cup(row, column):
    return f"{ESC}[{row};{column}H"


class Scratch(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.mkdtemp(prefix="test-analyze-stream-")
        self.addCleanup(shutil.rmtree, self.scratch, ignore_errors=True)

    def write(self, name, stream, steps=None, rows=None, cols=None):
        path = os.path.join(self.scratch, name)
        with open(path, "wb") as handle:
            handle.write(stream.encode())
        if steps is not None:
            markers = [{"index": index, "offset": offset, "at": 0.0, "input": ""}
                       for index, offset in enumerate(steps)]
            with open(path + ".steps.json", "w") as handle:
                json.dump({"format": 1, "scenario": "test", "rows": rows, "cols": cols,
                           "loops": 1, "total": len(stream.encode()), "steps": markers}, handle)
        return path

    def quietly(self, function, *args):
        with contextlib.redirect_stdout(io.StringIO()):
            return function(*args)


class TestRuns(Scratch):
    """Each trim counted alone against a stream whose answer is countable."""

    def test_each_trim_is_counted_where_today_spends_it(self):
        stream = (
            # A whole-line row: background, erase, content, five cells of
            # padding the erase had already painted, reset. Its move names
            # column 1 of row 1, which `ESC[H` says in three fewer bytes.
            cup(1, 1) + f"{ESC}[48;5;17m{ESC}[2K" + "hello" + " " * 5 + f"{ESC}[0m"
            # A span ending in eight plain blanks: `ESC[8X` is four bytes.
            + cup(3, 10) + "abc" + " " * 8
            # A second span on the same row. The cursor is at column 21, so
            # `ESC[9C` (four bytes) says what `ESC[3;30H` (seven) does.
            + cup(3, 30) + "x"
            # Another row, column 1: `ESC[5H` drops the `;1`.
            + cup(5, 1) + "y"
        )
        trims = self.quietly(analyze_stream.runs, self.write("trims.ansi", stream))
        self.assertEqual(trims["padding"], 5)
        self.assertEqual(trims["erasable"], 8 - len(f"{ESC}[8X"))
        self.assertEqual(trims["forward"], len(cup(3, 30)) - len(f"{ESC}[9C"))
        self.assertEqual(trims["default_column"], 3 + 2)

    def test_a_blank_an_erase_cannot_draw_is_not_counted(self):
        # Underlined blanks show the underline; an erase would not.
        stream = cup(2, 4) + "ab" + f"{ESC}[4m" + " " * 9
        trims = self.quietly(analyze_stream.runs, self.write("underline.ansi", stream))
        self.assertEqual(trims["erasable"], 0)

    def test_a_short_blank_run_is_not_worth_an_erase(self):
        stream = cup(2, 4) + "ab" + " " * 4
        trims = self.quietly(analyze_stream.runs, self.write("short.ansi", stream))
        self.assertEqual(trims["erasable"], 0)

    def test_an_unknown_cursor_is_not_guessed_at(self):
        # A line feed moves the cursor somewhere this walk does not model, so
        # the next move on "the same row" is not credited to CUF.
        stream = cup(3, 10) + "abc\n" + cup(3, 30) + "x"
        trims = self.quietly(analyze_stream.runs, self.write("unknown.ansi", stream))
        self.assertEqual(trims["forward"], 0)


@unittest.skipUnless(HAVE_PYTE, "needs pyte")
class TestShift(Scratch):
    """A list scrolled by whole rows, which a band shift reproduces."""

    ROWS, COLS = 10, 20

    def frame(self, first):
        """Every row painted whole, as `FrameDiffWriter` paints a changed row:
        row i shows item `first + i`."""
        return "".join(cup(row + 1, 1) + f"{ESC}[2K" + f"item {first + row:02d}"
                       for row in range(self.ROWS))

    def test_a_scroll_by_two_is_found_and_priced(self):
        first, second = self.frame(0), self.frame(2)
        path = self.write("scroll.ansi", first + second,
                          steps=[0, len(first)], rows=self.ROWS, cols=self.COLS)
        written, saved, with_residue = self.quietly(analyze_stream.shift, path, path + ".steps.json")
        self.assertEqual(written, len(first) + len(second))
        self.assertEqual(with_residue, saved, "nothing differs but the shift")
        # The second frame rewrote all ten rows; a shift keeps eight of them
        # and pays for the region, the scroll and the two rows it exposes.
        self.assertGreater(saved, 0)
        self.assertLess(saved, len(second))
        band = sum(len(cup(row + 1, 1) + f"{ESC}[2K" + "item 00") for row in range(8))
        self.assertLessEqual(saved, band - analyze_stream.SCROLL_OVERHEAD)

    def test_the_shift_is_the_one_that_happened(self):
        screen = pyte.Screen(self.COLS, self.ROWS)
        stream = pyte.ByteStream(screen)
        stream.feed(self.frame(0).encode())
        before = [analyze_stream.row_snapshot(screen, y) for y in range(self.ROWS)]
        stream.feed(self.frame(3).encode())
        after = [analyze_stream.row_snapshot(screen, y) for y in range(self.ROWS)]
        ids = {}
        identify = lambda rows: [ids.setdefault(row, len(ids)) for row in rows]  # noqa: E731
        spent = [len(cup(1, 1) + f"{ESC}[2K" + "item 00")] * self.ROWS
        saved, k, top, bottom = analyze_stream.best_shift(
            identify(before), identify(after), before, after, spent)
        # Content moved UP three rows: new row i is old row i + 3, and the
        # region runs from row 1 to the bottom.
        self.assertEqual((k, top, bottom), (3, 1, self.ROWS))
        self.assertGreater(saved, 0)

    def test_a_frame_that_did_not_move_saves_nothing(self):
        first = self.frame(0)
        repaint = self.frame(0)
        path = self.write("still.ansi", first + repaint,
                          steps=[0, len(first)], rows=self.ROWS, cols=self.COLS)
        _, saved, with_residue = self.quietly(analyze_stream.shift, path, path + ".steps.json")
        self.assertEqual((saved, with_residue), (0, 0))

    def test_a_band_too_short_to_pay_is_not_taken(self):
        # Moved by six of ten rows: a four-row band survives, and four
        # short rows cannot pay for the region, the scroll and six exposed
        # rows.
        first, second = self.frame(0), self.frame(6)
        path = self.write("short.ansi", first + second,
                          steps=[0, len(first)], rows=self.ROWS, cols=self.COLS)
        _, saved, with_residue = self.quietly(analyze_stream.shift, path, path + ".steps.json")
        self.assertEqual((saved, with_residue), (0, 0))

    def boxed(self, first, thumb):
        """A list in a box with its own scroll indicator, as Example's scroll
        views are drawn: `|item NN       ^|`, the indicator column holding an
        arrow at each end and the thumb on row `thumb`. A scroll moves the
        items and leaves the indicator where it is, so no row equals its
        source exactly."""
        lines = []
        for row in range(self.ROWS):
            mark = "^" if row == 0 else "v" if row == self.ROWS - 1 else "#" if row == thumb else " "
            lines.append(cup(row + 1, 1) + f"{ESC}[2K" + f"|item {first + row:02d}" + " " * 9 + mark + "|")
        return "".join(lines)

    def test_a_scroll_under_a_fixed_indicator_rides_with_its_residue(self):
        first, second = self.boxed(0, thumb=5), self.boxed(1, thumb=6)
        path = self.write("boxed.ansi", first + second,
                          steps=[0, len(first)], rows=self.ROWS, cols=self.COLS)
        _, exact, with_residue = self.quietly(analyze_stream.shift, path, path + ".steps.json")
        # Moved by one: rows whose indicator cell is blank in both places
        # move exactly, but the arrows and the thumb's two rows cut every
        # exact run short of four rows (1-3, 5 and 7).
        self.assertEqual(exact, 0)
        # Allowed a cell of residue each, the whole box rides, and what the
        # shift saves is the rewrite less the indicator cells redrawn after.
        self.assertGreater(with_residue, 0)
        _, _, none = self.quietly(analyze_stream.shift, path, path + ".steps.json", 0)
        self.assertEqual(none, 0, "a residue of zero is the exact search")


if __name__ == "__main__":
    unittest.main()
