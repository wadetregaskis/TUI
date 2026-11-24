//  🖥️ TUI — A Terminal UI framework for Swift
//  ColumnOfSeveralCrossingTests.swift
//
//  H-71 (SCROLL-3), the owner's O-14 (c), 2026-11-21: content of several
//  views with a loop among them, in scroll content, is drawn at the column's
//  identity step (`_ImplicitColumnOfSeveral`) whatever the loop's count, so a
//  filtered loop crossing the lazy stack's threshold (256) either way keeps
//  its siblings' focus and its rows' `@State`. Before, the step was taken
//  only past the threshold, and each crossing gave every view a new identity.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUI
import TUITesting

/// Hands each row's `@State` a number of its own when it is made, so a row
/// whose state is kept shows the number it was first given.
@MainActor private final class Births {
    var next = 0
    func take() -> Int {
        next += 1
        return next
    }
}

/// A row with state of its own: the number it was born with.
private struct BornRow: View {
    let index: Int
    @State private var born: Int

    init(index: Int, births: Births) {
        self.index = index
        _born = State(initialValue: MainActor.assumeIsolated { births.take() })
    }

    var body: some View { Text(verbatim: "r\(index) b\(born)") }
}

@MainActor
@Suite("H-71: a loop crossing 256 rows beside other views keeps their focus and its rows' state")
struct ColumnOfSeveralCrossingTests {
    enum Shape: String, CaseIterable, Sendable {
        case lazyStack, groupBox, section
    }

    /// The filter field above a loop of `wide` rows while the field is empty
    /// and of `narrow` once anything is typed in it, in `shape`.
    private struct Filtered: View {
        let shape: Shape
        let wide: Int
        let narrow: Int
        let births: Births
        @State private var query = ""

        var body: some View {
            ScrollView {
                switch shape {
                case .lazyStack:
                    LazyVStack(alignment: .leading, spacing: 0) {
                        TextField("Filter", text: $query)
                        rows
                    }
                case .groupBox:
                    GroupBox {
                        TextField("Filter", text: $query)
                        rows
                    }
                case .section:
                    LazyVStack(alignment: .leading, spacing: 0) {
                        Section {
                            rows
                        } header: {
                            TextField("Filter", text: $query)
                        }
                    }
                }
            }
        }

        private var rows: some View {
            ForEach(0..<(query.isEmpty ? wide : narrow), id: \.self) { index in
                BornRow(index: index, births: births)
            }
        }
    }

    /// Row 0's line on screen.
    private static func firstRow(_ app: TestApp) -> String? {
        app.screen.lines.lazy.map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("r0 ") || $0.contains(" r0 ") || $0.contains("│r0 ") }
    }

    @Test("Crossing down and back up keeps the field focused, its text, and row 0's state",
          arguments: Shape.allCases, [(300, 200), (200, 300)])
    func crossingKeepsState(_ shape: Shape, _ counts: (Int, Int)) {
        guard shape == .section else {
            Self.cross(shape, counts)
            return
        }
        // A lazy stack's own section with a loop in it is taken apart into
        // the stack's rows below the threshold and drawn whole, as a column
        // of its parts, past it (`SectionCore+PulledParts.swift`): not the
        // column of several O-14 (c) settles, and left as it was (H-71).
        withKnownIssue("a lazy stack's section still changes identity at the threshold") {
            Self.cross(shape, counts)
        }
    }

    private static func cross(_ shape: Shape, _ counts: (Int, Int)) {
        let births = Births()
        let app = TestApp(width: 40, height: 12) {
            Filtered(shape: shape, wide: counts.0, narrow: counts.1, births: births)
        }
        // The scroll view takes the focus first, then the field.
        for _ in 0..<3 where app.focusedID?.hasPrefix("textfield-") != true { _ = app.press(.tab) }
        let focused = app.focusedID
        #expect(focused?.hasPrefix("textfield-") == true, "\(shape): \(focused ?? "nil")\n\(app.screen)")
        let before = Self.firstRow(app)
        #expect(before != nil, "\(shape):\n\(app.screen)")

        // Typing crosses the threshold one way; the second letter must land
        // in the same field.
        app.type("x")
        app.type("y")
        #expect(app.focusedID == focused, "\(shape) after typing: \(app.focusedID ?? "nil") was \(focused ?? "nil")")
        #expect(app.screen.contains("xy"), "\(shape):\n\(app.screen)")
        #expect(Self.firstRow(app) == before, "\(shape) row 0 after typing:\n\(app.screen)")

        // And back.
        _ = app.press(.backspace, times: 2)
        #expect(app.focusedID == focused, "\(shape) after clearing: \(app.focusedID ?? "nil") was \(focused ?? "nil")")
        #expect(Self.firstRow(app) == before, "\(shape) row 0 after clearing:\n\(app.screen)")
        app.type("z")
        #expect(app.screen.contains("z"), "\(shape):\n\(app.screen)")
        #expect(app.focusedID == focused, "\(shape) after retyping: \(app.focusedID ?? "nil")")
    }

    // MARK: - A small loop draws as it did

    /// The small shapes: a lazy stack at each alignment and spacing, and the
    /// containers with no lazy counterpart, each a header and a loop.
    enum Small: String, CaseIterable, Sendable {
        case leading0, center1, trailing0, groupBox, disclosureGroup, twoLoops
        /// A lazy stack marked `scrollTargetLayout()` under `.viewAligned`:
        /// its header and every row are where a scroll settles.
        case viewAligned
    }

    /// Rows of uneven width, some two lines, one with a filling frame, a
    /// header above them and a footer below, in scroll content; drawn `whole`
    /// as before the column step (`drawsContainerRowsWhole`), the twin.
    private static func small(_ shape: Small, rows: Int, whole: Bool) -> TestApp {
        TestApp(width: 30, height: 12) {
            ScrollView {
                switch shape {
                case .leading0: LazyVStack(alignment: .leading, spacing: 0) { smallContent(rows) }
                case .center1: LazyVStack(alignment: .center, spacing: 1) { smallContent(rows) }
                case .trailing0: LazyVStack(alignment: .trailing, spacing: 0) { smallContent(rows) }
                case .groupBox: GroupBox { smallContent(rows) }
                case .disclosureGroup:
                    DisclosureGroup("More", isExpanded: .constant(true)) { smallContent(rows) }
                case .twoLoops:
                    LazyVStack(alignment: .leading, spacing: 0) {
                        smallContent(rows)
                        ForEach(0..<3, id: \.self) { Text(verbatim: "tail \($0)") }
                    }
                case .viewAligned:
                    LazyVStack(alignment: .leading, spacing: 0) { smallContent(rows) }
                        .scrollTargetLayout()
                }
            }
            .scrollTargetBehavior(.viewAligned)
            .environment(\.drawsContainerRowsWhole, whole)
        }
    }

    @ViewBuilder private static func smallContent(_ rows: Int) -> some View {
        Text("a wide header line")
        ForEach(0..<rows, id: \.self) { index in
            if index == 4 {
                Text(verbatim: "fills").frame(maxWidth: .infinity)
            } else {
                Text(verbatim: index.isMultiple(of: 3) ? "row \(index)\n  more" : "r\(index)")
            }
        }
        Text("footer")
    }

    @Test("A small loop beside other views draws what it drew before the step, at the top, paged and at the end",
          arguments: Small.allCases, [0, 1, 40])
    func smallLoopDrawsAsBefore(_ shape: Small, _ rows: Int) {
        let stepped = Self.small(shape, rows: rows, whole: false)
        let before = Self.small(shape, rows: rows, whole: true)
        func check(_ step: String) {
            #expect(
                stepped.screen.lines == before.screen.lines,
                "\(shape) \(rows) \(step):\n\(stepped.screen)\n---\n\(before.screen)")
        }
        check("top")
        for page in 1...2 {
            for app in [stepped, before] { _ = app.press(.pageDown) }
            check("page \(page)")
        }
        for tick in 1...3 {
            for app in [stepped, before] { app.scroll(.down, by: 1, at: CellPoint(x: 5, y: 5)) }
            check("wheel \(tick)")
        }
        for app in [stepped, before] { _ = app.press(.end) }
        check("end")
    }
}
