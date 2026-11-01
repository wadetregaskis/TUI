"""Type-checks each TUI module with -strict-memory-safety (SE-0458) and counts the diagnostics, by module, kind and
cause. Against the modules a release build has made, so nothing is compiled and nothing in the source changes."""
import collections
import os
import re
import subprocess

SKIP = {'TUIMacros', 'TUIMacrosPlugin', 'TUIBenchmarks', 'TUIWidthCorpus'}
_DIAGNOSTIC = re.compile(r'(\S+?):(\d+):(\d+): (warning|error): (.*)')
_NOTE = re.compile(r'\S+?:\d+:\d+: note: (.*)')


def _sdk():
    environment = {k: v for k, v in os.environ.items() if k not in ('DEVELOPER_DIR', 'SDKROOT')}
    return subprocess.run(['xcrun', '--show-sdk-path'], env=environment, capture_output=True, text=True).stdout.strip()


def _deployment_target(source_root):
    """The macOS floor in TUI's manifest at this commit: a module type-checks only at the target its neighbours built for."""
    with open(os.path.join(source_root, 'Package.swift')) as manifest:
        return re.search(r'\.macOS\(\.v(\d+)\)', manifest.read()).group(1)


def _typecheck(module, source_root, modules, sdk, toolchain, slot, out):
    sources = os.path.join(source_root, 'Sources')
    files = [os.path.relpath(os.path.join(directory, name), sources)
             for directory, _, names in os.walk(os.path.join(sources, module)) for name in names if name.endswith('.swift')]
    if not files:
        return ''
    swiftc = ['env', '-u', 'DEVELOPER_DIR', '-u', 'SDKROOT', 'swiftly', 'run', 'swiftc', f'+{toolchain}'] if toolchain != 'system' else ['swiftc']
    include = os.path.join(sources, 'CSTBImage', 'include')
    command = swiftc + ['-typecheck', '-strict-memory-safety', '-diagnostic-style', 'llvm', '-parse-as-library',
                        '-swift-version', '6', '-module-name', module, '-package-name', 'tui',
                        '-target', f'arm64-apple-macosx{_deployment_target(source_root)}.0', '-sdk', sdk, '-I', modules, '-I', include,
                        '-Xcc', f'-I{include}'] + files
    done = subprocess.run((['python3', slot] if slot else []) + command, cwd=sources, capture_output=True, text=True,
                          env={**os.environ, 'TUIKIT_SWIFT': 'swiftly'})
    text = done.stdout + done.stderr
    with open(os.path.join(out, f'{module}.log'), 'w') as log:
        log.write(text)
    return text


def _cause(note):
    if 'unsafe type' in note:
        return 'a value of an Unsafe* or C pointer type'
    if 'nonisolated(unsafe)' in note:
        return 'a read of a nonisolated(unsafe) global'
    if 'exclusivity(unchecked)' in note:
        return 'a read of an @exclusivity(unchecked) property'
    if 'unsafe global function' in note:
        return 'a call of an unsafe function'
    if 'unowned(unsafe)' in note:
        return 'an unowned(unsafe) property'
    return 'other: ' + re.sub(r"'[^']*'", 'X', note)[:60]


def summarise(text, seen):
    """The strict-safety diagnostics in one module's output: their count, kinds and causes, and any setup errors."""
    lines = text.split('\n')
    count, errors = 0, 0
    kinds, causes, files = collections.Counter(), collections.Counter(), collections.Counter()
    for number, line in enumerate(lines):
        match = _DIAGNOSTIC.match(line)
        if not match:
            continue
        if match.group(4) == 'error':
            errors += 1
            continue
        if 'StrictMemorySafety' not in line:
            continue
        key = match.group(1, 2, 3, 5)
        if key in seen:
            continue
        seen.add(key)
        count += 1
        kinds[re.sub(r"'[^']*'", 'X', match.group(5)).split(' [')[0]] += 1
        files[match.group(1)] += 1
        for following in lines[number + 1:number + 8]:
            note = _NOTE.match(following)
            if note:
                causes[_cause(note.group(1))] += 1
                break
    return count, errors, kinds, causes, files


def run(source_root, modules, out, toolchain, build):
    slot = build.find_slot()
    sdk = _sdk()
    seen = set()
    rows, all_kinds, all_causes, all_files = [], collections.Counter(), collections.Counter(), collections.Counter()
    for module in sorted(os.listdir(os.path.join(source_root, 'Sources'))):
        if not module.startswith('TUI') or module in SKIP:
            continue
        count, errors, kinds, causes, files = summarise(_typecheck(module, source_root, modules, sdk, toolchain, slot, out), seen)
        rows.append((module, count, errors))
        all_kinds.update(kinds)
        all_causes.update(causes)
        all_files.update(files)
    print('Module | Sites | Setup errors')
    for module, count, errors in sorted(rows, key=lambda row: -row[1]):
        print(f'{module} | {count} | {errors}')
    print(f'Total: {sum(row[1] for row in rows)} sites in {sum(1 for row in rows if row[1])} of {len(rows)} modules')
    print('\nKinds')
    for name, count in all_kinds.most_common(10):
        print(f'{count:6d}  {name}')
    print('\nCauses (the first note of each)')
    for name, count in all_causes.most_common(12):
        print(f'{count:6d}  {name}')
    print('\nFiles')
    for name, count in all_files.most_common(15):
        print(f'{count:6d}  {name}')
