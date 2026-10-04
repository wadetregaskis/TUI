//  🖥️ TUIkit — Terminal UI Kit for Swift
//  View+Transfer.swift
//
//  SwiftUI's Transferable-era clipboard modifiers: `copyable`, `cuttable` and
//  `pasteDestination`.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

/// The payloads need no `Transferable` conformance, as `draggable(_:)`'s need
/// none: CoreTransferable is Apple-only, and a terminal's clipboard holds text.
/// A copy writes each value's text (a string, or its description) and keeps
/// the values, so a paste in this app gets them back; text copied elsewhere
/// pastes as a `String`, or as a `LosslessStringConvertible` value read from
/// it. See ``TypedClipboard``.
extension View {
    /// Specifies a list of items to copy in response to the Copy command (⌘C,
    /// resolved through ``EnvironmentValues/commandKey``) while this view
    /// holds the focus — mirrors SwiftUI's `copyable(_:)`.
    ///
    /// - Parameter payload: The items to copy, evaluated at the copy.
    /// - Returns: A view that copies `payload` on the Copy command.
    public func copyable<T>(_ payload: @autoclosure @escaping () -> [T]) -> some View {
        clipboardCommand("c") { _, clipboard in
            clipboard.copy(payload())
            return true
        }
    }

    /// Specifies an action that removes items and puts them on the clipboard
    /// in response to the Cut command (⌘X) — mirrors SwiftUI's
    /// `cuttable(for:action:)`.
    ///
    /// - Parameters:
    ///   - payloadType: The type of the items cut.
    ///   - action: Removes the items, returning what was removed.
    /// - Returns: A view that cuts on the Cut command.
    public func cuttable<T>(for payloadType: T.Type = T.self, action: @escaping () -> [T]) -> some View {
        clipboardCommand("x") { _, clipboard in
            clipboard.copy(action())
            return true
        }
    }

    /// Specifies an action that receives pasted items, in response to the
    /// Paste command (⌘V, or the terminal's own paste) — mirrors SwiftUI's
    /// `pasteDestination(for:action:validator:)`.
    ///
    /// The command triggers only when the clipboard's content can be had as
    /// `T` and `validator` keeps some of it.
    ///
    /// - Parameters:
    ///   - payloadType: The type of the items pasted.
    ///   - action: Receives the pasted items.
    ///   - validator: Filters the items before `action` sees them. An empty
    ///     result keeps the command from triggering.
    /// - Returns: A view that pastes on the Paste command.
    public func pasteDestination<T>(
        for payloadType: T.Type = T.self, action: @escaping ([T]) -> Void,
        validator: @escaping ([T]) -> [T] = { $0 }
    ) -> some View {
        clipboardCommand("v") { event, clipboard in
            let text: String?
            if case .paste(let pasted) = event.key { text = pasted } else { text = clipboard.read() }
            guard let text, !text.isEmpty,
                let items = clipboard.paste(text, as: T.self)
            else { return false }
            let kept = validator(items)
            guard !kept.isEmpty else { return false }
            action(kept)
            return true
        }
    }
}
