//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LinkHyperlinkTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUIkit
@testable import TUIkitApp
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTerminalHost
@testable import TUIkitView

/// ``Link``'s OSC 8 half: what it emits, when, and the property that must hold
/// however the label is laid out.
///
/// The support flag is pinned task-locally rather than assigned, so these run
/// alongside every other suite without putting hyperlinks into anybody else's
/// rendering.
@MainActor
@Suite("Link terminal hyperlinks")
struct LinkHyperlinkTests {

    private let url = URL(string: "https://example.com/docs")!

    private func render(_ view: some View, width: Int = 40, height: Int = 6) -> FrameBuffer {
        renderToBuffer(view, context: makeRenderContext(width: width, height: height))
    }

    /// Whether `line` leaves a link open at its end — the property whose
    /// failure spreads past the control and down the row.
    private func leavesLinkOpen(_ line: String) -> Bool {
        var scan = HyperlinkScan()
        for segment in line.ansiSegments() {
            if case .ansi(let sequence, _) = segment { scan.note(sequence) }
        }
        return scan.opening != nil
    }

    @Test("A supported host gets the sequence, and it costs no cells")
    func supportedHostGetsTheLink() {
        let view = Link("swift.org", destination: url)
        let without = TerminalHyperlink.withSupport(false) { render(view) }
        let with = TerminalHyperlink.withSupport(true) { render(view) }

        #expect(!without.lines.joined().contains("\u{1B}]8;"))
        #expect(with.lines.joined().contains("\u{1B}]8;;https://example.com/docs\u{1B}\\"))
        #expect(with.lines.joined().hasSuffix(TerminalHyperlink.closing))
        // The whole point of an escape: the layout is the same either way.
        #expect(with.width == without.width)
        #expect(with.lines.map(\.strippedLength) == without.lines.map(\.strippedLength))
        #expect(with.lines.map(\.stripped) == without.lines.map(\.stripped))
    }

    /// `URL(fileURLWithPath:)` spells a local file with an empty host, and
    /// Ghostty refuses such a link. The link names this machine instead, as
    /// the OSC 8 specification asks: over ssh, the remote one.
    ///
    /// The machine's name is pinned, so this asks the same question whatever
    /// the machine running it is called — a name that is not a plain host
    /// name is not used at all, which is the second half.
    @Test("A link to a local file names this machine as its host")
    func fileLinkNamesTheHost() {
        let file = URL(fileURLWithPath: "/tmp/notes.txt")
        func drawn(onHost host: String) -> String {
            TerminalClient.$localHostNamePin.withValue(host) {
                TerminalHyperlink.withSupport(true) {
                    render(Link("notes", destination: file)).lines.joined()
                }
            }
        }
        let named = drawn(onHost: "box")
        #expect(named.contains("\u{1B}]8;;file://box/tmp/notes.txt\u{1B}\\"), "\(named.debugDescription)")
        #expect(!named.contains("file:///"))

        let unusable = drawn(onHost: "user@box")
        #expect(unusable.contains("\u{1B}]8;;file:///tmp/notes.txt\u{1B}\\"), "\(unusable.debugDescription)")
    }

    /// `Link` sends `URL.absoluteString`, which Foundation has already
    /// percent-encoded. Encoding its `%` again sent `Read%2520me.txt`, which a
    /// terminal decodes once, to a file called `Read%20me.txt` that is not
    /// there. The path's part of the URI does not depend on the host name, so
    /// these hold whatever this machine is called.
    @Test("A link to a file with a space or an accent in its name is encoded once")
    func fileLinkIsEncodedOnce() {
        func drawn(_ destination: URL) -> String {
            TerminalHyperlink.withSupport(true) {
                render(Link("file", destination: destination)).lines.joined()
            }
        }
        let spaced = drawn(URL(fileURLWithPath: "/Users/x/Read me.txt"))
        #expect(spaced.contains("/Users/x/Read%20me.txt\u{1B}\\"), "\(spaced.debugDescription)")
        #expect(!spaced.contains("%25"))

        let accentedURL = URL(fileURLWithPath: "/Users/x/café.txt")
        let accented = drawn(accentedURL)
        // Foundation's own escapes, however it spelled the é (Darwin's
        // decomposes it, `e%CC%81`): its URI less the `file://` the host name
        // goes after.
        let accentedPath = String(accentedURL.absoluteString.dropFirst("file://".count))
        #expect(accentedPath.hasPrefix("/Users/x/caf") && accentedPath.contains("%"), "an escaped é")
        #expect(accented.contains(accentedPath + "\u{1B}\\"), "\(accented.debugDescription)")
        #expect(!accented.contains("%25"))

        // A web URL that already carries escapes reaches the host unchanged.
        let web = URL(string: "https://example.com/a%20b/caf%C3%A9?q=%26x")!
        #expect(drawn(web).contains("\u{1B}]8;;https://example.com/a%20b/caf%C3%A9?q=%26x\u{1B}\\"))
    }

    /// VTE and iTerm2 drop a link over 2083 bytes, so it is not sent: the
    /// label draws as it is, which is what a host that dropped it would show.
    @Test("A link too long for a terminal to keep draws its label without one")
    func overLongLinkDrawsWithoutTheSequence() throws {
        let long = try #require(URL(string: "https://example.com/" + String(repeating: "a", count: 2100)))
        let drawn = TerminalHyperlink.withSupport(true) { render(Link("long", destination: long)) }
        let without = TerminalHyperlink.withSupport(false) { render(Link("long", destination: long)) }
        #expect(!drawn.lines.joined().contains("\u{1B}]8;"))
        #expect(drawn.lines == without.lines)
    }

    /// A disabled link is skipped by Tab, registers no region and never runs
    /// its action — and a terminal that honours OSC 8 opens a linked cell on
    /// its OWN gesture, past all of that. iTerm2 opens on every click.
    @Test("A disabled link carries no hyperlink for the terminal to open")
    func disabledLinkHasNoHyperlink() {
        let disabled = TerminalHyperlink.withSupport(true) {
            render(Link("swift.org", destination: url).disabled(true))
        }
        #expect(!disabled.lines.joined().contains("\u{1B}]8;"), "\(disabled.lines)")
        let enabled = TerminalHyperlink.withSupport(true) { render(Link("swift.org", destination: url)) }
        #expect(enabled.lines.joined().contains("\u{1B}]8;"), "the rule is about disabled, not about support")
    }

    /// Renders `view` in a pass that lets the link register and take the
    /// focus, then again — so the second buffer is the FOCUSED one, breath
    /// runs and all.
    private func focusedRender(_ view: some View) -> FrameBuffer {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: 40, availableHeight: 6, environment: environment, tuiContext: tui)
        var buffer = FrameBuffer()
        for _ in 0..<2 {
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            environment.focusManager?.beginRenderPass()
            buffer = renderToBuffer(view, context: context)
            environment.focusManager?.endRenderPass()
            tui.stateStorage.endRenderPass()
        }
        return buffer
    }

    /// A focused link breathes by REPLACING its cells with pre-rendered
    /// frames, and the splice closes any open link at the cut. Frames without
    /// their own pair stripped the hyperlink from the one link the user had
    /// selected, on the first tick.
    @Test("A focused link's breath frames carry the hyperlink too")
    func breathFramesKeepTheLink() {
        let buffer = TerminalHyperlink.withSupport(true) {
            focusedRender(Link("swift.org", destination: url))
        }
        #expect(!buffer.animatedCells.isEmpty, "a focused link breathes")
        for run in buffer.animatedCells {
            for frame in run.frames {
                #expect(frame.contains("\u{1B}]8;;https://"), "a frame without the link: \(frame.debugDescription)")
                #expect(!leavesLinkOpen(frame))
            }
        }
    }

    /// A run can carry what its cells owe per frame (`AnimatedRunAlpha`), and when it
    /// does the run is the ONLY thing saying so: a blinking caret over a faded well has
    /// no rectangle true of both its frames. The link rebuilds every run to give its
    /// frames their own pair, and rebuilt field by field it dropped that payload — so a
    /// text field in a link's label replayed its well at full strength on a host that
    /// honours OSC 8, and faded correctly on one that does not.
    ///
    /// The oracle is the same view without the hyperlink: the escapes cost no cells and
    /// the spans are run-relative, so the payload must come through unchanged.
    @Test("A label's run keeps its per-frame alpha through the hyperlink")
    func runAlphaSurvivesTheLink() throws {
        func drawn() -> FrameBuffer {
            let tui = TUIContext()
            var environment = EnvironmentValues()
            environment.palette = FadedAll()
            environment.applyRuntimeServices(from: tui)
            // Its own focus manager, or the field is not focused and has no caret.
            environment.focusManager = FocusManager()
            let context = RenderContext(
                availableWidth: 40, availableHeight: 3, environment: environment, tuiContext: tui
            ).isolatingRenderCache()
            // A URL mode, so the label is not wrapped in a button and the field is the
            // one focusable thing on the page.
            let view = Link(destination: url) {
                TextField("label", text: .constant("abc")).textCursor(.block, animation: .blink)
            }
                .linkDisplay(.urlInParentheses)
            return renderToBuffer(view, context: context)
        }
        let plain = TerminalHyperlink.withSupport(false) { drawn() }
        let linked = TerminalHyperlink.withSupport(true) { drawn() }

        let expected = try #require(
            plain.animatedCells.first { $0.alpha != nil },
            "the premise: the caret's run states its alpha when nothing rebuilds it")
        let caret = try #require(
            linked.animatedCells.first { $0.offsetX == expected.offsetX && $0.offsetY == expected.offsetY },
            "the caret still animates: \(linked.animatedCells.map { ($0.offsetX, $0.offsetY) })")
        #expect(caret.frames.allSatisfy { $0.contains("\u{1B}]8;;https://") }, "the premise: it was rebuilt")
        #expect(caret.alpha == expected.alpha, "the payload came through: \(String(describing: caret.alpha))")
    }

    /// A terminal-owned ⌘-click goes to the system opener over the top of
    /// ``OpenURLAction``, so an app that intercepts its own scheme needs a way
    /// to keep every URL for itself.
    @Test(".terminalHyperlinks(false) removes it on a host that would honour it")
    func subtreeCanOptOut() {
        let opted = TerminalHyperlink.withSupport(true) {
            render(VStack { Link("swift.org", destination: url) }.terminalHyperlinks(false))
        }
        #expect(!opted.lines.joined().contains("\u{1B}]8;"))
        #expect(opted.lines.joined().contains("swift.org"))
    }

    /// One balanced pair per LINE. A pair spanning rows would be split by any
    /// container that clipped between them, and a row whose link is left open
    /// hands it to everything drawn after it.
    @Test("Every row is balanced, and a multi-row label shares one id")
    func everyRowIsSelfContained() {
        let wrapped = TerminalHyperlink.withSupport(true) {
            render(Link("a documentation link long enough to wrap", destination: url), width: 14)
        }
        #expect(wrapped.lines.count > 1, "the label has to wrap for this to test anything")
        for line in wrapped.lines {
            #expect(!leavesLinkOpen(line))
        }
        #expect(wrapped.lines.joined().contains("\u{1B}]8;id="), "runs of one link share an id")

        // …and a single-run link spends no bytes on an identity it cannot use.
        let single = TerminalHyperlink.withSupport(true) {
            render(Link("swift.org", destination: url))
        }
        #expect(!single.lines.joined().contains("id="))
    }

    /// The property asked of the thing a container actually does to a control
    /// too wide for it, rather than of the walk underneath.
    @Test("A clipped link never leaves the sequence open", arguments: 1...9)
    func clippingKeepsItBalanced(width: Int) {
        let clipped = TerminalHyperlink.withSupport(true) {
            render(Link("swift.org", destination: url).frame(width: width), width: width + 4)
        }
        for line in clipped.lines {
            #expect(!leavesLinkOpen(line))
        }
    }

    /// The clips above cut a link TUIkit itself emitted, which is balanced
    /// before anything pads it — so the cut lands outside the link and nothing
    /// is left open. The route that does leave one open is content the app
    /// hands in: `Text`, a `Table` cell and a `List` row all pass a raw OSC 8
    /// through unchanged, and `truncatedToWidth` then clips it.
    ///
    /// That clip took the byte-drop fast path in
    /// `ansiAwarePrefix(visibleCount:knownVisibleWidth:)`, which returned the
    /// line minus its trailing space bytes — byte-identical to the walk for
    /// everything EXCEPT the one thing the walk adds at a cut: the closing
    /// sequence of a link still open. The width re-scan guarding that path
    /// cannot see the difference, because a closing sequence is zero cells.
    /// The link then ran on over the ellipsis and over whatever the caller
    /// appended next — a row's fill and badge, the scrollbar column, the diff
    /// writer's padding — and a click anywhere along that opened the URL.
    @Test("A truncated line closes a hyperlink the content left open", arguments: 1...6)
    func truncatingClosesAnOpenHyperlink(excess: Int) {
        let raw = "\u{1B}]8;;https://example.com/docs\u{1B}\\click here      "
        let clipped = raw.truncatedToWidth(raw.strippedLength - excess)
        #expect(!leavesLinkOpen(clipped), "excess \(excess): \(clipped.debugDescription)")
    }

    /// A hyperlink is not styling, so it must not be mistaken for any: the
    /// label keeps its accent and its underline, and the row still measures
    /// what it paints.
    @Test("The link rides alongside the styling rather than replacing it")
    func stylingSurvives() {
        let styled = TerminalHyperlink.withSupport(true) {
            render(Link("swift.org", destination: url))
        }
        let joined = styled.lines.joined()
        // SGR 4 arrives folded into the run's colour (`ESC[4;38;2;…m`), which
        // is the point: the link and the styling are separate sequences and
        // neither has displaced the other.
        #expect(joined.contains("\u{1B}[4;") || joined.contains("\u{1B}[4m"), "still underlined")
        let lineLengths: Int = styled.lines.map(\.strippedLength).reduce(0, +)
        #expect(joined.strippedLength == lineLengths)
    }
}
