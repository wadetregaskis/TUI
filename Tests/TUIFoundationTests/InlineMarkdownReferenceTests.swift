//  🖥️ TUI — A Terminal UI framework for Swift
//  InlineMarkdownReferenceTests.swift
//
//  Link reference definitions and reference links, as Foundation's Markdown
//  parser reads them in the inline-only mode SwiftUI draws a key with (owner
//  ruling B86, 2026-10-26). The table is Foundation's output, measured on
//  macOS 15.8 with an `AttributedString(markdown:)` probe; on Darwin each case
//  is also checked against Foundation live.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIFoundation
@testable import TUIStrings

@Suite("Inline Markdown's link reference definitions")
struct InlineMarkdownReferenceTests {
    /// Runs as «text»→link, adjacent runs with the same link merged, as
    /// Foundation's runs are once emphasis is set aside. Shared with the other
    /// suites that hold a table of Foundation's readings.
    static func encode(_ spans: [InlineMarkdown.Span]) -> String {
        var runs: [(text: String, link: String?)] = []
        for span in spans {
            let text = String(String.UnicodeScalarView(span.atoms.compactMap(\.scalar)))
            let link = span.link.flatMap {
                Text.linkURL(String(String.UnicodeScalarView($0.compactMap(\.scalar))))?.absoluteString
            }
            if let last = runs.last, last.link == link {
                runs[runs.count - 1].text += text
            } else {
                runs.append((text, link))
            }
        }
        return runs.map { "«\($0.text)»" + ($0.link.map { "→" + $0 } ?? "") }.joined()
    }

    /// Foundation's reading of each, from the probe.
    static let cases: [(String, String)] = [
        ("[a]: https://x.com\nsee [a] here", "«see »«a»→https://x.com« here»"),
        ("see [a] here\n[a]: https://x.com", "«see [a] here\n[a]: »«https://x.com»→https://x.com"),
        ("see [a]\n\n[a]: https://x.com", "«see [a]\n\n[a]: »«https://x.com»→https://x.com"),
        ("[a]: https://x.com", "«[a]: »«https://x.com»→https://x.com"),
        ("[a]: https://x.com \"Title\"\n[a]", "«a»→https://x.com"),
        ("[A]: https://x.com\n[a]", "«a»→https://x.com"),
        (
            "[a]: https://x.com\n[text][a] and [a][] and [a]",
            "«text»→https://x.com« and »«a»→https://x.com« and »«a»→https://x.com"
        ),
        ("x [a]: https://x.com\n[a]", "«x [a]: »«https://x.com»→https://x.com«\n[a]»"),
        ("   [a]: https://x.com\n[a]", "«   [a]: »«https://x.com»→https://x.com«\n[a]»"),
        ("[a]:\nhttps://x.com\n[a]", "«a»→https://x.com"),
        ("[a]: <https://x.com/a b>\n[a]", "«a»→https://x.com/a%20b"),
        ("[a]: https://x.com\n[a]: https://y.com\n[a]", "«a»→https://x.com"),
        ("[a]: https://x.com 'bad\n[a]", "«[a]: »«https://x.com»→https://x.com« 'bad\n[a]»"),
        ("[a]:https://x.com\n[a]", "«a»→https://x.com"),
        ("[a  b]: https://x.com\n[A B]", "«A B»→https://x.com"),
        ("[a]: https://x.com garbage\n[a]", "«[a]: »«https://x.com»→https://x.com« garbage\n[a]»"),
        ("[a]: https://x.com\n![img][a] and ![a]", "«img and a»"),
        ("[a]: https://x.com\n\"T\"\n[a]", "«a»→https://x.com"),
        ("[a]: https://x.com\n\ntext [a]", "«\ntext »«a»→https://x.com"),
        ("[Ä]: https://x.com\n[ä]", "«ä»→https://x.com"),
        ("[ß]: https://x.com\n[SS]", "«SS»→https://x.com"),
        ("[a]: https://x.com/(p)\n[a]", "«a»→https://x.com/(p)"),
        ("[a]: https://x.com\n[b]: https://y.com\n[b] [a]", "«b»→https://y.com« »«a»→https://x.com"),
        ("[a]: https://x.com\n[x][b] [a][zz] [a] [b]", "«[x][b] [a][zz] »«a»→https://x.com« [b]»"),
        ("[a]: https://x.com\n[a] [a][]", "«a»→https://x.com« »«a»→https://x.com"),
        ("[a]: https://x.com\n[a](https://y.com)", "«a»→https://y.com"),
        ("[a]: https://x.com\n[text][a]extra", "«text»→https://x.com«extra»"),
        ("[a]:   <>\n[a]", "«a»"),
        ("[a]: https://x.com\t\n[a]", "«a»→https://x.com"),
        ("[a]: https://x.com (Title)\n[a]", "«a»→https://x.com"),
        ("[a]: https://x.com\n  [a]", "«  »«a»→https://x.com"),
        ("[\\]]: https://x.com\n[\\]]", "«]»→https://x.com"),
        ("[]: https://x.com\n[]", "«[]: »«https://x.com»→https://x.com«\n[]»"),
        ("[a]: https://x.com\n[a] [ a ]", "«a»→https://x.com« »« a »→https://x.com"),
        ("[a]: https://x.com\n[a][  ]\t[A]", "«a»→https://x.com«\t»«A»→https://x.com"),
        ("[a]: https://x.com\n[A][\n\t]", "«A»→https://x.com"),
        ("[a]: https://x.com\n[a]: https://y.com", "«a»→https://x.com«: »«https://y.com»→https://y.com"),
        ("[a]: https://x.com ", ""),
        ("[a]: https://x.com\n", ""),
        ("[a]: <https://x.com>", "«[a]: »«https://x.com»→https://x.com"),
        ("[a]: https://x.com\n[a][a][a][", "«aa»→https://x.com«[»"),
    ]

    @Test("Each reads as Foundation reads it", arguments: cases)
    func reads(source: String, expected: String) {
        #expect(Self.encode(InlineMarkdown.parse(source)) == expected, "\(source.debugDescription)")
    }

    #if canImport(Darwin)
        /// Foundation's own reading of `source`, encoded as ``encode(_:)`` encodes TUI's.
        static func foundationReading(_ source: String) throws -> String {
            let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            let theirs = try AttributedString(markdown: source, options: options)
            var runs: [(text: String, link: String?)] = []
            for run in theirs.runs {
                let text = String(theirs[run.range].characters)
                let link = run.link?.absoluteString
                if let last = runs.last, last.link == link {
                    runs[runs.count - 1].text += text
                } else {
                    runs.append((text, link))
                }
            }
            return runs.map { "«\($0.text)»" + ($0.link.map { "→" + $0 } ?? "") }.joined()
        }

        @Test("Each reads as Foundation reads it on this machine", arguments: cases)
        func agreesWithFoundation(source: String, expected: String) throws {
            let foundation = try Self.foundationReading(source)
            #expect(foundation == expected, "the table is stale: \(source.debugDescription)")
            #expect(Self.encode(InlineMarkdown.parse(source)) == foundation, "\(source.debugDescription)")
        }
    #endif
}
