//  🖥️ TUI — A Terminal UI framework for Swift
//  SectionLoopCrossingTests.swift
//
//  The owner's H71-SECTIONS (b), 2026-11-24: a lazy stack's sections made by
//  a loop — `LazyVStack { ForEach(groups) { Section { ForEach(rows) } } }` —
//  draw at the same identities whatever the count of their rows together, so
//  a row's `@State` and the focus on it survive the rows crossing the lazy
//  stack's threshold (256) either way, as they do in SwiftUI. Before, at or
//  below 256 each section laid its parts out whole, and past it drew them as
//  a column of its parts (`_ImplicitColumnOfSeveral`), so every row started
//  afresh and the focus left its row at each crossing.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUI
import TUITesting

/// A focusable row with a counter of its own, bumped by pressing it.
private struct CountedRow: View {
    let group: Int
    let index: Int
    @State private var presses = 0

    var body: some View {
        Button {
            presses += 1
        } label: {
            Text(verbatim: "g\(group) r\(index) n\(presses)")
        }
    }
}

@MainActor
@Suite("H71-SECTIONS: a loop of sections whose rows cross 256 keeps its rows' state and focus")
struct SectionLoopCrossingTests {
    enum Shape: String, CaseIterable, Sendable {
        case plain0, plain1, titled0, titled1, pinned0, pinned1, pinnedTitled0, pinnedTitled1

        var pinned: Bool { rawValue.hasPrefix("pinned") }
        var titled: Bool { rawValue.contains("itled") }
        var spacing: Int { rawValue.hasSuffix("1") ? 1 : 0 }
    }

    /// 25 sections of nine rows, 250 rows counting a header each; `+` gives
    /// the last ten rows more (260) and `-` takes them away again. Or,
    /// `manySections`, 250 sections of a row each, and `+` ten sections more:
    /// the sections themselves crossing the threshold, past which the stack
    /// no longer prices their loops by a sample (the SCROLL-FIT design's S7).
    private struct Grouped: View {
        let shape: Shape
        let startsLong: Bool
        var manySections = false
        @State private var long: Bool?

        var body: some View {
            ScrollView {
                if shape.titled {
                    LazyVStack(alignment: .leading, spacing: shape.spacing, pinnedViews: pins) {
                        Text("a title")
                        groups
                    }
                } else {
                    LazyVStack(alignment: .leading, spacing: shape.spacing, pinnedViews: pins) { groups }
                }
            }
            .onKeyPress("+") {
                long = true
                return .handled
            }
            .onKeyPress("-") {
                long = false
                return .handled
            }
        }

        private var pins: PinnedScrollableViews { shape.pinned ? .sectionHeaders : [] }

        private func rows(_ group: Int) -> Int {
            if manySections { return 1 }
            return group == 24 && (long ?? startsLong) ? 19 : 9
        }

        private var groups: some View {
            ForEach(0..<(manySections ? ((long ?? startsLong) ? 260 : 250) : 25), id: \.self) { group in
                Section {
                    ForEach(0..<rows(group), id: \.self) { index in
                        CountedRow(group: group, index: index)
                    }
                } header: {
                    Text(verbatim: "Group \(group)")
                }
            }
        }
    }

    /// The line of the row pressed `presses` times.
    private static func pressed(_ app: TestApp, _ presses: Int) -> String? {
        app.screen.lines.lazy.map { $0.trimmingCharacters(in: .whitespaces) }.first { $0.contains(" n\(presses)") }
    }

    @Test("Crossing 256 and back keeps the focused row focused and its state",
          arguments: Shape.allCases, [false, true])
    func crossingKeepsState(_ shape: Shape, _ startsLong: Bool) {
        Self.cross(shape, startsLong, manySections: false)
    }

    @Test("Sections crossing 256 and back keep the focused row focused and its state",
          arguments: Shape.allCases, [false, true])
    func sectionsCrossingKeepState(_ shape: Shape, _ startsLong: Bool) {
        Self.cross(shape, startsLong, manySections: true)
    }

    private static func cross(_ shape: Shape, _ startsLong: Bool, manySections: Bool) {
        let app = TestApp(width: 40, height: 12) {
            Grouped(shape: shape, startsLong: startsLong, manySections: manySections)
        }
        // The scroll view takes the focus first, then the first row.
        for _ in 0..<3 where app.focusedID?.hasPrefix("button-") != true { _ = app.press(.tab) }
        _ = app.press(.enter)
        let focused = app.focusedID
        let row = Self.pressed(app, 1)
        #expect(focused?.hasPrefix("button-") == true, "\(shape): \(focused ?? "nil")\n\(app.screen)")
        #expect(row != nil, "\(shape) precondition, a row pressed:\n\(app.screen)")

        for (step, key) in [("across", startsLong ? "-" : "+"), ("back", startsLong ? "+" : "-")] {
            app.type(key)
            #expect(app.focusedID == focused, "\(shape) \(step): \(app.focusedID ?? "nil") was \(focused ?? "nil")")
            #expect(Self.pressed(app, 1) == row, "\(shape) \(step), the row's state:\n\(app.screen)")
        }
        // The focus still on the row: pressing bumps it again.
        _ = app.press(.enter)
        #expect(Self.pressed(app, 2)?.prefix(6) == row?.prefix(6), "\(shape) after:\n\(app.screen)")
    }

    // MARK: - A small stack of sections draws as it did

    /// `sections` sections of `rows` uneven rows (some two lines, one with a
    /// filling frame), headers and footers, in `shape`; drawn `whole` as
    /// before the step (`drawsContainerRowsWhole`), the twin.
    private static func small(_ shape: Shape, sections: Int, rows: Int, whole: Bool) -> TestApp {
        func groups() -> some View {
            ForEach(0..<sections, id: \.self) { group in
                Section {
                    ForEach(0..<rows, id: \.self) { index in
                        if index == 4 {
                            Text(verbatim: "fills \(group)").frame(maxWidth: .infinity)
                        } else {
                            Text(verbatim: index.isMultiple(of: 3) ? "g\(group) row \(index)\n  more" : "g\(group) r\(index)")
                        }
                    }
                } header: {
                    Text(verbatim: "Group \(group), a wide header")
                } footer: {
                    Text(verbatim: "end \(group)")
                }
            }
        }
        let pins: PinnedScrollableViews = shape.pinned ? [.sectionHeaders, .sectionFooters] : []
        return TestApp(width: 30, height: 12) {
            ScrollView {
                if shape.titled {
                    LazyVStack(alignment: .leading, spacing: shape.spacing, pinnedViews: pins) {
                        Text("a title")
                        groups()
                    }
                } else {
                    LazyVStack(alignment: .leading, spacing: shape.spacing, pinnedViews: pins) { groups() }
                }
            }
            .environment(\.drawsContainerRowsWhole, whole)
        }
    }

    @Test("A small stack of sections draws what it drew before the step, at the top, paged, wheeled and at the end",
          arguments: Shape.allCases, [(0, 0), (1, 1), (6, 9), (25, 9)])
    func smallSectionsDrawAsBefore(_ shape: Shape, _ size: (sections: Int, rows: Int)) {
        let stepped = Self.small(shape, sections: size.sections, rows: size.rows, whole: false)
        let before = Self.small(shape, sections: size.sections, rows: size.rows, whole: true)
        func check(_ step: String) {
            #expect(
                stepped.screen.lines == before.screen.lines,
                "\(shape) \(size) \(step):\n\(stepped.screen)\n---\n\(before.screen)")
        }
        check("top")
        for page in 1...3 {
            for app in [stepped, before] { _ = app.press(.pageDown) }
            check("page \(page)")
        }
        for tick in 1...3 {
            for app in [stepped, before] { app.scroll(.down, by: 1, at: CellPoint(x: 5, y: 5)) }
            check("wheel \(tick)")
        }
        for app in [stepped, before] { _ = app.press(.end) }
        check("end")
        for page in 1...2 {
            for app in [stepped, before] { _ = app.press(.pageUp) }
            check("end, page up \(page)")
        }
        for app in [stepped, before] { _ = app.press(.home) }
        check("home")
    }

    // MARK: - A changed count draws as the new count drawn afresh

    /// `from` sections of `perSection` rows until `+` makes them `to`.
    private struct Counted: View {
        let shape: Shape
        let from: Int
        let to: Int
        let perSection: Int
        @State private var moved = false

        var body: some View {
            ScrollView {
                if shape.titled {
                    LazyVStack(alignment: .leading, spacing: shape.spacing, pinnedViews: pins) {
                        Text("a title")
                        groups
                    }
                } else {
                    LazyVStack(alignment: .leading, spacing: shape.spacing, pinnedViews: pins) { groups }
                }
            }
            .onKeyPress("+") {
                moved = true
                return .handled
            }
        }

        private var pins: PinnedScrollableViews { shape.pinned ? .sectionHeaders : [] }

        private var groups: some View {
            ForEach(0..<(moved ? to : from), id: \.self) { group in
                Section {
                    ForEach(0..<perSection, id: \.self) { Text(verbatim: "g\(group) r\($0)") }
                } header: {
                    Text(verbatim: "Group \(group)")
                }
            }
        }
    }

    @Test("A changed count of sections draws what the new count draws afresh",
          arguments: Shape.allCases, [(260, 250, 1), (250, 260, 1), (300, 280, 1), (280, 300, 1), (30, 20, 9), (20, 30, 9)])
    func changedCountDrawsAfresh(_ shape: Shape, _ counts: (from: Int, to: Int, per: Int)) {
        let moved = TestApp(width: 40, height: 12) {
            Counted(shape: shape, from: counts.from, to: counts.to, perSection: counts.per)
        }
        _ = moved.screen
        _ = moved.press(.tab)
        moved.type("+")
        let fresh = TestApp(width: 40, height: 12) {
            Counted(shape: shape, from: counts.to, to: counts.to, perSection: counts.per)
        }
        _ = fresh.press(.tab)
        fresh.type("+")
        #expect(moved.screen.contains("g0 r0"), "\(shape) \(counts) moved:\n\(moved.screen)")
        #expect(
            moved.screen.lines == fresh.screen.lines, "\(shape) \(counts):\n\(moved.screen)\n---\n\(fresh.screen)")
    }

    /// Where the stack is scrolled to before its count changes.
    enum Place: String, CaseIterable, Sendable {
        case top, middle, end

        /// Scrolls `app` there (the scroll view focused first).
        @MainActor func scroll(_ app: TestApp) {
            _ = app.press(.tab)
            switch self {
            case .top: break
            case .middle: for _ in 0..<5 { _ = app.press(.pageDown) }
            case .end: _ = app.press(.end)
            }
        }
    }

    /// H-71d: 260 sections of a row cut to 250 under a title at spacing 1 drew
    /// the headers and none of the rows, until the next change. Each section's
    /// loop, a lazy stack once the sections' loops together pass the threshold,
    /// measured its one row at no lines: its sample left the last row's gap
    /// out and its total took it off again. Every shape, scrolled to the top,
    /// the middle or the end, cut and grown, against the new count scrolled
    /// there afresh; then End and Home on both. Grown at the end, the stack
    /// keeps the row at its top, where the new count scrolled to its end is
    /// further down, so that frame is not compared. Failed before the fix in
    /// the four shapes at spacing 1, cut 260 → 250: under a title, headers
    /// and no rows; without one, Home after End landed mid-list.
    @Test("A changed count of sections, scrolled anywhere, draws what the new count draws afresh",
          arguments: Shape.allCases, [(260, 250), (300, 100), (250, 260)])
    func changedCountScrolledDrawsAfresh(_ shape: Shape, _ counts: (from: Int, to: Int)) {
        for place in Place.allCases {
            let moved = TestApp(width: 40, height: 12) {
                Counted(shape: shape, from: counts.from, to: counts.to, perSection: 1)
            }
            place.scroll(moved)
            moved.type("+")
            let fresh = TestApp(width: 40, height: 12) {
                Counted(shape: shape, from: counts.to, to: counts.to, perSection: 1)
            }
            // Scrolled there, and nothing written: a write at the end is
            // `writeAtTheEndKeepsTheEnd`'s.
            place.scroll(fresh)
            func check(_ step: String) {
                #expect(
                    moved.screen.lines == fresh.screen.lines,
                    "\(shape) \(counts) \(place) \(step):\n\(moved.screen)\n---\n\(fresh.screen)")
            }
            // Every header drawn has its row below it, wherever the frame is
            // (but one pinned over the top line, whose row may be off it).
            let lines = moved.screen.lines.map { $0.trimmingCharacters(in: .whitespaces) }
            for (index, line) in lines.enumerated().dropLast(2)
            where line.hasPrefix("Group ") && !(shape.pinned && index == 0) {
                let group = line.dropFirst(6).prefix { $0.isNumber }
                #expect(
                    lines[index + 1 + shape.spacing].hasPrefix("g\(group) r0"),
                    "\(shape) \(counts) \(place), a header without its row:\n\(moved.screen)")
            }
            if !(place == .end && counts.to > counts.from) { check("changed") }
            for app in [moved, fresh] { _ = app.press(.end) }
            check("end")
            for app in [moved, fresh] { _ = app.press(.home) }
            check("home")
        }
    }

    /// H-71e: 250 sections of a row at spacing 1, scrolled to the end, drew
    /// their end a line down after a `@State` write that changes nothing they
    /// draw (two lines at spacing 2), the last row gone, until the next End.
    /// At the end the viewport's top lay in the gap below a section, and the
    /// column anchored that section and handed it a top past its end: it drew
    /// its row on that line and reported itself a line taller, and the write's
    /// frame handed it that place again. Failed before the fix at spacing 1.
    @Test("A write at the end of a stack of sections keeps the end", arguments: Shape.allCases)
    func writeAtTheEndKeepsTheEnd(_ shape: Shape) {
        let app = TestApp(width: 40, height: 12) {
            Counted(shape: shape, from: 250, to: 250, perSection: 1)
        }
        Place.end.scroll(app)
        let before = app.screen.lines
        #expect(Self.endsWithLastRow(app, "g249 r0"), "\(shape), End:\n\(app.screen)")
        app.type("+")
        #expect(app.screen.lines == before, "\(shape):\n\(app.screen)")
    }

    /// Whether `app`'s bottom line is the row `last`: the end drawn where it
    /// is, not only alike in two stacks that both miss it.
    private static func endsWithLastRow(_ app: TestApp, _ last: String) -> Bool {
        app.screen.lines.last?.trimmingCharacters(in: .whitespaces).hasPrefix(last) == true
    }

    // MARK: - The end, kept across a write, a resize and an insert

    /// `count` sections of `perSection` rows, in `shape` at `spacing`, with a
    /// section `-1` above them once `^` inserts it, or from the start
    /// (`startsInserted`); `+` writes a state that changes nothing drawn.
    private struct AtTheEnd: View {
        let shape: Shape
        let spacing: Int
        let count: Int
        let perSection: Int
        let startsInserted: Bool
        @State private var inserted: Bool?
        @State private var written = false

        var body: some View {
            ScrollView {
                if shape.titled {
                    LazyVStack(alignment: .leading, spacing: spacing, pinnedViews: pins) {
                        Text("a title")
                        groups
                    }
                } else {
                    LazyVStack(alignment: .leading, spacing: spacing, pinnedViews: pins) { groups }
                }
            }
            .onKeyPress("+") {
                written.toggle()
                return .handled
            }
            .onKeyPress("^") {
                inserted = true
                return .handled
            }
        }

        private var pins: PinnedScrollableViews { shape.pinned ? .sectionHeaders : [] }

        private var groups: some View {
            ForEach(((inserted ?? startsInserted) ? -1 : 0)..<count, id: \.self) { group in
                Section {
                    ForEach(0..<perSection, id: \.self) { Text(verbatim: "g\(group) r\($0)") }
                } header: {
                    Text(verbatim: "Group \(group)")
                }
            }
        }
    }

    /// What is done to a stack scrolled to its end.
    enum StepAtTheEnd: String, CaseIterable, Sendable {
        /// A `@State` write that changes nothing drawn.
        case write
        /// The terminal made narrower and taller: the offset at the end is
        /// past the new end, and clamped to it.
        case resize
        /// A section inserted above every other, the rows on screen held.
        case insert
    }

    /// H-71e's variants: spacing 0, 1 and 2, sections of one row and of two,
    /// 50, 250 and 1,000 of them (their loops together within the threshold,
    /// past it, and the sections themselves past it), in every shape (pinned
    /// or not, titled or not), scrolled to the end and then written, resized
    /// or inserted into at the top: that frame, and a write after it, against
    /// a fresh stack of the result scrolled to its end. Failed before the fix
    /// wherever the sections are pulled (their loops together past the
    /// threshold) at a spacing that put a gap on the end's top line.
    @Test("The end of a stack of sections stays the end across a write, a resize and an insert at the top",
          arguments: Shape.allCases.filter { $0.spacing == 0 }, [0, 1, 2])
    func endStaysTheEnd(_ shape: Shape, _ spacing: Int) {
        for count in [50, 250, 1_000] {
            for perSection in [1, 2] {
                for step in StepAtTheEnd.allCases {
                    Self.checkEnd(shape, spacing: spacing, count: count, perSection: perSection, step: step)
                }
            }
        }
    }

    /// One of ``endStaysTheEnd(_:_:)``'s cases.
    private static func checkEnd(_ shape: Shape, spacing: Int, count: Int, perSection: Int, step: StepAtTheEnd) {
        let app = TestApp(width: 40, height: 12) {
            AtTheEnd(shape: shape, spacing: spacing, count: count, perSection: perSection, startsInserted: false)
        }
        Place.end.scroll(app)
        let (width, height) = step == .resize ? (36, 14) : (40, 12)
        switch step {
        case .write: app.type("+")
        case .resize: app.resize(width: width, height: height)
        case .insert: app.type("^")
        }
        let fresh = TestApp(width: width, height: height) {
            AtTheEnd(
                shape: shape, spacing: spacing, count: count, perSection: perSection, startsInserted: step == .insert)
        }
        Place.end.scroll(fresh)
        let label = "\(shape) spacing \(spacing), \(count) x \(perSection), \(step)"
        #expect(Self.endsWithLastRow(fresh, "g\(count - 1) r\(perSection - 1)"), "\(label), fresh:\n\(fresh.screen)")
        // Found by H-71e, not fixed (and so before it, and without sections:
        // `LazyVStack { Text(title); ForEach(rows) }`, anywhere in the list):
        // under a title, rows inserted at the top of the loop are not held,
        // and the rows on screen move down by the lines inserted. Measured
        // held at 250 sections, whose loops together pass the threshold, so
        // that each section is pulled.
        withKnownIssue("under a title, an insert at the top of the loop is not held") {
            #expect(app.screen.lines == fresh.screen.lines, "\(label):\n\(app.screen)\n---\n\(fresh.screen)")
            app.type("+")
            #expect(
                app.screen.lines == fresh.screen.lines, "\(label), then a write:\n\(app.screen)\n---\n\(fresh.screen)")
        } when: {
            step == .insert && shape.titled && count != 250
        }
    }
}
