//  🖥️ TUI — A Terminal UI framework for Swift
//  AnimationPageShowHideTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import Example
import TUI
@testable import TUIFoundation
import TUITesting

/// What the panel says, as the page draws it: the key's English text when the
/// Example's strings are registered, and the key itself when — as in this
/// process — they are not.
@MainActor
private var panelText: String { LocalizationService.shared.string(for: "page.animation.panel") }

// MARK: - The slot, in a page of nothing else

/// The Animation page's "Coming and going" demo reduced to what drives it: a
/// button that toggles the panel inside a one-second linear `withAnimation`,
/// and the page's own slot, ``AnimationPage/panelSlot(showsPanel:space:transition:)``,
/// standing in a scrolling stack exactly as it stands in the page's — the
/// `if` with its `.transition`, in a stack under one `.frame(height:)` that
/// is `nil` unless the space is kept.
///
/// The slot is the page's, not a copy of its shape: the shape is exactly what
/// went wrong, twice, and a copy went on passing when the page's own was put
/// back the way it had been. What this adds to the whole page below is the
/// timing — a linear second, so a picture can be checked against how far the
/// removal has got — and the transitions the page offers only through a menu.
private struct PanelPage: View {
    @State private var showsPanel = false
    let space: AnimationPage.PanelSpace
    let transition: AnyTransition

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                Button("toggle") {
                    withAnimation(.linear(duration: 1)) { showsPanel.toggle() }
                }
                AnimationPage.panelSlot(
                    showsPanel: showsPanel, space: space, transition: transition)
                Text("below")
            }
        }
        .scrollIndicators(.automatic)
    }
}

/// A page in a ``TestApp``, with what these tests read of it: where a line is,
/// and what colour it is drawn in.
@MainActor
private final class PageDriver {
    private let app: TestApp
    /// The text on the first line below the panel's slot.
    private let belowText: String

    init(_ app: TestApp, belowText: String) {
        self.app = app
        self.belowText = belowText
        _ = app.screen
    }

    /// The instant of the last frame drawn.
    var now: Duration { app.elapsed }

    /// Presses the focused control's key — the page's one button, when there
    /// is only one. Whether it took the key.
    func pressFocused() -> Bool { app.press(.enter) }

    /// Clicks the middle of `text`, where it first appears. Whether it was there.
    func click(_ text: String) -> Bool { (try? app.click(text)) != nil }

    /// Moves the clock on by `millis`, drawing the frames the page asks for.
    func advance(byMillis millis: Int) {
        app.advance(by: .milliseconds(millis))
    }

    /// Renders ONE frame, `millis` from now: for a page too large to draw
    /// every frame of, where only the instants asked about matter.
    func jump(byMillis millis: Int) {
        app.headless.frame(atNanos: app.headless.lastFrameNanos + Int64(millis) * 1_000_000)
    }

    var screen: [String] { app.screen.styledLines }

    /// Where `text` first appears on screen, styling stripped: row and column.
    /// Only the rows above `limit` are searched when one is given.
    func position(of text: String, above limit: Int? = nil) -> (row: Int, column: Int)? {
        for (row, line) in screen.map(\.stripped).enumerated() where row < (limit ?? screen.count) {
            if let range = line.range(of: text) {
                return (row, line.distance(from: line.startIndex, to: range.lowerBound))
            }
        }
        return nil
    }

    /// The 24-bit colours `text` is drawn in, where it first appears: the last
    /// foreground and the last background stated before it on its row.
    func colours(of text: String) -> (ink: [Int], page: [Int])? {
        guard let line = screen.first(where: { $0.contains(text) }),
            let range = line.range(of: text)
        else { return nil }
        let before = line[..<range.lowerBound]
        func lastColour(introducedBy introducer: String) -> [Int]? {
            guard let start = before.range(of: introducer, options: .backwards) else { return nil }
            let channels = before[start.upperBound...]
                .split(separator: ";", maxSplits: 3, omittingEmptySubsequences: false)
                .prefix(3)
                .compactMap { Int($0.prefix(while: \.isNumber)) }
            return channels.count == 3 ? channels : nil
        }
        guard let ink = lastColour(introducedBy: "38;2;"), let page = lastColour(introducedBy: "48;2;")
        else { return nil }
        return (ink, page)
    }

    /// The row the line below the slot is on.
    var belowRow: Int? { position(of: belowText)?.row }

    /// The panel's top-left corner: the first `╭` above the line below it.
    /// Bounded because the status bar is drawn in the same rounded border, at
    /// column 0 — where the panel's own corner starts too.
    var panelCorner: (row: Int, column: Int)? {
        guard let below = belowRow else { return nil }
        return position(of: "╭", above: below)
    }
}

/// Whether `ink` is `original` with only `fraction` of its difference from
/// `page` left, to within the one-unit rounding of 8-bit channels: the
/// encoded-sRGB mix a fade draws (`OpacityFade`).
private func isBlend(
    _ ink: [Int], of original: [Int], toward page: [Int], keeping fraction: Double
) -> Bool {
    guard ink.count == 3, original.count == 3, page.count == 3 else { return false }
    return (0..<3).allSatisfy { channel in
        let expected = Double(page[channel]) + fraction * Double(original[channel] - page[channel])
        return abs(Double(ink[channel]) - expected) <= 1
    }
}

@MainActor
@Suite("The Animation page's Show / hide plays the removal")
struct AnimationPageShowHideTests {

    private func panelPage(space: AnimationPage.PanelSpace, transition: AnyTransition) -> PageDriver {
        PageDriver(TestApp(width: 40, height: 20) { PanelPage(space: space, transition: transition) }, belowText: "below")
    }

    private func panelPage(reservesSpace: Bool, transition: AnyTransition) -> PageDriver {
        panelPage(space: reservesSpace ? .kept : .closesUp, transition: transition)
    }

    /// SwiftUI's model, measured (`Tools/SwiftUIProbes/Insertion and removal (FB16)/samples.txt`): the space goes on
    /// the frame the panel does, and the page below glides up into it while
    /// the panel slides out where it was. Kept, nothing below moves at all.
    @Test("Hiding the panel slides it out in place, the page below gliding up or kept still",
        arguments: [false, true])
    func hidingSlidesOut(reservesSpace: Bool) {
        let page = panelPage(reservesSpace: reservesSpace, transition: .move(edge: .trailing))
        #expect(page.pressFocused(), "precondition: the button took the key")
        page.advance(byMillis: 1200)
        let shownCorner = page.panelCorner
        let shownBelow = page.belowRow
        #expect(shownCorner != nil && shownBelow != nil, "precondition: the panel arrived")
        guard let shownCorner, let shownBelow else { return }

        #expect(page.pressFocused(), "precondition: the button took the key")
        page.advance(byMillis: 17)
        #expect(
            page.panelCorner.map { $0 == shownCorner } == true,
            "the panel was gone on the first frame of its removal:\n\(page.screen.map(\.stripped))")
        #expect(page.belowRow == shownBelow, "the page below jumped on the first frame of the removal")

        page.advance(byMillis: 500)
        // In its own row, past half-way, whether or not the space is given
        // back: the slot's stack, empty now, takes no gap, so its place in
        // the page moved up a row — but a view leaving plays where it was.
        #expect(
            page.panelCorner.map { $0.row == shownCorner.row && $0.column > shownCorner.column } == true,
            "not sliding out half-way, in its own row:\n\(page.screen.map(\.stripped))")
        if reservesSpace {
            #expect(page.belowRow == shownBelow, "the kept space was given back")
        } else {
            #expect(
                page.belowRow.map { $0 > shownBelow - 6 && $0 < shownBelow } == true,
                "the page below is not on its way up half-way: \(page.belowRow ?? -1)")
        }

        page.advance(byMillis: 700)
        #expect(page.panelCorner == nil, "still drawn after the removal ended")
        #expect(page.belowRow == (reservesSpace ? shownBelow : shownBelow - 6))
    }

    /// The page's default transition, and the one whose failure the owner saw.
    ///
    /// A fade is the panel's ink blended toward the page by how far the
    /// removal has got, so that is what is checked, at two instants: not
    /// merely that the row changed, which a panel drawn in some other colour,
    /// or one frozen part-way, would pass as well. 24-bit colour so the blend
    /// can be read off the escapes without a palette's rounding.
    @Test("Hiding the panel fades it out, with the space kept or not", arguments: [false, true])
    func hidingFadesOut(reservesSpace: Bool) {
        ColorDepth.withCurrent(.truecolor) {
            let page = panelPage(reservesSpace: reservesSpace, transition: .opacity)
            #expect(page.pressFocused(), "precondition: the button took the key")
            page.advance(byMillis: 1200)
            let shownPanel = page.position(of: panelText)
            let shown = page.colours(of: panelText)
            #expect(shownPanel != nil && shown != nil, "precondition: the panel arrived")
            guard let shownPanel, let shown else { return }

            #expect(page.pressFocused(), "precondition: the button took the key")
            // The removal starts on the frame the key causes.
            let removedAt = page.now
            for millis in [250, 250] {
                page.advance(byMillis: millis)
                let elapsed = (page.now - removedAt) / .seconds(1)
                #expect(
                    page.position(of: panelText).map { $0 == shownPanel } == true,
                    "the panel was gone \(elapsed) s into its one-second removal")
                let drawn = page.colours(of: panelText)
                let fades = drawn.map {
                    isBlend($0.ink, of: shown.ink, toward: shown.page, keeping: 1 - elapsed)
                }
                #expect(drawn?.page == shown.page, "the page under the panel changed colour")
                #expect(
                    fades == true,
                    "\(elapsed) s in, the panel's ink \(drawn?.ink ?? []) is not \(shown.ink) blended toward the page \(shown.page)")
            }

            page.advance(byMillis: 1000)
            #expect(page.position(of: panelText) == nil, "still drawn after the removal ended")
        }
    }

    /// What the toggle is for. Kept, the slot is the panel's five rows whether
    /// the panel is there or not — before it is ever shown, while it is, and
    /// after it has gone — so nothing below it ever moves. Given back, the page
    /// closes up once the panel has gone: five rows and the stack's spacing.
    @Test("With the space kept nothing below the panel moves; without it the page closes up",
        arguments: [false, true])
    func spaceIsKeptOrGivenBack(reservesSpace: Bool) {
        let page = panelPage(reservesSpace: reservesSpace, transition: .opacity)
        let before = page.belowRow
        #expect(page.pressFocused(), "precondition: the button took the key")
        page.advance(byMillis: 1200)
        let shown = page.belowRow
        #expect(page.pressFocused(), "precondition: the button took the key")
        page.advance(byMillis: 1200)
        let after = page.belowRow
        #expect(before != nil && shown != nil, "precondition: the page is drawn")
        guard let before, let shown else { return }

        if reservesSpace {
            #expect(before == shown, "showing the panel moved what is below it")
            #expect(after == shown, "hiding the panel gave its space back")
        } else {
            #expect(before == shown - 6)
            #expect(after == before, "the page did not close up after the panel went")
        }
    }

    /// The default: what SwiftUI's stack does with any insertion and removal
    /// under `withAnimation` — the page below is pushed down as the panel
    /// arrives, part-way part-way through, and drawn back up as it goes.
    @Test("By default the page below glides with the panel as it comes and goes")
    func pageBelowGlides() {
        let page = panelPage(space: .closesUp, transition: .opacity)
        let before = page.belowRow
        #expect(page.pressFocused(), "precondition: the button took the key")
        page.advance(byMillis: 500)
        let arriving = page.belowRow
        page.advance(byMillis: 700)
        let shown = page.belowRow
        #expect(page.pressFocused(), "precondition: the button took the key")
        page.advance(byMillis: 500)
        let going = page.belowRow
        page.advance(byMillis: 700)
        let after = page.belowRow
        guard let before, let arriving, let shown, let going, let after else {
            Issue.record("the page is drawn")
            return
        }
        #expect(before < arriving && arriving < shown, "the page below moved part-way: \(before), \(arriving), \(shown)")
        #expect(shown == before + 6, "pushed by the panel's rows and a gap: \(before) → \(shown)")
        #expect(after < going && going < shown, "and back up part-way: \(shown), \(going), \(after)")
        #expect(after == before)
    }

    /// Held (`.transitionSpace(.held)`): the space stays while the panel
    /// leaves, so the page below stands still under the removal, and goes at
    /// once when the panel has gone.
    @Test("Held, the page below stands still while the panel leaves, then closes up")
    func heldSpaceStandsStill() {
        let page = panelPage(space: .held, transition: .opacity)
        let before = page.belowRow
        #expect(page.pressFocused(), "precondition: the button took the key")
        page.advance(byMillis: 1200)
        let shown = page.belowRow
        #expect(page.pressFocused(), "precondition: the button took the key")
        page.advance(byMillis: 500)
        let going = page.belowRow
        page.advance(byMillis: 700)
        let after = page.belowRow
        guard let before, let shown, let going, let after else {
            Issue.record("the page is drawn")
            return
        }
        #expect(shown == before + 6)
        #expect(going == shown, "the page below moved while the panel left: \(shown) → \(going)")
        #expect(after == before, "the page did not close up after the panel went")
    }

    // MARK: - The whole page

    /// The page itself, as the owner used it: the demo's own buttons clicked,
    /// its default fade on its default curve, and whatever else the page
    /// draws around the slot. Not timed against the curve — the page's curve
    /// is the page's to change — so the fade is checked for being part-way,
    /// neither the ink it was drawn in nor the page behind it.
    @Test("On the page itself, Show / hide fades the panel out, the page gliding up unless the space is kept",
        arguments: [false, true])
    func wholePageFadesAndKeepsItsSpace(reservesSpace: Bool) {
        ColorDepth.withCurrent(.truecolor) {
            // Tall enough for the whole page down to its keyboard help, the
            // matched geometry demo above it included.
            let page = PageDriver(
                TestApp(width: 100, height: 100) { AnimationPage() }, belowText: "demo.keyboardControls")
            if reservesSpace {
                // "Its space" is a picker: opened on its value, then the choice.
                #expect(page.click("page.animation.space.closesUp"), "precondition: the picker took the click")
                page.jump(byMillis: 17)
                #expect(page.click("page.animation.reserveSpace"), "precondition: the menu took the click")
                page.jump(byMillis: 17)
            }
            let before = page.belowRow
            #expect(page.click("page.animation.button.toggle"), "precondition: the button took the click")
            // The frame that shows the change, where everything below the
            // panel still stands where it was and starts to glide down.
            page.jump(byMillis: 17)
            page.jump(byMillis: 800)
            let shownPanel = page.position(of: panelText)
            let shown = page.colours(of: panelText)
            let shownBelow = page.belowRow
            #expect(
                shownPanel != nil && shown != nil && before != nil && shownBelow != nil,
                "precondition: the panel arrived:\n\(page.screen.map(\.stripped))")
            guard let shownPanel, let shown, let before, let shownBelow else { return }
            #expect(
                shownBelow == (reservesSpace ? before : before + 6),
                "showing the panel moved what is below it by \(shownBelow - before) rows")

            #expect(page.click("page.animation.button.toggle"), "precondition: the button took the click")
            page.jump(byMillis: 17)
            #expect(
                page.position(of: panelText).map { $0 == shownPanel } == true,
                "the panel was gone on the first frame of its removal:\n\(page.screen.map(\.stripped))")
            #expect(page.belowRow == shownBelow, "the page closed up on the first frame of the removal")

            // Half-way through the page's default curve.
            page.jump(byMillis: 283)
            let drawn = page.colours(of: panelText)
            #expect(
                page.position(of: panelText).map { $0 == shownPanel } == true,
                "the panel was gone part-way through its removal")
            #expect(
                drawn.map { $0.ink != shown.ink && $0.ink != shown.page } == true,
                "part-way out, the panel's ink \(drawn?.ink ?? []) is not between \(shown.ink) and the page \(shown.page)")
            if reservesSpace {
                #expect(page.belowRow == shownBelow, "the kept space was given back")
            } else {
                #expect(
                    page.belowRow.map { $0 > before && $0 < shownBelow } == true,
                    "the page below is not on its way up part-way through the removal")
            }

            page.jump(byMillis: 700)
            #expect(page.position(of: panelText) == nil, "still drawn after the removal ended")
            #expect(
                page.belowRow == (reservesSpace ? shownBelow : before),
                reservesSpace ? "hiding the panel gave its space back" : "the page did not close up")
        }
    }
}
