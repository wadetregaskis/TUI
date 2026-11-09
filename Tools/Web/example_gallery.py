#!/usr/bin/env python3
"""Adds the Example's pages and languages to the browser demo's manifest.

    Tools/Web/example_gallery.py SOURCES/Example SITE/manifest.json

`build.sh` runs it after writing the manifest, for the Example alone. The page
(`site/index.html`) offers what it finds under `gallery` as its start-page and
language pickers, and passes the chosen page in the variable `gallery.variable`
names, so the page itself knows nothing about the Example.

Read from the source rather than kept by hand, so that a page added to
`DemoPage` is offered by the next build:

- the pages are the cases of `enum DemoPage` (`ContentView.swift`), in order,
  less `menu`, which is where the app opens anyway;
- each page's title is the English string of its menu entry's key
  (`MainMenuPage.swift`, then the `en` tables under `Localization/`);
- the languages are the keys of `ExampleStrings.translations`' base table.

Stops with a message rather than writing a partial list when the source has
moved on from what it reads, so the build that would publish a broken picker
fails instead. Only the standard library, like the rest of `Tools/`.
"""
import json
import os
import re
import sys


def fail(message):
    sys.exit(f"example_gallery.py: {message}")


def read(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def page_names(sources):
    text = read(os.path.join(sources, "ContentView.swift"))
    body = re.search(r"enum DemoPage\b[^{]*\{(.*?)\n    (?:///|static|func|var)", text, re.S)
    if not body:
        fail("no `enum DemoPage` in ContentView.swift")
    names = re.findall(r"^\s*case (\w+)\s*$", body.group(1), re.M)
    if "menu" not in names:
        fail("`DemoPage` has no `menu` case")
    return [name for name in names if name != "menu"]


def menu_keys(sources):
    text = read(os.path.join(sources, "Pages", "MainMenuPage.swift"))
    return dict(re.findall(r'Entry\(page: \.(\w+), key: "([^"]+)"', text))


def english_strings(sources):
    """Every `"key": "value"` in an English table under `Localization/`."""
    strings = {}
    root = os.path.join(sources, "Localization")
    # A table starts at `static let en: [String: String] = [` or, in the
    # generated fragments, at `"en": [`; it runs to the next table's start.
    start = re.compile(r'static let (\w+): \[String: String\] = \[|^\s*"(\w+)": \[\s*$', re.M)
    for base, _, files in sorted(os.walk(root)):
        for name in sorted(files):
            if not name.endswith(".swift"):
                continue
            text = read(os.path.join(base, name))
            starts = list(start.finditer(text))
            for index, match in enumerate(starts):
                if (match.group(1) or match.group(2)) != "en":
                    continue
                end = starts[index + 1].start() if index + 1 < len(starts) else len(text)
                for key, value in re.findall(r'"([^"]+)": "((?:[^"\\]|\\.)*)"', text[match.end():end]):
                    strings.setdefault(key, value.replace('\\"', '"'))
    return strings


def languages(sources):
    text = read(os.path.join(sources, "Localization", "ExampleStrings.swift"))
    base = re.search(r"let base: \[String: \[String: String\]\] = \[(.*?)\]", text, re.S)
    if not base:
        fail("no base table in ExampleStrings.swift")
    codes = re.findall(r'"(\w+)": \w+', base.group(1))
    if "en" not in codes:
        fail("the Example's base table has no English")
    return codes


def main():
    if len(sys.argv) != 3:
        fail("usage: example_gallery.py SOURCES/Example SITE/manifest.json")
    sources, manifest_path = sys.argv[1:]
    keys, strings = menu_keys(sources), english_strings(sources)
    pages = []
    for name in page_names(sources):
        key = keys.get(name)
        if key is None:
            fail(f"page `{name}` has no entry in MainMenuPage.swift")
        if key not in strings:
            fail(f"no English string for `{key}`")
        pages.append({"name": name, "title": strings[key]})

    manifest = json.loads(read(manifest_path))
    manifest["gallery"] = {
        "variable": "TUI_EXAMPLE_PAGE",
        "pages": pages,
        "languages": languages(sources),
    }
    with open(manifest_path, "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=2, ensure_ascii=False)
    print(f"   {len(pages)} page(s), {len(manifest['gallery']['languages'])} language(s)")


if __name__ == "__main__":
    main()
