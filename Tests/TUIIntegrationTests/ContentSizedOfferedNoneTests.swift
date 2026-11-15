//  🖥️ TUI — A Terminal UI framework for Swift
//  ContentSizedOfferedNoneTests.swift
//
//  SCROLL-FIT P7 (design 2a, 2f): the views that answered the height they
//  were offered, flexibly — `List` and `TextEditor` drawn whole, a scroll
//  view, a grouped `Form` (a scroll view outside one), the split views — are
//  their content's height when they are asked how tall they would be with
//  nothing to stop them: under `.fixedSize`, and in a scroll view's content
//  where nothing pulls them. Before, under `.fixedSize` they were the height
//  left on the screen (23 lines of a 10,000-row list), and in a scroll view
//  the measuring ladder's first rung (4,096 lines), the rows past it out of
//  reach in a split view.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUI
import TUITesting
@testable import TUITestSupport

@MainActor
@Suite("SCROLL-FIT P7: content-sized views asked for no height are their content's height", .drawsInTruecolor)
struct ContentSizedOfferedNoneTests {
    private static func measure(_ subject: ScrollFitSubject, _ situation: ScrollFitSituation, rows: Int)
        -> ScrollFitResult
    {
        ScrollFitMeasure.measure(subject, situation, rows: rows, walk: false, fitsContent: true)
    }

    // MARK: - Under .fixedSize, outside a scroll view

    @Test(
        "A tall List or TextEditor under .fixedSize is its content's height, and draws only what shows",
        arguments: [
            (ScrollFitSubject.listPlain, 10_002), (.listSectioned, 10_004), (.listOutline, 10_002),
            (.textEditor, 10_000),
        ])
    func tallUnderFixedSize(_ subject: ScrollFitSubject, _ height: Int) {
        let result = Self.measure(subject, .fixedSize, rows: 10_000)
        #expect(result.sizeA == CellSize(width: 60, height: height), "\(result)")
        #expect(result.builtFirst < 150, "\(result)")
    }

    @Test("A 60-row List under .fixedSize draws what the list framed to its height draws")
    func listUnderFixedSizeDrawsWhatItsFramedTwinDraws() {
        let data = ScrollFitCatalogue.items("r", 60)
        func page(framed: Bool) -> TestApp {
            TestApp(width: 40, height: 12) {
                VStack(spacing: 0) {
                    Text("title")
                    if framed {
                        List { ForEach(data) { Text($0.label) } }.frame(height: 62)
                    } else {
                        List { ForEach(data) { Text($0.label) } }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .environment(\.scrollFitsContent, true)
            }
        }
        let pulled = page(framed: false)
        let whole = page(framed: true)
        #expect(pulled.screen.text == whole.screen.text, "\(pulled.screen)\n---\n\(whole.screen)")
    }

    /// 2,100 rows of a grouped form are 4,199 lines (a row and the rule
    /// under it), past the measuring ladder's first rung.
    @Test("A grouped Form taller than the ladder's first rung under .fixedSize is its content's height")
    func groupedFormUnderFixedSize() {
        let result = Self.measure(.formGrouped, .fixedSize, rows: 2_100)
        #expect(result.sizeA == CellSize(width: 60, height: 4_199), "\(result)")
    }

    // MARK: - In a scroll view, where nothing pulls them

    @Test("A horizontal ScrollView in a vertical one's content is its content's height")
    func crossAxisScrollViewIsItsContentsHeight() {
        let result = Self.measure(.scrollCrossAxis, .underTitle, rows: 3)
        #expect(result.sizeA == CellSize(width: 60, height: 3), "\(result)")
        let tall = Self.measure(.scrollCrossAxis, .underTitle, rows: 5_000)
        #expect(tall.sizeA?.height == 5_000, "\(tall)")
        #expect(!tall.innerIndicator, "\(tall)")
    }

    @Test("A split view in a scroll view is its tallest pane's height beside, its panes' one above another")
    func splitViewsAreTheirPanesHeight() {
        #expect(Self.measure(.hSplitView, .underTitle, rows: 3).sizeA == CellSize(width: 60, height: 3))
        #expect(Self.measure(.vSplitView, .underTitle, rows: 3).sizeA == CellSize(width: 60, height: 5))
        #expect(Self.measure(.hSplitView, .underTitle, rows: 5_000).sizeA?.height == 5_000)
        #expect(Self.measure(.vSplitView, .underTitle, rows: 5_000).sizeA?.height == 5_002)
    }

    @Test("Every row of a split view's pane is reached by the wheel, and a vertical split cuts no pane")
    func splitViewsRowsAreReached() {
        for subject in [ScrollFitSubject.hSplitView, .vSplitView] {
            let result = ScrollFitMeasure.measure(subject, .underTitle, rows: 60, fitsContent: true)
            #expect(result.reachedA, "\(subject) \(result)")
        }
        // The vertical split's top pane whole: its last row right above the
        // divider, the bottom pane below it.
        let app = TestApp(width: 30, height: 12) {
            ScrollView {
                VSplitView {
                    VStack(alignment: .leading, spacing: 0) { ForEach(0..<20, id: \.self) { Text("r\($0)") } }
                    Text("bottom")
                }
            }
            .environment(\.scrollFitsContent, true)
        }
        app.scroll(.down, by: 30, at: CellPoint(x: 5, y: 5))
        let lines = app.screen.lines
        let last = lines.firstIndex { $0.hasPrefix("r19") }
        let bottom = lines.firstIndex { $0.hasPrefix("bottom") }
        #expect(last != nil && bottom == last.map { $0 + 2 }, "\(app.screen)")
    }
}
