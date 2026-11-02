//  🖥️ TUI — A Terminal UI framework for Swift
//  DocumentCommands.swift
//
//  The File menu of a `DocumentGroup`: New, Open…, Save and Save As….
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICommands
import TUIFoundation

/// A `DocumentGroup`'s commands, in the groups macOS has them in: New and Open…
/// where an app's `CommandGroup(replacing: .newItem)` takes them away, as
/// document apps do, and Save and Save As… after Close, if the app has one.
struct DocumentCommands: Commands {
    /// Whether the group only views, so the menu has only Open….
    let isViewer: Bool

    /// The window's session, as the window drew it last.
    @FocusedValue(\.documentSession) private var session

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            if !isViewer {
                Button(LocalizationService.shared.string(for: LocalizationKey.Menu.new)) { session?.new() }
                    .keyboardShortcut("n")
                    .disabled(session == nil)
            }
            Button(LocalizationService.shared.string(for: LocalizationKey.Document.open)) { session?.open() }
                .keyboardShortcut("o")
                .disabled(session == nil)
        }
        CommandGroup(after: .saveItem) {
            if !isViewer {
                Button(LocalizationService.shared.string(for: LocalizationKey.Menu.save)) { session?.save() }
                    .keyboardShortcut("s")
                    .disabled(session == nil)
                Button(LocalizationService.shared.string(for: LocalizationKey.Document.saveAs)) { session?.saveAs() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(session == nil)
            }
        }
    }
}

private struct DocumentSessionKey: FocusedValueKey {
    typealias Value = DocumentSession
}

extension FocusedValues {
    /// The `DocumentGroup` window's session, which the File commands act on.
    var documentSession: DocumentSession? {
        get { self[DocumentSessionKey.self] }
        set { self[DocumentSessionKey.self] = newValue }
    }
}
