//  🖥️ TUI — A Terminal UI framework for Swift
//  AppShapeCanvasLabels.swift
//
//  A treemap's shape, as tuidisk's is written: one `Canvas` filling the page,
//  forty tiles filled at the canvas's own grain and, in the labelled variant,
//  a short name drawn at each tile's top-left with `context.draw(Text, at:)`.
//  The tiles' colours move on at every frame of a `TimelineView(.animation)`,
//  so no memo serves the canvas and a frame is what drawing it costs. The
//  pair prices the labels: tuidisk measured its map's names costing more
//  than all its fills (TUI-FEEDBACK.md, M2 item 9).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUI

/// The page: the treemap, redrawn at every frame.
struct CanvasLabelsApp: View {
    let labelled: Bool
    let seed: UInt64

    var body: some View {
        TimelineView(.animation) { timeline in
            CanvasLabelsMap(
                phase: Int(timeline.date.timeIntervalSinceReferenceDate * 60) % 4, labelled: labelled, seed: seed)
        }
    }
}

/// Forty tiles in eight columns of five, each filled, and named where
/// `labelled`.
private struct CanvasLabelsMap: View {
    static let across = 8
    static let down = 5

    let phase: Int
    let labelled: Bool
    let seed: UInt64

    var body: some View {
        Canvas { [phase, labelled, seed] context, size in
            let colours: [Color] = [.red, .blue, .yellow, .green]
            let tile = CGSize(width: size.width / CGFloat(Self.across), height: size.height / CGFloat(Self.down))
            for index in 0..<(Self.across * Self.down) {
                let origin = CGPoint(x: CGFloat(index % Self.across) * tile.width, y: CGFloat(index / Self.across) * tile.height)
                let rect = CGRect(origin: origin, size: tile).insetBy(dx: 0.25, dy: 0.25)
                context.fill(Path(rect), with: .color(colours[(Int(mix(seed, index) % 4) + phase) % 4]))
            }
            guard labelled else { return }
            for index in 0..<(Self.across * Self.down) {
                let origin = CGPoint(x: CGFloat(index % Self.across) * tile.width, y: CGFloat(index / Self.across) * tile.height)
                context.draw(
                    Text(verbatim: "dir \(index)").foregroundStyle(.white), at: CGPoint(x: origin.x + 1, y: origin.y),
                    anchor: .topLeading)
            }
        }
    }
}
