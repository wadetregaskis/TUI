//  🖥️ TUI — A Terminal UI framework for Swift
//  AlignmentGuideKindTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUITestSupport

/// A custom guide, which travels out of any container.
private enum KindMarkID: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> Double { 0 }
}

extension HorizontalAlignment {
    fileprivate static let kindMark = Self(KindMarkID.self)
}

/// A layout of the app's own that stacks its subviews and states nothing
/// about guides, so the default `explicitAlignment` answers for it.
private struct PlainColumn: Layout {
    func sizeThatFits(proposal: ProposedSize, subviews: Subviews, cache: inout ()) -> ViewSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return ViewSize(width: sizes.map(\.width).max() ?? 0, height: sizes.map(\.height).reduce(0, +))
    }

    func placeSubviews(
        in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()
    ) {
        var y = bounds.y
        for subview in subviews {
            subview.place(at: (x: bounds.x, y: y), proposal: .unspecified)
            y += subview.sizeThatFits(.unspecified).height
        }
    }
}

/// `G`, a one-cell view whose leading guide is five cells in.
@MainActor
private func guided() -> some View {
    Text("G").alignmentGuide(.leading) { _ in 5 }
}

/// A view of the app's own whose body is `G`.
private struct OneView: View {
    var body: some View { guided() }
}

/// A view of the app's own whose body is an `if`/`else` of one view each.
private struct Branch: View {
    let flag: Bool
    var body: some View {
        if flag {
            guided()
        } else {
            Text("G")
        }
    }
}

/// SwiftUI's rule, measured (decisions A-GUIDE-2,
/// `Tools/SwiftUIProbes/Alignment guides/layout1.out`): a container that
/// arranges several views places them by an edge or centre guide and reports
/// none of it; a text baseline and a custom guide travel on out of it; and a
/// container whose content is statically one view reports every guide of it.
@MainActor
@Suite("Which guides leave a container")
struct AlignmentGuideKindTests {

    /// Where the six-cell `C` beside `inner` in a leading-aligned column
    /// starts: 5 when `inner` reports `G`'s leading guide, 0 when it does not.
    private func leadingReported(_ inner: some View) -> Int {
        let buffer = renderToBuffer(
            VStack(alignment: .leading, spacing: 0) {
                inner
                Text("CCCCCC")
            },
            context: makeRenderContext(width: 40, height: 10))
        let line = buffer.lines.last?.stripped ?? ""
        return line.count - line.drop(while: { $0 == " " }).count
    }

    /// Where the one-row `C` beside `inner` in a row aligned on the first
    /// text baseline sits: 5 when `inner` reports the baseline `G` sets, 0
    /// when it does not (a view's own first baseline is its first row).
    private func baselineReported(_ inner: some View) -> Int {
        let buffer = renderToBuffer(
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                inner
                Text("C")
            },
            context: makeRenderContext(width: 40, height: 10))
        return buffer.lines.firstIndex { $0.stripped.hasSuffix("C") } ?? -1
    }

    @Test("A stack of several views keeps an edge guide to itself")
    func edgeGuideStaysInAStackOfSeveral() {
        #expect(leadingReported(VStack(alignment: .leading, spacing: 0) { guided(); Text("SSSSSS") }) == 0)
        #expect(leadingReported(HStack(spacing: 0) { guided(); Text("SSSSSS") }) == 0)
        #expect(leadingReported(ZStack(alignment: .leading) { guided(); Text("SSSSSS") }) == 0)
        #expect(leadingReported(VStackLayout(alignment: .leading, spacing: 0) { guided(); Text("SSSSSS") }) == 0)
    }

    @Test("Two edge guides in a stack are not averaged into one")
    func edgeGuidesAreNotAveraged() {
        // TUI reported 4, the mean of 7 and 1, where no child aligned.
        let inner = VStack(alignment: .center, spacing: 0) {
            guided()
            Text("SSSSSS").alignmentGuide(.leading) { _ in 1 }
        }
        #expect(leadingReported(inner) == 0)
    }

    @Test("A stack whose content is statically one view reports its edge guide")
    func staticallyOneViewReportsItsEdgeGuide() {
        #expect(leadingReported(VStack(spacing: 0) { guided() }) == 5)
        #expect(leadingReported(VStack(spacing: 0) { guided(); EmptyView() }) == 5)
        #expect(leadingReported(VStack(spacing: 0) { Group { guided() } }) == 5)
        #expect(leadingReported(VStack(spacing: 0) { guided().padding(0) }) == 5)
        #expect(leadingReported(VStack(spacing: 0) { OneView() }) == 5)
        #expect(leadingReported(HStack(spacing: 0) { guided() }) == 5)
        #expect(leadingReported(VStackLayout(alignment: .leading, spacing: 0) { guided() }) == 5)
        #expect(leadingReported(ZStackLayout(alignment: .leading) { guided() }) == 5)
    }

    @Test("Content that is one view only at run time keeps an edge guide in its stack")
    func dynamicallyOneViewKeepsItsEdgeGuide() {
        #expect(leadingReported(VStack(spacing: 0) { ForEach(0..<1, id: \.self) { _ in guided() } }) == 0)
        #expect(leadingReported(VStack(spacing: 0) { if true { guided() } }) == 0)
        #expect(leadingReported(VStack(spacing: 0) { Branch(flag: true) }) == 0)
        #expect(leadingReported(VStack(spacing: 0) { AnyView(guided()) }) == 0)
        #expect(leadingReported(PlainColumn { guided() }) == 0)
    }

    @Test("A view of the app's own whose body is an if/else passes the guide of its live branch")
    func branchBodyPassesItsGuide() {
        #expect(leadingReported(Branch(flag: true)) == 5)
        #expect(leadingReported(Branch(flag: false)) == 0)
    }

    @Test("A custom guide leaves a stack of several views")
    func customGuideLeavesAStackOfSeveral() {
        let buffer = renderToBuffer(
            VStack(alignment: .kindMark, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("G").alignmentGuide(.kindMark) { _ in 5 }
                    Text("SSSSSS")
                }
                Text("CCCCCC")
            },
            context: makeRenderContext(width: 40, height: 10))
        let line = buffer.lines.last?.stripped ?? ""
        #expect(line.count - line.drop(while: { $0 == " " }).count == 5)
    }

    @Test("A text baseline leaves a stack or a layout of several views")
    func baselineLeavesAContainerOfSeveral() {
        func baselined() -> some View { Text("G").alignmentGuide(.firstTextBaseline) { _ in 5 } }
        #expect(baselineReported(VStack(spacing: 0) { Text("S"); Text("T") }) == 0)
        #expect(baselineReported(VStack(spacing: 0) { baselined(); Text("S") }) == 5)
        #expect(baselineReported(HStack(spacing: 0) { baselined(); Text("S") }) == 5)
        #expect(baselineReported(ZStack { baselined(); Text("S") }) == 5)
        // A layout's default merged a baseline as if it were an edge, and
        // dropped it.
        #expect(baselineReported(PlainColumn { baselined(); Text("S") }) == 5)
    }

    @Test("Several first baselines merge to the topmost")
    func firstBaselinesMergeToTheTopmost() {
        let inner = VStack(spacing: 0) {
            Text("G").alignmentGuide(.firstTextBaseline) { _ in 5 }
            Text("S").alignmentGuide(.firstTextBaseline) { _ in 2 }
        }
        // `S` sits a row below `G`, so its baseline is at 3 in the stack.
        #expect(baselineReported(inner) == 3)
    }
}
