//  🖥️ TUIkit — Terminal UI Kit for Swift
//  View+ClipboardCommand.swift
//
//  The modifier every clipboard command is: a handler for SwiftUI's ⌘C, ⌘X or
//  ⌘V on the focus path, and for a bracketed paste.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

extension View {
    /// The focus-path modifier a clipboard command is: a command-stage
    /// handler for SwiftUI's ⌘`key`, resolved through the environment's
    /// ``EnvironmentValues/commandKey`` where the view renders, and — for
    /// the paste — for a bracketed paste too.
    ///
    /// - Parameters:
    ///   - key: The letter SwiftUI binds the command to with ⌘.
    ///   - perform: Given the key event and the clipboard, answers whether
    ///     the command took the key.
    func clipboardCommand(
        _ key: KeyEquivalent, perform: @escaping (KeyEvent, ClipboardAccess) -> Bool
    ) -> FocusPathModifier<Self> {
        let takesPaste = key == "v"
        return FocusPathModifier(content: self, stage: .command) { context in
            let chord = KeyboardShortcut(key, modifiers: .command)
                .resolved(commandKey: context.environment.commandKey)?.trigger
            let clipboard = context.environment.clipboardAccess
            return { event in
                let isPaste: Bool
                if case .paste = event.key { isPaste = true } else { isPaste = false }
                guard (isPaste && takesPaste) || (chord != nil && KeyboardShortcut.trigger(for: event) == chord)
                else { return false }
                return perform(event, clipboard)
            }
        }
    }
}
