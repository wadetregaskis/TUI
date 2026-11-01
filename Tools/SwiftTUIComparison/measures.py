"""The measurements: how a scene is driven, and which scenes each phase runs. README.md says what each one means."""
import json
import os
import re
import subprocess
import time

from memory_guard import MemoryGuard
from pty_driver import SYNC_BEGIN, SYNC_END, App, marker, quantiles

ENTER = b'\r'
DOWN = b'\x1b[B'
WHEEL_DOWN = b'\x1b[<65;50;25M'  # SGR mouse, button 65, over the middle of the screen.
SCREEN_ROWS, SCREEN_COLS = 50, 200


def row_marker(i):
    return f'Row {i} some'


def table_marker(i):
    return f'Row {i} '


class Session:
    """What a run shares: the binaries, where results go, and what was asked for."""

    def __init__(self, bins, work_dir, alloc_dylib, out_dir, frameworks, runs=None, presses=None, only=None,
                 memory_limit_gb=8.0):
        self.bins, self.work_dir, self.alloc_dylib, self.out_dir = bins, work_dir, alloc_dylib, out_dir
        self.frameworks, self.runs, self.presses, self.only = frameworks, runs, presses, only
        self.guard = MemoryGuard(memory_limit_gb)
        os.makedirs(out_dir, exist_ok=True)
        self.results_path = os.path.join(out_dir, 'results.jsonl')

    def wants(self, scenario):
        return not self.only or scenario in self.only

    def spawn(self, framework, scenario=None, binary='bench', env=None):
        environment = dict(env or {})
        if scenario:
            environment['BENCH'] = scenario
        app = App(os.path.join(self.bins[framework], binary), self.work_dir, self.alloc_dylib, env=environment,
                  rows=SCREEN_ROWS, cols=SCREEN_COLS)
        self.guard.watch(app.pid)
        return app

    def finish(self, app):
        """Stops the program: its last counters, and why it is not to be trusted if it was killed for its memory."""
        self.guard.forget(app.pid)
        killed = self.guard.killed.get(app.pid)
        final = app.stop()
        return final, (f'killed by the memory guard at {killed / 1e9:.1f} GB' if killed else None)

    def count(self, default):
        return self.presses if self.presses else default

    def rounds(self, default):
        return range(self.runs if self.runs else default)

    def emit(self, phase, scenario, framework, run, metrics, params=None, error=None):
        record = {'phase': phase, 'scenario': scenario, 'fw': framework, 'run': run, 'params': params or {},
                  'metrics': {k: _rounded(v) for k, v in metrics.items() if v is not None},
                  'load1': round(os.getloadavg()[0], 1), 'at': time.strftime('%H:%M:%S')}
        if error:
            record['error'] = error
        with open(self.results_path, 'a') as out:
            out.write(json.dumps(record) + '\n')
        shown = ' '.join(f'{k}={record["metrics"][k]}' for k in ('lat_ms', 'allocs', 'frame_bytes', 'stripped',
                                                                 'frames_per_s', 'cpu_pct') if k in record['metrics'])
        print(f'  {phase} {scenario} {framework} {params or ""} run {run}: {shown} {error or ""}', flush=True)


def _rounded(value):
    if isinstance(value, float):
        return round(value, 3) if abs(value) < 100 else round(value)
    return value


def _peak(final):
    return final['lifetime_max_footprint'] if final else None


def press_series(session, framework, scenario, presses, key=ENTER, env=None, post=0.12, mark=marker, start=None,
                 limit=120.0):
    """N key presses, each answered by a marker: what it took to appear, and what the frame cost. What the program
    does anyway (a focus pulse) is measured first and subtracted, so the answer does not depend on its going quiet."""
    app = session.spawn(framework, scenario, env=env)
    first = app.wait_for((start or mark(0)).encode(), limit)
    if first is None:
        death = app.death()
        _, killed = session.finish(app)
        return {}, killed or death or f'no first frame in {limit:.0f} s, still alive'
    first_frame = first - app.spawned_at
    app.wait_quiet(0.5, 5)
    settled = app.rusage()
    bytes_before = app.total
    idle_from = time.perf_counter()
    app.drain(2.0)
    idle = time.perf_counter() - idle_from
    after_idle = app.rusage()
    if after_idle is None:
        _, killed = session.finish(app)
        return {}, killed or app.death() or 'gone while idle'
    cpu_rate = (after_idle['cpu_ns'] - settled['cpu_ns']) / 1e6 / idle
    allocs_rate = (after_idle['allocs'] - settled['allocs']) / idle
    bytes_rate = (app.total - bytes_before) / idle
    latencies, frame_bytes, net_bytes, allocs, cpu = [], [], [], [], []
    missed = 0
    app.keep = True
    for i in range(1, presses + 1):
        before = app.rusage()
        if before is None:
            break
        app.transcript.clear()
        pressed = time.perf_counter()
        app.write(key)
        needle = mark(i).encode()
        found = None
        while time.perf_counter() - pressed < 20.0:
            got = app.pump(0.005)
            if got == b'':
                break
            if got and needle in bytes(app.transcript[-(1 << 21):]):
                found = got[0]
                break
        if found is None:
            missed += 1
            if not app.alive:
                break
            continue
        app.drain(post)
        ended = time.perf_counter()
        after = app.rusage()
        if after is None:
            break
        transcript = bytes(app.transcript)
        took = ended - pressed
        at = transcript.find(needle)
        begin = transcript.rfind(SYNC_BEGIN, 0, at)
        end = transcript.find(SYNC_END, at)
        latencies.append((found - pressed) * 1e3)
        frame_bytes.append((end if end >= 0 else len(transcript)) - (begin if begin >= 0 else 0))
        net_bytes.append(len(transcript) - bytes_rate * took)
        allocs.append(after['allocs'] - before['allocs'] - allocs_rate * took)
        cpu.append((after['cpu_ns'] - before['cpu_ns']) / 1e6 - cpu_rate * took)
    death = app.death()
    final, killed = session.finish(app)
    error = killed or (death if death and missed else None)
    latency = quantiles(latencies)
    metrics = {'first_frame_s': first_frame, 'allocs_to_settle': settled['allocs'], 'footprint': settled['footprint'],
               'peak_footprint': _peak(final), 'missed': missed}
    if latency:
        metrics.update(lat_ms=latency['med'], lat_p95_ms=latency['p95'], frame_bytes=quantiles(frame_bytes)['med'],
                       bytes=quantiles(net_bytes)['med'], allocs=quantiles(allocs)['med'], cpu_ms=quantiles(cpu)['med'])
    return metrics, error


def notch_series(session, framework, scenario, notches, gap=0.35):
    """Wheel notches over a scroll view: bytes on the wire, and whether a scroll region carried them."""
    app = session.spawn(framework, scenario)
    app.drain(3.0)
    before = app.rusage()
    bytes_before = app.total
    idle_from = time.perf_counter()
    app.drain(2.0)
    idle = time.perf_counter() - idle_from
    after_idle = app.rusage()
    if after_idle is None:
        _, killed = session.finish(app)
        return {}, killed or app.death() or 'gone while idle'
    cpu_rate = (after_idle['cpu_ns'] - before['cpu_ns']) / 1e6 / idle
    allocs_rate = (after_idle['allocs'] - before['allocs']) / idle
    bytes_rate = (app.total - bytes_before) / idle
    app.keep = True
    first, first_frame, net_bytes, cpu, allocs, frames, regions = [], [], [], [], [], [], 0
    for _ in range(notches):
        before = app.rusage()
        if before is None:
            break
        app.transcript.clear()
        sent = time.perf_counter()
        app.write(WHEEL_DOWN)
        arrived = None
        while time.perf_counter() - sent < gap:
            got = app.pump(0.003)
            if got and arrived is None:
                arrived = got[0] - sent
        after = app.rusage()
        if arrived is None or after is None:
            continue
        took = time.perf_counter() - sent
        transcript = bytes(app.transcript)
        begin = transcript.find(SYNC_BEGIN)
        end = transcript.find(SYNC_END, begin)
        first.append(arrived * 1e3)
        first_frame.append(end - begin if begin >= 0 and end >= 0 else len(transcript))
        net_bytes.append(len(transcript) - bytes_rate * took)
        cpu.append((after['cpu_ns'] - before['cpu_ns']) / 1e6 - cpu_rate * took)
        allocs.append(after['allocs'] - before['allocs'] - allocs_rate * took)
        frames.append(transcript.count(SYNC_BEGIN))
        regions = len(re.findall(rb'\x1b\[\d+;\d+r', transcript))
    final, killed = session.finish(app)
    if not first:
        return {}, killed or 'no output to a wheel notch'
    return {'first_byte_ms': quantiles(first)['med'], 'first_frame_bytes': quantiles(first_frame)['med'],
            'bytes': quantiles(net_bytes)['med'], 'cpu_ms': quantiles(cpu)['med'], 'allocs': quantiles(allocs)['med'],
            'frames': quantiles(frames)['med'], 'scroll_ops': regions, 'peak_footprint': _peak(final)}, killed


def latency_series(session, framework, scenario, presses, env=None, gap=0.25):
    """While the program keeps itself busy (a ticker), press a key every `gap` s: time from key to marker."""
    app = session.spawn(framework, scenario, env=env)
    first = app.wait_for(marker(0).encode(), 120)
    if first is None:
        death = app.death()
        _, killed = session.finish(app)
        return {}, killed or death or 'no first frame in 120 s'
    first_frame = first - app.spawned_at
    app.drain(1.5)
    before = app.rusage()
    bytes_before = app.total
    started = time.perf_counter()
    latencies, frames, missed = [], 0, 0
    for i in range(1, presses + 1):
        needle = marker(i).encode()
        pressed = time.perf_counter()
        app.write(ENTER)
        window, found = b'', None
        while time.perf_counter() - pressed < 6.0:
            got = app.pump(0.01)
            if got == b'':
                break
            if not got:
                continue
            window = (window + got[1])[-(1 << 20):]
            frames += got[1].count(SYNC_BEGIN)
            if needle in window:
                found = got[0]
                break
        if found is None:
            missed += 1
        else:
            latencies.append((found - pressed) * 1e3)
        # Drain to the next press, so a backlog is not taken for the latency of the next one.
        end = time.perf_counter() + gap
        while time.perf_counter() < end:
            got = app.pump(0.01)
            if got:
                frames += got[1].count(SYNC_BEGIN)
    ended = time.perf_counter()
    after = app.rusage()
    took = ended - started
    bytes_written = app.total - bytes_before
    final, killed = session.finish(app)
    latency = quantiles(latencies) or {}
    return {'lat_ms': latency.get('med'), 'lat_p95_ms': latency.get('p95'), 'lat_max_ms': latency.get('max'),
            'cpu_share': (after['cpu_ns'] - before['cpu_ns']) / 1e9 / took if after else None,
            'frames_per_s': frames / took, 'bytes_per_s': bytes_written / took,
            'allocs_per_s': (after['allocs'] - before['allocs']) / took if after else None,
            'first_frame_s': first_frame, 'peak_footprint': _peak(final), 'missed': missed}, killed


def stream_series(session, framework, scenario, seconds=8.0, env=None):
    """Nothing but the program animating itself. A frame is a synchronized-output block."""
    app = session.spawn(framework, scenario, env=env)
    app.drain(2.0)
    before = app.rusage()
    bytes_before = app.total
    started = time.perf_counter()
    frames = 0
    while time.perf_counter() - started < seconds:
        got = app.pump(0.01)
        if got:
            frames += got[1].count(SYNC_BEGIN)
    took = time.perf_counter() - started
    after = app.rusage()
    bytes_written = app.total - bytes_before
    final, killed = session.finish(app)
    if after is None:
        return {}, killed or 'gone while animating'
    return {'frames_per_s': frames / took, 'bytes_per_s': bytes_written / took,
            'cpu_share': (after['cpu_ns'] - before['cpu_ns']) / 1e9 / took,
            'allocs_per_s': (after['allocs'] - before['allocs']) / took, 'peak_footprint': _peak(final)}, killed


def idle_series(session, framework, binary, scenario, env, seconds=20.0):
    """A program with nothing to do: what it spends staying alive."""
    app = session.spawn(framework, scenario, binary=binary, env=env)
    app.drain(4.0)
    before = app.rusage()
    bytes_before = app.total
    started = time.perf_counter()
    app.drain(seconds)
    took = time.perf_counter() - started
    after = app.rusage()
    bytes_written = app.total - bytes_before
    final, killed = session.finish(app)
    if after is None:
        return {}, killed or 'gone while idle'
    wakeups = (after['pkg_idle_wkups'] + after['interrupt_wkups']) - (before['pkg_idle_wkups'] + before['interrupt_wkups'])
    return {'cpu_pct': 100 * (after['cpu_ns'] - before['cpu_ns']) / 1e9 / took, 'wakeups_per_s': wakeups / took,
            'allocs_per_s': (after['allocs'] - before['allocs']) / took, 'bytes_per_s': bytes_written / took,
            'footprint': after['footprint'], 'peak_footprint': _peak(final)}, killed


def memory_series(session, framework, binary, scenario, env, needle, limit=120.0):
    """What the program holds once its first frame has settled."""
    app = session.spawn(framework, scenario, binary=binary, env=env)
    first = app.wait_for(needle.encode(), limit)
    if first is None:
        app.drain(0.1)
    else:
        app.wait_quiet(0.5, 5)
    settled = app.rusage()
    death = app.death() if settled is None else None
    _, killed = session.finish(app)
    if settled is None:
        return {}, killed or death or 'gone'
    return {'first_frame_s': first - app.spawned_at if first is not None else None, 'footprint': settled['footprint'],
            'peak_footprint': settled['lifetime_max_footprint'], 'allocs_to_settle': settled['allocs']}, killed


def _press_phase(session, phase, scenarios, runs, presses, **kw):
    for run in session.rounds(runs):
        for framework in session.frameworks:
            for scenario in scenarios:
                if session.wants(scenario):
                    metrics, error = press_series(session, framework, scenario, session.count(presses), **kw)
                    session.emit(phase, scenario, framework, run, metrics, error=error)


def phase_tree(session):
    """One thing changes in a grid of 1,920 cells, built with ForEach."""
    _press_phase(session, 'tree', ['tree-leaf', 'tree-obs', 'tree-root', 'tree-all'], 3, 40)


def phase_scale(session):
    """How those costs, and a list's, grow."""
    for run in session.rounds(2):
        for framework in session.frameworks:
            for rows, columns in [(5, 8), (10, 20), (24, 40), (48, 40)]:
                for scenario in ['tree-leaf', 'tree-root']:
                    if session.wants(scenario):
                        metrics, error = press_series(session, framework, scenario, session.count(20),
                                                      env={'BENCH_R': str(rows), 'BENCH_C': str(columns)})
                        session.emit('scale', scenario, framework, run, metrics, {'cells': rows * columns}, error)
            for count in [100, 1000, 10000, 100000]:
                for scenario, mark in [('list-data', row_marker), ('table', table_marker)]:
                    # Past these sizes SwiftTUI's unbounded collections take minutes and many GB a run (2026-11).
                    if framework == 'swifttui' and (count > 10000 or (scenario == 'table' and count > 1000)):
                        continue
                    if session.wants(scenario):
                        metrics, error = press_series(session, framework, scenario, session.count(10), key=DOWN,
                                                      mark=mark, start=marker(0), env={'BENCH_N': str(count)})
                        session.emit('scale', scenario, framework, run, metrics, {'rows': count}, error)


def phase_fan(session):
    """A static tree with no ForEach: what a frame does to plain views, with no row memo in the way."""
    for run in session.rounds(3):
        for depth in [3, 4, 5]:
            for framework in session.frameworks:
                if session.wants('fan-leaf'):
                    metrics, error = press_series(session, framework, 'fan-leaf', session.count(15),
                                                  env={'BENCH_D': str(depth)}, limit=90.0)
                    session.emit('fan', 'fan-leaf', framework, run, metrics, {'leaves': 4 ** depth}, error)


def phase_siblings(session):
    """A retained graph's own case: siblings with slow bodies whose inputs never change."""
    _press_phase(session, 'siblings', ['slow-sibling', 'slow-sibling-parent'], 3, 10)


def phase_lists(session):
    """10,000 rows with no stated height, as SwiftUI code reads; the case that reached 25 GB."""
    for run in session.rounds(3):
        for framework in session.frameworks:
            for scenario, mark in [('list-data', row_marker), ('list', row_marker), ('table', table_marker)]:
                if session.wants(scenario):
                    metrics, error = press_series(session, framework, scenario, session.count(40), key=DOWN, mark=mark,
                                                  start=marker(0))
                    session.emit('lists', scenario, framework, run, metrics, error=error)


def phase_lists_framed(session):
    """The same with a stated height, at three sizes."""
    for run in session.rounds(3):
        for framework in session.frameworks:
            for count in [1000, 10000, 100000]:
                for scenario, mark in [('list-framed', row_marker), ('table-framed', table_marker)]:
                    if session.wants(scenario):
                        metrics, error = press_series(session, framework, scenario, session.count(15), key=DOWN,
                                                      mark=mark, start=marker(0), env={'BENCH_N': str(count)})
                        session.emit('lists-framed', scenario, framework, run, metrics, {'rows': count}, error)


def phase_scroll(session):
    """Wheel notches over a lazy stack: rows that look alike, and rows that share nothing."""
    for run in session.rounds(3):
        for framework in session.frameworks:
            for scenario in ['scroll', 'scroll-varied']:
                if session.wants(scenario):
                    metrics, error = notch_series(session, framework, scenario, session.count(25))
                    session.emit('scroll', scenario, framework, run, metrics, error=error)


def phase_latency(session):
    """Key to frame while busy. SwiftTUI's render mode is its own switch, so async against sync is its off-main tail."""
    for run in session.rounds(3):
        for scenario in ['lat-slowbody', 'lat-heavy', 'lat-blend']:
            if not session.wants(scenario):
                continue
            for framework, mode in [('tui', None), ('swifttui', 'async'), ('swifttui', 'sync')]:
                if framework not in session.frameworks:
                    continue
                env = {'SWIFTTUI_RENDER_MODE': mode} if mode else {}
                metrics, error = latency_series(session, framework, scenario, session.count(30), env=env)
                session.emit('latency', scenario, framework, run, metrics, {'mode': mode} if mode else None, error)


def phase_deep(session):
    """How deep a VStack nesting goes before it stops working, and how it stops. Each ladder ends at its first failure."""
    ladders = [('tui', None), ('swifttui', None), ('swifttui', 'sync')]
    for framework, mode in ladders:
        if framework not in session.frameworks:
            continue
        for scenario in ['deep-plain', 'deep']:
            if not session.wants(scenario):
                continue
            for depth in [25, 50, 100, 200, 400, 800, 1600, 3200]:
                failed = False
                for run in session.rounds(2):
                    env = {'BENCH_D': str(depth)}
                    if mode:
                        env['SWIFTTUI_RENDER_MODE'] = mode
                    metrics, error = press_series(session, framework, scenario, session.count(10), env=env, limit=60.0)
                    params = {'depth': depth}
                    if mode:
                        params['mode'] = mode
                    session.emit('deep', scenario, framework, run, metrics, params, error)
                    failed = failed or bool(error) or 'lat_ms' not in metrics
                if failed:
                    break


def phase_anim(session):
    """A whole screen of cells animating."""
    for run in session.rounds(3):
        for framework in session.frameworks:
            for scenario in ['anim-opacity', 'anim-move', 'anim-tick']:
                if session.wants(scenario):
                    metrics, error = stream_series(session, framework, scenario)
                    session.emit('anim', scenario, framework, run, metrics, error=error)


def phase_idle(session):
    """Nothing happening. TUI's focus pulse and SwiftTUI's attach poll show here."""
    cases = [('hello', 'hello', None, {}), ('counter', 'counter', None, {}), ('big-tree', 'bench', 'tree-leaf', {})]
    extras = {'swifttui': ('counter-companion', 'counter', None, {'SWIFTTUI_COMPANION': None}),
              'tui': ('counter-reduce-motion', 'counter', None, {'TUI_REDUCE_MOTION': '1'})}
    for run in session.rounds(3):
        for framework in session.frameworks:
            for label, binary, scenario, env in cases + [extras[framework]]:
                if session.wants(label):
                    metrics, error = idle_series(session, framework, binary, scenario, env)
                    session.emit('idle', label, framework, run, metrics, error=error)


def phase_memory(session):
    """What a program holds once settled."""
    cases = [('hello', 'hello', None, {}, 'Hello'), ('big-tree', 'bench', 'tree-leaf', {}, marker(0)),
             ('list-10k', 'bench', 'list', {}, marker(0)), ('list-100k', 'bench', 'list', {'BENCH_N': '100000'}, marker(0)),
             ('table-10k', 'bench', 'table', {}, marker(0))]
    for run in session.rounds(3):
        for framework in session.frameworks:
            for label, binary, scenario, env, needle in cases:
                if session.wants(label):
                    metrics, error = memory_series(session, framework, binary, scenario, env, needle)
                    session.emit('memory', label, framework, run, metrics, error=error)


def phase_frame_trace(session):
    """SwiftTUI's own trace: how many frames it committed, cancelled and dropped under load."""
    if 'swifttui' not in session.frameworks:
        return
    for run in session.rounds(1):
        for scenario in ['lat-blend', 'lat-heavy']:
            if not session.wants(scenario):
                continue
            for mode in ['async', 'async-no-drop', 'async-no-cancel', 'sync']:
                trace = os.path.join(session.work_dir, f'trace-{scenario}-{mode}.tsv')
                if os.path.exists(trace):
                    os.unlink(trace)
                env = {'SWIFTTUI_FRAME_TRACE': trace, 'SWIFTTUI_RENDER_MODE': mode}
                metrics, error = latency_series(session, 'swifttui', scenario, session.count(10), env=env)
                metrics = {'lat_ms': metrics.get('lat_ms'), **_trace_counts(trace)}
                session.emit('frame-trace', scenario, 'swifttui', run, metrics, {'mode': mode}, error)


def _trace_counts(path):
    if not os.path.exists(path):
        return {}
    with open(path) as lines:
        rows = [line.rstrip('\n').split('\t') for line in lines]
    os.unlink(path)
    if not rows or 'tail' not in rows[0] or 'kind' not in rows[0]:
        return {}
    tail, kind = rows[0].index('tail'), rows[0].index('kind')
    data = [row for row in rows[1:] if len(row) > max(tail, kind)]
    # A frame with no artifacts that was not cancelled before its tail started is one dropped after finishing it.
    return {'frames_committed': sum(row[kind] == 'COMMIT' for row in data),
            'frames_cancelled': sum(row[tail].startswith('cancelled') for row in data),
            'frames_dropped': sum(row[kind] == 'ZEROART' and not row[tail].startswith('cancelled') for row in data)}


def stripped_size(path, work_dir):
    """Bytes of a binary as built and after `strip`, and of its code."""
    copy = os.path.join(work_dir, 'stripped-copy')
    subprocess.run(['strip', '-o', copy, path], check=False, stderr=subprocess.DEVNULL)
    listing = subprocess.run(['size', '-m', copy], capture_output=True, text=True).stdout
    code = next((int(line.split()[2]) for line in listing.split('\n') if line.startswith('\tSection __text')), None)
    sizes = {'unstripped': os.path.getsize(path), 'stripped': os.path.getsize(copy), 'text': code}
    os.unlink(copy)
    return sizes


PHASES = {'tree': phase_tree, 'scale': phase_scale, 'fan': phase_fan, 'siblings': phase_siblings, 'lists': phase_lists,
          'lists-framed': phase_lists_framed, 'scroll': phase_scroll, 'latency': phase_latency, 'deep': phase_deep,
          'anim': phase_anim, 'idle': phase_idle, 'memory': phase_memory, 'frame-trace': phase_frame_trace}
