//  🖥️ TUI — A Terminal UI framework for Swift
//  AppShapeTimelineList.swift
//
//  A launcher's list of live previews: a `List` of a few tall rows, each an
//  animated `Canvas` inside its own `TimelineView(.animation)` beside a title,
//  the first row selected. Every row changes on every frame, so no memo can
//  serve one, and what a frame costs is what the list spends drawing each row
//  — the shape that found every visible row drawn twice a frame, once to learn
//  whether the rows overflow and again to compose them.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUI

/// The page: the list, its first row selected.
struct TimelineListApp: View {
    let rows: Int
    let seed: UInt64
    @State private var selection: Int? = 0

    var body: some View {
        List(Array(0..<rows), id: \.self, selection: $selection) { index in
            TimelineListRow(index: index, title: Synth.sentence(mix(seed, index), words: 3), seed: seed)
        }
    }
}

/// A row: its preview, three lines tall, beside its title.
private struct TimelineListRow: View, Equatable {
    let index: Int
    let title: String
    let seed: UInt64

    var body: some View {
        HStack(spacing: 2) {
            TimelineView(.animation) { timeline in
                TimelineListPreview(
                    phase: Int(timeline.date.timeIntervalSinceReferenceDate * 10) % 20, seed: mix(seed, index))
            }
            .frame(width: 20, height: 3)
            Text(verbatim: "\(index) \(title)")
        }
    }
}

/// A preview of 30 fills, moved along a cell at each phase.
private struct TimelineListPreview: View {
    let phase: Int
    let seed: UInt64

    var body: some View {
        Canvas { [phase, seed] context, _ in
            let colours: [Color] = [.red, .blue, .yellow, .green]
            for index in 0..<30 {
                let rect = CGRect(x: (index % 10 * 2 + phase) % 20, y: index / 10, width: 2, height: 1)
                context.fill(Path(rect), with: .color(colours[Int(mix(seed, index) % 4)]))
            }
        }
    }
}
