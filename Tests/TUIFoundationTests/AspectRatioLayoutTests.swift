//  🖥️ TUI — A Terminal UI framework for Swift
//  AspectRatioLayoutTests.swift
//
//  `aspectRatio(_:contentMode:)`, `scaledToFit()` and `scaledToFill()` as the
//  layout modifier SwiftUI's is, on any view (measured on macOS 15.8,
//  PROBES-1014/aspect-ratio): the largest size of the ratio inside the offer
//  for `.fit`, the smallest covering it for `.fill`, the ratio in points.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("aspectRatio as a layout")
struct AspectRatioLayoutTests {

    /// A context whose cells are `cellAspect` times as tall as they are wide.
    private func context(cellAspect: Double = 1, width: Int = 20, height: Int = 20) -> RenderContext {
        var context = makeRenderContext(width: width, height: height)
        context.environment.imageCellAspect = cellAspect
        return context
    }

    private func size(_ view: some View, _ proposal: ProposedSize, cellAspect: Double = 1) -> (Int, Int) {
        let measured = measureChild(view, proposal: proposal, context: context(cellAspect: cellAspect))
        return (measured.width, measured.height)
    }

    @Test("Fit offers the largest size of the ratio inside the offer")
    func fitIsTheLargestInside() {
        let wide = Color.red.aspectRatio(2, contentMode: .fit)
        #expect(size(wide, .fixed(20, 20)) == (20, 10))
        #expect(size(wide, .fixed(20, 4)) == (8, 4))
        // A colour has no shape of its own (its ideal is nothing), so with no
        // ratio there is none to keep, and it fills what it is offered.
        let fitted = renderToBuffer(Color.red.scaledToFit(), context: context(width: 20, height: 6))
        #expect(fitted.width == 20 && fitted.lines.count == 6, "\(fitted.width)×\(fitted.lines.count)")
    }

    @Test("Fill covers the offer, and is cut to it")
    func fillCoversTheOffer() {
        let wide = Color.red.aspectRatio(2, contentMode: .fill)
        #expect(size(wide, .fixed(20, 20)) == (20, 20), "40×20 covers it, and is cut to it")
        let buffer = renderToBuffer(wide, context: context(width: 20, height: 4))
        #expect(buffer.width == 20 && buffer.lines.count == 4, "drawn in its space: \(buffer.width)×\(buffer.lines.count)")
    }

    @Test("The ratio is in points: a square is twice as many columns as rows in cells twice as tall")
    func ratioIsInPoints() {
        #expect(size(Color.red.aspectRatio(1, contentMode: .fit), .fixed(40, 40), cellAspect: 2) == (40, 20))
        #expect(size(Color.red.aspectRatio(1, contentMode: .fit), .fixed(40, 10), cellAspect: 2) == (20, 10))
    }

    @Test("An axis offered nothing follows the ratio from the other")
    func openAxisFollowsTheRatio() {
        let wide = Color.red.aspectRatio(2, contentMode: .fit)
        #expect(size(wide, ProposedSize(width: 20, height: nil)) == (20, 10))
        #expect(size(wide, ProposedSize(width: nil, height: 5)) == (10, 5))
    }

    @Test("A view that does not take its offer keeps its own size")
    func textKeepsItsSize() {
        #expect(size(Text("Hello").aspectRatio(2, contentMode: .fit), .fixed(20, 20)) == (5, 1))
        #expect(size(Color.red.frame(width: 3, height: 6).scaledToFit(), .fixed(20, 20)) == (3, 6))
    }

    @Test("The rows of a fitted colour are the rows it draws")
    func fitDraws() {
        let buffer = renderToBuffer(Color.red.aspectRatio(2, contentMode: .fit), context: context(width: 20, height: 20))
        #expect(buffer.width == 20 && buffer.lines.count == 10, "\(buffer.width)×\(buffer.lines.count)")
    }
}
