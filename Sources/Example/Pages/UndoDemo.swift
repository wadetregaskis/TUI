//  🖥️ TUI — A Terminal UI framework for Swift
//  UndoDemo.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Observation
import TUI

/// The app's undo: changes registered with `\.undoManager` are taken back by
/// ⌃Z and put back by redo — the status bar names both keys while there is a
/// step for each, and its items can be clicked too.
struct UndoDemo: View {
    @Environment(\.undoManager) private var undoManager
    @State private var counter = UndoableCounter()

    var body: some View {
        DemoSection("page.state.undoSection") {
            VStack(alignment: .leading, spacing: 1) {
                Text("page.state.undoExplain")
                    .foregroundStyle(.palette.foregroundSecondary)
                HStack(spacing: 2) {
                    Button("−") { counter.set(counter.value - 1, undoManager: undoManager) }
                    Text("\(counter.value)").bold().foregroundStyle(.palette.accent)
                    Button("+") { counter.set(counter.value + 1, undoManager: undoManager) }
                }
            }
        }
    }
}

/// A number whose every change registers its own undo.
///
/// A main-actor class — so `Sendable`, which the macOS 15 SDK asks of what an
/// undo handler captures — that keeps the manager it was last changed under,
/// for the undo to register the redo with.
@MainActor
@Observable
final class UndoableCounter {
    private(set) var value = 0
    @ObservationIgnored private weak var undoManager: UndoManager?

    func set(_ newValue: Int, undoManager: UndoManager?) {
        let old = value
        value = newValue
        self.undoManager = undoManager
        undoManager?.registerUndo(withTarget: self) { counter in
            // Undo runs on the main actor, where the change was made.
            MainActor.assumeIsolated { counter.set(old, undoManager: counter.undoManager) }
        }
    }
}
