//  🖥️ TUI — A Terminal UI framework for Swift
//  HTMLEntities.swift
//
//  HTML's named character references, `&Aacute;` and the 2,124 others, for
//  the Markdown parse: the table is generated
//  (`HTMLEntityTable.generated.swift`, from `Tools/GenerateHTMLEntities`).
//
//  Created by Wade Tregaskis
//  License: MIT

/// Every named character reference HTML defines with a semicolon — the 2,125
/// Foundation's Markdown parser decodes (owner ruling B86, 2026-10-26: the
/// whole table rather than the 140 common ones TUI carried before) — searched
/// where it is baked into the binary.
///
/// Front-coded rather than compressed further: DEFLATE would halve the 20 KB
/// but put the inflated table in dirty memory in every process that decodes
/// one name, where this one is clean, file-backed, and read only where a
/// lookup reads (the SF Symbols table's measurement, `Documentation/Swift
/// language/Baking a large static lookup table in Swift.md`).
enum HTMLEntities {
    /// The names, searched in place.
    static let names = FrontCodedNames(
        blocks: nameBlocks, blockStarts: nameBlockStarts, blockSize: blockSize, count: count)

    /// The scalars `&name;` stands for — one, or two for the 93 names whose
    /// character has a combining mark or a variation selector — or `nil` for
    /// a name HTML does not define. `name` is without its `&` and `;`, and is
    /// case-sensitive, as HTML's are (`&Aacute;` is Á, `&aacute;` á).
    static func scalars(named name: String) -> [Unicode.Scalar]? {
        names.index(of: name).map(scalars(at:))
    }

    /// Name `index`'s scalars: the value after the `index % blockSize` values
    /// before it in its block, each ended by U+0000.
    static func scalars(at index: Int) -> [Unicode.Scalar] {
        valueBlocks.withUTF8Buffer { blob in
            var position = Int(valueBlockStarts[index / blockSize])
            for _ in 0..<(index % blockSize) {
                while blob[position] != 0 { position += 1 }
                position += 1
            }
            var end = position
            while blob[end] != 0 { end += 1 }
            // swiftlint:disable:next optional_data_string_conversion - no `Data`: whole scalars of valid UTF-8
            return Array(String(decoding: UnsafeBufferPointer(rebasing: blob[position..<end]), as: UTF8.self).unicodeScalars)
        }
    }
}
