#!/usr/bin/env python3
"""dedup_check.py: does anything in TUIkit depend on two different functions having different addresses, in an app
linked with `-Xlinker -deduplicate`? (ld then folds byte-identical functions onto one address.)

Run it after a release build that linked an app with `-Xlinker -deduplicate`, on the UNSTRIPPED app and the build's
object files (arm64 only):

    python3 Tools/DedupCheck/dedup_check.py --binary <app> --objects <release build directory> \\
        [--manifest <manifest>] [--plain <the app linked without it>] [--json out.json]

The manifest defaults to manifest.json beside this file. With `--report` it fails on nothing and lists, for an app
developer, the key paths their binary forms that now compare equal ("app" against TUIkit's "tk"), and the code that
compares or hashes key paths.

Exit status: 0 clean (always, under --report), 1 a finding the manifest does not account for, 2 the check could not
run: no objects, none of TUIkit's, no key paths in them, a stripped or universal binary. Never a pass.

Swift code can observe a function's address in two ways, and the check covers both:

KEY PATHS. A key path to a COMPUTED property (or subscript) is identified by its getter's address; `==` and `hash`
compare that address, plus the key path's class (root and value type). So once two getters with the same root and
value type are folded, two different key paths compare and hash equal. A key path to a STORED property is an offset
and cannot be folded.
  [K1] Every key path TUIkit itself forms is a pattern (`l_keypath*`) in its objects, whose relocations name the
       getter that identifies each computed component. Groups of those getters that share one address in the binary,
       and share a root and a value type, are equal key paths. Each group is classified:
         alias      - every member is read-only, or every member's setter also shares one address: the key paths
                      read (and write) the same thing, so treating them as one is harmless for a READER. Listed.
         DIVERGENT  - they compare equal but write differently. A finding unless the manifest's `key_path_aliases`
                      lists the group with a reason.
       An alias still breaks a consumer that uses a key path as a NAME (a tag in a table); see K2.
  [K2] The CONSUMERS: every function in TUIkit's objects that references the standard library's key-path equality or
       hashing (`AnyKeyPath.==`, `.hashValue`, `hash(into:)`, its Equatable/Hashable witness tables) or Foundation's
       KeyPathComparator/SortDescriptor conformances. The set must match `key_path_consumers` in the manifest: a new
       consumer is a finding until someone has checked where its key paths come from and listed it.
  [K3] (report only) Every getter anywhere in the binary that shares its address with a getter of the same root and
       value type: the key paths anyone COULD form that would compare equal. Stored properties are left out.

FUNCTION POINTERS. Comparing the address of a C function (`@convention(c)`) or of a closure.
  [F1] Every `@convention(c)` function (mangled suffix `To`) whose address TUIkit's code or data takes. The set must
       match `c_function_addresses` in the manifest (each entry says whether TUIkit compares that address).
  [F2] Every function the manifest's `address_identity` patterns match (an address TUIkit compares) must be alone at
       its address in the binary, and every pattern must match one: a pattern that names nothing (a renamed
       function, or a binary that does not link it) would otherwise check nothing and pass.

Which objects are TUIkit's: the manifest's `modules` names them by module, and an object's module is where SwiftPM
put it (`<Module>.build/…/x.o`, or Swift Build's merged `<Module>.o`). Every other module's objects are the app's:
reported, never failed. Not covered (documented gaps): key paths and functions compared through a dynamic cast
(`x as? any Hashable`) or generic code that never names them; `unsafeBitCast` of a Swift closure (the SwiftLint rule
`function_address_identity` is the guard there). See README.md beside this file.
"""
import argparse, bisect, collections, json, os, re, shlex, shutil, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import machofile  # noqa: E402

GETTER = re.compile(r'(vg|ig)Z?$')                 # property / subscript getter (Z = static)
PATTERN = re.compile(r'^l_keypath(\.\d+)?$')
SETTER_THUNK = re.compile(r'^l_keypath_set(\.\d+)?$|Tk$')
C_THUNK = re.compile(r'^_?\$s.*To$')               # a @convention(c) entry point (Swift-mangled)
# swift-syntax's modules and the macro plugins: host tools, never linked into an app, and large to read.
SKIP_MODULES = re.compile(r'_?Swift(Syntax|Parser|Diagnostics|BasicFormat|Operators|CompilerPlugin|IfConfig|'
                          r'LexicalLookup|IDEUtils|Refactor|LibraryPluginProvider)\w*|_SwiftSyntax\w*|'
                          r'_InstructionCounter|\w*MacrosPlugin')
KP_EQ = re.compile(r'^_\$ss10AnyKeyPathC(2eeoiySbAB_ABtFZ|9hashValueSivg|4hash4intoys6HasherVz_tF|'
                   r'13_rawHashValue4seedS2i_tF|S[QH]s(WP|Mc))$'
                   r'|^_\$s10Foundation(17KeyPathComparator|14SortDescriptor)V.*(S[QH]AAMc|2eeoiySb|4hash4into)')
ADDR_TAKING = {'PAGE21', 'PAGEOFF12', 'GOT_LOAD_PAGE21', 'GOT_LOAD_PAGEOFF12', 'UNSIGNED', 'POINTER_TO_GOT'}


class CannotCheck(Exception):
    """The check could not run (exit 2): an empty answer must never read as a clean one."""


def build_dir_module(name):
    """The module a `<Module>.build` directory holds: Swift Build names them `<Module>-t.build` for a target and
    `<Module>-p.build` for an executable product. None for any other directory (`.build` itself included)."""
    if not name.endswith('.build') or name == '.build':
        return None
    return re.sub(r'-[tp]$', '', name[:-len('.build')])


def module_of(path):
    """(module, merged) for an object, from where SwiftPM put it. A per-file object sits below a `<Module>.build`
    directory: the native build system's `<Module>.build/x.swift.o`, or Swift Build's
    `Intermediates.noindex/…/<Module>-t.build/Objects-normal/arm64/x.o`. Anything else is Swift Build's MERGED module
    object, `Products/<Configuration>/<Module>.o`, named by its file."""
    parts = os.path.normpath(path).split(os.sep)
    for part in reversed(parts[:-1]):
        module = build_dir_module(part)
        if module:
            return module, False
    return os.path.splitext(parts[-1])[0], True


def module_filter(manifest):
    """A predicate: is this module one of TUIkit's (checked), per the manifest's `modules`? Without a manifest, none
    is: everything is the app's."""
    spec = (manifest or {}).get('modules')
    if not spec:
        return lambda module: False
    pattern, excluded = re.compile(spec['pattern']), set(spec.get('except', []))
    return lambda module: bool(pattern.fullmatch(module)) and module not in excluded


def find_objects(roots):
    """(path, module, merged) of every object under `roots`, less the host tools' (SKIP_MODULES), dSYM bundles and
    any debug build (`debug`, Swift Build's `Debug`): its unspecialised code compares key paths in functions a release
    build does not have. So `.build` itself is a root that works with either build system."""
    seen = set()
    for root in roots:
        for d, dirs, files in os.walk(root):
            dirs[:] = sorted(x for x in dirs if not x.endswith('.dSYM') and x.lower() != 'debug'
                             and not SKIP_MODULES.fullmatch(build_dir_module(x) or ''))
            for f in sorted(files):
                if not f.endswith('.o'):
                    continue
                p = os.path.realpath(os.path.join(d, f))
                module, merged = module_of(p)
                if p not in seen and not SKIP_MODULES.fullmatch(module):
                    seen.add(p)
                    yield p, module, merged


class Scan:
    """What the objects say: key-path patterns, consumers, address-taken C functions, defined names, stored fields."""

    def __init__(self):
        self.objects = 0
        self.checked_objects = 0
        self.merged_modules, self.per_file_modules = set(), set()     # TUIkit's, by the kind of object read
        self.patterns = {}          # getter -> {'sites', 'modules', 'writable', 'app_only'}
        self.consumers = {}         # function -> {'targets', 'checked', 'app', 'modules'}
        self.c_taken = {}           # C function -> {'references', 'checked', 'app', 'modules'}
        self.defined = set()
        self.fields = collections.defaultdict(set)   # type's mangled name ($s...V/C) -> stored field names


def _note(table, name, module, checked):
    e = table.setdefault(name, {'checked': False, 'app': False, 'modules': set()})
    e['checked'] = e['checked'] or checked
    e['app'] = e['app'] or not checked
    e['modules'].add(module)
    return e


def scan_objects(objects, is_checked):
    """Read every (path, module, merged) in `objects`; `is_checked(module)` says whether it is TUIkit's."""
    scan = Scan()
    for p, module, merged in objects:
        img = machofile.read(p)
        if img is None:
            continue
        checked = is_checked(module)
        if checked:
            (scan.merged_modules if merged else scan.per_file_modules).add(module)
        scan.objects += 1
        scan.checked_objects += checked
        by_sect = collections.defaultdict(list)
        for s in img.symbols:
            if s.defined:
                by_sect[s.sect].append(s)
                if s.external or not s.name.startswith('l'):
                    scan.defined.add(s.name)
        for syms in by_sect.values():
            syms.sort(key=lambda s: s.value)
        _scan_fields(img, by_sect, scan.fields)
        for sec in img.sections:
            if not sec.nreloc or sec.segname == '__DWARF' or sec.sectname in ('__compact_unwind', '__eh_frame'):
                continue
            rel = sorted(img.relocations(sec), key=lambda r: r[0])
            syms = by_sect.get(sec.index, [])
            starts = [s.value for s in syms]
            is_code = sec.sectname == '__text'

            def owner(addr):
                i = bisect.bisect_right(starts, addr) - 1
                return syms[i].name if i >= 0 else None

            if not is_code:
                # key path patterns: [start, next distinct symbol address)
                for i, s in enumerate(syms):
                    if not PATTERN.match(s.name):
                        continue
                    end = next((t.value for t in syms[i + 1:] if t.value > s.value), sec.addr + sec.size)
                    inside = [r for r in rel if s.value <= r[0] < end and r[1]]
                    getters = [r[1].replace('l_got.', '') for r in inside
                               if GETTER.search(r[1].replace('l_got.', '')) and r[2] != 'SUBTRACTOR']
                    writable = any(SETTER_THUNK.search(r[1]) for r in inside)
                    for g in getters:
                        e = scan.patterns.setdefault(
                            g, {'sites': set(), 'modules': set(), 'writable': False, 'app_only': True})
                        e['app_only'] = e['app_only'] and not checked
                        e['sites'].add(os.path.basename(p))
                        e['modules'].add(module)
                        e['writable'] = e['writable'] or writable
            for addr, name, rtype, _, _, _ in rel:
                if not name:
                    continue
                target = name.replace('l_got.', '')
                if KP_EQ.search(target):
                    e = _note(scan.consumers, owner(addr) or f'<{sec.sectname} of {module}>', module, checked)
                    e.setdefault('targets', set()).add(target)
                if C_THUNK.search(target) and rtype in ADDR_TAKING:
                    if is_code and rtype in ('UNSIGNED', 'POINTER_TO_GOT'):
                        continue
                    e = _note(scan.c_taken, target, module, checked)
                    e.setdefault('references', set()).add('code' if is_code else f'data:{sec.sectname}')
    return scan


def _scan_fields(img, by_sect, fields):
    """Stored fields per type, from the object's field descriptors (`__swift5_fieldmd`) and their names
    (`__swift5_reflstr`): K3 leaves stored properties out, whose key paths are offsets, not getters."""
    reflstr = img.section('__TEXT', '__swift5_reflstr')
    fieldmd = img.section('__TEXT', '__swift5_fieldmd')
    if not (reflstr and fieldmd and fieldmd.nreloc):
        return
    mfs = [s for s in by_sect.get(fieldmd.index, []) if s.name.endswith('MF')]
    frel = sorted(img.relocations(fieldmd), key=lambda r: r[0])
    for i, mf in enumerate(mfs):
        end = mfs[i + 1].value if i + 1 < len(mfs) else fieldmd.addr + fieldmd.size
        for addr, _, rtype, _, _, sym in frel:
            if mf.value <= addr < end and rtype == 'UNSIGNED' and sym is not None and sym.defined \
                    and sym.sect == reflstr.index:
                o = reflstr.offset + sym.value - reflstr.addr
                fields[mf.name[:-2]].add(img.data[o:img.data.index(b'\0', o)].decode('utf-8', 'replace'))


def binary_symbols(path):
    """(name -> address, address -> names) of the functions in the binary's __text, from its symbol table."""
    img = machofile.read(path)
    if img is None:
        raise CannotCheck(f'{path} is not a Mach-O file')
    text = img.section('__TEXT', '__text')
    addr_of, at = {}, collections.defaultdict(set)
    for s in img.symbols:
        if text and s.defined and s.sect == text.index:
            addr_of[s.name] = s.value
            at[s.value].add(s.name)
    if not addr_of:
        raise CannotCheck(f'{path} has no function symbols: the check needs the binary before `strip`')
    return addr_of, at


def demangler(command):
    """`command` is swift-demangle's path, or a command line such as `swift demangle` (CI's `$SWIFT demangle`)."""
    command = command or shutil.which('swift-demangle') or subprocess.run(
        ['xcrun', '-f', 'swift-demangle'], capture_output=True, text=True).stdout.strip()
    if not command:
        raise CannotCheck('no swift-demangle: pass --demangle <path or command>')
    argv = [command] if os.path.exists(command) else shlex.split(command)

    def run(names):
        names = sorted(set(names))
        if not names:
            return {}
        done = subprocess.run(argv + ['--compact'], input='\n'.join(n[1:] if n.startswith('_$') else n
                                                                    for n in names) + '\n',
                              capture_output=True, text=True)
        out = done.stdout.splitlines()
        if done.returncode != 0 or len(out) != len(names):
            raise CannotCheck(f'{command} --compact failed: {done.stderr.strip()[:200]}')
        return dict(zip(names, out))
    return run


def split_top(s, sep):
    """Index of the last `sep` at bracket depth 0, or -1."""
    depth, last = 0, -1
    for i, ch in enumerate(s):
        if ch in '(<[':
            depth += 1
        elif ch in ')>]':
            depth -= 1
        elif depth == 0 and s.startswith(sep, i):
            last = i
    return last


def root_value(dm):
    """('Root', 'Value', 'property') from a demangled getter, e.g. '(extension in M):A.B.x.getter : T'."""
    dm = re.sub(r'^\(extension in [^)]*\):', '', dm)
    dm = re.sub(r'^static ', '', dm)
    i = dm.find('.getter : ')
    if i < 0:
        return None
    left, value = dm[:i], dm[i + len('.getter : '):]
    j = split_top(left, '.')
    return (left[:j], value, left[j + 1:]) if j > 0 else None


def classify(rows):
    """A group of key paths that compare equal: what writing through each does. AnyKeyPath.== compares the key
    path's class and each component's KIND before its id, and ignores the accessors: a read-only (.get) and a settable
    (.mutatingGetSet) component are never equal, and two settable ones with one getter id are equal whatever their
    setters do."""
    writable = [r for r in rows if r['writable_key_path_formed']]
    if writable and len(writable) < len(rows):
        return 'not equal (read-only vs writable)'
    if not writable:
        return 'alias (read-only)'
    if len({r['setter_address'] for r in rows}) == 1 and rows[0]['setter_address'] is not None:
        return 'alias (same setter)'
    return 'DIVERGENT'


def check(scan, addr_of, at, manifest, dm, plain_addr=None):
    """The findings (fail unless the manifest accounts for them) and the report. `manifest` None: report only."""
    findings, report = [], {}
    manifest_given = manifest is not None
    manifest = manifest or {}

    # ---- K1: key paths TUIkit (and the app) forms
    live = {g: e for g, e in scan.patterns.items() if g in addr_of}
    names = dm(list(live))
    groups = collections.defaultdict(list)
    for g in live:
        rv = root_value(names.get(g, g))
        groups[(addr_of[g],) + ((rv[0], rv[1]) if rv else (g, ''))].append(g)
    k1 = []
    for key, gs in sorted(groups.items()):
        if len(gs) < 2:
            continue
        rows = []
        for g in sorted(gs):
            setter = re.sub(r'(v|i)g(Z?)$', r'\1s\2', g)
            rows.append({'getter': g, 'demangled': names.get(g, g), 'sites': sorted(live[g]['sites'])[:6],
                         'modules': sorted(live[g]['modules']), 'app_only': live[g]['app_only'],
                         'writable_key_path_formed': live[g]['writable'],
                         'setter_address': addr_of.get(setter), 'setter_defined': setter in scan.defined,
                         'folded_by_ld': (plain_addr is not None and len({plain_addr.get(x) for x in gs}) > 1)})
        kind = classify(rows)
        allowed = any(set(x['members']) <= {r['demangled'] for r in rows} or set(x['members']) <= set(gs)
                      for x in manifest.get('key_path_aliases', []))
        k1.append({'address': hex(key[0]), 'root': key[1], 'value': key[2], 'kind': kind, 'allowed': allowed,
                   'members': rows})
        if manifest_given and kind == 'DIVERGENT' and not allowed and not all(r['app_only'] for r in rows):
            findings.append(f'K1 DIVERGENT key paths {" == ".join(r["demangled"] for r in rows)}: equal under '
                            f'folding, but they write differently')
    folded_ids = sorted(g for g in live if len(at[addr_of[g]]) > 1)
    report['K1_not_in_binary'] = sorted(dm([g for g in scan.patterns if g not in addr_of]).values())
    partners = {g: sorted(at[addr_of[g]] - {g}) for g in folded_ids}
    pn = dm(folded_ids + [x for v in partners.values() for x in v])
    report['K1'] = {'patterns_getters': len(scan.patterns), 'in_binary': len(live),
                    'sharing_an_address': len(folded_ids),
                    'folded': [{'getter': pn.get(g, g), 'with': [pn.get(x, x) for x in partners[g]]}
                               for g in folded_ids],
                    'equal_groups': k1}

    # ---- K3 (report only): every getter in the binary folded with a getter of the same root and value type
    allg = [n for n in addr_of if GETTER.search(n) and len(at[addr_of[n]]) > 1]
    tn = dm(list(scan.fields))
    stored = collections.defaultdict(set)
    for t, f in scan.fields.items():
        stored[tn.get(t, t)] |= f
    gn = dm(allg)
    k3 = collections.defaultdict(list)
    for g in allg:
        rv = root_value(gn.get(g, g))
        if rv and rv[2] not in stored.get(re.sub(r'<.*>$', '', rv[0]), ()):
            k3[(addr_of[g], rv[0], rv[1])].append(rv[2])
    report['K3'] = [{'address': hex(k[0]), 'root': k[1], 'value': k[2], 'properties': sorted(set(v))}
                    for k, v in sorted(k3.items()) if len(set(v)) > 1]
    report['stored_fields'] = (sum(len(v) for v in stored.values()), len(stored))

    # ---- K2: consumers of key-path equality / hashing. The app's only if the binary has them: an object's code
    # that the link dropped compares nothing. TUIkit's always: another app may link what this one dropped.
    cnames = dm(list(scan.consumers))
    listed = manifest.get('key_path_consumers', {})
    k2 = []
    for c, e in sorted(scan.consumers.items()):
        if not e['checked'] and c not in addr_of:
            continue
        d = cnames.get(c, c)
        hit = next((k for k in listed if re.search(k, d)), None)
        k2.append({'function': d, 'entry_points': sorted(e['targets']), 'manifest': hit, 'tuikit': e['checked'],
                   'modules': sorted(e['modules'])})
        if manifest_given and hit is None and e['checked']:
            findings.append(f'K2 new key-path equality/hash consumer: {d}')
    used = {r['manifest'] for r in k2 if r['manifest']}
    report['K2'] = {'consumers': k2, 'stale_manifest_entries': [k for k in listed if k not in used]}

    # ---- F1: C functions whose address is taken
    fnames = dm(list(scan.c_taken))
    clisted = manifest.get('c_function_addresses', {})
    f1 = []
    for f, e in sorted(scan.c_taken.items()):
        if not e['checked'] and f not in addr_of:
            continue
        d = fnames.get(f, f)
        hit = next((k for k in clisted if re.search(k, d)), None)
        others = sorted(at.get(addr_of.get(f), set()) - {f}) if f in addr_of else []
        f1.append({'function': d, 'references': sorted(e['references']), 'manifest': hit,
                   'shares_address_with': others, 'tuikit': e['checked'], 'modules': sorted(e['modules'])})
        if manifest_given and hit is None and e['checked']:
            findings.append(f'F1 new address-taken C function: {d} ({", ".join(sorted(e["references"]))})')
    report['F1'] = f1

    # ---- F2: addresses TUIkit compares must be unique. The patterns read demangled names, as every other entry in
    # the manifest does, and one that matches nothing is a finding: it would check nothing and pass.
    f2 = []
    patterns = manifest.get('address_identity', [])
    bnames = dm(list(addr_of)) if patterns else {}
    for pat in patterns:
        matched = sorted(n for n in addr_of if re.search(pat, bnames.get(n, n)))
        if not matched:
            f2.append({'pattern': pat, 'symbol': None, 'shares_address_with': []})
            findings.append(f'F2 address_identity pattern "{pat}" matches no function in the binary: renamed (update '
                            f'the manifest), or not linked here (check a binary that links it)')
        for s in matched:
            others = sorted(at[addr_of[s]] - {s})
            f2.append({'pattern': pat, 'symbol': bnames.get(s, s), 'shares_address_with': others})
            if others:
                findings.append(f'F2 {bnames.get(s, s)} shares its address with {others[:3]}')
    report['F2'] = f2
    return findings, report


def print_report(scan, report, findings, manifest_given, out=sys.stdout):
    def p(s=''):
        print(s, file=out)
    k1 = report['K1']
    p(f'objects scanned: {scan.objects} ({scan.checked_objects} of them TUIkit\'s); key-path getters in patterns: '
      f'{k1["patterns_getters"]} ({k1["in_binary"]} in the binary)')
    p(f'K1 key-path getters sharing their address with another function: {k1["sharing_an_address"]} of '
      f'{k1["in_binary"]}; groups among them with one root and value type (equal key paths): '
      f'{len(k1["equal_groups"])}')
    if report['K1_not_in_binary']:
        p(f'   not in this binary (dead-stripped, so unchecked here): {len(report["K1_not_in_binary"])}')
    for g in k1['equal_groups']:
        p(f'   [{g["kind"]}{"; allowed" if g["allowed"] else ""}] {g["root"]} -> {g["value"]} @ {g["address"]}')
        for r in g['members']:
            p(f'       {r["demangled"]}  setter@{hex(r["setter_address"]) if r["setter_address"] else "-"}'
              f'  formed in {", ".join(r["modules"])}')
    fields, types = report['stored_fields']
    p(f'K3 (report) getters anywhere in the binary sharing an address with a same-root, same-value getter: '
      f'{len(report["K3"])} groups of computed properties (stored ones, {fields} fields of {types} types, are left '
      f'out: their key paths are offsets)')
    for g in report['K3'][:60]:
        p(f'   {g["root"]} -> {g["value"]}: {", ".join(g["properties"])}')
    def tag(r):
        if not r['tuikit']:
            return 'app'
        if not manifest_given:
            return 'tk '
        return 'ok ' if r['manifest'] else 'NEW'

    k2 = report['K2']
    p(f'K2 key-path equality/hash consumers: {len(k2["consumers"])}'
      + (f' (stale manifest entries: {k2["stale_manifest_entries"]})' if manifest_given else ''))
    for r in k2['consumers']:
        p(f'   {tag(r)} {r["function"][:150]}  [{", ".join(r["modules"])}]')
    p(f'F1 address-taken C functions: {len(report["F1"])}')
    for r in report['F1']:
        p(f'   {tag(r)} {r["function"][:120]}  ({", ".join(r["references"])})'
          + (f'  SHARES ADDRESS with {len(r["shares_address_with"])}' if r['shares_address_with'] else ''))
    if manifest_given:
        f2 = report['F2']
        p(f'F2 compared addresses: {sum(1 for r in f2 if r["symbol"])}; shared: '
          f'{sum(1 for r in f2 if r["shares_address_with"])}; patterns matching nothing in this binary: '
          f'{[r["pattern"] for r in f2 if r["symbol"] is None]}')
    if not manifest_given:
        p('\nREPORT ONLY: nothing was checked against a manifest')
    elif findings:
        p(f'\nFAIL: {len(findings)} finding(s)')
        for f in findings:
            p('  ' + f)
    else:
        p('\nOK: nothing in TUIkit depends on an address that -deduplicate folds')


MANIFEST = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'manifest.json')


def run(argv=None, dm=None, out=sys.stdout):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--binary', required=True, help='the app, linked with -Xlinker -deduplicate, NOT stripped')
    ap.add_argument('--objects', required=True, action='append', help='a directory of the build\'s objects')
    ap.add_argument('--manifest', default=MANIFEST, help='the reviewed facts (default: manifest.json beside this)')
    ap.add_argument('--report', action='store_true', help='list everything, fail on nothing: for an app developer')
    ap.add_argument('--plain', help='the same app linked without -deduplicate (marks what ld folded)')
    ap.add_argument('--demangle', help='swift-demangle to use (default: PATH, then xcrun)')
    ap.add_argument('--json')
    a = ap.parse_args(argv)
    try:
        with open(a.manifest) as f:
            manifest = json.load(f)
        dm = dm or demangler(a.demangle)
        objects = list(find_objects(a.objects))
        if not objects:
            raise CannotCheck(f'no object files under {", ".join(a.objects)}')
        scan = scan_objects(objects, module_filter(manifest))
        if not a.report:
            if not scan.checked_objects:
                raise CannotCheck(f'none of the {scan.objects} objects is of a module the manifest\'s `modules` names')
            if not any(not e['app_only'] for e in scan.patterns.values()):
                raise CannotCheck('TUIkit\'s objects form no key path: the scan could not read them')
            merged_only = sorted(scan.merged_modules - scan.per_file_modules)
            if merged_only:
                # Swift 6.4.0's Swift Build, measured 2026-10-11: its merged objects held 207 of the 315 key-path
                # patterns that its per-file objects did.
                raise CannotCheck(f'only Swift Build\'s merged objects of {", ".join(merged_only[:4])}, which lack '
                                  f'key-path patterns its per-file objects hold: pass Intermediates.noindex as well')
        addr_of, at = binary_symbols(a.binary)
        plain_addr = binary_symbols(a.plain)[0] if a.plain else None
        findings, report = check(scan, addr_of, at, None if a.report else manifest, dm, plain_addr)
    except (CannotCheck, machofile.NotReadable, OSError, ValueError) as e:
        print(f'dedup_check: cannot check: {e}', file=sys.stderr)
        return 2
    print_report(scan, report, findings, not a.report, out)
    if a.json:
        with open(a.json, 'w') as f:
            json.dump({'findings': findings, **report}, f, indent=1, default=str)
    return 1 if findings else 0


if __name__ == '__main__':
    sys.exit(run())
