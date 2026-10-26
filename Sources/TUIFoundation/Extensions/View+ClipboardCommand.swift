//  🖥️ TUI — A Terminal UI framework for Swift
//  View+ClipboardCommand.swift
//
//  The modifier every clipboard command is: a handler for SwiftUI's ⌘C, ⌘X or
//  ⌘V on the focus path, and for a bracketed paste.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

extension View {
    /// The focus-path modifier a clipboard command is: a command-stage
    /// handler for SwiftUI's ⌘`key`, resolved through the environment's
    /// ``EnvironmentValues/commandKey`` where the view renders, and — for
    /// the paste — for a bracketed paste too.
    ///
    /// - Parameters:
    ///   - key: The letter SwiftUI binds the command to with ⌘.
    ///   - declares: Which pastes the command takes, answered without running
    ///   it — a paste command's types, asked of the clipboard's before it is
    ///   read (`InputHandler.acceptsPaste(ofMIMEType:)`). `nil` declares none.
    ///   - perform: Given the key event and the clipboard, answers whether
    ///     the command took the key.
    func clipboardCommand(
        _ key: KeyEquivalent, declares: ((KeyEvent) -> Bool)? = nil,
        perform: @escaping (KeyEvent, ClipboardAccess) -> Bool
    ) -> FocusPathModifier<Self> {
        let takesPaste = key == "v"
        return FocusPathModifier(content: self, stage: .command, declares: declares) { context in
            let chord = KeyboardShortcut(key, modifiers: .command)
                .resolved(commandKey: context.environment.commandKey)?.trigger
            var clipboard = context.environment.clipboardAccess
            clipboard.typed = clipboard.typed ?? context.environment.typedClipboard
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
