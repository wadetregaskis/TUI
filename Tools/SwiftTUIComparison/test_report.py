"""Tests for the part that needs no macOS: `python3 -m unittest discover -s Tools/SwiftTUIComparison`."""
import json
import os
import tempfile
import unittest

import report


def record(phase, scenario, framework, run, metrics, params=None, error=None):
    entry = {'phase': phase, 'scenario': scenario, 'fw': framework, 'run': run, 'params': params or {},
             'metrics': metrics, 'load1': 5.0}
    if error:
        entry['error'] = error
    return entry


class SummaryTests(unittest.TestCase):
    def test_median_and_range_across_runs(self):
        scenes = report.summarise([record('tree', 'tree-leaf', 'tui', run, {'lat_ms': value, 'allocs': 642})
                                   for run, value in enumerate([3.0, 1.0, 2.0])])
        entry = scenes['tree / tree-leaf']['tui']
        self.assertEqual(entry['runs'], 3)
        self.assertEqual(entry['metrics']['lat_ms'], [2.0, 1.0, 3.0])
        self.assertEqual(entry['metrics']['allocs'], [642, 642, 642])

    def test_parameters_make_separate_scenes(self):
        scenes = report.summarise([record('scale', 'table', 'tui', 0, {'lat_ms': 1.0}, {'rows': 100}),
                                   record('scale', 'table', 'tui', 0, {'lat_ms': 2.0}, {'rows': 1000})])
        self.assertEqual(set(scenes), {'scale / table rows=100', 'scale / table rows=1000'})

    def test_errors_survive(self):
        scenes = report.summarise([record('deep', 'deep', 'swifttui', 0, {}, {'depth': 100}, 'died, signal 4')])
        self.assertEqual(scenes['deep / deep depth=100']['swifttui']['errors'], ['died, signal 4'])

    def test_write_and_load_a_summary(self):
        with tempfile.TemporaryDirectory() as directory:
            with open(os.path.join(directory, 'results.jsonl'), 'w') as out:
                out.write(json.dumps(record('tree', 'tree-leaf', 'tui', 0, {'allocs': 642})) + '\n')
            report.write_summary(directory, {'tui_commit': 'abc'})
            self.assertEqual(report.load_summary(directory)['meta']['tui_commit'], 'abc')


class OutputTests(unittest.TestCase):
    def summary(self, allocs):
        return {'meta': {}, 'scenes': report.summarise([record('tree', 'tree-leaf', 'tui', 0, {'allocs': allocs, 'lat_ms': 2.0})])}

    def test_compare_prints_the_ratio_and_marks_what_repeats(self):
        lines = []
        report.compare(self.summary(1000), self.summary(500), write=lines.append)
        row = next(line for line in lines if 'allocs' in line)
        self.assertIn('allocs *', row)
        self.assertIn('0.50', row)

    def test_compare_counts_what_only_one_side_has(self):
        lines = []
        old = {'meta': {}, 'scenes': {}}
        report.compare(old, self.summary(1), write=lines.append)
        self.assertIn('Not compared: 1 only in new.', lines)

    def test_tables_show_a_range_only_where_runs_differ(self):
        lines = []
        report.tables({'meta': {}, 'scenes': report.summarise([
            record('tree', 'tree-leaf', 'tui', 0, {'lat_ms': 1.0, 'allocs': 642}),
            record('tree', 'tree-leaf', 'tui', 1, {'lat_ms': 3.0, 'allocs': 650})])}, write=lines.append)
        row = next(line for line in lines if 'tree-leaf' in line)
        self.assertIn('2 [1 to 3]', row)
        self.assertIn('646', row)


if __name__ == '__main__':
    unittest.main()
