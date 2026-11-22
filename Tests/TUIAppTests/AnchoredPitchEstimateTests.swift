//  🖥️ TUI — A Terminal UI framework for Swift
//  AnchoredPitchEstimateTests.swift
//
//  The pitch the anchored walk prices the rows it never measured at
//  (SCROLL-9): a mean over the ROWS measured, one sample a row, not over the
//  frames that measured them; at the mean itself, not the whole line it
//  rounds to; and started afresh when the rows are replaced or re-wrapped.
//  What a scrollbar, "N more" and a far jump read.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUIView

@MainActor
@Suite("The anchored walk's running pitch")
struct AnchoredPitchEstimateTests {
    /// One band frame of `view` at `offset`, through a reply channel as a
    /// scroll view hands it: the reply, whose total is what the scrollbar
    /// and "N more" read.
    @discardableResult
    private func renderBand<V: View>(
        _ view: V, tuiContext: TUIContext, offset: Int, width: Int = 30, viewport: Int = 20
    ) -> ScrollContentReply {
        let reply = ScrollContentReply()
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tuiContext)
        environment.scrollContentWindow = ScrollContentWindow(
            offset: offset, viewportHeight: viewport, contentIdentity: nil, reply: reply)
        let context = RenderContext(
            availableWidth: width, availableHeight: viewport,
            environment: environment, tuiContext: tuiContext)
        tuiContext.preferences.beginRenderPass()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        _ = renderToBuffer(view, context: context)
        tuiContext.stateStorage.endRenderPass()
        tuiContext.renderCache.removeInactive()
        return reply
    }

    /// 5,000 rows, the first 40 of one and two lines in turn and the rest
    /// five: 24,860 lines. Of several heights from the first screen, so the
    /// first screen is drawn by the anchored walk, not the uniform arithmetic
    /// (which samples nothing).
    private static func tallAfterForty() -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<5_000, id: \.self) { i in
                Text(verbatim: "row \(i)").frame(height: i < 40 ? 1 + i % 2 : 5, alignment: .top)
            }
        }
    }

    /// A stack that sat on its first screen for 500 frames, then was paged
    /// down through rows five times as tall, prices the rows it has not
    /// reached by the rows it has, not by the frames it drew: a scrollbar
    /// jump to the middle then reads a total near the true one. Counted per
    /// frame, the first screen's one-line rows outweighed every page after
    /// them, and the total was a quarter of the truth.
    @Test("The estimate is a mean over rows, not frames: a total after dwelling, paging and a jump is near the truth")
    func estimateIsAMeanOverRows() {
        let tuiContext = TUIContext()
        let view = Self.tallAfterForty()
        for _ in 0..<500 { renderBand(view, tuiContext: tuiContext, offset: 0) }
        var offset = 0
        for _ in 0..<80 {
            offset += 20
            renderBand(view, tuiContext: tuiContext, offset: offset)
        }
        var reply = renderBand(view, tuiContext: tuiContext, offset: offset)
        let middle = (reply.sliceTotalHeight ?? 0) / 2
        for _ in 0..<10 { reply = renderBand(view, tuiContext: tuiContext, offset: middle) }
        let truth = 60 + 4_960 * 5
        let total = reply.sliceTotalHeight ?? 0
        #expect(abs(total - truth) * 5 <= truth, "total \(total), true \(truth)")
    }

    /// Rows of 1.4 lines on average are priced at 1.4, not at the whole line
    /// it rounds to: priced at 1, the total was 29% short.
    @Test("The estimate prices rows at their mean pitch, not the whole line it rounds to")
    func estimateIsNotRoundedToALine() {
        let tuiContext = TUIContext()
        let view = LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<5_000, id: \.self) { i in
                Text(verbatim: "row \(i)").frame(height: i.isMultiple(of: 5) ? 3 : 1, alignment: .top)
            }
        }
        var reply = renderBand(view, tuiContext: tuiContext, offset: 0)
        for _ in 0..<3 { reply = renderBand(view, tuiContext: tuiContext, offset: 0) }
        let truth = 7_000
        let total = reply.sliceTotalHeight ?? 0
        #expect(abs(total - truth) * 10 <= truth, "total \(total), true \(truth)")
    }

    /// The estimate starts afresh when the rows are replaced (new data, new
    /// ids) and when the width re-wraps them: the rows it sampled are not
    /// the rows there now.
    @Test("The estimate starts afresh when the rows are replaced or re-wrapped")
    func estimateStartsAfreshOnNewRowsOrWidth() {
        // Rows of two heights in turn, `height` and one more: of several
        // heights, so the anchored walk draws them.
        func doc(_ name: String, height: Int) -> some View {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array((0..<5_000).map { "\(name)\($0)" }.enumerated()), id: \.element) { row in
                    Text(verbatim: row.element).frame(height: height + row.offset % 2, alignment: .top)
                }
            }
        }
        let replaced = TUIContext()
        for _ in 0..<50 { renderBand(doc("a", height: 1), tuiContext: replaced, offset: 0) }
        var reply = renderBand(doc("b", height: 5), tuiContext: replaced, offset: 0)
        reply = renderBand(doc("b", height: 5), tuiContext: replaced, offset: 0)
        #expect(abs((reply.sliceTotalHeight ?? 0) - 27_500) * 5 <= 27_500, "replaced: \(reply.sliceTotalHeight ?? 0)")

        let wrapped = TUIContext()
        let words = LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<5_000, id: \.self) { i in
                Text(verbatim: i.isMultiple(of: 2) ? "abcd efgh ijkl mnop" : "abcd efgh ijkl mnop\nx")
            }
        }
        for _ in 0..<50 { renderBand(words, tuiContext: wrapped, offset: 0, width: 60) }
        reply = renderBand(words, tuiContext: wrapped, offset: 0, width: 4)
        reply = renderBand(words, tuiContext: wrapped, offset: 0, width: 4)
        // A word a line at 4 wide: 4 lines a row, and 5 for every other.
        #expect(abs((reply.sliceTotalHeight ?? 0) - 22_500) * 5 <= 22_500, "re-wrapped: \(reply.sliceTotalHeight ?? 0)")
    }
}
