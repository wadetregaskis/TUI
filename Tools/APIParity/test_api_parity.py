"""Tests for the pure comparison half of `api_parity.py`.

    cd Tools/APIParity && python3 -m unittest
    python3 -m unittest discover -s Tools/APIParity     # from the repository root

These need no SDK and no build: every function exercised here takes the
symbol dictionaries `load_symbols` would have produced (key -> kind), so each
case spells out exactly the vocabulary it is about.
"""
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import api_parity  # noqa: E402  (the path has to be set up first)


def symbols(*keys):
    """A symbol dictionary shaped like `load_symbols`' result."""
    return {key: "func" for key in keys}


class LabelDeviationTests(unittest.TestCase):

    def test_a_swiftui_declaration_is_never_a_misspelling_of_another(self):
        # `toolbar(removing:)` is exact SwiftUI API. That TUI lacks
        # `toolbar(content:)` does not make the one it has a misspelling.
        swiftui = symbols("View.toolbar(content:)", "View.toolbar(removing:)")
        tuikit = symbols("View.toolbar(removing:)")
        self.assertEqual(api_parity.label_deviations(swiftui, tuikit), {})

    def test_a_genuine_misspelling_is_still_flagged(self):
        swiftui = symbols("View.onHover(perform:)")
        tuikit = symbols("View.onHover(action:)")
        self.assertEqual(
            api_parity.label_deviations(swiftui, tuikit),
            {"View.onHover(perform:)": ["View.onHover(action:)"]})

    def test_only_the_misspelt_candidates_are_kept(self):
        # Two TUI overloads with the same name and arity: one is SwiftUI's
        # own `toolbar(removing:)`, the other is TUI's own spelling.
        swiftui = symbols("View.toolbar(content:)", "View.toolbar(removing:)")
        tuikit = symbols("View.toolbar(removing:)", "View.toolbar(items:)")
        self.assertEqual(
            api_parity.label_deviations(swiftui, tuikit),
            {"View.toolbar(content:)": ["View.toolbar(items:)"]})

    def test_a_different_arity_is_not_a_misspelling(self):
        # A missing overload with more or fewer arguments is an absence, not a
        # misspelling of the overload that exists.
        swiftui = symbols("Button.init(_:image:action:)", "View.alert(_:isPresented:)")
        tuikit = symbols("Button.init(_:action:)", "View.alert(_:isPresented:actions:message:)")
        self.assertEqual(api_parity.label_deviations(swiftui, tuikit), {})

    def test_a_call_that_compiles_is_not_a_deviation(self):
        # `border(_:width:)` binds to `border(_:style:width:)` by skipping the
        # defaulted `style:`; `border(style:width:)` sharing its arity does not
        # make the working call a misspelling.
        swiftui = symbols("View.border(_:width:)")
        tuikit = symbols("View.border(_:style:width:)", "View.border(style:width:)")
        compatible = {"View.border(_:width:)": "View.border(_:style:width:)"}
        self.assertEqual(
            api_parity.label_deviations(swiftui, tuikit, compatible), {})
        self.assertEqual(
            api_parity.label_deviations(swiftui, tuikit),
            {"View.border(_:width:)": ["View.border(style:width:)"]})

    def test_a_symbol_tuikit_has_is_not_a_deviation(self):
        swiftui = symbols("View.padding(_:)", "View.padding(_:_:)")
        tuikit = symbols("View.padding(_:)", "View.padding(_:_:)")
        self.assertEqual(api_parity.label_deviations(swiftui, tuikit), {})


class SynthesizedConformanceTests(unittest.TestCase):

    def graph(self, directory, relationships):
        """One module's symbol graph: a public struct `Angle`, with the
        `init(from:)` a synthesized `Decodable` leaves behind and NOT the
        `encode(to:)` a synthesized `Encodable` leaves out."""
        def symbol(precise, kind, *path):
            return {"identifier": {"precise": precise}, "kind": {"identifier": kind},
                    "pathComponents": list(path), "accessLevel": "public"}
        graph = {"symbols": [symbol("s:3TUI5AngleV", "swift.struct", "Angle"),
                             symbol("s:3TUI5AngleV4fromACs7Decoder_p_tKcfc",
                                    "swift.init", "Angle", "init(from:)")],
                 "relationships": relationships}
        with open(os.path.join(directory, "TUI.symbols.json"), "w") as handle:
            json.dump(graph, handle)

    def test_a_codable_type_has_encode_to(self):
        with tempfile.TemporaryDirectory() as directory:
            self.graph(directory, [
                {"kind": "conformsTo", "source": "s:3TUI5AngleV", "target": "s:SE"},
                {"kind": "conformsTo", "source": "s:3TUI5AngleV", "target": "s:Se"}])
            loaded = api_parity.load_symbols(directory, ["TUI"])
        self.assertIn("Angle.encode(to:)", loaded)
        self.assertIn("Angle.init(from:)", loaded)

    def test_a_raw_valued_enum_has_raw_value(self):
        with tempfile.TemporaryDirectory() as directory:
            self.graph(directory, [
                {"kind": "conformsTo", "source": "s:3TUI5AngleV", "target": "s:SY"}])
            loaded = api_parity.load_symbols(directory, ["TUI"])
        self.assertEqual(loaded.get("Angle.rawValue"), "var")

    def test_without_the_conformance_there_is_no_encode_to(self):
        with tempfile.TemporaryDirectory() as directory:
            self.graph(directory, [
                {"kind": "conformsTo", "source": "s:3TUI5AngleV", "target": "s:SQ"}])
            loaded = api_parity.load_symbols(directory, ["TUI"])
        self.assertNotIn("Angle.encode(to:)", loaded)


class DeprecationTests(unittest.TestCase):

    def test_how_a_symbol_is_deprecated(self):
        how = api_parity.deprecation
        self.assertEqual(how({"availability": [{"domain": "macOS", "deprecated": {"major": 26}}]}), "macOS 26.0")
        self.assertEqual(how({"availability": [{"domain": "macOS", "deprecated": {"major": 100000}}]}), "soft")
        self.assertEqual(how({"availability": [{"domain": "*", "isUnconditionallyDeprecated": True}]}),
                         "unconditionally")
        # Another platform's deprecation is not macOS's, and unavailable is absent, not deprecated.
        self.assertIsNone(how({"availability": [{"domain": "iOS", "deprecated": {"major": 17}}]}))
        self.assertIsNone(how({"availability": [{"domain": "macOS", "isUnconditionallyUnavailable": True}]}))

    def test_a_hit_is_exact_or_source_compatible(self):
        deprecated = {"View.frame()": [{"kind": "func", "how": "unconditionally", "decl": "func frame()"}],
                      "View.gone(_:)": [{"kind": "func", "how": "soft", "decl": "func gone(_:)"}],
                      "View.animation(_:)": [{"kind": "func", "how": "macOS 12.0", "decl": "func animation(_:)"}]}
        tuikit = symbols("View.frame(width:height:)", "View.animation(_:)")
        defaults = {"View.frame(width:height:)": [[True, True]], "View.animation(_:)": [[False]]}
        hits = api_parity.deprecated_hits(deprecated, symbols("View.animation(_:)"), tuikit, defaults)
        self.assertEqual([(h["key"], h["tuikit"], h["shared"]) for h in hits],
                         [("View.animation(_:)", "View.animation(_:)", True),
                          ("View.frame()", "View.frame(width:height:)", False)])


if __name__ == "__main__":
    unittest.main()
