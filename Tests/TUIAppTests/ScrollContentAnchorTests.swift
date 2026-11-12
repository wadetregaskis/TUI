//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollContentAnchorTests.swift
//
//  SCROLL-FIT P1 (B-SCROLLFIT-11): the scroll position is held by the scroll
//  view as an anchor — a row of its content and the lines of it above the
//  viewport — which the windowed stack at the content's origin walks and
//  moves. The anchor is the scroll view's, not the stack's: it names the row
//  at the top after a scroll, it starts afresh for another column, and a
//  window that brings none leaves the stack its own.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUIView

/// Rows of one and two lines, alternately: past 256 of them a lazy stack takes
/// the anchored walk.
@MainActor
private func mixedRow(_ index: Int, tag: String) -> Text {
    Text(index % 2 == 1 ? "\(tag) \(index)\n  of \(index)" : "\(tag) \(index)")
}

@MainActor
@Suite("The scroll view holds its position as an anchor")
struct ScrollContentAnchorTests {
    private final class Harness {
        let tui = TUIContext()
        let focus = FocusManager()

        @MainActor
        func frame(_ view: some View) -> [String] {
            var environment = EnvironmentValues()
            environment.focusManager = focus
            environment.applyRuntimeServices(from: tui)
            let context = RenderContext(
                availableWidth: 30, availableHeight: 10, environment: environment, tuiContext: tui)
            tui.preferences.beginRenderPass()
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            focus.beginRenderPass()
            let buffer = renderToBuffer(view, context: context)
            focus.endRenderPass()
            tui.stateStorage.endRenderPass()
            tui.renderCache.removeInactive()
            return buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
        }

        var handler: ScrollViewHandler? {
            focus.activeSection?.focusables.compactMap { $0 as? ScrollViewHandler }.first
        }
    }

    private struct Page: View {
        let tag: String

        var body: some View {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<300, id: \.self) { mixedRow($0, tag: tag) }
                }
            }
            .scrollIndicators(.never)
        }
    }

    @Test("the anchor names the row at the viewport's top, and the lines of it above")
    func anchorNamesTheTopRow() throws {
        let harness = Harness()
        let page = Page(tag: "row")
        _ = harness.frame(page)
        let handler = try #require(harness.handler)
        // Rows 0 and 1 take three lines; a scroll of four puts row 2's line
        // above the top and row 3's first line on it.
        handler.scrollOffset = 4
        let lines = harness.frame(page)
        #expect(lines.first == "row 3", "precondition: \(lines)")
        #expect(handler.contentAnchor.ordinal == 3)
        #expect(handler.contentAnchor.key == "3")
        #expect(handler.contentAnchor.within == 0)
        #expect(handler.contentAnchor.derivedOffset == 4)
        // One line more hides row 3's first line.
        handler.scrollOffset = 5
        _ = harness.frame(page)
        #expect(handler.contentAnchor.ordinal == 3)
        #expect(handler.contentAnchor.within == 1)
    }

    @Test("another column finds the anchor afresh, not the last one's row")
    func anotherColumnStartsAfresh() throws {
        let harness = Harness()
        _ = harness.frame(Page(tag: "row"))
        let handler = try #require(harness.handler)
        handler.scrollOffset = 40
        _ = harness.frame(Page(tag: "row"))
        #expect(handler.contentAnchor.ordinal > 0, "precondition")
        let anchor = handler.contentAnchor
        let identity = try #require(anchor.column)
        // A different state at the same column is the column drawn anew: its
        // window state was pruned, so the anchor starts over, as the state's
        // own anchor did.
        let fresh = anchor.claimed(byColumn: identity, state: StackWindowState())
        #expect(fresh.ordinal == 0 && fresh.key == nil && fresh.within == 0)
        #expect(fresh.derivedOffset == 0 && fresh.reportedTotal == nil)
    }

    @Test("a window that brings no anchor leaves the stack its own")
    func injectedWindowUsesTheStacksOwn() {
        let harness = Harness()
        let stack = LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<300, id: \.self) { mixedRow($0, tag: "row") }
        }
        let view = stack.environment(
            \.scrollContentWindow, ScrollContentWindow(offset: 4, viewportHeight: 10, contentIdentity: nil))
        let lines = harness.frame(view)
        #expect(lines.contains("row 3"), "drawn from the stack's own anchor: \(lines)")
    }
}
