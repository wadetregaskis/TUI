//  🖥️ TUI — A Terminal UI framework for Swift
//  FirstFrameIndicatorPlacementTests.swift
//
//  A scrolling view placed `.overContent` (the default) puts its indicators
//  beside its content while it holds the focus. The first focus stop on a page
//  takes the focus while its first frame is drawn — after it read where its
//  indicators go — and that frame must already have them beside the content:
//  the frame written is laid out for the focus, rather than a frame with no
//  bar and the content at the whole width, then a jump to the bar beside it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIApp
@testable import TUIAppTestSupport
import TUITesting

@MainActor
@Suite("The first frame places the indicators for the focus it takes")
struct FirstFrameIndicatorPlacementTests {
    private struct Row: Identifiable {
        let id: Int
        var name: String { "row \(id)" }
    }

    enum Kind: String, CaseIterable, CustomTestStringConvertible {
        case scrollView, list, table, textEditor
        var testDescription: String { rawValue }
    }

    private struct Page: View {
        let kind: Kind
        var body: some View {
            switch kind {
            case .scrollView:
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<40, id: \.self) { Text("row \($0)") }
                    }
                }
                .frame(width: 20, height: 8)
            case .list:
                List(0..<40, id: \.self) { Text("row \($0)") }
                    .frame(width: 20, height: 8)
            case .table:
                Table((0..<40).map(Row.init(id:))) { TableColumn("Name", value: \Row.name) }
                    .frame(width: 20, height: 10)
            case .textEditor:
                TextEditor(text: .constant((0..<40).map { "line \($0)" }.joined(separator: "\n")))
                    .frame(width: 20, height: 8)
            }
        }
    }

    @Test("The first frame of a view that takes the focus draws its bar beside the content", arguments: Kind.allCases)
    func firstFrameIsLaidOutForTheFocus(_ kind: Kind) {
        let app = TestApp(width: 30, height: 12) { Page(kind: kind) }
        app.frame(atNanos: 16_666_667)
        let first = app.screen.lines
        app.frame(atNanos: 33_333_334)
        let second = app.screen.lines
        #expect(app.focusedID != nil, "\(kind) took no focus")
        // A bar's arrow or a block of its thumb or track: a TextEditor's bar has no
        // arrows, and its thumb is drawn in eighths.
        let bar = second.contains { line in line.contains { "▲▼".contains($0) || ("\u{2580}"..."\u{259F}").contains($0) } }
        #expect(bar, "\(kind) has no bar beside it once focused: \(second)")
        #expect(first == second, "\(kind)'s first frame was not laid out for its focus:\n\(first)\n---\n\(second)")
    }
}
