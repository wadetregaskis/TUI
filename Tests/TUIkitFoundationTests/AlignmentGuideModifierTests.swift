//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AlignmentGuideModifierTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkitFoundation
@testable import TUIkitTestSupport

/// The line a decimal point sits on — the Layout page's own custom alignment,
/// reproduced here because a `ForEach` over it is what regressed.
private enum DecimalPointID: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> Double { 0 }
}

extension HorizontalAlignment {
    fileprivate static let decimalPoint = Self(DecimalPointID.self)
}

/// `.alignmentGuide` moves the line a container aligns a child on. The property
/// that makes it worth having — and the one every case here turns on — is that
/// a container can end up **wider (or taller) than its largest child**, because
/// a child hanging off the alignment line pushes its siblings across.
///
/// This has to work in every aligning container at once. A modifier that is live
/// in `VStack` and inert in `LazyVStack` is worse than one that does not exist:
/// `.anchorPosition` shipped that way and 3130 green tests missed it — running
/// the app caught it. So the suite walks eager stacks, lazy stacks, the viewport
/// window, `ZStack`, `.frame` and `.overlay`.
@MainActor
@Suite("alignmentGuide")
struct AlignmentGuideModifierTests {

    /// The leading edges of each line, which is what a guide actually moves.
    private func indents(_ buffer: FrameBuffer) -> [Int] {
        buffer.lines.map { line in
            let stripped = line.stripped
            return stripped.count - stripped.drop(while: { $0 == " " }).count
        }
    }

    /// Numbers whose whole parts differ in width, so a decimal-point guide is
    /// visibly not the same as aligning on either edge. `Hashable` because that
    /// is what routes a `ForEach` row through the element-keyed memo.
    private struct Amount: Hashable {
        let whole: String
        let fraction: String
    }

    private static let amounts = [
        Amount(whole: "7", fraction: "50"),
        Amount(whole: "1240", fraction: "05"),
        Amount(whole: "96", fraction: "125"),
    ]

    // MARK: - The basic shape

    @Test("A guide travels out through padding, evaluated at the content's own size")
    func guideThroughPadding() {
        // SwiftUI translates a guide as each wrapper changes the geometry, and
        // padding is one that knows by how much. The closure still sees the
        // CONTENT's dimensions — `$0.width` is "aaaa"'s 4, not the padded 6 —
        // and the answer is moved by the leading inset: 4 + 1, so "bb" lines
        // up under the cell after "aaaa".
        let wrapped = indents(renderToBuffer(
            VStack(alignment: .leading) {
                Text("aaaa").alignmentGuide(.leading) { Double($0.width) }.padding(.horizontal, 1)
                Text("bb")
            },
            context: makeBareRenderContext(width: 20, height: 4)))
        #expect(wrapped == [1, 5])
    }

    @Test("A guide under a wrapper that does not translate it stops there, deliberately")
    func guideUnderABorderIsInert() {
        // PINS A LIMITATION. A border also moves its content, but nothing here
        // translates a guide through it, and a wrong position is worse than a
        // documented no-op: the guide is not read at all.
        let wrapped = indents(renderToBuffer(
            VStack(alignment: .leading) {
                Text("aaaa").alignmentGuide(.leading) { Double($0.width) }.border(.red)
                Text("bb")
            },
            context: makeBareRenderContext(width: 20, height: 4)))
        let plain = indents(renderToBuffer(
            VStack(alignment: .leading) {
                Text("aaaa").border(.red)
                Text("bb")
            },
            context: makeBareRenderContext(width: 20, height: 4)))
        #expect(wrapped == plain)
    }

    @Test("A hanging guide widens the column and indents its siblings")
    func hangingGuideWidensTheColumn() {
        // "•" declares its guide at its own TRAILING edge, so the leading
        // alignment line falls one cell to its right — and everything else has
        // to move over to meet it.
        let buffer = renderToBuffer(
            VStack(alignment: .leading) {
                Text("•").alignmentGuide(.leading) { $0[.trailing] }
                Text("item")
            },
            context: makeRenderContext(width: 30, height: 4))

        #expect(indents(buffer) == [0, 1])
        // Wider than "item" alone: the whole point of the mechanism.
        #expect(buffer.width == 5)
    }

    @Test("Without the guide the same stack is flush — the control")
    func withoutTheGuideNothingMoves() {
        let buffer = renderToBuffer(
            VStack(alignment: .leading) {
                Text("•")
                Text("item")
            },
            context: makeRenderContext(width: 30, height: 4))

        #expect(indents(buffer) == [0, 0])
        #expect(buffer.width == 4)
    }

    @Test("A guide that is not a coordinate renders instead of trapping")
    func nonCoordinateGuideRenders() {
        // `{ d in Double(d.width) / Double(d.height) }` on a zero-height child
        // is how an app reaches `∞` without writing it; `.infinity` is the
        // blunt form of the same thing. Both used to trap inside the MEASURE
        // pass — `_VStackCore.sizeThatFits` — so there was never a buffer to
        // assert on, in this suite or in the app.
        //
        // Each is a logic error on a view with a width and a height, so each
        // is reported (`AlignmentGuideTests` pins the reports); collected
        // here, or a debug build would stop at the assertion.
        for guide in [Double.infinity, -.infinity, .nan, 1e300] {
            let (buffer, reports) = collectingGuideErrors {
                renderToBuffer(
                    VStack(alignment: .leading) {
                        Text("•").alignmentGuide(.leading) { _ in guide }
                        Text("item")
                    },
                    context: makeRenderContext(width: 30, height: 4))
            }

            #expect(reports.count == 1, "guide \(guide) -> \(reports)")
            #expect(buffer.lines.count == 2, "guide \(guide) -> \(buffer.lines)")
            #expect(buffer.width <= 30, "guide \(guide) -> width \(buffer.width)")
            #expect(indents(buffer).allSatisfy { $0 >= 0 })
        }

        // The vertical twin, through an HStack.
        let (horizontal, reports) = collectingGuideErrors {
            renderToBuffer(
                HStack(alignment: .top) {
                    Text("a").alignmentGuide(.top) { _ in .infinity }
                    Text("b")
                },
                context: makeRenderContext(width: 30, height: 4))
        }
        #expect(reports.count == 1, "\(reports)")
        #expect(!horizontal.lines.isEmpty)
    }

    @Test("A guide on a lazy stack's row is not silently inert")
    func lazyStackHonoursTheGuide() {
        // The `.anchorPosition` trap, pinned: `LazyVStack` is a different render
        // path through the same core, and it would happily have ignored this.
        let buffer = renderToBuffer(
            LazyVStack(alignment: .leading) {
                Text("•").alignmentGuide(.leading) { $0[.trailing] }
                Text("item")
            },
            context: makeRenderContext(width: 30, height: 4))

        #expect(indents(buffer) == [0, 1])
    }

    @Test("A ForEach row keeps its guide, Equatable element or not")
    func forEachRowsHonourTheGuide() {
        // `ForEach` wraps a row in the element-keyed value memo when the element
        // is `Equatable`, and the memo is `Renderable` — opaque to the stack's
        // guide query. Every row of the Layout page's decimal-point column read
        // back as unguided and the whole column drew flush left, under a caption
        // explaining that it lines up on the point.
        //
        // `Amount` is `Hashable` (so `Equatable`) on purpose: that is the branch
        // that broke. The `Int` control below takes the same branch and is here
        // to prove the assertion is about the guide, not the element type.
        let guided = renderToBuffer(
            VStack(alignment: .decimalPoint, spacing: 0) {
                ForEach(Self.amounts, id: \.self) { amount in
                    Text("\(amount.whole).\(amount.fraction)")
                        .alignmentGuide(.decimalPoint) { _ in Double(amount.whole.count) }
                }
            },
            context: makeRenderContext(width: 30, height: 4))

        // Widest whole part is 4 ("1240"), so each row is indented by the
        // difference — the point lands in one column for all three.
        #expect(indents(guided) == [3, 0, 2])

        let unguided = renderToBuffer(
            VStack(alignment: .decimalPoint, spacing: 0) {
                ForEach(Self.amounts, id: \.self) { amount in
                    Text("\(amount.whole).\(amount.fraction)")
                }
            },
            context: makeRenderContext(width: 30, height: 4))
        #expect(indents(unguided) == [0, 0, 0], "the control: no guide, no movement")
    }

    @Test("A guide survives the scroll viewport window")
    func viewportWindowHonoursTheGuide() {
        // The third VStack render path: a lazy stack inside a ScrollView renders
        // only the rows meeting the viewport, into a full-height buffer.
        var context = makeRenderContext(width: 30, height: 4)
        context.environment.scrollContentWindow = ScrollContentWindow(
            offset: 0, viewportHeight: 4)
        let buffer = renderToBuffer(
            LazyVStack(alignment: .leading) {
                Text("•").alignmentGuide(.leading) { $0[.trailing] }
                Text("item")
            },
            context: context)

        #expect(indents(buffer).prefix(2) == [0, 1])
    }

    // MARK: - Vertical

    @Test("A vertical guide grows the row and offsets a column")
    func verticalGuideInAnHStack() {
        // The left column declares its guide on its SECOND row, so that row is
        // what lines up with the right column's first — and the row has to grow
        // to three to hold both.
        let buffer = renderToBuffer(
            HStack(alignment: .top, spacing: 1) {
                Text("a\nb").alignmentGuide(.top) { _ in 1 }
                Text("x\ny")
            },
            context: makeRenderContext(width: 20, height: 6))

        #expect(buffer.height == 3)
        #expect(buffer.lines[0].stripped.contains("a"))
        #expect(!buffer.lines[0].stripped.contains("x"))
        #expect(buffer.lines[1].stripped.contains("b"))
        #expect(buffer.lines[1].stripped.contains("x"))
        #expect(buffer.lines[2].stripped.contains("y"))
    }

    @Test("A guide above the view's own top drops the view")
    func negativeGuideDropsTheColumn() {
        // A guide of -1 sits one row ABOVE the view. Putting that on the row's
        // top line therefore puts the view itself one row below it.
        let buffer = renderToBuffer(
            HStack(alignment: .top, spacing: 1) {
                Text("x").alignmentGuide(.top) { _ in -1 }
                Text("a\nb")
            },
            context: makeRenderContext(width: 20, height: 6))

        #expect(buffer.height == 2)
        #expect(!buffer.lines[0].stripped.contains("x"))
        #expect(buffer.lines[1].stripped.contains("x"))
    }

    @Test("A ZStack reads guides on both axes")
    func zStackHonoursBothAxes() {
        let buffer = renderToBuffer(
            ZStack(alignment: .topLeading) {
                Text("####")
                Text("^").alignmentGuide(.leading) { $0[.trailing] }
            },
            context: makeRenderContext(width: 20, height: 4))

        // "^" hangs entirely to the LEFT of the leading line — its trailing edge
        // is the guide — so the fill starts one cell in and the frame grows by
        // that cell.
        #expect(buffer.width == 5)
        #expect(buffer.lines[0].stripped == "^####")
    }

    // MARK: - Single-child regions

    @Test("A frame places its content by the content's guide")
    func frameHonoursTheGuide() {
        let plain = renderToBuffer(
            Text("ab").frame(width: 10, alignment: .center),
            context: makeRenderContext(width: 20, height: 3))
        // Centred: (10 - 2) / 2 == 4.
        #expect(indents(plain) == [4])

        let guided = renderToBuffer(
            Text("ab").alignmentGuide(HorizontalAlignment.center) { _ in 0 }
                .frame(width: 10, alignment: .center),
            context: makeRenderContext(width: 20, height: 3))
        // The guide is now the LEADING edge, so that edge meets the frame's
        // centre line instead of the text's middle doing so.
        #expect(indents(guided) == [5])
    }

    @Test("An overlay is placed by its own guide")
    func overlayHonoursTheGuide() {
        // A two-cell overlay, so the guided and unguided placements differ:
        // centred normally at (5 - 2) / 2 == 1, but guided on its own LEADING
        // edge that edge meets the base's centre line at 2.
        let plain = renderToBuffer(
            Text("#####").overlay(alignment: .center) { Text("^v") },
            context: makeRenderContext(width: 20, height: 3))
        #expect(plain.lines[0].stripped == "#^v##")

        let guided = renderToBuffer(
            Text("#####").overlay(alignment: .center) {
                Text("^v").alignmentGuide(HorizontalAlignment.center) { _ in 0 }
            },
            context: makeRenderContext(width: 20, height: 3))
        #expect(guided.lines[0].stripped == "##^v#")
    }

    // MARK: - Contract

    @Test("An unrelated guide is left alone")
    func onlyTheMatchingGuideApplies() {
        // A `.top` guide must not disturb a horizontal alignment, and vice
        // versa: guides are keyed by the AlignmentID that defines them.
        let buffer = renderToBuffer(
            VStack(alignment: .leading) {
                Text("•").alignmentGuide(.top) { _ in 5 }
                Text("item")
            },
            context: makeRenderContext(width: 30, height: 4))

        #expect(indents(buffer) == [0, 0])
    }

    @Test("A guide for another alignment leaves the container's own arithmetic in force")
    func irrelevantGuideChangesNothing() {
        // The run is decided on the values its children give for the guide
        // the row aligns on, not on whether a child carries a guide at all.
        // Here the row is clamped to two lines, where the run's arithmetic (an
        // extent of the tallest child, three) and the row's own (the two
        // lines it has) put the short child on different lines: deciding on
        // the flag, a `.leading` guide — a horizontal one, in a row that
        // aligns vertically — dropped "a" a line.
        func row(guided: Bool) -> [String] {
            renderToBuffer(
                HStack(alignment: .center, spacing: 1) {
                    if guided {
                        Text("a").alignmentGuide(.leading) { _ in 0 }
                    } else {
                        Text("a")
                    }
                    Text("x\ny\nz")
                },
                context: makeRenderContext(width: 10, height: 2)
            ).lines.map(\.stripped)
        }
        #expect(row(guided: true) == row(guided: false))
        #expect(row(guided: true).first?.hasPrefix("a") == true)
    }

    @Test("A run is built only when a child gives a value for the guide asked about")
    func runIsDecidedOnValues() {
        let children = [
            ChildView(Text("abc").alignmentGuide(.leading) { _ in 0 }, childIndex: 0),
            ChildView(Text("abcdef"), childIndex: 1),
        ]
        let sizes = [(width: 3, height: 1), (width: 6, height: 1)]
        let context = makeRenderContext(width: 20, height: 4)
        #expect(horizontalGuideRun(children, sizes: sizes, alignment: .center, context: context) == nil)
        #expect(verticalGuideRun(children, sizes: sizes, alignment: .top, context: context) == nil)
        #expect(horizontalGuideRun(children, sizes: sizes, alignment: .leading, context: context) != nil)
    }

    @Test("Chained guides both apply")
    func chainedGuidesBothApply() {
        // Nested wrappers: the outer must answer for its own guide AND forward
        // to the inner one for the other axis.
        let view = Text("•")
            .alignmentGuide(.leading) { $0[.trailing] }
            .alignmentGuide(.top) { _ in 0 }
        let buffer = renderToBuffer(
            VStack(alignment: .leading) {
                view
                Text("item")
            },
            context: makeRenderContext(width: 30, height: 4))

        #expect(indents(buffer) == [0, 1])
    }

    @Test("The outermost application of a repeated guide wins")
    func outermostRepeatedGuideWins() {
        let view = Text("••")
            .alignmentGuide(.leading) { _ in 0 }
            .alignmentGuide(.leading) { $0[.trailing] }
        let buffer = renderToBuffer(
            VStack(alignment: .leading) {
                view
                Text("item")
            },
            context: makeRenderContext(width: 30, height: 4))

        // The outer one (trailing edge, 2) is in force, not the inner `0`.
        #expect(indents(buffer) == [0, 2])
    }

    @Test("The measure reports the width the render produces")
    func measureAgreesWithRender() {
        // A guide grows the column; if only the render knew that, the parent
        // would reserve too little and clip it.
        let view = VStack(alignment: .leading) {
            Text("•").alignmentGuide(.leading) { $0[.trailing] }
            Text("item")
        }
        let context = makeRenderContext(width: 30, height: 4)
        let measured = measureChild(view, proposal: .unspecified, context: context)
        let rendered = renderToBuffer(view, context: context)

        #expect(measured.width == rendered.width)
        #expect(measured.height == rendered.height)
    }

    @Test("A guide buried under padding of nothing still applies")
    func aGuideThroughZeroPadding() {
        // Measured on SwiftUI: `.padding(0)` between a guide and the stack
        // that aligns on it changes nothing. The bullet hangs off the line.
        let buffer = renderToBuffer(
            VStack(alignment: .leading) {
                Text("•").alignmentGuide(.leading) { $0[.trailing] }.padding(0)
                Text("item")
            },
            context: makeRenderContext(width: 30, height: 4))

        #expect(indents(buffer) == [0, 1])
    }

    // MARK: - A guide travels up through containers

    @Test("A guide inside a column, a row or a ZStack moves that container as a whole")
    func guideTravelsThroughStacks() {
        func indentsOf(_ inner: some View) -> [Int] {
            indents(renderToBuffer(
                VStack(alignment: .leading) {
                    inner
                    Text("x")
                },
                context: makeRenderContext(width: 30, height: 6)))
        }
        // The inner container's guide is 3 cells in, so "x" moves to meet it.
        #expect(indentsOf(VStack { Text("ab").alignmentGuide(.leading) { _ in 3 } }) == [0, 3])
        #expect(indentsOf(ZStack { Text("ab").alignmentGuide(.leading) { _ in 3 } }) == [0, 3])
        // In a row the guide is moved by where its view sits: "bc" starts at 2.
        #expect(
            indentsOf(
                HStack(spacing: 1) {
                    Text("a")
                    Text("bc").alignmentGuide(.leading) { _ in 1 }
                }) == [0, 3])
    }

    @Test("A custom alignment set inside each row lines the rows up on it")
    func decimalPointThroughRows() {
        // The case the compatibility notes listed as a gap: the guide is on a
        // `Text` inside each row, and the column aligns the ROWS.
        let buffer = renderToBuffer(
            VStack(alignment: .decimalPoint) {
                HStack(spacing: 0) {
                    Text("12")
                    Text(".5").alignmentGuide(.decimalPoint) { _ in 0 }
                }
                HStack(spacing: 0) {
                    Text("1")
                    Text(".25").alignmentGuide(.decimalPoint) { _ in 0 }
                }
            },
            context: makeRenderContext(width: 30, height: 4))
        #expect(buffer.lines.map(\.stripped) == ["12.5 ", " 1.25"])
    }

    @Test("A guide does not travel out of a view type of the app's own")
    func guideStopsAtAnAppView() {
        // Documented: a view of the app's own states nothing about what its
        // body holds, so the column cannot know to ask it.
        struct Row: View {
            var body: some View {
                Text("ab").alignmentGuide(.leading) { _ in 3 }
            }
        }
        let buffer = renderToBuffer(
            VStack(alignment: .leading) {
                Row()
                Text("x")
            },
            context: makeRenderContext(width: 30, height: 4))
        #expect(indents(buffer) == [0, 0])
    }

    @Test("Guides do not disturb a stack that has none")
    func unguidedStacksAreByteIdentical() {
        // The regression guard for the whole change: the guide path floors ONCE
        // PER RUN where the old path floors once per child, and the two disagree
        // in 190 of 820 centring combinations. Every container therefore keeps
        // its previous arithmetic verbatim unless a child actually set a guide.
        for width in [10, 11, 20, 41] {
            let buffer = renderToBuffer(
                VStack(alignment: .center) {
                    Text("a")
                    Text("bbb")
                    Text("ccccc")
                },
                context: makeRenderContext(width: width, height: 5))
            // Widths 1, 3, 5 centred in the column's own 5 cells: (5-1)/2,
            // (5-3)/2, 0 — regardless of how much room the stack was offered.
            #expect(indents(buffer) == [2, 1, 0])
        }
    }
}
