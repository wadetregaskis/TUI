//  🖥️ TUIkit — Terminal UI Kit for Swift
//  BorderedSelectionScopeTests.swift
//
//  A drag that started inside a bordered card ran on through its border into
//  the page around it, selecting the border's glyphs and the page's text with
//  the card's lines (owner, 2026-10-23, #10: the Example's Contact card). A
//  bordered container keeps a selection begun inside it to its interior now.
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
@Suite("A bordered container keeps a selection to its interior")
struct BorderedSelectionScopeTests {

    /// A card of two lines between a line of page text above and below.
    struct Page: View {
        var scope: TextSelectionScope?
        var selectability: Bool?

        var body: some View {
            let card = VStack(alignment: .leading) {
                Text("Ada Lovelace")
                Text("London")
            }
            .border()
            let page = VStack(alignment: .leading) {
                Text("above the card")
                if let scope { card.textSelectionScope(scope) } else { card }
                Text("below the card")
            }
            switch selectability {
            case true?: page.textSelection(.enabled)
            case false?: page.textSelection(.disabled)
            case nil: page
            }
        }
    }

    // MARK: - Harness

    func harness(_ page: some View) -> InputChainHarness {
        let harness = InputChainHarness(width: 40, height: 10)
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

    func drag(_ harness: InputChainHarness, _ page: some View, from: (x: Int, y: Int), to: (x: Int, y: Int)) {
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: from.x, y: from.y))
        harness.frame(page)
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: to.x, y: to.y))
        harness.frame(page)
        harness.mouse(MouseEvent(button: .left, phase: .released, x: to.x, y: to.y))
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

    @Test("A drag from inside the card to the page below selects the card's lines and nothing else")
    func dragStaysInside() throws {
        let page = Page()
        let harness = harness(page)
        let ada = try find("Ada", in: harness, page)
        let below = try find("below", in: harness, page)
        drag(harness, page, from: ada, to: (below.x + 4, below.y))
        let text = try #require(selected(harness))
        #expect(text.contains("Ada Lovelace") && text.contains("London"), "the card's lines: \(text)")
        #expect(!text.contains("below"), "the selection left the card: \(text)")
        #expect(!text.contains("─") && !text.contains("│"), "the selection took the border: \(text)")
    }

    @Test(".textSelectionScope(.pane) lets the same drag run on past the border")
    func paneScopeCrosses() throws {
        let page = Page(scope: .pane)
        let harness = harness(page)
        let ada = try find("Ada", in: harness, page)
        let below = try find("below", in: harness, page)
        drag(harness, page, from: ada, to: (below.x + 4, below.y))
        let text = try #require(selected(harness))
        #expect(text.contains("below"), "the selection kept to the card: \(text)")
    }

    @Test("A drag that starts outside the card selects across it")
    func outsideDragCrosses() throws {
        let page = Page()
        let harness = harness(page)
        let above = try find("above", in: harness, page)
        let below = try find("below", in: harness, page)
        drag(harness, page, from: above, to: (below.x + 4, below.y))
        let text = try #require(selected(harness))
        #expect(text.contains("Ada Lovelace") && text.contains("below"), "the card stopped a drag from outside: \(text)")
    }

    @Test("Inside a .textSelection(.enabled) page the card still keeps the selection to itself")
    func innermostIsTheCard() throws {
        let page = Page(selectability: true)
        let harness = harness(page)
        let ada = try find("Ada", in: harness, page)
        let below = try find("below", in: harness, page)
        drag(harness, page, from: ada, to: (below.x + 4, below.y))
        let text = try #require(selected(harness))
        #expect(!text.contains("below"), "the selection left the card: \(text)")
    }

    @Test("Inside a .textSelection(.disabled) page the card selects nothing: an interior does not turn selection on")
    func disabledStaysDisabled() throws {
        let page = Page(selectability: false)
        let harness = harness(page)
        let ada = try find("Ada", in: harness, page)
        drag(harness, page, from: ada, to: (ada.x + 4, ada.y + 1))
        #expect(!harness.tui.screenSelection.hasSelection)
    }

    @Test("A card files its interior, and none under .textSelectionScope(.pane)")
    func filesOneInterior() {
        let harness = harness(Page())
        #expect(harness.tui.mouseEventDispatcher.selectionScopes.values.filter { $0 == .interior }.count == 1)
        let pane = self.harness(Page(scope: .pane))
        #expect(pane.tui.mouseEventDispatcher.selectionScopes.isEmpty)
        #expect(!harness.tui.mouseEventDispatcher.hasEnabledSelectionScope, "an interior counted as an enabled scope")
    }
}
