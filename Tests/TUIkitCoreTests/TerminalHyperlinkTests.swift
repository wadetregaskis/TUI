//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalHyperlinkTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkitCore

/// The sequence itself: how a destination is spelled, and why it is re-encoded
/// rather than trusted.
@Suite("OSC 8 hyperlink sequences")
struct TerminalHyperlinkSequenceTests {

    @Test("A link wraps its cells and adds no width")
    func linkAddsNoWidth() {
        let wrapped = "Docs".hyperlinked(to: TerminalHyperlink(destination: "https://example.com"))
        #expect(wrapped == "\u{1B}]8;;https://example.com\u{1B}\\Docs\u{1B}]8;;\u{1B}\\")
        #expect(wrapped.strippedLength == 4)
    }

    @Test("An id goes in the parameter field, shared by every run of one link")
    func idIsAParameter() {
        let link = TerminalHyperlink(destination: "https://example.com", id: "docs-1")
        #expect(link.opening == "\u{1B}]8;id=docs-1;https://example.com\u{1B}\\")
    }

    /// The sequence ends at an `ESC` or a `BEL`, so a destination carrying
    /// either does not render oddly — it ENDS THE SEQUENCE, and the rest is
    /// text the terminal draws. A URL is exactly the kind of value an app
    /// builds from data it did not author, which is why the encoding lives
    /// here rather than in each caller.
    @Test("A destination cannot break out of the sequence")
    func destinationCannotEscape() throws {
        let hostile = "https://example.com/\u{1B}]0;pwned\u{07}"
        let opening = try #require(TerminalHyperlink(destination: hostile).opening)
        #expect(opening.hasSuffix("\u{1B}\\"), "it still ends with its own ST")
        // Between the introducer and that ST there must be no ESC and no BEL:
        // either would end the sequence early and print the rest.
        let payload = opening.dropFirst(TerminalHyperlink.introducer.count).dropLast(2)
        #expect(!payload.contains("\u{1B}"))
        #expect(!payload.contains("\u{07}"))
        #expect(payload.contains("%1B"), "the ESC is carried as an encoded byte")

        // And it is still one zero-width sequence to every scan.
        let line = "Docs".hyperlinked(to: TerminalHyperlink(destination: hostile))
        #expect(line.strippedLength == 4)
        #expect(line.stripped == "Docs")
    }

    /// Everything outside printable ASCII is percent-encoded, and so is a `%`
    /// that cannot begin an escape — but not one that does. A URI carrying
    /// `%20` was encoded once already (`URL.absoluteString` always is), and
    /// encoding it again sent `%2520`, which a terminal decodes once, to a
    /// name with `%20` in it.
    @Test("Encoding is total, and keeps the escapes a URI already has")
    func encodingKeepsExistingEscapes() {
        #expect(TerminalHyperlink.encoded("a b") == "a%20b")
        #expect(TerminalHyperlink.encoded("café") == "caf%C3%A9", "UTF-8 bytes, not scalars")
        #expect(TerminalHyperlink.encoded("a;b[c]m") == "a;b[c]m", "printable ASCII is left alone")
        // An escape is kept, in either case, and anywhere in the value.
        #expect(TerminalHyperlink.encoded("%41") == "%41")
        #expect(TerminalHyperlink.encoded("Read%20me") == "Read%20me")
        #expect(TerminalHyperlink.encoded("caf%c3%a9") == "caf%c3%a9")
        // Encoding is idempotent now: a second pass changes nothing.
        let once = TerminalHyperlink.encoded("/tmp/Read me café 100%")
        #expect(once == "/tmp/Read%20me%20caf%C3%A9%20100%25")
        #expect(TerminalHyperlink.encoded(once) == once)
        // A `%` without two hex digits after it is no escape, and is encoded.
        #expect(TerminalHyperlink.encoded("100%") == "100%25")
        #expect(TerminalHyperlink.encoded("%4") == "%254")
        #expect(TerminalHyperlink.encoded("%4g") == "%254g")
        #expect(TerminalHyperlink.encoded("%%41") == "%25%41")
        // In an id, which is not a URI, every `%` is: `%3B` must stay
        // distinct from the `;` it would otherwise be read as.
        #expect(TerminalHyperlink.encoded("%41", in: .parameterValue) == "%2541")
        #expect(
            TerminalHyperlink.encoded("a%3Bb", in: .parameterValue)
                != TerminalHyperlink.encoded("a;b", in: .parameterValue))
    }

    /// The URIs the framework itself passes are Foundation's, already encoded:
    /// a local file with a space or a non-ASCII letter in its name, and an
    /// `https` URL with escapes in its path and query. Each reaches the host
    /// with its escapes as Foundation wrote them.
    @Test("A URL Foundation encoded is sent as Foundation encoded it")
    func foundationURLsAreNotEncodedTwice() throws {
        let spaced = URL(fileURLWithPath: "/Users/x/Read me.txt").absoluteString
        #expect(spaced == "file:///Users/x/Read%20me.txt")
        #expect(TerminalHyperlink(destination: spaced).opening == "\u{1B}]8;;file:///Users/x/Read%20me.txt\u{1B}\\")

        let accented = URL(fileURLWithPath: "/Users/x/café.txt").absoluteString
        let opening = try #require(TerminalHyperlink(destination: accented).opening)
        #expect(opening == "\u{1B}]8;;\(accented)\u{1B}\\")
        #expect(!opening.contains("%25"), "\(opening.debugDescription)")

        let web = "https://example.com/a%20b/caf%C3%A9?q=%26x#frag%2F"
        #expect(TerminalHyperlink(destination: web).opening == "\u{1B}]8;;\(web)\u{1B}\\")
    }

    /// An id is a parameter VALUE: `;` ends the parameter list, `:` separates
    /// parameters and `=` splits key from value, so in an id those three are
    /// the container's syntax and must be encoded — while in the URI, the
    /// last field, they are the URI's own and must not be.
    @Test("An id encodes its field syntax; the URI keeps its own")
    func parameterValueEncodesFieldSyntax() throws {
        #expect(TerminalHyperlink.encoded("a;b:c=d", in: .parameterValue) == "a%3Bb%3Ac%3Dd")
        #expect(TerminalHyperlink.encoded("a;b:c=d") == "a;b:c=d", "the URI is the last field")
        let link = TerminalHyperlink(destination: "https://x/?a=1;b", id: "row;2")
        #expect(link.opening == "\u{1B}]8;id=row%3B2;https://x/?a=1;b\u{1B}\\")
        #expect(TerminalHyperlink.opensLink(try #require(link.opening)))
    }

    /// The difference between the two sequences is the URI field, not the
    /// spelling — `ESC]8;;ST` names no destination, and that is precisely how
    /// OSC 8 says "the link ends here".
    @Test("Open and close are told apart by the URI field")
    func openAndCloseAreDistinguished() {
        #expect(TerminalHyperlink.opensLink("\u{1B}]8;;https://example.com\u{1B}\\"))
        #expect(TerminalHyperlink.opensLink("\u{1B}]8;id=x;https://example.com\u{07}"))
        #expect(!TerminalHyperlink.opensLink(TerminalHyperlink.closing))
        #expect(!TerminalHyperlink.opensLink("\u{1B}]8;;\u{07}"))
        #expect(!TerminalHyperlink.opensLink("\u{1B}]0;a title\u{07}"), "a different OSC command")
        #expect(!TerminalHyperlink.opensLink("\u{1B}[31m"))
    }
}

/// The two rules the OSC 8 specification and Ghostty's reference add to the
/// encoding: a `file:` link names its host, and a link too long for a terminal
/// to keep is not sent at all.
@Suite("OSC 8 file links and the length cap")
struct TerminalHyperlinkFileAndCapTests {

    private static func uri(_ destination: String, host: String? = "box") -> String? {
        TerminalHyperlink(destination: destination, localHostName: host).opening.map {
            String($0.dropFirst(TerminalHyperlink.introducer.count + 1).dropLast(2))
        }
    }

    /// `URL(fileURLWithPath:)` spells a local file `file:///path`, with an
    /// empty host, and Ghostty refuses that: a link to a local file did
    /// nothing on the host that otherwise handles OSC 8 best.
    @Test("A file URI with no host is given this machine's name")
    func hostlessFileLinkNamesTheHost() {
        #expect(Self.uri("file:///tmp/notes.txt") == "file://box/tmp/notes.txt")
        #expect(Self.uri("file:/tmp/notes.txt") == "file://box/tmp/notes.txt", "no authority at all")
        #expect(Self.uri("FILE:///tmp/x") == "FILE://box/tmp/x", "the scheme is case-blind, and kept")
        // The host goes in before encoding, and the path is encoded as ever.
        #expect(Self.uri("file:///tmp/a b") == "file://box/tmp/a%20b")
        // An escape the path already has is kept: Foundation's spelling of
        // `/Users/robot/Read me.txt` reaches the host as it is.
        let fromFoundation = "file:///Users/robot/Read%20me.txt"
        #expect(Self.uri(fromFoundation) == "file://box/Users/robot/Read%20me.txt")
    }

    @Test("A file URI that names a host keeps it, localhost included")
    func explicitHostsAreLeftAlone() {
        #expect(Self.uri("file://localhost/tmp/x") == "file://localhost/tmp/x")
        #expect(Self.uri("file://elsewhere.example/tmp/x") == "file://elsewhere.example/tmp/x")
    }

    @Test("Without a usable host name, and away from file:, nothing is rewritten")
    func otherURIsAreLeftAlone() {
        #expect(Self.uri("file:///tmp/x", host: nil) == "file:///tmp/x")
        #expect(Self.uri("file:///tmp/x", host: "") == "file:///tmp/x")
        // A name that is not a host name would change what the URI says.
        #expect(Self.uri("file:///tmp/x", host: "evil/../x") == "file:///tmp/x")
        #expect(Self.uri("file:///tmp/x", host: "user@box") == "file:///tmp/x")
        #expect(Self.uri("https:///tmp/x") == "https:///tmp/x")
        #expect(Self.uri("filer:///tmp/x") == "filer:///tmp/x")
        #expect(Self.uri("file:relative") == "file:relative")
        #expect(Self.uri("file:") == "file:")
    }

    /// VTE and iTerm2 drop a link over 2083 bytes and Ghostty 1.1.1 fixed a
    /// crash on very large ones, so a longer one is not sent, and the label
    /// draws as it is.
    @Test("A URI over 2083 bytes, encoded, is not sent")
    func overLongURIsAreNotSent() {
        let prefix = "https://x/"
        let atCap = prefix + String(repeating: "a", count: TerminalHyperlink.maximumURILength - prefix.count)
        #expect(TerminalHyperlink(destination: atCap).opening != nil)
        #expect(TerminalHyperlink(destination: atCap + "a").opening == nil)
        // The ENCODED length: 700 spaces are 2,100 bytes once each is `%20`.
        #expect(TerminalHyperlink(destination: prefix + String(repeating: " ", count: 700)).opening == nil)
        // The host a file link gains counts too.
        let file = "file:///" + String(repeating: "a", count: TerminalHyperlink.maximumURILength - 8)
        #expect(TerminalHyperlink(destination: file).opening != nil)
        #expect(TerminalHyperlink(destination: file, localHostName: "box").opening == nil)
        // A string linked to one is the string as it was, with no sequence.
        #expect("Docs".hyperlinked(to: TerminalHyperlink(destination: atCap + "a")) == "Docs")
    }
}

/// What a cut does to a link, which is the half that can go wrong invisibly in
/// one direction and very visibly in the other.
@Suite("A hyperlink across a cut")
struct HyperlinkCutTests {

    static let url = "https://example.com/a;b[c]m"
    static let opening = "\u{1B}]8;;\(url)\u{1B}\\"
    static let closing = TerminalHyperlink.closing

    /// Whether `line` leaves a link open at its end — the property every cut
    /// must preserve, and the one whose failure spreads.
    static func leavesLinkOpen(_ line: String) -> Bool {
        var scan = HyperlinkScan()
        for segment in line.ansiSegments() {
            if case .ansi(let sequence, _) = segment { scan.note(sequence) }
        }
        return scan.opening != nil
    }

    static func linked(_ text: String) -> String { opening + text + closing }

    // MARK: - Prefixes

    /// A prefix that keeps the opening sequence and loses the closing one does
    /// not merely lose the link: on a host that honours OSC 8 every cell drawn
    /// afterwards joins it — the rest of the row, its padding included.
    @Test("A prefix cut inside a link closes it", arguments: 1...5)
    func prefixClosesTheLink(cut: Int) {
        let line = Self.linked("Documentation")
        let (prefix, width) = line.exactAnsiAwarePrefixWithWidth(visibleCount: cut)
        #expect(width == cut)
        #expect(prefix.strippedLength == cut)
        #expect(!Self.leavesLinkOpen(prefix))
        #expect(prefix.hasSuffix(Self.closing))
    }

    /// …and the Terminal.app clip, which is a second walk with the same job.
    @Test("The Terminal.app prefix closes it too")
    func terminalAppPrefixClosesTheLink() {
        let prefix = Self.linked("Documentation")
            .exactAnsiAwarePrefixForTerminalAppWithWidth(visibleCount: 4).prefix
        #expect(prefix.stripped == "Docu")
        #expect(!Self.leavesLinkOpen(prefix))
    }

    /// The fast paths return `self` untouched when the line already fits, so
    /// the walk must not add a sequence at the natural end of the string —
    /// they are required to be byte-identical for every input.
    @Test("An uncut prefix is byte-identical, link or no link")
    func uncutPrefixIsUnchanged() {
        for line in [Self.linked("Docs"), "plain", Self.opening + "unbalanced"] {
            let width = line.strippedLength
            #expect(line.exactAnsiAwarePrefixWithWidth(visibleCount: width).prefix == line)
            #expect(line.ansiAwarePrefixWithWidth(visibleCount: width).prefix == line)
            #expect(
                line.ansiAwarePrefixWithWidth(visibleCount: width, knownVisibleWidth: width).prefix
                    == line)
        }
    }

    // MARK: - Suffixes and slices

    /// The quiet obligation: nothing looks broken when it is missed, the link
    /// is simply shorter than the label it belongs to.
    @Test("A suffix beginning inside a link re-opens it")
    func suffixReopensTheLink() {
        let suffix = Self.linked("Documentation").ansiAwareSuffix(droppingVisible: 4)
        #expect(suffix.stripped == "mentation")
        #expect(suffix.hasPrefix(Self.opening))
        #expect(!Self.leavesLinkOpen(suffix))
    }

    /// A link that opened AND closed before the boundary is not in force
    /// there, so nothing is owed. The state has to be tracked rather than
    /// accumulated, which is what tells this case from the one above.
    @Test("A link that closed before the boundary is not re-opened")
    func closedLinkIsNotReopened() {
        let line = Self.linked("Docs") + " and more text"
        let suffix = line.ansiAwareSuffix(droppingVisible: 6)
        #expect(suffix.stripped == "nd more text")
        #expect(!suffix.contains(Self.url))
    }

    @Test("A slice inside a link carries it in and closes it on the way out")
    func sliceCarriesAndCloses() {
        let line = "lead " + Self.linked("Documentation") + " tail"
        let slice = line.ansiAwareSlice(visibleStart: 7, visibleCount: 5)
        #expect(slice.stripped == "cumen")
        #expect(slice.contains(Self.url), "the link the window is inside")
        #expect(!Self.leavesLinkOpen(slice))
    }

    @Test("A slice past the link carries nothing")
    func sliceOutsideCarriesNothing() {
        let line = Self.linked("Docs") + " and more text"
        let slice = line.ansiAwareSlice(visibleStart: 5, visibleCount: 3)
        #expect(slice.stripped == "and")
        #expect(!slice.contains(Self.url))
    }

    // MARK: - The overlay split

    /// One scan, two cuts at different columns: the prefix ends where the
    /// overlay begins and owes a close (an open link would run under the
    /// overlay), and the suffix begins past the overlay's right edge and owes
    /// the opening sequence.
    @Test("The overlay split closes its prefix and resumes its suffix")
    func overlaySplitBalancesBothHalves() {
        let split = Self.linked("Documentation").ansiOverlaySplit(
            prefixColumns: 3, suffixDropColumns: 8)
        #expect(split.prefix.stripped == "Doc")
        #expect(!Self.leavesLinkOpen(split.prefix))
        #expect(split.suffix.stripped == "ation")
        #expect(split.suffix.hasPrefix(Self.opening))
        #expect(!Self.leavesLinkOpen(split.suffix))
    }

    /// A line SHORTER than the overlay's column never reaches the cut inside
    /// the walk, and the overlay is composited straight after it either way.
    @Test("A short line's link is still closed before the overlay")
    func shortLineStillCloses() {
        let split = (Self.opening + "Docs").ansiOverlaySplit(
            prefixColumns: 40, suffixDropColumns: 40)
        #expect(split.prefix.stripped == "Docs")
        #expect(!Self.leavesLinkOpen(split.prefix))
    }

    // MARK: - The buffer, end to end

    /// The property that actually matters, asked of the primitive every
    /// container clips through rather than of the walks underneath it.
    @Test("Clamping a buffer never leaves a link open", arguments: 1...8)
    func clampedBufferIsBalanced(width: Int) {
        let buffer = FrameBuffer(lines: [Self.linked("Documentation")])
        let clamped = buffer.clamped(toWidth: width, height: 1)
        #expect(clamped.width == min(width, 13))
        for line in clamped.lines {
            #expect(!Self.leavesLinkOpen(line))
        }
    }
}
