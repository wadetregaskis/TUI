//  🖥️ TUI — A Terminal UI framework for Swift
//  TitledLoopTopRowHoldTests.swift
//
//  H-71f: a lazy stack whose loop has a title beside it, `LazyVStack {
//  Text(title); ForEach(rows) { … } }`, keeps the row at the top of its
//  viewport where it is as rows are inserted at, or removed from, the top of
//  the loop, as it does without the title (the top-row hold,
//  `Documentation/Layout and scrolling/Scroll anchoring.md` §5) and as
//  SwiftUI's lazy stacks do through an insert (`Tools/SwiftUIProbes/Scroll
//  anchoring/hold.out`, case 1; a removal is held too, a recorded deviation,
//  R14). At the top of the stack the offset stays 0, so the rows inserted
//  show (case 4; `ScrollWindowHoldTests.atTheTopTheNewRowsShow`). Before the
//  fix, under a title, no hold ran at all for 256 rows or fewer, and past
//  that none in the frame after a jump into the loop (the SCROLL-FIT design's
//  H-71f record).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
import TUITesting

@MainActor
@Suite("H-71f: a titled lazy stack holds its top row through a change at the top of its loop")
struct TitledLoopTopRowHoldTests {
    /// Where the titles stand beside the loop.
    enum Titles: String, CaseIterable, Sendable {
        case none, oneAbove, twoAbove, oneBelow, twoBelow, aboveAndBelow
    }

    /// What is done to the top of the loop.
    enum Change: String, CaseIterable, Sendable {
        case insertOne, insertTen, deleteOne, deleteTen

        /// The new first row, from 0.
        var first: Int {
            switch self {
            case .insertOne: -1
            case .insertTen: -10
            case .deleteOne: 1
            case .deleteTen: 10
            }
        }
    }

    /// Where the stack is scrolled when the change is made.
    enum Place: String, CaseIterable, Sendable {
        case top, middle, end

        @MainActor func scroll(_ app: TestApp) {
            _ = app.press(.tab)
            switch self {
            case .top: break
            case .middle: _ = app.press(.pageDown, times: 5)
            case .end: _ = app.press(.end)
            }
        }
    }

    /// A loop of `count` rows from 0, with `titles` beside it; `^` moves its
    /// first row to `change`'s (or it starts there, `startsChanged`), and `+`
    /// writes a state that changes nothing drawn.
    private struct Titled: View {
        let titles: Titles
        let spacing: Int
        let count: Int
        let change: Change
        let startsChanged: Bool
        @State private var changed: Bool?
        @State private var written = false

        var body: some View {
            // Each shape its own stack, so the titles are plain views among
            // the stack's children, not a loop or an `if` of their own.
            ScrollView {
                switch titles {
                case .none:
                    LazyVStack(alignment: .leading, spacing: spacing) { rows }
                case .oneAbove:
                    LazyVStack(alignment: .leading, spacing: spacing) {
                        Text("title above 0")
                        rows
                    }
                case .twoAbove:
                    LazyVStack(alignment: .leading, spacing: spacing) {
                        Text("title above 0")
                        Text("title above 1")
                        rows
                    }
                case .oneBelow:
                    LazyVStack(alignment: .leading, spacing: spacing) {
                        rows
                        Text("title below 0")
                    }
                case .twoBelow:
                    LazyVStack(alignment: .leading, spacing: spacing) {
                        rows
                        Text("title below 0")
                        Text("title below 1")
                    }
                case .aboveAndBelow:
                    LazyVStack(alignment: .leading, spacing: spacing) {
                        Text("title above 0")
                        rows
                        Text("title below 0")
                    }
                }
            }
            // The rows compared, not the indicator, which a change of the
            // count moves.
            .scrollIndicators(.hidden)
            .onKeyPress("^") {
                changed = true
                return .handled
            }
            .onKeyPress("+") {
                written.toggle()
                return .handled
            }
        }

        private var rows: some View {
            ForEach(((changed ?? startsChanged) ? change.first : 0)..<count, id: \.self) {
                Text(verbatim: "row \($0)")
            }
        }
    }

    /// Every count (within the threshold, past it, far past it), change and
    /// place, at spacing 0 and 1, for each place of the titles: the frame of
    /// the change, and a write after it, keep the lines on screen where they
    /// were; at the top, they are what the changed rows draw from the top.
    @Test("The row at the top of the viewport stays there through a change at the top of the loop",
          arguments: Titles.allCases, [0, 1])
    func topRowIsHeld(_ titles: Titles, _ spacing: Int) {
        for count in [50, 250, 1_000] {
            for change in Change.allCases {
                for place in Place.allCases {
                    Self.check(titles, spacing: spacing, count: count, change: change, place: place)
                }
            }
        }
    }

    private static func check(_ titles: Titles, spacing: Int, count: Int, change: Change, place: Place) {
        let app = TestApp(width: 30, height: 12) {
            Titled(titles: titles, spacing: spacing, count: count, change: change, startsChanged: false)
        }
        place.scroll(app)
        let label = "\(titles) spacing \(spacing), \(count) rows, \(change) at the \(place)"
        let expected: [String]
        if place == .top {
            let fresh = TestApp(width: 30, height: 12) {
                Titled(titles: titles, spacing: spacing, count: count, change: change, startsChanged: true)
            }
            Place.top.scroll(fresh)
            expected = fresh.screen.lines
        } else {
            expected = app.screen.lines
        }
        app.type("^")
        #expect(app.screen.lines == expected, "\(label):\n\(app.screen)\n--- expected:\n\(expected.joined(separator: "\n"))")
        app.type("+")
        #expect(
            app.screen.lines == expected,
            "\(label), then a write:\n\(app.screen)\n--- expected:\n\(expected.joined(separator: "\n"))")
    }
}
