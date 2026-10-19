//  🖥️ TUIkit — Terminal UI Kit for Swift
//  EdgeGuideReachTests.swift
//
//  A guide inside a stack of several views can leave it only as a baseline or
//  a custom guide (decisions A-GUIDE-2), so a container aligning on an edge or
//  the centre asks no view whose type keeps every guide that way: a lazy stack
//  keeps its window over such rows, and an eager one evaluates no such body
//  to ask it (found in review of B19).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitFoundation
@testable import TUIkitTestSupport
@testable import TUIkitView

/// How many times a body was evaluated.
@MainActor
private final class Evaluations {
    var times = 0

    /// `content`, counted as one evaluation of the body it is.
    func counted<Content: View>(@ViewBuilder _ content: () -> Content) -> Content {
        times += 1
        return content()
    }
}

/// A row whose only guide is an edge guide inside a row of two views, where
/// it places the row's views and stays.
private struct MarkedRow: View {
    let index: Int
    let evaluations: Evaluations
    var body: some View {
        evaluations.counted {
            HStack(alignment: .top) {
                Text("*").alignmentGuide(.top) { _ in 0 }
                Text("row \(index)")
            }
        }
    }
}

/// A row of one view carrying a leading guide, which leaves it.
private struct LeadingRow: View {
    var body: some View {
        Text("ab").alignmentGuide(.leading) { _ in 1 }
    }
}

/// A column of two views, one with a leading guide.
private struct GuidedColumn: View {
    let evaluations: Evaluations
    var body: some View {
        evaluations.counted {
            VStack(alignment: .leading) {
                Text("a").alignmentGuide(.leading) { _ in 1 }
                Text("b")
            }
        }
    }
}

@MainActor
@Suite("Edge and centre guides a type keeps inside")
struct EdgeGuideReachTests {

    @Test("A type answers whether an edge or centre guide can leave it")
    func typeReach() {
        #expect(MarkedRow._providesAlignmentGuide, "it holds a guide")
        #expect(!mayReportEdgeOrCentreGuide(MarkedRow.self), "kept inside a row of two")
        #expect(mayReportEdgeOrCentreGuide(LeadingRow.self), "a guide of one view leaves")
        #expect(!mayReportEdgeOrCentreGuide(Text.self))
        #expect(
            !mayReportEdgeOrCentreGuide(
                VStack<TupleView<_AlignmentGuideView<Text>, Text>>.self),
            "a column of two")
        #expect(mayReportEdgeOrCentreGuide(VStack<_AlignmentGuideView<Text>>.self), "a column of one")
    }

    /// The window was given up for any row type holding a guide anywhere:
    /// 3,000 such rows evaluated 18,011 row bodies to draw ten.
    @Test("A lazy stack keeps its window over rows whose guides cannot leave them")
    func lazyStackKeepsItsWindow() {
        let evaluations = Evaluations()
        let buffer = renderToBuffer(
            ScrollView {
                LazyVStack {
                    ForEach(0..<3000, id: \.self) { MarkedRow(index: $0, evaluations: evaluations) }
                }
            },
            context: makeRenderContext(width: 40, height: 10))
        #expect(buffer.lines.first?.stripped.contains("row 0") == true, "\(buffer.lines.map(\.stripped))")
        #expect(evaluations.times < 1000, "evaluated \(evaluations.times) row bodies")
    }

    /// An `HStack(alignment: .center)` beside such a view asked it its
    /// vertical centre guide, evaluating its body for a guide that cannot
    /// leave it (found in review: three evaluations a render, not two).
    @Test("An edge or centre guide is not asked of a view whose guides all stay inside a stack of several")
    func edgeQueryDoesNotEvaluate() {
        let guided = Evaluations()
        let dimensions = ViewDimensions(width: 1, height: 2)
        let context = makeRenderContext(width: 30, height: 4)
        let column = GuidedColumn(evaluations: guided)
        #expect(explicitGuide(of: column, .vertical(.center), in: dimensions, context: context) == nil)
        #expect(explicitGuide(of: column, .horizontal(.leading), in: dimensions, context: context) == nil)
        #expect(guided.times == 0, "evaluated \(guided.times) times to ask")
    }

    @Test("A guide of one view still leaves a lazy stack's row")
    func lazyRowGuideStillPlaces() {
        let buffer = renderToBuffer(
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    LeadingRow()
                    Text("x")
                }
            },
            context: makeRenderContext(width: 20, height: 4))
        let lines = buffer.lines.map(\.stripped)
        #expect(lines.prefix(2).map { $0.prefix(3) } == ["ab ", " x "], "\(lines)")
    }
}
