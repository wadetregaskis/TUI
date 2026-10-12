"""Tests for which_module.py, on hand-written symbol graphs: `python3 -m unittest discover -s Tools/BuildDocs`."""

import json
import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import which_module  # noqa: E402


def symbol(path, kind="swift.struct", display="Structure", access="public", extension=None, precise=None):
    entry = {
        "kind": {"identifier": kind, "displayName": display},
        "identifier": {"precise": precise or "s:" + "".join(path), "interfaceLanguage": "swift"},
        "pathComponents": path,
        "names": {"title": path[-1]},
        "accessLevel": access,
    }
    if extension:
        entry["swiftExtension"] = {"extendedModule": extension[0], "typeKind": extension[1]}
    return entry


METHOD = {"kind": "swift.method", "display": "Instance Method"}

# A miniature of the package: KitView declares `View` (a protocol, with a modifier of its own) and `Text` (a struct,
# with a member in an extension); KitLists declares `List`; KitTables declares `Table` and a `View` modifier in its
# extension graph of KitView; KitStrings has no product of its own, and KitFoundation re-exports it.
GRAPHS = {
    "KitView.symbols.json": [
        symbol(["View"], "swift.protocol", "Protocol"),
        symbol(["View", "padding()"], **METHOD, extension=("KitView", "swift.protocol")),
        symbol(["Text"]),
        symbol(["Text", "bold()"], **METHOD, extension=("KitView", "swift.struct")),
        symbol(["Text", "init(_:)"], "swift.init", "Initializer"),
        symbol(["_ViewCore"]),
        symbol(["Hidden"], access="internal"),
    ],
    "KitLists.symbols.json": [symbol(["List"])],
    "KitTables.symbols.json": [symbol(["Table"])],
    "KitTables@KitView.symbols.json": [
        symbol(["View", "tableStyle(_:)"], **METHOD, extension=("KitView", "swift.protocol"), precise="s:a"),
        # An overload: the same name again.
        symbol(["View", "tableStyle(_:)"], **METHOD, extension=("KitView", "swift.protocol"), precise="s:b"),
        # A protocol extension's member repeated on a conforming type.
        symbol(["Text", "tableStyle(_:)"], **METHOD, extension=("KitView", "swift.struct"),
               precise="s:a::SYNTHESIZED::s:Text"),
        # A type this extension declares inside `Text`, and its member: one row, the type's.
        symbol(["Text", "Cell"], extension=("KitView", "swift.struct")),
        symbol(["Text", "Cell", "width"], "swift.property", "Instance Property"),
        # An associated type's witness.
        symbol(["Text", "RowBody"], "swift.typealias", "Type Alias", extension=("KitView", "swift.struct")),
        symbol(["Text", "pipe|name"], **METHOD, extension=("KitView", "swift.struct")),
    ],
    "KitStrings.symbols.json": [symbol(["Localizer"], "swift.class", "Class")],
    "KitFoundation.symbols.json": [symbol(["Button"])],
    "Example.symbols.json": [symbol(["ExampleApp"])],
}

DESCRIBE = {
    "products": [
        {"name": name, "type": {"library": ["automatic"]}}
        for name in ("Kit", "KitView", "KitLists", "KitTables", "KitFoundation")
    ] + [{"name": "Example", "type": {"executable": None}}],
    "targets": [
        {"name": "Kit", "type": "library", "module_type": "SwiftTarget", "product_memberships": ["Kit"]},
        {"name": "KitView", "type": "library", "module_type": "SwiftTarget",
         "product_memberships": ["Kit", "KitView", "KitLists", "KitTables", "KitFoundation"]},
        {"name": "KitLists", "type": "library", "module_type": "SwiftTarget",
         "product_memberships": ["Kit", "KitLists", "KitTables"]},
        {"name": "KitTables", "type": "library", "module_type": "SwiftTarget",
         "product_memberships": ["Kit", "KitTables"]},
        {"name": "KitStrings", "type": "library", "module_type": "SwiftTarget",
         "product_memberships": ["Kit", "KitFoundation", "KitLists", "KitTables"]},
        {"name": "KitFoundation", "type": "library", "module_type": "SwiftTarget",
         "product_memberships": ["Kit", "KitFoundation", "KitLists", "KitTables"]},
        {"name": "CImage", "type": "library", "module_type": "ClangTarget", "product_memberships": ["Kit"]},
        {"name": "Example", "type": "executable", "module_type": "SwiftTarget", "product_memberships": ["Example"]},
    ],
}

TEMPLATE = """# Which Module Provides It

Intro.

## The index

A note for an ungenerated copy.
"""


class WhichModuleTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.graphs = pathlib.Path(self.directory.name)
        for name, symbols in GRAPHS.items():
            (self.graphs / name).write_text(json.dumps({"module": {"name": name.split("@")[0]}, "symbols": symbols}))
        # The umbrella is not one of the miniature's graphs; it declares nothing.
        self.products = which_module.products_by_module(DESCRIBE)
        self.rows = which_module.build_index(self.graphs, self.products)
        self.names = {(row[0], row[2]) for row in self.rows}

    def tearDown(self):
        self.directory.cleanup()

    def test_products_are_the_modules_own_or_the_smallest_that_contains_them(self):
        self.assertEqual(self.products["KitTables"], "KitTables")
        # KitStrings has no product; KitFoundation's is the smallest of the four that hold it.
        self.assertEqual(self.products["KitStrings"], "KitFoundation")
        self.assertNotIn("CImage", self.products)
        self.assertNotIn("Example", self.products)

    def test_a_modifier_another_module_adds_is_listed_under_that_module(self):
        self.assertIn(("View.tableStyle(_:)", "KitTables"), self.names)
        self.assertEqual(sum(1 for row in self.rows if row[0] == "View.tableStyle(_:)"), 1, "overloads share a row")

    def test_a_modules_own_protocol_extension_members_are_listed(self):
        self.assertIn(("View.padding()", "KitView"), self.names)

    def test_members_of_a_modules_own_concrete_types_are_found_through_the_type(self):
        self.assertIn(("Text", "KitView"), self.names)
        self.assertNotIn(("Text.bold()", "KitView"), self.names)
        self.assertNotIn(("Text.init(_:)", "KitView"), self.names)

    def test_plumbing_is_left_out(self):
        listed = {row[0] for row in self.rows}
        self.assertNotIn("_ViewCore", listed)
        self.assertNotIn("Hidden", listed)
        self.assertNotIn("Text.tableStyle(_:)", listed, "a SYNTHESIZED repeat")
        self.assertNotIn("Text.RowBody", listed, "an associated type's witness")
        self.assertNotIn("ExampleApp", listed, "an executable's")

    def test_a_type_declared_in_an_extension_covers_its_members(self):
        self.assertIn(("Text.Cell", "KitTables"), self.names)
        self.assertNotIn(("Text.Cell.width", "KitTables"), self.names)

    def test_a_module_without_a_product_names_the_product_that_brings_it(self):
        row = next(row for row in self.rows if row[0] == "Localizer")
        self.assertEqual(row[2:], ("KitStrings", "KitFoundation"))

    def test_rows_are_sorted_by_name_without_case(self):
        names = [row[0] for row in self.rows]
        self.assertEqual(names, sorted(names, key=str.lower))

    def test_the_article_keeps_the_template_up_to_the_heading_and_escapes_cells(self):
        article = which_module.render(TEMPLATE, self.rows)
        self.assertTrue(article.startswith("# Which Module Provides It\n\nIntro.\n\n## The index\n"))
        self.assertNotIn("ungenerated", article)
        self.assertIn("| `View.tableStyle(_:)` | Instance Method | KitTables | KitTables |", article)
        self.assertIn("`Text.pipe\\|name`", article)
        self.assertIn(f"{len(self.rows)} names from", article)

    def test_a_template_without_the_heading_is_an_error(self):
        with self.assertRaises(ValueError):
            which_module.render("# Title\n\nNo heading.\n", self.rows)


if __name__ == "__main__":
    unittest.main()
