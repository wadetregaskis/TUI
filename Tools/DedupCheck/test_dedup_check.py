#!/usr/bin/env python3
"""
Tests for dedup_check.py on Mach-O files written here, small enough to read by eye: no build, no toolchain.

    python3 -m unittest discover -s Tools/DedupCheck -p 'test_*.py'

Each case writes one "TUIkit" object (forming key paths, comparing them, taking a C function's address), puts it
where SwiftPM would (`<Module>.build/x.swift.o`), writes an "app" whose symbol table says which functions the linker
folded onto one address, and runs the check with a stand-in demangler. What a real `-deduplicate` link folds is the
CI job's to show (README.md); these pin what the check concludes from a given fold.
"""

import contextlib
import io
import json
import os
import shutil
import struct
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dedup_check  # noqa: E402
import machofile  # noqa: E402

N_UNDF_EXT, N_SECT_LOCAL, N_SECT_EXT = 0x01, 0x0E, 0x0F
UNSIGNED, BRANCH26, PAGE21 = 0, 2, 3


def macho(filetype, sections, symbols, cputype=machofile.CPU_TYPE_ARM64):
    """A thin Mach-O 64 file. `sections`: [(segname, sectname, addr, size, [(offset, symbol index, type)])];
    `symbols`: [(name, n_type, n_sect, value)]. Section contents are zeros: the check reads names and relocations."""
    seg_size, symtab_size = 72 + 80 * len(sections), 24
    off = 32 + seg_size + symtab_size
    data_off = []
    for s in sections:
        data_off.append(off)
        off += s[3]
    reloc_off = []
    for s in sections:
        reloc_off.append(off)
        off += 8 * len(s[4])
    symoff = off
    strtab, strx = b'\0', []
    for name, *_ in symbols:
        strx.append(len(strtab))
        strtab += name.encode() + b'\0'
    stroff = symoff + 16 * len(symbols)
    out = struct.pack('<IiiIIIII', machofile.MH_MAGIC_64, cputype, 0, filetype, 2, seg_size + symtab_size, 0, 0)
    out += struct.pack('<II16sQQQQiiII', machofile.LC_SEGMENT_64, seg_size, b'', 0, 0, 0, 0, 7, 7, len(sections), 0)
    for i, (seg, sect, addr, size, relocs) in enumerate(sections):
        out += struct.pack('<16s16sQQIIIIIIII', sect.encode(), seg.encode(), addr, size, data_off[i], 0,
                           reloc_off[i], len(relocs), 0, 0, 0, 0)
    out += struct.pack('<IIIIII', machofile.LC_SYMTAB, symtab_size, symoff, len(symbols), stroff, len(strtab))
    for s in sections:
        out += b'\0' * s[3]
    for s in sections:
        for offset, symnum, rtype in s[4]:
            pcrel = 1 if rtype in (BRANCH26, PAGE21) else 0
            out += struct.pack('<iI', offset, symnum | pcrel << 24 | 2 << 25 | 1 << 27 | rtype << 28)
    for i, (name, n_type, n_sect, value) in enumerate(symbols):
        out += struct.pack('<IBBHQ', strx[i], n_type, n_sect, 0, value)
    return out + strtab


GA, GB, GC, GD = '_$s1M1SV1aSivg', '_$s1M1SV1bSivg', '_$s1M1SV1cSivg', '_$s1M1SV1dSivg'
SA, SB = '_$s1M1SV1aSivs', '_$s1M1SV1bSivs'
COMPARE = '_$s1M7compareySbs10AnyKeyPathC_ADtF'
SETUP = '_$s1M5setupyyF'
HANDLER = '_$s1M7handleryys5Int32VcvpZfiyADcfU_To'
KP_EQUALS = '_$ss10AnyKeyPathC2eeoiySbAB_ABtFZ'

DEMANGLED = {
    GA: 'M.S.a.getter : Swift.Int', GB: 'M.S.b.getter : Swift.Int',
    GC: 'M.S.c.getter : Swift.Int', GD: 'M.S.d.getter : Swift.Int',
    SA: 'M.S.a.setter : Swift.Int', SB: 'M.S.b.setter : Swift.Int',
    COMPARE: 'M.compare(Swift.AnyKeyPath, Swift.AnyKeyPath) -> Swift.Bool', SETUP: 'M.setup() -> ()',
    HANDLER: '@objc closure #1 (Swift.Int32) -> () in variable initialization expression of static M.handler',
}


def demangle(names):
    return {n: DEMANGLED.get(n, n) for n in names}


def library_object():
    """Four key-path patterns (\\S.a and \\S.b writable, \\S.c and \\S.d read-only), `compare` calling
    AnyKeyPath.==, and `setup` taking the address of a @convention(c) handler."""
    symbols = [
        ('l_keypath', N_SECT_LOCAL, 2, 0x100), ('l_keypath.1', N_SECT_LOCAL, 2, 0x120),
        ('l_keypath.2', N_SECT_LOCAL, 2, 0x140), ('l_keypath.3', N_SECT_LOCAL, 2, 0x150),
        (GA, N_UNDF_EXT, 0, 0), ('_$s1M1SV1aSivpACTk', N_UNDF_EXT, 0, 0),          # 4, 5
        (GB, N_UNDF_EXT, 0, 0), ('_$s1M1SV1bSivpACTk', N_UNDF_EXT, 0, 0),          # 6, 7
        (GC, N_UNDF_EXT, 0, 0), (GD, N_UNDF_EXT, 0, 0),                            # 8, 9
        (COMPARE, N_SECT_EXT, 1, 0x0), (KP_EQUALS, N_UNDF_EXT, 0, 0),              # 10, 11
        (HANDLER, N_UNDF_EXT, 0, 0), (SETUP, N_SECT_EXT, 1, 0x40),                 # 12, 13
    ]
    text = ('__TEXT', '__text', 0x0, 0x100, [(0x10, 11, BRANCH26), (0x44, 12, PAGE21)])
    const = ('__DATA', '__const', 0x100, 0x80, [(0x04, 4, UNSIGNED), (0x08, 5, UNSIGNED),
                                                (0x24, 6, UNSIGNED), (0x28, 7, UNSIGNED),
                                                (0x44, 8, UNSIGNED), (0x54, 9, UNSIGNED)])
    return macho(machofile.MH_OBJECT, [text, const], symbols)


def app_binary(setters_differ=True, handler_alone=True, with_compare=True):
    """The linked app: \\S.a's and \\S.b's getters folded onto 0x1100, \\S.c's and \\S.d's onto 0x1300."""
    symbols = [(GA, N_SECT_EXT, 1, 0x1100), (GB, N_SECT_EXT, 1, 0x1100),
               (SA, N_SECT_EXT, 1, 0x1200), (SB, N_SECT_EXT, 1, 0x1210 if setters_differ else 0x1200),
               (GC, N_SECT_EXT, 1, 0x1300), (GD, N_SECT_EXT, 1, 0x1300),
               (HANDLER, N_SECT_EXT, 1, 0x1500), (SETUP, N_SECT_EXT, 1, 0x1600)]
    if with_compare:
        symbols.append((COMPARE, N_SECT_EXT, 1, 0x1400))
    if not handler_alone:
        symbols.append(('_$s1M5otheryys5Int32VcvpZfiyADcfU_To', N_SECT_EXT, 1, 0x1500))
    return macho(machofile.MH_EXECUTE, [('__TEXT', '__text', 0x1000, 0x1000, [])], symbols)


MANIFEST = {
    'modules': {'pattern': 'TUIkit[A-Za-z]*', 'except': ['TUIkitTestSupport']},
    'key_path_consumers': {r'M\.compare': 'reviewed'},
    'c_function_addresses': {r'M\.handler': 'reviewed'},
    'address_identity': [r'^@objc closure .* M\.handler$'],
    'key_path_aliases': [],
}


class DedupCheckTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix='test-dedup-check-')
        self.addCleanup(shutil.rmtree, self.dir)

    def write(self, relpath, data):
        path = os.path.join(self.dir, relpath)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, 'wb') as f:
            f.write(data)
        return path

    def run_check(self, manifest=MANIFEST, binary=None, module='TUIkitView', extra=()):
        self.write(f'release/{module}.build/K.swift.o', library_object())
        binary = binary if binary is not None else app_binary()
        app = self.write('app/Stress', binary)
        mpath = self.write('manifest.json', json.dumps(manifest).encode())
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stderr(err):
            status = dedup_check.run(['--binary', app, '--objects', os.path.join(self.dir, 'release'),
                                      '--manifest', mpath, *extra], dm=demangle, out=out)
        return status, out.getvalue() + err.getvalue()

    def test_a_divergent_pair_fails(self):
        status, out = self.run_check()
        self.assertEqual(status, 1, out)
        self.assertIn('K1 DIVERGENT key paths M.S.a.getter : Swift.Int == M.S.b.getter : Swift.Int', out)

    def test_an_allow_listed_divergent_pair_passes(self):
        manifest = dict(MANIFEST, key_path_aliases=[{'members': [GA, GB], 'reason': 'reviewed'}])
        status, out = self.run_check(manifest)
        self.assertEqual(status, 0, out)
        self.assertIn('[DIVERGENT; allowed]', out)

    def test_one_setter_makes_an_alias_not_a_finding(self):
        status, out = self.run_check(binary=app_binary(setters_differ=False))
        self.assertEqual(status, 0, out)
        self.assertIn('[alias (same setter)]', out)

    def test_read_only_key_paths_folded_together_are_listed_as_an_alias(self):
        status, out = self.run_check(binary=app_binary(setters_differ=False))
        self.assertIn('[alias (read-only)] M.S -> Swift.Int @ 0x1300', out)

    def test_an_unlisted_consumer_of_key_path_equality_fails(self):
        status, out = self.run_check(dict(MANIFEST, key_path_consumers={},
                                          key_path_aliases=[{'members': [GA, GB], 'reason': 'r'}]))
        self.assertEqual(status, 1, out)
        self.assertIn('K2 new key-path equality/hash consumer: M.compare(', out)

    def test_a_consumer_is_checked_even_when_the_app_dropped_it(self):
        # Another app may link what this one dead-stripped.
        status, out = self.run_check(dict(MANIFEST, key_path_consumers={},
                                          key_path_aliases=[{'members': [GA, GB], 'reason': 'r'}]),
                                     binary=app_binary(with_compare=False))
        self.assertEqual(status, 1, out)

    def test_the_apps_own_consumers_and_key_paths_are_reported_not_failed(self):
        # The same code in a module the manifest does not name is the app's. The check still needs one of TUIkit's
        # objects with a key path to run at all.
        self.write('release/TUIkitCore.build/K.swift.o', library_object())
        status, out = self.run_check(dict(MANIFEST, key_path_consumers={},
                                          key_path_aliases=[{'members': [GA, GB], 'reason': 'r'}]),
                                     module='Stress')
        self.assertEqual(status, 1, out)  # TUIkitCore's copy is TUIkit's
        shutil.rmtree(os.path.join(self.dir, 'release/TUIkitCore.build'))
        status, out = self.run_check(dict(MANIFEST, key_path_consumers={}), module='Stress', extra=('--report',))
        self.assertEqual(status, 0, out)
        self.assertIn('app M.compare(', out)

    def test_an_unlisted_address_taken_c_function_fails(self):
        manifest = dict(MANIFEST, c_function_addresses={},
                        key_path_aliases=[{'members': [GA, GB], 'reason': 'r'}])
        status, out = self.run_check(manifest)
        self.assertEqual(status, 1, out)
        self.assertIn('F1 new address-taken C function: @objc closure #1', out)

    def test_a_compared_address_that_is_shared_fails(self):
        manifest = dict(MANIFEST, key_path_aliases=[{'members': [GA, GB], 'reason': 'r'}])
        status, out = self.run_check(manifest, binary=app_binary(handler_alone=False))
        self.assertEqual(status, 1, out)
        self.assertIn(f'F2 {DEMANGLED[HANDLER]} shares its address with', out)

    def test_a_compared_address_pattern_that_matches_nothing_fails(self):
        # A renamed function, or the pattern written against another spelling of the name: without this, F2 would
        # check nothing and pass.
        manifest = dict(MANIFEST, address_identity=[r'M\.renamedHandler'],
                        key_path_aliases=[{'members': [GA, GB], 'reason': 'r'}])
        status, out = self.run_check(manifest)
        self.assertEqual(status, 1, out)
        self.assertIn(r'F2 address_identity pattern "M\.renamedHandler" matches no function in the binary', out)

    def test_report_mode_fails_on_nothing(self):
        status, out = self.run_check(extra=('--report',))
        self.assertEqual(status, 0, out)
        self.assertIn('[DIVERGENT]', out)
        self.assertIn('REPORT ONLY', out)
        self.assertIn('tk  M.compare(', out)

    def test_a_stripped_binary_cannot_be_checked(self):
        stripped = macho(machofile.MH_EXECUTE, [('__TEXT', '__text', 0x1000, 0x1000, [])], [])
        status, out = self.run_check(binary=stripped)
        self.assertEqual(status, 2)
        self.assertIn('the check needs the binary before `strip`', out)

    def test_a_universal_binary_cannot_be_checked(self):
        status, out = self.run_check(binary=struct.pack('>II', machofile.FAT_MAGIC, 2) + b'\0' * 64)
        self.assertEqual(status, 2)
        self.assertIn('lipo -thin arm64', out)

    def test_without_tuikit_objects_the_check_cannot_run(self):
        status, out = self.run_check(module='Stress')
        self.assertEqual(status, 2)
        self.assertIn("none of the 1 objects is of a module the manifest's `modules` names", out)

    def test_a_debug_build_beside_the_release_one_is_not_read(self):
        # The same consumer, unlisted, in a debug build's object (as Swift Build lays one out): not a finding.
        self.write('release/Debug/TUIkitApp-t.build/Objects-normal/arm64/K.o', library_object())
        manifest = dict(MANIFEST, key_path_aliases=[{'members': [GA, GB], 'reason': 'r'}])
        status, out = self.run_check(manifest)
        self.assertEqual(status, 0, out)
        self.assertNotIn('TUIkitApp', out)

    def test_a_merged_module_object_alone_cannot_be_checked(self):
        # Swift Build's merged `<Module>.o` lacks key-path patterns its per-file objects hold.
        shutil.rmtree(self.dir)
        os.makedirs(self.dir)
        self.write('release/TUIkitView.o', library_object())
        app = self.write('app/Stress', app_binary())
        mpath = self.write('manifest.json', json.dumps(MANIFEST).encode())
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            status = dedup_check.run(['--binary', app, '--objects', os.path.join(self.dir, 'release'),
                                      '--manifest', mpath], dm=demangle, out=io.StringIO())
        self.assertEqual(status, 2)
        self.assertIn("only Swift Build's merged objects of TUIkitView", err.getvalue())

    def test_objects_for_another_cpu_cannot_be_checked(self):
        self.write('release/TUIkitApp.build/X.swift.o', macho(machofile.MH_OBJECT, [], [], cputype=0x01000007))
        status, out = self.run_check()
        self.assertEqual(status, 2)
        self.assertIn('not arm64', out)


class ParsingTests(unittest.TestCase):
    def test_module_of_reads_where_swiftpm_put_the_object(self):
        # The native build system, then Swift Build's per-file objects (a target's `-t`, an executable's `-p`), then
        # Swift Build's merged module object: the layouts measured with Swift 6.2.4 and 6.4.0.
        cases = {
            '.build/arm64-apple-macosx/release/TUIkitCore.build/Animation.swift.o': ('TUIkitCore', False),
            '/scratch/release/Stress.build/main.swift.o': ('Stress', False),
            '.build/out/Intermediates.noindex/TUIkit.build/Release/TUIkitView-t.build/Objects-normal/arm64/A.o':
                ('TUIkitView', False),
            '.build/out/Intermediates.noindex/TUIkit.build/Release/Stress-p.build/Objects-normal/arm64/main.o':
                ('Stress', False),
            '.build/out/Products/Release/TUIkitApp.o': ('TUIkitApp', True),
        }
        for path, module in cases.items():
            self.assertEqual(dedup_check.module_of(path), module, path)

    def test_root_value_splits_a_getter_at_the_top_level(self):
        self.assertEqual(
            dedup_check.root_value('(extension in TUIkitFoundation):TUIkitCore.EnvironmentValues.buttonStyle.getter'
                                   ' : TUIkitFoundation.ButtonStyle'),
            ('TUIkitCore.EnvironmentValues', 'TUIkitFoundation.ButtonStyle', 'buttonStyle'))
        self.assertEqual(dedup_check.root_value('static M.G<Swift.Int>.a.getter : Swift.Int'),
                         ('M.G<Swift.Int>', 'Swift.Int', 'a'))
        self.assertIsNone(dedup_check.root_value('M.f() -> ()'))

    def test_host_tools_are_not_read(self):
        for module in ('SwiftSyntax', 'SwiftParserDiagnostics', '_SwiftSyntaxCShims', 'TUIkitMacrosPlugin'):
            self.assertTrue(dedup_check.SKIP_MODULES.fullmatch(module), module)
        for module in ('TUIkitMacros', 'MySyntaxHighlighter', 'Stress'):
            self.assertFalse(dedup_check.SKIP_MODULES.fullmatch(module), module)


if __name__ == '__main__':
    unittest.main()
