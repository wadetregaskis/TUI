//  🖥️ TUI — A Terminal UI framework for Swift
//  HTMLEntitiesTests.swift
//
//  HTML's named character references, all 2,125 of them, as the Markdown parse
//  decodes them (owner ruling B86, 2026-10-26): the generated table's shape,
//  a few values that say the encoding is right, and, where Foundation has its
//  Markdown parser, every name against it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIStrings

@Suite("HTML named character references")
struct HTMLEntitiesTests {
    @Test("The table holds every name with a semicolon, sorted, its blocks where they say")
    func tableShape() {
        #expect(HTMLEntities.count == 2125)
        var names: [[UInt8]] = []
        HTMLEntities.names.forEachName { _, name in names.append(name) }
        #expect(names.count == 2125)
        #expect(zip(names, names.dropFirst()).allSatisfy { $0.lexicographicallyPrecedes($1) })
        #expect(Int(HTMLEntities.nameBlockStarts.last!) == HTMLEntities.nameBlocks.utf8CodeUnitCount)
        #expect(Int(HTMLEntities.valueBlockStarts.last!) == HTMLEntities.valueBlocks.utf8CodeUnitCount)
        let blocks = (2125 + 15) / 16
        #expect(HTMLEntities.nameBlockStarts.count == blocks + 1)
        #expect(HTMLEntities.valueBlockStarts.count == blocks + 1)
    }

    @Test(
        "Names decode to their characters, case-sensitively",
        arguments: [
            ("amp", "&"), ("Aacute", "Á"), ("aacute", "á"), ("NotEqualTilde", "\u{2242}\u{338}"),
            ("NewLine", "\n"), ("Tab", "\t"), ("zwnj", "\u{200C}"), ("zopf", "\u{1D56B}"), ("AElig", "Æ"),
            ("zwj", "\u{200D}"),
        ])
    func decodes(name: String, value: String) {
        #expect(HTMLEntities.scalars(named: name).map { String(String.UnicodeScalarView($0)) } == value)
    }

    @Test("A name HTML does not define, or one written without its case, is none", arguments: [
        "aacutee", "AACUTE", "", "zzzz", "amp;", "&amp",
    ])
    func unknownNames(name: String) {
        #expect(HTMLEntities.scalars(named: name) == nil)
    }

    @Test("A Markdown text decodes a name beyond the common ones")
    func markdownDecodes() {
        let spans = InlineMarkdown.parse("&Aacute;rbol &NotEqualTilde; &bogus;")
        let text = spans.flatMap(\.atoms).compactMap(\.scalar)
        #expect(String(String.UnicodeScalarView(text)) == "Árbol \u{2242}\u{338} &bogus;")
    }

    #if canImport(Darwin)
        /// Every name against Foundation's own parser, the one SwiftUI draws a
        /// key with, so the table is the one it decodes.
        @Test("Every name decodes as Foundation's Markdown parser decodes it")
        func agreesWithFoundation() throws {
            var differences: [String] = []
            HTMLEntities.names.forEachName { index, bytes in
                // swiftlint:disable:next optional_data_string_conversion - no `Data`: an ASCII name
                let name = String(decoding: bytes, as: UTF8.self)
                let source = "x&\(name);x"
                let ours = "x" + String(String.UnicodeScalarView(HTMLEntities.scalars(at: index))) + "x"
                let options = AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace)
                guard let theirs = try? AttributedString(markdown: source, options: options) else {
                    differences.append("\(name): Foundation refused")
                    return
                }
                if String(theirs.characters) != ours { differences.append(name) }
            }
            #expect(differences.isEmpty, "\(differences.count): \(differences.prefix(20))")
        }
    #endif
}
