//  🖥️ TUI — A Terminal UI framework for Swift
//  PulledTargetLayoutTests.swift
//
//  SCROLL-FIT's pull and what a scroll view asks of its content's rows: a
//  stack marked with `scrollTargetLayout()` under a title in a column, and so
//  pulled (`StackPulledColumn.swift`), is settled on by `.viewAligned` and
//  `.paging` as the same rows are when the stack is the scroll view's
//  content; the row at the top stays where it is as rows are inserted above
//  it, as it does there. Each case runs twinned: the pulled stack against the
//  same lines as one top-level stack, whose first row is the title. A row
//  the app holds with `.anchorPosition(.row(_:))` keeps its line too.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

@testable import TUI
import TUITesting

/// The rows, as a feed an app inserts into.
@Observable @MainActor private final class Feed {
    var ids: [Int]
    init(_ count: Int) { ids = Array(0..<count) }
}

/// The rows each page holds with `.anchorPosition`.
@Observable @MainActor private final class Anchors {
    var pulled: ScrollAnchor<Int>?
    var top: ScrollAnchor<Int>?
}

@MainActor
@Suite("SCROLL-FIT pull: a pulled stack's rows are settled on and held as a top-level stack's are")
struct PulledTargetLayoutTests {
    enum Behavior: String, CaseIterable, Sendable {
        case viewAligned, paging, free
    }

    /// Row `id`'s text: two lines every third row, three every fifth, so
    /// that a step lands inside a row unless something settles it. Row `-1`
    /// is the title, a row of the top-level twin's own `ForEach`, so that its
    /// stack is keyed alike throughout and draws by the anchored window as
    /// the pulled one does.
    @ViewBuilder
    private static func row(_ id: Int) -> some View {
        if id == Self.titleID {
            Text("title").frame(height: 2, alignment: .top)
        } else {
            Text(verbatim: "r\(id)").frame(height: id.isMultiple(of: 5) ? 3 : id.isMultiple(of: 3) ? 2 : 1, alignment: .top)
        }
    }

    private static let titleID = Int.min

    @ViewBuilder
    private static func page(pulled: Bool, feed: Feed, behavior: Behavior) -> some View {
        let scroll = ScrollView {
            if pulled {
                VStack(alignment: .leading, spacing: 0) {
                    row(Self.titleID)
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(feed.ids, id: \.self) { row($0) }
                    }
                    .scrollTargetLayout()
                }
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach([Self.titleID] + feed.ids, id: \.self) { row($0) }
                }
                .scrollTargetLayout()
            }
        }
        switch behavior {
        case .viewAligned: scroll.scrollTargetBehavior(.viewAligned)
        case .paging: scroll.scrollTargetBehavior(.paging)
        case .free: scroll
        }
    }

    private static func app(pulled: Bool, feed: Feed, behavior: Behavior) -> TestApp {
        TestApp(width: 24, height: 12) { page(pulled: pulled, feed: feed, behavior: behavior) }
    }

    /// The screen but the scrollbar's column: the pulled stack's thumb reads
    /// an estimated height.
    private static func content(_ app: TestApp) -> [String] {
        app.screen.lines.map { String(($0 + String(repeating: " ", count: 24)).prefix(23)) }
    }

    @Test("A behaviour settles on a pulled stack's rows as on a top-level stack's", arguments: [Behavior.viewAligned, .paging])
    func settlesAsAtTheTopLevel(_ behavior: Behavior) {
        let pulled = Self.app(pulled: true, feed: Feed(300), behavior: behavior)
        let top = Self.app(pulled: false, feed: Feed(300), behavior: behavior)
        func check(_ step: String) {
            #expect(Self.content(pulled) == Self.content(top), "\(behavior) \(step):\n\(pulled.screen)\n---\n\(top.screen)")
        }
        check("first frame")
        for tick in 1...12 {
            pulled.scroll(.down, at: CellPoint(x: 3, y: 3))
            top.scroll(.down, at: CellPoint(x: 3, y: 3))
            check("tick \(tick) down")
        }
        for tick in 1...4 {
            pulled.scroll(.up, at: CellPoint(x: 3, y: 3))
            top.scroll(.up, at: CellPoint(x: 3, y: 3))
            check("tick \(tick) up")
        }
        for step in 1...3 {
            _ = pulled.press(.pageDown)
            _ = top.press(.pageDown)
            check("page \(step)")
        }
    }

    @Test("Rows inserted above a pulled stack's top row leave the rows on screen where they are", arguments: [Behavior.free, .viewAligned])
    func holdsTheTopRow(_ behavior: Behavior) {
        let pulledFeed = Feed(300)
        let topFeed = Feed(300)
        let pulled = Self.app(pulled: true, feed: pulledFeed, behavior: behavior)
        let top = Self.app(pulled: false, feed: topFeed, behavior: behavior)
        for _ in 0..<20 {
            pulled.scroll(.down, at: CellPoint(x: 3, y: 3))
            top.scroll(.down, at: CellPoint(x: 3, y: 3))
        }
        let before = Self.content(pulled)
        #expect(before == Self.content(top), "\(behavior) before:\n\(pulled.screen)\n---\n\(top.screen)")
        for insert in 1...3 {
            let ids = (-5 * insert)..<(-5 * insert + 5)
            pulledFeed.ids.insert(contentsOf: ids, at: 0)
            topFeed.ids.insert(contentsOf: ids, at: 0)
            pulled.advance(by: .zero)
            top.advance(by: .zero)
            #expect(Self.content(top) == before, "\(behavior) insert \(insert), top level:\n\(top.screen)")
            #expect(Self.content(pulled) == before, "\(behavior) insert \(insert), pulled:\n\(pulled.screen)")
        }
        // And the rows inserted are there to scroll up to, as at the top level.
        for tick in 1...12 {
            pulled.scroll(.up, at: CellPoint(x: 3, y: 3))
            top.scroll(.up, at: CellPoint(x: 3, y: 3))
            #expect(Self.content(pulled) == Self.content(top), "\(behavior) up \(tick):\n\(pulled.screen)\n---\n\(top.screen)")
        }
    }

    /// A page whose row `held` the app holds with `.anchorPosition(.row(_:))`.
    private static func heldPage(pulled: Bool, feed: Feed, anchor: Binding<ScrollAnchor<Int>?>) -> some View {
        page(pulled: pulled, feed: feed, behavior: .free).anchorPosition(anchor)
    }

    @Test("A row held by .anchorPosition(.row(_:)) in a pulled stack keeps its line as rows come and go above it")
    func holdsTheDesignatedRow() {
        let pulledFeed = Feed(300)
        let topFeed = Feed(300)
        let anchors = Anchors()
        let pulled = TestApp(width: 24, height: 12) {
            Self.heldPage(pulled: true, feed: pulledFeed, anchor: Binding(get: { anchors.pulled }, set: { anchors.pulled = $0 }))
        }
        let top = TestApp(width: 24, height: 12) {
            Self.heldPage(pulled: false, feed: topFeed, anchor: Binding(get: { anchors.top }, set: { anchors.top = $0 }))
        }
        for _ in 0..<20 {
            pulled.scroll(.down, at: CellPoint(x: 3, y: 3))
            top.scroll(.down, at: CellPoint(x: 3, y: 3))
        }
        // The row on the screen's sixth line, held there.
        guard let line = Self.content(top)[5].firstMatch(of: /r(\d+)/), let id = Int(line.1) else {
            Issue.record("no row on the sixth line: \(top.screen)")
            return
        }
        anchors.pulled = .row(id)
        anchors.top = .row(id)
        pulled.advance(by: .zero)
        top.advance(by: .zero)
        let before = Self.content(top)
        #expect(Self.content(pulled) == before, "held:\n\(pulled.screen)\n---\n\(top.screen)")
        for change in 1...4 {
            if change.isMultiple(of: 2) {
                pulledFeed.ids.removeFirst(3)
                topFeed.ids.removeFirst(3)
            } else {
                // Inserted above the row on screen, not at the top: the row
                // at the top would be held without the designation.
                let at = pulledFeed.ids.firstIndex(of: id - 4) ?? 0
                let ids = (-10 * change)..<(-10 * change + 6)
                pulledFeed.ids.insert(contentsOf: ids, at: at)
                topFeed.ids.insert(contentsOf: ids, at: at)
            }
            pulled.advance(by: .zero)
            top.advance(by: .zero)
            #expect(Self.content(top).firstIndex { $0.hasPrefix("r\(id) ") } == 5, "change \(change), top level:\n\(top.screen)")
            #expect(Self.content(pulled).firstIndex { $0.hasPrefix("r\(id) ") } == 5, "change \(change), pulled:\n\(pulled.screen)")
        }
    }
}
