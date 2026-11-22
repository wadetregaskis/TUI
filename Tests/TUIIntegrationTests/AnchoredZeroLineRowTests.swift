//  🖥️ TUI — A Terminal UI framework for Swift
//  AnchoredZeroLineRowTests.swift
//
//  A row of no lines in a lazy stack past 256 rows (the anchored walk) takes
//  no line and earns no gap, as on every other path: the walk's pitch was
//  floored at a line for its own progress, and the row was drawn at it, a
//  blank line and a gap where a stack of 200 of the same rows drew nothing.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUI
import TUITesting

@MainActor
@Suite("A row of no lines on the anchored walk")
struct AnchoredZeroLineRowTests {
    /// 300 rows, every third of no lines, at spacing 1: in a lazy stack (the
    /// anchored walk) or an eager one (what it must draw).
    private static func app(lazy: Bool) -> TestApp {
        lazy
            ? TestApp(width: 30, height: 12) { ScrollView { LazyVStack(alignment: .leading, spacing: 1) { rows } } }
            : TestApp(width: 30, height: 12) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) { rows }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
    }

    private static var rows: some View {
        ForEach(0..<300, id: \.self) { index in
            Text(verbatim: "row \(index)").frame(height: index.isMultiple(of: 3) ? 0 : 1)
        }
    }

    @Test("Rows of no lines take no line and no gap past 256 rows, as an eager stack draws them")
    func zeroLineRowsDrawNothing() {
        let lazy = Self.app(lazy: true)
        let eager = Self.app(lazy: false)
        func content(_ app: TestApp) -> [String] {
            app.screen.lines.map { String(($0 + String(repeating: " ", count: 30)).prefix(29)) }
        }
        #expect(content(lazy) == content(eager), "top:\n\(lazy.screen)\n---\n\(eager.screen)")
        for page in 1...3 {
            _ = lazy.press(.pageDown)
            _ = eager.press(.pageDown)
            #expect(content(lazy) == content(eager), "page \(page):\n\(lazy.screen)\n---\n\(eager.screen)")
        }
    }
}
