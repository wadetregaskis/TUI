#!/usr/bin/env python3
"""Measures TUI against SwiftTUI at chosen commits. See README.md.

  comparison.py run --out DIR [--tui-commit C] [--swifttui-commit C] [--scratch DIR] [--phases a,b] [--only x,y] ...
  comparison.py table DIR
  comparison.py compare OLD NEW [--framework tui]
  comparison.py census [--sources DIR]
  comparison.py strict-safety --out DIR [--tui-commit C] [--scratch DIR]
"""
import argparse
import os
import platform
import subprocess
import sys
import tempfile
import time

import report

HERE = os.path.dirname(os.path.abspath(__file__))
BASELINE = os.path.join(HERE, 'baseline', 'summary.json')
SIZE = 'size'


def default_scratch():
    return os.path.join(tempfile.gettempdir(), 'tui-swifttui-comparison')


def _machine():
    def sysctl(name):
        return subprocess.run(['sysctl', '-n', name], capture_output=True, text=True).stdout.strip()
    model = sysctl('machdep.cpu.brand_string') or platform.machine()
    memory = int(sysctl('hw.memsize') or 0) / 2**30
    vm = ', a VM' if sysctl('kern.hv_vmm_present') == '1' else ''
    return f"{model}, {sysctl('hw.ncpu')} cores, {memory:.0f} GB, macOS {platform.mac_ver()[0]}{vm}"


def _needed_binaries(phases, session_only):
    """Which products the phases read, so a small run does not link everything."""
    needed = set()
    if set(phases) - {SIZE}:
        needed.add('bench')
    if 'idle' in phases:
        needed.update(['hello', 'counter'])
    if 'memory' in phases:
        needed.add('hello')
    return needed


def _measure_sizes(session, roots, toolchain, args, build, measures):
    for run in [0]:
        for framework in session.frameworks:
            for app, variant, binary in build.SIZE_APPS[framework]:
                if session.wants(app):
                    sizes = measures.stripped_size(os.path.join(session.bins[framework], binary), session.work_dir)
                    session.emit('size', app, framework, run, sizes, {'build': variant})
    if args.dedup:
        for framework in session.frameworks:
            for app, variant, binary in build.SIZE_APPS[framework]:
                if session.wants(app):
                    build.build(toolchain, os.path.join(roots[framework], 'apps'), os.path.join(roots[framework], 'build'),
                                os.path.join(args.out, 'build.log'), products=[binary],
                                extra=['-Xlinker', '-deduplicate'])
                    sizes = measures.stripped_size(os.path.join(session.bins[framework], binary), session.work_dir)
                    session.emit('size', app, framework, 0, sizes, {'build': variant, 'linker': 'deduplicate'})
    if args.large:
        for framework, found in build.large_apps(roots, args.scratch, toolchain, os.path.join(args.out, 'build.log')).items():
            for label, path in found:
                session.emit('size', label, framework, 0, measures.stripped_size(path, session.work_dir))


def command_run(args):
    if sys.platform != 'darwin':
        raise SystemExit('The measurements read macOS process counters, and load a library with DYLD_INSERT_LIBRARIES: '
                         'macOS only. `table`, `compare` and `census` work anywhere.')
    import build
    import measures
    phases = args.phases.split(',') if args.phases else list(measures.PHASES) + [SIZE]
    unknown = [phase for phase in phases if phase != SIZE and phase not in measures.PHASES]
    if unknown:
        raise SystemExit(f'Unknown phase {", ".join(unknown)}. There are: {", ".join(measures.PHASES)}, {SIZE}.')
    # The size phase goes last, because its --dedup relinks the small apps.
    phases = [phase for phase in phases if phase != SIZE] + ([SIZE] if SIZE in phases else [])
    frameworks = args.frameworks.split(',')
    args.scratch = os.path.abspath(args.scratch)
    args.out = os.path.abspath(args.out)
    os.makedirs(args.scratch, exist_ok=True)
    os.makedirs(args.out, exist_ok=True)
    toolchain = build.Toolchain(args.toolchain)
    log = os.path.join(args.out, 'build.log')
    print(f"Build slots: {build.find_slot() or 'none here, so builds just run'}", flush=True)
    roots, commits = {}, {}
    if 'tui' in frameworks:
        roots['tui'], commits['tui'] = build.tui_source(args.tui_commit, args.scratch)
    if 'swifttui' in frameworks:
        print(f'Fetching SwiftTUI {args.swifttui_commit[:12]}', flush=True)
        roots['swifttui'], commits['swifttui'] = build.swifttui_source(args.swifttui_commit, args.scratch)
    alloc = build.build_alloc_counter(args.scratch)
    needed = _needed_binaries(phases, args.only)
    bins = {}
    session = measures.Session(bins, args.scratch, alloc, args.out, frameworks, runs=args.runs, presses=args.presses,
                               only=set(args.only.split(',')) if args.only else None,
                               memory_limit_gb=args.memory_limit_gb)
    for framework in frameworks:
        apps = build.write_apps(framework, roots[framework])
        output = os.path.join(roots[framework], 'build')
        clean = not os.path.exists(os.path.join(output, 'release'))
        print(f'Building {framework} ({"clean" if clean else "incremental"}) under {output}', flush=True)
        if SIZE in phases:
            # Timed in two parts when clean: the narrowest app first, then everything else.
            smallest = 'hello_sel' if framework == 'tui' else 'hello_cli'
            wall, cpu = build.build(toolchain, apps, output, log, products=[smallest])
            if clean:
                session.emit('build', 'narrowest-app-clean', framework, 0, {'wall_s': wall, 'cpu_s': cpu})
            wall, cpu = build.build(toolchain, apps, output, log)
            if clean:
                session.emit('build', 'all-the-rest', framework, 0, {'wall_s': wall, 'cpu_s': cpu})
        else:
            wall, cpu = build.build(toolchain, apps, output, log, products=sorted(needed))
            if clean:
                session.emit('build', 'the-apps-this-run-needs', framework, 0, {'wall_s': wall, 'cpu_s': cpu})
        bins[framework] = os.path.join(output, 'release')
    meta = {'tui_commit': commits.get('tui', ''), 'swifttui_commit': commits.get('swifttui', ''),
            'swift': toolchain.describe(), 'machine': _machine(), 'date': time.strftime('%Y-%m-%d %H:%M %z'),
            'load_start': round(os.getloadavg()[0], 1), 'phases': phases, 'only': args.only or '',
            'runs': args.runs, 'presses': args.presses, 'memory_limit_gb': args.memory_limit_gb,
            'instruction_counts': 'proc_pid_rusage returned 0 on this VM when tried, so none are recorded'}
    print(f"{meta['swift']}; {meta['machine']}", flush=True)
    for phase in phases:
        print(f'{phase} {time.strftime("%H:%M:%S")} load {os.getloadavg()[0]:.1f}', flush=True)
        if phase == SIZE:
            _measure_sizes(session, roots, toolchain, args, build, measures)
        else:
            measures.PHASES[phase](session)
    meta['load_end'] = round(os.getloadavg()[0], 1)
    summary = report.write_summary(args.out, meta)
    print()
    report.tables(summary)
    print(f'\nResults: {args.out}. Against the committed baseline: {sys.argv[0]} compare {BASELINE} {args.out}')


def command_table(args):
    report.tables(report.load_summary(args.directory))


def command_compare(args):
    report.compare(report.load_summary(args.old), report.load_summary(args.new), framework=args.framework)


def command_census(args):
    import census
    census.main(args.sources, args.list)


def command_strict_safety(args):
    import build
    import strict_safety
    args.scratch = os.path.abspath(args.scratch)
    args.out = os.path.abspath(args.out)
    os.makedirs(args.out, exist_ok=True)
    toolchain = build.Toolchain(args.toolchain)
    root, sha = build.tui_source(args.tui_commit, args.scratch)
    apps = build.write_apps('tui', root)
    output = os.path.join(root, 'build')
    # The modules the type-check imports: every app, so that every module the apps reach exists.
    build.build(toolchain, apps, output, os.path.join(args.out, 'build.log'), products=['bench'])
    print(f'TUI {sha[:12]}, {toolchain.describe()}')
    strict_safety.run(os.path.join(root, 'tui'), os.path.join(output, 'release'), args.out, args.toolchain, build)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest='command', required=True)

    run = commands.add_parser('run', help='build both frameworks and measure them')
    run.add_argument('--out', required=True, help='directory for results.jsonl, summary.json and build.log')
    run.add_argument('--tui-commit', default='HEAD', help='any commit of this repository (default HEAD)')
    run.add_argument('--swifttui-commit', default=None, help='a commit of SwiftTUI/swift-tui (default the pinned one)')
    run.add_argument('--scratch', default=default_scratch(), help=f'sources and builds, outside the repo (default {default_scratch()})')
    run.add_argument('--frameworks', default='tui,swifttui', help='tui, swifttui or both')
    run.add_argument('--phases', help='comma-separated (default all)')
    run.add_argument('--only', help='comma-separated scene names within the phases')
    run.add_argument('--runs', type=int, help='process runs per scene (default per phase, mostly 3)')
    run.add_argument('--presses', type=int, help='inputs per run (default per phase, 10 to 40)')
    run.add_argument('--toolchain', default=None, help="swiftly version, or 'system' for the swift on PATH")
    run.add_argument('--memory-limit-gb', type=float, default=8.0, help='kill a measured program past this footprint; 0 for no limit')
    run.add_argument('--dedup', action='store_true', help='in the size phase, also relink with -Xlinker -deduplicate')
    run.add_argument('--large', action='store_true', help="in the size phase, also build each framework's large example")
    run.set_defaults(handler=command_run)

    table = commands.add_parser('table', help='print the tables of a finished run')
    table.add_argument('directory')
    table.set_defaults(handler=command_table)

    compared = commands.add_parser('compare', help='old against new, per scene')
    compared.add_argument('old', help=f'a results directory or summary file, such as {os.path.relpath(BASELINE, os.getcwd())}')
    compared.add_argument('new')
    compared.add_argument('--framework', choices=['tui', 'swifttui'])
    compared.set_defaults(handler=command_compare)

    counted = commands.add_parser('census', help='count @unchecked Sendable and nonisolated(unsafe) by reason')
    counted.add_argument('--sources', default=os.path.normpath(os.path.join(HERE, '..', '..', 'Sources')))
    counted.add_argument('--list', action='store_true', help='list every site under its class')
    counted.set_defaults(handler=command_census)

    strict = commands.add_parser('strict-safety', help='type-check every TUI module with -strict-memory-safety')
    strict.add_argument('--out', required=True)
    strict.add_argument('--tui-commit', default='HEAD')
    strict.add_argument('--scratch', default=default_scratch())
    strict.add_argument('--toolchain', default=None)
    strict.set_defaults(handler=command_strict_safety)

    args = parser.parse_args()
    if args.command in ('run', 'strict-safety'):
        import build
        args.toolchain = args.toolchain or build.DEFAULT_TOOLCHAIN
        if args.command == 'run':
            args.swifttui_commit = args.swifttui_commit or build.SWIFTTUI_PINNED
    args.handler(args)


if __name__ == '__main__':
    main()
