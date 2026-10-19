//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextLinkTests.swift
//
//  A link inside a `Text` — an attributed string's `link` run: drawn as a link,
//  and carried to the terminal as an OSC 8 hyperlink balanced on every line.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitStyling
@testable import TUIkitTerminalHost
@testable import TUIkitTestSupport

@MainActor
@Suite("Links in a Text")
struct TextLinkTests {

    private let url = URL(string: "https://example.com/docs")!
    private let red = Color.rgb(200, 20, 20)
    private let opening = "\u{1B}]8;;https://example.com/docs\u{1B}\\"

    /// "See " then "docs" linked to ``url``, then "." — the shape a sentence
    /// with a link in it has.
    private var sentence: AttributedString {
        var link = AttributedString("docs")
        link.link = url
        return AttributedString("See ") + link + AttributedString(" now")
    }

    private func lines(_ view: some View, width: Int = 40) -> [String] {
        renderToBuffer(view, context: makeRenderContext(width: width, height: 6)).lines
    }

    private func accentCodes() -> String {
        let palette = makeRenderContext().environment.palette
        return Color.palette.accent.resolve(with: palette).foregroundCodes().joined(separator: ";")
    }

    private func isUnderlined(_ word: String, in lines: [String]) -> Bool {
        sgrState(of: word, in: lines)?.parameters.split(separator: ";").contains("4") == true
    }

    /// Whether `line` leaves a link open at its end.
    private func leavesLinkOpen(_ line: String) -> Bool {
        var scan = HyperlinkScan()
        for segment in line.ansiSegments() {
            if case .ansi(let sequence, _) = segment { scan.note(sequence) }
        }
        return scan.opening != nil
    }

    // MARK: - How it draws

    @Test("A link draws in the accent, underlined, and the words around it do not")
    func drawsAsALink() {
        let drawn = lines(Text(sentence))
        #expect(sgrState(of: "docs", in: drawn)?.parameters.contains(accentCodes()) == true)
        #expect(isUnderlined("docs", in: drawn))
        #expect(sgrState(of: "See", in: drawn)?.parameters.contains(accentCodes()) == false)
        #expect(!isUnderlined("now", in: drawn))
    }

    @Test("A link's own colour wins; the text's colour does not reach it")
    func colourPrecedence() {
        // SwiftUI, measured on macOS 15.8: `.foregroundColor` on the text
        // leaves a link in the link colour, and the run's own colour beats it.
        let recoloured = lines(Text(sentence).foregroundStyle(red))
        #expect(sgrState(of: "docs", in: recoloured)?.parameters.contains(accentCodes()) == true)
        #expect(sgrState(of: "See", in: recoloured)?.parameters.contains(red.foregroundCodes().joined(separator: ";")) == true)

        var own = AttributedString("docs")
        own.link = url
        own.foregroundColor = red
        let stated = lines(Text(own))
        #expect(sgrState(of: "docs", in: stated)?.parameters.contains(red.foregroundCodes().joined(separator: ";")) == true)
    }

    @Test("linkUnderline(false) takes the underline away, as it does from a Link")
    func underlineFollowsTheEnvironment() {
        let drawn = lines(VStack { Text(sentence) }.linkUnderline(false))
        #expect(!isUnderlined("docs", in: drawn))
    }

    // MARK: - The hyperlink

    @Test("A host that honours OSC 8 gets the link around its words only")
    func hyperlink() {
        let without = TerminalHyperlink.withSupport(false) { lines(Text(sentence)) }
        let with = TerminalHyperlink.withSupport(true) { lines(Text(sentence)) }
        #expect(!without.joined().contains("\u{1B}]8;"))
        let line = with[0]
        #expect(line.contains(opening))
        #expect(!leavesLinkOpen(line))
        // The words either side are outside the pair.
        let linked = line.components(separatedBy: opening)
        #expect(linked.count == 2)
        #expect(linked[0].stripped == "See ")
        #expect(linked[1].components(separatedBy: TerminalHyperlink.closing)[0].stripped == "docs")
        // An escape costs no cells.
        #expect(with.map(\.stripped) == without.map(\.stripped))
    }

    @Test("No hyperlink where the subtree declines them or the text is disabled")
    func hyperlinkConditions() {
        let declined = TerminalHyperlink.withSupport(true) {
            lines(VStack { Text(sentence) }.terminalHyperlinks(false))
        }
        let disabled = TerminalHyperlink.withSupport(true) {
            lines(VStack { Text(sentence) }.disabled(true))
        }
        #expect(!declined.joined().contains("\u{1B}]8;"))
        #expect(!disabled.joined().contains("\u{1B}]8;"))
    }

    /// The rules `Link` follows, in a text's runs too: a file link names this
    /// machine, and a link too long for a terminal to keep is drawn as a link
    /// with no sequence.
    @Test("A run's file link names the host, and an over-long one carries none")
    func fileLinkAndCapInARun() throws {
        var file = AttributedString("notes")
        file.link = URL(fileURLWithPath: "/tmp/notes.txt")
        // The machine's name is pinned, so the expectation holds whatever
        // the machine running this is called.
        let filed = TerminalClient.$localHostNamePin.withValue("box") {
            TerminalHyperlink.withSupport(true) { lines(Text(file)) }.joined()
        }
        #expect(filed.contains("\u{1B}]8;;file://box/tmp/notes.txt\u{1B}\\"), "\(filed.debugDescription)")

        let longURL = try #require(URL(string: "https://example.com/" + String(repeating: "a", count: 2100)))
        var long = AttributedString("long")
        long.link = longURL
        let drawn = TerminalHyperlink.withSupport(true) { lines(Text(long)) }
        let plain = TerminalHyperlink.withSupport(false) { lines(Text(long)) }
        #expect(!drawn.joined().contains("\u{1B}]8;"))
        #expect(drawn == plain, "still drawn as a link, in the accent and underlined")
    }

    /// A run's link is `URL.absoluteString` too, already encoded, so its
    /// escapes reach the host as Foundation wrote them: `Read%20me.txt`, not
    /// `Read%2520me.txt`, which names a file that is not there.
    @Test("A run's link to a file with a space in its name is encoded once")
    func runFileLinkIsEncodedOnce() {
        var file = AttributedString("notes")
        file.link = URL(fileURLWithPath: "/Users/x/Read me.txt")
        let drawn = TerminalHyperlink.withSupport(true) { lines(Text(file)) }.joined()
        #expect(drawn.contains("/Users/x/Read%20me.txt\u{1B}\\"), "\(drawn.debugDescription)")
        #expect(!drawn.contains("%25"))
    }

    @Test("A link that wraps is balanced on every line and keeps one identity")
    func wrappedLink() {
        var link = AttributedString("alpha beta gamma delta")
        link.link = url
        let drawn = TerminalHyperlink.withSupport(true) { lines(Text(link), width: 8) }
        #expect(drawn.count > 1)
        for line in drawn where !line.stripped.isEmpty {
            #expect(!leavesLinkOpen(line), "\(line.debugDescription)")
            #expect(line.contains("\u{1B}]8;id="), "a wrapped link must carry its id")
        }
    }

    @Test("A concatenation's line is spelled as each fragment rendered, hyperlinked and joined")
    func styledLineIsThePerFragmentSpelling() {
        // `styledLine` writes a line into one reserved string. It must be the
        // per-fragment spelling it replaced, byte for byte: with and without a
        // style (an empty one draws bare), with and without links, a run
        // split over fragments, and no links at all (`openings == nil`).
        var bold = TextStyle()
        bold.isBold = true
        bold.foregroundColor = red
        var tinted = TextStyle()
        tinted.foregroundColor = Color.rgb(1, 2, 3)
        tinted.backgroundColor = Color.rgb(250, 240, 230)
        let styles = [bold, TextStyle(), tinted]
        let sequences = styles.map { ANSIRenderer.styleSequence(for: $0) }
        #expect(sequences[1] == nil)
        let lines: [[(text: String, run: Int)]] = [
            [("See ", 0), ("docs", 1), (" now", 2)],
            [("one", 0)],
            [("bare", 1)],
            [("a", 2), ("日本", 0), ("e\u{301}", 1), ("z", 2)],
            [],
        ]
        let openingSets: [[String?]?] = [
            nil, [nil, opening, nil], [opening, opening, "\u{1B}]8;id=x;https://x\u{1B}\\"],
        ]
        for openings in openingSets {
            for line in lines {
                let perFragment = line.map { fragment in
                    Text.hyperlinked(
                        ANSIRenderer.render(fragment.text, with: styles[fragment.run]),
                        opening: openings.flatMap { $0[fragment.run] })
                }.joined()
                let written = Text.styledLine(line, sequences: sequences, openings: openings)
                #expect(Array(written.utf8) == Array(perFragment.utf8), "\(line) \(String(describing: openings))")
            }
        }
    }

    // MARK: - It survives what a run goes through

    @Test("A link survives interpolation and a live read")
    func survives() throws {
        let joined = Text("\(Text(sentence))\(Text(Date(timeIntervalSinceNow: 3600), style: .relative))")
        #expect(joined.runs?.contains { $0.link == url } == true)
        let read = try #require(joined.readingLive(at: Date(), in: .current))
        #expect(read.text.runs?.contains { $0.link == url } == true)
    }

    @Test("A string that is one link is not a plain text")
    func wholeStringLink() {
        var link = AttributedString("docs")
        link.link = url
        #expect(Text(link).runs?.first?.link == url)
    }
}
