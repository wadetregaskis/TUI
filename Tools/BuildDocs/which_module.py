#!/usr/bin/env python3
"""Generate the "which module provides X" index: each public type, function and modifier, with its module and the
library product a client depends on to get it.

An app on the `TUIkit` product never needs this: `import TUIkit` is everything. An app or a library that depends on
per-module products does, because a name it uses without that module's product is an error that names no module
("cannot find 'Table' in scope", "value of type 'Text' has no member 'tableStyle'"), and the reference build-docs.sh
makes deliberately files every symbol under `TUIkit` (unify_symbol_graphs.py). So build-docs.sh runs this over the
same symbol graphs, before they are unified, and puts the index into its staged copy of the catalog as the article
ModuleIndex.md: generated with the reference, so it is never staler than the reference itself, and nothing in the
repository has to be regenerated when API changes.

Where a symbol comes from is in the graph's FILE NAME, which the unifier renames: `M.symbols.json` holds module M's
own declarations, and `M@N.symbols.json` M's extensions of module N's types (`View.tableStyle(_:)`, declared in
TUIkitTables on TUIkitView's `View`, is in `TUIkitTables@TUIkitView.symbols.json`).

What gets a row:
- every public top-level declaration of a module (types, protocols, functions, macros, global values);
- every public member a module declares on ANOTHER module's type (a modifier on `View`, an initializer on `Image`
  or `Color`), at any depth, unless it belongs to a type that module declares in that same extension (that type's
  own row covers it) or is a type alias (an associated type's witness, `ForEach.TableRowBody`);
- the members a module declares in an extension of one of its OWN protocols (`View`'s modifiers in TUIkitView), as
  a protocol's members are what one looks up by name; members of a module's own concrete types are found through
  the type.
Not: names with a component starting `_` (the framework's own plumbing, public only so its modules can share it), and
a protocol extension's members repeated on each conforming type (their identifiers say `::SYNTHESIZED::`).
Overloads share one row. A name declared by two modules (`View.toolbar(_:)`) has a row for each.

The product is read from `swift package describe --type json`: a module's own product where it has one, else the
smallest library product (other than the umbrella) that contains it, which for TUIkitStrings and
TUIkitTerminalHost is TUIkitFoundation, the module that re-exports them.

Usage:
    which_module.py SYMBOL_GRAPH_DIR --describe DESCRIBE_JSON --template ARTICLE [--output FILE]
                    [--allow-empty MODULE ...]
    which_module.py --verify-rendered PAGE_JSON

TEMPLATE is the catalog's own ModuleIndex.md. Everything up to and including its `## The index` heading is kept;
what follows it there (a note for a reader of an ungenerated copy) is replaced by the table.

Every library product's module must contribute a row, or the graphs did not cover it and the script fails, except a
module named with --allow-empty: one that declares nothing on the platform the docs are built on. build-docs.sh
names TUIkitAppKit off Apple platforms, since all of it is `#if canImport(AppKit)`.

--verify-rendered checks that DocC's render JSON of the page (`data/documentation/tuikit/moduleindex.json` in the
archive) is the generated index, not the template: that it holds the generated summary line, and a table under the
index's header with as many rows as that line counts. build-docs.sh runs it after converting. The template names
modules too (`TUIkitTables` gives you `List` too), so a search of the page for a module's name cannot tell them apart.

Python 3 standard library only.
"""

import argparse
import json
import pathlib
import re
import sys
from typing import Optional

HEADING = "## The index"
UMBRELLA = "TUIkit"
COLUMNS = ["Name", "Kind", "Module", "Product"]
# The line above the table, which only a generated page has; --verify-rendered reads the count back from it.
SUMMARY = (
    "{names:,} names from {modules} modules, generated from the symbol graphs of the build these pages were made from."
)
SUMMARY_PATTERN = re.compile(
    r"([\d,]+) names from (\d+) modules, generated from the symbol graphs of the build these pages were made from\."
)


def products_by_module(describe: dict) -> dict[str, str]:
    """Map each Swift library module to the product a client depends on to get it."""
    libraries = {p["name"] for p in describe["products"] if "library" in p["type"]}
    size: dict[str, int] = {name: 0 for name in libraries}
    for target in describe["targets"]:
        for product in target.get("product_memberships") or []:
            if product in size:
                size[product] += 1
    result: dict[str, str] = {}
    for target in describe["targets"]:
        if target.get("module_type") != "SwiftTarget" or target.get("type") != "library":
            continue
        name = target["name"]
        memberships = [p for p in (target.get("product_memberships") or []) if p in libraries]
        if not memberships:
            continue
        if name in libraries:
            result[name] = name
            continue
        candidates = [p for p in memberships if p != UMBRELLA] or memberships
        result[name] = min(candidates, key=lambda p: (size[p], p))
    return result


def rows_from_graph(path: pathlib.Path, module: str, extended: str) -> list[tuple[str, str]]:
    """The (name, kind) rows one graph file contributes."""
    graph = json.loads(path.read_text())
    symbols = [s for s in graph.get("symbols", []) if s.get("accessLevel") in ("public", "open")]
    # The types this graph declares, by path: a member of one of them is found through that type's own row.
    type_kinds = {"swift.struct", "swift.class", "swift.enum", "swift.protocol", "swift.typealias", "swift.actor"}
    declared_types = {tuple(s["pathComponents"]) for s in symbols if s["kind"]["identifier"] in type_kinds}
    rows = []
    for symbol in symbols:
        if "::SYNTHESIZED::" in symbol["identifier"]["precise"]:
            continue
        path_components = symbol["pathComponents"]
        if any(component.startswith("_") for component in path_components):
            continue
        parent = tuple(path_components[:-1])
        kind = symbol["kind"]["identifier"]
        if len(path_components) == 1:
            pass
        elif kind in ("swift.typealias", "swift.associatedtype"):
            # A member type alias is an associated type's witness (`ForEach.TableRowBody`), plumbing of a
            # conformance, not a name anyone spells.
            continue
        elif extended:
            # Another module's type: its members are this module's API, unless the parent is a type this
            # extension itself declares.
            if parent in declared_types:
                continue
        else:
            extension = symbol.get("swiftExtension")
            if not extension or extension.get("typeKind") != "swift.protocol" or len(path_components) != 2:
                continue
        rows.append((".".join(path_components), symbol["kind"]["displayName"]))
    return rows


def build_index(graph_dir: pathlib.Path, products: dict[str, str]) -> list[tuple[str, str, str, str]]:
    """Every row: (name, kind, module, product), sorted by name, overloads merged."""
    seen: set[tuple[str, str]] = set()
    rows = []
    for path in sorted(graph_dir.glob("*.symbols.json")):
        stem = path.name.removesuffix(".symbols.json")
        module, _, extended = stem.partition("@")
        if module not in products:
            continue
        for name, kind in rows_from_graph(path, module, extended):
            if (name, module) in seen:
                continue
            seen.add((name, module))
            rows.append((name, kind, module, products[module]))
    rows.sort(key=lambda row: (row[0].lower(), row[0], row[2]))
    return rows


def cell(text: str) -> str:
    """A table cell's code span: a `|` would end the cell, and a backtick the span."""
    text = text.replace("|", "\\|")
    if "`" in text:
        return "`` " + text + " ``"
    return "`" + text + "`"


def render(template: str, rows: list[tuple[str, str, str, str]]) -> str:
    index = template.find("\n" + HEADING + "\n")
    if index < 0:
        raise ValueError(f"the template has no '{HEADING}' heading")
    head = template[: index + len(HEADING) + 2]
    modules = sorted({row[2] for row in rows})
    lines = [
        head,
        SUMMARY.format(names=len(rows), modules=len(modules)),
        "",
        "| " + " | ".join(COLUMNS) + " |",
        "|" + "---|" * len(COLUMNS),
    ]
    for name, kind, module, product in rows:
        lines.append(f"| {cell(name)} | {kind} | {module} | {product} |")
    return "\n".join(lines) + "\n"


def plain_text(node) -> str:
    """The text of a piece of DocC render JSON: its inline content's text and code, run together."""
    if isinstance(node, list):
        return "".join(plain_text(item) for item in node)
    if not isinstance(node, dict):
        return ""
    if node.get("type") == "text":
        return node.get("text", "")
    if node.get("type") == "codeVoice":
        return node.get("code", "")
    return plain_text(node.get("inlineContent", []))


def rendered_index_problem(page: dict) -> Optional[str]:
    """Why DocC's render JSON of the ModuleIndex page is not the generated index, or None when it is."""
    paragraphs: list[str] = []
    tables: list[dict] = []

    def walk(node):
        if isinstance(node, list):
            for item in node:
                walk(item)
        elif isinstance(node, dict):
            if node.get("type") == "paragraph":
                paragraphs.append(plain_text(node))
            elif node.get("type") == "table":
                tables.append(node)
                return
            for value in node.values():
                walk(value)

    walk(page)
    summary = next((match for text in paragraphs if (match := SUMMARY_PATTERN.search(text))), None)
    if summary is None:
        return "it has no generated summary line (\"N names from M modules, generated from the symbol graphs …\")"
    index = next(
        (table for table in tables if table.get("rows") and [plain_text(c) for c in table["rows"][0]] == COLUMNS),
        None,
    )
    if index is None:
        return "it has no table headed " + ", ".join(COLUMNS)
    expected = int(summary.group(1).replace(",", ""))
    found = len(index["rows"]) - 1
    if found != expected or found == 0:
        return f"its table has {found:,} rows where its summary line counts {expected:,}"
    return None


def verify_rendered(path: pathlib.Path) -> int:
    if not path.exists():
        print(f"error: the module index page is missing ({path})", file=sys.stderr)
        return 1
    problem = rendered_index_problem(json.loads(path.read_text()))
    if problem:
        print(f"error: the module index page was not generated ({path}): {problem}", file=sys.stderr)
        return 1
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("graphs", type=pathlib.Path, nargs="?", help="the directory dump-symbol-graph wrote")
    parser.add_argument("--describe", type=pathlib.Path, help="`swift package describe --type json`")
    parser.add_argument("--template", type=pathlib.Path, help="the catalog's ModuleIndex.md")
    parser.add_argument("--output", type=pathlib.Path, help="where to write the article (default: stdout)")
    parser.add_argument("--allow-empty", action="append", default=[], metavar="MODULE",
                        help="a module that may declare no public name on this platform (repeat for several)")
    parser.add_argument("--verify-rendered", type=pathlib.Path, metavar="PAGE_JSON",
                        help="check that DocC's render JSON of the page is the generated index, and exit")
    args = parser.parse_args(argv)
    if args.verify_rendered:
        return verify_rendered(args.verify_rendered)
    if not (args.graphs and args.describe and args.template):
        parser.error("SYMBOL_GRAPH_DIR, --describe and --template are required to generate the index")

    products = products_by_module(json.loads(args.describe.read_text()))
    rows = build_index(args.graphs, products)
    empty = sorted(m for m in products if m != UMBRELLA and not any(row[2] == m for row in rows))
    missing = [m for m in empty if m not in args.allow_empty]
    if missing:
        print("error: no symbols for " + ", ".join(missing) + " — did dump-symbol-graph cover them?", file=sys.stderr)
        return 1
    for module in empty:
        print(f"note: {module} declares no public name on this platform, so the index has no row for it",
              file=sys.stderr)
    article = render(args.template.read_text(), rows)
    if args.output:
        args.output.write_text(article)
        print(f"module index: {len(rows)} names from {len({row[2] for row in rows})} modules -> {args.output}")
    else:
        sys.stdout.write(article)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
