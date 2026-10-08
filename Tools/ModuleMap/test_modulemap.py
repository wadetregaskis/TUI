"""Unit tests for the module map, on hand-written sources and occurrences: no index store, no build.

    python3 -m unittest discover -s Tools/ModuleMap
"""
import contextlib
import ctypes
import io
import os
import sys
import tempfile
import time
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import assigner  # noqa: E402
import checks  # noqa: E402
import modulemap  # noqa: E402
import indexstore as IX  # noqa: E402
import model as model_mod  # noqa: E402
import swiftsource as SS  # noqa: E402
from model import Model  # noqa: E402
from rules import Rules  # noqa: E402

DEF = IX.DEFINITION | IX.DECLARATION
REF = IX.REFERENCE


def rules(**extra):
    data = {
        'source': 'Sources/X', 'default': 'Base', 'app': 'App', 'umbrella': 'X',
        'modules': [{'name': 'Base', 'deps': []}, {'name': 'Lists', 'deps': ['Base']},
                    {'name': 'Tables', 'deps': ['Lists']}, {'name': 'App', 'deps': ['Base']},
                    {'name': 'X', 'deps': ['Lists', 'Tables', 'App']}],
        'files': [{'module': 'Lists', 'pin': False, 'match': r'^Lists/'},
                  {'module': 'Tables', 'pin': False, 'match': r'^Tables/'},
                  {'module': 'App', 'pin': True, 'match': r'^App/'},
                  {'module': 'X', 'pin': True, 'match': r'^Exports\.swift$'}],
        'declarations': [], 'unpin': [], 'scheduled': [], 'accepted': [],
        'posix': {'c_symbols': ['isatty'], 'swift_symbols': [], 'imports': ['Darwin']},
        'witness_pairs': {'View': ['Renderable']},
    }
    data.update(extra)
    return Rules(data)


def model(sources, occurrences, symbols):
    """A Model from {rel: text}, {rel: [(usr, roles, line, container)]} and {usr: (name, kind[, subkind])}."""
    M = Model()
    M.files = sorted(sources)
    M.lexed = {f: SS.lex(t) for f, t in sources.items()}
    M.symbols = {u: (tuple(s) + (0,))[:3] for u, s in symbols.items()}
    M.build(occurrences)
    return M


class LexerTests(unittest.TestCase):
    SRC = '\n'.join([
        '// Header comment',                       # 1
        'import Foundation',                       # 2
        '',                                        # 3
        '/// A doc comment.',                      # 4
        '@MainActor',                              # 5
        'public struct A {',                       # 6
        '    let s = "a { brace } in a string"',   # 7
        '    /* a { block',                        # 8
        '       comment } */',                     # 9
        '}',                                       # 10
        '',                                        # 11
        'typealias B = A',                         # 12
        '#if canImport(Darwin)',                   # 13
        'func posixOnly() { isatty(0) }',          # 14
        '#else',                                   # 15
        'func elsewhere() {}',                     # 16
        '#endif',                                  # 17
    ])

    def test_chunks_take_doc_comments_and_attributes(self):
        L = SS.lex(self.SRC)
        cs = SS.chunks(L)
        self.assertEqual(cs[0][:2], (3, 10))      # the doc comment and attribute (and the blank before) are A's
        self.assertEqual(cs[1][0], 11)

    def test_strings_and_comments_hide_brackets(self):
        L = SS.lex(self.SRC)
        self.assertEqual(L.dend[7], 1)
        self.assertEqual(L.dend[9], 1)
        self.assertEqual(L.dend[10], 0)
        self.assertNotIn('brace', L.stripped[7])

    def test_posix_guard_is_the_if_arm_not_the_else(self):
        L = SS.lex(self.SRC)
        self.assertTrue(SS.posix_guarded(L.conds[14]))
        self.assertFalse(SS.posix_guarded(L.conds[16]))
        self.assertFalse(SS.posix_guarded(SS.lex('#if !canImport(Darwin)\nx\n#endif').conds[2]))
        self.assertFalse(SS.posix_guarded(SS.lex('#if !os(WASI)\nx\n#endif').conds[2]))

    def guarded(self, text):
        L = SS.lex(text)
        return SS.posix_guarded(L.conds[text.split('\n').index('x') + 1])

    def test_an_else_arm_is_guarded_when_its_chain_rules_out_windows_and_wasi(self):
        # Plan section 4's K6: the WASI arm gains Windows, and the getpid left in the #else is POSIX-only.
        self.assertTrue(self.guarded('#if canImport(WASILibc) || os(Windows)\nw\n#else\nx\n#endif'))
        self.assertTrue(self.guarded('#if os(Windows)\nw\n#elseif canImport(WASILibc)\nv\n#else\nx\n#endif'))
        self.assertTrue(self.guarded('#if os(Windows)\nw\n#elseif canImport(Glibc)\nx\n#endif'))
        self.assertFalse(self.guarded('#if canImport(WASILibc)\nw\n#else\nx\n#endif'))         # Windows compiles it
        self.assertFalse(self.guarded('#if os(Windows) && arch(x86_64)\nw\n#elseif os(WASI)\nv\n#else\nx\n#endif'))

    def test_a_condition_is_evaluated_not_matched(self):
        self.assertTrue(self.guarded('#if !os(Windows) && !os(WASI)\nx\n#endif'))
        self.assertTrue(self.guarded('#if !os(Windows)\n#if !canImport(WASILibc)\nx\n#endif\n#endif'))
        self.assertTrue(self.guarded('#if canImport(AppKit)\nx\n#endif'))
        self.assertFalse(self.guarded('#if canImport(Darwin) || canImport(WASILibc)\nx\n#endif'))
        self.assertFalse(self.guarded('#if canImport(Darwin) || compiler(>=6.3)\nx\n#endif'))
        self.assertFalse(self.guarded('#if canImport(Darwin) ||\nx\n#endif'))                # does not parse


class RulesTests(unittest.TestCase):
    def test_visibility(self):
        R = rules()
        self.assertTrue(R.sees('Tables', 'Base'))
        self.assertFalse(R.sees('Base', 'Lists'))
        self.assertFalse(R.sees('Lists', 'App'))
        self.assertTrue(R.sees('Base', 'TUIkitView'))          # below the map: visible everywhere
        self.assertEqual(R.join({'Lists', 'App'}), 'X')
        self.assertEqual(R.meet('Tables', 'App'), 'Base')

    def test_rejects_a_cycle(self):
        with self.assertRaises(SystemExit):
            rules(modules=[{'name': 'Base', 'deps': ['Lists']}, {'name': 'Lists', 'deps': ['Base']}])

    def test_without_contents_rules_a_files_directory_is_its_module(self):
        # Since A5 every module's files sit in Sources/<module>: the directory says where a file goes, and nothing
        # moves it but a `git mv`. The contents rules would otherwise seed by path, and let an unpinned file move.
        data = dict(rules().data)
        del data['files']
        R = Rules(data)
        self.assertTrue(R.by_directory)
        self.assertEqual(R.seed('Lists/Views/A.swift'), ('Lists', True))
        self.assertEqual(R.seed('X/Exports.swift'), ('X', True))
        self.assertEqual(R.seed('Elsewhere/B.swift'), ('Base', False))       # no module of the map: never read
        self.assertFalse(rules().by_directory)
        self.assertEqual(rules().seed('Lists/Views/A.swift'), ('Lists', False))


class SpanAttributionTests(unittest.TestCase):
    """A reference with no container (a typealias's right-hand side) is charged to the declaration whose text holds
    it, not to the next one: the research graph's rule, which hid plan section 4's X1 and X2."""

    def test_typealias_rhs_charged_to_its_own_declaration(self):
        srcs = {'Base/P.swift': 'protocol P {\n    typealias Configuration = Conf\n}\nstruct Conf {}\n'}
        occ = {'Base/P.swift': [('s:P', DEF, 1, ''), ('s:P.C', DEF, 2, 's:P'), ('s:Conf', REF, 2, ''),
                                ('s:Conf', DEF, 4, '')]}
        M = model(srcs, occ, {'s:P': ('P', IX.K_PROTOCOL), 's:P.C': ('Configuration', IX.K_TYPEALIAS),
                              's:Conf': ('Conf', IX.K_STRUCT)})
        self.assertIn('s:Conf', M.edges['s:P'])


VIEW = 's:10TUIkitView4ViewP'


def view_extensions(firsts):
    """Lists/V.swift: one `extension View` block per entry of `firsts`, each opening with that member, in order."""
    lines, occ, sym = [], [], {VIEW: ('View', IX.K_PROTOCOL)}
    for i, first in enumerate(firsts):
        e, mem = f's:e:{first}', f's:{first}'
        lines += ['extension View {', f'    public func {first}() {{}}', '}']
        occ += [(e, DEF, 3 * i + 1, ''), (VIEW, REF | IX.REL_EXTENDED_BY, 3 * i + 1, e), (mem, DEF, 3 * i + 2, e)]
        sym[e] = ('View', IX.K_EXTENSION); sym[mem] = (f'{first}()', 16)
    return model({'Lists/V.swift': '\n'.join(lines) + '\n'}, {'Lists/V.swift': occ}, sym)


class LabelTests(unittest.TestCase):
    """map.json names a split file's declarations by label, so a label must come from the declaration's own text:
    with positional labels (`View(ext)#2`), an extension added above another took over its entry."""

    def test_an_extension_is_named_by_its_first_member(self):
        M = view_extensions(['modal', 'listStyle'])
        self.assertEqual([M.short_label(n) for n in M.nodes], ['View(ext)#modal()', 'View(ext)#listStyle()'])

    def test_a_member_less_extension_is_named_by_its_conformances(self):
        M = conformance_model()
        self.assertEqual(M.label('s:e:R'), 'Lists/R.swift::T(ext)#Renderable')

    def test_an_extension_added_above_keeps_its_neighbours_entries(self):
        before = view_extensions(['modal', 'listStyle'])
        files = {'Lists/V.swift': {'View(ext)#modal()': 'Base', 'View(ext)#listStyle()': 'Lists'}}
        after = view_extensions(['modal', 'added', 'listStyle'])
        asg, unmapped, kept = modulemap.resolve(after, rules(), files)
        self.assertEqual([asg[n] for n in before.nodes], ['Base', 'Lists'])
        self.assertEqual((asg['s:e:listStyle'], asg['s:e:modal']), ('Lists', 'Base'))
        self.assertEqual((unmapped, kept), (['s:e:added'], 0))

    def test_an_edited_extension_keeps_its_entry(self):
        # Its first member renamed (or one added above it): the one entry nothing claims is its own.
        files = {'Lists/V.swift': {'View(ext)#modal()': 'Base', 'View(ext)#listStyle()': 'Lists'}}
        asg, unmapped, kept = modulemap.resolve(view_extensions(['modal', 'listStyles']), rules(), files)
        self.assertEqual((asg['s:e:listStyles'], kept), ('Lists', 1))

    def test_an_edit_beside_an_addition_is_ambiguous_and_left_to_the_rules(self):
        files = {'Lists/V.swift': {'View(ext)#modal()': 'Lists', 'View(ext)#listStyle()': 'Lists',
                                   'View(ext)#gone()': 'Base'}}
        asg, _, kept = modulemap.resolve(view_extensions(['modal', 'listStyle', 'new1', 'new2']), rules(), files)
        self.assertEqual((asg['s:e:new1'], asg['s:e:new2'], kept), ('Lists', 'Lists', 0))


class PublicTests(unittest.TestCase):
    """Whether a declaration is or holds public API decides whether the assigner may lift it, and what public-above
    reports. `open` is also an identifier."""

    def test_public_and_open_count_only_as_modifiers(self):
        lines = ['struct Host {', '    private var open = false', '    func open() {}', '}',          # 1-4
                 'enum Phase {', '    case open', '}',                                              # 5-7
                 'open class Base {}',                                                              # 8
                 '@MainActor public final class Pub {}',                                            # 9
                 'struct Sets {', '    public private(set) var x = 0', '}',                         # 10-12
                 'struct Op {', '    public static prefix func - (a: Op) -> Op { a }', '}']         # 13-15
        decls = {1: 's:Host', 5: 's:Phase', 8: 's:Base', 9: 's:Pub', 10: 's:Sets', 13: 's:Op'}
        occ = [(u, DEF, ln, '') for ln, u in decls.items()]
        occ += [('s:Host.open', DEF, 2, 's:Host'), ('s:Host.open()', DEF, 3, 's:Host'), ('s:Phase.open', DEF, 6, 's:Phase'),
                ('s:Sets.x', DEF, 11, 's:Sets'), ('s:Op.-', DEF, 14, 's:Op')]
        sym = {u: (u[2:], IX.K_STRUCT) for u in decls.values()}
        sym.update({'s:Host.open': ('open', IX.K_VARIABLE), 's:Host.open()': ('open()', 16),
                    's:Phase.open': ('open', 13), 's:Sets.x': ('x', IX.K_VARIABLE), 's:Op.-': ('-(_:)', 17)})
        M = model({'Base/P.swift': '\n'.join(lines) + '\n'}, {'Base/P.swift': occ}, sym)
        self.assertEqual(sorted(M.public), ['s:Base', 's:Op', 's:Pub', 's:Sets'])


def two_module_model(pin_lists=False):
    """Base/A.swift uses Lists/L.swift's L, which only a Lists file declares."""
    srcs = {'Base/A.swift': 'struct A {\n    func f() { _ = L() }\n}\n', 'Lists/L.swift': 'struct L {}\n',
            'Lists/U.swift': 'struct U {\n    func g() { _ = L() }\n}\n'}
    occ = {'Base/A.swift': [('s:A', DEF, 1, ''), ('s:A.f', DEF, 2, 's:A'), ('s:L', REF, 2, 's:A.f')],
           'Lists/L.swift': [('s:L', DEF, 1, '')],
           'Lists/U.swift': [('s:U', DEF, 1, ''), ('s:U.g', DEF, 2, 's:U'), ('s:L', REF, 2, 's:U.g')]}
    sym = {'s:A': ('A', IX.K_STRUCT), 's:A.f': ('f()', 16), 's:L': ('L', IX.K_STRUCT), 's:U': ('U', IX.K_STRUCT),
           's:U.g': ('g()', 16)}
    files = [{'module': 'Lists', 'pin': pin_lists, 'match': r'^Lists/'}]
    return model(srcs, occ, sym), files


PIN_A = [{'module': 'Base', 'match': r'^Base/A\.swift::A$', 'why': ''}]


class AssignerTests(unittest.TestCase):
    def test_a_helper_used_below_comes_down(self):
        M, files = two_module_model()
        asg, _ = assigner.assign(M, rules(files=files, declarations=PIN_A))
        self.assertEqual(asg['s:L'], 'Base')
        self.assertEqual(asg['s:U'], 'Lists')

    def test_a_declaration_nothing_uses_goes_up_to_its_dependency(self):
        # The research assigner's order: lifting runs before pulling down, so a root (public API nothing inside
        # the module calls) follows what it uses. Plan section 4 reviewed the public blocks this moved.
        M, files = two_module_model()
        asg, _ = assigner.assign(M, rules(files=files))
        self.assertEqual((asg['s:A'], asg['s:L']), ('Lists', 'Lists'))

    def test_a_pinned_declaration_stays_and_the_reference_is_upward(self):
        M, files = two_module_model(pin_lists=True)
        R = rules(files=files, declarations=PIN_A)
        asg, _ = assigner.assign(M, R)
        self.assertEqual(asg['s:L'], 'Lists')
        ups = checks.upward(M, R, asg)
        self.assertEqual([(x.key, x.new) for x in ups], [('Base/A.swift::A -> Lists/L.swift::L', True)])

    def test_the_last_matching_declaration_rule_wins_for_the_assigner_and_the_map_reader_alike(self):
        # The r4 rules pin `Image.*Key` to Bitmaps and then three of those keys to Base. The assigner took the last
        # rule; map.json's reader, for a declaration the map does not name yet, took the first.
        src = 'struct ImageContentModeKey {}\nstruct ImageZoomKey {}\n'
        M = model({'Base/K.swift': src}, {'Base/K.swift': [('s:CM', DEF, 1, ''), ('s:Z', DEF, 2, '')]},
                  {'s:CM': ('ImageContentModeKey', IX.K_STRUCT), 's:Z': ('ImageZoomKey', IX.K_STRUCT)})
        R = rules(declarations=[{'module': 'Lists', 'match': r'^Base/K\.swift::Image.*Key$', 'why': ''},
                                {'module': 'Base', 'match': r'^Base/K\.swift::ImageContentModeKey$', 'why': ''}])
        asg, _ = assigner.assign(M, R)
        self.assertEqual(asg, {'s:CM': 'Base', 's:Z': 'Lists'})
        self.assertEqual(modulemap.resolve(M, R, {})[0], asg)

    def test_a_scheduled_refactor_is_reported_as_scheduled(self):
        M, files = two_module_model(pin_lists=True)
        R = rules(files=files, declarations=PIN_A,
                  scheduled=[{'id': 'K9', 'check': 'upward', 'from': '^Base/A', 'to': '::L$', 'why': ''}])
        asg, _ = assigner.assign(M, R)
        ups = checks.upward(M, R, asg)
        self.assertEqual([x.scheduled for x in ups], ['K9'])
        self.assertEqual(checks.stale_rules(R, ups), [])

    def test_each_scheduled_entry_goes_stale_on_its_own(self):
        # Entries that share an id (K4 has an upward and a posix one; K6 a posix one per file) are separate items.
        M, files = two_module_model(pin_lists=True)
        R = rules(files=files, declarations=PIN_A,
                  scheduled=[{'id': 'K9', 'check': 'upward', 'from': '^Base/A', 'to': '::L$', 'why': ''},
                             {'id': 'K9', 'check': 'upward', 'from': '^Base/Landed', 'to': '.', 'why': ''}])
        asg, _ = assigner.assign(M, R)
        stale = checks.stale_rules(R, checks.upward(M, R, asg))
        self.assertEqual([x.key for x in stale], ['scheduled K9 upward ^Base/Landed'])

    def test_a_scheduled_entry_that_matches_nothing_is_stale(self):
        M, _ = two_module_model()
        R = rules(scheduled=[{'id': 'K9', 'check': 'upward', 'from': '^Nowhere', 'to': '.', 'why': ''}])
        self.assertEqual([x.check for x in checks.stale_rules(R, [])], ['rules'])


def conformance_model():
    """struct T: View in Base/T.swift; `extension T: Renderable` in Lists/R.swift; protocol Q in Base, declared on T
    from Lists/Q.swift."""
    srcs = {'Base/T.swift': 'struct T: View {\n' + '    let a = 1\n' * 8 + '}\nprotocol Q {}\n',
            'Lists/R.swift': 'extension T: Renderable {}\n',
            'Lists/Q.swift': 'extension T: Q {}\n'}
    occ = {'Base/T.swift': [('s:T', DEF, 1, ''), ('s:10TUIkitView4ViewP', REF | IX.REL_BASE_OF, 1, 's:T'),
                            ('s:Q', DEF, 11, '')],
           'Lists/R.swift': [('s:e:R', DEF, 1, ''), ('s:T', REF | IX.REL_EXTENDED_BY, 1, 's:e:R'),
                             ('s:10TUIkitView10RenderableP', REF | IX.REL_BASE_OF, 1, 's:e:R')],
           'Lists/Q.swift': [('s:e:Q', DEF, 1, ''), ('s:T', REF | IX.REL_EXTENDED_BY, 1, 's:e:Q'),
                             ('s:Q', REF | IX.REL_BASE_OF, 1, 's:e:Q')]}
    sym = {'s:T': ('T', IX.K_STRUCT), 's:Q': ('Q', IX.K_PROTOCOL), 's:e:R': ('T', IX.K_EXTENSION),
           's:e:Q': ('T', IX.K_EXTENSION), 's:10TUIkitView4ViewP': ('View', IX.K_PROTOCOL),
           's:10TUIkitView10RenderableP': ('Renderable', IX.K_PROTOCOL)}
    return model(srcs, occ, sym)


class ConformanceTests(unittest.TestCase):
    def setUp(self):
        self.M = conformance_model()
        self.R = rules(files=[{'module': 'Lists', 'pin': True, 'match': r'^Lists/'}])
        self.asg = {'s:T': 'Base', 's:Q': 'Base', 's:e:R': 'Lists', 's:e:Q': 'Lists'}

    def test_renderable_out_of_the_view_conformance_s_sight(self):
        ws = checks.witnesses(self.M, self.R, self.asg, {'View': {'Renderable'}})
        self.assertEqual(len(ws), 1)
        self.assertIn('T: View is declared in Base', ws[0].message)

    def test_a_conformance_in_a_module_owning_neither(self):
        own = checks.owns_neither(self.M, self.R, self.asg)
        self.assertEqual([x.key for x in own],
                         ['T: Q @ Lists/Q.swift::T(ext)#Q', 'T: Renderable @ Lists/R.swift::T(ext)#Renderable'])
        own = checks.owns_neither(self.M, self.R, dict(self.asg, **{'s:e:R': 'Base', 's:e:Q': 'Base'}))
        self.assertEqual(own, [])

    def test_the_assigner_ties_conformances_to_their_type(self):
        R = rules(files=[{'module': 'Lists', 'pin': False, 'match': r'^Lists/'}])
        asg, _ = assigner.assign(self.M, R)
        self.assertEqual(asg['s:e:R'], 'Base')
        self.assertEqual(asg['s:e:Q'], 'Base')


def public_above_model():
    """ListStyle in Base; `.automatic` on it from Lists; style sugar whose `where` clause names a Lists type; and a
    View modifier in a Base file."""
    srcs = {'Base/S.swift': 'public protocol ListStyle {}\n',
            'Lists/D.swift': 'public struct DefaultListStyle: ListStyle {}\n',
            'Lists/E.swift': 'public extension ListStyle {\n    static var automatic: Int { 0 }\n}\n',
            'Lists/F.swift': 'public extension ListStyle where Self == DefaultListStyle {\n    static var plain: Int { 0 }\n}\n',
            'Base/V.swift': 'extension View {\n    public func listStyle() {}\n}\n'}
    occ = {'Base/S.swift': [('s:LS', DEF, 1, '')],
           'Lists/D.swift': [('s:DLS', DEF, 1, ''), ('s:LS', REF | IX.REL_BASE_OF, 1, 's:DLS')],
           'Lists/E.swift': [('s:e:A', DEF, 1, ''), ('s:LS', REF | IX.REL_EXTENDED_BY, 1, 's:e:A'),
                             ('s:A.automatic', DEF, 2, 's:e:A')],
           'Lists/F.swift': [('s:e:B', DEF, 1, ''), ('s:LS', REF | IX.REL_EXTENDED_BY, 1, 's:e:B'),
                             ('s:DLS', REF, 1, 's:e:B'), ('s:B.plain', DEF, 2, 's:e:B')],
           'Base/V.swift': [('s:e:V', DEF, 1, ''), (VIEW, REF | IX.REL_EXTENDED_BY, 1, 's:e:V'),
                            ('s:V.listStyle', DEF, 2, 's:e:V')]}
    sym = {'s:LS': ('ListStyle', IX.K_PROTOCOL), 's:DLS': ('DefaultListStyle', IX.K_STRUCT),
           's:e:A': ('ListStyle', IX.K_EXTENSION), 's:e:B': ('ListStyle', IX.K_EXTENSION),
           's:e:V': ('View', IX.K_EXTENSION), 's:A.automatic': ('automatic', IX.K_VARIABLE),
           's:B.plain': ('plain', IX.K_VARIABLE), 's:V.listStyle': ('listStyle()', 16), VIEW: ('View', IX.K_PROTOCOL)}
    asg = {'s:LS': 'Base', 's:DLS': 'Lists', 's:e:A': 'Lists', 's:e:B': 'Lists', 's:e:V': 'Lists'}
    return model(srcs, occ, sym), asg


class PublicAboveTests(unittest.TestCase):
    def test_both_forms_and_what_is_exempt(self):
        M, asg = public_above_model()
        keys = [x.key for x in checks.public_above(M, rules(), asg)]
        # `.automatic` is ListStyle's API declared above it; `.plain` names DefaultListStyle (Lists) in its where
        # clause, so it is Lists' own; the View modifier was carried from its file's module (Base) up to Lists.
        self.assertEqual(keys, ['Base/V.swift::View(ext)#listStyle()', 'Lists/E.swift::ListStyle(ext)#automatic'])

    def test_a_declaration_rule_is_a_chosen_placement_and_lists_its_members(self):
        # Chosen, so not new; but reported, accepted with the rule's reason, so `-v` lists every public member of the
        # block. Exempting it outright hid the layout trio inside the block the r4 rules pin to TUIkitBitmaps.
        M, asg = public_above_model()
        R = rules(declarations=[{'module': 'Lists', 'match': r'^Base/V\.swift::View\(ext\)$', 'why': 'list styling'}])
        xs = checks.public_above(M, R, asg)
        self.assertEqual([(x.key, x.new) for x in xs], [('Base/V.swift::View(ext)#listStyle()', False),
                                                        ('Lists/E.swift::ListStyle(ext)#automatic', True)])
        self.assertEqual(xs[0].message, 'public API on View placed in Lists by a declarations rule, above its file\'s '
                                        'Base: Base/V.swift::View(ext)#listStyle() (public: listStyle())')
        self.assertEqual(xs[0].accepted, r'declarations rule ^Base/V\.swift::View\(ext\)$: list styling')

    def test_a_copied_label_pins_that_declaration_alone(self):
        # The label `explain` and the findings print (with its `#first-member` discriminator), copied into a rule.
        M, asg = public_above_model()
        R = rules(declarations=[{'module': 'Lists', 'match': r'^Base/V\.swift::View\(ext\)#listStyle\(\)$', 'why': ''}])
        self.assertEqual([(x.key, x.new) for x in checks.public_above(M, R, asg)],
                         [('Base/V.swift::View(ext)#listStyle()', False), ('Lists/E.swift::ListStyle(ext)#automatic', True)])

    def test_every_public_member_of_a_flagged_block_is_listed(self):
        # A block's label names its first member only; the skeptic of the refined plan found `.focusSection` and
        # three layout modifiers moving module unseen inside lifted blocks. Each finding now lists them all.
        lines = ['extension View {',                                          # 1
                 '    func helper() {}',                                      # 2  internal
                 '    public func statusBarItems<T>(_ items: T) { let x = 0 }',  # 3  (its parameters and locals are not)
                 '    public var focus: Int { 0 }',                           # 4  (its getter is not a member)
                 '    private func hidden() {}',                              # 5
                 '    public struct Inner {',                                 # 6
                 '        public init() {}',                                  # 7
                 '        var x = 0',                                         # 8  internal member of a public type
                 '    }',                                                     # 9
                 '    public func focusSection() {}',                         # 10
                 '}',                                                         # 11
                 'public extension ListStyle {',                              # 12
                 '    static func a() {}',                                    # 13 public: the extension is
                 '    fileprivate static func b() {}',                        # 14
                 '    package static func c() {}',                            # 15
                 '    static var d: Int { 0 }',                               # 16
                 '}']                                                         # 17
        occ = [('s:e:V', DEF, 1, ''), (VIEW, REF | IX.REL_EXTENDED_BY, 1, 's:e:V'), ('s:V.helper', DEF, 2, 's:e:V'),
               ('s:V.sbi', DEF, 3, 's:e:V'), ('s:V.sbi.T', DEF, 3, 's:V.sbi'), ('s:V.sbi.t', DEF, 3, 's:V.sbi'),
               ('s:V.sbi.local', DEF, 3, 's:V.sbi'), ('s:V.focus', DEF, 4, 's:e:V'),
               ('s:V.focus.get', DEF | IX.IMPLICIT, 4, 's:V.focus'), ('s:V.hidden', DEF, 5, 's:e:V'),
               ('s:V.Inner', DEF, 6, 's:e:V'), ('s:V.Inner.init', DEF, 7, 's:V.Inner'), ('s:V.Inner.x', DEF, 8, 's:V.Inner'),
               ('s:V.fs', DEF, 10, 's:e:V'),
               ('s:e:L', DEF, 12, ''), ('s:LS', REF | IX.REL_EXTENDED_BY, 12, 's:e:L'), ('s:L.a', DEF, 13, 's:e:L'),
               ('s:L.b', DEF, 14, 's:e:L'), ('s:L.c', DEF, 15, 's:e:L'), ('s:L.d', DEF, 16, 's:e:L'),
               ('s:L.d.get', DEF, 16, 's:L.d')]
        sym = {'s:e:V': ('View', IX.K_EXTENSION), VIEW: ('View', IX.K_PROTOCOL), 's:V.helper': ('helper()', 16),
               's:V.sbi': ('statusBarItems(_:)', 16), 's:V.sbi.T': ('T', IX.K_TYPEALIAS, IX.SK_GENERIC_PARAMETER),
               's:V.sbi.t': ('items', IX.K_PARAMETER), 's:V.sbi.local': ('x', IX.K_VARIABLE),
               's:V.focus': ('focus', IX.K_VARIABLE),
               's:V.focus.get': ('getter:focus', 16), 's:V.hidden': ('hidden()', 16), 's:V.Inner': ('Inner', IX.K_STRUCT),
               's:V.Inner.init': ('init()', 22), 's:V.Inner.x': ('x', IX.K_VARIABLE), 's:V.fs': ('focusSection()', 16),
               's:e:L': ('ListStyle', IX.K_EXTENSION), 's:LS': ('ListStyle', IX.K_PROTOCOL), 's:L.a': ('a()', 18),
               's:L.b': ('b()', 18), 's:L.c': ('c()', 18), 's:L.d': ('d', IX.K_VARIABLE), 's:L.d.get': ('getter:d', 18)}
        M = model({'Base/V.swift': '\n'.join(lines) + '\n', 'Base/S.swift': 'public protocol ListStyle {}\n'},
                  {'Base/V.swift': occ, 'Base/S.swift': [('s:LS', DEF, 1, '')]}, sym)
        self.assertEqual(M.public_members, {'s:e:V': ['statusBarItems(_:)', 'focus', 'Inner', 'Inner.init()', 'focusSection()'],
                                            's:e:L': ['a()', 'd']})
        xs = checks.public_above(M, rules(), {'s:e:V': 'Lists', 's:e:L': 'Lists', 's:LS': 'Base'})
        self.assertEqual([x.message for x in xs], [
            'public API on View carried from Base up to Lists by the assigner: Base/V.swift::View(ext)#helper() '
            '(public: statusBarItems(_:), focus, Inner, Inner.init(), focusSection())',
            'public API of ListStyle (Base) is declared in Lists: Base/V.swift::ListStyle(ext)#a() (public: a(), d)'])

    def test_a_public_member_of_an_internal_nested_type_is_not_listed(self):
        lines = ['extension View {',                          # 1
                 '    struct Hidden {',                       # 2  internal
                 '        public func x() {}',                # 3  so x is not public API
                 '    }',                                     # 4
                 '    public struct Shown {',                 # 5
                 '        public func y() {}',                # 6
                 '        struct Deeper { public func z() {} }',  # 7  internal inside a public type
                 '    }',                                     # 8
                 '}']                                         # 9
        occ = [('s:e:V', DEF, 1, ''), (VIEW, REF | IX.REL_EXTENDED_BY, 1, 's:e:V'), ('s:H', DEF, 2, 's:e:V'),
               ('s:H.x', DEF, 3, 's:H'), ('s:S', DEF, 5, 's:e:V'), ('s:S.y', DEF, 6, 's:S'), ('s:D', DEF, 7, 's:S'),
               ('s:D.z', DEF, 7, 's:D')]
        sym = {'s:e:V': ('View', IX.K_EXTENSION), VIEW: ('View', IX.K_PROTOCOL), 's:H': ('Hidden', IX.K_STRUCT),
               's:H.x': ('x()', 16), 's:S': ('Shown', IX.K_STRUCT), 's:S.y': ('y()', 16), 's:D': ('Deeper', IX.K_STRUCT),
               's:D.z': ('z()', 16)}
        M = model({'Base/V.swift': '\n'.join(lines) + '\n'}, {'Base/V.swift': occ}, sym)
        self.assertEqual(M.public_members, {'s:e:V': ['Shown', 'Shown.y()']})
        self.assertIn('s:e:V', M.public)          # the block still counts as holding public API, as before

    @staticmethod
    def blocks(*members):
        """Base/V.swift: one `extension View` block per argument, holding those public methods in order."""
        lines, occ, sym = [], [], {VIEW: ('View', IX.K_PROTOCOL)}
        for b, ms in enumerate(members):
            e = f's:e:{b}'
            occ += [(e, DEF, len(lines) + 1, ''), (VIEW, REF | IX.REL_EXTENDED_BY, len(lines) + 1, e)]
            lines.append('extension View {')
            for m in ms:
                occ.append((f's:{m}', DEF, len(lines) + 1, e)); sym[f's:{m}'] = (f'{m}()', 16)
                lines.append(f'    public func {m}() {{}}')
            lines.append('}')
            sym[e] = ('View', IX.K_EXTENSION)
        return model({'Base/V.swift': '\n'.join(lines) + '\n'}, {'Base/V.swift': occ}, sym)

    S2 = [{'id': 'S2', 'check': 'public-above', 'from': r'^Base/V\.swift::View\(ext\)', 'to': r'^focus\(\)$', 'why': ''}]

    def report(self, M, R, asg):
        fs = checks.run_all(M, R, asg, '/nonexistent')
        return ([(x.key, x.scheduled, x.new) for x in fs if x.check == 'public-above'],
                [x.key for x in fs if x.check == 'rules'])

    def test_a_split_is_scheduled_while_the_block_holds_the_member_and_stale_once_it_left(self):
        # Refined plan S2: `.focusSection` rides in the `.statusBarItems` block, accepted in Chrome, until A4 splits it.
        acc = [{'check': 'public-above', 'key': 'Base/V.swift::View(ext)#status()', 'why': 'chrome'}]
        M = self.blocks(['status', 'focus'])
        self.assertEqual(self.report(M, rules(accepted=acc, scheduled=self.S2), {'s:e:0': 'Lists'}),
                         ([('Base/V.swift::View(ext)#status()', 'S2', False)], []))
        M = self.blocks(['status'], ['focus'])             # A4's split: focus stays in its file's module
        self.assertEqual(self.report(M, rules(accepted=acc, scheduled=self.S2), {'s:e:0': 'Lists', 's:e:1': 'Base'}),
                         ([('Base/V.swift::View(ext)#status()', None, False)], [r'scheduled S2 public-above ^Base/V\.swift::View\(ext\)']))
        # A split that left the member above its file's module is not done: the entry follows the member.
        self.assertEqual(self.report(M, rules(accepted=acc, scheduled=self.S2), {'s:e:0': 'Lists', 's:e:1': 'Lists'}),
                         ([('Base/V.swift::View(ext)#status()', None, False), ('Base/V.swift::View(ext)#focus()', 'S2', False)], []))

    def test_the_summary_counts_a_scheduled_and_accepted_finding_once(self):
        acc = [{'check': 'public-above', 'key': 'Base/V.swift::View(ext)#status()', 'why': 'chrome'},
               {'check': 'public-above', 'key': 'Base/V.swift::View(ext)#other()', 'why': 'chrome'}]
        M = self.blocks(['status', 'focus'], ['other'])
        fs = checks.run_all(M, rules(accepted=acc, scheduled=self.S2), {'s:e:0': 'Lists', 's:e:1': 'Lists'}, '/nonexistent')
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            modulemap.report(fs, rules(), False, False)
        self.assertIn('public-above     0 new   (scheduled S2 1; accepted 1)', out.getvalue())

    def test_a_split_scheduled_for_one_member_does_not_hide_the_rest_of_an_unreviewed_block(self):
        M = self.blocks(['status', 'focus'])
        self.assertEqual(self.report(M, rules(scheduled=self.S2), {'s:e:0': 'Lists'}),
                         ([('Base/V.swift::View(ext)#status()', 'S2', True)], []))

    def test_a_split_out_block_a_broad_rule_still_catches_keeps_the_split_open(self):
        # Refined plan S1: TUIkitBitmaps' rule pins `Views/Image.swift::...View\(ext\)`, every View block of the file, so
        # a block split out for the layout trio lands in Bitmaps again unless a later, narrower rule places it.
        s1 = [{'id': 'S1', 'check': 'public-above', 'from': r'^Base/V\.swift::View\(ext\)', 'to': r'^aspect\(\)$', 'why': ''}]
        broad = {'module': 'Lists', 'match': r'^Base/V\.swift::View\(ext\)$', 'why': 'image options'}
        M = self.blocks(['options'], ['aspect'])
        R = rules(declarations=[broad], scheduled=s1)
        asg, _ = assigner.assign(M, R)
        self.assertEqual(self.report(M, R, asg), ([('Base/V.swift::View(ext)#options()', None, False),
                                                   ('Base/V.swift::View(ext)#aspect()', 'S1', False)], []))
        narrow = {'module': 'Base', 'match': r'^Base/V\.swift::View\(ext\)#aspect\(\)$', 'why': 'S1 landed'}
        R = rules(declarations=[broad, narrow], scheduled=s1)
        asg, _ = assigner.assign(M, R)
        self.assertEqual(self.report(M, R, asg), ([('Base/V.swift::View(ext)#options()', None, False)],
                                                  [r'scheduled S1 public-above ^Base/V\.swift::View\(ext\)']))

    def test_an_accepted_placement_is_not_new(self):
        M, asg = public_above_model()
        R = rules(accepted=[{'check': 'public-above', 'key': 'Lists/E.swift::ListStyle(ext)#automatic', 'why': 'x'}])
        fs = [x for x in checks.run_all(M, R, asg, '/nonexistent') if x.check == 'public-above']
        self.assertEqual([(x.key, x.new) for x in fs],
                         [('Base/V.swift::View(ext)#listStyle()', True), ('Lists/E.swift::ListStyle(ext)#automatic', False)])


class PosixAndUmbrellaTests(unittest.TestCase):
    def test_unguarded_posix_outside_the_app_module(self):
        srcs = {'Base/T.swift': 'func f() { isatty(0) }\n#if canImport(Darwin)\nfunc g() { isatty(1) }\n#endif\n',
                'App/A.swift': 'func h() { isatty(2) }\n'}
        occ = {'Base/T.swift': [('s:f', DEF, 1, ''), ('c:@F@isatty', REF, 1, 's:f'), ('s:g', DEF, 3, ''),
                                ('c:@F@isatty', REF, 3, 's:g')],
               'App/A.swift': [('s:h', DEF, 1, ''), ('c:@F@isatty', REF, 1, 's:h')]}
        sym = {'s:f': ('f()', 12), 's:g': ('g()', 12), 's:h': ('h()', 12), 'c:@F@isatty': ('isatty(_:)', 12)}
        M = model(srcs, occ, sym)
        R = rules()
        xs = checks.posix(M, R, {'s:f': 'Base', 's:g': 'Base', 's:h': 'App'})
        self.assertEqual([x.key for x in xs], ['Base/T.swift::f() uses isatty'])

    def test_informational_posix_is_reported_but_not_new(self):
        # The owner relaxed the Windows rule (2026-10-07): with `informational`, a POSIX use outside the app module is
        # still listed, accepted with that reason; a scheduled refactor stays scheduled.
        srcs = {'Base/T.swift': 'func f() { isatty(0) }\nfunc g() { getpid() }\n'}
        occ = {'Base/T.swift': [('s:f', DEF, 1, ''), ('c:@F@isatty', REF, 1, 's:f'), ('s:g', DEF, 2, ''),
                                ('c:@F@getpid', REF, 2, 's:g')]}
        sym = {'s:f': ('f()', 12), 's:g': ('g()', 12), 'c:@F@isatty': ('isatty(_:)', 12), 'c:@F@getpid': ('getpid()', 12)}
        M = model(srcs, occ, sym)
        R = rules(posix={'c_symbols': ['isatty', 'getpid'], 'swift_symbols': [], 'imports': [], 'informational': 'relaxed'},
                  scheduled=[{'id': 'K6', 'check': 'posix', 'from': r'^Base/T\.swift::g', 'to': '^getpid$', 'why': ''}])
        xs = {x.key: x for x in checks.posix(M, R, {'s:f': 'Base', 's:g': 'Base'})}
        self.assertEqual(sorted(xs), ['Base/T.swift::f() uses isatty', 'Base/T.swift::g() uses getpid'])
        self.assertEqual((xs['Base/T.swift::f() uses isatty'].new, xs['Base/T.swift::f() uses isatty'].accepted), (False, 'relaxed'))
        self.assertEqual((xs['Base/T.swift::g() uses getpid'].scheduled, xs['Base/T.swift::g() uses getpid'].accepted), ('K6', None))

    def test_the_shipped_list_has_pid_t(self):
        # Plan section 4's K6: Windows signatures must not use pid_t. TerminalHost.swift had 13 unguarded uses until
        # step B2 spelled them Int32 (decisions B-SPB2-1).
        src = 'struct H {\n    let pid: pid_t?\n}\n'
        M = model({'Base/H.swift': src}, {'Base/H.swift': [('s:H', DEF, 1, ''), ('s:H.pid', DEF, 2, 's:H'),
                                                            ('c:@T@pid_t', REF, 2, 's:H.pid')]},
                  {'s:H': ('H', IX.K_STRUCT), 's:H.pid': ('pid', IX.K_VARIABLE), 'c:@T@pid_t': ('pid_t', IX.K_TYPEALIAS)})
        R = Rules.load(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'rules.json'))
        self.assertEqual([x.key for x in checks.posix(M, R, {'s:H': R.default})], ['Base/H.swift::H uses pid_t'])

    def test_k6_landed_as_the_plan_says_clears_its_findings(self):
        def findings(cond):
            src = f'func f() {{\n#if {cond}\nreturn\n#else\ngetpid()\n#endif\n}}\n'
            M = model({'Base/T.swift': src}, {'Base/T.swift': [('s:f', DEF, 1, ''), ('c:@F@getpid', REF, 5, 's:f')]},
                      {'s:f': ('f()', 12), 'c:@F@getpid': ('getpid()', 12)})
            R = rules(posix={'c_symbols': ['getpid'], 'swift_symbols': [], 'imports': []})
            return [x.key for x in checks.posix(M, R, {'s:f': 'Base'})]
        self.assertEqual(findings('canImport(WASILibc)'), ['Base/T.swift::f() uses getpid'])
        self.assertEqual(findings('canImport(WASILibc) || os(Windows)'), [])

    def test_the_umbrella_holds_only_imports(self):
        srcs = {'Exports.swift': '@_exported import Base\nlet x = 1\n'}
        M = model(srcs, {'Exports.swift': [('s:x', DEF, 2, '')]}, {'s:x': ('x', 13)})
        xs = checks.umbrella(M, rules(), {'s:x': 'X'})
        self.assertEqual(len(xs), 2)

    def test_the_umbrella_re_exports_every_module_carved_above_the_default_by_name(self):
        # Step B5's shape: Lists and App are carved out above Base, and Tables above Lists, re-exporting it (as
        # TUIkitColorPicker re-exports TUIkitNavigation until step C1). An umbrella without Lists still reaches it,
        # through Tables, so nothing fails to compile: only this check notices, and it names the module.
        def keys(umbrella, lists='@_exported import Base\n'):
            srcs = {'Exports.swift': umbrella, 'Lists/Exports.swift': lists,
                    'Tables/Exports.swift': '@_exported import Base\n@_exported import Lists\n',
                    'App/Exports.swift': '@_exported import Base\n', 'Base/B.swift': 'import Darwin\nfunc b() {}\n'}
            return [x.key for x in checks.umbrella(model(srcs, {}, {}), rules(), {})]
        self.assertEqual(keys('@_exported import App\n@_exported import Base\n@_exported import Tables\n'),
                         ['X does not re-export Lists'])
        self.assertEqual(keys('@_exported import Base\n'),
                         ['X does not re-export App', 'X does not re-export Lists', 'X does not re-export Tables'])
        self.assertEqual(keys('@_exported import App\n@_exported import Lists\n@_exported import Tables\n'), [])
        # A module the default still compiles re-exports nothing, and is not asked for; nor is the default itself.
        self.assertEqual(keys('@_exported import App\n@_exported import Tables\n', lists='func l() {}\n'), [])

    def test_every_form_of_an_import_is_one(self):
        # One reading of an import line for the three checks that look at imports. The `import Darwin` check missed
        # an access-level import and a second attribute; the umbrella took `@_exported public import` for code.
        srcs = {'Base/A.swift': 'internal import Darwin\nfunc f() {}\n',
                'Base/B.swift': '@preconcurrency @_implementationOnly import Darwin\nfunc g() {}\n',
                'Base/C.swift': '@_spi(Unsafe) import struct Darwin.timeval\nfunc h() {}\n',
                'Base/D.swift': 'import DarwinExtras\nfunc k() {}\n',
                'Exports.swift': '@_exported public import Base\n@_exported import struct Base.S\n'}
        occ = {f'Base/{c}.swift': [(f's:{c}', DEF, 2, '')] for c in 'ABCD'}
        M = model(srcs, occ, {f's:{c}': (f'{c.lower()}()', 12) for c in 'ABCD'})
        xs = checks.posix(M, rules(), {f's:{c}': 'Base' for c in 'ABCD'})
        self.assertEqual([x.key for x in xs], ['Base/A.swift imports Darwin', 'Base/B.swift imports Darwin',
                                               'Base/C.swift imports Darwin'])
        self.assertEqual(checks.umbrella(M, rules(), {f's:{c}': 'Base' for c in 'ABCD'}), [])
        self.assertEqual(SS.import_of('@preconcurrency @_exported import Core'), ('Core', True, ''))
        self.assertEqual(SS.import_of('import Core; let x = 1'), ('Core', False, '; let x = 1'))
        self.assertEqual(SS.import_of('let imported = 1'), None)


def lower_model():
    """Base/S.swift's S uses TUIkitCore's Lock twice and TUIkitView's AppState once; Lists/L.swift's L uses AppState;
    both use Foundation's Date, which no lower module defines."""
    srcs = {'Base/S.swift': 'struct S {\n    let l = Lock()\n    func f() { _ = Lock(); _ = AppState.shared; _ = Date() }\n}\n',
            'Lists/L.swift': 'struct L {\n    func g() { _ = AppState.shared; _ = Date() }\n}\n'}
    occ = {'Base/S.swift': [('s:S', DEF, 1, ''), ('s:S.l', DEF, 2, 's:S'), ('s:Core.Lock', REF, 2, 's:S.l'),
                            ('s:S.f', DEF, 3, 's:S'), ('s:Core.Lock', REF, 3, 's:S.f'),
                            ('s:View.AppState', REF, 3, 's:S.f'), ('s:Foundation.Date', REF, 3, 's:S.f')],
           'Lists/L.swift': [('s:L', DEF, 1, ''), ('s:L.g', DEF, 2, 's:L'), ('s:View.AppState', REF, 2, 's:L.g'),
                             ('s:Foundation.Date', REF, 2, 's:L.g')]}
    sym = {'s:S': ('S', IX.K_STRUCT), 's:S.l': ('l', IX.K_VARIABLE), 's:S.f': ('f()', 16), 's:L': ('L', IX.K_STRUCT),
           's:L.g': ('g()', 16), 's:Core.Lock': ('Lock', IX.K_STRUCT), 's:View.AppState': ('AppState', IX.K_CLASS),
           's:Foundation.Date': ('Date', IX.K_STRUCT)}
    M = model(srcs, occ, sym)
    M.lower_owner = {'s:Core.Lock': 'TUIkitCore', 's:View.AppState': 'TUIkitView'}
    M.lower_visible = M.lower_modules = {'TUIkitCore', 'TUIkitView'}
    return M, {'s:S': 'Base', 's:L': 'Lists'}


def lower_rules(**extra):
    R = rules(**extra)
    data = dict(R.data)
    data['modules'] = [dict(m, lower=['TUIkitCore']) if m['name'] == 'Base' else m for m in data['modules']]
    return Rules(data)


class LowerTests(unittest.TestCase):
    """A module may use only the lower modules its `lower` list names: a side module compiles beside TUIkitView,
    so it must not start using it (refined plan, step A1')."""

    def test_a_lower_module_the_list_does_not_name(self):
        M, asg = lower_model()
        xs = checks.lower(M, lower_rules(), asg)
        # Base names TUIkitCore only: Lock is allowed, AppState is not. Lists has no list, so it may use every
        # lower module. Date is defined by no lower module (the SDK), so it is not this check's business.
        self.assertEqual([(x.key, x.weight, x.line) for x in xs], [('Base/S.swift::S uses TUIkitView.AppState', 1, 3)])
        self.assertIn("Base's lower list does not name TUIkitView", xs[0].message)

    def test_one_finding_per_declaration_and_symbol_weighed_by_its_references(self):
        M, asg = lower_model()
        R = lower_rules()
        R.lower['Base'] = {'TUIkitView'}
        self.assertEqual([(x.key, x.weight) for x in checks.lower(M, R, asg)], [('Base/S.swift::S uses TUIkitCore.Lock', 2)])

    def test_a_scheduled_refactor_and_its_stale_entry(self):
        M, asg = lower_model()
        sched = [{'id': 'R1', 'check': 'lower', 'from': r'^Base/S\.swift::S$', 'to': r'^TUIkitView\.AppState$', 'why': ''}]
        fs = checks.run_all(M, lower_rules(scheduled=sched), asg, '/nonexistent')
        self.assertEqual([(x.check, x.scheduled, x.new) for x in fs if x.check in ('lower', 'rules')], [('lower', 'R1', False)])
        M.lower_owner = {}                  # R1 landed: Base no longer uses AppState
        fs = checks.run_all(M, lower_rules(scheduled=sched), asg, '/nonexistent')
        self.assertEqual([x.key for x in fs if x.check == 'rules'], [r'scheduled R1 lower ^Base/S\.swift::S$'])

    def test_a_lower_list_may_not_name_a_module_of_the_map(self):
        with self.assertRaises(SystemExit):
            rules(modules=[{'name': 'Base', 'deps': [], 'lower': ['Lists']}, {'name': 'Lists', 'deps': ['Base']}])

    def test_owners_are_the_lower_modules_definitions(self):
        files = {'/p/Sources/TUIkitCore/Lock.swift': [('s:Lock', DEF, 1, ''), ('s:Date', REF, 2, 's:Lock')],
                 '/p/Sources/TUIkitView/AppState.swift': [('s:AppState', DEF, 1, ''), ('s:Lock', REF, 3, 's:AppState')]}
        dirs = {'TUIkitCore': '/p/Sources/TUIkitCore/', 'TUIkitView': '/p/Sources/TUIkitView/'}
        sym = {'s:Lock': ('Lock', IX.K_STRUCT), 's:AppState': ('AppState', IX.K_CLASS), 's:Date': ('Date', IX.K_STRUCT)}
        self.assertEqual(model_mod.lower_owners(files, dirs, sym),
                         ({'s:Lock': 'TUIkitCore', 's:AppState': 'TUIkitView'}, {'s:Lock': 'Lock', 's:AppState': 'AppState'}))

    def test_a_lower_symbol_is_named_by_the_types_it_sits_in(self):
        # Two `shared` in TUIkitView: one on AppState, one added to Theme by an extension. A bare name made them one
        # finding, and R1's pattern for AppState's covered any other `shared` too.
        files = {'/p/V/A.swift': [('s:AppState', DEF, 1, ''), ('s:AppState.shared', DEF, 2, 's:AppState'),
                                  ('s:AppState.shared.get', DEF | IX.IMPLICIT, 2, 's:AppState.shared'),
                                  ('s:e:Theme', DEF, 4, ''), ('s:Theme.shared', DEF, 5, 's:e:Theme')]}
        sym = {'s:AppState': ('AppState', IX.K_CLASS), 's:AppState.shared': ('shared', IX.K_VARIABLE),
               's:AppState.shared.get': ('getter:shared', 19), 's:e:Theme': ('Theme', IX.K_EXTENSION),
               's:Theme.shared': ('shared', IX.K_VARIABLE)}
        owner, names = model_mod.lower_owners(files, {'TUIkitView': '/p/V/'}, sym)
        self.assertEqual(names, {'s:AppState': 'AppState', 's:AppState.shared': 'AppState.shared',
                                 's:AppState.shared.get': 'AppState.getter:shared', 's:e:Theme': 'Theme',
                                 's:Theme.shared': 'Theme.shared'})
        src = 'struct S {\n    func f() { _ = AppState.shared; _ = Theme.shared }\n}\n'
        M = model({'Base/S.swift': src},
                  {'Base/S.swift': [('s:S', DEF, 1, ''), ('s:S.f', DEF, 2, 's:S'), ('s:AppState.shared', REF, 2, 's:S.f'),
                                    ('s:Theme.shared', REF, 2, 's:S.f')]},
                  {'s:S': ('S', IX.K_STRUCT), 's:S.f': ('f()', 16), **sym})
        M.lower_owner, M.lower_name = owner, names
        sched = [{'id': 'R1', 'check': 'lower', 'from': r'^Base/S\.swift::S$', 'to': r'^TUIkitView\.AppState\.shared$',
                  'why': ''}]
        xs = checks.lower(M, lower_rules(scheduled=sched), {'s:S': 'Base'})
        self.assertEqual([(x.key, x.scheduled) for x in xs], [('Base/S.swift::S uses TUIkitView.AppState.shared', 'R1'),
                                                              ('Base/S.swift::S uses TUIkitView.Theme.shared', None)])

    def test_one_answer_to_which_lower_module_defines_a_symbol(self):
        # The `lower` check and owns-neither's module_of ask the same question. The index answers it, and sees what a
        # lower module adds to an SDK type (no TUIkit prefix in its USR); the USR's prefix is the fallback.
        M, asg = lower_model()
        M.lower_owner['s:Sa10TUIkitViewE4FlagV'] = 'TUIkitView'
        self.assertEqual(assigner.module_of(M, asg, 's:Sa10TUIkitViewE4FlagV'), 'TUIkitView')
        self.assertEqual(assigner.module_of(M, asg, 's:View.AppState'), 'TUIkitView')
        self.assertEqual(assigner.module_of(M, asg, 's:10TUIkitCore4LockV'), 'TUIkitCore')
        self.assertEqual(assigner.module_of(M, asg, 's:Foundation.Date'), None)
        self.assertEqual(assigner.module_of(M, asg, 's:S'), 'Base')

    def test_the_lower_modules_are_what_the_sources_import_and_what_that_re_exports(self):
        # Example and Stress import TUIkit and sit beside it too; reading their index cost ~0.6-0.9 s for nothing.
        with tempfile.TemporaryDirectory() as top:
            files = {'X/A.swift': '// import Commented\nimport Foundation\n@preconcurrency import View\n',
                     'View/V.swift': '@_exported import Core\nimport Styling\n', 'Core/C.swift': 'struct C {}\n',
                     'Styling/S.swift': 'struct S {}\n', 'Example/E.swift': 'import X\n', 'Commented/K.swift': ''}
            for rel, text in files.items():
                os.makedirs(os.path.join(top, os.path.dirname(rel)), exist_ok=True)
                with open(os.path.join(top, rel), 'w') as fh: fh.write(text)
            lexed = [SS.lex(files['X/A.swift'])]
            # View's plain import of Styling is View's own business: X cannot see Styling through it.
            self.assertEqual(model_mod.visible_modules(top, 'X', lexed), {'View', 'Core'})
            # Attributes with arguments, and `@_exported` after another attribute, are imports too.
            lexed = [SS.lex('@_spi(Internals) import View\n')]
            with open(os.path.join(top, 'View/V.swift'), 'w') as fh:
                fh.write('@preconcurrency @_exported import Core\n@_spi(X) @_exported public import Styling\n')
            self.assertEqual(model_mod.visible_modules(top, 'X', lexed), {'View', 'Core', 'Styling'})

    def test_by_directory_the_maps_own_modules_are_not_lower_ones(self):
        # Since A5 the map's modules sit beside the lower ones (Sources/TUIkitLists beside Sources/TUIkitView): an
        # import of one of its own, once carved, must not make it a lower module of the map.
        with tempfile.TemporaryDirectory() as top:
            files = {'Base/A.swift': 'import View\n', 'Lists/L.swift': 'import Base\nimport Core\n',
                     'View/V.swift': '', 'Core/C.swift': '', 'Example/E.swift': 'import X\n'}
            for rel, text in files.items():
                os.makedirs(os.path.join(top, os.path.dirname(rel)), exist_ok=True)
                with open(os.path.join(top, rel), 'w') as fh: fh.write(text)
            lexed = [SS.lex(files['Base/A.swift']), SS.lex(files['Lists/L.swift'])]
            self.assertEqual(model_mod.visible_modules(top, {'Base', 'Lists', 'X'}, lexed), {'View', 'Core'})

    def test_by_directory_only_the_maps_directories_are_read_and_labelled_by_them(self):
        with tempfile.TemporaryDirectory() as root:
            files = {'Sources/Base/Views/A.swift': 'struct A {}\n', 'Sources/Lists/Views/L.swift': 'struct L {}\n',
                     'Sources/X/Exports.swift': '@_exported import Core\n', 'Sources/Core/C.swift': 'struct C {}\n',
                     'Sources/Example/E.swift': 'import X\n'}
            for rel, text in files.items():
                os.makedirs(os.path.join(root, os.path.dirname(rel)), exist_ok=True)
                with open(os.path.join(root, rel), 'w') as fh: fh.write(text)
            calls = []

            def read(store, modules, prefixes, lib=None):
                calls.append((modules, prefixes))
                return {}, {}, {}
            with mock.patch.object(model_mod.IX, 'read', side_effect=read):
                M = Model.load(root, 'Sources', '/store', modules=['Base', 'Lists', 'Tables', 'App', 'X'])
            self.assertEqual(M.files, ['Base/Views/A.swift', 'Lists/Views/L.swift', 'X/Exports.swift'])
            # Every unit of the map's directories, whichever module compiled it: TUIkit, before a carve.
            modules, prefixes = calls[0]
            self.assertEqual(modules, {'TUIkit', 'Base', 'Lists', 'Tables', 'App', 'X'})
            self.assertEqual(sorted(p[len(os.path.realpath(root)):] for p in prefixes),
                             ['/Sources/Base/', '/Sources/Lists/', '/Sources/X/'])
            self.assertEqual(M.lower_visible, {'Core'})

    def test_a_lower_list_naming_no_module_the_index_knows_is_an_error(self):
        M, asg = lower_model()
        R = lower_rules()
        R.lower['Base'] = {'TUIkitCore', 'TUIkitVeiw'}
        with mock.patch.object(modulemap.Model, 'load', return_value=M), \
                mock.patch.object(modulemap.Rules, 'load', return_value=R), \
                mock.patch.object(modulemap.indexstore, 'find_store', return_value='/nonexistent'), \
                contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaisesRegex(SystemExit, 'TUIkitVeiw'):
                modulemap.main(['check'])


    def test_a_lower_module_the_index_lacks_is_an_error_even_when_no_list_names_it(self):
        # Base's list leaves TUIkitImage out, which denies it. A store without TUIkitImage's units would let Base's uses
        # of it through, with no finding and no error.
        M, asg = lower_model()
        M.lower_visible = {'TUIkitCore', 'TUIkitView', 'TUIkitImage'}
        with mock.patch.object(modulemap.Model, 'load', return_value=M), \
                mock.patch.object(modulemap.Rules, 'load', return_value=lower_rules()), \
                mock.patch.object(modulemap.indexstore, 'find_store', return_value='/nonexistent'), \
                contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaisesRegex(SystemExit, 'no definitions of TUIkitImage'):
                modulemap.main(['check'])
            M.lower_modules = set(M.lower_visible)
            self.assertEqual(modulemap.main(['check']), 1)       # read: the check runs (AppState in Base is new)


class IndexStoreTests(unittest.TestCase):
    def test_a_string_ref_is_read_by_its_length(self):
        # libIndexStore's strings point into its buffers with a length and no NUL; `ab` here is followed by a NUL
        # and more bytes inside the length, so a read up to the NUL loses them.
        buf = ctypes.create_string_buffer(b'ab\x00cd', 5)
        r = IX._SR()
        ctypes.c_void_p.from_address(ctypes.addressof(r)).value = ctypes.addressof(buf)
        r.length = 5
        self.assertEqual(IX._s(r), 'ab\x00cd')
        r.length = 2
        self.assertEqual(IX._s(r), 'ab')

    def test_the_store_a_build_wrote_last_is_read(self):
        # Two triples: the store made first was written last. Its directory is older; its newest unit is newer.
        with tempfile.TemporaryDirectory() as root:
            def store(triple, made, written):
                units = os.path.join(root, '.build', triple, 'debug', 'index', 'store', 'v5', 'units')
                os.makedirs(units)
                u = os.path.join(units, 'unit'); open(u, 'w').close(); os.utime(u, (written, written))
                for d in (units, os.path.dirname(units), os.path.dirname(os.path.dirname(units))):
                    os.utime(d, (made, made))
                return os.path.dirname(os.path.dirname(units))
            t = time.time()
            old = store('arm64-apple-macosx', made=t - 3600, written=t - 60)
            store('x86_64-apple-macosx', made=t - 600, written=t - 500)
            self.assertEqual(IX.find_store(root), old)

    def test_the_newest_unit_of_each_file_of_the_modules_asked_for(self):
        # The `lower` check reads several modules in one pass: a set of names and a tuple of prefixes.
        infos = [('u1', 'Core', '/p/Core/A.swift', 10.0), ('u2', 'Core', '/p/Core/A.swift', 20.0),
                 ('u3', 'View', '/p/View/B.swift', 30.0), ('u4', 'View', '/p/View/B.swift', 5.0),
                 ('u5', 'Example', '/p/Example/E.swift', 40.0),         # a module not asked for
                 ('u6', 'Core', '/elsewhere/Core/C.swift', 50.0),       # outside the prefixes
                 ('u7', 'Core', '/p/View/Odd.swift', 60.0)]             # under another asked-for module's prefix
        got = IX.newest_units(infos, {'Core', 'View'}, ('/p/Core/', '/p/View/'))
        self.assertEqual(got, {'/p/Core/A.swift': (20.0, 'u2'), '/p/View/B.swift': (30.0, 'u3'),
                               '/p/View/Odd.swift': (60.0, 'u7')})
        self.assertEqual(IX.newest_units(infos, 'Core', '/p/Core/'), {'/p/Core/A.swift': (20.0, 'u2')})

    def test_swift_build_s_store_is_found(self):
        # `--build-system swiftbuild` (SwiftPM 6.4's default) writes the store into .build/out.
        with tempfile.TemporaryDirectory() as root:
            units = os.path.join(root, '.build', 'out', 'v5', 'units')
            os.makedirs(units); open(os.path.join(units, 'unit'), 'w').close()
            self.assertEqual(IX.find_store(root), os.path.join(root, '.build', 'out'))


class UncompiledTests(unittest.TestCase):
    """Since A5 TUIkitFoundation's `sources:` names directories (and until B2 TUIkitStrings' files below its own), so
    a file can sit in a module's directory and be compiled by no target. SwiftPM only warns about it, and CI does not fail on that
    warning; the module map, which reads what the build compiled, does."""

    def test_a_source_the_last_build_passed_over_is_uncompiled_and_one_newer_than_it_is_stale(self):
        src = {'Base/A.swift': 100.0, 'Base/Edited.swift': 300.0, 'Base/Left.swift': 100.0, 'Base/New.swift': 300.0}
        units = {'Base/A.swift': 200.0, 'Base/Edited.swift': 200.0}
        self.assertEqual(model_mod.unit_freshness(sorted(src), src, units, 200.0),
                         (['Base/Edited.swift', 'Base/New.swift'], ['Base/Left.swift']))
        # A file written in the second the build started is not held against it; an empty store, against nothing.
        self.assertEqual(model_mod.unit_freshness(['Base/A.swift'], {'Base/A.swift': 199.5}, {}, 200.0),
                         (['Base/A.swift'], []))
        self.assertEqual(model_mod.unit_freshness(['Base/A.swift'], {'Base/A.swift': 1.0}, {}, None),
                         (['Base/A.swift'], []))

    def test_an_uncompiled_source_is_a_new_finding_that_a_gating_check_annotates(self):
        M, files = two_module_model()
        M.uncompiled = ['Lists/Left.swift']
        R = rules(files=files, declarations=PIN_A)
        asg, _ = assigner.assign(M, R)
        with tempfile.TemporaryDirectory() as root:
            xs = [x for x in checks.run_all(M, R, asg, root) if x.check == 'uncompiled']
        self.assertEqual([(x.key, x.file, x.new) for x in xs], [('Lists/Left.swift', 'Lists/Left.swift', True)])
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            self.assertEqual(len(modulemap.report(xs, R, True, False, 'error')), 1)
        self.assertIn('::error file=Sources/X/Lists/Left.swift,line=1,title=ModuleMap uncompiled::Lists/Left.swift is '
                      'compiled by no target', out.getvalue())


class CommandLineTests(unittest.TestCase):
    def annotations(self, n, level='warning'):
        fs = [checks.Finding('upward', f'k{i}', f'finding {i}', 'Base/A.swift', i + 1) for i in range(n)]
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            self.assertEqual(len(modulemap.report(fs, rules(), True, False, level)), n)
        return [ln for ln in out.getvalue().splitlines() if ln.startswith('::')]

    def test_annotations_past_github_s_ten_end_in_a_count(self):
        self.assertEqual(len(self.annotations(10)), 10)
        lines = self.annotations(23)
        self.assertEqual(len(lines), 10)
        self.assertIn('finding 8', lines[8])
        self.assertIn('::14 more new findings', lines[9])

    def test_a_gating_check_annotates_errors_and_a_warning_only_one_warnings(self):
        # CI gates on the check (no --exit-zero) since step A4: a new finding fails the step, and its annotation says
        # so. Under --exit-zero the same finding is a warning, as it was while the map was still being refined.
        self.assertTrue(all(ln.startswith('::error file=') for ln in self.annotations(3, 'error')))
        self.assertTrue(all(ln.startswith('::warning file=') for ln in self.annotations(3)))
        self.assertTrue(self.annotations(12, 'error')[-1].startswith('::error title=ModuleMap::3 more new findings'))

    def check_with_one_new_finding(self, *flags):
        """`check` through main() and run(), over a model whose checks report one new finding: (status, annotations)."""
        M, files = two_module_model()
        finding = checks.Finding('upward', 'k', 'a new finding', 'Base/A.swift', 2)
        out = io.StringIO()
        with tempfile.TemporaryDirectory() as store, \
                mock.patch.object(modulemap.Rules, 'load', return_value=rules(files=files, declarations=PIN_A)), \
                mock.patch.object(modulemap.Model, 'load', return_value=M), \
                mock.patch.object(modulemap.checks, 'run_all', return_value=[finding]), \
                contextlib.redirect_stdout(out):
            status = modulemap.main(['check', '--store', store, '--map', os.path.join(store, 'none.json'), *flags])
        return status, [ln for ln in out.getvalue().splitlines() if ln.startswith('::')]

    def test_a_new_finding_fails_a_gating_check_and_only_warns_under_exit_zero(self):
        # run() picks the level and the status from --exit-zero; report() only prints the level it is given.
        self.assertEqual(self.check_with_one_new_finding('--github'), (1, ['::error file=Sources/X/Base/A.swift,line=2,'
                                                                           'title=ModuleMap upward::a new finding']))
        status, lines = self.check_with_one_new_finding('--github', '--exit-zero')
        self.assertEqual((status, [ln.split(' ', 1)[0] for ln in lines]), (0, ['::warning']))

    def test_a_failure_of_the_tool_is_one_annotation_at_the_check_s_level(self):
        # A libIndexStore that will not load: nothing was checked. Under --exit-zero (a local run that only reports)
        # that is a warning and status 0; when the check gates, as CI's does, an error and status 1, so the failed step
        # says why. A gating run without --github raises, for the traceback.
        with tempfile.TemporaryDirectory() as store:
            args = ['check', '--store', store, '--lib', os.path.join(store, 'libIndexStore.dylib')]
            for flags, status, level in ((['--github', '--exit-zero'], 0, 'warning'), (['--github'], 1, 'error')):
                out = io.StringIO()
                with contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
                    self.assertEqual(modulemap.main(args + flags), status)
                self.assertIn(f'::{level} title=ModuleMap::modulemap failed, so nothing was checked: OSError',
                              out.getvalue())
            with self.assertRaises(OSError):
                modulemap.main(args)


if __name__ == '__main__':
    unittest.main()
