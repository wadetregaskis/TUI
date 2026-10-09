#!/usr/bin/env python3
"""
Tests for `analyze_timeprofile.py`: every sample is counted once, with its
weight, however xctrace spelled its stack.

    python3 Tools/Profiling/test_analyze_timeprofile.py

No build and no Instruments. The analyzer reads `xctrace export`'s XML from
a cache file beside the trace, so a directory holding that one file is a
trace as far as it can tell, and the XML here is written by hand in the
export's own shapes, small enough to count by hand.

What they guard: xctrace writes a stack it has already written as
`<backtrace ref="N"/>`, with no frames. Until 2026-10-08 the analyzer read
only the `<frame>` children, so every repeated stack came out empty and was
skipped — it counted each distinct stack once, 21-64% of the samples in that
day's traces, and the stacks it dropped were the most repeated, i.e. the
hottest. `TestARealTrace` checks the same on a recorded trace, and is skipped
without one (`$TIMEPROFILE_TEST_TRACE`, or a `profiling-traces/*.trace`
already exported once).
"""

import contextlib
import glob
import io
import os
import shutil
import sys
import tempfile
import unittest
import unittest.mock

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _HERE)
import analyze_timeprofile  # noqa: E402

CACHE = "analysis-cache-run1-time-profile.xml"

# The export's header, as `xctrace export` writes it (one line there).
HEADER = (
    '<?xml version="1.0"?>\n<trace-query-result>\n'
    "<node xpath='//trace-toc[1]/run[1]/data[1]/table[12]'>"
    '<schema name="time-profile">'
    "<col><mnemonic>time</mnemonic></col><col><mnemonic>thread</mnemonic></col>"
    "<col><mnemonic>process</mnemonic></col><col><mnemonic>core</mnemonic></col>"
    "<col><mnemonic>thread-state</mnemonic></col><col><mnemonic>weight</mnemonic></col>"
    "<col><mnemonic>stack</mnemonic></col></schema>\n"
)
FOOTER = "</node></trace-query-result>\n"

# Nine samples on three stacks, leaf first:
#
#   A  swift_release (a system library) <- Hot.inner() <- main      rows 1-4, 8
#   B  Cold.leaf() <- main                                           row 5
#   C  Idle.wait() <- main                                           rows 6, 9
#
# Each stack is written out once, where it first appears (`<backtrace id>`),
# and every later sample on it is `<backtrace ref>` alone. Frames repeat the
# same way: `main` is written in A and only referenced in B and C. Row 6 is
# Blocked, so the default `--state running` skips it, yet row 9 refers to the
# stack it defined. Row 7 has no stack at all (`<sentinel/>`, as xctrace
# writes one). Row 8 is on another thread. Row 5 weighs 2 ms, the rest 1 ms.
SAMPLES = HEADER + (
    # 1: everything is defined here — the main thread, its process, the
    #    state, the 1 ms weight, stack A and its three frames and two binaries.
    '<row><sample-time id="1" fmt="00:00.001">1000000</sample-time>'
    '<thread id="2" fmt="Main Thread 0x1 (App, pid: 7)"><tid id="3" fmt="0x1">1</tid>'
    '<process id="4" fmt="App (7)"><pid id="5" fmt="7">7</pid></process></thread>'
    '<process ref="4"/><core id="6" fmt="CPU 0">0</core>'
    '<thread-state id="7" fmt="Running">Running</thread-state>'
    '<weight id="8" fmt="1.00 ms">1000000</weight>'
    '<backtrace id="10">'
    '<frame id="11" name="swift_release" addr="0x18000">'
    '<binary id="12" name="libswiftCore.dylib" path="/usr/lib/swift/libswiftCore.dylib"/></frame>'
    '<frame id="13" name="Hot.inner()" addr="0x10010">'
    '<binary id="14" name="App" path="/Users/dev/App/.build/release/App"/></frame>'
    '<frame id="15" name="main" addr="0x10000"><binary ref="14"/></frame>'
    "</backtrace></row>\n"
    # 2-4: stack A again, by reference.
    + "".join(
        f'<row><sample-time id="{n}" fmt="t">{n}</sample-time><thread ref="2"/>'
        '<process ref="4"/><core ref="6"/><thread-state ref="7"/><weight ref="8"/>'
        '<backtrace ref="10"/></row>\n'
        for n in (16, 17, 18))
    # 5: stack B, 2 ms; `main` by frame reference.
    + '<row><sample-time id="19" fmt="t">19</sample-time><thread ref="2"/>'
    '<process ref="4"/><core ref="6"/><thread-state ref="7"/>'
    '<weight id="20" fmt="2.00 ms">2000000</weight>'
    '<backtrace id="21"><frame id="22" name="Cold.leaf()" addr="0x10020">'
    '<binary ref="14"/></frame><frame ref="15"/></backtrace></row>\n'
    # 6: Blocked, defining stack C.
    '<row><sample-time id="23" fmt="t">23</sample-time><thread ref="2"/>'
    '<process ref="4"/><core ref="6"/>'
    '<thread-state id="24" fmt="Blocked">Blocked</thread-state><weight ref="8"/>'
    '<backtrace id="25"><frame id="26" name="Idle.wait()" addr="0x10030">'
    '<binary ref="14"/></frame><frame ref="15"/></backtrace></row>\n'
    # 7: no stack.
    '<row><sample-time id="27" fmt="t">27</sample-time><thread ref="2"/>'
    '<process ref="4"/><core ref="6"/><thread-state ref="7"/><weight ref="8"/>'
    "<sentinel/></row>\n"
    # 8: another thread, defined here, on stack A.
    '<row><sample-time id="28" fmt="t">28</sample-time>'
    '<thread id="29" fmt="Thread 0x2 (App, pid: 7)"><tid id="30" fmt="0x2">2</tid>'
    '<process ref="4"/></thread><process ref="4"/><core ref="6"/>'
    '<thread-state ref="7"/><weight ref="8"/><backtrace ref="10"/></row>\n'
    # 9: Running, on the stack the skipped row 6 defined.
    '<row><sample-time id="31" fmt="t">31</sample-time><thread ref="2"/>'
    '<process ref="4"/><core ref="6"/><thread-state ref="7"/><weight ref="8"/>'
    '<backtrace ref="25"/></row>\n'
) + FOOTER


class Scratch(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.mkdtemp(prefix="test-analyze-timeprofile-")
        self.addCleanup(shutil.rmtree, self.scratch, ignore_errors=True)

    def trace(self, xml, name="synthetic"):
        """A directory the analyzer takes for an exported trace."""
        path = os.path.join(self.scratch, name + ".trace")
        os.makedirs(path, exist_ok=True)
        with open(os.path.join(path, CACHE), "w") as handle:
            handle.write(xml)
        return path

    def analyze(self, xml, thread="all", state="running", **options):
        return analyze_timeprofile.analyze(self.trace(xml), 1, 30, thread, state, **options)


class TestEverySampleCounts(Scratch):
    def test_a_repeated_stack_counts_every_time_with_its_weight(self):
        r = self.analyze(SAMPLES)
        self.assertEqual(r["rows"], 9)
        # Rows 1-5 and 7-9: everything but the Blocked row 6.
        self.assertEqual(r["samples"], 8)
        self.assertEqual(r["total_ms"], 4 * 1 + 2 + 1 + 1 + 1)
        # Rows 2, 3, 4, 8 and 9 are references, row 9's to a skipped row.
        self.assertEqual(r["repeated_stacks"], 5)
        self.assertEqual(r["unresolved"], {})
        self.assertEqual(r["no_stack"], 1)

    def test_shares_are_of_every_sample(self):
        # Counting a stack only where it is written out, as the analyzer did
        # until 2026-10-08, keeps rows 1 and 5 (1 + 2 ms): swift_release a
        # third, and Idle.wait() absent, since C is written out only in the
        # Blocked row.
        r = self.analyze(SAMPLES)
        total = r["total_ms"]
        self.assertAlmostEqual(r["self_ms"]["swift_release"] / total, 5 / 9)
        self.assertAlmostEqual(r["self_ms"]["Cold.leaf()"] / total, 2 / 9)
        self.assertAlmostEqual(r["self_ms"]["Idle.wait()"] / total, 1 / 9)
        self.assertAlmostEqual(r["self_ms"][analyze_timeprofile.NO_BACKTRACE] / total, 1 / 9)
        self.assertEqual(r["self_n"]["swift_release"], 5)
        self.assertEqual(dict(r["incl_ms"]), {
            "main": 8, "Hot.inner()": 5, "swift_release": 5, "Cold.leaf()": 2,
            "Idle.wait()": 1, analyze_timeprofile.NO_BACKTRACE: 1})

    def test_the_module_split_and_the_app_only_views(self):
        r = self.analyze(SAMPLES)
        self.assertEqual(dict(r["mod_ms"]), {"libswiftCore.dylib": 5, "App": 3,
                                             analyze_timeprofile.NO_BACKTRACE: 1})
        self.assertEqual(dict(r["app_self_ms"]), {"Cold.leaf()": 2, "Idle.wait()": 1})
        self.assertEqual(dict(r["app_incl_ms"]),
                         {"main": 8, "Hot.inner()": 5, "Cold.leaf()": 2, "Idle.wait()": 1})
        self.assertEqual(dict(r["thread_ms"]), {"Main Thread 0x1": 8, "Thread 0x2": 1})

    def test_the_filters_count_what_they_keep(self):
        everything = self.analyze(SAMPLES, state="all")
        self.assertEqual((everything["samples"], everything["total_ms"]), (9, 10))
        self.assertEqual(everything["self_ms"]["Idle.wait()"], 2)
        main = self.analyze(SAMPLES, thread="main")
        self.assertEqual((main["samples"], main["total_ms"]), (7, 8))
        self.assertEqual(main["self_ms"]["swift_release"], 4)
        self.assertEqual(self.analyze(SAMPLES, process_filter="App")["samples"], 8)
        self.assertEqual(self.analyze(SAMPLES, process_filter="Other")["samples"], 0)

    def test_blame_callers_and_within_see_the_repeats(self):
        r = self.analyze(SAMPLES, blame="")
        self.assertEqual(dict(r["blame_ms"]),
                         {"Hot.inner()": 5, "Cold.leaf()": 2, "Idle.wait()": 1})
        self.assertEqual(r["blame_n"]["Hot.inner()"], 5)
        self.assertEqual((r["blame_matched_ms"], r["blame_unattributed_ms"]), (9, 1))
        r = self.analyze(SAMPLES, blame="swift_release", callers_of="swift_release")
        self.assertEqual((r["blame_matched_ms"], dict(r["blame_ms"])), (5, {"Hot.inner()": 5}))
        self.assertEqual((r["callers_matched_ms"], dict(r["callers_ms"])), (5, {"Hot.inner()": 5}))
        r = self.analyze(SAMPLES, within="Cold|Idle")
        self.assertEqual((r["total_ms"], r["all_ms"]), (3, 9))
        self.assertEqual((r["within_samples"], r["samples"]), (2, 8))

    def test_no_pattern_matches_a_sample_with_no_stack(self):
        # Row 7's `<no backtrace>` is a placeholder for a missing stack, not
        # a function: it is counted, but there is nothing on it to match.
        for pattern in ("back", "no backtrace"):
            r = self.analyze(SAMPLES, within=pattern)
            self.assertEqual((r["total_ms"], r["all_ms"]), (0, 9), pattern)
            r = self.analyze(SAMPLES, blame=pattern, callers_of=pattern)
            self.assertEqual((r["blame_matched_ms"], r["callers_matched_ms"]), (0, 0), pattern)
            self.assertEqual(r["self_ms"][analyze_timeprofile.NO_BACKTRACE], 1, pattern)

    def test_the_header_says_how_many_rows_were_counted(self):
        trace = self.trace(SAMPLES)
        out, err = io.StringIO(), io.StringIO()
        argv = ["analyze_timeprofile.py", trace, "--blame", "--callers", "release"]
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err), \
                unittest.mock.patch.object(sys, "argv", argv):
            analyze_timeprofile.main()
        self.assertIn("rows=9 (5 repeat an earlier stack)  counted=8  on-CPU≈9 ms",
                      out.getvalue())
        self.assertIn("no stack=1", out.getvalue())
        self.assertEqual(err.getvalue(), "")

    def test_within_says_how_many_of_the_counted_samples_it_kept(self):
        # The header stays the whole denominator under --within, threads and
        # all: rows 5 and 9 (2 + 1 ms) are the two of the eight samples that
        # have Cold or Idle on them.
        out = io.StringIO()
        argv = ["analyze_timeprofile.py", self.trace(SAMPLES), "--within", "Cold|Idle"]
        with contextlib.redirect_stdout(out), \
                unittest.mock.patch.object(sys, "argv", argv):
            analyze_timeprofile.main()
        self.assertIn("counted=8  on-CPU≈9 ms", out.getvalue())
        self.assertIn("per-thread on-CPU ms: Main Thread 0x1=8, Thread 0x2=1", out.getvalue())
        self.assertIn("within 'Cold|Idle': 2 of the 8 counted samples, 3 ms of 9 ms (33.3%)",
                      out.getvalue())


class TestUnresolvedRefs(Scratch):
    def test_a_ref_to_nothing_is_counted_and_reported(self):
        # A stack and a frame that were never defined: the samples still
        # count, under names that say what is missing, and the analyzer
        # says how many refs it could not follow.
        xml = HEADER + (
            '<row><thread id="2" fmt="Main Thread 0x1 (App, pid: 7)"/>'
            '<thread-state id="7" fmt="Running">Running</thread-state>'
            '<weight id="8" fmt="1.00 ms">1000000</weight><backtrace ref="99"/></row>\n'
            '<row><thread ref="2"/><thread-state ref="7"/><weight ref="8"/>'
            '<backtrace id="10"><frame ref="98"/></backtrace></row>\n'
        ) + FOOTER
        r = self.analyze(xml)
        self.assertEqual((r["samples"], r["total_ms"]), (2, 2))
        self.assertEqual(r["unresolved"], {"backtrace": 1, "frame": 1})
        self.assertEqual(dict(r["self_ms"]), {analyze_timeprofile.NO_BACKTRACE: 1,
                                              analyze_timeprofile.UNSYMBOLICATED: 1})
        err = io.StringIO()
        argv = ["analyze_timeprofile.py", self.trace(xml, "unresolved")]
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(err), \
                unittest.mock.patch.object(sys, "argv", argv):
            analyze_timeprofile.main()
        self.assertIn("<backtrace> 1, <frame> 1", err.getvalue())


def recorded_trace():
    """A real trace whose export is already cached, or None."""
    named = os.environ.get("TIMEPROFILE_TEST_TRACE")
    if named:
        return named
    root = os.path.dirname(os.path.dirname(_HERE))
    cached = glob.glob(os.path.join(root, "profiling-traces", "*.trace", CACHE))
    return os.path.dirname(max(cached, key=os.path.getmtime)) if cached else None


@unittest.skipUnless(recorded_trace(), "no recorded trace: set $TIMEPROFILE_TEST_TRACE")
class TestARealTrace(unittest.TestCase):
    def test_every_row_is_counted(self):
        trace = recorded_trace()
        r = analyze_timeprofile.analyze(trace, 1, 30, "all", "all")
        xml = analyze_timeprofile.export_table(trace, 1, "time-profile")  # the cached export
        self.assertEqual(r["unresolved"], {})
        self.assertEqual(r["rows"], xml.count("<row>"))
        self.assertEqual(r["samples"], r["rows"])
        self.assertEqual(r["repeated_stacks"], xml.count("<backtrace ref="))
        self.assertGreater(r["repeated_stacks"], 0, "a real trace repeats its stacks")


if __name__ == "__main__":
    unittest.main()
