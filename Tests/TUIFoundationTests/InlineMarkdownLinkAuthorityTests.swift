//  🖥️ TUI — A Terminal UI framework for Swift
//  InlineMarkdownLinkAuthorityTests.swift
//
//  A link whose host or port Foundation cannot make a URL of is drawn as its
//  text alone, for every kind of link. The table is Foundation's output,
//  measured on macOS 15.8 with an `AttributedString(markdown:)` probe; on
//  Darwin each case is also checked against Foundation live.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIFoundation
@testable import TUIStrings

@Suite("Inline Markdown's links whose host Foundation refuses")
struct InlineMarkdownLinkAuthorityTests {
    /// Foundation's reading of each, from the probe.
    static let cases: [(String, String)] = [
        // The fuzz's two, found beside B86: a host Foundation refuses.
        ("x https://x.com'a\"T\"", "«x https://x.com'a\"T\"»"),
        ("https://x.com>(", "«https://x.com>(»"),
        // Each refused character in a host, bare and `www.`.
        ("see https://x.com\"b end", "«see https://x.com\"b end»"),
        ("see https://x.com>b end", "«see https://x.com>b end»"),
        ("see https://x.com\\b end", "«see https://x.com\\b end»"),
        ("see https://x.com^b end", "«see https://x.com^b end»"),
        ("see https://x.com`b end", "«see https://x.com`b end»"),
        ("see https://x.com{b end", "«see https://x.com{b end»"),
        ("see https://x.com|b end", "«see https://x.com|b end»"),
        ("see https://x.com}b end", "«see https://x.com}b end»"),
        ("see https://x.com[b end", "«see https://x.com[b end»"),
        ("see https://x.com]b end", "«see https://x.com]b end»"),
        ("see https://x.com%b end", "«see https://x.com%b end»"),
        ("see https://x.com%4/p end", "«see https://x.com%4/p end»"),
        ("see www.x.com>b end", "«see www.x.com>b end»"),
        // What a host may hold.
        ("see https://x.com'b end", "«see »«https://x.com'b»→https://x.com'b« end»"),
        ("see https://x.com%41b end", "«see »«https://x.com%41b»→https://x.com%41b« end»"),
        ("see https://x.com!b end", "«see »«https://x.com!b»→https://x.com!b« end»"),
        ("see https://x--y.com end", "«see »«https://x--y.com»→https://x--y.com« end»"),
        // A port: digits only.
        ("see https://x.com:80 end", "«see »«https://x.com:80»→https://x.com:80« end»"),
        ("see https://x.com:80b end", "«see https://x.com:80b end»"),
        ("see https://x.com:8:9 end", "«see https://x.com:8:9 end»"),
        ("see www.x.com:80 end", "«see »«www.x.com:80»→http://www.x.com:80« end»"),
        ("see www.x.com:a end", "«see www.x.com:a end»"),
        // The rest of a destination is encoded, user information included.
        ("see https://x.com/a\"b end", "«see »«https://x.com/a\"b»→https://x.com/a%22b« end»"),
        ("see https://x.com?a\"b end", "«see »«https://x.com?a\"b»→https://x.com?a%22b« end»"),
        ("see https://u\"@x.com end", "«see »«https://u\"@x.com»→https://u%22@x.com« end»"),
        ("see https://u:p@x.com end", "«see »«https://u:p@x.com»→https://u:p@x.com« end»"),
        // Every kind of link, not only a bare one.
        ("<https://x\"y.com>", "«https://x\"y.com»"),
        ("<https://x.com:8b>", "«https://x.com:8b»"),
        ("[t](https://x^y.com)", "«t»"),
        ("[t](https://x.com:8b)", "«t»"),
        ("[t](foo\"bar)", "«t»→foo%22bar"),
        ("[a]: https://x^y.com\n[a]", "«a»"),
    ]

    @Test("Each reads as Foundation reads it", arguments: cases)
    func reads(source: String, expected: String) {
        #expect(
            InlineMarkdownReferenceTests.encode(InlineMarkdown.parse(source)) == expected, "\(source.debugDescription)")
    }

    #if canImport(Darwin)
        @Test("Each reads as Foundation reads it on this machine", arguments: cases)
        func agreesWithFoundation(source: String, expected: String) throws {
            let foundation = try InlineMarkdownReferenceTests.foundationReading(source)
            #expect(foundation == expected, "the table is stale: \(source.debugDescription)")
            #expect(
                InlineMarkdownReferenceTests.encode(InlineMarkdown.parse(source)) == foundation,
                "\(source.debugDescription)")
        }
    #endif
}
