"""Unit tests for the module map, on hand-written sources and occurrences: no index store, no build.

    python3 -m unittest discover -s Tools/ModuleMap
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import assigner  # noqa: E402
import checks  # noqa: E402
import indexstore as IX  # noqa: E402
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
    """A Model from {rel: text}, {rel: [(usr, roles, line, container)]} and {usr: (name, kind)}."""
    M = Model()
    M.files = sorted(sources)
    M.lexed = {f: SS.lex(t) for f, t in sources.items()}
    M.symbols = {u: (n, k, 0) for u, (n, k) in symbols.items()}
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

    def test_a_scheduled_refactor_is_reported_as_scheduled(self):
        M, files = two_module_model(pin_lists=True)
        R = rules(files=files, declarations=PIN_A,
                  scheduled=[{'id': 'K9', 'check': 'upward', 'from': '^Base/A', 'to': '::L$', 'why': ''}])
        asg, _ = assigner.assign(M, R)
        ups = checks.upward(M, R, asg)
        self.assertEqual([x.scheduled for x in ups], ['K9'])
        self.assertEqual(checks.stale_rules(R, ups), [])

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
                         ['T: Q @ Lists/Q.swift::T(ext)', 'T: Renderable @ Lists/R.swift::T(ext)'])
        own = checks.owns_neither(self.M, self.R, dict(self.asg, **{'s:e:R': 'Base', 's:e:Q': 'Base'}))
        self.assertEqual(own, [])

    def test_the_assigner_ties_conformances_to_their_type(self):
        R = rules(files=[{'module': 'Lists', 'pin': False, 'match': r'^Lists/'}])
        asg, _ = assigner.assign(self.M, R)
        self.assertEqual(asg['s:e:R'], 'Base')
        self.assertEqual(asg['s:e:Q'], 'Base')


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

    def test_the_umbrella_holds_only_imports(self):
        srcs = {'Exports.swift': '@_exported import Base\nlet x = 1\n'}
        M = model(srcs, {'Exports.swift': [('s:x', DEF, 2, '')]}, {'s:x': ('x', 13)})
        xs = checks.umbrella(M, rules(), {'s:x': 'X'})
        self.assertEqual(len(xs), 2)


if __name__ == '__main__':
    unittest.main()
