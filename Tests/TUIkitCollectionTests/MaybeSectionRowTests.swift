//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MaybeSectionRowTests.swift
//
//  A loop's row that is a section only some of the time — an `if` around a
//  `Section`, written in the loop or as the body of a view of the app's own,
//  or an `if`/`else` with a section in an arm — in a lazy stack: drawn whole,
//  as a row that always is a section is, so its section pins as the stack's
//  own beside a sibling too, and the stack builds only the rows it draws.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitLists
@testable import TUIkitTestSupport
@testable import TUIkitView

/// How many rows of the loop were built.
@MainActor
private final class Built {
    var rows = 0
    func note() { rows += 1 }
}

/// Group `group` written bare: its header, then one to three rows.
@MainActor
private func bareGroup(_ group: Int) -> some View {
    Section {
        ForEach(0..<(group % 3 + 1), id: \.self) { Text("row \(group).\($0)") }
    } header: {
        Text("Header \(group)")
    }
}

/// Whether group `group` is drawn: every third is not.
private func isShown(_ group: Int) -> Bool { !group.isMultiple(of: 3) }

/// A section of the app's own under an `if`, drawing nothing for every third
/// group — the shape the D1S lane's review reported, on 2de94b626.
private struct MaybeGroupView: View {
    let group: Int
    let built: Built?

    var body: some View {
        // `let _ =`, not `_ =`: a view builder takes no assignment.
        // swiftlint:disable:next redundant_discardable_let
        let _ = built?.note()
        if isShown(group) {
            Section {
                ForEach(0..<(group % 3 + 1), id: \.self) { Text("row \(group).\($0)") }
            } header: {
                Text("Header \(group)")
            }
        }
    }
}

/// A view of the app's own whose body is an `if`/`else` of a group and a
/// note, or of a group and nothing: one child, drawn whole, as such a view
/// always was (decisions D1S, B-D1S-6) — what a loop's row that is a section
/// some of the time is drawn as now.
private struct GroupOrNoteView: View {
    let group: Int
    let note: Bool

    var body: some View {
        if isShown(group) {
            bareGroup(group)
        } else if note {
            Text("none \(group)")
        } else {
            EmptyView()
        }
    }
}

/// The shapes of a loop's row that is a section some of the time.
enum MaybeSectionRowShape: CaseIterable, Sendable {
    /// `ForEach(groups) { MaybeGroupView(group: $0) }`: a view of the app's
    /// own whose body is an `if` around a section.
    case optionalInAView
    /// `ForEach(groups) { if shown { Section … } }`.
    case optional
    /// `ForEach(groups) { if shown { Section … } else { EmptyView() } }`.
    case eitherOrNothing
    /// `ForEach(groups) { if shown { Section … } else { Text(…) } }`.
    case eitherOrANote
}

/// Where the loop is: its stack's whole content or beside a line of its own,
/// in a stack that pins its headers or not — and once with a line between
/// every two of the stack's views, which an empty row must not be given.
enum MaybeSectionRowLayout: CaseIterable, Sendable {
    case alone, besideASibling, pinnedAlone, pinnedBesideASibling, pinnedSpacedBesideASibling

    var pinned: Bool { self != .alone && self != .besideASibling }
    var sibling: Bool { self != .alone && self != .pinnedAlone }
    var spacing: Int { self == .pinnedSpacedBesideASibling ? 1 : 0 }
}

@MainActor
@Suite("A loop's row that is a section some of the time, in a lazy stack")
struct MaybeSectionRowTests {
    /// `rows` in a lazy stack that pins its headers or not, after a line of
    /// its own or as its whole content, in a scroll view eight lines tall at
    /// `box`'s position. The loop is the stack's own child, not under a
    /// `switch`'s arms, which would put its sections a step further from the
    /// stack than its own.
    @ViewBuilder
    private func page(
        _ box: PinnedPositionBox, _ layout: MaybeSectionRowLayout, @ViewBuilder rows: () -> some View
    ) -> some View {
        let pins: PinnedScrollableViews = layout.pinned ? .sectionHeaders : []
        let position = Binding(get: { box.position }, set: { box.position = $0 })
        if layout.sibling {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: layout.spacing, pinnedViews: pins) {
                    Text("Top")
                    rows()
                }
            }
            .scrollPosition(position)
            .scrollIndicators(.hidden)
            .frame(height: 8)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: layout.spacing, pinnedViews: pins) { rows() }
            }
            .scrollPosition(position)
            .scrollIndicators(.hidden)
            .frame(height: 8)
        }
    }

    /// The screens `view` draws scrolled through `box` to each of `offsets`,
    /// with `between` run before each.
    private func screens(
        of view: some View, _ box: PinnedPositionBox, at offsets: [Int], between: () -> Void = {}
    ) -> [[String]] {
        let (tui, focusManager) = (TUIContext(), FocusManager())
        return offsets.map { offset in
            box.position.scrollTo(y: offset)
            between()
            return scrollFrame(view, tui: tui, focusManager: focusManager)
        }
    }

    /// The screens a loop of `count` groups in `shape` draws, as
    /// ``screens(of:_:at:between:)``.
    private func screens(
        _ shape: MaybeSectionRowShape, _ layout: MaybeSectionRowLayout, count: Int, built: Built?,
        at offsets: [Int], between: () -> Void = {}
    ) -> [[String]] {
        let box = PinnedPositionBox()
        switch shape {
        case .optionalInAView:
            let view = page(box, layout) {
                ForEach(0..<count, id: \.self) { MaybeGroupView(group: $0, built: built) }
            }
            return screens(of: view, box, at: offsets, between: between)
        case .optional:
            let view = page(box, layout) {
                ForEach(0..<count, id: \.self) { group in
                    // swiftlint:disable:next redundant_discardable_let
                    let _ = built?.note()
                    if isShown(group) { bareGroup(group) }
                }
            }
            return screens(of: view, box, at: offsets, between: between)
        case .eitherOrNothing:
            let view = page(box, layout) {
                ForEach(0..<count, id: \.self) { group in
                    // swiftlint:disable:next redundant_discardable_let
                    let _ = built?.note()
                    if isShown(group) { bareGroup(group) } else { EmptyView() }
                }
            }
            return screens(of: view, box, at: offsets, between: between)
        case .eitherOrANote:
            let view = page(box, layout) {
                ForEach(0..<count, id: \.self) { group in
                    // swiftlint:disable:next redundant_discardable_let
                    let _ = built?.note()
                    if isShown(group) { bareGroup(group) } else { Text("none \(group)") }
                }
            }
            return screens(of: view, box, at: offsets, between: between)
        }
    }

    /// What a loop in `shape` draws as: the same rows as views of the app's
    /// own whose body is an `if`/`else`, which are drawn whole — the same
    /// number of rows, empty ones included, so a lazy stack that places rows
    /// it has not drawn by an estimate estimates them alike.
    private func expectedScreens(
        _ shape: MaybeSectionRowShape, _ layout: MaybeSectionRowLayout, count: Int, at offsets: [Int]
    ) -> [[String]] {
        let box = PinnedPositionBox()
        let note = shape == .eitherOrANote
        let view = page(box, layout) {
            ForEach(0..<count, id: \.self) { GroupOrNoteView(group: $0, note: note) }
        }
        return screens(of: view, box, at: offsets)
    }

    @Test(
        "Such a row draws and pins as a view of the app's own drawn whole",
        arguments: MaybeSectionRowShape.allCases, MaybeSectionRowLayout.allCases)
    func drawsAsExpected(shape: MaybeSectionRowShape, layout: MaybeSectionRowLayout) {
        let offsets = [0, 1, 2, 3, 7, 50, 51, 52, 58, 59, 400, 0]
        let drawn = screens(shape, layout, count: 300, built: nil, at: offsets)
        let wanted = expectedScreens(shape, layout, count: 300, at: offsets)
        // Pinned, a section's header covers whatever of its rows is at the
        // top; not pinned, some screen starts on a row.
        let startOnARow = wanted.filter { $0.first?.hasPrefix("row ") == true }.count
        #expect(
            layout.pinned ? startOnARow == 0 : startOnARow > 0,
            "precondition, \(shape) \(layout): \(startOnARow) screens start on a row: \(wanted)")
        let differing = zip(offsets, zip(drawn, wanted)).filter { $1.0 != $1.1 }.map { offset, screens in
            "offset \(offset): \(screens.0) vs \(screens.1)"
        }
        #expect(
            differing.isEmpty, "\(shape) \(layout): \(differing.count) screens differ: \(differing.prefix(2))")
    }

    @Test(
        "A lazy stack over a thousand such rows builds only the rows it draws",
        arguments: MaybeSectionRowShape.allCases, MaybeSectionRowLayout.allCases)
    func staysLazy(shape: MaybeSectionRowShape, layout: MaybeSectionRowLayout) {
        let built = Built()
        // Counted afresh before each frame, so what is left is the second's,
        // drawn at line 50: the first draws the top.
        let drawn = screens(shape, layout, count: 1_000, built: built, at: [0, 50]) { built.rows = 0 }
        #expect(drawn.last?.contains { $0.hasPrefix("row ") } == true, "precondition: rows drawn at line 50: \(drawn)")
        #expect(built.rows < 100, "\(shape) \(layout): built \(built.rows) rows to draw a screen")
    }

    /// A `List` reads such a row as the section it is while it is one — the
    /// walk that keeps every section whole was left as it was.
    @Test("To a List, such a row is its section while it is one, and nothing while it is not")
    func listReadsTheSections() {
        let fixture = ListSectionEditingFixture()
        fixture.render(
            List(selection: .constant(Int?.none)) {
                ForEach(0..<3, id: \.self) { MaybeGroupView(group: $0, built: nil) }
            }
            .frame(height: 10))
        let handler = fixture.handler(Int.self)
        let ids = (0..<(handler?.itemCount ?? 0)).map { handler?.id(at: $0) }
        // Group 0 draws nothing; 1 and 2 their headers, then their rows.
        #expect(ids == [nil, 0, 1, nil, 0, 1, 2], "\(ids)")
    }
}
