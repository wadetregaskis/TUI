//  🖥️ TUI — A Terminal UI framework for Swift
//  AnchoredTopEdgeTests.swift
//
//  The anchored walk's top edge (SCROLL-FIT design, "How estimates stay
//  steady", rule 2): the offset is dead-reckoned in the estimate's lines,
//  the rows are walked in their own, and where the walk reaches the first
//  row the two are reconciled, so the first row is on top exactly when the
//  offset is 0. Past 256 rows of several heights, an estimate below the
//  rows' mean ran the offset to 0 with rows still above, which no key, wheel
//  or Home could reach; one above it showed the first row with lines still
//  "above" it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUI
import TUITesting

/// The scroll view's offset, as `onScrollGeometryChange` last reported it.
@MainActor private final class OffsetLog {
    var offset = 0
}

@MainActor
@Suite("The anchored walk's top edge: offset 0 is the first row's top")
struct AnchoredTopEdgeTests {
    /// 2,000 rows (past the anchored walk's 256), the first `lead` of
    /// `leadHeight` lines and the rest of `restHeight`: a first screen that
    /// prices the rest at the wrong pitch.
    private static func app(lead: Int, leadHeight: Int, restHeight: Int, log: OffsetLog) -> TestApp {
        TestApp(width: 30, height: 12) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<2_000, id: \.self) { index in
                        Text(verbatim: "row \(index)")
                            .frame(height: index < lead ? leadHeight : restHeight, alignment: .top)
                    }
                }
            }
            .onScrollGeometryChange(for: Int.self, of: { $0.contentOffset.y }, action: { log.offset = $1 })
        }
    }

    /// The row drawn on the screen's top line, if a row's first line is there.
    private static func topRow(_ app: TestApp) -> Int? {
        let words = app.screen.lines.first?.split(separator: " ") ?? []
        guard words.count >= 2, words[0] == "row" else { return nil }
        return Int(words[1])
    }

    /// From the end, a page up a frame (and then, as a user would, Up and
    /// Home at the top) must reach row 0 on the top line at
    /// offset 0, and never show row 0 there at any other offset.
    @Test("Stepping up from the end reaches row 0 exactly at offset 0",
          arguments: [(lead: 20, leadHeight: 1, restHeight: 3), (lead: 20, leadHeight: 3, restHeight: 1)])
    func steppingUpFromTheEndReachesTheFirstRow(_ shape: (lead: Int, leadHeight: Int, restHeight: Int)) {
        let log = OffsetLog()
        let app = Self.app(lead: shape.lead, leadHeight: shape.leadHeight, restHeight: shape.restHeight, log: log)
        #expect(Self.topRow(app) == 0)
        _ = app.press(.end)
        #expect(Self.topRow(app) != 0, "\(app.screen)")
        var steps = 0
        var early: String?
        while log.offset > 0, steps < 2_000 {
            _ = app.press(.pageUp)
            steps += 1
            if early == nil, Self.topRow(app) == 0, log.offset != 0 {
                early = "row 0 on top at offset \(log.offset): \(app.screen)"
            }
        }
        #expect(early == nil, "\(early ?? "")")
        // At 0 nothing above remains for a key to reach.
        _ = app.press(.up)
        _ = app.press(.home)
        #expect(log.offset == 0)
        #expect(Self.topRow(app) == 0, "offset 0 shows \(app.screen)")
    }
}
