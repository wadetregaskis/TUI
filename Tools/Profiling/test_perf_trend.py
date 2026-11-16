#!/usr/bin/env python3
"""
Tests for `perf_trend.py`.

    python3 Tools/Profiling/test_perf_trend.py

They read `ab_bench.py` output written out below and a CSV in a temporary
folder, so they need no build and run nothing.
"""

import contextlib
import io
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import perf_trend  # noqa: E402

# What `ab_bench.py OLD NEW --cases timed` prints, as it prints it: a scenario
# id longer than its 16-column field, a row with RAM, one with the row work
# that moved, and one without either.
AB_BENCH_OUTPUT = """\
  skipped (not in both binaries): session/case:outline-rows

load 2.41 · busiest: 31.0% Safari; 4.2% WindowServer
metric=cpu-per-frame  reps=10  target=4.5s/run  order randomised per rep

scenario           iters     old µs     new µs   change           95% CI  verdict
-------------------------------------------------------------------------------
session/case:list-wheel    9338      481.9      476.0    -1.2%     -2.0%   -0.3%  faster  ram 21.3->21.4MB +0.1
session/case:table-fit-tail    1022     4402.6     4404.1    +0.0%     -0.6%   +0.7%  indistinguishable  ram 30.0->30.0MB +0.0  rows 62/36->61/37 composed/served  cells 195->195
fanout               349     4724.5     4463.0    -5.7%     -6.7%   -2.2%  faster
"""


def reading(scenario, median, low="-1.0", high="+1.0", sha="a", metric="cpu", date="2026-11-16T10:00"):
    """One CSV row, as an append writes it."""
    return {"date": date, "sha": sha, "host": "box", "load": "1.00", "metric": metric,
            "scenario": scenario, "iterations": "1000", "median_us": str(median),
            "ci_low_pct": low, "ci_high_pct": high, "rss_mb": "20.0"}


class ParseTests(unittest.TestCase):
    def test_every_result_row_is_read_and_nothing_else(self):
        load, metric, rows = perf_trend.parse_ab_bench(AB_BENCH_OUTPUT)
        self.assertEqual(load, "2.41")
        self.assertEqual(metric, "cpu")
        self.assertEqual([row["scenario"] for row in rows],
                         ["session/case:list-wheel", "session/case:table-fit-tail", "fanout"])

    def test_a_row_keeps_the_new_binarys_median_interval_and_rss(self):
        _, _, rows = perf_trend.parse_ab_bench(AB_BENCH_OUTPUT)
        self.assertEqual(rows[0], {"scenario": "session/case:list-wheel", "iterations": "9338",
                                   "median_us": "476.0", "ci_low_pct": "-2.0", "ci_high_pct": "-0.3",
                                   "rss_mb": "21.4"})
        # A row with no RAM reading keeps the column, empty.
        self.assertEqual(rows[2]["rss_mb"], "")

    def test_a_cold_run_is_its_own_metric(self):
        text = AB_BENCH_OUTPUT.replace("order randomised per rep", "order randomised per rep  COLD (cache reset every frame)")
        self.assertEqual(perf_trend.parse_ab_bench(text)[1], "cpu-cold")

    def test_a_fallback_to_the_wall_clock_is_recorded_as_wall(self):
        text = AB_BENCH_OUTPUT.replace(
            "\nscenario", "\n  /tmp/old predates cpu-per-frame — falling back to wall clock, which is "
            "preemption-sensitive; expect wider intervals.\n\nscenario")
        self.assertEqual(perf_trend.parse_ab_bench(text)[1], "wall")

    def test_output_with_no_results_has_no_rows(self):
        self.assertEqual(perf_trend.parse_ab_bench("load 1.00 · busiest: n/a\n")[2], [])


class CSVPathTests(unittest.TestCase):
    def test_csv_wins_then_the_environment(self):
        self.assertEqual(perf_trend.csv_path("given.csv", {perf_trend.ENVIRONMENT_VARIABLE: "env.csv"}),
                         "given.csv")
        self.assertEqual(perf_trend.csv_path(None, {perf_trend.ENVIRONMENT_VARIABLE: "env.csv"}), "env.csv")

    def test_the_default_only_where_its_folder_exists(self):
        with tempfile.TemporaryDirectory() as folder:
            there = os.path.join(folder, "trend.csv")
            self.assertEqual(perf_trend.csv_path(None, {}, default=there), there)
            missing = os.path.join(folder, "absent", "trend.csv")
            self.assertIsNone(perf_trend.csv_path(None, {}, default=missing))


class AppendTests(unittest.TestCase):
    def test_the_header_is_written_once_and_a_log_appended_twice_adds_nothing(self):
        with tempfile.TemporaryDirectory() as folder:
            path = os.path.join(folder, "trend.csv")
            rows = [reading("fanout", 100), reading("deep", 200)]
            self.assertEqual(len(perf_trend.append(path, rows)), 2)
            self.assertEqual(perf_trend.append(path, rows), [])
            self.assertEqual(len(perf_trend.append(path, [reading("fanout", 100, sha="b")])), 1)
            with open(path, encoding="utf-8") as file:
                text = file.read()
            self.assertEqual(text.count("date,sha,"), 1)
            self.assertEqual([row["sha"] for row in perf_trend.read_rows(path)], ["a", "a", "b"])

    def test_main_appends_a_saved_log_with_its_stamp(self):
        with tempfile.TemporaryDirectory() as folder:
            log, path = os.path.join(folder, "ab.log"), os.path.join(folder, "trend.csv")
            with open(log, "w", encoding="utf-8") as file:
                file.write(AB_BENCH_OUTPUT)
            with contextlib.redirect_stdout(io.StringIO()) as printed:
                self.assertEqual(perf_trend.main([log, "--csv", path, "--sha", "abc123", "--host", "box"]), 0)
            self.assertIn("appended 3 rows", printed.getvalue())
            rows = perf_trend.read_rows(path)
            self.assertEqual(len(rows), 3)
            self.assertEqual({(row["sha"], row["host"], row["load"], row["metric"]) for row in rows},
                             {("abc123", "box", "2.41", "cpu")})

    def test_main_writes_nothing_without_a_csv(self):
        saved = perf_trend.DEFAULT_CSV, os.environ.pop(perf_trend.ENVIRONMENT_VARIABLE, None)
        try:
            with tempfile.TemporaryDirectory() as folder:
                perf_trend.DEFAULT_CSV = os.path.join(folder, "absent", "trend.csv")
                with contextlib.redirect_stdout(io.StringIO()) as printed:
                    self.assertEqual(perf_trend.main(["ab.log", "--sha", "a"]), 2)
                self.assertIn("nothing was written", printed.getvalue())
                self.assertFalse(os.path.exists(perf_trend.DEFAULT_CSV))
        finally:
            perf_trend.DEFAULT_CSV = saved[0]
            if saved[1] is not None:
                os.environ[perf_trend.ENVIRONMENT_VARIABLE] = saved[1]


class ReportTests(unittest.TestCase):
    def test_the_last_rows_and_the_change_from_the_first_of_them(self):
        rows = [reading("fanout", median, sha=sha) for median, sha in
                [(500, "old"), (100, "a"), (102, "b"), (110, "c")]]
        lines = perf_trend.report(rows, last=3)
        self.assertEqual(lines[0], "fanout  (cpu)")
        self.assertEqual([line.split()[1] for line in lines[1:4]], ["a", "b", "c"])
        self.assertIn("change from the first: +10.0%", lines[4])
        self.assertIn("beyond its widest interval, ±1.0%", lines[4])

    def test_a_change_inside_the_noise_says_so(self):
        rows = [reading("deep", 100, low="-3.0", high="+3.0"), reading("deep", 102)]
        self.assertIn("+2.0%  (within its widest interval, ±3.0%)", perf_trend.report(rows)[-1])

    def test_metrics_and_scenarios_are_kept_apart(self):
        rows = [reading("deep", 100), reading("deep", 300, metric="cpu-cold"), reading("fanout", 50)]
        lines = perf_trend.report(rows)
        self.assertEqual([line for line in lines if not line.startswith(" ")],
                         ["deep  (cpu)", "deep  (cpu-cold)", "fanout  (cpu)"])
        self.assertEqual(lines.count("  one reading: no change yet"), 3)


if __name__ == "__main__":
    unittest.main()
