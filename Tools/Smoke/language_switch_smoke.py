#!/usr/bin/env python3
"""Does switching the language redraw the running app in it, and keep it?

`LocalizationService.setLanguage(_:)` is two halves in two places: the
service changes and persists its language, and an extension beside the views
asks the running app for the frame that shows it (the module split's R1 put
the halves apart, because the service sits below the views and cannot name the
app's render state). The unit tests cover each half; only a live run can say
the halves still meet — that the words on screen change, the app's own and
TUIkit's alike, and that the choice is there on the next launch.

The subject is the Example's Theme page, whose Language picker calls
`setLanguage(_:)`. Three runs, all on one fresh config directory:

  1. launch — the page reads in English (the precondition: the locale
     variables and the config directory are this probe's own); click
     "Deutsch", and the page and the status bar read in German;
  2. relaunch on the SAME directory — it opens in German, so the choice was
     stored;
  3. click "English" — it reads in English again.

What this cannot tell apart: the click is an input event a control consumed,
and the run loop asks for a frame after every such event, so a `setLanguage`
that forgot its own request would still pass here — LocalizationServiceTests'
`changingTheLanguageAsksForAFrame` pins that request. What this does catch is the
rest of the chain going quiet — strings that do not re-resolve, a memo that
serves the old words, a choice that is not stored.

Usage:  language_switch_smoke.py [--binary PATH] [--keep]
Exit 0 if every check passed, 1 if one failed, 2 if the page never came up.
"""
import argparse
import fcntl
import os
import pty
import select
import shutil
import struct
import sys
import termios
import time

import pyte

COLS, ROWS = 120, 40

# Each language's words for the two things checked: the Example's own section
# header (`page.theme.language`, a string the app registered) and TUIkit's own
# quit item in the status bar (`statusbar.quit`).
WORDS = {
    "en": {"header": "Language", "quit": "quit"},
    "de": {"header": "Sprache", "quit": "beenden"},
}

# The picker's options, as `Language.displayName` spells them.
OPTION = {"en": "English", "de": "Deutsch"}


class App:
    """One run of the Example on the Theme page, on a config directory the caller owns."""

    def __init__(self, binary, config_dir):
        self.screen = pyte.Screen(COLS, ROWS)
        self.stream = pyte.ByteStream(self.screen)
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.environ["TUIKIT_CONFIG_DIR"] = config_dir
            os.environ["TERM"] = "xterm-256color"
            # The language the environment asks for, so run 1 starts in English
            # whatever this machine's own is. Every variable the service reads
            # ahead of LANG goes too — LANGUAGE first, which German Linux
            # desktops set — or it, not LANG, decides
            # (LocalizationService+Detection.swift, `posixLanguageCodes`).
            os.environ["LANG"] = "en_US.UTF-8"
            for name in ("LANGUAGE", "LC_ALL", "LC_MESSAGES"):
                os.environ.pop(name, None)
            os.execv(binary, [binary, "--page", "theme"])
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, COLS, 0, 0))

    def drain(self, seconds):
        end = time.time() + seconds
        while time.time() < end:
            ready, _, _ = select.select([self.fd], [], [], 0.02)
            if not ready:
                continue
            try:
                self.stream.feed(os.read(self.fd, 65536))
            except OSError:
                return

    def text(self):
        return "\n".join(self.screen.display)

    def has_word(self, word):
        """Whether `word` is on screen as a word, not inside a longer one."""
        for line in self.screen.display:
            start = line.find(word)
            while start >= 0:
                end = start + len(word)
                before = line[start - 1] if start > 0 else " "
                after = line[end] if end < len(line) else " "
                if not before.isalpha() and not after.isalpha():
                    return True
                start = line.find(word, start + 1)
        return False

    def reads_in(self, language):
        return all(self.has_word(word) for word in WORDS[language].values())

    def wait_for(self, language, seconds):
        """Drains until the screen reads in `language`, for at most `seconds`."""
        end = time.time() + seconds
        while time.time() < end:
            if self.reads_in(language):
                return True
            self.drain(0.1)
        return self.reads_in(language)

    def find(self, text):
        for row, line in enumerate(self.screen.display):
            column = line.find(text)
            if column >= 0:
                return column, row
        return None

    def click(self, column, row):
        for suffix in (b"M", b"m"):
            os.write(self.fd, b"\x1b[<0;%d;%d%s" % (column + 1, row + 1, suffix))
            self.drain(0.05)

    def choose(self, language):
        """Clicks the picker's option for `language`; whether it was on screen."""
        place = self.find(OPTION[language])
        if place is None:
            return False
        self.click(*place)
        return True

    def quit(self):
        # Escape to the menu first: on a page `q` is a character.
        os.write(self.fd, b"\x1b")
        self.drain(0.4)
        os.write(self.fd, b"q")
        self.drain(0.6)
        for _ in range(60):
            finished, _ = os.waitpid(self.pid, os.WNOHANG)
            if finished == self.pid:
                return True
            time.sleep(0.05)
        self.kill()
        return False

    def kill(self):
        try:
            os.kill(self.pid, 9)
        except ProcessLookupError:
            pass
        try:
            os.waitpid(self.pid, 0)
        except ChildProcessError:
            pass


def summary(app):
    words = {lang: {key: app.has_word(word) for key, word in w.items()} for lang, w in WORDS.items()}
    return " ".join(f"{lang}:{','.join(k for k, v in seen.items() if v) or '-'}" for lang, seen in words.items())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", default=".build/debug/Example")
    parser.add_argument("--keep", action="store_true", help="leave the config dir behind")
    args = parser.parse_args()

    config_dir = os.path.join(os.environ.get("TMPDIR", "/tmp"), f"tuikit-language-{os.getpid()}")
    os.makedirs(config_dir, exist_ok=True)
    failures = []

    try:
        # 1. A fresh directory: English, then a click on Deutsch.
        app = App(args.binary, config_dir)
        if not app.wait_for("en", 5.0):
            print(f"!! the Theme page never read in English ({summary(app)})")
            print(app.text())
            app.kill()
            return 2
        print(f"run 1 (launch)   {summary(app)}")
        if not app.choose("de"):
            failures.append(f"no {OPTION['de']!r} option on the Theme page")
        elif not app.wait_for("de", 2.0):
            failures.append("clicking Deutsch did not redraw the page and the status bar in German")
        print(f"run 1 (Deutsch)  {summary(app)}")
        if not app.quit():
            failures.append("the app did not exit on Escape, q")

        # 2. The same directory: German from the first frame.
        app = App(args.binary, config_dir)
        if not app.wait_for("de", 5.0):
            failures.append("the relaunch did not open in German: the choice was not stored")
        print(f"run 2 (relaunch) {summary(app)}")

        # 3. And back.
        if not app.choose("en"):
            failures.append(f"no {OPTION['en']!r} option on the relaunched page")
        elif not app.wait_for("en", 2.0):
            failures.append("clicking English did not redraw the page in English")
        print(f"run 2 (English)  {summary(app)}")
        app.quit()
    finally:
        if not args.keep:
            shutil.rmtree(config_dir, ignore_errors=True)

    print()
    for failure in failures:
        print(f"FAIL: {failure}")
    if not failures:
        print("PASS: the language switched on screen at once, persisted, and switched back")
    return 1 if failures else 0


sys.exit(main())
