#!/usr/bin/env python3
"""
Tests for `drive.py`, the Mode-B PTY driver.

    python3 Tools/Profiling/test_drive.py

The driven binary is a stub that reports what it was launched with, so these
need no build and no Instruments: they are about what `drive.py` hands the
app, not about the app. The exception is `TestTourStaysOnItsRoute`, which is
about where the `tour`'s keys land in the real Example, drives a built one
(`.build/debug/Example`, or `$DRIVE_TEST_BINARY`), and is skipped without it.

What they guard is where the app's persisted state goes. `record.sh` — the
profiling flow CLAUDE.md sends everyone through — runs `drive.py`, and a
TUI app writes its `@AppStorage` wherever `TUI_CONFIG_DIR` says, or,
with it unset on macOS, into the user's real preferences domain
(`~/Library/Preferences/Example.plist`; UserDefaults ignores a `$HOME`
override, so nothing short of the variable isolates it). The driver passed
its own environment straight through, so a profiling run read and wrote the
developer's own settings — and what it wrote was page shortcuts typed into
the Sliders page's track editor, which is how a Fill of `■];q];-=s.m1`
reached the owner's screen.
"""

import base64
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
_DRIVE = os.path.join(_HERE, "drive.py")

# The stand-in app. It records the configuration directory it was given —
# and whether that directory existed — then writes a setting into it the way
# `JSONFileStorage` would, and runs until the driver's closing `q`, so the run
# ends the way a real one does rather than by the driver killing it.
_STUB = """\
import json, os, sys, tty
config = os.environ.get("TUI_CONFIG_DIR", "")
with open(os.environ["DRIVE_TEST_REPORT"], "w") as report:
    json.dump({"config": config, "existed": bool(config) and os.path.isdir(config)}, report)
if config:
    os.makedirs(os.path.join(config, "Example"), exist_ok=True)
    with open(os.path.join(config, "Example", "settings.json"), "w") as settings:
        settings.write("{}")
tty.setraw(0)
while True:
    data = os.read(0, 4096)
    if not data or b"q" in data:
        break
"""


class TestConfigIsolation(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.mkdtemp(prefix="test-drive-")
        self.addCleanup(shutil.rmtree, self.scratch, ignore_errors=True)
        self.stub = os.path.join(self.scratch, "Example")
        with open(self.stub, "w") as handle:
            handle.write(f"#!{sys.executable}\n{_STUB}")
        os.chmod(self.stub, os.stat(self.stub).st_mode | stat.S_IXUSR)

    def drive(self, name, config_dir=None):
        """One `drive.py` run of the stub; returns what the stub reported."""
        report = os.path.join(self.scratch, f"{name}.json")
        env = {key: value for key, value in os.environ.items() if key != "TUI_CONFIG_DIR"}
        env["DRIVE_TEST_REPORT"] = report
        if config_dir is not None:
            env["TUI_CONFIG_DIR"] = config_dir
        # `list` is the shortest scenario that types anything: ~2 s.
        subprocess.run(
            [sys.executable, _DRIVE, self.stub, "--scenario", "list", "--settle", "0.1", "--quiet"],
            env=env, check=True, timeout=60)
        with open(report) as handle:
            return json.load(handle)

    def test_a_run_gets_a_fresh_config_directory_of_its_own(self):
        first = self.drive("first")
        self.assertNotEqual(
            first["config"], "",
            "the app was launched with no TUI_CONFIG_DIR, so on macOS it read and wrote "
            "the developer's real preferences")
        self.assertTrue(first["existed"], "the directory the app was given did not exist")
        self.assertFalse(
            os.path.exists(first["config"]),
            "the run's configuration directory outlived the run")
        # Fresh each time: what one scenario typed into a field must not be
        # what the next one profiles.
        second = self.drive("second")
        self.assertNotEqual(second["config"], "")
        self.assertNotEqual(first["config"], second["config"])

    def test_a_directory_the_caller_chose_is_used_and_kept(self):
        chosen = os.path.join(self.scratch, "chosen")
        os.makedirs(chosen)
        reported = self.drive("chosen", config_dir=chosen)
        self.assertEqual(reported["config"], chosen)
        self.assertTrue(
            os.path.exists(os.path.join(chosen, "Example", "settings.json")),
            "a directory the caller named is the caller's to delete")


# A stand-in that answers every byte it reads with that byte in hex, and
# writes nothing else, so the stream the driver dumps is a known function of
# what the driver sent: the reply to a step begins exactly where the hex of
# every earlier step ends.
_ECHO_STUB = """\
import os, sys, tty
tty.setraw(0)
while True:
    data = os.read(0, 4096)
    if not data:
        break
    os.write(1, data.hex().encode())
    if b"q" in data:
        break
"""


class TestStepMarkers(unittest.TestCase):
    """`--dump` writes where each step was sent, beside the stream.

    O2's estimate (`analyze_stream.py --shift`) compares the screen before and
    after each step, so it needs to know which bytes answered which input. A
    PTY delivers one undivided stream; the driver is the only party that knows
    when it wrote each key.
    """

    def setUp(self):
        self.scratch = tempfile.mkdtemp(prefix="test-drive-steps-")
        self.addCleanup(shutil.rmtree, self.scratch, ignore_errors=True)
        self.stub = os.path.join(self.scratch, "Example")
        with open(self.stub, "w") as handle:
            handle.write(f"#!{sys.executable}\n{_ECHO_STUB}")
        os.chmod(self.stub, os.stat(self.stub).st_mode | stat.S_IXUSR)

    def test_each_step_is_marked_where_it_was_sent(self):
        sys.path.insert(0, _HERE)
        try:
            import drive
        finally:
            sys.path.remove(_HERE)
        dump = os.path.join(self.scratch, "list.ansi")
        env = dict(os.environ, TUI_CONFIG_DIR=self.scratch)
        subprocess.run(
            [sys.executable, _DRIVE, self.stub, "--scenario", "list", "--settle", "0.1",
             "--rows", "30", "--cols", "90", "--dump", dump, "--quiet"],
            env=env, check=True, timeout=60)
        with open(dump, "rb") as handle:
            stream = handle.read()
        with open(dump + ".steps.json") as handle:
            markers = json.load(handle)

        script = drive.build_scenario("list", 30, 90)
        payloads = [payload for _, payload in script]
        # The stream is still exactly the app's: the markers live beside it,
        # and the stub's only output is the hex of what it was sent.
        self.assertEqual(stream, b"".join(payloads).hex().encode())
        self.assertEqual(markers["total"], len(stream))
        self.assertEqual(
            (markers["scenario"], markers["rows"], markers["cols"], markers["loops"]),
            ("list", 30, 90, 1))

        steps = markers["steps"]
        # Startup, then one marker per scripted step, in order.
        self.assertEqual(len(steps), len(script) + 1)
        self.assertEqual([step["index"] for step in steps], list(range(len(steps))))
        self.assertEqual((steps[0]["offset"], steps[0]["input"]), (0, "startup"))
        self.assertEqual(steps[1]["input"], "-", "the Lists page shortcut")
        self.assertEqual(steps[2]["input"], "ESC[B", "a Down arrow")
        offsets = [step["offset"] for step in steps]
        self.assertEqual(offsets, sorted(offsets))
        # No marker is late: the reply to a step cannot begin before the
        # step's own marker, because the marker is taken before the write.
        # Step k's reply begins after the hex of every earlier step.
        echoed = 0
        answered = 0
        for step, payload in zip(steps[1:], payloads):
            self.assertLessEqual(step["offset"], echoed, f"step {step['index']}")
            # …and not early: by the time a step is sent, the delay before it
            # has drained the reply to the step before. Only nearly always —
            # a PTY makes no promise about when the stub's reply lands — but
            # a marker taken before the delay's drain misses it every time.
            if step["offset"] == echoed:
                answered += 1
            echoed += 2 * len(payload)
        self.assertGreaterEqual(
            answered, len(payloads) // 2,
            "most markers should fall after the previous step's reply")
        times = [step["at"] for step in steps]
        self.assertEqual(times, sorted(times))


# A stand-in that asks what every TUI startup exchange asks last, the
# status report `CSI 5n`, and records whether `CSI 0n` came back before the
# deadline TUI gives it — split across two writes, as a slow app might.
_FENCE_STUB = """\
import json, os, select, sys, time, tty
tty.setraw(0)
os.write(1, b"\\x1b[5")
time.sleep(0.05)
os.write(1, b"n")
got = b""
deadline = time.time() + 0.5
while time.time() < deadline and b"\\x1b[0n" not in got:
    ready, _, _ = select.select([0], [], [], max(0.0, deadline - time.time()))
    if ready:
        got += os.read(0, 64)
with open(os.environ["DRIVE_TEST_REPORT"], "w") as report:
    json.dump({"answered": b"\\x1b[0n" in got}, report)
while b"q" not in got:
    data = os.read(0, 4096)
    if not data:
        break
    got += data
"""


class TestAnswerFence(unittest.TestCase):
    """`--answer-fence` answers the status request as a terminal would.

    A PTY answers nothing, so each of a TUI app's three startup exchanges
    waits out its half-second deadline, and a scenario's keys land while it
    does: `scroll` lost all but a dozen of its steps to that. The flag is off
    by default, so numbers taken without it stay comparable.
    """

    def setUp(self):
        self.scratch = tempfile.mkdtemp(prefix="test-drive-fence-")
        self.addCleanup(shutil.rmtree, self.scratch, ignore_errors=True)
        self.stub = os.path.join(self.scratch, "Example")
        with open(self.stub, "w") as handle:
            handle.write(f"#!{sys.executable}\n{_FENCE_STUB}")
        os.chmod(self.stub, os.stat(self.stub).st_mode | stat.S_IXUSR)

    def answered(self, *flags):
        report = os.path.join(self.scratch, "fence.json")
        env = dict(os.environ, TUI_CONFIG_DIR=self.scratch, DRIVE_TEST_REPORT=report)
        subprocess.run(
            [sys.executable, _DRIVE, self.stub, "--scenario", "list", "--settle", "1",
             "--quiet", *flags],
            env=env, check=True, timeout=60)
        with open(report) as handle:
            return json.load(handle)["answered"]

    def test_the_status_request_is_answered_only_when_asked_to(self):
        self.assertTrue(self.answered("--answer-fence"), "even split across two reads")
        self.assertFalse(self.answered(), "off by default")


# A stand-in for an app whose status request comes in a LATER exchange, as
# the graphics and colour exchanges do: a first burst at once, the request
# 0.3 s after it, and the same half-second deadline for the reply.
_LATE_FENCE_STUB = """\
import json, os, select, sys, time, tty
tty.setraw(0)
os.write(1, b"\\x1b[?1049h")
time.sleep(0.3)
os.write(1, b"\\x1b[5n")
got = b""
deadline = time.time() + 0.5
while time.time() < deadline and b"\\x1b[0n" not in got:
    ready, _, _ = select.select([0], [], [], max(0.0, deadline - time.time()))
    if ready:
        got += os.read(0, 64)
with open(os.environ["DRIVE_TEST_REPORT"], "w") as report:
    json.dump({"answered": b"\\x1b[0n" in got}, report)
while b"q" not in got:
    data = os.read(0, 4096)
    if not data:
        break
    got += data
"""


class TestAnswerFenceWhileTracing(unittest.TestCase):
    """`--answer-fence` answers through `--trace`'s warm-up too.

    With `--trace` the driver gives xctrace two seconds to start sampling
    before it drives. It slept through them, after a settle that ends at the
    app's first burst, so a status request sent in that window, by the
    exchanges after the first, went unread until the deadline had passed.
    `xcrun` is a stand-in here that exits at once: what is under test is the
    driver's reading, not Instruments.
    """

    def setUp(self):
        self.scratch = tempfile.mkdtemp(prefix="test-drive-trace-")
        self.addCleanup(shutil.rmtree, self.scratch, ignore_errors=True)
        self.stub = os.path.join(self.scratch, "Example")
        with open(self.stub, "w") as handle:
            handle.write(f"#!{sys.executable}\n{_LATE_FENCE_STUB}")
        os.chmod(self.stub, os.stat(self.stub).st_mode | stat.S_IXUSR)
        self.bin = os.path.join(self.scratch, "bin")
        os.makedirs(self.bin)
        xcrun = os.path.join(self.bin, "xcrun")
        with open(xcrun, "w") as handle:
            handle.write("#!/bin/sh\nexit 0\n")
        os.chmod(xcrun, os.stat(xcrun).st_mode | stat.S_IXUSR)

    def test_a_request_during_the_warm_up_is_answered(self):
        report = os.path.join(self.scratch, "fence.json")
        env = dict(os.environ, TUI_CONFIG_DIR=self.scratch, DRIVE_TEST_REPORT=report,
                   PATH=self.bin + os.pathsep + os.environ.get("PATH", ""))
        subprocess.run(
            [sys.executable, _DRIVE, self.stub, "--scenario", "list", "--settle", "1",
             "--trace", os.path.join(self.scratch, "unused.trace"), "--answer-fence", "--quiet"],
            env=env, check=True, timeout=60)
        with open(report) as handle:
            self.assertTrue(json.load(handle)["answered"],
                            "the request 0.3 s after the first burst went unread")


_REPO = os.path.dirname(os.path.dirname(_HERE))
_EXAMPLE = os.environ.get("DRIVE_TEST_BINARY", os.path.join(_REPO, ".build", "debug", "Example"))


# Local only. Its margins — 150 ms between the two Escapes and before `q` — were
# measured on a developer's machine, and a slow shared runner can merge an ESC
# with the key after it (Alt+q), failing the run with nothing wrong. A flaky gate
# costs more than this check buys there; the stub test above is the CI half.
@unittest.skipIf(os.environ.get("CI"), "local only: its key timing margins were measured on a developer's machine")
@unittest.skipUnless(os.access(_EXAMPLE, os.X_OK), f"needs a built Example ({_EXAMPLE})")
class TestTourStaysOnItsRoute(unittest.TestCase):
    """The real Example, because the question is what its pages do with the keys.

    The `tour` jumps to a page by its menu shortcut, scrolls with the arrows
    and presses Escape to go back to the menu for the next one. On the
    Sliders page the arrows walk the focus into the track editor's Fill combo
    field, where Down opens its suggestions — so that page's Escape closed the
    menu instead of leaving the page, and every key after it (the Steppers and
    Split View shortcuts, then the closing `q`) was typed into the field. The
    two last pages were never profiled, the app never quit, and the text was
    saved as the field's value.
    """

    def test_the_tour_types_nothing_and_ends_by_quitting(self):
        scratch = tempfile.mkdtemp(prefix="test-drive-tour-")
        self.addCleanup(shutil.rmtree, scratch, ignore_errors=True)
        # Named explicitly, not left to the driver: this must be isolated
        # whichever `drive.py` it runs against.
        env = dict(os.environ, TUI_CONFIG_DIR=scratch)
        # A long settle: in a PTY that answers none of its startup queries, a
        # debug Example takes ~1.5 s to start reading keys, and everything
        # sent before then is parsed as one batch — a different question.
        result = subprocess.run(
            [sys.executable, _DRIVE, _EXAMPLE, "--scenario", "tour", "--settle", "2.5", "--quiet"],
            env=env, timeout=120, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        # The tour only navigates and scrolls, so it has no business saving
        # anything; what a stray keystroke saves is the evidence it went
        # somewhere other than where the script meant.
        settings_file = os.path.join(scratch, "Example", "settings.json")
        saved = {}
        if os.path.exists(settings_file):
            with open(settings_file) as handle:
                saved = json.load(handle)
        decoded = {key: base64.b64decode(value).decode() for key, value in saved.items()}
        self.assertEqual(decoded, {}, "the tour's keys changed the app's saved settings")


if __name__ == "__main__":
    unittest.main()
