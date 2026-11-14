//  🖥️ TUI — A Terminal UI framework for Swift
//  PulledTextEditorTests.swift
//
//  SCROLL-FIT's pull (design P4) for `TextEditor`: with the switch on
//  (`EnvironmentValues.scrollFitsContent`), an editor under a title in a
//  scroll view is its text's height — its rows, wrapped or not — and draws
//  only the rows on screen; the scroll view keeps the caret in sight as it
//  moves and as text is typed. Its drawing is the same editor drawn whole,
//  framed to its full height.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUI
import TUITesting

/// A title, a button, an editor and a button below it in a scroll view.
private struct EditorPage: View {
    @State private var text: String
    /// The twin's frame: the same editor drawn whole, framed to its full
    /// height, the switch off. `nil` for the pulled editor.
    let framed: Int?

    init(text: String, framed: Int?) {
        _text = State(initialValue: text)
        self.framed = framed
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("title")
                Button("above") {}
                if let framed {
                    TextEditor(text: $text).frame(height: framed)
                } else {
                    TextEditor(text: $text)
                }
                Button("below") {}
            }
        }
        .environment(\.scrollFitsContent, framed == nil)
    }
}

@MainActor
@Suite("SCROLL-FIT pull: a TextEditor under a title draws only the rows on screen, and keeps its caret in sight")
struct PulledTextEditorTests {
    /// `count` lines `l0`, `l1`, …, each padded with `x` to `length`
    /// characters where that is longer.
    private static func text(_ count: Int, length: Int = 0) -> String {
        (0..<count).map { index in
            let line = "l\(index)"
            return line + String(repeating: "x", count: max(0, length - line.count))
        }.joined(separator: "\n")
    }

    private static func app(_ text: String, framed: Int? = nil) -> TestApp {
        TestApp(width: 30, height: 12) { EditorPage(text: text, framed: framed) }
    }

    /// The screen's lines without the scroll view's bar, which reads an
    /// estimate on one side and a measure on the other.
    private static func content(_ app: TestApp) -> [String] {
        app.screen.lines.map { String(($0 + String(repeating: " ", count: 30)).prefix(28)) }
    }

    /// Whether line `l<index>` is on screen.
    private static func shows(_ app: TestApp, line index: Int) -> Bool {
        // `l<index>` not followed by a digit: `l1` is not shown by `l10`.
        app.screen.lines.contains { line in
            guard let found = line.range(of: "l\(index)") else { return false }
            return line[found.upperBound...].first.map { !$0.isNumber } ?? true
        }
    }

    @Test("The editor draws what the editor drawn whole draws, wrapped or not", arguments: [0, 40])
    func drawsWhatTheWholeEditorDraws(_ length: Int) {
        let text = Self.text(300, length: length)
        // A line of 40 characters wraps to two rows at the editor's 30 cells.
        let rows = length > 30 ? 600 : 300
        let pulled = Self.app(text)
        let whole = Self.app(text, framed: rows)
        func check(_ step: String) {
            #expect(Self.content(pulled) == Self.content(whole), "\(step):\n\(pulled.screen)\n---\n\(whole.screen)")
        }
        check("top")
        for step in 1...4 {
            pulled.scroll(.down, by: 2, at: CellPoint(x: 5, y: 5))
            whole.scroll(.down, by: 2, at: CellPoint(x: 5, y: 5))
            check("wheel \(step)")
        }
        pulled.scroll(.down, by: 30, at: CellPoint(x: 5, y: 5))
        whole.scroll(.down, by: 30, at: CellPoint(x: 5, y: 5))
        check("wheel burst")
        pulled.scroll(.up, by: 3, at: CellPoint(x: 5, y: 5))
        whole.scroll(.up, by: 3, at: CellPoint(x: 5, y: 5))
        check("wheel up")
    }

    @Test("The caret stays in sight as it moves down past the screen and back up")
    func caretStaysInSightMoving() {
        let app = Self.app(Self.text(300))
        _ = app.press(.tab)  // the editor
        for line in 1...30 {
            _ = app.press(.down)
            #expect(Self.shows(app, line: line), "down to \(line):\n\(app.screen)")
        }
        for line in stride(from: 29, through: 0, by: -1) {
            _ = app.press(.up)
            #expect(Self.shows(app, line: line), "up to \(line):\n\(app.screen)")
        }
        // The least movement that shows the caret: its line at the top.
        #expect(Self.content(app).first?.trimmingCharacters(in: .whitespaces) == "l0", "\(app.screen)")
    }

    @Test("The caret stays in sight as lines are typed below the screen")
    func caretStaysInSightTyping() {
        let app = Self.app(Self.text(5))
        _ = app.press(.tab)  // the editor
        for _ in 0..<4 { _ = app.press(.down) }
        _ = app.press(.end)
        for letter in "ABCDEFGHIJKLMNOP" {
            _ = app.press(.enter)
            _ = app.press(.character(letter))
            #expect(
                Self.content(app).contains { $0.trimmingCharacters(in: .whitespaces) == String(letter) },
                "typed \(letter):\n\(app.screen)")
        }
    }

    @Test("Page Down moves the caret a screen at a time through 10,000 lines, and the wheel reaches the end")
    func pageDownReachesTheEnd() {
        let app = Self.app(Self.text(10_000))
        _ = app.press(.tab)
        var pages = 0
        while !Self.shows(app, line: 9_999), pages < 2_000 {
            _ = app.press(.pageDown)
            pages += 1
        }
        #expect(Self.shows(app, line: 9_999), "\(app.screen)")
        // A page is the scroll view's screen, not the editor's whole height.
        #expect(pages > 800, "\(pages) pages")
        let wheeled = Self.app(Self.text(10_000))
        for _ in 0..<3_400 where !wheeled.screen.contains("below") {
            wheeled.scroll(.down, by: 3, at: CellPoint(x: 5, y: 5))
        }
        #expect(wheeled.screen.contains("below") && Self.shows(wheeled, line: 9_999), "\(wheeled.screen)")
    }
}
