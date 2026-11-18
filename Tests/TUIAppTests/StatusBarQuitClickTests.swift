//  🖥️ TUI — A Terminal UI framework for Swift
//  StatusBarQuitClickTests.swift
//
//  A click on the status bar's quit item quits, as its key does: the item
//  spells ⌃Q, which no trigger key carries, so the click sends the quit
//  shortcut's own event.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("A click on the status bar's quit item")
struct StatusBarQuitClickTests {
    /// The chain the harness builds, for the environment it builds it after.
    private final class Chain {
        var handler: InputHandler?
    }

    /// A harness whose status bar's clicks reach its chain, as an app's do.
    private func harness() -> InputChainHarness {
        let chain = Chain()
        let harness = InputChainHarness(width: 40, height: 3) { environment in
            environment.synthesizeKeyEvent = { _ = chain.handler?.handle($0) }
        }
        chain.handler = harness.handler
        return harness
    }

    /// Clicks the first cell of `text` on the bar's row.
    private func click(_ text: String, in harness: InputChainHarness, bar: StatusBar) {
        let row = harness.frame(bar).lines[0].stripped
        guard let range = row.range(of: text) else {
            Issue.record("\(text) is not drawn: \(row.debugDescription)")
            return
        }
        let column = row.distance(from: row.startIndex, to: range.lowerBound)
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: column, y: 0))
        harness.mouse(MouseEvent(button: .left, phase: .released, x: column, y: 0))
        harness.frame(bar)
    }

    @Test("⌃Q quit, the default, quits when clicked")
    func defaultQuitItem() {
        let harness = harness()
        let bar = StatusBar(userItems: [], systemItems: harness.statusBar.currentSystemItems, style: .compact)
        click("quit", in: harness, bar: bar)
        #expect(harness.quits == 1)
    }

    @Test("A quit shortcut of a plain key quits when clicked too")
    func plainKeyQuitItem() {
        let harness = harness()
        harness.statusBar.quitShortcut = .q
        let bar = StatusBar(userItems: [], systemItems: harness.statusBar.currentSystemItems, style: .compact)
        click("quit", in: harness, bar: bar)
        #expect(harness.quits == 1)
    }
}
