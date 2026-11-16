#!/usr/bin/env python3
"""
Tests for `ab_bench.py`'s calibration.

    python3 Tools/Profiling/test_ab_bench.py

The harness is a stub that prices a frame by how many the run has, so these
need no build: they are about how many iterations `calibrate` asks for.
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ab_bench  # noqa: E402


def stub(cheap_frames, cheap_us, dear_us):
    """A harness whose first `cheap_frames` frames cost `cheap_us` and the
    rest `dear_us`, as `glide`'s frames before its first `scrollTo` do; the
    iteration counts it was asked for are kept in `asked`."""
    asked = []

    def runner(binary, scenario, scale, iterations, cols, rows, cold):
        asked.append(iterations)
        cheap = min(iterations, cheap_frames)
        mean = (cheap * cheap_us + (iterations - cheap) * dear_us) / iterations
        return mean, mean, None, None

    return runner, asked


class CalibrationTests(unittest.TestCase):
    def test_a_steady_scenario_is_priced_by_its_frames(self):
        runner, asked = stub(cheap_frames=0, cheap_us=100, dear_us=100)
        iterations = ab_bench.calibrate("bin", "fanout", 1, 4.5, 120, 40, runner=runner)
        self.assertEqual(iterations, 45_000)
        # The second pilot is a tenth of a run, capped.
        self.assertEqual(asked, [30, 1_000])

    def test_frames_dearer_after_the_first_pilot_are_priced(self):
        # 30 frames at 60 µs, then 360 µs: one pilot of 30 asked for 75,000
        # frames, 27 s of them, against a 4.5 s target.
        runner, _ = stub(cheap_frames=31, cheap_us=60, dear_us=360)
        iterations = ab_bench.calibrate("bin", "glide", 1, 4.5, 120, 40, runner=runner)
        seconds = (31 * 60 + (iterations - 31) * 360) / 1_000_000
        self.assertLess(seconds, 4.5 * 1.2, f"{iterations} iterations last {seconds:.1f} s")

    def test_a_dear_scenario_pilots_no_more_than_it_needs(self):
        runner, asked = stub(cheap_frames=0, cheap_us=50_000, dear_us=50_000)
        ab_bench.calibrate("bin", "huge", 1, 4.5, 120, 40, runner=runner)
        self.assertEqual(asked, [30, 30])


class CaseSelectionTests(unittest.TestCase):
    """`--cases` and `--tags`, against a stub of `Stress --cases`."""

    CASES = {"list-wheel": ({"list", "window"}, True), "list-hover": ({"list", "hover"}, False),
             "table-fit-tail": ({"table", "memo"}, True)}

    def lister(self, binary, timed=False, tags=None):
        self.asked.append((timed, tags))
        return [case for case, (case_tags, case_timed) in self.CASES.items()
                if (not timed or case_timed) and (not tags or case_tags & set(tags))]

    def setUp(self):
        self.asked = []

    def choose(self, wanted, tags=()):
        return ab_bench.case_scenarios("bin", wanted, list(tags), lister=self.lister)

    def test_every_case_is_its_session(self):
        self.assertEqual(self.choose([]), ["session/case:list-wheel", "session/case:list-hover",
                                           "session/case:table-fit-tail"])

    def test_timed_asks_the_binary_for_the_timed_sweep(self):
        self.assertEqual(self.choose(["timed"]), ["session/case:list-wheel", "session/case:table-fit-tail"])
        self.assertEqual(self.asked, [(True, [])])

    def test_tags_pick_cases_with_any_of_them(self):
        self.assertEqual(self.choose([], tags=["hover", "memo"]),
                         ["session/case:list-hover", "session/case:table-fit-tail"])

    def test_named_cases_keep_their_order(self):
        self.assertEqual(self.choose(["table-fit-tail", "list-wheel"]),
                         ["session/case:table-fit-tail", "session/case:list-wheel"])

    def test_a_misspelt_case_stops_the_run(self):
        with self.assertRaises(SystemExit):
            self.choose(["list-wheal"])

    def test_a_binary_with_no_cases_stops_the_run(self):
        with self.assertRaises(SystemExit):
            ab_bench.case_scenarios("bin", [], [], lister=lambda *_, **__: None)


if __name__ == "__main__":
    unittest.main()
