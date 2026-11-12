//  🖥️ TUI — A Terminal UI framework for Swift
//  PulledFocusTests.swift
//
//  SCROLL-FIT's focus through pulled content (design 1e): Tab and Shift-Tab
//  run through a lazy stack under a title, in a box, beside a gutter, in the
//  rows of an outer lazy stack, in the order the same controls run in drawn
//  eagerly — the controls above a pulled column's anchor included, which it
//  draws after the ones below — and each control Tab lands on is on screen.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUI
import TUITesting

@MainActor
@Suite("SCROLL-FIT pull: Tab runs through pulled content in the eager order, and shows where it lands")
struct PulledFocusTests {
    enum Shape: String, CaseIterable, Sendable {
        case titled, boxed, hStack, sections
    }

    private static func button(_ id: String) -> some View {
        Button(id) {}
    }

    /// What a focus id names, the same in the lazy page and its eager twin:
    /// the key of the innermost `ForEach` row it lies in, or the id itself
    /// for a control in no row, whose path the twins share.
    private static func label(_ id: String?) -> String {
        guard let id else { return "-" }
        let keys = id.matches(of: /\[([^\]]+)\]/).map { String($0.1) }
        guard let key = keys.last(where: { $0.wholeMatch(of: /(a|s\d+r)?\d+/) != nil }) else {
            return id.split(separator: "/").suffix(3).joined(separator: "/")
        }
        return key
    }

    private static func rows(_ prefix: String, _ count: Int, lazy: Bool) -> AnyView {
        let ids = (0..<count).map { "\(prefix)\($0)" }
        if lazy {
            return AnyView(LazyVStack(alignment: .leading, spacing: 0) { ForEach(ids, id: \.self) { button($0) } })
        }
        return AnyView(
            VStack(alignment: .leading, spacing: 0) { ForEach(ids, id: \.self) { button($0) } }
                .frame(maxWidth: .infinity, alignment: .leading))
    }

    @ViewBuilder
    private static func content(_ shape: Shape, lazy: Bool) -> some View {
        switch shape {
        case .titled:
            VStack(alignment: .leading, spacing: 0) {
                button("top")
                rows("a", 300, lazy: lazy)
                button("bottom")
            }
        case .boxed:
            VStack(alignment: .leading, spacing: 0) {
                button("top")
                GroupBox { rows("a", 300, lazy: lazy) }
                button("bottom")
            }
        case .hStack:
            VStack(alignment: .leading, spacing: 0) {
                button("top")
                HStack(alignment: .top, spacing: 1) {
                    Text("|")
                    rows("a", 300, lazy: lazy)
                }
                button("bottom")
            }
        case .sections:
            let sections = (0..<3).map { section in
                VStack(alignment: .leading, spacing: 0) {
                    button("s\(section)")
                    rows("s\(section)r", 300, lazy: lazy)
                }
            }
            if lazy {
                LazyVStack(alignment: .leading, spacing: 0) { ForEach(0..<3, id: \.self) { sections[$0] } }
            } else {
                VStack(alignment: .leading, spacing: 0) { ForEach(0..<3, id: \.self) { sections[$0] } }
            }
        }
    }

    private static func app(_ shape: Shape, lazy: Bool) -> TestApp {
        TestApp(width: 30, height: 10) { ScrollView { content(shape, lazy: lazy) } }
    }

    /// The control focused after each of `steps` presses of `key`.
    private static func stops(_ app: TestApp, _ key: Key, modifiers: EventModifiers = [], steps: Int) -> [String] {
        _ = app.screen
        var stops: [String] = []
        for _ in 0..<steps {
            _ = app.press(key, modifiers: modifiers)
            stops.append(label(app.focusedID))
        }
        return stops
    }

    @Test("Tab runs through the controls in the eager order", arguments: Shape.allCases)
    func tabOrderMatchesTheEagerOne(_ shape: Shape) {
        let lazy = Self.stops(Self.app(shape, lazy: true), .tab, steps: 40)
        let eager = Self.stops(Self.app(shape, lazy: false), .tab, steps: 40)
        #expect(lazy == eager, "\(shape)")
    }

    /// Focus on the stack's first row, scrolled a line or two past it, so the
    /// column's anchor is the stack and the control above it (the column's
    /// first child, or the section's heading) is drawn after the stack's rows:
    /// Shift-Tab, and Shift-Tab again, step back up through the controls
    /// above as they do in the eager twin, rather than to the scroll view
    /// past them.
    @Test("Scrolled past the controls above the stack, Shift-Tab steps back to them", arguments: Shape.allCases)
    func shiftTabBackAboveTheAnchor(_ shape: Shape) {
        func walk(lazy: Bool) -> [String] {
            let app = Self.app(shape, lazy: lazy)
            // To the stack's first row; a line past the control above it, back
            // to it and down two; two lines past, back two and down two.
            var stops = Self.stops(app, .tab, steps: 1)
            for (lines, back) in [(1, 1), (2, 2)] {
                app.scroll(.down, by: lines, at: CellPoint(x: 5, y: 5))
                stops += Self.stops(app, .tab, modifiers: .shift, steps: back)
                stops += Self.stops(app, .tab, steps: 2)
            }
            return stops
        }
        #expect(walk(lazy: true) == walk(lazy: false), "\(shape)")
    }

    @Test("Each control Tab lands on is on screen", arguments: Shape.allCases)
    func tabRevealsWhereItLands(_ shape: Shape) {
        let app = Self.app(shape, lazy: true)
        _ = app.screen
        for step in 0..<40 {
            _ = app.press(.tab)
            let id = Self.label(app.focusedID)
            // A row's label is its text; a control in no row is labelled by its path.
            guard id.wholeMatch(of: /(a|s\d+r)\d+/) != nil else { continue }
            let shown = app.screen.lines.contains { $0.range(of: "\\b\(id)\\b", options: .regularExpression) != nil }
            #expect(shown, "\(shape) step \(step): \(id) not on screen:\n\(app.screen)")
        }
    }
}
