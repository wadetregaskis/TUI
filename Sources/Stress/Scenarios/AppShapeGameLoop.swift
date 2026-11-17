//  🖥️ TUI — A Terminal UI framework for Swift
//  AppShapeGameLoop.swift
//
//  A game's shape: a board drawn in a `Canvas`, a preview and a score beside
//  it, and a `TimelineView(.animation)` behind them that steps the game's rules
//  sixty times a second. The model publishes only when what is on screen
//  changes (a piece falls once a second), so most frames should draw nothing
//  but the timeline (tuiarcade's feedback, 2026-11-17).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Observation
import TUI

/// The game's rules, stepped every frame, and what the view draws, replaced
/// once a second.
@MainActor
@Observable
final class GameLoopModel {
    static let columns = 9
    static let rows = 18

    /// What the board shows: one colour index a cell, `0` empty.
    private(set) var board: [UInt8]
    private(set) var score = 0
    @ObservationIgnored private var ticks = 0
    @ObservationIgnored private var seed: UInt64

    init(seed: UInt64) {
        self.seed = seed
        board = (0..<(Self.columns * Self.rows)).map { UInt8(truncatingIfNeeded: mix(seed, $0) % 4) }
    }

    /// One tick of the rules. Publishes a new board every sixtieth.
    func step() {
        ticks += 1
        guard ticks.isMultiple(of: 60) else { return }
        seed = mix(seed, ticks)
        board = Array(board.dropFirst(Self.columns)) + (0..<Self.columns).map { UInt8(truncatingIfNeeded: mix(seed, $0) % 4) }
        score += 10
    }
}

/// The page: the board and the sidebar drawn inline, as an app writes them
/// first, with no `.equatable()`.
struct GameLoopApp: View {
    @State private var model: GameLoopModel

    init(seed: UInt64) {
        _model = State(initialValue: GameLoopModel(seed: seed))
    }

    var body: some View {
        let board = model.board
        HStack(alignment: .top, spacing: 2) {
            Canvas { context, _ in
                for (index, cell) in board.enumerated() {
                    let rect = CGRect(
                        x: index % GameLoopModel.columns * 2, y: index / GameLoopModel.columns * 2, width: 2, height: 2)
                    context.fill(Path(rect), with: .color(Self.colours[Int(cell)]))
                }
            }
            .frame(width: 2 * GameLoopModel.columns, height: GameLoopModel.rows)
            .border(Color.gray)
            .background {
                TimelineView(.animation) { timeline in
                    Color.clear.onChange(of: timeline.date, initial: true) { _, _ in model.step() }
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "Score \(model.score)")
                Canvas { context, _ in
                    for index in 0..<4 {
                        let rect = CGRect(x: index * 2, y: 0, width: 2, height: 2)
                        context.fill(Path(rect), with: .color(Self.colours[Int(board[index]) % 4]))
                    }
                }
                .frame(width: 8, height: 1)
            }
        }
    }

    private static let colours: [Color] = [.black, .red, .blue, .yellow]
}
