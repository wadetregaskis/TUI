//  🖥️ TUI — A Terminal UI framework for Swift
//  WindowedStackShiftTabTests.swift
//
//  Shift+Tab up through a lazy stack a scroll view windows reaches the rows
//  above the window one by one, scrolling each in, as Tab does downwards. A
//  windowed stack draws only the rows on screen and one past each edge, and
//  the row next to the focused one wherever it is; the one above the window
//  was drawn after the window's rows, so it came after them in the Tab ring,
//  and Shift+Tab from the top row went past it, out of the scroll view.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIApp
@testable import TUIAppTestSupport
import TUITesting

@MainActor
@Suite("Shift+Tab walks up a windowed lazy stack")
struct WindowedStackShiftTabTests {
    /// Uniform rows take the stack's uniform path; rows of two heights its
    /// anchored one.
    enum Rows: String, CaseIterable, CustomTestStringConvertible {
        case uniform, varied
        var testDescription: String { rawValue }
    }

    private struct Page: View {
        let rows: Rows
        var body: some View {
            VStack(spacing: 0) {
                Button("top") {}
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<30, id: \.self) { index in
                            if rows == .varied, index.isMultiple(of: 3) {
                                VStack(alignment: .leading, spacing: 0) {
                                    Button("row \(index)") {}
                                    Text("  more")
                                }
                            } else {
                                Button("row \(index)") {}
                            }
                        }
                    }
                }
                .frame(height: 6)
                Button("bottom") {}
            }
        }
    }

    /// The row a focus id names — the `ForEach` element in its path, `[N]` —
    /// or the control outside the stack it is.
    private static func name(_ id: String?) -> String {
        guard let id else { return "nothing" }
        if id.hasPrefix("scrollview") { return "the scroll view" }
        if let match = id.matches(of: /\[(\d+)\]/).last { return "row \(match.1)" }
        if id.contains("Button.0") { return "top" }
        if id.contains("Button.2") { return "bottom" }
        return id
    }

    @Test("Shift+Tab from below the window reaches every row above it, then the control above", arguments: Rows.allCases)
    func shiftTabReachesEveryRow(_ rows: Rows) {
        let app = TestApp(width: 30, height: 14) { Page(rows: rows) }
        app.frame(atNanos: 16_666_667)
        // Down to row 14, which scrolls the first rows out of the window.
        for _ in 0...14 { _ = app.press(.tab) }
        #expect(Self.name(app.focusedID) == "row 14", "precondition: \(Self.name(app.focusedID))")
        #expect(!app.screen.contains("row 0 "), "precondition: row 0 is scrolled away:\n\(app.screen)")
        var walked: [String] = []
        var hidden: [String] = []
        for _ in 0..<15 {
            _ = app.press(.tab, modifiers: .shift)
            let name = Self.name(app.focusedID)
            walked.append(name)
            if name.hasPrefix("row"), !app.screen.lines.contains(where: { $0.contains("\(name) ") }) {
                hidden.append(name)
            }
        }
        let expected = (0...13).reversed().map { "row \($0)" } + ["top"]
        #expect(walked == expected, "Shift+Tab walked \(walked)")
        #expect(hidden.isEmpty, "focused off screen: \(hidden)")
    }
}
