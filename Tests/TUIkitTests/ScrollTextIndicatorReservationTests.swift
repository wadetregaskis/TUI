//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollTextIndicatorReservationTests.swift
//
//  The "N more" pair a scroll target behaviour reserves out of a text-style
//  ScrollView's window: only where the content overflows (scroll lane review
//  3, item 1), decided once per layout, and counted by the view's ideal size
//  wherever it is reserved, so a parent that sizes to content gives the lines
//  room.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

@MainActor
@Suite("The \"N more\" pair's reservation")
struct ScrollTextIndicatorReservationTests {

    private func rows(_ count: Int) -> some View {
        ForEach(0..<count, id: \.self) { Text("row \($0)") }
    }

    /// The rows drawn on the frame, by number, and how many "N more" lines are
    /// (narrow, one reads "▲ 0").
    private func drawn(_ frames: ScrollTargetFrames) -> (rows: [Int], indicators: Int) {
        var rows: [Int] = []
        var indicators = 0
        for line in frames.last.lines.map(\.stripped) {
            if line.contains("▲") || line.contains("▼") { indicators += 1 }
            if let marker = line.range(of: "row ") {
                rows.append(Int(line[marker.upperBound...].prefix { $0.isNumber }) ?? -1)
            }
        }
        return (rows, indicators)
    }

    /// The review's failing input: the pair was reserved under the behaviour
    /// whatever the content, so five rows that fit drew three between
    /// "▲ 0 more lines above" and "▼ 2 more lines below", and scrolled.
    @Test("A paging text-style ScrollView whose content fits draws all of it and no indicators")
    func fittingContentReservesNothing() {
        let frames = ScrollTargetFrames(width: 30, height: 20)
        frames.render(
            Dialog(title: "T") {
                ScrollView { rows(5) }
                    .scrollIndicators(.automatic)
                    .scrollIndicatorStyle(.text)
                    .scrollTargetBehavior(.paging)
            })
        let result = drawn(frames)
        #expect(result.rows == [0, 1, 2, 3, 4], "\(frames.last.lines.map(\.stripped))")
        #expect(result.indicators == 0)
    }

    @Test("Content that fits a fixed window exactly is not reserved out of it")
    func exactlyFittingContent() {
        let frames = ScrollTargetFrames(width: 30, height: 10)
        frames.render(
            ScrollView { rows(10) }.frame(height: 10)
                .scrollIndicators(.automatic)
                .scrollIndicatorStyle(.text)
                .scrollTargetBehavior(.paging))
        let result = drawn(frames)
        #expect(result.rows == Array(0..<10))
        #expect(result.indicators == 0)
    }

    @Test("Content that overflows still has the pair reserved, at every stop")
    func overflowingContentReserves() {
        let frames = ScrollTargetFrames(width: 30, height: 10)
        let view = ScrollView { rows(11) }.frame(height: 10)
            .scrollIndicators(.automatic)
            .scrollIndicatorStyle(.text)
            .scrollTargetBehavior(.paging)
        frames.render(view)
        #expect(drawn(frames).rows == Array(0..<8))
        #expect(drawn(frames).indicators == 2)
        frames.wheel(.scrollDown)
        frames.render(view)
        #expect(drawn(frames).rows == Array(3..<11))
        #expect(drawn(frames).indicators == 2)
    }

    /// `.visible` reserves the pair at every offset whatever the content, so a
    /// parent that sizes to the view's ideal height has to be told about the
    /// two lines, or it gives the rows two lines too few and they scroll.
    @Test("The ideal height counts a reserved pair: a .visible text-style ScrollView in a Dialog draws every row")
    func idealHeightCountsTheReservedLines() {
        let frames = ScrollTargetFrames(width: 30, height: 20)
        frames.render(
            Dialog(title: "T") {
                ScrollView { rows(5) }
                    .scrollIndicators(.visible)
                    .scrollIndicatorStyle(.text)
            })
        let result = drawn(frames)
        #expect(result.rows == [0, 1, 2, 3, 4], "\(frames.last.lines.map(\.stripped))")
        #expect(result.indicators == 2)
    }

    /// The overflow is decided on the content measured against the whole
    /// window, and the content is then drawn against the window less the
    /// pair: two questions at one proposal, which the measure memos must not
    /// answer with each other's sizes. Served the probe's 50 lines, five
    /// window-sized pages drawn eight lines tall left the trailing spacer ten
    /// blank lines, and paging ended on them past the last page. The memoised
    /// rows' cross-frame size table served it without a pass tracker too; with
    /// one, the pass's own memo is on as well.
    @Test(
        "Pages sized against the window are measured against the window the pair leaves",
        arguments: [false, true])
    func theOverflowProbeIsNotServedToTheDraw(memoisesMeasures: Bool) {
        let frames = ScrollTargetFrames(width: 30, height: 10, memoisesMeasures: memoisesMeasures)
        let view = ScrollView {
            VStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { page in
                    VStack(spacing: 0) {
                        Text("top \(page)")
                        Spacer(minLength: 0)
                        Text("end \(page)")
                    }
                    .containerRelativeFrame(.vertical)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 10)
        .scrollIndicators(.automatic)
        .scrollIndicatorStyle(.text)
        .scrollTargetBehavior(.paging)
        frames.render(view)
        frames.render(view)
        #expect(frames.scrollView?.contentHeight == 40, "the pages were measured against the whole window")
        for _ in 0..<8 {
            frames.wheel(.scrollDown)
            frames.render(view)
        }
        let lines = frames.last.lines.map(\.stripped)
        #expect(lines.contains { $0.contains("top 4") }, "\(lines)")
        #expect(lines.contains { $0.contains("end 4") }, "\(lines)")
    }

    /// A horizontal bar that is always drawn takes its row off the window, so
    /// content as tall as the viewport overflows the window by that row. The
    /// decision was asked of the whole viewport, so it reserved nothing, and
    /// the pair was drawn over the window's edge lines under the behaviour.
    @Test("Content that overflows only by an always-drawn horizontal bar's row still has the pair reserved")
    func overflowByTheBarsRowReserves() {
        let frames = ScrollTargetFrames(width: 20, height: 10)
        let view = ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<10, id: \.self) { Text("row \($0) " + String(repeating: "-", count: 30)) }
            }
        }
        .scrollIndicators(.visible, axes: .horizontal)
        .scrollIndicators(.automatic, axes: .vertical)
        .scrollIndicatorStyle(.text)
        .scrollTargetBehavior(.paging)
        frames.render(view)
        frames.render(view)
        let result = drawn(frames)
        #expect(result.rows == Array(0..<7), "\(frames.last.lines.map(\.stripped))")
        #expect(result.indicators == 2)
    }
}
