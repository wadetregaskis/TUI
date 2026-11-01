//  🖥️ TUI — A Terminal UI framework for Swift
//  QuitKeyDemo.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUI

/// The key that quits the app, which is the app's to choose: Control-Q by
/// default, or a bare `q` for an app with nothing to type into.
/// TUI-specific — a window's close box has no terminal equivalent, so the
/// key is the way out, and the status bar names it.
///
/// It sets the app's quit key, not the page's: the status bar's "quit" shows
/// the new key on every page until it is set back.
struct QuitKeyDemo: View {
    @Environment(\.statusBar) private var statusBar

    /// The quit keys offered, by name.
    enum Choice: String, CaseIterable, Hashable {
        case ctrlQ, q, ctrlC

        var shortcut: QuitShortcut {
            switch self {
            case .q: .q
            case .ctrlQ: .ctrlQ
            case .ctrlC: .ctrlC
            }
        }

        /// The choice a quit shortcut is, by its symbol.
        init(_ shortcut: QuitShortcut?) {
            self = Self.allCases.first { $0.shortcut.shortcutSymbol == shortcut?.shortcutSymbol } ?? .ctrlQ
        }
    }

    var body: some View {
        DemoSection("page.focus.quitKey") {
            VStack(alignment: .leading, spacing: 1) {
                Text("page.focus.quitKeyExplain")
                    .foregroundStyle(.palette.foregroundSecondary)
                Picker("page.focus.quitKeyPicker", selection: choice) {
                    ForEach(Choice.allCases, id: \.self) { choice in
                        Text(verbatim: choice.shortcut.shortcutSymbol).tag(choice)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    /// The app's quit key, as a choice.
    private var choice: Binding<Choice> {
        Binding(
            get: { Choice(statusBar?.quitShortcut) },
            set: { statusBar?.quitShortcut = $0.shortcut })
    }
}
