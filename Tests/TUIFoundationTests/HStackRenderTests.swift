//  🖥️ TUI — A Terminal UI framework for Swift
//  HStackRenderTests.swift
//
//  Buffer-level render audit for HStack.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("HStack rendering")
struct HStackRenderTests {

    private func ctx(width: Int = 30, height: Int = 8) -> RenderContext {
        RenderContext(availableWidth: width, availableHeight: height, tuiContext: TUIContext()).isolatingRenderCache()
    }

    // MARK: - Default arrangement

    @Test("Arranges children left-to-right on one row with default spacing 1")
    func defaultArrangement() throws {
        let buffer = renderToBuffer(
            HStack {
                Text("A")
                Text("B")
                Text("C")
            },
            context: ctx()
        )
        try #require(buffer.lines.count == 1, "Single-line children stay on one row")
        // Default spacing is 1 character between each pair: "A B C".
        #expect(buffer.lines[0].stripped == "A B C")
        #expect(buffer.width == 5)
    }

    @Test("Zero spacing places children flush together")
    func zeroSpacing() {
        let buffer = renderToBuffer(
            HStack(spacing: 0) {
                Text("A")
                Text("B")
            },
            context: ctx()
        )
        #expect(buffer.lines[0].stripped == "AB")
        #expect(buffer.width == 2)
    }

    @Test("Explicit spacing widens the gaps")
    func explicitSpacing() {
        let buffer = renderToBuffer(
            HStack(spacing: 3) {
                Text("A")
                Text("B")
            },
            context: ctx()
        )
        #expect(buffer.lines[0].stripped == "A   B")
    }

    // MARK: - Empty

    @Test("Empty HStack renders nothing")
    func emptyStack() {
        let buffer = renderToBuffer(HStack {}, context: ctx())
        #expect(buffer.height == 0)
        #expect(buffer.lines.isEmpty)
    }

    @Test("A single child renders as itself")
    func singleChild() throws {
        let buffer = renderToBuffer(HStack { Text("solo") }, context: ctx())
        try #require(buffer.lines.count == 1)
        #expect(buffer.lines[0].stripped == "solo")
    }

    // MARK: - Spacer

    @Test("Spacer pushes siblings to the left and right edges")
    func spacerExpands() throws {
        let buffer = renderToBuffer(
            HStack {
                Text("L")
                Spacer()
                Text("R")
            },
            context: ctx(width: 20, height: 3)
        )
        try #require(buffer.lines.count == 1)
        let line = buffer.lines[0].stripped
        #expect(line.hasPrefix("L"), "Left item flush left")
        #expect(line.hasSuffix("R"), "Right item flush right")
        #expect(line.strippedLength == 20, "Row fills the full available width")
        // The interior between L and R is all spaces.
        let interior = String(line.dropFirst().dropLast())
        #expect(interior.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    // MARK: - Vertical alignment

    @Test("Top alignment puts a short child on the first row of a taller row")
    func topAlignment() throws {
        let buffer = renderToBuffer(
            HStack(alignment: .top, spacing: 1) {
                VStack { Text("a"); Text("b") }
                Text("X")
            },
            context: ctx(width: 10, height: 3)
        )
        try #require(buffer.lines.count == 2, "Row is as tall as the tallest child (2 lines)")
        #expect(buffer.lines[0].stripped == "a X", "X sits on the top row")
        #expect(buffer.lines[1].stripped.hasPrefix("b"))
        // The X column on the second row is blank (no second line for X).
        #expect(buffer.lines[1].stripped.trimmingCharacters(in: .whitespaces) == "b")
    }

    @Test("Center and bottom alignment position a short child within a taller row")
    func centerAndBottomAlignment() {
        // A 3-row sibling next to a 1-row Text. The single "X" should sit on the
        // top / middle / bottom row per the alignment. (Previously every
        // alignment top-pinned the X — `.center` and `.bottom` were ignored.)
        func rows(_ a: VerticalAlignment) -> [String] {
            renderToBuffer(
                HStack(alignment: a, spacing: 1) {
                    VStack(alignment: .leading) { Text("a"); Text("b"); Text("c") }
                    Text("X")
                },
                context: ctx(width: 10, height: 4)
            ).lines.map { $0.stripped }
        }
        // The X column occupies its cell on every row (blank where X is absent),
        // so non-X rows carry trailing spaces — pin them exactly.
        #expect(rows(.top) == ["a X", "b  ", "c  "], "top: X on the first row")
        #expect(rows(.center) == ["a  ", "b X", "c  "], "center: X on the middle row")
        #expect(rows(.bottom) == ["a  ", "b  ", "c X"], "bottom: X on the last row")
    }

    // MARK: - Narrow width (truncation, no overflow)

    @Test("Children squeezed past the width truncate instead of overflowing")
    func narrowTruncation() {
        let buffer = renderToBuffer(
            HStack(spacing: 1) {
                Text("AAAA")
                Text("BBBB")
                Text("CCCC")
            },
            context: ctx(width: 8, height: 2)
        )
        #expect(buffer.width <= 8, "Assembled row must not exceed the available width")
        for line in buffer.lines {
            #expect(line.strippedLength <= 8, "No line overflows the width")
        }
    }

    // MARK: - Multi-item

    @Test("All items render in order across the row")
    func manyItems() throws {
        let buffer = renderToBuffer(
            HStack(spacing: 1) {
                ForEach(0..<4) { Text("\($0)") }
            },
            context: ctx(width: 30, height: 2)
        )
        try #require(buffer.lines.count == 1)
        #expect(buffer.lines[0].stripped == "0 1 2 3")
    }

    // MARK: - Overflow degrades gracefully (regression)

    @Test("A spaced row wider than its space clips trailing columns, never blanks")
    func overflowingSpacedRowClipsNotBlanks() {
        // 12 single-cell columns with spacing 1 want 23 cells. In a 4-cell width
        // the inter-column gaps alone exceed it — reserving every gap first would
        // starve all columns to zero and render blank. The leading columns must
        // stay visible instead.
        let buffer = renderToBuffer(
            HStack(spacing: 1) {
                ForEach(0..<12) { Text("\($0 % 10)") }
            },
            context: ctx(width: 4, height: 2)
        )
        #expect(!buffer.lines.allSatisfy { $0.stripped.trimmingCharacters(in: .whitespaces).isEmpty },
                "Overflowing spaced row must not render blank")
        #expect(buffer.lines.first?.stripped.hasPrefix("0") == true, "Leading column stays visible")
        #expect(buffer.width <= 4, "Never overflows the width it was given")
    }

    // MARK: - Filtered (empty) children

    @Test("A leading empty child claims no spacing slot")
    func leadingEmptyChildClaimsNoSpacing() throws {
        // `EmptyView` is NOT a ChildViewProvider, so unlike `if false { … }` it
        // survives child resolution and renders an empty buffer at index 0 —
        // which is exactly the case that used to buy a spacing slot it never
        // earned, indenting the whole row.
        let buffer = renderToBuffer(
            HStack(spacing: 2) {
                EmptyView()
                Text("Hi")
            }, context: ctx())
        try #require(buffer.lines.count == 1)
        #expect(buffer.lines[0].stripped == "Hi")
        #expect(buffer.width == 2)
    }

    @Test("An interior empty child claims no spacing slot either")
    func interiorEmptyChildClaimsNoSpacing() {
        // Passes before and after: the guard rail that stops the fix being
        // over-applied to the already-correct interior case.
        let buffer = renderToBuffer(
            HStack(spacing: 2) {
                Text("A")
                EmptyView()
                Text("B")
            }, context: ctx())
        #expect(buffer.lines[0].stripped == "A  B")
    }

    // MARK: - A row of no height

    // SwiftUI's `HStack { Spacer() }` is no rows tall and as wide as it is
    // given (`Tools/SwiftUIProbes/ViewThatFits widths and spacers across the
    // axis (H-62, H-64)/fits.out`). Hunt 11-20, LAYOUT-8.

    @Test("A row of only a spacer is no rows tall and as wide as it is given")
    func spacerOnlyRowHasNoHeight() {
        let size = measureChild(HStack { Spacer() }, proposal: .unspecified, context: ctx(width: 20, height: 5))
        #expect(size.height == 0, "got \(size.width)x\(size.height)")
        #expect(size.width == 20 && size.isWidthFlexible)
        let buffer = renderToBuffer(HStack { Spacer() }, context: ctx(width: 20, height: 5))
        #expect(buffer.lines.isEmpty, "got \(buffer.lines.map(\.stripped))")
        #expect(buffer.width == 20, "the row still declares its width")
    }

    @Test("A spacer-only row between two texts adds no blank line, and still fills the column")
    func spacerOnlyRowInAColumn() throws {
        let column = VStack(spacing: 0) {
            Text("a")
            HStack { Spacer() }
            Text("b")
        }
        let buffer = renderToBuffer(column, context: ctx(width: 20, height: 5))
        try #require(buffer.lines.count == 2, "got \(buffer.lines.map(\.stripped))")
        #expect(buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) } == ["a", "b"])
        // Centred in the full width, as SwiftUI centres them (x 14.49 of 30).
        #expect(buffer.width == 20)
        #expect(buffer.lines[0].stripped == String(repeating: " ", count: 9) + "a" + String(repeating: " ", count: 10))
        let size = measureChild(column, proposal: .unspecified, context: ctx(width: 20, height: 5))
        #expect(size.height == 2 && size.width == 20, "got \(size.width)x\(size.height)")
    }

    @Test("A column of only a spacer-only row declares the width it fills")
    func columnOfASpacerOnlyRow() {
        let buffer = renderToBuffer(VStack { HStack { Spacer() } }, context: ctx(width: 12, height: 5))
        #expect(buffer.lines.isEmpty)
        #expect(buffer.width == 12, "a column holding the idiom is as wide as it")
        // …so a row beside it still puts its trailing view at the edge.
        let row = renderToBuffer(
            HStack(spacing: 0) { VStack { HStack { Spacer() } }; Text("R") }, context: ctx(width: 10, height: 5))
        #expect(row.lines.map(\.stripped) == ["         R"])
    }

    @Test("A spacer-only row inside a row keeps its columns")
    func spacerOnlyRowInsideARow() {
        let buffer = renderToBuffer(
            HStack(spacing: 0) { Text("a"); HStack { Spacer() }; Text("b") }, context: ctx(width: 10, height: 5))
        #expect(buffer.lines.map(\.stripped) == ["a        b"])
    }

    @Test("A lazy row of only a spacer is no rows tall either")
    func lazySpacerOnlyRow() {
        let buffer = renderToBuffer(
            VStack(spacing: 0) { Text("a"); LazyHStack { Spacer() }; Text("b") }, context: ctx(width: 20, height: 5))
        #expect(buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) } == ["a", "b"])
    }

    // Only a row of spacers loses its row. A `Color` has no height of its own
    // either, but it takes what it is given, and a row of them keeps the one
    // row it always drew (`MaskModifierTests.nestedAlphas` masks with one).

    @Test("A row of a colour is still one row")
    func colourRowKeepsItsRow() {
        for row in [AnyView(HStack { Color.red }), AnyView(HStack(spacing: 0) { Color.red.frame(width: 2); Spacer() })] {
            let size = measureChild(row, proposal: .unspecified, context: ctx(width: 6, height: 5))
            #expect(size.height == 1, "got \(size.width)x\(size.height)")
        }
        let column = VStack(spacing: 0) { Text("a"); HStack { Color.red }; Text("b") }
        let buffer = renderToBuffer(column, context: ctx(width: 6, height: 3))
        #expect(buffer.lines.count == 3, "got \(buffer.lines.map(\.stripped))")
        let lazy = renderToBuffer(
            VStack(spacing: 0) { Text("a"); LazyHStack { Color.red.frame(width: 2); Spacer() }; Text("b") },
            context: ctx(width: 6, height: 3))
        #expect(lazy.lines.count == 3, "got \(lazy.lines.map(\.stripped))")
    }

    @Test("A row of spacers and a text is one row")
    func spacersAndTextIsOneRow() {
        let row = HStack { Spacer(); Text("x"); Spacer() }
        let size = measureChild(row, proposal: .unspecified, context: ctx(width: 9, height: 5))
        #expect(size.height == 1 && size.width == 9, "got \(size.width)x\(size.height)")
        #expect(renderToBuffer(row, context: ctx(width: 9, height: 5)).lines.map(\.stripped) == ["    x    "])
    }

    @Test("A spacer beside a view that draws nothing is still no rows tall")
    func spacerBesideNothingHasNoHeight() {
        let shown = false
        let row = HStack {
            Spacer()
            EmptyView()
            if shown { Text("x") }
        }
        let size = measureChild(row, proposal: .unspecified, context: ctx(width: 12, height: 5))
        #expect(size.height == 0, "got \(size.width)x\(size.height)")
        let buffer = renderToBuffer(VStack(spacing: 0) { Text("a"); row; Text("b") }, context: ctx(width: 12, height: 5))
        #expect(buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) } == ["a", "b"])
    }
}
