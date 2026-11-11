//  🖥️ TUI — A Terminal UI framework for Swift
//  FlowLayoutTests.swift
//
//  `FlowLayout` wraps its subviews onto lines (owner's ruling, 2026-11-10).
//  These pin the rules its doc comment states: where a line breaks, how tall
//  a line is, the size reported for each kind of offer, what a member wider
//  than the offer does, the alignment, and that it works through `AnyLayout`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("FlowLayout")
struct FlowLayoutTests {

    /// The painted rows, trailing blanks dropped.
    private func lines(_ view: some View, width: Int, height: Int = 10) -> [String] {
        renderToBuffer(view, context: makeRenderContext(width: width, height: height))
            .lines
            .map { String($0.stripped.reversed().drop(while: { $0 == " " }).reversed()) }
    }

    /// The size reported for `proposal`, measured where the width offered is
    /// the width there is, as it is when the layout is drawn.
    private func size(_ view: some View, _ proposal: ProposedViewSize) -> ViewSize {
        measureChild(view, proposal: proposal, context: makeRenderContext(width: proposal.width ?? 80, height: 10))
    }

    private var chips: some View {
        FlowLayout {
            Text(verbatim: "aa")
            Text(verbatim: "bb")
            Text(verbatim: "cc")
        }
    }

    @Test("Members fill a line and wrap when the next would not fit")
    func wraps() {
        #expect(lines(chips, width: 5).prefix(2) == ["aa bb", "cc"])
        #expect(lines(chips, width: 8).first == "aa bb cc")
    }

    @Test("Each line is as tall as its tallest member")
    func lineHeight() {
        let view = FlowLayout {
            Text(verbatim: "a")
            Text(verbatim: "b\nb")
            Text(verbatim: "cc")
        }
        // `a` and the two-row `b` share a line two rows tall; `cc` starts
        // below it, not beside `b`'s second row.
        #expect(lines(view, width: 4).prefix(3) == ["a b", "  b", "cc"])
        #expect(size(view, ProposedViewSize(width: 4, height: nil)) == ViewSize(width: 3, height: 3))
    }

    @Test("Offered no width, the ideal is every member on one line")
    func idealIsOneLine() {
        #expect(size(chips, .unspecified) == ViewSize(width: 8, height: 1))
    }

    @Test("Offered a width, it reports its widest line, never more than the width")
    func finiteReportsWidestLine() {
        #expect(size(chips, ProposedViewSize(width: 6, height: nil)) == ViewSize(width: 5, height: 2))
        #expect(size(chips, ProposedViewSize(width: 100, height: 1)) == ViewSize(width: 8, height: 1))
    }

    @Test("Offered zero, every member gets a line of its own at its minimum")
    func zeroIsTheMinimum() {
        let view = FlowLayout {
            Color.red.frame(width: 2, height: 1)
            Color.red.frame(width: 3, height: 2)
        }
        // Asked for its minimum by a parent that has room (80 columns here),
        // as a stack asks its members with a zero proposal.
        let minimum = measureChild(view, proposal: .zero, context: makeRenderContext(width: 80, height: 10))
        #expect(minimum == ViewSize(width: 0, height: 3))
    }

    @Test("A text measures within the width there is, so it arrives wrapped")
    func textArrivesWrapped() {
        let view = FlowLayout {
            Text(verbatim: "x")
            Text(verbatim: "hello world")
        }
        // At 7, the text's ideal is `hello` over `world`, five wide, which
        // fits beside `x`.
        #expect(lines(view, width: 7).prefix(2) == ["x hello", "  world"])
        #expect(size(view, ProposedViewSize(width: 7, height: nil)) == ViewSize(width: 7, height: 2))
    }

    @Test("A member wider than the width starts a line and overhangs; the size stays within the offer")
    func rigidMemberOverhangs() {
        let view = FlowLayout {
            Text(verbatim: "x")
            Text(verbatim: "hello world").fixedSize()
        }
        let drawn = lines(view, width: 7)
        #expect(drawn.first == "x", "\(drawn)")
        #expect(drawn.dropFirst().first?.hasPrefix("hello") == true, "\(drawn)")
        #expect(size(view, ProposedViewSize(width: 7, height: nil)) == ViewSize(width: 7, height: 2))
    }

    @Test("Spacing and line spacing are stated in cells")
    func explicitSpacing() {
        let view = FlowLayout(spacing: 2, lineSpacing: 1) {
            Text(verbatim: "aa")
            Text(verbatim: "bb")
            Text(verbatim: "cc")
        }
        #expect(lines(view, width: 6).prefix(3) == ["aa  bb", "", "cc"])
        #expect(size(view, ProposedViewSize(width: 6, height: nil)) == ViewSize(width: 6, height: 3))
    }

    @Test("A member of no width takes no gap and never breaks a line")
    func emptyMemberTakesNoPart() {
        let view = FlowLayout {
            Text(verbatim: "aa")
            EmptyView()
            Text(verbatim: "bb")
        }
        #expect(lines(view, width: 5).first == "aa bb")
    }

    @Test("Alignment places each line across the width and each member in its line")
    func alignment() {
        let view = FlowLayout(alignment: .bottomTrailing) {
            Text(verbatim: "a")
            Text(verbatim: "b\nb")
            Text(verbatim: "cc")
        }
        // The layout is as wide as its widest line, `a b`; `cc`, a line of
        // its own, ends at that line's trailing edge, and `a` sits at the
        // bottom of the two-row line it shares with `b`.
        #expect(lines(view, width: 5).prefix(3) == ["  b", "a b", " cc"])
    }

    @Test("Through AnyLayout it arranges as it does directly")
    func throughAnyLayout() {
        let erased = AnyLayout(FlowLayout()) {
            Text(verbatim: "aa")
            Text(verbatim: "bb")
            Text(verbatim: "cc")
        }
        #expect(lines(erased, width: 5) == lines(chips, width: 5))
        #expect(size(erased, .unspecified) == size(chips, .unspecified))
    }
}
