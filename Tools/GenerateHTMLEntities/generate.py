#!/usr/bin/env python3
"""Regenerates Sources/TUIStrings/Rendering/HTMLEntityTable.generated.swift: every HTML named
character reference that ends in a semicolon, the 2,125 Foundation's Markdown parser knows, as
TUI's Markdown parse decodes them.

The names and values come from Python's own `html.entities.html5`, WHATWG's list, so the tool
needs nothing but Python 3 and downloads nothing. The 106 legacy names without a semicolon are
left out: CommonMark, and so Foundation, requires the semicolon.

Usage (from the repository root): python3 Tools/GenerateHTMLEntities/generate.py
"""

import html.entities
import os
import sys

BLOCK_SIZE = 16
OUTPUT = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "..", "Sources", "TUIStrings", "Rendering",
    "HTMLEntityTable.generated.swift")


def escaped(value: str) -> str:
    """`value` as Swift string-literal text: every scalar as a `\\u{…}` escape, so combining marks,
    controls (`&NewLine;`, `&Tab;`) and quotation marks all read the same way."""
    return "".join("\\u{%X}" % ord(scalar) for scalar in value)


def wrapped(values):
    """`values` as array-literal elements, about 96 columns to a line."""
    lines, line = [], ""
    for value in values:
        piece = f"{value},"
        if not line:
            line = piece
        elif len(line) + 1 + len(piece) > 96:
            lines.append(line)
            line = piece
        else:
            line += " " + piece
    if line:
        lines.append(line)
    return "\n".join("        " + l for l in lines)


def main() -> int:
    entities = {name[:-1]: value for name, value in html.entities.html5.items() if name.endswith(";")}
    names = sorted(entities, key=lambda name: name.encode())

    # Names, front-coded as FrontCodedNames reads them.
    name_lines, name_starts, name_length = [], [], 0
    for index, name in enumerate(names):
        raw = name.encode()
        if index % BLOCK_SIZE == 0:
            name_starts.append(name_length)
            name_lines.append(name)
            name_length += len(raw)
        else:
            previous = names[index - 1].encode()
            shared = 0
            while shared < min(len(previous), len(raw)) and previous[shared] == raw[shared]:
                shared += 1
            assert shared < 0x80, name
            name_lines.append("\\u{%X}" % shared + name[shared:])
            name_length += 1 + len(raw) - shared
        name_length += 1
    name_starts.append(name_length)

    # Values, in name order, each ended by U+0000 (a newline cannot end them: `&NewLine;` is one),
    # with the start of every block of BLOCK_SIZE.
    value_lines, value_starts, value_length = [], [], 0
    for index, name in enumerate(names):
        if index % BLOCK_SIZE == 0:
            value_starts.append(value_length)
        value = entities[name]
        value_lines.append(escaped(value) + "\\u{0}\\")
        value_length += len(value.encode()) + 1
    value_starts.append(value_length)
    # A multi-line literal's last line may not end in a line continuation.
    value_lines[-1] = value_lines[-1][:-1]

    name_block = "\n".join("        " + line for line in name_lines)
    value_block = "\n".join("        " + line for line in value_lines)
    source = f'''//  🖥️ TUI — A Terminal UI framework for Swift
//  HTMLEntityTable.generated.swift
//
//  Created by Wade Tregaskis
//  License: MIT

//  GENERATED — do not edit by hand.
//
//  Produced by `Tools/GenerateHTMLEntities/generate.py` from Python
//  {sys.version_info.major}.{sys.version_info.minor}'s `html.entities.html5` (WHATWG's list): the
//  {len(names):,} named character references that end in a semicolon, every one
//  Foundation's Markdown parser knows. Names sorted and front-coded in blocks of
//  {BLOCK_SIZE} (`FrontCodedNames`); values in the same order, each ended by
//  U+0000, with the start of each block. All compile-time data: nothing is
//  parsed or allocated until a name is looked up.

// swiftlint:disable file_length

extension HTMLEntities {{
    /// How many names there are.
    static let count = {len(names)}

    /// Names per block of ``nameBlocks`` and ``valueBlocks``.
    static let blockSize = {BLOCK_SIZE}

    /// Every name, without its `&` and `;`, sorted by its bytes and front-coded
    /// as ``FrontCodedNames`` reads them.
    static let nameBlocks: StaticString = """
{name_block}

        """

    /// The byte offset of each block in ``nameBlocks``, and of its end.
    static let nameBlockStarts: [UInt32] = [
{wrapped(name_starts)}
    ]

    /// Every name's value, in the names' order, each ended by U+0000.
    static let valueBlocks: StaticString = """
{value_block}
        """

    /// The byte offset of each block in ``valueBlocks``, and of its end.
    static let valueBlockStarts: [UInt32] = [
{wrapped(value_starts)}
    ]
}}
'''
    with open(OUTPUT, "w", encoding="utf-8") as output:
        output.write(source)
    print(f"wrote {OUTPUT}: {len(names)} names, {name_length} + {value_length} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
