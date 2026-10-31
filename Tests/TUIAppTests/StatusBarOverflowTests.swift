//  🖥️ TUI — A Terminal UI framework for Swift
//  StatusBarOverflowTests.swift
//
//  A status bar too narrow for its items: they never touch, none is cut, whole
//  items go from the end, the quit item last, and a click on one that stayed
//  still lands on it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("A status bar too narrow for its items")
struct StatusBarOverflowTests {
    /// Four page items and the quit item, as a bar's own key writing draws
    /// them: 7, 7, 9, 7 and 6 cells, 36 in all.
    private static let drawn = ["A alpha", "B bravo", "C charlie", "D delta"]
    private static let drawnQuit = "Q quit"
    private static let userItems: [any StatusBarItemProtocol] = [
        StatusBarItem(shortcut: "a", label: "alpha"), StatusBarItem(shortcut: "b", label: "bravo"),
        StatusBarItem(shortcut: "c", label: "charlie"), StatusBarItem(shortcut: "d", label: "delta"),
    ]
    private static let quit = StatusBarItem(shortcut: "q", label: "quit", order: .quit)

    /// The row of a bar `width` cells wide that holds the items, without the
    /// walls of a bordered one.
    private func itemRow(_ bar: StatusBar, width: Int, style: ChromeStyle) -> String {
        let context = RenderContext(availableWidth: width, availableHeight: 5, tuiContext: TUIContext())
            .isolatingRenderCache()
        let lines = renderToBuffer(bar, context: context).lines.map(\.stripped)
        switch style {
        case .compact: return lines[0]
        case .rule: return lines[1]
        case .bordered: return String(lines[1].dropFirst(2).dropLast(2))
        }
    }

    /// The items drawn in `row`: every run of words that is one of `known`,
    /// or a failure for whatever is left.
    private func itemsDrawn(in row: String, known: [String]) -> [String] {
        let words = row.split(separator: " ").map(String.init)
        var found: [String] = []
        var index = 0
        while index + 1 < words.count {
            let item = words[index] + " " + words[index + 1]
            guard known.contains(item) else {
                Issue.record("\"\(words[index]) \(words[index + 1])\" is no whole item: \(row.debugDescription)")
                return found
            }
            found.append(item)
            index += 2
        }
        if index < words.count { Issue.record("\"\(words[index])\" is no whole item: \(row.debugDescription)") }
        return found
    }

    @Test(
        "Items never touch and none is cut, at any width",
        arguments: [StatusBarAlignment.leading, .trailing, .center, .justified],
        [ChromeStyle.compact, .rule, .bordered])
    func itemsStayWhole(alignment: StatusBarAlignment, style: ChromeStyle) {
        let bar = StatusBar(userItems: Self.userItems, systemItems: [Self.quit], style: style, alignment: alignment)
        let known = Self.drawn + [Self.drawnQuit]
        let chrome = style == .bordered ? 4 : 0
        for width in (chrome + 1)...60 {
            let row = itemRow(bar, width: width, style: style)
            #expect(row.strippedLength == width - chrome, "width \(width): \(row.debugDescription)")
            let items = itemsDrawn(in: row, known: known)
            // In their order, whichever are left, so each one's column is its own.
            #expect(items == known.filter(items.contains), "width \(width): \(row.debugDescription)")
        }
    }

    @Test("Justified, the gaps close to one column before anything is dropped")
    func justifiedKeepsOneColumnBetween() {
        let bar = StatusBar(userItems: Self.userItems, systemItems: [Self.quit], style: .compact, alignment: .justified)
        // 36 cells of items and four gaps.
        #expect(itemRow(bar, width: 40, style: .compact) == "A alpha B bravo C charlie D delta Q quit")
        // One short: the last item but quit goes, not a gap.
        let row = itemRow(bar, width: 39, style: .compact)
        #expect(itemsDrawn(in: row, known: Self.drawn + [Self.drawnQuit]) == ["A alpha", "B bravo", "C charlie", "Q quit"])
    }

    @Test("Leading and trailing close their two-column gaps to one before dropping anything")
    func otherAlignmentsCloseTheirGaps() {
        let leading = StatusBar(userItems: Self.userItems, systemItems: [Self.quit], style: .compact, alignment: .leading)
        // A leading space, 36 cells and four gaps of one.
        #expect(itemRow(leading, width: 41, style: .compact) == " A alpha B bravo C charlie D delta Q quit")
        #expect(itemRow(leading, width: 45, style: .compact) == " A alpha  B bravo  C charlie  D delta  Q quit")
        let trailing = StatusBar(userItems: Self.userItems, systemItems: [Self.quit], style: .compact, alignment: .trailing)
        #expect(itemRow(trailing, width: 41, style: .compact) == "A alpha B bravo C charlie D delta Q quit ")
    }

    @Test("Items go from the end, the quit item last, whatever stands after it")
    func quitIsTheLastToGo() {
        let after = StatusBarItem(shortcut: "t", label: "theme", order: .theme)
        let bar = StatusBar(userItems: Self.userItems, systemItems: [Self.quit, after], style: .compact, alignment: .justified)
        let known = Self.drawn + [Self.drawnQuit, "T theme"]
        #expect(itemsDrawn(in: itemRow(bar, width: 48, style: .compact), known: known).last == "T theme")
        #expect(itemsDrawn(in: itemRow(bar, width: 47, style: .compact), known: known).last == Self.drawnQuit, "the theme item first")
        #expect(itemsDrawn(in: itemRow(bar, width: 6, style: .compact), known: known) == [Self.drawnQuit])
        #expect(itemRow(bar, width: 5, style: .compact) == "     ", "too narrow for it as well: blank, not cut")
    }

    @Test("With no quit item, simply from the end")
    func noQuitItem() {
        let bar = StatusBar(items: Self.userItems, style: .compact, alignment: .justified)
        #expect(itemsDrawn(in: itemRow(bar, width: 25, style: .compact), known: Self.drawn) == ["A alpha", "B bravo", "C charlie"])
        #expect(itemsDrawn(in: itemRow(bar, width: 24, style: .compact), known: Self.drawn) == ["A alpha", "B bravo"])
    }

    @Test(
        "A click lands on the item drawn there, with the gaps closed and items dropped",
        arguments: [StatusBarAlignment.leading, .trailing, .center, .justified])
    func clicksStillLand(alignment: StatusBarAlignment) {
        final class Fired { var names: [String] = [] }
        let fired = Fired()
        let items = ["alpha", "bravo", "charlie", "delta"].map { name in
            StatusBarItem(shortcut: String(name.prefix(1)), label: name) { fired.names.append(name) }
        }
        let width = 30
        let harness = InputChainHarness(width: width, height: 3)
        let bar = StatusBar(items: items, style: .compact, alignment: alignment)
        let row = harness.frame(bar).lines[0].stripped
        #expect(!row.contains("delta"), "precondition, a bar too narrow for delta: \(row.debugDescription)")
        for name in ["alpha", "bravo", "charlie"] {
            guard let range = row.range(of: name) else {
                Issue.record("\(name) is not drawn: \(row.debugDescription)")
                continue
            }
            let column = row.distance(from: row.startIndex, to: range.lowerBound)
            harness.mouse(MouseEvent(button: .left, phase: .pressed, x: column, y: 0))
            harness.mouse(MouseEvent(button: .left, phase: .released, x: column, y: 0))
            harness.frame(bar)
        }
        #expect(fired.names == ["alpha", "bravo", "charlie"], "\(row.debugDescription)")
    }
}
