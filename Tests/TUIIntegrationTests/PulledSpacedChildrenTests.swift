//  🖥️ TUI — A Terminal UI framework for Swift
//  PulledSpacedChildrenTests.swift
//
//  Two `VStack { header; LazyVStack(spacing:) { ForEach } }` in a scroll
//  view, each a pulled child of the content's column, draw what the same
//  content drawn whole draws wherever the keys and the wheel take them: at the
//  top, paged down, at the end, paged up from the end, and back home.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUI
import TUITesting

@MainActor
@Suite("Pulled children whose rows are spaced scroll as the same content drawn whole does")
struct PulledSpacedChildrenTests {
    /// The outer stack the two children are in.
    enum Outer: CaseIterable { case lazyStack, column }

    /// A row of block `block`.
    private static func row(_ block: Int, _ index: Int) -> Text {
        Text(verbatim: index.isMultiple(of: 3) ? "b\(block) row \(index)" : "b\(block) r\(index)")
    }

    /// Block `block`: a header over `rows` rows at `spacing`, lazy or not.
    @ViewBuilder private static func block(_ block: Int, rows: Int, spacing: Int, lazy: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "Header \(block)")
            if lazy {
                LazyVStack(alignment: .leading, spacing: spacing) {
                    ForEach(0..<rows, id: \.self) { Self.row(block, $0) }
                }
            } else {
                VStack(alignment: .leading, spacing: spacing) {
                    ForEach(0..<rows, id: \.self) { Self.row(block, $0) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Two blocks in `outer`, lazy, or drawn whole in an eager `VStack` as
    /// wide as the scroll view (a lazy stack fills its width).
    private static func app(_ outer: Outer, rows: Int, spacing: Int, lazy: Bool) -> TestApp {
        TestApp(width: 30, height: 12) {
            ScrollView {
                if !lazy {
                    VStack(alignment: .leading, spacing: 0) {
                        Self.block(0, rows: rows, spacing: spacing, lazy: false)
                        Self.block(1, rows: rows, spacing: spacing, lazy: false)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if outer == .lazyStack {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        Self.block(0, rows: rows, spacing: spacing, lazy: true)
                        Self.block(1, rows: rows, spacing: spacing, lazy: true)
                    }
                } else {
                    Self.block(0, rows: rows, spacing: spacing, lazy: true)
                    Self.block(1, rows: rows, spacing: spacing, lazy: true)
                }
            }
        }
    }

    /// The screen without the scroll bar's column.
    private static func content(_ app: TestApp) -> [String] { app.screen.lines.map { String($0.prefix(29)) } }

    @Test(
        "Paged, sent to either end and paged up from the end, it draws what the content drawn whole draws",
        arguments: Outer.allCases, [0, 1, 2, 6])
    func keys(_ outer: Outer, _ spacing: Int) {
        let lazy = Self.app(outer, rows: 280, spacing: spacing, lazy: true)
        let whole = Self.app(outer, rows: 280, spacing: spacing, lazy: false)
        func check(_ step: String) {
            #expect(Self.content(lazy) == Self.content(whole), "\(step):\n\(lazy.screen)\n---\n\(whole.screen)")
        }
        func press(_ key: Key, _ step: String) {
            for app in [lazy, whole] { _ = app.press(key) }
            check(step)
        }
        check("top")
        for page in 1...4 { press(.pageDown, "page \(page)") }
        press(.end, "end")
        for page in 1...4 { press(.pageUp, "end, page up \(page)") }
        press(.home, "home")
        press(.end, "end again")
        press(.home, "home again")
        for page in 1...2 { press(.pageDown, "home, page \(page)") }
    }

    @Test("Wheeled down past the first block and back, it draws what the content drawn whole draws",
          arguments: Outer.allCases, [0, 1])
    func wheel(_ outer: Outer, _ spacing: Int) {
        let lazy = Self.app(outer, rows: 280, spacing: spacing, lazy: true)
        let whole = Self.app(outer, rows: 280, spacing: spacing, lazy: false)
        func check(_ step: String) {
            #expect(Self.content(lazy) == Self.content(whole), "\(step):\n\(lazy.screen)\n---\n\(whole.screen)")
        }
        for step in 1...8 {
            for app in [lazy, whole] { app.scroll(.down, by: 40, at: CellPoint(x: 5, y: 5)) }
            check("down \(step)")
        }
        for app in [lazy, whole] { _ = app.press(.end) }
        check("end")
        for step in 1...8 {
            for app in [lazy, whole] { app.scroll(.up, by: 40, at: CellPoint(x: 5, y: 5)) }
            check("up \(step)")
        }
    }
}
