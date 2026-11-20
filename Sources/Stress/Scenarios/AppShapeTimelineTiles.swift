//  🖥️ TUI — A Terminal UI framework for Swift
//  AppShapeTimelineTiles.swift
//
//  A tile launcher's shape, as tuiarcade's launcher is written: a row of
//  focusable tiles, each a bordered column of a preview over its name, a
//  score and a blurb, the preview a `Canvas` beside its own
//  `TimelineView(.animation(minimumInterval:))` that steps a demo model,
//  ten frames a second for the chosen tile and five for the other. The
//  focus is on the first tile, which takes Return and a double click as the
//  launcher's do. What changes at an entry is one preview's picture; what
//  stood around it (the tiles' borders, their focus modifiers, the stacks
//  between the root and the timelines) is the cost this shape prices.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Observation
import TUI

/// One tile's demo: a board it moves on by a row at each frame its preview's
/// timeline asks for, at most one every `frameTicks` sixtieths of a second.
@MainActor
@Observable
final class TimelineTilesDemo {
    static let columns = 17
    static let rows = 8

    /// What the preview shows: one colour index a cell.
    private(set) var board: [UInt8]
    @ObservationIgnored private var seed: UInt64
    @ObservationIgnored private var lastFrame: Date?

    init(seed: UInt64) {
        self.seed = seed
        board = (0..<(Self.columns * Self.rows)).map { UInt8(truncatingIfNeeded: mix(seed, $0) % 4) }
    }

    /// Moves the board on if `frameTicks` sixtieths have passed since it last did.
    func run(to date: Date, frameTicks: Int) {
        if let lastFrame, date.timeIntervalSince(lastFrame) * 60 < Double(frameTicks) - 0.5 { return }
        lastFrame = date
        seed = mix(seed, 1)
        board = Array(board.dropFirst(Self.columns))
            + (0..<Self.columns).map { UInt8(truncatingIfNeeded: mix(seed, $0) % 4) }
    }
}

/// The launcher: a title, the tiles in a row, a line of keys.
struct TimelineTilesApp: View {
    let seed: UInt64
    /// Whether the focused tile draws the focus tint a `.focusable()` view
    /// draws, as a launcher that leaves its focus look to TUI does; the
    /// launcher this shape is drawn from turns it off and borders its tile.
    let tinted: Bool
    @FocusState private var focus: Int?
    @State private var demos: [TimelineTilesDemo]

    init(seed: UInt64, tinted: Bool = false) {
        self.seed = seed
        self.tinted = tinted
        _demos = State(initialValue: (0..<2).map { TimelineTilesDemo(seed: mix(seed, $0)) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: "TILES").bold()
            HStack(alignment: .top, spacing: 2) {
                ForEach(0..<demos.count, id: \.self) { index in
                    TimelineTile(index: index, demo: demos[index], isFocused: focus == index)
                        .focusable()
                        .focused($focus, equals: index)
                        .focusEffectDisabled(!tinted)
                        .onTapGesture(count: 2) {}
                        .onTapGesture { focus = index }
                        .onKeyPress(.return) { .handled }
                }
            }
            Text(verbatim: "← →  choose    Return  play").foregroundStyle(.secondary)
        }
        .padding(1)
        // The launcher's `onAppear` sets the focus; a bench has no lifecycle
        // to run one, and the default focus is the same first frame's choice.
        .defaultFocus($focus, 0)
    }
}

/// One tile: its preview over its name, its score and its blurb, bordered
/// brighter while it holds the focus.
private struct TimelineTile: View {
    let index: Int
    let demo: TimelineTilesDemo
    let isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TimelineTilePreview(demo: demo, frameTicks: isFocused ? 6 : 12)
                .frame(width: 2 * TimelineTilesDemo.columns, height: TimelineTilesDemo.rows)
            Text(verbatim: " ")
            HStack {
                Text(verbatim: "Game \(index + 1)").bold()
                Text(verbatim: index == 0 ? "arcade" : "puzzle").foregroundStyle(.secondary)
            }
            Text(verbatim: "Best \(100 * (index + 1))")
            Text(verbatim: Synth.sentence(mix(UInt64(index), 7), words: 8)).foregroundStyle(.secondary)
                .frame(width: 2 * TimelineTilesDemo.columns, height: 4, alignment: .topLeading)
        }
        .padding(.horizontal, 1)
        .border(isFocused ? Color.white : Color.gray)
    }
}

/// A preview: the demo's board, with the timeline that steps it beside it,
/// not behind it.
private struct TimelineTilePreview: View {
    let demo: TimelineTilesDemo
    let frameTicks: Int

    var body: some View {
        ZStack(alignment: .topLeading) {
            TimelineTileBoard(board: demo.board).equatable()
            TimelineView(.animation(minimumInterval: Double(frameTicks) / 60)) { timeline in
                Color.clear
                    .frame(width: 0, height: 0)
                    .onChange(of: timeline.date, initial: true) { _, date in
                        demo.run(to: date, frameTicks: frameTicks)
                    }
            }
        }
    }
}

/// The board drawn in two-cell squares.
private struct TimelineTileBoard: View, Equatable {
    let board: [UInt8]

    var body: some View {
        Canvas { context, _ in
            for (index, cell) in board.enumerated() {
                let rect = CGRect(
                    x: index % TimelineTilesDemo.columns * 2, y: index / TimelineTilesDemo.columns, width: 2,
                    height: 1)
                context.fill(Path(rect), with: .color(Self.colours[Int(cell)]))
            }
        }
    }

    private static let colours: [Color] = [.black, .red, .blue, .yellow]
}
