#!/usr/bin/env python3
"""
Unit tests for quick.py's verdicts: what it calls a pass, on output written here.

    python3 -m unittest discover -s Tools/Dev -p 'test_*.py'

No build, no toolchain. Every case is a way quick.py once printed a pass, or
nothing at all, for a run that did not happen (H-56).
"""

import importlib.util
import os
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
_SPEC = importlib.util.spec_from_file_location("quick", os.path.join(_HERE, "quick.py"))
quick = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(quick)


def run_output(summary, groups=(), problems=()):
    """parallel_test.py's output, from its own line shapes."""
    lines = ["parallel-test: 3 tests in 2 suites, 2 processes", ""]
    lines += ["  group %s: %5d tests    0.50s wall     1.0s cpu  %s" % g for g in groups]
    lines += ["", summary]
    lines += ["  RECONCILIATION: %s" % p for p in problems]
    return "\n".join(lines) + "\n"


class TestVerdict(unittest.TestCase):
    def test_a_passing_run_passes_with_its_count(self):
        out = run_output("parallel-test: 14 tests in 3 suites passed in 1.20s across 2 processes "
                         "(1.50s end to end, 2.0 cpu-s, 1.7x cores) with 0 known issues",
                         [("g0", 7, "ok"), ("g1", 7, "ok")])
        self.assertEqual(quick.test_verdict(0, out), (True, ["tests ok (14)"]))

    def test_one_test_is_counted_too(self):
        # parallel_test says "1 test in 1 suite"; this once read as no summary at all.
        out = run_output("parallel-test: 1 test in 1 suite passed in 0.20s across 1 process "
                         "(0.50s end to end, 0.2 cpu-s, 1.0x cores) with 0 known issues", [("g0", 1, "ok")])
        self.assertEqual(quick.test_verdict(0, out), (True, ["tests ok (1)"]))

    def test_a_group_that_ran_fewer_tests_than_planned_fails(self):
        # Every group printed ok, and the only problems were RECONCILIATION lines: the waiver passed this.
        out = run_output("parallel-test: 10 tests in 2 suites FAILED in 1.20s across 1 process "
                         "(1.50s end to end, 2.0 cpu-s, 1.7x cores) with 0 known issues",
                         [("g0", 10, "ok")],
                         ["group g0 ran 10 tests, the partition predicted 14",
                          "union 10 of 14 expected — 4 missing, 0 extra, 0 duplicated"])
        ok, lines = quick.test_verdict(1, out)
        self.assertFalse(ok)
        self.assertEqual(lines[-1], "tests FAILED (10)")

    def test_a_group_that_ran_more_tests_than_planned_fails(self):
        out = run_output("parallel-test: 3 tests in 1 suite FAILED in 0.20s across 1 process "
                         "(0.50s end to end, 0.2 cpu-s, 1.0x cores) with 0 known issues",
                         [("g0-TUIViewTests", 3, "ok")],
                         ["group g0-TUIViewTests ran 3 tests, the partition predicted 1"])
        self.assertFalse(quick.test_verdict(1, out)[0])

    def test_no_test_run_is_never_a_pass(self):
        out = run_output("parallel-test: 0 tests in 0 suites passed in 0.00s across 1 process "
                         "(0.10s end to end, 0.0 cpu-s, 0.0x cores) with 0 known issues")
        ok, lines = quick.test_verdict(0, out)
        self.assertFalse(ok)
        self.assertEqual(lines[-1], "tests FAILED (0): no test ran")
        self.assertNotIn("tests ok (0)", lines)

    def test_a_filter_matching_nothing_fails(self):
        out = "parallel-test: --filter 'NoSuchSuite' matched no tests\n"
        ok, lines = quick.test_verdict(1, out)
        self.assertFalse(ok)
        self.assertEqual(lines[-1], "tests FAILED (?)")
        self.assertIn("matched no tests", "\n".join(lines))


if __name__ == "__main__":
    unittest.main(verbosity=2)
