//  🖥️ TUI — A Terminal UI framework for Swift
//  CapabilityNote.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUI

/// A quiet note after a sample, said only where it is true: that this terminal
/// is known not to draw it as asked, or that nobody has measured whether it
/// does (`\.terminalCapabilities`). Where the terminal draws it, nothing.
struct CapabilityNote: View {
    /// What the sample needs the terminal to do.
    let features: TerminalCapabilities.Feature

    @Environment(\.terminalCapabilities) private var terminal

    var body: some View {
        if !terminal.unsupported.isDisjoint(with: features) {
            Text("capability.note.unsupported").foregroundStyle(.palette.foregroundTertiary)
        } else if !terminal.undetermined.isDisjoint(with: features) {
            Text("capability.note.undetermined").foregroundStyle(.palette.foregroundTertiary)
        }
    }
}

extension View {
    /// This sample, followed on its line by a ``CapabilityNote`` for
    /// `features`.
    func capabilityNote(_ features: TerminalCapabilities.Feature) -> some View {
        HStack(spacing: 1) {
            self
            CapabilityNote(features: features)
        }
    }
}
