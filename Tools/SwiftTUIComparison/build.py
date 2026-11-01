"""Gets each framework's source at a chosen commit, writes the same small apps against each, and builds them.

Everything lands in a scratch directory outside the repo, by commit, so a second run at the same commits rebuilds
nothing and a run at a new commit leaves the old build to be deleted by hand.
"""
import os
import re
import resource
import shutil
import subprocess
import time

HERE = os.path.dirname(os.path.abspath(__file__))
SWIFTTUI_URL = 'https://github.com/SwiftTUI/swift-tui.git'
SWIFTTUI_EXAMPLES_URL = 'https://github.com/SwiftTUI/swift-tui-examples.git'
# 0.20.0 and a little: what the 2026-11 comparison measured.
SWIFTTUI_PINNED = '207913d23c99962462310bcf5802e796d49814ef'
SWIFTTUI_EXAMPLES_PINNED = '4aba1833f81a5dc423725ec10201ee56acbe4d13'
DEFAULT_TOOLCHAIN = '6.4.0'

HELLO = '''
@main struct HelloApp: App {
    var body: some Scene { WindowGroup { Text("Hello, world") } }
}
'''
COUNTER = '''
struct CounterView: View {
    @State private var count = 0
    var body: some View {
        VStack {
            Text("Count: \\(count)")
            Button("Increment") { count += 1 }
        }
    }
}
@main struct CounterApp: App {
    var body: some Scene { WindowGroup { CounterView() } }
}
'''
LIST_WITH_SELECTION = '''
struct ListView: View {
    @State private var selection: Int? = 0
    var body: some View {
        VStack(alignment: .leading) {
            Text("Selected: \\(selection ?? -1)")
            List(selection: $selection) {
                ForEach(0..<100, id: \\.self) { i in
                    Text("Row \\(i)").tag(i)
                }
            }
        }
    }
}
@main struct ListApp: App {
    var body: some Scene { WindowGroup { ListView() } }
}
'''
MID_SIZE = '''
struct Person: Identifiable, Sendable { let id: Int; let name: String; let city: String; let age: String }
let people = (0..<100).map { Person(id: $0, name: "Name \\($0)", city: "City \\($0 % 7)", age: "\\(20 + $0 % 40)") }
struct DataTab: View {
    @State private var selection: Int? = 0
    var body: some View {
        TABLE
    }
}
struct EditTab: View {
    @State private var text = ""
    @State private var showing = false
    var body: some View {
        VStack(alignment: .leading) {
            TextField("Name", text: $text)
            Button("Show") { showing = true }
            Text("Typed: \\(text)")
        }
        .sheet(isPresented: $showing) {
            VStack {
                Text("Hello \\(text)")
                Button("Close") { showing = false }
            }
        }
    }
}
struct Root: View {
    @State private var tab = 0
    var body: some View {
        TabView(selection: $tab) {
            TAB_DATA { DataTab() }
            TAB_EDIT { EditTab() }
        }
    }
}
@main struct MidApp: App {
    var body: some Scene { WindowGroup { Root() } }
}
'''
MID_SIZE_TUI = MID_SIZE.replace('TABLE', '''Table(people, selection: $selection) {
            TableColumn("Name", value: \\.name)
            TableColumn("City", value: \\.city)
            TableColumn("Age", value: \\.age)
        }''').replace('TAB_DATA', 'Tab("Data", systemImage: "tablecells", value: 0)').replace(
    'TAB_EDIT', 'Tab("Edit", systemImage: "pencil", value: 1)')
MID_SIZE_SWIFTTUI = MID_SIZE.replace('TABLE', '''Table(people, id: \\.id, selection: $selection, columns: [TableColumn("Name"), TableColumn("City"), TableColumn("Age")]) { p in
            Text(p.name)
            Text(p.city)
            Text(p.age)
        }''').replace('TAB_DATA', 'Tab("Data", value: 0)').replace('TAB_EDIT', 'Tab("Edit", value: 1)')

BENCH_IMPORTS = 'import Foundation\nimport Observation\n'
SWIFTTUI_NARROW = 'import SwiftTUIRuntime\nimport SwiftTUICLI\nimport SwiftTUIArguments'
SWIFTTUI_NARROW_PRODUCTS = ['SwiftTUIRuntime', 'SwiftTUICLI', 'SwiftTUIArguments']


def _terminal_only(source):
    # With SwiftTUICLI the App has to be a SwiftTUICommand itself (their EntryPointFixtureCLIBare).
    return source.replace(': App {', ': App, SwiftTUICommand {\n    @OptionGroup var swiftTUIOptions: SwiftTUIOptions')


# Each app, per framework: the imports, the products it depends on, and the source. `bench` has its own files.
_TUI_APPS = {
    'hello': ('import TUI', ['TUI'], HELLO),
    'counter': ('import TUI', ['TUI'], COUNTER),
    'listsel': ('import TUI', ['TUI'], LIST_WITH_SELECTION),
    'midapp': ('import TUI', ['TUI'], MID_SIZE_TUI),
    'hello_sel': ('import TUIApp', ['TUIApp'], HELLO),
    'counter_sel': ('import TUIApp', ['TUIApp'], COUNTER),
    'listsel_sel': ('import TUIApp\nimport TUILists', ['TUIApp', 'TUILists'], LIST_WITH_SELECTION),
    'midapp_sel': ('import TUIApp\nimport TUITables\nimport TUITabs\nimport TUIPresentation\nimport TUITextInput',
                   ['TUIApp', 'TUITables', 'TUITabs', 'TUIPresentation', 'TUITextInput'], MID_SIZE_TUI),
}
_SWIFTTUI_APPS = {
    'hello': ('import SwiftTUI', ['SwiftTUI'], HELLO),
    'counter': ('import SwiftTUI', ['SwiftTUI'], COUNTER),
    'listsel': ('import SwiftTUI', ['SwiftTUI'], LIST_WITH_SELECTION),
    'midapp': ('import SwiftTUI', ['SwiftTUI'], MID_SIZE_SWIFTTUI),
    'hello_cli': (SWIFTTUI_NARROW, SWIFTTUI_NARROW_PRODUCTS, _terminal_only(HELLO)),
    'counter_cli': (SWIFTTUI_NARROW, SWIFTTUI_NARROW_PRODUCTS, _terminal_only(COUNTER)),
    'listsel_cli': (SWIFTTUI_NARROW, SWIFTTUI_NARROW_PRODUCTS, _terminal_only(LIST_WITH_SELECTION)),
    'midapp_cli': (SWIFTTUI_NARROW, SWIFTTUI_NARROW_PRODUCTS, _terminal_only(MID_SIZE_SWIFTTUI)),
}
# In the size table: the app, then which build of it, per framework.
SIZE_APPS = {'tui': [('hello', 'TUI', 'hello'), ('hello', 'selective', 'hello_sel'),
                     ('counter', 'TUI', 'counter'), ('counter', 'selective', 'counter_sel'),
                     ('listsel', 'TUI', 'listsel'), ('listsel', 'selective', 'listsel_sel'),
                     ('midapp', 'TUI', 'midapp'), ('midapp', 'selective', 'midapp_sel')],
             'swifttui': [('hello', 'SwiftTUI', 'hello'), ('hello', 'terminal-only', 'hello_cli'),
                          ('counter', 'SwiftTUI', 'counter'), ('counter', 'terminal-only', 'counter_cli'),
                          ('listsel', 'SwiftTUI', 'listsel'), ('listsel', 'terminal-only', 'listsel_cli'),
                          ('midapp', 'SwiftTUI', 'midapp'), ('midapp', 'terminal-only', 'midapp_cli')]}


def _git(*args, cwd=None):
    return subprocess.run(['git', *args], cwd=cwd, check=True, capture_output=True, text=True).stdout.strip()


def repo_root():
    return _git('rev-parse', '--show-toplevel', cwd=HERE)


def find_slot():
    """The machine's build-slot script, if this checkout's machine has one: it lives in the git-ignored working notes,
    so in a worktree it is beside the main checkout. Elsewhere builds just run."""
    relative = os.path.join('Documentation', 'Working notes', 'plan', 'slot.py')
    common = os.path.abspath(os.path.join(HERE, _git('rev-parse', '--git-common-dir', cwd=HERE)))
    for root in [repo_root(), os.path.dirname(common)]:
        candidate = os.path.join(root, relative)
        if os.path.exists(candidate):
            return candidate
    return None


class Toolchain:
    """`swiftly run swift … +<version>`, or with 'system' whichever `swift` the build environment has."""

    def __init__(self, version):
        self.version = version
        self.uses_swiftly = version != 'system'
        if self.uses_swiftly and not shutil.which('swiftly'):
            raise SystemExit(f'swiftly is not on PATH, and toolchain {version} was asked for. '
                             'Install it, or pass --toolchain system to use the `swift` on PATH.')

    def environment(self):
        env = dict(os.environ)
        if self.uses_swiftly:
            env['TUIKIT_SWIFT'] = 'swiftly'  # slot.py: keep this compiler rather than Xcode's.
        return env

    def command(self, *args):
        if self.uses_swiftly:
            # DEVELOPER_DIR unset because slot.py sets it to Xcode's, and SwiftTUI's tools version needs 6.4.
            return ['env', '-u', 'DEVELOPER_DIR', '-u', 'SDKROOT', 'swiftly', 'run', 'swift', *args, f'+{self.version}']
        return ['swift', *args]

    def describe(self):
        return subprocess.run(self.command('--version'), env=self.environment(), capture_output=True,
                              text=True).stdout.split('\n')[0].strip()


def run_build(command, cwd, toolchain, log):
    """Runs a build through the slot when there is one. Returns (exit status, wall seconds, CPU seconds)."""
    slot = find_slot()
    full = (['python3', slot] if slot else []) + command
    before = resource.getrusage(resource.RUSAGE_CHILDREN)
    started = time.time()
    with open(log, 'a') as out:
        status = subprocess.call(full, cwd=cwd, env=toolchain.environment(), stdout=out, stderr=subprocess.STDOUT)
    wall = time.time() - started
    after = resource.getrusage(resource.RUSAGE_CHILDREN)
    cpu = (after.ru_utime + after.ru_stime) - (before.ru_utime + before.ru_stime)
    return status, wall - _slot_wait(log, slot), cpu


def _slot_wait(log, slot):
    """How long the last build queued for its slot, which slot.py prints: not part of the build's time."""
    if not slot:
        return 0.0
    with open(log, errors='replace') as lines:
        waits = re.findall(r'slot\.py: got a slot after (\d+) s', lines.read())
    return float(waits[-1]) if waits else 0.0


def tui_source(commit, scratch):
    """TUI at `commit`, from this repository, without its documentation. Returns (root for this commit, full SHA)."""
    sha = _git('rev-parse', '--verify', commit + '^{commit}', cwd=HERE)
    root = os.path.join(scratch, f'tui-{sha[:12]}')
    source = os.path.join(root, 'tui')
    if not os.path.exists(os.path.join(source, 'Package.swift')):
        os.makedirs(source, exist_ok=True)
        archive = subprocess.Popen(['git', 'archive', sha, '--', '.', ':(exclude)Documentation'], cwd=repo_root(),
                                   stdout=subprocess.PIPE)
        subprocess.run(['tar', '-x', '-C', source], stdin=archive.stdout, check=True)
        if archive.wait() != 0:
            raise SystemExit(f'git archive {sha} failed')
    return root, sha


def _fetch(url, commit, directory):
    """A checkout of `url` at `commit` in `directory`, fetched shallowly when `commit` is a full SHA."""
    if os.path.exists(os.path.join(directory, '.git')):
        have = _git('rev-parse', 'HEAD', cwd=directory)
        if have.startswith(commit):
            return have
    else:
        os.makedirs(directory, exist_ok=True)
        _git('init', '-q', cwd=directory)
        _git('remote', 'add', 'origin', url, cwd=directory)
    if len(commit) == 40:
        _git('fetch', '-q', '--depth', '1', 'origin', commit, cwd=directory)
        _git('checkout', '-q', 'FETCH_HEAD', cwd=directory)
    else:
        _git('fetch', '-q', 'origin', cwd=directory)
        _git('checkout', '-q', commit, cwd=directory)
    return _git('rev-parse', 'HEAD', cwd=directory)


def swifttui_source(commit, scratch):
    """SwiftTUI at `commit`, fetched into scratch. Returns (root for this commit, full SHA)."""
    root = os.path.join(scratch, f'swifttui-{commit[:12]}')
    sha = _fetch(SWIFTTUI_URL, commit, os.path.join(root, 'swift-tui'))
    return root, sha


def _write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if os.path.exists(path):
        with open(path) as existing:
            if existing.read() == text:
                return
    with open(path, 'w') as out:
        out.write(text)


def _benchmark_source(shim):
    parts = []
    for name in [shim, 'Common.swift']:
        with open(os.path.join(HERE, 'Benchmark', name)) as source:
            parts.append(source.read())
    return '\n'.join(parts)


def write_apps(framework, root):
    """The apps package for one framework, in `root`, beside the framework's source."""
    apps = os.path.join(root, 'apps')
    if framework == 'tui':
        table, shim, umbrella, package, dependency, tools = _TUI_APPS, 'TUIShim.swift', 'TUI', 'tui', '../tui', '6.2'
    else:
        table, shim, umbrella, package, dependency, tools = (_SWIFTTUI_APPS, 'SwiftTUIShim.swift', 'SwiftTUI',
                                                             'swift-tui', '../swift-tui', '6.4')
    targets = []
    for name, (imports, products, source) in table.items():
        _write(os.path.join(apps, 'Sources', name, 'App.swift'), imports + '\n' + source)
        depends = ', '.join(f'.product(name: "{p}", package: "{package}")' for p in products)
        targets.append(f'        .executableTarget(name: "{name}", dependencies: [{depends}]),')
    _write(os.path.join(apps, 'Sources', 'bench', 'Bench.swift'),
           f'import {umbrella}\n' + BENCH_IMPORTS + _benchmark_source(shim))
    targets.append(f'        .executableTarget(name: "bench", dependencies: [.product(name: "{umbrella}", package: "{package}")]),')
    lines = '\n'.join(targets)
    _write(os.path.join(apps, 'Package.swift'), f'''// swift-tools-version: {tools}
import PackageDescription
let package = Package(
    name: "apps",
    platforms: [.macOS(.v15)],
    dependencies: [.package(path: "{dependency}")],
    targets: [
{lines}
    ]
)
''')
    return apps


def build(toolchain, package_dir, scratch_path, log, products=None, extra=()):
    """`swift build -c release`, one product at a time, or all of a package's. Returns (wall, CPU) seconds.

    Release linking leaves a dSYM per executable, about 80 MB each, that nothing here reads, so they go at once."""
    wall = cpu = 0.0
    for product in products or [None]:
        arguments = ['build', '-c', 'release', '-j', '6', '--scratch-path', scratch_path, *extra]
        if product:
            arguments += ['--product', product]
        status, took, used = run_build(toolchain.command(*arguments), package_dir, toolchain, log)
        wall += took
        cpu += used
        if status != 0:
            raise SystemExit(f'build failed (exit {status}); see {log}')
        release = os.path.join(scratch_path, 'release')
        for entry in os.listdir(release):
            if entry.endswith('.dSYM'):
                shutil.rmtree(os.path.join(release, entry), ignore_errors=True)
    return wall, cpu


def build_alloc_counter(scratch):
    target = os.path.join(scratch, 'alloccount.dylib')
    source = os.path.join(HERE, 'alloccount.c')
    if not os.path.exists(target) or os.path.getmtime(target) < os.path.getmtime(source):
        os.makedirs(scratch, exist_ok=True)
        subprocess.run(['clang', '-O2', '-dynamiclib', '-o', target, source], check=True)
    return target


def large_apps(root_by_framework, scratch, toolchain, log):
    """Each framework's own large example, built in place. They are not equivalent apps. Returns {framework: [(label,
    path)]}: `Example` and `Stress` are built as TUI's root package, since they use its `package` API; `gifeditor` is
    SwiftTUI's largest example, from its examples repository, with its dependency pointed at the source here."""
    found = {}
    if 'tui' in root_by_framework:
        source = os.path.join(root_by_framework['tui'], 'tui')
        output = os.path.join(root_by_framework['tui'], 'build-root')
        build(toolchain, source, output, log, products=['Example', 'Stress'])
        found['tui'] = [('large: Example', os.path.join(output, 'release', 'Example')),
                        ('large: Stress', os.path.join(output, 'release', 'Stress'))]
    if 'swifttui' in root_by_framework:
        examples = os.path.join(scratch, 'swift-tui-examples')
        _fetch(SWIFTTUI_EXAMPLES_URL, SWIFTTUI_EXAMPLES_PINNED, examples)
        package = os.path.join(examples, 'gifeditor')
        manifest = os.path.join(package, 'Package.swift')
        with open(manifest) as source:
            text = source.read()
        path = os.path.join(root_by_framework['swifttui'], 'swift-tui')
        rewritten = text.replace('.package(url: "https://github.com/SwiftTUI/swift-tui.git", exact: "0.20.0")',
                                 f'.package(path: "{path}")')
        if rewritten == text and path not in text:
            raise SystemExit('gifeditor names SwiftTUI differently now: update large_apps()')
        with open(manifest, 'w') as out:
            out.write(rewritten)
        output = os.path.join(root_by_framework['swifttui'], 'build-gifeditor')
        build(toolchain, package, output, log, products=['gifeditor'])
        found['swifttui'] = [('large: gifeditor', os.path.join(output, 'release', 'gifeditor'))]
    return found
