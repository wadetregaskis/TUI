//  🖥️ TUI — A Terminal UI framework for Swift
//  HorizontalScrollViewHeightTests.swift
//
//  SCROLL-FIT's A-SCROLLFIT-2, as the owner ruled it (b): `ScrollView(
//  .horizontal)` proposes its own height to its content, so a table or a
//  list in it is framed to that height and scrolls its own rows, as in
//  SwiftUI; content still taller (eager content) keeps its vertical
//  scrolling, so nothing becomes unreachable. Before, such a view's content
//  that took what it was offered was drawn at the measuring ladder's first
//  rung: a 10,000-row table 4,096 lines tall, every row of it built each
//  frame, the rows past it out of reach.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUI
import TUITesting
@testable import TUITestSupport

@MainActor
@Suite("SCROLL-FIT A-SCROLLFIT-2: a horizontal ScrollView proposes its own height", .drawsInTruecolor)
struct HorizontalScrollViewHeightTests {
    private static func measure(_ subject: ScrollFitSubject, rows: Int, walk: Bool = false) -> ScrollFitResult {
        ScrollFitMeasure.measure(subject, .horizontal, rows: rows, walk: walk, fitsContent: true)
    }

    @Test(
        "A Table, a List or a TextEditor in a horizontal ScrollView is its height and scrolls its own rows",
        arguments: [ScrollFitSubject.table, .listPlain, .listSectioned, .textEditor])
    func framedToTheViewsHeight(_ subject: ScrollFitSubject) {
        let tall = Self.measure(subject, rows: 10_000)
        #expect(tall.sizeA?.height == 24, "\(tall)")
        // An editor's bar is in the screen's last column, beside the page's.
        #expect(tall.innerIndicator || subject == .textEditor, "\(tall)")
        // A step builds a screenful. The first frame still builds a table's
        // rows down the ladder's first rung (4,156; 16,372 before), most
        // likely for the width ask, made at that rung's height: not traced.
        #expect(tall.builtFirst < 5_000 && tall.builtStep < 100, "\(tall)")
        // Every row reached by the wheel over it.
        #expect(Self.measure(subject, rows: 60, walk: true).reachedA)
    }

    @Test("Eager content taller than the view still scrolls down, every row reached")
    func eagerContentStillScrollsDown() {
        let result = Self.measure(.groupBox, rows: 60, walk: true)
        #expect(result.sizeA?.height == 63, "\(result)")
        #expect(result.reachedA, "\(result)")
        #expect(!result.innerIndicator, "\(result)")
    }
}
