"""Tests for the parts of `clipboard_probe.py` that guard the user's clipboard.

    cd Tools/TerminalProbes && python3 -m unittest test_clipboard_probe
    python3 -m unittest discover -s Tools/TerminalProbes -p 'test_*.py'

No terminal and no real clipboard: the clipboard here is a file, read and
written by `cat`, and its types are what each test says they are.
"""
import os
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import clipboard_probe  # noqa: E402  (the path has to be set up first)


class FileClipboard:
    """A clipboard that is a file, with the types a test states."""

    def __init__(self, contents, types):
        handle, self.path = tempfile.mkstemp()
        os.close(handle)
        with open(self.path, "w") as out:
            out.write(contents)
        self.types = types

    def board(self, lister=None):
        helpers = (["cat", self.path], ["sh", "-c", f"cat > '{self.path}'"])
        if lister is None:
            lister = (["sh", "-c", "true"], lambda _: self.types) if self.types is not None else (None, None)
        return clipboard_probe.Clipboard(fd=-1, manual=False, helpers=helpers, lister=lister)

    def contents(self):
        with open(self.path) as handle:
            return handle.read()

    def write(self, text):
        with open(self.path, "w") as out:
            out.write(text)

    def close(self):
        os.remove(self.path)


class TypesTests(unittest.TestCase):

    def test_clipboard_info_names_every_other_field(self):
        info = "«class utf8», 5, «class ut16», 12, string, 5, Unicode text, 10\n"
        self.assertEqual(
            clipboard_probe.parse_clipboard_info(info),
            ["«class utf8»", "«class ut16»", "string", "Unicode text"])
        self.assertEqual(clipboard_probe.parse_clipboard_info(""), [])

    def test_text_is_put_back_and_nothing_else_is(self):
        self.assertTrue(clipboard_probe.holds_only_text(["«class utf8»", "string"]))
        self.assertTrue(clipboard_probe.holds_only_text(["TARGETS", "UTF8_STRING", "text/plain;charset=utf-8"]))
        self.assertTrue(clipboard_probe.holds_only_text([]))
        self.assertFalse(clipboard_probe.holds_only_text(["«class PNGf»", "«class utf8»"]))
        self.assertFalse(clipboard_probe.holds_only_text(["«class RTF »", "«class utf8»"]))
        self.assertFalse(clipboard_probe.holds_only_text(["image/png"]))


class PreservingTests(unittest.TestCase):

    def setUp(self):
        self.clipboard = None

    def tearDown(self):
        if self.clipboard:
            self.clipboard.close()

    def test_the_clipboard_is_put_back_when_a_step_fails(self):
        self.clipboard = FileClipboard("the user's text", ["«class utf8»"])
        board = self.clipboard.board()

        def writes():
            self.clipboard.write("tuikit-osc52-nonce")
            raise RuntimeError("a helper failed")

        with self.assertRaises(RuntimeError):
            clipboard_probe.preserving(board, clobber=False, writes=writes)
        self.assertEqual(self.clipboard.contents(), "the user's text")

    def test_the_clipboard_is_put_back_when_the_run_is_interrupted(self):
        self.clipboard = FileClipboard("the user's text", ["string"])
        board = self.clipboard.board()

        def writes():
            self.clipboard.write("sentinel-1234")
            raise KeyboardInterrupt

        with self.assertRaises(KeyboardInterrupt):
            clipboard_probe.preserving(board, clobber=False, writes=writes)
        self.assertEqual(self.clipboard.contents(), "the user's text")

    def test_a_clipboard_holding_a_picture_is_not_written(self):
        self.clipboard = FileClipboard("", ["«class PNGf»", "«class 8BPS»"])
        board = self.clipboard.board()
        ran = []
        done, restored, refusal = clipboard_probe.preserving(
            board, clobber=False, writes=lambda: ran.append(True))
        self.assertFalse(done)
        self.assertFalse(restored)
        self.assertEqual(ran, [])
        self.assertIn("«class PNGf»", refusal)

    def test_a_clipboard_whose_types_cannot_be_listed_is_not_written(self):
        self.clipboard = FileClipboard("text", None)
        done, _, refusal = clipboard_probe.preserving(
            self.clipboard.board(), clobber=False, writes=lambda: self.fail("wrote"))
        self.assertFalse(done)
        self.assertIn("cannot be listed", refusal)
        # No copy makes them listable: the advice is the helper, or --clobber.
        self.assertNotIn("copy plain text", refusal)
        self.assertIn("xclip", refusal)
        self.assertIn("--clobber", refusal)

    def test_an_empty_x11_or_wayland_clipboard_is_empty_not_unlistable(self):
        self.clipboard = FileClipboard("", None)
        for message, pattern in [
            ("Nothing is copied", clipboard_probe.WAYLAND_EMPTY),
            ("Error: target TARGETS not available", clipboard_probe.XCLIP_EMPTY),
        ]:
            failing = ["sh", "-c", f"echo '{message}' >&2; exit 1"]
            board = self.clipboard.board(lister=(failing, str.split, pattern))
            self.assertEqual(board.types(), [])
            done, restored, refusal = clipboard_probe.preserving(
                board, clobber=False, writes=lambda: self.clipboard.write("nonce"))
            self.assertTrue(done, refusal)
            self.assertTrue(restored)
            self.assertEqual(self.clipboard.contents(), "")

    def test_a_listing_that_fails_otherwise_still_cannot_be_listed(self):
        self.clipboard = FileClipboard("text", None)
        failing = ["sh", "-c", "echo 'Error: Can't open display' >&2; exit 1"]
        board = self.clipboard.board(lister=(failing, str.split, clipboard_probe.XCLIP_EMPTY))
        self.assertIsNone(board.types())

    def test_a_lister_that_fails_is_advised_to_be_fixed_not_installed(self):
        # The follow-ups' review: a failing lister (xclip with no X server, an
        # osascript over ssh) was told to install the lister it already has.
        self.clipboard = FileClipboard("text", None)
        for lister, said in [
            (["sh", "-c", "echo \"Error: Can't open display: :0\" >&2; exit 1"], "Can't open display"),
            (["/nonexistent/clipboard-lister"], "could not run"),
        ]:
            board = self.clipboard.board(lister=(lister, str.split, clipboard_probe.XCLIP_EMPTY))
            done, _, refusal = clipboard_probe.preserving(
                board, clobber=False, writes=lambda: self.fail("wrote"))
            self.assertFalse(done)
            self.assertIn(said, refusal)
            self.assertIn("could not be listed", refusal)
            self.assertNotIn("install", refusal)
            self.assertIn("--clobber", refusal)
            self.assertEqual(self.clipboard.contents(), "text")

    def test_a_lister_that_does_not_answer_is_said_to_have_timed_out(self):
        # The review of the follow-ups' fixes: a lister that timed out was
        # reported as one that "could not run".
        self.clipboard = FileClipboard("text", None)
        board = self.clipboard.board(lister=(["sleep", "5"], str.split, clipboard_probe.XCLIP_EMPTY))
        with mock.patch.object(clipboard_probe, "LISTING_TIMEOUT", 0.1):
            done, _, refusal = clipboard_probe.preserving(
                board, clobber=False, writes=lambda: self.fail("wrote"))
        self.assertFalse(done)
        self.assertIn("did not answer within 0.1 s", refusal)
        self.assertNotIn("could not run", refusal)
        self.assertEqual(self.clipboard.contents(), "text")

    def test_a_failing_lister_is_told_what_to_fix_on_its_own_platform(self):
        # The same review: the advice named X11, Wayland and macOS whatever
        # the platform.
        for platform, fix, other in [
            ("darwin", "pasteboard", "DISPLAY"),
            ("linux", "DISPLAY", "pasteboard"),
        ]:
            with mock.patch.object(clipboard_probe.sys, "platform", platform):
                _, advice = clipboard_probe.refusal_advice(None, "`lister` failed: no")
            self.assertIn(fix, advice)
            self.assertNotIn(other, advice)
            self.assertIn("--clobber", advice)

    def test_rich_text_is_refused_with_a_way_to_copy_plain_text(self):
        self.clipboard = FileClipboard("styled", ["«class RTF »", "«class HTML»", "«class utf8»"])
        done, _, refusal = clipboard_probe.preserving(
            self.clipboard.board(), clobber=False, writes=lambda: self.fail("wrote"))
        self.assertFalse(done)
        self.assertIn("rich text", refusal)
        self.assertIn("copy plain text first", refusal)
        self.assertIn("printf probe |", refusal)
        self.assertEqual(self.clipboard.contents(), "styled")

    def test_clobber_runs_anyway(self):
        self.clipboard = FileClipboard("", ["«class PNGf»"])
        ran = []
        done, _, _ = clipboard_probe.preserving(
            self.clipboard.board(), clobber=True, writes=lambda: ran.append(True))
        self.assertTrue(done)
        self.assertEqual(ran, [True])

    def test_a_clean_run_puts_the_text_back(self):
        self.clipboard = FileClipboard("before", ["«class utf8»"])
        done, restored, _ = clipboard_probe.preserving(
            self.clipboard.board(), clobber=False, writes=lambda: self.clipboard.write("nonce"))
        self.assertTrue(done)
        self.assertTrue(restored)
        self.assertEqual(self.clipboard.contents(), "before")


class LeakCheckTests(unittest.TestCase):

    def unreadable(self):
        return clipboard_probe.Clipboard(fd=-1, manual=False, helpers=(None, None), lister=(None, None))

    def test_the_leak_check_runs_without_a_reader_where_its_write_is_accepted(self):
        ran = []
        out = clipboard_probe.run_writes(
            self.unreadable(), clobber=True, writes=lambda: self.fail("wrote"), leak=lambda: ran.append(True))
        self.assertEqual(ran, [True])
        self.assertIn("leak check alone ran", out["note"])

    def test_without_a_reader_or_clobber_nothing_is_written(self):
        out = clipboard_probe.run_writes(
            self.unreadable(), clobber=False, writes=lambda: self.fail("wrote"), leak=lambda: self.fail("leaked"))
        self.assertIn("--clobber takes the leak check alone", out["note"])


if __name__ == "__main__":
    unittest.main()
