//  🖥️ TUI — A Terminal UI framework for Swift
//  FilePanelGoToField.swift
//
//  The field a panel's path bar becomes when `/` is pressed: a path to go
//  to, typed as in a shell.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation
import TUITextInput

/// The path bar's other face: "Go to:" and a field holding a path, which
/// Return goes to and Tab completes (``PathCompletion``).
struct FilePanelGoToField: View {
    let path: Binding<String>

    var body: some View {
        HStack(spacing: 1) {
            Text(LocalizationService.shared.string(for: LocalizationKey.FilePanel.goTo))
                .foregroundStyle(.palette.foregroundSecondary)
            TextField(LocalizationService.shared.string(for: LocalizationKey.FilePanel.goTo), text: path)
        }
    }
}
