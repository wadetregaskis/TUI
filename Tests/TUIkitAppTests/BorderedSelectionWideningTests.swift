//  🖥️ TUIkit — Terminal UI Kit for Swift
//  BorderedSelectionWideningTests.swift
//
//  A drag begun inside a bordered container keeps to its interior (#10); one
//  that leaves the container by more than a few cells widens to the scope the
//  container sits in, and stays widened until the release (A-TEXT2-1, option
//  2, built as an experiment for the owner to try, 2026-10-24).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitApp
@testable import TUIkitAppTestSupport
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

@MainActor
@Suite("A drag that leaves a bordered container far enough widens its selection")
struct BorderedSelectionWideningTests {

    /// A card of two lines with a line of page text above and four below.
    struct Page: View {
        var body: some View {
            VStack(alignment: .leading) {
                Text("above the card")
                VStack(alignment: .leading) {
                    Text("Ada Lovelace")
                    Text("London")
                }
                .border()
                Text("row one below")
                Text("row two below")
                Text("row three below")
                Text("row four below")
            }
        }
    }

    /// A card inside a card, three lines of the outer one's own below the
    /// inner, and four lines of page below the outer.
    struct NestedPage: View {
        var body: some View {
            VStack(alignment: .leading) {
                Text("above the cards")
                VStack(alignment: .leading) {
                    VStack(alignment: .leading) {
                        Text("Ada Lovelace")
                        Text("London")
                    }
                    .border()
                    Text("outer line one")
                    Text("outer line two")
                    Text("outer line three")
                }
                .border()
                Text("page row one")
                Text("page row two")
                Text("page row three")
                Text("page row four")
            }
        }
    }

    /// The card and four lines below it inside an enabled `textSelection`
    /// that stops short of the page's last lines.
    struct ScopedPage: View {
        var body: some View {
            VStack(alignment: .leading) {
                VStack(alignment: .leading) {
                    VStack(alignment: .leading) {
                        Text("Ada Lovelace")
                        Text("London")
                    }
                    .border()
                    Text("scope row one")
                    Text("scope row two")
                    Text("scope row three")
                    Text("scope row four")
                }
                .textSelection(.enabled)
                Text("outside one")
                Text("outside two")
                Text("outside three")
                Text("outside four")
            }
        }
    }

    // MARK: - Harness

    func harness(_ page: some View) -> InputChainHarness {
        let harness = InputChainHarness(width: 40, height: 20)
        harness.frame(page)
        harness.frame(page)
        return harness
    }

    func find(_ needle: String, in harness: InputChainHarness, _ page: some View) throws -> (x: Int, y: Int) {
        let lines = harness.frame(page).lines.map(\.stripped)
        let row = try #require(lines.firstIndex { $0.contains(needle) })
        let prefix = try #require(lines[row].range(of: needle)).lowerBound
        return (lines[row][..<prefix].count, row)
    }

    /// Presses at `from`, drags through `steps` and releases at the last.
    func drag(_ harness: InputChainHarness, _ page: some View, from: (x: Int, y: Int), through steps: [(x: Int, y: Int)]) {
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: from.x, y: from.y))
        harness.frame(page)
        for step in steps {
            harness.mouse(MouseEvent(button: .left, phase: .dragged, x: step.x, y: step.y))
            harness.frame(page)
        }
        let end = steps.last ?? from
        harness.mouse(MouseEvent(button: .left, phase: .released, x: end.x, y: end.y))
        harness.frame(page)
    }

    /// The selected text, its rows' trailing blanks dropped.
    func selected(_ harness: InputChainHarness) -> String? {
        harness.tui.screenSelection.current?.text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0.reversed().drop { $0 == " " }.reversed()) }
            .joined(separator: "\n")
    }

    // MARK: - Tests

    @Test("The threshold: the border and two rows beyond it stay inside, as do the border and five columns beside it")
    func threshold() {
        let interior = ScreenSelection.Rect(x: 1, y: 2, width: 12, height: 2)
        func isPast(_ x: Int, _ y: Int) -> Bool { HeldPress.isPast(interior, ScreenSelection.Point(x: x, y: y)) }
        // Bottom border at row 4: rows 4, 5 and 6 keep to it, row 7 is past.
        #expect(!isPast(5, 4) && !isPast(5, 6))
        #expect(isPast(5, 7))
        // Top border at row 1: row -1 keeps to it, row -2 is past.
        #expect(!isPast(5, -1) && isPast(5, -2))
        // Right border at column 13: columns up to 18 keep to it, 19 is past.
        #expect(!isPast(18, 3) && isPast(19, 3))
        #expect(!isPast(-5, 3) && isPast(-6, 3))
    }

    @Test("A drag to the end of the card that overshoots the border by two rows keeps to the card")
    func endOfCardOvershootStaysInside() throws {
        let page = Page()
        let harness = harness(page)
        let ada = try find("Ada", in: harness, page)
        let two = try find("row two below", in: harness, page)
        drag(harness, page, from: ada, through: [(two.x + 4, two.y)])
        let text = try #require(selected(harness))
        #expect(text.contains("Ada Lovelace") && text.contains("London"), "the card's lines: \(text)")
        #expect(!text.contains("below") && !text.contains("│"), "the selection left the card: \(text)")
    }

    @Test("A drag three rows past the border widens to the page, and stays widened when the pointer comes back")
    func farDragWidensAndStays() throws {
        let page = Page()
        let harness = harness(page)
        let ada = try find("Ada", in: harness, page)
        let three = try find("row three below", in: harness, page)
        let london = try find("London", in: harness, page)
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: ada.x, y: ada.y))
        harness.frame(page)
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: three.x + 4, y: three.y))
        harness.frame(page)
        let widened = try #require(selected(harness))
        #expect(widened.contains("row one below") && widened.contains("row two below"), "not widened: \(widened)")
        // Back inside the card: still the page's selection, so the first
        // row runs on through the card's right border.
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: london.x + 2, y: london.y))
        harness.frame(page)
        harness.mouse(MouseEvent(button: .left, phase: .released, x: london.x + 2, y: london.y))
        harness.frame(page)
        let text = try #require(selected(harness))
        #expect(text.contains("│"), "the selection went back to the card: \(text)")
        #expect(!text.contains("below"), "the head did not come back: \(text)")
    }

    @Test("Sideways: five columns past the border keep to the card, six widen")
    func sidewaysThreshold() throws {
        let page = Page()
        let harness = harness(page)
        let ada = try find("Ada", in: harness, page)
        // The card's right border: its padding stands between it and the name.
        let row = harness.frame(page).lines[ada.y].stripped
        let border = try #require(row.lastIndex(of: "│").map { row.distance(from: row.startIndex, to: $0) })
        drag(harness, page, from: ada, through: [(border + 5, ada.y)])
        #expect(selected(harness) == "Ada Lovelace")
        let fresh = self.harness(page)
        drag(fresh, page, from: ada, through: [(border + 6, ada.y)])
        let text = try #require(selected(fresh))
        #expect(text.contains("Ada Lovelace │"), "not widened: \(text)")
    }

    @Test("A card inside a card widens to the outer card's interior first, then to the page")
    func nestedWidensOneScopeAtATime() throws {
        let page = NestedPage()
        let harness = harness(page)
        let ada = try find("Ada", in: harness, page)
        let three = try find("outer line three", in: harness, page)
        let pageTwo = try find("page row two", in: harness, page)
        let pageFour = try find("page row four", in: harness, page)
        // Four rows below the inner card's interior, inside the outer card.
        drag(harness, page, from: ada, through: [(three.x + 4, three.y)])
        var text = try #require(selected(harness))
        #expect(text.contains("outer line two"), "not widened to the outer card: \(text)")
        #expect(!text.contains("page row"), "widened past the outer card: \(text)")
        // In one step two rows below the outer card's border: past the inner
        // card by far, but only two past the outer, which keeps it.
        drag(harness, page, from: ada, through: [(pageTwo.x + 4, pageTwo.y)])
        text = try #require(selected(harness))
        #expect(text.contains("outer line three") && !text.contains("page row"), "\(text)")
        // On to three rows past the outer card's border: the page.
        drag(harness, page, from: ada, through: [(three.x + 4, three.y), (pageFour.x + 4, pageFour.y)])
        text = try #require(selected(harness))
        #expect(text.contains("page row one"), "not widened to the page: \(text)")
    }

    @Test("Inside an enabled textSelection the widening stops at that scope")
    func stopsAtAnEnabledScope() throws {
        let page = ScopedPage()
        let harness = harness(page)
        let ada = try find("Ada", in: harness, page)
        let four = try find("outside four", in: harness, page)
        drag(harness, page, from: ada, through: [(four.x + 4, four.y)])
        let text = try #require(selected(harness))
        #expect(text.contains("scope row four"), "not widened to the scope: \(text)")
        #expect(!text.contains("outside"), "widened past the app's scope: \(text)")
    }
}
