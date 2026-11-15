//  🖥️ TUI — A Terminal UI framework for Swift
//  PulledFormTests.swift
//
//  SCROLL-FIT (design P4) for a grouped `Form`: a grouped form in a scroll
//  view's content is no scroll view of its own but its sections' height, and the
//  scroll view around it scrolls it and reveals the control Tab reaches. Its
//  drawing is the same form drawn whole, framed to its full height.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUI
import TUITesting

/// A title, a grouped form of `sections` sections of five buttons, and a
/// button below it, in a scroll view.
private struct FormPage: View {
    let sections: Int
    /// The twin's frame: the same form drawn whole, framed to its full
    /// height. `nil` for the content-sized form.
    var framed: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("title")
                if let framed {
                    form.frame(height: framed)
                } else {
                    form
                }
                Button("below") {}
            }
        }
    }

    var form: some View {
        Form {
            ForEach(0..<sections, id: \.self) { section in
                Section("S\(section)") {
                    ForEach(0..<5, id: \.self) { row in
                        Button("b\(section)-\(row)") {}
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

@MainActor
@Suite("SCROLL-FIT: a grouped Form in a scroll view is its content's height, scrolled by the scroll view")
struct PulledFormTests {
    private static func app(_ sections: Int, framed: Int? = nil) -> TestApp {
        TestApp(width: 30, height: 12) { FormPage(sections: sections, framed: framed) }
    }

    /// The form's lines drawn whole: drawn alone on a screen taller than it,
    /// up to its last line that is not blank.
    private static func wholeHeight(_ sections: Int) -> Int {
        let tall = TestApp(width: 30, height: 600) { FormPage(sections: sections).form }
        let lines = tall.screen.lines
        return (lines.lastIndex { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? 0) + 1
    }

    /// The screen's lines without the scroll view's bar.
    private static func content(_ app: TestApp) -> [String] {
        app.screen.lines.map { String(($0 + String(repeating: " ", count: 30)).prefix(28)) }
    }

    @Test("A short form is its sections' height: the button below it stands right under it")
    func shortFormIsItsContentsHeight() {
        let height = Self.wholeHeight(1)
        let app = Self.app(1)
        let below = app.screen.lines.firstIndex { $0.contains("below") }
        #expect(below == 1 + height, "\(app.screen)")
        #expect(Self.content(app) == Self.content(Self.app(1, framed: height)), "\(app.screen)")
    }

    /// As the scroll view it would be lays its sections out: as wide as it
    /// is offered, at the leading edge. Hugging them, it stood centred in a
    /// column under a wider title.
    @Test("A form in a column under a wider title stands at the column's leading edge")
    func formStandsAtTheLeadingEdge() {
        let app = TestApp(width: 30, height: 12) {
            ScrollView {
                VStack {
                    Text("a title wider than the form")
                    Form { Text("row") }.formStyle(.grouped)
                }
            }
        }
        let row = app.screen.lines.first { $0.contains("row") }
        #expect(row?.hasPrefix("row") == true, "\(app.screen)")
    }

    @Test("A tall form draws what the form drawn whole draws as the scroll view moves over it")
    func tallFormDrawsWhatTheWholeFormDraws() {
        let pulled = Self.app(20)
        let whole = Self.app(20, framed: Self.wholeHeight(20))
        func check(_ step: String) {
            #expect(Self.content(pulled) == Self.content(whole), "\(step):\n\(pulled.screen)\n---\n\(whole.screen)")
        }
        check("top")
        for step in 1...6 {
            pulled.scroll(.down, by: 3, at: CellPoint(x: 5, y: 5))
            whole.scroll(.down, by: 3, at: CellPoint(x: 5, y: 5))
            check("wheel \(step)")
        }
        pulled.scroll(.down, by: 100, at: CellPoint(x: 5, y: 5))
        whole.scroll(.down, by: 100, at: CellPoint(x: 5, y: 5))
        check("wheel to the end")
        #expect(pulled.screen.contains("below"), "\(pulled.screen)")
    }

    @Test("Tab reaches a button below the screen, and the scroll view reveals it")
    func tabRevealsAControlBelowTheScreen() {
        let app = Self.app(20)
        // The first button may hold the focus at launch, so Tab `n` is on
        // button `n` or `n + 1`.
        for index in 0..<30 {
            _ = app.press(.tab)
            let names = [index, index + 1].map { "b\($0 / 5)-\($0 % 5)" }
            #expect(names.contains { app.screen.contains($0) }, "tab \(index) to \(names):\n\(app.screen)")
        }
    }
}
