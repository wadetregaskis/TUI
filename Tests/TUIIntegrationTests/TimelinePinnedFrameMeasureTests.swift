//  🖥️ TUI — A Terminal UI framework for Swift
//  TimelinePinnedFrameMeasureTests.swift
//
//  A frame pinned on both axes, `.frame(width:height:)`, is its pins whatever
//  it holds, so its measure does not measure what it holds: a running
//  `TimelineView` in one (a tile launcher's preview) is not measured at each
//  of its entries, and the measures above it can be kept, since none of them
//  depends on the clock. What the frame holds is still drawn at each entry,
//  and a timeline outside a pinned frame whose content changes size still
//  moves what is beside it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing
import TUI
import TUITesting
import TUIView

/// How often the probe below was measured. A global, not a capture, so no
/// view holds anything that would make it compare unequal.
@MainActor private var probeMeasures = 0

/// A leaf that counts its measures and draws one cell.
private struct MeasureProbe: View, Renderable, Layoutable {
    var body: Never { fatalError("MeasureProbe renders via Renderable") }

    func sizeThatFits(proposal: ProposedViewSize, context: RenderContext) -> ViewSize {
        probeMeasures += 1
        return ViewSize.fixed(1, 1)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        FrameBuffer(text: "p")
    }
}

/// A 60 Hz timeline holding the probe, as a preview's loop holds its picture.
private struct ProbedLoop: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            MeasureProbe().onChange(of: timeline.date) { _, _ in }
        }
    }
}

/// Two tiles in a row, each a bordered column of a title over its loop.
private struct Tiles: View {
    /// Whether the loops' frames are pinned on both axes, or on the width alone.
    let pinsHeight: Bool

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<2, id: \.self) { index in
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: "Tile \(index)")
                    if pinsHeight {
                        ProbedLoop().frame(width: 6, height: 2)
                    } else {
                        ProbedLoop().frame(width: 6)
                    }
                }
                .border()
            }
        }
    }
}

/// A clock whose width moves: one digit, then two, at alternate entries.
private struct Widening: View {
    var body: some View {
        HStack(spacing: 0) {
            TimelineView(.animation) { timeline in
                let even = Int((timeline.date.timeIntervalSinceReferenceDate * 60).rounded()).isMultiple(of: 2)
                Text(verbatim: even ? "1" : "22")
            }
            Text(verbatim: "|")
        }
    }
}

@MainActor
@Suite("A frame pinned on both axes is not measured through", .serialized)
struct TimelinePinnedFrameMeasureTests {
    /// The probe's measures over a second of the loops' entries, once the
    /// page has settled.
    private func measuresOverASecond(pinsHeight: Bool) -> (measures: Int, screen: String, after: String) {
        let app = TestApp(width: 20, height: 4) { Tiles(pinsHeight: pinsHeight) }
        _ = app.screen
        app.advance(by: .milliseconds(100))
        let screen = app.screen.text
        probeMeasures = 0
        app.advance(by: .seconds(1))
        let measures = probeMeasures
        return (measures, screen, app.screen.text)
    }

    @Test("A timeline in a frame pinned on both axes is not measured at its entries")
    func pinnedFrameIsNotMeasuredThrough() {
        let pinned = measuresOverASecond(pinsHeight: true)
        #expect(pinned.measures == 0, "the frame's size is its pins: \(pinned.measures) measures")
        #expect(pinned.screen.contains("p"), "what the frame holds is drawn")
        #expect(pinned.after == pinned.screen)
    }

    @Test("A frame pinned on one axis still measures what it holds")
    func halfPinnedFrameIsMeasured() {
        let halfPinned = measuresOverASecond(pinsHeight: false)
        #expect(halfPinned.measures >= 60, "its height is its content's: \(halfPinned.measures) measures")
    }

    @Test("A frame pinned on both axes measures as its pins, offered more or less")
    func pinnedFrameSize() {
        let context = RenderContext(availableWidth: 40, availableHeight: 10)
        probeMeasures = 0
        let framed = MeasureProbe().frame(width: 6, height: 2)
        let roomy = measureChild(framed, proposal: ProposedViewSize(width: 40, height: 10), context: context)
        let tight = measureChild(framed, proposal: ProposedViewSize(width: 4, height: 1), context: context)
        let unoffered = measureChild(framed, proposal: ProposedViewSize(width: nil, height: nil), context: context)
        #expect(probeMeasures == 0)
        #expect((roomy.width, roomy.height, roomy.isWidthFlexible, roomy.isHeightFlexible) == (6, 2, false, false))
        #expect((tight.width, tight.height, tight.isWidthFlexible, tight.isHeightFlexible) == (4, 1, true, true))
        #expect((unoffered.width, unoffered.height) == (6, 2))
    }

    @Test("An entry that changes a timeline's size lays out what is beside it again")
    func timelineSizeChangeRelaysOut() {
        let app = TestApp(width: 6, height: 1) { Widening() }
        _ = app.screen
        var seen: Set<String> = []
        for _ in 0..<6 {
            app.advance(by: .microseconds(16_667))
            seen.insert(app.screen.text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        #expect(seen == ["1|", "22|"], "the bar follows the clock's width: \(seen)")
    }
}
