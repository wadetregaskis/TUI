//  🖥️ TUI — A Terminal UI framework for Swift
//  AppShapeTimelineBeside.swift
//
//  A launcher's shape: a page of static, dear content — a board `Canvas`
//  under `.equatable()` with the game loop's `TimelineView(.animation)` in its
//  `.background`, a `List` of previews and a `Button` whose label is a canvas,
//  under two composites whose bodies sort — and a slow preview timeline at
//  five entries a second beside the 60 Hz one. Nothing it shows changes but the
//  timelines' own content, so a frame should run their content and nothing
//  else: no body above them, no canvas, and the slow timeline's content only
//  at its own entries (tuiarcade's TUI-FEEDBACK.md, M2 items 1 to 4).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUI

/// The page: two levels of composites above everything, each body sorting a
/// list as an app's might.
struct TimelineBesideApp: View {
    let seed: UInt64

    var body: some View {
        let names = (0..<200).map { Synth.sentence(mix(seed, $0), words: 2) }.sorted()
        TimelineBesideColumns(title: names.first ?? "", seed: seed)
    }
}

private struct TimelineBesideColumns: View {
    let title: String
    let seed: UInt64
    @State private var selection: Int?

    // The two columns are their own properties: as one expression the body
    // ran past the type-check guard's time limit.
    var body: some View {
        HStack(alignment: .top, spacing: 2) {
            board
            previews
        }
    }

    private var board: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: title)
            TimelineBesideBoard(seed: seed).equatable()
                .frame(width: 30, height: 10)
                .background { TimelineView(.animation) { timeline in TimelineBesideTick(date: timeline.date) } }
            Button {} label: {
                TimelineBesideBoard(seed: mix(seed, 99)).equatable().frame(width: 12, height: 2)
            }
        }
    }

    private var previews: some View {
        let order: [Int] = (0..<6).sorted { mix(seed, $0) < mix(seed, $1) }
        return VStack(alignment: .leading, spacing: 1) {
            TimelineView(.animation(minimumInterval: 0.2)) { timeline in
                TimelineBesideFrameLabel(date: timeline.date)
            }
            List(order, id: \.self, selection: $selection) { index in
                TimelineBesideBoard(seed: mix(seed, index)).equatable().frame(width: 20, height: 2)
            }
            .frame(width: 24, height: 14)
        }
    }
}

/// The game loop's tick: reads the date, draws nothing.
private struct TimelineBesideTick: View {
    let date: Date

    var body: some View {
        Color.clear.onChange(of: date) { _, _ in }
    }
}

/// The slow preview's frame number, at five entries a second.
private struct TimelineBesideFrameLabel: View {
    let date: Date

    var body: some View {
        let frame = Int(date.timeIntervalSinceReferenceDate * 5) % 100
        Text(verbatim: "frame \(frame)")
    }
}

/// A board of 60 fills that reads nothing but its seed.
private struct TimelineBesideBoard: View, Equatable {
    let seed: UInt64

    var body: some View {
        Canvas { context, _ in
            let colours: [Color] = [.red, .blue, .yellow, .green]
            for index in 0..<60 {
                let rect = CGRect(x: index % 10 * 2, y: index / 10, width: 2, height: 1)
                context.fill(Path(rect), with: .color(colours[Int(mix(seed, index) % 4)]))
            }
        }
    }
}
