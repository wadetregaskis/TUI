//  🖥️ TUI — A Terminal UI framework for Swift
//  InlineMarkdownTests.swift
//
//  TUI's inline Markdown parse against Foundation's: the table below is
//  Foundation's `AttributedString(markdown:options:)` with
//  `.inlineOnlyPreservingWhitespace` — what SwiftUI draws a key with — measured
//  on macOS 15.8 (SDK 26.2). Swift-foundation has no Markdown parser, so on
//  Linux this table is the only witness.
//
//  The parse was also run against Foundation on 550,000 random strings over
//  three alphabets (the syntax characters, URL and email pieces, Unicode
//  punctuation and spaces) with no difference outside the two noted in
//  `InlineMarkdown`: named references missing from the table (none since
//  2026-10-26, when the table became HTML's whole list), and link reference
//  definitions.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIFoundation
@testable import TUIStrings
@testable import TUITestSupport

@Suite("Inline Markdown")
struct InlineMarkdownTests {
    typealias Atom = InlineMarkdown.Atom

    /// A parse in the table's encoding: «text», the traits' raw value when
    /// there are any, and →destination for a link.
    ///
    /// With `resolvingLinks`, a destination is the URL a `Text` makes of it —
    /// `URL(string:)`, as Foundation's parse does, so `a b` is `a%20b` and an
    /// empty destination is no link — and spans that then agree are merged, as
    /// Foundation's runs are. Without it, the destination as parsed.
    private func encode(_ spans: [InlineMarkdown.Span], resolvingLinks: Bool = false) -> String {
        var runs: [(text: String, traits: UInt8, link: String?)] = []
        for span in spans {
            let link = span.link.flatMap { resolvingLinks ? Text.linkURL(text($0))?.absoluteString : text($0) }
            if let last = runs.last, last.traits == span.traits.rawValue, last.link == link {
                runs[runs.count - 1].text += text(span.atoms)
            } else {
                runs.append((text(span.atoms), span.traits.rawValue, link))
            }
        }
        return runs.map { run in
            "«" + run.text + "»" + (run.traits == 0 ? "" : "\(run.traits)") + (run.link.map { "→" + $0 } ?? "")
        }.joined()
    }

    /// Atoms as text, an argument as `§n`.
    private func text(_ atoms: [Atom]) -> String {
        var result = ""
        for atom in atoms {
            switch atom {
            case .scalar(let scalar): result.unicodeScalars.append(scalar)
            case .argument(let index): result += "§\(index)"
            }
        }
        return result
    }

    private func atoms(_ pieces: Any...) -> [Atom] {
        pieces.flatMap { piece -> [Atom] in
            if let index = piece as? Int { return [.argument(index)] }
            return (piece as? String ?? "").unicodeScalars.map(Atom.scalar)
        }
    }

    /// Traits: 1 emphasis, 2 strong, 4 code, 8 strikethrough.
    static let measured: [(source: String, parse: String)] = [
        ("**bold**", "«bold»2"),
        ("*italic*", "«italic»1"),
        ("_italic_", "«italic»1"),
        ("__bold__", "«bold»2"),
        ("***both***", "«both»3"),
        ("___both___", "«both»3"),
        ("**bold *nested* bold**", "«bold »2«nested»3« bold»2"),
        ("*a **b** c*", "«a »1«b»3« c»1"),
        ("~~strike~~", "«strike»8"),
        ("~strike~", "«strike»8"),
        ("~~~strike~~~", "«~~~strike~~~»"),
        ("`code`", "«code»4"),
        ("``a`b``", "«a`b»4"),
        ("` a `", "«a»4"),
        ("`a  b`", "«a  b»4"),
        ("`**not bold**`", "«**not bold**»4"),
        ("[link](https://example.com)", "«link»→https://example.com"),
        ("[link](https://example.com \"title\")", "«link»→https://example.com"),
        ("<https://example.com>", "«https://example.com»→https://example.com"),
        ("see https://example.com now", "«see »«https://example.com»→https://example.com« now»"),
        ("www.example.com", "«www.example.com»→http://www.example.com"),
        ("snake_case_word", "«snake_case_word»"),
        ("2*3*4", "«2»«3»1«4»"),
        ("a * b * c", "«a * b * c»"),
        ("**unclosed", "«**unclosed»"),
        ("*unclosed", "«*unclosed»"),
        ("unclosed**", "«unclosed**»"),
        ("\\*escaped\\*", "«*escaped*»"),
        ("\\\\backslash", "«\\backslash»"),
        ("\\a not escapable", "«\\a not escapable»"),
        ("line1\nline2", "«line1\nline2»"),
        ("a  b", "«a  b»"),
        ("  lead", "«  lead»"),
        ("trail  ", "«trail  »"),
        ("# heading", "«# heading»"),
        ("- item", "«- item»"),
        ("1. item", "«1. item»"),
        ("> quote", "«> quote»"),
        ("&amp; &lt; &copy; &#65; &#x42;", "«& < © A B»"),
        ("![img](https://example.com/y.png)", "«img»"),
        ("**bold**text", "«bold»2«text»"),
        ("foo**bar**baz", "«foo»«bar»2«baz»"),
        ("foo__bar__baz", "«foo__bar__baz»"),
        ("*foo bar *", "«*foo bar *»"),
        ("* foo*", "«* foo*»"),
        ("**foo*", "«*»«foo»1"),
        ("*foo**", "«foo»1«*»"),
        ("[a *b*](https://example.com)", "«a b»→https://example.com"),
        ("*[a](https://example.com)*", "«a»1→https://example.com"),
        ("[a](<https://example.com/a b>)", "«a»→https://example.com/a%20b"),
        ("[a][ref]", "«[a][ref]»"),
        ("[a]", "«[a]»"),
        ("[]()", ""),
        ("a\\\nb", "«a\nb»"),
        ("a  \nb", "«a  \nb»"),
        ("~~a~~b", "«a»8«b»"),
        ("a~~b~~c", "«a»«b»8«c»"),
        ("***a**b*", "«a»3«b»1"),
        ("**a*b***", "«a»2«b»3"),
        ("_a_b", "«_a_b»"),
        ("a_b_", "«a_b_»"),
        ("*a*b", "«a»1«b»"),
        ("**", "«**»"),
        ("****", "«****»"),
        ("* *", "«* *»"),
        ("a\n\nb", "«a\n\nb»"),
        ("\ttab", "«\ttab»"),
        ("[a](relative/path)", "«a»→relative/path"),
        ("[a](mailto:x@y.z)", "«a»→mailto:x@y.z"),
        ("x@y.z", "«x@y.z»→mailto:x@y.z"),
        ("**a\nb**", "«a\nb»2"),
        ("*a\n\nb*", "«a\n\nb»1"),
        ("\\`", "«`»"),
        ("\\~~a~~", "«~~a~~»"),
        ("~~a\\~~", "«~~a~~»"),
        ("__init__", "«init»2"),
        ("a__b__c", "«a__b__c»"),
        ("**a** **b**", "«a»2« »«b»2"),
        ("*a*_b_", "«ab»1"),
        ("<b>html</b>", "«<b>html</b>»"),
        ("a<br>b", "«a<br>b»"),
        ("[a](https://example.com/(x))", "«a»→https://example.com/(x)"),
        ("[a](https://example.com/x) and [b](https://example.org)", "«a»→https://example.com/x« and »«b»→https://example.org"),
        ("[[a]](https://example.com)", "«[a]»→https://example.com"),
        ("`a` `b`", "«a»4« »«b»4"),
        ("**`code`**", "«code»6"),
        ("~~**a**~~", "«a»10"),
        ("*~~a~~*", "«a»9"),
        ("[`c`](https://e.com)", "«c»→https://e.com"),
        ("![*a*](i.png)", "«a»"),
        ("[![a](i.png)](https://e.com)", "«a»→https://e.com"),
        ("^[**a**](x: 1)", "«a»2"),
        ("^[2 apple](inflect: true)", "«2 apple»"),
        ("^[a]", "«^[a]»"),
        ("[https://example.com]", "«[https://example.com]»"),
        ("[a](u) https://e.com", "«a»→u« »«https://e.com»→https://e.com"),
        ("https://example.com/a_b_c", "«https://example.com/a_b_c»→https://example.com/a_b_c"),
        ("https://example.com/*a*", "«https://example.com/*a»→https://example.com/*a«*»"),
        ("*https://example.com*", "«https://example.com»1→https://example.com"),
        ("(www.example.com)", "«(»«www.example.com»→http://www.example.com«)»"),
        ("www.example.com.", "«www.example.com»→http://www.example.com«.»"),
        ("https://example.com/(x))", "«https://example.com/(x)»→https://example.com/(x)«)»"),
        ("a.b@c.de", "«a.b@c.de»→mailto:a.b@c.de"),
        ("x@y", "«x@y»"),
        ("mailto:a@b.cd", "«mailto:a@b.cd»→mailto:a@b.cd"),
        ("first_last@x.com", "«first_last@x.com»→mailto:first_last@x.com"),
        ("a@b.c@d.e", "«a@»«b.c@d.e»→mailto:b.c@d.e"),
        ("hello@wörld.com", "«hello@wörld.com»"),
        ("&#0; &#xD800; &#1234567;", "«� � �»"),
        ("a*€*b", "«a»«€»1«b»"),
        ("*€a*", "«€a»1"),
        ("'a' \"b\"", "«'a' \"b\"»"),
        ("~a~~b~~", "«~a»«b»8"),
        ("~~a~", "«~~a~»"),
        ("~a~~", "«~a~~»"),
        ("x~~y~~ z", "«x»«y»8« z»"),
        ("[a](u 'title')", "«a»→u"),
        ("[a](u (title))", "«a»→u"),
        ("[a]( u )", "«a»→u"),
        ("[a](\nu)", "«a»→u"),
        ("[a](u\n)", "«a»→u"),
        ("[a](<u>)", "«a»→u"),
        ("[a](<>)", "«a»"),
        ("HTTPS://EXAMPLE.COM", "«HTTPS://EXAMPLE.COM»→HTTPS://EXAMPLE.COM"),
        ("ftp://example.com", "«ftp://example.com»→ftp://example.com"),
        ("xhttps://example.com", "«xhttps://example.com»"),
        ("1https://example.com", "«1»«https://example.com»→https://example.com"),
        ("Www.example.com", "«Www.example.com»"),
        ("www.ex_ample.com", "«www.ex_ample.com»"),
        ("www._ex.ample.com", "«www._ex.ample.com»→http://www._ex.ample.com"),
        ("www.example", "«www.example»→http://www.example"),
        ("http://a", "«http://a»→http://a"),
        ("&amp", "«&amp»"),
        ("&#x;", "«&#x;»"),
        ("&#;", "«&#;»"),
        ("\\&amp;", "«&amp;»"),
        ("`&amp;`", "«&amp;»4"),
        ("[&amp;](https://e.com/?a=1&amp;b=2)", "«&»→https://e.com/?a=1&b=2"),
    ]

    @Test("Every case parses as Foundation's parse does")
    func matchesFoundation() {
        for (source, parse) in Self.measured {
            #expect(encode(InlineMarkdown.parse(source), resolvingLinks: true) == parse, "\(source.debugDescription)")
        }
    }

    // MARK: - Arguments

    @Test("An interpolated argument is a letter to the delimiter rules")
    func argumentIsALetter() {
        // SwiftUI: `Text("**\(name)**")` is bold whatever `name` holds — even
        // " x ", whose spaces would stop `** x **` from being emphasis.
        #expect(encode(InlineMarkdown.parse(atoms("**", 0, "**"))) == "«§0»2")
        #expect(encode(InlineMarkdown.parse(atoms("_", 0, "_"))) == "«§0»1")
    }

    @Test("Delimiters inside arguments are not syntax")
    func argumentsAreOpaque() {
        // `Text("\(star)a\(star)")` with star = "*" draws "*a*": the stars are
        // the arguments' text, never delimiters.
        #expect(encode(InlineMarkdown.parse(atoms(0, "a", 1))) == "«§0a§1»")
    }

    @Test("An argument may sit in a link's destination, text or code span")
    func argumentsInConstructs() {
        #expect(
            encode(InlineMarkdown.parse(atoms("[a](https://example.com/", 0, ")")))
                == "«a»→https://example.com/§0")
        #expect(encode(InlineMarkdown.parse(atoms("[", 0, "](https://e.com)"))) == "«§0»→https://e.com")
        #expect(encode(InlineMarkdown.parse(atoms("`", 0, "`"))) == "«§0»4")
    }

    @Test("A URL that arrives as an argument is not autolinked")
    func argumentsAreNotAutolinked() {
        // SwiftUI, measured: `Text("see \(url)")` draws the URL as plain text.
        #expect(encode(InlineMarkdown.parse(atoms("see ", 0))) == "«see §0»")
        #expect(encode(InlineMarkdown.parse(atoms("https://", 0))) == "«https://§0»")
    }

    // MARK: - The fast path

    @Test("Only a template that could hold Markdown reaches the parser")
    func fastPath() {
        for plain in ["Save", "Name:", "100% done", "a.b", "Settings…", "w.w.w", "1:2", "", "wwwx"] {
            #expect(!InlineMarkdown.mightContainMarkup(plain), "\(plain.debugDescription)")
        }
        for marked in ["**", "_a_", "`", "~", "[a]", "<b>", "\\", "&amp;", "a@b.c", "https://x", "www.x", "mailto:@b.c"] {
            #expect(InlineMarkdown.mightContainMarkup(marked), "\(marked.debugDescription)")
        }
    }

    @Test("An interpolated key's placeholders do not reach the parser, and parse as plain text if they do")
    @MainActor
    func fastPathPlaceholders() {
        // A placeholder's `@` has no address before it, so these templates —
        // `"#\(index)"`, `"\(a) of \(b)"` — take the plain path.
        for template in ["#%@", "Row %@", "%1$@ of %2$@", "%@@b.c", "100%@"] {
            #expect(!InlineMarkdown.mightContainMarkup(template), "\(template.debugDescription)")
            #expect(encode(InlineMarkdown.parse(template)) == "«" + template + "»", "\(template.debugDescription)")
        }
        #expect(Text("#\(7)").runs == nil)
        #expect(Text("Saved **\(3)** files").runs != nil)
    }

    @Test("Everything the fast path passes over parses as plain text")
    func fastPathIsSound() {
        // The fast path is an optimisation, so anything it skips must be text
        // the parser would have returned unchanged.
        for (source, parse) in Self.measured where !InlineMarkdown.mightContainMarkup(source) {
            #expect(parse == "«" + source + "»" || (source.isEmpty && parse.isEmpty), "\(source.debugDescription)")
        }
    }

    // MARK: - Named references

    /// HTML's named references, all 2,125 Foundation knows (owner ruling B86,
    /// 2026-10-26; `HTMLEntitiesTests` checks every one against Foundation),
    /// and a name HTML does not define stays as written, as in Foundation.
    @Test("A named reference decodes, and a name HTML does not define stays as written")
    func namedReferences() {
        #expect(encode(InlineMarkdown.parse("&Aacute; &amp;")) == "«Á &»")
        #expect(encode(InlineMarkdown.parse("&Bogus; &amp;")) == "«&Bogus; &»")
    }
}
