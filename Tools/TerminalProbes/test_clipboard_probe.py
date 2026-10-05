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

    def board(self):
        helpers = (["cat", self.path], ["sh", "-c", f"cat > '{self.path}'"])
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


if __name__ == "__main__":
    unittest.main()
