//  🖥️ TUI — A Terminal UI framework for Swift
//  PulledRevealTests.swift
//
//  SCROLL-FIT's focus reveal as an anchor (design 1e): Tab, Shift-Tab and the
//  arrows onto a control the scroll view holds only off its band — a row of a
//  pulled or windowed stack far off screen, a button below one — show it by
//  making its row the anchor, as a minimal-movement `scrollTo` would, rather
//  than by moving the offset to where the off-band drawing estimated it and
//  closing in over the frames after: the view moves once, to where the same
//  controls drawn eagerly put it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUI
import TUITesting

/// The offsets a scroll view reported, one for each frame it moved.
@MainActor private final class Moves {
    var offsets: [Int] = []
}

/// A button, rows of buttons — the first forty one line tall, the rest four,
/// so the pitch the first rows teach a lazy stack prices the rest far short —
/// and a button below; lazy, the rows in a `LazyVStack` (pulled), eager in a
/// `VStack`.
private struct RevealPage: View {
    let lazy: Bool
    let count: Int
    let moves: Moves

    private func row(_ id: String) -> some View {
        Button {} label: {
            Text(verbatim: Int(id.dropFirst())! >= 40 ? "\(id)\n  .\n  .\n  ." : id)
        }
    }

    private var ids: [String] { (0..<count).map { "a\($0)" } }

    @ViewBuilder private var rows: some View {
        if lazy {
            LazyVStack(alignment: .leading, spacing: 0) { ForEach(ids, id: \.self) { row($0) } }
        } else {
            VStack(alignment: .leading, spacing: 0) { ForEach(ids, id: \.self) { row($0) } }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Button("top") {}
                rows
                Button("bottom") {}
            }
        }
        .onScrollGeometryChange(
            for: Int.self, of: { $0.contentOffset.y }, action: { _, offset in moves.offsets.append(offset) })
    }
}

@MainActor
@Suite("SCROLL-FIT pull: a focus move off screen sets the anchor, and the view moves once")
struct PulledRevealTests {
    /// What a focus id names: a row's text, or the control's own path's tail.
    private static func label(_ id: String?) -> String {
        guard let id else { return "-" }
        let keys = id.matches(of: /\[([^\]]+)\]/).map { String($0.1) }
        return keys.last { $0.wholeMatch(of: /a\d+/) != nil } ?? String(id.split(separator: "/").last ?? "")
    }

    /// The screen without the scrollbar's column: the lazy stack's thumb reads
    /// its estimated height, the eager one's its exact one.
    private static func lines(_ app: TestApp) -> [String] {
        app.screen.lines.map { String(($0 + String(repeating: " ", count: 30)).prefix(29)) }
    }

    /// Per key: the control it focused, the screen it left, and how many times
    /// the view moved for it.
    private static func walk(lazy: Bool, count: Int = 300, keys: [(Key, EventModifiers)]) -> [String] {
        let moves = Moves()
        let app = TestApp(width: 30, height: 10) { RevealPage(lazy: lazy, count: count, moves: moves) }
        _ = app.screen
        var out: [String] = []
        for (key, modifiers) in keys {
            let before = moves.offsets.count
            _ = app.press(key, modifiers: modifiers)
            out.append("\(label(app.focusedID)) moved \(moves.offsets.count - before)")
            out += lines(app)
        }
        return out
    }

    /// Shift-Tab from no focus goes to the scroll view, and on to the button
    /// below the rows, hundreds of lines down; on up to the last row; Tab
    /// back down, through the scroll view, wrapping to the button above the
    /// rows, then the first row, and the arrow down from it.
    private static let jumps: [(Key, EventModifiers)] = [
        (.tab, [.shift]), (.tab, [.shift]), (.tab, [.shift]),
        (.tab, []), (.tab, []), (.tab, []), (.tab, []), (.down, []),
    ]

    @Test("A far focus move draws what the eager twin draws, moving the view once")
    func farFocusMoveMatchesTheEagerTwin() {
        let lazy = Self.walk(lazy: true, keys: Self.jumps)
        let eager = Self.walk(lazy: false, keys: Self.jumps)
        #expect(lazy == eager, "\(lazy.joined(separator: "\n"))\n---\n\(eager.joined(separator: "\n"))")
    }

    @Test("A far focus move draws the same at 1,000 and 10,000 rows from the end")
    func farFocusMoveIsTheSameAtAnyCount() {
        // From the button below, Shift-Tab steps to the last row and on up:
        // the rows' texts differ by count only in their numbers, so compare
        // what moved and where.
        func shape(_ count: Int) -> [String] {
            Self.walk(lazy: true, count: count, keys: Array(repeating: (Key.tab, EventModifiers.shift), count: 4))
                .map { $0.replacing(/a\d+/, with: "a#").replacing(/[ ]+/, with: " ") }
        }
        #expect(shape(1_000) == shape(10_000))
    }
}
