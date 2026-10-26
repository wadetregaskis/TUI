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
        // Beyond ASCII, what is refused is the same everywhere; what is linked is
        // spelled by IDNA, which is the platform's (`idnaCases`).
        ("see https://—x.com end", "«see https://—x.com end»"),
        ("see https://«x.com end", "«see https://«x.com end»"),
        ("see https://é-.com end", "«see https://é-.com end»"),
        ("see https://-é.com end", "«see https://-é.com end»"),
        ("see https://xé.-y.com end", "«see https://xé.-y.com end»"),
        ("see https://é@-é end", "«see https://é@-é end»"),
        ("see https://-x.com end", "«see https://-x.com end»"),
        ("see https://x-.com end", "«see »«https://x-.com»→https://x-.com« end»"),
        // Every kind of link, not only a bare one.
        ("<https://x\"y.com>", "«https://x\"y.com»"),
        ("<https://x.com:8b>", "«https://x.com:8b»"),
        ("[t](https://x^y.com)", "«t»"),
        ("[t](https://x.com:8b)", "«t»"),
        ("[t](foo\"bar)", "«t»→foo%22bar"),
        ("[a]: https://x^y.com\n[a]", "«a»"),
    ]

    /// Hosts beyond ASCII that Foundation links, spelled through Darwin's IDNA:
    /// a host may begin with anything but a space or punctuation, and an
    /// underscore after such a character is not counted against the domain, as
    /// cmark-gfm's byte-wise walk counts it.
    static let idnaCases: [(String, String)] = [
        ("see https://éx.com end", "«see »«https://éx.com»→https://xn--x-9fa.com« end»"),
        ("see https://€x.com end", "«see »«https://€x.com»→https://xn--x-wpn.com« end»"),
        ("see www.yé_x end", "«see »«www.yé_x»→http://www.xn--y_x-bma« end»"),
        ("see http://é_.com end", "«see »«http://é_.com»→http://xn--_-9fa.com« end»"),
        ("see www.é8_1 end", "«see »«www.é8_1»→http://www.xn--8_1-9la« end»"),
    ]

    @Test("Each reads as Foundation reads it", arguments: cases)
    func reads(source: String, expected: String) {
        #expect(
            InlineMarkdownReferenceTests.encode(InlineMarkdown.parse(source)) == expected, "\(source.debugDescription)")
    }

    #if canImport(Darwin)
        @Test("A host beyond ASCII reads as Foundation reads it", arguments: idnaCases)
        func readsBeyondASCII(source: String, expected: String) {
            #expect(
                InlineMarkdownReferenceTests.encode(InlineMarkdown.parse(source)) == expected,
                "\(source.debugDescription)")
        }

        @Test("Each reads as Foundation reads it on this machine", arguments: cases + idnaCases)
        func agreesWithFoundation(source: String, expected: String) throws {
            let foundation = try InlineMarkdownReferenceTests.foundationReading(source)
            #expect(foundation == expected, "the table is stale: \(source.debugDescription)")
            #expect(
                InlineMarkdownReferenceTests.encode(InlineMarkdown.parse(source)) == foundation,
                "\(source.debugDescription)")
        }
    #endif
}
