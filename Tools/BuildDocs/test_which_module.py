"""Tests for which_module.py, on hand-written symbol graphs: `python3 -m unittest discover -s Tools/BuildDocs`."""

import contextlib
import io
import json
import pathlib
import sys
import tempfile
import unittest
from unittest import mock

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

    def generate(self, *options):
        """Runs the script's main over the miniature; its exit status, its stderr, and the article or None."""
        describe = self.graphs / "describe.json"
        describe.write_text(json.dumps(DESCRIBE))
        template = self.graphs / "ModuleIndex.md"
        template.write_text(TEMPLATE)
        output = self.graphs / "Generated.md"
        errors = io.StringIO()
        # The miniature's umbrella is Kit, which declares nothing, as TUIkit's does.
        with mock.patch.object(which_module, "UMBRELLA", "Kit"), \
                contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(errors):
            status = which_module.main([str(self.graphs), "--describe", str(describe), "--template", str(template),
                                        "--output", str(output), *options])
        return status, errors.getvalue(), output.read_text() if output.exists() else None

    def test_every_product_module_with_rows_generates(self):
        status, _, article = self.generate()
        self.assertEqual(status, 0)
        self.assertIn("| KitLists | KitLists |", article)

    def test_a_product_module_without_a_row_fails(self):
        # As a module looks when the graphs missed it, or when it declares nothing on this platform.
        (self.graphs / "KitLists.symbols.json").write_text(json.dumps({"module": {"name": "KitLists"}, "symbols": []}))
        status, errors, article = self.generate()
        self.assertEqual(status, 1)
        self.assertIn("no symbols for KitLists", errors)
        self.assertIsNone(article)

    def test_a_module_allowed_to_be_empty_generates_without_it(self):
        # TUIkitAppKit off Apple platforms: all of it is `#if canImport(AppKit)`.
        (self.graphs / "KitLists.symbols.json").write_text(json.dumps({"module": {"name": "KitLists"}, "symbols": []}))
        status, errors, article = self.generate("--allow-empty", "KitLists")
        self.assertEqual(status, 0)
        self.assertIn("note: KitLists declares no public name", errors)
        self.assertNotIn("| KitLists |", article)
        self.assertIn("| KitTables | KitTables |", article)

    def test_the_summary_line_is_what_the_rendered_check_reads_back(self):
        match = which_module.SUMMARY_PATTERN.search(which_module.render(TEMPLATE, self.rows))
        self.assertIsNotNone(match)
        self.assertEqual(int(match.group(1).replace(",", "")), len(self.rows))


# DocC's render JSON, in the shape `docc convert` writes for an article (checked with Xcode 26.3's docc): a paragraph's
# inline content, and a table whose first row is its header and each of whose cells is a list of blocks.
def text(value):
    return {"type": "text", "text": value}


def code(value):
    return {"type": "codeVoice", "code": value}


def paragraph(*inlines):
    return {"type": "paragraph", "inlineContent": list(inlines)}


def table(rows):
    return {
        "type": "table",
        "header": "row",
        "rows": [[[paragraph(code(cell) if index and not column else text(cell))] for column, cell in enumerate(row)]
                 for index, row in enumerate(rows)],
    }


def page(*blocks):
    return {"kind": "article", "primaryContentSections": [{"kind": "content", "content": list(blocks)}]}


ROWS = [["List", "Structure", "KitLists", "KitLists"], ["Table", "Structure", "KitTables", "KitTables"]]


class RenderedIndexTests(unittest.TestCase):
    def test_the_templates_note_is_not_taken_for_the_index(self):
        # The template names modules in its prose, as the real one does ("`TUIkitTables` gives you `List` too"), so
        # the page that a build which skipped the generator renders holds a module's name all the same.
        template_page = page(
            paragraph(text("Look the name up below. "), code("TUIkitTables"), text(" gives you "), code("List"),
                      text(" too.")),
            paragraph(text("This copy of the page has no index.")),
        )
        self.assertIn("TUIkitTables", json.dumps(template_page))
        self.assertIn("no generated summary line", which_module.rendered_index_problem(template_page))

    def test_the_generated_index_passes(self):
        summary = which_module.SUMMARY.format(names=len(ROWS), modules=2)
        self.assertIsNone(which_module.rendered_index_problem(
            page(paragraph(text(summary)), table([which_module.COLUMNS] + ROWS))))

    def test_a_table_short_of_its_summary_line_fails(self):
        summary = which_module.SUMMARY.format(names=1_234, modules=2)
        rendered = page(paragraph(text(summary)), table([which_module.COLUMNS] + ROWS))
        problem = which_module.rendered_index_problem(rendered)
        self.assertEqual(problem, "its table has 2 rows where its summary line counts 1,234")

    def test_a_summary_line_without_the_table_fails(self):
        summary = which_module.SUMMARY.format(names=len(ROWS), modules=2)
        problem = which_module.rendered_index_problem(page(paragraph(text(summary)), table([["A", "B"]] + ROWS)))
        self.assertIn("no table headed Name, Kind, Module, Product", problem)

    def test_the_catalogs_template_has_neither_the_summary_line_nor_the_table(self):
        template = pathlib.Path(__file__).resolve().parents[2] / "Sources/TUIkit/TUIkit.docc/Articles/ModuleIndex.md"
        content = template.read_text()
        self.assertIsNone(which_module.SUMMARY_PATTERN.search(content))
        self.assertNotIn("| " + " | ".join(which_module.COLUMNS) + " |", content)

    def test_verify_rendered_sets_the_exit_status(self):
        with tempfile.TemporaryDirectory() as directory:
            good = pathlib.Path(directory) / "good.json"
            good.write_text(json.dumps(page(
                paragraph(text(which_module.SUMMARY.format(names=len(ROWS), modules=2))),
                table([which_module.COLUMNS] + ROWS))))
            bad = pathlib.Path(directory) / "bad.json"
            bad.write_text(json.dumps(page(paragraph(code("TUIkitTables")))))
            self.assertEqual(which_module.main(["--verify-rendered", str(good)]), 0)
            self.assertEqual(which_module.main(["--verify-rendered", str(bad)]), 1)
            self.assertEqual(which_module.main(["--verify-rendered", str(pathlib.Path(directory) / "none.json")]), 1)


if __name__ == "__main__":
    unittest.main()
