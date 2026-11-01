"""Turns a run's records into a summary, a table per phase, and a comparison of two summaries. Nothing here runs a
program, so it works on any machine, on results made on another."""
import json
import os
import statistics

# The measures that repeat to a fraction of a percent on a loaded machine. The rest need a quiet box.
DETERMINISTIC = {'allocs', 'allocs_to_settle', 'frame_bytes', 'first_frame_bytes', 'bytes', 'stripped', 'unstripped',
                 'text', 'scroll_ops'}

_PRESS = [('lat_ms', 'Key to frame, ms'), ('lat_p95_ms', 'p95'), ('frame_bytes', 'Frame bytes'), ('allocs', 'Allocations'),
          ('cpu_ms', 'CPU ms'), ('first_frame_s', 'First frame, s'), ('footprint', 'Footprint'), ('peak_footprint', 'Peak')]
SECTIONS = [
    ('tree', 'One change in a grid of 1,920 cells', _PRESS),
    ('scale', 'How one change grows, with cells or rows', _PRESS),
    ('fan', 'One change beside a static tree with no ForEach', _PRESS),
    ('siblings', 'One change beside slow bodies whose inputs never change', _PRESS),
    ('lists', '10,000 rows, no stated height: Down arrow', _PRESS),
    ('lists-framed', 'Rows with a stated height: Down arrow', _PRESS),
    ('scroll', 'A wheel notch over a lazy stack',
     [('first_byte_ms', 'First byte, ms'), ('first_frame_bytes', 'First frame, bytes'), ('bytes', 'All bytes, net'),
      ('frames', 'Frames'), ('scroll_ops', 'Scroll regions'), ('allocs', 'Allocations'), ('cpu_ms', 'CPU ms'),
      ('peak_footprint', 'Peak')]),
    ('latency', 'Key to frame while busy',
     [('lat_ms', 'Key to frame, ms'), ('lat_p95_ms', 'p95'), ('frames_per_s', 'Frames/s'), ('cpu_share', 'CPU, cores'),
      ('bytes_per_s', 'Bytes/s'), ('allocs_per_s', 'Allocations/s'), ('peak_footprint', 'Peak')]),
    ('deep', 'Deep nesting', _PRESS),
    ('anim', 'A screen of cells animating',
     [('frames_per_s', 'Frames/s'), ('bytes_per_s', 'Bytes/s'), ('cpu_share', 'CPU, cores'),
      ('allocs_per_s', 'Allocations/s'), ('peak_footprint', 'Peak')]),
    ('idle', 'Idle',
     [('cpu_pct', 'CPU, %'), ('wakeups_per_s', 'Wakeups/s'), ('allocs_per_s', 'Allocations/s'), ('bytes_per_s', 'Bytes/s'),
      ('footprint', 'Footprint'), ('peak_footprint', 'Peak')]),
    ('memory', 'Memory once settled',
     [('footprint', 'Footprint'), ('peak_footprint', 'Peak'), ('first_frame_s', 'First frame, s'),
      ('allocs_to_settle', 'Allocations to settle')]),
    ('frame-trace', 'SwiftTUI frames, from its own trace',
     [('lat_ms', 'Key to frame, ms'), ('frames_committed', 'Committed'), ('frames_cancelled', 'Cancelled'),
      ('frames_dropped', 'Dropped')]),
    ('size', 'Size, stripped',
     [('stripped', 'Stripped'), ('text', '__text'), ('unstripped', 'As built')]),
    ('build', 'Build time, one run',
     [('wall_s', 'Wall, s'), ('cpu_s', 'CPU, s')]),
]
_MEMORY_METRICS = {'footprint', 'peak_footprint', 'stripped', 'text', 'unstripped'}


def scene_key(record):
    """What makes two records the same measurement: phase, scene and parameters."""
    params = record.get('params') or {}
    extra = ' '.join(f'{k}={params[k]}' for k in sorted(params))
    return f"{record['phase']} / {record['scenario']}" + (f' {extra}' if extra else '')


def summarise(records):
    """Per scene and framework, the median of the runs' values of each metric, with the lowest and highest run."""
    groups = {}
    for record in records:
        groups.setdefault((scene_key(record), record['fw']), []).append(record)
    scenes = {}
    for (key, framework), runs in sorted(groups.items()):
        metrics = {}
        names = sorted({name for run in runs for name in run.get('metrics', {})})
        for name in names:
            values = [run['metrics'][name] for run in runs if name in run.get('metrics', {})]
            metrics[name] = [_tidy(statistics.median(values)), _tidy(min(values)), _tidy(max(values))]
        entry = {'phase': runs[0]['phase'], 'runs': len(runs), 'metrics': metrics,
                 'load1': round(statistics.median(run.get('load1', 0) for run in runs), 1)}
        errors = sorted({run['error'] for run in runs if run.get('error')})
        if errors:
            entry['errors'] = errors
        scenes.setdefault(key, {})[framework] = entry
    return scenes


def _tidy(value):
    if isinstance(value, float):
        return round(value, 3) if abs(value) < 100 else round(value)
    return value


def load_records(directory):
    with open(os.path.join(directory, 'results.jsonl')) as lines:
        return [json.loads(line) for line in lines if line.strip()]


def write_summary(directory, meta):
    summary = {'meta': meta, 'scenes': summarise(load_records(directory))}
    with open(os.path.join(directory, 'summary.json'), 'w') as out:
        out.write(_dump(summary))
    return summary


def _dump(summary):
    """One scene to a line: small, and a diff of two baselines reads by scene."""
    scenes = ',\n'.join(f'  {json.dumps(key)}: {json.dumps(summary["scenes"][key], sort_keys=True)}'
                        for key in sorted(summary['scenes'], key=_natural))
    return f'{{\n "meta": {json.dumps(summary["meta"], indent=1, sort_keys=True)},\n "scenes": {{\n{scenes}\n }}\n}}\n'


def load_summary(path):
    """A summary from its file, or from a results directory holding one."""
    if os.path.isdir(path):
        path = os.path.join(path, 'summary.json')
    with open(path) as source:
        return json.load(source)


def format_value(name, value):
    if value is None:
        return '-'
    if name in _MEMORY_METRICS:
        return f'{value / 1e9:.2f} GB' if value >= 1e9 else f'{value / 1e6:.1f} MB'
    magnitude = abs(value)
    if value == int(value):
        return f'{int(value):,}'
    if magnitude >= 100:
        return f'{value:,.0f}'
    if magnitude >= 10:
        return f'{value:.1f}'
    return f'{value:.2f}'


def _cell(name, triple):
    if triple is None:
        return '-'
    median, low, high = triple
    text = format_value(name, median)
    if low != high and name not in DETERMINISTIC and name not in _MEMORY_METRICS:
        text += f' [{format_value(name, low)} to {format_value(name, high)}]'
    return text


def _print_rows(rows, write):
    widths = [max(len(row[i]) for row in rows) for i in range(len(rows[0]))]
    for number, row in enumerate(rows):
        write('| ' + ' | '.join(cell.ljust(widths[i]) for i, cell in enumerate(row)) + ' |')
        if number == 0:
            write('|' + '|'.join('-' * (w + 2) for w in widths) + '|')


def tables(summary, write=print):
    """The tables, a phase at a time. Each cell is the median of the runs, then [lowest to highest] where they differ;
    measures that repeat, and memory, show one number."""
    meta = summary.get('meta', {})
    write(f"TUI {meta.get('tui_commit', '?')[:12]}, SwiftTUI {meta.get('swifttui_commit', '?')[:12]}, "
          f"{meta.get('swift', '?')}; {meta.get('machine', '?')}; load {meta.get('load_start', '?')} to {meta.get('load_end', '?')}")
    scenes = summary['scenes']
    for phase, title, columns in SECTIONS:
        keys = [key for key in scenes if key.split(' / ')[0] == phase]
        if not keys:
            continue
        write('')
        write(f'{phase}: {title}')
        rows = [['Scene', 'Framework', 'Runs'] + [label for _, label in columns] + ['Load']]
        for key in sorted(keys, key=_natural):
            for framework in sorted(scenes[key]):
                entry = scenes[key][framework]
                cells = [key.split(' / ', 1)[1], framework, str(entry['runs'])]
                cells += [_cell(name, entry['metrics'].get(name)) for name, _ in columns]
                rows.append(cells + [str(entry.get('load1', ''))])
                for error in entry.get('errors', []):
                    rows.append(['  ^ ' + error, '', ''] + [''] * len(columns) + [''])
        _print_rows(rows, write)


def _natural(text):
    """Sorts `depth=100` after `depth=25`."""
    parts, current, digits = [], '', False
    for character in text:
        if character.isdigit() != digits:
            parts.append(int(current) if digits and current else current)
            current, digits = '', character.isdigit()
        current += character
    parts.append(int(current) if digits and current else current)
    return [(isinstance(part, int), part) for part in parts]


def compare(old, new, framework=None, write=print):
    """Old against new per scene, for the measures in that phase's table. A `*` marks the measures that repeat, which
    are the ones to believe on a busy machine. Lower is better everywhere except frames per second."""
    oldest, newest = old.get('meta', {}), new.get('meta', {})
    write(f"Old: TUI {oldest.get('tui_commit', '?')[:12]}, SwiftTUI {oldest.get('swifttui_commit', '?')[:12]}, "
          f"{oldest.get('swift', '?')}; {oldest.get('machine', '?')}; {oldest.get('date', '?')}")
    write(f"New: TUI {newest.get('tui_commit', '?')[:12]}, SwiftTUI {newest.get('swifttui_commit', '?')[:12]}, "
          f"{newest.get('swift', '?')}; {newest.get('machine', '?')}; {newest.get('date', '?')}")
    if oldest.get('machine') != newest.get('machine') or oldest.get('swift') != newest.get('swift'):
        write('Different machine or compiler: only the allocations and bytes mean much.')
    write('* repeats on a busy machine. Timings need a quiet box; check the load columns.')
    write('')
    columns = {phase: [name for name, _ in entries] for phase, _, entries in SECTIONS}
    rows = [['Scene', 'Framework', 'Measure', 'Old', 'New', 'New / old', 'Load old, new']]
    both = sorted(set(old['scenes']) | set(new['scenes']), key=_natural)
    missing = []
    for key in both:
        frameworks = set(old['scenes'].get(key, {})) | set(new['scenes'].get(key, {}))
        for name in sorted(frameworks):
            if framework and name != framework:
                continue
            before = old['scenes'].get(key, {}).get(name)
            after = new['scenes'].get(key, {}).get(name)
            if before is None or after is None:
                missing.append((key, name, 'new' if before is None else 'old'))
                continue
            for error_side, entry in (('old', before), ('new', after)):
                for error in entry.get('errors', []):
                    rows.append([key, name, f'{error_side} error', error, '', '', ''])
            for metric in columns.get(before['phase'], []):
                a = before['metrics'].get(metric)
                b = after['metrics'].get(metric)
                if a is None or b is None:
                    continue
                ratio = f'{b[0] / a[0]:.2f}' if a[0] else '-'
                mark = ' *' if metric in DETERMINISTIC else ''
                rows.append([key, name, metric + mark, format_value(metric, a[0]), format_value(metric, b[0]), ratio,
                             f"{before.get('load1', '?')}, {after.get('load1', '?')}"])
    _print_rows(rows, write)
    if missing:
        write('')
        counts = {}
        for _, _, side in missing:
            counts[side] = counts.get(side, 0) + 1
        write('Not compared: ' + ', '.join(f'{count} only in {side}' for side, count in sorted(counts.items())) + '.')
